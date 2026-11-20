require "./spec_helper"

# `bundle lock --add-platform <platform>` keeps the native spec row (task-64
# item 2). The reference resolves to one installable variant and then feeds
# the result through
# `SpecSet.new(resolved).specs_with_additional_variants_from(base.locked_specs)`
# (`resolver.rb:88-89`, `spec_set.rb:184-185`, `:301-309`), so a gem that also
# has a ruby-platform spec keeps that row in the lockfile even though only the
# platform variant is installed. `fixtures/gem-index-platform` ships both
# `platdemo` gems; `x64-mingw32` has no variant there, so adding it is exactly
# the case where the ruby row must survive.
#
# `[DEPRECATED] Found x64-mingw32 in lockfile ...` comes from the lockfile
# parser (`lockfile_parser.rb:157-159` on 4.0.24, `:144-155` on 2.7.2), so it
# fires on the command that parses such a lock -- 2.7.2 additionally rewrites
# the platform list while parsing, which is why its `PLATFORMS` shrinks.
private PLATFORM_INDEX_PLACEHOLDER = "file:///@PLATFORM_INDEX_DIR@"

private def add_platform_gemfile : String
  url = file_source_url(File.expand_path("../fixtures/gem-index-platform", __DIR__))
  "source \"#{url}\"\n\ngem \"platdemo\"\n"
end

private def with_add_platform_env(profile : String, &) : Nil
  keys = [
    "HOME", "USERPROFILE", "BUNDLE_PATH", "BUNDLE_APP_CONFIG",
    "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION",
    "CELERITE_REFERENCE_BUNDLER_VERSION", "CELERITE_REFERENCE_BUNDLER_LIB",
  ]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]?; ENV.delete(key) }
  begin
    yield
  ensure
    keys.each do |key|
      ENV.delete(key)
      if value = previous[key]
        ENV[key] = value
      end
    end
  end
end

private def add_platform_run(profile : String, dir : String, args : Array(String)) : {Int32, String, String}
  code = 0
  out = ""
  err = ""
  with_add_platform_env(profile) do
    app_config = File.join(dir, ".bundle")
    Dir.mkdir_p(app_config)
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
    ENV["BUNDLE_APP_CONFIG"] = app_config
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = profile
    ENV["CELERITE_REFERENCE_BUNDLER_VERSION"] = profile
    ENV["CELERITE_REFERENCE_BUNDLER_LIB"] = if profile == "2.7.2"
                                              "C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-2.7.2/lib"
                                            else
                                              File.expand_path("../.upstream-specs/v4.0.24/bundler/lib", __DIR__)
                                            end
    code, out, err = run_cli(args)
  end
  {code, out, err}
end

private def spec_lines(lockfile : String) : Array(String)
  lockfile.lines(chomp: true)
    .skip_while(&.!=("  specs:"))
    .skip(1).take_while { |line| line.starts_with?("    ") }
    .map(&.strip)
end

private def checksum_lines(lockfile : String) : Array(String)
  lines = lockfile.lines(chomp: true)
  index = lines.index("CHECKSUMS")
  return [] of String unless index
  lines[(index + 1)..].take_while { |line| line.starts_with?("  ") }.map(&.strip)
end

describe "M7(3) lock --add-platform keeps the native spec" do
  it "writes both the ruby and the platform row" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => add_platform_gemfile}) do |dir|
      code, out, err = add_platform_run("4.0.24", dir, ["lock", "--add-platform", "x64-mingw32"])
      code.should eq(0)
      err.should be_empty
      out.should contain("Writing lockfile to")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      spec_lines(lock).should eq(["platdemo (1.0.0)", "platdemo (1.0.0-x64-mingw-ucrt)"])
      lock.should contain("PLATFORMS\n  x64-mingw-ucrt\n  x64-mingw32\n")
      # Neither row has a digest yet: nothing is installed, and the checksum
      # table for the extra row comes from the index entry of that variant.
      checksum_lines(lock).should eq([
        "bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc",
        "platdemo (1.0.0)",
        "platdemo (1.0.0-x64-mingw-ucrt)",
      ])
    end
  end

  it "installs the platform variant only and keeps the extra row out of the count" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => add_platform_gemfile}) do |dir|
      add_platform_run("4.0.24", dir, ["lock", "--add-platform", "x64-mingw32"]).first.should eq(0)
      code, out, err = add_platform_run("4.0.24", dir, ["install"])
      code.should eq(0)
      out.should contain("Bundle complete! 1 Gemfile dependency, 1 gem now installed.")
      out.scan("Installing platdemo").size.should eq(1)
      out.should contain("Installing platdemo 1.0.0 (x64-mingw-ucrt)")
      err.should contain("[DEPRECATED] Found x64-mingw32 in lockfile, which is deprecated and will be removed in the future.")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      spec_lines(lock).should eq(["platdemo (1.0.0)", "platdemo (1.0.0-x64-mingw-ucrt)"])
      checksum_lines(lock).last.should eq(
        "platdemo (1.0.0-x64-mingw-ucrt) sha256=f02daf2996ea7ff8b3bdbb3ee90e575138a5628b9299edc5dbd43ce4ab81ecd6",
      )
      checksum_lines(lock).should contain("platdemo (1.0.0)")
    end
  end

  it "keeps the extra row on the 2.7.2 reuse path and drops the legacy platform" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => add_platform_gemfile}) do |dir|
      add_platform_run("2.7.2", dir, ["lock", "--add-platform", "x64-mingw32"]).first.should eq(0)
      code, out, err = add_platform_run("2.7.2", dir, ["install"])
      code.should eq(0)
      out.should contain("Bundle complete! 1 Gemfile dependency, 2 gems now installed.")
      out.scan("Installing platdemo").size.should eq(1)
      err.should contain("[DEPRECATED] Found x64-mingw32 in lockfile, which is deprecated. Removing it.")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      spec_lines(lock).should eq(["platdemo (1.0.0)", "platdemo (1.0.0-x64-mingw-ucrt)"])
      lock.should contain("PLATFORMS\n  x64-mingw-ucrt\n")
      lock.should_not contain("CHECKSUMS")
      lock.should_not contain("x64-mingw32")
    end
  end

  it "does not duplicate the rows on a second lock" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => add_platform_gemfile}) do |dir|
      add_platform_run("4.0.24", dir, ["lock", "--add-platform", "x64-mingw32"]).first.should eq(0)
      before = File.read(File.join(dir, "Gemfile.lock"))
      add_platform_run("4.0.24", dir, ["install"]).first.should eq(0)
      code, _, err = add_platform_run("4.0.24", dir, ["lock"])
      code.should eq(0)
      err.should contain("[DEPRECATED] Found x64-mingw32 in lockfile")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      spec_lines(lock).should eq(["platdemo (1.0.0)", "platdemo (1.0.0-x64-mingw-ucrt)"])
      lock.should contain("PLATFORMS\n  x64-mingw-ucrt\n  x64-mingw32\n")
      before.lines.size.should be <= lock.lines.size
    end
  end
end
