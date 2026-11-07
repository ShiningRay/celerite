require "./bridge/client"
require "./errors"

module Celerite
  # Plugin lifecycle hooks (pinned contract: `Bundler::Plugin.hook`).
  # Hooks are Ruby code executed by the bridge; with no installed plugins the
  # call is a no-op (parity: `return unless plugins.any?`).
  module PluginHooks
    EVENTS = [
      "post-install",       # after a successful install
      "post-Install-error", # (reference keeps this literal event name)
      "pre-install-check",
    ]

    struct HookResult
      getter fired : Bool
      getter reason : String?
      getter plugins : Array(String)

      def initialize(@fired : Bool, @reason : String? = nil, @plugins : Array(String) = [] of String)
      end
    end

    def self.plugins_index_path(definition : Definition) : String
      home = Config.user_home || "."
      File.join(home, ".bundle", "plugins")
    end

    def self.call(bridge : Bridge::Client, definition : Definition, event : String) : HookResult
      root = plugins_index_path(definition)
      result = bridge.exec_plugin_hook(event, root)
      HookResult.new(
        result["fired"].as_bool,
        result["reason"]?.try(&.as_s?),
        (result["plugins"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s),
      )
    end
  end
end
