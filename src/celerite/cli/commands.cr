require "json"
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
    # Reconstructs the structured Gemfile `ruby` declaration (version,
    # patchlevel, engine, engine_version).  `GemfileEvaluation#ruby` stays the
    # human-readable string for lockfile comparisons, but it drops the option
    # fields, so runtime validation must use the structured fields.
    def self.requested_ruby_version(evaluation : Bridge::GemfileEvaluation) : Celerite::RubyVersion?
      version = evaluation.ruby_version
      return nil unless version
      Celerite::RubyVersion.new(version, evaluation.ruby_patchlevel, evaluation.ruby_engine, evaluation.ruby_engine_version)
    end

    def self.platform(stdout : IO, rest : Array(String)) : Int32
      definition = Definition.build
      parseable = rest.includes?("--ruby")

      lockfile = definition.lockfile_exists? ? definition.lockfile! : nil
      ruby_version = lockfile.try(&.ruby_version).try(&.gsub(/p\d+\Z/, ""))

      output = [] of String
      if parseable
        output << (ruby_version || "No ruby version specified")
      else
        platforms = lockfile.try(&.platforms).dup || [] of String
        # Reference parity: the local platform always appears in the list
        # (add_current_platform appends it when the lockfile omits it).
        local_platform = Gem::Platform.local.to_s
        platforms << local_platform unless platforms.includes?(local_platform)
        platform_lines = platforms.map { |p| "* #{p}" }

        output << "Your platform is: #{Gem::Platform.local}"
        output << "Your app has gems that work on these platforms:\n#{platform_lines.join("\n")}"

        mismatch_message = nil
        ruby_validation_attempted = false
        ruby_validation_skipped = false
        if ruby_version
          # Runtime validation: Bundler prints a mismatch message but exits 0
          # for platform when the Gemfile ruby requirement does not match.
          if bridge_available?
            ruby_validation_attempted = true
            begin
              bridge = Bridge::Client.new
              begin
                evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
                if requested = requested_ruby_version(evaluation)
                  env = bridge.ruby_environment
                  if diff = RubyRuntime.diff_version!(requested, env)
                    system = Celerite::RubyVersion.system_from_env(env)
                    mismatch_message = Celerite::RubyVersion.mismatch_message(diff[0], diff[1], diff[2], requested, system)
                  end
                end
              rescue
                ruby_validation_skipped = true
              ensure
                bridge.close
              end
            rescue
              ruby_validation_skipped = true
            end
          else
            ruby_validation_skipped = true
          end
          output << "Your Gemfile specifies a Ruby version requirement:\n* #{ruby_version}"
          if mismatch_message
            output << mismatch_message
          elsif ruby_validation_skipped
            output << "Ruby version requirement not validated (bridge unavailable); cannot confirm runtime match."
          else
            output << "Your current platform satisfies the Ruby version requirement."
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
    def self.validate_ruby_runtime!(definition : Definition, bridge : Bridge::Client? = nil) : Nil
      return unless bridge_available?
      client = bridge || Bridge::Client.new
      begin
        evaluation = client.evaluate_gemfile(definition.gemfile_path)
        requested = requested_ruby_version(evaluation)
        return unless requested
        env = client.ruby_environment
        RubyRuntime.validate_version!(requested, env)
      ensure
        client.close if bridge.nil?
      end
    rescue ex : Error
      raise ex
    rescue
      # Best-effort: if evaluation/env is unavailable, do not block commands
      # that historically worked without runtime validation.
      nil
    end

    # Reference parity: Bundler re-resolves (printing "Resolving
    # dependencies...") when the Gemfile ruby declaration differs from the
    # lockfile RUBY VERSION, e.g. an explicit patchlevel the lockfile string
    # does not preserve (definition.rb `@unlocking_ruby`).  Celerite keeps
    # using the lockfile, so only the notification is mirrored.
    private def self.lock_ruby_declaration_mismatch?(definition : Definition, lockfile : Lockfile::Data) : Bool
      return false unless bridge_available?
      lock_ruby = lockfile.ruby_version
      return false if lock_ruby.nil? || lock_ruby.empty?
      bridge = Bridge::Client.new
      begin
        evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
        requested = requested_ruby_version(evaluation)
        return false if requested.nil?
        locked = Celerite::RubyVersion.from_string(lock_ruby)
        return false if locked.nil?
        !requested.diff(locked).nil?
      rescue
        false
      ensure
        bridge.close
      end
    end

    # ------------------------------------------------------------------
    # check
    # ------------------------------------------------------------------
    def self.check(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      validate_ruby_runtime!(definition)
      config = definition.config

      if config.frozen? && !definition.lockfile_exists?
        raise ProductionError.new("Frozen mode is set, but there's no lockfile")
      end

      lockfile = definition.lockfile!
      only_groups = flag_values(rest, "--only-group")
      without_groups = flag_values(rest, "--without-group")
      all_groups = bridge_available? ? lockfile_groups(definition, lockfile) : ["default"]

      if only_groups.any? && without_groups.any?
        stderr.puts "The `--only-group` and `--without-group` options cannot be used together"
        return 15
      end
      (only_groups + without_groups).uniq.each do |group|
        unless all_groups.includes?(group)
          stderr.puts "`#{group}` group could not be found."
          return 15
        end
      end

      requested_groups = requested_groups_for(config, all_groups, only_groups, without_groups)
      locked_specs = bridge_available? ? filter_locked_specs_by_groups(definition, lockfile, lockfile.specs.sort_by(&.full_name), requested_groups) : lockfile.specs.sort_by(&.full_name)

      # Reference parity: an explicit Gemfile patchlevel the lockfile RUBY
      # VERSION string does not preserve makes Bundler re-resolve here.
      stdout.puts "Resolving dependencies..." if lock_ruby_declaration_mismatch?(definition, lockfile)

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

      stdout.puts "The Gemfile's dependencies are satisfied"
      0
    end

    # ------------------------------------------------------------------
    # list
    # ------------------------------------------------------------------
    def self.list(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      paths = rest.includes?("--paths")
      name_only = rest.includes?("--name-only")
      json_format = rest.includes?("--format=json") || rest.includes?("--format") && flag_value(rest, "--format") == "json"
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

      all_groups = bridge_available? ? lockfile_groups(definition, lockfile) : ["default"]
      (only_groups + without_groups).uniq.each do |group|
        unless all_groups.includes?(group)
          stderr.puts "`#{group}` group could not be found."
          return 15
        end
      end

      requested_groups = requested_groups_for(config, all_groups, only_groups, without_groups)

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

      # Reference parity: see the platform-missing note in `check`.
      if platform_missing?(definition)
        stdout.puts "Resolving dependencies..."
      end

      # Filter locked specs by requested groups.
      locked_specs = bridge_available? ? filter_locked_specs_by_groups(definition, lockfile, locked_specs, requested_groups) : locked_specs

      missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }
      if missing.empty?
        if json_format
          gems = locked_specs.map do |spec|
            {"name" => spec.name, "version" => spec.version.to_s}
          end
          stdout.puts({"gems" => gems}.to_json)
        elsif paths
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
    def self.show_info(command : String, stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      validate_ruby_runtime!(definition)
      lockfile = definition.lockfile!
      locked_specs = lockfile.specs.sort_by(&.full_name)

      paths = rest.includes?("--paths")
      name_only = rest.includes?("--name-only")
      json_format = rest.includes?("--format=json") || (rest.includes?("--format") && flag_value(rest, "--format") == "json")
      only_groups = flag_values(rest, "--only-group")
      without_groups = flag_values(rest, "--without-group")

      # Validate mutually exclusive group filters like the reference.
      all_groups = bridge_available? ? lockfile_groups(definition, lockfile) : ["default"]
      if only_groups.any? && without_groups.any?
        stderr.puts "The `--only-group` and `--without-group` options cannot be used together"
        return 15
      end
      (only_groups + without_groups).uniq.each do |group|
        unless all_groups.includes?(group)
          stderr.puts "`#{group}` group could not be found."
          return 15
        end
      end

      requested_groups = requested_groups_for(definition.config, all_groups, only_groups, without_groups)
      locked_specs = bridge_available? ? filter_locked_specs_by_groups(definition, lockfile, locked_specs, requested_groups) : locked_specs

      names = rest.reject { |a| a.starts_with?("--") }
      if command == "show" && names.empty?
        stdout.puts "Gems included by the bundle:"
        missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }
        if missing.any?
          full_names = missing.map(&.full_name).join(", ")
          stderr.puts "Could not find #{full_names} in locally installed gems"
          return 7
        end
        if json_format
          gems = locked_specs.map do |spec|
            {"name" => spec.name, "version" => spec.version.to_s}
          end
          stdout.puts({"gems" => gems}.to_json)
        elsif paths
          locked_specs.each do |spec|
            path = installed_gem_dir(definition, spec, lockfile)
            stdout.puts(path ? display_path(path) : spec.full_name)
          end
        elsif name_only
          locked_specs.each { |spec| stdout.puts spec.name }
        else
          locked_specs.each { |spec| stdout.puts "  * #{spec_display_name(spec, lockfile)}" }
        end
        return 0
      end

      name = names.first?
      if name.nil?
        stderr.puts "Could not find command \"#{command}\"."
        return 15
      end

      spec = locked_specs.find(&.name.==(name))
      if spec.nil?
        # Check if gem exists in lockfile but filtered out by group.
        full_spec = lockfile.specs.find(&.name.==(name))
        if full_spec
          # Determine gem's groups
          groups = gem_groups_for(definition, name)
          configured_without = definition.config["without"]
          without_list = configured_without.is_a?(Array(String)) ? configured_without : configured_without.to_s.split(":").reject(&.empty?)
          if groups.any? { |g| without_list.includes?(g) }
            stderr.puts "Could not find gem '#{name}', because it's in the group '#{groups.first}', configured to be"
            stderr.puts "ignored."
            return 7
          end
        end
        stderr.puts "Could not find '#{name}' in locally installed gems. Run `bundle install` to install missing gems."
        return 7
      end

      if json_format
        if gem_dir = installed_gem_dir(definition, spec, lockfile)
          stdout.puts({"name" => spec.name, "version" => spec.version.to_s, "path" => display_path(gem_dir)}.to_json)
          return 0
        end
      elsif paths = rest.includes?("--paths")
        if gem_dir = installed_gem_dir(definition, spec, lockfile)
          stdout.puts display_path(gem_dir)
          return 0
        end
      elsif rest.includes?("--version")
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
      revision = lockfile.source_for(spec).try do |src|
        src.type == "GIT" ? src.option("revision") : nil
      end
      short = revision.to_s[0, 7]
      short.empty? ? "#{spec.name} (#{spec.version})" : "#{spec.name} (#{spec.version} #{short})"
    end

    private def self.display_path(path : String) : String
      path.gsub('\\', '/')
    end

    private def self.read_gemspec_info(gem_dir : String, full_name : String) : {String?, String?, Hash(String, String)}
      # Try installed specifications first.
      install_root = File.dirname(File.dirname(gem_dir))
      spec_path = File.join(install_root, "specifications", "#{full_name}.gemspec")
      text = File.file?(spec_path) ? File.read(spec_path) : nil
      # Fallback: search abi directories.
      if text.nil?
        ruby_root = File.dirname(install_root)
        Dir.each_child(ruby_root) do |abi|
          candidate = File.join(ruby_root, abi, "specifications", "#{full_name}.gemspec")
          if File.file?(candidate)
            text = File.read(candidate)
            break
          end
        end
      end
      return {nil, nil, {} of String => String} unless text

      summary = text.match(/\.summary\s*=\s*["']([^"']*)["']/).try(&.[1])
      homepage = text.match(/\.homepage\s*=\s*["']([^"']*)["']/).try(&.[1])
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
    # lock (M2: native resolution + generation)
    # ------------------------------------------------------------------
    def self.lock(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if rest.includes?("--frozen")
        bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        if code = frozen_flag_exit(rest, stderr, Definition.build.lockfile_exists?, bundle_version, "lock")
          return code
        end
      end
      # --normalize-platforms is mutually exclusive with platform add/remove
      if rest.includes?("--normalize-platforms") && (rest.includes?("--add-platform") || rest.includes?("--remove-platform"))
        stderr.puts "Error: --normalize-platforms can't be used with --add-platform/--remove-platform"
        return 15
      end
      add_platforms = platform_flag_values(rest, "--add-platform")
      remove_platforms = platform_flag_values(rest, "--remove-platform")

      print_mode = rest.includes?("--print")
      update = rest.includes?("--update") || rest.includes?("--all")

      definition = Definition.build
      unlock : Bool | Array(String) = update ? true : false

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

      if print_mode
        stdout.print text
      else
        File.write(definition.lockfile_path, text)
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
    def self.config(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      sub = rest.first?
      case sub
      when nil
        stderr.puts "[DEPRECATED] Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config list` instead."
        config_list(stdout)
      when "get"
        config_get(stdout, stderr, rest)
      when "list"
        config_list(stdout)
      when "set"
        config_set(stdout, stderr, rest)
      when "unset"
        config_unset(rest, stderr)
      else
        stderr.puts "Could not find command \"config #{sub}\"."
        15
      end
    end

    def self.config_get(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      parseable = rest.includes?("--parseable")
      name = rest.reject(&.starts_with?("--")).reject(&.==("get")).first?
      if name.nil?
        return config_argument_error(stderr, "get", "NAME")
      end
      config = config_for_command
      if parseable
        value = config[name]
        stdout.puts "#{name}=#{value}" unless value.nil?
        return value.nil? ? 1 : 0
      end
      stdout.puts "Settings for `#{name}` in order of priority. The top value will be used"
      config.pretty_values_for(name).each do |line|
        stdout.puts line
      end
      config.has?(name) ? 0 : 1
    end

    private def self.config_list(stdout : IO) : Int32
      config = config_for_command
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
      stderr.puts %(Usage: "bundle config #{sub} #{usage}")
      15
    end

    def self.config_set(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      return config_argument_error(stderr, "set", "NAME VALUE", rest[1..]) if rest.size < 3
      explicit = rest.includes?("--global") ? "global" : (rest.includes?("--local") ? "local" : nil)
      # Without a project the reference defaults `config set` to global.
      scope = explicit || (config_project_root.nil? ? "global" : "local")
      args = rest.reject(&.starts_with?("--")).reject(&.==("set"))
      name = args[0]?
      value = args[1..].join(" ")
      return config_argument_error(stderr, "set", "NAME VALUE", rest[1..]) if name.nil? || value.empty?
      config = config_for_command
      new_value = value
      # Reference `new_value`: `local.<gem>` values that are directories are
      # stored expanded.
      if name.starts_with?("local.") && Dir.exists?(value)
        new_value = File.expand_path(value).gsub(/\\/, "/")
      end
      if scope == "global"
        local_value = config.local_config[Config.key_for(name)]?
        if !local_value.nil?
          stdout.puts "Your application has set #{name} to #{local_value.inspect}. This will override the global value you are currently setting"
        elsif (env_value = ENV[Config.key_for(name)]?)
          stdout.puts "You have a bundler environment variable for #{name} set to #{env_value.inspect}. This will take precedence over the global value you are setting"
        else
          current = config.global_config[Config.key_for(name)]?
          if !current.nil? && Config.convert(current, name).to_s != new_value
            stdout.puts "You are replacing the current global value of #{name}, which is currently #{current.inspect}"
          end
        end
        config.set_global(name, new_value)
      else
        current = config.local_config[Config.key_for(name)]?
        if !current.nil? && Config.convert(current, name).to_s != new_value
          stdout.puts "You are replacing the current local value of #{name}, which is currently #{current.inspect}"
        end
        config.set_local(name, new_value)
      end
      0
    end

    def self.config_unset(rest : Array(String), stderr : IO) : Int32
      return config_argument_error(stderr, "unset", "NAME") if rest.size < 2
      explicit = rest.includes?("--global") ? "global" : (rest.includes?("--local") ? "local" : nil)
      args = rest.reject(&.starts_with?("--")).reject(&.==("unset"))
      name = args[0]?
      return config_argument_error(stderr, "unset", "NAME") if name.nil?
      config = config_for_command
      # Reference: unset removes from local and global unless a scope is given.
      if explicit != "global"
        config.set_local(name, nil)
      end
      if explicit != "local"
        config.set_global(name, nil)
      end
      0
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
