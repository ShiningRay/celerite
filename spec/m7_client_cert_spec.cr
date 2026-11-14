require "./spec_helper"
require "../src/celerite/downloader"
require "openssl"
require "socket"

# Fixtures in spec/fixtures/tls were generated with the OpenSSL shipped in
# C:\msys64\ucrt64\bin (100-year validity, no passphrase). Rebuild with:
#
#   openssl genrsa -out ca.key 2048
#   openssl req -x509 -new -key ca.key -sha256 -days 36500 \
#     -subj "/CN=Celerite Test CA" -out ca.pem
#   openssl genrsa -out server.key 2048
#   openssl req -new -key server.key -subj "/CN=localhost" -out server.csr
#   openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
#     -days 36500 -sha256 -extfile server_ext.cnf -out server.pem
#     # server_ext.cnf: subjectAltName=DNS:localhost,IP:127.0.0.1
#     #                 extendedKeyUsage=serverAuth
#   openssl genrsa -out client.key 2048
#   openssl req -new -key client.key -subj "/CN=celerite-client" -out client.csr
#   openssl x509 -req -in client.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
#     -days 36500 -sha256 -extfile client_ext.cnf -out client.pem
#     # client_ext.cnf: extendedKeyUsage=clientAuth keyUsage=digitalSignature
#   copy /b client.pem+client.key client-combined.pem
#   copy client.pem client-cert-only.pem

private def tls_fixture(name : String) : String
  File.expand_path(File.join("fixtures", "tls", name), __DIR__)
end

# Minimal HTTP-over-TLS server that demands a client certificate, so the
# positive case only succeeds when Downloader/HttpFetcher really install the
# client key.
private class ClientCertServer
  getter port : Int32

  def initialize(@body : String)
    ctx = OpenSSL::SSL::Context::Server.new
    ctx.certificate_chain = tls_fixture("server.pem")
    ctx.private_key = tls_fixture("server.key")
    ctx.ca_certificates = tls_fixture("ca.pem")
    ctx.verify_mode = OpenSSL::SSL::VerifyMode::PEER | OpenSSL::SSL::VerifyMode::FAIL_IF_NO_PEER_CERT

    @tcp = TCPServer.new("127.0.0.1", 0)
    @port = @tcp.local_address.as(Socket::IPAddress).port
    @ssl = OpenSSL::SSL::Server.new(@tcp, ctx)
  end

  def start : Nil
    spawn do
      loop do
        socket =
          begin
            @ssl.accept?
          rescue
            # A rejected handshake (missing/incomplete client cert) must not
            # kill the accept loop.
            next
          end
        break if socket.nil?
        begin
          respond(socket)
        rescue
        ensure
          socket.close rescue nil
        end
      end
    end
  end

  def close : Nil
    @tcp.close rescue nil
  end

  private def respond(socket) : Nil
    while (line = socket.gets("\r\n", chomp: false)) && line != "\r\n"
    end
    socket.print "HTTP/1.1 200 OK\r\n" \
                 "Content-Type: application/octet-stream\r\n" \
                 "Content-Length: #{@body.bytesize}\r\n" \
                 "Connection: close\r\n\r\n" \
                 "#{@body}"
    socket.flush
  end
end

private def with_client_cert_server(body : String, & : Int32 ->) : Nil
  server = ClientCertServer.new(body)
  server.start
  begin
    yield server.port
  ensure
    server.close
  end
end

private def with_cache_root(& : String ->) : Nil
  dir = File.tempname("celerite-mtls-spec")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

private def fetch_error(downloader : Celerite::Downloader) : Exception?
  downloader.fetch("demo", "1.0.0", nil, nil)
  nil
rescue ex
  ex
end

describe Celerite::TLS do
  it "presents a client certificate and key stored in one PEM" do
    body = "celerite-mtls-gem-bytes"
    with_client_cert_server(body) do |port|
      with_cache_root do |cache_root|
        remote = "https://127.0.0.1:#{port}"
        downloader = Celerite::Downloader.new(remote, cache_root, 0, nil, tls_fixture("ca.pem"), tls_fixture("client-combined.pem"), nil, timeout: 5)
        path = downloader.fetch("demo", "1.0.0", nil, nil)
        File.read(path).should eq(body)
      end
    end
  end

  it "fails when the PEM carries no client private key" do
    with_client_cert_server("nope") do |port|
      with_cache_root do |cache_root|
        remote = "https://127.0.0.1:#{port}"
        downloader = Celerite::Downloader.new(remote, cache_root, 0, nil, tls_fixture("ca.pem"), tls_fixture("client-cert-only.pem"), nil, timeout: 5)
        fetch_error(downloader).should_not be_nil
      end
    end
  end

  it "fails when no client certificate is configured" do
    with_client_cert_server("nope") do |port|
      with_cache_root do |cache_root|
        remote = "https://127.0.0.1:#{port}"
        downloader = Celerite::Downloader.new(remote, cache_root, 0, nil, tls_fixture("ca.pem"), nil, nil, timeout: 5)
        fetch_error(downloader).should_not be_nil
      end
    end
  end

  it "tolerates a certificate-only PEM and an empty path" do
    ctx = OpenSSL::SSL::Context::Client.new
    Celerite::TLS.configure_client_certificate(ctx, "")
    Celerite::TLS.configure_client_certificate(ctx, tls_fixture("client-cert-only.pem"))
  end

  it "wires the same client certificate through the compact index fetcher" do
    body = "celerite-mtls-index-body"
    with_client_cert_server(body) do |port|
      remote = "https://127.0.0.1:#{port}"
      fetcher = Celerite::CompactIndex::HttpFetcher.for(
        remote, nil, 0, nil, tls_fixture("ca.pem"), tls_fixture("client-combined.pem"), nil, timeout: 5)
      response = fetcher.call("/gems/demo-1.0.0.gem", {} of String => String)
      response.status.should eq(200)
      response.body.should eq(body)
    end
  end
end
