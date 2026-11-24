#!/usr/bin/env ruby
# frozen_string_literal: true

# Seals a fixture case into the public celerite.solve_batch/3 request. The
# resolver itself remains a separate boundary: this helper only computes the
# canonical source, candidate-closure, and locked-base digests required by S1.
require_relative "../assets/bridge/solve_batch"

ROOT = File.expand_path("..", __dir__)
FIXTURE_PATH = File.join(ROOT, "fixtures", "solve_batch", "cases.json")

def canonical(value)
  Celerite::SolveBatch.canonical_json(value)
end

def digest(value)
  Digest::SHA256.hexdigest(canonical(value))
end

def candidate_closure(requirements, locked_specs, candidates)
  by_name = candidates.group_by {|candidate| candidate.fetch("name") }
  queue = requirements.map {|requirement| requirement.fetch("name") }
  queue.concat(locked_specs.map {|spec| spec.fetch("name") })
  names = {}
  until queue.empty?
    name = queue.shift
    next if names.key?(name)

    names[name] = true
    Array(by_name[name]).each do |candidate|
      candidate.fetch("dependencies").each {|dependency| queue << dependency.fetch("name") }
    end
  end
  candidates.select {|candidate| names.key?(candidate.fetch("name")) }
end

def seal(case_name)
  fixture = JSON.parse(File.read(FIXTURE_PATH))
  test_case = fixture.fetch("cases").find {|entry| entry.fetch("name") == case_name }
  raise ArgumentError, "unknown fixture case #{case_name.inspect}" unless test_case

  source = Marshal.load(Marshal.dump(fixture.fetch("common").fetch("source")))
  source["identity_sha256"] = Celerite::SolveBatch.source_identity(source)
  requirements = Marshal.load(Marshal.dump(test_case.fetch("requirements")))
  locked_specs = Marshal.load(Marshal.dump(test_case.fetch("locked_specs")))
  candidates = candidate_closure(
    requirements,
    locked_specs,
    Marshal.load(Marshal.dump(fixture.fetch("candidate_sets").fetch(test_case.fetch("candidate_set"))))
  )
  candidates_by_source = {source.fetch("source_id") => candidates}

  gemfile_sha = Digest::SHA256.hexdigest("source \"https://example.invalid/\"\n")
  evaluation = {
    "gemfile" => {"path_sha256" => Digest::SHA256.hexdigest("Gemfile"), "sha256" => gemfile_sha},
    "fingerprint" => {
      "format" => "celerite-eval-v1",
      "digest" => Digest::SHA256.hexdigest(gemfile_sha),
      "state" => "deterministic",
      "state_reason" => nil,
      "verify_files" => [{"role" => "gemfile", "path" => "Gemfile", "sha256" => gemfile_sha}],
      "runtime" => {"ruby" => "4.0.6", "rubygems" => "4.0.16", "bundler" => Celerite::SolveBatch::REFERENCE_BUNDLER},
      "config" => {}
    },
    "sources" => [source],
    "plugins" => [],
    "groups" => {"with" => [], "without" => [], "optional" => [], "all" => []}
  }
  constraints = fixture.fetch("common").fetch("constraints").merge(test_case.fetch("constraints", {}))

  {
    "schema" => Celerite::SolveBatch::SCHEMA,
    "evaluation" => evaluation,
    "requirements" => requirements,
    "candidates_by_source" => candidates_by_source,
    "locked_base" => {"sha256" => Celerite::SolveBatch.locked_digest(locked_specs), "specs" => locked_specs},
    "promotion" => Marshal.load(Marshal.dump(test_case.fetch("promotion"))),
    "constraints" => constraints,
    "candidate_closure" => {
      "complete" => true,
      "digest" => Celerite::SolveBatch.candidate_digest(candidates_by_source),
      "name_count" => candidates.map {|candidate| candidate.fetch("name") }.uniq.length,
      "candidate_count" => candidates.length
    },
    "limits" => {"timeout_ms" => 60_000}
  }
end

if $PROGRAM_NAME == __FILE__
  case_name = ARGV.fetch(0) do
    warn "usage: ruby script/solve_batch_fixture.rb CASE_NAME"
    exit 64
  end
  puts JSON.generate(seal(case_name))
end
