require "./spec_helper"

# task-94: `definition.rb:699-708` rescues `IncorrectLockfileDependencies`
# (`lazy_specification.rb:259-270`) and, when not frozen, re-resolves without
# the offending spec. The retry prints a second `Resolving dependencies...`
# line, then the missing dependency is fetched and installed. `lock` never
# takes that path, but it does add the current platform
# (`definition.rb:850-857`).
private def autoheal_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index-locked-deps", __DIR__))
end

private def autoheal_project : Hash(String, String)
  {"Gemfile" => "source \"#{autoheal_index_url}\"\n\ngem \"net-smtp\", \"0.5.0\"\n"}
end

# `specs:` names only `net-smtp`: its `net-protocol` dependency row is missing,
# which is exactly the stale shape the reference auto-heals.
private def autoheal_lockfile(remote : String = "#{autoheal_index_url}/") : String
  <<-LOCK
    GEM
      remote: #{remote}
      specs:
        net-smtp (0.5.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      net-smtp (= 0.5.0)
    LOCK
end

private def with_autoheal_env(project : String, frozen : Bool = false, & : String ->) : Nil
  previous = {} of String => String?
  {
    "HOME"                             => project,
    "USERPROFILE"                      => project,
    "GEM_HOME"                         => File.join(project, "gems"),
    "GEM_PATH"                         => File.join(project, "gems"),
    "BUNDLE_PATH"                      => File.join(project, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
  }.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
  end
  previous["BUNDLE_FROZEN"] = ENV["BUNDLE_FROZEN"]?
  if frozen
    ENV["BUNDLE_FROZEN"] = "true"
  else
    ENV.delete("BUNDLE_FROZEN")
  end
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

describe "task-94 stale lockfile dependency edges" do
  it "re-resolves and installs the missing dependent spec on install" do
    with_project(autoheal_project) do |project|
      File.write(File.join(project, "Gemfile.lock"), autoheal_lockfile)

      with_autoheal_env(project) do
        code, out, err = run_cli(["install"])
        code.should eq(0)
        out.scan("Resolving dependencies...").size.should eq(2)
        out.should contain("Installing net-protocol 0.2.2")
        out.should contain("Installing net-smtp 0.5.0")
        out.should contain("Bundle complete! 1 Gemfile dependency, 2 gems now installed.")
        lock = File.read(File.join(project, "Gemfile.lock"))
        lock.should contain("net-protocol (0.2.2)")
        lock.should contain("      net-protocol")
        lock.should contain("  x64-mingw-ucrt")
        err.should_not contain("Bundler attempted to update")
      end
    end
  end

  it "reports the mismatch instead of healing when frozen" do
    with_project(autoheal_project) do |project|
      File.write(File.join(project, "Gemfile.lock"), autoheal_lockfile)

      with_autoheal_env(project, frozen: true) do |dir|
        code, _, err = run_cli(["install"])
        code.should eq(41)
        err.should contain("Bundler found incorrect dependencies in the lockfile for net-smtp-0.5.0")
        File.read(File.join(dir, "Gemfile.lock")).should_not contain("net-protocol (0.2.2)")
      end
    end
  end

  it "leaves the edges alone on lock but adds the current platform" do
    with_project(autoheal_project) do |project|
      File.write(File.join(project, "Gemfile.lock"), autoheal_lockfile)

      with_autoheal_env(project) do |dir|
        code, out, _ = run_cli(["lock"])
        code.should eq(0)
        out.should contain("Resolving dependencies...")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("  x64-mingw-ucrt")
        # No spec row: `lock` never heals the missing dependent gem. The
        # dependency line our generator derives from the index is a pre-existing
        # divergence from `lockfile_spec.rb` (the reference keeps the locked
        # dependency list); recorded in the compatibility report.
        lock.should_not contain("net-protocol (0.2.2)")
      end
    end
  end

  it "does not heal twice: the rewritten lockfile is stable" do
    with_project(autoheal_project) do |project|
      File.write(File.join(project, "Gemfile.lock"), autoheal_lockfile)

      with_autoheal_env(project) do |dir|
        run_cli(["install"]).first.should eq(0)
        healed = File.read(File.join(dir, "Gemfile.lock"))
        code, out, _ = run_cli(["install"])
        code.should eq(0)
        out.scan("Resolving dependencies...").size.should be <= 1
        File.read(File.join(dir, "Gemfile.lock")).should eq(healed)
      end
    end
  end
end
