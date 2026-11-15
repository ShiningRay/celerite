require "./bridge/client"
require "./config"
require "./errors"

module Celerite
  # Plugin lifecycle hooks (pinned contract: `Bundler::Plugin.hook`).
  # Hooks are Ruby code executed by the bridge; with no installed plugins the
  # call is a no-op (parity: `return unless plugins.any?`).
  #
  # Failure semantics mirror bundler-4.0.24 `lib/bundler/plugin.rb`:
  # - `hook` returns immediately unless `Bundler.settings[:plugins]` is truthy
  #   (L228-240), so a disabled setting skips loading and hook execution.
  # - `load_plugin` warns and continues when a load path directory is absent
  #   (L345-381); a failure while evaluating `plugins.rb` is reported and
  #   re-raised.
  # - hook blocks are invoked without a rescue, so a raise aborts the command.
  module PluginHooks
    # Reference layout event name: Bundler::Plugin::Events::GEM_AFTER_INSTALL
    # serializes as "after-install" in the project plugin index.
    EVENTS = ["after-install"]

    struct MissingPluginPaths
      getter plugin : String
      getter paths : Array(String)

      def initialize(@plugin : String, @paths : Array(String))
      end
    end

    struct HookResult
      getter status : String
      getter message : String?
      getter plugin : String?
      getter missing : Array(MissingPluginPaths)
      getter plugins : Array(String)
      getter reason : String?

      def initialize(@status : String, @message : String? = nil, @plugin : String? = nil,
                     @missing : Array(MissingPluginPaths) = [] of MissingPluginPaths,
                     @plugins : Array(String) = [] of String, @reason : String? = nil)
      end

      # Compatibility accessor for the first missing plugin's paths.
      def missing_paths : Array(String)
        @missing.first?.try(&.paths) || [] of String
      end

      def fired : Bool
        @status == "ok"
      end
    end

    # Bundler::Settings#[] treats only `false` and the string "false" as
    # disabled; an unset key or any other value means plugins are enabled.
    def self.enabled?(config : Config) : Bool
      case value = config["plugins"]
      when Bool
        value
      when String
        value != "false"
      else
        true
      end
    end

    # Reference layout: the plugin index is project-local
    # (<project>/.bundle/plugin/index) — written by `plugin install`.
    def self.index_path(definition : Definition) : String
      File.join(File.dirname(definition.gemfile_path), ".bundle", "plugin", "index")
    end

    def self.call(bridge : Bridge::Client, definition : Definition, event : String) : HookResult
      result = bridge.exec_plugin_hook(event, index_path(definition))
      status = result["status"]?.try(&.as_s?) || "skipped"
      message = result["message"]?.try(&.as_s?)
      plugin = result["plugin"]?.try(&.as_s?)
      paths = (result["paths"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
      missing = (result["missing"]?.try(&.as_a) || [] of JSON::Any).compact_map do |entry|
        name = entry["plugin"]?.try(&.as_s?)
        entry_paths = (entry["paths"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
        name ? MissingPluginPaths.new(name, entry_paths) : nil
      end
      # Compatibility with the intermediate payload that reported a single
      # missing plugin as {"status": "missing_paths", "plugin": ..., "paths": ...}.
      if missing.empty? && !paths.empty? && plugin
        missing << MissingPluginPaths.new(plugin.not_nil!, paths)
      end
      loaded = (result["plugins"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
      reason = result["reason"]?.try(&.as_s?)
      # Compatibility with the pre-status bridge payload: a load failure used
      # to come back as {"fired": false, "reason": "plugin <name> failed ..."}.
      if status == "skipped" && reason.nil? && result["fired"]?.try(&.as_bool) == false
        reason = "no plugin index"
      end
      # Keep the legacy `reason` text for callers that only consumed the
      # pre-status payload (spec/plugin_hooks_spec.cr).
      if status == "load_failed"
        reason ||= "plugin #{plugin} failed to load: #{message}"
      end
      HookResult.new(status: status, message: message, plugin: plugin,
        missing: missing, plugins: loaded, reason: reason)
    end
  end
end
