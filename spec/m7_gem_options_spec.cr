require "./spec_helper"

# M7(3) task-27: the `bundle gem` option surface (4.0.24 reference). The
# end-to-end template comparison lives in the `gem-*` differential fixtures;
# these examples pin help text, enum/unknown rejection and the rendered
# branches without spawning bundler.
describe "M7 gem options" do
  it "prints the pinned 4.0.24 manpage" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, ["--help"]).should eq(0)
      output.to_s.should eq(Celerite::GemTemplate.help_text("4.0.24"))
      errors.to_s.should be_empty
    end
  end

  it "renders test/ci/linter/license/exe branches" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      args = ["foo", "--test=rspec", "--linter=rubocop", "--ci=github", "--mit",
              "--exe", "--no-coc", "--no-changelog", "--no-bundle",
              "--github-username=testuser", "--no-git"]
      Celerite::Commands.gem(output, errors, args).should eq(0)
      errors.to_s.should be_empty
      output.to_s.should contain("MIT License enabled in config")
      output.to_s.should contain("RuboCop enabled in config")

      [
        "foo/.github/workflows/main.yml",
        "foo/.rubocop.yml",
        "foo/LICENSE.txt",
        "foo/exe/foo",
        "foo/spec/foo_spec.rb",
        "foo/.rspec",
      ].each { |relative| File.file?(relative).should be_true }

      File.read("foo/foo.gemspec").should contain("github.com/testuser/foo")
      File.read("foo/.github/workflows/main.yml").should contain("name: Ruby")
    end
  end

  it "renders a Rust extension scaffold" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      args = ["foo", "--ext=rust", "--no-test", "--no-ci", "--no-linter",
              "--no-git", "--no-coc", "--no-changelog", "--no-bundle", "--no-mit"]
      Celerite::Commands.gem(output, errors, args).should eq(0)
      File.file?("foo/Cargo.toml").should be_true
      File.file?("foo/ext/foo/src/lib.rs").should be_true
      File.read("foo/foo.gemspec").should contain(%(spec.extensions = ["ext/foo/extconf.rb"]))
    end
  end

  it "rejects unknown switches and multiple positionals" do
    with_project({} of String => String) do
      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, ["foo", "--bogus"]).should eq(15)
      errors.to_s.should eq(%(Unknown switches "--bogus"\n))

      output = IO::Memory.new
      errors = IO::Memory.new
      Celerite::Commands.gem(output, errors, ["foo", "bar"]).should eq(15)
      errors.to_s.should contain(%(ERROR: "bundle gem" was called with arguments ["foo", "bar"]))
    end
  end
end
