require "./spec_helper"
require "http/server"
require "openssl"
require "../src/celerite/downloader"
require "../src/celerite/errors"

# M7(4) TLS trust store, pinned against bundler/fetcher.rb:349-359:
#   - ssl_ca_cert is a directory -> add_path (CApath, c_rehash layout)
#   - ssl_ca_cert is a file      -> add_file
#   - neither                    -> set_default_paths (honours SSL_CERT_FILE /
#                                   SSL_CERT_DIR on the OpenSSL default store)
# The examples stay offline by serving the self-signed fixture certificate.

private def trust_store_fixture(name : String) : String
  File.expand_path("fixtures/tls/#{name}", __DIR__)
end

private def trust_store_bytes : String
  "trust-store-bytes"
end

private def with_trust_store_server(&)
  context = OpenSSL::SSL::Context::Server.new
  context.certificate_chain = trust_store_fixture("server.pem")
  context.private_key = trust_store_fixture("server.key")
  bytes = trust_store_bytes.to_slice
  server = HTTP::Server.new do |ctx|
    ctx.response.content_type = "application/octet-stream"
    ctx.response.write(bytes)
  end
  address = server.bind_tls("127.0.0.1", 0, context)
  spawn { server.listen }
  begin
    yield address.port
  ensure
    server.close
  end
end

private def with_ssl_cert_file(value : String?, &)
  previous = ENV["SSL_CERT_FILE"]?
  if value
    ENV["SSL_CERT_FILE"] = value
  else
    ENV.delete("SSL_CERT_FILE")
  end
  begin
    yield
  ensure
    if previous
      ENV["SSL_CERT_FILE"] = previous
    else
      ENV.delete("SSL_CERT_FILE")
    end
  end
end

private def with_trust_store_dir(&)
  dir = File.tempname("celerite-trust-store")
  Dir.mkdir_p(dir)
  yield dir
end

private def trust_store_fetch(port : Int32, dir : String, ca_cert : String?) : String
  downloader = Celerite::Downloader.new("https://127.0.0.1:#{port}/", dir, 0, ssl_ca_cert: ca_cert, timeout: 5)
  File.read(downloader.fetch("trust-store", "1.0.0", nil, nil))
end

describe "M7(4) TLS trust store" do
  it "honours SSL_CERT_FILE via the default verify paths when ssl_ca_cert is blank" do
    with_trust_store_server do |port|
      with_trust_store_dir do |dir|
        with_ssl_cert_file(trust_store_fixture("ca.pem")) do
          trust_store_fetch(port, dir, nil).should eq(trust_store_bytes)
        end
      end
    end
  end

  it "fails verification when no CA source is configured (negative control)" do
    with_trust_store_server do |port|
      with_trust_store_dir do |dir|
        with_ssl_cert_file(nil) do
          expect_raises(Celerite::CertificateFailureError) do
            trust_store_fetch(port, dir, nil)
          end
        end
      end
    end
  end

  it "uses an explicit PEM file passed through ssl_ca_cert" do
    with_trust_store_server do |port|
      with_trust_store_dir do |dir|
        with_ssl_cert_file(nil) do
          trust_store_fetch(port, dir, trust_store_fixture("ca.pem")).should eq(trust_store_bytes)
        end
      end
    end
  end

  it "uses an explicit CA directory (c_rehash layout) passed through ssl_ca_cert" do
    # spec/fixtures/tls/ca-dir/481f80ed.0 is ca.pem copied under the hash
    # computed by: openssl x509 -in spec/fixtures/tls/ca.pem -hash -noout
    with_trust_store_server do |port|
      with_trust_store_dir do |dir|
        with_ssl_cert_file(nil) do
          trust_store_fetch(port, dir, trust_store_fixture("ca-dir")).should eq(trust_store_bytes)
        end
      end
    end
  end
end
