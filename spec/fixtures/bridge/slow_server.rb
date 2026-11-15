# Minimal JSON-RPC bridge stub used by spec/m7_bridge_long_operations_spec.cr.
#
# It answers every request like assets/bridge/server.rb does, but sleeps for
# CELERITE_SLOW_SERVER_SECONDS (default 1.2s) before replying to anything other
# than the construction handshake, so a client with a short RPC timeout
# reproduces the "bridge request timed out" failure that a slow native
# extension build used to trigger.
require "json"

$stdout.sync = true
sleep_seconds = (ENV["CELERITE_SLOW_SERVER_SECONDS"] || "1.2").to_f

while line = $stdin.gets
  request = JSON.parse(line)
  id = request["id"]
  op = request["op"].to_s

  # The client performs a handshake during construction, so keep the ready
  # reply fast while every other op is slowed down on purpose.
  sleep sleep_seconds unless op == "ping"

  result =
    case op
    when "ping" then { "version" => "stub" }
    when "build_extension" then { "ok" => true }
    else { "echo" => op }
    end

  reply = {
    "proto" => request["proto"],
    "id" => id,
    "ok" => true,
    "result" => result,
  }
  $stdout.puts JSON.generate(reply)
end
