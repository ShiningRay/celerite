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

    # A bare `bundle` runs the default command (`cli.rb:133-148`), so there is
    # no Celerite-specific usage screen left to print.

    def self.run(args : Array(String), stdout : IO, stderr : IO) : Int32
      previous_sink = Definition.default_warning_sink
      Definition.default_warning_sink = stderr
      begin
        Commands.dispatch(args, stdout, stderr)
      ensure
        Definition.default_warning_sink = previous_sink
      end
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
