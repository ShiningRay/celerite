require "./spec_helper"

# M7(1): `platform` must report the lockfile/Gemfile Ruby requirement and must
# print the reference mismatch message (exit 0) when the running Ruby does not
# satisfy it. It calls Celerite::Commands.platform directly to avoid the CLI
# dispatch/downloader link chain (OpenSSL 3 toolchain lacks EVP_MD_size here).
# `platform` validates the runtime (`bundler/cli/platform.rb:35-40`), and the
# validation needs the Ruby bridge; locate it explicitly because `with_project`
# changes the working directory away from the repository checkout.
private def with_platform_bridge(& : ->) : Nil
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

describe "M7 platform ruby requirement reporting" do
  it "prints the runtime mismatch without failing" do
    pending! "ruby not available" unless ruby_available?
    with_platform_bridge do
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
        # Reference `cli/platform.rb:35-40` rescues RubyVersionMismatch and prints
        # its message; it must never claim satisfaction here.
        out.should match(/Your Ruby version is \d+\.\d+\.\d+, but your Gemfile specified 3\.0\.0/)
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

  # Reference `cli/platform.rb:11-15`: without a lockfile the requirement comes
  # from `Bundler.definition.ruby_version#single_version_string`, which renders
  # only the requirement's version operand (`ruby ">= 3.1"` → "ruby 3.1").
  it "renders the Gemfile requirement's version operand without a lockfile" do
    pending! "ruby not available" unless ruby_available?
    with_platform_bridge do
      with_project({
        "Gemfile" => "source \"https://rubygems.org\"\n\nruby \">= 3.1\"\n\ngem \"json_pure\"\n",
      }) do
        output = IO::Memory.new
        code = Celerite::Commands.platform(output, [] of String)
        out = output.to_s
        code.should eq(0)
        out.should contain("Your Gemfile specifies a Ruby version requirement:")
        out.should contain("* ruby 3.1")
        out.should_not contain("ruby >= 3.1")

        parseable = IO::Memory.new
        Celerite::Commands.platform(parseable, ["--ruby"]).should eq(0)
        parseable.to_s.should eq("ruby 3.1\n")
      end
    end
  end
end
