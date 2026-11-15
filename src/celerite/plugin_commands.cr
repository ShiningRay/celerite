require "json"
require "yaml"
require "./config"
require "./plugin_hooks"

module Celerite
  # Project-local plugin command registry (reference: Bundler::Plugin::Index
  # and CLI dispatch in bundler-4.0.24/lib/bundler/cli.rb:187-195).
  #
  # Commands are declared by a plugin's `plugins.rb` through
  # `Bundler::Plugin::API.command "<name>", <class>`; the plugin index stores
  # them as `commands: { "<name>" => "<plugin>" }`. Execution happens in a
  # one-shot Ruby process (assets/bridge/plugin_command.rb) so the bridge's
  # JSON-RPC stdout never mixes with plugin output.
  module PluginCommands
    # One-shot helper script, resolved like Bridge::Client.locate_server:
    # explicit override, then source-relative, then next to the executable.
    def self.script_path : String
      if path = ENV["CELERITE_PLUGIN_COMMAND"]?
        return path unless path.empty?
      end
      source_relative = File.expand_path("../../assets/bridge/plugin_command.rb", __DIR__)
      return source_relative if File.file?(source_relative)

      exe_dir = begin
        File.dirname(Process.executable_path || "")
      rescue
        ""
      end
      unless exe_dir.empty?
        candidates = [
          File.join(exe_dir, "assets", "bridge", "plugin_command.rb"),
          File.join(exe_dir, "..", "assets", "bridge", "plugin_command.rb"),
          File.join(exe_dir, "..", "..", "assets", "bridge", "plugin_command.rb"),
        ]
        candidates.each do |candidate|
          expanded = File.expand_path(candidate)
          return expanded if File.file?(expanded)
        end
      end
      source_relative
    end

    # True when the project plugin index already registers `name` under
    # `plugin_paths` (i.e. the plugin is installed).
    def self.installed_plugin?(index_path : String, name : String) : Bool
      return false unless File.file?(index_path)

      index = YAML.parse(File.read(index_path))
      paths = index["plugin_paths"]?
      !!(paths && paths.as_h?.try(&.has_key?(name)))
    rescue
      false
    end

    def self.index_path(gemfile_path : String) : String
      File.join(File.dirname(gemfile_path), ".bundle", "plugin", "index")
    end

    def self.enabled?(config : Config) : Bool
      PluginHooks.enabled?(config)
    end

    # command name -> plugin name, preserving the index's insertion order.
    def self.commands(index_path : String) : Hash(String, String)
      result = {} of String => String
      return result unless File.file?(index_path)

      data = YAML.parse(File.read(index_path))
      if section = data["commands"]?
        if map = section.as_h?
          map.each { |key, value| result[key.as_s] = value.as_s }
        end
      end
      result
    rescue
      {} of String => String
    end

    # Commands declared by a plugin's `plugins.rb` (empty when the plugin has
    # no commands or the file cannot be loaded).
    def self.declared_commands(plugins_rb_path : String) : Array(String)
      return [] of String unless File.file?(plugins_rb_path)

      ruby = ENV["CELERITE_RUBY"]? || "ruby"
      output = IO::Memory.new
      process = Process.run(
        ruby,
        [script_path, "--commands", plugins_rb_path],
        output: output,
        error: IO::Memory.new,
      )
      return [] of String unless process.success?

      line = output.to_s.lines.first?.try(&.strip) || ""
      return [] of String if line.empty?

      parsed = begin
        JSON.parse(line)
      rescue
        return [] of String
      end
      return [] of String if parsed["error"]?
      (parsed["commands"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
    end

    # Runs a registered plugin command in a child Ruby process with inherited
    # stdio (the reference runs it in-process; that difference is documented).
    def self.exec(index_path : String, command : String, args : Array(String)) : Int32
      ruby = ENV["CELERITE_RUBY"]? || "ruby"
      process = Process.run(
        ruby,
        [script_path, index_path, command] + args,
        input: :inherit,
        output: :inherit,
        error: :inherit,
      )
      process.exit_code
    rescue
      1
    end
  end
end
