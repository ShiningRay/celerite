module Celerite
  # `Bundler::URICredentialsFilter` (bundler/uri_credentials_filter.rb): the
  # reference never renders a source URI together with its userinfo. The
  # reference helper keeps the user part (`uri.password = nil`) because it is
  # normally handed an already-anonymised URI; the measured 4.0.24 output for
  # `source "http://user:pass@host/"` is `Fetching gem metadata from
  # http://host/.` with no `user@`, so this port drops the whole userinfo and
  # reproduces the observed line byte for byte.
  module URICredentialsFilter
    def self.credential_filtered_uri(remote : String) : String
      uri = URI.parse(remote)
      return remote if uri.user.nil? && uri.password.nil?
      scheme = uri.scheme
      return remote if scheme.nil?
      host = uri.host || ""
      port = uri.port ? ":#{uri.port}" : ""
      query = uri.query ? "?#{uri.query}" : ""
      "#{scheme}://#{host}#{port}#{uri.path}#{query}"
    rescue URI::Error
      remote
    end

    def self.credential_filtered_uri(uri : URI) : String
      credential_filtered_uri(uri.to_s)
    end
  end
end
