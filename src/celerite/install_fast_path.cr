require "./lock_fast_path"
require "./installed_index"
require "./glob"

module Celerite
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
      getter deps_count : Int32
      getter gems_count : Int32
      getter path_mode : Symbol

      def initialize(@digest : String, @evaluation : Bridge::GemfileEvaluation, @default_gem_dir : String,
                     @install_root : String, @deps_count : Int32, @gems_count : Int32,
                     @path_mode : Symbol)
      end
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
      return {nil, "hooks"} if PluginHooks.enabled?(config)

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

      deps_count = hit.evaluation.dependencies.count { |dep| !dep.gemspec_dev_dep }
      gems_count = reachable_specs(lockfile, hit.evaluation).size
      return {nil, "plan"} if gems_count.zero? && !lockfile.specs.empty?

      path_mode = if empty_bundle_path?(definition, config)
                    :empty
                  elsif InstallPaths.use_system_gems?(config, dir)
                    :system
                  else
                    :relative
                  end
      {Hit.new(hit.digest, hit.evaluation, dir, install_root, deps_count, gems_count, path_mode), nil}
    end

    # Prints the exact two-line no-op transcript of the compatible path.
    # `ProcessLock` is acquired by the caller around this call, matching the
    # compatibility path's serialization semantics.
    def self.emit(hit : Hit, stdout : IO, definition : Definition, config : Config) : Nil
      count = hit.deps_count
      stdout.puts "Bundle complete! #{count} Gemfile dependenc#{count == 1 ? "y" : "ies"}, " \
                  "#{hit.gems_count} gem#{hit.gems_count == 1 ? "" : "s"} now installed."
      case hit.path_mode
      when :empty
        stdout.puts "Bundled gems are installed into `./.`"
      when :system
        stdout.puts "Use `bundle info [gemname]` to see where a bundled gem is installed."
      else
        relative = InstallPaths.base_path_relative_to_pwd(config, definition.project_root)
        stdout.puts "Bundled gems are installed into `#{relative}`"
      end
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
        next unless specs.find_full_name(full_name)

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
