require "./spec_helper"

# Reference `Bundler.load` resolves the Gemfile when no lockfile exists yet, so
# `bundle show`/`bundle info` work before the first `bundle install`:
#
# * a resolved gem that is installed anywhere RubyGems looks (the bundle path or
#   the GEM_PATH/default gem dir) is reported by path (`bundler/cli/common.rb:68-96`
#   `select_spec` over `Bundler.definition.specs`);
# * a resolved gem that is installed nowhere fails while materializing the
#   definition with `Could not find gem '<name>' in locally installed gems.`
#   (exit 7), and `show` does not print its listing header first.
#
# Pinned against bundler 4.0.24 in a project with a `file://` source and no
# Gemfile.lock.
private SHOW_NO_LOCK_INDEX = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def show_no_lock_bridge(& : ->) : Nil
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
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

private def show_no_lock_gemfile(dependency_line : String) : String
  <<-GEMFILE
  source "#{SHOW_NO_LOCK_INDEX}"

  #{dependency_line}
  GEMFILE
end

# Installs a fake RubyGems tree in `dir` so the CLI finds it through the
# GEM_PATH/GEM_HOME it reports from the bridge, without touching the machine's
# real gem directories.
private def install_fake_gem(dir : String, name : String, version : String) : String
  gem_dir = File.join(dir, "gems", "#{name}-#{version}")
  Dir.mkdir_p(gem_dir)
  Dir.mkdir_p(File.join(dir, "specifications"))
  File.write(File.join(dir, "specifications", "#{name}-#{version}.gemspec"), <<-GEMSPEC)
  Gem::Specification.new do |s|
    s.name = "#{name}"
    s.version = "#{version}"
    s.summary = "fixture gem"
  end
  GEMSPEC
  gem_dir
end

# Points both RubyGems (`GEM_HOME`/`GEM_PATH`) and the bundle path
# (`BUNDLE_PATH`) at the fake tree, so the example does not depend on which
# install location the definition happens to prefer when specs run in one
# process: whichever wins, the gem is already there and `show` reports it.
private def with_bundle_path(dir : String, & : ->) : Nil
  previous = ENV["BUNDLE_PATH"]?
  ENV["BUNDLE_PATH"] = dir
  begin
    yield
  ensure
    if previous
      ENV["BUNDLE_PATH"] = previous
    else
      ENV.delete("BUNDLE_PATH")
    end
  end
end

private def with_gem_path(dir : String, & : ->) : Nil
  previous_home = ENV["GEM_HOME"]?
  previous_path = ENV["GEM_PATH"]?
  ENV["GEM_HOME"] = dir
  ENV["GEM_PATH"] = dir
  begin
    yield
  ensure
    if previous_home
      ENV["GEM_HOME"] = previous_home
    else
      ENV.delete("GEM_HOME")
    end
    if previous_path
      ENV["GEM_PATH"] = previous_path
    else
      ENV.delete("GEM_PATH")
    end
  end
end

describe "show/info without a lockfile" do
  it "reports a resolved but uninstalled gem the way materialization does" do
    show_no_lock_bridge do
      with_project({"Gemfile" => show_no_lock_gemfile(%(gem "my_plugin"))}) do |project|
        File.exists?(File.join(project, "Gemfile.lock")).should be_false

        code, out, err = run_cli(["show", "my_plugin"])
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'my_plugin' in locally installed gems.\n")
      end
    end
  end

  it "spells the requirement out like the reference dependency display" do
    show_no_lock_bridge do
      with_project({"Gemfile" => show_no_lock_gemfile(%(gem "my_plugin", "0.1.0"))}) do
        code, out, err = run_cli(["show", "my_plugin"])
        code.should eq(7)
        out.should eq("")
        err.should eq("Could not find gem 'my_plugin (= 0.1.0)' in locally installed gems.\n")
      end
    end
  end

  it "keeps the same message for info, --paths and the bare listing" do
    show_no_lock_bridge do
      with_project({"Gemfile" => show_no_lock_gemfile(%(gem "my_plugin"))}) do
        {"info my_plugin"         => ["info", "my_plugin"],
         "show --paths my_plugin" => ["show", "--paths", "my_plugin"],
         "show"                   => ["show"]}.each do |label, args|
          code, out, err = run_cli(args)
          code.should eq(7)
          out.should eq(""), label
          err.should eq("Could not find gem 'my_plugin' in locally installed gems.\n"), label
        end
      end
    end
  end

  it "finds a resolved gem installed in the GEM_PATH" do
    gem_home = File.tempname("celerite-spec", "gemhome")
    installed_dir = install_fake_gem(gem_home, "json_pure", "2.8.1")
    begin
      show_no_lock_bridge do
        with_gem_path(gem_home) do
          with_bundle_path(gem_home) do
            with_project({"Gemfile" => show_no_lock_gemfile(%(gem "json_pure", "2.8.1"))}) do
              code, out, err = run_cli(["show", "json_pure"])
              code.should eq(0)
              err.should eq("")
              out.strip.should eq(installed_dir.gsub('\\', "/"))
            end
          end
        end
      end
    ensure
      FileUtils.rm_rf(gem_home)
    end
  end

  it "lists the resolved specs and the running bundler for a bare show" do
    gem_home = File.tempname("celerite-spec", "gemhome")
    install_fake_gem(gem_home, "json_pure", "2.8.1")
    begin
      show_no_lock_bridge do
        with_gem_path(gem_home) do
          with_project({"Gemfile" => show_no_lock_gemfile(%(gem "json_pure", "2.8.1"))}) do
            code, out, err = run_cli(["show"])
            code.should eq(0)
            err.should eq("")
            out.should eq("Gems included by the bundle:\n  * bundler (4.0.24)\n  * json_pure (2.8.1)\n")
          end
        end
      end
    ensure
      FileUtils.rm_rf(gem_home)
    end
  end
end
