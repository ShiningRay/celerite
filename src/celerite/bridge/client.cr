require "json"
require "process"
require "../errors"

module Celerite
  module Bridge
    # Protocol version shared with assets/bridge/server.rb (architecture §2.2).
    PROTOCOL = 1

    class BridgeError < Error
      getter error_class : String

      def initialize(@error_class : String, message : String)
        super(message)
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
      getter platform : String
      getter ruby_exe : String
      getter gem_paths : Array(String)
      getter default_gem_dir : String
      getter user_gem_dir : String?
      getter loaded_bundler_version : String
    end

    struct EvaluatedDependency
      include JSON::Serializable
      getter name : String
      getter requirements : Array(String)
      getter groups : Array(String)
      getter platforms : Array(String)
      getter autorequire : String?
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
    end

    struct GemfileEvaluation
      include JSON::Serializable
      getter gemfile : String
      getter dependencies : Array(EvaluatedDependency)
      getter sources : Array(EvaluatedSource)
      getter ruby : String?
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

      def read_gem_spec(path : String) : JSON::Any
        request("read_gem_spec", {"path" => path})
      end

      def write_installed_spec(gem_path : String, destination : String, gem_dir : String) : JSON::Any
        request("write_installed_spec", {"gem_path" => gem_path, "destination" => destination, "gem_dir" => gem_dir})
      end

      def exec_plugin_hook(event : String, index_path : String) : JSON::Any
        request("exec_plugin_hook", {"event" => event, "index_path" => index_path})
      end

      def load_gemspec_dir(dir : String, glob : String? = nil) : GemSpecInfo
        payload = {"dir" => dir} of String => String
        payload["glob"] = glob if glob
        GemSpecInfo.from_json(request("load_gemspec_dir", payload).to_json)
      end

      def build_extension(gem_dir : String, destination : String, name : String, gem_path : String, target_rbconfig : String? = nil, build_args : Array(String)? = nil) : JSON::Any
        payload = {"gem_dir" => gem_dir, "destination" => destination, "name" => name, "gem_path" => gem_path} of String => String
        payload["target_rbconfig"] = target_rbconfig if target_rbconfig
        payload["build_args"] = build_args.join(" ") if build_args && !build_args.empty?
        request("build_extension", payload)
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

      private def request(op : String, payload : Hash(String, String) | Hash(String, String?) = {} of String => String) : JSON::Any
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

          finish_response(id, read_response)
        end
      end

      private def read_response : JSON::Any
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

        select
        when response = done.receive
          response
        when timeout(@timeout)
          raise BridgeError.new("Timeout", "bridge request timed out after #{@timeout.total_seconds}s")
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
          raise BridgeError.new(error["class"].as_s, error["message"].as_s)
        end
      end
    end
  end
end
