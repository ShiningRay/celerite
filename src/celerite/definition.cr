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

    # `Bundler::Definition#ensure_equivalent_gemfile_and_lockfile`
    # (definition.rb:475-492): frozen mode refuses to update the lockfile.
    # Implements the dependency-diff reasons plus the CHECKSUMS ones
    # (definition.rb:906-921 order: dependencies before checksums); source,
    # platform and path/git gemspec reasons remain open (see
    # docs/compat-report.md).
    def validate_frozen_lockfile!(explicit_flag : Bool = false,
                                  gemfile_dependencies : Array(Bridge::EvaluatedDependency)? = nil) : Nil
      return unless config.frozen?
      raise ProductionError.new("Frozen mode is set, but there's no lockfile") unless lockfile_exists?

      reasons = [] of String
      added = [] of String
      deleted = [] of String
      if deps = gemfile_dependencies
        diff = dependency_diff(deps)
        reasons << "the dependencies in your gemfile changed" if diff[2]
        added = diff[0]
        deleted = diff[1]
      end
      if reason = lockfile_update_reason
        reasons << reason
      end
      return if reasons.empty? && added.empty? && deleted.empty?

      reason = reasons.join(", ")
      lockfile_name = File.basename(lockfile_path)
      message = "#{reason[0].upcase}#{reason[1..].strip}, but "
      message += "the lockfile " unless message.starts_with?("Your lockfile")
      message += "can't be updated because frozen mode is set"
      message += "\n\nYou have added to the Gemfile:\n#{added.join("\n")}" unless added.empty?
      message += "\n\nYou have deleted from the Gemfile:\n#{deleted.join("\n")}" unless deleted.empty?
      message += "\n\nRun `bundle install` elsewhere and add the updated #{lockfile_name} to version control.\n"
      unless explicit_flag || frozen_from_environment?
        message += "\n\nIf this is a development machine, remove the #{lockfile_name} freeze by running `bundle config set frozen false`."
      end
      raise ProductionError.new(message)
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
