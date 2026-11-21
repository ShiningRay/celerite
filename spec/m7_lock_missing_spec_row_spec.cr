require "./spec_helper"

# task-117: `check_lockfile` (`definition.rb:973-1015`) validates every locked
# spec's dependency edges against the lock itself (`spec_set.rb:87-96`) and
# deletes the offending rows. Because the deleted row is the same object as
# `@originally_locked_specs` (`definition.rb:140`), the locked candidate *and*
# its preferred version disappear together, so the reference re-resolves and
# promotes `net-smtp` to the index's newest 0.5.1. Our `lock` used to short
# circuit on `Definition#lockfile_matches_dependencies?`, which only compares
# DEPENDENCIES with the Gemfile and never inspects the locked rows themselves.
private def spec_row_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index-locked-deps", __DIR__))
end

private def spec_row_project : Hash(String, String)
  {"Gemfile" => "source \"#{spec_row_index_url}\"\n\ngem \"net-smtp\"\n"}
end

# The shape under test: `net-protocol` is named as an edge of `net-smtp` but the
# `net-protocol (0.2.2)` spec row itself is absent.
private def missing_spec_row_lockfile(remote : String = "#{spec_row_index_url}/") : String
  <<-LOCK
    GEM
      remote: #{remote}
      specs:
        net-smtp (0.5.0)
          net-protocol

    PLATFORMS
      ruby
      x64-mingw-ucrt

    DEPENDENCIES
      net-smtp

    BUNDLED WITH
      4.0.24
    LOCK
end

# Control shape: both rows present and the edge present, so nothing is stale.
private def complete_spec_row_lockfile(remote : String = "#{spec_row_index_url}/") : String
  <<-LOCK
    GEM
      remote: #{remote}
      specs:
        net-protocol (0.2.2)
        net-smtp (0.5.0)
          net-protocol

    PLATFORMS
      ruby
      x64-mingw-ucrt

    DEPENDENCIES
      net-smtp

    BUNDLED WITH
      4.0.24
    LOCK
end

private def with_spec_row_env(project : String, & : String ->) : Nil
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

describe "task-117 locked spec row missing but its edge present" do
  it "re-resolves on lock and promotes the locked version" do
    with_project(spec_row_project) do |project|
      File.write(File.join(project, "Gemfile.lock"), missing_spec_row_lockfile)

      with_spec_row_env(project) do |dir|
        code, out, err = run_cli(["lock"])
        code.should eq(0)
        out.should contain("Fetching source index from")
        out.should contain("Resolving dependencies...")
        err.should_not contain("Bundler attempted to update")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain("    net-protocol (0.2.2)")
        lock.should contain("    net-smtp (0.5.1)\n      net-protocol")
        lock.should_not contain("net-smtp (0.5.0)")
      end
    end
  end

  it "does not re-resolve when both spec rows and the edge are present" do
    with_project(spec_row_project) do |project|
      original = "#{complete_spec_row_lockfile}\n"
      File.write(File.join(project, "Gemfile.lock"), original)

      with_spec_row_env(project) do |dir|
        code, out, err = run_cli(["lock"])
        code.should eq(0)
        out.should_not contain("Resolving dependencies...")
        out.should_not contain("Fetching source index from")
        err.should be_empty
        File.read(File.join(dir, "Gemfile.lock")).should eq(original)
      end
    end
  end

  it "does not add a missing edge when both spec rows are present" do
    with_project(spec_row_project) do |project|
      original = "#{complete_spec_row_lockfile}\n"
      without_edge = original.lines(chomp: false).reject { |line| line == "      net-protocol\n" }.join
      File.write(File.join(project, "Gemfile.lock"), without_edge)

      with_spec_row_env(project) do |dir|
        code, out, _ = run_cli(["lock"])
        code.should eq(0)
        out.should_not contain("Resolving dependencies...")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should eq(without_edge)
        lock.should contain("    net-smtp (0.5.0)")
        lock.should_not contain("      net-protocol")
      end
    end
  end
end
