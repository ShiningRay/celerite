require "./spec_helper"
require "../src/celerite/cli"

describe Celerite::CLI do
  it "prints its version" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    Celerite::CLI.run(["version"], stdout, stderr).should eq(0)
    stdout.to_s.should eq("#{Celerite::VERSION}\n")
    stderr.to_s.should be_empty
  end

  it "prints help without arguments" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    Celerite::CLI.run([] of String, stdout, stderr).should eq(0)
    stdout.to_s.should contain("Usage:")
    stderr.to_s.should be_empty
  end

  it "fails fast for unimplemented dependency commands" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    Celerite::CLI.run(["install"], stdout, stderr).should eq(1)
    stderr.to_s.should contain("not implemented")
    stdout.to_s.should be_empty
  end
end
