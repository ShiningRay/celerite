require "./spec_helper"

# M7 task-84: `Source::Path#cache` (source/path.rb:84-96) copies a path source
# that lives OUTSIDE the Gemfile root into the cache directory when `cache_all`
# is on, and stamps the copy with an empty `.bundlecache`. `cache_all` defaults
# to true in 4.x (settings.rb:88 `"BUNDLE_CACHE_ALL" => true`), so only an
# explicit `false` disables it. An in-project path source is never copied
# (`return if expand(@original_path).to_s.index(root_path.to_s + "/") == 0`).
private def cache_all_bridge : String
  File.expand_path("../assets/bridge/server.rb", __DIR__)
end

private def with_cache_all_env(dir : String, cache_all : Bool?, &)
  keys = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_APP_CONFIG GEM_HOME GEM_PATH
    BUNDLE_CACHE_ALL CELERITE_BRIDGE_SERVER CELERITE_PROFILE_BUNDLER_VERSION]
  previous = keys.to_h { |key| {key, ENV[key]?} }
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(dir, "appcfg")
  ENV["CELERITE_BRIDGE_SERVER"] = cache_all_bridge
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  Dir.mkdir_p(File.join(dir, "appcfg"))
  case cache_all
  when true  then ENV["BUNDLE_CACHE_ALL"] = "true"
  when false then ENV["BUNDLE_CACHE_ALL"] = "false"
  else            ENV.delete("BUNDLE_CACHE_ALL")
  end
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

private def cache_all_gem(dir : String) : Nil
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "lib", "pgem.rb"), "module Pgem\n  VERSION = \"0.1.0\"\nend\n")
  File.write(File.join(dir, "pgem.gemspec"), <<-SPEC)
    Gem::Specification.new do |s|
      s.name = "pgem"
      s.version = "0.1.0"
      s.summary = "path gem"
      s.authors = ["celerite"]
      s.files = ["lib/pgem.rb"]
    end
    SPEC
end

private def cache_all_run(project : String) : {Int32, String, String}
  original = Dir.current
  Dir.cd(project)
  begin
    run_cli(["cache"])
  ensure
    Dir.cd(original)
  end
end

describe "M7 task-84: cache_all copies path sources outside the Gemfile root" do
  it "copies an outside path source and stamps .bundlecache" do
    dir = File.join(File.expand_path("../.tmp-scratch/spec-cache-all", __DIR__), "outside")
    FileUtils.rm_rf(dir)
    Dir.mkdir_p(dir)
    with_cache_all_env(dir, nil) do
      project = File.join(dir, "project")
      Dir.mkdir_p(project)
      cache_all_gem(File.join(dir, "pgem"))
      File.write(File.join(project, "Gemfile"), <<-GEMFILE)
        source "file:///#{File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")}"
        gem "pgem", path: "../pgem"
        GEMFILE
      code, _out, err = cache_all_run(project)
      code.should eq(0), err
      copied = File.join(project, "vendor", "cache", "pgem")
      File.file?(File.join(copied, "lib", "pgem.rb")).should be_true
      File.exists?(File.join(copied, ".bundlecache")).should be_true
      File.read(File.join(copied, ".bundlecache")).should be_empty
    end
  end

  it "does not copy when cache_all is explicitly false" do
    dir = File.join(File.expand_path("../.tmp-scratch/spec-cache-all", __DIR__), "off")
    FileUtils.rm_rf(dir)
    Dir.mkdir_p(dir)
    with_cache_all_env(dir, false) do
      project = File.join(dir, "project")
      Dir.mkdir_p(project)
      cache_all_gem(File.join(dir, "pgem"))
      File.write(File.join(project, "Gemfile"), <<-GEMFILE)
        source "file:///#{File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")}"
        gem "pgem", path: "../pgem"
        GEMFILE
      code, _out, err = cache_all_run(project)
      code.should eq(0), err
      Dir.exists?(File.join(project, "vendor", "cache", "pgem")).should be_false
    end
  end

  it "never copies an in-project path source" do
    dir = File.join(File.expand_path("../.tmp-scratch/spec-cache-all", __DIR__), "inside")
    FileUtils.rm_rf(dir)
    Dir.mkdir_p(dir)
    with_cache_all_env(dir, nil) do
      project = File.join(dir, "project")
      Dir.mkdir_p(project)
      cache_all_gem(File.join(project, "vendor", "pgem"))
      File.write(File.join(project, "Gemfile"), <<-GEMFILE)
        source "file:///#{File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")}"
        gem "pgem", path: "vendor/pgem"
        GEMFILE
      code, _out, err = cache_all_run(project)
      code.should eq(0), err
      Dir.exists?(File.join(project, "vendor", "cache", "pgem")).should be_false
    end
  end
end
