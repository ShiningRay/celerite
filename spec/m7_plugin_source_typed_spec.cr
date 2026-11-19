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
