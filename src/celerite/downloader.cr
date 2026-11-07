require "./compact_index/cache"
require "./gem/platform"
require "./errors"
require "digest/sha256"
require "base64"

module Celerite
  # Downloads and verifies .gem files (architecture §3: checksummed downloads,
  # content-addressed cache, single-flight dedup per name/version/platform).
  class Downloader
    class ChecksumMismatchError < Error
      def status_code : Int32
        37 # Bundler::SecurityError
      end

      def wrap? : Bool
        true
      end
    end

    getter download_dir : String

    def initialize(@remote : String, cache_root : String)
      @download_dir = File.join(cache_root, "downloads")
      Dir.mkdir_p(@download_dir)
      @inflight = Hash(String, Channel(String?)).new
      @mutex = Mutex.new
    end

    # Downloads (or reuses) the .gem for one spec and returns the cached path.
    # `checksum` is the compact index checksum (hex or base64 sha256); when
    # present the downloaded artifact is verified before it is published.
    # A checksum mismatch leaves no usable artifact (architecture §4).
    def fetch(name : String, version : String, platform : String?, checksum : String?) : String
      key = "#{name}-#{version}-#{platform || "ruby"}"

      channel : Channel(String?)? = nil
      owner = false
      @mutex.synchronize do
        if existing = @inflight[key]?
          channel = existing
        else
          channel = Channel(String?).new(1)
          @inflight[key] = channel
          owner = true
        end
      end

      unless owner
        result = channel.not_nil!.receive
        return result || raise Error.new("download failed for #{key}")
      end

      begin
        result = fetch_uncached(name, version, platform, checksum)
        channel.not_nil!.send(result)
        @mutex.synchronize { @inflight.delete(key) }
        result || raise Error.new("download failed for #{key}")
      rescue ex
        channel.not_nil!.send(nil)
        @mutex.synchronize { @inflight.delete(key) }
        raise ex
      end
    end

    private def fetch_uncached(name : String, version : String, platform : String?, checksum : String?) : String?
      cache_path = cached_path(name, version, platform)

      if File.file?(cache_path)
        if checksum.nil? || verify(cache_path, checksum)
          return cache_path
        end
        # corrupted cache entry: remove and re-download
        File.delete(cache_path)
      end

      temp_path = "#{cache_path}.#{Process.pid}.tmp"
      begin
        download_to(name, version, platform, temp_path)
        if checksum && !verify(temp_path, checksum)
          File.delete(temp_path)
          raise ChecksumMismatchError.new(
            "SHA256 mismatch for #{name}-#{version}: downloaded artifact does not match the compact index checksum"
          )
        end
        File.rename(temp_path, cache_path)
        cache_path
      ensure
        File.delete(temp_path) if File.file?(temp_path)
      end
    end

    def cached_path(name : String, version : String, platform : String?) : String
      digest = Digest::SHA256.hexdigest("#{name}-#{version}-#{platform || "ruby"}")
      File.join(@download_dir, digest[0, 16] + "-#{name}-#{version}.gem")
    end

    private def verify(path : String, checksum : String) : Bool
      expected = normalize_checksum(checksum)
      return true if expected.nil?

      actual = Digest::SHA256.hexdigest(File.read(path))
      actual.downcase == expected.downcase
    end

    # Compact index checksums are raw hex, raw base64 or `sha256=<...>`.
    private def normalize_checksum(raw : String) : String?
      value = raw.lchop("sha256=").strip
      return nil if value.empty?
      if value.matches?(/\A[0-9a-f]{64}\z/i)
        return value
      end
      if value.matches?(/\A[-0-9a-z_+\/]{43}={0,2}\z/i)
        decoded = Base64.decode_string(value.tr("-_", "+/"))
        return decoded.bytes.map { |b| b.to_s(16, precision: 2) }.join
      end
      nil
    end

    private def download_to(name : String, version : String, platform : String?, path : String) : Nil
      full_name = (platform.nil? || platform == "ruby") ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      remote_path = "/gems/#{full_name}.gem"

      if @remote.starts_with?("file:")
        root = @remote.lchop("file:").lstrip('/')
        root += "/" unless root.ends_with?("/")
        source = File.expand_path(remote_path.lstrip('/'), root)
        raise Error.new("gem file not found: #{full_name}.gem") unless File.file?(source)
        File.write(path, File.read(source))
        return
      end

      uri = URI.parse(@remote)
      client = HTTP::Client.new(uri)
      client.connect_timeout = 30.seconds
      client.read_timeout = 120.seconds
      response = client.get(remote_path)
      unless response.status_code == 200
        raise GemNotFoundError.new("Could not fetch gem #{full_name} from #{@remote} (HTTP #{response.status_code})")
      end
      File.write(path, response.body)
    end
  end
end
