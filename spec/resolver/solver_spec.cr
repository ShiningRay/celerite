require "../spec_helper"
require "../../src/celerite"

alias SCSpec = NamedTuple(name: String, version: String, deps: Array({String, Array(String)}))

def build_index(specs : Array(SCSpec)) : Hash(String, Array(Celerite::Resolver::IndexSpec))
  grouped = Hash(String, Array(Celerite::Resolver::IndexSpec)).new
  specs.each do |spec|
    deps = spec[:deps].map do |(name, reqs)|
      Celerite::Resolver::DepSpec.new(name, Celerite::Gem::Requirement.new(reqs))
    end
    (grouped[spec[:name]] ||= [] of Celerite::Resolver::IndexSpec) << Celerite::Resolver::IndexSpec.new(
      spec[:name], Celerite::Gem::Version.new(spec[:version]), Celerite::Gem::Platform::RUBY, deps,
      Celerite::Gem::Requirement.new, Celerite::Gem::Requirement.new, nil
    )
  end
  grouped
end

def solve_index(index : Hash(String, Array(Celerite::Resolver::IndexSpec)), deps : Array(Celerite::Resolver::DepSpec),
                base : Hash(String, Celerite::Gem::Requirement) = {} of String => Celerite::Gem::Requirement,
                locked : Hash(String, Array(Celerite::Resolver::IndexSpec)) = {} of String => Array(Celerite::Resolver::IndexSpec))
  source = Celerite::Resolver::ResolutionSource.new(
    "Gemfile", "rubygems repository test", index, locked, base, Celerite::Gem::Platform::RUBY
  )
  orchestrator = Celerite::Resolver::Orchestrator.new(source, deps)
  decisions = orchestrator.solve
  decisions.reject { |package, _| package.root? }
    .map { |package, version| "#{package.name}=#{version.version}" }
    .sort
end

module Celerite
  # Standalone PubGrub solver checks against a static index (pinned behavior:
  # resolution results must match the reference for the same inputs).
  describe Resolver::ResolutionSource do
    it "resolves the highest satisfying versions" do
      index = build_index([
        {name: "a", version: "1.0", deps: [{"b", [">= 1.0"]}]},
        {name: "a", version: "2.0", deps: [{"b", [">= 2.0"]}]},
        {name: "b", version: "1.5", deps: [] of {String, Array(String)}},
        {name: "b", version: "2.5", deps: [] of {String, Array(String)}},
      ])
      deps = [Resolver::DepSpec.new("a", Gem::Requirement.new)]
      solve_index(index, deps).should eq(["a=2.0", "b=2.5"])
    end

    it "backtracks through conflicting transitive requirements" do
      index = build_index([
        {name: "a", version: "1.0", deps: [] of {String, Array(String)}},
        {name: "a", version: "2.0", deps: [{"c", ["< 2.0"]}]},
        {name: "b", version: "1.0", deps: [{"c", [">= 2.0"]}]},
        {name: "c", version: "1.0", deps: [] of {String, Array(String)}},
        {name: "c", version: "2.0", deps: [] of {String, Array(String)}},
      ])
      # a 2.0 conflicts with b (c constraints are disjoint); the solver must
      # backtrack a to 1.0
      deps = [
        Resolver::DepSpec.new("a", Gem::Requirement.new),
        Resolver::DepSpec.new("b", Gem::Requirement.new),
      ]
      solve_index(index, deps).should eq(["a=1.0", "b=1.0", "c=2.0"])
    end

    it "prefers locked versions when they satisfy the requirement" do
      index = build_index([
        {name: "a", version: "1.0", deps: [] of {String, Array(String)}},
        {name: "a", version: "2.0", deps: [] of {String, Array(String)}},
      ])
      locked = build_index([
        {name: "a", version: "1.0", deps: [] of {String, Array(String)}},
      ])
      base = {"a" => Gem::Requirement.new([">= 1.0"])}
      deps = [Resolver::DepSpec.new("a", Gem::Requirement.new([">= 1.0"]))]
      solve_index(index, deps, base, locked).should eq(["a=1.0"])
    end

    it "ignores the locked-version preference when unlocking" do
      index = build_index([
        {name: "a", version: "1.0", deps: [] of {String, Array(String)}},
        {name: "a", version: "2.0", deps: [] of {String, Array(String)}},
      ])
      locked = build_index([
        {name: "a", version: "1.0", deps: [] of {String, Array(String)}},
      ])
      deps = [Resolver::DepSpec.new("a", Gem::Requirement.new)]
      empty_base = {} of String => Gem::Requirement
      source = Resolver::ResolutionSource.new(
        "Gemfile", "rubygems repository test", index, locked,
        empty_base, Gem::Platform::RUBY, true
      )
      orchestrator = Resolver::Orchestrator.new(source, deps)
      decisions = orchestrator.solve
      a_version = decisions.find { |package, _| package.name == "a" }.not_nil![1]
      a_version.version.to_s.should eq("2.0")
    end

    it "raises GemNotFound for unknown root dependencies" do
      index = build_index([] of NamedTuple(name: String, version: String, deps: Array({String, Array(String)})))
      deps = [Resolver::DepSpec.new("missing", Gem::Requirement.new)]
      expect_raises(GemNotFoundError, "Could not find gem 'missing'") do
        solve_index(index, deps)
      end
    end

    it "keeps locked versions above the downgrade floor" do
      index = build_index([
        {name: "a", version: "1.0", deps: [] of {String, Array(String)}},
        {name: "a", version: "2.0", deps: [] of {String, Array(String)}},
        {name: "a", version: "3.0", deps: [] of {String, Array(String)}},
      ])
      locked = build_index([
        {name: "a", version: "2.0", deps: [] of {String, Array(String)}},
      ])
      base = {"a" => Gem::Requirement.new([">= 2.0"])}
      deps = [Resolver::DepSpec.new("a", Gem::Requirement.new)]
      # `bundle lock` keeps the locked version when it satisfies (strong
      # preference, not an upgrade trigger)
      solve_index(index, deps, base, locked).should eq(["a=2.0"])
    end
  end
end
