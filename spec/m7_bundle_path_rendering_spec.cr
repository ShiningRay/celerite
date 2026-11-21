require "./spec_helper"

# `cli/install.rb` L59-64 / `settings.rb:253-285`: the `Bundled gems are installed
# into` line prints the configured path relative to the working directory, keeps
# an absolute value exactly as it was written (backslashes included), and treats
# an explicitly empty value as the current directory (`./.`).
describe "celerite install bundle path rendering" do
  it "prefixes a relative path with ./" do
    with_bundle_path_env("./bundel") do |dir|
      code, out, err = bundle_path_run(dir)
      code.should eq(0), err
      out.should contain("Bundled gems are installed into `./bundel`")
    end
  end

  it "keeps the spelling of an absolute path" do
    absolute = File.join(bundle_path_root, "bundle-dir")
    with_bundle_path_env(absolute) do |dir|
      code, out, err = bundle_path_run(dir)
      code.should eq(0), err
      out.should contain("Bundled gems are installed into `#{absolute}`")
    end
  end

  it "prints ./. when the path is set but empty" do
    with_bundle_path_env("") do |dir|
      code, out, err = bundle_path_run(dir)
      code.should eq(0), err
      out.should contain("Bundled gems are installed into `./.`")
    end
  end
end

private def bundle_path_root : String
  File.join(Dir.current, ".tmp-scratch", "spec-bundle-path")
end

private def bundle_path_index : String
  File.join(Dir.current, "fixtures", "gem-index")
end

private def with_bundle_path_env(value : String, &)
  root = bundle_path_root
  FileUtils.rm_rf(root)
  project = File.join(root, "project")
  home = File.join(root, "home")
  Dir.mkdir_p(project)
  Dir.mkdir_p(home)
  File.write(File.join(project, "Gemfile"), "source #{file_source_url(bundle_path_index).inspect}\n\ngem \"json_pure\"\n")
  saved = {} of String => String?
  env = {
    "HOME"                             => home,
    "USERPROFILE"                      => home,
    "BUNDLE_PATH"                      => value,
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "BUNDLE_GEMFILE"                   => File.join(project, "Gemfile"),
    "CELERITE_BRIDGE_SERVER"           => File.join(Dir.current, "assets", "bridge", "server.rb"),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    "CELERITE_REFERENCE_BUNDLER_LIB"   => File.join(Dir.current, ".upstream-specs", "v4.0.24", "bundler", "lib"),
  }
  env.each { |key, _| saved[key] = ENV[key]? }
  begin
    env.each { |key, v| ENV[key] = v }
    yield project
  ensure
    saved.each do |key, v|
      if v.nil?
        ENV.delete(key)
      else
        ENV[key] = v
      end
    end
  end
end

private def bundle_path_run(project : String) : {Int32, String, String}
  Dir.cd(project) { run_cli(["install"]) }
end
