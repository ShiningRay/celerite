require "http/client"
require "socket"
require "openssl"
require "./proxy"

module Celerite
  # Minimal GET transport that can route through an HTTP proxy.
  #
  # Direct requests keep using `HTTP::Client` unchanged. Proxied requests use a
  # raw socket: plain HTTP is sent with an absolute request target, HTTPS is
  # tunneled with `CONNECT` and wrapped in TLS (SNI = origin host) using the
  # caller's context. Responses are parsed with `HTTP::Client::Response.from_io`
  # so callers keep the same contract as `HTTP::Client#get` (body already read
  # when the response is returned).
  #
  # One connection per request: neither `Downloader` nor the compact index
  # fetcher keeps persistent connections, so no pooling is lost.
  module HttpTransport
    def self.get(uri : URI, path : String, headers : HTTP::Headers = HTTP::Headers.new,
                 tls : OpenSSL::SSL::Context::Client? = nil, proxy : Proxy? = nil,
                 timeout : Int32 = 30, connect_timeout : Int32? = nil) : HTTP::Client::Response
      host = uri.host || raise ArgumentError.new("missing host in #{uri}")
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
      if proxy && !proxy.bypass?(host, port)
        proxied_get(uri, path, headers, tls, proxy, timeout, connect_timeout)
      else
        direct_get(uri, path, headers, tls, timeout, connect_timeout)
      end
    end

    private def self.direct_get(uri : URI, path : String, headers : HTTP::Headers,
                                tls : OpenSSL::SSL::Context::Client?, timeout : Int32,
                                connect_timeout : Int32?) : HTTP::Client::Response
      client = HTTP::Client.new(uri, tls: tls)
      client.connect_timeout = (connect_timeout || timeout).seconds
      client.read_timeout = timeout.seconds
      begin
        client.get(path, headers: headers)
      ensure
        client.close rescue nil
      end
    end

    private def self.proxied_get(uri : URI, path : String, headers : HTTP::Headers,
                                 tls : OpenSSL::SSL::Context::Client?, proxy : Proxy,
                                 timeout : Int32, connect_timeout : Int32?) : HTTP::Client::Response
      host = uri.host.not_nil!
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
      socket = TCPSocket.new(proxy.host, proxy.port,
        connect_timeout: (connect_timeout || timeout).seconds)
      socket.read_timeout = timeout.seconds
      channel : IO = socket
      begin
        if uri.scheme == "https"
          channel = open_tunnel(socket, tls, host, port, proxy)
        end
        target = uri.scheme == "https" ? path : absolute_target(uri, port, path)
        write_request(channel, target, host, port, uri.scheme == "https" ? 443 : 80, headers, proxy)
        HTTP::Client::Response.from_io(channel, ignore_body: false, decompress: true)
      ensure
        channel.close rescue nil
        socket.close rescue nil
      end
    end

    # Establish a CONNECT tunnel and wrap the socket in TLS for the origin.
    private def self.open_tunnel(socket : TCPSocket, tls : OpenSSL::SSL::Context::Client?,
                                 host : String, port : Int32, proxy : Proxy) : IO
      authority = "#{host}:#{port}"
      request = "CONNECT #{authority} HTTP/1.1\r\nHost: #{authority}\r\n"
      if auth = proxy.authorization
        request += "Proxy-Authorization: #{auth}\r\n"
      end
      request += "\r\n"
      socket << request
      socket.flush

      status_line = socket.gets("\r\n")
      raise Error.new("proxy CONNECT to #{authority} failed: no response") unless status_line
      status = status_line.split(" ")[1]?.try(&.to_i?) || 0
      unless status >= 200 && status < 300
        raise Error.new("proxy CONNECT to #{authority} failed: #{status_line.strip}")
      end
      while (line = socket.gets("\r\n"))
        break if line == "\r\n" || line.empty?
      end
      context = tls || OpenSSL::SSL::Context::Client.new
      OpenSSL::SSL::Socket::Client.new(socket, context: context, hostname: host, sync_close: true)
    end

    private def self.absolute_target(uri : URI, port : Int32, path : String) : String
      host = uri.host.not_nil!
      default_port = uri.scheme == "https" ? 443 : 80
      authority = port == default_port ? host : "#{host}:#{port}"
      "#{uri.scheme}://#{authority}#{path}"
    end

    private def self.write_request(io : IO, target : String, host : String, port : Int32,
                                   default_port : Int32, headers : HTTP::Headers, proxy : Proxy?) : Nil
      io << "GET " << target << " HTTP/1.1\r\n"
      unless headers.has_key?("Host")
        authority = port == default_port ? host : "#{host}:#{port}"
        io << "Host: " << authority << "\r\n"
      end
      headers.each do |name, values|
        values.each { |value| io << name << ": " << value << "\r\n" }
      end
      unless headers.has_key?("Proxy-Authorization")
        if auth = proxy.try(&.authorization)
          io << "Proxy-Authorization: " << auth << "\r\n"
        end
      end
      io << "Connection: close\r\n\r\n"
      io.flush
    end
  end
end
