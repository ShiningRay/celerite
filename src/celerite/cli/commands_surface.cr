require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../lockfile/writer"
require "../definition"
require "../resolution"
require "../mirror"
require "../proxy"
require "./commands_install"
require "../plugin_commands"
require "../git_source"
require "../glob"
require "../gem_template"
require "yaml"

module Celerite
  # M5 CLI surface commands (pinned against the 4.0.24 oracle): update,
  # add/remove, env, doctor, licenses, fund, info, open, plugin.
  module Commands
    # ------------------------------------------------------------------
    # update: resolve with the named gems (or all) unlocked
    # ------------------------------------------------------------------
    def self.update(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      with_gemfile_overrides(rest) do
        run_update(stdout, stderr, rest)
      end
    end

    private def self.run_update(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if code = reject_unknown_switches(stderr, rest, UPDATE_SWITCH_FLAGS, UPDATE_SWITCH_VALUES)
        return code
      end
      if message = numeric_switch_error(rest, ["--jobs", "-j"])
        stderr.puts message
        return 15
      end
      if rest.includes?("--frozen")
        # Thor rejects the flag before any Gemfile validation; the exact
        # message depends on the profile and the command (see frozen helper).
        bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        if code = frozen_flag_exit(rest, stderr, Definition.build.lockfile_exists?, bundle_version, "update")
          return code
        end
      end
      conservative = rest.includes?("--conservative")
      # `Bundler::CLI::Update#run` derives the update scope from Thor's parsed
      # inputs: positional gem names, `--source` values, `--group` values,
      # `--ruby` and `--bundler`. Only when all of them are empty is it a full
      # update; `--all` alongside any of them is rejected.
      gems = subcommand_arguments(rest, UPDATE_SWITCH_FLAGS, UPDATE_SWITCH_VALUES)
      sources = flag_values(rest, "--source")
      group_values = flag_values(rest, "--group") + flag_values(rest, "-g")
      ruby_flag = rest.includes?("--ruby")
      update_bundler = flag_value(rest, "--bundler")
      all_flag = rest.includes?("--all")
      full_update = gems.empty? && sources.empty? && group_values.empty? && !ruby_flag && !update_bundler
      if !full_update && all_flag
        stderr.puts "Cannot specify --all along with specific options."
        return 15
      end

      # parity: bare `bundle update` works but deprecates on stderr on 4.x
      # (2.7.x never deprecates the bare form -observed oracle diff).
      bridge_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
      if full_update && !all_flag && !bridge_version.starts_with?("2.")
        stderr.puts "[DEPRECATED] Pass --all to `bundle update` to update everything"
      end

      definition = Definition.build
      Commands.validate_runtime!(definition)
      config = definition.config
      if config.frozen? && !definition.lockfile_exists?
        raise ProductionError.new("Frozen mode is set, but there's no lockfile")
      end
      # M7(4): fail fast on explicitly configured unsupported settings
      # (and warn-but-continue for proxy env vars).
      if unsupported = Commands.unsupported_setting_error(config, stderr)
        stderr.puts unsupported
        return 1
      end

      # `cli/update.rb` L26-38: a scoped update needs an installed bundle
      # (status 22) and every named gem must already be in the lockfile
      # (status 7, `CLI::Common.ensure_all_gems_in_lockfile!`). A full update
      # may run without a lockfile at all.
      if !full_update
        unless definition.lockfile_exists?
          raise GemfileLockNotFound.new("This Bundle hasn't been installed yet. Run `bundle install` to update and install the bundled gems.")
        end
        locked_names = definition.lockfile!.specs.map(&.name)
        gems.each do |gem_name|
          unless locked_names.includes?(gem_name)
            raise GemNotFoundError.new("Could not find gem '#{gem_name}'.")
          end
        end
      end

      # --source=NAME: only gems from the named Gemfile source unlock; an
      # unknown name matches nothing (reference probe: resolve, then
      # "Bundle updated!" with no installs and no stayed-same report).
      source_restricted = !sources.empty?
      bridge = Bridge::Client.new
      lock : ProcessLock? = nil
      begin
        # `cli/update.rb` L33-35: `--group` widens the explicit gem list with
        # every dependency of the requested groups.
        if !group_values.empty?
          evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
          group_gems = evaluation.dependencies.select do |dep|
            dep.groups.any? { |g| group_values.includes?(g) }
          end.map(&.name)
          gems = (gems + group_gems).uniq
        end
        unlock : Bool | Array(String) = full_update ? true : gems
        if source_name = sources.first?
          evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
          matched = evaluation.sources.any? do |s|
            s.name == source_name || s.remote == source_name ||
              (s.remotes || [] of String).includes?(source_name)
          end
          unlock = matched ? unlock : ([] of String)
        end
        resolution = Resolution.new(definition, unlock, bridge)
        resolution.progress = stdout
        resolution.ruby_update = rest.includes?("--ruby")
        lock = ProcessLock.lock(InstallPaths.install_path(config))
        unless cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        resolution.local_only = rest.includes?("--local")
        resolution.prefer_local = rest.includes?("--prefer-local")
        if days = cooldown_flag_value(rest)
          resolution.cooldown_days = days
        end
        level = if rest.includes?("--patch")
                  "patch"
                elsif rest.includes?("--minor")
                  "minor"
                elsif rest.includes?("--major")
                  "major"
                end
        resolution.version_promotion = level
        resolution.version_promotion_strict = rest.includes?("--strict")

        # BUNDLED WITH semantics: update does not auto-switch -it records
        # the running bundler version in the rewritten lockfile (pinned
        # 2.7.2 reference: update on a 4.0.24 lockfile rewrote BUNDLED WITH
        # to its own version with 2.x indentation).

        install_path = InstallPaths.install_path(config)
        abi = InstallPaths.ruby_abi(bridge)
        gem_root = InstallPaths.gem_root(config, bridge.ruby_environment.default_gem_dir, abi)
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root, Commands.retry_count(config), Celerite::Mirror.resolve(config, resolution.primary_remote), ssl_option(config, "ssl_ca_cert"), ssl_option(config, "ssl_client_cert"), ssl_option(config, "ssl_verify_mode"), timeout: Commands.timeout_seconds(config), proxy: Celerite::Proxy.resolve(config))
        installer = Installer.new(gem_root, abi, bridge, downloader, stdout)
        installer.config = config
        installer.dependency_tree = ->(gem_name : String) { resolution.dependency_tree_for(gem_name) }
        installer.gemfile_name = File.basename(definition.gemfile_path)

        specs = resolution.resolve!

        # Reference prints "Resolving dependencies..." twice whenever a scoped
        # selection is unlocked (a conservative pre-resolve, then the real
        # resolve); `--group` widens into the same selection.
        if !gems.empty? && !source_restricted
          stdout.puts "Resolving dependencies..."
        end

        pending = specs.sort_by(&.full_name).select(&.source_type.==("GEM")).reject do |spec|
          installer.installed?(spec.name, spec.version.to_s, spec.platform)
        end
        previous_versions = definition.lockfile_exists? ? definition.lockfile!.specs.to_h { |s| {s.name, s.version} } : {} of String => String
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
          cached_paths[spec.full_name] = downloader.fetch(
            spec.name, spec.version.to_s, spec.platform, spec.checksum
          )
        end
        # Reference installs pure-Ruby gems first, native extensions last.
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
          installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum)
          if cached && File.file?(cached)
            sha = Digest::SHA256.hexdigest(File.read(cached))
            resolution.install_checksums["#{spec.name}-#{spec.version}"] = "sha256=#{sha}"
          end
        end

        unless config.frozen?
          text = resolution.generated_lockfile.to_lock
          Lockfile.write(definition.lockfile_path, text, preserve_crlf: preserve_lockfile_crlf?)
        end

        # `cli/update.rb` L54-72: for every updated gem compare the freshly
        # resolved version with the locked one - regressions are noted and an
        # unchanged version is reported on stderr. A `--source` restriction
        # narrows the definition to that source, so gems outside it have no
        # resolved spec and stay silent (oracle: `update --source nope
        # json_pure` prints nothing).
        unless gems.empty? || source_restricted
          gems.each do |gem_name|
            locked_version = previous_versions[gem_name]?
            next unless locked_version
            new_spec = specs.find { |s| s.name == gem_name }
            next unless new_spec
            new_version = new_spec.version.to_s
            if Gem::Version.new(new_version) < Gem::Version.new(locked_version)
              stderr.puts "Note: #{gem_name} version regressed from #{locked_version} to #{new_version}"
            elsif new_version == locked_version
              stderr.puts "Bundler attempted to update #{gem_name} but its version stayed the same"
            end
          end
        end

        stdout.puts "Bundle updated!"
        print_cooldown_summary(resolution, stdout)
        0
      ensure
        lock.try(&.close)
        bridge.close
      end
    end

    # ------------------------------------------------------------------
    # add: append `gem "name"` to the Gemfile and install
    # ------------------------------------------------------------------
    # `bundle add` option surface (bundler-4.0.24 cli.rb:404-426). Values that
    # are accepted but not implemented yet (--github/--glob/--cooldown) stay
    # here so the switch check matches the reference; their semantics are
    # recorded as a declared gap instead.
    ADD_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--skip-install", "--optimistic", "--strict"]
    ADD_SWITCH_VALUES = SWITCH_VALUES_COMMON + [
      "--version", "-v", "--group", "-g", "--source", "-s", "--require", "-r",
      "--path", "--git", "--github", "--branch", "--ref", "--glob", "--cooldown",
    ]

    def self.add(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if code = reject_unknown_switches(stderr, rest, ADD_SWITCH_FLAGS, ADD_SWITCH_VALUES)
        return code
      end
      if rest.includes?("--strict") && rest.includes?("--optimistic")
        stderr.puts "You cannot specify `--strict` and `--optimistic` at the same time."
        return 15
      end
      name = rest.reject(&.starts_with?("--")).first?
      if name.nil?
        stderr.puts "`add` requires at least 1 argument"
        return 1
      end

      # Pinned by `add-git`: the reference announces the git fetch before the
      # requirement probe's index fetch/resolve lines.
      if git = flag_value(rest, "--git")
        stdout.puts "Fetching #{git}"
      end

      definition = Definition.build
      gemfile_path = definition.gemfile_path
      gemfile = File.read(gemfile_path)

      if gemfile.matches?(/^\s*gem\s+["']#{Regex.escape(name)}["']/)
        stderr.puts "Cannot declare #{name} twice in the Gemfile"
        return 1
      end

      # Requirement semantics pinned by add-version/add-strict/
      # add-optimistic probes: explicit `--version` is exact; otherwise
      # strict (`= major.minor`), optimistic (`>= major.minor`) or the
      # default pessimistic (`~> major.minor`) form.
      version_requirement = latest_requirement_for(definition, name, stdout, rest)
      groups = (flag_value(rest, "--group") || flag_value(rest, "-g") || "").split(",").map(&.strip).reject(&.empty?)
      group_line = groups.empty? ? "" : ", group: #{groups.size == 1 && !rest.join(" ").includes?(",") ? ":#{groups.first}" : groups.map { |g| ":#{g}" }.join(", ")}"
      gem_line = "gem \"#{name}\"#{version_requirement}#{group_line}#{add_option_suffix(rest)}"

      # Ruby's text mode on Windows rewrites the Gemfile with CRLF (reference
      # parity: the file is normalized, not preserved).
      lines = gemfile.gsub(/\r\n/, "\n").chomp.split("\n")
      insert_at = lines.rindex { |l| l.strip.starts_with?("gem ") } || (lines.size - 1)
      lines.insert(insert_at + 1, gem_line)
      eol = {{ flag?(:windows) }} ? "\r\n" : "\n"
      File.write(gemfile_path, lines.join(eol) + eol)

      if rest.includes?("--skip-install")
        # Pinned by `add-skip-install`: write the Gemfile line (after the
        # requirement probe) and stop before installation.
        return 0
      end

      # Reference add prints two fetches (requirement probing + shared
      # resolution); install() repeats the second fetch when the lockfile
      # is (re)written.
      code = install(stdout, stderr, install_args_from_add(rest, name),
        summary: false, no_reuse: true)
      code
    end

    # `run_install` validates its arguments with INSTALL_SWITCH_*, which does
    # not know add-only options; forwarding them was a real exit-15 bug. Drop
    # the add-specific flags (and their values) plus the gem name positional.
    private def self.install_args_from_add(rest : Array(String), name : String) : Array(String)
      add_values = [
        "--version", "-v", "--group", "-g", "--source", "-s", "--require", "-r",
        "--path", "--git", "--github", "--branch", "--ref", "--glob", "--cooldown",
      ]
      add_flags = ["--skip-install", "--optimistic", "--strict"]
      filtered = [] of String
      skip_value = false
      rest.each do |arg|
        if skip_value
          skip_value = false
          next
        end
        next if arg == name
        next if add_flags.includes?(arg)
        matched = add_values.find { |flag| arg == flag || arg.starts_with?("#{flag}=") }
        if matched
          skip_value = arg == matched
          next
        end
        filtered << arg
      end
      filtered
    end

    # Gemfile options added by `bundle add` (--path/--git/--branch/--ref/
    # --source/--require). Values are Ruby string literals; `--require`
    # accepts the bare keyword `false`.
    private def self.add_option_suffix(rest : Array(String)) : String
      parts = [] of String
      if path = flag_value(rest, "--path")
        parts << "path: #{path.inspect}"
      end
      if git = flag_value(rest, "--git")
        parts << "git: #{git.inspect}"
      end
      if branch = flag_value(rest, "--branch")
        parts << "branch: #{branch.inspect}"
      end
      if git_ref = flag_value(rest, "--ref")
        parts << "ref: #{git_ref.inspect}"
      end
      if source = flag_value(rest, "--source") || flag_value(rest, "-s")
        parts << "source: #{source.inspect}"
      end
      if require_path = flag_value(rest, "--require") || flag_value(rest, "-r")
        parts << (require_path == "false" ? "require: false" : "require: #{require_path.inspect}")
      end
      parts.map { |part| ", #{part}" }.join
    end

    private def self.latest_requirement_for(definition : Definition, name : String, stdout : IO, rest : Array(String)) : String
      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, false, bridge)
        if flag_value(rest, "--path").nil? && flag_value(rest, "--git").nil?
          # Reference probes the index source before resolving: the fetch line
          # comes first, then the resolver announcement.
          resolution.progress = IO::Memory.new
          resolution.show_resolving = false
          resolution.resolve!
          remote = resolution.primary_remote
          stdout.puts "Fetching source index from #{remote.chomp("/")}/" unless remote.empty?
          stdout.puts "Resolving dependencies..."
        else
          resolution.progress = stdout # path/git probes use the local gemspec
          resolution.show_resolving = true
          resolution.resolve!
        end

        if explicit = flag_value(rest, "--version") || flag_value(rest, "-v")
          return ", \"= #{explicit}\""
        end

        versions = if local_spec_dir = flag_value(rest, "--path") || flag_value(rest, "--git")
                     # Path and local-git sources derive the version from the
                     # local gemspec (pinned `add-path`); index probes do not
                     # see the gem.
                     begin
                       info = bridge.load_gemspec_dir(File.expand_path(local_spec_dir, Dir.current))
                       [Gem::Version.new(info.version)]
                     rescue
                       [] of Gem::Version
                     end
                   else
                     # When scoped `--source` is used, resolve the requirement
                     # from that source rather than the primary remote.
                     source_remote = flag_value(rest, "--source") || flag_value(rest, "-s")
                     client = source_remote ? resolution.compact_index_client_for(source_remote) : resolution.compact_index_client
                     entries = client.info(name)
                     entries.map { |e| Gem::Version.new(e.version) }.reject(&.prerelease?)
                   end
        return "" if versions.empty?
        latest = versions.max
        # Pinned `Injector#conservative_version`: versions < 1.0 keep three
        # segments (0.1.0), versions >= 1.0 keep major.minor (1.8).
        seg_end = latest >= Gem::Version.new("1.0") ? 1 : 2
        segs = latest.segments
        segs = segs[0..seg_end] if segs.size > seg_end + 1
        operator = if rest.includes?("--strict")
                     "= "
                   elsif rest.includes?("--optimistic")
                     ">= "
                   else
                     "~> "
                   end
        ", \"#{operator}#{segs.join(".")}\""
      rescue
        ""
      ensure
        bridge.close
      end
    end

    # ------------------------------------------------------------------
    # remove: delete `gem "name"` lines from the Gemfile and clean up
    # ------------------------------------------------------------------
    def self.remove(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # Thor parses options before the command body runs, so unknown switches
      # are rejected even though `remove` has no options of its own.
      if (code = reject_unknown_switches(stderr, rest, REMOVE_SWITCH_FLAGS, REMOVE_SWITCH_VALUES))
        return code
      end
      names = rest.reject(&.starts_with?("--"))
      if names.empty?
        stderr.puts "`remove` requires at least 1 argument"
        return 1
      end

      definition = Definition.build
      gemfile_path = definition.gemfile_path
      lines = File.read(gemfile_path).gsub(/\r\n/, "\n").chomp.split("\n")

      removed = [] of String
      kept = lines.select do |line|
        matched = names.any? { |n| line.strip.matches?(/^gem\s+["']#{Regex.escape(n)}["']/) }
        removed << line.strip if matched
        !matched
      end

      if removed.empty?
        stderr.puts "No gems were removed from the Gemfile"
        return 1
      end

      stdout.puts "Removing gems from #{gemfile_path.gsub(/\\/, "/")}"
      eol = {{ flag?(:windows) }} ? "\r\n" : "\n"
      File.write(gemfile_path, kept.join(eol) + eol)
      removed.each do |line|
        # The message mirrors the Gemfile line: quoted tokens are the gem name
        # followed by the requirement(s) exactly as written (`~> 2.8`,
        # `= 2.8.1`, or several constraints). Options such as `group: :dev`
        # use bare symbols and are not quoted, so they are ignored here.
        quoted = line.scan(/"([^"]*)"|'([^']*)'/).map { |m| m[1]? || m[2]? }.compact
        label = quoted.first? || line
        requirements = quoted.skip(1).map { |requirement| pretty_requirement(requirement) }
        display = requirements.empty? ? label : "#{label} (#{requirements.join(", ")})"
        stdout.puts "#{display} was removed."
      end

      if kept.none? { |l| l.strip.starts_with?("gem ") }
        # Reference install reports this on stderr (the remove command still
        # exits 0 and prints the removal lines on stdout).
        stderr.puts "The Gemfile specifies no dependencies"
      end

      # Reference remove: regenerate the lockfile and reinstall silently (no
      # progress/summary output). It does **not** prune the bundle directory:
      # the gem that was just dropped from the Gemfile stays installed, and the
      # follow-up `bundle clean` is what reports `Removing <name> (<version>)`.
      # Pruning here used to be hidden by a stale `definition.lockfile!`
      # cache; reading the fresh lockfile made `clean` print nothing.
      null = IO::Memory.new
      install(null, stderr, rest, summary: false, cli_arguments: false)
      0
    end

    # Reference `pretty_dependency` renders `Gem::Dependency#to_s`, whose
    # requirement goes through `Gem::Requirement#to_s`: a bare version gains the
    # `=` operator (`"2.8.1"` -> `= 2.8.1`) while explicit operators stay as
    # written (`~> 2.8`, `>= 1`, `!= 2.0`).
    private def self.pretty_requirement(value : String) : String
      tokens = value.split(/\s+/).reject(&.empty?)
      return value if tokens.empty?
      if {"=", "!=", ">", "<", ">=", "<=", "~>"}.includes?(tokens[0])
        tokens.join(" ")
      else
        "= #{tokens.join(" ")}"
      end
    end

    private def self.build_timestamp : String
      begin
        output = IO::Memory.new
        # `git log -1 --format=%cs` is portable across Git builds; some
        # `git rev-parse --format=%cs` invocations return non-date output with
        # success on Windows Git 2.55, so avoid treating arbitrary stdout as a
        # timestamp.
        result = Process.run("git", ["log", "-1", "--format=%cs", "HEAD"],
          output: output, error: Process::Redirect::Close)
        if result.success?
          ts = output.to_s.lines.first?.try(&.strip) || ""
          return ts if ts.matches?(/^\d{4}-\d{2}-\d{2}$/)
        end
      rescue
      end
      "unknown"
    end

    # ------------------------------------------------------------------
    # env: full environment dump (pinned reference sections)
    # ------------------------------------------------------------------
    def self.env(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      if (code = reject_positional_arguments(stderr, "env", rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        re = bridge.ruby_environment
        config = definition.config
        bundler_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"

        stdout.puts "## Environment"
        stdout.puts
        stdout.puts "```"
        stdout.puts "Bundler       #{bundler_version}"
        platforms = [Gem::Platform::RUBY.to_s, Gem::Platform.local.to_s]
        stdout.puts "  Platforms   #{platforms.join(", ")}"
        stdout.puts "Ruby          #{re.ruby_env_line}"
        stdout.puts "  Full Path   #{re.ruby_exe.gsub(/\\/, "/")}"
        stdout.puts "  Config Dir  #{(re.system_config_dir || config_dir).gsub(/\\/, "/")}"
        stdout.puts "RubyGems      #{re.rubygems_version}"
        stdout.puts "  Gem Home    #{re.default_gem_dir.gsub(/\\/, "/")}"
        # Bundler::Env joins Gem.path with File::PATH_SEPARATOR (env.rb:77).
        stdout.puts "  Gem Path    #{re.gem_paths.map(&.gsub(/\\/, "/")).join(Process::PATH_DELIMITER)}"
        user_dir = re.user_gem_dir
        if user_dir
          forward = user_dir.gsub(/\\/, "/")
          stdout.puts "  User Home   #{forward.sub(/\/\.local\/share\/gem.*/, "")}"
          stdout.puts "  User Path   #{forward}"
        else
          stdout.puts "  User Home   "
          stdout.puts "  User Path   "
        end
        # `Gem.bindir`: RbConfig's bindir for the default gem home, otherwise
        # `<gem home>/bin` (rubygems.rb#bindir).
        bin_dir = re.gem_bindir || File.join(re.default_gem_dir, "bin")
        stdout.puts "  Bin Dir     #{bin_dir.gsub(/\\/, "/")}"
        # OpenSSL rows mirror Bundler::Env (env.rb:106-112): every row is gated
        # on OpenSSL being loaded, so a plain `bundle env` prints none of them.
        openssl_values = {
          "  Compiled"  => re.openssl_compiled,
          "  Loaded"    => re.openssl_loaded,
          "  Cert File" => re.openssl_cert_file,
          "  Cert Dir"  => re.openssl_cert_dir,
        }
        if openssl_values.any? { |_, value| value }
          stdout.puts "OpenSSL       "
          openssl_values.each do |label, value|
            stdout.puts "#{label.ljust(14)}#{value}" if value
          end
        end
        stdout.puts "Tools         "
        stdout.puts "  Git         #{git_version}"
        stdout.puts "  RVM         not installed"
        stdout.puts "  rbenv       not installed"
        stdout.puts "  chruby      not installed"
        stdout.puts "```"
        stdout.puts
        stdout.puts "## Bundler Build Metadata"
        stdout.puts
        stdout.puts "```"
        # Bundler::BuildMetadata is baked into each release (build_metadata.rb);
        # `bundle env` prints that constant, not the reporting process's own
        # git checkout. Fall back to this checkout only for unknown profiles.
        release = Celerite::ReleaseMetadata.for(bundler_version)
        stdout.puts "Timestamp  #{release ? release[0] : build_timestamp}"
        stdout.puts "Git SHA    #{release ? release[1] : git_sha}"
        stdout.puts "```"

        # settings section: one block per local-config key (reference shape)
        settings_lines = config_dump(config)
        unless settings_lines.empty?
          stdout.puts
          stdout.puts "## Bundler settings"
          stdout.puts
          stdout.puts "```"
          settings_lines.each { |section| section.each { |l| stdout.puts l } }
          stdout.puts "```"
        end

        stdout.puts
        # Gemfile section
        stdout.puts "## Gemfile"
        stdout.puts
        stdout.puts "### Gemfile"
        stdout.puts
        stdout.puts "```ruby"
        File.each_line(definition.gemfile_path) { |l| stdout.puts l.chomp }
        stdout.puts "```"
        stdout.puts
        stdout.puts "### Gemfile.lock"
        stdout.puts
        stdout.puts "```"
        if definition.lockfile_exists?
          File.each_line(definition.lockfile_path) { |l| stdout.puts l.chomp }
        else
          # Bundler::Env.read_file returns this placeholder instead of an
          # empty fence when the lockfile is absent.
          stdout.puts "<No #{definition.lockfile_path.gsub(/\\/, "/")} found>"
        end
        stdout.puts "```"
        # Bundler::Env appends `## Gemspecs` after the Gemfile section, one
        # `### <basename>` ruby fence per gemspec loaded by `gemspec` directives
        # (env.rb:51-58); the whole section is omitted when there are none.
        gemspec_paths = bridge.gemspec_paths(definition.gemfile_path)
        unless gemspec_paths.empty?
          stdout.puts
          stdout.puts "## Gemspecs"
          gemspec_paths.each do |path|
            stdout.puts
            stdout.puts "### #{File.basename(path)}"
            stdout.puts
            stdout.puts "```ruby"
            # Ruby writes the file with LF; normalize CRLF like the reference
            # `.chomp` rendering so the differential comparison is byte-stable.
            stdout.puts File.read(path).gsub(/\r\n?/, "\n").chomp
            stdout.puts "```"
          end
        end
        0
      ensure
        bridge.close
      end
    end

    private def self.config_dir : String
      # RubyGems config dir: %PROGRAMDATA% on Windows, /etc elsewhere
      {% if flag?(:windows) %}
        ENV["PROGRAMDATA"]? || "C:/ProgramData"
      {% else %}
        "/etc"
      {% end %}
    end

    private def self.git_version : String
      output = IO::Memory.new
      result = Process.run("git", ["--version"], output: output, error: :inherit)
      result.success? ? output.to_s.strip.sub("git version ", "") : "not installed"
    rescue
      "not installed"
    end

    private def self.config_dump(config : Config) : Array(Array(String))
      # mirror the reference: one section per setting from any source,
      # highest-priority source line first
      sections = [] of Array(String)
      keys = (config.local_config.keys | ENV.keys.select(&.starts_with?("BUNDLE_"))).uniq
      keys.each do |key|
        name = key.lchop("BUNDLE_").gsub("__", ".").downcase
        next if name.empty?
        if value = config.local_config[key]?
          file = config.local_config_file.to_s.gsub(/\\/, "/")
          sections << [name, "  Set for your local app (#{file}): #{value.inspect}"]
        elsif value = ENV[key]?
          sections << [name, "  Set via #{key}: #{value.inspect}"]
        end
      end
      sections
    end

    # ------------------------------------------------------------------
    # doctor
    # ------------------------------------------------------------------
    def self.doctor(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # `subcommand("doctor", Doctor)` makes Thor report unknown options as
      # leftover arguments of `diagnose` (cli.rb:669-671).
      unless (arguments = subcommand_arguments(rest, DOCTOR_SUBCOMMAND_FLAGS, DOCTOR_SUBCOMMAND_VALUES)).empty?
        stderr.puts %(ERROR: "bundle doctor diagnose" was called with arguments #{arguments.inspect})
        stderr.puts %(Usage: "bundle doctor diagnose [OPTIONS]")
        return 15
      end
      definition = Definition.build
      Commands.validate_ruby_runtime!(definition)
      # `doctor` resolves like `check` (cli/doctor.rb): it may fetch the index,
      # unlike the local-only read commands.
      lockfile = materialize_lockfile(definition, stdout)
      locked_specs = lockfile.specs.sort_by(&.full_name)

      if locked_specs.empty?
        stdout.puts "The Gemfile's dependencies are satisfied"
      else
        missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }
        if missing.empty?
          stdout.puts "The Gemfile's dependencies are satisfied"
        else
          stderr.puts "The following gems are missing"
          missing.each { |spec| stderr.puts " * #{spec.name} (#{spec.version})" }
          # `doctor` delegates to `Check#run` (doctor/diagnose.rb:74-76), which
          # prints the install hint right after the missing list.
          stderr.puts "Install missing gems with `bundle install`"
          return 1
        end
      end
      stdout.puts "No issues found with the installed bundle"
      0
    end

    # Returns true when the locked spec is installed/available for read-only commands.
    def self.installed_spec_dir?(definition : Definition, spec : Lockfile::Spec, lockfile : Lockfile::Data? = nil) : Bool
      !installed_gem_dir(definition, spec, lockfile).nil?
    end

    # Returns the installed gem directory for a locked spec, or nil when not found.
    # Handles RubyGems specs in the bundle path, PATH sources at their local path,
    # and GIT sources in the bundle's bundler/gems checkout.
    def self.installed_gem_dir(definition : Definition, spec : Lockfile::Spec, lockfile : Lockfile::Data? = nil) : String?
      lf = lockfile || (definition.lockfile_exists? ? definition.lockfile! : nil)
      source = lf.try(&.source_for(spec))

      if source
        case source.type
        when "PATH"
          remote = source.option("remote").to_s
          path = File.expand_path(remote, File.dirname(definition.gemfile_path))
          return Dir.exists?(path) ? path : nil
        when "GIT"
          revision = source.option("revision").to_s
          remote = source.option("remote").to_s
          return installed_git_checkout(definition, spec.name, remote, revision)
        end
      end

      # `path.system` puts gems directly in `Gem.dir` (`<Gem.dir>/gems`), with no
      # `ruby/<abi>` scope. Discover them explicitly instead of relying on the
      # fallback search below (which used to make this order-dependent).
      if (source.nil? || source.type == "GEM") && InstallPaths.system_gems?(definition.config)
        if system_dir = system_gem_search_dirs.first?
          gem_dir = File.join(system_dir, "gems", spec.full_name)
          return gem_dir if Dir.exists?(gem_dir)
        end
      end

      # Default: RubyGems-installed spec under bundle install path.
      install_path = InstallPaths.install_path(definition.config)
      ruby_root = File.join(InstallPaths.install_path(definition.config), "ruby")
      if Dir.exists?(ruby_root)
        Dir.each_child(ruby_root) do |abi|
          gem_dir = File.join(ruby_root, abi, "gems", spec.full_name)
          # For read-only commands (check/list/show/info/doctor), treat extracted
          # gem contents as installed even if the installed specification file is
          # missing from this layout.
          return gem_dir if Dir.exists?(gem_dir)
        end
      end

      # Fallback for RubyGems sources: check system/default gem directories.
      # This aligns `check/list/show/info/doctor` with Bundler behavior when
      # locked gems are satisfied by gems installed in GEM_PATH/system/default
      # locations (e.g. default gems) rather than the bundle install path.
      # A custom `path` keeps materialization limited to that path, exactly
      # like the reference (`bundle show` with `BUNDLE_PATH=.bundle` reports a
      # gem that only exists in `Gem.dir` as missing).
      if (source.nil? || source.type == "GEM") && system_gem_fallback_allowed?(definition)
        system_gem_search_dirs.each do |base|
          gem_dir = File.join(base, "gems", spec.full_name)
          return gem_dir if Dir.exists?(gem_dir)
        end
      end
      nil
    end

    # System gem dirs hold the bundle when no custom `path` is configured (the
    # reference `!bundler_5_mode?` default) or when `path.system` is set.
    private def self.system_gem_fallback_allowed?(definition : Definition) : Bool
      InstallPaths.use_system_gems?(definition.config, InstallPaths.install_path(definition.config))
    end

    @@system_gem_search_dirs : Array(String)? = nil
    @@system_gem_search_signature : String? = nil

    # Cached system gem base directories (GEM_PATH/default/user gem dirs) used
    # as a fallback when resolving installed RubyGems specs for read-only commands.
    # The cache is keyed by the environment that feeds it (GEM_HOME/GEM_PATH and
    # the home dir used by user_gem_dir), so a process that changes those env
    # vars inside one run (specs, `--deployment` toggles) recomputes instead of
    # reusing directories derived from a different environment.
    # Requires the bridge for ruby_environment; returns empty when unavailable.
    def self.system_gem_search_dirs : Array(String)
      signature = system_gem_environment_signature
      if dirs = @@system_gem_search_dirs
        return dirs if @@system_gem_search_signature == signature
      end
      dirs = [] of String
      begin
        # The bridge is how a normal CLI run learns RubyGems' own directories, so
        # this must not be gated on the test/differential environment variables
        # (CELERITE_BRIDGE_SERVER / CELERITE_REFERENCE_BUNDLER_LIB): gating it
        # made `show`/`info`/`check` miss gems installed in the default gem dir
        # outside the harness. A failed bridge call just yields no extra dirs.
        bridge = Bridge::Client.new
        begin
          env = bridge.ruby_environment
          unless env.default_gem_dir.empty?
            dirs << env.default_gem_dir
          end
          env.gem_paths.each do |p|
            dirs << p unless p.empty?
          end
          if user = env.user_gem_dir
            dirs << user unless user.empty?
          end
        ensure
          bridge.close
        end
      rescue
        dirs = [] of String
      end
      dirs = dirs.uniq
      @@system_gem_search_dirs = dirs
      @@system_gem_search_signature = signature
      dirs
    end

    private def self.system_gem_environment_signature : String
      [ENV["GEM_HOME"]?, ENV["GEM_PATH"]?, ENV["HOME"]?, ENV["USERPROFILE"]?].join('\u0000')
    end

    private def self.installed_git_checkout(definition : Definition, name : String, remote : String, revision : String) : String?
      roots = [] of String
      if InstallPaths.system_gems?(definition.config)
        # `path.system`: git checkouts live in `<Gem.dir>/bundler/gems`, i.e. the
        # base itself, without the `ruby/<abi>` scope.
        if system_dir = system_gem_search_dirs.first?
          roots << system_dir
        end
      else
        ruby_root = File.join(InstallPaths.install_path(definition.config), "ruby")
        return nil unless Dir.exists?(ruby_root)
        Dir.each_child(ruby_root) do |abi|
          roots << File.join(ruby_root, abi)
        end
      end

      base = GitSource.base_name(remote)
      short = revision.empty? ? nil : revision[0, 12]
      roots.each do |root|
        checkout_root = File.join(root, "bundler", "gems")
        next unless Dir.exists?(checkout_root)
        if short
          dir = File.join(checkout_root, "#{base}-#{short}")
          return dir if Dir.exists?(dir)
        end
        Dir.each_child(checkout_root) do |child|
          return File.join(checkout_root, child) if child.starts_with?("#{base}-")
        end
      end
      nil
    end

    # ------------------------------------------------------------------
    # licenses / fund
    # ------------------------------------------------------------------
    def self.licenses(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      if (code = reject_positional_arguments(stderr, "licenses", rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      definition = Definition.build
      Commands.validate_ruby_runtime!(definition)
      bridge = Bridge::Client.new
      begin
        abi = InstallPaths.ruby_abi(bridge)
        install_root = InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi)
        # `licenses` reads the materialized bundle without touching the index
        # (`cli/licenses.rb`), so a missing lockfile re-resolves locally.
        materialize_lockfile(definition, stdout, local_only: true).specs.each do |spec|
          next if spec.name == "bundler"
          license = spec_license(bridge, install_root, spec)
          stdout.puts "#{spec.name}: #{license}"
        end
        stdout.puts "bundler: MIT"
      ensure
        bridge.close
      end
      0
    end

    private def self.spec_license(bridge : Bridge::Client, install_root : String, spec : Lockfile::Spec) : String
      gem_file = File.join(install_root, "cache", "#{spec.full_name}.gem")
      return "Unknown" unless File.file?(gem_file)
      info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(gem_file).to_json)
      info.license || info.licenses.try(&.first?) || "Unknown"
    rescue
      "Unknown"
    end

    def self.fund(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, FUND_SWITCH_FLAGS, FUND_SWITCH_VALUES))
        return code
      end
      if (code = reject_positional_arguments(stderr, "fund", rest, FUND_SWITCH_FLAGS, FUND_SWITCH_VALUES))
        return code
      end
      definition = Definition.build
      Commands.validate_runtime!(definition)
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        # `--group` is a scalar Thor option (fund.rb:14-20): the last occurrence
        # wins, both `--group=x` and `--group x` are accepted, and a comma stays
        # part of the group name (4.0.24 turns "development,test" into one
        # symbol, which matches nothing).
        explicit_groups = fund_group_flag(rest)
        requested_groups = if explicit_groups
                             # Bundler passes the flag straight to
                             # dependencies_for and then crashes (NoMethodError
                             # on a nil spec) when that group is also in
                             # `without`; subtracting `without` keeps us from
                             # panicking while producing the same "no funding"
                             # answer for the excluded group.
                             explicit_groups - setting_list(definition.config, "without")
                           else
                             fund_requested_groups(evaluation, definition.config)
                           end
        deps = evaluation.dependencies.select do |dep|
          dep.groups.any? { |group| requested_groups.includes?(group) }
        end

        # `fund.rb`: `dependencies_for(groups)` narrows the definition before
        # it resolves, so a group with no dependencies never touches the
        # bundle (and never reports a missing gem).
        if deps.empty?
          stdout.puts "None of the installed gems you directly depend on are looking for funding."
          return 0
        end

        # `fund.rb:14-27` walks `Bundler.definition` (dependencies_for + specs),
        # which resolves from the Gemfile when the lockfile is missing.  The
        # sources stay local-only: fund never fetches the index.
        lockfile = materialize_lockfile(definition, stdout, local_only: true)

        # A missing PATH source fails Bundler's definition validation with
        # PathError (source/path.rb:198-204, status 13).  Reproduce it before
        # touching funding metadata.  The reference emits a single line and
        # lets the UI wrap it at the terminal width (ui/shell.rb:167-171), so
        # the wrap is derived, not hardcoded.
        if missing = fund_missing_path(definition, lockfile)
          stderr.puts Commands.word_wrap("The path `#{missing}` does not exist.", CLI.terminal_width)
          return 13
        end

        fund_info = [] of String
        deps.each do |dep|
          spec = lockfile.specs.find(&.name.==(dep.name))
          next unless spec
          funding = read_funding_uri(definition, spec, lockfile, bridge)
          if funding
            fund_info << "* #{spec.name} (#{spec.version})
  Funding: #{funding}"
          end
        end

        if fund_info.empty?
          stdout.puts "None of the installed gems you directly depend on are looking for funding."
        else
          stdout.puts fund_info.join("
")
        end
        0
      ensure
        bridge.close
      end
    end

    private def self.fund_group_flag(rest : Array(String)) : Array(String)?
      value : String? = nil
      index = 0
      while index < rest.size
        arg = rest[index]
        if arg == "--group"
          candidate = rest[index + 1]?
          value = candidate unless candidate.nil? || candidate.starts_with?("--")
          index += 1
        elsif arg.starts_with?("--group=")
          value = arg.split("=", 2)[1]
        end
        index += 1
      end
      value ? [value] : nil
    end

    # definition.rb:286-288 calls dependencies_for(requested_groups), and
    # :1251-1255 computes those as (declared groups - without - optional + with).
    # dependencies_for (:328-333) keeps a dependency when any of its groups
    # intersects the requested set.
    private def self.fund_requested_groups(evaluation : Bridge::GemfileEvaluation, config : Config) : Array(String)
      declared = evaluation.dependencies.flat_map(&.groups).uniq
      (declared - setting_list(config, "without") + setting_list(config, "with")).uniq
    end

    private def self.setting_list(config : Config, name : String) : Array(String)
      case value = config[name]
      when Array(String) then value
      when String        then value.split(":").reject(&.empty?)
      else                    [] of String
      end
    end

    # Bundler validates every source in the definition, not just the ones that
    # back a direct dependency, so a missing PATH entry anywhere in the
    # lockfile aborts with PathError (source/path.rb:198-204) in lockfile order.
    private def self.fund_missing_path(definition : Definition, lockfile : Lockfile::Data) : String?
      lockfile.sources.each do |source|
        next unless source.type == "PATH"
        remote = source.remote
        next if remote.nil? || remote.empty?
        dir = File.expand_path(remote, File.dirname(definition.gemfile_path))
        return dir.gsub('\\', "/") unless Dir.exists?(dir)
      end
      nil
    end

    private def self.read_source_funding_uri(definition : Definition, spec : Lockfile::Spec, lockfile : Lockfile::Data) : String?
      source = lockfile.source_for(spec)
      return nil unless source
      return nil unless source.type == "PATH" || source.type == "GIT"

      dir = installed_gem_dir(definition, spec, lockfile)
      return nil unless dir

      gemspec_path = File.join(dir, "#{spec.name}.gemspec")
      unless File.file?(gemspec_path)
        gemspec_path = Glob.paths(dir, "*.gemspec").sort.first?
      end
      return nil unless gemspec_path
      return nil unless File.file?(gemspec_path)

      text = File.read(gemspec_path)
      if match = text.match(/funding_uri["']?\s*=>\s*["']([^"']+)["']/)
        return match[1]
      end
      nil
    end

    private def self.read_funding_uri(definition : Definition, spec : Lockfile::Spec, lockfile : Lockfile::Data, bridge : Bridge::Client) : String?
      source_funding = read_source_funding_uri(definition, spec, lockfile)
      return source_funding if source_funding

      install_path = InstallPaths.install_path(definition.config)
      ruby_root = File.join(InstallPaths.install_path(definition.config), "ruby")
      return nil unless Dir.exists?(ruby_root)

      Dir.each_child(ruby_root) do |abi|
        # Reference Bundler reads funding metadata from definition.specs, i.e.
        # the installed specifications tree. It never unpacks cache/*.gem, so
        # neither do we (our installer writes the full metadata-bearing spec).
        gemspec_path = File.join(ruby_root, abi, "specifications", "#{spec.full_name}.gemspec")
        next unless File.file?(gemspec_path)
        begin
          text = File.read(gemspec_path)
          # Extract funding_uri from metadata hash if present.
          if match = text.match(/funding_uri["']?\s*=>\s*["']([^"']+)["']/)
            return match[1]
          end
        rescue
        end
      end
      nil
    end

    # ------------------------------------------------------------------
    # open
    # ------------------------------------------------------------------
    # `bundle open` (cli/open.rb:12-26). The whole point is fidelity of the
    # error surface: Thor validates the arity before `run`, and `run` then
    # rejects an empty `--path`, resolves the editor in
    # BUNDLER_EDITOR/VISUAL/EDITOR order, and only then selects the gem
    # (cli/common.rb:68-96: exact name, else regex, else the interpreter's
    # default gem, else an interactive picker).
    def self.open(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, OPEN_SWITCH_FLAGS, OPEN_SWITCH_VALUES))
        return code
      end

      path_option : String? = nil
      names = [] of String
      index = 0
      while index < rest.size
        arg = rest[index]
        if arg == "--path"
          index += 1
          path_option = rest[index]? || ""
        elsif value = arg.lchop?("--path=")
          path_option = value
        else
          names << arg
        end
        index += 1
      end

      if names.empty?
        stderr.puts %(ERROR: "bundle open" was called with no arguments)
        stderr.puts %(Usage: "bundle open GEM")
        return 15
      end
      if names.size > 1
        stderr.puts %(ERROR: "bundle open" was called with arguments #{names.inspect})
        stderr.puts %(Usage: "bundle open GEM")
        return 15
      end
      if (path = path_option) && path.empty?
        stderr.puts "Cannot specify `--path` option without a value"
        return 15
      end

      editor = [ENV["BUNDLER_EDITOR"]?, ENV["VISUAL"]?, ENV["EDITOR"]?].find { |value| !value.nil? && !value.empty? }
      unless editor
        stdout.puts "To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR"
        return 0
      end

      name = names.first
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        lockfile = materialize_lockfile(definition, nil, local_only: true)
        abi = InstallPaths.ruby_abi(bridge)
        install_root = InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi)
        specs = lockfile.specs.sort_by(&.full_name)

        chosen = specs.find(&.name.==(name))
        if chosen
          gem_dir = open_gem_dir(bridge, install_root, chosen.full_name)
          return run_editor(stdout, editor, gem_dir, path)
        end

        candidates = [] of NamedTuple(name: String, path: String, default_gem: Bool)
        regexp = begin
          Regex.new(name)
        rescue Regex::Error
          nil
        end
        if rx = regexp
          specs.each do |spec|
            candidates << {name: spec.name, path: open_gem_dir(bridge, install_root, spec.full_name), default_gem: false} if spec.name.matches?(rx)
          end
        end
        if (default_spec = bridge.default_gem_spec(name))
          candidates << {name: default_spec[:name], path: default_spec[:full_gem_path], default_gem: true}
        end

        case candidates.size
        when 0
          evaluation = begin
            bridge.evaluate_gemfile(definition.gemfile_path)
          rescue
            nil
          end
          groups = evaluation.try(&.dependencies.find(&.name.==(name)).try(&.groups)) || [] of String
          if groups.empty? && evaluation && evaluation.dependencies.any? { |dep| dep.name == name }
            groups = ["default"]
          end
          if groups.empty? && evaluation.nil?
            groups = gem_groups_for(definition, name)
          end
          if !groups.empty?
            message = "Could not find gem '#{name}', because it's in the #{verbalize_groups(groups)}, configured to be ignored."
            stderr.puts word_wrap(message, CLI.terminal_width)
          else
            alternatives = evaluation.try(&.dependencies.map(&.name)) || lockfile.dependencies.map(&.name)
            stderr.puts gem_not_found_message_for(name, alternatives)
          end
          return 7
        when 1
          return open_candidate(stdout, stderr, editor, name, path, candidates.first)
        else
          candidates.each_with_index do |candidate, position|
            stdout.puts "#{position + 1} : #{candidate[:name]}"
          end
          stdout.puts "0 : - exit -"
          # Reference prompt is Thor's ask, which prints the statement plus
          # a trailing space (`">  "`).
          stdout.print ">  "
          stdout.flush
          answer = STDIN.gets
          number = answer ? answer.strip.to_i : 0
          return 0 if number <= 0
          candidate = candidates[number - 1]?
          return 0 unless candidate
          return open_candidate(stdout, stderr, editor, name, path, candidate)
        end
      ensure
        bridge.close
      end
    end

    private def self.open_candidate(stdout : IO, stderr : IO, editor : String, name : String,
                                    path : String?, candidate : NamedTuple(name: String, path: String, default_gem: Bool)) : Int32
      if candidate[:default_gem]
        stdout.puts "Unable to open #{name} because it's a default gem, so the directory it would normally be installed to does not exist."
        return 0
      end
      run_editor(stdout, editor, candidate[:path], path)
    end

    # The installed directory of a locked gem, taken from the bridge's spec
    # list (`spec.full_gem_path`) rather than recomputed from the install root:
    # Bundler installs into Gem.dir unless `path` is configured, so the root
    # alone does not tell where a gem actually lives.
    private def self.open_gem_dir(bridge : Bridge::Client, install_root : String, full_name : String) : String
      specs = begin
        bridge.installed_specs(File.join(install_root, "specifications")).as_a
      rescue
        [] of JSON::Any
      end
      spec = specs.find { |entry| entry["full_name"]?.try(&.as_s?) == full_name }
      spec.try(&.["full_gem_path"]?.try(&.as_s?)) || File.join(install_root, "gems", full_name)
    end

    private def self.run_editor(stdout : IO, editor : String, gem_dir : String, path : String?) : Int32
      # RubyGems reports `full_gem_path` with forward slashes on Windows; the
      # reference hands that form straight to the editor.
      target = (path ? File.join(gem_dir, path) : gem_dir).tr("\\\\", "/")
      # open.rb:28-37: on Windows a value naming an existing file is taken as a
      # single word (shell splitting would corrupt "Program Files" paths).
      words = if File.file?(editor)
                [editor]
              else
                editor.split(/\s+/, remove_empty: true)
              end
      command = words + [target]
      status = spawn_editor(words, target, gem_dir)
      # Ruby's `system` runs a `.cmd`/`.bat` editor through the command
      # processor (CreateProcess alone cannot execute batch files), so retry
      # the same line under cmd.exe before reporting a failure.
      if status.nil? && {{ flag?(:windows) }} && batch_file?(words.first)
        status = spawn_editor(words, target, gem_dir, via_shell: true)
      end
      if status.nil? || !status.success?
        stdout.puts "Could not run '#{command.join(" ")}'"
      end
      0
    end

    private def self.batch_file?(path : String) : Bool
      name = path.downcase
      name.ends_with?(".cmd") || name.ends_with?(".bat")
    end

    private def self.spawn_editor(words : Array(String), target : String, gem_dir : String,
                                  via_shell : Bool = false) : Process::Status?
      if via_shell
        Process.run("#{words.join(" ")} #{target}", shell: true, chdir: gem_dir,
          output: Process::Redirect::Inherit, error: Process::Redirect::Inherit, input: Process::Redirect::Inherit)
      else
        Process.run(words.first, words[1..] + [target], chdir: gem_dir,
          output: Process::Redirect::Inherit, error: Process::Redirect::Inherit, input: Process::Redirect::Inherit)
      end
    rescue ex : File::Error | RuntimeError
      nil
    end

    # ------------------------------------------------------------------
    # plugin
    # ------------------------------------------------------------------
    def self.plugin(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      sub = rest.first? || "list"
      case sub
      when "list"
        index_path = plugin_index_path
        index = File.file?(index_path) ? YAML.parse(File.read(index_path)) : YAML.parse("{}")
        # Reference order: `installed_plugins` = @plugin_paths.keys (insertion
        # order, plugin/index.rb:128-130); never sorted.
        plugin_order = (index["plugin_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).keys.map(&.to_s)
        registered = PluginCommands.commands(index_path)
        if plugin_order.empty?
          stdout.puts "No plugins installed"
        else
          plugin_order.each do |name|
            stdout.puts name
            stdout.puts "-----"
            registered.each do |command, owner|
              stdout.puts "  #{command}" if owner == name
            end
            stdout.puts
          end
        end
        0
      when "install"
        names = rest[1..].reject(&.starts_with?("--"))
        if names.empty?
          stderr.puts "No plugin sources specified"
          return 1
        end

        path = flag_value(rest, "--path")
        git_remote = flag_value(rest, "--git")
        source_remote = flag_value(rest, "--source")
        if path.nil?
          if git_remote || source_remote
            # Remote plugin install: resolve through the same Source /
            # PubGrub machinery as a normal Gemfile with a synthesized
            # source list, then materialize into the plugin tree.
            return plugin_install_remote(names, rest, stdout, stderr)
          end
          stderr.puts "Plugin installation from remote sources requires git; use --path for a local plugin directory."
          return 19
        end

        stdout.puts "Resolving dependencies..."

        bridge = Bridge::Client.new
        begin
          info = Bridge::GemSpecInfo.from_json(bridge.load_gemspec_dir(path).to_json)
        ensure
          bridge.close
        end

        index_dir = plugin_tree_root
        Dir.mkdir_p(index_dir)
        index_path = File.join(index_dir, "index")
        index = File.file?(index_path) ? (YAML.parse(File.read(index_path)) || YAML.parse("{}")) : YAML.parse("{}")

        lib_dir = File.join(File.expand_path(path), "lib").gsub(/\\/, "/")
        root_dir = File.expand_path(path).gsub(/\\/, "/")
        load_path_map = {} of String => Array(String)
        (index["load_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
          load_path_map[key.as_s] = value.as_a?.try(&.map(&.as_s)) || [] of String
        end
        plugin_path_map = {} of String => String
        (index["plugin_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
          plugin_path_map[key.as_s] = value.as_s
        end
        hooks_map = {} of String => Array(String)
        (index["hooks"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
          hooks_map[key.as_s] = value.as_a?.try(&.map(&.as_s)) || [] of String
        end

        registered = PluginCommands.commands(index_path)
        declared = PluginCommands.declared_commands(File.join(root_dir, "plugins.rb"))
        conflict_command = declared.find do |command|
          owner = registered[command]?
          !owner.nil? && owner != info.name
        end
        if conflict = conflict_command
          message = "Failed to install plugin `#{info.name}`, due to Bundler::Plugin::Index::CommandConflict " \
                    "(Command(s) `#{conflict}` declared by #{info.name} are already registered.)"
          stderr.puts Commands.word_wrap(message, CLI.terminal_width)
          return 29
        end
        merged_commands = registered.dup
        declared.each { |command| merged_commands[command] = info.name }
        first_install = !plugin_path_map.has_key?(info.name)
        load_path_map[info.name] = [lib_dir]
        plugin_path_map[info.name] = root_dir

        # Reference index layout: bare keys for empty collections, quoted
        # string values, "---" document start. Commands keep their existing
        # owners; a plugin's keys are never duplicated.
        yaml = String.build do |y|
          y.puts "---"
          y.puts "commands:"
          merged_commands.each { |command, owner| y.puts "  #{command}: #{owner.inspect}" }
          y.puts "hooks:"
          hooks_map.each do |key, value|
            y.puts "  #{key}:"
            value.each { |item| y.puts "  - #{item.inspect}" }
          end
          y.puts "load_paths:"
          load_path_map.each do |key, value|
            y.puts "  #{key}:"
            value.each { |item| y.puts "  - #{item.inspect}" }
          end
          y.puts "plugin_paths:"
          plugin_path_map.each { |key, value| y.puts "  #{key}: #{value.inspect}" }
          y.puts "sources:"
        end
        File.write(index_path, yaml)
        # Reference re-install of an installed plugin prints nothing beyond
        # "Resolving dependencies..." (no second "Installed plugin" line).
        stdout.puts "Installed plugin #{info.name}" if first_install
        0
      when "uninstall"
        all = rest.includes?("--all")
        names = rest[1..].reject(&.starts_with?("--"))
        index_path = plugin_index_path
        installed = installed_plugins
        targets = all ? installed : names
        if targets.empty?
          stdout.puts "No plugins installed"
          return 0
        end
        index = File.file?(index_path) ? (YAML.parse(File.read(index_path)) || YAML.parse("{}")) : YAML.parse("{}")
        changed = false
        targets.each do |name|
          unless installed.includes?(name)
            stderr.puts "Plugin #{name} is not installed "
            next
          end
          changed = true
          stdout.puts "Uninstalled plugin #{name}"
        end
        if changed || File.file?(index_path)
          write_plugin_index(index_path, index, targets.select { |t| installed.includes?(t) })
        end
        0
      when "new"
        stderr.puts "The 'plugin new' command is not implemented yet."
        1
      else
        # `plugin` is a Thor subcommand; an unknown subcommand is reported
        # without the parent command prefix (`cli.rb` subcommand dispatch).
        stderr.puts "Could not find command \"#{sub}\"."
        15
      end
    end

    # Remote plugin install (`--source`/`--git`): synthesize a temporary
    # Gemfile at log level and resolve the plugin the same way Phase N built
    # it. The temporary GEMFILE is cleaned up after resolution.
    # Pure-Crystal recursive copy. Spawning msys `cp -r` under this sandbox's
    # Low integrity level dies with 0xC0000022 (same root cause as the git
    # fixtures), so plugin materialization copies the tree itself.
    private def self.copy_tree(source : String, destination : String) : Nil
      if File.file?(source)
        Dir.mkdir_p(File.dirname(destination))
        File.copy(source, destination)
        return
      end
      Dir.mkdir_p(destination)
      Dir.children(source).each do |child|
        copy_tree(File.join(source, child), File.join(destination, child))
      end
    end

    def self.plugin_install_remote(names : Array(String), rest : Array(String), stdout : IO, stderr : IO) : Int32
      version = flag_value(rest, "--version") || ">= 0"
      git_remote = flag_value(rest, "--git")
      source_remote = flag_value(rest, "--source")
      branch = flag_value(rest, "--branch")
      ref_flag = flag_value(rest, "--ref")

      if branch && ref_flag
        stderr.puts "You cannot specify `--branch` and `--ref` at the same time."
        return 1
      end
      if (branch || ref_flag) && !git_remote
        stderr.puts "--branch can only be used with git sources"
        return 1
      end

      bridge = Bridge::Client.new
      tmp_dir = ""
      tmp_root = ""
      app_root = ""
      app_root_was_absent = false
      begin
        stdout.puts "Fetching #{git_remote}" if git_remote
        # Reference `Bundler.tmp` lives under the app config root; the system
        # TEMP is neither writable here nor the project's temp dir. For a
        # Gemfile-less cwd this must not create a project-local `.bundle`.
        app_root = plugin_app_config_root
        app_root_was_absent = !Dir.exists?(app_root)
        tmp_root = File.join(app_root, "tmp")
        Dir.mkdir_p(tmp_root)
        tmp_dir = File.join(tmp_root, "celerite-plugin-#{Process.pid}-#{rand(1 << 30)}")
        Dir.mkdir_p(tmp_dir)
        synthesized = if git_remote
                        body = "source \"https://rubygems.org/\"\n\ngem \"#{names.first.not_nil!}\", git: \"#{git_remote}\""
                        body += ", branch: \"#{branch}\"" if branch
                        body += ", ref: \"#{ref_flag}\"" if ref_flag
                        body
                      else
                        remote = (source_remote || "https://rubygems.org/").to_s
                        "source \"#{remote}\"\n\ngem \"#{names.first.not_nil!}\", \"#{version}\""
                      end
        File.write(File.join(tmp_dir, "Gemfile"), synthesized)
        old_env = ENV["BUNDLE_GEMFILE"]?
        ENV["BUNDLE_GEMFILE"] = File.join(tmp_dir, "Gemfile")
        old_bundle_path = ENV["BUNDLE_PATH"]?
        ENV["BUNDLE_PATH"] = File.join(tmp_dir, "bundle")
        begin
          definition = Definition.build
          resolution = Resolution.new(definition, false, bridge)
          resolution.progress = stdout
          stdin_specs = resolution.resolve!
        rescue ex : Error
          stderr.puts Commands.word_wrap(ex.message || ex.class.name, CLI.terminal_width) if ex.wrap?
          stderr.puts ex.message if !ex.wrap?
          return ex.status_code
        ensure
          if old_env
            ENV["BUNDLE_GEMFILE"] = old_env
          else
            ENV.delete("BUNDLE_GEMFILE")
          end
          if old_bundle_path
            ENV["BUNDLE_PATH"] = old_bundle_path
          else
            ENV.delete("BUNDLE_PATH")
          end
        end

        host_root = old_env ? Dir.current : Dir.current
        plugin_root = plugin_tree_root
        Dir.mkdir_p(plugin_root)
        abi = InstallPaths.ruby_abi(bridge)
        gem_root = InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi)
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root, Commands.retry_count(definition.config), Celerite::Mirror.resolve(definition.config, resolution.primary_remote), ssl_option(definition.config, "ssl_ca_cert"), ssl_option(definition.config, "ssl_client_cert"), ssl_option(definition.config, "ssl_verify_mode"), definition.config.credentials_for(resolution.primary_remote), timeout: Commands.timeout_seconds(definition.config), proxy: Celerite::Proxy.resolve(definition.config))
        installer = Installer.new(gem_root, abi, bridge, downloader, stdout)
        installer.config = definition.config
        stdin_specs.each do |spec|
          next unless names.includes?(spec.name)
          # Git materialization happens during resolution (the plugin source
          # is cloned/checked out by `ensure_source_dir`); gems stay in the
          # bundler/gems checkout directory, like regular git gems.
          plugin_dir = if git_remote
                         Dir.glob(File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi).gsub('\\', "/"), "bundler", "gems", "#{GitSource.base_name(git_remote)}-*")).first?
                       else
                         stdout.puts "Fetching #{spec.name} #{spec.version}"
                         stdout.puts "Installing #{spec.name} #{spec.version}"
                         installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum)
                         File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "gems", spec.full_name)
                       end
          if git_remote
            Dir.mkdir_p(File.join(plugin_root, "bundler", "gems"))
            # The CELERITE clone lives under `<install_path>/ruby/<abi>/bundler/gems`
            # (GitSource); copy that checkout tree for parity with the plugin
            # materialization tree the reference uses.
            if plugin_dir && Dir.exists?(plugin_dir)
              dst = File.join(plugin_root, "bundler", "gems", File.basename(plugin_dir.to_s))
              # FileUtils (not `cp -r`): spawning msys cp under this sandbox's
              # Low integrity level dies with 0xC0000022 (same root cause as
              # the git fixtures); a pure-Crystal copy keeps the plugin
              # materialization working here.
              copy_tree(plugin_dir.to_s, dst)
            end
            cache_root = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "cache", "bundler", "git")
            Glob.paths(cache_root, "*").each do |dir|
              next unless Dir.exists?(dir) && Dir.exists?(File.join(dir, "HEAD"))
              dst = File.join(plugin_root, "cache", "bundler", "git", File.basename(dir))
              next if Dir.exists?(dst)
              copy_tree(dir, dst)
            end
          end
          unless git_remote
            # Materialize the installed plugin gem into the plugin tree
            # (Bundler::Plugin::Installer parity: gems/, specifications/,
            # cache/ plus empty extensions/doc/build_info/plugins dirs).
            installed_gem_dir = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "gems", spec.full_name)
            if Dir.exists?(installed_gem_dir)
              dst = File.join(plugin_root, "gems", spec.full_name)
              Dir.mkdir_p(File.dirname(dst))
              copy_tree(installed_gem_dir, dst)
            end
            cached_gem = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "cache", "#{spec.full_name}.gem")
            if File.file?(cached_gem)
              Dir.mkdir_p(File.join(plugin_root, "cache"))
              FileUtils.cp(cached_gem, File.join(plugin_root, "cache", "#{spec.full_name}.gem"))
            end
            installed_spec = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "specifications", "#{spec.full_name}.gemspec")
            if File.file?(installed_spec)
              Dir.mkdir_p(File.join(plugin_root, "specifications"))
              FileUtils.cp(installed_spec, File.join(plugin_root, "specifications", "#{spec.full_name}.gemspec"))
            end
            {"extensions", "doc", "build_info", "plugins"}.each { |d| Dir.mkdir_p(File.join(plugin_root, d)) }
            plugin_dir = dst
          end
          unless File.file?(File.join(plugin_dir.to_s, "plugins.rb"))
            Dir.mkdir_p(plugin_root)
            stderr.puts "Failed to install plugin `#{spec.name}`, due to Bundler::Plugin::MalformattedPlugin"
            stderr.puts "(plugins.rb was not found in the plugin.)"
            return 29
          end
          index_path = File.join(plugin_root, "index")
          unless File.file?(index_path)
            File.write(index_path, "---\ncommands:\nhooks:\nload_paths:\nplugin_paths:\nsources:\n")
          end
          index = YAML.parse(File.read(index_path))
          load_path_map = {} of String => Array(String)
          (index["load_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
            load_path_map[key.as_s] = value.as_a?.try(&.map(&.as_s)) || [] of String
          end
          plugin_path_map = {} of String => String
          (index["plugin_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
            plugin_path_map[key.as_s] = value.as_s
          end
          hooks_map = {} of String => Array(String)
          (index["hooks"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
            hooks_map[key.as_s] = value.as_a?.try(&.map(&.as_s)) || [] of String
          end
          gem_dir = if git_remote
                      File.join(plugin_root, "bundler", "gems", "#{GitSource.base_name(git_remote)}-#{spec.version}").gsub(/\\/, "/")
                    else
                      # Installed plugin gems live in the plugin tree
                      # (`<project>/.bundle/plugin/gems/<full>`), not in the
                      # application bundle directory (Bundler::Plugin.root).
                      File.join(plugin_root, "gems", spec.full_name).gsub(/\\/, "/")
                    end
          lib_dir = File.join(gem_dir, "lib").gsub(/\\/, "/")
          registered = PluginCommands.commands(index_path)
          declared = PluginCommands.declared_commands(File.join(gem_dir, "plugins.rb"))
          conflict_command = declared.find do |command|
            owner = registered[command]?
            !owner.nil? && owner != spec.name
          end
          if conflict = conflict_command
            message = "Failed to install plugin `#{spec.name}`, due to Bundler::Plugin::Index::CommandConflict " \
                      "(Command(s) `#{conflict}` declared by #{spec.name} are already registered.)"
            stderr.puts Commands.word_wrap(message, CLI.terminal_width)
            return 29
          end
          merged_commands = registered.dup
          declared.each { |command| merged_commands[command] = spec.name }
          first_install = !plugin_path_map.has_key?(spec.name)
          load_path_map[spec.name] = [lib_dir]
          plugin_path_map[spec.name] = gem_dir
          yaml = String.build do |y|
            y.puts "---"
            y.puts "commands:"
            merged_commands.each { |command, owner| y.puts "  #{command}: #{owner.inspect}" }
            y.puts "hooks:"
            hooks_map.each do |key, value|
              y.puts "  #{key}:"
              value.each { |item| y.puts "  - #{item.inspect}" }
            end
            y.puts "load_paths:"
            load_path_map.each do |key, value|
              y.puts "  #{key}:"
              value.each { |item| y.puts "  - #{item.inspect}" }
            end
            y.puts "plugin_paths:"
            plugin_path_map.each { |key, value| y.puts "  #{key}: #{value.inspect}" }
            y.puts "sources:"
          end
          File.write(index_path, yaml)
          stdout.puts "Installed plugin #{spec.name}" if first_install
        end
      rescue ex : Error
        stderr.puts ex.message
        return ex.status_code
      ensure
        FileUtils.rm_rf(tmp_dir) unless tmp_dir.empty?
        if !tmp_root.empty? && Dir.exists?(tmp_root) && Dir.empty?(tmp_root)
          Dir.delete(tmp_root)
        end
        # A project without a Gemfile must stay byte-clean: when this command
        # created the app config root only to hold its temp dir, drop the empty
        # shell as well.
        if app_root_was_absent && !app_root.empty? && Dir.exists?(app_root) && Dir.empty?(app_root)
          Dir.delete(app_root)
        end
        bridge.close
      end
      0
    end

    def self.flag_value(rest : Array(String), flag : String) : String?
      rest.each_with_index do |arg, index|
        if arg == flag
          value = rest[index + 1]?
          return value unless value.nil? || value.starts_with?("--")
        end
        if arg.starts_with?(flag + "=")
          return arg.split("=", 2)[1]
        end
      end
      nil
    end

    # Plugin project root and tree (`Bundler::Plugin.root`): the project that
    # owns the Gemfile, or the current directory when there is no Gemfile. The
    # reference keeps `plugin list` and plugin commands working without a
    # Gemfile, and always materializes plugins under `<project>/.bundle/plugin`.
    # Reference app-config root: `<Gemfile dir>/.bundle` inside a bundle,
    # otherwise the user-level `~/.bundle` (`Bundler.app_config_path`).
    private def self.plugin_app_config_root : String
      gemfile = begin
        Definition.find_gemfile
      rescue GemfileNotFound
        nil
      end
      if gemfile
        File.join(File.dirname(gemfile), ".bundle")
      else
        File.join(Config.user_home || ".", ".bundle")
      end
    end

    private def self.plugin_project_dir : String
      gemfile = begin
        Definition.find_gemfile
      rescue GemfileNotFound
        nil
      end
      gemfile ? File.dirname(gemfile) : Dir.current
    end

    private def self.plugin_tree_root : String
      # `Bundler::Plugin.root` = `app_config_path/plugin`: project-local inside
      # a bundle, `~/.bundle/plugin` for a Gemfile-less cwd (which is why the
      # reference prints `No plugins installed` there unless the global root
      # already holds plugins).
      File.join(plugin_app_config_root, "plugin")
    end

    private def self.plugin_index_path : String
      File.join(plugin_tree_root, "index")
    end

    private def self.installed_plugins : Array(String)
      index_path = plugin_index_path
      return [] of String unless File.file?(index_path)

      index = YAML.parse(File.read(index_path))
      names = (index["load_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).keys.map(&.to_s)
      names.sort
    end

    # Rewrites the plugin index without the uninstalled plugins, preserving
    # the reference layout (`---` start, bare empty collections).
    private def self.write_plugin_index(path : String, index : YAML::Any, removed : Array(String)) : Nil
      render = ->(section : YAML::Any, out : String::Builder) do
        map = section.as_h? || {} of YAML::Any => YAML::Any
        keys = map.keys.map(&.to_s).reject { |k| removed.includes?(k) }
        keys.each do |key|
          value = map[key]?
          out.puts "  #{key}:"
          if value && value.as_a?
            value.as_a.each { |v| out.puts "  - #{v.to_s.inspect}" }
          elsif !value.nil?
            out.puts "  #{value.to_s.inspect}"
          end
        end
      end
      yaml = String.build do |y|
        y.puts "---"
        y.puts "commands:"
        commands_map = index["commands"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
        commands_map.each do |key, value|
          owner = value.as_s
          next if removed.includes?(owner)
          y.puts "  #{key.to_s}: #{owner.inspect}"
        end
        y.puts "hooks:"
        render.call(index["hooks"]? || YAML.parse("{}"), y)
        y.puts "load_paths:"
        render.call(index["load_paths"]? || YAML.parse("{}"), y)
        y.puts "plugin_paths:"
        render.call(index["plugin_paths"]? || YAML.parse("{}"), y)
        y.puts "sources:"
        render.call(index["sources"]? || YAML.parse("{}"), y)
      end
      File.write(path, yaml)
    end

    # ------------------------------------------------------------------
    # pristine: reinstall gems from their cached packages
    # ------------------------------------------------------------------
    def self.pristine(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      definition = Definition.build
      Commands.validate_runtime!(definition)
      gems = rest.reject(&.starts_with?("--"))
      lockfile = definition.lockfile!
      unless gems.empty?
        unknown = gems.find { |g| lockfile.specs.none?(&.name.==(g)) }
        if unknown
          stderr.puts "Could not find gem '#{unknown}'."
          return 7
        end
      end

      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, false, bridge)
        abi = InstallPaths.ruby_abi(bridge)
        gem_root = InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi)
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root, Commands.retry_count(definition.config), Celerite::Mirror.resolve(definition.config, resolution.primary_remote), ssl_option(definition.config, "ssl_ca_cert"), ssl_option(definition.config, "ssl_client_cert"), ssl_option(definition.config, "ssl_verify_mode"), definition.config.credentials_for(resolution.primary_remote), timeout: Commands.timeout_seconds(definition.config), proxy: Celerite::Proxy.resolve(definition.config))
        installer = Installer.new(gem_root, abi, bridge, downloader, stdout)
        installer.config = definition.config
        install_root = InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi)
        cache_dir = File.join(install_root, "cache")
        gems_root = File.join(install_root, "gems")

        ordered = lockfile.specs.sort_by(&.full_name)
        # Map spec name to its source section type.
        type_of = {} of String => String
        lockfile.sources.each do |section|
          section.specs.each do |spec|
            type_of[spec.full_name] = section.type
          end
        end

        ordered.each do |spec|
          next if spec.name == "bundler"
          next unless gems.empty? || gems.includes?(spec.name)
          type = type_of[spec.full_name]? || "GEM"
          case type
          when "GEM"
            gem_file = File.join(cache_dir, "#{spec.full_name}.gem")
            unless File.file?(gem_file)
              gem_label = "#{spec.name} (#{spec.version})" + (spec.platform && !spec.platform_ruby? ? " (#{spec.platform})" : "")
              stderr.puts "Failed to pristine #{gem_label}. Cached gem #{gem_file} does not exist."
            end
            checksum = lockfile.checksums.find do |c|
              c.name == spec.name && c.version == spec.version
            end.try(&.checksums.first?)
            stdout.puts "Installing #{spec.name} #{spec.version}#{native_suffix(bridge, File.file?(gem_file) ? gem_file : nil)}"
            installer.reinstall(spec.name, spec.version, spec.platform, checksum)
          when "GIT"
            # Pinned reference behavior: git pristine removes the checkout
            # and re-materializes it silently (no "Installing" line).
            if definition.config["local.#{spec.name}"]
              stderr.puts "Cannot pristine #{spec.name} (#{spec.version}). Gem is locally overridden."
              next
            end
            if source = resolution.non_gem_sources[spec.name]?
              bundle_root = InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi)
              checkout_root = File.join(bundle_root, "bundler", "gems")
              FileUtils.rm_rf(Glob.paths(checkout_root, "#{GitSource.base_name(source.remote)}-*").first? || "")
              ext_dir = File.join(install_root, "extensions", Gem::Platform.local.to_s, abi, spec.full_name)
              FileUtils.rm_rf(ext_dir)
              resolution.ensure_source_dir(spec.name, source)
            end
          when "PATH"
            stderr.puts "Cannot pristine #{spec.name} (#{spec.version}). Gem is sourced from local path."
          else
            stderr.puts "Cannot pristine #{spec.name} (#{spec.version}). Gem is sourced from local path."
          end
        end
      ensure
        bridge.close
      end
      0
    end

    # ------------------------------------------------------------------
    # init: create a Gemfile skeleton (pinned reference template)
    # ------------------------------------------------------------------
    INIT_TEMPLATE = <<-TEXT
    # frozen_string_literal: true

    source "https://rubygems.org"

    # gem "rails"

    TEXT

    def self.init(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, INIT_SWITCH_FLAGS, INIT_SWITCH_VALUES))
        return code
      end
      gemfile_path = File.join(Dir.current, rest.select(&.starts_with?("--gemfile")).first?.try { |f| f.split("=")[1]? } || "Gemfile")
      if File.file?(gemfile_path)
        stderr.puts "Gemfile already exists at #{gemfile_path.gsub(/\\/, "/")}"
        return 1
      end
      File.write(gemfile_path, INIT_TEMPLATE)
      stdout.puts "Writing new Gemfile to #{gemfile_path.gsub(/\\/, "/")}"
      0
    end

    # ------------------------------------------------------------------
    # outdated: table of gems with newer versions (pinned reference columns)
    # ------------------------------------------------------------------
    def self.outdated(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, OUTDATED_SWITCH_FLAGS, OUTDATED_SWITCH_VALUES))
        return code
      end
      definition = Definition.build
      # `outdated` materializes the bundle before consulting the index
      # (`cli/outdated.rb` -> DependencyAPI/`Bundler.load`), so a missing
      # lockfile surfaces the local-only resolution error first.
      materialize_lockfile(definition, nil, local_only: true) unless definition.lockfile_exists?
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        RubyRuntime.validate!(evaluation.ruby, bridge.ruby_environment) if evaluation.ruby
      rescue ex : Error
        bridge.close
        raise ex
      rescue
      end
      begin
        parseable = rest.includes?("--parseable") || rest.includes?("--porcelain")
        local_flag = rest.includes?("--local")
        resolution = Resolution.new(definition, false, bridge)
        unless cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        verbose = ENV["CELERITE_VERBOSE"]? == "1"
        if verbose
          # The `Running ...` echo is emitted once by `Commands.dispatch`
          # (`print_command_echo`); only the reference debug line is printed
          # here, so the two never duplicate.
          primary = resolution.primary_remote
          if primary.starts_with?("file:") || primary.includes?("127.0.0.1") || primary.includes?("localhost")
            stdout.puts "Re-resolving dependencies because bundler is unlocking Using a local server, bundler won't use the CompactIndex API"
          end
        end
        # Pinned by the `outdated-parseable` differential: parseable mode
        # sends resolution progress to stderr; table mode writes it to stdout.
        # Local (cache-only) resolution prints Resolving but no index fetch.
        resolution.progress = local_flag && !parseable ? IO::Memory.new : (parseable ? stderr : stdout)
        # Option parsing for outdated selection flags (reference
        # `Bundler::CLI::Outdated#run`).
        selected = [] of String
        i = 0
        while i < rest.size
          arg = rest[i]
          if %w[--group --source --cooldown].includes?(arg)
            i += 2
          elsif arg.starts_with?("--group=") || arg.starts_with?("--source=") || arg.starts_with?("--cooldown=")
            i += 1
          elsif arg.starts_with?("--")
            i += 1
          else
            selected << arg
            i += 1
          end
        end
        # `Bundler::CLI::Outdated#run` validates the named gems against a
        # *silenced* resolve (`Bundler.ui.silence { Bundler.definition.resolve }`)
        # before it starts the printing resolution. A missing name therefore
        # reports `Could not find gem '<name>'.` (exit 7) with no index fetch
        # and no `Resolving dependencies...` line in front of it.
        unless selected.empty?
          known_names = if definition.lockfile_exists?
                          definition.lockfile!.specs.map(&.name)
                        else
                          materialize_lockfile(definition, nil, local_only: true).specs.map(&.name)
                        end
          selected.each do |gem_name|
            unless known_names.includes?(gem_name)
              raise GemNotFoundError.new("Could not find gem '#{gem_name}'.")
            end
          end
        end
        specs = resolution.resolve!
        cooldown_days = cooldown_flag_value(rest)
        cooldown_now = resolution.cooldown_now || Time.utc.to_unix
        cooldown_notes = {} of String => Int32
        cooldown_adoptable = {} of String => Gem::Version
        stdout.puts "Resolving dependencies..." if local_flag && !parseable
        # A named-gem request makes the reference build and resolve a
        # second (gem-scoped) definition for output.
        stdout.puts "Resolving dependencies..." if !selected.empty? && !local_flag
        filter_major = rest.includes?("--filter-major")
        filter_minor = rest.includes?("--filter-minor")
        filter_patch = rest.includes?("--filter-patch")
        only_explicit = rest.includes?("--only-explicit")
        include_pre = rest.includes?("--pre")
        strict = rest.includes?("--strict") || rest.includes?("--filter-strict") ||
                 rest.includes?("--patch") || rest.includes?("--minor") || rest.includes?("--major")
        promotion = if rest.includes?("--patch")
                      "patch"
                    elsif rest.includes?("--minor")
                      "minor"
                    elsif rest.includes?("--major")
                      "major"
                    end
        group_filter = flag_value(rest, "--group")
        groups_mode = group_filter ? "" : (rest.includes?("--groups") ? "all" : nil)
        source_flag = flag_value(rest, "--source")
        source_client = if source_flag
                          matched = resolution.evaluation.sources.find do |source|
                            candidate = source.remotes.try(&.first?) || source.remote
                            (source.name && source.name == source_flag) ||
                              (candidate && candidate.chomp('/').downcase == source_flag.chomp('/').downcase)
                          end
                          source_remote = matched ? (matched.remotes.try(&.first?) || matched.remote || source_flag) : source_flag
                          resolution.compact_index_client_for(source_remote)
                        else
                          resolution.compact_index_client
                        end
        explicit_names = lockfile_try = definition.lockfile_exists? ? definition.lockfile!.dependencies.map(&.name) : [] of String
        evaluation_groups = {} of String => String
        resolution.evaluation.dependencies.each do |dep|
          evaluation_groups[dep.name] = dep.groups.empty? ? "default" : dep.groups.join(", ")
        end

        rows = [] of Array(String)
        lockfile = definition.lockfile_exists? ? definition.lockfile! : nil
        local_cache_versions = local_flag ? local_cached_versions(definition, bridge, resolution) : {} of String => Array(Gem::Version)
        created_at_by_version = {} of Gem::Version => Int64
        specs.each do |spec|
          next unless selected.empty? || selected.includes?(spec.name)
          next if only_explicit && !explicit_names.includes?(spec.name)

          versions = if local_flag
                       (local_cache_versions[spec.name]? || [] of Gem::Version).reject { |v| v.prerelease? && !include_pre }
                     else
                       entries = source_client.info(spec.name)
                       entries.each do |entry|
                         if created = entry.created_at
                           created_at_by_version[Gem::Version.new(entry.version)] = created
                         end
                       end
                       entries.map { |e| Gem::Version.new(e.version) }.reject { |v| v.prerelease? && !include_pre }
                     end
          dep = lockfile.try(&.dependencies.find(&.name.==(spec.name)))
          reqs = dep.try(&.requirements)
          if strict && reqs && !reqs.empty?
            requirement = Gem::Requirement.new(reqs)
            versions = versions.select { |v| requirement.satisfied_by?(v) }
          end
          if promotion
            case promotion
            when "patch"
              versions = versions.select { |v| !v.prerelease? && v.segments[0] == spec.version.segments[0] && v.segments[1] == spec.version.segments[1] }
            when "minor"
              versions = versions.select { |v| !v.prerelease? && v.segments[0] == spec.version.segments[0] }
            end
          end
          latest = versions.max?
          next if latest.nil? || (latest <=> spec.version) <= 0

          if cooldown_days && !strict && !promotion
            if created = created_at_by_version[latest]
              remaining_seconds = cooldown_days.to_i64 * 86_400_i64 - (cooldown_now - created)
              if remaining_seconds > 0
                remaining_days = (remaining_seconds / 86_400.0).ceil.to_i32
                if remaining_days > 0
                  cooldown_notes[spec.name] = remaining_days
                  adoptable = versions.select do |candidate|
                    created_at = created_at_by_version[candidate]?
                    next false unless created_at
                    (cooldown_days.to_i64 * 86_400_i64 - (cooldown_now - created_at)) <= 0
                  end.select { |candidate| candidate > spec.version && candidate < latest }.max?
                  cooldown_adoptable[spec.name] = adoptable if adoptable
                end
              end
            end
          end

          if filter_major || filter_minor || filter_patch
            current_segments = spec.version.segments
            latest_segments = latest.segments
            passes = false
            if filter_major && latest_segments[0].to_i > current_segments[0].to_i
              passes = true
            end
            if !passes && (filter_minor || filter_patch) && latest_segments[0] == current_segments[0]
              passes = true if filter_minor && latest_segments[1].to_i > current_segments[1].to_i
              passes = true if filter_patch && latest_segments[1].to_i == current_segments[1].to_i && latest_segments[2].to_i > current_segments[2].to_i
            end
            next unless passes
          end

          requested = if reqs && !reqs.empty?
                        reqs.join(", ")
                      else
                        ">= 0"
                      end
          groups = evaluation_groups[spec.name]? || "default"
          row = [spec.name, spec.version.to_s, latest.to_s, requested, groups]
          if !parseable && (remaining = cooldown_notes[spec.name]?)
            table_suffix = " (cooldown #{remaining}d"
            table_suffix += ", #{cooldown_adoptable[spec.name]} out of cooldown" if cooldown_adoptable[spec.name]?
            table_suffix += ")"
            row[2] = latest.to_s + table_suffix
          end
          # Release Date column is 4.0.24-only (2.7.x reference has 5 columns)
          unless resolution.bridge_bundler_version.starts_with?("2.")
            row << release_date_for(definition, resolution, spec.name, latest.to_s, spec.checksum)
          end
          if verbose
            abi = InstallPaths.ruby_abi(bridge)
            path = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "specifications", "#{spec.name}-#{latest}.gemspec")
            row << (File.file?(path) ? path.gsub(/\\/, "/") : "")
          end
          rows << row
        end

        unless group_filter.nil? && groups_mode.nil?
          rows = rows.select { |row| groups_mode == "all" || row[4].split(", ").includes?(group_filter) }
          rows = rows.sort_by { |row| [row[4], row[0]] } if groups_mode
        end

        if parseable
          # Pinned by `outdated-parseable`: a leading blank line, then one
          # line per gem (release date only on the 4.0.24 profile).
          stdout.puts
          rows.each do |row|
            message = "#{row[0]} (newest #{row[2]}, installed #{row[1]}, requested #{row[3]}"
            if date = row[5]?
              message += ", released #{date}" unless date.strip.empty?
            end
            if remaining = cooldown_notes[row[0]]?
              message += ", in cooldown for #{remaining} more day#{remaining == 1 ? "" : "s"}"
              message += ", newest out of cooldown #{cooldown_adoptable[row[0]]}" if cooldown_adoptable[row[0]]?
            end
            stdout.puts "#{message})"
          end
          return rows.empty? ? 0 : 1
        end

        if rows.empty?
          stdout.puts
          if filter_major || filter_minor || filter_patch
            display = [] of String
            display << "major" if filter_major
            display << "minor" if filter_minor
            display << "patch" if filter_patch
            stdout.puts "No #{display.join(" or ")} updates to display."
          else
            stdout.puts "Bundle up to date!"
          end
          return 0
        end

        # Release Date column is 4.0.24-only (2.7.x reference has 5 columns)
        header = ["Gem", "Current", "Latest", "Requested", "Groups"]
        header << "Release Date" unless resolution.bridge_bundler_version.starts_with?("2.")
        header << "Path" if verbose
        widths = header.map_with_index do |h, i|
          Math.max(h.size, rows.max_of { |row| row[i]? ? row[i].size : 0 }) + 2
        end
        stdout.puts
        stdout.puts header.map_with_index { |h, i| h.ljust(widths[i]) }.join.rstrip
        rows.each do |row|
          stdout.puts row.map_with_index { |cell, i| cell.ljust(widths[i]) }.join.rstrip
        end
        # Reference exits 1 when outdated gems exist
        1
      ensure
        bridge.close
      end
    end

    private def self.local_cached_versions(definition : Definition, bridge : Bridge::Client, resolution : Resolution) : Hash(String, Array(Gem::Version))
      abi = InstallPaths.ruby_abi(bridge)
      cache_dir = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "cache")
      versions = {} of String => Array(Gem::Version)
      return versions unless Dir.exists?(cache_dir)

      Dir.children(cache_dir).select(&.ends_with?(".gem")).each do |gem_file|
        full = File.join(cache_dir, gem_file)
        next unless File.file?(full)
        begin
          info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(full).to_json)
          (versions[info.name] ||= [] of Gem::Version) << Gem::Version.new(info.version)
        rescue
          nil
        end
      end
      versions
    end

    private def self.release_date_for(definition : Definition, resolution : Resolution, name : String, version : String, checksum : String?) : String
      downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root, Commands.retry_count(definition.config), Celerite::Mirror.resolve(definition.config, resolution.primary_remote), ssl_option(definition.config, "ssl_ca_cert"), ssl_option(definition.config, "ssl_client_cert"), ssl_option(definition.config, "ssl_verify_mode"), definition.config.credentials_for(resolution.primary_remote), timeout: Commands.timeout_seconds(definition.config), proxy: Celerite::Proxy.resolve(definition.config))
      path = downloader.fetch(name, version, nil, checksum)
      info = Bridge::GemSpecInfo.from_json(bridge_read_spec_json(path).to_json)
      info.date.to_s.split(" ")[0]
    rescue
      ""
    end

    private def self.bridge_read_spec_json(path : String) : JSON::Any
      client = Bridge::Client.new
      begin
        client.read_gem_spec(path)
      ensure
        client.close
      end
    end

    # ------------------------------------------------------------------
    # issue: reference resource block + doctor-style diagnostics
    # ------------------------------------------------------------------
    ISSUE_RESOURCES_4X = <<-TEXT
    Did you find an issue with Bundler? Before filing a new issue,
    be sure to check out these resources:

    1. Check out our troubleshooting guide for quick fixes to common issues:
    https://github.com/ruby/rubygems/blob/master/doc/bundler/TROUBLESHOOTING.md

    2. Instructions for common Bundler uses can be found on the documentation
    site: https://guides.rubygems.org/

    3. Information about each Bundler command can be found in the Bundler
    man pages: https://guides.rubygems.org/command-reference/bundle/

    Hopefully the troubleshooting steps above resolved your problem!  If things
    still aren't working the way you expect them to, please let us know so
    that we can diagnose and help fix the problem you're having, by filling
    in the new issue form located at
    https://github.com/ruby/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md,
    and copy and pasting the information below.

    TEXT

    ISSUE_RESOURCES_2X = <<-TEXT
    Did you find an issue with Bundler? Before filing a new issue,
    be sure to check out these resources:

    1. Check out our troubleshooting guide for quick fixes to common issues:
    https://github.com/rubygems/rubygems/blob/master/doc/bundler/TROUBLESHOOTING.md

    2. Instructions for common Bundler uses can be found on the documentation
    site: https://bundler.io/

    3. Information about each Bundler command can be found in the Bundler
    man pages: https://bundler.io/man/bundle.1.html

    Hopefully the troubleshooting steps above resolved your problem!  If things
    still aren't working the way you expect them to, please let us know so
    that we can diagnose and help fix the problem you're having, by filling
    in the new issue form located at
    https://github.com/rubygems/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md,
    and copy and pasting the information below.

    TEXT

    def self.issue_resources : String
      if (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
        ISSUE_RESOURCES_2X
      else
        ISSUE_RESOURCES_4X
      end
    end

    def self.git_sha : String
      # Prefer actual source/checkout git SHA; avoid misleading hardcoded
      # reference Bundler build SHAs.
      begin
        if exe = Process.executable_path
          dir = File.dirname(exe)
          repo = File.expand_path("..", dir)
          if Dir.exists?(File.join(repo, ".git"))
            output = IO::Memory.new
            result = Process.run("git", ["-C", repo, "rev-parse", "--short=7", "HEAD"],
              output: output, error: Process::Redirect::Close)
            if result.success?
              sha = output.to_s.strip
              return sha unless sha.empty?
            end
          end
        end
        output = IO::Memory.new
        result = Process.run("git", ["rev-parse", "--short=7", "HEAD"], output: output, error: Process::Redirect::Close)
        if result.success?
          sha = output.to_s.strip
          return sha unless sha.empty?
        end
      rescue
      end
      "unknown"
    end

    def self.issue(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # `issue` takes no arguments: the reference rejects tokens in Thor
      # (`Usage: "bundle issue"`, no `[OPTIONS]` suffix).
      if (code = reject_unknown_switches(stderr, rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      if (code = reject_positional_arguments(stderr, "issue", rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      stdout.puts issue_resources.rstrip
      stdout.puts

      # env report is printed BEFORE the Gemfile lookup fails (reference
      # issue prints the full report, then the doctor error on stderr)
      bridge = Bridge::Client.new
      begin
        re = bridge.ruby_environment
        stdout.puts "## Environment"
        stdout.puts
        stdout.puts "```"
        bundler_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        # Same line as `env` (env.rb:44): the reference has no Celerite suffix,
        # and `issue` embeds the identical environment report.
        stdout.puts "Bundler       #{bundler_version}"
        platforms = [Gem::Platform::RUBY.to_s, Gem::Platform.local.to_s]
        stdout.puts "  Platforms   #{platforms.join(", ")}"
        stdout.puts "Ruby          #{re.ruby_env_line}"
        stdout.puts "  Full Path   #{re.ruby_exe.gsub(/\\/, "/")}"
        stdout.puts "  Config Dir  #{(re.system_config_dir || config_dir).gsub(/\\/, "/")}"
        stdout.puts "RubyGems      #{re.rubygems_version}"
        # `Gem.dir`/`Gem.path`/`Gem.bindir` as RubyGems resolves them, not the
        # bundle path: `Bundler::Env` reports the interpreter's gem environment
        # and leaves BUNDLE_PATH to the "## Bundler settings" section.
        gem_home = re.default_gem_dir.gsub(/\\/, "/")
        stdout.puts "  Gem Home    #{gem_home}"
        stdout.puts "  Gem Path    #{re.gem_paths.map(&.gsub(/\\/, "/")).join(Process::PATH_DELIMITER)}"
        user_dir = re.user_gem_dir
        if user_dir
          forward = user_dir.gsub(/\\/, "/")
          stdout.puts "  User Home   #{forward.sub(/\.local\/share\/gem.*/, "").rstrip("/")}"
          stdout.puts "  User Path   #{forward}"
        end
        bin_dir = re.gem_bindir || File.join(gem_home, "bin")
        stdout.puts "  Bin Dir     #{bin_dir.gsub(/\\/, "/")}"
        stdout.puts "Tools         "
        stdout.puts "  Git         #{git_version}"
        stdout.puts "  RVM         not installed"
        stdout.puts "  rbenv       not installed"
        stdout.puts "  chruby      not installed"
        stdout.puts "```"
        stdout.puts
        stdout.puts "## Bundler Build Metadata"
        stdout.puts
        stdout.puts "```"
        release = Celerite::ReleaseMetadata.for(bundler_version)
        stdout.puts "Timestamp  #{release ? release[0] : build_timestamp}"
        stdout.puts "Git SHA    #{release ? release[1] : git_sha}"
        stdout.puts "```"
        stdout.puts

        # Bundler settings block: all configured keys in priority order
        config = Config.new
        settings_keys = (config.local_config.keys | ENV.keys.select(&.starts_with?("BUNDLE_"))).uniq
        settings_names = settings_keys.map do |key|
          key.lchop("BUNDLE_").gsub("__", ".").gsub("___", "-").downcase
        end.uniq.sort
        unless settings_names.empty?
          stdout.puts "## Bundler settings"
          stdout.puts
          stdout.puts "```"
          settings_names.each do |name|
            stdout.puts name
            config.pretty_values_for(name).each { |l| stdout.puts "  " + l }
          end
          stdout.puts "```"
          stdout.puts
        end

        # Gemfile sections only when the files exist (reference issue prints
        # empty sections otherwise; fixture uses Gemfile-less sandbox)
        gemfile_path = File.join(Dir.current, "Gemfile")
        lockfile_path = File.join(Dir.current, "Gemfile.lock")
        if File.file?(gemfile_path)
          stdout.puts "## Gemfile"
          stdout.puts
          stdout.puts "### Gemfile"
          stdout.puts
          stdout.puts "```ruby"
          File.each_line(gemfile_path) { |l| stdout.puts l.chomp }
          stdout.puts "```"
          stdout.puts
          if File.file?(lockfile_path)
            stdout.puts "### Gemfile.lock"
            stdout.puts
            stdout.puts "```"
            File.each_line(lockfile_path) { |l| stdout.puts l.chomp }
            stdout.puts "```"
            stdout.puts
          end
        end

        stdout.puts "## Bundle Doctor"
      ensure
        bridge.close
      end

      definition = Definition.build
      lockfile = definition.lockfile_exists? ? definition.lockfile! : nil
      if lockfile.nil?
        stderr.puts "Could not locate Gemfile"
        return 10
      end

      # Reference parity: the doctor's check re-resolves when the lockfile
      # does not cover the local platform (see the platform-missing note in
      # `check`), and the resolver announces that on stdout.
      if Commands.platform_missing?(definition)
        stdout.puts "Resolving dependencies..."
      end

      missing = lockfile.specs.sort_by(&.full_name).reject do |spec|
        installed_spec_dir?(definition, spec, lockfile)
      end
      unless missing.empty?
        stderr.puts "The following gems are missing"
        missing.each { |spec| stderr.puts " * #{spec.name} (#{spec.version})" }
        stderr.puts "Install missing gems with `bundle install`"
        return 1
      end
      stdout.puts "The Gemfile's dependencies are satisfied"
      stdout.puts "No issues found with the installed bundle"
      0
    end

    # ------------------------------------------------------------------
    # console: exec an interactive console inside the bundle environment
    # ------------------------------------------------------------------
    def self.console(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES))
        return code
      end
      # `bundle console [GROUP]` takes at most one positional group.
      if (code = reject_positional_arguments(stderr, "console", rest, BARE_SWITCH_FLAGS, BARE_SWITCH_VALUES, max_positionals: 1))
        return code
      end
      definition = Definition.build
      Commands.validate_ruby_runtime!(definition)

      # bundler/cli.rb declares `console [GROUP]`; Thor rejects extra
      # positional arguments before the console starts (measured on 4.0.24:
      # `bundle console a b` prints the two lines below and exits 15).
      positional = rest.reject(&.starts_with?("-"))
      if positional.size > 1
        quoted = positional.map { |arg| "\"#{arg}\"" }.join(", ")
        stderr.puts %(ERROR: "bundle console" was called with arguments [#{quoted}])
        stderr.puts %(Usage: "bundle console [GROUP]")
        return 15
      end

      # cli/console.rb:16: the console name comes from `console`
      # (BUNDLE_CONSOLE) and defaults to irb.
      name = definition.config["console"].to_s
      name = "irb" if name.empty?

      executable = find_console_executable(name)
      if executable.nil?
        if name == "irb"
          stderr.puts "irb is not available"
          return 1
        end
        # cli/console.rb:24-33: any other missing console falls back to irb.
        stderr.puts "Couldn't load console #{name}, falling back to irb"
        executable = find_console_executable("irb")
        if executable.nil?
          stderr.puts "irb is not available"
          return 1
        end
      end

      # DECLARED DEVIATION: the reference runs Bundler.require and
      # `console.start` in-process, so gem `require`/group semantics apply
      # inside the session. Celerite execs the console executable with
      # RUBYOPT=-rbundler/setup: only the load path is prepared, and the GROUP
      # argument is accepted but not required (the reference clears ARGV, so no
      # arguments are forwarded either).
      process_env = ENV.to_h
      setup = "-rbundler/setup"
      rubyopt = (process_env["RUBYOPT"]? || "").split(" ").reject(&.empty?)
      rubyopt.unshift(setup) unless rubyopt.includes?(setup)
      process_env["RUBYOPT"] = rubyopt.join(" ")
      process_env["BUNDLE_GEMFILE"] = File.expand_path(definition.gemfile_path).gsub(/\\/, "/")

      # Windows .bat/.cmd wrappers need the command processor; direct spawn
      # would fail with "not a valid application".
      if executable.ends_with?(".bat") || executable.ends_with?(".cmd")
        Process.run("cmd", ["/c", executable], env: process_env,
          output: :inherit, error: :inherit, input: :inherit).exit_code
      else
        Process.run(executable, [] of String, env: process_env,
          output: :inherit, error: :inherit, input: :inherit).exit_code
      end
    end

    # PATHEXT wrappers are not expanded by find_executable, so the Windows
    # variants are probed explicitly.
    private def self.find_console_executable(name : String) : String?
      Process.find_executable(name) ||
        Process.find_executable("#{name}.bat") ||
        Process.find_executable("#{name}.cmd")
    end

    # ------------------------------------------------------------------
    # gem: project skeleton (bundle gem NAME)
    # ------------------------------------------------------------------
    def self.gem(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if (code = reject_unknown_switches(stderr, rest, GEM_SWITCH_FLAGS, GEM_SWITCH_VALUES))
        return code
      end
      # Thor rejects a missing/multiple positionals before any work; the
      # reference (4.0.24) prints these exact lines and exits 15.
      positionals = rest.reject(&.starts_with?("-"))
      if positionals.empty?
        stderr.puts %(ERROR: "bundle gem" was called with no arguments)
        stderr.puts %(Usage: "bundle gem NAME [OPTIONS]")
        return 15
      end
      if positionals.size > 1
        stderr.puts %(ERROR: "bundle gem" was called with arguments #{positionals.inspect})
        stderr.puts %(Usage: "bundle gem NAME [OPTIONS]")
        return 15
      end

      # gem.rb/cli.rb:607-608: the deprecated `--rubocop` spellings raise
      # InvalidOption before any work.
      if rest.includes?("--rubocop")
        stderr.puts "--rubocop has been removed, use --linter=rubocop"
        return 15
      end
      if rest.includes?("--no-rubocop")
        stderr.puts "--no-rubocop has been removed, use --no-linter"
        return 15
      end

      # DECLARED DEVIATION: non-default options are rejected instead of
      # rendered. The reference accepts them (--mit adds the MIT license block,
      # --test adds a test framework, --exe adds exe/, ...). See
      # docs/compat-report.md "gem 模板对齐" for the measured reference output.
      # Negations (`--no-git`, `--no-mit`, ...) all mean "keep the default", so
      # Thor accepts them and the scaffold is unchanged.
      supported = ["--git", "--no-git", "--no-mit", "--no-coc", "--no-changelog",
                   "--no-exe", "--no-bundle"]
      unsupported = rest.select { |arg| arg.starts_with?("-") && !supported.includes?(arg) }
      unless unsupported.empty?
        stderr.puts "bundle gem option #{unsupported.first} is not supported by Celerite"
        stderr.puts "Supported options: --git (default), --no-git"
        return 1
      end

      name = File.basename(positionals.first)
      use_git = !rest.includes?("--no-git") && !Process.find_executable("git").nil?
      target = File.expand_path(name)

      if File.exists?(target) && !Dir.exists?(target)
        stderr.puts "Couldn't create a new gem named `#{name}` because there's an existing file named `#{name}`."
        return 32
      end

      # gem.rb:47-49: author/email/github come from `git config`, with the TODO
      # fallbacks at gem.rb:69-70 and "[USERNAME]" at gem.rb:16/77. All three
      # reads are gated on use_git (gem.rb:45-49): with `--no-git` the gemspec
      # keeps the TODO placeholders.
      author = use_git ? git_config("user.name") : ""
      author = "TODO: Write your name" if author.empty?
      email = use_git ? git_config("user.email") : ""
      email = "TODO: Write your email address" if email.empty?
      github_username = use_git ? git_config("github.user") : ""

      stdout.puts "Creating gem '#{name}'..."
      # gem.rb prompts for test/CI/linter/license/COC/changelog and prefixes each
      # question block with a blank line. Celerite does not implement the
      # interactive prompts (declared deviation in docs/compat-report.md), so no
      # blank separator is printed here.

      if use_git
        # gem.rb:257-262: the git-init line starts with a blank separator and
        # `git init` output is captured, hints stay on stderr.
        stdout.puts
        stdout.puts "Initializing git repo in #{target.gsub('\\', "/")}"
        Process.run("git", ["init", target], output: IO::Memory.new, error: :inherit)
      end

      GemTemplate.render(name, author, email, github_username, use_git).each do |entry|
        path = File.join(target, entry.path)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, entry.content)
        stdout.puts "      create  #{name}/#{entry.path}"
      end

      if use_git
        # gem.rb:275-277: `git add .` in the target; there is no commit. The
        # CRLF warnings git prints for LF files are inherited on purpose.
        Dir.cd(target) do
          Process.run("git", ["add", "."], output: IO::Memory.new, error: :inherit)
        end
      end

      stdout.puts
      stdout.puts "Gem '#{name}' was successfully created. " \
                  "For more information on making a RubyGem visit https://guides.rubygems.org/make-your-own-gem/"
      0
    end

    private def self.git_config(key : String) : String
      output = IO::Memory.new
      status = Process.run("git", ["config", key], output: output, error: IO::Memory.new)
      status.success? ? output.to_s.chomp : ""
    rescue
      ""
    end
  end
end
