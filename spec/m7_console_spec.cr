require "./spec_helper"

private PATH_SEPARATOR = {{ flag?(:windows) ? ";" : ":" }}

private def with_console_env(name : String, value : String?, &)
  previous = ENV[name]?
  if value.nil?
    ENV.delete(name)
  else
    ENV[name] = value
  end
  yield
ensure
  if previous.nil?
    ENV.delete(name)
  else
    ENV[name] = previous
  end
end

private def write_fake_console(dir : String, name : String, tag : String) : String
  path = File.join(dir, "#{name}.bat")
  # `console` spawns the child with inherited stdio, so in-process specs cannot
  # capture its stdout; the fake writes a marker file instead.
  File.write(path, "@echo #{tag} %* > \"%CELERITE_CONSOLE_MARKER%\"\r\n@exit /b 0\r\n")
  path
end

private def with_console_marker(path : String, &)
  with_console_env("CELERITE_CONSOLE_MARKER", path) do
    yield
  end
end

# The console command spawns a child process, so PATH has to be swapped for
# the duration of the in-process CLI call and restored afterwards.
private def with_fake_console(fake_dir : String, &)
  original = ENV["PATH"]? || ""
  ENV["PATH"] = original.empty? ? fake_dir : "#{fake_dir}#{PATH_SEPARATOR}#{original}"
  begin
    yield
  ensure
    ENV["PATH"] = original
  end
end

private def console_bin : String?
  path = File.expand_path("../bin/celerite.exe", __DIR__)
  File.exists?(path) ? path : nil
end

