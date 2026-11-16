require "./spec_helper"

# M7(2)/M7(3): `bundle config` semantics (pinned contract:
# `bundler-4.0.24/lib/bundler/cli/config.rb` + `settings.rb#printable_value`).
private def with_config_env(files : Hash(String, String), & : String ->) : Nil
  dir = File.tempname("celerite-spec", "config")
  home = File.join(dir, "home")
  project = File.join(dir, "project")
  Dir.mkdir_p(home)
  Dir.mkdir_p(project)
  # `bundle config` only needs Bundler.root (the local scope); the source
  # line is never resolved here.
  File.write(File.join(project, "Gemfile"), %(source "https://rubygems.org"\n))
  files.each do |name, content|
    path = File.join(project, name)
    Dir.mkdir_p(File.dirname(path)) unless File.dirname(path) == project
    File.write(path, content)
  end

  saved = {} of String => String?
  %w[HOME USERPROFILE BUNDLE_USER_CONFIG BUNDLE_USER_CACHE BUNDLE_USER_PLUGIN BUNDLE_GEMFILE BUNDLE_PATH].each do |key|
    saved[key] = ENV[key]?
  end
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  ENV["BUNDLE_USER_CONFIG"] = File.join(home, ".bundle", "config")
  ENV["BUNDLE_USER_CACHE"] = File.join(home, ".bundle", "cache")
  ENV["BUNDLE_USER_PLUGIN"] = File.join(home, ".bundle", "plugin")
  ENV.delete("BUNDLE_GEMFILE")
  ENV.delete("BUNDLE_PATH")

  original_dir = Dir.current
  begin
    Dir.cd(project)
    yield project
  ensure
    Dir.cd(original_dir)
    saved.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
    FileUtils.rm_rf(dir)
  end
end

describe "bundle config semantics" do
  it "exits zero for unset array/boolean/number defaults, one otherwise" do
    with_config_env({} of String => String) do |_project|
      code, out, _err = run_cli(["config", "get", "without"])
      code.should eq(0)
      out.should contain("You have not configured a value for `without`")

      code, _, _ = run_cli(["config", "get", "retry"])
      code.should eq(0)

      code, _, _ = run_cli(["config", "get", "jobs"])
      code.should eq(1)
    end
  end

  it "redacts credentials and userinfo like the reference printable_value" do
    with_config_env({} of String => String) do |_project|
      run_cli(["config", "set", "gem.push_key", "secret123"])
      code, out, _ = run_cli(["config", "get", "gem.push_key"])
      code.should eq(0)
      out.should contain("[REDACTED]")
      out.should_not contain("secret123")
    end
  end

  it "keeps the legacy `config NAME` interface with a deprecation warning" do
    with_config_env({} of String => String) do |project|
      code, _out, err = run_cli(["config", "without", "development"])
      code.should eq(0)
      err.should contain("[DEPRECATED]")
      err.should contain("Use `bundle config set without development` instead.")
      File.read(File.join(project, ".bundle", "config")).should contain("BUNDLE_WITHOUT")

      code, _out, err = run_cli(["config", "frobnicate"])
      code.should eq(1)
      err.should contain("Use `bundle config get frobnicate` instead.")
    end
  end

  it "rejects both scope switches at once" do
    with_config_env({} of String => String) do |_project|
      code, _out, err = run_cli(["config", "set", "--local", "--global", "path", "vendor/x"])
      code.should eq(15)
      # The reference prints this through `ui.error message, wrap: true`.
      err.should contain("The options global and local were specified. Please only use one of the switches")
      err.should contain("at a time.")
    end
  end

  it "renders parseable output without the human headers" do
    with_config_env({} of String => String) do |_project|
      run_cli(["config", "set", "without", "development"])
      code, out, _ = run_cli(["config", "list", "--parseable"])
      code.should eq(0)
      out.should_not contain("Settings are listed in order of priority")
      out.should contain("without=[:development]")

      code, out, _ = run_cli(["config", "get", "without", "--parseable"])
      code.should eq(0)
      out.strip.should eq("without=[:development]")

      code, out, _ = run_cli(["config", "set", "without", "test", "--parseable"])
      code.should eq(0)
      out.strip.should eq("without=test")
    end
  end

  it "reports Thor-style argument errors" do
    with_config_env({} of String => String) do |_project|
      code, _out, err = run_cli(["config", "list", "extra"])
      code.should eq(15)
      err.should contain(%(ERROR: "bundle config list" was called with arguments ["extra"]))
      err.should contain(%(Usage: "bundle config list"))

      code, _out, err = run_cli(["config", "get", "path", "--global"])
      code.should eq(15)
      err.should contain(%(ERROR: "bundle config get" was called with arguments ["path", "--global"]))
      err.should contain(%(Usage: "bundle config get NAME"))
    end
  end

  it "prints the global config path exactly as configured" do
    with_config_env({} of String => String) do |_project|
      run_cli(["config", "set", "--global", "path", "vendor/global"])
      code, out, _ = run_cli(["config", "get", "path"])
      code.should eq(0)
      out.should contain("Set for the current user (#{ENV["BUNDLE_USER_CONFIG"].gsub(/\\/, "/")})")
    end
  end
end
