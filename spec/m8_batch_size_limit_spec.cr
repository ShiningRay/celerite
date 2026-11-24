require "./spec_helper"

# M8 / roadmap L163 (task-243): the batch protocol's own size bounds.
#
# The reference Bundler has no batch concept (`git grep batch` over
# `bundler-4.0.24/lib` finds nothing), so there is no reference output to match
# here: the oracle is that nothing observable changes for the requests that
# exist today (two sections, far below both bounds), plus the documented
# contract that an over-limit request is refused with a structured error rather
# than truncated, sharded, or half-answered. See
# `docs/roadmap-evidence/M8-fast-path-plan.md` §1.3 (A + bounded B) and
# `docs/compat-evidence/2026-11-23.md` task-243.
private BATCH_LIMIT_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)

private BATCH_LIMIT_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gemspec

  gem "rake"
  GEMFILE

private BATCH_LIMIT_GEMSPEC = <<-RUBY
  Gem::Specification.new do |spec|
    spec.name = "batch_limit_fixture"
    spec.version = "0.1.0"
    spec.summary = "batch size limit fixture"
    spec.authors = ["celerite"]
    spec.files = []
    spec.require_paths = ["lib"]
  end
  RUBY

# Same resolution as `spec/m8_batch_eval_spec.cr`: `.upstream-specs/` is
# machine-local, so the pinned reference Bundler is looked up in the checkout
# this worktree belongs to rather than in the worktree itself.
private def batch_limit_reference_lib : String
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
    return candidate if File.file?(File.join(candidate, "bundler", "dsl.rb"))
  end

  raise "reference Bundler 4.0.24 not materialised; run script/upstream-specs"
end

