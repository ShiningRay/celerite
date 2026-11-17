require "./spec_helper"
require "../src/celerite"

# Reference anchors for this round:
# * `bundler/cli.rb:155-185 #help` — alias resolution, plugin delegation, then
#   `puts File.read("#{man_path}/#{File.basename(man_page)}.ronn")` when `man`
#   is unavailable, and `super` (Thor `command_help`) for names without a page.
# * `bundler/vendor/thor/lib/thor.rb:252-280 command_help` — the fallback body
#   (`Usage:` + banner + class options + description).
# * `bundler/vendor/thor/lib/thor/base.rb:619-626 handle_argument_error` — two
#   lines, no trailing blank line.
# * `bundler/cli.rb:16-53 all_aliases` — `c`/`i`/`ls`/`pack`/`package`/`e`/`ex`/`exe`.
#
# The vendored pages live under `assets/man/<profile>/`; Ruby writes them
# through a text-mode IO, so the reference emits CRLF on Windows and we mirror
# that in `Manpages.normalize_newlines`.
private def man_text(name : String, profile : String = "4.0.24") : String
  path = File.expand_path(File.join(__DIR__, "..", "assets", "man", profile, name))
  File.read(path)
end

private def normalize(text : String) : String
  text.gsub("\r\n", "\n")
end

private def with_man_profile(version : String, & : ->) : Nil
  previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = version
  begin
    yield
  ensure
    previous ? (ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous) : ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  end
end

describe "M7(3) bundle help renders the bundled manpages" do
  it "prints the install page for `help install`" do
    code, stdout, err = run_cli(["help", "install"])
    code.should eq(0)
    err.should eq("")
    normalize(stdout).should eq(man_text("bundle-install.1.ronn"))
  end

  it "prints the top-level page for a bare `help` and for `--help`" do
    code, stdout, err = run_cli(["help"])
    code.should eq(0)
    err.should eq("")
    normalize(stdout).should eq(man_text("bundle.1.ronn"))

    code, stdout, err = run_cli(["--help"])
    code.should eq(0)
    err.should eq("")
    normalize(stdout).should eq(man_text("bundle.1.ronn"))
  end

  it "routes `gemfile` to the section 5 page" do
    code, stdout, err = run_cli(["help", "gemfile"])
    code.should eq(0)
    err.should eq("")
    normalize(stdout).should eq(man_text("gemfile.5.ronn"))
  end

  it "resolves the reference aliases before looking up the page" do
    {"c" => "bundle-check.1.ronn", "i" => "bundle-install.1.ronn", "ls" => "bundle-list.1.ronn"}.each do |alias_name, page|
      code, stdout, err = run_cli(["help", alias_name])
      code.should eq(0)
      err.should eq("")
      normalize(stdout).should eq(man_text(page))
    end
  end

  it "renders the page for `<command> --help` as Thor does" do
    code, stdout, err = run_cli(["install", "--help"])
    code.should eq(0)
    err.should eq("")
    normalize(stdout).should eq(man_text("bundle-install.1.ronn"))
  end

  it "keeps `help -h` on the help page itself" do
    # `-h` is a Thor class option (base.rb:17 HELP_MAPPINGS), so `help -h`
    # renders bundle-help(1) rather than treating `-h` as its own argument.
    code, stdout, err = run_cli(["help", "-h"])
    code.should eq(0)
    err.should eq("")
    normalize(stdout).should eq(man_text("bundle-help.1.ronn"))
  end

  it "falls back to Thor's command_help for page-less hidden commands" do
    code, stdout, err = run_cli(["help", "tree"])
    code.should eq(0)
    err.should eq("")
    text = normalize(stdout)
    text.should start_with("Usage:\n  bundle tree\n\nOptions:\n")
    text.should contain("-V, [--verbose], [--no-verbose], [--skip-verbose]")
    text.should end_with("Print a tree of all available commands\n")
  end

  it "reports unknown names and suggests the closest command" do
    code, stdout, err = run_cli(["help", "nosuchcmd"])
    code.should eq(15)
    stdout.should eq("")
    err.should eq(%(Could not find command "nosuchcmd".\n))

    code, stdout, err = run_cli(["help", "get"])
    code.should eq(15)
    stdout.should eq("")
    err.should eq(%(Could not find command "get".\nDid you mean?  "gem"\n))
  end

  it "rejects extra positional arguments like Thor does" do
    code, stdout, err = run_cli(["help", "install", "extra"])
    code.should eq(15)
    stdout.should eq("")
    # Thor `handle_argument_error` emits exactly two lines (no trailing blank).
    err.should eq(%(ERROR: "bundle help" was called with arguments ["install", "extra"]\nUsage: "bundle help [COMMAND]"\n))
  end

  it "uses the page of the active bundler profile" do
    with_man_profile("2.7.2") do
      code, stdout, err = run_cli(["help", "install"])
      code.should eq(0)
      err.should eq("")
      normalize(stdout).should eq(man_text("bundle-install.1.ronn", "2.7.2"))
      normalize(stdout).should_not eq(man_text("bundle-install.1.ronn"))
    end
  end

  it "drops the commands 2.7.2 never had instead of rendering Thor help" do
    # 2.7.2's `Bundler::CLI` has 32 commands (`tree` and `install_or_cli_help`
    # are 4.0.24 additions), so `help tree` is an undefined command there.
    with_man_profile("2.7.2") do
      code, stdout, err = run_cli(["help", "tree"])
      code.should eq(15)
      stdout.should eq("")
      err.should eq(%(Could not find command "tree".\n))

      code, stdout, err = run_cli(["help", "install_or_cli_help"])
      code.should eq(15)
      stdout.should eq("")
      err.should eq(%(Could not find command "install_or_cli_help".\n))
    end
  end

  it "renders the pages 2.7.2 did ship and keeps its page-less fallback" do
    with_man_profile("2.7.2") do
      code, stdout, err = run_cli(["help", "viz"])
      code.should eq(0)
      err.should eq("")
      normalize(stdout).should eq(man_text("bundle-viz.1.ronn", "2.7.2"))

      code, stdout, err = run_cli(["help", "inject"])
      code.should eq(0)
      err.should eq("")
      normalize(stdout).should eq(man_text("bundle-inject.1.ronn", "2.7.2"))

      code, stdout, err = run_cli(["help", "cli_help"])
      code.should eq(0)
      err.should eq("")
      normalize(stdout).should start_with("Usage:\n  bundle cli_help\n\nOptions:\n")
    end
  end
end
