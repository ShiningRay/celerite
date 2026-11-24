require "./lock_fast_path"
require "./installed_index"
require "./glob"
require "./plugin_gemfile_cache"

module Celerite
  # Pure install-summary rules shared by the compatibility and no-op paths.
  # Keeping the numbers and transcript rendering together prevents the fast
  # path from drifting on Bundler's own gem, typed sources, or path hints.
  module InstallSummary
    record Summary,
      deps_count : Int32,
      gems_count : Int32,
      skipped_groups : Array(String),
      path_mode : Symbol,
      relative_path : String

    def self.build(evaluation : Bridge::GemfileEvaluation,
                   spec_names : Enumerable(String),
                   hidden_names : Enumerable(String),
                   skipped_groups : Array(String),
                   switched_bundler : Bool,
                   bundler_version : String,
                   path_mode : Symbol,
                   relative_path : String) : Summary
      hidden = hidden_names.to_set
      deps_count = evaluation.dependencies.count do |dep|
        !dep.gemspec_dev_dep && !hidden.includes?(dep.name)
      end
      # `cli/install.rb:93-96` counts `definition.specs`, i.e. the
      # materialized form of the requested dependencies. A typed source's
      # inferred `bundler-source-<type>` gem is installed by the plugin
      # installer, not the application definition, and is hidden on both sides.
      gems_count = spec_names.count { |name| !hidden.includes?(name) }
      # 2.7.x counts the running Bundler; a switched run counts the
      # switched-to Bundler instead (`cli/common.rb:57`).
      gems_count += 1 if switched_bundler || bundler_version.starts_with?("2.")
      Summary.new(deps_count, gems_count, skipped_groups, path_mode, relative_path)
    end

    def self.complete_line(summary : Summary) : String
      count = summary.deps_count
      gems = summary.gems_count
      "Bundle complete! #{count} Gemfile dependenc#{count == 1 ? "y" : "ies"}, " \
      "#{gems} gem#{gems == 1 ? "" : "s"} now installed."
    end

    def self.skipped_groups_line(summary : Summary) : String?
      groups = summary.skipped_groups
      return nil if groups.empty?
      label = if groups.size == 1
                "group '#{groups.first}'"
              else
                quoted = groups.map { |group| "'#{group}'" }
                "groups #{quoted[0...-1].join(", ")} and #{quoted.last}"
              end
      "Gems in the #{label} were not installed."
    end

    def self.path_line(summary : Summary) : String
      case summary.path_mode
      when :empty
        "Bundled gems are installed into `./.`"
      when :system
        "Use `bundle info [gemname]` to see where a bundled gem is installed."
      else
        "Bundled gems are installed into `#{summary.relative_path}`"
      end
    end
  end

  # Unchanged-install fast path. It reuses `LockFastPath.trusted_attempt` for
  # every decision that can be made from the lockfile and cached evaluation;
  # only install-specific gates (argument shape, hooks, output-affecting
  # settings, installed tree, and the two summary numbers) live here.
  module InstallFastPath
    struct Hit
      getter digest : String
      getter evaluation : Bridge::GemfileEvaluation
      getter default_gem_dir : String
      getter install_root : String
      getter summary : InstallSummary::Summary

      def initialize(@digest : String, @evaluation : Bridge::GemfileEvaluation, @default_gem_dir : String,
                     @install_root : String, @summary : InstallSummary::Summary)
      end
    end

    # The Plugin::DSL preflight may be skipped only when the normal evaluation
    # and runtime record are already trusted and an empty plugin-name
    # certificate is bound to that exact fingerprint. This performs no bridge
    # work; the caller falls back to the existing Ruby preflight on any miss.
    def self.plugin_precheck_skippable?(definition : Definition, config : Config) : Bool
      return false unless PluginHooks.enabled?(config)
      # Both Bundler index files are Ruby-visible: the project-local tree and
      # the user-global tree. A root may be absent or an empty directory; an
      # index may be absent or a zero-byte regular file. Any other state keeps
      # the Plugin::DSL preflight.
      local_root = File.dirname(PluginHooks.index_path(definition))
      return false unless plugin_tree_empty?(local_root, File.join(local_root, "index"))
      if global_root = global_plugin_root
        return false unless plugin_tree_empty?(global_root, File.join(global_root, "index"))
      else
        return false
      end
      trusted, _reason = LockFastPath.trusted_attempt(definition)
      return false if trusted.nil?
      PluginGemfileCache.trusted?(trusted.digest)
    rescue
      false
    end

    private def self.global_plugin_root : String?
      if override = ENV["BUNDLE_USER_PLUGIN"]?
        return nil if override.empty?
        return File.expand_path(override)
      end
      if user_home = ENV["BUNDLE_USER_HOME"]?
        return nil if user_home.empty?
        return File.expand_path(File.join(user_home, "plugin"))
      end
      home = Config.user_home
      return nil if home.nil? || home.empty?
      File.expand_path(File.join(home, ".bundle", "plugin"))
    end

    private def self.plugin_tree_empty?(root : String, index : String) : Bool
      if File.exists?(root)
        return false unless Dir.exists?(root)
        return false unless Dir.children(root).empty?
      end
      if File.exists?(index)
        return false unless File.file?(index)
        return false unless File.size(index) == 0
      end
      true
    rescue
      false
    end

    def self.attempt(definition : Definition, config : Config, rest : Array(String),
                     summary : Bool, show_resolving : Bool, no_reuse : Bool, no_install : Bool,
                     cli_arguments : Bool, refresh_cache : Bool) : {Hit?, String?}
      return {nil, nil} unless LockFastPath.enabled?
      # Only a bare `bundle install` has a byte-stable no-op transcript. Any
      # flag can change filtering, paths, output, or filesystem side effects.
      return {nil, "switches"} unless rest.empty?
      return {nil, "switches"} unless summary && show_resolving && !no_reuse &&
                                      !no_install && cli_arguments && refresh_cache
      # `--verbose`/`BUNDLE_VERBOSE` adds progress and Ruby diagnostics that a
      # zero-spawn hit cannot synthesize.
      return {nil, "verbose"} if ENV["CELERITE_VERBOSE"]? == "1"

      trusted, reason = LockFastPath.trusted_attempt(definition)
      return {nil, reason} if trusted.nil?
      hit = trusted.not_nil!
      lockfile = definition.lockfile!
      facts = hit.facts

      # A lock written by a different Bundler profile can trigger the
      # auto-switch path, which installs Bundler and changes the summary.
      locked_bundler = lockfile.bundler_version
      return {nil, "bundler"} if locked_bundler.nil? ||
                                 locked_bundler != Celerite::Profile.bundler_version

      # These settings alter the install plan, install root, or append extra
      # summary lines. Keep them on the compatibility path even when the
      # environment signature itself still matches.
      return {nil, "groups"} if group_configured?(config)
      return {nil, "frozen"} if config.frozen? || config_bool?(config["deployment"])
      return {nil, "shared-gems"} if config_bool?(config["disable_shared_gems"])
      return {nil, "force-ruby-platform"} if config_bool?(config["force_ruby_platform"])
      return {nil, "clean"} if config_bool?(config["clean"])
      return {nil, "cooldown"} unless config["cooldown"].nil?
      return {nil, "app-cache"} if app_cache_exists?(definition, config, config.frozen?)

      default_gem_dir = facts.default_gem_dir.value
      return {nil, "default-gem-dir"} unless facts.default_gem_dir.known? && default_gem_dir
      dir = default_gem_dir.not_nil!
      abi = hit.record.abi.ruby_api_version
      install_root = InstallPaths.gem_root(config, dir, abi)
      return {nil, "funding"} if funding_possible?(definition, config, install_root)

      plan_reason = plan_complete?(lockfile, install_root, hit)
      return {nil, plan_reason} if plan_reason

      gems_count = reachable_specs(lockfile, hit.evaluation).size
      return {nil, "plan"} if gems_count.zero? && !lockfile.specs.empty?

      path_mode = if empty_bundle_path?(definition, config)
                    :empty
                  elsif InstallPaths.use_system_gems?(config, dir)
                    :system
                  else
                    :relative
                  end
      relative_path = if path_mode == :relative
                        InstallPaths.base_path_relative_to_pwd(config, definition.project_root)
                      else
                        ""
                      end
      return {nil, "hooks"} if PluginHooks.enabled?(config) &&
                               !plugin_precheck_skippable?(definition, config)
      summary = InstallSummary.build(hit.evaluation, reachable_specs(lockfile, hit.evaluation),
        [] of String, [] of String, false, Celerite::Profile.bundler_version, path_mode, relative_path)
      {Hit.new(hit.digest, hit.evaluation, dir, install_root, summary), nil}
    end

    # Prints the exact two-line no-op transcript of the compatible path.
    # `ProcessLock` is acquired by the caller around this call, matching the
    # compatibility path's serialization semantics.
    def self.emit(hit : Hit, stdout : IO, definition : Definition, config : Config) : Nil
      stdout.puts InstallSummary.complete_line(hit.summary)
      if line = InstallSummary.skipped_groups_line(hit.summary)
        stdout.puts line
      end
      stdout.puts InstallSummary.path_line(hit.summary)
    end

    private def self.config_bool?(value) : Bool
      case value
      when Bool, Int32, String, Nil then Config.to_bool(value)
      else                               false
      end
    end

    private def self.group_configured?(config : Config) : Bool
      ["with", "without", "only"].any? do |key|
        case value = config[key]
        when Array  then !value.empty?
        when String then !value.split(':').reject(&.empty?).empty?
        else             false
        end
      end
    end

    private def self.empty_bundle_path?(definition : Definition, config : Config) : Bool
      ENV["BUNDLE_PATH"]? == "" || config["path"].as?(String) == ""
    end

    private def self.app_cache_exists?(definition : Definition, config : Config, frozen : Bool) : Bool
      return false if frozen
      label = config["cache_path"].as?(String)
      label = "vendor/cache" if label.nil? || label.not_nil!.empty?
      Dir.exists?(File.expand_path(label.not_nil!, File.dirname(definition.gemfile_path)))
    end

    private def self.funding_possible?(definition : Definition, config : Config,
                                       install_root : String) : Bool
      case value = config["ignore_funding_requests"]
      when Array then return false unless value.empty?
      else
        return false if config_bool?(value)
      end

      definition.lockfile!.specs.any? do |spec|
        spec_path = File.join(install_root, "specifications", "#{spec.full_name}.gemspec")
        next false unless File.file?(spec_path)
        File.read(spec_path).includes?("funding_uri")
      end
    rescue
      true
    end

    private def self.plan_complete?(lockfile : Lockfile::Data, install_root : String,
                                    hit : LockFastPath::Hit) : String?
      specs = InstalledIndex.load([install_root])
      platform = Gem::Platform.local.to_s
      abi = hit.record.abi.ruby_api_version
      lockfile.specs.each do |spec|
        full_name = spec.full_name
        gemspecs = Glob.paths(File.join(install_root, "specifications"), "#{full_name}.gemspec")
        return "gemspec:#{full_name}" if gemspecs.empty?
        gemspec_path = gemspecs.first
        return "gemspec:#{full_name}" unless File.file?(gemspec_path)

        indices = Glob.paths(File.join(install_root, "gems"), full_name)
        return "gem-dir:#{full_name}" if indices.empty?
        gem_dir = indices.first
        return "gem-dir:#{full_name}" unless File.directory?(gem_dir)
        return "install-index:#{full_name}" unless specs.find_full_name(full_name)

        text = File.read(gemspec_path)
        next unless text.match(/\bextensions\b/)
        ext_dir = File.join(install_root, "extensions", platform, abi, full_name)
        return "native-ext:#{full_name}" unless File.directory?(ext_dir) &&
                                                File.file?(File.join(ext_dir, "gem.build_complete"))
      end
      nil
    rescue
      "install-tree"
    end

    private def self.reachable_specs(lockfile : Lockfile::Data,
                                     evaluation : Bridge::GemfileEvaluation) : Set(String)
      by_name = Hash(String, Lockfile::Spec).new
      lockfile.specs.each { |spec| by_name[spec.name] = spec unless by_name.has_key?(spec.name) }
      seen = Set(String).new
      queue = evaluation.dependencies.map(&.name)
      until queue.empty?
        name = queue.pop
        next unless seen.add?(name)
        spec = by_name[name]?
        next if spec.nil?
        spec.dependencies.each { |dep| queue << dep.name }
      end
      seen
    end
  end
end
