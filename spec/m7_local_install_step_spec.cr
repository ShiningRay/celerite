require "./spec_helper"

# M7 task-83: `install --local` restricts the SOURCES, not the install step.
# The reference still installs a gem it found in `vendor/cache` into the bundle
# path (`cli/install.rb:33` -> `Installer#run` -> `install(spec)`, where the
# skip condition is `installed?(spec)`, i.e. "already in this bundle"). Before
# this spec, celerite treated a host copy of the same name+version as installed
# and printed no `Installing` line at all, leaving the bundle empty.
private def local_step_index : String
  File.expand_path("../fixtures/gem-index", __DIR__)
end

private def local_step_bridge : String
  File.expand_path("../assets/bridge/server.rb", __DIR__)
end

private def local_step_root : String
  root = File.expand_path("../.tmp-scratch/spec-local-step", __DIR__)
  Dir.mkdir_p(root)
  root
end

private def local_step_restore(previous : Hash(String, String?)) : Nil
  previous.each do |key, value|
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
end

private def local_step_host_home(dir : String) : String
  home = File.join(dir, "hosthome")
  Dir.mkdir_p(home)
  status = Process.run("ruby", ["-S", "gem", "install", "--no-document", "--install-dir", home,
                                "--local", File.join(local_step_index, "gems", "json_pure-2.6.0.gem")],
    output: IO::Memory.new, error: IO::Memory.new)
  status.success?.should be_true
  home
end

private def with_local_step_env(dir : String, gem_home : String, &)
  keys = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_APP_CONFIG GEM_HOME GEM_PATH
    CELERITE_BRIDGE_SERVER CELERITE_PROFILE_BUNDLER_VERSION]
  previous = keys.to_h { |key| {key, ENV[key]?} }
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(dir, "appcfg")
  ENV["CELERITE_BRIDGE_SERVER"] = local_step_bridge
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  Dir.mkdir_p(File.join(dir, "appcfg"))
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = gem_home
  Dir.mkdir_p(gem_home)
  begin
    yield
  ensure
    local_step_restore(previous)
  end
end

private def local_step_project(dir : String, vendored : Bool) : String
  project = File.join(dir, "project")
  FileUtils.rm_rf(project)
  Dir.mkdir_p(project)
  File.write(File.join(project, "Gemfile"), %(source "file:///#{local_step_index.gsub('\\', "/")}"\ngem "json_pure", "2.6.0"\n))
  if vendored
    cache = File.join(project, "vendor", "cache")
    Dir.mkdir_p(cache)
    File.copy(File.join(local_step_index, "gems", "json_pure-2.6.0.gem"),
      File.join(cache, "json_pure-2.6.0.gem"))
  end
  project
end

private def local_step_run(project : String, args : Array(String)) : {Int32, String, String}
  Dir.cd(project) { run_cli(args) }
end

describe "M7 task-83: install --local still installs cached gems" do
  it "installs the vendored gem into the bundle path" do
    dir = File.join(local_step_root, "install")
    FileUtils.rm_rf(dir)
    with_local_step_env(dir, local_step_host_home(dir)) do
      project = local_step_project(dir, vendored: true)
      code, out, _err = local_step_run(project, ["install", "--local"])
      code.should eq(0)
      out.should contain("Installing json_pure 2.6.0")
      Dir.glob(File.join(dir, "bundle", "*", "*", "specifications", "json_pure-2.6.0.gemspec").gsub('\\', "/"))
        .should_not be_empty
    end
  end

  it "does not reinstall on a second run" do
    dir = File.join(local_step_root, "twice")
    FileUtils.rm_rf(dir)
    with_local_step_env(dir, local_step_host_home(dir)) do
      project = local_step_project(dir, vendored: true)
      first = local_step_run(project, ["install", "--local"])
      first[0].should eq(0)
      code, out, _err = local_step_run(project, ["install", "--local"])
      code.should eq(0)
      out.should_not contain("Installing json_pure")
    end
  end

  it "still reports a missing gem when the cache is empty" do
    dir = File.join(local_step_root, "missing")
    FileUtils.rm_rf(dir)
    with_local_step_env(dir, File.join(dir, "emptyhome")) do
      project = local_step_project(dir, vendored: false)
      Dir.mkdir_p(File.join(project, "vendor", "cache"))
      code, _out, err = local_step_run(project, ["install", "--local"])
      code.should eq(7)
      err.should contain("in cached gems or installed locally")
    end
  end
end
