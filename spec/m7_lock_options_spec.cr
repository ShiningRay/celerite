require "./spec_helper"

# `bundle lock` option semantics (task-58):
#   * `--normalize-platforms` runs `SpecSet#normalize_platforms!`
#     (`spec_set.rb:38-40`), which also calls `add_extra_platforms!`
#     (`:66-89`) - a pure-Ruby bundle therefore gains `ruby` next to the local
#     platform.
#   * `--lockfile PATH` only redirects where the lockfile is written; the
#     definition keeps reading the default lockfile (`cli.rb:69-77`,
#     `cli/lock.rb:81-93`), so an existing `Gemfile.lock` still short-circuits
#     the no-op path.
private def lock_options_project : Hash(String, String)
  url = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
  {
    "Gemfile" => "source \"#{url}\"\n\ngem \"json_pure\"\n",
  }
end

private def with_lock_project(&) : Nil
  with_project(lock_options_project) do |dir|
    previous = {} of String => String?
    {
      "HOME"                             => dir,
      "USERPROFILE"                      => dir,
      "BUNDLE_PATH"                      => File.join(dir, "bundle"),
      "BUNDLE_APP_CONFIG"                => File.join(dir, ".bundle"),
      "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
      "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    }.each do |key, value|
      previous[key] = ENV[key]?
      ENV[key] = value
    end
    begin
      yield dir
    ensure
      previous.each do |key, value|
        if value
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end
  end
end

private def platforms_block(lockfile : String) : String
  lockfile.lines(chomp: true).skip_while(&.!=("PLATFORMS"))
    .skip(1).take_while { |line| line.starts_with?("  ") }.join("\n")
end

describe "bundle lock options" do
  it "adds the ruby platform when normalizing platforms" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      code, out, err = run_cli(["lock", "--normalize-platforms"])
      code.should eq(0)
      lock = File.read(File.join(dir, "Gemfile.lock"))
      platforms_block(lock).should eq("  ruby\n  x64-mingw-ucrt")
    end
  end

  it "keeps the normalized platform list stable across repeated runs" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      run_cli(["lock", "--normalize-platforms"]).first.should eq(0)
      before = File.read(File.join(dir, "Gemfile.lock"))
      run_cli(["lock", "--normalize-platforms"]).first.should eq(0)
      File.read(File.join(dir, "Gemfile.lock")).should eq(before)
    end
  end

  it "reads the default lockfile but writes to --lockfile" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      original = File.read(File.join(dir, "Gemfile.lock"))
      code, out, err = run_cli(["lock", "--lockfile", "custom.lock"])
      code.should eq(0)
      out.should_not contain("Fetching source index")
      out.should_not contain("Resolving dependencies")
      out.should contain("Writing lockfile to #{File.expand_path(File.join(dir, "custom.lock")).gsub('\\', "/")}")
      File.read(File.join(dir, "custom.lock")).should eq(original)
      File.read(File.join(dir, "Gemfile.lock")).should eq(original)
    end
  end

  it "does not re-resolve when --lockfile points at the current lockfile" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      code, out, _ = run_cli(["lock", "--lockfile", "Gemfile.lock"])
      code.should eq(0)
      out.should_not contain("Fetching source index")
      out.should_not contain("Resolving dependencies")
    end
  end
end
