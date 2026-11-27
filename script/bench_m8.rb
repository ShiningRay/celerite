#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "etc"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "shellwords"
require "time"
require_relative "bench_m8_collector"
require_relative "bench_m8_validator"

module BenchM8
  class Error < StandardError; end

  class Options
    attr_accessor :repo_root, :celerite, :ruby, :bundle_exe, :scratch, :out, :gemfile, :reference_lock
    attr_accessor :baseline_sha, :run_id, :run_attempt, :workflow_ref, :mode, :runs, :warmup, :jobs
    attr_accessor :cold_timeout, :hot_timeout, :noop_timeout, :poll_ms, :oracle_spec
    attr_accessor :sides, :ruby_modes, :tiers, :self_test, :probe_only, :validate_only, :help
    attr_reader :requested

    def initialize
      @repo_root = File.expand_path("..", __dir__)
      @celerite = File.join(@repo_root, "bin", "celerite")
      @ruby = RbConfig.ruby
      @bundle_exe = ENV["BUNDLE_EXE"] || "bundle"
      @scratch = File.join(Dir.tmpdir, "celerite-m8-scratch")
      @out = File.join(Dir.tmpdir, "celerite-m8-artifacts")
      @run_id = ENV["GITHUB_RUN_ID"] || "local"
      @run_attempt = Integer(ENV["GITHUB_RUN_ATTEMPT"] || "1", 10)
      @workflow_ref = ENV["GITHUB_WORKFLOW_REF"]
      @mode = "full"
      @runs = nil
      @warmup = 1
      @jobs = 4
      @cold_timeout = 1800
      @hot_timeout = 120
      @noop_timeout = 120
      @poll_ms = 20
      @oracle_spec = "bundler-4.0.24.gemspec"
      @sides = %w[celerite bundle]
      @ruby_modes = []
      @tiers = []
      @self_test = false
      @probe_only = false
      @validate_only = false
      @help = false
      @requested = []
    end

    def timeout_for(tier)
      case tier
      when "cold" then cold_timeout
      when "hot" then hot_timeout
      when "noop" then noop_timeout
      else raise Error, "unknown tier: #{tier}"
      end
    end

    def self.parse(argv)
      options = new
      index = 0
      while index < argv.length
        argument = argv[index]
        if argument == "--help" || argument == "-h"
          options.help = true
          return options
        end
        name, inline = argument.split("=", 2)
        if %w[--self-test --probe-only --validate-only].include?(name)
          raise Error, "#{name} does not take a value" unless inline.nil?

          case name
          when "--self-test" then options.self_test = true
          when "--probe-only" then options.probe_only = true
          when "--validate-only" then options.validate_only = true
          end
          index += 1
          next
        end

        value = inline
        if value.nil?
          index += 1
          raise Error, "missing value for #{name}" if index >= argv.length || argv[index].start_with?("--")
          value = argv[index]
        end
        raise Error, "#{name} must not be empty" if value.empty?

        case name
        when "--celerite" then options.celerite = value
        when "--ruby" then options.ruby = value
        when "--bundle-exe" then options.bundle_exe = value
        when "--scratch" then options.scratch = value
        when "--out" then options.out = value
        when "--gemfile" then options.gemfile = value
        when "--reference-lock" then options.reference_lock = value
        when "--baseline-sha" then options.baseline_sha = value
        when "--run-id" then options.run_id = value
        when "--run-attempt" then options.run_attempt = positive_integer(name, value)
        when "--workflow-ref" then options.workflow_ref = value
        when "--mode" then options.mode = value
        when "--runs" then options.runs = positive_integer(name, value)
        when "--warmup" then options.warmup = nonnegative_integer(name, value)
        when "--jobs" then options.jobs = positive_integer(name, value)
        when "--timeout"
          timeout = positive_integer("--timeout_s", value)
          options.cold_timeout = options.hot_timeout = options.noop_timeout = timeout
        when "--cold-timeout" then options.cold_timeout = positive_integer(name, value)
        when "--hot-timeout" then options.hot_timeout = positive_integer(name, value)
        when "--noop-timeout" then options.noop_timeout = positive_integer(name, value)
        when "--poll-ms" then options.poll_ms = positive_integer(name, value)
        when "--oracle-spec" then options.oracle_spec = value
        when "--side"
          values = value.split(",").map(&:strip)
          unknown = values - %w[celerite bundle]
          raise Error, "unknown side: #{unknown.first}" unless unknown.empty?
          options.sides = values.uniq
        when "--tiers"
          values = value.split(",").map(&:strip)
          unknown = values - %w[cold hot noop]
          raise Error, "unknown tier: #{unknown.first}" unless unknown.empty?
          options.tiers = values.uniq
        when "--ruby-mode"
          raise Error, "--ruby-mode must be off or on" unless %w[off on].include?(value)
          options.ruby_modes << value unless options.ruby_modes.include?(value)
        else
          raise Error, "unknown option: #{name}"
        end
        options.requested << [name, value]
        index += 1
      end

      raise Error, "--mode must be smoke or full" unless %w[smoke full].include?(options.mode)
      options.tiers = options.mode == "smoke" ? %w[hot noop] : %w[cold hot noop] if options.tiers.empty?
      options.ruby_modes = %w[off on] if options.ruby_modes.empty?
      options.runs ||= options.mode == "smoke" ? 1 : 5
      if options.mode == "smoke"
        raise Error, "smoke mode requires --runs 1" unless options.runs == 1
        raise Error, "smoke mode requires --tiers hot,noop" unless options.tiers == %w[hot noop]
      end
      if options.mode == "full"
        raise Error, "full mode requires --runs 5" unless options.runs == 5
        raise Error, "full mode requires --warmup 1" unless options.warmup == 1
        raise Error, "full mode requires --tiers cold,hot,noop" unless options.tiers == %w[cold hot noop]
      end
      raise Error, "final matrix requires --side celerite,bundle" unless options.sides == %w[celerite bundle]
      raise Error, "final matrix requires --ruby-mode off --ruby-mode on" unless options.ruby_modes == %w[off on]
      raise Error, "--warmup must be at least 1 for the final matrix" if options.warmup < 1
      raise Error, "--baseline-sha must be a full 40-character commit" if options.baseline_sha && !options.baseline_sha.match?(/\A[0-9a-f]{40}\z/)
      options
    end

    def self.positive_integer(name, value)
      raise Error, "#{name} must be a positive integer" unless value.match?(/\A\d+\z/)
      integer = value.to_i
      raise Error, "#{name} must be at least 1" if integer < 1
      integer
    end

    def self.nonnegative_integer(name, value)
      raise Error, "#{name} must be a nonnegative integer" unless value.match?(/\A\d+\z/)
      value.to_i
    end

    def help_text
      <<~HELP
        Usage: script/bench-m8 [options]

        M8 Rails 8.0.2 final benchmark driver (Linux collector).
        Full matrix: 2 sides x cold/hot/noop x YJIT off/on, warmup=1, n=5.
        Smoke matrix: 2 sides x hot/noop x YJIT off/on, warmup=1, n=1.

        Required for a measured run:
          --baseline-sha SHA          Exact immutable HEAD (40 hex characters)

        Toolchain and paths:
          --celerite PATH             Current baseline bin/celerite
          --ruby PATH                 Ruby 4.0.6 executable
          --bundle-exe PATH           Bundler 4.0.24 executable
          --scratch DIR               Isolated scratch root
          --out DIR                   Artifact output root
          --gemfile PATH              Optional fixed Rails Gemfile
          --reference-lock PATH       Optional pre-generated reference lock

        Matrix:
          --mode smoke|full           Default: full
          --side celerite,bundle      Default: both
          --tiers cold,hot,noop       Default: mode-specific
          --ruby-mode off|on          Repeat for both; default: off then on
          --runs N                    Default: 5 full / 1 smoke
          --warmup N                  Default: 1
          --jobs N                    Default: 4
          --cold-timeout SEC          Default: 1800
          --hot-timeout SEC           Default: 120
          --noop-timeout SEC          Default: 120
          --timeout SEC               Legacy override for all tiers
          --poll-ms MS                Linux collector interval; default: 20
          --oracle-spec NAME          One explicit normalization exclusion
                                       Default: bundler-4.0.24.gemspec

        Evidence identity:
          --run-id ID                 Default: GITHUB_RUN_ID or local
          --run-attempt N             Default: GITHUB_RUN_ATTEMPT or 1
          --workflow-ref REF          Default: GITHUB_WORKFLOW_REF

        Operations:
          --probe-only                Record YJIT compiled/requested/enabled
          --self-test                 Run Linux collector self-test only
          --validate-only             Validate existing artifact and summarize
          --help                      Show this help
      HELP
    end
  end

  class Driver
    SAMPLE_COLUMNS = %w[
      sample_id kind run_id run_attempt baseline_sha side ruby_mode tier round
      started_at_utc ended_at_utc command scratch_id exit_status signal timed_out
      stdout_bytes stderr_bytes stdout_sha256 stderr_sha256 normalized_stdout_sha256
      lock_sha256 gemspec_count gemspec_manifest_sha256 normalized_gemspec_count
      normalized_gemspec_manifest_sha256 wall_s root_cpu_user_s root_cpu_system_s
      tree_cpu_user_s tree_cpu_system_s root_rss_peak_kb tree_rss_peak_kb
      root_read_bytes root_write_bytes root_syscr root_syscw tree_read_bytes
      tree_write_bytes tree_syscr tree_syscw rpc_procs rpc_count rpc_req_bytes
      rpc_resp_bytes yjit_compiled yjit_requested yjit_enabled collector_complete
      missing_metrics raw_dir
    ].freeze

    def initialize(options)
      @options = options
      @out = File.expand_path(options.out)
      @scratch = File.expand_path(options.scratch)
      @samples = []
      @sequence = []
      @unit_bounds = {}
      @probes = {}
      @prepared = false
      @manifest = {}
      @sample_index = 0
      @reference = {}
    end

    def run
      if @options.validate_only
        @prepared = true
        validator = Validator.new(@out)
        ok = validator.validate
        validator.generate_summary if ok
        return ok
      end

      prepare_out!
      verify_baseline!
      probe_yjit!
      write_probe_log
      if @options.probe_only
        @manifest = base_manifest(status: "probe-passed")
        write_manifest
        return true
      end

      if @options.self_test
        begin
          result = LinuxCollector.self_test(poll_ms: @options.poll_ms, ruby: @options.ruby)
          File.binwrite(File.join(@out, "logs", "collector-self-test.txt"), JSON.pretty_generate(result) + "\n")
        rescue StandardError => error
          File.binwrite(File.join(@out, "logs", "collector-self-test.txt"), "FAIL #{error.class}: #{error.message}\n")
          raise
        end
        @manifest = base_manifest(status: "collector-self-test-passed")
        @manifest["collector_self_test"] = result
        write_manifest
        return true
      end

      verify_toolchain!
      prepare_reference!
      @manifest = base_manifest(status: "running")
      write_manifest
      execute_matrix!
      persist_samples!
      @manifest["status"] = "samples-complete"
      @manifest["finished_at_utc"] = Time.now.utc.iso8601
      write_manifest
      validator = Validator.new(@out)
      ok = validator.validate
      if ok
        validator.generate_summary
        @manifest["status"] = "validated"
        @manifest["summary"] = "summary.json/summary.tsv"
      else
        @manifest["status"] = "validator-failed"
        @manifest["validator_errors"] = validator.errors
      end
      write_manifest
      ok
    rescue StandardError => error
      record_failure(error)
      false
    ensure
      write_checksums if @prepared
    end

    private

    def prepare_out!
      forbidden = ["/", "/root", File.expand_path(Dir.home), @options.repo_root].compact
      raise Error, "refusing unsafe --out path: #{@out}" if forbidden.include?(@out)

      FileUtils.mkdir_p([File.join(@out, "logs"), @scratch])
      %w[raw warmup seeds].each { |name| FileUtils.rm_rf(File.join(@out, name)) }
      %w[samples.jsonl samples.tsv summary.json summary.tsv validator.json validator.txt].each do |name|
        path = File.expand_path(name, @out)
        FileUtils.rm_f(path) if File.dirname(path) == @out
      end
      File.binwrite(File.join(@out, "commands.txt"), "# task-282 M8 Rails final benchmark\n")
      @prepared = true
    end

    def verify_baseline!
      baseline = @options.baseline_sha
      raise Error, "--baseline-sha is required" unless baseline
      head, status = Open3.capture2("git", "-C", @options.repo_root, "rev-parse", "HEAD")
      raise Error, "git rev-parse HEAD failed" unless status.success?
      raise Error, "baseline_sha #{baseline} does not equal HEAD #{head.strip}" unless head.strip == baseline

      dirty, status = Open3.capture2("git", "-C", @options.repo_root, "status", "--porcelain")
      raise Error, "git status failed" unless status.success?
      raise Error, "baseline worktree is not clean:\n#{dirty}" unless dirty.empty?
    end

    def probe_yjit!
      compiled_out, compiled_err, compiled_status = Open3.capture3(
        { "RUBYOPT" => "", "RUBY_YJIT_ENABLE" => "0" }, @options.ruby, "-e",
        'puts(defined?(RubyVM::YJIT) ? "compiled" : "missing")'
      )
      compiled = compiled_status.success? && compiled_out.strip == "compiled"
      @options.ruby_modes.each do |mode|
        code = if mode == "on"
          'abort "YJIT unavailable" unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?; puts "enabled"'
        else
          'abort "YJIT off requires compiled support and actual disabled state" unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? == false; puts "disabled"'
        end
        stdout, stderr, status = Open3.capture3(
          { "RUBYOPT" => "", "RUBY_YJIT_ENABLE" => mode == "on" ? "1" : "0", "LC_ALL" => "C" },
          @options.ruby, "-e", code
        )
        enabled = status.success?
        @probes[mode] = {
          "compiled" => compiled,
          "requested" => mode,
          "enabled" => enabled,
          "exit_status" => status.exitstatus,
          "stdout" => stdout,
          "stderr" => stderr,
          "compiled_probe_stdout" => compiled_out,
          "compiled_probe_stderr" => compiled_err
        }
        unless enabled
          raise Error, "YJIT #{mode} probe failed closed: #{stderr.strip}"
        end
      end
    end

    def write_probe_log
      File.binwrite(File.join(@out, "logs", "yjit-probe.txt"), JSON.pretty_generate(@probes) + "\n")
    rescue StandardError
      nil
    end

    def verify_toolchain!
      ruby_version, status = Open3.capture2(@options.ruby, "-e", "print RUBY_VERSION")
      raise Error, "Ruby version probe failed" unless status.success?
      raise Error, "Ruby must be exactly 4.0.6, got #{ruby_version}" unless ruby_version == "4.0.6"

      bundler_out, bundler_err, bundler_status = Open3.capture3(
        { "RUBYOPT" => "" }, @options.ruby, @options.bundle_exe, "_4.0.24_", "--version"
      )
      unless bundler_status.success? && bundler_out.match?(/Bundler version 4\.0\.24/)
        raise Error, "Bundler must be exactly 4.0.24: #{bundler_out} #{bundler_err}"
      end

      crystal_out, crystal_err, crystal_status = Open3.capture3("crystal", "--version")
      unless crystal_status.success? && crystal_out.match?(/Crystal 1\.22\.1/)
        raise Error, "Crystal must be exactly 1.22.1: #{crystal_out} #{crystal_err}"
      end
      raise Error, "final matrix requires Ubuntu 24.04" unless ubuntu_2404?
      raise Error, "celerite binary is missing: #{@options.celerite}" unless File.file?(@options.celerite)
      raise Error, "reference Bundler executable is missing: #{@options.bundle_exe}" unless command_exists?(@options.bundle_exe) || File.file?(@options.bundle_exe)
    end

    def ubuntu_2404?
      return false unless File.file?("/etc/os-release")

      values = File.foreach("/etc/os-release").each_with_object({}) do |line, result|
        key, value = line.strip.split("=", 2)
        result[key] = value.to_s.delete_prefix('"').delete_suffix('"') if key && value
      end
      values["ID"] == "ubuntu" && values["VERSION_ID"] == "24.04"
    end

    def command_exists?(command)
      return true if command.include?(File::SEPARATOR) && File.executable?(command)

      Open3.capture3("sh", "-c", "command -v \"$1\" >/dev/null 2>&1", "sh", command).last.success?
    end

    def prepare_reference!
      reference_dir = File.join(@scratch, "reference")
      FileUtils.mkdir_p(reference_dir)
      source_gemfile = @options.gemfile
      if @options.reference_lock && source_gemfile.nil?
        source_gemfile = File.join(File.dirname(@options.reference_lock), "Gemfile")
      end
      gemfile = File.join(reference_dir, "Gemfile")
      if source_gemfile
        raise Error, "Gemfile is missing: #{source_gemfile}" unless File.file?(source_gemfile)
        FileUtils.cp(source_gemfile, gemfile)
      else
        File.binwrite(gemfile, "source \"https://rubygems.org\"\n\ngem \"rails\", \"8.0.2\"\n")
      end
      lock = File.join(reference_dir, "Gemfile.lock")
      if @options.reference_lock
        raise Error, "reference lock is missing: #{@options.reference_lock}" unless File.file?(@options.reference_lock)
        FileUtils.cp(@options.reference_lock, lock)
      else
        env = reference_environment(reference_dir)
        stdout, stderr, status = Open3.capture3(env, @options.ruby, @options.bundle_exe,
          "_4.0.24_", "lock", "--gemfile", gemfile, chdir: reference_dir)
        File.binwrite(File.join(@out, "logs", "reference-lock.stdout.txt"), stdout)
        File.binwrite(File.join(@out, "logs", "reference-lock.stderr.txt"), stderr)
        append_command("reference lock", [@options.ruby, @options.bundle_exe, "_4.0.24_", "lock", "--gemfile", gemfile])
        raise Error, "reference lock generation failed: #{stderr}" unless status.success?
      end
      raise Error, "reference lock was not created" unless File.file?(lock)

      @reference = {
        "gemfile" => "Gemfile",
        "lock" => "Gemfile.lock",
        "gemfile_sha256" => Digest::SHA256.file(gemfile).hexdigest,
        "lock_sha256" => Digest::SHA256.file(lock).hexdigest,
        "source" => source_gemfile || "generated-rails-8.0.2"
      }
      FileUtils.cp(gemfile, File.join(@out, "Gemfile"))
      FileUtils.cp(lock, File.join(@out, "Gemfile.lock"))
    end

    def reference_environment(dir)
      home = File.join(dir, "home")
      bundle = File.join(dir, "bundle")
      app_config = File.join(dir, "app-config")
      tmp = File.join(dir, "tmp")
      FileUtils.mkdir_p([home, bundle, app_config, tmp])
      {
        "HOME" => home, "USERPROFILE" => home, "BUNDLE_PATH" => bundle,
        "BUNDLE_APP_CONFIG" => app_config, "TMPDIR" => tmp, "TMP" => tmp, "TEMP" => tmp,
        "RUBYOPT" => "", "RUBY_YJIT_ENABLE" => "0", "LC_ALL" => "C",
        "BUNDLE_GEMFILE" => nil, "GEM_HOME" => nil, "GEM_PATH" => nil, "RUBYLIB" => nil
      }
    end

    def base_manifest(status:)
      {
        "format" => "celerite.bench-m8.manifest/1",
        "generated_at_utc" => Time.now.utc.iso8601,
        "run_id" => @options.run_id,
        "run_attempt" => @options.run_attempt,
        "baseline_sha" => @options.baseline_sha,
        "workflow_ref" => @options.workflow_ref,
        "workflow_sha256" => safe_file_sha(File.join(@options.repo_root, ".github", "workflows", "m8-rails-final.yml")),
        "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
        "celerite_binary" => @options.celerite,
        "celerite_binary_sha256" => safe_file_sha(@options.celerite),
        "ruby" => ruby_manifest,
        "bundler" => { "version" => "4.0.24", "executable" => @options.bundle_exe },
        "crystal" => crystal_manifest,
        "platform" => platform_manifest,
        "matrix_mode" => @options.mode,
        "sides" => @options.sides,
        "ruby_modes" => @options.ruby_modes,
        "tiers" => @options.tiers,
        "runs" => @options.runs,
        "warmup" => @options.warmup,
        "jobs" => @options.jobs,
        "timeouts_s" => {
          "cold" => @options.cold_timeout, "hot" => @options.hot_timeout, "noop" => @options.noop_timeout
        },
        "poll_ms" => @options.poll_ms,
        "collector" => {
          "type" => "linux-proc-tree+gnu-time",
          "coverage" => "sampled pid+starttime process tree; short-lived processes may be missed",
          "root_cpu_rss" => "GNU time wait4 rusage",
          "identity" => "pid+/proc stat starttime",
          "timeout" => "new process group; KILL group; reap leader"
        },
        "normalization" => {
          "oracle_spec_exclusion" => @options.oracle_spec,
          "rule" => "exclude exactly this basename on both sides; retain raw and normalized manifests",
          "stdout" => "replace each sample scratch root with <SCRATCH>"
        },
        "reference" => @reference,
        "lock_sha256" => @reference["lock_sha256"],
        "yjit_probes" => @probes,
        "environment_keys" => %w[
          HOME USERPROFILE BUNDLE_PATH BUNDLE_APP_CONFIG TMPDIR TMP TEMP BUNDLE_JOBS
          RUBYOPT RUBY_YJIT_ENABLE LC_ALL CELERITE_BRIDGE_STATS
          CELERITE_PROFILE_BUNDLER_VERSION CELERITE_BRIDGE_SERVER
          CELERITE_REFERENCE_BUNDLER_LIB
        ],
        "unit_times" => @unit_bounds.values.sort_by { |unit| [unit["side"], unit["ruby_mode"], unit["tier"]] },
        "actual_order" => @sequence,
        "status" => status
      }
    end

    def ruby_manifest
      output, status = Open3.capture2(@options.ruby, "-e", "require 'json'; puts JSON.generate({'version' => RUBY_VERSION, 'config' => RbConfig::CONFIG.slice('ruby_version','host','host_cpu','host_os','arch','configure_args')})")
      return { "version" => nil, "error" => output } unless status.success?

      parsed = JSON.parse(output)
      { "version" => parsed["version"], "executable" => @options.ruby, "rbconfig" => parsed["config"] }
    rescue StandardError => error
      { "version" => RUBY_VERSION, "executable" => @options.ruby, "error" => error.message }
    end

    def crystal_manifest
      output, status = Open3.capture2("crystal", "--version")
      status.success? ? { "version_output" => output.strip } : { "error" => output.strip }
    rescue StandardError => error
      { "error" => error.message }
    end

    def platform_manifest
      cpu_model = if File.file?("/proc/cpuinfo")
        File.foreach("/proc/cpuinfo").find { |line| line.start_with?("model name") }.to_s.split(":", 2).last.to_s.strip
      end
      affinity = if File.file?("/proc/self/status")
        File.foreach("/proc/self/status").find { |line| line.start_with?("Cpus_allowed_list") }.to_s.split(":", 2).last.to_s.strip
      end
      nproc, status = Open3.capture2("nproc")
      kernel, kernel_status = Open3.capture2("uname", "-srm")
      {
        "os" => File.file?("/etc/os-release") ? File.read("/etc/os-release") : nil,
        "kernel" => kernel_status.success? ? kernel.strip : nil,
        "nproc" => status.success? ? nproc.strip.to_i : nil,
        "cpu_model" => cpu_model,
        "allowed_cpu_list" => affinity
      }
    rescue StandardError => error
      { "error" => error.message }
    end

    def execute_matrix!
      @options.tiers.each do |tier|
        @options.ruby_modes.each do |mode|
          seeds = {}
          @options.sides.each { |side| seeds[side] = prepare_seed(side, tier, mode) } unless tier == "cold"
          (0..@options.runs).each do |round|
            order = round.even? ? @options.sides : @options.sides.reverse
            order.each do |side|
              kind = round.zero? ? "warmup" : "measured"
              work = tier == "cold" ? prepare_cold_work(side, mode, tier, round) : seeds.fetch(side)
              execute_sample(side: side, mode: mode, tier: tier, round: round, kind: kind, work: work)
            end
          end
        end
      end
    end

    def prepare_seed(side, tier, mode)
      key = [side, tier, mode].join("/")
      @seeds ||= {}
      return @seeds[key] if @seeds[key]

      work = File.join(@scratch, "units", key)
      prepare_work(work)
      raw = File.join(@out, "seeds", key, "install")
      run_unmeasured(command: command_for(side, "install"), mode: mode, work: work, raw: raw, tier: tier, label: "#{side} seed")
      check_raw = File.join(@out, "seeds", key, "check")
      run_unmeasured(command: command_for(side, "hot"), mode: mode, work: work, raw: check_raw, tier: "hot", label: "#{side} seed check")
      @seeds[key] = work
    end

    def prepare_cold_work(side, mode, tier, round)
      work = File.join(@scratch, "cold", side, mode, tier, "r#{round}", format("sample-%04d", @sample_index + 1))
      prepare_work(work)
      work
    end

    def prepare_work(work)
      home = File.join(work, "home")
      bundle = File.join(work, "bundle")
      app_config = File.join(work, "app-config")
      tmp = File.join(work, "tmp")
      project = File.join(work, "project")
      FileUtils.mkdir_p([home, bundle, app_config, tmp, project])
      FileUtils.cp(File.join(@out, "Gemfile"), File.join(project, "Gemfile"))
      FileUtils.cp(File.join(@out, "Gemfile.lock"), File.join(project, "Gemfile.lock"))
      work
    end

    def execute_sample(side:, mode:, tier:, round:, kind:, work:)
      @sample_index += 1
      sample_id = format("sample-%04d", @sample_index)
      relative_raw = if kind == "warmup"
        File.join("warmup", side, mode, tier, "r#{round}", sample_id)
      else
        File.join("raw", side, mode, tier, "r#{round}", sample_id)
      end
      raw = File.join(@out, relative_raw)
      FileUtils.mkdir_p(File.join(raw, "lock"))
      stdout_path = File.join(raw, "stdout.txt")
      stderr_path = File.join(raw, "stderr.txt")
      command = command_for(side, tier)
      env = sample_environment(work, mode)
      started_at = Time.now.utc.iso8601
      append_command(sample_id, command)
      metrics = LinuxCollector.new(poll_ms: @options.poll_ms).run(
        command, env: env, chdir: File.join(work, "project"),
        stdout_path: stdout_path, stderr_path: stderr_path, timeout_s: @options.timeout_for(tier)
      )
      ended_at = Time.now.utc.iso8601
      stdout = File.binread(stdout_path).b
      stderr = File.binread(stderr_path).b
      project = File.join(work, "project")
      copy_lock(project, raw)
      gemspecs = collect_gemspecs(File.join(work, "bundle"))
      write_gemspecs(File.join(raw, "gemspecs.tsv"), gemspecs)
      normalized_stdout = normalize_output(stdout, work)
      rpc = side == "bundle" ? %w[N/A N/A N/A N/A] : parse_rpc(stderr + "\n" + stdout)
      row = {
        "sample_id" => sample_id,
        "kind" => kind,
        "run_id" => @options.run_id,
        "run_attempt" => @options.run_attempt,
        "baseline_sha" => @options.baseline_sha,
        "side" => side,
        "ruby_mode" => mode,
        "tier" => tier,
        "round" => round,
        "started_at_utc" => started_at,
        "ended_at_utc" => ended_at,
        "command" => command,
        "scratch_id" => relative_to(work, @scratch),
        "exit_status" => metrics[:exit_status],
        "signal" => metrics[:signal],
        "timed_out" => metrics[:timed_out],
        "stdout_bytes" => File.size(stdout_path),
        "stderr_bytes" => File.size(stderr_path),
        "stdout_sha256" => Digest::SHA256.file(stdout_path).hexdigest,
        "stderr_sha256" => Digest::SHA256.file(stderr_path).hexdigest,
        "normalized_stdout_sha256" => Digest::SHA256.hexdigest(normalized_stdout),
        "lock_sha256" => lock_sha(File.join(raw, "lock", "Gemfile.lock")),
        "gemspec_count" => gemspecs[:raw_count],
        "gemspec_manifest_sha256" => gemspecs[:raw_sha256],
        "normalized_gemspec_count" => gemspecs[:normalized_count],
        "normalized_gemspec_manifest_sha256" => gemspecs[:normalized_sha256],
        "wall_s" => metrics[:wall_s],
        "root_cpu_user_s" => metrics[:root_cpu_user_s],
        "root_cpu_system_s" => metrics[:root_cpu_system_s],
        "tree_cpu_user_s" => metrics[:tree_cpu_user_s],
        "tree_cpu_system_s" => metrics[:tree_cpu_system_s],
        "root_rss_peak_kb" => metrics[:root_rss_peak_kb],
        "tree_rss_peak_kb" => metrics[:tree_rss_peak_kb],
        "root_io" => metrics[:root_io],
        "tree_io" => metrics[:tree_io],
        "rpc_procs" => rpc[0], "rpc_count" => rpc[1], "rpc_req_bytes" => rpc[2], "rpc_resp_bytes" => rpc[3],
        "yjit_compiled" => @probes.fetch(mode)["compiled"],
        "yjit_requested" => mode,
        "yjit_enabled" => @probes.fetch(mode)["enabled"],
        "collector_complete" => metrics[:collector_complete],
        "missing_metrics" => metrics[:missing_metrics],
        "raw_dir" => relative_raw.tr("\\", "/")
      }
      File.binwrite(File.join(raw, "exit.txt"), "exit_status=#{row['exit_status'].inspect}\nsignal=#{row['signal'].inspect}\ntimed_out=#{row['timed_out']}\n")
      File.binwrite(File.join(raw, "metrics.json"), JSON.pretty_generate(row) + "\n")
      @samples << row
      unit_key = [side, mode, tier]
      @unit_bounds[unit_key] ||= {
        "side" => side, "ruby_mode" => mode, "tier" => tier, "started_at_utc" => started_at
      }
      @unit_bounds[unit_key]["ended_at_utc"] = ended_at
      @sequence << {
        "sequence" => @sequence.length + 1, "sample_id" => sample_id, "side" => side,
        "ruby_mode" => mode, "tier" => tier, "round" => round, "kind" => kind,
        "started_at_utc" => started_at, "ended_at_utc" => ended_at
      }
    end

    def run_unmeasured(command:, mode:, work:, raw:, tier:, label:)
      FileUtils.mkdir_p(raw)
      stdout = File.join(raw, "stdout.txt")
      stderr = File.join(raw, "stderr.txt")
      append_command(label, command)
      metrics = LinuxCollector.new(poll_ms: @options.poll_ms).run(
        command, env: sample_environment(work, mode), chdir: File.join(work, "project"),
        stdout_path: stdout, stderr_path: stderr, timeout_s: @options.timeout_for(tier)
      )
      File.binwrite(File.join(raw, "metrics.json"), JSON.pretty_generate(metrics) + "\n")
      File.binwrite(File.join(raw, "exit.txt"), "exit_status=#{metrics[:exit_status].inspect}\ntimed_out=#{metrics[:timed_out]}\n")
      unless metrics[:exit_status] == 0 && !metrics[:timed_out]
        raise Error, "#{label} failed: exit=#{metrics[:exit_status]} timeout=#{metrics[:timed_out]}"
      end
    end

    def command_for(side, tier)
      arguments = case tier
      when "cold" then ["install"]
      when "hot" then ["check"]
      when "noop" then ["install"]
      else raise Error, "unknown tier: #{tier}"
      end
      if side == "bundle"
        [@options.ruby, @options.bundle_exe, "_4.0.24_", *arguments]
      else
        [@options.celerite, *arguments]
      end
    end

    def sample_environment(work, mode)
      home = File.join(work, "home")
      env = {
        "HOME" => home, "USERPROFILE" => home,
        "BUNDLE_PATH" => File.join(work, "bundle"),
        "BUNDLE_APP_CONFIG" => File.join(work, "app-config"),
        "TMPDIR" => File.join(work, "tmp"), "TMP" => File.join(work, "tmp"), "TEMP" => File.join(work, "tmp"),
        "BUNDLE_JOBS" => @options.jobs.to_s, "MAKEFLAGS" => "-j#{@options.jobs}",
        "RUBYOPT" => "", "RUBY_YJIT_ENABLE" => mode == "on" ? "1" : "0", "LC_ALL" => "C",
        "CELERITE_BRIDGE_STATS" => "1", "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
        "BUNDLE_GEMFILE" => nil, "GEM_HOME" => nil, "GEM_PATH" => nil, "RUBYLIB" => nil,
        "BUNDLE_USER_PLUGIN" => File.join(work, "app-config", "plugins"),
        "BUNDLE_PLUGINS" => "true"
      }
      %w[CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB].each do |key|
        env[key] = ENV[key] if ENV[key] && !ENV[key].empty?
      end
      env
    end

    def copy_lock(project, raw)
      lock_dir = File.join(raw, "lock")
      FileUtils.mkdir_p(lock_dir)
      %w[Gemfile Gemfile.lock].each do |name|
        source = File.join(project, name)
        FileUtils.cp(source, File.join(lock_dir, name)) if File.file?(source)
      end
    end

    def collect_gemspecs(bundle_path)
      paths = Dir.glob(File.join(bundle_path, "**", "specifications", "*.gemspec")).sort
      rows = paths.map do |path|
        relative = relative_to(path, bundle_path).tr("\\", "/")
        {
          "relative_path" => relative,
          "basename" => File.basename(path),
          "sha256" => Digest::SHA256.file(path).hexdigest,
          "bytes" => File.size(path)
        }
      end
      normalized = rows.reject { |row| row["basename"] == @options.oracle_spec }
      {
        "rows" => rows,
        "raw_count" => rows.length,
        "raw_sha256" => manifest_digest(rows),
        "normalized_count" => normalized.length,
        "normalized_sha256" => manifest_digest(normalized)
      }
    end

    def manifest_digest(rows)
      text = rows.map do |row|
        [row["relative_path"], row["basename"], row["sha256"], row["bytes"]].join("\t")
      end.join("\n")
      Digest::SHA256.hexdigest(text)
    end

    def write_gemspecs(path, gemspecs)
      lines = ["relative_path\tbasename\tsha256\tbytes\tnormalized_excluded"]
      gemspecs[:rows].each do |row|
        excluded = row["basename"] == @options.oracle_spec ? "true" : "false"
        lines << [row["relative_path"], row["basename"], row["sha256"], row["bytes"], excluded].join("\t")
      end
      File.binwrite(path, lines.join("\n") + "\n")
    end

    def parse_rpc(text)
      labelled = text.scan(/bridge:\s*procs=(\d+)\s+rpc=(\d+)\s+req_bytes=(\d+)\s+resp_bytes=(\d+)/)
      compact = text.scan(/\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}/)
      candidates = (labelled + compact).uniq
      return candidates.first.map(&:to_i) if candidates.length == 1

      [nil, nil, nil, nil]
    end

    def normalize_output(text, work)
      normalized = text.gsub(work, "<SCRATCH>")
      real = File.realpath(work)
      normalized.gsub(real, "<SCRATCH>")
    rescue Errno::ENOENT
      normalized
    end

    def persist_samples!
      File.binwrite(File.join(@out, "samples.jsonl"), @samples.map { |row| JSON.generate(row) }.join("\n") + "\n")
      lines = [SAMPLE_COLUMNS.join("\t")]
      @samples.each do |row|
        lines << SAMPLE_COLUMNS.map { |column| tsv_value(row, column) }.join("\t")
      end
      File.binwrite(File.join(@out, "samples.tsv"), lines.join("\n") + "\n")
    end

    def tsv_value(row, column)
      value = case column
      when "command" then Shellwords.join(row[column])
      when "missing_metrics" then row[column].join(",")
      when "root_read_bytes" then row.dig("root_io", "read_bytes")
      when "root_write_bytes" then row.dig("root_io", "write_bytes")
      when "root_syscr" then row.dig("root_io", "syscr")
      when "root_syscw" then row.dig("root_io", "syscw")
      when "tree_read_bytes" then row.dig("tree_io", "read_bytes")
      when "tree_write_bytes" then row.dig("tree_io", "write_bytes")
      when "tree_syscr" then row.dig("tree_io", "syscr")
      when "tree_syscw" then row.dig("tree_io", "syscw")
      else row[column]
      end
      value.nil? ? "" : value.to_s.gsub("\t", " ").gsub("\r", "\\r").gsub("\n", "\\n")
    end

    def write_manifest
      File.binwrite(File.join(@out, "manifest.json"), JSON.pretty_generate(@manifest) + "\n")
    end

    def record_failure(error)
      message = "#{error.class}: #{error.message}"
      write_probe_log
      File.binwrite(File.join(@out, "logs", "driver.log"), "#{message}\n#{error.backtrace&.join("\n")}\n")
      @manifest = base_manifest(status: "failed") if @manifest.empty?
      @manifest["status"] = "failed"
      @manifest["error"] = message
      write_manifest
      File.binwrite(File.join(@out, "validator.txt"), "FAIL #{message}\n")
      File.binwrite(File.join(@out, "validator.json"), JSON.pretty_generate({ "ok" => false, "errors" => [message] }) + "\n")
      warn message
    rescue StandardError
      warn message
    end

    def append_command(label, command)
      File.open(File.join(@out, "commands.txt"), "a") { |file| file.puts("#{label}: #{Shellwords.join(command)}") }
    end

    def write_checksums
      paths = Dir.glob(File.join(@out, "**", "*")).select { |path| File.file?(path) && File.basename(path) != "checksums.sha256" }.sort
      lines = paths.map do |path|
        "#{Digest::SHA256.file(path).hexdigest}  #{relative_to(path, @out).tr('\\', '/')}"
      end
      File.binwrite(File.join(@out, "checksums.sha256"), lines.join("\n") + "\n")
    rescue StandardError => error
      warn "checksum generation failed: #{error.message}"
    end

    def lock_sha(path)
      File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
    end

    def safe_file_sha(path)
      File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
    end

    def relative_to(path, root)
      File.expand_path(path).delete_prefix(File.expand_path(root) + File::SEPARATOR)
    end

    def relative_to_out(path)
      relative_to(path, @out)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = BenchM8::Options.parse(ARGV)
    if options.help
      puts options.help_text
      exit 0
    end
    exit(BenchM8::Driver.new(options).run ? 0 : 1)
  rescue BenchM8::Error => error
    warn error.message
    exit 1
  end
end
