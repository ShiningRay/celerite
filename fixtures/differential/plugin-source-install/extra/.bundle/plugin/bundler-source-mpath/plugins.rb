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

  # `Plugin::API::Source#install` default raises MalformattedPlugin; the
  # reference success oracle used this copy-into-bundle contract.
  def install(spec, opts)
    dest = Bundler.bundle_path.join("gems", spec.full_name)
    FileUtils.mkdir_p(dest.dirname)
    FileUtils.cp_r(path.to_s, dest.to_s)
    spec_path = Bundler.bundle_path.join("specifications", "#{spec.full_name}.gemspec")
    FileUtils.mkdir_p(spec_path.dirname)
    spec_path.write(spec.to_ruby)
    spec.loaded_from = spec_path.to_s
    post_install(spec)
    "Installed #{spec.name}"
  end
end
