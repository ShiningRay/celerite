require "./spec_helper"

private def promotion_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def promotion_files : Hash(String, String)
  {
    "Gemfile"      => %(source "#{promotion_index_url}"\n\ngem "json_pure"\ngem "thor"\n),
    "Gemfile.lock" => <<-LOCK,
      GEM
        remote: #{promotion_index_url}/
        specs:
          json_pure (2.6.0)
          thor (1.3.2)

      PLATFORMS
        x64-mingw-ucrt

      DEPENDENCIES
        json_pure
        thor

      BUNDLED WITH
         4.0.24
      LOCK
  }
end

private def with_promotion_env(dir : String, &)
  keys = {"HOME", "USERPROFILE", "BUNDLE_APP_CONFIG", "BUNDLE_PATH", "CELERITE_BRIDGE_SERVER", "CELERITE_PROFILE_BUNDLER_VERSION"}
  saved = keys.map { |key| {key, ENV[key]?} }.to_h
  begin
    home = File.join(dir, "home")
    Dir.mkdir_p(File.join(home, "cfg"))
    ENV["HOME"] = home
    ENV["USERPROFILE"] = home
    ENV["BUNDLE_APP_CONFIG"] = File.join(home, "cfg")
    ENV["BUNDLE_PATH"] = File.join(home, "bundle")
    ENV["CELERITE_BRIDGE_SERVER"] = File.join(File.expand_path("..", __DIR__), "assets", "bridge", "server.rb")
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
    yield
  ensure
    saved.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end

describe "version promotion" do
  it "keeps a patch-level gem on its patch line for lock --patch --update" do
    with_project(promotion_files) do |dir|
      with_promotion_env(dir) do
        code, out, err = run_cli(["lock", "--patch", "--update", "json_pure"])
        code.should eq(0)
        File.read(File.join(dir, "Gemfile.lock")).should contain("json_pure (2.6.0)")
        err.should_not contain("Provide only one")
      end
    end
  end

  it "promotes to the newest minor for lock --minor --update" do
    with_project(promotion_files) do |dir|
      with_promotion_env(dir) do
        code, _, _ = run_cli(["lock", "--minor", "--update", "json_pure"])
        code.should eq(0)
        File.read(File.join(dir, "Gemfile.lock")).should contain("json_pure (2.8.1)")
      end
    end
  end

  it "rejects two levels on lock before writing" do
    with_project(promotion_files) do |dir|
      with_promotion_env(dir) do
        code, _, err = run_cli(["lock", "--patch", "--minor", "--update", "json_pure"])
        code.should eq(15)
        err.strip.should eq("Provide only one of the following options: minor, patch")
        File.read(File.join(dir, "Gemfile.lock")).should contain("json_pure (2.6.0)")
      end
    end
  end

  it "rejects two levels on update" do
    with_project(promotion_files) do |dir|
      with_promotion_env(dir) do
        run_cli(["install", "--quiet"])
        code, _, err = run_cli(["update", "--patch", "--minor", "json_pure"])
        code.should eq(15)
        err.strip.should eq("Provide only one of the following options: minor, patch")
      end
    end
  end
end
