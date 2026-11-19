require "./spec_helper"
require "../src/celerite"

# `bundle issue` must build the report from the current definition and hand the
# doctor section to the same code path as `bundle doctor` (cli/issue.rb:33-38):
# no lockfile is not an error, the lockfile sections always print (with the
# `Env.read_file` placeholder when absent), and a satisfied bundle writes the
# lockfile the reference would have written.
private def issue_gemfile : String
  "source \"https://rubygems.org\"\n"
end

private def with_issue_env(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  home = File.tempname("celerite-issue-home")
  bundle = File.tempname("celerite-issue-bundle")
  Dir.mkdir_p(home)
  Dir.mkdir_p(File.join(bundle, "ruby", "4.0.0"))
  previous_server = ENV["CELERITE_BRIDGE_SERVER"]?
  previous_home = ENV["HOME"]?
  previous_bundle = ENV["BUNDLE_PATH"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
  ENV["HOME"] = home
  ENV["BUNDLE_PATH"] = bundle
  begin
    yield
  ensure
    if previous_server
      ENV["CELERITE_BRIDGE_SERVER"] = previous_server
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
    if previous_home
      ENV["HOME"] = previous_home
    else
      ENV.delete("HOME")
    end
    if previous_bundle
      ENV["BUNDLE_PATH"] = previous_bundle
    else
      ENV.delete("BUNDLE_PATH")
    end
  end
end

describe "Celerite::CLI issue report" do
  it "resolves a Gemfile without a lockfile instead of failing" do
    with_issue_env do
      with_project({"Gemfile" => issue_gemfile}) do |dir|
        code, out, err = run_cli(["issue"])
        code.should eq(0)
        err.should_not contain("Could not locate Gemfile")
        out.should contain("## Gemfile\n\n### Gemfile\n\n```ruby\nsource \"https://rubygems.org\"\n```")
        out.should contain("### Gemfile.lock")
        out.should contain("<No #{File.join(dir, "Gemfile.lock").gsub('\\', "/")} found>")
        out.should contain("## Bundle Doctor")
        out.should contain("The Gemfile's dependencies are satisfied")
        out.should contain("No issues found with the installed bundle")
        File.exists?(File.join(dir, "Gemfile.lock")).should be_true
      end
    end
  end

  it "matches the doctor report for the same project" do
    with_issue_env do
      issue_out = ""
      with_project({"Gemfile" => issue_gemfile}) do
        _code, out, _err = run_cli(["issue"])
        issue_out = out
      end
      doctor_out = ""
      with_project({"Gemfile" => issue_gemfile}) do
        _code, out, _err = run_cli(["doctor"])
        doctor_out = out
      end
      # Both commands end with the same doctor body (cli/issue.rb:33-38).
      issue_out.should contain(doctor_out.lstrip("\n"))
    end
  end

  it "shares the Gemfile sections with env" do
    with_issue_env do
      with_project({"Gemfile" => issue_gemfile}) do
        _code, env_out, _err = run_cli(["env"])
        _code2, issue_out, _err2 = run_cli(["issue"])
        env_section = env_out.split("## Gemfile\n", 2)[1]
        issue_section = issue_out.split("## Gemfile\n", 2)[1]
        issue_section.starts_with?(env_section.split("## Gemspecs").first).should be_true
      end
    end
  end
end
