require "bundler/plugin/api"

class PlugA < Bundler::Plugin::API
  source "conflict-type"
end
