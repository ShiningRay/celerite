require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../definition"
require "../resolution"
require "./commands_install"
require "./commands_surface"

module Celerite
  # Read-only (M1) and resolution (M2) command implementations. Every command
  # pins its behavior against the Bundler 4.0.24 oracle; observed outputs and
  # exit codes are recorded in docs/compat-matrix/ and the differential
  # fixtures.
  #
  # Installed-gem materialization remains an M3 (Ruby bridge) concern; inside
  # M1's isolated fixtures no gems are installed, which is exactly the state
  # these implementations reproduce.
  module Commands
    # Global flags accepted before the subcommand (parsed, largely inert in M1).
    GLOBAL_FLAGS = ["--no-color", "--verbose", "-V", "--retry", "-r"]

    def self.dispatch(args : Array(String), stdout : IO, stderr : IO) : Int32
      args = strip_global_flags(args)

      if args.empty?
        stdout.puts CLI::USAGE
        return 0
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
      when "install"
        install(stdout, stderr, rest)
      when "cache", "package", "pack"
        cache(stdout, stderr, rest)
      when "clean"
        clean(stdout, stderr, rest)
      when "exec"
        exec(stdout, stderr, rest)
      when "binstubs"
        binstubs(stdout, stderr, rest)
      when "update"
        update(stdout, stderr, rest)
      when "add"
        add(stdout, stderr, rest)
      when "remove"
        remove(stdout, stderr, rest)
      when "env"
        env(stdout, stderr, rest)
      when "doctor"
        doctor(stdout, stderr, rest)
      when "licenses"
        licenses(stdout, stderr, rest)
      when "fund"
        fund(stdout, stderr, rest)
      when "open"
        open(stdout, stderr, rest)
      when "plugin"
        plugin(stdout, stderr, rest)
      when "pristine"
        pristine(stdout, stderr, rest)
      when "init"
        init(stdout, stderr, rest)
      when "outdated"
        outdated(stdout, stderr, rest)
      when "console"
        console(stdout, stderr, rest)
      when "gem"
        gem(stdout, stderr, rest)
      when "issue"
        issue(stdout, stderr, rest)
      when "config"
        config(stdout, stderr, rest)
      when "help", "--help", "-h"
        help(stdout, rest)
      else
        if known_unimplemented?(command)
          stderr.puts "The '#{command}' command is not implemented yet."
          1
        else
          stderr.puts "Could not find command \"#{command}\"."
          15
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
        "update", "add", "remove", "outdated", "init", "gem", "pristine",
        "doctor", "env", "licenses", "fund", "open", "console",
      }.includes?(command)
    end

    def self.platform_flag_values(rest : Array(String), flag : String) : Array(String)
      values = [] of String
      rest.each_with_index do |arg, index|
        next unless arg == flag
        value = rest[index + 1]?
        values << value if value && !value.starts_with?("--")
      end
      values
    end

    # Thor `word_wrap` (pinned contract: friendly-errors `wrap: true`).
    def self.word_wrap(text : String, width : Int32 = 80) : String
      pattern = Regex.new("(.{1,#{width}})(\\s+|$)")
      text.split("\n").map do |line|
        if line.size > width
          line.gsub(pattern, "\\1\n").strip
        else
          line
        end
      end.join("\n")
    end

    # ------------------------------------------------------------------
    # version
    # ------------------------------------------------------------------
    def self.version(stdout : IO, rest : Array(String)) : Int32
      stdout.puts Celerite::VERSION
      0
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
          # an M3 bridge concern; fixtures use lockfiles without RUBY VERSION.
          output << "Your Gemfile specifies a Ruby version requirement:\n* #{ruby_version}"
        else
          output << "Your Gemfile does not specify a Ruby version requirement."
        end
      end

      stdout.puts output.join("\n\n")
      0
    end

    # ------------------------------------------------------------------
    # check
    # ------------------------------------------------------------------
    def self.check(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      config = definition.config

      if config.frozen? && !definition.lockfile_exists?
        raise ProductionError.new("Frozen mode is set, but there's no lockfile")
      end

      lockfile = definition.lockfile!
      locked_specs = lockfile.specs.sort_by(&.full_name)

      if unresolved_dep(definition, lockfile)
        stderr.puts "Bundler can't satisfy your Gemfile's dependencies."
        stderr.puts "Install missing gems with `bundle install`."
        return 1
      end

      missing = locked_specs # locked path: no installed gems are discoverable yet
      if missing.any?
        stderr.puts "The following gems are missing"
        missing.each do |spec|
          stderr.puts " * #{spec.name} (#{spec.version})"
        end
        stderr.puts "Install missing gems with `bundle install`"
        return 1
      end

      stdout.puts "The Gemfile's dependencies are satisfied"
      0
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
        return 0
      end

      if unresolved = unresolved_dep(definition, lockfile)
        remote = first_remote(lockfile) || "https://rubygems.org/"
        stderr.puts "Could not find gem '#{unresolved}' in rubygems repository #{remote} or installed locally."
        stderr.puts "Install missing gems with `bundle install`."
        return 1
      end

      # Locked path: specs are not installed (M3 materializes them).
      full_names = locked_specs.map(&.full_name).join(", ")
      stderr.puts "Could not find #{full_names} in locally installed gems"
      unless paths
        stderr.puts "Install missing gems with `bundle install`."
      end
      1
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
          return 7
        end
        # No gems in the bundle: header only (parity with an empty bundle).
        return 0
      end

      name = rest.first?
      if name.nil?
        stderr.puts "Could not find command \"#{command}\"."
        return 15
      end

      spec = locked_specs.find(&.name.==(name))
      if spec.nil?
        stderr.puts "Could not find '#{name}' in locally installed gems. Run `bundle install` to install missing gems."
        return 7
      end

      # The gem exists in the lockfile but installation discovery is M3.
      full_names = locked_specs.map(&.full_name).join(", ")
      stderr.puts "Could not find #{full_names} in locally installed gems"
      7
    end

    # ------------------------------------------------------------------
    # lock (M2: native resolution + generation)
    # ------------------------------------------------------------------
    def self.lock(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      add_platforms = platform_flag_values(rest, "--add-platform")
      remove_platforms = platform_flag_values(rest, "--remove-platform")

      print_mode = rest.includes?("--print")
      update = rest.includes?("--update") || rest.includes?("--all")

      definition = Definition.build
      unlock : Bool | Array(String) = update ? true : false

      resolution = Resolution.new(definition, unlock)
      resolution.added_platforms = add_platforms
      resolution.removed_platforms = remove_platforms
      # Progress goes to stdout in write mode, stderr in --print mode
      # (pinned observation from the reference oracle).
      resolution.progress = print_mode ? stderr : stdout

      unless print_mode
        stdout.puts "Writing lockfile to #{File.expand_path(definition.lockfile_path).gsub(/\\/, "/")}"
      end

      data = resolution.generated_lockfile
      text = data.to_lock

      if print_mode
        stdout.print text
      else
        File.write(definition.lockfile_path, text)
      end
      resolution.close
      0
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
          return 1
        end
        definition = Definition.build
        stdout.puts "Settings for `#{name}` in order of priority. The top value will be used"
        definition.config.pretty_values_for(name).each do |line|
          stdout.puts line
        end
        0
      else
        stderr.puts "The 'config' command is not implemented yet."
        1
      end
    end

    # ------------------------------------------------------------------
    # help
    # ------------------------------------------------------------------
    def self.help(stdout : IO, rest : Array(String)) : Int32
      stdout.puts CLI::USAGE
      0
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
  end
end
