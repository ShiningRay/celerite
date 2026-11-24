require "digest/sha256"
require "json"

module Celerite
  # Client-side half of the M8 evaluation fingerprint (roadmap L162, slice F2).
  #
  # The bridge produces one fingerprint per evaluation (slice F1, see
  # `assets/bridge/server.rb` `bridge_fingerprint`): a deterministic text of
  # `key<TAB>value` records, a SHA-256 of that text, and a `verify` object
  # listing every file whose content the evaluation depended on. This module
  # parses that wire shape and re-checks it; `EvaluationCache` uses the result
  # to decide whether a cached evaluation may still answer.
  #
  # What is checked, and why it is enough:
  #
  # * `digest` must be the SHA-256 of `text` — the fingerprint cannot be
  #   edited without recomputing it, and a stale `text`/`digest` pair is a miss.
  # * every file in `verify.files` is re-hashed from disk. The fingerprint
  #   records the Gemfile itself, every file reached through `eval_gemfile`
  #   (`role: "evalchain"`) and every loaded `.gemspec` (`role: "gemspec"`), so
  #   a change anywhere in that closure is a miss. This is the hole the old
  #   size/mtime/sha256-of-the-main-Gemfile check left open: editing
  #   `nested/Gemfile.local` or a gemspec's development dependency changed the
  #   evaluation without touching the main file.
  # * the runtime records (`ruby.version`, `ruby.patchlevel`, `ruby.engine`,
  #   `ruby.engine_version`, `rubygems.version`, `bundler.version`,
  #   `platform`) must equal what the answering process reports. They are
  #   passed in as a `Runtime`; `nil` means "the cache entry was produced by
  #   this very client, hence by the same bridge process", where the records
  #   are equal by construction and no round trip is needed.
  #
  # The fingerprint text does **not** carry ENV (F1 did not include it), so
  # this module alone is not a complete invalidation key. `EvaluationCache`
  # keeps the whole-environment signature as a third, conservative component.
  module EvalFingerprint
    MAGIC  = "celerite-eval-v1"
    FORMAT = "1"

    ROLES = %w(gemfile evalchain gemspec)

    # The three cacheability verdicts the bridge decides (roadmap L162, slice
    # F3) — only the bridge may pick one, because only it knows what the DSL
    # actually executed. `EvaluationCache` consumes the verdict and never
    # upgrades it on its own; a missing or unrecognized value is `Unknown`.
    #
    # * `Deterministic` — the main Gemfile, every `eval_gemfile` target and
    #   every loaded gemspec consist only of static declarations, so the files
    #   listed in `verify` are the whole input of the evaluation. Such a result
    #   may be stored and reused while the fingerprint still verifies.
    # * `Unknown` — the evaluation read something the fingerprint cannot
    #   describe (dynamic Ruby, an `eval_gemfile` path built at runtime, a
    #   plugin source, an installed plugin index, ...). The result is still
    #   returned untouched; it is never stored or reused, so the command
    #   behaves exactly as it would without a cache.
    # * `Broken` — the fingerprint contradicts itself (`digest` does not match
    #   `text`, `fp.format` is unknown, `verify` is corrupt, or a file is
    #   recorded as `-`). Nothing is stored and `verify` can never pass, but the
    #   evaluation that produced it stays valid: a broken fingerprint must not
    #   fail the command.
    enum State
      Deterministic
      Unknown
      Broken

      def self.parse(value : String?) : State
        case value
        when "deterministic" then Deterministic
        when "broken"        then Broken
        else                      Unknown
        end
      end

      def wire : String
        case self
        in Deterministic then "deterministic"
        in Unknown       then "unknown"
        in Broken        then "broken"
        end
      end
    end

    # Whether a `verify` reason says the fingerprint itself is corrupt rather
    # than merely out of date. Only the former is `Broken`; a changed or
    # missing file makes the entry stale, which is an ordinary miss.
    def self.broken_reason?(reason : String) : Bool
      reason == "digest" || reason == "format" || reason == "gemfile" ||
        reason.starts_with?("count:") || reason.starts_with?("role:") ||
        reason.starts_with?("unreadable:")
    end

    # One file whose content the evaluation read.
    record FileRef, role : String, path : String, sha256 : String

    # The runtime facts recorded by the fingerprint, as reported by the
    # current process.
    struct Runtime
      getter ruby_version : String
      getter patchlevel : String
      getter engine : String
      getter engine_version : String
      getter rubygems_version : String
      getter bundler_version : String
      getter platform : String

      def initialize(@ruby_version : String, @patchlevel : String, @engine : String,
                     @engine_version : String, @rubygems_version : String,
                     @bundler_version : String, @platform : String)
      end
    end

    # A parsed fingerprint: the text, its digest, the flat record map used by
    # the checks above and the `verify` payload kept for re-serialization.
    class Document
      getter text : String
      getter digest : String
      getter records : Hash(String, String)
      getter files : Array(FileRef)
      getter verify : JSON::Any

      def initialize(@text : String, @digest : String, @records : Hash(String, String),
                     @files : Array(FileRef), @verify : JSON::Any)
      end

      # Parses one fingerprint as it arrives over the bridge. Returns `nil`
      # for a malformed text or verify payload; callers treat that as a cache
      # miss and simply evaluate again.
      def self.parse(text : String, digest : String, verify : JSON::Any) : Document?
        records = parse_records(text)
        return nil if records.nil?
        files = parse_files(verify)
        return nil if files.nil?
        new(text, digest, records, files, verify)
      end

      # The part of `verify` that never touches the disk: a fingerprint that
      # fails here contradicts itself and can never answer, so an entry
      # carrying one is `Broken` rather than stale.
      def integrity_reason : String?
        return "digest" unless Digest::SHA256.hexdigest(@text) == @digest
        return "format" unless @records["fp.format"]? == FORMAT

        gemfile_files = @files.select { |file| file.role == "gemfile" }
        return "gemfile" unless gemfile_files.size == 1

        {"evalchain", "gemspec"}.each do |role|
          recorded = @records["#{role}.count"]?.try(&.to_i?)
          return "count:#{role}" if recorded.nil?
          actual = @files.count { |file| file.role == role }
          return "count:#{role}" unless recorded == actual
        end

        @files.each do |file|
          return "role:#{file.role}" unless ROLES.includes?(file.role)
          # The bridge writes "-" when it could not hash a file at evaluation
          # time; such a record can never be re-verified.
          return "unreadable:#{file.role}:#{file.path}" if file.sha256 == "-"
        end

        nil
      end

      # Recomputes everything the fingerprint claims and compares it with the
      # current disk and process state. Returns `nil` on a match, otherwise a
      # short reason so a cache miss can say why it happened.
      def verify(base_dir : String, runtime : Runtime?) : String?
        if reason = integrity_reason
          return reason
        end

        @files.each do |file|
          bytes = begin
            File.read(resolve(base_dir, file.path))
          rescue
            return "missing:#{file.role}:#{file.path}"
          end
          unless Digest::SHA256.hexdigest(bytes) == file.sha256
            return "sha256:#{file.role}:#{file.path}"
          end
        end

        runtime_records = {
          "ruby.version"        => runtime.try(&.ruby_version),
          "ruby.patchlevel"     => runtime.try(&.patchlevel),
          "ruby.engine"         => runtime.try(&.engine),
          "ruby.engine_version" => runtime.try(&.engine_version),
          "rubygems.version"    => runtime.try(&.rubygems_version),
          "bundler.version"     => runtime.try(&.bundler_version),
          "platform"            => runtime.try(&.platform),
        }
        runtime_records.each do |key, current|
          recorded = @records[key]?
          return "record:#{key}" if recorded.nil?
          next if current.nil?
          return "runtime:#{key}" unless recorded == current
        end

        nil
      end

      private def resolve(base_dir : String, recorded : String) : String
        absolute = recorded.starts_with?('/') ||
                   (recorded.size >= 3 && recorded[1] == ':' && (recorded[2] == '/' || recorded[2] == '\\'))
        absolute ? File.expand_path(recorded) : File.expand_path(File.join(base_dir, recorded))
      end

      private def self.parse_records(text : String) : Hash(String, String)?
        lines = text.lines(chomp: true)
        return nil unless lines.first? == MAGIC

        records = {} of String => String
        lines[1..].each do |line|
          return nil if line.empty?
          key, value = line.split('\t', 2)
          return nil if value.nil?
          records[unescape(key)] = unescape(value)
        end
        records
      end

      private def self.parse_files(verify : JSON::Any) : Array(FileRef)?
        object = verify.as_h?
        return nil if object.nil?
        array = object["files"]?.try(&.as_a?)
        return nil if array.nil?

        files = [] of FileRef
        array.each do |item|
          entry = item.as_h?
          return nil if entry.nil?
          role = entry["role"]?.try(&.as_s?)
          path = entry["path"]?.try(&.as_s?)
          sha256 = entry["sha256"]?.try(&.as_s?)
          return nil if role.nil? || path.nil? || sha256.nil?
          files << FileRef.new(role, path, sha256)
        end
        files
      end

      # Inverse of `bridge_fingerprint_escape`: `\\`, `\t`, `\n`, `\r`.
      private def self.unescape(value : String) : String
        return value unless value.includes?('\\')
        out = String::Builder.new
        index = 0
        while index < value.size
          char = value[index]
          if char == '\\' && index + 1 < value.size
            index += 1
            escaped = value[index]
            out << case escaped
            when 't' then '\t'
            when 'n' then '\n'
            when 'r' then '\r'
            else          escaped
            end
          else
            out << char
          end
          index += 1
        end
        out.to_s
      end
    end
  end
end
