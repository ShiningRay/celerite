#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
require_relative "../script/bench_m8"
require_relative "../script/bench_m8_collector"
require_relative "../script/bench_m8_validator"

$passed = 0
$failures = []

def assert(condition, message)
  raise message unless condition
end

def check(name)
  yield
  $passed += 1
  puts "ok - #{name}"
rescue StandardError => error
  $failures << [name, error]
  warn "not ok - #{name}: #{error.class}: #{error.message}"
end

def option_error(argv)
  BenchM8::Options.parse(argv)
  nil
rescue BenchM8::Error => error
  error
end

def sha256(text)
  Digest::SHA256.hexdigest(text)
end

def manifest_digest(rows)
  text = rows.map do |row|
    [row["relative_path"], row["basename"], row["sha256"], row["bytes"]].join("\t")
  end.join("\n")
  sha256(text)
end

class FakeTreeSampler < BenchM8::LinuxCollector::TreeSampler
  attr_accessor :io_fixture, :children_fixture

  def initialize(clock_ticks: 100, page_size: 4096)
    super
    @io_fixture = {}
    @children_fixture = {}
  end

  private

  def read_io(pid)
    @io_fixture[pid]
  end

  def child_stats(pid)
    @children_fixture.fetch(pid, []).map do |pid, starttime, utime, stime, rss_pages|
      BenchM8::LinuxCollector::Stat.new(pid: pid, starttime: starttime, state: "S",
        utime: utime, stime: stime, rss_pages: rss_pages)
    end
  end
end

def fixture_io(offset = 0)
  BenchM8::LinuxCollector::IO_KEYS.each_with_object({}) { |key, result| result[key] = offset + 1 }
end

def stat(pid:, starttime:, utime:, stime:, rss_pages:)
  BenchM8::LinuxCollector::Stat.new(pid: pid, starttime: starttime, state: "S",
    utime: utime, stime: stime, rss_pages: rss_pages)
end

