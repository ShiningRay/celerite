require "socket"
require "uri"
require "./config"

module Celerite
  # Bundler mirror availability probing (pinned reference:
  # `vendor/reference/v4.0.24/mirror.rb` and bundler-4.0.24 `mirror.rb`
  # L57-221). A mirror configured with a non-zero `fallback_timeout` is only
  # used when a TCP connection to its host:port succeeds within that timeout;
  # otherwise the caller falls back to the original remote (the reference
  # treats the mirror as invalid in `Mirror#validate!` and `Mirrors#for`
  # returns the source URI).
  module Mirror
    # `Mirror::DEFAULT_FALLBACK_TIMEOUT` (mirror.rb L63).
    DEFAULT_FALLBACK_TIMEOUT = 0.1

    # `Mirror#fallback_timeout=` (mirror.rb L82-92): `true`/"true" -> 0.1s,
    # `false`/"false" -> 0s (probing disabled), numeric -> that many seconds.
    # Parsing lives in Config so both the getter and this helper share one
    # implementation (config.cr must not depend on this file).
    def self.fallback_timeout_seconds(value : Config::ConvertedValue) : Float64?
      Config.fallback_timeout_seconds(value)
    end

    # `TCPSocketProbe#replies?` (mirror.rb L148-176): a mirror is reachable
    # when a TCP handshake to its host:port completes within `timeout`.
    # Bundler skips probing entirely when `fallback_timeout == 0`.
    def self.reachable?(url : String, timeout : Float64) : Bool
      return true if timeout <= 0
      uri = URI.parse(url)
      host = uri.host
      return false if host.nil? || host.empty?
      port = uri.port || (uri.scheme.try(&.downcase) == "https" ? 443 : 80)
      socket = TCPSocket.new(host, port, connect_timeout: timeout.seconds)
      socket.close
      true
    rescue
      false
    end

    # `Mirrors#for` (mirror.rb L48-54): an invalid/unreachable mirror degrades
    # to the original remote. No configured fallback timeout keeps the legacy
    # behavior (mirror first, Downloader retries the original remote on
    # failure); an explicit 0 disables probing the same way.
    def self.resolve(config : Config, remote : String) : String?
      mirror = config.mirror_for(remote)
      return nil if mirror.nil?
      timeout = config.mirror_fallback_timeout(remote)
      return mirror if timeout.nil? || timeout == 0.0
      reachable?(mirror, timeout) ? mirror : nil
    end
  end
end
