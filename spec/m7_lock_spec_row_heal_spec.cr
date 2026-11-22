require "./spec_helper"

# task-149: the upstream oracle
# (`lockfile_spec.rb:2214-2279`, "a lockfile missing dependent specs" +
# "auto-heals") locks a Gemfile whose lockfile lists only the root gem, with no
# row and no edge for its dependency, and puts both `.gem` files in
# `vendor/cache`. The reference notices the gap by comparing the locked row's
# `dependencies` against the materialized spec's `runtime_dependencies`
# (`lazy_specification.rb:260-268`), raises `IncorrectLockfileDependencies` and
# re-resolves without the offending spec (`definition.rb:699-708`,
# `reresolve_without` at `definition.rb:782-785`), so the extended dependency
# closure (`spec_set.rb:241-270`) gains the missing row and the edge.
#
# The unreachable source is the point: with a reachable index the stale probe in
# `stale_locked_dependency_full_names` already heals, but when the index cannot
# be fetched the reference still heals from `vendor/cache` while we silently
# returned the locked specs.
#
# The vendored gems are the same minimal synthetic stubs the differential
# fixture uses (a few KiB each, no harvested real gem tree).
private def heal_vendor_dir : String
  File.expand_path("../fixtures/differential/lock-missing-spec-row/extra/vendor/cache", __DIR__)
end

private def heal_unreachable_remote : String
  "http://127.0.0.1:9/"
end

private def heal_project_files(with_vendor_cache : Bool) : Hash(String, String)
  files = {
    "Gemfile" => "source \"#{heal_unreachable_remote}\"\n\ngem \"zroot-gem\"\n",
  }
  if with_vendor_cache
    {"zroot-gem-1.6.0.gem", "child-gem-1.1.1.gem"}.each do |name|
      files["vendor/cache/#{name}"] = File.read(File.join(heal_vendor_dir, name))
    end
  end
  files
end

# The shape under test: `child-gem` is a runtime dependency of `zroot-gem` but
# neither its row nor the edge exists in the lockfile.
private def incomplete_heal_lockfile : String
  <<-LOCK
    GEM
      remote: #{heal_unreachable_remote}
      specs:
        zroot-gem (1.6.0)

    PLATFORMS
      x64-mingw-ucrt

    DEPENDENCIES
      zroot-gem

    BUNDLED WITH
      4.0.24
    LOCK
end

# Control shape: both rows and the edge are present, so nothing is stale.
private def complete_heal_lockfile : String
  <<-LOCK
    GEM
      remote: #{heal_unreachable_remote}
      specs:
        child-gem (1.1.1)
        zroot-gem (1.6.0)
          child-gem (~> 1.1)

    PLATFORMS
      x64-mingw-ucrt

    DEPENDENCIES
      zroot-gem

    BUNDLED WITH
      4.0.24
    LOCK
end

private def heal_ruby_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

private def with_heal_env(project : String, & : String ->) : Nil
  gem_home = File.join(project, "gemhome")
  Dir.mkdir_p(gem_home)
  previous = {} of String => String?
  {
    "HOME"                             => project,
    "USERPROFILE"                      => project,
    "GEM_HOME"                         => gem_home,
    "GEM_PATH"                         => gem_home,
    "BUNDLE_PATH"                      => File.join(project, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
  }.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
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

describe "task-149 locked spec row missing and the source index unreachable" do
  it "heals the missing row and edge from vendor/cache under --local" do
    with_project(heal_project_files(with_vendor_cache: true)) do |project|
      File.write(File.join(project, "Gemfile.lock"), incomplete_heal_lockfile)

      with_heal_env(project) do |dir|
        code, out, err = run_cli(["install", "--local"])
        code.should eq(0)
        err.should be_empty

        # Both gems are installed, not just the locked root.
        out.should contain("Installing child-gem 1.1.1")
        out.should contain("Installing zroot-gem 1.6.0")
        out.should contain("Bundle complete! 1 Gemfile dependency, 2 gems now installed.")

        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("    child-gem (1.1.1)")
        lock.should contain("    zroot-gem (1.6.0)\n      child-gem (~> 1.1)")

        specifications = File.join(dir, "bundle", "ruby", heal_ruby_abi, "specifications")
        File.file?(File.join(specifications, "child-gem-1.1.1.gemspec")).should be_true
        File.file?(File.join(specifications, "zroot-gem-1.6.0.gemspec")).should be_true
      end
    end
  end

  it "leaves a complete lockfile untouched" do
    with_project(heal_project_files(with_vendor_cache: true)) do |project|
      original = "#{complete_heal_lockfile}\n"
      File.write(File.join(project, "Gemfile.lock"), original)

      with_heal_env(project) do |dir|
        code, out, err = run_cli(["install", "--local"])
        code.should eq(0)
        err.should be_empty
        out.should_not contain("Resolving dependencies...")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should eq(original)
        # The row must not be duplicated by the heal path.
        lock.scan("    child-gem (1.1.1)\n").size.should eq(1)
      end
    end
  end

  it "still fails when neither the index nor vendor/cache can supply the row" do
    with_project(heal_project_files(with_vendor_cache: false)) do |project|
      File.write(File.join(project, "Gemfile.lock"), incomplete_heal_lockfile)

      with_heal_env(project) do |dir|
        code, _out, err = run_cli(["install", "--local"])
        code.should eq(7)
        err.should contain("Could not find zroot-gem-1.6.0 in locally installed gems")
        # Nothing may be invented for the missing dependency.
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should_not contain("child-gem")
      end
    end
  end
end
