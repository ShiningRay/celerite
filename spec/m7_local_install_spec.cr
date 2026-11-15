require "./spec_helper"
require "http/server"
require "../src/celerite/cli/commands"

# M7(5): `install --local` / `--prefer-local` (bundler 4.0.24 oracle).
#   --local       -> only installed gems + vendor/cache (no index, not even file://)
#   --prefer-local-> local versions win over newer index versions
private def local_gem_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

private def local_install_gem(dir : String, gem_path : String) : Nil
  status = Process.run(
    "ruby",
    ["-S", "gem", "install", "--no-document", "--install-dir", dir, gem_path],
    output: IO::Memory.new,
    error: IO::Memory.new,
  )
  status.success?.should be_true
end

private def local_ruby_gem_dir : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.default_dir"], output: output)
  output.to_s
end

private def with_local_gem_home(dir : String, &)
  # GEM_HOME/GEM_PATH isolate the gem set; HOME/USERPROFILE isolate the
  # bundle install path (`<project>/.bundle`), so later specs that assert
  # "missing gems" never see these examples' installs.
  previous_home_env = ENV["HOME"]?
  previous_profile = ENV["USERPROFILE"]?
  previous_home = ENV["GEM_HOME"]?
  previous_path = ENV["GEM_PATH"]?
  project = File.expand_path("../../..", dir)
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["GEM_HOME"] = dir
  ENV["GEM_PATH"] = "#{dir};#{local_ruby_gem_dir}"
  yield
ensure
  {"HOME" => previous_home_env, "USERPROFILE" => previous_profile,
   "GEM_HOME" => previous_home, "GEM_PATH" => previous_path}.each do |name, value|
    if value
      ENV[name] = value
    else
      ENV.delete(name)
    end
  end
end

private def with_local_install_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  yield
ensure
  if previous
    ENV["CELERITE_BRIDGE_SERVER"] = previous
  else
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end
end

private def local_gem_fixture(version : String) : String
  File.expand_path("../fixtures/gem-index/gems/json_pure-#{version}.gem", __DIR__)
end

describe "M7(5) install --local / --prefer-local" do
  it "uses installed versions under --local without touching the http index" do
    hits = Atomic(Int32).new(0)
    server = HTTP::Server.new do |context|
      hits.add(1)
      context.response.status_code = 404
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      remote = "http://127.0.0.1:#{address.port}/"
      with_local_install_bridge do
        with_project({"Gemfile" => "source \"#{remote}\"\n\ngem \"json_pure\"\n"}) do |dir|
          bundle = File.join(dir, ".bundle")
          gem_root = File.join(bundle, "ruby", local_gem_abi)
          Dir.mkdir_p(gem_root)
          local_install_gem(gem_root, local_gem_fixture("2.6.0"))
          with_local_gem_home(gem_root) do
            code, out, err = run_cli(["install", "--local"])
            code.should eq(0)
            File.read(File.join(dir, "Gemfile.lock")).should contain("json_pure (2.6.0)")
            out.should_not contain("Fetching")
            err.should eq("")
          end
        end
      end
      hits.get.should eq(0)
    ensure
      server.close
    end
  end

  it "reports the reference message when a gem is nowhere locally (exit 7)" do
    with_local_install_bridge do
      with_project({"Gemfile" => "source \"http://127.0.0.1:9/\"\n\ngem \"no_such_gem_xyz\"\n"}) do |dir|
        gem_root = File.join(dir, ".bundle", "ruby", local_gem_abi)
        Dir.mkdir_p(gem_root)
        with_local_gem_home(gem_root) do
          code, out, err = run_cli(["install", "--local"])
          code.should eq(7)
          out.should_not contain("Fetching")
          err.chomp.should eq("Could not find gem 'no_such_gem_xyz' in locally installed gems.")
        end
      end
    end
  end

  it "never consults a file:// index under --local (exit 7, oracle #3 revised)" do
    remote = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_local_install_bridge do
      with_project({"Gemfile" => "source \"#{remote}\"\n\ngem \"json_pure\"\n"}) do |dir|
        gem_root = File.join(dir, ".bundle", "ruby", local_gem_abi)
        Dir.mkdir_p(gem_root)
        with_local_gem_home(gem_root) do
          code, out, err = run_cli(["install", "--local"])
          code.should eq(7)
          out.should_not contain("Fetching")
          err.chomp.should eq("Could not find gem 'json_pure' in locally installed gems.")
        end
      end
    end
  end

  it "prefers the installed version under --prefer-local" do
    remote = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_local_install_bridge do
      with_project({"Gemfile" => "source \"#{remote}\"\n\ngem \"json_pure\"\n"}) do |dir|
        bundle = File.join(dir, ".bundle")
        gem_root = File.join(bundle, "ruby", local_gem_abi)
        Dir.mkdir_p(gem_root)
        local_install_gem(gem_root, local_gem_fixture("2.6.0"))
        with_local_gem_home(gem_root) do
          code, _out, _err = run_cli(["install", "--prefer-local"])
          code.should eq(0)
          File.read(File.join(dir, "Gemfile.lock")).should contain("json_pure (2.6.0)")
        end
      end
    end
  end

  it "picks the newest index version without the flag" do
    remote = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_local_install_bridge do
      with_project({"Gemfile" => "source \"#{remote}\"\n\ngem \"json_pure\"\n"}) do |dir|
        bundle = File.join(dir, ".bundle")
        gem_root = File.join(bundle, "ruby", local_gem_abi)
        Dir.mkdir_p(gem_root)
        local_install_gem(gem_root, local_gem_fixture("2.6.0"))
        with_local_gem_home(gem_root) do
          code, _out, _err = run_cli(["install"])
          code.should eq(0)
          File.read(File.join(dir, "Gemfile.lock")).should contain("json_pure (2.8.1)")
        end
      end
    end
  end
end
