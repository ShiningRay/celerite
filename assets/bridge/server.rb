# frozen_string_literal: true

# Celerite Ruby compatibility bridge — JSON Lines server.
#
# Architecture contract (docs/architecture.md §2.2): a short-lived, controlled
# Ruby subprocess implementing a versioned JSON Lines protocol. Each request
# carries a protocol version, request id, op and payload; responses are either
# structured results or structured errors — stderr/stdout Ruby text is never
# parsed back.
#
# Protocol v1 request:  {"proto":1,"id":N,"op":"...","payload":{...}}
# Protocol v1 response: {"proto":1,"id":N,"ok":true,"result":{...}}
#                       {"proto":1,"id":N,"ok":false,"error":{"class":..,"message":..}}
#
# The bridge runs the Gemfile through the real Bundler::Dsl so arbitrary Ruby
# DSL semantics match the reference exactly. Which Bundler is loaded is chosen
# by the caller via $LOAD_PATH (CELERITE_REFERENCE_BUNDLER_LIB).

require "json"
require "digest"
require "rbconfig"

BRIDGE_PROTO = 1

def bridge_emit(response)
  $stdout.puts JSON.generate(response)
  $stdout.flush
end

def bridge_error(id, klass, message)
  bridge_emit("proto" => BRIDGE_PROTO, "id" => id, "ok" => false,
              "error" => { "class" => klass, "message" => message })
end

def bridge_platform_string
  require "rubygems/platform"
  Gem::Platform.local.to_s
end

def op_ruby_environment(_payload)
  require "rubygems"
  {
    "ruby_version" => RUBY_VERSION,
    "ruby_description" => RUBY_DESCRIPTION,
    "ruby_env_line" => "#{RUBY_VERSION}p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE} revision #{RUBY_REVISION}) [#{Gem::Platform.local}]",
    "engine" => RUBY_ENGINE,
    "engine_version" => RUBY_ENGINE_VERSION,
    "rubygems_version" => Gem::VERSION,
    "ruby_revision" => RUBY_REVISION.to_s,
    "platform" => bridge_platform_string,
    "ruby_exe" => RbConfig.ruby,
    "gem_paths" => (ENV["GEM_PATH"] ? ENV["GEM_PATH"].split(Gem.path_separator) : Gem.path),
    "default_gem_dir" => (ENV["GEM_HOME"] || Gem.default_dir),
    "user_gem_dir" => (Gem.user_dir rescue nil),
    "loaded_bundler_version" => (defined?(Bundler) ? Bundler::VERSION : (Gem.loaded_specs["bundler"]&.version.to_s)),
  }
end

# Loads Bundler from the requested load path (or whatever `ruby` resolves),
# evaluates the Gemfile with the real Bundler::Dsl, and serializes the
# evaluation results for the native core.
def op_evaluate_gemfile(payload)
  gemfile = payload["gemfile"]
  raise ArgumentError, "missing gemfile path" unless gemfile

  # Pin the reference Bundler when requested (isolated environments would
  # otherwise fall back to the default gem). The load path wins because gem
  # activation cannot see installed gems outside an isolated GEM_PATH.
  if lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]
    $LOAD_PATH.unshift(lib) unless lib.empty?
  elsif version = ENV["CELERITE_REFERENCE_BUNDLER_VERSION"]
    gem "bundler", version unless version.empty?
  end
  require "bundler"
  require "bundler/dsl"

  builder = Bundler::Dsl.new
  contents = File.read(gemfile)
  builder.eval_gemfile(gemfile, contents)

  deps = builder.dependencies.map do |dep|
    source = dep.source
    {
      "name" => dep.name,
      "requirements" => dep.requirement.as_list,
      "groups" => dep.groups.map(&:to_s),
      "platforms" => dep.platforms.map(&:to_s),
      "autorequire" => dep.autorequire,
      "force_ruby_platform" => dep.force_ruby_platform,
      "gemspec_dev_dep" => !!dep.gemspec_dev_dep?,
      "source" => source ? serialize_source(source) : nil,
    }
  end

  {
    "gemfile" => gemfile,
    "dependencies" => deps,
    "sources" => builder.instance_variable_get(:@sources).all_sources.map { |s| serialize_source(s) },
    "ruby" => builder.instance_variable_get(:@ruby_version)&.to_s,
    "bundler_version" => Bundler::VERSION,
    "gemfile_sha256" => Digest::SHA256.hexdigest(contents),
  }
end

def op_bundler_cache_file(payload)
  require "bundler"
  version = payload["version"]
  version = Bundler::VERSION if version.nil? || version.empty?
  spec = Gem::Specification.find_by_name("bundler", version)
  { "path" => spec.cache_file, "exists" => File.exist?(spec.cache_file) }
