require "./spec_helper"
require "http/server"
require "../src/celerite/downloader"

# Minimal recording proxy: plain HTTP requests arrive with an absolute request
# target (and are relayed origin-form to the target), HTTPS requests arrive as
# CONNECT and are tunneled byte-for-byte after a 200 response.
class RecordingProxy
  getter port : Int32
  getter requests : Array(String)

  def initialize
    @requests = [] of String
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.local_address.port
    spawn do
      loop do
        socket = @server.accept?
        break unless socket
        spawn handle(socket)
      end
    end
  end

  def url : String
    "http://127.0.0.1:#{@port}"
  end

  def close : Nil
    @server.close rescue nil
  end

  private def handle(socket : TCPSocket) : Nil
    request_line = socket.gets("\r\n") || return
    @requests << request_line
    headers = HTTP::Headers.new
    while (line = socket.gets("\r\n"))
      break if line == "\r\n" || line.empty?
      name, value = line.split(":", 2)
      headers[name.strip] = value.strip if value
    end

    if request_line.starts_with?("CONNECT ")
      target = request_line.split(" ")[1]
      split_at = target.rindex(":").not_nil!
      host = target[0, split_at]
      port = target[split_at + 1..]
      socket << "HTTP/1.1 200 Connection Established\r\n\r\n"
      socket.flush
      upstream = TCPSocket.new(host, port.to_i)
      spawn pump(upstream, socket)
      pump(socket, upstream)
    else
      method, uri_text, version = request_line.split(" ")
      uri = URI.parse(uri_text)
      upstream = TCPSocket.new(uri.host.not_nil!, uri.port || 80)
      upstream << "#{method} #{uri.request_target || "/"} #{version}\r\n"
      headers.each do |name, values|
        values.each { |value| upstream << "#{name}: #{value}\r\n" }
      end
      upstream << "Connection: close\r\n\r\n"
      upstream.flush
      pump(upstream, socket)
      upstream.close rescue nil
      socket.close rescue nil
    end
  rescue
    # client disconnects are expected at the end of a request
  ensure
    socket.close rescue nil
  end

  private def pump(from : IO, to : IO) : Nil
    buffer = Bytes.new(16_384)
    while (read = from.read(buffer)) > 0
      to.write(buffer[0, read])
      to.flush
    end
  rescue
  ensure
    to.close rescue nil
    from.close rescue nil
  end
end

private def with_proxy_and_origin(& : RecordingProxy, HTTP::Server, Int32 ->)
  proxy = RecordingProxy.new
  origin = HTTP::Server.new do |ctx|
    if ctx.request.path == "/gems/demo-1.0.0.gem"
      ctx.response.content_type = "application/octet-stream"
      ctx.response.print("proxy-spec-gem-bytes")
    else
      ctx.response.status_code = 404
    end
  end
  probe = TCPServer.new("127.0.0.1", 0)
  port = probe.local_address.port
  probe.close
  origin.bind_tcp("127.0.0.1", port)
  spawn origin.listen
  begin
    yield proxy, origin, port
  ensure
    proxy.close
    origin.close
  end
end

