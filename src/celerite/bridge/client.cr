require "digest/sha256"
require "json"
require "process"
require "../errors"

module Celerite
  module Bridge
    # Protocol versions shared with assets/bridge/server.rb (architecture §2.2).
    # The server accepts every version in `PROTOCOL_MIN..PROTOCOL` and echoes
    # the request's own version, so a peer that only speaks the minimum still
    # receives an envelope it can read. `PROTOCOL` is what this client sends;
    # any response in the range is accepted, anything outside it is a
    # `ProtocolError`.
    PROTOCOL     = 2
    PROTOCOL_MIN = 1

    # Counters behind `CELERITE_BRIDGE_STATS` (M8 baseline: one process, one
    # line). The variable is off when unset, empty, or exactly "0"; any other
    # value turns it on. Counting is scoped to one `CLI.run` invocation so
    # in-process specs observe their own numbers, and the line is written by
    # the CLI exit point — see docs/compat-claims/M8-batch-bridge.md.
    module BridgeStats
      @@procs = 0
      @@rpc = 0
      @@req_bytes = 0
      @@resp_bytes = 0

      def self.enabled? : Bool
        value = ENV["CELERITE_BRIDGE_STATS"]?
        !value.nil? && !value.empty? && value != "0"
      end

      def self.begin_run : Nil
        return unless enabled?
        @@procs = 0
        @@rpc = 0
        @@req_bytes = 0
        @@resp_bytes = 0
      end

      # A bridge client spawns exactly one Ruby subprocess (`Process.new`).
      def self.record_process : Nil
        @@procs += 1 if enabled?
      end

      # `bytes` is the serialized request line including its trailing newline.
      def self.record_request(bytes : Int32) : Nil
        return unless enabled?
        @@rpc += 1
        @@req_bytes += bytes
      end

      # `bytes` is the raw response line returned by `IO#gets` (terminator
      # included); responses that never arrive are not counted.
      def self.record_response(bytes : Int32) : Nil
        @@resp_bytes += bytes if enabled?
      end

      def self.finish(io : IO) : Nil
        return unless enabled?
        io.puts "bridge: procs=#{@@procs} rpc=#{@@rpc} req_bytes=#{@@req_bytes} resp_bytes=#{@@resp_bytes}"
        io.flush
      end

      def self.procs : Int32
        @@procs
      end

      def self.rpc : Int32
        @@rpc
      end
    end

    # Per-command memo for `evaluate_gemfile`. One Celerite command evaluates
    # the same Gemfile from several sites (`check` deliberately twice: once for
    # the dependency diff, once inside the frozen branch), and every evaluation
    # is a full RPC round trip. The reference evaluates a Gemfile once per
    # process (`bundler.rb` `@definition ||=`) and reuses that definition, so a
    # command never re-evaluates an unchanged file; the cache reproduces that
    # without changing what any caller sees.
    #
    # A hit is only trusted when the bytes on disk still hash to the digest the
    # bridge reported (`gemfile_sha256`): commands rewrite the Gemfile in the
    # middle of a run (`add` appends a gem and then installs), and a size/mtime
    # key cannot tell an equal-length rewrite inside the same millisecond. The
    # cache only lives inside one `CLI.run` (see `begin_run`/`finish`).
    module EvaluationCache
      @@active = false
      @@entries = {} of String => GemfileEvaluation

      def self.begin_run : Nil
        @@active = true
        @@entries.clear
      end

      def self.finish : Nil
        @@active = false
        @@entries.clear
      end

      private def self.key(path : String) : String
        # Bundler's evaluation reads the process environment (BUNDLE_GEMFILE,
        # BUNDLE_WITHOUT, BUNDLE_FROZEN, ...), and commands temporarily rewrite
        # those. An entry evaluated under another environment must not answer.
        "#{File.expand_path(path)}|#{environment_signature}"
      end

      private def self.environment_signature : String
        ENV.to_h.to_a.sort_by { |pair| pair[0] }.map { |(key, value)| "#{key}=#{value}" }.join('\u0001')
      end

      private def self.contents(path : String) : String?
        File.read(path)
      rescue
        nil
      end

      def self.fetch(path : String) : GemfileEvaluation?
        return nil unless @@active
        entry = @@entries[key(path)]?
        return nil if entry.nil?
        bytes = contents(File.expand_path(path))
        return nil if bytes.nil?
        return nil unless Digest::SHA256.hexdigest(bytes) == entry.gemfile_sha256
        entry
      end

      def self.store(path : String, evaluation : GemfileEvaluation) : Nil
        return unless @@active
        @@entries[key(path)] = evaluation
      end
    end

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

    # Repeated-declaration warnings raised while a Gemfile is evaluated
    # (`dsl.rb:307-323`) are returned by the bridge instead of printed, because
    # one Celerite command evaluates the same Gemfile from several bridge
    # processes. The reference prints such a warning once per command: it
    # evaluates a Gemfile once per process (`bundler.rb` `@definition ||=`) and
    # its shell drops repeated identical messages (`ui/shell.rb:39-45`). This
    # ledger reproduces that per-command behaviour on the native side.
    module GemfileWarnings
      @@sink : IO? = nil
      @@seen = Set(String).new
      @@silenced = false

      # Starts a command's ledger. `silenced` mirrors commands whose reference
      # implementation wraps its evaluation in `Bundler.ui.silence`.
      def self.begin(sink : IO, silenced : Bool = false) : Nil
        @@sink = sink
        @@seen.clear
        @@silenced = silenced
      end

      def self.finish : Nil
        @@sink = nil
        @@seen.clear
        @@silenced = false
      end

      # Prints every unseen warning, mirroring `UI::Shell#tell_err`
      # (`ui/shell.rb:147-160`): a message that already ends with a newline is
      # written verbatim, otherwise one is appended.
      def self.record(warnings : Array(String)) : Nil
        sink = @@sink
        return if sink.nil? || @@silenced

        warnings.each do |warning|
          next if warning.empty? || @@seen.includes?(warning)
          @@seen << warning
          if warning.ends_with?('\n')
            sink.print(warning)
          else
            sink.puts(warning)
          end
          sink.flush
        end
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
      # `Gem.default_dir`, which ignores GEM_HOME: default gems live in the
      # Ruby installation, and `spec.loaded_from` reports that location even
      # when a project overrides GEM_HOME.
      getter ruby_default_dir : String? = nil
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
      # Warnings raised while the bridge evaluated this Gemfile (repeated `gem`
      # declarations); the ledger prints each distinct message once per command.
      getter warnings : Array(String) = [] of String
    end

    # Answer to `evaluate_batch` (roadmap L161, slice S2): the ordinary
    # evaluation plus the sections the request asked for. `gemspecs` stays nil
    # when the caller did not include it, so "not requested" and "requested but
    # empty" stay distinguishable without a second response type.
    struct BatchGemfileEvaluation
      getter evaluation : GemfileEvaluation
      getter gemspecs : Array(String)?

      def initialize(@evaluation : GemfileEvaluation, @gemspecs : Array(String)? = nil)
      end
    end

    # Answer to `ping`. `features` is the server's capability list, which is how
    # a client decides whether an op it knows about exists on the other side.
    # A server that predates the declaration omits the field; that says what it
    # cannot do, so it degrades to an empty set instead of failing the call.
    struct Ping
      getter ruby : String
      getter features : Array(String)

      def initialize(@ruby : String, @features : Array(String) = [] of String)
      end

      def self.from_json(result : JSON::Any) : Ping
        ruby = result["ruby"]?.try(&.as_s?) || ""
        features = result["features"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
        new(ruby, features)
      end
    end

    # Client for the JSON Lines bridge server. One process per client; the
    # server stays alive across requests and exits on stdin EOF.
    #
    # Commands do not need one process per call site: `Client.shared` hands out
    # a process-wide connection that every caller borrows and returns, and
    # `close` on such a handle is a no-op so the existing `ensure bridge.close`
    # blocks keep working unchanged. `Client.shutdown` disposes it at the end of
    # the command. `CELERITE_BRIDGE_IDLE_MS` (unset or `0` = never) closes a
    # shared connection that sat idle that long; the next `shared` call spawns a
    # fresh one. A client built with explicit arguments (spec harnesses) is
    # never shared.
    class Client
      @process : Process
      @stdin : IO
      @stdout : IO
      @request_id = 0
      @mutex = Mutex.new
      getter ruby_version : String
      @shared = false
      @closed = false
      @last_used = Time.instant
      @ruby_environment : RubyEnvironment? = nil

      @@shared : Client? = nil
      @@shared_key : String? = nil
      @@shared_mutex = Mutex.new

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
        BridgeStats.record_process
      end

      # The compatibility profile's reference Bundler version (docs/compat-matrix).
      private def reference_bundler_version : String
        Celerite::Profile.bundler_version
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

      # The process-wide connection every command borrows. Rebuilt when the
      # environment changes (the server captures `ENV` at spawn, and commands
      # temporarily override `BUNDLE_GEMFILE`/`BUNDLE_PATH`) or when
      # `CELERITE_BRIDGE_IDLE_MS` says the previous one went idle.
      def self.shared : Client
        @@shared_mutex.synchronize do
          key = shared_key
          if client = @@shared
            if key != @@shared_key || idle_expired?(client.idle_for)
              client.dispose
              @@shared = nil
              @@shared_key = nil
            end
          end
          unless client = @@shared
            client = new
            client.mark_shared
            @@shared = client
            @@shared_key = key
          end
          client
        end
      end

      # Ends the shared connection; the CLI calls this on its way out so an
      # in-process spec never reuses a connection spawned for another command.
      def self.shutdown : Nil
        @@shared_mutex.synchronize do
          if client = @@shared
            client.dispose
            @@shared = nil
            @@shared_key = nil
          end
        end
      end

      private def self.idle_timeout_ms : Int32
        value = ENV["CELERITE_BRIDGE_IDLE_MS"]?
        return 0 if value.nil? || value.empty?
        milliseconds = value.to_i?
        return 0 if milliseconds.nil? || milliseconds <= 0
        milliseconds
      end

      private def self.idle_expired?(idle_for : Time::Span) : Bool
        milliseconds = idle_timeout_ms
        return false if milliseconds <= 0
        idle_for >= milliseconds.milliseconds
      end

      # The server runs with the environment captured at spawn, so a change in
      # `ENV` between two borrows (commands temporarily rewrite BUNDLE_*) needs
      # a fresh process to stay faithful to "one client = one spawn env".
      private def self.shared_key : String
        ENV.to_h.to_a.sort_by { |pair| pair[0] }.join('\u0001') { |(key, value)| "#{key}=#{value}" }
      end

      protected def mark_shared : Nil
        @shared = true
      end

      protected def idle_for : Time::Span
        Time.instant - @last_used
      end

      # Full teardown, including shared connections (whose public `close` is a
      # no-op so call sites keep their `ensure bridge.close` semantics).
      protected def dispose : Nil
        return if @closed
        @closed = true
        @stdin.close unless @stdin.closed?
        @process.wait unless @process.terminated?
      end

      # Negotiation probe: the Ruby version plus the server's capability list.
      # An older server answers without `features`; see `Ping.from_json`.
      def ping : Ping
        Ping.from_json(request("ping"))
      end

      # The bridge process's Ruby environment never changes for a given spawn,
      # so one command needs at most one lookup (install used to pay nine).
      def ruby_environment : RubyEnvironment
        @ruby_environment ||= RubyEnvironment.from_json(request("ruby_environment").to_json)
      end

      def evaluate_gemfile(path : String) : GemfileEvaluation
        # A hit repeats an evaluation the caller would otherwise receive; the
        # warnings ledger already printed that evaluation's warnings once, so a
        # hit must not record them again (that would duplicate them when the
        # per-command dedupe is bypassed).
        if cached = EvaluationCache.fetch(path)
          return cached
        end
        evaluation = GemfileEvaluation.from_json(request("evaluate_gemfile", {"gemfile" => path}).to_json)
        GemfileWarnings.record(evaluation.warnings)
        EvaluationCache.store(path, evaluation)
        evaluation
      end

      # One request that answers what `evaluate_gemfile` answers plus the
      # sections named in `include` (roadmap L161, slice S2; `gemspecs` today).
      # With no section requested this is the old single-op call: the payload
      # omits `include`, and the cache may answer it exactly as before. A
      # request that names a section cannot be served from the cache — the
      # cache stores evaluations, not sections — so it always goes to the
      # bridge.
      def evaluate_batch(path : String, include sections : Array(String) = [] of String) : BatchGemfileEvaluation
        if sections.empty?
          if cached = EvaluationCache.fetch(path)
            return BatchGemfileEvaluation.new(cached)
          end
        end

        payload = {"gemfile" => JSON::Any.new(path)} of String => JSON::Any
        unless sections.empty?
          payload["include"] = JSON::Any.new(sections.map { |section| JSON::Any.new(section) })
        end

        result = request("evaluate_batch", payload)
        evaluation = GemfileEvaluation.from_json(result.to_json)
        GemfileWarnings.record(evaluation.warnings)
        EvaluationCache.store(path, evaluation)
        gemspecs = result["gemspecs"]?.try(&.as_a?).try(&.map(&.as_s))
        BatchGemfileEvaluation.new(evaluation, gemspecs)
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
        result = request("gemspec_paths", {"gemfile" => gemfile})
        GemfileWarnings.record(result["warnings"]?.try(&.as_a.map(&.as_s)) || [] of String)
        result["gemspecs"].as_a.map(&.as_s)
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

      # `Gem::Specification.load` for an installed `specifications/*.gemspec`
      # (reference `bundle info` reads the real spec, cli/info.rb:50-73). The
      # bridge evaluates the file as Ruby, so escaped literals are decoded.
      def load_installed_spec(path : String) : JSON::Any?
        result = request("load_installed_spec", {"path" => path})
        spec = result["spec"]?
        spec.nil? || spec.raw.nil? ? nil : spec
      end

      # `Bundler::CLI::Common.default_gem_spec` (common.rb:98-101): the
      # interpreter's default gem for a bare name, if any. `bundle open`
      # appends it to the regex candidates so `bundle open json` can offer
      # the interpreter's own `json` next to the bundled `json_pure`.
      def default_gem_spec(name : String) : NamedTuple(
        name: String, version: String, platform: String, full_gem_path: String,
        dependencies: Array(NamedTuple(name: String, requirements: Array(String))),
        required_ruby_version: String, required_rubygems_version: String,
        full_name: String, loaded_from: String?,
        summary: String?, homepage: String?, metadata: Hash(String, String))?
        result = request("default_gem_spec", {"name" => name})
        return nil if result.raw.nil?
        dependencies = (result["dependencies"]?.try(&.as_a) || [] of JSON::Any).map do |dep|
          requirements = (dep["requirements"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
          {name: dep["name"].as_s, requirements: requirements}
        end
        metadata = {} of String => String
        result["metadata"]?.try(&.as_h?).try &.each do |key, value|
          metadata[key] = value.as_s? || value.to_s
        end
        {
          name:                      result["name"].as_s,
          version:                   result["version"].as_s,
          platform:                  result["platform"].as_s,
          full_gem_path:             result["full_gem_path"].as_s,
          dependencies:              dependencies,
          required_ruby_version:     result["required_ruby_version"].as_s,
          required_rubygems_version: result["required_rubygems_version"].as_s,
          full_name:                 result["full_name"]?.try(&.as_s?) || "#{result["name"].as_s}-#{result["version"].as_s}",
          loaded_from:               result["loaded_from"]?.try(&.as_s?),
          summary:                   result["summary"]?.try(&.as_s?),
          homepage:                  result["homepage"]?.try(&.as_s?),
          metadata:                  metadata,
        }
      end

      # `cli/doctor/ssl.rb:61-69`: the interpreter's OpenSSL versions, so
      # `bundle doctor ssl` reports the same build as the reference.
      def ssl_openssl_versions : NamedTuple(version: String, compiled: String, loaded: String)
        result = request("ssl_openssl_versions", {} of String => String)
        {
          version:  result["version"].as_s,
          compiled: result["compiled"].as_s,
          loaded:   result["loaded"].as_s,
        }
      end

      # `cli/doctor/ssl.rb:99-121`: Net::HTTP connectivity probe with the
      # requested TLS bounds and verification mode.
      def ssl_probe(host : String, timeout : Int32, tls_version : String?, verify_mode : String?) : NamedTuple(
        success: Bool, error_class: String?, error_message: String?, backtrace: Array(String))
        payload = {"host" => host, "timeout" => timeout.to_s} of String => String
        payload["tls_version"] = tls_version if tls_version
        payload["verify_mode"] = verify_mode if verify_mode
        result = request("ssl_probe", payload, limit: (timeout + 5).seconds)
        {
          success:       result["success"].as_bool,
          error_class:   result["class"]?.try(&.as_s?),
          error_message: result["message"]?.try(&.as_s?),
          backtrace:     (result["backtrace"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s),
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
                           spec_name : String? = nil, spec_full_name : String? = nil,
                           gemfile_path : String? = nil) : JSON::Any
        payload = {"event" => event, "index_path" => index_path} of String => String?
        payload["spec_name"] = spec_name
        payload["spec_full_name"] = spec_full_name
        # Install-all hooks receive `definition.dependencies` (an Array of
        # `Bundler::Dependency`), which the bridge rebuilds from this Gemfile.
        payload["gemfile_path"] = gemfile_path
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

      # `plugins/<gem>_plugin.rb`: RubyGems writes it during `install`
      # (`installer.rb:475-488`); paths are the published install root so the
      # `require_relative` body points at the final `gems/` directory.
      def generate_plugins(gem_path : String, install_root : String, gem_dir : String) : JSON::Any
        request("generate_plugins", {"gem_path" => gem_path, "install_root" => install_root, "gem_dir" => gem_dir})
      end

      def load_gemspec_dir(dir : String, glob : String? = nil, name : String? = nil) : GemSpecInfo
        payload = {"dir" => dir} of String => String
        payload["glob"] = glob if glob
        payload["name"] = name if name
        GemSpecInfo.from_json(request("load_gemspec_dir", payload).to_json)
      end

      # All gemspecs a PATH source exposes under `glob` (`source/path.rb:159-179`
      # keeps the shallower gemspec when two share a name).
      def load_gemspec_dir_specs(dir : String, glob : String? = nil) : Array(GemSpecSummary)
        payload = {"dir" => dir} of String => String
        payload["glob"] = glob if glob
        Array(GemSpecSummary).from_json(request("load_gemspec_dir_specs", payload)["specs"].to_json)
      end

      def build_extension(gem_dir : String, destination : String, name : String, gem_path : String, target_rbconfig : String? = nil, build_args : Array(String)? = nil, build_jobs : Int32? = nil, jobs_mode : String? = nil) : JSON::Any
        payload = {"gem_dir" => gem_dir, "destination" => destination, "name" => name, "gem_path" => gem_path} of String => String
        payload["target_rbconfig"] = target_rbconfig if target_rbconfig
        payload["build_args"] = build_args.join(" ") if build_args && !build_args.empty?
        payload["build_jobs"] = build_jobs.to_s if build_jobs
        payload["jobs_mode"] = jobs_mode if jobs_mode
        request("build_extension", payload, limit: nil)
      end

      def bundler_cache_file(version : String) : String?
        result = request("bundler_cache_file", {"version" => version})
        path = result["path"].as_s?
        return nil if path.nil? || path.empty?
        result["exists"].as_bool ? path : nil
      end

      # Borrowed handles return rather than close: the shared connection lives
      # until `Client.shutdown`. A privately constructed client still tears its
      # process down here, exactly as before.
      def close : Nil
        return if @shared
        dispose
      end

      # Long-running operations (native extension builds, plugin hooks) mirror
      # the reference, which has no RPC deadline at all: a gem that takes
      # minutes to compile must not be cut off by the 30s default. Pass
      # `limit: nil` for those; everything else keeps the safety net.
      # `evaluate_batch` carries an array (`include`), which the string-only
      # payload hashes cannot express; the envelope itself is unchanged.
      private def request(op : String, payload : Hash(String, String) | Hash(String, String?) | Hash(String, JSON::Any) = {} of String => String, limit : Time::Span? = @timeout) : JSON::Any
        @mutex.synchronize do
          @last_used = Time.instant
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
          BridgeStats.record_request(line.bytesize + 1)

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
            BridgeStats.record_response(line.bytesize)
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
        proto = response["proto"].as_i?
        unless proto && proto >= PROTOCOL_MIN && proto <= PROTOCOL
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
