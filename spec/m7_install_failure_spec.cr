require "./spec_helper"

# M7(5): compile failures use the reference `InstallError` shape — status 5,
# RubyGems build error + real backtrace, "Gem files will remain installed …"
# and the `In Gemfile:` dependency tree (bundler/gem_installer.rb:44-57,
# bundler/parallel_installer.rb:198,256-275).

private def failing_extension_gem(name : String) : String
  File.expand_path("fixtures/failing-extension/gems/#{name}", __DIR__)
end

private def failing_extension_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def failure_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

private def failure_bridge(&)
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

private def failure_ruby_gem_dir : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.default_dir"], output: output)
  output.to_s
end

private def with_failure_env(project : String, &)
  gem_home = File.join(project, "gemhome")
  Dir.mkdir_p(gem_home)
  names = ["HOME", "USERPROFILE", "BUNDLE_PATH", "GEM_HOME", "GEM_PATH"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, ".bundle-test")
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = "#{gem_home};#{failure_ruby_gem_dir}"
  begin
    yield File.join(project, ".bundle-test")
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

private def failure_project(dir : String, gem_name : String, gems : Array(String)) : Nil
  File.write(File.join(dir, "Gemfile"),
    "source \"#{failing_extension_remote}\"\n\ngem \"#{gem_name}\"\n")
  cache = File.join(dir, "vendor", "cache")
  Dir.mkdir_p(cache)
  gems.each { |gem| FileUtils.cp(failing_extension_gem(gem), File.join(cache, gem)) }
end

private def failure_gem_root(bundle : String) : String
  File.join(bundle, "ruby", failure_abi)
end

describe "M7(5) install failure semantics" do
  it "fails with the reference InstallError for a direct dependency" do
    failure_bridge do
      with_project({} of String => String) do |dir|
        failure_project(dir, "fail-ext", ["fail-ext-0.1.0.gem"])
        with_failure_env(dir) do |bundle|
          code, output, errors = run_cli(["install", "--local"])
          code.should eq(5)
          output.should contain("Installing fail-ext 0.1.0 with native extensions")
          errors.lines.first.should eq("Gem::Ext::BuildError: ERROR: Failed to build gem native extension.")
          flattened = errors.gsub(/\s+/, " ")
          flattened.should contain("Gem files will remain installed in")
          flattened.should contain("for inspection.")
          errors.strip.lines.last(4).should eq(["continue.", "", "In Gemfile:", "  fail-ext"])

          gem_root = failure_gem_root(bundle)
          File.file?(File.join(gem_root, "gems", "fail-ext-0.1.0", "ext", "extconf.rb")).should be_true
          File.file?(File.join(gem_root, "specifications", "fail-ext-0.1.0.gemspec")).should be_false
        end
      end
    end
  end

  it "prints the resolved dependency chain for a transitive failure" do
    failure_bridge do
      with_project({} of String => String) do |dir|
        failure_project(dir, "fail-parent", ["fail-parent-0.1.0.gem", "fail-ext-0.1.0.gem"])
        with_failure_env(dir) do
          code, _output, errors = run_cli(["install", "--local"])
          code.should eq(5)
          errors.strip.lines.last(5).should eq([
            "continue.",
            "",
            "In Gemfile:",
            "  fail-parent was resolved to 0.1.0, which depends on",
            "    fail-ext",
          ])
        end
      end
    end
  end

  it "keeps the pre-existing error path for non-extension failures" do
    failure_bridge do
      with_project({} of String => String) do |dir|
        failure_project(dir, "json_pure", [] of String)
        with_failure_env(dir) do
          code, _output, errors = run_cli(["install", "--local"])
          code.should eq(7)
          errors.should contain("Could not find gem 'json_pure' in locally installed gems.")
        end
      end
    end
  end
end
