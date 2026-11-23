require "./spec_helper"

# M7 task-187: `Source::Path#cache` (source/path.rb:84-96) copies the WHOLE
# path source into `Bundler.app_cache.join(app_cache_dirname)`. `app_cache_dirname`
# is `name` = `File.basename(expanded_path.to_s)` (path.rb:72-74, 110-112), i.e.
# the path source's own directory name — not the name of any gemspec it exposes.
# A source holding several gemspecs (each in its own subdirectory) therefore
# lands under one `<cache>/<basename>/` tree, and every gemspec is copied.
private def multi_cache_bridge : String
  File.expand_path("../assets/bridge/server.rb", __DIR__)
end

private def with_multi_cache_env(dir : String, &)
  keys = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_APP_CONFIG GEM_HOME GEM_PATH
    BUNDLE_CACHE_ALL CELERITE_BRIDGE_SERVER CELERITE_PROFILE_BUNDLER_VERSION]
  previous = keys.to_h { |key| {key, ENV[key]?} }
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(dir, "appcfg")
  ENV["CELERITE_BRIDGE_SERVER"] = multi_cache_bridge
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  Dir.mkdir_p(File.join(dir, "appcfg"))
  begin
    yield
  ensure
    previous.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def multi_cache_gem(dir : String, name : String) : Nil
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "lib", "#{name}.rb"), "module #{name.camelcase}\n  VERSION = \"0.1.0\"\nend\n")
  File.write(File.join(dir, "#{name}.gemspec"), <<-SPEC)
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "0.1.0"
      s.summary = "path gem for the multi-gemspec cache fixture"
      s.authors = ["celerite"]
      s.files = ["lib/#{name}.rb"]
      s.require_paths = ["lib"]
    end
    SPEC
end

private def multi_cache_project(dir : String) : String
  project = File.join(dir, "project")
  Dir.mkdir_p(project)
  mono = File.join(dir, "mono")
  multi_cache_gem(File.join(mono, "a_gem"), "a_gem")
  multi_cache_gem(File.join(mono, "b_gem"), "b_gem")
  File.write(File.join(project, "Gemfile"), <<-GEMFILE)
    source "file:///#{File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")}"
    path "../mono" do
      gem "a_gem"
      gem "b_gem"
    end
    GEMFILE
  project
end

private def multi_cache_run(project : String, command : String) : {Int32, String, String}
  original = Dir.current
  Dir.cd(project)
  begin
    run_cli([command])
  ensure
    Dir.cd(original)
  end
end

describe "M7 task-187: cache copies a multi-gemspec path source under its basename" do
  it "keeps both gemspecs under vendor/cache/mono for cache" do
    dir = File.join(File.expand_path("../.tmp-scratch/spec-cache-multi", __DIR__), "cache")
    FileUtils.rm_rf(dir)
    Dir.mkdir_p(dir)
    with_multi_cache_env(dir) do
      project = multi_cache_project(dir)
      code, _out, err = multi_cache_run(project, "cache")
      code.should eq(0), err
      copied = File.join(project, "vendor", "cache", "mono")
      File.exists?(File.join(copied, ".bundlecache")).should be_true
      File.file?(File.join(copied, "a_gem", "a_gem.gemspec")).should be_true
      File.file?(File.join(copied, "b_gem", "b_gem.gemspec")).should be_true
      Dir.exists?(File.join(project, "vendor", "cache", "a_gem")).should be_false
    end
  end

  it "keeps both gemspecs under vendor/cache/mono for package" do
    dir = File.join(File.expand_path("../.tmp-scratch/spec-cache-multi", __DIR__), "package")
    FileUtils.rm_rf(dir)
    Dir.mkdir_p(dir)
    with_multi_cache_env(dir) do
      project = multi_cache_project(dir)
      code, _out, err = multi_cache_run(project, "package")
      code.should eq(0), err
      copied = File.join(project, "vendor", "cache", "mono")
      File.exists?(File.join(copied, ".bundlecache")).should be_true
      File.file?(File.join(copied, "a_gem", "a_gem.gemspec")).should be_true
      File.file?(File.join(copied, "b_gem", "b_gem.gemspec")).should be_true
      File.exists?(File.join(project, "vendor", "cache", "a_gem", "a_gem", "a_gem.gemspec")).should be_false
    end
  end
end
