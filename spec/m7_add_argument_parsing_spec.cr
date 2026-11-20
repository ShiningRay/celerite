require "./spec_helper"

private def with_parse_home(&)
  home = File.tempname("celerite-parse-home", "")
  Dir.mkdir_p(home)
  old_home = ENV["HOME"]?
  old_profile = ENV["USERPROFILE"]?
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  old_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    old_home ? (ENV["HOME"] = old_home) : ENV.delete("HOME")
    old_profile ? (ENV["USERPROFILE"] = old_profile) : ENV.delete("USERPROFILE")
    old_bridge ? (ENV["CELERITE_BRIDGE_SERVER"] = old_bridge) : ENV.delete("CELERITE_BRIDGE_SERVER")
    FileUtils.rm_rf(home)
  end
end

private def parse_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def with_parse_bundle_path(path : String, &)
  previous = ENV["BUNDLE_PATH"]?
  ENV["BUNDLE_PATH"] = path
  begin
    yield
  ensure
    previous ? (ENV["BUNDLE_PATH"] = previous) : ENV.delete("BUNDLE_PATH")
  end
end

describe "M7(2) add argument parsing and install --target-rbconfig" do
  # `cli/add.rb` only sees positionals for gem names; `--version thor` consumed
  # "thor" as the requirement, so no gem is left and validate_options! raises
  # InvalidOption ("Please specify gems to add.") before the Gemfile is touched.
  it "treats the --version value as a requirement, not as a gem name" do
    with_parse_home do
      gemfile = %(source "#{parse_index_url}"\n)
      with_project({"Gemfile" => gemfile}) do |dir|
        code, stdout, stderr = run_cli(["add", "--version", "thor", "--skip-install"])
        code.should eq(15)
        stdout.should eq("")
        stderr.should eq("Please specify gems to add.\n")
        File.read(File.join(dir, "Gemfile")).should eq(gemfile)
      end
    end
  end

  it "reports the same message for add with no operands" do
    with_parse_home do
      gemfile = %(source "#{parse_index_url}"\n)
      with_project({"Gemfile" => gemfile}) do |_dir|
        code, stdout, stderr = run_cli(["add"])
        code.should eq(15)
        stdout.should eq("")
        stderr.should eq("Please specify gems to add.\n")
      end
    end
  end

  # `--glob` takes a value, so the following operand is the gem name. Bundler
  # writes the pattern verbatim (injector.rb:119); only the Windows ruby.exe
  # argv layer expands wildcards before Bundler sees them.
  it "keeps the --glob value out of the gem position" do
    with_parse_home do
      with_project({"Gemfile" => %(source "#{parse_index_url}"\n)}) do |dir|
        with_parse_bundle_path(File.join(dir, "bundle")) do
          code, _stdout, stderr = run_cli(["add", "--glob", "*.gemspec", "json_pure", "--skip-install"])
          code.should eq(0)
          stderr.should eq("")
          File.read(File.join(dir, "Gemfile")).should contain(%(gem "json_pure", "~> 2.8", glob: "*.gemspec"))
        end
      end
    end
  end

  it "supports the inline --glob=value form" do
    with_parse_home do
      with_project({"Gemfile" => %(source "#{parse_index_url}"\n)}) do |dir|
        with_parse_bundle_path(File.join(dir, "bundle")) do
          code, _stdout, stderr = run_cli(["add", "--glob=sub/*.gemspec", "json_pure", "--skip-install"])
          code.should eq(0)
          stderr.should eq("")
          File.read(File.join(dir, "Gemfile")).should contain(%(gem "json_pure", "~> 2.8", glob: "sub/*.gemspec"))
        end
      end
    end
  end

  it "supports the inline --version=value form" do
    with_parse_home do
      with_project({"Gemfile" => %(source "#{parse_index_url}"\n)}) do |dir|
        with_parse_bundle_path(File.join(dir, "bundle")) do
          code, _stdout, stderr = run_cli(["add", "thor", "--version=1.3.2", "--skip-install"])
          code.should eq(0)
          stderr.should eq("")
          File.read(File.join(dir, "Gemfile")).should contain(%(gem "thor", "= 1.3.2"))
        end
      end
    end
  end

  # `cli/install.rb:24` loads the target rbconfig immediately; a missing file
  # raises LoadError inside friendly-errors and aborts before any lock write.
  it "fails install when --target-rbconfig points at a missing file" do
    with_parse_home do
      with_project({"Gemfile" => %(source "#{parse_index_url}"\n\ngem "json_pure"\n)}) do |dir|
        with_parse_bundle_path(File.join(dir, "bundle")) do
          code, stdout, stderr = run_cli(["install", "--target-rbconfig", "nofile.rb"])
          code.should eq(1)
          stdout.should eq("")
          stderr.should contain("LoadError: cannot load such file -- nofile.rb")
          File.exists?(File.join(dir, "Gemfile.lock")).should be_false
        end
      end
    end
  end
end
