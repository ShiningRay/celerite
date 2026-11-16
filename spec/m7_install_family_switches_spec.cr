require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(2): install-family switch surface. Thor validates switches before any
# Gemfile lookup, so an unknown flag reports exit 15 even in an empty
# directory; whitelisted flags fall through to the normal missing-Gemfile
# path (exit 10).
private def with_family_switches_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  yield
ensure
  if previous
    ENV["CELERITE_BRIDGE_SERVER"] = previous
  else
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end
end

private def run_family_switch(args : Array(String)) : {Int32, String, String}
  dir = File.tempname("celerite-family-switches")
  Dir.mkdir_p(dir)
  begin
    Dir.cd(dir) do
      run_cli(args)
    end
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "M7(2) install-family unknown switches" do
  it "rejects --bogus on install/update/lock/cache before locating a Gemfile" do
    with_family_switches_bridge do
      {"install", "update", "lock", "cache"}.each do |command|
        code, out, err = run_family_switch([command, "--bogus"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--bogus\"\n")
      end
    end
  end

  it "keeps =value suffixes verbatim and joins multiple unknowns with a comma" do
    with_family_switches_bridge do
      code, out, err = run_family_switch(["install", "--bogus=1", "--other"])
      code.should eq(15)
      out.should eq("")
      err.should eq("Unknown switches \"--bogus=1\", \"--other\"\n")
    end
  end

  it "rejects the short -v and long --version aliases (reference does too)" do
    with_family_switches_bridge do
      code, _out, err = run_family_switch(["install", "-v"])
      code.should eq(15)
      err.should eq("Unknown switches \"-v\"\n")

      code, _out, err = run_family_switch(["install", "--version"])
      code.should eq(15)
      # Verified against 4.0.24: the suggestion line follows the Unknown line.
      err.should eq("Unknown switches \"--version\"\nDid you mean?  \"--verbose\"\n")
    end
  end

  it "lets whitelisted flags reach the missing-Gemfile path" do
    with_family_switches_bridge do
      {"install" => "--local", "update" => "--all", "lock" => "--print", "cache" => "--no-install"}.each do |command, flag|
        code, _out, err = run_family_switch([command, flag])
        code.should eq(10)
        err.should contain("Could not locate Gemfile")
      end
    end
  end

  it "accepts global Thor flags and value options" do
    with_family_switches_bridge do
      code, _out, err = run_family_switch(["install", "--retry", "2", "--jobs=3", "--quiet"])
      code.should eq(10)
      err.should contain("Could not locate Gemfile")

      code, _out, err = run_family_switch(["lock", "--add-platform", "x86_64-linux"])
      code.should eq(10)
      err.should contain("Could not locate Gemfile")
    end
  end

  it "reports the remembered --path/--without/--with flags as removed in 4.x" do
    with_family_switches_bridge do
      code, _out, err = run_family_switch(["install", "--path", "vendor/bundle", "--without", "test"])
      code.should eq(15)
      err.should contain("The `--path` flag has been removed because it relied on being remembered")
    end
  end

  it "does not reject pack/package aliases" do
    with_family_switches_bridge do
      code, out, err = run_family_switch(["pack", "--bogus"])
      code.should eq(15)
      out.should eq("")
      err.should eq("Unknown switches \"--bogus\"\n")
    end
  end

  it "uses --gemfile for lock instead of the default Gemfile" do
    remote = family_switches_gemfile_remote
    with_family_switches_bridge do
      with_project({"Custom.gemfile" => "source \"#{remote}\"\n\ngem \"json_pure\"\n"}) do |dir|
        with_family_switches_home(dir) do
          code, _out, _err = run_cli(["lock", "--gemfile=Custom.gemfile"])
          code.should eq(0)
          File.exists?(File.join(dir, "Custom.gemfile.lock")).should be_true
          File.read(File.join(dir, "Custom.gemfile.lock")).should contain("json_pure (2.8.1)")
          ENV["BUNDLE_GEMFILE"]?.should be_nil
        end
      end
    end
  end

  it "uses --lockfile for install instead of the default lockfile" do
    remote = family_switches_gemfile_remote
    with_family_switches_bridge do
      with_project({"Gemfile" => "source \"#{remote}\"\n\ngem \"json_pure\"\n"}) do |dir|
        with_family_switches_home(dir) do
          code, _out, _err = run_cli(["install", "--lockfile=Custom.lock"])
          code.should eq(0)
          File.exists?(File.join(dir, "Custom.lock")).should be_true
          File.read(File.join(dir, "Custom.lock")).should contain("json_pure (2.8.1)")
          ENV["BUNDLE_LOCKFILE"]?.should be_nil
        end
      end
    end
  end

  it "accepts -j2/--trust-policy/--cooldown but rejects attached -P/-g and --lockfile outside install/lock" do
    with_family_switches_bridge do
      with_project({} of String => String) do
        run_cli(["install", "-j2"])[0].should eq(10)
        run_cli(["install", "--trust-policy=LowSecurity"])[0].should eq(10)
        run_cli(["lock", "--cooldown=5"])[0].should eq(10)
        run_cli(["cache", "--cooldown=5"])[0].should eq(10)

        code, out, err = run_cli(["install", "-PLowSecurity"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"-PLowSecurity\"\n")

        run_cli(["update", "-gfoo"])[0].should eq(15)
        run_cli(["update", "--lockfile=Y"])[0].should eq(15)
        run_cli(["cache", "--lockfile=Y"])[0].should eq(15)
      end
    end
  end
end

private def family_switches_gemfile_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

# These two examples really lock/install, so keep their bundle state inside the
# project: the full suite's cli_spec runs afterwards and must not see gems that
# leaked into the shared HOME.
private def with_family_switches_home(dir : String, &)
  previous_home = ENV["HOME"]?
  previous_profile = ENV["USERPROFILE"]?
  previous_bundle_path = ENV["BUNDLE_PATH"]?
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["BUNDLE_PATH"] = File.join(dir, ".bundle-test")
  yield
ensure
  if previous_home
    ENV["HOME"] = previous_home
  else
    ENV.delete("HOME")
  end
  if previous_profile
    ENV["USERPROFILE"] = previous_profile
  else
    ENV.delete("USERPROFILE")
  end
  if previous_bundle_path
    ENV["BUNDLE_PATH"] = previous_bundle_path
  else
    ENV.delete("BUNDLE_PATH")
  end
end
