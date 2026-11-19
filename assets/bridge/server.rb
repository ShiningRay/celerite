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

def bridge_error(id, klass, message, status = nil)
  error = { "class" => klass, "message" => message }
  error["status"] = status if status
  bridge_emit("proto" => BRIDGE_PROTO, "id" => id, "ok" => false, "error" => error)
end

def bridge_platform_string
  require "rubygems/platform"
  Gem::Platform.local.to_s
end

# Chooses which Bundler this process loads. The caller normally passes
# CELERITE_REFERENCE_BUNDLER_LIB (the reference release's lib dir), which wins
# because `gem` activation cannot see gems inside an isolated GEM_PATH. When
# only a version is requested, activate it through RubyGems; if the ambient
# GEM_PATH hides the default gem dir (a user-set GEM_PATH does exactly that),
# fall back to the release's own lib dir layout, which is what the reference
# `bundle` executable loads from (bundler/exe/bundle requires "bundler").
def bridge_activate_bundler
  if lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]
    $LOAD_PATH.unshift(lib) unless lib.empty?
    return
  end

  version = ENV["CELERITE_REFERENCE_BUNDLER_VERSION"]
  return if version.nil? || version.empty?

  begin
    gem "bundler", version
  rescue Gem::LoadError
    candidate = File.join(Gem.default_dir, "gems", "bundler-#{version}", "lib")
    raise unless File.directory?(candidate)

    $LOAD_PATH.unshift(candidate)
  end
end

def op_ruby_environment(_payload)
  require "rubygems"
  env = {
    "ruby_version" => RUBY_VERSION,
    "ruby_description" => RUBY_DESCRIPTION,
    "ruby_env_line" => "#{RUBY_VERSION}p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE} revision #{RUBY_REVISION}) [#{Gem::Platform.local}]",
    "engine" => RUBY_ENGINE,
    "engine_version" => RUBY_ENGINE_VERSION,
    "rubygems_version" => Gem::VERSION,
    "ruby_revision" => RUBY_REVISION.to_s,
    "patchlevel" => RUBY_PATCHLEVEL.to_s,
    "platform" => bridge_platform_string,
    "ruby_exe" => RbConfig.ruby,
    # `Bundler::Env#report` prints `Gem.path` (env.rb:73), which appends the
    # default gem dir when a user-set GEM_PATH omits it — splitting GEM_PATH
    # verbatim would drop that entry.
    "gem_paths" => Gem.path,
    # `Gem.default_path` is RubyGems' built-in search path: unlike `Gem.path`
    # it ignores a user-set GEM_PATH, which is what `bundle exec` needs when it
    # looks for the bundler gem it must load in the child (exec.rb:59 injects
    # its own `lib` directory regardless of GEM_PATH).
    "default_path" => Gem.default_path,
    "default_gem_dir" => (ENV["GEM_HOME"] || Gem.default_dir),
    "user_gem_dir" => (Gem.user_dir rescue nil),
    # `Bundler::Env#report` prints `Gem.bindir` (env.rb:78) and the directory
    # of `Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE` (env.rb:74). Neither is
    # derivable portably from Crystal: `Gem.bindir` reports RbConfig's bindir
    # when the install dir is the default gem dir, and the system-wide config
    # path is RubyGems' own build-time constant (forward slashes on Windows).
    "gem_bindir" => (Gem.bindir rescue nil),
    "system_config_dir" => (File.dirname(Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE) rescue nil),
    "loaded_bundler_version" => (defined?(Bundler) ? Bundler::VERSION : (Gem.loaded_specs["bundler"]&.version.to_s)),
  }
  # `Bundler::Env` prints the OpenSSL rows only when OpenSSL is already loaded
  # in the reporting process (env.rb:106-112 guards each row with `defined?`).
  # Deliberately do not `require "openssl"` here: `bundle env` without an
  # externally loaded OpenSSL prints no rows, and the differential harness
  # compares that exact output.
  env["openssl_compiled"] = (defined?(OpenSSL) ? OpenSSL::OPENSSL_VERSION : nil)
  env["openssl_loaded"] = (defined?(OpenSSL) ? OpenSSL::OPENSSL_LIBRARY_VERSION : nil)
  env["openssl_cert_file"] = (defined?(OpenSSL::X509) ? OpenSSL::X509::DEFAULT_CERT_FILE : nil)
  env["openssl_cert_dir"] = (defined?(OpenSSL::X509) ? OpenSSL::X509::DEFAULT_CERT_DIR : nil)
  env
