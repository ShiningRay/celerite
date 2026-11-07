require "./model"

module Celerite
  module Lockfile
    # Faithful port of `Bundler::LockfileParser` at the pinned reference
    # revisions (see model.cr). Deviations are limited to:
    # - errors raise Celerite::LockfileError instead of Bundler::LockfileError
    # - 2.7.2-only deprecation warnings/rewrites are not performed; parse
    #   results and validity follow the 4.0.24 profile
    class Parser
      BUNDLED      = "BUNDLED WITH"
      DEPENDENCIES = "DEPENDENCIES"
      CHECKSUMS    = "CHECKSUMS"
      PLATFORMS    = "PLATFORMS"
      RUBY         = "RUBY VERSION"
      GIT          = "GIT"
      GEM          = "GEM"
      PATH         = "PATH"
      PLUGIN       = "PLUGIN SOURCE"
      SPECS        = "  specs:"
      SOURCE       = [GIT, GEM, PATH, PLUGIN]

      # Sections introduced per Bundler version (identical in both references).
      SECTIONS_BY_VERSION_INTRODUCED = {
        Gem::Version.new("1.0")   => [DEPENDENCIES, PLATFORMS, GIT, GEM, PATH],
        Gem::Version.new("1.10")  => [BUNDLED],
        Gem::Version.new("1.12")  => [RUBY],
        Gem::Version.new("1.13")  => [PLUGIN],
        Gem::Version.new("2.5.0") => [CHECKSUMS],
      }

      KNOWN_SECTIONS = SECTIONS_BY_VERSION_INTRODUCED.values.flatten.uniq

      MERGE_CONFLICT_PATTERN = Regex.new("<<<<<<<|=======|>>>>>>>|\\|\\|\\|\\|\\|\\|\\|")

      OPTIONS_PATTERN = Regex.new("^  ([a-z]+): (.*)$", Regex::CompileOptions::IGNORE_CASE)

      # Exactly 2, 4, or 6 spaces at the start of the line (a 7th is forbidden),
      # then name, optional " (version[-platform])", optional "!" pinned marker,
      # optional space-separated checksum token.
      NAME_VERSION_PATTERN = Regex.new("^(  |    |      )(?! )(.*?)(?: \\(([^-]*)(?:-(.*))?\\))?(!)?(?: ([^ ]+))?$")

      # Port of Bundler::LockfileParser::Position: cumulative column tracking
      # used in error messages.
      private struct Position
        property line : Int32
        property column : Int32

        def initialize
          @line = 1
          @column = 1
        end

        def advance!(string : String) : Nil
          lines = string.count('\n')
          if lines > 0
            @line += lines
            @column = string.size - string.rindex('\n').not_nil!
          else
            @column += string.size
          end
        end

        def to_s(io : IO) : Nil
          io << line << ':' << column
        end
      end

      private enum Mode
        Source
        Dependency
        Checksum
        Platform
        Ruby
        BundledWith
      end

      getter data : Data

      @mode : Mode?
      @current_type : String?
      @current_options : Array(Option)
      @current_source_section : SourceSection?
      @current_spec : Spec?
      @current_unknown : UnknownSection?

      def self.parse(text : String, lockfile_path : String = "Gemfile.lock") : Data
        new(text, lockfile_path).parse
      end

      def initialize(@text : String, @lockfile_path : String)
        @data = Data.new([] of Section, @lockfile_path, false)
        @mode = nil
        @current_type = nil
        @current_options = [] of Option
        @current_source_section = nil
        @current_spec = nil
        @current_unknown = nil
        @pos = Position.new
      end

      # Ruby's ^ anchors at line starts; Crystal needs the MULTILINE option.
      LINE_HEADING_PATTERN = Regex.new("^\\w[\\w ]*$", Regex::CompileOptions::MULTILINE)

      def self.sections_in_lockfile(text : String) : Array(String)
        text.scan(LINE_HEADING_PATTERN).map(&.[0]).uniq
      end

      def self.unknown_sections_in_lockfile(text : String) : Array(String)
        sections_in_lockfile(text) - KNOWN_SECTIONS
      end

      def self.sections_to_ignore(base_version : Gem::Version? = nil) : Array(String)
        base = base_version ? base_version.release : Gem::Version.new("1.0")
        ignored = [] of String
        SECTIONS_BY_VERSION_INTRODUCED.each do |version, introduced|
          next if version <= base
          ignored.concat(introduced)
        end
        ignored
      end

      def parse : Data
        if @text.matches?(MERGE_CONFLICT_PATTERN)
          raise LockfileError.new(
            "Your #{@lockfile_path} contains merge conflicts.\n" \
            "Run `git checkout HEAD -- #{@lockfile_path}` first to get a clean lock."
          )
        end

        @data = Data.new([] of Section, @lockfile_path, valid_lockfile?)

        # Ruby splits on /((?:\r?\n)+)/ with a block, alternating content lines
        # and separator chunks; both advance the error position.
        @text.each_line(chomp: false) do |raw|
          if raw.matches?(/^\s*$/)
            @pos.advance!(raw)
            next
          end

          line = raw.chomp
          process_line(line)
          @pos.advance!(raw)
        end

        @current_unknown = nil
        @data
      rescue ex : Celerite::VersionError | Celerite::BadRequirementError
        raise LockfileError.new(
          "Your #{@lockfile_path} is unreadable. Run `rm #{@lockfile_path}` " \
          "and then `bundle install` to generate a new lockfile. The error occurred while " \
          "evaluating #{@lockfile_path}:#{@pos}"
        )
      end

      # 4.0.24 validity rule: empty lockfile or at least one known section.
      private def valid_lockfile? : Bool
        return true if @text.strip.empty?

        @text.split(/\r?\n+/).any? { |line| KNOWN_SECTIONS.includes?(line) }
      end

      private def process_line(line : String) : Nil
        case line
        when .in?(SOURCE)
          @mode = Mode::Source
          @current_type = line
          @current_options = [] of Option
          @current_source_section = nil
          @current_spec = nil
          @current_unknown = nil
        when DEPENDENCIES
          @mode = Mode::Dependency
          @current_unknown = nil
        when CHECKSUMS
          @mode = Mode::Checksum
          @current_unknown = nil
        when PLATFORMS
          @mode = Mode::Platform
          @current_unknown = nil
        when RUBY
          @mode = Mode::Ruby
          @current_unknown = nil
        when BUNDLED
          @mode = Mode::BundledWith
          @current_unknown = nil
        else
          if !line.empty? && !line[0].ascii_whitespace?
            # Any other column-0 line: unknown heading, kept verbatim.
            @mode = nil
            @current_spec = nil
            previous = @data.sections.last?
            previous_unknown = previous.is_a?(TypedSection(UnknownSection)) ? previous.inner : nil
            if previous_unknown && previous_unknown.heading == line
              @current_unknown = previous_unknown
            else
              unknown = UnknownSection.new(line)
              @data.sections << TypedSection.new(unknown)
              @current_unknown = unknown
            end
          elsif mode = @mode
            dispatch(mode, line)
          elsif unknown = @current_unknown
            unknown.lines << line
          end
        end
      end

      private def dispatch(mode : Mode, line : String) : Nil
        case mode
        when .source?       then parse_source(line)
        when .dependency?   then parse_dependency(line)
        when .checksum?     then parse_checksum(line)
        when .platform?     then parse_platform(line)
        when .ruby?         then parse_ruby(line)
        when .bundled_with? then parse_bundled_with(line)
        end
      end

      private def parse_source(line : String) : Nil
        case line
        when SPECS
          type = @current_type
          return unless type
          source = SourceSection.new(type, @current_options.dup)
          @data.sections << TypedSection.new(source)
          @current_source_section = source
          @current_spec = nil
        when OPTIONS_PATTERN
          match = OPTIONS_PATTERN.match(line).not_nil!
          value = match[2]
          value = true if value == "true"
          value = false if value == "false"

          @current_options << Option.new(match[1], value)
        else
          parse_spec(line)
        end
      end

      private def parse_spec(line : String) : Nil
        match = NAME_VERSION_PATTERN.match(line)
        return unless match

        spaces = match[1]
        name = match[2]
        version = match[3]?

        if spaces.size == 4
          platform = match[4]?

          parsed_version = Gem::Version.new(version || "")
          spec = Spec.new(name, parsed_version.raw, platform)
          @current_spec = spec
          if source = @current_source_section
            source.specs << spec
          end
        elsif spaces.size == 6
          requirements = version ? version.split(",").map(&.strip) : nil
          if spec = @current_spec
            spec.dependencies << SpecDependency.new(name, requirements)
          end
        end
      end

      private def parse_dependency(line : String) : Nil
        match = NAME_VERSION_PATTERN.match(line)
        return unless match

        spaces = match[1]
        return unless spaces.size == 2
        name = match[2]
        version = match[3]?
        pinned = !match[5]?.nil?

        requirements = version ? version.split(",").map(&.strip) : nil
        add_or_create_dependency(name, requirements, pinned)
      end

      private def add_or_create_dependency(name : String, requirements : Array(String)?, pinned : Bool) : Nil
        @data.sections.each do |section|
          if section.is_a?(TypedSection(DependenciesSection))
            section.inner.dependencies << Dependency.new(name, requirements, pinned)
            return
          end
        end

        # Ruby accumulates into @dependencies even when the heading was never
        # seen; keep the data reachable with an implicit section.
        @data.sections << TypedSection.new(DependenciesSection.new([Dependency.new(name, requirements, pinned)]))
      end

      private def parse_checksum(line : String) : Nil
        match = NAME_VERSION_PATTERN.match(line)
        return unless match

        spaces = match[1]
        return unless spaces.size == 2
        name = match[2]
        version = match[3]?
        platform = match[4]?
        checksums_raw = match[6]?

        checksums = checksums_raw ? checksums_raw.split(",") : [] of String
        parsed_version = Gem::Version.new(version || "")
        entry = ChecksumEntry.new(name, parsed_version.raw, platform, checksums)

        @data.sections.each do |section|
          if section.is_a?(TypedSection(ChecksumsSection))
            section.inner.entries << entry
            return
          end
        end

        @data.sections << TypedSection.new(ChecksumsSection.new([entry]))
      end

      private def parse_platform(line : String) : Nil
        match = line.match(/^  (.*)$/)
        return unless match
        platform = match[1].strip

        section = @data.sections.last?
        if section.is_a?(TypedSection(PlatformsSection))
          section.inner.platforms << platform
        else
          @data.sections << TypedSection.new(PlatformsSection.new([platform]))
        end
      end

      private def parse_ruby(line : String) : Nil
        stripped = line.strip

        section = @data.sections.last?
        @data.sections.pop if section.is_a?(TypedSection(RubySection))
        @data.sections << TypedSection.new(RubySection.new(stripped))
      end

      private def parse_bundled_with(line : String) : Nil
        stripped = line.strip
        return unless Gem::Version.correct?(stripped)

        version = Gem::Version.new(stripped).raw
        section = @data.sections.last?
        @data.sections.pop if section.is_a?(TypedSection(BundledWithSection))
        @data.sections << TypedSection.new(BundledWithSection.new(version))
      end
    end
  end
end
