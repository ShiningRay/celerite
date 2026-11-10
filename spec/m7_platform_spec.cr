require "./spec_helper"

# M7(1): `platform` must report the lockfile/Gemfile Ruby requirement and must
# never claim runtime satisfaction when validation was skipped (bridge
# unavailable). It calls Celerite::Commands.platform directly to avoid the CLI
# dispatch/downloader link chain (OpenSSL 3 toolchain lacks EVP_MD_size here).
describe "M7 platform ruby requirement reporting" do
  it "does not claim validation when the bridge is unavailable" do
    with_project({
      "Gemfile"      => "source \"https://rubygems.org\"\n\nruby \"3.0.0\"\n\ngem \"json_pure\"\n",
      "Gemfile.lock" => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nRUBY VERSION\n   ruby 3.0.0p0\n\nBUNDLED WITH\n   4.0.24\n",
    }) do
      output = IO::Memory.new
      errors = IO::Memory.new
      code = Celerite::Commands.platform(output, [] of String)
      out = output.to_s
      err = errors.to_s

      code.should eq(0)
      err.should eq("")
      out.should contain("Your Gemfile specifies a Ruby version requirement:")
      out.should contain("* ruby 3.0.0")
      unless Celerite::Commands.bridge_available?
        out.should contain("Ruby version requirement not validated (bridge unavailable); cannot confirm runtime match.")
        out.should_not contain("Your current platform satisfies the Ruby version requirement.")
      end
    end
  end

  it "prints the parseable ruby requirement with --ruby" do
    with_project({
      "Gemfile"      => "source \"https://rubygems.org\"\n\nruby \"3.0.0\"\n\ngem \"json_pure\"\n",
      "Gemfile.lock" => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nRUBY VERSION\n   ruby 3.0.0p0\n\nBUNDLED WITH\n   4.0.24\n",
    }) do
      output = IO::Memory.new
      errors = IO::Memory.new
      code = Celerite::Commands.platform(output, ["--ruby"])
      output.to_s.should eq("ruby 3.0.0\n")
      errors.to_s.should eq("")
      code.should eq(0)
    end
  end
end
