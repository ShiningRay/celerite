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
      getter required_rubygems_version : Gem::Requirement
      getter checksum : String?

      def initialize(@name : String, @version : Gem::Version, @platform : Gem::Platform,
                     @dependencies : Array(DepSpec), @required_ruby_version : Gem::Requirement,
                     @required_rubygems_version : Gem::Requirement = Gem::Requirement.new,
                     @checksum : String? = nil)
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
                     @unlock : Bool | Array(String) = false,
                     @spec_fetcher : (String -> Array(IndexSpec))? = nil,
                     @resolution_platforms : Array(Gem::Platform)? = nil,
                     @bridge_ruby_version : String = "4.0.6",
                     @bridge_rubygems_version : String = "4.0.16",
                     @bridge_ruby_engine : String = "ruby",
                     @bridge_ruby_engine_version : String = "4.0.6",
                     @bridge_ruby_patchlevel : String? = nil)
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
          platforms = top_level ? resolution_platforms : [@local_platform]
          pkg = Package.new(dependency.name, platforms, locked_version, @unlock, dependency, prerelease_specified)
          @packages[dependency.name] = pkg
        end
        pkg
      end

      # All platforms the resolution covers: local + lockfile + added.
      def resolution_platforms : Array(Gem::Platform)
        @resolution_platforms || [@local_platform]
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
        requirement = package.dependency.try(&.requirement)
        label = requirement.nil? || requirement.none? ? name : "#{name} (#{requirement})"

        # Reference message selection (pinned Resolver#raise_not_found!):
        # specs matching the requirement exist but not installable on every
        # resolution platform -> "gems matching ... valid for all resolution
        # platforms (plist)"; single-platform match -> "gem 'label' with
        # platform 'plat'"; otherwise the plain not-found line.
        specs = all_specs(name)
        matching = specs.select do |spec|
          requirement.nil? || requirement.none? || requirement.satisfied_by?(spec.version)
        end
        # Pinned `Resolver#raise_not_found!`: list requirement-matching
        # variants when any exist; otherwise list all variants for the gem
        # name. The listing heading uses the name in the latter case.
        listing_specs = matching.empty? ? specs : matching
        listing_label = matching.empty? ? name : label
        listing = String.build do |b|
          unless listing_specs.empty?
            b << "

"
            b << "The source contains the following gems matching '#{listing_label}':
"
            listing_specs.each { |spec| b << "  * #{spec.full_name}
" }
          end
        end
        platforms = package.platforms
        if matching.any?
          if platforms.size > 1
            raise GemNotFoundError.new(
              "Could not find gems matching '#{label}' valid for all resolution platforms (#{platforms.join(", ")}) in #{source_description(package)}." + listing
            )
          end
          raise GemNotFoundError.new(
            "Could not find gem '#{label}' with platform '#{platforms.first}' in #{source_description(package)}." + listing
          )
        end

        raise GemNotFoundError.new(
          "Could not find gem '#{label}' in #{source_description(package)}." + listing
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
          index = @index[name]?
          if index.nil? && (fetcher = @spec_fetcher)
            index = fetcher.call(name)
            @index[name] = index
          end
          index ||= [] of IndexSpec
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
          # Reference parity: one group per resolution platform; a top-level
          # gem must have a variant on EVERY platform, otherwise the version
          # is not a candidate at all.
          per_platform = package.platforms.map do |platform|
            group_specs.select { |spec| installable?(spec, platform) }
          end
          platform_specs = per_platform.flatten.uniq

          next if package.top_level? && per_platform.any?(&.empty?)

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

      # Reference `MatchPlatform.select_best_platform_match` +
      # `Materialization#specs` (bundler resolver.rb:88, materialization.rb:21-29,
      # match_platform.rb:5-10, platform.rb:326-348): a spec is installable when
      # its platform is ruby or exactly the target platform; among installable
      # same-version specs the exact local-platform match wins (specificity
      # -1) over ruby (1_000_000).
      def self.select_variant(specs : Hash(String, Array(IndexSpec))?, name : String, version : Gem::Version) : IndexSpec?
        return nil unless specs
        same = specs[name]?.try(&.select { |s| s.version == version })
        return nil if same.nil? || same.empty?

        same.select { |s| s.platform_ruby? || s.platform == Gem::Platform.local }
          .min_by? { |s| Gem::Platform.platform_specificity_match(s.platform, Gem::Platform.local) }
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
        return false unless spec.required_ruby_version.satisfied_by?(Gem::Version.new(running_ruby_version))
        return false unless spec.required_rubygems_version.satisfied_by?(Gem::Version.new(running_rubygems_version))
        true
      end

      # Reference parity: Bundler matches gem metadata with Gem.ruby_version,
      # which is RUBY_VERSION without a patchlevel suffix. Patchlevel only
      # participates in Gemfile target validation (Celerite::RubyRuntime).
      private def running_ruby_version_for_gem : String
        running_ruby_version
      end

      private def running_ruby_version : String
        @bridge_ruby_version
      end

      private def running_rubygems_version : String
        @bridge_rubygems_version
      end

      def system_ruby_version : Celerite::RubyVersion
        Celerite::RubyVersion.system(
          @bridge_ruby_engine,
          @bridge_ruby_version,
          @bridge_ruby_engine_version,
          @bridge_ruby_patchlevel,
        )
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

      # Bundler models Ruby/RubyGems as metadata packages in PubGrub, so a
      # version that only fails `required_ruby_version`/`required_rubygems_version`
      # is a solve failure (status 6), not a missing gem (status 7). Mirror that
      # distinction for root requirements: if requirement-matching specs exist
      # but every installable candidate is excluded by gem metadata, report a
      # SolveFailure with the reference explanation shape.
      private def raise_metadata_or_not_found!(package : Package, requirement : Gem::Requirement) : NoReturn
        platform_specs = all_specs(package.name).select do |spec|
          requirement.none? || requirement.satisfied_by?(spec.version)
        end.select do |spec|
          package.platforms.all? { |platform| installable?(spec, platform) }
        end

        excluded = platform_specs.reject { |spec| ruby_requirement_satisfied?(spec) }
        if excluded.empty?
          raise_not_found!(package)
        end

        spec = excluded.first
        root_requirement = requirement.none? ? ">= 0" : requirement.to_s
        if !spec.required_ruby_version.satisfied_by?(Gem::Version.new(running_ruby_version))
          label = "Ruby"
          required = spec.required_ruby_version.to_s
          actual = running_ruby_version
        else
          label = "RubyGems"
          required = spec.required_rubygems_version.to_s
          actual = running_rubygems_version
        end

        message = String.build do |io|
          io << "Could not find compatible versions\n\n"
          io << "Because every version of #{package.name} depends on #{label} #{required}\n"
          io << "  and Gemfile depends on #{package.name} #{root_requirement},\n"
          io << "  #{label} #{required} is required.\n"
          io << "So, because current #{label} version is = #{actual},\n"
          io << "  version solving has failed."
        end

        term = Term.new(Constraint.new(package, requirement_to_range(requirement)), true)
        cause = IncompatibilityCause::NoVersions.new(term)
        incompatibility = Incompatibility.new([term], cause, message)
        raise SolveFailure.new(incompatibility)
      end

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
            raise_metadata_or_not_found!(package, dep.requirement)
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
            Package.new(dep.name, resolution_platforms, locked_version, @unlock, dep, prerelease_specified).tap do |pkg|
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
