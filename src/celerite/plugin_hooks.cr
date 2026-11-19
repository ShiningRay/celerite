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
    # Reference event layout (`plugin/events.rb`): `GEM_BEFORE_INSTALL_ALL`
    # serializes as "before-install-all" (`:49-50`), `GEM_AFTER_INSTALL_ALL`
    # as "after-install-all" (`:57-58`), and the per-spec
    # `GEM_AFTER_INSTALL` as "after-install" (`:45-46`). The install-all
    # events receive `definition.dependencies` as their single argument
    # (`installer.rb:12-20`).
    EVENTS = ["after-install", "before-install-all", "after-install-all"]

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
      getter output : String

      def initialize(@status : String, @message : String? = nil, @plugin : String? = nil,
                     @missing : Array(MissingPluginPaths) = [] of MissingPluginPaths,
                     @plugins : Array(String) = [] of String, @reason : String? = nil,
                     @output : String = "")
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

    # The reference fires `gem_after_install` once per installed spec from
    # inside the installer (`parallel_installer.rb:217`), handing over the
    # `SpecInstallation` (`name`/`full_name`/`state`). `spec_name` carries that
    # identity so plugin blocks that read `ctx.name` see the same value.
    def self.call(bridge : Bridge::Client, definition : Definition, event : String,
                  spec_name : String? = nil, spec_full_name : String? = nil,
                  gemfile_path : String? = nil) : HookResult
      result = bridge.exec_plugin_hook(event, index_path(definition), spec_name, spec_full_name,
        gemfile_path || definition.gemfile_path)
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
      output = result["stdout"]?.try(&.as_s?) || ""
      HookResult.new(status: status, message: message, plugin: plugin,
        missing: missing, plugins: loaded, reason: reason, output: output)
    end

    # Runs an install-lifecycle event (`before-install-all` /
    # `after-install-all`) and returns a non-nil exit code when the command
    # must abort. The reference calls these from `Installer.install`
    # (`installer.rb:12-20`) with no rescue around the block, so a raising
    # hook aborts the command; missing load paths only warn
    # (`plugin.rb:345-381`).
    def self.run(bridge : Bridge::Client, definition : Definition, config : Config,
                 event : String, stdout : IO, stderr : IO) : Int32?
      return nil unless enabled?(config)

      result = call(bridge, definition, event)
      stdout.print result.output
      result.missing.each do |entry|
        stderr.puts "The following plugin paths don't exist: #{entry.paths.join(", ")}."
        stderr.puts
        stderr.puts "This can happen if the plugin was installed with a different version of Ruby that has since been uninstalled."
        stderr.puts
        stderr.puts "If you would like to reinstall the plugin, run:"
        stderr.puts
        stderr.puts "bundler plugin uninstall #{entry.plugin} && bundler plugin install #{entry.plugin}"
        stderr.puts
        stderr.puts "Continuing without installing plugin #{entry.plugin}."
      end
      case result.status
      when "load_failed"
        stderr.puts "Failed loading plugin #{result.plugin}: #{result.message}"
        1
      when "hook_failed"
        stderr.puts "Plugin hook #{event} failed: #{result.message}"
        1
      else
        nil
      end
    end
  end
end
