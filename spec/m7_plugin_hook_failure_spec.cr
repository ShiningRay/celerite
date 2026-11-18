require "./spec_helper"
require "../src/celerite"

# Reference failure semantics for plugin hooks (bundler-4.0.24 plugin.rb
# L228-240 hook / L345-381 load_plugin), exercised through `install`.
private def plugin_hook_index(dir : String, name : String, plugin_root : String,
                              hooks : String = name) : Nil
  index_dir = File.join(dir, ".bundle", "plugin")
  Dir.mkdir_p(index_dir)
  lib_dir = File.join(plugin_root, "lib").gsub(/\\/, "/")
  root_dir = plugin_root.gsub(/\\/, "/")
  File.write(File.join(index_dir, "index"), <<-YAML)
  ---
  commands:
  hooks:
    after-install:
    - "#{hooks}"
  load_paths:
    #{name}:
    - "#{lib_dir}"
  plugin_paths:
    #{name}: "#{root_dir}"
  sources:
  YAML
end

private def plugin_hook_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  "source \"#{remote}\"\n\ngem \"json_pure\"\n"
end

private def with_plugin_hook_home(dir : String, &)
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

private def with_plugin_hook_bridge(&)
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

private def write_marker_plugin(dir : String, name : String, body : String) : String
  root = File.join(dir, name)
  Dir.mkdir_p(File.join(root, "lib"))
  File.write(File.join(root, "plugins.rb"), "require \"#{name}\"\n")
  File.write(File.join(root, "lib", "#{name}.rb"), body)
  root
end

private def with_plugins_setting(value : String?, &)
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

