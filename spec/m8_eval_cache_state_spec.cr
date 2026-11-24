require "./spec_helper"
require "digest/sha256"

# M8 task-236 (roadmap L162, slice F3): an evaluation is cached only when the
# bridge classifies it as `deterministic`. The three states are decided on the
# bridge side (it is the only side that knows what the DSL executed) and this
# client consumes them verbatim:
#
# * `deterministic` — static declarations only, every input is in `verify`, so
#   the second identical call must hit without a second evaluation;
# * `unknown` — the evaluation read something the fingerprint cannot describe
#   (`ENV`, `Dir`, a plugin index, ...). Both calls evaluate again and must
#   return the same result: no cache and no behaviour change;
# * `broken` — the fingerprint contradicts itself. The evaluation that produced
#   it is still usable, but nothing is stored.
#
# Diagnostics for all three keep the documented shape
# `eval-cache: state=<wire>[ reason=<why>]`; the specs capture them through the
# injectable `EvaluationCache.debug_io` instead of the process STDERR.
private F3_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)

private F3_ENV_NAMES = %w[
  HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE BUNDLE_APP_CONFIG
  CELERITE_BRIDGE_SERVER CELERITE_BRIDGE_STATS CELERITE_EVAL_DEBUG
  CELERITE_PROFILE_BUNDLER_VERSION CELERITE_REFERENCE_BUNDLER_VERSION
]

