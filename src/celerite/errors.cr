require "uri"

module Celerite
  # Base error for all Celerite failures surfaced to the CLI.
  #
  # Status codes mirror `Bundler::Error#status_code` at the pinned revision
  # (see docs/compat-matrix/cli-commands.md).
  class Error < Exception
    def status_code : Int32
      1
    end

    # Exception-path errors render through the friendly-errors pipeline,
    # which word-wraps the message at the terminal width (Thor parity).
    def wrap? : Bool
      false
    end
  end

  # Raised for user-facing CLI usage mistakes (unknown command, bad flags).
  # Thor::Error maps to exit code 15.
  class UsageError < Error
    def status_code : Int32
      15
    end
  end

  # Raised when an operation has no native implementation yet; the CLI reports
  # the engine explicitly instead of silently degrading (architecture §2.3).
  class UnsupportedCommandError < Error
  end

  # Raised when input violates the RubyGems version grammar (mirrors Ruby's
  # ArgumentError from Gem::Version.new).
  class VersionError < Error
  end

  # Raised when a requirement string is malformed (mirrors
  # Gem::Requirement::BadRequirementError).
  class BadRequirementError < Error
  end

  # Bundler::SolveFailure — dependency resolution failure.
  class SolveFailureError < Error
    def status_code : Int32
      6
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::GemNotFound.
  class GemNotFoundError < Error
    def status_code : Int32
      7
    end

    def wrap? : Bool
      true
    end
  end

  # Raised when a Gemfile cannot be located (mirrors Bundler::GemfileNotFound).
  class GemfileNotFound < Error
    def status_code : Int32
      10
    end
  end

  # Bundler::ProductionError — frozen-mode validation failures.
  class ProductionError < Error
    def status_code : Int32
      16
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::AuthenticationRequiredError (fetcher.rb:45-52, status 17):
  # the source answered 401/403 and no usable credentials were supplied. The
  # message names the host (not the full URL) and the BUNDLE_* key the user
  # would have to set, matching the reference's `Settings.key_for(host)`.
  class AuthenticationRequiredError < Error
    getter host : String

    def initialize(@host : String)
      super("Authentication is required for #{@host}.\n" \
            "Please supply credentials for this source. You can do this by running:\n" \
            "`bundle config set --global #{@host} username:password`\n" \
            "or by storing the credentials in the `#{Config.key_for(@host)}` environment variable")
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::BadAuthenticationError (fetcher.rb:54-58, status 17):
  # credentials were sent but the source still answered 401.
  class BadAuthenticationError < Error
    getter host : String

    def initialize(@host : String)
      super("Bad username or password for #{@host}.\n" \
            "Please double-check your credentials and correct them.")
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::AuthenticationForbiddenError (fetcher.rb:60-64, status
  # 17). Kept for completeness; the measured 4.0.24 oracle reports a plain 403
  # without `WWW-Authenticate` as AuthenticationRequiredError, so call sites map
  # 403 there and this class is not raised yet.
  class AuthenticationForbiddenError < Error
    getter host : String

    def initialize(@host : String)
      super("Access token could not be authenticated for #{@host}.\n" \
            "Make sure it's valid and has the necessary scopes configured.")
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::PermissionError (errors.rb:94-128, status 23): a filesystem
  # operation was denied. The reference raises this from
  # `SharedHelpers#filesystem_access` (shared_helpers.rb:105-127) and the lock
  # writer wraps the write in it (definition.rb:436-442). Most filesystem
  # errors subclass this and only replace the closing sentence; `action` is the
  # `filesystem_access` action (:read/:write/:create/:executable) and `:create`
  # names the parent folder because creating a file needs write access to it.
  class PermissionError < Error
    getter path : String
    getter permission_type : Symbol

    def initialize(path : String, @permission_type : Symbol = :write)
      @path = path.gsub('\\', "/")
      super(message)
    end

    protected def action_phrase : String
      case permission_type
      when :read       then "read from"
      when :write      then "write to"
      when :executable then "execute"
      when :exec       then "execute"
      else                  permission_type.to_s
      end
    end

    protected def permission_description : String
      if permission_type == :create
        "executable permissions for all parent directories and write permissions for `#{parent_folder}`"
      else
        "#{permission_type} permissions for that path"
      end
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. It is likely that you need to grant #{permission_description}."
    end

    def message : String
      default_message
    end

    def parent_folder : String
      File.dirname(path)
    end

    def status_code : Int32
      23
    end

    def wrap? : Bool
      true
    end
  end

  # bundler/errors.rb:156-164. The reference concatenates "try" and
  # "the operation again." without a space, so the message really says
  # "trythe"; kept verbatim for parity.
  class TemporaryResourceError < PermissionError
    def status_code : Int32
      26
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. Some resource was temporarily unavailable. It's suggested that you trythe operation again."
    end
  end

  # bundler/errors.rb:166-173 (a BundlerError, not a PermissionError: the
  # message carries no path/action).
  class VirtualProtocolError < Error
    def initialize
      super(nil)
    end

    def status_code : Int32
      27
    end

    def message : String
      "There was an error relating to virtualization and file access. It is likely that you need to grant access to or mount some file system correctly."
    end

    def wrap? : Bool
      true
    end
  end

  # bundler/errors.rb:175-181.
  class OperationNotSupportedError < PermissionError
    def status_code : Int32
      28
    end

    protected def default_message : String
      "Attempting to #{action_phrase} `#{path}` is unsupported by your OS."
    end
  end

  # bundler/errors.rb:183-190.
  class NoSpaceOnDeviceError < PermissionError
    def status_code : Int32
      31
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. There was insufficient space remaining on the device."
    end
  end

  # bundler/errors.rb:192-199.
  class ReadOnlyFileSystemError < PermissionError
    def status_code : Int32
      42
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. File system is read-only."
    end
  end

  # bundler/errors.rb:201-208.
  class OperationNotPermittedError < PermissionError
    def status_code : Int32
      43
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. Underlying OS system call raised an EPERM error."
    end
  end

  # bundler/errors.rb:210-219.
  class GenericSystemCallError < Error
    getter underlying_error : Exception

    def initialize(message : String, @underlying_error : Exception)
      super(message)
    end

    def message : String
      "#{super}\nThe underlying system error is #{underlying_error.class}: #{underlying_error}"
    end

    def status_code : Int32
      32
    end

    def wrap? : Bool
      true
    end
  end

  # Raised for lockfile parse/validation failures (mirrors Bundler::LockfileError).
  class LockfileError < Error
    def status_code : Int32
      20
    end

    def wrap? : Bool
      true
    end
  end

  # Raised when the running Ruby does not satisfy the Gemfile/lockfile Ruby
  # requirement (mirrors Bundler::RubyVersionMismatch).
  class RubyVersionMismatch < Error
    def status_code : Int32
      18
    end
  end

  # Raised when a download fails due to too many redirects or other
  # transport-level failures (mirrors Bundler::HTTPError).
  class DownloadError < Error
    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::NetworkDownError (an HTTPError, exit 17): the connection
  # could not be established at all. The reference labels the host from the
  # request URI and keeps `:port` only when the URL spells out a non-default
  # port (bundler/fetcher/downloader.rb:96-103).
  class NetworkDownError < Error
    # The original socket/DNS error, kept for diagnostics (never swallowed).
    getter socket_error : Exception?

    def initialize(message : String, @socket_error : Exception? = nil)
      super(message)
    end

    def self.message_for(uri : URI) : String
      host = uri.host || "unknown host"
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
      host_port = "#{host}:#{port}"
      host = host_port if uri.to_s.includes?(host_port)
      "Could not reach host #{host}. Check your network connection and try again."
    end

    def self.for(uri : URI, socket_error : Exception? = nil) : NetworkDownError
      new(message_for(uri), socket_error)
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::CertificateFailureError (an HTTPError, exit 17): the TLS
  # handshake could not verify the peer certificate. Message and layout mirror
  # bundler/fetcher.rb:25-34 verbatim (newline after the URI). Bundler filters
  # credentials with URICredentialsFilter; this port has no equivalent helper,
  # so `display_uri` drops userinfo instead of printing secrets.
  class CertificateFailureError < Error
    # The original OpenSSL error, kept for diagnostics (never swallowed).
    getter ssl_error : Exception?

    def initialize(message : String, @ssl_error : Exception? = nil)
      super(message)
    end

    def self.message_for(uri : URI) : String
      "Could not verify the SSL certificate for #{display_uri(uri)}.\n" \
      "There is a chance you are experiencing a man-in-the-middle attack, but most " \
      "likely your system doesn't have the CA certificates needed for verification. " \
      "For information about OpenSSL certificates, see " \
      "https://railsapps.github.io/openssl-certificate-verify-failed.html."
    end

    def self.for(uri : URI, ssl_error : Exception? = nil) : CertificateFailureError
      new(message_for(uri), ssl_error)
    end

    def self.display_uri(uri : URI) : String
      return uri.to_s if uri.user.nil? && uri.password.nil?
      host = uri.host || ""
      port = uri.port ? ":#{uri.port}" : ""
      query = uri.query ? "?#{uri.query}" : ""
      "#{uri.scheme}://#{host}#{port}#{uri.path}#{query}"
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end
end
