require "./spec_helper"

# `GemfileEvaluation#ruby` is the human-readable requirement string and drops
# the option fields, so validating through it loses `patchlevel`
# (`ruby_version.cr:64-71`). Every runtime check must use the structured
# declaration (`cli/install.rb:24`, `cli/clean.rb`, `cli/exec.rb`,
# `cli/outdated.rb` all call `validate_runtime!`).
private PATCHLEVEL_INDEX_URL = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def patchlevel_gemfile(patchlevel : String = "999") : String
  <<-GEMFILE
  source "#{PATCHLEVEL_INDEX_URL}"

  ruby "4.0.6", patchlevel: "#{patchlevel}"

  gem "json_pure"
  GEMFILE
end

private EXPECTED_PATCHLEVEL_MESSAGE = "Your Ruby patchlevel is 0, but your Gemfile specified 999"

describe "Gemfile patchlevel validation" do
  it "refuses to install when the declared patchlevel differs" do
    with_project({"Gemfile" => patchlevel_gemfile}) do |dir|
      with_patchlevel_env(dir, bundle_path: File.join(dir, "bundle")) do
        code, out, err = run_cli(["install"])
        code.should eq(18)
        err.should contain(EXPECTED_PATCHLEVEL_MESSAGE)
        out.should_not contain("Bundle complete!")
      end
    end
  end

  it "refuses to clean when the declared patchlevel differs" do
    with_project({"Gemfile" => patchlevel_gemfile}) do |dir|
      with_patchlevel_env(dir, bundle_path: File.join(dir, "bundle")) do
        code, _, err = run_cli(["clean"])
        code.should eq(18)
        err.should contain(EXPECTED_PATCHLEVEL_MESSAGE)
      end
    end
  end

  it "refuses to exec when the declared patchlevel differs" do
    with_project({"Gemfile" => patchlevel_gemfile}) do |dir|
      with_patchlevel_env(dir, bundle_path: File.join(dir, "bundle")) do
        code, out, err = run_cli(["exec", "ruby", "-e", "puts :ran"])
        code.should eq(18)
        err.should contain(EXPECTED_PATCHLEVEL_MESSAGE)
        out.should_not contain("ran")
      end
    end
  end

  it "refuses to report outdated gems when the declared patchlevel differs" do
    with_project({"Gemfile" => patchlevel_gemfile}) do |dir|
      with_patchlevel_env(dir, bundle_path: File.join(dir, "bundle")) do
        code, _, err = run_cli(["outdated"])
        code.should eq(18)
        err.should contain(EXPECTED_PATCHLEVEL_MESSAGE)
      end
    end
  end
end

private def with_patchlevel_env(dir : String, bundle_path : String, &) : Nil
  names = %w[BUNDLE_PATH BUNDLE_APP_CONFIG HOME USERPROFILE GEM_HOME GEM_PATH CELERITE_BRIDGE_SERVER CELERITE_PROFILE_BUNDLER_VERSION]
  saved = {} of String => String?
  names.each { |name| saved[name] = ENV[name]? }
  begin
    app_config = File.join(dir, ".bundle-app")
    Dir.mkdir_p(app_config)
    Dir.mkdir_p(bundle_path)
    ENV["BUNDLE_PATH"] = bundle_path
    ENV["BUNDLE_APP_CONFIG"] = app_config
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["GEM_HOME"] = File.join(dir, "gemhome")
    ENV["GEM_PATH"] = File.join(dir, "gemhome")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
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
