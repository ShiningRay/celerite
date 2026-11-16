require "./spec_helper"
require "../src/celerite"

# Reference `bundler-4.0.24/lib/bundler/cli.rb`:
# - `:290-300` runs the remembered-flag checks for install before anything else
# - `:817-838` prints the removed-flag message (word-wrapped at 80 columns)
private def with_removed_flags_bridge(& : ->) : Nil
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def removed_flags_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  %(source "#{remote}"\n)
end

private def remembered_flag(flag : String, option : String, value : String) : String
  "The `#{flag}` flag has been removed because it relied on being remembered across bundler invocations, which bundler no longer does. Instead please use `bundle config set #{option} #{value}`, and stop using this flag"
end

private def expected_removed(flag : String, option : String, value : String) : String
  Celerite::Commands.word_wrap(remembered_flag(flag, option, value), 80) + "\n"
end

describe "removed flags and switch suggestions" do
  it "reports the removed --frozen flag for install" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--frozen"])
        code.should eq(15)
        out.should eq("")
        err.should eq(expected_removed("--frozen", "frozen", "true"))
      end
    end
  end

  it "reports the removed --path flag with the given value" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--path", "vendor/x"])
        code.should eq(15)
        out.should eq("")
        err.should eq(expected_removed("--path", "path", "'vendor/x'"))
      end
    end
  end

  it "reports the removed --path flag without a value using the bare flag name" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--path"])
        code.should eq(15)
        out.should eq("")
        err.should eq(expected_removed("--path", "path", "'path'"))
      end
    end
  end

  it "reports the removed --binstubs option with its dedicated message" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--binstubs"])
        code.should eq(15)
        out.should eq("")
        err.should eq("The --binstubs option has been removed in favor of `bundle binstubs --all`\n")
      end
    end
  end

  it "reports the removed cache --all flag" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["cache", "--all"])
        code.should eq(15)
        out.should eq("")
        err.should eq(expected_removed("--all", "cache_all", "true"))
      end
    end
  end

  it "does not apply the removed-flag wording to cache --deployment" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["cache", "--deployment"])
        code.should eq(15)
        out.should eq("")
        err.should contain("Unknown switches \"--deployment\"")
        err.should_not contain("has been removed because it relied")
      end
    end
  end

  it "suggests --force for update --frozen" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["update", "--frozen"])
        code.should eq(15)
        out.should eq("")
        err.should contain("Unknown switches \"--frozen\"")
        err.should contain("Did you mean?  \"--force\"")
      end
    end
  end

  it "suggests --force for a mistyped install switch" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--forse"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--forse\"\nDid you mean?  \"--force\"\n")
      end
    end
  end

  # did_you_mean's misspell pass: `--deployment` is four edits from `--deploy`,
  # beyond ceil(8 * 0.25) == 2, so it only survives through the fallback that
  # keeps the closest Jaro-Winkler hit.
  it "suggests the removed --deployment through the misspell fallback" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--deploy"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--deploy\"\nDid you mean?  \"--deployment\"\n")
      end
    end
  end

  # The edit budget is ceil(9 * 0.25) == 3, so both `--lockfile` (one edit) and
  # `--local` (three edits) are reported, closest first.
  it "reports every switch inside the edit budget" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--lockfil"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--lockfil\"\nDid you mean?  \"--lockfile\"\n               \"--local\"\n")
      end
    end
  end

  # `--jbos` is six characters, so the budget is two: `--jobs` (two edits) is
  # reported and `--verbose` (four edits) is not.
  it "drops suggestions beyond the edit budget" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--jbos"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--jbos\"\nDid you mean?  \"--jobs\"\n")
      end
    end
  end

  # `--redownload` is only an alias of `--force`, and Thor's suggestion
  # dictionary holds declared names, so the reference stays silent here.
  it "does not suggest option aliases" do
    with_removed_flags_bridge do
      with_project({"Gemfile" => removed_flags_gemfile}) do |dir|
        code, out, err = run_cli(["install", "--redownloa"])
        code.should eq(15)
        out.should eq("")
        err.should eq("Unknown switches \"--redownloa\"\n")
      end
    end
  end
end
