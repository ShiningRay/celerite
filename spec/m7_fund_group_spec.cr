require "./spec_helper"

# M7(3) fund --group: mirrors bundler-4.0.24/lib/bundler/cli/fund.rb:14-32 and
# definition.rb:286-288/:328-333/:1251-1255. Group membership is not stored in
# the lockfile, so every example drives the bridge Gemfile evaluation.
private def fund_group_remote : String
  "https://rubygems.org"
end

private def fund_group_gemfile : String
  <<-GEMFILE
  source "https://rubygems.org"

  gem "alpha", path: "vendor/alpha"

  group :development do
    gem "beta", path: "vendor/beta"
  end
  GEMFILE
end

private def fund_group_lockfile : String
  <<-LOCKFILE
  PATH
    remote: vendor/alpha
    specs:
      alpha (0.1.0)

  PATH
    remote: vendor/beta
    specs:
      beta (0.2.0)

  GEM
    remote: https://rubygems.org/
    specs:

  PLATFORMS
    x64-mingw-ucrt

  DEPENDENCIES
    alpha!
    beta!

  BUNDLED WITH
     4.0.24
  LOCKFILE
end

private def fund_group_gemspec(name : String, version : String) : String
  <<-SPEC
  Gem::Specification.new do |s|
    s.name = "#{name}"
    s.version = "#{version}"
    s.summary = "#{name}"
    s.metadata = { "funding_uri" => "https://example.com/fund/#{name}" }
  end
  SPEC
end

private def fund_group_project_files(extra : Hash(String, String) = {} of String => String) : Hash(String, String)
  files = {
    "Gemfile"                    => fund_group_gemfile,
    "Gemfile.lock"               => fund_group_lockfile,
    "vendor/alpha/alpha.gemspec" => fund_group_gemspec("alpha", "0.1.0"),
    "vendor/alpha/lib/alpha.rb"  => "module Alpha\nend\n",
    "vendor/beta/beta.gemspec"   => fund_group_gemspec("beta", "0.2.0"),
    "vendor/beta/lib/beta.rb"    => "module Beta\nend\n",
  }
  extra.each { |key, value| files[key] = value }
  files
end

private def with_fund_bridge(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
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

private def run_fund(rest : Array(String) = [] of String) : Tuple(Int32, String, String)
  output = IO::Memory.new
  errors = IO::Memory.new
  code = Celerite::Commands.fund(output, errors, rest)
  {code, output.to_s, errors.to_s}
end

# `fund` renders the `PathError` through the unified word wrap
# (`src/celerite/cli/commands.cr:1205-1214` via `cli.cr:52-61`), and the message
# embeds the temp project's *absolute* path. At the 80-column default the break
# points therefore follow the temp root's length (task-225: red under
# `C:\t\sp225`, green under `C:\t\cel\.tmp-scratch\sp225`). Pinning 30 columns
# removes that coupling: the fixed words fill each line by themselves and the
# path is always far wider than 30 columns, so the rendering below holds for any
# temp root. Restore shape copied from `spec/m7_add_options_spec.cr:41-53`.
private def with_fund_columns(columns : String, &) : Nil
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

private def with_fund_project(extra : Hash(String, String) = {} of String => String, &)
  with_fund_bridge do
    with_project(fund_group_project_files(extra)) do |dir|
      yield dir
    end
  end
end

private def fund_none : String
  "None of the installed gems you directly depend on are looking for funding.\n"
end

private def fund_alpha_only : String
  "* alpha (0.1.0)\n  Funding: https://example.com/fund/alpha\n"
end

private def fund_beta_only : String
  "* beta (0.2.0)\n  Funding: https://example.com/fund/beta\n"
end

describe "M7 fund --group" do
  it "lists every requested group by default (alpha then beta)" do
    with_fund_project do
      code, out, err = run_fund
      code.should eq(0)
      err.should eq("")
      out.should eq(fund_alpha_only + fund_beta_only)
    end
  end

  it "filters by --group=development" do
    with_fund_project do
      code, out, _err = run_fund(["--group=development"])
      code.should eq(0)
      out.should eq(fund_beta_only)
    end
  end

  it "accepts the space-separated --group form" do
    with_fund_project do
      code, out, _err = run_fund(["--group", "development"])
      code.should eq(0)
      out.should eq(fund_beta_only)
    end
  end

  it "does not split commas in --group (development,test matches nothing)" do
    with_fund_project do
      code, out, _err = run_fund(["--group=development,test"])
      code.should eq(0)
      out.should eq(fund_none)
    end
  end

  it "takes the last repeated --group flag (test overwrites development)" do
    with_fund_project do
      code, out, _err = run_fund(["--group=development", "--group=test"])
      code.should eq(0)
      out.should eq(fund_none)
    end
  end

  it "prints the none message for an unknown group" do
    with_fund_project do
      code, out, _err = run_fund(["--group=missing"])
      code.should eq(0)
      out.should eq(fund_none)
    end
  end

  it "honours BUNDLE_WITHOUT for the default selection" do
    with_fund_project({".bundle/config" => "---\nBUNDLE_WITHOUT: \"development\"\n"}) do
      code, out, _err = run_fund
      code.should eq(0)
      out.should eq(fund_alpha_only)
    end
  end

  it "returns the none message instead of crashing for --group inside BUNDLE_WITHOUT" do
    # 4.0.24 raises NoMethodError (fund.rb:24, nil spec) here; we stay calm.
    with_fund_project({".bundle/config" => "---\nBUNDLE_WITHOUT: \"development\"\n"}) do
      code, out, _err = run_fund(["--group=development"])
      code.should eq(0)
      out.should eq(fund_none)
    end
  end

  it "reports a missing PATH dependency like Bundler's PathError (exit 13)" do
    with_fund_project do |dir|
      FileUtils.rm_rf(File.join(dir, "vendor", "beta"))
      missing = File.join(dir, "vendor", "beta").gsub('\\', "/")

      # 30 columns: the message wraps into the same three lines whatever the
      # project path happens to be, because none of the fixed words can share a
      # line with any part of the path.
      with_fund_columns("30") do
        code, out, err = run_fund
        code.should eq(13)
        out.should eq("")
        # source/path.rb:198-204 emits one line; ui/shell.rb:167-171 wraps it,
        # so here the path owns its line. Expectation is a literal, not
        # `Commands.word_wrap` applied to the message.
        err.should eq("The path\n`#{missing}`\ndoes not exist.\n")
      end

      # The breaks above come from the pinned width, not from a hardcoded
      # newline: a wide terminal keeps the whole sentence on a single line.
      with_fund_columns("1000") do
        wide_code, wide_out, wide_err = run_fund
        wide_code.should eq(13)
        wide_out.should eq("")
        wide_err.should eq("The path `#{missing}` does not exist.\n")
      end
    end
  end
end
