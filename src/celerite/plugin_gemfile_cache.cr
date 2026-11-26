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
  # source URI, or credential. Its semantic payload is the successful nonce and
  # ordered plugin name list; only an empty list may authorize skipping the
  # Ruby preflight. The evaluation cache entry with the same digest remains the
  # proof for Gemfile/eval-chain/gemspec bytes, environment, runtime, and ABI.
  module PluginGemfileCache
    FORMAT     = "celerite-plugin-gemfile-cache/2"
    LAYOUT     = "v2"
    ENTRY_NAME = "certificate.json"
    ROOT_ENV   = "CELERITE_CACHE_DIR"
    DIRECTORY  = ".celerite"
    DIGEST     = /\A[0-9a-f]{64}\z/

    # The install fast path accepts only absent/empty plugin trees. These
    # root-independent digests are the corresponding SuccessCertificate proof;
    # non-empty local or global trees still fail the separate filesystem gate.
    EMPTY_ROOTS_DIGEST = Digest::SHA256.hexdigest("celerite-plugin-roots/v1\n")
    EMPTY_INDEX_DIGEST = Digest::SHA256.hexdigest("celerite-plugin-index/v1\n")

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
                      evaluation : Bridge::GemfileEvaluation?, fingerprint : Bridge::EvalFingerprint?,
                      certificate_nonce : String) : Bool
      return false unless enabled?
      return false if plugin_names.nil? || evaluation.nil? || fingerprint.nil?
      return false unless plugin_names.empty? && evaluation.warnings.empty?
      return false unless fingerprint.state == Celerite::EvalFingerprint::State::Deterministic
      return false unless EvalCacheStore::Identity.valid_nonce?(certificate_nonce)

      document = EvalFingerprint::Document.parse(fingerprint.text, fingerprint.digest, fingerprint.verify)
      return false if document.nil?
      return false if document.integrity_reason
      return false if document.verify(File.dirname(File.expand_path(gemfile_path)), nil)

      payload = JSON.build do |json|
        json.object do
          json.field "format", FORMAT
          json.field "digest", fingerprint.digest
          json.field "certificate_nonce", certificate_nonce
          json.field "plugin_names" do
            json.array { plugin_names.each { |name| json.string(name) } }
          end
        end
      end
      return false unless EvalCacheStore.persistable?(payload)
      write(fingerprint.digest, payload)
    rescue
      # Persistence is an optimization. A read-only cache, full disk, or racing
      # cleanup must not alter stdout, stderr, filesystem work, or exit status.
      false
    end

    # A valid certificate is necessary but not sufficient: the caller must
    # also verify the matching evaluation/runtime record, certificate nonce, and
    # local plugin tree. Corrupt certificates are removed so the next run takes
    # the normal Ruby preflight and can replace them with a fresh proof.
    def self.trusted?(digest : String, certificate_nonce : String? = nil) : Bool
      return false unless enabled?
      return false if certificate_nonce.nil? || !EvalCacheStore::Identity.valid_nonce?(certificate_nonce)
      path = entry_path(digest)
      return false if path.nil? || !File.file?(path)

      json = JSON.parse(File.read(path))
      return false unless json.as_h.keys.sort == ["certificate_nonce", "digest", "format", "plugin_names"]
      return false unless json["format"]?.try(&.as_s?) == FORMAT
      return false unless json["digest"]?.try(&.as_s?) == digest
      return false unless json["certificate_nonce"]?.try(&.as_s?) == certificate_nonce
      names = json["plugin_names"]?.try(&.as_a?)
      return false if names.nil? || names.any? { |name| name.as_s?.nil? }

      names.empty?
    rescue
      discard(path.not_nil!) unless path.nil?
      false
    end

    # Install transactions replace one project-global plugin certificate. Keep
    # its exact previous bytes so a later RuntimeRecord write failure can restore
    # the nonce still referenced by the previous record.
    def self.snapshot(digest : String) : String?
      path = entry_path(digest)
      return nil if path.nil? || !File.file?(path)
      File.read(path)
    end

    def self.restore(digest : String, snapshot : String?) : Bool
      path = entry_path(digest)
      return false if path.nil?
      if snapshot
        write(digest, snapshot)
      else
        discard(path)
        true
      end
    rescue
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
