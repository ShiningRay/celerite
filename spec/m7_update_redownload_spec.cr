require "./spec_helper"

private def with_redownload_env(&)
  home = File.tempname("celerite-redownload-home", "")
  Dir.mkdir_p(home)
  old_home = ENV["HOME"]?
  old_profile = ENV["USERPROFILE"]?
  old_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  old_profile_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  begin
    yield
  ensure
    old_home ? (ENV["HOME"] = old_home) : ENV.delete("HOME")
    old_profile ? (ENV["USERPROFILE"] = old_profile) : ENV.delete("USERPROFILE")
    old_bridge ? (ENV["CELERITE_BRIDGE_SERVER"] = old_bridge) : ENV.delete("CELERITE_BRIDGE_SERVER")
    old_profile_version ? (ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = old_profile_version) : ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    FileUtils.rm_rf(home)
  end
end

private def redownload_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def with_redownload_bundle_path(path : String, &)
  previous = ENV["BUNDLE_PATH"]?
  ENV["BUNDLE_PATH"] = path
  begin
    yield
  ensure
    previous ? (ENV["BUNDLE_PATH"] = previous) : ENV.delete("BUNDLE_PATH")
  end
end

private def redownload_gemfile : String
  %(source "#{redownload_index_url}"\n\ngem "json_pure"\n)
end

describe "M7(2) update --redownload output" do
  # `--redownload` is an alias of `force` (cli.rb:330): an already cached gem is
  # reinstalled from <bundle>/ruby/<abi>/cache, so the reference prints only the
  # Installing line, never Fetching.
  it "omits Fetching when the package is cached" do
    with_redownload_env do
      with_project({"Gemfile" => redownload_gemfile}) do |dir|
        with_redownload_bundle_path(File.join(dir, "bundle")) do
          run_cli(["install", "--quiet"])[0].should eq(0)
          code, stdout, _stderr = run_cli(["update", "--redownload"])
          code.should eq(0)
          stdout.should contain("Installing json_pure 2.8.1")
          stdout.should_not contain("Fetching json_pure 2.8.1")
        end
      end
    end
  end

  # Declared divergence: the reference aborts with `Bundler::GemNotFound` when
  # the cached package is gone, while celerite re-downloads it (download
  # behaviour intentionally unchanged) and therefore does print Fetching.
  it "prints Fetching when the cache was removed" do
    with_redownload_env do
      with_project({"Gemfile" => redownload_gemfile}) do |dir|
        with_redownload_bundle_path(File.join(dir, "bundle")) do
          run_cli(["install", "--quiet"])[0].should eq(0)
          cached = File.join(dir, "bundle", "ruby", "4.0.0", "cache", "json_pure-2.8.1.gem")
          File.delete(cached)
          code, stdout, _stderr = run_cli(["update", "--redownload"])
          code.should eq(0)
          stdout.should contain("Fetching json_pure 2.8.1")
          stdout.should contain("Installing json_pure 2.8.1")
        end
      end
    end
  end

  it "prints Fetching for a first-time update without a lockfile" do
    with_redownload_env do
      with_project({"Gemfile" => redownload_gemfile}) do |dir|
        with_redownload_bundle_path(File.join(dir, "bundle")) do
          code, stdout, _stderr = run_cli(["update", "--redownload"])
          code.should eq(0)
          stdout.should contain("Fetching json_pure 2.8.1")
          stdout.should contain("Installing json_pure 2.8.1")
          stdout.should end_with("Bundle updated!\n")
        end
      end
    end
  end
end