rescue Gem::LoadError, Gem::MissingSpecError, Gem::MissingSpecVersionError
  # Isolated GEM_PATH: fall back to the load-path-provided gem (the running
  # Bundler), matching how the reference's metadata source finds it.
  if lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]
    # lib = <repository>/gems/bundler-<version>/lib; the spec cache file lives
    # at <repository>/cache/bundler-<version>.gem
    repository = File.expand_path("../../..", lib)
    cache = File.join(repository, "cache", "bundler-#{version}.gem")
    { "path" => cache, "exists" => File.exist?(cache), "lib_env" => lib }
  else
    { "path" => nil, "exists" => false }
  end
end

# Unmarshal the specification of a .gem file and serialize the fields the
# native installer needs (pinned: Gem::Package spec fields).
def op_read_gem_spec(payload)
  require "rubygems/package"
  path = payload["path"]
  spec = Gem::Package.new(path).spec
  {
    "name" => spec.name,
    "version" => spec.version.to_s,
    "platform" => spec.platform.to_s,
    "full_name" => spec.full_name,
    "executables" => spec.executables,
    "bindir" => spec.bindir,
    "required_ruby_version" => spec.required_ruby_version.to_s,
    "required_rubygems_version" => spec.required_rubygems_version.to_s,
    "extensions" => spec.extensions,
    "date" => (spec.date.to_s if spec.respond_to?(:date)),
    "license" => (spec.license if spec.respond_to?(:license)),
    "licenses" => (spec.licenses if spec.respond_to?(:licenses)),
    "dependencies" => spec.runtime_dependencies.map { |d|
      { "name" => d.name, "type" => d.type.to_s, "requirements" => d.requirement.as_list }
    },
  }
end

# Write the Marshal'd specification of an installed gem (specifications/*.gemspec)
# the way RubyGems does, given the extracted gem directory.
def op_write_installed_spec(payload)
  require "rubygems/package"
  require "fileutils"
  gem_path = payload["gem_path"]       # cache/<name>-<version>.gem
  destination = payload["destination"] # specifications/<full_name>.gemspec
  spec = Gem::Package.new(gem_path).spec
  # Recording the install path keeps parity with RubyGems-installed specs
  spec.full_gem_path = payload["gem_dir"] if payload["gem_dir"]
  FileUtils.mkdir_p(File.dirname(destination))
  # RubyGems writes Ruby-format stub specifications (not Marshal)
  File.write(destination, spec.to_ruby_for_cache)
  {
    "name" => spec.name,
    "full_name" => spec.full_name,
    "executables" => spec.executables,
    "bindir" => spec.bindir,
    "extensions" => spec.extensions,
  }
end

# Build native extensions with the reference Ruby/RubyGems toolchain
# (architecture §2.1: extensions run through the Ruby toolchain, not native code).
def op_build_extension(payload)
  require "rubygems/ext"
  require "rubygems/package"
  require "rubygems/user_interaction"
  require "fileutils"
  # Builder output would corrupt the JSON Lines protocol on stdout; silence it
  Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
  gem_dir = payload["gem_dir"]
  destination = payload["destination"] # extensions/<platform>/<abi>/<full_name>
  # The payload may not contain a .gemspec; load the spec from the cached .gem
  spec = if payload["gem_path"] && File.exist?(payload["gem_path"])
    Gem::Package.new(payload["gem_path"]).spec
  else
    Gem::Specification.load(File.join(gem_dir, "#{payload["name"]}.gemspec"))
  end
  raise "gemspec not found in #{gem_dir}" unless spec
  gem_build_complete = File.join(destination, "gem.build_complete")
  FileUtils.mkdir_p(destination)
  spec.full_gem_path = gem_dir
  spec.extension_dir = destination
  Gem::Ext::Builder.new(spec).build_extensions
  File.write(gem_build_complete, "")
  { "built" => spec.extensions, "complete" => gem_build_complete }
rescue StandardError => e
  { "error" => e.message, "backtrace" => e.backtrace.first(4) }
end

# Load the gemspec of a directory source (path gems, git checkouts).
def op_load_gemspec_dir(payload)
  require "rubygems/specification"
  dir = payload["dir"].tr("\\", "/")
  glob = payload["glob"] || "{,*}.gemspec"
  candidates = Dir.glob(File.join(dir, glob)).sort
  raise "no gemspec in #{dir}" if candidates.empty?
  spec = Gem::Specification.load(candidates.first)
  raise "invalid gemspec in #{dir}" unless spec
  {
    "name" => spec.name,
    "version" => spec.version.to_s,
    "platform" => spec.platform.to_s,
    "full_name" => spec.full_name,
    "executables" => spec.executables,
    "bindir" => spec.bindir,
    "required_ruby_version" => spec.required_ruby_version.to_s,
    "required_rubygems_version" => spec.required_rubygems_version.to_s,
    "extensions" => spec.extensions,
    "dependencies" => spec.runtime_dependencies.map { |d|
      { "name" => d.name, "type" => d.type.to_s, "requirements" => d.requirement.as_list }
    },
  }
