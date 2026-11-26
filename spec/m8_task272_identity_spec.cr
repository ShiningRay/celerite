require "./spec_helper"
require "../src/celerite"

private T272_KEYS = %w[
  HOME USERPROFILE CELERITE_RUBY PATH CELERITE_CACHE_DIR CELERITE_EVAL_CACHE
  CELERITE_FAST_PATH BUNDLE_GEMS__EXAMPLE__COM BUNDLE_GEMFILE BUNDLE_APP_CONFIG
  CELERITE_BRIDGE_STATS
]

private def t272_with(& : String ->) : Nil
  with_project({} of String => String) do |project|
    saved = {} of String => String?
    T272_KEYS.each { |key| saved[key] = ENV[key]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["CELERITE_CACHE_DIR"] = File.join(project, "cache")
    ENV["CELERITE_EVAL_CACHE"] = "1"
    ENV["CELERITE_FAST_PATH"] = "1"
    ENV.delete("CELERITE_RUBY")
    ENV.delete("BUNDLE_GEMS__EXAMPLE__COM")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("BUNDLE_APP_CONFIG")
    ENV.delete("CELERITE_BRIDGE_STATS")
    begin
      yield project
    ensure
      saved.each do |key, value|
        if value
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end
  end
end

private def t272_ruby(project : String, bytes : String = "ruby-bytes", root : String = ".ruby") : String
  bin = File.join(project, root, "bin")
  rbconfig = File.join(project, root, "lib", "ruby", "9.9.0", "fake-arch")
  Dir.mkdir_p(bin)
  Dir.mkdir_p(rbconfig)
  exe = File.join(bin, "ruby.exe")
  File.write(exe, bytes)
  File.write(File.join(rbconfig, "rbconfig.rb"), "# readable rbconfig\n")
  exe
end

private def t272_certificate(identity : Celerite::CacheIdentity::RubyIdentity,
                             command : String = "lock") : Celerite::CacheIdentity::SuccessCertificate
  lock = Celerite::CacheIdentity::LockIdentity.new("Gemfile.lock", "a" * 64, 42_i64,
    "lf", "parser-1", "bundler-4", "b" * 64, ["x64-mingw-ucrt"])
  install = command == "install" ? Celerite::CacheIdentity::InstallCertificate.new("c" * 64) : nil
  Celerite::CacheIdentity::SuccessCertificate.new(Celerite::CacheIdentity::CERTIFICATE,
    command, "default", identity.identity_digest.not_nil!, lock, install: install)
end

private def t272_record(project : String, identity : Celerite::CacheIdentity::RubyIdentity,
                        digest : String = "d" * 64, nonce : String = "1" * 32) : Celerite::FastPathStore::RuntimeRecord
  abi = Celerite::FastPathStore::Abi.new("4.0", "4.0", "4.0")
  Celerite::FastPathStore::RuntimeRecord.new(Celerite::FastPathStore::FORMAT,
    "2026-11-25T00:00:00Z", Celerite::FastPathStore.project_digest(project),
    Celerite::EvalCacheStore.namespace, "4.0.6", "0", "ruby", "4.0.6",
    "x64-mingw-ucrt", "4.0.16", "4.0.24", abi, identity, digest, nonce)
end

private def t272_facts(exe : String) : Celerite::RuntimeFacts::Facts
  known = ->(value : String) { Celerite::RuntimeFacts::Field.new(value, Celerite::RuntimeFacts::Source::Record) }
  Celerite::RuntimeFacts::Facts.new(exe, known.call("4.0.6"), known.call("0"),
    known.call("ruby"), known.call("4.0.6"), known.call("4.0.16"), known.call("4.0.24"),
    known.call("x64-mingw-ucrt"), known.call("gems"), known.call("4.0"),
    known.call("4.0"), known.call("4.0"), known.call("prefix"), known.call("lib"))
end

private def t272_seed(project : String, record : Celerite::FastPathStore::RuntimeRecord) : Nil
  payload = %({"format":"celerite-eval-cache/2","digest":"#{record.eval_digest}","evaluation":{},"certificates":{}})
  Celerite::EvalCacheStore.write(record.eval_digest, payload).should be_true
  Celerite::EvalCacheStore.put_certificate(record.eval_digest, record.certificate_nonce,
    t272_certificate(record.ruby_identity)).should be_true
end

describe Celerite::CacheIdentity::RubyIdentity do
  it "persists path-free facts and invokes no process" do
    t272_with do |project|
      exe = t272_ruby(project)
      ENV["CELERITE_BRIDGE_STATS"] = "1"
      Celerite::Bridge::BridgeStats.begin_run
      identity = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      identity.known?.should be_true
      identity.selection_kind.should eq("explicit")
      identity.relative_locator.should eq("bin/ruby.exe")
      identity.size.should eq(File.info(exe).size)
      identity.file_sha256.should eq(Digest::SHA256.hexdigest(File.read(exe)))
      body = identity.to_json
      body.should_not contain(project)
      body.should_not contain(".ruby")
      body.should_not contain("canonical_path")
      body.should_not contain("rbconfig_path")
      Celerite::CacheIdentity::RubyIdentity.parse(JSON.parse(body)).identity_digest.should eq(identity.identity_digest)
      Celerite::Bridge::BridgeStats.procs.should eq(0)
      Celerite::Bridge::BridgeStats.rpc.should eq(0)
    end
  end

  it "uses CELERITE_RUBY then PATH and never skips the first shim" do
    t272_with do |project|
      exe = t272_ruby(project)
      ENV["CELERITE_RUBY"] = exe
      Celerite::CacheIdentity::RubyIdentity.detect.selection_kind.should eq("explicit")
      ENV.delete("CELERITE_RUBY")
      ENV["PATH"] = File.dirname(exe)
      Celerite::CacheIdentity::RubyIdentity.detect.selection_kind.should eq("path")
      shim = File.join(project, "shim")
      Dir.mkdir_p(shim)
      File.write(File.join(shim, "ruby.exe"), "#!/bin/sh\n")
      separator = {% if flag?(:win32) %} ";" {% else %} ":" {% end %}
      ENV["PATH"] = "#{shim}#{separator}#{File.dirname(exe)}"
      identity = Celerite::CacheIdentity::RubyIdentity.detect
      identity.state.should eq("unknown")
      identity.relative_locator.should be_nil
      identity.identity_digest.should be_nil
      Celerite::CacheIdentity::RubyIdentity.detect("").state.should eq("unknown")

      batch = File.join(project, "batch-shims")
      Dir.mkdir_p(batch)
      File.write(File.join(batch, "ruby.bat"), "@echo off\r\n")
      File.write(File.join(batch, "ruby.cmd"), "@echo off\r\n")
      ENV["PATH"] = batch
      Celerite::CacheIdentity::RubyIdentity.detect.state.should eq("unknown")

      separator = {% if flag?(:win32) %} ";" {% else %} ":" {% end %}
      wrong_separator = {% if flag?(:win32) %} ":" {% else %} ";" {% end %}
      ENV["PATH"] = "#{batch}#{separator}#{File.dirname(exe)}"
      Celerite::CacheIdentity::RubyIdentity.detect.selection_kind.should eq("path")
      ENV["PATH"] = "#{batch}#{wrong_separator}#{File.dirname(exe)}"
      Celerite::CacheIdentity::RubyIdentity.detect.state.should eq("unknown")
    end
  end

  it "returns Unknown for broken links, unreadable files and unproven layouts" do
    t272_with do |project|
      broken = File.join(project, "broken-ruby.exe")
      created = begin
        File.symlink(File.join(project, "missing-target"), broken)
        true
      rescue File::Error
        false
      end
      next pending "symlink creation is unavailable in this environment" unless created
      Celerite::CacheIdentity::RubyIdentity.detect(broken).state.should eq("unknown")

      exe = t272_ruby(project)
      other_exe = t272_ruby(project, "other-ruby-bytes", ".ruby-other")
      original = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      other = Celerite::CacheIdentity::RubyIdentity.detect(other_exe)
      other.known?.should be_true
      other.identity_digest.should_not eq(original.identity_digest)
      linked = File.join(project, "linked-ruby.exe")
      File.symlink(other_exe, linked)
      Celerite::CacheIdentity::RubyIdentity.detect(linked).identity_digest.should eq(other.identity_digest)

      cycle_a = File.join(project, "cycle-a", "ruby.exe")
      cycle_b = File.join(project, "cycle-b", "ruby.exe")
      Dir.mkdir_p(File.dirname(cycle_a))
      Dir.mkdir_p(File.dirname(cycle_b))
      File.symlink(cycle_b, cycle_a)
      File.symlink(cycle_a, cycle_b)
      Celerite::CacheIdentity::RubyIdentity.detect(cycle_a).state.should eq("unknown")

      File.delete(File.join(project, ".ruby", "lib", "ruby", "9.9.0", "fake-arch", "rbconfig.rb"))
      Celerite::CacheIdentity::RubyIdentity.detect(File.join(project, ".ruby", "bin", "ruby.exe")).state.should eq("unknown")
      Dir.mkdir_p(File.join(project, "wrong-bin"))
      File.write(File.join(project, "wrong-bin", "ruby.exe"), "not a ruby layout")
      Celerite::CacheIdentity::RubyIdentity.detect(File.join(project, "wrong-bin", "ruby.exe")).state.should eq("unknown")
    end
  end

  it "changes the digest for path, size, mtime and same-second content changes" do
    t272_with do |project|
      exe = t272_ruby(project)
      first = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      File.write(exe, "ruby-bytes-longer")
      changed = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      changed.identity_digest.should_not eq(first.identity_digest)
      changed.size.should eq(17)
      File.utime(Time.utc(2020, 1, 2, 3, 4, 5), Time.utc(2020, 1, 2, 3, 4, 5), exe)
      timed = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      timed.precision.should eq("second")
      File.utime(Time.utc(2020, 1, 2, 3, 4, 6), Time.utc(2020, 1, 2, 3, 4, 6), exe)
      Celerite::CacheIdentity::RubyIdentity.detect(exe).identity_digest.should_not eq(timed.identity_digest)
      File.utime(Time.utc(2020, 1, 2, 3, 4, 6), Time.utc(2020, 1, 2, 3, 4, 6), exe)
      before_content = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      File.write(exe, "RUBY-BYTES-LONGER")
      File.utime(Time.utc(2020, 1, 2, 3, 4, 6), Time.utc(2020, 1, 2, 3, 4, 6), exe)
      after_content = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      after_content.precision.should eq("second")
      after_content.mtime_seconds.should eq(before_content.mtime_seconds)
      after_content.file_sha256.should_not eq(before_content.file_sha256)
      after_content.identity_digest.should_not eq(before_content.identity_digest)
      moved = File.join(project, "migrated")
      FileUtils.mv(File.join(project, ".ruby"), moved)
      moved_exe = File.join(moved, "bin", "ruby.exe")
      Celerite::CacheIdentity::RubyIdentity.detect(moved_exe).identity_digest.should eq(after_content.identity_digest)
    end
  end
end

describe "task-272 v2 certificate transactions" do
  it "keeps legacy /1 evaluation-only and never upgrades it into a certificate" do
    t272_with do |project|
      digest = "e" * 64
      legacy = %({"format":"celerite-eval-cache/1","digest":"#{digest}","evaluation":{},"env":{},"fingerprint":{},"gemspecs":[]})
      Celerite::EvalCacheStore.write(digest, legacy).should be_true
      Celerite::EvalCacheStore.entry_path(digest).not_nil!
      File.file?(Celerite::EvalCacheStore.entry_path(digest).not_nil!).should be_false
      Celerite::EvalCacheStore.certificate(digest, "1" * 32).should be_nil
      entry = Celerite::EvalCacheStore.read_all.find { |item| item.digest == digest }.not_nil!
      entry.evaluation_only?.should be_true
      Celerite::EvalCacheStore.write(digest, legacy).should be_true
      File.file?(Celerite::EvalCacheStore.legacy_entry_path(digest).not_nil!).should be_true
      File.file?(Celerite::EvalCacheStore.entry_path(digest).not_nil!).should be_false
    end
  end

  it "commits independent nonces and failed transactions preserve the old bytes" do
    t272_with do |project|
      exe = t272_ruby(project)
      identity = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      record = t272_record(project, identity)
      t272_seed(project, record)
      nonce2 = "2" * 32
      Celerite::EvalCacheStore.put_certificate(record.eval_digest, nonce2,
        t272_certificate(identity)).should be_true
      Celerite::EvalCacheStore.certificate(record.eval_digest, record.certificate_nonce).not_nil!.command.should eq("lock")
      Celerite::EvalCacheStore.certificate(record.eval_digest, nonce2).not_nil!.command.should eq("lock")
      path = Celerite::EvalCacheStore.entry_path(record.eval_digest).not_nil!
      old = File.read(path)
      bad_lock = Celerite::CacheIdentity::LockIdentity.new("Gemfile.lock", "not-a-sha", 42_i64,
        "lf", "parser-1", "bundler-4", "b" * 64, ["x64-mingw-ucrt"])
      bad_certificate = Celerite::CacheIdentity::SuccessCertificate.new(Celerite::CacheIdentity::CERTIFICATE,
        "lock", "default", identity.identity_digest.not_nil!, bad_lock)
      Celerite::EvalCacheStore.put_certificate(record.eval_digest, nonce2, bad_certificate).should be_false
      File.read(path).should eq(old)
      replacement = Celerite::CacheIdentity::SuccessCertificate.new(Celerite::CacheIdentity::CERTIFICATE,
        "install", "default", identity.identity_digest.not_nil!, Celerite::CacheIdentity::LockIdentity.new(
        "Gemfile.lock", "a" * 64, 42_i64, "lf", "parser-1", "bundler-4", "b" * 64, ["x64-mingw-ucrt"]),
        install: Celerite::CacheIdentity::InstallCertificate.new("c" * 64))
      Celerite::EvalCacheStore.put_certificate(record.eval_digest, nonce2, replacement).should be_true
      File.read(path).should_not eq(old)
      Celerite::EvalCacheStore.certificate(record.eval_digest, nonce2).not_nil!.command.should eq("install")
      Dir.children(File.dirname(path)).any? { |name| name.ends_with?(".tmp") }.should be_false
    end
  end

  it "requires a current Ruby identity, matching evaluation and command certificate" do
    t272_with do |project|
      exe = t272_ruby(project)
      identity = Celerite::CacheIdentity::RubyIdentity.detect(exe)
      record = t272_record(project, identity)
      Celerite::EvalCacheStore.write(record.eval_digest,
        %({"format":"celerite-eval-cache/2","digest":"#{record.eval_digest}","evaluation":{},"certificates":{}})).should be_true
      facts = t272_facts(exe)
      verdict = Celerite::FastPathStore.decision(project, record.eval_digest, facts, record,
        Celerite::EvalFingerprint::State::Deterministic)
      verdict.reason.should eq("lock-unbound")
      Celerite::FastPathStore.decision(project, "f" * 64, facts, record,
        Celerite::EvalFingerprint::State::Deterministic).reason.should eq("eval-digest-mismatch")
      Celerite::FastPathStore.decision(project, record.eval_digest, facts, record,
        Celerite::EvalFingerprint::State::Deterministic, Celerite::CacheIdentity::RubyIdentity.unknown)
        .reason.should eq("ruby-identity-unknown")
      t272_seed(project, record)
      current_lock = t272_certificate(record.ruby_identity).lock
      Celerite::EvalCacheStore.put_certificate(record.eval_digest, record.certificate_nonce,
        Celerite::CacheIdentity::SuccessCertificate.new(Celerite::CacheIdentity::CERTIFICATE,
          "lock", Celerite::Profile.bundler_version, identity.identity_digest.not_nil!, current_lock)).should be_true
      Celerite::FastPathStore.decision(project, record.eval_digest, facts, record,
        Celerite::EvalFingerprint::State::Deterministic, identity, "lock", current_lock).allowed?.should be_true
      record.to_json.should_not contain("\"lock\"")
      old = JSON.parse(record.to_json)
      old.as_h.delete("ruby_identity")
      FileUtils.mkdir_p(File.dirname(Celerite::FastPathStore.default_path(project).not_nil!))
      old_path = Celerite::FastPathStore.default_path(project).not_nil!
      File.write(old_path, old.to_json)
      Celerite::FastPathStore.load(old_path).should be_nil
    end
  end

  it "normalizes a missing v2 certificate map but preserves the old file on a malformed map" do
    t272_with do |project|
      t272_ruby(project)
      digest = "e" * 64
      payload = %({"format":"celerite-eval-cache/2","digest":"#{digest}","evaluation":{}})
      Celerite::EvalCacheStore.write(digest, payload).should be_true
      entry = Celerite::EvalCacheStore.read_all.first
      entry.format.should eq(Celerite::EvalCacheStore::FORMAT)
      entry.certificate("1" * 32).should be_nil
      JSON.parse(File.read(entry.path))["certificates"].as_h.should be_empty
      path = entry.path
      before = File.read(path)

      malformed = JSON.parse(payload)
      malformed.as_h["certificates"] = JSON.parse(%({"not-a-nonce":{}}))
      Celerite::EvalCacheStore.write(digest, malformed.to_json).should be_false
      File.read(path).should eq(before)
      Dir.children(File.dirname(path)).any? { |name| name.ends_with?(".tmp") }.should be_false
    end
  end

  it "rejects unknown certificate fields and invalid command/lock combinations" do
    t272_with do |project|
      identity = Celerite::CacheIdentity::RubyIdentity.detect(t272_ruby(project))
      certificate = t272_certificate(identity)
      object = JSON.parse(certificate.to_json)
      object.as_h["unexpected"] = JSON::Any.new("true")
      expect_raises(JSON::ParseException) { Celerite::CacheIdentity::SuccessCertificate.parse(object) }
      expect_raises(JSON::ParseException) do
        Celerite::CacheIdentity::SuccessCertificate.new("wrong", "lock", "default",
          identity.identity_digest.not_nil!, certificate.lock).validate
      end
      expect_raises(JSON::ParseException) do
        Celerite::CacheIdentity::SuccessCertificate.new(Celerite::CacheIdentity::CERTIFICATE,
          "install", "default", identity.identity_digest.not_nil!, certificate.lock).validate
      end
    end
  end

  it "round-trips absent and JSON-null optional certificate fields" do
    t272_with do |project|
      identity = Celerite::CacheIdentity::RubyIdentity.detect(t272_ruby(project))
      lock = t272_certificate(identity)
      absent = JSON.parse(lock.to_json)
      absent.as_h.delete("plugin")
      absent.as_h.delete("install")
      restored = Celerite::CacheIdentity::SuccessCertificate.parse(absent)
      restored.plugin.should be_nil
      restored.install.should be_nil

      null_lock = JSON.parse(lock.to_json)
      null_lock.as_h["plugin"] = JSON::Any.new(nil)
      null_lock.as_h["install"] = JSON::Any.new(nil)
      restored_null_lock = Celerite::CacheIdentity::SuccessCertificate.parse(null_lock)
      restored_null_lock.plugin.should be_nil
      restored_null_lock.install.should be_nil

      install = t272_certificate(identity, "install")
      null_install = JSON.parse(install.to_json)
      null_install.as_h["plugin"] = JSON::Any.new(nil)
      restored_null_install = Celerite::CacheIdentity::SuccessCertificate.parse(null_install)
      restored_null_install.install.not_nil!.should_not be_nil
      restored_null_install.plugin.should be_nil
    end
  end
end
