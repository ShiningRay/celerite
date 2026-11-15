require "./spec_helper"
require "../src/celerite/glob"

# M7(5): `Dir.glob` treats `\` as an escape, so `File.join`-built patterns never
# match on Windows. `Celerite::Glob.paths` normalises the directory to `/`.
private def vendor_cache_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  yield
ensure
  if previous
    ENV["CELERITE_BRIDGE_SERVER"] = previous
  else
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end
end

private def vendor_cache_ruby_gem_dir : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.default_dir"], output: output)
  output.to_s
end

private def vendor_cache_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

private def with_vendor_cache_env(project : String, &)
  gem_home = File.join(project, "gemhome")
  Dir.mkdir_p(gem_home)
  names = ["HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = "#{gem_home};#{vendor_cache_ruby_gem_dir}"
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  begin
    yield gem_home
  ensure
    previous.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def vendor_cache_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def vendor_cache_gem_fixture : String
  File.expand_path("../fixtures/vendor-cache/plain-gem-0.2.0.gem", __DIR__)
end

describe "M7(5) vendor/cache globbing" do
  it "matches Windows-style directories built with File.join" do
    dir = File.join(File.tempname("celerite-glob", "dir"), "data")
    Dir.mkdir_p(dir)
    begin
      File.write(File.join(dir, "a.gem"), "")
      File.write(File.join(dir, "b.gem"), "")
      # `File.join` yields `...\data\*.gem` on Windows; a raw Dir.glob on that
      # pattern returns [] because `\` is an escape.
      matches = Celerite::Glob.paths(File.join(dir), "*.gem")
      matches.size.should eq(2)
    ensure
      FileUtils.rm_rf(File.dirname(dir))
    end
  end

  it "installs a gem that only exists in vendor/cache under --local" do
    vendor_cache_bridge do
      with_project({
        "Gemfile"                          => "source \"#{vendor_cache_remote}\"\n\ngem \"plain-gem\"\n",
        "vendor/cache/plain-gem-0.2.0.gem" => File.read(vendor_cache_gem_fixture),
      }) do |dir|
        with_vendor_cache_env(dir) do
          code, output, _errors = run_cli(["install", "--local"])
          code.should eq(0)
          output.should contain("Installing plain-gem 0.2.0")
          spec_path = File.join(dir, "bundle", "ruby", vendor_cache_abi, "specifications", "plain-gem-0.2.0.gemspec")
          File.file?(spec_path).should be_true
        end
      end
    end
  end

  it "still reports a missing gem when neither the index nor vendor/cache has it" do
    vendor_cache_bridge do
      with_project({
        "Gemfile" => "source \"#{vendor_cache_remote}\"\n\ngem \"json_pure\"\n",
      }) do |dir|
        with_vendor_cache_env(dir) do
          code, _output, errors = run_cli(["install", "--local"])
          code.should eq(7)
          errors.should contain("Could not find gem 'json_pure' in locally installed gems.")
        end
      end
    end
  end
end
