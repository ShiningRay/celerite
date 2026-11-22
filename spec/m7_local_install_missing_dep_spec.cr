require "./spec_helper"

# M7 (task-120): `install --local` with a lockfile that does not cover a
# Gemfile dependency.
#
# The reference turns the sources local but still resolves (`definition.rb`:
# `resolve` at :342-366, `setup_domain!` at :186-203). A Gemfile dependency the
# lockfile does not list counts as an unresolved change
# (`converge_dependencies`, :1051-1109), so the local-only source is asked for
# the new name and reports `Could not find gem '<name>' in locally installed
# gems.` (resolver.rb:334-361) with exit 7, leaving the lockfile untouched.
#
# Reusing the locked specs instead silently dropped the dependency and rewrote
# DEPENDENCIES with an entry its GEM specs never provided.
private def missing_dep_local_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

private def missing_dep_install_gem(dir : String, gem_path : String) : Nil
  status = Process.run(
    "ruby",
    ["-S", "gem", "install", "--no-document", "--install-dir", dir, gem_path],
    output: IO::Memory.new,
    error: IO::Memory.new,
  )
  status.success?.should be_true
end

private def missing_dep_ruby_gem_dir : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.default_dir"], output: output)
  output.to_s
end

private def with_missing_dep_gem_home(dir : String, &)
  previous_home_env = ENV["HOME"]?
  previous_profile = ENV["USERPROFILE"]?
  previous_home = ENV["GEM_HOME"]?
  previous_path = ENV["GEM_PATH"]?
  project = File.expand_path("../../..", dir)
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["GEM_HOME"] = dir
  ENV["GEM_PATH"] = "#{dir};#{missing_dep_ruby_gem_dir}"
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

private def with_missing_dep_bridge(&)
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

private def missing_dep_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

describe "M7 (task-120) install --local with an uncovered Gemfile dependency" do
  it "reports the added gem and leaves the lockfile untouched (exit 7)" do
    with_missing_dep_bridge do
      with_project({
        "Gemfile" => "source \"#{missing_dep_index_url}\"\n\ngem \"json_pure\"\n",
      }) do |dir|
        gem_root = File.join(dir, ".bundle", "ruby", missing_dep_local_abi)
        Dir.mkdir_p(gem_root)
        with_missing_dep_gem_home(gem_root) do
          # A real lockfile plus the installed gem: the state a user reaches
          # after one successful `bundle install`.
          code, _, err = run_cli(["install", "--quiet"])
          code.should eq(0)
          err.should eq("")

          lock_path = File.join(dir, "Gemfile.lock")
          File.read(lock_path).should contain("json_pure (2.8.1)")
          locked = File.read(lock_path)

          # The user adds a dependency that is neither locked nor installed.
          File.write(File.join(dir, "Gemfile"),
            "source \"#{missing_dep_index_url}\"\n\ngem \"json_pure\"\ngem \"thor\"\n")

          code, out, err = run_cli(["install", "--local"])
          code.should eq(7)
          out.should eq("")
          err.chomp.should eq("Could not find gem 'thor' in locally installed gems.")
          # The failure must not leave a half-written lock behind: DEPENDENCIES
          # listing `thor` while GEM/specs only carries json_pure is the broken
          # state this task removes.
          File.read(lock_path).should eq(locked)
          File.read(lock_path).should_not contain("thor")
        end
      end
    end
  end

  it "still reuses the lockfile when every dependency is locally satisfied (exit 0)" do
    with_missing_dep_bridge do
      with_project({
        "Gemfile" => "source \"#{missing_dep_index_url}\"\n\ngem \"json_pure\"\n",
      }) do |dir|
        gem_root = File.join(dir, ".bundle", "ruby", missing_dep_local_abi)
        Dir.mkdir_p(gem_root)
        with_missing_dep_gem_home(gem_root) do
          code, _, _ = run_cli(["install", "--quiet"])
          code.should eq(0)
          locked = File.read(File.join(dir, "Gemfile.lock"))

          code, out, err = run_cli(["install", "--local"])
          code.should eq(0)
          err.should eq("")
          out.should contain("Bundle complete!")
          out.should_not contain("Fetching")
          # Nothing changed: the dependency set is covered by the lockfile and
          # the locked spec is installed.
          File.read(File.join(dir, "Gemfile.lock")).should eq(locked)
        end
      end
    end
  end

  it "keeps the not-found report when there is no lockfile to reuse (exit 7)" do
    with_missing_dep_bridge do
      with_project({
        "Gemfile" => "source \"#{missing_dep_index_url}\"\n\ngem \"json_pure\"\ngem \"thor\"\n",
      }) do |dir|
        gem_root = File.join(dir, ".bundle", "ruby", missing_dep_local_abi)
        Dir.mkdir_p(gem_root)
        missing_dep_install_gem(gem_root, File.expand_path("../fixtures/gem-index/gems/json_pure-2.8.1.gem", __DIR__))
        with_missing_dep_gem_home(gem_root) do
          code, out, err = run_cli(["install", "--local"])
          code.should eq(7)
          out.should eq("")
          err.chomp.should eq("Could not find gem 'thor' in locally installed gems.")
          File.exists?(File.join(dir, "Gemfile.lock")).should be_false
        end
      end
    end
  end
end
