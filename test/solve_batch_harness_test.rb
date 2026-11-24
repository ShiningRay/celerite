#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../assets/bridge/solve_batch"
require_relative "../script/solve_batch_fixture"

TEST_ROOT = File.expand_path("..", __dir__)
HARNESS = File.join(TEST_ROOT, "bin", "solve_batch")
BRIDGE_SERVER = File.join(TEST_ROOT, "assets", "bridge", "server.rb")
FIXTURES = JSON.parse(File.read(File.join(TEST_ROOT, "fixtures", "solve_batch", "cases.json")))
$passed = 0
$failures = []

def assert(condition, message)
  raise message unless condition
end

def run_harness(raw, chdir: TEST_ROOT)
  Open3.capture3(RbConfig.ruby, HARNESS, stdin_data: raw, chdir: chdir)
end

def bridge_environment(overrides = {})
  bundler_entry = $LOADED_FEATURES.find {|path| path.end_with?("/bundler.rb") || path.end_with?("\\bundler.rb") }
  lib = File.dirname(bundler_entry)
  { "CELERITE_REFERENCE_BUNDLER_LIB" => lib }.merge(overrides)
end

def run_bridge(input, env: {}, server: BRIDGE_SERVER, chdir: TEST_ROOT)
  Open3.capture3(bridge_environment(env), RbConfig.ruby, server, stdin_data: input, chdir: chdir)
end

def bridge_request(id, op, payload, proto = 2)
  JSON.generate("proto" => proto, "id" => id, "op" => op, "payload" => payload)
end

def bridge_responses(stdout)
  stdout.lines.reject {|line| line.strip.empty? }.map {|line| JSON.parse(line) }
end

def refresh_closure!(request)
  candidates = request.fetch("candidates_by_source")
  request["candidate_closure"]["digest"] = Celerite::SolveBatch.candidate_digest(candidates)
  request["candidate_closure"]["candidate_count"] = candidates.values.sum(&:length)
  request["candidate_closure"]["name_count"] = candidates.values.flatten.map {|candidate| candidate["name"] }.uniq.length
end

def check(name)
  yield
  $passed += 1
  puts "ok - #{name}"
rescue StandardError => error
  $failures << [name, error]
  warn "not ok - #{name}: #{error.class}: #{error.message}"
end

check("pinned Bundler 4.0.24 is the real resolver oracle") do
  assert(Bundler::VERSION == "4.0.24", "expected Bundler 4.0.24, got #{Bundler::VERSION}")
  assert(Celerite::SolveBatch::SCHEMA == "celerite.solve_batch/3", "schema mismatch")
end

FIXTURES.fetch("cases").each do |fixture|
  check("fixture #{fixture.fetch('name')}") do
    response = Celerite::SolveBatch.call(seal(fixture.fetch("name")))
    result = response.fetch("result")
    failure = result["failure"]
    if fixture["expected_failure"]
      assert(!response["ok"], "expected #{fixture['expected_failure']}, got success")
      assert(failure && failure["category"] == fixture["expected_failure"], "expected #{fixture['expected_failure']}, got #{failure&.dig('category')}: #{failure&.dig('message')}")
    else
      assert(response["ok"], "unexpected failure: #{failure&.dig('category')}: #{failure&.dig('message')}")
      chosen = result.fetch("chosen").map do |spec|
        [spec["name"], spec["version"], spec["platform"]].join("/")
      end.sort
      assert(chosen == fixture.fetch("expected_chosen").sort, "expected #{fixture['expected_chosen'].inspect}, got #{chosen.inspect}")
    end
  end
end

check("stdout, stderr, exit and lockfile isolation for success") do
  raw = JSON.generate(seal("promotion_patch"))
  Dir.mktmpdir("celerite-t260") do |dir|
    lock = File.join(dir, "Gemfile.lock")
    File.write(lock, "GEM\n  specs:\n\nPLATFORMS\n  ruby\n")
    before = File.binread(lock)
    stdout, stderr, status = run_harness(raw, chdir: dir)
    assert(status.success?, "harness exited #{status.exitstatus}: #{stderr}")
    assert(stderr.empty?, "handled success wrote stderr: #{stderr.inspect}")
    assert(stdout.lines.length == 1, "expected one JSON line, got #{stdout.lines.length}")
    assert(JSON.parse(stdout).dig("ok"), "success envelope was not ok")
    assert(File.binread(lock) == before, "Gemfile.lock changed")
  end
