module Celerite
  # Base error for all Celerite failures surfaced to the CLI.
  class Error < Exception
  end

  # Raised for user-facing CLI usage mistakes (unknown command, bad flags).
  class UsageError < Error
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

  # Raised for lockfile parse/validation failures (mirrors Bundler::LockfileError).
  class LockfileError < Error
  end

  # Raised when a Gemfile cannot be located (mirrors Bundler::GemfileNotFound).
  class GemfileNotFound < Error
  end
end
