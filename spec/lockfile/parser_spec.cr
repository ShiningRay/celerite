require "../spec_helper"
require "../../src/celerite"

private def full_lockfile : String
  text = <<-LOCK
  GEM
    remote: https://rubygems.org/
    remote: https://mirror.example.com/
    specs:
      json_pure (2.8.1)
      rake (13.2.0)
      nokogiri (1.16.0-x86_64-linux)
        racc (~> 1.4)

  GIT
    remote: https://github.com/example/geo.git
    revision: 0e9d4a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f
    branch: main
    specs:
      geo (2.0.0)

  PATH
    remote: vendor/local_gem
    specs:
      local_gem (0.1.0)

  PLATFORMS
    x64-mingw-ucrt
    x86_64-linux

  DEPENDENCIES
    json_pure (>= 2.0, < 3.0)
    local_gem (= 0.1.0)
    nokogiri (~> 1.16)
    rake!

  CHECKSUMS
    bundler (4.0.24) sha256=7978a8ac648767f5e635bc522445b79e80a52b907a39a36c2d8085ed6bc762ae
    json_pure (2.8.1) sha256=6a877929ba9d4fa0808ccc38656d1b15d138b2aa0aa32037ee05abea13427ace
    nokogiri (1.16.0-x86_64-linux) sha256=aaaa,sha256=bbbb

  RUBY VERSION
    ruby 3.2.0p0

  BUNDLED WITH
    4.0.24
  LOCK
  text + "\n"
end

module Celerite
  describe Lockfile::Parser do
    it "parses sources, specs and spec dependencies in order" do
      data = Lockfile::Parser.parse(full_lockfile)
      sources = data.sources
      sources.size.should eq(3)
      sources[0].type.should eq("GEM")
      sources[0].remotes.should eq(["https://rubygems.org/", "https://mirror.example.com/"])
      sources[0].specs.map(&.full_name).should eq(["json_pure-2.8.1", "rake-13.2.0", "nokogiri-1.16.0-x86_64-linux"])
      sources[0].specs[2].dependencies[0].name.should eq("racc")
      sources[0].specs[2].dependencies[0].requirements.should eq(["~> 1.4"])
      sources[1].type.should eq("GIT")
      sources[1].option("revision").should eq("0e9d4a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f")
      sources[2].type.should eq("PATH")
    end

    it "parses platforms, dependencies, checksums, ruby and bundler versions" do
      data = Lockfile::Parser.parse(full_lockfile)
      data.platforms.should eq(["x64-mingw-ucrt", "x86_64-linux"])
      data.dependencies.map(&.name).should eq(["json_pure", "local_gem", "nokogiri", "rake"])
      data.dependencies[0].requirements.should eq([">= 2.0", "< 3.0"])
      data.dependencies[3].pinned.should be_true
      data.dependencies[0].pinned.should be_false
      data.checksums.size.should eq(3)
      data.checksums[2].checksums.should eq(["sha256=aaaa", "sha256=bbbb"])
      data.ruby_version.should eq("ruby 3.2.0p0")
      data.bundler_version.should eq("4.0.24")
    end

    it "round-trips canonical lockfiles byte-identically" do
      data = Lockfile::Parser.parse(full_lockfile)
      data.to_lock.should eq(full_lockfile)
    end

    it "round-trips a real bundler 4.0.24-generated lockfile" do
      path = File.join(__DIR__, "..", "fixtures", "lockfile_rubygems_4.0.24.lock")
      text = File.read(path)
      Lockfile::Parser.parse(text).to_lock.should eq(text)
    end

    it "preserves unknown sections verbatim" do
      text = full_lockfile + "\nCUSTOM SECTION\n  some content\n  more content\n"
      data = Lockfile::Parser.parse(text)
      data.unknown_sections.should eq(["CUSTOM SECTION"])
      data.to_lock.should eq(text)
    end

    it "reports known sections and ignores them in unknowns" do
      Lockfile::Parser.sections_in_lockfile(full_lockfile).uniq.sort.should eq(
        ["BUNDLED WITH", "CHECKSUMS", "DEPENDENCIES", "GEM", "GIT", "PATH", "PLATFORMS", "RUBY VERSION"]
      )
    end

    it "rejects merge conflicts" do
      conflicted = full_lockfile.gsub("json_pure", "json_pure") + "\n<<<<<<< HEAD\n"
      expect_raises(LockfileError, "contains merge conflicts") do
        Lockfile::Parser.parse(conflicted)
      end
    end

    it "treats empty lockfiles as valid" do
      data = Lockfile::Parser.parse("")
      data.valid?.should be_true
      data.to_lock.should eq("")
    end

    it "marks lockfiles without known sections invalid" do
      data = Lockfile::Parser.parse("JUST SOME TEXT\n")
      data.valid?.should be_false
    end

    it "fails on malformed spec versions with position info" do
      bad = <<-LOCK
      GEM
        remote: https://rubygems.org/
        specs:
          bad (x.y.z)

      PLATFORMS
        ruby

      DEPENDENCIES
        bad

      BUNDLED WITH
        4.0.24
      LOCK
      expect_raises(LockfileError, "unreadable") do
        Lockfile::Parser.parse(bad)
      end
    end

    it "handles CRLF line endings" do
      data = Lockfile::Parser.parse(full_lockfile.gsub('\n', "\r\n"))
      data.sources.size.should eq(3)
      data.to_lock.should eq(full_lockfile)
    end

    it "computes sections_to_ignore per bundler version" do
      Lockfile::Parser.sections_to_ignore(Gem::Version.new("1.0")).sort.should eq(
        ["BUNDLED WITH", "CHECKSUMS", "PLUGIN SOURCE", "RUBY VERSION"]
      )
      Lockfile::Parser.sections_to_ignore(Gem::Version.new("4.0.24")).should be_empty
    end

    describe "dependency rendering" do
      it "renders bare names for default requirements" do
        data = Lockfile::Parser.parse(<<-LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            rails (7.0.4)

        PLATFORMS
          ruby

        DEPENDENCIES
          rails

        BUNDLED WITH
          4.0.24
        LOCK
        data.to_lock.should contain("DEPENDENCIES\n  rails\n")
      end

      it "renders pinned markers" do
        data = Lockfile::Parser.parse(<<-LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            rails (7.0.4)

        PLATFORMS
          ruby

        DEPENDENCIES
          rails!

        BUNDLED WITH
          4.0.24
        LOCK
        data.dependencies[0].pinned.should be_true
        data.to_lock.should contain("  rails!\n")
      end
    end
  end
end
