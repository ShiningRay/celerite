require "./spec_helper"

# task-123 — `installer.rb:73-77` (4.0.24) / `installer.rb:75` (2.7.2): when the
# Gemfile declares no dependency at all, `Installer#run` warns
# `The Gemfile specifies no dependencies` on stderr, writes the lockfile and
# returns before resolving. `install`, `update` (`cli/update.rb:81`) and `cache`
# (`cli/cache.rb:24-30`) all funnel through `Installer.install`, so all three
# used to pass silently while the reference warned. `lock` and `check` never
# reach `Installer#run` and stay silent in both implementations.
private def with_empty_gemfile_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
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

private def empty_gemfile_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def empty_gemfile_project(gemfile : String, & : String ->) : Nil
  with_project({"Gemfile" => gemfile}) do |dir|
    previous_home = ENV["HOME"]?
    previous_profile = ENV["USERPROFILE"]?
    previous_bundle_path = ENV["BUNDLE_PATH"]?
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, ".bundle-test")
    begin
      yield dir
    ensure
      previous_home ? (ENV["HOME"] = previous_home) : ENV.delete("HOME")
      previous_profile ? (ENV["USERPROFILE"] = previous_profile) : ENV.delete("USERPROFILE")
      previous_bundle_path ? (ENV["BUNDLE_PATH"] = previous_bundle_path) : ENV.delete("BUNDLE_PATH")
    end
  end
end

private NO_DEPENDENCIES = "The Gemfile specifies no dependencies\n"

# `BUNDLE_PATH` is set per project by the helper, so the reference's
# `use_system_gems?` false branch renders the relative bundle path instead of
# the `bundle info` hint (`cli/install.rb:59-64`).
private INSTALL_STDOUT = "Resolving dependencies...\n" \
                         "Bundle complete! 0 Gemfile dependencies, 0 gems now installed.\n" \
                         "Bundled gems are installed into `./.bundle-test`\n"

private UPDATE_STDERR = "[DEPRECATED] Pass --all to `bundle update` to update everything\n" +
                        NO_DEPENDENCIES

describe "M7 empty Gemfile (task-123)" do
  it "warns on stderr for install with a 0-byte Gemfile" do
    with_empty_gemfile_bridge do
      empty_gemfile_project("") do |dir|
        code, out, err = run_cli(["install"])
        code.should eq(0)
        out.should eq(INSTALL_STDOUT)
        err.should eq(NO_DEPENDENCIES)
        File.file?(File.join(dir, "Gemfile.lock")).should be_true
      end
    end
  end

  it "warns on stderr for install --local with a source-only Gemfile" do
    with_empty_gemfile_bridge do
      empty_gemfile_project("source \"#{empty_gemfile_remote}\"\n") do |_dir|
        code, out, err = run_cli(["install", "--local"])
        code.should eq(0)
        out.should eq(INSTALL_STDOUT)
        err.should eq(NO_DEPENDENCIES)
      end
    end
  end

  it "warns on stderr for install with a comment-only Gemfile" do
    with_empty_gemfile_bridge do
      empty_gemfile_project("# nothing here\n") do |_dir|
        code, out, err = run_cli(["install"])
        code.should eq(0)
        out.should eq(INSTALL_STDOUT)
        err.should eq(NO_DEPENDENCIES)
      end
    end
  end

  it "warns on stderr after the deprecation notice for a bare update" do
    with_empty_gemfile_bridge do
      empty_gemfile_project("") do |dir|
        code, out, err = run_cli(["update"])
        code.should eq(0)
        out.should eq("Resolving dependencies...\nBundle updated!\n")
        err.should eq(UPDATE_STDERR)
        File.file?(File.join(dir, "Gemfile.lock")).should be_true
      end
    end
  end

  it "warns on stderr for cache and still fills vendor/cache" do
    with_empty_gemfile_bridge do
      empty_gemfile_project("") do |dir|
        code, out, err = run_cli(["cache"])
        code.should eq(0)
        out.should eq(INSTALL_STDOUT + "Updating files in vendor/cache\n")
        err.should eq(NO_DEPENDENCIES)
        File.directory?(File.join(dir, "vendor", "cache")).should be_true
      end
    end
  end

  it "keeps lock and check silent because neither calls Installer#run" do
    with_empty_gemfile_bridge do
      # Two separate projects: `check` prints `Resolving dependencies...` only
      # while there is no lockfile, and a preceding `lock` would hide that line.
      empty_gemfile_project("") do |_dir|
        code, out, err = run_cli(["lock"])
        code.should eq(0)
        # The lock path is rendered with forward slashes on every platform.
        lock_path = File.join(Dir.current, "Gemfile.lock").gsub('\\', "/")
        out.should eq("Writing lockfile to #{lock_path}\nResolving dependencies...\n")
        err.should eq("")
      end

      empty_gemfile_project("") do |_dir|
        code, out, err = run_cli(["check"])
        code.should eq(0)
        out.should eq("Resolving dependencies...\nThe Gemfile's dependencies are satisfied\n")
        err.should eq("")
      end
    end
  end

  it "stays silent when the Gemfile does declare a dependency" do
    with_empty_gemfile_bridge do
      empty_gemfile_project("source \"#{empty_gemfile_remote}\"\n\ngem \"json_pure\", \"2.6.0\"\n") do |_dir|
        # Served from the local `fixtures/gem-index` and installed into the
        # project-local `BUNDLE_PATH`, so the run stays offline.
        code, _out, err = run_cli(["install"])
        code.should eq(0)
        err.should eq("")
      end
    end
  end
end
