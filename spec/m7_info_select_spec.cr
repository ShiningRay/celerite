require "./spec_helper"

# `bundle info`/`show` go through `Common.select_spec` (`cli/common.rb:68-111`),
# which has three steps beyond a plain lockfile lookup: an exact name match, a
# regex match over `definition.specs`, and a default-gem fallback from
# `Gem::Specification.find_all_by_name(name).last` when that spec is a default
# gem. Two matches open the interactive menu, which the differential fixtures
# (`info-regex-menu`) cover end-to-end; these examples pin the non-interactive
# branches.
private def info_select_index_url : String
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  "file:///#{index.sub(%r{^/}, "")}"
end

private def info_select_gemfile : String
  %(source "#{info_select_index_url}"\n\ngem "json_pure", "2.6.0"\n)
end

private def info_select_lock : String
  <<-LOCK
    GEM
      remote: #{info_select_index_url}/
      specs:
        json_pure (2.6.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      json_pure (= 2.6.0)

    BUNDLED WITH
        4.0.24
    LOCK
end

private def info_select_restore(name : String, value : String?) : Nil
  value.nil? ? ENV.delete(name) : (ENV[name] = value)
end

private def with_info_select_project(lock : Bool = true, & : String ->) : Nil
  saved_home = ENV["HOME"]?
  saved_profile = ENV["USERPROFILE"]?
  saved_path = ENV["BUNDLE_PATH"]?
  saved_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  files = {"Gemfile" => info_select_gemfile}
  files["Gemfile.lock"] = info_select_lock if lock
  with_project(files) do |dir|
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    begin
      yield dir
    ensure
      info_select_restore("HOME", saved_home)
      info_select_restore("USERPROFILE", saved_profile)
      info_select_restore("BUNDLE_PATH", saved_path)
      info_select_restore("CELERITE_BRIDGE_SERVER", saved_bridge)
    end
  end
end

describe "info select_spec" do
  # `cli/common.rb:98-101` + `cli/info.rb:50-73`: a default gem that the lockfile
  # does not mention is still selectable, and only then does the header carry
  # the `Default Gem: yes` marker.
  it "falls back to the default gem for a name outside the lockfile" do
    with_info_select_project(lock: false) do
      run_cli(["install", "--quiet"]).first.should eq(0)
      code, out, err = run_cli(["info", "stringio"])
      code.should eq(0)
      err.should be_empty
      out.should contain("  * stringio (")
      out.should contain("Summary: Pseudo IO on String")
      out.should contain("Default Gem: yes")
    end
  end

  # `cli/common.rb:68-96` never reaches the definition for `bundler` itself:
  # `select_spec` returns `spec` only from `Bundler.definition.specs`, so the
  # reference special-cases nothing yet still prints the running bundler.
  it "prints the running bundler without a Default Gem marker" do
    with_info_select_project(lock: false) do
      run_cli(["install", "--quiet"]).first.should eq(0)
      code, out, err = run_cli(["info", "bundler"])
      code.should eq(0)
      err.should be_empty
      out.should contain("  * bundler (")
      out.should contain("Summary: The best way to manage your application's dependencies")
      out.should_not contain("Default Gem: yes")
    end
  end

  # A single regex match resolves without the menu (`specs.count == 1`).
  it "uses the only regex match" do
    with_info_select_project do
      run_cli(["install", "--quiet"]).first.should eq(0)
      code, out, err = run_cli(["info", "pure"])
      code.should eq(0)
      err.should be_empty
      out.should contain("  * json_pure (2.6.0)")
      out.should_not contain(" : ")
    end
  end

  # `cli/common.rb:113-123` keeps the plain not-found line when no suggestion
  # exists, and the exit status stays 7.
  it "reports a missing gem without a suggestion" do
    with_info_select_project do
      run_cli(["install", "--quiet"]).first.should eq(0)
      code, out, err = run_cli(["info", "zzzznotagem"])
      code.should eq(7)
      out.should be_empty
      err.should contain("Could not find gem 'zzzznotagem'.")
      err.should_not contain("Did you mean")
    end
  end
end
