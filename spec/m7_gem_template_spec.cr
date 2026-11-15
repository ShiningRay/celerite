require "./spec_helper"

# The frozen expectation comes from running the 4.0.24 oracle with an isolated
# git identity (`GIT_CONFIG_GLOBAL` pointing at a fixture config), so the ten
# files are byte-identical to `bundle gem foogem` modulo the live author/email
# values, which depend on the repository's git config.
private def gem_template_fixture : String
  File.expand_path(File.join(__DIR__, "fixtures", "gem-template", "foogem"))
end

private def gem_template_files : Array(String)
  [
    "Gemfile",
    "lib/foogem.rb",
    "lib/foogem/version.rb",
    "sig/foogem.rbs",
    "foogem.gemspec",
    "Rakefile",
    "README.md",
    "bin/console",
    "bin/setup",
    ".gitignore",
  ]
end

private def gem_git_config(key : String) : String
  output = IO::Memory.new
  Process.run("git", ["config", key], output: output, error: IO::Memory.new)
  output.to_s.chomp
end

private def gem_expected_author : String
  value = gem_git_config("user.name")
  value.empty? ? "TODO: Write your name" : value
end

private def gem_expected_email : String
  value = gem_git_config("user.email")
  value.empty? ? "TODO: Write your email address" : value
end

describe "M7(3) bundle gem default scaffold" do
  it "writes the ten 4.0.24 files and prints the reference output" do
    with_project({} of String => String) do |dir|
      code, out, err = run_cli(["gem", "foogem"])
      code.should eq(0)

      target = File.join(dir, "foogem")
      lines = out.lines
      lines[0].should eq("Creating gem 'foogem'...")
      lines[1].should eq("")
      lines[2].should eq("Initializing git repo in #{target.gsub('\\', "/")}")

      gem_template_files.each_with_index do |relative, index|
        lines[3 + index].should eq("      create  foogem/#{relative}")

        generated = File.read(File.join(target, relative)).gsub("\r\n", "\n")
        expected = File.read(File.join(gem_template_fixture, relative)).gsub("\r\n", "\n")
        if relative == "foogem.gemspec"
          expected = expected
            .gsub(/spec\.authors = \[.*\]/, "spec.authors = [#{gem_expected_author.inspect}]")
            .gsub(/spec\.email = \[.*\]/, "spec.email = [#{gem_expected_email.inspect}]")
        end
        generated.should eq(expected)
      end

      lines[13].should eq("")
      lines[14].should eq(
        "Gem 'foogem' was successfully created. For more information on making a RubyGem visit https://guides.rubygems.org/make-your-own-gem/"
      )
      lines.size.should eq(15)
      err.should_not contain("fatal")
    end
  end

  it "rejects multiple positionals like Thor (exit 15)" do
    with_project({} of String => String) do
      code, out, err = run_cli(["gem", "a", "b"])
      code.should eq(15)
      out.should be_empty
      err.lines[0].should eq(%(ERROR: "bundle gem" was called with arguments ["a", "b"]))
      err.lines[1].should eq(%(Usage: "bundle gem NAME [OPTIONS]"))
    end
  end

  it "refuses to overwrite an existing file with the same name (exit 32)" do
    with_project({} of String => String) do
      File.write("blocked", "x")
      code, _out, err = run_cli(["gem", "blocked"])
      code.should eq(32)
      err.should contain(
        "Couldn't create a new gem named `blocked` because there's an existing file named `blocked`."
      )
    end
  end
end
