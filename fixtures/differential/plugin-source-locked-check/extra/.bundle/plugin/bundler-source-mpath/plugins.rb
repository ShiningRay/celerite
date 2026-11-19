require "bundler-source-mpath"

class MPath < Bundler::Plugin::API
  source "mpath"

  attr_reader :path

  def initialize(opts)
    super
    @path = Pathname.new options["uri"]
  end

  def fetch_gemspec_files
    @spec_files ||= Dir["#{path}/{,*,*/*}.gemspec"]
  end

  # `check` calls `source_list.local_only!`; a plugin that does not implement
  # the hook raises through `Plugin::API#method_missing` (source.rb API).
  def local_only!
  end

  def remote!
  end
end
