require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(1): frozen mode must reject "unlocking ruby" instead of re-resolving.
# Oracle (bundler 4.0.24): `check` exits 16 with the two-line message;
# `show`/`show --paths`/`info` do not run that check and still exit 0;
# `list` keeps listing but does not announce `Resolving dependencies...`;
# 2.7.2 has no such guard (exit 0, plain "satisfied" output).
private def frozen_unlock_fixture_dir : String
  File.expand_path(File.join(__DIR__, "..", "fixtures", "differential", "check-satisfied-nolock-ruby"))
end

private def frozen_unlock_index_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

private def frozen_unlock_files : Hash(String, String)
  base = frozen_unlock_fixture_dir
  gemfile = File.read(File.join(base, "Gemfile")).gsub("@INDEX_DIR@", frozen_unlock_index_remote)
  lock = File.read(File.join(base, "Gemfile.lock"))
    .gsub("@INDEX_DIR@", frozen_unlock_index_remote)
    .gsub("@BUNDLER_VERSION@", "4.0.24")
  {"Gemfile" => gemfile, "Gemfile.lock" => lock}
end

private def with_frozen_unlock_bridge(&)
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

private def with_frozen_env(pairs : Hash(String, String?), &)
  previous = {} of String => String?
  pairs.each_key { |key| previous[key] = ENV[key]? }
  pairs.each do |key, value|
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
  begin
    yield
  ensure
    previous.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def prepare_frozen_unlock_bundle(dir : String) : Nil
  bundle = File.join(dir, "bundle")
  Dir.mkdir_p(bundle)
  FileUtils.cp_r(File.join(frozen_unlock_fixture_dir, "bundle-preset", "ruby"), File.join(bundle, "ruby"))
  Dir.mkdir_p(File.join(dir, "home"))
end

private def frozen_unlock_env(dir : String, frozen : Bool) : Hash(String, String?)
  {
    "BUNDLE_PATH"       => File.join(dir, "bundle"),
    "HOME"              => File.join(dir, "home"),
    "USERPROFILE"       => File.join(dir, "home"),
    "BUNDLE_FROZEN"     => frozen ? "true" : nil,
    "BUNDLE_DEPLOYMENT" => nil,
  }
end

private def run_frozen_unlock(args : Array(String), frozen : Bool) : {Int32, String, String}
  with_frozen_unlock_bridge do
    with_project(frozen_unlock_files) do
      dir = Dir.current
      prepare_frozen_unlock_bundle(dir)
      with_frozen_env(frozen_unlock_env(dir, frozen)) do
        return run_cli(args)
      end
    end
  end
end

private def run_frozen_unlock_with(args : Array(String), env : Hash(String, String?)) : {Int32, String, String}
  with_frozen_unlock_bridge do
    with_project(frozen_unlock_files) do
      dir = Dir.current
      prepare_frozen_unlock_bundle(dir)
      with_frozen_env(frozen_unlock_env(dir, false).merge(env)) do
        return run_cli(args)
      end
    end
  end
end

FROZEN_UNLOCK_MESSAGE = "Bundler is unlocking ruby, but the lockfile can't be updated because frozen mode\nis set\n"

DEPLOY_UNLOCK_HINT = "If this is a development machine, remove the Gemfile.lock freeze by running `bundle config set frozen false`."

describe "M7(1) frozen ruby unlocking" do
  it "rejects ruby unlocking in `check` when frozen" do
    code, out, err = run_frozen_unlock(["check"], true)
    code.should eq(16)
    out.should eq("")
    err.should eq(FROZEN_UNLOCK_MESSAGE)
  end

  it "keeps `show` listing gems when frozen (no production check)" do
    code, out, err = run_frozen_unlock(["show"], true)
    code.should eq(0)
    err.should eq("")
    out.should contain("Gems included by the bundle:")
    out.should contain("json_pure (2.8.1)")
  end

  it "keeps `show --paths` working when frozen" do
    code, out, err = run_frozen_unlock(["show", "--paths"], true)
    code.should eq(0)
    err.should eq("")
    out.should contain("json_pure-2.8.1")
  end

  it "keeps `info` working when frozen" do
    code, out, err = run_frozen_unlock(["info", "json_pure"], true)
    code.should eq(0)
    err.should eq("")
    out.should contain("json_pure (2.8.1)")
    out.should contain("Path:")
  end

  it "keeps `list` working but silent about resolving when frozen" do
    code, out, err = run_frozen_unlock(["list"], true)
    code.should eq(0)
    err.should eq("")
    out.should_not contain("Resolving dependencies...")
    out.should contain("Gems included by the bundle:")
    out.should contain("json_pure (2.8.1)")
  end

  it "still announces resolving and succeeds when not frozen" do
    code, out, err = run_frozen_unlock(["check"], false)
    code.should eq(0)
    err.should eq("")
    out.should eq("Resolving dependencies...\nThe Gemfile's dependencies are satisfied\n")
  end

  it "prints the resolve notice for `check` under a 2.7.2 profile when not frozen" do
    code, out, err = run_frozen_unlock_with(["check"], {"CELERITE_PROFILE_BUNDLER_VERSION" => "2.7.2"})
    code.should eq(0)
    err.should eq("")
    out.should contain("Resolving dependencies...")
    out.should contain("The Gemfile's dependencies are satisfied")
  end

  it "prints the resolve notice for `list` under a 2.7.2 profile when not frozen" do
    code, out, err = run_frozen_unlock_with(["list"], {"CELERITE_PROFILE_BUNDLER_VERSION" => "2.7.2"})
    code.should eq(0)
    err.should eq("")
    out.should contain("Resolving dependencies...")
    out.should contain("json_pure (2.8.1)")
  end

  it "accepts the unlock under a frozen 2.7.2 profile (no production check)" do
    code, out, err = run_frozen_unlock_with(["check"], {"CELERITE_PROFILE_BUNDLER_VERSION" => "2.7.2", "BUNDLE_FROZEN" => "true"})
    code.should eq(0)
    err.should eq("")
    out.should eq("The Gemfile's dependencies are satisfied\n")
  end

  it "adds the remove-the-freeze hint when frozen comes from deployment mode" do
    code, out, err = run_frozen_unlock_with(["check"], {"BUNDLE_DEPLOYMENT" => "true"})
    code.should eq(16)
    out.should eq("")
    err.should start_with("Bundler is unlocking ruby, but the lockfile can't be updated because frozen mode")
    err.should contain("\n\n")
    # The hint is wrapped by the friendly-error renderer; compare normalized
    # whitespace here and let the differential fixture pin the exact layout.
    err.gsub(/\s+/, " ").should contain(DEPLOY_UNLOCK_HINT)
  end
end
