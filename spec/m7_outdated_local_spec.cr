require "./spec_helper"

# Two `outdated` / `install --local` contracts pinned against the 4.0.24
# reference:
#
# A. `Bundler::CLI::Outdated#print_gem` (`cli/outdated.rb:210-226`) only appends
#    `, requested <req>` when the Gemfile dependency is *specific*
#    (`dependency&.specific?`), while the table cell always shows the
#    requirement (`gem_column_for`, `:248-263`).
# B. `install --local` never enables remote sources (`setup_domain!`,
#    `definition.rb:190-203`), and `Source::Rubygems#to_s`
#    (`source/rubygems.rb:122-136`) says "cached gems or installed locally"
#    only when `cached!` actually ran — which requires the app cache directory
#    to exist (`:69-76`).
private def with_local_outdated_env(project : String, &)
  names = ["HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH", "BUNDLE_APP_CONFIG", "BUNDLE_USER_CONFIG", "BUNDLE_USER_CACHE", "BUNDLE_USER_PLUGIN", "CELERITE_BRIDGE_SERVER"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(project, ".bundle")
  Dir.mkdir_p(ENV["BUNDLE_APP_CONFIG"])
  ENV["BUNDLE_USER_CONFIG"] = File.join(project, "home-config")
  ENV["BUNDLE_USER_CACHE"] = File.join(project, "home-cache")
  ENV["BUNDLE_USER_PLUGIN"] = File.join(project, "home-plugin")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  # The host already has json_pure 2.6.0 installed; an isolated GEM_HOME is what
  # makes that copy invisible, exactly like the differential sandbox.
  gem_home = File.join(project, "gemhome")
  Dir.mkdir_p(gem_home)
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = gem_home
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

private def local_outdated_index : String
  File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
end

describe "bundle outdated parseable requested segment" do
  it "omits requested for a non-specific dependency" do
    files = {
      "Gemfile"      => "source \"file:///#{local_outdated_index}/\"\n\ngem \"json_pure\"\n",
      "Gemfile.lock" => <<-LOCK,
        GEM
          remote: file:///#{local_outdated_index}/
          specs:
            json_pure (2.6.0)

        PLATFORMS
          x64-mingw-ucrt

        DEPENDENCIES
          json_pure

        BUNDLED WITH
           4.0.24
        LOCK
    }
    with_project(files) do |dir|
      with_local_outdated_env(dir) do
        code, _, _ = run_cli(["install", "--quiet"])
        code.should eq(0)

        code, out, err = run_cli(["outdated", "--parseable"])
        code.should eq(1)
        out.should contain("json_pure (newest 2.8.1, installed 2.6.0")
        out.should_not contain("requested")
        # Parseable mode routes resolution progress to stderr (pinned by
        # `outdated-parseable`); only the result line goes to stdout.
        out.should_not contain("Resolving dependencies")
      end
    end
  end

  it "keeps requested for a specific dependency" do
    files = {
      "Gemfile" => "source \"file:///#{local_outdated_index}/\"\n\ngem \"json_pure\", \"2.6.0\"\n",
    }
    with_project(files) do |dir|
      with_local_outdated_env(dir) do
        code, _, _ = run_cli(["install", "--quiet"])
        code.should eq(0)

        code, out, _ = run_cli(["outdated", "--parseable"])
        code.should eq(1)
        out.should contain("requested = 2.6.0")
      end
    end
  end
end

describe "bundle install --local source description" do
  it "says cached gems or installed locally when the app cache exists" do
    files = {"Gemfile" => "source \"file:///#{local_outdated_index}/\"\n\ngem \"json_pure\", \"2.6.0\"\n"}
    with_project(files) do |dir|
      Dir.mkdir_p(File.join(dir, "vendor", "cache"))
      with_local_outdated_env(dir) do
        code, _, err = run_cli(["install", "--local"])
        code.should eq(7)
        err.should contain("in cached gems or installed locally")
        err.should contain("in gems cached in vendor/cache")
      end
    end
  end

  it "says locally installed gems when there is no app cache" do
    files = {"Gemfile" => "source \"file:///#{local_outdated_index}/\"\n\ngem \"json_pure\", \"2.6.0\"\n"}
    with_project(files) do |dir|
      with_local_outdated_env(dir) do
        code, _, err = run_cli(["install", "--local"])
        code.should eq(7)
        err.should contain("in locally installed gems.")
        err.should_not contain("vendor/cache")
      end
    end
  end
end
