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
end
