require "./spec_helper"
require "./m8_fast_path_matrix_support"

# S8c (roadmap L164, `docs/roadmap-evidence/M8-fast-path-plan.md`): a `lock`
# whose Gemfile evaluation and runtime are already proven on disk rewrites the
# same bytes without loading Bundler -- that is, without starting the Ruby
# bridge. Every case here runs the real binary in a child process, because the
# claim is about *processes*: an in-process `Celerite::CLI.run` reuses one
# bridge client and cannot observe a spawn.
#
# The acceptance state is "a lockfile that is already current". For Bundler 4
# that includes complete CHECKSUMS entries: an empty entry makes the reference
# re-resolve (`definition.rb:630-659`), which is why `lfp_install` builds the
# state with `install` instead of hand-writing a lock. The `checksums` miss
# below pins the other side of that boundary.
private LFP_INDEX = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private LFP_STATS = /^bridge: procs=(\d+) rpc=(\d+) req_bytes=(\d+) resp_bytes=(\d+)$/

private LFP_HIT = /^fast-path: lock hit \(digest=([0-9a-f]{12})\)$/

private LFP_MISS = /^fast-path: lock miss \((.+)\)$/

# The switches every run has to *inherit or not*, plus the environment the
# bridge and both caches key on. `CELERITE_EVAL_CACHE`/`CELERITE_FAST_PATH` are
# added per run by `lfp_env`.
private LFP_SWITCHES = %w[
  CELERITE_FAST_PATH CELERITE_FAST_PATH_DEBUG CELERITE_EVAL_CACHE
  CELERITE_CACHE_DIR CELERITE_BRIDGE_STATS CELERITE_BRIDGE_SERVER
  CELERITE_REFERENCE_BUNDLER_LIB CELERITE_VERBOSE
]

private LFP_ISOLATED = %w[HOME USERPROFILE BUNDLE_PATH TMPDIR TMP TEMP]

private def lfp_bin : String?
  path = ENV["CELERITE_LFP_BIN"]? || File.expand_path("../bin/celerite.exe", __DIR__)
  File.exists?(path) ? File.expand_path(path) : nil
end

private def lfp_pending!(project : String) : Nil
  pending!("bin/celerite.exe is not built") unless lfp_bin
  pending!("no Ruby interpreter on PATH for the bridge") unless ruby_available?
  Dir.mkdir_p(File.join(project, "tmp"))
end

private def lfp_env(*switches : String) : Hash(String, String)
  env = {"CELERITE_BRIDGE_STATS" => "1"}
  switches.each { |name| env[name] = "1" }
  env
end

