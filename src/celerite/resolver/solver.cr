require "./ranges"
require "./package"

module Celerite
  module Resolver
    # PubGrub Term: a positive or negative constraint over one package (pinned
    # contract: `Bundler::PubGrub::Term`).
    class Term
      getter constraint : Constraint
      getter package : Package

      def initialize(@constraint : Constraint, @positive : Bool)
        @package = constraint.package
      end

      def initialize(range : VersionRange, @positive : Bool, package : Package)
        @constraint = Constraint.new(package, range)
        @package = package
      end

      def positive? : Bool
        @positive
      end

      def negative? : Bool
        !@positive
      end

      def invert : Term
        Term.new(constraint, !@positive)
      end

      def intersect(other : Term) : Term
        raise ArgumentError.new("packages must match") if package != other.package

        if positive? && other.positive?
          Term.new(constraint.intersect(other.constraint), true)
        elsif negative? && other.negative?
          Term.new(constraint.union(other.constraint), false)
        else
          positive_term = positive? ? self : other
          negative_term = negative? ? self : other
          Term.new(positive_term.constraint.intersect(negative_term.constraint.invert), true)
        end
      end

      def difference(other : Term) : Term
        intersect(other.invert)
      end

      def relation(other : Term) : Symbol
        if positive? && other.positive?
          constraint.relation(other.constraint)
        elsif negative? && other.positive?
          constraint.allows_all?(other.constraint) ? :disjoint : :overlap
        elsif positive? && other.negative?
          if !other.constraint.allows_any?(constraint)
            :subset
          elsif other.constraint.allows_all?(constraint)
            :disjoint
          else
            :overlap
          end
        else
          constraint.allows_all?(other.constraint) ? :subset : :overlap
        end
      end

      def satisfies?(other : Term) : Bool
        raise ArgumentError.new("packages must match") unless package == other.package
        relation(other) == :subset
      end

      def empty? : Bool
        normalized_range.empty?
      end

      def normalized_range : VersionRange
        positive? ? constraint.range : constraint.range.invert
      end

      def ==(other : Term) : Bool
        positive? == other.positive? && constraint == other.constraint
      end

      def hash : UInt64
        {constraint, positive?}.hash
      end

      def to_s(io : IO) : Nil
        if positive?
          io << constraint.constraint_string
        else
          io << "not " << constraint.constraint_string
        end
      end
    end

    # Cause of an incompatibility (pinned contract:
    # `Bundler::PubGrub::Incompatibility`).
    abstract class IncompatibilityCause
      # root incompatibility marker
      class Root < IncompatibilityCause
      end

      # plain dependency edge
      class Dependency < IncompatibilityCause
      end

      # no versions matched a term
      class NoVersions < IncompatibilityCause
        getter term : Term

        def initialize(@term : Term)
        end
      end

      # derived conflict: two incompatibilities combined
      class Conflict < IncompatibilityCause
        getter incompatibility : Incompatibility
        getter satisfier : Assignment

        def initialize(@incompatibility : Incompatibility, @satisfier : Assignment)
        end
      end

      class Custom < IncompatibilityCause
        getter explanation : String

        def initialize(@explanation : String)
        end
      end
    end

    # One assignment in the partial solution (pinned contract:
    # `Bundler::PubGrub::Assignment`).
    class Assignment
      getter term : Term
      getter cause : Incompatibility | Nil
      getter decision_level : Int32
      getter index : Int32

      def initialize(@term : Term, @cause : Incompatibility | Nil, @decision_level : Int32, @index : Int32)
      end

      def self.decision(package : Package, version : CandidateVersion, decision_level : Int32, index : Int32) : Assignment
        term = Term.new(Constraint.exact(package, version), true)
        new(term, nil, decision_level, index)
      end

      def decision? : Bool
        @cause.nil?
      end

      def satisfier_cause : Incompatibility
        cause.not_nil!
      end
    end

    # PubGrub incompatibility: a set of terms that cannot all be satisfied.
    class Incompatibility
      getter terms : Array(Term)
      getter cause : IncompatibilityCause
      getter custom_explanation : String?

      def initialize(terms : Array(Term), @cause : IncompatibilityCause,
                     @custom_explanation : String? = nil)
        @terms = cleanup_terms(terms)
      end

      def conflict? : Bool
        cause.is_a?(IncompatibilityCause::Conflict)
      end

      def failure? : Bool
        terms.empty? || (terms.size == 1 && terms[0].package.root? && terms[0].positive?)
      end

      def ==(other : Incompatibility) : Bool
        cause.class == other.cause.class && terms == other.terms &&
          custom_explanation == other.custom_explanation
      end

      def hash : UInt64
        {cause.class, terms}.hash
      end

      private def cleanup_terms(terms : Array(Term)) : Array(Term)
        return terms if terms.size <= 1
        return terms if terms.size == 2 && terms[0].package != terms[1].package

        # merge same-package terms (pinned: `Incompatibility#cleanup_terms`)
        by_package = Hash(Package, Term).new
        order = [] of Package
        terms.each do |term|
          if existing = by_package[term.package]?
            by_package[term.package] = existing.intersect(term)
          else
            by_package[term.package] = term
            order << term.package
          end
        end
        order.map { |p| by_package[p] }
      end

      def to_s(io : IO) : Nil
        if text = @custom_explanation
          io << text
          return
        end

        cause_obj = cause
        if cause_obj.is_a?(IncompatibilityCause::Root)
          io << "(root dependency)"
        elsif cause_obj.is_a?(IncompatibilityCause::Dependency)
          io << "#{terms[0]} depends on #{terms[1].invert}"
        elsif cause_obj.is_a?(IncompatibilityCause::NoVersions)
          io << "no versions satisfy #{cause_obj.term.constraint.constraint_string}"
        elsif cause_obj.is_a?(IncompatibilityCause::Custom)
          io << cause_obj.explanation
        elsif cause_obj.is_a?(IncompatibilityCause::Conflict)
          if failure?
            io << "version solving has failed"
          else
            io << "(derived conflict)"
          end
        end
      end
    end

    # PubGrub PartialSolution (pinned contract: `Bundler::PubGrub::PartialSolution`).
    class PartialSolution
      getter assignments : Array(Assignment)
      getter decisions : Hash(Package, CandidateVersion)
      getter attempted_solutions : Int32

      @assignments : Array(Assignment) = [] of Assignment
      @assignments_by : Hash(Package, Array(Assignment)) = {} of Package => Array(Assignment)
      @cumulative_assignments : Hash(Assignment, Term) = {} of Assignment => Term
      @decisions : Hash(Package, CandidateVersion) = {} of Package => CandidateVersion
      @terms : Hash(Package, Term) = {} of Package => Term
      @required : Hash(Package, Bool) = {} of Package => Bool
      @attempted_solutions : Int32 = 1
      @backtracking : Bool = false

      def initialize
        reset!
        @attempted_solutions = 1
        @backtracking = false
      end

      def decision_level : Int32
        decisions.size
      end

      def relation(term : Term) : Symbol
        return :overlap unless @terms.has_key?(term.package)

        result = @terms[term.package].relation(term)
        if ENV["CELERITE_DEBUG_RESOLVER"]?
          puts "[solution] have=#{@terms[term.package].constraint.constraint_string.inspect} incoming=#{term.constraint.constraint_string.inspect}/#{term.positive?} => #{result}"
        end
        result
      end

      def satisfies?(term : Term) : Bool
        relation(term) == :subset
      end

      def derive(term : Term, cause : Incompatibility) : Nil
        add_assignment(Assignment.new(term, cause, decision_level, assignments.size))
      end

      def satisfier(term : Term) : Assignment
        by = @assignments_by[term.package]?
        found = by.try(&.bsearch do |assignment|
          @cumulative_assignments[assignment].satisfies?(term)
        end)
        found || raise Error.new("#{term} unsatisfied")
      end

      # A list of unsatisfied terms (packages required but not decided).
      def unsatisfied : Array(Term)
        @required.keys.reject { |package| decisions.has_key?(package) }.map do |package|
          @terms[package]
        end
      end

      def decide(package : Package, version : CandidateVersion) : Nil
        @attempted_solutions += 1 if @backtracking
        @backtracking = false

        decisions[package] = version
        add_assignment(Assignment.decision(package, version, decision_level, assignments.size))
      end

      def backtrack(previous_level : Int32) : Nil
        @backtracking = true

        new_assignments = assignments.select(&.decision_level.<=(previous_level))
        new_decisions = decisions.first(previous_level).to_h

        reset!
        @decisions = new_decisions

        new_assignments.each { |assignment| add_assignment(assignment) }
      end

      private def reset! : Nil
        @assignments = [] of Assignment
        @assignments_by = Hash(Package, Array(Assignment)).new
        @cumulative_assignments = Hash(Assignment, Term).new
        @decisions = Hash(Package, CandidateVersion).new
        @terms = Hash(Package, Term).new
        @required = Hash(Package, Bool).new
      end

      private def add_assignment(assignment : Assignment) : Nil
        term = assignment.term
        package = term.package

        @assignments << assignment
        (@assignments_by[package] ||= [] of Assignment) << assignment

        @required[package] = true if term.positive?

        if old_term = @terms[package]?
          @terms[package] = old_term.intersect(term)
        else
          @terms[package] = term
        end

        @cumulative_assignments[assignment] = @terms[package]
      end
    end

    # PubGrub VersionSolver (pinned contract: `Bundler::PubGrub::VersionSolver`).
    class VersionSolver
      getter solution : PartialSolution

      @incompatibilities : Hash(Package, Array(Incompatibility))
      @seen_incompatibilities : Hash(Incompatibility, Bool)

      def initialize(@source : VersionSource, @root : Package, strategy : Strategy)
        @strategy = strategy
        @incompatibilities = Hash(Package, Array(Incompatibility)).new
        @seen_incompatibilities = Hash(Incompatibility, Bool).new
        @solution = PartialSolution.new

        add_incompatibility(Incompatibility.new(
          [Term.new(Constraint.any(@root), false)],
          IncompatibilityCause::Root.new
        ))
        debug_log("init: incomp[root] size=#{(@incompatibilities[@root]?.try(&.size) || 0)}")
        propagate(@root)
        debug_log("init done: unsatisfied=#{solution.unsatisfied.size} required=#{solution.decisions.size}d")
      end

      def solved? : Bool
        solution.unsatisfied.empty?
      end

      # One step of solving; returns false when done.
      def work : Bool
        unsatisfied_terms = solution.unsatisfied
        debug_log("work: unsatisfied=#{unsatisfied_terms.map(&.package.name).inspect}")
        return false if unsatisfied_terms.empty?

        package = choose_package_version_from(unsatisfied_terms)
        propagate(package)

        true
      end

      def solve : Hash(Package, CandidateVersion)
        while work; end
        solution.decisions
      end

      private def propagate(initial_package : Package) : Nil
        changed = [initial_package]
        debug_log("propagate: start #{initial_package.name}, queue=#{changed.size}")
        while package = changed.shift?
          (@incompatibilities[package]? || [] of Incompatibility).reverse_each do |incompatibility|
            result = propagate_incompatibility(incompatibility)
            if result == :conflict
              root_cause = resolve_conflict(incompatibility)
              changed.clear
              derived = propagate_incompatibility(root_cause)
              changed << derived if derived.is_a?(Package)
            elsif result.is_a?(Package)
              changed << result
            end
          end
          changed.uniq!
        end
      end

      private def propagate_incompatibility(incompatibility : Incompatibility) : Package | Symbol | Nil
        debug_log("prop_incomp: #{incompatibility.terms.size} terms")
        unsatisfied : Term? = nil
        incompatibility.terms.each do |term|
          relation = solution.relation(term)
          debug_log("  rel #{term.package.name}/#{term.positive?}=#{relation}")
          if relation == :disjoint
            return nil
          elsif relation == :overlap
            return nil if unsatisfied
            unsatisfied = term
          end
        end

        return :conflict unless unsatisfied

        debug_log("derive #{unsatisfied.not_nil!.invert.package.name} from #{incompatibility.terms.map(&.package.name).inspect}")
        solution.derive(unsatisfied.not_nil!.invert, incompatibility)

        unsatisfied.not_nil!.package
      end

      private def debug_log(msg : String) : Nil
        return unless ENV["CELERITE_DEBUG_RESOLVER"]?
        puts "[solver] #{msg}"
      end

      private def choose_package_version_from(unsatisfied_terms : Array(Term)) : Package
        remaining = [] of {Package, VersionRange}
        unsatisfied_terms.each { |t| remaining << {t.package, t.constraint.range} }

        package, version = @strategy.next_package_and_version(remaining)
        debug_log("trying #{package.name} #{version.try(&.version)}")

        if version.nil?
          unsatisfied_term = unsatisfied_terms.find { |t| t.package == package }.not_nil!
          add_incompatibility(@source.no_versions_incompatibility_for(package, unsatisfied_term))
          return package
        end

        conflict = false

        @source.incompatibilities_for(package, version).each do |incompatibility|
          next if @seen_incompatibilities.has_key?(incompatibility)
          @seen_incompatibilities[incompatibility] = true

          add_incompatibility(incompatibility)

          conflict ||= incompatibility.terms.all? do |term|
            term.package == package || solution.satisfies?(term)
          end
        end

        debug_log("conflict=#{conflict} deps=#{@source.incompatibilities_for(package, version.not_nil!).size}")
        unless conflict
          solution.decide(package, version.not_nil!)
        end

        package
      end

      private def resolve_conflict(incompatibility : Incompatibility) : Incompatibility
        new_incompatibility = nil

        until incompatibility.failure?
          most_recent_term = nil
          most_recent_satisfier = nil
          difference = nil

          previous_level = 1

          incompatibility.terms.each do |term|
            satisfier = solution.satisfier(term)

            if most_recent_satisfier.nil?
              most_recent_term = term
              most_recent_satisfier = satisfier
            elsif most_recent_satisfier.not_nil!.index < satisfier.index
              previous_level = Math.max(previous_level, most_recent_satisfier.not_nil!.decision_level)
              most_recent_term = term
              most_recent_satisfier = satisfier
              difference = nil
            else
              previous_level = Math.max(previous_level, satisfier.decision_level)
            end

            if most_recent_term == term
              difference = most_recent_satisfier.not_nil!.term.difference(most_recent_term.not_nil!)
              if difference.empty?
                difference = nil
              else
                difference_satisfier = solution.satisfier(difference.invert)
                previous_level = Math.max(previous_level, difference_satisfier.decision_level)
              end
            end
          end

          mrt = most_recent_term.not_nil!
          mrs = most_recent_satisfier.not_nil!

          if previous_level < mrs.decision_level || mrs.decision?
            solution.backtrack(previous_level)
            add_incompatibility(new_incompatibility) if new_incompatibility
            return incompatibility
          end

          new_terms = [] of Term
          new_terms += incompatibility.terms.reject(&.==(mrt))
          satisfier_incompatibility = mrs.cause
          if satisfier_incompatibility
            new_terms += satisfier_incompatibility.terms.reject do |term|
              term.package == mrs.term.package
            end
          end
          new_terms << difference.invert if difference

          new_incompatibility = Incompatibility.new(
            new_terms,
            IncompatibilityCause::Conflict.new(incompatibility, mrs)
          )

          if incompatibility.to_s == new_incompatibility.to_s
            break
          end

          incompatibility = new_incompatibility
        end

        raise SolveFailure.new(incompatibility)
      end

      private def add_incompatibility(incompatibility : Incompatibility) : Nil
        incompatibility.terms.each do |term|
          (@incompatibilities[term.package] ||= [] of Incompatibility) << incompatibility
        end
        debug_log("added incomp: packages=#{incompatibility.terms.map(&.package.name).inspect} root_table=#{@incompatibilities.size}")
      end
    end

    # Solver failure carrying the explaining incompatibility (pinned contract:
    # `Bundler::PubGrub::SolveFailure`).
    class SolveFailure < Error
      getter incompatibility : Incompatibility

      def initialize(@incompatibility : Incompatibility)
        super(incompatibility.to_s)
      end

      def status_code : Int32
        6
      end

      def wrap? : Bool
        true
      end
    end

    # Strategy: which package to try next and which version to try first
    # (pinned contract: `Bundler::Resolver::Strategy`).
    class Strategy
      def initialize(@source : VersionSource)
        @package_priority_cache = Hash({Package, VersionRange}, {Int32, Int32}).new
      end

      def next_package_and_version(unsatisfied : Array({Package, VersionRange})) : {Package, CandidateVersion?}
        package, range = next_term_to_try_from(unsatisfied)

        {package, most_preferred_version_of(package, range)}
      end

      private def next_term_to_try_from(unsatisfied : Array({Package, VersionRange})) : {Package, VersionRange}
        best : {Package, VersionRange}? = nil
        best_key : {Int32, Int32}? = nil
        unsatisfied.each do |entry|
          key = @package_priority_cache[entry] ||= begin
            package, range = entry
            matching_versions = @source.versions_for(package, range)
            higher_versions = @source.versions_for(package, range.upper_invert)
            {matching_versions.size <= 1 ? 0 : 1, higher_versions.size}
          end
          if best_key.nil? || key < best_key.not_nil!
            best_key = key
            best = entry
          end
        end
        best.not_nil!
      end

      private def most_preferred_version_of(package : Package, range : VersionRange) : CandidateVersion?
        versions = @source.versions_for(package, range)
        return versions[0]? if versions.size <= 1

        sorted = @source.sort_versions_by_preferred(package, versions)
        sorted[0]?
      end
    end
  end
end
