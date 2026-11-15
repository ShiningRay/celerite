require "./spec_helper"
require "http/server"
require "openssl"
require "../src/celerite/downloader"

# M7(4) TLS certificate failures: the reference maps verification errors to
# Bundler::Fetcher::CertificateFailureError (an HTTPError, exit 17) with a fixed
# multi-line message (bundler/fetcher.rb:25-34, fetcher/downloader.rb:94-95).
# These examples use a local HTTPS server with the self-signed fixture
# certificate, so everything stays offline.

private CERT_FAILURE_GEM_NAME    = "net-protocol"
private CERT_FAILURE_GEM_VERSION = "0.2.2"
private CERT_FAILURE_GEM_FILE    = "net-protocol-0.2.2.gem"

private def cert_failure_bytes : Bytes
  File.read(File.expand_path("fixtures/locked-deps/gems/#{CERT_FAILURE_GEM_FILE}", __DIR__)).to_slice
end

private def cert_failure_tls_fixture(name : String) : String
  File.expand_path("fixtures/tls/#{name}", __DIR__)
end

private def with_certificate_failure_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def with_certificate_failure_server(&)
  context = OpenSSL::SSL::Context::Server.new
  context.certificate_chain = cert_failure_tls_fixture("server.pem")
  context.private_key = cert_failure_tls_fixture("server.key")
  bytes = cert_failure_bytes
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

private def certificate_failure_message(port : Int32) : String
  "Could not verify the SSL certificate for https://127.0.0.1:#{port}/.\n" +
    "There is a chance you are experiencing a man-in-the-middle attack, but most " +
    "likely your system doesn't have the CA certificates needed for verification. " +
    "For information about OpenSSL certificates, see " +
    "https://railsapps.github.io/openssl-certificate-verify-failed.html."
end

private def cert_failure_fetch(downloader : Celerite::Downloader) : String
  downloader.fetch(CERT_FAILURE_GEM_NAME, CERT_FAILURE_GEM_VERSION, nil, nil)
end

private def with_cert_failure_dir(&)
  dir = File.tempname("celerite-cert-failure")
  Dir.mkdir_p(dir)
  yield dir
end

describe "M7(4) TLS certificate failure" do
  it "reports CertificateFailureError, prints the reference text and exits 17" do
    with_certificate_failure_bridge do
      with_certificate_failure_server do |port|
        gemfile = "source \"https://127.0.0.1:#{port}/\"\n\ngem \"thor\"\n"
        with_project({"Gemfile" => gemfile}) do
          # The suite wraps at 80 columns; widen the terminal so the comparison
          # is about wording rather than wrap points (the reference wraps too).
          previous_columns = ENV["THOR_COLUMNS"]?
          ENV["THOR_COLUMNS"] = "200"
          begin
            code, _out, err = run_cli(["install"])
          ensure
            if previous_columns
              ENV["THOR_COLUMNS"] = previous_columns
            else
              ENV.delete("THOR_COLUMNS")
            end
          end
          code.should eq(17)
          err.should_not contain("celerite internal error")
          err.should contain(
            "Could not verify the SSL certificate for https://127.0.0.1:#{port}/.\n" +
            "There is a chance you are experiencing a man-in-the-middle attack,"
          )
          err.gsub(/\s+/, " ").strip.should eq(
            certificate_failure_message(port).gsub(/\s+/, " ").strip
          )
          err.should contain("https://railsapps.github.io/openssl-certificate-verify-failed.html.")
        end
      end
    end
  end

  it "still accepts the self-signed certificate when ssl_verify_mode is none" do
    bytes = cert_failure_bytes
    with_certificate_failure_server do |port|
      with_cert_failure_dir do |dir|
        downloader = Celerite::Downloader.new(
          "https://127.0.0.1:#{port}/", dir, 0,
          ssl_verify_mode: "none", timeout: 5)
        File.read(cert_failure_fetch(downloader)).to_slice.should eq(bytes)
      end
    end
  end

  it "still accepts the certificate when ssl_ca_cert supplies its CA" do
    bytes = cert_failure_bytes
    with_certificate_failure_server do |port|
      with_cert_failure_dir do |dir|
        downloader = Celerite::Downloader.new(
          "https://127.0.0.1:#{port}/", dir, 0,
          ssl_ca_cert: cert_failure_tls_fixture("ca.pem"), timeout: 5)
        File.read(cert_failure_fetch(downloader)).to_slice.should eq(bytes)
      end
    end
  end
end