end

# Execute a plugin lifecycle hook through the reference Bundler::Plugin API
# (architecture §2.2: plugin hooks are Ruby code, executed by the bridge).
# payload: event, plugins_root (dir holding the plugins index), context (hash).
def op_exec_plugin_hook(payload)
  require "bundler"
  require "bundler/plugin"
  require "yaml"
  event = payload["event"].to_s
  index_path = payload["index_path"].to_s
  return { "fired" => false, "reason" => "no plugin index" } unless File.exist?(index_path)

  index = YAML.safe_load(File.read(index_path), permitted_classes: [Symbol], aliases: true) || {}
  load_paths = index["load_paths"] || {}
  hook_plugins = (index["hooks"] || {})[event] || []
  return { "fired" => false, "reason" => "no plugins for event" } if hook_plugins.empty?

  loaded = []
  plugin_paths = index["plugin_paths"] || {}
  hook_plugins.each do |name|
    paths = load_paths[name]
    if paths.is_a?(Array)
      paths.each { |p| $LOAD_PATH.unshift(p) unless $LOAD_PATH.include?(p) }
    end
    begin
      # Reference entry point: each plugin ships a root plugins.rb
      entry = plugin_paths[name] ? File.join(plugin_paths[name].to_s, "plugins.rb") : name.to_s.tr("-", "/")
      require entry
    rescue LoadError, StandardError => e
      return { "fired" => false, "reason" => "plugin #{name} failed to load: #{e.message}" }
    end
    loaded << name
  end

  # plugins.rb (or its lib) registered hooks through the reference
  # Bundler::Plugin::API (global registry). Bundler::Plugin.hook gates on
  # its global index; for project-local plugins we invoke the registered
  # blocks directly (same objects the reference would call).
  hooks = Bundler::Plugin.instance_variable_get(:@hooks_by_event) || {}
  blocks = hooks[event] || []
  context = payload["context"] || {}
  blocks.each { |blk| blk.call(context) }
  { "fired" => blocks.any?, "plugins" => loaded }
end

def serialize_source(source)
  type = source.class.name.split("::").last # Rubygems / Git / Path / Plugin / Metadata
  result = { "type" => type }
  if source.respond_to?(:remotes) && !source.remotes.empty?
    result["remotes"] = source.remotes.map(&:to_s)
  elsif source.respond_to?(:uri)
    result["remote"] = source.uri.to_s
  elsif source.respond_to?(:path) && source.path
    # Path/Gemspec sources expose their location via #path
    result["remote"] = source.path.to_s
  end
  if source.respond_to?(:options) && source.options["name"]
    result["name"] = source.options["name"]
  elsif source.respond_to?(:name) && source.name && source.name.to_s != ""
    result["name"] = source.name.to_s
  end
  %w[branch tag ref glob submodules cooldown].each do |key|
    value = source.options[key] if source.respond_to?(:options)
    result[key] = value if value
  end
  if source.respond_to?(:remote_cooldowns) && source.remote_cooldowns && !source.remote_cooldowns.empty?
    result["remote_cooldowns"] = source.remote_cooldowns
  end
  result
end

def bridge_dispatch(id, op, payload)
  result = case op
           when "ping"          then { "proto" => BRIDGE_PROTO, "ruby" => RUBY_VERSION }
           when "ruby_environment" then op_ruby_environment(payload)
           when "evaluate_gemfile" then op_evaluate_gemfile(payload)
           when "bundler_cache_file" then op_bundler_cache_file(payload)
           when "read_gem_spec" then op_read_gem_spec(payload)
           when "write_installed_spec" then op_write_installed_spec(payload)
           when "build_extension" then op_build_extension(payload)
           when "load_gemspec_dir" then op_load_gemspec_dir(payload)
           when "exec_plugin_hook" then op_exec_plugin_hook(payload)
           else
             return bridge_error(id, "UnknownOp", "unknown bridge op #{op.inspect}")
           end
  bridge_emit("proto" => BRIDGE_PROTO, "id" => id, "ok" => true, "result" => result)
rescue Exception => e # rubocop:disable Lint/RescueException — bridge boundary: everything is reported, nothing escapes
  bridge_error(id, e.class.name.to_s, e.message.to_s)
end

loop do
  line = $stdin.gets
  break if line.nil?

  line = line.strip
  next if line.empty?

  request = JSON.parse(line)
  id = request["id"]
  unless request["proto"] == BRIDGE_PROTO
    bridge_error(id, "ProtocolError", "unsupported proto #{request["proto"].inspect}")
    next
  end
  bridge_dispatch(id, request["op"], request["payload"] || {})
end