def smoke_fixture(directory)
  manifest = {
    "run_id" => "fixture-run", "run_attempt" => "1", "baseline_sha" => "b" * 40,
    "matrix_mode" => "smoke", "sides" => %w[celerite bundle], "runs" => 1,
    "warmup" => 1, "jobs" => 4,
    "reference" => { "lock_sha256" => "a" * 64, "gemfile_sha256" => "c" * 64 },
    "lock_sha256" => "a" * 64,
    "normalization" => { "oracle_spec_exclusion" => "bundler-4.0.24.gemspec" }
  }
  gemfile = "source 'https://rubygems.org'\n"
  lock = "GEM\n  specs:\n    example (1.0)\n"
  File.binwrite(File.join(directory, "Gemfile"), gemfile)
  File.binwrite(File.join(directory, "Gemfile.lock"), lock)
  manifest["ruby_modes"] = %w[off on]
  manifest["tiers"] = %w[hot noop]
  manifest["reference"]["gemfile_sha256"] = sha256(gemfile)
  manifest["reference"]["lock_sha256"] = sha256(lock)
  manifest["lock_sha256"] = sha256(lock)
  rows = []
  actual_order = []
  %w[hot noop].each do |tier|
    %w[off on].each do |ruby_mode|
      [0, 1].each do |round|
        kind = round.zero? ? "warmup" : "measured"
        sides = round.even? ? %w[celerite bundle] : %w[celerite bundle].reverse
        sides.each do |side|
          sequence = rows.length + 1
          sample_id = "#{kind}-#{side}-#{ruby_mode}-#{tier}-#{round}"
          raw = File.join("raw", side, ruby_mode, tier, round.to_s, sample_id)
          raw = File.join("warmup", raw) if kind == "warmup"
          FileUtils.mkdir_p([File.join(directory, raw), File.join(directory, raw, "lock")])
          stdout = "same normalized output\n"
          stderr = ""
          File.binwrite(File.join(directory, raw, "stdout.txt"), stdout)
          File.binwrite(File.join(directory, raw, "stderr.txt"), stderr)
          File.binwrite(File.join(directory, raw, "exit.txt"),
            "exit_status=0\nsignal=nil\ntimed_out=false\n")
          File.binwrite(File.join(directory, raw, "lock", "Gemfile"), gemfile)
          File.binwrite(File.join(directory, raw, "lock", "Gemfile.lock"), lock)
          raw_specs = [
            { "relative_path" => "specifications/bundler-4.0.24.gemspec", "basename" => "bundler-4.0.24.gemspec",
              "sha256" => "1" * 64, "bytes" => 10 },
            { "relative_path" => "specifications/example-1.0.gemspec", "basename" => "example-1.0.gemspec",
              "sha256" => "2" * 64, "bytes" => 20 }
          ]
          normalized_specs = raw_specs.reject { |entry| entry["basename"] == "bundler-4.0.24.gemspec" }
          File.write(File.join(directory, raw, "gemspecs.tsv"),
            (["relative_path\tbasename\tsha256\tbytes\tnormalized_excluded"] +
              raw_specs.map do |entry|
                marker = entry["basename"] == "bundler-4.0.24.gemspec" ? "true" : "false"
                [entry["relative_path"], entry["basename"], entry["sha256"], entry["bytes"], marker].join("\t")
              end).join("\n") + "\n")
          root_io = fixture_io
          tree_io = fixture_io(2)
          rpc = side == "bundle" ? ["N/A"] * 4 : [1, 2, 3, 4]
          row = {
            "sequence" => sequence, "sample_id" => sample_id, "kind" => kind,
            "run_id" => manifest["run_id"], "run_attempt" => manifest["run_attempt"],
            "baseline_sha" => manifest["baseline_sha"], "side" => side, "ruby_mode" => ruby_mode,
            "tier" => tier, "round" => round, "command" => [side, tier],
            "exit_status" => 0, "signal" => nil, "timed_out" => false,
            "wall_s" => 1.0, "root_cpu_user_s" => 0.1, "root_cpu_system_s" => 0.2,
            "root_rss_peak_kb" => 100, "tree_cpu_user_s" => 0.3, "tree_cpu_system_s" => 0.4,
            "tree_rss_peak_kb" => 200, "root_io" => root_io, "tree_io" => tree_io,
            "collector_complete" => true, "missing_metrics" => [], "identity_changed" => false,
            "root_pid" => 123, "root_starttime" => 456, "observed_process_count" => 2,
            "yjit_compiled" => true, "yjit_requested" => ruby_mode, "yjit_enabled" => ruby_mode == "on",
            "lock_sha256" => manifest["lock_sha256"], "gemspec_count" => 2,
            "gemspec_manifest_sha256" => manifest_digest(raw_specs),
            "normalized_gemspec_count" => 1,
            "normalized_gemspec_manifest_sha256" => manifest_digest(normalized_specs),
            "stdout_sha256" => sha256(stdout), "stderr_sha256" => sha256(stderr),
            "stdout_bytes" => stdout.bytesize, "stderr_bytes" => 0,
            "normalized_stdout_sha256" => sha256(stdout),
            "rpc_procs" => rpc[0], "rpc_count" => rpc[1],
            "rpc_req_bytes" => rpc[2], "rpc_resp_bytes" => rpc[3],
            "raw_dir" => raw
          }
          File.write(File.join(directory, raw, "metrics.json"), JSON.generate(row))
          rows << row
          actual_order << row.slice("sequence", "sample_id", "side", "ruby_mode", "tier", "round", "kind")
        end
      end
    end
  end
  manifest["actual_order"] = actual_order
  File.write(File.join(directory, "manifest.json"), JSON.generate(manifest))
  File.write(File.join(directory, "samples.jsonl"), rows.map { |row| JSON.generate(row) }.join("\n") + "\n")
  manifest
end

check("options accept every required explicit path and per-tier timeout") do
  options = BenchM8::Options.parse([
    "--celerite", "/repo/bin/celerite", "--ruby", "/ruby/bin/ruby", "--bundle-exe", "/ruby/bin/bundle",
    "--scratch", "/scratch", "--out", "/out", "--jobs", "2", "--runs", "5", "--warmup", "1",
    "--baseline-sha", "a" * 40, "--run-id", "run-1", "--run-attempt", "7",
    "--cold-timeout", "1201", "--hot-timeout", "602", "--noop-timeout", "603",
    "--ruby-mode", "off", "--ruby-mode", "on"
  ])
  assert(options.celerite == "/repo/bin/celerite", "celerite override missing")
  assert(options.ruby == "/ruby/bin/ruby", "ruby override missing")
  assert(options.bundle_exe == "/ruby/bin/bundle", "bundle override missing")
  assert(options.scratch == "/scratch" && options.out == "/out", "scratch/out overrides missing")
  assert([options.cold_timeout, options.hot_timeout, options.noop_timeout] == [1201, 602, 603], "per-tier timeouts lost")
  assert(options.ruby_modes == %w[off on], "ruby modes lost")
  assert(options.jobs == 2 && options.runs == 5 && options.warmup == 1, "matrix overrides lost")
  driver = BenchM8::Driver.new(options)
  assert(driver.send(:command_for, "bundle", "hot")[2] == "_4.0.24_", "sample Bundler version is not pinned")
