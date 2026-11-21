require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../lockfile/writer"
require "../definition"
require "../resolution"
require "../mirror"
require "../proxy"
require "../installer"
require "../downloader"
require "../plugin_hooks"
require "../plugin_commands"
require "../plugin_gemfile"
require "../binstub_template"
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

    # Reference prints the platform for platform-specific variants
    # (`Fetching platdemo 1.0.0 (x64-mingw-ucrt)`); the ruby platform is
    # elided from progress lines.
    def self.platform_suffix(platform : String?) : String
      return "" if platform.nil? || platform.empty? || platform == "ruby"
      " (#{platform})"
    end

    # ------------------------------------------------------------------
    # install
    # ------------------------------------------------------------------
    # Reference `Plugin.gemfile_install` (`bundler/plugin.rb:104-127`): the
    # plugins a Gemfile declares are installed before the normal install runs.
    # Each plugin resolves exactly like `celerite plugin install --source`; a
    # missing gem therefore fails with the reference GemNotFoundError (exit 7)
    # before the main install starts.
    private def self.install_gemfile_plugins(gemfile_path : String, stdout : IO, stderr : IO) : Int32?
      begin
        names = PluginGemfile.plugin_names(gemfile_path)
      rescue ex : Bridge::BridgeError
        # Only the reference's own Gemfile/plugin statuses may abort the
        # install: DSLError inherits 4/15, GemNotFoundError is 7,
        # PluginGemfileError is 29. Anything else falls through so the normal
        # path reports its own (reference) error.
        raise ex if {4, 7, 15, 29}.includes?(ex.status_code)
        return nil
      rescue ex : Error
        # No usable bridge (e.g. "bridge server script not found" in
        # in-process specs): the normal install path reports its own errors.
        return nil
      end
      return nil if names.empty?

      remote = PluginGemfile.primary_source(gemfile_path)
      index_path = PluginCommands.index_path(gemfile_path)
      # Reference resolves the inferred plugin inside `Plugin.gemfile_install`,
      # whose definition allows remote/cached sources only — but only once a
      # plugin actually registered a source; with no plugin loaded the same
      # lookup runs with local sources allowed (source/rubygems.rb:122-136).
      remote_only = !PluginCommands.sources(index_path).empty?
      names.each do |name|
        next if PluginCommands.installed_plugin?(index_path, name)
        # A Gemfile that only declares `source ..., type: :t` has no primary
        # remote: the reference resolves the inferred plugin against installed
        # gems only (`Plugin::Installer#install_definition` builds an empty
        # source list), so a missing `bundler-source-t` is a local GemNotFound
        # (exit 7), not a network attempt against rubygems.org.
        if remote
          code = plugin_install_remote([name], ["--source", remote], stdout, stderr, remote_only: remote_only)
        else
          code = plugin_install_remote([name], [] of String, stdout, stderr, local_only: true, remote_only: remote_only)
        end
        return code unless code == 0
      end
      nil
    end

    # `--gemfile`/`--lockfile` really take effect for install in the reference;
    # scope the ENV override to this command and restore on every exit path.
    def self.install(stdout : IO, stderr : IO, rest : Array(String), summary : Bool = true, show_resolving : Bool = true, no_reuse : Bool = false, no_install : Bool = false, cli_arguments : Bool = true) : Int32
      # Thor parses `--jobs`/`--retry` as numeric values and rejects positional
      # arguments before `install` runs; internal callers (add/remove/cache/clean)
      # pass gem names through this entry, so they opt out of that check.
      begin
        with_gemfile_overrides(rest) do
          run_install(stdout, stderr, rest, summary, show_resolving, no_reuse, no_install, cli_arguments)
        end
      rescue ex : GemfileNotFound
        # `cli.rb:290-313`: `bundle install` rescues a missing Gemfile, renders
        # `cli_help` and re-raises so the exit status still reports the missing
        # Gemfile (measured: exit 10, the table on stdout, `Could not locate
        # Gemfile` on stderr). 2.7.2 has no such rescue, so it stays silent.
        unless (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
          Commands.cli_help(stdout, stderr, [] of String)
        end
        raise ex
      end
    end

    private def self.run_install(stdout : IO, stderr : IO, rest : Array(String), summary : Bool = true, show_resolving : Bool = true, no_reuse : Bool = false, no_install : Bool = false, cli_arguments : Bool = true) : Int32
      if rest.includes?("--frozen")
        # Thor rejects the flag before any Gemfile validation; the exact
        # message depends on the profile and the command (see frozen helper).
        bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        lockfile_exists = begin
          Definition.build.lockfile_exists?
        rescue
          false
        end
        if code = frozen_flag_exit(rest, stderr, lockfile_exists, bundle_version, "install")
          return code
        end
      end
      # `--path`/`--without`/`--with`/`--clean`/... are accepted by our switch
      # surface because this port implements their semantics, but 4.x reports
      # the removed-flag message; the check runs before the switch whitelist so
      # those flags keep their reference wording. 2.7.x only warns (and keeps
      # going: `install --path` still reaches the Gemfile check).
      if removed = Commands.removed_flag(rest, "install")
        bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        if bundle_version.starts_with?("2.")
          stderr.puts Commands.removed_flag_deprecation(removed) unless removed.special_message
        else
          stderr.puts Commands.word_wrap(Commands.removed_flag_message(removed), 80)
          return 15
        end
      end
      if code = reject_unknown_switches(stderr, rest, INSTALL_SWITCH_FLAGS, INSTALL_SWITCH_VALUES, INSTALL_SUGGEST_DICTIONARY)
        return code
      end
      # Thor parses `--jobs`/`--retry` as numeric and rejects positional arguments
      # before `install` runs; internal callers pass gem names, so they opt out.
      if cli_arguments
        if message = numeric_switch_error(rest, ["--jobs", "-j"])
          stderr.puts message
          return 15
        end
        if code = reject_positional_arguments(stderr, "install", rest, INSTALL_SWITCH_FLAGS, INSTALL_SWITCH_VALUES)
          return code
        end
      end
      definition = Definition.build
      config = definition.config
      # `install --standalone` without an explicit path (and without `--local`)
      # installs into `./bundle` for this run only — the reference uses
      # `set_command_option :path, "bundle"` (cli/install.rb L112-114), which
      # never reaches `.bundle/config`.
      standalone_requested = rest.any? { |a| a == "--standalone" || a.starts_with?("--standalone=") }
      if standalone_requested && config["path"].to_s.empty? && !rest.includes?("--local")
        config.set_temporary("path", "bundle")
      end
      if config.frozen? && !definition.lockfile_exists?
        # `cli/install.rb:29-35` (4.0.24) / `:27-34` (2.7.2) name the setting that
        # forced frozen mode: 4.x lets `frozen` override `deployment`, 2.x uses
        # `flag ||=`, so `deployment` wins there.
        deployment = config["deployment"] == true
        frozen = config["frozen"] == true
        flag = if profile_2_x?
                 deployment ? "deployment setting" : "frozen setting"
               else
                 frozen ? "frozen setting" : "deployment setting"
               end
        raise ProductionError.new(
          "The #{flag} requires a lockfile. Please make sure you have checked " \
          "your #{relative_lockfile_path(definition)} into version control before deploying.")
      end
      # M7(4): fail fast on explicitly configured unsupported settings
      # (and warn-but-continue for proxy env vars).
      if unsupported = Commands.unsupported_setting_error(config, stderr)
        stderr.puts unsupported
        return 1
      end

      # M7(6): the reference runs `Plugin.gemfile_install` before the main
      # definition is built. Celerite's own client-side policy checks above do
      # not need the bridge, so they run first; only then evaluate the Gemfile
      # for declared plugins (this is the first bridge work in `install`).
      if PluginGemfile.enabled?(Config.new(File.dirname(Definition.find_gemfile)))
        if plugin_code = install_gemfile_plugins(Definition.find_gemfile, stdout, stderr)
          return plugin_code
        end
      end

      bridge = Bridge::Client.new
      lock : ProcessLock? = nil
      begin
        # Runtime Ruby requirement validation (Bundler validate_runtime!/validate_ruby!)
        # for install flows when evaluation is available.
        gemfile_dependencies : Array(Bridge::EvaluatedDependency)? = nil
        gemfile_sources : Array(Bridge::EvaluatedSource)? = nil
        begin
          evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
          gemfile_dependencies = evaluation.dependencies
          gemfile_sources = evaluation.sources
          # `evaluation.ruby` is the human-readable requirement string and drops
          # the option fields, so patchlevel would be lost
          # (`ruby_version.cr:64-71`); validate the structured declaration
          # instead, before any resolution touches the network.
          if requested = Commands.requested_ruby_version(evaluation)
            RubyRuntime.validate_version!(requested, bridge.ruby_environment)
          end
          # `validate_runtime!` also runs `validate_platforms!`
          # (definition.rb:494-530); a frozen lockfile that does not list the
          # local platform fails here, before the lockfile-changes summary.
          definition.validate_platforms!(bridge.ruby_environment.platform)
        rescue ex : Error
          raise ex
        rescue
        end

        resolution = Resolution.new(definition, false, bridge)
        resolution.progress = stdout
        lock = ProcessLock.lock(install_path(config))
        # `Bundler.create_bundle_path` runs before the frozen validation
        # (bundler/installer.rb:63-71), so a deployment install that then fails
        # still leaves `vendor/bundle/ruby/<abi>` behind.
        install_root = InstallPaths.gem_root(config, bridge.ruby_environment.default_gem_dir, InstallPaths.ruby_abi(bridge))
        Dir.mkdir_p(install_root)
        # `definition.rb:153` (`converge_paths`) only guards the 4.x line; a
        # stale PATH spec under frozen mode re-resolves nowhere and 2.7.2
        # reports it as missing instead.
        path_specs_changed = resolution.bridge_bundler_version.starts_with?("4.") &&
                             resolution.path_specs_changed?
        definition.validate_frozen_lockfile!(rest.includes?("--deployment"), gemfile_dependencies,
          gemfile_sources, path_specs_changed: path_specs_changed)
        if !cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        if days = cooldown_flag_value(rest)
          resolution.cooldown_days = days
        end
        resolution.local_only = rest.includes?("--local")
        resolution.prefer_local = rest.includes?("--prefer-local")

        # Fetch/install lines are buffered as events and flushed after the
        # resolution decision (see the comment above `install_events`'s later
        # uses), but the reference prints a gem's `Fetching` line *before* its
        # download retries start: `Bundler::Retry#fail_attempt` writes a blank
        # line and then the warning (`retry.rb:60-64`), so a 403 download leaves
        # `Fetching <gem>` followed by one blank line per attempt. `early_fetch`
        # names the gem whose buffered line must be printed at the first retry
        # notice, which keeps both orders intact.
        install_events = [] of NamedTuple(kind: String, name: String, line: String)
        early_fetch = [] of String
        flush_early_fetch = -> {
          unless early_fetch.empty?
            name = early_fetch.first
            if index = install_events.index { |event| event[:kind] == "fetch" && event[:name] == name }
              stdout.puts install_events[index][:line]
              install_events.delete_at(index)
            end
            early_fetch.clear
          end
          stdout.puts ""
        }

        install_path = install_path(config)
        abi = ruby_abi(bridge)
        gem_root = InstallPaths.gem_root(config, bridge.ruby_environment.default_gem_dir, abi)
        downloader = Downloader.new(resolution.primary_remote, downloader_cache_root, Commands.retry_count(config), Celerite::Mirror.resolve(config, resolution.primary_remote), Commands.ssl_option(config, "ssl_ca_cert"), Commands.ssl_option(config, "ssl_client_cert"), Commands.ssl_option(config, "ssl_verify_mode"), config.credentials_for(resolution.primary_remote), timeout: Commands.timeout_seconds(config), proxy: Celerite::Proxy.resolve(config), warning_io: stderr, notice: flush_early_fetch)
        installer = Installer.new(gem_root, abi, bridge, downloader, stdout)
        installer.config = config
        installer.no_install = no_install
        installer.dependency_tree = ->(gem_name : String) { resolution.dependency_tree_for(gem_name) }
        installer.gemfile_name = File.basename(definition.gemfile_path)
        installers_by_remote = {resolution.primary_remote => installer}
        if target_rbconfig = flag_value(rest, "--target-rbconfig")
          expanded = File.expand_path(target_rbconfig, Dir.current)
          unless File.file?(expanded)
            # `cli/install.rb:24` passes the path straight to
            # `Gem.set_target_rbconfig` (rubygems_integration.rb:34 →
            # rubygems/target_rbconfig.rb:37), which loads it immediately. A
            # missing file raises LoadError before anything is resolved or
            # written, so stdout stays empty, no lockfile is produced, and
            # friendly-errors prints the ERROR REPORT TEMPLATE (exit 1).
            stderr.puts "--- ERROR REPORT TEMPLATE -------------------------------------------------------"
            stderr.puts ""
            stderr.puts "```"
            stderr.puts "LoadError: cannot load such file -- #{target_rbconfig}"
            stderr.puts "```"
            stderr.puts ""
            stderr.puts "--- TEMPLATE END ----------------------------------------------------------------"
            stderr.puts ""
            stderr.puts "Unfortunately, an unexpected error occurred, and Bundler cannot continue."
            return 1
          end
          installer.target_rbconfig = expanded
        end

        # --no-lock: resolve from scratch every run (no reuse, no write).
        no_lock = rest.includes?("--no-lock")
        # `Plugin::DSL#source` adds an inferred `bundler-source-<type>`
        # dependency for every typed source (plugin/dsl.rb:39-49). Reference
        # `install` resolves it like any other gem, so the lockfile reused from
        # a previous `lock` (which does not record inferred deps) no longer
        # matches and the plugin gem is fetched.
        inferred_plugins = [] of String
        if evaluation
          inferred = evaluation.sources.compact_map do |src|
            src.type == "Plugin" ? src.plugin_type : nil
          end.map { |plugin_type| "bundler-source-#{plugin_type}" }
          inferred_plugins = inferred
          resolution.add_inferred_plugin_dependencies!(inferred) unless inferred.empty?
        end
        reuse = (no_reuse || no_lock) ? false : resolution_can_reuse?(resolution)
        # A lockfile whose CHECKSUMS entries are missing/empty must be refreshed
        # from the index even when every gem is already installed
        # (`definition.rb:630-659`; only a remote fetch can fill the entry).
        # `--local` keeps the locked resolution, matching the reference's
        # `empty_checksums_actionable?`.
        checksum_refresh = reuse && definition.checksums_need_refresh?(rest.includes?("--local"))
        reuse = false if checksum_refresh
        resolution.show_resolving = show_resolving
        # 4.0.24 backfills checksums without announcing resolution on `install`
        # (measured; `lock` does print it), while 2.7.2 prints both lines.
        resolution.show_resolving = false if checksum_refresh && !resolution.bridge_bundler_version.starts_with?("2.")

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

        # Reference `setup_domain!` re-resolves whenever a gem still needs
        # installing, and only then can a locked spec's Ruby/RubyGems
        # requirement matter (`definition.rb:190-203`, `installer.rb:79-82`).
        # Silent idempotent reruns keep the offline path and print nothing.
        verify_locked_compat = reuse && definition.lockfile_exists? &&
                               definition.lockfile!.sources.any? do |source|
                                 source.type == "GEM" && source.specs.any? do |locked|
                                   !installer.installed?(locked.name, locked.version, locked.platform)
                                 end
                               end
        # `Installer.install` fires `gem_before_install_all` before it resolves
        # and installs (`installer.rb:12-20`); the hook receives
        # `definition.dependencies`.
        if code = PluginHooks.run(bridge, definition, config, "before-install-all", stdout, stderr)
          return code
        end
        # `definition.rb:868-875` explains the resolution decision, and
        # `fetcher.rb:273-276` notes the local-server shortcut for `file://`
        # remotes. Both are `Bundler.ui.debug`, so `--verbose`/`BUNDLE_VERBOSE`
        # is the only way to see them.
        verbose_output = Commands.verbose_debug?
        if verbose_output
          Commands.print_debug_reason(stdout, Commands.debug_reason_for(definition, resolution))
          # The local-server note comes from the fetcher (`fetcher.rb:273-276`),
          # so it only appears when an index fetch is unavoidable: not for the
          # lockfile reuse path, but yes when an empty CHECKSUMS entry forces a
          # refresh (`checksums_need_refresh?`). Measured both ways.
          if !reuse || checksum_refresh
            Commands.debug_local_server(stdout, resolution.primary_remote)
          end
        end
        specs = resolution.resolve!(reuse, verify_locked_compat: verify_locked_compat)
        installer.ensure_specs_are_compatible!(specs)

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
        # `--local` restricts the SOURCES, not the install step: the reference
        # still installs a cached/local gem into the bundle path
        # (`cli/install.rb:33` `Installer#run` -> `install(spec)`; the skip is
        # `installed?(spec)`, which only counts specs already in the bundle).
        # Filtering by `local_installed_full_names` here wrongly treated a host
        # copy (same name+version, different GEM_HOME) as installed and printed
        # no `Installing` line at all, so the bundle stayed empty.

        # Default gems come from the interpreter, not from the declared
        # sources. The reference installs nothing for them but warns that they
        # cannot be cached (`rubygems_integration.rb` source cache), and still
        # counts the dependency in the summary. Keep them in `specs` (counts)
        # while removing them from the download/install worklist.
        #
        # The test is the spec's ORIGIN, not "the interpreter ships a gem with
        # this name and version": `source/rubygems.rb:181`, `:206` gate the
        # built-in path on `spec.default_gem?`, and a lock/index spec that
        # happens to match a shipped default gem (e.g. `net-protocol 0.2.2`) is
        # a normal remote spec that must still be fetched and installed.
        default_gems = specs.select do |spec|
          spec.source_type == "GEM" && spec.default_gem
        end
        unless default_gems.empty?
          default_gems.each do |spec|
            stderr.puts "#{spec.full_name} is built in to Ruby, and can't be cached because your Gemfile doesn't have any sources that contain it."
          end
          pending.reject! { |spec| default_gems.includes?(spec) }
          force_install.reject! { |spec| default_gems.includes?(spec) }
        end

        # Locked-path installs print the source-index line when downloads are
        # pending, but never a Resolving line (pinned reference behavior,
        # update-conservative fixture).
        if reuse && pending.any? && !resolution.index_fetch_logged?
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
        # The lockfile repair below can only be decided once the .gem packages
        # are available (it compares their real gemspec edges). When it does
        # repair, the reference resolves twice and prints
        # "Resolving dependencies..." twice between the source-index line and
        # the first Fetching line, so buffer the fetch/install lines as events
        # and flush them after the decision. On the 2.7 profile the reference
        # repairs one spec at a time and prints its Fetching/Installing pair
        # together, so the flush reorders the buffered events in that case.
        # `install_events` itself is declared above so the retry notice can
        # release one pending `Fetching` line early.
        repaired_edges = false
        plugin_messages = [] of {String, String}
        hidden_plugins = [] of String
        hidden_full_names = [] of String
        begin
          cached_paths = {} of String => String
          # Download every pending gem first, then install them (pure-Ruby
          # before native). The 2.7 profile is reordered at flush time below
          # when the lockfile was actually repaired.
          install_spec = ->(spec : Resolution::ResolvedSpec, cached : String?) do
            remote = resolution.remote_for(spec.name)
            spec_installer = installers_by_remote[remote]? || begin
              remote_downloader = Downloader.new(remote, downloader_cache_root, Commands.retry_count(config), Celerite::Mirror.resolve(config, remote), Commands.ssl_option(config, "ssl_ca_cert"), Commands.ssl_option(config, "ssl_client_cert"), Commands.ssl_option(config, "ssl_verify_mode"), config.credentials_for(remote), timeout: Commands.timeout_seconds(config), proxy: Celerite::Proxy.resolve(config), warning_io: stderr, notice: flush_early_fetch)
              next_installer = Installer.new(gem_root, abi, bridge, remote_downloader, stdout)
              next_installer.config = config
              next_installer.no_install = no_install
              next_installer.dependency_tree = ->(gem_name : String) { resolution.dependency_tree_for(gem_name) }
              next_installer.gemfile_name = File.basename(definition.gemfile_path)
              installers_by_remote[remote] = next_installer
              next_installer
            end
            unless no_install
              install_events << {
                kind: "install",
                name: spec.full_name,
                line: "Installing #{spec.name} #{spec.version}#{platform_suffix(spec.platform)}#{was_suffix.call(spec)}#{native_suffix(bridge, cached)}",
              }
            end
            spec_installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum, gem_file: cached)
            # The reference records the installed package's sha256 in CHECKSUMS
            # even for file:// sources.
            if cached && File.file?(cached)
              sha = Digest::SHA256.hexdigest(File.read(cached))
              resolution.install_checksums["#{spec.name}-#{spec.version}"] = "sha256=#{sha}"
            end
          end

          pending.each do |spec|
            # App-cache gems install from `<project>/vendor/cache`; the
            # reference prints no `Fetching` line and never hits the index.
            if vendor_path = resolution.vendor_cache_path(spec.full_name)
              cached_paths[spec.full_name] = vendor_path
              next
            end
            install_events << {
              kind: "fetch",
              name: spec.full_name,
              line: "Fetching #{spec.name} #{spec.version}#{platform_suffix(spec.platform)}#{was_suffix.call(spec)}",
            }
            # Arm the retry notice so a 403 download prints this buffered
            # `Fetching` line before the first blank line (see the comment on
            # `flush_early_fetch`).
            early_fetch << spec.full_name
            remote = resolution.remote_for(spec.name)
            spec_downloader = remote == resolution.primary_remote ? downloader : (installers_by_remote[remote]?.try(&.downloader) || Downloader.new(remote, downloader_cache_root, Commands.retry_count(config), Celerite::Mirror.resolve(config, remote), Commands.ssl_option(config, "ssl_ca_cert"), Commands.ssl_option(config, "ssl_client_cert"), Commands.ssl_option(config, "ssl_verify_mode"), config.credentials_for(remote), timeout: Commands.timeout_seconds(config), proxy: Celerite::Proxy.resolve(config), warning_io: stderr, notice: flush_early_fetch))
            begin
              cached_paths[spec.full_name] = spec_downloader.fetch(
                spec.name, spec.version.to_s, spec.platform, spec.checksum
              )
            rescue ex : Downloader::ForbiddenDownloadError
              # RubyGems' downloader failure surfaces as an install failure
              # (class name, install line, `In Gemfile:` tree) with exit 5
              # (`gem_installer.rb:38-49`, `parallel_installer.rb:198`).
              raise InstallError.new(Installer.download_failure_message(spec.name, spec.version.to_s, ex))
            end
          end
          pure, ext = pending.partition do |spec|
            cached = cached_paths[spec.full_name]?
            begin
              cached.nil? || Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(cached).to_json).extensions.empty?
            rescue
              true
            end
          end
          (pure + ext).each do |spec|
            install_spec.call(spec, cached_paths[spec.full_name]?)
          end
          force_install.each do |spec|
            install_events << {
              kind: "install",
              name: spec.full_name,
              line: "Installing #{spec.name} #{spec.version}#{platform_suffix(spec.platform)}#{native_suffix(bridge, nil)}",
            }
            installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum, true)
          end

          # Plugin sources install through the plugin's own `install` method
          # (`plugin/api/source.rb:90`, `installer/gem_installer.rb:67-75`);
          # the reference prints no Fetching/Installing pair for these, only a
          # post-install message after the summary. The inferred
          # `bundler-source-<type>` dependency becomes a registered plugin and
          # is dropped from the lockfile (`plugin/dsl.rb:39-49`; measured).
          bundle_root = gem_root
          specs.select(&.source_type.==("PLUGIN")).each do |spec|
            next if installer.installed?(spec.name, spec.version.to_s, spec.platform)
            remote = spec.source_remote || spec.source_info.try(&.remote) || ""
            message = bridge.plugin_source_install(definition.gemfile_path, remote, spec.full_name, bundle_root)
            plugin_messages << {spec.name, message.not_nil!} if message && !message.empty?
            locked_bundler = definition.lockfile_exists? ? definition.lockfile!.bundler_version : nil
            if resolution.bridge_bundler_version.starts_with?("2.") || ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?.try(&.starts_with?("2.")) || locked_bundler.try(&.starts_with?("2."))
              root = File.join(Config.app_config_path(File.dirname(definition.gemfile_path)), "plugin")
              cache_files = [] of String
              {File.join(gem_root, "cache"), File.join(root, "cache")}.each do |dir|
                next unless Dir.exists?(dir)
                Dir.children(dir).select { |f| f.ends_with?(".gem") }.each { |f| cache_files << File.join(dir, f) }
              end
              cache_files.uniq.each do |gem_file|
                full = File.basename(gem_file, ".gem")
                gems_dir = File.join(root, "gems", full)
                next if Dir.exists?(gems_dir)
                bridge.write_installed_spec(gem_file, File.join(root, "specifications", "#{full}.gemspec"), gems_dir, unpack: true)
              end
            end
            if plugin_type = spec.source_info.try(&.plugin_type)
              inferred = "bundler-source-#{plugin_type}"
              full_name = specs.find { |s| s.name == inferred }.try(&.full_name)
              hidden_plugins << inferred
              hidden_full_names << full_name if full_name
              resolution.hide_inferred_plugins!([inferred])
            end
          end
          unless hidden_plugins.empty?
            specs.reject! { |spec| hidden_plugins.includes?(spec.name) }
            # The reference installs inferred plugin gems under the plugin
            # root (`Plugin::Installer#install_all_sources` sets
            # GEM_HOME/GEM_PATH to `Plugin.root`): only the cached package and
            # the installed specification remain, not a regular bundle gem.
            plugin_root = File.join(Config.app_config_path(File.dirname(definition.gemfile_path)), "plugin")
            %w[build_info doc extensions gems plugins cache specifications].each do |dir|
              Dir.mkdir_p(File.join(plugin_root, dir))
            end
            hidden_full_names.each do |full_name|
              gem_file = File.join(gem_root, "cache", "#{full_name}.gem")
              next unless File.file?(gem_file)
              FileUtils.cp(gem_file, File.join(plugin_root, "cache", "#{full_name}.gem"))
              temp_gem_dir = File.join(plugin_root, "gems", full_name)
              bridge.write_installed_spec(gem_file, File.join(plugin_root, "specifications", "#{full_name}.gemspec"), temp_gem_dir, unpack: true)
              # 2.7.2 leaves the unpacked plugin gem under `.bundle/plugin/gems`;
              # 4.0.24 keeps only the cache and the generated specification.
              locked_bundler = definition.lockfile_exists? ? definition.lockfile!.bundler_version : nil
              keep_unpacked = resolution.bridge_bundler_version.starts_with?("2.") || ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?.try(&.starts_with?("2.")) || locked_bundler.try(&.starts_with?("2."))
              FileUtils.rm_rf(temp_gem_dir) unless keep_unpacked
            end
          end

          # 2.7.2's plugin installer also unpacks the plugin gem under
          # `.bundle/plugin/gems` even when the plugin was pre-installed by the
          # inferred-plugin pass above (which only copies cache/specification).
          plugin_root = File.join(Config.app_config_path(File.dirname(definition.gemfile_path)), "plugin")
          locked_bundler = definition.lockfile_exists? ? definition.lockfile!.bundler_version : nil
          if resolution.bridge_bundler_version.starts_with?("2.") || ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?.try(&.starts_with?("2.")) || locked_bundler.try(&.starts_with?("2."))
            cache_dir = File.join(plugin_root, "cache")
            (Dir.exists?(cache_dir) ? Dir.children(cache_dir).select(&.ends_with?(".gem")).map { |f| File.join(cache_dir, f) } : [] of String).each do |gem_file|
              full_name = File.basename(gem_file, ".gem")
              gems_dir = File.join(plugin_root, "gems", full_name)
              next if Dir.exists?(gems_dir)
              bridge.write_installed_spec(gem_file, File.join(plugin_root, "specifications", "#{full_name}.gemspec"), gems_dir, unpack: true)
            end
          end

          # Locked-path repair (reference `spec_set.rb#materialize`): the lockfile
          # records each locked spec's dependency edges, and a lockfile written
          # without them (Bundler's locked specs never carry edges,
          # `lazy_specification.rb:26-39`) would otherwise be reused unchanged
          # forever — `check_lockfile` (`definition.rb:973-1014`) cannot see the
          # gap. Refresh the edges of the locked specs fetched in this run from
          # their real gemspecs, keeping every locked version. Runs before the
          # lockfile is written and does not touch the pending/install flow.
          if reuse && cached_paths.any?
            repaired_edges = resolution.refresh_locked_dependencies(cached_paths) do |package|
              info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(package).to_json)
              (info.dependencies || [] of JSON::Any).compact_map do |dep|
                next unless dep["type"]?.try(&.as_s?) == "runtime"
                name = dep["name"].as_s
                requirements = dep["requirements"]?.try(&.as_a?).try { |values| values.map(&.as_s) }
                Lockfile::SpecDependency.new(name, requirements)
              end
            end
          end
        ensure
          # The reference does two resolves on this path and prints one line per
          # resolve (`resolver.rb:34`); only a real edge rewrite triggers it.
          if repaired_edges
            stdout.puts "Resolving dependencies..."
            stdout.puts "Resolving dependencies..."
          end
          # The reference's parallel installer prints all Fetching lines first
          # and the Installing lines as workers finish, so the order inside a
          # batch depends on thread scheduling. With `jobs = 1` it installs one
          # spec at a time and prints that spec's Fetching/Installing pair
          # before moving on (`parallel_installer.rb`), which is deterministic.
          # 2.7 repairs the lockfile one spec at a time and always interleaves.
          sequential = config["jobs"] == 1
          if (repaired_edges && resolution.bridge_bundler_version.starts_with?("2.")) || sequential
            # 2.7 repairs the lockfile one spec at a time, so each gem's
            # Fetching line is immediately followed by its Installing line;
            # 4.0 keeps the batched order (pinned stdout of
            # lock-missing-dependency-edges on both profiles).
            pending.each do |spec|
              install_events.each do |event|
                stdout.puts event[:line] if event[:kind] == "fetch" && event[:name] == spec.full_name
              end
              install_events.each do |event|
                stdout.puts event[:line] if event[:kind] == "install" && event[:name] == spec.full_name
              end
            end
            flushed_names = pending.map(&.full_name).to_set
            install_events.each do |event|
              stdout.puts event[:line] unless flushed_names.includes?(event[:name])
            end
          else
            install_events.each { |event| stdout.puts event[:line] }
          end
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
          render_standalone_setup(install_path,
            standalone_specs(specs, resolution.evaluation.dependencies, standalone_groups(rest)))
          # `definition.specs_for(groups)` re-materializes the selected groups,
          # so the reference fetches the index once more before its summary
          # (installer/standalone.rb L10-12).
          if !standalone_groups(rest).empty?
            remote = resolution.primary_remote
            if remote.starts_with?("file:")
              stdout.puts "Fetching source index from #{remote}"
            else
              stdout.puts "Fetching gem metadata from #{remote}."
            end
          end
        end

        # Plugin lifecycle hook (architecture §2.2); no-op without plugins.
        # The reference runs `gem_after_install` from inside the installer once
        # per spec whose install just finished (`parallel_installer.rb:217`),
        # including specs that were already installed and the running Bundler's
        # own spec, which is always part of the install set. We emit that
        # `bundler` pseudo-spec first; the reference's order is not guaranteed
        # because its hooks fire from parallel install workers (`.d/oracle11b-4.0.24/`
        # `proj-path/hook-log` records `alpha`/`beta`/`bundler` on the rerun). It runs before the lockfile write and
        # before `cli/install.rb` prints the "Bundle complete!" summary
        # (`installer.rb` hook call, then `definition.to_lock`); a raising hook
        # must therefore leave no `Gemfile.lock` and no summary line behind (G2).
        if PluginHooks.enabled?(config)
          hook_specs = [] of {String, String}
          hook_specs << {"bundler", "bundler-#{resolution.bridge_bundler_version}"}
          specs.each { |spec| hook_specs << {spec.name, spec.full_name} }
          first_hook = true
          hook_specs.each do |(hook_name, hook_full_name)|
            result = PluginHooks.call(bridge, definition, "after-install", hook_name, hook_full_name)
            stdout.print result.output
            # The reference re-loads the plugin index on every `Plugin.hook`
            # call, so it warns once per spec; we warn once per command to keep
            # the pinned missing-path stderr stable (declared difference).
            if first_hook
              result.missing.each do |entry|
                stderr.puts "The following plugin paths don't exist: #{entry.paths.join(", ")}."
                stderr.puts
                stderr.puts "This can happen if the plugin was installed with a different version of Ruby that has since been uninstalled."
                stderr.puts
                stderr.puts "If you would like to reinstall the plugin, run:"
                stderr.puts
                stderr.puts "bundler plugin uninstall #{entry.plugin} && bundler plugin install #{entry.plugin}"
                stderr.puts
                stderr.puts "Continuing without installing plugin #{entry.plugin}."
              end
              first_hook = false
            end
            case result.status
            when "load_failed"
              stderr.puts "Failed loading plugin #{result.plugin}: #{result.message}"
              return 1
            when "hook_failed"
              stderr.puts "Plugin hook after-install failed: #{result.message}"
              return 1
            end
          end
        end

        # `Installer.install` fires `gem_after_install_all` after the install
        # run (`installer.rb:12-20`); the summary below belongs to
        # `cli/install.rb`, so the hook output precedes `Bundle complete!`.
        if code = PluginHooks.run(bridge, definition, config, "after-install-all", stdout, stderr)
          return code
        end

        # `parallel_installer.rb:18` emits one debug line per installed spec;
        # our installer is sequential, so the worker prefix is always `0` (the
        # reference prints `0` on the lock-reuse path too).
        if verbose_output
          bundler_version = resolution.bridge_bundler_version
          stdout.puts "Using bundler #{bundler_version}"
          # The default gem's `loaded_from` renders as
          # `<gems dir>/gems/<full_name>/../../specifications/<full_name>.gemspec`
          # in the reference (a plain join of the stub's paths, never
          # normalised), so keep the `../..` segment. Both profiles print it.
          bundler_spec = File.join(bridge.ruby_environment.ruby_default_dir || bridge.ruby_environment.default_gem_dir, "gems",
            "bundler-#{bundler_version}", "..", "..", "specifications",
            "bundler-#{bundler_version}.gemspec").gsub('\\', "/")
          stdout.puts "0:  bundler (#{bundler_version}) from #{bundler_spec}"
          specs.sort_by(&.full_name).each do |spec|
            next unless spec.source_type == "GEM"
            stdout.puts "Using #{spec.name} #{spec.version}"
            spec_path = File.join(install_root, "specifications",
              "#{spec.full_name}.gemspec").gsub('\\', "/")
            stdout.puts "0:  #{spec.name} (#{spec.version}) from #{spec_path}"
          end
        end

        if summary
          deps_count = resolution.evaluation.dependencies.count { |d| !d.gemspec_dev_dep && !hidden_plugins.includes?(d.name) }
          gems_count = specs.size
          # 2.7.x counts the running Bundler; a switched run counts the
          # switched-to bundler instead
          if resolution.switched_bundler
            gems_count += 1
          elsif resolution.bridge_bundler_version.starts_with?("2.")
            gems_count += 1
          end
          # The reference updates the app cache during install whenever
          # `vendor/cache` exists (and caching wasn't disabled/frozen).
          app_cache = File.join(File.dirname(definition.gemfile_path), "vendor", "cache")
          if Dir.exists?(app_cache) && !config.frozen? && !rest.includes?("--no-cache")
            stdout.puts "Updating files in vendor/cache"
          end
          stdout.puts "Bundle complete! #{deps_count} Gemfile dependenc#{deps_count == 1 ? "y" : "ies"}, #{gems_count} gem#{gems_count == 1 ? "" : "s"} now installed."
          # `cli/install.rb` L59-64 as of 2.7.2/4.0.24: system gems report the
          # `bundle info` hint, a custom path prints the base path relative to
          # the working directory (no ruby scope).
          if InstallPaths.use_system_gems?(config, bridge.ruby_environment.default_gem_dir)
            stdout.puts "Use `bundle info [gemname]` to see where a bundled gem is installed."
          else
            # `Pathname` renders with `/` even on Windows, and the reference
            # prints it back with `./` for paths below the working directory.
            relative = InstallPaths.base_path_relative_to_pwd(config, definition.project_root)
            stdout.puts "Bundled gems are installed into `#{relative.gsub(/\\/, "/")}`"
          end
          plugin_messages.each do |(plugin_name, message)|
            stdout.puts "Post-install message from #{plugin_name}:"
            stdout.puts message
          end
          print_cooldown_summary(resolution, stdout)
          # `cli/install.rb:69`: BUNDLE_CLEAN runs the cleaner after the
          # cooldown summary and before the funding hint (`cli/install.rb:74`).
          clean_after_install(stdout, definition, resolution.generated_lockfile, install_root, bridge)
          # `cli/install.rb:74`: the funding hint is the last line group of the
          # install summary, after post-install messages and the cooldown line.
          # The reference reads it off the freshly resolved definition, so use
          # the generated lock rather than the file on disk (written below).
          print_fund_summary(definition, resolution.evaluation, resolution.generated_lockfile, bridge, stdout)
        end

        unless rest.includes?("--no-lock") || config.frozen?
          text = resolution.generated_lockfile.to_lock
          existing = File.file?(definition.lockfile_path) ? File.read(definition.lockfile_path) : nil
          # Reference parity: install leaves the lockfile untouched when the
          # semantic content is unchanged — formatting-only deltas (BUNDLED
          # WITH indent across profiles) do not trigger a rewrite.
          if existing.nil? || semantic_content(existing) != semantic_content(text)
            Lockfile.write(definition.lockfile_path, text, preserve_crlf: preserve_lockfile_crlf?)
          end
        end

        0
      ensure
        lock.try(&.close)
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
    # `--standalone[=GROUP...]` is a Thor `:array` option (cli/install.rb L105):
    # a bare flag means every group, otherwise the value carries the group list.
    private def self.standalone_groups(rest : Array(String)) : Array(String)
      groups = [] of String
      index = 0
      while index < rest.size
        arg = rest[index]
        if arg == "--standalone"
          following = rest[index + 1]?
          while following && !following.starts_with?("-")
            groups.concat(following.split(',').map(&.strip).reject(&.empty?))
            index += 1
            following = rest[index + 1]?
          end
        elsif value = arg.lchop?("--standalone=")
          groups.concat(value.split(',').map(&.strip).reject(&.empty?))
        end
        index += 1
      end
      groups.uniq
    end

    # `Bundler::Standalone#generate` renders `definition.specs_for(groups)`
    # (installer/standalone.rb L10-12): without groups that is every spec but
    # the running bundler, otherwise the selected groups plus their transitive
    # dependencies.
    private def self.standalone_specs(specs : Array(Resolution::ResolvedSpec),
                                      deps : Array(Bridge::EvaluatedDependency),
                                      groups : Array(String)) : Array(Resolution::ResolvedSpec)
      return specs.reject { |spec| spec.name == "bundler" } if groups.empty?

      by_name = {} of String => Resolution::ResolvedSpec
      specs.each { |spec| by_name[spec.name] = spec unless by_name.has_key?(spec.name) }
      selected = Set(String).new
      queue = deps.select { |dep| !(dep.groups & groups).empty? }.map(&.name)
      until queue.empty?
        name = queue.pop
        next if selected.includes?(name)
        next unless spec = by_name[name]?
        selected << name
        spec.dependencies.each { |dep| queue << dep.name }
      end
      specs.select { |spec| selected.includes?(spec.name) }
    end

    private def self.render_standalone_setup(install_path : String, specs : Array(Resolution::ResolvedSpec)) : Nil
      target = File.join(install_path, "bundler")
      Dir.mkdir_p(target)
      body = String.build do |io|
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
      end
      # The reference opens the file in text mode (`File.open(..., "w")`), so
      # Windows gets CRLF line endings.
      {% if flag?(:windows) %}
        body = body.gsub("\n", "\r\n")
      {% end %}
      File.write(File.join(target, "setup.rb"), body)
    end

    # ------------------------------------------------------------------
    # cache / package / pack
    # ------------------------------------------------------------------
    def self.cache(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      with_gemfile_overrides(rest) do
        run_cache(stdout, stderr, rest)
      end
    end

    # `bundle cache` accepts switches that `install` does not (`--cache-path`,
    # `--all-platforms`, `--no-install`); strip those before delegating to the
    # install pipeline, which validates with INSTALL_SWITCH_*.
    private def self.install_args_from_cache(rest : Array(String)) : Array(String)
      filtered = [] of String
      skip_value = false
      rest.each do |arg|
        if skip_value
          skip_value = false
          next
        end
        if arg == "--cache-path" || arg == "--path"
          skip_value = true
          next
        end
        next if arg.starts_with?("--cache-path=") || arg.starts_with?("--path=")
        next if arg == "--all-platforms" || arg == "--no-install"
        filtered << arg
      end
      filtered
    end

    # `SharedHelpers.relative_lockfile_path` (shared_helpers.rb:223-232): the
    # lockfile path relative to the process cwd; an absolute path is the
    # fallback when cwd and lockfile sit on different drives.
    private def self.relative_lockfile_path(definition : Definition) : String
      fallback = File.join(File.dirname(definition.gemfile_path), "Gemfile.lock").gsub('\\', "/")
      lockfile = definition.lockfile_path || fallback
      begin
        Path[lockfile].relative_to(Path[Dir.current]).to_s.gsub('\\', "/")
      rescue ArgumentError
        lockfile
      end
    end

    private def self.run_cache(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
      if removed = Commands.removed_flag(rest, "cache")
        if bundle_version.starts_with?("2.")
          stderr.puts Commands.removed_flag_deprecation(removed) unless removed.special_message
        else
          stderr.puts Commands.word_wrap(Commands.removed_flag_message(removed), 80)
          return 15
        end
      end
      if code = reject_unknown_switches(stderr, rest, CACHE_SWITCH_FLAGS, CACHE_SWITCH_VALUES, CACHE_SUGGEST_DICTIONARY)
        return code
      end
      if code = reject_positional_arguments(stderr, "cache", rest, CACHE_SWITCH_FLAGS, CACHE_SWITCH_VALUES)
        return code
      end

      # `--path` is declared by Thor but rejected before the install in 4.x;
      # 2.7.x only deprecates it and remembers it as the install path
      # (`Bundler::CLI::Cache#install` forwards the option to the installer).
      has_path = rest.any? { |arg| arg == "--path" || arg.starts_with?("--path=") }
      if has_path
        if bundle_version.starts_with?("2.")
          stderr.puts "[DEPRECATED] The `--path` flag is deprecated because its semantics are unclear. Use `bundle config cache_path` to configure the path of your cache of gems, and `bundle config path` to configure the path where your gems are installed, and stop using this flag"
        else
          stderr.puts Commands.word_wrap("The `--path` flag has been removed because its semantics were unclear. Use `bundle config cache_path` to configure the path of your cache of gems, and `bundle config path` to configure the path where your gems are installed, and stop using this flag", 80)
          return 15
        end
      end

      definition = Definition.build
      if unsupported = Commands.unsupported_setting_error(definition.config, stderr)
        stderr.puts unsupported
        return 1
      end
      if has_path && bundle_version.starts_with?("2.")
        if path_value = flag_value(rest, "--path")
          definition.config.set_local("path", path_value) unless path_value.empty?
        end
      end
      cache_arg = flag_value(rest, "--cache-path") if rest.any? { |a| a == "--cache-path" || a.starts_with?("--cache-path=") }
      # `Bundler.app_cache` = `Pathname.new(custom_path || root).join(cache_path)`
      # (bundler.rb:340-343), and `cache_path` defaults to "vendor/cache"
      # (settings.rb:304-306) — both resolve against the Gemfile root, never the
      # invocation cwd. `CLI::Cache#run` installs a `--cache-path` flag as a
      # command-option setting (cli/cache.rb:11), so the flag wins over the
      # configured/env value, and `runtime.rb:115` prints the raw setting.
      gemfile_root = File.dirname(definition.gemfile_path)
      configured_cache = definition.config["cache_path"].as?(String)
      cache_label = cache_arg || (configured_cache.nil? || configured_cache.empty? ? "vendor/cache" : configured_cache)
      cache_target = File.expand_path(cache_label, gemfile_root)

      # `cache` always runs the install pipeline (reference `CLI::Cache#run` →
      # `CLI::Install`); `--no-install` only suppresses unpacking the gems.
      code = install(stdout, stderr, install_args_from_cache(rest), no_install: rest.includes?("--no-install"), cli_arguments: false)
      return code if code != 0

      Commands.validate_ruby_runtime!(definition)
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
        install_root = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), "cache")
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

        # `Source::Path#cache` (source/path.rb:84-96): with `cache_all` on, a
        # path source that lives OUTSIDE the Gemfile root is copied wholesale
        # into the cache directory and stamped with an empty `.bundlecache`;
        # an in-project path source is never copied. `cache_all` defaults to
        # true in 4.x (settings.rb:88 `"BUNDLE_CACHE_ALL" => true`), so only an
        # explicit `false` disables it. The destination directory is named
        # after the source's gem name (`app_cache_dirname`, path.rb:110-112).
        if definition.config["cache_all"] != false
          root_prefix = gemfile_root.gsub('\\', "/").chomp("/") + "/"
          definition.lockfile!.sources.each do |source|
            next unless source.type == "PATH"
            original = source.remote
            next if original.nil?
            source_path = File.expand_path(original, gemfile_root)
            next unless Dir.exists?(source_path)
            next if source_path.gsub('\\', "/").starts_with?(root_prefix)
            dir_name = source.specs.first?.try(&.name) || File.basename(source_path)
            destination = File.join(cache_target, dir_name)
            # `rm_rf` then `cp_r("<src>/.", dest)` — the reference replaces the
            # whole directory rather than merging into a stale copy.
            FileUtils.rm_rf(destination)
            Dir.mkdir_p(destination)
            Dir.children(source_path).each do |child|
              FileUtils.cp_r(File.join(source_path, child), destination)
            end
            File.touch(File.join(destination, ".bundlecache"))
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
      # `clean` takes no arguments and declares only `--dry-run` on top of the
      # class options (cli.rb), so Thor rejects other switches and positional
      # tokens before `Bundler.load.clean` runs.
      clean_flags = BARE_SWITCH_FLAGS + ["--dry-run", "--force"]
      if code = reject_unknown_switches(stderr, rest, clean_flags, BARE_SWITCH_VALUES)
        return code
      end
      if code = reject_positional_arguments(stderr, "clean", rest, clean_flags, BARE_SWITCH_VALUES)
        return code
      end
      dry_run = rest.includes?("--dry-run")
      force = rest.includes?("--force")
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        # `cli/clean.rb:11-24` refuses to prune a system-wide gem set without
        # `--force`: with no `path` configured the install root IS the RubyGems
        # directory, so cleaning would delete every gem outside this bundle.
        # `--dry-run` never reaches the guard in the reference.
        if !dry_run && !force &&
           InstallPaths.use_system_gems?(definition.config, bridge.ruby_environment.default_gem_dir)
          raise InvalidOptionError.new(
            "Cleaning all the gems on your system is dangerous! If you're sure " \
            "you want to remove every system gem not in this bundle, run " \
            "`bundle clean --force`.")
        end
        begin
          evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
          if requested = Commands.requested_ruby_version(evaluation)
            RubyRuntime.validate_version!(requested, bridge.ruby_environment)
          end
        rescue ex : Error
          raise ex
        rescue
        end
        abi = ruby_abi(bridge)
        install_root = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi))
        # `Bundler.load.clean` goes through `Bundler.definition`, which resolves
        # the Gemfile when there is no lockfile yet (cli/clean.rb:14).  The
        # sources stay local-only: clean never fetches the index.
        lockfile = materialize_lockfile(definition, stdout, local_only: true)
        # specs_to_keep (pinned `Bundler::Runtime#clean`): lockfile specs plus
        # the running bundler itself (not installed via Source::Rubygems here).
        # The reference keeps the locked specs for both 4.0.x and 2.7.x; the
        # earlier 2.7.x "clean everything" special case was an artifact of
        # differential output truncated by a harness defect and is withdrawn
        # (2026-11-15).
        keep_names = lockfile.specs.map(&.full_name).to_set

        perform_clean(stdout, install_root, keep_names, lockfile, dry_run)
        0
      ensure
        bridge.close
      end
    end

    # Shared removal pass for `bundle clean` and the install/update tail
    # (`Bundler::Cleaner#run`): keeps the locked specs, drops every other gem
    # directory, specification, cached gem and stale git checkout. Only gem/git
    # directory removals are announced, mirroring `Runtime#remove_dir`.
    private def self.perform_clean(stdout : IO, install_root : String, keep_names : Set(String),
                                   lockfile : Lockfile::Data, dry_run : Bool) : Nil
      # Stale git checkouts: any <base>-* directory not holding a locked
      # Git source checkout (locked git sources are kept for both profiles).
      checkout_keep = Set(String).new
      lockfile.sources.each do |section|
        next unless section.type == "GIT"
        checkout_keep << GitSource.base_name(section.remote || "")
      end
      git_root = File.join(install_root, "bundler", "gems")
      stale_git_dirs = [] of String
      if Dir.exists?(git_root)
        stale_git_dirs = Dir.children(git_root).select do |name|
          full = File.join(git_root, name)
          Dir.exists?(full) && name != "extensions" && !checkout_keep.any? { |base| name.starts_with?("#{base}-") }
        end
      end

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
    end

    # `clean_after_install` (`cli/common.rb:150-156`): `bundle install` and
    # `bundle update` run `Bundler::Cleaner.new(definition, false, false).run`
    # after the install when `settings[:clean]` is set (BUNDLE_CLEAN), keeping
    # the locked specs and removing everything else inside the bundle path.
    def self.clean_after_install(stdout : IO, definition : Definition, lockfile : Lockfile::Data,
                                 install_root : String, bridge : Bridge::Client) : Nil
      return unless definition.config["clean"] == true
      keep_names = lockfile.specs.map(&.full_name).to_set
      # The running Bundler may live inside the bundle path (`bundle update`
      # installs it on version switch); never clean it away.
      gems_dir = File.join(install_root, "gems")
      if Dir.exists?(gems_dir)
        Dir.children(gems_dir).each { |name| keep_names << name if name.starts_with?("bundler-") }
      end
      perform_clean(stdout, install_root, keep_names, lockfile, false)
    end

    # ------------------------------------------------------------------
    # exec
    # ------------------------------------------------------------------
    def self.exec(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # `--gemfile` is applied through BUNDLE_GEMFILE so the definition and the
      # child process see the same Gemfile, but the override must not leak into
      # the caller (CLI.run is used in-process by the specs).
      previous_gemfile = ENV["BUNDLE_GEMFILE"]?
      begin
        exec_in_bundle(stdout, stderr, rest)
      ensure
        if previous_gemfile
          ENV["BUNDLE_GEMFILE"] = previous_gemfile
        else
          ENV.delete("BUNDLE_GEMFILE")
        end
      end
    end

    private def self.exec_in_bundle(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # Thor hands `exec` a splat, so the reference accepts its own switches
      # (`--gemfile`, `--keep-file-descriptors`) plus the class switches before
      # the command name; everything from the first non-switch token onward is
      # forwarded verbatim (cli.rb `desc "exec"` keeps the command's own flags).
      args = rest.dup
      gemfile_override : String? = nil
      cleaned = [] of String
      index = 0
      while index < args.size
        token = args[index]
        if token == "--"
          index += 1
          break
        end
        break unless token.starts_with?("-")
        case token
        when "--help", "-h"
          return Commands.help(stdout, ["exec"], stderr)
        when "--keep-file-descriptors", "--no-keep-file-descriptors"
          # The reference keeps descriptors by default; the switch is accepted
          # for compatibility only.
        when "--gemfile"
          index += 1
          gemfile_override = args[index]?
        else
          if value = token.lchop?("--gemfile=")
            gemfile_override = value
          else
            cleaned << token
          end
        end
        index += 1
      end
      cleaned.concat(args[index..]) if index < args.size
      rest = cleaned
      if override = gemfile_override
        ENV["BUNDLE_GEMFILE"] = File.expand_path(override)
      end

      command = rest.first?
      if command.nil? || command.empty?
        stderr.puts "bundler: exec needs a command to run"
        return 128
      end

      explicit_gemfile = ENV["BUNDLE_GEMFILE"]?
      # Reference `Bundler::CLI::Exec` never reads the Gemfile itself: it exports
      # RUBYOPT/BUNDLE_GEMFILE and execs the child, so a missing explicit
      # Gemfile surfaces as `-rbundler/setup` raising Bundler::GemfileNotFound
      # inside the child (cli/exec.rb:54-68, setup.rb:32). Skip the Crystal-side
      # definition/evaluation in that case.
      missing_explicit_gemfile = explicit_gemfile && !explicit_gemfile.empty? && !File.file?(explicit_gemfile)
      definition = missing_explicit_gemfile ? nil : Definition.build
      bridge = Bridge::Client.new
      begin
        env = bridge.ruby_environment
        # Reference Bundler.setup validates Ruby requirements during exec.
        if current_definition = definition
          begin
            evaluation = bridge.evaluate_gemfile(current_definition.gemfile_path)
            if requested = Commands.requested_ruby_version(evaluation)
              RubyRuntime.validate_version!(requested, env)
            end
          rescue ex : Error
            raise ex
          rescue
          end
        end
        bundler_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        bundler_lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
        if bundler_lib.nil? || bundler_lib.empty?
          bundler_lib = find_bundler_lib(env, bundler_version)
        end
        bundler_lib = bundler_lib.not_nil!

        abi = ruby_abi(bridge)
        bin_dir = if d = definition
                    File.join(InstallPaths.gem_root(d.config, bridge.ruby_environment.default_gem_dir, abi), "bin")
                  else
                    ""
                  end

        process_env = ENV.to_h
        # Windows environment variable names are case-insensitive at the OS
        # level, but Crystal's ENV.to_h preserves the original casing (e.g.
        # "Path" rather than "PATH").  Normalise every PATH variant to the
        # canonical "PATH" key so that the child process receives a single,
        # complete PATH instead of a stale "Path" shadowing the injected
        # "PATH".
        path_value = ENV["PATH"]? || ""
        process_env.keys.select { |k| k.downcase == "path" }.each { |k| process_env.delete(k) }
        # Never inject a `-r` that cannot resolve: a missing bundler lib would
        # abort the child with a LoadError before the command runs.
        unless bundler_lib.empty?
          # Forward slashes matter: the child's own `bundler/setup` compares
          # its `-r` entry against RUBYOPT verbatim (shared_helpers.rb:362-372),
          # and a backslash path would make it append a second, equivalent
          # entry (task-48 S1). Reference `exec.rb:59` injects a slash path.
          setup_path = File.join(bundler_lib, "bundler/setup").gsub('\\', "/")
          setup_require = setup_path.includes?(" ") ? "-rbundler/setup" : "-r#{setup_path}"
          existing_rubyopt = (process_env["RUBYOPT"]? || "").split(" ").reject(&.empty?)
          # The bridge reports its own setup entry with Windows backslashes
          # (`-rC:\...\bundler\setup` on some hosts), so compare after
          # normalizing separators. Reference `shared_helpers.rb:355,362-372`
          # drops any existing `-rbundler/setup` and adds exactly one entry.
          normalized_setup = normalize_env_path(setup_require)
          existing_rubyopt.reject! do |arg|
            normalized = normalize_env_path(arg)
            normalized == "-rbundler/setup" || normalized.ends_with?("/bundler/setup")
          end
          unless existing_rubyopt.any? { |arg| normalize_env_path(arg) == normalized_setup }
            existing_rubyopt.unshift(setup_require)
          end
          process_env["RUBYOPT"] = existing_rubyopt.join(" ")
          rubylib = (process_env["RUBYLIB"]? || "").split(path_delimiter_static).reject(&.empty?)
          normalized_lib = normalize_env_path(bundler_lib)
          rubylib.reject! { |entry| normalize_env_path(entry) == normalized_lib }
          rubylib.unshift(bundler_lib)
          process_env["RUBYLIB"] = rubylib.join(path_delimiter_static)
          process_env["BUNDLER_SETUP"] = setup_path
          exe_candidate = File.join(bundler_lib, "..", "exe", "bundle")
          process_env["BUNDLE_BIN_PATH"] = File.expand_path(exe_candidate).gsub(/\\/, "/") if File.file?(exe_candidate)
        end
        gemfile_for_env = definition.try(&.gemfile_path) || explicit_gemfile.not_nil!
        lockfile_for_env = definition.try(&.lockfile_path) || "#{gemfile_for_env}.lock"
        process_env["BUNDLE_GEMFILE"] = File.expand_path(gemfile_for_env).gsub(/\\/, "/")
        process_env["BUNDLE_LOCKFILE"] = File.expand_path(lockfile_for_env).gsub(/\\/, "/")
        process_env["BUNDLER_VERSION"] = bundler_version
        path_delimiter = {{ flag?(:windows) }} ? ";" : ":"
        process_env["PATH"] = bin_dir.empty? ? path_value : "#{bin_dir.gsub(/\\/, "/")}#{path_delimiter}#{path_value}"

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
          search_path = process_env["PATH"]? || ""
          resolved = find_executable(command, search_path)
          if resolved.nil?
            stderr.puts "bundler: command not found: #{command}"
            stderr.puts "Install missing gem executables with `bundle install`"
            return 127
          end
        end

        disable_exec_load = definition.try { |d| d.config["disable_exec_load"] == true } || false
        loadable = !disable_exec_load && directly_loadable?(resolved, env.ruby_exe, stderr)
        executable : String
        exec_args : Array(String)
        via_shell = false
        if loadable
          # Bundler's loadable-script optimization: run the script through the
          # Ruby runtime adapter's Kernel.load entry point instead of a fresh
          # shebang process. The loader sets $0/ARGV and restores SIGINT to
          # DEFAULT exactly as Bundler::CLI::Exec#kernel_load does.
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
          executable = env.ruby_exe
          exec_args = ["-e", loader, File.expand_path(resolved)] + args
        elsif resolved.downcase.ends_with?(".bat") || resolved.downcase.ends_with?(".cmd")
          executable = "cmd"
          exec_args = ["/c", resolved] + args
          via_shell = true
        elsif resolved.downcase.ends_with?(".exe") || executable_binary?(resolved)
          executable = resolved
          exec_args = args
        elsif ruby_shebang?(resolved)
          # Parity with the reference's directly-loadable path: a Ruby
          # executable still runs under the bundle's RUBYOPT/RUBYLIB.
          executable = "ruby"
          exec_args = [resolved] + args
        elsif File.executable?(resolved) || {{ flag?(:windows) }}
          executable = resolved
          exec_args = args
        else
          stderr.puts "bundler: not executable: #{command}"
          return 126
        end

        run_with_forwarded_signals(executable, exec_args, process_env, via_shell)
      ensure
        bridge.close
      end
    end

    private def self.path_delimiter_static : String
      {{ flag?(:windows) }} ? ";" : ":"
    end

    # Compares environment entries (RUBYOPT `-r` targets, RUBYLIB directories)
    # after normalizing Windows separators and trailing slashes; the bridge
    # reports its own bundler setup entry with backslashes on some hosts, and a
    # raw comparison would therefore inject a duplicate `-r` (task-48 S1).
    private def self.normalize_env_path(value : String) : String
      value.gsub('\\', '/').sub(/\/+$/, "")
    end

    # Runs the child and forwards SIGINT (the reference's only trapped
    # signal) so `bundle exec` behaves like the same-process Kernel.load path.
    private def self.run_with_forwarded_signals(executable : String, args : Array(String),
                                                env : Hash(String, String), via_shell : Bool) : Int32
      process = Process.new(executable, args, env: env,
        input: :inherit, output: :inherit, error: :inherit, shell: via_shell)
      {% unless flag?(:windows) %}
        Signal::INT.trap { process.signal(Signal::INT) }
      {% end %}
      process.wait.exit_code
    ensure
      {% unless flag?(:windows) %}
        Signal::INT.reset
      {% end %}
    end

    # Locate the reference bundler library for exec's setup injection.
    # `exec.rb:59` loads the bundler that ships with the running `bundle`
    # (`require_relative "../setup"`), i.e. entirely independent of GEM_PATH.
    # Mirror that by searching RubyGems' built-in path first (`Gem.default_path`
    # ignores a user-set GEM_PATH), then the configured gem paths, then any
    # installed bundler version.
    private def self.find_bundler_lib(env : Bridge::RubyEnvironment, version : String) : String
      roots = [] of String
      roots.concat(env.default_path || [] of String)
      roots << env.default_gem_dir unless env.default_gem_dir.empty?
      roots.concat(env.gem_paths)
      if user = env.user_gem_dir
        roots << user unless user.empty?
      end
      roots = roots.uniq
      roots.each do |dir|
        candidate = File.join(dir, "gems", "bundler-#{version}", "lib")
        return candidate if File.file?(File.join(candidate, "bundler", "setup.rb"))
      end
      roots.each do |dir|
        gems_dir = File.join(dir, "gems")
        next unless Dir.exists?(gems_dir)
        entries = Dir.children(gems_dir).select(&.starts_with?("bundler-")).sort!.reverse!
        entries.each do |entry|
          candidate = File.join(gems_dir, entry, "lib")
          return candidate if File.file?(File.join(candidate, "bundler", "setup.rb"))
        end
      end
      ruby_lib = File.expand_path("../lib", File.dirname(env.ruby_exe))
      File.file?(File.join(ruby_lib, "bundler", "setup.rb")) ? ruby_lib : ""
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
        "#! ruby\n",
        "#!#{ruby_exe.gsub(/\\/, "/")}\n",
      ]
      bytes = Bytes.new(possibilities.map(&.bytesize).max)
      File.open(path, "rb") { |io| io.read(bytes) }
      header = String.new(bytes)
      possibilities.any? { |shebang| header.starts_with?(shebang) } || header.starts_with?("#! ruby\r\n")
    rescue
      false
    end

    private def self.ruby_shebang?(path : String) : Bool
      return false unless File.file?(path)
      return false if File.size(path) == 0
      first_line = File.open(path, "rb") { |io| io.gets_to_end }.lines.first? || ""
      first_line == "#!/usr/bin/env ruby" ||
        first_line == "#!/usr/bin/env ruby -w" ||
        first_line == "#!/usr/bin/env jruby" ||
        first_line == "#!/usr/bin/env truffleruby" ||
        first_line == "#! ruby" ||
        first_line.starts_with?("#!#{ENV["RUBY"]? || "/usr/bin/ruby"}")
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

      downloader = Downloader.new("https://rubygems.org/", InstallPaths.downloader_cache_root, Commands.retry_count(definition.config), Celerite::Mirror.resolve(definition.config, "https://rubygems.org/"), Commands.ssl_option(definition.config, "ssl_ca_cert"), Commands.ssl_option(definition.config, "ssl_client_cert"), Commands.ssl_option(definition.config, "ssl_verify_mode"), definition.config.credentials_for("https://rubygems.org/"), timeout: Commands.timeout_seconds(definition.config), proxy: Celerite::Proxy.resolve(definition.config), warning_io: stderr, notice: -> { stdout.puts "" })
      cached = downloader.fetch("bundler", locked, nil, nil)
      stdout.puts "Fetching gem metadata from https://rubygems.org/."

      bridge = Bridge::Client.new
      begin
        abi = InstallPaths.ruby_abi(bridge)
        installer = Installer.new(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi), abi, bridge, downloader, stdout)
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

    # `remembered_flag_deprecation("path", option_name: "bin")`: Thor parses
    # `--path` with `lazy_default: "bin"`, so a bare `--path` still carries the
    # value `'bin'`.  4.x raises InvalidOption (15); 2.7.x warns
    # (`[DEPRECATED] ...`) and keeps going, which is why the same helper serves
    # both profiles.
    private def self.binstubs_path_value(rest : Array(String)) : String?
      return nil unless rest.any? { |arg| arg == "--path" || arg.starts_with?("--path=") }
      # Thor's `lazy_default: "bin"` applies whenever no value follows, including
      # when the next token is another switch (`--path --force` -> "bin").
      value = flag_value(rest, "--path") || "bin"
      # cli/binstubs.rb:13-14 (2.7.x): `path_option = nil if path_option&.empty?`.
      value.empty? ? nil : value
    end

    private def self.binstubs_path_flag(value : String?, stderr : IO) : Int32?
      return nil if value.nil?
      flag = RemovedFlag.new("--path", "bin", "'#{value}'")
      if profile_2_x?
        stderr.puts removed_flag_deprecation(flag)
        nil
      else
        stderr.puts word_wrap(removed_flag_message(flag), 80)
        15
      end
    end

    # ------------------------------------------------------------------
    # binstubs
    # ------------------------------------------------------------------
    # Runtime dependencies of a cached gemspec in declaration order; the
    # binstubs "no executables" hint walks them (installer.rb:106-108 iterates
    # `spec.runtime_dependencies`).  `read_gem_spec` already serializes only
    # runtime dependencies (assets/bridge/server.rb:212).
    private def self.each_runtime_dependency(info : Bridge::GemSpecInfo, & : String ->)
      (info.dependencies || [] of JSON::Any).each do |raw|
        next unless name = raw["name"]?.try(&.as_s?)
        yield name
      end
    end

    def self.binstubs(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # Thor parses the option surface before the command body runs, so an
      # unknown switch (`--quiet` is not declared for binstubs) outranks both
      # the ruby validation and the "needs at least one gem" check. Measured:
      # bad Gemfile ruby + `binstubs --quiet` still reports the switch (15).
      if code = reject_unknown_switches(stderr, rest, BINSTUBS_SWITCH_FLAGS, BINSTUBS_SWITCH_VALUES)
        return code
      end
      # Reference `cli.rb` binstubs body: `remembered_flag_deprecation("path",
      # option_name: "bin")` runs before `Bundler.definition.validate_runtime!`,
      # so 4.x reports the removed `--path` (15) ahead of a bad Gemfile ruby
      # (18).  Thor declares `--path` with `lazy_default: "bin"`, hence a bare
      # `--path` (or `--path --force`) still reads as `'bin'`.
      path_value = binstubs_path_value(rest)
      if path_code = binstubs_path_flag(path_value, stderr)
        return path_code
      end
      names = subcommand_arguments(rest, BINSTUBS_SWITCH_FLAGS, BINSTUBS_SWITCH_VALUES)
      binstubs_remember_shebang(rest, stderr)
      # Reference `cli/binstubs.rb:12`: the runtime is validated before the
      # argument checks, so a mismatched Gemfile ruby wins over "pass a gem name".
      definition = Definition.build
      Commands.validate_runtime!(definition)
      # cli/binstubs.rb:15 (2.7.x): `set_command_option :bin, path_option` writes
      # the remembered value into `.bundle/config` right after the runtime check
      # and before the installer runs; `bin` is a REMEMBERED_KEY (settings.rb:46-52).
      if profile_2_x? && !path_value.nil?
        definition.config.set_local("bin", path_value)
      end
      if rest.includes?("--all") && !names.empty?
        stderr.puts "Cannot specify --all with specific gems"
        return 15
      end
      if names.empty? && !rest.includes?("--all")
        # cli/binstubs.rb:28-30: `Bundler.ui.error "`bundle binstubs` needs at
        # least one gem to run."` and exit 1.
        stderr.puts "`bundle binstubs` needs at least one gem to run."
        return 1
      end

      bridge = Bridge::Client.new
      begin
        abi = ruby_abi(bridge)
        install_root = File.join(InstallPaths.gem_root(definition.config, bridge.ruby_environment.default_gem_dir, abi))
        bin_dir = File.join(install_root, "bin")
        config_bin = definition.config["bin"].to_s
        # `Bundler.bin_path` (bundler.rb:120-126) expands a relative `bin`
        # against `Bundler.root` (the Gemfile's directory), not the process cwd.
        root = File.dirname(definition.gemfile_path)
        target = config_bin.empty? ? File.join(root, "bin") : File.expand_path(config_bin, root)

        all = rest.includes?("--all")
        force = rest.includes?("--force")
        custom_shebang = flag_value(rest, "--shebang")
        # `Bundler.definition.specs` resolves the Gemfile when the lockfile is
        # missing (cli/binstubs.rb:12-26), so binstubs work before the first
        # install.  Nothing is written back to the lockfile, and the sources are
        # local-only (binstubs never fetches the index).
        specs = materialize_lockfile(definition, stdout, local_only: true).specs
        # `--all` walks `definition.specs`, which always carries the running
        # bundler even when the lockfile has no `bundler` line.
        names_list = all ? (["bundler"] + specs.map(&.name)) : names
        names_list.each do |name|
          # installer.rb:98-102: RubyGems owns the bundler stub.
          if name == "bundler"
            stderr.puts "Bundler itself does not use binstubs because its version is selected by RubyGems"
            next
          end
          spec = specs.find(&.name.==(name))
          if spec.nil?
            # cli/common.rb:113-123: `gem_not_found_message(name, specs)`.
            stderr.puts gem_not_found_message_for(name, specs.map(&.name))
            return 7
          end
          gem_file = File.join(install_root, "cache", "#{spec.full_name}.gem")
          next unless File.file?(gem_file)
          info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(gem_file).to_json)
          # installer.rb:104-118: an explicit `binstubs GEM` without executables
          # points at a dependency that has some, else it reports the gem.
          if !all && info.executables.empty?
            suggestions = [] of Tuple(String, Array(String))
            each_runtime_dependency(info) do |dep_name|
              dep_spec = specs.find(&.name.==(dep_name))
              next if dep_spec.nil?
              dep_file = File.join(install_root, "cache", "#{dep_spec.full_name}.gem")
              next unless File.file?(dep_file)
              dep_info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(dep_file).to_json)
              next if dep_info.executables.empty?
              suggestions << {dep_name, dep_info.executables}
            end
            if suggestions.empty?
              stderr.puts "There are no executables for the gem #{spec.name}."
            else
              stderr.puts "#{spec.name} has no executables, but you may want one from a gem it depends on."
              suggestions.each { |dep_name, bins| stderr.puts "  #{dep_name} has: #{bins.join(", ")}" }
            end
            next
          end
          gem_dir = File.join(install_root, "gems", spec.full_name)
          bindir = info.bindir.empty? ? "bin" : info.bindir
          # `Bundler.bin_path` memoizes and mkdir_p's on first use (bundler.rb:120-126),
          # which the installer reaches only once a spec with executables is at
          # hand (installer.rb:121-130) — so a missing gem never leaves `bin/` behind.
          Dir.mkdir_p(target)
          exists = [] of String
          info.executables.each do |executable|
            source = File.join(gem_dir, bindir, executable)
            next unless File.file?(source)
            stub = File.join(target, executable)
            if File.file?(stub) && !force
              exists << executable
              next
            end
            # `Bundler::Binstub#write` (4.0.24 binstub.rb:20-27, 2.7.2 :14-22)
            # renders `templates/Executable`, never the gem's own executable:
            # the stub points at the Gemfile and re-runs `Gem.bin_path` inside
            # `bundler/setup`. The gem's executable is only probed for presence.
            profile = profile_2_x? ? "2.7.2" : "4.0.24"
            relative = BinstubTemplate.relative_gemfile_path(target, definition.gemfile_path)
            content = BinstubTemplate.render(profile, spec.name, executable, relative, custom_shebang || "ruby")
            File.write(stub, content)
            # Windows: also emit `<exe>.cmd` with the wrapper preamble
            if {% if flag?(:windows) %}true{% else %}false{% end %} || rest.includes?("--all-platforms")
              File.write(stub + ".cmd", "@ruby -x \"%~f0\" %*\n@exit /b %ERRORLEVEL%\n\n" + content)
            end
          end
          # installer.rb:151-163: only the explicit form reports skipped stubs.
          unless all || exists.empty?
            stderr.puts case exists.size
            when 1 then "Skipped #{exists[0]} since it already exists."
            when 2 then "Skipped #{exists.join(" and ")} since they already exist."
            else
              "Skipped #{exists[0...-1].join(", ")} and #{exists.last} since they already exist."
            end
            stderr.puts "If you want to overwrite skipped stubs, use --force."
          end
        end
        0
      ensure
        bridge.close
      end
    end
  end
end
