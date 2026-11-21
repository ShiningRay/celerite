require "./spec_helper"

# task-97: `settings[:only]` intersects the requested group set
# (`definition.rb:1251-1254`), so install/list/check see only those groups while
# the lockfile keeps every dependency; `update` additionally reports the groups
# `without` skipped (`cli/update.rb:119`, `common.rb:49-58`).
private def only_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def only_group_gemfile : String
  "source \"#{only_index_url}\"\n\ngem \"json_pure\"\n\ngroup :test do\n  gem \"thor\"\nend\n"
end

private def with_only_env(only : String?, without : String?, & : String ->) : Nil
  previous = {} of String => String?
  {
    "HOME"                             => only_sandbox,
    "USERPROFILE"                      => only_sandbox,
    "GEM_HOME"                         => File.join(only_sandbox, "gems"),
    "GEM_PATH"                         => File.join(only_sandbox, "gems"),
    "BUNDLE_PATH"                      => File.join(only_sandbox, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(only_sandbox, ".bundle"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
  }.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
  end
  {"BUNDLE_ONLY" => only, "BUNDLE_WITHOUT" => without}.each do |key, value|
    previous[key] = ENV[key]?
    value ? (ENV[key] = value) : ENV.delete(key)
  end
  begin
    yield only_sandbox
  ensure
    previous.each do |key, value|
      value ? (ENV[key] = value) : ENV.delete(key)
    end
  end
end

private def only_sandbox : String
  dir = File.expand_path("../.tmp-scratch/spec-only-group", __DIR__)
  Dir.mkdir_p(dir)
  dir
end

private def only_run(dir : String, args : Array(String)) : {Int32, String, String}
  only_project(dir)
  code = 0
  out = IO::Memory.new
  err = IO::Memory.new
  Dir.cd(dir) do
    code, out_s, err_s = run_cli(args)
    out << out_s
    err << err_s
  end
  {code, out.to_s, err.to_s}
end

private def only_project(dir : String) : Nil
  File.write(File.join(dir, "Gemfile"), only_group_gemfile)
  {% if false %}{% end %}
end

describe "M7 task-97: the only setting and update group notices" do
  it "installs only the requested group" do
    with_only_env("test", nil) do |dir|
      code, out, _err = only_run(dir, ["install"])
      code.should eq(0)
      out.should contain("1 gem now installed")
      out.should_not contain("Fetching json_pure")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      lock.should contain("json_pure")
      lock.should contain("thor")
    end
  end

  it "lists only the requested group" do
    with_only_env("test", nil) do |dir|
      only_run(dir, ["install"])
      code, out, _err = only_run(dir, ["list"])
      code.should eq(0)
      out.should contain("thor (1.3.2)")
      out.should_not contain("json_pure")
    end
  end

  it "reports satisfied when every requested gem is installed" do
    with_only_env("test", nil) do |dir|
      only_run(dir, ["install"])
      code, out, _err = only_run(dir, ["check"])
      code.should eq(0)
      out.should contain("The Gemfile's dependencies are satisfied")
    end
  end

  it "names the excluded group after update" do
    with_only_env(nil, "test") do |dir|
      only_run(dir, ["install", "--quiet"])
      code, out, _err = only_run(dir, ["update", "--all"])
      code.should eq(0)
      out.should contain("Bundle updated!")
      out.should contain("Gems in the group 'test' were not updated.")
      out.should_not contain("Fetching thor")
    end
  end
end