end

check("categorized solver failure keeps exit zero and stderr empty") do
  stdout, stderr, status = run_harness(JSON.generate(seal("requirements_conflict")))
  body = JSON.parse(stdout)
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  assert(!body["ok"] && body.dig("result", "failure", "category") == "requirements_conflict", "wrong failure envelope")
end

check("strict schema rejects missing and unknown properties with exit 64") do
  missing = seal("promotion_patch")
  missing.delete("promotion")
  stdout, stderr, status = run_harness(JSON.generate(missing))
  assert(status.exitstatus == 64 && stderr.empty?, "missing field: status=#{status.exitstatus}, stderr=#{stderr.inspect}, stdout=#{stdout}")
  unknown = seal("promotion_patch")
  unknown["unexpected"] = true
  stdout, stderr, status = run_harness(JSON.generate(unknown))
  assert(status.exitstatus == 64 && stderr.empty?, "unknown field: status=#{status.exitstatus}, stderr=#{stderr.inspect}, stdout=#{stdout}")
end

check("deleting all root candidates fails even after resealing the digest") do
  request = seal("promotion_patch")
  request["candidates_by_source"]["default"].reject! {|candidate| candidate["name"] == "app" }
  refresh_closure!(request)
  response = Celerite::SolveBatch.call(request)
  assert(!response["ok"] && response.dig("result", "failure", "category") == "candidate_incomplete", response.to_json)
end

check("checksum mutation fails after resealing the candidate digest") do
  request = seal("checksum_bound_to_locked_candidate")
  candidate = request["candidates_by_source"]["default"].find {|item| item["name"] == "checked" }
  candidate["checksum"]["value"] = "b" * 64
  refresh_closure!(request)
  response = Celerite::SolveBatch.call(request)
  assert(!response["ok"] && response.dig("result", "failure", "category") == "checksum_invalid", response.to_json)
end

check("source identity mutation is rejected") do
  request = seal("promotion_patch")
  request["evaluation"]["sources"].first["identity_sha256"] = "0" * 64
  response = Celerite::SolveBatch.call(request)
  assert(!response["ok"] && response.dig("result", "failure", "category") == "source_unsupported", response.to_json)
end

check("credential-bearing URI is rejected before resolver") do
  request = seal("promotion_patch")
  request["evaluation"]["sources"].first["remotes"] = ["https://user:pass@example.invalid/"]
  response = Celerite::SolveBatch.call(request)
  assert(!response["ok"] && response.dig("result", "failure", "category") == "source_unsupported", response.to_json)
end

check("NUL-bearing Ruby metadata names classify as ruby_incompatible") do
  message = "Ruby\0 requires Ruby >= 9.0"
  assert(Celerite::SolveBatch.classify_resolver_error(message) == "ruby_incompatible", message)
end

check("oversized failure details return a bounded JSON envelope") do
  message = ("\xFF".b * 20_000).force_encoding(Encoding::UTF_8) + ("界" * 10_000)
  response = Celerite::SolveBatch.failure_response(Celerite::SolveBatch::Error.new("internal", message), {})
  assert(JSON.generate(response).bytesize <= Celerite::SolveBatch::MAX_RESPONSE_BYTES, "failure envelope exceeded limit")
  bounded = response.dig("result", "failure", "message")
  assert(bounded.valid_encoding? && bounded.bytesize <= 16_384 && bounded.end_with?("…"), "failure message exceeded 16 KiB or was not valid UTF-8")
end

check("request timeout covers semantic validation, not only the resolver") do
  request = seal("promotion_patch")
  request["limits"]["timeout_ms"] = 1
  original = Celerite::SolveBatch.method(:validate_semantics!)
  Celerite::SolveBatch.define_singleton_method(:validate_semantics!) do |value|
    sleep 0.05
    original.call(value)
  end
  response = Celerite::SolveBatch.call(request)
  assert(!response["ok"] && response.dig("result", "failure", "category") == "timeout", response.to_json)
