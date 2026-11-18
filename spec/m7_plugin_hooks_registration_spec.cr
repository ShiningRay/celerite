require "./spec_helper"

# Plugin hook registration (M7 task-5, G1): hook events declared through
# `Bundler::Plugin.add_hook` in a plugin's `plugins.rb` must reach the project
# plugin index's `hooks:` section during `plugin install`, and the recorded
# plugin must then run its hook during `install`.
#
# Reference: bundler-4.0.24 `lib/bundler/plugin.rb:215-220` (add_hook appends
# the block to `@hooks_by_event[event.to_s]`) and
# `lib/bundler/plugin/index.rb:54-74` (register_plugin copies those keys into
# `index["hooks"]`, one ordered deduped plugin list per event).

private def with_hooks_registration_bridge(&)
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

private def with_hooks_registration_home(dir : String, &)
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

private def with_hooks_registration_plugins(value : String?, &)
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

private def hooks_registration_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  "source \"#{remote}\"\n\ngem \"json_pure\"\n"
end

# A plugin source shaped like the reference: <dir>/<name>.gemspec, plugins.rb,
# lib/<name>.rb. `plugins.rb` always registers a command and, when `marker` is
# given, also declares an `after-install` hook that writes that file.
private def hooks_registration_plugins_rb(marker : String? = nil) : String
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
    if marker
      io.puts %(  File.write(#{marker.inspect}, "after-install"))
    end
    io.puts %(end)
  end
end

private def hooks_registration_write_source(dir : String, name : String, plugins_rb : String) : Nil
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "#{name}.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "0.1.0"
      s.summary = "#{name}"
      s.authors = ["Fixture"]
      s.files = ["plugins.rb", "lib/#{name}.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
  File.write(File.join(dir, "plugins.rb"), plugins_rb)
  File.write(File.join(dir, "lib", "#{name}.rb"), "module HookFixture\nend\n")
end

private def hooks_registration_index(dir : String) : String
  File.read(File.join(dir, ".bundle", "plugin", "index"))
end

describe "M7 task-5 plugin hook registration" do
  it "records hook events declared by plugins.rb in the plugin index" do
    pending! "ruby not available" unless ruby_available?
    with_hooks_registration_bridge do
      with_project({"Gemfile" => hooks_registration_gemfile}) do |dir|
        source = File.join(dir, "hook_plugin")
        hooks_registration_write_source(source, "hook_plugin", hooks_registration_plugins_rb)
        code, out, err = run_cli(["plugin", "install", "hook_plugin", "--path", source])
        code.should eq(0)
        err.should be_empty
        out.should contain("Installed plugin hook_plugin")
        index = hooks_registration_index(dir)
        index.should contain(%(  hookprobe: "hook_plugin"))
        index.should contain(%(  after-install:\n  - "hook_plugin"))
        index.should contain("load_paths:")
      end
    end
  end

  it "reads commands and hook events from plugins.rb in one probe" do
    pending! "ruby not available" unless ruby_available?
    dir = File.tempname("celerite-spec", "hook-probe")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "plugins.rb")
      File.write(path, hooks_registration_plugins_rb)
      Dir.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "hook_plugin.rb"), "module HookPlugin\nend\n")
      declared = Celerite::PluginCommands.declared(path, [File.join(dir, "lib")])
      declared[:commands].should eq(["hookprobe"])
      declared[:hooks].should eq(["after-install"])
      Celerite::PluginCommands.declared_commands(path, [File.join(dir, "lib")]).should eq(["hookprobe"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "runs a plugin's recorded after-install hook during install" do
    pending! "ruby not available" unless ruby_available?
    with_hooks_registration_bridge do
      with_project({"Gemfile" => hooks_registration_gemfile}) do |dir|
        source = File.join(dir, "hook_plugin")
        marker = File.join(dir, "hook-fired.txt")
        hooks_registration_write_source(source, "hook_plugin", hooks_registration_plugins_rb(marker))
        run_cli(["plugin", "install", "hook_plugin", "--path", source])[0].should eq(0)
        with_hooks_registration_home(dir) do
          with_hooks_registration_plugins(nil) do
            code, _out, err = run_cli(["install"])
            code.should eq(0)
            err.should_not contain("Plugin hook")
            File.read(marker).should eq("after-install")
          end
        end
      end
    end
  end

  it "leaves the hooks section empty for a plugin without hook declarations" do
    pending! "ruby not available" unless ruby_available?
    with_hooks_registration_bridge do
      with_project({"Gemfile" => hooks_registration_gemfile}) do |dir|
        source = File.join(dir, "my_plugin")
        FileUtils.cp_r(File.expand_path("../fixtures/differential/plugin-install/extra/my_plugin", __DIR__), source)
        code, _out, err = run_cli(["plugin", "install", "my_plugin", "--path", source])
        code.should eq(0)
        err.should be_empty
        index = hooks_registration_index(dir)
        hooks_section = index[/^hooks:\n(.*?)^load_paths:/m, 1]?
        hooks_section.should eq("")
      end
    end
  end
end