# The console child inherits stdio, so messages the boot helper writes cannot be
# captured in-process; these helpers run the built binary and capture both
# streams like a user would see them.
private def run_console_cli(project : String, args : Array(String), env : Hash(String, String)) : {Int32, String, String}
  bin = console_bin || pending!("bin/celerite.exe is not built")
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(bin, args, chdir: project, env: env, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

# Path gems used by the console probe project: two gems in different groups
# (only required when Bundler.require names the group) plus a fake console gem
# whose `start` reports which constants exist and exits.
private def probe_gemspec(name : String) : String
  <<-RUBY
  Gem::Specification.new do |s|
    s.name = "#{name}"
    s.version = "0.0.1"
    s.summary = "console probe"
    s.authors = ["probe"]
    s.files = ["lib/#{name}.rb"]
    s.require_paths = ["lib"]
  end
  RUBY
end

private def probe_console_lib(constant : String, tag : String) : String
  <<-RUBY
  module #{constant}
    def self.start(*args)
      line = "#{tag} default=\#{defined?(ProbeDefault) ? 1 : 0} foo=\#{defined?(ProbeFoo) ? 1 : 0} argv=\#{ARGV.inspect}"
      marker = ENV["CELERITE_CONSOLE_MARKER"].to_s
      if marker.empty?
        puts line
      else
        File.write(marker, line + "\\n")
      end
      code = ENV["CELERITE_CONSOLE_EXIT"].to_s
      exit(code.empty? ? 0 : code.to_i)
    end
  end
  RUBY
end

# Lockfile measured from the reference (`bundle _4.0.24_ install` on
# 2026-11-19) for the path-only probe project; present so `bundler/setup`
# never has to resolve (or rewrite) anything while the probe runs.
private CONSOLE_PROBE_LOCK = <<-LOCK
PATH
  remote: probe_default
  specs:
    probe_default (0.0.1)

PATH
  remote: probe_foo
  specs:
    probe_foo (0.0.1)

PATH
  remote: pry
  specs:
    pry (0.0.1)

GEM
  specs:

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  probe_default!
  probe_foo!
  pry!

BUNDLED WITH
  4.0.24
LOCK

# Dependency-free bundle with a matching lockfile: `bundler/setup` then has
# nothing to resolve, so the boot helper reaches its console lookups without
# touching the network or rewriting Gemfile.lock.
private EMPTY_BUNDLE_FILES = {
  "Gemfile"      => "source \"https://rubygems.org\"\n",
  "Gemfile.lock" => <<-LOCK,
    GEM
      remote: https://rubygems.org/
      specs:

    PLATFORMS
      x64-mingw-ucrt

    DEPENDENCIES

    BUNDLED WITH
      4.0.24
    LOCK
}

private def console_probe_files(console_name = "pry", console_file = "pry", console_constant = "Pry", console_tag = "PROBE_START") : Hash(String, String)
  {
    "Gemfile" => <<-GEMFILE,
      gem "probe_default", :path => "./probe_default"
      gem "probe_foo", :path => "./probe_foo", :group => :foo
      gem "#{console_file}", :path => "./#{console_file}"
      GEMFILE
    "Gemfile.lock"                            => CONSOLE_PROBE_LOCK,
    ".bundle/config"                          => "---\nBUNDLE_CONSOLE: \"#{console_name}\"\n",
    "probe_default/probe_default.gemspec"     => probe_gemspec("probe_default"),
    "probe_default/lib/probe_default.rb"      => "module ProbeDefault\nend\n",
    "probe_foo/probe_foo.gemspec"             => probe_gemspec("probe_foo"),
    "probe_foo/lib/probe_foo.rb"              => "module ProbeFoo\nend\n",
    "#{console_file}/#{console_file}.gemspec" => probe_gemspec(console_file),
    "#{console_file}/lib/#{console_file}.rb"  => probe_console_lib(console_constant, console_tag),
  }
end

describe "M7(3) console" do
  it "starts the configured console with the bundle's group required" do
    with_project(console_probe_files) do |dir|
      marker = File.join(dir, "console-marker.txt")
      with_console_marker(marker) do
        code, _out, err = run_cli(["console", "foo"])
        code.should eq(0)
        File.read(marker).chomp.should eq("PROBE_START default=1 foo=1 argv=[]")
        err.should eq("")
      end
    end
  end

  it "requires only the default group when no GROUP is given" do
    with_project(console_probe_files) do |dir|
      marker = File.join(dir, "console-marker.txt")
      with_console_marker(marker) do
        code, _out, _err = run_cli(["console"])
        code.should eq(0)
        File.read(marker).chomp.should eq("PROBE_START default=1 foo=0 argv=[]")
      end
    end
  end

  it "prefers the console named by BUNDLE_CONSOLE over irb" do
    with_project(console_probe_files("ripl", "ripl", "Ripl", "RIPL_START")) do |dir|
      markrid = File.join(dir, "console-marker.txt")
      with_console_marker(markrid) do
        code, _out, _err = run_cli(["console"])
        code.should eq(0)
        File.read(markrid).chomp.should eq("RIPL_START default=1 foo=0 argv=[]")
      end
    end
  end

  it "starts the bundle's console gem instead of a PATH executable" do
    with_project(console_probe_files) do |dir|
      fake = File.join(dir, "fakebin")
      Dir.mkdir_p(fake)
      write_fake_console(fake, "pry", "FAKE_PRY")
      marker = File.join(dir, "console-marker.txt")
      with_console_marker(marker) do
        with_fake_console(fake) do
          code, _out, _err = run_cli(["console"])
          code.should eq(0)
          # The PATH wrapper is no longer executed: the bundle's gem boots.
          File.read(marker).chomp.should eq("PROBE_START default=1 foo=0 argv=[]")
        end
      end
    end
  end

  it "passes the console's exit code through" do
    with_project(console_probe_files) do |dir|
      marker = File.join(dir, "console-marker.txt")
      with_console_marker(marker) do
        with_console_env("CELERITE_CONSOLE_EXIT", "3") do
          code, _out, _err = run_cli(["console"])
          code.should eq(3)
          File.read(marker).chomp.should eq("PROBE_START default=1 foo=0 argv=[]")
        end
      end
    end
  end

  it "falls back to irb when the configured console is missing" do
    with_project(EMPTY_BUNDLE_FILES) do |dir|
      ruby = Process.find_executable("ruby") || "ruby"
      # Reference (2.7.2 measured 2026-11-19): the fallback line, then irb
      # cannot be loaded because irb is a bundled gem outside the bundle.
      code, _out, err = run_console_cli(dir, ["console"], {
        "BUNDLE_CONSOLE" => "pry",
        "CELERITE_RUBY"  => ruby,
        "HOME"           => dir,
        "USERPROFILE"    => dir,
      })
      code.should eq(1)
      err.lines.first?.try(&.chomp).should eq("Couldn't load console pry, falling back to irb")
      err.should contain("irb is not available")
    end
  end

  it "reports irb is not available when no console can be found" do
    with_project(EMPTY_BUNDLE_FILES) do |dir|
      ruby = Process.find_executable("ruby") || "ruby"
      code, _out, err = run_console_cli(dir, ["console"], {
        "BUNDLE_CONSOLE" => "",
        "CELERITE_RUBY"  => ruby,
        "HOME"           => dir,
        "USERPROFILE"    => dir,
      })
      code.should eq(1)
      err.lines.last?.try(&.chomp).should eq("irb is not available")
    end
  end

  it "rejects more than one positional group like Thor (exit 15)" do
    with_project(EMPTY_BUNDLE_FILES) do
      code, _out, err = run_cli(["console", "a", "b"])
      code.should eq(15)
      err.should contain("ERROR: \"bundle console\" was called with arguments [\"a\", \"b\"]")
      err.should contain("Usage: \"bundle console [GROUP]\"")
    end
  end
end
