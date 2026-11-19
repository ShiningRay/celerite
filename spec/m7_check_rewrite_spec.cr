require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(8): `check` persists the lockfile on success (unless `--dry-run`) and maps
# resolver/git failures to the reference "can't satisfy" pair.
private def check_rewrite_files(name : String) : Hash(String, String)
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  remote = "file:///#{index}"
  files = {} of String => String
  {% for file in %w[Gemfile Gemfile.lock] %}
    path = File.join(dir, {{file}})
    if File.file?(path)
      files[{{file}}] = File.read(path).gsub("@INDEX_DIR@", index)
    end
  {% end %}
  files
end

private def with_check_rewrite_env(name : String, & : String ->) : Nil
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  with_project(check_rewrite_files(name)) do |project|
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

describe "M7(8) check lock persistence" do
  it "rewrites a satisfied lock (platform + BUNDLED WITH) unless dry-run" do
    with_check_rewrite_env("check-rewrites-lock") do |_|
      code, out, err = run_cli(["check"])
      code.should eq(0), "stderr=#{err}\nstdout=#{out}"
      err.should eq("")
      out.should contain("The Gemfile's dependencies are satisfied")
      lock = File.read("Gemfile.lock")
      lock.should contain("  java\n  x64-mingw-ucrt\n")
      lock.should contain("BUNDLED WITH\n  4.0.24\n")
      lock.should_not contain("4.0.20")
    end
  end

  it "leaves the lock untouched with --dry-run" do
    with_check_rewrite_env("check-dry-run-keeps-lock") do |_|
      before = File.read("Gemfile.lock")
      code, out, err = run_cli(["check", "--dry-run"])
      code.should eq(0)
      err.should eq("")
      out.should contain("The Gemfile's dependencies are satisfied")
      File.read("Gemfile.lock").should eq(before)
      File.read("Gemfile.lock").should contain("4.0.20")
    end
  end

  it "reports the reference satisfied pair when resolution fails" do
    with_check_rewrite_env("check-triplet-missing-index") do |_|
      code, out, err = run_cli(["check"])
      code.should eq(1)
      out.should contain("Fetching source index from")
      err.should eq("Bundler can't satisfy your Gemfile's dependencies.\nInstall missing gems with `bundle install`.\n")
      File.exists?("Gemfile.lock").should be_false
    end
  end
end
