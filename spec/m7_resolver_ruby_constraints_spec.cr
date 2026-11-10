require "./spec_helper"

private alias ResolverIndex = Hash(String, Array(Celerite::Resolver::IndexSpec))

private def resolver_index(specs : Array(Celerite::Resolver::IndexSpec)) : ResolverIndex
  grouped = ResolverIndex.new
  specs.each do |spec|
    (grouped[spec.name] ||= [] of Celerite::Resolver::IndexSpec) << spec
  end
  grouped
end

private def index_spec(name : String, version : String,
                       required_ruby : String = ">= 0",
                       required_rubygems : String = ">= 0",
                       platform : Celerite::Gem::Platform = Celerite::Gem::Platform::RUBY) : Celerite::Resolver::IndexSpec
  Celerite::Resolver::IndexSpec.new(
    name,
    Celerite::Gem::Version.new(version),
    platform,
    [] of Celerite::Resolver::DepSpec,
    Celerite::Gem::Requirement.new([required_ruby]),
    Celerite::Gem::Requirement.new([required_rubygems]),
  )
end

private def constraint_source(specs : Array(Celerite::Resolver::IndexSpec),
                              ruby_version : String = "4.0.6",
                              rubygems_version : String = "4.0.16",
                              patchlevel : String? = nil) : Celerite::Resolver::ResolutionSource
  index = resolver_index(specs)
  locked = ResolverIndex.new
  base = {} of String => Celerite::Gem::Requirement
  local_platform = Celerite::Gem::Platform::RUBY
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
    ruby_version,
    rubygems_version,
    "ruby",
    ruby_version,
    patchlevel,
  )
end

private def candidate_versions(source : Celerite::Resolver::ResolutionSource, name : String) : Array(String)
  package = source.package_for(Celerite::Resolver::DepSpec.new(name, Celerite::Gem::Requirement.new))
  source.all_versions_for(package).map { |candidate| candidate.version.version.to_s }.sort
end

private def resolved_version(source : Celerite::Resolver::ResolutionSource, name : String,
                             requirement : Celerite::Gem::Requirement = Celerite::Gem::Requirement.new) : String?
  orchestrator = Celerite::Resolver::Orchestrator.new(
    source,
    [Celerite::Resolver::DepSpec.new(name, requirement)],
  )
  decision = orchestrator.solve.find { |package, _| package.name == name }
  decision.try(&.[1].version.to_s)
end

describe Celerite::Resolver::ResolutionSource do
  it "filters candidates whose required Ruby version is not satisfied" do
    source = constraint_source([
      index_spec("a", "1.0", required_ruby: ">= 3.3"),
      index_spec("a", "2.0", required_ruby: ">= 5.0"),
    ])

    candidate_versions(source, "a").should eq(["1.0"])
  end

  it "filters candidates whose required RubyGems version is not satisfied" do
    source = constraint_source([
      index_spec("a", "1.0", required_rubygems: ">= 4.0"),
      index_spec("a", "2.0", required_rubygems: ">= 5.0"),
    ])

    candidate_versions(source, "a").should eq(["1.0"])
  end

  it "ignores the runtime patchlevel when matching gem required_ruby_version" do
    # Bundler compares gem metadata against Gem.ruby_version (RUBY_VERSION),
    # not a patchlevel-suffixed string; a p0 suffix would be a prerelease and
    # would incorrectly reject a `>= 4.0.6` requirement.
    source = constraint_source([
      index_spec("a", "1.0", required_ruby: ">= 4.0.6"),
    ], patchlevel: "0")

    candidate_versions(source, "a").should eq(["1.0"])
  end

  it "still honors prerelease-style gem requirements using RubyGems ordering" do
    source = constraint_source([
      index_spec("a", "1.0", required_ruby: ">= 4.0.6p1"),
    ], patchlevel: "0")

    candidate_versions(source, "a").should eq(["1.0"])
  end

  it "lets the resolver pick the highest candidate that satisfies Ruby constraints" do
    source = constraint_source([
      index_spec("a", "1.0", required_ruby: ">= 3.3"),
      index_spec("a", "2.0", required_ruby: ">= 5.0"),
    ])

    resolved_version(source, "a").should eq("1.0")
  end

  it "reports a solve failure when every candidate is filtered by Ruby metadata" do
    source = constraint_source([
      index_spec("a", "1.0", required_ruby: ">= 5.0"),
    ])

    error = expect_raises(Celerite::Resolver::SolveFailure) do
      resolved_version(source, "a")
    end
    error.status_code.should eq(6)
    error.message.should eq(<<-MSG.chomp)
      Could not find compatible versions

      Because every version of a depends on Ruby >= 5.0
        and Gemfile depends on a >= 0,
        Ruby >= 5.0 is required.
      So, because current Ruby version is = 4.0.6,
        version solving has failed.
      MSG
  end

  it "reports a solve failure when every candidate is filtered by RubyGems metadata" do
    source = constraint_source([
      index_spec("a", "1.0", required_rubygems: ">= 5.0"),
    ])

    error = expect_raises(Celerite::Resolver::SolveFailure) do
      resolved_version(source, "a")
    end
    error.status_code.should eq(6)
    error.message.not_nil!.should contain("depends on RubyGems >= 5.0")
    error.message.not_nil!.should contain("current RubyGems version is = 4.0.16")
  end

  it "still raises not-found when the requirement itself has no matching version" do
    source = constraint_source([
      index_spec("a", "1.0", required_ruby: ">= 3.3"),
    ])

    error = expect_raises(Celerite::GemNotFoundError) do
      resolved_version(source, "a", Celerite::Gem::Requirement.new([">= 99.0"]))
    end
    error.status_code.should eq(7)
    error.message.not_nil!.should contain("Could not find gem 'a (>= 99.0)'")
  end
end
