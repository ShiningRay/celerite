require "./spec_helper"

# task-96 A: `settings.rb:312-319` validates every setting before `doctor`
# proceeds, and the `path`/`path.system` rule (`settings/validator.rb:57-63`)
# prints `Setting `key` to nil, since path and path.system are mutually
# exclusive` for both keys before `Path#validate!` raises (exit 15).
private def doctor_settings_index : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def with_doctor_settings_env(project : String, settings : Hash(String, String?), & : String ->) : Nil
  keys = ["HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH",
          "BUNDLE_PATH__SYSTEM", "BUNDLE_DISABLE_SHARED_GEMS", "CELERITE_BRIDGE_SERVER",
          "CELERITE_PROFILE_BUNDLER_VERSION"]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]? }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["GEM_HOME"] = File.join(project, "gems")
  ENV["GEM_PATH"] = File.join(project, "gems")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  settings.each do |key, value|
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
  begin
    yield project
  ensure
    previous.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def doctor_settings_gemfile : Hash(String, String)
  {"Gemfile" => "source \"#{doctor_settings_index}\"\n\ngem \"json_pure\"\n"}
end

describe "task-96 doctor settings conflict" do
  it "prints both mutual-exclusion notices before failing" do
    with_project(doctor_settings_gemfile) do |project|
      with_doctor_settings_env(project, {"BUNDLE_PATH" => "./relbundle", "BUNDLE_PATH__SYSTEM" => "true"}) do |dir|
        code, out, err = run_cli(["doctor"])
        # The in-process harness surfaces the raised error through the generic
        # handler, so the CLI-driven fixture pins the exact exit code (15).
        code.should_not eq(0)
        out.lines.first?.should eq("Setting `path.system` to nil, since path and path.system are mutually exclusive")
        out.lines[1]?.should eq("Setting `path` to nil, since path and path.system are mutually exclusive")
        err.should contain("Using a custom path while using system gems is unsupported.")
      end
    end
  end

  it "keeps the notices silent when only the path is configured" do
    with_project(doctor_settings_gemfile) do |project|
      with_doctor_settings_env(project, {"BUNDLE_PATH" => "./relbundle", "BUNDLE_PATH__SYSTEM" => nil}) do |dir|
        code, out, _ = run_cli(["doctor"])
        code.should_not eq(15)
        out.should_not contain("mutually exclusive")
      end
    end
  end

  it "treats the legacy disable_shared_gems: false like path.system" do
    with_project(doctor_settings_gemfile) do |project|
      with_doctor_settings_env(project, {"BUNDLE_PATH" => "./relbundle", "BUNDLE_DISABLE_SHARED_GEMS" => "false"}) do |dir|
        code, out, err = run_cli(["doctor"])
        code.should_not eq(0)
        out.should contain("Setting `path.system` to nil, since path and path.system are mutually exclusive")
        out.should contain("Setting `path` to nil, since path and path.system are mutually exclusive")
        err.should contain("Using a custom path while using system gems is unsupported.")
      end
    end
  end
end
