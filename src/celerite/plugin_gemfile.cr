require "./config"
require "./plugin_hooks"
require "./bridge/client"
require "./gemfile_evaluation"

module Celerite
  # Gemfile-level plugin declarations (reference: `Bundler::Plugin.gemfile_install`
  # in `bundler/plugin.rb:104-127`).
  #
  # The reference pre-installs the plugins a Gemfile declares *before* the
  # normal install runs (`bundler/cli/install.rb:41`), evaluating the Gemfile
  # through `Bundler::Plugin::DSL`. That DSL silently ignores `gem` lines,
  # records `plugin "name"` declarations and turns `source ..., type: :t` into
  # the inferred plugin `bundler-source-t`; unknown methods fail with
  # `PluginGemfileError` (exit 29). The bridge op mirrors that evaluation.
  module PluginGemfile
    def self.enabled?(config : Config) : Bool
      PluginHooks.enabled?(config)
    end

    # Names the Plugin::DSL would pre-install, in declaration order.
    # Raises `Bridge::BridgeError` for Gemfile errors; the envelope carries the
    # reference `status_code` (29 plugin gemfile errors, 15 invalid options,
    # 4 other Gemfile errors), so callers simply propagate it.
    def self.plugin_names(gemfile_path : String) : Array(String)
      bridge = Bridge::Client.shared
      begin
        GemfileEvaluator.plugin_names(gemfile_path, bridge)
      ensure
        bridge.close
      end
    end

    # First `source "<url>"` without a `type:` option; the pre-install pass
    # resolves plugins from the same source list the Gemfile uses.
    def self.primary_source(gemfile_path : String) : String?
      return nil unless File.file?(gemfile_path)

      File.each_line(gemfile_path) do |line|
        code = strip_comment(line)
        next if code.includes?("type:")
        if source = code.match(/^\s*source\s*\(?\s*['"]([^'"]+)['"]/)
          return source[1]
        end
      end
      nil
    end

    private def self.strip_comment(line : String) : String
      single = false
      double = false
      line.each_char_with_index do |char, index|
        case char
        when '\''
          single = !single unless double
        when '"'
          double = !double unless single
        when '#'
          return line[0, index] if !single && !double
        end
      end
      line
    end
  end
end
