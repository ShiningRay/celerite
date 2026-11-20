require "./spec_helper"

private FROZEN_LOCKFILE_MESSAGE     = "The frozen setting requires a lockfile. Please make sure you have checked your\nGemfile.lock into version control before deploying.\n"
private DEPLOYMENT_LOCKFILE_MESSAGE = "The deployment setting requires a lockfile. Please make sure you have checked\nyour Gemfile.lock into version control before deploying.\n"

private def with_frozen_env(env : Hash(String, String), &) : Nil
  keys = ["BUNDLE_FROZEN", "BUNDLE_DEPLOYMENT", "CELERITE_PROFILE_BUNDLER_VERSION", "CELERITE_REFERENCE_BUNDLER_VERSION", "CELERITE_REFERENCE_BUNDLER_LIB"]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]?; ENV.delete(key) }
  env.each { |key, value| ENV[key] = value }
  begin
    yield
  ensure
    keys.each do |key|
      ENV.delete(key)
      if value = previous[key]
        ENV[key] = value
      end
    end
  end
end

private def frozen_nolock_files : Hash(String, String)
  {"Gemfile" => %(source "file:///#{File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")}"\n\ngem "json_pure"\n)}
end

private def frozen_install(env : Hash(String, String)) : {Int32, String, String}
  code = 0
  out = ""
  err = ""
  with_frozen_env(env) do
    code, out, err = run_cli(["install"])
  end
  {code, out, err}
end

describe "M7(3) frozen/deployment no-lockfile install message" do
  it "names the frozen setting when BUNDLE_FROZEN is set" do
    with_project(frozen_nolock_files) do
      code, out, err = frozen_install({"BUNDLE_FROZEN" => "true"})
      code.should eq(16)
      out.should eq("")
      err.should eq(FROZEN_LOCKFILE_MESSAGE)
    end
  end

  it "names the deployment setting when BUNDLE_DEPLOYMENT is set" do
    with_project(frozen_nolock_files) do
      code, out, err = frozen_install({"BUNDLE_DEPLOYMENT" => "true"})
      code.should eq(16)
      out.should eq("")
      err.should eq(DEPLOYMENT_LOCKFILE_MESSAGE)
    end
  end

  it "lets frozen win over deployment in the 4.x profile" do
    with_project(frozen_nolock_files) do
      code, _, err = frozen_install({"BUNDLE_FROZEN" => "true", "BUNDLE_DEPLOYMENT" => "true", "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24"})
      code.should eq(16)
      err.should eq(FROZEN_LOCKFILE_MESSAGE)
    end
  end

  it "lets deployment win over frozen in the 2.7.2 profile" do
    with_project(frozen_nolock_files) do
      code, _, err = frozen_install({"BUNDLE_FROZEN" => "true", "BUNDLE_DEPLOYMENT" => "true", "CELERITE_PROFILE_BUNDLER_VERSION" => "2.7.2", "CELERITE_REFERENCE_BUNDLER_VERSION" => "2.7.2", "CELERITE_REFERENCE_BUNDLER_LIB" => "C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-2.7.2/lib"})
      code.should eq(16)
      err.should eq(DEPLOYMENT_LOCKFILE_MESSAGE)
    end
  end

  it "keeps the check-specific wording (regression guard)" do
    with_project(frozen_nolock_files) do
      code = 0
      err = ""
      with_frozen_env({"BUNDLE_FROZEN" => "true"}) do
        code, _, err = run_cli(["check"])
      end
      code.should eq(16)
      err.should eq("Frozen mode is set, but there's no lockfile\n")
    end
  end
end
