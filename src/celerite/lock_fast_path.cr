require "digest/sha256"
require "json"

require "./bridge/client"
require "./definition"
require "./eval_cache_store"
require "./eval_fingerprint"
require "./fast_path_store"
require "./profile"
require "./resolution"
require "./runtime_facts"

module Celerite
  # S8c of the M8 zero-Ruby slice (roadmap L164): a bare `lock` on a project
  # whose Gemfile evaluation is already proven deterministic may rewrite the
  # locked lockfile without loading Bundler and without starting Ruby.
  #
  # The provenance of every input, and why no bridge is needed:
  #
  # * the evaluation (dependencies, sources, warnings, bundler version) comes
  #   from an F4 entry under `CELERITE_CACHE_DIR`, written by an earlier run
  #   that *did* evaluate the Gemfile;
  # * the entry is accepted only when its own `entry.json` proves itself — the
  #   stored text hashes to the stored digest, every file in `verify.files` is
  #   re-hashed from disk (Gemfile, the whole `eval_gemfile` chain and every
  #   loaded gemspec), the recorded runtime records agree with the runtime
  #   record below, and the environment signature still matches;
  # * the runtime comes from `RuntimeFacts`, which reads this machine's
  #   rbconfig, and from the S8b record, which remembers what the interpreter
  #   reported when the evaluator last ran. `FastPathStore.decision` refuses
  #   `Allowed` unless the record belongs to this project, this credential
  #   namespace, this format version, and its seven fields and ABI agree.
  #
  # `engine`/`engine_version` are the one pair `RuntimeFacts` cannot rebuild
  # from the install tree (no rbconfig key names the engine). They are filled
  # from the record only under the CRuby invariants — `engine == "ruby"` and
  # `engine_version == RUBY_VERSION` — so the remaining check on them is a
  # consistency requirement, never a wildcard; the other five fields and the
  # ABI are still compared against the local rbconfig. This slice must not
  # change `FastPathStore` to make that easier (S8b pins a known field as a
  # requirement); it fills the two fields with `Source::Record` instead, which
  # keeps `decision` honest about where each value came from.
  #
  # The command-level gate is deliberately narrow: a bare `lock` only. Every
  # switch `lock` accepts (`--print`, `--lockfile`, `--update`/`--all`,
  # `--patch`/`--minor`/`--major`/`--strict`/`--conservative`/`--pre`,
  # `--add-platform`/`--remove-platform`, `--normalize-platforms`,
  # `--add-checksums`, `--local`, `--full-index`, `--bundler`, `--cooldown`)
  # either changes the bytes written or changes what is printed around them, so
  # it keeps the existing Ruby path; the gate is `rest.empty?`.
  module LockFastPath
    DEBUG_SWITCH = "CELERITE_FAST_PATH_DEBUG"

    # Gemfile source kinds whose spec set can be reproduced from the lockfile
    # and the cached evaluation alone. A PATH source needs a live
    # `load_gemspec_dir_specs` to reproduce `specs_for_source_changed?`, a GIT
    # source needs the checkout, and an installed plugin can change the DSL
    # itself — all three keep the Ruby path.
    REMOTE_SOURCE_TYPES = %w(Rubygems Metadata)

    # One validated hit: the entry digests the decision, the evaluation carries
    # the bytes `lock` writes, and `bundler_version` is the same
    # `evaluation.bundler_version` the Ruby path retargets `BUNDLED WITH` with.
    struct Hit
      getter digest : String
      getter bundler_version : String
      getter evaluation : Bridge::GemfileEvaluation
      getter record : FastPathStore::RuntimeRecord
      getter facts : RuntimeFacts::Facts
      getter lockfile_sha256 : String

      def initialize(@digest : String, @bundler_version : String,
                     @evaluation : Bridge::GemfileEvaluation,
                     @record : FastPathStore::RuntimeRecord,
                     @facts : RuntimeFacts::Facts,
                     @lockfile_sha256 : String)
      end
    end

    def self.debug? : Bool
      ENV[DEBUG_SWITCH]? == "1"
    end

    # Both switches are required. The fingerprint can only come from the
    # persistent evaluation cache (`CELERITE_EVAL_CACHE=1`) and the runtime
    # record only from the fast-path store (`CELERITE_FAST_PATH=1`); a
    # half-configured cache must never decide a lock.
    def self.enabled? : Bool
      FastPathStore.enabled? && EvalCacheStore.enabled?
    end

    # The directory the runtime record is keyed by: the Gemfile's directory,
    # which is also the base `verify.files` paths are resolved against.
    def self.project_root(definition : Definition) : String
      File.dirname(File.expand_path(definition.gemfile_path))
    end

    def self.detect_lock_identity(definition : Definition,
                                  path : String = definition.lockfile_path) : CacheIdentity::LockIdentity?
      CacheIdentity::LockIdentity.detect(path, project_root: project_root(definition))
    rescue
      nil
    end

    # `Bundler::Plugin.root` = `<app_config>/plugin`. Missing or empty means no
    # plugin can be loaded, which is the state the cached evaluation was proven
    # in. Install additionally accepts the project-local marker file when it is
    # a zero-byte ordinary `index`; `lock` retains the strict empty-root rule.
    # Anything else -- including a root we cannot read -- sends the command back
    # to Ruby: an unreadable directory is unknown, never "empty".
    private def self.plugin_root_absent?(definition : Definition, allow_zero_byte_index : Bool = false) : Bool
      plugin_root = File.join(Config.app_config_path(project_root(definition)), "plugin")
      return true unless File.exists?(plugin_root)
      return false unless File.directory?(plugin_root)
      children = Dir.children(plugin_root)
      return true if children.empty?
      return false unless allow_zero_byte_index && children.size == 1
      index = File.join(plugin_root, "index")
      return false unless File.join(plugin_root, children[0]) == index
      File.file?(index) && !File.symlink?(index) && File.size(index) == 0
    rescue
      false
    end

    # Returns `{hit, nil}` when the whole gate holds, otherwise `{nil, reason}`.
    # `reason` is a short stable token used by `CELERITE_FAST_PATH_DEBUG=1`;
    # `nil` means "not even considered" (the switches are off), which is the
    # ordinary case and must stay silent.
    def self.attempt(definition : Definition, rest : Array(String)) : {Hit?, String?}
      return {nil, nil} unless enabled?
      return {nil, "switches"} unless rest.empty?
      trusted_attempt(definition)
    end

    # The command-independent part of `attempt`: it assumes the switches are
    # on and the command's argument shape is already known to be safe. Both
    # `lock` and `install` call this one gate; command-specific checks stay in
    # their own modules so they cannot drift from the shared trust decision.
    def self.trusted_attempt(definition : Definition,
                             expected_command : String = "lock") : {Hit?, String?}
      return {nil, "no-lockfile"} unless definition.lockfile_exists?
      # The Ruby path computes this with `rest.includes?("--local")`; a bare
      # `lock` has no `--local`, so a missing or empty CHECKSUMS entry forces
      # its re-resolution and must do the same here.
      return {nil, "checksums"} unless definition.checksums_need_refresh?(false).nil?

      lock_identity = detect_lock_identity(definition)
      return {nil, "lock-format"} if lock_identity.nil?

      lockfile = definition.lockfile!
      local_platform = Gem::Platform.local.to_s
      return {nil, "platforms"} unless lockfile.platforms == [local_platform]

      # Nothing in the persisted entry records what is installed under the
      # plugin root: `verify.files` digests the Gemfile chain and the gemspecs,
      # and the evaluation config records the root's path only. A plugin
      # installed after the entry was written can still change the DSL the
      # Gemfile evaluates to (hooks, `plugin` sources, command registration), so
      # a populated root always means "this evaluation is stale" -- decided
      # locally, without starting Ruby.
      return {nil, "plugin-index"} unless plugin_root_absent?(definition, expected_command == "install")

      record = load_record(definition)
      return {nil, "record"} if record.nil?

      entry, document = find_entry(definition.gemfile_path, runtime_for(record))
      return {nil, "entry"} if entry.nil? || document.nil?

      evaluation = parse_evaluation(entry.not_nil!)
      return {nil, "evaluation"} if evaluation.nil?
      ev = evaluation.not_nil!

      # The Ruby path prints the evaluation's warnings once per command, and
      # also prints the dependency-API warning for scoped Rubygems sources. A
      # Gemfile that produces either cannot be reproduced byte-for-byte from
      # the entry alone, so it keeps the Ruby path.
      return {nil, "warnings"} unless ev.warnings.empty?
      return {nil, "sources"} unless remote_sources_only?(ev)

      return {nil, "dependencies"} unless definition.lockfile_matches_dependencies?(ev.dependencies)
      return {nil, "sources-changed"} if definition.dependency_sources_changed?(ev.dependencies, ev.sources)
      # `resolution.incomplete_locked_spec_names.empty?` — a locked row whose
      # own edges the lockfile cannot satisfy makes the reference re-resolve.
      return {nil, "incomplete"} unless Resolution.incomplete_locked_spec_names(definition).empty?

      facts = RuntimeFacts.detect
      return {nil, "facts"} if facts.nil?
      completed = complete_facts(facts.not_nil!, record.not_nil!)
      return {nil, "engine"} if completed.nil?

      verdict = FastPathStore.decision(project_root(definition), entry.not_nil!.digest,
        completed, record, EvalFingerprint::State::Deterministic,
        expected_command: expected_command, current_lock: lock_identity)
      return {nil, "verdict:#{verdict.reason}"} unless verdict.allowed?

      lock_digest = begin
        Digest::SHA256.hexdigest(File.read(definition.lockfile_path))
      rescue
        return {nil, "lock-read"}
      end

      {Hit.new(entry.not_nil!.digest, ev.bundler_version, ev, record.not_nil!,
        completed.not_nil!, lock_digest), nil}
    end

    # Writes the runtime record for this project after a successful Ruby-path
    # `lock`, so the next bare `lock` can take the fast path. Both switches
    # gate it, and every input is read back from disk: the deterministic
    # evaluation entry proves the seven recorded runtime fields, `RuntimeFacts`
    # proves what this machine's rbconfig says, and `record_from` refuses a
    # record whose two sources disagree. A guessed record is never written.
    def self.remember(definition : Definition) : Nil
      return unless enabled?
      facts = RuntimeFacts.detect
      return if facts.nil?

      entry, document = find_entry(definition.gemfile_path, nil)
      return if entry.nil? || document.nil?
      doc = document.not_nil!
      runtime = runtime_from_document(doc)
      return if runtime.nil?
      abi = abi_from_document(doc)
      return if abi.nil?

      record = FastPathStore.record_from(project_root(definition), facts, runtime, abi)
      return if record.nil?
      FastPathStore.store(record)
    rescue
      # Persistence is an optimization: a read-only home or a racing writer
      # must never change a `lock` result.
    end

    # A successful lock commits a command certificate before its RuntimeRecord.
    # The caller supplies the exact rendered SHA/size; the actual target is read
    # back only after the writer closed it. Any mismatch, exception, failed
    # certificate write, or failed record write leaves the prior nonce intact.
    # `lock --print` never calls this method.
    def self.remember_after_lock(definition : Definition, write_path : String,
                                 expected_sha256 : String,
                                 expected_byte_size : Int64) : Nil
      return unless enabled?
      actual = File.read(write_path)
      return unless Digest::SHA256.hexdigest(actual) == expected_sha256
      return unless actual.bytesize.to_i64 == expected_byte_size
      lock_identity = detect_lock_identity(definition, write_path)
      return if lock_identity.nil?

      facts = RuntimeFacts.detect
      return if facts.nil?
      ruby_identity = CacheIdentity::RubyIdentity.detect(facts.ruby_exe)
      return unless ruby_identity.known?

      entry, document = find_entry(definition.gemfile_path, nil)
      return if entry.nil? || document.nil?
      doc = document.not_nil!
      runtime = runtime_from_document(doc)
      return if runtime.nil?
      abi = abi_from_document(doc)
      return if abi.nil?

      nonce = CacheIdentity.nonce
      certificate = CacheIdentity::SuccessCertificate.new(
        CacheIdentity::CERTIFICATE, "lock", Profile.bundler_version,
        ruby_identity.identity_digest.not_nil!, lock_identity.not_nil!)
      return unless EvalCacheStore.put_certificate(entry.not_nil!.digest, nonce, certificate)

      record = FastPathStore.record_from(project_root(definition), facts, runtime, abi,
        Time.utc, ruby_identity, entry.not_nil!.digest, nonce)
      return if record.nil?
      FastPathStore.store(record)
    rescue
      # Persistence is best-effort and must never change command output/status.
    end

    # Install writes its runtime record only after a successful Ruby-path
    # install returns 0; a failed install therefore cannot leave a trusted
    # record behind. `remember` itself re-reads the evaluation entry and
    # local RuntimeFacts, so a half-written or non-deterministic entry stays
    # unused.
    def self.remember_after_install : Nil
      return unless enabled?
      remember(Definition.build)
    rescue
    end

    # `RuntimeFacts` cannot name the engine; the record can, and CRuby pins
    # `RUBY_ENGINE_VERSION == RUBY_VERSION`. Only under both invariants are the
    # two fields filled — as `Source::Record`, so `decision` still sees where
    # they came from — and every other field stays the locally rebuilt one.
    def self.complete_facts(facts : RuntimeFacts::Facts,
                            record : FastPathStore::RuntimeRecord) : RuntimeFacts::Facts?
      return nil unless record.engine == "ruby"
      ruby_version = facts.ruby_version
      return nil unless ruby_version.known?
      return nil unless record.engine_version == ruby_version.value

      RuntimeFacts::Facts.new(facts.ruby_exe, facts.ruby_version, facts.patchlevel,
        RuntimeFacts::Field.new(record.engine, RuntimeFacts::Source::Record),
        RuntimeFacts::Field.new(record.engine_version, RuntimeFacts::Source::Record),
        facts.rubygems_version, facts.bundler_version, facts.platform,
        facts.default_gem_dir, facts.abi,
        facts.ruby_api_version, facts.extension_api_version,
        facts.prefix, facts.libdir)
    end

    # The runtime the entry's own records must agree with. Using the record
    # (instead of `nil`) turns `verify` into a cross-check between two files
    # written by different runs, and still re-hashes every covered file.
    def self.runtime_for(record : FastPathStore::RuntimeRecord) : EvalFingerprint::Runtime
      EvalFingerprint::Runtime.new(record.ruby_version, record.patchlevel, record.engine,
        record.engine_version, record.rubygems_version, record.bundler_version,
        record.platform,
        EvalFingerprint::Abi.new(record.abi.ruby_api_version,
          record.abi.extension_api_version, record.abi.rbconfig_ruby_version))
    end

    private def self.load_record(definition : Definition) : FastPathStore::RuntimeRecord?
      path = FastPathStore.default_path(project_root(definition))
      return nil if path.nil?
      FastPathStore.load(path)
    end

    # Newest entry per Gemfile wins, exactly like `EvaluationCache.load_persisted`.
    # `runtime` is `nil` when the caller has no record yet (the writer): `verify`
    # then skips the runtime comparison but still re-hashes every file.
    private def self.find_entry(gemfile : String,
                                runtime : EvalFingerprint::Runtime?) : {EvalCacheStore::EntryFile?, EvalFingerprint::Document?}
      base = File.dirname(File.expand_path(gemfile))
      EvalCacheStore.read_all.each do |stored|
        next unless same_gemfile?(stored, gemfile)
        next unless environment_matches?(stored)
        document = document_for(stored)
        next if document.nil?
        next if document.not_nil!.verify(base, runtime)
        return {stored, document}
      end
      {nil, nil}
    end

    # An entry evaluated under another environment (`BUNDLE_WITHOUT`,
    # `BUNDLE_GEMFILE`, `BUNDLE_FROZEN`, ...) describes a different dependency
    # set. This is the same test the F4 reader applies, and it is what keeps a
    # `BUNDLE_WITHOUT` run from reusing a full-lock evaluation.
    private def self.environment_matches?(stored : EvalCacheStore::EntryFile) : Bool
      declared = stored.json["env"]?
      return false if declared.nil?
      declared.as_s? == Bridge::EvaluationCache.environment_signature
    end

    private def self.same_gemfile?(stored : EvalCacheStore::EntryFile, gemfile : String) : Bool
      recorded = stored.json["evaluation"]?.try(&.as_h?)
        .try { |node| node["gemfile"]? }.try(&.as_s?)
      return false if recorded.nil?
      File.expand_path(recorded) == File.expand_path(gemfile)
    end

    # A stored fingerprint is usable only when it is well-formed, still hashes
    # to its directory name and calls itself deterministic. Anything else is a
    # miss here; deleting a stale entry stays `EvaluationCache`'s job.
    private def self.document_for(stored : EvalCacheStore::EntryFile) : EvalFingerprint::Document?
      node = stored.json["fingerprint"]?.try(&.as_h?)
      return nil if node.nil?
      text = node["text"]?.try(&.as_s?)
      digest = node["digest"]?.try(&.as_s?)
      verify = node["verify"]?
      return nil if text.nil? || digest.nil? || verify.nil?
      return nil unless digest == stored.digest
      return nil unless EvalFingerprint::State.parse(node["state"]?.try(&.as_s?)).deterministic?
      EvalFingerprint::Document.parse(text, digest, verify)
    end

    private def self.parse_evaluation(stored : EvalCacheStore::EntryFile) : Bridge::GemfileEvaluation?
      node = stored.json["evaluation"]?
      return nil if node.nil?
      Bridge::GemfileEvaluation.from_json(node.to_json)
    rescue
      nil
    end

    private def self.remote_sources_only?(evaluation : Bridge::GemfileEvaluation) : Bool
      declared = evaluation.dependencies.compact_map(&.source)
      return false unless declared.all? { |source| REMOTE_SOURCE_TYPES.includes?(source.type) }
      evaluation.sources.all? { |source| REMOTE_SOURCE_TYPES.includes?(source.type) }
    end

    private def self.runtime_from_document(document : EvalFingerprint::Document) : EvalFingerprint::Runtime?
      values = {} of String => String
      {"ruby.version", "ruby.patchlevel", "ruby.engine", "ruby.engine_version",
       "rubygems.version", "bundler.version", "platform"}.each do |key|
        value = document.records[key]?
        return nil if value.nil? || value.empty?
        values[key] = value
      end
      EvalFingerprint::Runtime.new(values["ruby.version"], values["ruby.patchlevel"],
        values["ruby.engine"], values["ruby.engine_version"],
        values["rubygems.version"], values["bundler.version"], values["platform"],
        abi_from_document(document))
    end

    private def self.abi_from_document(document : EvalFingerprint::Document) : EvalFingerprint::Abi?
      api = document.records["abi.ruby_api_version"]?
      extension = document.records["abi.extension_api_version"]?
      rbconfig = document.records["abi.rbconfig_ruby_version"]?
      source = document.records["abi.source"]?
      return nil if api.nil? || extension.nil? || rbconfig.nil? || source.nil?
      return nil if api.empty? || extension.empty? || rbconfig.empty?
      EvalFingerprint::Abi.new(api, extension, rbconfig, source)
    end
  end
end
