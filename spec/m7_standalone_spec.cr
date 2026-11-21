require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(2) `install --standalone`: without a configured path the reference points
# `path` at `./bundle` for that command only (`set_command_option`,
# cli/install.rb L112-114), renders `definition.specs_for(groups)` into
# `<path>/bundler/setup.rb` (installer/standalone.rb L10-20), and opens the file
# in text mode, which is CRLF on Windows.
private def standalone_gemfile : String
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  String.build do |io|
    io.puts %(source "file:///#{index}/")
    io.puts ""
    io.puts %(gem "json_pure", "2.6.0")
    io.puts ""
    io.puts "group :development do"
    io.puts %(  gem "thor", "1.3.2")
    io.puts "end"
  end
end

private def with_standalone_env(dir : String, bundle_path : String? = nil, &)
  names = ["HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH"]
  saved = {} of String => String?
  names.each { |name| saved[name] = ENV[name]? }
  gem_home = File.join(dir, "gem-home")
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = gem_home
  if bundle_path
    ENV["BUNDLE_PATH"] = bundle_path
  else
    ENV.delete("BUNDLE_PATH")
  end
  begin
    yield
  ensure
    saved.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def with_standalone_bridge(&)
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

private def standalone_path_gem(root : String) : Nil
  Dir.mkdir_p(File.join(root, "lib"))
  File.write(File.join(root, "lib", "pgem.rb"), "module Pgem\n  VERSION = \"1.0.0\"\nend\n")
  File.write(File.join(root, "pgem.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "pgem"
      s.version = "1.0.0"
      s.summary = "pgem"
      s.authors = ["celerite"]
      s.files = ["lib/pgem.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
end

private def standalone_gemfile_with_path(declared : String) : String
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  String.build do |io|
    io.puts %(source "file:///#{index}/")
    io.puts ""
    io.puts %(gem "json_pure", "2.6.0")
    io.puts %(gem "pgem", path: "#{declared.gsub('\\', "/")}")
  end
end

private def standalone_require_works?(setup : String, project : String) : Bool
  ruby = Process.find_executable("ruby")
  return true if ruby.nil?
  output = IO::Memory.new
  status = Process.run(ruby, ["-r", setup, "-e", "require 'pgem'"], chdir: project,
    output: output, error: output)
  status.success?
end

describe "M7(2) install --standalone" do
  it "installs into ./bundle and renders setup.rb with CRLF" do
    with_standalone_bridge do
      with_project({"Gemfile" => standalone_gemfile}) do |dir|
        with_standalone_env(dir) do
          code, out, _err = run_cli(["install", "--standalone"])
          code.should eq(0)
          out.should contain("Bundled gems are installed into `./bundle`")

          setup = File.join(dir, "bundle", "bundler", "setup.rb")
          File.exists?(setup).should be_true
          body = File.read(setup)
          body.should contain("gems/json_pure-2.6.0/lib")
          body.should contain("gems/thor-1.3.2/lib")
          # `File.open(..., "w")` in the reference is a text-mode write.
          {% if flag?(:windows) %}
            line_feeds = body.scan(/\n/).size
            carriages = body.scan(/\r\n/).size
            carriages.should be > 30
            carriages.should eq(line_feeds)
          {% end %}
        end
      end
    end
  end

  it "renders only the selected groups and refetches the index" do
    with_standalone_bridge do
      with_project({"Gemfile" => standalone_gemfile}) do |dir|
        bundle_path = File.join(dir, "vendor-bundle")
        with_standalone_env(dir, bundle_path) do
          code, out, _err = run_cli(["install", "--standalone=development"])
          code.should eq(0)

          setup = File.join(bundle_path, "bundler", "setup.rb")
          File.exists?(setup).should be_true
          body = File.read(setup)
          body.should contain("gems/thor-1.3.2/lib")
          body.should_not contain("json_pure")
          # `definition.specs_for(groups)` materializes the groups again.
          out.scan(/Fetching source index from/).size.should eq(2)
        end
      end
    end
  end

  it "does not point path at ./bundle with --local" do
    with_standalone_bridge do
      with_project({"Gemfile" => standalone_gemfile}) do |dir|
        with_standalone_env(dir) do
          code, _out, err = run_cli(["install", "--standalone", "--local"])
          code.should eq(7)
          err.should contain("Could not find gem 'json_pure (= 2.6.0)' in locally installed gems.")
          File.exists?(File.join(dir, "bundle")).should be_false
        end
      end
    end
  end

  # `installer/standalone.rb:30-40`: non-GEM sources are rendered too, one line
  # per `require_paths` entry, relative to `<install>/bundler` (`:54-61`).
  it "renders an out-of-project path source relative to the bundler directory" do
    with_standalone_bridge do
      sibling = File.join(Dir.tempdir, "standalone-pgem-#{Process.pid}")
      standalone_path_gem(sibling)
      begin
        with_project({"Gemfile" => standalone_gemfile_with_path(sibling)}) do |dir|
          with_standalone_env(dir) do
            code, _out, _err = run_cli(["install", "--standalone"])
            code.should eq(0)
            setup = File.join(dir, "bundle", "bundler", "setup.rb")
            body = File.read(setup)
            line = body.lines.find(&.includes?("standalone-pgem")).not_nil!
            line.should contain("\#{__dir__}/")
            line.should_not contain(sibling.gsub('\\', "/"))
            # The rendered line must resolve to the path gem's lib directory.
            relative = line.split("\#{__dir__}/").last.split("\")").first
            File.expand_path(relative, File.join(dir, "bundle", "bundler"))
              .gsub('\\', "/").should eq(File.join(sibling, "lib").gsub('\\', "/"))
            standalone_require_works?(setup, dir).should be_true
          end
        end
      ensure
        FileUtils.rm_rf(sibling)
      end
    end
  end

  it "renders a path source whose declared path is absolute and skips bundler" do
    with_standalone_bridge do
      sibling = File.join(Dir.tempdir, "standalone-pgem-abs-#{Process.pid}")
      standalone_path_gem(sibling)
      begin
        with_project({"Gemfile" => standalone_gemfile_with_path(File.join(sibling, "").gsub('\\', "/"))}) do |dir|
          with_standalone_env(dir) do
            code, _out, _err = run_cli(["install", "--standalone"])
            code.should eq(0)
            setup = File.join(dir, "bundle", "bundler", "setup.rb")
            body = File.read(setup)
            body.should contain("standalone-pgem-abs")
            body.should_not contain("bundler-4.0")
            body.should contain("gems/json_pure-2.6.0/lib")
            standalone_require_works?(setup, dir).should be_true
          end
        end
      ensure
        FileUtils.rm_rf(sibling)
      end
    end
  end

  it "skips the installed bundler spec when rendering the load path" do
    with_standalone_bridge do
      with_project({"Gemfile" => standalone_gemfile}) do |dir|
        with_standalone_env(dir) do
          code, _out, _err = run_cli(["install", "--standalone"])
          code.should eq(0)
          body = File.read(File.join(dir, "bundle", "bundler", "setup.rb"))
          body.should_not contain("gems/bundler-")
          body.should contain("gems/json_pure-2.6.0/lib")
        end
      end
    end
  end
end
