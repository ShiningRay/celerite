require "hook_plugin"

module HookPlugin
  class ProbeCommand
    def exec(_command, _args)
      0
    end
  end
end

Bundler::Plugin::API.command("grootprobe", HookPlugin::ProbeCommand)
Bundler::Plugin.add_hook("after-install") { |_ctx| }