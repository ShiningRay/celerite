require "./spec_helper"

# `bundle update --bundler` (`bundler/cli/update.rb:14-23`,
# `bundler/self_manager.rb:33-46`) resolves the target from the rubygems
# remote, prints `Updating bundler to <version>.` and records that version in
# `BUNDLED WITH`. A target that cannot be found fails with location 15 and
# `The `bundle update --bundler` target version (<target>) does not exist`.
private def with_update_bundler_env(project : String, profile : String = "4.0.24", &)
  names = ["HOME", "USERPROFILE", "BUNDLE_PATH", "BUNDLE_APP_CONFIG", "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(project, ".bundle")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = profile
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

private def update_bundler_project(index_name : String) : Hash(String, String)
  index = File.expand_path("../fixtures/#{index_name}", __DIR__).gsub('\\', "/")
  {
    "Gemfile" => "source \"file:///#{index}/\"\n\ngem \"json_pure\"\n",
  }
end

describe "bundle update --bundler" do
  it "reports a missing target on the 4.x profile" do
    with_project(update_bundler_project("gem-index")) do |dir|
      with_update_bundler_env(dir) do
        run_cli(["install"]).first.should eq(0)

        code, out, err = run_cli(["update", "--bundler"])
        code.should eq(15)
        out.should contain("Fetching source index from")
        err.should eq("The `bundle update --bundler` target version (>= 4.0.24) does not exist\n")
      end
    end
  end

  it "reports a nonexistent explicit target" do
    with_project(update_bundler_project("gem-index")) do |dir|
      with_update_bundler_env(dir) do
        run_cli(["install"]).first.should eq(0)

        code, out, err = run_cli(["update", "--bundler", "9.9.9"])
        code.should eq(15)
        out.should contain("Fetching source index from")
        err.should eq("The `bundle update --bundler` target version (9.9.9) does not exist\n")
      end
    end
  end

  it "updates BUNDLED WITH to the resolved target" do
    with_project(update_bundler_project("gem-index-bundler")) do |dir|
      with_update_bundler_env(dir) do
        run_cli(["install"]).first.should eq(0)

        code, out, _ = run_cli(["update", "--bundler", "9.9.9"])
        code.should eq(0)
        out.should contain("Updating bundler to 9.9.9.")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("BUNDLED WITH\n  9.9.9\n")
      end
    end
  end

  it "keeps the current bundler on the 2.x profile when the target is bare" do
    with_project(update_bundler_project("gem-index")) do |dir|
      with_update_bundler_env(dir, "2.7.2") do
        run_cli(["install"]).first.should eq(0)

        code, out, _ = run_cli(["update", "--bundler"])
        code.should eq(0)
        out.should_not contain("Updating bundler to")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("BUNDLED WITH\n   2.7.2\n")
      end
    end
  end
end
