require "./spec_helper"

# The bridge serializes `dep.autorequire` raw (assets/bridge/server.rb:89).
# Bundler array-wraps `:require` when present
# (`Array(options["require"] || [])`, bundler/dependency.rb#autorequire in
# 2.2/2.7/4.0) and leaves it nil when absent, so the wire shape is an array
# (or null), never a scalar string.
private def dep_json(autorequire : String)
  %({
    "name": "myrack-obama",
    "requirements": [">= 1.0"],
    "groups": ["default"],
    "platforms": ["ruby"],
    "autorequire": #{autorequire},
    "force_ruby_platform": null,
    "gemspec_dev_dep": false,
    "source": null
  })
end

describe Celerite::Bridge::EvaluatedDependency do
  it "parses array-shaped autorequire from the bridge" do
    dep = Celerite::Bridge::EvaluatedDependency.from_json(dep_json(%(["myrack/obama"])))
    dep.autorequire.should eq(["myrack/obama"])
  end

  it "parses a multi-entry autorequire array" do
    dep = Celerite::Bridge::EvaluatedDependency.from_json(dep_json(%(["a/b", "c/d"])))
    dep.autorequire.should eq(["a/b", "c/d"])
  end

  it "parses an empty autorequire array (require: false or empty)" do
    dep = Celerite::Bridge::EvaluatedDependency.from_json(dep_json(%([])))
    dep.autorequire.should eq([] of String)
  end

  it "parses a null autorequire (no :require option in the Gemfile)" do
    dep = Celerite::Bridge::EvaluatedDependency.from_json(dep_json("null"))
    dep.autorequire.should be_nil
  end

  it "parses the full dependency shape sent by assets/bridge/server.rb" do
    dep = Celerite::Bridge::EvaluatedDependency.from_json(%({
      "name": "rails",
      "requirements": ["= 8.0.2"],
      "groups": ["default"],
      "platforms": ["ruby"],
      "autorequire": ["rails/all"],
      "force_ruby_platform": false,
      "gemspec_dev_dep": false,
      "source": {"type": "rubygems", "remotes": ["https://rubygems.org"]}
    }))
    dep.name.should eq("rails")
    dep.requirements.should eq(["= 8.0.2"])
    dep.autorequire.should eq(["rails/all"])
    dep.source.try(&.type).should eq("rubygems")
  end

  it "rejects a scalar-string autorequire (old bridge shape)" do
    expect_raises(JSON::ParseException) do
      Celerite::Bridge::EvaluatedDependency.from_json(dep_json(%("myrack/obama")))
    end
  end
end
