require "./spec_helper"

# `cli/clean.rb:11-24`: `bundle clean` refuses to prune a system-wide gem set
# unless `--force` is given, because with no `path` configured the install root
# is the RubyGems directory. `--dry-run` never reaches the guard.
private GEM_INDEX_URL = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def clean_gemfile : String
  <<-GEMFILE
  source "#{GEM_INDEX_URL}"
  gem "json_pure"
  GEMFILE
end

describe "bundle clean system-gems guard" do
  it "refuses to clean system gems without --force and deletes nothing" do
    with_project({"Gemfile" => clean_gemfile}) do |dir|
      gem_home = File.join(dir, "gemhome")
      kept = File.join(gem_home, "gems", "kept-1.0.0")
      Dir.mkdir_p(kept)
      with_clean_env(dir, gem_home) do
        code, _, err = run_cli(["clean"])
        code.should eq(15)
        err.should contain("Cleaning all the gems on your system is dangerous!")
        err.should contain("run `bundle clean --force`.")
        Dir.exists?(kept).should be_true
      end
    end
  end

  it "keeps the guard out of the --dry-run path" do
    with_project({"Gemfile" => clean_gemfile}) do |dir|
      gem_home = File.join(dir, "gemhome")
      Dir.mkdir_p(gem_home)
      with_clean_env(dir, gem_home) do
        run_cli(["install", "--quiet"]).first.should eq(0)
        code, _, err = run_cli(["clean", "--dry-run"])
        code.should eq(0)
        err.should_not contain("Cleaning all the gems on your system is dangerous!")
      end
    end
  end

  it "skips the guard when a bundle path is configured" do
    with_project({"Gemfile" => clean_gemfile}) do |dir|
      gem_home = File.join(dir, "gemhome")
      Dir.mkdir_p(gem_home)
      with_clean_env(dir, gem_home, bundle_path: File.join(dir, "bundle")) do
        run_cli(["install", "--quiet"]).first.should eq(0)
        code, _, err = run_cli(["clean"])
        code.should eq(0)
        err.should_not contain("Cleaning all the gems on your system is dangerous!")
      end
    end
  end
end

# The guard keys off `Path#use_system_gems?`, so the sandbox has to look like a
# system-gem install: no `BUNDLE_PATH` at all (an empty value is still an
# explicit path for Bundler) and an isolated `GEM_HOME` so a regression cannot
# touch the developer's gems.
private def with_clean_env(dir : String, gem_home : String, bundle_path : String? = nil, &) : Nil
  names = %w[BUNDLE_PATH BUNDLE_APP_CONFIG HOME USERPROFILE GEM_HOME GEM_PATH CELERITE_BRIDGE_SERVER]
  saved = {} of String => String?
  names.each { |name| saved[name] = ENV[name]? }
  begin
    Dir.mkdir_p(gem_home)
    app_config = File.join(dir, ".bundle-app")
    Dir.mkdir_p(app_config)
    ENV.delete("BUNDLE_PATH")
    ENV["BUNDLE_APP_CONFIG"] = app_config
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["GEM_HOME"] = gem_home
    ENV["GEM_PATH"] = gem_home
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["BUNDLE_PATH"] = bundle_path if bundle_path
    yield
  ensure
    names.each do |name|
      value = saved[name]
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end
