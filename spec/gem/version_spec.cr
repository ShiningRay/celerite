require "../spec_helper"
require "../../src/celerite"

module Celerite
  describe Gem::Version do
    describe "ordering" do
      it "matches the pinned RubyGems oracle (non-strict over canonical-equal versions)" do
        versions = version_oracle

        (versions.size - 1).times do |i|
          lhs = Gem::Version.new(versions[i])
          rhs = Gem::Version.new(versions[i + 1])
          (lhs <=> rhs).should be <= 0
        end
      end

      it "sorts a shuffled list back into oracle order (canonical-equal groups ignored)" do
        versions = version_oracle
        sorted = versions.shuffle(random: Random.new(42)).sort! { |a, b| Gem::Version.new(a) <=> Gem::Version.new(b) }

        # Adjacent canonical-equal versions may swap under unstable sorts; only
        # the non-equal ordering is contractual.
        (sorted.size - 1).times do |i|
          lhs = Gem::Version.new(sorted[i])
          rhs = Gem::Version.new(sorted[i + 1])
          unless lhs.canonical == rhs.canonical
            (lhs <=> rhs).should eq(-1)
          end
        end
      end

      it "implements the documented pairwise relations" do
        (Gem::Version.new("3.10") <=> Gem::Version.new("3.2")).should eq(1)
        (Gem::Version.new("1.0.a") <=> Gem::Version.new("1.0")).should eq(-1)
        (Gem::Version.new("1.0.b1") <=> Gem::Version.new("1.0.a.2")).should eq(1)
        (Gem::Version.new("1.0.a.10") <=> Gem::Version.new("1.0.a9")).should eq(1)
        (Gem::Version.new("2.a") <=> Gem::Version.new("10")).should eq(-1)
        (Gem::Version.new("1.0.0.0") <=> Gem::Version.new("1")).should eq(0)
        (Gem::Version.new("0.1a") <=> Gem::Version.new("0.1.a")).should eq(0)
        (Gem::Version.new("1.0") <=> Gem::Version.new("1")).should eq(0)
        (Gem::Version.new("1.0") <=> Gem::Version.new("1.0.1")).should eq(-1)
      end
    end

    describe "parsing" do
      it "normalizes dashes to .pre. in the stored string" do
        v = Gem::Version.new("1.0-beta.1")
        v.raw.should eq("1.0.pre.beta.1")
        v.to_s.should eq("1.0.pre.beta.1")
      end

      it "treats blank input as 0" do
        Gem::Version.new("").raw.should eq("0")
        Gem::Version.new("   ").raw.should eq("0")
      end

      it "strips surrounding whitespace" do
        Gem::Version.new("  1.2.3  ").raw.should eq("1.2.3")
      end

      it "keeps precision in eql? but not ==" do
        Gem::Version.new("1.0").should eq(Gem::Version.new("1"))
        Gem::Version.new("1.0").eql?(Gem::Version.new("1")).should be_false
      end

      it "reports prerelease for any letter" do
        Gem::Version.new("1.0.a").prerelease?.should be_true
        Gem::Version.new("1.0.pre.1").prerelease?.should be_true
        Gem::Version.new("1.0-beta").prerelease?.should be_true
        Gem::Version.new("1.0.0").prerelease?.should be_false
      end

      it "rejects malformed versions with the reference message" do
        ["1.0-", "1..0", "1.", "a", "1.0.alpha+x", "1.0 beta", "1,2"].each do |bad|
          expect_raises(Celerite::VersionError, "Malformed version number string") do
            Gem::Version.new(bad)
          end
        end
      end

      it "accepts reference-valid oddities" do
        ["1.0--", "0.01", "1.2.3.4.5.6.7.8", "2026.11.07", " 1.0 "].each do |good|
          Gem::Version.correct?(good).should be_true
        end
      end
    end

    describe "release and bump" do
      it "computes release by dropping string segments" do
        Gem::Version.new("1.2.0.a").release.to_s.should eq("1.2.0")
        Gem::Version.new("1.a.2.b").release.to_s.should eq("1")
        Gem::Version.new("1.2.0").release.to_s.should eq("1.2.0")
        Gem::Version.new("0.a").release.to_s.should eq("0")
      end

      it "computes bump like the reference" do
        Gem::Version.new("5.3.1").bump.to_s.should eq("5.4")
        Gem::Version.new("5.3.1.b.2").bump.to_s.should eq("5.4")
        Gem::Version.new("1").bump.to_s.should eq("2")
      end
    end

    it "hashes canonical-equal versions equally" do
      Gem::Version.new("1.0").hash.should eq(Gem::Version.new("1.0.0").hash)
    end
  end
end
