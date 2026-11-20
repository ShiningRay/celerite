require "./spec_helper"

# M7(2) task-65: the "built in to Ruby" handling keys on the resolved spec's
# ORIGIN, not on "the interpreter ships a gem with this name and version"
# (`source/rubygems.rb:181`, `:206` gate on `spec.default_gem?`). A lock/index
# row that merely matches a shipped default gem is a normal remote spec: the
# reference fetches and installs it. Regression guard for
# `fixtures/differential/lock-missing-dependency-edges`.
# The dev machine can have net-protocol installed already; isolate the bundle
# so "Fetching"/"Installing" reflect the fixture index only.
def with_origin_sandbox(dir : String, &) : Nil
  keys = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_APP_CONFIG GEM_HOME GEM_PATH]
  saved = keys.map { |key| {key, ENV[key]?} }
  home = File.join(dir, "home")
  Dir.mkdir_p(home)
  app_config = File.join(dir, "appcfg")
  Dir.mkdir_p(app_config)
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = app_config
  ENV.delete("GEM_HOME")
  ENV.delete("GEM_PATH")
  begin
    yield
  ensure
    saved.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

describe "M7 default gem origin" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end

  it "installs a locked gem that shares a name and version with a default gem" do
    index = file_source_url(File.expand_path("../fixtures/gem-index-locked-deps", __DIR__))
    lock = <<-LOCK
    GEM
      remote: #{index}/
      specs:
        net-protocol (0.2.2)
        net-smtp (0.5.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      net-smtp
    LOCK
    with_project({
      "Gemfile"      => %(source "#{index}"\n\ngem "net-smtp"\n),
      "Gemfile.lock" => lock,
    }) do |dir|
      with_origin_sandbox(dir) do
        code, stdout, stderr = run_cli(["install"])
        code.should eq(0)
        stderr.should_not contain("is built in to Ruby")
        stdout.should contain("Fetching net-protocol 0.2.2")
        stdout.should contain("Installing net-protocol 0.2.2")
        stdout.should contain("Installing net-smtp 0.5.0")
      end
    end
  end

  it "keeps the built-in warning when the index has no candidate" do
    index = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))
    with_project({"Gemfile" => %(source "#{index}"\n\ngem "json"\n)}) do |_dir|
      run_cli(["lock"])
      code, _stdout, stderr = run_cli(["install"])
      code.should eq(0)
      stderr.should contain("is built in to Ruby")
      stderr.should contain("json-")
    end
  end
end
