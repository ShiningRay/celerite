#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module BenchM8
  class ValidationError < StandardError; end

  class Validator
    IO_KEYS = %i[rchar wchar syscr syscw read_bytes write_bytes cancelled_write_bytes].freeze
    NUMERIC_METRICS = %i[
      wall_s root_cpu_user_s root_cpu_system_s tree_cpu_user_s tree_cpu_system_s
      root_rss_peak_kb tree_rss_peak_kb
    ].freeze
    RAW_FILES = %w[stdout.txt stderr.txt exit.txt metrics.json gemspecs.tsv lock/Gemfile lock/Gemfile.lock].freeze

    attr_reader :errors, :rows, :manifest

    def initialize(out)
      @out = File.expand_path(out)
      @errors = []
      @rows = []
      @manifest = {}
    end

    def validate(write: true)
      @errors = []
      load_inputs
      validate_identity
      validate_matrix
      validate_order
      validate_rows
      validate_pairs
      if write
        FileUtils.mkdir_p(@out)
        File.binwrite(File.join(@out, "validator.txt"), validator_text)
        File.binwrite(File.join(@out, "validator.json"), JSON.pretty_generate(validator_json) + "\n")
        remove_stale_summary unless @errors.empty?
      end
      @errors.empty?
    end

    def validated_rows
      @rows.select { |row| row["kind"] == "measured" }
    end

    def generate_summary
      raise ValidationError, "cannot summarize invalid rows" unless @errors.empty?

      units = {}
      validated_rows.group_by { |row| [row["side"], row["ruby_mode"], row["tier"]] }.each do |key, rows|
        side, mode, tier = key
        stats = metric_stats(rows)
        units[[side, mode, tier].join("/")] = {
          "side" => side,
          "ruby_mode" => mode,
          "tier" => tier,
          "n" => rows.length,
          "metrics" => stats
        }
      end
      summary = {
        "format" => "celerite.bench-m8.summary/1",
        "generated_at_utc" => Time.now.utc.iso8601,
        "run_id" => @manifest["run_id"],
        "run_attempt" => @manifest["run_attempt"],
        "baseline_sha" => @manifest["baseline_sha"],
        "matrix_mode" => @manifest["matrix_mode"],
        "validated_sample_count" => validated_rows.length,
        "units" => units
      }
      File.binwrite(File.join(@out, "summary.json"), JSON.pretty_generate(summary) + "\n")
      File.binwrite(File.join(@out, "summary.tsv"), summary_tsv(units))
      summary
    end

    def validator_text
      if @errors.empty?
        "PASS run_id=#{@manifest['run_id']} attempt=#{@manifest['run_attempt']} baseline_sha=#{@manifest['baseline_sha']} samples=#{@rows.length}\n"
      else
        "FAIL run_id=#{@manifest['run_id']} attempt=#{@manifest['run_attempt']} baseline_sha=#{@manifest['baseline_sha']}\n" \
          "#{@errors.map { |error| "- #{error}\n" }.join}"
      end
    end

    def validator_json
      {
        "ok" => @errors.empty?,
        "run_id" => @manifest["run_id"],
        "run_attempt" => @manifest["run_attempt"],
        "baseline_sha" => @manifest["baseline_sha"],
        "sample_count" => @rows.length,
        "errors" => @errors
      }
    end

    private

    def load_inputs
      @manifest = JSON.parse(File.read(File.join(@out, "manifest.json")))
      @rows = File.readlines(File.join(@out, "samples.jsonl"), chomp: true).map.with_index do |line, index|
        begin
          JSON.parse(line)
        rescue JSON::ParserError => error
          @errors << "samples.jsonl line #{index + 1}: #{error.message}"
          {}
        end
      end
    rescue Errno::ENOENT => error
      @errors << "missing input: #{error.message}"
    end

    def validate_identity
      required = %w[run_id run_attempt baseline_sha matrix_mode sides ruby_modes tiers runs warmup jobs lock_sha256]
      required.each do |key|
        @errors << "manifest missing #{key}" if @manifest[key].nil?
      end
      return if @errors.any?

      @rows.each do |row|
        next if row.empty?

        @errors << "#{row['sample_id']}: run_id mismatch" unless row["run_id"].to_s == @manifest["run_id"].to_s
        @errors << "#{row['sample_id']}: run_attempt mismatch" unless row["run_attempt"].to_s == @manifest["run_attempt"].to_s
        @errors << "#{row['sample_id']}: baseline_sha mismatch" unless row["baseline_sha"] == @manifest["baseline_sha"]
      end
      if @manifest["matrix_mode"] == "full"
        @errors << "full matrix requires both Ruby modes" unless @manifest["ruby_modes"] == %w[off on]
        @errors << "full matrix requires cold/hot/noop" unless @manifest["tiers"] == %w[cold hot noop]
        @errors << "full matrix requires runs=5" unless @manifest["runs"] == 5
        @errors << "full matrix requires warmup=1" unless @manifest["warmup"] == 1
        @errors << "full matrix requires jobs=4" unless @manifest["jobs"] == 4
      elsif @manifest["matrix_mode"] == "smoke"
        @errors << "smoke matrix requires hot/noop only" unless @manifest["tiers"] == %w[hot noop]
        @errors << "smoke matrix requires both Ruby modes" unless @manifest["ruby_modes"] == %w[off on]
        @errors << "smoke matrix requires runs=1" unless @manifest["runs"] == 1
        @errors << "smoke matrix requires warmup=1" unless @manifest["warmup"] == 1
        @errors << "smoke matrix requires jobs=4" unless @manifest["jobs"] == 4
      else
        @errors << "unknown matrix_mode: #{@manifest['matrix_mode']}"
      end
      @errors << "matrix requires both sides" unless @manifest["sides"] == %w[celerite bundle]
    end

    def validate_matrix
      return if @errors.any?

      expected_units = @manifest["sides"].length * @manifest["ruby_modes"].length * @manifest["tiers"].length
      expected_measured = expected_units * @manifest["runs"]
      expected_warmup = expected_units * @manifest["warmup"]
      measured = @rows.count { |row| row["kind"] == "measured" }
      warmup = @rows.count { |row| row["kind"] == "warmup" }
      @errors << "measured row count #{measured}, expected #{expected_measured}" unless measured == expected_measured
      @errors << "warmup row count #{warmup}, expected #{expected_warmup}" unless warmup == expected_warmup

      ids = @rows.map { |row| row["sample_id"] }
      duplicates = ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
      @errors << "duplicate sample_id: #{duplicates.join(', ')}" unless duplicates.empty?

      @manifest["tiers"].each do |tier|
        @manifest["ruby_modes"].each do |mode|
          (0..@manifest["runs"]).each do |round|
            kind = round.zero? ? "warmup" : "measured"
            @manifest["sides"].each do |side|
              count = @rows.count do |row|
                row["side"] == side && row["ruby_mode"] == mode && row["tier"] == tier &&
                  row["round"] == round && row["kind"] == kind
              end
              @errors << "missing/duplicate unit #{side}/#{mode}/#{tier}/#{kind}/#{round}" unless count == 1
            end
          end
        end
      end
    end

    def validate_order
      return if @errors.any?

      order = @manifest["actual_order"]
      unless order.is_a?(Array) && order.length == @rows.length
        @errors << "actual_order length mismatch"
        return
      end
      order.each_with_index do |entry, index|
        row = @rows[index]
        expected = index + 1
        @errors << "actual_order sequence mismatch at #{index}" unless entry["sequence"] == expected
        @errors << "actual_order sample mismatch at #{index}" unless entry["sample_id"] == row["sample_id"]
        @errors << "actual_order side mismatch at #{index}" unless entry["side"] == row["side"]
        expected_sides = row["round"].even? ? @manifest["sides"] : @manifest["sides"].reverse
        group = order.select { |item| [item["ruby_mode"], item["tier"], item["round"], item["kind"]] == [row["ruby_mode"], row["tier"], row["round"], row["kind"]] }
        @errors << "interleaving mismatch at #{row['sample_id']}" unless group.map { |item| item["side"] } == expected_sides
      end
    end

    def validate_rows
      @rows.each do |row|
        next if row.empty?

        id = row["sample_id"] || "<unknown>"
        @errors << "#{id}: unexpected tier" unless @manifest.fetch("tiers", []).include?(row["tier"])
        @errors << "#{id}: unexpected ruby_mode" unless @manifest.fetch("ruby_modes", []).include?(row["ruby_mode"])
        @errors << "#{id}: unexpected side" unless @manifest.fetch("sides", []).include?(row["side"])
        @errors << "#{id}: timeout" if row["timed_out"]
        @errors << "#{id}: unexpected exit #{row['exit_status'].inspect}" unless row["exit_status"] == 0
        @errors << "#{id}: unexpected signal #{row['signal'].inspect}" unless row["signal"].nil?
        @errors << "#{id}: collector incomplete" unless row["collector_complete"] == true
        @errors << "#{id}: missing metrics recorded" unless row["missing_metrics"] == []
        @errors << "#{id}: lock SHA mismatch" unless row["lock_sha256"] == @manifest["lock_sha256"]

        NUMERIC_METRICS.each do |key|
          value = row[key.to_s]
          @errors << "#{id}: missing/non-numeric #{key}" unless value.is_a?(Numeric) && value >= 0
        end
        %w[root_io tree_io].each do |scope|
          io = row[scope]
          unless io.is_a?(Hash)
            @errors << "#{id}: missing #{scope}"
            next
          end
          IO_KEYS.each do |key|
            value = io[key.to_s]
            @errors << "#{id}: missing/non-numeric #{scope}.#{key}" unless value.is_a?(Numeric) && value >= 0
          end
        end

        mode = row["ruby_mode"]
        @errors << "#{id}: requested YJIT mismatch" unless row["yjit_requested"] == mode
        @errors << "#{id}: off mode enabled YJIT" if mode == "off" && row["yjit_enabled"] != false
        if mode == "on"
          @errors << "#{id}: on mode did not compile YJIT" unless row["yjit_compiled"] == true
          @errors << "#{id}: on mode did not enable YJIT" unless row["yjit_enabled"] == true
        end

        if row["side"] == "bundle"
          %w[rpc_procs rpc_count rpc_req_bytes rpc_resp_bytes].each do |key|
            @errors << "#{id}: bundle #{key} must be N/A" unless row[key] == "N/A"
          end
        else
          %w[rpc_procs rpc_count rpc_req_bytes rpc_resp_bytes].each do |key|
            value = row[key]
            @errors << "#{id}: celerite #{key} must be numeric" unless value.is_a?(Numeric) && value >= 0
          end
        end

        %w[gemspec_count normalized_gemspec_count].each do |key|
          @errors << "#{id}: invalid #{key}" unless row[key].is_a?(Integer) && row[key] >= 0
        end
        %w[gemspec_manifest_sha256 normalized_gemspec_manifest_sha256 stdout_sha256 stderr_sha256 normalized_stdout_sha256].each do |key|
          @errors << "#{id}: missing #{key}" if row[key].to_s.empty?
        end
        validate_raw_files(row, id)
      end
    end

    def validate_raw_files(row, id)
      raw = expanded_raw_dir(row["raw_dir"])
      unless raw && raw.start_with?(@out + File::SEPARATOR)
        @errors << "#{id}: raw_dir escapes artifact"
        return
      end
      RAW_FILES.each do |relative|
        @errors << "#{id}: missing raw file #{relative}" unless File.file?(File.join(raw, relative))
      end
      stdout_path = File.join(raw, "stdout.txt")
      stderr_path = File.join(raw, "stderr.txt")
      lock_path = File.join(raw, "lock", "Gemfile.lock")
      if File.file?(stdout_path)
        bytes = File.size(stdout_path)
        @errors << "#{id}: stdout byte count mismatch" unless row["stdout_bytes"] == bytes
        @errors << "#{id}: stdout SHA mismatch" unless row["stdout_sha256"] == Digest::SHA256.file(stdout_path).hexdigest
      end
      if File.file?(stderr_path)
        bytes = File.size(stderr_path)
        @errors << "#{id}: stderr byte count mismatch" unless row["stderr_bytes"] == bytes
        @errors << "#{id}: stderr SHA mismatch" unless row["stderr_sha256"] == Digest::SHA256.file(stderr_path).hexdigest
      end
      if File.file?(lock_path)
        @errors << "#{id}: copied lock SHA mismatch" unless row["lock_sha256"] == Digest::SHA256.file(lock_path).hexdigest
      end
      gemfile_path = File.join(raw, "lock", "Gemfile")
      if File.file?(gemfile_path)
        expected = @manifest.dig("reference", "gemfile_sha256")
        @errors << "#{id}: copied Gemfile SHA mismatch" unless expected == Digest::SHA256.file(gemfile_path).hexdigest
      end
      metrics_path = File.join(raw, "metrics.json")
      if File.file?(metrics_path)
        begin
          @errors << "#{id}: metrics.json row mismatch" unless JSON.parse(File.read(metrics_path)) == row
        rescue JSON::ParserError => error
          @errors << "#{id}: invalid metrics.json: #{error.message}"
        end
      end
      validate_gemspecs(row, id, raw)
    end

    def validate_gemspecs(row, id, raw)
      path = File.join(raw, "gemspecs.tsv")
      return unless File.file?(path)

      lines = File.readlines(path, chomp: true)
      return if lines.empty? || lines.first != "relative_path\tbasename\tsha256\tbytes\tnormalized_excluded"

      rows = lines.drop(1).map do |line|
        relative, basename, sha256, bytes, excluded = line.split("\t", 5)
        { "relative_path" => relative, "basename" => basename, "sha256" => sha256,
          "bytes" => bytes&.to_i, "normalized_excluded" => excluded }
      end
      oracle = @manifest.dig("normalization", "oracle_spec_exclusion")
      rows.each do |entry|
        expected = entry["basename"] == oracle ? "true" : "false"
        @errors << "#{id}: gemspec exclusion marker mismatch" unless entry["normalized_excluded"] == expected
      end
      raw_rows = rows.map { |entry| entry.slice("relative_path", "basename", "sha256", "bytes") }
      normalized_rows = rows.reject { |entry| entry["basename"] == oracle }
        .map { |entry| entry.slice("relative_path", "basename", "sha256", "bytes") }
      @errors << "#{id}: gemspec count mismatch" unless row["gemspec_count"] == raw_rows.length
      @errors << "#{id}: normalized gemspec count mismatch" unless row["normalized_gemspec_count"] == normalized_rows.length
      @errors << "#{id}: gemspec manifest SHA mismatch" unless row["gemspec_manifest_sha256"] == manifest_digest(raw_rows)
      @errors << "#{id}: normalized gemspec manifest SHA mismatch" unless row["normalized_gemspec_manifest_sha256"] == manifest_digest(normalized_rows)
    rescue StandardError => error
      @errors << "#{id}: invalid gemspecs.tsv: #{error.message}"
    end

    def manifest_digest(rows)
      text = rows.map do |row|
        [row["relative_path"], row["basename"], row["sha256"], row["bytes"]].join("\t")
      end.join("\n")
      Digest::SHA256.hexdigest(text)
    end

    def validate_pairs
      return if @errors.any?

      grouped = @rows.group_by { |row| [row["tier"], row["ruby_mode"], row["round"], row["kind"]] }
      grouped.each do |key, rows|
        tier, mode, round, kind = key
        celerite = rows.find { |row| row["side"] == "celerite" }
        bundle = rows.find { |row| row["side"] == "bundle" }
        next unless celerite && bundle

        label = "#{tier}/#{mode}/#{kind}/#{round}"
        @errors << "#{label}: lock mismatch" unless celerite["lock_sha256"] == bundle["lock_sha256"]
        @errors << "#{label}: normalized stdout mismatch" unless celerite["normalized_stdout_sha256"] == bundle["normalized_stdout_sha256"]
        @errors << "#{label}: normalized gemspec count mismatch" unless celerite["normalized_gemspec_count"] == bundle["normalized_gemspec_count"]
        @errors << "#{label}: normalized gemspec manifest mismatch" unless celerite["normalized_gemspec_manifest_sha256"] == bundle["normalized_gemspec_manifest_sha256"]
      end
    end

    def expanded_raw_dir(path)
      return nil if path.to_s.empty?

      File.expand_path(path, @out)
    end

    def remove_stale_summary
      %w[summary.json summary.tsv].each do |name|
        path = File.expand_path(name, @out)
        FileUtils.rm_f(path) if File.dirname(path) == @out
      end
    end

    def metric_stats(rows)
      values = lambda do |getter|
        numbers = rows.filter_map { |row| getter.call(row) }.select { |value| value.is_a?(Numeric) }
        return nil if numbers.empty?

        {
          "median" => median(numbers),
          "mean" => numbers.sum.to_f / numbers.length,
          "min" => numbers.min,
          "max" => numbers.max
        }
      end
      stats = {}
      NUMERIC_METRICS.each do |key|
        stats[key.to_s] = values.call(->(row) { row[key.to_s] })
      end
      %w[read_bytes write_bytes syscr syscw].each do |key|
        stats["tree_io_#{key}"] = values.call(->(row) { row.dig("tree_io", key) })
        stats["root_io_#{key}"] = values.call(->(row) { row.dig("root_io", key) })
      end
      %w[rpc_procs rpc_count rpc_req_bytes rpc_resp_bytes].each do |key|
        stats[key] = if rows.first["side"] == "bundle"
          "N/A"
        else
          values.call(->(row) { row[key] })
        end
      end
      stats
    end

    def median(values)
      sorted = values.sort
      middle = sorted.length / 2
      sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end

    def summary_tsv(units)
      columns = %w[
        side ruby_mode tier n wall_s_median tree_cpu_median_s root_cpu_median_s
        tree_rss_peak_median_kb root_rss_peak_median_kb tree_read_bytes_median
        tree_write_bytes_median tree_syscr_median tree_syscw_median rpc_procs_median
        rpc_count_median rpc_req_bytes_median rpc_resp_bytes_median
      ]
      lines = [columns.join("\t")]
      units.values.sort_by { |unit| [unit["side"], unit["ruby_mode"], unit["tier"]] }.each do |unit|
        metrics = unit["metrics"]
        values = {
          "side" => unit["side"], "ruby_mode" => unit["ruby_mode"], "tier" => unit["tier"], "n" => unit["n"],
          "wall_s_median" => metrics.dig("wall_s", "median"),
          "tree_cpu_median_s" => combined_cpu(metrics, "tree"),
          "root_cpu_median_s" => combined_cpu(metrics, "root"),
          "tree_rss_peak_median_kb" => metrics.dig("tree_rss_peak_kb", "median"),
          "root_rss_peak_median_kb" => metrics.dig("root_rss_peak_kb", "median"),
          "tree_read_bytes_median" => metrics.dig("tree_io_read_bytes", "median"),
          "tree_write_bytes_median" => metrics.dig("tree_io_write_bytes", "median"),
          "tree_syscr_median" => metrics.dig("tree_io_syscr", "median"),
          "tree_syscw_median" => metrics.dig("tree_io_syscw", "median"),
          "rpc_procs_median" => rpc_median(metrics, "rpc_procs"),
          "rpc_count_median" => rpc_median(metrics, "rpc_count"),
          "rpc_req_bytes_median" => rpc_median(metrics, "rpc_req_bytes"),
          "rpc_resp_bytes_median" => rpc_median(metrics, "rpc_resp_bytes")
        }
        lines << columns.map { |column| values[column].nil? ? "" : values[column] }.join("\t")
      end
      lines.join("\n") + "\n"
    end

    def combined_cpu(metrics, prefix)
      user = metrics.dig("#{prefix}_cpu_user_s", "median")
      system = metrics.dig("#{prefix}_cpu_system_s", "median")
      user && system ? user + system : nil
    end

    def rpc_median(metrics, key)
      value = metrics[key]
      value == "N/A" ? value : value&.dig("median")
    end
  end
end
