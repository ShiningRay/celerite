require "./spec_helper"

# M7 task-167: `Injector#inject` resolves the injected dependency, appends the
# Gemfile line and relocks *before* `Installer.install` runs
# (bundler-4.0.24/lib/bundler/injector.rb:44-50 vs lib/bundler/cli/add.rb:22),
# so an install-stage failure leaves both files rewritten on disk. A failure
# raised while injecting itself happens before `append_to`, so the Gemfile
# keeps its original bytes.
private def add_strict_index : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def add_strict_gemfile : String
  "source \"#{add_strict_index}\"\n\ngem \"json_pure\"\n"
end

private def add_strict_lockfile : String
  [
    "GEM",
    "  remote: https://rubygems.org/",
    "  specs:",
    "    json_pure (2.8.1)",
    "    rake (13.4.2)",
    "",
    "PLATFORMS",
    "  x64-mingw-ucrt",
    "",
    "DEPENDENCIES",
    "  json_pure",
    "  rake (~> 13.0)",
    "",
    "BUNDLED WITH",
    "  4.0.24",
    "",
  ].join("\n")
end

private def with_add_strict_env(dir : String, &)
  keys = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_APP_CONFIG CELERITE_BRIDGE_SERVER]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]? }
  ENV["HOME"] = File.join(dir, "home")
  ENV["USERPROFILE"] = File.join(dir, "home")
  ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(dir, "appcfg")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  Dir.mkdir_p(ENV["HOME"])
  Dir.mkdir_p(ENV["BUNDLE_APP_CONFIG"])
  begin
    yield
  ensure
    keys.each do |key|
      if value = previous[key]
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

describe "M7 bundle add --strict write timing" do
  it "keeps the appended Gemfile and the relocked lockfile when install fails" do
    with_project({"Gemfile" => add_strict_gemfile, "Gemfile.lock" => add_strict_lockfile}) do |dir|
      with_add_strict_env(dir) do
        code, _out, err = run_cli(["add", "racc", "--strict"])
        code.should eq(7)
        err.should contain("Could not find gem 'racc (= 1.8)' in rubygems repository")
        err.should contain("The source contains the following gems matching 'racc':")
        File.read(File.join(dir, "Gemfile")).should contain("gem \"racc\", \"= 1.8\"")
        lockfile = File.read(File.join(dir, "Gemfile.lock"))
        lockfile.should contain("DEPENDENCIES\n  json_pure\n  racc\n")
        # The relock used the injected `>= 0` requirement, so `rake` drops out.
        lockfile.should_not contain("rake")
      end
    end
  end

  it "keeps the Gemfile untouched when the injection itself fails" do
    with_project({"Gemfile" => add_strict_gemfile}) do |dir|
      with_add_strict_env(dir) do
        code, _out, err = run_cli(["add", "nosuchgem"])
        code.should eq(7)
        err.should contain("Could not find gem 'nosuchgem' in rubygems repository")
        File.read(File.join(dir, "Gemfile")).should eq(add_strict_gemfile)
      end
    end
  end
end
