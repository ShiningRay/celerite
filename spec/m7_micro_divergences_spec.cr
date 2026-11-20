require "./spec_helper"

# Micro-divergences (M7 task-56): four small surfaces where the reference
# behavior was measured directly.
#   1. `plugin new` is an unknown command (exit 15, `Could not find command "new".`).
#   2. `licenses` sorts by license descending and includes bundler itself
#      (cli.rb:570-583 `Bundler.load.specs.sort_by {|s| s.license.to_s }.reverse_each`).
#   3. `config get` prints the local app config path verbatim: an absolute
#      BUNDLE_APP_CONFIG keeps native separators before the `/config` join.
#   4. `known_unimplemented?` was dead code and is gone; unknown commands keep
#      reporting `Could not find command "<name>".`.

private def micro_with_bridge(&)
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

private def micro_project(&)
  dir = File.join(Dir.tempdir, "celerite-micro-#{Random.rand(1_000_000)}")
  Dir.mkdir_p(dir)
  home = File.join(dir, "home")
  Dir.mkdir_p(home)
  home_previous = ENV["HOME"]?
  profile_previous = ENV["USERPROFILE"]?
  gemfile_previous = ENV["BUNDLE_GEMFILE"]?
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  previous_dir = Dir.current
  Dir.cd(dir)
  begin
    yield dir
  ensure
    Dir.cd(previous_dir)
    {"HOME" => home_previous, "USERPROFILE" => profile_previous, "BUNDLE_GEMFILE" => gemfile_previous}.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
    FileUtils.rm_rf(dir)
  end
end

private def micro_write_gemfile(dir : String, gems : Array(String))
  File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\n\n" + gems.map { |g| "gem \"#{g}\"\n" }.join)
end

describe "M7 task-56 micro divergences" do
  it "reports plugin new as an unknown command" do
    micro_project do |dir|
      micro_write_gemfile(dir, ["json_pure"])
      code, stdout, stderr = run_cli(["plugin", "new", "foo"])
      code.should eq(15)
      stdout.should eq("")
      stderr.should eq("Could not find command \"new\".\n")
    end
  end

  it "sorts licenses by license and includes bundler" do
    micro_project do |dir|
      micro_write_gemfile(dir, ["json_pure", "thor"])
      bundle = File.join(dir, "bundle")
      # The license reader looks in `<bundle>/ruby/<abi>/cache` (host ABI 4.0.0).
      cache = File.join(bundle, "ruby", "4.0.0", "cache")
      Dir.mkdir_p(cache)
      File.join(dir, "Gemfile.lock").tap do |path|
        File.write(path, <<-LOCK)
GEM
  remote: https://rubygems.org/
  specs:
    json_pure (2.8.1)
    thor (1.3.2)

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  json_pure
  thor

BUNDLED WITH
   4.0.24
LOCK
      end
      %w[json_pure-2.8.1.gem thor-1.3.2.gem].each do |name|
        FileUtils.cp(File.expand_path("../fixtures/gem-index/gems/#{name}", __DIR__), File.join(cache, name))
      end
      ENV["BUNDLE_PATH"] = bundle
      ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
      begin
        micro_with_bridge do
          code, stdout, _stderr = run_cli(["licenses"])
          code.should eq(0)
          stdout.should eq("json_pure: Ruby\nbundler: MIT\nthor: MIT\n")
        end
      ensure
        ENV.delete("BUNDLE_PATH")
        ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
      end
    end
  end

  it "keeps native separators for an absolute BUNDLE_APP_CONFIG" do
    micro_project do |dir|
      micro_write_gemfile(dir, ["json_pure"])
      appcfg = File.join(dir, "appcfg")
      Dir.mkdir_p(appcfg)
      File.write(File.join(appcfg, "config"), "---\nBUNDLE_FOO: \"bar\"\n")
      previous = ENV["BUNDLE_APP_CONFIG"]?
      ENV["BUNDLE_APP_CONFIG"] = appcfg
      begin
        code, stdout, _stderr = run_cli(["config", "get", "foo"])
        code.should eq(0)
        stdout.should contain("Set for your local app (#{appcfg}/config): \"bar\"")
      ensure
        if previous
          ENV["BUNDLE_APP_CONFIG"] = previous
        else
          ENV.delete("BUNDLE_APP_CONFIG")
        end
      end
    end
  end

  it "prints the default local app config path with forward slashes" do
    micro_project do |dir|
      micro_write_gemfile(dir, ["json_pure"])
      Dir.mkdir_p(File.join(dir, ".bundle"))
      File.write(File.join(dir, ".bundle", "config"), "---\nBUNDLE_FOO: \"bar\"\n")
      expected = File.join(dir, ".bundle", "config").gsub('\\', "/")
      code, stdout, _stderr = run_cli(["config", "get", "foo"])
      code.should eq(0)
      stdout.should contain("Set for your local app (#{expected}): \"bar\"")
    end
  end

  it "keeps the unknown-command wording after removing known_unimplemented?" do
    micro_project do |_dir|
      code, _stdout, stderr = run_cli(["nosuchcmd"])
      code.should eq(15)
      stderr.should contain("Could not find command \"nosuchcmd\".")
    end
  end
end
