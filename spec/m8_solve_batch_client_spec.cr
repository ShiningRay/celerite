require "./spec_helper"
require "../src/celerite"
require "base64"
require "file_utils"

alias SolveBatch = Celerite::Bridge::SolveBatch

private def solve_batch_source(source_id : String = "default", name : String = source_id,
                               type : String = "Rubygems", materialization : String = "pure_data") : JSON::Any
  JSON::Any.new({
    "source_id"       => JSON::Any.new(source_id),
    "type"            => JSON::Any.new(type),
    "name"            => JSON::Any.new(name),
    "identity_sha256" => JSON::Any.new("0" * 64),
    "uri_redacted"    => JSON::Any.new("https://rubygems.org"),
    "remotes"         => JSON::Any.new([] of JSON::Any),
    "path"            => JSON::Any.new(nil),
    "revision"        => JSON::Any.new(nil),
    "ref"             => JSON::Any.new(nil),
    "branch"          => JSON::Any.new(nil),
    "tag"             => JSON::Any.new(nil),
    "glob"            => JSON::Any.new(nil),
    "submodules"      => JSON::Any.new(nil),
    "plugin_type"     => JSON::Any.new(nil),
    "lock_options"    => JSON::Any.new({} of String => JSON::Any),
    "materialization" => JSON::Any.new(materialization),
  })
end

private def solve_batch_candidate(name : String = "alpha") : JSON::Any
  JSON::Any.new({
    "name"                      => JSON::Any.new(name),
    "version"                   => JSON::Any.new("1.0"),
    "platform"                  => JSON::Any.new("ruby"),
    "dependencies"              => JSON::Any.new([] of JSON::Any),
    "required_ruby_version"     => JSON::Any.new(nil),
    "required_rubygems_version" => JSON::Any.new(nil),
    "created_at"                => JSON::Any.new(nil),
    "checksum"                  => JSON::Any.new(nil),
  })
end

private def solve_batch_payload(candidate : JSON::Any = solve_batch_candidate) : JSON::Any
  candidates = {"default" => [candidate]}
  digest = SolveBatch::Digest.candidate_digest(candidates)
  JSON::Any.new({
    "schema"     => JSON::Any.new(SolveBatch::SCHEMA),
    "evaluation" => JSON::Any.new({
      "gemfile" => JSON::Any.new({
        "path_sha256" => JSON::Any.new("a" * 64),
        "sha256"      => JSON::Any.new("b" * 64),
      }),
      "fingerprint" => JSON::Any.new({
        "format"       => JSON::Any.new("celerite-eval-v1"),
        "digest"       => JSON::Any.new("c" * 64),
        "state"        => JSON::Any.new("deterministic"),
        "state_reason" => JSON::Any.new(nil),
        "verify_files" => JSON::Any.new([] of JSON::Any),
        "runtime"      => JSON::Any.new({} of String => JSON::Any),
        "config"       => JSON::Any.new({} of String => JSON::Any),
      }),
      "sources" => JSON::Any.new([solve_batch_source]),
      "plugins" => JSON::Any.new([] of JSON::Any),
      "groups"  => JSON::Any.new({
        "with"     => JSON::Any.new([] of JSON::Any),
        "without"  => JSON::Any.new([] of JSON::Any),
        "optional" => JSON::Any.new([] of JSON::Any),
        "all"      => JSON::Any.new([] of JSON::Any),
      }),
    }),
    "requirements" => JSON::Any.new([JSON::Any.new({
      "name"                => JSON::Any.new(candidate["name"].as_s),
      "requirements"        => JSON::Any.new([JSON::Any.new(">= 0")]),
      "source_id"           => JSON::Any.new(nil),
      "groups"              => JSON::Any.new([JSON::Any.new("default")]),
      "platforms"           => JSON::Any.new([JSON::Any.new("ruby")]),
      "autorequire"         => JSON::Any.new([] of JSON::Any),
      "force_ruby_platform" => JSON::Any.new(false),
      "gemspec_dev_dep"     => JSON::Any.new(false),
      "direct"              => JSON::Any.new(true),
    })]),
    "candidates_by_source" => JSON::Any.new({
      "default" => JSON::Any.new([candidate]),
    }),
    "locked_base" => JSON::Any.new({
      "sha256" => JSON::Any.new(SolveBatch::Digest.locked_digest([] of JSON::Any)),
      "specs"  => JSON::Any.new([] of JSON::Any),
    }),
    "promotion" => JSON::Any.new({
      "level"        => JSON::Any.new("patch"),
      "strict"       => JSON::Any.new(true),
      "pre"          => JSON::Any.new(false),
      "unlock"       => JSON::Any.new(false),
      "conservative" => JSON::Any.new(true),
      "prefer_local" => JSON::Any.new(false),
      "local_only"   => JSON::Any.new(false),
    }),
    "constraints" => JSON::Any.new({
      "ruby_version"        => JSON::Any.new("3.3.0"),
      "ruby_patchlevel"     => JSON::Any.new(nil),
      "ruby_engine"         => JSON::Any.new("ruby"),
      "ruby_engine_version" => JSON::Any.new("3.3.0"),
      "rubygems_version"    => JSON::Any.new("3.5.0"),
      "bundler_version"     => JSON::Any.new("4.0.24"),
      "platforms"           => JSON::Any.new([JSON::Any.new("ruby")]),
      "added_platforms"     => JSON::Any.new([] of JSON::Any),
      "removed_platforms"   => JSON::Any.new([] of JSON::Any),
      "force_ruby_platform" => JSON::Any.new(false),
    }),
    "candidate_closure" => JSON::Any.new({
      "complete"        => JSON::Any.new(true),
      "digest"          => JSON::Any.new(digest),
      "name_count"      => JSON::Any.new(1_i64),
      "candidate_count" => JSON::Any.new(1_i64),
    }),
    "limits" => JSON::Any.new({"timeout_ms" => JSON::Any.new(5_000_i64)}),
  })
