require "./spec_helper"
require "../src/celerite/bridge/client"

# M7(9) rails-scale unblocking: a native extension build can take minutes, so
# the bridge must not apply its 30s metadata deadline to it. The reference has
# no RPC deadline at all (Ruby runs the build in-process), which is why
# `bigdecimal`, `nokogiri` & friends must be allowed to finish.
#
# The stub bridge (spec/fixtures/bridge/slow_server.rb) answers every request
# after 1.2s; a client configured with a 0.2s deadline reproduces the old bug
# verbatim: "bridge request timed out after 0.2s".
private def slow_bridge_server : String
  File.expand_path("fixtures/bridge/slow_server.rb", __DIR__)
end

private def with_slow_client(timeout : Time::Span, & : Celerite::Bridge::Client ->) : Nil
  previous = ENV["CELERITE_SLOW_SERVER_SECONDS"]?
  ENV["CELERITE_SLOW_SERVER_SECONDS"] = "1.2"
  client = Celerite::Bridge::Client.new(server_path: slow_bridge_server, timeout: timeout)
  begin
    yield client
  ensure
    client.close
    if previous
      ENV["CELERITE_SLOW_SERVER_SECONDS"] = previous
    else
      ENV.delete("CELERITE_SLOW_SERVER_SECONDS")
    end
  end
end

describe "M7(9) bridge deadlines for long operations" do
  it "lets a native extension build outlive the metadata deadline" do
    with_slow_client(0.2.seconds) do |client|
      # 1.2s of work with a 0.2s metadata deadline: this used to raise
      # BridgeError("Timeout").
      result = client.build_extension(
        gem_dir: "/tmp/gem",
        destination: "/tmp/dest",
        name: "bigdecimal",
        gem_path: "/tmp/bigdecimal-4.1.3.gem",
      )
      result["ok"].as_bool.should be_true
    end
  end

  it "keeps the metadata deadline for fast calls (negative control)" do
    with_slow_client(0.2.seconds) do |client|
      error = expect_raises(Celerite::Bridge::BridgeError) do
        client.write_installed_spec("/tmp/gem", "/tmp/dest", "/tmp/gemdir")
      end
      error.message.not_nil!.should contain("bridge request timed out after 0.2s")
    end
  end
end
