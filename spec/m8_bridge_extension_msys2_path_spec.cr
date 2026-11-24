require "./spec_helper"
require "../src/celerite"

# task-247: `bundle install` of a gem with a native extension succeeds even when
# the caller's PATH contains no `make`, because RubyGems fires the
# `Gem.pre_install` hook registered by RubyInstaller
# (`rubygems/defaults/operating_system.rb:33-39`) from
# `Gem::Installer#install` (`rubygems/installer.rb:271`). That hook prepends the
# RubyInstaller MSYS2/MINGW bin directories to PATH
# (`ruby_installer/runtime/msys2_installation.rb:156-163,237-253`), and `make`
# lives in one of them. The bridge calls `Gem::Ext::Builder` directly
# (`assets/bridge/server.rb`, `op_build_extension`), which never runs the hook,
# so it must replay the hook before building.
#
# Both examples construct PATH explicitly from `RbConfig::TOPDIR` and the system
# root; they never read the host's PATH for the scenario itself. They are
# skipped on a Ruby build without the RubyInstaller layout (non-Windows, or a
# plain ruby-build install), where the hook does not exist.
private BRIDGE_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)

private def ruby_topdir : String?
  output = IO::Memory.new
  status = Process.run("ruby", ["-rrbconfig", "-e", "print RbConfig::TOPDIR"],
    output: output, error: Process::Redirect::Close)
  status.success? ? output.to_s.strip : nil
rescue
  nil
end

# Ruby's own bin directory plus the Windows system directories: every MSYS2 or
# MINGW directory is absent, so `make` is not resolvable.
private def controlled_path(ruby_bin : String) : String
  system_root = ENV["SystemRoot"]? || "C:\\Windows"
  "#{ruby_bin};#{system_root}\\system32;#{system_root}"
end

private def make_visible?(path : String) : Bool
  Process.run("where", ["make"], env: {"PATH" => path}).success?
rescue
  true
end

private def with_env(values : Hash(String, String?), &) : Nil
  saved = {} of String => String
  values.each_key do |key|
    if value = ENV[key]?
      saved[key] = value
    end
  end
  begin
    values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    values.each_key do |key|
      ENV.delete(key)
    end
    saved.each { |key, value| ENV[key] = value }
  end
end

describe "M8 native extension build PATH (task-247)" do
  it "builds racc 1.8.1 with a controlled PATH that has no make" do
    pending! "ruby not available" unless ruby_available?
    topdir = ruby_topdir
    pending! "RubyInstaller layout not found" if topdir.nil? || !File.directory?(File.join(topdir, "msys64"))
    path = controlled_path(File.join(topdir, "bin"))
    make_visible?(path).should be_false

    index_url = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_project({"Gemfile" => %(source "#{index_url}"\n\ngem "racc"\n)}) do |project|
      with_env({
        "PATH"                   => path,
        "HOME"                   => project,
        "USERPROFILE"            => project,
        "BUNDLE_PATH"            => File.join(project, "vendor", "bundle"),
        "CELERITE_BRIDGE_SERVER" => BRIDGE_SERVER_PATH,
        "GEM_HOME"               => nil,
        "GEM_PATH"               => nil,
        "RUBYOPT"                => nil,
        "BUNDLE_GEMFILE"         => nil,
      }) do
        code, output, errors = run_cli(["install"])
        code.should eq(0), "install exited #{code}\nstdout:\n#{output}\nstderr:\n#{errors}"
        built = Dir.glob(File.join(project, "vendor", "bundle", "**", "*.so").gsub('\\', "/"))
        built.should_not be_empty
      end
    end
  end

  it "leaves PATH untouched for a bridge op that builds no extension" do
    pending! "ruby not available" unless ruby_available?
    topdir = ruby_topdir
    pending! "RubyInstaller layout not found" if topdir.nil? || !File.directory?(File.join(topdir, "msys64"))
    path = controlled_path(File.join(topdir, "bin"))

    dir = File.tempname("celerite-path-probe", "dir")
    Dir.mkdir_p(dir)
    begin
      report = File.join(dir, "path_unchanged.txt")
      wrapper = File.join(dir, "path_probe.rb")
      # The wrapper loads the real server, which answers requests until EOF, then
      # reports whether the bridge process's own PATH changed.
      File.write(wrapper, <<-'RUBY')
      before = ENV["PATH"]
      load ENV.fetch("CELERITE_SERVER_UNDER_TEST")
      File.write(ENV.fetch("CELERITE_PATH_REPORT"), (ENV["PATH"] == before).to_s)
      RUBY
      requests = [
        %({"proto":2,"id":1,"op":"ping","payload":{}}),
        %({"proto":2,"id":2,"op":"read_gem_spec","payload":{"path":"#{File.join(File.expand_path("../fixtures/gem-index", __DIR__), "gems", "racc-1.8.1.gem").gsub("\\", "\\\\")}"}}),
      ]
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run("ruby", [wrapper],
        input: IO::Memory.new(requests.join('\n') + "\n"),
        output: output,
        error: error,
        env: {
          "PATH"                       => path,
          "CELERITE_SERVER_UNDER_TEST" => BRIDGE_SERVER_PATH,
          "CELERITE_PATH_REPORT"       => report,
        })
      status.success?.should be_true
      File.read(report).should eq("true"), "PATH changed: #{output.to_s}\n#{error.to_s}"
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
