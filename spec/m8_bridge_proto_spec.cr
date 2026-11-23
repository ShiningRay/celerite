require "./spec_helper"
require "../src/celerite"

# M8 / roadmap L161 slice S1: the bridge envelope is a public protocol
# boundary. These specs drive `assets/bridge/server.rb` over raw JSON Lines (no
# Crystal client in the way) and pin the version range, the echoed `proto`, and
# the `ping.features` capability list. S1 changes no command semantics: the
# last two examples hold the exit code and `Gemfile.lock` bytes fixed when the
# server copy predates the capability list.
private BRIDGE_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)
private BRIDGE_INDEX_URL   = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

# One process for the whole batch: every request is queued on stdin, the server
# answers them in order and exits on EOF. Responses keep their arrival order.
private def bridge_exchange(requests : Array(String)) : Array(JSON::Any)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run("ruby", [BRIDGE_SERVER_PATH],
    input: IO::Memory.new(requests.join('\n') + "\n"),
    output: output,
    error: error)
  status.success?.should be_true
  output.to_s.lines.reject(&.empty?).map { |line| JSON.parse(line) }
end

private def bridge_request(proto : Int32, id : Int32, op : String) : String
  %({"proto":#{proto},"id":#{id},"op":"#{op}","payload":{}})
end

private def with_bridge_server(path : String, &)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = path
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
    Celerite::Bridge::Client.shutdown
  end
end

# The isolated HOME/BUNDLE_PATH geometry the other bridge specs use, so a
# `lock` run never reads or writes the developer's own bundle directory.
private def with_isolated_bundle_home(project : String, &)
  keys = {"HOME", "USERPROFILE", "BUNDLE_PATH"}
  saved = {} of String => String
  keys.each { |key| saved[key] = ENV[key] if ENV[key]? }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, ".bundle-test")
  begin
    yield
  ensure
    keys.each { |key| ENV.delete(key) }
    saved.each { |key, value| ENV[key] = value }
  end
end

# A copy of the server as an older release would have shipped it: same version
# range and ops, no `features` key in the `ping` result. The guard below fails
# loudly if the source no longer contains the exact string this strips, so the
# copy can never silently become a verbatim copy of the current server.
private def legacy_server_copy(dir : String) : String
  source = File.read(BRIDGE_SERVER_PATH)
  stripped = source.gsub(/,\s*"features"\s*=>\s*BRIDGE_FEATURES/, "")
  stripped.should_not eq(source)
  path = File.join(dir, "server_without_features.rb")
  File.write(path, stripped)
  path
end

describe "bridge protocol version range" do
  it "answers a proto 1 request with proto 1" do
    pending! "ruby not available" unless ruby_available?
    response = bridge_exchange([bridge_request(1, 1, "ping")]).first
    response["proto"].as_i.should eq(1)
    response["id"].as_i.should eq(1)
    response["ok"].as_bool.should be_true
    response["result"]["ruby"].as_s.should match(/\d+\.\d+\.\d+/)
  end

  it "answers a proto 2 request with proto 2" do
    pending! "ruby not available" unless ruby_available?
    response = bridge_exchange([bridge_request(2, 2, "ping")]).first
    response["proto"].as_i.should eq(2)
    response["id"].as_i.should eq(2)
    response["ok"].as_bool.should be_true
  end

  it "rejects versions outside 1..2 with ProtocolError and the unchanged message" do
    pending! "ruby not available" unless ruby_available?
    responses = bridge_exchange([
      bridge_request(3, 3, "ping"),
      bridge_request(0, 4, "ping"),
    ])
    responses.each do |response|
      response["ok"].as_bool.should be_false
      response["error"]["class"].as_s.should eq("ProtocolError")
    end
    responses[0]["error"]["message"].as_s.should eq("unsupported proto 3")
    responses[1]["error"]["message"].as_s.should eq("unsupported proto 0")
    # An unsupported request version cannot be echoed as-is: the rejection
    # speaks the highest version the server understands.
    responses.each { |response| response["proto"].as_i.should eq(2) }
  end

  it "echoes the request version on error envelopes too" do
    pending! "ruby not available" unless ruby_available?
    response = bridge_exchange([bridge_request(1, 5, "no_such_op")]).first
    response["proto"].as_i.should eq(1)
    response["ok"].as_bool.should be_false
    response["error"]["class"].as_s.should eq("UnknownOp")
  end

  it "advertises the capabilities this server can actually serve" do
    pending! "ruby not available" unless ruby_available?
    response = bridge_exchange([bridge_request(2, 6, "ping")]).first
    features = response["result"]["features"].as_a.map(&.as_s)
    features.should contain("evaluate_gemfile")
    features.should contain("gemspec_paths")
    features.should contain("plugin_gemfile_eval")
    # `evaluate_batch` is roadmap L161 slice S2: the op exists now, so the
    # advertisement names it. Advertising an op that does not exist would turn
    # a feature probe into `UnknownOp`, so this line and `BRIDGE_FEATURES` move
    # together.
    features.should contain("evaluate_batch")
  end

  it "treats a response without features as an empty capability set" do
    ping = Celerite::Bridge::Ping.from_json(JSON.parse(%({"ruby":"4.0.6","proto":1})))
    ping.ruby.should eq("4.0.6")
    ping.features.should be_empty

    # Malformed entries degrade per entry instead of failing the handshake.
    partial = Celerite::Bridge::Ping.from_json(JSON.parse(%({"ruby":"4.0.6","features":["evaluate_gemfile",7]})))
    partial.features.should eq(["evaluate_gemfile"])
  end

  it "pings a server copy that predates the capability list" do
    pending! "ruby not available" unless ruby_available?
    with_project({} of String => String) do |dir|
      legacy = legacy_server_copy(dir)
      client = Celerite::Bridge::Client.new(server_path: legacy)
      begin
        ping = client.ping
        ping.ruby.should match(/\d+\.\d+\.\d+/)
        ping.features.should be_empty
      ensure
        client.close
      end
    end
  end

  it "keeps lock output and the exit code when the server lacks features" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => %(source "#{BRIDGE_INDEX_URL}"\n\ngem "json_pure"\n)}) do |project|
      with_isolated_bundle_home(project) do
        lockfile = File.join(project, "Gemfile.lock")
        current_lock = ""

        with_bridge_server(BRIDGE_SERVER_PATH) do
          status, _output, _errors = run_cli(["lock"])
          status.should eq(0)
          current_lock = File.read(lockfile)
        end

        legacy = legacy_server_copy(project)
        with_bridge_server(legacy) do
          status, _output, _errors = run_cli(["lock"])
          status.should eq(0)
          File.read(lockfile).should eq(current_lock)
        end
      end
    end
  end
end
