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

  # `--print` decides the destination before the write: the lock body goes to
  # stdout and `--lockfile` never touches the disk (measured on 4.0.24 and
  # 2.7.2 -- `lock --lockfile custom.lock --print` writes neither file).
  it "prints the lock body without writing when --print is combined with --lockfile" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      original = File.read(File.join(dir, "Gemfile.lock"))
      code, out, err = run_cli(["lock", "--lockfile", "custom.lock", "--print"])
      code.should eq(0)
      err.should eq("")
      out.should_not contain("Writing lockfile to")
      out.should start_with("GEM\n")
      out.should contain("BUNDLED WITH")
      Dir.exists?(File.join(dir, "custom.lock")).should be_false
      File.read(File.join(dir, "Gemfile.lock")).should eq(original)
    end
  end

  # A missing parent directory is not created: the reference announces the
  # write target, then friendly-errors wraps `Errno::ENOENT` (definition.rb
  # 437-438) and exits 1. Our report keeps the same template shape because a
  # bare Crystal exception message is not the reference surface.
  it "reports a friendly-errors crash when the lockfile directory is missing" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      code, out, err = run_cli(["lock", "--lockfile", "./nodir/x.lock"])
      code.should eq(1)
      target = File.expand_path(File.join(dir, "nodir", "x.lock")).gsub('\\', "/")
      out.should contain("Writing lockfile to #{target}")
      err.should contain("--- ERROR REPORT TEMPLATE")
      err.should contain("Errno::ENOENT: No such file or directory @ rb_sysopen - #{target}")
      err.should contain("--- TEMPLATE END")
      err.should contain("Unfortunately, an unexpected error occurred")
      Dir.exists?(File.join(dir, "nodir")).should be_false
      err.should_not contain("celerite internal error")
    end
  end

  # Both flags are regression guards: the reference accepts them and the exit
  # code and lock stay unchanged, so there is nothing to discriminate.
  it "accepts --redownload on install and leaves the lock untouched" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      original = File.read(File.join(dir, "Gemfile.lock"))
      code, out, err = run_cli(["install", "--redownload"])
      code.should eq(0)
      out.should contain("Installing json_pure")
      File.read(File.join(dir, "Gemfile.lock")).should eq(original)
    end
  end

  # `install --target-rbconfig` loads the file through `Gem.set_target_rbconfig`
  # before resolution (cli/install.rb:24). For a pure-Ruby gem the loaded
  # rbconfig only refreshes `Gem::Platform.local`, so nothing is observable in
  # stdout or the lockfile -- this example pins the accepted surface.
  it "accepts an existing --target-rbconfig value" do
    pending! "ruby not available" unless ruby_available?
    with_lock_project do |dir|
      run_cli(["install"]).first.should eq(0)
      File.write(File.join(dir, "target-rbconfig.rb"), "TRIVIAL = 1\n")
      original = File.read(File.join(dir, "Gemfile.lock"))
      code, out, _ = run_cli(["install", "--target-rbconfig", "target-rbconfig.rb"])
      code.should eq(0)
      out.should contain("Bundle complete!")
      File.read(File.join(dir, "Gemfile.lock")).should eq(original)
    end
  end
end
