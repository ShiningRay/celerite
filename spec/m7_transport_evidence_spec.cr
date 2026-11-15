require "./spec_helper"
require "http/server"
require "openssl"
require "../src/celerite/downloader"

# M7(4) transport evidence: real 3xx following, retry counts, and
# `ssl_verify_mode` handshake outcomes. Every server is local (127.0.0.1) and
# the gem bytes come from an existing fixture, so the spec is offline.

private TRANSPORT_GEM_NAME    = "net-protocol"
private TRANSPORT_GEM_VERSION = "0.2.2"
private TRANSPORT_GEM_FILE    = "net-protocol-0.2.2.gem"

private def transport_gem_path : String
  File.expand_path("fixtures/locked-deps/gems/#{TRANSPORT_GEM_FILE}", __DIR__)
end

private def transport_gem_bytes : Bytes
  File.read(transport_gem_path).to_slice
end

private def with_transport_dir(&)
  dir = File.tempname("celerite-transport")
  Dir.mkdir_p(dir)
  yield dir
end

private def transport_fetch(downloader : Celerite::Downloader) : String
  downloader.fetch(TRANSPORT_GEM_NAME, TRANSPORT_GEM_VERSION, nil, nil)
end

private def tls_fixture(name : String) : String
  File.expand_path("fixtures/tls/#{name}", __DIR__)
end

describe "M7(4) transport evidence" do
  it "follows a 302 redirect with a relative Location" do
    bytes = transport_gem_bytes
    paths = [] of String
    server = HTTP::Server.new do |ctx|
      paths << ctx.request.path
      if ctx.request.path.starts_with?("/real/")
        ctx.response.content_type = "application/octet-stream"
        ctx.response.write(bytes)
      else
        ctx.response.status = HTTP::Status::FOUND
        ctx.response.headers["Location"] = "/real/#{File.basename(ctx.request.path)}"
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("http://127.0.0.1:#{address.port}/", dir, 0, timeout: 5)
        fetched = transport_fetch(downloader)
        File.read(fetched).to_slice.should eq(bytes)
        paths.should eq(["/gems/#{TRANSPORT_GEM_FILE}", "/real/#{TRANSPORT_GEM_FILE}"])
      end
    ensure
      server.close
    end
  end

  it "stops at the redirect limit with max_redirects: 0" do
    server = HTTP::Server.new do |ctx|
      ctx.response.status = HTTP::Status::FOUND
      ctx.response.headers["Location"] = "/gems/#{TRANSPORT_GEM_FILE}"
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("http://127.0.0.1:#{address.port}/", dir, 0, timeout: 5, max_redirects: 0)
        expect_raises(Celerite::DownloadError, /Too many redirects \(>0\)/) do
          transport_fetch(downloader)
        end
      end
    ensure
      server.close
    end
  end

  it "retries transient failures and records three server-side requests" do
    bytes = transport_gem_bytes
    attempts = 0
    server = HTTP::Server.new do |ctx|
      attempts += 1
      if attempts < 3
        ctx.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
      else
        ctx.response.write(bytes)
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("http://127.0.0.1:#{address.port}/", dir, 2, timeout: 5)
        fetched = transport_fetch(downloader)
        File.read(fetched).to_slice.should eq(bytes)
        attempts.should eq(3)
      end
    ensure
      server.close
    end
  end

  it "gives up after a single request when retries: 0" do
    attempts = 0
    server = HTTP::Server.new do |ctx|
      attempts += 1
      ctx.response.status = HTTP::Status::NOT_FOUND
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("http://127.0.0.1:#{address.port}/", dir, 0, timeout: 5)
        expect_raises(Celerite::GemNotFoundError, /Could not fetch gem/) do
          transport_fetch(downloader)
        end
        attempts.should eq(1)
      end
    ensure
      server.close
    end
  end

  it "accepts a self-signed certificate when ssl_verify_mode is none" do
    bytes = transport_gem_bytes
    with_tls_gem_server(bytes) do |port|
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("https://127.0.0.1:#{port}/", dir, 0, ssl_verify_mode: "none", timeout: 5)
        File.read(transport_fetch(downloader)).to_slice.should eq(bytes)
      end
    end
  end

  it "rejects a self-signed certificate by default (peer verification)" do
    with_tls_gem_server(transport_gem_bytes) do |port|
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("https://127.0.0.1:#{port}/", dir, 0, timeout: 5)
        # Bundler maps verification failures to CertificateFailureError (exit
        # 17); see spec/m7_certificate_failure_spec.cr.
        error = expect_raises(Celerite::CertificateFailureError) do
          transport_fetch(downloader)
        end
        error.message.not_nil!.should contain(
          "Could not verify the SSL certificate for https://127.0.0.1:#{port}/."
        )
      end
    end
  end

  it "accepts the self-signed certificate when its CA is configured" do
    bytes = transport_gem_bytes
    with_tls_gem_server(bytes) do |port|
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new(
          "https://127.0.0.1:#{port}/", dir, 0,
          ssl_ca_cert: tls_fixture("ca.pem"), timeout: 5)
        File.read(transport_fetch(downloader)).to_slice.should eq(bytes)
      end
    end
  end
end

describe "M7(4) retry policy evidence" do
  # Bundler's gem-download path wraps `fetch_path` in
  # `Bundler::Retry.new("download gem from ...")` with no exception allow-list
  # (bundler/rubygems_integration.rb:384; retry.rb:55 retries every
  # StandardError), so a 404 from the gem endpoint is retried there too.
  it "retries 404 for gem downloads like Bundler's download_gem wrapper" do
    attempts = 0
    server = HTTP::Server.new do |ctx|
      attempts += 1
      ctx.response.status = HTTP::Status::NOT_FOUND
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("http://127.0.0.1:#{address.port}/", dir, 2, timeout: 5)
        expect_raises(Celerite::GemNotFoundError, /Could not fetch gem/) do
          transport_fetch(downloader)
        end
        attempts.should eq(3)
      end
    ensure
      server.close
    end
  end

  it "keeps retrying 500 until the retry budget is exhausted" do
    attempts = 0
    server = HTTP::Server.new do |ctx|
      attempts += 1
      ctx.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      with_transport_dir do |dir|
        downloader = Celerite::Downloader.new("http://127.0.0.1:#{address.port}/", dir, 2, timeout: 5)
        expect_raises(Celerite::GemNotFoundError, /Could not fetch gem/) do
          transport_fetch(downloader)
        end
        attempts.should eq(3)
      end
    ensure
      server.close
    end
  end
end

private def with_tls_gem_server(bytes : Bytes, &)
  context = OpenSSL::SSL::Context::Server.new
  context.certificate_chain = tls_fixture("server.pem")
  context.private_key = tls_fixture("server.key")
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
