require "./spec_helper"

private alias HResolverIndex = Hash(String, Array(Celerite::Resolver::IndexSpec))

private def h_cv(version : String, priority : Int32 = -1) : Celerite::Resolver::CandidateVersion
  Celerite::Resolver::CandidateVersion.new(Celerite::Gem::Version.new(version), priority)
end

private def h_versions(list : Array(String)) : Array(Celerite::Resolver::CandidateVersion)
  list.map { |v| h_cv(v) }
end

private def h_ge(version : String) : Celerite::Resolver::VersionRange
  Celerite::Resolver::VersionRange.new(min: h_cv(version), include_min: true)
end

# "!= x" as the complement of the exact single-version range [x@ruby, x@platform].
private def h_neq(version : String) : Celerite::Resolver::VersionRange
  Celerite::Resolver::VersionRange.new(
    min: h_cv(version),
    max: h_cv(version, 1),
    include_min: true,
    include_max: true,
  ).invert
end

private def h_index_spec(name : String, version : String,
                         deps : Array(Celerite::Resolver::DepSpec) = [] of Celerite::Resolver::DepSpec) : Celerite::Resolver::IndexSpec
  Celerite::Resolver::IndexSpec.new(
    name,
    Celerite::Gem::Version.new(version),
    Celerite::Gem::Platform::RUBY,
    deps,
    Celerite::Gem::Requirement.new([">= 0"]),
    Celerite::Gem::Requirement.new([">= 0"]),
  )
end

private def h_source(specs : Array(Celerite::Resolver::IndexSpec)) : Celerite::Resolver::ResolutionSource
  index = HResolverIndex.new
  specs.each { |spec| (index[spec.name] ||= [] of Celerite::Resolver::IndexSpec) << spec }
  locked = HResolverIndex.new
  base = {} of String => Celerite::Gem::Requirement
  local_platform = Celerite::Gem::Platform::RUBY
  Celerite::Resolver::ResolutionSource.new(
    "Gemfile",
    "rails-min regression",
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

private def h_solve(source : Celerite::Resolver::ResolutionSource,
                    requirements : Array(Celerite::Resolver::DepSpec)) : Hash(String, String)
  orchestrator = Celerite::Resolver::Orchestrator.new(source, requirements)
  orchestrator.solve.map { |package, version| {package.name, version.version.to_s} }.to_h
end

describe "VersionUnion#intersect with != exclusions" do
  it "keeps the above-excluded side when intersecting with an unbounded range" do
    result = h_ge("1.15.7").intersect(h_neq("1.16.0.rc1"))
    result.is_a?(Celerite::Resolver::VersionUnion).should be_true
    result.to_s.should contain(" OR ")
    result.select_versions(h_versions(["1.15.7", "1.16.0.rc1", "1.19.5"]))
      .map(&.version.to_s).should eq(["1.15.7", "1.19.5"])
  end

  it "preserves all versions above multiple != exclusions (rails-html-sanitizer nokogiri shape)" do
    requirement_ranges = [h_ge("1.15.7"),
                          h_neq("1.16.7"), h_neq("1.16.6"), h_neq("1.16.5"),
                          h_neq("1.16.4"), h_neq("1.16.3"), h_neq("1.16.2"),
                          h_neq("1.16.1"), h_neq("1.16.0.rc1"), h_neq("1.16.0")]
    result = requirement_ranges.reduce { |a, b| a.intersect(b) }
    result.select_versions(h_versions(["1.15.7", "1.16.0", "1.16.7", "1.19.5", "1.19.7"]))
      .map(&.version.to_s).should eq(["1.15.7", "1.19.5", "1.19.7"])
  end

  it "keeps the set difference even when the excluded version has no candidates" do
    result = h_ge("1.15.7").intersect(h_neq("9.9.9"))
    result.select_versions(h_versions(["1.15.7", "1.16.0", "1.19.5"]))
      .map(&.version.to_s).should eq(["1.15.7", "1.16.0", "1.19.5"])
  end

  it "excludes exactly the named prerelease version and nothing above it" do
    result = h_ge("1.15.7").intersect(h_neq("1.16.0.rc1"))
    result.select_versions(h_versions(["1.15.7", "1.16.0.rc1", "1.16.0", "1.19.5"]))
      .map(&.version.to_s).should eq(["1.15.7", "1.16.0", "1.19.5"])
  end
end

describe Celerite::Gem::Requirement do
  it "keeps != exclusions enumerable in to_s and satisfied_by?" do
    req = Celerite::Gem::Requirement.new([">= 1.15.7", "!= 1.16.7", "!= 1.16.6", "!= 1.16.0.rc1"])
    req.to_s.should eq(">= 1.15.7, != 1.16.7, != 1.16.6, != 1.16.0.rc1")
    req.satisfied_by?(Celerite::Gem::Version.new("1.19.7")).should be_true
    req.satisfied_by?(Celerite::Gem::Version.new("1.16.7")).should be_false
    req.satisfied_by?(Celerite::Gem::Version.new("1.16.0.rc1")).should be_false
  end

  it "intersects by concatenating constraint lists" do
    a = Celerite::Gem::Requirement.new([">= 1.15.7"])
    b = Celerite::Gem::Requirement.new(["!= 1.16.7", "!= 1.16.6"])
    Celerite::Gem::Requirement.intersect(a, b).to_s.should eq(">= 1.15.7, != 1.16.7, != 1.16.6")
  end
end

describe "rails-min nokogiri/loofah regression (offline recorded metadata)" do
  it "solves the rails-html-sanitizer + loofah nokogiri diamond without a derived conflict" do
    source = h_source([
      h_index_spec("rails-html-sanitizer", "1.7.2", [
        Celerite::Resolver::DepSpec.new("loofah", Celerite::Gem::Requirement.new(["~> 2.25", ">= 2.25.3"])),
        Celerite::Resolver::DepSpec.new("nokogiri", Celerite::Gem::Requirement.new([
          ">= 1.15.7", "!= 1.16.7", "!= 1.16.6", "!= 1.16.5", "!= 1.16.4",
          "!= 1.16.3", "!= 1.16.2", "!= 1.16.1", "!= 1.16.0.rc1", "!= 1.16.0",
        ])),
      ]),
      h_index_spec("loofah", "2.25.3", [
        Celerite::Resolver::DepSpec.new("crass", Celerite::Gem::Requirement.new(["~> 1.0.2"])),
        Celerite::Resolver::DepSpec.new("nokogiri", Celerite::Gem::Requirement.new([">= 1.19.5"])),
      ]),
      h_index_spec("crass", "1.0.2"),
      h_index_spec("nokogiri", "1.15.7"),
      h_index_spec("nokogiri", "1.16.0.rc1"),
      h_index_spec("nokogiri", "1.16.0"),
      h_index_spec("nokogiri", "1.16.7"),
      h_index_spec("nokogiri", "1.19.5"),
      h_index_spec("nokogiri", "1.19.7"),
    ])

    solved = h_solve(source, [
      Celerite::Resolver::DepSpec.new("rails-html-sanitizer", Celerite::Gem::Requirement.new(["= 1.7.2"])),
      Celerite::Resolver::DepSpec.new("loofah", Celerite::Gem::Requirement.new(["= 2.25.3"])),
    ])
    solved["nokogiri"].should eq("1.19.7")
    solved["loofah"].should eq("2.25.3")
    solved["crass"].should eq("1.0.2")
  end
end
