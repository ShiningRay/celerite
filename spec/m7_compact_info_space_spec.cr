require "./spec_helper"
require "../src/celerite"

# rubygems.org writes a version's requirements straight after the version when
# the gem has no dependencies but does have a checksum:
#
#     1.0.0|checksum:Bc7TaK4atHJ+xJRK664etA+kcA57HSEZgmAyyL76lBw=
#
# The reference splits the info line on `|` (`Gem::Resolver::APISet` +
# `Bundler::CompactIndexClient::Parser`) and therefore accepts both that form
# and the spaced form (`1.0.0 |checksum:...`) that our fixtures used so far.
# Parsing the pipe as part of the version made the version malformed
# (`Malformed version number string`), so the lock failed with exit 20 against
# an index that the reference resolves happily.
private def with_compact_info_bridge(& : ->) : Nil
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
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

private def compact_info_index_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index-platform")))
end

describe "compact index info lines" do
  # `fixtures/gem-index-platform/info/platdemo` mixes both spellings: the
  # platform variant keeps the space (`1.0.0-x64-mingw-ucrt |checksum:...`)
  # and the ruby variant drops it (`1.0.0|checksum:...`).
  it "accepts requirements written without a space before the pipe" do
    pending! "ruby not available" unless ruby_available?
    remote = compact_info_index_remote
    with_compact_info_bridge do
      with_project({"Gemfile" => %(source "#{remote}"\n\ngem "platdemo"\n)}) do
        with_client do |client|
          resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
          resolution.progress = IO::Memory.new

          specs = resolution.resolve!
          spec = specs.find { |candidate| candidate.name == "platdemo" }
          spec.should_not be_nil
          # The pipe must not leak into the version; both variants are 1.0.0.
          spec.not_nil!.version.to_s.should eq("1.0.0")
          spec.not_nil!.version.to_s.should_not contain("|")
        end
      end
    end
  end

  it "keeps accepting the spaced spelling alongside the unspaced one" do
    pending! "ruby not available" unless ruby_available?
    remote = compact_info_index_remote
    with_compact_info_bridge do
      with_project({"Gemfile" => %(source "#{remote}"\n\ngem "platdemo"\n)}) do
        with_client do |client|
          resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
          resolution.progress = IO::Memory.new
          lockfile = resolution.generated_lockfile.to_lock

          lockfile.should contain("platdemo (1.0.0")
          lockfile.should_not contain("|checksum")
        end
      end
    end
  end
end
