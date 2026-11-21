require "./spec_helper"

# `bundle install --local` never installs the lockfile's `BUNDLED WITH`
# bundler: the reference branches to
# `Bundler.self_manager.restart_with_locked_bundler_if_needed`, which only
# restarts when that version is already installed, so no announcement and no
# rubygems fetch happen (`cli/install.rb:15-19`, `self_manager.rb:9-14`).
private def local_switch_index : String
  url = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
  url.ends_with?("/") ? url : url + "/"
end

private def local_switch_lock(bundler_version : String) : String
  String.build do |str|
    str << "GEM\n"
    str << "  remote: " << local_switch_index << "\n"
    str << "  specs:\n"
    str << "    json_pure (2.8.1)\n\n"
    str << "PLATFORMS\n  ruby\n\n"
    str << "DEPENDENCIES\n  json_pure\n\n"
    str << "BUNDLED WITH\n   " << bundler_version << "\n"
  end
end

private def local_switch_run(bundler_version : String) : {Int32, String, String}
  files = {
    "Gemfile"      => "source \"#{local_switch_index}\"\n\ngem \"json_pure\"\n",
    "Gemfile.lock" => local_switch_lock(bundler_version),
  }
  code = 0
  out_text = ""
  err_text = ""
  with_project(files) do |dir|
    previous = {} of String => String?
    values = {
      "BUNDLE_PATH"                      => File.join(dir, "bundle"),
      "BUNDLE_APP_CONFIG"                => File.join(dir, ".bundle"),
      "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
      "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    }
    values.each do |key, value|
      previous[key] = ENV[key]?
      ENV[key] = value
    end
    begin
      Dir.mkdir_p(File.join(dir, ".bundle"))
      code, out, err = Dir.cd(dir) { run_cli(["install", "--local"]) }
      out_text = out
      err_text = err
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
  {code, out_text, err_text}
end

describe "install --local and the locked bundler" do
  it "does not try to install a missing locked bundler" do
    code, out, err = local_switch_run("9.9.9")
    code.should eq(7)
    out.should_not contain("Installing Bundler")
    out.should_not contain("Fetching bundler")
    err.should contain("Could not find json_pure-2.8.1 in locally installed gems")
  end

  it "stays silent about the running bundler when the lock already matches" do
    code, out, err = local_switch_run("4.0.24")
    code.should eq(7)
    out.should_not contain("Installing Bundler")
    out.should_not contain("Fetching bundler")
    err.should contain("Could not find json_pure-2.8.1 in locally installed gems")
  end
end