private def batch_limit_request(id : Int32, gemfile : String, sections : Array(String)) : String
  payload = %({"gemfile":#{gemfile.to_json},"include":#{sections.to_json}})
  %({"proto":2,"id":#{id},"op":"evaluate_batch","payload":#{payload}})
end

# One real bridge process, several request lines in, one response line out per
# request (the stream is line-oriented, so extra lines prove nothing was
# truncated or dropped).
private def batch_limit_exchange(requests : Array(String)) : Array(String)
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(
    "ruby",
    [BATCH_LIMIT_SERVER_PATH],
    input: IO::Memory.new(requests.join('\n') + "\n"),
    output: output,
    error: errors,
  )
  status.success?.should be_true, "bridge failed: #{errors.to_s}"
  output.to_s.lines.reject(&.empty?)
end

private def with_batch_limit_env(project : String, extra : Hash(String, String?), &) : Nil
  names = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE BUNDLE_FROZEN CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB CELERITE_BATCH_MAX_BYTES]
  previous = {} of String => String?
  names.each { |name| previous[name] = ENV[name]? }

  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV.delete("BUNDLE_GEMFILE")
  ENV.delete("BUNDLE_FROZEN")
  ENV["CELERITE_BRIDGE_SERVER"] = BATCH_LIMIT_SERVER_PATH
  ENV["CELERITE_REFERENCE_BUNDLER_LIB"] = batch_limit_reference_lib
  ENV.delete("CELERITE_BATCH_MAX_BYTES")
  extra.each do |name, value|
    if value.nil?
      ENV.delete(name)
    else
      ENV[name] = value
    end
  end
  begin
    yield
  ensure
    previous.each do |name, value|
      if value.nil?
        ENV.delete(name)
      else
        ENV[name] = value
      end
    end
  end
end

private def with_batch_limit_fixture(extra : Hash(String, String?), & : {String, String} ->) : Nil
  files = {
    "Gemfile"                     => BATCH_LIMIT_GEMFILE,
    "batch_limit_fixture.gemspec" => BATCH_LIMIT_GEMSPEC,
  }
  with_project(files) do |project|
    with_batch_limit_env(project, extra) do
      yield({project, File.join(project, "Gemfile")})
    end
  end
end

describe "M8 task-243 batch size limits" do
  # `BridgeStats` counts only while `CELERITE_BRIDGE_STATS` is on, and the
  # counters are process-global (another spec's client would otherwise leak in).
  before_each do
    ENV["CELERITE_BRIDGE_STATS"] = "1"
    Celerite::Bridge::BridgeStats.begin_run
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_STATS")
  end

  it "refuses more than four include sections before any bridge is spawned" do
    Celerite::Bridge::BridgeStats.begin_run
    Celerite::Bridge::BridgeStats.procs.should eq(0)

    error = expect_raises(Celerite::Bridge::BatchTooLargeError) do
      Celerite::Bridge.validate_batch_sections!(%w[fingerprint gemspecs plugins a b])
    end
    error.error_class.should eq("BatchTooLarge")
    error.message.to_s.should contain("5 sections")
    error.message.to_s.should contain("limit is 4")
    # The pre-flight gate is the only path that can keep the promise "no bridge
    # for an over-limit request": Client#initialize spawns eagerly, so a caller
    # that must not spawn validates here first.
    Celerite::Bridge::BridgeStats.procs.should eq(0)

    # The boundary itself is legal: four sections are accepted, so the gate is
    # not off by one against MAX_INCLUDE_SECTIONS.
    Celerite::Bridge.validate_batch_sections!(%w[fingerprint gemspecs plugins a])
    Celerite::Bridge::MAX_INCLUDE_SECTIONS.should eq(4)
  end

  it "refuses an over-limit request on Client#evaluate_batch without an RPC" do
    pending! "ruby not available" unless ruby_available?

    with_batch_limit_fixture({} of String => String?) do |project, gemfile|
      Celerite::Bridge::BridgeStats.begin_run
      client = Celerite::Bridge::Client.new(server_path: BATCH_LIMIT_SERVER_PATH)
      begin
        # The constructor spawns the bridge (`client.cr:830-846`); the limit is
        # enforced inside `evaluate_batch` before the cache or any RPC, so the
        # process exists but is never asked anything.
        Celerite::Bridge::BridgeStats.procs.should eq(1)
        error = expect_raises(Celerite::Bridge::BatchTooLargeError) do
          client.evaluate_batch(gemfile, %w[fingerprint gemspecs plugins a b])
        end
        error.error_class.should eq("BatchTooLarge")
        error.message.to_s.should contain("5 sections")
        error.message.to_s.should contain("limit is 4")
        Celerite::Bridge::BridgeStats.rpc.should eq(0)
        # A refused request must not evaluate the Gemfile either: no lock file,
        # no bundle directory, nothing written under the project.
        Dir.children(project).sort.should eq(["Gemfile", "batch_limit_fixture.gemspec"])
      ensure
        client.close
      end
    end
  end

  it "answers a two-section request exactly as before, far below the byte cap" do
    pending! "ruby not available" unless ruby_available?

    with_batch_limit_fixture({} of String => String?) do |project, gemfile|
      responses = batch_limit_exchange([
        batch_limit_request(1, gemfile, %w[fingerprint gemspecs]),
      ])
      responses.size.should eq(1)
      responses[0].should contain(%("ok":true))
      parsed = JSON.parse(responses[0])
      result = parsed["result"]
      result["gemspecs"].as_a.size.should eq(1)
      result["gemspecs"].as_a[0].as_s.should end_with("batch_limit_fixture.gemspec")
      result["fingerprint"]["digest"].as_s.size.should eq(64)
      # The cap is a ceiling, not a target: the existing two-section answer is
      # two orders of magnitude smaller, which is why no current command can
      # reach it.
      responses[0].bytesize.should be < Celerite::Bridge::MAX_BATCH_RESPONSE_BYTES
      responses[0].bytesize.should be < 64 * 1024
    end
  end

  it "rejects five sections on the server with a structured error and stays usable" do
    pending! "ruby not available" unless ruby_available?

    with_batch_limit_fixture({} of String => String?) do |project, gemfile|
      responses = batch_limit_exchange([
        batch_limit_request(1, gemfile, %w[fingerprint gemspecs plugins a b]),
        batch_limit_request(2, gemfile, %w[fingerprint gemspecs]),
      ])
      # One line per request: the refusal replaces the answer instead of being
      # appended to a truncated one, and the next request is served normally.
      responses.size.should eq(2)
      rejected = JSON.parse(responses[0])
      rejected["ok"].as_bool.should be_false
      rejected["error"]["class"].as_s.should eq("BatchTooLarge")
      rejected["error"]["message"].as_s.should contain("5 sections")
      rejected["error"]["message"].as_s.should contain("limit is 4")
      rejected.as_h.has_key?("result").should be_false

      accepted = JSON.parse(responses[1])
      accepted["ok"].as_bool.should be_true
      accepted["result"]["gemspecs"].as_a.size.should eq(1)
    end
  end

  it "rejects an oversized response on the server, and the client turns it into BatchTooLargeError" do
    pending! "ruby not available" unless ruby_available?

    # Server side: the injected limit is smaller than any real answer, so the
    # rejection path is reachable without a multi-megabyte fixture. Both peers
    # read the same variable, but the server reads it at boot — see the client
    # case below, where the variable is set after the process started.
    with_batch_limit_fixture({"CELERITE_BATCH_MAX_BYTES" => "64"}) do |project, gemfile|
      responses = batch_limit_exchange([
        batch_limit_request(1, gemfile, %w[fingerprint gemspecs]),
        batch_limit_request(2, gemfile, %w[fingerprint gemspecs]),
      ])
      responses.size.should eq(2)
      rejected = JSON.parse(responses[0])
      rejected["ok"].as_bool.should be_false
      rejected["error"]["class"].as_s.should eq("BatchTooLarge")
      rejected["error"]["message"].as_s.should contain("limit is 64")
      rejected["error"]["message"].as_s.should match(/response is \d+ bytes/)
      rejected.as_h.has_key?("result").should be_false
      # The refusal does not corrupt the stream: the second request is answered
      # the same way rather than hanging or echoing the first answer.
      responses[1].should contain(%("ok":false))
    end

    # Client side: the bridge is started with the production cap (4 MiB), then
    # the local cap is shrunk, so the rejection happens in the client's reader
    # rather than in Ruby. The line is consumed whole, so the next request on the
    # same process still succeeds once the cap is restored.
    with_batch_limit_fixture({} of String => String?) do |project, gemfile|
      Celerite::Bridge::BridgeStats.begin_run
      client = Celerite::Bridge::Client.new(server_path: BATCH_LIMIT_SERVER_PATH)
      begin
        ENV["CELERITE_BATCH_MAX_BYTES"] = "64"
        error = expect_raises(Celerite::Bridge::BatchTooLargeError) do
          client.evaluate_batch(gemfile, %w[fingerprint gemspecs])
        end
        error.error_class.should eq("BatchTooLarge")
        error.message.to_s.should contain("limit is 64")
        error.message.to_s.should match(/response is \d+ bytes/)
        Celerite::Bridge::BridgeStats.rpc.should eq(1)

        ENV.delete("CELERITE_BATCH_MAX_BYTES")
        Celerite::Bridge::BridgeStats.rpc.should eq(1)
        evaluation = client.evaluate_batch(gemfile, %w[fingerprint gemspecs])
        evaluation.gemspecs.not_nil!.size.should eq(1)
        Celerite::Bridge::BridgeStats.rpc.should eq(2)
      ensure
        ENV.delete("CELERITE_BATCH_MAX_BYTES")
        client.close
      end
    end
  end

  it "pins the response-byte gate boundaries" do
    limit = 128
    Celerite::Bridge.check_batch_response_bytes!(limit, limit)
    error = expect_raises(Celerite::Bridge::BatchTooLargeError) do
      Celerite::Bridge.check_batch_response_bytes!(limit + 1, limit)
    end
    error.message.to_s.should contain("response is 129 bytes")
    error.message.to_s.should contain("limit is 128")
    error.error_class.should eq("BatchTooLarge")
  end

  it "keeps ignoring unknown include sections, as the existing protocol documents" do
    pending! "ruby not available" unless ruby_available?

    with_batch_limit_fixture({} of String => String?) do |project, gemfile|
      responses = batch_limit_exchange([
        batch_limit_request(1, gemfile, %w[gemspecs plugins]),
      ])
      responses.size.should eq(1)
      parsed = JSON.parse(responses[0])
      parsed["ok"].as_bool.should be_true
      result = parsed["result"].as_h
      result.has_key?("gemspecs").should be_true
      # Unknown sections stay silently ignored (`assets/bridge/server.rb`
      # `op_evaluate_batch` documents the degrade contract): no key, no error.
      result.has_key?("plugins").should be_false
      result.has_key?("fingerprint").should be_false
    end
  end
end
