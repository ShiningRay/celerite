require "json"
require "digest/sha256"
require "random/secure"
require "time"
require "./checksum"
require "./config"
require "./fast_path_store"
require "./lockfile/model"
require "uri"

# Opt-in persistent cache for parsed/install plans. P1 supplies canonical keys
# and read-only validation; P2 adds a fail-closed writer and namespace-local
# pruning. There is still no command integration: callers must opt in and no
# result is used to change resolution or installation behaviour.
module Celerite::PlanCache
  FORMAT       = "celerite-plan-cache/1"
  LAYOUT       = "plan/v1"
  SWITCH       = "CELERITE_PLAN_CACHE"
  DEBUG_SWITCH = "CELERITE_PLAN_CACHE_DEBUG"
  ROOT_ENV     = "CELERITE_CACHE_DIR"
  MAX_ENTRIES  = 256
  MAX_BYTES    = 16_i64 * 1024 * 1024

  DIGEST         = /\A[0-9a-f]{64}\z/
  NAMESPACE      = /\A[0-9a-f]{16}\z/
  REVISION       = /\A[0-9a-fA-F]{40}\z/
  ENTRY_FILE     = /\A[0-9a-f]{64}\.json\z/
  CREDENTIAL_URI = %r{://[^/"\\\s]+@}
  SENSITIVE_KEY  = /\A(?:api[_-]?key|authorization|credential|credentials|password|passwd|secret|token)\z/i
  PAYLOAD_KEYS   = %w[installed_snapshot plan specs]

  @@debug_io : IO = STDERR

  def self.debug_io : IO
    @@debug_io
  end

  def self.debug_io=(io : IO) : IO
    @@debug_io = io
  end

  enum Status
    Hit
    Miss
    Unknown
    Corrupt
  end

  enum WriteStatus
    Written
    Disabled
    InvalidKey
    InvalidComponents
    InvalidNamespace
    InvalidPayload
    InvalidDigest
    NonPortablePayload
    CredentialPayload
    TooLarge
    RootUnavailable
    IoError
  end

  struct ReadResult
    getter status : Status
    getter reason : String
    getter payload : JSON::Any?

    def initialize(@status : Status, @reason : String, @payload : JSON::Any? = nil)
    end

    def hit? : Bool
      @status.hit?
    end

    def miss? : Bool
      @status.miss?
    end

    def unknown? : Bool
      @status.unknown?
    end

    def corrupt? : Bool
      @status.corrupt?
    end
  end

  struct WriteResult
    getter status : WriteStatus
    getter reason : String

    def initialize(@status : WriteStatus, @reason : String)
    end

    def written? : Bool
      @status.written?
    end
  end

  def self.enabled? : Bool
    ENV[SWITCH]? == "1"
  end

  def self.debug? : Bool
    ENV[DEBUG_SWITCH]? == "1"
  end

  def self.root : String?
    override = ENV[ROOT_ENV]?
    return File.expand_path(override) if override && !override.empty?
    home = Config.user_home
    home ? File.join(home, ".celerite", "cache") : nil
  end

  # Same credential-bearing BUNDLE_* selection as EvalCacheStore. Only the
  # resulting 16-hex namespace is exposed in keys or on disk.
  def self.credential?(key : String, value : String) : Bool
    key.starts_with?("BUNDLE_") && (key.includes?("__") || value.matches?(%r{://[^/"\\\s]+@}))
  end

  def self.namespace : String
    pairs = ENV.to_h.to_a.select { |key, value| credential?(key, value) }
    material = pairs.sort_by(&.first).map { |key, value| "#{key}=#{value}" }.join("\u0001")
    Digest::SHA256.hexdigest(material)[0, 16]
  end

  def self.namespace_dir : String?
    base = root
    base ? File.join(base, LAYOUT, namespace) : nil
  end

  def self.entry_path(key : String) : String?
    return nil unless key.matches?(DIGEST)
    dir = namespace_dir
    dir ? File.join(dir, "#{key}.json") : nil
  end

  # Stable JSON: object keys sorted lexically, array order retained, no
  # whitespace, UTF-8 strings emitted by JSON's canonical escaping rules.
  def self.canonical_json(value : JSON::Any) : String
    case raw = value.raw
    when Hash(String, JSON::Any)
      "{" + raw.keys.sort.map do |name|
        "#{name.to_json}:#{canonical_json(raw[name])}"
      end.join(",") + "}"
    when Array(JSON::Any)
      "[" + raw.map { |item| canonical_json(item) }.join(",") + "]"
    when String
      raw.to_json
    when Bool, Nil, Int64, Int32, Int16, Int8, UInt64, UInt32, UInt16, UInt8, Float64
      raw.to_json
    else
      raise ArgumentError.new("unsupported JSON value")
    end
  end

  def self.valid_key?(key : String) : Bool
    key.matches?(DIGEST)
  end

  # Pure canonicalization for a complete six-component object. It never
  # substitutes a wildcard or a best-effort value for an unknown component.
  def self.key_for(components : JSON::Any) : String?
    return nil unless valid_components?(components)
    Digest::SHA256.hexdigest(canonical_json(components))
  end

  def self.build_key(sources : JSON::Any, checksums : JSON::Any, platform : JSON::Any,
                     abi : JSON::Any, build : JSON::Any,
                     credential_namespace : String? = nil) : String?
    ns = credential_namespace || namespace
    return nil unless ns.matches?(NAMESPACE)
    object = JSON::Any.new({
      "sources"              => sources,
      "credential_namespace" => JSON::Any.new(ns),
      "checksums"            => checksums,
      "platform"             => platform,
      "abi"                  => abi,
      "build"                => build,
    })
    key_for(object)
  end

  def self.components_for(primary_remote : String?, lockfile : Lockfile::Data,
                          project_root : String, local_platform : String?,
                          abi : FastPathStore::Abi, config : Config) : JSON::Any?
    return nil if !lockfile.valid? || primary_remote.nil? || primary_remote.empty?
    return nil if local_platform.nil? || local_platform.empty?
    return nil unless abi.complete?

    sources = [] of JSON::Any
    primary = normalize_source("GEM", primary_remote, project_root: project_root)
    return nil unless primary
    sources << primary

    lockfile.sources.each do |section|
      section_remote = section.remote
      next if section.type == "GEM" && (!section_remote || section_remote.empty?)
      remote = section_remote || option_string(section, "remote")
      next if remote.nil? && section.type == "GEM"
      identity = normalize_source(
        section.type,
        remote || "",
        revision: option_string(section, "revision") || option_string(section, "ref"),
        submodules: option_bool(section, "submodules"),
        glob: option_string(section, "glob"),
        plugin_type: option_string(section, "type"),
        project_root: project_root
      )
      return nil unless identity
      sources << identity
    end
    sources.sort_by! { |source| canonical_json(source) }
    sources.uniq!

    locked_platforms = lockfile.platforms
    return nil if locked_platforms.empty?

    checksums = [] of JSON::Any
    lockfile.specs.each do |spec|
      platform = spec.platform || "ruby"
      entry = lockfile.checksums.find do |candidate|
        candidate.name == spec.name && candidate.version == spec.version &&
          (candidate.platform || "ruby") == platform
      end
      return nil unless entry
      normalized = entry.checksums.compact_map do |raw|
        Checksum.normalize_hex(raw)
      end
      return nil if normalized.empty? || normalized.size != entry.checksums.size
      checksums << JSON::Any.new({
        "name"      => JSON::Any.new(spec.name),
        "version"   => JSON::Any.new(spec.version),
        "platform"  => JSON::Any.new(platform),
        "checksums" => JSON::Any.new(normalized.sort.uniq.map { |v| JSON::Any.new(v) }),
      })
    end
    checksums.sort_by! { |entry| canonical_json(entry) }

    force = config["force_ruby_platform"]
    return nil unless force.nil? || force.is_a?(Bool)

    build = {} of String => JSON::Any
    lockfile.specs.each do |spec|
      args = build_args(config, spec.name)
      return nil unless args
      build[spec.name] = JSON::Any.new(args.map { |v| JSON::Any.new(v) })
    end

    platform = JSON::Any.new({
      "local"               => JSON::Any.new(local_platform),
      "locked"              => JSON::Any.new(locked_platforms.sort.uniq.map { |v| JSON::Any.new(v) }),
      "force_ruby_platform" => JSON::Any.new(force == true),
    })
    abi_value = JSON::Any.new({
      "ruby_api_version"      => JSON::Any.new(abi.ruby_api_version),
      "extension_api_version" => JSON::Any.new(abi.extension_api_version),
      "rbconfig_ruby_version" => JSON::Any.new(abi.rbconfig_ruby_version),
    })
    key = build_key(JSON::Any.new(sources), JSON::Any.new(checksums), platform,
      abi_value, JSON::Any.new(build))
    return nil unless key
    JSON.parse(canonical_json(JSON::Any.new({
      "sources"              => JSON::Any.new(sources),
      "credential_namespace" => JSON::Any.new(namespace),
      "checksums"            => JSON::Any.new(checksums),
      "platform"             => platform,
      "abi"                  => abi_value,
      "build"                => JSON::Any.new(build),
    })))
  end

  # Normalize one source identity. URI credentials are discarded before any
  # key material is returned; malformed or incomplete identities are unknown.
  def self.normalize_source(type : String, remote : String, revision : String? = nil,
                            submodules : Bool? = nil, glob : String? = nil,
                            plugin_type : String? = nil,
                            project_root : String = Dir.current) : JSON::Any?
    case type
    when "GEM"
      value = normalize_uri(remote)
      return nil unless value
      JSON::Any.new({"type" => JSON::Any.new("gem"), "remote" => JSON::Any.new(value)})
    when "PATH"
      return nil if remote.empty?
      path = File.expand_path(remote, project_root).gsub('\\', '/')
      path += "/" unless path.ends_with?("/")
      JSON::Any.new({"type" => JSON::Any.new("path"), "remote" => JSON::Any.new(path)})
    when "GIT"
      return nil unless revision && revision.matches?(REVISION)
      value = normalize_uri(remote)
      return nil unless value
      JSON::Any.new({
        "type"       => JSON::Any.new("git"),
        "remote"     => JSON::Any.new(value),
        "revision"   => JSON::Any.new(revision.downcase),
        "submodules" => JSON::Any.new(submodules == true),
        "glob"       => JSON::Any.new(glob || "*"),
      })
    else
      return nil if plugin_type.nil? || plugin_type.empty?
      JSON::Any.new({"type" => JSON::Any.new(type), "plugin_type" => JSON::Any.new(plugin_type)})
    end
  end

  def self.normalize_uri(raw : String) : String?
    return nil if raw.empty?
    uri = URI.parse(raw)
    scheme = uri.scheme
    return nil unless scheme && !scheme.empty?
    host = uri.host
    return nil unless host && !host.empty?
    return nil unless uri.query.nil? && uri.fragment.nil?
    uri.scheme = scheme.downcase
    uri.host = host.downcase
    uri.user = nil
    uri.password = nil
    path = (uri.path || "").rstrip("/")
    uri.path = path
    uri.to_s
  rescue URI::Error
    nil
  end

  def self.read(key : String?) : ReadResult
    return result(Status::Unknown, "invalid_key") unless key && valid_key?(key)
    return result(Status::Miss, "disabled") unless enabled?
    path = entry_path(key)
    return result(Status::Unknown, "root_unavailable") unless path

    begin
      info = File.info(path)
      return corrupt(path, "too_large") if info.size > MAX_BYTES
      text = File.read(path)
      entry = JSON.parse(text).as_h
      return corrupt(path, "format") unless entry["format"]?.try(&.as_s?) == FORMAT

      components = entry["key"]?
      return corrupt(path, "key_missing") unless components
      recomputed = key_for(components)
      return corrupt(path, "key_invalid") unless recomputed
      return corrupt(path, "key_mismatch") unless recomputed == key
      embedded_ns = components.as_h["credential_namespace"]?.try(&.as_s?)
      return corrupt(path, "key_namespace_mismatch") unless embedded_ns == namespace

      digest = entry["digest"]?.try(&.as_s?)
      return corrupt(path, "digest_invalid") unless digest && digest.matches?(DIGEST)
      payload = entry["payload"]?
      return corrupt(path, "payload_missing") unless payload
      return corrupt(path, "digest_mismatch") unless Digest::SHA256.hexdigest(canonical_json(payload)) == digest

      result(Status::Hit, "ok", payload)
    rescue ex : File::NotFoundError
      result(Status::Miss, "not_found")
    rescue ex : JSON::ParseException
      corrupt(path, "invalid_json")
    rescue ex : TypeCastError
      corrupt(path, "invalid_shape")
    rescue ex : ArgumentError
      corrupt(path, "invalid_json")
    rescue ex : IO::Error
      result(Status::Miss, "io_error")
    end
  end

  def self.delete(key : String?) : Bool
    return false unless key && valid_key?(key)
    return false unless enabled?
    path = entry_path(key)
    return false unless path
    discard(path)
    true
  end

  # Persist one complete, self-validating entry. A supplied digest is checked
  # against the canonical payload; omitting it lets the writer compute digest.
  # The payload is deliberately root-independent: P2 refuses absolute/home/drive
  # paths and any parent-directory segment under either separator instead of
  # pretending that a project-specific plan can be relocated.
  def self.write(key : String, components : JSON::Any, payload : JSON::Any,
                 digest : String? = nil) : WriteResult
    return write_result(WriteStatus::InvalidKey, "invalid_key") unless valid_key?(key)
    return write_result(WriteStatus::Disabled, "disabled") unless enabled?
    path = entry_path(key)
    return write_result(WriteStatus::RootUnavailable, "root_unavailable") unless path

    recomputed = key_for(components)
    return write_result(WriteStatus::InvalidComponents, "key_invalid") unless recomputed
    return write_result(WriteStatus::InvalidKey, "key_mismatch") unless recomputed == key
    embedded_ns = components.as_h["credential_namespace"].as_s?
    return write_result(WriteStatus::InvalidNamespace, "key_namespace_mismatch") unless embedded_ns == namespace
    return write_result(WriteStatus::CredentialPayload, "credential_key") unless credential_free_json?(components)
    return write_result(WriteStatus::InvalidPayload, "payload_invalid") unless valid_payload?(payload)
    return write_result(WriteStatus::CredentialPayload, "credential_key") unless credential_free_json?(payload)
    return write_result(WriteStatus::NonPortablePayload, "payload_root_dependent") unless portable_json?(payload)

    begin
      canonical_payload = canonical_json(payload)
      computed_digest = Digest::SHA256.hexdigest(canonical_payload)
      if digest
        return write_result(WriteStatus::InvalidDigest, "digest_invalid") unless digest.matches?(DIGEST)
        return write_result(WriteStatus::InvalidDigest, "digest_mismatch") unless digest == computed_digest
      end
      entry = JSON::Any.new({
        "format"     => JSON::Any.new(FORMAT),
        "written_at" => JSON::Any.new(Time.utc.to_rfc3339),
        "digest"     => JSON::Any.new(computed_digest),
        "key"        => components,
        "payload"    => payload,
      })
      text = canonical_json(entry)
      return write_result(WriteStatus::TooLarge, "too_large") if text.bytesize > MAX_BYTES
      return write_result(WriteStatus::CredentialPayload, "credential_value") if contains_environment_credential?(text)
      return write_result(WriteStatus::IoError, "io_error") unless atomic_write(path, text)
    rescue ex : ArgumentError
      return write_result(WriteStatus::InvalidPayload, "payload_invalid")
    rescue ex : IO::Error
      return write_result(WriteStatus::IoError, "io_error")
    end

    prune
    write_result(WriteStatus::Written, "ok")
  end

  def self.store(key : String, components : JSON::Any, payload : JSON::Any,
                 digest : String? = nil) : WriteResult
    write(key, components, payload, digest)
  end

  # Evict oldest entries until both budgets hold. The directory is resolved
  # once from the current credential namespace; no root-wide traversal occurs.
  def self.prune(max_entries : Int32 = MAX_ENTRIES, max_bytes : Int64 = MAX_BYTES) : Bool
    return false unless enabled?
    return false if max_entries < 0 || max_bytes < 0
    dir = namespace_dir
    return false unless dir
    return true unless Dir.exists?(dir)

    files = [] of NamedTuple(path: String, size: Int64, mtime: Time)
    Dir.each_child(dir) do |child|
      next unless child.matches?(ENTRY_FILE)
      path = File.join(dir, child)
      next unless File.file?(path)
      begin
        info = File.info(path)
        files << {path: path, size: info.size, mtime: info.modification_time}
      rescue ex : File::NotFoundError
        # Another process may have removed it after enumeration.
      end
    end
    files.sort_by! { |file| {file[:mtime], file[:path]} }
    total = files.sum { |file| file[:size] }
    while !files.empty? && (files.size > max_entries || total > max_bytes)
      oldest = files.shift.not_nil!
      begin
        File.delete(oldest[:path])
      rescue ex : File::NotFoundError
        # Already absent: the budget still improves by its enumerated size.
      rescue
        return false
      end
      total -= oldest[:size]
    end
    true
  rescue
    # Garbage collection is best-effort and must never fail a command.
    false
  end

  def self.debug_line(status : Status, reason : String) : String
    "[plan-cache] status=#{status.to_s.downcase} reason=#{reason}"
  end

  private def self.write_result(status : WriteStatus, reason : String) : WriteResult
    if debug?
      debug_io.puts "[plan-cache] operation=write status=#{status.to_s.downcase} reason=#{reason}"
      debug_io.flush
    end
    WriteResult.new(status, reason)
  end

  private def self.atomic_write(path : String, text : String) : Bool
    temp = File.join(File.dirname(path), ".plan-#{Process.pid}-#{Random::Secure.hex(4)}.tmp")
    begin
      Dir.mkdir_p(File.dirname(path))
      File.open(temp, "w") do |file|
        file.print(text)
        file.flush
        begin
          file.fsync
        rescue
          # Some filesystems do not support fsync; the rename still publishes a
          # complete temp file and the next read verifies format/key/digest.
        end
      end
      # Both Windows MoveFileExW(MOVEFILE_REPLACE_EXISTING) and POSIX rename(2)
      # replace an existing file atomically; never unlink the target first.
      File.rename(temp, path)
      true
    rescue
      begin
        File.delete(temp) if File.exists?(temp)
      rescue
      end
      false
    end
  end

  private def self.valid_payload?(value : JSON::Any) : Bool
    object = value.as_h?
    return false unless object && object.keys.sort == PAYLOAD_KEYS
    object["specs"].as_a?.is_a?(Array(JSON::Any)) &&
      object["plan"].as_h?.is_a?(Hash(String, JSON::Any)) &&
      object["installed_snapshot"].as_a?.is_a?(Array(JSON::Any))
  end

  private def self.portable_json?(value : JSON::Any) : Bool
    case raw = value.raw
    when Hash(String, JSON::Any)
      raw.all? { |_, item| portable_json?(item) }
    when Array(JSON::Any)
      raw.all? { |item| portable_json?(item) }
    when String
      portable_string?(raw)
    else
      true
    end
  end

  private def self.portable_string?(value : String) : Bool
    return false if value.includes?('\u0000')
    return false if value.starts_with?("/") || value.starts_with?("\\")
    return false if value.starts_with?("~/") || value.starts_with?("~\\")
    return false if value.starts_with?("./") || value.starts_with?("../")
    return false if value.starts_with?(".\\") || value.starts_with?("..\\")
    # Normalize separators before inspecting every segment. This also rejects
    # foo/../bar and foo\..\bar, not only strings that begin with a parent segment.
    return false if value.gsub('\\', '/').split('/').includes?("..")
    return false if value.matches?(/\A[A-Za-z]:/)
    return false if value.matches?(/\Afile:\/\//i)
    true
  end

  private def self.credential_free_json?(value : JSON::Any) : Bool
    case raw = value.raw
    when Hash(String, JSON::Any)
      raw.all? do |key, item|
        !key.matches?(SENSITIVE_KEY) && credential_free_json?(item)
      end
    when Array(JSON::Any)
      raw.all? { |item| credential_free_json?(item) }
    when String
      !raw.matches?(CREDENTIAL_URI)
    else
      true
    end
  end

  private def self.contains_environment_credential?(text : String) : Bool
    ENV.any? do |key, value|
      credential?(key, value) && !value.empty? && text.includes?(value)
    end
  end

  private def self.result(status : Status, reason : String, payload : JSON::Any? = nil) : ReadResult
    value = ReadResult.new(status, reason, payload)
    if debug?
      debug_io.puts debug_line(status, reason)
      debug_io.flush
    end
    value
  end

  private def self.corrupt(path : String, reason : String) : ReadResult
    discard(path)
    result(Status::Corrupt, reason)
  end

  private def self.discard(path : String) : Nil
    File.delete(path)
    parent = File.dirname(path)
    Dir.delete(parent) if Dir.exists?(parent) && Dir.children(parent).empty?
  rescue ex : IO::Error
    # Cache cleanup is best-effort; validation still returns a non-hit.
  end

  private def self.nonempty_s?(value : JSON::Any?) : Bool
    return false unless value
    text = value.as_s?
    !text.nil? && !text.empty?
  end

  private def self.valid_components?(value : JSON::Any) : Bool
    object = value.as_h?
    return false unless object
    return false unless object.keys.sort == %w[abi build checksums credential_namespace platform sources]
    return false unless object["sources"].as_a?.try(&.size.>(0))
    return false unless object["credential_namespace"].as_s?.try(&.matches?(NAMESPACE))

    checksums = object["checksums"].as_a?
    return false unless checksums && !checksums.empty?
    checksums.each do |entry|
      row = entry.as_h?
      return false unless row && row.keys.sort == %w[checksums name platform version]
      return false unless nonempty_s?(row["name"])
      return false unless nonempty_s?(row["version"])
      return false unless nonempty_s?(row["platform"])
      values = row["checksums"].as_a?
      return false unless values && !values.empty?
      return false unless values.all? { |item| item.as_s?.try(&.matches?(DIGEST)) }
    end

    platform = object["platform"].as_h?
    return false unless platform && platform.keys.sort == %w[force_ruby_platform local locked]
    return false unless nonempty_s?(platform["local"])
    locked = platform["locked"].as_a?
    return false unless locked && !locked.empty? && locked.all? { |item| nonempty_s?(item) }
    return false unless platform["force_ruby_platform"].raw.is_a?(Bool)

    abi = object["abi"].as_h?
    return false unless abi && abi.keys.sort == %w[extension_api_version rbconfig_ruby_version ruby_api_version]
    return false unless abi.values.all? { |item| nonempty_s?(item) }

    build = object["build"].as_h?
    return false unless build
    return false unless build.values.all? do |item|
                          args = item.as_a?
                          args && args.all? { |arg| arg.as_s? }
                        end

    sources = object["sources"].as_a?
    return false unless sources && sources.all? do |source|
                          identity = source.as_h?
                          identity && nonempty_s?(identity["type"]?) &&
                          (identity["remote"]?.try(&.as_s?) || identity["plugin_type"]?.try(&.as_s?))
                        end
    true
  end

  private def self.build_args(config : Config, name : String) : Array(String)?
    value = config["build.#{name}"]
    case value
    when Nil
      [] of String
    when String
      value.split.reject(&.empty?)
    when Array(String)
      value.flat_map(&.split).reject(&.empty?)
    else
      nil
    end
  end

  private def self.option_string(section : Lockfile::SourceSection, key : String) : String?
    case value = section.option(key)
    when String
      value.empty? ? nil : value
    end
  end

  private def self.option_bool(section : Lockfile::SourceSection, key : String) : Bool?
    case value = section.option(key)
    when Bool
      value
    end
  end
end
