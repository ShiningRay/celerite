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
  end
end
