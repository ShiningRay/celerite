require "./glob"
require "./eval_fingerprint"
require "./profile"
require "./resolution"

module Celerite
  # Runtime facts reconstructed without starting Ruby (M8 slice S8a, roadmap
  # L164).
  #
  # The zero-Ruby fast path must know seven runtime fields before it decides
  # anything, because `EvalFingerprint::Runtime` (`eval_fingerprint.cr:96-109`)
  # keys the evaluation cache on them. Asking Ruby for them would defeat the
  # point, so this module reads them from the interpreter's own build files:
  #
  # * `<root>/lib/ruby/<lib version>/<arch>/rbconfig.rb` — `MAJOR`/`MINOR`/
  #   `TEENY`/`PATCHLEVEL`/`arch`/`libdir`/`rubylibprefix`;
  # * `<root>/lib/ruby/<lib version>/rubygems.rb` — the `Gem::VERSION`
  #   literal;
  # * the compiled-in reference Bundler version (`Profile.bundler_version`).
  #
  # `rbconfig.rb` is not a data file: `CONFIG` values may reference each other
  # as `$(...)`, `TOPDIR` is computed from the file's own location, and the
  # file contains comments and `raise` guards. The parser therefore only
  # accepts the literal `CONFIG["key"] = "value"` shape, expands `$(...)`
  # recursively, and substitutes `TOPDIR` from the rbconfig path.
  #
  # Two fields are genuinely absent from the tree: `engine` and
  # `engine_version` are compile-time constants of the running interpreter and
  # are not written into rbconfig. They stay `Source::Unknown`, and
  # `Facts#matches?` treats any unknown field as a mismatch (never as a
  # wildcard), so a caller that only has `Facts` always falls back to the
  # compatibility path for those two. Cross-checking against the runtime record
  # written by the last bridge run (`assets/bridge/server.rb`'s
  # `op_ruby_environment`) is the caller's job; this module deliberately
  # cannot claim a match it cannot prove.
  #
  # `detect` never spawns a process: everything is a file read. There is no
  # process, no shell and no PATH probing beyond a `File.file?` check.
  module RuntimeFacts
    # Where one field's value came from. `Unknown` means no local source
    # exists; such a field never matches a runtime record.
    enum Source
      # A literal from `rbconfig.rb`, or derived from its TOPDIR position.
      Rbconfig
      # A literal from a sibling file in the Ruby install tree
      # (`lib/ruby/<lib version>/rubygems.rb`).
      RubyLib
      # The reference Bundler version compiled into Celerite
      # (`Profile.bundler_version`).
      Profile
      # Read from the process environment (`GEM_HOME`).
      Environment
      # Supplied by the last bridge runtime record (`op_ruby_environment`),
      # for fields no local file carries (`engine`/`engine_version`). `detect`
      # never produces this source; it exists so the record merge can build a
      # `Facts` whose values are marked as recorded rather than reconstructed.
      Record
      # No local source; only the last bridge runtime record can supply it.
      Unknown
    end

    # One runtime fact: its value (when reconstructable) and where it came
    # from. `value` is `nil` exactly when the source is `Unknown`.
    struct Field
      getter value : String?
      getter source : Source

      def initialize(@value : String?, @source : Source)
      end

      def known? : Bool
        !@value.nil? && @source != Source::Unknown
      end
    end

    # The facts `detect` could reconstruct for one Ruby installation.
    struct Facts
      getter ruby_exe : String
      getter ruby_version : Field
      getter patchlevel : Field
      getter engine : Field
      getter engine_version : Field
      getter rubygems_version : Field
      getter bundler_version : Field
      getter platform : Field
      getter default_gem_dir : Field
      getter abi : Field
      # `TOPDIR` as substituted from the rbconfig path; `prefix` is that value.
      getter prefix : Field
      getter libdir : Field

      def initialize(@ruby_exe : String, @ruby_version : Field,
                     @patchlevel : Field, @engine : Field,
                     @engine_version : Field, @rubygems_version : Field,
                     @bundler_version : Field, @platform : Field,
                     @default_gem_dir : Field, @abi : Field,
                     @prefix : Field, @libdir : Field)
      end

      # Whether this installation still matches a runtime record. Every one of
      # the seven `EvalFingerprint::Runtime` fields must be known locally and
      # equal; an unknown field is a mismatch, never a wildcard, so a partial
      # reconstruction cannot make the fast path claim safety it lacks.
      def matches?(runtime : EvalFingerprint::Runtime) : Bool
        pairs = {
          {@ruby_version, runtime.ruby_version},
          {@patchlevel, runtime.patchlevel},
          {@engine, runtime.engine},
          {@engine_version, runtime.engine_version},
          {@rubygems_version, runtime.rubygems_version},
          {@bundler_version, runtime.bundler_version},
          {@platform, runtime.platform},
        }
        pairs.all? { |(field, recorded)| field.known? && field.value == recorded }
      end
    end

    # The maximum number of substitution passes. A self-referential value such
    # as `a = "$(a)"` stops here and is reported as unresolvable.
    MAX_EXPANSION_DEPTH = 8

    # Only the literal assignment shape is a fact. Comment lines, `TOPDIR`
    # assignments and the `RUBY_VERSION.start_with?(...) or raise` guard are
    # all rejected by this pattern.
    CONFIG_LINE = /^\s*CONFIG\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*$/

    # `/lib/ruby/<lib version>/<arch>` at the end of the rbconfig directory.
    LIB_DIR_SUFFIX = /\/lib\/ruby\/[^\/]+\/[^\/]+\z/

    # Locates `ruby_exe`, derives `<root>` from `<root>/bin/ruby[.exe]`, parses
    # the rbconfig of that tree and returns the facts. Every failure (missing
    # executable, a `ruby_exe` that is not under `<root>/bin`, no rbconfig, an
    # unreadable or empty rbconfig) returns `nil` so the caller takes the
    # compatibility path.
    def self.detect(ruby_exe : String? = nil) : Facts?
      exe = resolve_exe(ruby_exe)
      return nil if exe.nil?
      return nil unless File.file?(exe)

      root = ruby_root(exe)
      return nil if root.nil?

      rbconfig = find_rbconfig(root)
      return nil if rbconfig.nil?

      topdir = topdir_from(rbconfig)
      return nil if topdir.nil?

      text = begin
        File.read(rbconfig)
      rescue
        return nil
      end
      config = parse_config(text)
      return nil if config.empty?

      build_facts(exe, rbconfig, topdir, config)
    end

    # Explicit path wins; then `CELERITE_RUBY`; then PATH. An explicit but
    # unusable path is *not* retried against the environment: silently falling
    # back would hide a broken configuration behind a different Ruby.
    def self.resolve_exe(explicit : String?) : String?
      if explicit
        return explicit.empty? ? nil : explicit
      end
      if env = ENV["CELERITE_RUBY"]?
        return nil if env.empty?
        return env
      end
      find_on_path
    end

    private def self.find_on_path : String?
      path = ENV["PATH"]?
      return nil if path.nil? || path.empty?
      separator = {% if flag?(:windows) %} ';' {% else %} ':' {% end %}
      names = {% if flag?(:windows) %} ["ruby.exe", "ruby"] {% else %} ["ruby"] {% end %}
      path.split(separator).each do |dir|
        next if dir.empty?
        names.each do |name|
          candidate = File.join(dir, name)
          return candidate if File.file?(candidate)
        end
      end
      nil
    end

    # `<root>/bin/ruby[.exe]` -> `<root>`. Returns `nil` for anything else
    # (a shim outside `bin`, a bare name, a path with no parent).
    def self.ruby_root(ruby_exe : String) : String?
      dir = File.dirname(ruby_exe.gsub('\\', "/"))
      return nil unless File.basename(dir).downcase == "bin"
      root = File.dirname(dir)
      return nil if root.empty? || root == "."
      root
    end

    # First `<root>/lib/ruby/*/<arch>/rbconfig.rb` in sorted order. Templates
    # often carry several version directories; the caller only needs one
    # consistent tree, and the sort makes the choice deterministic.
    def self.find_rbconfig(root : String) : String?
      Glob.paths(File.join(root, "lib", "ruby"), "*").each do |version_dir|
        next unless File.directory?(version_dir)
        Glob.paths(version_dir, "*").each do |arch_dir|
          next unless File.directory?(arch_dir)
          candidate = File.join(arch_dir, "rbconfig.rb")
          return candidate if File.file?(candidate)
        end
      end
      nil
    end

    # The `TOPDIR` the file itself computes, derived from its location:
    # `.../lib/ruby/<lib version>/<arch>/rbconfig.rb` -> the prefix before
    # `/lib/ruby`. This is what `File.dirname(__FILE__).chomp!("/lib/ruby/…")`
    # yields for an installed Ruby, without evaluating Ruby.
    def self.topdir_from(rbconfig_path : String) : String?
      dir = File.dirname(rbconfig_path.gsub('\\', "/"))
      match = dir.match(/(.+)\/lib\/ruby\/[^\/]+\/[^\/]+\z/)
      return nil if match.nil?
      match[1]
    end

    # Collects the literal `CONFIG["key"] = "value"` assignments. Everything
    # else is ignored, so comments and guard expressions cannot inject values.
    def self.parse_config(text : String) : Hash(String, String)
      config = {} of String => String
      text.each_line do |line|
        next if line.lstrip.starts_with?('#')
        match = CONFIG_LINE.match(line)
        next if match.nil?
        config[match[1]] = unescape(match[2])
      end
      config
    end

    private def self.unescape(value : String) : String
      value.gsub(/\\(.)/) { |match| match[1] }
    end

    # Expands `$(KEY)` against the config, repeatedly, so `libdir ->
    # exec_prefix -> prefix` resolves in one call. Returns `nil` when a key is
    # missing, a `$(...)` never closes, or the expansion does not settle within
    # `MAX_EXPANSION_DEPTH` passes.
    def self.expand(value : String, config : Hash(String, String)) : String?
      current = value
      MAX_EXPANSION_DEPTH.times do
        match = /\$\(([^)]*)\)/.match(current)
        return current if match.nil?
        key = match[1]
        replacement = config[key]?
        return nil if replacement.nil?
        head = current[0, match.begin(0)]
        tail = current[match.end(0)..]? || ""
        current = "#{head}#{replacement}#{tail}"
      end
      current.includes?("$(") ? nil : current
    end

    private def self.build_facts(exe : String, rbconfig_path : String,
                                 topdir : String,
                                 config : Hash(String, String)) : Facts?
      with_prefix = config.dup
      # `CONFIG["prefix"]` is the expression `(TOPDIR || DESTDIR + "/.")`,
      # which the literal parser correctly refuses; TOPDIR is known here.
      with_prefix["prefix"] = topdir

      ruby_version = version_text(config)
      version_field =
        if ruby_version
          Field.new(ruby_version, Source::Rbconfig)
        else
          Field.new(nil, Source::Unknown)
        end

      patchlevel = field(config["PATCHLEVEL"]?, Source::Rbconfig)
      platform = platform_field(config["arch"]?)
      rubygems = rubygems_version(rbconfig_path)
      bundler = Field.new(Profile.bundler_version, Source::Profile)
      version = version_field.value
      default_gem_dir = default_gem_dir(with_prefix, config["ruby_version"]?)
      abi = version.nil? ? Field.new(nil, Source::Unknown) : Field.new(InstallPaths.ruby_abi_for(version), Source::Rbconfig)
      prefix = expanded_field(with_prefix, "prefix")
      libdir = expanded_field(with_prefix, "libdir")

      # Positional order matches `Facts#initialize`.
      Facts.new(exe, version_field, patchlevel,
        Field.new(nil, Source::Unknown), Field.new(nil, Source::Unknown),
        rubygems, bundler, platform, default_gem_dir, abi, prefix, libdir)
    end

    private def self.field(value : String?, source : Source) : Field
      value.nil? ? Field.new(nil, Source::Unknown) : Field.new(value, source)
    end

    # `MAJOR.MINOR.TEENY` is `RUBY_VERSION` (4.0.6 here); `CONFIG["ruby_version"]`
    # is the *library* version (4.0.0) and must not be confused with it.
    private def self.version_text(config : Hash(String, String)) : String?
      major = config["MAJOR"]?
      minor = config["MINOR"]?
      teeny = config["TEENY"]?
      return nil if major.nil? || minor.nil? || teeny.nil?
      "#{major}.#{minor}.#{teeny}"
    end

    # `Gem::Platform.local` is `RbConfig::CONFIG["arch"]`, with `_60` appended
    # only for the legacy `mswin32`/`mswin64` platforms (RubyGems
    # `platform.rb`); mingw and every other arch are taken verbatim.
    private def self.platform_field(arch : String?) : Field
      return Field.new(nil, Source::Unknown) if arch.nil?
      value = arch.matches?(/mswin(?:32|64)$/) ? "#{arch}_60" : arch
      Field.new(value, Source::Rbconfig)
    end

    # `<root>/lib/ruby/<lib version>/rubygems.rb` carries `Gem::VERSION` as a
    # literal. It is part of the install tree but not of rbconfig, hence
    # `Source::RubyLib`.
    def self.rubygems_version(rbconfig_path : String) : Field
      lib_dir = File.dirname(File.dirname(rbconfig_path.gsub('\\', "/")))
      path = "#{lib_dir}/rubygems.rb"
      return Field.new(nil, Source::Unknown) unless File.file?(path)
      text = begin
        File.read(path)
      rescue
        return Field.new(nil, Source::Unknown)
      end
      text.each_line do |line|
        next if line.lstrip.starts_with?('#')
        if match = /^\s*VERSION\s*=\s*"([^"]+)"/.match(line)
          return Field.new(match[1], Source::RubyLib)
        end
      end
      Field.new(nil, Source::Unknown)
    end

    # `Gem.default_dir` is `CONFIG["rubylibprefix"]/gems/<CONFIG["ruby_version"]>`
    # (`rubygems/defaults.rb`), unless `GEM_HOME` overrides it — the same
    # precedence the bridge uses (`ENV["GEM_HOME"] || Gem.default_dir`).
    # rbconfig paths use `/`, so the result is joined with `/` and matches the
    # record's spelling on Windows.
    private def self.default_gem_dir(config : Hash(String, String),
                                     lib_version : String?) : Field
      if gem_home = ENV["GEM_HOME"]?
        return Field.new(gem_home, Source::Environment) unless gem_home.empty?
      end
      return Field.new(nil, Source::Unknown) if lib_version.nil?
      rubylibprefix = config["rubylibprefix"]?
      return Field.new(nil, Source::Unknown) if rubylibprefix.nil?
      expanded = expand(rubylibprefix, config)
      return Field.new(nil, Source::Unknown) if expanded.nil?
      Field.new("#{expanded}/gems/#{lib_version}", Source::Rbconfig)
    end

    private def self.expanded_field(config : Hash(String, String), key : String) : Field
      raw = config[key]?
      return Field.new(nil, Source::Unknown) if raw.nil?
      expanded = expand(raw, config)
      expanded.nil? ? Field.new(nil, Source::Unknown) : Field.new(expanded, Source::Rbconfig)
    end
  end
end
