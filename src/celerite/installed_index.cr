require "./glob"

module Celerite
  # Disk-only index of the gems RubyGems has installed for this interpreter.
  #
  # Read-only commands (`check`/`show`/`info`/`list`, plus `doctor`) need only
  # four things about an installed gem: its name, version, platform and the
  # directory it lives in. A RubyGems installation already stores all four in
  # the *file name* of its specification file:
  #
  #   <root>/specifications/<name>-<version>[-<platform>].gemspec
  #   <root>/specifications/default/<name>-<version>[-<platform>].gemspec
  #
  # so the whole list can be read without a Ruby interpreter. That is the data
  # the bridge's `installed_specs` / `default_gem_spec` ops report (see
  # `assets/bridge/server.rb:718-785`); the index answers the same questions
  # from the filesystem and the bridge stays the fallback for roots it cannot
  # read (see the call sites in `cli/commands_surface.cr` and
  # `cli/commands.cr`).
  #
  # Failure posture: every path read is defensive. An unreadable directory, a
  # file name that does not parse or a directory that vanished mid-scan is
  # skipped, and `empty?` tells the caller the index has nothing to say, so the
  # caller falls back to the bridge instead of concluding "not installed".
  struct InstalledIndex
    # The suffix every RubyGems specification file ends with.
    SPECIFICATION_SUFFIX = ".gemspec"

    # One installed specification file.
    struct Entry
      # `Gem::Specification#name`.
      getter name : String
      # `Gem::Specification#version#to_s`.
      getter version : String
      # `Gem::Specification#platform#to_s`, except that the plain-Ruby platform
      # is `nil` here (Ruby spells it `"ruby"`; the callers compare against
      # both, see `same_platform?`).
      getter platform : String?
      # `Gem::Specification#full_name`.
      getter full_name : String
      # The specification file this entry came from.
      getter spec_path : String
      # `Gem::Specification#full_gem_path`: `<root>/gems/<full_name>`.
      getter gem_dir : String
      # True when the specification lives under `specifications/default/`, i.e.
      # the gem ships with the interpreter (`Gem::Specification#default_gem?`).
      getter default_gem : Bool

      def initialize(@name : String, @version : String, @platform : String?,
                     @full_name : String, @spec_path : String, @gem_dir : String,
                     @default_gem : Bool)
      end

      # RubyGems reports `Gem::Platform::RUBY` as `"ruby"`; a lockfile row may
      # carry either that string or nothing at all.
      def self.same_platform?(entry_platform : String?, spec_platform : String?) : Bool
        return true if spec_platform.nil?
        (entry_platform || "ruby") == spec_platform
      end
    end

    # Splits `<name>-<version>[-<platform>]` the way RubyGems does: the version
    # starts at the first dash-separated component that begins with a digit, and
    # everything after the version is the platform (platforms contain dashes of
    # their own, e.g. `x86_64-linux-gnu`).
    def self.parse_full_name(full_name : String) : {String, String, String?}?
      parts = full_name.split('-')
      return nil if parts.size < 2
      start = parts.index { |part| !part.empty? && part[0].ascii_number? }
      return nil if start.nil? || start == 0 || start >= parts.size
      name = parts[0...start].join('-')
      version = parts[start]
      platform = parts[(start + 1)..].join('-')
      return nil if name.empty? || version.empty?
      {name, version, platform.empty? ? nil : platform}
    end

    getter entries : Array(Entry)

    def initialize(@entries : Array(Entry) = [] of Entry)
    end

    # Reads every specification file below `roots` (`Gem.dir`, `GEM_PATH`
    # entries, the interpreter's default gem dir, ...). Roots are de-duplicated
    # by normalized path; a root that appears twice is read once.
    def self.load(roots : Enumerable(String)) : InstalledIndex
      entries = [] of Entry
      seen = Set(String).new
      roots.each do |root|
        next if root.empty?
        normalized = root.gsub('\\', "/").chomp("/")
        next if normalized.empty?
        next unless seen.add?(normalized)
        specs_dir = File.join(normalized, "specifications")
        load_dir(specs_dir, File.join(normalized, "gems"), false, entries)
        load_dir(File.join(specs_dir, "default"), File.join(normalized, "gems"), true, entries)
      end
      InstalledIndex.new(entries)
    end

    private def self.load_dir(dir : String, gems_dir : String, default_gem : Bool,
                              entries : Array(Entry)) : Nil
      Glob.paths(dir, "*#{SPECIFICATION_SUFFIX}").each do |spec_path|
        full_name = File.basename(spec_path)
        full_name = full_name[0...-SPECIFICATION_SUFFIX.size]
        next if full_name.empty?
        parsed = parse_full_name(full_name)
        next unless parsed
        name, version, platform = parsed
        entries << Entry.new(name, version, platform, full_name, spec_path,
          File.join(gems_dir, full_name), default_gem)
      end
    rescue
      # Unreadable directory or vanished entry: contribute nothing rather than
      # turning a filesystem failure into "this gem is not installed".
      nil
    end

    def empty? : Bool
      @entries.empty?
    end

    def size : Int32
      @entries.size
    end

    # The entry for an exact `full_name`, if any.
    def find_full_name(full_name : String) : Entry?
      @entries.find { |entry| entry.full_name == full_name }
    end

    # The installed entry for `name` (optionally constrained to `version`).
    # The plain-Ruby platform wins over a platform-specific build, matching
    # `Gem::Specification.find_by_name`'s preference for the pure-Ruby variant.
    def find(name : String, version : String? = nil) : Entry?
      candidates = @entries.select { |entry| entry.name == name }
      candidates = candidates.select { |entry| entry.version == version } if version
      return nil if candidates.empty?
      candidates.find { |entry| entry.platform.nil? } || candidates.first
    end

    # The interpreter's default gem for `name`, mirroring
    # `Gem::Specification.find_all_by_name(name).select(&:default_gem?).max_by(&:version)`
    # (`assets/bridge/server.rb:764`).
    def default_gem(name : String) : Entry?
      candidates = @entries.select do |entry|
        entry.default_gem && entry.name == name && Gem::Version.correct?(entry.version)
      end
      return nil if candidates.empty?
      best = candidates.first
      best_version = Gem::Version.new(best.version)
      candidates.each do |candidate|
        version = Gem::Version.new(candidate.version)
        if version > best_version
          best = candidate
          best_version = version
        end
      end
      best
    end
  end
end
