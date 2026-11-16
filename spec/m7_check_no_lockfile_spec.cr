require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(1): `check` resolves the Gemfile when the project has no lockfile yet.
#
# Reference: `bundler/cli/check.rb` builds the definition (which resolves and
# prints the fetch/resolve progress), reports the missing gems, and only writes
# the lockfile when every dependency is installed and `--dry-run` is absent.
private def check_nolock_gemfile : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  remote = file_source_url(index)
  gemfile = <<-GEMFILE
    source "#{remote}"

    gem "json_pure", "2.8.1"
    GEMFILE
  {"Gemfile" => gemfile}
end

# Seeds a fake `json_pure 2.8.1` installation the gem resolver can discover
# through GEM_HOME/GEM_PATH, so the satisfied branch is reachable offline.
private def seed_check_nolock_gem(gems_dir : String) : Nil
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

private def with_check_nolock_env(dir : String, install : Bool, & : String ->) : Nil
  gems = File.join(dir, "gems")
  seed_check_nolock_gem(gems) if install
  Dir.mkdir_p(gems)
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

describe "M7(1) check without a lockfile" do
  it "resolves, reports the missing gems and leaves the lockfile alone" do
    next unless ruby_available?
    with_project(check_nolock_gemfile) do |dir|
      with_check_nolock_env(dir, install: false) do
        code, out, err = run_cli(["check"])
        code.should eq(1)
        out.should contain("Resolving dependencies...")
        err.should contain("The following gems are missing")
        err.should contain(" * json_pure (2.8.1)")
        err.should contain("Install missing gems with `bundle install`")
        File.exists?(File.join(dir, "Gemfile.lock")).should be_false
      end
    end
  end

  it "writes the resolved lockfile when the dependencies are installed" do
    next unless ruby_available?
    with_project(check_nolock_gemfile) do |dir|
      with_check_nolock_env(dir, install: true) do
        code, out, err = run_cli(["check"])
        code.should eq(0)
        out.should contain("Resolving dependencies...")
        out.should contain("The Gemfile's dependencies are satisfied")
        err.should eq("")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("json_pure (2.8.1)")
        lock.should contain("BUNDLED WITH")
      end
    end
  end

  it "honors --dry-run and does not write the lockfile" do
    next unless ruby_available?
    with_project(check_nolock_gemfile) do |dir|
      with_check_nolock_env(dir, install: true) do
        code, out, _err = run_cli(["check", "--dry-run"])
        code.should eq(0)
        out.should contain("The Gemfile's dependencies are satisfied")
        File.exists?(File.join(dir, "Gemfile.lock")).should be_false
      end
    end
  end
end
