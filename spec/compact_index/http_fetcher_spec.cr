require "../spec_helper"
require "../../src/celerite/compact_index/cache"
require "http/server"
require "base64"

module Celerite
  # Local HTTP server used to prove that credentials, mirrors and retries on
  # `HttpFetcher` take effect against a real socket (not just by argument
  # plumbing).
  class AuthTestServer
    getter port : Int32
    getter requests : Array(String)
    @server : HTTP::Server

    def initialize(expected_auth : String?, body : String, status : Int32 = 200, fail_first : Int32 = 0)
      @requests = [] of String
      @expected_auth = expected_auth
      @body = body
      @status = status
      @fail_first = fail_first
      @closed = false
      server = HTTP::Server.new do |context|
        auth = context.request.headers["Authorization"]?
        @requests << (auth || "")
        if @expected_auth && auth != @expected_auth
          context.response.status_code = 401
          context.response.print "unauthorized"
        elsif @fail_first > 0
          @fail_first -= 1
          context.response.status_code = 500
          context.response.print "boom"
        else
          context.response.status_code = @status
          context.response.print @body
        end
        context.response.close
      end
      address = server.bind_tcp("127.0.0.1", 0)
      @port = address.port
      @server = server
      spawn do
        server.listen
      end
      sleep 20.milliseconds
    end

    def close : Nil
      return if @closed
      @closed = true
      @server.close
    end
  end

  describe CompactIndex::HttpFetcher do
    it "sends resolved credentials and applies configured retries" do
      server = AuthTestServer.new("Basic #{Base64.strict_encode("user:s3cret")}", "---\n")
      begin
        fetcher = CompactIndex::HttpFetcher.for(
          "http://127.0.0.1:#{server.port}/", {"user", "s3cret"}, retries: 0
        )
        response = fetcher.call("/info/demo", {} of String => String)
        response.status.should eq(200)
        response.body.should eq("---\n")
        server.requests.size.should eq(1)
        server.requests.first.should eq("Basic #{Base64.strict_encode("user:s3cret")}")
      ensure
        server.close
      end
    end

    it "fails without credentials when the remote requires them" do
      server = AuthTestServer.new("Basic #{Base64.strict_encode("user:s3cret")}", "---\n")
      begin
        fetcher = CompactIndex::HttpFetcher.for("http://127.0.0.1:#{server.port}/", nil, retries: 0)
        response = fetcher.call("/info/demo", {} of String => String)
        response.status.should eq(401)
      ensure
        server.close
      end
    end

    it "retries a failing HTTP status before succeeding" do
      server = AuthTestServer.new(nil, "---\n", fail_first: 1)
      begin
        fetcher = CompactIndex::HttpFetcher.for("http://127.0.0.1:#{server.port}/", nil, retries: 1)
        response = fetcher.call("/versions", {} of String => String)
        response.status.should eq(200)
        # one 500 followed by the successful retry
        server.requests.size.should eq(2)
      ensure
        server.close
      end
    end

    it "falls back to the original remote when the mirror answers an error" do
      mirror = AuthTestServer.new(nil, "mirror", status: 500)
      origin = AuthTestServer.new(nil, "origin")
      begin
        fetcher = CompactIndex::HttpFetcher.for(
          "http://127.0.0.1:#{origin.port}/", nil, retries: 0,
          mirror_url: "http://127.0.0.1:#{mirror.port}/"
        )
        response = fetcher.call("/versions", {} of String => String)
        response.body.should eq("origin")
        mirror.requests.size.should eq(1)
        origin.requests.size.should eq(1)
      ensure
        mirror.close
        origin.close
      end
    end

    it "uses the mirror when it answers successfully" do
      mirror = AuthTestServer.new(nil, "mirror")
      origin = AuthTestServer.new(nil, "origin")
      begin
        fetcher = CompactIndex::HttpFetcher.for(
          "http://127.0.0.1:#{origin.port}/", nil, retries: 0,
          mirror_url: "http://127.0.0.1:#{mirror.port}/"
        )
        response = fetcher.call("/versions", {} of String => String)
        response.body.should eq("mirror")
        origin.requests.should be_empty
      ensure
        mirror.close
        origin.close
      end
    end
  end
end
