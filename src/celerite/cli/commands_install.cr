require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../definition"
require "../resolution"
require "../installer"
require "../downloader"
require "digest/sha256"

module Celerite
  # M3 installation commands (pinned against the 4.0.24 oracle): install,
  # cache/package, clean, exec, binstubs. Observed output contracts:
  # - install prints progress on stdout, "Bundle complete! ..." summary, and
  #   "Bundled gems are installed into `<path>`"
  # - idempotent rerun (locked, everything installed) prints only the summary
  # - cache runs install first, then "Updating files in vendor/cache" +
  #   "  * <gem>.gem" lines
  # - exec exports RUBYOPT=-r<bundler_lib>/bundler/setup, RUBYLIB=<bundler_lib>,
  #   BUNDLE_GEMFILE=<abs>, and prepends the bundle bin dir to PATH
  module Commands
    def self.ruby_abi(bridge : Bridge::Client) : String
      env = bridge.ruby_environment
      parts = env.ruby_version.split(".")
      "#{parts[0]}.#{parts[1]}.0"
    end

    def self.install_path(config : Config) : String
      configured = config["path"].to_s
      base = configured.empty? ? File.join(Config.user_home || ".", ".bundle") : configured
      File.expand_path(base)
    end

    def self.downloader_cache_root : String
      home = Config.user_home || "."
      File.join(home, ".bundle", "cache")
    end

    def self.native_suffix(bridge : Bridge::Client, gem_file : String?) : String
      return "" if gem_file.nil? || !File.file?(gem_file)
      info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(gem_file).to_json)
      info.extensions.empty? ? "" : " with native extensions"
    rescue
      ""
    end

    # ------------------------------------------------------------------
    # install
    # ------------------------------------------------------------------
    def self.install(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      config = definition.config
      if config.frozen? && !definition.lockfile_exists?
        raise ProductionError.new("Frozen mode is set, but there's no lockfile")
      end

      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, false, bridge)
        resolution.progress = stdout

        install_path = install_path(config)
        abi = ruby_abi(bridge)
        downloader = Downloader.new(resolution.primary_remote, downloader_cache_root)
        installer = Installer.new(install_path, abi, bridge, downloader, stdout)

        reuse = resolution_can_reuse?(resolution)
        specs = resolution.resolve!(reuse)

        pending = specs.sort_by(&.full_name).reject do |spec|
          installer.installed?(spec.name, spec.version.to_s, spec.platform)
        end
        # Reference output order: all "Fetching" lines (downloads) first,
        # then all "Installing" lines.
        cached_paths = {} of String => String
        pending.each do |spec|
          stdout.puts "Fetching #{spec.name} #{spec.version}"
          cached_paths[spec.full_name] = downloader.fetch(
            spec.name, spec.version.to_s, spec.platform, spec.checksum
          )
        end
        pending.each do |spec|
          cached = cached_paths[spec.full_name]?
          stdout.puts "Installing #{spec.name} #{spec.version}#{native_suffix(bridge, cached)}"
          installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum)
          # The reference records the installed package's sha256 in CHECKSUMS
          # even for file:// sources.
          if cached && File.file?(cached)
            sha = Digest::SHA256.hexdigest(File.read(cached))
            resolution.install_checksums["#{spec.name}-#{spec.version}"] = "sha256=#{sha}"
          end
        end

        deps_count = resolution.evaluation.dependencies.count { |d| !d.gemspec_dev_dep }
        gems_count = specs.size
        # 2.7.x counts the running Bundler in "gems now installed"
        gems_count += 1 if resolution.bridge_bundler_version.starts_with?("2.")
        stdout.puts "Bundle complete! #{deps_count} Gemfile dependencies, #{gems_count} gems now installed."
        stdout.puts "Bundled gems are installed into `#{install_path.gsub(/\\\\/, "/").gsub(/\\/, "/")}`"

        unless rest.includes?("--no-lock") || config.frozen?
          text = resolution.generated_lockfile.to_lock
          existing = File.file?(definition.lockfile_path) ? File.read(definition.lockfile_path) : nil
          File.write(definition.lockfile_path, text) if existing != text
        end
        0
      ensure
        bridge.close
      end
    end

    # The reference install reuses a valid lockfile without re-resolving
    # (no "Fetching source index"/"Resolving dependencies..." on reruns).
    private def self.resolution_can_reuse?(resolution : Resolution) : Bool
      resolution.reuse_locked?
    end

    # ------------------------------------------------------------------
    # cache / package / pack
    # ------------------------------------------------------------------
    def self.cache(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      code = install(stdout, stderr, rest)
      return code if code != 0

      definition = Definition.build
      vendor = File.join(Dir.current, "vendor", "cache")
      Dir.mkdir_p(vendor)

      bridge = Bridge::Client.new
      begin
        abi = ruby_abi(bridge)
        install_root = File.join(install_path(definition.config), "ruby", abi, "cache")
        stdout.puts "Updating files in vendor/cache"
        definition.lockfile!.specs.each do |spec|
          gem_file = File.join(install_root, "#{spec.full_name}.gem")
          next unless File.file?(gem_file)
          destination = File.join(vendor, "#{spec.full_name}.gem")
          next if File.file?(destination)
          FileUtils.cp(gem_file, destination)
          stdout.puts "  * #{spec.full_name}.gem"
        end
      ensure
        bridge.close
      end
      0
    end

    # ------------------------------------------------------------------
    # clean
    # ------------------------------------------------------------------
    def self.clean(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        abi = ruby_abi(bridge)
        install_root = File.join(install_path(definition.config), "ruby", abi)
        gems_dir = File.join(install_root, "gems")
        bin_dir = File.join(install_root, "bin")
        specs_dir = File.join(install_root, "specifications")
        return 0 unless Dir.exists?(gems_dir)

        used = Set(String).new
        definition.lockfile!.specs.each { |s| used << s.full_name }

        removed = 0
        Dir.children(gems_dir).each do |full_name|
          next if used.includes?(full_name)
          gem_bin_dir = File.join(gems_dir, full_name, "bin")
          if Dir.exists?(gem_bin_dir)
            Dir.children(gem_bin_dir).each do |exe|
              {"", ".bat"}.each do |suffix|
                stub = File.join(bin_dir, exe + suffix)
                File.delete(stub) if File.file?(stub)
              end
            end
          end
          FileUtils.rm_rf(File.join(gems_dir, full_name))
          spec_file = File.join(specs_dir, "#{full_name}.gemspec")
          File.delete(spec_file) if File.file?(spec_file)
          removed += 1
        end
        stdout.puts "Removing #{removed} gem#{removed == 1 ? "" : "s"}" if removed > 0
        0
      ensure
        bridge.close
      end
    end

    # ------------------------------------------------------------------
    # exec
    # ------------------------------------------------------------------
    def self.exec(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      command = rest.first?
      if command.nil? || command.empty?
        stderr.puts "executable not specified"
        return 1
      end

      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        env = bridge.ruby_environment
        bundler_lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
        if bundler_lib.nil? || bundler_lib.empty?
          bundler_lib = File.expand_path("../lib", File.dirname(env.ruby_exe))
        end

        abi = ruby_abi(bridge)
        bin_dir = File.join(install_path(definition.config), "ruby", abi, "bin")

        process_env = ENV.to_h
        process_env["RUBYOPT"] = "-r#{File.join(bundler_lib.not_nil!, "bundler/setup")}"
        process_env["RUBYLIB"] = bundler_lib.not_nil!
        process_env["BUNDLE_GEMFILE"] = File.expand_path(definition.gemfile_path).gsub(/\\/, "/")
        path_delimiter = {{ flag?(:windows) }} ? ";" : ":"
        process_env["PATH"] = "#{bin_dir.gsub(/\\/, "/")}#{path_delimiter}#{process_env["PATH"]? || ""}"

        args = rest[1..]

        # Resolve the command against the child PATH. Direct execution avoids
        # cmd.exe quoting mangling; .bat/.cmd wrappers still need the shell.
        bin_forward = bin_dir.gsub(/\\/, "/")
        search_path = "#{bin_forward}#{path_delimiter}#{process_env["PATH"]? || ""}"
        resolved = find_executable(command, search_path)
        if resolved.nil?
          stderr.puts "Could not find executable '#{command}' in the bundle or on PATH."
          return 127
        end

        if resolved.downcase.ends_with?(".bat") || resolved.downcase.ends_with?(".cmd")
          # invoke through cmd so the wrapper resolves its ruby
          process = Process.run("cmd", ["/c", resolved] + args, env: process_env,
            output: :inherit, error: :inherit, input: :inherit)
        elsif resolved.downcase.ends_with?(".exe") || executable_binary?(resolved)
          process = Process.run(resolved, args, env: process_env,
            output: :inherit, error: :inherit, input: :inherit)
        else
          # extensionless ruby script (bin stub) — must run via its shebang
          process = Process.run("ruby", [resolved] + args, env: process_env,
            output: :inherit, error: :inherit, input: :inherit)
        end
        process.exit_code
      ensure
        bridge.close
      end
    end

    private def self.executable_binary?(path : String) : Bool
      return false unless File.file?(path)
      header = Bytes.new(2)
      File.open(path, "rb") { |io| io.read(header) }
      header[0] == 0x4D && header[1] == 0x5A # MZ
    end

    private def self.find_executable(command : String, search_path : String) : String?
      return command if command.includes?("/") || command.includes?("\\") && File.file?(command)

      suffixes = {{ flag?(:windows) }} ? ["", ".bat", ".cmd", ".exe"] : [""]
      search_path.split({{ flag?(:windows) }} ? ";" : ":").each do |dir|
        next if dir.empty?
        suffixes.each do |suffix|
          candidate = File.join(dir, command + suffix)
          return candidate if File.file?(candidate)
        end
      end
      nil
    end

    # ------------------------------------------------------------------
    # binstubs
    # ------------------------------------------------------------------
    def self.binstubs(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      names = rest.reject(&.starts_with?("--"))
      if names.empty?
        stderr.puts "Please pass a gem name on the command line, e.g. bundle binstubs rails"
        return 1
      end

      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        abi = ruby_abi(bridge)
        install_root = File.join(install_path(definition.config), "ruby", abi)
        bin_dir = File.join(install_root, "bin")
        config_bin = definition.config["bin"].to_s
        target = config_bin.empty? ? bin_dir : File.expand_path(config_bin)
        Dir.mkdir_p(target)

        names.each do |name|
          spec = definition.lockfile!.specs.find(&.name.==(name))
          if spec.nil?
            stderr.puts "Could not find gem '#{name}' in the bundle."
            return 7
          end
          gem_file = File.join(install_root, "cache", "#{spec.full_name}.gem")
          next unless File.file?(gem_file)
          info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(gem_file).to_json)
          gem_dir = File.join(install_root, "gems", spec.full_name)
          bindir = info.bindir.empty? ? "bin" : info.bindir
          info.executables.each do |executable|
            source = File.join(gem_dir, bindir, executable)
            next unless File.file?(source)
            content = File.read(source)
            shebang = content.starts_with?("#!") ? "" : "#!/usr/bin/env ruby\n"
            File.write(File.join(target, executable), shebang + content)
            stdout.puts "  #{File.join(target, executable).gsub(/\\/, "/")}"
          end
        end
        0
      ensure
        bridge.close
      end
    end
  end
end
