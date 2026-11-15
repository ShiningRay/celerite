require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(1): `check` mirrors the reference's re-resolve notice
# ("Resolving dependencies...") when the Gemfile declares `ruby` but the
# lockfile has no RUBY VERSION section, and it must do so in the satisfied
# case too (the existing `check-missing-ruby-nolock` differential fixture only
# covers the missing-dependency path).
#
# Reference: `bundler/cli/check.rb` (always builds the definition, which
# resolves) + `Bundler::Definition#@unlocking_ruby`
# (`definition.rb` `(!@locked_ruby_version ^ !@ruby_version)`).
private def check_notice_ruby_version : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print RUBY_VERSION"], output: output)
  output.to_s
end

private def check_notice_ruby_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

# Pretends json_pure was installed into `<project>/.bundle` (the bundle path
# this example exports) so `check` reports satisfied dependencies without
# touching the network.
private def seed_installed_json_pure(dir : String) : Nil
  ruby_root = File.join(dir, ".bundle", "ruby", check_notice_ruby_abi)
  spec_dir = File.join(ruby_root, "specifications")
  gem_dir = File.join(ruby_root, "gems", "json_pure-2.8.1")
  Dir.mkdir_p(spec_dir)
  Dir.mkdir_p(File.join(gem_dir, "lib"))
  File.write(File.join(spec_dir, "json_pure-2.8.1.gemspec"), <<-RUBY)
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
  File.write(File.join(gem_dir, "lib", "celerite_fixture.rb"), "# stub\n")
end

private def check_notice_files : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  remote = file_source_url(index)
  gemfile = <<-GEMFILE
    source "#{remote}"

    ruby "#{check_notice_ruby_version}"

    gem "json_pure"
    GEMFILE
  lockfile = <<-LOCK
    GEM
      remote: #{remote}/
      specs:
        json_pure (2.8.1)

    PLATFORMS
      ruby

    DEPENDENCIES
      json_pure

    BUNDLED WITH
       4.0.24
    LOCK
  {"Gemfile" => gemfile, "Gemfile.lock" => lockfile}
end

private def with_check_notice_env(dir : String, bridge : Bool, &)
  previous = {} of String => String?
  previous["BUNDLE_PATH"] = ENV["BUNDLE_PATH"]?
  previous["CELERITE_BRIDGE_SERVER"] = ENV["CELERITE_BRIDGE_SERVER"]?
  previous["CELERITE_REFERENCE_BUNDLER_LIB"] = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
  ENV["BUNDLE_PATH"] = File.join(dir, ".bundle")
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  if bridge
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  else
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end
  begin
    yield
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

describe "M7(1) check ruby re-resolve notice" do
  it "announces the re-resolution when the lockfile has no RUBY VERSION and dependencies are satisfied" do
    next unless ruby_available?
    with_project(check_notice_files) do |dir|
      seed_installed_json_pure(dir)
      with_check_notice_env(dir, bridge: true) do
        code, out, err = run_cli(["check"])
        code.should eq(0)
        out.should eq("Resolving dependencies...\nThe Gemfile's dependencies are satisfied\n")
        err.should eq("")
      end
    end
  end

  it "omits the notice when the bridge is unavailable (documented best-effort fallback)" do
    next unless ruby_available?
    with_project(check_notice_files) do |dir|
      seed_installed_json_pure(dir)
      with_check_notice_env(dir, bridge: false) do
        code, out, err = run_cli(["check"])
        code.should eq(0)
        out.should eq("The Gemfile's dependencies are satisfied\n")
        err.should eq("")
      end
    end
  end
end
