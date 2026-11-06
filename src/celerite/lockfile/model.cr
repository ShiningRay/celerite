require "../errors"
require "../gem/version"
require "../gem/requirement"
require "../gem/platform"

module Celerite
  module Lockfile
    # Object model of a `Gemfile.lock`-format file (pinned contract:
    # `vendor/reference/{v4.0.24,bundler-v2.7.2}/lockfile_parser.rb` and
    # `lockfile_generator.rb`).
    #
    # Sections keep their file order so read/write round-trips stay faithful;
    # unknown sections are preserved verbatim instead of silently dropped
    # (architecture §2.1 lockfile fidelity rule).

    # A source option line, value is the literal string unless it was the
    # exact text "true"/"false", which parse into booleans like the reference.
    struct Option
      getter key : String
      getter value : String | Bool

      def initialize(@key : String, @value : String | Bool)
      end

      def to_lock_line(io : IO) : Nil
        io << "  " << key << ": " << value
      end
    end

    # A `name (requirements)` line inside a spec (6-space indent).
    struct SpecDependency
      getter name : String
      getter requirements : Array(String)?

      def initialize(@name : String, @requirements : Array(String)?)
      end

      # Gem::Dependency#to_lock (Bundler's rubygems_ext): `op version` strings
      # byte-sorted then reversed; omitted when the requirement is the default.
      # Bundler's LazySpecification#to_lock prefixes 4 more spaces, for the
      # 6-space spec-dependency lines.
      def to_lock_line(io : IO) : Nil
        io << "      " << name << Lockfile.requirement_suffix(requirements)
      end

      def requirement : Gem::Requirement
        Gem::Requirement.new(requirements || [] of String)
      end
    end

    # A locked gem: `    name (version)` or `    name (version-platform)`.
    struct Spec
      getter name : String
      getter version : String
      getter platform : String? # nil means the virtual ruby platform
      getter dependencies : Array(SpecDependency)

      def initialize(@name : String, @version : String, @platform : String?,
                     @dependencies : Array(SpecDependency) = [] of SpecDependency)
      end

      def platform_ruby? : Bool
        platform.nil? || platform == "ruby"
      end

      # Gem::NameTuple#full_name ordering contract.
      def full_name : String
        platform_ruby? ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      end

      def to_lock_line(io : IO) : Nil
        suffix = platform_ruby? ? "" : "-#{platform}"
        io << "    " << name << " (" << version << suffix << ")"
      end
    end

    # A source header plus its locked specs.
    class SourceSection
      getter type : String # GEM / PATH / GIT / PLUGIN SOURCE
      getter options : Array(Option)
      getter specs : Array(Spec)

      def initialize(@type : String, @options : Array(Option) = [] of Option,
                     @specs : Array(Spec) = [] of Spec)
      end

      def option(key : String) : (String | Bool)?
        options.find { |o| o.key == key }.try &.value
      end

      def remote : String?
        option("remote").as?(String)
      end

      def remotes : Array(String)
        options.select { |o| o.key == "remote" }.compact_map(&.value.as?(String))
      end

      def to_lock(io : IO) : Nil
        io << type << "\n"
        options.each do |option|
          option.to_lock_line(io)
          io << "\n"
        end
        io << "  specs:\n"
        specs.each do |spec|
          spec.to_lock_line(io)
          io << "\n"
          spec.dependencies.each do |dep|
            dep.to_lock_line(io)
            io << "\n"
          end
        end
      end
    end

    class PlatformsSection
      getter platforms : Array(String)

      def initialize(@platforms : Array(String) = [] of String)
      end

      def to_lock(io : IO) : Nil
        io << "PLATFORMS\n"
        platforms.each { |p| io << "  " << p << "\n" }
      end
    end

    struct Dependency
      getter name : String
      getter requirements : Array(String)? # nil = no requirement (">= 0")
      getter pinned : Bool                 # trailing "!" marker

      def initialize(@name : String, @requirements : Array(String)?, @pinned : Bool = false)
      end

      # Bundler::Dependency#to_lock = Gem::Dependency#to_lock + "!" when the
      # dependency is pinned to its locked source.
      def to_lock(io : IO) : Nil
        io << "  " << name << Lockfile.requirement_suffix(requirements)
        io << "!" if pinned
        io << "\n"
      end

      def requirement : Gem::Requirement
        Gem::Requirement.new(requirements || [] of String)
      end
    end

    # Shared rendering of a requirement list the way Bundler's
    # `Gem::Dependency#to_lock` does it.
    def self.requirement_suffix(requirements : Array(String)?) : String
      requirement = Gem::Requirement.new(requirements || [] of String)
      return "" if requirement.none?

      " (#{requirement.to_lock_requirements.join(", ")})"
    end

    class DependenciesSection
      getter dependencies : Array(Dependency)

      def initialize(@dependencies : Array(Dependency) = [] of Dependency)
      end

      def to_lock(io : IO) : Nil
        io << "DEPENDENCIES\n"
        dependencies.each(&.to_lock(io))
      end
    end

    struct ChecksumEntry
      getter name : String
      getter version : String
      getter platform : String? # nil means ruby
      getter checksums : Array(String)

      def initialize(@name : String, @version : String, @platform : String?,
                     @checksums : Array(String))
      end

      def to_lock(io : IO) : Nil
        io << "  " << name << " (" << version
        io << "-" << platform unless platform.nil? || platform == "ruby"
        io << ")"
        unless checksums.empty?
          io << " " << checksums.join(",")
        end
        io << "\n"
      end
    end

    class ChecksumsSection
      getter entries : Array(ChecksumEntry)

      def initialize(@entries : Array(ChecksumEntry) = [] of ChecksumEntry)
      end

      def to_lock(io : IO) : Nil
        io << "CHECKSUMS\n"
        entries.each(&.to_lock(io))
      end
    end

    class RubySection
      getter ruby_version : String

      def initialize(@ruby_version : String)
      end

      def to_lock(io : IO) : Nil
        io << "RUBY VERSION\n"
        io << "  " << ruby_version << "\n"
      end
    end

    class BundledWithSection
      getter version : String

      def initialize(@version : String)
      end

      def to_lock(io : IO) : Nil
        io << "BUNDLED WITH\n"
        io << "  " << version << "\n"
      end
    end

    # Any heading not in the known set; content lines preserved verbatim.
    class UnknownSection
      getter heading : String
      getter lines : Array(String)

      def initialize(@heading : String, @lines : Array(String) = [] of String)
      end

      def to_lock(io : IO) : Nil
        io << heading << "\n"
        lines.each do |line|
          io << line << "\n"
        end
      end
    end

    abstract class Section
      abstract def to_lock(io : IO) : Nil
    end

    class TypedSection(Inner) < Section
      getter inner : Inner

      def initialize(@inner : Inner)
      end

      def to_lock(io : IO) : Nil
        inner.to_lock(io)
      end
    end

    # Complete parsed lockfile.
    class Data
      getter sections : Array(Section)
      getter lockfile_path : String

      def initialize(@sections : Array(Section), @lockfile_path : String, @valid : Bool)
      end

      def valid? : Bool
        @valid
      end

      def sources : Array(SourceSection)
        sections.flat_map do |section|
          section.is_a?(TypedSection(SourceSection)) ? [section.inner] : [] of SourceSection
        end
      end

      def platforms_section : PlatformsSection?
        sections.each do |section|
          return section.inner if section.is_a?(TypedSection(PlatformsSection))
        end
        nil
      end

      def platforms : Array(String)
        platforms_section.try(&.platforms) || [] of String
      end

      def dependencies_section : DependenciesSection?
        sections.each do |section|
          return section.inner if section.is_a?(TypedSection(DependenciesSection))
        end
        nil
      end

      def dependencies : Array(Dependency)
        dependencies_section.try(&.dependencies) || [] of Dependency
      end

      def checksums_section : ChecksumsSection?
        sections.each do |section|
          return section.inner if section.is_a?(TypedSection(ChecksumsSection))
        end
        nil
      end

      def checksums : Array(ChecksumEntry)
        checksums_section.try(&.entries) || [] of ChecksumEntry
      end

      def ruby_version : String?
        sections.each do |section|
          return section.inner.ruby_version if section.is_a?(TypedSection(RubySection))
        end
        nil
      end

      def bundler_version : String?
        sections.each do |section|
          return section.inner.version if section.is_a?(TypedSection(BundledWithSection))
        end
        nil
      end

      def unknown_sections : Array(String)
        sections.flat_map do |section|
          section.is_a?(TypedSection(UnknownSection)) ? [section.inner.heading] : [] of String
        end
      end

      def specs : Array(Spec)
        sources.flat_map(&.specs)
      end

      def find_spec(name : String) : Spec?
        specs.find(&.name.==(name))
      end

      def to_lock(io : IO) : Nil
        sections.each_with_index do |section, index|
          io << "\n" unless index.zero?
          section.to_lock(io)
        end
      end

      def to_lock : String
        String.build { |io| to_lock(io) }
      end
    end
  end
end
