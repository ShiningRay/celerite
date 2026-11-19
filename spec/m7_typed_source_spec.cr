require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(6) task-24: a Gemfile that declares only `source ..., type: :t` has no
# primary remote. The reference evaluates that Gemfile through
# `Bundler::Plugin::DSL`, infers `bundler-source-t`, and installs it with an
# empty source list (`bundler/plugin/installer.rb:91-101`), so a plugin that is
# not installed locally raises GemNotFoundError (exit 7) before the main
# Gemfile is resolved. Measured oracle (4.0.24 and 2.7.2):
#   stdout: empty
#   stderr: Could not find gem 'bundler-source-foo' in locally installed gems.
private def with_typed_source_bridge(&)
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

private def run_typed_source_install(dir : String) : {Int32, String, String}
  previous_path = ENV["BUNDLE_PATH"]?
  previous_plugins = ENV["BUNDLE_PLUGINS"]?
  ENV["BUNDLE_PATH"] = File.join(dir, ".bundle-test")
  ENV["BUNDLE_PLUGINS"] = "true"
  begin
    Dir.cd(dir) { run_cli(["install"]) }
  ensure
    if previous_path
      ENV["BUNDLE_PATH"] = previous_path
    else
      ENV.delete("BUNDLE_PATH")
    end
    if previous_plugins
      ENV["BUNDLE_PLUGINS"] = previous_plugins
    else
      ENV.delete("BUNDLE_PLUGINS")
    end
  end
end

private def typed_only_gemfile(declaration : String) : Hash(String, String)
  {"Gemfile" => "source \"https://example.com/\", type: :foo#{declaration}\n"}
end

describe "M7(6) task-24 typed-source-only install" do
  it "fails the inferred source plugin locally with the reference message and exit 7" do
    with_typed_source_bridge do
      with_project(typed_only_gemfile("")) do
        code, out, err = run_typed_source_install(Dir.current)
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'bundler-source-foo' in locally installed gems.\n")
      end
    end
  end

  it "does not fall back to rubygems.org when the typed source has a block" do
    with_typed_source_bridge do
      with_project(typed_only_gemfile(" do\n  gem \"json_pure\"\nend")) do
        code, out, err = run_typed_source_install(Dir.current)
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'bundler-source-foo' in locally installed gems.\n")
        err.should_not contain("rubygems.org")
        err.should_not contain("SSL")
      end
    end
  end
end
