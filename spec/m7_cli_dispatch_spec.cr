require "./spec_helper"
require "../src/celerite"

# Reference anchors for this round (Bundler 4.0.24 / 2.7.2):
# * `bundler/vendor/thor/lib/thor.rb:643-660 #dispatch` — an unknown action is
#   resolved through `Thor::Util.find_class_and_command_by_namespace`-style
#   prefix matching, which yields "Ambiguous command" when several commands
#   share the prefix, and `Suggestion` ("Did you mean?") when none does.
# * `bundler/vendor/thor/lib/thor/base.rb:17-18` — `HELP_MAPPINGS` and
#   `TREE_MAPPINGS = %w(-t --tree)`; 2.7.2 has no `TREE_MAPPINGS` at all.
# * `bundler/vendor/thor/lib/thor.rb:675-706 self.tree` — namespace line,
#   `klass.commands` minus `hidden?` and `help`, sorted by name, `├─`/`└─`
#   prefixes, description = `description.split("\n").first`.
# * `bundler/cli.rb:583-587` — `viz` and `graph` removal notice; `cli.rb:635-638`
#   — `inject` removal notice; `bundler/shared_helpers.rb #feature_removed!`
#   prefixes "[REMOVED] " and exits 9.
# * `bundler/cli.rb:133-148 self.default_command` — `install_or_cli_help` is a
#   deprecated 4.x alias that warns before dispatching to `install`.
private def with_dispatch_profile(version : String, & : ->) : Nil
  previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = version
  begin
    yield
  ensure
    previous ? (ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous) : ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  end
end

# `bundle tree` under 4.0.24, 41 lines; the two-byte box-drawing glyphs are
# written exactly as the vendored Thor emits them.
private TREE_4_X = [
  "bundler:c_l_i",
  "  ├─ add (Add gem to Gemfile and run bundle install)",
  "  ├─ binstubs (Install the binstubs of the listed gem)",
  "  ├─ cache (Locks and then caches all of the gems into vendor/cache)",
  "  ├─ check (Checks if the dependencies listed in Gemfile are satisfied by currently installed gems)",
  "  ├─ clean (Cleans up unused gems in your bundler directory)",
  "  ├─ config (Retrieve or set a configuration value)",
  "  ├─ console (Opens an IRB session with the bundle pre-loaded)",
  "  ├─ doctor (Checks the bundle for common problems)",
  "  ├─ env (Print information about the environment Bundler is running under)",
  "  ├─ exec (Run the command in context of the bundle)",
  "  ├─ fund (Lists information about gems seeking funding assistance)",
  "  ├─ gem (Creates a skeleton for creating a rubygem)",
  "  ├─ info (Show information for the given gem)",
  "  ├─ init (Generates a Gemfile into the current working directory)",
  "  ├─ install (Install the current environment to the system)",
  "  ├─ issue (Learn how to report an issue in Bundler)",
  "  ├─ licenses (Prints the license of all gems in the bundle)",
  "  ├─ list (List all gems in the bundle)",
  "  ├─ lock (Creates a lockfile without installing)",
  "  ├─ open (Opens the source directory of the given bundled gem)",
  "  ├─ outdated (List installed gems with newer versions available)",
  "  ├─ platform (Displays platform compatibility information)",
  "  ├─ plugin (Manage the bundler plugins)",
  "  ├─ pristine (Restores installed gems to pristine condition)",
  "  ├─ remove (Removes gems from the Gemfile)",
  "  ├─ show (Shows all gems that are part of the bundle, or the path to a given gem)",
  "  ├─ update (Update the current environment)",
  "  └─ version (Prints Bundler version information)",
  "  bundler:c_l_i:config",
  "    ├─ get (Returns the value for the given key)",
  "    ├─ list (List out all configured settings)",
  "    ├─ set (Sets the given value for the given key)",
  "    └─ unset (Unsets the value for the given key)",
  "  bundler:c_l_i:doctor",
  "    ├─ diagnose (Checks the bundle for common problems)",
  "    └─ ssl (Diagnose SSL problems)",
  "  bundler:c_l_i:plugin",
  "    ├─ install (Install the plugin from the source)",
  "    ├─ list (List the installed plugins and available commands)",
  "    └─ uninstall (Uninstall the plugins)",
]

private INSTALL_OR_CLI_HELP_WARNINGS = "`bundle install_or_cli_help` is a deprecated alias of `bundle install`.\n" +
                                       "It might be called due to the 'default_cli_command' being set to 'install_or_cli_help',\n" +
                                       "if so fix that by running `bundle config set default_cli_command install --global`.\n"

