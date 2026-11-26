require "./spec_helper"
require "digest/sha256"

# M8 task-252 (roadmap L164, slice S8b): the zero-Ruby fast path needs a durable
# observation of the runtime it is allowed to trust, plus a structural decision
# that refuses to answer `Allowed` from partial evidence.
#
# These specs pin the boundaries this slice must hold:
#   * a record round-trips field by field;
#   * an unknown format version, a truncated JSON body, or an I/O failure is a
#     silent miss that deletes the file and never raises;
#   * the switch is dark by default and gates every write;
#   * `decision` yields `Allowed` only for a complete record of *this* project
#     whose seven runtime fields and ABI agree with the fresh facts, and
#     `RequiresRuby(<stable reason>)` for every other shape;
#   * `record_from` never fills a field it cannot prove;
#   * credentials reach the disk only as a namespace hash;
#   * the whole module is pure file I/O: zero processes, zero RPCs.
private M8_FP_ENV = %w[
  HOME USERPROFILE CELERITE_RUBY CELERITE_CACHE_DIR CELERITE_FAST_PATH CELERITE_BRIDGE_STATS
  BUNDLE_GEMS__EXAMPLE__COM BUNDLE_GEMFILE BUNDLE_APP_CONFIG
]

private def m8_fp_with(switch : String? = "1", & : {String, String} ->) : Nil
  with_project({} of String => String) do |project|
    saved = {} of String => String?
    M8_FP_ENV.each { |name| saved[name] = ENV[name]? }
    cache = File.join(project, "cache")
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["CELERITE_CACHE_DIR"] = cache
    ENV.delete("BUNDLE_GEMS__EXAMPLE__COM")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("BUNDLE_APP_CONFIG")
    ENV.delete("CELERITE_BRIDGE_STATS")
    fake_bin = File.join(project, ".ruby", "bin")
    fake_rbconfig = File.join(project, ".ruby", "lib", "ruby", "9.9.0", "fake-arch")
    Dir.mkdir_p(fake_bin)
    Dir.mkdir_p(fake_rbconfig)
    File.write(File.join(fake_bin, "ruby.exe"), "synthetic-ruby")
    File.write(File.join(fake_rbconfig, "rbconfig.rb"), "# synthetic layout\n")
    ENV["CELERITE_RUBY"] = File.join(fake_bin, "ruby.exe")
    if switch
      ENV["CELERITE_FAST_PATH"] = switch
    else
      ENV.delete("CELERITE_FAST_PATH")
    end
    begin
      yield({project, cache})
    ensure
      saved.each do |name, value|
        if value
          ENV[name] = value
        else
          ENV.delete(name)
        end
      end
    end
  end
end

private def m8_fp_abi(ruby_api : String = "4.0.0", extension : String = "4.0.0",
                      rbconfig : String = "4.0.0") : Celerite::FastPathStore::Abi
  Celerite::FastPathStore::Abi.new(ruby_api, extension, rbconfig)
end

private def m8_fp_identity(project : String) : Celerite::CacheIdentity::RubyIdentity
  Celerite::CacheIdentity::RubyIdentity.detect(File.join(project, ".ruby", "bin", "ruby.exe"))
end

private def m8_fp_record(project : String, *,
                         ruby_version : String = "4.0.6",
                         patchlevel : String = "0",
                         engine : String = "ruby",
                         engine_version : String = "4.0.6",
                         platform : String = "x64-mingw-ucrt",
                         rubygems_version : String = "4.0.16",
                         bundler_version : String = "4.0.24",
                         abi : Celerite::FastPathStore::Abi = m8_fp_abi,
                         format : String = Celerite::FastPathStore::FORMAT,
                         namespace : String = Celerite::EvalCacheStore.namespace,
                         written_at : String = "2026-11-24T05:00:00Z",
                         project_digest : String? = nil,
                         ruby_identity : Celerite::CacheIdentity::RubyIdentity = m8_fp_identity(project),
                         eval_digest : String = m8_fp_digest(project),
                         certificate_nonce : String = "11111111111111111111111111111111") : Celerite::FastPathStore::RuntimeRecord
  Celerite::FastPathStore::RuntimeRecord.new(format, written_at,
    project_digest || Celerite::FastPathStore.project_digest(project), namespace,
    ruby_version, patchlevel, engine, engine_version, platform,
    rubygems_version, bundler_version, abi, ruby_identity, eval_digest, certificate_nonce)
end

