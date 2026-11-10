require "./spec_helper"

describe "M7 installed gem discovery" do
  it "check treats gem dir without specification file as installed" do
    with_project({
      "Gemfile"                                             => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
      "Gemfile.lock"                                        => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nBUNDLED WITH\n   4.0.24\n",
      "vendor/bundle/ruby/3.4.0/gems/json_pure-2.8.1/.keep" => "",
      ".bundle/config"                                      => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
    }) do
      code, out, err = run_cli(["check"])
      err.should eq("")
      out.should eq("The Gemfile's dependencies are satisfied\n")
      code.should eq(0)
    end
  end

  it "list shows installed gem when only gem dir exists" do
    with_project({
      "Gemfile"                                             => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
      "Gemfile.lock"                                        => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nBUNDLED WITH\n   4.0.24\n",
      "vendor/bundle/ruby/3.4.0/gems/json_pure-2.8.1/.keep" => "",
      ".bundle/config"                                      => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
    }) do
      code, out, err = run_cli(["list"])
      err.should eq("")
      out.should contain("json_pure (2.8.1)")
      code.should eq(0)
    end
  end
end
