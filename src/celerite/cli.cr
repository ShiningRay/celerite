require "../celerite"
require "./errors"

module Celerite
  module CLI
    USAGE = <<-TEXT
    Celerite #{VERSION}: Bundler-compatible dependency management in Crystal.

    Status: only help and version are implemented.

    Usage:
      celerite help
      celerite version
      celerite --help
      celerite --version
    TEXT

    def self.run(args : Array(String), stdout : IO, stderr : IO) : Int32
      if args.empty?
        stdout.puts USAGE
        return 0
      end

      command = args.first
      case command
      when "help", "--help", "-h"
        if args.size == 1
          stdout.puts USAGE
          0
        else
          stderr.puts "Unsupported arguments: #{args.join(' ')}"
          1
        end
      when "version", "--version", "-v"
        if args.size == 1
          stdout.puts VERSION
          0
        else
          stderr.puts "Unsupported arguments: #{args.join(' ')}"
          1
        end
      else
        if args.size == 1
          if command.starts_with?('-')
            stderr.puts "Unknown option: #{command}"
          else
            stderr.puts "The '#{command}' command is not implemented yet."
          end
        else
          stderr.puts "Unsupported arguments: #{args.join(' ')}"
        end
        stderr.puts USAGE
        1
      end
    end
  end
end
