require "./spec_helper"

# `Bundler::CLI::Outdated#run` (`bundler/cli/outdated.rb:26-50`) validates the
# gem names given on the command line against a *silenced* resolve
# (`Bundler.ui.silence { Bundler.definition.resolve }`) before it starts the
# printing resolution, so an unknown name reports
# `Could not find gem '<name>'.` (exit 7) without any `Fetching source index`
# or `Resolving dependencies...` line in front of it.
private def with_outdated_naming_env(project : String, &)
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

private def outdated_naming_project : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {
    "Gemfile" => "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"json_pure\", \"2.6.0\"\n\ngroup :development do\n  gem \"thor\", \"1.3.2\"\nend\n",
  }
end

describe "bundle outdated named gems" do
  it "reports an unknown gem name without printing resolution progress" do
    with_project(outdated_naming_project) do |dir|
      with_outdated_naming_env(dir) do
        install_code, _, _ = run_cli(["install"])
        install_code.should eq(0)

        code, out, err = run_cli(["outdated", "nosuchgem"])
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'nosuchgem'.\n")
      end
    end
  end

  it "keeps stderr to the single error line in parseable mode" do
    with_project(outdated_naming_project) do |dir|
      with_outdated_naming_env(dir) do
        install_code, _, _ = run_cli(["install"])
        install_code.should eq(0)

        code, out, err = run_cli(["outdated", "--parseable", "nosuchgem"])
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'nosuchgem'.\n")
      end
    end
  end

  it "treats a value-less --groups argument as a gem name" do
    with_project(outdated_naming_project) do |dir|
      with_outdated_naming_env(dir) do
        install_code, _, _ = run_cli(["install"])
        install_code.should eq(0)

        code, out, err = run_cli(["outdated", "--groups", "development"])
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'development'.\n")
      end
    end
  end

  it "still resolves and reports for a gem that is in the bundle" do
    with_project(outdated_naming_project) do |dir|
      with_outdated_naming_env(dir) do
        install_code, _, _ = run_cli(["install"])
        install_code.should eq(0)

        code, out, err = run_cli(["outdated", "json_pure"])
        code.should eq(1)
        err.should eq("")
        out.scan("Resolving dependencies...").size.should eq(2)
        out.should contain("json_pure")
      end
    end
  end
end
