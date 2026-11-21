require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(6): Gemfile-level plugin declarations, pinned against the 4.0.24 oracle.
#   plugins=true  + `source ..., type: :t` / `plugin "x"` -> pre-install pass,
#                    missing gem => GemNotFoundError (exit 7)
#   plugins=false + `source ..., type: :t`                 -> DSL parse error (15)
#   plugins=false + `plugin "x"`                           -> ignored (exit 0)
#   unknown method: plugins=true -> PluginGemfileError (29), false -> GemfileError (4)
private def gemfile_plugins_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

private def with_gemfile_plugins_env(name : String, value : String?, &)
  previous = ENV[name]?
  if value
    ENV[name] = value
  else
    ENV.delete(name)
  end
  yield
ensure
  if previous
    ENV[name] = previous
  else
    ENV.delete(name)
  end
end

private def with_gemfile_plugins_bridge(&)
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

private def gemfile_plugins_project(remote : String, declaration : String) : Hash(String, String)
  {"Gemfile" => "source \"#{remote}\"\n\n#{declaration}\n"}
end

private def run_gemfile_plugins_install(dir : String, plugins_enabled : Bool) : {Int32, String, String}
  previous = ENV["BUNDLE_PLUGINS"]?
  previous_bundle_path = ENV["BUNDLE_PATH"]?
  # Plugin pre-install writes gems into a bundle root. Point it at this
  # project so the shared suite home is not polluted (later specs assert
  # "missing gem" behaviour against it).
  ENV["BUNDLE_PATH"] = File.join(dir, ".bundle-test")
  ENV["BUNDLE_PLUGINS"] = plugins_enabled ? "true" : "false"
  begin
    Dir.cd(dir) do
      run_cli(["install"])
    end
  ensure
    if previous
      ENV["BUNDLE_PLUGINS"] = previous
    else
      ENV.delete("BUNDLE_PLUGINS")
    end
    if previous_bundle_path
      ENV["BUNDLE_PATH"] = previous_bundle_path
    else
      ENV.delete("BUNDLE_PATH")
    end
  end
end

describe "M7(6) Gemfile-declared plugins" do
  it "pre-installs source-type plugins and fails missing gems with exit 7" do
    remote = gemfile_plugins_remote
    with_gemfile_plugins_bridge do
      with_project(gemfile_plugins_project(remote, "source \"#{remote}\", type: :psource do\n  gem \"json_pure\"\nend")) do
        code, out, err = run_gemfile_plugins_install(Dir.current, true)
        code.should eq(7)
        out.should contain("Fetching source index from #{remote}")
        err.should contain("Could not find gem 'bundler-source-psource' in rubygems repository")
        # Gemfile-declared `type:` sources go through the normal install path,
        # so the description is the plain "rubygems repository <remote> or
        # installed locally." form (source/rubygems.rb:122-136 with only
        # `@allow_local`); the "cached gems or installed locally" wording
        # belongs to `plugin install --source` (task-47) and must not be
        # asserted here. Verified against 4.0.24 on this Gemfile and index, and
        # by the passing `plugin-gemfile-missing` fixture (task-81).
        err.should contain("gem-index/ or")
        err.should contain("installed locally.")
      end
    end
  end

  it "treats a sourceless type: without a block the same way" do
    remote = gemfile_plugins_remote
    with_gemfile_plugins_bridge do
      with_project(gemfile_plugins_project(remote, "source \"#{remote}\", type: :psource")) do
        code, out, err = run_gemfile_plugins_install(Dir.current, true)
        code.should eq(7)
        out.should contain("Fetching source index from #{remote}")
        err.should contain("Could not find gem 'bundler-source-psource' in rubygems repository")
      end
    end
  end

  it "pre-installs plugin declarations and fails missing plugin gems with exit 7" do
    remote = gemfile_plugins_remote
    with_gemfile_plugins_bridge do
      with_project(gemfile_plugins_project(remote, "plugin \"psource-plugin\"\n\ngem \"json_pure\"")) do
        code, out, err = run_gemfile_plugins_install(Dir.current, true)
        code.should eq(7)
        out.should contain("Fetching source index from #{remote}")
        err.should contain("Could not find gem 'psource-plugin' in rubygems repository")
      end
    end
  end

  it "rejects source types in the main DSL when plugins are disabled (exit 15)" do
    remote = gemfile_plugins_remote
    with_gemfile_plugins_bridge do
      with_project(gemfile_plugins_project(remote, "source \"#{remote}\", type: :psource do\n  gem \"json_pure\"\nend")) do
        code, out, err = run_gemfile_plugins_install(Dir.current, false)
        code.should eq(15)
        out.should eq("")
        err.should contain("No plugin sources available for psource")
        err.should contain(">  source ")
      end
    end
  end

  it "ignores plugin declarations when plugins are disabled (exit 0)" do
    remote = gemfile_plugins_remote
    with_gemfile_plugins_bridge do
      with_project(gemfile_plugins_project(remote, "plugin \"psource-plugin\"\n\ngem \"json_pure\"")) do
        code, _out, err = run_gemfile_plugins_install(Dir.current, false)
        code.should eq(0)
        err.should_not contain("Could not find gem 'psource-plugin'")
        index = File.join(Dir.current, ".bundle", "plugin", "index")
        File.exists?(index).should be_false
      end
    end
  end

  it "rejects a gem without plugin metadata with MalformattedPlugin (exit 29)" do
    remote = gemfile_plugins_remote
    with_gemfile_plugins_bridge do
      with_project(gemfile_plugins_project(remote, "plugin \"json_pure\"\n\ngem \"json_pure\"")) do
        code, _out, err = run_gemfile_plugins_install(Dir.current, true)
        # A plugin gem must ship `plugins.rb`; json_pure does not, so reference
        # rejects it as MalformattedPlugin (29). `plugin list` stays empty.
        code.should eq(29)
        err.should contain("MalformattedPlugin")
        index = File.join(Dir.current, ".bundle", "plugin", "index")
        File.exists?(index).should be_false
      end
    end
  end

  it "maps unknown Gemfile methods to the reference status codes (29 enabled, 4 disabled)" do
    remote = gemfile_plugins_remote
    with_gemfile_plugins_bridge do
      with_project(gemfile_plugins_project(remote, "undefined_method_here \"x\"")) do
        enabled_code, _out, enabled_err = run_gemfile_plugins_install(Dir.current, true)
        enabled_code.should eq(29)
        enabled_err.should contain("Undefined")
      end
      with_project(gemfile_plugins_project(remote, "undefined_method_here \"x\"")) do
        disabled_code, _out, disabled_err = run_gemfile_plugins_install(Dir.current, false)
        disabled_code.should eq(4)
        disabled_err.should contain("Undefined")
      end
    end
  end
end
