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
      begin
        expanded = File.expand_path(base, project_root)
        relative = Path[expanded].relative_to(Dir.current).to_s
        value = if relative.starts_with?("..")
                  Path[base].absolute? ? base : relative
                else
                  relative == "." ? "." : "./#{relative}"
                end
        # `Pathname` prints `/` even on Windows.
        value.gsub(/\\/, "/")
      rescue ArgumentError
        # Windows paths on different drives cannot be made relative
        # (Pathname.relative_path_from raises ArgumentError there too).
        File.expand_path(base, project_root).gsub(/\\/, "/")
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
      @root_dependency_names = [] of String
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
    # `<Gemfile dir>/vendor/cache/*.gem`. file:// sources count as local, so
    # their index is still consulted (oracle: `--local` + file:// resolves
    # through the index).
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

    private def index_specs_for(name : String) : Array(Resolver::IndexSpec)
      local = local_index_specs(name)
      if @local_only
        # `local_only!` sources know nothing beyond the gems installed for this
        # bundle: an unknown name is left for the resolver, which reports
        # "Could not find gem '<name> (<req>)' in locally installed gems."
        return local
      end
      if @prefer_local && !local.empty?
        return local
      end
      index_specs_from_remote(name)
    end

    # Build candidate specs for one gem from the compact index.
    private def index_specs_from_remote(name : String) : Array(Resolver::IndexSpec)
      cache = @index_specs_cache ||= {} of String => Array(Resolver::IndexSpec)
      cache[name] ||= begin
        remote = remote_for(name)
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
      @root_dependency_names = deps.map(&.name)
      @resolved_specs
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
      # Reference `converge_dependencies` (definition.rb:1051-1076) and
      # `check_lockfile` (definition.rb:973-1014): the locked specs must cover
      # every dependency, otherwise `@missing_lockfile_dep` (etc.) makes
      # `something_changed?` (definition.rb:630-645) true and we re-resolve.
      return false unless lockfile_covers_dependencies?(lockfile, deps)
      return false unless sources_compatible?(lockfile)
      # Reference parity: a lockfile that does not cover the local platform
      # (no `ruby`, no matching entry) makes the definition re-resolve
      # (current_platform_missing -> something_changed?), so the locked path
      # does not apply.
      return false unless covers_local_platform?(lockfile)

      ruby_compatible?(lockfile)
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
          spec.source_index, spec.source_type, spec.source_info, spec.source_remote)
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
      # `Source::Rubygems#to_s` (4.0.24 lib/bundler/source/rubygems.rb:122-136):
      # with `@allow_remote` off the source only describes installed gems, which
      # is what `fund`/`clean`/`binstubs` report for a missing gem.
      description = if @local_only
                      "locally installed gems"
                    else
                      "rubygems repository #{primary_remote} or installed locally"
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
      @resolved_specs.select(&.source_type.==("GEM")).reject(&.name.==("bundler")).each do |spec|
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
        @resolved_specs.reject(&.name.==("bundler")).each do |spec|
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
        # Dedupe defense: collapse any duplicate (name, version, platform)
        # entries, keeping the last (self-checksum override wins).
        deduped = {} of String => Lockfile::ChecksumEntry
        checksum_section.entries.each do |e|
          deduped["#{e.name}|#{e.version}|#{e.platform}"] = e
        end
        checksum_section.entries.clear
        deduped.values.each { |e| checksum_section.entries << e }
        sections << Lockfile::TypedSection.new(checksum_section)
      end

      indent = profile_is_2_x? ? "   " : "  "
      if ruby_line = ruby_section_value
        sections << Lockfile::TypedSection.new(Lockfile::RubySection.new(ruby_line, indent))
      end

      sections << Lockfile::TypedSection.new(Lockfile::BundledWithSection.new(@bridge_bundler_version, indent))

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
