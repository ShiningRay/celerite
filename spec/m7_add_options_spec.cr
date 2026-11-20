require "./spec_helper"

private def with_add_home(&)
  home = File.tempname("celerite-add-home", "")
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

private def add_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def with_bundle_path(path : String, &)
  previous = ENV["BUNDLE_PATH"]?
  ENV["BUNDLE_PATH"] = path
  begin
    yield
  ensure
    previous ? (ENV["BUNDLE_PATH"] = previous) : ENV.delete("BUNDLE_PATH")
  end
end

describe "M7(2) add option surface" do
  it "renders --glob into the Gemfile" do
    with_add_home do
      with_project({"Gemfile" => %(source "#{add_index_url}"\n)}) do |dir|
        with_bundle_path(File.join(dir, "bundle")) do
          code, _stdout, stderr = run_cli(["add", "json_pure", "--glob", "sub/*.gemspec", "--skip-install"])
          code.should eq(0)
          stderr.should eq("")
          File.read(File.join(dir, "Gemfile")).should contain(%(gem "json_pure", "~> 2.8", glob: "sub/*.gemspec"))
        end
      end
    end
  end

  it "rejects a value-less --version before touching the Gemfile" do
    with_add_home do
      gemfile = %(source "https://rubygems.org/"\n)
      with_project({"Gemfile" => gemfile}) do |dir|
        code, stdout, stderr = run_cli(["add", "thor", "--version", "--skip-install"])
        code.should eq(15)
        stdout.should eq("")
        stderr.should eq("Invalid gem requirement pattern 'version'\n")
        File.read(File.join(dir, "Gemfile")).should eq(gemfile)
      end
    end
  end

  it "reports a missing --path directory as a PathError without writing" do
    with_add_home do
      gemfile = %(source "https://rubygems.org/"\n)
      with_project({"Gemfile" => gemfile}) do |dir|
        code, stdout, stderr = run_cli(["add", "json_pure", "--path", "vendor/x", "--skip-install"])
        code.should eq(13)
        stdout.should eq("")
        stderr.should contain("does not exist.")
        File.read(File.join(dir, "Gemfile")).should eq(gemfile)
        Dir.exists?(File.join(dir, "vendor")).should be_false
      end
    end
  end

  it "accepts update --redownload as a force alias" do
    with_add_home do
      with_project({
        "Gemfile" => %(source "#{add_index_url}"\n\ngem "json_pure"\n),
      }) do |dir|
        with_bundle_path(File.join(dir, "bundle")) do
          run_cli(["install"])[0].should eq(0)
          code, _stdout, stderr = run_cli(["update", "--redownload"])
          code.should eq(0)
          stderr.should_not contain("Unknown switches")
        end
      end
    end
  end
end
