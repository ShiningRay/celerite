require "./spec_helper"
require "../src/celerite"
require "../src/celerite/gem/platform"
require "file_utils"

module Celerite
  describe "M8 L161 S3b Resolution solve_batch integration" do
    it "sends the complete eligible request once and reuses the existing evaluation" do
      with_resolution_batch_project do |dir, definition, batch|
        with_resolution_batch_server("success") do |client, log|
          resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
          specs = resolution.resolve!

          specs.map(&.name).should eq(["alpha"])
          requests = resolution_batch_log(log).select { |entry| entry["op"] == "solve_batch" }
          requests.size.should eq(1)
          resolution_batch_log(log).count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)

          payload = requests.first["payload"]
          payload["schema"].as_s.should eq(Celerite::Bridge::SolveBatch::SCHEMA)
          payload["evaluation"]["fingerprint"]["state"].as_s.should eq("deterministic")
          payload["evaluation"]["sources"].as_a.all? { |source| source["type"].as_s == "Rubygems" }.should be_true
          payload["evaluation"]["sources"].as_a.all? { |source| source["materialization"].as_s == "pure_data" }.should be_true
          payload["requirements"].as_a.map { |value| value["name"].as_s }.should eq(["alpha"])
          payload["candidate_closure"]["complete"].as_bool.should be_true
          payload["candidate_closure"]["candidate_count"].as_i.should eq(2)
          payload["candidates_by_source"].as_h.values.sum(&.as_a.size).should eq(2)
          payload["locked_base"]["specs"].as_a.should be_empty
          payload["limits"]["timeout_ms"].as_i.should eq(Celerite::Bridge::SolveBatch::MAX_TIMEOUT_MS)
        end
      end
    end

    it "keeps Bundler 2.7.2 on the legacy path with zero solve_batch calls" do
      with_resolution_batch_project do |_dir, definition, batch|
        with_resolution_batch_server("success") do |client, log|
          evaluation = resolution_batch_evaluation(batch.evaluation, "2.7.2")
          resolution = Resolution.from_evaluation(definition, evaluation, client, batch.fingerprint)
          resolution.resolve!.map(&.name).should eq(["alpha"])
          resolution_batch_log(log).count { |entry| entry["op"] == "solve_batch" }.should eq(0)
        end
      end
    end

    it "keeps unknown and broken fingerprints on the legacy path" do
      {EvalFingerprint::State::Unknown, EvalFingerprint::State::Broken}.each do |state|
        with_resolution_batch_project do |_dir, definition, batch|
          with_resolution_batch_server("success") do |client, log|
            original = batch.fingerprint.not_nil!
            fingerprint = Celerite::Bridge::EvalFingerprint.new(original.text, original.digest, original.verify, state, "test")
            resolution = Resolution.from_evaluation(definition, batch.evaluation, client, fingerprint)
            resolution.resolve!.map(&.name).should eq(["alpha"])
            resolution_batch_log(log).count { |entry| entry["op"] == "solve_batch" }.should eq(0)
          end
        end
      end
    end

    it "keeps a full unlock on the legacy path with zero solve_batch calls" do
      with_resolution_batch_project do |_dir, definition, batch|
        with_resolution_batch_server("success") do |client, log|
          resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
          resolution.unlock = true
          resolution.resolve!.map(&.name).should eq(["alpha"])
          resolution_batch_log(log).count { |entry| entry["op"] == "solve_batch" }.should eq(0)
        end
      end
    end

    it "backfills chosen specs, platform extras, edges and variants from the response" do
      with_resolution_batch_project do |_dir, definition, batch|
        with_resolution_batch_server("variants") do |client, log|
          resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
          resolution.added_platforms = ["ruby"]
          specs = resolution.resolve!

          specs.size.should eq(1)
          specs.first.platform.should eq(Gem::Platform.local.to_s)
          specs.first.checksum.should be_nil
          resolution.lock_extra_specs.size.should eq(1)
          resolution.lock_extra_specs.first.platform.should be_nil
          resolution.lock_extra_specs.first.checksum.should be_nil

          request = resolution_batch_log(log).find { |entry| entry["op"] == "solve_batch" }.not_nil!["payload"]
          request["candidate_closure"]["candidate_count"].as_i.should eq(2)
        end
      end
    end

    it "reads locked_base from the current lockfile before reuse probes" do
      with_resolution_batch_project(true) do |dir, definition, batch|
        with_resolution_batch_server("success") do |client, log|
          resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
          resolution.resolve!
          payload = resolution_batch_log(log).find { |entry| entry["op"] == "solve_batch" }.not_nil!["payload"]
          locked = payload["locked_base"]["specs"].as_a
          locked.size.should eq(1)
          locked.first["name"].as_s.should eq("alpha")
          locked.first["version"].as_s.should eq("1.0.0")
          locked.first["platform"].as_s.should eq("ruby")
          locked.first["source_id"].as_s.should eq("default")
          locked.first["checksum"].raw.should be_nil
        end
      end
    end

    it "silently falls back for protocol, schema, identity and closure mismatches" do
      %w[unknown_op bad_schema bad_edge bad_identity bad_closure bad_digest].each do |mode|
        with_resolution_batch_project do |_dir, definition, batch|
          with_resolution_batch_server(mode) do |client, log|
            resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
            resolution.resolve!.map(&.name).should eq(["alpha"])
            entries = resolution_batch_log(log)
            entries.count { |entry| entry["op"] == "solve_batch" }.should eq(1)
            entries.count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)
          end
        end
      end
    end

    it "falls back atomically when a later chosen group spans multiple sources" do
      dependency = %(gem "alpha", ">= 0"\ngem "beta", ">= 0")
      with_resolution_batch_project(dependency: dependency, beta: true) do |_dir, definition, batch|
        raw = JSON.parse(batch.evaluation.to_json)
        raw["dependencies"].as_a.each { |dependency| dependency.as_h["source"] = JSON::Any.new(nil) }
        first = raw["sources"].as_a.find { |source| source["type"].as_s == "Rubygems" }.not_nil!
        first.as_h["name"] = JSON::Any.new(nil)
        second = JSON.parse(first.to_json)
        second.as_h["name"] = JSON::Any.new("secondary")
        raw.as_h["sources"] = JSON::Any.new([first, second])
        evaluation = Celerite::Bridge::GemfileEvaluation.from_json(raw.to_json)
        with_resolution_batch_server("cross_source") do |client, log|
          resolution = Resolution.from_evaluation(definition, evaluation, client, batch.fingerprint)
          specs = resolution.resolve!

          specs.map(&.name).should eq(["alpha", "beta"])
          resolution.resolved_specs.map(&.name).should eq(["alpha", "beta"])
          resolution.build_base_requirements(Set(String).new).keys.sort.should eq(["alpha", "beta"])
          entries = resolution_batch_log(log)
          entries.count { |entry| entry["op"] == "solve_batch" }.should eq(1)
          entries.count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)
        end
      end
    end

    it "does not fall back for semantic requirements, Ruby or platform failures" do
      %w[requirements_conflict ruby_incompatible platform_unavailable].each do |category|
        with_resolution_batch_project do |_dir, definition, batch|
          with_resolution_batch_server(category) do |client, log|
            resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
            if category == "platform_unavailable"
              expect_raises(GemNotFoundError) { resolution.resolve! }
            else
              expect_raises(SolveFailureError) { resolution.resolve! }
            end
            entries = resolution_batch_log(log)
            entries.count { |entry| entry["op"] == "solve_batch" }.should eq(1)
            entries.count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)
          end
        end
      end
    end

    it "falls back for an unknown semantic category without a second evaluation" do
      with_resolution_batch_project do |_dir, definition, batch|
        with_resolution_batch_server("unknown_failure") do |client, log|
          resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
          resolution.resolve!.map(&.name).should eq(["alpha"])
          entries = resolution_batch_log(log)
          entries.count { |entry| entry["op"] == "solve_batch" }.should eq(1)
          entries.count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)
        end
      end
    end

    it "accepts an empty requirement set and returns an empty chosen set" do
      with_resolution_batch_project(dependency: "") do |_dir, definition, batch|
        with_resolution_batch_server("success") do |client, log|
          resolution = Resolution.from_evaluation(definition, batch.evaluation, client, batch.fingerprint)
          resolution.resolve!.should be_empty
          entries = resolution_batch_log(log)
          entries.count { |entry| entry["op"] == "solve_batch" }.should eq(1)
          entries.count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)
          payload = entries.find { |entry| entry["op"] == "solve_batch" }.not_nil!["payload"]
          payload["requirements"].as_a.should be_empty
          payload["candidate_closure"]["candidate_count"].as_i.should eq(0)
        end
      end
    end

    it "keeps multiple named sources without a default source on the legacy path" do
      with_resolution_batch_project do |_dir, definition, batch|
        raw = JSON.parse(batch.evaluation.to_json)
        first = raw["sources"].as_a.first
        first.as_h["name"] = JSON::Any.new("primary")
        second = JSON.parse(first.to_json)
        second.as_h["name"] = JSON::Any.new("secondary")
        raw.as_h["sources"] = JSON::Any.new([first, second])
        evaluation = Celerite::Bridge::GemfileEvaluation.from_json(raw.to_json)
        with_resolution_batch_server("success") do |client, log|
          resolution = Resolution.from_evaluation(definition, evaluation, client, batch.fingerprint)
          resolution.resolve!.map(&.name).should eq(["alpha"])
          entries = resolution_batch_log(log)
          entries.count { |entry| entry["op"] == "solve_batch" }.should eq(0)
          entries.count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)
        end
      end
    end

    it "keeps query or fragment source identities on the legacy path" do
      with_resolution_batch_project do |_dir, definition, batch|
        raw = JSON.parse(batch.evaluation.to_json)
        source = raw["sources"].as_a.first.as_h
        remote = "#{source["remotes"].as_a.first.as_s}?cache=1#section"
        source["remote"] = JSON::Any.new(remote)
        source["remotes"] = JSON::Any.new([JSON::Any.new(remote)])
        evaluation = Celerite::Bridge::GemfileEvaluation.from_json(raw.to_json)
        with_resolution_batch_server("success") do |client, log|
          resolution = Resolution.from_evaluation(definition, evaluation, client, batch.fingerprint)
          resolution.resolve!.map(&.name).should eq(["alpha"])
          entries = resolution_batch_log(log)
          entries.count { |entry| entry["op"] == "solve_batch" }.should eq(0)
          entries.count { |entry| entry["op"] == "evaluate_batch" }.should eq(0)
        end
      end
    end
  end
