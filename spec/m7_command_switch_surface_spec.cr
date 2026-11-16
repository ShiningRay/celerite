require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(2): every command surface rejects unknown switches before running, the
# way Thor does for `Bundler::CLI.commands[name].options`
# (lib/bundler/cli.rb) — measured on 4.0.24:
#
#   bundle licenses --format=csv   => Unknown switches "--format=csv"  (15)
#   bundle outdated --bogus        => Unknown switches + Did you mean?  (15)
#   bundle doctor --bogus          => ERROR: "bundle doctor diagnose" ...  (15)
#   bundle licenses --no-color     => global class options stay accepted
#
# The read-only commands (`licenses`, `outdated`) also resolve the bundle
# locally like `fund`/`clean`/`binstubs`, while `doctor` fetches the index the
# way `check` does.
private def switch_surface_gemfile : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {"Gemfile" => %(source "#{file_source_url(index)}"\n\ngem "json_pure", "2.8.1"\n)}
end

private def with_switch_surface_env(dir : String, & : ->)
  names = %w[HOME USERPROFILE GEM_HOME GEM_PATH BUNDLE_PATH CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB]
  previous = {} of String => String?
  names.each { |name| previous[name] = ENV[name]? }
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["GEM_HOME"] = File.join(dir, "gems")
  ENV["GEM_PATH"] = File.join(dir, "gems")
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    previous.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def run_switch_surface(command : String, rest : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  err = IO::Memory.new
  code = case command
         when "licenses" then Celerite::Commands.licenses(output, err, rest)
         when "outdated" then Celerite::Commands.outdated(output, err, rest)
         when "doctor"   then Celerite::Commands.doctor(output, err, rest)
         when "fund"     then Celerite::Commands.fund(output, err, rest)
         when "env"      then Celerite::Commands.env(output, err, rest)
         when "gem"      then Celerite::Commands.gem(output, err, rest)
         else                 raise "unsupported command #{command}"
         end
  {code, output.to_s, err.to_s}
end

describe "M7(2) command switch surfaces" do
  it "rejects unknown switches on licenses with the reference message" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        code, output, err = run_switch_surface("licenses", ["--format=csv"])
        code.should eq(15)
        output.should be_empty
        err.should eq(%(Unknown switches "--format=csv"\n))
      end
    end
  end

  it "keeps Thor class options accepted" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        # The sandbox has no installed json_pure, so the local resolution fails
        # after the options parse — the point is that it is not a switch error.
        error = expect_raises(Celerite::GemNotFoundError) do
          run_switch_surface("licenses", ["--no-color", "--retry", "3"])
        end
        error.message.should eq("Could not find gem 'json_pure (= 2.8.1)' in locally installed gems.")
      end
    end
  end

  it "suggests the closest switch for outdated" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        code, _output, err = run_switch_surface("outdated", ["--bogus"])
        code.should eq(15)
        err.should contain(%(Unknown switches "--bogus"))
        err.should contain(%(Did you mean?  "--groups"))
      end
    end
  end

  it "reports unknown doctor options as leftover diagnose arguments" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        code, output, err = run_switch_surface("doctor", ["--bogus"])
        code.should eq(15)
        output.should be_empty
        err.should eq(%(ERROR: "bundle doctor diagnose" was called with arguments ["--bogus"]\n) +
                      %(Usage: "bundle doctor diagnose [OPTIONS]"\n))
      end
    end
  end

  it "rejects unknown switches on fund and env too" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        code, _output, err = run_switch_surface("fund", ["--bogus"])
        code.should eq(15)
        err.should eq(%(Unknown switches "--bogus"\n))

        code, _output, err = run_switch_surface("env", ["--bogus"])
        code.should eq(15)
        err.should eq(%(Unknown switches "--bogus"\n))
      end
    end
  end

  it "rejects unknown switches on gem before the positional check" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        code, _output, err = run_switch_surface("gem", ["--bogus"])
        code.should eq(15)
        err.should eq(%(Unknown switches "--bogus"\n))
      end
    end
  end

  it "reports the missing local gem for outdated without a lockfile" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        error = expect_raises(Celerite::GemNotFoundError) do
          run_switch_surface("outdated", ["--parseable"])
        end
        error.message.should eq("Could not find gem 'json_pure (= 2.8.1)' in locally installed gems.")
      end
    end
  end

  it "checks the bundle remotely for doctor without a lockfile" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        code, output, err = run_switch_surface("doctor", [] of String)
        code.should eq(1)
        output.should contain("Resolving dependencies...")
        err.should contain("The following gems are missing")
        err.should contain(" * json_pure (2.8.1)")
        err.should contain("Install missing gems with `bundle install`")
      end
    end
  end

  it "skips resolution when the requested group has no dependencies" do
    next unless ruby_available?
    with_project(switch_surface_gemfile) do |dir|
      with_switch_surface_env(dir) do
        code, output, err = run_switch_surface("fund", ["--group", "development"])
        code.should eq(0)
        output.should eq("None of the installed gems you directly depend on are looking for funding.\n")
        output.should_not contain("Fetching source index")
        err.should be_empty
      end
    end
  end
end
