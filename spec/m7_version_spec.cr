require "./spec_helper"
require "../src/celerite"

private def version_with_profile(command : Array(String), profile : String)
  previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = profile
  begin
    run_cli(command)
  ensure
    if previous
      ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous
    else
      ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    end
  end
end

describe "Celerite::CLI version output" do
  it "prints the release build metadata for `bundle version`" do
    # `Bundler.verbose_version` + `Bundler::BuildMetadata` constants.
    code, out, err = version_with_profile(["version"], "4.0.24")
    code.should eq(0)
    out.should eq("4.0.24 (2026-11-05 commit 3b396e4)\n")
    err.should be_empty
  end

  it "prints the bare version for -v and --version" do
    ["-v", "--version"].each do |flag|
      code, out, _err = version_with_profile([flag], "4.0.24")
      code.should eq(0)
      out.should eq("4.0.24\n")
    end
  end

  it "prints the 2.7.x shape with that release's metadata" do
    code, out, _err = version_with_profile(["version"], "2.7.2")
    code.should eq(0)
    out.should eq("Bundler version 2.7.2 (2025-09-09 commit b463ced1459)\n")
  end

  it "rejects extra arguments like the reference" do
    code, out, err = version_with_profile(["version", "extra"], "4.0.24")
    code.should eq(15)
    out.should be_empty
    err.should contain(%(ERROR: "bundle version" was called with arguments ["extra"]))
    err.should contain(%(Usage: "bundle version"))
  end
end
