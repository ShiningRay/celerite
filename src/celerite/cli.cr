require "../celerite"
require "./errors"
require "./gem/platform"
require "./lockfile/parser"
require "./definition"
require "./cli/commands"

module Celerite
  module CLI
    # Reference-compatible exit codes (observed from the pinned oracles and
    # recorded in docs/compat-matrix/cli-commands.md).
    module ExitCode
      SUCCESS           =  0
      GENERIC           =  1
      GEM_NOT_FOUND     =  7
      GEMFILE_NOT_FOUND = 10
      UNKNOWN_COMMAND   = 15
      CHECKSUM_MISMATCH = 37
    end

    USAGE = <<-TEXT
    Usage:
      celerite COMMAND [OPTIONS]

    Celerite is a Bundler-compatible dependency manager written in Crystal.

    Implemented (M1, locked path):
      check, list, show, info, platform, version, lock --print, config get

    Run `celerite help COMMAND` for command help.
    TEXT

    # Bundler-compatible friendly error rendering: message on stderr, mapping
    # Celerite errors to the reference exit codes.
    def self.run(args : Array(String), stdout : IO, stderr : IO) : Int32
      Commands.dispatch(args, stdout, stderr)
    rescue ex : GemfileNotFound
      stderr.puts ex.message
      ExitCode::GEMFILE_NOT_FOUND
    rescue ex : LockfileError
      stderr.puts ex.message
      ExitCode::GENERIC
    rescue ex : VersionError | BadRequirementError
      stderr.puts ex.message
      ExitCode::GENERIC
    rescue ex : UnsupportedCommandError
      stderr.puts ex.message
      ExitCode::GENERIC
    rescue ex : UsageError
      stderr.puts ex.message
      ExitCode::UNKNOWN_COMMAND
    end
  end
end
