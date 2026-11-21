require "./spec_helper"

# `bundle update --group <group>` (`bundler/cli/update.rb:49-56`): groups only
# widen the explicit gem list. A group with no members leaves the unlock set
# empty, so the reference resolves nothing, leaves the lockfile untouched and
# only prints `Bundle updated!`; a populated group still re-resolves.
private def with_update_group_env(project : String, &)
  names = ["HOME", "USERPROFILE", "BUNDLE_PATH", "BUNDLE_APP_CONFIG", "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(project, ".bundle")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  begin
    yield
  ensure
    previous.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def update_group_project : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  {
    "Gemfile" => "source \"file:///#{index}/\"\n\ngem \"json_pure\"\n\ngroup :dev do\n  gem \"thor\"\nend\n",
  }
end

describe "bundle update --group" do
  it "does not re-resolve for a group with no members" do
    with_project(update_group_project) do |dir|
      with_update_group_env(dir) do
        run_cli(["install", "--quiet"]).first.should eq(0)
        before = File.read(File.join(dir, "Gemfile.lock"))

        code, out, err = run_cli(["update", "--group", "nope"])
        code.should eq(0)
        out.should eq("Bundle updated!\n")
        out.should_not contain("Fetching source index")
        out.should_not contain("Resolving dependencies")
        err.should be_empty
        File.read(File.join(dir, "Gemfile.lock")).should eq(before)
      end
    end
  end

  it "still re-resolves for a group with members" do
    with_project(update_group_project) do |dir|
      with_update_group_env(dir) do
        run_cli(["install", "--quiet"]).first.should eq(0)

        code, out, err = run_cli(["update", "--group", "dev"])
        code.should eq(0)
        out.should contain("Fetching source index from")
        out.should contain("Resolving dependencies...")
        out.should contain("Bundle updated!")
        err.should contain("Bundler attempted to update thor but its version stayed the same")
      end
    end
  end

  it "leaves the lockfile byte-identical when no group matches" do
    with_project(update_group_project) do |dir|
      with_update_group_env(dir) do
        run_cli(["install", "--quiet"]).first.should eq(0)
        before = File.read(File.join(dir, "Gemfile.lock"))

        run_cli(["update", "--group", "nope", "--group", "alsonope"]).first.should eq(0)
        File.read(File.join(dir, "Gemfile.lock")).should eq(before)
      end
    end
  end
end