end

# Loads Bundler from the requested load path (or whatever `ruby` resolves),
# evaluates the Gemfile with the real Bundler::Dsl, and serializes the
# evaluation results for the native core.
def op_evaluate_gemfile(payload)
  gemfile = payload["gemfile"]
  raise ArgumentError, "missing gemfile path" unless gemfile

  bridge_activate_bundler
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

  ruby_version = builder.instance_variable_get(:@ruby_version)

  {
    "gemfile" => gemfile,
    "dependencies" => deps,
    "sources" => builder.instance_variable_get(:@sources).all_sources.map { |s| serialize_source(s) },
    "ruby" => ruby_version&.to_s,
    # `to_s` omits the patchlevel; expose the structured declaration so
    # Celerite can validate Gemfile `ruby ..., patchlevel:/engine:` options.
    "ruby_version" => ruby_version&.versions&.first,
    "ruby_patchlevel" => ruby_version&.patchlevel,
    "ruby_engine" => ruby_version&.engine,
    "ruby_engine_version" => ruby_version&.engine_versions&.first,
    "bundler_version" => Bundler::VERSION,
    "gemfile_sha256" => Digest::SHA256.hexdigest(contents),
  }
end

# Absolute paths of the `.gemspec` files loaded by `gemspec` directives in the
# Gemfile, in DSL order (reference: `Bundler::Dsl#gemspecs.map(&:loaded_from)`).
def op_gemspec_paths(payload)
  gemfile = payload["gemfile"]
  raise ArgumentError, "missing gemfile path" unless gemfile

  bridge_activate_bundler
  require "bundler"
  require "bundler/dsl"

  dsl = Bundler::Dsl.new
  dsl.eval_gemfile(gemfile, File.read(gemfile))
  { "gemspecs" => dsl.gemspecs.map(&:loaded_from) }
end

def op_bundler_cache_file(payload)
  require "bundler"
  version = payload["version"]
  version = Bundler::VERSION if version.nil? || version.empty?
  spec = begin
    Gem::Specification.find_by_name("bundler", version)
  rescue Gem::LoadError, Gem::MissingSpecError, Gem::MissingSpecVersionError
    nil
  end
  if spec && File.exist?(spec.cache_file)
    return { "path" => spec.cache_file, "exists" => true }
  end
  # An isolated GEM_PATH hides the default gem dir from Gem::Specification
  # (GEM_PATH replaces the default path), but the reference still records the
  # running Bundler's checksum from its cache file in Gem.default_dir.
  default_cache = File.join(Gem.default_dir, "cache", "bundler-#{version}.gem")
  return { "path" => default_cache, "exists" => true } if File.exist?(default_cache)
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
# Every gem RubyGems can see for the running interpreter (system dirs plus
# GEM_HOME/GEM_PATH). Used by `install --local` / `--prefer-local`; the
# reference equivalent is `Bundler.rubygems.loaded_specs` /
# `Gem::Specification.to_a`. Errors are deliberately not rescued: a broken
# gem environment must surface, not be silently treated as empty.
def op_installed_specs(payload)
  # `dir` lets the caller add the gems installed into this project's bundle path
  # (`<install root>/specifications`). Bundler's `sources.local_only!` sees them
  # because `bundle` rewires Gem.path to the bundle path; a bare bridge process
  # does not, so we read that directory explicitly.
  extra_dir = payload && payload["dir"]
  # Ruby's Dir.glob on Windows treats a backslash as an escape, so a native
  # path never matches: normalize the separators first.
  extra_dir = extra_dir.tr("\\", "/") if extra_dir
  entries = Gem::Specification.to_a.map { |spec| [spec, nil] }
  if extra_dir && File.directory?(extra_dir)
    Dir[File.join(extra_dir, "*.gemspec")].sort.each do |path|
      spec = begin
        Gem::Specification.load(path)
      rescue StandardError, ScriptError
        nil
      end
      entries << [spec, extra_dir] if spec
    end
  end
  entries.uniq { |(spec, _root)| spec.full_name }.map do |(spec, root)|
    {
      "name" => spec.name,
      "version" => spec.version.to_s,
      "platform" => spec.platform.to_s,
      "dependencies" => spec.runtime_dependencies.map { |d|
        { "name" => d.name, "requirements" => d.requirement.as_list }
      },
      "required_ruby_version" => spec.required_ruby_version.to_s,
      "required_rubygems_version" => spec.required_rubygems_version.to_s,
      "full_gem_path" => root ? File.join(File.dirname(root), "gems", spec.full_name) : spec.full_gem_path,
      "from_dir" => root ? true : false,
    }
  end
