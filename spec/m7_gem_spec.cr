require "./spec_helper"

# M7(3): `gem` scaffold must be usable (real module/version wiring, README/LICENSE,
# no TODO placeholders) and must be explicit about unsupported Bundler options.
describe "M7 gem scaffold" do
  it "generates a minimal but usable scaffold" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      code = Celerite::Commands.gem(output, errors, ["foo-bar"])
      code.should eq(0)
      output.to_s.should eq("Creating gem 'foo-bar'...\n")
      errors.to_s.should eq("")

      File.file?("foo-bar/foo-bar.gemspec").should be_true
      File.file?("foo-bar/lib/foo_bar.rb").should be_true
      File.file?("foo-bar/README.md").should be_true
      File.file?("foo-bar/LICENSE.txt").should be_true
      File.file?("foo-bar/Gemfile").should be_true

      gemspec = File.read("foo-bar/foo-bar.gemspec")
      gemspec.should contain("spec.name = \"foo-bar\"")
      gemspec.should contain("require_relative \"lib/foo_bar\"")
      gemspec.should contain("spec.version = FooBar::VERSION")
      gemspec.should contain("spec.summary = \"Ruby gem foo-bar\"")
      gemspec.should contain("spec.required_ruby_version = \">= 3.0.0\"")
      gemspec.should_not contain("TODO")

      lib_file = File.read("foo-bar/lib/foo_bar.rb")
      lib_file.should contain("module FooBar")
      lib_file.should contain("VERSION = \"0.1.0\"")
    end
  end

  it "warns that option-specific scaffolding is unsupported" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      code = Celerite::Commands.gem(output, errors, ["widget", "--test"])
      code.should eq(0)
      errors.to_s.should contain("bundle gem options not fully supported by Celerite: --test")
      errors.to_s.should contain("Generating a minimal scaffold only")
      File.file?("widget/widget.gemspec").should be_true
    end
  end

  it "rejects a missing gem name" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, [] of String).should eq(1)
      errors.to_s.should eq("Please provide a gem name\n")
    end
  end

  it "rejects an existing directory" do
    with_project({"taken/.keep" => ""}) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, ["taken"]).should eq(1)
      errors.to_s.should eq("Directory taken already exists\n")
    end
  end
end
