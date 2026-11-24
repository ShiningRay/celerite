require "digest/sha256"
require "json"
require "random/secure"

require "./bridge/client"
require "./config"
require "./eval_cache_store"
require "./eval_fingerprint"
require "./fast_path_store"

module Celerite
  # Proof that a successful `Bundler::Plugin::DSL` evaluation declared no
  # plugins for the deterministic Gemfile evaluation identified by `digest`.
  #
  # The certificate deliberately carries no project root, environment value,
  # source URI, or credential. Its only semantic payload is the ordered plugin
  # name list; only an empty list may authorize skipping the Ruby preflight.
  # The evaluation cache entry with the same digest remains the proof for the
  # Gemfile/eval-chain/gemspec bytes, environment, runtime, and ABI.
  module PluginGemfileCache
    FORMAT     = "celerite-plugin-gemfile-cache/1"
    LAYOUT     = "v1"
    ENTRY_NAME = "certificate.json"
    ROOT_ENV   = "CELERITE_CACHE_DIR"
    DIRECTORY  = ".celerite"
    DIGEST     = /\A[0-9a-f]{64}\z/

    # A plugin certificate is useful only to the zero-Ruby install path, which
    # already requires both switches. Keeping the same gate avoids creating a
    # second cache artifact for commands that cannot consume it.
    def self.enabled? : Bool
      EvalCacheStore.enabled? && FastPathStore.enabled?
    end

    def self.root : String?
      if override = ENV[ROOT_ENV]?
        return nil if override.empty?
        return File.expand_path(override)
      end
      home = Config.user_home
      return nil if home.nil? || home.empty?
      File.expand_path(File.join(home, DIRECTORY, "cache", "plugin-gemfile"))
    end

    def self.entry_path(digest : String) : String?
      base = root
      return nil if base.nil? || !digest.matches?(DIGEST)
      File.join(base, LAYOUT, digest, ENTRY_NAME)
    end

    # Bind a successful, warning-free Plugin::DSL result to the deterministic
    # fingerprint produced by the normal evaluation in the same install. Only
    # an empty name list may create a certificate; all other states keep the
    # Ruby preflight. Every failure is a cache miss, never a command failure.
    def self.remember(gemfile_path : String, plugin_names : Array(String)?,
                      evaluation : Bridge::GemfileEvaluation?, fingerprint : Bridge::EvalFingerprint?) : Nil
      return unless enabled?
      return if plugin_names.nil? || evaluation.nil? || fingerprint.nil?
      return unless plugin_names.empty? && evaluation.warnings.empty?
      return unless fingerprint.state == Celerite::EvalFingerprint::State::Deterministic

      document = EvalFingerprint::Document.parse(fingerprint.text, fingerprint.digest, fingerprint.verify)
      return if document.nil?
      return if document.integrity_reason
      return if document.verify(File.dirname(File.expand_path(gemfile_path)), nil)

      payload = JSON.build do |json|
        json.object do
          json.field "format", FORMAT
          json.field "digest", fingerprint.digest
          json.field "plugin_names" do
            json.array { plugin_names.each { |name| json.string(name) } }
          end
        end
      end
      return unless EvalCacheStore.persistable?(payload)
      write(fingerprint.digest, payload)
    rescue
      # Persistence is an optimization. A read-only cache, full disk, or racing
      # cleanup must not alter stdout, stderr, filesystem work, or exit status.
    end

    # A valid certificate is necessary but not sufficient: the caller must
    # also verify the matching evaluation/runtime record and the local plugin
    # tree. Corrupt certificates are removed so the next run takes the normal
    # Ruby preflight and can replace them with a fresh proof.
    def self.trusted?(digest : String) : Bool
      return false unless enabled?
      path = entry_path(digest)
      return false if path.nil? || !File.file?(path)

      json = JSON.parse(File.read(path))
      return false unless json.as_h.keys.sort == ["digest", "format", "plugin_names"]
      return false unless json["format"]?.try(&.as_s?) == FORMAT
      return false unless json["digest"]?.try(&.as_s?) == digest
      names = json["plugin_names"]?.try(&.as_a?)
      return false if names.nil? || names.any? { |name| name.as_s?.nil? }

      names.empty?
    rescue
      discard(path.not_nil!) unless path.nil?
      false
    end

    def self.write(digest : String, payload : String) : Bool
      target = entry_path(digest)
      return false if target.nil?
      dir = File.dirname(target.not_nil!)
      temp = File.join(dir, ".certificate-#{Process.pid}-#{Random::Secure.hex(4)}.tmp")
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
        # Same-directory rename atomically replaces a complete certificate.
        # Crystal's Win32 rename uses MOVEFILE_REPLACE_EXISTING, so the trusted
        # target remains present until the new payload is published.
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

    private def self.discard(path : String) : Nil
      File.delete(path) if File.exists?(path)
      parent = File.dirname(path)
      Dir.delete(parent) if Dir.exists?(parent) && Dir.children(parent).empty?
    rescue
    end
  end
end
