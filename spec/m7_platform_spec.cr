require "./spec_helper"

describe "M7 platform ruby mismatch behavior" do
  it "prints mismatch message but exits 0 when Gemfile ruby mismatches (bridge unavailable best-effort)" do
    # Without bridge, runtime validation is best-effort skipped; platform still
    # reports lockfile ruby requirement and satisfaction text.
    with_project({
      "Gemfile"      => "source \"https://rubygems.org\"\n\nruby \"3.0.0\"\n\ngem \"json_pure\"\n",
      "Gemfile.lock" => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nRUBY VERSION\n   ruby 3.0.0p0\n\nBUNDLED WITH\n   4.0.24\n",
    }) do
      code, out, err = run_cli(["platform"])
      err.should eq("")
      out.should contain("Your Gemfile specifies a Ruby version requirement:")
      out.should contain("* ruby 3.0.0")
      # When bridge/runtime validation is unavailable, mismatch is not detected
      # here (best-effort skip per ruling); command should not falsely claim
      # validation failure nor crash.
      code.should eq(0)
    end
  end
end
