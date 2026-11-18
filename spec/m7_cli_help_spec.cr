require "./spec_helper"
require "../src/celerite"

# Reference anchors for this round:
# * `bundler/cli.rb:99-121 #cli_help` — the banner, then `printable_commands`
#   split into `primary_commands` (fixed order) and `utilities`
#   (`by_name.keys.sort - primary_commands`), both rendered by
#   `shell.print_table(…, indent: 4, truncate: true)`, then
#   `class_options_help`.
# * `bundler/cli.rb:133-148 self.default_command` — the five-line notice while
#   `default_cli_command` is unset, then `install` as the fallback.
# * `bundler/cli.rb:290-313 #install` — rescue `GemfileNotFound`, render
#   `cli_help`, re-raise.
# * `bundler/settings/validator.rb:78-81` — `default_cli_command` must be
#   `install` or `cli_help` (4.x only; 2.7.2 has no such rule).
# * `bundler/vendor/thor/lib/thor/shell/table_printer.rb:103-111` — a truncated
#   row is `chars[0, truncate - 3 - indent] + "..."`.
# * `bundler/vendor/thor/lib/thor.rb:591-620` — a leading switch that is not a
#   dash mapping is never shifted, so the command falls back to
#   `default_command`.
private def with_cli_help_profile(version : String, & : ->) : Nil
  previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = version
  begin
    yield
  ensure
    previous ? (ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous) : ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  end
end

# `config set … --global` writes `~/.bundle/config`, so each example needs its
# own home or a previous case's value leaks into the next one.
private def with_cli_help_home(& : ->) : Nil
  home = File.tempname("celerite-cli-help", "home")
  Dir.mkdir_p(home)
  previous_home = ENV["HOME"]?
  previous_profile = ENV["USERPROFILE"]?
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  begin
    yield
  ensure
    previous_home ? (ENV["HOME"] = previous_home) : ENV.delete("HOME")
    previous_profile ? (ENV["USERPROFILE"] = previous_profile) : ENV.delete("USERPROFILE")
    FileUtils.rm_rf(home)
  end
end

private CLI_HELP_PRIMARY_4_X = [
  "    bundle install [OPTIONS]    # Install the current environment to the system",
  "    bundle update [OPTIONS]     # Update the current environment",
  "    bundle cache [OPTIONS]      # Locks and then caches all of the gems into ...",
  "    bundle exec [OPTIONS]       # Run the command in context of the bundle",
  "    bundle config NAME [VALUE]  # Retrieve or set a configuration value",
  "    bundle help [COMMAND]       # Describe available commands or one specific...",
]

private CLI_HELP_UTILITIES_4_X = [
  "    bundle add GEM VERSION         # Add gem to Gemfile and run bundle install",
  "    bundle binstubs GEM [OPTIONS]  # Install the binstubs of the listed gem",
  "    bundle check [OPTIONS]         # Checks if the dependencies listed in Gem...",
  "    bundle clean [OPTIONS]         # Cleans up unused gems in your bundler directory",
  "    bundle console [GROUP]         # Opens an IRB session with the bundle pre-loaded",
  "    bundle doctor [OPTIONS]        # Checks the bundle for common problems",
  "    bundle env                     # Print information about the environment ...",
  "    bundle fund [OPTIONS]          # Lists information about gems seeking fun...",
  "    bundle gem NAME [OPTIONS]      # Creates a skeleton for creating a rubygem",
  "    bundle info GEM [OPTIONS]      # Show information for the given gem",
  "    bundle init [OPTIONS]          # Generates a Gemfile into the current wor...",
  "    bundle issue                   # Learn how to report an issue in Bundler",
  "    bundle licenses                # Prints the license of all gems in the bundle",
  "    bundle list                    # List all gems in the bundle",
  "    bundle lock                    # Creates a lockfile without installing",
  "    bundle open GEM                # Opens the source directory of the given ...",
  "    bundle outdated GEM [OPTIONS]  # List installed gems with newer versions ...",
  "    bundle platform [OPTIONS]      # Displays platform compatibility information",
  "    bundle plugin                  # Manage the bundler plugins",
  "    bundle pristine [GEMS...]      # Restores installed gems to pristine condition",
  "    bundle remove [GEM [GEM ...]]  # Removes gems from the Gemfile",
  "    bundle show GEM [OPTIONS]      # Shows all gems that are part of the bund...",
  "    bundle tree                    # Print a tree of all available commands",
  "    bundle version                 # Prints Bundler version information",
]

