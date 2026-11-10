require "./spec_helper"

describe Celerite::RubyVersion do
  it "parses plain ruby version string" do
    rv = Celerite::RubyVersion.from_string("ruby 4.0.6").not_nil!
    rv.versions.should eq(["4.0.6"])
    rv.patchlevel.should be_nil
    rv.engine.should eq("ruby")
    rv.engine_versions.should eq(["4.0.6"])
    rv.to_s.should eq("ruby 4.0.6")
  end

  it "parses ruby version with patchlevel" do
    rv = Celerite::RubyVersion.from_string("ruby 4.0.6p0").not_nil!
    rv.versions.should eq(["4.0.6"])
    rv.patchlevel.should eq("0")
    rv.to_s.should eq("ruby 4.0.6")
  end

  it "parses engine requirement string" do
    rv = Celerite::RubyVersion.from_string("ruby 2.6.0 (jruby 9.4.0.0)").not_nil!
    rv.versions.should eq(["2.6.0"])
    rv.engine.should eq("jruby")
    rv.engine_versions.should eq(["9.4.0.0"])
    rv.to_s.should eq("ruby 2.6.0 (jruby 9.4.0.0)")
  end

  it "detects version mismatch against system" do
    system = Celerite::RubyVersion.system("ruby", "4.0.6", "4.0.6", "0")
    requested = Celerite::RubyVersion.from_string("ruby 3.0.0").not_nil!
    diff = requested.diff(system)
    diff.should_not be_nil
    if diff
      diff[0].should eq(:version)
      Celerite::RubyVersion.mismatch_message(diff[0], diff[1], diff[2], requested, system).should eq("Your Ruby version is 4.0.6, but your Gemfile specified 3.0.0")
    end
  end

  it "treats system with patchlevel as compatible with requested version without patchlevel" do
    system = Celerite::RubyVersion.system("ruby", "4.0.6", "4.0.6", "0")
    requested = Celerite::RubyVersion.from_string("ruby 4.0.6").not_nil!
    requested.diff(system).should be_nil
  end

  it "treats explicit matching patchlevel as compatible" do
    system = Celerite::RubyVersion.system("ruby", "4.0.6", "4.0.6", "0")
    requested = Celerite::RubyVersion.from_string("ruby 4.0.6p0").not_nil!
    system.diff(requested).should be_nil
  end

  it "detects patchlevel mismatch when requested differs" do
    system = Celerite::RubyVersion.system("ruby", "4.0.6", "4.0.6", "0")
    requested = Celerite::RubyVersion.from_string("ruby 4.0.6p1").not_nil!
    diff = requested.diff(system)
    diff.should_not be_nil
    if diff
      diff[0].should eq(:patchlevel)
      Celerite::RubyVersion.mismatch_message(diff[0], diff[1], diff[2], requested, system).should eq("Your Ruby patchlevel is 0, but your Gemfile specified 1")
    end
  end

  it "detects engine mismatch" do
    system = Celerite::RubyVersion.system("ruby", "4.0.6", "4.0.6", "0")
    requested = Celerite::RubyVersion.from_string("ruby 4.0.6 (jruby 9.4.0.0)").not_nil!
    diff = requested.diff(system)
    diff.should_not be_nil
    if diff
      diff[0].should eq(:engine)
      Celerite::RubyVersion.mismatch_message(diff[0], diff[1], diff[2], requested, system).should eq("Your Ruby engine is ruby, but your Gemfile specified jruby")
    end
  end
end
