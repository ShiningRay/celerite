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
end
