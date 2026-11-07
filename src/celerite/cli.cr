require "../celerite"
require "./errors"
require "./gem/platform"
require "./lockfile/parser"
require "./definition"
require "./cli/commands"

module Celerite
  module CLI
    # Friendly-errors semantics (pinned contract: `Bundler.with_friendly_errors`):
    # BundlerError subclasses exit with their status_code; Thor::Error with 15;
    # wrap-worthy messages are word-wrapped at the terminal width (80 for
    # non-TTY, THOR_COLUMNS override).
    module ExitCode
      SUCCESS = 0
    end

    DEFAULT_TERMINAL_WIDTH = 80

    USAGE = <<-TEXT
    Usage:
      celerite COMMAND [OPTIONS]

    Celerite is a Bundler-compatible dependency manager written in Crystal.

    Implemented:
      locked path (M1): check, list, show, info, platform, version, config get
      resolution (M2): lock [--print] [--update]

    Run `celerite help COMMAND` for command help.
    TEXT

    def self.run(args : Array(String), stdout : IO, stderr : IO) : Int32
      Commands.dispatch(args, stdout, stderr)
    rescue ex : Error
      friendly_error(ex, stderr)
      ex.status_code
    rescue ex : Exception
      # Unhandled internals: report without pretending compatibility.
      stderr.puts "celerite internal error: #{ex.message}"
      1
    end

    private def self.friendly_error(ex : Error, stderr : IO) : Nil
      message = ex.message || ex.class.name
      if ex.wrap?
        stderr.puts Commands.word_wrap(message, terminal_width)
      else
        stderr.puts message
      end
    end

    def self.terminal_width : Int32
      if columns = ENV["THOR_COLUMNS"]?
        value = columns.to_i
        return value >= 10 ? value : DEFAULT_TERMINAL_WIDTH
      end
      DEFAULT_TERMINAL_WIDTH
    end
  end
end
