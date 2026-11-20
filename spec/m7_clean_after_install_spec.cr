require "./spec_helper"

# M7(3): `bundle install`/`update` run the cleaner after the install when
# `BUNDLE_CLEAN` is set (`cli/common.rb:150-156`, `cli/install.rb:69`,
# `cli/update.rb:84`): locked specs stay, everything else in the bundle path is
# removed and announced as `Removing <name> (<version>)`.
def clean_spec_gemspec(name : String, version : String) : String
  <<-SPEC
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "#{version}"
      s.summary = "fixture"
      s.authors = ["Celerite"]
      s.files = ["lib/#{name}.rb"]
    end
    SPEC
end

describe "M7 clean_after_install" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    ENV.delete("BUNDLE_CLEAN")
  end

  index_url = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))

  preset = {
    "vendor/bundle/ruby/4.0.0/specifications/json_pure-2.8.1.gemspec" => clean_spec_gemspec("json_pure", "2.8.1"),
    "vendor/bundle/ruby/4.0.0/specifications/thor-1.3.2.gemspec"      => clean_spec_gemspec("thor", "1.3.2"),
    "vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1/lib/json_pure.rb"  => "",
    "vendor/bundle/ruby/4.0.0/gems/thor-1.3.2/lib/thor.rb"            => "",
  }

  it "removes gems outside the lockfile after the install summary" do
    ENV["BUNDLE_CLEAN"] = "true"
    with_project({
      "Gemfile"        => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config" => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }.merge(preset)) do |dir|
      code, stdout, stderr = run_cli(["install"])
      code.should eq(0)
      stderr.should eq("")
      stdout.should contain("Removing thor (1.3.2)")
      # The removal line follows the install summary (`cli/install.rb:69`).
      stdout.index("Bundled gems are installed into `").not_nil!.should be < stdout.index("Removing thor (1.3.2)").not_nil!
      File.directory?(File.join(dir, "vendor/bundle/ruby/4.0.0/gems/thor-1.3.2")).should be_false
      File.directory?(File.join(dir, "vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1")).should be_true
    end
  end

  it "keeps stale gems when BUNDLE_CLEAN is not set" do
    with_project({
      "Gemfile"        => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config" => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }.merge(preset)) do |dir|
      code, stdout, _stderr = run_cli(["install"])
      code.should eq(0)
      stdout.should_not contain("Removing thor")
      File.directory?(File.join(dir, "vendor/bundle/ruby/4.0.0/gems/thor-1.3.2")).should be_true
    end
  end

  it "cleans after `update --all` before `Bundle updated!`" do
    ENV["BUNDLE_CLEAN"] = "true"
    with_project({
      "Gemfile"        => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config" => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }.merge(preset)) do |dir|
      code, stdout, _stderr = run_cli(["update", "--all"])
      code.should eq(0)
      stdout.should contain("Removing thor (1.3.2)")
      stdout.index("Removing thor (1.3.2)").not_nil!.should be < stdout.index("Bundle updated!").not_nil!
      File.directory?(File.join(dir, "vendor/bundle/ruby/4.0.0/gems/thor-1.3.2")).should be_false
    end
  end

  it "keeps stale gems when BUNDLE_CLEAN is explicitly false" do
    ENV["BUNDLE_CLEAN"] = "false"
    with_project({
      "Gemfile"        => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config" => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }.merge(preset)) do |dir|
      code, stdout, _stderr = run_cli(["install"])
      code.should eq(0)
      stdout.should_not contain("Removing thor")
      File.directory?(File.join(dir, "vendor/bundle/ruby/4.0.0/gems/thor-1.3.2")).should be_true
    end
  end
end
