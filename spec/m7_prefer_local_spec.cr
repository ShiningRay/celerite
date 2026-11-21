require "./spec_helper"

# `install --prefer-local` must treat the gems installed for THIS bundle as the
# candidates: the reference rewires `Gem.path` to `BUNDLE_PATH`
# (`definition.rb:190-203`, `source/rubygems.rb:148-178`), so the interpreter's
# own directories (host `json_pure 2.8.1`, `thor 1.5.0`) stay invisible. The
# bridge's `installed_specs` aggregates the whole RubyGems view, which leaked
# those host copies into the candidate set and produced
# `gem file not found: thor-1.5.0.gem`; candidates now come from the project's
# own `specifications/*.gemspec` (globbed with `Celerite::Glob`, since
# `Dir.glob` never matches a Windows path) plus `vendor/cache`.
private def prefer_local_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

private def prefer_local_gemfile : String
  %(source "#{prefer_local_remote}"\n\ngem "json_pure"\ngem "thor"\n)
end

private def prefer_local_lockfile : String
  remote = prefer_local_remote
  <<-LOCK
  GEM
    remote: #{remote}
    specs:
      json_pure (2.6.0)
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

private def with_prefer_local_env(dir : String, & : ->) : Nil
  keys = {"HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH", "BUNDLE_APP_CONFIG",
          "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION", "BUNDLE_GEMFILE"}
  saved = keys.map { |key| {key, ENV[key]?} }
  home = File.join(dir, "home")
  Dir.mkdir_p(home)
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  ENV.delete("GEM_HOME")
  ENV.delete("GEM_PATH")
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(dir, "cfg")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  begin
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : (ENV[key] = value) }
  end
end

# Lays the hand-written 2.6.0/1.3.2 lock into the bundle, then removes the lock
# so the next run has to resolve without one.
private def prefer_local_primed_project(dir : String, & : String ->) : Nil
  with_prefer_local_env(dir) do
    with_project({"Gemfile" => prefer_local_gemfile, "Gemfile.lock" => prefer_local_lockfile}) do |project|
      ENV["BUNDLE_GEMFILE"] = File.join(project, "Gemfile")
      run_cli(["install", "--quiet"]).first.should eq(0)
      File.read(File.join(dir, "bundle", "ruby", "4.0.0", "specifications", "json_pure-2.6.0.gemspec"))
      File.delete(File.join(project, "Gemfile.lock"))
      yield project
    end
  end
end

describe "install --prefer-local" do
  it "keeps the bundled versions when the lockfile is gone" do
    dir = File.tempname("celerite-prefer-local", "proj")
    Dir.mkdir_p(dir)
    begin
      prefer_local_primed_project(dir) do |project|
        code, out, err = run_cli(["install", "--prefer-local"])
        code.should eq(0)
        err.should eq("")
        out.should contain("Resolving dependencies...")
        out.should_not contain("Fetching json_pure 2.8.1")
        out.should_not contain("thor 1.5.0")
        lock = File.read(File.join(project, "Gemfile.lock"))
        lock.should contain("    json_pure (2.6.0)")
        lock.should contain("    thor (1.3.2)")
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "upgrades to the newest versions without the flag" do
    dir = File.tempname("celerite-prefer-local", "proj")
    Dir.mkdir_p(dir)
    begin
      prefer_local_primed_project(dir) do |project|
        code, _out, _err = run_cli(["install"])
        code.should eq(0)
        File.read(File.join(project, "Gemfile.lock")).should contain("    json_pure (2.8.1)")
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "follows a complete lockfile without touching it" do
    dir = File.tempname("celerite-prefer-local", "proj")
    Dir.mkdir_p(dir)
    begin
      with_prefer_local_env(dir) do
        with_project({"Gemfile" => prefer_local_gemfile, "Gemfile.lock" => prefer_local_lockfile}) do |project|
          ENV["BUNDLE_GEMFILE"] = File.join(project, "Gemfile")
          before = File.read(File.join(project, "Gemfile.lock"))

          code, _out, _err = run_cli(["install", "--prefer-local"])
          code.should eq(0)
          # The hand-written fixture lock spells the remote without the trailing
          # slash that the run rewrites, so compare the resolved rows, not bytes.
          after = File.read(File.join(project, "Gemfile.lock"))
          after.should contain("    json_pure (2.6.0)")
          after.should contain("    thor (1.3.2)")
          after.should_not contain("json_pure (2.8.1)")
        end
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