end

check("options enforce mode-specific matrix and required values") do
  assert(option_error(["--baseline-sha", "abc"]), "short baseline accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--runs"]), "missing option value accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--ruby-mode", "auto"]), "invalid ruby mode accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--mode", "smoke", "--runs", "2"]), "smoke n2 accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--mode", "smoke", "--tiers", "cold,hot,noop"]), "smoke cold tier accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--mode", "full", "--runs", "2"]), "full n2 accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--mode", "full", "--warmup", "2"]), "full warmup2 accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--side", "celerite"]), "single-side final matrix accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--ruby-mode", "off"]), "single-YJIT-mode final matrix accepted")
  assert(option_error(["--baseline-sha", "a" * 40, "--jobs", "0"]), "jobs0 accepted")
  missing = BenchM8::Options.parse([])
  driver = BenchM8::Driver.new(missing)
  error = nil
  begin
    driver.send(:verify_baseline!)
  rescue BenchM8::Error => caught
    error = caught
  end
  assert(error&.message&.include?("--baseline-sha is required"), "missing baseline did not fail in driver")
  wrong = BenchM8::Options.parse(["--baseline-sha", "0" * 40])
  error = nil
  begin
    BenchM8::Driver.new(wrong).send(:verify_baseline!)
  rescue BenchM8::Error => caught
    error = caught
  end
  assert(error&.message&.include?("does not equal HEAD"), "wrong baseline did not fail in driver")
end

check("RPC parsing fails closed for missing, malformed and duplicate counters") do
  driver = BenchM8::Driver.new(BenchM8::Options.parse(["--baseline-sha", "a" * 40]))
  assert(driver.send(:parse_rpc, "bridge: procs=2 rpc=3 req_bytes=4 resp_bytes=5\n") == [2, 3, 4, 5], "labelled RPC failed")
  assert(driver.send(:parse_rpc, "{2, 3, 4, 5}") == [2, 3, 4, 5], "compact RPC failed")
  ["", "procs=2 rpc=3 req_bytes=4", "procs=x rpc=3 req_bytes=4 resp_bytes=5",
   "procs=2 rpc=3 req_bytes=4 resp_bytes=5\nprocs=2 rpc=3 req_bytes=4 resp_bytes=5"].each do |text|
    assert(driver.send(:parse_rpc, text) == [nil, nil, nil, nil], "invalid RPC accepted: #{text.inspect}")
  end
  row = { "rpc_procs" => nil, "rpc_count" => nil, "rpc_req_bytes" => nil, "rpc_resp_bytes" => nil }
  assert(driver.send(:tsv_value, row, "rpc_procs") == "", "nil RPC was fabricated as zero")
end

check("gemspec normalization excludes only the configured oracle spec") do
  Dir.mktmpdir("m8-gemspecs") do |directory|
    bundle = File.join(directory, "bundle")
    specifications = File.join(bundle, "ruby", "4.0.0", "specifications")
    FileUtils.mkdir_p(specifications)
    %w[bundler-4.0.24.gemspec example-1.0.gemspec].each do |name|
      File.write(File.join(specifications, name), name)
    end
    driver = BenchM8::Driver.new(BenchM8::Options.parse(["--baseline-sha", "a" * 40]))
    result = driver.send(:collect_gemspecs, bundle)
    assert(result["raw_count"] == 2, "raw gemspec count mismatch: #{result.inspect}")
    assert(result["normalized_count"] == 1, "normalization excluded the wrong entry")
    assert(result["normalized_sha256"] != result["raw_sha256"], "normalized digest did not change")
  end
end

