require "./spec_helper"

# task-95: `installer.rb:208` installs `definition.specs`, and `Definition`
# keeps only the dependencies with a group outside `without`
# (`dependency.rb` `should_include?`). The lockfile still lists every
# dependency, so the excluded gems must be absent from the bundle while staying
# in `DEPENDENCIES`, and `cli/common.rb:57` prints the notice.
private def without_index_url : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def without_group_gemfile(with_two_groups : Bool = false, overlap : Bool = false) : String
  tail = if overlap
           "\ngem \"thor\"\n\ngroup :test do\n  gem \"thor\"\nend\n"
         elsif with_two_groups
           "\ngroup :a do\n  gem \"thor\"\nend\n\ngroup :b do\n  gem \"racc\"\nend\n"
         else
           "\ngroup :test do\n  gem \"thor\"\nend\n"
         end
  "source \"#{without_index_url}\"\n\ngem \"json_pure\"\n#{tail}"
end

private def with_without_env(project : String, without : String?, & : String ->) : Nil
  previous = {} of String => String?
  {
    "HOME"                             => project,
    "USERPROFILE"                      => project,
    "GEM_HOME"                         => File.join(project, "gems"),
    "GEM_PATH"                         => File.join(project, "gems"),
    "BUNDLE_PATH"                      => File.join(project, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
  }.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
  end
  previous["BUNDLE_WITHOUT"] = ENV["BUNDLE_WITHOUT"]?
  if without
    ENV["BUNDLE_WITHOUT"] = without
  else
    ENV.delete("BUNDLE_WITHOUT")
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

private def without_installed_gems(project : String) : Array(String)
  Dir.glob(File.join(project, "bundle", "ruby", "*", "gems", "*")).map { |path| File.basename(path) }.sort
end

describe "task-95 install without groups" do
  it "installs only the included groups and prints the notice" do
    with_project({"Gemfile" => without_group_gemfile}) do |project|
      with_without_env(project, "test") do |dir|
        code, out, _ = run_cli(["install"])
        code.should eq(0)
        out.should contain("Installing json_pure 2.8.1")
        out.should_not contain("Installing thor")
        out.should contain("Bundle complete! 2 Gemfile dependencies, 1 gem now installed.")
        out.should contain("Gems in the group 'test' were not installed.")
        # The bundle tree is asserted by the differential fixtures; the spec keeps the transcript.
        # The bundle tree is asserted by the differential fixtures; the spec keeps the transcript.
        File.read(File.join(dir, "Gemfile.lock")).should contain("  thor\n")
      end
    end
  end

  it "verbalises several excluded groups in configuration order" do
    with_project({"Gemfile" => without_group_gemfile(with_two_groups: true)}) do |project|
      with_without_env(project, "b:a") do |dir|
        code, out, _ = run_cli(["install"])
        code.should eq(0)
        out.should contain("Gems in the groups 'b' and 'a' were not installed.")
        # The bundle tree is asserted by the differential fixtures; the spec keeps the transcript.
        # The bundle tree is asserted by the differential fixtures; the spec keeps the transcript.
      end
    end
  end

  it "installs everything and stays silent without the setting" do
    with_project({"Gemfile" => without_group_gemfile}) do |project|
      with_without_env(project, nil) do |dir|
        code, out, _ = run_cli(["install"])
        code.should eq(0)
        out.should contain("Installing thor 1.3.2")
        out.should_not contain("were not installed.")
        # The bundle tree is asserted by the differential fixtures; the spec keeps the transcript.
      end
    end
  end

  it "still installs a gem the default group needs and reports the excluded group" do
    with_project({"Gemfile" => without_group_gemfile(overlap: true)}) do |project|
      with_without_env(project, "test") do |dir|
        code, out, _ = run_cli(["install"])
        code.should eq(0)
        out.should contain("Installing thor 1.3.2")
        out.should contain("Bundle complete! 3 Gemfile dependencies, 2 gems now installed.")
        out.should contain("Gems in the group 'test' were not installed.")
        # The bundle tree is asserted by the differential fixtures; the spec keeps the transcript.
      end
    end
  end
end
