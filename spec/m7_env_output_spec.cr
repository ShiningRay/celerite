require "./spec_helper"
require "../src/celerite"

private def env_gemfile
  "source \"https://rubygems.org\"\n"
end

private def with_env_var(name : String, value : String?, &)
  previous = ENV[name]?
  if value
    ENV[name] = value
  else
    ENV.delete(name)
  end
  begin
    yield
  ensure
    if previous
      ENV[name] = previous
    else
      ENV.delete(name)
    end
  end
end

private def with_env_bridge(&)
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

describe "Celerite::CLI env output" do
  it "prints only the profile bundler version" do
    with_env_bridge do
      with_project({"Gemfile" => env_gemfile}) do
        code, out, _err = run_cli(["env"])
        code.should eq(0)
        bundler_line = out.lines.find { |line| line.starts_with?("Bundler ") }.not_nil!
        expected = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        bundler_line.should eq("Bundler       #{expected}")
        bundler_line.should_not contain("compatibility profile")
      end
    end
  end

  it "prints the reference release's baked build metadata" do
    with_env_bridge do
      with_env_var("CELERITE_PROFILE_BUNDLER_VERSION", "4.0.24") do
        with_project({"Gemfile" => env_gemfile}) do
          code, out, _err = run_cli(["env"])
          code.should eq(0)
          # `Bundler::BuildMetadata` is a constant of the release, not this
          # checkout's `git log`/`rev-parse`.
          out.should contain("## Bundler Build Metadata\n\n```\nTimestamp  2026-11-05\nGit SHA    3b396e4\n```")
        end
      end
    end
  end

  it "reports the 2.7.x build metadata for that profile" do
    with_env_bridge do
      with_env_var("CELERITE_PROFILE_BUNDLER_VERSION", "2.7.2") do
        with_project({"Gemfile" => env_gemfile}) do
          code, out, _err = run_cli(["env"])
          code.should eq(0)
          out.should contain("Timestamp  2025-09-09")
          out.should contain("Git SHA    b463ced1459")
        end
      end
    end
  end

  it "joins Gem Path with the platform path separator" do
    with_env_bridge do
      with_env_var("GEM_PATH", "C:/gems-a;C:/gems-b") do
        with_project({"Gemfile" => env_gemfile}) do
          code, out, _err = run_cli(["env"])
          code.should eq(0)
          # `Bundler::Env` uses `Gem.path.join(File::PATH_SEPARATOR)`, and
          # `Gem.path` appends the default dir to a user-set GEM_PATH.
          gem_path_line = out.lines.find { |line| line.starts_with?("  Gem Path    ") }.not_nil!
          gem_path_line.should_not contain(", ")
          gem_path_line.should contain(";")
          gem_path_line.split(";").first(2).should eq(["  Gem Path    C:/gems-a", "C:/gems-b"])
        end
      end
    end
  end

  it "renders the system config directory with forward slashes" do
    with_env_bridge do
      with_project({"Gemfile" => env_gemfile}) do
        code, out, _err = run_cli(["env"])
        code.should eq(0)
        config_line = out.lines.find { |line| line.starts_with?("  Config Dir  ") }.not_nil!
        config_line.should_not contain('\\')
      end
    end
  end

  it "prints the reference placeholder when the lockfile is missing" do
    with_env_bridge do
      with_project({"Gemfile" => env_gemfile}) do
        code, out, _err = run_cli(["env"])
        code.should eq(0)
        out.should contain("<No ")
        out.should contain("Gemfile.lock found>")
        out.should end_with("```\n")
      end
    end
  end

  it "prints a Bundler settings section when BUNDLE_PATH is set" do
    with_env_bridge do
      with_env_var("BUNDLE_PATH", "vendor/bundle") do
        with_project({"Gemfile" => env_gemfile}) do
          code, out, _err = run_cli(["env"])
          code.should eq(0)
          out.should contain("## Bundler settings\n\n```\npath\n")
          out.should contain("Set via BUNDLE_PATH")
        end
      end
    end
  end

  it "prints the OpenSSL block when the bridge process has OpenSSL loaded" do
    with_env_bridge do
      with_env_var("RUBYOPT", "-ropenssl") do
        with_project({"Gemfile" => env_gemfile}) do
          code, out, _err = run_cli(["env"])
          code.should eq(0)
          out.should contain("OpenSSL       ")
          compiled_line = out.lines.find { |line| line.starts_with?("  Compiled    ") }.not_nil!
          compiled_line[14..].strip.should_not be_empty
          cert_line = out.lines.find { |line| line.starts_with?("  Cert File   ") }.not_nil!
          environment = Celerite::Bridge::Client.new.ruby_environment
          environment.openssl_cert_file.not_nil!.should eq(cert_line[14..])
        end
      end
    end
  end

  it "prints the Gemspecs section only when the Gemfile loads a gemspec" do
    gemspec = <<-GEMSPEC
      Gem::Specification.new do |spec|
        spec.name = "foo"
        spec.version = "0.1.0"
        spec.summary = "fixture"
        spec.authors = ["fixture"]
        spec.files = []
      end
      GEMSPEC
    with_env_bridge do
      with_project({
        "Gemfile"     => "source \"https://rubygems.org\"\n\ngemspec name: \"foo\"\n",
        "foo.gemspec" => gemspec,
      }) do
        code, out, _err = run_cli(["env"])
        code.should eq(0)
        out.should contain("## Gemspecs\n\n### foo.gemspec\n\n```ruby\n")
        out.should contain("Gem::Specification.new do |spec|")
        out.should end_with("```\n")
      end
      with_project({"Gemfile" => env_gemfile}) do
        code, out, _err = run_cli(["env"])
        code.should eq(0)
        out.should_not contain("## Gemspecs")
      end
    end
  end
end
