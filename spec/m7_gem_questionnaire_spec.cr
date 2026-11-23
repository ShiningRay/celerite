require "./spec_helper"

# `bundle gem` questionnaire (task-189).
#
# Reference: bundler/cli/gem.rb of 4.0.24. The six questions run in this order
# (`bundle gem` in cli.rb:595-620 calls them): test framework (:118, :322-347),
# CI (:157, :362-391), MIT licence (:173, :299-310), code of conduct (:182),
# changelog (:191), linter (:203, :393-426). Answers are persisted with
# `Bundler.settings.set_global("gem.<key>", ...)`, which lands in the
# user-level `.bundle/config` as `BUNDLE_GEM__*` (config.cr:401-433).
#
# The prompts come from Thor: `Bundler.ui.ask` -> `Thor::Shell::Basic#ask_simply`
# (vendor/thor/lib/thor/shell/basic.rb:330-345) prints the statement plus one
# trailing space, `yes?` (:149-151) prints `"<prompt> y/(n): "`, and `say`
# (:98-106) only adds the newline when the message does not already end with
# one. Those details are what the literal expectations below pin; they are also
# why the differential fixture feeds a plain pipe (see
# fixtures/differential/gem-questionnaire/env).

# Clears the gem.* settings the command reads and points both home variables at
# `home`, so no example can touch the developer profile or inherit its config.
private def with_isolated_gem_settings(home : String, &) : Nil
  keys = ["HOME", "USERPROFILE", "BUNDLE_USER_CONFIG", "BUNDLE_USER_HOME",
          "BUNDLE_CONFIG", "BUNDLE_GEM__TEST", "BUNDLE_GEM__CI", "BUNDLE_GEM__MIT",
          "BUNDLE_GEM__COC", "BUNDLE_GEM__CHANGELOG", "BUNDLE_GEM__LINTER",
          "BUNDLE_GEM__RUBOCOP"]
  saved = keys.map { |key| {key, ENV[key]?} }
  begin
    keys.each { |key| ENV.delete(key) }
    ENV["HOME"] = home
    ENV["USERPROFILE"] = home
    yield
  ensure
    saved.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def run_gem(dir : String, args : Array(String), answers : String) : {Int32, String, String}
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  input = IO::Memory.new(answers)
  code = Celerite::Commands.gem(stdout, stderr, args, input)
  {code, stdout.to_s, stderr.to_s}
end

private def gem_config(dir : String) : String
  path = File.join(dir, "home", ".bundle", "config")
  File.exists?(path) ? File.read(path) : ""
end

private def question_order(output : String) : Array(Int32)
  [
    "Enter a test framework. rspec/minitest/test-unit/(none): ",
    "Enter a CI service. github/gitlab/circle/(none): ",
    "Do you want to license your code permissively under the MIT license? y/(n): ",
    "Do you want to include a code of conduct in gems you generate? y/(n): ",
    "Do you want to include a changelog? y/(n): ",
    "Enter a linter. rubocop/standard/(none): ",
  ].map do |prompt|
    index = output.index(prompt)
    index.nil? ? -1 : index
  end
end

