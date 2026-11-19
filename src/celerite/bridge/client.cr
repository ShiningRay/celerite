require "json"
require "process"
require "../errors"

module Celerite
  module Bridge
    # Protocol version shared with assets/bridge/server.rb (architecture §2.2).
    PROTOCOL = 1

    class BridgeError < Error
      getter error_class : String
      # Optional `status_code` carried by the Ruby side (Bundler errors know
      # their exit status: PluginGemfileError 29, InvalidOption 15,
      # GemfileError 4). Falls back to the pre-existing default of 1.
      getter status : Int32?

      def initialize(@error_class : String, message : String, @status : Int32? = nil)
        super(message)
      end

      def status_code : Int32
        @status || 1
      end
    end

    struct RubyEnvironment
      include JSON::Serializable
      getter ruby_version : String
      getter ruby_description : String
      getter ruby_env_line : String
      getter engine : String
      getter engine_version : String
      getter rubygems_version : String
      getter ruby_revision : String
      getter patchlevel : String?
      getter platform : String
      getter ruby_exe : String
      getter gem_paths : Array(String)
      # RubyGems' built-in search path (`Gem.default_path`), which ignores a
      # user-set GEM_PATH. `bundle exec` needs it to find the bundler gem it
      # loads into the child process.
      getter default_path : Array(String)? = nil
      getter default_gem_dir : String
      getter user_gem_dir : String?
      # `Gem.bindir` / the system-wide RubyGems config directory; reported by
      # RubyGems itself because Crystal cannot reproduce them portably.
      getter gem_bindir : String? = nil
      getter system_config_dir : String? = nil
      getter loaded_bundler_version : String
      # Present only when the bridge process had OpenSSL loaded, mirroring
      # `Bundler::Env`'s `defined?(OpenSSL)` guards (env.rb:106-112).
      getter openssl_compiled : String? = nil
      getter openssl_loaded : String? = nil
      getter openssl_cert_file : String? = nil
      getter openssl_cert_dir : String? = nil
    end

    struct EvaluatedDependency
      include JSON::Serializable
      getter name : String
      getter requirements : Array(String)
      getter groups : Array(String)
      getter platforms : Array(String)
      # Bundler always array-wraps `:require` when present
      # (`Array(options["require"] || [])`, bundler/dependency.rb#autorequire
      # in 2.2/2.7/4.0) and leaves it nil when absent; symbols serialize as
      # JSON strings, `false`/empty become `[]`.
      getter autorequire : Array(String) | Nil
      getter force_ruby_platform : Bool?
      getter gemspec_dev_dep : Bool
      getter source : EvaluatedSource?
    end

    struct EvaluatedSource
      include JSON::Serializable
      getter name : String?
      getter type : String
      getter remotes : Array(String)?
      getter remote : String?
      getter branch : String?
      getter tag : String?
      getter ref : String?
      getter glob : String?
      getter submodules : Bool?
      getter cooldown : Int32?
      getter remote_cooldowns : Hash(String, Int32)?
      # Plugin sources (`Bundler::Plugin::API::Source`): the declared plugin
      # type (`source "...", type: :mpath`) and the options persisted by
      # `options_to_lock` (`plugin/api/source.rb:73`).
      getter plugin_type : String?
      getter lock_options : Hash(String, String)?
    end

    struct PluginSpecDependency
      include JSON::Serializable
      getter name : String
      getter requirements : Array(String)
    end

    struct PluginSourceSpec
      include JSON::Serializable
      getter name : String
      getter version : String
      getter platform : String
      getter loaded_from : String?
      getter dependencies : Array(PluginSpecDependency)?
    end

    struct PluginSourceSpecs
      include JSON::Serializable
      getter remote : String
      getter specs : Array(PluginSourceSpec)
    end

    # Specification fields of a .gem, extracted by the bridge (Marshal side).
    # Fields returned when writing an installed specification.
    struct WrittenSpec
      include JSON::Serializable
      getter name : String
      getter full_name : String
      getter executables : Array(String)
      getter bindir : String
      getter extensions : Array(String)
    end

    # Minimal spec identity returned by `load_gemspec_dir_specs`; the PATH
    # re-resolve judge only compares names and versions.
    struct GemSpecSummary
      include JSON::Serializable
      getter name : String
      getter version : String
      getter platform : String
      getter full_name : String
    end

    struct GemSpecInfo
      include JSON::Serializable
      getter name : String
      getter version : String
      getter platform : String
      getter full_name : String
      getter executables : Array(String)
      getter bindir : String
      getter required_ruby_version : String
      getter required_rubygems_version : String
      getter extensions : Array(String)
      getter dependencies : Array(JSON::Any)?
      getter date : String?
      getter license : String?
      getter licenses : Array(String)?
      getter metadata : Hash(String, String)?
      getter homepage : String?
    end

    struct GemfileEvaluation
      include JSON::Serializable
      getter gemfile : String
      getter dependencies : Array(EvaluatedDependency)
      getter sources : Array(EvaluatedSource)
      getter ruby : String?
      getter ruby_version : String?
      getter ruby_patchlevel : String?
      getter ruby_engine : String?
      getter ruby_engine_version : String?
      getter bundler_version : String
      getter gemfile_sha256 : String
    end

    # Client for the JSON Lines bridge server. One process per client; the
    # server stays alive across requests and exits on stdin EOF.
    class Client
      @process : Process
      @stdin : IO
      @stdout : IO
      @request_id = 0
      @mutex = Mutex.new
      getter ruby_version : String

      def initialize(ruby_exe : String? = nil, server_path : String? = nil, timeout : Time::Span = 30.seconds)
        ruby = ruby_exe || ENV["CELERITE_RUBY"]? || "ruby"
        server = server_path || Client.locate_server
        @timeout = timeout
        env = ENV.to_h
        env["CELERITE_REFERENCE_BUNDLER_VERSION"] = reference_bundler_version
        if bundler_lib = reference_bundler_lib
          env["CELERITE_REFERENCE_BUNDLER_LIB"] = bundler_lib
        end
        @process = Process.new(
          ruby,
          [server],
          input: :pipe, output: :pipe, error: :inherit,
          env: env,
        )
        @stdin = @process.input
        @stdout = @process.output
        @ruby_version = "unknown"
      end

      # The compatibility profile's reference Bundler version (docs/compat-matrix).
      private def reference_bundler_version : String
        ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
      end

      # Load path for the pinned reference Bundler (set by the differential
      # harness; gem activation is invisible inside isolated GEM_PATHs).
      private def reference_bundler_lib : String?
        ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
      end

      # Server script resolution: explicit override > CELERITE_BRIDGE_SERVER env
      # > relative to the running executable (bin/celerite -> assets/bridge).
      def self.locate_server : String
        if given = ENV["CELERITE_BRIDGE_SERVER"]?
          return given unless given.empty?
        end

        if exe = Process.executable_path
          base = File.dirname(exe)
          [
            File.join(base, "assets", "bridge", "server.rb"),
            File.join(base, "..", "assets", "bridge", "server.rb"),
          ].each do |candidate|
            return candidate if File.file?(candidate)
          end
        end

        raise Error.new("bridge server script not found; set CELERITE_BRIDGE_SERVER")
      end

      def ping : String
        result = request("ping")
        result["ruby"].as_s
      end

      def ruby_environment : RubyEnvironment
        RubyEnvironment.from_json(request("ruby_environment").to_json)
      end

      def evaluate_gemfile(path : String) : GemfileEvaluation
        GemfileEvaluation.from_json(request("evaluate_gemfile", {"gemfile" => path}).to_json)
      end

      # Specs exposed by a plugin source (`Bundler::Plugin::API::Source#specs`).
      # The bridge re-evaluates the Gemfile and returns the plugin source's
      # materialized index; used when writing the PLUGIN SOURCE lock section.
      def plugin_source_specs(gemfile : String, remote : String) : PluginSourceSpecs
        PluginSourceSpecs.from_json(
          request("plugin_source_specs", {"gemfile" => gemfile, "remote" => remote}).to_json
        )
      end

      # Runs a plugin source's own `install` implementation
      # (`plugin/api/source.rb:90`, `installer/gem_installer.rb:67-75`) and
      # returns the optional post-install message.
      def plugin_source_install(gemfile : String, remote : String, full_name : String,
                                bundle_root : String) : String?
        result = request("plugin_source_install", {
          "gemfile" => gemfile, "remote" => remote,
          "full_name" => full_name, "bundle_root" => bundle_root,
        })
        result["message"]?.try(&.as_s?)
      end

      # Absolute paths of the gemspecs loaded by Gemfile `gemspec` directives,
      # in DSL order (reference: `Bundler::Dsl#gemspecs.map(&:loaded_from)`).
      def gemspec_paths(gemfile : String) : Array(String)
        request("gemspec_paths", {"gemfile" => gemfile})["gemspecs"].as_a.map(&.as_s)
      end

      # Every gem visible to the bridge interpreter's RubyGems (system dirs
      # plus GEM_HOME/GEM_PATH). Backs `install --local` / `--prefer-local`.
      # `spec_dir` adds the project's `<install root>/specifications` directory:
      # gems installed into the bundle path are invisible to a bare RubyGems
      # process, while Bundler's local-only sources do see them.
      def installed_specs(spec_dir : String? = nil) : JSON::Any
        if dir = spec_dir
          request("installed_specs", {"dir" => dir})
        else
          request("installed_specs")
        end
      end

      def read_gem_spec(path : String) : JSON::Any
        request("read_gem_spec", {"path" => path})
      end

      # `Bundler::CLI::Common.default_gem_spec` (common.rb:98-101): the
      # interpreter's default gem for a bare name, if any. `bundle open`
      # appends it to the regex candidates so `bundle open json` can offer
      # the interpreter's own `json` next to the bundled `json_pure`.
      def default_gem_spec(name : String) : NamedTuple(
        name: String, version: String, platform: String, full_gem_path: String,
        dependencies: Array(NamedTuple(name: String, requirements: Array(String))),
        required_ruby_version: String, required_rubygems_version: String)?
        result = request("default_gem_spec", {"name" => name})
        return nil if result.raw.nil?
        dependencies = (result["dependencies"]?.try(&.as_a) || [] of JSON::Any).map do |dep|
          requirements = (dep["requirements"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
          {name: dep["name"].as_s, requirements: requirements}
        end
        {
          name:                      result["name"].as_s,
          version:                   result["version"].as_s,
          platform:                  result["platform"].as_s,
          full_gem_path:             result["full_gem_path"].as_s,
          dependencies:              dependencies,
          required_ruby_version:     result["required_ruby_version"].as_s,
          required_rubygems_version: result["required_rubygems_version"].as_s,
        }
      end

      def write_installed_spec(gem_path : String, destination : String, gem_dir : String, unpack : Bool = false) : JSON::Any
        request("write_installed_spec", {"gem_path" => gem_path, "destination" => destination, "gem_dir" => gem_dir, "unpack" => unpack ? "true" : ""})
      end

      # `spec_name`/`spec_full_name` mirror the reference hook argument: the
      # `Bundler::ParallelInstaller::SpecInstallation` of the spec whose install
      # just finished (`parallel_installer.rb:217`). The bridge hands the hook
      # block an object exposing `#name`/`#full_name`.
      def exec_plugin_hook(event : String, index_path : String,
                           spec_name : String? = nil, spec_full_name : String? = nil) : JSON::Any
        payload = {"event" => event, "index_path" => index_path} of String => String?
        payload["spec_name"] = spec_name
        payload["spec_full_name"] = spec_full_name
        # Hooks run arbitrary plugin code, exactly like the reference, so they
        # are not cut off by the RPC deadline used for fast metadata calls.
        request("exec_plugin_hook", payload, limit: nil)
      end

      # Plugin pre-install pass (`Bundler::Plugin.gemfile_install`): names the
      # Gemfile declares through `plugin "x"` or `source ..., type:`.
      def plugin_gemfile_eval(gemfile_path : String) : JSON::Any
        request("plugin_gemfile_eval", {"gemfile_path" => gemfile_path})
      end

      # Generates RubyGems-compatible executable wrappers for one installed gem.
      def generate_bin_stubs(gem_path : String, destination : String, gem_dir : String) : JSON::Any
        request("generate_bin_stubs", {"gem_path" => gem_path, "destination" => destination, "gem_dir" => gem_dir})
      end

      def load_gemspec_dir(dir : String, glob : String? = nil) : GemSpecInfo
        payload = {"dir" => dir} of String => String
        payload["glob"] = glob if glob
        GemSpecInfo.from_json(request("load_gemspec_dir", payload).to_json)
      end

      # All gemspecs a PATH source exposes under `glob` (`source/path.rb:159-179`
      # keeps the shallower gemspec when two share a name).
      def load_gemspec_dir_specs(dir : String, glob : String? = nil) : Array(GemSpecSummary)
        payload = {"dir" => dir} of String => String
        payload["glob"] = glob if glob
        Array(GemSpecSummary).from_json(request("load_gemspec_dir_specs", payload)["specs"].to_json)
      end

      def build_extension(gem_dir : String, destination : String, name : String, gem_path : String, target_rbconfig : String? = nil, build_args : Array(String)? = nil) : JSON::Any
        payload = {"gem_dir" => gem_dir, "destination" => destination, "name" => name, "gem_path" => gem_path} of String => String
        payload["target_rbconfig"] = target_rbconfig if target_rbconfig
        payload["build_args"] = build_args.join(" ") if build_args && !build_args.empty?
        request("build_extension", payload, limit: nil)
      end

      def bundler_cache_file(version : String) : String?
        result = request("bundler_cache_file", {"version" => version})
        path = result["path"].as_s?
        return nil if path.nil? || path.empty?
        result["exists"].as_bool ? path : nil
      end

      def close : Nil
        @stdin.close unless @stdin.closed?
        @process.wait unless @process.terminated?
      end

      # Long-running operations (native extension builds, plugin hooks) mirror
      # the reference, which has no RPC deadline at all: a gem that takes
      # minutes to compile must not be cut off by the 30s default. Pass
      # `limit: nil` for those; everything else keeps the safety net.
      private def request(op : String, payload : Hash(String, String) | Hash(String, String?) = {} of String => String, limit : Time::Span? = @timeout) : JSON::Any
        @mutex.synchronize do
          @request_id += 1
          id = @request_id
          line = JSON.build do |json|
            json.object do
              json.field "proto", PROTOCOL
              json.field "id", id
              json.field "op", op
              json.field "payload", payload
            end
          end
          @stdin.puts(line)
          @stdin.flush

          finish_response(id, read_response(limit))
        end
      end

      private def read_response(limit : Time::Span?) : JSON::Any
        done = Channel(JSON::Any).new(1)

        spawn(name: "bridge-reader") do
          line = @stdout.gets
          if line.nil?
            done.send(crash_response("bridge server closed the connection", "BridgeCrashed"))
          else
            begin
              done.send(JSON.parse(line))
            rescue ex
              done.send(crash_response("bridge sent non-JSON output: #{ex.message}", "ProtocolError"))
            end
          end
        end

        if limit
          select
          when response = done.receive
            response
          when timeout(limit)
            raise BridgeError.new("Timeout", "bridge request timed out after #{limit.total_seconds}s")
          end
        else
          done.receive
        end
      end

      private def crash_response(message : String, error_class : String) : JSON::Any
        text = JSON.build do |json|
          json.object do
            json.field "proto", PROTOCOL
            json.field "id", -1
            json.field "ok", false
            json.field "error" do
              json.object do
                json.field "class", error_class
                json.field "message", message
              end
            end
          end
        end
        JSON.parse(text)
      end

      private def finish_response(id : Int32, response : JSON::Any) : JSON::Any
        unless response["proto"].as_i? == PROTOCOL
          raise BridgeError.new("ProtocolError", "unsupported bridge proto #{response["proto"]?}")
        end
        unless response["id"].as_i? == id
          raise BridgeError.new("ProtocolError", "response id mismatch: expected #{id}, got #{response["id"]?}")
        end

        if response["ok"].as_bool
          response["result"]
        else
          error = response["error"]
          raise BridgeError.new(error["class"].as_s, error["message"].as_s, error["status"]?.try(&.as_i?))
        end
      end
    end
  end
end
