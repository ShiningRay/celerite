require "../celerite"
require "base64"
require "digest/sha256"
require "./bridge/client"
require "./compact_index/cache"
require "./resolver/source"
require "./definition"
require "./mirror"
require "./proxy"
require "./git_source"
require "./glob"

module Celerite
  # Install path helpers shared by Resolution and the CLI commands.
  #
  # Mirrors `Bundler::Settings::Path` (settings.rb L238-297): an explicit
  # `path` wins; deployment mode injects `vendor/bundle`; with nothing
  # configured the RubyGems install dir (`Gem.dir`) is used, exactly like the
  # reference for the 2.7.x/4.x profiles. `path.system` (or the legacy
  # `disable_shared_gems: false`) also selects `Gem.dir`. The ruby scope
  # (`ruby/<abi>`) is appended only when system gems are **not** in use.
  #
  # Call sites that cannot resolve `Gem.dir` (a bridge RPC) pass no
  # `system_gem_dir`; they keep the `<home>/.bundle` fallback, which is only
  # used for process locks and cache roots there.
  module InstallPaths
    # `Settings#path` (settings.rb L238-251) injects `vendor/bundle` as the
    # configured path when deployment mode is on and no path was given, which
    # then takes the explicit-path branch of `Path` (non-system gems, relative
    # to the project root).
    DEPLOYMENT_PATH = "vendor/bundle"

    # Base directory (without the ruby scope). Kept as the compatibility entry
    # used by process locks and other non-gem-root call sites.
    def self.install_path(config : Config, system_gem_dir : String = "") : String
      base_path(config, system_gem_dir)
    end

    # Deployment mode without an explicit `path` (`Settings#path`, L238-251).
    def self.deployment_path_requested?(config : Config) : Bool
      config["path"].to_s.empty? && config["deployment"] == true
    end

    # `Path#use_system_gems?` (settings.rb L260-264) decides whether the
    # install root is the RubyGems directory: `path.system` (or the legacy
    # `disable_shared_gems: false`) turns system gems on, an explicit `path`
    # (including the deployment default) turns them off. With nothing
    # configured the reference also uses system gems (`!bundler_5_mode?` for
    # the 2.7.x/4.x profiles); that branch needs the resolved `Gem.dir`, so a
    # call site without `system_gem_dir` keeps the `<home>/.bundle` fallback.
    def self.use_system_gems?(config : Config, system_gem_dir : String = "") : Bool
      return false unless config["path"].to_s.empty?
      return false if deployment_path_requested?(config)
      return true if config["path.system"] == true || config["disable_shared_gems"] == false
      !system_gem_dir.empty?
    end

    # Backwards-compatible name used by the CLI surfaces.
    def self.system_gems?(config : Config, system_gem_dir : String = "") : Bool
      use_system_gems?(config, system_gem_dir)
    end

    # `Path#validate!` (settings.rb L287-297): an explicit `path` cannot be
    # combined with system gems; the reference reports every configured value
    # of the three involved keys and exits 15.
    def self.validate!(config : Config) : Nil
      return if config["path"].to_s.empty?
      return unless config["path.system"] == true || config["disable_shared_gems"] == false
      raise PathConflictError.new(conflict_message(config))
    end

    # `Path#base_path` (settings.rb L266-271).
    def self.base_path(config : Config, system_gem_dir : String) : String
      validate!(config)
      configured = config["path"].to_s
      unless configured.empty?
        # `Bundler.bundle_path` expands the configured path against the project
        # root (bundler.rb L104), not against the process working directory.
        return File.expand_path(configured, config.project_root)
      end
      if deployment_path_requested?(config)
        root = config.project_root || Dir.current
        return File.expand_path(File.join(root, DEPLOYMENT_PATH))
      end
      if use_system_gems?(config, system_gem_dir) && !system_gem_dir.empty?
        return File.expand_path(system_gem_dir)
      end
      File.expand_path(File.join(Config.user_home || ".", ".bundle"))
    end

    # `Path#base_path_relative_to_pwd` (settings.rb L273-285): the install
    # summary prints the base path relative to the working directory (prefixed
    # with `./`), falling back to the configured absolute path when the base
    # lives above the working directory and was given absolutely.
    def self.base_path_relative_to_pwd(config : Config, project_root : String,
                                       system_gem_dir : String = "") : String
      # Keep the configured spelling: the reference decides the "above pwd"
      # branch on whether `base_path` itself was absolute, and prints it as
      # given in that case.
      configured = config["path"].to_s
      base = configured.empty? ? base_path(config, system_gem_dir) : configured
      # Normalise to `/` before the relative computation: Crystal's `Path`
      # treats backslashes as ordinary characters on some inputs, which makes
      # `relative_to` raise across what look like different roots.
      expanded = File.expand_path(base, project_root).gsub(/\\/, "/")
      cwd = Dir.current.gsub(/\\/, "/")
      absolute = base.starts_with?("/") || base.matches?(/\A[A-Za-z]:[\\\/]/)
      begin
        relative = Path[expanded].relative_to(Path[cwd]).to_s.gsub(/\\/, "/")
        if relative.starts_with?("..")
          # Above the working directory: the reference keeps the configured
          # spelling verbatim (`Pathname#to_s` of the raw value), so an
          # absolute `C:\…` path prints with backslashes and an absolute
          # `C:/…` path prints with forward slashes.
          absolute ? base : relative
        else
          # Below the working directory the reference prints
          # `Pathname.new(File.join(".", relative))`, i.e. `./<relative>`.
          relative == "." ? "./." : "./#{relative}"
        end
      rescue ArgumentError
        # Windows paths on different drives cannot be made relative
        # (Pathname.relative_path_from raises ArgumentError there too); the
        # reference falls back to the expanded base path.
        expanded
      end
    end

    # `Path#path` (settings.rb L270-280): the ruby scope is appended only when
    # system gems are not in use; with `path.system` `Gem.dir` itself is the
    # gem root (no `ruby/<abi>` level).
    def self.gem_root(config : Config, system_gem_dir : String, abi : String) : String
      base = base_path(config, system_gem_dir)
      use_system_gems?(config, system_gem_dir) ? base : File.join(base, "ruby", abi)
    end

    # Directory holding every ruby scope (`<base>/ruby`), or the gem dir itself
    # for `path.system` (there is no ruby scope then).
    def self.ruby_root(config : Config, system_gem_dir : String) : String
      base = base_path(config, system_gem_dir)
      use_system_gems?(config, system_gem_dir) ? base : File.join(base, "ruby")
    end

    # `Path#validate!` message body: `pretty_values_for` blocks for `path`,
    # `path.system` and `disable_shared_gems`, each preceded by a blank line
    # and a title (the reference only adds a block when the key has values).
    private def self.conflict_message(config : Config) : String
      parts = ["Using a custom path while using system gems is unsupported."]
      {"path" => "path:", "path.system" => "path.system:",
       "disable_shared_gems" => "disable_shared_gems:"}.each do |name, title|
        values = config.pretty_values_for(name)
        next if values.empty?
        parts << "" << title
        parts.concat(values)
      end
      parts.join("\n")
    end

    def self.downloader_cache_root : String
      home = Config.user_home || "."
      File.join(home, ".bundle", "cache")
    end

    def self.ruby_abi(bridge : Bridge::Client) : String
      ruby_abi_for(bridge.ruby_environment.ruby_version)
    end

    # Pure helper so the ABI derivation can be tested without a Ruby bridge.
    # RubyGems/Bundler use `<major>.<minor>.0` (e.g. 4.0.6 -> 4.0.0).
    def self.ruby_abi_for(ruby_version : String) : String
      parts = ruby_version.split(".")
      "#{parts[0]}.#{parts[1]? || "0"}.0"
    end
  end

  # M2 resolution orchestration: bridge Gemfile evaluation -> candidate index
  # -> PubGrub resolution -> lockfile generation (pinned contracts:
  # `Bundler::Definition` + `Bundler::Resolver`).
  class Resolution
    # The compact-index `checksum` requirement may be raw hex (rubygems.org
    # /info), raw base64 or `sha256=<hex>`; lockfiles render `sha256=<hex>`
    # (reference `Checksum::API_SHA256_HEX`). Shared normalization lives in
    # Celerite::Checksum; invalid input raises here so the failure names the
    # value instead of writing a mangled checksum.
    def self.info_checksum_value(raw : String) : String
      normalized = Celerite::Checksum.normalize_hex(raw)
      raise ArgumentError.new("invalid compact-index checksum #{raw.inspect}") if normalized.nil?
      "sha256=#{normalized}"
    end

    struct LockedSpec
      getter name : String
      getter version : Gem::Version
      getter platform : String?
      getter source_type : String
      getter remote : String?

      def initialize(@name : String, @version : Gem::Version, @platform : String?,
                     @source_type : String, @remote : String?)
      end
    end

    struct ResolvedSpec
      getter name : String
      getter version : Gem::Version
      getter platform : String?
      getter dependencies : Array(Lockfile::SpecDependency)
      getter checksum : String?
      getter source_index : Int32
      getter source_type : String # GEM / PATH / GIT
      getter source_info : SourceInfo?
      getter source_remote : String?
      # The declared (unexpanded) path for PATH/GIT sources, kept so
      # `install --standalone` can reproduce `source.path.absolute?`
      # (`installer/standalone.rb:54-61`) from the lockfile text.
      property source_declared : String? = nil

      # `Gem::Specification#required_ruby_version` / `required_rubygems_version`
      # from the resolved index entry. Reference `Installer#ensure_specs_are_compatible!`
      # (`installer.rb:234-245`) compares both at install time. The locked reuse
      # path materializes specs without loading gemspecs, so they stay nil there.
      getter required_ruby_version : Gem::Requirement? = nil
      getter required_rubygems_version : Gem::Requirement? = nil

      # True only when this row came from the interpreter's default gem (the
      # `index_specs_for` last-resort fallback), i.e. a `Gem::Specification`
      # whose `default_gem?` is true. A lock/index row that merely shares the
      # name and version with a default gem is a normal remote spec: the
      # reference keys its built-in handling on `spec.default_gem?`
      # (`source/rubygems.rb:181`, `:206`), and a materialized lock spec is
      # never a default gem, so it is fetched and installed from the remote
      # (measured: `net-protocol 0.2.2` in `lock-missing-dependency-edges`).
      getter default_gem : Bool = false

      def initialize(@name : String, @version : Gem::Version, @platform : String?,
                     @dependencies : Array(Lockfile::SpecDependency), @checksum : String?,
                     @source_index : Int32, @source_type : String = "GEM",
                     @source_info : SourceInfo? = nil, @source_remote : String? = nil,
                     @required_ruby_version : Gem::Requirement? = nil,
                     @required_rubygems_version : Gem::Requirement? = nil,
                     @default_gem : Bool = false)
      end

      def platform_ruby? : Bool
        platform.nil? || platform == "ruby"
      end

      def full_name : String
        platform_ruby? ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      end
    end

    # Non-GEM source descriptor (PATH remote / GIT remote+ref options).
    class SourceInfo
      include JSON::Serializable
      getter type : String
      getter remote : String
      getter branch : String?
      getter tag : String?
      getter ref : String?
      getter submodules : Bool?
      getter glob : String?
      property revision : String?
      # Plugin sources: declared type and `options_to_lock` values from the
      # bridge (`plugin/api/source.rb:41,73`).
      getter plugin_type : String?
      getter lock_options : Hash(String, String)?
    end

    getter evaluation : Bridge::GemfileEvaluation
    getter resolved_specs : Array(ResolvedSpec)
    getter sources : Array(Bridge::EvaluatedSource)
    getter bridge_bundler_version : String
    getter bundler_cache_path : String?

    # BUNDLED WITH version selection: after an auto-switch, the lockfile must
    # record the switched-to version.
    @bundler_cache_path : String?

    def bridge_bundler_version=(v : String)
      @bridge_bundler_version = v
      @bundler_cache_path = query_bundler_cache_path
    end

    # `bundle update --bundler <target>` records the target in BUNDLED WITH
    # without switching the interpreter profile (the reference execs a new
    # bundler; we keep the running one). Kept separate from
    # `bridge_bundler_version`, which drives 2.x vs 4.x lockfile formatting.
    property bundler_version_to_lock : String? = nil

    # `SelfManager#resolve_update_version_from` (self_manager.rb:47-65) asks
    # the rubygems remote for published `bundler` versions; installed or
    # default gems are not candidates for an update target.
    def bundler_versions(requirement : Gem::Requirement) : Array(Gem::Version)
      index_specs_from_remote("bundler")
        .map(&.version)
        .select { |version| requirement.satisfied_by?(version) }
        .uniq
        .sort
    end

    @non_gem_sources : Hash(String, SourceInfo)?
    @locked_specs : Array(LockedSpec)?
    @locked_by_name : Hash(String, Array(LockedSpec))?
    @compact_index_client : CompactIndex::Client?
    @index_specs_cache : Hash(String, Array(Resolver::IndexSpec))?
    @plugin_specs_cache : Hash(String, Array(Resolver::IndexSpec))?
    @default_gem_specs_cache : Hash(String, Resolver::IndexSpec?)?
    # Cooldown exclusions (name, version, created_at unix seconds) recorded
    # while building the candidate index (4.0.24 profile only).
    @cooldown_skipped = [] of Tuple(String, String, Int64)

    # Clock injection for cooldown tests (unix seconds).
    property cooldown_now : Int64?
    property cooldown_days : Int32?
    # Version promotion: :patch/:minor/:major ceiling for updates.
    property version_promotion : String?
    property version_promotion_strict : Bool = false
    # --ruby: rewrite the RUBY VERSION section to the running environment.
    property ruby_update : Bool = false

    # Progress output for "Fetching source index..." / "Resolving dependencies..."
    # lines (stdout for `lock`, stderr for `lock --print` — pinned behavior).
    property progress : IO = IO::Memory.new

    def initialize(@definition : Definition, @unlock : Bool | Array(String) = false,
                   @bridge : Bridge::Client? = nil)
      @owned_bridge = @bridge.nil?
      @bridge = @bridge || Bridge::Client.new
      @evaluation = eval_gemfile
      @sources = @evaluation.sources
      @bridge_bundler_version = @evaluation.bundler_version
      @bundler_cache_path = query_bundler_cache_path
      @resolved_specs = [] of ResolvedSpec
      @root_dependency_names = [] of String
      @resolved = false
      @current_base_requirements = {} of String => Gem::Requirement
      @current_index = {} of String => Array(Resolver::IndexSpec)
      @prerelease_available = Set(String).new
    end

    def close : Nil
      @bridge.not_nil!.close if @owned_bridge
    end

    # Exposed for callers that need the running Ruby ABI (e.g. the
    # `--add-checksums` installation cache and the bundle gem root).
    def bridge : Bridge::Client
      @bridge.not_nil!
    end

    # `--add-checksums` on 4.0.24 computes digests from the installed package
    # cache (`definition.rb:564-583`), fetching the gem when only the
    # specification is present. 2.7.2 only forces a CHECKSUMS section, so
    # callers gate this on the profile.
    def compute_checksums_from_installed(&fetch : ResolvedSpec -> String?) : Nil
      bridge = @bridge.not_nil!
      gem_root = InstallPaths.gem_root(@definition.config, bridge.ruby_environment.default_gem_dir, InstallPaths.ruby_abi(bridge))
      cache_dir = File.join(gem_root, "cache")
      existing_checksums = @definition.lockfile_exists? ? @definition.lockfile!.checksums : [] of Lockfile::ChecksumEntry
      @resolved_specs.each do |spec|
        next if spec.name == "bundler"
        next if spec.checksum
        existing = existing_checksums.find do |c|
          c.name == spec.name && c.version == spec.version.to_s &&
            (c.platform.nil? || c.platform == "ruby") && !c.checksums.empty?
        end
        next if existing
        next unless File.file?(File.join(gem_root, "specifications", "#{spec.full_name}.gemspec"))
        cached = File.join(cache_dir, "#{spec.full_name}.gem")
        unless File.file?(cached)
          next unless fetched = fetch.call(spec)
          next unless File.file?(fetched)
          Dir.mkdir_p(cache_dir)
          File.copy(fetched, cached)
        end
        @install_checksums["#{spec.name}-#{spec.version}"] = "sha256=#{Digest::SHA256.hexdigest(File.read(cached))}"
      end
    end

    private def eval_gemfile : Bridge::GemfileEvaluation
      @bridge.not_nil!.evaluate_gemfile(@definition.gemfile_path)
    end

    private def query_bundler_cache_path : String?
      # The reference records a checksum for the running Bundler when its
      # cached .gem is available; ask the Ruby side for the cache path.
      @bridge.not_nil!.bundler_cache_file(@bridge_bundler_version)
    rescue Bridge::BridgeError
      nil
    end

    # ------------------------------------------------------------------
    # Locked state
    # ------------------------------------------------------------------

    def locked_specs : Array(LockedSpec)
      @locked_specs ||= begin
        lockfile = @definition.lockfile_exists? ? @definition.lockfile! : nil
        list = [] of LockedSpec
        if lockfile
          lockfile.sources.each do |source|
            remote = source.remote
            source.specs.each do |spec|
              list << LockedSpec.new(spec.name, Gem::Version.new(spec.version), spec.platform,
                source.type, remote)
            end
          end
        end
        list
      end
    end

    private def locked_specs_by_name : Hash(String, Array(LockedSpec))
      @locked_by_name ||= locked_specs.group_by(&.name)
    end

    # Versions recorded in the ORIGINAL lockfile, keyed by gem name. The
    # reference keeps these apart from the resolution base: `reresolve_without`
    # deletes rows from the base only (`definition.rb:782-785`), while
    # `new_resolution_base` always hands `Resolver::Base` the untouched
    # `@originally_locked_specs` (`definition.rb:1323`), so `Package#locked_version`
    # still reports them and the promoter keeps preferring the locked version
    # (`gem_version_promoter.rb:134-145`). Used by the lock-edge heal so that
    # completing a missing dependency edge never upgrades an already-locked gem.
    private def preferred_locked_versions : Hash(String, Gem::Version)?
      specs = locked_specs
      return nil if specs.empty?

      versions = {} of String => Gem::Version
      specs.each do |spec|
        next if @dropped_locked_names.includes?(spec.name)
        versions[spec.name] ||= spec.version
      end
      versions.empty? ? nil : versions
    end

    # `@locked_spec_with_missing_deps` / `@locked_spec_with_invalid_deps`
    # (`definition.rb:973-1015 check_lockfile` + `spec_set.rb:87-96
    # validate_deps`): a locked row whose edge points at a gem with no locked row
    # at all is `:missing`; one whose edge names a locked gem but no locked
    # version satisfies the edge requirement is `:invalid`. The reference
    # deletes such rows from `@locked_specs`, which makes `something_changed?`
    # true (`definition.rb:630-645`) and lets the resolve pick a fresh version.
    # A row with no edges at all (S3: the edge line is absent) is complete and
    # keeps the reference's no-op behavior.
    def incomplete_locked_spec_names : Array(String)
      @incomplete_locked_names ||= begin
        names = [] of String
        if @definition.lockfile_exists?
          rows = [] of Lockfile::Spec
          @definition.lockfile!.sources.each { |source| rows.concat(source.specs) }
          by_name = Hash(String, Array(Lockfile::Spec)).new
          rows.each { |row| (by_name[row.name] ||= [] of Lockfile::Spec) << row }
          rows.each do |row|
            incomplete = row.dependencies.any? do |edge|
              next false if edge.name == "bundler"
              targets = by_name[edge.name]?
              if targets.nil?
                true
              else
                !targets.any? { |target| edge.requirement.satisfied_by?(Gem::Version.new(target.version)) }
              end
            end
            names << row.name if incomplete
          end
        end
        names.uniq!
        names
      end
    end

    # ------------------------------------------------------------------
    # Source/index setup
    # ------------------------------------------------------------------

    # Remote of the primary rubygems source (M2: file:// and http(s)),
    # normalized with a trailing slash like the reference remotes.
    def primary_remote : String
      remote = rubygem_source_remote
      remote = "https://rubygems.org/" if remote.empty?
      remote += "/" unless remote.ends_with?("/")
      remote
    end

    private def rubygem_source_remote : String
      scoped_remotes = @evaluation.dependencies.compact_map do |dep|
        source = dep.source
        next unless source && (source.type == "Rubygems" || source.type == "Metadata")
        remote = source.remotes.try(&.first?) || source.remote
        remote ? remote.chomp('/') : nil
      end.to_set

      rubygem_source = @sources.select(&.type.==("Rubygems")).find do |source|
        remote = source.remotes.try(&.first?) || source.remote
        remote.nil? || !scoped_remotes.includes?(remote.chomp('/'))
      end
      rubygem_source ||= @sources.find(&.type.==("Rubygems"))
      rubygem_source.try(&.remotes.try(&.first?)) ||
        rubygem_source.try(&.remote) ||
        ""
    end

    private def normalize_rubygems_remote(remote : String?) : String?
      return nil if remote.nil? || remote.empty?
      remote = remote.chomp('/')
      remote = "https://rubygems.org" if remote.empty? || remote == "https://rubygems.org"
      remote += "/" unless remote.ends_with?("/")
      remote
    end

    # Declared Rubygems/Metadata source remotes in Gemfile evaluation order,
    # normalized for lockfile GEM sections. Includes scoped remotes and the
    # primary source; deduplicates by normalized remote.
    #
    # A rubygems source that declares no remote at all (a Gemfile with no
    # `source` line) is *not* expanded into the `https://rubygems.org/` default:
    # the reference writes `GEM` with an empty option list there
    # (`source/rubygems.rb:114-120 to_lock`: `remote` lines come from
    # `lockfile_remotes`, so an empty list yields `GEM\n  specs:\n`). Measured
    # on 4.0.24/2.7.2 (task-44a oracle (d)). `rubygem_source_without_remote?`
    # reports that shape.
    private def declared_rubygem_remotes : Array(String)
      remotes = [] of String
      seen = Set(String).new
      @sources.each do |source|
        next unless source.type == "Rubygems" || source.type == "Metadata"
        candidates = source.remotes
        if candidates && !candidates.empty?
          candidates.each do |candidate|
            remote = normalize_rubygems_remote(candidate)
            next unless remote
            remotes << remote unless seen.includes?(remote)
            seen << remote
          end
        else
          remote = normalize_rubygems_remote(source.remote)
          next unless remote
          unless seen.includes?(remote)
            remotes << remote
            seen << remote
          end
        end
      end
      remotes
    end

    # True when the Gemfile declares a rubygems source with no remote at all
    # (no `source` line): the lockfile then carries a bare `GEM` section.
    private def rubygem_source_without_remote? : Bool
      @sources.any? do |source|
        next false unless source.type == "Rubygems" || source.type == "Metadata"
        remotes = source.remotes
        (remotes.nil? || remotes.empty?) && normalize_rubygems_remote(source.remote).nil?
      end
    end

    def compact_index_client : CompactIndex::Client
      @compact_index_client ||= CompactIndex::Client.new(primary_remote, user_cache_root, @definition.config.credentials_for(primary_remote), Commands.retry_count(@definition.config), Celerite::Mirror.resolve(@definition.config, primary_remote), ssl_ca_cert: Commands.ssl_option(@definition.config, "ssl_ca_cert"), ssl_client_cert: Commands.ssl_option(@definition.config, "ssl_client_cert"), ssl_verify_mode: Commands.ssl_option(@definition.config, "ssl_verify_mode"), timeout: Commands.timeout_seconds(@definition.config), proxy: Celerite::Proxy.resolve(@definition.config))
    end

    def compact_index_client_for(remote : String) : CompactIndex::Client
      CompactIndex::Client.new(remote, user_cache_root, @definition.config.credentials_for(remote), Commands.retry_count(@definition.config), Celerite::Mirror.resolve(@definition.config, remote), ssl_ca_cert: Commands.ssl_option(@definition.config, "ssl_ca_cert"), ssl_client_cert: Commands.ssl_option(@definition.config, "ssl_client_cert"), ssl_verify_mode: Commands.ssl_option(@definition.config, "ssl_verify_mode"), timeout: Commands.timeout_seconds(@definition.config), proxy: Celerite::Proxy.resolve(@definition.config))
    end

    # Scoped Rubygems source (`gem "x", source: <remote>`), normalized like
    # the lockfile remotes.
    def scoped_remote_for(name : String) : String?
      dep = @evaluation.dependencies.find(&.name.==(name))
      src = dep.try(&.source)
      return nil unless src && (src.type == "Rubygems" || src.type == "Metadata")
      remote = src.remotes.try(&.first?) || src.remote
      return nil unless remote && !remote.empty?
      remote += "/" unless remote.ends_with?("/")
      remote
    end

    def remote_for(name : String) : String
      scoped_remote_for(name) || primary_remote
    end

    private def user_cache_root : String
      home = Config.user_home || "."
      File.join(home, ".bundle", "cache", "compact_index")
    end

    # Non-GEM sources from the Gemfile evaluation (PATH remote / GIT options),
    # keyed by the dependency name bound to them.
    def non_gem_sources : Hash(String, SourceInfo)
      @non_gem_sources ||= begin
        map = {} of String => SourceInfo
        @evaluation.dependencies.each do |dep|
          src = dep.source
          next if src.nil?
          next if src.type == "Rubygems" || src.type == "Metadata"
          map[dep.name] = SourceInfo.from_json({
            "type" => src.type, "remote" => (src.remote || src.remotes.try(&.first?) || ""),
            "branch" => src.branch, "tag" => src.tag, "ref" => src.ref,
            "submodules" => src.submodules, "glob" => src.glob, "revision" => nil,
            "plugin_type" => src.plugin_type, "lock_options" => src.lock_options,
          }.to_json)
        end
        map
      end
    end

    # Loads the spec of a path/git source gem (gemspec in the given dir).
    #
    # The bridge enumerates the whole glob and matches on the gemspec's own
    # name (`source/path.rb:159-179`); a directory that only holds a sibling
    # gem must not yield a spec for `name`. Reference `resolver/base.rb:113-118`
    # then reports `Could not find gem '<name>' in <source>`.
    def load_source_gem_spec(name : String, dir : String, glob : String?) : Resolver::IndexSpec?
      # Reference source/path.rb:19 and source/git.rb:15 default the glob to
      # DEFAULT_GLOB; pass it explicitly so the bridge never falls back to a
      # different shallow pattern.
      info = @bridge.not_nil!.load_gemspec_dir(dir, glob || DEFAULT_GLOB, name)
      return nil unless info.name == name
      version = Gem::Version.new(info.version)
      platform = info.platform == "ruby" ? Gem::Platform::RUBY : Gem::Platform.new(info.platform)
      deps = (info.dependencies || [] of JSON::Any).map do |d|
        reqs = d["requirements"].as_a.map(&.as_s)
        reqs.empty? ? Resolver::DepSpec.new(d["name"].as_s, Gem::Requirement.new) : Resolver::DepSpec.new(d["name"].as_s, Gem::Requirement.new(reqs))
      end
      ruby_req = info.required_ruby_version.empty? ? Gem::Requirement.new : Gem::Requirement.new(info.required_ruby_version)
      rubygems_req = info.required_rubygems_version.empty? ? Gem::Requirement.new : Gem::Requirement.new(info.required_rubygems_version)
      Resolver::IndexSpec.new(name, version, platform, deps, ruby_req, rubygems_req, nil)
    rescue ex : Bridge::BridgeError
      nil
    end

    # The rubygems index is fetched lazily on first access (pinned reference
    # behavior: the fetch lands before "Resolving dependencies..." when root
    # gem deps need it, after it otherwise).
    @index_fetch_logged = false

    private def log_index_fetch : Nil
      log_fetch_for(primary_remote)
    end

    # True once the primary source-index fetch line has been printed. Callers
    # that print the line themselves on the locked path use this to avoid the
    # duplicate caused by a compatibility-check fetch.
    def index_fetch_logged? : Bool
      @index_fetch_logged
    end

    @fetch_logged_remotes = Set(String).new

    # Locked specs re-checked against the current Ruby/RubyGems and found
    # incompatible (see `resolve!`); they must not seed the solver's locked
    # index with empty requirements.
    @excluded_locked_names = Set(String).new

    @incomplete_locked_names : Array(String)?

    @path_specs_changed : Bool?

    @fetch_replayed = false

    # install asks for the eresolve_without heal of stale lockfile edges
    # (definition.rb:699-708); lock deliberately keeps the edges as written.
    property autoheal_locked_edges : Bool = false

    # `lock` asks for the `check_lockfile` semantics instead: a locked row whose
    # own edges cannot be satisfied by the lockfile is removed from the locked
    # state entirely, so the solver may pick a newer version (see
    # `incomplete_locked_spec_names`).
    property drop_incomplete_locked_specs : Bool = false

    # Names removed by `drop_incomplete_locked_specs`. They must disappear from
    # the locked index AND from the preferred-version map and the `>= locked`
    # floor, because the reference deletes the row from `@locked_specs`, the
    # very object `@originally_locked_specs` aliases (`definition.rb:140`).
    @dropped_locked_names = Set(String).new

    private def log_fetch_for(remote : String) : Nil
      return unless @fetch_logged_remotes.add?(remote)
      return if remote == primary_remote && @index_fetch_logged
      @index_fetch_logged = true if remote == primary_remote
      if remote.starts_with?("file:")
        @progress.puts "Fetching source index from #{remote}"
      else
        # Bundler renders this line only once the fetch is under way (a
        # connection failure prints nothing; see network-unreachable), and it
        # follows the caller's stream split (stdout for `lock`, stderr for
        # `lock --print`) via #progress.
        @progress.puts "Fetching gem metadata from #{remote}."
      end
    end

    # Gemfile per-source `cooldown:` value for a remote (nil unless declared).
    private def source_cooldown(remote : String) : Int32?
      @sources.each do |source|
        next unless source.type == "Rubygems" || source.type == "Metadata"
        if mappings = source.remote_cooldowns
          mappings.each do |uri, days|
            return days if normalize_remote(uri) == normalize_remote(remote)
          end
        end
        next unless source.cooldown
        match = (source.remotes || [] of String).includes?(remote) ||
                source.remote == remote
        return source.cooldown if match
      end
      nil
    end

    # Version promotion ceiling: candidate versions above the locked
    # major/minor/patch are excluded from the request (pinned
    # `Bundler::GemVersionPromoter` at the flag level).
    private def promoted_out?(name : String, version : Gem::Version) : Bool
      level = @version_promotion
      level = (@version_promotion_strict ? "patch" : nil) if level.nil?
      return false if level.nil?
      locked = locked_specs_by_name[name]?.try(&.first?)
      return false unless locked
      locked_v = locked.version
      case level
      when "patch"
        !(version.segments[0] == locked_v.segments[0] && version.segments[1] == locked_v.segments[1])
      when "minor"
        !(version.segments[0] == locked_v.segments[0])
      else
        false
      end
    end

    # Cooldown: gem versions published less than the configured number of
    # days ago are excluded from candidacy (4.0.24 profile, `cooldown`
    # setting). A version already pinned in the lockfile stays exempt unless
    # the user explicitly unlocked that gem (pinned `Resolver#cooldown_excluded?`).
    private def cooldown_excluded?(name : String, version : Gem::Version, created_at : Int64?) : Bool
      return false unless bridge_bundler_version.starts_with?("4.")
      # file:// (v1 marshal) indexes never carry per-version created_at in
      # the reference, so cooldown never applies there (bundle-config(1):
      # versions without the metadata remain resolvable).
      return false if primary_remote.starts_with?("file:")
      # Precedence: CLI > config > Gemfile per-source (bundle-config(1)).
      days = @cooldown_days || @definition.config.cooldown_days || source_cooldown(primary_remote)
      return false if days.nil? || days <= 0
      return false if created_at.nil?
      return false if locked_specs_by_name[name]?.try { |list| list.any? { |s| s.version == version } } &&
                      !explicitly_unlocked?(name)
      now = @cooldown_now || Time.utc.to_unix
      (now - created_at) < days.to_i64 * 86_400_i64
    end

    private def explicitly_unlocked?(name : String) : Bool
      if @unlock == true
        true
      elsif unlocked_names = @unlock.as?(Array(String))
        unlocked_names.includes?(name)
      else
        false
      end
    end

    # Skipped-by-cooldown newest entries above the resolved version.
    def cooldown_skipped_summary : Array(Tuple(String, String, String, Int32))
      resolved = @resolved_specs.to_h { |s| {s.name, s} }
      days = @cooldown_days || @definition.config.cooldown_days || source_cooldown(primary_remote) || 0
      @cooldown_skipped.compact_map do |(name, version, created_at)|
        spec = resolved[name]?
        next if spec.nil?
        next unless Gem::Version.new(version) > spec.version
        requirement = @current_base_requirements[name]?
        next unless requirement.nil? || requirement.satisfied_by?(Gem::Version.new(version))
        remaining = (days.to_i64 * 86_400 - ((@cooldown_now || Time.utc.to_unix) - created_at))
        days_left = [(remaining / 86_400.0).ceil.to_i32, 1].max
        {name, version, spec.version.to_s, days_left}
      end.sort_by { |(name, _, _, _)| name }
    end

    # Local/prefer-local installs read from locally installed gems only
    # (pinned `install --local`; the compact index is never consulted).
    property local_only : Bool = false
    property prefer_local : Bool = false
    # `Plugin.gemfile_install` resolves the inferred `bundler-source-<type>`
    # dependencies with `sources.cached!` + `remotely!` only, so
    # `Source::Rubygems#to_s` reports "…, cached gems or installed locally"
    # (rubygems.rb:122-136). Install sets this while probing inferred plugins.
    property remote_only : Bool = false
    @installed_local_specs : Array(Resolver::IndexSpec)? = nil
    # full_name of the installed gems that supplied `--local` candidates; the
    # installer skips these (they are already present in this GEM_HOME).
    getter local_installed_full_names = Set(String).new

    # `vendor/cache` gems are installed straight from the cached file; the
    # reference never downloads them again (`install --local` with an app cache
    # prints no `Fetching` line). Keyed by full name.
    getter vendor_cache_paths = {} of String => String

    def vendor_cache_path(full_name : String) : String?
      @vendor_cache_paths[full_name]?
    end

    # `install --local` candidates: gems already visible to RubyGems plus
    # `<Gemfile dir>/vendor/cache/*.gem`. The reference never enables remote
    # sources for `--local` (`setup_domain!`, definition.rb:190-203), so the
    # index is not consulted at all.
    # `<install root>/specifications` of this project's bundle path, when it
    # exists: gems installed there are invisible to the bare bridge's RubyGems,
    # while Bundler's local-only sources see them because `bundle` rewires
    # Gem.path to the bundle path.
    private def project_spec_dir : String?
      env = @bridge.not_nil!.ruby_environment
      root = InstallPaths.gem_root(@definition.config, env.default_gem_dir, ruby_abi_for_git)
      dir = File.join(root, "specifications")
      Dir.exists?(dir) ? dir : nil
    end

    private def local_index_specs(name : String) : Array(Resolver::IndexSpec)
      installed = @installed_local_specs ||= begin
        list = [] of Resolver::IndexSpec
        payload = @bridge.not_nil!.installed_specs(project_spec_dir)
        (payload.as_a? || [] of JSON::Any).each do |entry|
          spec_name = entry["name"]?.try(&.as_s?) || next
          version = entry["version"]?.try(&.as_s?) || next
          # `--local` means "gems installed for this project": when GEM_HOME is
          # set, only specs living under it count. The host's user/system gem
          # dirs can carry newer copies (json_pure 2.8.1 in the test host) that
          # the reference oracle never sees in an isolated GEM_HOME.  Specs read
          # from the project's own bundle path are always project gems.
          if !entry["from_dir"]?.try(&.as_bool?) && (home = ENV["GEM_HOME"]?)
            unless home.empty?
              home_prefix = home.gsub('\\', "/").chomp("/") + "/"
              gem_path = (entry["full_gem_path"]?.try(&.as_s?) || "").gsub('\\', "/")
              next unless gem_path.starts_with?(home_prefix)
            end
          end
          # `install --local` restricts the interpreter's view to the project
          # bundle (`Gem.path` is rewired to `BUNDLE_PATH`), so host gems must
          # not become candidates; otherwise a host copy would be "installed"
          # and the reference's `Could not find gem '<name>' in locally
          # installed gems.` never fires.  Only when a custom path is in play:
          # without one the reference does see the system gems.
          if @local_only && !@definition.config["path"].as?(String).try(&.empty?).nil?
            next unless entry["from_dir"]?.try(&.as_bool?)
          end
          platform_raw = entry["platform"]?.try(&.as_s?) || "ruby"
          platform = platform_raw == "ruby" ? Gem::Platform::RUBY : Gem::Platform.new(platform_raw)
          deps = (entry["dependencies"]?.try(&.as_a) || [] of JSON::Any).map do |dep|
            requirements = (dep["requirements"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
            Resolver::DepSpec.new(dep["name"].as_s, Gem::Requirement.new(requirements))
          end
          ruby_req = requirement_from(entry["required_ruby_version"]?.try(&.as_s?))
          rubygems_req = requirement_from(entry["required_rubygems_version"]?.try(&.as_s?))
          list << Resolver::IndexSpec.new(spec_name, Gem::Version.new(version), platform, deps, ruby_req, rubygems_req)
          full_name = platform_raw == "ruby" ? "#{spec_name}-#{version}" : "#{spec_name}-#{version}-#{platform_raw}"
          @local_installed_full_names << full_name
        end
        list
      end
      candidates = installed.select(&.name.==(name))
      candidates.concat(vendor_cache_specs(name))
      candidates
    end

    private def requirement_from(text : String?) : Gem::Requirement
      return Gem::Requirement.new if text.nil? || text.empty?
      # RubyGems renders multi-clause constraints as ">= 3.0, < 5.0"; the
      # requirement constructor takes one clause per element.
      requirements = text.split(",").map(&.strip).reject(&.empty?)
      return Gem::Requirement.new if requirements.empty?
      Gem::Requirement.new(requirements)
    end

    # `<Gemfile dir>/vendor/cache/*.gem` entries for one gem (the reference
    # treats the app cache as local candidates under --local/--prefer-local).
    private def vendor_cache_specs(name : String) : Array(Resolver::IndexSpec)
      dir = File.join(File.dirname(@definition.gemfile_path), "vendor", "cache")
      return [] of Resolver::IndexSpec unless Dir.exists?(dir)
      specs = [] of Resolver::IndexSpec
      Glob.paths(dir, "#{name}-*.gem").sort.each do |path|
        data = @bridge.not_nil!.read_gem_spec(path)
        next unless data["name"]?.try(&.as_s?) == name
        version = data["version"]?.try(&.as_s?) || next
        platform_raw = data["platform"]?.try(&.as_s?) || "ruby"
        platform = platform_raw == "ruby" ? Gem::Platform::RUBY : Gem::Platform.new(platform_raw)
        deps = (data["dependencies"]?.try(&.as_a) || [] of JSON::Any).compact_map do |dep|
          next unless dep["type"]?.try(&.as_s?) == "runtime"
          requirements = (dep["requirements"]?.try(&.as_a) || [] of JSON::Any).map(&.as_s)
          Resolver::DepSpec.new(dep["name"].as_s, Gem::Requirement.new(requirements))
        end
        ruby_req = requirement_from(data["required_ruby_version"]?.try(&.as_s?))
        rubygems_req = requirement_from(data["required_rubygems_version"]?.try(&.as_s?))
        specs << Resolver::IndexSpec.new(name, Gem::Version.new(version), platform, deps, ruby_req, rubygems_req)
        full_name = platform_raw == "ruby" ? "#{name}-#{version}" : "#{name}-#{version}-#{platform_raw}"
        @vendor_cache_paths[full_name] = path
      end
      specs
    end

    # `Bundler.app_cache.exist?` — `Pathname.new(custom_path || root).join(cache_path)`
    # (bundler.rb:340-343) with `cache_path` defaulting to "vendor/cache"
    # (settings.rb:304-306). Only its existence matters here: `Source::Rubygems#cached!`
    # returns early unless the directory exists (source/rubygems.rb:69-76).
    def app_cache_present? : Bool
      root = File.dirname(@definition.gemfile_path)
      Dir.exists?(File.expand_path(app_cache_label, root))
    end

    # `Bundler.settings.app_cache_path` = `self[:cache_path] || "vendor/cache"`
    # (settings.rb:304-306); the not-found message spells it verbatim.
    def app_cache_label : String
      case value = @definition.config["cache_path"]
      when String then value
      else             "vendor/cache"
      end
    end

    # `install --prefer-local` only sees the gems installed for THIS project:
    # the reference rewires `Gem.path` to `BUNDLE_PATH`, so the interpreter's
    # own directories are invisible. `Bridge.installed_specs` aggregates the
    # whole RubyGems view (host `json_pure 2.8.1`), which is exactly what must
    # not leak in here, so enumerate the project's `specifications/*.gemspec`
    # ourselves and read them through the bridge (task-50/112 op).
    private def prefer_local_candidates(name : String) : Array(Resolver::IndexSpec)
      specs = [] of Resolver::IndexSpec
      if dir = project_spec_dir
        Glob.paths(dir, "*.gemspec").each do |path|
          data = @bridge.not_nil!.load_installed_spec(path) || next
          next unless data["name"]?.try(&.as_s?) == name
          version = data["version"]?.try(&.as_s?) || next
          platform_raw = data["platform"]?.try(&.as_s?) || "ruby"
          platform = platform_raw == "ruby" ? Gem::Platform::RUBY : Gem::Platform.new(platform_raw)
          deps = (data["dependencies"]?.try(&.as_a) || [] of JSON::Any).compact_map do |dep|
            dep_name = dep.as_s?
            dep_name ? Resolver::DepSpec.new(dep_name, Gem::Requirement.new) : nil
          end
          specs << Resolver::IndexSpec.new(
            name,
            Gem::Version.new(version),
            platform,
            deps,
            requirement_from(data["required_ruby_version"]?.try(&.as_s?)),
            requirement_from(data["required_rubygems_version"]?.try(&.as_s?)),
          )
        end
      end
      specs.concat(vendor_cache_specs(name))
      specs
    end

    private def index_specs_for(name : String) : Array(Resolver::IndexSpec)
      local = local_index_specs(name)
      if @local_only
        # `local_only!` sources know nothing beyond the gems installed for this
        # bundle: an unknown name is left for the resolver, which reports
        # "Could not find gem '<name> (<req>)' in locally installed gems."
        return local
      end
      if @prefer_local
        # `install --prefer-local` still owns the remote source: the reference
        # fetches the index (so `Fetching source index …` prints) and only then
        # prefers the bundle copies (source/rubygems.rb:148-178 keeps both
        # views; the resolver takes the local one when available).
        remote = index_specs_from_remote(name)
        candidates = prefer_local_candidates(name)
        return candidates unless candidates.empty?
        return remote unless remote.empty?
        return [] of Resolver::IndexSpec
      end
      remote = index_specs_from_remote(name)
      return remote unless remote.empty?

      # `Bundler::CLI::Common.default_gem_spec` (cli/common.rb:98-101): when
      # the index has no candidates for the name, Bundler's source can still
      # materialize the interpreter's default gem. Keep this strictly a
      # last-resort fallback; ordinary index hits never mix in default gems.
      if fallback = default_gem_index_spec(name)
        [fallback]
      else
        remote
      end
    end

    # Build a resolver candidate from the interpreter's default gem. The
    # reference writes it into the lockfile under the declared GEM remote
    # (measured: `json (2.18.0)`), so the source type stays GEM.
    private def default_gem_index_spec(name : String) : Resolver::IndexSpec?
      @default_gem_specs_cache ||= {} of String => Resolver::IndexSpec?
      if @default_gem_specs_cache.not_nil!.has_key?(name)
        return @default_gem_specs_cache.not_nil![name]
      end
      data = @bridge.not_nil!.default_gem_spec(name)
      spec = if data
               platform = data[:platform] == "ruby" ? Gem::Platform::RUBY : Gem::Platform.new(data[:platform])
               deps = data[:dependencies].map do |dep|
                 Resolver::DepSpec.new(dep[:name], Gem::Requirement.new(dep[:requirements]))
               end
               Resolver::IndexSpec.new(
                 data[:name],
                 Gem::Version.new(data[:version]),
                 platform,
                 deps,
                 requirement_from(data[:required_ruby_version]),
                 requirement_from(data[:required_rubygems_version]),
                 nil,
                 data[:full_gem_path],
               )
             end
      @default_gem_specs_cache.not_nil![name] = spec
      spec
    end

    # Build candidate specs for one gem from the compact index.
    private def index_specs_from_remote(name : String) : Array(Resolver::IndexSpec)
      remote = remote_for(name)
      cache = @index_specs_cache ||= {} of String => Array(Resolver::IndexSpec)
      cache[name] ||= begin
        client = remote == primary_remote ? compact_index_client : compact_index_client_for(remote)
        entries = client.info(name)
        log_fetch_for(remote)
        entries.each do |entry|
          version = Gem::Version.new(entry.version)
          @cooldown_skipped << {name, entry.version, entry.created_at.not_nil!} if cooldown_excluded?(name, version, entry.created_at)
        end
        filtered = entries.reject { |entry| cooldown_excluded?(name, Gem::Version.new(entry.version), entry.created_at) }
        filtered = filtered.reject { |entry| promoted_out?(name, Gem::Version.new(entry.version)) } if @version_promotion
        filtered.map do |entry|
          version = Gem::Version.new(entry.version)
          platform = entry.platform_ruby? ? Gem::Platform::RUBY : Gem::Platform.new(entry.platform.not_nil!)
          deps = entry.dependencies.map do |d|
            if d.requirements.empty?
              Resolver::DepSpec.new(d.name, Gem::Requirement.new)
            else
              Resolver::DepSpec.new(d.name, Gem::Requirement.new(d.requirements))
            end
          end
          ruby_req = Gem::Requirement.new(entry.required_ruby_version_list)
          rubygems_req = Gem::Requirement.new(entry.required_rubygems_version_list)
          # Parity: the reference only records per-gem checksums from remote
          # API sources; file:// indexes install without them.
          checksum = remote.starts_with?("file:") ? nil : entry.checksum
          Resolver::IndexSpec.new(name, version, platform, deps, ruby_req, rubygems_req, checksum)
        end
      rescue ex : CompactIndex::Error
        raise ex
      rescue ex : Celerite::AuthenticationForbiddenError
        # The compact index answered 403. `compact_index_request` swallows that
        # and the reference falls back to the legacy index, which logs its own
        # fetch line before the 403 is reported with the source URI
        # (fetcher/compact_index.rb L9-23, fetcher/index.rb L14-19).
        @progress.puts "Fetching source index from #{remote}"
        @progress.puts ""
        raise ex
      rescue ex : Celerite::VersionError
        raise LockfileError.new("bad compact index data for #{name}: #{ex.message}")
      end
    end

    # ------------------------------------------------------------------
    # Resolution
    # ------------------------------------------------------------------

    def resolve!(reuse : Bool = false, verify_locked_compat : Bool = false) : Array(ResolvedSpec)
      @resolved = true
      deps = top_level_deps
      # `definition.rb:190-203`: `--local` never enables remote sources, so a
      # locked bundle is materialized from the lockfile and nothing is
      # resolved or fetched. When a package is neither installed in the bundle
      # nor present in the app cache the installer reports the not-found
      # message (`installer.rb:81-96`) and no resolve line is printed.
      # `definition.rb:342-366` + `setup_domain!` (`:186-203`): `--local` only
      # turns the sources local, it does not skip the resolve. When the Gemfile
      # names a dependency the lockfile does not carry at all,
      # `Definition#converge_dependencies` (`:1051-1109`) marks the definition
      # as changed, so `resolve` leaves `@locked_specs` behind and asks the
      # local-only source for the new name. That source knows nothing beyond the
      # installed gems and reports `Could not find gem '<name>' in locally
      # installed gems.` (resolver.rb:334-361). Reusing the lock here instead
      # would silently drop the dependency from the resolved set and write a
      # lock whose DEPENDENCIES section disagrees with its GEM specs.
      if @local_only && @definition.lockfile_exists? && lockfile_covers_all_dependencies?(deps)
        @resolved_specs = materialize_locked
        gem_specs = @resolved_specs.select { |spec| spec.source_type == "GEM" }
        available = gem_specs.all? do |spec|
          index_specs_for(spec.name)
          @local_installed_full_names.includes?(spec.full_name) || !vendor_cache_specs(spec.name).empty?
        end
        # The reference only announces a resolve when one really happens: with
        # the locked platforms covering the local platform every spec is
        # materialized straight from the bundle/cache and no
        # `Resolving dependencies...` line is printed. A lock that lists only
        # `ruby` (or a platform we cannot satisfy) still triggers the resolve
        # announcement before the installer reports the missing package.
        platform_ready = @definition.lockfile!.platforms.any? do |entry|
          next false if entry == "ruby"
          next true if entry == Gem::Platform.local.to_s
          begin
            Gem::Platform.new(entry).match?(Gem::Platform.local)
          rescue
            false
          end
        end
        @progress.puts "Resolving dependencies..." if @show_resolving && available && !platform_ready
        return @resolved_specs
      end

      # `source/git.rb:76-81`: a source change makes the locked spec ineligible;
      # drop it from the locked index so the solver would otherwise keep the
      # old conservative pin even though the Gemfile points at a new tag.
      if @definition.lockfile_exists?
        @definition.changed_dependency_sources(@evaluation.dependencies, @evaluation.sources).each do |name|
          @excluded_locked_names << name
        end
      end

      # `definition.rb:699-708`: a frozen bundle re-raises the lockfile
      # dependency mismatch (`lazy_specification.rb:259-270`) instead of
      # re-resolving, so validate before the reuse decision is taken.
      if @definition.lockfile_exists? && (@definition.config["frozen"] == true || @autoheal_locked_edges)
        @resolved_specs = materialize_locked
        if (stale = stale_locked_dependency_full_names).any?
          if @definition.config["frozen"] == true
            announce_index_fetch_for(stale.first)
            raise IncorrectLockfileDependenciesError.new("Bundler found incorrect dependencies in the lockfile for #{stale.first}")
          end
          # `definition.rb:699-708` heals by `reresolve_without([spec])`: the
          # offending rows leave the locked index so their dependencies come
          # back from the index, and the retry prints the second
          # `Resolving dependencies...` line. The rows are NOT added to
          # `@gems_to_unlock`: `reresolve_without` only deletes from the
          # resolution base (`definition.rb:782-785`), while `Resolver::Base`
          # still receives the untouched `@originally_locked_specs`
          # (`definition.rb:1323`), so the locked version stays the preferred
          # one and completing an edge never upgrades a locked gem.
          announce_index_fetch_for(stale.first)
          stale.compact_map do |full_name|
            @resolved_specs.find { |spec| spec.full_name == full_name }.try(&.name)
          end.each { |name| @excluded_locked_names << name }
          @heal_locked_edges = true
          # `resolver.rb:34` prints one `Resolving dependencies...` per
          # `start_resolution`. A lock whose platforms cover the host needs no
          # resolve before the heal, so the reference emits exactly one line
          # (the heal's own); a `ruby`-only lock resolves both before and after
          # and prints two. Measured 4.0.24 on `fixtures/gem-index-locked-deps`:
          # `x64-mingw-ucrt` lock → 1 line, `ruby` lock → 2 lines.
          @progress.puts "Resolving dependencies..." unless locked_platform_covers_local?
        end
      end

      if reuse && reuse_locked_resolution?(deps)
        # Reference `Installer#ensure_specs_are_compatible!` only runs after
        # `setup_domain!` re-resolved (`installer.rb:79-82, 234-245`). A locked
        # spec that still needs installing is checked against the current
        # Ruby/RubyGems; an incompatible pin is unlocked so the solver reports
        # the reference's "Because every version…" failure instead of
        # materializing (or blindly installing) the gem.
        incompatible = verify_locked_compat ? incompatible_locked_spec_names : [] of String
        if incompatible.empty?
          @resolved_specs = materialize_locked
          # `lazy_specification.rb:259-270` compares the lockfile's recorded
          # dependencies with the spec materialized from the index during a strict
          # (install) materialization; a mismatch means the lock is missing a
          # dependent spec. `definition.rb:699-708` raises when frozen and
          # otherwise re-resolves `without` the offending spec.
          stale = stale_locked_dependency_full_names
          if stale.empty?
            return @resolved_specs
          end
          if @definition.config["frozen"] == true
            announce_index_fetch_for(stale.first)
            raise IncorrectLockfileDependenciesError.new("Bundler found incorrect dependencies in the lockfile for #{stale.first}")
          end
          announce_index_fetch_for(stale.first)
          # `definition.rb:699-708` heals by `reresolve_without([spec])`: the
          # offending rows leave the locked index, so their dependencies come
          # back from the index instead of the lockfile row, and the retry emits
          # the second `Resolving dependencies...` line.
          # `reresolve_without` deletes the rows from the resolution BASE only
          # (`definition.rb:782-785` -> `resolver/base.rb:39-41`); it never adds
          # them to `@gems_to_unlock`, and `Resolver::Base` keeps receiving the
          # untouched `@originally_locked_specs` (`definition.rb:1323`), so
          # `Package#locked_version` still reports the locked version and the
          # promoter keeps preferring it. Measured 4.0.24: `net-smtp` stays
          # 0.5.0 while its missing `net-protocol` edge is restored.
          stale.compact_map do |full_name|
            @resolved_specs.find { |spec| spec.full_name == full_name }.try(&.name)
          end.each do |name|
            @excluded_locked_names << name
          end
          @heal_locked_edges = true
        end
        unlocked = @unlock.is_a?(Array(String)) ? @unlock.as(Array(String)) : [] of String
        @unlock = (unlocked + incompatible).uniq
        incompatible.each { |name| @excluded_locked_names << name }
      end

      # `definition.rb:973-1015 check_lockfile` runs during `Definition#initialize`
      # for every command, but only a command that actually writes the lockfile
      # (i.e. `lock`, which has no "skip the write" short circuit in
      # `cli/lock.rb:78-97`) observes the consequence. Drop the incomplete rows
      # before the resolve so their locked candidate, their preferred version and
      # their `>= locked` floor all disappear together, exactly as
      # `@locked_specs.delete(rows)` does in the reference (it deletes from the
      # object `@originally_locked_specs` aliases).
      if @drop_incomplete_locked_specs
        incomplete_locked_spec_names.each do |name|
          @dropped_locked_names << name
          @excluded_locked_names << name
        end
      end

      @resolved_specs = run_resolution(deps)
      @root_dependency_names = deps.map(&.name)
      @resolved_specs
    end

    # Names (full names) whose index spec declares different dependencies than
    # the lockfile row: the "missing dependent specs" case. Local-only
    # resolutions cannot consult the index, and the reference skips validation
    # for `StubSpecification` outside strict mode (`lazy_specification.rb:262-268`).
    private def stale_locked_dependency_full_names : Array(String)
      return [] of String if @local_only
      specs = @resolved_specs
      stale = [] of String
      previous = @progress
      @progress = IO::Memory.new
      # The probe must not consume the fetch announcement the real resolution
      # still owes the caller: save the fetch bookkeeping and restore it below.
      logged = @index_fetch_logged
      logged_remotes = @fetch_logged_remotes.dup
      replayed = @fetch_replayed
      probed = [] of String
      begin
        specs.each do |spec|
          next unless spec.source_type == "GEM"
          probed << spec.name
          index = begin
            index_specs_for(spec.name)
          rescue
            next
          end
          candidate = index.find { |s| s.version == spec.version && (s.platform_ruby? ? spec.platform_ruby? : s.platform.to_s == spec.platform) } ||
                      index.find { |s| s.version == spec.version }
          next unless candidate
          remote = candidate.dependencies.map(&.name).reject("bundler").sort
          locked = spec.dependencies.map(&.name).reject("bundler").sort
          stale << spec.full_name unless remote == locked
        end
      ensure
        @progress = previous
        unless stale.any?
          @index_fetch_logged = logged
          @fetch_logged_remotes = logged_remotes
          @fetch_replayed = replayed
          # The probe cached these names, so the real resolution would reuse
          # them silently; drop them and let it fetch and announce the index
          # itself, keeping the original line order.
          probed.each { |name| @index_specs_cache.try &.delete(name) }
        end
      end
      stale
    end

    # The reference's fetch note is emitted by the resolution it then performs;
    # our validation fetch above is silent, so replay the line here before the
    # re-resolution or the frozen error.
    private def announce_index_fetch_for(_name : String) : Nil
      remote = primary_remote
      return if remote.empty?
      # The validation fetch above already registered the remote with
      # `#log_fetch_for`, so replay the line exactly once here.
      return if @fetch_replayed
      @fetch_replayed = true
      @index_fetch_logged = true
      @fetch_logged_remotes << remote
      if remote.starts_with?("file:")
        @progress.puts "Fetching source index from #{remote}"
      else
        @progress.puts "Fetching gem metadata from #{remote}."
      end
    end

    # Dependency path from a top-level Gemfile dependency down to `name`
    # (reference `In Gemfile:` tree). Breadth-first over resolved dependency
    # edges; an unreachable name yields a single-element path so the caller can
    # still print `In Gemfile:\n  <name>`.
    def dependency_tree_for(name : String) : Array(NamedTuple(name: String, version: String?))
      resolve! unless @resolved
      by_name = {} of String => ResolvedSpec
      @resolved_specs.each { |spec| by_name[spec.name] ||= spec }
      roots = if @root_dependency_names.empty?
                begin
                  @definition.lockfile!.dependencies.map(&.name)
                rescue
                  [] of String
                end
              else
                @root_dependency_names
              end
      seen = {} of String => Bool
      queue = roots.map { |root| [root] }
      while path = queue.shift?
        current = path.last
        next if seen[current]?
        seen[current] = true
        if current == name
          return path.map { |entry| {name: entry, version: by_name[entry]?.try(&.version.to_s)} }
        end
        spec = by_name[current]?
        next unless spec
        spec.dependencies.each do |dep|
          queue << (path + [dep.name]) unless path.includes?(dep.name)
        end
      end
      [{name: name, version: by_name[name]?.try(&.version.to_s)}]
    end

    # Suppressed on locked-path installs (the reference prints no
    # "Resolving dependencies..." there).
    property show_resolving : Bool = true

    # `Definition#converge_dependencies` (`definition.rb:1051-1109`): a Gemfile
    # dependency the lockfile does not list at all counts as an unresolved
    # change, which sends `Definition#resolve` (`:342-366`) down the resolve
    # path instead of reusing the locked specs. Callers keep that distinction
    # for `--local` so a newly named dependency is looked up in the installed
    # gems (and reported as not found) rather than reused from the lock.
    private def lockfile_covers_all_dependencies?(deps : Array(Resolver::DepSpec)) : Bool
      return true unless @definition.lockfile_exists?
      names = @definition.lockfile!.sources.flat_map(&.specs).map(&.name).to_set
      deps.all? { |dep| names.includes?(dep.name) }
    end

    private def top_level_deps : Array(Resolver::DepSpec)
      deps = [] of Resolver::DepSpec
      seen = Set(String).new
      @evaluation.dependencies.each do |dep|
        next if dep.gemspec_dev_dep
        next unless seen.add?(dep.name)
        deps << Resolver::DepSpec.new(dep.name, Gem::Requirement.new(dep.requirements))
      end
      deps
    end

    # Locked-path reuse: identical dependencies + sources mean the lockfile is
    # still valid; no network needed (architecture §2.3 execution path 1).
    def reuse_locked? : Bool
      reuse_locked_resolution?(top_level_deps)
    end

    def top_level_dependencies : Array(Resolver::DepSpec)
      top_level_deps
    end

    private def reuse_locked_resolution?(deps : Array(Resolver::DepSpec)) : Bool
      return false if @unlock == true || (@unlock.is_a?(Array(String)) && !@unlock.as(Array(String)).empty?)
      return false unless @definition.lockfile_exists?

      lockfile = @definition.lockfile!
      return false unless lockfile.valid?
      # The setting changes which spec row is materialized, so a lock written
      # for the native platform cannot be reused as-is (`definition.rb:662`
      # only short-circuits the EXTRA-platform pass; the resolver still runs
      # against the ruby platform). Measured on 4.0.24/2.7.2: `install` with
      # the setting re-resolves, fetches `platdemo 1.0.0` and keeps the native
      # row in the lockfile.
      return false if force_ruby_platform?

      locked_deps = lockfile.dependencies
      return false unless locked_deps.size == deps.size

      all_ok = deps.all? do |dep|
        locked = locked_deps.find(&.name.==(dep.name))
        next false unless locked
        locked.requirement == dep.requirement
      end
      return false unless all_ok
      # Reference `converge_dependencies` (definition.rb:1051-1076) and
      # `check_lockfile` (definition.rb:973-1014): the locked specs must cover
      # every dependency, otherwise `@missing_lockfile_dep` (etc.) makes
      # `something_changed?` (definition.rb:630-645) true and we re-resolve.
      return false unless lockfile_covers_dependencies?(lockfile, deps)
      # `source/git.rb:76-81` includes uri/ref/branch/glob/submodules in source
      # identity; a changed tag must re-resolve instead of rewriting the old
      # lockfile. `source_diff` already owns the reference label rendering.
      return false if @definition.dependency_sources_changed?(@evaluation.dependencies, @evaluation.sources)
      # `definition.rb:929-950` (`specs_changed?` -> `converge_paths`): for a
      # PATH source the LOCKED source object is authoritative
      # (`source_list.rb:208-217 replace_path_source`), so a glob change in the
      # Gemfile never re-resolves; only a changed visible spec set does.
      return false if path_specs_changed?
      return false unless sources_compatible?(lockfile)
      # Reference parity: a lockfile that does not cover the local platform
      # (no `ruby`, no matching entry) makes the definition re-resolve
      # (current_platform_missing -> something_changed?), so the locked path
      # does not apply.
      return false unless covers_local_platform?(lockfile)

      ruby_compatible?(lockfile)
    end

    # `definition.rb:929-950` (`specs_for_source_changed?`): compare the locked
    # specs against the specs the source exposes now. The locked PATH source is
    # authoritative (`source_list.rb:208-217 replace_path_source`), so the glob
    # comes from the lockfile: a Gemfile glob change alone never re-resolves,
    # while a gemspec version bump visible under the locked glob does.
    def path_specs_changed? : Bool
      cached = @path_specs_changed
      return cached unless cached.nil?
      @path_specs_changed = !Resolution.stale_path_specs(@definition, @bridge, @evaluation).empty?
    end

    # Locked PATH specs that the source no longer exposes under its LOCKED glob.
    def self.stale_path_specs(definition : Definition, bridge : Bridge::Client?,
                              evaluation : Bridge::GemfileEvaluation) : Array(Lockfile::Spec)
      stale = [] of Lockfile::Spec
      return stale unless bridge
      return stale unless definition.lockfile_exists?
      lockfile = definition.lockfile!
      root = File.dirname(definition.gemfile_path)
      evaluation.dependencies.each do |dep|
        source = dep.source
        next unless source && source.type == "Path"
        section = lockfile.sources.find do |candidate|
          candidate.type == "PATH" && candidate.specs.any? { |spec| spec.name == dep.name }
        end
        next unless section
        remote = section.remote || section.option("path").as?(String)
        next unless remote
        glob = section.option("glob").as?(String) || DEFAULT_GLOB
        dir = File.expand_path(remote, root)
        visible = begin
          bridge.load_gemspec_dir_specs(dir, glob).map { |spec| "#{spec.name}-#{spec.version}" }
        rescue Bridge::BridgeError
          next
        end
        section.specs.each do |locked|
          stale << locked unless visible.includes?("#{locked.name}-#{locked.version}")
        end
      end
      stale
    end

    # `@missing_lockfile_dep` / `@locked_spec_with_missing_deps` /
    # `@locked_spec_with_invalid_deps` equivalents: an empty `specs:` section
    # (or a dependency edge pointing at a gem that is not locked, or at a
    # locked version outside the requirement) must not be reused, otherwise
    # `materialize_locked` would silently install nothing.
    private def lockfile_covers_dependencies?(lockfile : Lockfile::Data,
                                              deps : Array(Resolver::DepSpec)) : Bool
      locked = Hash(String, Array(Lockfile::Spec)).new
      lockfile.sources.each do |source|
        source.specs.each do |spec|
          (locked[spec.name] ||= [] of Lockfile::Spec) << spec
        end
      end

      deps.each do |dep|
        next if dep.name == "bundler"
        return false unless locked.has_key?(dep.name)
      end

      locked.each_value do |specs|
        specs.each do |spec|
          spec.dependencies.each do |edge|
            targets = locked[edge.name]?
            return false unless targets
            return false unless targets.any? { |target| edge.requirement.satisfied_by?(Gem::Version.new(target.version)) }
          end
        end
      end

      true
    end

    # Reference `current_platform_locked?`: `ruby` covers every local platform
    # (it is the generic platform for non-Windows hosts), otherwise an exact
    # local entry is required.
    def covers_local_platform?(lockfile : Lockfile::Data) : Bool
      local = Gem::Platform.local.to_s
      lockfile.platforms.any? { |p| p == "ruby" || p == local }
    end

    # True only when the lockfile lists a NON-`ruby` platform that matches the
    # running host (e.g. `x64-mingw-ucrt` here). A `ruby`-only lock does not
    # count: the reference resolves it before the lockfile-dependency heal as
    # well, which is why that shape prints two `Resolving dependencies...`
    # lines instead of one.
    private def locked_platform_covers_local? : Bool
      return false unless @definition.lockfile_exists?
      lockfile = @definition.lockfile!
      lockfile.platforms.any? do |entry|
        next false if entry == "ruby"
        next true if entry == Gem::Platform.local.to_s
        begin
          Gem::Platform.new(entry).match?(Gem::Platform.local)
        rescue
          false
        end
      end
    end

    # Reference `Bundler::MatchPlatform.generic_local_platform_is_ruby?`:
    # `Gem::Platform.generic` maps non-Windows/non-Java local platforms to
    # `ruby`.
    def generic_local_platform_is_ruby? : Bool
      !(Gem::Platform.local.to_s =~ /mingw|mswin|java/)
    end

    private def sources_compatible?(lockfile : Lockfile::Data) : Bool
      remote = primary_remote
      normalized_remote = normalize_remote(remote)
      lockfile.sources.all? do |source|
        next true unless source.type == "GEM"
        source.remotes.any? { |r| normalize_remote(r) == normalized_remote }
      end
    end

    private def normalize_remote(remote : String) : String
      return File.expand_path(remote.lchop("file:").lstrip('/')).chomp('/') if remote.starts_with?("file:")
      remote
    end

    private def ruby_compatible?(lockfile : Lockfile::Data) : Bool
      Resolution.ruby_compatible?(@evaluation.ruby, lockfile.ruby_version)
    end

    # Pure helper for Gemfile-declared Ruby vs lockfile Ruby compatibility.
    # Exposed for the M7 constraint matrix; `ruby_compatible?` delegates here.
    def self.ruby_compatible?(requested_ruby : String?, locked_ruby : String?) : Bool
      return true if requested_ruby.nil? && locked_ruby.nil?
      return false if requested_ruby.nil? != locked_ruby.nil?
      return false unless requested_ruby && locked_ruby

      requested = Celerite::RubyVersion.parse_requirement(requested_ruby)
      locked = Celerite::RubyVersion.from_string(locked_ruby) ||
               Celerite::RubyVersion.parse_requirement(locked_ruby)
      return locked_ruby == requested_ruby unless requested && locked

      # Locked ruby must satisfy the requested declaration (Bundler-style diff).
      requested.diff(locked).nil?
    rescue
      locked_ruby == requested_ruby
    end

    # Reference `Gem::Specification#matches_current_ruby?` /
    # `matches_current_rubygems?` (`installer.rb:234-245`). The lockfile carries
    # no requirements, so consult the compact index; names whose entry is absent
    # (or whose lookup fails offline) stay trusted — reuse is offline-first.
    private def incompatible_locked_spec_names : Array(String)
      names = [] of String
      env = @bridge.not_nil!.ruby_environment
      ruby = Gem::Version.new(env.ruby_version)
      rubygems = Gem::Version.new(env.rubygems_version)
      @definition.lockfile!.sources.each do |source|
        next unless source.type == "GEM"
        source.specs.each do |locked|
          version = Gem::Version.new(locked.version)
          platform = locked.platform || "ruby"
          # A locked default gem is satisfied by the interpreter itself; do not
          # hit the index just to prove it (also avoids a spurious Fetching
          # line on a reused lock).
          if default_gem = @bridge.not_nil!.default_gem_spec(locked.name)
            next if default_gem[:version] == locked.version && default_gem[:platform] == platform
          end
          match = index_specs_for(locked.name).find do |candidate|
            candidate.version == version && candidate.platform.to_s == platform
          end
          next unless match
          unless match.required_ruby_version.satisfied_by?(ruby) &&
                 match.required_rubygems_version.satisfied_by?(rubygems)
            names << locked.name
          end
        end
      end
      names
    rescue
      # Only a positive index answer may veto reuse (see the offline note above).
      [] of String
    end

    private def materialize_locked : Array(ResolvedSpec)
      lockfile = @definition.lockfile!
      specs = [] of ResolvedSpec
      lockfile.sources.each do |source|
        source_info = locked_source_info(source)
        # GEM sections keep the resolved remote out of `source_remote`: the
        # reuse path never re-groups them, and the existing emission logic
        # already falls back to `primary_remote` there.
        source_remote = source.type == "PLUGIN SOURCE" ? source.remote : nil
        type = locked_source_type(source.type)
        source_declared = type == "GEM" || type == "PLUGIN SOURCE" ? nil : source.remote
        rows = source.specs.map do |spec|
          # Checksums are per platform row: the ruby row of a gem that also has
          # a native row stays digestless (measured 4.0.24 lock output).
          checksum = lockfile.checksums.find do |c|
            c.name == spec.name && c.version == spec.version &&
              (c.platform.nil? || c.platform == "ruby") == (spec.platform.nil? || spec.platform == "ruby") &&
              (spec.platform.nil? || spec.platform == "ruby" || c.platform == spec.platform)
          end
          ResolvedSpec.new(spec.name, Gem::Version.new(spec.version), spec.platform,
            spec.dependencies, checksum.try(&.checksums.first?), 0, type, source_info, source_remote).tap { |row| row.source_declared = source_declared }
        end
        rows.each { |row| specs << row }
      end
      # A lock written for several platforms can carry more than one row per
      # gem. The reference installs and counts only the row materialized for the
      # local platform (`definition.specs`), while the lockfile re-emits every
      # variant (`resolver.rb:88-89`, `spec_set.rb:184-185`). Keep the surplus
      # rows out of the install set but still emit them: measured `install` on a
      # two-row `platdemo` lock installs one gem on both 4.0.24 and 2.7.2.
      local = Gem::Platform.local
      extras = [] of ResolvedSpec
      specs.group_by { |spec| "#{spec.name}-#{spec.version}" }.each do |_, group|
        gem_rows = group.select(&.source_type.==("GEM"))
        next if gem_rows.size < 2
        installable = gem_rows.select do |spec|
          spec.platform_ruby? || Gem::Platform.new(spec.platform.not_nil!).match?(local)
        end
        best = installable.min_by? do |spec|
          spec_platform = spec.platform_ruby? ? Gem::Platform.new("ruby") : Gem::Platform.new(spec.platform.not_nil!)
          Gem::Platform.platform_specificity_match(spec_platform, local)
        end || gem_rows.first
        gem_rows.each { |spec| extras << spec unless spec.platform == best.platform }
      end
      @lock_extra_specs = extras.sort_by(&.full_name)
      extras.empty? ? specs : specs.reject { |spec| spec.in?(extras) }
    end

    # Lock section type -> `ResolvedSpec#source_type`; `generated_lockfile`
    # groups non-GEM specs by tag ("PATH"/"GIT"/"PLUGIN").
    private def locked_source_type(type : String) : String
      case type
      when "PATH"          then "PATH"
      when "GIT"           then "GIT"
      when "PLUGIN SOURCE" then "PLUGIN"
      else                      "GEM"
      end
    end

    # Rebuilds the non-GEM source descriptor from the lockfile section so that
    # a reused lockfile re-emits its `PATH`/`GIT`/`PLUGIN SOURCE` blocks
    # verbatim. Reference `Source::Path#from_lock`/`Git#from_lock`
    # (source/path.rb:41-43, source/git.rb:39-48) replay the locked options into
    # the source object; `lockfile_generator.rb:31-42` then writes
    # `source.to_lock` from that object, not from the Gemfile.
    private def locked_source_info(source : Lockfile::SourceSection) : SourceInfo?
      case source.type
      when "PLUGIN SOURCE"
        plugin_source_info(source)
      when "PATH"
        glob = source.option("glob").as?(String) || DEFAULT_GLOB
        SourceInfo.from_json({
          "type" => "Path", "remote" => source.remote || "",
          "glob" => glob, "revision" => nil,
        }.to_json)
      when "GIT"
        glob = source.option("glob").as?(String)
        SourceInfo.from_json({
          "type" => "Git", "remote" => source.remote || "",
          "revision" => source.option("revision").as?(String),
          "ref" => source.option("ref").as?(String),
          "branch" => source.option("branch").as?(String),
          "tag" => source.option("tag").as?(String),
          "submodules" => source.option("submodules") == true,
          "glob" => glob,
        }.to_json)
      else
        nil
      end
    end

    # Rebuilds the plugin source metadata from a `PLUGIN SOURCE` lockfile
    # section (`plugin/api/source.rb:45-52,283-295`): the lockfile records the
    # `type` as a lock option and the remaining options are replayed into the
    # plugin's `initialize` when the plugin is loaded.
    private def plugin_source_info(source : Lockfile::SourceSection) : SourceInfo
      lock_options = {} of String => String
      plugin_type = nil.as(String?)
      source.options.each do |option|
        value = option.value
        next unless value.is_a?(String)
        if option.key == "type"
          plugin_type = value
        elsif option.key != "remote"
          lock_options[option.key] = value
        end
      end
      SourceInfo.from_json({
        "type" => "Plugin", "remote" => source.remote || "",
        "plugin_type" => plugin_type, "lock_options" => lock_options,
      }.to_json)
    end

    # Reuse-path repair for stale dependency edges. The lockfile records each
    # locked spec's edges and the reuse path trusts them, so a lockfile written
    # without them (Bundler's locked specs report an empty dependency list —
    # `lazy_specification.rb:26-39`, which is why `check_lockfile`
    # `definition.rb:973-1014` never flags the gap) would stay stale forever.
    # The reference repairs the edges from materialized gemspecs
    # (`spec_set.rb#materialize`) while keeping every locked version, so we
    # refresh them from the .gem packages fetched for this run.
    #
    # Only GEM sources are refreshed, and only from the locked/reuse path: a
    # fresh resolve already carries the index metadata (including platform
    # variants) and must not be rewritten, while PATH/GIT specs keep the edges
    # recorded in the lockfile.
    # Returns true when at least one spec's dependency edges were rewritten.
    def refresh_locked_dependencies(packages : Hash(String, String), & : String -> Array(Lockfile::SpecDependency)) : Bool
      return false if packages.empty?
      changed = false
      @resolved_specs = @resolved_specs.map do |spec|
        next spec unless spec.source_type == "GEM"
        package = packages[spec.full_name]?
        next spec if package.nil?
        dependencies = yield package
        next spec if dependencies == spec.dependencies
        changed = true
        ResolvedSpec.new(spec.name, spec.version, spec.platform, dependencies, spec.checksum,
          spec.source_index, spec.source_type, spec.source_info, spec.source_remote,
          spec.required_ruby_version, spec.required_rubygems_version, spec.default_gem)
      end
      changed
    end

    private def run_resolution(deps : Array(Resolver::DepSpec)) : Array(ResolvedSpec)
      unlocked = Set(String).new
      prerelease_exceptions = Set(String).new

      base_requirements = build_base_requirements(unlocked)
      index = build_index(deps)
      locked_index = build_locked_index
      remember_relaxation_state(base_requirements, index)

      # GEM specs fetch lazily from the compact index during resolution
      # (pinned: the index fetch lands relative to "Resolving dependencies..."
      # depending on whether root deps need it).
      fetcher = Proc(String, Array(Resolver::IndexSpec)).new do |name|
        index_specs_for(name)
      end
      source = make_source(base_requirements, index, locked_index, prerelease_exceptions, @unlock, fetcher)

      orchestrator = begin
        Resolver::Orchestrator.new(source, deps)
      rescue ex : Resolver::SolveFailure
        # Root-dependency validation runs in the Orchestrator constructor. A
        # metadata-only solve failure happens after the reference has already
        # announced resolution, while missing/platform errors happen earlier
        # and do not print it (pinned oracle behavior).
        # `--local` never announces a resolve: the reference materializes from the
        # installed specs only (`sources.local_only!`) and reports not-found.
        @progress.puts "Resolving dependencies..." if @show_resolving && !@local_only
        raise ex
      end
      # `--local` announces the resolve only once it actually succeeded: the
      # reference materializes from the installed specs only
      # (`sources.local_only!`) and a not-found error therefore prints nothing.
      @progress.puts "Resolving dependencies..." if @show_resolving && !@local_only
      decisions = solve_with_relaxation(source, deps, prerelease_exceptions, unlocked, orchestrator)
      specs = decisions_to_specs(decisions, index, locked_index)
      @progress.puts "Resolving dependencies..." if @show_resolving && @local_only
      specs
    end

    private def make_source(base_requirements : Hash(String, Gem::Requirement),
                            index : Hash(String, Array(Resolver::IndexSpec)),
                            locked_index : Hash(String, Array(Resolver::IndexSpec)),
                            prerelease_exceptions : Set(String),
                            unlock : Bool | Array(String) = false,
                            spec_fetcher : (String -> Array(Resolver::IndexSpec))? = nil) : Resolver::ResolutionSource
      env = @bridge.not_nil!.ruby_environment
      # `Source::Rubygems#to_s` (4.0.24 lib/bundler/source/rubygems.rb:122-136):
      # with `@allow_remote` off the source only describes installed gems, which
      # is what `fund`/`clean`/`binstubs` report for a missing gem.
      description = if @local_only
                      # `setup_domain!` calls `sources.cached!` before `local!`
                      # (definition.rb:190-203), and `cached!` is a no-op unless
                      # the app cache exists (source/rubygems.rb:69-76). So an
                      # `--local` source with `vendor/cache` present describes
                      # itself as "cached gems or installed locally"
                      # (rubygems.rb:122-136).
                      if app_cache_present?
                        "cached gems or installed locally"
                      else
                        "locally installed gems"
                      end
                    elsif @remote_only
                      "rubygems repository #{primary_remote}, cached gems or installed locally"
                    else
                      "rubygems repository #{primary_remote} or installed locally"
                    end
      # Reference `Source::Path#to_s` = "source at `<path>`" and
      # `Source::Plugin#to_s` = "plugin source for <type> with uri <uri>"
      # (plugin/api/source.rb:293-296); `Resolver#raise_not_found!` prints the
      # dependency's own source. GIT attribution stays on the legacy rubygems
      # wording (declared compatibility gap).
      source_descriptions = {} of String => String
      non_gem_sources.each do |name, info|
        case info.type
        when "Path"
          source_descriptions[name] = "source at `#{info.remote}`"
        when "Plugin"
          source_descriptions[name] = "plugin source for #{info.plugin_type} with uri #{info.remote}"
        end
      end
      source = Resolver::ResolutionSource.new(
        File.basename(@definition.gemfile_path),
        description,
        index,
        locked_index,
        base_requirements,
        Gem::Platform.local,
        unlock,
        spec_fetcher,
        resolution_platforms,
        env.ruby_version,
        env.rubygems_version,
        env.engine,
        env.engine_version,
        env.patchlevel,
        source_descriptions,
        # `Resolver#raise_not_found!` adds this suffix whenever the app cache
        # directory exists (resolver.rb:334-361).
        app_cache_present? ? " or in gems cached in #{app_cache_label}" : nil,
        # `definition.rb:1323` hands `Resolver::Base` the untouched
        # `@originally_locked_specs`, so a row the heal removed from the
        # candidate list still supplies the preferred version.
        preferred_locked_versions,
      )
      prerelease_exceptions.each { |name| source.package_consider_prereleases(name) }
      source
    end

    private def remember_relaxation_state(base_requirements : Hash(String, Gem::Requirement),
                                          index : Hash(String, Array(Resolver::IndexSpec))) : Nil
      @current_base_requirements = base_requirements
      @current_index = index
      @prerelease_available = Set(String).new
      index.each do |name, specs|
        @prerelease_available << name if specs.any?(&.version.prerelease?)
      end
    end

    private def solve_with_relaxation(source : Resolver::ResolutionSource, deps : Array(Resolver::DepSpec),
                                      prerelease_exceptions : Set(String), unlocked : Set(String),
                                      orchestrator : Resolver::Orchestrator? = nil,
                                      fetcher : (String -> Array(Resolver::IndexSpec))? = nil) : Hash(Resolver::Package, Resolver::CandidateVersion)
      orchestrator ||= Resolver::Orchestrator.new(source, deps)
      begin
        return orchestrator.solve
      rescue ex : Resolver::SolveFailure
        names = find_names_to_relax(ex.incompatibility)
        new_prereleases = names[:prerelease].reject { |n| prerelease_exceptions.includes?(n) }.to_set
        new_unlocks = names[:unlock].reject { |n| unlocked.includes?(n) }.to_set

        if !new_prereleases.empty? || !new_unlocks.empty?
          new_prereleases.each { |name| prerelease_exceptions << name }
          new_unlocks.each { |name| unlocked << name }

          base = build_base_requirements(unlocked)
          index = build_index(deps)
          locked_index = build_locked_index
          remember_relaxation_state(base, index)
          source = make_source(base, index, locked_index, prerelease_exceptions, @unlock, fetcher)
          return solve_with_relaxation(source, deps, prerelease_exceptions, unlocked, orchestrator: nil, fetcher: fetcher)
        end

        raise ex
      end
    end

    # Simplified port of `Resolver#find_names_to_relax`.
    private def find_names_to_relax(incompatibility : Resolver::Incompatibility) : {unlock: Set(String), prerelease: Set(String)}
      unlock_names = Set(String).new
      prerelease_names = Set(String).new

      current = incompatibility
      while current.conflict?
        cause = current.cause.as(Resolver::IncompatibilityCause::Conflict)
        current = cause.incompatibility

        current.terms.each do |term|
          name = term.package.name
          unlock_names << name if @current_base_requirements.has_key?(name)
          prerelease_names << name if @prerelease_available.includes?(name)
        end
      end

      {unlock: unlock_names, prerelease: prerelease_names}
    end

    # Reference `SpecGroup#merge`/`equivalent?` (bundler resolver.rb:285-293):
    # when a platform variant's dep set equals the ruby variant's, the ruby
    # candidate group carries both, and materialization still picks the
    # local-platform variant.
    private def platform_mergeable?(specs : Array(Resolver::IndexSpec)?) : Bool
      return false unless specs
      ruby = specs.select(&.platform_ruby?)
      plat = specs.reject(&.platform_ruby?)
      return false if ruby.empty? || plat.empty?

      signature = ->(s : Resolver::IndexSpec) { s.dependencies.map { |d| "#{d.name} #{d.requirement}" }.sort.join("|") }
      ruby_sigs = ruby.map { |s| signature.call(s) }.uniq
      plat_sigs = plat.map { |s| signature.call(s) }.uniq
      ruby_sigs == plat_sigs
    end

    private def decisions_to_specs(decisions : Hash(Resolver::Package, Resolver::CandidateVersion),
                                   index : Hash(String, Array(Resolver::IndexSpec)),
                                   locked_index : Hash(String, Array(Resolver::IndexSpec))) : Array(ResolvedSpec)
      specs = [] of ResolvedSpec
      variants_out = [] of ResolvedSpec
      decisions.each do |package, candidate_version|
        next if package.root? || package.meta?
        name = package.name
        same_version = index[name]?.try(&.select { |s| s.version == candidate_version.version }) ||
                       locked_index[name]?.try(&.select { |s| s.version == candidate_version.version })
        chosen =
          if force_ruby_platform?
            # `Gemfile.lock` under `BUNDLE_FORCE_RUBY_PLATFORM` lists the generic
            # variant only: `MatchPlatform.select_best_platform_match` runs
            # against `Gem::Platform::RUBY` (`match_platform.rb:28`,
            # `lazy_specification.rb:221`). Measured 4.0.24/2.7.2: the lock holds
            # `platdemo (1.0.0)` and install fetches `platdemo 1.0.0`.
            ruby_only = index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? }) ||
                        locked_index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? })
            ruby_only ? [ruby_only] : [] of Resolver::IndexSpec
          elsif candidate_version.priority == 1 || platform_mergeable?(same_version)
            # Platform-variant candidate, or a ruby candidate whose group carries
            # merged platform variants: materialize the local-platform variant
            # (reference `Materialization#specs` +
            # `MatchPlatform.select_best_platform_match`), falling back to the
            # ruby spec when no local-platform variant is indexed.
            variant = Resolver::ResolutionSource.select_variant(index, name, candidate_version.version) ||
                      Resolver::ResolutionSource.select_variant(locked_index, name, candidate_version.version) ||
                      index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? }) ||
                      locked_index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? })
            variant ? [variant] : [] of Resolver::IndexSpec
          else
            variant = index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? }) ||
                      locked_index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? })
            variant ? [variant] : [] of Resolver::IndexSpec
          end
        next if chosen.empty?

        source = non_gem_sources[name]?
        source_type = source ? source.type.upcase : "GEM"
        source_type = "PATH" if source_type == "GEMSPEC"
        source_remote = source ? (source.remote || "") : remote_for(name)
        chosen.each do |spec|
          lock_deps = spec.dependencies.map do |dep|
            Lockfile::SpecDependency.new(dep.name, dep.requirement.to_lock_requirements)
          end
          specs << ResolvedSpec.new(name, spec.version, spec.platform_ruby? ? nil : spec.platform.to_s, lock_deps, spec.checksum, 0, source_type, source, source_remote, spec.required_ruby_version, spec.required_rubygems_version, !spec.default_gem_path.nil?)
        end

        # Lockfile-only variants: the reference materializes the graph against
        # every `definition.platforms` entry (`definition.rb:813-819` →
        # `resolver.rb:88-89` + `spec_set.rb:184-185`, `:301-309`), so a platform
        # with no native variant falls back to the ruby spec and BOTH rows land in
        # the lockfile (measured: `lock --add-platform x64-mingw32` on 4.0.24 and
        # 2.7.2). They are not installed and not counted — the reference prints
        # `Bundle complete! 1 Gemfile dependency, 1 gem now installed.` for such a
        # lock (`cli/install.rb:93-96` counts `definition.specs`, i.e. the
        # materialized local set).
        next unless source_type == "GEM"
        best_match_variants(same_version, resolution_platforms).each do |variant|
          next if chosen.any? { |c| c.platform.to_s == variant.platform.to_s }
          lock_deps = variant.dependencies.map do |dep|
            Lockfile::SpecDependency.new(dep.name, dep.requirement.to_lock_requirements)
          end
          variants_out << ResolvedSpec.new(name, variant.version, variant.platform_ruby? ? nil : variant.platform.to_s, lock_deps, variant.checksum, 0, source_type, source, source_remote, variant.required_ruby_version, variant.required_rubygems_version)
        end
      end
      specs.sort_by!(&.full_name)
      @lock_extra_specs = variants_out.uniq { |spec| spec.full_name }.sort_by(&.full_name)
      specs
    end

    # Best platform match per resolution platform, mirroring
    # `MatchPlatform.select_best_platform_match` (match_platform.rb:12-16) with
    # the `platform.rb:326-348` specificity ordering. Ruby specs match every
    # platform, so a platform without a native variant selects the ruby spec.
    private def best_match_variants(specs : Array(Resolver::IndexSpec)?,
                                    platforms : Array(Gem::Platform)) : Array(Resolver::IndexSpec)
      return [] of Resolver::IndexSpec unless specs
      chosen = [] of Resolver::IndexSpec
      platforms.each do |platform|
        installable = specs.select { |s| s.platform_ruby? || s.platform.match?(platform) }
        next if installable.empty?
        best = installable.min_by { |s| Gem::Platform.platform_specificity_match(s.platform, platform) }
        chosen << best unless chosen.any? { |c| c.name == best.name && c.version == best.version && c.platform.to_s == best.platform.to_s }
      end
      chosen
    end

    def top_level_dependencies : Array(Resolver::DepSpec)
      top_level_deps
    end

    def build_base_requirements(unlocked : Set(String)) : Hash(String, Gem::Requirement)
      base = {} of String => Gem::Requirement
      @evaluation.dependencies.each do |dep|
        next if dep.gemspec_dev_dep
        requirement = Gem::Requirement.new(dep.requirements)
        base[dep.name] = base.has_key?(dep.name) ? Gem::Requirement.intersect(base[dep.name], requirement) : requirement
      end

      locked_specs_by_name.each do |name, specs|
        next if @unlock == true
        next if @unlock.is_a?(Array(String)) && @unlock.as(Array(String)).includes?(name)
        next if unlocked.includes?(name)
        next if @dropped_locked_names.includes?(name)
        locked_version = specs.first?.try(&.version)
        next unless locked_version
        next unless base.has_key?(name)
        next unless base[name].satisfied_by?(locked_version)

        floor = Gem::Requirement.new([">= #{locked_version}"])
        base[name] = Gem::Requirement.intersect(base[name], floor)
      end
      base
    end

    def build_index(deps : Array(Resolver::DepSpec)) : Hash(String, Array(Resolver::IndexSpec))
      index = {} of String => Array(Resolver::IndexSpec)
      queue = deps.map(&.name)
      seen = Set(String).new
      while name = queue.shift?
        next unless seen.add?(name)
        if source = non_gem_sources[name]?
          specs = index_for_source_gem(name, source)
          index[name] = specs
          specs.each do |spec|
            spec.dependencies.each do |dep|
              queue << dep.name unless seen.includes?(dep.name)
            end
          end
        elsif scoped_remote_for(name)
          index[name] = specs = index_specs_for(name)
          specs.each do |spec|
            spec.dependencies.each do |dep|
              queue << dep.name unless seen.includes?(dep.name)
            end
          end
        end
        # GEM-source specs are fetched lazily by ResolutionSource via the
        # spec_fetcher during resolution
      end
      index
    end

    # Path/git source gems: load their gemspec from the source location.
    # Git sources are cloned/checked out first (the reference fetches before
    # resolving).
    private def index_for_source_gem(name : String, source : SourceInfo) : Array(Resolver::IndexSpec)
      return plugin_source_specs(name, source) if source.type == "Plugin"
      dir = ensure_source_dir(name, source)
      spec = load_source_gem_spec(name, dir, source.glob)
      spec ? [spec] : [] of Resolver::IndexSpec
    end

    # Plugin source specs come from the plugin itself
    # (`Bundler::Plugin::API::Source#specs`, plugin/api/source.rb:136); the
    # bridge re-evaluates the Gemfile and materializes its gemspec list.
    private def plugin_source_specs(name : String, source : SourceInfo) : Array(Resolver::IndexSpec)
      remote = source.remote
      @plugin_specs_cache ||= {} of String => Array(Resolver::IndexSpec)
      if cached = @plugin_specs_cache.not_nil![remote]?
        return cached.select { |spec| spec.name == name }
      end
      result = @bridge.not_nil!.plugin_source_specs(@definition.gemfile_path, remote)
      specs = result.specs.map do |info|
        version = Gem::Version.new(info.version)
        platform = info.platform == "ruby" ? Gem::Platform::RUBY : Gem::Platform.new(info.platform)
        deps = (info.dependencies || [] of Bridge::PluginSpecDependency).map do |dep|
          reqs = dep.requirements
          Resolver::DepSpec.new(dep.name, reqs.empty? ? Gem::Requirement.new : Gem::Requirement.new(reqs))
        end
        Resolver::IndexSpec.new(info.name, version, platform, deps, Gem::Requirement.new, Gem::Requirement.new, nil)
      end
      @plugin_specs_cache.not_nil![remote] = specs
      specs.select { |spec| spec.name == name }
    end

    # Ensures the gemspec directory exists for the source; for git sources
    # performs the mirror clone/checkout and records the revision.
    def ensure_source_dir(name : String, source : SourceInfo) : String
      case source.type
      when "Path", "Gemspec"
        # path sources resolve relative to the Gemfile directory
        path = source.remote
        path = File.expand_path(path, File.dirname(@definition.gemfile_path)) unless File.exists?(path)
        path
      when "Git"
        bundle_root = File.join(install_path_root, "ruby", ruby_abi_for_git)
        git = GitSource.new(source.remote, bundle_root)
        revision = source.revision || git.fetch(branch: source.branch, tag: source.tag, ref: source.ref)
        source.revision = revision
        git.checkout(revision, source.submodules == true)
      else
        raise Error.new("unsupported source type #{source.type} for #{name}")
      end
    end

    def install_path_root : String
      InstallPaths.install_path(@definition.config)
    end

    def ruby_abi_for_git : String
      @ruby_abi_for_git ||= InstallPaths.ruby_abi(@bridge.not_nil!)
    end

    def build_locked_index : Hash(String, Array(Resolver::IndexSpec))
      index = {} of String => Array(Resolver::IndexSpec)
      lockfile = @definition.lockfile_exists? ? @definition.lockfile! : nil
      locked_specs.each do |locked|
        next if @excluded_locked_names.includes?(locked.name)
        case locked.source_type
        when "GEM"
          (index[locked.name] ||= [] of Resolver::IndexSpec) << Resolver::IndexSpec.new(
            locked.name, locked.version,
            locked.platform && locked.platform != "ruby" ? Gem::Platform.new(locked.platform.not_nil!) : Gem::Platform::RUBY,
            [] of Resolver::DepSpec, Gem::Requirement.new, Gem::Requirement.new, nil
          )
        when "PLUGIN SOURCE"
          source = lockfile.try(&.sources.find do |section|
            section.type == "PLUGIN SOURCE" && section.specs.any? { |spec| spec.name == locked.name }
          end)
          next unless source
          begin
            specs = plugin_source_specs(locked.name, plugin_source_info(source))
          rescue ex : Bridge::BridgeError
            # Plugin not installed: the reference's `UnloadedSource` yields an
            # empty spec list (`plugin.rb:202-211`), so the locked entry cannot
            # satisfy resolution. Keep the section intact for reuse and let the
            # caller surface the missing plugin.
            next
          end
          (index[locked.name] ||= [] of Resolver::IndexSpec).concat(specs)
        end
      end
      index
    end

    # ------------------------------------------------------------------
    # Lockfile generation
    # ------------------------------------------------------------------

    property switched_bundler : Bool = false
    property added_platforms : Array(String) = [] of String
    property removed_platforms : Array(String) = [] of String
    property normalize_platforms : Bool = false
    # `lock --add-checksums`: the reference records a CHECKSUMS section even
    # when the lockfile had none and the running profile would not enable
    # checksums by default (`cli/lock.rb:70` → `definition.add_checksums`).
    property add_checksums : Bool = false

    # Resolution platform set: local + existing lockfile platforms + added.
    def resolution_platforms : Array(Gem::Platform)
      # `BUNDLE_FORCE_RUBY_PLATFORM` resolves against the generic platform only
      # (`settings.rb:21` lists the key in `BOOL_KEYS`, `definition.rb:662`
      # short-circuits the extra-platform pass, `lazy_specification.rb:221` and
      # `match_platform.rb:28` force the ruby variant). Measured on 4.0.24 and
      # 2.7.2: the lock holds `platdemo (1.0.0)` and `PLATFORMS` has only
      # `  ruby`.
      platforms = [force_ruby_platform? ? Gem::Platform.new("ruby") : Gem::Platform.local]
      if @definition.lockfile_exists?
        @definition.lockfile!.platforms.each do |p|
          platform = Gem::Platform.new(p)
          platforms << platform unless platforms.any?(&.==(platform))
        end
      end
      @added_platforms.each do |p|
        platform = Gem::Platform.new(p)
        platforms << platform unless platforms.any?(&.==(platform))
      end
      @removed_platforms.each do |p|
        platform = Gem::Platform.new(p)
        platforms.reject!(&.==(platform))
      end
      platforms
    end

    # `BUNDLE_FORCE_RUBY_PLATFORM` (`settings.rb:21`): resolution materializes
    # the generic variants only. A locked native row is not reused as the
    # installed spec — measured: a `platdemo (1.0.0-x64-mingw-ucrt)` lock plus
    # the setting makes the reference re-resolve, install `platdemo 1.0.0` and
    # keep the native row in the lockfile.
    private def force_ruby_platform? : Bool
      @definition.config["force_ruby_platform"] == true
    end

    # Lockfile-only platform variants (see `decisions_to_specs`): rows the
    # reference writes into the lockfile for platforms it materialized but does
    # not install.
    getter lock_extra_specs : Array(ResolvedSpec) = [] of ResolvedSpec
    @lock_extra_specs = [] of ResolvedSpec

    # Install-time checksum overrides: the reference records the sha256 of
    # each downloaded package in the lockfile even for file:// sources.
    property install_checksums : Hash(String, String) = {} of String => String

    # Gems installed as source plugins are removed from the bundle lockfile
    # after installation: the reference's inferred `bundler-source-<type>`
    # dependency is registered as a plugin, not as a bundled gem
    # (`plugin/dsl.rb:39-49`; measured lock after install).
    @hidden_dependencies = Set(String).new

    def hide_inferred_plugins!(names : Enumerable(String)) : Nil
      names.each do |name|
        @hidden_dependencies << name
        @resolved_specs.reject! { |spec| spec.name == name }
      end
    end

    # `Bundler::Plugin::DSL#source` (4.0.24
    # bundler/lib/bundler/plugin/dsl.rb:39-49) turns every typed source into a
    # top-level `bundler-source-<type>` dependency for install-time resolution.
    # The lockfile never records these inferred dependencies, so they are added
    # only to the evaluation used by `install` and hidden again by
    # `hide_inferred_plugins!`.
    def add_inferred_plugin_dependencies!(names : Enumerable(String)) : Nil
      names.each do |name|
        next if @evaluation.dependencies.any? { |dep| dep.name == name }
        dep = Bridge::EvaluatedDependency.from_json({
          "name" => name, "requirements" => [">= 0"], "groups" => ["default"],
          "platforms" => [] of String, "autorequire" => nil,
          "force_ruby_platform" => false, "gemspec_dev_dep" => false,
          "source" => nil,
        }.to_json)
        @evaluation.dependencies << dep
      end
    end

    # Lockfile form of a PATH source remote (reference
    # `Bundler::Source::Path#lockfile_path`, source/path.rb:136-139, with
    # `relative_path` at :210-215): a project-relative path stays relative, an
    # absolute path under the Gemfile directory becomes relative to it, and any
    # other absolute path is kept absolute. Output uses forward slashes and no
    # leading "./".
    private def lockfile_path_for(remote : String) : String
      return remote if remote.empty?
      root = File.expand_path(File.dirname(@definition.gemfile_path))
      expanded = File.expand_path(remote, root)
      relative = relative_under_root(expanded, root)
      return relative if relative
      local_absolute_path?(remote) ? expanded.gsub('\\', "/") : remote.gsub('\\', "/")
    end

    private def relative_under_root(expanded : String, root : String) : String?
      base = root.gsub('\\', "/").chomp('/')
      path = expanded.gsub('\\', "/").chomp('/')
      return "." if path == base
      prefix = "#{base}/"
      {% if flag?(:windows) %}
        return nil unless path.downcase.starts_with?(prefix.downcase)
      {% else %}
        return nil unless path.starts_with?(prefix)
      {% end %}
      path[prefix.size..]
    end

    private def local_absolute_path?(path : String) : Bool
      path.starts_with?("/") || path.starts_with?("\\\\") || path.matches?(/\A[A-Za-z]:[\/\\]/)
    end

    # Reference `Source::Path::DEFAULT_GLOB` (bundler-4.0.24 source/path.rb:14):
    # a glob equal to this default is never written to the lockfile, and only a
    # non-default glob earns a `glob:` line.
    DEFAULT_GLOB = "{,*,*/*}.gemspec"

    # Reference `Source::Git#to_lock` (source/git.rb:53-61) writes `remote`,
    # `revision`, then the options present in %w[ref branch tag submodules],
    # then a non-default glob. The order is load-bearing for byte-equal locks.
    def self.git_lock_options(remote : String, info : SourceInfo) : Array(Lockfile::Option)
      options = [Lockfile::Option.new("remote", remote),
                 Lockfile::Option.new("revision", info.revision || "")]
      options << Lockfile::Option.new("ref", info.ref.not_nil!) if info.ref
      options << Lockfile::Option.new("branch", info.branch.not_nil!) if info.branch
      options << Lockfile::Option.new("tag", info.tag.not_nil!) if info.tag
      options << Lockfile::Option.new("submodules", "true") if info.submodules == true
      if glob = info.glob
        options << Lockfile::Option.new("glob", glob) unless glob == DEFAULT_GLOB
      end
      options
    end

    # Reference `Source::Path#to_lock` (source/path.rb:45-49): `remote` plus the
    # `glob:` line only for a non-default glob.
    def self.path_lock_options(remote : String, info : SourceInfo) : Array(Lockfile::Option)
      options = [Lockfile::Option.new("remote", remote)]
      if glob = info.glob
        options << Lockfile::Option.new("glob", glob) unless glob == DEFAULT_GLOB
      end
      options
    end

    # `bundle check`'s satisfied branch calls `definition.lock(true)`; the
    # reference serializes the already-locked definition without resolving.
    # Materialize the locked specs directly so the rewrite keeps the locked
    # resolution while still refreshing PLATFORMS/CHECKSUMS/BUNDLED WITH.
    def lockfile_rewrite_text : String
      if !@resolved && @definition.lockfile_exists?
        @resolved_specs = materialize_locked
        @resolved = true
      end
      generated_lockfile.to_lock
    end

    def generated_lockfile : Lockfile::Data
      resolve! unless @resolved

      sections = [] of Lockfile::Section

      # Non-GEM sources first (pinned: lock_sources = (path + git).sort_by
      # identifier — "git..." sorts before "path..." — then rubygems sources).
      non_gem = @resolved_specs.reject(&.source_type.==("GEM"))
      # Plugin sources sort before git/path by identifier
      # (`lockfile_generator.rb:31-36` + `plugin/api/source.rb:293-295`); their
      # `to_lock` writes remote, type, then every `options_to_lock` entry.
      non_gem.select(&.source_type.==("PLUGIN")).group_by(&.source_info.not_nil!.remote).each do |remote, specs|
        info = specs.first.source_info.not_nil!
        options = [Lockfile::Option.new("remote", remote),
                   Lockfile::Option.new("type", info.plugin_type || "")]
        (info.lock_options || {} of String => String).each do |key, value|
          options << Lockfile::Option.new(key, value)
        end
        source_specs = specs.sort_by(&.full_name).map do |spec|
          Lockfile::Spec.new(spec.name, spec.version.to_s, spec.platform, spec.dependencies)
        end
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("PLUGIN SOURCE", options, source_specs))
      end
      non_gem.select(&.source_type.==("GIT")).group_by(&.source_info.not_nil!.remote).each do |remote, specs|
        source_specs = specs.map do |spec|
          Lockfile::Spec.new(spec.name, spec.version.to_s, spec.platform, spec.dependencies)
        end
        info = specs.first.source_info.not_nil!
        options = Resolution.git_lock_options(remote, info)
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("GIT", options, source_specs))
      end
      non_gem.select(&.source_type.==("PATH")).group_by { |spec| lockfile_path_for(spec.source_info.not_nil!.remote) }.each do |remote, specs|
        source_specs = specs.map do |spec|
          Lockfile::Spec.new(spec.name, spec.version.to_s, spec.platform, spec.dependencies)
        end
        info = specs.first.source_info.not_nil!
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("PATH",
          Resolution.path_lock_options(remote, info), source_specs))
      end

      gem_sections_by_remote = {} of String => Array(Lockfile::Spec)
      (@resolved_specs.select(&.source_type.==("GEM")) + lock_extra_specs).reject(&.name.==("bundler")).each do |spec|
        next if @hidden_dependencies.includes?(spec.name)
        remote = spec.source_remote || primary_remote
        gem_sections_by_remote[remote] ||= [] of Lockfile::Spec
        gem_sections_by_remote[remote] << Lockfile::Spec.new(spec.name, spec.version.to_s, spec.platform, spec.dependencies)
      end

      gem_sections_by_remote.each do |remote, specs|
        specs.sort_by!(&.full_name)
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("GEM",
          [Lockfile::Option.new("remote", remote)], specs))
      end

      # Bundler emits declared rubygems source sections even when no GEM specs
      # resolve from them (for example a Gemfile with only a path gem still
      # records `GEM / remote: https://rubygems.org/ / specs:` when the Gemfile
      # declares that source).
      gem_section_emitted = !gem_sections_by_remote.empty?
      declared_rubygem_remotes.each do |remote|
        next if gem_sections_by_remote.has_key?(remote)
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("GEM",
          [Lockfile::Option.new("remote", remote)], [] of Lockfile::Spec))
        gem_section_emitted = true
      end

      # A Gemfile with no `source` line still locks an (empty) GEM section, but
      # without a `remote:` line (`source/rubygems.rb:114-120`; measured on
      # 4.0.24 and 2.7.2 — task-44a oracle (d)).
      if !gem_section_emitted && rubygem_source_without_remote?
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("GEM",
          [] of Lockfile::Option, [] of Lockfile::Spec))
      end

      platforms = [] of String
      # Existing lockfile platforms persist (parity with re-lock behavior)
      if @definition.lockfile_exists?
        @definition.lockfile!.platforms.each do |p|
          platforms << p unless platforms.includes?(p)
        end
      end
      # `BUNDLE_FORCE_RUBY_PLATFORM` records the generic platform instead of the
      # local one (measured: `PLATFORMS\n  ruby`, and a pre-existing native row
      # is kept next to it).
      platforms << Gem::Platform.local.to_s unless force_ruby_platform? || platforms.includes?(Gem::Platform.local.to_s)
      platforms << "ruby" if force_ruby_platform?
      # Reference `should_add_extra_platforms?`: a fresh resolution on a host
      # whose generic local platform is `ruby` records the ruby platform too
      # (Linux/macOS lockfiles list `ruby`; Windows lists the mingw platform).
      if !@definition.lockfile_exists? && generic_local_platform_is_ruby?
        platforms << "ruby" unless platforms.includes?("ruby")
      end
      @resolved_specs.each do |spec|
        if platform = spec.platform
          platforms << platform unless platforms.includes?(platform)
        end
      end
      @added_platforms.each do |p|
        platforms << p unless platforms.includes?(p)
      end
      @removed_platforms.each do |p|
        platforms.delete(p)
      end
      # --normalize-platforms collapses versioned platforms to the generic
      # platform when the resolved set has no variant-only specs
      # (`Bundler::SpecSet#normalize_platforms!` for the common shapes).
      if @normalize_platforms
        platforms = platforms.map do |p|
          next p if p == "ruby"
          platform = Gem::Platform.new(p)
          version = platform.version
          next p if version.nil?
          version.to_i? || next p
          platform.cpu && platform.os ? "#{platform.cpu}-#{platform.os}" : p
        end.uniq
        # `SpecSet#normalize_platforms!` also calls `add_extra_platforms!`
        # (`spec_set.rb:38-40`, `:66-89`): every platform the sources can
        # completely satisfy whose generic form is `ruby` joins the list. A
        # pure-Ruby gem therefore adds `ruby` next to the local platform
        # (measured on 4.0.24 and 2.7.2).
        if !platforms.includes?("ruby") && @resolved_specs.any? { |spec| spec.platform.nil? || spec.platform == "ruby" }
          platforms << "ruby"
        end
      end
      platforms = platforms.reject(&.==("ruby")) + (platforms.select(&.==("ruby")))
      platforms.sort!
      sections << Lockfile::TypedSection.new(Lockfile::PlatformsSection.new(platforms))

      dep_section = Lockfile::DependenciesSection.new
      @evaluation.dependencies.each do |dep|
        next if dep.gemspec_dev_dep
        next if @hidden_dependencies.includes?(dep.name)
        requirement = Gem::Requirement.new(dep.requirements)
        source_type = dep.source.try(&.type)
        pinned = !source_type.nil? && source_type != "Rubygems" && source_type != "Metadata"
        dep_section.dependencies << Lockfile::Dependency.new(
          dep.name,
          requirement.none? ? nil : requirement.to_lock_requirements,
          pinned,
        )
      end
      sections << Lockfile::TypedSection.new(dep_section)

      if checksums_enabled?
        checksum_section = Lockfile::ChecksumsSection.new
        # Checksum precedence: installed-package digest (this run) > existing
        # lockfile entry (the reference keeps locked checksums on re-lock) >
        # index checksum.
        existing_checksums = @definition.lockfile_exists? ? @definition.lockfile!.checksums : [] of Lockfile::ChecksumEntry
        @resolved_specs.reject(&.name.==("bundler")).each do |spec|
          next if @hidden_dependencies.includes?(spec.name)
          installed = @install_checksums["#{spec.name}-#{spec.version}"]?
          existing = existing_checksums.find do |c|
            c.name == spec.name && c.version == spec.version.to_s &&
              (c.platform.nil? || c.platform == "ruby") && !c.checksums.empty?
          end
          raw = installed || existing.try(&.checksums.first?) || spec.checksum
          checksum = raw.try { |c| c.starts_with?("sha256=") ? c : self.class.info_checksum_value(c) }
          checksums = checksum ? [checksum.not_nil!] : [] of String
          checksum_section.entries << Lockfile::ChecksumEntry.new(spec.name, spec.version.to_s, spec.platform, checksums)
        end
        # Lockfile-only rows carry their own index checksum and never inherit
        # the installed digest of the local variant (`lockfile_generator.rb:69-76`
        # maps `definition.resolve`, i.e. every materialized row).
        lock_extra_specs.each do |spec|
          next if @hidden_dependencies.includes?(spec.name)
          raw = spec.checksum
          checksum = raw.try { |c| c.starts_with?("sha256=") ? c : self.class.info_checksum_value(c) }
          checksums = checksum ? [checksum.not_nil!] : [] of String
          checksum_section.entries << Lockfile::ChecksumEntry.new(spec.name, spec.version.to_s, spec.platform, checksums)
        end
        # The bundler self-checksum entry is 4.0.24-only (2.7.x never records
        # one — pinned generator diff, vendor/reference/MANIFEST.md).
        if !profile_is_2_x? && (path = @bundler_cache_path)
          if File.file?(path)
            sha = Digest::SHA256.hexdigest(File.read(path))
            checksum_section.entries << Lockfile::ChecksumEntry.new("bundler", (@bundler_version_to_lock || @bridge_bundler_version), nil, ["sha256=#{sha}"])
          end
        end
        # Dedupe defense: collapse any duplicate (name, version, platform)
        # entries, keeping the last (self-checksum override wins).
        deduped = {} of String => Lockfile::ChecksumEntry
        checksum_section.entries.each do |e|
          deduped["#{e.name}|#{e.version}|#{e.platform}"] = e
        end
        checksum_section.entries.clear
        deduped.values.each { |e| checksum_section.entries << e }
        # 2.7.x never records a bundler self-checksum, including when an older
        # lockfile (or a 4.x refresh) already carries one; the reference drops
        # it on rewrite (`lockfile_generator.rb` 4.0.24-only path).
        checksum_section.entries.reject! { |e| profile_is_2_x? && e.name == "bundler" }
        sections << Lockfile::TypedSection.new(checksum_section)
      end

      indent = profile_is_2_x? ? "   " : "  "
      if ruby_line = ruby_section_value
        sections << Lockfile::TypedSection.new(Lockfile::RubySection.new(ruby_line, indent))
      end

      sections << Lockfile::TypedSection.new(Lockfile::BundledWithSection.new(@bundler_version_to_lock || @bridge_bundler_version, indent))

      Lockfile::Data.new(sections, @definition.lockfile_path, true)
    end

    # Reference `Definition#locked_ruby_version`: a fresh lockfile — or one whose
    # Gemfile ruby declaration differs from the locked one, or that is being
    # refreshed by `--ruby` — serializes the *running* Ruby
    # (`Bundler::RubyVersion.system`), never the Gemfile requirement; an unchanged
    # declaration keeps the value already in the lockfile.
    private def ruby_section_value : String?
      declared = @evaluation.ruby
      return nil unless declared
      existing = @definition.lockfile_exists? ? @definition.lockfile!.ruby_version : nil
      if existing && !@ruby_update && ruby_declaration_matches_lock?(declared, existing)
        return existing
      end
      system_ruby_string || declared
    end

    private def ruby_declaration_matches_lock?(declared : String, locked : String) : Bool
      requested = Celerite::RubyVersion.parse_requirement(declared)
      locked_version = Celerite::RubyVersion.from_string(locked)
      return false unless requested && locked_version
      requested.diff(locked_version).nil?
    end

    # `Bundler::RubyVersion.system#to_s`: 4.x prints `ruby <version>` (plus the
    # engine tuple for non-CRuby engines), 2.x appends `p<patchlevel>`.
    private def system_ruby_string : String?
      env = @bridge.try(&.ruby_environment)
      return nil unless env
      String.build do |io|
        io << "ruby " << env.ruby_version
        if profile_is_2_x?
          patch = env.patchlevel
          if patch && !patch.empty? && patch != "-1"
            io << 'p' << patch
          end
        end
        unless env.engine == "ruby"
          io << " (" << env.engine << ' ' << (env.engine_version.empty? ? env.ruby_version : env.engine_version) << ')'
        end
      end
    end

    # Pinned behavior: a NEW lockfile gets CHECKSUMS when the profile defaults
    # them on (4.0.24) or the config forces them; an existing lockfile keeps
    # whatever it had (absent stays absent). 2.7.x defaults CHECKSUMS off.
    private def checksums_enabled? : Bool
      # `lock --add-checksums` writes the section in both profiles, even when
      # it did not exist before (`definition.rb:564-583`, 2.7.2 `:535-541`).
      return true if @add_checksums

      if profile_is_2_x?
        # 2.7.x defaults CHECKSUMS off; keep them only when already locked
        return @definition.lockfile_exists? && !@definition.lockfile!.checksums_section.nil?
      end

      # A lockfile that already carries the section keeps it on every rewrite:
      # `lockfile_generator.rb:69-76` emits CHECKSUMS whenever
      # `definition.locked_checksums` is set, and `locked_checksums` is
      # initialized from the locked section (`definition.rb:661-670`), not from
      # config. This is what `check`'s lockfile rewrite relies on (oracle case
      # (c): reference keeps `CHECKSUMS` while adding the local platform).
      return true if @definition.lockfile_exists? && !@definition.lockfile!.checksums_section.nil?

      # A fresh lockfile still needs `lockfile_checksums` enabled in config;
      # `lock --add-checksums` (handled above) forces the section instead.
      return false if @definition.config["lockfile_checksums"] != true

      !@definition.lockfile_exists?
    end

    private def profile_is_2_x? : Bool
      @bridge_bundler_version.starts_with?("2.")
    end
  end
end
