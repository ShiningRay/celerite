require "../spec_helper"
require "../../src/celerite/compact_index/cache"
require "base64"
require "openssl"

module Celerite
  # Scripted fetcher for the updater contract tests: returns queued responses
  # and records the request headers (range + conditional GET).
  class ScriptedFetcher < CompactIndex::Fetcher
    getter requests = [] of Hash(String, String)

    def initialize(@responses : Array(CompactIndex::FetchResponse))
    end

    def call(remote_path : String, headers : Hash(String, String)) : CompactIndex::FetchResponse
      @requests << headers
      response = @responses.shift?
      raise "no scripted response for #{remote_path}" if response.nil?
      response
    end
  end

  def self.repr_digest(data : String) : String
    digest = OpenSSL::Digest.new("SHA256")
    digest.update(data.to_slice)
    "sha-256=:" + Base64.encode(digest.final).rstrip + ":"
  end

  def self.etag_header(etag : String) : Hash(String, String)
    {"etag" => %("#{etag}")}
  end

  describe CompactIndex::Updater do
    it "appends a 206 range response and persists the new ETag" do
      local = File.tempname("celerite-ci", "versions")
      etag = "#{local}.etag"
      File.write(local, "abc")
      File.write(etag, "old-etag")

      full = "abcdef"
      fetcher = ScriptedFetcher.new([
        CompactIndex::FetchResponse.new(206, "Xdef", {
          "etag" => %("new-etag"),
          "repr-digest" => repr_digest(full),
        }),
      ])
      CompactIndex::Updater.new(fetcher).update("/versions", local, etag)

      File.read(local).should eq("abcdef")
      File.read(etag).should eq("new-etag")
      fetcher.requests.first["Range"].should eq("bytes=2-")
      fetcher.requests.first["If-None-Match"].should eq(%("old-etag"))
      FileUtils.rm_rf(local)
      FileUtils.rm_rf(etag)
    end

    it "keeps the cache on 304 Not Modified" do
      local = File.tempname("celerite-ci", "versions")
      etag = "#{local}.etag"
      File.write(local, "abc")
      File.write(etag, "old-etag")

      fetcher = ScriptedFetcher.new([
        CompactIndex::FetchResponse.new(304, "", {} of String => String),
      ])
      CompactIndex::Updater.new(fetcher).update("/versions", local, etag)

      File.read(local).should eq("abc")
      File.read(etag).should eq("old-etag")
      FileUtils.rm_rf(local)
      FileUtils.rm_rf(etag)
    end

    it "replaces the cache when the server returns 200 to a range request" do
      local = File.tempname("celerite-ci", "versions")
      etag = "#{local}.etag"
      File.write(local, "abc")
      File.write(etag, "old-etag")

      fetcher = ScriptedFetcher.new([
        CompactIndex::FetchResponse.new(200, "xyz", {
          "etag" => %("next-etag"),
          "repr-digest" => repr_digest("xyz"),
        }),
      ])
      CompactIndex::Updater.new(fetcher).update("/versions", local, etag)

      File.read(local).should eq("xyz")
      File.read(etag).should eq("next-etag")
      FileUtils.rm_rf(local)
      FileUtils.rm_rf(etag)
    end

    it "falls back to a full replace when the 206 response has no digest" do
      local = File.tempname("celerite-ci", "versions")
      etag = "#{local}.etag"
      File.write(local, "abc")
      File.write(etag, "old-etag")

      fetcher = ScriptedFetcher.new([
        CompactIndex::FetchResponse.new(206, "Xdef", {"etag" => %("partial")}),
        CompactIndex::FetchResponse.new(200, "abcdef", {
          "etag" => %("full"),
          "repr-digest" => repr_digest("abcdef"),
        }),
      ])
      CompactIndex::Updater.new(fetcher).update("/versions", local, etag)

      File.read(local).should eq("abcdef")
      File.read(etag).should eq("full")
      fetcher.requests.size.should eq(2)
      FileUtils.rm_rf(local)
      FileUtils.rm_rf(etag)
    end

    it "rejects a mismatching Repr-Digest and keeps the previous cache" do
      local = File.tempname("celerite-ci", "versions")
      etag = "#{local}.etag"
      File.write(local, "abc")
      File.write(etag, "old-etag")

      fetcher = ScriptedFetcher.new([
        CompactIndex::FetchResponse.new(200, "tampered", {
          "etag" => %("bad"),
          "repr-digest" => repr_digest("expected"),
        }),
      ])

      expect_raises(CompactIndex::MismatchedChecksumError) do
        CompactIndex::Updater.new(fetcher).update("/versions", local, etag)
      end
      File.read(local).should eq("abc")
      Dir.glob("#{local}.*.tmp").should be_empty
      FileUtils.rm_rf(local)
      FileUtils.rm_rf(etag)
    end

    it "writes a fresh cache from 200 and strips weak/quoted ETags" do
      local = File.tempname("celerite-ci", "names")
      etag = "#{local}.etag"

      fetcher = ScriptedFetcher.new([
        CompactIndex::FetchResponse.new(200, "data", {
          "etag" => %(W/"weak-tag"),
          "repr-digest" => repr_digest("data"),
        }),
      ])
      CompactIndex::Updater.new(fetcher).update("/names", local, etag)

      File.read(local).should eq("data")
      File.read(etag).should eq("weak-tag")
      FileUtils.rm_rf(local)
      FileUtils.rm_rf(etag)
    end
  end
end
