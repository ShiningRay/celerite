require "./cache_file"
require "digest/md5"
require "json"
require "uri"
require "http/client"
require "base64"

module Celerite
  module CompactIndex
    # A fetcher response: status, body and headers (lowercased names).
    struct FetchResponse
      getter status : Int32
      getter body : String
      getter headers : Hash(String, String)

      def initialize(@status : Int32, @body : String, @headers : Hash(String, String))
      end

      def header(name : String) : String?
        @headers[name.downcase]?
      end

      def not_modified? : Bool
        status == 304
      end

      def partial_content? : Bool
        status == 206
      end
    end

    # Fetchers answer `call(remote_path, headers)` like the pinned updater
    # expects: a compact index path (e.g. "/versions") and request headers.
    abstract class Fetcher
      abstract def call(remote_path : String, headers : Hash(String, String)) : FetchResponse
    end

    # file:// source: read directly from a compact index directory (produced
    # by `gem generate_index`). Always returns the full content; the update
    # algorithm then degrades to read+replace, which is exactly how the
    # reference treats local indexes.
    class FileFetcher < Fetcher
      def initialize(@root : String)
      end

      def call(remote_path : String, headers : Hash(String, String)) : FetchResponse
        clean = remote_path.lstrip("/")
        path = File.expand_path(clean, @root)
        # refuse traversal outside the index root
        unless path.starts_with?(File.expand_path(@root))
          return FetchResponse.new(404, "not found", {} of String => String)
        end

        unless File.file?(path)
          return FetchResponse.new(404, "not found", {} of String => String)
        end

        FetchResponse.new(200, File.read(path), {"content-type" => "text/plain"} of String => String)
      end
    end

    # HTTP(S) fetcher over stdlib HTTP::Client with optional credentials.
    class HttpFetcher < Fetcher
      def initialize(@uri : URI, @user : String? = nil, @password : String? = nil, @timeout : Time::Span = 30.seconds)
      end

      def self.for(remote : String, credentials : {String, String}? = nil) : HttpFetcher
        uri = URI.parse(remote)
        user = credentials.try(&.[0]) || uri.user
        password = credentials.try(&.[1]) || uri.password
        new(uri, user, password)
      end

      def call(remote_path : String, headers : Hash(String, String)) : FetchResponse
        client = HTTP::Client.new(@uri)
        client.connect_timeout = @timeout
        client.read_timeout = @timeout
        if @user || @password
          client.basic_auth(@user || "", @password || "")
        end

        request_headers = HTTP::Headers.new
        headers.each { |k, v| request_headers[k] = v }

        response = client.get(remote_path, headers: request_headers)
        response_headers = {} of String => String
        response.headers.each do |name, values|
          response_headers[name.downcase] = values.first? || ""
        end
        FetchResponse.new(response.status_code, response.body, response_headers)
      end
    end

    # Port of `Bundler::CompactIndexClient::Updater`: append via Range requests
    # (cached_size - 1), fall back to full replace, verify Repr-Digest.
    class Updater
      def initialize(@fetcher : Fetcher)
      end

      def update(remote_path : String, local_path : String, etag_path : String) : Nil
        append(remote_path, local_path, etag_path) || replace(remote_path, local_path, etag_path)
      rescue ex : DigestMismatchError
        raise MismatchedChecksumError.new(remote_path, ex.message || "digest mismatch")
      end

      private def append(remote_path : String, local_path : String, etag_path : String) : Bool
        return false unless File.file?(local_path) && File.size(local_path) != 0

        etag = File.file?(etag_path) ? File.read(etag_path).chomp : nil
        # Subtract a byte to ensure the range won't be empty: avoids 416s.
        range_start = File.size(local_path) - 1
        response = @fetcher.call(remote_path, request_headers(etag, range_start))
        return true if response.not_modified?

        digests = parse_digests(response)
        if response.partial_content?
          body = response.body
          return false if body.bytesize < 1
          tail = body.byte_slice(1)
          # CacheFile.append cannot verify without digests; fall back to the
          # full replace so the cache never keeps unverified partial data.
          return false unless CacheFile.append(local_path, tail, digests)
          write_etag(etag_path, response)
          true
        else
          # server may ignore Range and return the full response
          CacheFile.write(local_path, response.body, digests)
          write_etag(etag_path, response)
          true
        end
      end

      private def replace(remote_path : String, local_path : String, etag_path : String) : Nil
        etag = File.file?(etag_path) ? File.read(etag_path).chomp : nil
        response = @fetcher.call(remote_path, request_headers(etag))
        return if response.not_modified?

        CacheFile.write(local_path, response.body, parse_digests(response))
        write_etag(etag_path, response)
      end

      private def write_etag(etag_path : String, response : FetchResponse) : Nil
        if etag = etag_from_response(response)
          File.write(etag_path, etag)
        end
      end

      private def request_headers(etag : String?, range_start : Int64? = nil) : Hash(String, String)
        headers = {} of String => String
        headers["Range"] = "bytes=#{range_start}-" if range_start
        headers["If-None-Match"] = %("#{etag}") if etag
        headers
      end

      private def etag_from_response(response : FetchResponse) : String?
        raw = response.header("ETag") || return nil
        etag = raw.lchop("W/")
        # strip surrounding quotes (server-dependent; rubygems.org sends them)
        if etag.starts_with?('"') && etag.ends_with?('"') && etag.size >= 2
          etag = etag[1...-1]
        end
        etag.empty? ? nil : etag
      end

      # RFC 8941 structured field byte sequences; unsupported algos ignored.
      private def parse_digests(response : FetchResponse) : Hash(String, String)?
        header = response.header("Repr-Digest") || response.header("Digest") || return nil

        digests = {} of String => String
        header.split(",") do |param|
          algorithm, _, value = param.partition("=")
          algorithm = algorithm.strip.downcase
          next unless SUPPORTED_DIGESTS.has_key?(algorithm)
          next unless value = byte_sequence(value)
          digests[algorithm] = value
        end
        digests.empty? ? nil : digests
      end

      private def byte_sequence(value : String) : String?
        v = value.strip
        if v.starts_with?(':') && v.ends_with?(':') && v.size >= 2
          return v[1...-1]
        end
        if v.starts_with?('"') && v.ends_with?('"') && v.size >= 2
          return v[1...-1]
        end
        v.empty? ? nil : v
      end
    end

    # Cache layout: <root>/names, <root>/versions (+.etag), <root>/info/<gem>,
    # <root>/info-etags/<gem>-<md5>; special-character names get an MD5 suffix.
    class Cache
      getter directory : String

      def initialize(@directory : String, @updater : Updater?)
        Dir.mkdir_p(File.join(directory, "info"))
        Dir.mkdir_p(File.join(directory, "info-special-characters"))
        Dir.mkdir_p(File.join(directory, "info-etags"))
        @fetched = Set(String).new
        @mutex = Mutex.new
      end

      def names : String
        fetch("names", names_path, names_etag_path)
      end

      def versions : String
        fetch("versions", versions_path, versions_etag_path)
      end

      def info(name : String, remote_checksum : String?) : String
        path = info_path(name)
        if remote_checksum && remote_checksum != file_md5(path)
          fetch("info/#{name}", path, info_etag_path(name))
        else
          read(path)
        end
      end

      def reset! : Nil
        @mutex.synchronize { @fetched.clear }
      end

      private def names_path
        File.join(@directory, "names")
      end

      private def names_etag_path
        File.join(@directory, "names.etag")
      end

      private def versions_path
        File.join(@directory, "versions")
      end

      private def versions_etag_path
        File.join(@directory, "versions.etag")
      end

      def info_path(name : String) : String
        name = validate_name!(name)
        if name.matches?(/[^a-z0-9_-]/)
          File.join(@directory, "info-special-characters", "#{name}-#{md5_hex(name)}")
        else
          File.join(@directory, "info", name)
        end
      end

      private def info_etag_path(name : String) : String
        name = validate_name!(name)
        File.join(@directory, "info-etags", "#{name}-#{md5_hex(name)}")
      end

      private def validate_name!(name : String) : String
        # Gem names come from the remote index; refuse path escapes.
        raise Error.new("malformed gem name: #{name.inspect}") if File.basename(name) != name
        name
      end

      private def md5_hex(name : String) : String
        Digest::MD5.hexdigest(name).downcase
      end

      private def file_md5(path : String) : String?
        return nil unless File.file?(path)
        Digest::MD5.hexdigest(File.read(path)).downcase
      end

      private def fetch(remote_path : String, path : String, etag_path : String) : String
        already = @mutex.synchronize { !@fetched.add?(remote_path) }
        unless already
          @updater.try(&.update(remote_path, path, etag_path))
        end
        read(path)
      end

      private def read(path : String) : String
        File.file?(path) ? File.read(path) : ""
      end
    end

    struct InfoDependency
      getter name : String
      getter requirements : Array(String)

      def initialize(@name : String, @requirements : Array(String))
      end
    end

    struct InfoRequirement
      getter key : String
      getter values : Array(String)

      def initialize(@key : String, @values : Array(String))
      end
    end

    struct InfoEntry
      getter version : String
      getter platform : String?
      getter dependencies : Array(InfoDependency)
      getter requirements : Array(InfoRequirement)

      def initialize(@version : String, @platform : String?,
                     @dependencies : Array(InfoDependency),
                     @requirements : Array(InfoRequirement))
      end

      def checksum : String?
        requirements.find(&.key.==("checksum")).try(&.values.first?)
      end

      def required_ruby_version_list : Array(String)
        requirements.find(&.key.==("ruby")).try(&.values) || [] of String
      end

      def required_rubygems_version_list : Array(String)
        requirements.find(&.key.==("rubygems")).try(&.values) || [] of String
      end

      # platform-less entries are the virtual ruby platform
      def platform_ruby? : Bool
        platform.nil? || platform.try(&.empty?) || platform == "ruby"
      end
    end

    # Port of `Bundler::CompactIndexClient::Parser` plus
    # `Gem::Resolver::APISet::GemParser` line grammar.
    class Parser
      def initialize(@compact_index : Cache)
      end

      def names : Array(String)
        lines(@compact_index.names)
      end

      def versions : Hash(String, Array(VersionLine))
        result = Hash(String, Array(VersionLine)).new
        lines(@compact_index.versions).each do |line|
          next if line.empty?
          parts = line.split(" ", 3)
          name = parts[0]?
          versions_string = parts[1]? || next
          checksum = parts[2]?
          next if name.nil?
          bucket = result[name] ||= [] of VersionLine
          versions_string.split(",") do |entry|
            next if entry.empty?
            yanked = entry.starts_with?("-")
            version_part = yanked ? entry.lchop("-") : entry
            vparts = version_part.split("-", 2)
            line = VersionLine.new(name, vparts[0], vparts[1]? || "ruby", yanked, checksum || "")
            if yanked
              bucket.delete(line)
            else
              bucket << line
            end
          end
        end
        result
      end

      def info_checksums : Hash(String, String)
        checksums = {} of String => String
        lines(@compact_index.versions).each do |line|
          name_end = line.index(" ") || next
          checksum_start = line.index(" ", name_end + 1) || next
          checksums[line[0, name_end]] = line[(checksum_start + 1)..]
        end
        checksums
      end

      def info(name : String) : Array(InfoEntry)
        data = @compact_index.info(name, info_checksums[name]?)
        lines(data).map do |line|
          parse_info_line(name, line)
        end
      end

      private def parse_info_line(name : String, line : String) : InfoEntry
        segments = line.split(" ", 2)
        version_and_platform = segments[0]
        rest = segments[1]?
        parts = version_and_platform.split("-", 2)
        version = parts[0]
        platform = parts[1]?

        dependencies = [] of InfoDependency
        requirements = [] of InfoRequirement
        if rest
          deps_string, _, reqs_string = rest.partition("|")
          deps_string.split(",").each do |dep|
            next if dep.empty?
            dep_name, _, dep_reqs = dep.partition(":")
            dependencies << InfoDependency.new(dep_name, dep_reqs.empty? ? [] of String : dep_reqs.split("&"))
          end
          if reqs_string && !reqs_string.empty?
            reqs_string.split(",").each do |req|
              next if req.empty?
              key, _, values = req.partition(":")
              requirements << InfoRequirement.new(key, values.empty? ? [] of String : values.split("&"))
            end
          end
        end

        InfoEntry.new(version, platform, dependencies, requirements)
      end

      private def lines(data : String?) : Array(String)
        return [] of String if data.nil? || data.empty?
        all = data.split("\n").map(&.chomp('\r'))
        header = all.index("---")
        body = header ? all[(header + 1)..] : all
        body.reject(&.empty?)
      end
    end

    struct VersionLine
      getter name : String
      getter version : String
      getter platform : String
      getter yanked : Bool
      getter info_checksum : String

      def initialize(@name : String, @version : String, @platform : String, @yanked : Bool, @info_checksum : String)
      end
    end

    # Facade mirroring `Bundler::CompactIndexClient`.
    class Client
      @parser : Parser

      def initialize(remote : String, cache_root : String, credentials : {String, String}? = nil)
        fetcher = make_fetcher(remote, credentials)
        cache_dir = File.join(cache_root, cache_key(remote))
        @parser = Parser.new(Cache.new(cache_dir, Updater.new(fetcher)))
      end

      def available? : Bool
        !@parser.info_checksums.empty?
      end

      def versions : Hash(String, Array(VersionLine))
        @parser.versions
      end

      def info(name : String) : Array(InfoEntry)
        @parser.info(name)
      end

      private def make_fetcher(remote : String, credentials : {String, String}?) : Fetcher
        if remote.starts_with?("file:")
          # Use URI parsing so file:///C:/..., file:///home/... and
          # file:/C:/... all resolve to an absolute local path.
          uri = URI.parse(remote)
          path = uri.path || ""
          if (h = uri.host) && !h.empty? && !path.includes?(":")
            # file://host/path with a non-drive host — fold host into path
            path = "/#{h}#{path}"
          end
          path = path.gsub(/\\/, "/")
          # collapse a doubled leading slash (file:////abs) before expand:
          # POSIX expand keeps "//" (UNC on Windows)
          path = path.sub(%r{^/{2,}}, "/")
          # file:///C:/... leaves a leading slash before the drive letter
          path = path.sub(/^\/[A-Za-z]:\//) { |m| m[1..] }
          path = File.expand_path(path)
          path += "/" unless path.ends_with?("/")
          FileFetcher.new(path)
        else
          HttpFetcher.for(remote, credentials)
        end
      end

      private def cache_key(remote : String) : String
        sanitized = remote.gsub(/[^a-z0-9_.\-]/i, "-").downcase
        Digest::MD5.hexdigest(remote)[0, 8] + "-" + sanitized[0, 64]
      end
    end
  end
end
