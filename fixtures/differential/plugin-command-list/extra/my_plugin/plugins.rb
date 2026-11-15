require "bundler"
require "bundler/plugin"

class MahCommand
  def exec(command, args)
    0
  end
end

Bundler::Plugin::API.command "mahcommand", MahCommand