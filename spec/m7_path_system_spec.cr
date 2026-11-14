require "./spec_helper"

# M7(4) `path.system`: the install root must follow `Bundler::Settings::Path`
# (settings.rb L238-297). With `path.system` the reference uses `Gem.dir`
# (`Bundler.rubygems.gem_dir`) and does **not** append the ruby scope
# (`ruby/<abi>`); an explicit `path` wins over `path.system` (validator.rb
# L57-63 clears the earlier key).
private def path_system_config(values : Hash(String, Celerite::Config::Value)) : Celerite::Config
  dir = File.tempname("celerite-path-system")
  Dir.mkdir_p(dir)
  Celerite::Config.new(dir, values)
end

private def with_path_system_bridge(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def with_env_vars(vars : Hash(String, String?), &)
  saved = {} of String => String?
  vars.each_key { |key| saved[key] = ENV[key]? }
  begin
    vars.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
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

describe "M7(4) path.system install root" do
  it "uses the system gem dir without a ruby scope" do
    values = {} of String => Celerite::Config::Value
    values["BUNDLE_PATH__SYSTEM"] = "true"
    config = path_system_config(values)

    Celerite::InstallPaths.system_gems?(config).should be_true
    base = Celerite::InstallPaths.base_path(config, "/fake/system/gems")
    base.should eq(File.expand_path("/fake/system/gems"))

    root = Celerite::InstallPaths.gem_root(config, "/fake/system/gems", "4.0.0")
    root.should eq(File.expand_path("/fake/system/gems"))
    root.should_not contain("ruby/4.0.0")
  end

  it "keeps the product default .bundle/ruby/<abi> without any path setting" do
    config = path_system_config({} of String => Celerite::Config::Value)

    Celerite::InstallPaths.system_gems?(config).should be_false
    base = Celerite::InstallPaths.base_path(config, "/fake/system/gems")
    base.should eq(File.expand_path(File.join(Celerite::Config.user_home || ".", ".bundle")))

    root = Celerite::InstallPaths.gem_root(config, "/fake/system/gems", "4.0.0")
    root.should eq(File.join(base, "ruby", "4.0.0"))
  end

  it "lets an explicit path win over path.system" do
    values = {} of String => Celerite::Config::Value
    values["BUNDLE_PATH"] = "vendor/bundle"
    values["BUNDLE_PATH__SYSTEM"] = "true"
    config = path_system_config(values)

    Celerite::InstallPaths.system_gems?(config).should be_false
    base = Celerite::InstallPaths.base_path(config, "/fake/system/gems")
    base.should eq(File.expand_path("vendor/bundle"))
    Celerite::InstallPaths.gem_root(config, "/fake/system/gems", "4.0.0")
      .should eq(File.join(base, "ruby", "4.0.0"))
  end

  it "installs and checks gems in GEM_HOME when path.system is enabled" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_project({
      "Gemfile" => "source \"#{index}\"\n\ngem \"thor\"\n",
    }) do |dir|
      gem_home = File.join(dir, "sys-gems")
      Dir.mkdir_p(gem_home)

      with_path_system_bridge do
        # Isolate the home dir too: the machine-level `~/.bundle/config` sets
        # BUNDLE_PATH and would otherwise turn system gems off mid-spec.
        with_env_vars({"GEM_HOME" => gem_home, "HOME" => dir, "USERPROFILE" => dir, "BUNDLE_PATH__SYSTEM" => "true"}) do
          code, _, err = run_cli(["install"])
          code.should eq(0)
          err.should_not contain("Could not")

          File.exists?(File.join(gem_home, "gems", "thor-1.3.2")).should be_true
          Dir.exists?(File.join(gem_home, "ruby")).should be_false

          check_code, check_out, check_err = run_cli(["check"])
          check_code.should eq(0)
          check_err.should_not contain("missing")
        end
      end
    end
  end

  it "recomputes the cached system gem dirs when the environment changes" do
    pending! "ruby not available" unless ruby_available?
    with_project({} of String => String) do |dir|
      home = File.join(dir, "home")
      gem_home_a = File.join(dir, "gems-a")
      gem_home_b = File.join(dir, "gems-b")
      Dir.mkdir_p(home)
      Dir.mkdir_p(gem_home_a)
      Dir.mkdir_p(gem_home_b)

      with_path_system_bridge do
        with_env_vars({"GEM_HOME" => gem_home_a, "HOME" => home, "USERPROFILE" => home}) do
          first = Celerite::Commands.system_gem_search_dirs
          first.should contain(gem_home_a)

          with_env_vars({"GEM_HOME" => gem_home_b}) do
            second = Celerite::Commands.system_gem_search_dirs
            second.should contain(gem_home_b)
            second.should_not eq(first)
          end
        end
      end
    end
  end
end
