require "./spec_helper"

# M7(3) task-87: every install refreshes `vendor/cache` while the directory
# exists (`cli/install.rb:52-53` → `Runtime#cache`, runtime.rb:108-146),
# copying each resolved gem package and printing `  * <file>.gem`
# (`Source::Rubygems#cache`, rubygems.rb:233-242). `--no-cache` and a frozen
# bundle skip the whole step (cli/install.rb:52).
private def app_cache_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def app_cache_files : Hash(String, String)
  {
    "Gemfile"               => "source \"#{app_cache_index_url}\"\n\ngem \"json_pure\"\n",
    "vendor/cache/keep.txt" => "keep\n",
  }
end

private def with_app_cache_env(dir : String, values : Hash(String, String), &)
  previous = {} of String => String?
  base = {
    "BUNDLE_GEMFILE"    => File.join(dir, "Gemfile"),
    "BUNDLE_PATH"       => File.join(dir, "bundle"),
    "BUNDLE_APP_CONFIG" => File.join(dir, ".bundle"),
  }
  base.merge(values).each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
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

private def capture_app_cache(&block : (IO, IO) -> Int32) : {Int32, String, String}
  out_io = IO::Memory.new
  err = IO::Memory.new
  code = yield out_io, err
  {code, out_io.to_s, err.to_s}
end

private def app_cache_install(dir : String, args : Array(String) = [] of String,
                              env : Hash(String, String) = {} of String => String) : {Int32, String, String}
  Dir.mkdir_p(File.join(dir, ".bundle"))
  with_app_cache_env(dir, env) do
    capture_app_cache { |o, e| Celerite::Commands.install(o, e, args) }
  end
end

describe "M7 install refreshes the app cache" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end

  it "copies the resolved gem into an existing vendor/cache and prints the star line" do
    with_project(app_cache_files) do |dir|
      code, out_text, _err = app_cache_install(dir)
      code.should eq(0)
      out_text.should contain("Updating files in vendor/cache")
      out_text.should contain("  * json_pure-2.8.1.gem")
      # `Runtime#cache` runs after the installer and before `Bundle complete!`.
      out_text.index("Updating files in vendor/cache").not_nil!.should be < out_text.index("Bundle complete!").not_nil!
      File.file?(File.join(dir, "vendor", "cache", "json_pure-2.8.1.gem")).should be_true
    end
  end

  it "skips the refresh under --no-cache even when vendor/cache exists" do
    with_project(app_cache_files) do |dir|
      code, out_text, _err = app_cache_install(dir, ["--no-cache"])
      code.should eq(0)
      out_text.should_not contain("Updating files in")
      File.exists?(File.join(dir, "vendor", "cache", "json_pure-2.8.1.gem")).should be_false
    end
  end

  it "skips the refresh for a frozen bundle and restores nothing" do
    with_project(app_cache_files) do |dir|
      code, _out, _err = app_cache_install(dir)
      code.should eq(0)
      cached = File.join(dir, "vendor", "cache", "json_pure-2.8.1.gem")
      File.delete(cached)
      File.exists?(cached).should be_false

      frozen_code, frozen_out, _frozen_err = app_cache_install(dir, [] of String, {"BUNDLE_FROZEN" => "true"})
      frozen_code.should eq(0)
      frozen_out.should_not contain("Updating files in")
      File.exists?(cached).should be_false
    end
  end
end
