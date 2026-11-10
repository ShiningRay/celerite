require "./spec_helper"

# M7(3): `console` must fail clearly when IRB is unavailable instead of
# pretending to run an interactive console. The full Bundler console is not
# implemented; this spec pins the documented unsupported path.
describe "M7 console" do
  it "fails clearly when IRB is not available" do
    ruby = Process.find_executable("ruby").not_nil!

    server = File.expand_path("../assets/bridge/server.rb", __DIR__)
    previous_server = ENV["CELERITE_BRIDGE_SERVER"]?
    previous_ruby = ENV["CELERITE_RUBY"]?
    previous_path = ENV["PATH"]?
    empty_dir = File.tempname("celerite-empty-path")
    Dir.mkdir_p(empty_dir)
    ENV["CELERITE_BRIDGE_SERVER"] = server
    ENV["CELERITE_RUBY"] = ruby
    begin
      ENV["PATH"] = empty_dir
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
        "Gemfile.lock" => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  x64-mingw-ucrt\n\nDEPENDENCIES\n  json_pure\n\nBUNDLED WITH\n   4.0.24\n",
      }) do
        output = IO::Memory.new
        errors = IO::Memory.new
        code = Celerite::Commands.console(output, errors, [] of String)
        code.should eq(127)
        output.to_s.should eq("")
        errors.to_s.should contain("bundle console requires IRB")
        errors.to_s.should contain("full interactive bundle console not implemented")
      end
    ensure
      if previous_path
        ENV["PATH"] = previous_path
      else
        ENV.delete("PATH")
      end
      if previous_server
        ENV["CELERITE_BRIDGE_SERVER"] = previous_server
      else
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
      if previous_ruby
        ENV["CELERITE_RUBY"] = previous_ruby
      else
        ENV.delete("CELERITE_RUBY")
      end
      FileUtils.rm_rf(empty_dir)
    end
  end
end