ensure
  Celerite::SolveBatch.define_singleton_method(:validate_semantics!) {|value| original.call(value) } if original
end

check("bridge advertises solve_batch and echoes protocol 1 and 2") do
  input = [bridge_request(1, "ping", {}, 1), bridge_request(2, "ping", {}, 2)].join("\n") + "\n"
  stdout, stderr, status = run_bridge(input)
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  responses = bridge_responses(stdout)
  assert(responses.length == 2, "expected two responses, got #{responses.length}")
  responses.zip([1, 2]).each do |response, proto|
    assert(response["proto"] == proto && response["ok"], response.to_json)
    assert(response.dig("result", "features").include?("solve_batch"), response.to_json)
  end
end

check("bridge dispatches solve_batch under protocol 1 and 2 with nested S1 envelopes") do
  request = seal("promotion_patch")
  input = [bridge_request(3, "solve_batch", request, 1), bridge_request(4, "solve_batch", request, 2)].join("\n") + "\n"
  stdout, stderr, status = run_bridge(input)
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  responses = bridge_responses(stdout)
  assert(responses.length == 2, "expected two responses, got #{responses.length}")
  responses.zip([1, 2]).each do |response, proto|
    assert(response["ok"] && response["proto"] == proto, response.to_json)
    solver = response.fetch("result")
    assert(solver["schema"] == "celerite.solve_batch/3" && solver["ok"], response.to_json)
    assert(solver.dig("result", "chosen").any? {|spec| spec["name"] == "app" }, response.to_json)
  end
end

check("bridge keeps categorized solver failure inside a successful dispatch envelope") do
  stdout, stderr, status = run_bridge(bridge_request(5, "solve_batch", seal("requirements_conflict")) + "\n")
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  response = bridge_responses(stdout).fetch(0)
  assert(response["ok"], response.to_json)
  assert(!response.dig("result", "ok") && response.dig("result", "result", "failure", "category") == "requirements_conflict", response.to_json)
end

check("bridge rejects non-object and schema-invalid payloads without escaping") do
  invalid = seal("promotion_patch")
  invalid.delete("promotion")
  input = [
    bridge_request(6, "solve_batch", []),
    bridge_request(7, "solve_batch", invalid),
    bridge_request(8, "ping", {})
  ].join("\n") + "\n"
  stdout, stderr, status = run_bridge(input)
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  responses = bridge_responses(stdout)
  assert(responses.length == 3 && responses.all? {|response| response["ok"] }, stdout)
  assert(responses[0].dig("result", "result", "failure", "class") == "schema_invalid", responses[0].to_json)
  assert(responses[1].dig("result", "result", "failure", "class") == "schema_invalid", responses[1].to_json)
  assert(responses[2].dig("result", "features").include?("solve_batch"), responses[2].to_json)
end

check("bridge drains an oversized request line and serves the next request") do
  input = ("x" * 2048) + "\n" + bridge_request(9, "ping", {}) + "\n"
  stdout, stderr, status = run_bridge(input, env: { "CELERITE_SOLVE_BATCH_MAX_LINE_BYTES" => "1024" })
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  responses = bridge_responses(stdout)
  assert(responses.length == 2, stdout)
  assert(!responses[0]["ok"] && responses[0].dig("error", "class") == "BatchTooLarge", responses[0].to_json)
  assert(responses[1]["ok"] && responses[1]["id"] == 9, responses[1].to_json)
end

check("bridge reports invalid JSON and continues serving requests") do
  input = "{\n" + bridge_request(10, "ping", {}) + "\n"
  stdout, stderr, status = run_bridge(input)
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  responses = bridge_responses(stdout)
  assert(responses.length == 2, stdout)
  assert(!responses[0]["ok"] && responses[0].dig("error", "class") == "JSONParseError", responses[0].to_json)
  assert(responses[1]["ok"] && responses[1]["id"] == 10, responses[1].to_json)
