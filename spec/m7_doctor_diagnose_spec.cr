require "./spec_helper"

# M7: `bundle doctor` is a Thor subcommand class (`cli/doctor.rb:6-20`,
# `cli.rb:589-602`, `:669-671`). `diagnose` is the default subcommand; a
# subcommand `--help` becomes `bundle help doctor <sub>` and is rejected as an
# argument; unknown options are leftover arguments of `diagnose`.
def doctor_spec_gemspec(name : String, version : String) : String
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

describe "M7 doctor subcommand surface" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    ENV.delete("BUNDLE_GEMFILE")
  end

  index_url = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))

  it "prints the doctor manpage for `doctor --help`" do
    code, stdout, stderr = run_cli(["doctor", "--help"])
    code.should eq(0)
    stderr.should eq("")
    stdout.should start_with("bundle-doctor(1) -- Checks the bundle for common problems")
    stdout.should contain("## SYNOPSIS")
    stdout.should contain("`bundle doctor [diagnose]` [--quiet]")
    stdout.should contain("`bundle doctor ssl` [--host=HOST]")
    stdout.chomp.should end_with("  Accepted values are: `CLIENT_ONCE`, `FAIL_IF_NO_PEER_CERT`, `NONE`, `PEER`.")
  end

  it "rejects a subcommand help as a `bundle help` argument" do
    code, stdout, stderr = run_cli(["doctor", "diagnose", "--help"])
    code.should eq(15)
    stdout.should eq("")
    stderr.should contain(%(ERROR: "bundle help" was called with arguments ["doctor", "diagnose"]))
    stderr.should contain(%(Usage: "bundle help [COMMAND]"))
  end

  it "reports unknown options as leftover arguments of diagnose" do
    code, _, stderr = run_cli(["doctor", "nosuchsub"])
    code.should eq(15)
    stderr.should contain(%(ERROR: "bundle doctor diagnose" was called with arguments ["nosuchsub"]))
    stderr.should contain(%(Usage: "bundle doctor diagnose [OPTIONS]"))
  end

  it "prints nothing for `doctor --quiet` when the bundle is satisfied" do
    with_project({
      "Gemfile"                                                         => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config"                                                  => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
      "vendor/bundle/ruby/4.0.0/specifications/json_pure-2.8.1.gemspec" => doctor_spec_gemspec("json_pure", "2.8.1"),
      "vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1/lib/json_pure.rb"  => "",
    }) do |_dir|
      code, stdout, stderr = run_cli(["doctor", "--quiet"])
      code.should eq(0)
      stdout.should eq("")
      stderr.should eq("")
    end
  end

  it "warns once per dylib and still reports a clean bundle" do
    with_project({
      "Gemfile"                                                         => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config"                                                  => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
      "vendor/bundle/ruby/4.0.0/specifications/json_pure-2.8.1.gemspec" => doctor_spec_gemspec("json_pure", "2.8.1"),
      "vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1/lib/json_pure.rb"  => "",
      "vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1/lib/fake.bundle"   => "",
      "vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1/lib/other.bundle"  => "",
    }) do |_dir|
      code, stdout, stderr = run_cli(["doctor"])
      code.should eq(0)
      stdout.should contain("The Gemfile's dependencies are satisfied")
      stdout.should contain("No issues found with the installed bundle")
      stderr.should eq("Dynamic library check not supported on this platform.\n" * 2)
    end
  end
end
