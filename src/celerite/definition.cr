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
  end
end
