require "./spec_helper"

# Differential fixtures cover the same shapes end-to-end; these examples pin the
# surfaces that are easy to regress without a sandbox: the extra-positional
# banner shared by `info`/`show`/`list` (Thor rejects them before `run`) and
# `pristine`'s missing-cache error, which must skip the gem entirely.
private def extra_args_index_url : String
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  "file:///#{index.sub(%r{^/}, "")}"
end

private def extra_args_gemfile : String
  %(source "#{extra_args_index_url}"\n\ngem "json_pure", "2.6.0"\n)
end

# A lockfile plus a stub installed bundle (gemspec + gem dir, no `cache/` entry),
# mirroring the `bundle-preset` convention used by the differential fixtures.
private def pristine_preset_files : Hash(String, String)
  lock = <<-LOCK
    GEM
      remote: #{extra_args_index_url}/
      specs:
        json_pure (2.6.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      json_pure (= 2.6.0)

    BUNDLED WITH
        4.0.24
    LOCK
  gemspec = <<-SPEC
    Gem::Specification.new do |s|
      s.name = "json_pure"
      s.version = "2.6.0"
      s.summary = "stub installed gem for differential fixtures"
      s.description = s.summary
      s.authors = ["Celerite fixtures"]
      s.email = ["fixtures@example.com"]
      s.homepage = "https://example.com/json_pure"
      s.license = "MIT"
      s.require_paths = ["lib"]
    end
    SPEC
  {
    "Gemfile.lock"                                                   => lock,
    "bundle/ruby/4.0.0/specifications/json_pure-2.6.0.gemspec"       => gemspec,
    "bundle/ruby/4.0.0/gems/json_pure-2.6.0/lib/celerite_fixture.rb" => "",
  }
end

private def restore_env(name : String, value : String?) : Nil
  if value.nil?
    ENV.delete(name)
  else
    ENV[name] = value
  end
end

private def with_extra_args_project(files : Hash(String, String) = {} of String => String,
                                    & : String ->) : Nil
  saved_home = ENV["HOME"]?
  saved_profile = ENV["USERPROFILE"]?
  saved_path = ENV["BUNDLE_PATH"]?
  saved_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  with_project({"Gemfile" => extra_args_gemfile}.merge(files)) do |dir|
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    begin
      yield dir
    ensure
      restore_env("HOME", saved_home)
      restore_env("USERPROFILE", saved_profile)
      restore_env("BUNDLE_PATH", saved_path)
      restore_env("CELERITE_BRIDGE_SERVER", saved_bridge)
    end
  end
end

describe "extra positional arguments" do
  # `cli.rb` declares `desc "info GEM [OPTIONS]"`, so Thor rejects the second
  # positional with its own banner before the definition is built.
  it "rejects `info GEM extra` with the info banner" do
    with_extra_args_project do
      code, out, err = run_cli(["info", "json_pure", "extra"])
      code.should eq(15)
      out.should be_empty
      err.should contain(%(ERROR: "bundle info" was called with arguments ["json_pure", "extra"]))
      err.should contain(%(Usage: "bundle info GEM [OPTIONS]"))
    end
  end

  it "rejects `show GEM extra` with the show banner" do
    with_extra_args_project do
      code, out, err = run_cli(["show", "json_pure", "extra"])
      code.should eq(15)
      out.should be_empty
      err.should contain(%(ERROR: "bundle show" was called with arguments ["json_pure", "extra"]))
      err.should contain(%(Usage: "bundle show GEM [OPTIONS]"))
    end
  end

  # `bundle list` is declared without an argument list, and its usage line has no
  # `[OPTIONS]` suffix (`cli.rb:364`).
  it "rejects `list extra` with the bare list usage" do
    with_extra_args_project do
      code, out, err = run_cli(["list", "extra"])
      code.should eq(15)
      out.should be_empty
      err.should contain(%(ERROR: "bundle list" was called with arguments ["extra"]))
      err.should contain(%(Usage: "bundle list"))
      err.should_not contain("[OPTIONS]")
    end
  end
end

describe "pristine without a cached gem" do
  # `cli/pristine.rb:26-30` reports the missing cache entry and skips the gem, so
  # no `Installing` line is printed for it.
  it "reports the missing cache entry and does not reinstall" do
    with_extra_args_project(pristine_preset_files) do
      code, out, err = run_cli(["pristine"])
      code.should eq(0)
      out.should_not contain("Installing")
      err.should contain("Failed to pristine json_pure (2.6.0). Cached gem ")
      err.should contain("does not exist.")
      err.should_not contain("\\cache\\")
    end
  end
end
