#!/usr/bin/env ruby
# frozen_string_literal: true

require "etc"
require "tmpdir"

module BenchM8
  class CollectionError < StandardError; end

  # Linux-only process-tree collector. Root CPU/RSS come from GNU time's wait4
  # rusage for the measured command; tree values are sampled from /proc using
  # pid + stat starttime identities. Missing observations stay nil.
  class LinuxCollector
    Stat = Struct.new(:pid, :starttime, :state, :utime, :stime, :rss_pages, keyword_init: true)
    IO_KEYS = %i[rchar wchar syscr syscw read_bytes write_bytes cancelled_write_bytes].freeze
    REQUIRED_METRICS = %i[
      wall_s root_cpu_user_s root_cpu_system_s tree_cpu_user_s tree_cpu_system_s
      root_rss_peak_kb tree_rss_peak_kb
    ].freeze

    attr_reader :last_result

    def initialize(poll_ms: 20, time_exe: "/usr/bin/time")
      @poll_ms = poll_ms
      @time_exe = time_exe
      @clock_ticks = Etc.sysconf(Etc::SC_CLK_TCK)
      @page_size = Etc.sysconf(Etc::SC_PAGESIZE)
      raise CollectionError, "Linux collector requires /proc" unless File.directory?("/proc")
      raise CollectionError, "GNU time is required at #{@time_exe}" unless File.executable?(@time_exe)
    end

    def self.self_test(poll_ms: 20, ruby: RbConfig.ruby)
      collector = new(poll_ms: poll_ms)
      Dir.mktmpdir("celerite-m8-collector-selftest") do |dir|
        io_path = File.join(dir, "child-io.bin")
        child = <<~'RUBY'
          path = ARGV.fetch(0)
          data = "x" * (4 * 1024 * 1024)
          2_000.times { data << "y" }
          File.binwrite(path, data)
          2.times { raise "short read" unless File.binread(path).bytesize == data.bytesize }
          sum = 0
          300_000.times { |i| sum += i % 97 }
          raise "impossible" unless sum.positive?
        RUBY
        parent = <<~RUBY
          child = #{child.dump}
          pid = Process.spawn(#{ruby.dump}, "-e", child, ARGV.fetch(0))
          sleep 0.05
          Process.wait(pid)
        RUBY
        stdout = File.join(dir, "stdout.txt")
        stderr = File.join(dir, "stderr.txt")
        result = collector.run(
          [ruby.dump, "-e", parent, io_path],
          env: { "RUBYOPT" => "", "LC_ALL" => "C" },
          chdir: dir,
          stdout_path: stdout,
          stderr_path: stderr,
          timeout_s: 15
        )
        errors = []
        errors << "self-test command failed" unless result[:exit_status] == 0 && !result[:timed_out]
        errors << "self-test collector incomplete: #{result[:missing_metrics].join(', ')}" unless result[:collector_complete]
        root_cpu = result[:root_cpu_user_s].to_f + result[:root_cpu_system_s].to_f
        tree_cpu = result[:tree_cpu_user_s].to_f + result[:tree_cpu_system_s].to_f
        errors << "tree CPU #{tree_cpu} did not exceed root CPU #{root_cpu}" unless tree_cpu > root_cpu
        errors << "tree RSS did not exceed root RSS" unless result[:tree_rss_peak_kb].to_i > result[:root_rss_peak_kb].to_i
        %i[rchar wchar syscr syscw].each do |key|
          root_io = result.dig(:root_io, key)
          tree_io = result.dig(:tree_io, key)
          errors << "missing #{key} IO" if root_io.nil? || tree_io.nil?
          errors << "tree #{key} IO did not exceed root" if root_io && tree_io && tree_io <= root_io
        end
        %i[read_bytes write_bytes].each do |key|
          errors << "missing #{key} IO" if result.dig(:root_io, key).nil? || result.dig(:tree_io, key).nil?
        end
        raise CollectionError, errors.join("; ") unless errors.empty?

        result.slice(:wall_s, :root_cpu_user_s, :root_cpu_system_s, :tree_cpu_user_s,
          :tree_cpu_system_s, :root_rss_peak_kb, :tree_rss_peak_kb, :root_io, :tree_io,
          :collector_complete, :missing_metrics, :exit_status, :timed_out)
      end
    end

    def run(command, env:, chdir:, stdout_path:, stderr_path:, timeout_s:)
      time_path = "#{stdout_path}.time"
      format = "%e %U %S %M %x"
      wrapped = [@time_exe, "-f", format, "-o", time_path, *command]
      sampler = TreeSampler.new(clock_ticks: @clock_ticks, page_size: @page_size)
      stdout = File.open(stdout_path, "wb")
      stderr = File.open(stderr_path, "wb")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pid = nil
      reaped = false
      timed_out = false
      identity_changed = false
      begin
        pid = Process.spawn(env, *wrapped, chdir: chdir, out: stdout, err: stderr, pgroup: true)
        root_pid = nil
        loop do
          root_pid ||= discover_root(pid)
          if root_pid
            root_stat = read_stat(root_pid)
            if root_stat
              identity_changed = true if sampler.root_identity && sampler.root_identity != [root_pid, root_stat.starttime]
              sampler.root_identity = [root_pid, root_stat.starttime]
              sampler.sample(root_stat)
            end
          end

          if Process.waitpid(pid, Process::WNOHANG)
            reaped = true
            break
          end
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= timeout_s
            timed_out = true
            begin
              Process.kill("KILL", -pid)
            rescue Errno::ESRCH
              nil
            end
            begin
              Process.waitpid(pid)
              reaped = true
            rescue Errno::ECHILD
              nil
            end
            break
          end
          sleep(@poll_ms / 1000.0)
        end
      ensure
        stdout.close
        stderr.close
        if pid && !reaped
          begin
            Process.kill("KILL", -pid)
          rescue Errno::ESRCH
            nil
          end
          begin
            Process.waitpid(pid)
          rescue Errno::ECHILD
            nil
          end
        end
      end

      ended = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      root_values = parse_time_file(time_path)
      status = $?
      result = {
        wall_s: ended - started,
        root_cpu_user_s: root_values[:user],
        root_cpu_system_s: root_values[:system],
        root_rss_peak_kb: root_values[:rss_kb],
        tree_cpu_user_s: sampler.tree_cpu_user,
        tree_cpu_system_s: sampler.tree_cpu_system,
        tree_rss_peak_kb: sampler.tree_rss_peak_kb,
        root_io: sampler.root_io,
        tree_io: sampler.tree_io,
        exit_status: status&.exitstatus,
        signal: status&.termsig,
        timed_out: timed_out,
        identity_changed: identity_changed,
        root_pid: sampler.root_identity&.first,
        root_starttime: sampler.root_identity&.last,
        observed_process_count: sampler.observed_count,
        poll_ms: @poll_ms,
        collector: "linux-proc-tree+gnu-time",
        coverage: "sampled descendants; short-lived processes may be missed"
      }
      result[:missing_metrics] = missing_metrics(result)
      result[:missing_metrics] << "process_tree" unless sampler.complete?
      result[:collector_complete] = result[:missing_metrics].empty? && !timed_out && !identity_changed
      @last_result = result
      result
    end

    private

    def missing_metrics(result)
      missing = REQUIRED_METRICS.select { |key| result[key].nil? }
      missing << "root_io" unless complete_io?(result[:root_io])
      missing << "tree_io" unless complete_io?(result[:tree_io])
      missing
    end

    def complete_io?(io)
      io.is_a?(Hash) && IO_KEYS.all? { |key| io[key].is_a?(Numeric) }
    end

    def parse_time_file(path)
      return {} unless File.file?(path)

      values = File.read(path).strip.split
      return {} unless values.length == 5
      return {} unless values.all? { |value| value.match?(/\A\d+(?:\.\d+)?\z/) }

      {
        wall: values[0].to_f,
        user: values[1].to_f,
        system: values[2].to_f,
        rss_kb: values[3].to_i,
        time_exit: values[4]&.to_i
      }
    rescue StandardError
      {}
    end

    def discover_root(time_pid)
      children = []
      Dir.glob("/proc/#{time_pid}/task/*/children").each do |path|
        children.concat(File.read(path).split.map(&:to_i))
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end
      children.find { |child| File.directory?("/proc/#{child}") }
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def read_stat(pid)
      self.class.parse_stat(pid, File.read("/proc/#{pid}/stat"))
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def self.parse_stat(pid, text)
      close_paren = text.rindex(")")
      return nil unless close_paren

      fields = text[(close_paren + 2)..].split
      required = [11, 12, 19, 21]
      return nil unless required.all? { |index| fields[index]&.match?(/\A\d+\z/) }

      Stat.new(
        pid: pid,
        starttime: fields[19].to_i,
        state: fields[0],
        utime: fields[11].to_i,
        stime: fields[12].to_i,
        rss_pages: fields[21].to_i
      )
    end

    class TreeSampler
      attr_accessor :root_identity
      attr_reader :observed_count

      def initialize(clock_ticks:, page_size:)
        @clock_ticks = clock_ticks
        @page_size = page_size
        @cpu_user = Hash.new(0)
        @cpu_system = Hash.new(0)
        @io = {}
        @seen_pids = {}
        @io_incomplete = false
        @tree_incomplete = false
        @rss_peak_kb = 0
        @root_io = nil
        @observed_count = 0
      end

      def sample(root_stat)
        queue = [root_stat]
        visited = {}
        rss_kb = 0
        while (stat = queue.shift)
          identity = [stat.pid, stat.starttime]
          next if visited[identity]

          visited[identity] = true
          @seen_pids[stat.pid] = true
          @observed_count += 1
          @cpu_user[identity] = [@cpu_user[identity], stat.utime].max
          @cpu_system[identity] = [@cpu_system[identity], stat.stime].max
          io = read_io(stat.pid)
          if io
            @io[identity] = merge_io(@io[identity], io)
            @root_io = merge_io(@root_io, io) if root_identity == identity
          elsif !@io.key?(identity)
            @io_incomplete = true
          end
          rss_kb += stat.rss_pages * @page_size / 1024
          queue.concat(child_stats(stat.pid))
        end
        @rss_peak_kb = [@rss_peak_kb, rss_kb].max
      end

      def tree_cpu_user
        return nil if @tree_incomplete || @cpu_user.empty?

        @cpu_user.values.sum.to_f / @clock_ticks
      end

      def tree_cpu_system
        return nil if @tree_incomplete || @cpu_system.empty?

        @cpu_system.values.sum.to_f / @clock_ticks
      end

      def tree_rss_peak_kb
        return nil if @tree_incomplete
        @rss_peak_kb.positive? ? @rss_peak_kb : nil
      end

      def complete?
        !@tree_incomplete && !@io_incomplete && !tree_cpu_user.nil? &&
          !tree_cpu_system.nil? && !tree_rss_peak_kb.nil? && !tree_io.nil?
      end

      def root_io
        @root_io
      end

      def tree_io
        return nil if @io_incomplete || @io.empty?

        IO_KEYS.each_with_object({}) do |key, result|
          values = @io.values.filter_map { |io| io[key] }
          result[key] = values.sum unless values.empty?
        end
      end

      private

      def child_stats(pid)
        children = []
        Dir.glob("/proc/#{pid}/task/*/children").each do |path|
          children.concat(File.read(path).split.map(&:to_i))
        rescue Errno::ENOENT, Errno::EACCES
          @tree_incomplete = true unless @seen_pids.key?(pid)
        end
        children.filter_map do |child|
          stat = read_stat(child)
          if stat
            @seen_pids[child] = true
            stat
          else
            @tree_incomplete = true unless @seen_pids.key?(child)
            nil
          end
        end
      rescue Errno::ENOENT, Errno::EACCES
        @tree_incomplete = true unless @seen_pids.key?(pid)
        []
      end

      def read_stat(pid)
        LinuxCollector.parse_stat(pid, File.read("/proc/#{pid}/stat"))
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end

      def read_io(pid)
        values = {}
        File.foreach("/proc/#{pid}/io") do |line|
          key, value = line.split(":", 2)
          next unless key && value

          raw = value.strip
          return nil unless raw.match?(/\A\d+\z/)

          values[key.to_sym] = raw.to_i
        end
        values if IO_KEYS.all? { |key| values.key?(key) }
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end

      def merge_io(left, right)
        return right unless left
        return left unless right

        IO_KEYS.each_with_object({}) { |key, result| result[key] = [left[key], right[key]].compact.max }
      end
    end
  end
end
