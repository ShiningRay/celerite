require "./spec_helper"

# `bundle cache` declares only all/all-platforms/cache-path/cooldown/frozen/
# gemfile/no-install/no-prune/path/quiet (`bundler/cli.rb:466-497`), and it always
# runs the install pipeline (`CLI::Cache#run` -> `CLI::Install`), where
# `--no-install` only suppresses unpacking the packages
# (`source/rubygems.rb:211`).
private def with_cache_switch_env(project : String, &)
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
  # `with_project` chdirs into the temporary project, so the bridge script has
  # to be spelled out; the default `install` path already requires it.
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

private def cache_switch_project : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {
    "Gemfile" => "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"json_pure\", \"2.8.1\"\n",
  }
end

private def cache_switch_glob(pattern : String) : Array(String)
  # `Dir.glob` treats `\` as an escape on Windows, so the joined native pattern
  # never matches; normalise before globbing.
  Dir.glob(pattern.gsub('\\', "/"))
end

private def cache_switch_bundle_gem(project : String, name : String) : String?
  cache_switch_glob(File.join(project, "bundle", "ruby", "*", "cache", name)).first?
end

describe "bundle cache switch surface" do
  it "rejects install-only switches with the reference suggestion" do
    with_project(cache_switch_project) do |dir|
      with_cache_switch_env(dir) do
        code, out, err = run_cli(["cache", "--force"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--force\"\nDid you mean?  \"--frozen\"\n")

        code, out, err = run_cli(["cache", "--local"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--local\"\n")

        code, out, err = run_cli(["cache", "--without", "dev"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--without\"\n")
      end
    end
  end

  it "rejects --path with the cache-specific removed message" do
    with_project(cache_switch_project) do |dir|
      with_cache_switch_env(dir) do
        code, out, err = run_cli(["cache", "--path", "vendor/x"])
        code.should eq(15)
        out.should eq("")
        message = "The `--path` flag has been removed because its semantics were unclear. Use `bundle config cache_path` to configure the path of your cache of gems, and `bundle config path` to configure the path where your gems are installed, and stop using this flag"
        err.should eq("#{Celerite::Commands.word_wrap(message, 80)}\n")
      end
    end
  end

  it "caches without unpacking the gems under --no-install" do
    with_project(cache_switch_project) do |dir|
      with_cache_switch_env(dir) do
        code, out, err = run_cli(["cache", "--no-install"])
        code.should eq(0), err
        out.should contain("Bundle complete! 1 Gemfile dependency, 1 gem now installed.")
        out.should contain("Updating files in vendor/cache")
        out.should contain("  * json_pure-2.8.1.gem")

        File.file?(File.join(dir, "Gemfile.lock")).should be_true
        cache_switch_bundle_gem(dir, "json_pure-2.8.1.gem").should_not be_nil
        File.file?(File.join(dir, "vendor", "cache", "json_pure-2.8.1.gem")).should be_true
        Dir.glob(File.join(dir, "bundle", "ruby", "*", "gems", "json_pure-2.8.1").gsub('\\', "/")).should be_empty
        Dir.glob(File.join(dir, "bundle", "ruby", "*", "specifications", "json_pure-2.8.1.gemspec").gsub('\\', "/")).should be_empty
      end
    end
  end
end
