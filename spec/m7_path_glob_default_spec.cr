require "./spec_helper"

# Reference `Bundler::Source::Path::DEFAULT_GLOB` is `{,*,*/*}.gemspec`
# (bundler-4.0.24 source/path.rb:14). The bridge used to fall back to
# `{,*}.gemspec`, so a `vendor/<mono>/gems/<gem>.gemspec` layout was not
# discovered even though `bundle lock` finds it. A missing path gem must also
# be attributed to its path source (`Source::Path#to_s`), not to the primary
# rubygems remote.
PATH_GLOB_GEMSPEC = <<-SPEC
  Gem::Specification.new do |s|
    s.name = "mono_a"
    s.version = "0.1.0"
    s.summary = "path glob probe"
  end
  SPEC

private def with_path_bridge(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def path_mono_gemfile : String
  <<-GEMFILE
    source "https://rubygems.org"

    path "vendor/mono" do
      gem "mono_a"
    end
    GEMFILE
end

describe "M7 path source default glob" do
  it "finds a gemspec one directory below the path root" do
    with_project({
      "Gemfile"                         => path_mono_gemfile,
      "vendor/mono/gems/mono_a.gemspec" => PATH_GLOB_GEMSPEC,
    }) do |dir|
      with_path_bridge do
        code, _, stderr = run_cli(["lock"])
        code.should eq(0)
        stderr.should be_empty
      end

      text = File.read(File.join(dir, "Gemfile.lock"))
      text.should contain("PATH\n  remote: vendor/mono\n  specs:\n    mono_a (0.1.0)\n")
      text.should contain("DEPENDENCIES\n  mono_a!\n")
    end
  end

  it "attributes a too-deep path miss to the path source" do
    with_project({
      "Gemfile"                                => path_mono_gemfile,
      "vendor/mono/gems/mono_a/mono_a.gemspec" => PATH_GLOB_GEMSPEC,
    }) do |dir|
      with_path_bridge do
        code, _, stderr = run_cli(["lock"])
        code.should eq(7)
        stderr.should contain("Could not find gem 'mono_a' in source at `vendor/mono`.")
        stderr.should_not contain("in rubygems repository")
      end
      File.exists?(File.join(dir, "Gemfile.lock")).should be_false
    end
  end
end
