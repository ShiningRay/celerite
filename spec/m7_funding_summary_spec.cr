require "./spec_helper"

# M7(8): `install`/`update` end with the funding hint from `cli/common.rb:34-47`.
# The reference counts only direct Gemfile dependencies in the requested groups
# whose resolved spec carries a `funding_uri` metadata entry, is silent when the
# count is zero, and short-circuits when `ignore_funding_requests` is set.
def funded_gemspec(name : String, version : String, uri : String) : String
  <<-SPEC
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "#{version}"
      s.summary = "fixture"
      s.authors = ["Celerite"]
      s.files = ["lib/#{name}.rb"]
      s.metadata = { "funding_uri" => "#{uri}" }
    end
    SPEC
end

describe "M7 funding summary" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "4.0.24"
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  end

  index_url = file_source_url(File.expand_path("../fixtures/gem-index-legacy", __DIR__))

  it "prints the singular hint once after the install summary" do
    with_project({
      "Gemfile"                    => %(source "#{index_url}"\n\ngem "alpha", path: "vendor/alpha"\ngem "json_pure"\n),
      "vendor/alpha/alpha.gemspec" => funded_gemspec("alpha", "0.1.0", "https://example.com/fund/alpha"),
      "vendor/alpha/lib/alpha.rb"  => "",
      ".bundle/config"             => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }) do |_dir|
      code, stdout, stderr = run_cli(["install"])
      code.should eq(0)
      stderr.should eq("")
      stdout.should contain("Bundle complete! 2 Gemfile dependencies, 2 gems now installed.")
      stdout.should contain("1 installed gem you directly depend on is looking for funding.\n  Run `bundle fund` for details\n")
      # The hint is the last thing the reference prints.
      stdout.ends_with?("  Run `bundle fund` for details\n").should be_true
    end
  end

  it "uses the plural wording for two funded gems" do
    with_project({
      "Gemfile"                    => %(source "#{index_url}"\n\ngem "alpha", path: "vendor/alpha"\ngem "beta", path: "vendor/beta"\ngem "json_pure"\n),
      "vendor/alpha/alpha.gemspec" => funded_gemspec("alpha", "0.1.0", "https://example.com/fund/alpha"),
      "vendor/alpha/lib/alpha.rb"  => "",
      "vendor/beta/beta.gemspec"   => funded_gemspec("beta", "0.2.0", "https://example.com/fund/beta"),
      "vendor/beta/lib/beta.rb"    => "",
      ".bundle/config"             => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }) do |_dir|
      code, stdout, _stderr = run_cli(["install"])
      code.should eq(0)
      stdout.should contain("2 installed gems you directly depend on are looking for funding.\n  Run `bundle fund` for details\n")
    end
  end

  it "prints nothing when ignore_funding_requests is set" do
    with_project({
      "Gemfile"                    => %(source "#{index_url}"\n\ngem "alpha", path: "vendor/alpha"\ngem "json_pure"\n),
      "vendor/alpha/alpha.gemspec" => funded_gemspec("alpha", "0.1.0", "https://example.com/fund/alpha"),
      "vendor/alpha/lib/alpha.rb"  => "",
      ".bundle/config"             => %(---\nBUNDLE_PATH: "vendor/bundle"\nBUNDLE_IGNORE_FUNDING_REQUESTS: "true"\n),
    }) do |_dir|
      code, stdout, _stderr = run_cli(["install"])
      code.should eq(0)
      stdout.should_not contain("looking for funding")
    end
  end

  it "prints nothing when no direct dependency has funding metadata" do
    with_project({
      "Gemfile"        => %(source "#{index_url}"\n\ngem "json_pure"\n),
      ".bundle/config" => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }) do |_dir|
      code, stdout, _stderr = run_cli(["install"])
      code.should eq(0)
      stdout.should_not contain("looking for funding")
    end
  end

  it "prints the hint after `update --all`" do
    with_project({
      "Gemfile"                    => %(source "#{index_url}"\n\ngem "alpha", path: "vendor/alpha"\ngem "json_pure"\n),
      "vendor/alpha/alpha.gemspec" => funded_gemspec("alpha", "0.1.0", "https://example.com/fund/alpha"),
      "vendor/alpha/lib/alpha.rb"  => "",
      ".bundle/config"             => %(---\nBUNDLE_PATH: "vendor/bundle"\n),
    }) do |_dir|
      run_cli(["install"])
      code, stdout, _stderr = run_cli(["update", "--all"])
      code.should eq(0)
      stdout.should contain("Bundle updated!\n1 installed gem you directly depend on is looking for funding.")
    end
  end
end
