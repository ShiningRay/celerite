require "../spec_helper"
require "../../src/celerite/compact_index/cache"

module Celerite
  # Fails the first `@failures` fetches, then serves `@body`. Mirrors the
  # real-world case behind task-157: the locked-spec staleness probe
  # (`resolution.cr` `stale_locked_dependency_full_names`) swallows a fetch
  # error, and the install path must still see the failure instead of a
  # silently empty index.
  class T157FlakyFetcher < CompactIndex::Fetcher
    getter calls = 0

    def initialize(@failures : Int32, @body : String = "body")
    end

    def call(remote_path : String, headers : Hash(String, String)) : CompactIndex::FetchResponse
      @calls += 1
      if @calls <= @failures
        raise Celerite::NetworkDownError.for(URI.parse("http://127.0.0.1:9/"))
      end
      CompactIndex::FetchResponse.new(200, @body, {} of String => String)
    end
  end

  describe CompactIndex::Cache do
    it "re-raises on a second call after a failed fetch" do
      directory = File.tempname("celerite-ci", "cache")
      fetcher = T157FlakyFetcher.new(failures: 2)
      cache = CompactIndex::Cache.new(directory, CompactIndex::Updater.new(fetcher))

      # First call: the fetch fails. The error surfaces here and is swallowed
      # by the product caller (the locked-spec staleness probe).
      expect_raises(Celerite::NetworkDownError) { cache.versions }

      # The endpoint must not be remembered as fetched: the next call has to
      # reach the source again and re-raise, instead of reading the cache file
      # that was never written as an empty index.
      expect_raises(Celerite::NetworkDownError) { cache.versions }
      fetcher.calls.should eq(2)
      File.file?(File.join(directory, "versions")).should be_false
      FileUtils.rm_rf(directory)
    end

    it "serves the cached body once a fetch succeeded" do
      directory = File.tempname("celerite-ci", "cache")
      fetcher = T157FlakyFetcher.new(failures: 0, body: "versions-body")
      cache = CompactIndex::Cache.new(directory, CompactIndex::Updater.new(fetcher))

      cache.versions.should eq("versions-body")
      cache.versions.should eq("versions-body")
      fetcher.calls.should eq(1)
      FileUtils.rm_rf(directory)
    end

    it "fetches again after a failure once the source is reachable" do
      directory = File.tempname("celerite-ci", "cache")
      fetcher = T157FlakyFetcher.new(failures: 1, body: "late-body")
      cache = CompactIndex::Cache.new(directory, CompactIndex::Updater.new(fetcher))

      expect_raises(Celerite::NetworkDownError) { cache.versions }
      cache.versions.should eq("late-body")
      fetcher.calls.should eq(2)
      FileUtils.rm_rf(directory)
    end

    it "still reads a cache file that the fetcher never had to write" do
      directory = File.tempname("celerite-ci", "cache")
      fetcher = T157FlakyFetcher.new(failures: 1)
      cache = CompactIndex::Cache.new(directory, CompactIndex::Updater.new(fetcher))
      File.write(File.join(directory, "versions"), "pre-seeded")

      # `info/1` is read straight from disk when no checksum is supplied.
      File.write(cache.info_path("plain-gem"), "info-body")
      cache.info("plain-gem", nil).should eq("info-body")
      fetcher.calls.should eq(0)
      FileUtils.rm_rf(directory)
    end
  end
end
