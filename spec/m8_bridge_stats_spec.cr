require "./spec_helper"

# M8 baseline counters: `CELERITE_BRIDGE_STATS` must be off by default and,
# when on, print exactly one stable line on stderr at the CLI exit point —
# even for commands that never start a bridge (all zeroes).
private GEM_INDEX_URL = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private STATS_LINE = /^bridge: procs=(\d+) rpc=(\d+) req_bytes=(\d+) resp_bytes=(\d+)$/

private def bridge_stats_gemfile : String
  <<-GEMFILE
  source "#{GEM_INDEX_URL}"

  gem "json_pure"
  GEMFILE
end

private def with_bridge_stats(value : String?, &)
  previous_stats = ENV["CELERITE_BRIDGE_STATS"]?
  previous_server = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  if value
    ENV["CELERITE_BRIDGE_STATS"] = value
  else
    ENV.delete("CELERITE_BRIDGE_STATS")
  end
  begin
    yield
  ensure
    if previous_stats
      ENV["CELERITE_BRIDGE_STATS"] = previous_stats
    else
      ENV.delete("CELERITE_BRIDGE_STATS")
    end
    if previous_server
      ENV["CELERITE_BRIDGE_SERVER"] = previous_server
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def with_bridge_stats_project(project : String, &)
  previous = {
    "HOME"        => ENV["HOME"]?,
    "USERPROFILE" => ENV["USERPROFILE"]?,
    "BUNDLE_PATH" => ENV["BUNDLE_PATH"]?,
  }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, ".bundle-test")
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

private def stats_lines(errors : String) : Array(String)
  errors.lines.select(&.starts_with?("bridge: procs="))
end

describe "CELERITE_BRIDGE_STATS" do
  it "stays silent when the switch is unset or exactly \"0\"" do
    with_project({"Gemfile" => bridge_stats_gemfile}) do |project|
      with_bridge_stats_project(project) do
        with_bridge_stats(nil) do
          status, _output, errors = run_cli(["lock"])
          status.should eq(0)
          errors.should_not contain("bridge: procs=")
        end
        with_bridge_stats("0") do
          status, _output, errors = run_cli(["lock"])
          status.should eq(0)
          errors.should_not contain("bridge: procs=")
        end
      end
    end
  end

  it "prints exactly one well-formed line with the bridge counters" do
    with_project({"Gemfile" => bridge_stats_gemfile}) do |project|
      with_bridge_stats_project(project) do
        with_bridge_stats("1") do
          status, _output, errors = run_cli(["lock"])
          status.should eq(0)
          lines = stats_lines(errors)
          lines.size.should eq(1)
          match = lines.first.match(STATS_LINE).not_nil!
          match[1].to_i.should be >= 1
          match[2].to_i.should be >= 1
          match[3].to_i.should be > 0
          match[4].to_i.should be > 0
        end
      end
    end
  end

  it "prints an all-zero line for a command that never starts a bridge" do
    with_bridge_stats("1") do
      status, output, errors = run_cli(["--version"])
      status.should eq(0)
      output.strip.should eq(Celerite::Profile.bundler_version)
      stats_lines(errors).should eq(
        ["bridge: procs=0 rpc=0 req_bytes=0 resp_bytes=0"]
      )
    end
  end
end
