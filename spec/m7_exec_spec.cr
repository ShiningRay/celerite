require "./spec_helper"

# `exec` spawns the child with inherited stdio, so the specs assert on marker
# files written by the child and on the parent's exit code/stderr.
private def with_exec_env(name : String, value : String?, &)
  previous = ENV[name]?
  if value.nil?
    ENV.delete(name)
  else
    ENV[name] = value
  end
  yield
ensure
  if previous.nil?
    ENV.delete(name)
  else
    ENV[name] = previous
  end
end

# `exec` needs the bridge to read the Ruby environment; `with_project` chdirs
# away from the repository, so the script path has to be absolute.
private def with_exec_bridge(&)
  with_exec_env("CELERITE_BRIDGE_SERVER", File.expand_path("../assets/bridge/server.rb", __DIR__)) do
    yield
  end
end

private def with_exec_marker(marker : String, &)
  with_exec_env("CELERITE_EXEC_MARKER", marker) do
    yield
  end
end

describe "M7(2) bundle exec" do
  it "runs the command with the bundle's RUBYOPT and BUNDLE_GEMFILE" do
    pending! "ruby is not on PATH" unless ruby_available?
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do |dir|
        marker = File.join(dir, "exec-marker.txt")
        with_exec_marker(marker) do
          code, _out, err = run_cli([
            "exec", "ruby", "-e",
            %(File.write(ENV["CELERITE_EXEC_MARKER"], ENV["RUBYOPT"].to_s + "|" + ENV["BUNDLE_GEMFILE"].to_s)),
          ])
          code.should eq(0)
          err.should eq("")
        end
        content = File.read(marker).gsub('\\', "/")
        content.should contain("bundler/setup")
        content.should contain("Gemfile")
      end
    end
  end

  it "accepts the exec-specific switches Thor declares" do
    pending! "ruby is not on PATH" unless ruby_available?
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do |dir|
        Dir.mkdir_p(File.join(dir, "nested"))
        File.write(File.join(dir, "nested", "Gemfile"), %(source "https://rubygems.org"\n))
        marker = File.join(dir, "exec-switches.txt")
        with_exec_marker(marker) do
          code, _out, _err = run_cli([
            "exec", "--keep-file-descriptors", "--gemfile", "nested/Gemfile",
            "ruby", "-e", %(File.write(ENV["CELERITE_EXEC_MARKER"], ENV["BUNDLE_GEMFILE"].to_s)),
          ])
          code.should eq(0)
        end
        File.read(marker).gsub('\\', "/").should contain("nested/Gemfile")
      end
    end
  end

  it "renders the exec manpage for --help instead of treating it as a command" do
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do
        code, out, err = run_cli(["exec", "--help"])
        code.should eq(0)
        out.should contain("bundle-exec(1) -- Execute a command in the context of the bundle")
        err.should eq("")
      end
    end
  end

  it "reports a missing command with the reference exit codes" do
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do
        code, out, err = run_cli(["exec"])
        code.should eq(128)
        out.should eq("")
        err.should eq("bundler: exec needs a command to run\n")
      end
    end
  end

  it "reports an unknown executable as command-not-found (127)" do
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do
        code, _out, err = run_cli(["exec", "celerite_no_such_command_xyz"])
        code.should eq(127)
        err.should contain("bundler: command not found: celerite_no_such_command_xyz")
        err.should contain("Install missing gem executables with `bundle install`")
      end
    end
  end

  it "treats unknown leading switches as the command to run, like the reference" do
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do
        code, _out, err = run_cli(["exec", "--bogus", "true"])
        code.should eq(127)
        err.should contain("bundler: command not found: --bogus")
      end
    end
  end
end