end

private def resolution_batch_local_checksum : String
  "a" * 64
end

private def resolution_batch_ruby_checksum : String
  "b" * 64
end

private def resolution_batch_evaluation(evaluation : Celerite::Bridge::GemfileEvaluation, version : String) : Celerite::Bridge::GemfileEvaluation
  raw = JSON.parse(evaluation.to_json)
  raw.as_h["bundler_version"] = JSON::Any.new(version)
  Celerite::Bridge::GemfileEvaluation.from_json(raw.to_json)
end

private def with_resolution_batch_project(locked : Bool = false, dependency : String = %(gem "alpha", ">= 0"), beta : Bool = false, & : String, Celerite::Definition, Celerite::Bridge::BatchGemfileEvaluation -> Nil) : Nil
  pending! "ruby not available" unless ruby_available?
  platform = Celerite::Gem::Platform.local.to_s
  files = {
    "Gemfile"            => "",
    "index/specs.4.8.gz" => "",
    "index/versions"     => "created_at: 2026-11-01T00:00:00Z\r\n---\r\nalpha 1.0.0-#{platform},1.0.0 info\r\n",
    "index/info/alpha"   => "---\n1.0.0-#{platform} |ruby:< 4,checksum:#{resolution_batch_local_checksum}\n1.0.0 |ruby:< 4,checksum:#{resolution_batch_ruby_checksum}\n",
  }
  if beta
    files["index/versions"] = "#{files["index/versions"]}beta 1.0.0-#{platform},1.0.0 info\r\n"
    files["index/info/beta"] = "---\n1.0.0-#{platform} |ruby:< 4,checksum:#{resolution_batch_local_checksum}\n1.0.0 |ruby:< 4,checksum:#{resolution_batch_ruby_checksum}\n"
  end
  with_project(files) do |dir|
    index = File.join(dir, "index").gsub(/\\/, "/")
    remote = file_source_url(index)
    gemfile = File.join(dir, "Gemfile")
    File.write(gemfile, %(source "#{remote}"\n\n#{dependency}\n))
    if locked
      File.write(File.join(dir, "Gemfile.lock"), [
        "GEM",
        "  remote: #{remote}",
        "  specs:",
        "    alpha (1.0.0)",
        "",
        "PLATFORMS",
        "  ruby",
        "",
        "DEPENDENCIES",
        "  alpha",
        "",
        "BUNDLED WITH",
        "   4.0.24",
        "",
      ].join("\n"))
    end
    ENV["CELERITE_REFERENCE_BUNDLER_VERSION"] = "4.0.24"
    with_client do |client|
      batch = client.evaluate_batch(gemfile, ["fingerprint"])
      batch.evaluation.bundler_version.should eq("4.0.24")
      batch.fingerprint.should_not be_nil
      batch.fingerprint.not_nil!.state.should eq(Celerite::EvalFingerprint::State::Deterministic)
      yield dir, Celerite::Definition.build, batch
    end
  end
end

private def resolution_batch_log(path : String) : Array(JSON::Any)
  return [] of JSON::Any unless File.exists?(path)
  File.read_lines(path).map { |line| JSON.parse(line) }
end

private def with_resolution_batch_server(mode : String, & : Celerite::Bridge::Client, String -> Nil) : Nil
  pending! "ruby not available" unless ruby_available?
  dir = File.join(Dir.tempdir, "celerite-resolution-batch-#{Process.pid}-#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(dir)
  log = File.join(dir, "requests.jsonl")
  server = File.join(dir, "server.rb")
  File.write(server, <<-RUBY)
    require "json"
    require "rubygems"
    mode = #{mode.inspect}
    log = #{log.inspect}
    environment = {
      "ruby_version" => "3.3.0", "ruby_description" => "ruby 3.3.0",
      "ruby_env_line" => "ruby 3.3.0", "engine" => "ruby",
      "engine_version" => "3.3.0", "rubygems_version" => "3.5.0",
      "ruby_revision" => "test", "patchlevel" => "0", "platform" => "ruby",
      "ruby_exe" => "ruby", "gem_paths" => [], "default_gem_dir" => "/gems",
      "loaded_bundler_version" => "4.0.24"
    }
    chosen_output = lambda do |candidate|
      candidate.slice("name", "version", "platform", "dependencies", "checksum",
        "required_ruby_version", "required_rubygems_version").merge("source_id" => candidate["source_id"])
    end
    STDIN.each_line do |line|
      envelope = JSON.parse(line)
      File.open(log, "a") { |io| io.puts JSON.generate("op" => envelope["op"], "payload" => envelope["payload"]) }
      if mode == "unknown_op" && envelope["op"] == "solve_batch"
        STDOUT.puts JSON.generate("proto" => envelope["proto"], "id" => envelope["id"], "ok" => false,
          "error" => {"class" => "UnknownOp", "message" => "unsupported op"})
        STDOUT.flush
        next
      end
      result = case envelope["op"]
      when "ruby_environment"
        environment
      when "installed_specs"
        []
      when "solve_batch"
        payload = envelope["payload"]
        candidates = []
        payload["candidates_by_source"].each do |source_id, values|
          values.each { |value| candidates << value.merge("source_id" => source_id) }
        end
        chosen = []
        payload["requirements"].each do |requirement|
          pool = candidates.select { |candidate| candidate["name"] == requirement["name"] }
          if requirement["source_id"] && !(mode == "cross_source" && requirement["name"] == "beta")
            pool = pool.select { |candidate| candidate["source_id"] == requirement["source_id"] }
          end
          requirement_obj = Gem::Requirement.new(requirement["requirements"].join(", "))
          pool = pool.select { |candidate| requirement_obj.satisfied_by?(Gem::Version.new(candidate["version"])) }
          next if pool.empty?
          version = pool.map { |candidate| Gem::Version.new(candidate["version"]) }.max
          matches = pool.select { |candidate| Gem::Version.new(candidate["version"]) == version }
          if mode == "cross_source" && requirement["name"] == "beta"
            chosen.concat([
              matches.find { |candidate| candidate["platform"] == "ruby" && candidate["source_id"] == "default" },
              matches.find { |candidate| candidate["platform"] != "ruby" && candidate["source_id"] != "default" },
            ].compact)
          else
            matches = matches.select { |candidate| candidate["platform"] == "ruby" } if mode != "variants" && matches.any? { |candidate| candidate["platform"] == "ruby" }
            chosen.concat(mode == "variants" ? matches : matches.first(1))
          end
        end
        chosen.uniq! { |candidate| [candidate["name"], candidate["version"], candidate["platform"], candidate["source_id"]] }
        chosen_values = chosen.map { |candidate| chosen_output.call(candidate) }
        edges = []
        payload["requirements"].each do |requirement|
          chosen.select { |candidate| candidate["name"] == requirement["name"] }.each do |candidate|
            edges << {"from" => "root", "to" => "\#{candidate["name"]}/\#{candidate["version"]}/\#{candidate["platform"]}",
              "requirements" => requirement["requirements"].sort}
          end
        end
        chosen.each do |source|
          source["dependencies"].each do |dependency|
            chosen.select { |target| target["name"] == dependency["name"] }.each do |target|
              edges << {"from" => "\#{source["name"]}/\#{source["version"]}/\#{source["platform"]}",
                "to" => "\#{target["name"]}/\#{target["version"]}/\#{target["platform"]}",
                "requirements" => dependency["requirements"].sort}
            end
          end
        end
        edges.uniq!
        variants = {}
        chosen.group_by { |candidate| [candidate["name"], candidate["version"]] }.each do |_key, group|
          next if group.size < 2
          group.each do |candidate|
            variants["\#{candidate["name"]}/\#{candidate["version"]}/\#{candidate["platform"]}"] =
              group.reject { |item| item.equal?(candidate) }.map { |item| item["platform"] }.sort
          end
        end
        if %w[requirements_conflict ruby_incompatible platform_unavailable unknown_failure].include?(mode)
          failure = {"class" => "Bundler::SolveFailure", "message" => "semantic failure",
            "category" => (mode == "unknown_failure" ? "unknown" : mode), "incompatibilities" => []}
          {"schema" => payload["schema"], "ok" => false, "result" => {"chosen" => [], "edges" => [],
            "variants" => {}, "failure" => failure, "stats" => {}}}
        else
          edges = [] if mode == "bad_edge"
          chosen_values = [] if mode == "bad_closure"
          chosen_values[0]["source_id"] = "source-9999" if mode == "bad_identity" && !chosen_values.empty?
          stats = {"candidate_bytes" => payload.to_json.bytesize, "candidate_count" => candidates.size,
            "source_count" => payload["candidates_by_source"].size,
            "name_count" => candidates.map { |candidate| candidate["name"] }.uniq.size,
            "materialize_ms" => 1.0, "solve_ms" => 1.0,
            "candidate_digest" => (mode == "bad_digest" ? "0" * 64 : payload["candidate_closure"]["digest"]),
            "bridge_pid" => Process.pid,
            "relaxations" => [], "fallback_reason" => nil}
          {"schema" => (mode == "bad_schema" ? "wrong/schema" : payload["schema"]), "ok" => true,
            "result" => {"chosen" => chosen_values, "edges" => edges, "variants" => variants,
              "failure" => nil, "stats" => stats}}
        end
      else
        raise "unexpected bridge op: \#{envelope["op"]}"
      end
      STDOUT.puts JSON.generate("proto" => envelope["proto"], "id" => envelope["id"], "ok" => true, "result" => result)
      STDOUT.flush
    end
  RUBY
  client = Celerite::Bridge::Client.new(server_path: server)
  begin
    yield client, log
  ensure
    client.close
    FileUtils.rm_rf(dir)
  end
end
