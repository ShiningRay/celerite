require "./version"

module Celerite
  module Gem
    # Semantic equivalent of RubyGems' `Gem::Requirement` (pinned contract:
    # `vendor/reference/{v4.0.24,bundler-v2.7.2}/requirement.rb`).
    #
    # Contracts:
    # - ops `= != > < >= <= ~>`; `~>` satisfied when `v >= r && v.release < r.bump`
    # - parse pattern: optional op, optional whitespace, non-empty version,
    #   optional whitespace; bare version => `=`
    # - empty requirement set behaves as `>= 0` (the "none" requirement)
    # - lockfile rendering of a dependency's requirement list: `"op version"`
    #   strings, byte-sorted then reversed (Bundler's Gem::Dependency#to_lock
    #   monkeypatch in `bundler/rubygems_ext.rb`)
    struct Requirement
      OPS           = ["=", "!=", ">", "<", ">=", "<=", "~>"]
      OPS_PATTERN   = OPS.map { |op| Regex.escape(op) }.join("|")
      PARSE_PATTERN = Regex.new("\\A\\s*(#{OPS_PATTERN})?\\s*(#{Version::VERSION_PATTERN})\\s*\\z")

      struct Constraint
        getter op : String
        getter version : Version

        def initialize(@op : String, @version : Version)
        end

        def to_s(io : IO) : Nil
          io << op << ' ' << version
        end
      end

      getter constraints : Array(Constraint)

      def self.new(*requirements : String | Version)
        new(requirements.to_a)
      end

      def initialize(requirements : Array(String | Version) = [] of String | Version)
        requirements = requirements.compact
        requirements = requirements.uniq

        @constraints = if requirements.empty?
                         [Constraint.new(">=", Version.new("0"))]
                       else
                         requirements.map { |r| self.class.parse_constraint(r) }
                       end
      end

      def self.parse(input : String) : Requirement
        new([input])
      end

      def self.parse_constraint(input : String | Version) : Constraint
        if input.is_a?(Version)
          return Constraint.new("=", input)
        end

        match = PARSE_PATTERN.match(input)
        unless match
          raise ::Celerite::BadRequirementError.new("Illformed requirement [#{input.inspect}]")
        end

        Constraint.new(match[1]? || "=", Version.new(match[2]))
      end

      def satisfied_by?(version : Version) : Bool
        constraints.all? do |c|
          case c.op
          when "="
            (version <=> c.version) == 0
          when "!="
            (version <=> c.version) != 0
          when ">"
            (version <=> c.version) > 0
          when "<"
            (version <=> c.version) < 0
          when ">="
            (version <=> c.version) >= 0
          when "<="
            (version <=> c.version) <= 0
          else # "~>"
            (version <=> c.version) >= 0 && version.release < c.version.bump
          end
        end
      end

      def prerelease? : Bool
        constraints.any? { |c| c.version.prerelease? }
      end

      # True when this is exactly the default `>= 0` requirement.
      def none? : Bool
        constraints.size == 1 &&
          constraints[0].op == ">=" &&
          constraints[0].version.raw == "0"
      end

      def exact? : Bool
        constraints.size == 1 && constraints[0].op == "="
      end

      def specific? : Bool
        return true if constraints.size > 1

        !{">", ">="}.includes?(constraints[0].op)
      end

      # `Gem::Dependency#to_lock` rendering: `"op version"` strings byte-sorted,
      # then reversed; omitted entirely for the none requirement.
      def to_lock_requirements : Array(String)
        constraints.map(&.to_s).sort.reverse
      end

      # `Gem::Requirement#for_lockfile` rendering (used by RubyGems-side
      # lockfiles): nil for the default requirement, otherwise version-sorted
      # unique list wrapped in parens.
      def for_lockfile : String?
        return nil if none?

        list = constraints
          .sort_by { |c| c.version }
          .map(&.to_s)
          .uniq
        " (#{list.join(", ")})"
      end

      def to_s(io : IO) : Nil
        io << constraints.map(&.to_s).join(", ")
      end

      def inspect(io : IO) : Nil
        io << "#<Celerite::Gem::Requirement "
        to_s(io)
        io << ">"
      end

      def ==(other : Requirement) : Bool
        constraints == other.constraints
      end

      def hash : UInt64
        constraints.hash
      end

      # Intersection of two requirements: concatenating the constraint lists
      # (Ruby semantics: Gem::Requirement.new(a.as_list + b.as_list)).
      def self.intersect(a : Requirement, b : Requirement) : Requirement
        list = a.constraints.map(&.to_s) + b.constraints.map(&.to_s)
        Requirement.new(list)
      end
    end
  end
end
