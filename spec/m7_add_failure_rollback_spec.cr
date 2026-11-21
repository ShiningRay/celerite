require "./spec_helper"

# M7 task-81: a failed `bundle add` must leave the Gemfile untouched.
# `Injector` resolves/installs the injected dependency before appending the
# line, so every failure path exits with the original bytes; we append first
# (the lock regeneration needs the new dependency) and restore on failure.
private def add_failure_index : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def add_failure_gemfile : String
  "source \"#{add_failure_index}\"\n"
end

private def with_add_failure_env(dir : String, &)
  keys = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_APP_CONFIG CELERITE_BRIDGE_SERVER]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]? }
  ENV["HOME"] = File.join(dir, "home")
  ENV["USERPROFILE"] = File.join(dir, "home")
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(dir, "appcfg")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  Dir.mkdir_p(ENV["HOME"])
  Dir.mkdir_p(ENV["BUNDLE_APP_CONFIG"])
  begin
    yield
  ensure
    keys.each do |key|
      if value = previous[key]
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

describe "M7 bundle add failure rollback" do
  it "keeps the Gemfile untouched when the gem is missing from the index" do
    with_project({"Gemfile" => add_failure_gemfile}) do |dir|
      with_add_failure_env(dir) do
        code, out, err = run_cli(["add", "nosuchgem", "--skip-install"])
        code.should eq(7)
        err.should contain("Could not find gem 'nosuchgem' in rubygems repository")
        # The resolver announcement only appears once the index answers for the
        # gem; a missing gem stops after the fetch line.
        out.should_not contain("Resolving dependencies...")
        File.read(File.join(dir, "Gemfile")).should eq(add_failure_gemfile)
      end
    end
  end

  it "keeps the Gemfile untouched for an invalid requirement pattern" do
    with_project({"Gemfile" => add_failure_gemfile}) do |dir|
      with_add_failure_env(dir) do
        code, _out, err = run_cli(["add", "json_pure", "--version", "bogus", "--skip-install"])
        code.should eq(15)
        err.should contain("Invalid gem requirement pattern 'bogus'")
        File.read(File.join(dir, "Gemfile")).should eq(add_failure_gemfile)
      end
    end
  end

  it "keeps the Gemfile untouched when --path points at a missing directory" do
    with_project({"Gemfile" => add_failure_gemfile}) do |dir|
      with_add_failure_env(dir) do
        code, _out, err = run_cli(["add", "json_pure", "--path", "vendor/nope", "--skip-install"])
        code.should eq(13)
        err.should contain("does not exist.")
        File.read(File.join(dir, "Gemfile")).should eq(add_failure_gemfile)
      end
    end
  end
end