end

# `Bundler::CLI::Common.default_gem_spec` (cli/common.rb:98-101): the last
# installed spec for the name, only when it is a default gem. `bundle open`
# appends it to the regex candidates so `bundle open json` can offer the
# interpreter's default gem alongside the bundled json_pure.
def op_default_gem_spec(payload)
  name = payload["name"]
  spec = Gem::Specification.find_all_by_name(name).last
  return nil unless spec && spec.default_gem?
  {
    "name" => spec.name,
    "version" => spec.version.to_s,
    "full_gem_path" => spec.full_gem_path,
  }
end

def op_read_gem_spec(payload)
  require "rubygems/package"
  path = payload["path"]
  spec = Gem::Package.new(path).spec
  metadata = spec.respond_to?(:metadata) ? spec.metadata : {}
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
    "metadata" => metadata,
    "homepage" => (spec.homepage if spec.respond_to?(:homepage)),
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
  # RubyGems stamps the RubyGems version that performed the install; without
  # it the generated stub lacks `s.installed_by_version` (reference parity).
  spec.installed_by_version = Gem::VERSION if spec.respond_to?(:installed_by_version=)
  FileUtils.mkdir_p(File.dirname(destination))
  # 2.7.2 also unpacks the installed plugin gem under `.bundle/plugin/gems`
  # (`Gem::Installer#unpack`), so mirror that when the caller asks for it.
  if payload["unpack"] == "true" && (gem_dir = payload["gem_dir"])
    FileUtils.rm_rf(gem_dir)
    FileUtils.mkdir_p(gem_dir)
    Gem::Package.new(gem_path).extract_files(gem_dir)
  end
  # RubyGems writes Ruby-format stub specifications (not Marshal)
  File.binwrite(destination, spec.to_ruby_for_cache)
  {
    "name" => spec.name,
    "full_name" => spec.full_name,
    "executables" => spec.executables,
    "bindir" => spec.bindir,
    "extensions" => spec.extensions,
  }
end

