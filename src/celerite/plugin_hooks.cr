require "./bridge/client"
require "./errors"

module Celerite
  # Plugin lifecycle hooks (pinned contract: `Bundler::Plugin.hook`).
  # Hooks are Ruby code executed by the bridge; with no installed plugins the
  # call is a no-op (parity: `return unless plugins.any?`).
  module PluginHooks
    EVENTS = ["post-install"]

    struct HookResult
      getter fired : Bool
      getter reason : String?
      getter plugins : Array(String)

      def initialize(@fired : Bool, @reason : String? = nil, @plugins : Array(String) = [] of String)
      end
    end

    # Reference layout: the plugin index is project-local
    # (<project>/.bundle/plugin/index) — written by `plugin install`.
    def self.index_path(definition : Definition) : String
      File.join(File.dirname(definition.gemfile_path), ".bundle", "plugin", "index")
    end

    def self.call(bridge : Bridge::Client, definition : Definition, event : String) : HookResult
      result = bridge.exec_plugin_hook(event, index_path(definition))
      HookResult.new(
        result["fired"].as_bool,
        result["reason"]?.try(&.as_s?),
        (result["plugins"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s),
      )
    end
  end
end