private def m8_fp_bind(_project : String, record : Celerite::FastPathStore::RuntimeRecord) : Nil
  lock = Celerite::CacheIdentity::LockIdentity.new("Gemfile.lock", "a" * 64, 1_i64,
    "lf", "parser-1", "bundler-4", "b" * 64, ["x64-mingw-ucrt"])
  certificate = Celerite::CacheIdentity::SuccessCertificate.new(
    Celerite::CacheIdentity::CERTIFICATE, "lock", "default",
    record.ruby_identity.identity_digest.not_nil!, lock)
  payload = %({"format":"celerite-eval-cache/2","digest":"#{record.eval_digest}","evaluation":{},"certificates":{}})
  raise "failed to seed evaluation" unless Celerite::EvalCacheStore.write(record.eval_digest, payload)
  raise "failed to seed certificate" unless Celerite::EvalCacheStore.put_certificate(
                                              record.eval_digest, record.certificate_nonce, certificate)
end

private def m8_fp_field(value : String?) : Celerite::RuntimeFacts::Field
  if value.nil?
    Celerite::RuntimeFacts::Field.new(nil, Celerite::RuntimeFacts::Source::Unknown)
  else
    Celerite::RuntimeFacts::Field.new(value, Celerite::RuntimeFacts::Source::Rbconfig)
  end
end

# Synthetic facts: every field is a literal this spec chose, so the assertions
# below never depend on the host Ruby. `nil` means "the install tree cannot
# tell", exactly like `engine`/`engine_version` from a real `RuntimeFacts.detect`.
private def m8_fp_facts(*, ruby_version : String? = "4.0.6",
                        patchlevel : String? = "0",
                        engine : String? = "ruby",
                        engine_version : String? = "4.0.6",
                        platform : String? = "x64-mingw-ucrt",
                        rubygems_version : String? = "4.0.16",
                        bundler_version : String? = "4.0.24",
                        abi : String? = "4.0.0",
                        ruby_api_version : String? = "4.0.0",
                        extension_api_version : String? = "4.0.0") : Celerite::RuntimeFacts::Facts
  Celerite::RuntimeFacts::Facts.new(ENV["CELERITE_RUBY"]? || "C:/Ruby40-x64/bin/ruby.exe",
    m8_fp_field(ruby_version), m8_fp_field(patchlevel),
    m8_fp_field(engine), m8_fp_field(engine_version),
    m8_fp_field(rubygems_version), m8_fp_field(bundler_version),
    m8_fp_field(platform), m8_fp_field("C:/Ruby40-x64/lib/ruby/gems/4.0.0"),
    m8_fp_field(abi), m8_fp_field(ruby_api_version),
    m8_fp_field(extension_api_version),
    m8_fp_field("C:/Ruby40-x64"),
    m8_fp_field("C:/Ruby40-x64/lib"))
end

private def m8_fp_deterministic : Celerite::EvalFingerprint::State
  Celerite::EvalFingerprint::State::Deterministic
end

private def m8_fp_digest(project : String) : String
  Digest::SHA256.hexdigest("fingerprint:#{project}")
end

private def m8_fp_walk(directory : String) : Array(String)
  files = [] of String
  return files unless Dir.exists?(directory)
  Dir.each_child(directory) do |child|
    path = File.join(directory, child)
    if File.directory?(path)
      files.concat(m8_fp_walk(path))
    else
      files << path
    end
  end
  files.sort!
end

