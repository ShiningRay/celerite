require "./spec_helper"

# M7(6) S1: a typed custom source (`source "...", type: :mpath`) must be
# evaluated through the bridge, resolved from the plugin's own `specs`
# (`Bundler::Plugin::API::Source#specs`), and written as a `PLUGIN SOURCE`
# section whose spec list is not empty (plugin/api/source.rb:41,136,283).

private def typed_source_fixture_root : String
  File.expand_path("../fixtures/differential/plugin-source-typed", __DIR__)
end

private def collect_typed_source_files(dir : String, prefix : String, files : Hash(String, String))
  Dir.children(dir).each do |child|
    path = File.join(dir, child)
    relative = prefix.empty? ? child : "#{prefix}/#{child}"
    if File.directory?(path)
      collect_typed_source_files(path, relative, files)
    else
      files[relative] = File.read(path)
    end
  end
end

private def typed_source_files : Hash(String, String)
  root = typed_source_fixture_root
  index_remote = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
  files = {} of String => String
  collect_typed_source_files(File.join(root, "extra"), "", files)
  files["Gemfile"] = File.read(File.join(root, "Gemfile")).gsub("@INDEX_DIR@", index_remote)
  files
end

private def with_typed_source_env(project : String, &)
  previous_home = ENV["HOME"]?
  previous_profile = ENV["USERPROFILE"]?
  previous_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous_home
      ENV["HOME"] = previous_home
    else
      ENV.delete("HOME")
    end
    if previous_profile
      ENV["USERPROFILE"] = previous_profile
    else
      ENV.delete("USERPROFILE")
    end
    if previous_bridge
      ENV["CELERITE_BRIDGE_SERVER"] = previous_bridge
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

describe "M7(6) typed plugin source lock" do
  it "resolves the plugin source specs and writes a complete PLUGIN SOURCE section" do
    with_project(typed_source_files) do |project|
      with_typed_source_env(project) do
        code, stdout, stderr = run_cli(["lock"])

        code.should eq(0), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
        stderr.should eq("")
        stdout.should contain("Resolving dependencies...")
        stdout.should contain("Writing lockfile to")

        lock = File.read(File.join(project, "Gemfile.lock"))
        lock.should contain("PLUGIN SOURCE\n  remote: ./stub-path-gem\n  type: mpath\n  specs:\n    stub-gem (1.0.0)\n")
        lock.should contain("DEPENDENCIES\n  stub-gem!\n")
        lock.should contain("    stub-gem (1.0.0)\n")
      end
    end
  end
end

# M7(6) S2: an existing `PLUGIN SOURCE` lock must be reused through the
# plugin's specs (no re-resolution as a normal gem, no dropped section), and a
# missing plugin must fail while the lock is evaluated, matching
# `Bundler::Plugin::UnloadedSource` (`plugin.rb:202-211`).
private def locked_typed_source_files(include_plugin : Bool, version : String) : Hash(String, String)
  root = File.expand_path("../fixtures/differential/plugin-source-locked", __DIR__)
  index_remote = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
  files = typed_source_files
  files.delete("Gemfile")
  files["Gemfile"] = File.read(File.join(root, "Gemfile")).gsub("@INDEX_DIR@", index_remote)
  lock = File.read(File.join(root, "Gemfile.lock"))
    .gsub("file:///@INDEX_DIR@/", "#{index_remote}/")
    .gsub("@BUNDLER_VERSION@", version)
  files["Gemfile.lock"] = lock
  unless include_plugin
    files.each_key.select(&.starts_with?(".bundle/")).each { |key| files.delete(key) }
  end
  files
end

describe "M7(6) locked plugin source" do
  it "reuses the PLUGIN SOURCE section without resolving again" do
    with_project(locked_typed_source_files(true, "4.0.24")) do |project|
      with_typed_source_env(project) do
        code, stdout, stderr = run_cli(["lock"])

        code.should eq(0), "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
        stderr.should eq("")
        stdout.should contain("Writing lockfile to")
        stdout.should_not contain("Resolving dependencies...")
        stdout.should_not contain("Fetching")

        lock = File.read(File.join(project, "Gemfile.lock"))
        lock.should contain("PLUGIN SOURCE\n  remote: ./stub-path-gem\n  type: mpath\n  specs:\n    stub-gem (1.0.0)\n")
        lock.should contain("DEPENDENCIES\n  stub-gem!\n")
        lock.should contain("bundler (4.0.24) sha256=")
      end
    end
  end

  it "raises the reference Gemfile error when the plugin is not installed" do
    with_project(locked_typed_source_files(false, "4.0.24")) do |project|
      with_typed_source_env(project) do
        before = File.read(File.join(project, "Gemfile.lock"))
        code, _stdout, stderr = run_cli(["lock"])

        code.should eq(15), "stderr=#{stderr.inspect}"
        stderr.should contain("There was an error parsing `Gemfile`: No plugin sources available for mpath")
        File.read(File.join(project, "Gemfile.lock")).should eq(before)
      end
    end
  end
end
