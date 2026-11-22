require "./spec_helper"
require "../src/celerite"

# task-143 — the "default reference bundler version" has exactly one home:
# `Celerite::Profile::DEFAULT_BUNDLER_VERSION`, reached through
# `Celerite::Profile.bundler_version`, which every former call site of the
# inlined `ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"` now uses.
#
# These examples deliberately never compare against a `"4.0.24"` literal: the
# default is pinned through independent oracles (the reference release
# metadata table, the profile-generation predicate, the vendored manpage
# profile directory, and the CLI's own `version` rendering), so a stale or
# typo'd constant fails here instead of being silently re-asserted.
#
# Pre-refactor behaviour measured on 1af3a0d (raw `ENV[...]?` probe, Windows,
# Crystal 1.22.1): unset -> default; "" -> default (the OS deletes an empty
# environment value, so it is indistinguishable from unset); "   " -> "   ";
# " 2.7.2 " -> " 2.7.2 ". No trimming or validation existed, and none was added.
private def with_profile_env(value : String?, & : ->) : Nil
  previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  if value
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = value
  else
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  end
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous
    else
      ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    end
  end
end

describe "Celerite::Profile.bundler_version" do
  it "resolves to a release the reference metadata table knows (unset env)" do
    with_profile_env(nil) do
      version = Celerite::Profile.bundler_version
      metadata = Celerite::ReleaseMetadata.for(version)
      metadata.should_not be_nil
      date, commit = metadata.not_nil!
      version.should match(/\A\d+\.\d+\.\d+\z/)
      date.should match(/\A\d{4}-\d{2}-\d{2}\z/)
      commit.should_not be_empty
      # The default selects the 4.x generation, which the search-directory
      # fallbacks (`Commands.preserve_lockfile_crlf?`, `with_profile_indent`)
      # depend on.
      Celerite::Commands.profile_2_x?.should be_false
    end
  end

  it "points at a vendored manpage profile directory (unset env)" do
    with_profile_env(nil) do
      dir = File.expand_path("../assets/man/#{Celerite::Profile.bundler_version}", __DIR__)
      Dir.exists?(dir).should be_true
    end
  end

  it "renders the default through the CLI with its release build metadata" do
    with_profile_env(nil) do
      version = Celerite::Profile.bundler_version
      date, commit = Celerite::ReleaseMetadata.for(version).not_nil!
      code, out, err = run_cli(["version"])
      code.should eq(0)
      out.should eq("#{version} (#{date} commit #{commit})\n")
      err.should be_empty
    end
  end

  it "takes the value of CELERITE_PROFILE_BUNDLER_VERSION when it is set" do
    with_profile_env("2.7.2") do
      Celerite::Profile.bundler_version.should eq("2.7.2")
      Celerite::Commands.bundle_profile_version.should eq("2.7.2")
      Celerite::Commands.profile_2_x?.should be_true
    end
  end

  it "accepts an unknown value without validating it" do
    with_profile_env("9.9.9") do
      Celerite::Profile.bundler_version.should eq("9.9.9")
    end
  end

  it "uses the value verbatim: no trimming and no blank fallback" do
    with_profile_env("   ") do
      Celerite::Profile.bundler_version.should eq("   ")
      Celerite::Commands.profile_2_x?.should be_false
    end
    with_profile_env(" 2.7.2 ") do
      Celerite::Profile.bundler_version.should eq(" 2.7.2 ")
      Celerite::Commands.profile_2_x?.should be_false
    end
  end

  it "is the single source of truth for the manpage profile default" do
    Celerite::Manpages::PROFILE_DEFAULT.should eq(Celerite::Profile::DEFAULT_BUNDLER_VERSION)
    with_profile_env(nil) do
      Celerite::Manpages::PROFILE_DEFAULT.should eq(Celerite::Profile.bundler_version)
    end
  end
end
