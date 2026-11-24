require "digest/sha256"
require "json"
require "process"
require "../errors"
require "../eval_cache_store"
require "../eval_fingerprint"

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

    # Batch bounds (roadmap L163, task-243). The reference Bundler has no batch
    # concept at all (`git grep batch` over bundler 4.0.24 finds nothing), so
    # these limits belong to this bridge protocol, not to a reference behaviour:
    # one request may not ask for unbounded work (`include` sections), and its
    # answer may not be unbounded either. Both sides enforce them and both
    # answer with a structured `BatchTooLarge` error — never truncation, never
    # sharding, never a degraded success.
    #
    # Every existing call site requests exactly two sections (`fingerprint`,
    # `gemspecs`, from GemfileEvaluator), so four is twice the observed ceiling
    # and no existing command can reach it. The byte cap is sized from measured
    # data (docs/compat-evidence/2026-11-23.md, task-243): the largest single
    # batch response observed is 2,125 bytes, and the largest whole-command
    # response total recorded in the differential runs is 289,430 bytes over up
    # to 15 RPCs, so no single response can exceed that. 4 MiB is ~1,970x the
    # measured response and ~14x that command total: bounded, yet unreachable
    # by any real Gemfile.
    MAX_INCLUDE_SECTIONS     = 4
    MAX_BATCH_RESPONSE_BYTES = 4 * 1024 * 1024

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
      @@evaluations = 0

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
        @@evaluations = 0
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

      # An *evaluation* is one `evaluate_batch` round trip, i.e. one run of
      # `Bundler::Dsl#eval_gemfile` inside the bridge. It is tracked apart from
      # `rpc` because F5's invariant is about evaluations, not requests: a
      # command may spend RPCs on `ruby_environment`/`gemspec_paths` without
      # evaluating the Gemfile again, and a cache hit costs zero evaluations.
      # Deliberately absent from `finish`'s line, which is pinned output.
      def self.record_evaluation : Nil
        @@evaluations += 1 if enabled?
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

      def self.evaluations : Int32
        @@evaluations
      end
    end

    # Per-command memo for `evaluate_gemfile` / `evaluate_batch`. One Celerite
    # command evaluates the same Gemfile from several sites (`check`
    # deliberately twice: once for the dependency diff, once inside the frozen
    # branch), and every evaluation is a full RPC round trip. The reference
    # evaluates a Gemfile once per process (`bundler.rb` `@definition ||=`) and
    # reuses that definition, so a command never re-evaluates an unchanged
    # file; the cache reproduces that without changing what any caller sees.
    #
    # F2 (roadmap L162): a hit no longer rests on the main Gemfile alone. The
    # entry carries the evaluation fingerprint produced by the very same
    # evaluation (slice F1), and a hit requires all three of:
    #
    #  1. the fingerprint text still hashes to its digest and every file in its
    #     `verify` set re-hashes equal — the main Gemfile, every file reached
    #     through `eval_gemfile` and every loaded gemspec. A missing file, a
    #     changed eval-chain file or a changed gemspec is a miss. This is
    #     exactly the hole the old check left open.
    #  2. the runtime records (`ruby.*`, `rubygems.version`, `bundler.version`,
    #     `platform`) equal the answering process. The comparison is skipped
    #     only when the entry was produced by this very client, i.e. by the
    #     same bridge process, where the records are equal by construction.
    #  3. the environment signature still matches. F1's fingerprint does not
    #     cover ENV, so the whole environment stays a conservative component.
    #     It is stored hashed, never in plaintext.
    #
    # Why this cannot cost a second evaluation: the fingerprint arrives in the
    # response of the evaluation it describes, so storing it is free; on a hit
    # the runtime records come from `ruby_environment` (one RPC per client,
    # memoized) only when the entry came from another client, and the file set
    # is re-hashed locally. No code path asks the bridge to run the Gemfile DSL
    # again to obtain a fingerprint. The cache still lives only inside one
    # `CLI.run` (see `begin_run`/`finish`).
    module EvaluationCache
      struct Entry
        getter evaluation : GemfileEvaluation
        getter fingerprint : Bridge::EvalFingerprint?
        getter document : Celerite::EvalFingerprint::Document?
        getter gemspecs : Array(String)?
        getter env_signature : String
        getter owner_cache_id : Int32

        def initialize(@evaluation : GemfileEvaluation, @fingerprint : Bridge::EvalFingerprint?,
                       @document : Celerite::EvalFingerprint::Document?, @gemspecs : Array(String)?,
                       @env_signature : String, @owner_cache_id : Int32)
        end
      end

      @@active = false
      @@entries = {} of String => Entry
      # Paths whose last evaluation was withheld (`unknown` or `broken`), mapped
      # to the reason. Nothing about the evaluation is kept — only the fact that
      # a later lookup cannot be served, so it is reported as a miss instead of
      # silently re-evaluating as if the cache had never seen the path.
      @@withheld = {} of String => String
      @@hits = 0
      @@misses = 0
      @@debug_io : IO = STDERR

      def self.begin_run : Nil
        @@active = true
        @@entries.clear
        @@withheld.clear
        @@hits = 0
        @@misses = 0
      end

      # Whether a command has started its cache lifetime. The client asks for
      # the fingerprint's configuration records only while this holds, so
      # commands that run without a cache keep their RPC shape unchanged.
      def self.active? : Bool
        @@active
      end

      def self.finish : Nil
        # The on-disk store (F4) is pruned here, while the entry just written is
        # still the newest: the cap is per entry count and total bytes and never
        # touches an entry this command would still answer from.
        EvalCacheStore.prune if EvalCacheStore.enabled?
        @@active = false
        @@entries.clear
        @@withheld.clear
        @@hits = 0
        @@misses = 0
      end

      def self.hits : Int32
        @@hits
      end

      def self.misses : Int32
        @@misses
      end

      # Where `CELERITE_EVAL_DEBUG=1` diagnostics go. STDERR in production; the
      # specs point it at an `IO::Memory` instead of redirecting the process.
      def self.debug_io : IO
        @@debug_io
      end

      def self.debug_io=(io : IO) : IO
        @@debug_io = io
      end

      private def self.debug(message : String) : Nil
        return unless ENV["CELERITE_EVAL_DEBUG"]? == "1"
        @@debug_io.puts message
        @@debug_io.flush
      end

      private def self.normalized(path : String) : String
        File.expand_path(path).tr("\\", "/")
      end

      private def self.environment_signature : String
        # Bundler's evaluation reads the process environment (BUNDLE_GEMFILE,
        # BUNDLE_WITHOUT, BUNDLE_FROZEN, ...), and commands temporarily rewrite
        # those. An entry evaluated under another environment must not answer.
        # The signature is hashed so no environment value (credentials, tokens)
        # is ever kept in memory as plaintext.
        material = ENV.to_h.to_a.sort_by { |pair| pair[0] }.map { |(key, value)| "#{key}=#{value}" }.join('\u0001')
        Digest::SHA256.hexdigest(material)
      end

      private def self.miss(reason : String) : Nil
        @@misses += 1
        debug("eval-cache: miss (#{reason})")
      end

      # Returns the cached entry when the fingerprint, the runtime records and
      # the environment signature all still hold. `runtime` is evaluated lazily
      # and only for entries produced by a different client: for our own
      # entries the records cannot have changed.
      def self.fetch(path : String, sections : Array(String), cache_id : Int32,
                     &runtime : -> Celerite::EvalFingerprint::Runtime) : Entry?
        return nil unless @@active
        entry = @@entries[normalized(path)]?
        if entry.nil?
          # A path that was evaluated and withheld can never answer; count the
          # lookup as a miss instead of pretending the cache is empty.
          if withheld = @@withheld[normalized(path)]?
            return miss(withheld)
          end
          return load_persisted(path, sections, cache_id) { runtime.call }
        end

        return miss("env") unless entry.env_signature == environment_signature
        return miss("path") unless normalized(entry.evaluation.gemfile) == normalized(path)

        document = entry.document
        return miss("fingerprint") if document.nil?
        if sections.includes?("gemspecs") && entry.gemspecs.nil?
          return miss("gemspecs")
        end

        current_runtime = entry.owner_cache_id == cache_id ? nil : runtime.call
        if reason = document.verify(File.dirname(File.expand_path(path)), current_runtime)
          if Celerite::EvalFingerprint.broken_reason?(reason)
            # The entry contradicts itself. It cannot answer now or later, so
            # drop it and report the broken state rather than a plain miss.
            @@entries.delete(normalized(path))
            return miss("broken:#{reason}")
          end
          return miss(reason)
        end

        @@hits += 1
        debug("eval-cache: hit")
        entry
      end

      # Cross-command lookup (F4). The entry must prove itself without trusting
      # the fingerprint that ships with it: the directory name is the digest,
      # the stored text must hash to that digest, every file in `verify` is
      # re-hashed from disk, and the runtime records still come from the bridge.
      # A corrupt or stale entry is deleted and reported as a miss; the command
      # never fails because of the cache.
      private def self.load_persisted(path : String, sections : Array(String), cache_id : Int32,
                                      &runtime : -> Celerite::EvalFingerprint::Runtime) : Entry?
        return nil unless EvalCacheStore.enabled?
        base = File.dirname(File.expand_path(path))
        stale : String? = nil
        EvalCacheStore.read_all.each do |stored|
          evaluation_node = stored.json["evaluation"]?
          next if evaluation_node.nil?
          recorded = evaluation_node["gemfile"]?.try(&.as_s?)
          next if recorded.nil? || normalized(recorded) != normalized(path)

          entry = begin
            persisted_entry(stored, sections, base, cache_id) { runtime.call }
          rescue
            {nil, "unreadable"}
          end
          candidate, reason = entry
          if candidate
            @@entries[normalized(path)] = candidate
            @@hits += 1
            debug("eval-cache: hit (persistent)")
            return candidate
          end
          if reason
            stale = reason
            EvalCacheStore.delete(stored.digest) if discard_persisted?(reason)
            # A runtime record can differ from another machine/Ruby and come
            # back later; the safe response is a miss, not a deleted entry.
            debug("eval-cache: persistent miss (#{reason})")
          end
        end
        stale ? miss("persistent:#{stale}") : nil
      end

      private def self.persisted_entry(stored : EvalCacheStore::EntryFile, sections : Array(String),
                                       base : String, cache_id : Int32,
                                       &runtime : -> Celerite::EvalFingerprint::Runtime) : {Entry?, String?}
        node = stored.json
        return {nil, "format"} unless node["format"]?.try(&.as_s?) == EvalCacheStore::FORMAT
        # The full environment signature is a conservative requirement: a
        # command that runs under a different environment must re-evaluate.
        return {nil, "env"} unless node["env"]?.try(&.as_s?) == environment_signature

        fp_node = node["fingerprint"]?.try(&.as_h?)
        return {nil, "fingerprint"} if fp_node.nil?
        text = fp_node["text"]?.try(&.as_s?)
        digest = fp_node["digest"]?.try(&.as_s?)
        verify = fp_node["verify"]?
        return {nil, "fingerprint"} if text.nil? || digest.nil? || verify.nil?
        return {nil, "digest"} unless digest == stored.digest

        state = Celerite::EvalFingerprint::State.parse(fp_node["state"]?.try(&.as_s?))
        return {nil, "state"} unless state.deterministic?

        document = Celerite::EvalFingerprint::Document.parse(text, digest, verify)
        return {nil, "fingerprint"} if document.nil?
        if reason = document.integrity_reason
          return {nil, reason}
        end
        if sections.includes?("gemspecs") && node["gemspecs"]?.try(&.as_a?).nil?
          return {nil, "gemspecs"}
        end
        if reason = document.verify(base, runtime.call)
          return {nil, reason}
        end

        evaluation = GemfileEvaluation.from_json(node["evaluation"].to_json)
        gemspecs = node["gemspecs"]?.try(&.as_a?).try(&.map(&.as_s))
        fingerprint = Bridge::EvalFingerprint.new(
          text, digest, verify, state, fp_node["state_reason"]?.try(&.as_s?))
        {Entry.new(evaluation, fingerprint, document, gemspecs, node["env"].as_s, cache_id), nil}
      end

      private def self.discard_persisted?(reason : String) : Bool
        return true if Celerite::EvalFingerprint.broken_reason?(reason)
        return true if reason.starts_with?("sha256:") || reason.starts_with?("missing:")
        {"format", "digest", "state", "gemfile", "unreadable"}.includes?(reason)
      end

      # Only a `deterministic` evaluation may be reused. `unknown` means the
      # bridge could not reproduce the evaluation from the files the fingerprint
      # covers; `broken` means the fingerprint cannot even describe it. Both are
      # returned to the caller untouched and never stored, so the observable
      # behaviour equals a run without a cache. The evaluation itself already
      # succeeded here: a broken fingerprint must not fail the command.
      def self.store(path : String, evaluation : GemfileEvaluation, cache_id : Int32,
                     fingerprint : Bridge::EvalFingerprint? = nil,
                     gemspecs : Array(String)? = nil) : Nil
        return unless @@active
        state, reason = if fp = fingerprint
                          {fp.state, fp.state_reason}
                        else
                          {Celerite::EvalFingerprint::State::Unknown, "fingerprint-missing"}
                        end
        document = fingerprint.try { |fp| Celerite::EvalFingerprint::Document.parse(fp.text, fp.digest, fp.verify) }

        if state.deterministic?
          # A fingerprint that calls itself deterministic must survive its own
          # self-check; a corrupt section is `broken`, not a cache entry.
          if document.nil?
            state = Celerite::EvalFingerprint::State::Broken
            reason = "unparsable"
          elsif (integrity = document.not_nil!.integrity_reason)
            state = Celerite::EvalFingerprint::State::Broken
            reason = integrity
          end
        end

        unless state.deterministic?
          debug(reason ? "eval-cache: state=#{state.wire} reason=#{reason}" : "eval-cache: state=#{state.wire}")
          @@withheld[normalized(path)] = reason ? "#{state.wire}:#{reason}" : state.wire
          return
        end

        debug("eval-cache: state=deterministic")
        @@withheld.delete(normalized(path))
        # A section the caller did not ask for is not a section that changed:
        # carrying the earlier entry's `gemspecs` over when the fingerprint
        # digest is unchanged keeps a later `gemspecs` lookup a cache hit instead
        # of charging a second evaluation for the very same files (F5).
        if gemspecs.nil?
          if (existing = @@entries[normalized(path)]?) &&
             (previous = existing.fingerprint) && (current = fingerprint) &&
             previous.digest == current.digest
            gemspecs = existing.gemspecs
          end
        end
        entry = Entry.new(evaluation, fingerprint, document, gemspecs,
          environment_signature, cache_id)
        @@entries[normalized(path)] = entry
        persist(entry)
      end

      # Writes the proof-carrying entry documented in plan §1.5: the evaluation
      # is the only payload; the fingerprint and its `verify` set let a later
      # command re-check the cache without a second evaluation. Refused when the
      # evaluation itself embeds a credential-bearing URI.
      private def self.persist(entry : Entry) : Nil
        return unless EvalCacheStore.enabled?
        fingerprint = entry.fingerprint
        return if fingerprint.nil?

        payload = JSON.build do |json|
          json.object do
            json.field "format", EvalCacheStore::FORMAT
            json.field "digest", fingerprint.digest
            json.field "env", entry.env_signature
            json.field "fingerprint" do
              json.object do
                json.field "text", fingerprint.text
                json.field "digest", fingerprint.digest
                json.field "state", fingerprint.state.wire
                json.field "state_reason", fingerprint.state_reason
                json.field "verify", fingerprint.verify
              end
            end
            json.field "gemspecs" do
              if gemspecs = entry.gemspecs
                json.array { gemspecs.each { |name| json.string(name) } }
              else
                json.null
              end
            end
            json.field "evaluation", JSON.parse(entry.evaluation.to_json)
          end
        end

        unless EvalCacheStore.persistable?(payload)
          debug("eval-cache: persist skipped (credential)")
          return
        end
        if EvalCacheStore.write(fingerprint.digest, payload)
          debug("eval-cache: persisted #{fingerprint.digest[0, 12]}")
        else
          debug("eval-cache: persist failed")
        end
      rescue ex
        # Persistence is an optimization: a read-only home, a full disk or a
        # racing GC must not change the command's output or exit status.
        debug("eval-cache: persist failed (#{ex.class})")
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

    # A batch request or answer exceeded `MAX_INCLUDE_SECTIONS` /
    # `MAX_BATCH_RESPONSE_BYTES`. `error_class` is the protocol class name the
    # Ruby side sends (`BatchTooLarge`), so code that inspects `error_class` and
    # code that rescues this type agree.
    class BatchTooLargeError < BridgeError
      def initialize(message : String, status : Int32? = nil)
        super("BatchTooLarge", message, status)
      end
    end

    # Section-count gate for `evaluate_batch`. Kept callable on its own because
    # the constructor spawns the bridge eagerly (`Client#initialize`): a caller
    # that must not start a bridge process validates here first. `evaluate_batch`
    # calls it before any cache lookup or RPC, so the limit can never be turned
    # into a slower request.
    def self.validate_batch_sections!(sections : Array(String)) : Nil
      return if sections.size <= MAX_INCLUDE_SECTIONS

      raise BatchTooLargeError.new(
        "evaluate_batch include has #{sections.size} sections, limit is #{MAX_INCLUDE_SECTIONS}")
    end

    # Byte cap applied to a batch response line, with the test/diagnostic
    # override shared with `assets/bridge/server.rb`.
    def self.batch_response_bytes_limit : Int32
      value = ENV["CELERITE_BATCH_MAX_BYTES"]?
      return MAX_BATCH_RESPONSE_BYTES if value.nil? || value.empty?

      parsed = value.to_i?
      return MAX_BATCH_RESPONSE_BYTES if parsed.nil? || parsed <= 0

      parsed
    end

    # Rejects an over-long response line. The whole response is one line, so a
    # refusal consumes exactly the bytes it rejects and the stream stays in
    # sync for the next request.
    def self.check_batch_response_bytes!(bytesize : Int32, limit : Int32 = batch_response_bytes_limit) : Nil
      return if bytesize <= limit

      raise BatchTooLargeError.new(
        "evaluate_batch response is #{bytesize} bytes, limit is #{limit}")
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
      # ABI facts (task-246). `Gem.extension_api_version` carries the `-static`
      # suffix when Ruby was built without shared libraries; the plain
      # `ruby_version` record cannot distinguish those builds.
      getter ruby_api_version : String? = nil
      getter extension_api_version : String? = nil
      getter rbconfig_ruby_version : String? = nil
      # Only requested for the evaluation cache; `bundle env` leaves it nil and
      # an older bridge answers without it.
      getter evaluation_config : Celerite::EvalFingerprint::EvaluationConfig? = nil
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

    # One `celerite-eval-v1` fingerprint produced by the same evaluation as the
    # rest of the batch answer (roadmap L162, slice F1). `state` is the bridge's
    # cacheability verdict (slice F3): only this client's side of the wire is
    # allowed to consume it, never to infer it.
    struct EvalFingerprint
      getter text : String
      getter digest : String
      # The cheap inputs a caller can re-hash to check a future hit:
      # `{"files":[{"role","path","sha256"}]}`, paths relative to the Gemfile's
      # directory. Kept as JSON so a later slice can widen it without a client
      # break; F1 republishes what the bridge sent.
      getter verify : JSON::Any
      # See `Celerite::EvalFingerprint::State`. A missing or unrecognized value
      # degrades to `Unknown`: an old server, or a section this client cannot
      # read, must never be mistaken for "safe to reuse".
      getter state : Celerite::EvalFingerprint::State
      # Why the bridge withheld the cache (`token:ENV`, `plugin-index`, ...);
      # nil when deterministic.
      getter state_reason : String?

      def initialize(@text : String, @digest : String, @verify : JSON::Any,
                     @state : Celerite::EvalFingerprint::State = Celerite::EvalFingerprint::State::Unknown,
                     @state_reason : String? = nil)
      end

      # A malformed section degrades to nil: a server that predates the section
      # or a shape this client does not know must not break the command that
      # asked for it.
      def self.parse(node : JSON::Any?) : EvalFingerprint?
        object = node.try(&.as_h?)
        return nil unless object
        text = object["text"]?.try(&.as_s?)
        digest = object["digest"]?.try(&.as_s?)
        verify = object["verify"]?
        return nil unless text && digest && verify
        return nil unless verify.as_h?
        state = Celerite::EvalFingerprint::State.parse(object["state"]?.try(&.as_s?))
        reason = object["state_reason"]?.try(&.as_s?)
        new(text, digest, verify, state, reason)
      rescue JSON::Error
        nil
      end
    end

    # Answer to `evaluate_batch` (roadmap L161, slice S2): the ordinary
    # evaluation plus the sections the request asked for. `gemspecs` stays nil
    # when the caller did not include it, so "not requested" and "requested but
    # empty" stay distinguishable without a second response type; the same
    # holds for `fingerprint`.
    struct BatchGemfileEvaluation
      getter evaluation : GemfileEvaluation
      getter gemspecs : Array(String)?
      getter fingerprint : EvalFingerprint?

      def initialize(@evaluation : GemfileEvaluation, @gemspecs : Array(String)? = nil, @fingerprint : EvalFingerprint? = nil)
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
      # The runtime records a cache hit is re-verified against (task-246). Built
      # once per client from `ruby_environment`, which already carries the
      # configuration records while the cache is active.
      @fingerprint_runtime : Celerite::EvalFingerprint::Runtime? = nil

      @@shared : Client? = nil
      @@shared_key : String? = nil
      @@shared_mutex = Mutex.new

      # Monotonic identity for cache ownership checks. `object_id` can be
      # recycled after a client is collected, and a recycled id would make a
      # stale entry look like it came from the current process.
      @@cache_serial = 0_i32

      # Identifies this client to `EvaluationCache`: an entry owned by the same
      # id was produced by this very bridge process, so its runtime records
      # need no re-check.
      getter cache_id : Int32

      def initialize(ruby_exe : String? = nil, server_path : String? = nil, timeout : Time::Span = 30.seconds)
        ruby = ruby_exe || ENV["CELERITE_RUBY"]? || "ruby"
        server = server_path || Client.locate_server
        @timeout = timeout
        @cache_id = (@@cache_serial += 1)
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
      # While the evaluation cache is active the same answer carries the
      # configuration the fingerprint records (task-246), so verification costs
      # no extra RPC: a persisted hit still pays fewer requests than a cold run.
      def ruby_environment : RubyEnvironment
        @ruby_environment ||= begin
          payload = {} of String => JSON::Any
          payload["evaluation_config"] = JSON::Any.new(true) if EvaluationCache.active?
          RubyEnvironment.from_json(request("ruby_environment", payload).to_json)
        end
      end

      def evaluate_gemfile(path : String) : GemfileEvaluation
        # A hit repeats an evaluation the caller would otherwise receive; the
        # warnings ledger already printed that evaluation's warnings once, so a
        # hit must not record them again (that would duplicate them when the
        # per-command dedupe is bypassed).
        #
        # The request asks for the `fingerprint` section: the fingerprint is
        # produced by the same single Gemfile evaluation the bridge performs
        # for this request (slice F1), so carrying it costs no second
        # evaluation and no extra RPC — it is what lets the cache verify a hit.
        evaluate_batch(path, ["fingerprint"]).evaluation
      end

      # One request that answers what `evaluate_gemfile` answers plus the
      # sections named in `include` (roadmap L161, slice S2: `gemspecs`;
      # roadmap L162, slice F1: `fingerprint`). A cached entry can answer a
      # request when every requested section is one the entry itself carries;
      # sections it cannot vouch for must reach the bridge. `fingerprint` is
      # itself the cache's invalidation evidence (see `EvaluationCache`), so
      # asking for it does not bypass the cache — a hit still re-verifies it.
      def evaluate_batch(path : String, include sections : Array(String) = [] of String) : BatchGemfileEvaluation
        Bridge.validate_batch_sections!(sections)
        cacheable = sections.all? { |section| section == "fingerprint" || section == "gemspecs" }
        if cacheable
          if entry = EvaluationCache.fetch(path, sections, cache_id) { cache_runtime }
            return BatchGemfileEvaluation.new(
              entry.evaluation,
              sections.includes?("gemspecs") ? entry.gemspecs : nil,
              sections.includes?("fingerprint") ? entry.fingerprint : nil,
            )
          end
        end

        payload = {"gemfile" => JSON::Any.new(path)} of String => JSON::Any
        unless sections.empty?
          payload["include"] = JSON::Any.new(sections.map { |section| JSON::Any.new(section) })
        end

        BridgeStats.record_evaluation
        result = request("evaluate_batch", payload, max_response_bytes: Bridge.batch_response_bytes_limit)
        evaluation = GemfileEvaluation.from_json(result.to_json)
        GemfileWarnings.record(evaluation.warnings)
        gemspecs = result["gemspecs"]?.try(&.as_a?).try(&.map(&.as_s))
        fingerprint = EvalFingerprint.parse(result["fingerprint"]?)
        EvaluationCache.store(path, evaluation, cache_id, fingerprint, gemspecs)
        BatchGemfileEvaluation.new(evaluation, gemspecs, fingerprint)
      end

      # Runtime facts a cache hit must match when the entry came from another
      # client (another bridge process). `ruby_environment` is memoized per
      # client, so this costs at most one RPC per command. `bundler.version`
      # is compared against the requested profile version: the bridge refuses
      # to evaluate when the process loaded a different release
      # (`BundlerVersionMismatch`), so the requested version is the one the
      # evaluation ran under.
      private def cache_runtime : Celerite::EvalFingerprint::Runtime
        @fingerprint_runtime ||= begin
          environment = ruby_environment
          config = environment.evaluation_config
          abi = if (api = environment.ruby_api_version) &&
                   (extension = environment.extension_api_version) &&
                   (rbconfig = environment.rbconfig_ruby_version)
                  Celerite::EvalFingerprint::Abi.new(api, extension, rbconfig)
                end
          Celerite::EvalFingerprint::Runtime.new(
            ruby_version: environment.ruby_version,
            patchlevel: environment.patchlevel || "-",
            engine: environment.engine,
            engine_version: environment.engine_version,
            rubygems_version: environment.rubygems_version,
            bundler_version: reference_bundler_version,
            platform: environment.platform,
            abi: abi,
            config: config,
          )
        end
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
      # Production callers use `GemfileEvaluator.gemspecs`, which gets them from
      # the evaluation request itself (slice F5); this op stays for protocol
      # compatibility and for simulations that only implement `gemspec_paths`.
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
      private def request(op : String, payload : Hash(String, String) | Hash(String, String?) | Hash(String, JSON::Any) = {} of String => String, limit : Time::Span? = @timeout, max_response_bytes : Int32? = nil) : JSON::Any
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

          finish_response(id, read_response(limit, max_response_bytes, id))
        end
      end

      private def read_response(limit : Time::Span?, max_bytes : Int32? = nil, id : Int32 = -1) : JSON::Any
        done = Channel(JSON::Any).new(1)

        spawn(name: "bridge-reader") do
          line = @stdout.gets
          if line.nil?
            done.send(crash_response(id, "bridge server closed the connection", "BridgeCrashed"))
          else
            BridgeStats.record_response(line.bytesize)
            if (cap = max_bytes) && line.bytesize > cap
              # One response is one line, so the oversized line has been fully
              # consumed and the stream stays aligned.
              done.send(crash_response(id, "evaluate_batch response is #{line.bytesize} bytes, limit is #{cap}", "BatchTooLarge"))
            else
              begin
                done.send(JSON.parse(line))
              rescue ex
                done.send(crash_response(id, "bridge sent non-JSON output: #{ex.message}", "ProtocolError"))
              end
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

      private def crash_response(id : Int32, message : String, error_class : String) : JSON::Any
        text = JSON.build do |json|
          json.object do
            json.field "proto", PROTOCOL
            json.field "id", id
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
          error_class = error["class"].as_s
          message = error["message"].as_s
          status = error["status"]?.try(&.as_i?)
          # Keep the type and the protocol class name in step: a peer's
          # `BatchTooLarge` rejection is as much a `BatchTooLargeError` as the
          # local pre-flight/byte checks above.
          raise BatchTooLargeError.new(message, status) if error_class == "BatchTooLarge"

          raise BridgeError.new(error_class, message, status)
        end
      end
    end
  end
end
