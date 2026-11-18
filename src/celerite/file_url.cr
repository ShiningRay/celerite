require "uri"

module Celerite
  # Converts a `file:` remote URL into a local filesystem path with the same
  # rules the reference Bundler/rubygems fetcher applies on Windows:
  #
  # * only the URI path is used — the host is ignored, so `file://C:/x`
  #   (host "C", path "/x") and `file://host/x` both mean "/x" on the
  #   current drive, exactly like `Gem::RemoteFetcher#fetch_file`;
  # * a leading slash before a drive letter is dropped (`/C:/x` -> `C:/x`),
  #   mirroring `Gem::Util.correct_for_windows_path`;
  # * a leading `//` is preserved, so `file:////server/share` keeps its UNC
  #   form instead of collapsing to a single slash.
  #
  # The reference does not expand the resulting path; callers join entries
  # onto it. `directory` resolves it to an absolute directory with a
  # trailing separator, which also keeps UNC bases usable for joins (Crystal
  # appends the working directory to a bare `//server/share` base).
  module FileURL
    def self.local_path(remote : String) : String
      path = URI.parse(remote).path || ""
      path = path.gsub('\\', '/')
      path = path.sub(/^\/([A-Za-z]:)/) { |match| match[1..] }
      path
    end

    def self.directory(remote : String) : String
      path = local_path(remote)
      path += "/" unless path.ends_with?("/")
      File.expand_path(path)
    end
  end
end
