require "./spec_helper"
require "../src/celerite"

module Celerite
  # Plugin visible objects through the bridge (architecture §2.2): the hook
  # execution runs the reference Bundler::Plugin API in the bridge process.
  describe PluginHooks do
    it "reports no-op when no plugin index exists" do
      pending! "ruby not available" unless ruby_available?
      with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do
        with_client do |client|
          result = PluginHooks.call(client, Definition.build, "after-install")
          result.fired.should be_false
        end
      end
    end

    it "fires a plugin hook through the bridge (third-party plugin fixture)" do
      pending! "ruby not available" unless ruby_available?
      with_project({
        "Gemfile" => "source \"https://rubygems.org\"\n",
      }) do |dir|
        # hand-built third-party plugin: reference layout (plugins.rb + lib)
        plugin_root = File.join(dir, "my_plugin")
        Dir.mkdir_p(File.join(plugin_root, "lib"))
        File.write(File.join(plugin_root, "plugins.rb"), "require \"my_plugin\"\n")
        File.write(File.join(plugin_root, "lib", "my_plugin.rb"), <<-RUBY
        require "bundler/plugin"
        require "bundler/plugin/api"

        class MyHookPlugin < Bundler::Plugin::API
          hook(Bundler::Plugin::Events::GEM_AFTER_INSTALL) do |_, _ctx|
            File.write(File.join(#{dir.inspect}, "hook-fired.txt"), "fired")
          end
        end
        RUBY
        )

        # project-local plugin index (reference layout, written by plugin install)
        marker = File.join(dir, "hook-fired.txt")
        index_dir = File.join(dir, ".bundle", "plugin")
        Dir.mkdir_p(index_dir)
        lib_dir = File.join(plugin_root, "lib").gsub(/\\/, "/")
        File.write(File.join(index_dir, "index"), <<-YAML
        ---
        hooks:
          after-install:
          - my_hook_plugin
        load_paths:
          my_hook_plugin:
          - #{lib_dir.inspect}
        plugin_paths:
          my_hook_plugin: #{plugin_root.inspect}
        YAML
        )

        with_client do |client|
          result = PluginHooks.call(client, Definition.build, "after-install")
          result.fired.should be_true
          File.file?(marker).should be_true
        end
      end
    end

    it "reports load failure for a broken plugin" do
      pending! "ruby not available" unless ruby_available?
      with_project({
        "Gemfile" => "source \"https://rubygems.org\"\n",
      }) do |dir|
        plugin_root = File.join(dir, "broken_plugin")
        Dir.mkdir_p(File.join(plugin_root, "lib"))
        File.write(File.join(plugin_root, "plugins.rb"), "require \"broken_plugin\"\n")
        File.write(File.join(plugin_root, "lib", "broken_plugin.rb"), "raise 'boom'\n")

        index_dir = File.join(dir, ".bundle", "plugin")
        Dir.mkdir_p(index_dir)
        lib_dir = File.join(plugin_root, "lib").gsub(/\\/, "/")
        File.write(File.join(index_dir, "index"), <<-YAML
        ---
        hooks:
          after-install:
          - broken_plugin
        load_paths:
          broken_plugin:
          - #{lib_dir.inspect}
        YAML
        )

        with_client do |client|
          result = PluginHooks.call(client, Definition.build, "after-install")
          result.fired.should be_false
          result.reason.to_s.should contain "failed to load"
        end
      end
    end
  end
end
