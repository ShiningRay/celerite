require "./spec_helper"

private def with_remove_bridge(&)
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

private def remove_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def remove_project(files : Hash(String, String), & : String ->) : Nil
  with_project(files) do |dir|
    previous_home = ENV["HOME"]?
    previous_profile = ENV["USERPROFILE"]?
    previous_bundle_path = ENV["BUNDLE_PATH"]?
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, ".bundle-test")
    begin
      yield dir
    ensure
      previous_home ? (ENV["HOME"] = previous_home) : ENV.delete("HOME")
      previous_profile ? (ENV["USERPROFILE"] = previous_profile) : ENV.delete("USERPROFILE")
      previous_bundle_path ? (ENV["BUNDLE_PATH"] = previous_bundle_path) : ENV.delete("BUNDLE_PATH")
    end
  end
end

private def remove_gemfile : String
  "source \"#{remove_remote}\"\n\ngem \"json_pure\", \"= 2.6.0\"\n"
end

# The reference rewrites the Gemfile through `File.puts` in text mode, which on
# Windows ends every line with CRLF (injector.rb:212 + shared_helpers.rb:205-217).
# Compare line structure, not the platform line-ending byte pair.
private def remove_gemfile_on_disk(dir : String) : String
  File.read(File.join(dir, "Gemfile")).gsub("\r\n", "\n")
end

describe "M7(3) bundle remove failure modes" do
  # Reference: cli.rb:246-248 raises InvalidOption before Remove#run, so the
  # Gemfile is never touched and no install is triggered.
  it "rejects --install with exit 15 and leaves the Gemfile untouched" do
    with_remove_bridge do
      remove_project({"Gemfile" => remove_gemfile}) do |dir|
        code, out, err = run_cli(["remove", "--install", "json_pure"])
        code.should eq(15)
        out.should eq("")
        err.should eq("The `--install` flag has been removed. `bundle install` is triggered by default.\n")
        File.read(File.join(dir, "Gemfile")).should eq(remove_gemfile)
      end
    end
  end

  # Unknown switches are rejected by Thor before the --install guard, so the
  # ordering of the two checks is observable.
  it "checks unknown switches before the --install guard" do
    with_remove_bridge do
      remove_project({"Gemfile" => remove_gemfile}) do
        code, out, err = run_cli(["remove", "--install", "json_pure", "--bogus"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--bogus\"\n")
      end
    end
  end

  it "requires at least one gem name with the reference wording (exit 15)" do
    with_remove_bridge do
      remove_project({"Gemfile" => remove_gemfile}) do
        code, out, err = run_cli(["remove"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Please specify gems to remove.\n")
      end
    end
  end

  # Reference: injector.rb:138 prints the header before eval/validation, and
  # friendly_errors wraps the GemfileError message at 80 columns.
  it "reports an undeclared gem with exit 4 after printing the Gemfile header" do
    with_remove_bridge do
      remove_project({"Gemfile" => remove_gemfile}) do |dir|
        code, out, err = run_cli(["remove", "nosuchgem"])
        code.should eq(4)
        display = File.join(dir, "Gemfile").gsub('\\', "/")
        out.should eq("Removing gems from #{display}\n")
        err.should contain("`nosuchgem` is not specified in")
        err.should contain("so it could not be removed.")
        err.lines.size.should be >= 2 # wrapped, not one long line
        File.read(File.join(dir, "Gemfile")).should eq(remove_gemfile)
      end
    end
  end

  # Reference: injector.rb:210 removes the `end`-terminated block once it holds
  # no gems (remove_nested_blocks), so no empty `group ... end` remnant stays.
  it "removes the enclosing group block along with its last gem" do
    with_remove_bridge do
      gemfile = "source \"#{remove_remote}\"\n\ngem \"json_pure\", \"= 2.6.0\"\n\ngroup :dev do\n  gem \"thor\"\nend\n"
      remove_project({"Gemfile" => gemfile}) do |dir|
        code, out, _err = run_cli(["install"])
        code.should eq(0)
        code, out, err = run_cli(["remove", "thor"])
        code.should eq(0)
        out.should contain("thor was removed.")
        err.should eq("")
        remove_gemfile_on_disk(dir).should eq(remove_gemfile)
      end
    end
  end
end
