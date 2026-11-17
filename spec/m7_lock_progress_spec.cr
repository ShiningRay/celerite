require "./spec_helper"

# `bundle lock` resolves nothing when the lockfile already matches the Gemfile,
# so the reference prints only its "Writing lockfile" line (`cli/lock.rb`), and
# `lock --print` silences the UI entirely before printing the lock body. The
# forcing flags (`--add-checksums`, `--normalize-platforms`) do re-resolve but
# still omit the "Resolving dependencies..." line. `check` reaches the
# remembered-flag path for `--path` only, and `show --paths` prints the running
# Bundler's own gem directory first.
private def with_lock_progress_env(project : String, &)
  gem_home = File.join(project, "gemhome")
  Dir.mkdir_p(gem_home)
  names = ["HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH", "BUNDLE_USER_CONFIG", "BUNDLE_USER_CACHE", "BUNDLE_USER_PLUGIN", "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION", "CELERITE_REFERENCE_BUNDLER_LIB"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = gem_home
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["BUNDLE_USER_CONFIG"] = File.join(project, "home-config")
  ENV["BUNDLE_USER_CACHE"] = File.join(project, "home-cache")
  ENV["BUNDLE_USER_PLUGIN"] = File.join(project, "home-plugin")
  # `with_project` chdirs into the temporary project, so the bridge script has
  # to be spelled out.
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
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

private def lock_progress_project : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  {
    "Gemfile" => "source \"file:///#{index.gsub('\\', "/")}/\"\n\ngem \"json_pure\", \"2.6.0\"\n\ngroup :development do\n  gem \"thor\", \"1.3.2\"\nend\n",
  }
end

private def lock_progress_installed : Nil
  code, out, err = run_cli(["install"])
  code.should eq(0)
  out.should contain("Bundle complete!")
  err.should eq("")
end

describe "bundle lock progress and check --path" do
  it "prints only the lockfile line when nothing needs unlocking" do
    with_project(lock_progress_project) do |dir|
      with_lock_progress_env(dir) do
        lock_progress_installed

        code, out, err = run_cli(["lock"])
        code.should eq(0)
        err.should eq("")
        out.should contain("Writing lockfile to")
        # The reference resolves nothing here (measured on 4.0.24 and 2.7.2).
        out.should_not contain("Fetching source index")
        out.should_not contain("Resolving dependencies...")
        out.lines.size.should eq(1)
      end
    end
  end

  it "silences the resolution for lock --print" do
    with_project(lock_progress_project) do |dir|
      with_lock_progress_env(dir) do
        lock_progress_installed

        code, out, err = run_cli(["lock", "--print"])
        code.should eq(0)
        err.should eq("")
        out.should start_with("GEM\n")
        out.should contain("BUNDLED WITH")
        out.should_not contain("Fetching source index")
        out.should_not contain("Resolving dependencies...")
        out.should_not contain("Writing lockfile to")
      end
    end
  end

  it "keeps the index fetch but drops the resolving line for --add-checksums" do
    with_project(lock_progress_project) do |dir|
      with_lock_progress_env(dir) do
        lock_progress_installed

        code, out, err = run_cli(["lock", "--add-checksums"])
        code.should eq(0)
        err.should eq("")
        out.should contain("Fetching source index from")
        out.should contain("Writing lockfile to")
        out.should_not contain("Resolving dependencies...")
      end
    end
  end

  it "reports the removed --path for check" do
    with_project(lock_progress_project) do |dir|
      with_lock_progress_env(dir) do
        lock_progress_installed

        code, out, err = run_cli(["check", "--path", "vendor/bundle"])
        code.should eq(15)
        out.should eq("")
        expected = Celerite::Commands.word_wrap(Celerite::Commands.removed_flag_message(
          Celerite::Commands::RemovedFlag.new("--path", "path", "'vendor/bundle'")), 80)
        err.should eq("#{expected}\n")
      end
    end
  end

  it "suggests --no-color for check --no-prune like Thor" do
    with_project(lock_progress_project) do |dir|
      with_lock_progress_env(dir) do
        lock_progress_installed

        code, out, err = run_cli(["check", "--no-prune"])
        code.should eq(15)
        out.should eq("")
        err.should contain(%(Unknown switches "--no-prune"))
        err.should contain(%(Did you mean?  "--no-color"))
        err.should_not contain("--no-deployment")
      end
    end
  end

  it "prints the running bundler directory first for show --paths" do
    with_project(lock_progress_project) do |dir|
      with_lock_progress_env(dir) do
        lock_progress_installed

        code, out, err = run_cli(["show", "--paths"])
        code.should eq(0)
        err.should eq("")
        lines = out.lines
        # bundler itself, json_pure and thor.
        lines.size.should eq(3)
        lines.first.ends_with?("gems/bundler-4.0.24").should be_true
        lines[1].should contain("json_pure-2.6.0")
        lines[2].should contain("thor-1.3.2")
      end
    end
  end
end