describe "Celerite proxy routing" do
  it "routes gem downloads through http_proxy with an absolute request target" do
    with_proxy_and_origin do |proxy, _origin, port|
      previous = ENV["http_proxy"]?
      ENV["http_proxy"] = proxy.url
      begin
        dir = File.tempname("celerite-proxy-spec")
        Dir.mkdir_p(dir)
        begin
          downloader = Celerite::Downloader.new("http://127.0.0.1:#{port}/", dir, 0, timeout: 5)
          path = downloader.fetch("demo", "1.0.0", nil, nil)
          File.read(path).should eq("proxy-spec-gem-bytes")
          proxy.requests.size.should eq(1)
          proxy.requests.first.should contain("GET http://127.0.0.1:#{port}/gems/demo-1.0.0.gem")
        ensure
          FileUtils.rm_rf(dir)
        end
      ensure
        if previous
          ENV["http_proxy"] = previous
        else
          ENV.delete("http_proxy")
        end
      end
    end
  end

  it "tunnels https gem downloads through CONNECT" do
    with_tls_origin do |proxy, _origin, port|
      with_env({"http_proxy" => proxy.url, "no_proxy" => nil}) do
        ca = File.expand_path("fixtures/tls/ca.pem", __DIR__)
        dir = File.tempname("celerite-proxy-spec")
        Dir.mkdir_p(dir)
        begin
          downloader = Celerite::Downloader.new("https://127.0.0.1:#{port}/", dir, 0, ssl_ca_cert: ca, timeout: 5)
          path = downloader.fetch("demo", "1.0.0", nil, nil)
          File.read(path).should eq("proxy-spec-gem-bytes")
          proxy.requests.first.should contain("CONNECT 127.0.0.1:#{port}")
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  end

  it "bypasses the proxy when no_proxy matches host:port" do
    with_proxy_and_origin do |proxy, _origin, port|
      with_env({"http_proxy" => proxy.url, "no_proxy" => "127.0.0.1:#{port}"}) do
        dir = File.tempname("celerite-proxy-spec")
        Dir.mkdir_p(dir)
        begin
          downloader = Celerite::Downloader.new("http://127.0.0.1:#{port}/", dir, 0, timeout: 5)
          path = downloader.fetch("demo", "1.0.0", nil, nil)
          File.read(path).should eq("proxy-spec-gem-bytes")
          proxy.requests.size.should eq(0)
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  end

  it "connects directly when no_proxy is *" do
    with_proxy_and_origin do |proxy, _origin, port|
      with_env({"http_proxy" => proxy.url, "no_proxy" => "*"}) do
        dir = File.tempname("celerite-proxy-spec")
        Dir.mkdir_p(dir)
        begin
          downloader = Celerite::Downloader.new("http://127.0.0.1:#{port}/", dir, 0, timeout: 5)
          path = downloader.fetch("demo", "1.0.0", nil, nil)
          File.read(path).should eq("proxy-spec-gem-bytes")
          proxy.requests.size.should eq(0)
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  end

  it "prefers the config proxy over the environment" do
    proxy = RecordingProxy.new
    begin
      values = {} of String => Celerite::Config::Value
      values["BUNDLE_PROXY"] = proxy.url
      config = Celerite::Config.new(nil, values)
      resolved = Celerite::Proxy.resolve(config)
      resolved.not_nil!.host.should eq("127.0.0.1")
      resolved.not_nil!.port.should eq(proxy.port)
    ensure
      proxy.close
    end
  end

  it "ignores https_proxy and ALL_PROXY" do
    with_env({"http_proxy" => nil, "https_proxy" => "http://127.0.0.1:1", "ALL_PROXY" => "http://127.0.0.1:1"}) do
      Celerite::Proxy.from_environment.should be_nil
    end
  end

  it "adds the http scheme to schemeless proxy URLs" do
    with_env({"http_proxy" => "127.0.0.1:3128"}) do
      proxy = Celerite::Proxy.from_environment.not_nil!
      proxy.host.should eq("127.0.0.1")
      proxy.port.should eq(3128)
    end
  end
end

private def with_tls_origin(& : RecordingProxy, HTTP::Server, Int32 ->)
  proxy = RecordingProxy.new
  context = OpenSSL::SSL::Context::Server.new
  context.certificate_chain = File.expand_path("fixtures/tls/server.pem", __DIR__)
  context.private_key = File.expand_path("fixtures/tls/server.key", __DIR__)
  origin = HTTP::Server.new do |ctx|
    if ctx.request.path == "/gems/demo-1.0.0.gem"
      ctx.response.content_type = "application/octet-stream"
      ctx.response.print("proxy-spec-gem-bytes")
    else
      ctx.response.status_code = 404
    end
  end
  probe = TCPServer.new("127.0.0.1", 0)
  port = probe.local_address.port
  probe.close
  origin.bind_tls("127.0.0.1", port, context)
  spawn origin.listen
  begin
    yield proxy, origin, port
  ensure
    proxy.close
    origin.close
  end
end

private def with_env(pairs : Hash(String, String?), &)
  saved = {} of String => String?
  pairs.each do |key, value|
    saved[key] = ENV[key]?
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
  begin
    yield
  ensure
    saved.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end
