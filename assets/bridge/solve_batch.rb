# frozen_string_literal: true

# Pure-data compatibility boundary for M8 L161 S1. This file deliberately does
# not load the bridge server, evaluate a Gemfile, install gems, or write locks.
require "digest"
require "json"
require "set"
require "time"
require "timeout"
require "uri"
require "bundler"

module Celerite
  module SolveBatch
    SCHEMA = "celerite.solve_batch/3".freeze
    REFERENCE_BUNDLER = "4.0.24".freeze
    MAX_REQUEST_BYTES = 32 * 1024 * 1024
    MAX_RESPONSE_BYTES = 8 * 1024 * 1024
    MAX_CANDIDATES = 100_000
    MAX_SOURCES = 4_096
    MAX_NAMES = 10_000
    SCHEMA_PATH = File.expand_path("solve_batch.schema.json", __dir__)
    SCHEMA_DOCUMENT = JSON.parse(File.read(SCHEMA_PATH)).freeze

    class Error < StandardError
      attr_reader :category, :error_class, :incompatibilities

      def initialize(category, message, error_class = nil, incompatibilities = [])
        @category = category
        @error_class = error_class || self.class.name
        @incompatibilities = incompatibilities
        super(message)
      end
    end

    class SchemaError < Error
      def initialize(message)
        super("internal", message, "schema_invalid")
      end
    end

    class NoMaterializationError < Error
      def initialize(message)
        super("internal", message, "pure_data_materialization_forbidden")
      end
    end

    # The runtime validator implements the JSON Schema subset used by
    # solve_batch.schema.json. Keeping one schema document as the contract avoids
    # a second, drifting hand-written list of fields.
    class SchemaValidator
      def self.validate!(value, schema = SCHEMA_DOCUMENT, path = "$")
        new(schema).validate!(value, schema, path)
      end

      def initialize(root)
        @root = root
      end

      def validate!(value, schema, path)
        if (ref = schema["$ref"])
          target = ref.delete_prefix("#").split("/").reject(&:empty?).reduce(@root) do |node, key|
            pointer_key = key.gsub("~1", "/").gsub("~0", "~")
            node.is_a?(Hash) && node.key?(pointer_key) ? node[pointer_key] : nil
          end
          raise SchemaError, "#{path}: unresolved schema reference #{ref}" unless target
          return validate!(value, target, path)
        end

        if (one_of = schema["oneOf"])
          matches = one_of.count do |branch|
            begin
              validate!(value, branch, path)
              true
            rescue SchemaError
              false
            end
          end
          raise SchemaError, "#{path}: expected exactly one oneOf branch, got #{matches}" unless matches == 1
        end

        if (types = schema["type"])
          types = [types] if types.is_a?(String)
          unless types.any? {|type| matches_type?(value, type) }
            raise SchemaError, "#{path}: expected #{types.join(" or ")}, got #{value.class}"
          end
        end

        validate_const!(value, schema, path)
        validate_enum!(value, schema, path)
        validate_string!(value, schema, path)
        validate_number!(value, schema, path)
        validate_array!(value, schema, path)
        validate_object!(value, schema, path)
      end

      private

      def matches_type?(value, type)
        case type
        when "null" then value.nil?
        when "boolean" then value == true || value == false
        when "object" then value.is_a?(Hash)
        when "array" then value.is_a?(Array)
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "number" then value.is_a?(Numeric)
        else false
        end
      end

      def fail(path, message)
        raise SchemaError, "#{path}: #{message}"
      end

      def validate_const!(value, schema, path)
        fail(path, "expected #{schema["const"].inspect}") if schema.key?("const") && value != schema["const"]
      end

      def validate_enum!(value, schema, path)
        fail(path, "expected one of #{schema["enum"].inspect}") if schema["enum"] && !schema["enum"].include?(value)
      end

      def validate_string!(value, schema, path)
        return unless value.is_a?(String)
        fail(path, "is shorter than #{schema["minLength"]}") if schema["minLength"] && value.length < schema["minLength"]
        fail(path, "is longer than #{schema["maxLength"]}") if schema["maxLength"] && value.length > schema["maxLength"]
        if schema["pattern"] && !Regexp.new(schema["pattern"]).match?(value)
          fail(path, "does not match #{schema["pattern"]}")
        end
      end

      def validate_number!(value, schema, path)
        return unless value.is_a?(Numeric)
        fail(path, "is below #{schema["minimum"]}") if schema["minimum"] && value < schema["minimum"]
        fail(path, "is above #{schema["maximum"]}") if schema["maximum"] && value > schema["maximum"]
      end

      def validate_array!(value, schema, path)
        return unless value.is_a?(Array)
        fail(path, "has fewer than #{schema["minItems"]} items") if schema["minItems"] && value.length < schema["minItems"]
        fail(path, "has more than #{schema["maxItems"]} items") if schema["maxItems"] && value.length > schema["maxItems"]
        fail(path, "has duplicate items") if schema["uniqueItems"] && value.uniq.length != value.length
        if schema["items"]
          value.each_with_index {|item, index| validate!(item, schema["items"], "#{path}[#{index}]") }
        end
      end

      def validate_object!(value, schema, path)
        return unless value.is_a?(Hash)
        required = schema["required"] || []
        missing = required - value.keys
        fail(path, "is missing required fields: #{missing.join(", ")}") unless missing.empty?

        properties = schema["properties"] || {}
        additional = schema.fetch("additionalProperties", true)
        value.each do |key, item|
          child_path = "#{path}.#{key}"
          if properties.key?(key)
            validate!(item, properties[key], child_path)
          elsif additional == false
            fail(path, "has unknown field #{key.inspect}")
          elsif additional.is_a?(Hash)
            validate!(item, additional, child_path)
          end
        end
        fail(path, "has more than #{schema["maxProperties"]} properties") if schema["maxProperties"] && value.length > schema["maxProperties"]
      end
    end

    class PureGemsSource < Bundler::Source::Rubygems
      attr_reader :source_id, :candidate_index, :materialization_calls

      def initialize(source_id, candidate_index, remotes)
        super("remotes" => remotes)
        @source_id = source_id
        @candidate_index = candidate_index
        @materialization_calls = 0
      end

      def specs
        @candidate_index
      end

      def remote_specs(*)
        materialization_forbidden!
      end

      def installed_specs(*)
        materialization_forbidden!
      end

      def cached_specs(*)
        materialization_forbidden!
      end

      def fetch_specs(*)
        materialization_forbidden!
      end

      private

      def materialization_forbidden!
        @materialization_calls += 1
        raise NoMaterializationError, "pure-data source #{source_id} attempted remote/cache/installed materialization"
      end
    end

    class PureMetadataSource < Bundler::Source::Metadata
      def initialize(ruby_version, rubygems_version)
        index = Bundler::Index.build do |idx|
          idx << Gem::Specification.new("Ruby\0", Gem::Version.new(ruby_version))
          idx << Gem::Specification.new("RubyGems\0", Gem::Version.new(rubygems_version)) do |spec|
            spec.required_rubygems_version = Gem::Requirement.default
          end
          idx << Gem::Specification.new do |spec|
            spec.name = "bundler"
            spec.version = Gem::Version.new(REFERENCE_BUNDLER)
            spec.platform = Gem::Platform::RUBY
            spec.summary = "Bundler reference metadata"
            spec.authors = ["celerite"]
          end
        end
        index.each {|spec| spec.source = self }
        @candidate_index = index.freeze
      end

      def specs
        @candidate_index
      end
    end

    module_function

    def parse(raw)
      raise SchemaError, "request exceeds #{MAX_REQUEST_BYTES} bytes" if raw.bytesize > MAX_REQUEST_BYTES
      request = JSON.parse(raw)
      SchemaValidator.validate!(request)
      request
    rescue JSON::ParserError => error
      raise SchemaError, "invalid JSON: #{error.message}"
    end

    def canonical_json(value)
      JSON.generate(canonicalize(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).each_with_object({}) do |key, output|
          output[key] = canonicalize(value[key])
        end
      when Array
        value.map {|item| canonicalize(item) }
      else
        value
      end
    end

    def candidate_digest(candidates_by_source)
      normalized = candidates_by_source.each_with_object({}) do |(source_id, candidates), output|
        output[source_id] = candidates.map do |candidate|
          normalized_candidate = canonicalize(candidate)
          normalized_candidate["dependencies"] = normalized_candidate["dependencies"].sort_by do |dependency|
            [dependency["name"], dependency["requirements"].sort]
          end
          normalized_candidate["dependencies"].each {|dependency| dependency["requirements"] = dependency["requirements"].sort }
          normalized_candidate["checksum"] = normalized_candidate["checksum"]&.merge("value" => normalized_candidate["checksum"]["value"].downcase)
          normalized_candidate
        end.sort_by {|candidate| [candidate["name"], candidate["version"], candidate["platform"]] }
      end
      Digest::SHA256.hexdigest(canonical_json(normalized))
    end

    def source_identity(source)
      normalized = canonicalize(source.reject {|key, _| key == "identity_sha256" })
      normalized["remotes"] = normalized["remotes"].sort
      Digest::SHA256.hexdigest(canonical_json(normalized))
    end

    def locked_digest(specs)
      normalized = specs.map do |spec|
        item = canonicalize(spec)
        item["dependencies"] = item["dependencies"].sort_by {|dependency| [dependency["name"], dependency["requirements"].sort] }
        item["dependencies"].each {|dependency| dependency["requirements"] = dependency["requirements"].sort }
        item["checksum"] = item["checksum"]&.merge("value" => item["checksum"]["value"].downcase)
        item
      end.sort_by {|spec| [spec["source_id"], spec["name"], spec["version"], spec["platform"]] }
      Digest::SHA256.hexdigest(canonical_json(normalized))
    end

    # Returns the real Bundler::SpecSet produced by Bundler 4.0.24. The resolver
    # returns an Array in this release after variants are unioned; wrapping that
    # array is the explicit SpecSet boundary required by S1.
    def resolve(request)
      solve_internal(request).first
    end

    def call(request)
      raw = request.is_a?(String) ? request : JSON.generate(request)
      parsed = parse(raw)
      stats = base_stats(raw, parsed)
      spec_set, timings, context = solve_internal(parsed, stats)
      chosen = serialize_chosen(spec_set, context)
      result = {
        "chosen" => chosen,
        "edges" => serialize_edges(chosen, parsed["requirements"]),
        "variants" => serialize_variants(chosen),
        "failure" => nil,
        "stats" => stats.merge("materialize_ms" => timings[0], "solve_ms" => timings[1])
      }
      check_response_size!(result)
      {"schema" => SCHEMA, "ok" => true, "result" => result}
    rescue Error => error
      failure_response(error, stats || base_stats(raw.to_s, {}))
    rescue Timeout::Error => error
      failure_response(Error.new("timeout", error.message, error.class.name), stats || base_stats(raw.to_s, {}))
    rescue StandardError => error
      failure_response(Error.new("internal", error.message, error.class.name), stats || base_stats(raw.to_s, {}))
    end

    def solve_internal(request, stats = nil)
      context = validate_semantics!(request)
      stats ||= base_stats(JSON.generate(request), request)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sources = build_sources(request, context)
      metadata = PureMetadataSource.new(request.dig("constraints", "ruby_version"), request.dig("constraints", "rubygems_version"))
      dependencies = root_dependencies(request, sources, context)
      locked = build_locked_spec_set(request, sources, context)
      platforms = effective_platforms(request)
      source_requirements = { :default => default_source(sources) }
      request["requirements"].each do |requirement|
        source = source_for_requirement(requirement, sources, context)
        source_requirements[requirement["name"]] = source if source
      end
      request["locked_base"]["specs"].each do |spec|
        source_requirements[spec["name"]] = sources.fetch(spec["source_id"])
      end
      source_requirements["Ruby\0"] = metadata
      source_requirements["RubyGems\0"] = metadata
      source_requirements["bundler"] = metadata
      source_requirements[:default_bundler] = metadata

      dependencies.concat([
        Bundler::Dependency.new("Ruby\0", request.dig("constraints", "ruby_version")),
        Bundler::Dependency.new("RubyGems\0", request.dig("constraints", "rubygems_version"))
      ])

      promotion = request["promotion"]
      options = {
        locked_specs: locked,
        unlock: promotion["unlock"] ? (promotion["conservative"] ? request["requirements"].map {|requirement| requirement["name"] } : true) : [],
        prerelease: promotion["pre"],
        prefer_local: promotion["prefer_local"],
        new_platforms: request.dig("constraints", "added_platforms").map {|platform| Gem::Platform.new(platform) },
        explicit_unlocks: []
      }
      materialize_ms = elapsed_ms(started)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      spec_set = with_silent_bundler do
        Timeout.timeout(request.dig("limits", "timeout_ms") / 1000.0) do
          unlock_names = options[:unlock] == true ? locked.to_a.map(&:name) : options[:unlock]
          base_specs = locked.to_a.reject {|spec| unlock_names.include?(spec.name) }
          base = Bundler::Resolver::Base.new(source_requirements, dependencies, Bundler::SpecSet.new(base_specs), platforms, options)
          promoter = Bundler::GemVersionPromoter.new
          promoter.level = promotion["level"].to_sym
          promoter.strict = promotion["strict"]
          promoter.pre = promotion["pre"]
          resolved = Bundler::Resolver.new(base, promoter).start
          resolved = Bundler::SpecSet.new(resolved) unless resolved.is_a?(Bundler::SpecSet)
          unless resolved.is_a?(Bundler::SpecSet)
            raise Error.new("internal", "Bundler::Resolver#start did not produce a SpecSet boundary")
          end
          resolved
        end
      end
      solve_ms = elapsed_ms(started)

      sources.each_value do |source|
        raise NoMaterializationError, "pure-data source #{source.source_id} attempted materialization" unless source.materialization_calls.zero?
      end
      validate_resolved_closure!(spec_set, context)
      [spec_set, [materialize_ms, solve_ms], context]
    rescue Error
      raise
    rescue Timeout::Error
      raise
    rescue Bundler::SolveFailure, Bundler::GemNotFound => error
      raise Error.new(classify_resolver_error(error.message), error.message, error.class.name)
    rescue StandardError => error
      raise Error.new("internal", error.message, error.class.name)
    end

    def validate_semantics!(request)
      guard_credentials!(request)
      fingerprint = request.dig("evaluation", "fingerprint")
      unless fingerprint["state"] == "deterministic"
        raise Error.new("source_unsupported", "evaluation fingerprint is #{fingerprint["state"]}: #{fingerprint["state_reason"]}")
      end
      unless request.dig("constraints", "bundler_version") == REFERENCE_BUNDLER
        raise Error.new("source_unsupported", "only Bundler #{REFERENCE_BUNDLER} is supported by this harness")
      end
      if request.dig("promotion", "local_only")
        raise Error.new("source_unsupported", "local_only cannot be proven from a pure remote-data candidate closure")
      end

      source_list = request.dig("evaluation", "sources")
      raise Error.new("source_unsupported", "at least one source is required") if source_list.empty?
      raise Error.new("source_unsupported", "source count exceeds #{MAX_SOURCES}") if source_list.length > MAX_SOURCES
      sources = {}
      source_list.each do |source|
        source_id = source["source_id"]
        raise Error.new("source_unsupported", "duplicate source_id #{source_id.inspect}") if sources.key?(source_id)
        unless source["type"] == "Rubygems" && source["materialization"] == "pure_data"
          raise Error.new("source_unsupported", "source #{source_id.inspect} is #{source["type"]}/#{source["materialization"]}, not pure GEM data")
        end
        validate_redacted_uri!(source["uri_redacted"], "source #{source_id} uri_redacted") if source["uri_redacted"]
        source["remotes"].each_with_index {|remote, index| validate_redacted_uri!(remote, "source #{source_id} remotes[#{index}]") }
        expected_identity = source_identity(source)
        unless source["identity_sha256"] == expected_identity
          raise Error.new("source_unsupported", "source #{source_id.inspect} identity_sha256 mismatch")
        end
        sources[source_id] = source
      end
      raise Error.new("source_unsupported", "multiple sources require a source_id named default") if sources.length > 1 && !sources.key?("default")

      candidates_by_source = request["candidates_by_source"]
      unless candidates_by_source.keys.sort == sources.keys.sort
        raise Error.new("candidate_incomplete", "candidates_by_source keys must exactly match pure GEM source ids")
      end
      candidate_count = candidates_by_source.values.sum(&:length)
      raise Error.new("candidate_incomplete", "candidate count exceeds #{MAX_CANDIDATES}") if candidate_count > MAX_CANDIDATES
      name_count = candidates_by_source.values.flatten.map {|candidate| candidate["name"] }.uniq.length
      raise Error.new("candidate_incomplete", "candidate name count exceeds #{MAX_NAMES}") if name_count > MAX_NAMES

      candidate_map = {}
      checksum_map = {}
      candidates_by_source.each do |source_id, candidates|
        candidates.each do |candidate|
          validate_candidate_values!(candidate, source_id)
          key = candidate_key(candidate, source_id)
          if candidate_map.key?(key)
            previous = candidate_map[key]
            category = previous["checksum"] != candidate["checksum"] ? "checksum_invalid" : "candidate_incomplete"
            raise Error.new(category, "duplicate candidate #{key.inspect}")
          end
          candidate_map[key] = candidate.merge("source_id" => source_id)
          if candidate["checksum"]
            checksum_key = [source_id, candidate["name"], candidate["version"], candidate["platform"]]
            checksum_map[checksum_key] = candidate["checksum"]["value"].downcase
          end
        end
      end

      closure = request["candidate_closure"]
      digest = candidate_digest(candidates_by_source)
      unless closure["digest"] == digest
        raise Error.new("candidate_incomplete", "candidate_closure digest mismatch: expected #{digest}")
      end
      unless closure["candidate_count"] == candidate_count && closure["name_count"] == name_count
        raise Error.new("candidate_incomplete", "candidate_closure count mismatch")
      end
      unless closure["complete"]
        raise Error.new("candidate_incomplete", "candidate_closure is explicitly incomplete")
      end

      reachable = reachable_names(request, candidate_map)
      candidate_names = candidate_map.values.map {|candidate| candidate["name"] }.uniq
      missing = reachable - candidate_names
      unless missing.empty?
        raise Error.new("candidate_incomplete", "candidate closure is missing names: #{missing.sort.join(", ")}")
      end
      extra = candidate_names - reachable
      unless extra.empty?
        raise Error.new("candidate_incomplete", "candidate closure contains unreachable names: #{extra.sort.join(", ")}")
      end

      locked_digest_actual = locked_digest(request.dig("locked_base", "specs"))
      unless request.dig("locked_base", "sha256") == locked_digest_actual
        raise Error.new("candidate_incomplete", "locked_base sha256 mismatch: expected #{locked_digest_actual}")
      end
      request.dig("locked_base", "specs").each do |spec|
        key = candidate_key(spec, spec["source_id"])
        candidate = candidate_map[key]
        raise Error.new("candidate_incomplete", "locked candidate #{key.inspect} is absent from the candidate closure") unless candidate
        locked_dependencies = spec["dependencies"].map {|dependency| [dependency["name"], dependency["requirements"].sort] }.sort
        candidate_dependencies = candidate["dependencies"].map {|dependency| [dependency["name"], dependency["requirements"].sort] }.sort
        unless locked_dependencies == candidate_dependencies
          raise Error.new("candidate_incomplete", "locked dependency declaration changed for #{key.inspect}")
        end
        if spec["checksum"] && candidate["checksum"]&.fetch("value")&.downcase != spec["checksum"]["value"].downcase
          raise Error.new("checksum_invalid", "locked checksum mismatch for #{key.inspect}")
        end
        if checksum_map[[spec["source_id"], spec["name"], spec["version"], spec["platform"]]] &&
           spec["checksum"] && checksum_map[[spec["source_id"], spec["name"], spec["version"], spec["platform"]]] != spec["checksum"]["value"].downcase
          raise Error.new("checksum_invalid", "candidate checksum changed for #{key.inspect}")
        end
      end

      {
        "sources" => sources,
        "candidate_map" => candidate_map,
        "candidate_digest" => digest,
        "candidate_count" => candidate_count,
        "name_count" => name_count
      }
    end

    def validate_candidate_values!(candidate, source_id)
      Gem::Version.new(candidate["version"])
      Gem::Platform.new(candidate["platform"])
      candidate["dependencies"].each do |dependency|
        Gem::Requirement.new(dependency["requirements"])
      end
      Gem::Requirement.new(candidate["required_ruby_version"]) if candidate["required_ruby_version"]
      Gem::Requirement.new(candidate["required_rubygems_version"]) if candidate["required_rubygems_version"]
    rescue ArgumentError => error
      raise Error.new("candidate_incomplete", "invalid candidate in source #{source_id.inspect}: #{error.message}")
    end

    def reachable_names(request, candidate_map)
      names = request["requirements"].map {|requirement| requirement["name"] } +
              request.dig("locked_base", "specs").map {|spec| spec["name"] }
      seen = Set.new(names)
      queue = names.dup
      until queue.empty?
        name = queue.shift
        candidate_map.values.select {|candidate| candidate["name"] == name }.each do |candidate|
          candidate["dependencies"].each do |dependency|
            next if seen.include?(dependency["name"])
            seen.add(dependency["name"])
            queue << dependency["name"]
          end
        end
      end
      seen.to_a
    end

    def guard_credentials!(value, path = "$")
      case value
      when Hash
        value.each do |key, item|
          if key.match?(/(?:password|passwd|token|secret|authorization|api[_-]?key|private[_-]?key)/i)
            raise Error.new("source_unsupported", "credential-bearing field is forbidden at #{path}.#{key}")
          end
          guard_credentials!(item, "#{path}.#{key}")
        end
      when Array
        value.each_with_index {|item, index| guard_credentials!(item, "#{path}[#{index}]") }
      when String
        if value.match?(%r{://[^/\s:@]+:[^/\s@]+@}) || value.match?(/(?:password|passwd|token|secret|authorization|api[_-]?key|private[_-]?key)\s*[:=]\s*\S+/i)
          raise Error.new("source_unsupported", "credential-bearing value is forbidden at #{path}")
        end
      end
    end

    def validate_redacted_uri!(value, path)
      uri = URI.parse(value)
      unless %w[http https file].include?(uri.scheme) && uri.host && !uri.userinfo
        raise Error.new("source_unsupported", "#{path} must be an absolute redacted http/https/file URI without userinfo")
      end
    rescue URI::InvalidURIError => error
      raise Error.new("source_unsupported", "#{path} is invalid: #{error.message}")
    end

    def candidate_key(candidate, source_id = candidate["source_id"])
      [source_id, candidate["name"], Gem::Version.new(candidate["version"]).to_s, Gem::Platform.new(candidate["platform"]).to_s]
    end

    def build_sources(request, context)
      context["sources"].each_with_object({}) do |(source_id, source), output|
        specs = request["candidates_by_source"].fetch(source_id).map do |candidate|
          build_candidate_spec(candidate)
        end
        index = Bundler::Index.build {|idx| specs.each {|spec| idx.add(spec) } }
        pure_source = PureGemsSource.new(source_id, index.freeze, source["remotes"])
        specs.each {|spec| spec.source = pure_source }
        output[source_id] = pure_source
      end
    end

    def build_candidate_spec(candidate)
      Gem::Specification.new do |spec|
        spec.name = candidate["name"]
        spec.version = Gem::Version.new(candidate["version"])
        spec.platform = Gem::Platform.new(candidate["platform"])
        spec.summary = "Pure-data solve_batch candidate"
        spec.authors = ["celerite"]
        spec.required_ruby_version = candidate["required_ruby_version"] ? Gem::Requirement.new(candidate["required_ruby_version"]) : Gem::Requirement.default
        spec.required_rubygems_version = candidate["required_rubygems_version"] ? Gem::Requirement.new(candidate["required_rubygems_version"]) : Gem::Requirement.default
        candidate["dependencies"].each do |dependency|
          spec.add_runtime_dependency(dependency["name"], dependency["requirements"])
        end
      end
    end

    def build_locked_spec_set(request, sources, context)
      specs = request.dig("locked_base", "specs").map do |locked|
        candidate = context["candidate_map"].fetch(candidate_key(locked, locked["source_id"]))
        spec = build_candidate_spec(candidate)
        spec.source = sources.fetch(locked["source_id"])
        lazy = Bundler::LazySpecification.from_spec(spec)
        lazy.dependencies = locked["dependencies"].map do |dependency|
          Bundler::Dependency.new(dependency["name"], dependency["requirements"])
        end
        lazy
      end
      Bundler::SpecSet.new(specs)
    end

    def default_source(sources)
      sources.length == 1 ? sources.values.first : sources.fetch("default")
    end

    def source_for_requirement(requirement, sources, context)
      return nil unless requirement["source_id"]
      source = sources[requirement["source_id"]]
      raise Error.new("source_unsupported", "unknown source_id #{requirement["source_id"].inspect}") unless source
      source
    end

    def root_dependencies(request, sources, context)
      request["requirements"].map do |requirement|
        platform_options = requirement["platforms"].map do |platform|
          mapped = Bundler::CurrentRuby::PLATFORM_MAP[platform.to_sym]
          raise Error.new("source_unsupported", "unsupported requirement platform selector #{platform.inspect}") unless mapped
          platform.to_sym
        end
        Bundler::Dependency.new(requirement["name"], requirement["requirements"],
          "platforms" => platform_options,
          "force_ruby_platform" => requirement["force_ruby_platform"] || request.dig("constraints", "force_ruby_platform"),
          "source" => source_for_requirement(requirement, sources, context))
      end
    end

    def effective_platforms(request)
      constraints = request["constraints"]
      removed = constraints["removed_platforms"]
      platforms = (constraints["platforms"] + constraints["added_platforms"]).reject {|platform| removed.include?(platform) }.uniq
      raise Error.new("platform_unavailable", "no effective resolution platforms remain") if platforms.empty?
      platforms.map {|platform| Gem::Platform.new(platform) }
    end

    def with_silent_bundler
      previous = Bundler.ui
      Bundler.ui = Bundler::UI::Silent.new
      yield
    ensure
      Bundler.ui = previous
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0).round(3)
    end

    def base_stats(raw, request)
      candidates = request.is_a?(Hash) ? request["candidates_by_source"] || {} : {}
      {
        "candidate_bytes" => raw.bytesize,
        "candidate_count" => candidates.values.sum(&:length),
        "source_count" => request.is_a?(Hash) ? (request.dig("evaluation", "sources") || []).length : 0,
        "name_count" => candidates.values.flatten.map {|candidate| candidate["name"] }.uniq.length,
        "materialize_ms" => 0,
        "solve_ms" => 0,
        "candidate_digest" => candidates.empty? ? Digest::SHA256.hexdigest(canonical_json({})) : candidate_digest(candidates),
        "bridge_pid" => Process.pid,
        "relaxations" => [],
        "fallback_reason" => nil
      }
    end

    def serialize_chosen(spec_set, context)
      spec_set.to_a.reject {|spec| spec.name.end_with?("\0") }.map do |spec|
        source_id = spec.source.is_a?(PureGemsSource) ? spec.source.source_id : nil
        key = candidate_key({ "name" => spec.name, "version" => spec.version.to_s, "platform" => spec.platform.to_s }, source_id)
        candidate = context["candidate_map"][key]
        raise Error.new("candidate_incomplete", "resolver selected unknown candidate #{key.inspect}") unless candidate
        {
          "name" => spec.name,
          "version" => spec.version.to_s,
          "platform" => spec.platform.to_s,
          "source_id" => source_id,
          "dependencies" => serialize_dependencies(spec.runtime_dependencies),
          "checksum" => candidate["checksum"],
          "required_ruby_version" => candidate["required_ruby_version"],
          "required_rubygems_version" => candidate["required_rubygems_version"]
        }
      end.sort_by {|spec| [spec["name"], spec["version"], spec["platform"], spec["source_id"]] }
    end

    def serialize_dependencies(dependencies)
      dependencies.map do |dependency|
        {"name" => dependency.name, "requirements" => dependency.requirement.as_list}
      end.sort_by {|dependency| [dependency["name"], dependency["requirements"]] }
    end

    def spec_output_key(spec)
      "#{spec["name"]}/#{spec["version"]}/#{spec["platform"]}"
    end

    def serialize_edges(chosen, requirements)
      edges = []
      requirements.each do |requirement|
        chosen.select {|spec| spec["name"] == requirement["name"] }.each do |spec|
          edges << {"from" => "root", "to" => spec_output_key(spec), "requirements" => requirement["requirements"].sort}
        end
      end
      chosen.each do |source|
        source["dependencies"].each do |dependency|
          chosen.select {|target| target["name"] == dependency["name"] }.each do |target|
            edges << {"from" => spec_output_key(source), "to" => spec_output_key(target), "requirements" => dependency["requirements"].sort}
          end
        end
      end
      edges.uniq.sort_by {|edge| [edge["from"], edge["to"], edge["requirements"]] }
    end

    def serialize_variants(chosen)
      chosen.group_by {|spec| [spec["name"], spec["version"]] }.each_with_object({}) do |((name, version), specs), output|
        next if specs.length < 2
        specs.each do |spec|
          output[spec_output_key(spec)] = specs.reject {|other| other.equal?(spec) }.map {|other| other["platform"] }.sort
        end
      end
    end

    def validate_resolved_closure!(spec_set, context)
      specs = spec_set.to_a.reject {|spec| spec.name.end_with?("\0") }
      specs.each do |spec|
        spec.runtime_dependencies.each do |dependency|
          unless specs.any? {|candidate| candidate.name == dependency.name && dependency.matches_spec?(candidate) }
            raise Error.new("candidate_incomplete", "resolved dependency #{dependency.name} #{dependency.requirement} required by #{spec.full_name} is absent")
          end
        end
      end
      true
    end

    def classify_resolver_error(message)
      if message.match?(/Ruby\x00|RubyGems\x00|required ruby|ruby version|rubygems version/i)
        "ruby_incompatible"
      elsif message.match?(/platform|valid for all resolution platforms/i)
        ruby_spec_listed = message.lines.any? do |line|
          line.strip.start_with?("* ") && line.strip.match?(/-\d+(?:\.\d+)*(?:[A-Za-z][0-9A-Za-z.]*)?\z/)
        end
        ruby_spec_listed ? "requirements_conflict" : "platform_unavailable"
      else
        "requirements_conflict"
      end
    end

    def failure_response(error, stats)
      message = error.message.to_s.byteslice(0, 16_384).to_s.scrub
      message += "…" if error.message.to_s.bytesize > 16_384
      result = {
        "chosen" => [],
        "edges" => [],
        "variants" => {},
        "failure" => {
          "class" => error.error_class,
          "message" => message,
          "category" => error.category,
          "incompatibilities" => []
        },
        "stats" => stats
      }
      response = {"schema" => SCHEMA, "ok" => false, "result" => result}
      return response if JSON.generate(response).bytesize <= MAX_RESPONSE_BYTES

      {"schema" => SCHEMA, "ok" => false, "result" => {
        "chosen" => [], "edges" => [], "variants" => {},
        "failure" => {"class" => "Error", "message" => "response exceeds #{MAX_RESPONSE_BYTES} bytes; details omitted", "category" => "internal", "incompatibilities" => []},
        "stats" => {}
      }}
    end

    def check_response_size!(response)
      bytes = JSON.generate(response).bytesize
      raise Error.new("internal", "response exceeds #{MAX_RESPONSE_BYTES} bytes") if bytes > MAX_RESPONSE_BYTES
    end
  end
end
