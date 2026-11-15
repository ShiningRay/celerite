require "./spec_helper"
require "json"

private GEM_INDEX_URL = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def list_format_gemfile(empty : Bool = false) : String
  if empty
    "source \"#{GEM_INDEX_URL}\"\n"
  else
    <<-GEMFILE
    source "#{GEM_INDEX_URL}"

    gem "json_pure"

    group :development do
      gem "thor"
    end
    GEMFILE
  end
end

private def with_list_format_env(project : String, &)
  previous = {
    "HOME"        => ENV["HOME"]?,
    "USERPROFILE" => ENV["USERPROFILE"]?,
    "BUNDLE_PATH" => ENV["BUNDLE_PATH"]?,
  }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, ".bundle-test")
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

private def with_list_format_bridge(&)
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

private def list_format_json(output : String) : JSON::Any
  JSON.parse(output)
end

private def run_list_format(project : String, args : Array(String)) : {Int32, String, String}
  with_list_format_env(project) do
    status, output, errors = run_cli(args)
    {status, output, errors}
  end
end

describe "bundle list output formats" do
  it "emits the reference JSON payload with a null git_version" do
    with_project({"Gemfile" => list_format_gemfile}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["install"])
        status, output, errors = run_list_format(project, ["list", "--format=json"])
        status.should eq(0)
        errors.should eq("")
        gems = list_format_json(output)["gems"].as_a
        gems.map(&.["name"].as_s).should eq(["json_pure", "thor"])
        gems.first.as_h.keys.should eq(["name", "version", "git_version"])
        gems.first["git_version"].raw.should be_nil
      end
    end
  end

  it "drops version fields under --name-only" do
    with_project({"Gemfile" => list_format_gemfile}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["install"])
        status, output, _ = run_list_format(project, ["list", "--format=json", "--name-only"])
        status.should eq(0)
        gems = list_format_json(output)["gems"].as_a
        gems.first.as_h.keys.should eq(["name"])
      end
    end
  end

  it "adds forward-slash paths under --paths" do
    with_project({"Gemfile" => list_format_gemfile}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["install"])
        status, output, _ = run_list_format(project, ["list", "--format=json", "--paths"])
        status.should eq(0)
        gem = list_format_json(output)["gems"].as_a.first
        gem.as_h.keys.should eq(["name", "version", "git_version", "path"])
        path = gem["path"].as_s
        path.should contain("/")
        path.should_not contain("\\")
        path.should end_with("json_pure-2.8.1")
      end
    end
  end

  it "accepts the two-token --format json form" do
    with_project({"Gemfile" => list_format_gemfile}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["install"])
        token_status, token_output, _ = run_list_format(project, ["list", "--format", "json"])
        equals_status, equals_output, _ = run_list_format(project, ["list", "--format=json"])
        token_status.should eq(0)
        equals_status.should eq(0)
        token_output.should eq(equals_output)
      end
    end
  end

  it "rejects --name-only with --paths before loading specs" do
    with_project({"Gemfile" => list_format_gemfile}) do |project|
      with_list_format_bridge do
        status, output, errors = run_list_format(project, ["list", "--name-only", "--paths"])
        status.should eq(15)
        output.should eq("")
        errors.strip.should eq("The `--name-only` and `--paths` options cannot be used together")
      end
    end
  end

  it "rejects an unsupported --format value" do
    with_project({"Gemfile" => list_format_gemfile}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["install"])
        status, output, errors = run_list_format(project, ["list", "--format=bogus"])
        status.should eq(15)
        output.should eq("")
        errors.strip.should eq("Unknown option`--format=bogus`. Supported formats: `json`")
      end
    end
  end

  it "prefers the missing-gem exit over an invalid format" do
    thor_only = <<-GEMFILE
    source "#{GEM_INDEX_URL}"

    gem "thor"
    GEMFILE
    with_project({"Gemfile" => thor_only}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["lock"])
        status, _output, errors = run_list_format(project, ["list", "--format=bogus"])
        status.should eq(1)
        errors.should contain("Could not find thor-1.3.2 in locally installed gems")
      end
    end
  end

  it "prints an empty JSON payload for an empty bundle" do
    with_project({"Gemfile" => list_format_gemfile(empty: true)}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["lock"])
        status, output, errors = run_list_format(project, ["list", "--format=json"])
        status.should eq(0)
        errors.should eq("")
        output.strip.should eq(%({"gems":[]}))
      end
    end
  end

  it "validates the format even for an empty bundle" do
    with_project({"Gemfile" => list_format_gemfile(empty: true)}) do |project|
      with_list_format_bridge do
        run_list_format(project, ["lock"])
        status, _output, errors = run_list_format(project, ["list", "--format=bogus"])
        status.should eq(15)
        errors.strip.should eq("Unknown option`--format=bogus`. Supported formats: `json`")
      end
    end
  end
end