private CLI_HELP_OPTIONS = [
  "      [--no-color]                                   # Disable colorization in output",
  "  -r, [--retry=NUM]                                  # Specify the number of times you wish to attempt network commands",
  "  -V, [--verbose], [--no-verbose], [--skip-verbose]  # Enable verbose output mode",
]

private CLI_HELP_NOTICE = "In a future version of Bundler, running `bundle` without argument will no longer run `bundle install`.\n" +
                          "Instead, the `cli_help` command will be displayed. Please use `bundle install` explicitly for scripts like CI/CD.\n" +
                          "You can use the future behavior now with `bundle config set default_cli_command cli_help --global`,\n" +
                          "or you can continue to use the current behavior with `bundle config set default_cli_command install --global`.\n" +
                          "This message will be removed after a default_cli_command value is set.\n"

describe "M7(2) bundle cli_help" do
  it "renders the 4.0.24 command tables byte for byte" do
    with_cli_help_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["cli_help"])
        code.should eq(0)
        err.should eq("")
        lines = out.gsub("\r\n", "\n").split("\n")
        lines[0].should eq("Bundler version 4.0.24 (2026-11-05 commit 3b396e4)")
        lines[2].should eq("Bundler commands:")
        lines[4].should eq("  Primary commands:")
        lines[5, 6].should eq(CLI_HELP_PRIMARY_4_X)
        lines[12].should eq("  Utilities:")
        lines[13, 24].should eq(CLI_HELP_UTILITIES_4_X)
        lines[38].should eq("Options:")
        lines[39, 3].should eq(CLI_HELP_OPTIONS)
        # Two trailing newlines after the last option row.
        out.should end_with("# Enable verbose output mode\n\n")
        out.size.should eq(2718)
      end
    end
  end

  it "drops `tree` and `clean` under 2.7.2" do
    with_cli_help_profile("2.7.2") do
      with_project({} of String => String) do
        code, out, err = run_cli(["cli_help"])
        code.should eq(0)
        err.should eq("")
        lines = out.gsub("\r\n", "\n").split("\n")
        lines[0].should eq("Bundler version 2.7.2 (2025-09-09 commit b463ced1459)")
        lines[5, 6].should eq(CLI_HELP_PRIMARY_4_X)
        # 2.7.2 has no `clean` and no `tree`: 22 utilities instead of 24.
        lines[13, 22].should eq(CLI_HELP_UTILITIES_4_X.reject { |row| row.includes?(" bundle clean ") || row.includes?(" bundle tree ") })
        lines[35].should eq("")
        lines[36].should eq("Options:")
        out.should end_with("# Enable verbose output mode\n\n")
        out.size.should eq(2560)
      end
    end
  end

  it "rejects arguments and unknown switches like Thor" do
    with_cli_help_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["cli_help", "extra"])
        code.should eq(15)
        out.should eq("")
        err.should eq(%(ERROR: "bundle cli_help" was called with arguments ["extra"]\nUsage: "bundle cli_help"\n))

        code, out, err = run_cli(["cli_help", "--bogus"])
        code.should eq(15)
        out.should eq("")
        err.should eq(%(Unknown switches "--bogus"\n))
      end
    end
  end

  it "echoes the invocation under --verbose" do
    with_cli_help_profile("4.0.24") do
      with_project({} of String => String) do
        begin
          code, out, err = run_cli(["cli_help", "--verbose"])
          code.should eq(0)
          out.should start_with("Running `bundle cli_help --verbose` with bundler 4.0.24\n")
          # The echo adds 56 bytes on top of the plain table.
          out.size.should eq(2774)
        ensure
          # `strip_global_flags` records `--verbose` in the process environment,
          # which would otherwise make every later example verbose too.
          ENV.delete("CELERITE_VERBOSE")
        end
      end
    end
  end

  it "keeps the Thor fallback page for `help cli_help`" do
    with_cli_help_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["help", "cli_help"])
        code.should eq(0)
        out.gsub("\r\n", "\n").should eq("Usage:\n  bundle cli_help\n\nOptions:\n" +
                                         CLI_HELP_OPTIONS.join("\n") + "\n\nPrints a summary of bundler commands\n")
      end
    end
  end
