module Celerite
  # Minimal Bundler::RubyVersion-compatible representation for M7(1).
  # Parses "ruby X.Y.Z", "ruby X.Y.ZpN", "ruby X.Y.Z (engine ev)" forms
  # and compares against the running system (engine, version, engine_version,
  # patchlevel) using Bundler 4.0.24 semantics.
  class RubyVersion
    getter versions : Array(String)
    getter patchlevel : String?
    getter engine : String
    getter engine_versions : Array(String)
    getter input_engine : String?

    PATTERN = /^ruby\s+(\d+\.\d+\.\d+(?:\.\S+)?)(?:p(-?\d+))?(?:\s+\((\S+)\s+(.+)\))?/

    def initialize(versions : String | Array(String), patchlevel : String | Int32 | Nil, engine : String?, engine_version : String | Array(String) | Nil)
      raw_versions = versions.is_a?(Array) ? versions : [versions]
      @versions = raw_versions.map { |v| normalize_version(v.to_s) }
      @input_engine = engine.try(&.to_s)
      @engine = @input_engine || "ruby"
      ev = if engine_version
             engine_version.is_a?(Array) ? engine_version.map(&.to_s) : [engine_version.to_s]
           else
             @versions.dup
           end
      @engine_versions = ev
      @patchlevel = if patchlevel.nil?
                      nil
                    else
                      patchlevel.to_s
                    end
      # ruby-head style: missing patchlevel on prerelease treated as -1 in Bundler
      if @patchlevel.nil? && prerelease_version?
        @patchlevel = "-1"
      end
    end

    def self.from_string(string : String) : RubyVersion?
      if m = string.strip.match(PATTERN)
        ruby_v = m[1]
        pl = m[2]?
        eng = m[3]?
        eng_v = m[4]?
        new(ruby_v, pl, eng, eng_v)
      end
    end

    def self.system(engine : String, versions : String | Array(String), engine_version : String | Array(String), patchlevel : String | Int32 | Nil) : RubyVersion
      new(versions, patchlevel, engine, engine_version)
    end

    def self.system_from_env(env) : RubyVersion
      system(env.engine, env.ruby_version, env.engine_version, env.patchlevel)
    end

    # Parses Gemfile DSL ruby declaration string when available as "ruby X..." or
    # plain version string; returns nil if unparseable.
    def self.parse_requirement(ruby_string : String?) : RubyVersion?
      return nil unless ruby_string
      s = ruby_string.strip
      return nil if s.empty?
      from_string(s) || from_string("ruby #{s}")
    end

    def to_s(io : IO) : Nil
      io << "ruby " << versions_string(@versions)
      unless @engine == "ruby"
        io << " (" << @engine << " " << versions_string(@engine_versions) << ")"
      end
    end

    def to_s : String
      String.build { |io| to_s(io) }
    end

    def single_version_string : String
      @versions.first? || "0"
    end

    def gem_version : Gem::Version
      Gem::Version.new(single_version_string)
    end

    def engine_gem_version : Gem::Version
      Gem::Version.new(@engine_versions.first? || single_version_string)
    end

    # Returns [problem, expected, actual] comparing self (requested) vs other
    # (system), or nil when compatible. Matches Bundler 4.0.24 RubyVersion#diff.
    def diff(other : RubyVersion) : Tuple(Symbol, String, String)?
      if @engine != other.engine && @input_engine
        {:engine, @engine, other.engine}
      elsif @versions.empty? || !matches_requirements?(@versions, other.gem_version.to_s)
        {:version, versions_string(@versions), versions_string(other.versions)}
      elsif @input_engine && !matches_requirements?(@engine_versions, other.engine_gem_version.to_s)
        {:engine_version, versions_string(@engine_versions), versions_string(other.engine_versions)}
      elsif @patchlevel && !matches_patchlevel?(@patchlevel.not_nil!, other.patchlevel)
        {:patchlevel, @patchlevel.not_nil!, (other.patchlevel || "")}
      else
        nil
      end
    end

    # Bundler::RubyVersionMismatch message text for a diff tuple.
    def self.mismatch_message(problem : Symbol, expected : String, actual : String, requested : RubyVersion, system : RubyVersion) : String
      case problem
      when :engine
        "Your Ruby engine is #{actual}, but your Gemfile specified #{expected}"
      when :version
        "Your Ruby version is #{actual}, but your Gemfile specified #{expected}"
      when :engine_version
        "Your #{system.engine} version is #{actual}, but your Gemfile specified #{requested.engine} #{expected}"
      when :patchlevel
        if !expected.is_a?(String)
          "The Ruby patchlevel in your Gemfile must be a string"
        else
          "Your Ruby patchlevel is #{actual}, but your Gemfile specified #{expected}"
        end
      else
        "Your Ruby version is #{actual}, but your Gemfile specified #{expected}"
      end
    end

    def ==(other : RubyVersion) : Bool
      @versions == other.versions && @engine == other.engine && @engine_versions == other.engine_versions
    end

    private def versions_string(versions : Array(String)) : String
      versions.join(", ")
    end

    private def normalize_version(v : String) : String
      v.tr("-", ".")
    end

    private def prerelease_version? : Bool
      v = @versions.first?
      return false unless v
      Gem::Version.new(v).prerelease?
    rescue
      false
    end

    private def matches_requirements?(requirements : Array(String), version : String) : Bool
      # -1 sentinel (ruby-head) matches by equality
      has_neg1 = requirements.any? { |r| r.to_s == "-1" } || version.to_s == "-1"
      if has_neg1
        return requirements.any? { |r| r.to_s == "-1" } && version.to_s == "-1"
      end
      Gem::Requirement.new(requirements).satisfied_by?(Gem::Version.new(version))
    rescue
      false
    end

    private def matches_patchlevel?(req_patch : String, actual_patch : String?) : Bool
      return false if actual_patch.nil?
      # Bundler: if req patch is "-1" or actual "-1" compare equality, else Gem::Requirement match
      return req_patch == actual_patch if req_patch == "-1" || actual_patch == "-1"
      Gem::Requirement.new([req_patch]).satisfied_by?(Gem::Version.new(actual_patch))
    rescue
      req_patch == actual_patch
    end
  end
end
