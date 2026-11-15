#!/usr/bin/env ruby
# One-shot helper for Celerite's plugin command support.
#
# Modes:
#   plugin_command.rb --commands <plugins.rb>           -> {"commands":["cmd", ...]}
#   plugin_command.rb <index> <command> <args...>       -> exec the plugin command
#
# Kept as a separate process so the long-lived bridge's JSON-RPC stdout stays
# clean: a plugin command may print arbitrary output.
require "json"
require "yaml"

def load_plugin_api
  require "bundler"
  require "bundler/plugin"
  Bundler::Plugin::API
end

mode = ARGV[0].to_s

if mode == "--commands"
  plugins_rb = ARGV[1].to_s
  begin
    load_plugin_api
    load plugins_rb
    commands = Bundler::Plugin.instance_variable_get(:@commands) || {}
    puts JSON.generate({ "commands" => commands.keys })
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts JSON.generate({ "error" => "#{e.class}: #{e.message}" })
    exit 1
  end
else
  index_path, command, *args = ARGV
  begin
    load_plugin_api
    index = YAML.safe_load(File.read(index_path), permitted_classes: [Symbol], aliases: true) || {}
    plugin = (index["commands"] || {})[command]
    raise "command `#{command}` is not registered in the plugin index" if plugin.nil?
    root = (index["plugin_paths"] || {})[plugin]
    raise "plugin `#{plugin}` has no recorded path in the index" if root.nil?
    load File.join(root.to_s, "plugins.rb")
    klass = (Bundler::Plugin.instance_variable_get(:@commands) || {})[command]
    raise "command `#{command}` was not registered by #{plugin}" if klass.nil?
    klass.new.exec(command, args)
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "celerite plugin command `#{command}` failed: #{e.class}: #{e.message}"
    exit 1
  end
end
