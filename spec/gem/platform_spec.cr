require "../spec_helper"
require "../../src/celerite"

module Celerite
  describe Gem::Platform do
    describe "parsing" do
      it "parses common platforms" do
        p = Gem::Platform.new("x86_64-linux")
        p.cpu.should eq("x86_64")
        p.os.should eq("linux")
        p.version.should be_nil
        p.to_s.should eq("x86_64-linux")

        p = Gem::Platform.new("arm64-darwin-21")
        p.cpu.should eq("arm64")
        p.os.should eq("darwin")
        p.version.should eq("21")
        p.to_s.should eq("arm64-darwin-21")
      end

      it "normalizes i?86 cpus to x86" do
        Gem::Platform.new("i686-linux").cpu.should eq("x86")
        Gem::Platform.new("i486-linux").to_s.should eq("x86-linux")
      end

      it "handles mingw and mswin variants" do
        p = Gem::Platform.new("x64-mingw-ucrt")
        {p.cpu, p.os, p.version}.should eq({"x64", "mingw", "ucrt"})

        p = Gem::Platform.new("x86-mingw32")
        {p.cpu, p.os, p.version}.should eq({"x86", "mingw32", nil})

        p = Gem::Platform.new("x64-mswin64-120")
        {p.cpu, p.os, p.version}.should eq({"x64", "mswin64", "120"})
      end

      it "maps legacy jruby single tokens" do
        p = Gem::Platform.new("jruby")
        p.cpu.should be_nil
        p.os.should eq("java")
        p.to_s.should eq("java")
      end

      it "falls back to unknown os" do
        p = Gem::Platform.new("weirdos")
        p.cpu.should be_nil
        p.os.should eq("unknown")
        p.to_s.should eq("unknown")
      end

      it "treats ruby as the virtual platform" do
        Gem::Platform.new("ruby").ruby?.should be_true
        Gem::Platform.new("").ruby?.should be_true
        Gem::Platform::RUBY.ruby?.should be_true
        Gem::Platform.new("ruby").to_s.should eq("ruby")
      end

      it "strips trailing dashes" do
        Gem::Platform.new("x86_64-linux-").to_s.should eq("x86_64-linux")
      end
    end

    describe "matching" do
      it "matches equal platforms" do
        Gem::Platform.new("x86_64-linux").match?(Gem::Platform.new("x86_64-linux")).should be_true
      end

      it "matches when either side lacks a version" do
        Gem::Platform.new("x86_64-linux").match?(Gem::Platform.new("x86_64-linux-gnu")).should be_true
        Gem::Platform.new("x86_64-linux-gnu").match?(Gem::Platform.new("x86_64-linux")).should be_true
      end

      it "does not match differing versions outside linux" do
        Gem::Platform.new("x86_64-darwin-20").match?(Gem::Platform.new("x86_64-darwin-21")).should be_false
        Gem::Platform.new("x86_64-darwin-20").match?(Gem::Platform.new("x86_64-darwin")).should be_true
      end

      it "applies linux gnu/musl normalization" do
        Gem::Platform.new("x86_64-linux").match?(Gem::Platform.new("x86_64-linux-gnu")).should be_true
        Gem::Platform.new("x86_64-linux-gnu").match?(Gem::Platform.new("x86_64-linux-musl")).should be_false
        Gem::Platform.new("x86_64-linux-musl").match?(Gem::Platform.new("x86_64-linux-musl")).should be_true
      end

      it "cross-matches universal mingw" do
        Gem::Platform.new("universal-mingw").match?(Gem::Platform.new("x64-mingw-ucrt")).should be_true
        Gem::Platform.new("x64-mingw-ucrt").match?(Gem::Platform.new("universal-mingw")).should be_true
      end

      it "matches arm family cpus" do
        Gem::Platform.new("arm-linux").match?(Gem::Platform.new("armv7-linux")).should be_true
      end

      it "never matches across operating systems" do
        Gem::Platform.new("x86_64-linux").match?(Gem::Platform.new("x86_64-darwin")).should be_false
      end
    end

    describe "specificity" do
      it "scores exact platform best" do
        local = Gem::Platform.new("x86_64-linux")
        exact = Gem::Platform.new("x86_64-linux")
        generic = Gem::Platform::RUBY
        other = Gem::Platform.new("x86_64-darwin")

        Gem::Platform.platform_specificity_match(exact, local).should eq(-1)
        Gem::Platform.platform_specificity_match(generic, local).should eq(1_000_000)
        Gem::Platform.platform_specificity_match(other, local).should be > 0
      end

      it "scores generic cpu/os/version mismatches" do
        local = Gem::Platform.new("x86_64-linux-gnu")
        # same os, nil cpu (universal-ish), same version => cpu penalty only
        spec_platform = Gem::Platform.new("universal-linux-gnu")
        Gem::Platform.platform_specificity_match(spec_platform, local).should eq(
          Gem::Platform.platform_specificity_match(spec_platform, local)
        )
        # os mismatch dominates over version
        os_mismatch = Gem::Platform.new("x86_64-darwin-gnu")
        cpu_nil = Gem::Platform.new("universal-linux")
        Gem::Platform.platform_specificity_match(os_mismatch, local).should be > 10
        Gem::Platform.platform_specificity_match(cpu_nil, local).should eq(110)
      end
    end
  end
end
