require "./spec_helper"

# M7(3) task-51 F2: `bundle cache` writes into `<Gemfile root>/vendor/cache`
# (`Bundler.app_cache` = root.join(settings.app_cache_path), bundler.rb:340-343,
# settings.rb:304-306), not into the invocation cwd.
private def cache_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def cache_gemfile : String
  "source \"#{cache_index_url}\"\n\ngem \"json_pure\"\n"
end

private def with_env(values : Hash(String, String), &)
  previous = {} of String => String?
  values.each do |key, value|
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

private def capture_cache(&block : (IO, IO) -> Int32) : {Int32, String, String}
  stdout_mem = IO::Memory.new
  stderr_mem = IO::Memory.new
  code = yield stdout_mem, stderr_mem
  {code, stdout_mem.to_s, stderr_mem.to_s}
end

describe "M7 bundle cache target root" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end

  it "writes vendor/cache under the Gemfile root when BUNDLE_GEMFILE is in a subdirectory" do
    with_project({
      "app/deps.gemfile" => cache_gemfile,
    }) do |dir|
      bundle_path = File.join(dir, "tmp-bundle")
      with_env({"BUNDLE_GEMFILE" => "app/deps.gemfile", "BUNDLE_PATH" => bundle_path}) do
        code, out_text, err_text = capture_cache { |o, e| Celerite::Commands.cache(o, e, [] of String) }
        code.should eq(0)
        err_text.should eq("")
        out_text.should contain("Updating files in vendor/cache")
        File.file?(File.join(dir, "app/vendor/cache/json_pure-2.8.1.gem")).should be_true
        Dir.exists?(File.join(dir, "vendor/cache")).should be_false
      end
    end
  end

  it "resolves --cache-path relative to the Gemfile root" do
    with_project({"Gemfile" => cache_gemfile}) do |dir|
      bundle_path = File.join(dir, "tmp-bundle")
      with_env({"BUNDLE_PATH" => bundle_path}) do
        code, _out, _err = capture_cache { |o, e| Celerite::Commands.cache(o, e, ["--cache-path", "relcache"]) }
        code.should eq(0)
        File.file?(File.join(dir, "relcache/json_pure-2.8.1.gem")).should be_true
      end
    end
  end

  it "keeps the default vendor/cache when the Gemfile is at the working directory" do
    with_project({"Gemfile" => cache_gemfile}) do |dir|
      bundle_path = File.join(dir, "tmp-bundle")
      with_env({"BUNDLE_PATH" => bundle_path}) do
        code, _out, _err = capture_cache { |o, e| Celerite::Commands.cache(o, e, [] of String) }
        code.should eq(0)
        File.file?(File.join(dir, "vendor/cache/json_pure-2.8.1.gem")).should be_true
      end
    end
  end

  # `app_cache_path` reads the `cache_path` setting (settings.rb:304-306), which
  # `BUNDLE_CACHE_PATH` feeds; `runtime.rb:115` prints that raw value, so the
  # label stays `custom` instead of an expanded path.
  it "writes BUNDLE_CACHE_PATH under the Gemfile root and prints the label" do
    with_project({"Gemfile" => cache_gemfile}) do |dir|
      bundle_path = File.join(dir, "tmp-bundle")
      with_env({"BUNDLE_PATH" => bundle_path, "BUNDLE_CACHE_PATH" => "custom"}) do
        code, out_text, err_text = capture_cache { |o, e| Celerite::Commands.cache(o, e, [] of String) }
        code.should eq(0)
        err_text.should eq("")
        out_text.should contain("Updating files in custom")
        File.file?(File.join(dir, "custom/json_pure-2.8.1.gem")).should be_true
        Dir.exists?(File.join(dir, "vendor/cache")).should be_false
      end
    end
  end

  # `CLI::Cache#run` installs `--cache-path` as a command-option setting
  # (cli/cache.rb:11), which outranks the env/config value.
  it "lets --cache-path win over BUNDLE_CACHE_PATH" do
    with_project({"Gemfile" => cache_gemfile}) do |dir|
      bundle_path = File.join(dir, "tmp-bundle")
      with_env({"BUNDLE_PATH" => bundle_path, "BUNDLE_CACHE_PATH" => "fromenv"}) do
        code, out_text, _err = capture_cache { |o, e| Celerite::Commands.cache(o, e, ["--cache-path", "flagdir"]) }
        code.should eq(0)
        out_text.should contain("Updating files in flagdir")
        File.file?(File.join(dir, "flagdir/json_pure-2.8.1.gem")).should be_true
        Dir.exists?(File.join(dir, "fromenv")).should be_false
      end
    end
  end
end
