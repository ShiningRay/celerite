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
    getter retries : Int32
    getter mirror_url : String?
    getter ssl_ca_cert : String?
    getter ssl_client_cert : String?
    getter ssl_verify_mode : String?

    def initialize(@remote : String, cache_root : String, retries : Int32 = 3, mirror_url : String? = nil, ssl_ca_cert : String? = nil, ssl_client_cert : String? = nil, ssl_verify_mode : String? = nil)
      @mirror_url = mirror_url
      @ssl_ca_cert = ssl_ca_cert
      @ssl_client_cert = ssl_client_cert
      @ssl_verify_mode = ssl_verify_mode
      @download_dir = File.join(cache_root, "downloads")
      Dir.mkdir_p(@download_dir)
      @inflight = Hash(String, Channel(String?)).new
      @mutex = Mutex.new
      @retries = retries < 0 ? 0 : retries
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

    private def download_to(name : String, version : String, platform : String?, path : String, allow_mirror : Bool = true) : Nil
      full_name = (platform.nil? || platform == "ruby") ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      remote_path = "/gems/#{full_name}.gem"

      # Bundler mirror support: try the mirror first, then fall back to the
      # original remote. allow_mirror=false prevents retrying the mirror
      # after it already failed (and avoids unbounded recursion).
      if allow_mirror && (mirror = @mirror_url)
        saved = @remote
        begin
          @remote = mirror
          download_to(name, version, platform, path, allow_mirror: false)
          @remote = saved
          return
        rescue
          @remote = saved
        end
      end

      if @remote.starts_with?("file:")
        # URI parsing keeps absolute POSIX paths intact (file:///home/...)
        # and folds Windows drive paths (file:///C:/...)
        uri = URI.parse(@remote)
        root = uri.path || ""
        if (h = uri.host) && !h.empty? && !h.includes?(".") && !root.includes?(":")
          root = "/#{h}#{root}"
        end
        # collapse a doubled leading slash (file:////abs) before expand:
        # POSIX expand keeps "//" (UNC on Windows)
        root = root.gsub(/\\/, "/").sub(%r{^/{2,}}, "/")
        # file:///C:/... leaves a leading slash before the drive letter
        root = root.sub(/^\/[A-Za-z]:\//) { |m| m[1..] }
        root = root.sub(/^\/[A-Za-z]:\//) { |m| m[1..] }
        root = File.expand_path(root)
        source = File.expand_path(remote_path.lstrip('/'), root)
        raise Error.new("gem file not found: #{full_name}.gem") unless File.file?(source)
        File.write(path, File.read(source))
        return
      end

      uri = URI.parse(@remote)
      tls_ctx = nil
      if uri.scheme == "https"
        ctx = OpenSSL::SSL::Context::Client.new
        if ca = @ssl_ca_cert
          ctx.ca_certificates = ca
        end
        if mode = @ssl_verify_mode
          case mode.downcase
          when "none"
            ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
          when "peer"
            ctx.verify_mode = OpenSSL::SSL::VerifyMode::PEER
          end
        end
        tls_ctx = ctx
      end
      client = HTTP::Client.new(uri, tls: tls_ctx)
      client.connect_timeout = 30.seconds
      client.read_timeout = 120.seconds
      # Retry with exponential backoff (pinned Bundler behavior).
      max_attempts = {@retries + 1, 1}.max
      attempt = 0
      loop do
        attempt += 1
        begin
          response = client.get(remote_path)
        rescue ex
          client.close rescue nil
          if attempt < max_attempts
            sleep (0.5 * (2 ** (attempt - 1))).seconds
            client = HTTP::Client.new(URI.parse(@remote))
            client.connect_timeout = 30.seconds
            client.read_timeout = 120.seconds
            next
          end
          raise ex
        end
        if response.status_code == 200
          File.write(path, response.body)
          client.close rescue nil
          return
        elsif response.status_code == 301 || response.status_code == 302 || response.status_code == 303 || response.status_code == 307 || response.status_code == 308
          # Follow redirect
          if loc = response.headers["Location"]?
            client.close rescue nil
            @remote = loc
            return download_to(name, version, platform, path, allow_mirror: false)
          end
        end
        if attempt < max_attempts
          sleep (0.5 * (2 ** (attempt - 1))).seconds
          next
        end
        client.close rescue nil
        raise GemNotFoundError.new("Could not fetch gem #{full_name} from #{@remote} (HTTP #{response.status_code})")
      end
    end
  end
end
