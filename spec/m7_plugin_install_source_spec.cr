require "./spec_helper"

# M7(6): `plugin install <gem> --source <index>` must work end-to-end without
# relying on the system TEMP directory, must materialize the plugin gem under
# `<project>/.bundle/plugin/gems` (Bundler::Plugin.root), and the plugin's
# commands must keep working when the project has no Gemfile (global plugin
# root `~/.bundle/plugin`).

private def plugin_source_bin : String?
  candidate = File.expand_path("../bin/celerite.exe", __DIR__)
  return candidate if File.file?(candidate)

  fallback = File.expand_path("../bin/celerite", __DIR__)
  File.file?(fallback) ? fallback : nil
end

private def plugin_source_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def plugin_source_index_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index-plugin", __DIR__))
end

private def plugin_source_files : Hash(String, String)
  {
    "Gemfile" => "source \"#{plugin_source_remote}\"\n\ngem \"json_pure\"\n",
  }
end

private def with_plugin_source_env(project : String, &)
  names = ["HOME", "USERPROFILE", "BUNDLE_PATH", "TEMP", "TMP", "TMPDIR"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  # The reference uses the project's `.bundle/tmp`; the system TEMP must not be
  # touched at all. Point TEMP/TMP/TMPDIR at a regular *file* so any attempt to
  # create a directory underneath it fails (the sandbox also denies writes
  # outside the workspace, which is how the original defect surfaced).
  blocked_temp = File.join(project, "blocked-temp")
  File.write(blocked_temp, "")
  ENV["TEMP"] = blocked_temp
  ENV["TMP"] = blocked_temp
  ENV["TMPDIR"] = blocked_temp
  begin
    yield
  ensure
    previous.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def run_plugin_source(bin : String, project : String, args : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(bin, args, chdir: project, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

describe "M7(6) plugin install --source" do
  it "installs into the project plugin tree without a writable system TEMP" do
    bin = plugin_source_bin
    pending!("build bin/celerite.exe first") unless bin

    with_project(plugin_source_files) do |dir|
      with_plugin_source_env(dir) do
        code, output, errors = run_plugin_source(bin, dir, [
          "plugin", "install", "candle_plug", "--source", plugin_source_index_remote,
        ])
        code.should eq(0)
        errors.should_not contain("Unable to create directory")
        errors.should_not contain("celerite internal error")
        output.should contain("Installed plugin candle_plug")

        index_path = File.join(dir, ".bundle", "plugin", "index")
        File.file?(index_path).should be_true
        index = YAML.parse(File.read(index_path))
        plugin_path = index["plugin_paths"]["candle_plug"].as_s
        load_path = index["load_paths"]["candle_plug"][0].as_s
        plugin_path.gsub('\\', "/").should end_with("/.bundle/plugin/gems/candle_plug-0.1.0")
        load_path.gsub('\\', "/").should end_with("/.bundle/plugin/gems/candle_plug-0.1.0/lib")
        plugin_path.should_not contain("/bundle/ruby/")

        File.file?(File.join(dir, ".bundle", "plugin", "gems", "candle_plug-0.1.0", "plugins.rb")).should be_true
        File.file?(File.join(dir, ".bundle", "plugin", "specifications", "candle_plug-0.1.0.gemspec")).should be_true
        File.file?(File.join(dir, ".bundle", "plugin", "cache", "candle_plug-0.1.0.gem")).should be_true
        File.exists?(File.join(dir, ".bundle", "tmp")).should be_false
      end
    end
  end

  it "lists and runs the plugin command, including without a Gemfile" do
    bin = plugin_source_bin
    pending!("build bin/celerite.exe first") unless bin

    with_project(plugin_source_files) do |dir|
      with_plugin_source_env(dir) do
        run_plugin_source(bin, dir, ["plugin", "install", "candle_plug", "--source", plugin_source_index_remote])[0].should eq(0)

        code, output, _errors = run_plugin_source(bin, dir, ["plugin", "list"])
        code.should eq(0)
        output.should eq("candle_plug\n-----\n  candle\n\n")

        code, output, _errors = run_plugin_source(bin, dir, ["candle", "x", "y"])
        code.should eq(0)
        output.should contain("candle: x,y")

        # Without a Gemfile the reference looks at the global plugin root
        # (`~/.bundle/plugin`); with HOME=project that is the same tree.
        File.delete(File.join(dir, "Gemfile"))
        code, output, _errors = run_plugin_source(bin, dir, ["plugin", "list"])
        code.should eq(0)
        output.should contain("candle_plug")

        code, output, _errors = run_plugin_source(bin, dir, ["candle", "x", "y"])
        code.should eq(0)
        output.should contain("candle: x,y")
      end
    end
  end

  it "reports no plugins when neither the project nor the global root has one" do
    bin = plugin_source_bin
    pending!("build bin/celerite.exe first") unless bin

    with_project({} of String => String) do |dir|
      with_plugin_source_env(dir) do
        ENV["HOME"] = File.join(dir, "empty-home")
        ENV["USERPROFILE"] = ENV["HOME"]
        Dir.mkdir_p(ENV["HOME"])

        code, output, _errors = run_plugin_source(bin, dir, ["plugin", "list"])
        code.should eq(0)
        output.should eq("No plugins installed\n")

        code, _output, errors = run_plugin_source(bin, dir, ["candle", "x", "y"])
        code.should eq(15)
        errors.should contain("Could not find command \"candle\".")
      end
    end
  end
end
