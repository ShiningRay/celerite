require "./spec_helper"
require "digest/sha256"

# M8 task-235 (roadmap L162, slice F2): the in-process evaluation cache must be
# driven by the evaluation fingerprint, not by the main Gemfile alone. These
# specs prove the two directions:
#
# * a change that the evaluation depends on but that leaves the main Gemfile
#   untouched (a file on the `eval_gemfile` chain, a loaded gemspec's
#   development dependency) must invalidate the cached evaluation;
# * an unchanged project must still hit, without paying a second RPC — the
#   fingerprint rides along with the evaluation that produced it, so verifying
#   a hit costs no extra evaluation.
#
# Runtime records are exercised at the unit level on the parsed document
# (forging `bundler.version` / `platform`), the environment signature through a
# Gemfile that reads an environment variable.
private F2_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)

private F2_ENV_NAMES = %w[
  HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE CELERITE_BRIDGE_SERVER
  CELERITE_BRIDGE_STATS CELERITE_PROFILE_BUNDLER_VERSION
  CELERITE_REFERENCE_BUNDLER_VERSION
]

private F2_PROBE_ENV = "CELERITE_SPEC_PROBE_GEM"

# Runs the block with an isolated project, an isolated HOME/BUNDLE_PATH and the
# repository's bridge server, and brackets it with one cache lifetime (one
# `CLI.run` equivalent).
private def with_f2_project(files : Hash(String, String), *,
                            stats : Bool = false, & : String ->) : Nil
  with_project(files) do |project|
    saved = {} of String => String?
    F2_ENV_NAMES.each { |name| saved[name] = ENV[name]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("BUNDLE_GEMFILE")
    ENV["CELERITE_BRIDGE_SERVER"] = F2_SERVER_PATH
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    if stats
      ENV["CELERITE_BRIDGE_STATS"] = "1"
    else
      ENV.delete("CELERITE_BRIDGE_STATS")
    end
    begin
      # Same order as `CLI.run`: the process-wide counters must start at zero,
      # otherwise an earlier spec in the same process leaks its RPC counts in.
      Celerite::Bridge::BridgeStats.begin_run
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

private def f2_client : Celerite::Bridge::Client
  Celerite::Bridge::Client.new(server_path: F2_SERVER_PATH)
end

private def f2_names(evaluation : Celerite::Bridge::GemfileEvaluation) : Array(String)
  evaluation.dependencies.map(&.name)
end

private F2_MAIN_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gem "rake"
  GEMFILE

private def f2_chain_files : Hash(String, String)
  {
    "Gemfile"              => "source \"https://rubygems.org\"\n\neval_gemfile \"nested/Gemfile.local\"\n",
    "nested/Gemfile.local" => "gem \"json\"\n",
  }
end

private def f2_gemspec_files : Hash(String, String)
  {
    "Gemfile"     => "source \"https://rubygems.org\"\n\ngemspec\n",
    "foo.gemspec" => <<-SPEC,
      Gem::Specification.new do |spec|
        spec.name = "foo"
        spec.version = "0.1.0"
        spec.summary = "celerite fingerprint cache fixture"
        spec.authors = ["celerite"]
        spec.add_development_dependency "rspec"
      end
      SPEC
  }
end

private def f2_runtime(document : Celerite::EvalFingerprint::Document) : Celerite::EvalFingerprint::Runtime
  records = document.records
  Celerite::EvalFingerprint::Runtime.new(
    ruby_version: records["ruby.version"],
    patchlevel: records["ruby.patchlevel"],
    engine: records["ruby.engine"],
    engine_version: records["ruby.engine_version"],
    rubygems_version: records["rubygems.version"],
    bundler_version: records["bundler.version"],
    platform: records["platform"],
  )
end

private def f2_forge(document : Celerite::EvalFingerprint::Document, key : String,
                     value : String) : Celerite::EvalFingerprint::Document
  text = document.text.sub(/\n#{Regex.escape(key)}\t[^\n]*/, "\n#{key}\t#{value}")
  Celerite::EvalFingerprint::Document.parse(text, Digest::SHA256.hexdigest(text), document.verify).not_nil!
end

describe "M8 evaluation fingerprint cache (task-235)" do
  it "re-evaluates when a file on the eval_gemfile chain changes" do
    pending! "ruby not available" unless ruby_available?
    with_f2_project(f2_chain_files) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f2_client
      begin
        first = client.evaluate_gemfile(gemfile)
        f2_names(first).should contain("json")

        File.write(File.join(project, "nested", "Gemfile.local"), "gem \"rake\"\n")
        second = client.evaluate_gemfile(gemfile)

        f2_names(second).should contain("rake")
        f2_names(second).should_not contain("json")
        Celerite::Bridge::EvaluationCache.misses.should be >= 1
      ensure
        client.close
      end
    end
  end

  it "re-evaluates when a loaded gemspec's development dependency changes" do
    pending! "ruby not available" unless ruby_available?
    with_f2_project(f2_gemspec_files) do |project|
      gemfile = File.join(project, "Gemfile")
      first = f2_client
      begin
        f2_names(first.evaluate_gemfile(gemfile)).should contain("rspec")
      ensure
        first.close
      end

      # Bundler keeps its own `@gemspec_cache` per process (`bundler.rb`
      # `load_gemspec`), so the changed development dependency can only be
      # observed by a bridge process that has not loaded the old spec. What
      # this spec pins is that the *cache* refuses to answer and the old
      # evaluation is not reused: the second client re-evaluates and reports
      # the new dependency.
      spec_path = File.join(project, "foo.gemspec")
      File.write(spec_path, File.read(spec_path).sub("rspec", "minitest"))

      second = f2_client
      begin
        names = f2_names(second.evaluate_gemfile(gemfile))
        names.should contain("minitest")
        names.should_not contain("rspec")
        Celerite::Bridge::EvaluationCache.misses.should be >= 1
      ensure
        second.close
      end
    end
  end

  it "re-evaluates when the main Gemfile changes" do
    pending! "ruby not available" unless ruby_available?
    with_f2_project({"Gemfile" => F2_MAIN_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f2_client
      begin
        first = client.evaluate_gemfile(gemfile)
        f2_names(first).should_not contain("json")

        File.write(gemfile, F2_MAIN_GEMFILE + "\ngem \"json\"\n")
        second = client.evaluate_gemfile(gemfile)

        f2_names(second).should contain("json")
        second.gemfile_sha256.should_not eq(first.gemfile_sha256)
        Celerite::Bridge::EvaluationCache.misses.should be >= 1
      ensure
        client.close
      end
    end
  end

  it "hits on an unchanged project without another RPC or process" do
    pending! "ruby not available" unless ruby_available?
    with_f2_project({"Gemfile" => F2_MAIN_GEMFILE}, stats: true) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f2_client
      begin
        first = client.evaluate_gemfile(gemfile)
        first_rpc = Celerite::Bridge::BridgeStats.rpc
        first_rpc.should eq(1)

        second = client.evaluate_gemfile(gemfile)
        Celerite::Bridge::BridgeStats.rpc.should eq(first_rpc)
        Celerite::Bridge::BridgeStats.procs.should eq(1)
        Celerite::Bridge::EvaluationCache.hits.should eq(1)
        Celerite::Bridge::EvaluationCache.misses.should eq(0)

        f2_names(second).should eq(f2_names(first))
        second.gemfile_sha256.should eq(first.gemfile_sha256)
      ensure
        client.close
      end
    end
  end

  it "rejects a fingerprint whose runtime records do not match the process" do
    pending! "ruby not available" unless ruby_available?
    with_f2_project({"Gemfile" => F2_MAIN_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      base = File.dirname(gemfile)
      client = f2_client
      begin
        wire = client.evaluate_batch(gemfile, ["fingerprint"]).fingerprint.not_nil!
        document = Celerite::EvalFingerprint::Document.parse(wire.text, wire.digest, wire.verify).not_nil!
        runtime = f2_runtime(document)

        document.verify(base, runtime).should be_nil

        forged_bundler = f2_forge(document, "bundler.version", "9.9.9")
        forged_bundler.verify(base, runtime).should eq("runtime:bundler.version")

        forged_platform = f2_forge(document, "platform", "forged-platform")
        forged_platform.verify(base, runtime).should eq("runtime:platform")
      ensure
        client.close
      end
    end
  end

  it "misses when an evaluation-relevant environment variable changes" do
    pending! "ruby not available" unless ruby_available?
    files = {
      "Gemfile" => "source \"https://rubygems.org\"\n\ngem ENV[\"#{F2_PROBE_ENV}\"] || \"rake\"\n",
    }
    with_f2_project(files) do |project|
      gemfile = File.join(project, "Gemfile")
      ENV.delete(F2_PROBE_ENV)
      begin
        first = Celerite::Bridge::Client.shared.evaluate_gemfile(gemfile)
        f2_names(first).should eq(["rake"])

        ENV[F2_PROBE_ENV] = "json"
        second = Celerite::Bridge::Client.shared.evaluate_gemfile(gemfile)

        f2_names(second).should eq(["json"])
        Celerite::Bridge::EvaluationCache.misses.should be >= 1
      ensure
        ENV.delete(F2_PROBE_ENV)
        Celerite::Bridge::Client.shutdown
      end
    end
  end

  it "keeps the environment signature stable across plan-cache switches" do
    saved = {"CELERITE_PLAN_CACHE"       => ENV["CELERITE_PLAN_CACHE"]?,
             "CELERITE_PLAN_CACHE_DEBUG" => ENV["CELERITE_PLAN_CACHE_DEBUG"]?}
    begin
      ENV["CELERITE_PLAN_CACHE"] = "0"
      ENV.delete("CELERITE_PLAN_CACHE_DEBUG")
      disabled = Celerite::Bridge::EvaluationCache.environment_signature

      ENV["CELERITE_PLAN_CACHE"] = "1"
      ENV["CELERITE_PLAN_CACHE_DEBUG"] = "1"
      Celerite::Bridge::EvaluationCache.environment_signature.should eq(disabled)
    ensure
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
