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

    # source type -> plugin name, preserving the index's insertion order
    # (`sources:` in the reference index; plugin/index.rb:62-64, :186-200).
    def self.sources(index_path : String) : Hash(String, String)
      result = {} of String => String
      return result unless File.file?(index_path)

      data = YAML.parse(File.read(index_path))
      if section = data["sources"]?
        if map = section.as_h?
          map.each { |key, value| result[key.as_s] = value.as_s }
        end
      end
      result
    rescue
      {} of String => String
    end

    # Declarations made by a plugin's `plugins.rb`: commands registered through
    # `Bundler::Plugin::API.command` and hook events registered through
    # `Bundler::Plugin.add_hook` (reference: bundler-4.0.24/lib/bundler/plugin.rb:207-220
    # and plugin/index.rb:54-74, where both key sets are copied into the index).
    # `error` carries the load failure reported by the probe (`{"error": ...}`),
    # e.g. an undefined hook event that the reference raises for in plugin.rb:213-220;
    # both arrays are empty in that case and callers must not treat it as success.
    alias Declared = NamedTuple(commands: Array(String), hooks: Array(String), sources: Array(String), error: String?)

    def self.declared(plugins_rb_path : String, load_paths : Array(String) = [] of String) : Declared
      none = {commands: [] of String, hooks: [] of String, sources: [] of String, error: nil.as(String?)}
      return none unless File.file?(plugins_rb_path)

      begin
        ruby = ENV["CELERITE_RUBY"]? || "ruby"
        output = IO::Memory.new
        process = Process.run(
          ruby,
          [script_path, "--commands", plugins_rb_path] + load_paths,
          output: output,
          error: IO::Memory.new,
        )

        line = output.to_s.lines.first?.try(&.strip) || ""
        return none if line.empty?

        parsed = begin
          JSON.parse(line)
        rescue
          return none
        end
        # A malformed plugin makes the probe exit non-zero after printing the
        # error object; surface it instead of silently dropping the declarations.
        if failure = parsed["error"]?
          return {commands: [] of String, hooks: [] of String, sources: [] of String, error: failure.to_s.as(String?)}
        end
        return none unless process.success?

        {commands: string_array(parsed, "commands"), hooks: string_array(parsed, "hooks"), sources: string_array(parsed, "sources"), error: nil.as(String?)}
      rescue
        none
      end
    end

    # Commands declared by a plugin's `plugins.rb` (empty when the plugin has
    # no commands or the file cannot be loaded).
    def self.declared_commands(plugins_rb_path : String, load_paths : Array(String) = [] of String) : Array(String)
      declared(plugins_rb_path, load_paths)[:commands]
    end

    private def self.string_array(parsed : JSON::Any, key : String) : Array(String)
      value = parsed[key]?
      return [] of String unless value
      value.as_a.map(&.as_s)
    rescue
      [] of String
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
