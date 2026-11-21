require "./spec_helper"

# task-93: `cli/show.rb` sorts `Bundler.load.specs` by name for both the
# listing (`:37-51`) and the `--paths` form (`:33-36`), and the running Bundler
# is one of those specs - so it sorts with the rest instead of being pinned to
# the top. `show bundler` short-circuits to a single path line (`:19-30`).
private def show_order_project : Hash(String, String)
  url = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
  {
    "Gemfile"                        => "source \"#{url}\"\n\ngem \"json_pure\"\ngem \"app_gem\", path: \"vendor/app_gem\"\n",
    "vendor/app_gem/lib/app_gem.rb"  => "module AppGem\n  VERSION = \"1.0.0\"\nend\n",
    "vendor/app_gem/app_gem.gemspec" => <<-SPEC,
      Gem::Specification.new do |s|
        s.name = "app_gem"
        s.version = "1.0.0"
        s.summary = "App gem"
        s.homepage = "https://example.invalid/app_gem"
        s.authors = ["x"]
        s.files = ["lib/app_gem.rb"]
        s.require_paths = ["lib"]
      end
      SPEC
  }
end

private def with_show_order_env(project : String, & : ->) : Nil
  previous = {} of String => String?
  {
    "HOME"                             => project,
    "USERPROFILE"                      => project,
    "BUNDLE_PATH"                      => File.join(project, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    # `cli/show.rb:20-21` expands its own `lib/bundler`; under the harness the
    # running Bundler is the upstream checkout, so mirror that.
    "CELERITE_REFERENCE_BUNDLER_LIB" => File.expand_path("../.upstream-specs/v4.0.24/bundler/lib", __DIR__),
  }.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
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

private def show_order_installed(project : String) : Nil
  with_show_order_env(project) do
    code, _, err = run_cli(["install", "--quiet"])
    code.should eq(0)
    err.should_not contain("Could not find")
  end
end

describe "task-93 show ordering and bundler output" do
  it "sorts the listing by name, with bundler in its alphabetical slot" do
    with_project(show_order_project) do |project|
      show_order_installed(project)
      code = 0
      out = ""
      with_show_order_env(project) { code, out, _ = run_cli(["show"]) }
      code.should eq(0)
      lines = out.lines.reject(&.empty?)
      lines[0].should eq("Gems included by the bundle:")
      # app_gem < bundler < json_pure
      lines[1].should eq("  * app_gem (1.0.0)")
      lines[2].should eq("  * bundler (4.0.24)")
      lines[3].should eq("  * json_pure (2.8.1)")
    end
  end

  it "sorts --paths by name as well" do
    with_project(show_order_project) do |project|
      show_order_installed(project)
      code = 0
      out = ""
      with_show_order_env(project) { code, out, _ = run_cli(["show", "--paths"]) }
      code.should eq(0)
      lines = out.lines.reject(&.empty?)
      lines.size.should eq(3)
      lines[0].should contain("vendor/app_gem")
      lines[1].should contain("bundler")
      lines[2].should contain("json_pure")
    end
  end

  it "prints only a single path line for `show bundler`" do
    with_project(show_order_project) do |project|
      show_order_installed(project)
      code = 0
      out = ""
      with_show_order_env(project) { code, out, _ = run_cli(["show", "bundler"]) }
      code.should eq(0)
      out.lines.reject(&.empty?).size.should eq(1)
      out.should contain("bundler")
      out.should_not contain("* bundler")
      out.should_not contain("Summary:")
    end
  end

  it "keeps the single path line for `show bundler --paths`" do
    with_project(show_order_project) do |project|
      show_order_installed(project)
      code = 0
      out = ""
      with_show_order_env(project) { code, out, _ = run_cli(["show", "bundler", "--paths"]) }
      code.should eq(0)
      out.lines.reject(&.empty?).size.should eq(1)
      out.should contain("bundler")
      out.should_not contain("* bundler")
    end
  end
end
