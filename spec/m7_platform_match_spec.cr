require "./spec_helper"

# M7(1): platform matching must mirror the pinned RubyGems `Gem::Platform`
# contract (vendor/reference/{v4.0.24,bundler-v2.7.2}/platform.rb), which the
# system RubyGems probe confirmed: `===` is not commutative, the universal
# mingw variant matches any mingw platform, and the virtual ruby platform does
# not match a concrete local platform (specificity, not `===`, routes pure
# gems). Platforms are constructed explicitly so the specs stay host-independent.
describe Celerite::Gem::Platform do
  it "parses platform triples, the virtual ruby platform, and legacy cpu fixups" do
    u = Celerite::Gem::Platform.new("x64-mingw-ucrt")
    u.cpu.should eq("x64")
    u.os.should eq("mingw")
    u.version.should eq("ucrt")
    u.to_s.should eq("x64-mingw-ucrt")
    u.ruby?.should be_false

    linux = Celerite::Gem::Platform.new("x86_64-linux")
    linux.cpu.should eq("x86_64")
    linux.os.should eq("linux")
    linux.version.should be_nil

    ruby = Celerite::Gem::Platform.new("ruby")
    ruby.should eq(Celerite::Gem::Platform::RUBY)
    ruby.ruby?.should be_true

    Celerite::Gem::Platform.new("i386-mingw32").cpu.should eq("x86")
    Celerite::Gem::Platform.new("universal-mingw32").cpu.should eq("universal")
  end

  it "matches platforms with RubyGems === semantics (non-commutative)" do
    user = Celerite::Gem::Platform.new("x64-mingw-ucrt")
    Celerite::Gem::Platform.new("x64-mingw-ucrt").match?(user).should be_true
    Celerite::Gem::Platform.new("universal-mingw32").match?(user).should be_true
    Celerite::Gem::Platform.new("ruby").match?(user).should be_false
    user.match?(Celerite::Gem::Platform.new("ruby")).should be_false
    Celerite::Gem::Platform.new("x86_64-linux").match?(user).should be_false
    Celerite::Gem::Platform.new("x86_64-mingw32").match?(user).should be_false
  end

  it "treats a missing linux version as gnu-normalized wildcard" do
    Celerite::Gem::Platform.new("x86_64-linux")
      .match?(Celerite::Gem::Platform.new("x86_64-linux-gnu")).should be_true
  end

  it "scores specificity exactly and worst-case for ruby" do
    user = Celerite::Gem::Platform.new("x64-mingw-ucrt")
    Celerite::Gem::Platform.platform_specificity_match(user, user).should eq(-1)
    Celerite::Gem::Platform.platform_specificity_match(
      Celerite::Gem::Platform::RUBY, user).should eq(1_000_000)
  end
end
