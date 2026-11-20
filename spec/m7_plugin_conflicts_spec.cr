require "./spec_helper"

# M7(6): a `plugin install --path` that fails registration must behave like the
# reference in two ways — the exit status is 29 with the conflict message, the
# index keeps only the plugin that registered first, and (because `uninstall`
# removes `spec.full_gem_path`, which for a path source IS the source
# directory) the directory of the failing plugin is deleted.
# Anchors: `.upstream-specs/v4.0.24/bundler/lib/bundler/plugin/index.rb:54-76`,
# `plugin.rb:292-306`, `plugin/installer/path.rb`.

private def plugin_conflict_bin : String?
  candidate = File.expand_path("../bin/celerite.exe", __DIR__)
  return candidate if File.file?(candidate)

  fallback = File.expand_path("../bin/celerite", __DIR__)
  File.file?(fallback) ? fallback : nil
end

private def plugin_conflict_gemfile : String
  "source \"#{file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))}\"\n"
end

private def plugin_conflict_gemspec(name : String, summary : String) : String
  <<-SPEC
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "1.0.0"
      s.summary = "#{summary}"
      s.authors = ["Celerite"]
      s.files = ["plugins.rb"]
      s.require_paths = ["lib"]
    end
    SPEC
end

private def write_source_plugin(dir : String, name : String, klass : String, source_type : String) : Nil
  Dir.mkdir_p(dir)
  File.write(File.join(dir, "#{name}.gemspec"), plugin_conflict_gemspec(name, "stub plugin registering a source type"))
  File.write(File.join(dir, "plugins.rb"), <<-RUBY)
    require "bundler/plugin/api"

    class #{klass} < Bundler::Plugin::API
      source "#{source_type}"
    end
    RUBY
end

private def write_command_plugin(dir : String, name : String, klass : String, command_class : String) : Nil
  Dir.mkdir_p(dir)
  File.write(File.join(dir, "#{name}.gemspec"), plugin_conflict_gemspec(name, "stub plugin registering a command"))
  File.write(File.join(dir, "plugins.rb"), <<-RUBY)
    require "bundler/plugin/api"

    class #{command_class}
      def exec(command, args); end
    end

    class #{klass} < Bundler::Plugin::API
      command "conflictcmd", #{command_class}
    end
    RUBY
end

