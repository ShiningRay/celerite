require "../spec_helper"
require "../../src/celerite"

module Celerite
  describe Gem::Requirement do
    it "satisfies versions per the pinned oracle" do
      each_requirement_oracle do |satisfied, req, version|
        requirement = Gem::Requirement.new(req)
        result = requirement.satisfied_by?(Gem::Version.new(version))
        result.should eq(satisfied), "requirement #{req} vs #{version}"
      end
    end

    it "defaults an empty requirement to >= 0" do
      r = Gem::Requirement.new
      r.none?.should be_true
      r.satisfied_by?(Gem::Version.new("999.0")).should be_true
      r.satisfied_by?(Gem::Version.new("0.a")).should be_false
    end

    it "parses bare versions as exact" do
      r = Gem::Requirement.new("1.2")
      r.exact?.should be_true
      r.satisfied_by?(Gem::Version.new("1.2")).should be_true
      r.satisfied_by?(Gem::Version.new("1.2.0")).should be_true
      r.satisfied_by?(Gem::Version.new("1.2.1")).should be_false
    end

    it "accepts versions without an operator" do
      r = Gem::Requirement.new(Gem::Version.new("2.0"))
      r.exact?.should be_true
    end

    it "rejects malformed requirements with the reference message" do
      ["", " ", ">> 1.0", "=< 1.0", ">= ", "abc", ">=", "=> 1.0", ">= 1.0.x!!"].each do |bad|
        expect_raises(Celerite::BadRequirementError, "Illformed requirement") do
          Gem::Requirement.new(bad)
        end
      end
    end

    it "renders to_lock_requirements sorted then reversed" do
      r = Gem::Requirement.new([">= 2.0", "< 3.0"])
      r.to_lock_requirements.should eq([">= 2.0", "< 3.0"])
    end

    it "renders for_lockfile version-sorted with the oracle" do
      each_render_oracle do |reqs, expected|
        requirement = Gem::Requirement.new(reqs)
        rendered = requirement.for_lockfile
        rendered.should eq(expected.empty? ? nil : expected)
      end
    end

    it "detects prerelease requirements" do
      Gem::Requirement.new(">= 1.0.a").prerelease?.should be_true
      Gem::Requirement.new(">= 1.0").prerelease?.should be_false
    end

    it "detects specific requirements" do
      Gem::Requirement.new(">= 1.0").specific?.should be_false
      Gem::Requirement.new("> 1.0").specific?.should be_false
      Gem::Requirement.new(["< 1.0"]).specific?.should be_true
      Gem::Requirement.new([">= 1.0", "< 2.0"]).specific?.should be_true
    end
  end
end
