require "./spec_helper"

private def with_unknown_switches_bridge(&block : ->)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    block.call
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def capture_switches(&block : IO, IO -> Int32)
  output = IO::Memory.new
  errors = IO::Memory.new
  code = block.call(output, errors)
  {code, output.to_s, errors.to_s}
end

private def checks_index_remote : String
  "file:///#{File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")}/"
end

private def check_project_lockfile(remote : String) : String
  <<-LOCK
GEM
  remote: #{remote}
  specs:
    json_pure (2.8.1)

PLATFORMS
  ruby

DEPENDENCIES
  json_pure

BUNDLED WITH
   4.0.24
LOCK
end

private def empty_project_lockfile(remote : String) : String
  <<-LOCK
GEM
  remote: #{remote}
  specs:

PLATFORMS
  ruby

DEPENDENCIES

BUNDLED WITH
   4.0.24
LOCK
end

describe "M7 option surface: unknown switches and check --gemfile" do
  it "check rejects an unknown switch before reading the project" do
    with_project({} of String => String) do
      code, out, err = capture_switches { |o, e| Celerite::Commands.check(o, e, ["--bogus-flag"]) }
      code.should eq(15)
      out.should eq("")
      err.should eq("Unknown switches \"--bogus-flag\"\n")
    end
  end

  it "check quotes each unknown switch and keeps the original token" do
    with_project({} of String => String) do
      code, _out, err = capture_switches { |o, e| Celerite::Commands.check(o, e, ["--bogus", "--other"]) }
      code.should eq(15)
      err.should eq("Unknown switches \"--bogus\", \"--other\"\n")

      code, _out, err = capture_switches { |o, e| Celerite::Commands.check(o, e, ["--gemfile=Missing.gemfile", "--bogus=1"]) }
      code.should eq(15)
      err.should eq("Unknown switches \"--bogus=1\"\n")
    end
  end

  it "list rejects unknown switches but keeps its documented switches" do
    with_project({} of String => String) do
      code, _out, err = capture_switches { |o, e| Celerite::Commands.list(o, e, ["--bogus", "--other"]) }
      code.should eq(15)
      err.should eq("Unknown switches \"--bogus\", \"--other\"\n")
    end
  end

  it "show only accepts --paths" do
    with_project({} of String => String) do
      code, _out, err = capture_switches { |o, e| Celerite::Commands.show_info("show", o, e, ["--bogus-flag"]) }
      code.should eq(15)
      err.should eq("Unknown switches \"--bogus-flag\"\n")

      code, _out, err = capture_switches { |o, e| Celerite::Commands.show_info("show", o, e, ["--format=json"]) }
      code.should eq(15)
      err.should eq("Unknown switches \"--format=json\"\n")
    end
  end

  it "info rejects --paths and only accepts --path/--version" do
    with_project({} of String => String) do
      code, _out, err = capture_switches { |o, e| Celerite::Commands.show_info("info", o, e, ["--paths"]) }
      code.should eq(15)
      err.should eq("Unknown switches \"--paths\"\nDid you mean?  \"--path\"\n")

      code, _out, err = capture_switches { |o, e| Celerite::Commands.show_info("info", o, e, ["--gemfile=Empty.gemfile"]) }
      code.should eq(15)
      err.should eq("Unknown switches \"--gemfile=Empty.gemfile\"\n")
    end
  end

  it "info without a gem name prints the reference argument error" do
    with_project({} of String => String) do
      code, out, err = capture_switches { |o, e| Celerite::Commands.show_info("info", o, e, ["--path"]) }
      code.should eq(15)
      out.should eq("")
      err.should eq("ERROR: \"bundle info\" was called with no arguments\nUsage: \"bundle info GEM [OPTIONS]\"\n")
    end
  end

  it "check --gemfile really switches the target Gemfile and restores ENV" do
    with_unknown_switches_bridge do
      remote = checks_index_remote
      missing_path_lockfile = <<-LOCK
PATH
  remote: vendor/missing_gem
  specs:
    missing_gem (0.1.0)

GEM
  remote: #{remote}
  specs:

PLATFORMS
  ruby

DEPENDENCIES
  missing_gem!

BUNDLED WITH
   4.0.24
LOCK
      with_project({
        ".bundle/config"     => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
        "Gemfile"            => "source \"#{remote}\"\n\ngem \"missing_gem\", path: \"vendor/missing_gem\"\n",
        "Gemfile.lock"       => missing_path_lockfile,
        "Empty.gemfile"      => "source \"#{remote}\"\n",
        "Empty.gemfile.lock" => empty_project_lockfile(remote),
      }) do
        previous = ENV["BUNDLE_GEMFILE"]?

        code, _out, err = capture_switches { |o, e| Celerite::Commands.check(o, e, [] of String) }
        code.should eq(1)
        err.should contain("missing_gem")

        code, out, err = capture_switches { |o, e| Celerite::Commands.check(o, e, ["--gemfile=Empty.gemfile"]) }
        code.should eq(0)
        out.should eq("The Gemfile's dependencies are satisfied\n")
        err.should eq("")

        code, out, err = capture_switches { |o, e| Celerite::Commands.check(o, e, ["--gemfile", "Empty.gemfile"]) }
        code.should eq(0)
        out.should eq("The Gemfile's dependencies are satisfied\n")
        err.should eq("")

        ENV["BUNDLE_GEMFILE"]?.should eq(previous)
      end
    end
  end
end
