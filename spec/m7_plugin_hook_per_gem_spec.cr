require "./spec_helper"

# Per-spec `after-install` coverage (M7 task-11): the reference fires
# `Bundler::Plugin.hook(Events::GEM_AFTER_INSTALL, spec_install)` from inside
# the installer for *every* spec whose install just finished
# (`bundler-4.0.24/lib/bundler/installer/parallel_installer.rb:205-219`), and
# the running Bundler's own spec is part of that set and observed first.
# Re-running `install` with nothing to do fires the hook again for the same
# specs (oracle11b, 4.0.24 + 2.7.2).
#
# The hook receives the spec installation object, so blocks read `ctx.name`
# (`parallel_installer.rb:8-59` exposes `:name`, `:full_name`, `:state`).

private def with_per_gem_bridge(&)
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

private def with_per_gem_home(dir : String, &)
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

private def with_per_gem_plugins(value : String?, &)
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

private def per_gem_gemfile : String
  String.build do |io|
    io.puts %(gem "alpha", path: "./alpha")
    io.puts %(gem "beta", path: "./beta")
    io.puts %(gem "gamma", path: "./gamma")
  end
end

# Same shape without path sources: path specs cannot be re-materialized from a
# lockfile without hitting the network yet (existing gap, out of task-11 scope),
# so the repeat-install example uses the local gem index instead.
private def per_gem_index_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  String.build do |io|
    io.puts %(source "#{remote}")
    io.puts
    io.puts %(gem "json_pure")
    io.puts %(gem "thor")
  end
end

# The plugin's `after-install` hook records the spec name it was handed.
private def per_gem_plugins_rb(log : String) : String
  String.build do |io|
    io.puts %(require "bundler/plugin")
    io.puts %(require "hook_plugin")
    io.puts
    io.puts %(module HookProbe)
    io.puts %(  class ProbeCommand)
    io.puts %(    def exec(command, args))
    io.puts %(      0)
    io.puts %(    end)
    io.puts %(  end)
    io.puts %(end)
    io.puts
    io.puts %(Bundler::Plugin::API.command("hookprobe", HookProbe::ProbeCommand))
    io.puts %(Bundler::Plugin.add_hook("after-install") do |ctx|)
    io.puts %(  File.open(#{log.inspect}, "a") { |f| f.puts "after-install:\#{ctx.name}" })
    io.puts %(end)
  end
end

private def per_gem_write_source(dir : String, log : String) : Nil
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "hook_plugin.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "hook_plugin"
      s.version = "0.1.0"
      s.summary = "per-spec hook probe"
      s.authors = ["Fixture"]
      s.files = ["plugins.rb", "lib/hook_plugin.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
  File.write(File.join(dir, "plugins.rb"), per_gem_plugins_rb(log))
  File.write(File.join(dir, "lib", "hook_plugin.rb"), "module HookPlugin\nend\n")
end

private def per_gem_write_path_gem(root : String, name : String) : Nil
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

private def per_gem_log_lines(path : String) : Array(String)
  File.exists?(path) ? File.read(path).lines : [] of String
end

private def run_per_gem_install(dir : String) : Tuple(Int32, String, String)
  with_per_gem_home(dir) do
    with_per_gem_plugins(nil) do
      return run_cli(["install"])
    end
  end
end

describe "M7 task-11 plugin hook per install spec" do
  it "runs the hook once per spec in the install set, Bundler first" do
    pending! "ruby not available" unless ruby_available?
    with_per_gem_bridge do
      with_project({"Gemfile" => per_gem_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        %w[alpha beta gamma].each { |name| per_gem_write_path_gem(dir, name) }
        per_gem_write_source(File.join(dir, "hook_plugin"), log)

        code, _out, err = run_cli(["plugin", "install", "hook_plugin",
                                   "--path", File.join(dir, "hook_plugin")])
        code.should eq(0)
        err.should be_empty

        code, out, err = run_per_gem_install(dir)
        code.should eq(0)
        err.should be_empty
        out.should contain("Bundle complete!")
        lines = per_gem_log_lines(log)
        lines.size.should eq(4)
        lines[0].should eq("after-install:bundler")
        lines[1..].should eq(["after-install:alpha", "after-install:beta", "after-install:gamma"])
      end
    end
  end

  it "fires the hooks again on an install that changes nothing" do
    pending! "ruby not available" unless ruby_available?
    with_per_gem_bridge do
      with_project({"Gemfile" => per_gem_index_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        per_gem_write_source(File.join(dir, "hook_plugin"), log)
        run_cli(["plugin", "install", "hook_plugin", "--path", File.join(dir, "hook_plugin")])

        run_per_gem_install(dir)[0].should eq(0)
        lines = per_gem_log_lines(log)
        lines.size.should eq(3)
        lines[0].should eq("after-install:bundler")
        run_per_gem_install(dir)[0].should eq(0)
        lines = per_gem_log_lines(log)
        lines.size.should eq(6)
        lines[3].should eq("after-install:bundler")
        lines[3..].sort.should eq(["after-install:bundler", "after-install:json_pure", "after-install:thor"])
      end
    end
  end

  it "aborts at the first raising hook without writing a lockfile" do
    pending! "ruby not available" unless ruby_available?
    with_per_gem_bridge do
      with_project({"Gemfile" => per_gem_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        %w[alpha beta gamma].each { |name| per_gem_write_path_gem(dir, name) }
        source = File.join(dir, "hook_plugin")
        per_gem_write_source(source, log)
        File.write(File.join(source, "plugins.rb"), <<-RUBY)
          require "bundler/plugin"
          require "hook_plugin"

          module HookProbe
            class ProbeCommand
              def exec(command, args)
                0
              end
            end
          end

          Bundler::Plugin::API.command("hookprobe", HookProbe::ProbeCommand)
          Bundler::Plugin.add_hook("after-install") do |ctx|
            raise "boom per-gem"
          end
          RUBY
        run_cli(["plugin", "install", "hook_plugin", "--path", source])

        code, _out, err = run_per_gem_install(dir)
        code.should eq(1)
        err.should contain("Plugin hook after-install failed: boom per-gem")
        File.exists?(File.join(dir, "Gemfile.lock")).should be_false
      end
    end
  end

  it "passes the spec name to hooks through the bridge payload" do
    pending! "ruby not available" unless ruby_available?
    with_per_gem_bridge do
      with_project({"Gemfile" => per_gem_gemfile}) do |dir|
        log = File.join(dir, "hook-log")
        %w[alpha beta gamma].each { |name| per_gem_write_path_gem(dir, name) }
        per_gem_write_source(File.join(dir, "hook_plugin"), log)
        run_cli(["plugin", "install", "hook_plugin", "--path", File.join(dir, "hook_plugin")])
        run_per_gem_install(dir)[0].should eq(0)

        # `ctx` is the spec installation the reference hands over
        # (`parallel_installer.rb:8-59`): name, full_name and state are readable.
        lines = per_gem_log_lines(log)
        lines.should contain("after-install:bundler")
        lines.should contain("after-install:alpha")
        lines.all? { |line| line.starts_with?("after-install:") }.should be_true
      end
    end
  end
end
