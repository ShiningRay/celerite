require "./spec_helper"
require "../src/celerite"

# M7(4) `build.<gem>`: `.bundle/config`/env -> `Installer#config_build_args`
# (installer.cr:40-46) -> `Bridge::Client#build_extension` (client.cr:208-212)
# -> `assets/bridge/server.rb:251-252` `Gem::Ext::Builder.new(spec, build_args)`
# -> `ruby extconf.rb <args>`.
#
# The fixture gem's `ext/extconf.rb` records `ARGV.inspect` into
# `$CELERITE_BUILD_ARGS_MARKER` and writes a no-op Makefile, so the build needs
# no compiler. Fixture: `spec/fixtures/build-args/gems/build-args-demo-1.0.0.gem`
# (built offline with `ruby -S gem build`, mirroring `spec/fixtures/locked-deps`).
BUILD_ARGS_GEM_NAME = "build-args-demo"

private def with_build_args_bridge(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
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

private def with_build_args_env(vars : Hash(String, String?), &)
  saved = {} of String => String?
  vars.each_key { |key| saved[key] = ENV[key]? }
  begin
    vars.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
    yield
  ensure
    saved.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def build_args_make_dir : String
  # `Gem::Ext::Builder` shells out to `make`; the interpreter's bundled MSYS
  # make is not on the default PATH of this environment.
  ruby_bin = `ruby -e "print RbConfig::CONFIG['bindir']"`.strip
  File.join(File.dirname(ruby_bin), "msys64", "usr", "bin")
end

private def build_args_env(extra : Hash(String, String?), marker : String) : Hash(String, String?)
  vars = {} of String => String?
  extra.each { |key, value| vars[key] = value }
  vars["CELERITE_BUILD_ARGS_MARKER"] = marker
  path = ENV["PATH"]? || ""
  vars["PATH"] = "#{build_args_make_dir};#{path}"
  vars
end

private def build_args_remote : String
  file_source_url(File.expand_path("fixtures/build-args", __DIR__))
end

private def build_args_project : Hash(String, String)
  remote = build_args_remote
  {
    "Gemfile"      => "source \"#{remote}\"\n\ngem \"#{BUILD_ARGS_GEM_NAME}\"\n",
    "Gemfile.lock" => <<-LOCK,
      GEM
        remote: #{remote}/
        specs:
          #{BUILD_ARGS_GEM_NAME} (1.0.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        #{BUILD_ARGS_GEM_NAME}

      BUNDLED WITH
         4.0.24
      LOCK
    ".bundle/config" => "BUNDLE_PATH: \"vendor/bundle\"\n",
  }
end

describe "M7(4) build.<gem> arguments" do
  it "passes configured build arguments through the bridge to extconf" do
    with_project(build_args_project) do |dir|
      marker = File.join(dir, "build_args_marker.txt")
      key = Celerite::Config.key_for("build.#{BUILD_ARGS_GEM_NAME}")
      with_build_args_bridge do
        with_build_args_env(build_args_env({key => "--with-marker-flag --another=1"}, marker)) do
          code, _, err = run_cli(["install"])
          code.should eq(0)
          File.exists?(marker).should be_true
          recorded = File.read(marker)
          recorded.should contain("--with-marker-flag")
          recorded.should contain("--another=1")
        end
      end
    end
  end

  it "leaves extconf ARGV empty when build arguments are not configured" do
    with_project(build_args_project) do |dir|
      marker = File.join(dir, "build_args_marker.txt")
      with_build_args_bridge do
        with_build_args_env(build_args_env({} of String => String?, marker)) do
          code, _, err = run_cli(["install"])
          code.should eq(0)
          File.exists?(marker).should be_true
          File.read(marker).should eq("[]")
        end
      end
    end
  end
end

# M7(4) policy: explicitly configured settings that the reference does not
# implement (`ssl_client_key`) or that Celerite does not implement yet
# (`legacy_index`/`full_index`) fail fast with a fixed message. `bundler`
# 4.0.24 has zero source hits for all three keys (verified by grep), so the
# fast-fail is the intended policy rather than a compatibility gap.
private def unsupported_config(values : Hash(String, Celerite::Config::Value)) : Celerite::Config
  dir = File.tempname("celerite-unsupported")
  Dir.mkdir_p(dir)
  Celerite::Config.new(dir, values)
end

private def config_values(pairs : Hash(String, String)) : Hash(String, Celerite::Config::Value)
  values = {} of String => Celerite::Config::Value
  pairs.each { |name, value| values[Celerite::Config.key_for(name)] = value }
  values
end

describe "M7(4) unsupported settings" do
  it "returns the exact fast-fail message for each unsupported key" do
    {"ssl_client_key" => "client.key", "legacy_index" => "true", "full_index" => "true"}.each do |key, value|
      config = unsupported_config(config_values({key => value}))
      Celerite::Commands.unsupported_setting_error(config, IO::Memory.new)
        .should eq("not supported by Celerite: #{key}")
    end
  end

  it "returns nil for proxy keys and supported TLS settings" do
    config = unsupported_config(config_values({
      "proxy"        => "http://127.0.0.1:3128",
      "http_proxy"   => "http://127.0.0.1:3128",
      "ssl_ca_cert"  => "ca.pem",
      "legacy_index" => "false",
    }))
    Celerite::Commands.unsupported_setting_error(config, IO::Memory.new).should be_nil
  end

  it "fails install with exit 1 and the documented message" do
    with_project({"Gemfile" => "source \"#{file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))}\"\n"}) do |dir|
      key = Celerite::Config.key_for("ssl_client_key")
      with_build_args_env({key => "client.key"}) do
        code, _, err = run_cli(["install"])
        code.should eq(1)
        err.should contain("not supported by Celerite: ssl_client_key")
      end
    end
  end
end
