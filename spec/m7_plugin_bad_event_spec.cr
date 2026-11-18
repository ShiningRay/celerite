require "./spec_helper"

# Undefined plugin hook events (M7 task-15, G1): when a plugin's `plugins.rb`
# declares a hook for an event Bundler does not know, `plugin install` must fail
# with exit 29 and the reference's two-line malformed-plugin message, and it must
# leave no plugin index behind.
#
# Reference: bundler-4.0.24 `lib/bundler/plugin.rb:215-217` raises
# `ArgumentError, "Event '<event>' not defined in Bundler::Plugin::Events"` from
# `add_hook`, and `lib/bundler/cli/plugin.rb` reports the failure as
# `Failed to install plugin `<name>`, due to Bundler::Plugin::MalformattedPlugin`
# followed by `(<class>: <message>)`. Both 4.0.24 and 2.7.2 produce exit 29 with
# byte-identical stderr (verified by fixtures/differential/plugin-install-bad-event).

private def with_bad_event_bridge(&)
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

private def bad_event_gemfile : String
  remote = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
  "source \"#{remote}\"\n\ngem \"json_pure\"\n"
end

# <dir>/<name>.gemspec + plugins.rb + lib/<name>.rb, mirroring the fixtures'
# plugin shape. `hook_event` is the event the plugin declares an (empty) hook
# for; a nil value writes the same plugin without any hook declaration.
private def bad_event_write_source(dir : String, name : String, hook_event : String?) : Nil
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "#{name}.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "0.1.0"
      s.summary = "#{name}"
      s.authors = ["Fixture"]
      s.files = ["plugins.rb", "lib/#{name}.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
  plugins_rb = String.build do |io|
    io.puts %(require "bundler/plugin")
    io.puts %(require "#{name}")
    io.puts
    io.puts %(module BadEventProbe)
    io.puts %(  class ProbeCommand)
    io.puts %(    def exec(command, args))
    io.puts %(      0)
    io.puts %(    end)
    io.puts %(  end)
    io.puts %(end)
    io.puts
    io.puts %(Bundler::Plugin::API.command("badeventprobe", BadEventProbe::ProbeCommand))
    if event = hook_event
      io.puts %(Bundler::Plugin.add_hook(#{event.inspect}) { |_ctx| })
    end
  end
  File.write(File.join(dir, "plugins.rb"), plugins_rb)
  File.write(File.join(dir, "lib", "#{name}.rb"), "module BadEventFixture\nend\n")
end

private def bad_event_plugins_rb(dir : String) : String
  File.join(dir, "plugins.rb")
end

describe "M7 task-15 undefined plugin hook events" do
  it "surfaces the probe error instead of silently dropping the declarations" do
    pending! "ruby not available" unless ruby_available?
    dir = File.tempname("celerite-spec", "bad-event")
    Dir.mkdir_p(dir)
    begin
      source = File.join(dir, "bad")
      bad_event_write_source(source, "bad", "post-install")
      declared = Celerite::PluginCommands.declared(bad_event_plugins_rb(source), [File.join(source, "lib")])
      declared[:commands].should be_empty
      declared[:hooks].should be_empty
      error = declared[:error].not_nil!
      error.should contain("Event 'post-install' not defined in Bundler::Plugin::Events")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "fails the plugin install with the reference message and writes no index" do
    pending! "ruby not available" unless ruby_available?
    with_bad_event_bridge do
      with_project({"Gemfile" => bad_event_gemfile}) do |dir|
        source = File.join(dir, "bad")
        bad_event_write_source(source, "bad", "post-install")
        code, out, err = run_cli(["plugin", "install", "bad", "--path", source])
        code.should eq(29)
        out.should contain("Resolving dependencies...")
        out.should_not contain("Installed plugin")
        lines = err.lines.map(&.chomp).reject(&.empty?)
        lines.size.should eq(2)
        lines[0].should eq("Failed to install plugin `bad`, due to Bundler::Plugin::MalformattedPlugin")
        lines[1].should contain("ArgumentError: Event 'post-install' not defined in Bundler::Plugin::Events")
        File.exists?(File.join(dir, ".bundle", "plugin", "index")).should be_false
        File.exists?(File.join(dir, "Gemfile.lock")).should be_false
      end
    end
  end

  it "still installs a plugin whose hook event is defined" do
    pending! "ruby not available" unless ruby_available?
    with_bad_event_bridge do
      with_project({"Gemfile" => bad_event_gemfile}) do |dir|
        source = File.join(dir, "good")
        bad_event_write_source(source, "good", "after-install")
        code, out, err = run_cli(["plugin", "install", "good", "--path", source])
        code.should eq(0)
        err.should be_empty
        out.should contain("Installed plugin good")
        index = File.read(File.join(dir, ".bundle", "plugin", "index"))
        index.should contain(%(  badeventprobe: "good"))
        index.should contain(%(  after-install:\n  - "good"))
      end
    end
  end
end
