require "./spec_helper"
require "digest/sha256"

# M8 task-237 (roadmap L162, slice F4): the F2/F3 evaluation cache may outlive a
# single command. The store is opt-in (`CELERITE_EVAL_CACHE=1`, exactly that
# value), content-addressed by the F1/F3 fingerprint digest, versioned (`v1`) and
# partitioned by a credential-bearing environment namespace that only ever
# appears as a hash. A persisted entry carries its own `verify` set, so a later
# command re-hashes every input before answering; anything that does not prove
# itself is a miss and is deleted.
#
# Boundaries this spec pins down: the switch is dark by default (byte-identical
# output and no directory), corruption never fails a command, changed inputs do
# not answer from a stale entry, credentials never reach the disk, and the store
# is bounded by count and bytes.
private M8_STORE_SERVER = File.expand_path("../assets/bridge/server.rb", __DIR__)
private M8_STORE_INDEX  = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private M8_STORE_ENV = %w[
  HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE BUNDLE_APP_CONFIG
  CELERITE_BRIDGE_SERVER CELERITE_BRIDGE_STATS CELERITE_EVAL_DEBUG
  CELERITE_EVAL_CACHE CELERITE_CACHE_DIR BUNDLE_GEMS__EXAMPLE__COM
  CELERITE_PROFILE_BUNDLER_VERSION CELERITE_REFERENCE_BUNDLER_VERSION
]

