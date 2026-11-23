require "gitplugin"

module GitPlugin
  class ProbeCommand
    def exec(_command, _args)
      0
    end
  end
end

Bundler::Plugin::API.command("gitprobe", GitPlugin::ProbeCommand)
