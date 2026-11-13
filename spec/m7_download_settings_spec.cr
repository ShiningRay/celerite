require "./spec_helper"
require "../src/celerite"
require "../src/celerite/downloader"
require "../src/celerite/errors"

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
      it "warns but continues when a proxy env var is set" do
        previous = ENV["HTTP_PROXY"]?
        begin
          ENV["HTTP_PROXY"] = "http://proxy.example:8080"
          stderr = IO::Memory.new
          config = Config.new
          Commands.unsupported_setting_error(config, stderr).should be_nil
          stderr.to_s.should contain("warning: HTTP proxy (HTTP_PROXY) is set but Celerite does not route through proxies")
        ensure
          if previous
            ENV["HTTP_PROXY"] = previous
          else
            ENV.delete("HTTP_PROXY")
          end
        end
      end

      it "fails fast when proxy is explicitly configured" do
        stderr = IO::Memory.new
        config = Config.new(nil, {"BUNDLE_PROXY" => "http://proxy.example:8080"} of String => Config::Value)
        error = Commands.unsupported_setting_error(config, stderr)
        error.should eq("not supported by Celerite: proxy")
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
end
