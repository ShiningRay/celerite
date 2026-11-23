require "./spec_helper"

# C-M7-6-037: with no Gemfile anywhere above the working directory the plugin
# root is the *global* one (reference `lib/bundler/plugin.rb:136-152`:
# `SharedHelpers.in_bundle? ? local_root : global_root`, `global_root =
# Bundler.user_bundle_path("plugin")` = `~/.bundle/plugin`). This spec pins the
# write side of that branch: `plugin install <dir> --path <rel>` from a
# Gemfile-less cwd must record the plugin *and its `add_hook` registrations* in
# `<HOME>/.bundle/plugin/index`, keep the project byte-clean, and expose the
# plugin's command only through that global index.
#
# `spec/m7_plugin_install_source_spec.cr` covers the same branch for
# `--source`, but with `HOME` set to the project directory itself, so the
# project root and the global root are the same tree and the two cannot be told
# apart. Here HOME is a sibling of the project.

private def global_hook_bin : String?
  candidate = File.expand_path("../bin/celerite.exe", __DIR__)
  return candidate if File.file?(candidate)

  fallback = File.expand_path("../bin/celerite", __DIR__)
  File.file?(fallback) ? fallback : nil
end

private def global_hook_plugins_rb : String
  [
    %(require "bundler/plugin/api"),
    "",
    "module GlobalHookPlugin",
    "  class ProbeCommand",
    "    def exec(_command, _args)",
    "      0",
    "    end",
    "  end",
    "end",
    "",
    %(Bundler::Plugin::API.command("grootprobe", GlobalHookPlugin::ProbeCommand)),
    %(Bundler::Plugin.add_hook("after-install") { |_ctx| }),
    "",
  ].join("\n")
end

private def global_hook_gemspec : String
  [
    "Gem::Specification.new do |s|",
    %(  s.name = "hook_plugin"),
    %(  s.version = "0.1.0"),
    %(  s.summary = "global plugin root hook probe"),
    %(  s.authors = ["Fixture"]),
    %(  s.files = ["plugins.rb", "lib/hook_plugin.rb"]),
    %(  s.require_paths = ["lib"]),
    "end",
    "",
  ].join("\n")
end

private def write_global_hook_stub(project : String) : String
  dir = File.join(project, "hook_plugin")
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "plugins.rb"), global_hook_plugins_rb)
  File.write(File.join(dir, "hook_plugin.gemspec"), global_hook_gemspec)
  File.write(File.join(dir, "lib", "hook_plugin.rb"), "module GlobalHookPlugin\nend\n")
  dir
end

# The global branch only applies where the upward search in
# `Definition.find_gemfile` finds neither Gemfile nor gems.rb.
private def gemfile_ancestor(from : String) : String?
  dir = File.expand_path(from)
  loop do
    gemfile = File.join(dir, "Gemfile")
    return gemfile if File.exists?(gemfile)
    parent = File.dirname(dir)
    break if parent == dir
    dir = parent
  end
  nil
end

private def with_global_hook_env(home : String, project : String, tmp : String, &)
  names = ["HOME", "USERPROFILE", "BUNDLE_PATH", "GEM_HOME", "GEM_PATH", "TEMP", "TMP", "TMPDIR"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["GEM_HOME"] = File.join(project, "gems")
  ENV["GEM_PATH"] = ENV["GEM_HOME"]
  ENV["TEMP"] = tmp
  ENV["TMP"] = tmp
  ENV["TMPDIR"] = tmp
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

private def run_global_hook(bin : String, cwd : String, args : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(bin, args, chdir: cwd, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

private def with_global_hook_probe(&)
  root = File.tempname("celerite-spec", "plugin-global")
  home = File.join(root, "home")
  project = File.join(root, "project")
  tmp = File.join(root, "tmp")
  [home, project, tmp].each { |dir| Dir.mkdir_p(dir) }
  begin
    yield root, home, project, tmp
  ensure
    FileUtils.rm_rf(root)
  end
end

describe "M7(6) plugin hooks in the global plugin root" do
  it "records hooks in the global index when the project has no Gemfile" do
    bin = global_hook_bin
    pending!("build bin/celerite.exe first") unless bin

    with_global_hook_probe do |_root, home, project, tmp|
      stub = write_global_hook_stub(project)
      gemfile_ancestor(project).should be_nil

      with_global_hook_env(home, project, tmp) do
        code, output, errors = run_global_hook(bin, project, [
          "plugin", "install", "hook_plugin", "--path", "./hook_plugin",
        ])
        errors.should_not contain("GemfileNotFound")
        code.should eq(0)
        output.should contain("Installed plugin hook_plugin")

        index_path = File.join(home, ".bundle", "plugin", "index")
        File.file?(index_path).should be_true
        index = YAML.parse(File.read(index_path))
        index["commands"]["grootprobe"].as_s.should eq("hook_plugin")
        index["hooks"]["after-install"].as_a.map(&.as_s).should eq(["hook_plugin"])
        index["plugin_paths"]["hook_plugin"].as_s.gsub('\\', "/").should eq(stub.gsub('\\', "/"))
        index["load_paths"]["hook_plugin"][0].as_s.gsub('\\', "/").should end_with("/hook_plugin/lib")

        File.read(index_path).should contain("hooks:\n  after-install:\n  - \"hook_plugin\"\n")

        # The project keeps no plugin tree of its own: everything above lives
        # under the global root.
        File.exists?(File.join(project, ".bundle")).should be_false

        code, output, _errors = run_global_hook(bin, project, ["plugin", "list"])
        code.should eq(0)
        output.should eq("hook_plugin\n-----\n  grootprobe\n\n")

        code, _output, _errors = run_global_hook(bin, project, ["grootprobe"])
        code.should eq(0)
      end
    end
  end

  it "finds the installed command through the global root only" do
    bin = global_hook_bin
    pending!("build bin/celerite.exe first") unless bin

    with_global_hook_probe do |root, home, project, tmp|
      write_global_hook_stub(project)
      empty_home = File.join(root, "empty-home")
      Dir.mkdir_p(empty_home)

      with_global_hook_env(home, project, tmp) do
        run_global_hook(bin, project, ["plugin", "install", "hook_plugin", "--path", "./hook_plugin"])[0].should eq(0)
      end

      # Same working directory, different HOME: the project has no `.bundle`,
      # so nothing is discoverable and the command must be unknown.
      with_global_hook_env(empty_home, project, tmp) do
        code, output, _errors = run_global_hook(bin, project, ["plugin", "list"])
        code.should eq(0)
        output.should eq("No plugins installed\n")

        code, _output, errors = run_global_hook(bin, project, ["grootprobe"])
        code.should eq(15)
        errors.should contain("Could not find command \"grootprobe\".")
      end
    end
  end
end
