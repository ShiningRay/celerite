require "./spec_helper"

# `install` against a port that is guaranteed to refuse connections must mirror
# bundler's NetworkDownError: `Could not reach host <host[:port]>. Check your
# network connection and try again.` with exit code 17 (HTTPError) and no
# "celerite internal error" wrapper.
private def with_network_down_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

# Bind and immediately close to get a port with no listener: connecting to it
# is refused deterministically on every platform (no reliance on port 9 being
# filtered or on DNS).
private def network_down_closed_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

describe "M7(4) network down" do
  it "reports the reference NetworkDownError and exits 17" do
    with_network_down_bridge do
      port = network_down_closed_port
      gemfile = "source \"http://127.0.0.1:#{port}/\"\n\ngem \"thor\"\n"
      with_project({"Gemfile" => gemfile}) do
        # The suite runs with a fixed 80-column wrapper; widen the terminal so
        # the assertion can compare the exact reference sentence even when the
        # random port makes it exceed 80 columns.
        previous_columns = ENV["THOR_COLUMNS"]?
        ENV["THOR_COLUMNS"] = "200"
        begin
          code, out, err = run_cli(["install"])
        ensure
          if previous_columns
            ENV["THOR_COLUMNS"] = previous_columns
          else
            ENV.delete("THOR_COLUMNS")
          end
        end
        code.should eq(17)
        # Bundler renders "Fetching gem metadata from ..." as a Thor progress
        # bar, which writes nothing when stdout is not a TTY; the differential
        # fixture network-unreachable shows reference stdout empty. Celerite
        # matches that (the progress bar is TTY-gated in Resolution#log_fetch_for).
        out.should be_empty
        err.chomp.should eq(
          "Could not reach host 127.0.0.1:#{port}. Check your network connection and try again."
        )
        err.should_not contain("celerite internal error")
      end
    end
  end
end