private def with_plugin_conflict_env(project : String, &)
  names = ["HOME", "USERPROFILE", "BUNDLE_PATH", "BUNDLE_APP_CONFIG", "GEM_HOME", "GEM_PATH", "CELERITE_BRIDGE_SERVER"]
  previous = names.to_h { |name| {name, ENV[name]?} }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["BUNDLE_APP_CONFIG"] = File.join(project, ".bundle")
  Dir.mkdir_p(ENV["BUNDLE_APP_CONFIG"])
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  ENV.delete("GEM_HOME")
  ENV.delete("GEM_PATH")
  begin
    yield
  ensure
    previous.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def run_plugin_conflict(bin : String, project : String, args : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(bin, args, chdir: project, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

private def plugin_index_text(project : String) : String
  path = File.join(project, ".bundle", "plugin", "index")
  File.file?(path) ? File.read(path) : ""
end

describe "M7(6) plugin install conflicts" do
  it "rejects a second plugin claiming the same source type" do
    bin = plugin_conflict_bin
    pending!("build bin/celerite.exe first") unless bin

    with_project({"Gemfile" => plugin_conflict_gemfile}) do |dir|
      project = File.expand_path(dir)
      write_source_plugin(File.join(project, "plug_a"), "plug_a", "PlugA", "conflict-type")
      write_source_plugin(File.join(project, "plug_b"), "plug_b", "PlugB", "conflict-type")

      with_plugin_conflict_env(project) do
        code_a, out_a, err_a = run_plugin_conflict(bin.as(String), project, ["plugin", "install", "plug_a", "--path", "plug_a"])
        {code_a, err_a}.should eq({0, ""})
        out_a.should contain("Installed plugin plug_a")

        code_b, _out_b, err_b = run_plugin_conflict(bin.as(String), project, ["plugin", "install", "plug_b", "--path", "plug_b"])
        code_b.should eq(29)
        err_b.should contain("Failed to install plugin `plug_b`, due to Bundler::Plugin::Index::SourceConflict")
        err_b.should contain("(Source(s) `conflict-type` declared by plug_b are already registered.)")

        index = plugin_index_text(project)
        index.should contain("conflict-type: \"plug_a\"")
        index.should_not contain("plug_b")
        # `uninstall` removes the path source's full_gem_path, i.e. the plugin
        # source directory the failed install was asked to read.
        Dir.exists?(File.join(project, "plug_b")).should be_false
        Dir.exists?(File.join(project, "plug_a")).should be_true
      end
    end
  end

  it "rejects a second plugin claiming the same command" do
    bin = plugin_conflict_bin
    pending!("build bin/celerite.exe first") unless bin

    with_project({"Gemfile" => plugin_conflict_gemfile}) do |dir|
      project = File.expand_path(dir)
      write_command_plugin(File.join(project, "plug_ca"), "plug_ca", "PlugCA", "ConflictCommand")
      write_command_plugin(File.join(project, "plug_cb"), "plug_cb", "PlugCB", "OtherConflictCommand")

      with_plugin_conflict_env(project) do
        code_a, _out_a, _err_a = run_plugin_conflict(bin.as(String), project, ["plugin", "install", "plug_ca", "--path", "plug_ca"])
        code_a.should eq(0)

        code_b, _out_b, err_b = run_plugin_conflict(bin.as(String), project, ["plugin", "install", "plug_cb", "--path", "plug_cb"])
        code_b.should eq(29)
        err_b.should contain("Bundler::Plugin::Index::CommandConflict (Command(s) `conflictcmd` declared by")
        err_b.should contain("plug_cb are already registered.)")

        index = plugin_index_text(project)
        index.should contain("conflictcmd: \"plug_ca\"")
        index.should_not contain("plug_cb")
        Dir.exists?(File.join(project, "plug_cb")).should be_false
      end
    end
  end

  it "keeps the source directory of a plugin that installs successfully" do
    bin = plugin_conflict_bin
    pending!("build bin/celerite.exe first") unless bin

    with_project({"Gemfile" => plugin_conflict_gemfile}) do |dir|
      project = File.expand_path(dir)
      write_source_plugin(File.join(project, "plug_a"), "plug_a", "PlugA", "conflict-type")

      with_plugin_conflict_env(project) do
        code, _out, err = run_plugin_conflict(bin.as(String), project, ["plugin", "install", "plug_a", "--path", "plug_a"])
        code.should eq(0)
        err.should eq("")
        Dir.exists?(File.join(project, "plug_a")).should be_true
        File.file?(File.join(project, "plug_a", "plugins.rb")).should be_true
      end
    end
  end

  it "leaves the index without a registration from the failed plugin" do
    bin = plugin_conflict_bin
    pending!("build bin/celerite.exe first") unless bin

    with_project({"Gemfile" => plugin_conflict_gemfile}) do |dir|
      project = File.expand_path(dir)
      write_source_plugin(File.join(project, "plug_a"), "plug_a", "PlugA", "conflict-type")
      write_source_plugin(File.join(project, "plug_b"), "plug_b", "PlugB", "conflict-type")

      with_plugin_conflict_env(project) do
        run_plugin_conflict(bin.as(String), project, ["plugin", "install", "plug_a", "--path", "plug_a"])
        before = plugin_index_text(project)
        run_plugin_conflict(bin.as(String), project, ["plugin", "install", "plug_b", "--path", "plug_b"])
        plugin_index_text(project).should eq(before)
      end
    end
  end
end
