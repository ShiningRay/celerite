require "digest"
require "json"
require "random/secure"

module Celerite
  # Content identities are deliberately path-free.  Absolute locators are used
  # only during selection and are never included in a persisted identity.
  module CacheIdentity
    extend self

    SHA256      = /\A[0-9a-f]{64}\z/
    NONCE       = /\A[0-9a-f]{32}\z/
    UNKNOWN     = "unknown"
    CERTIFICATE = "celerite-success-certificate/1"

    def parse_error(message : String) : JSON::ParseException
      JSON::ParseException.new(message, 0, 0)
    end

    def nonce : String
      Random::Secure.hex(16)
    end

    def sha256(value : String) : String
      Digest::SHA256.hexdigest(value)
    end

    def valid_nonce?(value : String?) : Bool
      !value.nil? && NONCE.matches?(value)
    end

    def valid_sha256?(value : String?) : Bool
      !value.nil? && SHA256.matches?(value)
    end

    def exact_keys?(object : JSON::Any, keys : Array(String)) : Bool
      object.as_h?.try(&.keys.all? { |key| keys.includes?(key) }) == true
    end

    def required_keys?(object : JSON::Any, keys : Array(String)) : Bool
      object.as_h?.try do |values|
        keys.all? { |key| values[key]?.try { |value| !value.raw.nil? } == true }
      end == true
    end

    def nullable(object : JSON::Any, key : String, &block : JSON::Any -> T) : T? forall T
      value = object[key]?
      return nil if value.nil? || value.raw.nil?
      yield value
    end

    def string(object : JSON::Any, key : String, nonempty : Bool = true) : String
      value = object[key].as_s? || raise CacheIdentity.parse_error("#{key} must be a string")
      raise CacheIdentity.parse_error("#{key} must not be empty") if nonempty && value.empty?
      value
    end

    def sha256_field(object : JSON::Any, key : String) : String
      value = string(object, key)
      raise CacheIdentity.parse_error("#{key} must be a SHA-256") unless SHA256.matches?(value)
      value
    end

    def nonce_field(object : JSON::Any, key : String) : String
      value = string(object, key)
      raise CacheIdentity.parse_error("#{key} must be a nonce") unless NONCE.matches?(value)
      value
    end

    class LockIdentity
      include JSON::Serializable

      property slot : String
      property sha256 : String
      property byte_size : Int64
      property line_ending : String
      property parser_revision : String
      property bundled_with : String
      property checksums_sha256 : String
      property platforms : Array(String)

      KEYS = %w[slot sha256 byte_size line_ending parser_revision bundled_with checksums_sha256 platforms]

      def initialize(@slot, @sha256, @byte_size, @line_ending,
                     @parser_revision, @bundled_with, @checksums_sha256, @platforms)
      end

      def self.parse(object : JSON::Any) : self
        raise CacheIdentity.parse_error("lock identity has unknown fields") unless CacheIdentity.exact_keys?(object, KEYS)
        identity = new(
          CacheIdentity.string(object, "slot"),
          CacheIdentity.sha256_field(object, "sha256"),
          (object["byte_size"].as_i64? || raise CacheIdentity.parse_error("byte_size must be an integer")),
          CacheIdentity.string(object, "line_ending"),
          CacheIdentity.string(object, "parser_revision"),
          CacheIdentity.string(object, "bundled_with"),
          CacheIdentity.sha256_field(object, "checksums_sha256"),
          Array(String).from_json(object["platforms"].to_json),
        )
        identity.validate
        identity
      end

      def self.from_json(string : String) : self
        parse(JSON.parse(string))
      end

      def validate : Nil
        raise CacheIdentity.parse_error("lock sha256 must be a SHA-256") unless CacheIdentity.valid_sha256?(sha256)
        raise CacheIdentity.parse_error("lock checksum must be a SHA-256") unless CacheIdentity.valid_sha256?(checksums_sha256)
        raise CacheIdentity.parse_error("byte_size must be non-negative") if byte_size < 0
        raise CacheIdentity.parse_error("platforms must not be empty") if platforms.empty?
        raise CacheIdentity.parse_error("platforms must be non-empty strings") unless platforms.all? { |p| !p.strip.empty? }
        raise CacheIdentity.parse_error("line_ending must be lf or crlf") unless %w[lf crlf].includes?(line_ending)
      end
    end

    class PluginCertificate
      include JSON::Serializable

      property certificate_nonce : String
      property roots_digest : String
      property index_digest : String

      KEYS = %w[certificate_nonce roots_digest index_digest]

      def initialize(@certificate_nonce, @roots_digest, @index_digest)
      end

      def self.parse(object : JSON::Any) : self
        raise CacheIdentity.parse_error("plugin certificate has unknown fields") unless CacheIdentity.exact_keys?(object, KEYS)
        certificate = new(
          CacheIdentity.nonce_field(object, "certificate_nonce"),
          CacheIdentity.sha256_field(object, "roots_digest"),
          CacheIdentity.sha256_field(object, "index_digest"),
        )
        certificate
      end

      def self.from_json(string : String) : self
        parse(JSON.parse(string))
      end
    end

    class InstallCertificate
      include JSON::Serializable

      property plan_digest : String

      KEYS = %w[plan_digest]

      def initialize(@plan_digest)
      end

      def self.parse(object : JSON::Any) : self
        raise CacheIdentity.parse_error("install certificate has unknown fields") unless CacheIdentity.exact_keys?(object, KEYS)
        new(CacheIdentity.sha256_field(object, "plan_digest"))
      end

      def self.from_json(string : String) : self
        parse(JSON.parse(string))
      end
    end

    class SuccessCertificate
      include JSON::Serializable

      property format : String
      property command : String
      property profile : String
      property ruby_identity : String
      property lock : LockIdentity
      property plugin : PluginCertificate?
      property install : InstallCertificate?

      KEYS         = %w[format command profile ruby_identity lock plugin install]
      REQUIRED     = %w[format command profile ruby_identity lock]
      COMMANDS     = %w[lock install]
      LINE_ENDINGS = %w[lf crlf]

      def initialize(@format, @command, @profile, @ruby_identity, @lock,
                     @plugin = nil, @install = nil)
      end

      def self.parse(object : JSON::Any) : self
        raise CacheIdentity.parse_error("certificate has unknown fields") unless CacheIdentity.exact_keys?(object, KEYS)
        raise CacheIdentity.parse_error("certificate is missing fields") unless CacheIdentity.required_keys?(object, REQUIRED)
        certificate = new(
          CacheIdentity.string(object, "format"),
          CacheIdentity.string(object, "command"),
          CacheIdentity.string(object, "profile"),
          CacheIdentity.sha256_field(object, "ruby_identity"),
          LockIdentity.parse(object["lock"]),
          CacheIdentity.nullable(object, "plugin") { |value| PluginCertificate.parse(value) },
          CacheIdentity.nullable(object, "install") { |value| InstallCertificate.parse(value) },
        )
        certificate.validate
        certificate
      end

      def self.from_json(string : String) : self
        parse(JSON.parse(string))
      end

      def validate : Nil
        raise CacheIdentity.parse_error("unsupported certificate format") unless format == CERTIFICATE
        raise CacheIdentity.parse_error("unsupported certificate command") unless COMMANDS.includes?(command)
        raise CacheIdentity.parse_error("profile must not be empty") if profile.strip.empty?
        lock.validate
        if command == "lock" && !install.nil?
          raise CacheIdentity.parse_error("lock certificate must not contain install binding")
        end
        if command == "install" && install.nil?
          raise CacheIdentity.parse_error("install certificate must contain install binding")
        end
      end
    end

    # Runtime selection and proof that the bytes belong to an ordinary Ruby
    # installation.  No subprocess is ever started here.
    class RubyIdentity
      include JSON::Serializable

      property state : String
      property relative_locator : String?
      property selection_kind : String?
      property size : Int64?
      property mtime_seconds : Int64?
      property mtime_ns : Int32?
      property precision : String?
      property file_sha256 : String?
      property identity_digest : String?

      @[JSON::Field(ignore: true)]
      getter canonical_path : String? = nil

      @[JSON::Field(ignore: true)]
      getter rbconfig_path : String? = nil

      KEYS = %w[state relative_locator selection_kind size mtime_seconds mtime_ns precision file_sha256 identity_digest]

      def initialize(@state, @relative_locator = nil, @selection_kind = nil,
                     @size = nil, @mtime_seconds = nil, @mtime_ns = nil,
                     @precision = nil, @file_sha256 = nil, @identity_digest = nil,
                     canonical_path = nil, rbconfig_path = nil)
        @canonical_path = canonical_path
        @rbconfig_path = rbconfig_path
      end

      def self.unknown : self
        new(UNKNOWN)
      end

      def known? : Bool
        state == "known" && complete? && valid_digest?
      end

      def complete? : Bool
        !relative_locator.nil? && !selection_kind.nil? && !size.nil? &&
          !mtime_seconds.nil? && !mtime_ns.nil? && !precision.nil? &&
          !file_sha256.nil? && !identity_digest.nil?
      end

      def digest_material : String
        raise "Unknown RubyIdentity has no digest material" unless complete?
        String.build do |io|
          io << "celerite/ruby-identity/1\0"
          io << selection_kind << '\0'
          io << relative_locator << "\0"
          io << size << "\0"
          io << mtime_seconds << "\0"
          io << mtime_ns << "\0"
          io << precision << "\0"
          io << file_sha256
        end
      end

      def valid_digest? : Bool
        complete? && identity_digest == CacheIdentity.sha256(digest_material)
      end

      def self.parse(object : JSON::Any) : self
        raise CacheIdentity.parse_error("Ruby identity has unknown fields") unless CacheIdentity.exact_keys?(object, KEYS)
        state = CacheIdentity.string(object, "state")
        raise CacheIdentity.parse_error("unsupported Ruby identity state") unless %w[known unknown].includes?(state)
        identity = new(
          state,
          CacheIdentity.nullable(object, "relative_locator", &.as_s?),
          CacheIdentity.nullable(object, "selection_kind", &.as_s?),
          CacheIdentity.nullable(object, "size", &.as_i64?),
          CacheIdentity.nullable(object, "mtime_seconds", &.as_i64?),
          CacheIdentity.nullable(object, "mtime_ns", &.as_i?.try { |value| value.to_i32 if value >= 0 && value < 1_000_000_000 }),
          CacheIdentity.nullable(object, "precision", &.as_s?),
          CacheIdentity.nullable(object, "file_sha256", &.as_s?),
          CacheIdentity.nullable(object, "identity_digest", &.as_s?),
        )
        identity.validate
        identity
      end

      def self.from_json(string : String) : self
        parse(JSON.parse(string))
      end

      def validate : Nil
        if state == "unknown"
          fields = [relative_locator, selection_kind, size, mtime_seconds, mtime_ns,
                    precision, file_sha256, identity_digest]
          raise CacheIdentity.parse_error("Unknown Ruby identity must not contain facts") unless fields.all?(&.nil?)
          return
        end
        raise CacheIdentity.parse_error("known Ruby identity is incomplete") unless complete?
        raise CacheIdentity.parse_error("invalid Ruby selection kind") unless %w[explicit path].includes?(selection_kind.to_s)
        raise CacheIdentity.parse_error("invalid relative locator") unless relative_locator.to_s.matches?(/\Abin\/ruby(?:\.exe)?\z/)
        raise CacheIdentity.parse_error("invalid file SHA-256") unless CacheIdentity.valid_sha256?(file_sha256)
        raise CacheIdentity.parse_error("invalid identity SHA-256") unless CacheIdentity.valid_sha256?(identity_digest)
        raise CacheIdentity.parse_error("invalid mtime precision") unless %w[ns second].includes?(precision.to_s)
        ns = mtime_ns
        raise CacheIdentity.parse_error("invalid mtime nanoseconds") if ns.nil? || !(0...1_000_000_000).covers?(ns)
        raise CacheIdentity.parse_error("invalid identity digest") unless valid_digest?
      end

      def self.resolve_candidate(explicit : String?) : String?
        if !explicit.nil?
          return nil if explicit.empty?
          return explicit
        end
        selected = ENV["CELERITE_RUBY"]?
        return selected if !selected.nil? && !selected.empty?
        return find_on_path
      end

      def self.find_on_path : String?
        path = ENV["PATH"]?
        return nil if path.nil? || path.empty?
        windows = {% if flag?(:win32) %} true {% else %} false {% end %}
        separator = windows ? ';' : ':'
        candidates = windows ? %w[ruby.exe ruby] : %w[ruby]
        path.split(separator).each do |directory|
          next if directory.empty?
          candidates.each do |name|
            candidate = File.join(directory, name)
            return candidate if File.exists?(candidate) || File.symlink?(candidate)
          end
        end
        nil
      rescue
        nil
      end

      def self.detect(explicit : String? = nil) : self
        candidate = resolve_candidate(explicit)
        return unknown if candidate.nil?
        # Crystal's Windows glob does not normalize mixed separators returned by realpath.
        canonical = File.realpath(candidate).tr("\\", "/")
        return unknown unless File.file?(canonical)
        root = File.dirname(File.dirname(canonical))
        return unknown unless File.basename(File.dirname(canonical)).downcase == "bin"
        windows = {% if flag?(:win32) %} true {% else %} false {% end %}
        expected = windows ? "ruby.exe" : "ruby"
        return unknown unless File.basename(canonical).downcase == expected
        locator = "bin/#{File.basename(canonical).downcase}"
        return unknown unless locator.matches?(/\Abin\/ruby(?:\.exe)?\z/)
        # Enumerate directories instead of Dir.glob: Crystal's Windows glob does
        # not match absolute drive-letter patterns consistently.
        ruby_lib = File.join(root, "lib", "ruby")
        return unknown unless File.directory?(ruby_lib)
        rbconfigs = [] of String
        Dir.children(ruby_lib).sort.each do |version|
          version_dir = File.join(ruby_lib, version)
          next unless File.directory?(version_dir)
          Dir.children(version_dir).sort.each do |arch|
            candidate = File.join(version_dir, arch, "rbconfig.rb")
            rbconfigs << candidate if File.file?(candidate)
          end
        end
        return unknown unless rbconfigs.size == 1
        rbconfig = rbconfigs[0]
        # Prove that this is a readable rbconfig, not merely a matching name.
        _rbconfig_bytes = File.read(rbconfig)
        bytes = File.read(canonical)
        info = File.info(canonical)
        total_ns = info.modification_time.to_unix_ns
        seconds = (total_ns // 1_000_000_000).to_i64
        ns = (total_ns % 1_000_000_000).to_i32
        precision = ns == 0 ? "second" : "ns"
        sha = CacheIdentity.sha256(bytes)
        # PATH selection is the only persisted alternative to explicit.
        env_ruby = ENV["CELERITE_RUBY"]?
        kind = (!explicit.nil? || (!env_ruby.nil? && !env_ruby.empty?)) ? "explicit" : "path"
        digest = CacheIdentity.sha256(
          "celerite/ruby-identity/1\0#{kind}\0#{locator}\0#{bytes.size}\0#{seconds}\0#{ns}\0#{precision}\0#{sha}",
        )
        new("known", locator, kind, bytes.size.to_i64, seconds, ns, precision,
          sha, digest, canonical, rbconfig)
      rescue
        unknown
      end
    end
  end
end
