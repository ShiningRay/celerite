require "hook_plugin"

module HookPlugin
  class ProbeCommand
    def exec(command, args)
      0
    end
  end
end

Bundler::Plugin::API.command("hookprobe", HookPlugin::ProbeCommand)
Bundler::Plugin.add_hook("after-install") { |_ctx| }