private def with_m8_store(files : Hash(String, String), *, cache : String?,
                          stats : Bool = false, debug : Bool = false,
                          & : String ->) : Nil
  with_project(files) do |project|
    saved = {} of String => String?
    M8_STORE_ENV.each { |name| saved[name] = ENV[name]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("BUNDLE_APP_CONFIG")
    ENV.delete("BUNDLE_GEMS__EXAMPLE__COM")
    ENV.delete("CELERITE_CACHE_DIR")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    ENV["CELERITE_BRIDGE_SERVER"] = M8_STORE_SERVER
    if cache
      ENV["CELERITE_EVAL_CACHE"] = cache
    else
      ENV.delete("CELERITE_EVAL_CACHE")
    end
    if stats
      ENV["CELERITE_BRIDGE_STATS"] = "1"
    else
      ENV.delete("CELERITE_BRIDGE_STATS")
    end
    if debug
      ENV["CELERITE_EVAL_DEBUG"] = "1"
    else
      ENV.delete("CELERITE_EVAL_DEBUG")
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

private def m8_store_gemfile : String
  %(source "#{M8_STORE_INDEX}"\n\ngem "json_pure"\n)
end

private def m8_root(project : String) : String
  File.join(project, ".celerite", "cache", "eval")
end

# `Dir.glob` does not walk the hidden `.celerite` directory reliably on this
# platform, so the helpers walk the tree themselves and stay deterministic.
private def m8_walk(directory : String) : Array(String)
  files = [] of String
  return files unless Dir.exists?(directory)
  Dir.each_child(directory) do |child|
    path = File.join(directory, child)
    if File.directory?(path)
      files.concat(m8_walk(path))
    else
      files << path
    end
  end
  files.sort!
end

private def m8_entries(project : String) : Array(String)
  m8_walk(m8_root(project)).select { |path| File.basename(path) == "entry.json" }
end

private def m8_files(project : String) : Array(String)
  m8_walk(m8_root(project))
end

private def m8_digests(project : String) : Array(String)
  m8_entries(project).map { |path| File.basename(File.dirname(path)) }
end

private def m8_purge(project : String) : Nil
  m8_entries(project).each { |path| File.delete(path) }
end

private def m8_stats(stderr : String) : {Int32, Int32}
  line = stderr.lines.find(&.starts_with?("bridge: procs=")).not_nil!
  match = line.match(/^bridge: procs=(\d+) rpc=(\d+) /).not_nil!
  {match[1].to_i, match[2].to_i}
end

private def with_m8_debug_log(& : IO::Memory ->) : Nil
  log = IO::Memory.new
  previous : IO = Celerite::Bridge::EvaluationCache.debug_io
  Celerite::Bridge::EvaluationCache.debug_io = log
  begin
    yield log
  ensure
    Celerite::Bridge::EvaluationCache.debug_io = previous
  end
end

describe "M8 persistent evaluation cache (task-237)" do
  it "stays off unless CELERITE_EVAL_CACHE is exactly 1" do
    pending! "ruby not available" unless ruby_available?
    with_m8_store({"Gemfile" => m8_store_gemfile}, cache: nil) do |project|
      first = run_cli(["lock"])
      second = run_cli(["lock"])
      first[0].should eq(0)
      second[0].should eq(0)
      second[1].should eq(first[1])
      second[2].should eq(first[2])
      Dir.exists?(File.join(project, ".celerite")).should be_false
    end

    # No other spelling enables the store: "0", "true" and an empty value all
    # keep the F2/F3 in-process behaviour.
    ["0", "true", ""].each do |value|
      with_m8_store({"Gemfile" => m8_store_gemfile}, cache: value) do |project|
        2.times do
          status, _output, _errors = run_cli(["lock"])
          status.should eq(0)
        end
        Dir.exists?(File.join(project, ".celerite")).should be_false
      end
    end
  end

  it "hits across commands byte-for-byte and does less bridge work" do
    pending! "ruby not available" unless ruby_available?
    with_m8_debug_log do |log|
      with_m8_store({"Gemfile" => m8_store_gemfile}, cache: "1", debug: true) do |project|
        first = run_cli(["lock"])
        first_lock = File.read(File.join(project, "Gemfile.lock"))
        entries = m8_entries(project)
        entries.size.should eq(1)
        entry = JSON.parse(File.read(entries.first))
        entry["format"].should eq("celerite-eval-cache/1")
        File.basename(File.dirname(entries.first)).should eq(entry["digest"])

        second = run_cli(["lock"])
        second[0].should eq(first[0])
        second[1].should eq(first[1])
        second[2].should eq(first[2])
        File.read(File.join(project, "Gemfile.lock")).should eq(first_lock)
      end
      log.to_s.should contain("eval-cache: persisted ")
      log.to_s.should contain("eval-cache: hit (persistent)")
    end

    # The same two commands with counters visible: the hit must not spawn an
    # extra bridge process and must issue fewer RPCs than the cold run (the only
    # RPC left is `ruby_environment` for the runtime records).
    with_m8_store({"Gemfile" => m8_store_gemfile}, cache: "1", stats: true) do |project|
      first = run_cli(["lock"])
      second = run_cli(["lock"])
      procs_first, rpc_first = m8_stats(first[2])
      procs_second, rpc_second = m8_stats(second[2])
      procs_first.should be >= 1
      rpc_first.should be >= 1
      procs_second.should be <= procs_first
      rpc_second.should be < rpc_first
    end
  end

  it "treats a truncated, field-less or digest-tampered entry as a miss" do
    pending! "ruby not available" unless ruby_available?

    truncate = ->(path : String) do
      body = File.read(path)
      File.write(path, body[0, body.size // 2])
    end
    drop_evaluation = ->(path : String) do
      json = JSON.parse(File.read(path))
      json.as_h.delete("evaluation")
      File.write(path, json.to_json)
    end
    tamper_digest = ->(path : String) do
      fake = Digest::SHA256.hexdigest("tampered")
      File.write(path, File.read(path).gsub(/"digest":"[0-9a-f]{64}"/, %("digest":"#{fake}")))
    end

    {"truncated" => truncate, "no evaluation" => drop_evaluation,
     "tampered digest" => tamper_digest}.each do |name, corrupt|
      with_m8_debug_log do |log|
        with_m8_store({"Gemfile" => m8_store_gemfile}, cache: "1", debug: true) do |project|
          first = run_cli(["lock"])
          first[0].should eq(0)
          entries = m8_entries(project)
          entries.size.should eq(1)
          corrupt.call(entries.first)

          log.clear
          second = run_cli(["lock"])
          second[0].should eq(0)
          second[1].should eq(first[1])
          second[2].should eq(first[2])
          log.to_s.should_not contain("hit (persistent)")

          # The bad entry is gone and a fresh, self-consistent one replaced it.
          after = m8_entries(project)
          after.size.should eq(1)
          JSON.parse(File.read(after.first))["format"].should eq("celerite-eval-cache/1")
        end
      end
    end
  end

  it "re-evaluates after the gemfile, the eval chain or a gemspec changes" do
    pending! "ruby not available" unless ruby_available?

    with_m8_debug_log do |log|
      with_m8_store({"Gemfile" => m8_store_gemfile}, cache: "1", debug: true) do |project|
        run_cli(["lock"]).first.should eq(0)
        old = m8_entries(project).first
        File.open(File.join(project, "Gemfile"), "a") { |file| file.puts "# changed" }
        log.clear
        run_cli(["lock"]).first.should eq(0)
        log.to_s.should_not contain("hit (persistent)")
        log.to_s.should contain("sha256:gemfile:Gemfile")
        m8_entries(project).size.should eq(1)
        m8_entries(project).first.should_not eq(old)
      end
    end

    files = {
      "Gemfile"              => %(source "#{M8_STORE_INDEX}"\n\neval_gemfile "nested/Gemfile.local"\n),
      "nested/Gemfile.local" => %(gem "json_pure"\n),
    }
    with_m8_debug_log do |log|
      with_m8_store(files, cache: "1", debug: true) do |project|
        run_cli(["lock"]).first.should eq(0)
        log.clear
        File.write(File.join(project, "nested", "Gemfile.local"), %(gem "json_pure"\n# changed\n))
        run_cli(["lock"]).first.should eq(0)
        log.to_s.should_not contain("hit (persistent)")
        log.to_s.should contain("sha256:evalchain:nested/Gemfile.local")
      end
    end

    gemspec = {"Gemfile"      => %(source "#{M8_STORE_INDEX}"\n\ngemspec\n),
               "demo.gemspec" => <<-SPEC}
                 Gem::Specification.new do |spec|
                   spec.name = "demo"
                   spec.version = "1.0.0"
                   spec.summary = "demo"
                   spec.authors = ["demo"]
                 end
                 SPEC
    with_m8_debug_log do |log|
      with_m8_store(gemspec, cache: "1", debug: true) do |project|
        run_cli(["lock"]).first.should eq(0)
        log.clear
        path = File.join(project, "demo.gemspec")
        File.write(path, File.read(path).sub("1.0.0", "1.0.1"))
        run_cli(["lock"]).first.should eq(0)
        log.to_s.should_not contain("hit (persistent)")
        log.to_s.should contain("sha256:gemspec:demo.gemspec")
      end
    end
  end

  it "never writes a credential-bearing source URI and hashes the namespace" do
    pending! "ruby not available" unless ruby_available?

    Celerite::EvalCacheStore.persistable?(
      %({"type":"Rubygems","remotes":["https://alice:s3cret@gems.example.invalid/"]})).should be_false
    Celerite::EvalCacheStore.persistable?(%(... "remotes":["https://gems.example.invalid/"] ...)).should be_true

    with_m8_debug_log do |log|
      with_m8_store({"Gemfile" => m8_store_gemfile}, cache: "1", debug: true) do |project|
        ENV.delete("BUNDLE_GEMS__EXAMPLE__COM")
        plain = Celerite::EvalCacheStore.namespace
        plain.matches?(/\A[0-9a-f]{16}\z/).should be_true
        ENV["BUNDLE_GEMS__EXAMPLE__COM"] = "alice:s3cret"
        Celerite::EvalCacheStore.namespace.should_not eq(plain)
        Celerite::EvalCacheStore.namespace.should_not contain("s3cret")

        gemfile = File.join(project, "Gemfile")
        client = Celerite::Bridge::Client.new(server_path: M8_STORE_SERVER)
        begin
          Celerite::Bridge::BridgeStats.begin_run
          Celerite::Bridge::EvaluationCache.begin_run
          answer = client.evaluate_batch(gemfile, ["fingerprint"])
          fingerprint = answer.fingerprint.not_nil!
          fingerprint.state.should eq(Celerite::EvalFingerprint::State::Deterministic)

          # A real evaluation whose `sources` carry userinfo: the store must
          # withhold it instead of writing the credential to disk. The batch
          # that produced the fingerprint already persisted its own clean entry,
          # so clear the store first and watch the tainted payload alone.
          m8_purge(project)
          raw = JSON.parse(answer.evaluation.to_json).as_h
          raw["sources"] = JSON.parse(
            %([{"type":"Rubygems","remotes":["https://alice:s3cret@gems.example.invalid/"]}]))
          tainted = Celerite::Bridge::GemfileEvaluation.from_json(raw.to_json)
          Celerite::Bridge::EvaluationCache.store(gemfile, tainted, client.cache_id, fingerprint)
          m8_entries(project).should be_empty
          log.to_s.should contain("persist skipped (credential)")

          # The same fingerprint with the clean evaluation is stored, so the
          # refusal is about the payload and not about the switch.
          Celerite::Bridge::EvaluationCache.store(gemfile, answer.evaluation, client.cache_id, fingerprint)
          m8_entries(project).size.should eq(1)
        ensure
          client.close
          Celerite::Bridge::EvaluationCache.finish
        end

        m8_files(project).each do |path|
          body = File.read(path)
          body.should_not contain("s3cret")
          body.should_not contain("alice")
        end
        m8_walk(m8_root(project)).each do |path|
          path.should_not contain("s3cret")
        end
      end
    end
  end

  it "bounds the store by entry count and total bytes, oldest first" do
    Celerite::EvalCacheStore::MAX_ENTRIES.should eq(128)
    Celerite::EvalCacheStore::MAX_BYTES.should eq(8_i64 * 1024 * 1024)

    with_m8_store({} of String => String, cache: "1") do |project|
      digests = [] of String
      6.times do |index|
        digest = Digest::SHA256.hexdigest("entry-#{index}")
        digests << digest
        payload = %({"format":"celerite-eval-cache/1","digest":"#{digest}","evaluation":{}})
        Celerite::EvalCacheStore.write(digest, payload).should be_true
        sleep 5.milliseconds
      end
      m8_entries(project).size.should eq(6)

      Celerite::EvalCacheStore.prune(nil, 4, Celerite::EvalCacheStore::MAX_BYTES)
      m8_entries(project).size.should eq(4)
      remaining = m8_digests(project)
      remaining.sort.should eq(digests.last(4).sort)

      Celerite::EvalCacheStore.prune(nil, 100, 250)
      kept = m8_entries(project)
      kept.sum { |path| File.info(path).size }.should be <= 250
      kept.size.should be <= 2
    end
  end

  it "does not persist the states F2/F3 withhold and keeps in-process hits" do
    pending! "ruby not available" unless ruby_available?

    dynamic = <<-GEMFILE
      source "#{M8_STORE_INDEX}"

      if ENV["CELERITE_SPEC_DYNAMIC_GEM"]
        gem "json"
      else
        gem "json_pure"
      end
      GEMFILE

    with_m8_store({"Gemfile" => dynamic}, cache: "1", debug: true) do |project|
      gemfile = File.join(project, "Gemfile")
      client = Celerite::Bridge::Client.new(server_path: M8_STORE_SERVER)
      begin
        Celerite::Bridge::BridgeStats.begin_run
        Celerite::Bridge::EvaluationCache.begin_run
        answer = client.evaluate_batch(gemfile, ["fingerprint"])
        answer.fingerprint.not_nil!.state.should eq(Celerite::EvalFingerprint::State::Unknown)
        Celerite::Bridge::EvaluationCache.store(gemfile, answer.evaluation, client.cache_id,
          answer.fingerprint)
        m8_entries(project).should be_empty
        Dir.exists?(File.join(project, ".celerite")).should be_false
      ensure
        client.close
        Celerite::Bridge::EvaluationCache.finish
      end
    end

    with_m8_store({"Gemfile" => m8_store_gemfile}, cache: "1") do |project|
      gemfile = File.join(project, "Gemfile")
      client = Celerite::Bridge::Client.new(server_path: M8_STORE_SERVER)
      begin
        Celerite::Bridge::BridgeStats.begin_run
        Celerite::Bridge::EvaluationCache.begin_run
        answer = client.evaluate_batch(gemfile, ["fingerprint"])
        fingerprint = answer.fingerprint.not_nil!
        document = Celerite::EvalFingerprint::Document.parse(
          fingerprint.text, fingerprint.digest, fingerprint.verify).not_nil!
        forged_text = document.text.sub("gemfile.path\t", "gemfile.path\tforged-")
        forged = Celerite::EvalFingerprint::Document.parse(
          forged_text, document.digest, document.verify).not_nil!
        forged.verify(project, nil).should eq("digest")
        m8_purge(project)
        Celerite::Bridge::EvaluationCache.store(gemfile, answer.evaluation, client.cache_id,
          Celerite::Bridge::EvalFingerprint.new(forged.text, forged.digest, forged.verify))
        m8_entries(project).should be_empty

        # The in-process F2/F3 cache still answers first: a second lookup in the
        # same command is a memory hit and does not touch the disk.
        Celerite::Bridge::EvaluationCache.store(gemfile, answer.evaluation, client.cache_id,
          fingerprint)
        Celerite::Bridge::EvaluationCache.fetch(gemfile, ["fingerprint"], client.cache_id) do
          raise "a same-client entry must not ask for runtime records"
        end.should_not be_nil
        Celerite::Bridge::EvaluationCache.hits.should eq(1)
      ensure
        client.close
        Celerite::Bridge::EvaluationCache.finish
      end
    end
  end
end
