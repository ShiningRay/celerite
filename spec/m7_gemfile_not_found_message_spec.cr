require "./spec_helper"

# task-171: `GemfileNotFound` opts into the repository-wide `word_wrap`
# (`src/celerite/errors.cr:259-267`, where `wrap?` returns `true`). That matches
# the reference for every `BundlerError`: `friendly_errors.rb:35` calls
# `Bundler.ui.error message, wrap: true`, and `ui/shell.rb:167-171 #word_wrap`
# re-breaks the line at the terminal width. task-168 claimed the opposite — that
# `wrap?` stayed `false` and long paths were printed unwrapped — and pinned that
# wrong shape; the examples below assert the rendered output instead.
#
# The message body itself stays a single interpolated string —
# `definition.rb:38`: `raise GemfileNotFound, "#{gemfile} not found"` — so only
# the *rendering* may span lines. The width is derived from the message under
# test (the lesson from task-137 `4ce6d51` and task-165): a hard-coded
# `THOR_COLUMNS` stops asserting the text as soon as the temp directory grows
# past it.
#
# `install --gemfile <missing>` is deliberately absent: there the reference never
# reaches `definition.rb:38`, it leaks an `Errno::ENOENT` (`bundler.rb:501`)
# with a backtrace and exits 1. That divergence is tracked separately in the
# task-168 evidence, not fixed here.
private def with_columns(columns : String, &) : Nil
  previous = ENV["THOR_COLUMNS"]?
  begin
    ENV["THOR_COLUMNS"] = columns
    yield
  ensure
    if previous
      ENV["THOR_COLUMNS"] = previous
    else
      ENV.delete("THOR_COLUMNS")
    end
  end
end

# A width wide enough to keep `message` on one line, derived from the message
# itself so the assertion survives a different temp-directory length.
private def wide_columns(message : String) : String
  (message.size + 20).to_s
end

# The path celerite reports: expanded against the project and separator-normalized
# (the reference hands `File.expand_path` output to `ui.error`, which prints it
# verbatim on Windows as forward slashes via its own normalization).
private def missing_gemfile_path(dir : String, gemfile : String) : String
  File.expand_path(gemfile, dir).gsub('\\', "/")
end

describe "GemfileNotFound message shape for a missing --gemfile" do
  it "prints `<expanded path> not found` as one line when the width allows it" do
    with_project({} of String => String) do |dir|
      path = missing_gemfile_path(dir, "missing/Gemfile")
      message = "#{path} not found"
      with_columns(wide_columns(message)) do
        code, out, err = run_cli(["check", "--gemfile", "missing/Gemfile"])
        code.should eq(10)
        out.should eq("")
        err.should eq("#{message}\n")
        err.lines.size.should eq(1)
        # The old defect was a literal "\n" baked into the message itself; a
        # wrap added by the renderer is fine, a message-level break is not.
        err.should_not contain("\nnot found\n")
      end
    end
  end

  it "keeps the same single-line body for check, lock, update and cache" do
    with_project({} of String => String) do |dir|
      path = missing_gemfile_path(dir, "missing/Gemfile")
      message = "#{path} not found"
      with_columns(wide_columns(message)) do
        {"check", "lock", "update", "cache"}.each do |command|
          code, out, err = run_cli([command, "--gemfile", "missing/Gemfile"])
          code.should eq(10), command
          out.should eq(""), command
          err.should eq("#{message}\n"), command
        end
      end
    end
  end

  it "normalizes Windows separators in the reported path" do
    with_project({} of String => String) do |dir|
      path = missing_gemfile_path(dir, "Missing.gemfile")
      message = "#{path} not found"
      with_columns(wide_columns(message)) do
        _code, _out, err = run_cli(["lock", "--gemfile=Missing.gemfile"])
        err.should eq("#{message}\n")
        err.should_not contain('\\')
      end
    end
  end

  it "participates in the shared word_wrap, re-breaking long lines like the reference" do
    # Reference: `friendly_errors.rb:35` -> `ui/shell.rb:167-171 #word_wrap`.
    Celerite::GemfileNotFound.new("probe").wrap?.should be_true

    with_project({} of String => String) do |dir|
      path = missing_gemfile_path(dir, "missing/Gemfile")
      message = "#{path} not found"
      # Half of the message is well below the expanded path, so the wrap must
      # break at the single space before `not found` — the shape the reference
      # produces for paths longer than the terminal width.
      columns = Math.max(10, message.size // 2)
      with_columns(columns.to_s) do
        code, out, err = run_cli(["check", "--gemfile", "missing/Gemfile"])
        code.should eq(10)
        out.should eq("")
        err.lines.size.should eq(2)
        err.lines.first.should eq(path)
        err.lines.last.should eq("not found")
      end
    end
  end
end
