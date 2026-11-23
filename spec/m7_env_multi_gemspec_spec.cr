require "./spec_helper"
require "../src/celerite"

# `bundle env` Gemspecs section (task-189, claim C-M7-3-035).
#
# Reference: bundler/env.rb:51-58 builds the section from
# `Bundler::Dsl.new.tap { |d| d.eval_gemfile(Bundler.default_gemfile) }.gemspecs`
# and prints, for each entry, `\n### <basename>` plus the file body in a ruby
# fence. `Bundler::Dsl#gemspec` (dsl.rb:63-99) appends to `@gemspecs` in
# Gemfile evaluation order and never de-duplicates, so a `gemspec` directive
# repeated for the same spec shows up twice. Celerite renders the section from
# the bridge, which evaluates the Gemfile with the reference `Bundler::Dsl`
# (`assets/bridge/server.rb:227-238`), so the order and the repeats are the
# reference's own.
#
# Decided against the reference on 2026-11-23 with
# fixtures/differential/env-gemspec-multi (4.0.24 profile).

private def with_multi_env_bridge(&)
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

private def multi_gemspec_project : Hash(String, String)
  {"Gemfile" => %(source "https://rubygems.org"\n\n) +
    %(gemspec path: "aaa", name: "aaa"\n) +
    %(gemspec path: "zzz", name: "zzz"\n) +
    %(gemspec path: "aaa", name: "aaa"\n),
   "aaa/aaa.gemspec" => %(Gem::Specification.new do |spec|\n) +
     %(  spec.name = "aaa"\n  spec.version = "0.1.0"\n) +
     %(  spec.summary = "aaa fixture"\n) +
     %(  spec.authors = ["fixture"]\n  spec.files = []\n) +
     %(  spec.require_paths = ["lib"]\nend\n),
   "zzz/zzz.gemspec" => %(Gem::Specification.new do |spec|\n) +
     %(  spec.name = "zzz"\n  spec.version = "0.1.0"\n) +
     %(  spec.summary = "zzz fixture"\n) +
     %(  spec.authors = ["fixture"]\n  spec.files = []\n) +
     %(  spec.require_paths = ["lib"]\nend\n)}
end

private def gemspec_section(output : String) : String
  start = output.index("## Gemspecs")
  start ? output[start..] : ""
end

private def gemspec_headers(output : String) : Array(String)
  start = output.index("## Gemspecs")
  return [] of String unless start
  output[start..].lines.select(&.starts_with?("### ")).map { |line| line.lchop("### ").strip }
end

describe "M7 env multi gemspec (task-189)" do
  it "keeps Gemfile evaluation order and does not de-duplicate gemspec directives" do
    with_multi_env_bridge do
      with_project(multi_gemspec_project) do
        code, output, error = run_cli(["env"])

        code.should eq(0)
        # env.rb:51-58 appends one `### <basename>` block per `dsl.gemspecs`
        # entry, so the repeated `aaa` directive appears twice, in place.
        gemspec_headers(output).should eq(["aaa.gemspec", "zzz.gemspec", "aaa.gemspec"])
        output.should contain("spec.summary = \"aaa fixture\"")
        output.should contain("spec.summary = \"zzz fixture\"")
        # Each block is fenced: two fences per entry.
        gemspec_section(output).scan(/```ruby/).size.should eq(3)

        # The duplicate dependency that `gemspec` adds is what the reference
        # warns about (Dsl#gem), on stderr, not stdout.
        error.should contain("Your Gemfile lists the gem aaa (>= 0) more than once.")
        output.should_not contain("more than once")
      end
    end
  end

  it "prints a single gemspec once when it is declared once" do
    with_multi_env_bridge do
      with_project(multi_gemspec_project) do
        # Same project as above, but only the first directive stays.
        File.write("Gemfile", %(source "https://rubygems.org"\n\ngemspec path: "aaa", name: "aaa"\n))
        code, output, _error = run_cli(["env"])

        code.should eq(0)
        gemspec_headers(output).should eq(["aaa.gemspec"])
        gemspec_section(output).scan(/```ruby/).size.should eq(1)
        output.should_not contain("zzz.gemspec")
      end
    end
  end
end
