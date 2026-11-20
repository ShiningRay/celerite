require "./spec_helper"
require "../src/celerite/cli/commands"

# M7 task-67: `check` must follow the reference when the Gemfile gained a
# dependency the lockfile does not cover yet.
#
# Reference: `Bundler::Definition#check!` (definition.rb:172-182) resolves
# remotely when `@dependency_changes` is set, `missing_specs`
# (definition.rb:261-264) then reports what that resolution needs but the bundle
# lacks, and `Bundler::CLI::Check` (cli/check.rb:19-31) prints the three
# missing-gem lines and exits 1 *before* the `definition.lock(true)` call, so the
# lockfile keeps its old contents. `--dry-run` skips only that write, so the
# failure output is identical.
private def check_missing_dependency_files(name : String) : Hash(String, String)
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  files = {} of String => String
  {% for file in %w[Gemfile Gemfile.lock] %}
    path = File.join(dir, {{file}})
    if File.file?(path)
      files[{{file}}] = File.read(path).gsub("@INDEX_DIR@", index)
    end
  {% end %}
  files
end

private def with_check_missing_dependency_env(name : String, files : Hash(String, String)? = nil,
                                              & : String ->) : Nil
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  with_project(files || check_missing_dependency_files(name)) do |project|
    FileUtils.cp_r(File.join(dir, "bundle-preset"), File.join(project, "bundle"))
    names = %w[HOME USERPROFILE BUNDLE_PATH CELERITE_BRIDGE_SERVER CELERITE_PROFILE_BUNDLER_VERSION]
    previous = {} of String => String?
    names.each { |n| previous[n] = ENV[n]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
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

private CHECK_MISSING_THREE_LINES = "The following gems are missing\n * thor (1.3.2)\n" +
                                    "Install missing gems with `bundle install`\n"

describe "M7 task-67 check with an unlocked Gemfile dependency" do
  it "resolves the new dependency and reports it missing without writing the lock" do
    with_check_missing_dependency_env("check-gemfile-new-dependency") do |_|
      before = File.read("Gemfile.lock")
      code, out, err = run_cli(["check"])
      code.should eq(1), "stdout=#{out}\nstderr=#{err}"
      out.should contain("Fetching source index from")
      out.should contain("Resolving dependencies...")
      err.should eq(CHECK_MISSING_THREE_LINES)
      File.read("Gemfile.lock").should eq(before)
      File.read("Gemfile.lock").should_not contain("thor")
    end
  end

  it "reports the same three lines under --dry-run and keeps the lock" do
    with_check_missing_dependency_env("check-gemfile-new-dependency") do |_|
      before = File.read("Gemfile.lock")
      code, out, err = run_cli(["check", "--dry-run"])
      code.should eq(1), "stdout=#{out}\nstderr=#{err}"
      out.should contain("Fetching source index from")
      err.should eq(CHECK_MISSING_THREE_LINES)
      File.read("Gemfile.lock").should eq(before)
    end
  end

  it "stays satisfied when every Gemfile dependency is locked and installed" do
    files = check_missing_dependency_files("check-gemfile-new-dependency")
    files["Gemfile"] = files["Gemfile"].sub("gem \"thor\"\n", "")
    with_check_missing_dependency_env("check-gemfile-new-dependency", files) do |_|
      code, out, err = run_cli(["check"])
      code.should eq(0), "stdout=#{out}\nstderr=#{err}"
      err.should eq("")
      out.should contain("The Gemfile's dependencies are satisfied")
      out.should_not contain("Resolving dependencies...")
      lock = File.read("Gemfile.lock")
      lock.should contain("json_pure (2.6.0)")
      lock.should_not contain("thor")
    end
  end
end
