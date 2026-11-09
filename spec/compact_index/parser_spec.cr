require "../spec_helper"
require "../../src/celerite"
require "../../src/celerite/compact_index/cache"

def parser_with(versions : String, infos : Hash(String, String)) : Celerite::CompactIndex::Parser
  cache = Celerite::CompactIndex::Cache.new(File.tempname("celerite-ci", "cache"), nil)
  File.write(File.join(cache.directory, "versions"), versions)
  infos.each do |name, content|
    File.write(cache.info_path(name), content)
  end
  Celerite::CompactIndex::Parser.new(cache)
end

module Celerite
  describe CompactIndex::Parser do
    it "parses the versions index with info checksums" do
      parser = parser_with(
        "created_at: 2026-11-07T00:00:00Z\r\n---\r\njson_pure 2.6.0,2.8.1 abc123\r\nracc 1.8.1 def456\r\n",
        {} of String => String
      )
      versions = parser.versions
      versions["json_pure"].map(&.version).should eq(["2.6.0", "2.8.1"])
      versions["json_pure"].map(&.yanked).should eq([false, false])
      versions["racc"].first.info_checksum.should eq("def456")
    end

    it "parses platform variants and yanked entries" do
      parser = parser_with(
        "---\ngem-with-platform 1.0.0-x86_64-linux,1.0.0 abc\ngem-yanked 2.0.0,-1.0.0 abc\n",
        {} of String => String
      )
      versions = parser.versions
      versions["gem-with-platform"].map(&.platform).should eq(["x86_64-linux", "ruby"])
      versions["gem-yanked"].map(&.version).should eq(["2.0.0"])
    end

    it "parses info entries with dependencies and requirements" do
      parser = parser_with(
        "---\ngem-with-platform 1.0.0 abc\n",
        {
          "gem-with-platform" => "---\n1.0.0 racc:>= 1.4&< 2.0,rack|ruby:>= 3.0,rubygems:>= 3.4,checksum:abc123\n",
        }
      )
      entries = parser.info("gem-with-platform")
      entries.size.should eq(1)
      entry = entries[0]
      entry.version.should eq("1.0.0")
      entry.platform_ruby?.should be_true
      entry.dependencies.map { |d| "#{d.name}:#{d.requirements.join("&")}" }.should eq([
        "racc:>= 1.4&< 2.0",
        "rack:",
      ])
      entry.required_ruby_version_list.should eq([">= 3.0"])
      entry.required_rubygems_version_list.should eq([">= 3.4"])
      entry.checksum.should eq("abc123")
    end

    it "parses created_at metadata for cooldown filtering" do
      parser = parser_with(
        "---\ngem-with-platform 1.0.0 abc\n",
        {
          "gem-with-platform" => "---\n1.0.0 |checksum:abc123,ruby:>= 3.0,created_at:2026-11-01 10:00:00 UTC\n",
        }
      )
      created = parser.info("gem-with-platform")[0].created_at
      created.should_not be_nil
      Time.unix(created.not_nil!).year.should eq(2026)
      Time.unix(created.not_nil!).month.should eq(11)
      entry_checksum = parser.info("gem-with-platform")[0].checksum
      entry_checksum.should eq("abc123")
    end

    it "parses platform-specific info entries" do
      parser = parser_with(
        "---\ngem-with-platform 1.0.0 abc\n",
        {
          "gem-with-platform" => "---\n1.0.0-x86_64-linux |racc (> 0)|ruby:>= 3.0\n",
        }
      )
      entries = parser.info("gem-with-platform")
      entries[0].platform.should eq("x86_64-linux")
      entries[0].platform_ruby?.should be_false
    end

    it "exposes info via the client cache flow" do
      idx = File.expand_path(File.join(__DIR__, "..", "..", "fixtures", "gem-index"))
      remote = file_source_url(idx)
      client = CompactIndex::Client.new(remote, File.tempname("celerite-ci", "root"))
      versions = client.versions
      versions["json_pure"].map(&.version).sort.should eq(["2.6.0", "2.8.1"])
      entries = client.info("json_pure")
      entries.map(&.version).should eq(["2.6.0", "2.8.1"])
    end
  end
end
