require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../definition"
require "../resolution"
require "../installer"
require "../downloader"
require "../plugin_hooks"
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
      InstallPaths.ruby_abi(bridge)
    end

    def self.install_path(config : Config) : String
      InstallPaths.install_path(config)
    end

    def self.downloader_cache_root : String
      InstallPaths.downloader_cache_root
    end

    # Port of `Bundler::ProcessLock`: a process-wide exclusive lock on
    # `<bundle_path>/bundler.lock`, acquired during install/update/pristine
    # runs (multi-process competition serializes rather than corrupts).
    class ProcessLock
      getter file : File

      def self.lock(bundle_path : String) : ProcessLock
        Dir.mkdir_p(bundle_path)
        io = File.open(File.join(bundle_path, "bundler.lock"), "a+")
        io.flock_exclusive
        new(io)
      end

      def initialize(@file : File)
      end

      def close : Nil
        @file.flock_unlock
        @file.close
      rescue
        nil
      end
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
    def self.install(stdout : IO, stderr : IO, rest : Array(String), summary : Bool = true, show_resolving : Bool = true, no_reuse : Bool = false) : Int32
      if rest.includes?("--frozen")
        # Thor rejects the flag before any Gemfile validation; the exact
        # message depends on the profile and the command (see frozen helper).
        bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        if code = frozen_flag_exit(rest, stderr, Definition.build.lockfile_exists?, bundle_version, "install")
          return code
        end
      end
      definition = Definition.build
      config = definition.config
      if config.frozen? && !definition.lockfile_exists?
        raise ProductionError.new("Frozen mode is set, but there's no lockfile")
      end

      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, false, bridge)
        resolution.progress = stdout
        lock = ProcessLock.lock(install_path(config))
        if !cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        if days = cooldown_flag_value(rest)
          resolution.cooldown_days = days
        end
        resolution.local_only = rest.includes?("--local")
        resolution.prefer_local = rest.includes?("--prefer-local")

        install_path = install_path(config)
        abi = ruby_abi(bridge)
        downloader = Downloader.new(resolution.primary_remote, downloader_cache_root)
        installer = Installer.new(install_path, abi, bridge, downloader, stdout)
        installers_by_remote = {resolution.primary_remote => installer}
        if target_rbconfig = flag_value(rest, "--target-rbconfig")
          installer.target_rbconfig = File.expand_path(target_rbconfig, Dir.current)
        end

        # --no-lock: resolve from scratch every run (no reuse, no write).
        no_lock = rest.includes?("--no-lock")
        reuse = (no_reuse || no_lock) ? false : resolution_can_reuse?(resolution)
        resolution.show_resolving = show_resolving

        # --no-lock exists only on 4.x (2.7.x: unknown switch).
        if no_lock && resolution.bridge_bundler_version.starts_with?("2.")
          stderr.puts "Unknown switches \"--no-lock\""
          stderr.puts "Did you mean?  \"--no-color\""
          return 15
        end

        # --trust-policy validation (pinned RubyGems known policies).
        if policy = flag_value(rest, "--trust-policy")
          unless {"NoSecurity", "AlmostNoSecurity", "LowSecurity", "MediumSecurity", "HighSecurity"}.includes?(policy)
            exit_untrusted_policy = stderr
            exit_untrusted_policy.puts "RubyGems doesn't know about trust policy '#{policy}'. The known policies are:"
            exit_untrusted_policy.puts "NoSecurity, AlmostNoSecurity, LowSecurity, MediumSecurity, HighSecurity."
            return 15
          end
        end

        # BUNDLED WITH version selection (pinned reference behavior): when the
        # running profile differs from the lockfile's BUNDLED WITH, install
        # the target bundler into GEM_HOME and continue under it.
        if definition.lockfile_exists?
          locked_bundler = definition.lockfile!.bundler_version
          if locked_bundler && !resolution.bridge_bundler_version.starts_with?(locked_bundler.split(".")[0] + "." + (locked_bundler.split(".")[1]? || "0"))
            auto_switch_bundler(definition, stdout, stderr, resolution)
          end
        end
        # no_reuse (add): the reference prints the source-index fetch up front
        # (its resolve runs before the resolution's lazy fetch would).
        if no_reuse
          # reference order: probe resolves (fetch+Resolving), then the install
          # fetches once more without a second Resolving line (its lazy fetch
          # lands after the probe's lines)
          resolution.show_resolving = false
        end

        # Git sources fetch before resolving (pinned reference behavior);
        # their "Fetching <remote>" lines appear first.
        resolution.non_gem_sources.each do |name, source|
          next unless source.type == "Git"
          # revision already pinned and checked out -> nothing to fetch
          next if reuse && source.revision
          stdout.puts "Fetching #{source.remote}"
          resolution.ensure_source_dir(name, source)
        end

        specs = resolution.resolve!(reuse)

        previous_versions = definition.lockfile_exists? ? definition.lockfile!.specs.to_h { |s| {s.name, s.version} } : {} of String => String
        # --force reinstalls already-installed gems (no "Fetching" lines for
        # already-installed specs; the reference still installs them).
        force_reinstall = rest.any? { |a| a == "--force" || a == "--redownload" }
        force_install = [] of Resolution::ResolvedSpec
        pending = specs.sort_by(&.full_name).select(&.source_type.==("GEM"))
        if force_reinstall
          force_install, pending = pending.partition do |spec|
            installer.installed?(spec.name, spec.version.to_s, spec.platform)
          end
        else
          pending = pending.reject do |spec|
            installer.installed?(spec.name, spec.version.to_s, spec.platform)
          end
        end
        # Locked-path installs print the source-index line when downloads are
        # pending, but never a Resolving line (pinned reference behavior,
        # update-conservative fixture).
        if reuse && pending.any?
          if resolution.primary_remote.starts_with?("file:")
            stdout.puts "Fetching source index from #{resolution.primary_remote}"
          else
            stdout.puts "Fetching gem metadata from #{resolution.primary_remote}."
          end
        end
        # Reference output order: all "Fetching" lines (downloads) first,
        # then all "Installing" lines. Updated gems show "(was <old>)".
        was_suffix = ->(spec : Resolution::ResolvedSpec) do
          if old = previous_versions[spec.name]?
            old != spec.version.to_s ? " (was #{old})" : ""
          else
            ""
          end
        end
        cached_paths = {} of String => String
        pending.each do |spec|
          stdout.puts "Fetching #{spec.name} #{spec.version}#{was_suffix.call(spec)}"
          remote = resolution.remote_for(spec.name)
          spec_downloader = remote == resolution.primary_remote ? downloader : (installers_by_remote[remote]?.try(&.downloader) || Downloader.new(remote, downloader_cache_root))
          cached_paths[spec.full_name] = spec_downloader.fetch(
            spec.name, spec.version.to_s, spec.platform, spec.checksum
          )
        end
        # Reference installs pure-Ruby gems first, native-extension gems
        # last (pinned cache --all-platforms install order probe).
        pure, ext = pending.partition do |spec|
          cached = cached_paths[spec.full_name]?
          begin
            cached.nil? || Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(cached).to_json).extensions.empty?
          rescue
            true
          end
        end
        (pure + ext).each do |spec|
          cached = cached_paths[spec.full_name]?
          stdout.puts "Installing #{spec.name} #{spec.version}#{was_suffix.call(spec)}#{native_suffix(bridge, cached)}"
          remote = resolution.remote_for(spec.name)
          spec_installer = installers_by_remote[remote]? || begin
            remote_downloader = Downloader.new(remote, downloader_cache_root)
            next_installer = Installer.new(install_path, abi, bridge, remote_downloader, stdout)
            installers_by_remote[remote] = next_installer
            next_installer
          end
          spec_installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum)
          # The reference records the installed package's sha256 in CHECKSUMS
          # even for file:// sources.
          if cached && File.file?(cached)
            sha = Digest::SHA256.hexdigest(File.read(cached))
            resolution.install_checksums["#{spec.name}-#{spec.version}"] = "sha256=#{sha}"
          end
        end
        force_install.each do |spec|
          stdout.puts "Installing #{spec.name} #{spec.version}#{native_suffix(bridge, nil)}"
          installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum, true)
        end

        # PATH/GIT sources don't print fetch/install lines; materialize
        # bundle binstubs from their checked-out gemspec directory so
        # `bundle exec <executable>` can resolve them.
        specs.each do |spec|
          next unless spec.source_type == "PATH" || spec.source_type == "GIT"
          source = spec.source_info
          next unless source
          source_dir = resolution.ensure_source_dir(spec.name, source)
          installer.install_source_gem(spec.name, spec.version.to_s, spec.platform, source_dir)
        end

        # --standalone[=GROUP...]: render <install_path>/bundler/setup.rb
        # (pinned `Bundler::Standalone#generate`), so the installed bundle
        # works without RubyGems/Bundler activation.
        standalone = rest.any? { |a| a == "--standalone" || a.starts_with?("--standalone=") }
        if standalone
          render_standalone_setup(install_path, abi, specs)
        end

        if summary
          deps_count = resolution.evaluation.dependencies.count { |d| !d.gemspec_dev_dep }
          gems_count = specs.size
          # 2.7.x counts the running Bundler; a switched run counts the
          # switched-to bundler instead
          if resolution.switched_bundler
            gems_count += 1
          elsif resolution.bridge_bundler_version.starts_with?("2.")
            gems_count += 1
          end
          stdout.puts "Bundle complete! #{deps_count} Gemfile dependenc#{deps_count == 1 ? "y" : "ies"}, #{gems_count} gem#{gems_count == 1 ? "" : "s"} now installed."
          stdout.puts "Bundled gems are installed into `#{install_path.gsub(/\\\\/, "/").gsub(/\\/, "/")}`"
          print_cooldown_summary(resolution, stdout)
        end

        unless rest.includes?("--no-lock") || config.frozen?
          text = resolution.generated_lockfile.to_lock
          existing = File.file?(definition.lockfile_path) ? File.read(definition.lockfile_path) : nil
          # Reference parity: install leaves the lockfile untouched when the
          # semantic content is unchanged — formatting-only deltas (BUNDLED
          # WITH indent across profiles) do not trigger a rewrite.
          if existing.nil? || semantic_content(existing) != semantic_content(text)
            File.write(definition.lockfile_path, text)
          end
        end

        # Plugin lifecycle hook (architecture §2.2); no-op without plugins
        begin
          PluginHooks.call(bridge, definition, "post-install")
        rescue Bridge::BridgeError
          # hook failures must not fail the install (reference: friendly error)
        end
        0
      ensure
        lock.not_nil!.close
        bridge.close
      end
    end

    # The reference install reuses a valid lockfile without re-resolving
    # (no "Fetching source index"/"Resolving dependencies..." on reruns).
    private def self.resolution_can_reuse?(resolution : Resolution) : Bool
      resolution.reuse_locked?
    end

    # Writes the standalone `bundler/setup.rb` body (pinned
    # `Bundler::Standalone#generate`) next to the installed tree.
    private def self.render_standalone_setup(install_path : String, abi : String, specs : Array(Resolution::ResolvedSpec)) : Nil
      target = File.join(install_path, "bundler")
      Dir.mkdir_p(target)
      File.write(File.join(target, "setup.rb"), String.build do |io|
        io.puts "require 'rbconfig'"
        io.puts "module Kernel"
        io.puts "  remove_method(:gem) if private_method_defined?(:gem)"
        io.puts ""
        io.puts "  def gem(*)"
        io.puts "  end"
        io.puts ""
        io.puts "  private :gem"
        io.puts "end"
        io.puts "unless defined?(Gem)"
        io.puts "  module Gem"
        io.puts "    def self.ruby_api_version"
        io.puts "      RbConfig::CONFIG[\"ruby_version\"]"
        io.puts "    end"
        io.puts ""
        io.puts "    def self.extension_api_version"
        io.puts "      if 'no' == RbConfig::CONFIG['ENABLE_SHARED']"
        io.puts "        \"\#{ruby_api_version}-static\""
        io.puts "      else"
        io.puts "        ruby_api_version"
        io.puts "      end"
        io.puts "    end"
        io.puts "  end"
        io.puts "end"
        io.puts "if Gem.respond_to?(:discover_gems_on_require=)"
        io.puts "  Gem.discover_gems_on_require = false"
        io.puts "else"
        io.puts "  [::Kernel.singleton_class, ::Kernel].each do |k|"
        io.puts "    if k.private_method_defined?(:gem_original_require)"
        io.puts "      private_require = k.private_method_defined?(:require)"
        io.puts "      k.send(:remove_method, :require)"
        io.puts "      k.send(:define_method, :require, k.instance_method(:gem_original_require))"
        io.puts "      k.send(:private, :require) if private_require"
        io.puts "    end"
        io.puts "  end"
        io.puts "end"
        specs.each do |spec|
          next unless spec.source_type == "GEM"
          io << "$:.unshift File.expand_path(\"\#{__dir__}/../\#{RUBY_ENGINE}/\#{Gem.ruby_api_version}/gems/#{spec.full_name}/lib\")\n"
        end
      end)
    end

    # ------------------------------------------------------------------
    # cache / package / pack
    # ------------------------------------------------------------------
    def self.cache(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      cache_arg = flag_value(rest, "--cache-path") if rest.any? { |a| a == "--cache-path" || a.starts_with?("--cache-path=") }
      cache_target = cache_arg ? File.expand_path(cache_arg) : File.join(Dir.current, "vendor", "cache")
      cache_label = cache_arg ? cache_arg.gsub(/\\/, "/") : "vendor/cache"
      unless rest.includes?("--no-install")
        code = install(stdout, stderr, rest)
        return code if code != 0
      end

      definition = Definition.build
      Dir.mkdir_p(cache_target)
      # 2.7.x: cache options are remembered in .bundle/config (pinned probe:
      # plain `cache` writes BUNDLE_CACHE_ALL "false").
      bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
      if bundle_version.starts_with?("2.")
        definition.config.set_local("cache_all", "false")
        definition.config.set_local("cache_path", cache_arg) if cache_arg
      end

      bridge = Bridge::Client.new
      begin
        abi = ruby_abi(bridge)
        install_root = File.join(install_path(definition.config), "ruby", abi, "cache")
        stdout.puts "Updating files in #{cache_label}"
        if rest.includes?("--all-platforms") && bundle_version.starts_with?("4.")
          # The 4.x reference re-fetches the source index to enumerate the
          # locked gems' platform variants (pinned probe).
          if gem_remote = definition.lockfile!.sources.find { |s| s.type == "GEM" || s.type == "Rubygems" }.try(&.remote)
            stdout.puts "Fetching source index from #{gem_remote}"
          end
        end
        definition.lockfile!.specs.each do |spec|
          candidates = if rest.includes?("--all-platforms")
                         # Every platform variant of the locked spec present
                         # in the download cache (Bundler `cache
                         # --all-platforms` parity).
                         prefix = "#{spec.name}-#{spec.version}"
                         Dir.exists?(install_root) ? Dir.children(install_root).select { |f| f == "#{prefix}.gem" || f.starts_with?("#{prefix}-") }.sort : [] of String
                       else
                         ["#{spec.full_name}.gem"]
                       end
          candidates.each do |gem_name|
            gem_file = File.join(install_root, gem_name)
            next unless File.file?(gem_file)
            destination = File.join(cache_target, gem_name)
            next if File.file?(destination)
            FileUtils.cp(gem_file, destination)
            stdout.puts "  * #{gem_name}"
          end
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
      dry_run = rest.includes?("--dry-run")
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        abi = ruby_abi(bridge)
        install_root = File.join(install_path(definition.config), "ruby", abi)
        lockfile = definition.lockfile!
        # specs_to_keep (pinned `Bundler::Runtime#clean`): lockfile specs plus
        # the running bundler itself (not installed via Source::Rubygems here).
        keep_names = lockfile.specs.map(&.full_name).to_set

        # Stale git checkouts: any <base>-* directory not holding a locked
        # Git source checkout.
        checkout_keep = Set(String).new
        lockfile.sources.each do |section|
          next unless section.type == "GIT"
          base = GitSource.base_name(section.remote || "")
          checkout_keep << base
        end
        git_root = File.join(install_root, "bundler", "gems")
        git_removed = [] of String
        stale_git_dirs = [] of String
        if Dir.exists?(git_root)
          stale_git_dirs = Dir.children(git_root).select do |name|
            full = File.join(git_root, name)
            Dir.exists?(full) && name != "extensions" && !checkout_keep.any? { |base| name.starts_with?("#{base}-") }
          end
        end
        git_removed += stale_git_dirs

        # Stale gem dirs, printed per entry (pinned: only gem/git dir removals
        # announce with "Removing <dir name>"; cache/spec/bin go silently).
        gems_dir = File.join(install_root, "gems")
        stale_gem_dirs = [] of String
        if Dir.exists?(gems_dir)
          stale_gem_dirs = Dir.children(gems_dir).select do |full_name|
            Dir.exists?(File.join(gems_dir, full_name)) && !keep_names.includes?(full_name)
          end
        end
        unless dry_run
          stale_gem_dirs.each do |full_name|
            gem_bin_dir = File.join(gems_dir, full_name, "bin")
            if Dir.exists?(gem_bin_dir)
              Dir.children(gem_bin_dir).each do |exe|
                {"", ".bat"}.each do |suffix|
                  stub = File.join(File.join(install_root, "bin"), exe + suffix)
                  File.delete(stub) if File.file?(stub)
                end
              end
            end
          end
          stale_gem_dirs.each { |full_name| FileUtils.rm_rf(File.join(gems_dir, full_name)) }
          stale_git_dirs.each { |name| FileUtils.rm_rf(File.join(git_root, name)) }
          # Silent removals: stale specifications, cache .gem files,
          # extension dirs and git cache mirrors.
          specs_dir = File.join(install_root, "specifications")
          Dir.children(specs_dir).reject { |f| keep_names.includes?(f.sub(/\.gemspec$/, "")) }
            .each { |f| File.delete(File.join(specs_dir, f)) } if Dir.exists?(specs_dir)
          cache_dir = File.join(install_root, "cache")
          if Dir.exists?(cache_dir)
            Dir.children(cache_dir).select(&.ends_with?(".gem")).reject { |f| keep_names.includes?(f.sub(/\.gem$/, "")) }
              .each { |f| File.delete(File.join(cache_dir, f)) }
          end
        end
        (stale_gem_dirs + stale_git_dirs).sort.each do |name|
          # Pinned `Bundler::Runtime#remove_dir`: "name (version)" from the
          # directory basename; dry-run announces "Would have removed".
          parts = name.split("-")
          label = "#{parts[0...-1].join("-")} (#{parts.last})"
          stdout.puts "#{dry_run ? "Would have removed" : "Removing"} #{label}"
        end
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

        # Path commands: an existing but non-executable file reports 126
        # ("not executable"); anything else falls through to not-found.
        if command.includes?("/") || command.downcase.matches?(/^[a-z]:[\\\/]/)
          if File.file?(command) && !File.executable?(command)
            stderr.puts "bundler: not executable: #{command}"
            return 126
          end
          if File.file?(command)
            resolved = command
          else
            stderr.puts "bundler: command not found: #{command}"
            stderr.puts "Install missing gem executables with `bundle install`"
            return 127
          end
        else
          # Resolve the command against the child PATH. Direct execution avoids
          # cmd.exe quoting mangling; .bat/.cmd wrappers still need the shell.
          bin_forward = bin_dir.gsub(/\\/, "/")
          search_path = "#{bin_forward}#{path_delimiter}#{process_env["PATH"]? || ""}"
          resolved = find_executable(command, search_path)
          if resolved.nil?
            stderr.puts "bundler: command not found: #{command}"
            stderr.puts "Install missing gem executables with `bundle install`"
            return 127
          end
        end

        disable_exec_load = definition.config["disable_exec_load"] == true
        loadable = !disable_exec_load && directly_loadable?(resolved, env.ruby_exe, stderr)
        exe_name, exe_args = if loadable
                               # Bundler's loadable-script optimization: run the
                               # script through the Ruby runtime adapter's
                               # Kernel.load entry point instead of a fresh
                               # shebang process. The loader sets $0/ARGV and
                               # restores SIGINT to DEFAULT exactly as
                               # Bundler::CLI::Exec#kernel_load does.
                               loader = <<-RUBY
                               file = ARGV.shift
                               $0 = file
                               cmd = ENV["CELERITE_EXEC_COMMAND"] || file
                               Process.setproctitle("\#{file} \#{ARGV.join(" ")}".strip) if Process.respond_to?(:setproctitle)
                               trap("INT", "DEFAULT")
                               begin
                                 Kernel.load(file)
                               rescue SystemExit, SignalException
                                 raise
                               rescue Exception
                                 warn "bundler: failed to load command: \#{cmd} (\#{file})"
                                 raise
                               end
                               RUBY
                               process_env["CELERITE_EXEC_COMMAND"] = command
                               {env.ruby_exe, ["-e", loader, File.expand_path(resolved)] + args}
                             elsif resolved.downcase.ends_with?(".bat") || resolved.downcase.ends_with?(".cmd")
                               {"cmd", ["/c", resolved] + args}
                             elsif resolved.downcase.ends_with?(".exe") || executable_binary?(resolved)
                               {resolved, args}
                             else
                               # extensionless ruby script (bin stub)
                               {"ruby", [resolved] + args}
                             end

        child = Process.new(exe_name, exe_args, input: :inherit, output: :inherit, error: :inherit, env: process_env)
        install_signal_forward(child)
        child.wait.exit_code
      ensure
        bridge.close
      end
    end

    # Terminate the exec'd child when this process receives SIGINT/SIGTERM,
    # so the group exits together (Bundler traps signals on `exec`).
    # On Windows, Signal traps are not implemented in this Crystal build and
    # the spawn path shares the console instead.
    private def self.install_signal_forward(child : Process) : Nil
      {% if !flag?(:windows) %}
        Signal::INT.trap do
          child.terminate
        end
      {% end %}
    end

    # Pinned `Bundler::CLI::Exec#directly_loadable?`: a non-empty Ruby script
    # whose shebang (Unix) or .bat companion (Windows) shows it targets Ruby.
    private def self.directly_loadable?(resolved : String, ruby_exe : String, stderr : IO) : Bool
      {% if flag?(:windows) %}
        wrapper = resolved.ends_with?(".bat") ? resolved : "#{resolved}.bat"
        script = resolved.ends_with?(".bat") ? resolved.chomp(".bat") : resolved
        return false unless File.file?(script)
        if File.size(script) == 0
          stderr.puts "#{script} is empty"
          return false
        end
        if File.file?(wrapper)
          bytes = Bytes.new(32)
          File.open(wrapper, "rb") { |io| io.read(bytes) }
          header = String.new(bytes)
          return header.includes?(File.basename(ruby_exe))
        end
        ruby_shebang?(script, ruby_exe)
      {% else %}
        ruby_shebang?(resolved, ruby_exe)
      {% end %}
    end

    private def self.ruby_shebang?(path : String, ruby_exe : String) : Bool
      return false unless File.file?(path)
      if File.size(path) == 0
        return false
      end
      possibilities = [
        "#!/usr/bin/env ruby\n",
        "#!/usr/bin/env jruby\n",
        "#!/usr/bin/env truffleruby\n",
        "#!#{ruby_exe.gsub(/\\/, "/")}\n",
      ]
      bytes = Bytes.new(possibilities.map(&.bytesize).max)
      File.open(path, "rb") { |io| io.read(bytes) }
      header = String.new(bytes)
      possibilities.any? { |shebang| header.starts_with?(shebang) }
    rescue
      false
    end

    private def self.executable_binary?(path : String) : Bool
      return false unless File.file?(path)
      header = Bytes.new(4)
      read = File.open(path, "rb") { |io| io.read(header) }
      return false if read < 2
      # PE/COFF (MZ) — Windows executables
      return true if header[0] == 0x4D && header[1] == 0x5A
      return false if read < 4
      # ELF — Linux executables
      if header[0] == 0x7F && header[1] == 0x45 && header[2] == 0x4C && header[3] == 0x46
        return true
      end
      # Mach-O 32/64 and fat variants — macOS executables
      mach_o = {0xCE, 0xCF, 0xCA, 0xBE}.any? do |first|
        header[0] == first && header[1] == 0xFA
      end
      mach_o ||=
        header[0] == 0xCA && header[1] == 0xFE && header[2] == 0xBA && header[3] == 0xBE
      mach_o ||=
        header[0] == 0xBE && header[1] == 0xBA && header[2] == 0xFE && header[3] == 0xCA
      mach_o
    end

    # Reference auto-switch trace (2.7.x profile on a 4.0.24 lockfile):
    #   Bundler 2.7.2 is running, but your lockfile was generated with 4.0.24.
    #     Installing Bundler 4.0.24 and restarting using that version.
    #   Fetching bundler 4.0.24
    #   Fetching gem metadata from https://rubygems.org/.
    #   Installing bundler 4.0.24
    # The bundler gem comes from rubygems.org (the reference's switch source).
    def self.auto_switch_bundler(definition : Definition, stdout : IO, stderr : IO, resolution : Resolution) : Nil
      locked = definition.lockfile!.bundler_version.not_nil!
      stdout.puts "Bundler #{resolution.bridge_bundler_version} is running, but your lockfile was generated with #{locked}. Installing Bundler #{locked} and restarting using that version."
      stdout.puts "Fetching bundler #{locked}"

      downloader = Downloader.new("https://rubygems.org/", InstallPaths.downloader_cache_root)
      cached = downloader.fetch("bundler", locked, nil, nil)
      stdout.puts "Fetching gem metadata from https://rubygems.org/."

      bridge = Bridge::Client.new
      begin
        abi = InstallPaths.ruby_abi(bridge)
        installer = Installer.new(InstallPaths.install_path(definition.config), abi, bridge, downloader, stdout)
        stdout.puts "Installing bundler #{locked}"
        installer.install("bundler", locked, nil, nil)
        # The reference restarts under the installed version; the lockfile
        # records the switched-to version from this point on, and the
        # "gems now installed" count includes the switched bundler.
        resolution.bridge_bundler_version = locked
        resolution.switched_bundler = true
      ensure
        bridge.close
      end
    end

    # Reference parity: install leaves the lockfile untouched when the
    # semantic content is unchanged — formatting-only deltas (BUNDLED WITH
    # indent across profiles) do not trigger a rewrite. Comparison strips
    # blank lines, the BUNDLED WITH heading and its version line.
    private def self.semantic_content(text : String) : String
      text.gsub(/\r\n/, "\n").lines.reject do |line|
        stripped = line.strip
        stripped.empty? || stripped == "BUNDLED WITH" || stripped.matches?(/^\d+\.\d+\.\d+/)
      end.join("\n")
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

    private def self.binstubs_remember_shebang(rest : Array(String), stderr : IO) : Nil
      return unless (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
      if custom = flag_value(rest, "--shebang")
        Definition.build.config.set_local("shebang", custom)
      end
    end

    # ------------------------------------------------------------------
    # binstubs
    # ------------------------------------------------------------------
    def self.binstubs(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      names = rest.reject(&.starts_with?("--"))
      binstubs_remember_shebang(rest, stderr)
      if rest.includes?("--all") && !names.empty?
        stderr.puts "Cannot specify --all with specific gems"
        return 15
      end
      if names.empty? && !rest.includes?("--all")
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
        target = config_bin.empty? ? File.join(Dir.current, "bin") : File.expand_path(config_bin, Dir.current)
        Dir.mkdir_p(target)

        all = rest.includes?("--all")
        force = rest.includes?("--force")
        storm_specs = definition.lockfile!.specs
        if all
          stderr.puts "Bundler itself does not use binstubs because its version is selected by RubyGems"
        end
        names_list = all ? storm_specs.map(&.name) : names
        skipped = false
        names_list.each do |name|
          spec = storm_specs.find(&.name.==(name))
          if spec.nil?
            stderr.puts "Could not find gem '#{name}' in the bundle."
            return 7
          end
          gem_file = File.join(install_root, "cache", "#{spec.full_name}.gem")
          next unless File.file?(gem_file)
          info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(gem_file).to_json)
          gem_dir = File.join(install_root, "gems", spec.full_name)
          bindir = info.bindir.empty? ? "bin" : info.bindir
          custom_shebang = flag_value(rest, "--shebang")
          info.executables.each do |executable|
            source = File.join(gem_dir, bindir, executable)
            next unless File.file?(source)
            stub = File.join(target, executable)
            next if File.file?(stub) && !force
            content = File.read(source)
            shebang = if custom_shebang
                        "#!/usr/bin/env #{custom_shebang}\n"
                      else
                        content.starts_with?("#!") ? "" : "#!/usr/bin/env ruby\n"
                      end
            File.write(stub, shebang + content)
            # Windows: also emit `<exe>.cmd` with the wrapper preamble
            if {% if flag?(:windows) %}true{% else %}false{% end %} || rest.includes?("--all-platforms")
              File.write(stub + ".cmd", "@ruby -x \"%~f0\" %*\n@exit /b %ERRORLEVEL%\n\n" + shebang + content)
            end
          end
        end
        stdout.puts "If you want to overwrite skipped stubs, use --force." if skipped
        0
      ensure
        bridge.close
      end
    end
  end
end
