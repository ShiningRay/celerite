require "./spec_helper"
require "../src/celerite"
require "../src/celerite/lockfile/parser"

# Reference: bundler `lockfile_parser.rb:105-109` uses
# `SharedHelpers.relative_lockfile_path` (i.e. `relative_path_to` with
# `Pathname#relative_path_from(Dir.pwd)`, `shared_helpers.rb`) as the path in
# its messages; `:113-116` is the merge-conflict text and `:123-124`/`:169-171`
# are the other messages that embed the same value. Upstream test
# `lockfile_spec.rb:2431-2437` asserts `/your Gemfile.lock contains merge
# conflicts/i` and `/git checkout HEAD -- Gemfile.lock/i`.
private CONFLICT_LOCK = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:
<<<<<<< HEAD
    thor (1.3.2)
=======
    thor (1.2.0)
>>>>>>> origin/main

PLATFORMS
  ruby

DEPENDENCIES
  thor

BUNDLED WITH
   4.0.24
LOCK

private def with_conflict_bridge(& : ->) : Nil
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def conflict_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  "source \"#{remote}\"\n\ngem \"thor\"\n"
end

describe "lockfile merge conflicts" do
  it "reports the lockfile relative to the project and exits 20" do
    pending! "ruby not available" unless ruby_available?
    with_conflict_bridge do
      with_project({
        "Gemfile"      => conflict_gemfile,
        "Gemfile.lock" => CONFLICT_LOCK,
      }) do |dir|
        code, _out, err = run_cli(["install"])

        code.should eq(20)
        err.should contain("Your Gemfile.lock contains merge conflicts.")
        err.should contain("Run `git checkout HEAD -- Gemfile.lock` first to get a clean lock.")
        # The message must not leak the absolute project path (drive letter or
        # leading slash form).
        err.should_not contain(dir)
        err.should_not match(/[A-Za-z]:[\/\\]/)
      end
    end
  end

  it "prints the exact two reference lines" do
    pending! "ruby not available" unless ruby_available?
    with_conflict_bridge do
      with_project({
        "Gemfile"      => conflict_gemfile,
        "Gemfile.lock" => CONFLICT_LOCK,
      }) do
        code, _out, err = run_cli(["install"])

        code.should eq(20)
        err.chomp.should eq(
          "Your Gemfile.lock contains merge conflicts.\n" \
          "Run `git checkout HEAD -- Gemfile.lock` first to get a clean lock."
        )
      end
    end
  end

  it "keeps a parent-relative path for a lockfile outside the project" do
    sibling = File.expand_path("../celerite-spec-elsewhere/Gemfile.lock")
    ex = expect_raises(Celerite::LockfileError) do
      Celerite::Lockfile::Parser.parse(CONFLICT_LOCK, sibling)
    end
    ex.message.not_nil!.should contain("Your ../celerite-spec-elsewhere/Gemfile.lock contains merge conflicts.")
  end

  {% if flag?(:windows) %}
    it "falls back to the absolute path when it cannot be made relative" do
      other = "D:/celerite-spec-elsewhere/Gemfile.lock"
      ex = expect_raises(Celerite::LockfileError) do
        Celerite::Lockfile::Parser.parse(CONFLICT_LOCK, other)
      end
      ex.message.not_nil!.should contain("Your #{other} contains merge conflicts.")
    end
  {% end %}

  it "uses the same relative path for the unreadable message" do
    with_project({
      "Gemfile"      => conflict_gemfile,
      "Gemfile.lock" => "GEM\n  remote: https://rubygems.org/\n  specs:\n    thor (bogus)\n",
    }) do
      ex = expect_raises(Celerite::LockfileError) do
        Celerite::Lockfile::Parser.parse(File.read("Gemfile.lock"), File.expand_path("Gemfile.lock"))
      end
      ex.message.not_nil!.should contain("Your Gemfile.lock is unreadable.")
      ex.message.not_nil!.should contain("Run `rm Gemfile.lock`")
      ex.message.should_not match(/[A-Za-z]:[\/\\]/)
    end
  end
end
