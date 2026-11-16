require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(2): `bundle open` (lib/bundler/cli/open.rb:12-26). Measured on 4.0.24:
#
#   bundle open                    => ERROR: "bundle open" was called with no arguments (15)
#   bundle open a b                => ERROR: ... called with arguments ["a", "b"]      (15)
#   bundle open gem --path         => Cannot specify `--path` option without a value   (15)
#   bundle open nosuchgem          => Could not find gem 'nosuchgem'.                  (7)
#   bundle open gem                => opens spec.full_gem_path (or the --path below it)
#   bundle open (no editor)        => To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR (0)
#
# `select_spec` (cli/common.rb:68-96) matches the exact name first, then treats
# the argument as a regex, then falls back to the interpreter's default gem and
# finally to the interactive picker.
private def open_gemfile : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {"Gemfile" => %(source "#{file_source_url(index)}"\n\ngem "json_pure", "2.8.1"\n)}
end

private def open_lockfile(dir : String) : String
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  <<-LOCK
    GEM
      remote: #{file_source_url(index)}/
      specs:
        json_pure (2.8.1)

    PLATFORMS
      x64-mingw-ucrt

    DEPENDENCIES
      json_pure (= 2.8.1)

    BUNDLED WITH
      4.0.24

    LOCK
end

private def seed_open_gem(dir : String) : String
  gem_dir = File.join(dir, "bundle", "ruby", "4.0.0", "gems", "json_pure-2.8.1")
  Dir.mkdir_p(File.join(gem_dir, "lib"))
  File.write(File.join(gem_dir, "lib", "json_pure.rb"), "# fixture\n")
  specs = File.join(dir, "bundle", "ruby", "4.0.0", "specifications")
  Dir.mkdir_p(specs)
  File.write(File.join(specs, "json_pure-2.8.1.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |spec|
      spec.name = "json_pure"
      spec.version = "2.8.1"
      spec.summary = "fixture"
      spec.authors = ["fixture"]
      spec.files = ["lib/json_pure.rb"]
      spec.require_paths = ["lib"]
    end
    GEMSPEC
  gem_dir
end

private def with_open_env(dir : String, editor : String?, & : ->)
  names = %w[HOME USERPROFILE GEM_HOME GEM_PATH BUNDLE_PATH BUNDLER_EDITOR VISUAL EDITOR
    CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB]
  previous = {} of String => String?
  names.each { |name| previous[name] = ENV[name]? }
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["GEM_HOME"] = File.join(dir, "gems")
  ENV["GEM_PATH"] = File.join(dir, "gems")
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  if editor
    ENV["BUNDLER_EDITOR"] = editor
    ENV["VISUAL"] = editor
    ENV["EDITOR"] = editor
  else
    ENV.delete("BUNDLER_EDITOR")
    ENV.delete("VISUAL")
    ENV.delete("EDITOR")
  end
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

private def run_open(rest : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  err = IO::Memory.new
  code = Celerite::Commands.open(output, err, rest)
  {code, output.to_s, err.to_s}
end

# A `.cmd` editor that records the path it was handed (Ruby's `system` runs it
# through the command processor; the product retries through cmd.exe too).
private def write_recording_editor(dir : String) : {String, String}
  log = File.join(dir, "editor-arg.txt")
  script = File.join(dir, "recording-editor.cmd")
  File.write(script, "@echo OFF\r\necho %1 > \"#{log}\"\r\n")
  {script, log}
end

describe "M7(2) bundle open" do
  it "reports the missing positional argument like Thor" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      with_open_env(dir, nil) do
        code, output, err = run_open([] of String)
        code.should eq(15)
        output.should be_empty
        err.should eq(%(ERROR: "bundle open" was called with no arguments\n) +
                      %(Usage: "bundle open GEM"\n))
      end
    end
  end

  it "reports extra positional arguments like Thor" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      with_open_env(dir, nil) do
        code, _output, err = run_open(["json_pure", "extra"])
        code.should eq(15)
        err.should eq(%(ERROR: "bundle open" was called with arguments ["json_pure", "extra"]\n) +
                      %(Usage: "bundle open GEM"\n))
      end
    end
  end

  it "rejects an empty --path before resolving anything" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      with_open_env(dir, nil) do
        code, _output, err = run_open(["json_pure", "--path"])
        code.should eq(15)
        err.should eq("Cannot specify `--path` option without a value\n")
      end
    end
  end

  it "asks for an editor before resolving the gem" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      File.write(File.join(dir, "Gemfile.lock"), open_lockfile(dir))
      with_open_env(dir, nil) do
        code, output, _err = run_open(["nosuchgem"])
        code.should eq(0)
        output.should eq("To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR\n")
      end
    end
  end

  it "reports a gem that is not in the bundle" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      File.write(File.join(dir, "Gemfile.lock"), open_lockfile(dir))
      seed_open_gem(dir)
      script, _log = write_recording_editor(dir)
      with_open_env(dir, script) do
        code, output, err = run_open(["nosuchgem"])
        code.should eq(7)
        output.should be_empty
        err.should eq("Could not find gem 'nosuchgem'.\n")
      end
    end
  end

  it "opens the exact gem name in the editor" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      File.write(File.join(dir, "Gemfile.lock"), open_lockfile(dir))
      gem_dir = seed_open_gem(dir)
      script, log = write_recording_editor(dir)
      with_open_env(dir, script) do
        code, _output, _err = run_open(["json_pure"])
        code.should eq(0)
        File.read(log).strip.should eq(gem_dir.tr("\\", "/"))
      end
    end
  end

  it "treats the name as a regex when it is not an exact match" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      File.write(File.join(dir, "Gemfile.lock"), open_lockfile(dir))
      gem_dir = seed_open_gem(dir)
      script, log = write_recording_editor(dir)
      with_open_env(dir, script) do
        code, _output, _err = run_open(["jso"])
        code.should eq(0)
        File.read(log).strip.should eq(gem_dir.tr("\\", "/"))
      end
    end
  end

  it "appends --path below the gem directory" do
    next unless ruby_available?
    with_project(open_gemfile) do |dir|
      File.write(File.join(dir, "Gemfile.lock"), open_lockfile(dir))
      gem_dir = seed_open_gem(dir)
      script, log = write_recording_editor(dir)
      with_open_env(dir, script) do
        code, _output, _err = run_open(["json_pure", "--path", "lib"])
        code.should eq(0)
        File.read(log).strip.should eq("#{gem_dir.tr("\\", "/")}/lib")
      end
    end
  end
end
