require "./spec_helper"
require "../src/celerite"

# Reference `bundler-4.0.24/lib/bundler/cli.rb:777-791` (`print_command`): with
# `--verbose` the invocation is echoed before the command runs, re-rendering the
# switches through `Thor::Options.to_switches` (booleans bare, strings inspected,
# array options bracketed) and sorting them by option name. `PARSEABLE_COMMANDS`
# (`cli.rb:13`) never echo.
#
# Expected lines below were captured from the reference oracle; each case is
# byte-identical to `bundle <args>` output at bundler 4.0.24.
private def verbose_echo(args : Array(String)) : String
  io = IO::Memory.new
  verbose = args.includes?("--verbose")
  retry_value = Celerite::Commands.extract_retry_switch(args)
  stripped = Celerite::Commands.strip_global_flags(args)
  return "" if stripped.empty?
  Celerite::Commands.print_command_echo(stripped[0], stripped[1..], verbose, retry_value, io)
  io.to_s
end

private def with_bundler_profile(version : String, & : ->) : Nil
  previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = version
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous
    else
      ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    end
  end
end

private def verbose_echo_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  %(source "#{remote}"\ngem "json_pure", "2.8.1"\n)
end

describe "verbose command echo" do
  it "echoes a bare --verbose install" do
    verbose_echo(["install", "--verbose"])
      .should eq("Running `bundle install --verbose` with bundler 4.0.24\n")
  end

  it "renders numeric switches unquoted and sorts by option name" do
    verbose_echo(["install", "--verbose", "--retry", "5"])
      .should eq("Running `bundle install --retry 5 --verbose` with bundler 4.0.24\n")
    verbose_echo(["install", "--verbose", "--jobs", "2", "--no-color"])
      .should eq("Running `bundle install --jobs 2 --no-color --verbose` with bundler 4.0.24\n")
  end

  it "renders string switches through Ruby inspect" do
    verbose_echo(["add", "json_pure", "--verbose", "--version", "2.8.1"])
      .should eq(%(Running `bundle add json_pure --verbose --version "2.8.1"` with bundler 4.0.24\n))
    verbose_echo(["add", "json_pure", "--verbose", "--group", "dev"])
      .should eq(%(Running `bundle add json_pure --group "dev" --verbose` with bundler 4.0.24\n))
    verbose_echo(["install", "--verbose", "--without", "development"])
      .should eq(%(Running `bundle install --verbose --without "development"` with bundler 4.0.24\n))
  end

  it "renders array switches as inspect lists, or `true` when bare" do
    verbose_echo(["lock", "--verbose", "--update"])
      .should eq("Running `bundle lock --update true --verbose` with bundler 4.0.24\n")
    verbose_echo(["lock", "--verbose", "--update", "json_pure"])
      .should eq(%(Running `bundle lock --update ["json_pure"] --verbose` with bundler 4.0.24\n))
    verbose_echo(["lock", "--verbose", "--update", "json_pure", "thor"])
      .should eq(%(Running `bundle lock --update ["json_pure", "thor"] --verbose` with bundler 4.0.24\n))
  end

  it "echoes the configured bundler profile" do
    with_bundler_profile("2.7.2") do
      verbose_echo(["install", "--verbose"])
        .should eq("Running `bundle install --verbose` with bundler 2.7.2\n")
    end
  end

  it "never echoes parseable commands" do
    verbose_echo(["check", "--verbose"]).should eq("")
    verbose_echo(["show", "--verbose"]).should eq("")
    verbose_echo(["version", "--verbose"]).should eq("")
  end

  it "never echoes without --verbose" do
    verbose_echo(["install", "--jobs", "2"]).should eq("")
  end

  it "echoes before the removed-flag error" do
    with_project({"Gemfile" => verbose_echo_gemfile}) do
      code, out, err = run_cli(["install", "--verbose", "--frozen"])
      code.should eq(15)
      out.lines.first.should eq("Running `bundle install --frozen --verbose` with bundler 4.0.24")
      err.should contain("The `--frozen` flag has been removed")
    end
  end
end