check("proc stat parsing is identity-aware and fails closed") do
  fields = Array.new(22, "0")
  fields[0] = "S"
  fields[11] = "12"
  fields[12] = "3"
  fields[19] = "99"
  fields[21] = "4"
  parsed = BenchM8::LinuxCollector.parse_stat(42, "42 (ruby worker) #{fields.join(' ')}")
  assert(parsed && parsed.pid == 42 && parsed.starttime == 99 && parsed.utime == 12 && parsed.stime == 3 && parsed.rss_pages == 4,
    "valid /proc stat fields were not parsed")
  assert(BenchM8::LinuxCollector.parse_stat(42, "broken").nil?, "malformed stat accepted")
  fields[19] = "unknown"
  assert(BenchM8::LinuxCollector.parse_stat(42, "42 (ruby) #{fields.join(' ')}").nil?, "nonnumeric starttime accepted")
end

check("tree sampler sums identities and marks missing child IO incomplete") do
  sampler = FakeTreeSampler.new
  sampler.io_fixture = { 1 => fixture_io, 2 => fixture_io(2) }
  sampler.children_fixture = { 1 => [[2, 101, 5, 1, 25]] }
  sampler.root_identity = [1, 100]
  sampler.sample(stat(pid: 1, starttime: 100, utime: 10, stime: 2, rss_pages: 10))
  sampler.sample(stat(pid: 1, starttime: 100, utime: 20, stime: 4, rss_pages: 20))
  assert(sampler.tree_cpu_user == 0.25, "tree CPU did not sum per-identity maxima")
  assert(sampler.tree_cpu_system == 0.05, "tree system CPU mismatch")
  assert(sampler.tree_rss_peak_kb > 100, "tree RSS did not include child")
  assert(sampler.tree_io.values.sum == fixture_io.values.sum + fixture_io(2).values.sum, "tree IO did not sum identities")
  assert(sampler.root_io == fixture_io, "root IO was changed")
  assert(sampler.complete?, "complete fake tree marked incomplete")
  sampler.io_fixture.delete(2)
  sampler.sample(stat(pid: 1, starttime: 100, utime: 30, stime: 6, rss_pages: 20))
  assert(sampler.complete?, "process exit race discarded previously complete child IO")

  incomplete = FakeTreeSampler.new
  incomplete.io_fixture = { 1 => fixture_io }
  incomplete.children_fixture = { 1 => [[2, 101, 5, 1, 25]] }
  incomplete.root_identity = [1, 100]
  incomplete.sample(stat(pid: 1, starttime: 100, utime: 10, stime: 2, rss_pages: 10))
  assert(incomplete.tree_io.nil?, "missing child IO was silently replaced with root-only IO")
  assert(!incomplete.complete?, "missing child IO was marked complete")
end

check("manual workflow is dispatch-only, pinned, fail-closed and secret-free") do
  workflow = YAML.load_file(File.join(ROOT, ".github/workflows/m8-rails-final.yml"))
  trigger = workflow.key?("on") ? workflow["on"] : workflow[true]
  assert(trigger.keys == ["workflow_dispatch"], "workflow has a non-manual trigger")
  assert(workflow["permissions"] == { "contents" => "read" }, "permissions are not minimal")
  job = workflow.fetch("jobs").fetch("rails-final")
  assert(job["runs-on"] == "ubuntu-24.04", "runner is not Ubuntu 24.04")
  assert(job["timeout-minutes"] == 180, "job timeout missing")
  steps = job.fetch("steps")
  run_text = steps.filter_map { |step| step["run"] }.join("\n")
  assert(run_text.include?('^[0-9a-f]{40}$'), "workflow does not validate full baseline SHA")
  steps.each do |step|
    next unless step["uses"]
    assert(step["uses"].match?(/@[0-9a-f]{40}\z/), "mutable action: #{step['uses']}")
  end
  driver_source = File.read(File.join(ROOT, "script/bench_m8.rb"))
  assert(run_text.include?("--probe-only") && driver_source.include?("RubyVM::YJIT.enabled? == false"), "YJIT fail-closed probe missing")
  assert(run_text.include?("--self-test"), "collector self-test missing")
  assert(run_text.include?("--mode") && driver_source.include?("Validator.new") && driver_source.include?("validator.generate_summary if ok"), "validator gate missing")
  assert(run_text.include?("--jobs 4"), "parallel Bundler job setting differs from matrix contract")
  assert(!run_text.include?("secrets.") && !run_text.include?("GITHUB_TOKEN"), "workflow references secrets")
  setup = steps.find { |step| step["uses"]&.start_with?("ruby/setup-ruby@") }
  assert(setup && setup["with"]["bundler-cache"] == false, "bundler-cache enabled")
  upload = steps.find { |step| step["uses"]&.start_with?("actions/upload-artifact@") }
  assert(upload && upload["if"] == "always()", "failure artifact upload missing")
  assert(upload["with"]["name"].include?("${{ inputs.baseline_sha }}"), "artifact name lacks baseline SHA")
