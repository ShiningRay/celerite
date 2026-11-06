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
    "engine" => RUBY_ENGINE,
    "engine_version" => RUBY_ENGINE_VERSION,
    "rubygems_version" => Gem::VERSION,
    "ruby_revision" => RUBY_REVISION.to_s,
    "platform" => bridge_platform_string,
    "ruby_exe" => RbConfig.ruby,
    "gem_paths" => Gem.path,
    "default_gem_dir" => Gem.default_dir,
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

def serialize_source(source)
  type = source.class.name.split("::").last # Rubygems / Git / Path / Plugin / Metadata
  result = { "type" => type }
  if source.respond_to?(:remotes) && !source.remotes.empty?
    result["remotes"] = source.remotes.map(&:to_s)
  elsif source.respond_to?(:uri)
    result["remote"] = source.uri.to_s
  end
  %w[branch tag ref glob submodules].each do |key|
    value = source.options[key] if source.respond_to?(:options)
    result[key] = value if value
  end
  result
end

def bridge_dispatch(id, op, payload)
  result = case op
           when "ping"          then { "proto" => BRIDGE_PROTO, "ruby" => RUBY_VERSION }
           when "ruby_environment" then op_ruby_environment(payload)
           when "evaluate_gemfile" then op_evaluate_gemfile(payload)
           when "bundler_cache_file" then op_bundler_cache_file(payload)
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
