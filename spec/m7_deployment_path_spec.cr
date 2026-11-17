require "./spec_helper"

# M7(4) deployment default target: `Settings#path` (settings.rb L238-251)
# injects `vendor/bundle` when deployment mode is on and no path was given, and
# `Definition#ensure_equivalent_gemfile_and_lockfile` (definition.rb L475-492)
# refuses to update the lockfile in frozen mode with a `ProductionError`
# (status 16). `bundler/installer.rb:63-71` creates the bundle path before that
# check, so the failure still leaves `vendor/bundle/ruby/<abi>` behind.
private def dep_path_config(values : Hash(String, Celerite::Config::Value)) : {Celerite::Config, String}
  dir = File.tempname("celerite-deployment")
  Dir.mkdir_p(dir)
  {Celerite::Config.new(dir, values), dir}
end

private def with_dep_bridge(&)
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

private def with_dep_env(vars : Hash(String, String?), &)
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

# A lockfile whose CHECKSUMS entry for json_pure exists but carries no hash,
# which is what a deployment install of an unchecked source has to reject.
private def dep_empty_checksums_lock(index : String, bundler_version : String) : String
  <<-LOCK
  GEM
    remote: #{index}
    specs:
      json_pure (2.8.1)

  PLATFORMS
    x64-mingw-ucrt

  DEPENDENCIES
    json_pure (= 2.8.1)

  CHECKSUMS
    json_pure (2.8.1)

  BUNDLED WITH
    #{bundler_version}
  LOCK
end

private def dep_isolated_env(project : String, extra : Hash(String, String?) = {} of String => String?) : Hash(String, String?)
  home = File.join(project, "home")
  gems = File.join(project, "gems")
  Dir.mkdir_p(home)
  Dir.mkdir_p(gems)
  env = {
    "HOME"               => home,
    "USERPROFILE"        => home,
    "GEM_HOME"           => gems,
    "GEM_PATH"           => gems,
    "BUNDLE_USER_CONFIG" => File.join(home, ".bundle", "config"),
    "BUNDLE_PATH"        => nil,
    "BUNDLE_DEPLOYMENT"  => nil,
    "BUNDLE_FROZEN"      => nil,
    "BUNDLE_WITH"        => nil,
    "BUNDLE_WITHOUT"     => nil,
  } of String => String?
  extra.each { |key, value| env[key] = value }
  env
end

private def dep_project_files(index : String) : Hash(String, String)
  {
    "Gemfile"      => "source \"#{index}\"\n\ngem \"json_pure\", \"2.8.1\"\n",
    "Gemfile.lock" => dep_empty_checksums_lock(index, "4.0.24"),
  }
end

