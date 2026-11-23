require "./spec_helper"

# M7(6): `plugin install <name> --git <url> [--branch <b>|--ref <r>]`.
#
# The reference materializes a git plugin through
# `Bundler::Plugin::Installer::Git` on top of `Source::GitProxy#copy_to`:
# the bare mirror lands in `Plugin.cache/bundler/git/<base>-<uri_hash>`, the
# checkout in `Plugin.root/bundler/gems/<base>-<shortref_for_path(revision)>`
# (both under `<project>/.bundle/plugin`), and `Plugin::Index` then records
# those *same* paths as the plugin's `plugin_paths`/`load_paths`.
#
# These examples pin the two defects that used to break that end to end:
#
#   * the checkout was located with
#     `Dir.glob(File.join(root, "bundler", "gems", "<base>-*"))`, which on
#     Windows silently matches nothing because `File.join` yields a mixed
#     `C:/a\b\c` and `Dir.glob` reads the `\` as an escape -- so the install
#     aborted with `MalformattedPlugin (plugins.rb was not found in the
#     plugin.)` (exit 29) and left an empty `bundler/gems`;
#   * the recorded `plugin_paths` used `"<base>-<spec.version>"` instead of
#     the checkout directory name, so the index pointed at a path that does
#     not exist and the plugin's commands never registered.

private GIT_PLUGIN_GEMSPEC = <<-SPEC
  Gem::Specification.new do |s|
    s.name = "gitplugin"
    s.version = "0.1.0"
    s.summary = "git plugin probe"
    s.authors = ["Celerite"]
    s.files = ["plugins.rb", "lib/gitplugin.rb"]
    s.require_paths = ["lib"]
  end
  SPEC

private GIT_PLUGIN_PLUGINS_RB = <<-RUBY
  require "gitplugin"

  module GitPlugin
    class ProbeCommand
      def exec(_command, _args)
        0
      end
    end
  end

  Bundler::Plugin::API.command("gitprobe", GitPlugin::ProbeCommand)
  RUBY

private GIT_PLUGIN_LIB_RB = <<-RUBY
  module GitPlugin
    VERSION = "0.1.0"
  end
  RUBY

private def git_plugin_bin : String?
  candidate = File.expand_path("../bin/celerite.exe", __DIR__)
  return candidate if File.file?(candidate)

  fallback = File.expand_path("../bin/celerite", __DIR__)
  File.file?(fallback) ? fallback : nil
end

private def git_plugin_available? : Bool
  Process.run("git", ["--version"], output: IO::Memory.new, error: IO::Memory.new).success?
rescue
  false
end

private def git_plugin_git(dir : String, args : Array(String)) : String
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run("git", args, chdir: dir, output: output, error: errors)
  raise "git #{args.join(" ")} failed in #{dir}: #{errors.to_s.chomp}" unless status.success?
  output.to_s
end

# Creates the plugin stub as a real repository and returns its HEAD revision.
private def git_plugin_repo(dir : String, plugins_rb : String?) : String
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "gitplugin.gemspec"), GIT_PLUGIN_GEMSPEC)
  File.write(File.join(dir, "lib", "gitplugin.rb"), GIT_PLUGIN_LIB_RB)
  File.write(File.join(dir, "plugins.rb"), plugins_rb) if plugins_rb

  git_plugin_git(dir, ["init", "-q", "-b", "master"])
  git_plugin_git(dir, ["config", "user.email", "spec@example.test"])
  git_plugin_git(dir, ["config", "user.name", "Spec"])
  git_plugin_git(dir, ["config", "commit.gpgsign", "false"])
  git_plugin_git(dir, ["add", "-A"])
  git_plugin_git(dir, ["commit", "-q", "-m", "plugin"])
  git_plugin_git(dir, ["rev-parse", "HEAD"]).strip
end