private def plugin_hook_body(dir : String, file : String, content : String) : String
  <<-RUBY
  require "bundler/plugin"
  require "bundler/plugin/api"

  class FailureSemanticsPlugin < Bundler::Plugin::API
    hook(Bundler::Plugin::Events::GEM_AFTER_INSTALL) do |_, _ctx|
      File.write(File.join(#{dir.inspect}, #{file.inspect}), #{content.inspect})
    end
  end
  RUBY
end

describe "M7(6) plugin hook failure semantics" do
  it "skips loading and hooks when BUNDLE_PLUGINS is false" do
    pending! "ruby not available" unless ruby_available?
    with_plugin_hook_bridge do
      with_project({"Gemfile" => plugin_hook_gemfile}) do |dir|
        root = write_marker_plugin(dir, "marker_plugin", plugin_hook_body(dir, "hook-fired.txt", "fired"))
        plugin_hook_index(dir, "marker_plugin", root)
        with_plugin_hook_home(dir) do
          with_plugins_setting("false") do
            code, _out, err = run_cli(["install"])
            code.should eq(0)
            File.exists?(File.join(dir, "hook-fired.txt")).should be_false
            err.downcase.should_not contain("plugin")
          end
        end
      end
    end
  end

  it "runs hooks when BUNDLE_PLUGINS is unset" do
    pending! "ruby not available" unless ruby_available?
    with_plugin_hook_bridge do
      with_project({"Gemfile" => plugin_hook_gemfile}) do |dir|
        root = write_marker_plugin(dir, "marker_plugin", plugin_hook_body(dir, "hook-fired.txt", "fired"))
        plugin_hook_index(dir, "marker_plugin", root)
        with_plugin_hook_home(dir) do
          with_plugins_setting(nil) do
            code, _out, _err = run_cli(["install"])
            code.should eq(0)
            File.exists?(File.join(dir, "hook-fired.txt")).should be_true
          end
        end
      end
    end
  end

  it "fails the install when a hook raises" do
    pending! "ruby not available" unless ruby_available?
    with_plugin_hook_bridge do
      with_project({"Gemfile" => plugin_hook_gemfile}) do |dir|
        body = <<-RUBY
        require "bundler/plugin"
        require "bundler/plugin/api"

        class RaisingHookPlugin < Bundler::Plugin::API
          hook(Bundler::Plugin::Events::GEM_AFTER_INSTALL) do |_, _ctx|
            raise "boom from plugin hook"
          end
        end
        RUBY
        root = write_marker_plugin(dir, "raising_hook_plugin", body)
        plugin_hook_index(dir, "raising_hook_plugin", root)
        with_plugin_hook_home(dir) do
          with_plugins_setting(nil) do
            code, out, err = run_cli(["install"])
            code.should eq(1)
            err.should contain("Plugin hook after-install failed:")
            err.should contain("boom from plugin hook")
            # The reference runs hooks inside the installer, before it writes
            # the lockfile and before `bundle install` prints its summary.
            File.exists?(File.join(dir, "Gemfile.lock")).should be_false
            out.should_not contain("Bundle complete!")
          end
        end
      end
    end
  end

  it "fails the install when a plugin cannot be loaded" do
    pending! "ruby not available" unless ruby_available?
    with_plugin_hook_bridge do
      with_project({"Gemfile" => plugin_hook_gemfile}) do |dir|
        root = File.join(dir, "broken_plugin")
        Dir.mkdir_p(File.join(root, "lib"))
        File.write(File.join(root, "plugins.rb"), "raise \"boom at plugin load\"\n")
        plugin_hook_index(dir, "broken_plugin", root)
        with_plugin_hook_home(dir) do
          with_plugins_setting(nil) do
            code, _out, err = run_cli(["install"])
            code.should eq(1)
            err.should contain("Failed loading plugin broken_plugin: boom at plugin load")
          end
        end
      end
    end
  end

  it "warns and continues when a plugin load path is missing" do
    pending! "ruby not available" unless ruby_available?
    with_plugin_hook_bridge do
      with_project({"Gemfile" => plugin_hook_gemfile}) do |dir|
        root = File.join(dir, "ghost_plugin")
        plugin_hook_index(dir, "ghost_plugin", root)
        with_plugin_hook_home(dir) do
          with_plugins_setting(nil) do
            code, _out, err = run_cli(["install"])
            code.should eq(0)
            expected = "The following plugin paths don't exist: #{File.join(dir, "ghost_plugin", "lib").gsub(/\\/, "/")}.\n\n" \
                       "This can happen if the plugin was installed with a different version of Ruby that has since been uninstalled.\n\n" \
                       "If you would like to reinstall the plugin, run:\n\n" \
                       "bundler plugin uninstall ghost_plugin && bundler plugin install ghost_plugin\n\n" \
                       "Continuing without installing plugin ghost_plugin.\n"
            err.should eq(expected)
          end
        end
      end
    end
  end

  it "still runs hooks of healthy plugins when another plugin path is missing" do
    pending! "ruby not available" unless ruby_available?
    with_plugin_hook_bridge do
      with_project({"Gemfile" => plugin_hook_gemfile}) do |dir|
        marker_root = write_marker_plugin(dir, "marker_plugin", plugin_hook_body(dir, "hook-fired.txt", "fired"))
        ghost_root = File.join(dir, "ghost_plugin")
        # Two plugins in the same event; the broken one is listed first so the
        # old bridge returned before loading the healthy plugin.
        index_dir = File.join(dir, ".bundle", "plugin")
        Dir.mkdir_p(index_dir)
        File.write(File.join(index_dir, "index"), <<-YAML)
        ---
        commands:
        hooks:
          after-install:
          - "ghost_plugin"
          - "marker_plugin"
        load_paths:
          ghost_plugin:
          - "#{File.join(dir, "ghost_lib").gsub(/\\/, "/")}"
          marker_plugin:
          - "#{File.join(marker_root, "lib").gsub(/\\/, "/")}"
        plugin_paths:
          ghost_plugin: "#{ghost_root.gsub(/\\/, "/")}"
          marker_plugin: "#{marker_root.gsub(/\\/, "/")}"
        sources:
        YAML
        with_plugin_hook_home(dir) do
          with_plugins_setting(nil) do
            code, _out, err = run_cli(["install"])
            code.should eq(0)
            err.should contain("Continuing without installing plugin ghost_plugin.")
            File.exists?(File.join(dir, "hook-fired.txt")).should be_true
          end
        end
      end
    end
  end
end
