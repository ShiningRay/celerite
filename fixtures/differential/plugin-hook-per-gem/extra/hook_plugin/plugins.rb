require "bundler/plugin"
require "hook_plugin"

module HookProbe
  class ProbeCommand
    def exec(command, args)
      0
    end
  end
end

Bundler::Plugin::API.command("hookprobe", HookProbe::ProbeCommand)
# The reference runs each spec's hook from the install worker threads
# (parallel_installer.rb:173-184), so hook blocks that append to one shared
# file lose or interleave lines. Write one file per spec instead.
Bundler::Plugin.add_hook("after-install") do |ctx|
  name = ctx.name.to_s
  File.write("hook-log-#{name}", "after-install:#{name}\n")
end
