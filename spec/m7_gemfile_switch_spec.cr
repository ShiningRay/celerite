require "./spec_helper"

# The reference validates `--gemfile` after Thor but before the definition is
# built, so every command that declares the switch reports the same
# `GemfileNotFound` (exit 10) with `"<expanded path> not found"` on a single
# line (`definition.rb:38`), instead of leaking a Ruby `Errno::ENOENT` out of
# the bridge. A second line only appears when the reference's own word wrap
# re-breaks a line longer than the terminal width.
# Command list from `bundler/cli.rb` (`method_option "gemfile"`): init, check,
# install, update, cache, lock.
private def gemfile_switch_project : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {
    "Gemfile" => "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"json_pure\", \"2.8.1\"\n",
  }
end

# The message body stays a single line, but the *rendering* is word-wrapped at
# the terminal width (`ui/shell.rb:167-171`, migrated on the Celerite side in
# task-171). `with_project` puts the fixture under `File.tempname`, whose
# absolute path can outgrow the default 80 columns on its own, so pin the width
# from the message under test rather than hard-coding one (the lesson from
# task-137 `4ce6d51` and task-165).
private def with_columns(columns : String, &) : Nil
  previous = ENV["THOR_COLUMNS"]?
  begin
    ENV["THOR_COLUMNS"] = columns
    yield
  ensure
    if previous
      ENV["THOR_COLUMNS"] = previous
    else
      ENV.delete("THOR_COLUMNS")
    end
  end
end

# A width wide enough to keep `message` on one line, derived from the message.
private def wide_columns(message : String) : String
  (message.size + 20).to_s
end

describe "--gemfile switch" do
  it "reports a missing Gemfile for check" do
    with_project(gemfile_switch_project) do |dir|
      expected = "#{dir.gsub('\\', "/")}/missing/Gemfile not found"
      with_columns(wide_columns(expected)) do
        code, out, err = run_cli(["check", "--gemfile", "missing/Gemfile"])
        code.should eq(10)
        out.should eq("")
        err.should eq("#{expected}\n")
        err.lines.size.should eq(1)
      end
    end
  end

  it "reports a missing Gemfile for lock, update and cache" do
    with_project(gemfile_switch_project) do |dir|
      expected = "#{dir.gsub('\\', "/")}/missing/Gemfile not found"
      with_columns(wide_columns(expected)) do
        {"lock", "update", "cache"}.each do |command|
          code, out, err = run_cli([command, "--gemfile", "missing/Gemfile"])
          code.should eq(10)
          out.should eq(""), command
          err.should eq("#{expected}\n"), command
        end
      end
    end
  end

  it "accepts an existing alternate Gemfile and resolves from it" do
    index = File.expand_path("../fixtures/gem-index", __DIR__)
    files = gemfile_switch_project
    files["Alt.gemfile"] = "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"thor\", \"1.3.2\"\n"
    # `with_project` chdirs into the temporary project, so the bridge script
    # cannot be located relative to the checkout unless it is spelled out.
    server = File.expand_path("../assets/bridge/server.rb", __DIR__)
    previous = ENV["CELERITE_BRIDGE_SERVER"]?
    ENV["CELERITE_BRIDGE_SERVER"] = server
    begin
      with_project(files) do |dir|
        code, _out, err = run_cli(["lock", "--gemfile", "Alt.gemfile"])
        code.should eq(0), err
        lockfile = File.read(File.join(dir, "Alt.gemfile.lock"))
        lockfile.should contain("thor (1.3.2)")
        lockfile.should_not contain("json_pure")
      end
    ensure
      if previous
        ENV["CELERITE_BRIDGE_SERVER"] = previous
      else
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
    end
  end
end
