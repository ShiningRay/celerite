require "./spec_helper"

# M7(3): `bundle gem` now follows the 4.0.24 scaffold (byte-level comparison
# lives in m7_gem_template_spec); these assertions pin the argument handling,
# unsupported-option policy and overwrite semantics that used to be
# Celerite-specific.
describe "M7 gem scaffold" do
  it "generates the reference scaffold for a hyphenated name" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, ["foo-bar"]).should eq(0)

      lines = output.to_s.lines
      lines[0].should eq("Creating gem 'foo-bar'...")
      lines[1].should eq("")
      lines[2].should eq("Initializing git repo in #{File.join(Dir.current, "foo-bar").gsub('\\', "/")}")
      lines.size.should eq(15)

      [
        "Gemfile",
        "lib/foo/bar.rb",
        "lib/foo/bar/version.rb",
        "sig/foo/bar.rbs",
        "foo-bar.gemspec",
        "Rakefile",
        "README.md",
        "bin/console",
        "bin/setup",
        ".gitignore",
      ].each_with_index do |relative, index|
        lines[3 + index].should eq("      create  foo-bar/#{relative}")
        File.file?(File.join("foo-bar", relative)).should be_true
      end

      gemspec = File.read("foo-bar/foo-bar.gemspec")
      gemspec.should contain(%(spec.name = "foo-bar"))
      gemspec.should contain(%(spec.version = Foo::Bar::VERSION))
      gemspec.should contain(%(require_relative "lib/foo/bar/version"))
      gemspec.should contain(%(spec.required_ruby_version = ">= 3.2.0"))
      library = File.read("foo-bar/lib/foo/bar.rb")
      library.should contain("module Foo")
      library.should contain("module Bar")
      library.should contain("class Error < StandardError; end")
    end
  end

  it "rejects an enum value with Thor's exact validation error" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, ["widget", "--test=minitestx"]).should eq(15)
      errors.to_s.should eq("Expected '--test' to be one of rspec, minitest, test-unit; got minitestx\n")
      File.exists?("widget").should be_false
    end
  end

  it "rejects a missing gem name with Thor's usage error" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, [] of String).should eq(15)
      errors.to_s.should eq(
        %(ERROR: "bundle gem" was called with no arguments\n) +
        %(Usage: "bundle gem NAME [OPTIONS]"\n)
      )
    end
  end

  it "writes into an existing directory like the reference" do
    with_project({"taken/.keep" => ""}) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, ["taken"]).should eq(0)
      File.file?("taken/taken.gemspec").should be_true
      File.file?("taken/.keep").should be_true
    end
  end
end