# Generate RubyGems-compatible executable wrappers (app script + Windows .bat
# stub) exactly like `Gem::Installer#generate_bin_script`, so the installed
# bin tree matches the reference byte-for-byte after path normalization.
def op_generate_bin_stubs(payload)
  require "rubygems/installer"
  require "rubygems/package"
  require "fileutils"
  gem_path = payload["gem_path"]
  destination = payload["destination"] # <install_root>/bin
  gem_dir = payload["gem_dir"]
  spec = Gem::Package.new(gem_path).spec
  spec.full_gem_path = gem_dir if gem_dir
  FileUtils.mkdir_p(destination)
  installer = Gem::Installer.at(gem_path,
                                install_dir: File.dirname(destination),
                                bin_dir: destination,
                                wrappers: true,
                                generate_binstubs: false,
                                ignore_dependencies: true,
                                env_shebang: true,
                                document: [])
  spec.bindir = "bin" if spec.bindir.nil? || spec.bindir.empty?
  installer.instance_variable_set(:@spec, spec)
  written = []
  spec.executables.each do |executable|
    script_path = File.join(destination, installer.send(:formatted_program_filename, executable))
    File.binwrite(script_path, installer.send(:app_script_text, executable))
    File.chmod(script_path, 0o755) unless Gem.win_platform?
    if Gem.win_platform?
      bat_path = "#{script_path}.bat"
      File.binwrite(bat_path, installer.send(:windows_stub_script, destination, executable))
    end
    written << executable
  end
  { "executables" => written }
rescue StandardError => e
  { "error" => e.message, "backtrace" => e.backtrace.first(4) }
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
  if target_rbconfig = payload["target_rbconfig"]
    Gem.set_target_rbconfig(target_rbconfig)
  end
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
  build_args = payload["build_args"] ? payload["build_args"].to_s.split(" ") : []
  Gem::Ext::Builder.new(spec, build_args).build_extensions
  File.write(gem_build_complete, "")
  { "built" => spec.extensions, "complete" => gem_build_complete }
rescue StandardError => e
  # Return the full backtrace: the CLI renders the real RubyGems build stack
  # (never a synthesized Bundler stack; see the M7(5) install-failure note).
  { "error_class" => e.class.name, "error" => e.message, "backtrace" => (e.backtrace || []) }
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
# Hook argument for `after-install`. The reference passes the
# `Bundler::ParallelInstaller::SpecInstallation` whose install just finished,
# so plugin blocks can read `#name`, `#full_name` and `#state`
# (`parallel_installer.rb:8-59`). Only those readers are reproduced.
class PluginHookSpec
  attr_reader :name, :full_name

  def initialize(name, full_name)
    @name = name
    @full_name = full_name
  end

  def state
    :installed
  end
end

def op_exec_plugin_hook(payload)
  require "bundler"
  require "bundler/plugin"
  require "yaml"
  event = payload["event"].to_s
  index_path = payload["index_path"].to_s
  return { "status" => "skipped", "reason" => "no plugin index" } unless File.exist?(index_path)

  index = YAML.safe_load(File.read(index_path), permitted_classes: [Symbol], aliases: true) || {}
  load_paths = index["load_paths"] || {}
  hook_plugins = (index["hooks"] || {})[event] || []
  return { "status" => "skipped", "reason" => "no plugins for event" } if hook_plugins.empty?

  loaded = []
  missing = []
  plugin_paths = index["plugin_paths"] || {}
  hook_plugins.each do |name|
    paths = load_paths[name]
    if paths.is_a?(Array)
      absent = paths.map(&:to_s).reject { |p| File.directory?(p) }
      unless absent.empty?
        # Reference load_plugin warns for THIS plugin and returns; the
        # remaining plugins are still loaded and their hooks still run
        # (bundler/plugin.rb L237-239 and L345-381).
        missing << { "plugin" => name.to_s, "paths" => absent }
        next
      end
      paths.each { |p| $LOAD_PATH.unshift(p.to_s) unless $LOAD_PATH.include?(p.to_s) }
    end
    begin
      # Reference entry point: each plugin ships a root plugins.rb
      entry = plugin_paths[name] ? File.join(plugin_paths[name].to_s, "plugins.rb") : name.to_s.tr("-", "/")
      require entry
    rescue LoadError, StandardError => e
      return { "status" => "load_failed", "plugin" => name.to_s, "message" => e.message.to_s, "missing" => missing }
    end
    loaded << name.to_s
  end

  # plugins.rb (or its lib) registered hooks through the reference
  # Bundler::Plugin::API (global registry). Bundler::Plugin.hook gates on
  # its global index; for project-local plugins we invoke the registered
  # blocks directly (same objects the reference would call).
  # Mirror of `Bundler::ParallelInstaller::SpecInstallation` for the parts
  # plugin hooks read (`parallel_installer.rb:8-59` exposes :name, :full_name,
  # :state and :spec). The full reference object also carries the resolved
  # specification and dependency edges, which plugins may inspect; that part
  # is not reproduced (declared difference).
  hooks = Bundler::Plugin.instance_variable_get(:@hooks_by_event) || {}
  blocks = hooks[event] || []
  context = if payload["spec_name"]
    PluginHookSpec.new(payload["spec_name"].to_s, payload["spec_full_name"].to_s)
  else
    payload["context"] || {}
  end
  begin
    blocks.each { |blk| blk.call(context) }
  rescue StandardError => e
    return { "status" => "hook_failed", "plugin" => (loaded.first || hook_plugins.first.to_s), "message" => e.message.to_s, "missing" => missing }
  end
  { "status" => "ok", "plugins" => loaded, "missing" => missing }
