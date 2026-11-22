require "./spec_helper"

# task-135: outside the differential harness `CELERITE_REFERENCE_BUNDLER_LIB`
# is not exported, so `show bundler` resolves through the bridge's installed
# specs instead - the real installed-gem phase. `cli/show.rb:20-21` expands
# `../../..` from `__dir__`, which is `<gem>/lib/bundler/cli`, i.e. the gem
# root. Anchoring one level lower (`lib/bundler`) printed the shared `<gems>`
# directory that only *contains* the gem.
private def show_bundler_path_fixture : Hash(String, String)
  {
    "Gemfile" => "source \"#{file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))}\"\n\ngem \"json_pure\"\n",
  }
end

# The task pins the Ruby that owns the reference 4.0.24 gem. Prefer it over a
# bare `ruby` lookup so the expected value never comes from another Ruby.
private def show_bundler_path_ruby : String
  pinned = "C:/Ruby40-x64/bin/ruby.exe"
  File.exists?(pinned) ? pinned : "ruby"
end

# Resolve the expected value from the real installation instead of pinning the
# host layout: the installed bundler 4.0.24 gem is what the bridge reports.
private def show_bundler_path_installed_gem_dir : String?
  output = IO::Memory.new
  status = Process.run(
    show_bundler_path_ruby,
    ["-e", %(print(Gem::Specification.find_by_name("bundler", "4.0.24").full_gem_path))],
    output: output, error: Process::Redirect::Close)
  return nil unless status.success?
  dir = output.to_s.strip
  return nil if dir.empty?
  cli_dir = File.join(dir, "lib", "bundler", "cli")
  File.exists?(File.join(cli_dir, "show.rb")) ? dir : nil
end

# task-136: `info bundler --path` shares the special case with `show bundler`
# (`cli/info.rb:36-47` print_gem_path), so the same helper must answer both.
# The reference-lib phase matters separately: under the differential harness
# `CELERITE_REFERENCE_BUNDLER_LIB` is exported and the answer is the checkout
# root, which the old `lib/bundler` anchor ignored entirely.
private def show_bundler_path_reference_lib : String?
  output = IO::Memory.new
  status = Process.run(
    show_bundler_path_ruby,
    ["-e", %(print(File.join(Gem::Specification.find_by_name("bundler", "4.0.24").full_gem_path, "lib")))],
    output: output, error: Process::Redirect::Close)
  return nil unless status.success?
  dir = output.to_s.strip
  return nil if dir.empty?
  File.exists?(File.join(dir, "bundler", "cli", "info.rb")) ? dir : nil
end

private def with_show_bundler_path_env(project : String, reference_lib : String? = nil, & : ->) : Nil
  previous = {} of String => String?
  {
    "HOME"                             => project,
    "USERPROFILE"                      => project,
    "BUNDLE_PATH"                      => File.join(project, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    "CELERITE_REFERENCE_BUNDLER_LIB"   => reference_lib,
  }.each do |key, value|
    previous[key] = ENV[key]?
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
  begin
    yield
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

describe "task-135 show bundler outside the harness" do
  it "prints the installed bundler gem directory for `show bundler`" do
    next unless ruby_available?
    expected = show_bundler_path_installed_gem_dir
    pending!("no installed bundler 4.0.24 gem to resolve") if expected.nil?
    gem_dir = expected.not_nil!.gsub('\\', "/")
    with_project(show_bundler_path_fixture) do |project|
      with_show_bundler_path_env(project) do
        run_cli(["install", "--quiet"]).first.should eq(0)
        code, out, err = run_cli(["show", "bundler"])
        code.should eq(0)
        err.should eq("")
        out.strip.should eq(gem_dir)
        # The gem root, not the shared `<gems>` directory holding it.
        out.strip.should_not eq(File.dirname(gem_dir))
      end
    end
  end

  it "prints the installed bundler gem directory for `show bundler --paths`" do
    next unless ruby_available?
    expected = show_bundler_path_installed_gem_dir
    pending!("no installed bundler 4.0.24 gem to resolve") if expected.nil?
    gem_dir = expected.not_nil!.gsub('\\', "/")
    with_project(show_bundler_path_fixture) do |project|
      with_show_bundler_path_env(project) do
        run_cli(["install", "--quiet"]).first.should eq(0)
        code, out, err = run_cli(["show", "bundler", "--paths"])
        code.should eq(0)
        err.should eq("")
        out.strip.should eq(gem_dir)
        out.strip.should_not eq(File.dirname(gem_dir))
      end
    end
  end
end

# task-136: `cli/info.rb:36-47` `print_gem_path` special-cases bundler with the
# same `File.expand_path("../../..", __dir__)`, so `info bundler --path` must
# print the gem root - not the shared `<gems>` directory holding it (the bug)
# and not a stale value that ignores the reference-lib configuration.
describe "task-136 info bundler --path outside the harness" do
  it "prints the installed bundler gem directory when CELERITE_REFERENCE_BUNDLER_LIB is unset" do
    next unless ruby_available?
    expected = show_bundler_path_installed_gem_dir
    pending!("no installed bundler 4.0.24 gem to resolve") if expected.nil?
    gem_dir = expected.not_nil!.gsub('\\', "/")
    with_project(show_bundler_path_fixture) do |project|
      with_show_bundler_path_env(project) do
        run_cli(["install", "--quiet"]).first.should eq(0)
        code, out, err = run_cli(["info", "bundler", "--path"])
        code.should eq(0)
        err.should eq("")
        out.strip.should eq(gem_dir)
        out.strip.should_not eq(File.dirname(gem_dir))
      end
    end
  end

  it "prints the reference checkout root when CELERITE_REFERENCE_BUNDLER_LIB is set" do
    next unless ruby_available?
    expected = show_bundler_path_installed_gem_dir
    pending!("no installed bundler 4.0.24 gem to resolve") if expected.nil?
    gem_dir = expected.not_nil!.gsub('\\', "/")
    reference_lib = show_bundler_path_reference_lib
    pending!("no installed bundler 4.0.24 lib to resolve") if reference_lib.nil?
    # In this phase the resolution walks `bundler_gem_dir` -> `dirname(ref_lib)`,
    # so the assertion that the env var was really exported keeps the two
    # phases from collapsing into the same code path.
    File.dirname(reference_lib.not_nil!).gsub('\\', "/").should eq(gem_dir)
    with_project(show_bundler_path_fixture) do |project|
      with_show_bundler_path_env(project, reference_lib) do
        ENV["CELERITE_REFERENCE_BUNDLER_LIB"].should_not be_nil
        run_cli(["install", "--quiet"]).first.should eq(0)
        code, out, err = run_cli(["info", "bundler", "--path"])
        code.should eq(0)
        err.should eq("")
        out.strip.should eq(gem_dir)
        out.strip.should_not eq(File.dirname(gem_dir))
      end
    end
  end
end