end

check("validator emits a summary only for a complete current smoke run") do
  Dir.mktmpdir("m8-validator-pass") do |directory|
    fixture = smoke_fixture(directory)
    validator = BenchM8::Validator.new(directory)
    assert(validator.validate, validator.errors.join("\n"))
    summary = validator.generate_summary
    assert(File.file?(File.join(directory, "summary.json")), "valid run did not produce summary")
    summary = JSON.parse(File.read(File.join(directory, "summary.json")))
    assert(summary["units"].length == 8, "smoke summary unit count mismatch")
    assert(summary["units"].values.all? { |unit| unit["n"] == 1 }, "smoke summary n mismatch")
    assert(File.file?(File.join(directory, "summary.tsv")), "valid run did not produce TSV")
    validate_options = BenchM8::Options.parse(["--validate-only", "--out", directory, "--scratch", File.join(directory, "scratch")])
    assert(BenchM8::Driver.new(validate_options).run, "validate-only rerun failed")
    assert(File.file?(File.join(directory, "samples.jsonl")), "validate-only deleted raw sample index")
    assert(File.file?(File.join(directory, "checksums.sha256")), "validate-only did not reseal checksums")
  end
end

check("validator fails closed and removes stale summary on invalid evidence") do
  Dir.mktmpdir("m8-validator-fail") do |directory|
    smoke_fixture(directory)
    samples_path = File.join(directory, "samples.jsonl")
    rows = File.readlines(samples_path).map { |line| JSON.parse(line) }
    mutations = [
      ->(copy) { copy[0]["run_id"] = "stale-run" },
      ->(copy) { copy[0]["baseline_sha"] = "0" * 40 },
      ->(copy) { copy[0]["root_io"].delete("rchar") },
      ->(copy) { copy[0]["tree_io"]["write_bytes"] = nil },
      ->(copy) { copy[0]["timed_out"] = true },
      ->(copy) { copy[0]["exit_status"] = 1 },
      ->(copy) { copy[0]["yjit_enabled"] = true },
      ->(copy) { copy.find { |row| row["side"] == "bundle" }["rpc_count"] = 0 },
      ->(copy) { copy.find { |row| row["side"] == "celerite" }["rpc_count"] = nil },
      ->(copy) { copy[0]["gemspec_count"] = 0 },
      ->(copy) { copy[0]["lock_sha256"] = "d" * 64 },
      ->(copy, path = directory) { File.write(File.join(path, "manifest.json"),
        JSON.generate(JSON.parse(File.read(File.join(path, "manifest.json"))).merge(
          "actual_order" => JSON.parse(File.read(File.join(path, "manifest.json")))["actual_order"].reverse))) }
    ]
    mutations.each_with_index do |mutation, index|
      Dir.mktmpdir("m8-validator-invalid") do |case_directory|
        smoke_fixture(case_directory)
        case_rows = File.readlines(File.join(case_directory, "samples.jsonl")).map { |line| JSON.parse(line) }
        mutation.call(case_rows, case_directory) if index == 11
        mutation.call(case_rows) unless index == 11
        File.write(File.join(case_directory, "samples.jsonl"), case_rows.map { |row| JSON.generate(row) }.join("\n") + "\n")
        File.write(File.join(case_directory, "summary.json"), "stale")
        File.write(File.join(case_directory, "summary.tsv"), "stale")
        validator = BenchM8::Validator.new(case_directory)
        assert(!validator.validate, "invalid mutation #{index} passed: #{validator.errors.join(' | ')}")
        assert(!File.exist?(File.join(case_directory, "summary.json")), "invalid mutation #{index} retained summary")
        assert(!File.exist?(File.join(case_directory, "summary.tsv")), "invalid mutation #{index} retained TSV")
      end
    end
    assert(rows.length == 16, "fixture row count mismatch")
  end
end

puts "#{$passed} checks, #{$failures.length} failures"
exit($failures.empty? ? 0 : 1)