end

# Specs exposed by a plugin source: re-evaluates the Gemfile (the bridge has
# no persistent source handles), finds the `Bundler::Plugin::API::Source` with
# the same `uri`, and materializes its `specs` index
# (`plugin/api/source.rb:136`, `fetch_gemspec_files`).
def op_plugin_source_specs(payload)
  gemfile = payload["gemfile"]
  remote = payload["remote"].to_s
  raise ArgumentError, "missing gemfile path" unless gemfile

  bridge_activate_bundler
  require "bundler"
  require "bundler/dsl"

  builder = Bundler::Dsl.new
  builder.eval_gemfile(gemfile, File.read(gemfile))
  candidates = builder.dependencies.map(&:source).compact +
               builder.instance_variable_get(:@sources).all_sources
  source = candidates.uniq.find do |candidate|
    defined?(Bundler::Plugin::API::Source) &&
      candidate.is_a?(Bundler::Plugin::API::Source) &&
      candidate.uri.to_s == remote
  end
  raise ArgumentError, "plugin source not found: #{remote}" unless source

  specs = source.specs.each.map do |spec|
    {
      "name" => spec.name,
      "version" => spec.version.to_s,
      "platform" => spec.platform.to_s,
      "loaded_from" => spec.loaded_from,
      "dependencies" => spec.dependencies.map do |dep|
        { "name" => dep.name, "requirements" => dep.requirement.as_list }
      end,
    }
  end
  { "remote" => remote, "specs" => specs }
end

# Installs one spec through a plugin source's own `install` implementation
# (`plugin/api/source.rb:90`; `installer/gem_installer.rb:67-75`). The plugin
# source decides where the gem lands; the bridge only offers the bundle path
# the reference's `Bundler.bundle_path` would resolve to.
def op_plugin_source_install(payload)
  gemfile = payload["gemfile"]
  remote = payload["remote"].to_s
  full_name = payload["full_name"].to_s
  bundle_root = payload["bundle_root"].to_s
  raise ArgumentError, "missing gemfile path" unless gemfile

  bridge_activate_bundler
  require "bundler"
  require "bundler/dsl"
  require "pathname"
  # Bundler's own install path has FileUtils loaded; plugin `install` hooks
  # routinely use it without an explicit require.
  require "fileutils"

  if !bundle_root.empty?
    # `bundle_root` is the ABI install root (`<bundle>/ruby/<abi>`), the same
    # path reference `Bundler.bundle_path` exposes. Set it in memory only:
    # `set_local` would persist `BUNDLE_PATH` into the project's
    # `.bundle/config`, which the reference does not write here.
    Bundler.instance_variable_set(:@bundle_path, Pathname.new(bundle_root))
  end

  builder = Bundler::Dsl.new
  builder.eval_gemfile(gemfile, File.read(gemfile))
  candidates = builder.dependencies.map(&:source).compact +
               builder.instance_variable_get(:@sources).all_sources
  source = candidates.uniq.find do |candidate|
    defined?(Bundler::Plugin::API::Source) &&
      candidate.is_a?(Bundler::Plugin::API::Source) &&
      candidate.uri.to_s == remote
  end
  raise ArgumentError, "plugin source not found: #{remote}" unless source

  spec = source.specs.find { |candidate| candidate.full_name == full_name }
  raise ArgumentError, "plugin spec not found: #{full_name}" unless spec

  message = source.install(spec, force: false, local: false, build_args: [], previous_spec: nil)
  { "message" => message.nil? ? nil : message.to_s }
