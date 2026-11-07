require "../errors"

module Celerite
  module Gem
    # Semantic equivalent of RubyGems' `Gem::Platform` (pinned contract:
    # `vendor/reference/{v4.0.24,bundler-v2.7.2}/platform.rb`).
    #
    # The virtual "ruby" platform is the empty triple; `to_s` renders it as
    # "ruby". Parsing follows RubyGems' ordered os-pattern case table,
    # including the legacy jruby single-token form and mswin cpu fixups.
    struct Platform
      include Comparable(self)

      getter cpu : String?
      getter os : String?
      getter version : String?

      # The virtual platform matching every pure-Ruby gem.
      RUBY = new

      def initialize
        @cpu = nil
        @os = nil
        @version = nil
      end

      def initialize(@cpu : String?, @os : String?, @version : String?)
      end

      def self.new(str : String) : Platform
        return RUBY if str == "ruby" || str == ""
        return local if str == "current"

        parts = str.sub(/-+\z/, "").split("-", limit: 2)
        cpu = parts[0]?
        os_part = parts[1]?
        if os_part.nil?
          os_part = cpu # legacy jruby: single token is an os
          cpu = nil
        end

        if cpu && cpu.matches?(/i\d86/)
          cpu = "x86"
        end

        os, version, cpu = match_os(os_part.not_nil!, cpu)

        new(cpu, os, version)
      end

      # Mirrors RubyGems' ordered case table; first matching branch wins.
      # Returns {os, version, cpu} because the mswin branch may fix the cpu.
      private def self.match_os(os_part : String, cpu : String?) : {String?, String?, String?}
        if m = os_part.match(/aix-?(\d+)?/)
          return {"aix", m[1]?, cpu}
        elsif m = os_part.match(/cygwin/)
          return {"cygwin", nil, cpu}
        elsif m = os_part.match(/darwin-?(\d+)?/)
          return {"darwin", m[1]?, cpu}
        elsif m = os_part.match(/^macruby-?(\d+(?:\.\d+)*)?/)
          return {"macruby", m[1]?, cpu}
        elsif m = os_part.match(/freebsd-?(\d+)?/)
          return {"freebsd", m[1]?, cpu}
        elsif os_part == "java" || os_part == "jruby"
          return {"java", nil, cpu}
        elsif m = os_part.match(/^java-?(\d+(?:\.\d+)*)?/)
          return {"java", m[1]?, cpu}
        elsif m = os_part.match(/^dalvik-?(\d+)?/)
          return {"dalvik", m[1]?, cpu}
        elsif m = os_part.match(/^dotnet-?(\d+(?:\.\d+)*)?/)
          return {"dotnet", m[1]?, cpu}
        elsif m = os_part.match(/linux-?(\w+)?/)
          return {"linux", m[1]?, cpu}
        elsif m = os_part.match(/mingw32/)
          return {"mingw32", nil, cpu}
        elsif m = os_part.match(/mingw-?(\w+)?/)
          return {"mingw", m[1]?, cpu}
        elsif m = os_part.match(/(mswin\d+)(?:[_-](\d+))?/)
          cpu = "x86" if cpu.nil? && m[1].ends_with?("32")
          return {m[1], m[2]?, cpu}
        elsif m = os_part.match(/netbsdelf/)
          return {"netbsdelf", nil, cpu}
        elsif m = os_part.match(/openbsd-?(\d+\.\d+)?/)
          return {"openbsd", m[1]?, cpu}
        elsif m = os_part.match(/solaris-?(\d+\.\d+)?/)
          return {"solaris", m[1]?, cpu}
        elsif m = os_part.match(/wasi/)
          return {"wasi", nil, cpu}
        elsif m = os_part.match(/^(\w+_platform)-?(\d+)?/)
          return {m[1], m[2]?, cpu}
        else
          return {"unknown", nil, cpu}
        end
      end

      def self.local : Platform
        @@local ||= new(local_arch)
      end

      # Best-effort local platform discovery with an explicit test override.
      # Parity with `Gem::Platform.local` is differential-tested per host;
      # `CELERITE_LOCAL_PLATFORM` overrides for fixtures.
      def self.local_arch : String
        if override = ENV["CELERITE_LOCAL_PLATFORM"]?
          return override
        end

        {% if flag?(:windows) %}
          arch = ENV["PROCESSOR_ARCHITECTURE"]? || "AMD64"
          arch == "ARM64" ? "aarch64-mingw-ucrt" : "x64-mingw-ucrt"
        {% elsif flag?(:darwin) %}
          cpu = `uname -m`.strip
          major = `uname -r`.strip.split(".")[0]
          "#{cpu}-darwin-#{major}"
        {% else %}
          "#{`uname -m`.strip}-linux"
        {% end %}
      end

      def to_s(io : IO) : Nil
        if ruby?
          io << "ruby"
          return
        end

        joiner = cpu.nil? ? "" : "-"
        io << [cpu, os, version].compact.join(joiner)
      end

      def inspect(io : IO) : Nil
        io << "#<Celerite::Gem::Platform "
        to_s(io)
        io << ">"
      end

      def ruby? : Bool
        cpu.nil? && os.nil? && version.nil?
      end

      def ==(other : Platform) : Bool
        cpu == other.cpu && os == other.os && version == other.version
      end

      def hash : UInt64
        {cpu, os, version}.hash
      end

      # Platform match semantics (Ruby's `===`). The receiver is the gem
      # platform and the argument the user platform; not commutative for linux.
      def match?(other : Platform) : Bool
        # universal-mingw matches any mingw variant
        if (cpu == "universal" || other.cpu == "universal") &&
           os.try(&.starts_with?("mingw")) && other.os.try(&.starts_with?("mingw"))
          return true
        end

        cpu_match =
          cpu.nil? || cpu == "universal" ||
            other.cpu.nil? || other.cpu == "universal" ||
            cpu == other.cpu ||
            (cpu == "arm" && other.cpu.try(&.starts_with?("armv")))
        return false unless cpu_match

        return false unless os == other.os

        version_match?(other)
      end

      private def version_match?(other : Platform) : Bool
        return true if version == other.version
        return version.nil? || other.version.nil? unless os == "linux"

        normalized_linux_version == other.normalized_linux_version ||
          {musl_candidate("musl"), musl_candidate("musleabi"), musl_candidate("musleabihf")}.includes?(other.version)
      end

      def normalized_linux_version : String?
        return nil unless v = version

        without_gnu = v.sub(/\Agnu/, "")
        without_abi = without_gnu.sub(/eabi(hf)?\Z/, "")
        without_abi.empty? ? nil : without_abi
      end

      private def musl_candidate(prefix : String) : String
        "#{prefix}#{version}"
      end

      # `Gem::Platform.platform_specificity_match`: how well a spec platform
      # matches the user platform; lower is better.
      def self.platform_specificity_match(spec_platform : Platform, user_platform : Platform) : Int32
        return -1 if spec_platform == user_platform
        return 1_000_000 if spec_platform.ruby? || user_platform.ruby?

        os_match(spec_platform, user_platform) +
          cpu_match(spec_platform, user_platform) * 10 +
          version_match(spec_platform, user_platform) * 100
      end

      private def self.os_match(spec : Platform, user : Platform) : Int32
        spec.os == user.os ? 0 : 1
      end

      private def self.cpu_match(spec : Platform, user : Platform) : Int32
        return 0 if spec.cpu == user.cpu
        return 0 if spec.cpu == "arm" && user.cpu.to_s.starts_with?("arm")
        return 1 if spec.cpu.nil? || spec.cpu == "universal"

        2
      end

      private def self.version_match(spec : Platform, user : Platform) : Int32
        return 0 if spec.version == user.version
        return 1 if spec.version.nil?

        2
      end

      # Deterministic total order for Celerite-internal sorting: the ruby
      # platform first, then by string form. (Not a RubyGems contract; RubyGems
      # sorts via platform_specificity_match instead.)
      def <=>(other : Platform) : Int32
        return 0 if self == other
        return -1 if ruby?
        return 1 if other.ruby?

        to_s <=> other.to_s
      end
    end
  end
end
