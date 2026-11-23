require "./spec_helper"
require "../src/celerite/cli/commands"

# `lock --gemfile=<missing>`: the reference validates the file after Thor and
# raises GemfileNotFound (exit 10), printing `"<absolute path> not found"` on a
# single line (`definition.rb:38`). Before this guard Celerite leaked the
# bridge's Ruby Errno
# (`No such file or directory @ rb_sysopen - Missing.gemfile`, exit 1).
describe "M7(2)/L157 lock --gemfile missing" do
  it "reports GemfileNotFound with the absolute path (exit 10)" do
    with_project({} of String => String) do
      code, out, err = run_cli(["lock", "--gemfile=Missing.gemfile"])
      expected = "#{File.expand_path("Missing.gemfile", Dir.current).gsub('\\', "/")} not found\n"
      code.should eq(10)
      out.should eq("")
      err.should eq(expected)
    end
  end
end
