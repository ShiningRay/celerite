require "./spec_helper"

# Plugin hook uninstall coverage (M7 task-9): uninstalling a plugin must drop
# its `after-install` registration from `.bundle/plugin/index` so later
# `install` runs no longer execute it, and reinstalling must restore both the
# index entry and the hook call.
#
# Reference: bundler-4.0.24 `lib/bundler/plugin/index.rb:77-87`
# (unregister_plugin deletes the plugin name from every hook event list and
# removes events left empty), `lib/bundler/plugin/index.rb:54-74`
# (register_plugin re-adds the name) and
# `lib/bundler/plugin.rb:228-240` (hooks only run for plugins recorded in the
# index). Oracle (both 4.0.24 and 2.7.2, isolated sandbox, same a-f sequence as
# `fixtures/differential/plugin-hook-uninstall`): install -> hook runs twice;
# uninstall -> index reduced to the empty skeleton; install -> hook does not
# run; reinstall -> hook runs twice again.

private def with_uninstall_hooks_bridge(&)
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

private def with_uninstall_hooks_home(dir : String, &)
  home = ENV["HOME"]?
  profile = ENV["USERPROFILE"]?
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  begin
    yield
  ensure
    if home
      ENV["HOME"] = home
    else
      ENV.delete("HOME")
    end
    if profile
      ENV["USERPROFILE"] = profile
    else
      ENV.delete("USERPROFILE")
    end
  end
end

private def with_uninstall_hooks_plugins(value : String?, &)
  previous = ENV["BUNDLE_PLUGINS"]?
  if value
    ENV["BUNDLE_PLUGINS"] = value
  else
    ENV.delete("BUNDLE_PLUGINS")
  end
  begin
    yield
  ensure
    if previous
      ENV["BUNDLE_PLUGINS"] = previous
    else
      ENV.delete("BUNDLE_PLUGINS")
    end
  end
end

private def uninstall_hooks_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  "source \"#{remote}\"\n\ngem \"json_pure\"\n"
end

