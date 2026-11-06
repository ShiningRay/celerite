require "./spec_helper"
require "../src/celerite"

module Celerite
  describe Config do
    it "normalizes keys like the reference" do
      Config.key_for("path").should eq("BUNDLE_PATH")
      Config.key_for("path.system").should eq("BUNDLE_PATH__SYSTEM")
      Config.key_for("BUNDLE_FROZEN").should eq("BUNDLE_FROZEN")
      Config.key_for("mirror.https://rubygems.org").should eq("BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG")
    end

    it "respects priority temporary > local > env > global > default" do
      dir = File.tempname("celerite-spec", "cfg")
      Dir.mkdir_p(dir)
      begin
        Dir.mkdir_p(File.join(dir, ".bundle"))
        File.write(File.join(dir, ".bundle", "config"), "---\nBUNDLE_FROZEN: \"false\"\nBUNDLE_JOBS: \"4\"\n")
        config = Config.new(dir, {"BUNDLE_JOBS" => 8} of String => Config::Value)

        config["frozen"].should eq(false)
        config["jobs"].should eq(8) # temporary wins

        ENV["BUNDLE_JOBS"] = "2"
        config = Config.new(dir)
        config["jobs"].should eq(4) # local file beats env (pinned settings.rb order)
        config["frozen"].should eq(false)
        ENV.delete("BUNDLE_JOBS")

        # Without a local file, env wins over defaults
        empty_dir = File.tempname("celerite-spec", "empty")
        Dir.mkdir_p(empty_dir)
        begin
          ENV["BUNDLE_JOBS"] = "2"
          config = Config.new(empty_dir)
          config["jobs"].should eq(2)
        ensure
          ENV.delete("BUNDLE_JOBS")
          FileUtils.rm_rf(empty_dir)
        end

        config = Config.new(dir)
        config["jobs"].should eq(4)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "falls back to defaults for known keys" do
      config = Config.new
      config["retry"].should eq(3)
      config["timeout"].should eq(10)
      config["version"].should eq("lockfile")
      config["lockfile_checksums"].should eq(true)
    end

    it "reads env-only configuration" do
      ENV["BUNDLE_CELERITE__TEST__KEY"] = "hello"
      begin
        config = Config.new
        config["celerite.test.key"].should eq("hello")
      ensure
        ENV.delete("BUNDLE_CELERITE__TEST__KEY")
      end
    end

    it "ignores config files with BUNDLE_IGNORE_CONFIG" do
      dir = File.tempname("celerite-spec", "cfg")
      Dir.mkdir_p(dir)
      begin
        Dir.mkdir_p(File.join(dir, ".bundle"))
        File.write(File.join(dir, ".bundle", "config"), "---\nBUNDLE_FROZEN: \"true\"\n")
        ENV["BUNDLE_IGNORE_CONFIG"] = "1"
        config = Config.new(dir)
        config["frozen"].should be_nil
      ensure
        ENV.delete("BUNDLE_IGNORE_CONFIG")
        FileUtils.rm_rf(dir)
      end
    end

    it "converts boolean and numeric values" do
      Config.convert("true", "frozen").should eq(true)
      Config.convert("false", "frozen").should eq(false)
      Config.convert("0", "frozen").should eq(false)
      Config.convert("yes", "frozen").should eq(true)
      Config.convert("7", "jobs").should eq(7)
      Config.convert("with :dev", "with").should eq(["with", "", "dev"])
      Config.convert("vendor/bundle", "path").should eq("vendor/bundle")
    end

    it "reports pretty values per source" do
      dir = File.tempname("celerite-spec", "cfg")
      Dir.mkdir_p(dir)
      begin
        Dir.mkdir_p(File.join(dir, ".bundle"))
        File.write(File.join(dir, ".bundle", "config"), "---\nBUNDLE_PATH: \"vendor/bundle\"\n")
        ENV["BUNDLE_JOBS"] = "2"
        config = Config.new(dir)
        lines = config.pretty_values_for("path")
        lines.size.should eq(1)
        lines[0].should contain("Set for your local app")
        lines[0].should contain("vendor/bundle")

        lines = config.pretty_values_for("jobs")
        lines[0].should contain("Set via BUNDLE_JOBS")
        lines[0].should contain("Set via BUNDLE_JOBS: 2")

        lines = config.pretty_values_for("retry")
        lines.should eq(["You have not configured a value for `retry`"])
      ensure
        ENV.delete("BUNDLE_JOBS")
        FileUtils.rm_rf(dir)
      end
    end
  end
end
