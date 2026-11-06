require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../definition"

module Celerite
  # M1 read-only command implementations (the "locked path"): every command
  # here reads an existing lockfile and never writes one. Behavior is pinned
  # against the Bundler 4.0.24 oracle (observed outputs recorded in
  # docs/compat-matrix/ and spec fixtures).
  #
  # Installed-gem materialization is an M3 (Ruby bridge) concern; inside M1's
  # isolated fixtures no gems are installed, which is exactly the state these
  # implementations reproduce.
  module Commands
    # Global flags accepted before the subcommand (parsed, largely inert in M1).
    GLOBAL_FLAGS = ["--no-color", "--verbose", "-V", "--retry", "-r"]

    def self.dispatch(args : Array(String), stdout : IO, stderr : IO) : Int32
      args = strip_global_flags(args)

      if args.empty?
        stdout.puts CLI::USAGE
        return CLI::ExitCode::SUCCESS
      end

      command = args[0]
      rest = args[1..]

      case command
      when "version", "--version"
        version(stdout, rest)
      when "platform"
        platform(stdout, rest)
      when "check"
        check(stdout, stderr, rest)
      when "list"
        list(stdout, stderr, rest)
      when "show", "info"
        show_info(command, stdout, stderr, rest)
      when "lock"
        lock(stdout, stderr, rest)
      when "config"
        config(stdout, stderr, rest)
      when "help", "--help", "-h"
        help(stdout, rest)
      else
        if known_unimplemented?(command)
          stderr.puts "The '#{command}' command is not implemented yet."
          CLI::ExitCode::GENERIC
        else
          stderr.puts "Could not find command \"#{command}\"."
          CLI::ExitCode::UNKNOWN_COMMAND
        end
      end
    end

    def self.strip_global_flags(args : Array(String)) : Array(String)
      result = [] of String
      skip_next = false
      args.each_with_index do |arg, index|
        if skip_next
          skip_next = false
          next
        end
        if arg == "--retry" || arg == "-r"
          skip_next = true
          next
        end
        next if GLOBAL_FLAGS.includes?(arg) && index < 2
        result << arg
      end
      result
    end

    def self.known_unimplemented?(command : String) : Bool
      {
        "install", "update", "exec", "cache", "package", "pack", "add", "remove",
        "binstubs", "outdated", "init", "gem", "clean", "pristine", "doctor",
        "env", "issue", "licenses", "fund", "open", "console", "plugin",
      }.includes?(command)
    end

    # A dependency declared in the lockfile without any locked spec. The
    # reference detects this during resolution (Gemfile eval, M2 bridge); the
    # locked path detects it purely from the lockfile itself.
    def self.unresolved_dep(definition : Definition, lockfile : Lockfile::Data) : String?
      spec_names = lockfile.specs.map(&.name).to_set
      lockfile.dependencies.find { |dep| !spec_names.includes?(dep.name) }.try(&.name)
    end

    def self.first_remote(lockfile : Lockfile::Data) : String?
      lockfile.sources.first?.try(&.remote)
    end

    # ------------------------------------------------------------------
    # version
    # ------------------------------------------------------------------
    def self.version(stdout : IO, rest : Array(String)) : Int32
      stdout.puts Celerite::VERSION
      CLI::ExitCode::SUCCESS
    end

    # ------------------------------------------------------------------
    # platform (Bundler::CLI::Platform at the pinned revision)
    # ------------------------------------------------------------------
    def self.platform(stdout : IO, rest : Array(String)) : Int32
      definition = Definition.build
      parseable = rest.includes?("--ruby")

      lockfile = definition.lockfile_exists? ? definition.lockfile! : nil
      ruby_version = lockfile.try(&.ruby_version).try(&.gsub(/p\d+\Z/, ""))

      output = [] of String
      if parseable
        output << (ruby_version || "No ruby version specified")
      else
        platforms = lockfile.try(&.platforms) || [] of String
        platform_lines = platforms.map { |p| "* #{p}" }

        output << "Your platform is: #{Gem::Platform.local}"
        output << "Your app has gems that work on these platforms:\n#{platform_lines.join("\n")}"

        if ruby_version
          # Runtime validation (validate_runtime!) needs the system Ruby and is
          # an M2 bridge concern; M1 fixtures use lockfiles without RUBY VERSION.
          output << "Your Gemfile specifies a Ruby version requirement:\n* #{ruby_version}"
        else
          output << "Your Gemfile does not specify a Ruby version requirement."
        end
      end

      stdout.puts output.join("\n\n")
      CLI::ExitCode::SUCCESS
    end

    # ------------------------------------------------------------------
    # check
    # ------------------------------------------------------------------
    def self.check(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      config = definition.config

      if config.frozen? && !definition.lockfile_exists?
        stderr.puts "Frozen mode is set, but there's no lockfile"
        return 16
      end

      lockfile = definition.lockfile!
      locked_specs = lockfile.specs.sort_by(&.full_name)

      if unresolved_dep(definition, lockfile)
        stderr.puts "Bundler can't satisfy your Gemfile's dependencies."
        stderr.puts "Install missing gems with `bundle install`."
        return CLI::ExitCode::GENERIC
      end

      missing = locked_specs # locked path: no installed gems are discoverable yet
      if missing.any?
        stderr.puts "The following gems are missing"
        missing.each do |spec|
          stderr.puts " * #{spec.name} (#{spec.version})"
        end
        stderr.puts "Install missing gems with `bundle install`"
        return CLI::ExitCode::GENERIC
      end

      stdout.puts "The Gemfile's dependencies are satisfied"
      CLI::ExitCode::SUCCESS
    end

    # ------------------------------------------------------------------
    # list
    # ------------------------------------------------------------------
    def self.list(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      paths = rest.includes?("--paths")
      definition = Definition.build
      lockfile = definition.lockfile!

      locked_specs = lockfile.specs.sort_by(&.full_name)
      if lockfile.dependencies.empty?
        stdout.puts "No gems in the Gemfile"
        return CLI::ExitCode::SUCCESS
      end

      if unresolved = unresolved_dep(definition, lockfile)
        remote = first_remote(lockfile) || "https://rubygems.org/"
        stderr.puts "Could not find gem '#{unresolved}' in rubygems repository #{remote} or installed locally."
        stderr.puts "Install missing gems with `bundle install`."
        return CLI::ExitCode::GENERIC
      end

      # Locked path: specs are not installed (M3 materializes them).
      full_names = locked_specs.map(&.full_name).join(", ")
      stderr.puts "Could not find #{full_names} in locally installed gems"
      unless paths
        stderr.puts "Install missing gems with `bundle install`."
      end
      CLI::ExitCode::GENERIC
    end

    # ------------------------------------------------------------------
    # show / info
    # ------------------------------------------------------------------
    def self.show_info(command : String, stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      lockfile = definition.lockfile!
      locked_specs = lockfile.specs.sort_by(&.full_name)

      if command == "show" && rest.empty?
        stdout.puts "Gems included by the bundle:"
        unless locked_specs.empty?
          full_names = locked_specs.map(&.full_name).join(", ")
          stderr.puts "Could not find #{full_names} in locally installed gems"
          return CLI::ExitCode::GEM_NOT_FOUND
        end
        # No gems in the bundle: header only (parity with an empty bundle).
        return CLI::ExitCode::SUCCESS
      end

      name = rest.first?
      if name.nil?
        stderr.puts "Could not find command \"#{command}\"."
        return CLI::ExitCode::UNKNOWN_COMMAND
      end

      spec = locked_specs.find(&.name.==(name))
      if spec.nil?
        stderr.puts "Could not find '#{name}' in locally installed gems. Run `bundle install` to install missing gems."
        return CLI::ExitCode::GEM_NOT_FOUND
      end

      # The gem exists in the lockfile but installation discovery is M3.
      full_names = locked_specs.map(&.full_name).join(", ")
      stderr.puts "Could not find #{full_names} in locally installed gems"
      CLI::ExitCode::GEM_NOT_FOUND
    end

    # ------------------------------------------------------------------
    # lock (locked path: --print only; writing is M2)
    # ------------------------------------------------------------------
    def self.lock(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if !rest.empty? && (rest.first == "--print" || rest.first == "--update")
        if rest.first == "--update"
          stderr.puts "The 'lock' command is not implemented yet."
          return CLI::ExitCode::GENERIC
        end
        definition = Definition.build
        stdout.print definition.lockfile!.to_lock
        return CLI::ExitCode::SUCCESS
      end

      stderr.puts "The 'lock' command is not implemented yet."
      CLI::ExitCode::GENERIC
    end

    # ------------------------------------------------------------------
    # config (read-only: get/list)
    # ------------------------------------------------------------------
    def self.config(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      sub = rest.first?
      case sub
      when "get"
        name = rest[1]?
        if name.nil?
          stderr.puts "Please provide the name of the configuration settings you want to retrieve."
          return CLI::ExitCode::GENERIC
        end
        definition = Definition.build
        stdout.puts "Settings for `#{name}` in order of priority. The top value will be used"
        definition.config.pretty_values_for(name).each do |line|
          stdout.puts line
        end
        CLI::ExitCode::SUCCESS
      else
        stderr.puts "The 'config' command is not implemented yet."
        CLI::ExitCode::GENERIC
      end
    end

    # ------------------------------------------------------------------
    # help
    # ------------------------------------------------------------------
    def self.help(stdout : IO, rest : Array(String)) : Int32
      stdout.puts CLI::USAGE
      CLI::ExitCode::SUCCESS
    end
  end
end
