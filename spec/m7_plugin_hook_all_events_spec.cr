require "./spec_helper"

# Install-all hooks (M7 task-45): the reference fires
# `Bundler::Plugin.hook(GEM_BEFORE_INSTALL_ALL, definition.dependencies)` before
# `Installer#run` and `GEM_AFTER_INSTALL_ALL` after it
# (bundler-4.0.24/lib/bundler/installer.rb:12-20), handing the block the
# Gemfile dependencies array. Both hooks fire on every `install`, including a
# rerun that changes nothing and a Gemfile with zero dependencies, and neither
# fires when `BUNDLE_PLUGINS=false`.

private def with_all_hook_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
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

private def with_all_hook_home(dir : String, &)
  home = ENV["HOME"]?
  profile = ENV["USERPROFILE"]?
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  begin
    yield
  ensure
    if home
      ENV["HOME"] = home
    else
      ENV.delete("HOME")
    end
    if profile
      ENV["USERPROFILE"] = profile
    else
      ENV.delete("USERPROFILE")
    end
  end
end

private def with_all_hook_plugins(value : String?, &)
  previous = ENV["BUNDLE_PLUGINS"]?
  if value
    ENV["BUNDLE_PLUGINS"] = value
  else
    ENV.delete("BUNDLE_PLUGINS")
  end
  begin
    yield
  ensure
    if previous
      ENV["BUNDLE_PLUGINS"] = previous
    else
      ENV.delete("BUNDLE_PLUGINS")
    end
  end
end

private def all_hook_gemfile : String
  String.build do |io|
    io.puts %(gem "alpha", path: "./alpha")
    io.puts %(gem "beta", path: "./beta")
  end
end

private def all_hook_plugins_rb : String
  String.build do |io|
    io.puts %(require "bundler/plugin/api")
    io.puts
    io.puts %(Bundler::Plugin.add_hook("before-install-all") do |deps|)
    io.puts %(  puts "BEFORE_ALL class=\#{deps.class} names=\#{deps.map(&:name).join(",")}")
    io.puts %(end)
    io.puts
    io.puts %(Bundler::Plugin.add_hook("after-install-all") do |deps|)
    io.puts %(  puts "AFTER_ALL class=\#{deps.class} names=\#{deps.map(&:name).join(",")}")
    io.puts %(end)
  end
end

private def all_hook_write_plugin(dir : String) : Nil
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "hook_plugin.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "hook_plugin"
      s.version = "0.1.0"
      s.summary = "install-all hook probe"
      s.authors = ["Fixture"]
      s.files = ["plugins.rb", "lib/hook_plugin.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
  File.write(File.join(dir, "plugins.rb"), all_hook_plugins_rb)
  File.write(File.join(dir, "lib", "hook_plugin.rb"), "module HookPlugin\nend\n")
end

private def all_hook_write_path_gem(root : String, name : String) : Nil
  dir = File.join(root, name)
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "#{name}.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "0.1.0"
      s.summary = "#{name}"
      s.authors = ["Fixture"]
      s.files = ["lib/#{name}.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
  File.write(File.join(dir, "lib", "#{name}.rb"), "module #{name.capitalize}\nend\n")
end

private def run_all_hook_install(dir : String, plugins : String? = nil) : Tuple(Int32, String, String)
  with_all_hook_home(dir) do
    with_all_hook_plugins(plugins) do
      return run_cli(["install"])
    end
  end
end

describe "M7 task-45 install-all plugin hooks" do
  it "exposes the reference install-all event names" do
    Celerite::PluginHooks::EVENTS.should eq(
      ["after-install", "before-install-all", "after-install-all"])
  end

  it "fires before-install-all before resolving and after-install-all after installing" do
    pending! "ruby not available" unless ruby_available?
    with_all_hook_bridge do
      with_project({"Gemfile" => all_hook_gemfile}) do |dir|
        %w[alpha beta].each { |name| all_hook_write_path_gem(dir, name) }
        all_hook_write_plugin(File.join(dir, "hook_plugin"))

        code, _out, err = run_cli(["plugin", "install", "hook_plugin",
                                   "--path", File.join(dir, "hook_plugin")])
        code.should eq(0)
        err.should be_empty

        code, out, err = run_all_hook_install(dir)
        code.should eq(0)
        err.should be_empty
        out.should contain("BEFORE_ALL class=Array names=alpha,beta")
        out.should contain("AFTER_ALL class=Array names=alpha,beta")

        before = out.index("BEFORE_ALL").not_nil!
        resolving = out.index("Resolving dependencies...").not_nil!
        after = out.index("AFTER_ALL").not_nil!
        complete = out.index("Bundle complete!").not_nil!
        (before < resolving).should be_true
        (resolving < after).should be_true
        (after < complete).should be_true
      end
    end
  end

  it "fires both hooks again on a rerun that changes nothing" do
    pending! "ruby not available" unless ruby_available?
    with_all_hook_bridge do
      with_project({"Gemfile" => all_hook_gemfile}) do |dir|
        %w[alpha beta].each { |name| all_hook_write_path_gem(dir, name) }
        all_hook_write_plugin(File.join(dir, "hook_plugin"))
        run_cli(["plugin", "install", "hook_plugin", "--path", File.join(dir, "hook_plugin")])

        run_all_hook_install(dir)[1].scan(/BEFORE_ALL/).size.should eq(1)
        _code, out, _err = run_all_hook_install(dir)
        out.scan(/BEFORE_ALL/).size.should eq(1)
        out.scan(/AFTER_ALL/).size.should eq(1)
      end
    end
  end

  it "stays silent when BUNDLE_PLUGINS is false" do
    pending! "ruby not available" unless ruby_available?
    with_all_hook_bridge do
      with_project({"Gemfile" => all_hook_gemfile}) do |dir|
        %w[alpha beta].each { |name| all_hook_write_path_gem(dir, name) }
        all_hook_write_plugin(File.join(dir, "hook_plugin"))
        run_cli(["plugin", "install", "hook_plugin", "--path", File.join(dir, "hook_plugin")])

        code, out, _err = run_all_hook_install(dir, "false")
        code.should eq(0)
        out.should_not contain("BEFORE_ALL")
        out.should_not contain("AFTER_ALL")
      end
    end
  end
end
