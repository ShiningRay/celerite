require "./spec_helper"
require "../src/celerite"

# `check` rewrites the lockfile in place when the only change is the local
# platform (`definition.rb:401-418` → `LockfileGenerator.generate`). The
# reference regenerates every section from the *locked source objects*
# (`source/path.rb:41-43,45-50`, `source/git.rb:39-48`, `lockfile_generator.rb:31-42`),
# so a `PATH`/`GIT`/`PLUGIN SOURCE` section survives the rewrite verbatim, and a
# rubygems source with no remote renders `GEM\n  specs:\n` without a `remote:`
# line (`source/rubygems.rb:114-120`). These examples pin those two shapes on
# the reuse path (`Resolution#lockfile_rewrite_text`), which never resolves.
private def path_source_project(glob : Bool) : Hash(String, String)
  gemfile = String.build do |io|
    io << "path \"vendor/d\""
    io << ", glob: \"gems/*/*.gemspec\"" if glob
    io << " do\n  gem \"dgem\"\nend\n"
  end
  lock = "PATH\n  remote: vendor/d\n"
  lock += "  glob: gems/*/*.gemspec\n" if glob
  lock += "  specs:\n    dgem (2.0.0)\n\nGEM\n  specs:\n\nPLATFORMS\n  java\n\nDEPENDENCIES\n  dgem!\n\nBUNDLED WITH\n  4.0.24\n"
  {
    "Gemfile"                      => gemfile,
    "Gemfile.lock"                 => lock,
    "vendor/d/dgem.gemspec"        => path_gemspec("dgem", "1.0.0"),
    "vendor/d/lib/dgem.rb"         => "module DGem\n  VERSION = \"1.0.0\"\nend\n",
    "vendor/d/gems/x/dgem.gemspec" => path_gemspec("dgem", "2.0.0"),
  }
end

private def path_gemspec(name : String, version : String) : String
  String.build do |io|
    io << "Gem::Specification.new do |s|\n"
    io << "  s.name = \"" << name << "\"\n"
    io << "  s.version = \"" << version << "\"\n"
    io << "  s.summary = \"path gem\"\n"
    io << "  s.authors = [\"Celerite\"]\n"
    io << "  s.files = []\n"
    io << "end\n"
  end
end

describe "lockfile rewrite fidelity" do
  it "keeps the PATH section and its glob instead of re-emitting it as GEM" do
    pending! "ruby not available" unless ruby_available?
    with_client do |client|
      with_project(path_source_project(glob: true)) do |_dir|
        resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
        resolution.progress = IO::Memory.new
        text = resolution.lockfile_rewrite_text
        text.should contain("PATH\n  remote: vendor/d\n  glob: gems/*/*.gemspec\n  specs:\n    dgem (2.0.0)\n")
        text.should_not contain("GEM\n  remote: https://rubygems.org/")
      end
    end
  end

  it "writes a GEM section without a remote line when no source is declared" do
    pending! "ruby not available" unless ruby_available?
    lock = "PATH\n  remote: vendor/k\n  specs:\n    kgem (1.0.0)\n\nGEM\n  specs:\n\nPLATFORMS\n  java\n\nDEPENDENCIES\n  kgem!\n\nBUNDLED WITH\n  4.0.24\n"
    files = {
      "Gemfile"               => "gem \"kgem\", path: \"vendor/k\"\n",
      "Gemfile.lock"          => lock,
      "vendor/k/kgem.gemspec" => path_gemspec("kgem", "1.0.0"),
      "vendor/k/lib/kgem.rb"  => "module KGem\n  VERSION = \"1.0.0\"\nend\n",
    }
    with_client do |client|
      with_project(files) do |_dir|
        resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
        resolution.progress = IO::Memory.new
        text = resolution.lockfile_rewrite_text
        text.should contain("\nGEM\n  specs:\n")
        text.should_not contain("remote: https://rubygems.org/")
      end
    end
  end
end
