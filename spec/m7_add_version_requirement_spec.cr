require "./spec_helper"

# M7 task-80 D1: `bundle add --version` renders the requirement it was given
# (cli/add.rb:33 splits on commas, injector.rb:106 dumps each entry), instead of
# wrapping the value in a synthetic `= ` pin.
private def add_version_index : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def add_version_gemfile : String
  "source \"#{add_version_index}\"\n"
end

private def with_add_version_env(dir : String, &)
  keys = {
    "HOME"                   => File.join(dir, "home"),
    "USERPROFILE"            => File.join(dir, "home"),
    "BUNDLE_PATH"            => File.join(dir, "bundle"),
    "BUNDLE_APP_CONFIG"      => File.join(dir, "appcfg"),
    "CELERITE_BRIDGE_SERVER" => File.expand_path("../assets/bridge/server.rb", __DIR__),
  }
  saved = {} of String => String?
  keys.each do |key, value|
    saved[key] = ENV[key]?
    ENV[key] = value
  end
  Dir.mkdir_p(File.join(dir, "home"))
  Dir.mkdir_p(File.join(dir, "appcfg"))
  original = Dir.current
  begin
    yield
  ensure
    Dir.cd(original)
    keys.each_key do |key|
      if previous = saved[key]?
        ENV[key] = previous
      else
        ENV.delete(key)
      end
    end
  end
end

private def add_gemfile_line(dir : String) : String
  File.read(File.join(dir, "Gemfile")).lines.reject(&.starts_with?("source")).join(" ").strip
end

describe "M7 add --version requirement rendering" do
  it "keeps an operator requirement instead of pinning it with `= `" do
    with_project({"Gemfile" => add_version_gemfile}) do |dir|
      with_add_version_env(dir) do
        code, _out, err = run_cli(["add", "json_pure", "--version", "~>2.8", "--skip-install"])
        err.should_not contain("Illformed requirement")
        code.should eq(0)
        add_gemfile_line(dir).should contain("gem \"json_pure\", \"~> 2.8\"")
      end
    end
  end

  it "dumps every comma separated entry as its own requirement" do
    with_project({"Gemfile" => add_version_gemfile}) do |dir|
      with_add_version_env(dir) do
        code, _out, err = run_cli(["add", "json_pure", "--version", ">=2.6,<2.9", "--skip-install"])
        err.should eq("")
        code.should eq(0)
        add_gemfile_line(dir).should contain("gem \"json_pure\", \">= 2.6\", \"< 2.9\"")
      end
    end
  end

  it "renders a bare version as an exact pin" do
    with_project({"Gemfile" => add_version_gemfile}) do |dir|
      with_add_version_env(dir) do
        code, _out, _err = run_cli(["add", "json_pure", "--version", "2.8.1", "--skip-install"])
        code.should eq(0)
        add_gemfile_line(dir).should contain("gem \"json_pure\", \"= 2.8.1\"")
      end
    end
  end

  it "rejects an invalid pattern before touching the Gemfile" do
    with_project({"Gemfile" => add_version_gemfile}) do |dir|
      with_add_version_env(dir) do
        before = File.read(File.join(dir, "Gemfile"))
        code, _out, err = run_cli(["add", "json_pure", "--version", "bogus", "--skip-install"])
        code.should eq(15)
        err.should contain("Invalid gem requirement pattern 'bogus'")
        File.read(File.join(dir, "Gemfile")).should eq(before)
      end
    end
  end
end
