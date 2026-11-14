require "./spec_helper"

# Reference: bundler `spec/lock/lockfile_spec.rb:2088-2142` "automatically fixes
# the lockfile when it has incorrect deps, keeping the locked version".
#
# Bundler cannot see the missing edge through the lockfile: `LazySpecification`
# (`lazy_specification.rb:26-39`) reports an empty dependency list, so
# `check_lockfile` (`definition.rb:973-1014`) never flags it. The edge appears
# only once the real gemspec is materialized (`spec_set.rb#materialize`); the
# reference therefore repairs the lockfile while keeping the locked versions.
#
# Our `install` takes the locked path (`commands_install.cr:177
# resolution.resolve!(reuse)`), so the reuse path has to refresh the locked
# specs' dependency edges from the fetched .gem metadata before the lockfile is
# written (`commands_install.cr:290`).
private def with_locked_deps_bridge(& : ->) : Nil
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

private def locked_deps_remote : String
  # Downloader appends "/gems/<full name>.gem", so the source root is the
  # directory that contains the "gems" folder.
  file_source_url(File.expand_path(File.join(__DIR__, "fixtures", "locked-deps")))
end

private def locked_deps_gemfile(remote : String) : String
  %(source "#{remote}"\n\ngem "net-smtp"\n)
end

# `InstallPaths.downloader_cache_root` lives under the user home
# (`~/.bundle/cache`), so point the home at the throw-away project: the
# download cache is then per-test and the fixtures are re-fetched every run
# instead of being served from a possibly stale global cache entry.
private def with_isolated_home(dir : String, & : ->) : Nil
  home = ENV["HOME"]?
  profile = ENV["USERPROFILE"]?
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  begin
    yield
  ensure
    if home
      ENV["HOME"] = home
    else
      ENV.delete("HOME")
    end
    if profile
      ENV["USERPROFILE"] = profile
    else
      ENV.delete("USERPROFILE")
    end
  end
end

private def locked_deps_lockfile(remote : String, edges : Bool) : String
  specs = if edges
            "    net-protocol (0.2.2)\n    net-smtp (0.5.0)\n      net-protocol\n"
          else
            "    net-protocol (0.2.2)\n    net-smtp (0.5.0)\n"
          end
  "GEM\n  remote: #{remote}/\n  specs:\n#{specs}\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  net-smtp\n\nBUNDLED WITH\n   4.0.24\n"
end

describe "locked dependency edges" do
  it "fills a missing locked dependency edge from the fetched gemspec" do
    pending! "ruby not available" unless ruby_available?
    remote = locked_deps_remote
    with_locked_deps_bridge do
      with_project({
        "Gemfile"        => locked_deps_gemfile(remote),
        "Gemfile.lock"   => locked_deps_lockfile(remote, edges: false),
        ".bundle/config" => "BUNDLE_PATH: \"vendor/bundle\"\n",
      }) do |dir|
        with_isolated_home(dir) do
          code, _out, err = run_cli(["install"])
          code.should eq(0)

          lock = File.read(File.join(dir, "Gemfile.lock"))
          lock.should contain("    net-smtp (0.5.0)\n      net-protocol\n")
          lock.should contain("    net-protocol (0.2.2)")
          lock.should_not contain("net-smtp (0.5.1)")
          err.should_not contain("net-smtp (0.5.1)")
        end
      end
    end
  end

  it "keeps the lockfile stable when the locked edges are already complete" do
    pending! "ruby not available" unless ruby_available?
    remote = locked_deps_remote
    with_locked_deps_bridge do
      with_project({
        "Gemfile"        => locked_deps_gemfile(remote),
        "Gemfile.lock"   => locked_deps_lockfile(remote, edges: true),
        ".bundle/config" => "BUNDLE_PATH: \"vendor/bundle\"\n",
      }) do |dir|
        with_isolated_home(dir) do
          code, _out, _err = run_cli(["install"])
          code.should eq(0)
          settled = File.read(File.join(dir, "Gemfile.lock"))

          code2, out2, _err2 = run_cli(["install"])
          code2.should eq(0)
          File.read(File.join(dir, "Gemfile.lock")).should eq(settled)
          out2.should_not contain("Fetching net-smtp")
          settled.should contain("    net-smtp (0.5.0)\n      net-protocol\n")
        end
      end
    end
  end
end
