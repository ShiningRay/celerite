require "./spec_helper"

# M7(3) task-41: a default gem participates in resolution only when the
# configured sources have no candidate. The lock records it under the declared
# remote, `info` prints the interpreter path and `Default Gem: yes`, and a
# version constraint that the default gem cannot satisfy still fails.
describe "M7 default gem fallback" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end

  it "resolves a default gem only when the index has no candidate" do
    index = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))
    with_project({"Gemfile" => %(source "#{index}"\n\ngem "json"\n)}) do |dir|
      code, stdout, stderr = run_cli(["lock"])
      code.should eq(0)
      stderr.should be_empty
      stdout.should contain("Resolving dependencies...")
      lock = File.read(File.join(dir, "Gemfile.lock"))
      lock.should contain("    json (")
      lock.should contain("DEPENDENCIES\n  json\n")
      lock.should_not contain("bundler-source")
    end
  end

  it "prints the default gem marker in info" do
    index = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))
    with_project({"Gemfile" => %(source "#{index}"\n\ngem "json"\n)}) do |_dir|
      run_cli(["lock"])
      code, stdout, stderr = run_cli(["info", "json"])
      code.should eq(0)
      stderr.should be_empty
      stdout.should contain("Default Gem: yes")
      stdout.should contain("Path: ")
      stdout.should contain("json-")
    end
  end

  it "does not fall back when the constraint excludes the default gem" do
    index = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))
    with_project({"Gemfile" => %(source "#{index}"\n\ngem "json", "9.9"\n)}) do |_dir|
      code, _stdout, stderr = run_cli(["lock"])
      code.should eq(7)
      stderr.should contain("The source contains the following gems matching 'json':")
      stderr.should contain("json-")
    end
  end

  it "uses the reference wording for an unknown gem in info" do
    index = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))
    with_project({"Gemfile" => %(source "#{index}"\n\ngem "json"\n)}) do |_dir|
      run_cli(["lock"])
      code, _stdout, stderr = run_cli(["info", "nosuchgem"])
      code.should eq(7)
      stderr.should eq("Could not find gem 'nosuchgem'.\n")
    end
  end
end
