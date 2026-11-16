require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(2)/M7(3): `fund`, `clean` and `binstubs` resolve the Gemfile when the
# project has no lockfile, with Bundler's local-only sources.
#
# Reference: these commands only walk `Bundler.definition.specs`; they never
# call `check!`/`setup_domain!`, so the sources stay at `@allow_remote = false`
# (lib/bundler/source/rubygems.rb:21,44-52).  A missing gem therefore reports
# "in locally installed gems" and no index is fetched.
private def nolock_commands_gemfile(gem_line : String) : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  remote = file_source_url(index)
  gemfile = <<-GEMFILE
    source "#{remote}"

    #{gem_line}
    GEMFILE
  {"Gemfile" => gemfile}
end

private def seed_nolock_commands_gem(gems_dir : String) : Nil
  gem_dir = File.join(gems_dir, "gems", "json_pure-2.8.1")
  Dir.mkdir_p(File.join(gems_dir, "specifications"))
  Dir.mkdir_p(File.join(gem_dir, "lib"))
  File.write(File.join(gem_dir, "lib", "celerite_fixture.rb"), "# stub\n")
  File.write(File.join(gems_dir, "specifications", "json_pure-2.8.1.gemspec"), <<-RUBY)
    Gem::Specification.new do |s|
      s.name = "json_pure"
      s.version = "2.8.1"
      s.summary = "stub installed gem"
      s.description = s.summary
      s.authors = ["Celerite specs"]
      s.email = ["specs@example.com"]
      s.homepage = "https://example.com/json_pure"
      s.license = "MIT"
      s.require_paths = ["lib"]
    end
    RUBY
end

private def with_nolock_commands_env(dir : String, & : String ->) : Nil
  gems = File.join(dir, "gems")
  seed_nolock_commands_gem(gems)
  names = %w[HOME USERPROFILE GEM_HOME GEM_PATH BUNDLE_PATH CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB]
  previous = {} of String => String?
  names.each { |name| previous[name] = ENV[name]? }
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["GEM_HOME"] = gems
  ENV["GEM_PATH"] = gems
  ENV.delete("BUNDLE_PATH")
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield gems
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

describe "M7(2) fund/clean/binstubs without a lockfile" do
  it "resolves installed gems for fund without fetching the index" do
    next unless ruby_available?
    with_project(nolock_commands_gemfile(%(gem "json_pure", "2.8.1"))) do |dir|
      with_nolock_commands_env(dir) do
        code, out, err = run_cli(["fund"])
        code.should eq(0)
        out.should contain("Resolving dependencies...")
        out.should contain("None of the installed gems you directly depend on are looking for funding.")
        out.should_not contain("Fetching source index")
        err.should eq("")
      end
    end
  end

  it "resolves installed gems for clean --dry-run without writing a lockfile" do
    next unless ruby_available?
    with_project(nolock_commands_gemfile(%(gem "json_pure", "2.8.1"))) do |dir|
      with_nolock_commands_env(dir) do
        code, out, err = run_cli(["clean", "--dry-run"])
        code.should eq(0)
        out.should eq("Resolving dependencies...\n")
        err.should eq("")
        File.exists?(File.join(dir, "Gemfile.lock")).should be_false
      end
    end
  end

  it "reports a gem that is not installed as local-only for binstubs" do
    next unless ruby_available?
    with_project(nolock_commands_gemfile(%(gem "thor", "1.3.2"))) do |dir|
      with_nolock_commands_env(dir) do
        code, _out, err = run_cli(["binstubs", "thor"])
        code.should eq(7)
        err.should eq("Could not find gem 'thor (= 1.3.2)' in locally installed gems.\n")
        File.exists?(File.join(dir, "bin", "thor")).should be_false
      end
    end
  end

  it "explains that RubyGems owns the bundler stub" do
    next unless ruby_available?
    with_project(nolock_commands_gemfile(%(gem "json_pure", "2.8.1"))) do |dir|
      with_nolock_commands_env(dir) do
        code, _out, err = run_cli(["binstubs", "bundler"])
        code.should eq(0)
        err.should contain("Bundler itself does not use binstubs because its version is selected by RubyGems")
        File.exists?(File.join(dir, "bin", "bundler")).should be_false
      end
    end
  end
end
