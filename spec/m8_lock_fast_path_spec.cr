require "./spec_helper"

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
  path = File.expand_path("../bin/celerite.exe", __DIR__)
  File.exists?(path) ? path : nil
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
  Dir.glob(File.join(project, ".celerite", "cache", "fast-path", "v1", "*", "*.json").tr("\\", "/"))
end

private def lfp_entry_paths(project : String) : Array(String)
  Dir.glob(File.join(project, ".celerite", "cache", "eval", "*", "v1", "*", "entry.json").tr("\\", "/"))
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
private def lfp_ready(project : String) : String
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

  lfp_record_paths(project).size.should eq(1)
  lfp_digest(project)
end

describe "lock takes the no-Ruby fast path on an unchanged project" do
  it "rewrites the locked bytes with procs=0 when the switches are on and both caches are warm" do
    with_project({} of String => String) do |project|
      lfp_pending!(project)
      digest = lfp_ready(project)
      lock_before = File.read(File.join(project, "Gemfile.lock"))

      status, output, errors, procs, rpc = lfp_lock(project, lfp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG"))
      status.should eq(0)
      procs.should eq(0)
      rpc.should eq(0)
      lfp_hits(errors).size.should eq(1)
      lfp_hits(errors).first.should eq(lfp_fingerprint_digest(project)[0, 12])
      lfp_misses(errors).should be_empty
      output.should eq("Writing lockfile to #{File.join(project, "Gemfile.lock").gsub('\\', "/")}\n")
      File.read(File.join(project, "Gemfile.lock")).should eq(lock_before)
      lfp_digest(project).should eq(digest)
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
