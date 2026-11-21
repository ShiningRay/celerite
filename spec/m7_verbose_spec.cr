require "./spec_helper"

# M7 task-78: `BUNDLE_VERBOSE` (settings.rb:21 `verbose`) must behave like the
# `--verbose` global flag, and the verbose transcript carries the reference's
# debug lines (`definition.rb:868-875`, `parallel_installer.rb:18`).
private def verbose_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def verbose_gemfile : String
  "source \"#{verbose_index_url}\"\n\ngem \"json_pure\"\n"
end

private def with_verbose_env(values : Hash(String, String), &)
  previous = {} of String => String?
  values.each do |key, value|
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

describe "M7 verbose output" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end

  it "prints the reference debug lines for --verbose" do
    with_project({"Gemfile" => verbose_gemfile}) do |dir|
      env = {
        "BUNDLE_PATH"                      => File.join(dir, "tmp-bundle"),
        "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
        "BUNDLE_VERBOSE"                   => "",
      }
      with_verbose_env(env) do
        run_cli(["install"]).first.should eq(0)
        code, out, _err = run_cli(["install", "--verbose"])
        code.should eq(0)
        out.should contain("Running `bundle install --verbose` with bundler 4.0.24")
        out.should contain("Found no changes, using resolution from the lockfile")
        out.should contain("Using bundler 4.0.24")
        out.should contain("Using json_pure 2.8.1")
        out.should contain("0:  json_pure (2.8.1) from")
      end
    end
  end

  # `-V` is Thor's short alias for `--verbose` (`cli.rb` class option), so the
  # echo still renders the long form the reference prints.
  it "treats -V like --verbose" do
    with_project({"Gemfile" => verbose_gemfile}) do |dir|
      env = {
        "BUNDLE_PATH"                      => File.join(dir, "tmp-bundle"),
        "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
        "BUNDLE_VERBOSE"                   => "",
      }
      with_verbose_env(env) do
        run_cli(["install"]).first.should eq(0)
        code, out, _err = run_cli(["install", "-V"])
        code.should eq(0)
        out.should contain("Running `bundle install --verbose` with bundler 4.0.24")
        out.should contain("Using json_pure 2.8.1")
      end
    end
  end

  # With the setting alone the transcript is identical but the echo must not
  # invent a `--verbose` the user never typed.
  it "honours BUNDLE_VERBOSE=true without adding --verbose to the echo" do
    with_project({"Gemfile" => verbose_gemfile}) do |dir|
      env = {
        "BUNDLE_PATH"                      => File.join(dir, "tmp-bundle"),
        "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
      }
      with_verbose_env(env.merge({"BUNDLE_VERBOSE" => "false"})) do
        run_cli(["install"]).first.should eq(0)
      end
      with_verbose_env(env.merge({"BUNDLE_VERBOSE" => "true"})) do
        code, out, _err = run_cli(["install"])
        code.should eq(0)
        out.should contain("Running `bundle install` with bundler 4.0.24")
        out.should_not contain("install --verbose")
        out.should contain("Found no changes, using resolution from the lockfile")
        out.should contain("Using bundler 4.0.24")
      end
    end
  end

  # `BUNDLE_VERBOSE=false` must not swallow the explicit flag.
  it "keeps --verbose effective when BUNDLE_VERBOSE is false" do
    with_project({"Gemfile" => verbose_gemfile}) do |dir|
      env = {
        "BUNDLE_PATH"                      => File.join(dir, "tmp-bundle"),
        "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
        "BUNDLE_VERBOSE"                   => "false",
      }
      with_verbose_env(env) do
        run_cli(["install"]).first.should eq(0)
        code, out, _err = run_cli(["install", "--verbose"])
        code.should eq(0)
        out.should contain("Running `bundle install --verbose` with bundler 4.0.24")
        out.should contain("Using json_pure 2.8.1")
      end
    end
  end
end
