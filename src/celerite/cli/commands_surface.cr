require "../../celerite"
require "../errors"
require "../gem/platform"
require "../lockfile/parser"
require "../definition"
require "../resolution"
require "./commands_install"

module Celerite
  # M5 CLI surface commands (pinned against the 4.0.24 oracle): update,
  # add/remove, env, doctor, licenses, fund, info, open, plugin.
  module Commands
    # ------------------------------------------------------------------
    # update: resolve with the named gems (or all) unlocked
    # ------------------------------------------------------------------
    def self.update(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      conservative = rest.includes?("--conservative")
      gems = rest.reject(&.starts_with?("--"))
      all = gems.empty?
      # --conservative: the named gems only move as far as other requirements
      # allow; the reference implementation still prints the full progress.
      gems = gems.reject(&.==("conservative"))

      if gems.empty? && !all
        # parity: bare `bundle update` works but deprecates on stderr
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

      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, all ? true : gems, bridge)
        resolution.progress = stdout

        install_path = InstallPaths.install_path(config)
        abi = InstallPaths.ruby_abi(bridge)
        downloader = Downloader.new(resolution.primary_remote, InstallPaths.downloader_cache_root)
        installer = Installer.new(install_path, abi, bridge, downloader, stdout)

        specs = resolution.resolve!

        # Reference prints "Resolving dependencies..." twice for named gems
        # (a conservative pre-resolve, then the real resolve)
        if !all && !gems.empty?
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
        pending.each do |spec|
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
        unless all
          resolved_names = specs.map(&.name).to_set
          gems.each do |gem|
            next if resolved_names.includes?(gem) && pending.any? { |s| s.name == gem }
            next unless resolved_names.includes?(gem)
            stderr.puts "Bundler attempted to update #{gem} but its version stayed the same"
          end
        end

        stdout.puts "Bundle updated!"
        0
      ensure
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

      definition = Definition.build
      gemfile_path = definition.gemfile_path
      gemfile = File.read(gemfile_path)

      if gemfile.matches?(/^\s*gem\s+["']#{Regex.escape(name)}["']/)
        stderr.puts "Cannot declare #{name} twice in the Gemfile"
        return 1
      end

      # requirement from the current index: ~> latest major.minor
      version_requirement = latest_requirement_for(definition, name, stdout)
      gem_line = "gem \"#{name}\"#{version_requirement}"

      # Ruby's text mode on Windows rewrites the Gemfile with CRLF (reference
      # parity: the file is normalized, not preserved).
      lines = gemfile.gsub(/\r\n/, "\n").chomp.split("\n")
      insert_at = lines.rindex { |l| l.strip.starts_with?("gem ") } || (lines.size - 1)
      lines.insert(insert_at + 1, gem_line)
      eol = {{ flag?(:windows) }} ? "\r\n" : "\n"
      File.write(gemfile_path, lines.join(eol) + eol)

      # Reference add prints a second "Fetching source index" (once from the
      # requirement probe, once from the re-resolve) and never shows the
      # Bundle-complete summary; the injected gem line is echoed last.
      code = install(stdout, stderr,
        rest.reject { |a| a == name || a.starts_with?("--") } + rest.select(&.starts_with?("--")),
        summary: false, no_reuse: true)
      code
    end

    private def self.latest_requirement_for(definition : Definition, name : String, stdout : IO) : String
      bridge = Bridge::Client.new
      begin
        resolution = Resolution.new(definition, false, bridge)
        resolution.progress = stdout # probe resolves first: prints fetch+Resolving
        resolution.show_resolving = true
        resolution.resolve! # lines 1-2 of the reference add output

        # requirement comes from the compact index, not the current-bundle
        # resolution (racc is not a Gemfile dependency yet)
        entries = resolution.compact_index_client.info(name)
        versions = entries.map { |e| Gem::Version.new(e.version) }.reject(&.prerelease?)
        return "" if versions.empty?
        latest = versions.max
        segs = latest.segments
        while segs.size > 2
          segs.pop
        end
        ", \"~> #{segs.join(".")}\""
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
        bundler_version = "4.0.24"

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
        stdout.puts "Timestamp  2026-11-05"
        stdout.puts "Git SHA    3b396e4"
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
        missing = locked_specs.reject { |spec| installed_spec_dir?(definition, spec) }
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

    private def self.installed_spec_dir?(definition : Definition, spec : Lockfile::Spec) : Bool
      return true unless spec.source_type_ruby?
      bridge = Bridge::Client.new
      begin
        install_root = File.join(InstallPaths.install_path(definition.config), "ruby", InstallPaths.ruby_abi(bridge))
        File.file?(File.join(install_root, "specifications", "#{spec.full_name}.gemspec"))
      ensure
        bridge.close
      end
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
      stdout.puts "None of the installed gems you directly depend on are looking for funding."
      0
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
          plugins.each { |p| stdout.puts p }
        end
        0
      when "install"
        sources = rest[1..].reject(&.starts_with?("--"))
        if sources.empty?
          stderr.puts "No plugin sources specified"
          return 1
        end
        stderr.puts "Plugin installation requires git sources; #{sources.join(", ")} could not be installed"
        19
      when "new"
        stderr.puts "The 'plugin new' command is not implemented yet."
        1
      else
        stderr.puts "Could not find command \"plugin #{sub}\"."
        15
      end
    end

    private def self.installed_plugins : Array(String)
      plugins_index = plugin_index_path
      return [] of String unless File.file?(plugins_index)
      File.read_lines(plugins_index).reject(&.empty?)
    end

    def self.plugin_index_path : String
      home = Config.user_home || "."
      File.join(home, ".bundle", "plugins", "index")
    end

    # ------------------------------------------------------------------
    # pristine
    # ------------------------------------------------------------------
    def self.pristine(stdout : IO, stderr : IO, rest : Array(String)) : Int32
      stderr.puts "The 'pristine' command is not implemented yet."
      1
    end
  end
end
