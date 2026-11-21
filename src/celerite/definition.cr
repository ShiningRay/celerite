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

    # Lockfile parsing can emit deprecation warnings (`lockfile_parser.rb:144-159`).
    # They belong to the command's stderr, but parsing happens deep inside the
    # definition, so `CLI.run` points this sink at the stderr it was given.
    class_property default_warning_sink : IO = STDERR

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
      @lockfile ||= begin
        data = Lockfile::Parser.parse(lockfile_text, @lockfile_path)
        normalize_legacy_mingw_platform(data)
        data
      end
    end

    # `x64-mingw32` in `PLATFORMS` is deprecated. 4.0.24 warns on every parse
    # (`lockfile_parser.rb:157-159` → `shared_helpers.rb:129-131`); 2.7.2
    # rewrites the platform while parsing and warns with the removal wording
    # (`lockfile_parser.rb:144-155`), except in frozen mode where it leaves the
    # lockfile untouched. Measured: 4.0.24 `lock`/`check`/`install`/`update` all
    # warn; 2.7.2 warns on the first command that parses and drops the platform,
    # so later commands no longer see it.
    LEGACY_MINGW_PLATFORM = "x64-mingw32"
    MINGW_UCRT_PLATFORM   = "x64-mingw-ucrt"

    private def normalize_legacy_mingw_platform(data : Lockfile::Data) : Nil
      section = data.platforms_section
      return unless section
      return unless section.platforms.includes?(LEGACY_MINGW_PLATFORM)
      return if config["silence_deprecations"] == true

      if (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
        return if config["frozen"] == true

        if section.platforms.includes?(MINGW_UCRT_PLATFORM)
          section.platforms.delete(LEGACY_MINGW_PLATFORM)
          self.class.default_warning_sink.puts "[DEPRECATED] Found x64-mingw32 in lockfile, which is deprecated. " \
                                               "Removing it. Support for x64-mingw32 will be removed in Bundler 4.0."
        else
          index = section.platforms.index(LEGACY_MINGW_PLATFORM).not_nil!
          section.platforms[index] = MINGW_UCRT_PLATFORM
          self.class.default_warning_sink.puts "[DEPRECATED] Found x64-mingw32 in lockfile, which is deprecated. " \
                                               "Using x64-mingw-ucrt, the replacement for x64-mingw32 in modern rubies, instead. " \
                                               "Support for x64-mingw32 will be removed in Bundler 4.0."
        end
        return
      end

      self.class.default_warning_sink.puts "[DEPRECATED] Found x64-mingw32 in lockfile, which is deprecated and will be removed in the future."
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

    # Reference `Definition#converge_dependencies` (definition.rb:1051-1086)
    # decides `@dependency_changes`, the only trigger for `check!`'s
    # `resolve_remotely!` (definition.rb:172-182). A Gemfile dependency counts
    # as changed when its name is absent from the locked `DEPENDENCIES`, or when
    # the requirement no longer matches the locked spec
    # (`Gem::Dependency#matches_spec?` → name + `requirement.satisfied_by?(version)`).
    # A requirement *string* change that the locked version still satisfies
    # (`= 2.6.0` → `>= 2.6`) is NOT a change: the reference keeps the locked
    # resolve (no index fetch) and only rewrites `DEPENDENCIES` via
    # `cli/check.rb:33 definition.lock(true)`.
    #
    # A dependency listed in `DEPENDENCIES` without a locked spec is
    # `@missing_lockfile_dep` in the reference (definition.rb:1068-1069), not a
    # dependency change; `check` reports it through the locked-spec path.
    def gemfile_dependency_changes?(deps : Array(Bridge::EvaluatedDependency)) : Bool
      return false unless lockfile_exists?

      data = lockfile!
      locked = data.dependencies_section.try(&.dependencies) || [] of Lockfile::Dependency
      specs = data.sources.flat_map(&.specs)
      deps.any? do |dep|
        next true if locked.none? { |entry| entry.name == dep.name }
        locked_specs = specs.select { |spec| spec.name == dep.name }
        next false if locked_specs.empty?

        requirement = Gem::Requirement.new(dep.requirements)
        !requirement.satisfied_by?(Gem::Version.new(locked_specs.first.version))
      end
    rescue
      # A lockfile that cannot be parsed has no dependency view; the locked
      # path reports it through the ordinary missing-spec logic instead.
      false
    end

    # Port of `Bundler::Definition#validate_platforms!` (definition.rb:524-530),
    # part of `validate_runtime!`: refuse to continue when the lockfile does
    # not list the local platform (and does not fall back to the `ruby`
    # platform). Reference freezes the platform list only in frozen mode:
    # `Definition#initialize` calls `add_current_platform` unless
    # `Bundler.frozen_bundle?` (definition.rb:150), so `current_platform_locked?`
    # is already true when `validate_platforms!` runs. Celerite does not mutate
    # the lockfile-backed platform list at definition-build time, so mirror the
    # same outcome here and let lock generation add the local platform.
    def validate_platforms!(local_platform : String) : Nil
      return unless config.frozen?
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
                                  gemfile_sources : Array(Bridge::EvaluatedSource)? = nil,
                                  path_specs_changed : Bool = false) : Nil
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
      # `definition.rb:906-921` lists the path-gemspec reason after the
      # platform ones; our reason list only carries the sources/dependency/
      # checksums entries, so append it before them is not observable.
      reasons << "the gemspecs for path gems changed" if path_specs_changed
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
        # A dependency served by the Gemfile's default rubygems source is locked
        # in the plain `GEM` section, whose label is "no specified source"; the
        # bridge may still attach that default source to the dependency, so the
        # comparison has to fold it back (reference compares `Source` objects,
        # and `file://C:/x` / `file:///C:/x` normalise to the same identifier).
        if lock_label == "no specified source" && default_rubygems_source?(dep.source, data)
          next
        end

        changed << "* #{dep.name} from `#{lock_label}` to `#{gemfile_label}`"
      end
      default_changed = default_source_changed?(data, gemfile_sources)
      {changed, default_changed || !changed.empty?}
    end

    # `source/git.rb:76-81`: two Git sources are the same only when uri, ref,
    # branch, glob and submodules all match. Reuse must apply the same rule, so
    # a changed tag/ref/branch/glob has to re-resolve instead of rewriting the
    # old lockfile (`source/git.rb:64` is the `to_gemfile` label).
    def dependency_sources_changed?(deps : Array(Bridge::EvaluatedDependency),
                                    gemfile_sources : Array(Bridge::EvaluatedSource)?) : Bool
      !changed_dependency_sources(deps, gemfile_sources).empty?
    end

    # Names whose Gemfile source label no longer matches the locked section.
    # The resolver must also drop these from the locked index: otherwise the
    # old locked spec remains a candidate and wins as the conservative pin even
    # though the source changed.
    def changed_dependency_sources(deps : Array(Bridge::EvaluatedDependency),
                                   gemfile_sources : Array(Bridge::EvaluatedSource)?) : Array(String)
      return [] of String unless lockfile_exists?
      source_diff(deps, gemfile_sources)[0].compact_map { |line| line[/\* (\S+) from/, 1]? }
    end

    # `source/rubygems.rb:146` (`to_gemfile` is `identifier`), `source/git.rb:64`,
    # `source/path.rb:58` (`to_gemfile` is `path`); the Gemfile side of an entry
    # without an explicit `source:` option has no source at all.
    private def source_label(source : Bridge::EvaluatedSource?) : String
      return "no specified source" unless source
      case source.type
      when "Git"
        git_label(source.remote, source.branch, source.tag, source.ref, source.glob,
          source.submodules.try(&.to_s))
      when "Path"
        path_label(source.remote, source.glob)
      when "Plugin"
        plugin_label(source.remote, source.plugin_type)
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
        submodules = section.option("submodules")
        git_label(section.remote, option_string(section, "branch"), option_string(section, "tag"),
          option_string(section, "ref"), option_string(section, "glob"),
          submodules.nil? ? nil : submodules.to_s)
      when "PATH"
        path_label(option_string(section, "remote") || option_string(section, "path"),
          option_string(section, "glob"))
      when "PLUGIN SOURCE"
        plugin_label(option_string(section, "remote"), option_string(section, "type"))
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

    # True when the dependency's Gemfile source is one of the remote sources the
    # lockfile lists in its default `GEM` section(s). Only the equality verdict
    # uses this; the lockfile keeps its own spelling.
    private def default_rubygems_source?(source : Bridge::EvaluatedSource?, data : Lockfile::Data) : Bool
      return false unless source
      return false if source.type == "Git" || source.type == "Path" || source.type == "Plugin"
      remote = source.remote
      return false unless remote
      target = normalize_remote(remote)
      data.sources
        .select { |candidate| candidate.type == "GEM" }
        .flat_map { |candidate| candidate.remotes.map { |candidate_remote| normalize_remote(candidate_remote) } }
        .includes?(target)
    end

    private def git_label(remote : String?, branch : String?, tag : String?, ref : String?, glob : String?,
                          submodules : String? = nil) : String
      label = remote || ""
      specifiers = {"branch" => branch, "tag" => tag, "ref" => ref, "submodules" => submodules, "glob" => glob}
      parts = [] of String
      specifiers.each do |name, value|
        parts << "#{name}: #{value}" if value
      end
      parts.empty? ? label : "#{label} (#{parts.join(", ")})"
    end

    # `source/path.rb:64-68` (`eql?`): a PATH source's identity is the expanded
    # path plus `version` — `glob` is deliberately NOT part of it, so a glob
    # change alone never shows up as a source change here. Whether the re-resolve
    # is needed is decided by the visible spec set instead
    # (`Resolution#path_specs_changed?`).
    private def path_label(path : String?, glob : String?) : String
      return "no specified source" unless path
      File.expand_path(path, File.dirname(gemfile_path)).gsub('\\', "/")
    end

    # `plugin/api/source.rb:283-295` locks `remote:` plus `type:`.
    private def plugin_label(remote : String?, plugin_type : String?) : String
      return "no specified source" unless remote
      plugin_type ? "#{remote} (type: #{plugin_type})" : remote
    end

    private def trim_remote(value : String) : String
      normalize_remote(value)
    end

    # `file://C:/x` and `file:///C:/x` denote the same local directory (task-19
    # made the resolver accept both), so the frozen source comparison must not
    # distinguish their spellings: only the equality verdict changes; the
    # written lockfile still carries the original string. The bridge also
    # round-trips the drive colon away (`C/Users/...`), which is folded back
    # here so a `file://` default source compares equal.
    private def normalize_remote(value : String) : String
      return value unless value.downcase.starts_with?("file:")
      body = value.sub(/\Afile:\/\//i, "")
      body = body.sub(/\A\/+/, "")
      body = body.sub(/\/+\z/, "")
      body.sub(/\A([A-Za-z])\//) { "#{$1}:/" }
    rescue
      value
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
        next if candidate.type == "Git" || candidate.type == "Path" || candidate.type == "Plugin"
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

    # Why the locked resolution cannot be reused for the CHECKSUMS entries: the
    # reference distinguishes a *missing* store entry from an *empty* one
    # (`definition.rb:984-1002` collects them separately) and the two behave
    # differently downstream -- see `checksums_need_refresh?`.
    enum ChecksumsRefreshReason
      Missing
      Empty
    end

    # Reference `Definition#something_changed?` / `#empty_checksums_actionable?`
    # (definition.rb:630-659): a *missing* CHECKSUMS entry always forces the
    # lockfile to be refreshed; an *empty* one only when a remote fetch can fill
    # it (`Bundler.frozen_bundle? || !sources.local_mode?`). Without a remote
    # fetch a local resolution would repeat on every setup without changing the
    # lockfile, so `--local` keeps reusing the locked resolution.
    #
    # The reason matters beyond "refresh or not": a missing entry makes the
    # reference run a real resolution, so it announces
    # `Resolving dependencies...` (`resolver.rb:34`), while an empty entry only
    # re-reads the index without resolving and stays silent (measured on
    # 4.0.24). Callers that print progress must therefore branch on the reason
    # instead of on a collapsed boolean.
    def checksums_need_refresh?(local_only : Bool = false) : ChecksumsRefreshReason?
      return nil unless lockfile_exists?

      data = lockfile!
      section = data.checksums_section
      return nil unless section

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
      return ChecksumsRefreshReason::Missing if missing
      return ChecksumsRefreshReason::Empty if empty && (config.frozen? || !local_only)

      nil
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
