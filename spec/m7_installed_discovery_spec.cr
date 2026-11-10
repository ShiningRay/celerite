require "./spec_helper"

# M7(2): installed-gem discovery must not report locked gems as missing when
# their extracted contents exist (RubyGems layouts may omit the installed
# .gemspec), and must still resolve PATH and GIT sources.
#
# These specs call command entry points directly (Celerite::Commands.check /
# list / show_info) instead of Celerite::CLI.run. The CLI dispatch pulls in the
# install/downloader chain, which links OpenSSL; the local MSYS2 toolchain ships
# OpenSSL 3.x without the legacy `EVP_MD_size` symbol this Crystal version
# binds, so run_cli-based specs cannot link here. Calling the module methods
# under test keeps the evidence runnable and exercises the same code paths.
LOCKFILE_TEXT = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:
    json_pure (2.8.1)

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  json_pure

BUNDLED WITH
   4.0.24
LOCK

PATH_LOCKFILE_TEXT = <<-LOCK
PATH
  remote: vendor/local
  specs:
    localgem (0.1.0)

GEM
  remote: https://rubygems.org/
  specs:

PLATFORMS
  ruby

DEPENDENCIES
  localgem!

BUNDLED WITH
   4.0.24
LOCK

GIT_LOCKFILE_TEXT = <<-LOCK
GIT
  remote: https://example.com/example.git
  revision: abcdef1234567890abcdef1234567890abcdef12
  specs:
    example (0.1.0)

GEM
  remote: https://rubygems.org/
  specs:

PLATFORMS
  ruby

DEPENDENCIES
  example!

BUNDLED WITH
   4.0.24
LOCK

def capture_command(&block : (IO, IO) -> Int32) : {Int32, String, String}
  output_io = IO::Memory.new
  error_io = IO::Memory.new
  code = yield output_io, error_io
  {code, output_io.to_s, error_io.to_s}
end

private def project_files(lockfile : String, extra : Hash(String, String) = {} of String => String) : Hash(String, String)
  files = {
    "Gemfile"        => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
    "Gemfile.lock"   => lockfile,
    ".bundle/config" => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
  }
  files.merge(extra)
end

private def project_files_for(lockfile : String, gemfile : String, extra : Hash(String, String) = {} of String => String) : Hash(String, String)
  files = {
    "Gemfile"        => gemfile,
    "Gemfile.lock"   => lockfile,
    ".bundle/config" => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
  }
  files.merge(extra)
end

describe "M7 installed gem discovery" do
  it "check treats a gem dir without a specifications file as installed" do
    with_project(project_files(LOCKFILE_TEXT, {
      "vendor/bundle/ruby/3.4.0/gems/json_pure-2.8.1/lib/json_pure.rb" => "",
    })) do
      code, out, err = capture_command { |o, e| Celerite::Commands.check(o, e, [] of String) }
      err.should eq("")
      out.should eq("The Gemfile's dependencies are satisfied\n")
      code.should eq(0)
    end
  end

  it "list shows a gem whose dir exists without a specifications file" do
    with_project(project_files(LOCKFILE_TEXT, {
      "vendor/bundle/ruby/3.4.0/gems/json_pure-2.8.1/lib/json_pure.rb" => "",
    })) do
      code, out, err = capture_command { |o, e| Celerite::Commands.list(o, e, [] of String) }
      err.should eq("")
      out.should contain("json_pure-2.8.1")
      code.should eq(0)
    end
  end

  it "show treats a gem dir without a specifications file as installed" do
    with_project(project_files(LOCKFILE_TEXT, {
      "vendor/bundle/ruby/3.4.0/gems/json_pure-2.8.1/lib/json_pure.rb" => "",
    })) do
      code, out, err = capture_command { |o, e| Celerite::Commands.show_info("show", o, e, ["json_pure"]) }
      code.should eq(0)
      err.should eq("")
      out.should contain("json_pure-2.8.1")
    end
  end

  it "show --paths resolves a gem dir without a specifications file" do
    with_project(project_files(LOCKFILE_TEXT, {
      "vendor/bundle/ruby/3.4.0/gems/json_pure-2.8.1/lib/json_pure.rb" => "",
    })) do
      code, out, err = capture_command { |o, e| Celerite::Commands.show_info("show", o, e, ["--paths", "json_pure"]) }
      code.should eq(0)
      err.should eq("")
      out.should contain("json_pure-2.8.1")
    end
  end

  it "check still reports a missing gem when neither dir nor specification exists" do
    with_project(project_files(LOCKFILE_TEXT)) do
      code, out, err = capture_command { |o, e| Celerite::Commands.check(o, e, [] of String) }
      code.should eq(1)
      err.should contain("The following gems are missing")
      err.should contain("json_pure (2.8.1)")
      out.should eq("")
    end
  end

  it "check still reports a missing gem when only the specification file exists" do
    with_project(project_files(LOCKFILE_TEXT, {
      "vendor/bundle/ruby/3.4.0/specifications/json_pure-2.8.1.gemspec" => "Gem::Specification.new\n",
    })) do
      code, _out, err = capture_command { |o, e| Celerite::Commands.check(o, e, [] of String) }
      code.should eq(1)
      err.should contain("json_pure (2.8.1)")
    end
  end

  it "resolves a PATH source relative to the Gemfile" do
    with_project(project_files_for(PATH_LOCKFILE_TEXT, "gem \"localgem\", path: \"vendor/local\"\n", {
      "vendor/local/localgem.gemspec" => "Gem::Specification.new\n",
    })) do
      definition = Celerite::Definition.build
      lockfile = definition.lockfile!
      spec = lockfile.specs.find(&.name.==("localgem")).not_nil!
      gem_dir = Celerite::Commands.installed_gem_dir(definition, spec, lockfile)
      gem_dir.should_not be_nil
      gem_dir.not_nil!.gsub('\\', '/').should end_with("/vendor/local")
      Celerite::Commands.installed_spec_dir?(definition, spec, lockfile).should be_true
    end
  end

  it "resolves a GIT source from the bundler/gems checkout" do
    with_project(project_files_for(GIT_LOCKFILE_TEXT, "gem \"example\", git: \"https://example.com/example.git\"\n", {
      "vendor/bundle/ruby/3.4.0/bundler/gems/example-abcdef123456/example.gemspec" => "Gem::Specification.new\n",
    })) do
      definition = Celerite::Definition.build
      lockfile = definition.lockfile!
      spec = lockfile.specs.find(&.name.==("example")).not_nil!
      gem_dir = Celerite::Commands.installed_gem_dir(definition, spec, lockfile)
      gem_dir.should_not be_nil
      gem_dir.not_nil!.gsub('\\', '/').should end_with("/bundler/gems/example-abcdef123456")
      Celerite::Commands.installed_spec_dir?(definition, spec, lockfile).should be_true
    end
  end

  it "returns nil for a GIT source without a checkout" do
    with_project(project_files_for(GIT_LOCKFILE_TEXT, "gem \"example\", git: \"https://example.com/example.git\"\n")) do
      definition = Celerite::Definition.build
      lockfile = definition.lockfile!
      spec = lockfile.specs.find(&.name.==("example")).not_nil!
      Celerite::Commands.installed_gem_dir(definition, spec, lockfile).should be_nil
      Celerite::Commands.installed_spec_dir?(definition, spec, lockfile).should be_false
    end
  end
end
