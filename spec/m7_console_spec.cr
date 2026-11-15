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

describe "M7(3) console" do
  it "execs irb from PATH with the bundle environment" do
    with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do |dir|
      fake = File.join(dir, "fakebin")
      Dir.mkdir_p(fake)
      write_fake_console(fake, "irb", "FAKE_IRB")
      marker = File.join(dir, "console-marker.txt")
      with_console_marker(marker) do
        with_fake_console(fake) do
          code, _out, err = run_cli(["console"])
          code.should eq(0)
          File.read(marker).should contain("FAKE_IRB")
          err.should eq("")
        end
      end
    end
  end

  it "prefers the console named by BUNDLE_CONSOLE over irb" do
    with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do |dir|
      fake = File.join(dir, "fakebin")
      Dir.mkdir_p(fake)
      write_fake_console(fake, "irb", "FAKE_IRB")
      write_fake_console(fake, "fakecons", "FAKE_CONS")
      marker = File.join(dir, "console-marker.txt")
      with_console_env("BUNDLE_CONSOLE", "fakecons") do
        with_console_marker(marker) do
          with_fake_console(fake) do
            code, _out, _err = run_cli(["console"])
            code.should eq(0)
            File.read(marker).should contain("FAKE_CONS")
          end
        end
      end
    end
  end

  it "falls back to irb when the configured console is missing" do
    with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do |dir|
      fake = File.join(dir, "fakebin")
      Dir.mkdir_p(fake)
      ruby = Process.find_executable("ruby") || "ruby"
      with_console_env("BUNDLE_CONSOLE", "pry") do
        with_console_env("CELERITE_RUBY", ruby) do
          with_console_env("PATH", fake) do
            code, _out, err = run_cli(["console"])
            code.should eq(1)
            err.should contain("Couldn't load console pry, falling back to irb")
            err.should contain("irb is not available")
          end
        end
      end
    end
  end

  it "reports irb is not available when no console can be found" do
    with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do |dir|
      fake = File.join(dir, "fakebin")
      Dir.mkdir_p(fake)
      ruby = Process.find_executable("ruby") || "ruby"
      with_console_env("BUNDLE_CONSOLE", nil) do
        with_console_env("CELERITE_RUBY", ruby) do
          with_console_env("PATH", fake) do
            code, _out, err = run_cli(["console"])
            code.should eq(1)
            err.chomp.should eq("irb is not available")
          end
        end
      end
    end
  end

  it "rejects more than one positional group like Thor (exit 15)" do
    with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do
      code, _out, err = run_cli(["console", "a", "b"])
      code.should eq(15)
      err.should contain("ERROR: \"bundle console\" was called with arguments [\"a\", \"b\"]")
      err.should contain("Usage: \"bundle console [GROUP]\"")
    end
  end
end
