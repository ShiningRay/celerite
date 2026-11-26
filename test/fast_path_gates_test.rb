#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
load File.expand_path("../script/fast-path-gates", __dir__)

$passed = 0
$failures = []

def assert(condition, message)
  raise message unless condition
end

def check(name)
  yield
  $passed += 1
  puts "ok - #{name}"
rescue StandardError => error
  $failures << [name, error]
  warn "not ok - #{name}: #{error.class}: #{error.message}"
end

check("stats parser accepts the exact four-counter line") do
  assert(FastPathGates.parse_stats("bridge: procs=0 rpc=0 req_bytes=0 resp_bytes=0\n") == [0, 0, 0, 0],
         "zero stats did not parse")
  assert(FastPathGates.parse_stats("bridge: procs=2 rpc=3 req_bytes=4 resp_bytes=5\r\n") == [2, 3, 4, 5],
         "CRLF stats did not parse")
end

check("stats parser fails closed for missing, duplicate, or malformed lines") do
  ["", "bridge: procs=0 rpc=0 req_bytes=0\n",
   "bridge: procs=0 rpc=0 req_bytes=0 resp_bytes=0\nbridge: procs=0 rpc=0 req_bytes=0 resp_bytes=0\n"].each do |stderr|
    begin
      FastPathGates.parse_stats(stderr)
    rescue FastPathGates::GateFailure
      next
    end
    raise "accepted invalid stats: #{stderr.inspect}"
  end
end

check("compatibility stderr removes only the stats line") do
  stderr = "warning: keep me\nbridge: procs=1 rpc=2 req_bytes=3 resp_bytes=4\nfast-path: text stays\n"
  assert(FastPathGates.strip_stats(stderr) == "warning: keep me\nfast-path: text stays\n",
         "strip_stats removed user stderr")
end

check("command construction selects native executable suffixes") do
  root = "C:/repo"
  assert(FastPathGates.default_binary(root, windows: true) == File.join(root, "bin", "celerite.exe"),
         "Windows default binary mismatch")
  assert(FastPathGates.default_binary(root, windows: false) == File.join(root, "bin", "celerite"),
         "Unix default binary mismatch")
  binary = File.join(root, "bin", "celerite.exe")
  assert(FastPathGates.command(binary, ["install", "--verbose"]) == [File.expand_path(binary), "install", "--verbose"],
         "argument array was not preserved")
end

check("file URLs and output normalization are path portable") do
  url = FastPathGates.file_source_url("C:\\Temp\\celerite index")
  assert(url == "file://C:/Temp/celerite%20index", "unexpected Windows file URL: #{url}")
  project = "C:\\Temp\\celerite project"
  text = "Writing lockfile to C:/Temp/celerite project/Gemfile.lock\nC:\\Temp\\celerite project\\bundle\n"
  assert(FastPathGates.normalize_output(text, project) ==
         "Writing lockfile to {PROJECT}/Gemfile.lock\n{PROJECT}/bundle\n", "path normalization mismatch")
end

check("environment fixes switches once and isolates Bundler state") do
  project = File.join(Dir.tmpdir, "celerite-gate-project")
  previous = ENV["BUNDLE_PATH"]
  begin
    ENV["BUNDLE_PATH"] = "polluted"
    env = FastPathGates.environment(project: project, root: File.join(Dir.tmpdir, "repo"), profile: "4.0.24",
      reference_lib: File.join(Dir.tmpdir, "bundler", "lib"), fast_path: true)
    assert(env["CELERITE_FAST_PATH"] == "1" && env["CELERITE_EVAL_CACHE"] == "1" &&
           env["CELERITE_BRIDGE_STATS"] == "1", "fast-path switches missing")
    assert(env["BUNDLE_PATH"] == File.join(project, "bundle"), "inherited BUNDLE_PATH leaked")
    assert(env["BUNDLE_USER_PLUGIN"] == File.join(project, "global-plugin"), "plugin root is not isolated")
    compat = FastPathGates.environment(project: project, root: File.join(Dir.tmpdir, "repo"), profile: "2.7.2",
      reference_lib: File.join(Dir.tmpdir, "bundler", "lib"), fast_path: false)
    assert(compat["CELERITE_FAST_PATH"] == "0" && compat["CELERITE_PROFILE_BUNDLER_VERSION"] == "2.7.2",
           "compatibility profile mismatch")
  ensure
    ENV["BUNDLE_PATH"] = previous
  end
end

check("stats-off control disables the product observer") do
  previous = ENV["CELERITE_GATE_FORCE_STATS_OFF"]
  begin
    ENV["CELERITE_GATE_FORCE_STATS_OFF"] = "1"
    env = FastPathGates.environment(project: Dir.tmpdir, root: Dir.tmpdir, profile: "4.0.24",
      reference_lib: File.join(Dir.tmpdir, "bundler", "lib"), fast_path: true)
    assert(env["CELERITE_BRIDGE_STATS"] == "0", "stats-off control did not reach the product")
  ensure
    ENV["CELERITE_GATE_FORCE_STATS_OFF"] = previous
  end
end

check("tree manifest ignores cache/log/temp but hashes installed content") do
  Dir.mktmpdir("celerite-gate-tree") do |project|
    installed = File.join(project, "bundle", "ruby", "4.0.0", "gems", "json_pure-2.6.0", "lib", "json_pure.rb")
    FileUtils.mkdir_p(File.dirname(installed))
    File.write(installed, "original\n")
    File.write(File.join(project, "Gemfile.lock"), "lock\n")
    noise = [File.join(project, ".celerite", "cache", "noise"), File.join(project, "tmp", "noise"),
             File.join(project, "log", "noise"), File.join(project, "vendor", "cache", "noise"),
             File.join(project, "bundle", "ruby", "4.0.0", "cache", "noise")]
    noise.each { |path| FileUtils.mkdir_p(File.dirname(path)); File.write(path, "ignored") }
    before = FastPathGates.tree_manifest(project)
    manifest = JSON.parse(before)
    assert(manifest.keys.none? { |key| key.match?(%r{\A(?:/|[A-Za-z]:/)}) },
      "tree manifest keys must be project-relative on Windows and Unix")
    noise.each { |path| File.write(path, "changed") }
    assert(FastPathGates.tree_manifest(project) == before, "excluded cache/log/temp changed the manifest")
    File.write(installed, "tampered\n")
    assert(FastPathGates.tree_manifest(project) != before, "installed content change was not detected")
  end
end

check("lock byte and comment mutations change raw bytes") do
  Dir.mktmpdir("celerite-gate-lock") do |project|
    path = File.join(project, "Gemfile.lock")
    File.binwrite(path, "GEM\n  specs:\n\nBUNDLED WITH\n   4.0.24\n")
    before = File.binread(path)
    FastPathGates.mutate_lock_bytes(project)
    assert(File.binread(path) != before, "byte mutation was a no-op")
    FastPathGates.mutate_lock_comment(project)
    assert(File.binread(path).include?("# task-275 lock comment tamper"), "comment mutation missing")
  end
end

check("plugin index mutation writes nonempty valid YAML") do
  Dir.mktmpdir("celerite-gate-plugin") do |project|
    FastPathGates.mutate_plugin_index(project)
    index = File.join(project, ".bundle", "plugin", "index")
    assert(File.size(index).positive?, "plugin index is empty")
    assert(File.read(index) == "---\nplugins: []\n", "plugin index shape mismatch")
  end
end

puts "fast_path_gates_test: #{$passed} checks, #{$failures.length} failures"
exit($failures.empty? ? 0 : 1)
