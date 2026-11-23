require "./spec_helper"

# task-166: a `bundler` dependency edge inside a locked spec must not make the
# lockfile look incomplete.
#
# `lockfile_covers_dependencies?` (`resolution.cr:1477`) walks every locked
# spec's edges and demands a locked row for each one. `bundler` never has a spec
# row of its own: the reference only synthesizes a `LazySpecification` for it out
# of the CHECKSUMS section (`lockfile_parser.rb:274-276`) and skips it at the
# same level when validating edges (`SpecSet#validate_deps`, `spec_set.rb:87-96`)
# — as `rails (8.0.2)` shows, whose row carries `bundler (>= 1.15.0)`. Without
# the same skip, any lockfile containing such an edge (every `rails` lockfile
# does) was judged incomplete, `reuse_locked_resolution?` returned false and
# `install` fell through to a full `run_resolution` (`resolution.cr:1241`) that
# rewrote the lockfile with only the specs the solver happened to re-pick.
private def with_bundler_edge_bridge(& : ->) : Nil
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

private def with_bundler_edge_home(dir : String, & : ->) : Nil
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

private def bundler_edge_lock(remote : String) : String
  <<-LOCK
  GEM
    remote: #{remote}
    specs:
      net-protocol (0.2.2)
      net-smtp (0.5.1)
        bundler (>= 1.15.0)
        net-protocol

  PLATFORMS
    x64-mingw-ucrt

  DEPENDENCIES
    net-smtp (= 0.5.1)

  CHECKSUMS
    bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc
    net-protocol (0.2.2) sha256=7b8a581482291525e23fd723b9ee84cbb060395d5e40fd51002ebb6f8945abd0
    net-smtp (0.5.1) sha256=74e4cd630e7a83e320ba7114bb6a49c9b0d525cfcea1d4af375737701b09bd68

  BUNDLED WITH
    4.0.24
  LOCK
end

describe "install with a bundler edge in the lockfile" do
  it "keeps every locked spec instead of re-resolving" do
    pending! "ruby not available" unless ruby_available?
    remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index-locked-deps")))
    with_bundler_edge_bridge do
      with_project({
        "Gemfile"        => %(source "#{remote}"\n\ngem "net-smtp", "0.5.1"\n),
        "Gemfile.lock"   => bundler_edge_lock(remote),
        ".bundle/config" => "BUNDLE_PATH: \"vendor/bundle\"\n",
      }) do |dir|
        with_bundler_edge_home(dir) do
          code, out, _err = run_cli(["install"])
          code.should eq(0)

          installed = File.read(File.join(dir, "Gemfile.lock"))
          installed.should contain("    net-protocol (0.2.2)")
          installed.should contain("    net-smtp (0.5.1)\n      net-protocol\n")
          installed.should contain("  net-protocol (0.2.2) sha256=")
          installed.should contain("  net-smtp (0.5.1) sha256=")
          out.should contain("Installing net-protocol 0.2.2")
          out.should contain("Installing net-smtp 0.5.1")
          out.should contain("Bundle complete! 1 Gemfile dependency, 2 gems now installed.")
        end
      end
    end
  end
end