describe "M7(4) deployment install target" do
  it "uses vendor/bundle when deployment mode has no explicit path" do
    values = {} of String => Celerite::Config::Value
    values["BUNDLE_DEPLOYMENT"] = "true"
    config, dir = dep_path_config(values)

    Celerite::InstallPaths.use_system_gems?(config).should be_false
    base = Celerite::InstallPaths.base_path(config, "/fake/system/gems")
    base.should eq(File.expand_path(File.join(dir, "vendor", "bundle")))
    Celerite::InstallPaths.gem_root(config, "/fake/system/gems", "4.0.0")
      .should eq(File.join(base, "ruby", "4.0.0"))

    Dir.cd(dir) do
      relative = Celerite::InstallPaths.base_path_relative_to_pwd(config, dir)
      relative.should eq("./vendor/bundle")
      relative.should_not contain("\\")
    end
  end

  it "lets an explicit path win over the deployment default" do
    values = {} of String => Celerite::Config::Value
    values["BUNDLE_DEPLOYMENT"] = "true"
    values["BUNDLE_PATH"] = "custom/vendor"
    config, dir = dep_path_config(values)

    Celerite::InstallPaths.base_path(config, "/fake/system/gems")
      .should eq(File.expand_path(File.join(dir, "custom", "vendor")))
  end

  it "refuses to update an empty CHECKSUMS entry in deployment mode" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_project(dep_project_files(index)) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_DEPLOYMENT" => "true"})) do
          code, out, err = run_cli(["install"])
          code.should eq(16), "#{out}\n#{err}"
          err.should contain("Your lockfile has an empty CHECKSUMS entry for \"json_pure\", but can't be updated")
          err.should contain("because frozen mode is set")
          err.should contain("Run `bundle install` elsewhere and add the updated Gemfile.lock to version")
          err.should contain("If this is a development machine, remove the Gemfile.lock freeze by running")
          # installer.rb:63-71: the bundle path exists before the frozen check.
          Dir.exists?(File.join(dir, "vendor", "bundle")).should be_true
          # `Dir.glob` treats `\` as an escape on Windows, so list the children
          # instead of globbing a native pattern.
          Dir.children(File.join(dir, "vendor", "bundle", "ruby")).empty?.should be_false
        end
      end
    end
  end

  it "drops the hint when frozen comes from BUNDLE_FROZEN" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_project(dep_project_files(index)) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_FROZEN" => "true"})) do
          code, _out, err = run_cli(["install"])
          code.should eq(16), err
          err.should contain("empty CHECKSUMS entry for \"json_pure\"")
          err.should_not contain("If this is a development machine")
        end
      end
    end
  end

  it "rejects the same lockfile from check" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_project(dep_project_files(index)) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_DEPLOYMENT" => "true"})) do
          code, _out, err = run_cli(["check"])
          code.should eq(16), err
          err.should contain("Your lockfile has an empty CHECKSUMS entry for \"json_pure\", but can't be updated")
        end
      end
    end
  end

  it "accepts a lockfile without a CHECKSUMS section" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    lock = dep_empty_checksums_lock(index, "4.0.24")
      .sub(/CHECKSUMS\n  json_pure \(2\.8\.1\)\n\n/, "")
    with_project({"Gemfile" => "source \"#{index}\"\n\ngem \"json_pure\", \"2.8.1\"\n", "Gemfile.lock" => lock}) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_DEPLOYMENT" => "true"})) do
          definition = Celerite::Definition.build
          definition.config.frozen?.should be_true
          # Without a store the reference has no CHECKSUMS reason to report
          # (definition.rb L973-1002), so the frozen guard lets the install run.
          definition.validate_frozen_lockfile!
        end
      end
    end
  end

  it "lists an added dependency like the reference Gemfile diff" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    files = dep_project_files(index)
    files["Gemfile"] = "source \"#{index}\"\n\ngem \"json_pure\", \"2.8.1\"\ngem \"thor\", \"1.3.2\"\n"
    with_project(files) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_FROZEN" => "true"})) do
          code, _out, err = run_cli(["install"])
          code.should eq(16), err
          # definition.rb L906-921 joins the reasons in order, dependencies
          # first, then the CHECKSUMS entry.
          err.should contain("The dependencies in your gemfile changed, your lockfile has an empty CHECKSUMS")
          err.should contain("entry for \"json_pure\", but the lockfile can't be updated because frozen mode is")
          err.should contain("but the lockfile can't be updated because frozen mode")
          err.should contain("You have added to the Gemfile:\n* thor (= 1.3.2)")
          err.should_not contain("You have deleted from the Gemfile")
        end
      end
    end
  end

  it "lists a deleted dependency without the dependency-changed reason" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    lock = <<-LOCK
    GEM
      remote: #{index}
      specs:
        json_pure (2.8.1)
        thor (1.3.2)

    PLATFORMS
      x64-mingw-ucrt

    DEPENDENCIES
      json_pure (= 2.8.1)
      thor (= 1.3.2)

    CHECKSUMS
      json_pure (2.8.1)
      thor (1.3.2)

    BUNDLED WITH
      4.0.24
    LOCK
    with_project({"Gemfile" => "source \"#{index}\"\n\ngem \"json_pure\", \"2.8.1\"\n", "Gemfile.lock" => lock}) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_FROZEN" => "true"})) do
          code, _out, err = run_cli(["install"])
          code.should eq(16), err
          # A pure deletion does not set `@dependency_changes`
          # (definition.rb L1051-1087) yet still prints the deleted list.
          err.should contain("Your lockfile has an empty CHECKSUMS entry for \"json_pure\", but can't be updated")
          err.should_not contain("The dependencies in your gemfile changed")
          err.should contain("You have deleted from the Gemfile:\n* thor (= 1.3.2)")
        end
      end
    end
  end

  it "reports a scoped source switch as a changed entry" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    scoped = file_source_url(File.expand_path("../fixtures/gem-index-scoped", __DIR__))
    files = dep_project_files(index)
    files["Gemfile"] = "source \"#{index}\"\n\ngem \"json_pure\", \"2.8.1\", source: \"#{scoped}\"\n"
    with_project(files) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_FROZEN" => "true"})) do
          code, _out, err = run_cli(["install"])
          code.should eq(16), err
          # definition.rb L906-921 lists the source change before the
          # dependencies and the CHECKSUMS entry.
          err.should contain("The list of sources changed, your lockfile has an empty CHECKSUMS entry for")
          err.should contain("You have changed in the Gemfile:\n* json_pure from `no specified source` to `rubygems repository")
          err.should contain("gem-index-scoped/`")
          err.should_not contain("The dependencies in your gemfile changed")
        end
      end
    end
  end

  it "reports a replaced default source without a changed entry" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    scoped = file_source_url(File.expand_path("../fixtures/gem-index-scoped", __DIR__))
    files = dep_project_files(index)
    files["Gemfile"] = "source \"#{scoped}\"\n\ngem \"json_pure\", \"2.8.1\"\n"
    with_project(files) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_FROZEN" => "true"})) do
          code, _out, err = run_cli(["install"])
          code.should eq(16), err
          # The dependency keeps the same label ("no specified source" on both
          # sides), so only the source-list reason is reported (definition.rb
          # L152, L908).
          err.should contain("The list of sources changed, your lockfile has an empty CHECKSUMS entry for")
          err.should_not contain("You have changed in the Gemfile:")
        end
      end
    end
  end

  it "keeps the default source quiet when it matches the lockfile" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    lock = dep_empty_checksums_lock(index, "4.0.24")
      .sub(/CHECKSUMS\n  json_pure \(2\.8\.1\)\n\n/, "")
    with_project({"Gemfile" => "source \"#{index}\"\n\ngem \"json_pure\", \"2.8.1\"\n", "Gemfile.lock" => lock}) do |_dir|
      with_dep_bridge do
        definition = Celerite::Definition.build
        evaluation = Celerite::Bridge::Client.new.evaluate_gemfile(definition.gemfile_path)
        definition.validate_frozen_lockfile!(false, evaluation.dependencies, evaluation.sources)
      end
    end
  end

  it "reports a requirement change as one added and one deleted entry" do
    index = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    files = dep_project_files(index)
    files["Gemfile"] = "source \"#{index}\"\n\ngem \"json_pure\", \"2.6.0\"\n"
    with_project(files) do |dir|
      with_dep_bridge do
        with_dep_env(dep_isolated_env(dir, {"BUNDLE_FROZEN" => "true"})) do
          code, _out, err = run_cli(["install"])
          code.should eq(16), err
          err.should contain("You have added to the Gemfile:\n* json_pure (= 2.6.0)")
          err.should contain("You have deleted from the Gemfile:\n* json_pure (= 2.8.1)")
        end
      end
    end
  end
end