end

check("bridge bounds an oversized solve_batch response and continues") do
  [1024, 320].each do |limit|
    input = bridge_request(11, "solve_batch", seal("platform_variant")) + "\n" + bridge_request(12, "ping", {}) + "\n"
    stdout, stderr, status = run_bridge(input, env: { "CELERITE_SOLVE_BATCH_MAX_RESPONSE_BYTES" => limit.to_s })
    assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
    lines = stdout.lines.reject {|line| line.strip.empty? }
    assert(lines.length == 2 && lines.all? {|line| line.bytesize <= limit }, stdout)
    responses = lines.map {|line| JSON.parse(line) }
    solver = responses[0].dig("result")
    assert(responses[0]["ok"] && solver["schema"] == "celerite.solve_batch/3" && !solver["ok"] && solver.dig("result", "failure", "class") == "response_too_large", responses[0].to_json)
    assert(responses[1]["ok"] && responses[1]["id"] == 12, responses[1].to_json)
  end
end

check("bridge rejects unsupported protocol and invalid request identifiers") do
  input = [
    bridge_request(13, "ping", {}, 3),
    bridge_request(2_147_483_648, "ping", {}),
    "[]\n",
    bridge_request(15, "界" * 10_000, {}),
    bridge_request(14, "ping", {})
  ].join("\n") + "\n"
  stdout, stderr, status = run_bridge(input)
  assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
  responses = bridge_responses(stdout)
  assert(responses.length == 5, stdout)
  assert(responses[0].dig("error", "class") == "ProtocolError" && responses[0]["proto"] == 2, responses[0].to_json)
  assert(responses[1].dig("error", "class") == "InvalidRequest" && responses[1]["id"].nil?, responses[1].to_json)
  assert(responses[2].dig("error", "class") == "InvalidRequest", responses[2].to_json)
  message = responses[3].dig("error", "message")
  assert(responses[3].dig("error", "class") == "UnknownOp", responses[3].to_json)
  assert(message.valid_encoding? && message.bytesize <= 16_384 && message.end_with?("…"), "bridge error message exceeded 16 KiB or was not valid UTF-8")
  assert(responses[4]["ok"] && responses[4]["id"] == 14, responses[4].to_json)
end

check("evaluate_batch default result remains byte-compatible with evaluate_gemfile") do
  Dir.mktmpdir("celerite-t263-gemfile") do |dir|
    gemfile = File.join(dir, "Gemfile")
    File.write(gemfile, "source \"https://example.invalid\"\ngem \"rack\"\n")
    input = [
      bridge_request(15, "evaluate_gemfile", { "gemfile" => gemfile }),
      bridge_request(16, "evaluate_batch", { "gemfile" => gemfile })
    ].join("\n") + "\n"
    stdout, stderr, status = run_bridge(input, chdir: dir)
    assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
    responses = bridge_responses(stdout)
    assert(responses.length == 2 && responses.all? {|response| response["ok"] }, stdout)
    assert(JSON.generate(responses[0]["result"]) == JSON.generate(responses[1]["result"]), "evaluate_batch changed the default result")
  end
end

check("base 95e19a0 rejects solve_batch as UnknownOp") do
  source, stderr, status = Open3.capture3("git", "show", "95e19a0:assets/bridge/server.rb", chdir: TEST_ROOT)
  assert(status.success?, "git show failed: #{stderr}")
  Dir.mktmpdir("celerite-t263-base") do |dir|
    server = File.join(dir, "server.rb")
    File.write(server, source)
    stdout, stderr, status = run_bridge(bridge_request(17, "solve_batch", seal("promotion_patch")) + "\n", server: server, chdir: dir)
    assert(status.success? && stderr.empty?, "status=#{status.exitstatus}, stderr=#{stderr.inspect}")
    response = bridge_responses(stdout).fetch(0)
    assert(!response["ok"] && response.dig("error", "class") == "UnknownOp", response.to_json)
  end
end

puts "#{$passed} checks, #{$failures.length} failures"
exit($failures.empty? ? 0 : 1)
