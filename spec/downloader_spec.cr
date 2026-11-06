require "./spec_helper"
require "../src/celerite"
require "../src/celerite/downloader"

def fixture_index_remote : String
  "file:///" + File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")).gsub(/\\/, "/")
end

module Celerite
  describe Downloader do
    it "downloads and caches gem packages from a file:// index" do
      cache_root = File.tempname("celerite-dl", "cache")
      downloader = Downloader.new(fixture_index_remote, cache_root)

      path = downloader.fetch("json_pure", "2.8.1", nil, nil)
      File.file?(path).should be_true
      path.should end_with("json_pure-2.8.1.gem")

      # second fetch returns the same cache entry
      downloader.fetch("json_pure", "2.8.1", nil, nil).should eq(path)

      # gem payload parses: tar contains metadata.gz + data.tar.gz
      names = [] of String
      File.open(path, "rb") do |io|
        Tar.each_entry(io) do |entry, _|
          names << entry.name
        end
      end
      names.should contain("metadata.gz")
      names.should contain("data.tar.gz")
      FileUtils.rm_rf(cache_root)
    end

    it "rejects a mismatching checksum and leaves no usable artifact" do
      cache_root = File.tempname("celerite-dl", "cache")
      downloader = Downloader.new(fixture_index_remote, cache_root)
      bad_checksum = "sha256=" + ("ab" * 32)

      expect_raises(Downloader::ChecksumMismatchError) do
        downloader.fetch("json_pure", "2.8.1", nil, bad_checksum)
      end

      # no usable artifact in the cache
      Dir.children(File.join(cache_root, "downloads")).select(&.ends_with?(".gem")).should be_empty
      FileUtils.rm_rf(cache_root)
    end

    it "verifies matching hex checksums" do
      cache_root = File.tempname("celerite-dl", "cache")
      downloader = Downloader.new(fixture_index_remote, cache_root)
      good = Digest::SHA256.hexdigest(
        File.read(File.join(__DIR__, "..", "fixtures", "gem-index", "gems", "json_pure-2.8.1.gem"))
      )
      path = downloader.fetch("json_pure", "2.8.1", nil, good)
      File.file?(path).should be_true
      FileUtils.rm_rf(cache_root)
    end
  end
end
