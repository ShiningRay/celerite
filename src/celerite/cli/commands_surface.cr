require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../definition"
require "../resolution"
require "./commands_install"
require "../git_source"
require "yaml"

module Celerite
  # M5 CLI surface commands (pinned against the 4.0.24 oracle): update,
  # add/remove, env, doctor, licenses, fund, info, open, plugin.
  module Commands
    # ------------------------------------------------------------------
    # update: resolve with the named gems (or all) unlocked
    # ------------------------------------------------------------------
    def self.update(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      if rest.includes?("--frozen")
        # Thor rejects the flag before any Gemfile validation; the exact
        # message depends on the profile and the command (see frozen helper).
        bundle_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
        if code = frozen_flag_exit(rest, stderr, Definition.build.lockfile_exists?, bundle_version, "update")
          return code
        end
      end
      conservative = rest.includes?("--conservative")
      # --group: only deps of these groups are unlocked (parity with
      # `update --group dev`).
      only_group = flag_value(rest, "--group") || flag_value(rest, "-g")
      gems = rest.reject(&.starts_with?("--"))
      all = gems.present? == false
      # --conservative: the named gems only move as far as other requirements
      # allow; the reference implementation still prints the full progress.
      gems = gems.reject(&.==("conservative"))

      # parity: bare `bundle update` works but deprecates on stderr on 4.x
      # (2.7.x never deprecates the bare form — observed oracle diff).
      # `--ruby` and explicit selections/`--all` suppress the deprecation.
      has_gems = gems.present?
      bridge_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"
      if all && !rest.includes?("--all") && !bridge_version.starts_with?("2.") &&
         !rest.includes?("--ruby") && !rest.includes?("--group") && !rest.includes?("-g")
        stderr.puts "[DEPRECATED] Pass --all to `bundle update` to update everything"
      end

      definition = Definition.build
      config = definition.config
      if config.frozen? && !definition.lockfile_exists?
        raise ProductionError.new("Frozen mode is set, but there's no lockfile")
      end

      unless definition.lockfile_exists?
        stderr.puts "This Gemfile does not contain a lockfile. Run `bundle install` first."
        return 1
      end

      # --source=NAME: only gems from the named Gemfile source unlock; an
      # unknown name matches nothing (reference probe: resolve, then
      # "Bundle updated!" with no installs and no stayed-same report).
      source_restricted = !flag_value(rest, "--source").nil?
      bridge = Bridge::Client.new
      begin
        unlock : Bool | Array(String) = all ? true : gems
        if source_name = flag_value(rest, "--source")
          evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
          matched = evaluation.sources.any? do |s|
            s.name == source_name || s.remote == source_name ||
              (s.remotes || [] of String).includes?(source_name)
          end
          unlock = matched ? unlock : ([] of String)
        end
        if only_group
          # Restrict the update set to the requested groups (parity with
          # `update --group dev`); ungrouped top-level deps are kept.
          evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
          wanted = only_group.gsub(/\s/, ",").split(",").map(&.strip)
          group_deps = evaluation.dependencies.select do |dep|
            dep.groups.any? { |g| wanted.includes?(g) } || dep.groups.empty?
          end
          unlock = (all || only_group) ? group_deps.map(&.name) : gems
        end
        resolution = Resolution.new(definition, unlock, bridge)
        resolution.progress = stdout
        resolution.ruby_update = rest.includes?("--ruby")
        lock = ProcessLock.lock(InstallPaths.install_path(config))
        unless cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        resolution.local_only = rest.includes?("--local")
        resolution.prefer_local = rest.includes?("--prefer-local")
        if days = cooldown_flag_value(rest)
          resolution.cooldown_days = days
        end
        level = if rest.includes?("--patch")
                  "patch"
                elsif rest.includes?("--minor")
                  "minor"
                elsif rest.includes?("--major")
                  "major"
                end
        resolution.version_promotion = level
        resolution.version_promotion_strict = rest.includes?("--strict")

        # BUNDLED WITH semantics: update does not auto-switch — it records
        # the running bundler version in the rewritten lockfile (pinned
        # 2.7.2 reference: update on a 4.0.24 lockfile rewrote BUNDLED WITH
        # to its own version with 2.x indentation).

        install_path = InstallPaths.install_path(config)
        abi = InstallPaths.ruby_abi(bridge)
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root)
        installer = Installer.new(install_path, abi, bridge, downloader, stdout)

        specs = resolution.resolve!

        # Reference prints "Resolving dependencies..." twice for named gems
        # (a conservative pre-resolve, then the real resolve)
        if !all && !gems.empty? && !source_restricted
          stdout.puts "Resolving dependencies..." if conservative || !conservative
        end

        pending = specs.sort_by(&.full_name).select(&.source_type.==("GEM")).reject do |spec|
          installer.installed?(spec.name, spec.version.to_s, spec.platform)
        end
        previous_versions = definition.lockfile_exists? ? definition.lockfile!.specs.to_h { |s| {s.name, s.version} } : {} of String => String
        was_suffix = ->(spec : Resolution::ResolvedSpec) do
          if old = previous_versions[spec.name]?
            old != spec.version.to_s ? " (was #{old})" : ""
          else
            ""
          end
        end
        cached_paths = {} of String => String
        pending.each do |spec|
          stdout.puts "Fetching #{spec.name} #{spec.version}#{was_suffix.call(spec)}"
          cached_paths[spec.full_name] = downloader.fetch(
            spec.name, spec.version.to_s, spec.platform, spec.checksum
          )
        end
        # Reference installs pure-Ruby gems first, native extensions last.
        pure, ext = pending.partition do |spec|
          cached = cached_paths[spec.full_name]?
          begin
            cached.nil? || Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(cached).to_json).extensions.empty?
          rescue
            true
          end
        end
        (pure + ext).each do |spec|
          cached = cached_paths[spec.full_name]?
          stdout.puts "Installing #{spec.name} #{spec.version}#{was_suffix.call(spec)}#{native_suffix(bridge, cached)}"
          installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum)
          if cached && File.file?(cached)
            sha = Digest::SHA256.hexdigest(File.read(cached))
            resolution.install_checksums["#{spec.name}-#{spec.version}"] = "sha256=#{sha}"
          end
        end

        unless config.frozen?
          text = resolution.generated_lockfile.to_lock
          File.write(definition.lockfile_path, text)
        end

        # parity: specific-gem updates report unchanged versions on stderr
        unless all || source_restricted
          resolved_names = specs.map(&.name).to_set
          gems.each do |gem|
            next if resolved_names.includes?(gem) && pending.any? { |s| s.name == gem }
            next unless resolved_names.includes?(gem)
            stderr.puts "Bundler attempted to update #{gem} but its version stayed the same"
          end
        end

        stdout.puts "Bundle updated!"
        print_cooldown_summary(resolution, stdout)
        0
      ensure
        lock.not_nil!.close
        bridge.close
      end
    end

    # ------------------------------------------------------------------
    # add: append `gem "name"` to the Gemfile and install
    # ------------------------------------------------------------------
    def self.add(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      name = rest.reject(&.starts_with?("--")).first?
      if name.nil?
        stderr.puts "`add` requires at least 1 argument"
        return 1
      end

      # Pinned by `add-git`: the reference announces the git fetch before the
      # requirement probe's index fetch/resolve lines.
      if git = flag_value(rest, "--git")
        stdout.puts "Fetching #{git}"
      end

      definition = Definition.build
      gemfile_path = definition.gemfile_path
      gemfile = File.read(gemfile_path)

      if gemfile.matches?(/^\s*gem\s+["']#{Regex.escape(name)}["']/)
        stderr.puts "Cannot declare #{name} twice in the Gemfile"
        return 1
      end

      # Requirement semantics pinned by add-version/add-strict/
      # add-optimistic probes: explicit `--version` is exact; otherwise
      # strict (`= major.minor`), optimistic (`>= major.minor`) or the
      # default pessimistic (`~> major.minor`) form.
      version_requirement = latest_requirement_for(definition, name, stdout, rest)
      groups = (flag_value(rest, "--group") || flag_value(rest, "-g") || "").split(",").map(&.strip).reject(&.empty?)
      group_line = groups.empty? ? "" : ", group: #{groups.size == 1 && !rest.join(" ").includes?(",") ? ":#{groups.first}" : groups.map { |g| ":#{g}" }.join(", ")}"
      gem_line = "gem \"#{name}\"#{version_requirement}#{group_line}#{add_option_suffix(rest)}"

      # Ruby's text mode on Windows rewrites the Gemfile with CRLF (reference
      # parity: the file is normalized, not preserved).
      lines = gemfile.gsub(/\r\n/, "\n").chomp.split("\n")
      insert_at = lines.rindex { |l| l.strip.starts_with?("gem ") } || (lines.size - 1)
      lines.insert(insert_at + 1, gem_line)
      eol = {{ flag?(:windows) }} ? "\r\n" : "\n"
      File.write(gemfile_path, lines.join(eol) + eol)

      if rest.includes?("--skip-install")
        # Pinned by `add-skip-install`: write the Gemfile line (after the
        # requirement probe) and stop before installation.
        return 0
      end

      # Reference add prints two fetches (requirement probing + shared
      # resolution); install() repeats the second fetch when the lockfile
      # is (re)written.
      code = install(stdout, stderr,
        rest.reject { |a| a == name || a.starts_with?("--") } + rest.select(&.starts_with?("--")),
        summary: false, no_reuse: true)
      code
    end

    # Gemfile options added by `bundle add` (--path/--git/--branch/--ref/
    # --source/--require). Values are Ruby string literals; `--require`
    # accepts the bare keyword `false`.
    private def self.add_option_suffix(rest : Array(String)) : String
      parts = [] of String
      if path = flag_value(rest, "--path")
        parts << "path: #{path.inspect}"
      end
      if git = flag_value(rest, "--git")
        parts << "git: #{git.inspect}"
      end
      if branch = flag_value(rest, "--branch")
        parts << "branch: #{branch.inspect}"
      end
      if git_ref = flag_value(rest, "--ref")
        parts << "ref: #{git_ref.inspect}"
      end
      if source = flag_value(rest, "--source") || flag_value(rest, "-s")
        parts << "source: #{source.inspect}"
      end
      if require_path = flag_value(rest, "--require") || flag_value(rest, "-r")
        parts << (require_path == "false" ? "require: false" : "require: #{require_path.inspect}")
      end
      parts.map { |part| ", #{part}" }.join
    end

    private def self.latest_requirement_for(definition : Definition, name : String, stdout : IO, rest : Array(String)) : String
      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, false, bridge)
        resolution.progress = stdout # probe resolves first: prints fetch+Resolving
        resolution.show_resolving = true
        resolution.resolve! # lines 1-2 of the reference add output

        if explicit = flag_value(rest, "--version") || flag_value(rest, "-v")
          return ", \"= #{explicit}\""
        end

        versions = if local_spec_dir = flag_value(rest, "--path") || flag_value(rest, "--git")
                     # Path and local-git sources derive the version from the
                     # local gemspec (pinned `add-path`); index probes do not
                     # see the gem.
                     begin
                       info = bridge.load_gemspec_dir(File.expand_path(local_spec_dir, Dir.current))
                       [Gem::Version.new(info.version)]
                     rescue
                       [] of Gem::Version
                     end
                   else
                     # When scoped `--source` is used, resolve the requirement
                     # from that source rather than the primary remote.
                     source_remote = flag_value(rest, "--source") || flag_value(rest, "-s")
                     client = source_remote ? resolution.compact_index_client_for(source_remote) : resolution.compact_index_client
                     entries = client.info(name)
                     entries.map { |e| Gem::Version.new(e.version) }.reject(&.prerelease?)
                   end
        return "" if versions.empty?
        latest = versions.max
        # Pinned `Injector#conservative_version`: versions < 1.0 keep three
        # segments (0.1.0), versions >= 1.0 keep major.minor (1.8).
        seg_end = latest >= Gem::Version.new("1.0") ? 1 : 2
        segs = latest.segments
        segs = segs[0..seg_end] if segs.size > seg_end + 1
        operator = if rest.includes?("--strict")
                     "= "
                   elsif rest.includes?("--optimistic")
                     ">= "
                   else
                     "~> "
                   end
        ", \"#{operator}#{segs.join(".")}\""
      rescue
        ""
      ensure
        bridge.close
      end
    end

    # ------------------------------------------------------------------
    # remove: delete `gem "name"` lines from the Gemfile and clean up
    # ------------------------------------------------------------------
    def self.remove(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      names = rest.reject(&.starts_with?("--"))
      if names.empty?
        stderr.puts "`remove` requires at least 1 argument"
        return 1
      end

      definition = Definition.build
      gemfile_path = definition.gemfile_path
      lines = File.read(gemfile_path).gsub(/\r\n/, "\n").chomp.split("\n")

      removed = [] of String
      kept = lines.select do |line|
        matched = names.any? { |n| line.strip.matches?(/^gem\s+["']#{Regex.escape(n)}["']/) }
        removed << line.strip if matched
        !matched
      end

      if removed.empty?
        stderr.puts "No gems were removed from the Gemfile"
        return 1
      end

      stdout.puts "Removing gems from #{gemfile_path.gsub(/\\/, "/")}"
      eol = {{ flag?(:windows) }} ? "\r\n" : "\n"
      File.write(gemfile_path, kept.join(eol) + eol)
      removed.each do |line|
        label = line.sub(/^gem\s+/, "").gsub(/['"]/, "").split(",")[0].strip
        req_label = definition.lockfile!.dependencies.find(&.name.==(label)).try do |dep|
          reqs = dep.requirements
          reqs.nil? || reqs.empty? ? label : "#{label} (#{reqs.join(", ")})"
        end || label
        stdout.puts "#{req_label} was removed."
      end

      # Reference remove: regenerate the lockfile and prune the bundle
      # silently (no progress/summary output).
      null = IO::Memory.new
      install(null, stderr, rest, summary: false)

      # silently remove the unneeded gems from the bundle path
      bridge = Bridge::Client.new
      begin
        abi = InstallPaths.ruby_abi(bridge)
        install_root = File.join(InstallPaths.install_path(definition.config), "ruby", abi)
        used = Set(String).new
        definition.lockfile!.specs.each { |s| used << s.full_name }
        gems_dir = File.join(install_root, "gems")
        if Dir.exists?(gems_dir)
          Dir.children(gems_dir).each do |full_name|
            next if used.includes?(full_name)
            FileUtils.rm_rf(File.join(gems_dir, full_name))
            spec_file = File.join(install_root, "specifications", "#{full_name}.gemspec")
            File.delete(spec_file) if File.file?(spec_file)
          end
        end
      ensure
        bridge.close
      end
      0
    end

    # ------------------------------------------------------------------
    # env: full environment dump (pinned reference sections)
    # ------------------------------------------------------------------
    def self.env(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        re = bridge.ruby_environment
        config = definition.config
        bundler_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"

        stdout.puts "## Environment"
        stdout.puts
        stdout.puts "```"
        stdout.puts "Bundler       #{bundler_version}"
        platforms = [Gem::Platform::RUBY.to_s, Gem::Platform.local.to_s]
        stdout.puts "  Platforms   #{platforms.join(", ")}"
        stdout.puts "Ruby          #{re.ruby_env_line}"
        stdout.puts "  Full Path   #{re.ruby_exe.gsub(/\\/, "/")}"
        stdout.puts "  Config Dir  #{config_dir.gsub(/\\/, "/")}"
        stdout.puts "RubyGems      #{re.rubygems_version}"
        stdout.puts "  Gem Home    #{re.default_gem_dir.gsub(/\\/, "/")}"
        stdout.puts "  Gem Path    #{re.gem_paths.map(&.gsub(/\\/, "/")).join(", ")}"
        user_dir = re.user_gem_dir
        if user_dir
          forward = user_dir.gsub(/\\/, "/")
          stdout.puts "  User Home   #{forward.sub(/\/\.local\/share\/gem.*/, "")}"
          stdout.puts "  User Path   #{forward}"
        else
          stdout.puts "  User Home   "
          stdout.puts "  User Path   "
        end
        stdout.puts "  Bin Dir     #{File.join(re.default_gem_dir, "bin").gsub(/\\/, "/")}"
        stdout.puts "Tools         "
        stdout.puts "  Git         #{git_version}"
        stdout.puts "  RVM         not installed"
        stdout.puts "  rbenv       not installed"
        stdout.puts "  chruby      not installed"
        stdout.puts "```"
        stdout.puts
        stdout.puts "## Bundler Build Metadata"
        stdout.puts
        stdout.puts "```"
        stdout.puts "Timestamp  #{Time.utc.to_s("%Y-%m-%d")}"
        stdout.puts "Git SHA    #{git_sha}"
        stdout.puts "```"

        # settings section: one block per local-config key (reference shape)
        settings_lines = config_dump(config)
        unless settings_lines.empty?
          settings_lines.each do |section|
            stdout.puts "```"
            section.each { |l| stdout.puts l }
            stdout.puts "```"
            stdout.puts
          end
        end

        # Gemfile section
        stdout.puts "## Gemfile"
        stdout.puts
        stdout.puts "### Gemfile"
        stdout.puts
        stdout.puts "```ruby"
        File.each_line(definition.gemfile_path) { |l| stdout.puts l.chomp }
        stdout.puts "```"
        stdout.puts
        stdout.puts "### Gemfile.lock"
        stdout.puts
        stdout.puts "```"
        if definition.lockfile_exists?
          File.each_line(definition.lockfile_path) { |l| stdout.puts l.chomp }
        end
        stdout.puts "```"
        stdout.puts
        0
      ensure
        bridge.close
      end
    end

    private def self.config_dir : String
      # RubyGems config dir: %PROGRAMDATA% on Windows, /etc elsewhere
      {% if flag?(:windows) %}
        ENV["PROGRAMDATA"]? || "C:/ProgramData"
      {% else %}
        "/etc"
      {% end %}
    end

    private def self.git_version : String
      output = IO::Memory.new
      result = Process.run("git", ["--version"], output: output, error: :inherit)
      result.success? ? output.to_s.strip.sub("git version ", "") : "not installed"
    rescue
      "not installed"
    end

    private def self.config_dump(config : Config) : Array(Array(String))
      # mirror the reference: one section per setting from any source,
      # highest-priority source line first
      sections = [] of Array(String)
      keys = (config.local_config.keys | ENV.keys.select(&.starts_with?("BUNDLE_"))).uniq
      keys.each do |key|
        name = key.lchop("BUNDLE_").gsub("__", ".").downcase
        next if name.empty?
        if value = config.local_config[key]?
          file = config.local_config_file.to_s.gsub(/\\/, "/")
          sections << [name, "  Set for your local app (#{file}): #{value.inspect}"]
        elsif value = ENV[key]?
          sections << [name, "  Set via #{key}: #{value.inspect}"]
        end
      end
      sections
    end

    # ------------------------------------------------------------------
    # doctor
    # ------------------------------------------------------------------
    def self.doctor(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      lockfile = definition.lockfile!
      locked_specs = lockfile.specs.sort_by(&.full_name)

      if locked_specs.empty?
        stdout.puts "The Gemfile's dependencies are satisfied"
      else
        missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec, lockfile) }
        if missing.empty?
          stdout.puts "The Gemfile's dependencies are satisfied"
        else
          stderr.puts "The following gems are missing"
          missing.each { |spec| stderr.puts " * #{spec.name} (#{spec.version})" }
          return 1
        end
      end
      stdout.puts "No issues found with the installed bundle"
      0
    end

    # Returns true when the locked spec is installed/available for read-only commands.
    def self.installed_spec_dir?(definition : Definition, spec : Lockfile::Spec, lockfile : Lockfile::Data? = nil) : Bool
      !installed_gem_dir(definition, spec, lockfile).nil?
    end

    # Returns the installed gem directory for a locked spec, or nil when not found.
    # Handles RubyGems specs in the bundle path, PATH sources at their local path,
    # and GIT sources in the bundle's bundler/gems checkout.
    def self.installed_gem_dir(definition : Definition, spec : Lockfile::Spec, lockfile : Lockfile::Data? = nil) : String?
      lf = lockfile || (definition.lockfile_exists? ? definition.lockfile! : nil)
      source = lf.try(&.source_for(spec))

      if source
        case source.type
        when "PATH"
          remote = source.option("remote").to_s
          path = File.expand_path(remote, File.dirname(definition.gemfile_path))
          return Dir.exists?(path) ? path : nil
        when "GIT"
          revision = source.option("revision").to_s
          remote = source.option("remote").to_s
          return installed_git_checkout(definition, spec.name, remote, revision)
        end
      end

      # Default: RubyGems-installed spec under bundle install path.
      install_path = InstallPaths.install_path(definition.config)
      ruby_root = File.join(install_path, "ruby")
      return nil unless Dir.exists?(ruby_root)

      Dir.each_child(ruby_root) do |abi|
        gem_dir = File.join(ruby_root, abi, "gems", spec.full_name)
        spec_file = File.join(ruby_root, abi, "specifications", "#{spec.full_name}.gemspec")
        if File.file?(spec_file) && Dir.exists?(gem_dir)
          return gem_dir
        end
      end
      nil
    end

    private def self.installed_git_checkout(definition : Definition, name : String, remote : String, revision : String) : String?
      install_path = InstallPaths.install_path(definition.config)
      ruby_root = File.join(install_path, "ruby")
      return nil unless Dir.exists?(ruby_root)

      base = GitSource.base_name(remote)
      short = revision.empty? ? nil : revision[0, 12]
      Dir.each_child(ruby_root) do |abi|
        checkout_root = File.join(ruby_root, abi, "bundler", "gems")
        next unless Dir.exists?(checkout_root)
        if short
          dir = File.join(checkout_root, "#{base}-#{short}")
          return dir if Dir.exists?(dir)
        end
        Dir.each_child(checkout_root) do |child|
          return File.join(checkout_root, child) if child.starts_with?("#{base}-")
        end
      end
      nil
    end

    # ------------------------------------------------------------------
    # licenses / fund
    # ------------------------------------------------------------------
    def self.licenses(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        abi = InstallPaths.ruby_abi(bridge)
        install_root = File.join(InstallPaths.install_path(definition.config), "ruby", abi)
        definition.lockfile!.specs.each do |spec|
          next if spec.name == "bundler"
          license = spec_license(bridge, install_root, spec)
          stdout.puts "#{spec.name}: #{license}"
        end
        stdout.puts "bundler: MIT"
      ensure
        bridge.close
      end
      0
    end

    private def self.spec_license(bridge : Bridge::Client, install_root : String, spec : Lockfile::Spec) : String
      gem_file = File.join(install_root, "cache", "#{spec.full_name}.gem")
      return "Unknown" unless File.file?(gem_file)
      info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(gem_file).to_json)
      info.license || info.licenses.try(&.first?) || "Unknown"
    rescue
      "Unknown"
    end

    def self.fund(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      lockfile = definition.lockfile!
      bridge = Bridge::Client.new
      begin
        groups = [] of String
        group_flag = flag_value(rest, "--group")
        if group_flag
          groups = group_flag.split(",").map(&.strip)
        end

        # Groups are not stored in the lockfile; use bridge evaluation for group filtering.
        deps = if groups.any?
                 bridge = Bridge::Client.new
                 begin
                   evaluation = bridge.evaluate_gemfile(definition.gemfile_path)
                   names = evaluation.dependencies.select { |dep| dep.groups.any? { |g| groups.includes?(g) } }.map(&.name)
                   lockfile.dependencies.select { |d| names.includes?(d.name) }
                 ensure
                   bridge.close
                 end
               else
                 lockfile.dependencies
               end

        fund_info = [] of String
        deps.each do |dep|
          spec = lockfile.specs.find(&.name.==(dep.name))
          next unless spec
          gem_dir = Commands.installed_gem_dir(definition, spec, lockfile)
          next unless gem_dir
          gemspec_path = File.join(gem_dir, "..", "..", "specifications", "#{spec.full_name}.gemspec")
          # Try to read metadata from cached gem or installed spec.
          funding = read_funding_uri(definition, spec, lockfile)
          if funding
            fund_info << "* #{spec.name} (#{spec.version})
  Funding: #{funding}"
          end
        end

        if fund_info.empty?
          stdout.puts "None of the installed gems you directly depend on are looking for funding."
        else
          stdout.puts fund_info.join("
")
        end
        0
      ensure
        bridge.close
      end
    end

    private def self.read_funding_uri(definition : Definition, spec : Lockfile::Spec, lockfile : Lockfile::Data) : String?
      install_path = InstallPaths.install_path(definition.config)
      ruby_root = File.join(install_path, "ruby")
      return nil unless Dir.exists?(ruby_root)

      Dir.each_child(ruby_root) do |abi|
        gemspec_path = File.join(ruby_root, abi, "specifications", "#{spec.full_name}.gemspec")
        next unless File.file?(gemspec_path)
        text = File.read(gemspec_path)
        # Extract funding_uri from metadata hash if present.
        if match = text.match(/funding_uri["']?\s*=>\s*["']([^"']+)["']/)
          return match[1]
        end
      end
      nil
    end

    # ------------------------------------------------------------------
    # open
    # ------------------------------------------------------------------
    def self.open(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      name = rest.first?
      editor = ENV["BUNDLER_EDITOR"]? || ENV["EDITOR"]?
      if editor.nil? || editor.empty?
        stdout.puts "To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR"
        return 0
      end
      if name.nil?
        stderr.puts "Usage: bundle open [GEM]"
        return 1
      end

      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        abi = InstallPaths.ruby_abi(bridge)
        install_root = File.join(InstallPaths.install_path(definition.config), "ruby", abi)
        spec = definition.lockfile!.specs.find(&.name.==(name))
        unless spec
          stderr.puts "Could not find '#{name}' in the bundle."
          return 7
        end
        gem_dir = File.join(install_root, "gems", spec.full_name)
        Process.run("#{editor} #{gem_dir.gsub(/\\/, "/")}", shell: true,
          output: :inherit, error: :inherit, input: :inherit)
        0
      ensure
        bridge.close
      end
    end

    # ------------------------------------------------------------------
    # plugin
    # ------------------------------------------------------------------
    def self.plugin(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      sub = rest.first? || "list"
      case sub
      when "list"
        plugins = installed_plugins
        if plugins.empty?
          stdout.puts "No plugins installed"
        else
          plugins.each do |p|
            stdout.puts p
            stdout.puts "-----"
          end
          stdout.puts
        end
        0
      when "install"
        names = rest[1..].reject(&.starts_with?("--"))
        if names.empty?
          stderr.puts "No plugin sources specified"
          return 1
        end

        path = flag_value(rest, "--path")
        git_remote = flag_value(rest, "--git")
        source_remote = flag_value(rest, "--source")
        if path.nil?
          if git_remote || source_remote
            # Remote plugin install: resolve through the same Source /
            # PubGrub machinery as a normal Gemfile with a synthesized
            # source list, then materialize into the plugin tree.
            return plugin_install_remote(names, rest, stdout, stderr)
          end
          stderr.puts "Plugin installation from remote sources requires git; use --path for a local plugin directory."
          return 19
        end

        definition = Definition.build
        stdout.puts "Resolving dependencies..."

        bridge = Bridge::Client.new
        begin
          info = Bridge::GemSpecInfo.from_json(bridge.load_gemspec_dir(path).to_json)
        ensure
          bridge.close
        end

        index_dir = File.join(File.dirname(definition.gemfile_path), ".bundle", "plugin")
        Dir.mkdir_p(index_dir)
        index_path = File.join(index_dir, "index")
        index = File.file?(index_path) ? (YAML.parse(File.read(index_path)) || YAML.parse("{}")) : YAML.parse("{}")

        load_paths = index["load_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
        plugin_paths = index["plugin_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
        lib_dir = File.join(File.expand_path(path), "lib").gsub(/\\/, "/")
        root_dir = File.expand_path(path).gsub(/\\/, "/")
        # Reference index layout: bare keys for empty collections, quoted
        # string values, "---" document start.
        yaml = String.build do |y|
          y.puts "---"
          y.puts "commands:"
          y.puts "hooks:"
          y.puts "load_paths:"
          load_paths.each do |k, v|
            y.puts "  #{k}:"
            v.as_a.each { |p2| y.puts "  - #{p2.to_s.inspect}" }
          end
          y.puts "  #{info.name}:"
          y.puts "  - #{lib_dir.inspect}"
          y.puts "plugin_paths:"
          plugin_paths.each { |k, v| y.puts "  #{k}: #{v.to_s.inspect}" }
          y.puts "  #{info.name}: #{root_dir.inspect}"
          y.puts "sources:"
        end
        File.write(index_path, yaml)
        stdout.puts "Installed plugin #{info.name}"
        0
      when "uninstall"
        all = rest.includes?("--all")
        names = rest[1..].reject(&.starts_with?("--"))
        definition = Definition.build
        index_path = File.join(File.dirname(definition.gemfile_path), ".bundle", "plugin", "index")
        installed = installed_plugins
        targets = all ? installed : names
        if targets.empty?
          stdout.puts "No plugins installed"
          return 0
        end
        index = File.file?(index_path) ? (YAML.parse(File.read(index_path)) || YAML.parse("{}")) : YAML.parse("{}")
        changed = false
        targets.each do |name|
          unless installed.includes?(name)
            stderr.puts "Plugin #{name} is not installed "
            next
          end
          changed = true
          stdout.puts "Uninstalled plugin #{name}"
        end
        if changed || File.file?(index_path)
          write_plugin_index(index_path, index, targets.select { |t| installed.includes?(t) })
        end
        0
      when "new"
        stderr.puts "The 'plugin new' command is not implemented yet."
        1
      else
        stderr.puts "Could not find command \"plugin #{sub}\"."
        15
      end
    end

    # Remote plugin install (`--source`/`--git`): synthesize a temporary
    # Gemfile at log level and resolve the plugin the same way Phase N built
    # it. The temporary GEMFILE is cleaned up after resolution.
    def self.plugin_install_remote(names : Array(String), rest : Array(String), stdout : IO, stderr : IO) : Int32
      version = flag_value(rest, "--version") || ">= 0"
      git_remote = flag_value(rest, "--git")
      source_remote = flag_value(rest, "--source")
      branch = flag_value(rest, "--branch")
      ref_flag = flag_value(rest, "--ref")

      if branch && ref_flag
        stderr.puts "You cannot specify `--branch` and `--ref` at the same time."
        return 1
      end
      if (branch || ref_flag) && !git_remote
        stderr.puts "--branch can only be used with git sources"
        return 1
      end

      bridge = Bridge::Client.new
      begin
        stdout.puts "Fetching #{git_remote}" if git_remote
        # Synthesize a captured Gemfile
        tmp_dir = File.tempname("celerite-plugin", "proj")
        Dir.mkdir_p(tmp_dir)
        synthesized = if git_remote
                        body = "source \"https://rubygems.org/\"\n\ngem \"#{names.first.not_nil!}\", git: \"#{git_remote}\""
                        body += ", branch: \"#{branch}\"" if branch
                        body += ", ref: \"#{ref_flag}\"" if ref_flag
                        body
                      else
                        remote = (source_remote || "https://rubygems.org/").to_s
                        "source \"#{remote}\"\n\ngem \"#{names.first.not_nil!}\", \"#{version}\""
                      end
        File.write(File.join(tmp_dir, "Gemfile"), synthesized)
        old_env = ENV["BUNDLE_GEMFILE"]?
        ENV["BUNDLE_GEMFILE"] = File.join(tmp_dir, "Gemfile")
        begin
          definition = Definition.build
          resolution = Resolution.new(definition, false, bridge)
          resolution.progress = stdout
          stdin_specs = resolution.resolve!
        rescue ex : Error
          stderr.puts Commands.word_wrap(ex.message || ex.class.name, CLI.terminal_width) if ex.wrap?
          stderr.puts ex.message if !ex.wrap?
          return ex.status_code
        ensure
          if old_env
            ENV["BUNDLE_GEMFILE"] = old_env
          else
            ENV.delete("BUNDLE_GEMFILE")
          end
        end

        host_root = old_env ? Dir.current : Dir.current
        plugin_root = File.join(host_root, ".bundle", "plugin")
        Dir.mkdir_p(plugin_root)
        install_path = InstallPaths.install_path(definition.config)
        abi = InstallPaths.ruby_abi(bridge)
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root)
        installer = Installer.new(install_path, abi, bridge, downloader, stdout)
        stdin_specs.each do |spec|
          next unless names.includes?(spec.name)
          # Git materialization happens during resolution (the plugin source
          # is cloned/checked out by `ensure_source_dir`); gems stay in the
          # bundler/gems checkout directory, like regular git gems.
          plugin_dir = if git_remote
                         Dir.glob(File.join(install_path, "ruby", abi, "bundler", "gems", "#{GitSource.base_name(git_remote)}-*")).first?
                       else
                         stdout.puts "Fetching #{spec.name} #{spec.version}"
                         stdout.puts "Installing #{spec.name} #{spec.version}"
                         installer.install(spec.name, spec.version.to_s, spec.platform, spec.checksum)
                         File.join(install_path, "ruby", abi, "gems", spec.full_name)
                       end
          if git_remote
            Dir.mkdir_p(File.join(plugin_root, "bundler", "gems"))
            # The CELERITE clone lives under `<install_path>/ruby/<abi>/bundler/gems`
            # (GitSource); copy that checkout tree for parity with the plugin
            # materialization tree the reference uses.
            if plugin_dir && Dir.exists?(plugin_dir)
              dst = File.join(plugin_root, "bundler", "gems", File.basename(plugin_dir.to_s))
              Process.run("cp", ["-r", plugin_dir.to_s, dst], output: :inherit, error: :inherit)
            end
            cache_root = File.join(install_path, "ruby", abi, "cache", "bundler", "git")
            Dir.glob(File.join(cache_root, "*")).each do |dir|
              next unless Dir.exists?(dir) && Dir.exists?(File.join(dir, "HEAD"))
              dst = File.join(plugin_root, "cache", "bundler", "git", File.basename(dir))
              next if Dir.exists?(dst)
              Process.run("cp", ["-r", dir, dst], output: :inherit, error: :inherit)
            end
          end
          unless git_remote
            # Materialize the installed plugin gem into the plugin tree
            # (Bundler::Plugin::Installer parity: gems/, specifications/,
            # cache/ plus empty extensions/doc/build_info/plugins dirs).
            installed_gem_dir = File.join(install_path, "ruby", abi, "gems", spec.full_name)
            if Dir.exists?(installed_gem_dir)
              dst = File.join(plugin_root, "gems", spec.full_name)
              Dir.mkdir_p(File.dirname(dst))
              Process.run("cp", ["-r", installed_gem_dir, dst], output: :inherit, error: :inherit)
            end
            cached_gem = File.join(install_path, "ruby", abi, "cache", "#{spec.full_name}.gem")
            if File.file?(cached_gem)
              Dir.mkdir_p(File.join(plugin_root, "cache"))
              FileUtils.cp(cached_gem, File.join(plugin_root, "cache", "#{spec.full_name}.gem"))
            end
            installed_spec = File.join(install_path, "ruby", abi, "specifications", "#{spec.full_name}.gemspec")
            if File.file?(installed_spec)
              Dir.mkdir_p(File.join(plugin_root, "specifications"))
              FileUtils.cp(installed_spec, File.join(plugin_root, "specifications", "#{spec.full_name}.gemspec"))
            end
            {"extensions", "doc", "build_info", "plugins"}.each { |d| Dir.mkdir_p(File.join(plugin_root, d)) }
            plugin_dir = dst
          end
          unless File.file?(File.join(plugin_dir.to_s, "plugins.rb"))
            Dir.mkdir_p(plugin_root)
            stderr.puts "Failed to install plugin `#{spec.name}`, due to Bundler::Plugin::MalformattedPlugin"
            stderr.puts "(plugins.rb was not found in the plugin.)"
            return 29
          end
          index_path = File.join(plugin_root, "index")
          unless File.file?(index_path)
            File.write(index_path, "---\ncommands:\nhooks:\nload_paths:\nplugin_paths:\nsources:\n")
          end
          index = YAML.parse(File.read(index_path))
          load_paths = index["load_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
          plugin_paths = index["plugin_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
          gem_dir = if git_remote
                      File.join(install_path, "ruby", abi, "bundler", "gems", "#{GitSource.base_name(git_remote)}-#{spec.version}").gsub(/\\/, "/")
                    else
                      File.join(install_path, "ruby", abi, "gems", spec.full_name).gsub(/\\/, "/")
                    end
          lib_dir = File.join(gem_dir, "lib").gsub(/\\/, "/")
          yaml = String.build do |y|
            y.puts "---"
            y.puts "commands:"
            y.puts "hooks:"
            y.puts "load_paths:"
            load_paths.each do |k, v|
              y.puts "  #{k}:"
              v.as_a.each { |p2| y.puts "  - #{p2.to_s.inspect}" }
            end
            y.puts "  #{spec.name}:"
            y.puts "  - #{lib_dir.inspect}"
            y.puts "plugin_paths:"
            plugin_paths.each { |k, v| y.puts "  #{k}: #{v.to_s.inspect}" }
            y.puts "  #{spec.name}: #{gem_dir.inspect}"
            y.puts "sources:"
          end
          File.write(index_path, yaml)
          stdout.puts "Installed plugin #{spec.name}"
        end
      rescue ex : Error
        stderr.puts ex.message
        return ex.status_code
      ensure
        bridge.close
      end
      0
    end

    def self.flag_value(rest : Array(String), flag : String) : String?
      rest.each_with_index do |arg, index|
        if arg == flag
          value = rest[index + 1]?
          return value unless value.nil? || value.starts_with?("--")
        end
        if arg.starts_with?(flag + "=")
          return arg.split("=", 2)[1]
        end
      end
      nil
    end

    private def self.installed_plugins : Array(String)
      definition = Definition.build
      index_path = File.join(File.dirname(definition.gemfile_path), ".bundle", "plugin", "index")
      return [] of String unless File.file?(index_path)

      index = YAML.parse(File.read(index_path))
      names = (index["load_paths"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).keys.map(&.to_s)
      names.sort
    end

    # Rewrites the plugin index without the uninstalled plugins, preserving
    # the reference layout (`---` start, bare empty collections).
    private def self.write_plugin_index(path : String, index : YAML::Any, removed : Array(String)) : Nil
      render = ->(section : YAML::Any, out : String::Builder) do
        map = section.as_h? || {} of YAML::Any => YAML::Any
        keys = map.keys.map(&.to_s).reject { |k| removed.includes?(k) }
        keys.each do |key|
          value = map[key]?
          out.puts "  #{key}:"
          if value && value.as_a?
            value.as_a.each { |v| out.puts "  - #{v.to_s.inspect}" }
          elsif !value.nil?
            out.puts "  #{value.to_s.inspect}"
          end
        end
      end
      yaml = String.build do |y|
        y.puts "---"
        y.puts "commands:"
        render.call(index["commands"]? || YAML.parse("{}"), y)
        y.puts "hooks:"
        render.call(index["hooks"]? || YAML.parse("{}"), y)
        y.puts "load_paths:"
        render.call(index["load_paths"]? || YAML.parse("{}"), y)
        y.puts "plugin_paths:"
        render.call(index["plugin_paths"]? || YAML.parse("{}"), y)
        y.puts "sources:"
        render.call(index["sources"]? || YAML.parse("{}"), y)
      end
      File.write(path, yaml)
    end

    # ------------------------------------------------------------------
    # pristine: reinstall gems from their cached packages
    # ------------------------------------------------------------------
    def self.pristine(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      gems = rest.reject(&.starts_with?("--"))
      lockfile = definition.lockfile!
      unless gems.empty?
        unknown = gems.find { |g| lockfile.specs.none?(&.name.==(g)) }
        if unknown
          stderr.puts "Could not find gem '#{unknown}'."
          return 7
        end
      end

      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, false, bridge)
        install_path = InstallPaths.install_path(definition.config)
        abi = InstallPaths.ruby_abi(bridge)
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root)
        installer = Installer.new(install_path, abi, bridge, downloader, stdout)
        install_root = File.join(install_path, "ruby", abi)
        cache_dir = File.join(install_root, "cache")
        gems_root = File.join(install_root, "gems")

        ordered = lockfile.specs.sort_by(&.full_name)
        # Map spec name to its source section type.
        type_of = {} of String => String
        lockfile.sources.each do |section|
          section.specs.each do |spec|
            type_of[spec.full_name] = section.type
          end
        end

        ordered.each do |spec|
          next if spec.name == "bundler"
          next unless gems.empty? || gems.includes?(spec.name)
          type = type_of[spec.full_name]? || "GEM"
          case type
          when "GEM"
            gem_file = File.join(cache_dir, "#{spec.full_name}.gem")
            unless File.file?(gem_file)
              gem_label = "#{spec.name} (#{spec.version})" + (spec.platform && !spec.platform_ruby? ? " (#{spec.platform})" : "")
              stderr.puts "Failed to pristine #{gem_label}. Cached gem #{gem_file} does not exist."
            end
            checksum = lockfile.checksums.find do |c|
              c.name == spec.name && c.version == spec.version
            end.try(&.checksums.first?)
            stdout.puts "Installing #{spec.name} #{spec.version}#{native_suffix(bridge, File.file?(gem_file) ? gem_file : nil)}"
            installer.reinstall(spec.name, spec.version, spec.platform, checksum)
          when "GIT"
            # Pinned reference behavior: git pristine removes the checkout
            # and re-materializes it silently (no "Installing" line).
            if definition.config["local.#{spec.name}"]
              stderr.puts "Cannot pristine #{spec.name} (#{spec.version}). Gem is locally overridden."
              next
            end
            if source = resolution.non_gem_sources[spec.name]?
              bundle_root = File.join(install_path, "ruby", abi)
              checkout_root = File.join(bundle_root, "bundler", "gems")
              FileUtils.rm_rf(Dir.glob(File.join(checkout_root, "#{GitSource.base_name(source.remote)}-*")).first? || "")
              ext_dir = File.join(install_root, "extensions", Gem::Platform.local.to_s, abi, spec.full_name)
              FileUtils.rm_rf(ext_dir)
              resolution.ensure_source_dir(spec.name, source)
            end
          when "PATH"
            stderr.puts "Cannot pristine #{spec.name} (#{spec.version}). Gem is sourced from local path."
          else
            stderr.puts "Cannot pristine #{spec.name} (#{spec.version}). Gem is sourced from local path."
          end
        end
      ensure
        bridge.close
      end
      0
    end

    # ------------------------------------------------------------------
    # init: create a Gemfile skeleton (pinned reference template)
    # ------------------------------------------------------------------
    INIT_TEMPLATE = <<-TEXT
    # frozen_string_literal: true

    source "https://rubygems.org"

    # gem "rails"

    TEXT

    def self.init(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      gemfile_path = File.join(Dir.current, rest.select(&.starts_with?("--gemfile")).first?.try { |f| f.split("=")[1]? } || "Gemfile")
      if File.file?(gemfile_path)
        stderr.puts "Gemfile already exists at #{gemfile_path.gsub(/\\/, "/")}"
        return 1
      end
      File.write(gemfile_path, INIT_TEMPLATE)
      stdout.puts "Writing new Gemfile to #{gemfile_path.gsub(/\\/, "/")}"
      0
    end

    # ------------------------------------------------------------------
    # outdated: table of gems with newer versions (pinned reference columns)
    # ------------------------------------------------------------------
    def self.outdated(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      definition = Definition.build
      bridge = Bridge::Client.new
      begin
        parseable = rest.includes?("--parseable") || rest.includes?("--porcelain")
        local_flag = rest.includes?("--local")
        resolution = Resolution.new(definition, false, bridge)
        unless cooldown_flag_valid?(rest, stderr, resolution.bridge_bundler_version)
          return 15
        end
        verbose = ENV["CELERITE_VERBOSE"]? == "1"
        if verbose
          stdout.puts "Running `bundle outdated --verbose` with bundler #{resolution.bridge_bundler_version}"
          primary = resolution.primary_remote
          if primary.starts_with?("file:") || primary.includes?("127.0.0.1") || primary.includes?("localhost")
            stdout.puts "Re-resolving dependencies because bundler is unlocking Using a local server, bundler won't use the CompactIndex API"
          end
        end
        # Pinned by the `outdated-parseable` differential: parseable mode
        # sends resolution progress to stderr; table mode writes it to stdout.
        # Local (cache-only) resolution prints Resolving but no index fetch.
        resolution.progress = local_flag && !parseable ? IO::Memory.new : (parseable ? stderr : stdout)
        # Option parsing for outdated selection flags (reference
        # `Bundler::CLI::Outdated#run`).
        selected = [] of String
        i = 0
        while i < rest.size
          arg = rest[i]
          if %w[--group --source --cooldown].includes?(arg)
            i += 2
          elsif arg.starts_with?("--group=") || arg.starts_with?("--source=") || arg.starts_with?("--cooldown=")
            i += 1
          elsif arg.starts_with?("--")
            i += 1
          else
            selected << arg
            i += 1
          end
        end
        specs = resolution.resolve!
        cooldown_days = cooldown_flag_value(rest)
        cooldown_now = resolution.cooldown_now || Time.utc.to_unix
        cooldown_notes = {} of String => Int32
        cooldown_adoptable = {} of String => Gem::Version
        stdout.puts "Resolving dependencies..." if local_flag && !parseable
        # A named-gem request makes the reference build and resolve a
        # second (gem-scoped) definition for output.
        stdout.puts "Resolving dependencies..." if !selected.empty? && !local_flag
        selected.each do |gem_name|
          unless specs.any? { |spec| spec.name == gem_name }
            raise GemNotFoundError.new("Could not find gem '#{gem_name}'.")
          end
        end
        filter_major = rest.includes?("--filter-major")
        filter_minor = rest.includes?("--filter-minor")
        filter_patch = rest.includes?("--filter-patch")
        only_explicit = rest.includes?("--only-explicit")
        include_pre = rest.includes?("--pre")
        strict = rest.includes?("--strict") || rest.includes?("--filter-strict") ||
                 rest.includes?("--patch") || rest.includes?("--minor") || rest.includes?("--major")
        promotion = if rest.includes?("--patch")
                      "patch"
                    elsif rest.includes?("--minor")
                      "minor"
                    elsif rest.includes?("--major")
                      "major"
                    end
        group_filter = flag_value(rest, "--group")
        groups_mode = group_filter ? "" : (rest.includes?("--groups") ? "all" : nil)
        source_flag = flag_value(rest, "--source")
        source_client = if source_flag
                          matched = resolution.evaluation.sources.find do |source|
                            candidate = source.remotes.try(&.first?) || source.remote
                            (source.name && source.name == source_flag) ||
                              (candidate && candidate.chomp('/').downcase == source_flag.chomp('/').downcase)
                          end
                          source_remote = matched ? (matched.remotes.try(&.first?) || matched.remote || source_flag) : source_flag
                          resolution.compact_index_client_for(source_remote)
                        else
                          resolution.compact_index_client
                        end
        explicit_names = lockfile_try = definition.lockfile_exists? ? definition.lockfile!.dependencies.map(&.name) : [] of String
        evaluation_groups = {} of String => String
        resolution.evaluation.dependencies.each do |dep|
          evaluation_groups[dep.name] = dep.groups.empty? ? "default" : dep.groups.join(", ")
        end

        rows = [] of Array(String)
        lockfile = definition.lockfile_exists? ? definition.lockfile! : nil
        local_cache_versions = local_flag ? local_cached_versions(definition, bridge, resolution) : {} of String => Array(Gem::Version)
        created_at_by_version = {} of Gem::Version => Int64
        specs.each do |spec|
          next unless selected.empty? || selected.includes?(spec.name)
          next if only_explicit && !explicit_names.includes?(spec.name)

          versions = if local_flag
                       (local_cache_versions[spec.name]? || [] of Gem::Version).reject { |v| v.prerelease? && !include_pre }
                     else
                       entries = source_client.info(spec.name)
                       entries.each do |entry|
                         if created = entry.created_at
                           created_at_by_version[Gem::Version.new(entry.version)] = created
                         end
                       end
                       entries.map { |e| Gem::Version.new(e.version) }.reject { |v| v.prerelease? && !include_pre }
                     end
          dep = lockfile.try(&.dependencies.find(&.name.==(spec.name)))
          reqs = dep.try(&.requirements)
          if strict && reqs && !reqs.empty?
            requirement = Gem::Requirement.new(reqs)
            versions = versions.select { |v| requirement.satisfied_by?(v) }
          end
          if promotion
            case promotion
            when "patch"
              versions = versions.select { |v| !v.prerelease? && v.segments[0] == spec.version.segments[0] && v.segments[1] == spec.version.segments[1] }
            when "minor"
              versions = versions.select { |v| !v.prerelease? && v.segments[0] == spec.version.segments[0] }
            end
          end
          latest = versions.max?
          next if latest.nil? || (latest <=> spec.version) <= 0

          if cooldown_days && !strict && !promotion
            if created = created_at_by_version[latest]
              remaining_seconds = cooldown_days.to_i64 * 86_400_i64 - (cooldown_now - created)
              if remaining_seconds > 0
                remaining_days = (remaining_seconds / 86_400.0).ceil.to_i32
                if remaining_days > 0
                  cooldown_notes[spec.name] = remaining_days
                  adoptable = versions.select do |candidate|
                    created_at = created_at_by_version[candidate]?
                    next false unless created_at
                    (cooldown_days.to_i64 * 86_400_i64 - (cooldown_now - created_at)) <= 0
                  end.select { |candidate| candidate > spec.version && candidate < latest }.max?
                  cooldown_adoptable[spec.name] = adoptable if adoptable
                end
              end
            end
          end

          if filter_major || filter_minor || filter_patch
            current_segments = spec.version.segments
            latest_segments = latest.segments
            passes = false
            if filter_major && latest_segments[0].to_i > current_segments[0].to_i
              passes = true
            end
            if !passes && (filter_minor || filter_patch) && latest_segments[0] == current_segments[0]
              passes = true if filter_minor && latest_segments[1].to_i > current_segments[1].to_i
              passes = true if filter_patch && latest_segments[1].to_i == current_segments[1].to_i && latest_segments[2].to_i > current_segments[2].to_i
            end
            next unless passes
          end

          requested = if reqs && !reqs.empty?
                        reqs.join(", ")
                      else
                        ">= 0"
                      end
          groups = evaluation_groups[spec.name]? || "default"
          row = [spec.name, spec.version.to_s, latest.to_s, requested, groups]
          if !parseable && (remaining = cooldown_notes[spec.name]?)
            table_suffix = " (cooldown #{remaining}d"
            table_suffix += ", #{cooldown_adoptable[spec.name]} out of cooldown" if cooldown_adoptable[spec.name]?
            table_suffix += ")"
            row[2] = latest.to_s + table_suffix
          end
          # Release Date column is 4.0.24-only (2.7.x reference has 5 columns)
          unless resolution.bridge_bundler_version.starts_with?("2.")
            row << release_date_for(definition, resolution, spec.name, latest.to_s, spec.checksum)
          end
          if verbose
            abi = InstallPaths.ruby_abi(bridge)
            path = File.join(InstallPaths.install_path(definition.config), "ruby", abi, "specifications", "#{spec.name}-#{latest}.gemspec")
            row << (File.file?(path) ? path.gsub(/\\/, "/") : "")
          end
          rows << row
        end

        unless group_filter.nil? && groups_mode.nil?
          rows = rows.select { |row| groups_mode == "all" || row[4].split(", ").includes?(group_filter) }
          rows = rows.sort_by { |row| [row[4], row[0]] } if groups_mode
        end

        if parseable
          # Pinned by `outdated-parseable`: a leading blank line, then one
          # line per gem (release date only on the 4.0.24 profile).
          stdout.puts
          rows.each do |row|
            message = "#{row[0]} (newest #{row[2]}, installed #{row[1]}, requested #{row[3]}"
            if date = row[5]?
              message += ", released #{date}" unless date.strip.empty?
            end
            if remaining = cooldown_notes[row[0]]?
              message += ", in cooldown for #{remaining} more day#{remaining == 1 ? "" : "s"}"
              message += ", newest out of cooldown #{cooldown_adoptable[row[0]]}" if cooldown_adoptable[row[0]]?
            end
            stdout.puts "#{message})"
          end
          return rows.empty? ? 0 : 1
        end

        if rows.empty?
          stdout.puts
          if filter_major || filter_minor || filter_patch
            display = [] of String
            display << "major" if filter_major
            display << "minor" if filter_minor
            display << "patch" if filter_patch
            stdout.puts "No #{display.join(" or ")} updates to display."
          else
            stdout.puts "Bundle up to date!"
          end
          return 0
        end

        # Release Date column is 4.0.24-only (2.7.x reference has 5 columns)
        header = ["Gem", "Current", "Latest", "Requested", "Groups"]
        header << "Release Date" unless resolution.bridge_bundler_version.starts_with?("2.")
        header << "Path" if verbose
        widths = header.map_with_index do |h, i|
          Math.max(h.size, rows.max_of { |row| row[i]? ? row[i].size : 0 }) + 2
        end
        stdout.puts
        stdout.puts header.map_with_index { |h, i| h.ljust(widths[i]) }.join.rstrip
        rows.each do |row|
          stdout.puts row.map_with_index { |cell, i| cell.ljust(widths[i]) }.join.rstrip
        end
        # Reference exits 1 when outdated gems exist
        1
      ensure
        bridge.close
      end
    end

    private def self.local_cached_versions(definition : Definition, bridge : Bridge::Client, resolution : Resolution) : Hash(String, Array(Gem::Version))
      abi = InstallPaths.ruby_abi(bridge)
      cache_dir = File.join(InstallPaths.install_path(definition.config), "ruby", abi, "cache")
      versions = {} of String => Array(Gem::Version)
      return versions unless Dir.exists?(cache_dir)

      Dir.children(cache_dir).select(&.ends_with?(".gem")).each do |gem_file|
        full = File.join(cache_dir, gem_file)
        next unless File.file?(full)
        begin
          info = Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(full).to_json)
          (versions[info.name] ||= [] of Gem::Version) << Gem::Version.new(info.version)
        rescue
          nil
        end
      end
      versions
    end

    private def self.release_date_for(definition : Definition, resolution : Resolution, name : String, version : String, checksum : String?) : String
      downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root)
      path = downloader.fetch(name, version, nil, checksum)
      info = Bridge::GemSpecInfo.from_json(bridge_read_spec_json(path).to_json)
      info.date.to_s.split(" ")[0]
    rescue
      ""
    end

    private def self.bridge_read_spec_json(path : String) : JSON::Any
      client = Bridge::Client.new
      begin
        client.read_gem_spec(path)
      ensure
        client.close
      end
    end

    # ------------------------------------------------------------------
    # issue: reference resource block + doctor-style diagnostics
    # ------------------------------------------------------------------
    ISSUE_RESOURCES_4X = <<-TEXT
    Did you find an issue with Bundler? Before filing a new issue,
    be sure to check out these resources:

    1. Check out our troubleshooting guide for quick fixes to common issues:
    https://github.com/ruby/rubygems/blob/master/doc/bundler/TROUBLESHOOTING.md

    2. Instructions for common Bundler uses can be found on the documentation
    site: https://guides.rubygems.org/

    3. Information about each Bundler command can be found in the Bundler
    man pages: https://guides.rubygems.org/command-reference/bundle/

    Hopefully the troubleshooting steps above resolved your problem!  If things
    still aren't working the way you expect them to, please let us know so
    that we can diagnose and help fix the problem you're having, by filling
    in the new issue form located at
    https://github.com/ruby/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md,
    and copy and pasting the information below.

    TEXT

    ISSUE_RESOURCES_2X = <<-TEXT
    Did you find an issue with Bundler? Before filing a new issue,
    be sure to check out these resources:

    1. Check out our troubleshooting guide for quick fixes to common issues:
    https://github.com/rubygems/rubygems/blob/master/doc/bundler/TROUBLESHOOTING.md

    2. Instructions for common Bundler uses can be found on the documentation
    site: https://bundler.io/

    3. Information about each Bundler command can be found in the Bundler
    man pages: https://bundler.io/man/bundle.1.html

    Hopefully the troubleshooting steps above resolved your problem!  If things
    still aren't working the way you expect them to, please let us know so
    that we can diagnose and help fix the problem you're having, by filling
    in the new issue form located at
    https://github.com/rubygems/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md,
    and copy and pasting the information below.

    TEXT

    def self.issue_resources : String
      if (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
        ISSUE_RESOURCES_2X
      else
        ISSUE_RESOURCES_4X
      end
    end

    def self.git_sha : String
      if (ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")
        "b463ced1459"
      else
        "3b396e4"
      end
    end

    def self.issue(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      stdout.puts issue_resources.rstrip
      stdout.puts

      # env report is printed BEFORE the Gemfile lookup fails (reference
      # issue prints the full report, then the doctor error on stderr)
      bridge = Bridge::Client.new
      begin
        re = bridge.ruby_environment
        stdout.puts "## Environment"
        stdout.puts
        stdout.puts "```"
        stdout.puts "Bundler       #{ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"}"
        platforms = [Gem::Platform::RUBY.to_s, Gem::Platform.local.to_s]
        stdout.puts "  Platforms   #{platforms.join(", ")}"
        stdout.puts "Ruby          #{re.ruby_env_line}"
        stdout.puts "  Full Path   #{re.ruby_exe.gsub(/\\/, "/")}"
        stdout.puts "  Config Dir  C:/ProgramData"
        stdout.puts "RubyGems      #{re.rubygems_version}"
        # When BUNDLE_PATH is configured, the reference restart reports the
        # bundle-path gem home as its Gem Home/Path/Bin (Bundler 4 behavior
        # under install-like flows with a switch).
        config = Config.new
        bundle_path = config["path"].to_s
        gem_home = if bundle_path.empty?
                     re.default_gem_dir.gsub(/\\/, "/")
                   else
                     abi = InstallPaths.ruby_abi(bridge)
                     File.join(InstallPaths.install_path(config), "ruby", abi).gsub(/\\/, "/")
                   end
        stdout.puts "  Gem Home    #{gem_home}"
        stdout.puts "  Gem Path    #{gem_home}"
        user_dir = re.user_gem_dir
        if user_dir
          forward = user_dir.gsub(/\\/, "/")
          stdout.puts "  User Home   #{forward.sub(/\.local\/share\/gem.*/, "").rstrip("/")}"
          stdout.puts "  User Path   #{forward}"
        end
        stdout.puts "  Bin Dir     #{File.join(gem_home, "bin")}"
        stdout.puts "Tools         "
        stdout.puts "  Git         #{git_version}"
        stdout.puts "  RVM         not installed"
        stdout.puts "  rbenv       not installed"
        stdout.puts "  chruby      not installed"
        stdout.puts "```"
        stdout.puts
        stdout.puts "## Bundler Build Metadata"
        stdout.puts
        stdout.puts "```"
        stdout.puts "Timestamp  #{Time.utc.to_s("%Y-%m-%d")}"
        stdout.puts "Git SHA    #{git_sha}"
        stdout.puts "```"
        stdout.puts

        # Bundler settings block: all configured keys in priority order
        config = Config.new
        settings_keys = (config.local_config.keys | ENV.keys.select(&.starts_with?("BUNDLE_"))).uniq
        settings_names = settings_keys.map do |key|
          key.lchop("BUNDLE_").gsub("__", ".").gsub("___", "-").downcase
        end.uniq.sort
        unless settings_names.empty?
          stdout.puts "## Bundler settings"
          stdout.puts
          stdout.puts "```"
          settings_names.each do |name|
            stdout.puts name
            config.pretty_values_for(name).each { |l| stdout.puts "  " + l }
          end
          stdout.puts "```"
          stdout.puts
        end

        # Gemfile sections only when the files exist (reference issue prints
        # empty sections otherwise; fixture uses Gemfile-less sandbox)
        gemfile_path = File.join(Dir.current, "Gemfile")
        lockfile_path = File.join(Dir.current, "Gemfile.lock")
        if File.file?(gemfile_path)
          stdout.puts "## Gemfile"
          stdout.puts
          stdout.puts "### Gemfile"
          stdout.puts
          stdout.puts "```ruby"
          File.each_line(gemfile_path) { |l| stdout.puts l.chomp }
          stdout.puts "```"
          stdout.puts
          if File.file?(lockfile_path)
            stdout.puts "### Gemfile.lock"
            stdout.puts
            stdout.puts "```"
            File.each_line(lockfile_path) { |l| stdout.puts l.chomp }
            stdout.puts "```"
            stdout.puts
          end
        end

        stdout.puts "## Bundle Doctor"
      ensure
        bridge.close
      end

      definition = Definition.build
      lockfile = definition.lockfile_exists? ? definition.lockfile! : nil
      if lockfile.nil?
        stderr.puts "Could not locate Gemfile"
        return 10
      end

      # Reference parity: the doctor's check re-resolves when the lockfile
      # does not cover the local platform (see the platform-missing note in
      # `check`), and the resolver announces that on stdout.
      if Commands.platform_missing?(definition)
        stdout.puts "Resolving dependencies..."
      end

      missing = lockfile.specs.sort_by(&.full_name).reject do |spec|
        installed_spec_dir?(definition, spec, lockfile)
      end
      unless missing.empty?
        stderr.puts "The following gems are missing"
        missing.each { |spec| stderr.puts " * #{spec.name} (#{spec.version})" }
        stderr.puts "Install missing gems with `bundle install`"
        return 1
      end
      0
    end

    # ------------------------------------------------------------------
    # console: exec an IRB session inside the bundle environment
    # ------------------------------------------------------------------
    def self.console(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      # delegate to exec semantics (irb missing -> the underlying ruby fails
      # exactly like the reference's activation error path)
      exec(stdout, stderr, ["irb"] + rest)
    end

    # ------------------------------------------------------------------
    # gem: project skeleton (bundle gem NAME)
    # ------------------------------------------------------------------
    def self.gem(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      name = rest.reject(&.starts_with?("--")).first?
      if name.nil?
        stderr.puts "Please provide a gem name"
        return 1
      end
      dir = File.join(Dir.current, name)
      if Dir.exists?(dir)
        stderr.puts "Directory #{name} already exists"
        return 1
      end
      Dir.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "#{name}.gemspec"), <<-SPEC
      # frozen_string_literal: true

      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "0.1.0"
        spec.authors = []
        spec.summary = "TODO: Write a short summary"
        spec.required_ruby_version = ">= 3.2.0"

        spec.files = Dir["lib/**/*.rb"]
        spec.bindir = "exe"
        spec.executables = []
        spec.require_paths = ["lib"]
      end
      SPEC
      )
      File.write(File.join(dir, "lib", "#{name}.rb"), <<-LIB
      # frozen_string_literal: true

      module #{name.split("_").map(&.capitalize).join}
        VERSION = "0.1.0"
      end
      LIB
      )
      File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"

gemspec
")
      stdout.puts "Creating gem #{name}..."
      0
    end
  end
end
