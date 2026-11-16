require "./errors"
require "./config"
require "./lockfile/parser"

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
    # This port implements the CHECKSUMS reasons (missing / empty entry), the
    # ones a deployment install of a source without checksums hits first; the
    # Gemfile-diff reasons are still listed as an open gap in
    # docs/compat-report.md.
    def validate_frozen_lockfile!(explicit_flag : Bool = false) : Nil
      return unless config.frozen?
      raise ProductionError.new("Frozen mode is set, but there's no lockfile") unless lockfile_exists?

      reason = lockfile_update_reason
      return unless reason

      lockfile_name = File.basename(lockfile_path)
      message = "#{reason[0].upcase}#{reason[1..].strip}, but can't be updated because frozen mode is set"
      message += "\n\nRun `bundle install` elsewhere and add the updated #{lockfile_name} to version control.\n"
      unless explicit_flag || frozen_from_environment?
        message += "\n\nIf this is a development machine, remove the #{lockfile_name} freeze by running `bundle config set frozen false`."
      end
      raise ProductionError.new(message)
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