# The plugin's `after-install` hook appends one line to `log.write`.
private def uninstall_hooks_plugins_rb(log : String) : String
  String.build do |io|
    io.puts %(require "bundler/plugin")
    io.puts %(require "hook_plugin")
    io.puts
    io.puts %(module HookProbe)
    io.puts %(  class ProbeCommand)
    io.puts %(    def exec(command, args))
    io.puts %(      0)
    io.puts %(    end)
    io.puts %(  end)
    io.puts %(end)
    io.puts
    io.puts %(Bundler::Plugin::API.command("hookprobe", HookProbe::ProbeCommand))
    io.puts %(Bundler::Plugin.add_hook("after-install") do |_ctx|)
    io.puts %(  File.open(#{log.inspect}, "a") { |f| f.puts "after-install" })
    io.puts %(end)
  end
end

private def uninstall_hooks_write_source(dir : String, log : String) : Nil
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "hook_plugin.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "hook_plugin"
      s.version = "0.1.0"
      s.summary = "hook uninstall probe"
      s.authors = ["Fixture"]
      s.files = ["plugins.rb", "lib/hook_plugin.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
  File.write(File.join(dir, "plugins.rb"), uninstall_hooks_plugins_rb(log))
  File.write(File.join(dir, "lib", "hook_plugin.rb"), "module HookPlugin\nend\n")
end

private def uninstall_hooks_index(dir : String) : String
  File.read(File.join(dir, ".bundle", "plugin", "index"))
end

private def uninstall_hooks_section(dir : String) : String
  uninstall_hooks_index(dir)[/^hooks:\n(.*?)^load_paths:/m, 1]? || ""
end

private def uninstall_hooks_log_lines(path : String) : Int32
  File.exists?(path) ? File.read(path).lines.size : 0
end

private def run_install_in_project(dir : String) : Tuple(Int32, String, String)
  with_uninstall_hooks_home(dir) do
    with_uninstall_hooks_plugins(nil) do
      return run_cli(["install"])
    end
  end
end

describe "M7 task-9 plugin hook uninstall" do
  it "drops the hook event from the index when the plugin is uninstalled" do
    pending! "ruby not available" unless ruby_available?
    with_uninstall_hooks_bridge do
      with_project({"Gemfile" => uninstall_hooks_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        source = File.join(dir, "hook_plugin")
        uninstall_hooks_write_source(source, log)

        run_cli(["plugin", "install", "hook_plugin", "--path", source])[0].should eq(0)
        uninstall_hooks_section(dir).should contain(%(  after-install:\n  - "hook_plugin"))

        code, out, err = run_cli(["plugin", "uninstall", "hook_plugin"])
        code.should eq(0)
        err.should be_empty
        out.should contain("Uninstalled plugin hook_plugin")
        uninstall_hooks_section(dir).should eq("")
        uninstall_hooks_index(dir).should_not contain("hookprobe")
      end
    end
  end

  it "does not run the hook on an install that follows the uninstall" do
    pending! "ruby not available" unless ruby_available?
    with_uninstall_hooks_bridge do
      with_project({"Gemfile" => uninstall_hooks_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        source = File.join(dir, "hook_plugin")
        uninstall_hooks_write_source(source, log)

        run_cli(["plugin", "install", "hook_plugin", "--path", source])[0].should eq(0)
        code, _out, err = run_install_in_project(dir)
        code.should eq(0)
        err.should_not contain("Plugin hook")
        uninstall_hooks_log_lines(log).should eq(1)

        run_cli(["plugin", "uninstall", "hook_plugin"])[0].should eq(0)
        code, out, err = run_install_in_project(dir)
        code.should eq(0)
        err.should_not contain("Plugin hook")
        out.should contain("Bundle complete!")
        uninstall_hooks_log_lines(log).should eq(1)
      end
    end
  end

  it "restores the hook after the plugin is installed again" do
    pending! "ruby not available" unless ruby_available?
    with_uninstall_hooks_bridge do
      with_project({"Gemfile" => uninstall_hooks_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        source = File.join(dir, "hook_plugin")
        uninstall_hooks_write_source(source, log)

        run_cli(["plugin", "install", "hook_plugin", "--path", source])[0].should eq(0)
        run_install_in_project(dir)[0].should eq(0)
        uninstall_hooks_log_lines(log).should eq(1)

        run_cli(["plugin", "uninstall", "hook_plugin"])[0].should eq(0)
        run_install_in_project(dir)[0].should eq(0)
        uninstall_hooks_log_lines(log).should eq(1)

        run_cli(["plugin", "install", "hook_plugin", "--path", source])[0].should eq(0)
        uninstall_hooks_section(dir).should contain(%(  after-install:\n  - "hook_plugin"))
        run_install_in_project(dir)[0].should eq(0)
        uninstall_hooks_log_lines(log).should eq(2)
      end
    end
  end

  it "lists the plugin again after reinstalling it" do
    pending! "ruby not available" unless ruby_available?
    with_uninstall_hooks_bridge do
      with_project({"Gemfile" => uninstall_hooks_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        source = File.join(dir, "hook_plugin")
        uninstall_hooks_write_source(source, log)

        run_cli(["plugin", "install", "hook_plugin", "--path", source])[0].should eq(0)
        run_cli(["plugin", "uninstall", "hook_plugin"])[0].should eq(0)
        code, out, _err = with_uninstall_hooks_home(dir) { run_cli(["plugin", "list"]) }
        code.should eq(0)
        out.should contain("No plugins installed")

        run_cli(["plugin", "install", "hook_plugin", "--path", source])[0].should eq(0)
        code, out, _err = with_uninstall_hooks_home(dir) { run_cli(["plugin", "list"]) }
        code.should eq(0)
        out.should contain("hook_plugin")
      end
    end
  end
end
