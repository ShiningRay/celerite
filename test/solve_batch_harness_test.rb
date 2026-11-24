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
FIXTURES = JSON.parse(File.read(File.join(TEST_ROOT, "fixtures", "solve_batch", "cases.json")))
$passed = 0
$failures = []

def assert(condition, message)
  raise message unless condition
end

def run_harness(raw, chdir: TEST_ROOT)
  Open3.capture3(RbConfig.ruby, HARNESS, stdin_data: raw, chdir: chdir)
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
  response = Celerite::SolveBatch.failure_response(Celerite::SolveBatch::Error.new("internal", "x" * (9 * 1024 * 1024)), {})
  assert(JSON.generate(response).bytesize <= Celerite::SolveBatch::MAX_RESPONSE_BYTES, "failure envelope exceeded limit")
  assert(response.dig("result", "failure", "message").bytesize < 20_000, "failure message was not truncated")
end

puts "#{$passed} checks, #{$failures.length} failures"
exit($failures.empty? ? 0 : 1)
