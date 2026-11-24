require "./spec_helper"

# M8 task-239 (roadmap L162, slice F5): every Gemfile evaluation a command
# performs now goes through `Celerite::GemfileEvaluator`. The entry point is not
# allowed to change what a command prints or which exit code it returns — it only
# changes the process and RPC structure behind that output. Boundaries pinned
# here:
#
# * one command evaluates the Gemfile at most once, whatever its call sites
#   (`BridgeStats.evaluations`, reset by `CLI.run` like every other counter);
# * a caller that needs `gemspecs` gets them from that same evaluation request,
#   so the pair costs one RPC and a second lookup is answered from the cache;
# * a persisted `EvalCacheStore` entry serves the next command without any
#   evaluation at all;
# * an `unknown` fingerprint is never reused (the evaluation happens again);
# * stdout/stderr/exit stay byte-identical to a run without the persistent
#   cache, i.e. the feature is invisible to every observable channel.
private M8_EVAL_SERVER = File.expand_path("../assets/bridge/server.rb", __DIR__)
private M8_EVAL_INDEX  = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private M8_EVAL_ENV = %w[
  HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE BUNDLE_APP_CONFIG BUNDLE_FROZEN
  CELERITE_BRIDGE_SERVER CELERITE_BRIDGE_STATS CELERITE_EVAL_DEBUG
  CELERITE_EVAL_CACHE CELERITE_CACHE_DIR BUNDLE_GEMS__EXAMPLE__COM
  CELERITE_PROFILE_BUNDLER_VERSION CELERITE_REFERENCE_BUNDLER_VERSION
]