private def with_git_plugin_env(project : String, & : ->) : Nil
  keys = {"HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH", "BUNDLE_APP_CONFIG",
          "BUNDLE_GEMFILE", "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION",
          "TMP", "TEMP", "TMPDIR"}
  saved = keys.map { |key| {key, ENV[key]?} }
  home = File.join(project, "home")
  temp = File.join(project, "tmp")
  Dir.mkdir_p(home)
  Dir.mkdir_p(temp)
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  ENV.delete("GEM_HOME")
  ENV.delete("GEM_PATH")
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(project, ".bundle")
  ENV["BUNDLE_GEMFILE"] = File.join(project, "Gemfile")
  ENV["TMP"] = temp
  ENV["TEMP"] = temp
  ENV["TMPDIR"] = temp
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  begin
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : (ENV[key] = value) }
  end
end

private def run_git_plugin(bin : String, project : String, args : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(bin, args, chdir: project, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

private def git_plugin_project_files : Hash(String, String)
  {"Gemfile" => %(source "https://rubygems.org/"\n)}
end

private def git_plugin_plugin_tree(project : String) : String
  File.join(project, ".bundle", "plugin")
end

# A git plugin install materializes its bare mirror under
# `<project>/.bundle/tmp/celerite-plugin-<pid>-<rand>/bundle/ruby/<abi>/cache/
# bundler/git/<base>-<40 hex>/objects/<2 hex>/<38 hex>`. On Windows that
# overruns MAX_PATH when the project root itself is long, and git then fails
# with `fatal: failed to unlink ... Filename too long`. The shared
# `with_project` helper puts the project under `File.tempname` (i.e. under
# `TMPDIR`, which is already deep), so these examples use a deliberately short
# root next to the repository instead. The behavior under test is unaffected;
# only the materialization path length is.
private def with_git_plugin_project(files : Hash(String, String), & : String ->) : Nil
  dir = File.join(Dir.current, ".tmp-pgs-#{Process.pid}-#{rand(1_000_000)}")
  FileUtils.rm_rf(dir)
  Dir.mkdir_p(dir)
  files.each do |name, content|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "M7(6) plugin install --git" do
  it "materializes the checkout, the cache mirror and a resolvable index" do
    bin = git_plugin_bin
    pending!("build bin/celerite.exe first") unless bin
    pending! "git is not available" unless git_plugin_available?

    with_git_plugin_project(git_plugin_project_files) do |project|
      revision = git_plugin_repo(File.join(project, "gitplugin"), GIT_PLUGIN_PLUGINS_RB)
      with_git_plugin_env(project) do
        code, output, errors = run_git_plugin(bin, project, [
          "plugin", "install", "gitplugin", "--git", "./gitplugin", "--branch", "master",
        ])
        code.should eq(0), "stderr=#{errors}\nstdout=#{output}"
        errors.should_not contain("MalformattedPlugin")
        output.should contain("Fetching ./gitplugin")
        output.should contain("Installed plugin gitplugin")

        plugin_root = git_plugin_plugin_tree(project)
        checkout = File.join(plugin_root, "bundler", "gems", "gitplugin-#{revision[0, 12]}")

        # The checkout is the one `GitSource` produced, and it is a real git
        # checkout (shallow, fetched and reset) rather than a bare copy.
        File.file?(File.join(checkout, "plugins.rb")).should be_true
        File.file?(File.join(checkout, "lib", "gitplugin.rb")).should be_true
        File.file?(File.join(checkout, ".git", "shallow")).should be_true
        File.read(File.join(checkout, ".git", "shallow")).strip.should eq(revision)

        # No `bundler/gems/gitplugin-0.1.0` (the version-named path the index
        # used to point at) may be left behind.
        Dir.exists?(File.join(plugin_root, "bundler", "gems", "gitplugin-0.1.0")).should be_false
        entries = Dir.children(File.join(plugin_root, "bundler", "gems")).sort
        entries.should eq(["gitplugin-#{revision[0, 12]}"])

        # The bare mirror is copied next to the checkout, like
        # `Plugin::Installer::Git#cache_path`.
        cache_entries = Dir.children(File.join(plugin_root, "cache", "bundler", "git"))
        cache_entries.size.should eq(1)
        mirror = File.join(plugin_root, "cache", "bundler", "git", cache_entries.first)
        File.file?(File.join(mirror, "HEAD")).should be_true

        # The index must name the materialized paths, not a version-suffixed
        # directory, or `plugin list`/command dispatch cannot find anything.
        index = YAML.parse(File.read(File.join(plugin_root, "index")))
        index["commands"]["gitprobe"].as_s.should eq("gitplugin")
        plugin_path = index["plugin_paths"]["gitplugin"].as_s.gsub('\\', "/")
        plugin_path.should eq(checkout.gsub('\\', "/"))
        index["load_paths"]["gitplugin"][0].as_s.gsub('\\', "/").should eq("#{checkout.gsub('\\', "/")}/lib")
      end
    end
  end

  it "lists and dispatches the command the plugin registered" do
    bin = git_plugin_bin
    pending!("build bin/celerite.exe first") unless bin
    pending! "git is not available" unless git_plugin_available?

    with_git_plugin_project(git_plugin_project_files) do |project|
      git_plugin_repo(File.join(project, "gitplugin"), GIT_PLUGIN_PLUGINS_RB)
      with_git_plugin_env(project) do
        run_git_plugin(bin, project, [
          "plugin", "install", "gitplugin", "--git", "./gitplugin", "--branch", "master",
        ])[0].should eq(0)

        code, output, errors = run_git_plugin(bin, project, ["plugin", "list"])
        code.should eq(0)
        errors.should be_empty
        output.should eq("gitplugin\n-----\n  gitprobe\n\n")

        # `Bundler::Plugin::API.command` registration must be dispatchable.
        code, _output, errors = run_git_plugin(bin, project, ["gitprobe"])
        code.should eq(0)
        errors.should_not contain("Could not find command")
      end
    end
  end

  it "accepts --ref as well as --branch" do
    bin = git_plugin_bin
    pending!("build bin/celerite.exe first") unless bin
    pending! "git is not available" unless git_plugin_available?

    with_git_plugin_project(git_plugin_project_files) do |project|
      revision = git_plugin_repo(File.join(project, "gitplugin"), GIT_PLUGIN_PLUGINS_RB)
      with_git_plugin_env(project) do
        code, output, errors = run_git_plugin(bin, project, [
          "plugin", "install", "gitplugin", "--git", "./gitplugin", "--ref", revision,
        ])
        code.should eq(0), "stderr=#{errors}\nstdout=#{output}"
        errors.should_not contain("MalformattedPlugin")
        output.should contain("Installed plugin gitplugin")

        checkout = File.join(git_plugin_plugin_tree(project), "bundler", "gems", "gitplugin-#{revision[0, 12]}")
        File.file?(File.join(checkout, "plugins.rb")).should be_true
      end
    end
  end

  it "reports MalformattedPlugin (exit 29) when the checkout has no plugins.rb" do
    bin = git_plugin_bin
    pending!("build bin/celerite.exe first") unless bin
    pending! "git is not available" unless git_plugin_available?

    with_git_plugin_project(git_plugin_project_files) do |project|
      git_plugin_repo(File.join(project, "gitplugin"), nil)
      with_git_plugin_env(project) do
        code, output, errors = run_git_plugin(bin, project, [
          "plugin", "install", "gitplugin", "--git", "./gitplugin", "--branch", "master",
        ])
        code.should eq(29), "stderr=#{errors}\nstdout=#{output}"
        output.should contain("Fetching ./gitplugin")
        errors.should contain("Failed to install plugin `gitplugin`")
        errors.should contain("Bundler::Plugin::MalformattedPlugin")
        errors.should contain("plugins.rb was not found in the plugin.")

        # A failed install must not leave a broken plugin behind.
        index = File.join(git_plugin_plugin_tree(project), "index")
        File.exists?(index).should be_false
      end
    end
  end
end
