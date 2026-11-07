require "../gem/version"
require "../gem/requirement"
require "../gem/platform"

module Celerite
  module Resolver
    # Dependency as seen by the resolver: name plus requirement strings.
    struct DepSpec
      getter name : String
      getter requirement : Gem::Requirement

      def initialize(@name : String, requirement : Array(String) | Gem::Requirement)
        @requirement = requirement.is_a?(Gem::Requirement) ? requirement : Gem::Requirement.new(requirement)
      end

      def to_s(io : IO) : Nil
        io << name << " (" << requirement << ")"
      end
    end

    # Represents a gem being resolved (pinned contract:
    # `Bundler::Resolver::Package`).
    class Package
      getter name : String
      getter platforms : Array(Gem::Platform)
      getter dependency : DepSpec?
      getter locked_version : Gem::Version?

      enum PrereleaseMode
        Ignore        # prereleases filtered from candidates
        ConsiderFirst # requirement or lockfile mentioned a prerelease
        ConsiderLast  # a relaxation retry enabled prereleases
      end

      @prerelease : PrereleaseMode = PrereleaseMode::Ignore

      def initialize(name : String, @platforms : Array(Gem::Platform), locked_version : Gem::Version?,
                     @unlock : Bool | Array(String) = false,
                     dependency : DepSpec? = nil,
                     prerelease_specified : Bool = false,
                     @prefer_local : Bool = false,
                     @top_level : Bool = true)
        @name = name
        @locked_version = locked_version
        @dependency = dependency || DepSpec.new(name, Gem::Requirement.new)
        @top_level = !dependency.nil?
        @prerelease = (prerelease_specified || locked_version.try(&.prerelease?)) ? PrereleaseMode::ConsiderFirst : PrereleaseMode::Ignore
      end

      def platform_specs(specs : Array(Candidate)) : Array(Candidate)
        specs.select do |candidate|
          platforms.any? { |platform| candidate.installable_on?(platform) }
        end
      end

      def to_s(io : IO) : Nil
        io << name
      end

      def root? : Bool
        false
      end

      def top_level? : Bool
        @top_level
      end

      def meta? : Bool
        false
      end

      def ==(other : Package) : Bool
        self.class == other.class && name == other.name
      end

      def hash : UInt64
        name.hash
      end

      def unlock? : Bool
        @unlock == true || (@unlock.is_a?(Array(String)) && @unlock.as(Array(String)).includes?(name))
      end

      def ignores_prereleases? : Bool
        @prerelease == PrereleaseMode::Ignore
      end

      def prerelease_specified? : Bool
        @prerelease == PrereleaseMode::ConsiderFirst
      end

      def consider_prereleases! : Nil
        @prerelease = PrereleaseMode::ConsiderLast
      end

      def prefer_local? : Bool
        @prefer_local
      end

      def consider_remote_versions! : Nil
        @prefer_local = false
      end
    end

    # The Gemfile itself, seen as the root package.
    class RootPackage < Package
      def initialize(name : String)
        @name = name
        @platforms = [] of Gem::Platform
        @locked_version = nil
        @unlock = false
        @dependency = nil
        @top_level = true
        @prerelease = PrereleaseMode::ConsiderFirst
        @prefer_local = false
      end

      def root? : Bool
        true
      end

      def meta? : Bool
        true
      end
    end
  end
end
