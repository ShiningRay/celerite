require "bundler/plugin/api"

class ConflictCommand
  def exec(command, args); end
end

class PlugCA < Bundler::Plugin::API
  command "conflictcmd", ConflictCommand
end