describe "M7 gem questionnaire (task-189)" do
  it "asks the six questions in reference order and persists every answer" do
    with_project({} of String => String) do |dir|
      home = File.join(dir, "home")
      Dir.mkdir_p(home)
      with_isolated_gem_settings(home) do
        code, output, err = run_gem(dir, ["basicgem", "--no-git"], "rspec\ngithub\ny\nn\ny\nrubocop\n")

        code.should eq(0)
        err.should eq("")
        output.starts_with?("Creating gem 'basicgem'...\n").should be_true

        order = question_order(output)
        order.each { |index| index.should be >= 0 }
        order.should eq(order.sort)

        # Thor semantics: the prompt keeps one trailing space, and the boolean
        # prompt is written with `y/(n): `; the follow-up line starts right
        # after that space.
        output.should contain("Enter a test framework. rspec/minitest/test-unit/(none): \n" \
                              "Do you want to set up continuous integration for your gem?")
        output.should contain("Do you want to license your code permissively under the MIT license? " \
                              "y/(n): MIT License enabled in config\n")
        output.should contain("Do you want to include a changelog? y/(n): Changelog enabled in config\n")
        output.should contain("Enter a linter. rubocop/standard/(none): RuboCop enabled in config\n")
        output.should_not contain("Code of conduct enabled in config")

        gem_config(dir).should eq("---\n" \
                                  "BUNDLE_GEM__TEST: \"rspec\"\n" \
                                  "BUNDLE_GEM__CI: \"github\"\n" \
                                  "BUNDLE_GEM__MIT: \"true\"\n" \
                                  "BUNDLE_GEM__COC: \"false\"\n" \
                                  "BUNDLE_GEM__CHANGELOG: \"true\"\n" \
                                  "BUNDLE_GEM__LINTER: \"rubocop\"\n")

        gem = File.join(dir, "basicgem")
        %w[.rspec .rubocop.yml CHANGELOG.md LICENSE.txt Rakefile
          .github/workflows/main.yml spec/spec_helper.rb spec/basicgem_spec.rb
          sig/basicgem.rbs].each do |relative|
          File.exists?(File.join(gem, relative)).should be_true
        end
        File.read(File.join(gem, ".rspec")).should contain("--require spec_helper")
        File.read(File.join(gem, ".rubocop.yml")).should contain("TargetRubyVersion")
        File.read(File.join(gem, "spec", "spec_helper.rb")).should contain("RSpec.configure")
        File.read(File.join(gem, "Gemfile")).should contain(%(gem "rspec", "~> 3.0"))
        File.read(File.join(gem, "CHANGELOG.md")).should contain("## [Unreleased]")
      end
    end
  end

  it "suppresses every question when the settings are already persisted" do
    with_project({} of String => String) do |dir|
      home = File.join(dir, "home")
      Dir.mkdir_p(File.join(home, ".bundle"))
      File.write(File.join(home, ".bundle", "config"), "---\n" \
                                                       "BUNDLE_GEM__TEST: \"rspec\"\n" \
                                                       "BUNDLE_GEM__CI: \"github\"\n" \
                                                       "BUNDLE_GEM__MIT: \"false\"\n" \
                                                       "BUNDLE_GEM__COC: \"false\"\n" \
                                                       "BUNDLE_GEM__CHANGELOG: \"false\"\n" \
                                                       "BUNDLE_GEM__LINTER: \"false\"\n")
      with_isolated_gem_settings(home) do
        code, output, err = run_gem(dir, ["quietgem", "--no-git"], "")

        code.should eq(0)
        err.should eq("")
        # A persisted value (including the literal "false") replaces the
        # question: gem.rb:325-337 only asks when `settings["gem.test"].to_s`
        # is empty.
        question_order(output).each { |index| index.should eq(-1) }
        output.should_not contain("enabled in config")

        gem = File.join(dir, "quietgem")
        File.exists?(File.join(gem, "LICENSE.txt")).should be_false
        File.exists?(File.join(gem, ".rubocop.yml")).should be_false
        File.exists?(File.join(gem, "CHANGELOG.md")).should be_false
        File.exists?(File.join(gem, ".rspec")).should be_true
        File.exists?(File.join(gem, ".github", "workflows", "main.yml")).should be_true
        # Nothing was rewritten: the file keeps exactly the six lines.
        gem_config(dir).lines.select(&.starts_with?("BUNDLE_GEM__")).size.should eq(6)
      end
    end
  end

  it "keeps --no-test/--no-ci/--no-linter silent and leaves those settings unset" do
    with_project({} of String => String) do |dir|
      home = File.join(dir, "home")
      Dir.mkdir_p(home)
      with_isolated_gem_settings(home) do
        code, output, err = run_gem(dir, ["basicgem", "--no-git", "--no-test", "--no-ci", "--no-linter"],
          "n\nn\nn\n")

        code.should eq(0)
        err.should eq("")
        output.should_not contain("Enter a test framework.")
        output.should_not contain("Enter a CI service.")
        output.should_not contain("Enter a linter.")
        output.should_not contain("enabled in config")

        config = gem_config(dir)
        config.should contain(%(BUNDLE_GEM__MIT: "false"))
        config.should contain(%(BUNDLE_GEM__COC: "false"))
        config.should contain(%(BUNDLE_GEM__CHANGELOG: "false"))
        config.should_not contain("BUNDLE_GEM__TEST")
        config.should_not contain("BUNDLE_GEM__CI")
        config.should_not contain("BUNDLE_GEM__LINTER")

        gem = File.join(dir, "basicgem")
        File.exists?(File.join(gem, "LICENSE.txt")).should be_false
        File.exists?(File.join(gem, ".rspec")).should be_false
        File.exists?(File.join(gem, ".rubocop.yml")).should be_false
      end
    end
  end

  it "skips only the question whose persisted answer is already set" do
    with_project({} of String => String) do |dir|
      home = File.join(dir, "home")
      Dir.mkdir_p(File.join(home, ".bundle"))
      File.write(File.join(home, ".bundle", "config"), "---\nBUNDLE_GEM__MIT: \"false\"\n")
      with_isolated_gem_settings(home) do
        code, output, _ = run_gem(dir, ["basicgem", "--no-git"], "rspec\ngithub\nn\ny\nrubocop\n")

        code.should eq(0)
        output.should_not contain("Do you want to license your code")
        output.should_not contain("MIT License enabled in config")
        # The five remaining questions are still asked, once each.
        question_order(output).reject { |index| index < 0 }.size.should eq(5)
        File.exists?(File.join(dir, "basicgem", "LICENSE.txt")).should be_false
        File.read(File.join(dir, "basicgem", "CHANGELOG.md")).should contain("## [Unreleased]")
      end
    end
  end
end
