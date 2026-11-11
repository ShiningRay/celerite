require "./spec_helper"

private def test_ruby_env(ruby_version = "4.0.6", engine = "ruby", engine_version = "4.0.6", patchlevel : String? = "0")
  Celerite::Bridge::RubyEnvironment.from_json(%({
    "ruby_version": #{ruby_version.to_json},
    "ruby_description": "ruby #{ruby_version}p#{patchlevel || 0}",
    "ruby_env_line": "ruby #{ruby_version}p#{patchlevel || 0} (2026-01-01 revision 0000000) [x64-mingw-ucrt]",
    "engine": #{engine.to_json},
    "engine_version": #{engine_version.to_json},
    "rubygems_version": "4.0.6",
    "ruby_revision": "0",
    "patchlevel": #{patchlevel.to_json},
    "platform": "x64-mingw-ucrt",
    "ruby_exe": "C:/Ruby40-x64/bin/ruby.exe",
    "gem_paths": [],
    "default_gem_dir": "C:/Ruby40-x64/lib/ruby/gems/4.0.0",
    "user_gem_dir": null,
    "loaded_bundler_version": "4.0.24"
  }))
end

describe Celerite::RubyRuntime do
  it "raises RubyVersionMismatch for different ruby version" do
    env = test_ruby_env
    begin
      Celerite::RubyRuntime.validate!("ruby 3.0.0", env)
      fail "expected RubyVersionMismatch"
    rescue ex : Celerite::RubyVersionMismatch
      ex.status_code.should eq(18)
      ex.message.should eq("Your Ruby version is 4.0.6, but your Gemfile specified 3.0.0")
    end
  end

  it "accepts matching version without explicit patchlevel when system has patchlevel" do
    env = test_ruby_env
    Celerite::RubyRuntime.validate!("ruby 4.0.6", env)
  end

  it "accepts matching version with explicit patchlevel" do
    env = test_ruby_env("4.0.6", "ruby", "4.0.6", "0")
    requested = Celerite::RubyVersion.from_string("ruby 4.0.6p0").not_nil!
    Celerite::RubyRuntime.validate_version!(requested, env)
  end

  it "accepts matching explicit engine and engine_version" do
    env = test_ruby_env("4.0.6", "ruby", "4.0.6", "0")
    requested = Celerite::RubyVersion.from_string("ruby 4.0.6 (ruby 4.0.6)").not_nil!
    Celerite::RubyRuntime.validate_version!(requested, env)
  end

  it "detects engine mismatch" do
    env = test_ruby_env
    begin
      Celerite::RubyRuntime.validate!("ruby 4.0.6 (jruby 9.4.0.0)", env)
      fail "expected RubyVersionMismatch"
    rescue ex : Celerite::RubyVersionMismatch
      ex.status_code.should eq(18)
      ex.message.should eq("Your Ruby engine is ruby, but your Gemfile specified jruby")
    end
  end

  it "detects engine version mismatch for an explicit engine" do
    env = test_ruby_env("2.6.0", "jruby", "9.4.0.0", "0")
    requested = Celerite::RubyVersion.from_string("ruby 2.6.0 (jruby 9.3.0.0)").not_nil!
    begin
      Celerite::RubyRuntime.validate_version!(requested, env)
      fail "expected RubyVersionMismatch"
    rescue ex : Celerite::RubyVersionMismatch
      ex.status_code.should eq(18)
      ex.message.should eq("Your jruby version is 9.4.0.0, but your Gemfile specified jruby 9.3.0.0")
    end
  end

  it "detects patchlevel mismatch when explicitly requested" do
    env = test_ruby_env("4.0.6", "ruby", "4.0.6", "0")
    begin
      Celerite::RubyRuntime.validate!("ruby 4.0.6p1", env)
      fail "expected RubyVersionMismatch"
    rescue ex : Celerite::RubyVersionMismatch
      ex.status_code.should eq(18)
      ex.message.should eq("Your Ruby patchlevel is 0, but your Gemfile specified 1")
    end
  end

  it "preserves Gemfile ruby engine options through the bridge evaluation" do
    with_project({"Gemfile" => %(source "https://rubygems.org"\nruby "2.6.0", engine: "jruby", engine_version: "9.4.0.0"\n)}) do
      with_client do |client|
        evaluation = client.evaluate_gemfile("Gemfile")
        evaluation.ruby_version.should eq("2.6.0")
        evaluation.ruby_engine.should eq("jruby")
        evaluation.ruby_engine_version.should eq("9.4.0.0")

        requested = Celerite::Commands.requested_ruby_version(evaluation).not_nil!
        requested.engine.should eq("jruby")
        requested.engine_versions.should eq(["9.4.0.0"])

        env = test_ruby_env("4.0.6", "ruby", "4.0.6", "0")
        expect_raises(Celerite::RubyVersionMismatch, "Your Ruby engine is ruby, but your Gemfile specified jruby") do
          Celerite::RubyRuntime.validate_version!(requested, env)
        end
      end
    end
  end

  it "preserves Gemfile ruby patchlevel options through the bridge evaluation" do
    with_project({"Gemfile" => %(source "https://rubygems.org"\nruby "4.0.6", patchlevel: "1"\n)}) do
      with_client do |client|
        evaluation = client.evaluate_gemfile("Gemfile")
        evaluation.ruby_version.should eq("4.0.6")
        evaluation.ruby_patchlevel.should eq("1")

        requested = Celerite::Commands.requested_ruby_version(evaluation).not_nil!
        requested.patchlevel.should eq("1")

        env = test_ruby_env("4.0.6", "ruby", "4.0.6", "0")
        expect_raises(Celerite::RubyVersionMismatch, "Your Ruby patchlevel is 0, but your Gemfile specified 1") do
          Celerite::RubyRuntime.validate_version!(requested, env)
        end
      end
    end
  end
end
