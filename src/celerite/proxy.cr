require "uri"
require "base64"
require "./config"

module Celerite
  # HTTP proxy selection mirroring the reference (`net-http-persistent`'s
  # `proxy_from_env`, vendored by Bundler and wired in `fetcher.rb`):
  #
  # - only `http_proxy`/`HTTP_PROXY` is consulted (lowercase wins, empty value
  #   means "no proxy"); `https_proxy`/`ALL_PROXY` are deliberately ignored,
  #   exactly like the reference;
  # - a proxy without a scheme is treated as `http://`;
  # - `http_proxy_user`/`http_proxy_pass` (and uppercase variants) fill in
  #   credentials missing from the URI;
  # - `.bundle/config` `proxy`/`http_proxy` win over the environment.
  #
  # This type is pure: it never opens sockets, so it can be unit tested
  # offline. Routing lives in `HttpTransport`.
  struct Proxy
    getter uri : URI
    getter user : String?
    getter password : String?

    def initialize(@uri : URI, @user : String?, @password : String?)
    end

    # Proxy configured through `http_proxy`/`HTTP_PROXY` only.
    def self.from_environment : Proxy?
      raw = ENV["http_proxy"]? || ENV["HTTP_PROXY"]?
      return nil if raw.nil? || raw.strip.empty?
      parse(raw, env_credential("http_proxy_user", "HTTP_PROXY_USER"), env_credential("http_proxy_pass", "HTTP_PROXY_PASS"))
    end

    # `.bundle/config` keys first (`proxy` then `http_proxy`), then the
    # environment. The config value intentionally overrides `http_proxy`.
    def self.resolve(config : Config) : Proxy?
      {"proxy", "http_proxy"}.each do |key|
        value = config[key].to_s
        next if value.strip.empty?
        proxy = parse(value, env_credential("http_proxy_user", "HTTP_PROXY_USER"), env_credential("http_proxy_pass", "HTTP_PROXY_PASS"))
        return proxy if proxy
      end
      from_environment
    end

    def host : String
      @uri.host.not_nil!
    end

    def port : Int32
      @uri.port || 80
    end

    # `Proxy-Authorization` value, or nil when the proxy needs no credentials.
    def authorization : String?
      user = @user
      return nil if user.nil?
      "Basic " + Base64.strict_encode("#{user}:#{@password || ""}")
    end

    # `no_proxy` semantics from `net-http-persistent#proxy_bypass?`: a comma
    # separated list of suffixes; a value of exactly `*` bypasses everything.
    # An entry may carry a port (`example.com:8080`).
    def bypass?(host : String, port : Int32) : Bool
      raw = ENV["no_proxy"]? || ENV["NO_PROXY"]?
      return false if raw.nil?
      text = raw.strip
      return false if text.empty?
      return true if text == "*"

      target = host.downcase
      target_with_port = "#{target}:#{port}"
      text.split(',').each do |entry|
        name = entry.strip.downcase
        next if name.empty?
        return true if target.ends_with?(name) || target_with_port.ends_with?(name)
      end
      false
    end

    private def self.env_credential(lower : String, upper : String) : String?
      value = ENV[lower]? || ENV[upper]?
      return nil if value.nil? || value.empty?
      value
    end

    private def self.parse(raw : String, user : String?, password : String?) : Proxy?
      text = raw.strip
      return nil if text.empty?
      text = "http://#{text}" unless text.includes?("://")
      uri = URI.parse(text)
      host = uri.host
      return nil if host.nil? || host.empty?

      new(uri, uri.user || user, uri.password || password)
    rescue URI::Error
      nil
    end
  end
end
