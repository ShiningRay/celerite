require "./spec_helper"

# `BUNDLE_FORCE_RUBY_PLATFORM` (task-76). The reference resolves against the
# generic platform only: `settings.rb:21` lists the key in `BOOL_KEYS`,
# `definition.rb:662` short-circuits the extra-platform pass,
# `lazy_specification.rb:221` and `match_platform.rb:28` force the ruby
# variant. Measured on 4.0.24 and 2.7.2 with `fixtures/gem-index-platform`
# (which ships both `platdemo-1.0.0` and `platdemo-1.0.0-x64-mingw-ucrt`):
# the lock holds `platdemo (1.0.0)` and `PLATFORMS` has only `  ruby`.
#
# A lock written for the native platform is not reused: the reference
# re-resolves, installs the ruby variant and keeps the native row in the
# lockfile (`resolver.rb:88-89` + `spec_set.rb:301-309`).

private def force_ruby_gemfile : String
  url = file_source_url(File.expand_path("../fixtures/gem-index-platform", __DIR__))
  "source \"#{url}\"\n\ngem \"platdemo\"\n"
end

private def force_ruby_locked_lockfile : String
  url = file_source_url(File.expand_path("../fixtures/gem-index-platform", __DIR__))
  <<-LOCK
GEM
  remote: #{url}/
  specs:
    platdemo (1.0.0-x64-mingw-ucrt)

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  platdemo
LOCK
end

private def with_force_ruby_env(force : String?, &) : Nil
  keys = [
    "HOME", "USERPROFILE", "BUNDLE_PATH", "BUNDLE_APP_CONFIG",
    "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION",
    "CELERITE_REFERENCE_BUNDLER_VERSION", "CELERITE_REFERENCE_BUNDLER_LIB",
    "BUNDLE_FORCE_RUBY_PLATFORM",
  ]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]?; ENV.delete(key) }
  begin
    yield
  ensure
    keys.each do |key|
      ENV.delete(key)
      if value = previous[key]
        ENV[key] = value
      end
    end
  end
end

private def force_ruby_run(profile : String, dir : String, force : String?, args : Array(String)) : {Int32, String, String}
  code = 0
  out = ""
  err = ""
  with_force_ruby_env(force) do
    app_config = File.join(dir, ".bundle")
    Dir.mkdir_p(app_config)
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
    ENV["BUNDLE_APP_CONFIG"] = app_config
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = profile
    ENV["CELERITE_REFERENCE_BUNDLER_VERSION"] = profile
    ENV["CELERITE_REFERENCE_BUNDLER_LIB"] = if profile == "2.7.2"
                                              "C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-2.7.2/lib"
                                            else
                                              File.expand_path("../.upstream-specs/v4.0.24/bundler/lib", __DIR__)
                                            end
    ENV["BUNDLE_FORCE_RUBY_PLATFORM"] = force.not_nil! if force
    code, out, err = run_cli(args)
  end
  {code, out, err}
end

private def force_ruby_specs(lockfile : String) : Array(String)
  lockfile.lines(chomp: true)
    .skip_while(&.!=("  specs:"))
    .skip(1).take_while { |line| line.starts_with?("    ") }
    .map(&.strip)
end

private def force_ruby_platforms(lockfile : String) : Array(String)
  lockfile.lines(chomp: true)
    .skip_while(&.!=("PLATFORMS"))
    .skip(1).take_while { |line| line.starts_with?("  ") }
    .map(&.strip)
end

describe "M7(3) BUNDLE_FORCE_RUBY_PLATFORM" do
  it "resolves and locks the generic platform only" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => force_ruby_gemfile}) do |dir|
      code, out, err = force_ruby_run("4.0.24", dir, "true", ["install"])
      code.should eq(0)
      err.should be_empty
      out.should contain("Fetching platdemo 1.0.0\n")
      out.should contain("Installing platdemo 1.0.0\n")
      out.should_not contain("x64-mingw-ucrt")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      force_ruby_specs(lock).should eq(["platdemo (1.0.0)"])
      lock.should contain("PLATFORMS\n  ruby\n\nDEPENDENCIES")
    end
  end

  it "keeps the native variant when the setting is false" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => force_ruby_gemfile}) do |dir|
      code, out, err = force_ruby_run("4.0.24", dir, "false", ["install"])
      code.should eq(0)
      err.should be_empty
      out.should contain("Fetching platdemo 1.0.0 (x64-mingw-ucrt)\n")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      force_ruby_specs(lock).should eq(["platdemo (1.0.0-x64-mingw-ucrt)"])
      lock.should contain("PLATFORMS\n  x64-mingw-ucrt\n")
    end
  end

  it "treats an unset setting like false" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => force_ruby_gemfile}) do |dir|
      code, _, _ = force_ruby_run("4.0.24", dir, nil, ["install"])
      code.should eq(0)
      unset_lock = File.read(File.join(dir, "Gemfile.lock"))
      File.delete(File.join(dir, "Gemfile.lock"))

      code, _, _ = force_ruby_run("4.0.24", dir, "false", ["install"])
      code.should eq(0)
      false_lock = File.read(File.join(dir, "Gemfile.lock"))
      # Byte equality would also compare the CHECKSUMS section, which picks up
      # a digest once the gem sits in the bundle cache; the platform decision is
      # what this pair of runs exercises.
      force_ruby_specs(false_lock).should eq(force_ruby_specs(unset_lock))
      force_ruby_platforms(false_lock).should eq(force_ruby_platforms(unset_lock))
    end
  end

  it "re-resolves a native lock and keeps the platform row" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => force_ruby_gemfile, "Gemfile.lock" => force_ruby_locked_lockfile}) do |dir|
      code, out, err = force_ruby_run("4.0.24", dir, "true", ["install"])
      code.should eq(0)
      err.should be_empty
      out.should contain("Resolving dependencies...")
      out.should contain("Fetching platdemo 1.0.0\n")
      out.should_not contain("Fetching platdemo 1.0.0 (x64-mingw-ucrt)")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      force_ruby_specs(lock).should eq(["platdemo (1.0.0)", "platdemo (1.0.0-x64-mingw-ucrt)"])
      lock.should contain("PLATFORMS\n  ruby\n  x64-mingw-ucrt\n")
    end
  end
end
