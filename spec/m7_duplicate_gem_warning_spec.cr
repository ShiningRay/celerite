require "./spec_helper"

# task-124: a Gemfile that lists the same gem twice makes Bundler warn
# (`dsl.rb:307-323`). The reference prints that warning **once per command**: it
# evaluates a Gemfile at most once per process (`bundler.rb` `@definition ||=`)
# and its shell drops repeated identical messages (`ui/shell.rb:39-45`). Celerite
# evaluates the same Gemfile from several bridge processes per command, which
# used to replay the warning once per evaluation (measured: `check` 6x,
# `show`/`info` 3x, `list` 3x before this fix).
private DUP_INDEX = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private DUP_GEMFILE = <<-GEMFILE
source "#{DUP_INDEX}"

gem "json_pure"
gem "json_pure"
GEMFILE

# Verbatim reference output (4.0.24 and 2.7.2 agree; measured 2026-11-22).
private WARNING_LINES = [
  "Your Gemfile lists the gem json_pure (>= 0) more than once.",
  "You should probably keep only one of them.",
  "Remove any duplicate entries and specify the gem only once.",
  "While it's not a problem now, it could cause errors if you change the version of one of them later.",
]

private def duplicate_warning_count(stderr : String) : Int32
  stderr.scan("more than once").size
end

private def assert_one_warning(stderr : String, command : String) : Nil
  duplicate_warning_count(stderr).should eq(1)
  WARNING_LINES.each { |line| stderr.should contain(line) }
end

private def assert_no_warning(stderr : String, command : String) : Nil
  duplicate_warning_count(stderr).should eq(0)
end

# The warning is raised by the Ruby bridge (`Bundler::Dsl#eval_gemfile`), so the
# project needs a bridge server plus an isolated HOME/GEM_HOME, like every other
# M7 spec that evaluates a Gemfile.
private def with_dup_warning_project(files : Hash(String, String), & : String ->) : Nil
  with_project(files) do |dir|
    names = %w[HOME USERPROFILE GEM_HOME GEM_PATH BUNDLE_PATH CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB]
    previous = {} of String => String?
    names.each { |name| previous[name] = ENV[name]? }
    gems = File.join(dir, "gems")
    Dir.mkdir_p(gems)
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["GEM_HOME"] = gems
    ENV["GEM_PATH"] = gems
    ENV.delete("BUNDLE_PATH")
    ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    begin
      yield dir
    ensure
      previous.each do |name, value|
        if value
          ENV[name] = value
        else
          ENV.delete(name)
        end
      end
    end
  end
end

private def install_dup_project(dir : String) : Nil
  code, _, err = run_cli(["install"])
  code.should eq(0)
  assert_one_warning(err, "install")
end

describe "repeated Gemfile declarations (task-124)" do
  # One evaluation feeds `install`; the locked commands each re-evaluate the
  # Gemfile several times (check: 6 evaluations before the fix) but must still
  # print the warning once.
  it "warns once for install and every locked command" do
    with_dup_warning_project({"Gemfile" => DUP_GEMFILE}) do |dir|
      install_dup_project(dir)

      code, _, err = run_cli(["lock"])
      code.should eq(0)
      assert_one_warning(err, "lock")

      code, _, err = run_cli(["check"])
      code.should eq(0)
      assert_one_warning(err, "check")

      code, _, err = run_cli(["list"])
      code.should eq(0)
      assert_one_warning(err, "list")

      code, _, err = run_cli(["update"])
      code.should eq(0)
      assert_one_warning(err, "update")

      code, _, err = run_cli(["pristine"])
      code.should eq(0)
      assert_one_warning(err, "pristine")

      code, _, err = run_cli(["cache"])
      code.should eq(0)
      assert_one_warning(err, "cache")
    end
  end

  it "warns once without a lockfile" do
    with_dup_warning_project({"Gemfile" => DUP_GEMFILE}) do |dir|
      code, _, err = run_cli(["check"])
      code.should eq(1) # no lockfile: the reference reports missing gems
      assert_one_warning(err, "check")
    end
  end

  # `show`, `info` (cli/show.rb:13-17, cli/info.rb:11-15) and `exec`
  # (setup.rb:16/32) evaluate the Gemfile inside `Bundler.ui.silence`, so the
  # reference never prints the warning for them.
  it "silences the warning for show, info and exec" do
    with_dup_warning_project({"Gemfile" => DUP_GEMFILE}) do |dir|
      install_dup_project(dir)

      code, _, err = run_cli(["show"])
      code.should eq(0)
      assert_no_warning(err, "show")

      code, _, err = run_cli(["show", "json_pure"])
      code.should eq(0)
      assert_no_warning(err, "show json_pure")

      code, _, err = run_cli(["info", "json_pure"])
      code.should eq(0)
      assert_no_warning(err, "info json_pure")

      code, _, err = run_cli(["exec", "ruby", "-e", "puts 1"])
      code.should eq(0)
      assert_no_warning(err, "exec")
    end
  end

  # `bundle remove` reports the duplicate declarations of the Gemfile it is
  # about to rewrite: `Injector#remove` reaches `Bundler.definition`
  # (injector.rb:65) before the file is edited.
  it "warns once before rewriting the Gemfile on remove" do
    with_dup_warning_project({"Gemfile" => DUP_GEMFILE}) do |dir|
      install_dup_project(dir)

      code, _, err = run_cli(["remove", "json_pure"])
      code.should eq(0)
      assert_one_warning(err, "remove")
      File.read(File.join(dir, "Gemfile")).scan("json_pure").size.should eq(0)
    end
  end

  it "warns once for add" do
    with_dup_warning_project({"Gemfile" => DUP_GEMFILE}) do |dir|
      install_dup_project(dir)

      code, _, err = run_cli(["add", "thor"])
      code.should eq(0)
      assert_one_warning(err, "add")
    end
  end

  it "does not warn for a Gemfile without duplicates" do
    gemfile = "source \"#{DUP_INDEX}\"\n\ngem \"json_pure\"\n"
    with_dup_warning_project({"Gemfile" => gemfile}) do |dir|
      code, _, err = run_cli(["install"])
      code.should eq(0)
      assert_no_warning(err, "install")

      code, _, err = run_cli(["check"])
      code.should eq(0)
      assert_no_warning(err, "check")
    end
  end
end
