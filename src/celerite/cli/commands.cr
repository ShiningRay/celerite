require "json"
require "../../celerite"
require "../errors"
require "../suggestions"
require "../gem/platform"
require "../lockfile/parser"
require "../lockfile/writer"
require "../definition"
require "../resolution"
require "../manpages"
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
      # `--quiet` raises the UI level to `warn` (bundler/cli/install.rb:11 and
      # friends), so every `info`/`confirm` line disappears while warnings and
      # errors stay on stderr. It is captured before `strip_global_flags` for
      # symmetry with `--verbose`, even though it is a method option and
      # therefore already sits inside `rest`.
      quiet_requested = args.includes?("--quiet")
      cli_retry = extract_retry_switch(args)
      # Thor parses the class option `--retry` before dispatch, so a
      # non-numeric value fails before any command output.
      if message = numeric_switch_error(args, ["--retry", "-r"])
        stderr.puts message
        return 15
      end
      raw_args = args
      args = strip_global_flags(args)

      # Thor only shifts a leading token when it resolves a command
      # (`thor.rb:591-595`): a switch that is not one of the dash mappings
      # (`base.rb:17-18` for help/tree, `cli.rb:41-53` for version) stays on the
      # argument list, so the method name is unresolved and
      # `normalize_command_name` (thor.rb:605-620) falls back to
      # `default_command` (cli.rb:133-148). A bare `bundle` takes the same path,
      # which is why it runs the default command instead of printing usage.
      defaulted = raw_args.empty? ||
                  (raw_args[0].starts_with?("-") && !dash_command_map.has_key?(raw_args[0]))

      if defaulted
        # The unresolved tokens all become the default command's arguments
        # (`Thor::Options.split` pulls the switches back out later). Global
        # switches were already consumed by `strip_global_flags`, which is why
        # the echo below does not repeat `--verbose`.
        command = default_cli_command(stdout)
        rest = args
      else
        # Thor resolves the leading token through `normalize_command_name`
        # (thor.rb:605-620): an unambiguous prefix selects the command, an
        # ambiguous prefix raises `Ambiguous command <w> matches [a, b]`, and an
        # unknown token falls through to the did_you_mean path below.
        if (resolved = resolve_command_name(args[0], stderr))
          command = resolved
          rest = args[1..]
        else
          return 15
        end
      end
      command = expand_deprecated_alias(command, stderr)
      print_command_echo(command, rest, verbose_requested, cli_retry, stdout)

      # `--quiet` is honoured by install/update/add/cache (and `doctor`, whose
      # Thor subcommand declares the same option): the reference raises the UI
      # level to `warn`, which silences every `info`/`confirm` line while
      # warnings and errors keep flowing to stderr. The echo above runs before
      # that level change in the reference too, so it survives `--verbose`.
      if quiet_requested && (QUIET_COMMANDS.includes?(command) || command == "doctor")
        stdout = IO::Memory.new
      end

      # Thor prints the command's manpage for `--help` before the body runs
      # (`bundle install --help` renders bundle-install(1)).
      if command != "exec" && (rest.includes?("--help") || rest.includes?("-h"))
        return help(stdout, [command], stderr)
      end

      case command
      when "version", "--version", "-v"
        # The dash mappings fold `-v`/`--version` onto `version` (cli.rb:41-53),
        # so the original tokens are gone by now — the reference decides on the
        # literal `ARGV.include?("version")` (cli.rb:557), not on the resolved
        # command name.
        version(raw_args.includes?("version"), stdout, stderr, rest)
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
      when "cli_help"
        cli_help(stdout, stderr, rest)
      when "tree"
        tree(stdout, stderr, rest)
      when "viz", "inject"
        # 4.0.24 raises `RemovedError` through `feature_removed!`
        # (shared_helpers.rb:129-138, status 9); 2.7.2 still ships both behind
        # `major_deprecation`, so the profile selects the behaviour.
        removed_command(command, rest, stderr)
      when "help", "--help", "-h", "-?", "-D"
        # Thor's dash mappings (`base.rb:17 HELP_MAPPINGS = %w(-h -? --help -D)`)
        # all land on `help`, so `-D`/`-?` render the top-level page too.
        help(stdout, rest, stderr)
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
          # Thor's `UndefinedCommandError` carries the command table as its
          # did_you_mean dictionary (`base.rb:614-615`,
          # `error.rb:37 SpellChecker.new(dictionary: error.all_commands)`), so
          # `lst` suggests `list` while an arbitrary token gets no hint.
          stderr.puts "Could not find command \"#{command}\"."
          if message = Suggestions.message(command, reference_commands)
            stderr.puts message
          end
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

    # Thor's dash mappings, minus the entries the profile does not have: 2.7.2
    # ships no `tree`, so `-t`/`--tree` never map there and stay on the argument
    # list as unknown switches of the default command (measured: 15 with
    # `Unknown switches "-t"`).
    private def self.dash_command_map : Hash(String, String)
      return DASH_COMMAND_MAP_4_X unless profile_2_x?

      DASH_COMMAND_MAP_4_X.reject { |key, _| key == "-t" || key == "--tree" }
    end

    # `Bundler::CLI.all_aliases` (cli.rb:41-53) resolves an alias back to its
    # command; the dash mappings are the same thing keyed by switch.
    private def self.command_alias_target(name : String) : String?
      COMMAND_ALIASES[name]? || dash_command_map[name]?
    end

    # Thor's `find_command_possibilities` (thor.rb:626-638): the candidates are
    # the command table merged with `map` (aliases and dash mappings), filtered
    # by prefix and sorted. An exact hit wins over the longer commands sharing
    # the prefix, and a single mapped candidate resolves directly.
    private def self.command_possibilities(word : String) : Array(String)
      candidates = reference_commands + COMMAND_ALIASES.keys + dash_command_map.keys
      if profile_2_x?
        # 2.7.2's thor.rb:628 is `all_commands.merge(map)` — no hidden-command
        # reject — so `clean`/`cli_help`/`inject`/`viz` all take part there.
      else
        candidates = candidates.reject { |name| HIDDEN_COMMANDS_4_X.includes?(name) }
      end
      possibilities = candidates.select { |name| name.starts_with?(word) }.sort
      return [word] if possibilities.includes?(word)

      unique = possibilities.map { |name| command_alias_target(name) || name }.uniq
      unique.size == 1 ? unique : possibilities
    end

    # Thor's `normalize_command_name` (thor.rb:605-620). An ambiguous prefix is
    # reported before any command output; a word without candidates is handed
    # back untouched so the caller reports `Could not find command` with the
    # did_you_mean corrections.
    private def self.resolve_command_name(word : String, stderr : IO) : String?
      possibilities = command_possibilities(word)
      if possibilities.size > 1
        stderr.puts "Ambiguous command #{word} matches [#{possibilities.join(", ")}]"
        return nil
      end
      resolved = possibilities.first? || word
      command_alias_target(resolved) || resolved
    end

    # `Bundler::CLI#install_or_cli_help` (cli.rb:123-131): the deprecated alias
    # still ships in 4.x, warns on stderr and then runs `install`. 2.7.2 has no
    # such command (measured: 15, `Could not find command
    # "install_or_cli_help".`), so the name is never expanded there.
    private def self.expand_deprecated_alias(command : String, stderr : IO) : String
      return command unless command == "install_or_cli_help"
      return command if profile_2_x?

      stderr.puts "`bundle install_or_cli_help` is a deprecated alias of `bundle install`."
      stderr.puts "It might be called due to the 'default_cli_command' being set to 'install_or_cli_help',"
      stderr.puts "if so fix that by running `bundle config set default_cli_command install --global`."
      "install"
    end

    # Commands whose `--verbose` echo is suppressed (reference
    # `Bundler::CLI::PARSEABLE_COMMANDS`).
    PARSEABLE_COMMANDS = ["check", "config", "help", "exec", "platform", "show", "version"]

    # The three class options of `Bundler::CLI` as Thor renders them
    # (`base.rb:657-675 print_options`, indent 2, padding 3 because `-V,` is
    # the longest alias list): description column starts at offset 53.
    CLASS_OPTION_LINES = "      [--no-color]                                   # Disable colorization in output\n" \
                         "  -r, [--retry=NUM]                                  # Specify the number of times you wish to attempt network commands\n" \
                         "  -V, [--verbose], [--no-verbose], [--skip-verbose]  # Enable verbose output mode\n"

    # `bundle` without a subcommand prints this block unless
    # `default_cli_command` is configured (cli.rb:133-148).
    DEFAULT_CLI_COMMAND_NOTICE = "In a future version of Bundler, running `bundle` without argument will no longer run `bundle install`.\n" \
                                 "Instead, the `cli_help` command will be displayed. Please use `bundle install` explicitly for scripts like CI/CD.\n" \
                                 "You can use the future behavior now with `bundle config set default_cli_command cli_help --global`,\n" \
                                 "or you can continue to use the current behavior with `bundle config set default_cli_command install --global`.\n" \
                                 "This message will be removed after a default_cli_command value is set.\n"

    # `--quiet` is a `method_option` of these commands only
    # (bundler/cli.rb:281 install, :328 update, :418 add, :474 cache);
    # every other command reports `Unknown switches "--quiet"`.
    QUIET_COMMANDS = ["install", "update", "add", "cache", "package", "pack"]

    # Commands `cli_help` lists first, in this exact order (cli.rb:104).
    CLI_HELP_PRIMARY = ["install", "update", "cache", "exec", "config", "help"]

    # `Bundler::CLI.printable_commands(true)` (thor.rb:309-315) in declaration
    # order, with the reference executable name prefixed by `banner`
    # (thor.rb:546-550). Hidden commands are absent: 4.0.24 hides `cli_help`,
    # `install_or_cli_help`, `viz` and `inject`, which leaves 30 rows.
    PRINTABLE_COMMANDS = [
      {"bundle help [COMMAND]", "Describe available commands or one specific command"},
      {"bundle tree", "Print a tree of all available commands"},
      {"bundle init [OPTIONS]", "Generates a Gemfile into the current working directory"},
      {"bundle check [OPTIONS]", "Checks if the dependencies listed in Gemfile are satisfied by currently installed gems"},
      {"bundle remove [GEM [GEM ...]]", "Removes gems from the Gemfile"},
      {"bundle install [OPTIONS]", "Install the current environment to the system"},
      {"bundle update [OPTIONS]", "Update the current environment"},
      {"bundle show GEM [OPTIONS]", "Shows all gems that are part of the bundle, or the path to a given gem"},
      {"bundle list", "List all gems in the bundle"},
      {"bundle info GEM [OPTIONS]", "Show information for the given gem"},
      {"bundle binstubs GEM [OPTIONS]", "Install the binstubs of the listed gem"},
      {"bundle add GEM VERSION", "Add gem to Gemfile and run bundle install"},
      {"bundle outdated GEM [OPTIONS]", "List installed gems with newer versions available"},
      {"bundle fund [OPTIONS]", "Lists information about gems seeking funding assistance"},
      {"bundle cache [OPTIONS]", "Locks and then caches all of the gems into vendor/cache"},
      {"bundle exec [OPTIONS]", "Run the command in context of the bundle"},
      {"bundle config NAME [VALUE]", "Retrieve or set a configuration value"},
      {"bundle open GEM", "Opens the source directory of the given bundled gem"},
      {"bundle console [GROUP]", "Opens an IRB session with the bundle pre-loaded"},
      {"bundle version", "Prints Bundler version information"},
      {"bundle licenses", "Prints the license of all gems in the bundle"},
      {"bundle gem NAME [OPTIONS]", "Creates a skeleton for creating a rubygem"},
      {"bundle clean [OPTIONS]", "Cleans up unused gems in your bundler directory"},
      {"bundle platform [OPTIONS]", "Displays platform compatibility information"},
      {"bundle lock", "Creates a lockfile without installing"},
      {"bundle env", "Print information about the environment Bundler is running under"},
      {"bundle doctor [OPTIONS]", "Checks the bundle for common problems"},
      {"bundle issue", "Learn how to report an issue in Bundler"},
      {"bundle pristine [GEMS...]", "Restores installed gems to pristine condition"},
      {"bundle plugin", "Manage the bundler plugins"},
    ] of Tuple(String, String)

    # 2.7.2 dropped `tree` outright and marks `clean` as `hide: true`
    # (`Bundler::CLI` reflection: 28 printable rows), so `cli_help` shows 21
    # utilities there instead of 24.
    PRINTABLE_COMMANDS_HIDDEN_2_X = ["tree", "clean"]

    # Values accepted for `default_cli_command`
    # (`settings/validator.rb:78-81`); 2.7.2 has no such rule.
    DEFAULT_CLI_COMMAND_VALUES = ["install", "cli_help"]

    # `Bundler::CLI.all_commands` hides these four in 4.0.24. Thor's
    # `find_command_possibilities` rejects hidden commands there
    # (thor.rb:628), so they never take part in prefix matching. 2.7.2 has no
    # such reject (its thor.rb:628 reads `all_commands.merge(map)`), which is
    # why `bundle cl` is ambiguous there (`[clean, cli_help]`) while 4.0.24
    # resolves it to `clean`.
    HIDDEN_COMMANDS_4_X = ["cli_help", "install_or_cli_help", "viz", "inject"]

    # Commands 2.7.2 lacks outright — `LEGACY_ABSENT_COMMANDS` below.
    # Thor's dash mappings for help/tree (`base.rb:17-18`) and version
    # (`cli.rb:41-53`). 2.7.2 has no `tree`, so `-t`/`--tree` stay on the
    # argument list there and end up as unknown switches of the default command.
    DASH_COMMAND_MAP_4_X = {
      "--help"    => "help",
      "-h"        => "help",
      "-?"        => "help",
      "-D"        => "help",
      "-t"        => "tree",
      "--tree"    => "tree",
      "--version" => "version",
      "-v"        => "version",
    }

    # Commands this CLI implements that the reference echoes before running.
    # `info` is a Thor command of its own (bundler/cli.rb:382) and is not part of
    # `PARSEABLE_COMMANDS`, so `bundle info --verbose` echoes while
    # `bundle show --verbose` does not.
    ECHO_COMMANDS = [
      "install", "update", "lock", "cache", "package", "pack", "clean",
      "add", "remove", "binstubs", "env", "doctor", "licenses", "fund",
      "open", "plugin", "pristine", "init", "outdated", "console", "gem", "issue",
      "info", "cli_help", "tree",
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

    # The profile selects the reference implementation we mirror
    # (`CELERITE_PROFILE_BUNDLER_VERSION`, defaulting to 4.0.24).
    def self.bundle_profile_version : String
      ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
    end

    def self.profile_2_x? : Bool
      bundle_profile_version.starts_with?("2.")
    end

    def self.reject_unknown_switches(stderr : IO, rest : Array(String), allowed_flags : Array(String),
                                     allowed_values : Array(String),
                                     dictionary : Array(String)? = nil) : Int32?
      # `--cooldown` only exists on 4.x: 2.7.2 rejects it on every command with
      # `Unknown switches "--cooldown"` (measured on lock/update/cache/install/
      # add/outdated), so it leaves the value surface for the 2.x profile.
      if Commands.profile_2_x?
        allowed_values = allowed_values.reject { |value| value == "--cooldown" }
        dict = dictionary.try(&.reject { |entry| entry == "--cooldown" })
        dictionary = dict
      end
      unknown = unknown_switch_tokens(rest, allowed_flags, allowed_values)
      return nil if unknown.empty?
      stderr.puts "Unknown switches " + unknown.map { |token| "\"#{token}\"" }.join(", ")
      if hinted = Suggestions.message(unknown.first, dictionary || (allowed_flags + allowed_values))
        stderr.puts hinted
      end
      15
    end

    # Thor's class options are accepted by every subcommand. Measured on
    # `Bundler::CLI.class_options`: only `no-color`, `retry` and `verbose`
    # exist, so `--quiet` is a *method* option of install/update/add/cache and
    # every other command reports `Unknown switches "--quiet"`.
    SWITCH_FLAGS_CLASS  = ["--help", "-h", "--no-color", "--verbose", "-V"]
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
    # `cli.rb` binstubs: force, path, shebang, standalone, all, all-platforms.
    # No `quiet` line, so `bundle binstubs --quiet` is an unknown switch and
    # Thor reports it before the command body validates the runtime.
    BINSTUBS_SWITCH_FLAGS  = BARE_SWITCH_FLAGS + ["--force", "--standalone", "--all", "--all-platforms"]
    BINSTUBS_SWITCH_VALUES = BARE_SWITCH_VALUES + ["--path", "--shebang"]

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
    DOCTOR_SUBCOMMAND_FLAGS  = BARE_SWITCH_FLAGS + ["--ssl", "--quiet"]
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
      when "check"
        # `check` carries the same remembered `--path` as `install`: 4.x rejects
        # it, 2.7.x deprecates it and keeps using the value.
        if flags.includes?("--path")
          value = flag_value_ornext(rest, "--path") || "path"
          return RemovedFlag.new("--path", "path", "'#{value}'")
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
    SWITCH_FLAGS_COMMON  = ["-h", "--help", "--verbose", "--no-color"]
    SWITCH_VALUES_COMMON = ["--retry", "--jobs", "-j", "--gemfile"]

    INSTALL_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--local", "--prefer-local", "--full-index", "--standalone", "--no-cache", "--no-lock", "--force", "--redownload", "--path", "--without", "--with", "--quiet"]
    INSTALL_SWITCH_VALUES = SWITCH_VALUES_COMMON + ["--target-rbconfig", "--cooldown", "--trust-policy", "-P", "--lockfile"]

    # `update` and `lock` switch surface, taken from the declared Thor options
    # (`Bundler::CLI.commands[name].options`, identical in 2.7.2 and 4.0.24
    # except `--cooldown`). Anything else must be rejected as an unknown switch
    # instead of being accepted and ignored.
    UPDATE_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--all", "--local", "--full-index", "--force", "--patch", "--minor", "--major", "--pre", "--strict", "--conservative", "--ruby", "--quiet"]
    UPDATE_SWITCH_VALUES = SWITCH_VALUES_COMMON + ["--group", "-g", "--source", "--bundler", "--cooldown"]

    LOCK_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--local", "--full-index", "--print", "--normalize-platforms", "--add-checksums", "--patch", "--minor", "--major", "--pre", "--strict", "--conservative", "--update"]
    LOCK_SWITCH_VALUES = SWITCH_VALUES_COMMON + ["--add-platform", "--remove-platform", "--bundler", "--cooldown", "--lockfile"]

    # `cache` declares only all/all-platforms/cache-path/cooldown/frozen/gemfile/
    # no-install/no-prune/path/quiet (`bundler/cli.rb:466-497`). `--force`,
    # `--redownload`, `--no-cache`, `--local`, `--without` and `--with` are
    # install switches: Thor rejects them here instead of ignoring them.
    CACHE_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--no-install", "--all-platforms", "--path", "--quiet"]
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

    # The reference re-serializes a lockfile with its own writer whenever it
    # prints or rewrites one, so the parsed indentation of `BUNDLED WITH` and
    # `RUBY VERSION` values never survives: 4.x emits two spaces, 2.x three
    # (measured with the same three-space fixture on both profiles).
    private def self.with_profile_indent(text : String) : String
      indent = (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.") ? "   " : "  "
      text.gsub(/(BUNDLED WITH\n|RUBY VERSION\n)[ \t]*/) { "#{$1}#{indent}" }
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
    def self.version(worded : Bool, stdout : IO, stderr : IO, rest : Array(String)) : Int32
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
      # version alone (cli.rb:557 — `ARGV.include?("version")`).
      if worded
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
    # `check` declares only `dry-run` and `gemfile` besides the Thor class
    # options (`bundler/cli.rb:305-312`). `--path` is still a `method_option`
    # (Thor therefore does not call it unknown) but 4.x turns it into the
    # remembered-flag error and 2.7.x only deprecates it -- and persists it, so
    # the check keeps using that path (measured on both profiles).
    CHECK_SWITCH_FLAGS  = SWITCH_FLAGS_COMMON + ["--dry-run", "--path"]
    CHECK_SWITCH_VALUES = ["--retry", "-r", "--gemfile"]
    # `check` reaches the remembered-flag path only for `--path`; the other
    # install flags are plain Thor errors here (`check --no-prune` is unknown and
    # suggests `--no-color`, so they are absent from the Thor dictionary).
    CHECK_REMOVED_FLAGS = ["--path"]
    # Thor's suggestion dictionary is the declared switch list, including the
    # removed ones (`check --no-prune` suggests `--no-color`).
    CHECK_SUGGEST_DICTIONARY = CHECK_SWITCH_FLAGS + CHECK_SWITCH_VALUES + CHECK_REMOVED_FLAGS

    def self.check(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if code = reject_unknown_switches(stderr, rest, CHECK_SWITCH_FLAGS, CHECK_SWITCH_VALUES, CHECK_SUGGEST_DICTIONARY)
        return code
      end
      if code = reject_positional_arguments(stderr, "check", rest, CHECK_SWITCH_FLAGS, CHECK_SWITCH_VALUES + ["--path"])
        return code
      end
      if flag = removed_flag(rest, "check")
        if (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
          stderr.puts removed_flag_deprecation(flag)
          if flag.flag == "--path"
            value = flag.value.strip('\'')
            Definition.build.config.set_local("path", value) unless value.empty?
          end
        else
          stderr.puts word_wrap(removed_flag_message(flag), CLI.terminal_width)
          return 15
        end
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
          # `cli/show.rb:25-28` guards the path print the same way as the plain
          # form: a specification without its extracted directory warns.
          unless Dir.exists?(gem_dir)
            stderr.puts "The gem #{name} is missing. It should be installed at #{display_path(gem_dir)}, but was not found"
            return 0
          end
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
            # `cli/show.rb:25-28`: materialization succeeds as soon as the
            # installed specification exists, so a spec without its extracted
            # directory warns instead of failing.
            unless Dir.exists?(gem_dir)
              stderr.puts "The gem #{name} is missing. It should be installed at #{display_path(gem_dir)}, but was not found"
              return 0
            end
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
      if reference_lib && !reference_lib.empty?
        dir = File.dirname(reference_lib)
        return dir if (File.directory?(dir) rescue false)
      end
      # Outside the harness the running Bundler is the gem the bridge reports:
      # `find_bundler_lib` already walks the RubyGems paths (`Gem.default_path`,
      # `Gem.dir`, `GEM_PATH`, user dir) and prefers the profile version, which
      # is how the reference finds its own install directory even when GEM_HOME
      # is isolated (`shared_helpers.rb:362-378` expands its own `lib`).
      env = (Bridge::Client.new.ruby_environment rescue nil)
      return nil unless env
      bundler_lib = find_bundler_lib(env, profile_bundler_version)
      return nil if bundler_lib.empty?
      dir = File.dirname(bundler_lib)
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
      add_checksums = rest.includes?("--add-checksums")
      normalize_platforms = rest.includes?("--normalize-platforms")

      # The reference only skips the "Resolving dependencies..." line when a
      # lockfile already covers the Gemfile and nothing forces a re-resolution:
      # `--print` and the forcing flags then short-circuit through the locked
      # resolution (`definition.rb:342-363 no_resolve_needed?`). An unlock
      # (`--update` / `--update NAME`), a platform edit, or a lockfile that
      # disagrees with the Gemfile always starts the resolver, which announces
      # the line -- on stderr in `--print` mode (measured on 4.0.24 and 2.7.2:
      # `lock --update --print` and a stale lock both print it).
      lockfile_exists_at_start = definition.lockfile_exists?
      # Missing/empty CHECKSUMS entries force a remote re-resolution even when
      # DEPENDENCIES already matches the Gemfile (`definition.rb:630-659`,
      # `empty_checksums_actionable?`); `--local` keeps the no-op path unless
      # `--add-checksums` explicitly asks to compute (`cli/lock.rb:70`).
      checksum_refresh = definition.checksums_need_refresh?(rest.includes?("--local") && !add_checksums)

      resolution = Resolution.new(definition, unlock)
      # Nothing to unlock and `DEPENDENCIES` already matches the Gemfile: the
      # reference resolves nothing, so plain `lock` prints only "Writing
      # lockfile to ..." and `lock --print` prints only the lock body (measured
      # on 4.0.24 and 2.7.2 -- no "Fetching source index", no "Resolving
      # dependencies..."). The forcing flags resolve too.
      if !checksum_refresh && !update && update_names.empty? && !add_checksums && !normalize_platforms &&
         !rest.includes?("--add-platform") && !rest.includes?("--remove-platform") &&
         definition.lockfile_exists? && definition.lockfile_matches_dependencies?(resolution.evaluation.dependencies)
        resolution.close
        text = with_profile_indent(definition.lockfile!.to_lock)
        if print_mode
          stdout.print text
        else
          stdout.puts "Writing lockfile to #{File.expand_path(definition.lockfile_path).gsub(/\\/, "/")}"
          Lockfile.write(definition.lockfile_path, text, preserve_crlf: preserve_lockfile_crlf?)
        end
        return 0
      end
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
      resolution.local_only = rest.includes?("--local") && !add_checksums
      resolution.prefer_local = rest.includes?("--prefer-local")
      resolution.normalize_platforms = rest.includes?("--normalize-platforms")
      resolution.add_checksums = add_checksums
      resolution.added_platforms = add_platforms
      resolution.removed_platforms = remove_platforms
      # Progress goes to stdout in write mode and to stderr in `--print` mode
      # (pinned oracle: `lock --print` without a lockfile prints the index fetch
      # on stderr). `--print` and the forcing flags omit the
      # "Resolving dependencies..." line.
      resolution.progress = print_mode ? stderr : stdout
      # `no_resolve_needed?` is the only path that skips the announcement: it
      # requires a lockfile that still satisfies the Gemfile and no unlock,
      # platform edit or checksum/normalize forcing flag. `--normalize-platforms`
      # and `--add-checksums` only short-circuit when the lockfile is already
      # current (`lock-normalize` and `lock-add-checksums` fixtures: the resolver
      # prints nothing there but does print when the lockfile is stale).
      lockfile_current = lockfile_exists_at_start &&
                         !update && update_names.empty? &&
                         !rest.includes?("--add-platform") && !rest.includes?("--remove-platform") &&
                         definition.lockfile_matches_dependencies?(resolution.evaluation.dependencies)
      if lockfile_current && (print_mode || normalize_platforms || (add_checksums && !checksum_refresh))
        resolution.show_resolving = false
      end

      # 4.0.24 `--add-checksums` derives digests from the installed package
      # cache before writing the lockfile (`definition.rb:564-583`); the
      # reference prints "Fetching <name> <version>" when it has to download
      # the gem into the bundle cache first.
      if add_checksums && !resolution.bridge_bundler_version.starts_with?("2.")
        resolution.resolve!
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root,
          Commands.retry_count(definition.config), Celerite::Mirror.resolve(definition.config, resolution.primary_remote),
          Commands.ssl_option(definition.config, "ssl_ca_cert"), Commands.ssl_option(definition.config, "ssl_client_cert"),
          Commands.ssl_option(definition.config, "ssl_verify_mode"), definition.config.credentials_for(resolution.primary_remote),
          timeout: Commands.timeout_seconds(definition.config), proxy: Celerite::Proxy.resolve(definition.config))
        resolution.compute_checksums_from_installed do |spec|
          stdout.puts "Fetching #{spec.name} #{spec.version}"
          stdout.flush
          downloader.fetch(spec.name, spec.version.to_s, spec.platform, nil)
        end
      end

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
      # `Bundler::Settings::Validator.validate!` runs inside `set_key`
      # (settings.rb:401-423), i.e. before the value is written, and raises
      # `InvalidOption` for a bad `default_cli_command`
      # (settings/validator.rb:78-81). 2.7.2 has no such rule.
      if !profile_2_x? && name == "default_cli_command" && !DEFAULT_CLI_COMMAND_VALUES.includes?(value)
        stderr.puts "Setting `default_cli_command` to #{value.inspect} failed:"
        stderr.puts " - default_cli_command must be either 'install' or 'cli_help'"
        stderr.puts " - must be one of: #{DEFAULT_CLI_COMMAND_VALUES.join(", ")}"
        return 15
      end
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
    # cli_help
    # ------------------------------------------------------------------
    # `bundle cli_help` (cli.rb:99-121): version banner, the primary commands,
    # the sorted remainder and the three class options. It is hidden from
    # `help`, so the only way to reach it is by name or as `default_cli_command`.
    def self.cli_help(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # Thor `check_unknown_options!` runs before the body (base.rb:619-626),
      # and this command takes no arguments at all.
      if (unknown = reject_unknown_switches(stderr, rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS))
        return unknown
      end

      arguments = subcommand_arguments(rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS)
      unless arguments.empty?
        stderr.puts %(ERROR: "bundle cli_help" was called with arguments #{arguments.inspect})
        stderr.puts %(Usage: "bundle cli_help")
        return 15
      end

      # cli.rb:102-108: the `version` banner, then the two tables. `by_name`
      # keeps the printable rows keyed by their command word; `primary` renders
      # in the fixed CLI_HELP_PRIMARY order and `utilities` in sorted order
      # (both `map!` over the name lists in the reference, so neither keeps the
      # declaration order of `printable_commands`).
      printable = printable_rows
      by_name = {} of String => Tuple(String, String)
      printable.each { |row| by_name[command_word(row[0])] = row }
      stdout.puts version_banner
      stdout.puts ""
      stdout.puts "Bundler commands:"
      stdout.puts ""
      stdout.puts "  Primary commands:"
      render_command_table(stdout, CLI_HELP_PRIMARY.compact_map { |name| by_name[name]? }, indent: 4, truncate_at: 80)
      stdout.puts ""
      stdout.puts "  Utilities:"
      utilities = printable.map { |row| command_word(row[0]) }.sort - CLI_HELP_PRIMARY
      render_command_table(stdout, utilities.compact_map { |name| by_name[name]? }, indent: 4, truncate_at: 80)
      stdout.puts ""
      # base.rb:657-675 `print_options` with indent 2; the three class options
      # share one fixed padding, so CLASS_OPTION_LINES is used verbatim.
      stdout.puts "Options:"
      stdout.print CLASS_OPTION_LINES
      stdout.puts ""
      0
    end

    # The banner `cli_help` prints first (cli.rb:110 + cli.rb:554-566): the
    # full version with build metadata, unlike `bundle version`.
    private def self.version_banner : String
      profile = bundle_profile_version
      if meta = Celerite::ReleaseMetadata.for(profile)
        "Bundler version #{profile} (#{meta[0]} commit #{meta[1]})"
      else
        "Bundler version #{profile}"
      end
    end

    # `Bundler::CLI.printable_commands(true)`, minus the two rows 2.7.2 hides.
    private def self.printable_rows : Array(Tuple(String, String))
      if profile_2_x?
        PRINTABLE_COMMANDS.reject { |row| PRINTABLE_COMMANDS_HIDDEN_2_X.includes?(command_word(row[0])) }
      else
        PRINTABLE_COMMANDS
      end
    end

    # `name.match(/^bundler? (\w+)/)[1]` (cli.rb:105-106) — the command word of
    # a printable banner such as `bundle help [COMMAND]`.
    private def self.command_word(banner : String) : String
      words = banner.split(' ')
      words.size > 1 ? words[1] : banner
    end

    # Thor `TablePrinter` (shell/table_printer.rb), two columns only: the last
    # column is `%-s` and every earlier one is `%-#{maxima + 2}s`
    # (`:59-65`). Rows over `truncate_at` are cut to
    # `chars[0, truncate_at - 3 - indent]` plus `"..."` (`:103-111`), which is
    # what makes a truncated row exactly `truncate_at` columns wide.
    private def self.render_command_table(stdout : IO, rows : Array(Tuple(String, String)), indent : Int32, truncate_at : Int32) : Nil
      return if rows.empty?

      widths = rows.map { |row| row[0].size }
      prefix_width = widths.max.not_nil! + 2
      rows.each do |row|
        sentence = row[0].ljust(prefix_width) + "# #{row[1]}"
        if sentence.size > truncate_at
          sentence = sentence[0, truncate_at - 3 - indent] + "..."
        end
        stdout.puts (" " * indent) + sentence
      end
    end

    # `Bundler::CLI.default_command` (cli.rb:133-148): print the five-line
    # notice unless `default_cli_command` is configured, then return the
    # command the invocation should run. 2.7.2 wires the default with
    # `default_task(Bundler.feature_flag.default_cli_command)` instead, so it
    # never reaches this override: there is no notice and the fallback is
    # already `install` (feature_flag.rb:38), never nil.
    private def self.default_cli_command(stdout : IO) : String
      config = config_for_command
      configured = config["default_cli_command"]
      # `Bundler.settings[:default_cli_command]` is nil until it is set, and
      # that nil is exactly what gates the notice.
      if configured.is_a?(String)
        configured
      elsif profile_2_x?
        "install"
      else
        stdout.print DEFAULT_CLI_COMMAND_NOTICE
        stdout.puts ""
        "install"
      end
    end

    # ------------------------------------------------------------------
    # tree
    # ------------------------------------------------------------------
    # `bundle tree` is Thor's own command, not a `Bundler::CLI` method
    # (thor.rb:675-707): `TREE_MAPPINGS` (`-t`, `--tree`; base.rb:18) map onto
    # it and the body renders `build_command_tree(self.class, "")`. 2.7.2 ships
    # no `tree`, so the name never resolves there (measured: 15,
    # `Could not find command "tree".`).
    TREE_ROOT_NAMESPACE = "bundler:c_l_i"

    # `build_command_tree` skips `hidden?` commands and `help` (thor.rb:689).
    # `tree` itself lives on `Bundler::Thor`, so it is not a `CLI` command
    # either; every other printable row shows up.
    TREE_HIDDEN_COMMANDS = ["help", "tree"]

    # `klass.subcommand_classes` (thor.rb:702) in declaration order, each with
    # its visible commands sorted by name. `config`'s `base` subcommand is
    # `hide: true` (cli/config.rb), so it never appears.
    TREE_SUBCOMMANDS = [
      {"config", [
        {"get", "Returns the value for the given key"},
        {"list", "List out all configured settings"},
        {"set", "Sets the given value for the given key"},
        {"unset", "Unsets the value for the given key"},
      ]},
      {"doctor", [
        {"diagnose", "Checks the bundle for common problems"},
        {"ssl", "Diagnose SSL problems"},
      ]},
      {"plugin", [
        {"install", "Install the plugin from the source"},
        {"list", "List the installed plugins and available commands"},
        {"uninstall", "Uninstall the plugins"},
      ]},
    ]

    def self.tree(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if profile_2_x?
        # Thor's command table has no `tree` under 2.7.2, so the token stays
        # unresolved (thor.rb:605-620) and the reference reports it there.
        stderr.puts %(Could not find command "tree".)
        return 15
      end

      # Thor `check_unknown_options!` (base.rb:619-626) runs before the body;
      # `tree` declares no method options, so only the class options are known.
      if (unknown = reject_unknown_switches(stderr, rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS))
        return unknown
      end

      arguments = subcommand_arguments(rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS)
      unless arguments.empty?
        stderr.puts %(ERROR: "bundle tree" was called with arguments #{arguments.inspect})
        stderr.puts %(Usage: "bundle tree")
        return 15
      end

      stdout.print command_tree
      0
    end

    # `build_command_tree` (thor.rb:684-706). The reference `say` calls carry
    # `:blue`/`:green`, but Thor's shell only emits ANSI codes when stdout is a
    # TTY, which is exactly the non-colored text reproduced here.
    private def self.command_tree : String
      rows = PRINTABLE_COMMANDS
        .reject { |row| TREE_HIDDEN_COMMANDS.includes?(command_word(row[0])) }
        .map { |row| {command_word(row[0]), row[1]} }
        .sort_by { |row| row[0] }

      String.build do |io|
        io << TREE_ROOT_NAMESPACE << '\n'
        render_tree_rows(io, rows, "  ")
        TREE_SUBCOMMANDS.each do |section|
          io << "  " << TREE_ROOT_NAMESPACE << ':' << section[0] << '\n'
          render_tree_rows(io, section[1], "    ")
        end
      end
    end

    private def self.render_tree_rows(io : IO, rows : Array(Tuple(String, String)), indent : String) : Nil
      rows.each_with_index do |row, index|
        icon = index == rows.size - 1 ? "└─" : "├─"
        io << indent << icon << ' ' << row[0] << " (" << row[1] << ")\n"
      end
    end

    # ------------------------------------------------------------------
    # viz / inject
    # ------------------------------------------------------------------
    # 4.0.24 hides both commands and routes them through
    # `SharedHelpers.feature_removed!` (shared_helpers.rb:129-138), which raises
    # `RemovedError` with the `[REMOVED] ` prefix and status 9
    # (cli.rb:583-587, cli.rb:635-638). 2.7.2 still implements both behind
    # `SharedHelpers.major_deprecation 2` (cli.rb:520-535, cli.rb:580-587).
    def self.removed_command(command : String, rest : Array(String), stderr : IO) : Int32
      profile_2_x? ? legacy_removed_command(command, rest, stderr) : removed_command_4_x(command, rest, stderr)
    end

    private def self.removed_command_4_x(command : String, rest : Array(String), stderr : IO) : Int32
      if (unknown = reject_unknown_switches(stderr, rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS))
        return unknown
      end

      if command == "viz"
        # `desc "viz [OPTIONS]"` + `def viz` (cli.rb:583-587): Thor rejects
        # positional arguments before the body raises RemovedError.
        arguments = subcommand_arguments(rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS)
        unless arguments.empty?
          stderr.puts %(ERROR: "bundle viz" was called with arguments #{arguments.inspect})
          stderr.puts %(Usage: "bundle viz [OPTIONS]")
          return 15
        end

        # The reference message spans two lines; `RemovedError` is rendered
        # verbatim (friendly errors only wrap, and there is nothing to wrap).
        raise RemovedError.new("[REMOVED] The `viz` command has been renamed to `graph` and moved to a plugin.\n" \
                               "See https://github.com/rubygems/bundler-graph")
      end

      # `def inject(*)` (cli.rb:635-638) accepts any arguments, so the body
      # runs (and raises) regardless of the positionals.
      raise RemovedError.new("[REMOVED] The `inject` command has been replaced by the `add` command")
    end

    # 2.7.2 `viz` still declares its options (cli.rb:526-530) even though the
    # implementation only reports the missing ruby-graphviz gem.
    LEGACY_VIZ_FLAGS     = SWITCH_FLAGS_CLASS + ["--requirements", "-R", "--version", "-v"]
    LEGACY_VIZ_VALUES    = SWITCH_VALUES_CLASS + ["--file", "-f", "--format", "-F", "--without", "-W"]
    LEGACY_INJECT_VALUES = SWITCH_VALUES_CLASS + ["--source", "--group"]

    private def self.legacy_removed_command(command : String, rest : Array(String), stderr : IO) : Int32
      if command == "viz"
        if (unknown = reject_unknown_switches(stderr, rest, LEGACY_VIZ_FLAGS, LEGACY_VIZ_VALUES))
          return unknown
        end

        arguments = subcommand_arguments(rest, LEGACY_VIZ_FLAGS, LEGACY_VIZ_VALUES, ["--without", "-W"])
        unless arguments.empty?
          stderr.puts %(ERROR: "bundle viz" was called with arguments #{arguments.inspect})
          stderr.puts %(Usage: "bundle viz [OPTIONS]")
          return 15
        end

        # `cli/viz.rb:10-29` (2.7.2): `major_deprecation`, then
        # `gem "ruby-graphviz"` / `require "graphviz"`; a missing gem prints the
        # exception, the install guidance, and still exits 0. The exception
        # line names the host's gem count and GEM_PATH, so it cannot be
        # reproduced — see docs/compat-report.md (declared difference).
        stderr.puts "[DEPRECATED] The `viz` command has been renamed to `graph` and moved to a plugin. " \
                    "See https://github.com/rubygems/bundler-graph"
        stderr.puts "Make sure you have the graphviz ruby gem. You can install it with:"
        stderr.puts "`gem install ruby-graphviz`"
        return 0
      end

      # `def inject(name, version)` (cli.rb:583): Thor reports a missing or
      # surplus positional before the body's deprecation notice.
      if (unknown = reject_unknown_switches(stderr, rest, SWITCH_FLAGS_CLASS, LEGACY_INJECT_VALUES))
        return unknown
      end

      arguments = subcommand_arguments(rest, SWITCH_FLAGS_CLASS, LEGACY_INJECT_VALUES)
      if arguments.empty?
        stderr.puts %(ERROR: "bundle inject" was called with no arguments)
        stderr.puts %(Usage: "bundle inject GEM VERSION")
        return 15
      end
      unless arguments.size == 2
        stderr.puts %(ERROR: "bundle inject" was called with arguments #{arguments.inspect})
        stderr.puts %(Usage: "bundle inject GEM VERSION")
        return 15
      end

      stderr.puts "[DEPRECATED] The `inject` command has been replaced by the `add` command"
      # `Inject#run` resolves the Gemfile first; without one the reference exits
      # 10 (measured) before touching anything. Rewriting a present Gemfile is
      # out of scope for this slice (declared difference).
      gemfile = begin
        Definition.find_gemfile
      rescue GemfileNotFound
        nil
      end
      raise GemfileNotFound.new("Could not locate Gemfile") unless gemfile
      raise UnsupportedCommandError.new("The 'inject' command is not implemented yet.")
    end

    # ------------------------------------------------------------------
    # help
    # ------------------------------------------------------------------
    # `bundle help [COMMAND]` (cli.rb:155-185): resolve an alias, hand unknown
    # names to plugins, otherwise print the vendored `.ronn` page. Names that
    # have no page fall back to Thor's own `command_help` rendering
    # (thor.rb:252-280) — that is what the reference does for hidden commands
    # such as `tree`/`viz`/`inject`/`cli_help`.
    def self.help(stdout : IO, rest : Array(String), stderr : IO = STDERR) : Int32
      if (unknown = reject_unknown_switches(stderr, rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS))
        return unknown
      end

      arguments = subcommand_arguments(rest, SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS)
      if arguments.size > 1
        # Thor `handle_argument_error` (base.rb:619-626): two lines, no trailing
        # blank line (`shell.error` strips the one it would add).
        stderr.puts %(ERROR: "bundle help" was called with arguments #{arguments.inspect})
        stderr.puts %(Usage: "bundle help [COMMAND]")
        return 15
      end

      target = arguments.first?
      unless target
        Manpages.render("bundle", stdout)
        return 0
      end

      # `cli.rb:156` maps an alias back to its command before the page lookup;
      # `cli.rb:162-166` gives `gemfile` its own section-5 page. Both happen on
      # the *raw* token, which is why `help v` renders Thor's help text for
      # `version` instead of the `bundle-version` page.
      canonical = COMMAND_ALIASES[target]? || target
      if Manpages.render(canonical, stdout)
        return 0
      end

      # No page: the reference falls through to `super`, i.e. Thor's
      # `command_help`, which resolves the name through `normalize_command_name`
      # (thor.rb:605-620) and renders it.
      possibilities = command_possibilities(canonical)
      if possibilities.size > 1
        stderr.puts "Ambiguous command #{canonical} matches [#{possibilities.join(", ")}]"
        return 15
      end
      resolved = possibilities.first? || canonical
      resolved = command_alias_target(resolved) || resolved

      if reference_commands.includes?(resolved)
        if entry = thor_help_entry(resolved)
          stdout.print(Manpages.normalize_newlines(thor_help_text(entry[0], entry[1])))
          return 0
        end
      end

      if (plugin_exit = dispatch_plugin_command(target, ["--help"]))
        return plugin_exit
      end

      help_unknown_command(canonical, stderr)
    end

    # Thor `command_help` (thor.rb:252-280): usage banner, the three class
    # options and the command description. Hidden commands such as `tree`,
    # `viz`, `inject`, `cli_help` and `install_or_cli_help` have no man page,
    # so the reference renders this instead.
    private def self.thor_help_text(usage : String, description : String) : String
      String.build do |io|
        io << "Usage:\n"
        io << "  bundle " << usage << '\n'
        io << '\n'
        io << "Options:\n"
        io << CLASS_OPTION_LINES
        io << '\n'
        io << description << '\n'
      end
    end

    # Thor `command_help` also prints the command's own option table
    # (thor.rb:258-262). Reproducing that table needs per-option banners and
    # defaults the CLI does not carry, so this port renders the usage banner,
    # the class options and the description only — see docs/compat-report.md
    # for the declared difference.
    private def self.thor_help_entry(name : String) : Tuple(String, String)?
      if entry = THOR_HELP_FALLBACK[name]?
        return {entry[0], entry[1]}
      end

      PRINTABLE_COMMANDS.each do |banner, description|
        next unless banner == "bundle #{name}" || banner.starts_with?("bundle #{name} ")
        return {banner.lchop("bundle "), description}
      end
      nil
    end

    # Thor `UndefinedCommandError#message` plus its did_you_mean corrections
    # (error.rb:24-55); the dictionary is the reference command table, hidden
    # commands included.
    private def self.help_unknown_command(target : String, stderr : IO) : Int32
      stderr.puts %(Could not find command "#{target}".)
      if message = Suggestions.message(target, reference_commands)
        stderr.puts message
      end
      15
    end

    # `Bundler::CLI.all_aliases` (cli.rb:16-24, 41-53): every alias maps back to
    # the canonical command name before `help` looks for a man page. The Thor
    # dash mappings (`-h`, `-?`, `--help`, `-D` -> help) are handled in
    # `dispatch`, because they never reach `help` as its own argument.
    COMMAND_ALIASES = {
      "c"       => "check",
      "i"       => "install",
      "ls"      => "list",
      "e"       => "exec",
      "ex"      => "exec",
      "exe"     => "exec",
      "package" => "cache",
      "pack"    => "cache",
    }

    # The reference command table, hidden commands included
    # (`Bundler::CLI` reflection: 33 entries). It doubles as the did_you_mean
    # dictionary, which is why `lst` suggests `list` and `get` suggests `gem`
    # while arbitrary misspellings get nothing.
    REFERENCE_COMMANDS = [
      "add", "binstubs", "cache", "check", "clean", "cli_help", "config",
      "console", "doctor", "env", "exec", "fund", "gem", "help", "info",
      "init", "inject", "install", "install_or_cli_help", "issue", "licenses",
      "list", "lock", "open", "outdated", "platform", "plugin", "pristine",
      "remove", "show", "tree", "update", "version", "viz",
    ]

    # Commands that exist in the reference but ship no man page; `help` renders
    # Thor's `command_help` text for them (usage banner, description), which is
    # what `cli.rb:155-185` falls through to via `super`.
    THOR_HELP_FALLBACK = {
      "tree"                => {"tree", "Print a tree of all available commands"},
      "viz"                 => {"viz [OPTIONS]", "Generates a visual dependency graph"},
      "inject"              => {"inject GEM VERSION", "Add the named gem, with version requirements, to the resolved Gemfile"},
      "cli_help"            => {"cli_help", "Prints a summary of bundler commands"},
      "install_or_cli_help" => {"install_or_cli_help", "Deprecated alias of install"},
    }

    # 2.7.2 dropped `tree` and `install_or_cli_help` (`Bundler::CLI` reflection:
    # 32 commands, 4.0.24 has 33). Asking `help` for them under that profile is
    # an undefined command in the reference, not a Thor help fallback — and the
    # did_you_mean dictionary is the same table, so no suggestion is offered
    # either.
    LEGACY_ABSENT_COMMANDS = ["tree", "install_or_cli_help"]

    private def self.reference_commands : Array(String)
      if profile_2_x?
        REFERENCE_COMMANDS.reject { |name| LEGACY_ABSENT_COMMANDS.includes?(name) }
      else
        REFERENCE_COMMANDS
      end
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
