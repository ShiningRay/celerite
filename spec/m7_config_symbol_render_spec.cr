require "./spec_helper"

# `Symbol#inspect` decides how an array setting is rendered: a bare name keeps
# the short form, anything else is quoted (`config/  {get,list}` and
# `config list --parseable` share the same rendering helper).
private CONFIG_GEM_INDEX_URL = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def config_render_gemfile : String
  <<-GEMFILE
  source "#{CONFIG_GEM_INDEX_URL}"
  gem "json_pure"
  GEMFILE
end

describe "bundle config array rendering" do
  it "quotes a value that is not a bare symbol literal" do
    with_project({"Gemfile" => config_render_gemfile}) do |dir|
      with_config_render_env(dir) do
        run_cli(["config", "set", "--local", "without", "test,dev"]).first.should eq(0)
        code, out, _ = run_cli(["config", "get", "without"])
        code.should eq(0)
        out.should contain(%([:"test,dev"]))
        out.should_not contain("[:test,dev]")
      end
    end
  end

  it "uses the same rendering for `config list --parseable`" do
    with_project({"Gemfile" => config_render_gemfile}) do |dir|
      with_config_render_env(dir) do
        run_cli(["config", "set", "--local", "without", "test,dev"]).first.should eq(0)
        code, out, _ = run_cli(["config", "list", "--parseable"])
        code.should eq(0)
        out.should contain("without=[:\"test,dev\"]")
      end
    end
  end

  it "keeps the bare form for ordinary names" do
    with_project({"Gemfile" => config_render_gemfile}) do |dir|
      with_config_render_env(dir) do
        run_cli(["config", "set", "--local", "with", "test"]).first.should eq(0)
        _, out, _ = run_cli(["config", "get", "with"])
        out.should contain("[:test]")
      end
    end
  end
end

private def with_config_render_env(dir : String, &) : Nil
  names = %w[HOME USERPROFILE BUNDLE_APP_CONFIG CELERITE_BRIDGE_SERVER BUNDLE_PATH]
  saved = {} of String => String?
  names.each { |name| saved[name] = ENV[name]? }
  begin
    app_config = File.join(dir, ".bundle-app")
    Dir.mkdir_p(app_config)
    ENV["BUNDLE_APP_CONFIG"] = app_config
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV.delete("BUNDLE_PATH")
    yield
  ensure
    names.each do |name|
      value = saved[name]
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end
