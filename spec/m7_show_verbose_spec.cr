require "./spec_helper"

# M7(2): `bundle show --verbose` runs the outdated check before the bundle is
# loaded (`bundler/cli/show.rb:34-47 fetch_latest_specs`), so the
# "Fetching remote specs for outdated check..." header and the index lines come
# first, and the listing grows a Summary/Homepage/Status block per gem
# (`cli/show.rb:60-74`). Bundler 2.7.2 reaches the same branch through the
# deprecated `--outdated` flag (`cli/show.rb` `@verbose = options[:verbose] ||
# options[:outdated]`).
private def show_verbose_ruby_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

private def seed_show_verbose_gem(dir : String, version : String) : Nil
  ruby_root = File.join(dir, ".bundle", "ruby", show_verbose_ruby_abi)
  spec_dir = File.join(ruby_root, "specifications")
  gem_dir = File.join(ruby_root, "gems", "json_pure-#{version}")
  Dir.mkdir_p(spec_dir)
  Dir.mkdir_p(File.join(gem_dir, "lib"))
  File.write(File.join(spec_dir, "json_pure-#{version}.gemspec"), <<-RUBY)
    Gem::Specification.new do |s|
      s.name = "json_pure"
      s.version = "#{version}"
      s.summary = "JSON Implementation for Ruby"
      s.description = s.summary
      s.authors = ["Celerite specs"]
      s.email = ["specs@example.com"]
      s.homepage = "http://flori.github.com/json"
      s.license = "MIT"
      s.require_paths = ["lib"]
    end
    RUBY
  File.write(File.join(gem_dir, "lib", "celerite_fixture.rb"), "# stub\n")
end

private def show_verbose_files(dependency_line : String, locked_version : String) : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  remote = file_source_url(index)
  gemfile = <<-GEMFILE
    source "#{remote}"

    #{dependency_line}
    GEMFILE
  lockfile = <<-LOCK
    GEM
      remote: #{remote}/
      specs:
        json_pure (#{locked_version})

    PLATFORMS
      ruby

    DEPENDENCIES
      #{dependency_line.sub(/\A\s*/, "")}

    BUNDLED WITH
       4.0.24
    LOCK
  {"Gemfile" => gemfile, "Gemfile.lock" => lockfile}
end

private def with_show_verbose_env(dir : String, & : ->) : Nil
  names = {"BUNDLE_PATH", "CELERITE_BRIDGE_SERVER", "CELERITE_REFERENCE_BUNDLER_LIB", "CELERITE_PROFILE_BUNDLER_VERSION"}
  previous = {} of String => String?
  names.each { |name| previous[name] = ENV[name]? }
  ENV["BUNDLE_PATH"] = File.join(dir, ".bundle")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
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

describe "M7(2) show --verbose" do
  it "prints the outdated header before the bundle and a status block per gem" do
    next unless ruby_available?
    with_project(show_verbose_files(%(gem "json_pure"), "2.6.0")) do |dir|
      seed_show_verbose_gem(dir, "2.6.0")
      with_show_verbose_env(dir) do
        code, out, err = run_cli(["show", "--verbose"])
        code.should eq(0)
        err.should eq("")
        out.should start_with("Fetching remote specs for outdated check...\n\n")
        out.should contain("Resolving dependencies...\nGems included by the bundle:\n* bundler (4.0.24)\n")
        out.should contain("\tSummary:  The best way to manage your application's dependencies\n")
        out.should contain("\tHomepage: https://bundler.io\n\tStatus:   Up to date\n")
        out.should contain("\tSummary:  JSON Implementation for Ruby\n" \
                           "\tHomepage: http://flori.github.com/json\n")
        # The Gemfile no longer pins 2.6.0, so the unlocked remote resolution
        # offers 2.8.1 and the locked 2.6.0 is reported as outdated.
        out.should contain("\tStatus:   Outdated - 2.6.0 < 2.8.1\n")
      end
    end
  end

  it "reports up to date when the resolution cannot move past the locked version" do
    next unless ruby_available?
    with_project(show_verbose_files(%(gem "json_pure", "2.6.0"), "2.6.0")) do |dir|
      seed_show_verbose_gem(dir, "2.6.0")
      with_show_verbose_env(dir) do
        code, out, err = run_cli(["show", "--verbose"])
        code.should eq(0)
        err.should eq("")
        out.should contain("* json_pure (2.6.0)\n")
        out.should contain("\tStatus:   Up to date\n")
        out.should_not contain("Outdated")
      end
    end
  end

  it "prints only the path for a named gem but keeps the outdated header" do
    next unless ruby_available?
    with_project(show_verbose_files(%(gem "json_pure"), "2.6.0")) do |dir|
      seed_show_verbose_gem(dir, "2.6.0")
      with_show_verbose_env(dir) do
        code, out, err = run_cli(["show", "--verbose", "json_pure"])
        code.should eq(0)
        err.should eq("")
        out.should start_with("Fetching remote specs for outdated check...\n\n")
        out.should contain("json_pure-2.6.0")
        out.should_not contain("Summary:")
      end
    end
  end

  it "keeps rejecting the removed --outdated flag on bundler 4" do
    with_project(show_verbose_files(%(gem "json_pure"), "2.6.0")) do
      code, out, err = run_cli(["show", "--outdated"])
      code.should eq(15)
      out.should eq("")
      err.should contain("the `--outdated` flag to `bundle show` has been removed in favor of")
      err.should contain("--verbose`")
    end
  end
end
