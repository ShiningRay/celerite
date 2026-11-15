require "openssl"

module Celerite
  # Client-side TLS plumbing shared by the gem downloader and the compact
  # index fetcher.
  module TLS
    # Bundler treats `ssl_client_cert` as one PEM that may also carry the
    # client private key (`lib/bundler/fetcher.rb` L324-331): it always assigns
    # `con.cert = Certificate.new(pem)` and assigns `con.key = PKey.read(pem)`
    # only when that PEM bundles a key. Mirror that shape here so an mTLS
    # handshake can actually present the client certificate key.
    def self.configure_client_certificate(ctx : OpenSSL::SSL::Context::Client, pem_path : String) : Nil
      return if pem_path.empty?

      ctx.certificate_chain = pem_path
      # RSA / EC / ENCRYPTED private keys all carry this marker; a
      # certificate-only PEM does not. Leaving the key unset matches Bundler's
      # `key = nil` branch; real errors (bad password, mismatched key) are
      # deliberately not rescued.
      return unless File.read(pem_path).includes?("PRIVATE KEY")

      ctx.private_key = pem_path
    end

    # Bundler's trust store shape (bundler/fetcher.rb:349-359): an explicit
    # `ssl_ca_cert` is a CA *directory* (CApath, c_rehash layout) when it points
    # at a directory and a single PEM file otherwise; with no setting Bundler
    # calls `set_default_paths`, so the OpenSSL default store is initialised
    # and honours SSL_CERT_FILE / SSL_CERT_DIR. Errors from loading a bad CA
    # path are deliberately not rescued (same as the reference).
    def self.configure_trust_store(ctx : OpenSSL::SSL::Context::Client, ca_cert : String?) : Nil
      path = ca_cert.to_s
      if path.empty?
        ctx.set_default_verify_paths
        # Windows only: Crystal's ENV[]= goes through SetEnvironmentVariable,
        # which does not update the CRT `environ` block that OpenSSL's
        # set_default_paths reads, so an SSL_CERT_FILE assigned inside the
        # process would otherwise be ignored. Loading it explicitly here keeps
        # the variable meaningful whether it was inherited or set at runtime.
        if cert_file = ENV["SSL_CERT_FILE"]?
          ctx.ca_certificates = cert_file unless cert_file.empty?
        end
      elsif File.directory?(path)
        ctx.ca_certificates_path = path
      else
        ctx.ca_certificates = path
      end
    end
  end
end
