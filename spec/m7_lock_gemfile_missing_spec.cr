require "./spec_helper"
require "../src/celerite/cli/commands"

# `lock --gemfile=<missing>`: the reference validates the file after Thor and
# raises GemfileNotFound (exit 10), printing `"<absolute path> not found"` on a
# single line (`definition.rb:38`). Before this guard Celerite leaked the
# bridge's Ruby Errno
# (`No such file or directory @ rb_sysopen - Missing.gemfile`, exit 1).
#
# The message body is single-line, but the *rendering* is word-wrapped at the
# terminal width (`ui/shell.rb:167-171`, migrated on the Celerite side in
# task-171). The temp project lives under `File.tempname`, so its absolute path
# can outgrow the default 80 columns on its own; pin the width from the message
# under test instead of hard-coding one (the lesson from task-137 `4ce6d51` and
# task-165). `with_project` returns the project directory as a full path, so no
# `Dir.current` lookup is needed.
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

# A width wide enough to keep `message` on one line, derived from the message.
private def wide_columns(message : String) : String
  (message.size + 20).to_s
end

describe "M7(2)/L157 lock --gemfile missing" do
  it "reports GemfileNotFound with the absolute path (exit 10)" do
    with_project({} of String => String) do |dir|
      expected = "#{File.expand_path("Missing.gemfile", dir).gsub('\\', "/")} not found"
      with_columns(wide_columns(expected)) do
        code, out, err = run_cli(["lock", "--gemfile=Missing.gemfile"])
        code.should eq(10)
        out.should eq("")
        err.should eq("#{expected}\n")
        err.lines.size.should eq(1)
      end
    end
  end
end
