require "./spec_helper"
require "../src/celerite"

# M7(1): the Gemfile `ruby` declaration is a runtime constraint, not just a
# lockfile annotation. Reference `Definition#validate_runtime!`
# (`bundler/definition.rb:494-523`) is called by check/show/info/install/
# platform/fund/update/outdated/pristine/binstubs, and it must run outside the
# differential harness too. A fresh lockfile serializes the *running* Ruby
# (`Bundler::RubyVersion.system`), never the Gemfile requirement string.
private def with_bridge_script(& : ->) : Nil
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

private def mismatched_ruby_gemfile : String
  "source \"https://rubygems.org\"\n\nruby \"9.9.9\"\n\ngem \"json_pure\"\n"
end

describe "M7 ruby runtime enforcement" do
  it "fails check when the Gemfile ruby requirement does not match the runtime" do
    pending! "ruby not available" unless ruby_available?
    with_bridge_script do
      with_project({"Gemfile" => mismatched_ruby_gemfile}) do
        ex = expect_raises(Celerite::RubyVersionMismatch) do
          Celerite::Commands.check(IO::Memory.new, IO::Memory.new, [] of String)
        end
        ex.message.should match(/Your Ruby version is \d+\.\d+\.\d+, but your Gemfile specified 9\.9\.9/)
        ex.status_code.should eq(18)
      end
    end
  end

  it "fails show when the Gemfile ruby requirement does not match the runtime" do
    pending! "ruby not available" unless ruby_available?
    with_bridge_script do
      with_project({"Gemfile" => mismatched_ruby_gemfile}) do
        ex = expect_raises(Celerite::RubyVersionMismatch) do
          Celerite::Commands.show_info("show", IO::Memory.new, IO::Memory.new, [] of String)
        end
        ex.status_code.should eq(18)
      end
    end
  end

  # Reference `cli/binstubs.rb:12` validates the runtime before the argument
  # checks, so the mismatch wins over "Please pass a gem name".
  it "fails binstubs on the runtime before reporting a missing gem name" do
    pending! "ruby not available" unless ruby_available?
    with_bridge_script do
      with_project({"Gemfile" => mismatched_ruby_gemfile}) do
        stderr = IO::Memory.new
        ex = expect_raises(Celerite::RubyVersionMismatch) do
          Celerite::Commands.binstubs(IO::Memory.new, stderr, [] of String)
        end
        ex.status_code.should eq(18)
        stderr.to_s.should eq("")
      end
    end
  end

  it "serializes the running Ruby instead of the Gemfile requirement" do
    pending! "ruby not available" unless ruby_available?
    remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
    with_project({"Gemfile" => %(source "#{remote}"\n\nruby ">= 3.1"\n\ngem "json_pure", "2.8.1"\n)}) do
      with_client do |client|
        resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
        resolution.progress = IO::Memory.new
        lock = resolution.generated_lockfile.to_lock
        system_version = client.ruby_environment.ruby_version
        lock.should contain("RUBY VERSION\n  ruby #{system_version}\n")
        lock.should_not contain("ruby >= 3.1")
      end
    end
  end
end
