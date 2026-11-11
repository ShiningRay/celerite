require "./spec_helper"

# M7(3): `fund` must read real funding metadata from the installed tree
# (specifications .gemspec metadata) instead of printing a fixed response.
# Calls Celerite::Commands.fund directly to avoid the CLI dispatch/downloader
# link chain (local OpenSSL 3 lacks the EVP_MD_size symbol Crystal binds).
describe "M7 fund" do
  it "prints a funding URI read from installed specifications metadata" do
    server = File.expand_path("../assets/bridge/server.rb", __DIR__)
    previous = ENV["CELERITE_BRIDGE_SERVER"]?
    ENV["CELERITE_BRIDGE_SERVER"] = server
    begin
      with_project({
        "Gemfile"                                                         => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
        "Gemfile.lock"                                                    => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nBUNDLED WITH\n   4.0.24\n",
        "vendor/bundle/ruby/3.4.0/specifications/json_pure-2.8.1.gemspec" => <<-SPEC,
          Gem::Specification.new do |s|
            s.name = "json_pure"
            s.version = "2.8.1"
            s.metadata = { "funding_uri" => "https://example.com/fund" }
          end
          SPEC
        ".bundle/config" => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
      }) do
        output = IO::Memory.new
        errors = IO::Memory.new
        code = Celerite::Commands.fund(output, errors, [] of String)
        code.should eq(0)
        errors.to_s.should eq("")
        output.to_s.should contain("* json_pure (2.8.1)")
        output.to_s.should contain("Funding: https://example.com/fund")
      end
    ensure
      if previous
        ENV["CELERITE_BRIDGE_SERVER"] = previous
      else
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
    end
  end

  it "prints a funding URI read from a PATH source gemspec" do
    server = File.expand_path("../assets/bridge/server.rb", __DIR__)
    previous = ENV["CELERITE_BRIDGE_SERVER"]?
    ENV["CELERITE_BRIDGE_SERVER"] = server
    begin
      with_project({
        "Gemfile"                        => "source \"https://rubygems.org\"\n\ngem \"example\", path: \"vendor/example\"\n",
        "Gemfile.lock"                   => "PATH\n  remote: vendor/example\n  specs:\n    example (1.0.0)\n\nGEM\n  remote: https://rubygems.org/\n  specs:\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  example!\n\nBUNDLED WITH\n   4.0.24\n",
        "vendor/example/example.gemspec" => <<-SPEC,
          Gem::Specification.new do |s|
            s.name = "example"
            s.version = "1.0.0"
            s.summary = "path funding probe"
            s.metadata = { "funding_uri" => "https://example.com/path-funding" }
          end
          SPEC
        "vendor/example/lib/example.rb" => "module Example; VERSION = \"1.0.0\"; end\n",
      }) do
        output = IO::Memory.new
        errors = IO::Memory.new
        code = Celerite::Commands.fund(output, errors, [] of String)
        code.should eq(0)
        errors.to_s.should eq("")
        output.to_s.should eq("* example (1.0.0)\n  Funding: https://example.com/path-funding\n")
      end
    ensure
      if previous
        ENV["CELERITE_BRIDGE_SERVER"] = previous
      else
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
    end
  end

  it "reports no funding when installed gems have no funding metadata" do
    server = File.expand_path("../assets/bridge/server.rb", __DIR__)
    previous = ENV["CELERITE_BRIDGE_SERVER"]?
    ENV["CELERITE_BRIDGE_SERVER"] = server
    begin
      with_project({
        "Gemfile"                                                         => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
        "Gemfile.lock"                                                    => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nBUNDLED WITH\n   4.0.24\n",
        "vendor/bundle/ruby/3.4.0/specifications/json_pure-2.8.1.gemspec" => "Gem::Specification.new do |s|\n  s.name = \"json_pure\"\n  s.version = \"2.8.1\"\nend\n",
        ".bundle/config"                                                  => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
      }) do
        output = IO::Memory.new
        errors = IO::Memory.new
        code = Celerite::Commands.fund(output, errors, [] of String)
        code.should eq(0)
        errors.to_s.should eq("")
        output.to_s.should eq("None of the installed gems you directly depend on are looking for funding.\n")
      end
    ensure
      if previous
        ENV["CELERITE_BRIDGE_SERVER"] = previous
      else
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
    end
  end
end
