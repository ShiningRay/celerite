require "./spec_helper"

# M7(8) product difference 1: a `path` source written with an absolute path is
# recorded relative to the Gemfile directory in the lockfile, matching the
# reference (`Bundler::Source::Path#lockfile_path`, source/path.rb:136-139,
# relative_path at :210-215) and upstream lockfile_spec.rb:1154
# (`path File.expand_path("foo", __dir__)` -> `remote: foo`).
EXAMPLE_PATH_GEMSPEC = <<-SPEC
  Gem::Specification.new do |s|
    s.name = "example"
    s.version = "1.0.0"
    s.summary = "path lockfile probe"
  end
  SPEC

def path_source_gemfile(gem_path : String) : String
  "source \"https://rubygems.org\"\n\ngem \"example\", path: \"#{gem_path.gsub('\\', "/")}\"\n"
end

def with_bridge_server(&)
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

describe "M7(8) path source lockfile remote" do
  it "records an absolute project path relative to the Gemfile" do
    with_project({
      "Gemfile"                        => "source \"https://rubygems.org\"\n",
      "vendor/example/example.gemspec" => EXAMPLE_PATH_GEMSPEC,
    }) do |dir|
      absolute = File.expand_path("vendor/example", dir).gsub('\\', "/")
      File.write(File.join(dir, "Gemfile"), path_source_gemfile(absolute))

      with_bridge_server do
        code, _, _ = run_cli(["lock"])
        code.should eq(0)
      end

      text = File.read(File.join(dir, "Gemfile.lock"))
      text.should contain("remote: vendor/example\n")
      text.should_not contain(absolute)
      text.should_not contain('\\')
    end
  end

  it "keeps the lockfile byte-identical once the Gemfile uses the relative form" do
    with_project({
      "Gemfile"                        => "source \"https://rubygems.org\"\n",
      "vendor/example/example.gemspec" => EXAMPLE_PATH_GEMSPEC,
    }) do |dir|
      absolute = File.expand_path("vendor/example", dir).gsub('\\', "/")
      File.write(File.join(dir, "Gemfile"), path_source_gemfile(absolute))
      with_bridge_server do
        run_cli(["lock"]).first.should eq(0)
      end
      first = File.read(File.join(dir, "Gemfile.lock"))

      File.write(File.join(dir, "Gemfile"), path_source_gemfile("vendor/example"))
      with_bridge_server do
        run_cli(["lock"]).first.should eq(0)
      end

      File.read(File.join(dir, "Gemfile.lock")).should eq(first)
    end
  end

  it "keeps an absolute path that lives outside the project" do
    outside = File.tempname("celerite-outside", "gem")
    Dir.mkdir_p(outside)
    begin
      File.write(File.join(outside, "example.gemspec"), EXAMPLE_PATH_GEMSPEC)
      with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do |dir|
        absolute = File.expand_path(outside).gsub('\\', "/")
        File.write(File.join(dir, "Gemfile"), path_source_gemfile(absolute))

        with_bridge_server do
          run_cli(["lock"]).first.should eq(0)
        end

        text = File.read(File.join(dir, "Gemfile.lock"))
        text.should contain("remote: #{absolute}\n")
      end
    ensure
      FileUtils.rm_rf(outside)
    end
  end

  it "reuses the normalized lockfile when rebuilt from the absolute form" do
    with_project({
      "Gemfile"                        => "source \"https://rubygems.org\"\n",
      "vendor/example/example.gemspec" => EXAMPLE_PATH_GEMSPEC,
    }) do |dir|
      absolute = File.expand_path("vendor/example", dir).gsub('\\', "/")
      File.write(File.join(dir, "Gemfile"), path_source_gemfile(absolute))
      lockfile = File.join(dir, "Gemfile.lock")

      with_bridge_server do
        run_cli(["lock"]).first.should eq(0)
        first = File.read(lockfile)
        run_cli(["lock"]).first.should eq(0)
        File.read(lockfile).should eq(first)
      end

      File.read(lockfile).should contain("remote: vendor/example\n")
    end
  end
end
