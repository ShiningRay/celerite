require "./spec_helper"

# M7: `bundle doctor ssl` (`cli/doctor.rb:25-31`, `cli/doctor/ssl.rb:14-24`)
# prints the interpreter's OpenSSL build, probes Bundler/RubyGems/net/http and
# always exits 0; `doctor diagnose --ssl` runs the same report after the
# dependency check (`cli/doctor/diagnose.rb:77-79`), and `diagnose` has no
# `--host` option.
def doctor_ssl_spec_gemspec(name : String, version : String) : String
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

describe "M7 doctor ssl subcommand" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  end

  index_url = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))

  it "rejects `doctor ssl --help` as a `bundle help` argument" do
    code, stdout, stderr = run_cli(["doctor", "ssl", "--help"])
    code.should eq(15)
    stdout.should eq("")
    stderr.should eq(%(ERROR: "bundle help" was called with arguments ["doctor", "ssl"]\n) +
                     %(Usage: "bundle help [COMMAND]"\n))
  end

  it "prints the OpenSSL environment and exits 0 for an unreachable host" do
    code, stdout, stderr = run_cli(["doctor", "ssl", "--host", "no-such-host.invalid"])
    code.should eq(0)
    stdout.should start_with("Here's your OpenSSL environment:\n\nOpenSSL:       ")
    stdout.should contain("\nCompiled with: OpenSSL ")
    stdout.should contain("\nLoaded with:   OpenSSL ")
    stdout.should end_with("\nTrying connections to https://no-such-host.invalid:\n")
    stderr.should contain("Bundler:       failed")
    stderr.should contain("Ruby net/http: failed")
  end

  it "accepts the TLS and verification options and still exits 0" do
    code, stdout, _ = run_cli(["doctor", "ssl", "--host", "no-such-host.invalid",
                               "--tls-version", "TLS1_2", "--verify-mode", "none"])
    code.should eq(0)
    stdout.should contain("Trying connections to https://no-such-host.invalid:")
  end

  it "rejects `--host` as a diagnose argument" do
    code, stdout, stderr = run_cli(["doctor", "diagnose", "--ssl", "--host", "x"])
    code.should eq(15)
    stdout.should eq("")
    stderr.should eq(%(ERROR: "bundle doctor diagnose" was called with arguments ["--host", "x"]\n) +
                     %(Usage: "bundle doctor diagnose [OPTIONS]"\n))
  end

  it "runs the ssl report after the dependency check for `diagnose --ssl`" do
    with_project({
      "Gemfile"                                                         => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config"                                                  => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
      "vendor/bundle/ruby/4.0.0/specifications/json_pure-2.8.1.gemspec" => doctor_ssl_spec_gemspec("json_pure", "2.8.1"),
      "vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1/lib/json_pure.rb"  => "",
    }) do |_dir|
      code, stdout, _ = run_cli(["doctor", "diagnose", "--ssl"])
      code.should eq(0)
      stdout.should contain("The Gemfile's dependencies are satisfied")
      satisfied_at = stdout.index("The Gemfile's dependencies are satisfied").not_nil!
      stdout.index("OpenSSL:").not_nil!.should be > satisfied_at
      stdout.should contain("No issues found with the installed bundle")
    end
  end
end
