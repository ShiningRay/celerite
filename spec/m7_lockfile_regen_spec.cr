require "./spec_helper"
require "../src/celerite"

# Reference: bundler `definition.rb:1051-1076` (`converge_dependencies` flags a
# dependency that is listed in DEPENDENCIES but has no locked spec as
# `@missing_lockfile_dep`) and `:973-1014` (`check_lockfile` drops specs with
# missing/invalid dependency edges). Any hit makes `something_changed?`
# (`:630-645`) true, so the definition re-resolves instead of reusing.
#
# `install` takes the locked path (`commands_install.cr:177
# resolution.resolve!(reuse)`); `lock` always re-resolves (`commands_surface.cr:247
# no_reuse: true`), so the regression is exercised through `resolve!(reuse: true)`.
private def with_regen_bridge(& : ->) : Nil
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

private def regen_index_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

# `definition.rb:844-848` (`current_platform_locked?`): a `ruby` entry only
# covers the host when `Bundler.generic_local_platform` is `ruby` (Windows
# reports `universal-mingw`), so a reusable lock must also name the host
# platform. The default below keeps every reuse precondition satisfiable; the
# ruby-only variant is covered by its own example.
private def regen_platforms : String
  "  ruby\n  #{Celerite::Gem::Platform.local}\n"
end

private def regen_gemfile(remote : String, specs : String, deps : String,
                          platforms : String = regen_platforms) : String
  "GEM\n  remote: #{remote}/\n  specs:\n#{specs}\nPLATFORMS\n#{platforms}\nDEPENDENCIES\n#{deps}\n\nBUNDLED WITH\n   4.0.24\n"
end

describe "lockfile regeneration" do
  it "re-resolves through the locked path when the lockfile has no specs" do
    pending! "ruby not available" unless ruby_available?
    remote = regen_index_remote
    with_regen_bridge do
      with_project({
        "Gemfile"      => %(source "#{remote}"\n\ngem "thor"\n),
        "Gemfile.lock" => regen_gemfile(remote, "", "  thor\n"),
      }) do
        with_client do |client|
          resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
          resolution.progress = IO::Memory.new
          resolution.reuse_locked?.should be_false

          specs = resolution.resolve!(reuse: true)
          names = specs.map(&.name)
          names.should contain("thor")
          specs.find { |spec| spec.name == "thor" }.not_nil!.version.to_s.should eq("1.3.2")
        end
      end
    end
  end

  it "reuses the locked path when every dependency has a locked spec" do
    pending! "ruby not available" unless ruby_available?
    remote = regen_index_remote
    with_regen_bridge do
      with_project({
        "Gemfile"      => %(source "#{remote}"\n\ngem "thor"\n),
        "Gemfile.lock" => regen_gemfile(remote, "    thor (1.3.2)\n", "  thor\n"),
      }) do
        with_client do |client|
          resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
          resolution.progress = IO::Memory.new
          resolution.reuse_locked?.should be_true
          resolution.resolve!(reuse: true).map(&.name).should eq(["thor"])
        end
      end
    end
  end

  # `definition.rb:844-848` + `:150` + `:635`: a `ruby`-only `PLATFORMS` entry
  # does NOT cover a host whose `generic_local_platform` differs from `ruby`
  # (Windows: `universal-mingw`), so `@current_platform_missing` is set and
  # `something_changed?` forces a re-resolve. Reusing the lock here would hide
  # the whole index fetch — measured 4.0.24: `install` against an unreachable
  # source with a `ruby`-only lock and a populated `vendor/cache` exits 17,
  # while the same tree with `x64-mingw-ucrt` locked exits 0.
  it "re-resolves when the lockfile only covers `ruby` on a non-ruby host" do
    pending! "ruby not available" unless ruby_available?
    skip = Celerite::Gem::Platform.new("ruby").match?(Celerite::Gem::Platform.local)
    pending! "generic local platform is ruby" if skip
    remote = regen_index_remote
    with_regen_bridge do
      with_project({
        "Gemfile"      => %(source "#{remote}"\n\ngem "thor"\n),
        "Gemfile.lock" => regen_gemfile(remote, "    thor (1.3.2)\n", "  thor\n", platforms: "  ruby\n"),
      }) do
        with_client do |client|
          resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
          resolution.progress = IO::Memory.new
          resolution.reuse_locked?.should be_false
          resolution.resolve!(reuse: true).map(&.name).should eq(["thor"])
        end
      end
    end
  end

  it "re-resolves when a locked spec depends on a gem missing from the lockfile" do
    pending! "ruby not available" unless ruby_available?
    remote = regen_index_remote
    with_regen_bridge do
      with_project({
        "Gemfile"      => %(source "#{remote}"\n\ngem "json_pure", "2.6.0"\n),
        "Gemfile.lock" => regen_gemfile(remote, "    json_pure (2.6.0)\n      racc (~> 1.4)\n", "  json_pure (2.6.0)\n"),
      }) do
        with_client do |client|
          resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
          resolution.progress = IO::Memory.new
          resolution.reuse_locked?.should be_false

          specs = resolution.resolve!(reuse: true)
          specs.map(&.name).should eq(["json_pure"])
        end
      end
    end
  end

  it "regenerates an empty-spec lockfile through `lock`" do
    pending! "ruby not available" unless ruby_available?
    remote = regen_index_remote
    with_regen_bridge do
      with_project({
        "Gemfile"      => %(source "#{remote}"\n\ngem "thor"\n),
        "Gemfile.lock" => regen_gemfile(remote, "", "  thor\n"),
      }) do |dir|
        code, _out, _err = run_cli(["lock"])
        code.should eq(0)
        File.read(File.join(dir, "Gemfile.lock")).should contain("    thor (1.3.2)")
      end
    end
  end
end