describe "M7(task-2) Thor command prefixes and the tree/removed surfaces" do
  it "expands the unique prefix `instal` to `install` under 4.x" do
    with_dispatch_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["instal"])
        # install forwards the missing Gemfile to the 4.x cli_help page.
        code.should eq(10)
        out.should contain("Bundler commands:")
        out.should contain("  Primary commands:")
        err.should eq("Could not locate Gemfile\n")
      end
    end
  end

  it "rejects the ambiguous prefix `co` with exit 15" do
    with_dispatch_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["co"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Ambiguous command co matches [config, console]\n")
      end
    end

    with_dispatch_profile("2.7.2") do
      with_project({} of String => String) do
        code, out, err = run_cli(["co"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Ambiguous command co matches [config, console]\n")
      end
    end
  end

  it "prints the 4.0.24 command tree byte for byte" do
    with_dispatch_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["tree"])
        code.should eq(0)
        err.should eq("")
        lines = out.gsub("\r\n", "\n").chomp.split("\n")
        lines.size.should eq(41)
        lines.should eq(TREE_4_X)
        out.gsub("\r\n", "\n").should eq(TREE_4_X.join("\n") + "\n")
        # 2178 characters: the oracle's 2326-byte LF rendering minus the two
        # extra bytes each box-drawing glyph carries in UTF-8.
        out.size.should eq(2178)
      end
    end
  end

  it "does not know `tree` under 2.7.2" do
    with_dispatch_profile("2.7.2") do
      with_project({} of String => String) do
        code, out, err = run_cli(["tree"])
        code.should eq(15)
        out.should eq("")
        err.should eq(%(Could not find command "tree".\n))
      end
    end
  end

  it "maps `-t` and `--tree` to tree under 4.x only" do
    with_dispatch_profile("4.0.24") do
      with_project({} of String => String) do
        {"-t", "--tree"}.each do |flag|
          code, out, err = run_cli([flag])
          code.should eq(0)
          err.should eq("")
          out.gsub("\r\n", "\n").should eq(TREE_4_X.join("\n") + "\n")
        end
      end
    end

    with_dispatch_profile("2.7.2") do
      with_project({} of String => String) do
        code, out, err = run_cli(["-t"])
        code.should eq(15)
        out.should eq("")
        err.should eq(%(Unknown switches "-t"\n))
      end
    end
  end

  it "exits 9 for the removed `viz` and `inject` commands under 4.x" do
    with_dispatch_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["viz"])
        code.should eq(9)
        out.should eq("")
        err.should eq("[REMOVED] The `viz` command has been renamed to `graph` and moved to a plugin.\n" +
                      "See https://github.com/rubygems/bundler-graph\n")

        code, out, err = run_cli(["inject"])
        code.should eq(9)
        out.should eq("")
        err.should eq("[REMOVED] The `inject` command has been replaced by the `add` command\n")

        # `feature_removed!` runs after the switch/argument guard.
        code, out, err = run_cli(["inject", "--bogus"])
        code.should eq(15)
        out.should eq("")
        err.should eq(%(Unknown switches "--bogus"\n))
      end
    end
  end

  it "resolves `cl` to clean under 4.x but reports it ambiguous under 2.7.2" do
    with_dispatch_profile("4.0.24") do
      # `clean` guards on `--force` before touching a Gemfile, so the prefix
      # resolves visibly even in an empty project.
      with_project({} of String => String) do
        code, out, err = run_cli(["cl", "--force"])
        code.should_not eq(15)
        err.should_not contain("Ambiguous command cl")
      end
    end

    with_dispatch_profile("2.7.2") do
      with_project({} of String => String) do
        code, out, err = run_cli(["cl"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Ambiguous command cl matches [clean, cli_help]\n")
      end
    end
  end

  it "suggests `list` for the unknown command `lst`" do
    with_dispatch_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["lst"])
        code.should eq(15)
        out.should eq("")
        err.should eq(%(Could not find command "lst".\nDid you mean?  "list"\n))
      end
    end
  end

  it "warns about the deprecated `install_or_cli_help` alias under 4.x only" do
    with_dispatch_profile("4.0.24") do
      with_project({} of String => String) do
        code, out, err = run_cli(["install_or_cli_help"])
        code.should eq(10)
        out.should contain("Bundler commands:")
        err.should eq(INSTALL_OR_CLI_HELP_WARNINGS + "Could not locate Gemfile\n")
      end
    end

    with_dispatch_profile("2.7.2") do
      with_project({} of String => String) do
        code, out, err = run_cli(["install_or_cli_help"])
        code.should eq(15)
        out.should eq("")
        err.should eq(%(Could not find command "install_or_cli_help".\n))
      end
    end
  end
end
