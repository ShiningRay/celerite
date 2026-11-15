require "./spec_helper"

# Plain user environment: the CLI binary itself is the only "asset" present
# (no CELERITE_BRIDGE_SERVER / CELERITE_REFERENCE_BUNDLER_LIB hints). The CLI
# must still discover its bridge (next to the executable) and resolve groups.
# Regression: `list` gated group lookup on those env vars, so a real
# `--only-group development` failed with "`development` group could not be found."
private PLAIN_GROUP_INDEX = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def plain_group_bin : String?
  path = File.expand_path("../bin/celerite.exe", __DIR__)
  File.exists?(path) ? path : nil
end

private def plain_group_gemfile : String
  <<-GEMFILE
  source "#{PLAIN_GROUP_INDEX}"

  gem "json_pure"

  group :development do
    gem "thor"
  end
  GEMFILE
end

private def run_plain_cli(project : String, args : Array(String)) : {Int32, String, String}
  bin = plain_group_bin.not_nil!
  keys = ["CELERITE_BRIDGE_SERVER", "CELERITE_REFERENCE_BUNDLER_LIB", "HOME", "USERPROFILE", "BUNDLE_PATH"]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]? }
  ENV.delete("CELERITE_BRIDGE_SERVER")
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, ".bundle-test")
  output = IO::Memory.new
  errors = IO::Memory.new
  begin
    status = Process.run(bin, args, chdir: project, output: output, error: errors)
    {status.exit_code, output.to_s, errors.to_s}
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

describe "bundle list groups in a plain environment" do
  it "lists an only-group selection without bridge hint variables" do
    pending!("bin/celerite.exe is not built") unless plain_group_bin
    with_project({"Gemfile" => plain_group_gemfile}) do |project|
      install_status, install_out, install_err = run_plain_cli(project, ["install"])
      fail "install failed (#{install_status}): #{install_out} #{install_err}" unless install_status == 0

      status, output, errors = run_plain_cli(project, ["list", "--only-group", "development"])
      status.should eq(0)
      errors.should eq("")
      output.lines.should eq([
        "Gems included by the bundle:",
        "  * thor (1.3.2)",
        "Use `bundle info` to print more detailed information about a gem",
      ])
    end
  end

  it "still rejects an unknown group without bridge hint variables" do
    pending!("bin/celerite.exe is not built") unless plain_group_bin
    with_project({"Gemfile" => plain_group_gemfile}) do |project|
      install_status, _, _ = run_plain_cli(project, ["install"])
      pending!("build a bridge-less fixture environment") unless install_status == 0

      status, output, errors = run_plain_cli(project, ["list", "--only-group", "nope"])
      status.should eq(15)
      output.should eq("")
      errors.strip.should eq("`nope` group could not be found.")
    end
  end
end
