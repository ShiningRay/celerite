require "./spec_helper"

# M7 task-46: a PATH source must be matched by gemspec name, not by
# "the first gemspec the directory happens to contain".
#
# Reference `Source::Path#specs` (`source/path.rb:159-179`) loads the whole
# glob and `Resolver#raise_not_found!` (`resolver/base.rb:113-118`) reports
# `Could not find gem '<name>' in source at `<path>`.` when that name is
# absent. The bridge used to hand back `candidates.first` and we labelled it
# with the requested name, fabricating a spec for a gem that never existed.

private def with_missing_gem_bridge(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def missing_gem_spec(name : String, version : String) : String
  <<-SPEC
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "#{version}"
      s.summary = "#{name}"
      s.authors = ["Fixture"]
      s.files = []
    end
    SPEC
end

describe "M7 task-46 PATH source name matching" do
  it "still resolves a path gem whose gemspec matches the dependency name" do
    with_project({
      "Gemfile"                    => %(gem "alpha", path: "vendor/alpha"\n),
      "vendor/alpha/alpha.gemspec" => missing_gem_spec("alpha", "1.0.0"),
    }) do |dir|
      with_missing_gem_bridge do
        code, _, stderr = run_cli(["lock"])
        code.should eq(0)
        stderr.should be_empty
      end

      text = File.read(File.join(dir, "Gemfile.lock"))
      text.should contain("PATH\n  remote: vendor/alpha\n  specs:\n    alpha (1.0.0)\n")
      text.should contain("DEPENDENCIES\n  alpha!\n")
    end
  end

  it "does not fabricate a spec from a sibling gemspec with another name" do
    with_project({
      "Gemfile"                    => %(gem "nope-gem", path: "vendor/x"\n),
      "vendor/x/other-gem.gemspec" => missing_gem_spec("other-gem", "1.0.0"),
    }) do |dir|
      with_missing_gem_bridge do
        code, _, stderr = run_cli(["lock"])
        code.should eq(7)
        stderr.chomp.should eq("Could not find gem 'nope-gem' in source at `vendor/x`.")
      end

      File.exists?(File.join(dir, "Gemfile.lock")).should be_false
    end
  end

  it "prefers the shallower gemspec when both layers expose the requested name" do
    with_project({
      "Gemfile"                         => %(gem "pathgem", path: "vendor/d"\n),
      "vendor/d/pathgem.gemspec"        => missing_gem_spec("pathgem", "2.0.0"),
      "vendor/d/gems/x/pathgem.gemspec" => missing_gem_spec("pathgem", "1.0.0"),
    }) do |dir|
      with_missing_gem_bridge do
        code, _, stderr = run_cli(["lock"])
        code.should eq(0)
        stderr.should be_empty
      end

      text = File.read(File.join(dir, "Gemfile.lock"))
      text.should contain("specs:\n    pathgem (2.0.0)\n")
    end
  end
end
