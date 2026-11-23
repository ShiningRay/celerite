require "./spec_helper"

# M8 / roadmap L161 slice S2 (task-227): `evaluate_batch` answers in one request
# what `evaluate_gemfile` plus a second op answer in two. The contract is
# equivalence, not novelty, so every assertion below is made against the old
# ops rather than against a literal:
#
# * without `include`, the result bytes must be the `evaluate_gemfile` result
#   bytes (`docs/roadmap-evidence/M8-batch-protocol.md` §6 S2);
# * with `include: ["gemspecs"]`, the tree must be the `evaluate_gemfile` +
#   `gemspec_paths` pair, warnings in the same order;
# * the counters must show one RPC instead of two.
#
# The fixture is offline: the bridge only evaluates the DSL, it never resolves.
private BATCH_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)

# Duplicate declarations produce the two warnings whose order the equality
# assertion covers (`bundler/lib/bundler/dsl.rb:307-323`); `gemspec` makes
# `gemspecs` non-empty (`dsl.rb:63-81`).
private BATCH_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gemspec

  gem "rake"
  gem "rake"
  gem "json"
  gem "json"
  GEMFILE

private BATCH_GEMSPEC = <<-RUBY
  Gem::Specification.new do |spec|
    spec.name = "batch_fixture"
    spec.version = "0.1.0"
    spec.summary = "evaluate_batch fixture"
    spec.authors = ["celerite"]
    spec.files = []
    spec.require_paths = ["lib"]
  end
  RUBY

# `.upstream-specs/` is machine-local (`.gitignore:8`), so a worktree does not
# carry it: the pinned reference Bundler lives in the checkout the worktree
# belongs to, which `git rev-parse --git-common-dir` names. Falling back to the
# machine's Bundler would silently describe a different release than the one in
# `docs/compat-matrix`, so this fails instead of guessing.
private def batch_reference_lib : String
  if value = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
    return value unless value.empty?
  end

  candidates = [] of String
  candidates << File.expand_path("../.upstream-specs/v4.0.24/bundler/lib", __DIR__)

  output = IO::Memory.new
  status = Process.run(
    "git",
    ["-C", __DIR__, "rev-parse", "--path-format=absolute", "--git-common-dir"],
    output: output,
    error: Process::Redirect::Close,
  )
  if status.success?
    common = output.to_s.strip
    unless common.empty?
      candidates << File.join(File.dirname(common), ".upstream-specs", "v4.0.24", "bundler", "lib")
    end
  end

  candidates.each do |candidate|
    return candidate if File.directory?(File.join(candidate, "bundler", "dsl.rb"))
  end

  raise "reference Bundler 4.0.24 not materialised; run script/upstream-specs"
end

# Runs the real bridge over a batch of request lines and returns the response
# lines, one per request, with their bytes intact: the byte-for-byte assertion
# below compares these strings, not re-serialized JSON.
private def batch_exchange(requests : Array(String)) : Array(String)
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(
    "ruby",
    [BATCH_SERVER_PATH],
    input: IO::Memory.new(requests.join('\n') + "\n"),
    output: output,
    error: errors,
  )
  status.success?.should be_true, "bridge failed: #{errors.to_s}"
  output.to_s.lines.reject(&.empty?)
end

# Envelope: {"proto":<echo>,"id":N,"ok":true,"result":{...}} (`server.rb:11-13`).
private BATCH_RESULT_MARK = %(,"ok":true,"result":)

private def batch_result_bytes(response : String) : String
  index = response.index(BATCH_RESULT_MARK)
  raise "unexpected bridge response: #{response}" if index.nil?
  start = index + BATCH_RESULT_MARK.size
  response[start, response.size - start - 1]
end

