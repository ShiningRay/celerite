require "./spec_helper"

private def constraint_ruby_env(ruby_version = "4.0.6", engine = "ruby", engine_version = "4.0.6", patchlevel : String? = "0")
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

describe Celerite::InstallPaths do
  it "derives the Ruby ABI as major.minor.0" do
    Celerite::InstallPaths.ruby_abi_for("4.0.6").should eq("4.0.0")
    Celerite::InstallPaths.ruby_abi_for("3.3.7").should eq("3.3.0")
    Celerite::InstallPaths.ruby_abi_for("4").should eq("4.0.0")
  end
end

describe Celerite::Resolution do
  it "treats missing Gemfile and lockfile Ruby declarations as compatible" do
    Celerite::Resolution.ruby_compatible?(nil, nil).should be_true
  end

  it "rejects a one-sided Ruby declaration" do
    Celerite::Resolution.ruby_compatible?(nil, "ruby 4.0.6").should be_false
    Celerite::Resolution.ruby_compatible?("ruby 4.0.6", nil).should be_false
  end

  it "accepts a matching locked Ruby version" do
    Celerite::Resolution.ruby_compatible?("ruby 4.0.6", "ruby 4.0.6").should be_true
    Celerite::Resolution.ruby_compatible?("ruby 4.0.6", "ruby 4.0.6p0").should be_true
  end

  it "rejects a locked Ruby version that does not satisfy the Gemfile target" do
    Celerite::Resolution.ruby_compatible?("ruby 3.0.0", "ruby 4.0.6").should be_false
    Celerite::Resolution.ruby_compatible?("ruby 4.0.6p1", "ruby 4.0.6p0").should be_false
  end

  it "falls back to string equality when either declaration is unparseable" do
    Celerite::Resolution.ruby_compatible?("ruby-head", "ruby-head").should be_true
    Celerite::Resolution.ruby_compatible?("ruby-head", "ruby 4.0.6").should be_false
  end
end

describe Celerite::RubyRuntime do
  it "does nothing when the Gemfile has no explicit Ruby declaration" do
    Celerite::RubyRuntime.validate!(nil, constraint_ruby_env)
    Celerite::RubyRuntime.diff(nil, constraint_ruby_env).should be_nil
  end

  it "reports an explicit patchlevel diff against the system patchlevel" do
    diff = Celerite::RubyRuntime.diff("ruby 4.0.6p1", constraint_ruby_env)
    diff.should eq({:patchlevel, "1", "0"})
  end

  it "reports no diff when the requested patchlevel matches" do
    Celerite::RubyRuntime.diff("ruby 4.0.6p0", constraint_ruby_env).should be_nil
  end

  it "reports an engine version diff for an explicit non-MRI engine" do
    env = constraint_ruby_env("2.6.0", "jruby", "9.4.0.0", "0")
    diff = Celerite::RubyRuntime.diff("ruby 2.6.0 (jruby 9.3.0.0)", env)
    diff.should eq({:engine_version, "9.3.0.0", "9.4.0.0"})
  end

  it "prefers the engine diff over a version diff" do
    env = constraint_ruby_env("4.0.6", "ruby", "4.0.6", "0")
    diff = Celerite::RubyRuntime.diff("ruby 3.0.0 (jruby 9.4.0.0)", env)
    diff.should eq({:engine, "jruby", "ruby"})
  end

  it "prefers the engine version diff over a patchlevel diff" do
    env = constraint_ruby_env("4.0.6", "ruby", "4.0.6", "0")
    diff = Celerite::RubyRuntime.diff("ruby 4.0.6p1 (ruby 4.0.5)", env)
    diff.should eq({:engine_version, "4.0.5", "4.0.6"})
  end

  it "reports no diff when engine, engine version and patchlevel all match" do
    env = constraint_ruby_env("4.0.6", "ruby", "4.0.6", "0")
    Celerite::RubyRuntime.diff("ruby 4.0.6p0 (ruby 4.0.6)", env).should be_nil
  end
end
