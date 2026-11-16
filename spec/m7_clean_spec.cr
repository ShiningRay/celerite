require "./spec_helper"
require "../src/celerite"

# Reference: `Bundler::Runtime#clean` keeps exactly the gems locked by the
# current lockfile (plus the running bundler). This port used to clear the keep
# set for the 2.7.x profile, because a broken differential harness (`>>`
# truncation) had hidden the reference output; that special case is withdrawn
# (2026-11-15). The fixtures mirror `fixtures/differential/clean-unused` and
# `clean-force` (Gemfile locks json_pure + thor).
private def with_clean_bridge(& : ->) : Nil
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

private def with_clean_home(dir : String, & : ->) : Nil
  saved = {} of String => String?
  {"HOME", "USERPROFILE", "GEM_HOME"}.each do |key|
    saved[key] = ENV[key]?
  end
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  # Nothing configures `path`, so the install target is `Gem.dir`; keep it
  # inside the project directory.
  ENV["GEM_HOME"] = File.join(dir, ".gem-home")
  Dir.mkdir_p(ENV["GEM_HOME"])
  begin
    yield
  ensure
    saved.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def clean_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

private def clean_gemfile(remote : String) : String
  %(source "#{remote}"\n\ngem "json_pure"\ngem "thor"\n)
end

# `<project>/.gem-home/gems` holds the install root when no `path` is
# configured (the RubyGems install dir); `with_clean_home` points GEM_HOME at
# the project so the suite never touches the machine's gem home.
private def clean_gems_dir(dir : String) : String
  File.join(dir, ".gem-home", "gems")
end

describe "clean" do
  it "removes only the unlocked gem and keeps the still-locked json_pure" do
    pending! "ruby not available" unless ruby_available?
    remote = clean_remote
    with_clean_bridge do
      with_project({"Gemfile" => clean_gemfile(remote)}) do |dir|
        with_clean_home(dir) do
          run_cli(["install"])[0].should eq(0)
          gems = clean_gems_dir(dir)
          Dir.exists?(File.join(gems, "thor-1.3.2")).should be_true

          run_cli(["remove", "thor"])[0].should eq(0)

          code, out, _err = run_cli(["clean"])
          code.should eq(0)
          out.should contain("Removing thor (1.3.2)")
          out.should_not contain("json_pure")
          Dir.exists?(File.join(gems, "thor-1.3.2")).should be_false
          Dir.exists?(File.join(gems, "json_pure-2.8.1")).should be_true
          File.exists?(File.join(File.dirname(gems), "specifications", "json_pure-2.8.1.gemspec")).should be_true
        end
      end
    end
  end

  it "keeps every gem the lockfile still lists (clean --force)" do
    pending! "ruby not available" unless ruby_available?
    remote = clean_remote
    with_clean_bridge do
      with_project({"Gemfile" => clean_gemfile(remote)}) do |dir|
        with_clean_home(dir) do
          run_cli(["install"])[0].should eq(0)
          gems = clean_gems_dir(dir)

          code, out, _err = run_cli(["clean", "--force"])
          code.should eq(0)
          out.should_not contain("Removing")
          Dir.exists?(File.join(gems, "thor-1.3.2")).should be_true
          Dir.exists?(File.join(gems, "json_pure-2.8.1")).should be_true
        end
      end
    end
  end

  it "reports dry-run removals without deleting the gem" do
    pending! "ruby not available" unless ruby_available?
    remote = clean_remote
    with_clean_bridge do
      with_project({"Gemfile" => clean_gemfile(remote)}) do |dir|
        with_clean_home(dir) do
          run_cli(["install"])[0].should eq(0)
          gems = clean_gems_dir(dir)
          run_cli(["remove", "thor"])[0].should eq(0)

          code, out, _err = run_cli(["clean", "--dry-run"])
          code.should eq(0)
          out.should contain("Would have removed thor (1.3.2)")
          Dir.exists?(File.join(gems, "thor-1.3.2")).should be_true
        end
      end
    end
  end

  it "is idempotent when clean runs twice" do
    pending! "ruby not available" unless ruby_available?
    remote = clean_remote
    with_clean_bridge do
      with_project({"Gemfile" => clean_gemfile(remote)}) do |dir|
        with_clean_home(dir) do
          run_cli(["install"])[0].should eq(0)
          run_cli(["remove", "thor"])[0].should eq(0)

          first_code, first_out, _err = run_cli(["clean"])
          first_code.should eq(0)
          first_out.should contain("Removing thor (1.3.2)")

          code, out, _err = run_cli(["clean"])
          code.should eq(0)
          out.should_not contain("Removing")
        end
      end
    end
  end
end
