require "../gem/version"
require "../gem/platform"
require "./package"

module Celerite
  module Resolver
    # A PubGrub-compatible "Version": a Gem::Version plus a platform priority
    # (ruby = -1, platform-specific = +1), pinned contract
    # `Bundler::Resolver::Candidate`.
    struct CandidateVersion
      include Comparable(self)

      getter version : Gem::Version
      getter priority : Int32

      def initialize(@version : Gem::Version, @priority : Int32 = -1)
      end

      def prerelease? : Bool
        version.prerelease?
      end

      def <=>(other : CandidateVersion) : Int32
        c = version <=> other.version
        return c if c != 0
        priority <=> other.priority
      end

      def ==(other : CandidateVersion) : Bool
        version == other.version && priority == other.priority
      end

      def hash : UInt64
        {version, priority}.hash
      end

      def to_s(io : IO) : Nil
        io << version
      end
    end

    # PubGrub VersionRange over CandidateVersion (pinned contract:
    # `Bundler::PubGrub::VersionRange`).
    class VersionRange
      getter min : CandidateVersion?
      getter max : CandidateVersion?
      getter? include_min : Bool
      getter? include_max : Bool
      getter name : String?

      def initialize(@min : CandidateVersion? = nil, @max : CandidateVersion? = nil,
                     @include_min : Bool = false, @include_max : Bool = false,
                     @name : String? = nil)
        if @min.nil? && @include_min
          raise ArgumentError.new("Ranges without a lower bound cannot have include_min == true")
        end
        if @max.nil? && @include_max
          raise ArgumentError.new("Ranges without an upper bound cannot have include_max == true")
        end
      end

      def self.empty : VersionRange
        EmptyRange.instance
      end

      def self.any : VersionRange
        new
      end

      def self.exact(version : CandidateVersion) : VersionRange
        new(min: version, max: version, include_min: true, include_max: true)
      end

      def ranges : Array(VersionRange)
        [self]
      end

      def empty? : Bool
        false
      end

      def any? : Bool
        min.nil? && max.nil?
      end

      def include?(version : CandidateVersion) : Bool
        compare_version(version) == 0
      end

      def compare_version(version : CandidateVersion) : Int32
        if min = @min
          c = version <=> min
          return -1 if c < 0
          return -1 if c == 0 && !include_min?
        end

        if max = @max
          c = version <=> max
          return 1 if c > 0
          return 1 if c == 0 && !include_max?
        end

        0
      end

      # Partitions sorted versions into [lower, within, higher].
      def partition_versions(versions : Array(CandidateVersion)) : {Array(CandidateVersion), Array(CandidateVersion), Array(CandidateVersion)}
        lower_index = 0
        if min = @min
          lower_index = versions.index do |v|
            include_min? ? v >= min : v > min
          end || versions.size
        end

        lower = versions[0, lower_index]
        rest = versions[lower_index..]

        upper_index = rest.size
        if max = @max
          upper_index = rest.index do |v|
            include_max? ? v > max : v >= max
          end || rest.size
        end

        {lower, rest[0, upper_index], rest[upper_index..]}
      end

      def select_versions(versions : Array(CandidateVersion)) : Array(CandidateVersion)
        return versions if any?
        partition_versions(versions)[1]
      end

      def strictly_lower?(other : VersionRange) : Bool
        return false if max.nil? || other.min.nil?

        c = max.not_nil! <=> other.min.not_nil!
        if c == 0
          !include_max? || !other.include_min?
        else
          c < 0
        end
      end

      def strictly_higher?(other : VersionRange) : Bool
        other.strictly_lower?(self)
      end

      def intersects?(other : VersionRange) : Bool
        return false if other.empty?
        return other.intersects?(self) if other.is_a?(VersionUnion)
        !strictly_lower?(other) && !strictly_higher?(other)
      end

      def allows_any?(other : VersionRange) : Bool
        intersects?(other)
      end

      def intersect(other : VersionRange) : VersionRange
        return other if other.empty?
        return other.intersect(self) if other.is_a?(VersionUnion)

        min_range =
          if @min.nil?
            other
          elsif other.min.nil?
            self
          else
            c = min.not_nil! <=> other.min.not_nil!
            case c
            when  0 then include_min? ? other : self
            when -1 then other
            else         self
            end
          end

        max_range =
          if @max.nil?
            other
          elsif other.max.nil?
            self
          else
            c = max.not_nil! <=> other.max.not_nil!
            case c
            when  0 then include_max? ? other : self
            when -1 then self
            else         other
            end
          end

        if min_range.object_id != max_range.object_id && min_range.min && max_range.max
          c = min_range.min.not_nil! <=> max_range.max.not_nil!
          if c > 0
            return VersionRange.empty
          elsif c == 0
            return VersionRange.empty unless min_range.include_min? && max_range.include_max?
          end
        end

        VersionRange.new(
          min: min_range.min,
          include_min: min_range.include_min?,
          max: max_range.max,
          include_max: max_range.include_max?,
        )
      end

      def span(other : VersionRange) : VersionRange
        return self if other.empty?

        min_range =
          if @min.nil?
            self
          elsif other.min.nil?
            other
          else
            c = min.not_nil! <=> other.min.not_nil!
            case c
            when  0 then include_min? ? self : other
            when -1 then self
            else         other
            end
          end

        max_range =
          if @max.nil?
            self
          elsif other.max.nil?
            other
          else
            c = max.not_nil! <=> other.max.not_nil!
            case c
            when  0 then include_max? ? self : other
            when -1 then other
            else         self
            end
          end

        VersionRange.new(
          min: min_range.min,
          include_min: min_range.include_min?,
          max: max_range.max,
          include_max: max_range.include_max?,
        )
      end

      def union(other : VersionRange) : VersionRange
        return other.union(self) if other.is_a?(VersionUnion)

        if contiguous_to?(other)
          span(other)
        else
          VersionUnion.union([self, other])
        end
      end

      def contiguous_to?(other : VersionRange) : Bool
        return false if other.empty?
        return true if any?

        intersects?(other) || contiguous_below?(other) || contiguous_above?(other)
      end

      def contiguous_below?(other : VersionRange) : Bool
        return false if max.nil? || other.min.nil?

        max == other.min && (include_max? || other.include_min?)
      end

      def contiguous_above?(other : VersionRange) : Bool
        other.contiguous_below?(self)
      end

      def allows_all?(other : VersionRange) : Bool
        return true if other.empty?

        if other.is_a?(VersionUnion)
          return VersionUnion.new([self]).allows_all?(other)
        end

        return false if max && other.max.nil?
        return false if min && other.min.nil?

        if min = @min
          other_min = other.min.not_nil!
          c = min <=> other_min
          if c > 0
            return false
          elsif c == 0 && !include_min? && other.include_min?
            return false
          end
        end

        if max = @max
          other_max = other.max.not_nil!
          c = max <=> other_max
          return false if c < 0
          return false if c == 0 && !include_max? && other.include_max?
        end

        true
      end

      def upper_invert : VersionRange
        return VersionRange.empty unless max = @max
        VersionRange.new(min: max, include_min: !include_max?)
      end

      def invert : VersionRange
        return VersionRange.empty if any?

        if @min.nil?
          return VersionRange.new(min: max, include_min: !include_max?)
        end
        if @max.nil?
          return VersionRange.new(max: min, include_max: !include_min?)
        end

        VersionRange.new(max: min, include_max: !include_min?)
          .union(VersionRange.new(min: max, include_min: !include_max?))
      end

      def ==(other : VersionRange) : Bool
        if other.is_a?(EmptyRange)
          empty?
        else
          !other.empty? &&
            min == other.min && max == other.max &&
            include_min? == other.include_min? && include_max? == other.include_max?
        end
      end

      def hash : UInt64
        {min, max, include_min?, include_max?}.hash
      end

      def to_s(io : IO) : Nil
        io << (name || constraints_text)
      end

      private def constraints_text : String
        return "any" if any?
        return "= #{min}" if min.to_s == max.to_s

        c = [] of String
        c << "#{include_min? ? ">=" : ">"} #{min}" if min
        c << "#{include_max? ? "<=" : "<"} #{max}" if max
        c.join(", ")
      end
    end

    # The singleton empty range.
    class EmptyRange < VersionRange
      @@instance : EmptyRange? = nil

      def initialize
        super()
      end

      def self.instance : EmptyRange
        @@instance ||= EmptyRange.new
      end

      def empty? : Bool
        true
      end

      def intersects?(other : VersionRange) : Bool
        false
      end

      def intersect(other : VersionRange) : VersionRange
        self
      end

      def allows_all?(other : VersionRange) : Bool
        other.empty?
      end

      def include?(version : CandidateVersion) : Bool
        false
      end

      def any? : Bool
        false
      end

      def select_versions(versions : Array(CandidateVersion)) : Array(CandidateVersion)
        [] of CandidateVersion
      end

      def upper_invert : VersionRange
        VersionRange.any
      end

      def invert : VersionRange
        VersionRange.any
      end

      def to_s(io : IO) : Nil
        io << "(no versions)"
      end
    end

    # Union of disjoint ranges (pinned contract: `Bundler::PubGrub::VersionUnion`).
    class VersionUnion < VersionRange
      getter ranges : Array(VersionRange)

      def self.union(list : Array(VersionRange)) : VersionRange
        normalized = normalize_ranges(list)
        return VersionRange.empty if normalized.empty?
        return normalized[0] if normalized.size == 1
        new(normalized)
      end

      def self.normalize_ranges(ranges : Array(VersionRange)) : Array(VersionRange)
        flat = ranges.flat_map(&.ranges).reject(&.empty?)
        return [] of VersionRange if flat.empty?

        mins, bounded = flat.partition(&.min.nil?)
        original = mins + bounded.sort { |a, b|
          c = a.min.not_nil! <=> b.min.not_nil!
          if c == 0
            (a.include_min? ? 0 : 1) <=> (b.include_min? ? 0 : 1)
          else
            c
          end
        }

        result = [original.shift]
        original.each do |range|
          if result.last.contiguous_to?(range)
            result << result.pop.span(range)
          else
            result << range
          end
        end
        result
      end

      def initialize(@ranges : Array(VersionRange))
        super()
      end

      def ranges_list : Array(VersionRange)
        @ranges
      end

      def empty? : Bool
        false
      end

      def any? : Bool
        false
      end

      def select_versions(versions : Array(CandidateVersion)) : Array(CandidateVersion)
        selected = [] of CandidateVersion
        acc = versions
        @ranges.each do |range|
          _, matching, higher = range.partition_versions(acc)
          selected.concat(matching)
          acc = higher
        end
        selected
      end

      def intersects?(other : VersionRange) : Bool
        my_ranges = @ranges.dup
        other_ranges = other.ranges.dup

        my_range = my_ranges.shift?
        other_range = other_ranges.shift?
        while my_range && other_range
          return true if my_range.intersects?(other_range)

          if my_range.max.nil? || other_range.max.nil? || other_range.max.not_nil! < my_range.max.not_nil!
            other_range = other_ranges.shift?
          else
            my_range = my_ranges.shift?
          end
        end
        false
      end

      def allows_all?(other : VersionRange) : Bool
        my_ranges = @ranges.dup
        my_range = my_ranges.shift?

        other.ranges.all? do |other_range|
          while my_range
            break if my_range.allows_all?(other_range)
            my_range = my_ranges.shift?
          end
          !my_range.nil?
        end
      end

      def intersect(other : VersionRange) : VersionRange
        my_ranges = @ranges.dup
        other_ranges = other.ranges.dup
        new_ranges = [] of VersionRange

        my_range = my_ranges.shift?
        other_range = other_ranges.shift?
        while my_range && other_range
          new_ranges << my_range.intersect(other_range)

          if my_range.max.nil? || other_range.max.nil? || other_range.max.not_nil! < my_range.max.not_nil!
            other_range = other_ranges.shift?
          else
            my_range = my_ranges.shift?
          end
        end
        VersionUnion.union(new_ranges.reject(&.empty?))
      end

      def upper_invert : VersionRange
        @ranges.last.upper_invert
      end

      def invert : VersionRange
        @ranges.map(&.invert).reduce { |a, b| a.intersect(b) }
      end

      def union(other : VersionRange) : VersionRange
        VersionUnion.union([self, other])
      end

      def ==(other : VersionRange) : Bool
        other.is_a?(VersionUnion) && @ranges == other.ranges
      end

      def hash : UInt64
        @ranges.hash
      end

      def to_s(io : IO) : Nil
        io << @ranges.join(" OR ")
      end
    end

    # PubGrub VersionConstraint: package + range (pinned contract:
    # `Bundler::PubGrub::VersionConstraint`).
    class Constraint
      getter package : Package
      getter range : VersionRange

      def initialize(@package : Package, @range : VersionRange)
      end

      def self.exact(package : Package, version : CandidateVersion) : Constraint
        new(package, VersionRange.exact(version))
      end

      def self.any(package : Package) : Constraint
        new(package, VersionRange.any)
      end

      def intersect(other : Constraint) : Constraint
        Constraint.new(package, range.intersect(other.range))
      end

      def union(other : Constraint) : Constraint
        Constraint.new(package, range.union(other.range))
      end

      def invert : Constraint
        Constraint.new(package, range.invert)
      end

      def allows_all?(other : Constraint) : Bool
        range.allows_all?(other.range)
      end

      def allows_any?(other : Constraint) : Bool
        range.intersects?(other.range)
      end

      def empty? : Bool
        range.empty?
      end

      def any? : Bool
        range.any?
      end

      def relation(other : Constraint) : Symbol
        # Ruby semantics: subset?(other) == other.allows_all?(self)
        if other.allows_all?(self)
          :subset
        elsif allows_any?(other)
          :overlap
        else
          :disjoint
        end
      end

      def constraint_string : String
        any? ? ">= 0" : range.to_s
      end

      def ==(other : Constraint) : Bool
        package == other.package && range == other.range
      end

      def hash : UInt64
        {package, range}.hash
      end

      def to_s(io : IO) : Nil
        io << package << ' ' << constraint_string
      end
    end
  end
end
