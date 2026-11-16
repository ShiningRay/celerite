require "./spec_helper"

# `Bundler::CLI::Update#run` (`bundler/cli/update.rb:26-38`) derives the update
# scope from Thor's parsed inputs: a scoped update (`gems`, `--source`,
# `--group`, `--ruby`, `--bundler`) needs an installed bundle (status 22,
# `GemfileLockNotFound`) and every named gem must already be locked
# (status 7, `CLI::Common.ensure_all_gems_in_lockfile!`), while `--all`
# together with any of those selectors is rejected (status 15).
private def with_update_scope_env(project : String, &)
  gem_home = File.join(project, "gemhome")
  Dir.mkdir_p(gem_home)
  names = ["HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH", "BUNDLE_USER_CONFIG", "BUNDLE_USER_CACHE", "BUNDLE_USER_PLUGIN", "CELERITE_BRIDGE_SERVER"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = gem_home
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["BUNDLE_USER_CONFIG"] = File.join(project, "home-config")
  ENV["BUNDLE_USER_CACHE"] = File.join(project, "home-cache")
  ENV["BUNDLE_USER_PLUGIN"] = File.join(project, "home-plugin")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
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

private def update_scope_project : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {
    "Gemfile" => "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"json_pure\", \"2.6.0\"\n\ngroup :development do\n  gem \"thor\", \"1.3.2\"\nend\n",
  }
end

describe "bundle update scope" do
  it "asks for an install when a scoped update has no lockfile" do
    with_project(update_scope_project) do |dir|
      with_update_scope_env(dir) do
        code, out, err = run_cli(["update", "nosuchgem"])
        code.should eq(22)
        out.should eq("")
        err.should contain("This Bundle hasn't been installed yet.")
        err.should contain("to update and\ninstall the bundled gems.")
      end
    end
  end

  it "rejects --all together with specific selectors" do
    with_project(update_scope_project) do |dir|
      with_update_scope_env(dir) do
        code, out, err = run_cli(["update", "--all", "json_pure"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Cannot specify --all along with specific options.\n")

        code, out, err = run_cli(["update", "--all", "--group", "development"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Cannot specify --all along with specific options.\n")
      end
    end
  end

  it "reports an unknown gem name like the reference" do
    with_project(update_scope_project) do |dir|
      with_update_scope_env(dir) do
        install_code, _, _ = run_cli(["install"])
        install_code.should eq(0)

        code, out, err = run_cli(["update", "nosuchgem"])
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'nosuchgem'.\n")
      end
    end
  end

  it "widens --group into the named gems and reports unchanged versions" do
    with_project(update_scope_project) do |dir|
      with_update_scope_env(dir) do
        install_code, _, _ = run_cli(["install"])
        install_code.should eq(0)

        code, out, err = run_cli(["update", "--group", "development"])
        code.should eq(0)
        out.should contain("Bundle updated!")
        out.scan("Resolving dependencies...").size.should eq(2)
        err.should eq("Bundler attempted to update thor but its version stayed the same\n")
      end
    end
  end

  it "reports the pinned gem as unchanged for a named update" do
    with_project(update_scope_project) do |dir|
      with_update_scope_env(dir) do
        install_code, _, _ = run_cli(["install"])
        install_code.should eq(0)

        code, out, err = run_cli(["update", "json_pure"])
        code.should eq(0)
        err.should eq("Bundler attempted to update json_pure but its version stayed the same\n")
        out.should contain("Bundle updated!")
      end
    end
  end
end
