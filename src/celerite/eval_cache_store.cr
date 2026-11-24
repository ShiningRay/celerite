require "digest/sha256"
require "json"
require "random/secure"

require "./config"

module Celerite
  # F4 of the M8 evaluation-cache slice (roadmap L162): makes the in-process
  # F2/F3 evaluation cache survive the end of a command.
  #
  # The store is deliberately narrow. It persists only the *evaluation* (the
  # DSL result the bridge returns: dependencies, sources, ruby constraints,
  # plugin declarations, warnings, gemspec paths) under a content address that
  # is the F1/F3 fingerprint digest. It never persists a lockfile, an install
  # plan, or an installed spec: those are produced by later commands from the
  # evaluation and are not inputs to it.
  #
  # Layout: `<root>/<namespace>/v1/<hex64 digest>/entry.json`, where
  # `<namespace>` is the first 16 hex digits of the SHA-256 over the
  # credential-bearing `BUNDLE_*` environment pairs. Only the hash reaches the
  # disk: a Gemfile may carry userinfo in a source URI, but such an evaluation is
  # never persisted at all (see `persistable?`), because redacting the URI would
  # change what a cache hit replays.
  #
  # Everything here is opt-in: `CELERITE_EVAL_CACHE=1`. Unset (or any other
  # value) keeps the cache in memory for the duration of one command, exactly as
  # F2/F3 shipped. Corruption is always a miss, never an error.
  module EvalCacheStore
    FORMAT      = "celerite-eval-cache/1"
    LAYOUT      = "v1"
    SWITCH      = "CELERITE_EVAL_CACHE"
    ROOT_ENV    = "CELERITE_CACHE_DIR"
    ENTRY_NAME  = "entry.json"
    MAX_ENTRIES = 128
    MAX_BYTES   = 8_i64 * 1024 * 1024
    DIRECTORY   = ".celerite"

    # A URI with userinfo (`scheme://user:pass@host/...`). The fingerprint never
    # contains a source URI, but the evaluation does; any match withholds the
    # entry instead of writing a credential to disk.
    CREDENTIAL_URI = %r{://[^/"\\\s]+@}
    DIGEST         = /\A[0-9a-f]{64}\z/
    NAMESPACE      = /\A[0-9a-f]{16}\z/

    record EntryFile, digest : String, path : String, json : JSON::Any

    def self.enabled? : Bool
      ENV[SWITCH]? == "1"
    end

    # `CELERITE_CACHE_DIR` wins so a sandbox can pin one directory; otherwise
    # the plan's `$HOME/.celerite/cache/eval` applies. No home directory means
    # no persistence (never fall back to the project working directory).
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

    # Bundler's host credential convention (`BUNDLE_GEMS__EXAMPLE__COM`) and any
    # `BUNDLE_*` value that itself embeds userinfo. Non-credential values are
    # hashed too, which only makes the namespace more specific.
    def self.credential?(key : String, value : String) : Bool
      return false unless key.starts_with?("BUNDLE_")
      key.includes?("__") || value.matches?(CREDENTIAL_URI)
    end

    def self.namespace_dir : String?
      base = root
      return nil if base.nil?
      File.join(base, namespace, LAYOUT)
    end

    def self.entry_path(digest : String) : String?
      dir = namespace_dir
      return nil if dir.nil? || !digest.matches?(DIGEST)
      File.join(dir, digest, ENTRY_NAME)
    end

    # A payload is persistable only when it cannot carry a credential-bearing
    # URI. This is checked on the exact bytes that would be written, so a future
    # evaluation field cannot leak a credential by accident.
    def self.persistable?(payload : String) : Bool
      !payload.matches?(CREDENTIAL_URI)
    end

    def self.write(digest : String, payload : String) : Bool
      target = entry_path(digest)
      return false if target.nil?
      dir = File.dirname(target.not_nil!)
      temp = File.join(dir, ".entry-#{Process.pid}-#{Random::Secure.hex(4)}.tmp")
      begin
        Dir.mkdir_p(dir)
        File.open(temp, "w") do |file|
          file.print(payload)
          file.flush
          begin
            file.fsync
          rescue
          end
        end
        # Same-directory temp + rename: a reader sees either the old file, no
        # file, or the complete new one. Windows cannot rename over an existing
        # target, and two writers of the same digest write equivalent bytes, so
        # delete-then-rename is safe here (plan §6.3).
        File.delete(target) if File.exists?(target)
        File.rename(temp, target)
        true
      rescue
        begin
          File.delete(temp) if File.exists?(temp)
        rescue
        end
        false
      end
    end

    def self.read_all : Array(EntryFile)
      dir = namespace_dir
      return [] of EntryFile if dir.nil? || !Dir.exists?(dir)
      entries = [] of EntryFile
      Dir.each_child(dir) do |child|
        next unless child.matches?(DIGEST)
        path = File.join(dir, child, ENTRY_NAME)
        next unless File.file?(path)
        entry = parse(path, child)
        if entry
          entries << entry
        else
          discard(path)
        end
      end
      # Newest first: the caller tries the most recently written entry for a
      # Gemfile path before older ones.
      entries.sort_by! { |entry| -File.info(entry.path).modification_time.to_unix_ms }
      entries
    rescue
      [] of EntryFile
    end

    def self.delete(digest : String) : Nil
      path = entry_path(digest)
      discard(path.not_nil!) unless path.nil?
    end

    # Evicts oldest entries across every namespace under `base` until both the
    # entry count and the byte budget hold. Called once per command from
    # `EvaluationCache.finish`, so the store cannot grow without bound even when
    # several credential namespaces exist.
    def self.prune(base : String? = nil, max_entries : Int32 = MAX_ENTRIES,
                   max_bytes : Int64 = MAX_BYTES) : Nil
      root_dir = base || root
      return if root_dir.nil? || !Dir.exists?(root_dir)

      files = [] of NamedTuple(path: String, size: Int64, mtime: Time)
      Dir.each_child(root_dir) do |namespace|
        next unless namespace.matches?(NAMESPACE)
        layout = File.join(root_dir, namespace, LAYOUT)
        next unless Dir.exists?(layout)
        Dir.each_child(layout) do |digest|
          next unless digest.matches?(DIGEST)
          path = File.join(layout, digest, ENTRY_NAME)
          next unless File.file?(path)
          info = File.info(path)
          files << {path: path, size: info.size, mtime: info.modification_time}
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
        rescue
        end
        total -= oldest[:size]
      end
    rescue
      # GC must never fail a command.
    end

    private def self.parse(path : String, digest : String) : EntryFile?
      json = JSON.parse(File.read(path))
      return nil unless json["format"]?.try(&.as_s?) == FORMAT
      return nil unless json["digest"]?.try(&.as_s?) == digest
      return nil unless json["evaluation"]?.try(&.as_h?)
      EntryFile.new(digest, path, json)
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
