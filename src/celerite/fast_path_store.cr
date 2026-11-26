require "digest/sha256"
require "json"
require "random/secure"

require "./config"
require "./eval_cache_store"
require "./eval_fingerprint"
require "./runtime_facts"

module Celerite
  # M8 slice S8b (roadmap L164): the two durable inputs the zero-Ruby fast path
  # needs, and the decision that consumes them.
  #
  # S8a's `RuntimeFacts` reconstructs five of the seven
  # `EvalFingerprint::Runtime` fields from the interpreter's build files but
  # cannot supply `engine`/`engine_version` (`runtime_facts.cr:27-35`) and cannot
  # prove the values it did read belong to the Ruby the last bridge actually
  # ran. This slice closes that gap from the other direction: the bridge's
  # `op_ruby_environment` response is a *recorded* observation, stored under
  # `<CELERITE_CACHE_DIR>/fast-path/v1/<namespace>/<sha256(project)>.json`, and
  # a later command may only skip Ruby when the fresh `Facts` agree with that
  # record field by field.
  #
  # Three deliberate non-goals, because S8c/S8d/S8e own them:
  #
  # * nothing here is wired into `lock`/`install`: no command reads this module,
  #   so every command's stdout/stderr/exit/procs are unchanged. With the
  #   switch dark the module is simply dead code;
  # * no install-plan cache (that is L165) and no lockfile snapshot: the record
  #   carries runtime facts only;
  # * `decision` is structural. `Allowed` means "every recorded input is known,
  #   well-formed, from this project and agrees with the fresh facts"; whether a
  #   later slice may actually skip the bridge also needs the lockfile/DSL/
  #   plugin evidence that slice will check.
  #
  # Engineering follows `eval_cache_store.cr`: opt-in switch (`CELERITE_FAST_PATH=1`,
  # exactly that value), same `CELERITE_CACHE_DIR` root, same credential
  # namespace hash, same-directory temp + rename, and "corruption is a miss,
  # never an error". The namespace is a SHA-256 prefix over credential-bearing
  # `BUNDLE_*` pairs; no plaintext credential, and no `://user:pass@` string, is
  # ever written.
  module FastPathStore
    FORMAT        = "celerite-fast-path/2"
    LEGACY_FORMAT = "celerite-fast-path/1"
    SWITCH        = "CELERITE_FAST_PATH"
    ROOT_ENV      = "CELERITE_CACHE_DIR"
    LAYOUT        = "fast-path/v2"
    DIRECTORY     = ".celerite"
    SUFFIX        = ".json"

    DIGEST    = /\A[0-9a-f]{64}\z/
    NAMESPACE = /\A[0-9a-f]{16}\z/

    # Fixed evaluation order. `decision` reports the first unknown or mismatched
    # field in this order, so a reason string is stable across runs and can be
    # asserted verbatim.
    FIELDS = %w[
      ruby_version patchlevel engine engine_version rubygems_version
      bundler_version platform
    ]

    # The Ruby ABI as the bridge reported it (`Gem.ruby_api_version`,
    # `Gem.extension_api_version`, `RbConfig::CONFIG["ruby_version"]`), matching
    # `EvalFingerprint::Abi` minus its `source` tag: a record only ever stores
    # real values, so the tag would always be `"real"` and is dropped.
    struct Abi
      include JSON::Serializable

      getter ruby_api_version : String
      getter extension_api_version : String
      getter rbconfig_ruby_version : String

      def initialize(@ruby_api_version : String,
                     @extension_api_version : String,
                     @rbconfig_ruby_version : String)
      end

      def complete? : Bool
        ![@ruby_api_version, @extension_api_version, @rbconfig_ruby_version].any?(&.empty?)
      end
    end

    # One recorded observation of a Ruby installation. Every value came from a
    # process that actually ran (`op_ruby_environment`) or from an install-tree
    # file `RuntimeFacts` read; `record_from` refuses to build one otherwise.
    #
    # `project_digest` is `sha256(File.expand_path(project_root))`, never the
    # path itself: the record is per project but does not need to spell out a
    # user directory. `credential_namespace` is the same 16-hex hash
    # `EvalCacheStore.namespace` uses, so records written under different
    # `BUNDLE_*` credential contexts never see each other.
    struct RuntimeRecord
      include JSON::Serializable

      getter format : String
      getter written_at : String
      getter project_digest : String
      getter credential_namespace : String
      getter ruby_version : String
      getter patchlevel : String
      getter engine : String
      getter engine_version : String
      getter platform : String
      getter rubygems_version : String
      getter bundler_version : String
      getter abi : Abi
      getter ruby_identity : CacheIdentity::RubyIdentity
      getter eval_digest : String
      getter certificate_nonce : String

      KEYS = %w[format written_at project_digest credential_namespace ruby_version patchlevel engine engine_version platform rubygems_version bundler_version abi ruby_identity eval_digest certificate_nonce]

      def initialize(@format : String, @written_at : String,
                     @project_digest : String, @credential_namespace : String,
                     @ruby_version : String, @patchlevel : String,
                     @engine : String, @engine_version : String,
                     @platform : String, @rubygems_version : String,
                     @bundler_version : String, @abi : Abi,
                     @ruby_identity : CacheIdentity::RubyIdentity,
                     @eval_digest : String, @certificate_nonce : String)
      end

      def self.from_json(string : String) : self
        object = JSON.parse(string)
        raise CacheIdentity.parse_error("runtime record has unknown fields") unless CacheIdentity.exact_keys?(object, KEYS)
        raise CacheIdentity.parse_error("runtime record is missing fields") unless CacheIdentity.required_keys?(object, KEYS)
        new(CacheIdentity.string(object, "format"), CacheIdentity.string(object, "written_at"),
          CacheIdentity.string(object, "project_digest"), CacheIdentity.string(object, "credential_namespace"),
          CacheIdentity.string(object, "ruby_version"), CacheIdentity.string(object, "patchlevel"),
          CacheIdentity.string(object, "engine"), CacheIdentity.string(object, "engine_version"),
          CacheIdentity.string(object, "platform"), CacheIdentity.string(object, "rubygems_version"),
          CacheIdentity.string(object, "bundler_version"), Abi.from_json(object["abi"].to_json),
          CacheIdentity::RubyIdentity.parse(object["ruby_identity"]),
          CacheIdentity.string(object, "eval_digest"), CacheIdentity.string(object, "certificate_nonce"))
      end

      def complete? : Bool
        @format == FORMAT && !@written_at.empty? &&
          @project_digest.matches?(DIGEST) &&
          @credential_namespace.matches?(NAMESPACE) &&
          !@ruby_version.empty? && !@patchlevel.empty? &&
          !@engine.empty? && !@engine_version.empty? &&
          !@platform.empty? && !@rubygems_version.empty? &&
          !@bundler_version.empty? && @abi.complete? &&
          @ruby_identity.known? && @eval_digest.matches?(DIGEST) &&
          CacheIdentity.valid_nonce?(@certificate_nonce)
      end
    end

    # The tri-state answer S8c will branch on.
    #
    # * `Allowed` — every input is known, well-formed, belongs to this project
    #   and agrees with the fresh facts.
    # * `RequiresRuby(reason)` — a definite, stable reason forces the
    #   compatibility path. `reason` is a short ASCII token (plus, for field
    #   problems, a `:` and the field name) so a spec can assert it verbatim.
    # * `Unknown` — a required input was not supplied at all (`facts` or the
    #   fingerprint state is `nil`). It is never `Allowed`; the caller must
    #   treat it as "cannot decide" rather than "safe".
    struct Verdict
      enum Kind
        Allowed
        RequiresRuby
        Unknown
      end

      getter kind : Kind
      getter reason : String?

      private def initialize(@kind : Kind, @reason : String?)
      end

      def self.allowed : Verdict
        new(Kind::Allowed, nil)
      end

      def self.requires_ruby(reason : String) : Verdict
        new(Kind::RequiresRuby, reason)
      end

      def self.unknown : Verdict
        new(Kind::Unknown, nil)
      end

      def allowed? : Bool
        @kind == Kind::Allowed
      end

      def requires_ruby? : Bool
        @kind == Kind::RequiresRuby
      end

      def unknown? : Bool
        @kind == Kind::Unknown
      end

      def to_s(io : IO) : Nil
        case @kind
        in Kind::Allowed      then io << "Allowed"
        in Kind::RequiresRuby then io << "RequiresRuby(" << @reason << ')'
        in Kind::Unknown      then io << "Unknown"
        end
      end
    end

    def self.enabled? : Bool
      ENV[SWITCH]? == "1"
    end

    # `CELERITE_CACHE_DIR` wins; otherwise `$HOME/.celerite/cache`, the root F4
    # already uses. No home directory means no persistence, never the project
    # working directory.
    def self.root : String?
      if override = ENV[ROOT_ENV]?
        return nil if override.empty?
        return File.expand_path(override)
      end
      home = Config.user_home
      return nil if home.nil? || home.empty?
      File.expand_path(File.join(home, DIRECTORY, "cache"))
    end

    def self.layout_dir : String?
      base = root
      return nil if base.nil?
      File.join(base, LAYOUT)
    end

    def self.project_digest(project_root : String) : String
      Digest::SHA256.hexdigest(File.expand_path(project_root))
    end

    # The record location this slice would use. `nil` while the switch is dark,
    # so `store` cannot write until an operator opts in.
    def self.default_path(project_root : String) : String?
      return nil unless enabled?
      path_for(project_digest(project_root))
    end

    def self.path_for(digest : String) : String?
      dir = layout_dir
      return nil if dir.nil? || !digest.matches?(DIGEST)
      File.join(dir, EvalCacheStore.namespace, "#{digest}#{SUFFIX}")
    end

    # Reads one record. Anything that does not prove itself — unreadable file,
    # truncated or corrupt JSON, unknown format version, missing/empty fields,
    # malformed digest or namespace — is a miss *and deletes the file*, so a
    # half-written record cannot be retried forever.
    def self.load(path : String) : RuntimeRecord?
      record = parse(path)
      # Only a path this store owns is deleted on failure; a caller that hands
      # in some other file must not lose it to a typo.
      discard(path) if record.nil? && path.ends_with?(SUFFIX)
      record
    end

    # Writes `record` atomically. The switch gates every write, including an
    # explicit `path`; `load`/`decision` stay pure reads so a later slice can
    # inspect state without turning persistence on.
    def self.store(record : RuntimeRecord, path : String? = nil) : Bool
      return false unless enabled?
      target = path || path_for(record.project_digest)
      return false if target.nil?
      return false unless record.complete?
      write_atomic(target, record.to_json + "\n")
    end

    # Merges the two honest sources into one record. A field known to
    # `RuntimeFacts` (`Source != Unknown`) is used directly; a field it cannot
    # know (`engine`/`engine_version`) is taken from the bridge's last
    # `op_ruby_environment` response. If the two disagree, if neither supplies
    # a field, or if no real ABI is available, the result is `nil`: a record is
    # never filled with a guess.
    def self.record_from(project_root : String,
                         facts : RuntimeFacts::Facts?,
                         bridge : EvalFingerprint::Runtime? = nil,
                         abi : EvalFingerprint::Abi? = nil,
                         written_at : Time = Time.utc,
                         ruby_identity : CacheIdentity::RubyIdentity? = nil,
                         eval_digest : String? = nil,
                         certificate_nonce : String? = nil) : RuntimeRecord?
      # Facts carry their own conservative identity. An explicit identity may
      # be supplied by a trusted caller, but it must describe the same Ruby.
      identity = ruby_identity || facts.try(&.ruby_identity)
      if facts_identity = facts.try(&.ruby_identity)
        return nil if facts_identity.known? && identity.try(&.identity_digest) != facts_identity.identity_digest
      end
      # Old callers cannot mint a v2 success proof. Until task-273 supplies the
      # certificate nonce, preserve the source API but never write an unbound
      # record.
      return nil if identity.nil? || eval_digest.nil? || certificate_nonce.nil?
      return nil unless identity.known?
      return nil unless eval_digest.matches?(DIGEST)
      return nil unless CacheIdentity.valid_nonce?(certificate_nonce)
      return nil if project_root.empty?
      real_abi = abi || bridge.try(&.abi)
      return nil if real_abi.nil?
      # A "real" tag without three concrete values proves nothing; an older
      # bridge that omits the ABI fields cannot seed a record.
      if real_abi.ruby_api_version.empty? ||
         real_abi.extension_api_version.empty? ||
         real_abi.rbconfig_ruby_version.empty?
        return nil
      end

      if facts
        local = facts.not_nil!
        return nil unless local.ruby_api_version.known? &&
                          local.ruby_api_version.value == real_abi.ruby_api_version
        return nil unless local.extension_api_version.known? &&
                          local.extension_api_version.value == real_abi.extension_api_version
        return nil unless local.abi.known? &&
                          local.abi.value == real_abi.rbconfig_ruby_version
      end

      values = {} of String => String
      FIELDS.each do |name|
        local = facts.try { |f| field_of(f, name) }
        recorded = bridge.try { |b| value_of(b, name) }
        if local.try(&.known?)
          value = local.not_nil!.value.not_nil!
          return nil if recorded && recorded != value
          values[name] = value
        elsif recorded
          values[name] = recorded
        else
          return nil
        end
      end

      RuntimeRecord.new(FORMAT, written_at.to_s("%FT%TZ"),
        project_digest(project_root), EvalCacheStore.namespace,
        values["ruby_version"], values["patchlevel"],
        values["engine"], values["engine_version"],
        values["platform"], values["rubygems_version"],
        values["bundler_version"],
        Abi.new(real_abi.ruby_api_version, real_abi.extension_api_version,
          real_abi.rbconfig_ruby_version), identity.not_nil!, eval_digest.not_nil!,
        certificate_nonce.not_nil!)
    end

    # The structural verdict (see `Verdict`). Checks run in a fixed order, so
    # the same inputs always produce the same reason:
    #
    # 1. `nil` facts or state -> `Unknown`;
    # 2. empty project root / non-hex digest -> `project-invalid` /
    #    `digest-invalid`;
    # 3. fingerprint state must be `deterministic`;
    # 4. the record must exist, carry this format version, belong to this
    #    project and this credential namespace, and be complete;
    # 5. the seven runtime fields must be known to `Facts` and equal the
    #    record, in `FIELDS` order;
    # 6. the three ABI views must be known to `Facts` and equal the record's
    #    `ruby_api_version`, `extension_api_version` and
    #    `rbconfig_ruby_version` respectively.
    #
    # Any deviation returns `RequiresRuby`, never `Allowed`; an unknown field
    # is a mismatch, never a wildcard.
    def self.decision(project_root : String,
                      digest : String,
                      facts : RuntimeFacts::Facts?,
                      record : RuntimeRecord?,
                      state : EvalFingerprint::State?,
                      fresh_identity : CacheIdentity::RubyIdentity? = nil) : Verdict
      return Verdict.unknown if facts.nil?
      return Verdict.unknown if state.nil?

      return Verdict.requires_ruby("project-invalid") if project_root.empty?
      return Verdict.requires_ruby("digest-invalid") unless digest.matches?(DIGEST)

      # Only a deterministic evaluation event may be reused; the two other
      # states mean the fingerprint itself is not trustworthy.
      return Verdict.requires_ruby("fingerprint-unknown") if state == EvalFingerprint::State::Unknown
      return Verdict.requires_ruby("fingerprint-broken") if state == EvalFingerprint::State::Broken

      return Verdict.requires_ruby("record-missing") if record.nil?
      rec = record.not_nil!
      return Verdict.requires_ruby("record-format") unless rec.format == FORMAT
      return Verdict.requires_ruby("record-incomplete") unless rec.complete?
      return Verdict.requires_ruby("project-mismatch") unless rec.project_digest == project_digest(project_root)

      namespace = EvalCacheStore.namespace
      unless rec.credential_namespace == namespace
        return Verdict.requires_ruby("namespace-mismatch")
      end

      return Verdict.requires_ruby("eval-digest-mismatch") unless rec.eval_digest == digest
      identity = fresh_identity || CacheIdentity::RubyIdentity.detect(facts.ruby_exe)
      return Verdict.requires_ruby("ruby-identity-unknown") unless identity.known?
      return Verdict.requires_ruby("ruby-identity-mismatch") unless identity.identity_digest == rec.ruby_identity.identity_digest
      certificate = EvalCacheStore.certificate(digest, rec.certificate_nonce)
      # Legacy /1 evaluations, v2 entries without this nonce, and malformed
      # certificates all land here; an evaluation alone is never success proof.
      return Verdict.requires_ruby("lock-unbound") if certificate.nil?
      cert = certificate.not_nil!
      return Verdict.requires_ruby("certificate-command") unless %w[lock install].includes?(cert.command)
      return Verdict.requires_ruby("certificate-ruby-identity") unless cert.ruby_identity == identity.identity_digest

      pairs = {
        {name: "ruby_version", local: facts.ruby_version, recorded: rec.ruby_version},
        {name: "patchlevel", local: facts.patchlevel, recorded: rec.patchlevel},
        {name: "engine", local: facts.engine, recorded: rec.engine},
        {name: "engine_version", local: facts.engine_version, recorded: rec.engine_version},
        {name: "rubygems_version", local: facts.rubygems_version, recorded: rec.rubygems_version},
        {name: "bundler_version", local: facts.bundler_version, recorded: rec.bundler_version},
        {name: "platform", local: facts.platform, recorded: rec.platform},
      }
      pairs.each do |pair|
        unless pair[:local].known?
          return Verdict.requires_ruby("facts-unknown:#{pair[:name]}")
        end
        unless pair[:local].value == pair[:recorded]
          return Verdict.requires_ruby("facts-mismatch:#{pair[:name]}")
        end
      end

      abi_pairs = {
        {name: "ruby_api_version", local: facts.ruby_api_version, recorded: rec.abi.ruby_api_version},
        {name: "extension_api_version", local: facts.extension_api_version, recorded: rec.abi.extension_api_version},
        {name: "rbconfig_ruby_version", local: facts.abi, recorded: rec.abi.rbconfig_ruby_version},
      }
      abi_pairs.each do |pair|
        unless pair[:local].known?
          return Verdict.requires_ruby("facts-unknown:#{pair[:name]}")
        end
        unless pair[:local].value == pair[:recorded]
          return Verdict.requires_ruby("facts-mismatch:#{pair[:name]}")
        end
      end

      Verdict.allowed
    end

    # Byte-level removal. Never raises: a missing or locked file is already a
    # miss, and cleanup must not fail a command.
    def self.discard(path : String) : Nil
      File.delete(path) if File.file?(path)
    rescue
    end

    private def self.parse(path : String) : RuntimeRecord?
      return nil unless File.file?(path)
      record = RuntimeRecord.from_json(File.read(path))
      record.complete? ? record : nil
    rescue
      nil
    end

    private def self.write_atomic(target : String, payload : String) : Bool
      dir = File.dirname(target)
      temp = File.join(dir, ".#{File.basename(target, SUFFIX)}-#{Process.pid}-#{Random::Secure.hex(4)}.tmp")
      begin
        Dir.mkdir_p(dir)
        File.open(temp, "w") do |file|
          file.print(payload)
          file.flush
          begin
            file.fsync
          rescue
          end
        end
        # Windows MoveFileExW uses REPLACE_EXISTING here.  The old record stays
        # visible until the complete replacement is atomically installed.
        File.rename(temp, target)
        true
      rescue
        begin
          File.delete(temp) if File.exists?(temp)
        rescue
        end
        false
      end
    end

    private def self.field_of(facts : RuntimeFacts::Facts, name : String) : RuntimeFacts::Field
      case name
      when "ruby_version"     then facts.ruby_version
      when "patchlevel"       then facts.patchlevel
      when "engine"           then facts.engine
      when "engine_version"   then facts.engine_version
      when "rubygems_version" then facts.rubygems_version
      when "bundler_version"  then facts.bundler_version
      when "platform"         then facts.platform
      else                         RuntimeFacts::Field.new(nil, RuntimeFacts::Source::Unknown)
      end
    end

    private def self.value_of(runtime : EvalFingerprint::Runtime, name : String) : String
      case name
      when "ruby_version"     then runtime.ruby_version
      when "patchlevel"       then runtime.patchlevel
      when "engine"           then runtime.engine
      when "engine_version"   then runtime.engine_version
      when "rubygems_version" then runtime.rubygems_version
      when "bundler_version"  then runtime.bundler_version
      when "platform"         then runtime.platform
      else                         ""
      end
    end
  end
end