# The child inherits this process environment, so the isolated variables (and
# every switch) are set here and restored afterwards.
private def lfp_with_env(project : String, overrides : Hash(String, String), &)
  keys = (LFP_ISOLATED + LFP_SWITCHES).uniq!
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]? }
  keys.each { |key| ENV.delete(key) }
  tmp = File.join(project, "tmp")
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["TMPDIR"] = tmp
  ENV["TMP"] = tmp
  ENV["TEMP"] = tmp
  overrides.each { |key, value| ENV[key] = value }
  begin
    yield
  ensure
    previous.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def lfp_run(project : String, args : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(lfp_bin.not_nil!, args, chdir: project, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

private def lfp_counters(errors : String) : {Int32, Int32}
  line = errors.lines.find(&.starts_with?("bridge: procs="))
  fail "missing bridge stats line in #{errors.inspect}" unless line
  match = line.match(LFP_STATS).not_nil!
  {match[1].to_i, match[2].to_i}
end

private def lfp_counter_quad(errors : String) : {Int32, Int32, Int32, Int32}
  line = errors.lines.find(&.starts_with?("bridge: procs="))
  fail "missing bridge stats line in #{errors.inspect}" unless line
  match = line.match(LFP_STATS).not_nil!
  {match[1].to_i, match[2].to_i, match[3].to_i, match[4].to_i}
end

private def lfp_hits(errors : String) : Array(String)
  errors.lines.compact_map(&.match(LFP_HIT)).map(&.[1])
end

private def lfp_misses(errors : String) : Array(String)
  errors.lines.compact_map(&.match(LFP_MISS)).map(&.[1])
end

private def lfp_fast_path_lines(errors : String) : Array(String)
  errors.lines.select(&.starts_with?("fast-path:"))
end

private def lfp_digest(project : String) : String
  Digest::SHA256.hexdigest(File.read(File.join(project, "Gemfile.lock")))
end

private def lfp_record_paths(project : String) : Array(String)
  Dir.glob(File.join(project, ".celerite", "cache", "fast-path", "v2", "*", "*.json").tr("\\", "/"))
end

private def lfp_entry_paths(project : String) : Array(String)
  Dir.glob(File.join(project, ".celerite", "cache", "eval", "*", "v2", "*", "entry.json").tr("\\", "/"))
end

private def lfp_record_nonce(project : String) : String
  JSON.parse(File.read(lfp_record_paths(project).first))["certificate_nonce"].as_s
end

private def lfp_certificate_nonces(project : String) : Array(String)
  JSON.parse(File.read(lfp_entry_paths(project).first))["certificates"].as_h.keys.sort
end

# The digest the debug line reports is the evaluation fingerprint digest stored
# in the entry, not the lockfile's own hash.
private def lfp_fingerprint_digest(project : String) : String
  paths = lfp_entry_paths(project)
  fail "no evaluation entry under #{project}" if paths.empty?
  JSON.parse(File.read(paths.first))["fingerprint"]["digest"].as_s
end

# `lock` in the given environment. The bridge stats line is how a spawn is
# observed: the client prints exactly one per command, including `procs=0`.
private def lfp_lock(project : String, env : Hash(String, String)) : {Int32, String, String, Int32, Int32}
  lfp_with_env(project, env) do
    status, output, errors = lfp_run(project, ["lock"])
    procs, rpc = lfp_counters(errors)
    {status, output, errors, procs, rpc}
  end
end

private def lfp_install(project : String) : String
  File.write(File.join(project, "Gemfile"), %(source "#{LFP_INDEX}"\n\ngem "json_pure"\n))
  lfp_with_env(project, {} of String => String) do
    status, output, errors = lfp_run(project, ["install"])
    fail "install failed (#{status}): #{output} #{errors}" unless status == 0
  end
  lock = File.read(File.join(project, "Gemfile.lock"))
  # The no-op branch is only reachable when the lockfile is genuinely current,
  # so the fixture must not carry an empty CHECKSUMS entry.
  lock.should contain("CHECKSUMS")
  lock.should match(/json_pure \(\d+\.\d+\.\d+\) sha256=[0-9a-f]{64}/)
  lock
end

# install -> a persisted evaluation (`CELERITE_EVAL_CACHE=1`) -> a runtime
# record (the fast-path switch on, but no record yet, so the Ruby path runs and
# `remember_after_lock` writes one). Returns the current lock digest.
private def lfp_ready(project : String, require_v2 : Bool = true) : String
  lfp_install(project)

  status, _out, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE"))
  fail "warm lock failed (#{status}): #{errors}" unless status == 0
  procs.should be >= 1

  # The first switched run has the entry but no record: it must fall back to
  # the Ruby path (and write the record on the way out).
  status, _out, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH"))
  fail "record lock failed (#{status}): #{errors}" unless status == 0
  procs.should be >= 1
  lfp_fast_path_lines(errors).should be_empty

  if require_v2
    lfp_record_paths(project).size.should eq(1)
    lfp_entry_paths(project).size.should eq(1)
    lfp_certificate_nonces(project).should contain(lfp_record_nonce(project))
  end
  lfp_digest(project)
end

# Run one negative case from byte-identical warm/cold state through the explicit
# compatibility switch and the enabled fast path. This asserts exit, normalized
# stdout/stderr and every non-cache file-tree item, not merely `procs >= 1`.
private def lfp_matrix_parity(project : String, args : Array(String) = ["lock"]) : Nil
  archive = File.join(Dir.tempdir, "celerite-m8-lock-matrix-#{Process.pid}-#{Random.rand(1_000_000)}")
  m8_matrix_snapshot(project, archive)
  begin
    reference_env = lfp_env("CELERITE_EVAL_CACHE", "CELERITE_BRIDGE_STATS")
    reference_env["CELERITE_FAST_PATH"] = "0"
    lfp_with_env(project, reference_env) do
      m8_matrix_restore(project, archive)
      reference = m8_matrix_run(project, args)
      reference_tree = m8_matrix_tree(project)
      lfp_with_env(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_BRIDGE_STATS")) do
        m8_matrix_restore(project, archive)
        candidate = m8_matrix_run(project, args)
        candidate_tree = m8_matrix_tree(project)
        m8_matrix_assert_compat_parity(reference, candidate, project, reference_tree, candidate_tree)
      end
    end
  ensure
    FileUtils.rm_rf(archive)
  end
end

# Change both independently persisted ABI views. Updating the fingerprint text,
# its SHA-256 and its digest directory keeps the old cache internally
# consistent: this is the tamper shape that used to bypass the store's
# rbconfig-only check.
private def lfp_tamper_abi(project : String, field : String, value : String) : Nil
  record_path = lfp_record_paths(project).first
  record = JSON.parse(File.read(record_path)).as_h
  record["abi"].as_h[field] = JSON::Any.new(value)
  File.write(record_path, record.to_json)

  entry_path = lfp_entry_paths(project).first
  payload = JSON.parse(File.read(entry_path)).as_h
  fingerprint = payload["fingerprint"].as_h
  text = fingerprint["text"].as_s
  record_key = "abi.#{field}"
  changed = text.gsub(/#{Regex.escape(record_key)}\t[^\r\n]+/, "#{record_key}\t#{value}")
  changed.should_not eq(text)
  digest = Digest::SHA256.hexdigest(changed)
  fingerprint["text"] = JSON::Any.new(changed)
  fingerprint["digest"] = JSON::Any.new(digest)
  payload["digest"] = JSON::Any.new(digest)
  old_dir = File.dirname(entry_path)
  new_dir = File.join(File.dirname(old_dir), digest)
  File.rename(old_dir, new_dir)
  File.write(File.join(new_dir, "entry.json"), payload.to_json)
end

describe "lock takes the no-Ruby fast path on an unchanged project" do
  it "rewrites the locked bytes with procs=0 when the switches are on and both caches are warm" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      digest = lfp_ready(project)
      lock_before = File.read(File.join(project, "Gemfile.lock"))
      old_nonce = lfp_record_nonce(project)

      status, output, errors, procs, rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      lfp_counter_quad(errors).should eq({0, 0, 0, 0})
      procs.should eq(0)
      rpc.should eq(0)
      lfp_hits(errors).size.should eq(1)
      lfp_hits(errors).first.should eq(lfp_fingerprint_digest(project)[0, 12])
      lfp_misses(errors).should be_empty
      output.should eq("Writing lockfile to #{File.join(project, "Gemfile.lock").gsub('\\', "/")}\n")
      File.read(File.join(project, "Gemfile.lock")).should eq(lock_before)
      lfp_digest(project).should eq(digest)
      new_nonce = lfp_record_nonce(project)
      new_nonce.should_not eq(old_nonce)
      lfp_certificate_nonces(project).should contain(new_nonce)
      lfp_certificate_nonces(project).should contain(old_nonce)
    end
  end

  it "keeps the Ruby path when CELERITE_FAST_PATH is unset" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      status, output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE"))
      status.should eq(0)
      procs.should be >= 1
      lfp_fast_path_lines(errors).should be_empty
      output.should contain("Writing lockfile to")
    end
  end

  it "keeps the Ruby path when CELERITE_FAST_PATH is set to something other than 1" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      env = lfp_env("CELERITE_EVAL_CACHE")
      env["CELERITE_FAST_PATH"] = "true"
      env["CELERITE_FAST_PATH_DEBUG"] = "1"
      status, _output, errors, procs, _rpc = lfp_lock(project, env)
      status.should eq(0)
      procs.should be >= 1
      # Only the exact value `1` enables the fast path, so there is not even a
      # miss line to print: the gate is never reached.
      lfp_fast_path_lines(errors).should be_empty
    end
  end

  it "keeps the Ruby path when the persisted evaluation cache is off" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      # Without `CELERITE_EVAL_CACHE=1` there is no fingerprint to read, so the
      # fast path must not even look at the store.
      lfp_fast_path_lines(errors).should be_empty
    end
  end

  it "keeps the Ruby path when the Gemfile changed since the evaluation" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      File.write(File.join(project, "Gemfile"), %(source "#{LFP_INDEX}"\n\ngem "json_pure"\ngem "thor"\n))
      status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      lfp_misses(errors).should eq(["entry"])
      # The Ruby path resolved the new dependency.
      File.read(File.join(project, "Gemfile.lock")).should contain("thor (1.3.2)")
    end
  end

  it "keeps the Ruby path when the lockfile is missing" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      File.delete(File.join(project, "Gemfile.lock"))
      status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      lfp_misses(errors).should eq(["no-lockfile"])
      File.exists?(File.join(project, "Gemfile.lock")).should be_true
    end
  end

  it "keeps the Ruby path when the runtime record is missing" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      paths = lfp_record_paths(project)
      paths.size.should eq(1)
      File.delete(paths.first)
      status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      lfp_misses(errors).should eq(["record"])
    end
  end

  it "keeps the Ruby path when the runtime record has the wrong format" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      path = lfp_record_paths(project).first
      File.write(path, %({"format":"celerite-fast-path/999","written_at":"2026-01-01T00:00:00Z"}\n))
      status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      lfp_misses(errors).should eq(["record"])

      # A corrupt record is deleted instead of trusted, and the next run still
      # takes the Ruby path.
      File.write(path, "not json at all\n")
      status, _out, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_misses(errors).should eq(["record"])
    end
  end

  it "keeps the Ruby path when the fingerprint is no longer deterministic" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      entry = lfp_entry_paths(project).first
      %w[unknown broken].each do |state|
        original = File.read(entry)
        begin
          payload = JSON.parse(original).as_h
          fingerprint = payload["fingerprint"].as_h
          fingerprint["state"] = JSON::Any.new(state)
          File.write(entry, payload.to_json)
          status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
          status.should eq(0)
          procs.should be >= 1
          lfp_hits(errors).should be_empty
          lfp_misses(errors).should eq(["entry"])
        ensure
          File.write(entry, original)
        end
      end
    end
  end

  it "keeps the Ruby path when a covered file changed under the fingerprint" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      # Same Gemfile semantics, different bytes: the stored sha256 no longer
      # matches, so the entry describes a project that is gone.
      File.write(File.join(project, "Gemfile"), %(source "#{LFP_INDEX}"\n\ngem "json_pure" # comment\n))
      status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      lfp_misses(errors).should eq(["entry"])
    end
  end

  it "keeps the Ruby path when the lockfile has an empty CHECKSUMS entry" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      lock = File.read(File.join(project, "Gemfile.lock"))
      # Rewrite in place so the line terminators survive: `String#lines` chomps,
      # and `^`/`$` are not line anchors here, so anchor on the newline itself.
      stripped = lock.gsub(/(\n[ ]{2}json_pure \([^)]+\)) sha256=[0-9a-f]{64}/, "\\1")
      stripped.should_not eq(lock)
      File.write(File.join(project, "Gemfile.lock"), stripped)
      status, _output, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      lfp_misses(errors).should eq(["checksums"])
    end
  end

  it "prints byte-identical output to the Ruby path" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      _s1, ruby_out, _e1, ruby_procs, _r1 = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE"))
      ruby_procs.should be >= 1
      before = lfp_digest(project)
      status, fast_out, errors, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should eq(0)
      lfp_hits(errors).size.should eq(1)
      fast_out.should eq(ruby_out)
      lfp_digest(project).should eq(before)
    end
  end

  it "keeps CELERITE_FAST_PATH=0 on the compatibility path with full observable parity" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      reference_env = lfp_env("CELERITE_EVAL_CACHE", "CELERITE_BRIDGE_STATS")
      reference_env["CELERITE_FAST_PATH"] = "0"
      reference = nil.as(M8MatrixRun?)
      reference_tree = {} of String => String
      lfp_with_env(project, reference_env) do
        reference = m8_matrix_run(project, ["lock"])
        reference_tree = m8_matrix_tree(project)
      end
      lfp_with_env(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_BRIDGE_STATS")) do
        candidate = m8_matrix_run(project, ["lock"])
        candidate_tree = m8_matrix_tree(project)
        reference.not_nil!.procs.should be >= 1
        candidate.status.should eq(reference.not_nil!.status)
        m8_matrix_normalize(candidate.stdout, project).should eq(m8_matrix_normalize(reference.not_nil!.stdout, project))
        m8_matrix_normalize(m8_matrix_observable_stderr(candidate), project)
          .should eq(m8_matrix_normalize(m8_matrix_observable_stderr(reference.not_nil!), project))
        candidate_tree.should eq(reference_tree)
        candidate.procs.should eq(0)
        candidate.rpc.should eq(0)
        candidate.req_bytes.should eq(0)
        candidate.resp_bytes.should eq(0)
      end
    end
  end

  it "falls back with full compatibility parity on a cold cache" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_install(project)
      FileUtils.rm_rf(File.join(project, ".celerite", "cache"))
      lfp_matrix_parity(project)
    end
  end

  it "hits through a bad bridge URL with exact zero process, RPC and byte counters" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      env = lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_BRIDGE_STATS")
      env["CELERITE_BRIDGE_SERVER"] = "http://127.0.0.1:1"
      lfp_with_env(project, env) do
        run = m8_matrix_run(project, ["lock"])
        run.status.should eq(0)
        run.procs.should eq(0)
        run.rpc.should eq(0)
        run.req_bytes.should eq(0)
        run.resp_bytes.should eq(0)
      end
    end
  end

  it "rejects an empty credential namespace with full compatibility parity" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = lfp_record_paths(project).first
      payload = JSON.parse(File.read(path)).as_h
      payload["credential_namespace"] = JSON::Any.new("")
      File.write(path, payload.to_json)
      lfp_matrix_parity(project)
    end
  end

  it "rejects independently tampered ruby and extension ABI views with full compatibility parity" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      original_record = File.read(lfp_record_paths(project).first)
      original_entry = File.read(lfp_entry_paths(project).first)
      original_entry_dir = File.dirname(lfp_entry_paths(project).first)
      begin
        lfp_tamper_abi(project, "ruby_api_version", "4.0.1")
        lfp_matrix_parity(project)
      ensure
        File.write(lfp_record_paths(project).first, original_record)
        lfp_entry_paths(project).each { |entry| FileUtils.rm_rf(File.dirname(entry)) }
        Dir.mkdir_p(original_entry_dir)
        File.write(File.join(original_entry_dir, "entry.json"), original_entry)
      end
      lfp_tamper_abi(project, "extension_api_version", "4.0.0-static")
      lfp_matrix_parity(project)
    end
  end

  it "rejects runtime-record and lock-platform changes with full compatibility parity" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = lfp_record_paths(project).first
      original = File.read(path)
      payload = JSON.parse(original).as_h
      payload["engine"] = JSON::Any.new("jruby")
      payload["engine_version"] = JSON::Any.new("9.4.0.0")
      File.write(path, payload.to_json)
      lfp_matrix_parity(project)

      File.write(path, original)
      lock_path = File.join(project, "Gemfile.lock")
      lock = File.read(lock_path)
      changed = lock.gsub("PLATFORMS\n  x64-mingw-ucrt", "PLATFORMS\n  x64-mingw-ucrt\n  x86_64-linux")
      changed.should_not eq(lock)
      File.write(lock_path, changed)
      lfp_matrix_parity(project)
    end
  end

  it "rejects a path source with full compatibility parity" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      gem_root = File.join(project, "vendor", "json_pure")
      Dir.mkdir_p(gem_root)
      File.write(File.join(gem_root, "json_pure.gemspec"), <<-CRYSTAL)
        Gem::Specification.new do |s|
          s.name = "json_pure"
          s.version = "2.0.0"
          s.summary = "path source"
          s.authors = ["celerite"]
          s.files = []
        end
        CRYSTAL
      File.write(File.join(project, "Gemfile"), %(source "#{LFP_INDEX}"\n\ngem "json_pure", path: "vendor/json_pure"\n))
      lfp_matrix_parity(project)
    end
  end

  it "prints the hit line on stderr only when CELERITE_FAST_PATH_DEBUG=1" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      status, quiet_out, quiet_err, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH"))
      status.should eq(0)
      procs.should eq(0)
      lfp_fast_path_lines(quiet_err).should be_empty
      quiet_out.should_not contain("fast-path")

      status, loud_out, loud_err, procs, _rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should eq(0)
      lfp_fast_path_lines(loud_err).size.should eq(1)
      loud_err.lines.select(&.starts_with?("fast-path:")).size.should eq(1)
      # The debug line never reaches stdout, and stdout does not change.
      loud_out.should eq(quiet_out)
      loud_out.should_not contain("fast-path")
    end
  end

  it "keeps every lock switch on the Ruby path" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      # Every switch `LOCK_SWITCH_FLAGS`/`LOCK_SWITCH_VALUES` accepts, i.e. the
      # whole surface `lock` has. `--frozen` is not one of them (it is rejected
      # as an unknown switch), so frozen mode is not part of this table.
      switches = [
        ["--print"],
        ["--local"],
        ["--full-index"],
        ["--normalize-platforms"],
        ["--add-checksums"],
        ["--patch"],
        ["--minor"],
        ["--major"],
        ["--pre"],
        ["--strict"],
        ["--conservative"],
        ["--update"],
        ["--add-platform", "x86_64-linux"],
        ["--remove-platform", "x64-mingw-ucrt"],
        ["--bundler", "4.0.24"],
        ["--cooldown", "3"],
        ["--lockfile", "Other.lock"],
      ]
      observed = {} of String => Array(String)
      switches.each do |args|
        lfp_with_env(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")) do
          _status, _output, errors = lfp_run(project, ["lock"] + args)
          observed[args.join(' ')] = lfp_fast_path_lines(errors)
        end
      end
      observed.each do |args, lines|
        lines.should eq(["fast-path: lock miss (switches)"]), "args=#{args} lines=#{lines.inspect}"
      end
    end
  end

  it "prints the lock body and nothing else in --print mode" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)

      lock = File.read(File.join(project, "Gemfile.lock"))
      status = -1
      output = ""
      errors = ""
      lfp_with_env(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")) do
        status, output, errors = lfp_run(project, ["lock", "--print"])
      end
      status.should eq(0)
      lfp_hits(errors).should be_empty
      output.should eq(lock)
    end
  end
end

# A plugin install can change the DSL a Gemfile evaluates to (hooks, `plugin`
# sources, command registration) without touching anything the fingerprint
# digests: `verify.files` covers the Gemfile chain and the gemspecs, and the
# evaluation config records only the plugin root's *path*. So a `deterministic`
# entry written before the install is silent about the project afterwards, and
# the gate has to look at the plugin root on disk instead.
describe "lock refuses the fast path once the plugin root is populated" do
  it "misses with plugin-index and starts the bridge after the plugin root gains an entry" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      digest = lfp_ready(project)

      # The hit that must not survive the plugin install.
      status, _out, quiet_errors, procs, _rpc = lfp_lock(project,
        lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should eq(0)
      lfp_hits(quiet_errors).size.should eq(1)

      # `Bundler::Plugin.root` = `<app_config>/plugin`. An empty directory keeps
      # the reference's behaviour (it only reads `<root>/index`), but the root
      # is no longer empty: from here on the cached evaluation cannot be assumed
      # to describe this project.
      plugin_root = File.join(project, ".bundle", "plugin")
      Dir.mkdir_p(File.join(plugin_root, "cache"))

      status, output, errors, procs, _rpc = lfp_lock(project,
        lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      lfp_hits(errors).should be_empty
      lfp_misses(errors).should eq(["plugin-index"])
      procs.should be >= 1
      output.should contain("Writing lockfile to")
      # Falling back does not change the bytes: the reference is a no-op here
      # too, so the digest the hit would have written is still the one on disk.
      lfp_digest(project).should eq(digest)
    end
  end

  it "still hits when the plugin root exists but is empty" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      Dir.mkdir_p(File.join(project, ".bundle", "plugin"))

      status, _output, errors, procs, _rpc = lfp_lock(project,
        lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      lfp_misses(errors).should be_empty
      lfp_hits(errors).size.should eq(1)
      procs.should eq(0)
    end
  end
end

private def lfp_assert_compat_miss(project : String, reason : String? = nil) : String
  status, output, errors, procs, _rpc = lfp_lock(project,
    lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
  status.should eq(0)
  procs.should be >= 1
  lfp_hits(errors).should be_empty
  misses = lfp_misses(errors)
  misses.size.should eq(1)
  misses.first.should eq(reason) if reason
  output
end

private def lfp_with_read_only(path : String, &)
  {% if flag?(:windows) %}
    attrib = "C:\\Windows\\System32\\attrib.exe"
    set = Process.run(attrib, ["+R", path], output: Process::Redirect::Close, error: Process::Redirect::Close)
    set.success?.should be_true
    expect_raises(File::AccessDeniedError) { File.open(path, "w") { |io| io << "probe" } }
    begin
      yield
    ensure
      Process.run(attrib, ["-R", path], output: Process::Redirect::Close, error: Process::Redirect::Close).success?.should be_true
    end
  {% else %}
    pending!("read-only file attribute is Windows-specific")
  {% end %}
end

describe "task-273 lock byte gate and success certificate transaction" do
  it "misses after one raw lock byte changes and restores the reference bytes" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      digest = lfp_ready(project)
      path = File.join(project, "Gemfile.lock")
      File.write(path, File.read(path) + "# tampered\n")
      lfp_assert_compat_miss(project, "certificate-lock")
      lfp_digest(project).should eq(digest)
    end
  end

  it "misses after LF becomes CRLF" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = File.join(project, "Gemfile.lock")
      lock = File.read(path)
      lock.should_not contain("\r\n")
      File.write(path, lock.gsub("\n", "\r\n"))
      lfp_assert_compat_miss(project, "certificate-lock")
      bytes = File.read(path)
      bytes.should contain("\r\n")
      bytes.gsub("\r\n", "").should_not contain('\n')
    end
  end

  it "misses after BUNDLED WITH changes and rotates the nonce on success" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      digest = lfp_ready(project)
      old_nonce = lfp_record_nonce(project)
      path = File.join(project, "Gemfile.lock")
      lock = File.read(path)
      changed = lock.sub("    4.0.24", "    0.0.0")
      changed.should_not eq(lock)
      File.write(path, changed)
      lfp_assert_compat_miss(project, "certificate-lock")
      lfp_digest(project).should eq(digest)
      lfp_record_nonce(project).should_not eq(old_nonce)
    end
  end

  it "checks the rendered bytes before emitting the hit or Writing line" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = File.join(project, "Gemfile.lock")
      lock = File.read(path)
      changed = lock.sub("    4.0.24", "    0.0.0")
      File.write(path, changed)
      identity = Celerite::CacheIdentity::LockIdentity.detect(path, project_root: project)
      entry_path = lfp_entry_paths(project).first
      payload = JSON.parse(File.read(entry_path)).as_h
      nonce = lfp_record_nonce(project)
      certificates = payload["certificates"].as_h
      certificate = certificates[nonce].as_h
      certificate["lock"] = JSON.parse(identity.to_json)
      File.write(entry_path, payload.to_json)
      output = lfp_assert_compat_miss(project, "lock-render")
      output.lines.count(&.starts_with?("Writing lockfile to ")).should eq(1)
    end
  end

  it "misses after a CHECKSUMS digest changes" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = File.join(project, "Gemfile.lock")
      lock = File.read(path)
      changed = lock.sub(/sha256=[0-9a-f]{64}/) do |match|
        match[0, 71] + (match[71] == '0' ? '1' : '0')
      end
      changed.should_not eq(lock)
      File.write(path, changed)
      lfp_assert_compat_miss(project, "certificate-lock")
    end
  end

  it "misses after the PLATFORMS set changes" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = File.join(project, "Gemfile.lock")
      changed = File.read(path).sub("  x64-mingw-ucrt\n", "  x64-mingw-ucrt\n  x86_64-linux\n")
      File.write(path, changed)
      lfp_assert_compat_miss(project, "platforms")
    end
  end

  it "misses after the Bundler profile changes" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      env = lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
      env["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.23"
      status, _output, errors, procs, _rpc = lfp_lock(project, env)
      status.should eq(0)
      procs.should be >= 1
      lfp_hits(errors).should be_empty
      lfp_misses(errors).size.should eq(1)
    end
  end

  it "misses after the certificate parser revision changes" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = lfp_entry_paths(project).first
      payload = JSON.parse(File.read(path)).as_h
      nonce = lfp_record_nonce(project)
      payload["certificates"].as_h[nonce].as_h["lock"].as_h["parser_revision"] = JSON::Any.new("celerite-lockfile/0")
      File.write(path, payload.to_json)
      lfp_assert_compat_miss(project, "certificate-lock")
    end
  end

  it "misses for legacy /1 and v2 evaluation-only entries" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = lfp_entry_paths(project).first
      original = File.read(path)
      %w[legacy evaluation-only].each do |mode|
        payload = JSON.parse(original).as_h
        if mode == "legacy"
          payload["format"] = JSON::Any.new("celerite-eval-cache/1")
          payload.delete("certificates")
        else
          payload["certificates"] = JSON::Any.new({} of String => JSON::Any)
        end
        File.write(path, payload.to_json)
        begin
          lfp_assert_compat_miss(project, "entry")
        ensure
          File.write(path, original)
        end
      end
    end
  end

  it "does not write a certificate for lock --print" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      entry = lfp_entry_paths(project).first
      record = lfp_record_paths(project).first
      entry_before = File.read(entry)
      record_before = File.read(record)
      lock_before = lfp_digest(project)
      lfp_with_env(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")) do
        status, output, errors = lfp_run(project, ["lock", "--print"])
        status.should eq(0)
        lfp_misses(errors).should eq(["switches"])
      end
      File.read(entry).should eq(entry_before)
      File.read(record).should eq(record_before)
      lfp_digest(project).should eq(lock_before)
    end
  end

  it "preserves the old nonce and lock bytes when the hot-path write fails" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      path = File.join(project, "Gemfile.lock")
      entry = lfp_entry_paths(project).first
      record = lfp_record_paths(project).first
      lock_before = File.read(path)
      entry_before = File.read(entry)
      record_before = File.read(record)
      lfp_with_read_only(path) do
        status, output, errors, procs, _rpc = lfp_lock(project,
          lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
        status.should eq(23)
        procs.should eq(0)
        lfp_hits(errors).size.should eq(1)
        output.should contain("Writing lockfile to")
      end
      File.read(path).should eq(lock_before)
      File.read(entry).should eq(entry_before)
      File.read(record).should eq(record_before)
      Dir.glob(File.join(project, ".Gemfile.lock.*.tmp")).should be_empty
    end
  end

  it "stays on the compatibility path after the final record write fails" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project)
      record = lfp_record_paths(project).first
      File.delete(record)
      parent = File.join(project, ".celerite", "cache", "fast-path")
      Dir.mkdir_p(parent)
      blocker = File.join(parent, "v2")
      File.write(blocker, "block record directory")
      lfp_assert_compat_miss(project, "record")
      lfp_assert_compat_miss(project, "record")
      File.delete(blocker)
      lfp_assert_compat_miss(project, "record")
      lfp_record_paths(project).size.should eq(1)
    end
  end

  it "is a behavioral anti-false-green for the base binary on lock tampering" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      lfp_ready(project, require_v2: false)
      status, _out, errors, procs, _rpc = lfp_lock(project,
        lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should eq(0)
      lfp_hits(errors).size.should eq(1)
      path = File.join(project, "Gemfile.lock")
      lock = File.read(path)
      File.write(path, lock.sub("    4.0.24", "    0.0.0"))
      lfp_assert_compat_miss(project)
    end
  end
end
