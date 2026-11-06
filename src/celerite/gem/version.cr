require "../errors"

module Celerite
  module Gem
    # Semantic equivalent of RubyGems' `Gem::Version`, derived from the pinned
    # reference sources at `vendor/reference/{v4.0.24,bundler-v2.7.2}/version.rb`.
    #
    # Notable contracts:
    # - grammar `[0-9]+(?>\.[0-9a-zA-Z]+)*(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?`,
    #   anchored, surrounding whitespace allowed, empty/blank => "0"
    # - stored string replaces `-` with `.pre.` (`1.0-beta` is `1.0.pre.beta`);
    #   `to_s` returns that stored string
    # - prerelease = stored string contains a letter
    # - comparison over canonical segments (trailing `[.0]+` after a letter or
    #   dot removed; prereleases additionally drop `[0.]+` before the first
    #   letter); at the first differing index a string sorts before a number
    #
    # This is deliberately *not* SemVer. Never sort versions as integers or
    # strings, and never reorder segments.
    struct Version
      include Comparable(self)

      VERSION_PATTERN  = "[0-9]+(?>\\.[0-9a-zA-Z]+)*(-[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?"
      ANCHORED_PATTERN = Regex.new("\\A\\s*(#{VERSION_PATTERN})?\\s*\\z")
      SEGMENT_PATTERN  = Regex.new("\\d+|[a-z]+", Regex::CompileOptions::IGNORE_CASE)

      alias Segment = Int32 | String

      # The stored version string: stripped, `-` rewritten to `.pre.`, and the
      # string `to_s` returns (parity with Ruby's `Gem::Version#version`).
      getter raw : String

      @canonical : Array(Segment)?

      def initialize(str : String)
        unless self.class.correct?(str)
          raise ::Celerite::VersionError.new("Malformed version number string #{str.inspect}")
        end

        s = str.strip
        s = "0" if s.empty?
        @raw = s.gsub("-", ".pre.")
        @canonical = nil
      end

      def self.correct?(str : String) : Bool
        ANCHORED_PATTERN.matches?(str)
      end

      def self.new(version : Version) : Version
        version
      end

      def prerelease? : Bool
        raw.matches?(/[a-zA-Z]/)
      end

      # Segments of the stored string (not canonicalized): digits become
      # integers, letter runs stay strings.
      def segments : Array(Segment)
        scan_segments(raw)
      end

      # The release for this version (e.g. 1.2.0.a -> 1.2.0); non-prereleases
      # return themselves.
      def release : Version
        return self unless prerelease?

        segs = segments
        while segs.any?(String)
          segs.pop
        end
        self.class.new(segs.join("."))
      end

      # Next-to-last revision number incremented (5.3.1 => 5.4); prerelease
      # parts ignored.
      def bump : Version
        segs = segments
        while segs.any?(String)
          segs.pop
        end
        segs.pop if segs.size > 1
        last = segs[-1]
        segs[-1] = last.is_a?(Int32) ? last + 1 : last
        self.class.new(segs.join("."))
      end

      def <=>(other : Version) : Int32
        return 0 if raw == other.raw || canonical == other.canonical

        compare_segments(canonical, other.canonical)
      end

      # Ruby `eql?`: same precision required; "1.0" is not eql? "1".
      def eql?(other : Version) : Bool
        raw == other.raw
      end

      def hash : UInt64
        canonical.hash
      end

      def to_s(io : IO) : Nil
        io << raw
      end

      def inspect(io : IO) : Nil
        io << "#<Celerite::Gem::Version "
        raw.inspect(io)
        io << ">"
      end

      # Canonical segment list used for comparison and hashing.
      def canonical : Array(Segment)
        @canonical ||= compute_canonical
      end

      private def compute_canonical : Array(Segment)
        cv = trim_trailing_zeros(raw)
        cv = trim_leading_zeros(cv) if prerelease?
        scan_segments(cv)
      end

      # Mirrors `@version.sub(/(?<=[a-zA-Z.])[.0]+\z/, "")`: removes the
      # leftmost suffix made entirely of `.`/`0` characters that is preceded by
      # a letter or dot. (A suffix starting at index 0 never matches: the
      # lookbehind requires a preceding character.)
      private def trim_trailing_zeros(str : String) : String
        i = 1
        while i < str.size
          if letter_or_dot?(str[i - 1]) && zero_dot_run?(str, i)
            return str.byte_slice(0, i)
          end
          i += 1
        end
        str
      end

      # Mirrors `@version.sub(/(?<=\.|\A)[0.]+(?=[a-zA-Z])/, "")`: removes the
      # leftmost run of `.`/`0` characters (greedy, with backtracking) that is
      # followed by a letter, and is preceded by a dot or starts the string.
      private def trim_leading_zeros(str : String) : String
        i = 0
        while i < str.size
          if i == 0 || str[i - 1] == '.'
            run_end = i
            while run_end < str.size && (str[run_end] == '0' || str[run_end] == '.')
              run_end += 1
            end
            k = run_end
            while k > i
              if k < str.size && letter?(str[k])
                return str.byte_slice(0, i) + str[k..]
              end
              k -= 1
            end
          end
          i += 1
        end
        str
      end

      private def letter_or_dot?(char : Char) : Bool
        letter?(char) || char == '.'
      end

      private def letter?(char : Char) : Bool
        ('a' <= char <= 'z') || ('A' <= char <= 'Z')
      end

      private def zero_dot_run?(str : String, from : Int32) : Bool
        from.upto(str.size - 1) do |idx|
          c = str[idx]
          return false unless c == '0' || c == '.'
        end
        true
      end

      private def scan_segments(str : String) : Array(Segment)
        result = Array(Segment).new
        str.scan(SEGMENT_PATTERN) do |match|
          token = match[0]
          if token[0].ascii_number?
            result << token.to_i
          else
            result << token
          end
        end
        result
      end

      private def compare_segments(lh : Array(Segment), rh : Array(Segment)) : Int32
        lhsize = lh.size
        rhsize = rh.size
        limit = lhsize < rhsize ? lhsize : rhsize

        i = 0
        while i < limit
          lhs = lh[i]
          rhs = rh[i]
          i += 1

          next if lhs == rhs
          return -1 if lhs.is_a?(String) && rhs.is_a?(Int32)
          return 1 if lhs.is_a?(Int32) && rhs.is_a?(String)

          return compare_pair(lhs, rhs)
        end

        lhs = lh[i]?

        if lhs.nil?
          while i < rhsize
            rhs = rh[i]
            return 1 if rhs.is_a?(String)
            return -1 unless rhs.is_a?(Int32) && rhs == 0
            i += 1
          end
        else
          while i < lhsize
            return -1 if lhs.is_a?(String)
            return 1 unless lhs.is_a?(Int32) && lhs == 0
            i += 1
            lhs = lh[i]?
          end
        end

        0
      end

      private def compare_pair(lhs : Segment, rhs : Segment) : Int32
        case lhs
        when Int32
          rhs.is_a?(Int32) ? (lhs <=> rhs) : -1
        else
          rhs.is_a?(String) ? (lhs <=> rhs) : 1
        end
      end
    end
  end
end
