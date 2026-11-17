require "json"
require "../../celerite"
require "../errors"
require "../suggestions"
require "../gem/platform"
require "../lockfile/parser"
require "../lockfile/writer"
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
      # `strip_global_flags` removes the global switches before dispatch, so the
      # `--verbose` echo (reference `CLI#print_command`) must be reconstructed
      # from the raw invocation.
      verbose_requested = args.includes?("--verbose")
      cli_retry = extract_retry_switch(args)
      # Thor parses the class option `--retry` before dispatch, so a
      # non-numeric value fails before any command output.
      if message = numeric_switch_error(args, ["--retry", "-r"])
        stderr.puts message
        return 15
      end
      args = strip_global_flags(args)

      if args.empty?
        stdout.puts CLI::USAGE
        return 0
      end

      command = args[0]
      rest = args[1..]
      print_command_echo(command, rest, verbose_requested, cli_retry, stdout)

      # Thor prints the command's manpage for `--help` before the body runs.
      # The manpage text itself stays a declared divergence: we print the shared
      # usage banner instead, but the exit status matches the reference.
      if command != "exec" && (rest.includes?("--help") || rest.includes?("-h"))
        return help(stdout, [command])
      end

      case command
      when "version", "--version", "-v"
        version(command, stdout, stderr, rest)
      when "platform"
        platform(stdout, stderr, rest)
      when "check"
        check(stdout, stderr, rest)
      when "list"
        list(stdout, stderr, rest)
      when "show", "info"
        show_info(command, stdout, stderr, rest, verbose_requested)
      when "lock"
        # Purist: bundler version `--bundler <ver>` expects a lockfile and
        # forces a re-resolve regardless of flags (implementation path).
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
        if (plugin_exit = dispatch_plugin_command(command, rest))
          return plugin_exit
        end
        if command.starts_with?("bundler-") && !find_executable(command, ENV["PATH"]? || "").nil?
          # Reference PATH fallback: hand the invocation to `bundler-<name>`
          # found on PATH (or report the bare command when missing).
          run_fallback_command(command, rest, stdout, stderr)
        elsif known_unimplemented?(command)
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
          if value = args[index + 1]?
            ENV["CELERITE_CLI_RETRY"] = value unless value.starts_with?("--")
          end
          skip_next = true
          next
        end
        if arg.starts_with?("--retry=")
          ENV["CELERITE_CLI_RETRY"] = arg.split("=", 2)[1]? || ""
          next
        end
        if arg == "--verbose"
          ENV["CELERITE_VERBOSE"] = "1"
          next
        end
        next if GLOBAL_FLAGS.includes?(arg) && index < 2
        result << arg
      end
      result
    end

    # Commands whose `--verbose` echo is suppressed (reference
    # `Bundler::CLI::PARSEABLE_COMMANDS`).
    PARSEABLE_COMMANDS = ["check", "config", "help", "exec", "platform", "show", "version"]

    # Commands this CLI implements that the reference echoes before running.
    # `info` is a Thor command of its own (bundler/cli.rb:382) and is not part of
    # `PARSEABLE_COMMANDS`, so `bundle info --verbose` echoes while
    # `bundle show --verbose` does not.
    ECHO_COMMANDS = [
      "install", "update", "lock", "cache", "package", "pack", "clean",
      "add", "remove", "binstubs", "env", "doctor", "licenses", "fund",
      "open", "plugin", "pristine", "init", "outdated", "console", "gem", "issue",
      "info",
    ]

    # Boolean options: Thor renders them as a bare `--name`.
    ECHO_FLAG_SWITCHES = [
      "-h", "--help", "--verbose", "-V", "--no-color", "--quiet", "--dry-run",
      "--local", "--prefer-local", "--full-index", "--standalone", "--no-cache",
      "--no-lock", "--force", "--redownload", "--all", "--patch", "--minor",
      "--major", "--pre", "--strict", "--conservative", "--system", "--clean",
      "--ruby", "--bundler", "--print", "--normalize-platforms",
      "--add-checksums", "--name-only", "--paths", "--no-install",
      "--all-platforms", "--skip-install", "--optimistic", "--parseable",
      "--only-explicit", "--frozen", "--deployment", "--no-deployment",
      "--no-prune", "--shebang", "--binstubs", "--ext", "--no-git", "--no-ci",
      "--no-mit", "--no-exe", "--no-coc", "--no-changelog", "--edit",
    ]

    # Numeric options print unquoted (`--retry 5`); strings are inspected.
    ECHO_NUMERIC_SWITCHES = ["-r", "--retry", "-j", "--jobs"]

    # Array options render as `--name ["a", "b"]`, or `--name true` when bare.
    ECHO_ARRAY_SWITCHES = ["--update", "--add-platform", "--remove-platform"]

    def self.extract_retry_switch(args : Array(String)) : String?
      args.each_with_index do |arg, index|
        if arg == "--retry" || arg == "-r"
          value = args[index + 1]?
          return value if value && !value.starts_with?("--")
        elsif arg.starts_with?("--retry=")
          return arg.split("=", 2)[1]?
        end
      end
      nil
    end

    # Reference `CLI#print_command` (bundler/cli.rb:777-791): with `--verbose`
    # the invocation is echoed with Thor-rendered switches (booleans bare,
    # strings inspected, array options bracketed, sorted by option name).
    def self.print_command_echo(command : String, rest : Array(String), verbose : Bool, retry_value : String?, stdout : IO) : Nil
      return unless verbose
      return if PARSEABLE_COMMANDS.includes?(command)
      return unless ECHO_COMMANDS.includes?(command)

      positionals = [] of String
      switches = [] of Tuple(String, String)
      index = 0
      while index < rest.size
        token = rest[index]
        unless token.starts_with?("-") && token.size > 1
          positionals << token
          index += 1
          next
        end

        name = token
        inline_value : String? = nil
        if (equal_index = token.index('=')) && equal_index > 0
          name = token[0, equal_index]
          inline_value = token[(equal_index + 1)..]
        end

        if inline_value.nil? && ECHO_FLAG_SWITCHES.includes?(name)
          switches << {echo_sort_key(name), name}
          index += 1
          next
        end

        if ECHO_ARRAY_SWITCHES.includes?(name)
          values = [] of String
          if value = inline_value
            values << value
          else
            while (candidate = rest[index + 1]?) && !candidate.starts_with?("-")
              values << candidate
              index += 1
            end
          end
          rendered = values.empty? ? "#{name} true" : "#{name} [#{values.map(&.inspect).join(", ")}]"
          switches << {echo_sort_key(name), rendered}
          index += 1
          next
        end

        value = inline_value || rest[index + 1]?
        if value.nil? || value.starts_with?("-")
          switches << {echo_sort_key(name), name}
        else
          index += 1 if inline_value.nil?
          rendered = ECHO_NUMERIC_SWITCHES.includes?(name) ? "#{name} #{value}" : "#{name} #{value.inspect}"
          switches << {echo_sort_key(name), rendered}
        end
        index += 1
      end

      if value = retry_value
        switches << {"retry", "--retry #{value}"}
      end
      switches << {"verbose", "--verbose"}

      parts = ["bundle", command]
      positionals.each { |positional| parts << positional }
      switches.sort_by! { |entry| entry[0] }
      switches.each { |entry| parts << entry[1] }
      profile = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
      stdout.puts "Running `#{parts.join(" ")}` with bundler #{profile}"
    end

    private def self.echo_sort_key(name : String) : String
      name.lchop("--").lchop("-")
    end

    # Effective retry count for network operations: CLI --retry overrides config.
    def self.retry_count(config : Config? = nil) : Int32
      if cli = ENV["CELERITE_CLI_RETRY"]?
        if value = cli.to_i?
          return value if value >= 0
        end
      end
      cfg = config || (begin
        Config.new
      rescue
        nil
      end)
      if cfg
        value = cfg["retry"]
        case value
        when Int32
          return value if value >= 0
        when String
          if parsed = value.to_i?
            return parsed if parsed >= 0
          end
        end
      end
      3
    end

    def self.known_unimplemented?(command : String) : Bool
      {
        "update", "add", "remove", "outdated", "init", "gem", "pristine",
        "doctor", "env", "licenses", "fund", "open", "console",
      }.includes?(command)
    end

    # PATH fallback plumbing (pinned `Bundler::CLI` behavior): `bundler-<name>`
    # found on PATH is executed directly.
    def self.run_fallback_command(command : String, rest : Array(String), stdout : IO, stderr : IO) : Int32
      resolved = find_executable(command, ENV["PATH"]? || "")
      if resolved.nil?
        stderr.puts "Could not find command \"#{command}\"."
        return 15
      end
      if resolved.downcase.ends_with?(".bat") || resolved.downcase.ends_with?(".cmd")
        Process.run("cmd", ["/c", resolved] + rest, output: :inherit, error: :inherit, input: :inherit).exit_code
      else
        Process.run(resolved, rest, output: :inherit, error: :inherit, input: :inherit).exit_code
      end
    end

    # Validates the `--cooldown` flag (pinned `CLI::Common.validate_cooldown!`
    # + Thor numeric option). On failure the reference exits 15 with the
    # pinned message.
    def self.cooldown_flag_valid?(rest : Array(String), stderr : IO, bundler_version : String? = nil) : Bool
      value = flag_value_ornext(rest, "--cooldown")
      return true if value.nil?
      if bundler_version && bundler_version.starts_with?("2.")
        stderr.puts "Unknown switches \"--cooldown\""
        return false
      end
      days = value.to_i?
      if days.nil?
        stderr.puts "Expected numeric value for '--cooldown'; got #{value.inspect}"
        return false
      end
      if days < 0
        stderr.puts "Expected `--cooldown` to be a non-negative integer, got #{days}"
        return false
      end
      true
    end

    def self.cooldown_flag_value(rest : Array(String)) : Int32?
      flag_value_ornext(rest, "--cooldown").try(&.to_i?)
    end

    # `--frozen` is rejected on 4.0.24 (pinned unknown-switches error) and
    # deprecated on 2.7.x (deprecation notice + frozen lockfile check).
    # `install --frozen` uses the removed-flag message on 4.0.24, while
    # lock/update use Thor unknown switch messages. Returns exit code or nil.
    def self.frozen_flag_exit(rest : Array(String), stderr : IO, lockfile_exists : Bool, bundler_version : String? = nil, command_name : String? = nil) : Int32?
      if !rest.includes?("--frozen")
        return nil
      end
      # `install --frozen`: removed-flag message (4.0.24) or the deprecated
      # + lockfile-required diagnostic (2.7.x).
      if command_name == "install"
        if bundler_version && bundler_version.starts_with?("2.")
          stderr.puts "[DEPRECATED] The `--frozen` flag is deprecated because it relies on being remembered across bundler invocations, which bundler will no longer do in future versions. Instead please use `bundle config set frozen true`, and stop using this flag"
          if !lockfile_exists
            stderr.puts "The --frozen flag requires a lockfile. Please make sure you have checked your"
            stderr.puts "Gemfile.lock into version control before deploying."
            return 16
          end
          nil
        else
          stderr.puts "The `--frozen` flag has been removed because it relied on being remembered"
          stderr.puts "across bundler invocations, which bundler no longer does. Instead please use"
          stderr.puts "`bundle config set frozen true`, and stop using this flag"
          15
        end
      else
        # lock/update --frozen: unknown switch (update adds a suggestion).
        stderr.puts "Unknown switches \"--frozen\""
        stderr.puts "Did you mean?  \"--force\"" if command_name == "update"
        15
      end
    end

    # Shared summary emitter (pinned `Common.output_cooldown_skipped_summary`).
    def self.print_cooldown_summary(resolution : Resolution, stream : IO) : Nil
      skipped = resolution.cooldown_skipped_summary
      return if skipped.empty?
      stream.puts "The following gem versions were skipped by the cooldown setting:"
      skipped.each do |(name, version, resolved, days_left)|
        stream.puts "  * #{name} #{version} (available in #{days_left} #{days_left == 1 ? "day" : "days"}), resolved #{resolved} instead"
      end
    end

    # Reference Bundler validates switches in Thor before any Gemfile or
    # lockfile work starts. Unknown tokens are reported verbatim (a `=value`
    # suffix stays part of the token), each quoted, comma + space separated.
    private def self.unknown_switch_tokens(rest : Array(String), allowed_flags : Array(String),
                                           allowed_values : Array(String)) : Array(String)
      unknown = [] of String
      index = 0
      while index < rest.size
        arg = rest[index]
        if arg.starts_with?("-") && arg != "-" && arg != "--"
          name = arg.split("=", 2)[0]
          if allowed_values.includes?(name)
            index += 1 unless arg.includes?("=")
          elsif attached_short_value?(arg)
            # Thor accepts attached values for short options (`-j2`, `-gfoo`,
            # `-PLowSecurity`); the whole token is the option plus its value.
          elsif !allowed_flags.includes?(name) && !negated_flag?(name, allowed_flags)
            unknown << arg
          end
        end
        index += 1
      end
      unknown
    end

    private def self.attached_short_value?(arg : String) : Bool
      # Thor only accepts attached values for `-j` (`aliases: "-j"`); `-g`
      # (array alias) and `-P` (singular alias) reject `-gfoo`/`-PLow...`.
      arg.starts_with?("-j") && arg.size > 2 && arg[2..].each_char.all?(&.ascii_number?)
    end

    # Thor generates a `--no-<name>` counterpart for every boolean switch, so
    # `bundle gem demo --no-git` and `--no-mit` are valid even though only the
    # positive spelling is declared. Value options have no negation.
    private def self.negated_flag?(name : String, allowed_flags : Array(String)) : Bool
      return false unless name.starts_with?("--no-") && name.size > 5
      allowed_flags.includes?("--" + name[5..])
    end

    # Thor rejects unexpected positional arguments for commands declared
    # without an argument list (`Thor::UnknownArgumentError`, exit 15). The
    # usage line mirrors the reference banners: commands declared with
    # `[OPTIONS]` keep the suffix, others do not (`cli.rb` desc strings).
    NO_ARG_USAGE = {
      "check"    => "[OPTIONS]",
      "console"  => "[GROUP]",
      "clean"    => "[OPTIONS]",
      "install"  => "[OPTIONS]",
      "cache"    => "[OPTIONS]",
      "platform" => "[OPTIONS]",
      "fund"     => "[OPTIONS]",
      "list"     => "[OPTIONS]",
      "lock"     => "",
      "env"      => "",
      "licenses" => "",
      "issue"    => "",
    }

    # Thor `:array` options consume every following non-switch token, so those
    # values must not be reported as stray positional arguments.
    POSITIONAL_ARRAY_FLAGS = {
      "list"    => ["--only-group", "--without-group"],
      "install" => ["--with", "--without", "--standalone"],
      "lock"    => ["--update", "--add-platform", "--remove-platform"],
    }

    # Thor rejects extra positional arguments before the command runs; `console`
    # takes one optional GROUP (`bundle console [GROUP]`), everything else none.
    private def self.reject_positional_arguments(stderr : IO, command : String, rest : Array(String),
                                                 allowed_flags : Array(String),
                                                 allowed_values : Array(String),
                                                 max_positionals : Int32 = 0) : Int32?
      suffix = NO_ARG_USAGE[command]?
      return nil if suffix.nil?
      value_flags = allowed_values + POSITIONAL_VALUE_FLAGS.fetch(command, [] of String)
      array_flags = POSITIONAL_ARRAY_FLAGS.fetch(command, [] of String)
      arguments = subcommand_arguments(rest, allowed_flags, value_flags, array_flags)
      return nil if arguments.size <= max_positionals
      stderr.puts "ERROR: \"bundle #{command}\" was called with arguments #{arguments.inspect}"
      usage = suffix.empty? ? "bundle #{command}" : "bundle #{command} #{suffix}"
      stderr.puts "Usage: \"#{usage}\""
      15
    end

    # Thor parses `:numeric` options before running the command and rejects
    # non-numeric values with `Expected numeric value for '--jobs'; got "x"`
    # (`Thor::Option#parse`, exit 15).
    private def self.numeric_switch_error(rest : Array(String), flags : Array(String)) : String?
      rest.each_with_index do |token, index|
        flags.each do |flag|
          value : String? = nil
          switch = flag
          if token == flag
            value = rest[index + 1]?
          elsif flag.starts_with?("--") && token.starts_with?(flag + "=")
            value = token.split("=", 2)[1]
          end
          next if value.nil?
          next if value.empty?
          next if value.matches?(/\A[-+]?\d+\z/)
          canonical = flag == "-j" ? "--jobs" : (flag == "-r" ? "--retry" : flag)
          return "Expected numeric value for '#{canonical}'; got #{value.inspect}"
        end
      end
      nil
    end

    private def self.reject_unknown_switches(stderr : IO, rest : Array(String), allowed_flags : Array(String),
                                             allowed_values : Array(String),
                                             dictionary : Array(String)? = nil) : Int32?
      unknown = unknown_switch_tokens(rest, allowed_flags, allowed_values)
      return nil if unknown.empty?
      stderr.puts "Unknown switches " + unknown.map { |token| "\"#{token}\"" }.join(", ")
      if hinted = Suggestions.message(unknown.first, dictionary || (allowed_flags + allowed_values))
        stderr.puts hinted
      end
      15
    end

    # Thor's class options are accepted by every subcommand.
    SWITCH_FLAGS_CLASS  = ["--help", "-h", "--no-color", "--quiet", "--verbose", "-V"]
    SWITCH_VALUES_CLASS = ["--retry", "-r"]

    # Option surfaces of commands that used to accept anything, transcribed
    # from `Bundler::CLI.commands[name].options` (Thor declarations in
    # `bundler-4.0.24/lib/bundler/cli.rb`).
    BARE_SWITCH_FLAGS    = SWITCH_FLAGS_CLASS
    BARE_SWITCH_VALUES   = SWITCH_VALUES_CLASS
    INIT_SWITCH_FLAGS    = BARE_SWITCH_FLAGS
    INIT_SWITCH_VALUES   = BARE_SWITCH_VALUES + ["--gemfile", "--gemspec"]
    FUND_SWITCH_FLAGS    = BARE_SWITCH_FLAGS
    FUND_SWITCH_VALUES   = BARE_SWITCH_VALUES + ["--group", "-g"]
    OPEN_SWITCH_FLAGS    = BARE_SWITCH_FLAGS
    OPEN_SWITCH_VALUES   = BARE_SWITCH_VALUES + ["--path"]
    REMOVE_SWITCH_FLAGS  = BARE_SWITCH_FLAGS + ["--install"]
    REMOVE_SWITCH_VALUES = BARE_SWITCH_VALUES

    # Options that take a value but live in the matching `*_SWITCH_FLAGS` array
    # (the command code reads those flags directly). Positional-argument
    # detection must not mistake their values for arguments.
    POSITIONAL_VALUE_FLAGS = {
      "install" => ["--binstubs", "--path", "--shebang", "--standalone", "--target-rbconfig", "--trust-policy", "--with", "--without"],
      "cache"   => ["--path"],
      "lock"    => ["--update"],
    }

    OUTDATED_SWITCH_FLAGS = BARE_SWITCH_FLAGS + [
      "--filter-major", "--filter-minor", "--filter-patch", "--filter-strict",
      "--groups", "--local", "--major", "--minor", "--only-explicit",
      "--parseable", "--porcelain", "--patch", "--pre", "--strict", "--update-strict",
    ]
    OUTDATED_SWITCH_VALUES = BARE_SWITCH_VALUES + ["--cooldown", "--group", "--source"]
    GEM_SWITCH_FLAGS       = BARE_SWITCH_FLAGS + [
      "--bundle", "--changelog", "--coc", "--exe", "--bin", "-b", "--git", "--mit", "--rubocop",
    ]
    GEM_SWITCH_VALUES = BARE_SWITCH_VALUES + [
      "--ci", "--edit", "-e", "--ext", "--github-username", "--linter", "--test",
    ]
    DOCTOR_SUBCOMMAND_FLAGS  = BARE_SWITCH_FLAGS + ["--ssl"]
    DOCTOR_SUBCOMMAND_VALUES = BARE_SWITCH_VALUES + ["--gemfile", "--tls-version", "--verify-mode"]

    # `doctor`/`plugin` route through Thor subcommands, which report unknown
    # options as leftover arguments instead of `Unknown switches` (measured on
    # 4.0.24: `bundle doctor diagnose --bogus`).
    private def self.subcommand_arguments(rest : Array(String), allowed_flags : Array(String),
                                          allowed_values : Array(String),
                                          array_flags : Array(String) = [] of String) : Array(String)
      arguments = [] of String
      index = 0
      while index < rest.size
        arg = rest[index]
        name = arg.split("=", 2)[0]
        if array_flags.includes?(name) && !arg.includes?("=")
          # Thor `:array` options also swallow space separated values
          # (`--only-group development test`).
          index += 1
          while index < rest.size && !rest[index].starts_with?("-")
            index += 1
          end
          next
        end
        if allowed_values.includes?(name)
          # `--flag=value` carries its value in the same token; only the separated
          # form consumes the next token. Advancing nothing here would spin forever.
          index += arg.includes?("=") ? 1 : 2
          next
        end
        if allowed_flags.includes?(name) || attached_short_value?(arg)
          index += 1
          next
        end
        arguments << arg
        index += 1
      end
      arguments
    end

    # 4.x rejects these flags (`print_remembered_flag_deprecation`); 2.7.x only
    # warns (`[DEPRECATED] The ... flag is deprecated ... in future versions`)
    # and keeps going, which is why the same helper serves both profiles.
    record RemovedFlag, flag : String, option_name : String, value : String, special_message : String? = nil

    def self.removed_flag(rest : Array(String), command : String) : RemovedFlag?
      flags = rest.map { |arg| arg.split("=", 2)[0] }
      case command
      when "install"
        # Order pinned to `bundler/cli.rb:290-300`: clean, deployment, frozen
        # (handled before this call), no-prune, path, shebang, without, with,
        # then --system, --no-deployment and --binstubs.
        {"--clean" => "clean", "--deployment" => "deployment", "--no-prune" => "no_prune", "--system" => "path.system"}.each do |flag, option|
          return RemovedFlag.new(flag, option, "true") if flags.includes?(flag)
        end
        if flags.includes?("--path")
          value = flag_value_ornext(rest, "--path") || "path"
          return RemovedFlag.new("--path", "path", "'#{value}'")
        end
        if flags.includes?("--shebang")
          value = flag_value_ornext(rest, "--shebang") || "shebang"
          return RemovedFlag.new("--shebang", "shebang", "'#{value}'")
        end
        if flags.includes?("--without")
          values = flag_values(rest, "--without")
          value = values.empty? ? "without" : values.join(" ")
          return RemovedFlag.new("--without", "without", "'#{value}'")
        end
        if flags.includes?("--with")
          values = flag_values(rest, "--with")
          value = values.empty? ? "with" : values.join(" ")
          return RemovedFlag.new("--with", "with", "'#{value}'")
        end
        if flags.includes?("--no-deployment")
          return RemovedFlag.new("--no-deployment", "deployment", "false")
        end
        if flags.includes?("--binstubs")
          return RemovedFlag.new("--binstubs", "binstubs", "true",
            "The --binstubs option has been removed in favor of `bundle binstubs --all`")
        end
      when "cache"
        return RemovedFlag.new("--all", "cache_all", "true") if flags.includes?("--all")
        return RemovedFlag.new("--no-all", "cache_all", "false") if flags.includes?("--no-all")
        return RemovedFlag.new("--no-prune", "no_prune", "true") if flags.includes?("--no-prune")
        return RemovedFlag.new("--frozen", "frozen", "true") if flags.includes?("--frozen")
      end
      nil
    end

    def self.removed_flag_message(flag : RemovedFlag) : String
      return flag.special_message.not_nil! if flag.special_message
      "The `#{flag.flag}` flag has been removed because it relied on being remembered across bundler invocations, which bundler no longer does. Instead please use `bundle config set #{flag.option_name} #{flag.value}`, and stop using this flag"
    end

    def self.removed_flag_deprecation(flag : RemovedFlag) : String
      "[DEPRECATED] The `#{flag.flag}` flag is deprecated because it relies on being remembered across bundler invocations, which bundler will no longer do in future versions. Instead please use `bundle config set #{flag.option_name} #{flag.value}`, and stop using this flag"
    end

    # Install-family switch surface, measured against the 4.0.24 (and 2.7.2)
    # oracles. Global Thor flags are accepted everywhere; `--path`, `--without`
    # and `--with` are accepted because this port implements their semantics
    # even though 4.x removed them (declared deviation, see compat-report).
    SWITCH_FLAGS_COMMON  = ["-h", "--help", "--verbose", "--no-color", "--quiet"]
    SWITCH_VALUES_COMMON = ["--retry", "--jobs", "-j", "--gemfile"]

    INSTALL_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--local", "--prefer-local", "--full-index", "--standalone", "--no-cache", "--no-lock", "--force", "--redownload", "--path", "--without", "--with"]
    INSTALL_SWITCH_VALUES = SWITCH_VALUES_COMMON + ["--target-rbconfig", "--cooldown", "--trust-policy", "-P", "--lockfile"]

    # `update` and `lock` switch surface, taken from the declared Thor options
    # (`Bundler::CLI.commands[name].options`, identical in 2.7.2 and 4.0.24
    # except `--cooldown`). Anything else must be rejected as an unknown switch
    # instead of being accepted and ignored.
    UPDATE_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--all", "--local", "--full-index", "--force", "--patch", "--minor", "--major", "--pre", "--strict", "--conservative", "--ruby"]
    UPDATE_SWITCH_VALUES = SWITCH_VALUES_COMMON + ["--group", "-g", "--source", "--bundler", "--cooldown"]

    LOCK_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--local", "--full-index", "--print", "--normalize-platforms", "--add-checksums", "--patch", "--minor", "--major", "--pre", "--strict", "--conservative", "--update"]
    LOCK_SWITCH_VALUES = SWITCH_VALUES_COMMON + ["--add-platform", "--remove-platform", "--bundler", "--cooldown", "--lockfile"]

    # `cache` declares only all/all-platforms/cache-path/cooldown/frozen/gemfile/
    # no-install/no-prune/path/quiet (`bundler/cli.rb:466-497`). `--force`,
    # `--redownload`, `--no-cache`, `--local`, `--without` and `--with` are
    # install switches: Thor rejects them here instead of ignoring them.
    CACHE_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--no-install", "--all-platforms", "--path"]
    CACHE_SWITCH_VALUES = ["--retry", "-r", "--gemfile", "--cache-path", "--cooldown"]

    # Thor's `Unknown switches` suggestion dictionary is `switches`, i.e. every
    # declared option name -- including the removed ones (they are still
    # `method_option`s) and excluding aliases such as `--redownload`
    # (`method_option "force", aliases: "--redownload"`). Typo suggestions are
    # therefore wider than the accepted switch surface, and `install --frozenn`
    # must suggest `--frozen` even though `--frozen` itself is rejected.
    INSTALL_REMOVED_FLAGS      = ["--clean", "--deployment", "--frozen", "--no-prune", "--system", "--binstubs", "--shebang", "--no-deployment"]
    CACHE_REMOVED_FLAGS        = ["--all", "--no-all", "--no-prune", "--frozen"]
    INSTALL_SUGGEST_DICTIONARY = (INSTALL_SWITCH_FLAGS + INSTALL_SWITCH_VALUES + INSTALL_REMOVED_FLAGS).reject { |flag| flag == "--redownload" }
    CACHE_SUGGEST_DICTIONARY   = (CACHE_SWITCH_FLAGS + CACHE_SWITCH_VALUES + CACHE_REMOVED_FLAGS).reject { |flag| flag == "--redownload" }

    # Reference 2.7.x reads the existing lockfile in text mode on Windows, so
    # its `match?("\r\n")` never fires and a CRLF lockfile is rewritten as LF;
    # 4.x preserves the style. Mirror that per profile.
    def self.preserve_lockfile_crlf? : Bool
      !(ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
    end

    # `--gemfile`/`--lockfile` are command-level in the reference: the flag is
    # not just parsed, the definition really uses that Gemfile and lockfile
    # (`Definition.find_gemfile`/`resolve_lockfile` already prefer the ENV
    # vars). Scope the override to the command body and restore on every exit
    # path, including exceptions.
    private def self.with_gemfile_overrides(rest : Array(String), &)
      gemfile = flag_value_ornext(rest, "--gemfile")
      lockfile = flag_value_ornext(rest, "--lockfile")
      # The reference validates the switch after Thor but before the definition
      # is built, so a missing file raises `GemfileNotFound` (exit 10) with the
      # expanded path and `not found` on its own line.
      if gemfile
        expanded = File.expand_path(gemfile)
        raise GemfileNotFound.new("#{expanded.gsub('\\', "/")}\nnot found") unless File.file?(expanded)
      end
      previous_gemfile = ENV["BUNDLE_GEMFILE"]?
      previous_lockfile = ENV["BUNDLE_LOCKFILE"]?
      ENV["BUNDLE_GEMFILE"] = gemfile if gemfile
      ENV["BUNDLE_LOCKFILE"] = lockfile if lockfile
      begin
        yield
      ensure
        if gemfile
          if previous_gemfile
            ENV["BUNDLE_GEMFILE"] = previous_gemfile
          else
            ENV.delete("BUNDLE_GEMFILE")
          end
        end
        if lockfile
          if previous_lockfile
            ENV["BUNDLE_LOCKFILE"] = previous_lockfile
          else
            ENV.delete("BUNDLE_LOCKFILE")
          end
        end
      end
    end

    private def self.flag_value_ornext(rest : Array(String), flag : String) : String?
      rest.each_with_index do |arg, index|
        if arg == flag
          nxt = rest[index + 1]?
          return nxt unless nxt.nil? || nxt.empty?
        end
        if arg.starts_with?(flag + "=")
          return arg.split("=", 2)[1]
        end
      end
      nil
    end

    # Group filters accept Thor-style space-separated lists (reference
    # `bundle list --without-group=GROUP[ GROUP...]`) as well as repeated
    # flags and comma/colon separated values.
    def self.flag_values(rest : Array(String), flag : String) : Array(String)
      values = [] of String
      index = 0
      while index < rest.size
        arg = rest[index]
        if arg == flag
          cursor = index + 1
          while cursor < rest.size && !rest[cursor].starts_with?("-")
            value = rest[cursor]
            break if value.empty?
            values << value
            cursor += 1
          end
          index = cursor
          next
        elsif arg.starts_with?(flag + "=")
          values.concat(arg.split("=", 2)[1].split(/[\s,:]+/).reject(&.empty?))
        end
        index += 1
      end
      values.uniq
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

    # RubyGems platform normalization used by `--add-platform`/`--remove-platform`
    # (`Gem::Platform.new(value)`, cli/lock.rb L49-58). Unknown names normalize to
    # "unknown", which the reference rejects for adds.
    def self.normalized_platform(value : String) : String
      Celerite::Gem::Platform.new(value).to_s
    rescue
      "unknown"
    end

    # Platform list a definition starts from before add/remove edits
    # (`@platforms = @locked_platforms.dup`, definition.rb L108; a fresh lock
    # seeds the local platform via `add_current_platform`).
    def self.platforms_before_changes(definition : Definition) : Array(String)
      if definition.lockfile_exists?
        definition.lockfile!.platforms.map { |entry| normalized_platform(entry) }
      else
        [normalized_platform(Celerite::Gem::Platform.local.to_s)]
      end
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
    def self.version(command : String, stdout : IO, stderr : IO, rest : Array(String)) : Int32
      unless rest.empty?
        # Thor's `UnknownArgumentError` rendering (error.rb:65-89): the command
        # rejects positional arguments, and the reference exits 15.
        stderr.puts %(ERROR: "bundle version" was called with arguments #{rest.inspect})
        stderr.puts %(Usage: "bundle version")
        return 15
      end

      profile = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
      # Bundler 2.x prefixes the human-readable command with "Bundler version";
      # 4.x prints the bare version (cli.rb#version).
      text = profile.starts_with?("2.") ? "Bundler version #{profile}" : profile
      # Only `bundle version` appends build metadata; `-v`/`--version` print the
      # version alone (cli.rb#version vs. `Bundler.verbose_version`).
      if command == "version"
        if meta = Celerite::ReleaseMetadata.for(profile)
          text += " (#{meta[0]} commit #{meta[1]})"
        end
      end
      stdout.puts text
      0
    end

    # ------------------------------------------------------------------
    # platform (Bundler::CLI::Platform at the pinned revision)
    # ------------------------------------------------------------------
    # Reconstructs the structured Gemfile `ruby` declaration (version,
    # patchlevel, engine, engine_version).  `GemfileEvaluation#ruby` stays the
    # human-readable string for lockfile comparisons, but it drops the option
    # fields, so runtime validation must use the structured fields.
    def self.requested_ruby_version(evaluation : Bridge::GemfileEvaluation) : Celerite::RubyVersion?
      version = evaluation.ruby_version
      return nil unless version
      Celerite::RubyVersion.new(version, evaluation.ruby_patchlevel, evaluation.ruby_engine, evaluation.ruby_engine_version)
    end

    def self.platform(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # `platform` takes no arguments in the reference, so Thor rejects both
      # unknown switches and positional tokens before the definition is built.
      platform_flags = BARE_SWITCH_FLAGS + ["--ruby"]
      if code = reject_unknown_switches(stderr, rest, platform_flags, BARE_SWITCH_VALUES)
        return code
      end
      if code = reject_positional_arguments(stderr, "platform", rest, platform_flags, BARE_SWITCH_VALUES)
        return code
      end
      definition = Definition.build
      parseable = rest.includes?("--ruby")

      lockfile = definition.lockfile_exists? ? definition.lockfile! : nil
      ruby_version = lockfile.try(&.ruby_version).try(&.gsub(/p\d+\Z/, ""))
      # Reference `platform.rb:11-15`: without a lockfile the value comes from
      # `Bundler.definition.ruby_version#single_version_string` (the Gemfile
      # declaration), so a project that was never locked still reports it.
      if ruby_version.nil?
        begin
          bridge = Bridge::Client.new
          begin
            evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
            if requested = requested_ruby_version(evaluation)
              ruby_version = requested.single_version_string
            end
          ensure
            bridge.close
          end
        rescue
          nil
        end
      end

      output = [] of String
      if parseable
        output << (ruby_version || "No ruby version specified")
      else
        platforms = lockfile.try(&.platforms).dup || [] of String
        # `Definition#add_current_platform` appends the local platform unless
        # the bundle is frozen (definition.rb:150), so a frozen lockfile that
        # omits it lists only its own platforms.
        local_platform = Gem::Platform.local.to_s
        unless definition.config.frozen?
          platforms << local_platform unless platforms.includes?(local_platform)
        end
        platform_lines = platforms.map { |p| "* #{p}" }

        output << "Your platform is: #{Gem::Platform.local}"
        output << "Your app has gems that work on these platforms:\n#{platform_lines.join("\n")}"

        mismatch_message = nil
        ruby_validation_attempted = false
        ruby_validation_skipped = false
        if ruby_version
          output << "Your Gemfile specifies a Ruby version requirement:\n* #{ruby_version}"
          # Reference `platform.rb:35-40`: a mismatch is printed but does not
          # fail the command.
          begin
            validate_runtime!(definition)
            output << "Your current platform satisfies the Ruby version requirement."
          rescue ex : RubyVersionMismatch
            output << (ex.message || "")
          end
        else
          output << "Your Gemfile does not specify a Ruby version requirement."
        end
      end

      stdout.puts output.join("\n\n")
      0
    end

    # Validates Gemfile ruby requirement against the running Ruby when
    # evaluation is available (Bundler validate_runtime!/validate_ruby!).
    # The reference *is* Ruby, so it always validates. Celerite needs a Ruby
    # bridge to learn the running interpreter: when no bridge can be located or
    # started, the check is skipped (degraded build), and a genuine version
    # mismatch always propagates as RubyVersionMismatch.
    def self.validate_ruby_runtime!(definition : Definition, bridge : Bridge::Client? = nil) : Nil
      client = bridge
      unless client
        begin
          client = Bridge::Client.new
        rescue
          return
        end
      end
      begin
        evaluation = client.evaluate_gemfile(definition.gemfile_path)
        requested = requested_ruby_version(evaluation)
        return unless requested
        env = client.ruby_environment
        RubyRuntime.validate_version!(requested, env)
      ensure
        client.close if bridge.nil?
      end
    rescue ex : RubyVersionMismatch
      raise ex
    rescue
      # Best-effort: if evaluation/env is unavailable, do not block commands
      # that historically worked without runtime validation.
      nil
    end

    # Port of `Bundler::Definition#validate_runtime!` (definition.rb:494-497):
    # the Ruby version and the platform list are validated together, as
    # `bundler/cli/{binstubs,fund,info,install,outdated,platform,pristine,show,update}.rb`
    # do at the start of the command.
    def self.validate_runtime!(definition : Definition, bridge : Bridge::Client? = nil) : Nil
      client = bridge
      unless client
        begin
          client = Bridge::Client.new
        rescue
          return
        end
      end
      begin
        validate_ruby_runtime!(definition, client)
        definition.validate_platforms!(client.ruby_environment.platform)
      ensure
        client.close if bridge.nil?
      end
    rescue ex : RubyVersionMismatch
      raise ex
    rescue ex : ProductionError
      raise ex
    rescue
      nil
    end

    # Reference parity: Bundler re-resolves/unlocks when the Gemfile ruby
    # declaration differs from the lockfile RUBY VERSION (e.g. explicit
    # patchlevel dropped by lock serialization) or when the Gemfile declares
    # ruby but the lockfile has no RUBY VERSION section
    # (definition.rb `@unlocking_ruby` / `(!@locked_ruby_version ^ !@ruby_version)`).
    # Celerite keeps using the lockfile, so only the notification is mirrored.
    # Returns :diff, :missing_from_lock, or :none.
    private def self.lock_ruby_unlock_kind(definition : Definition, lockfile : Lockfile::Data) : Symbol
      return :none unless bridge_available?
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        requested = requested_ruby_version(evaluation)
        return :none if requested.nil?
        lock_ruby = lockfile.ruby_version
        if lock_ruby.nil? || lock_ruby.empty?
          return :missing_from_lock
        end
        locked = Celerite::RubyVersion.from_string(lock_ruby)
        return :none if locked.nil?
        requested.diff(locked).nil? ? :none : :diff
      rescue
        :none
      ensure
        bridge.close
      end
    end

    # `BUNDLE_FROZEN` supplied through the environment suppresses the
    # "remove the freeze" hint; deployment mode and config-file frozen keep it.
    # definition.rb:475-492 clears `suggested_command` when the frozen setting
    # lives only in the :env location and appends the hint only when it exists.
    private def self.frozen_from_environment? : Bool
      value = ENV["BUNDLE_FROZEN"]?
      return false if value.nil? || value.empty?
      value.downcase != "false"
    end

    # ------------------------------------------------------------------
    # check
    # ------------------------------------------------------------------
    def self.check(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if code = reject_unknown_switches(stderr, rest, ["--dry-run"], ["--gemfile"])
        return code
      end
      if code = reject_positional_arguments(stderr, "check", rest, ["--dry-run"], ["--gemfile"])
        return code
      end
      # `--gemfile FILE` is command-level in the reference: check really builds
      # its definition from that file (`with_gemfile_overrides` also rejects a
      # missing path with GemfileNotFound, exit 10).
      with_gemfile_overrides(rest) do
        run_check(stdout, stderr, rest)
      end
    end

    # `Bundler.definition.specs` materializes the definition from the Gemfile and
    # resolves on demand, so the commands built on `Bundler.definition` /
    # `Bundler.load` work before the first install (`bundle binstubs`,
    # `bundle clean`, `bundle fund`).  The lockfile is deliberately not written
    # here: only `check` and `install` persist it (cli/check.rb:33
    # `definition.lock(true)`); the rest read the freshly resolved specs.
    #
    # `local_only` mirrors the state of Bundler's sources for these commands:
    # only `check` (`definition.check!` → `resolve_remotely!`) and `install`
    # (`setup_domain!` → `sources.remote!`) ever enable remote lookups.  Every
    # other command resolves against `sources.local_only!`, so a missing gem is
    # reported as "in locally installed gems" and no index is fetched.
    private def self.materialize_lockfile(definition : Definition, progress : IO? = nil, local_only : Bool = false) : Lockfile::Data
      return definition.lockfile! if definition.lockfile_exists?
      resolution = Resolution.new(definition, false)
      begin
        resolution.progress = progress if progress
        resolution.local_only = local_only
        resolution.resolve!
        resolution.generated_lockfile
      ensure
        resolution.close
      end
    end

    # Reference `cli/common.rb:113-123 gem_not_found_message`: the plain name
    # plus a DidYouMean suggestion over the names that were available.  Exact
    # (lower-cased) alternatives are suggested verbatim; otherwise the spell
    # checker proposes up to three names joined the way `word_list` does.
    private def self.gem_not_found_message_for(name : String, alternatives : Array(String)) : String
      message = "Could not find gem '#{name}'."
      lowered = name.downcase
      if alternatives.includes?(lowered)
        message += "\nDid you mean '#{lowered}'?"
      else
        suggestions = Suggestions.for(name, alternatives)
        unless suggestions.empty?
          quoted = suggestions.map { |suggestion| "'#{suggestion}'" }
          list = if quoted.size == 1
                   quoted[0]
                 else
                   "#{quoted[0...-1].join(", ")} or #{quoted.last}"
                 end
          message += "\nDid you mean #{list}?"
        end
      end
      message
    end

    private def self.run_check(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      config = definition.config

      if config.frozen? && !definition.lockfile_exists?
        raise ProductionError.new("Frozen mode is set, but there's no lockfile")
      end
      # `bundler/cli/check.rb:15` runs `ensure_equivalent_gemfile_and_lockfile`
      # before resolving, so the CHECKSUMS reason wins over the resolve output.
      # The Gemfile diff needs the evaluated dependencies; a bridge that is
      # unavailable only narrows the reason list, never the outcome.
      gemfile_dependencies : Array(Bridge::EvaluatedDependency)? = nil
      gemfile_sources : Array(Bridge::EvaluatedSource)? = nil
      if config.frozen? && definition.lockfile_exists?
        begin
          evaluation = Bridge::Client.new.evaluate_gemfile(definition.gemfile_path)
          gemfile_dependencies = evaluation.dependencies
          gemfile_sources = evaluation.sources
        rescue
        end
      end
      definition.validate_frozen_lockfile!(gemfile_dependencies: gemfile_dependencies,
        gemfile_sources: gemfile_sources)
      # `bundler/cli/check.rb:16` runs `validate_runtime!` only after the
      # frozen lockfile check, so the lockfile summary wins over a platform
      # mismatch.
      validate_runtime!(definition)

      # Reference `Bundler.definition.check!` resolves the Gemfile when no
      # lockfile exists yet, so `bundle check` works before the first install:
      # the resolver announces the source-index fetch and the resolve, and the
      # lockfile is written only once every gem turns out to be installed
      # (bundler/cli/check.rb:18-34 `definition.check!` + `definition.lock(true)`).
      resolved_from_gemfile = !definition.lockfile_exists?
      generated_text : String? = nil
      lockfile = if resolved_from_gemfile
                   resolution = Resolution.new(definition, false)
                   begin
                     resolution.progress = stdout
                     resolution.resolve!
                     data = resolution.generated_lockfile
                     generated_text = data.to_lock
                     data
                   ensure
                     resolution.close
                   end
                 else
                   definition.lockfile!
                 end
      all_groups = bridge_available? ? lockfile_groups(definition, lockfile) : ["default"]

      # `check` has no group switches in the reference; BUNDLE_WITH/WITHOUT
      # still filter through requested_groups_for.
      requested_groups = requested_groups_for(config, all_groups, [] of String, [] of String)
      locked_specs = bridge_available? ? filter_locked_specs_by_groups(definition, lockfile, lockfile.specs.sort_by(&.full_name), requested_groups) : lockfile.specs.sort_by(&.full_name)

      # Reference parity: Gemfile ruby declaration differs from lock RUBY VERSION
      # or is absent from the lock; check prints the re-resolve notice in both
      # satisfied and missing-dependency cases.
      ruby_unlock_kind = lock_ruby_unlock_kind(definition, lockfile)
      # Reference parity (definition.rb:421-425, 475-492): the re-resolve
      # notice is profile-independent and suppressed only by frozen mode.
      # Frozen refuses the unlock on the 4.x line only (2.7.2 has no such
      # guard), and the "remove the freeze" hint is dropped when frozen comes
      # from the environment (BUNDLE_FROZEN=true) rather than deployment/config.
      if ruby_unlock_kind != :none && !config.frozen?
        stdout.puts "Resolving dependencies..."
      end
      if ruby_unlock_kind != :none && config.frozen? && profile_bundler_version.starts_with?("4.")
        message = "Bundler is unlocking ruby, but the lockfile can't be updated because frozen mode is set"
        unless frozen_from_environment?
          message += "\n\nIf this is a development machine, remove the #{File.basename(definition.lockfile_path)} freeze by running `bundle config set frozen false`."
        end
        raise ProductionError.new(message)
      end

      if unresolved_dep(definition, lockfile)
        stderr.puts "Bundler can't satisfy your Gemfile's dependencies."
        stderr.puts "Install missing gems with `bundle install`."
        return 1
      end

      # Reference parity: a lockfile that does not cover the local platform
      # makes the definition re-resolve (current_platform_missing), and the
      # resolver announces that (platform-missing fixtures; the reference
      # fails the unresolved-dep probe before its resolver starts).
      if platform_missing?(definition)
        stdout.puts "Resolving dependencies..."
      end

      missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }
      if missing.any?
        stderr.puts "The following gems are missing"
        missing.each do |spec|
          stderr.puts " * #{spec.name} (#{spec.version})"
        end
        stderr.puts "Install missing gems with `bundle install`"
        return 1
      end

      # A definition resolved straight from the Gemfile has no lockfile yet;
      # the reference persists one as part of a satisfied `check` unless
      # `--dry-run` was given (`definition.lock(true) unless options[:"dry-run"]`).
      if resolved_from_gemfile && !rest.includes?("--dry-run")
        if text = generated_text
          existing = File.file?(definition.lockfile_path) ? File.read(definition.lockfile_path) : nil
          if existing.nil? || semantic_content(existing) != semantic_content(text)
            Lockfile.write(definition.lockfile_path, text, preserve_crlf: preserve_lockfile_crlf?)
          end
        end
      end

      stdout.puts "The Gemfile's dependencies are satisfied"
      0
    end

    # ------------------------------------------------------------------
    # list
    # ------------------------------------------------------------------
    # Group metadata is evaluated by the Ruby bridge itself (`Bridge::Client`
    # degrades safely when Bundler is unavailable); gating on the test harness
    # env vars (`CELERITE_BRIDGE_SERVER`/`CELERITE_REFERENCE_BUNDLER_LIB`) made
    # `list --only-group` reject real groups in plain user environments.
    private def self.available_groups(definition : Definition, lockfile : Lockfile::Data) : Array(String)
      groups = begin
        lockfile_groups(definition, lockfile)
      rescue
        # A missing/broken bridge must not turn `list` into an error: fall back
        # to the default group exactly like the old gated behavior did.
        [] of String
      end
      groups.empty? ? ["default"] : groups
    end

    def self.list(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # `--format` only exists from 4.x: 2.7.2 rejects it as an unknown switch
      # (`Unknown switches "--format=json"`, exit 15) — same for our profile.
      format_values = ["--only-group", "--without-group"]
      format_values << "--format" unless profile_bundler_version.starts_with?("2.")
      if code = reject_unknown_switches(stderr, rest, ["--name-only", "--paths"], format_values)
        return code
      end
      if code = reject_positional_arguments(stderr, "list", rest, ["--name-only", "--paths"], format_values)
        return code
      end
      # Reference `cli/list.rb:17`: the two output selectors are exclusive and
      # the check happens before any spec loading.
      if rest.includes?("--name-only") && rest.includes?("--paths")
        stderr.puts "The `--name-only` and `--paths` options cannot be used together"
        return 15
      end
      paths = rest.includes?("--paths")
      name_only = rest.includes?("--name-only")
      # `--format=json` and `--format json` are equivalent; validation happens
      # after the missing-gem exit (oracle: missing gems win over a bad format).
      format = flag_value_ornext(rest, "--format")
      only_groups = flag_values(rest, "--only-group")
      without_groups = flag_values(rest, "--without-group")
      definition = Definition.build
      # Reference Bundler 4.0.24: `bundle list` does not run validate_runtime!
      # on Ruby mismatch in installed-bundle scenarios; keep listing behavior.
      config = definition.config
      lockfile = definition.lockfile!

      # Validate mutually exclusive group filters like the reference.
      if only_groups.any? && without_groups.any?
        stderr.puts "The `--only-group` and `--without-group` options cannot be used together"
        return 15
      end

      all_groups = available_groups(definition, lockfile)
      (only_groups + without_groups).uniq.each do |group|
        unless all_groups.includes?(group)
          stderr.puts "`#{group}` group could not be found."
          return 15
        end
      end

      requested_groups = requested_groups_for(config, all_groups, only_groups, without_groups)

      locked_specs = lockfile.specs.sort_by(&.full_name)

      # Reference parity: Gemfile ruby declaration differs from lock RUBY
      # VERSION (e.g. explicit patchlevel dropped by lock serialization) or is
      # absent from the lock. list prints the notice for declaration diffs even
      # when satisfied, but list prints the notice for a missing lock RUBY VERSION
      # even when dependencies are satisfied.
      ruby_unlock_kind = lock_ruby_unlock_kind(definition, lockfile)
      # Frozen mode refuses the unlock for check/show/info; `list` keeps listing
      # but stays silent about the re-resolve (oracle: exit 0, no notice).
      if !config.frozen? && ruby_unlock_kind != :none
        stdout.puts "Resolving dependencies..."
      end

      # Empty-bundle handling lives in the output branches: the JSON form
      # prints `{"gems":[]}` (reference `cli/list.rb`), the human form prints
      # `No gems in the Gemfile`.
      if unresolved = unresolved_dep(definition, lockfile)
        remote = first_remote(lockfile) || "https://rubygems.org/"
        stderr.puts "Could not find gem '#{unresolved}' in rubygems repository #{remote} or installed locally."
        stderr.puts "Install missing gems with `bundle install`."
        return 1
      end

      # Filter locked specs by requested groups.
      filtered_specs = begin
        filter_locked_specs_by_groups(definition, lockfile, locked_specs, requested_groups)
      rescue
        locked_specs
      end

      installed_missing = filtered_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }

      locked_specs = filtered_specs
      missing = installed_missing
      if missing.empty?
        # Reference validation order: mutual exclusions, spec loading (missing
        # gems exit 1 above), then `--format`. An empty bundle still validates
        # the format (oracle: empty + --format=bogus => exit 15).
        if format && format != "json"
          stderr.puts "Unknown option`--format=#{format}`. Supported formats: `json`"
          return 15
        end
        if format == "json"
          gems = locked_specs.map do |spec|
            item = {} of String => JSON::Any
            item["name"] = JSON::Any.new(spec.name)
            unless name_only
              item["version"] = JSON::Any.new(spec.version.to_s)
              if git_version = spec_git_version(spec, lockfile)
                item["git_version"] = JSON::Any.new(git_version)
              else
                item["git_version"] = JSON::Any.new(nil)
              end
              if paths
                if path = installed_gem_dir(definition, spec, lockfile)
                  item["path"] = JSON::Any.new(display_path(path))
                end
              end
            end
            item
          end
          stdout.puts({"gems" => gems}.to_json)
          return 0
        end
        if locked_specs.empty?
          stdout.puts "No gems in the Gemfile"
          return 0
        end
        if paths
          locked_specs.each do |spec|
            path = installed_gem_dir(definition, spec, lockfile)
            stdout.puts(path ? display_path(path) : spec.full_name)
          end
        elsif name_only
          locked_specs.each { |spec| stdout.puts spec.name }
        else
          # Reference 4.0.24 prints this header for every human-readable listing,
          # including when no group filter was given.
          stdout.puts "Gems included by the bundle:"
          locked_specs.each { |spec| stdout.puts "  * #{spec_display_name(spec, lockfile)}" }
          stdout.puts "Use `bundle info` to print more detailed information about a gem"
        end
        return 0
      end
      full_names = missing.map(&.full_name).join(", ")
      stderr.puts "Could not find #{full_names} in locally installed gems"
      unless paths
        stderr.puts "Install missing gems with `bundle install`."
      end
      1
    end

    # ------------------------------------------------------------------
    # show / info
    # ------------------------------------------------------------------
    def self.show_info(command : String, stdout : IO, stderr : IO, rest : Array(String),
                       verbose : Bool = false) : Int32
      # `show` and `info` expose different switches in the reference: show
      # takes --paths only, info takes --path/--version. Unknown switches are
      # rejected before the definition is built, like Thor.
      allowed_flags = command == "info" ? ["--path", "--version"] : ["--paths", "--outdated"]
      if code = reject_unknown_switches(stderr, rest, allowed_flags, [] of String)
        return code
      end
      # `cli.rb` L354-357: `show --outdated` is a removed flag with its own
      # message (InvalidOption, exit 15, wrapped to the terminal width). 2.7.x
      # only deprecates it: it warns and runs the outdated check instead.
      if command == "show" && rest.includes?("--outdated")
        if profile_bundler_version.starts_with?("2.")
          stderr.puts "[DEPRECATED] the `--outdated` flag to `bundle show` will be removed in favor of `bundle show --verbose`"
          rest = rest.reject { |arg| arg == "--outdated" }
          outdated_deprecated = true
        else
          stderr.puts word_wrap("the `--outdated` flag to `bundle show` has been removed in favor of `bundle show --verbose`", CLI.terminal_width)
          return 15
        end
      end
      # `cli/show.rb:11-12,41-48`: `--verbose` (and 2.7.x's deprecated
      # `--outdated`) fetches the unlocked remote resolution while the command
      # object is constructed, so the header and index lines come first.
      # `--verbose` is a class option: `dispatch` strips it from `rest` before
      # the command runs, so the flag arrives through the `verbose` argument.
      verbose_listing = command == "show" && (verbose || outdated_deprecated)

      names = rest.reject { |a| a.starts_with?("-") }
      if command == "info" && names.empty?
        stderr.puts "ERROR: \"bundle info\" was called with no arguments"
        stderr.puts "Usage: \"bundle info GEM [OPTIONS]\""
        return 15
      end

      definition = Definition.build
      # Reference order: `Show.new` fetches the latest remote specs before
      # `run` validates the runtime, so the fetch output precedes any error.
      latest_versions = {} of String => Gem::Version
      if verbose_listing
        stdout.puts "Fetching remote specs for outdated check..."
        stdout.puts ""
        remote = Resolution.new(definition, true)
        begin
          remote.progress = stdout
          remote.resolve!.each { |resolved| latest_versions[resolved.name] = resolved.version }
        ensure
          remote.close
        end
      end
      validate_runtime!(definition)
      # Reference `Bundler.load` resolves the Gemfile when no lockfile exists yet,
      # so `show`/`info` work before the first `bundle install`; asking for the
      # lockfile here raised LockfileError (exit 20) instead of resolving.
      resolved_from_gemfile = !definition.lockfile_exists?
      # Gemfile dependencies are only reachable through the resolution object; the
      # missing-gem message spells the requirement out (`'json_pure (= 2.8.1)'`),
      # so remember the display form before the bridge goes away.
      dependency_displays = {} of String => String
      lockfile = if resolved_from_gemfile
                   resolution = Resolution.new(definition, false)
                   begin
                     resolution.resolve!
                     resolution.evaluation.dependencies.each do |dep|
                       # `Gem::Dependency#to_s` omits the requirement when it is
                       # the default `>= 0` (`Gem::Requirement#none?`), which is how
                       # the reference renders `'my_plugin'` vs `'json_pure (= 2.8.1)'`.
                       none = dep.requirements.empty? || dep.requirements == [">= 0"]
                       dependency_displays[dep.name] = none ? dep.name : "#{dep.name} (#{dep.requirements.join(", ")})"
                     end
                     resolution.generated_lockfile
                   ensure
                     resolution.close
                   end
                 else
                   definition.lockfile!
                 end
      # Measured against 4.0.24: `show`/`show --paths`/`show GEM`/`info GEM` do
      # NOT run the frozen ruby-unlock production check (they exit 0 and print
      # the listing/paths); only `check` raises ProductionError here.
      # `show`/`info` still honor BUNDLE_WITH/WITHOUT from config (the CLI
      # group switches were removed above, the config filter was not).
      all_groups = available_groups(definition, lockfile)
      requested_groups = requested_groups_for(definition.config, all_groups, [] of String, [] of String)
      sorted_specs = lockfile.specs.sort_by(&.full_name)
      locked_specs = begin
        filter_locked_specs_by_groups(definition, lockfile, sorted_specs, requested_groups)
      rescue
        sorted_specs
      end
      paths = rest.includes?("--paths")
      # Reference `Bundler.load` materializes every locked gem (honoring the
      # group filter) before `select_spec` runs, so a missing installed gem is
      # reported before the requested gem is resolved. `bundle show` prints the
      # listing header for the human-readable form only; `--paths` stays bare
      # (see `bundle show --paths` in cli.rb / printer.rb).
      missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }
      if missing.any?
        if resolved_from_gemfile
          # Resolved from the Gemfile but not installed anywhere: the reference
          # reports the dependency (name plus its requirement, e.g.
          # `json_pure (= 2.8.1)`) and prints no listing header, because
          # materializing the definition is what fails.
          display = dependency_displays[missing.first.name]? || missing.first.name
          stderr.puts "Could not find gem '#{display}' in locally installed gems."
        else
          stdout.puts "Gems included by the bundle:" if command == "show" && names.empty? && !paths
          full_names = missing.map(&.full_name).join(", ")
          stderr.puts "Could not find #{full_names} in locally installed gems"
        end
        return 7
      end
      if command == "show" && names.empty?
        if paths
          if dir = bundler_gem_dir
            stdout.puts display_path(dir)
          end
          locked_specs.each do |spec|
            path = installed_gem_dir(definition, spec, lockfile)
            stdout.puts(path ? display_path(path) : spec.full_name)
          end
        else
          # Reference `bundle show` lists the running Bundler itself first
          # (`Bundler.definition.specs` includes the bundler spec), which is the
          # compatibility profile version here rather than the locked one.
          stdout.puts "Gems included by the bundle:"
          if verbose_listing
            # `cli/show.rb:60-74`: the verbose form drops the two-space indent
            # (`desc.lstrip`) and adds Summary/Homepage/Status rows.
            bundler_dir = bundler_gem_dir
            bsummary : String? = nil
            bhomepage : String? = nil
            if bundler_dir
              bundler_info = read_gemspec_info(bundler_dir, "bundler-#{profile_bundler_version}")
              bsummary = bundler_info[0]
              bhomepage = bundler_info[1]
            end
            print_show_verbose_entry(stdout, "* bundler (#{profile_bundler_version})",
              bsummary || "The best way to manage your application's dependencies",
              bhomepage || "https://bundler.io",
              Gem::Version.new(profile_bundler_version), latest_versions["bundler"]?)
            locked_specs.each do |spec|
              gem_dir = installed_gem_dir(definition, spec, lockfile)
              summary : String? = nil
              homepage : String? = nil
              if gem_dir
                spec_info = read_gemspec_info(gem_dir, spec.full_name)
                summary = spec_info[0]
                homepage = spec_info[1]
              end
              print_show_verbose_entry(stdout, "* #{spec_display_name(spec, lockfile)}",
                summary, homepage, Gem::Version.new(spec.version), latest_versions[spec.name]?)
            end
          else
            # Reference `bundle show` lists the running Bundler itself first
            # (`Bundler.definition.specs` includes the bundler spec), which is the
            # compatibility profile version here rather than the locked one.
            stdout.puts "  * bundler (#{profile_bundler_version})"
            locked_specs.each { |spec| stdout.puts "  * #{spec_display_name(spec, lockfile)}" }
          end
        end
        return 0
      end

      name = names.first

      spec = locked_specs.find(&.name.==(name))
      if spec.nil?
        # Reference `Bundler::CLI::Common.select_spec`: when the gem is a
        # dependency whose every group was filtered out it raises `GemNotFound`
        # (exit 7) naming those groups instead of the generic missing message.
        full_spec = lockfile.specs.find(&.name.==(name))
        if full_spec
          groups = gem_groups_for(definition, name)
          ignored = groups - requested_groups
          unless groups.empty? || ignored.size != groups.size
            message = "Could not find gem '#{name}', because it's in the #{verbalize_groups(groups)}, configured to be ignored."
            stderr.puts word_wrap(message, CLI.terminal_width)
            return 7
          end
        end
        stderr.puts "Could not find '#{name}' in locally installed gems. Run `bundle install` to install missing gems."
        return 7
      end

      if command == "show" && rest.includes?("--paths")
        if gem_dir = installed_gem_dir(definition, spec, lockfile)
          stdout.puts display_path(gem_dir)
          return 0
        end
      elsif command == "info" && rest.includes?("--path")
        if gem_dir = installed_gem_dir(definition, spec, lockfile)
          stdout.puts display_path(gem_dir)
          return 0
        end
      elsif command == "info" && rest.includes?("--version")
        stdout.puts spec.version.to_s
        return 0
      else
        if gem_dir = installed_gem_dir(definition, spec, lockfile)
          # Reference `bundle show <gem>` prints only the installed gem path;
          # detailed metadata belongs to `bundle info`.
          if command == "show"
            stdout.puts display_path(gem_dir)
            return 0
          end

          summary, homepage, metadata = read_gemspec_info(gem_dir, spec.full_name)
          stdout.puts "  * #{spec_display_name(spec, lockfile)}"
          stdout.puts "\tSummary: #{summary}" if summary
          stdout.puts "\tHomepage: #{homepage}" if homepage
          stdout.puts "\tDocumentation: #{metadata["documentation_uri"]}" if metadata.has_key?("documentation_uri")
          stdout.puts "\tSource Code: #{metadata["source_code_uri"]}" if metadata.has_key?("source_code_uri")
          stdout.puts "\tFunding: #{metadata["funding_uri"]}" if metadata.has_key?("funding_uri")
          stdout.puts "\tWiki: #{metadata["wiki_uri"]}" if metadata.has_key?("wiki_uri")
          stdout.puts "\tChangelog: #{metadata["changelog_uri"]}" if metadata.has_key?("changelog_uri")
          stdout.puts "\tBug Tracker: #{metadata["bug_tracker_uri"]}" if metadata.has_key?("bug_tracker_uri")
          stdout.puts "\tMailing List: #{metadata["mailing_list_uri"]}" if metadata.has_key?("mailing_list_uri")
          stdout.puts "\tPath: #{display_path(gem_dir)}"
          stdout.puts "\tDefault Gem: yes" if default_gem?(gem_dir)
          reverse_dependencies = gem_reverse_dependencies(locked_specs, spec.name)
          if reverse_dependencies.any?
            stdout.puts "\tReverse Dependencies: "
            reverse_dependencies.each { |line| stdout.puts "\t\t#{line}" }
          end
          return 0
        end
      end
      stderr.puts "Could not find #{spec.full_name} in locally installed gems"
      7
    end

    # Bundler prints the short git revision in human-readable listings and
    # info headings, and renders paths with forward slashes on Windows.
    private def self.spec_display_name(spec : Lockfile::Spec, lockfile : Lockfile::Data) : String
      short = spec_git_version(spec, lockfile)
      short ? "#{spec.name} (#{spec.version} #{short})" : "#{spec.name} (#{spec.version})"
    end

    # `rubygems_ext.rb:264-267`: git sources contribute `" #{revision[0..6]}"`
    # (seven characters) which the caller strips; non-GIT sources are null in
    # the JSON payload.
    private def self.spec_git_version(spec : Lockfile::Spec, lockfile : Lockfile::Data) : String?
      revision = lockfile.source_for(spec).try do |src|
        src.type == "GIT" ? src.option("revision") : nil
      end
      return nil if revision.nil?
      short = revision.to_s[0, 7]
      short.empty? ? nil : short
    end

    # `cli/show.rb:60-74`: the verbose listing drops the two-space indent
    # (`desc.lstrip`) and adds Summary/Homepage/Status rows, where the status is
    # `Outdated - <current> < <latest>` only when the remote resolution has a
    # newer version of that gem.
    private def self.print_show_verbose_entry(stdout : IO, desc : String, summary : String?,
                                              homepage : String?, current : Gem::Version,
                                              latest : Gem::Version?) : Nil
      status = if latest && current < latest
                 "Outdated - #{current} < #{latest}"
               else
                 "Up to date"
               end
      stdout.puts desc
      stdout.puts "\tSummary:  #{summary || "No description available."}"
      stdout.puts "\tHomepage: #{homepage || "No website available."}"
      stdout.puts "\tStatus:   #{status}"
    end

    private def self.display_path(path : String) : String
      path.gsub('\\', '/')
    end

    # The Bundler release Celerite emulates in this run.
    private def self.profile_bundler_version : String
      ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
    end

    # `bundle show` lists the running Bundler as a gem of the bundle, and
    # `bundle show --paths` prints its gem directory first. Celerite ships the
    # reference Bundler as a compatibility profile instead of an installed gem,
    # so resolve that directory from the configured reference lib (the
    # differential harness and the bridge both export
    # `CELERITE_REFERENCE_BUNDLER_LIB`).
    private def self.bundler_gem_dir : String?
      reference_lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
      return nil if reference_lib.nil? || reference_lib.empty?
      dir = File.dirname(reference_lib)
      (File.directory?(dir) rescue false) ? dir : nil
    end

    private def self.read_gemspec_info(gem_dir : String, full_name : String) : {String?, String?, Hash(String, String)}
      # Try installed specifications first.
      install_root = File.dirname(File.dirname(gem_dir))
      spec_path = File.join(install_root, "specifications", "#{full_name}.gemspec")
      text = (File.file?(spec_path) rescue false) ? File.read(spec_path) : nil
      # Fallback: search abi directories.
      if text.nil?
        ruby_root = File.dirname(install_root)
        if (Dir.exists?(ruby_root) rescue false)
          begin
            Dir.each_child(ruby_root) do |abi|
              candidate = File.join(ruby_root, abi, "specifications", "#{full_name}.gemspec")
              if (File.file?(candidate) rescue false)
                text = File.read(candidate)
                break
              end
            end
          rescue
          end
        end
      end
      # Fallback: PATH/GIT sources keep the gemspec in the gem directory.
      if text.nil? && (Dir.exists?(gem_dir) rescue false)
        gem_name = full_name.sub(/-[^-]+(?:-[^-]+)?\z/, "")
        candidate = File.join(gem_dir, "#{gem_name}.gemspec")
        text = File.read(candidate) if (File.file?(candidate) rescue false)
        if text.nil?
          begin
            Dir.each_child(gem_dir) do |entry|
              next unless entry.ends_with?(".gemspec")
              candidate = File.join(gem_dir, entry)
              if (File.file?(candidate) rescue false)
                text = File.read(candidate)
                break
              end
            end
          rescue
          end
        end
      end
      return {nil, nil, {} of String => String} unless text

      # Match the quotes, not `[^"']`, so an apostrophe inside a double-quoted
      # summary (`The best way to manage your application's dependencies`) does
      # not truncate it.
      summary = text.match(/\.summary\s*=\s*"([^"]*)"/).try(&.[1]) ||
                text.match(/\.summary\s*=\s*'([^']*)'/).try(&.[1])
      homepage = text.match(/\.homepage\s*=\s*"([^"]*)"/).try(&.[1]) ||
                 text.match(/\.homepage\s*=\s*'([^']*)'/).try(&.[1])
      metadata = {} of String => String
      text.scan(/\.metadata\s*=\s*\{(.*?)\}/m) do |match|
        match[1].scan(/["']([^"']+)["']\s*=>\s*["']([^"']*)["']/) do |pair|
          metadata[pair[1]] = pair[2]
        end
      end
      text.scan(/\.metadata\[["']([^"']+)["']\]\s*=\s*["']([^"']*)["']/) do |pair|
        metadata[pair[1]] = pair[2]
      end
      {summary, homepage, metadata}
    end

    # Reference `spec.default_gem?` is true for specs installed in Ruby's
    # default gem directory; bundle-installed gems omit the line.
    private def self.default_gem?(gem_dir : String) : Bool
      return false unless bridge_available?

      bridge = Bridge::Client.new
      begin
        env = bridge.ruby_environment
        default_dir = env.default_gem_dir
        !default_dir.empty? && gem_dir.starts_with?(default_dir)
      rescue
        false
      ensure
        bridge.close
      end
    end

    private def self.gem_reverse_dependencies(locked_specs : Array(Lockfile::Spec), gem_name : String) : Array(String)
      locked_specs.map do |spec|
        dependency = spec.dependencies.find(&.name.==(gem_name))
        next unless dependency
        "#{spec.name} (#{spec.version}) depends on #{gem_name} (#{dependency.requirement})"
      end.compact.sort
    end

    # ------------------------------------------------------------------
    # Group helpers for read-only commands
    # ------------------------------------------------------------------
    # Reference `Bundler::CLI::Common.verbalize_groups`: quote every group,
    # join all but the last with ", " and the last with " and ", and pluralize.
    private def self.verbalize_groups(groups : Array(String)) : String
      quoted = groups.map { |group| "'#{group}'" }
      list = if quoted.size <= 1
               quoted.join
             else
               quoted[0...-1].join(", ") + " and " + quoted[-1]
             end
      "#{quoted.size == 1 ? "group" : "groups"} #{list}"
    end

    def self.lockfile_groups(definition : Definition, lockfile : Lockfile::Data) : Array(String)
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        groups = [] of String
        evaluation.dependencies.each do |dep|
          gs = dep.groups.empty? ? ["default"] : dep.groups
          gs.each { |g| groups << g unless groups.includes?(g) }
        end
        groups
      rescue
        [] of String
      ensure
        bridge.close
      end
    end

    def self.gem_groups_for(definition : Definition, name : String) : Array(String)
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        dep = evaluation.dependencies.find(&.name.==(name))
        groups = dep.try(&.groups) || [] of String
        groups = ["default"] if groups.empty?
        groups
      rescue
        [] of String
      ensure
        bridge.close
      end
    end

    def self.requested_groups_for(config : Config, all_groups : Array(String), only_groups : Array(String), without_groups : Array(String)) : Array(String)
      configured_without = config["without"]
      configured_with = config["with"]
      without_list = configured_without.is_a?(Array(String)) ? configured_without : configured_without.to_s.split(":").reject(&.empty?)
      with_list = configured_with.is_a?(Array(String)) ? configured_with : configured_with.to_s.split(":").reject(&.empty?)

      requested = all_groups - without_list
      requested = (requested + with_list).uniq

      if only_groups.any?
        requested = only_groups
      elsif without_groups.any?
        requested = all_groups - without_groups
      end
      requested
    end

    def self.filter_locked_specs_by_groups(definition : Definition, lockfile : Lockfile::Data, specs : Array(Lockfile::Spec), requested_groups : Array(String)) : Array(Lockfile::Spec)
      return specs if requested_groups.empty? || requested_groups == lockfile_groups(definition, lockfile)
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        group_map = {} of String => Array(String)
        evaluation.dependencies.each do |dep|
          groups = dep.groups
          groups = ["default"] if groups.empty?
          group_map[dep.name] = groups
        end
        specs.select do |spec|
          groups = group_map[spec.name]? || ["default"]
          !(groups & requested_groups).empty?
        end
      rescue
        specs
      ensure
        bridge.close
      end
    end

    def self.bridge_available? : Bool
      server = ENV["CELERITE_BRIDGE_SERVER"]?
      return true if server && !server.empty? && File.file?(server)
      ref_lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
      return true if ref_lib && !ref_lib.empty? && Dir.exists?(ref_lib)
      false
    end

    # ------------------------------------------------------------------
    # M7(4) download/settings helpers (shared by install, update, etc.)
    # ------------------------------------------------------------------
    # Normalize a config SSL option to nil when absent/empty, so empty strings
    # never reach the TLS context (which would raise on ca_certificates="").
    def self.ssl_option(config : Config, key : String) : String?
      value = config[key]
      return nil unless value.is_a?(String)
      value.empty? ? nil : value
    end

    # Normalize the BUNDLE_TIMEOUT config value (default 10) to a positive
    # Int32; falls back to 10 for missing/invalid/zero/negative values.
    def self.timeout_seconds(config : Config) : Int32
      value = config["timeout"]
      seconds = value.is_a?(Int32) ? value : 10
      seconds < 1 ? 10 : seconds
    end

    # Return an error message for explicitly configured but unsupported
    # settings (caller should print it and exit non-zero), or nil when no
    # blocking unsupported setting is present.
    #
    # Policy:
    # - Proxy routing is supported: `Proxy.resolve` honors the `proxy` and
    #   `http_proxy` config keys and the `http_proxy`/`HTTP_PROXY` env vars,
    #   and both the downloader and the compact-index fetcher route through
    #   it. Bundler reads no other proxy env var (`https_proxy`/`ALL_PROXY`)
    #   and no `~/.gemrc` proxy entries, so those are silently ignored here
    #   instead of warning or failing.
    # - ssl_client_key: Bundler 4.0.24 / 4.0.16 / 2.7.2 do not define this
    #   setting at all (`settings.rb` has no such key); a client private key
    #   belongs in the same PEM referenced by `ssl_client_cert`. Because some
    #   users write it anyway we keep failing fast with the historical message.
    # - legacy_index, full_index remain unsupported and fail fast when
    #   explicitly set.
    def self.unsupported_setting_error(config : Config, stderr : IO) : String?
      if ssl_key = config["ssl_client_key"]
        unless ssl_key.nil? || ssl_key.to_s.empty?
          return "not supported by Celerite: ssl_client_key"
        end
      end

      {"legacy_index", "full_index"}.each do |key|
        if idx_setting = config[key]
          unless idx_setting.nil? || idx_setting == false || idx_setting.to_s.empty?
            return "not supported by Celerite: #{key}"
          end
        end
      end

      nil
    end

    # ------------------------------------------------------------------
    # lock (M2: native resolution + generation)
    # ------------------------------------------------------------------
    # Reference `lock --gemfile`/`--lockfile` really use the given files
    # (`Definition.find_gemfile`/`resolve_lockfile` already prefer the ENV
    # vars); scope the override to this command and restore afterwards.
    def self.lock(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if code = reject_unknown_switches(stderr, rest, LOCK_SWITCH_FLAGS, LOCK_SWITCH_VALUES)
        return code
      end
      if code = reject_positional_arguments(stderr, "lock", rest, LOCK_SWITCH_FLAGS, LOCK_SWITCH_VALUES)
        return code
      end
      # `--gemfile` validation lives in `with_gemfile_overrides` so every
      # command that accepts the switch reports the same GemfileNotFound.
      with_gemfile_overrides(rest) do
        run_lock(stdout, stderr, rest)
      end
    end

    private def self.run_lock(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if rest.includes?("--frozen")
        bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        if code = frozen_flag_exit(rest, stderr, Definition.build.lockfile_exists?, bundle_version, "lock")
          return code
        end
      end
      # --normalize-platforms is mutually exclusive with platform add/remove
      # (`CLI::Lock#check_for_conflicting_options`, cli/lock.rb L107-116).
      if rest.includes?("--normalize-platforms")
        if rest.includes?("--add-platform")
          stderr.puts "--normalize-platforms can't be used with --add-platform"
          return 15
        end
        if rest.includes?("--remove-platform")
          stderr.puts "--normalize-platforms can't be used with --remove-platform"
          return 15
        end
      end
      add_platforms = platform_flag_values(rest, "--add-platform")
      remove_platforms = platform_flag_values(rest, "--remove-platform")
      # `--update` is a repeatable array option in the reference; a bare
      # `--update` records `true`, names record a per-gem unlock list.
      update_names = platform_flag_values(rest, "--update")

      definition = Definition.build
      if unsupported = Commands.unsupported_setting_error(definition.config, stderr)
        stderr.puts unsupported
        return 1
      end

      # Platform edits run before resolution, removals first
      # (`Definition#remove_platform`, definition.rb L541-546; cli/lock.rb L49-67).
      if !remove_platforms.empty? || !add_platforms.empty?
        current = platforms_before_changes(definition)
        remove_platforms.each do |value|
          normalized = normalized_platform(value)
          unless current.includes?(normalized)
            stderr.puts "Unable to remove the platform `#{value}` since the only platforms are #{current.join(", ")}"
            return 15
          end
          current.delete(normalized)
        end
        # Unknown platform names are rejected before they reach the lockfile
        # (cli/lock.rb L56-63).
        add_platforms.each do |value|
          normalized = normalized_platform(value)
          if normalized == "unknown"
            stderr.puts "The platform `#{value}` is unknown to RubyGems and can't be added to the lockfile."
            return 1
          end
          current << normalized unless current.includes?(normalized)
        end
        if current.empty?
          stderr.puts "Removing all platforms from the bundle is not allowed"
          return 15
        end
      end
      # `--update NAME` must name a gem that is already locked
      # (`CLI::Common.ensure_all_gems_in_lockfile!`, cli/common.rb L95-103).
      # It returns early when there is no lockfile at all, so a first-time lock
      # with named updates is not an error.
      unless update_names.empty?
        if definition.lockfile_exists?
          locked_names = definition.lockfile!.specs.map(&.name)
          update_names.each do |name|
            next if locked_names.includes?(name)
            stderr.puts gem_not_found_message_for(name, locked_names)
            return 7
          end
        end
      end
      # Removing every platform is rejected before resolution (cli/lock.rb L65-67).
      print_mode = rest.includes?("--print")
      update = rest.includes?("--update") || rest.includes?("--all")

      definition = Definition.build
      unlock : Bool | Array(String) = update_names.empty? ? update : update_names

      resolution = Resolution.new(definition, unlock)
      # The Bundler dependency API warning for scoped Rubygems sources
      # without one is printed by the reference before resolution.
      scoped_remotes = [] of String
      resolution.evaluation.dependencies.each do |dep|
        source = dep.source
        next unless source && (source.type == "Rubygems" || source.type == "Metadata")
        remote = source.remotes.try(&.first?) || source.remote
        next unless remote && !remote.empty?
        scoped_remotes << remote.chomp('/')
      end
      unless scoped_remotes.empty? || resolution.bridge_bundler_version.starts_with?("2.")
        stderr.puts "Your Gemfile contains scoped sources that don't implement a dependency API, namely:"
        stderr.puts
        scoped_remotes.uniq.each { |remote| stderr.puts "  * rubygems repository #{remote}/" }
        stderr.puts
        stderr.puts "Using the above gem servers may result in installing unexpected gems. To resolve this warning, make sure you use gem servers that implement dependency APIs, such as gemstash or geminabox gem servers."
      end

      unless cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
        return 15
      end
      if days = cooldown_flag_value(rest)
        resolution.cooldown_days = days
      end
      resolution.local_only = rest.includes?("--local")
      resolution.prefer_local = rest.includes?("--prefer-local")
      resolution.normalize_platforms = rest.includes?("--normalize-platforms")
      resolution.added_platforms = add_platforms
      resolution.removed_platforms = remove_platforms
      # Progress goes to stdout in write mode, stderr in --print mode
      # (pinned observation from the reference oracle).
      resolution.progress = print_mode ? stderr : stdout

      unless print_mode
        if rest.includes?("--normalize-platforms") || rest.includes?("--add-checksums")
          # Reference re-resolves BEFORE writing for these flags.
          data = resolution.generated_lockfile
          text = data.to_lock
          stdout.puts "Writing lockfile to #{File.expand_path(definition.lockfile_path).gsub(/\\/, "/")}"
        else
          stdout.puts "Writing lockfile to #{File.expand_path(definition.lockfile_path).gsub(/\\/, "/")}"
          data = resolution.generated_lockfile
          text = data.to_lock
        end
      else
        data = resolution.generated_lockfile
        text = data.to_lock
      end

      # A named `--update` unlocks specific gems, and the reference materializes
      # the definition once for the unlock list and again in `#remotely!`, so the
      # progress line appears twice (pinned oracle for `lock --update <gem>`).
      unless update_names.empty?
        (print_mode ? stderr : stdout).puts "Resolving dependencies..."
      end

      if print_mode
        stdout.print text
      else
        Lockfile.write(definition.lockfile_path, text, preserve_crlf: preserve_lockfile_crlf?)
      end
      # 4.0.24: report versions skipped by the cooldown setting (stderr in
      # --print mode, stdout in write mode --pinned reference stream split).
      print_cooldown_summary(resolution, print_mode ? stderr : stdout)
      resolution.close
      0
    end

    # ------------------------------------------------------------------
    # config: get/list/set/unset (pinned 4.0.24 output)
    # ------------------------------------------------------------------
    CONFIG_FLAGS = ["--global", "-g", "--local", "--delete", "--parseable"]

    def self.config(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      case rest.first?
      when nil
        config_deprecated(stdout, stderr, rest)
      when "get"
        config_get(stdout, stderr, rest)
      when "list"
        config_list(stdout, stderr, rest)
      when "set"
        config_set(stdout, stderr, rest)
      when "unset"
        config_unset(stderr, rest)
      else
        config_deprecated(stdout, stderr, rest)
      end
    end

    # Reference `bundle config NAME [VALUE]` (`cli/config.rb:16-32 base`): the
    # legacy interface is deprecated but still applied to the given NAME/VALUE.
    private def self.config_deprecated(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      argv = ["config"] + rest
      replacement =
        if argv.size == 1
          ["config", "list"]
        elsif argv.includes?("--delete")
          argv.map { |arg| arg == "--delete" ? "unset" : arg }
        elsif argv.includes?("--global") || argv.includes?("--local") || argv.size == 3
          ["config", "set"] + argv[1..]
        else
          ["config", "get", argv[1]]
        end
      stderr.puts "[DEPRECATED] Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle #{replacement.join(" ")}` instead."

      parseable = rest.includes?("--parseable")
      global_flag = rest.includes?("--global") || rest.includes?("-g")
      local_flag = rest.includes?("--local")
      return config_scope_conflict(stderr) if global_flag && local_flag
      explicit_scope = global_flag || local_flag
      scope = if global_flag
                "global"
              elsif local_flag
                "local"
              else
                config_project_root ? "local" : "global"
              end

      positionals = rest.reject { |arg| CONFIG_FLAGS.includes?(arg) }
      name = positionals.first?
      value = positionals.size > 1 ? positionals[1..].join(" ") : nil

      if name.nil?
        config_warn_unused_scope(stderr, explicit_scope, parseable, "Ignoring --#{scope}")
        return config_list(stdout, stderr, ["list"] + (parseable ? ["--parseable"] : [] of String))
      end

      if rest.includes?("--delete")
        return config_unset_values(stderr, name, explicit_scope, scope)
      end

      if value.nil?
        config_warn_unused_scope(stderr, explicit_scope, parseable, "Ignoring --#{scope} since no value to set was given")
        return config_confirm_or_parseable(stdout, stderr, name, parseable)
      end

      config_store(stdout, stderr, name, value, scope, parseable)
    end

    # Reference `scope_options` + `validate_scope!` (cli/config.rb:183-196).
    private def self.config_scope_conflict(stderr : IO) : Int32
      stderr.puts word_wrap("The options global and local were specified. Please only use one of the switches at a time.", CLI.terminal_width)
      15
    end

    # Reference `warn_unused_scope` (cli/config.rb:176-181): only with an
    # explicit scope and never in `--parseable` mode.
    private def self.config_warn_unused_scope(stderr : IO, explicit : Bool, parseable : Bool, message : String) : Nil
      return unless explicit && !parseable
      stderr.puts message
    end

    def self.config_get(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      parseable = rest.includes?("--parseable")
      args = rest[1..].reject { |arg| arg == "--parseable" }
      return config_argument_error(stderr, "get", "NAME") if args.empty?
      return config_argument_error(stderr, "get", "NAME", args) if args.size > 1
      name = args.first
      return config_confirm_or_parseable(stdout, stderr, name, parseable)
    end

    # Reference `Base#run` when no value was given (cli/config.rb:88-105).
    private def self.config_confirm_or_parseable(stdout : IO, stderr : IO, name : String, parseable : Bool) : Int32
      config = config_for_command
      value = config[name]
      if parseable
        unless value.nil?
          stdout.puts "#{name}=#{Config.parseable_converted(value)}"
        end
        return value.nil? ? 1 : 0
      end
      stdout.puts "Settings for `#{name}` in order of priority. The top value will be used"
      config.pretty_values_for(name).each do |line|
        stdout.puts line
      end
      value.nil? ? 1 : 0
    end

    private def self.config_list(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      parseable = rest.includes?("--parseable")
      args = rest[1..].reject { |arg| arg == "--parseable" }
      return config_argument_error(stderr, "list", "", args) unless args.empty?
      config = config_for_command
      if parseable
        config.all.each do |name|
          stdout.puts "#{name}=#{Config.parseable_converted(config[name])}"
        end
        return 0
      end
      stdout.puts "Settings are listed in order of priority. The top value will be used."
      config.all.each do |name|
        stdout.puts name
        config.pretty_values_for(name).each { |line| stdout.puts line }
        stdout.puts
      end
      0
    end

    # Config commands work without a Gemfile (the reference resolves the
    # local `.bundle/config` from Bundler.root, falling back to the cwd).
    private def self.config_project_root : String?
      if given = ENV["BUNDLE_GEMFILE"]?
        return File.dirname(File.expand_path(given)) unless given.empty?
      end
      gemfile = Definition.search_up("Gemfile") || Definition.search_up("gems.rb")
      gemfile ? File.dirname(gemfile) : nil
    end

    private def self.config_for_command : Config
      Config.new(config_project_root || Dir.current)
    end

    private def self.config_global_flag?(rest : Array(String)) : Bool
      rest.includes?("--global") || rest.includes?("-g")
    end

    private def self.config_argument_error(stderr : IO, sub : String, usage : String, args : Array(String) = [] of String) : Int32
      if args.empty?
        stderr.puts %(ERROR: "bundle config #{sub}" was called with no arguments)
      else
        stderr.puts %(ERROR: "bundle config #{sub}" was called with arguments [#{args.map(&.inspect).join(", ")}])
      end
      suffix = usage.empty? ? "" : " #{usage}"
      stderr.puts %(Usage: "bundle config #{sub}#{suffix}")
      15
    end

    def self.config_set(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      parseable = rest.includes?("--parseable")
      args = rest[1..].reject { |arg| CONFIG_FLAGS.includes?(arg) }
      return config_argument_error(stderr, "set", "NAME VALUE", args) if args.size < 2
      global_flag = rest.includes?("--global") || rest.includes?("-g")
      local_flag = rest.includes?("--local")
      return config_scope_conflict(stderr) if global_flag && local_flag
      scope = global_flag ? "global" : (local_flag ? "local" : (config_project_root ? "local" : "global"))
      name = args.first
      value = args[1..].join(" ")
      config_store(stdout, stderr, name, value, scope, parseable)
    end

    # Reference `Base#run` set branch (cli/config.rb:107-108) with the
    # `message`/`new_value` helpers (cli/config.rb:134-162).
    private def self.config_store(stdout : IO, stderr : IO, name : String, value : String, scope : String, parseable : Bool) : Int32
      config = config_for_command
      new_value = value
      # Reference `new_value`: `local.<gem>` values that are directories are
      # stored expanded.
      if name.starts_with?("local.") && Dir.exists?(value)
        new_value = File.expand_path(value).gsub(/\\/, "/")
      end
      if parseable
        stdout.puts "#{name}=#{new_value}"
      else
        message = config_set_message(config, name, value, new_value, scope)
        stdout.puts message if message
      end
      if scope == "global"
        config.set_global(name, new_value)
      else
        config.set_local(name, new_value)
      end
      0
    end

    private def self.config_set_message(config : Config, name : String, value : String, new_value : String, scope : String) : String?
      if scope == "global"
        local_value = config.local_config[Config.key_for(name)]?
        if !local_value.nil?
          return "Your application has set #{name} to #{local_value.inspect}. This will override the global value you are currently setting"
        elsif (env_value = ENV[Config.key_for(name)]?)
          return "You have a bundler environment variable for #{name} set to #{env_value.inspect}. This will take precedence over the global value you are setting"
        end
        current = config.global_config[Config.key_for(name)]?
        if !current.nil? && current.to_s != value
          return "You are replacing the current global value of #{name}, which is currently #{current.inspect}"
        end
      else
        current = config.local_config[Config.key_for(name)]?
        if !current.nil? && current.to_s != value
          return "You are replacing the current local value of #{name}, which is currently #{current.inspect}"
        end
      end
      nil
    end

    def self.config_unset(stderr : IO, rest : Array(String)) : Int32
      args = rest[1..].reject { |arg| CONFIG_FLAGS.includes?(arg) }
      return config_argument_error(stderr, "unset", "NAME", args) if args.empty?
      return config_argument_error(stderr, "unset", "NAME", args) if args.size > 1
      global_flag = rest.includes?("--global") || rest.includes?("-g")
      local_flag = rest.includes?("--local")
      return config_scope_conflict(stderr) if global_flag && local_flag
      explicit_scope = global_flag || local_flag
      scope = global_flag ? "global" : (local_flag ? "local" : nil)
      config_unset_values(stderr, args.first, explicit_scope, scope)
    end

    # Reference `Base#run` delete branch (cli/config.rb:78-86).
    private def self.config_unset_values(stderr : IO, name : String, explicit_scope : Bool, scope : String?) : Int32
      config = config_for_command
      # With no explicit scope both levels are cleared; `--local` clears only
      # the local level and `--global` only the global one.
      config.set_local(name, nil) unless explicit_scope && scope == "global"
      config.set_global(name, nil) unless explicit_scope && scope == "local"
      0
    end

    # ------------------------------------------------------------------
    # help
    # ------------------------------------------------------------------
    def self.help(stdout : IO, rest : Array(String)) : Int32
      # Reference `help <cmd>`: a plugin command that is not a builtin runs
      # with ["--help"] (cli.rb:155-160); everything else prints usage.
      target = rest.reject(&.starts_with?("-")).first?
      if target && !BUILTIN_COMMANDS.includes?(target)
        if (plugin_exit = dispatch_plugin_command(target, ["--help"]))
          return plugin_exit
        end
      end
      stdout.puts CLI::USAGE
      0
    end

    # Commands handled by the CLI itself; a plugin command never shadows them.
    BUILTIN_COMMANDS = %w[
      version platform check list show info lock install cache package pack
      clean exec binstubs update add remove env doctor licenses fund open
      plugin pristine init outdated console gem issue config help get set
      unset search push key
    ]

    # Dispatches a project-local plugin command before the `bundler-<name>`
    # PATH fallback (cli.rb:187-195). Best effort: any missing definition or
    # index silently falls through so existing exit codes do not change.
    private def self.dispatch_plugin_command(command : String, rest : Array(String)) : Int32?
      return nil if command.empty? || command.starts_with?("-")
      return nil if BUILTIN_COMMANDS.includes?(command)

      gemfile = begin
        Definition.find_gemfile
      rescue GemfileNotFound
        nil
      end
      project_dir = gemfile ? File.dirname(gemfile) : Dir.current
      config = begin
        Config.new(project_dir)
      rescue
        nil
      end
      return nil if config && !PluginCommands.enabled?(config)

      # `Bundler::Plugin.root`: project plugin tree in a bundle, global
      # (`~/.bundle/plugin`) otherwise — a Gemfile-less cwd does not see a
      # project-local plugin install.
      index = if gemfile
                File.join(project_dir, ".bundle", "plugin", "index")
              else
                File.join(Config.user_home || ".", ".bundle", "plugin", "index")
              end
      return nil unless File.file?(index)
      return nil unless PluginCommands.commands(index).has_key?(command)

      PluginCommands.exec(index, command, rest)
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

    # Reference `current_platform_missing`: the lockfile names neither `ruby`
    # (the generic platform for non-Windows hosts) nor the exact local
    # platform, so the definition re-resolves and the resolver announces it.
    def self.platform_missing?(definition : Definition) : Bool
      return false unless definition.lockfile_exists?
      lockfile = definition.lockfile!
      local = Gem::Platform.local.to_s
      !lockfile.platforms.any? { |p| p == "ruby" || p == local }
    end
  end
end
