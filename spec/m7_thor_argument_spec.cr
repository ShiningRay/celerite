require "./spec_helper"

# M7(2): Thor-level argument handling. The reference parses options before a
# command runs, so a non-numeric value for a `:numeric` option and positional
# arguments handed to a command that takes none both fail with exit 15 and no
# command output at all.
private THOR_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gem "json_pure"
  GEMFILE

describe "M7 Thor-level argument validation" do
  it "rejects a non-numeric --jobs before installing" do
    with_project({"Gemfile" => THOR_GEMFILE}) do |dir|
      code, out, err = run_cli(["install", "--jobs", "bogus"])
      code.should eq(15)
      out.should eq("")
      err.should eq("Expected numeric value for '--jobs'; got \"bogus\"\n")
      File.exists?(File.join(dir, "Gemfile.lock")).should be_false
    end
  end

  it "rejects a non-numeric -j and --retry with the canonical switch name" do
    with_project({"Gemfile" => THOR_GEMFILE}) do
      code, out, err = run_cli(["install", "-j", "many"])
      code.should eq(15)
      out.should eq("")
      err.should eq("Expected numeric value for '--jobs'; got \"many\"\n")

      code, out, err = run_cli(["install", "--retry=bogus"])
      code.should eq(15)
      out.should eq("")
      err.should eq("Expected numeric value for '--retry'; got \"bogus\"\n")
    end
  end

  it "rejects positional arguments for commands that take none" do
    with_project({"Gemfile" => THOR_GEMFILE}) do
      code, out, err = run_cli(["clean", "json_pure"])
      code.should eq(15)
      out.should eq("")
      err.should eq("ERROR: \"bundle clean\" was called with arguments [\"json_pure\"]\n" \
                    "Usage: \"bundle clean [OPTIONS]\"\n")

      # `lock`, `env`, `licenses` and `issue` have no `[OPTIONS]` suffix in
      # their reference usage line.
      code, out, err = run_cli(["lock", "a", "b"])
      code.should eq(15)
      out.should eq("")
      err.should eq("ERROR: \"bundle lock\" was called with arguments [\"a\", \"b\"]\n" \
                    "Usage: \"bundle lock\"\n")

      code, _out, err = run_cli(["issue", "extra"])
      code.should eq(15)
      err.should eq("ERROR: \"bundle issue\" was called with arguments [\"extra\"]\n" \
                    "Usage: \"bundle issue\"\n")
    end
  end

  it "keeps positional arguments for commands that take a gem name" do
    with_project({"Gemfile" => THOR_GEMFILE}) do
      # `pristine` accepts gem names, so this is a gem lookup failure, not a
      # Thor argument error.
      code, _out, err = run_cli(["pristine", "extra"])
      code.should_not eq(15)
      err.should_not contain("was called with arguments")
    end
  end

  it "reports `show --outdated` as removed with the reference wording" do
    with_project({"Gemfile" => THOR_GEMFILE}) do
      code, out, err = run_cli(["show", "--outdated"])
      code.should eq(15)
      out.should eq("")
      # `cli.rb` L354-357 wraps the message to the terminal width; at 80
      # columns the wrap lands between `bundle show` and `--verbose`.
      err.should contain("the `--outdated` flag to `bundle show` has been removed in favor of `bundle show")
      err.should contain("--verbose`")
    end
  end

  it "reports an unknown plugin subcommand without the parent prefix" do
    with_project({"Gemfile" => THOR_GEMFILE}) do
      code, out, err = run_cli(["plugin", "extra"])
      code.should eq(15)
      out.should eq("")
      err.should eq("Could not find command \"extra\".\n")
    end
  end
end
