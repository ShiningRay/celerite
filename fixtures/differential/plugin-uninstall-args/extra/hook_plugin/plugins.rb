require "hook_plugin"

module HookPlugin
  class ProbeCommand
    def exec(_command, _args)
      0
    end
  end
end

Bundler::Plugin::API.command("hookprobe", HookPlugin::ProbeCommand)

# First install (no lockfile yet): append a line to `hook-log`. Once a
# lockfile exists the project has already been installed once, so a *later*
# call must be the post-uninstall `install`; if the uninstall cleanup failed
# and the plugin is still recorded, this file appears and `file-absent` fails.
Bundler::Plugin.add_hook("after-install") do |_ctx|
  if File.exist?("hook-log") && File.exist?("Gemfile.lock")
    File.write("hook-after-uninstall", "hook ran after uninstall\n")
  else
    File.open("hook-log", "a") { |f| f.puts "after-install" }
  end
end
