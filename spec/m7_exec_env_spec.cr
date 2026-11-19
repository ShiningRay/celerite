require "./spec_helper"

# `exec` inherits stdio, so these specs assert through a marker file written by
# the child and through the parent's exit code/stderr. The helper names mirror
# `m7_exec_spec.cr` (which keeps them private to that file).
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

# Writes the child's RUBYOPT into CELERITE_EXEC_MARKER.
private def exec_env_probe : String
  %(File.write(ENV["CELERITE_EXEC_MARKER"], ENV["RUBYOPT"].to_s))
end

private def setup_entry_count(content : String) : Int32
  content.gsub('\\', "/").split(" ").count { |arg| arg.ends_with?("/bundler/setup") }
end

describe "M7(2) bundle exec environment" do
  it "injects exactly one bundler/setup require" do
    pending! "ruby is not on PATH" unless ruby_available?
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do |dir|
        marker = File.join(dir, "exec-env.txt")
        with_exec_marker(marker) do
          code, _out, err = run_cli(["exec", "ruby", "-e", exec_env_probe])
          code.should eq(0)
          err.should eq("")
        end
        # A backslash `-r` path would make the child's own bundler/setup append
        # a second, equivalent entry (task-48 S1).
        setup_entry_count(File.read(marker)).should eq(1)
      end
    end
  end

  it "keeps unrelated RUBYOPT entries alongside the canonical setup require" do
    pending! "ruby is not on PATH" unless ruby_available?
    with_exec_bridge do
      with_project({"Gemfile" => %(source "https://rubygems.org"\n)}) do |dir|
        marker = File.join(dir, "exec-env.txt")
        with_exec_env("RUBYOPT", "-rjson") do
          with_exec_marker(marker) do
            code, _out, _err = run_cli(["exec", "ruby", "-e", exec_env_probe])
            code.should eq(0)
          end
        end
        content = File.read(marker)
        content.gsub('\\', "/").split(" ").should contain("-rjson")
        setup_entry_count(content).should eq(1)
      end
    end
  end

  it "lets the child fail before running when the explicit Gemfile is missing" do
    pending! "ruby is not on PATH" unless ruby_available?
    with_exec_bridge do
      with_project({} of String => String) do |dir|
        marker = File.join(dir, "ran.txt")
        code, _out, _err = run_cli([
          "exec", "--gemfile", "missing.rb", "ruby", "-e",
          %(File.write(#{marker.inspect}, "ran")),
        ])
        # The child dies in `-rbundler/setup` (Bundler::GemfileNotFound); the
        # companion differential fixture asserts the message shape, which is
        # inherited stdio and therefore not capturable here.
        code.should eq(1)
        File.exists?(marker).should be_false
      end
    end
  end
end
