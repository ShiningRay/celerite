require "../celerite"
require "base64"
require "digest/sha256"
require "./bridge/client"
require "./compact_index/cache"
require "./resolver/source"
require "./definition"
require "./git_source"

module Celerite
  # Install path helpers shared by Resolution and the CLI commands.
  module InstallPaths
    def self.install_path(config : Config) : String
      configured = config["path"].to_s
      if configured.empty? && config["path.system"] == true
        # path.system: install into the system gem location (user gem dir)
        return File.expand_path(Config.user_home || ".")
      end
      base = configured.empty? ? File.join(Config.user_home || ".", ".bundle") : configured
      File.expand_path(base)
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

      def initialize(@name : String, @version : Gem::Version, @platform : String?,
                     @dependencies : Array(Lockfile::SpecDependency), @checksum : String?,
                     @source_index : Int32, @source_type : String = "GEM",
                     @source_info : SourceInfo? = nil, @source_remote : String? = nil)
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

    @non_gem_sources : Hash(String, SourceInfo)?
    @locked_specs : Array(LockedSpec)?
    @locked_by_name : Hash(String, Array(LockedSpec))?
    @compact_index_client : CompactIndex::Client?
    @index_specs_cache : Hash(String, Array(Resolver::IndexSpec))?
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
      @resolved = false
      @current_base_requirements = {} of String => Gem::Requirement
      @current_index = {} of String => Array(Resolver::IndexSpec)
      @prerelease_available = Set(String).new
    end

    def close : Nil
      @bridge.not_nil!.close if @owned_bridge
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
          remote ||= primary_remote
          unless seen.includes?(remote)
            remotes << remote
            seen << remote
          end
        end
      end
      remotes
    end

    def compact_index_client : CompactIndex::Client
      @compact_index_client ||= CompactIndex::Client.new(primary_remote, user_cache_root, @definition.config.credentials_for(primary_remote), Commands.retry_count(@definition.config), @definition.config.mirror_for(primary_remote), ssl_ca_cert: Commands.ssl_option(@definition.config, "ssl_ca_cert"), ssl_client_cert: Commands.ssl_option(@definition.config, "ssl_client_cert"), ssl_verify_mode: Commands.ssl_option(@definition.config, "ssl_verify_mode"), timeout: Commands.timeout_seconds(@definition.config))
    end

    def compact_index_client_for(remote : String) : CompactIndex::Client
      CompactIndex::Client.new(remote, user_cache_root, @definition.config.credentials_for(remote), Commands.retry_count(@definition.config), @definition.config.mirror_for(remote), ssl_ca_cert: Commands.ssl_option(@definition.config, "ssl_ca_cert"), ssl_client_cert: Commands.ssl_option(@definition.config, "ssl_client_cert"), ssl_verify_mode: Commands.ssl_option(@definition.config, "ssl_verify_mode"), timeout: Commands.timeout_seconds(@definition.config))
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
          }.to_json)
        end
        map
      end
    end

    # Loads the spec of a path/git source gem (gemspec in the given dir).
    def load_source_gem_spec(name : String, dir : String, glob : String?) : Resolver::IndexSpec?
      info = @bridge.not_nil!.load_gemspec_dir(dir, glob)
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

    @fetch_logged_remotes = Set(String).new

    private def log_fetch_for(remote : String) : Nil
      return unless @fetch_logged_remotes.add?(remote)
      return if remote == primary_remote && @index_fetch_logged
      @index_fetch_logged = true if remote == primary_remote
      if remote.starts_with?("file:")
        @progress.puts "Fetching source index from #{remote}"
      else
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

    # Build candidate specs for one gem from the compact index.
    private def index_specs_for(name : String) : Array(Resolver::IndexSpec)
      cache = @index_specs_cache ||= {} of String => Array(Resolver::IndexSpec)
      cache[name] ||= begin
        if @local_only
          raise GemNotFoundError.new(
            "Could not find gem '#{name}' in locally installed gems."
          )
        end
        remote = remote_for(name)
        log_fetch_for(remote)
        client = remote == primary_remote ? compact_index_client : compact_index_client_for(remote)
        entries = client.info(name)
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
      rescue ex : Celerite::VersionError
        raise LockfileError.new("bad compact index data for #{name}: #{ex.message}")
      end
    end

    # ------------------------------------------------------------------
    # Resolution
    # ------------------------------------------------------------------

    def resolve!(reuse : Bool = false) : Array(ResolvedSpec)
      @resolved = true
      deps = top_level_deps

      if reuse && reuse_locked_resolution?(deps)
        @resolved_specs = materialize_locked
        return @resolved_specs
      end

      @resolved_specs = run_resolution(deps)
      @resolved_specs
    end

    # Suppressed on locked-path installs (the reference prints no
    # "Resolving dependencies..." there).
    property show_resolving : Bool = true

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

      locked_deps = lockfile.dependencies
      return false unless locked_deps.size == deps.size

      all_ok = deps.all? do |dep|
        locked = locked_deps.find(&.name.==(dep.name))
        next false unless locked
        locked.requirement == dep.requirement
      end
      return false unless all_ok
      return false unless sources_compatible?(lockfile)
      # Reference parity: a lockfile that does not cover the local platform
      # (no `ruby`, no matching entry) makes the definition re-resolve
      # (current_platform_missing -> something_changed?), so the locked path
      # does not apply.
      return false unless covers_local_platform?(lockfile)

      ruby_compatible?(lockfile)
    end

    # Reference `current_platform_locked?`: `ruby` covers every local platform
    # (it is the generic platform for non-Windows hosts), otherwise an exact
    # local entry is required.
    def covers_local_platform?(lockfile : Lockfile::Data) : Bool
      local = Gem::Platform.local.to_s
      lockfile.platforms.any? { |p| p == "ruby" || p == local }
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

    private def materialize_locked : Array(ResolvedSpec)
      lockfile = @definition.lockfile!
      specs = [] of ResolvedSpec
      lockfile.sources.each do |source|
        source.specs.each do |spec|
          checksum = lockfile.checksums.find { |c| c.name == spec.name && c.version == spec.version }
          specs << ResolvedSpec.new(spec.name, Gem::Version.new(spec.version), spec.platform,
            spec.dependencies, checksum.try(&.checksums.first?), 0)
        end
      end
      specs
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
        @progress.puts "Resolving dependencies..." if @show_resolving
        raise ex
      end
      @progress.puts "Resolving dependencies..." if @show_resolving
      decisions = solve_with_relaxation(source, deps, prerelease_exceptions, unlocked, orchestrator)
      decisions_to_specs(decisions, index, locked_index)
    end

    private def make_source(base_requirements : Hash(String, Gem::Requirement),
                            index : Hash(String, Array(Resolver::IndexSpec)),
                            locked_index : Hash(String, Array(Resolver::IndexSpec)),
                            prerelease_exceptions : Set(String),
                            unlock : Bool | Array(String) = false,
                            spec_fetcher : (String -> Array(Resolver::IndexSpec))? = nil) : Resolver::ResolutionSource
      env = @bridge.not_nil!.ruby_environment
      source = Resolver::ResolutionSource.new(
        File.basename(@definition.gemfile_path),
        "rubygems repository #{primary_remote} or installed locally",
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
      decisions.each do |package, candidate_version|
        next if package.root? || package.meta?
        name = package.name
        same_version = index[name]?.try(&.select { |s| s.version == candidate_version.version }) ||
                       locked_index[name]?.try(&.select { |s| s.version == candidate_version.version })
        spec =
          if candidate_version.priority == 1 || platform_mergeable?(same_version)
            # Platform-variant candidate, or a ruby candidate whose group carries
            # merged platform variants: materialize the local-platform variant
            # (reference `Materialization#specs` +
            # `MatchPlatform.select_best_platform_match`), falling back to the
            # ruby spec when no local-platform variant is indexed.
            Resolver::ResolutionSource.select_variant(index, name, candidate_version.version) ||
              Resolver::ResolutionSource.select_variant(locked_index, name, candidate_version.version) ||
              index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? }) ||
              locked_index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? })
          else
            index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? }) ||
              locked_index[name]?.try(&.find { |s| s.version == candidate_version.version && s.platform_ruby? })
          end
        next unless spec

        lock_deps = spec.dependencies.map do |dep|
          Lockfile::SpecDependency.new(dep.name, dep.requirement.to_lock_requirements)
        end
        source = non_gem_sources[name]?
        source_type = source ? source.type.upcase : "GEM"
        source_type = "PATH" if source_type == "GEMSPEC"
        specs << ResolvedSpec.new(name, spec.version, spec.platform_ruby? ? nil : spec.platform.to_s, lock_deps, spec.checksum, 0, source_type, source, remote_for(name))
      end
      specs.sort_by!(&.full_name)
      specs
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
      dir = ensure_source_dir(name, source)
      spec = load_source_gem_spec(name, dir, source.glob)
      spec ? [spec] : [] of Resolver::IndexSpec
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
      locked_specs.each do |locked|
        next unless locked.source_type == "GEM"
        (index[locked.name] ||= [] of Resolver::IndexSpec) << Resolver::IndexSpec.new(
          locked.name, locked.version,
          locked.platform && locked.platform != "ruby" ? Gem::Platform.new(locked.platform.not_nil!) : Gem::Platform::RUBY,
          [] of Resolver::DepSpec, Gem::Requirement.new, Gem::Requirement.new, nil
        )
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

    # Resolution platform set: local + existing lockfile platforms + added.
    def resolution_platforms : Array(Gem::Platform)
      platforms = [Gem::Platform.local]
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

    # Install-time checksum overrides: the reference records the sha256 of
    # each downloaded package in the lockfile even for file:// sources.
    property install_checksums : Hash(String, String) = {} of String => String

    def generated_lockfile : Lockfile::Data
      resolve! unless @resolved

      sections = [] of Lockfile::Section

      # Non-GEM sources first (pinned: lock_sources = (path + git).sort_by
      # identifier — "git..." sorts before "path..." — then rubygems sources).
      non_gem = @resolved_specs.reject(&.source_type.==("GEM"))
      non_gem.select(&.source_type.==("GIT")).group_by(&.source_info.not_nil!.remote).each do |remote, specs|
        source_specs = specs.map do |spec|
          Lockfile::Spec.new(spec.name, spec.version.to_s, spec.platform, spec.dependencies)
        end
        info = specs.first.source_info.not_nil!
        options = [Lockfile::Option.new("remote", remote),
                   Lockfile::Option.new("revision", info.revision || "")]
        options << Lockfile::Option.new("branch", info.branch.not_nil!) if info.branch
        options << Lockfile::Option.new("tag", info.tag.not_nil!) if info.tag
        options << Lockfile::Option.new("ref", info.ref.not_nil!) if info.ref
        options << Lockfile::Option.new("submodules", "true") if info.submodules == true
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("GIT", options, source_specs))
      end
      non_gem.select(&.source_type.==("PATH")).group_by(&.source_info.not_nil!.remote).each do |remote, specs|
        source_specs = specs.map do |spec|
          Lockfile::Spec.new(spec.name, spec.version.to_s, spec.platform, spec.dependencies)
        end
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("PATH",
          [Lockfile::Option.new("remote", remote)], source_specs))
      end

      gem_sections_by_remote = {} of String => Array(Lockfile::Spec)
      @resolved_specs.select(&.source_type.==("GEM")).each do |spec|
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
      # records `GEM / remote: https://rubygems.org/ / specs:`).
      declared_rubygem_remotes.each do |remote|
        next if gem_sections_by_remote.has_key?(remote)
        sections << Lockfile::TypedSection.new(Lockfile::SourceSection.new("GEM",
          [Lockfile::Option.new("remote", remote)], [] of Lockfile::Spec))
      end

      platforms = [] of String
      # Existing lockfile platforms persist (parity with re-lock behavior)
      if @definition.lockfile_exists?
        @definition.lockfile!.platforms.each do |p|
          platforms << p unless platforms.includes?(p)
        end
      end
      platforms << Gem::Platform.local.to_s unless platforms.includes?(Gem::Platform.local.to_s)
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
      end
      platforms = platforms.reject(&.==("ruby")) + (platforms.select(&.==("ruby")))
      platforms.sort!
      sections << Lockfile::TypedSection.new(Lockfile::PlatformsSection.new(platforms))

      dep_section = Lockfile::DependenciesSection.new
      @evaluation.dependencies.each do |dep|
        next if dep.gemspec_dev_dep
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
        @resolved_specs.each do |spec|
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
        # The bundler self-checksum entry is 4.0.24-only (2.7.x never records
        # one — pinned generator diff, vendor/reference/MANIFEST.md).
        if !profile_is_2_x? && (path = @bundler_cache_path)
          if File.file?(path)
            sha = Digest::SHA256.hexdigest(File.read(path))
            checksum_section.entries << Lockfile::ChecksumEntry.new("bundler", @bridge_bundler_version, nil, ["sha256=#{sha}"])
          end
        end
        sections << Lockfile::TypedSection.new(checksum_section)
      end

      indent = profile_is_2_x? ? "   " : "  "
      ruby_req = @evaluation.ruby
      if @ruby_update
        env = @bridge.not_nil!.ruby_environment
        patch = env.patchlevel
        ruby_req = if patch && !patch.empty?
                     "#{env.ruby_version}p#{patch}"
                   else
                     env.ruby_version
                   end
      end
      if ruby_req
        sections << Lockfile::TypedSection.new(Lockfile::RubySection.new(ruby_req, indent))
      end

      sections << Lockfile::TypedSection.new(Lockfile::BundledWithSection.new(@bridge_bundler_version, indent))

      Lockfile::Data.new(sections, @definition.lockfile_path, true)
    end

    # Pinned behavior: a NEW lockfile gets CHECKSUMS when the profile defaults
    # them on (4.0.24) or the config forces them; an existing lockfile keeps
    # whatever it had (absent stays absent). 2.7.x defaults CHECKSUMS off.
    private def checksums_enabled? : Bool
      if profile_is_2_x?
        # 2.7.x defaults CHECKSUMS off; keep them only when already locked
        return @definition.lockfile_exists? && !@definition.lockfile!.checksums_section.nil?
      end

      return false if @definition.config["lockfile_checksums"] != true

      return true unless @definition.lockfile_exists?
      !@definition.lockfile!.checksums_section.nil?
    end

    private def profile_is_2_x? : Bool
      @bridge_bundler_version.starts_with?("2.")
    end
  end
end
