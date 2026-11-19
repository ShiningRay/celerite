require "./errors"
require "./config"
require "./lockfile/parser"
require "./bridge/client"

module Celerite
  # Resolves the project context for a command run: Gemfile location, lockfile
  # location, configuration (pinned contract: `Bundler.default_gemfile` /
  # `default_lockfile` discovery).
  class Definition
    getter gemfile_path : String
    getter lockfile_path : String
    getter config : Config
    getter lockfile : Lockfile::Data?

    def self.build(args : Args = Args.new) : Definition
      new(args)
    end

    struct Args
      property lockfile_override : String?

      def initialize(@lockfile_override : String? = nil)
      end
    end

    def initialize(args : Args = Args.new)
      @config = Config.new(project_root)
      @gemfile_path = Definition.find_gemfile
      @lockfile_path = Definition.resolve_lockfile(@gemfile_path, args.lockfile_override)
      @lockfile = nil
    end

    def self.find_gemfile : String
      if given = ENV["BUNDLE_GEMFILE"]?
        return given unless given.empty?
      end

      search_up("Gemfile") || search_up("gems.rb") ||
        raise GemfileNotFound.new("Could not locate Gemfile")
    end

    def self.search_up(name : String, from : String = Dir.current) : String?
      current = from
      loop do
        candidate = File.join(current, name)
        return candidate if File.file?(candidate)

        parent = File.dirname(current)
        return nil if parent == current
        current = parent
      end
    end

    def self.resolve_lockfile(gemfile_path : String, override : String?) : String
      return override if override

      if lockfile = ENV["BUNDLE_LOCKFILE"]?
        return lockfile unless lockfile.empty?
      end

      base = File.basename(gemfile_path)
      case base
      when "gems.rb" then File.join(File.dirname(gemfile_path), "gems.locked")
      else                "#{gemfile_path}.lock"
      end
    end

    def project_root : String
      if given = ENV["BUNDLE_GEMFILE"]?
        unless given.empty?
          return File.dirname(File.expand_path(given))
        end
      end
      Dir.current
    end

    # Parses (and memoizes) the lockfile. Missing lockfiles are an error like
    # the reference; `check` etc. operate only on a parsed lockfile.
    def lockfile! : Lockfile::Data
      @lockfile ||= Lockfile::Parser.parse(lockfile_text, @lockfile_path)
    end

    def lockfile_text : String
      unless File.file?(@lockfile_path)
        raise LockfileError.new("Could not find #{@lockfile_path} for resolution")
      end
      File.read(@lockfile_path)
    end

    def lockfile_exists? : Bool
      File.file?(@lockfile_path)
    end

    # True when `DEPENDENCIES` already matches the Gemfile declarations *and*
    # every dependency has a locked spec that satisfies it, i.e. `bundle lock`
    # has nothing to unlock. The reference resolves nothing in that case, so
    # plain `lock` prints only its "Writing lockfile" line and `lock --print`
    # prints only the lockfile (measured on 4.0.24 and 2.7.2). A lockfile whose
    # `specs:` list is empty (or misses a dependency) still triggers a full
    # resolution, as `spec/m7_lockfile_regen_spec.cr` pins.
    def lockfile_matches_dependencies?(deps : Array(Bridge::EvaluatedDependency)) : Bool
      return false unless lockfile_exists?
      added, deleted, changed = dependency_diff(deps)
      return false unless added.empty? && deleted.empty? && !changed

      data = lockfile!
      specs = data.sources.flat_map(&.specs)
      deps.all? do |dep|
        specs.any? do |spec|
          next false unless spec.name == dep.name
          requirement = Gem::Requirement.new(dep.requirements.map { |value| value.as(String) })
          requirement.satisfied_by?(Gem::Version.new(spec.version))
        end
      end
    rescue
      false
    end

    # Port of `Bundler::Definition#validate_platforms!` (definition.rb:524-530),
    # part of `validate_runtime!`: refuse to continue when the lockfile does
    # not list the local platform (and does not fall back to the `ruby`
    # platform). Reference freezes the platform list, so this is what a frozen
    # install reports instead of the lockfile-changes summary.
    def validate_platforms!(local_platform : String) : Nil
      return unless lockfile_exists?
      platforms = lockfile!.platforms
      return if platforms.empty? || platforms.includes?(local_platform) || platforms.includes?("ruby")

      listed = platforms.map { |platform| platform.inspect }.join(", ")
      raise ProductionError.new(
        "Your bundle only supports platforms [#{listed}] but your local platform is " \
        "#{local_platform}. Add the current platform to the lockfile with\n" \
        "`bundle lock --add-platform #{local_platform}` and try again."
      )
    end

    # `Bundler::Definition#ensure_equivalent_gemfile_and_lockfile`
    # (definition.rb:475-492): frozen mode refuses to update the lockfile.
    # Implements the source-switch and dependency-diff reasons plus the
    # CHECKSUMS ones (definition.rb:906-921 order: sources, dependencies, then
    # checksums); platform and path/git gemspec reasons remain open (see
    # docs/compat-report.md).
    def validate_frozen_lockfile!(explicit_flag : Bool = false,
                                  gemfile_dependencies : Array(Bridge::EvaluatedDependency)? = nil,
                                  gemfile_sources : Array(Bridge::EvaluatedSource)? = nil) : Nil
      return unless config.frozen?
      raise ProductionError.new("Frozen mode is set, but there's no lockfile") unless lockfile_exists?

      reasons = [] of String
      added = [] of String
      deleted = [] of String
      changed = [] of String
      if deps = gemfile_dependencies
        sources = source_diff(deps, gemfile_sources)
        changed = sources[0]
        reasons << "the list of sources changed" if sources[1]
        diff = dependency_diff(deps)
        reasons << "the dependencies in your gemfile changed" if diff[2]
        added = diff[0]
        deleted = diff[1]
      end
      if reason = lockfile_update_reason
        reasons << reason
      end
      return if reasons.empty? && added.empty? && deleted.empty? && changed.empty?

      reason = reasons.join(", ")
      lockfile_name = File.basename(lockfile_path)
      message = "#{reason[0].upcase}#{reason[1..].strip}, but "
      message += "the lockfile " unless message.starts_with?("Your lockfile")
      message += "can't be updated because frozen mode is set"
      message += "\n\nYou have added to the Gemfile:\n#{added.join("\n")}" unless added.empty?
      message += "\n\nYou have deleted from the Gemfile:\n#{deleted.join("\n")}" unless deleted.empty?
      message += "\n\nYou have changed in the Gemfile:\n#{changed.join("\n")}" unless changed.empty?
      message += "\n\nRun `bundle install` elsewhere and add the updated #{lockfile_name} to version control.\n"
      unless explicit_flag || frozen_from_environment?
        message += "\n\nIf this is a development machine, remove the #{lockfile_name} freeze by running `bundle config set frozen false`."
      end
      raise ProductionError.new(message)
    end

    # `definition.rb:598-612`: every dependency present in both the Gemfile and
    # the locked `DEPENDENCIES` is compared by source, and a mismatch is listed
    # as `* name from `lockfile source` to `gemfile source``. The labels come
    # from `Source#to_gemfile` (rubygems.rb:146 aliases `identifier`, git.rb:64,
    # path.rb:58); an unset source renders as "no specified source". A change in
    # the Gemfile's default source also counts, because the reference compares
    # the whole source list (`definition.rb:152, 908`).
    private def source_diff(deps : Array(Bridge::EvaluatedDependency),
                            gemfile_sources : Array(Bridge::EvaluatedSource)?) : Tuple(Array(String), Bool)
      data = lockfile!
      changed = [] of String
      deps.each do |dep|
        gemfile_label = source_label(dep.source)
        section = data.sources.find { |candidate| candidate.specs.any? { |spec| spec.name == dep.name } }
        lock_label = locked_source_label(section)
        next if lock_label == gemfile_label

        changed << "* #{dep.name} from `#{lock_label}` to `#{gemfile_label}`"
      end
      default_changed = default_source_changed?(data, gemfile_sources)
      {changed, default_changed || !changed.empty?}
    end

    # `source/rubygems.rb:146` (`to_gemfile` is `identifier`), `source/git.rb:64`,
    # `source/path.rb:58` (`to_gemfile` is `path`); the Gemfile side of an entry
    # without an explicit `source:` option has no source at all.
    private def source_label(source : Bridge::EvaluatedSource?) : String
      return "no specified source" unless source
      case source.type
      when "Git"
        git_label(source.remote, source.branch, source.tag, source.ref, source.glob)
      when "Path"
        source.remote || "no specified source"
      else
        remotes = source.remotes
        remote = source.remote
        names = remotes && !remotes.empty? ? remotes.join(", ") : (remote || "no specified source")
        "rubygems repository #{names}"
      end
    end

    # The lockfile side: a gem locked in the default `GEM` section has no
    # source of its own (`LockfileParser` only attaches one for `GIT`/`PATH`
    # entries), so only a differing `remote:` can be observed there.
    private def locked_source_label(section : Lockfile::SourceSection?) : String
      return "no specified source" unless section
      case section.type
      when "GIT"
        git_label(section.remote, option_string(section, "branch"), option_string(section, "tag"),
          option_string(section, "ref"), option_string(section, "glob"))
      when "PATH"
        option_string(section, "remote") || option_string(section, "path") || "no specified source"
      else
        # Gems locked in the default `GEM` section have no source of their own
        # (`LockfileParser` only records one for `GIT`/`PATH` entries), so the
        # reference compares them against the Gemfile's default source and
        # reports "no specified source" on the lockfile side.
        "no specified source"
      end
    end

    private def option_string(section : Lockfile::SourceSection, key : String) : String?
      section.option(key).as?(String)
    end

    private def git_label(remote : String?, branch : String?, tag : String?, ref : String?, glob : String?) : String
      label = remote || ""
      specifiers = {"branch" => branch, "tag" => tag, "ref" => ref, "submodules" => nil, "glob" => glob}
      parts = [] of String
      specifiers.each do |name, value|
        parts << "#{name}: #{value}" if value
      end
      parts.empty? ? label : "#{label} (#{parts.join(", ")})"
    end

    private def trim_remote(value : String) : String
      value.ends_with?("/") ? value[0...-1] : value
    end

    # `Definition#converge_sources` (definition.rb:152 and `:908`) compares the
    # whole source list, so replacing the Gemfile's default source changes the
    # lockfile even when every dependency keeps the same label. The bridge
    # serialises each rubygems source with both a `name` and the `remotes` list,
    # so the comparison has to run over the remote sets rather than the names.
    private def default_source_changed?(data : Lockfile::Data,
                                        gemfile_sources : Array(Bridge::EvaluatedSource)?) : Bool
      return false unless sources = gemfile_sources
      gemfile_remotes = [] of String
      sources.each do |candidate|
        next if candidate.type == "Git" || candidate.type == "Path"
        remotes = candidate.remotes
        if remotes && !remotes.empty?
          remotes.each { |remote| gemfile_remotes << trim_remote(remote) }
        elsif remote = candidate.remote
          gemfile_remotes << trim_remote(remote)
        end
      end
      return false if gemfile_remotes.empty?
      locked_remotes = data.sources
        .select { |candidate| candidate.type == "GEM" }
        .flat_map { |candidate| candidate.remotes.map { |remote| trim_remote(remote) } }
      return false if locked_remotes.empty?
      gemfile_remotes.uniq.sort != locked_remotes.uniq.sort
    end

    # `Definition#lockfile_changes_summary` (definition.rb:1053-1090): the
    # added/deleted lists come from set differences between the Gemfile
    # dependencies and the locked `DEPENDENCIES` entries, each rendered like
    # `SharedHelpers.pretty_dependency`. Only additions or requirement changes
    # set `@dependency_changes` (definition.rb:1051-1087); a pure deletion
    # still lists the removed dependency.
    private def dependency_diff(deps : Array(Bridge::EvaluatedDependency)) : Tuple(Array(String), Array(String), Bool)
      locked = lockfile!.dependencies_section.try(&.dependencies) || [] of Lockfile::Dependency
      added = [] of String
      changed = false
      deps.each do |dep|
        wanted = normalized_requirements(dep.requirements)
        match = locked.find { |entry| entry.name == dep.name }
        if match.nil?
          added << "* #{pretty_dependency(dep.name, wanted)}"
          changed = true
        elsif normalized_requirements(match.requirements) != wanted
          added << "* #{pretty_dependency(dep.name, wanted)}"
          changed = true
        end
      end
      deleted = [] of String
      locked.each do |entry|
        reqs = normalized_requirements(entry.requirements)
        next if deps.any? { |dep| dep.name == entry.name && normalized_requirements(dep.requirements) == reqs }

        deleted << "* #{pretty_dependency(entry.name, reqs)}"
      end
      {added, deleted, changed}
    end

    private def normalized_requirements(requirements : Array(String)?) : Array(String)
      (requirements || [] of String).reject { |value| value == ">= 0" }
    end

    private def pretty_dependency(name : String, requirements : Array(String)) : String
      return name if requirements.empty?

      "#{name} (#{requirements.join(", ")})"
    end

    # First CHECKSUMS reason the reference would report (definition.rb:984-1002:
    # a spec missing from the store wins over an entry without checksums).
    private def lockfile_update_reason : String?
      data = lockfile!
      section = data.checksums_section
      return nil unless section

      entries = section.entries
      missing : String? = nil
      empty : String? = nil
      data.sources.each do |source|
        next unless source.type == "GEM"

        source.specs.each do |spec|
          entry = entries.find { |candidate| checksum_matches?(candidate, spec) }
          if entry.nil?
            missing ||= spec.name
          elsif entry.checksums.empty?
            empty ||= spec.name
          end
        end
      end
      return "your lockfile is missing a CHECKSUMS entry for \"#{missing}\"" if missing
      return "your lockfile has an empty CHECKSUMS entry for \"#{empty}\"" if empty
      nil
    end

    # Reference `Definition#something_changed?` / `#empty_checksums_actionable?`
    # (definition.rb:630-659): a *missing* CHECKSUMS entry always forces the
    # lockfile to be refreshed; an *empty* one only when a remote fetch can fill
    # it (`Bundler.frozen_bundle? || !sources.local_mode?`). Without a remote
    # fetch a local resolution would repeat on every setup without changing the
    # lockfile, so `--local` keeps reusing the locked resolution.
    def checksums_need_refresh?(local_only : Bool = false) : Bool
      return false unless lockfile_exists?

      data = lockfile!
      section = data.checksums_section
      return false unless section

      missing = false
      empty = false
      data.sources.each do |source|
        next unless source.type == "GEM"

        source.specs.each do |spec|
          entry = section.entries.find { |candidate| checksum_matches?(candidate, spec) }
          if entry.nil?
            missing = true
          elsif entry.checksums.empty?
            empty = true
          end
        end
      end
      missing || (empty && (config.frozen? || !local_only))
    end

    private def checksum_matches?(entry : Lockfile::ChecksumEntry, spec : Lockfile::Spec) : Bool
      return false unless entry.name == spec.name && entry.version == spec.version

      entry_platform = entry.platform.nil? || entry.platform == "ruby" ? nil : entry.platform
      spec_platform = spec.platform.nil? || spec.platform == "ruby" ? nil : spec.platform
      entry_platform == spec_platform
    end

    # `SharedHelpers`/friendly-errors parity: the "remove the freeze" hint is
    # dropped when frozen comes from `BUNDLE_FROZEN` (settings source :env).
    private def frozen_from_environment? : Bool
      ENV["BUNDLE_FROZEN"]? == "true"
    end
  end
end