end

def serialize_source(source)
  # Plugin sources (`Bundler::Plugin::API::Source`) are not a Bundler::Source
  # subclass and their class name is the plugin's own class (e.g. `MPath`).
  # The lockfile contract keys off the declared plugin `type` and the raw
  # `uri` (`plugin/api/source.rb:41,283-295`).
  if defined?(Bundler::Plugin::API::Source) && source.is_a?(Bundler::Plugin::API::Source)
    lock_options = source.options_to_lock.each_with_object({}) do |(key, value), memo|
      memo[key.to_s] = value.to_s
    end
    return {
      "type" => "Plugin",
      "plugin_type" => source.options["type"].to_s,
      "remote" => source.uri.to_s,
      "lock_options" => lock_options,
      "name" => source.name.to_s,
    }
  end
  type = source.class.name.split("::").last # Rubygems / Git / Path / Metadata
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

# Evaluate a Gemfile through Bundler::Plugin::DSL (the reference pre-install
# pass, `Bundler::Plugin.gemfile_install`): collects `plugin "x"` declarations
# plus the inferred `bundler-source-<type>` dependencies and returns their
# names in declaration order. Errors are NOT rescued here: the bridge envelope
# carries the class/message/status the reference would exit with
# (PluginGemfileError 29, InvalidOption 15, GemfileError 4).
def op_plugin_gemfile_eval(payload)
  require "bundler"
  require "bundler/plugin"
  dsl = Bundler::Plugin::DSL.new
  dsl.eval_gemfile(payload["gemfile_path"].to_s)
  dependencies = dsl.instance_variable_get(:@dependencies) || []
  { "plugin_names" => dependencies.map(&:name) }
end

def bridge_dispatch(id, op, payload)
  result = case op
           when "ping"          then { "proto" => BRIDGE_PROTO, "ruby" => RUBY_VERSION }
           when "ruby_environment" then op_ruby_environment(payload)
           when "evaluate_gemfile" then op_evaluate_gemfile(payload)
           when "gemspec_paths"   then op_gemspec_paths(payload)
           when "bundler_cache_file" then op_bundler_cache_file(payload)
           when "read_gem_spec" then op_read_gem_spec(payload)
           when "write_installed_spec" then op_write_installed_spec(payload)
           when "generate_bin_stubs" then op_generate_bin_stubs(payload)
           when "build_extension" then op_build_extension(payload)
           when "load_gemspec_dir" then op_load_gemspec_dir(payload)
           when "exec_plugin_hook" then op_exec_plugin_hook(payload)
           when "plugin_gemfile_eval" then op_plugin_gemfile_eval(payload)
           when "plugin_source_specs" then op_plugin_source_specs(payload)
           when "plugin_source_install" then op_plugin_source_install(payload)
  when "installed_specs" then op_installed_specs(payload)
    when "default_gem_spec" then op_default_gem_spec(payload)
           else
             return bridge_error(id, "UnknownOp", "unknown bridge op #{op.inspect}")
           end
  bridge_emit("proto" => BRIDGE_PROTO, "id" => id, "ok" => true, "result" => result)
rescue Exception => e # rubocop:disable Lint/RescueException — bridge boundary: everything is reported, nothing escapes
  bridge_error(id, e.class.name.to_s, e.message.to_s, (e.status_code if e.respond_to?(:status_code)))
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
