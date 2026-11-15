require "./spec_helper"
require "../src/celerite/cli/commands"

# M7(1): `bundle show` lists the running Bundler as a member of the bundle
# (`Bundler.definition.specs` contains the bundler spec) and prints the
# listing header only for the human readable form. `bundle show --paths`
# prints bare paths, starting with the running Bundler's gem directory.
private def show_listing_ruby_version : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print RUBY_VERSION"], output: output)
  output.to_s
end

private def show_listing_ruby_abi : String
  output = IO::Memory.new
  Process.run("ruby", ["-e", "print Gem.ruby_api_version"], output: output)
  output.to_s
end

# The host Bundler gem directory, used as the "running Bundler" that
# `bundle show --paths` prints first.
private def show_listing_reference_lib : String?
  script = %(require "bundler"; spec = Gem.loaded_specs["bundler"]; print(spec ? File.join(spec.gem_dir, "lib") : ""))
  output = IO::Memory.new
  status = Process.run("ruby", ["-e", script], output: output)
  return nil unless status.success?
  path = output.to_s.strip
  return nil if path.empty?
  Dir.exists?(path) ? path : nil
end

private def seed_show_listing_json_pure(dir : String) : Nil
  ruby_root = File.join(dir, ".bundle", "ruby", show_listing_ruby_abi)
  spec_dir = File.join(ruby_root, "specifications")
  gem_dir = File.join(ruby_root, "gems", "json_pure-2.8.1")
  Dir.mkdir_p(spec_dir)
  Dir.mkdir_p(File.join(gem_dir, "lib"))
  File.write(File.join(spec_dir, "json_pure-2.8.1.gemspec"), <<-RUBY)
    Gem::Specification.new do |s|
      s.name = "json_pure"
      s.version = "2.8.1"
      s.summary = "stub installed gem"
      s.description = s.summary
      s.authors = ["Celerite specs"]
      s.email = ["specs@example.com"]
      s.homepage = "https://example.com/json_pure"
      s.license = "MIT"
      s.require_paths = ["lib"]
    end
    RUBY
  File.write(File.join(gem_dir, "lib", "celerite_fixture.rb"), "# stub\n")
end

private def show_listing_files : Hash(String, String)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  remote = file_source_url(index)
  gemfile = <<-GEMFILE
    source "#{remote}"

    ruby "#{show_listing_ruby_version}"

    gem "json_pure"
    GEMFILE
  lockfile = <<-LOCK
    GEM
      remote: #{remote}/
      specs:
        json_pure (2.8.1)

    PLATFORMS
      ruby

    DEPENDENCIES
      json_pure

    BUNDLED WITH
       4.0.24
    LOCK
  {"Gemfile" => gemfile, "Gemfile.lock" => lockfile}
end

private def with_show_listing_env(dir : String, reference_lib : String?, &)
  previous = {} of String => String?
  {"BUNDLE_PATH", "CELERITE_BRIDGE_SERVER", "CELERITE_REFERENCE_BUNDLER_LIB", "CELERITE_PROFILE_BUNDLER_VERSION"}.each do |name|
    previous[name] = ENV[name]?
  end
  ENV["BUNDLE_PATH"] = File.join(dir, ".bundle")
  ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  if ref = reference_lib
    # The bridge needs its server script once any reference lib is visible.
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_REFERENCE_BUNDLER_LIB"] = ref
  else
    ENV.delete("CELERITE_BRIDGE_SERVER")
    ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  end
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

describe "M7(1) show listing" do
  it "lists the running Bundler before the locked gems in the human readable form" do
    next unless ruby_available?
    with_project(show_listing_files) do |dir|
      seed_show_listing_json_pure(dir)
      with_show_listing_env(dir, reference_lib: nil) do
        code, out, err = run_cli(["show"])
        code.should eq(0)
        out.should eq("Gems included by the bundle:\n  * bundler (4.0.24)\n  * json_pure (2.8.1)\n")
        err.should eq("")
      end
    end
  end

  it "prints bare paths for --paths, starting with the Bundler gem directory" do
    next unless ruby_available?
    reference_lib = show_listing_reference_lib
    next if reference_lib.nil?
    with_project(show_listing_files) do |dir|
      seed_show_listing_json_pure(dir)
      with_show_listing_env(dir, reference_lib: reference_lib) do
        code, out, err = run_cli(["show", "--paths"])
        code.should eq(0)
        out.should_not contain("Gems included by the bundle:")
        lines = out.lines
        lines.size.should eq(2)
        lines[0].should eq(File.dirname(reference_lib).gsub('\\', "/"))
        lines[1].should contain("json_pure-2.8.1")
        err.should eq("")
      end
    end
  end

  it "skips the Bundler path when no reference lib is configured (documented fallback)" do
    next unless ruby_available?
    with_project(show_listing_files) do |dir|
      seed_show_listing_json_pure(dir)
      with_show_listing_env(dir, reference_lib: nil) do
        code, out, err = run_cli(["show", "--paths"])
        code.should eq(0)
        out.should_not contain("Gems included by the bundle:")
        out.lines.size.should eq(1)
        out.should contain("json_pure-2.8.1")
        err.should eq("")
      end
    end
  end

  it "keeps the header for the human readable form when gems are missing" do
    next unless ruby_available?
    with_project(show_listing_files) do |dir|
      with_show_listing_env(dir, reference_lib: nil) do
        code, out, err = run_cli(["show"])
        code.should eq(7)
        out.should eq("Gems included by the bundle:\n")
        err.should contain("Could not find json_pure-2.8.1 in locally installed gems")
      end
    end
  end

  it "omits the header for --paths when gems are missing" do
    next unless ruby_available?
    reference_lib = show_listing_reference_lib
    next if reference_lib.nil?
    with_project(show_listing_files) do |dir|
      with_show_listing_env(dir, reference_lib: reference_lib) do
        code, out, err = run_cli(["show", "--paths"])
        code.should eq(7)
        out.should eq("")
        err.should contain("Could not find json_pure-2.8.1 in locally installed gems")
      end
    end
  end
end
