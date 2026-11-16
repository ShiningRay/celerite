require "./spec_helper"

private def with_add_remove_bridge(&)
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

private def add_remove_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def add_remove_project(files : Hash(String, String), & : String ->) : Nil
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

describe "M7(2) bundle add/remove switch surface" do
  it "rejects unknown switches before requiring a gem name (exit 15)" do
    with_add_remove_bridge do
      add_remove_project({"Gemfile" => "source \"#{add_remove_remote}\"\n"}) do
        code, out, err = run_cli(["add", "--bogus"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--bogus\"\n")
      end
    end
  end

  it "rejects --strict together with --optimistic (exit 15, period)" do
    with_add_remove_bridge do
      add_remove_project({"Gemfile" => "source \"#{add_remove_remote}\"\n"}) do
        code, _out, err = run_cli(["add", "json_pure", "--strict", "--optimistic"])
        code.should eq(15)
        err.should eq("You cannot specify `--strict` and `--optimistic` at the same time.\n")
      end
    end
  end

  it "adds the gem with an exact requirement and installs it" do
    with_add_remove_bridge do
      add_remove_project({"Gemfile" => "source \"#{add_remove_remote}\"\n"}) do |dir|
        code, out, _err = run_cli(["add", "json_pure", "--version=2.8.1"])
        code.should eq(0)
        out.should contain("Installing json_pure 2.8.1")
        File.read(File.join(dir, "Gemfile")).should contain("gem \"json_pure\", \"= 2.8.1\"")
      end
    end
  end

  it "prints the Gemfile requirement when removing a pinned gem" do
    with_add_remove_bridge do
      add_remove_project({"Gemfile" => "source \"#{add_remove_remote}\"\n\ngem \"json_pure\", \"~> 2.8\"\n"}) do |dir|
        run_cli(["install"])
        code, out, _err = run_cli(["remove", "json_pure"])
        code.should eq(0)
        out.should contain("json_pure (~> 2.8) was removed.")
        File.read(File.join(dir, "Gemfile")).should_not contain("gem \"json_pure\"")
      end
    end
  end

  it "prints the exact requirement form for an equality pin" do
    with_add_remove_bridge do
      add_remove_project({"Gemfile" => "source \"#{add_remove_remote}\"\n\ngem \"json_pure\", \"= 2.8.1\"\n"}) do |dir|
        run_cli(["install"])
        code, out, _err = run_cli(["remove", "json_pure"])
        code.should eq(0)
        out.should contain("json_pure (= 2.8.1) was removed.")
        File.read(File.join(dir, "Gemfile")).should_not contain("gem \"json_pure\"")
      end
    end
  end

  it "adds the equality operator for a bare version requirement" do
    with_add_remove_bridge do
      add_remove_project({"Gemfile" => "source \"#{add_remove_remote}\"\n\ngem \"json_pure\", \"2.8.1\"\n"}) do |dir|
        run_cli(["install"])
        code, out, _err = run_cli(["remove", "json_pure"])
        code.should eq(0)
        # Reference `pretty_dependency` renders `Gem::Requirement#to_s`, which
        # normalizes a bare version to `= <version>`.
        out.should contain("json_pure (= 2.8.1) was removed.")
        File.read(File.join(dir, "Gemfile")).should_not contain("gem \"json_pure\"")
      end
    end
  end

  it "prints the bare name when the Gemfile has no requirement" do
    with_add_remove_bridge do
      add_remove_project({"Gemfile" => "source \"#{add_remove_remote}\"\n\ngem \"json_pure\"\n"}) do |dir|
        run_cli(["install"])
        code, out, err = run_cli(["remove", "json_pure"])
        code.should eq(0)
        out.should contain("json_pure was removed.")
        out.should_not contain("The Gemfile specifies no dependencies")
        err.should contain("The Gemfile specifies no dependencies")
        File.read(File.join(dir, "Gemfile")).should_not contain("gem \"json_pure\"")
      end
    end
  end
end
