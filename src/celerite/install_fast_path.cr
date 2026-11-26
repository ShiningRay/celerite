require "digest/sha256"
require "random/secure"
require "set"

require "./lock_fast_path"
require "./installed_index"
require "./glob"
require "./plugin_gemfile_cache"

module Celerite
  # Pure install-summary rules shared by the compatibility and no-op paths.
  # Keeping the numbers and transcript rendering together prevents the fast
  # path from drifting on Bundler's own gem, typed sources, or path hints.
  module InstallSummary
    record Summary,
      deps_count : Int32,
      gems_count : Int32,
      skipped_groups : Array(String),
      path_mode : Symbol,
      relative_path : String

    def self.build(evaluation : Bridge::GemfileEvaluation,
                   spec_names : Enumerable(String),
                   hidden_names : Enumerable(String),
                   skipped_groups : Array(String),
                   switched_bundler : Bool,
                   bundler_version : String,
                   path_mode : Symbol,
                   relative_path : String) : Summary
      hidden = hidden_names.to_set
      deps_count = evaluation.dependencies.count do |dep|
        !dep.gemspec_dev_dep && !hidden.includes?(dep.name)
      end
      # `cli/install.rb:93-96` counts `definition.specs`, i.e. the
      # materialized form of the requested dependencies. A typed source's
      # inferred `bundler-source-<type>` gem is installed by the plugin
      # installer, not the application definition, and is hidden on both sides.
      gems_count = spec_names.count { |name| !hidden.includes?(name) }
      # 2.7.x counts the running Bundler; a switched run counts the
      # switched-to Bundler instead (`cli/common.rb:57`).
      gems_count += 1 if switched_bundler || bundler_version.starts_with?("2.")
      Summary.new(deps_count, gems_count, skipped_groups, path_mode, relative_path)
    end

    def self.complete_line(summary : Summary) : String
      count = summary.deps_count
      gems = summary.gems_count
      "Bundle complete! #{count} Gemfile dependenc#{count == 1 ? "y" : "ies"}, " \
      "#{gems} gem#{gems == 1 ? "" : "s"} now installed."
    end

    def self.skipped_groups_line(summary : Summary) : String?
      groups = summary.skipped_groups
      return nil if groups.empty?
      label = if groups.size == 1
                "group '#{groups.first}'"
              else
                quoted = groups.map { |group| "'#{group}'" }
                "groups #{quoted[0...-1].join(", ")} and #{quoted.last}"
              end
      "Gems in the #{label} were not installed."
    end

    def self.path_line(summary : Summary) : String
      case summary.path_mode
      when :empty
        "Bundled gems are installed into `./.`"
      when :system
        "Use `bundle info [gemname]` to see where a bundled gem is installed."
      else
        "Bundled gems are installed into `#{summary.relative_path}`"
      end
    end
  end

  # Unchanged-install fast path. It reuses `LockFastPath.trusted_attempt` for
  # every decision that can be made from the lockfile and cached evaluation;
  # only install-specific gates (argument shape, hooks, output-affecting
  # settings, installed tree, and the two summary numbers) live here.
  module InstallFastPath
    struct Hit
      getter digest : String
      getter evaluation : Bridge::GemfileEvaluation
      getter trusted : LockFastPath::Hit
      getter default_gem_dir : String
      getter install_root : String
      getter summary : InstallSummary::Summary
      getter plan_digest : String
      getter lock_identity : CacheIdentity::LockIdentity

      def initialize(@digest : String, @evaluation : Bridge::GemfileEvaluation,
                     @trusted : LockFastPath::Hit, @default_gem_dir : String,
                     @install_root : String, @summary : InstallSummary::Summary,
                     @plan_digest : String, @lock_identity : CacheIdentity::LockIdentity)
      end
    end

    # A deterministic seam for specs that mutate the lock/tree between the
    # unlocked attempt and the caller's ProcessLock. Production never sets it.
    @@after_attempt : Proc(Definition, Config, Nil)? = nil

    def self.after_attempt=(callback : Proc(Definition, Config, Nil)?)
      @@after_attempt = callback
    end

    def self.run_after_attempt_hook(definition : Definition, config : Config) : Nil
      if callback = @@after_attempt
        callback.call(definition, config)
      end
    end

    # The Plugin::DSL preflight may be skipped only when the normal evaluation
    # and runtime record are already trusted and an empty plugin-name
    # certificate is bound to that exact fingerprint. This performs no bridge
    # work; the caller falls back to the existing Ruby preflight on any miss.
    def self.plugin_precheck_skippable?(definition : Definition, config : Config) : Bool
      return false unless PluginHooks.enabled?(config)
      # Both Bundler index files are Ruby-visible: the project-local tree and
      # the user-global tree. A root may be absent or an empty directory; an
      # index may be absent or a zero-byte regular file. Any other state keeps
      # the Plugin::DSL preflight.
      local_root = File.dirname(PluginHooks.index_path(definition))
      return false unless plugin_tree_empty?(local_root, File.join(local_root, "index"))
      if global_root = global_plugin_root
        return false unless plugin_tree_empty?(global_root, File.join(global_root, "index"))
      else
        return false
      end
      trusted, _reason = LockFastPath.trusted_attempt(definition, "install")
      return false if trusted.nil?
      hit = trusted.not_nil!
      certificate = EvalCacheStore.certificate(hit.digest, hit.record.certificate_nonce)
      return false if certificate.nil?
      plugin = certificate.not_nil!.plugin
      return false if plugin.nil? || plugin.certificate_nonce != hit.record.certificate_nonce
      return false unless plugin.roots_digest == PluginGemfileCache::EMPTY_ROOTS_DIGEST
      return false unless plugin.index_digest == PluginGemfileCache::EMPTY_INDEX_DIGEST
      PluginGemfileCache.trusted?(hit.digest, hit.record.certificate_nonce)
    rescue
      false
    end

    private def self.global_plugin_root : String?
      if override = ENV["BUNDLE_USER_PLUGIN"]?
        return nil if override.empty?
        return File.expand_path(override)
      end
      if user_home = ENV["BUNDLE_USER_HOME"]?
        return nil if user_home.empty?
        return File.expand_path(File.join(user_home, "plugin"))
      end
      home = Config.user_home
      return nil if home.nil? || home.empty?
      File.expand_path(File.join(home, ".bundle", "plugin"))
    end

    private def self.plugin_tree_empty?(root : String, index : String) : Bool
      if File.exists?(root)
        return false unless Dir.exists?(root)
        children = Dir.children(root)
        unless children.empty? || (children.size == 1 && File.join(root, children[0]) == index)
          return false
        end
      end
      if File.exists?(index)
        return false unless File.file?(index) && !File.symlink?(index)
        return false unless File.size(index) == 0
      end
      true
    rescue
      false
    end

    def self.attempt(definition : Definition, config : Config, rest : Array(String),
                     summary : Bool, show_resolving : Bool, no_reuse : Bool, no_install : Bool,
                     cli_arguments : Bool, refresh_cache : Bool,
                     trusted_result : {LockFastPath::Hit?, String?}? = nil) : {Hit?, String?}
      return {nil, nil} unless LockFastPath.enabled?
      # Only a bare `bundle install` has a byte-stable no-op transcript. Any
      # flag can change filtering, paths, output, or filesystem side effects.
      return {nil, "switches"} unless rest.empty?
      return {nil, "switches"} unless summary && show_resolving && !no_reuse &&
                                      !no_install && cli_arguments && refresh_cache
      # `--verbose`/`BUNDLE_VERBOSE` adds progress and Ruby diagnostics that a
      # zero-spawn hit cannot synthesize.
      return {nil, "verbose"} if ENV["CELERITE_VERBOSE"]? == "1"

      trusted, reason = trusted_result || LockFastPath.trusted_attempt(definition, "install")
      return {nil, reason} if trusted.nil?
      hit = trusted.not_nil!
      lockfile = definition.lockfile!
      facts = hit.facts

      # A lock written by a different Bundler profile can trigger the
      # auto-switch path, which installs Bundler and changes the summary.
      locked_bundler = lockfile.bundler_version
      return {nil, "bundler"} if locked_bundler.nil? ||
                                 locked_bundler != Celerite::Profile.bundler_version

      # These settings alter the install plan, install root, or append extra
      # summary lines. Keep them on the compatibility path even when the
      # environment signature itself still matches.
      return {nil, "groups"} if group_configured?(config)
      return {nil, "frozen"} if config.frozen? || config_bool?(config["deployment"])
      return {nil, "shared-gems"} if config_bool?(config["disable_shared_gems"])
      return {nil, "force-ruby-platform"} if config_bool?(config["force_ruby_platform"])
      return {nil, "clean"} if config_bool?(config["clean"])
      return {nil, "cooldown"} unless config["cooldown"].nil?
      return {nil, "app-cache"} if app_cache_exists?(definition, config, config.frozen?)

      default_gem_dir = facts.default_gem_dir.value
      return {nil, "default-gem-dir"} unless facts.default_gem_dir.known? && default_gem_dir
      dir = default_gem_dir.not_nil!
      abi = hit.record.abi.ruby_api_version
      install_root = InstallPaths.gem_root(config, dir, abi)
      return {nil, "funding"} if funding_possible?(definition, config, install_root)

      plan_digest_value, plan_reason = plan_evidence(lockfile, install_root,
        hit.record.abi.ruby_api_version, hit.evaluation)
      return {nil, plan_reason} if plan_reason
      certificate = EvalCacheStore.certificate(hit.digest, hit.record.certificate_nonce)
      return {nil, "install-certificate"} if certificate.nil?
      install = certificate.not_nil!.install
      return {nil, "plan-digest"} if install.nil? || install.plan_digest != plan_digest_value

      gems_count = reachable_specs(lockfile, hit.evaluation).size
      return {nil, "plan"} if gems_count.zero? && !lockfile.specs.empty?

      path_mode = if empty_bundle_path?(definition, config)
                    :empty
                  elsif InstallPaths.use_system_gems?(config, dir)
                    :system
                  else
                    :relative
                  end
      relative_path = if path_mode == :relative
                        InstallPaths.base_path_relative_to_pwd(config, definition.project_root)
                      else
                        ""
                      end
      if PluginHooks.enabled?(config)
        local_root = File.dirname(PluginHooks.index_path(definition))
        return {nil, "plugin-index"} unless plugin_tree_empty?(local_root, File.join(local_root, "index"))
        return {nil, "hooks"} unless plugin_precheck_skippable?(definition, config)
      end
      summary = InstallSummary.build(hit.evaluation, reachable_specs(lockfile, hit.evaluation),
        [] of String, [] of String, false, Celerite::Profile.bundler_version, path_mode, relative_path)
      {Hit.new(hit.digest, hit.evaluation, hit, dir, install_root, summary,
        plan_digest_value.not_nil!, certificate.not_nil!.lock), nil}
    end

    # The caller reaches this method only while holding ProcessLock. Re-run the
    # complete zero-Ruby proof so a lock/tree mutation between attempt and lock
    # can never produce a stale no-op transcript or leave a stale trusted hit
    # for the compatibility path.
    def self.revalidate?(hit : Hit, definition : Definition, config : Config) : Bool
      trusted, _reason = LockFastPath.trusted_attempt(definition, "install")
      return false if trusted.nil?
      current = trusted.not_nil!
      return false unless current.digest == hit.digest
      return false unless current.record.certificate_nonce == hit.trusted.record.certificate_nonce
      lock_identity = LockFastPath.detect_lock_identity(definition)
      return false if lock_identity.nil? || !lock_identity.not_nil!.same?(hit.lock_identity)

      lockfile = definition.lockfile!
      digest, reason = plan_evidence(lockfile, hit.install_root,
        current.record.abi.ruby_api_version, hit.evaluation)
      return false if reason || digest != hit.plan_digest
      return false if PluginHooks.enabled?(config) && !plugin_precheck_skippable?(definition, config)
      true
    rescue
      false
    end

    # Prints the exact two-line no-op transcript of the compatible path.
    # `ProcessLock` is acquired by the caller around this call, matching the
    # compatibility path's serialization semantics.
    def self.emit(hit : Hit, stdout : IO, definition : Definition, config : Config) : Nil
      stdout.puts InstallSummary.complete_line(hit.summary)
      if line = InstallSummary.skipped_groups_line(hit.summary)
        stdout.puts line
      end
      stdout.puts InstallSummary.path_line(hit.summary)
    end

    # Publish one successful install transaction. The caller already holds the
    # install ProcessLock. Both the EvalCache entry and the single plugin
    # certificate are snapshotted/restored on later failure, and RuntimeRecord is
    # the final commit marker.
    def self.remember_after_install(definition : Definition, config : Config, digest : String,
                                    evaluation : Bridge::GemfileEvaluation,
                                    fingerprint : Bridge::EvalFingerprint,
                                    plugin_names : Array(String)?) : Bool
      plugin_snapshot : String? = nil
      eval_snapshot : String? = nil
      plugin_phase : Bool? = nil
      eval_phase : Bool? = nil
      return false unless LockFastPath.enabled?
      return false unless digest.matches?(EvalCacheStore::DIGEST)
      return false unless fingerprint.digest == digest
      return false unless fingerprint.state == EvalFingerprint::State::Deterministic

      stored = EvalCacheStore.read_all.find do |entry|
        entry.digest == digest && entry.format == EvalCacheStore::FORMAT &&
          entry.json["env"]?.try(&.as_s?) == Bridge::EvaluationCache.environment_signature &&
          entry.json["evaluation"]?.try(&.as_h?).try { |value| value["gemfile"]? }
            .try(&.as_s?).try { |path| File.expand_path(path) == File.expand_path(definition.gemfile_path) }
      end
      return false if stored.nil?
      document = EvalFingerprint::Document.parse(fingerprint.text, fingerprint.digest, fingerprint.verify)
      return false if document.nil? || document.integrity_reason
      runtime = runtime_from_document(document)
      return false if runtime.nil? || runtime.abi.nil?
      base = File.dirname(File.expand_path(definition.gemfile_path))
      return false if document.verify(base, runtime)

      facts = RuntimeFacts.detect
      return false if facts.nil?
      identity = facts.ruby_identity
      return false unless identity.known?
      return false unless facts.default_gem_dir.known?
      default_gem_dir = facts.default_gem_dir.value.not_nil!
      abi = runtime.abi.not_nil!
      install_root = InstallPaths.gem_root(config, default_gem_dir, abi.ruby_api_version)
      lock_identity = LockFastPath.detect_lock_identity(definition)
      return false if lock_identity.nil?
      lockfile = definition.lockfile!
      plan_digest_value = plan_digest(lockfile, install_root, abi.ruby_api_version, evaluation)
      return false if plan_digest_value.nil?

      plugins_enabled = PluginHooks.enabled?(config)
      if plugins_enabled
        return false if plugin_names.nil? || !plugin_names.empty? || !evaluation.warnings.empty?
        return false unless plugin_trees_empty?(definition)
      end

      nonce = Random::Secure.hex(16)
      plugin = if plugins_enabled
                 CacheIdentity::PluginCertificate.new(nonce,
                   PluginGemfileCache::EMPTY_ROOTS_DIGEST, PluginGemfileCache::EMPTY_INDEX_DIGEST)
               else
                 nil
               end
      certificate = CacheIdentity::SuccessCertificate.new(CacheIdentity::CERTIFICATE, "install",
        Celerite::Profile.bundler_version, identity.identity_digest.not_nil!, lock_identity.not_nil!,
        plugin, CacheIdentity::InstallCertificate.new(plan_digest_value.not_nil!))
      eval_path = EvalCacheStore.entry_path(digest)
      return false if eval_path.nil? || !File.file?(eval_path)
      eval_snapshot = File.read(eval_path)
      plugin_snapshot = plugins_enabled ? PluginGemfileCache.snapshot(digest) : nil
      return false unless EvalCacheStore.put_certificate(digest, nonce, certificate)
      eval_phase = true

      plugin_written = false
      if plugins_enabled
        plugin_phase = true
        plugin_written = PluginGemfileCache.remember(definition.gemfile_path, plugin_names,
          evaluation, fingerprint, nonce)
        unless plugin_written
          rollback_certificates(digest, eval_snapshot, plugin_snapshot, eval_phase, plugin_phase)
          return false
        end
      end

      record = FastPathStore.record_from(definition.project_root, facts, runtime, abi,
        Time.utc, identity, digest, nonce)
      if record.nil?
        rollback_certificates(digest, eval_snapshot, plugin_snapshot, eval_phase, plugin_phase)
        return false
      end

      current_lock = LockFastPath.detect_lock_identity(definition)
      current_plan = plan_digest(definition.lockfile!, install_root, abi.ruby_api_version, evaluation)
      unchanged = current_lock.try(&.same?(lock_identity.not_nil!)) && current_plan == plan_digest_value
      unchanged &&= document.verify(base, runtime).nil?
      if plugins_enabled
        unchanged &&= plugin_trees_empty?(definition) &&
                      PluginGemfileCache.trusted?(digest, nonce)
      end
      unless unchanged
        rollback_certificates(digest, eval_snapshot, plugin_snapshot, eval_phase, plugin_phase)
        return false
      end

      unless FastPathStore.store(record.not_nil!)
        rollback_certificates(digest, eval_snapshot, plugin_snapshot, eval_phase, plugin_phase)
        return false
      end
      true
    rescue
      rollback_certificates(digest, eval_snapshot, plugin_snapshot, eval_phase, plugin_phase)
      false
    end

    # A hot install rotates the commit nonce without starting Ruby. The caller
    # holds ProcessLock and has already emitted the no-op transcript.
    def self.rotate(hit : Hit, definition : Definition, config : Config) : Bool
      stored = EvalCacheStore.read_all.find do |entry|
        entry.digest == hit.digest && entry.format == EvalCacheStore::FORMAT &&
          entry.json["env"]?.try(&.as_s?) == Bridge::EvaluationCache.environment_signature &&
          entry.json["evaluation"]?.try(&.as_h?).try { |value| value["gemfile"]? }
            .try(&.as_s?).try { |path| File.expand_path(path) == File.expand_path(definition.gemfile_path) }
      end
      return false if stored.nil?
      fingerprint = Bridge::EvalFingerprint.parse(stored.not_nil!.json["fingerprint"]?)
      return false if fingerprint.nil?
      plugin_names = PluginHooks.enabled?(config) ? [] of String : nil
      remember_after_install(definition, config, hit.digest, hit.evaluation,
        fingerprint.not_nil!, plugin_names)
    rescue
      false
    end

    private def self.runtime_from_document(document : EvalFingerprint::Document) : EvalFingerprint::Runtime?
      values = {} of String => String
      {"ruby.version", "ruby.patchlevel", "ruby.engine", "ruby.engine_version",
       "rubygems.version", "bundler.version", "platform"}.each do |key|
        value = document.records[key]?
        return nil if value.nil? || value.empty?
        values[key] = value
      end
      EvalFingerprint::Runtime.new(values["ruby.version"], values["ruby.patchlevel"],
        values["ruby.engine"], values["ruby.engine_version"],
        values["rubygems.version"], values["bundler.version"], values["platform"],
        abi_from_document(document))
    end

    private def self.abi_from_document(document : EvalFingerprint::Document) : EvalFingerprint::Abi?
      api = document.records["abi.ruby_api_version"]?
      extension = document.records["abi.extension_api_version"]?
      rbconfig = document.records["abi.rbconfig_ruby_version"]?
      source = document.records["abi.source"]?
      return nil if api.nil? || extension.nil? || rbconfig.nil? || source.nil?
      return nil if api.empty? || extension.empty? || rbconfig.empty?
      EvalFingerprint::Abi.new(api, extension, rbconfig, source)
    end

    private def self.plugin_trees_empty?(definition : Definition) : Bool
      local_root = File.dirname(PluginHooks.index_path(definition))
      return false unless plugin_tree_empty?(local_root, File.join(local_root, "index"))
      if global_root = global_plugin_root
        plugin_tree_empty?(global_root, File.join(global_root, "index"))
      else
        false
      end
    rescue
      false
    end

    private def self.rollback_certificates(digest : String, eval_snapshot : String?,
                                           plugin_snapshot : String?, eval_phase : Bool?,
                                           plugin_phase : Bool?) : Nil
      if plugin_phase
        begin
          PluginGemfileCache.restore(digest, plugin_snapshot)
        rescue
          # Continue with the eval entry rollback even if plugin restore fails.
        end
      end
      if eval_phase && !eval_snapshot.nil? && (path = EvalCacheStore.entry_path(digest))
        restore_file(path, eval_snapshot.not_nil!)
      end
    rescue
      # Rollback is best effort; the RuntimeRecord commit marker remains absent.
    end

    private def self.restore_file(path : String, payload : String) : Bool
      dir = File.dirname(path)
      temp = File.join(dir, ".restore-#{Process.pid}-#{Random::Secure.hex(8)}.tmp")
      begin
        Dir.mkdir_p(dir)
        File.open(temp, "w") do |file|
          file.print(payload)
          file.flush
          file.fsync
        end
        File.rename(temp, path)
        true
      rescue
        begin
          File.delete(temp) if File.exists?(temp)
        rescue IO::Error
        end
        false
      end
    end

    private def self.config_bool?(value) : Bool
      case value
      when Bool, Int32, String, Nil then Config.to_bool(value)
      else                               false
      end
    end

    private def self.group_configured?(config : Config) : Bool
      ["with", "without", "only"].any? do |key|
        case value = config[key]
        when Array  then !value.empty?
        when String then !value.split(':').reject(&.empty?).empty?
        else             false
        end
      end
    end

    private def self.empty_bundle_path?(definition : Definition, config : Config) : Bool
      ENV["BUNDLE_PATH"]? == "" || config["path"].as?(String) == ""
    end

    private def self.app_cache_exists?(definition : Definition, config : Config, frozen : Bool) : Bool
      return false if frozen
      label = config["cache_path"].as?(String)
      label = "vendor/cache" if label.nil? || label.not_nil!.empty?
      Dir.exists?(File.expand_path(label.not_nil!, File.dirname(definition.gemfile_path)))
    end

    private def self.funding_possible?(definition : Definition, config : Config,
                                       install_root : String) : Bool
      case value = config["ignore_funding_requests"]
      when Array then return false unless value.empty?
      else
        return false if config_bool?(value)
      end

      definition.lockfile!.specs.any? do |spec|
        spec_path = File.join(install_root, "specifications", "#{spec.full_name}.gemspec")
        next false unless File.file?(spec_path)
        File.read(spec_path).includes?("funding_uri")
      end
    rescue
      true
    end

    def self.plan_digest(lockfile : Lockfile::Data, install_root : String, abi : String,
                         evaluation : Bridge::GemfileEvaluation? = nil) : String?
      digest, reason = plan_evidence(lockfile, install_root, abi, evaluation)
      digest if reason.nil?
    end

    private def self.plan_evidence(lockfile : Lockfile::Data, install_root : String, abi : String,
                                   evaluation : Bridge::GemfileEvaluation?) : {String?, String?}
      begin
        manifest = IO::Memory.new
        manifest << "celerite-install-plan/1\n"
        installed = InstalledIndex.load([install_root])
        reachable = evaluation.try { |value| reachable_specs(lockfile, value) }
        selected = lockfile.specs.select do |spec|
          next false if reachable && !reachable.not_nil!.includes?(spec.name)
          spec.platform_ruby? || Gem::Platform.new(spec.platform.not_nil!).match?(Gem::Platform.local)
        end.sort_by(&.full_name)
        selected.each do |spec|
          full_name = spec.full_name
          manifest << "spec\t" << spec.name << '\0' << spec.version << '\0'
          manifest << (spec.platform || "ruby") << '\n'
          dependencies = spec.dependencies.map { |dep| {dep.name, dep.requirements || [] of String} }
          dependencies.sort_by { |dep| {dep[0], dep[1].join("\u0001")} }.each do |dep|
            manifest << "dep\t" << dep[0] << '\0' << dep[1].join("\u0001") << '\n'
          end
          return {nil, "install-index:#{full_name}"} unless installed.find_full_name(full_name)
          gemspecs = Glob.paths(File.join(install_root, "specifications"), "#{full_name}.gemspec")
          return {nil, "gemspec:#{full_name}"} if gemspecs.empty?
          gemspec_path = gemspecs.first
          return {nil, "gemspec:#{full_name}"} unless hash_file!(manifest, "gemspec:#{full_name}", gemspec_path)

          gem_dirs = Glob.paths(File.join(install_root, "gems"), full_name)
          return {nil, "gem-dir:#{full_name}"} if gem_dirs.empty?
          gem_dir = gem_dirs.first
          return {nil, "gem-dir:#{full_name}"} unless File.directory?(gem_dir)
          return {nil, "install-tree"} unless hash_tree!(manifest, full_name, gem_dir)

          text = File.read(gemspec_path)
          next unless text.matches?(/\bextensions\b/)
          platform = Gem::Platform.local.to_s
          ext_dir = File.join(install_root, "extensions", platform, abi, full_name)
          marker = File.join(ext_dir, "gem.build_complete")
          return {nil, "native-ext:#{full_name}"} unless File.directory?(ext_dir) &&
                                                         hash_file!(manifest, "native:#{full_name}", marker)
        end
        {Digest::SHA256.hexdigest(manifest.to_s), nil}
      rescue
        {nil, "install-tree"}
      end
    end

    private def self.hash_file!(manifest : IO::Memory, label : String, path : String) : Bool
      return false unless File.file?(path)
      manifest << label << '\0' << File.size(path) << '\0'
      manifest << Digest::SHA256.hexdigest(File.read(path)) << '\n'
      true
    rescue
      false
    end

    private def self.hash_tree!(manifest : IO::Memory, prefix : String, root : String) : Bool
      Dir.children(root).sort.each do |name|
        path = File.join(root, name)
        relative = normalize_manifest_path("#{prefix}/#{name}")
        if File.symlink?(path)
          manifest << "link\t" << relative << '\0' << File.readlink(path) << '\n'
        elsif Dir.exists?(path)
          manifest << "dir\t" << relative << '\n'
          return false unless hash_tree!(manifest, relative, path)
        elsif File.file?(path)
          return false unless hash_file!(manifest, "file:#{relative}", path)
        else
          return false
        end
      end
      true
    rescue
      false
    end

    private def self.normalize_manifest_path(path : String) : String
      path.gsub('\\', '/')
    end

    private def self.reachable_specs(lockfile : Lockfile::Data,
                                     evaluation : Bridge::GemfileEvaluation) : Set(String)
      by_name = Hash(String, Lockfile::Spec).new
      lockfile.specs.each { |spec| by_name[spec.name] = spec unless by_name.has_key?(spec.name) }
      seen = Set(String).new
      queue = evaluation.dependencies.map(&.name)
      until queue.empty?
        name = queue.pop
        next unless seen.add?(name)
        spec = by_name[name]?
        next if spec.nil?
        spec.dependencies.each { |dep| queue << dep.name }
      end
      seen
    end
  end
end
