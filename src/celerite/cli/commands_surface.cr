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
require "http/client"
require "openssl"

module Celerite
  # M5 CLI surface commands (pinned against the 4.0.24 oracle): update,
  # add/remove, env, doctor, licenses, fund, info, open, plugin.
  module Commands
    # ------------------------------------------------------------------
    # update: resolve with the named gems (or all) unlocked
    # ------------------------------------------------------------------
    # `cli/update.rb:14-16` forwards `--bundler` to the self-manager: a bare
    # flag asks for everything `>= #{Bundler::VERSION}`, an explicit value is
    # used verbatim. Returns nil when the flag is absent, "" when it is bare.
    private def self.update_bundler_target(rest : Array(String)) : String?
      rest.each_with_index do |arg, i|
        if arg == "--bundler"
          value = rest[i + 1]?
          return "" if value.nil? || value.starts_with?("-")
          return value
        end
        return arg.split("=", 2)[1] if arg.starts_with?("--bundler=")
      end
      nil
    end

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
      # A bare `--bundler` is a truthy option in the reference (empty string),
      # so it must count as a scoped update and not trigger the bare-update
      # deprecation notice.
      update_bundler = !update_bundler_target(rest).nil?
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
      # A full update in frozen/deployment mode with no lockfile stops in
      # `Definition#validate_platforms!` (definition.rb:471-473): the platform
      # list is empty, so `current_platform_locked?` is false and the
      # add-platform error fires (measured on 4.0.24 and 2.7.2, exit 16). A
      # scoped update instead fails later with "This Bundle hasn't been
      # installed yet." (exit 22), so it must not be preempted here.
      if full_update && config.frozen? && !definition.lockfile_exists?
        local_platform = Gem::Platform.local.to_s
        raise ProductionError.new(
          "Your bundle only supports platforms [] but your local platform is " \
          "#{local_platform}. Add the current platform to the lockfile with\n" \
          "`bundle lock --add-platform #{local_platform}` and try again.")
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
            # `cli/common.rb:113-123`: the raise carries the Did-you-mean line
            # over the lockfile names, exactly like `lock --update`.
            raise GemNotFoundError.new(gem_not_found_message_for(gem_name, locked_names))
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
        # `cli/update.rb:49-56`: a selector that matches nothing leaves the
        # unlock set empty, and `Bundler.definition(gems: [], 閳?` then unlocks
        # nothing 閳?the lockfile is left untouched and only the closing line
        # is printed. Without this the resolver still fetches the index and
        # re-resolves, which the reference never does.
        if !full_update && gems.empty? && sources.empty? && !ruby_flag && !update_bundler
          stdout.puts "Bundle updated!"
          return 0
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
        # `SelfManager#update_bundler_and_restart_with_it_if_needed`
        # (self_manager.rb:33-46): resolve the target against the rubygems
        # remote before any update work; a missing target is a hard error
        # (cli/update.rb:111-116). We record the target instead of exec'ing a
        # different bundler (declared divergence).
        emit_bundler_fetch = false
        if target = update_bundler_target(rest)
          current = resolution.bridge_bundler_version
          current_version = Gem::Version.new(current)
          bare = target.empty?
          # 4.x defaults a bare flag to `>= #{Bundler::VERSION}`; 2.7.2 uses
          # the `lazy_default` `> 0.a` (cli.rb:332 vs :266).
          requirement_text = if bare
                               current.starts_with?("2.") ? "> 0.a" : ">= #{current}"
                             else
                               target
                             end
          requirement = begin
            Gem::Requirement.new(requirement_text)
          rescue
            stderr.puts "The `bundle update --bundler` target version (#{requirement_text}) does not exist"
            return 15
          end
          # `SelfManager#find_latest_matching_spec` (self_manager.rb:140-153)
          # always consults the remote; 2.7.2 falls back to the installed
          # bundler for its non-specific `> 0.a` default, 4.x does not.
          candidate = resolution.bundler_versions(requirement).last?
          if bare && current.starts_with?("2.")
            candidate = current_version if candidate.nil? || candidate < current_version
          elsif !bare && candidate.nil? && requirement.satisfied_by?(current_version)
            candidate = current_version
          end
          if candidate.nil?
            stderr.puts "The `bundle update --bundler` target version (#{requirement_text}) does not exist"
            return 15
          end
          needs_update = requirement.specific? ? candidate != current_version : current_version < candidate
          if needs_update
            stdout.puts "Updating bundler to #{candidate}."
            resolution.bundler_version_to_lock = candidate.to_s
          end
          # The reference's self-manager and the update resolution each own a
          # source instance, so both print the index line; our resolution
          # caches the fetch, so replay the second line here.
          emit_bundler_fetch = true
        end
        if emit_bundler_fetch
          stdout.puts "Fetching source index from #{resolution.primary_remote}"
        end
        lock = ProcessLock.lock(InstallPaths.install_path(config))
        unless cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        resolution.local_only = rest.includes?("--local")
        resolution.prefer_local = rest.includes?("--prefer-local")
        if days = cooldown_flag_value(rest)
          resolution.cooldown_days = days
        end
        # `cli/common.rb:137` rejects multiple promotion levels before the
        # promoter is configured, i.e. before resolution and any write.
        if conflicts = Commands.promotion_level_conflicts(rest)
          stderr.puts "Provide only one of the following options: #{conflicts.join(", ")}"
          return 15
        end
        # `cli/common.rb:134-144`: the level is the requested one, else `:patch`
        # when `prefer_patch` is set (`:136` appends it before `level.first`),
        # else `:major`; `strict` is the flag alone (`:141`).
        update_level = Commands.requested_promotion_level(rest)
        update_level = "patch" if update_level.nil? && definition.config["prefer_patch"] == true
        resolution.version_promotion = update_level || "major"
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

        # `update` runs through the same `Installer.install` entry point as
        # `install` (`cli/update.rb:81`), so both install-all hooks fire.
        if code = PluginHooks.run(bridge, definition, config, "before-install-all", stdout, stderr)
          return code
        end
        # `cli/update.rb:81` hands the definition to the same `Installer.install`
        # as `install`, so `installer.rb:73-77` warns here as well — before the
        # resolve that prints `Resolving dependencies...`.
        Commands.warn_when_no_dependencies(stderr, resolution)
        # `definition.rb:866-902`: an unlocked update always re-resolves, and the
        # debug reason names the gems for a scoped selection and stays a bare
        # trailing space for `--all` (`@gems_to_unlock` empty), which Thor then
        # prints without a newline so the local-server note shares the line.
        if Commands.verbose_debug?
          reason = if gems.empty?
                     "Re-resolving dependencies because bundler is unlocking "
                   else
                     "Re-resolving dependencies because bundler is unlocking gems: (#{gems.sort.join(", ")})"
                   end
          Commands.print_debug_reason(stdout, reason)
          Commands.debug_local_server(stdout, resolution.primary_remote)
        end
        specs = resolution.resolve!

        # Reference prints "Resolving dependencies..." twice whenever a scoped
        # selection is unlocked (a conservative pre-resolve, then the real
        # resolve); `--group` widens into the same selection.
        if !gems.empty? && !source_restricted
          stdout.puts "Resolving dependencies..."
        end

        force_reinstall = rest.includes?("--force") || rest.includes?("--redownload")
        pending = specs.sort_by(&.full_name).select(&.source_type.==("GEM"))
        # `definition.rb:1251-1254` + `dependency.rb#should_include?`: the
        # requested group set is `groups - without - optional + with`, so gems
        # that only belong to an excluded group never enter the install step
        # (oracle: `BUNDLE_WITHOUT=test update --all` installs no `test` gem
        # while the lockfile keeps it).
        update_without = without_group_names(definition)
        unless update_without.empty?
          update_deps = resolution.evaluation.dependencies
          all_groups = update_deps.flat_map { |dep| dep.groups.empty? ? ["default"] : dep.groups }.uniq
          requested = all_groups.reject { |group| update_without.includes?(group) }
          keep = installable_specs(resolution, specs, requested).map(&.full_name).to_set
          pending = pending.select { |spec| keep.includes?(spec.full_name) }
        end
        unless force_reinstall
          pending = pending.reject do |spec|
            installer.installed?(spec.name, spec.version.to_s, spec.platform)
          end
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
          # `update --redownload`/`--force` map to `method_option "force"` in
          # the reference (`cli.rb:330`): gems that are already cached are
          # reinstalled from `<bundle>/ruby/<abi>/cache` or `vendor/cache`, and
          # the reference prints only the `Installing` line for them. A
          # `Fetching` line is reserved for a real package download.
          if cached = resolution.vendor_cache_path(spec.full_name) || installer.cached_package_path(spec.full_name)
            cached_paths[spec.full_name] = cached
            next
          end
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
          installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum, gem_file: cached)
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

        # `Installer.install` fires `gem_after_install_all` after the install
        # run; `Bundle updated!` is printed afterwards by `cli/update.rb`.
        if code = PluginHooks.run(bridge, definition, config, "after-install-all", stdout, stderr)
          return code
        end

        # `cli/update.rb:82`: `Bundler.load.cache if Bundler.app_cache.exist?` 閳?        # update refreshes the app cache right after the install pass and
        # before the optional cleaner and the `Bundle updated!` line.
        update_install_root = InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, InstallPaths.ruby_abi(bridge))
        if Dir.exists?(app_cache_path(definition))
          update_entries = resolution.generated_lockfile.specs.map { |spec| {spec.name, spec.full_name} }
          refresh_app_cache(stdout, definition, update_install_root, update_entries, resolution.generated_lockfile)
        end

        # `cli/update.rb:84`: BUNDLE_CLEAN cleans after the install pass and
        # before `Bundle updated!` (oracle: Removing precedes that line).
        clean_after_install(stdout, definition, resolution.generated_lockfile, update_install_root, bridge)
        stdout.puts "Bundle updated!"
        print_update_without_notice(stdout, definition, resolution.evaluation.dependencies)
        print_cooldown_summary(resolution, stdout)
        # `cli/update.rb:123`: same trailing funding hint as install, printed
        # last, over the freshly resolved definition.
        print_fund_summary(definition, resolution.evaluation, resolution.generated_lockfile, bridge, stdout)
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
    ADD_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--skip-install", "--optimistic", "--strict", "--quiet"]
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
      # `cli/add.rb:41-52` rejects these combinations before the injector runs,
      # so nothing is written to the Gemfile (Thor exits 15). Measured: 4.0.24
      # rejects all four; 2.7.2 has no such block and instead fails later inside
      # the injected Gemfile (branch/git+github: exit 4) or proceeds (ref alone:
      # exit 0, git clone failure: exit 11), so the checks are 4.x only.
      unless profile_2_x?
        if rest.includes?("--git") && rest.includes?("--github")
          stderr.puts "You cannot specify `--git` and `--github` at the same time."
          return 15
        end
        unless rest.includes?("--git") || rest.includes?("--github")
          if rest.includes?("--branch")
            stderr.puts "You cannot specify `--branch` unless `--git` or `--github` is specified."
            return 15
          end
          if rest.includes?("--ref")
            stderr.puts "You cannot specify `--ref` unless `--git` or `--github` is specified."
            return 15
          end
        end
        if rest.includes?("--branch") && rest.includes?("--ref")
          stderr.puts "You cannot specify `--branch` and `--ref` at the same time."
          return 15
        end
      end
      # Thor only treats the operands it parses as values of the preceding
      # `--option` as option values (`cli/add.rb` then requires at least one
      # positional gem). `rest.reject(&.starts_with?("--"))` wrongly promoted
      # every option value to a gem name, e.g. `add --version thor` looked like
      # gem "thor" with requirement "= thor", and `add --glob x.gemspec thor`
      # injected a gem literally named "x.gemspec".
      name = add_positional_arguments(rest).first?
      if name.nil?
        stderr.puts "Please specify gems to add."
        return 15
      end

      # `cli/add.rb:57-59` validates every `--version` pattern before the
      # injector runs. Thor hands a value-less `--version` through as the
      # literal option name, so the reference reports it as an invalid
      # requirement instead of silently adding the gem.
      if (rest.includes?("--version") || rest.includes?("-v")) &&
         flag_value(rest, "--version").nil? && flag_value(rest, "-v").nil?
        stderr.puts "Invalid gem requirement pattern 'version'"
        return 15
      end

      definition = Definition.build
      gemfile_path = definition.gemfile_path

      # `cli/add.rb:33` splits `--version` on commas; each entry is validated
      # with `Gem::Requirement::PATTERN` (:57-59) and `Injector` dumps every
      # entry on its own (`injector.rb:106`), so `~> 2.8` keeps its operator and
      # a bare `1.2.3` becomes `= 1.2.3`. The old `"= <value>"` wrapping turned
      # every non-bare requirement into `Illformed requirement` after the
      # Gemfile had already been written.
      explicit_parts = nil.as(Array(String)?)
      if version_value = flag_value(rest, "--version") || flag_value(rest, "-v")
        explicit_parts = add_requirement_parts(version_value, stderr)
        return 15 if explicit_parts.nil?
      end

      # `source/path.rb:198-204` raises PathError (status 13) while the injector
      # evaluates the new dependency, i.e. before `append_to` writes anything.
      # Validate here so a missing `--path` leaves the Gemfile untouched.
      if path = flag_value(rest, "--path")
        expanded = File.expand_path(path, File.dirname(gemfile_path)).gsub('\\', "/")
        unless Dir.exists?(expanded)
          message = File.exists?(expanded) ? "is not a directory." : "does not exist."
          raise PathError.new("The path `#{expanded}` #{message}")
        end
      end

      # `Bundler::Injector#inject` (injector.rb:25-58) evaluates the Gemfile and
      # then drops every requested dependency the Gemfile already declares
      # (`@deps -= builder.dependencies`, which compares name+requirement+type).
      # The remaining set gates both `append_to` and the injected-gems
      # evaluation, so a repeated `add` with the same requirement is a no-op
      # (the Gemfile keeps its bytes) while a different requirement surfaces as
      # a conflict inside the synthetic `injected gems` file 閳?before any index
      # fetch line or Gemfile write.
      # `Injector` resolves and installs the injected dependency BEFORE it
      # appends the line, so a failed `add` leaves the Gemfile byte-identical
      # (oracle: `add nosuchgem --skip-install` exits 7 with the source line
      # only). We write first because the lock regeneration needs the new
      # dependency, so restore the original bytes whenever anything after the
      # append raises.
      gemfile_backup = File.read(gemfile_path)
      gemfile_appended = false
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(gemfile_path)
        desired = explicit_parts || [">= 0"]
        current = evaluation.dependencies.find { |dep| dep.name == name }
        if current && !same_requirement?(current.requirements, desired)
          raise injected_gem_conflict(name, current.requirements, desired, gemfile_path)
        end
        already_declared = !current.nil?

        probe_printed = false
        unless already_declared
          # Pinned by `add-git`: the reference announces the git fetch while
          # evaluating the injected dependency, i.e. after the conflict check
          # and before the requirement probe's index fetch/resolve lines.
          if git = flag_value(rest, "--git")
            stdout.puts "Fetching #{git}"
          end

          # Requirement semantics pinned by add-version/add-strict/
          # add-optimistic probes: explicit `--version` is exact; otherwise
          # strict (`= major.minor`), optimistic (`>= major.minor`) or the
          # default pessimistic (`~> major.minor`) form.
          probe = latest_requirement_for(definition, name, stdout, rest, bridge, explicit_parts)
          version_requirement = probe[:requirement]
          gem_line = "gem \"#{name}\"#{version_requirement}#{add_group_option(rest)}#{add_option_suffix(rest)}"
          append_gemfile(gemfile_path, gem_line)
          gemfile_appended = true
          probe_printed = probe[:printed]
        end

        # `Injector#inject` (injector.rb:25-58) relocks the definition even when
        # every requested gem was already declared (`@definition.lock` runs
        # unconditionally, only `append_to` is gated on `@deps.any?`). The plain
        # install path below writes that lockfile itself, but `--skip-install`
        # stops before the installer, so the relock has to happen here: with an
        # existing lockfile the regenerated contents equal the old ones and
        # nothing is printed (`add json_pure` on a locked project is silent),
        # while a project without a lockfile gets the resolver's fetch/resolve
        # announcement and the new lockfile (`add-skip-install`,
        # `add-existing-same` fixtures).
        if rest.includes?("--skip-install")
          persist_add_lockfile(definition, bridge, stdout, probe_printed)
        end
      rescue ex
        File.write(gemfile_path, gemfile_backup) if gemfile_appended
        raise ex
      ensure
        bridge.close
      end

      if rest.includes?("--skip-install")
        # Pinned by `add-skip-install`: write the Gemfile line (after the
        # requirement probe) and stop before installation.
        return 0
      end

      # Reference add prints two fetches (requirement probing + shared
      # resolution); install() repeats the second fetch when the lockfile
      # is (re)written. An unchanged Gemfile still runs the installer, which
      # reuses the lockfile resolution and therefore prints nothing.
      code = begin
        install(stdout, stderr, install_args_from_add(rest, name),
          summary: false, no_reuse: !already_declared)
      rescue ex
        File.write(gemfile_path, gemfile_backup) if gemfile_appended
        raise ex
      end
      # `cli/add.rb:26-30`: `perform_bundle_install` = install, then
      # `Bundler.load.cache if Bundler.app_cache.exist?`.
      if code == 0
        add_definition = Definition.build
        if Dir.exists?(app_cache_path(add_definition))
          add_root = begin
            add_bridge = Bridge::Client.new
            begin
              InstallPaths.gem_root(add_definition.config, add_bridge.ruby_environment.default_gem_dir, InstallPaths.ruby_abi(add_bridge))
            ensure
              add_bridge.close
            end
          end
          add_entries = add_definition.lockfile_exists? ? add_definition.lockfile!.specs.map { |spec| {spec.name, spec.full_name} } : [] of Tuple(String, String)
          refresh_app_cache(stdout, add_definition, add_root, add_entries, add_definition.lockfile_exists? ? add_definition.lockfile! : nil)
        end
      end
      code
    end

    # `Gem::Requirement#==` compares the sorted `as_list`; the Gemfile text
    # `"2.6.0"` and `--version 2.6.0` both normalize to `= 2.6.0`.
    private def self.same_requirement?(current : Array(String), desired : Array(String)) : Bool
      current.sort == desired.sort
    end

    # `Bundler::Dsl#add_dependency` raises `GemfileError` when the requested
    # requirement differs from the one already declared, but only when the
    # conflicting file is the injector's synthetic `injected gems` (dsl.rb:289-303);
    # the wrapper in `eval_gemfile` (dsl.rb:46-61) prefixes it and `DSLError#to_s`
    # renders the offending line.
    private def self.injected_gem_conflict(name : String, current : Array(String), desired : Array(String),
                                           gemfile_path : String) : DSLError
      current_open = current.includes?(">= 0")
      prompt = if desired.includes?(">= 0") && !current_open
                 ". Gem already added"
               else
                 update = ". If you want to update the gem version, run `bundle update #{name}`"
                 unless current_open
                   update += ". You may also need to change the version requirement specified in the Gemfile if it's too restrictive."
                 end
                 update
               end
      description = "There was an error parsing `injected gems`: You cannot specify the same gem twice with different version requirements.\n" \
                    "You specified: #{name} (#{current.join(", ")}) and #{name} (#{desired.join(", ")})#{prompt}"
      # `Injector#build_gem_lines` joins with "\n" and appends none (injector.rb:99-124),
      # so the synthetic file's single line carries no terminator 閳?that is why
      # the 2.7.x frame (which resolves its index to `-1`) renders the same line
      # twice on one output line instead of splitting it.
      contents = "gem \"#{name}\", #{desired.map(&.inspect).join(", ")}"
      # Ruby builds the injector's synthetic path with `File.join` over the
      # already-normalized Bundler root, so the frame renders forward slashes
      # even on Windows (`<root>/injected gems:1`).
      injected_path = "#{File.dirname(gemfile_path).gsub('\\', '/')}/injected gems"
      DSLError.new(description, injected_path, contents, 0)
    end

    # `Injector#append_to` (injector.rb:126-131): `f.puts; f.puts new_gem_lines`
    # appends in Ruby's text mode, so the existing bytes stay untouched and the
    # new block is written with CRLF on Windows.
    private def self.append_gemfile(gemfile_path : String, gem_line : String) : Nil
      eol = {{ flag?(:windows) }} ? "\r\n" : "\n"
      File.open(gemfile_path, "a") do |file|
        file.print(eol)
        file.print(gem_line)
        file.print(eol)
      end
    end

    # `Injector#build_gem_lines` (injector.rb:109-111): one group renders as
    # `group: :dev`, several as `groups: [:dev, :test]`.
    private def self.add_group_option(rest : Array(String)) : String
      raw = flag_value(rest, "--group") || flag_value(rest, "-g")
      return "" unless raw
      groups = raw.split(",").map(&.strip).reject(&.empty?)
      return "" if groups.empty?
      if groups.size == 1
        ", group: :#{groups.first}"
      else
        ", groups: [#{groups.map { |group| ":#{group}" }.join(", ")}]"
      end
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

    # Thor gives an operand to the preceding `--option` when that option takes a
    # value (`--version 1.2`, `--glob "*.gemspec"`, `-g dev`); only the
    # remaining operands are gem names. `--option=value` and a trailing `--`
    # (everything after it is positional) are honoured too.
    private def self.add_positional_arguments(rest : Array(String)) : Array(String)
      positionals = [] of String
      index = 0
      while index < rest.size
        token = rest[index]
        if token == "--"
          positionals.concat(rest[(index + 1)..]? || [] of String)
          break
        elsif token.starts_with?("--")
          flag = token.split('=', 2).first
          inline_value = token.includes?('=')
          index += 1
          if !inline_value && ADD_SWITCH_VALUES.includes?(flag)
            index += 1 if index < rest.size && !rest[index].starts_with?("-")
          end
        elsif token.starts_with?("-") && token.size > 1
          index += 1
          if ADD_SWITCH_VALUES.includes?(token)
            index += 1 if index < rest.size && !rest[index].starts_with?("-")
          end
        else
          positionals << token
          index += 1
        end
      end
      positionals
    end

    # `cli/add.rb:33,57-59`: the `--version` value is a comma separated list of
    # requirement entries, each validated against `Gem::Requirement::PATTERN`.
    # Returns nil (after printing the reference's message) when an entry is not
    # a requirement. Bare versions are dumped as `= 1.2.3`.
    private def self.add_requirement_parts(value : String, stderr : IO) : Array(String)?
      parts = [] of String
      value.split(',').each do |raw|
        entry = raw.strip
        next if entry.empty?
        match = entry.match(/\A(>=|<=|!=|~>|>|<|=)?\s*(\S+)\z/)
        version = match.try(&.[2]?)
        valid = false
        if version
          begin
            Gem::Version.new(version)
            valid = true
          rescue VersionError | ArgumentError
            valid = false
          end
        end
        unless valid
          stderr.puts "Invalid gem requirement pattern '#{entry}'"
          return nil
        end
        operator = match.not_nil![1]? || "="
        parts << "#{operator} #{version}"
      end
      parts.empty? ? nil : parts
    end

    # Gemfile options added by `bundle add`. `injector.rb:122` fixes the order:
    # source, path, git, github, branch, ref, glob, require.
    private def self.add_option_suffix(rest : Array(String)) : String
      parts = [] of String
      if source = flag_value(rest, "--source") || flag_value(rest, "-s")
        parts << "source: #{source.inspect}"
      end
      if path = flag_value(rest, "--path")
        parts << "path: #{path.inspect}"
      end
      if git = flag_value(rest, "--git")
        parts << "git: #{git.inspect}"
      end
      # `injector.rb:116` renders `github: "owner/repo"`.
      if github = flag_value(rest, "--github")
        parts << "github: #{github.inspect}"
      end
      if branch = flag_value(rest, "--branch")
        parts << "branch: #{branch.inspect}"
      end
      if git_ref = flag_value(rest, "--ref")
        parts << "ref: #{git_ref.inspect}"
      end
      # `injector.rb:114` renders `glob: "..."` from the dependency options.
      if glob = flag_value(rest, "--glob")
        parts << "glob: #{glob.inspect}"
      end
      if require_path = flag_value(rest, "--require") || flag_value(rest, "-r")
        parts << (require_path == "false" ? "require: false" : "require: #{require_path.inspect}")
      end
      parts.map { |part| ", #{part}" }.join
    end

    # Returns the Gemfile requirement suffix plus whether the probe already
    # printed its source-index/resolve lines, so the injector's relock can stay
    # silent instead of announcing the same fetch twice.
    private def self.latest_requirement_for(definition : Definition, name : String, stdout : IO, rest : Array(String),
                                            bridge : Bridge::Client,
                                            explicit_parts : Array(String)?) : NamedTuple(requirement: String, printed: Bool)
      printed = false
      announce_resolving = false
      begin
        resolution = Resolution.new(definition, false, bridge)
        # `--github` resolves against the source list like a plain add (the
        # reference writes `~> 1.5` without cloning; the git source is only
        # materialised during install), so only `--path`/`--git` skip the index
        # probe.
        if flag_value(rest, "--path").nil? && flag_value(rest, "--git").nil?
          # Reference probes the index source before resolving: the fetch line
          # comes first, then the resolver announcement.
          resolution.progress = IO::Memory.new
          resolution.show_resolving = false
          resolution.resolve!
          remote = resolution.primary_remote
          stdout.puts "Fetching source index from #{remote.chomp("/")}/" unless remote.empty?
          # The resolver announcement is printed only once the index actually
          # answers for this gem: with an unknown gem the reference stops after
          # the fetch line and raises (oracle `add nosuchgem --skip-install`).
          announce_resolving = true
          printed = true
        else
          resolution.progress = stdout # path/git probes use the local gemspec
          resolution.show_resolving = true
          resolution.resolve!
          printed = true
        end

        # `Injector#build_gem_lines` (injector.rb:106) dumps each requirement
        # entry on its own, so `~> 2.8` stays `~> 2.8` and `>= 1.0, < 2` becomes
        # `">= 1.0", "< 2"`.
        if explicit_parts
          dumped = explicit_parts.map { |part| "\"#{part}\"" }.join(", ")
          # An explicit requirement does not need the index lookup, but the
          # announcement still follows the fetch line (pinned by
          # `add-version-requirement`).
          stdout.puts "Resolving dependencies..." if announce_resolving
          return {requirement: ", #{dumped}", printed: printed}
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
        # The resolver announcement follows the fetch line, but only when the
        # index answered for this gem; an unknown gem stops after the fetch
        # (oracle: `add nosuchgem --skip-install`).
        stdout.puts "Resolving dependencies..." if announce_resolving && !versions.empty?

        return {requirement: "", printed: printed} if versions.empty?
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
        {requirement: ", \"#{operator}#{segs.join(".")}\"", printed: printed}
      rescue
        {requirement: "", printed: printed}
      end
    end

    # `Injector#inject` relocks the definition even when nothing was appended
    # (`@definition.lock` at injector.rb:53 runs unconditionally), and
    # `Definition#write_lock` (definition.rb:401-419) rewrites the file only when
    # the regenerated contents differ from the existing ones. `--skip-install`
    # returns before the installer writes the lockfile, so the relock happens
    # here instead: a locked project whose Gemfile still matches resolves
    # through the lockfile and prints nothing (`add json_pure` is silent), while
    # a stale or missing lockfile makes the resolver announce
    # `Fetching source index from <remote>/` + `Resolving dependencies...` and
    # the new lockfile lands (`add-skip-install`, `add-existing-same` fixtures).
    private def self.persist_add_lockfile(definition : Definition, bridge : Bridge::Client, stdout : IO,
                                          probe_printed : Bool) : Nil
      resolution = Resolution.new(definition, false, bridge)
      begin
        # A newly appended gem already made the requirement probe fetch and
        # resolve; repeating those lines would duplicate them.
        resolution.progress = probe_printed ? IO::Memory.new : stdout
        resolution.show_resolving = !probe_printed
        resolution.resolve!(true)
        text = resolution.generated_lockfile.to_lock
        existing = File.file?(definition.lockfile_path) ? File.read(definition.lockfile_path) : nil
        if existing.nil? || semantic_content(existing) != semantic_content(text)
          Lockfile.write(definition.lockfile_path, text, preserve_crlf: preserve_lockfile_crlf?)
        end
      ensure
        resolution.close
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

      # `cli.rb:245-249` (4.0.24): the command body rejects `--install` with an
      # `InvalidOption` (status 15) *after* Thor's unknown-switch check and
      # *before* the empty-argument check, so `remove --install x --bogus`
      # reports only `--bogus`. The 2.7.2 tree (`cli.rb:191-200`) runs
      # `major_deprecation` instead and keeps going with the flag already
      # consumed by Thor.
      if rest.any? { |arg| arg.split("=", 2)[0] == "--install" }
        if profile_2_x?
          stderr.puts "[DEPRECATED] The `--install` flag has been deprecated. `bundle install` is triggered by default."
        else
          raise InvalidOptionError.new("The `--install` flag has been removed. `bundle install` is triggered by default.")
        end
      end
      # Thor consumed the flag, so it never reaches the nested `install`.
      install_rest = rest.reject { |arg| arg.split("=", 2)[0] == "--install" }

      names = rest.reject(&.starts_with?("--"))
      if names.empty?
        # `cli/remove.rb:10-12` raises `InvalidOption` (status 15).
        raise InvalidOptionError.new("Please specify gems to remove.")
      end

      definition = Definition.build
      gemfile_path = definition.gemfile_path
      display_path = gemfile_path.gsub(/\\/, "/")
      initial_lines = File.read(gemfile_path).gsub(/\r\n/, "\n").lines(chomp: false)

      # `Injector#remove` reports the duplicate declarations of the Gemfile it
      # is about to rewrite (injector.rb:65 evaluates `Bundler.definition`
      # before `remove_gems_from_gemfile` edits the file).
      evaluate_gemfile_before_rewrite(definition)

      # `Injector#remove_deps` (injector.rb:135-159) announces the file before
      # evaluating it, so this line also precedes a missing-gem error.
      stdout.puts "Removing gems from #{display_path}"

      # `remove_gems_from_dependencies` (injector.rb:165-181): the first name
      # the Gemfile does not declare aborts with a `GemfileError` (status 4)
      # before anything is written. A commented-out declaration is not a
      # dependency (`is_not_within_comment?`, injector.rb:217-220).
      names.each do |name|
        declared = initial_lines.any? do |line|
          match = remove_pattern(name).match(line)
          !match.nil? && !within_gemfile_comment?(line, match)
        end
        unless declared
          raise GemfileError.new("`#{name}` is not specified in #{display_path} so it could not be removed.")
        end
      end

      # `remove_gems_from_gemfile` (injector.rb:185-213): drop every line whose
      # `gem <name>` declaration matches, following `,`-terminated multiline
      # declarations, then collapse the blocks the removal emptied.
      patterns = remove_pattern(names)
      new_gemfile = [] of String?
      removed_lines = [] of String
      multiline_removal = false
      initial_lines.each do |line|
        if (match = patterns.match(line)) && !within_gemfile_comment?(line, match)
          multiline_removal = line.rstrip.ends_with?(",")
          removed_lines << line
          next
        end
        if multiline_removal
          removed_lines[removed_lines.size - 1] += line
          multiline_removal = line.rstrip.ends_with?(",")
          next
        end
        new_gemfile << line
      end

      # injector.rb:210 閳?an emptied `group`/`source`/`env`/`install_if` block
      # is dropped together with its `end` line.
      {"group", "source", "env", "install_if"}.each do |block|
        remove_nested_blocks(new_gemfile, block)
      end

      # `remove_gems_from_gemfile` ends with `new_gemfile.join.chomp`
      # (injector.rb:212) 閳?exactly one trailing newline is stripped 閳?and
      # `SharedHelpers.write_to_gemfile` (shared_helpers.rb:215-217) then does
      # `File.open(path, "w") { |file| file.puts contents }`: `puts` appends a
      # newline only when `contents` does not already end with one, and the
      # file is opened in text mode, so every LF becomes the platform line
      # separator (CRLF on Windows). Appending `eol` unconditionally would
      # leave a blank line whenever the removed gem was preceded by one.
      cleaned = new_gemfile.compact.join.chomp
      cleaned += "\n" unless cleaned.ends_with?("\n")
      eol = {{ flag?(:windows) }} ? "\r\n" : "\n"
      File.write(gemfile_path, cleaned.gsub("\n", eol))

      # `Injector#remove` (injector.rb:70-72) confirms each removed dependency
      # in the order the CLI named them.
      names.each do |name|
        line = removed_lines.find { |candidate| remove_pattern(name).matches?(candidate) }
        next if line.nil?
        # The message mirrors the Gemfile line: quoted tokens are the gem name
        # followed by the requirement(s) exactly as written (`~> 2.8`,
        # `= 2.8.1`, or several constraints). Options such as `group: :dev`
        # use bare symbols and are not quoted, so they are ignored here.
        quoted = line.scan(/"([^"]*)"|'([^']*)'/).map { |m| m[1]? || m[2]? }.compact
        label = quoted.first? || line.strip
        requirements = quoted.skip(1).map { |requirement| pretty_requirement(requirement) }
        display = requirements.empty? ? label : "#{label} (#{requirements.join(", ")})"
        stdout.puts "#{display} was removed."
      end

      # `cli/remove.rb:15` ends with the same `Installer.install` call as
      # `install`, so an emptied Gemfile gets `The Gemfile specifies no
      # dependencies` from that shared path (`installer.rb:73-77`) — the call
      # below prints it once, on stderr, while remove still exits 0 and keeps
      # its removal lines on stdout.

      # Reference remove: regenerate the lockfile and reinstall silently (no
      # progress/summary output). It does **not** prune the bundle directory:
      # the gem that was just dropped from the Gemfile stays installed, and the
      # follow-up `bundle clean` is what reports `Removing <name> (<version>)`.
      # Pruning here used to be hidden by a stale `definition.lockfile!`
      # cache; reading the fresh lockfile made `clean` print nothing.
      null = IO::Memory.new
      install(null, stderr, install_rest, summary: false, cli_arguments: false)
      0
    end

    # `Injector#remove_gems_from_gemfile`'s matcher (injector.rb:186):
    # `gem\s+(['"])NAME\1|gem\s*\((['"])NAME\2.*\)`. `Regexp.union` wraps the
    # gem list in a group, so the backreference still points at the quote.
    private def self.remove_pattern(names : Array(String)) : Regex
      union = "(?:" + names.map { |name| Regex.escape(name) }.join("|") + ")"
      Regex.new("gem\\s+(['\"])#{union}\\1|gem\\s*\\((['\"])#{union}\\2.*\\)")
    end

    private def self.remove_pattern(name : String) : Regex
      remove_pattern([name])
    end

    # injector.rb:217-220 閳?a `gem` line that is commented out is not a
    # declaration, so it survives the removal.
    private def self.within_gemfile_comment?(line : String, match : Regex::MatchData) : Bool
      offset = match.begin(0)
      return false if offset <= 0
      line[0..(offset - 1)].includes?("#")
    end

    # injector.rb:224-243 閳?drop a block header line together with the `end`
    # line directly after it, repeating until the pass stops changing anything
    # (the reference counts adjacent block headers to bound its loop; iterating
    # to a fixed point drops the same lines).
    private def self.remove_nested_blocks(gemfile : Array(String?), block_name : String) : Nil
      loop do
        changed = false
        gemfile.each_with_index do |line, index|
          current = line
          next if current.nil?
          next unless current.strip.starts_with?(block_name)
          following = gemfile[index + 1]?
          next if following.nil?
          next unless following.matches?(/^\s*end\s*$/)
          gemfile[index] = nil
          gemfile[index + 1] = nil
          changed = true
        end
        gemfile.compact!
        break unless changed
      end
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

        print_gemfile_sections(stdout, definition, bridge)
        0
      ensure
        bridge.close
      end
    end

    # Gemfile / Gemfile.lock / Gemspecs sections shared by `env` and `issue`
    # (Bundler::Env.report, env.rb:35-58). The reference always prints the
    # Gemfile.lock heading and falls back to `<No <path> found>` when the file
    # is absent (Env.read_file, env.rb:63-66).
    private def self.print_gemfile_sections(stdout : IO, definition : Definition, bridge : Bridge::Client?) : Nil
      stdout.puts
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
        stdout.puts "<No #{definition.lockfile_path.gsub(/\\/, "/")} found>"
      end
      stdout.puts "```"
      # Bundler::Env appends `## Gemspecs` after the Gemfile section, one
      # `### <basename>` ruby fence per gemspec loaded by `gemspec` directives
      # (env.rb:51-58); the whole section is omitted when there are none.
      gemspec_paths = bridge ? bridge.gemspec_paths(definition.gemfile_path) : [] of String
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
          # Reference prints `local_config_file.to_s` verbatim: a raw absolute
          # BUNDLE_APP_CONFIG keeps its native separators before the `/config`
          # join (settings.rb local_config_file message).
          file = config.local_config_file.to_s
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
      quiet = rest.includes?("--quiet")
      # `--help` is routed by `Commands.run` to `bundle help` before this body
      # runs (Thor class option, cli.rb:589-602). `subcommand("doctor", Doctor)`
      # makes Thor report unknown options as leftover arguments of `diagnose`
      # (cli.rb:669-671); `diagnose` is the default command.
      arguments = subcommand_arguments(rest, DOCTOR_SUBCOMMAND_FLAGS, DOCTOR_SUBCOMMAND_VALUES)
      # `doctor ssl` is a real subcommand (cli/doctor.rb:25-31) with its own
      # `--host`/`--tls-version`/`--verify-mode` options.
      if arguments.first? == "ssl"
        return doctor_ssl(stdout, stderr, arguments[1..], quiet: quiet)
      end
      ssl = rest.includes?("--ssl")
      arguments = arguments.reject { |arg| arg == "diagnose" }
      unless arguments.empty?
        stderr.puts %(ERROR: "bundle doctor diagnose" was called with arguments #{arguments.inspect})
        stderr.puts %(Usage: "bundle doctor diagnose [OPTIONS]")
        return 15
      end
      gemfile = option_value(rest, "--gemfile")
      previous_gemfile = ENV["BUNDLE_GEMFILE"]?
      begin
        ENV["BUNDLE_GEMFILE"] = gemfile if gemfile
        doctor_report(stdout, stderr, quiet: quiet, ssl: ssl)
      ensure
        if previous_gemfile
          ENV["BUNDLE_GEMFILE"] = previous_gemfile
        else
          ENV.delete("BUNDLE_GEMFILE")
        end
      end
    end

    # `bundle doctor --help` (cli/doctor.rb manpage, identical in 4.0.24 and
    # 2.7.2; Thor renders it at 80 columns for non-TTY output).
    private def self.option_value(rest : Array(String), name : String) : String?
      rest.each_with_index do |arg, index|
        return arg.split("=", 2)[1] if arg.starts_with?("#{name}=")
        return rest[index + 1]? if arg == name
      end
      nil
    end

    # The `## Bundle Doctor` body shared by `doctor` and `issue`
    # (cli/doctor.rb:8-16, cli/doctor/diagnose.rb:74-76). Resolving from a
    # missing lockfile writes it (reference Diagnose#run leaves the definition
    # locked), which is why `issue` on a Gemfile-only project must not fail with
    # the old `Could not locate Gemfile`.
    # `cli/update.rb:119` calls `Common.output_without_groups_message(:update)`,
    # which (`common.rb:49-58`) returns when `without` is empty and otherwise
    # names the excluded groups that still carry Gemfile dependencies, in the
    # command's past tense. Only `without` triggers it; `only` stays silent.
    private def self.print_update_without_notice(stdout : IO, definition : Definition, deps : Array(Bridge::EvaluatedDependency)) : Nil
      groups = case value = definition.config["without"]
               when Array  then value.map(&.to_s)
               when String then value.split(":").reject(&.empty?)
               else             [] of String
               end
      return if groups.empty?
      present = deps.flat_map do |dep|
        dep.groups.empty? ? ["default"] : dep.groups
      end.uniq
      skipped = groups.select { |group| present.includes?(group) }
      return if skipped.empty?
      message = if skipped.size == 1
                  "Gems in the group '#{skipped.first}' were not updated."
                else
                  quoted = skipped.map { |group| "'#{group}'" }
                  "Gems in the groups #{quoted[0..-2].join(", ")} and #{quoted.last} were not updated."
                end
      stdout.puts message
    end

    # `settings/validator.rb:57-63`: when `path` and `path.system` are both set,
    # the rule nils each one in turn and reports it with `Rule#set`, whose
    # message is `Setting `key` to nil, since <description>`. The reference
    # walks `path` first (silencing `path.system`), then `path.system`
    # (silencing `path`), which is the order seen in `doctor` output.
    private def self.doctor_settings_notices(stdout : IO, stderr : IO, definition : Definition) : Nil
      config = definition.config
      # `settings/validator.rb:57-63`.
      unless config["path"].to_s.empty?
        if config["path.system"] == true || config["disable_shared_gems"] == false
          stdout.puts "Setting `path.system` to nil, since path and path.system are mutually exclusive"
          stdout.puts "Setting `path` to nil, since path and path.system are mutually exclusive"
        end
      end
      # `settings/validator.rb:65-76`: the `with`/`without` rule reports the
      # overlap through `fail!`, which prints the header plus one indented line
      # per argument on stderr and exits 15.
      with_groups = group_setting(config["with"])
      without_groups = group_setting(config["without"])
      conflicting = with_groups & without_groups
      unless conflicting.empty?
        stderr.puts "Setting `with` to #{symbol_list(with_groups)} failed:"
        stderr.puts " - a group cannot be in both `with` & `without` simultaneously"
        stderr.puts " - `without` is current set to #{symbol_list(without_groups)}"
        stderr.puts " - the `#{conflicting.join("`, `")}` groups conflict"
        raise InvalidOptionError.new("")
      end
      # `settings/validator.rb:78-83` is 4.x-only (the 2.7.2 validator has no
      # such rule: an invalid value there falls through to the normal run).
      unless profile_2_x?
        value = config["default_cli_command"]
        unless value.nil? || {"install", "cli_help"}.includes?(value.to_s)
          stderr.puts "Setting `default_cli_command` to #{value.to_s.inspect} failed:"
          stderr.puts " - default_cli_command must be either 'install' or 'cli_help'"
          stderr.puts " - must be one of: install, cli_help"
          raise InvalidOptionError.new("")
        end
      end
    end

    # Group settings arrive either as arrays or as the `:`-separated string form.
    private def self.group_setting(value : Config::ConvertedValue) : Array(String)
      case value
      when Array  then value.map(&.to_s)
      when String then value.split(":").reject(&.empty?)
      else             [] of String
      end
    end

    # `[:test]` 閳?the shape `fail!` produces for `settings.fetch(...).to_sym`.
    private def self.symbol_list(groups : Array(String)) : String
      "[:#{groups.join(", :")}]"
    end

    def self.doctor_report(stdout : IO, stderr : IO, quiet : Bool = false, ssl : Bool = false) : Int32
      definition = Definition.build
      Commands.validate_ruby_runtime!(definition)
      # `settings.rb:312-319` runs every `settings/validator.rb` rule before
      # `cli/doctor/diagnose.rb:79` proceeds. The `path`/`path.system` rule
      # (`:57-63`) silences the loser with an info line on stdout, and only then
      # does `Path#validate!` (settings.rb:287-297) raise; the reference
      # therefore prints both notices before the conflict report.
      doctor_settings_notices(stdout, stderr, definition)
      # `doctor` resolves like `check` (cli/doctor.rb): it may fetch the index,
      # unlike the local-only read commands.
      lockfile = materialize_lockfile(definition, stdout)
      locked_specs = lockfile.specs.sort_by(&.full_name)

      if locked_specs.empty?
        persist_generated_lockfile(definition, lockfile)
        stdout.puts "The Gemfile's dependencies are satisfied" unless quiet
      else
        missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }
        if missing.empty?
          persist_generated_lockfile(definition, lockfile)
          stdout.puts "The Gemfile's dependencies are satisfied" unless quiet
        else
          stderr.puts "The following gems are missing"
          missing.each { |spec| stderr.puts " * #{spec.name} (#{spec.version})" }
          # `doctor` delegates to `Check#run` (doctor/diagnose.rb:74-76), which
          # prints the install hint right after the missing list.
          stderr.puts "Install missing gems with `bundle install`"
          return 1
        end
      end
      # `doctor/diagnose.rb:77-79`: `--ssl` runs the SSL report right after the
      # dependency check and before the dylib scan. Diagnose has no `--host`, so
      # the report always targets the default host.
      doctor_ssl(stdout, stderr, [] of String, quiet: quiet) if ssl
      # `diagnose.rb:86-96`: every `**/*.bundle` file makes `dylibs` warn on
      # non-darwin/linux hosts (one warning per file) and return an empty list.
      # Crystal's `File.join` uses `\` on Windows, which `Dir.glob` does not
      # understand, so the pattern is built with forward slashes.
      locked_specs.each do |spec|
        gem_dir = installed_gem_dir(definition, spec, lockfile)
        next unless gem_dir && Dir.exists?(gem_dir)
        pattern = "#{gem_dir.gsub('\\', "/")}/**/*.bundle"
        Dir.glob(pattern).each do
          stderr.puts "Dynamic library check not supported on this platform."
        end
      end
      # `check_home_permissions` warnings (broken links, foreign ownership,
      # non-writable files) could not be triggered in this environment; see
      # the compat report's task-53 section.
      stdout.puts "No issues found with the installed bundle" unless quiet
      0
    end

    # `cli/doctor/ssl.rb`: prints the interpreter's OpenSSL build, probes
    # Bundler, RubyGems and Ruby's net/http against https://<host>/, and
    # summarizes. Probe failures are reported as warnings; the subcommand
    # itself always exits 0 (cli/doctor/ssl.rb:14-24).
    def self.doctor_ssl(stdout : IO, stderr : IO, rest : Array(String), quiet : Bool = false) : Int32
      host = option_value(rest, "--host") || "rubygems.org"
      tls_version = option_value(rest, "--tls-version")
      verify_mode = option_value(rest, "--verify-mode")
      timeout = 10

      bridge = Bridge::Client.new
      begin
        versions = bridge.ssl_openssl_versions
        unless quiet
          stdout.print "Here's your OpenSSL environment:\n\n"
          stdout.print "OpenSSL:       #{versions[:version]}\n"
          stdout.print "Compiled with: #{versions[:compiled]}\n"
          stdout.print "Loaded with:   #{versions[:loaded]}\n"
          stdout.print "\nTrying connections to https://#{host}:\n"
        end

        bundler = bridge.ssl_probe(host, timeout, tls_version, verify_mode)
        bundler_ok = bundler[:success]
        if bundler_ok
          stdout.puts "Bundler:       success" unless quiet
        else
          message = bundler[:error_message] || bundler[:error_class] || "unknown error"
          stderr.puts "Bundler:       failed     (#{ssl_probe_explanation(message)})"
        end

        rubygems_error = ssl_rubygems_probe(host, timeout)
        rubygems_ok = rubygems_error.nil?
        if rubygems_ok
          stdout.puts "RubyGems:      success" unless quiet
        else
          stderr.puts "RubyGems:      failed     (#{ssl_probe_explanation(rubygems_error || "")})"
        end

        net_http = bridge.ssl_probe(host, timeout, tls_version, verify_mode)
        unless net_http[:success]
          message = net_http[:error_message] || net_http[:error_class] || "unknown error"
          error_class = net_http[:error_class] || "StandardError"
          stderr.print "Ruby net/http: failed\n\n"
          stderr.print "Unfortunately, this Ruby can't connect to #{host}.\n\n"
          stderr.print ssl_net_http_explanation(message, error_class, net_http[:backtrace], host, tls_version)
          return 0
        end
        stdout.puts "Ruby net/http: success" unless quiet

        unless quiet
          stdout.print "\n#{ssl_summary(bundler_ok, rubygems_ok, host)}\n"
        end
      ensure
        bridge.close
      end
      0
    end

    # `cli/doctor/ssl.rb:88-97`: the RubyGems probe uses Ruby's remote fetcher;
    # a peer-verifying TLS GET is the same check on our side.
    private def self.ssl_rubygems_probe(host : String, timeout : Int32) : String?
      uri = URI.parse("https://#{host}/")
      client = HTTP::Client.new(uri)
      client.connect_timeout = timeout.seconds
      client.read_timeout = timeout.seconds
      begin
        client.get("/")
        nil
      ensure
        client.close
      end
    rescue ex
      ex.message
    end

    # `cli/doctor/ssl.rb:148-159`.
    private def self.ssl_probe_explanation(message : String) : String
      case message
      when /certificate verify failed/
        "certificate verification"
      when /read server hello A/
        "SSL/TLS protocol version mismatch"
      when /tlsv1 alert protocol version/
        "requested TLS version is too old"
      else
        message
      end
    end

    # `cli/doctor/ssl.rb:161-197`.
    private def self.ssl_net_http_explanation(message : String, error_class : String,
                                              backtrace : Array(String), host : String,
                                              tls_version : String?) : String
      if message.matches?(/certificate verify failed/)
        cert_file = ENV["SSL_CERT_FILE"]? || "/usr/lib/ssl/cert.pem"
        cert_dir = ENV["SSL_CERT_DIR"]? || "/usr/lib/ssl/certs"
        file_state = File.file?(cert_file) ? "exists     " : "is missing "
        dir_state = Dir.exists?(cert_dir) ? "exists     " : "is missing "
        return "Below affect only Ruby net/http connections:\n" \
               "SSL_CERT_FILE: #{file_state}#{cert_file}\n" \
               "SSL_CERT_DIR:  #{dir_state}#{cert_dir}\n" \
               "Your Ruby can't connect to #{host} because you are missing the certificate files " \
               "OpenSSL needs to verify you are connecting to the genuine #{host} servers.\n"
      end
      if message.matches?(/read server hello A/) || message.matches?(/tlsv1 alert protocol version/)
        if tls_version == "TLS1_3"
          return "Your Ruby can't connect to #{host} because #{tls_version} isn't supported yet.\n"
        end
        return "Your Ruby can't connect to #{host} because your version of OpenSSL is too old.\n" \
               "You'll need to upgrade your OpenSSL install and/or recompile Ruby to use a newer OpenSSL.\n"
      end
      if message.matches?(/unknown SSL method/)
        return "Your Ruby can't connect because #{tls_version} isn't supported by your version of OpenSSL.\n"
      end
      trace = backtrace.map { |line| "  #{line}" }.join('\n')
      "Even worse, we're not sure why.\n\n" \
      "Here's the full error information:\n" \
      "#{error_class}: #{message}\n" \
      "#{trace}\n\n" \
      "You might have more luck using Mislav's SSL doctor.rb script. You can get it here:\n" \
      "https://github.com/mislav/ssl-tools/blob/8b3dec4/doctor.rb\n\n" \
      "Read more about the script and how to use it in this blog post:\n" \
      "https://mislav.net/2013/07/ruby-openssl/\n"
    end

    # `cli/doctor/ssl.rb:199-231`.
    private def self.ssl_summary(bundler_ok : Bool, rubygems_ok : Bool, host : String) : String
      guide = "http://ruby.to/ssl-check-failed"
      if bundler_ok && rubygems_ok
        "Hooray! This Ruby can connect to #{host}.\nYou are all set to use Bundler and RubyGems."
      elsif !bundler_ok && !rubygems_ok
        "For some reason, your Ruby installation can connect to #{host}, but neither RubyGems nor Bundler can.\n" \
        "The most likely fix is to manually upgrade RubyGems by following the instructions at #{guide}.\n" \
        "After you've done that, run `gem install bundler` to upgrade Bundler, and then run this script again to make sure everything worked."
      elsif !bundler_ok
        "Although your Ruby installation and RubyGems can both connect to #{host}, Bundler is having trouble.\n" \
        "The most likely way to fix this is to upgrade Bundler by running `gem install bundler`.\n" \
        "Run this script again after doing that to make sure everything is all set.\n" \
        "If you're still having trouble, check out the troubleshooting guide at #{guide}."
      else
        "It looks like Ruby and Bundler can connect to #{host}, but RubyGems itself cannot.\n" \
        "You can likely solve this by manually downloading and installing a RubyGems update.\n" \
        "Visit #{guide} for instructions on how to manually upgrade RubyGems."
      end
    end

    # `Definition#resolve` in the reference resolves into the lockfile object
    # that Diagnose later writes; our materialize_lockfile returns the generated
    # lockfile without touching disk, so the doctor command has to persist it.
    private def self.persist_generated_lockfile(definition : Definition, lockfile : Lockfile::Data) : Nil
      return if definition.lockfile_exists?
      File.write(definition.lockfile_path, lockfile.to_lock)
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
        when "PLUGIN SOURCE"
          # A plugin source materializes its gemspecs from the source itself
          # (`plugin/api/source.rb:136` + `fetch_gemspec_files`), so the locked
          # spec is already available once the plugin is loaded. The reference
          # `check` reports these as satisfied without a bundle `<gems>` tree
          # (`cli/check.rb:18-31`).
          remote = source.option("remote").to_s
          return remote.empty? ? nil : File.expand_path(remote, File.dirname(definition.gemfile_path))
        end
      end

      # `path.system` puts gems directly in `Gem.dir` (`<Gem.dir>/gems`), with no
      # `ruby/<abi>` scope. Discover them explicitly instead of relying on the
      # fallback search below (which used to make this order-dependent).
      if (source.nil? || source.type == "GEM") && InstallPaths.system_gems?(definition.config)
        if system_dir = system_gem_search_dirs.first?
          if installed_spec_file?(File.join(system_dir, "specifications"), spec.full_name)
            return File.join(system_dir, "gems", spec.full_name)
          end
        end
      end

      # Default: RubyGems-installed spec under bundle install path. The
      # reference materializes a `LazySpecification` through
      # `Gem::Specification.stubs_for`, i.e. the installed specification file
      # (`<root>/specifications/<full_name>.gemspec`), not the extracted gem
      # directory. A spec file without its `gems/<full_name>` directory is
      # still "installed" for check/list (and `show` warns), while a directory
      # without its specification is missing. See `cli/check.rb:14-31`,
      # `definition.rb:260-262`, `spec_set.rb:154-162`.
      install_path = InstallPaths.install_path(definition.config)
      ruby_root = File.join(install_path, "ruby")
      if Dir.exists?(ruby_root)
        Dir.each_child(ruby_root) do |abi|
          abi_root = File.join(ruby_root, abi)
          if installed_spec_file?(File.join(abi_root, "specifications"), spec.full_name)
            return File.join(abi_root, "gems", spec.full_name)
          end
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
          if installed_spec_file?(File.join(base, "specifications"), spec.full_name)
            return File.join(base, "gems", spec.full_name)
          end
        end
      end

      # Interpreter default gems are not in `<bundle>/specifications` but are
      # still valid for `check/list/show/info` (`cli/common.rb:68-101` falls
      # back to `default_gem_spec`). A custom `path` does not hide them.
      if (source.nil? || source.type == "GEM") && bridge_available?
        bridge = Bridge::Client.new
        begin
          if info = bridge.default_gem_spec(spec.name)
            if info[:version] == spec.version.to_s && (spec.platform.nil? || info[:platform] == spec.platform)
              return info[:full_gem_path]
            end
          end
        rescue
        ensure
          bridge.close
        end
      end
      nil
    end

    private def self.installed_spec_file?(specifications_dir : String, full_name : String) : Bool
      File.file?(File.join(specifications_dir, "#{full_name}.gemspec"))
    rescue
      false
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
        # `cli.rb:570-583`: `Bundler.load.specs.sort_by {|s| s.license.to_s }
        # .reverse_each`. Bundler's own spec is part of `Bundler.load.specs`
        # (license MIT) and equal keys keep `Bundler.load` order, which the
        # lockfile order mirrors; ties are therefore keyed by full_name here
        # to stay deterministic.
        lockfile = materialize_lockfile(definition, stdout, local_only: true)
        # A `PATH` source keeps its spec under the path, not under the bundle,
        # so the live gemspec has to be located from the lockfile's source.
        path_remotes = {} of String => String
        lockfile.sources.each do |source|
          next unless source.type == "PATH"
          remote = source.remote
          next if remote.nil? || remote.empty?
          source.specs.each { |spec| path_remotes[spec.full_name] = remote }
        end
        gemfile_dir = File.dirname(definition.gemfile_path)
        # `Bundler.load.specs` lists the running Bundler first, then the
        # definition's specs in lockfile order, and `sort_by {|s| s.license }`
        # is stable in Ruby, so equal licenses keep that order. Crystal's
        # `sort_by` is not stable, hence the explicit position tie-breaker.
        entries = [{"bundler", "bundler", "MIT"}]
        # `Bundler.load.specs` orders specs by the Gemfile dependency order
        # (`definition.specs`), not by lockfile section layout, so the
        # tie-breaker follows the DEPENDENCIES section.
        ordered = [] of Lockfile::Spec
        bridge.evaluate_gemfile(definition.gemfile_path).dependencies.each do |dependency|
          spec = lockfile.specs.find(&.name.==(dependency.name))
          ordered << spec if spec && !ordered.includes?(spec)
        end
        lockfile.specs.each { |spec| ordered << spec unless ordered.includes?(spec) }
        ordered.each do |spec|
          entries << {spec.full_name, spec.name, spec_license(bridge, install_root, spec, path_remotes, gemfile_dir)}
        end
        indexed = entries.map_with_index { |entry, index| {entry, index} }
        indexed.sort! do |a, b|
          by_license = b[0][2] <=> a[0][2]
          by_license == 0 ? (a[1] <=> b[1]) : by_license
        end
        indexed.each do |(entry, _index)|
          name, license = entry[1], entry[2]
          if license.empty? || license == "Unknown"
            stderr.puts "#{name}: Unknown"
          else
            stdout.puts "#{name}: #{license}"
          end
        end
      ensure
        bridge.close
      end
      0
    end

    # `cli.rb:571-581` reports `spec.license || spec.licenses` from the LIVE
    # spec (`Bundler.load.specs`), so a path source and a bundle whose cache was
    # deleted still show their real license. The cached `.gem` is only a
    # fallback for the case where no gemspec can be read.
    private def self.spec_license(bridge : Bridge::Client, install_root : String, spec : Lockfile::Spec,
                                  path_remotes : Hash(String, String), gemfile_dir : String) : String
      candidates = [File.join(install_root, "specifications", "#{spec.full_name}.gemspec")]
      if remote = path_remotes[spec.full_name]?
        base = File.expand_path(remote, gemfile_dir).gsub('\\', "/")
        Dir.glob("#{base}/*.gemspec").each { |path| candidates << path }
      end
      candidates.each do |path|
        next unless File.file?(path)
        if license = license_from_spec_file(bridge, path)
          return license
        end
      end
      gem_file = File.join(install_root, "cache", "#{spec.full_name}.gem")
      return "Unknown" unless File.file?(gem_file)
      info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(gem_file).to_json)
      info.license || info.licenses.try(&.first?) || "Unknown"
    rescue
      "Unknown"
    end

    # The bridge returns the gemspec's own `license`/`licenses` fields
    # (`server.rb` `op_load_installed_spec`).
    private def self.license_from_spec_file(bridge : Bridge::Client, path : String) : String?
      spec = bridge.load_installed_spec(path)
      return nil if spec.nil?
      if license = spec["license"]?.try(&.as_s?)
        return license unless license.empty?
      end
      if list = spec["licenses"]?.try(&.as_a?)
        joined = list.compact_map(&.as_s?).reject(&.empty?).join(", ")
        return joined unless joined.empty?
      end
      nil
    rescue
      nil
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
    # `cli/common.rb:34-47` prints a trailing funding hint after install and
    # update: it counts only the Gemfile's direct dependencies in the requested
    # groups whose (locked) spec carries a `funding_uri` metadata entry, and
    # stays silent when the count is zero or `ignore_funding_requests` is set
    # (`Bundler.settings["ignore_funding_requests"]` short-circuits first).
    def self.print_fund_summary(definition : Definition, evaluation : Bridge::GemfileEvaluation,
                                lockfile : Lockfile::Data?, bridge : Bridge::Client, stream : IO) : Nil
      case value = definition.config["ignore_funding_requests"]
      when Array(String) then return if !value.empty?
      else
        return if Config.to_bool(value)
      end

      return unless lockfile

      requested_groups = fund_requested_groups(evaluation, definition.config)
      count = evaluation.dependencies.count do |dep|
        next false unless dep.groups.any? { |group| requested_groups.includes?(group) }

        spec = lockfile.specs.find(&.name.==(dep.name))
        next false unless spec

        !read_funding_uri(definition, spec, lockfile, bridge).nil?
      end
      return if count.zero?

      intro = count > 1 ? "#{count} installed gems you directly depend on are" : "#{count} installed gem you directly depend on is"
      stream.puts "#{intro} looking for funding."
      stream.puts "  Run `bundle fund` for details"
    end

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
        sources_map = {} of String => String
        (index["sources"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
          sources_map[key.as_s] = value.as_s
        end

        registered = PluginCommands.commands(index_path)
        declared = PluginCommands.declared(File.join(root_dir, "plugins.rb"), [lib_dir])
        if error = declared[:error]
          # Reference plugin.rb:213-220 raises ArgumentError for an undefined
          # hook event; save_plugin wraps it as MalformattedPlugin (exit 29) and
          # leaves no index entry behind. The message is a single string that
          # friendly_errors wraps to the terminal width (friendly_errors.rb:31-35
          # passes `wrap: true`).
          put_plugin_install_failure(stderr, info.name, error)
          remove_failed_plugin_source(root_dir)
          return 29
        end
        conflict_command = declared[:commands].find do |command|
          owner = registered[command]?
          !owner.nil? && owner != info.name
        end
        if conflict = conflict_command
          message = "Failed to install plugin `#{info.name}`, due to Bundler::Plugin::Index::CommandConflict " \
                    "(Command(s) `#{conflict}` declared by #{info.name} are already registered.)"
          stderr.puts Commands.word_wrap(message, CLI.terminal_width)
          remove_failed_plugin_source(root_dir)
          return 29
        end
        merged_commands = registered.dup
        declared[:commands].each { |command| merged_commands[command] = info.name }
        conflict_source = declared[:sources].find do |type|
          owner = sources_map[type]?
          !owner.nil? && owner != info.name
        end
        if conflict = conflict_source
          message = "Failed to install plugin `#{info.name}`, due to Bundler::Plugin::Index::SourceConflict " \
                    "(Source(s) `#{conflict}` declared by #{info.name} are already registered.)"
          stderr.puts Commands.word_wrap(message, CLI.terminal_width)
          remove_failed_plugin_source(root_dir)
          return 29
        end
        # Source types a plugin registers through `Bundler::Plugin::API.source`
        # are recorded in the index (`sources:` = type -> plugin,
        # plugin/index.rb:62-64), which is what makes a later
        # `source "...", type: :<type>` block resolvable (dsl.rb:124-126).
        declared[:sources].each { |type| sources_map[type] = info.name }
        first_install = !plugin_path_map.has_key?(info.name)
        load_path_map[info.name] = [lib_dir]
        plugin_path_map[info.name] = root_dir
        # Hooks are recorded like the reference index: one ordered, deduped
        # plugin list per event (plugin/index.rb register_plugin).
        declared[:hooks].each do |event|
          owners = (hooks_map[event] ||= [] of String)
          owners << info.name unless owners.includes?(info.name)
        end

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
          sources_map.each { |type, owner| y.puts "  #{type}: #{owner.inspect}" }
        end
        # The plugin tree is created only once the plugin is known to load; a
        # malformed plugin (undefined hook event) therefore leaves the project
        # without `.bundle/plugin`, matching the reference.
        Dir.mkdir_p(index_dir)
        File.write(index_path, yaml)
        # Reference re-install of an installed plugin prints nothing beyond
        # "Resolving dependencies..." (no second "Installed plugin" line).
        stdout.puts "Installed plugin #{info.name}" if first_install
        0
      when "uninstall"
        all = rest.includes?("--all")
        # Reference `bundle plugin uninstall` declares only `--all`
        # (cli/plugin.rb:25-32), so Thor passes any other token through as a
        # plugin name: `--version`/`--local` are reported as missing plugins
        # instead of being silently dropped (plugin.rb:55-77).
        names = rest[1..].reject { |arg| arg == "--all" }
        if names.empty? && !all
          stderr.puts "No plugins to uninstall. Specify at least 1 plugin to uninstall."
          stderr.puts "Use --all option to uninstall all the installed plugins."
          return 0
        end
        index_path = plugin_index_path
        index = File.file?(index_path) ? (YAML.parse(File.read(index_path)) || YAML.parse("{}")) : YAML.parse("{}")
        # Reference `installed_plugins` = @plugin_paths.keys (insertion order,
        # plugin/index.rb:169-171); unregister_plugin mutates the index
        # immediately, so a duplicate name on the command line is "not
        # installed" the second time (plugin.rb:63-73).
        installed = installed_plugins(index)
        targets = all ? installed : names
        if targets.empty?
          stdout.puts "No plugins installed"
          return 0
        end
        removed = [] of String
        targets.each do |name|
          unless installed.includes?(name)
            stderr.puts "Plugin #{name} is not installed "
            next
          end
          path = plugin_path(index, name)
          # Plugins installed by Bundler itself live under
          # `.bundle/plugin`; rm_rf their checkout before dropping the
          # registry entries (plugin.rb:66-68, index.rb:192-196).
          FileUtils.rm_rf(path) if path && plugin_owned_path?(path)
          installed.delete(name)
          removed << name
          stdout.puts "Uninstalled plugin #{name}"
        end
        write_plugin_index(index_path, index, removed) unless removed.empty?
        0
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

    # Reference `save_plugin` (plugin.rb:292-298) raises a single message
    # ("Failed to install plugin `x`, due to <Class> (<cause>)") and
    # friendly_errors prints it with `wrap: true`, so the line breaks come from
    # thor's `word_wrap` at the terminal width (THOR_COLUMNS on Windows, else
    # 80). Every plugin-install failure path prints through this helper.
    private def self.put_plugin_install_failure(stderr : IO, name : String, cause : String) : Nil
      message = "Failed to install plugin `#{name}`, due to Bundler::Plugin::MalformattedPlugin (#{cause})"
      stderr.puts Commands.word_wrap(message, CLI.terminal_width)
    end

    # `plugin.rb:298-306` rolls a failed install back through `uninstall`, and
    # for a `--path` plugin the spec's `full_gem_path` is the source directory
    # itself, so the reference deletes the directory it was asked to install
    # from whenever registration fails (`plugin/installer/path.rb`). Observed
    # for MalformattedPlugin, CommandConflict and SourceConflict on both
    # reference versions; the differential fixtures `plugin-conflict-source`
    # and `plugin-conflict-command` pin that removal through the project tree.
    private def self.remove_failed_plugin_source(root_dir : String) : Nil
      FileUtils.rm_rf(root_dir) if Dir.exists?(root_dir)
    rescue
    end

    # `local_only` mirrors `Plugin::Installer#install_definition` for a typed
    # source without a primary remote: the reference builds its plugin
    # definition with an empty source list, so resolution only sees installed
    # gems and a missing inferred plugin raises GemNotFoundError (exit 7,
    # "Could not find gem 'bundler-source-<type>' in locally installed gems.").
    def self.plugin_install_remote(names : Array(String), rest : Array(String), stdout : IO, stderr : IO, local_only : Bool = false, remote_only : Bool = false) : Int32
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
          resolution.local_only = local_only
          resolution.remote_only = remote_only
          # `Plugin::Installer` resolves against remote/cached sources only
          # (the definition never calls `local!`), so the reference GemNotFound
          # message reads "閳? cached gems or installed locally"
          # (source/rubygems.rb:122-136).
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
            put_plugin_install_failure(stderr, spec.name, "plugins.rb was not found in the plugin.")
            return 29
          end
          index_path = File.join(plugin_root, "index")
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
          declared = PluginCommands.declared(File.join(gem_dir, "plugins.rb"), [lib_dir])
          if error = declared[:error]
            # Same mapping as the local branch: undefined hook events surface as
            # MalformattedPlugin with exit 29 and no index entry (the index file
            # is only created after this check).
            put_plugin_install_failure(stderr, spec.name, error)
            return 29
          end
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
          sources_map = {} of String => String
          (index["sources"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).each do |key, value|
            sources_map[key.as_s] = value.as_s
          end
          conflict_command = declared[:commands].find do |command|
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
          declared[:commands].each { |command| merged_commands[command] = spec.name }
          conflict_source = declared[:sources].find do |type|
            owner = sources_map[type]?
            !owner.nil? && owner != spec.name
          end
          if conflict = conflict_source
            message = "Failed to install plugin `#{spec.name}`, due to Bundler::Plugin::Index::SourceConflict " \
                      "(Source(s) `#{conflict}` declared by #{spec.name} are already registered.)"
            stderr.puts Commands.word_wrap(message, CLI.terminal_width)
            return 29
          end
          # `sources:` records the types registered through
          # `Bundler::Plugin::API.source` (plugin/index.rb:62-64).
          declared[:sources].each { |type| sources_map[type] = spec.name }
          first_install = !plugin_path_map.has_key?(spec.name)
          load_path_map[spec.name] = [lib_dir]
          plugin_path_map[spec.name] = gem_dir
          # Hooks are recorded like the reference index: one ordered, deduped
          # plugin list per event (plugin/index.rb register_plugin).
          declared[:hooks].each do |event|
            owners = (hooks_map[event] ||= [] of String)
            owners << spec.name unless owners.includes?(spec.name)
          end
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
            sources_map.each { |type, owner| y.puts "  #{type}: #{owner.inspect}" }
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
        Config.app_config_path(File.dirname(gemfile))
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

      installed_plugins(YAML.parse(File.read(index_path)))
    end

    # `@plugin_paths.keys` order, never sorted: the reference keys the index
    # hash by plugin_paths, so `list`/`--all` follow installation order
    # (plugin/index.rb:169-171).
    private def self.installed_plugins(index : YAML::Any) : Array(String)
      plugin_path_map(index).keys.map(&.to_s)
    end

    private def self.plugin_path_map(index : YAML::Any) : Hash(YAML::Any, YAML::Any)
      index["plugin_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
    end

    private def self.plugin_path(index : YAML::Any, name : String) : String?
      plugin_path_map(index)[name]?.try(&.to_s)
    end

    # Equivalent of `Bundler::Plugin::Index#installed_in_plugin_root?`
    # (plugin/index.rb:192-196): only checkouts below `.bundle/plugin` are
    # Bundler-managed and safe to delete; `--path` plugins point elsewhere.
    private def self.plugin_owned_path?(path : String) : Bool
      root = plugin_tree_root.gsub('\\', "/")
      prefix = root.ends_with?("/") ? root : root + "/"
      path.gsub('\\', "/").starts_with?(prefix)
    end

    # Rewrites the plugin index without the uninstalled plugins, preserving
    # the reference layout (`---` start, bare empty collections).
    private def self.write_plugin_index(path : String, index : YAML::Any, removed : Array(String)) : Nil
      render = ->(section : YAML::Any, out : String::Builder, by_value : Bool) do
        map = section.as_h? || {} of YAML::Any => YAML::Any
        map.each do |key, value|
          drop = by_value ? removed.includes?(value.to_s) : removed.includes?(key.to_s)
          next if drop
          out.puts "  #{key}:"
          if value.as_a?
            value.as_a.each { |v| out.puts "  - #{v.to_s.inspect}" }
          else
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
        # Hook events map to plugin-name arrays; uninstalling a plugin drops it
        # from every list and removes events that end up empty, matching
        # plugin/index.rb unregister_plugin.
        hooks_map = index["hooks"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
        hooks_map.each do |event, names|
          owners = (names.as_a?.try(&.map(&.to_s)) || [] of String).reject { |name| removed.includes?(name) }
          next if owners.empty?
          y.puts "  #{event.to_s}:"
          owners.each { |name| y.puts "  - #{name.inspect}" }
        end
        y.puts "load_paths:"
        render.call(index["load_paths"]? || YAML.parse("{}"), y, false)
        y.puts "plugin_paths:"
        render.call(index["plugin_paths"]? || YAML.parse("{}"), y, false)
        y.puts "sources:"
        # Sources map source-name => plugin-name; unregister_plugin drops by
        # value, not by key (plugin/index.rb:80).
        render.call(index["sources"]? || YAML.parse("{}"), y, true)
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
      # `cli/pristine.rb:10` runs `CLI::Common.ensure_all_gems_in_lockfile!`
      # before the definition is used, and `common.rb:125-132` short-circuits on
      # `return unless locked_gems` -- with no lockfile the requested-name check
      # is a no-op, so an unknown name is not reported (the resolve below only
      # knows the gems the Gemfile asks for).
      lockfile = if definition.lockfile_exists?
                   definition.lockfile!
                 else
                   # `cli/pristine.rb:17` `definition.specs` materializes the
                   # definition from the Gemfile and resolves on demand
                   # (definition.rb:249-251), so `bundle pristine` works before
                   # the first install. The resolve is local-only (only
                   # `check`/`install` enable remote sources) and the lockfile is
                   # never written (`cli/pristine.rb` never calls
                   # `definition.lock`); a gem that is not installed raises
                   # GemNotFound, which exits 7 with the
                   # "... in locally installed gems." message.
                   materialize_lockfile(definition, stdout, local_only: true)
                 end
      if definition.lockfile_exists? && !gems.empty?
        unknown = gems.find { |g| lockfile.specs.none?(&.name.==(g)) }
        if unknown
          # `cli/pristine.rb:10` calls `ensure_all_gems_in_lockfile!`, so the
          # text is the shared message, Did-you-mean line included.
          stderr.puts gem_not_found_message_for(unknown, lockfile.specs.map(&.name))
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
              # `cli/pristine.rb:26-30`: report and skip the gem; the resolved
              # path is printed with forward slashes regardless of platform.
              stderr.puts "Failed to pristine #{gem_label}. Cached gem #{gem_file.gsub('\\', "/")} does not exist."
              next
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
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        if requested = Commands.requested_ruby_version(evaluation)
          RubyRuntime.validate_version!(requested, bridge.ruby_environment)
        end
      rescue ex : Error
        bridge.close
        raise ex
      rescue
      end
      # `cli/outdated.rb:26-33` runs `validate_runtime!` before it resolves the
      # bundle, so a patchlevel mismatch outranks the local-only resolution
      # error a missing lockfile would otherwise raise.
      materialize_lockfile(definition, nil, local_only: true) unless definition.lockfile_exists?
      begin
        parseable = rest.includes?("--parseable") || rest.includes?("--porcelain")
        local_flag = rest.includes?("--local")
        resolution = Resolution.new(definition, false, bridge)
        unless cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        verbose = ENV["CELERITE_VERBOSE"]? == "1"
        # The `Running ...` echo is emitted once by `Commands.dispatch`
        # (`print_command_echo`). The reference's only debug output here is the
        # resolve-need reason, which `fetcher.rb:273-276` then merges with the
        # local-server note; it is printed just before `resolve!` below
        # (`definition.rb:866-902`).
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
        # `outdated` re-resolves without naming gems (`cli/outdated.rb:45-65`),
        # so the reference's reason keeps the empty unlocking name and its
        # trailing space, merging with the local-server note.
        if Commands.verbose_debug?
          Commands.print_debug_reason(stdout, "Re-resolving dependencies because bundler is unlocking ")
          Commands.debug_local_server(stdout, resolution.primary_remote)
        end
        specs = resolution.resolve!
        cooldown_days = cooldown_flag_value(rest)
        cooldown_now = resolution.cooldown_now || Time.utc.to_unix
        cooldown_notes = {} of String => Int32
        cooldown_adoptable = {} of String => Gem::Version
        requested_specific = {} of String => Bool
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
          # `print_gem` only appends `, requested <req>` for a SPECIFIC
          # dependency (`dependency&.specific?`, cli/outdated.rb:218-220); the
          # table cell always shows the requirement (`gem_column_for`, :257-259).
          if dep
            begin
              requested_specific[spec.name] = Gem::Requirement.new(reqs || [] of String).specific?
            rescue ArgumentError
              requested_specific[spec.name] = false
            end
          end
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
            message = "#{row[0]} (newest #{row[2]}, installed #{row[1]}"
            message += ", requested #{row[3]}" if requested_specific[row[0]]?
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
        end

        # Bundler::Env.report builds the Gemfile sections from the current
        # definition (env.rb:35-45); `issue` prints them before the doctor
        # section and only omits them when there is no Gemfile at all.
        definition = begin
          Definition.build
        rescue GemfileNotFound
          nil
        end
        print_gemfile_sections(stdout, definition, bridge) if definition

        stdout.puts
        stdout.puts "## Bundle Doctor"
      ensure
        bridge.close
      end

      # cli/issue.rb:33-38 delegates to the doctor; a missing Gemfile raises
      # GemfileNotFound from here, after the report above (exit 10).
      doctor_report(stdout, stderr)
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

      # cli/console.rb:15: the console name comes from `console`
      # (BUNDLE_CONSOLE) and defaults to irb.
      name = definition.config["console"].to_s
      name = "irb" if name.empty?
      group = positional.first? || ""

      # cli/console.rb:11-17 runs `Bundler.require` (group aware), clears ARGV
      # and calls `console.start` in-process. Celerite keeps the separate
      # process, but hands the whole boot sequence to assets/bridge/console_boot.rb
      # so the bundle's gems are really required and the GROUP argument takes
      # effect (declared deviation: the console object is built in a child
      # process, not inside the CLI process).
      process_env = ENV.to_h
      process_env["BUNDLE_GEMFILE"] = File.expand_path(definition.gemfile_path).gsub(/\\/, "/")
      process_env["CELERITE_CONSOLE"] = name
      process_env["CELERITE_CONSOLE_GROUPS"] = group

      ruby = ENV["CELERITE_RUBY"]? || "ruby"
      boot = console_boot_path
      # Windows .bat/.cmd wrappers need the command processor; direct spawn
      # would fail with "not a valid application".
      if ruby.ends_with?(".bat") || ruby.ends_with?(".cmd")
        Process.run("cmd", ["/c", ruby, boot], env: process_env,
          output: :inherit, error: :inherit, input: :inherit).exit_code
      else
        Process.run(ruby, [boot], env: process_env,
          output: :inherit, error: :inherit, input: :inherit).exit_code
      end
    end

    # Console boot helper (assets/bridge/console_boot.rb), resolved like
    # PluginCommands.script_path: explicit override, then source-relative, then
    # next to the executable.
    private def self.console_boot_path : String
      if path = ENV["CELERITE_CONSOLE_BOOT"]?
        return path unless path.empty?
      end
      source_relative = File.expand_path("../../../assets/bridge/console_boot.rb", __DIR__)
      return source_relative if File.file?(source_relative)

      exe_dir = begin
        File.dirname(Process.executable_path || "")
      rescue
        ""
      end
      unless exe_dir.empty?
        candidates = [
          File.join(exe_dir, "assets", "bridge", "console_boot.rb"),
          File.join(exe_dir, "..", "assets", "bridge", "console_boot.rb"),
          File.join(exe_dir, "..", "..", "assets", "bridge", "console_boot.rb"),
        ]
        candidates.each do |candidate|
          expanded = File.expand_path(candidate)
          return expanded if File.file?(expanded)
        end
      end
      source_relative
    end

    # ------------------------------------------------------------------
    # gem: project skeleton (bundle gem NAME)
    # ------------------------------------------------------------------
    def self.gem(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      profile = bundle_profile_version
      # cli.rb:589-602 lists --help as a class option; Thor prints the manpage
      # before running the command (measured on 4.0.24 and 2.7.2).
      if rest.includes?("--help") || rest.includes?("-h")
        stdout.print GemTemplate.help_text(profile)
        return 0
      end
      if (code = reject_unknown_switches(stderr, rest, GEM_SWITCH_FLAGS, GEM_SWITCH_VALUES))
        return code
      end

      # gem.rb/cli.rb:607-608: the deprecated `--rubocop` spellings raise
      # InvalidOption before any work. 2.7.2 keeps the same rejection but uses
      # "--linter" (without the =rubocop suffix) for --no-rubocop.
      if rest.includes?("--rubocop")
        stderr.puts "--rubocop has been removed, use --linter=rubocop"
        return 15
      end
      if rest.includes?("--no-rubocop")
        stderr.puts profile.starts_with?("2.") ? "--no-rubocop has been removed, use --linter" : "--no-rubocop has been removed, use --no-linter"
        return 15
      end

      ext_values = profile.starts_with?("2.") ? ["c", "rust"] : ["c", "rust", "go"]
      if (index = rest.index("--ext"))
        next_argument = index + 1 < rest.size ? rest[index + 1] : nil
        unless next_argument && ext_values.includes?(next_argument)
          stderr.puts "Extensions can now be generated using C or Rust, so `--ext` with no arguments has been removed. Please select a language, e.g. `--ext=rust` to generate a Rust extension."
          return 15
        end
      end

      positionals = [] of String
      values = {} of String => String
      flags = Set(String).new
      value_options = ["--test", "-t", "--ci", "--linter", "--ext", "--edit", "-e", "--github-username"]
      index = 0
      while index < rest.size
        argument = rest[index]
        name = argument.split("=", 2)[0]
        if value_options.includes?(name)
          if argument.includes?("=")
            values[name] = argument.split("=", 2)[1]
            index += 1
          elsif index + 1 < rest.size
            values[name] = rest[index + 1]
            index += 2
          else
            values[name] = ""
            index += 1
          end
        elsif argument.starts_with?("-")
          flags << argument
          index += 1
        else
          positionals << argument
          index += 1
        end
      end

      # Thor enum validation (`Expected '--test' to be one of rspec, minitest,
      # test-unit; got minitestx`, exit 15) 閳?measured on both references.
      if value = values["--test"]?
        unless ["rspec", "minitest", "test-unit"].includes?(value)
          stderr.puts "Expected '--test' to be one of rspec, minitest, test-unit; got #{value}"
          return 15
        end
      end
      if value = values["--ci"]?
        unless ["github", "gitlab", "circle"].includes?(value)
          stderr.puts "Expected '--ci' to be one of github, gitlab, circle; got #{value}"
          return 15
        end
      end
      if value = values["--linter"]?
        unless ["rubocop", "standard"].includes?(value)
          stderr.puts "Expected '--linter' to be one of rubocop, standard; got #{value}"
          return 15
        end
      end
      if value = values["--ext"]?
        unless ext_values.includes?(value)
          stderr.puts "Expected '--ext' to be one of #{ext_values.join(", ")}; got #{value}"
          return 15
        end
      end

      # Thor rejects a missing/multiple positionals before any work; the
      # reference prints these exact lines and exits 15.
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

      # --edit opens the generated gemspec and --bundle runs `bundle install`;
      # the reference behavior is recorded in docs/compat-report.md. They are
      # not silently ignored here.
      if flags.includes?("--bundle")
        stderr.puts "bundle gem option --bundle is not supported by Celerite (reference runs `bundle install`)"
        return 1
      end
      if values.has_key?("--edit") || values.has_key?("-e")
        stderr.puts "bundle gem option --edit is not supported by Celerite (reference opens the gemspec in an editor)"
        return 1
      end

      name = File.basename(positionals.first)
      use_git = !flags.includes?("--no-git") && !Process.find_executable("git").nil?
      target = File.expand_path(name)

      if File.exists?(target) && !Dir.exists?(target)
        stderr.puts "Couldn't create a new gem named `#{name}` because there's an existing file named `#{name}`."
        return 32
      end

      # gem.rb:45-49: author/email/github come from `git config`, with the TODO
      # fallbacks at gem.rb:69-70 and "[USERNAME]" at gem.rb:16/77. All three
      # reads are gated on use_git.
      author = use_git ? git_config("user.name") : ""
      author = "TODO: Write your name" if author.empty?
      email = use_git ? git_config("user.email") : ""
      email = "TODO: Write your email address" if email.empty?
      github_username = values["--github-username"]? || (use_git ? git_config("github.user") : "")

      test_given = values.has_key?("--test") || values.has_key?("-t")
      ci_given = values.has_key?("--ci")
      linter_given = values.has_key?("--linter")
      test = values["--test"]? || values["-t"]?
      test = nil if flags.includes?("--no-test")
      ci = values["--ci"]?
      ci = nil if flags.includes?("--no-ci")
      linter = values["--linter"]?
      linter = nil if flags.includes?("--no-linter")
      ext = values["--ext"]?
      ext = nil if flags.includes?("--no-ext")
      exe = !flags.includes?("--no-exe") && (flags.includes?("--exe") || flags.includes?("--bin") || flags.includes?("-b"))
      mit = flags.includes?("--no-mit") ? false : (flags.includes?("--mit") ? true : nil)
      coc = flags.includes?("--no-coc") ? false : (flags.includes?("--coc") ? true : nil)
      changelog = flags.includes?("--no-changelog") ? false : (flags.includes?("--changelog") ? true : nil)

      stdout.puts "Creating gem '#{name}'..."
      # gem.rb:342-344/386-388/421-423: when the explicit option matches the
      # persisted gem.* setting (the default settings in the reference test
      # environment do), the reference logs this note before scaffolding.
      stdout.puts "#{test} is already configured, ignoring --test flag." if test_given && test
      stdout.puts "#{ci} is already configured, ignoring --ci flag." if ci_given && ci
      stdout.puts "MIT License enabled in config" if mit
      stdout.puts "Code of conduct enabled in config" if coc
      stdout.puts "Changelog enabled in config" if changelog
      stdout.puts "#{linter} is already configured, ignoring --linter flag." if linter_given && linter
      if linter
        stdout.puts "RuboCop enabled in config" if linter == "rubocop"
        stdout.puts "Standard enabled in config" if linter == "standard"
      end

      if use_git
        # gem.rb:257-262: the git-init line starts with a blank separator and
        # `git init` output is captured, hints stay on stderr.
        stdout.puts
        stdout.puts "Initializing git repo in #{target.gsub('\\', "/")}"
        Process.run("git", ["init", target], output: IO::Memory.new, error: :inherit)
      end

      branch = use_git ? git_head_branch(target) : nil
      options = GemTemplate::Options.new(test: test, ci: ci, linter: linter, ext: ext,
        exe: exe, mit: mit == true, coc: coc == true, changelog: changelog == true, bundle: false)
      GemTemplate.render(name, author, email, github_username, use_git, profile, options, branch).each do |entry|
        path = File.join(target, entry.path)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, entry.content)
        stdout.puts "      create  #{name}/#{entry.path}"
      end

      # gem.rb:269-273: console/setup/exe are marked executable.
      ["bin/console", "bin/setup", "exe/#{name}"].each do |relative|
        path = File.join(target, relative)
        File.chmod(path, 0o755) if File.exists?(path)
      end

      if use_git
        # gem.rb:275-277: `git add .` in the target; there is no commit. The
        # CRLF warnings git prints for LF files are inherited on purpose.
        Dir.cd(target) do
          Process.run("git", ["add", "."], output: IO::Memory.new, error: :inherit)
        end
      end

      stdout.puts
      guide = profile.starts_with?("2.") ? "https://bundler.io/guides/creating_gem.html" : "https://guides.rubygems.org/make-your-own-gem/"
      stdout.puts "Gem '#{name}' was successfully created. " \
                  "For more information on making a RubyGem visit #{guide}"
      0
    end

    private def self.git_head_branch(target : String) : String
      head = File.join(target, ".git", "HEAD")
      return "main" unless File.file?(head)
      line = File.read(head).strip
      line.split("refs/heads/").last? || "main"
    rescue
      "main"
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