describe Celerite::FastPathStore do
  it "round-trips a record field by field" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      path = Celerite::FastPathStore.default_path(project).not_nil!
      Celerite::FastPathStore.store(record).should be_true
      File.file?(path).should be_true

      body = File.read(path)
      body.starts_with?("{").should be_true
      body.ends_with?("\n").should be_true
      body.to_slice[0].should_not eq(0xEF_u8) # no UTF-8 BOM
      body[0..-2].includes?('\n').should be_false

      loaded = Celerite::FastPathStore.load(path).not_nil!
      loaded.format.should eq(Celerite::FastPathStore::FORMAT)
      loaded.written_at.should eq("2026-11-24T05:00:00Z")
      loaded.project_digest.should eq(Celerite::FastPathStore.project_digest(project))
      loaded.credential_namespace.should eq(record.credential_namespace)
      loaded.ruby_version.should eq("4.0.6")
      loaded.patchlevel.should eq("0")
      loaded.engine.should eq("ruby")
      loaded.engine_version.should eq("4.0.6")
      loaded.platform.should eq("x64-mingw-ucrt")
      loaded.rubygems_version.should eq("4.0.16")
      loaded.bundler_version.should eq("4.0.24")
      loaded.abi.ruby_api_version.should eq("4.0.0")
      loaded.abi.extension_api_version.should eq("4.0.0")
      loaded.abi.rbconfig_ruby_version.should eq("4.0.0")

      # Same-directory temp + rename leaves no partial file behind.
      m8_fp_walk(Celerite::FastPathStore.layout_dir.not_nil!)
        .select { |file| file.ends_with?(".tmp") }.should be_empty
    end
  end

  it "treats an unknown format version as a miss and deletes the record" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      path = Celerite::FastPathStore.default_path(project).not_nil!
      Dir.mkdir_p(File.dirname(path))
      File.write(path, record.to_json.sub(Celerite::FastPathStore::FORMAT, "celerite-fast-path/3"))

      Celerite::FastPathStore.load(path).should be_nil
      File.exists?(path).should be_false
    end
  end

  it "treats a truncated or corrupt JSON body as a miss and deletes it" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      path = Celerite::FastPathStore.default_path(project).not_nil!
      Dir.mkdir_p(File.dirname(path))

      File.write(path, record.to_json[0, 40])
      Celerite::FastPathStore.load(path).should be_nil
      File.exists?(path).should be_false

      File.write(path, "not json at all\n")
      Celerite::FastPathStore.load(path).should be_nil
      File.exists?(path).should be_false

      # A structurally valid JSON with missing required fields is corrupt too.
      File.write(path, %({"format":"celerite-fast-path/1"}
))
      Celerite::FastPathStore.load(path).should be_nil
      File.exists?(path).should be_false
    end
  end

  it "silently misses when the record directory cannot be created" do
    m8_fp_with do |project, _cache|
      blocker = File.join(project, "blocker")
      File.write(blocker, "")
      ENV["CELERITE_CACHE_DIR"] = blocker

      Celerite::FastPathStore.store(m8_fp_record(project)).should be_false
      File.file?(blocker).should be_true

      # A path that is not a regular file is a miss, not an exception.
      Celerite::FastPathStore.load(blocker).should be_nil
      File.file?(blocker).should be_true
    end
  end

  it "stays dark by default and writes nothing while the switch is off" do
    m8_fp_with(switch: nil) do |project, cache|
      Celerite::FastPathStore.enabled?.should be_false
      Celerite::FastPathStore.default_path(project).should be_nil
      Celerite::FastPathStore.store(m8_fp_record(project)).should be_false
      Dir.exists?(cache).should be_false
    end

    m8_fp_with(switch: "0") do |project, cache|
      Celerite::FastPathStore.enabled?.should be_false
      Celerite::FastPathStore.store(m8_fp_record(project)).should be_false
      Dir.exists?(cache).should be_false
    end
  end

  it "allows the fast path only when record, facts and fingerprint all agree" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      verdict = Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), m8_fp_facts, record, m8_fp_deterministic)
      verdict.allowed?.should be_true
      verdict.to_s.should eq("Allowed")
    end
  end

  it "requires Ruby with reason record-missing when the record is absent" do
    m8_fp_with do |project, _cache|
      # The signature case from S8a: Facts cannot supply engine/engine_version.
      facts = m8_fp_facts(engine: nil, engine_version: nil)
      verdict = Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), facts, nil, m8_fp_deterministic)
      verdict.requires_ruby?.should be_true
      verdict.reason.should eq("record-missing")
      verdict.to_s.should eq("RequiresRuby(record-missing)")
    end
  end

  it "requires Ruby for every non-deterministic fingerprint state" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      digest = m8_fp_digest(project)

      unknown = Celerite::FastPathStore.decision(
        project, digest, m8_fp_facts, record, Celerite::EvalFingerprint::State::Unknown)
      unknown.reason.should eq("fingerprint-unknown")

      broken = Celerite::FastPathStore.decision(
        project, digest, m8_fp_facts, record, Celerite::EvalFingerprint::State::Broken)
      broken.reason.should eq("fingerprint-broken")
    end
  end

  it "reports facts-unknown for a field only the bridge record can supply" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      facts = m8_fp_facts(engine: nil, engine_version: nil)
      verdict = Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), facts, record, m8_fp_deterministic)
      verdict.reason.should eq("facts-unknown:engine")
    end
  end

  it "reports facts-mismatch for a field that disagrees with the record" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      verdict = Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), m8_fp_facts(ruby_version: "4.0.5"),
        record, m8_fp_deterministic)
      verdict.reason.should eq("facts-mismatch:ruby_version")

      verdict = Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), m8_fp_facts(platform: "x86_64-linux"),
        record, m8_fp_deterministic)
      verdict.reason.should eq("facts-mismatch:platform")

      verdict = Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), m8_fp_facts(abi: "4.0.1"),
        record, m8_fp_deterministic)
      verdict.reason.should eq("facts-mismatch:rbconfig_ruby_version")
    end
  end

  it "requires Ruby when any ABI view is unknown or disagrees" do
    m8_fp_with do |project, _cache|
      digest = m8_fp_digest(project)
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      variants = [
        {m8_fp_facts(ruby_api_version: nil), "facts-unknown:ruby_api_version"},
        {m8_fp_facts(extension_api_version: nil), "facts-unknown:extension_api_version"},
        {m8_fp_facts(abi: nil), "facts-unknown:rbconfig_ruby_version"},
        {m8_fp_facts(ruby_api_version: "4.0.1"), "facts-mismatch:ruby_api_version"},
        {m8_fp_facts(extension_api_version: "4.0.1"), "facts-mismatch:extension_api_version"},
        {m8_fp_facts(abi: "4.0.1"), "facts-mismatch:rbconfig_ruby_version"},
      ]
      variants.each do |(facts, reason)|
        Celerite::FastPathStore.decision(project, digest, facts, record, m8_fp_deterministic)
          .reason.should eq(reason)
      end

      changed = m8_fp_record(project, abi: m8_fp_abi("4.0.1", "4.0.0", "4.0.0"))
      Celerite::FastPathStore.decision(project, digest, m8_fp_facts, changed, m8_fp_deterministic)
        .reason.should eq("facts-mismatch:ruby_api_version")
      changed = m8_fp_record(project, abi: m8_fp_abi("4.0.0", "4.0.0-static", "4.0.0"))
      Celerite::FastPathStore.decision(project, digest, m8_fp_facts, changed, m8_fp_deterministic)
        .reason.should eq("facts-mismatch:extension_api_version")
    end
  end

  it "rejects an empty or malformed credential namespace instead of treating it as a wildcard" do
    m8_fp_with do |project, _cache|
      digest = m8_fp_digest(project)
      ["", "not-a-namespace", "0123456789abcdeZ"].each do |namespace|
        record = m8_fp_record(project, namespace: namespace)
        record.complete?.should be_false
        Celerite::FastPathStore.decision(project, digest, m8_fp_facts, record, m8_fp_deterministic)
          .reason.should eq("record-incomplete")
      end
    end
  end

  it "refuses a record that is malformed, from another project, or another namespace" do
    m8_fp_with do |project, _cache|
      digest = m8_fp_digest(project)
      facts = m8_fp_facts

      bad_format = m8_fp_record(project, format: "celerite-fast-path/1")
      Celerite::FastPathStore.decision(project, digest, facts, bad_format, m8_fp_deterministic)
        .reason.should eq("record-format")

      incomplete = m8_fp_record(project, engine: "")
      Celerite::FastPathStore.decision(project, digest, facts, incomplete, m8_fp_deterministic)
        .reason.should eq("record-incomplete")

      other_project = m8_fp_record(project,
        project_digest: Celerite::FastPathStore.project_digest("/some/other/project"))
      Celerite::FastPathStore.decision(project, digest, facts, other_project, m8_fp_deterministic)
        .reason.should eq("project-mismatch")

      other_namespace = m8_fp_record(project, namespace: "0123456789abcdef")
      Celerite::FastPathStore.decision(project, digest, facts, other_namespace, m8_fp_deterministic)
        .reason.should eq("namespace-mismatch")
    end
  end

  it "returns Unknown, never Allowed, when a decision input is not supplied" do
    m8_fp_with do |project, _cache|
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      digest = m8_fp_digest(project)

      Celerite::FastPathStore.decision(project, digest, nil, record, m8_fp_deterministic)
        .unknown?.should be_true
      Celerite::FastPathStore.decision(project, digest, m8_fp_facts, record, nil)
        .unknown?.should be_true
      Celerite::FastPathStore.decision(project, digest, m8_fp_facts, record, nil)
        .allowed?.should be_false

      Celerite::FastPathStore.decision(project, "not-a-digest", m8_fp_facts, record,
        m8_fp_deterministic).reason.should eq("digest-invalid")
      Celerite::FastPathStore.decision("", digest, m8_fp_facts, record,
        m8_fp_deterministic).reason.should eq("project-invalid")
    end
  end

  it "builds a record only from fields a real source proved" do
    m8_fp_with do |project, _cache|
      bridge = Celerite::EvalFingerprint::Runtime.new(
        "4.0.6", "0", "ruby", "4.0.6", "4.0.16", "4.0.24", "x64-mingw-ucrt",
        Celerite::EvalFingerprint::Abi.new("4.0.0", "4.0.0", "4.0.0"))

      # Facts know five fields; engine/engine_version come from the bridge.
      record = Celerite::FastPathStore.record_from(project, m8_fp_facts(engine: nil,
        engine_version: nil), bridge, ruby_identity: m8_fp_identity(project),
        eval_digest: m8_fp_digest(project), certificate_nonce: "11111111111111111111111111111111").not_nil!
      record.engine.should eq("ruby")
      record.engine_version.should eq("4.0.6")
      record.ruby_version.should eq("4.0.6")
      record.written_at.matches?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/).should be_true
      record.credential_namespace.matches?(/\A[0-9a-f]{16}\z/).should be_true

      # No bridge and no ABI -> no record at all, never a guessed engine.
      Celerite::FastPathStore.record_from(project, m8_fp_facts(engine: nil,
        engine_version: nil)).should be_nil

      # Facts and the bridge disagreeing is not a record; it is a conflict.
      Celerite::FastPathStore.record_from(project,
        m8_fp_facts(ruby_version: "4.0.5"), bridge).should be_nil

      # A bridge without ABI cannot prove the native-extension layout.
      no_abi = Celerite::EvalFingerprint::Runtime.new(
        "4.0.6", "0", "ruby", "4.0.6", "4.0.16", "4.0.24", "x64-mingw-ucrt")
      Celerite::FastPathStore.record_from(project, m8_fp_facts, no_abi).should be_nil

      # A real ABI that disagrees with the install tree cannot seed a record.
      changed_abi = Celerite::EvalFingerprint::Runtime.new(
        "4.0.6", "0", "ruby", "4.0.6", "4.0.16", "4.0.24", "x64-mingw-ucrt",
        Celerite::EvalFingerprint::Abi.new("4.0.0", "4.0.0-static", "4.0.0"))
      Celerite::FastPathStore.record_from(project, m8_fp_facts, changed_abi).should be_nil
      Celerite::FastPathStore.record_from(project,
        m8_fp_facts(extension_api_version: nil), bridge).should be_nil
    end
  end

  it "stores credentials only as a namespace hash and rejects another context" do
    m8_fp_with do |project, _cache|
      ENV["BUNDLE_GEMS__EXAMPLE__COM"] = "alice:s3cret"
      record = m8_fp_record(project)
      m8_fp_bind(project, record)
      record.credential_namespace.matches?(/\A[0-9a-f]{16}\z/).should be_true
      Celerite::FastPathStore.store(record).should be_true

      body = File.read(Celerite::FastPathStore.default_path(project).not_nil!)
      body.should_not contain("s3cret")
      body.should_not contain("alice")
      body.should_not contain("://")

      # The same record under a different credential context is not trusted.
      ENV["BUNDLE_GEMS__EXAMPLE__COM"] = "bob:other"
      verdict = Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), m8_fp_facts, record, m8_fp_deterministic)
      verdict.reason.should eq("namespace-mismatch")
    end
  end

  it "never spawns a process or makes an RPC" do
    m8_fp_with do |project, _cache|
      ENV["CELERITE_BRIDGE_STATS"] = "1"
      Celerite::Bridge::BridgeStats.begin_run

      record = Celerite::FastPathStore.record_from(project, m8_fp_facts) ||
               m8_fp_record(project)
      m8_fp_bind(project, record)
      Celerite::FastPathStore.store(record).should be_true
      path = Celerite::FastPathStore.default_path(project).not_nil!
      Celerite::FastPathStore.load(path).should_not be_nil
      Celerite::FastPathStore.decision(
        project, m8_fp_digest(project), m8_fp_facts, record, m8_fp_deterministic)
        .allowed?.should be_true

      Celerite::Bridge::BridgeStats.procs.should eq(0)
      Celerite::Bridge::BridgeStats.rpc.should eq(0)
    end
  end
end
