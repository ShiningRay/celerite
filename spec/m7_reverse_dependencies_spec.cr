require "./spec_helper"

# M7(2): reverse dependencies in `info` output and path-source gemspec metadata
# fallback. These call Celerite::Commands.show_info directly (no CLI/install
# link chain; see spec/m7_installed_discovery_spec.cr header note).
REVERSE_DEP_LOCKFILE = <<-LOCK
PATH
  remote: vendor/depender
  specs:
    depender (1.0.0)
      dependee (>= 1.0)

PATH
  remote: vendor/dependee
  specs:
    dependee (1.0.0)

GEM
  remote: https://rubygems.org/
  specs:

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  depender!
  dependee!

BUNDLED WITH
   4.0.24
LOCK

REVERSE_DEP_GEMFILE = <<-GEMFILE
source "https://rubygems.org"

gem "depender", path: "vendor/depender"
gem "dependee", path: "vendor/dependee"
GEMFILE

PATH_GROUP_LOCKFILE = <<-LOCK
PATH
  remote: vendor/default_gem
  specs:
    default_gem (1.0.0)

PATH
  remote: vendor/test_gem
  specs:
    test_gem (1.0.0)

GEM
  remote: https://rubygems.org/
  specs:

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  default_gem!
  test_gem!

BUNDLED WITH
   4.0.24
LOCK

PATH_GROUP_GEMFILE = <<-GEMFILE
source "https://rubygems.org"

gem "default_gem", path: "vendor/default_gem"
gem "test_gem", path: "vendor/test_gem", group: :test
GEMFILE

private def with_bridge_server(&)
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

describe "M7(2) reverse dependencies and path-source discovery" do
  it "info shows reverse dependencies and reads summary from a path-source gemspec" do
    with_project({
      "Gemfile"                          => REVERSE_DEP_GEMFILE,
      "Gemfile.lock"                     => REVERSE_DEP_LOCKFILE,
      "vendor/depender/depender.gemspec" => "Gem::Specification.new do |s|\n  s.name = \"depender\"\n  s.version = \"1.0.0\"\n  s.summary = \"Depender fixture\"\n  s.authors = [\"x\"]\n  s.files = []\n  s.add_dependency \"dependee\", \">= 1.0\"\nend\n",
      "vendor/depender/lib/depender.rb"  => "module Depender; end\n",
      "vendor/dependee/dependee.gemspec" => "Gem::Specification.new do |s|\n  s.name = \"dependee\"\n  s.version = \"1.0.0\"\n  s.summary = \"Dependee fixture\"\n  s.authors = [\"x\"]\n  s.files = []\nend\n",
      "vendor/dependee/lib/dependee.rb"  => "module Dependee; end\n",
    }) do
      code, out, err = capture_command { |o, e| Celerite::Commands.show_info("info", o, e, ["dependee"]) }
      code.should eq(0)
      err.should eq("")
      out.should contain("  * dependee (1.0.0)")
      out.should contain("\tSummary: Dependee fixture")
      out.should contain("\tPath: ")
      out.should contain("vendor/dependee")
      out.should contain("\tReverse Dependencies: ")
      out.should contain("\t\tdepender (1.0.0) depends on dependee (>= 1.0)")
    end
  end

  it "info shows no reverse dependencies section for a leaf gem" do
    with_project({
      "Gemfile"                          => REVERSE_DEP_GEMFILE,
      "Gemfile.lock"                     => REVERSE_DEP_LOCKFILE,
      "vendor/depender/depender.gemspec" => "Gem::Specification.new do |s|\n  s.name = \"depender\"\n  s.version = \"1.0.0\"\n  s.summary = \"Depender fixture\"\n  s.authors = [\"x\"]\n  s.files = []\n  s.add_dependency \"dependee\", \">= 1.0\"\nend\n",
      "vendor/depender/lib/depender.rb"  => "module Depender; end\n",
      "vendor/dependee/dependee.gemspec" => "Gem::Specification.new do |s|\n  s.name = \"dependee\"\n  s.version = \"1.0.0\"\n  s.summary = \"Dependee fixture\"\n  s.authors = [\"x\"]\n  s.files = []\nend\n",
      "vendor/dependee/lib/dependee.rb"  => "module Dependee; end\n",
    }) do
      code, out, err = capture_command { |o, e| Celerite::Commands.show_info("info", o, e, ["depender"]) }
      code.should eq(0)
      err.should eq("")
      out.should contain("  * depender (1.0.0)")
      out.should contain("\tSummary: Depender fixture")
      out.should_not contain("Reverse Dependencies:")
    end
  end

  it "check --without-group ignores a missing path gem in the excluded group" do
    with_bridge_server do
      with_project({
        "Gemfile"                                => PATH_GROUP_GEMFILE,
        "Gemfile.lock"                           => PATH_GROUP_LOCKFILE,
        "vendor/default_gem/default_gem.gemspec" => "Gem::Specification.new do |s|\n  s.name = \"default_gem\"\n  s.version = \"1.0.0\"\n  s.summary = \"default\"\n  s.authors = [\"x\"]\n  s.files = []\nend\n",
        "vendor/default_gem/lib/default_gem.rb"  => "module DefaultGem; end\n",
      }) do
        code, out, err = capture_command { |o, e| Celerite::Commands.check(o, e, ["--without-group", "test"]) }
        err.should eq("")
        out.should eq("The Gemfile's dependencies are satisfied\n")
        code.should eq(0)
      end
    end
  end

  it "list --without-group lists only the path gem in included groups" do
    with_bridge_server do
      with_project({
        "Gemfile"                                => PATH_GROUP_GEMFILE,
        "Gemfile.lock"                           => PATH_GROUP_LOCKFILE,
        "vendor/default_gem/default_gem.gemspec" => "Gem::Specification.new do |s|\n  s.name = \"default_gem\"\n  s.version = \"1.0.0\"\n  s.summary = \"default\"\n  s.authors = [\"x\"]\n  s.files = []\nend\n",
        "vendor/default_gem/lib/default_gem.rb"  => "module DefaultGem; end\n",
        "vendor/test_gem/test_gem.gemspec"       => "Gem::Specification.new do |s|\n  s.name = \"test_gem\"\n  s.version = \"1.0.0\"\n  s.summary = \"test\"\n  s.authors = [\"x\"]\n  s.files = []\nend\n",
        "vendor/test_gem/lib/test_gem.rb"        => "module TestGem; end\n",
      }) do
        code, out, err = capture_command { |o, e| Celerite::Commands.list(o, e, ["--without-group", "test"]) }
        err.should eq("")
        out.should eq("Gems included by the bundle:\n  * default_gem (1.0.0)\nUse `bundle info` to print more detailed information about a gem\n")
        code.should eq(0)
      end
    end
  end
end

private def capture_command(&block : (IO, IO) -> Int32) : {Int32, String, String}
  output_io = IO::Memory.new
  error_io = IO::Memory.new
  code = yield output_io, error_io
  {code, output_io.to_s, error_io.to_s}
end