private def batch_request(id : Int32, op : String, gemfile : String, sections : Array(String)? = nil) : String
  payload = String.build do |io|
    io << %({"gemfile":)
    io << gemfile.to_json
    unless sections.nil?
      io << %(,"include":)
      io << sections.to_json
    end
    io << '}'
  end
  %({"proto":2,"id":#{id},"op":#{op.to_json},"payload":#{payload}})
end

# Creates the fixture and runs the block with the environment the bridge needs:
# the pinned reference Bundler plus a HOME/BUNDLE_PATH inside the temp project,
# so no developer configuration leaks into the evaluation.
private def with_batch_fixture(& : String ->) : Nil
  files = {
    "Gemfile"               => BATCH_GEMFILE,
    "batch_fixture.gemspec" => BATCH_GEMSPEC,
  }
  with_project(files) do |project|
    names = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE BUNDLE_FROZEN CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB]
    previous = {} of String => String?
    names.each { |name| previous[name] = ENV[name]? }

    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("BUNDLE_FROZEN")
    ENV["CELERITE_BRIDGE_SERVER"] = BATCH_SERVER_PATH
    ENV["CELERITE_REFERENCE_BUNDLER_LIB"] = batch_reference_lib
    begin
      yield File.join(project, "Gemfile")
    ensure
      previous.each do |name, value|
        if value
          ENV[name] = value
        else
          ENV.delete(name)
        end
      end
    end
  end
end

describe "M8 task-227 evaluate_batch" do
  it "returns the evaluate_gemfile bytes when include is absent" do
    pending! "ruby not available" unless ruby_available?
    with_batch_fixture do |gemfile|
      responses = batch_exchange([
        batch_request(1, "evaluate_gemfile", gemfile),
        batch_request(2, "evaluate_batch", gemfile),
      ])

      responses.each { |response| response.should contain(%("ok":true)) }
      # Same result bytes, key order included: the batch default is the old
      # answer, not a re-encoded look-alike.
      batch_result_bytes(responses[1]).should eq(batch_result_bytes(responses[0]))
    end
  end

  it "equals the evaluate_gemfile plus gemspec_paths pair when include is gemspecs" do
    pending! "ruby not available" unless ruby_available?
    with_batch_fixture do |gemfile|
      responses = batch_exchange([
        batch_request(1, "evaluate_gemfile", gemfile),
        batch_request(2, "gemspec_paths", gemfile),
        batch_request(3, "evaluate_batch", gemfile, ["gemspecs"]),
      ])

      evaluation = JSON.parse(responses[0])["result"]
      paths = JSON.parse(responses[1])["result"]
      batch = JSON.parse(responses[2])["result"]

      # Only appended: the old object survives byte for byte, then `gemspecs`.
      evaluation_bytes = batch_result_bytes(responses[0])
      batch_bytes = batch_result_bytes(responses[2])
      batch_bytes.starts_with?(evaluation_bytes[0, evaluation_bytes.size - 1]).should be_true
      batch_bytes.size.should be > evaluation_bytes.size

      batch.as_h.keys.each do |key|
        next if key == "gemspecs"
        batch[key].should eq(evaluation[key])
      end
      batch["gemspecs"].should eq(paths["gemspecs"])
      batch["warnings"].should eq(paths["warnings"])

      # The fixture raises two warnings, so the order assertion has teeth.
      warnings = batch["warnings"].as_a.map(&.as_s)
      warnings.size.should eq(2)
      warnings[0].should contain("rake")
      warnings[1].should contain("json")
      batch["warnings"].should eq(evaluation["warnings"])

      gemspecs = batch["gemspecs"].as_a.map(&.as_s)
      gemspecs.size.should eq(1)
      gemspecs.first.should end_with("batch_fixture.gemspec")
    end
  end

  it "costs one RPC where the two old ops cost two" do
    pending! "ruby not available" unless ruby_available?
    with_batch_fixture do |gemfile|
      previous_stats = ENV["CELERITE_BRIDGE_STATS"]?
      ENV["CELERITE_BRIDGE_STATS"] = "1"
      Celerite::Bridge::BridgeStats.begin_run
      Celerite::Bridge::EvaluationCache.begin_run
      client = Celerite::Bridge::Client.new(server_path: BATCH_SERVER_PATH)
      begin
        before = Celerite::Bridge::BridgeStats.rpc
        old = client.evaluate_gemfile(gemfile)
        paths = client.gemspec_paths(gemfile)
        pair = Celerite::Bridge::BridgeStats.rpc - before

        before = Celerite::Bridge::BridgeStats.rpc
        batch = client.evaluate_batch(gemfile, ["gemspecs"])
        single = Celerite::Bridge::BridgeStats.rpc - before

        pair.should eq(2)
        single.should eq(1)
        batch.evaluation.should eq(old)
        batch.gemspecs.should eq(paths)
      ensure
        client.close
        Celerite::Bridge::EvaluationCache.finish
        if previous_stats
          ENV["CELERITE_BRIDGE_STATS"] = previous_stats
        else
          ENV.delete("CELERITE_BRIDGE_STATS")
        end
      end
    end
  end
end
