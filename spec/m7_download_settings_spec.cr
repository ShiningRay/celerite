require "./spec_helper"
require "../src/celerite"
require "../src/celerite/downloader"
require "../src/celerite/errors"
require "../src/celerite/mirror"
require "http/server"

# A local port that was bound and immediately closed, so TCP connects to it
# fail fast (used as an unreachable mirror).
def mirror_test_closed_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.as(Socket::IPAddress).port
  server.close
  port
end

# Mirror settings keyed exactly like Config#key_for/`mirror_for` expect
# (`BUNDLE_MIRROR__<URL>` and `...__FALLBACK_TIMEOUT`).
def mirror_test_config(remote : String, mirror : String, fallback : String? = nil) : Hash(String, Celerite::Config::Value)
  config = {Celerite::Config.key_for("mirror.#{remote}") => mirror} of String => Celerite::Config::Value
  if fallback
    config[Celerite::Config.key_for("mirror.#{remote}.fallback_timeout")] = fallback
  end
  config
end

module Celerite
  describe Commands do
    describe ".ssl_option" do
      it "returns nil for missing/empty values and the value otherwise" do
        empty = Config.new
        Commands.ssl_option(empty, "ssl_ca_cert").should be_nil

        blank = Config.new(nil, {"BUNDLE_SSL_CA_CERT" => ""} of String => Config::Value)
        Commands.ssl_option(blank, "ssl_ca_cert").should be_nil

        valued = Config.new(nil, {"BUNDLE_SSL_CA_CERT" => "/path/to/ca.pem"} of String => Config::Value)
        Commands.ssl_option(valued, "ssl_ca_cert").should eq("/path/to/ca.pem")
      end
    end

    describe ".timeout_seconds" do
      it "defaults to 10 and normalizes explicit/invalid values" do
        empty = Config.new
        Commands.timeout_seconds(empty).should eq(10)

        explicit = Config.new(nil, {"BUNDLE_TIMEOUT" => 3} of String => Config::Value)
        Commands.timeout_seconds(explicit).should eq(3)

        invalid = Config.new(nil, {"BUNDLE_TIMEOUT" => 0} of String => Config::Value)
        Commands.timeout_seconds(invalid).should eq(10)

        negative = Config.new(nil, {"BUNDLE_TIMEOUT" => -5} of String => Config::Value)
        Commands.timeout_seconds(negative).should eq(10)
      end
    end

    describe ".unsupported_setting_error" do
      it "does not warn when a proxy env var is set (routing is supported)" do
        previous = ENV["HTTP_PROXY"]?
        begin
          ENV["HTTP_PROXY"] = "http://proxy.example:8080"
          stderr = IO::Memory.new
          config = Config.new
          Commands.unsupported_setting_error(config, stderr).should be_nil
          stderr.to_s.should be_empty
        ensure
          if previous
            ENV["HTTP_PROXY"] = previous
          else
            ENV.delete("HTTP_PROXY")
          end
        end
      end

      it "accepts an explicitly configured proxy" do
        stderr = IO::Memory.new
        config = Config.new(nil, {"BUNDLE_PROXY" => "http://proxy.example:8080"} of String => Config::Value)
        Commands.unsupported_setting_error(config, stderr).should be_nil
      end
    end
  end

  describe Downloader do
    it "exposes the configured timeout as connect_timeout" do
      downloader = Downloader.new("https://rubygems.org", Dir.tempdir, timeout: 1)
      downloader.timeout.should eq(1)
      downloader.connect_timeout.should eq(1.second)
    end
  end

  describe DownloadError do
    it "carries the redirect limit and URL in its message" do
      ex = DownloadError.new("Too many redirects (>5) for https://example.test/gems/foo-1.0.0.gem")
      ex.message.not_nil!.should contain("Too many redirects")
      ex.message.not_nil!.should contain(">5")
      ex.message.not_nil!.should contain("https://example.test/gems/foo-1.0.0.gem")
    end
  end

  describe Mirror do
    describe ".fallback_timeout_seconds" do
      it "maps true/false/numeric/nil like Bundler's Mirror#fallback_timeout=" do
        Mirror.fallback_timeout_seconds(nil).should be_nil
        Mirror.fallback_timeout_seconds(true).should eq(0.1)
        Mirror.fallback_timeout_seconds("true").should eq(0.1)
        Mirror.fallback_timeout_seconds(false).should eq(0.0)
        Mirror.fallback_timeout_seconds("false").should eq(0.0)
        Mirror.fallback_timeout_seconds("2").should eq(2.0)
        Mirror.fallback_timeout_seconds(2).should eq(2.0)
      end

      it "truncates the numeric branch to whole seconds like Bundler's to_i" do
        Mirror.fallback_timeout_seconds("2.5").should eq(2.0)
        Mirror.fallback_timeout_seconds("0.5").should eq(0.0)
        Mirror.fallback_timeout_seconds("abc").should eq(0.0)
      end
    end

    describe ".reachable?" do
      it "accepts an open TCP port and rejects a closed one" do
        server = TCPServer.new("127.0.0.1", 0)
        begin
          open_port = server.local_address.as(Socket::IPAddress).port
          Mirror.reachable?("http://127.0.0.1:#{open_port}", 1.0).should be_true
        ensure
          server.close unless server.closed?
        end

        closed_port = mirror_test_closed_port
        Mirror.reachable?("http://127.0.0.1:#{closed_port}", 1.0).should be_false
      end

      it "skips probing for non-positive timeouts" do
        Mirror.reachable?("http://127.0.0.1:1", 0.0).should be_true
        Mirror.reachable?("http://127.0.0.1:1", -1.0).should be_true
      end
    end

    describe ".resolve" do
      it "returns nil when no mirror is configured" do
        config = Config.new(nil, {} of String => Config::Value)
        Mirror.resolve(config, "https://rubygems.org/").should be_nil
      end

      it "keeps an unreachable mirror when no fallback_timeout is configured" do
        remote = "https://rubygems.org/"
        mirror = "http://127.0.0.1:#{mirror_test_closed_port}"
        config = Config.new(nil, mirror_test_config(remote, mirror))
        Mirror.resolve(config, remote).should eq(mirror)
      end

      it "drops an unreachable mirror configured with a fallback_timeout" do
        remote = "https://rubygems.org/"
        mirror = "http://127.0.0.1:#{mirror_test_closed_port}"
        config = Config.new(nil, mirror_test_config(remote, mirror, "1"))
        Mirror.resolve(config, remote).should be_nil
      end

      it "keeps an unreachable mirror when fallback_timeout is 0" do
        remote = "https://rubygems.org/"
        mirror = "http://127.0.0.1:#{mirror_test_closed_port}"
        config = Config.new(nil, mirror_test_config(remote, mirror, "0"))
        Config.fallback_timeout_seconds("0").should eq(0.0)
        Mirror.resolve(config, remote).should eq(mirror)
      end

      it "reads fallback_timeout from a .bundle/config file" do
        remote = "https://rubygems.org/"
        mirror = "http://127.0.0.1:#{mirror_test_closed_port}"
        dir = File.tempname("celerite-mirror-spec")
        Dir.mkdir_p(File.join(dir, ".bundle"))
        begin
          File.write(File.join(dir, ".bundle", "config"),
            "---\n" \
            "#{Config.key_for("mirror.#{remote}")}: \"#{mirror}\"\n" \
            "#{Config.key_for("mirror.#{remote}.fallback_timeout")}: \"2\"\n")

          config = Config.new(dir)
          config.mirror_fallback_timeout(remote).should eq(2.0)
          Mirror.resolve(config, remote).should be_nil
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "keeps a reachable mirror configured with a fallback_timeout" do
        remote = "https://rubygems.org/"
        server = TCPServer.new("127.0.0.1", 0)
        begin
          port = server.local_address.as(Socket::IPAddress).port
          mirror = "http://127.0.0.1:#{port}"
          config = Config.new(nil, mirror_test_config(remote, mirror, "1"))
          Mirror.resolve(config, remote).should eq(mirror)
        ensure
          server.close unless server.closed?
        end
      end
    end

    it "downloads from the original remote when the mirror is unreachable" do
      gem_bytes = "celerite-spec-gem-bytes"
      server = HTTP::Server.new do |context|
        if context.request.path == "/gems/demo-1.0.0.gem"
          context.response.content_type = "application/octet-stream"
          context.response.print gem_bytes
        else
          context.response.status_code = 404
        end
      end
      address = server.bind_tcp("127.0.0.1", 0)
      spawn { server.listen }
      begin
        remote = "http://127.0.0.1:#{address.port}"
        mirror = "http://127.0.0.1:#{mirror_test_closed_port}"
        config = Config.new(nil, mirror_test_config(remote, mirror, "1"))
        cache_root = File.tempname("celerite-mirror-spec")
        Dir.mkdir_p(cache_root)
        begin
          resolved = Celerite::Mirror.resolve(config, remote)
          resolved.should be_nil

          downloader = Downloader.new(remote, cache_root, 1, resolved, timeout: 1)
          path = downloader.fetch("demo", "1.0.0", nil, nil)
          File.read(path).should eq(gem_bytes)
        ensure
          FileUtils.rm_rf(cache_root)
        end
      ensure
        server.close
      end
    end
  end
end
