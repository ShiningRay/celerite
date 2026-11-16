require "./spec_helper"

# The reference validates `--gemfile` after Thor but before the definition is
# built, so every command that declares the switch reports the same
# `GemfileNotFound` (exit 10) with the expanded path and `not found` on its own
# line, instead of leaking a Ruby `Errno::ENOENT` out of the bridge.
# Command list from `bundler/cli.rb` (`method_option "gemfile"`): init, check,
# install, update, cache, lock.
private def gemfile_switch_project : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {
    "Gemfile" => "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"json_pure\", \"2.8.1\"\n",
  }
end

describe "--gemfile switch" do
  it "reports a missing Gemfile for check" do
    with_project(gemfile_switch_project) do |dir|
      code, out, err = run_cli(["check", "--gemfile", "missing/Gemfile"])
      code.should eq(10)
      out.should eq("")
      err.should eq("#{dir.gsub('\\', "/")}/missing/Gemfile\nnot found\n")
    end
  end

  it "reports a missing Gemfile for lock, update and cache" do
    with_project(gemfile_switch_project) do |dir|
      expected = "#{dir.gsub('\\', "/")}/missing/Gemfile\nnot found\n"
      {"lock", "update", "cache"}.each do |command|
        code, out, err = run_cli([command, "--gemfile", "missing/Gemfile"])
        code.should eq(10)
        out.should eq("")
        err.should eq(expected)
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
