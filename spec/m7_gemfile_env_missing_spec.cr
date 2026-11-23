require "./spec_helper"
require "../src/celerite/cli/commands"

# `BUNDLE_GEMFILE=<missing path>`: the reference does not validate the path in
# `SharedHelpers.find_gemfile` (shared_helpers.rb:263-267); validation happens
# later in `Definition.build` (definition.rb:38), which raises GemfileNotFound
# with the *expanded* path followed by ` not found` on a single line (exit 10).
# Celerite used to leak the bridge's Ruby Errno instead
# (`No such file or directory @ rb_sysopen - nope/Gemfile`, exit 1), and
# `bundle platform` did not check at all (exit 0).
#
# Restores every ENV key the command touches, so a failure cannot leak state
# into the other examples.
#
# `columns` pins `THOR_COLUMNS`, which is the width `GemfileNotFound` is
# word-wrapped at (ui/shell.rb:167-169). Derive it from the message under test
# — a fixed number would stop asserting the text as soon as the temp directory
# happens to grow past it.
private def with_gemfile_env(values : Hash(String, String?), columns : String, &) : Nil
  keys = (["BUNDLE_GEMFILE", "THOR_COLUMNS"] + values.keys).uniq
  saved = keys.map { |key| {key, ENV[key]?} }
  begin
    ENV["THOR_COLUMNS"] = columns
    values.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
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

private def missing_gemfile_env_message : String
  "#{File.expand_path(File.join(Dir.current, "nope", "Gemfile")).gsub('\\', "/")} not found\n"
end

# A width wide enough to keep `message` on one line, derived from the message
# itself so the assertions survive a different temp-directory length.
private def wide_columns(message : String) : String
  (message.size + 20).to_s
end

describe "M7 gemfile env missing (task-165)" do
  it "raises GemfileNotFound (exit 10) with the expanded path for list" do
    with_project({} of String => String) do
      with_gemfile_env({"BUNDLE_GEMFILE" => "nope/Gemfile"}, wide_columns(missing_gemfile_env_message)) do
        code, out, err = run_cli(["list"])
        code.should eq(10)
        out.should eq("")
        err.should eq(missing_gemfile_env_message)
      end
    end
  end

  it "raises GemfileNotFound (exit 10) for check" do
    with_project({} of String => String) do
      with_gemfile_env({"BUNDLE_GEMFILE" => "nope/Gemfile"}, wide_columns(missing_gemfile_env_message)) do
        code, out, err = run_cli(["check"])
        code.should eq(10)
        out.should eq("")
        err.should eq(missing_gemfile_env_message)
      end
    end
  end

  # The regression this task exists for: before the fix `platform` printed the
  # platform report and exited 0, i.e. it never validated the Gemfile.
  it "raises GemfileNotFound (exit 10) for platform instead of printing a report" do
    with_project({} of String => String) do
      with_gemfile_env({"BUNDLE_GEMFILE" => "nope/Gemfile"}, wide_columns(missing_gemfile_env_message)) do
        code, out, err = run_cli(["platform"])
        code.should eq(10)
        out.should eq("")
        err.should eq(missing_gemfile_env_message)
      end
    end
  end

  it "never leaks the bridge Errno or an internal error for a missing BUNDLE_GEMFILE" do
    with_project({"Gemfile" => "source \"https://rubygems.org/\"\n"}) do
      with_gemfile_env({"BUNDLE_GEMFILE" => "nope/Gemfile"}, wide_columns(missing_gemfile_env_message)) do
        _, _, err = run_cli(["list"])
        expanded = File.expand_path(File.join(Dir.current, "nope", "Gemfile")).gsub('\\', "/")
        err.should contain(expanded)
        err.should contain("not found")
        err.should_not contain("rb_sysopen")
        err.should_not contain("internal error")
      end
    end
  end

  it "does not report a missing Gemfile when BUNDLE_GEMFILE points at an existing file" do
    with_project({"deps.gemfile" => "source \"https://rubygems.org/\"\n"}) do
      with_gemfile_env({"BUNDLE_GEMFILE" => "deps.gemfile"}, wide_columns(missing_gemfile_env_message)) do
        definition = Celerite::Definition.build
        definition.gemfile_path.should eq("deps.gemfile")
      end
    end
  end

  it "keeps the no-BUNDLE_GEMFILE wording when no Gemfile can be located" do
    with_project({} of String => String) do
      with_gemfile_env({"BUNDLE_GEMFILE" => nil}, wide_columns(missing_gemfile_env_message)) do
        code, out, err = run_cli(["list"])
        code.should eq(10)
        out.should eq("")
        err.should eq("Could not locate Gemfile\n")
      end
    end
  end

  # Corrected by task-171: this example used to pin the *two-line* wording
  # (`"#{path}\nnot found\n"`) that predated task-168's `1fc1b9d`, which removed
  # the literal `\n` from the message. The message body is single-line again;
  # wrapping is the renderer's job (`ui/shell.rb:167-171`), so the width here is
  # wide enough to keep it on one line.
  it "keeps the --gemfile switch wording (single line) unchanged" do
    with_project({} of String => String) do
      with_gemfile_env({"BUNDLE_GEMFILE" => nil}, wide_columns(missing_gemfile_env_message)) do
        code, out, err = run_cli(["lock", "--gemfile=Missing.gemfile"])
        expected = "#{File.expand_path("Missing.gemfile", Dir.current).gsub('\\', "/")} not found"
        code.should eq(10)
        out.should eq("")
        err.should eq("#{expected}\n")
        err.lines.size.should eq(1)
      end
    end
  end
end
