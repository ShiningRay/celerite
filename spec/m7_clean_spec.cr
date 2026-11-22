require "./spec_helper"
require "../src/celerite"

# Reference: `Bundler::Runtime#clean` keeps exactly the gems locked by the
# current lockfile (plus the running bundler). This port used to clear the keep
# set for the 2.7.x profile, because a broken differential harness (`>>`
# truncation) had hidden the reference output; that special case is withdrawn
# (2026-11-15). The fixtures mirror `fixtures/differential/clean-unused` and
# `clean-force` (Gemfile locks json_pure + thor).
#
# 2026-11-22 (task-132): with no `path` configured the install root is the
# RubyGems directory, so `clean` never reaches the prune set at all -- the
# reference guard (`cli/clean.rb:19-22`) exits 15 and removes nothing. Two
# examples here expected a prune and were asserting a state the reference has
# never produced (`fixtures/differential/clean-no-path`); they now assert the
# guard instead. Pruning is still covered by the `--force` example below and by
# `fixtures/differential/clean-force`.
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

# Verbatim guard message from `Bundler::CLI::Clean#require_path_or_force`
# (`bundler-4.0.24/lib/bundler/cli/clean.rb:19-22`; the 2.7.2 file is
# character-identical). The reference ends both lines with "\n"; its CRLF
# rendering on Windows comes from the process's own line discipline, which the
# differential harness folds under normalization N10.
private def clean_guard_error : String
  "Cleaning all the gems on your system is dangerous! If you're sure you want to\nremove every system gem not in this bundle, run `bundle clean --force`.\n"
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
  it "refuses to remove the unlocked gem while no path is configured" do
    pending! "ruby not available" unless ruby_available?
    remote = clean_remote
    with_clean_bridge do
      with_project({"Gemfile" => clean_gemfile(remote)}) do |dir|
        with_clean_home(dir) do
          run_cli(["install"])[0].should eq(0)
          gems = clean_gems_dir(dir)
          Dir.exists?(File.join(gems, "thor-1.3.2")).should be_true

          run_cli(["remove", "thor"])[0].should eq(0)

          # No `path` is configured, so the install root is the RubyGems
          # directory and the reference guard fires before anything is pruned:
          # `bundle clean` exits 15 and removes nothing.
          code, out, err = run_cli(["clean"])
          code.should eq(15)
          out.should eq("")
          err.should eq(clean_guard_error)
          Dir.exists?(File.join(gems, "thor-1.3.2")).should be_true
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

  it "is idempotent when clean runs twice while no path is configured" do
    pending! "ruby not available" unless ruby_available?
    remote = clean_remote
    with_clean_bridge do
      with_project({"Gemfile" => clean_gemfile(remote)}) do |dir|
        with_clean_home(dir) do
          run_cli(["install"])[0].should eq(0)
          run_cli(["remove", "thor"])[0].should eq(0)
          gems = clean_gems_dir(dir)

          # The guard rejects both runs identically and removes nothing, so a
          # second `clean` sees exactly the state the first one left behind.
          first_code, first_out, first_err = run_cli(["clean"])
          first_code.should eq(15)
          first_out.should eq("")
          first_err.should eq(clean_guard_error)

          code, out, err = run_cli(["clean"])
          code.should eq(15)
          out.should eq("")
          err.should eq(first_err)
          Dir.exists?(File.join(gems, "thor-1.3.2")).should be_true
          Dir.exists?(File.join(gems, "json_pure-2.8.1")).should be_true
        end
      end
    end
  end
end
