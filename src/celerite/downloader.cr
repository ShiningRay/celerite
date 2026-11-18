require "./compact_index/cache"
require "./file_url"
require "./tls"
require "./proxy"
require "./http_transport"
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

    # A 403 on the gem artifact itself comes from RubyGems' downloader, which
    # retries the fetch and then reports a `Bundler::HTTPError`-shaped failure
    # (status 5). The reference's message is
    # "Could not download gem from <source> due to underlying error <…>"; the
    # Ruby backtrace it also prints cannot be reproduced here.
    class ForbiddenDownloadError < Error
      def initialize(@source : String, @url : String, @name : String? = nil, @version : String? = nil)
        super(nil)
      end

      def status_code : Int32
        5
      end

      def wrap? : Bool
        true
      end

      def message : String
        # `Bundler::HTTPError` surfaces the source plus the artifact URL
        # (oracle 4.0.24); the class name is prefixed by the install failure
        # formatter like every other `BundlerError`.
        "Could not download gem from #{@source} due to underlying error " \
        "<bad response Forbidden 403 (#{@url})>"
      end

      def error_class_name : String
        "Bundler::HTTPError"
      end
    end

    getter download_dir : String
    getter retries : Int32
    getter mirror_url : String?
    getter ssl_ca_cert : String?
    getter ssl_client_cert : String?
    getter ssl_verify_mode : String?
    getter credentials : {String, String}?
    getter timeout : Int32
    getter max_redirects : Int32
    getter redirect_count : Int32
    getter proxy : Proxy?

    # Expose the configured per-request timeout as a Time::Span so callers
    # and specs can assert the exact connect/read timeout applied to clients.
    def connect_timeout : Time::Span
      @timeout.seconds
    end

    def initialize(@remote : String, cache_root : String, retries : Int32 = 3, mirror_url : String? = nil, ssl_ca_cert : String? = nil, ssl_client_cert : String? = nil, ssl_verify_mode : String? = nil, @credentials : {String, String}? = nil, timeout : Int32 = 30, max_redirects : Int32 = 5, proxy : Proxy? = nil, @warning_io : IO? = nil, @notice : Proc(Nil)? = nil)
      @mirror_url = mirror_url
      @ssl_ca_cert = ssl_ca_cert
      @ssl_client_cert = ssl_client_cert
      @ssl_verify_mode = ssl_verify_mode
      # An explicit proxy (from `.bundle/config`) wins; otherwise honor the
      # `http_proxy` environment like the reference fetcher does.
      @proxy = proxy || Proxy.from_environment
      @timeout = timeout < 1 ? 30 : timeout
      @max_redirects = max_redirects < 0 ? 0 : max_redirects
      @redirect_count = 0
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

    # Compact index checksums are raw hex, raw base64 or `sha256=<...>`;
    # normalization is shared with the lockfile writer (Checksum.normalize_hex).
    private def normalize_checksum(raw : String) : String?
      Celerite::Checksum.normalize_hex(raw)
    end

    private def download_to(name : String, version : String, platform : String?, path : String, allow_mirror : Bool = true, request_path : String? = nil) : Nil
      @redirect_count = 0 if allow_mirror
      full_name = (platform.nil? || platform == "ruby") ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      remote_path = request_path || "/gems/#{full_name}.gem"

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
        # Same rules as the compact-index file fetcher: ignore the URI host,
        # drop a slash before a drive letter, keep a UNC "//" prefix.
        root = FileURL.directory(@remote)
        source = File.expand_path(remote_path.lstrip('/'), root)
        raise Error.new("gem file not found: #{full_name}.gem") unless File.file?(source)
        File.write(path, File.read(source))
        return
      end

      uri = URI.parse(@remote)
      tls_ctx = nil
      if uri.scheme == "https"
        ctx = OpenSSL::SSL::Context::Client.new
        Celerite::TLS.configure_trust_store(ctx, @ssl_ca_cert)
        if cert = @ssl_client_cert
          Celerite::TLS.configure_client_certificate(ctx, cert)
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
      headers = HTTP::Headers.new
      if creds = @credentials
        headers["Authorization"] = basic_authorization(creds[0], creds[1])
      elsif uri.user || uri.password
        headers["Authorization"] = basic_authorization(uri.user || "", uri.password || "")
      end
      # Retry with exponential backoff (pinned Bundler behavior).
      max_attempts = {@retries + 1, 1}.max
      attempt = 0
      loop do
        attempt += 1
        begin
          response = HttpTransport.get(URI.parse(@remote), remote_path, headers, tls_ctx, @proxy, @timeout)
        rescue ex : AuthenticationRequiredError | BadAuthenticationError | AuthenticationForbiddenError
          # Authentication failures are terminal (no retry) like the reference.
          raise ex
        rescue ex
          if attempt < max_attempts
            sleep (0.5 * (2 ** (attempt - 1))).seconds
            next
          end
          raise ex
        end
        if response.status_code == 200
          File.write(path, response.body)
          return
        elsif response.status_code == 401
          # fetcher/downloader.rb:70-71: 401 with `uri.userinfo` present means
          # the credentials were rejected; without them the source simply
          # requires authentication. The message names the host.
          host = uri.host || uri.to_s
          raise AuthenticationRequiredError.new(host) unless @credentials || uri.user || uri.password
          raise BadAuthenticationError.new(host)
        elsif response.status_code == 403
          # RubyGems' own downloader (not the metadata fetcher) performs the gem
          # download, so a 403 here is retried like any other fetch error:
          # `Retrying download gem from <source> due to error (n/4):
          # Gem::RemoteFetcher::FetchError bad response Forbidden 403 (<url>)`
          # (oracle: 4.0.24 gem download 403 → three retry lines then
          # `Bundler::HTTPError: Could not download gem from …` and exit 5).
          if attempt < max_attempts
            if warning = @warning_io
              # `Bundler::Retry#fail_attempt` prints a blank line on stdout
              # before the warning (`retry.rb:60-64`), which is why the oracle
              # stdout ends with several empty lines.
              @notice.try(&.call)
              gem_url = "#{@remote.chomp("/")}#{remote_path}"
              warning.puts "Retrying download gem from #{@remote} due to error (#{attempt + 1}/#{max_attempts}): " \
                           "Gem::RemoteFetcher::FetchError bad response Forbidden 403 (#{gem_url})"
            end
            sleep (0.5 * (2 ** (attempt - 1))).seconds
            next
          end
          @notice.try(&.call)
          raise ForbiddenDownloadError.new(@remote, "#{@remote.chomp("/")}#{remote_path}", name, version)
        elsif response.status_code == 301 || response.status_code == 302 || response.status_code == 303 || response.status_code == 307 || response.status_code == 308
          # Follow redirect, honoring BUNDLE_REDIRECT max-redirect limit.
          if loc = response.headers["Location"]?
            if @redirect_count >= @max_redirects
              raise DownloadError.new("Too many redirects (>#{@max_redirects}) for #{@remote}")
            end
            @redirect_count += 1
            # `Location` may be absolute or relative (RFC 9110 §10.2.2);
            # resolve it against the URL that produced the redirect so the
            # follow-up request carries a host. The redirect target also
            # replaces the request path (Bundler requests the Location URL
            # verbatim); rebuilding "/gems/<full>.gem" would loop forever.
            resolved = resolve_redirect_location(@remote, loc)
            target = URI.parse(resolved)
            request = target.request_target
            request = "/" if request.empty?
            @remote = resolved
            return download_to(name, version, platform, path, allow_mirror: false, request_path: request)
          end
        end
        if attempt < max_attempts
          sleep (0.5 * (2 ** (attempt - 1))).seconds
          next
        end
        raise GemNotFoundError.new("Could not fetch gem #{full_name} from #{@remote} (HTTP #{response.status_code})")
      end
    end

    private def basic_authorization(user : String, password : String) : String
      "Basic " + Base64.strict_encode("#{user}:#{password}")
    end

    # RFC 9110 §10.2.2: `Location` may be relative; resolve it against the
    # request URL so a subsequent `URI.parse` still has a host (Bundler gets
    # this for free from URI.join in the reference implementation).
    private def resolve_redirect_location(base : String, location : String) : String
      ref = URI.parse(location)
      return location if ref.host
      URI.parse(base).resolve(ref).to_s
    rescue
      location
    end
  end
end
