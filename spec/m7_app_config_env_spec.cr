require "./spec_helper"

# M7(3) task-51 F3: `BUNDLE_APP_CONFIG` replaces `<root>/.bundle` for the local
# config (and plugin root) — `Bundler.app_config_path` (bundler.rb:326-339)
# expands a relative value against the project root, not the working directory.
private def with_app_config(value : String?, &)
  previous = ENV["BUNDLE_APP_CONFIG"]?
  if value
    ENV["BUNDLE_APP_CONFIG"] = value
  else
    ENV.delete("BUNDLE_APP_CONFIG")
  end
  begin
    yield
  ensure
    if previous
      ENV["BUNDLE_APP_CONFIG"] = previous
    else
      ENV.delete("BUNDLE_APP_CONFIG")
    end
  end
end

private def run_config(rest : Array(String)) : {Int32, String, String}
  stdout_mem = IO::Memory.new
  stderr_mem = IO::Memory.new
  code = Celerite::Commands.config(stdout_mem, stderr_mem, rest)
  {code, stdout_mem.to_s, stderr_mem.to_s}
end

describe "M7 BUNDLE_APP_CONFIG resolution" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end

  it "uses an absolute BUNDLE_APP_CONFIG as the app config root" do
    with_project({"Gemfile" => "source \"https://rubygems.org/\"\n"}) do |dir|
      absolute = File.join(dir, "elsewhere", "appcfg")
      with_app_config(absolute) do
        Celerite::Config.app_config_path(dir).should eq(absolute)
        # `Config.join_config` always appends with a forward slash (task-56).
        Celerite::Config.new(dir).local_config_file.should eq("#{absolute}/config")
      end
    end
  end

  it "expands a relative BUNDLE_APP_CONFIG against the project root, not the cwd" do
    with_project({"Gemfile" => "source \"https://rubygems.org/\"\n"}) do |dir|
      parent = File.dirname(dir)
      with_app_config("relcfg") do
        Dir.cd(parent) do
          Celerite::Config.app_config_path(dir).should eq(File.join(dir, "relcfg").gsub('\\', "/"))
        end
      end
    end
  end

  it "writes --local config under BUNDLE_APP_CONFIG and reports that path" do
    with_project({"Gemfile" => "source \"https://rubygems.org/\"\n"}) do |dir|
      with_app_config("appcfg") do
        code, _out_text, err_text = run_config(["set", "--local", "nope_key", "value"])
        code.should eq(0)
        err_text.should eq("")
        File.file?(File.join(dir, "appcfg", "config")).should be_true
        Dir.exists?(File.join(dir, ".bundle")).should be_false

        code, out_text, _err_text = run_config(["get", "nope_key"])
        code.should eq(0)
        out_text.should contain("appcfg")
        out_text.should contain("nope_key")
        out_text.should contain("\"value\"")
      end
    end
  end

  it "keeps <root>/.bundle when BUNDLE_APP_CONFIG is unset" do
    with_project({"Gemfile" => "source \"https://rubygems.org/\"\n"}) do |dir|
      with_app_config(nil) do
        Celerite::Config.app_config_path(dir).should eq(File.join(dir, ".bundle").gsub('\\', "/"))
        Celerite::Config.new(dir).local_config_file.should eq("#{File.join(dir, ".bundle").gsub('\\', "/")}/config")
      end
    end
  end
end
