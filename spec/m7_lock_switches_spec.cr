require "./spec_helper"

# `bundle lock` validates its platform edits and named updates before writing:
# `cli/lock.rb:49-67` rejects unknown platforms (exit 1), names missing from the
# lockfile or removing the last platform (exit 15), and
# `CLI::Common.ensure_all_gems_in_lockfile!` rejects unlocked names (exit 7).
private def lock_switch_files : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {
    "Gemfile" => "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"json_pure\", \"2.8.1\"\n",
  }
end

private def with_lock_switch_project(&)
  # `with_project` chdirs into the temporary project, so the bridge script can
  # only be found through the absolute path.
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
  begin
    with_project(lock_switch_files) { |dir| yield dir }
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def lock_switch_local_platform : String
  Celerite::Gem::Platform.local.to_s
end

describe "lock switch semantics" do
  it "rejects an unknown platform" do
    with_lock_switch_project do |_dir|
      code, out, err = run_cli(["lock", "--add-platform", "nonsense"])
      code.should eq(1)
      out.should eq("")
      err.should eq("The platform `nonsense` is unknown to RubyGems and can't be added to the lockfile.\n")
    end
  end

  it "rejects removing a platform the lockfile does not carry" do
    with_lock_switch_project do |_dir|
      code, _out, err = run_cli(["lock"])
      code.should eq(0), err
      code, out, err = run_cli(["lock", "--remove-platform", "java"])
      code.should eq(15)
      out.should eq("")
      err.should eq("Unable to remove the platform `java` since the only platforms are #{lock_switch_local_platform}\n")
    end
  end

  it "rejects removing every platform" do
    with_lock_switch_project do |_dir|
      run_cli(["lock"])
      code, out, err = run_cli(["lock", "--remove-platform", lock_switch_local_platform])
      code.should eq(15)
      out.should eq("")
      err.should eq("Removing all platforms from the bundle is not allowed\n")
    end
  end

  it "rejects --normalize-platforms combined with a platform edit" do
    with_lock_switch_project do |_dir|
      code, _out, err = run_cli(["lock", "--normalize-platforms", "--add-platform", "java"])
      code.should eq(15)
      err.should eq("--normalize-platforms can't be used with --add-platform\n")

      code, _out, err = run_cli(["lock", "--normalize-platforms", "--remove-platform", "java"])
      code.should eq(15)
      err.should eq("--normalize-platforms can't be used with --remove-platform\n")
    end
  end

  it "adds the requested platform to the lockfile" do
    with_lock_switch_project do |dir|
      code, _out, err = run_cli(["lock", "--add-platform", "java"])
      code.should eq(0), err
      File.read(File.join(dir, "Gemfile.lock")).should contain("java")
    end
  end

  it "resolves twice for a named update" do
    with_lock_switch_project do |_dir|
      run_cli(["lock"])
      code, out, err = run_cli(["lock", "--update", "json_pure"])
      code.should eq(0), err
      out.scan("Resolving dependencies...").size.should eq(2)
    end
  end

  it "rejects a named update for a gem that is not locked" do
    with_lock_switch_project do |_dir|
      run_cli(["lock"])
      code, out, err = run_cli(["lock", "--update", "nosuchgem"])
      code.should eq(7)
      out.should eq("")
      err.should eq("Could not find gem 'nosuchgem'.\n")
    end
  end

  it "rejects switches the reference does not declare for lock and update" do
    with_lock_switch_project do |_dir|
      code, _out, err = run_cli(["lock", "--ruby"])
      code.should eq(15)
      err.should contain("Unknown switches \"--ruby\"")

      code, _out, err = run_cli(["update", "--prefer-local"])
      code.should eq(15)
      err.should contain("Unknown switches \"--prefer-local\"")
    end
  end
end
