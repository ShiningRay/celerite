#!/usr/bin/env ruby
# One-shot helper for Celerite's plugin command support.
#
# Modes:
#   plugin_command.rb --commands <plugins.rb> [<load path>...]
#                                                       -> {"commands":["cmd", ...],
#                                                           "hooks":["event", ...]}
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
  load_paths = ARGV[2..] || []
  begin
    load_plugin_api
    # The reference loads plugins.rb with the plugin's own require paths on
    # $LOAD_PATH (plugin.rb register_plugin); mirror that so `require "<gem>"`
    # at the top of plugins.rb resolves.
    load_paths.each { |path| $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path) }
    load plugins_rb
    commands = Bundler::Plugin.instance_variable_get(:@commands) || {}
    hooks = Bundler::Plugin.instance_variable_get(:@hooks_by_event) || {}
    # `Bundler::Plugin::API.source "<type>"` records the type in `@sources`
    # (plugin.rb:181-183); register_plugin copies those keys into the index
    # under `sources:` (plugin.rb:333, plugin/index.rb:62-64), which is what
    # `Plugin.source?(type)` later checks when a Gemfile declares
    # `source "...", type: :<type>` (dsl.rb:124-126).
    sources = Bundler::Plugin.instance_variable_get(:@sources) || {}
    puts JSON.generate({ "commands" => commands.keys, "hooks" => hooks.keys.map(&:to_s),
                         "sources" => sources.keys.map(&:to_s) })
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
    # The reference loads a plugin command through
    # `Plugin.load_plugin(name)` (plugin.rb:345-375), which does
    # `Gem.add_to_load_path(*index.load_paths(name))` (:354, :372) before
    # `load path.join("plugins.rb")`. Without that, a `plugins.rb` whose first
    # line is `require "<plugin gem>"` dies with `LoadError: cannot load such
    # file -- <plugin gem>` even though the plugin is installed correctly.
    Array((index["load_paths"] || {})[plugin]).each do |path|
      $LOAD_PATH.unshift(path.to_s) unless $LOAD_PATH.include?(path.to_s)
    end
    load File.join(root.to_s, "plugins.rb")
    klass = (Bundler::Plugin.instance_variable_get(:@commands) || {})[command]
    raise "command `#{command}` was not registered by #{plugin}" if klass.nil?
    klass.new.exec(command, args)
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "celerite plugin command `#{command}` failed: #{e.class}: #{e.message}"
    exit 1
  end
end