end

private def solve_batch_request(payload : JSON::Any = solve_batch_payload) : SolveBatch::Request
  SolveBatch::Request.parse(payload)
end

private def set_solve_batch_field(value : JSON::Any, path : String, replacement : JSON::Any) : Nil
  keys = path.split('.')
  current = value
  keys[0...-1].each { |key| current = current.as_h[key] }
  current.as_h[keys.last] = replacement
end

private def solve_batch_response(request : SolveBatch::Request) : JSON::Any
  candidate = request.payload["candidates_by_source"]["default"].as_a.first
  JSON::Any.new({
    "schema" => JSON::Any.new(SolveBatch::SCHEMA),
    "ok"     => JSON::Any.new(true),
    "result" => JSON::Any.new({
      "chosen" => JSON::Any.new([JSON::Any.new({
        "name"                      => candidate["name"],
        "version"                   => candidate["version"],
        "platform"                  => candidate["platform"],
        "source_id"                 => JSON::Any.new("default"),
        "dependencies"              => candidate["dependencies"],
        "checksum"                  => candidate["checksum"],
        "required_ruby_version"     => candidate["required_ruby_version"],
        "required_rubygems_version" => candidate["required_rubygems_version"],
      })]),
      "edges" => JSON::Any.new([JSON::Any.new({
        "from"         => JSON::Any.new("root"),
        "to"           => JSON::Any.new("alpha/1.0/ruby"),
        "requirements" => JSON::Any.new([JSON::Any.new(">= 0")]),
      })]),
      "variants" => JSON::Any.new({} of String => JSON::Any),
      "failure"  => JSON::Any.new(nil),
      "stats"    => JSON::Any.new({
        "candidate_bytes"  => JSON::Any.new(1_i64),
        "candidate_count"  => JSON::Any.new(1_i64),
        "source_count"     => JSON::Any.new(1_i64),
        "name_count"       => JSON::Any.new(1_i64),
        "materialize_ms"   => JSON::Any.new(1.0),
        "solve_ms"         => JSON::Any.new(1.0),
        "candidate_digest" => JSON::Any.new(request.candidate_digest),
        "bridge_pid"       => JSON::Any.new(123_i64),
        "relaxations"      => JSON::Any.new([] of JSON::Any),
        "fallback_reason"  => JSON::Any.new(nil),
      }),
    }),
  })
end

private def solve_batch_ruby_available? : Bool
  !Process.find_executable(ENV["CELERITE_RUBY"]? || "ruby").nil?
end

