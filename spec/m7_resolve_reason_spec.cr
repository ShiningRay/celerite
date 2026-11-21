require "./spec_helper"

# M7 task-79: the verbose "why are we resolving" debug line
# (`definition.rb:866-876`, `:886-902`, `:906-923`). Thor's `say` suppresses the
# newline for a message that ends with a space, so an empty unlocking reason
# merges with the following local-server note.
private def resolve_reason_index : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def resolve_reason_gemfile(extra : String? = nil) : String
  body = "source \"#{resolve_reason_index}\"\n\ngem \"json_pure\", \"2.6.0\"\n"
  extra.nil? ? body : body + extra
end

private def with_resolve_reason_env(dir : String, verbose : String?, &)
  saved = {} of String => String?
  values = {
    "HOME"                             => File.join(dir, "home"),
    "USERPROFILE"                      => File.join(dir, "home"),
    "BUNDLE_PATH"                      => File.join(dir, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(dir, "appcfg"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    "BUNDLE_VERBOSE"                   => verbose,
  }
  values.each do |key, value|
    saved[key] = ENV[key]?
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
  end
  Dir.mkdir_p(File.join(dir, "home"))
  Dir.mkdir_p(File.join(dir, "appcfg"))
  begin
    yield
  ensure
    saved.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def resolve_reason_lock(index : String) : String
  <<-LOCK
  GEM
    remote: #{index}/
    specs:
      json_pure (2.6.0)

  PLATFORMS
    x64-mingw-ucrt

  DEPENDENCIES
    json_pure (= 2.6.0)

  BUNDLED WITH
     4.0.24
  LOCK
end

describe "M7 verbose resolve reason" do
  it "explains a gemfile dependency change before resolving" do
    index = resolve_reason_index
    with_project({
      "Gemfile"      => resolve_reason_gemfile("gem \"thor\"\n"),
      "Gemfile.lock" => resolve_reason_lock(index),
    }) do |dir|
      with_resolve_reason_env(dir, "true") do
        code, out, _err = run_cli(["check"])
        code.should eq(1)
        lines = out.lines
        lines[0].should eq("Found changes from the lockfile, re-resolving dependencies because the dependencies in your gemfile changed")
        lines[1].should eq("Using a local server, bundler won't use the CompactIndex API")
      end
    end
  end

  it "keeps the local-server note on the same line when the unlocking reason is empty" do
    index = resolve_reason_index
    with_project({"Gemfile" => resolve_reason_gemfile, "Gemfile.lock" => resolve_reason_lock(index)}) do |dir|
      with_resolve_reason_env(dir, "true") do
        run_cli(["install"]).first.should eq(0)
        _code, out, _err = run_cli(["update", "--all"])
        out.should contain(
          "Re-resolving dependencies because bundler is unlocking " \
          "Using a local server, bundler won't use the CompactIndex API\n"
        )
      end
    end
  end

  it "names the unlocked gems for a scoped update" do
    index = resolve_reason_index
    with_project({"Gemfile" => resolve_reason_gemfile, "Gemfile.lock" => resolve_reason_lock(index)}) do |dir|
      with_resolve_reason_env(dir, "true") do
        run_cli(["install"]).first.should eq(0)
        _code, out, _err = run_cli(["update", "json_pure"])
        out.should contain("Re-resolving dependencies because bundler is unlocking gems: (json_pure)\n")
        out.should_not contain("unlocking Using a local server")
      end
    end
  end

  it "prints no reason line without a verbose level" do
    index = resolve_reason_index
    with_project({"Gemfile" => resolve_reason_gemfile, "Gemfile.lock" => resolve_reason_lock(index)}) do |dir|
      with_resolve_reason_env(dir, nil) do
        run_cli(["install"]).first.should eq(0)
        _code, out, _err = run_cli(["check"])
        out.should_not contain("re-resolving dependencies")
        out.should_not contain("Using a local server")
      end
    end
  end
end
