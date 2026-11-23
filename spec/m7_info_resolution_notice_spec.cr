require "./spec_helper"

# `bundle info`/`show` wrap the runtime check and `Bundler.load.lock` in
# `Bundler.ui.silence` (`cli/info.rb:11-15`, `cli/show.rb:13-17`), so a lockfile
# that needs re-resolution is repaired without printing any notice. The oracle
# (reference 4.0.24) prints only the gem block for both shapes below; these
# examples pin celerite to the same silence.
private def info_notice_index_url : String
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  "file:///#{index.sub(%r{^/}, "")}"
end

private def info_notice_legacy_url : String
  index = File.expand_path("../fixtures/gem-index-legacy", __DIR__).gsub('\\', "/")
  "file:///#{index.sub(%r{^/}, "")}"
end

private def info_notice_restore(name : String, value : String?) : Nil
  value.nil? ? ENV.delete(name) : (ENV[name] = value)
end

private def with_info_notice_project(& : String ->) : Nil
  saved_home = ENV["HOME"]?
  saved_profile = ENV["USERPROFILE"]?
  saved_path = ENV["BUNDLE_PATH"]?
  saved_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  files = {
    "Gemfile"      => %(source "#{info_notice_index_url}"\n\ngem "json_pure"\n),
    "Gemfile.lock" => <<-LOCK,
      GEM
        remote: #{info_notice_index_url}/
        specs:
          json_pure (2.8.1)

      PLATFORMS
        ruby

      DEPENDENCIES
        json_pure

      BUNDLED WITH
          4.0.24
      LOCK
  }
  with_project(files) do |dir|
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    begin
      run_cli(["install", "--quiet"]).first.should eq(0)
      yield dir
    ensure
      info_notice_restore("HOME", saved_home)
      info_notice_restore("USERPROFILE", saved_profile)
      info_notice_restore("BUNDLE_PATH", saved_path)
      info_notice_restore("CELERITE_BRIDGE_SERVER", saved_bridge)
    end
  end
end

private def assert_info_silent(stdout_text : String, err : String) : Nil
  err.should be_empty
  stdout_text.should contain("  * json_pure (2.8.1)")
  stdout_text.should_not contain("Resolving dependencies")
  stdout_text.should_not contain("Re-resolving dependencies")
  stdout_text.should_not contain("Found changes from the lockfile")
  stdout_text.should_not contain("Fetching")
end

describe "info/show re-resolution notices" do
  # Locked source no longer matches the Gemfile source: the reference resolves
  # again inside `Bundler.ui.silence` and prints only the gem block.
  it "stays silent when the locked source set changed" do
    with_info_notice_project do |dir|
      lock = File.read(File.join(dir, "Gemfile.lock"))
      File.write(File.join(dir, "Gemfile.lock"), lock.sub(info_notice_index_url, info_notice_legacy_url))
      code, stdout_text, err = run_cli(["info", "json_pure"])
      code.should eq(0)
      assert_info_silent(stdout_text, err)
    end
  end

  # The lockfile lists the dependency but not its spec (`your lockfile is
  # missing "json_pure"`): the reference re-resolves silently.
  it "stays silent when the locked spec is missing" do
    with_info_notice_project do |dir|
      path = File.join(dir, "Gemfile.lock")
      lock = File.read(path)
      File.write(path, lock.sub(/^    json_pure \(2\.8\.1\)\n/, ""))
      code, stdout_text, err = run_cli(["info", "json_pure"])
      code.should eq(0)
      assert_info_silent(stdout_text, err)
    end
  end
end
