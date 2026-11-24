require "spec"

# Windows/POSIX shell-driver contract tests.  These deliberately stop before
# bootstrap/install: the real Rails-scale runs are recorded in the evidence
# documents, not repeated by the product spec suite.
private def bench_m8_path : String
  File.expand_path("../script/bench-m8", __DIR__).gsub('\\', '/')
end

private def run_bench_m8(args : Array(String)) : {Int32, String, String}
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  bash = Process.find_executable("bash").not_nil!.gsub('\\', '/')
  status = Process.run(bash, ["script/bench-m8"] + args,
    chdir: File.expand_path("..", __DIR__), output: stdout, error: stderr)
  {status.exit_code, stdout.to_s, stderr.to_s}
end

describe "bench-m8 driver arguments" do
  it "prints help without starting a benchmark" do
    pending! "bash not available" unless Process.find_executable("bash")
    code, out, err = run_bench_m8(["--help"])
    code.should eq(0)
    out.should contain("--yjit")
    out.should contain("GetProcessIoCounters")
    err.should be_empty
  end

  it "rejects a missing value for every value-taking option" do
    pending! "bash not available" unless Process.find_executable("bash")
    %w(--side --tiers --runs --scratch --out --gemfile --celerite --ruby
      --bundle-exe --jobs --timeout --poll-ms).each do |option|
      code, _out, err = run_bench_m8([option])
      code.should eq(1), option
      err.should contain("missing value for #{option}"), option
    end
  end

  it "rejects empty, zero, nonnumeric and unknown arguments" do
    pending! "bash not available" unless Process.find_executable("bash")
    {
      ["--runs=0"]              => "--runs must be at least 1",
      ["--runs=abc"]            => "--runs must be a positive integer",
      ["--side="]               => "--side must not be empty",
      ["--tiers="]              => "--tiers must not be empty",
      ["--jobs=0"]              => "--jobs must be at least 1",
      ["--timeout=no"]          => "--timeout_s must be a positive integer",
      ["--poll-ms=0"]           => "--poll_ms must be at least 1",
      ["--phase", "cold"]       => "unknown option: --phase",
      ["--side", "not-a-side"]  => "unknown side: not-a-side",
      ["--tiers", "not-a-tier"] => "unknown tier: not-a-tier",
    }.each do |args, message|
      code, _out, err = run_bench_m8(args)
      code.should eq(1), args.join(" ")
      err.should contain(message), args.join(" ")
    end
  end
end

describe "bench-m8 measurement contract" do
  it "declares the root/tree I/O columns consumed by the summary" do
    pending! "bash not available" unless Process.find_executable("bash")
    source = File.read(bench_m8_path)
    columns = source.lines.find(&.includes?("# columns=")).not_nil!
    columns.should contain("io_tree_read_ops io_root_read_ops")
    columns.should contain("io_tree_write_ops io_root_write_ops")
    columns.should contain("io_tree_other_ops io_root_other_ops")
    columns.should contain("io_tree_read_bytes io_root_read_bytes")
    columns.should contain("io_tree_write_bytes io_root_write_bytes")
    columns.should contain("io_tree_other_bytes io_root_other_bytes")
    columns.should contain("lock_sha256 gemspec_count gemspec_manifest_sha256 out_head out_tail")
    columns.split("# columns=", 2).last.not_nil!.split.size.should eq(34)
  end

  it "uses kernel I/O counters and preserves every labelled raw output" do
    pending! "bash not available" unless Process.find_executable("bash")
    source = File.read(bench_m8_path)
    source.should contain("GetProcessIoCounters")
    source.should contain("$identity = [string]$id + '|' + [string]([int64]$created.ToUniversalTime().Ticks)")
    source.should contain("$ioProcess.StartTime.ToUniversalTime()")
    source.should contain("cp \"$seed/proj/out.log\" \"$seed/proj/$label.out\"")
    source.should contain("cp \"$seed/proj/err.log\" \"$seed/proj/$label.err\"")
    source.should contain("checking existing tree before reuse")
    source.should contain("installed tree failed check")
  end

  it "compares lockfiles and installed gemspec manifests across sides" do
    pending! "bash not available" unless Process.find_executable("bash")
    source = File.read(bench_m8_path)
    source.should contain("sha256sum \"$workdir/Gemfile.lock\"")
    source.should contain("sha256sum *.gemspec | LC_ALL=C sort | sha256sum")
    source.should contain("lock_c=$(field celerite \"$tier\" 28")
    source.should contain("count_c=$(field celerite \"$tier\" 29")
    source.should contain("manifest_c=$(field celerite \"$tier\" 30")
    source.should contain("cmp -s \"$c_lock\" \"$b_lock\"")
    source.should contain("awk -F'\\t' 'NF >= 34")
    source.should contain("printf '%s\\n' \"$tail\" >>\"$OUT\"")
    source.should_not contain("printf '\\n' >>\"$OUT\"")
    source.should contain("if [ \"$WANT_YJIT\" = 1 ] && [ \"$yjit_state\" != \"available\" ]; then")
  end
end
