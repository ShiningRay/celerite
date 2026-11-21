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

# task-115: the upstream `lockfile_spec.rb:2088` shape ("automatically fixes the
# lockfile when it has incorrect deps, keeping the locked version"). Both spec
# rows are present but the dependent's edge line is missing; `install` must
# restore the edge and keep the locked version, printing ONE
# `Resolving dependencies...` because a lock whose platforms cover the host does
# not resolve before the heal (`definition.rb:782-785` never adds the row to
# `@gems_to_unlock`, so `gem_version_promoter.rb:134-145` still prefers 0.5.0).
private def edge_heal_lockfile(remote : String = "#{autoheal_index_url}/") : String
  <<-LOCK
    GEM
      remote: #{remote}
      specs:
        net-protocol (0.2.2)
        net-smtp (0.5.0)

    PLATFORMS
      x64-mingw-ucrt

    DEPENDENCIES
      net-smtp

    BUNDLED WITH
       4.0.24
    LOCK
end

describe "task-115 missing dependency edge keeps the locked version" do
  it "restores the edge without upgrading the locked spec" do
    with_project(autoheal_project) do |project|
      File.write(File.join(project, "Gemfile.lock"), edge_heal_lockfile)

      with_autoheal_env(project) do |dir|
        code, out, err = run_cli(["install"])
        code.should eq(0)
        out.scan("Resolving dependencies...").size.should eq(1)
        out.should contain("Installing net-smtp 0.5.0")
        out.should_not contain("net-smtp 0.5.1")
        err.should_not contain("net-smtp 0.5.1")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("    net-protocol (0.2.2)")
        lock.should contain("    net-smtp (0.5.0)\n      net-protocol")
        lock.should_not contain("net-smtp (0.5.1)")
      end
    end
  end

  it "keeps the locked version when the healed row is the only one missing" do
    with_project(autoheal_project) do |project|
      # `net-protocol` row absent as well: the heal adds both the row and the
      # edge and still must not promote `net-smtp` to the index's newest 0.5.1.
      File.write(File.join(project, "Gemfile.lock"), edge_heal_lockfile.lines.reject { |l| l.includes?("net-protocol (0.2.2)") }.join)

      with_autoheal_env(project) do |dir|
        code, out, _ = run_cli(["install"])
        code.should eq(0)
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("    net-protocol (0.2.2)")
        lock.should contain("    net-smtp (0.5.0)\n      net-protocol")
        lock.should_not contain("net-smtp (0.5.1)")
        out.should_not contain("(was 0.5.0)")
      end
    end
  end
end
