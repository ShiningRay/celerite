require "./spec_helper"

# task-161: `lock` followed by `install` must keep a transitive spec that the
# lockfile already resolved.
#
# The file:// index installs without checksums, so the lock written by `lock`
# carries bare CHECKSUMS rows. The following `install` therefore sees
# `checksums_need_refresh? == Empty` (`definition.cr:598`) and is forced off the
# reuse path onto a real resolve (`commands_install.cr:369-370`). In that
# resolve the locked candidates used to be listed before the source index in
# `ResolutionSource#all_specs`, and the locked stubs carry no dependency edges
# (`resolution.cr:2253-2257`), so `uniq { {version, platform} }` kept the
# empty-edge stub and shadowed the indexed spec. `net-smtp`'s `net-protocol`
# requirement never reached the graph: `net-protocol` was neither installed nor
# kept in the rewritten lockfile, while the reference resolves with the
# lockfile's own edges, installs both gems and keeps both rows.
private def with_transitive_bridge(& : ->) : Nil
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

private def transitive_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index-locked-deps")))
end

private def with_isolated_transitive_home(dir : String, & : ->) : Nil
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

describe "install after lock" do
  it "keeps a transitive locked spec that the dependency closure still needs" do
    pending! "ruby not available" unless ruby_available?
    remote = transitive_remote
    with_transitive_bridge do
      with_project({
        "Gemfile"        => %(source "#{remote}"\n\ngem "net-smtp"\n),
        ".bundle/config" => "BUNDLE_PATH: \"vendor/bundle\"\n",
      }) do |dir|
        with_isolated_transitive_home(dir) do
          code, _out, err = run_cli(["lock"])
          code.should eq(0)
          locked = File.read(File.join(dir, "Gemfile.lock"))
          locked.should contain("    net-protocol (0.2.2)")
          locked.should contain("    net-smtp (0.5.1)\n      net-protocol\n")

          code2, out2, err2 = run_cli(["install"])
          code2.should eq(0)
          err2.should eq("")

          installed = File.read(File.join(dir, "Gemfile.lock"))
          installed.should contain("    net-protocol (0.2.2)")
          installed.should contain("    net-smtp (0.5.1)\n      net-protocol\n")
          out2.should contain("Bundle complete! 1 Gemfile dependency, 2 gems now installed.")
          out2.should contain("Installing net-protocol 0.2.2")
          out2.should contain("Installing net-smtp 0.5.1")
          installed_gems = (Dir.glob("**/gems/net-*") + Dir.glob(File.join(dir, "**", "gems", "net-*")))
            .map { |p| File.basename(p) }
            .uniq
            .sort
          installed_gems.should eq(["net-protocol-0.2.2", "net-smtp-0.5.1"])
        end
      end
    end
  end
end
