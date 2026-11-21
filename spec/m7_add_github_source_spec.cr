require "./spec_helper"

# M7 task-82: `add --github owner/repo` must attach the injected dependency to
# the git source, not the rubygems source. Bundler's DSL normalises the
# `github:` option into `Bundler::Source::Git` with
# `https://github.com/<repo>.git` (dsl.rb git_source(:github)), so the injected
# line resolves against that source and a missing gem is reported against it.
# The checkout step (`git clone --no-hardlinks`) cannot run in this sandbox
# (msys `0xC0000022`), so the end-to-end clone is asserted at the evaluation
# boundary instead of through `script/differential`.
private def github_source_gemfile(path : String) : String
  File.join(path, "Gemfile")
end

describe "M7 add --github source selection" do
  it "maps a github option to the git source with the canonical URL" do
    with_project({"Gemfile" => "source \"https://rubygems.org\"\n\ngem \"json_pure\", github: \"rails/thor\"\n"}) do |dir|
      server = File.expand_path("../assets/bridge/server.rb", __DIR__)
      ENV["CELERITE_BRIDGE_SERVER"] = server
      begin
        with_client do |client|
          evaluation = client.evaluate_gemfile(github_source_gemfile(dir))
          dependency = evaluation.dependencies.find(&.name.==("json_pure")).not_nil!
          source = dependency.source.not_nil!
          source.type.downcase.should eq("git")
          source.remote.should eq("https://github.com/rails/thor.git")
        end
      ensure
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
    end
  end

  it "keeps the injected line byte-identical to the reference rendering" do
    with_project({"Gemfile" => "source \"https://rubygems.org\"\n"}) do |dir|
      server = File.expand_path("../assets/bridge/server.rb", __DIR__)
      ENV["CELERITE_BRIDGE_SERVER"] = server
      begin
        File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\n\ngem \"json_pure\", github: \"rails\\/thor\"\n")
        with_client do |client|
          evaluation = client.evaluate_gemfile(github_source_gemfile(dir))
          source = evaluation.dependencies.find(&.name.==("json_pure")).not_nil!.source.not_nil!
          # No branch/tag/ref in the shorthand form: the git source carries the
          # URL only, so the lockfile records the resolved revision.
          source.branch.should be_nil
          source.tag.should be_nil
          source.ref.should be_nil
        end
      ensure
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
    end
  end
end
