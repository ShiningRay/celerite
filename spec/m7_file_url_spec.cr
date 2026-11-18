require "./spec_helper"
require "../src/celerite"
require "../src/celerite/downloader"

# The reference fetcher (`rubygems/remote_fetcher.rb:205-207`) reads
# `Gem::Util.correct_for_windows_path(uri.path)` and discards the URI host.
# These cases pin that mapping, including the non-canonical
# `file://C:/...` form that used to fold the drive letter into the path.
module Celerite
  describe FileURL do
    it "resolves every reference file: URL form to a local path" do
      FileURL.local_path("file://C:/x").should eq("/x")
      FileURL.local_path("file:///C:/x").should eq("C:/x")
      FileURL.local_path("file:/C:/x").should eq("C:/x")
      FileURL.local_path("file://host/x").should eq("/x")
      FileURL.local_path("file:////server/share").should eq("//server/share")
      FileURL.local_path("file:C:/x").should eq("C:/x")
    end

    it "only strips the slash before a drive letter" do
      FileURL.local_path("file:///c:/tmp").should eq("c:/tmp")
      FileURL.local_path("file:///C:").should eq("C:")
      FileURL.local_path("file:///tmp/x").should eq("/tmp/x")
    end

    it "keeps trailing separators and normalizes backslashes" do
      FileURL.local_path("file:///C:/dir/").should eq("C:/dir/")
      FileURL.local_path(%(file:///C:\\dir)).should eq("C:/dir")
    end

    {% if flag?(:win32) %}
      it "expands drive, host and UNC forms without dropping the UNC prefix" do
        FileURL.directory("file:///C:/x").should eq("C:\\x\\")
        FileURL.directory("file://C:/x").should eq("C:\\x\\")
        FileURL.directory("file://host/x").should eq("C:\\x\\")
        FileURL.directory("file:////server/share").should eq("\\\\server\\share\\")
      end
    {% end %}
  end

  {% if flag?(:win32) %}
    describe Downloader do
      it "downloads from a non-canonical file:// drive URL" do
        index = File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")).gsub('\\', "/")
        cache_root = File.tempname("celerite-dl-noncanonical", "cache")
        downloader = Downloader.new("file://#{index}", cache_root)

        path = downloader.fetch("json_pure", "2.8.1", nil, nil)
        File.file?(path).should be_true
        path.should end_with("json_pure-2.8.1.gem")
        FileUtils.rm_rf(cache_root)
      end
    end
  {% end %}
end
