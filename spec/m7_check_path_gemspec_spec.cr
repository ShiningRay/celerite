require "./spec_helper"
require "../src/celerite/cli/commands"

# M7 task-102: `check` must heal a `PATH` section whose gemspecs drifted.
#
# Reference: `definition.rb:172-182` materializes the locked definition against
# local sources after the Gemfile comparison, so a `PATH` block with no spec row
# (or a stale version) heals on `check`, announces `Resolving dependencies...`,
# and `cli/check.rb:33` writes the refreshed lock unless `--dry-run`.
private def check_path_index : String
  File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
end

private def check_path_gemspec(version : String) : String
  <<-SPEC
  Gem::Specification.new do |s|
    s.name = "pg"
    s.version = "#{version}"
    s.summary = "path gem"
    s.authors = ["a"]
    s.files = ["lib/pg.rb"]
  end
  SPEC
end

private def check_path_files(version : String, lock_version : String?) : Hash(String, String)
  specs = lock_version ? "    pg (#{lock_version})\n" : ""
  files = {
    "Gemfile"      => %(source "file:///#{check_path_index}"\n\ngem "pg", path: "./pg"\n),
    "Gemfile.lock" => %(PATH\n  remote: pg\n  specs:\n#{specs}\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  pg!\n\nBUNDLED WITH\n   4.0.24\n),
    "pg/pg.gemspec"  => check_path_gemspec(version),
    "pg/lib/pg.rb"   => "module Pg; end\n",
  }
  files
end

private def with_check_path_env(files : Hash(String, String), & : String ->) : Nil
  with_project(files) do |project|
    names = %w[HOME USERPROFILE BUNDLE_PATH CELERITE_BRIDGE_SERVER CELERITE_PROFILE_BUNDLER_VERSION]
    previous = {} of String => String?
    names.each { |n| previous[n] = ENV[n]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
    begin
      yield project
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
end

describe "check with a drifted PATH section" do
  it "heals a missing spec row and announces the resolve" do
    with_check_path_env(check_path_files("1.0.0", nil)) do |project|
      code, out, err = run_cli(["check"])
      code.should eq(0)
      out.should eq("Resolving dependencies...\nThe Gemfile's dependencies are satisfied\n")
      err.should eq("")
      File.read(File.join(project, "Gemfile.lock")).should contain("    pg (1.0.0)")
    end
  end

  it "heals a stale locked version from the gemspec" do
    with_check_path_env(check_path_files("2.0.0", "1.0.0")) do |project|
      code, out, _err = run_cli(["check"])
      code.should eq(0)
      out.should contain("Resolving dependencies...")
      lock = File.read(File.join(project, "Gemfile.lock"))
      lock.should contain("    pg (2.0.0)")
      lock.should_not contain("    pg (1.0.0)")
    end
  end

  it "keeps the lock untouched under --dry-run" do
    with_check_path_env(check_path_files("1.0.0", nil)) do |project|
      before = File.read(File.join(project, "Gemfile.lock"))
      code, out, _err = run_cli(["check", "--dry-run"])
      code.should eq(0)
      out.should eq("Resolving dependencies...\nThe Gemfile's dependencies are satisfied\n")
      File.read(File.join(project, "Gemfile.lock")).should eq(before)
    end
  end

end
