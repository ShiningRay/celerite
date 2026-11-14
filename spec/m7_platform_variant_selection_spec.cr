require "./spec_helper"

# Offline spec for M7(1)/(2) platform-variant selection (K2):
# a version resolved as a platform-variant candidate must materialize the
# local-platform variant (reference `Materialization#specs` +
# `MatchPlatform.select_best_platform_match`), fall back to ruby when the
# local variant is absent, and the solver must prefer the platform candidate
# when variant dep sets differ.
private alias ResolverIndex = Hash(String, Array(Celerite::Resolver::IndexSpec))

private def kv_index_spec(name : String, version : String, platform : String,
                          deps : Array(Celerite::Resolver::DepSpec) = [] of Celerite::Resolver::DepSpec) : Celerite::Resolver::IndexSpec
  Celerite::Resolver::IndexSpec.new(
    name,
    Celerite::Gem::Version.new(version),
    Celerite::Gem::Platform.new(platform),
    deps,
    Celerite::Gem::Requirement.new([">= 0"]),
    Celerite::Gem::Requirement.new([">= 0"]),
    nil,
  )
end

private def kv_dep(name : String, req : String) : Celerite::Resolver::DepSpec
  Celerite::Resolver::DepSpec.new(name, Celerite::Gem::Requirement.new([req]))
end

private def kv_source(specs : Array(Celerite::Resolver::IndexSpec),
                      local_platform : Celerite::Gem::Platform) : Celerite::Resolver::ResolutionSource
  index = ResolverIndex.new
  specs.each do |spec|
    (index[spec.name] ||= [] of Celerite::Resolver::IndexSpec) << spec
  end
  locked = ResolverIndex.new
  base = {} of String => Celerite::Gem::Requirement
  Celerite::Resolver::ResolutionSource.new(
    "Gemfile",
    "rubygems repository test",
    index,
    locked,
    base,
    local_platform,
    false,
    nil,
    nil,
    "4.0.6",
    "4.0.16",
    "ruby",
    "4.0.6",
    nil,
  )
end

private def kv_decision(source : Celerite::Resolver::ResolutionSource, name : String,
                        requirement : String) : Celerite::Resolver::CandidateVersion?
  orchestrator = Celerite::Resolver::Orchestrator.new(
    source,
    [Celerite::Resolver::DepSpec.new(name, Celerite::Gem::Requirement.new([requirement]))],
  )
  pair = orchestrator.solve.find { |package, _| package.name == name }
  pair.try(&.[1])
end

describe "platform variant selection (ResolutionSource.select_variant)" do
  it "prefers the local-platform variant among same-version platform variants" do
    index = ResolverIndex{
      "nokogiri" => [
        kv_index_spec("nokogiri", "1.19.7", "ruby"),
        kv_index_spec("nokogiri", "1.19.7", "x64-mingw-ucrt"),
        kv_index_spec("nokogiri", "1.19.7", "x86_64-linux"),
      ],
    }
    spec = Celerite::Resolver::ResolutionSource.select_variant(index, "nokogiri", Celerite::Gem::Version.new("1.19.7"))
    spec.should_not be_nil
    spec.not_nil!.platform.to_s.should eq(Celerite::Gem::Platform.local.to_s)
  end

  it "falls back to the ruby variant when no local-platform variant exists" do
    index = ResolverIndex{
      "myrack" => [
        kv_index_spec("myrack", "1.0.0", "ruby"),
        kv_index_spec("myrack", "1.0.0", "x86_64-linux"),
      ],
    }
    spec = Celerite::Resolver::ResolutionSource.select_variant(index, "myrack", Celerite::Gem::Version.new("1.0.0"))
    spec.should_not be_nil
    spec.not_nil!.platform_ruby?.should be_true
  end

  it "returns nil when the version or the index is absent" do
    index = ResolverIndex{
      "myrack" => [kv_index_spec("myrack", "1.0.0", "ruby")],
    }
    Celerite::Resolver::ResolutionSource.select_variant(index, "myrack", Celerite::Gem::Version.new("2.0.0")).should be_nil
    Celerite::Resolver::ResolutionSource.select_variant(nil, "myrack", Celerite::Gem::Version.new("1.0.0")).should be_nil
  end

  it "prefers the platform candidate when variant dep sets differ (solver side)" do
    source = kv_source([
      kv_index_spec("nokogiri", "1.19.7", "ruby", [kv_dep("racc", "~> 1.4"), kv_dep("mini_portile2", "~> 2.8.2")]),
      kv_index_spec("nokogiri", "1.19.7", "x64-mingw-ucrt", [kv_dep("racc", "~> 1.4")]),
      kv_index_spec("racc", "1.8.1", "ruby"),
      kv_index_spec("mini_portile2", "2.8.2", "ruby"),
    ], Celerite::Gem::Platform.new("x64-mingw-ucrt"))

    decision = kv_decision(source, "nokogiri", ">= 1.15.7")
    decision.should_not be_nil
    decision.not_nil!.version.to_s.should eq("1.19.7")
    decision.not_nil!.priority.should eq(1)
  end

  it "keeps the ruby candidate when only a ruby variant exists" do
    source = kv_source([
      kv_index_spec("myrack", "1.0.0", "ruby", [kv_dep("mydep", ">= 0")]),
      kv_index_spec("mydep", "1.0.0", "ruby"),
    ], Celerite::Gem::Platform.new("x64-mingw-ucrt"))

    decision = kv_decision(source, "myrack", ">= 1.0")
    decision.should_not be_nil
    decision.not_nil!.priority.should eq(-1)
  end
end