private def with_solve_batch_server(response : JSON::Any, & : Celerite::Bridge::Client, String -> Nil) : Nil
  pending! "ruby not available" unless solve_batch_ruby_available?
  dir = File.join(Dir.tempdir, "celerite-solve-batch-#{Process.pid}-#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(dir)
  marker = File.join(dir, "received")
  server = File.join(dir, "server.rb")
  encoded = Base64.strict_encode(response.to_json)
  File.write(server, <<-RUBY)
    require "json"
    require "base64"
    STDIN.each_line do |line|
      envelope = JSON.parse(line)
      File.write(#{marker.inspect}, "received")
      result = JSON.parse(Base64.decode64(#{encoded.inspect}))
      STDOUT.puts JSON.generate({"proto" => envelope["proto"], "id" => envelope["id"], "ok" => true, "result" => result})
      STDOUT.flush
    end
  RUBY
  client = Celerite::Bridge::Client.new(server_path: server)
  begin
    yield client, marker
  ensure
    client.close
    FileUtils.rm_rf(dir)
  end
end

module Celerite
  describe Bridge::SolveBatch do
    it "matches Ruby canonical JSON bytes and digest" do
      fixture = JSON.parse(File.read(File.join(__DIR__, "fixtures", "m8_solve_batch", "canonical.json")))
      canonical = fixture["canonical"]
      SolveBatch::Canonical.json(canonical["input"]).should eq(canonical["bytes"].as_s)
      SolveBatch::Canonical.digest(canonical["input"]).should eq(canonical["sha256"].as_s)
    end

    it "matches Ruby candidate canonicalization, dependency order and checksum case" do
      fixture = JSON.parse(File.read(File.join(__DIR__, "fixtures", "m8_solve_batch", "canonical.json")))
      digest = fixture["candidate_digest"]
      input = {} of String => Array(JSON::Any)
      digest["input"].as_h.each do |source_id, candidates|
        input[source_id] = candidates.as_a
      end
      SolveBatch::Digest.candidate_digest(input).should eq(digest["sha256"].as_s)
      normalized = SolveBatch::Digest.candidates_by_source(digest["input"], ["default"])
      SolveBatch::Canonical.json(JSON::Any.new(normalized.transform_values { |value| JSON::Any.new(value) })).should eq(digest["bytes"].as_s)
    end

    it "assigns source IDs stably independent of input order" do
      sources = [solve_batch_source("b"), solve_batch_source("default"), solve_batch_source("a")]
      forward = SolveBatch::SourceRegistry.assign(sources)
      reverse = SolveBatch::SourceRegistry.assign(sources.reverse)
      forward.should eq(reverse)
      forward.map { |source| source["source_id"].as_s }.should eq(["default", "source-0001", "source-0002"])
      forward[1]["name"].as_s.should eq("a")
      forward[2]["name"].as_s.should eq("b")
    end

    it "matches Ruby source identities under shuffled sources and remotes" do
      fixture = JSON.parse(File.read(File.join(__DIR__, "fixtures", "m8_solve_batch", "canonical.json")))
      identity = fixture["source_identity"]
      sources = identity["sources"].as_a
      forward = SolveBatch::SourceRegistry.assign(sources)
      shuffled = sources.reverse.map do |source|
        raw = source.as_h
        raw["remotes"] = JSON::Any.new(raw["remotes"].as_a.reverse)
        raw["source_id"] = JSON::Any.new(raw["name"].as_s == "zeta" ? "default" : "ignored-alpha")
        JSON::Any.new(raw)
      end
      reverse = SolveBatch::SourceRegistry.assign(shuffled)
      expected = identity["expected"].as_h
      forward.each do |source|
        source["identity_sha256"].as_s.should eq(expected[source["name"].as_s].as_s)
      end
      reverse.map { |source| {source["name"].as_s, source["identity_sha256"].as_s} }.sort.should eq(
        forward.map { |source| {source["name"].as_s, source["identity_sha256"].as_s} }.sort
      )
    end

    it "recomputes identity after source IDs include source_id" do
      assigned = SolveBatch::SourceRegistry.assign([solve_batch_source("custom", "custom")])
      original_identity = assigned[0]["identity_sha256"].as_s
      original_identity.should_not eq("0" * 64)
      source = assigned[0].as_h
      source["source_id"] = JSON::Any.new("source-9999")
      source.delete("identity_sha256")
      SolveBatch::SourceRegistry.identity(source).should_not eq(original_identity)
    end

    it "rejects duplicate source IDs and multi-source registries without default" do
      duplicate = solve_batch_payload
      set_solve_batch_field(duplicate, "evaluation.sources", JSON::Any.new([solve_batch_source, solve_batch_source]))
      expect_raises(SolveBatch::ValidationError, "duplicate source_id") { SolveBatch::Request.parse(duplicate) }

      missing_default = solve_batch_payload
      set_solve_batch_field(missing_default, "evaluation.sources", JSON::Any.new([solve_batch_source("a"), solve_batch_source("b")]))
      expect_raises(SolveBatch::ValidationError, "multiple sources require a default source") { SolveBatch::Request.parse(missing_default) }
    end

    it "only considers deterministic Bundler 4.0.24 Rubygems pure_data eligible" do
      constraints = solve_batch_payload["constraints"]
      fingerprint = solve_batch_payload["evaluation"]["fingerprint"]
      promotion = solve_batch_payload["promotion"]
      SolveBatch::Eligibility.eligible?(constraints, fingerprint, [solve_batch_source], promotion).should be_true

      [{"Path", "path"}, {"Git", "git"}, {"Plugin", "plugin"}, {"Metadata", "unknown"}, {"Unknown", "unknown"}].each do |type, materialization|
        SolveBatch::Eligibility.eligible?(constraints, fingerprint, [solve_batch_source(type: type, materialization: materialization)], promotion).should be_false
        payload = solve_batch_payload
        set_solve_batch_field(payload, "evaluation.sources", JSON::Any.new([solve_batch_source(type: type, materialization: materialization)]))
        expect_raises(SolveBatch::IneligibleError) { SolveBatch::Request.parse(payload) }
      end
    end

    it "rejects nondeterministic, wrong Bundler and local promotion requests" do
      payload = solve_batch_payload
      set_solve_batch_field(payload, "evaluation.fingerprint.state", JSON::Any.new("unknown"))
      expect_raises(SolveBatch::IneligibleError) { SolveBatch::Request.parse(payload) }

      payload = solve_batch_payload
      set_solve_batch_field(payload, "constraints.bundler_version", JSON::Any.new("4.0.23"))
      expect_raises(SolveBatch::ValidationError) { SolveBatch::Request.parse(payload) }

      payload = solve_batch_payload
      set_solve_batch_field(payload, "promotion.prefer_local", JSON::Any.new(true))
      expect_raises(SolveBatch::IneligibleError) { SolveBatch::Request.parse(payload) }
    end

    it "enforces request byte limits before parsing or transport" do
      SolveBatch::Request.validate_bytes!(SolveBatch::MAX_REQUEST_BYTES)
      expect_raises(SolveBatch::TooLargeError) { SolveBatch::Request.validate_bytes!(SolveBatch::MAX_REQUEST_BYTES + 1) }
      expect_raises(SolveBatch::TooLargeError) { SolveBatch::Request.parse(" " * (SolveBatch::MAX_REQUEST_BYTES + 1)) }
    end

    it "rejects credential-bearing URIs and values without echoing the secret" do
      payload = solve_batch_payload
      payload["evaluation"]["sources"].as_a.first.as_h["uri_redacted"] = JSON::Any.new("https://user:credential-sentinel@example.org")
      error = expect_raises(SolveBatch::ValidationError) { SolveBatch::Request.parse(payload) }
      error.message.to_s.should_not contain("credential-sentinel")

      payload = solve_batch_payload
      set_solve_batch_field(payload, "evaluation.fingerprint.runtime", JSON::Any.new({"token" => JSON::Any.new("credential-sentinel")}))
      error = expect_raises(SolveBatch::ValidationError) { SolveBatch::Request.parse(payload) }
      error.message.to_s.should_not contain("credential-sentinel")

      payload = solve_batch_payload
      set_solve_batch_field(payload, "evaluation.fingerprint.runtime", JSON::Any.new({"uri" => JSON::Any.new("https://[")}))
      error = expect_raises(SolveBatch::ValidationError, "invalid URI") { SolveBatch::Request.parse(payload) }
      error.message.to_s.should_not contain("https://[")
    end

    it "keeps created_at absent instead of fabricating the current time" do
      absent = Celerite::CompactIndex::InfoEntry.new("1.0", nil, [] of Celerite::CompactIndex::InfoDependency, [] of Celerite::CompactIndex::InfoRequirement)
      absent.created_at.should be_nil
      spec = Celerite::Resolver::IndexSpec.new("alpha", Gem::Version.new("1.0"), Gem::Platform.new("ruby"), [] of Celerite::Resolver::DepSpec, Gem::Requirement.new)
      spec.created_at.should be_nil
      SolveBatch::Candidate.from_index_spec(spec).payload["created_at"].raw.should be_nil
    end

    it "preserves compact-index created_at through the optional IndexSpec state" do
      entry = Celerite::CompactIndex::InfoEntry.new("1.0", nil, [] of Celerite::CompactIndex::InfoDependency, [
        Celerite::CompactIndex::InfoRequirement.new("created_at", ["2024-01-02T03:04:05"]),
      ])
      timestamp = entry.created_at
      timestamp.should eq(Time.utc(2024, 1, 2, 3, 4, 5).to_unix)
      spec = Celerite::Resolver::IndexSpec.new("alpha", Gem::Version.new("1.0"), Gem::Platform.new("ruby"), [] of Celerite::Resolver::DepSpec, Gem::Requirement.new, created_at: timestamp)
      spec.created_at.should eq(timestamp)
      SolveBatch::Candidate.from_index_spec(spec).payload["created_at"].as_s.should eq("2024-01-02T03:04:05Z")
    end

    it "accepts a scripted successful response through the thin client" do
      request = solve_batch_request
      response = solve_batch_response(request)
      with_solve_batch_server(response) do |client, _marker|
        parsed = client.solve_batch(request)
        parsed.ok?.should be_true
        parsed.chosen.map(&.name).should eq(["alpha"])
        parsed.edges.map(&.to).should eq(["alpha/1.0/ruby"])
      end
    end

    it "accepts Ruby-compatible empty chosen for empty requirements" do
      payload = solve_batch_payload
      set_solve_batch_field(payload, "requirements", JSON::Any.new([] of JSON::Any))
      set_solve_batch_field(payload, "candidates_by_source", JSON::Any.new({} of String => JSON::Any))
      digest = SolveBatch::Digest.candidate_digest({} of String => Array(JSON::Any))
      set_solve_batch_field(payload, "candidate_closure.digest", JSON::Any.new(digest))
      set_solve_batch_field(payload, "candidate_closure.candidate_count", JSON::Any.new(0_i64))
      set_solve_batch_field(payload, "candidate_closure.name_count", JSON::Any.new(0_i64))
      request = solve_batch_request(payload)
      response = JSON::Any.new({
        "schema" => JSON::Any.new(SolveBatch::SCHEMA),
        "ok"     => JSON::Any.new(true),
        "result" => JSON::Any.new({
          "chosen"   => JSON::Any.new([] of JSON::Any),
          "edges"    => JSON::Any.new([] of JSON::Any),
          "variants" => JSON::Any.new({} of String => JSON::Any),
          "failure"  => JSON::Any.new(nil),
          "stats"    => JSON::Any.new({
            "candidate_bytes"  => JSON::Any.new(0_i64),
            "candidate_count"  => JSON::Any.new(0_i64),
            "source_count"     => JSON::Any.new(1_i64),
            "name_count"       => JSON::Any.new(0_i64),
            "materialize_ms"   => JSON::Any.new(0.0),
            "solve_ms"         => JSON::Any.new(0.0),
            "candidate_digest" => JSON::Any.new(digest),
            "bridge_pid"       => JSON::Any.new(123_i64),
            "relaxations"      => JSON::Any.new([] of JSON::Any),
            "fallback_reason"  => JSON::Any.new(nil),
          }),
        }),
      })
      with_solve_batch_server(response) do |client, _marker|
        parsed = client.solve_batch(request)
        parsed.ok?.should be_true
        parsed.chosen.should be_empty
        parsed.edges.should be_empty
      end
    end

    it "accepts bounded failure responses and rejects null failure stats" do
      request = solve_batch_request
      response = solve_batch_response(request)
      response.as_h["ok"] = JSON::Any.new(false)
      set_solve_batch_field(response, "result.chosen", JSON::Any.new([] of JSON::Any))
      set_solve_batch_field(response, "result.edges", JSON::Any.new([] of JSON::Any))
      set_solve_batch_field(response, "result.variants", JSON::Any.new({} of String => JSON::Any))
      set_solve_batch_field(response, "result.failure", JSON::Any.new({
        "class"             => JSON::Any.new("Bundler::GemNotFound"),
        "message"           => JSON::Any.new("bounded failure"),
        "category"          => JSON::Any.new("requirements_conflict"),
        "incompatibilities" => JSON::Any.new([] of JSON::Any),
      }))
      set_solve_batch_field(response, "result.stats", JSON::Any.new({} of String => JSON::Any))
      parsed = SolveBatch::Response.parse(response, request)
      parsed.ok?.should be_false
      parsed.failure.not_nil!.category.should eq("requirements_conflict")

      set_solve_batch_field(response, "result.stats", JSON::Any.new(nil))
      expect_raises(SolveBatch::ValidationError, "stats must be an object") { SolveBatch::Response.parse(response, request) }
    end

    it "rejects missing edges, unknown sources, wrong digests and wrong types" do
      request = solve_batch_request
      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.edges", JSON::Any.new([] of JSON::Any))
      expect_raises(SolveBatch::ProtocolError, "edges") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      response["result"]["chosen"].as_a.first.as_h["source_id"] = JSON::Any.new("source-9999")
      expect_raises(SolveBatch::ProtocolError, "unknown candidate or source") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.stats.candidate_digest", JSON::Any.new("0" * 64))
      expect_raises(SolveBatch::ProtocolError, "candidate_digest") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.stats.candidate_count", JSON::Any.new("1"))
      expect_raises(SolveBatch::ValidationError, "must be an integer") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.stats.candidate_bytes", JSON::Any.new(-1_i64))
      expect_raises(SolveBatch::ProtocolError, "nonnegative") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.stats.materialize_ms", JSON::Any.new(-1.0))
      expect_raises(SolveBatch::ProtocolError, "timings must be nonnegative") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.stats.bridge_pid", JSON::Any.new(-1_i64))
      expect_raises(SolveBatch::ProtocolError, "nonnegative") { SolveBatch::Response.parse(response, request) }
    end

    it "rejects unknown and missing response fields, empty chosen and truncated JSON" do
      request = solve_batch_request
      response = solve_batch_response(request)
      set_solve_batch_field(response, "extra", JSON::Any.new(true))
      expect_raises(SolveBatch::ValidationError, "unknown") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      response.as_h.delete("schema")
      expect_raises(SolveBatch::ValidationError, "required") { SolveBatch::Response.parse(response, request) }

      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.chosen", JSON::Any.new([] of JSON::Any))
      expect_raises(SolveBatch::ProtocolError, "no chosen candidate") { SolveBatch::Response.parse(response, request) }

      raw = solve_batch_response(request).to_json
      expect_raises(SolveBatch::ProtocolError, "truncated") { SolveBatch::Response.parse(raw[0...-1], request) }
    end

    it "rejects oversized responses" do
      request = solve_batch_request
      expect_raises(SolveBatch::TooLargeError, "response exceeds") do
        SolveBatch::Response.parse(" " * (SolveBatch::MAX_RESPONSE_BYTES + 1), request)
      end
    end

    it "does not send a request above the 32 MiB preflight limit" do
      request = solve_batch_request
      request.payload.as_h["padding"] = JSON::Any.new("x" * SolveBatch::MAX_REQUEST_BYTES)
      response = solve_batch_response(solve_batch_request)
      with_solve_batch_server(response) do |client, marker|
        expect_raises(SolveBatch::TooLargeError) { client.solve_batch(request) }
        File.exists?(marker).should be_false
      end
    end

    it "rejects an 8 MiB response overflow in the client transport" do
      request = solve_batch_request
      response = solve_batch_response(request)
      set_solve_batch_field(response, "result.stats.fallback_reason", JSON::Any.new("x" * SolveBatch::MAX_RESPONSE_BYTES))
      with_solve_batch_server(response) do |client, _marker|
        expect_raises(Celerite::Bridge::BatchTooLargeError, "solve_batch response is") { client.solve_batch(request) }
      end
    end

    it "keeps diagnostics opt-in and free of payload, environment and backtrace" do
      previous = ENV["CELERITE_SOLVE_BATCH_DIAG"]?
      ENV["CELERITE_SOLVE_BATCH_DIAG_SECRET"] = "diagnostic-sentinel"
      begin
        ENV["CELERITE_SOLVE_BATCH_DIAG"] = nil
        silent = IO::Memory.new
        SolveBatch::Diagnostics.emit("failure", "ineligible", silent)
        silent.to_s.should be_empty

        ENV["CELERITE_SOLVE_BATCH_DIAG"] = "1"
        output = IO::Memory.new
        SolveBatch::Diagnostics.emit("failure", "ineligible", output)
        output.to_s.should contain("event=failure category=ineligible")
        output.to_s.should_not contain("diagnostic-sentinel")
        output.to_s.should_not contain("payload")
        output.to_s.should_not contain("backtrace")

        redacted = IO::Memory.new
        SolveBatch::Diagnostics.emit("failure", "diagnostic-sentinel", redacted)
        redacted.to_s.should contain("category=unknown")
        redacted.to_s.should_not contain("diagnostic-sentinel")
      ensure
        ENV["CELERITE_SOLVE_BATCH_DIAG"] = previous
        ENV.delete("CELERITE_SOLVE_BATCH_DIAG_SECRET")
      end
    end
  end
end
