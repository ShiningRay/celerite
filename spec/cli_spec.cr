require "./spec_helper"
require "../src/celerite"

describe Celerite::CLI do
  it "prints its version" do
    code, out, err = run_cli(["version"])
    code.should eq(0)
    out.should eq("#{Celerite::VERSION}\n")
    err.should be_empty
  end

  it "prints help without arguments" do
    code, out, err = run_cli([] of String)
    code.should eq(0)
    out.should contain("Usage:")
    err.should be_empty
  end

  it "runs install (M3) through the full path" do
    # install without a Gemfile reports the missing Gemfile like the reference
    with_project({} of String => String) do
      code, out, err = run_cli(["install"])
      code.should eq(10)
      err.should contain("Could not locate Gemfile")
    end
  end

  it "rejects unknown commands like the reference" do
    code, out, err = run_cli(["bogus-cmd"])
    code.should eq(15)
    err.should contain("Could not find command \"bogus-cmd\".")
    out.should be_empty
  end

  describe "check" do
    it "reports missing locked gems with the reference format" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => FIXTURE_LOCKFILE,
      }) do
        code, out, err = run_cli(["check"])
        code.should eq(1)
        out.should be_empty
        err.should eq("The following gems are missing
" +
                      " * json_pure (2.8.1)
" +
                      "Install missing gems with `bundle install`
")
      end
    end

    it "dry-run suppresses the resolving line" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => FIXTURE_LOCKFILE,
      }) do
        code, out, err = run_cli(["check", "--dry-run"])
        code.should eq(1)
        out.should be_empty
        err.should contain("The following gems are missing")
      end
    end

    it "fails for a dependency without a locked spec" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"nosuchgem\"\n",
        "Gemfile.lock" => <<-LOCK
        GEM
          remote: https://rubygems.org/
          specs:

        PLATFORMS
          ruby

        DEPENDENCIES
          nosuchgem

        BUNDLED WITH
          4.0.24
        LOCK
      }) do
        code, out, err = run_cli(["check"])
        code.should eq(1)
        err.should contain("Bundler can't satisfy your Gemfile's dependencies.")
      end
    end

    it "reports frozen mode without a lockfile" do
      with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do
        ENV["BUNDLE_FROZEN"] = "true"
        begin
          code, out, err = run_cli(["check"])
          code.should eq(16)
          err.should contain("Frozen mode is set, but there's no lockfile")
        ensure
          ENV.delete("BUNDLE_FROZEN")
        end
      end
    end

    it "does not write the lockfile (read-only path)" do
      lockfile = FIXTURE_LOCKFILE
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => lockfile,
      }) do |dir|
        run_cli(["check"])
        File.read(File.join(dir, "Gemfile.lock")).should eq(lockfile)
      end
    end
  end

  describe "list/show/info" do
    it "lists missing gems with full names" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => FIXTURE_LOCKFILE,
      }) do
        code, out, err = run_cli(["list"])
        code.should eq(1)
        out.should be_empty
        err.should eq("Could not find json_pure-2.8.1 in locally installed gems
" +
                      "Install missing gems with `bundle install`.
")
      end
    end

    it "reports an empty bundle" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n",
        "Gemfile.lock" => EMPTY_LOCKFILE,
      }) do
        code, out, err = run_cli(["list"])
        code.should eq(0)
        out.should eq("No gems in the Gemfile\n")
        err.should be_empty
      end
    end

    it "show without arguments prints the bundle header then fails on missing gems" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => FIXTURE_LOCKFILE,
      }) do
        code, out, err = run_cli(["show"])
        code.should eq(7)
        out.should eq("Gems included by the bundle:\n")
        err.should contain("Could not find json_pure-2.8.1 in locally installed gems")
      end
    end

    it "show <gem> and info <gem> fail for missing gems" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => FIXTURE_LOCKFILE,
      }) do
        code, out, err = run_cli(["show", "json_pure"])
        code.should eq(7)
        out.should be_empty
        err.should contain("Could not find json_pure-2.8.1 in locally installed gems")

        code, out, err = run_cli(["info", "json_pure"])
        code.should eq(7)
      end
    end
  end

  describe "platform" do
    it "prints local and locked platforms with the reference format" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => FIXTURE_LOCKFILE,
      }) do
        code, out, err = run_cli(["platform"])
        code.should eq(0)
        err.should be_empty
        out.should eq <<-TEXT
        Your platform is: #{Celerite::Gem::Platform.local}

        Your app has gems that work on these platforms:
        * #{Celerite::Gem::Platform.local}

        Your Gemfile does not specify a Ruby version requirement.

        TEXT
      end
    end

    it "reports the locked ruby version with --ruby" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n",
        "Gemfile.lock" => RUBY_VERSION_LOCKFILE,
      }) do
        code, out, err = run_cli(["platform", "--ruby"])
        code.should eq(0)
        out.should eq("ruby 3.2.0\n")
      end
    end
  end

  describe "lock" do
    it "manages platforms natively (remove then re-add is a no-op change)" do
      local_platform = Celerite::Gem::Platform.local.to_s
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\"\n",
        "Gemfile.lock" => FIXTURE_LOCKFILE,
      }) do |dir|
        ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
        begin
          # remove the local platform then re-add it: the lockfile round-trips
          code, out, err = run_cli(["lock", "--remove-platform", local_platform])
          code.should eq(0)
          lock_after_remove = File.read(File.join(dir, "Gemfile.lock"))
          lock_after_remove.should_not contain(local_platform)

          code, out, err = run_cli(["lock", "--add-platform", local_platform])
          code.should eq(0)
          File.read(File.join(dir, "Gemfile.lock")).should eq(FIXTURE_LOCKFILE + "\n")
        ensure
          ENV.delete("CELERITE_BRIDGE_SERVER")
        end
      end
    end
  end

  describe "config get" do
    it "reports unset values" do
      with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do
        # Pinned reference behavior: `config get` for an unset key exits 1.
        code, out, err = run_cli(["config", "get", "retry"])
        code.should eq(1)
        out.should eq <<-TEXT
        Settings for `retry` in order of priority. The top value will be used
        You have not configured a value for `retry`

        TEXT
      end
    end

    it "reports env values" do
      with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do
        ENV["BUNDLE_JOBS"] = "4"
        begin
          code, out, err = run_cli(["config", "get", "jobs"])
          code.should eq(0)
          out.should contain("Set via BUNDLE_JOBS: 4")
        ensure
          ENV.delete("BUNDLE_JOBS")
        end
      end
    end
  end

  describe "negative paths" do
    it "reports a missing Gemfile with the reference code" do
      with_project({} of String => String) do
        code, out, err = run_cli(["check"])
        code.should eq(10)
        err.should contain("Could not locate Gemfile")
      end
    end

    it "reports malformed lockfiles as unreadable" do
      with_project({
        "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
        "Gemfile.lock" => "GEM\n  remote: https://rubygems.org/\n  specs:\n    bad (x.y.z)\n",
      }) do
        code, out, err = run_cli(["check"])
        code.should eq(20) # Bundler::LockfileError status code
        err.should contain("unreadable")
      end
    end
  end
end

FIXTURE_LOCKFILE = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:
    json_pure (2.8.1)

PLATFORMS
  #{Celerite::Gem::Platform.local}

DEPENDENCIES
  json_pure (>= 2.0)

BUNDLED WITH
  4.0.24
LOCK

EMPTY_LOCKFILE = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:

PLATFORMS
  ruby

DEPENDENCIES

BUNDLED WITH
  4.0.24
LOCK

RUBY_VERSION_LOCKFILE = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:

PLATFORMS
  ruby

DEPENDENCIES

RUBY VERSION
   ruby 3.2.0p0

BUNDLED WITH
  4.0.24
LOCK
