require "digest/sha256"
require "json"
require "random/secure"

require "./cache_identity"
require "./config"

module Celerite
  # Persistent evaluations are not command-success proofs.  Layout v2 adds a
  # nonce-keyed certificate map; legacy v1 remains readable only for evaluation
  # replay and can never satisfy a command certificate lookup.
  module EvalCacheStore
    FORMAT         = "celerite-eval-cache/2"
    LEGACY_FORMAT  = "celerite-eval-cache/1"
    LAYOUT         = "v2"
    LEGACY_LAYOUT  = "v1"
    SWITCH         = "CELERITE_EVAL_CACHE"
    ROOT_ENV       = "CELERITE_CACHE_DIR"
    ENTRY_NAME     = "entry.json"
    MAX_ENTRIES    = 128
    MAX_BYTES      = 8_i64 * 1024 * 1024
    DIRECTORY      = ".celerite"
    CREDENTIAL_URI = %r{://[^/"\\\s]+@}
    DIGEST         = /\A[0-9a-f]{64}\z/
    NAMESPACE      = /\A[0-9a-f]{16}\z/
    ENTRY_KEYS     = %w[format digest evaluation certificates]

    alias Identity = CacheIdentity

    record EntryFile, digest : String, path : String, json : JSON::Any do
      def format : String
        json["format"].as_s
      end

      def evaluation_only? : Bool
        format == LEGACY_FORMAT
      end

      def certificate(nonce : String) : Identity::SuccessCertificate?
        return nil if format != FORMAT || !Identity.valid_nonce?(nonce)
        object = json["certificates"]?.try(&.as_h?).try(&.[nonce]?)
        object ? Identity::SuccessCertificate.parse(object) : nil
      rescue
        nil
      end
    end

    def self.enabled? : Bool
      ENV[SWITCH]? == "1"
    end

    def self.root : String?
      if override = ENV[ROOT_ENV]?
        return nil if override.empty?
        return File.expand_path(override)
      end
      home = Config.user_home
      return nil if home.nil? || home.empty?
      File.expand_path(File.join(home, DIRECTORY, "cache", "eval"))
    end

    def self.namespace : String
      material = ENV.to_h.to_a
        .select { |(key, value)| credential?(key, value) }
        .sort_by { |(key, _)| key }
        .map { |(key, value)| "#{key}=#{value}" }
        .join("\u0001")
      Digest::SHA256.hexdigest(material)[0, 16]
    end

    def self.credential?(key : String, value : String) : Bool
      return false unless key.starts_with?("BUNDLE_")
      key.includes?("__") || value.matches?(CREDENTIAL_URI)
    end

    def self.namespace_dir : String?
      base = root
      base ? File.join(base, namespace, LAYOUT) : nil
    end

    def self.legacy_namespace_dir : String?
      base = root
      base ? File.join(base, namespace, LEGACY_LAYOUT) : nil
    end

    def self.entry_path(digest : String) : String?
      dir = namespace_dir
      return nil if dir.nil? || !digest.matches?(DIGEST)
      File.join(dir, digest, ENTRY_NAME)
    end

    def self.legacy_entry_path(digest : String) : String?
      dir = legacy_namespace_dir
      return nil if dir.nil? || !digest.matches?(DIGEST)
      File.join(dir, digest, ENTRY_NAME)
    end

    def self.persistable?(payload : String) : Bool
      !payload.matches?(CREDENTIAL_URI)
    end

    # New evaluations get an empty certificate map.  Existing certificates are
    # retained when the same evaluation is refreshed.  Legacy input is written
    # only to v1; it is never silently upgraded into a command-capable entry.
    def self.write(digest : String, payload : String) : Bool
      return false unless persistable?(payload)
      object = JSON.parse(payload)
      format = object["format"]?.try(&.as_s?)
      target = case format
               when LEGACY_FORMAT then legacy_entry_path(digest)
               when FORMAT        then entry_path(digest)
               else                    return false
               end
      return false if target.nil?
      legacy = format == LEGACY_FORMAT
      # The unchanged bridge client still emits /2 without a certificate map.
      # Normalize that evaluation-only shape before the strict /2 validation;
      # legacy /1 is never upgraded.
      validate_evaluation!(object, digest, legacy, !legacy)
      if format == FORMAT
        certificates = existing_certificates(digest)
        if object.as_h.has_key?("certificates")
          supplied = object["certificates"].as_h? || raise Identity.parse_error("certificates must be an object")
          supplied.each { |nonce, value| certificates[nonce] = value }
        end
        object = JSON::Any.new(object.as_h.merge({"certificates" => JSON.parse(certificates.to_json)}))
        validate_entry!(object, digest)
        payload = object.to_json
      end
      atomic_write(target, payload)
    rescue JSON::ParseException
      false
    rescue TypeCastError
      false
    rescue IO::Error
      false
    end

    # Transactional per-nonce commit.  Validation and serialization complete
    # before the rename, so any failure leaves the prior nonce untouched.
    def self.put_certificate(digest : String, nonce : String,
                             certificate : Identity::SuccessCertificate) : Bool
      return false unless Identity.valid_nonce?(nonce)
      target = entry_path(digest)
      return false if target.nil? || !File.file?(target)
      object = JSON.parse(File.read(target))
      validate_entry!(object, digest)
      certificate.validate
      certificates = Hash(String, JSON::Any).from_json(object["certificates"].to_json)
      certificates[nonce] = JSON.parse(certificate.to_json)
      object = JSON::Any.new(object.as_h.merge({"certificates" => JSON.parse(certificates.to_json)}))
      validate_certificates!(object)
      atomic_write(target, object.to_json)
    rescue
      false
    end

    def self.certificate(digest : String, nonce : String) : Identity::SuccessCertificate?
      target = entry_path(digest)
      return nil if target.nil? || !Identity.valid_nonce?(nonce) || !File.file?(target)
      object = JSON.parse(File.read(target))
      validate_entry!(object, digest)
      value = object["certificates"][nonce]?
      value ? Identity::SuccessCertificate.parse(value) : nil
    rescue
      nil
    end

    def self.read_all : Array(EntryFile)
      entries = [] of EntryFile
      [{namespace_dir, false}, {legacy_namespace_dir, true}].each do |item|
        dir, legacy = item
        next if dir.nil? || !Dir.exists?(dir)
        Dir.each_child(dir) do |child|
          next unless child.matches?(DIGEST)
          path = File.join(dir, child, ENTRY_NAME)
          next unless File.file?(path)
          entry = parse(path, child, legacy)
          if entry
            entries << entry
          else
            discard(path)
          end
        end
      end
      entries.sort_by! { |entry| -File.info(entry.path).modification_time.to_unix_ms }
      entries
    rescue
      [] of EntryFile
    end

    def self.delete(digest : String) : Nil
      [entry_path(digest), legacy_entry_path(digest)].compact.each { |path| discard(path) }
    end

    def self.prune(base : String? = nil, max_entries : Int32 = MAX_ENTRIES,
                   max_bytes : Int64 = MAX_BYTES) : Nil
      root_dir = base || root
      return if root_dir.nil? || !Dir.exists?(root_dir)
      files = [] of NamedTuple(path: String, size: Int64, mtime: Time)
      Dir.each_child(root_dir) do |namespace|
        next unless namespace.matches?(NAMESPACE)
        [LAYOUT, LEGACY_LAYOUT].each do |layout_name|
          layout = File.join(root_dir, namespace, layout_name)
          next unless Dir.exists?(layout)
          Dir.each_child(layout) do |digest|
            next unless digest.matches?(DIGEST)
            path = File.join(layout, digest, ENTRY_NAME)
            next unless File.file?(path)
            info = File.info(path)
            files << {path: path, size: info.size, mtime: info.modification_time}
          end
        end
      end
      files.sort_by! { |file| file[:mtime] }
      total = files.sum { |file| file[:size] }
      while files.size > max_entries || total > max_bytes
        oldest = files.shift
        begin
          File.delete(oldest[:path])
          parent = File.dirname(oldest[:path])
          Dir.delete(parent) if Dir.children(parent).empty?
        rescue IO::Error
          # GC is best effort; a failed eviction must never fail a command.
        end
        total -= oldest[:size]
      end
    rescue
      # GC must never fail a command.
    end

    private def self.validate_evaluation!(object : JSON::Any, digest : String, legacy : Bool,
                                          allow_missing_certificates : Bool = false) : Nil
      # v2 retains the evaluation proof fields used by the bridge client and
      # adds certificates. Optional proof metadata never substitutes for the
      # required format/digest/evaluation/certificates fields.
      allowed = legacy ? %w[format digest evaluation env fingerprint gemspecs] : ENTRY_KEYS + %w[env fingerprint gemspecs]
      required = legacy ? %w[format digest evaluation] : (allow_missing_certificates ? %w[format digest evaluation] : ENTRY_KEYS)
      raise Identity.parse_error("evaluation entry has invalid fields") unless Identity.exact_keys?(object, allowed) && Identity.required_keys?(object, required)
      raise Identity.parse_error("evaluation format mismatch") unless Identity.string(object, "format") == (legacy ? LEGACY_FORMAT : FORMAT)
      raise Identity.parse_error("evaluation digest mismatch") unless Identity.string(object, "digest") == digest
      raise Identity.parse_error("evaluation must be an object") unless object["evaluation"].as_h?
      unless legacy
        validate_certificates!(object) if !allow_missing_certificates || object.as_h.has_key?("certificates")
      end
    end

    private def self.validate_entry!(object : JSON::Any, digest : String) : Nil
      validate_evaluation!(object, digest, false)
      raise Identity.parse_error("certificates must be an object") unless object["certificates"].as_h?
    end

    private def self.validate_certificates!(object : JSON::Any) : Nil
      certificates = object["certificates"]?.try(&.as_h?)
      raise Identity.parse_error("certificates must be an object") unless certificates
      certificates.each do |nonce, value|
        raise Identity.parse_error("invalid certificate nonce") unless Identity.valid_nonce?(nonce)
        Identity::SuccessCertificate.parse(value)
      end
    end

    private def self.existing_certificates(digest : String) : Hash(String, JSON::Any)
      target = entry_path(digest)
      return {} of String => JSON::Any if target.nil? || !File.file?(target)
      object = JSON.parse(File.read(target))
      validate_entry!(object, digest)
      Hash(String, JSON::Any).from_json(object["certificates"].to_json)
    end

    private def self.atomic_write(target : String, payload : String) : Bool
      dir = File.dirname(target)
      temp = File.join(dir, ".entry-#{Process.pid}-#{Random::Secure.hex(8)}.tmp")
      begin
        Dir.mkdir_p(dir)
        File.open(temp, "w") do |file|
          file.print(payload)
          file.flush
          file.fsync
        end
        # MoveFileExW(REPLACE_EXISTING) is supported by Crystal on Windows.  Do
        # not delete the old certificate before this atomic replacement.
        File.rename(temp, target)
        true
      rescue
        begin
          File.delete(temp) if File.exists?(temp)
        rescue IO::Error
          # Nothing else to clean up.
        end
        false
      end
    end

    private def self.parse(path : String, digest : String, legacy : Bool) : EntryFile?
      object = JSON.parse(File.read(path))
      validate_evaluation!(object, digest, legacy)
      EntryFile.new(digest, path, object)
    rescue
      nil
    end

    private def self.discard(path : String) : Nil
      File.delete(path) if File.exists?(path)
      parent = File.dirname(path)
      Dir.delete(parent) if Dir.exists?(parent) && Dir.children(parent).empty?
    rescue
    end
  end
end