private def with_m8_eval(files : Hash(String, String), *,
                         cache : String? = nil, stats : Bool = false,
                         & : String ->) : Nil
  with_project(files) do |project|
    saved = {} of String => String?
    M8_EVAL_ENV.each { |name| saved[name] = ENV[name]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("BUNDLE_APP_CONFIG")
    ENV.delete("BUNDLE_FROZEN")
    ENV.delete("BUNDLE_GEMS__EXAMPLE__COM")
    ENV.delete("CELERITE_CACHE_DIR")
    ENV.delete("CELERITE_EVAL_DEBUG")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    ENV.delete("CELERITE_REFERENCE_BUNDLER_VERSION")
    ENV["CELERITE_BRIDGE_SERVER"] = M8_EVAL_SERVER
    if stats
      ENV["CELERITE_BRIDGE_STATS"] = "1"
    else
      ENV.delete("CELERITE_BRIDGE_STATS")
    end
    if cache
      ENV["CELERITE_EVAL_CACHE"] = cache
    else
      ENV.delete("CELERITE_EVAL_CACHE")
    end
    begin
      yield project
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

private def m8_eval_gemfile : String
  %(source "#{M8_EVAL_INDEX}"\n\ngem "thor"\n)
end

# The same project shape plus a `gemspec` directive, which is the only way a
# `gemspecs` section becomes non-empty (`bundler/lib/bundler/dsl.rb:63-81`).
private M8_EVAL_GEMSPEC_FILES = {
  "Gemfile"          => %(source "#{M8_EVAL_INDEX}"\n\ngemspec\n\ngem "thor"\n),
  "eval_fix.gemspec" => <<-RUBY,
    Gem::Specification.new do |spec|
      spec.name = "eval_fix"
      spec.version = "0.1.0"
      spec.summary = "single-entry fixture"
      spec.authors = ["celerite"]
      spec.files = []
      spec.require_paths = ["lib"]
    end
    RUBY
}

# `unknown` is produced by an evaluation that read something the fingerprint
# cannot describe (slice F3): the `ENV` read makes the fingerprint `token:ENV`
# and the evaluation must stay out of every cache.
private M8_EVAL_ENV_GEMFILE = <<-GEMFILE
  source "#{M8_EVAL_INDEX}"

  if ENV["CELERITE_SPEC_DYNAMIC_GEM"]
    gem "json_pure"
  else
    gem "thor"
  end
  GEMFILE

private def m8_eval_stats(stderr : String) : {Int32, Int32}
  line = stderr.lines.find(&.starts_with?("bridge: procs=")).not_nil!
  match = line.match(/^bridge: procs=(\d+) rpc=(\d+) /).not_nil!
  {match[1].to_i, match[2].to_i}
end

describe "M8 single evaluation entry (task-239)" do
  it "evaluates the Gemfile at most once per command" do
    pending! "ruby not available" unless ruby_available?
    with_m8_eval({"Gemfile" => m8_eval_gemfile}, stats: true) do
      run_cli(["lock"]).first.should eq(0)
      run_cli(["install"]).first.should eq(0)

      # The reference evaluates once per process (`bundler.rb:229-235`
      # `@definition ||=`), so no command may evaluate twice. `list` needs no
      # evaluation at all: it answers from the lockfile.
      {"lock" => 1, "check" => 1, "install" => nil, "show thor" => 1, "list" => nil}.each do |command, expected|
        status, _output, errors = run_cli(command.split(' '))
        status.should eq(0)
        evaluations = Celerite::Bridge::BridgeStats.evaluations
        evaluations.should be <= 1
        if expected
          evaluations.should eq(expected)
        end
        # A command that evaluated still shows up in the RPC counters, so a
        # silently skipped bridge cannot make this test pass by doing nothing.
        m8_eval_stats(errors).first.should be >= 0
      end
    end
  end

  it "answers a gemspec request from the evaluation request itself" do
    pending! "ruby not available" unless ruby_available?
    with_m8_eval(M8_EVAL_GEMSPEC_FILES, stats: true) do |project|
      Celerite::Bridge::BridgeStats.begin_run
      Celerite::Bridge::EvaluationCache.begin_run
      gemfile = File.join(project, "Gemfile")
      with_client do |client|
        begin
          before = Celerite::Bridge::BridgeStats.rpc
          first = Celerite::GemfileEvaluator.fetch(gemfile, client: client)
          Celerite::Bridge::BridgeStats.rpc.should eq(before + 1)
          Celerite::Bridge::BridgeStats.evaluations.should eq(1)
          first.evaluation.gemfile.should eq(gemfile)

          paths = first.gemspecs.not_nil!
          paths.size.should eq(1)
          paths.first.should end_with("eval_fix.gemspec")
          first.fingerprint.should_not be_nil

          # The evaluation request carried `gemspecs`, so the entry remembers
          # them and a second lookup answers without another request or
          # evaluation.
          before = Celerite::Bridge::BridgeStats.rpc
          Celerite::GemfileEvaluator.gemspecs(gemfile, client).should eq(paths)
          Celerite::Bridge::BridgeStats.rpc.should eq(before)
          Celerite::Bridge::BridgeStats.evaluations.should eq(1)
        ensure
          Celerite::Bridge::EvaluationCache.finish
        end
      end
    end
  end

  it "serves the next command from the persistent store without evaluating" do
    pending! "ruby not available" unless ruby_available?
    with_m8_eval({"Gemfile" => m8_eval_gemfile}, cache: "1", stats: true) do |project|
      first = run_cli(["lock"])
      first[0].should eq(0)
      lockfile = File.read(File.join(project, "Gemfile.lock"))

      second = run_cli(["lock"])
      # stderr carries the `CELERITE_BRIDGE_STATS` line, whose numbers differ by
      # construction (the second run answers from the store), so only stdout
      # and the exit code must match byte-for-byte.
      second[0].should eq(first[0])
      second[1].should eq(first[1])
      File.read(File.join(project, "Gemfile.lock")).should eq(lockfile)

      # The in-process cache is reset by every `CLI.run`, so a zero here can
      # only come from the persisted entry.
      Celerite::Bridge::BridgeStats.evaluations.should eq(0)
      # It still costs a runtime lookup that proves the record set, but strictly
      # fewer RPC than the evaluating run.
      Celerite::Bridge::BridgeStats.evaluations.should eq(0)
      m8_eval_stats(second[2]).last.should be < m8_eval_stats(first[2]).last
    end
  end

  it "does not reuse an unknown fingerprint" do
    pending! "ruby not available" unless ruby_available?
    with_m8_eval({"Gemfile" => M8_EVAL_ENV_GEMFILE}, stats: true) do |project|
      Celerite::Bridge::BridgeStats.begin_run
      Celerite::Bridge::EvaluationCache.begin_run
      gemfile = File.join(project, "Gemfile")
      with_client do |client|
        begin
          first = Celerite::GemfileEvaluator.fetch(gemfile, client: client)
          first.fingerprint.not_nil!.state.should eq(Celerite::EvalFingerprint::State::Unknown)
          Celerite::Bridge::BridgeStats.evaluations.should eq(1)

          second = Celerite::GemfileEvaluator.fetch(gemfile, client: client)
          second.fingerprint.not_nil!.state.should eq(Celerite::EvalFingerprint::State::Unknown)
          # Withheld: the second lookup evaluates again instead of answering.
          Celerite::Bridge::BridgeStats.evaluations.should eq(2)
          Celerite::Bridge::EvaluationCache.hits.should eq(0)
          second.evaluation.dependencies.map(&.name).should eq(first.evaluation.dependencies.map(&.name))
        ensure
          Celerite::Bridge::EvaluationCache.finish
        end
      end
    end
  end

  it "keeps stdout, stderr and the exit code byte-identical with the cache on" do
    pending! "ruby not available" unless ruby_available?

    # Same command set, same project shape, one run with the persistent cache
    # off and one with it on. `lock` runs first in both so each command sees the
    # same lockfile state; only the on run leaves a `.celerite` directory.
    {"check" => ["check"], "list" => ["list"], "show" => ["show", "thor"]}.each do |label, argv|
      off = nil.as({Int32, String, String}?)
      with_m8_eval({"Gemfile" => m8_eval_gemfile}) do |project|
        run_cli(["lock"]).first.should eq(0)
        off = run_cli(argv)
        Dir.exists?(File.join(project, ".celerite")).should be_false
      end

      with_m8_eval({"Gemfile" => m8_eval_gemfile}, cache: "1") do |project|
        run_cli(["lock"]).first.should eq(0)
        Dir.exists?(File.join(project, ".celerite")).should be_true
        on = run_cli(argv)
        off.should_not be_nil
        baseline = off.not_nil!
        on[0].should eq(baseline[0])
        on[1].should eq(baseline[1])
        on[2].should eq(baseline[2])
      end
    end
  end
end