private def with_f3_project(files : Hash(String, String), *,
                            app_config : Bool = false, debug : Bool = false,
                            & : String ->) : Nil
  with_project(files) do |project|
    saved = {} of String => String?
    F3_ENV_NAMES.each { |name| saved[name] = ENV[name]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("BUNDLE_GEMFILE")
    ENV["CELERITE_BRIDGE_SERVER"] = F3_SERVER_PATH
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    ENV.delete("CELERITE_BRIDGE_STATS")
    if app_config
      dir = File.join(project, "app-config", "plugin")
      Dir.mkdir_p(dir)
      File.write(File.join(dir, "index"), "")
      ENV["BUNDLE_APP_CONFIG"] = File.join(project, "app-config")
    else
      ENV.delete("BUNDLE_APP_CONFIG")
    end
    if debug
      ENV["CELERITE_EVAL_DEBUG"] = "1"
    else
      ENV.delete("CELERITE_EVAL_DEBUG")
    end
    begin
      Celerite::Bridge::EvaluationCache.begin_run
      yield project
    ensure
      Celerite::Bridge::EvaluationCache.finish
      saved.each do |name, value|
        if value
          ENV[name] = value
        else
          ENV.delete(name)
        end
      end
    end
  end
end

private def f3_client : Celerite::Bridge::Client
  Celerite::Bridge::Client.new(server_path: F3_SERVER_PATH)
end

private def f3_evaluate(client : Celerite::Bridge::Client, gemfile : String) : Celerite::Bridge::BatchGemfileEvaluation
  client.evaluate_batch(gemfile, ["fingerprint"])
end

private def f3_names(evaluation : Celerite::Bridge::GemfileEvaluation) : Array(String)
  evaluation.dependencies.map(&.name)
end

private F3_STATIC_FILES = {
  "Gemfile"              => "source \"https://rubygems.org\"\n\neval_gemfile \"nested/Gemfile.local\"\n",
  "nested/Gemfile.local" => "gem \"rake\"\n",
}

private F3_ENV_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  if ENV["CELERITE_SPEC_DYNAMIC_GEM"]
    gem "json"
  else
    gem "rake"
  end
  GEMFILE

private F3_GLOB_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  Dir.glob("deps/*.gem").sort.each do |path|
    gem File.basename(path, ".gem")
  end
  GEMFILE

describe "M8 evaluation cache state (task-236)" do
  it "stores and hits a deterministic Gemfile with a static eval_gemfile chain" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project(F3_STATIC_FILES) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f3_client
      begin
        first = f3_evaluate(client, gemfile)
        fingerprint = first.fingerprint.not_nil!
        fingerprint.state.should eq(Celerite::EvalFingerprint::State::Deterministic)
        fingerprint.state_reason.should be_nil
        f3_names(first.evaluation).should eq(["rake"])

        Celerite::Bridge::EvaluationCache.hits.should eq(0)

        second = f3_evaluate(client, gemfile)
        f3_names(second.evaluation).should eq(["rake"])
        Celerite::Bridge::EvaluationCache.hits.should eq(1)
        Celerite::Bridge::EvaluationCache.misses.should eq(0)
      ensure
        client.close
      end
    end
  end

  it "never caches or reuses an evaluation that reads ENV" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project({"Gemfile" => F3_ENV_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f3_client
      begin
        first = f3_evaluate(client, gemfile)
        fingerprint = first.fingerprint.not_nil!
        fingerprint.state.should eq(Celerite::EvalFingerprint::State::Unknown)
        fingerprint.state_reason.not_nil!.should eq("token:ENV")
        f3_names(first.evaluation).should eq(["rake"])

        second = f3_evaluate(client, gemfile)
        second.fingerprint.not_nil!.state.should eq(Celerite::EvalFingerprint::State::Unknown)
        # Same result both times, and no hit: the cache is transparent here.
        f3_names(second.evaluation).should eq(["rake"])
        Celerite::Bridge::EvaluationCache.hits.should eq(0)
        # The second lookup is a reported miss: the path was evaluated and
        # withheld, so the cache cannot answer and must evaluate again.
        Celerite::Bridge::EvaluationCache.misses.should eq(1)
      ensure
        client.close
      end
    end
  end

  it "never caches or reuses a Gemfile that globs the filesystem" do
    pending! "ruby not available" unless ruby_available?
    files = {"Gemfile" => F3_GLOB_GEMFILE, "deps/alpha.gem" => "stub\n"}
    with_f3_project(files) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f3_client
      begin
        first = f3_evaluate(client, gemfile)
        fingerprint = first.fingerprint.not_nil!
        fingerprint.state.should eq(Celerite::EvalFingerprint::State::Unknown)
        # The scan reports the first token it sees; `Dir.glob` and
        # `File.basename` are both dynamic, so either name withholds the cache.
        fingerprint.state_reason.not_nil!.should eq("token:File")
        f3_names(first.evaluation).should eq(["alpha"])

        second = f3_evaluate(client, gemfile)
        f3_names(second.evaluation).should eq(["alpha"])
        Celerite::Bridge::EvaluationCache.hits.should eq(0)
        Celerite::Bridge::EvaluationCache.misses.should eq(1)
      ensure
        client.close
      end
    end
  end

  it "refuses to store a fingerprint whose digest does not match its text" do
    pending! "ruby not available" unless ruby_available?
    log = IO::Memory.new
    previous : IO = Celerite::Bridge::EvaluationCache.debug_io
    Celerite::Bridge::EvaluationCache.debug_io = log
    begin
      with_f3_project(F3_STATIC_FILES, debug: true) do |project|
        gemfile = File.join(project, "Gemfile")
        client = f3_client
        answer = begin
          # The evaluation itself succeeds and yields a usable answer.
          result = f3_evaluate(client, gemfile)
          f3_names(result.evaluation).should eq(["rake"])
          result
        ensure
          client.close
        end

        fingerprint = answer.fingerprint.not_nil!
        document = Celerite::EvalFingerprint::Document.parse(
          fingerprint.text, fingerprint.digest, fingerprint.verify).not_nil!
        # Hand-forged entry: edited text, stale digest. `verify` must call it
        # broken and never let it answer.
        forged_text = document.text.sub("gemfile.path\t", "gemfile.path\tforged-")
        forged_text.should_not eq(document.text)
        document.verify(project, nil).should be_nil
        forged = Celerite::EvalFingerprint::Document.parse(
          forged_text, document.digest, document.verify).not_nil!
        forged.verify(project, nil).should eq("digest")
        Celerite::EvalFingerprint.broken_reason?("digest").should be_true

        Celerite::Bridge::EvaluationCache.begin_run
        wire = Celerite::Bridge::EvalFingerprint.new(
          forged.text, forged.digest, forged.verify,
          Celerite::EvalFingerprint::State::Deterministic)
        Celerite::Bridge::EvaluationCache.store(
          gemfile, answer.evaluation, client.cache_id, wire)
        Celerite::Bridge::EvaluationCache.fetch(gemfile, ["fingerprint"], client.cache_id) do
          raise "the runtime must not be queried without an entry"
        end.should be_nil
        log.to_s.should contain("eval-cache: state=broken reason=digest")
        Celerite::Bridge::EvaluationCache.hits.should eq(0)
      end
    ensure
      Celerite::Bridge::EvaluationCache.debug_io = previous
    end
  end

  it "treats a corrupt verify payload and an unhashable file as broken" do
    # Missing `verify` on the wire: the section cannot be parsed, so no entry.
    Celerite::Bridge::EvalFingerprint.parse(JSON.parse(%({"text":"x","digest":"y"}))).should be_nil

    text = <<-TEXT
      celerite-eval-v1
      fp.format\t1
      evalchain.count\t0
      gemspec.count\t0
      TEXT
    verify = JSON.parse(%({"files":[{"role":"gemfile","path":"Gemfile","sha256":"-"}]}))
    document = Celerite::EvalFingerprint::Document.parse(text, Digest::SHA256.hexdigest(text), verify).not_nil!
    document.integrity_reason.should eq("unreadable:gemfile:Gemfile")
    document.verify(".", nil).should eq("unreadable:gemfile:Gemfile")
    Celerite::EvalFingerprint.broken_reason?("unreadable:gemfile:Gemfile").should be_true

    # A structural mismatch is broken too: one gemfile record is required.
    two = JSON.parse(%({"files":[
      {"role":"gemfile","path":"Gemfile","sha256":"-"},
      {"role":"gemfile","path":"Other","sha256":"-"}
    ]}))
    again = Celerite::EvalFingerprint::Document.parse(text, Digest::SHA256.hexdigest(text), two).not_nil!
    again.integrity_reason.should eq("gemfile")
  end

  it "treats an installed plugin index as unknown and says why" do
    pending! "ruby not available" unless ruby_available?
    # F1 hashes the Gemfile, the eval chain and the loaded gemspecs — not the
    # plugin index. A `source ..., type:` or a plugin-provided DSL call could
    # therefore change the evaluation without changing the fingerprint, so an
    # installed index withholds the cache instead of guessing "no plugins".
    with_f3_project({"Gemfile" => "source \"https://rubygems.org\"\n\ngem \"rake\"\n"},
      app_config: true) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f3_client
      begin
        answer = f3_evaluate(client, gemfile)
        fingerprint = answer.fingerprint.not_nil!
        fingerprint.state.should eq(Celerite::EvalFingerprint::State::Unknown)
        fingerprint.state_reason.not_nil!.should eq("plugin-index")
        f3_names(answer.evaluation).should eq(["rake"])
        Celerite::Bridge::EvaluationCache.hits.should eq(0)
      ensure
        client.close
      end
    end
  end

  it "reports each state and its reason under CELERITE_EVAL_DEBUG=1" do
    pending! "ruby not available" unless ruby_available?
    log = IO::Memory.new
    previous : IO = Celerite::Bridge::EvaluationCache.debug_io
    Celerite::Bridge::EvaluationCache.debug_io = log
    begin
      with_f3_project(F3_STATIC_FILES, debug: true) do |project|
        client = f3_client
        begin
          2.times { f3_evaluate(client, File.join(project, "Gemfile")) }
        ensure
          client.close
        end
      end
      log.to_s.should contain("eval-cache: state=deterministic")
      log.to_s.should contain("eval-cache: hit")

      with_f3_project({"Gemfile" => F3_ENV_GEMFILE}, debug: true) do |project|
        client = f3_client
        begin
          f3_evaluate(client, File.join(project, "Gemfile"))
        ensure
          client.close
        end
      end
      log.to_s.should contain("eval-cache: state=unknown reason=token:ENV")
    ensure
      Celerite::Bridge::EvaluationCache.debug_io = previous
    end
  end
end
