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
end
