require "./spec_helper"

# task-168: the reference raises `GemfileNotFound` from `definition.rb:38` with
# a *single* interpolated string — `raise GemfileNotFound, "#{gemfile} not
# found"` — and the two-line rendering seen on wide paths is produced later by
# `bundler/ui/shell.rb:167-171 #word_wrap`, not by the message itself. Celerite
# used to hard-code the second line, which diverged from the reference for every
# path short enough not to be re-wrapped.
#
# Declared difference: `GemfileNotFound` does not opt into wrapping
# (`wrap?` stays false), so a path long enough to exceed the terminal width is
# printed on one line instead of being re-broken like the reference. The last
# example pins that shape on purpose so the difference cannot drift silently.
describe "GemfileNotFound message shape for a missing --gemfile" do
  it "prints `<expanded path> not found` on exactly one line" do
    with_project({} of String => String) do |dir|
      code, out, err = run_cli(["check", "--gemfile", "missing/Gemfile"])
      code.should eq(10)
      out.should eq("")
      expected = "#{dir.gsub('\\', "/")}/missing/Gemfile not found\n"
      err.should eq(expected)
      err.lines.size.should eq(1)
      err.should_not contain("\nnot found")
    end
  end

  it "keeps the same single line for check, lock, update and cache" do
    with_project({} of String => String) do |dir|
      expected = "#{dir.gsub('\\', "/")}/missing/Gemfile not found\n"
      # `install --gemfile <missing>` is deliberately absent: there the reference
      # never reaches `definition.rb:38`, it leaks an `Errno::ENOENT`
      # (`bundler.rb:501`) with a backtrace and exits 1. That divergence is
      # tracked separately in the task-168 evidence, not fixed here.
      {"check", "lock", "update", "cache"}.each do |command|
        code, out, err = run_cli([command, "--gemfile", "missing/Gemfile"])
        code.should eq(10), command
        out.should eq(""), command
        err.should eq(expected), command
      end
    end
  end

  it "normalizes Windows separators in the reported path" do
    with_project({} of String => String) do |dir|
      _code, _out, err = run_cli(["lock", "--gemfile=Missing.gemfile"])
      err.should contain(File.expand_path("Missing.gemfile", dir).gsub('\\', "/"))
      err.should_not contain('\\')
    end
  end

  it "does not re-wrap a path longer than the terminal width (declared difference)" do
    with_project({} of String => String) do |dir|
      long = "missing/" + ("x" * 60) + "/Gemfile"
      previous = ENV["THOR_COLUMNS"]?
      ENV["THOR_COLUMNS"] = "40"
      begin
        code, _out, err = run_cli(["check", "--gemfile", long])
        code.should eq(10)
        # The reference would break this at 40 columns; celerite emits one line.
        err.should eq("#{dir.gsub('\\', "/")}/#{long} not found\n")
        err.lines.size.should eq(1)
      ensure
        if previous
          ENV["THOR_COLUMNS"] = previous
        else
          ENV.delete("THOR_COLUMNS")
        end
      end
    end
  end
end
