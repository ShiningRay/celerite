require "boom_plugin"

module BoomPlugin
  class ProbeCommand
    def exec(command, args)
      0
    end
  end
end

Bundler::Plugin::API.command("boomprobe", BoomPlugin::ProbeCommand)
Bundler::Plugin.add_hook("after-install") { |_ctx| raise "boom" }
