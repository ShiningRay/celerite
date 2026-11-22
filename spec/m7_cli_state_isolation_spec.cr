require "./spec_helper"

# task-128 — the reference executes exactly one command per process and derives
# its UI level inside `Bundler::CLI#initialize`
# (`bundler-4.0.24/lib/bundler/cli.rb`: `Bundler.ui.level = "debug" if
# settings[:verbose]`); Thor parses the class option `--retry` on the same
# one-shot object. `run_cli` drives `Celerite::CLI.run` in-process, so every
# per-invocation switch has to be re-applied — including cleared when it was not
# requested — on each entry, instead of being written only when it is present.
private def isolation_gemfile : String
  "source \"#{file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))}\"\n\ngem \"json_pure\", \"2.8.1\"\n"
end

private def with_isolation_env(dir : String, &)
  values = {
    "BUNDLE_PATH"                      => File.join(dir, "tmp-bundle"),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
  }
  previous = {} of String => String?
  values.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
  end
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

# The debug transcript of a verbose `install` (`Commands.verbose_debug?`, driven
# by `ENV["CELERITE_VERBOSE"]`): the reason line, the bundler line and, for a
# `file://` remote, the local-server notice.
private DEBUG_LINES = [
  "Resolving dependencies because",
  "Using bundler ",
  "Using a local server",
]

describe "M7 CLI per-invocation state isolation (task-128)" do
  it "does not leak the verbose debug output of one invocation into the next" do
    ["--verbose", "-V"].each do |verbose_flag|
      with_project({"Gemfile" => isolation_gemfile}) do |dir|
        with_isolation_env(dir) do
          code, out, _err = run_cli(["install", verbose_flag])
          code.should eq(0)
          # Control: this invocation really is verbose, so the assertions below
          # are about leakage and not about an inactive debug layer.
          DEBUG_LINES.each { |line| out.should contain(line) }
        end
      end

      # An independent project: the plain `install` must start from the state of
      # *its own* invocation, not from the previous call's `--verbose`.
      with_project({"Gemfile" => isolation_gemfile}) do |dir|
        with_isolation_env(dir) do
          code, out, err = run_cli(["install"])
          code.should eq(0)
          DEBUG_LINES.each { |line| out.should_not contain(line) }
          out.should_not contain("Running `bundle")
          err.should eq("")
          ENV["CELERITE_VERBOSE"]?.should be_nil
        end
      end
    end
  end

  # `--retry` is the CLI override of the download retry budget
  # (`Commands.retry_count`). Whether the leaked value would show up as extra
  # HTTP attempts is only observable against a failing remote, so the switch is
  # asserted at the state the consumer reads.
  it "clears the CLI retry switch for the invocation that did not ask for it" do
    with_project({"Gemfile" => isolation_gemfile}) do |dir|
      with_isolation_env(dir) do
        run_cli(["install", "--retry", "7"])
        ENV["CELERITE_CLI_RETRY"]?.should eq("7")
      end

      with_isolation_env(dir) do
        run_cli(["install"])
        ENV["CELERITE_CLI_RETRY"]?.should be_nil
      end
    end
  end
end
