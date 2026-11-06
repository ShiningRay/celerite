require "./ranges"
require "./package"
require "./solver"
require "../gem/platform"

module Celerite
  module Resolver
    # A candidate gem spec from an index or the lockfile.
    struct IndexSpec
      getter name : String
      getter version : Gem::Version
      getter platform : Gem::Platform
      getter dependencies : Array(DepSpec)
      getter required_ruby_version : Gem::Requirement
      getter checksum : String?

      def initialize(@name : String, @version : Gem::Version, @platform : Gem::Platform,
                     @dependencies : Array(DepSpec), @required_ruby_version : Gem::Requirement,
                     @checksum : String?)
      end

      def platform_ruby? : Bool
        platform.ruby?
      end

      def full_name : String
        platform_ruby? ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      end
    end

    # One resolvable candidate: version + priority + merged dependencies.
    class Candidate
      getter version : CandidateVersion
      getter dependencies : Array(DepSpec)
      getter platform : Gem::Platform
      getter priority : Int32

      def initialize(@version : CandidateVersion, @dependencies : Array(DepSpec),
                     @platform : Gem::Platform, @priority : Int32)
      end

      def ==(other : Candidate) : Bool
        version == other.version && priority == other.priority
      end

      def hash : UInt64
        {version, priority}.hash
      end
    end

    abstract class VersionSource
      abstract def versions_for(package : Package, range : VersionRange) : Array(CandidateVersion)
      abstract def sort_versions_by_preferred(package : Package, versions : Array(CandidateVersion)) : Array(CandidateVersion)
      abstract def incompatibilities_for(package : Package, version : CandidateVersion) : Array(Incompatibility)
      abstract def no_versions_incompatibility_for(package : Package, term : Term) : Incompatibility
    end

    # Port of `Bundler::Resolver` (the PubGrub source adapter) over a compact
    # index plus locked stubs.
    class ResolutionSource < VersionSource
      getter root : RootPackage
      getter packages : Hash(String, Package)

      def initialize(@root_name : String, @remote_description : String,
                     @index : Hash(String, Array(IndexSpec)),
                     @locked_specs : Hash(String, Array(IndexSpec)),
                     @base_requirements : Hash(String, Gem::Requirement),
                     @local_platform : Gem::Platform,
                     @unlock : Bool | Array(String) = false)
        @root = RootPackage.new(@root_name)
        @packages = {} of String => Package
        @all_versions = {} of Package => Array(Candidate)
        @sorted_versions = {} of Package => Array(CandidateVersion)
        @cached_dependencies = Hash(Package, Hash(CandidateVersion, Hash(Package, Constraint))).new
        @all_specs = {} of String => Array(IndexSpec)

        @sorted_versions[@root] = [CandidateVersion.new(Gem::Version.new("0"), 0)]
      end

      def package_for(dependency : DepSpec, top_level : Bool = false) : Package
        pkg = @packages[dependency.name]?
        unless pkg
          prerelease_specified = dependency.requirement.prerelease?
          locked_version = @locked_specs[dependency.name]?.try(&.first?).try(&.version)
          pkg = Package.new(dependency.name, [@local_platform], locked_version, @unlock, dependency, prerelease_specified)
          @packages[dependency.name] = pkg
        end
        pkg
      end

      def root_dependencies(requirements : Array(DepSpec)) : Hash(Package, Constraint)
        prepared = prepare_dependencies(requirements)
        # The root candidate's dependencies drive the whole solve
        # (pinned: `@cached_dependencies[root] = {root_version => ...}`).
        @cached_dependencies[@root] ||= begin
          table = Hash(CandidateVersion, Hash(Package, Constraint)).new
          table[CandidateVersion.new(Gem::Version.new("0"), 0)] = prepared
          table
        end
        prepared
      end

      # Port of `Resolver#raise_not_found!` for root dependencies with no
      # matching versions (simplified: no platform/cooldown hints yet).
      def raise_not_found!(package : Package) : NoReturn
        name = package.name
        label = begin
          requirement = package.dependency.try(&.requirement)
          if requirement.nil? || requirement.none?
            name
          else
            "#{name} (#{requirement})"
          end
        end
        raise GemNotFoundError.new(
          "Could not find gem '#{label}' in #{source_description(package)}."
        )
      end

      def source_description(package : Package) : String
        @remote_description
      end

      # ------------------------------------------------------------------
      # Candidate access
      # ------------------------------------------------------------------

      def all_specs(name : String) : Array(IndexSpec)
        @all_specs[name] ||= begin
          locked = @locked_specs[name]? || [] of IndexSpec
          index = @index[name]? || [] of IndexSpec
          (locked + index).uniq do |spec|
            {spec.version, spec.platform}
          end
        end
      end

      def all_versions_for(package : Package) : Array(Candidate)
        name = package.name
        specs = all_specs(name)

        specs = filter_prereleases(specs, package)

        results = [] of IndexSpec
        locked_requirement = @base_requirements[name]?
        specs.each do |spec|
          if ruby_requirement_satisfied?(spec)
            results << spec
          end
        end
        results = filter_matching(results, locked_requirement) if locked_requirement

        groups = [] of Candidate
        results.group_by(&.version).each do |version, group_specs|
          platform_specs = group_specs.select do |spec|
            package.platforms.any? { |platform| installable?(spec, platform) }
          end

          next if package.top_level? && platform_specs.empty?

          ruby_specs = group_specs.select(&.platform_ruby?)
          if ruby_specs.empty?
            # pure platform variant without a ruby variant: ruby candidate
            # still exists as the locked/ruby group only when present
          end

          unless ruby_specs.empty?
            ruby_deps = merged_dependencies(ruby_specs)
            groups << Candidate.new(CandidateVersion.new(version, -1), ruby_deps, Gem::Platform::RUBY, -1)
          end

          platform_only = platform_specs.reject(&.platform_ruby?)
          unless platform_only.empty?
            platform_deps = merged_dependencies(platform_only)
            unless platform_deps == merged_dependencies(ruby_specs) && !ruby_specs.empty?
              groups << Candidate.new(CandidateVersion.new(version, 1), platform_deps, platform_only.first.platform, 1)
            end
          end

          if platform_only.empty? && ruby_specs.empty?
            groups << Candidate.new(CandidateVersion.new(version, -1), merged_dependencies(group_specs), Gem::Platform::RUBY, -1)
          end
        end
        groups
      end

      private def merged_dependencies(specs : Array(IndexSpec)) : Array(DepSpec)
        deps = Hash(String, Gem::Requirement).new
        order = [] of String
        specs.each do |spec|
          spec.dependencies.each do |dep|
            if existing = deps[dep.name]?
              deps[dep.name] = Gem::Requirement.intersect(existing, dep.requirement)
            else
              deps[dep.name] = dep.requirement
              order << dep.name
            end
          end
        end
        order.map { |n| DepSpec.new(n, deps[n]) }
      end

      private def filter_prereleases(specs : Array(IndexSpec), package : Package) : Array(IndexSpec)
        return specs unless package.ignores_prereleases? && specs.size > 1
        specs.reject(&.version.prerelease?)
      end

      private def filter_matching(specs : Array(IndexSpec), requirement : Gem::Requirement) : Array(IndexSpec)
        specs.select { |spec| requirement.satisfied_by?(spec.version) }
      end

      private def ruby_requirement_satisfied?(spec : IndexSpec) : Bool
        true
      end

      private def installable?(spec : IndexSpec, platform : Gem::Platform) : Bool
        return true if spec.platform_ruby?
        spec.platform.match?(platform)
      end

      def package_consider_prereleases(name : String) : Nil
        if pkg = @packages[name]?
          pkg.consider_prereleases!
        end
      end

      def sorted_versions(package : Package) : Array(CandidateVersion)
        @sorted_versions[package] ||= filtered_versions_for(package).sort
      end

      def versions_for(package : Package, range : VersionRange) : Array(CandidateVersion)
        range.select_versions(sorted_versions(package))
      end

      def sort_versions_by_preferred(package : Package, versions : Array(CandidateVersion)) : Array(CandidateVersion)
        locked_version = package.locked_version

        result = versions.sort do |a, b|
          unless package.prerelease_specified?
            if a.prerelease? && !b.prerelease?
              next 1
            elsif b.prerelease? && !a.prerelease?
              next -1
            end
          end
          b <=> a
        end

        return result if package.unlock? || locked_version.nil?

        move = result.select { |candidate| candidate.version == locked_version }
        keep = result.reject { |candidate| candidate.version == locked_version }
        move + keep
      end

      private def filtered_versions_for(package : Package) : Array(CandidateVersion)
        all_versions_for(package).map(&.version)
      end

      # ------------------------------------------------------------------
      # Dependency incompatibilities
      # ------------------------------------------------------------------

      def cached_dependencies(package : Package) : Hash(CandidateVersion, Hash(Package, Constraint))
        @cached_dependencies[package] ||= begin
          table = Hash(CandidateVersion, Hash(Package, Constraint)).new
          all_versions_for(package).each do |candidate|
            deps = candidate.dependencies.reject { |d| d.name == package.name }
            table[candidate.version] = to_dependency_hash(deps)
          end
          table
        end
      end

      def incompatibilities_for(package : Package, version : CandidateVersion) : Array(Incompatibility)
        package_deps = cached_dependencies(package)
        sorted = sorted_versions(package)

        version_deps = package_deps[version]?
        return [] of Incompatibility if version_deps.nil?

        version_deps.map do |dep_package, dep_constraint|
          low = sorted.index(version) || 0
          high = low

          while low > 0
            prev_deps = package_deps[sorted[low - 1]]?
            break unless prev_deps && prev_deps[dep_package]? == dep_constraint
            low -= 1
          end
          low_bound = low == 0 ? nil : sorted[low]

          while high < sorted.size
            next_deps = package_deps[sorted[high]]?
            break unless next_deps && next_deps[dep_package]? == dep_constraint
            high += 1
          end
          high_bound = high == sorted.size ? nil : sorted[high]

          range = VersionRange.new(min: low_bound, max: high_bound, include_min: !low_bound.nil?)
          self_constraint = Constraint.new(package, range)
          dep_term = Term.new(dep_constraint, false)
          self_term = Term.new(self_constraint, true)

          Incompatibility.new([self_term, dep_term], IncompatibilityCause::Dependency.new)
        end
      end

      def no_versions_incompatibility_for(package : Package, term : Term) : Incompatibility
        cause = IncompatibilityCause::NoVersions.new(term)
        constraint_string = term.constraint.constraint_string
        custom = "#{constraint_string} could not be found in #{source_description(package)}"

        Incompatibility.new([term], cause, custom)
      end

      # ------------------------------------------------------------------
      # Root dependency preparation
      # ------------------------------------------------------------------

      private def prepare_dependencies(requirements : Array(DepSpec)) : Hash(Package, Constraint)
        result = Hash(Package, Constraint).new
        requirements.each do |dep|
          package = package_for(dep, top_level: true)
          constraint = parse_dependency(package, dep.requirement)

          range = constraint.range
          versions = versions_for(package, range)
          if versions.empty? && package.ignores_prereleases?
            package.consider_prereleases!
            versions = versions_for(package, range)
          end

          if versions.empty?
            raise_not_found!(package)
          end

          existing = result[package]?
          result[package] = existing ? existing.intersect(constraint) : constraint
        end
        result
      end

      def parse_dependency(package : Package, requirement : Gem::Requirement) : Constraint
        Constraint.new(package, requirement_to_range(requirement))
      end

      # Port of `Bundler::Resolver#requirement_to_range` (platform priority
      # bounds).
      def requirement_to_range(requirement : Gem::Requirement) : VersionRange
        ranges = requirement.constraints.map do |constraint|
          op = constraint.op
          version = constraint.version

          ver = CandidateVersion.new(version, -1)
          platform_ver = CandidateVersion.new(version, 1)

          case op
          when "~>"
            bump = CandidateVersion.new(Gem::Version.new(version.bump.to_s + ".A"), -1)
            VersionRange.new(name: "~> #{ver}", min: ver, max: bump, include_min: true)
          when ">"
            VersionRange.new(min: platform_ver)
          when ">="
            VersionRange.new(min: ver, include_min: true)
          when "<"
            VersionRange.new(max: ver)
          when "<="
            VersionRange.new(max: platform_ver, include_max: true)
          when "="
            VersionRange.new(min: ver, max: platform_ver, include_min: true, include_max: true)
          when "!="
            VersionRange.new(min: ver, max: platform_ver, include_min: true, include_max: true).invert
          else
            raise Error.new("bad version specifier: #{op}")
          end
        end

        return VersionRange.any if ranges.empty?
        ranges.reduce { |a, b| a.intersect(b) }
      end

      private def to_dependency_hash(deps : Array(DepSpec)) : Hash(Package, Constraint)
        result = Hash(Package, Constraint).new
        deps.each do |dep|
          package = @packages[dep.name]?
          package ||= begin
            prerelease_specified = dep.requirement.prerelease?
            locked_version = @locked_specs[dep.name]?.try(&.first?).try(&.version)
            Package.new(dep.name, [@local_platform], locked_version, @unlock, dep, prerelease_specified).tap do |pkg|
              @packages[dep.name] = pkg
            end
          end

          constraint = parse_dependency(package, dep.requirement)
          existing = result[package]?
          result[package] = existing ? existing.intersect(constraint) : constraint
        end
        result
      end
    end

    # Orchestrates one resolution pass (pinned contract: `Resolver#start`).
    class Orchestrator
      getter source : ResolutionSource
      getter root_dependencies : Hash(Package, Constraint)

      def initialize(@source : ResolutionSource, requirements : Array(DepSpec))
        @root_dependencies = source.root_dependencies(requirements)
      end

      def solve : Hash(Package, CandidateVersion)
        strategy = Strategy.new(@source)
        solver = VersionSolver.new(@source, @source.root, strategy)
        solver.solve
      end
    end
  end
end
