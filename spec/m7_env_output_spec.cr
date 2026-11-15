require "./spec_helper"
require "../src/celerite"

private def env_gemfile
  "source \"https://rubygems.org\"\n"
end

private def with_env_var(name : String, value : String?, &)
  previous = ENV[name]?
  if value
    ENV[name] = value
  else
    ENV.delete(name)
  end
  begin
    yield
  ensure
    if previous
      ENV[name] = previous
    else
      ENV.delete(name)
    end
  end
end

private def with_env_bridge(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
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

describe "Celerite::CLI env output" do
  it "prints only the profile bundler version" do
    with_env_bridge do
      with_project({"Gemfile" => env_gemfile}) do
        code, out, _err = run_cli(["env"])
        code.should eq(0)
        bundler_line = out.lines.find { |line| line.starts_with?("Bundler ") }.not_nil!
        expected = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        bundler_line.should eq("Bundler       #{expected}")
        bundler_line.should_not contain("compatibility profile")
      end
    end
  end

  it "prints the reference placeholder when the lockfile is missing" do
    with_env_bridge do
      with_project({"Gemfile" => env_gemfile}) do
        code, out, _err = run_cli(["env"])
        code.should eq(0)
        out.should contain("<No ")
        out.should contain("Gemfile.lock found>")
        out.should end_with("```\n")
      end
    end
  end

  it "prints a Bundler settings section when BUNDLE_PATH is set" do
    with_env_bridge do
      with_env_var("BUNDLE_PATH", "vendor/bundle") do
        with_project({"Gemfile" => env_gemfile}) do
          code, out, _err = run_cli(["env"])
          code.should eq(0)
          out.should contain("## Bundler settings\n\n```\npath\n")
          out.should contain("Set via BUNDLE_PATH")
        end
      end
    end
  end
end
