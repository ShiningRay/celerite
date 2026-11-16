require "./errors"

module Celerite
  # Bundler-compatible configuration discovery (pinned contract:
  # `vendor/reference/{v4.0.24,bundler-v2.7.2}/settings.rb`).
  #
  # Priority: CLI temporary > local (.bundle/config) > ENV (BUNDLE_*) >
  # global > defaults. Keys are stored with dots doubled to `__` and the
  # `BUNDLE_` prefix, exactly like the reference.
  class Config
    alias Value = Nil | Bool | Int32 | String
    alias ConvertedValue = Nil | Bool | Int32 | String | Array(String)

    BOOL_KEYS = [
      "frozen", "deployment", "cache_all", "cache_all_platforms", "clean",
      "disable_checksum_validation", "disable_exec_load", "disable_local_branch_check",
      "disable_shared_gems", "force", "global_gem_cache", "ignore_funding_requests",
      "lockfile_checksums", "no_install", "no_prune", "plugins", "prefer_local",
      "prune", "silence_deprecations", "disable_version_check",
      "prefer_patch", "update_requires_all_flag", "forget_cli_options",
      "allow_offline_install", "cache_command_is_package", "error_on_stderr",
      "major_deprecations", "path.system", "default_install_uses_path",
    ]

    NUMBER_KEYS = ["jobs", "retry", "redirect", "timeout", "cooldown"]

    ARRAY_KEYS = ["with", "without"]

    DEFAULT_CONFIG = {
      "BUNDLE_SILENCE_DEPRECATIONS"     => false,
      "BUNDLE_DISABLE_VERSION_CHECK"    => true,
      "BUNDLE_PREFER_PATCH"             => false,
      "BUNDLE_REDIRECT"                 => 5,
      "BUNDLE_RETRY"                    => 3,
      "BUNDLE_TIMEOUT"                  => 10,
      "BUNDLE_VERSION"                  => "lockfile",
      "BUNDLE_LOCKFILE_CHECKSUMS"       => true,
      "BUNDLE_CACHE_ALL"                => true,
      "BUNDLE_PLUGINS"                  => true,
      "BUNDLE_GLOBAL_GEM_CACHE"         => false,
      "BUNDLE_UPDATE_REQUIRES_ALL_FLAG" => false,
    }

    private getter temporary : Hash(String, Value)
    getter local_config : Hash(String, Value)
    getter global_config : Hash(String, Value)
    getter local_config_file : String?
    getter global_config_file : String?

    # Keys visible across all configuration sources (the reference `all`
    # excludes defaults: `config list` never shows default-only values).
    def all : Array(String)
      keys = (@temporary.keys | @local_config.keys | @env.keys | @global_config.keys)
      keys.map! do |key|
        key = key.lchop("BUNDLE_")
        key = key.gsub("___", "-").gsub("__", ".")
        key.downcase
      end
      keys.sort
    end

    # `Bundler::Settings#set_local` / `#set_global` + the YAML config write.
    def set_value(name : String, value : String, global : Bool) : Nil
      key = Config.key_for(name)
      hash = global ? @global_config : @local_config
      file = global ? @global_config_file : @local_config_file
      hash[key] = Config.storage_value(name, value)
      Config.write_config(file, hash) if file
    end

    def unset_value(name : String, global : Bool) : Nil
      key = Config.key_for(name)
      hash = global ? @global_config : @local_config
      file = global ? @global_config_file : @local_config_file
      return unless hash.delete(key)
      Config.write_config(file, hash) if file
    end

    # Storage representation: arrays join with `:`; everything else is the
    # raw CLI string (the reference's YAML serializer stores strings).
    def self.storage_value(name : String, value : String) : String
      normalized = name.lchop("BUNDLE_")
      if ARRAY_KEYS.includes?(normalized)
        value.tr(" ", ":")
      else
        value
      end
    end

    def self.write_config(file : String, hash : Hash(String, Value)) : Nil
      Dir.mkdir_p(File.dirname(file))
      text = String.build do |yaml|
        yaml.puts "---"
        hash.each do |key, value|
          next if value.nil?
          yaml.puts "#{key}: #{yaml_string(value.to_s)}"
        end
      end
      temp = "#{file}.#{Process.pid}.tmp"
      File.write(temp, text)
      File.rename(temp, file)
    ensure
      File.delete(temp) if temp && File.file?(temp)
    end

    private def self.yaml_string(value : String) : String
      escaped = value.gsub("\\", "\\\\").gsub("\"", "\\\"")
      "\"#{escaped}\""
    end

    def initialize(project_root : String? = nil, temporary : Hash(String, Value) = {} of String => Value)
      @temporary = temporary
      ignore = ENV["BUNDLE_IGNORE_CONFIG"]?

      local_root =
        if root = project_root
          File.expand_path(File.join(root, ".bundle"))
        else
          File.expand_path(".bundle")
        end

      local_file = ignore ? nil : File.join(local_root, "config")
      @local_config_file = local_file
      @local_config = local_file ? Config.load_config(local_file) : {} of String => Value

      @env = {} of String => Value
      ENV.each do |key, value|
        next unless key.starts_with?("BUNDLE_")
        next if key == "BUNDLE_"
        @env[key] = value
      end

      global_file = ignore ? nil : Config.global_config_file
      @global_config_file = global_file
      @global_config = global_file ? Config.load_config(global_file) : {} of String => Value
    end

    # `Bundler::Settings#pretty_values_for` (pinned reference): per-source
    # values in priority order, converted then inspected.
    def pretty_values_for(name : String) : Array(String)
      key = Config.key_for(name)
      locations = [] of String

      if v = @temporary[key]?
        locations << "Set for the current command: #{Config.display_value(name, v)}"
      end
      if v = @local_config[key]?
        locations << "Set for your local app (#{Config.display_path(@local_config_file || "")}): #{Config.display_value(name, v)}"
      end
      if v = @env[key]?
        locations << "Set via #{key}: #{Config.display_value(name, v)}"
      end
      if v = @global_config[key]?
        locations << "Set for the current user (#{Config.display_path(@global_config_file || "")}): #{Config.display_value(name, v)}"
      end

      return ["You have not configured a value for `#{name}`"] if locations.empty?
      locations
    end

    # The reference builds these paths with `Pathname`, whose separator is `/`
    # even on Windows (`C:/Users/...`); a native Crystal path would print
    # `C:\Users\...` and no longer match the reference byte for byte.
    def self.display_path(path : String) : String
      path.gsub(/\\/, "/")
    end

    # Reference `STRING_KEYS` (settings.rb:59-77): values printed as-is instead
    # of being redacted as credentials/userinfo.
    STRING_KEYS = [
      "bin", "cache_path", "console", "default_cli_command", "gem.ci",
      "gem.github_username", "gem.linter", "gem.rubocop", "gem.test",
      "gemfile", "lockfile", "path", "shebang", "simulate_version",
      "system_bindir", "trust-policy", "version",
    ]

    # `Bundler::Settings#is_string` (settings.rb:358-361).
    def self.string_key?(name : String) : Bool
      normalized = name.lchop("BUNDLE_").downcase
      STRING_KEYS.includes?(normalized) || normalized.starts_with?("local.") ||
        normalized.starts_with?("mirror.") || normalized.starts_with?("build.")
    end

    # `Bundler::Settings#printable_value` (settings.rb:441-462): credential
    # keys are fully redacted and any other string containing a colon is
    # treated as `user:pass`, keeping only the user name. The reference does
    # this for every non-string setting, so a Windows path such as
    # `C:\Users\me` prints as `"C:[REDACTED]"`.
    def self.printable_value(name : String, value : Value) : ConvertedValue
      converted = convert(value, name)
      return converted unless converted.is_a?(String)
      normalized = name.lchop("BUNDLE_").downcase
      if string_key?(normalized)
        converted
      elsif normalized == "gem.push_key"
        "[REDACTED]"
      elsif converted.includes?(":")
        parts = converted.split(":", 2)
        username = parts[0]
        password = parts.size > 1 ? parts[1] : ""
        if password == "x-oauth-basic"
          username = "[REDACTED]"
        else
          password = "[REDACTED]"
        end
        "#{username}:#{password}"
      else
        converted
      end
    end

    # `--parseable` rendering (`#{setting}=#{value}`): arrays use the symbol
    # form `[:test, :development]`, everything else converts without `inspect`.
    def self.parseable_converted(converted : ConvertedValue) : String
      if converted.is_a?(Array(String))
        "[" + converted.map { |item| ":#{item}" }.join(", ") + "]"
      else
        converted.to_s
      end
    end

    # Reference display of a converted value: array settings (`with`,
    # `without`) are symbol arrays, so `inspect` renders `[:test, :development]`.
    def self.display_value(name : String, value : Value) : String
      printable = printable_value(name, value)
      if printable.is_a?(Array(String))
        return "[" + printable.map { |item| ":#{item}" }.join(", ") + "]"
      end
      printable.inspect
    end

    # `Bundler::Settings.key_for`: dots doubled, dashes tripled, uppercased,
    # BUNDLE_ prefix; URI-style keys get the reference's trailing slash.
    def self.key_for(key : String) : String
      key = key.lchop("BUNDLE_")
      # `mirror.<url>.fallback_timeout` keeps its option suffix outside URI
      # normalization: the reference normalizes the URI part (trailing slash)
      # and re-appends `.__FALLBACK_TIMEOUT` (settings.rb L519-550).
      suffix = ""
      if key.ends_with?(".fallback_timeout")
        key = key[0, key.size - ".fallback_timeout".size]
        suffix = "__FALLBACK_TIMEOUT"
      elsif key.ends_with?("__FALLBACK_TIMEOUT")
        key = key[0, key.size - "__FALLBACK_TIMEOUT".size]
        suffix = "__FALLBACK_TIMEOUT"
      end
      key += "/" if key.matches?(/https?:/i) && !key.ends_with?("/")
      key = key.gsub(".", "__")
      key = key.gsub("-", "___")
      "BUNDLE_#{key.upcase}#{suffix}"
    end

    def self.global_config_file : String?
      if value = ENV["BUNDLE_CONFIG"]?
        return value unless value.empty?
      end
      if value = ENV["BUNDLE_USER_CONFIG"]?
        return value unless value.empty?
      end
      if value = ENV["BUNDLE_USER_HOME"]?
        return File.join(value, "config") unless value.empty?
      end
      if home = user_home
        return File.join(home, ".bundle", "config")
      end
      nil
    end

    def self.user_home : String?
      # Ruby's `File.expand_path("~")` honors HOME before the Windows profile
      # variables, so a caller that isolates HOME (specs, differential sandboxes)
      # also moves the user-level `.bundle` config and cache. Preferring
      # USERPROFILE sent those writes to the real profile instead.
      if home = ENV["HOME"]?
        return home unless home.empty?
      end
      {% if flag?(:windows) %}
        ENV["USERPROFILE"]? || (ENV["HOMEDRIVE"]? && ENV["HOMEPATH"]? && File.join(ENV["HOMEDRIVE"].not_nil!, ENV["HOMEPATH"].not_nil!))
      {% else %}
        nil
      {% end %}
    end

    # Loads a Bundler config file: shallow YAML mapping with the reference's
    # key normalization (URLs get a trailing slash, dots -> `__`,
    # `-` -> `___`, `#`-prefixed keys skipped).
    def self.load_config(path : String) : Hash(String, Value)
      config = {} of String => Value
      return config unless File.file?(path)
      text = File.read(path)

      text.each_line do |line|
        line = line.strip
        next if line.empty? || line == "---" || line.starts_with?("#")

        separator = line.index(": ")
        if line.ends_with?(":")
          key = line.rchop
          value = ""
        elsif separator
          key = line[0...separator]
          value = line[(separator + 2)..]
        else
          next
        end

        key = key.strip
        key += "/" if key.matches?(/https?:/i) && !key.ends_with?("/") && !key.ends_with?("__FALLBACK_TIMEOUT")
        key = key.gsub(".", "__")

        # YAML values arrive quoted; strip the surrounding quotes like the
        # reference serializer load does.
        if value.size >= 2 && value.starts_with?('"') && value.ends_with?('"')
          value = value[1...-1]
        end

        config[key] = value unless key.starts_with?("#")
      end

      config
    end

    def has?(name : String) : Bool
      key = Config.key_for(name)
      @temporary.has_key?(key) || @local_config.has_key?(key) ||
        @env.has_key?(key) || @global_config.has_key?(key)
    end

    def set_local(name : String, value : String?) : Nil
      set_in(@local_config_file, @local_config, name, value)
    end

    def set_global(name : String, value : String?) : Nil
      set_in(@global_config_file, @global_config, name, value)
    end

    private def set_in(path : String?, store : Hash(String, Value), name : String, value : String?) : Nil
      return if path.nil?
      key = Config.key_for(name)
      if value.nil?
        store.delete(key)
      else
        store[key] = value
      end
      Config.write_config(path, store)
    end

    # Reference `Settings#key_for` display inverse (`BUNDLE_PATH` -> `path`,
    # `BUNDLE_GEM__GITHUB_USERNAME` -> `gem.github_username`).
    def self.display_name(key : String) : String
      key.lchop("BUNDLE_").downcase.gsub("__", ".")
    end

    # Writes the config file the way the reference does: `---` document start,
    # one `KEY: "value"` line per entry in insertion order.
    def self.write_config(path : String, store : Hash(String, Value)) : Nil
      Dir.mkdir_p(File.dirname(path)) unless File.dirname(path).empty?
      text = String.build do |io|
        io.puts "---"
        store.each do |key, value|
          io.puts "#{key}: #{quote_yaml(value.to_s)}"
        end
      end
      File.write(path, text)
    end

    def self.quote_yaml(value : String) : String
      escaped = value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\n").gsub("\r", "\\r").gsub("\t", "\\t")
      "\"#{escaped}\""
    end

    def [](name : String) : ConvertedValue
      key = Config.key_for(name)

      v = @temporary[key]? || @local_config[key]? || @env[key]? || @global_config[key]? ||
          DEFAULT_CONFIG[key]?

      Config.convert(v, name)
    end

    def frozen? : Bool
      self["frozen"] == true || self["deployment"] == true
    end

    # Number of cooldown days (4.0.24 `cooldown` setting); nil unless set.
    def cooldown_days : Int32?
      value = self["cooldown"]
      return nil if value.nil?
      return value if value.is_a?(Int32)
      value.to_s.to_i?
    end

    # Bundler mirror support: `mirror.<url>` (and `mirror.<url>.fallback_timeout`)
    # map a source URL onto a mirror URL. Keys are tried with and without a
    # trailing slash to tolerate Bundler's normalization (config-keys.md).
    def mirror_for(remote : String) : String?
      candidates = [remote, remote.chomp("/"), "#{remote}/"].uniq
      candidates.each do |candidate|
        value = self["mirror.#{candidate}"]
        result = case value
                 when String
                   value
                 when Nil
                   nil
                 else
                   value.to_s
                 end
        return result unless result.nil? || result.empty?
      end
      nil
    end

    # Bundler `mirror.<url>.fallback_timeout` (mirror.rb L82-92). `nil` means
    # the option is not configured; 0 means "do not probe the mirror".
    def mirror_fallback_timeout(remote : String) : Float64?
      candidates = [remote, remote.chomp("/"), "#{remote}/"].uniq
      candidates.each do |candidate|
        value = self["mirror.#{candidate}.fallback_timeout"]
        return Config.fallback_timeout_seconds(value) unless value.nil?
      end
      nil
    end

    # Shared parser for the `fallback_timeout` option value. Bundler maps
    # `true`/`"true"` to 0.1 seconds, `false`/`"false"` to 0 and everything
    # else through a numeric conversion (mirror.rb L82-92).
    def self.fallback_timeout_seconds(value : ConvertedValue) : Float64?
      case value
      when Nil
        nil
      when Bool
        value ? 0.1 : 0.0
      when Int32
        value.to_f64
      else
        text = value.to_s.strip
        case text.downcase
        when "true"  then 0.1
        when "false" then 0.0
        else
          # Bundler truncates the numeric branch (`timeout.to_i`), so "2.5"
          # becomes 2 and "0.5" becomes 0 (= no probe).
          (text.to_f? || 0.0).to_i.to_f64
        end
      end
    end

    # Bundler `Settings#credentials_for`: the full URI string is consulted
    # first, then the bare host. Values use the `user:password` form.
    # Callers must never print the returned pair (architecture §4).
    def credentials_for(remote : String) : {String, String}?
      uri = begin
        URI.parse(remote)
      rescue
        nil
      end
      candidates = [remote]
      if uri && (host = uri.host) && !host.empty?
        candidates << "#{uri.scheme}://#{host}/"
        candidates << host
      end
      candidates.uniq.each do |candidate|
        value = self[candidate]
        next if value.nil?
        text = value.to_s
        next if text.empty?
        user, _, password = text.partition(":")
        return {user, password} unless user.empty?
      end
      nil
    end

    def self.convert(value : Value, key : String) : ConvertedValue
      normalized = key.lchop("BUNDLE_")

      if Config::ARRAY_KEYS.includes?(normalized)
        Config.to_array(value)
      elsif value.nil?
        nil
      elsif Config::BOOL_KEYS.includes?(normalized) || value == "false"
        Config.to_bool(value)
      elsif Config::NUMBER_KEYS.includes?(normalized)
        value.to_s.to_i? || 0
      else
        value.to_s
      end
    end

    def self.to_bool(value : Value) : Bool
      case value
      when String
        !(value =~ /\A(false|f|no|n|0|)\z/i)
      when Nil, false
        false
      else
        true
      end
    end

    def self.to_array(value : Value) : Array(String)
      return [] of String if value.nil?
      value.to_s.tr(" ", ":").split(":")
    end
  end
end