end

describe "M7(2) the default command of a bare `bundle`" do
  it "prints the notice and then runs install" do
    with_cli_help_profile("4.0.24") do
      with_project({
        "Gemfile" => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \"2.6.0\"\n",
      }) do
        code, out, err = run_cli([] of String)
        # No network and no local index, so install fails on the source index;
        # the notice still precedes it.
        out.should start_with(CLI_HELP_NOTICE + "\n")
      end
    end
  end

  it "stays silent under 2.7.2, whose default is fixed at class definition" do
    with_cli_help_profile("2.7.2") do
      with_project({} of String => String) do
        code, out, _err = run_cli([] of String)
        code.should eq(10)
        out.should eq("")
      end
    end
  end

  it "renders cli_help when install cannot find a Gemfile (4.x only)" do
    with_cli_help_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli([] of String)
        code.should eq(10)
        out.should start_with(CLI_HELP_NOTICE + "\n")
        out.should contain("Bundler commands:")
        out.should contain("  Primary commands:")
        err.should eq("Could not locate Gemfile\n")
      end
    end
  end

  it "honours default_cli_command and falls back to install" do
    with_cli_help_home do
      with_cli_help_profile("4.0.24") do
        with_project({} of String => String) do
          code, out, err = run_cli(["config", "set", "default_cli_command", "cli_help", "--global"])
          code.should eq(0)
          out.should eq("")
          err.should eq("")

          # Configured: no notice, just the table; the table then rejects
          # positional arguments the unresolved tokens became.
          ENV["BUNDLE_DEFAULT_CLI_COMMAND"] = "cli_help"
          begin
            code, out, err = run_cli([] of String)
            code.should eq(0)
            out.should_not contain("In a future version of Bundler")
            out.should contain("Bundler commands:")

            code, _out, err = run_cli(["--no-color", "lock"])
            code.should eq(15)
            err.should eq(%(ERROR: "bundle cli_help" was called with arguments ["lock"]\nUsage: "bundle cli_help"\n))

            code, _out, err = run_cli(["-V", "lock"])
            code.should eq(15)
            err.should eq(%(ERROR: "bundle cli_help" was called with arguments ["lock"]\nUsage: "bundle cli_help"\n))
          ensure
            ENV.delete("BUNDLE_DEFAULT_CLI_COMMAND")
          end
        end
      end
    end
  end

  it "rejects an invalid default_cli_command under 4.x only" do
    with_cli_help_home do
      with_cli_help_profile("4.0.24") do
        with_project({} of String => String) do
          code, out, err = run_cli(["config", "set", "default_cli_command", "bogus", "--global"])
          code.should eq(15)
          out.should eq("")
          err.should eq("Setting `default_cli_command` to \"bogus\" failed:\n" +
                        " - default_cli_command must be either 'install' or 'cli_help'\n" +
                        " - must be one of: install, cli_help\n")
        end
      end
    end

    with_cli_help_home do
      with_cli_help_profile("2.7.2") do
        with_project({} of String => String) do
          code, out, err = run_cli(["config", "set", "default_cli_command", "bogus", "--global"])
          code.should eq(0)
          out.should eq("")
          err.should eq("")
        end
      end
    end
  end
end
