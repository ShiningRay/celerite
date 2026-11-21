require "./spec_helper"

# task-92: the bridge round-trips a `file://` Gemfile source without its drive
# colon (`C/Users/...`), while a lockfile keeps `file://C:/Users/...`. The frozen
# source comparison must fold both spellings; otherwise an untouched lock is
# reported as "the list of sources changed" (exit 16). The reference compares
# `Source` objects, whose identifiers normalise the same way.
private def frozen_source_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index-locked-deps", __DIR__))
end

private def frozen_source_project : Hash(String, String)
  {
    "Gemfile" => "source \"#{frozen_source_index_url}\"\n\ngem \"net-smtp\", \"0.5.0\"\n",
  }
end

private def frozen_source_lockfile(remote : String) : String
  <<-LOCK
    GEM
      remote: #{remote}
      specs:
        net-smtp (0.5.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      net-smtp (= 0.5.0)
    LOCK
end

private def with_frozen_source_env(project : String, & : String ->) : Nil
  previous = {} of String => String?
  {
    "BUNDLE_FROZEN"                    => "true",
    "HOME"                             => project,
    "USERPROFILE"                      => project,
    "BUNDLE_PATH"                      => File.join(project, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
  }.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
  end
  begin
    yield project
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

describe "task-92 frozen source normalisation" do
  it "keeps a non-canonical file:// drive spelling equal to the Gemfile source" do
    with_project(frozen_source_project) do |project|
      # Two-slash form (`file://C:/...`): the same directory the Gemfile names,
      # and the shape a hand-written/3rd-party lockfile can carry.
      remote = frozen_source_index_url.sub("file:///", "file://")
      File.write(File.join(project, "Gemfile.lock"), frozen_source_lockfile(remote))

      with_frozen_source_env(project) do
        code, _, err = run_cli(["install"])
        err.should_not contain("the list of sources changed")
        code.should_not eq(16)
      end
    end
  end

  it "still reports a source change when the locked remote really differs" do
    with_project(frozen_source_project) do |project|
      File.write(File.join(project, "Gemfile.lock"),
        frozen_source_lockfile("file:///C:/somewhere/else/"))

      with_frozen_source_env(project) do
        code, _, err = run_cli(["install"])
        code.should eq(16)
        err.should contain("list of sources changed")
      end
    end
  end
end
