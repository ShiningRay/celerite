require "digest/sha256"
require "json"
require "time"
require "uri"
require "../resolver/source"

module Celerite
  module Bridge
    # Pure-data boundary for `celerite.solve_batch/3` (M8 L161 S3a).
    #
    # This module deliberately does not collect candidates or backfill a
    # Resolution. It only constructs, validates, serializes and converts the
    # bridge payload. Resolution integration belongs to S3b.
    module SolveBatch
      SCHEMA                  = "celerite.solve_batch/3"
      MAX_REQUEST_BYTES       = 32 * 1024 * 1024
      MAX_RESPONSE_BYTES      = 8 * 1024 * 1024
      MAX_CANDIDATES          = 100_000
      MAX_SOURCES             =   4_096
      MAX_NAMES               =  10_000
      MAX_TIMEOUT_MS          =  60_000
      BUNDLER_VERSION         = "4.0.24"
      DIAGNOSTICS_ENV         = "CELERITE_SOLVE_BATCH_DIAG"
      TOP_LEVEL_KEYS          = %w[schema evaluation requirements candidates_by_source locked_base promotion constraints candidate_closure limits]
      SOURCE_KEYS             = %w[source_id type name identity_sha256 uri_redacted remotes path revision ref branch tag glob submodules plugin_type lock_options materialization]
      REQUIREMENT_KEYS        = %w[name requirements source_id groups platforms autorequire force_ruby_platform gemspec_dev_dep direct]
      CANDIDATE_KEYS          = %w[name version platform dependencies required_ruby_version required_rubygems_version created_at checksum]
      DEPENDENCY_KEYS         = %w[name requirements]
      CHECKSUM_KEYS           = %w[algorithm value]
      LOCKED_SPEC_KEYS        = %w[name version platform source_id dependencies checksum]
      PROMOTION_KEYS          = %w[level strict pre unlock conservative prefer_local local_only]
      CONSTRAINT_KEYS         = %w[ruby_version ruby_patchlevel ruby_engine ruby_engine_version rubygems_version bundler_version platforms added_platforms removed_platforms force_ruby_platform]
      CLOSURE_KEYS            = %w[complete digest name_count candidate_count]
      CHOSEN_KEYS             = %w[name version platform source_id dependencies checksum required_ruby_version required_rubygems_version]
      EDGE_KEYS               = %w[from to requirements]
      RESULT_KEYS             = %w[chosen edges variants failure stats]
      FAILURE_KEYS            = %w[class message category incompatibilities]
      STATS_KEYS              = %w[candidate_bytes candidate_count source_count name_count materialize_ms solve_ms candidate_digest bridge_pid relaxations fallback_reason]
      SHA256_PATTERN          = /\A[0-9a-f]{64}\z/
      GEM_NAME_PATTERN        = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
      VERSION_PATTERN         = /\A[0-9]+(?:\.[0-9]+)*(?:[-.][0-9A-Za-z.-]+)?\z/
      PLATFORM_PATTERN        = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
      SENSITIVE_KEY_PATTERN   = /(?:password|passwd|token|secret|authorization|api[_-]?key|private[_-]?key)/i
      SENSITIVE_VALUE_PATTERN = /(?:password|passwd|token|secret|authorization|api[_-]?key|private[_-]?key)\s*[=:]/i
      DIAGNOSTIC_CATEGORIES   = %w[ineligible version_mismatch requirements_conflict platform_unavailable internal timeout transport validation protocol unknown]

      class Error < Exception
      end

      class ValidationError < Error
      end

      class IneligibleError < ValidationError
      end

      class TooLargeError < ValidationError
      end

      class ProtocolError < ValidationError
      end

      # Ruby `JSON.generate(canonicalize(value))` byte equivalent for the JSON
      # value domain used by the bridge. Crystal's normal JSON writer is not
      # used here: its escaping/number formatting is not the canonical contract.
      module Canonical
        extend self

        def json(value : JSON::Any) : String
          io = IO::Memory.new
          write(io, value)
          io.to_s
        end

        def json(value : Hash(String, JSON::Any)) : String
          json(JSON::Any.new(value))
        end

        def digest(value : JSON::Any) : String
          ::Digest::SHA256.hexdigest(json(value))
        end

        def digest(value : Hash(String, JSON::Any)) : String
          digest(JSON::Any.new(value))
        end

        private def write(io : IO, value : JSON::Any) : Nil
          case raw = value.raw
          when Nil
            io << "null"
          when Bool
            io << (raw ? "true" : "false")
          when Int64
            io << raw
          when Float64
            raise ValidationError.new("canonical JSON cannot contain a non-finite number") unless raw.finite?
            text = raw.to_s.gsub('E', 'e')
            if match = text.match(/\A(-?)(\d+)(?:\.(\d+))?e-(\d+)\z/)
              sign, integer, fraction, exponent = match[1], match[2], match[3]? || "", match[4].to_i
              digits = integer + fraction
              point = integer.size - exponent
              text = if point <= 0
                       "#{sign}0.#{"0" * -point}#{digits}"
                     elsif point >= digits.size
                       "#{sign}#{digits}#{"0" * (point - digits.size)}.0"
                     else
                       "#{sign}#{digits[0, point]}.#{digits[point..]}"
                     end
              if text.includes?('.') && !text.includes?('e')
                text = text.sub(/0+\z/, "")
                text += "0" if text.ends_with?('.')
              end
            else
              text = text.gsub(/\.0e/, "e")
              text = text.gsub(/e([+-])0+(\d+)/, "e\\1\\2")
              text += ".0" unless text.includes?('.') || text.includes?('e')
            end
            io << text
          when String
            write_string(io, raw)
          when Array(JSON::Any)
            io << '['
            raw.each_with_index do |item, index|
              io << ',' unless index == 0
              write(io, item)
            end
            io << ']'
          when Hash(String, JSON::Any)
            io << '{'
            raw.keys.sort.each_with_index do |key, index|
              io << ',' unless index == 0
              write_string(io, key)
              io << ':'
              write(io, raw[key])
            end
            io << '}'
          else
            raise ValidationError.new("unsupported canonical JSON value")
          end
        end

        private def write_string(io : IO, value : String) : Nil
          io << '"'
          value.each_char do |char|
            case char
            when '"'
              io << "\\\""
            when '\\'
              io << "\\\\"
            when '\b'
              io << "\\b"
            when '\f'
              io << "\\f"
            when '\n'
              io << "\\n"
            when '\r'
              io << "\\r"
            when '\t'
              io << "\\t"
            else
              codepoint = char.ord
              if codepoint < 0x20
                io << "\\u00" << codepoint.to_s(16).rjust(2, '0')
              else
                io << char
              end
            end
          end
          io << '"'
        end
      end

      module Validation
        extend self

        def object(value : JSON::Any, path : String, keys : Array(String)) : Hash(String, JSON::Any)
          raw = value.raw
          raise ValidationError.new("#{path} must be an object") unless raw.is_a?(Hash(String, JSON::Any))
          keys.each do |key|
            raise ValidationError.new("#{path}.#{key} is required") unless raw.has_key?(key)
          end
          raw.each_key do |key|
            raise ValidationError.new("#{path}.#{key} is unknown") unless keys.includes?(key)
          end
          raw
        end

        def dynamic_object(value : JSON::Any, path : String) : Hash(String, JSON::Any)
          raw = value.raw
          raise ValidationError.new("#{path} must be an object") unless raw.is_a?(Hash(String, JSON::Any))
          raw
        end

        def array(value : JSON::Any, path : String) : Array(JSON::Any)
          raw = value.raw
          raise ValidationError.new("#{path} must be an array") unless raw.is_a?(Array(JSON::Any))
          raw
        end

        def string(value : JSON::Any, path : String, allow_empty : Bool = true, max : Int32? = nil) : String
          raw = value.raw
          raise ValidationError.new("#{path} must be a string") unless raw.is_a?(String)
          raise ValidationError.new("#{path} must not be empty") if !allow_empty && raw.empty?
          raise ValidationError.new("#{path} is too long") if max && raw.bytesize > max
          raw
        end

        def nullable_string(value : JSON::Any, path : String, max : Int32? = nil) : String?
          return nil if value.raw.nil?
          string(value, path, true, max)
        end

        def boolean(value : JSON::Any, path : String) : Bool
          raw = value.raw
          raise ValidationError.new("#{path} must be a boolean") unless raw.is_a?(Bool)
          raw
        end

        def integer(value : JSON::Any, path : String) : Int64
          raw = value.raw
          raise ValidationError.new("#{path} must be an integer") unless raw.is_a?(Int64)
          raw
        end

        def nullable_integer(value : JSON::Any, path : String) : Int64?
          return nil if value.raw.nil?
          integer(value, path)
        end

        def number(value : JSON::Any, path : String) : Float64
          case raw = value.raw
          when Int64
            raw.to_f64
          when Float64
            raise ValidationError.new("#{path} must be finite") unless raw.finite?
            raw
          else
            raise ValidationError.new("#{path} must be a number")
          end
        end

        def string_array(value : JSON::Any, path : String, min : Int32 = 0, max : Int32? = nil) : Array(String)
          values = array(value, path).map_with_index do |item, index|
            string(item, "#{path}[#{index}]", true, max)
          end
          raise ValidationError.new("#{path} has too few items") if values.size < min
          raise ValidationError.new("#{path} has duplicate items") unless values.uniq.size == values.size
          values
        end

        def sha256(value : JSON::Any, path : String) : String
          result = string(value, path, false, 64)
          raise ValidationError.new("#{path} must be lowercase sha256") unless SHA256_PATTERN.matches?(result)
          result
        end

        def gem_name(value : JSON::Any, path : String) : String
          result = string(value, path, false, 100)
          raise ValidationError.new("#{path} is not a gem name") unless GEM_NAME_PATTERN.matches?(result)
          result
        end

        def version(value : JSON::Any, path : String) : String
          result = string(value, path, false, 100)
          raise ValidationError.new("#{path} is not a version") unless VERSION_PATTERN.matches?(result)
          result
        end

        def platform(value : JSON::Any, path : String) : String
          result = string(value, path, false, 100)
          raise ValidationError.new("#{path} is not a platform") unless PLATFORM_PATTERN.matches?(result)
          result
        end

        def enum(value : JSON::Any, path : String, allowed : Array(String)) : String
          result = string(value, path)
          raise ValidationError.new("#{path} has an unsupported value") unless allowed.includes?(result)
          result
        end

        def checksum(value : JSON::Any, path : String, normalize : Bool = false) : JSON::Any?
          return nil if value.raw.nil?
          raw = object(value, path, CHECKSUM_KEYS)
          algorithm = string(raw["algorithm"], "#{path}.algorithm")
          raise ValidationError.new("#{path}.algorithm must be sha256") unless algorithm == "sha256"
          checksum_value = string(raw["value"], "#{path}.value", false, 64)
          if normalize
            checksum_value = checksum_value.downcase
          end
          raise ValidationError.new("#{path}.value must be lowercase sha256") unless SHA256_PATTERN.matches?(checksum_value)
          JSON::Any.new({"algorithm" => JSON::Any.new("sha256"), "value" => JSON::Any.new(checksum_value)})
        end

        def credential_free!(value : JSON::Any, path : String = "payload") : Nil
          case raw = value.raw
          when Hash(String, JSON::Any)
            raw.each do |key, child|
              raise ValidationError.new("#{path} contains a sensitive field") if SENSITIVE_KEY_PATTERN.matches?(key)
              credential_free!(child, path)
            end
          when Array(JSON::Any)
            raw.each { |child| credential_free!(child, path) }
          when String
            if SENSITIVE_VALUE_PATTERN.matches?(raw)
              raise ValidationError.new("#{path} contains credential material")
            end
            if raw.includes?("://")
              begin
                uri = URI.parse(raw)
                host = uri.host
                if host && host.count('[') != host.count(']')
                  raise URI::Error.new("invalid host")
                end
                credential = uri.userinfo
              rescue URI::Error
                raise ValidationError.new("#{path} contains an invalid URI")
              end
              raise ValidationError.new("#{path} contains credential material") if credential
            end
          else
            # JSON scalar with no credential representation.
          end
        end
      end

      module Ordering
        extend self

        def self.compare_string_arrays(left : JSON::Any, right : JSON::Any) : Int32
          left_values = left.as_a.map(&.as_s)
          right_values = right.as_a.map(&.as_s)
          count = Math.min(left_values.size, right_values.size)
          count.times do |index|
            comparison = left_values[index] <=> right_values[index]
            return comparison unless comparison == 0
          end
          left_values.size <=> right_values.size
        end

        def self.dependency(left : JSON::Any, right : JSON::Any) : Int32
          comparison = left["name"].as_s <=> right["name"].as_s
          comparison == 0 ? compare_string_arrays(left["requirements"], right["requirements"]) : comparison
        end

        def self.edge(left : JSON::Any, right : JSON::Any) : Int32
          comparison = left["from"].as_s <=> right["from"].as_s
          return comparison unless comparison == 0
          comparison = left["to"].as_s <=> right["to"].as_s
          comparison == 0 ? compare_string_arrays(left["requirements"], right["requirements"]) : comparison
        end
      end

      module Digest
        extend self

        def dependencies(value : JSON::Any, path : String, normalize : Bool = true) : Array(JSON::Any)
          result = Validation.array(value, path).map_with_index do |dependency, index|
            raw = Validation.object(dependency, "#{path}[#{index}]", DEPENDENCY_KEYS)
            name = Validation.gem_name(raw["name"], "#{path}[#{index}].name")
            requirements = Validation.string_array(raw["requirements"], "#{path}[#{index}].requirements", 1, 500)
            requirements.sort! if normalize
            JSON::Any.new({"name" => JSON::Any.new(name), "requirements" => JSON::Any.new(requirements.map { |item| JSON::Any.new(item) })})
          end
          result.sort! { |left, right| Ordering.dependency(left, right) } if normalize
          result
        end

        def candidate(value : JSON::Any, path : String, normalize : Bool = true) : JSON::Any
          raw = Validation.object(value, path, CANDIDATE_KEYS)
          name = Validation.gem_name(raw["name"], "#{path}.name")
          version = Validation.version(raw["version"], "#{path}.version")
          platform = Validation.platform(raw["platform"], "#{path}.platform")
          dependencies = self.dependencies(raw["dependencies"], "#{path}.dependencies", normalize)
          ruby_requirement = Validation.nullable_string(raw["required_ruby_version"], "#{path}.required_ruby_version", 500)
          rubygems_requirement = Validation.nullable_string(raw["required_rubygems_version"], "#{path}.required_rubygems_version", 500)
          created_at = Validation.nullable_string(raw["created_at"], "#{path}.created_at", 100)
          checksum = Validation.checksum(raw["checksum"], "#{path}.checksum", normalize)
          JSON::Any.new({
            "name"                      => JSON::Any.new(name),
            "version"                   => JSON::Any.new(version),
            "platform"                  => JSON::Any.new(platform),
            "dependencies"              => JSON::Any.new(dependencies),
            "required_ruby_version"     => JSON::Any.new(ruby_requirement),
            "required_rubygems_version" => JSON::Any.new(rubygems_requirement),
            "created_at"                => JSON::Any.new(created_at),
            "checksum"                  => checksum || JSON::Any.new(nil),
          })
        end

        def candidates_by_source(value : JSON::Any, source_ids : Array(String)) : Hash(String, Array(JSON::Any))
          raw = Validation.dynamic_object(value, "candidates_by_source")
          result = {} of String => Array(JSON::Any)
          raw.each do |source_id, candidates|
            raise ValidationError.new("candidates_by_source contains an unknown source_id") unless source_ids.includes?(source_id)
            parsed = Validation.array(candidates, "candidates_by_source.#{source_id}").map_with_index do |candidate, index|
              self.candidate(candidate, "candidates_by_source.#{source_id}[#{index}]")
            end
            parsed.sort_by! { |candidate| [candidate["name"].as_s, candidate["version"].as_s, candidate["platform"].as_s] }
            result[source_id] = parsed
          end
          result
        end

        def candidate_digest(candidates : Hash(String, Array(JSON::Any))) : String
          normalized = {} of String => JSON::Any
          candidates.each do |source_id, values|
            normalized[source_id] = JSON::Any.new(values.map do |candidate|
              self.candidate(candidate, "candidate", true)
            end.sort_by { |candidate| [candidate["name"].as_s, candidate["version"].as_s, candidate["platform"].as_s] })
          end
          Canonical.digest(normalized)
        end

        def locked_spec(value : JSON::Any, path : String) : JSON::Any
          raw = Validation.object(value, path, LOCKED_SPEC_KEYS)
          checksum = Validation.checksum(raw["checksum"], "#{path}.checksum", true)
          JSON::Any.new({
            "name"         => JSON::Any.new(Validation.gem_name(raw["name"], "#{path}.name")),
            "version"      => JSON::Any.new(Validation.version(raw["version"], "#{path}.version")),
            "platform"     => JSON::Any.new(Validation.platform(raw["platform"], "#{path}.platform")),
            "source_id"    => JSON::Any.new(Validation.string(raw["source_id"], "#{path}.source_id", false, 200)),
            "dependencies" => JSON::Any.new(dependencies(raw["dependencies"], "#{path}.dependencies")),
            "checksum"     => checksum || JSON::Any.new(nil),
          })
        end

        def locked_digest(specs : Array(JSON::Any)) : String
          normalized = specs.map { |spec| locked_spec(spec, "locked_base.specs") }
          normalized.sort_by! { |spec| [spec["source_id"].as_s, spec["name"].as_s, spec["version"].as_s, spec["platform"].as_s] }
          Canonical.digest(JSON::Any.new(normalized))
        end
      end

      # Assigns stable bridge IDs first, then computes Ruby-compatible content
      # identities. Registry ordering excludes IDs, but the protocol identity
      # includes the assigned source_id and excludes only identity_sha256.
      module SourceRegistry
        extend self

        def identity(source : Hash(String, JSON::Any)) : String
          normalized = source.reject { |key, _| key == "identity_sha256" }
          if remotes = normalized["remotes"]?
            normalized["remotes"] = JSON::Any.new(Validation.string_array(remotes, "source.remotes").sort.map { |remote| JSON::Any.new(remote) })
          end
          Canonical.digest(normalized)
        end

        def assign(sources : Array(JSON::Any)) : Array(JSON::Any)
          raise ValidationError.new("at least one source is required") if sources.empty?
          raise ValidationError.new("too many sources") if sources.size > MAX_SOURCES

          entries = sources.map_with_index do |source, index|
            raw = Validation.object(source, "evaluation.sources[#{index}]", SOURCE_KEYS)
            source_id = Validation.string(raw["source_id"], "evaluation.sources[#{index}].source_id", false, 200)
            normalized = raw.dup
            normalized.delete("identity_sha256")
            normalized.delete("source_id")
            if remotes = normalized["remotes"]?
              normalized["remotes"] = JSON::Any.new(Validation.string_array(remotes, "source.remotes").sort.map { |remote| JSON::Any.new(remote) })
            end
            {source_id, normalized}
          end

          ids = entries.map(&.[0])
          raise ValidationError.new("duplicate source_id") unless ids.uniq.size == ids.size
          raise ValidationError.new("multiple sources require a default source") if entries.size > 1 && !ids.includes?("default")
          identities = entries.map { |entry| Canonical.digest(entry[1]) }
          raise ValidationError.new("duplicate source identity") unless identities.uniq.size == identities.size

          ordered = entries.sort_by { |entry| Canonical.json(entry[1]) }
          default_index = ordered.index { |entry| entry[0] == "default" } || 0
          primary = ordered.delete_at(default_index)
          assigned = [{primary, "default"}]
          ordered.each_with_index do |entry, index|
            assigned << {entry, "source-#{(index + 1).to_s.rjust(4, '0')}"}
          end

          assigned.map do |entry, source_id|
            raw = entry[1].dup
            raw["source_id"] = JSON::Any.new(source_id)
            raw["identity_sha256"] = JSON::Any.new(identity(raw))
            JSON::Any.new(raw)
          end
        end
      end

      module Eligibility
        extend self

        def eligible?(constraints : JSON::Any, fingerprint : JSON::Any, sources : Array(JSON::Any),
                      promotion : JSON::Any, frozen : Bool = false, autoheal : Bool = false) : Bool
          constraint_object = Validation.object(constraints, "constraints", CONSTRAINT_KEYS)
          fingerprint_object = Validation.object(fingerprint, "evaluation.fingerprint", %w[format digest state state_reason verify_files runtime config])
          promotion_object = Validation.object(promotion, "promotion", PROMOTION_KEYS)
          return false unless constraint_object["bundler_version"].raw == BUNDLER_VERSION
          return false unless fingerprint_object["state"].raw == "deterministic"
          return false if frozen || autoheal
          return false if promotion_object["prefer_local"].raw == true || promotion_object["local_only"].raw == true
          return false if sources.empty? || sources.size > MAX_SOURCES

          sources.all? do |source|
            raw = Validation.object(source, "evaluation.sources", SOURCE_KEYS)
            raw["type"].raw == "Rubygems" && raw["materialization"].raw == "pure_data"
          end
        rescue ValidationError
          false
        end
      end

      struct Candidate
        getter payload : JSON::Any

        def initialize(@payload : JSON::Any)
        end

        def self.from_json(value : JSON::Any, path : String = "candidate") : Candidate
          new(Digest.candidate(value, path, true))
        end

        def self.from_index_spec(spec : Resolver::IndexSpec) : Candidate
          created_at = if timestamp = spec.created_at
                         Time.unix(timestamp).to_rfc3339
                       end
          checksum = if value = spec.checksum
                       JSON::Any.new({"algorithm" => JSON::Any.new("sha256"), "value" => JSON::Any.new(value.downcase)})
                     end
          dependencies = spec.dependencies.map do |dependency|
            requirements = dependency.requirement.constraints.map(&.to_s).sort
            JSON::Any.new({"name" => JSON::Any.new(dependency.name), "requirements" => JSON::Any.new(requirements.map { |item| JSON::Any.new(item) })})
          end
          dependencies.sort! { |left, right| Ordering.dependency(left, right) }
          payload = JSON::Any.new({
            "name"                      => JSON::Any.new(spec.name),
            "version"                   => JSON::Any.new(spec.version.to_s),
            "platform"                  => JSON::Any.new(spec.platform.to_s),
            "dependencies"              => JSON::Any.new(dependencies),
            "required_ruby_version"     => JSON::Any.new(spec.required_ruby_version.to_s),
            "required_rubygems_version" => JSON::Any.new(spec.required_rubygems_version.to_s),
            "created_at"                => JSON::Any.new(created_at),
            "checksum"                  => checksum || JSON::Any.new(nil),
          })
          new(payload)
        end

        def name : String
          @payload["name"].as_s
        end

        def version : String
          @payload["version"].as_s
        end

        def platform : String
          @payload["platform"].as_s
        end

        def checksum : JSON::Any?
          @payload["checksum"].raw.nil? ? nil : @payload["checksum"]
        end

        def output_key : String
          "#{name}/#{version}/#{platform}"
        end
      end

      struct Request
        getter payload : JSON::Any
        getter sources : Array(JSON::Any)
        getter candidates_by_source : Hash(String, Array(Candidate))
        getter candidate_digest : String

        def initialize(@payload : JSON::Any, @sources : Array(JSON::Any),
                       @candidates_by_source : Hash(String, Array(Candidate)), @candidate_digest : String)
        end

        def self.parse(value : JSON::Any) : Request
          raw = Validation.object(value, "request", TOP_LEVEL_KEYS)
          schema = Validation.string(raw["schema"], "request.schema", false)
          raise ValidationError.new("unsupported solve_batch schema") unless schema == SCHEMA

          evaluation = validate_evaluation(raw["evaluation"])
          sources = SourceRegistry.assign(Validation.array(evaluation["sources"], "evaluation.sources"))
          evaluation["sources"] = JSON::Any.new(sources)
          source_ids = sources.map { |source| source["source_id"].as_s }
          candidates = Digest.candidates_by_source(raw["candidates_by_source"], source_ids)
          typed_candidates = {} of String => Array(Candidate)
          candidates.each { |source_id, values| typed_candidates[source_id] = values.map { |value| Candidate.new(value) } }

          requirements = Validation.array(raw["requirements"], "requirements").map_with_index do |requirement, index|
            validate_requirement(requirement, "requirements[#{index}]", source_ids)
          end
          locked_base = validate_locked_base(raw["locked_base"], source_ids)
          promotion = validate_promotion(raw["promotion"])
          constraints = validate_constraints(raw["constraints"])
          unless Eligibility.eligible?(JSON::Any.new(constraints), evaluation["fingerprint"], sources, JSON::Any.new(promotion))
            raise IneligibleError.new("solve_batch request is not eligible")
          end
          closure = validate_closure(raw["candidate_closure"])
          limits = Validation.object(raw["limits"], "limits", %w[timeout_ms])
          timeout_ms = Validation.integer(limits["timeout_ms"], "limits.timeout_ms")
          raise ValidationError.new("limits.timeout_ms is out of range") unless timeout_ms >= 1 && timeout_ms <= MAX_TIMEOUT_MS

          candidate_count = candidates.values.sum(&.size)
          name_count = candidates.values.flat_map(&.map(&.["name"].as_s)).uniq.size
          raise ValidationError.new("too many candidates") if candidate_count > MAX_CANDIDATES
          raise ValidationError.new("too many candidate names") if name_count > MAX_NAMES
          digest = Digest.candidate_digest(candidates)
          raise ValidationError.new("candidate_closure.digest does not match candidates") unless closure["digest"].as_s == digest
          raise ValidationError.new("candidate_closure.candidate_count does not match candidates") unless closure["candidate_count"].as_i64 == candidate_count
          raise ValidationError.new("candidate_closure.name_count does not match candidates") unless closure["name_count"].as_i64 == name_count
          unless closure["complete"].as_bool
            raise ValidationError.new("candidate closure must be complete")
          end

          candidate_map = {} of String => Candidate
          candidates.each do |source_id, values|
            values.each do |candidate|
              key = candidate_key(candidate, source_id)
              raise ValidationError.new("duplicate candidate") if candidate_map.has_key?(key)
              candidate_map[key] = Candidate.new(candidate)
            end
          end
          validate_locked_candidates!(locked_base, candidate_map)
          validate_candidate_dependencies!(candidate_map)

          normalized = {
            "schema"               => JSON::Any.new(SCHEMA),
            "evaluation"           => JSON::Any.new(evaluation),
            "requirements"         => JSON::Any.new(requirements),
            "candidates_by_source" => JSON::Any.new(candidates.transform_values { |values| JSON::Any.new(values) }),
            "locked_base"          => JSON::Any.new(locked_base),
            "promotion"            => JSON::Any.new(promotion),
            "constraints"          => JSON::Any.new(constraints),
            "candidate_closure"    => JSON::Any.new(closure),
            "limits"               => JSON::Any.new({"timeout_ms" => JSON::Any.new(timeout_ms)}),
          }
          payload = JSON::Any.new(normalized)
          Validation.credential_free!(payload)
          validate_redacted_uris!(sources)
          validate_bytes!(Canonical.json(payload).bytesize)
          new(payload, sources, typed_candidates, digest)
        end

        def self.parse(raw : String) : Request
          raise TooLargeError.new("solve_batch request exceeds #{MAX_REQUEST_BYTES} bytes") if raw.bytesize > MAX_REQUEST_BYTES
          begin
            parse(JSON.parse(raw))
          rescue JSON::ParseException
            raise ProtocolError.new("solve_batch request JSON is truncated or invalid")
          end
        end

        def self.build(evaluation : JSON::Any, requirements : Array(JSON::Any),
                       candidates_by_source : Hash(String, Array(JSON::Any)), locked_base : JSON::Any,
                       promotion : JSON::Any, constraints : JSON::Any,
                       candidate_closure : JSON::Any, limits : JSON::Any,
                       frozen : Bool = false, autoheal : Bool = false) : Request
          evaluation_object = Validation.dynamic_object(evaluation, "evaluation")
          fingerprint = evaluation_object["fingerprint"]
          sources = Validation.array(evaluation_object["sources"], "evaluation.sources")
          unless Eligibility.eligible?(constraints, fingerprint, sources, promotion, frozen, autoheal)
            raise IneligibleError.new("solve_batch request is not eligible")
          end
          parse(JSON::Any.new({
            "schema"               => JSON::Any.new(SCHEMA),
            "evaluation"           => evaluation,
            "requirements"         => JSON::Any.new(requirements),
            "candidates_by_source" => JSON::Any.new(candidates_by_source.transform_values { |values| JSON::Any.new(values) }),
            "locked_base"          => locked_base,
            "promotion"            => promotion,
            "constraints"          => constraints,
            "candidate_closure"    => candidate_closure,
            "limits"               => limits,
          }))
        end

        def self.validate_bytes!(bytes : Int32) : Nil
          raise TooLargeError.new("solve_batch request exceeds #{MAX_REQUEST_BYTES} bytes") if bytes > MAX_REQUEST_BYTES
        end

        def to_json : String
          Canonical.json(@payload)
        end

        def payload_hash : Hash(String, JSON::Any)
          @payload.as_h
        end

        def timeout : Time::Span
          Time::Span.new(nanoseconds: @payload["limits"]["timeout_ms"].as_i.to_i64 * 1_000_000_i64)
        end

        def source_ids : Array(String)
          @sources.map { |source| source["source_id"].as_s }
        end

        def candidate(source_id : String, name : String, version : String, platform : String) : Candidate?
          @candidates_by_source[source_id]?.try &.find do |candidate|
            candidate.name == name && candidate.version == version && candidate.platform == platform
          end
        end

        def requirements : Array(JSON::Any)
          @payload["requirements"].as_a
        end

        private def self.validate_evaluation(value : JSON::Any) : Hash(String, JSON::Any)
          raw = Validation.object(value, "evaluation", %w[gemfile fingerprint sources plugins groups])
          gemfile = Validation.object(raw["gemfile"], "evaluation.gemfile", %w[path_sha256 sha256])
          Validation.sha256(gemfile["path_sha256"], "evaluation.gemfile.path_sha256")
          Validation.sha256(gemfile["sha256"], "evaluation.gemfile.sha256")

          fingerprint = Validation.object(raw["fingerprint"], "evaluation.fingerprint", %w[format digest state state_reason verify_files runtime config])
          Validation.enum(fingerprint["format"], "evaluation.fingerprint.format", ["celerite-eval-v1"])
          Validation.sha256(fingerprint["digest"], "evaluation.fingerprint.digest")
          Validation.enum(fingerprint["state"], "evaluation.fingerprint.state", %w[deterministic unknown broken])
          Validation.nullable_string(fingerprint["state_reason"], "evaluation.fingerprint.state_reason")
          Validation.array(fingerprint["verify_files"], "evaluation.fingerprint.verify_files").each_with_index do |file, index|
            entry = Validation.object(file, "evaluation.fingerprint.verify_files[#{index}]", %w[role path sha256])
            Validation.string(entry["role"], "evaluation.fingerprint.verify_files[#{index}].role", false, 100)
            Validation.string(entry["path"], "evaluation.fingerprint.verify_files[#{index}].path", false, 4096)
            Validation.sha256(entry["sha256"], "evaluation.fingerprint.verify_files[#{index}].sha256")
          end
          Validation.dynamic_object(fingerprint["runtime"], "evaluation.fingerprint.runtime")
          Validation.dynamic_object(fingerprint["config"], "evaluation.fingerprint.config")

          Validation.array(raw["sources"], "evaluation.sources")
          plugins = Validation.array(raw["plugins"], "evaluation.plugins").map_with_index do |plugin, index|
            entry = Validation.object(plugin, "evaluation.plugins[#{index}]", %w[name version source_id declaration_sha256])
            Validation.string(entry["name"], "evaluation.plugins[#{index}].name", false, 200)
            Validation.nullable_string(entry["version"], "evaluation.plugins[#{index}].version", 100)
            Validation.nullable_string(entry["source_id"], "evaluation.plugins[#{index}].source_id", 200)
            Validation.sha256(entry["declaration_sha256"], "evaluation.plugins[#{index}].declaration_sha256")
            entry
          end
          groups = Validation.object(raw["groups"], "evaluation.groups", %w[with without optional all])
          groups.each do |key, value|
            Validation.string_array(value, "evaluation.groups.#{key}", 0, 200)
          end
          raw.merge({"sources" => raw["sources"], "plugins" => JSON::Any.new(plugins.map { |plugin| JSON::Any.new(plugin) })})
        end

        private def self.validate_source(value : JSON::Any, path : String) : Hash(String, JSON::Any)
          raw = Validation.object(value, path, SOURCE_KEYS)
          Validation.string(raw["source_id"], "#{path}.source_id", false, 200)
          Validation.enum(raw["type"], "#{path}.type", %w[Rubygems Path Git Plugin Metadata Unknown])
          Validation.nullable_string(raw["name"], "#{path}.name", 200)
          Validation.sha256(raw["identity_sha256"], "#{path}.identity_sha256")
          uri = Validation.nullable_string(raw["uri_redacted"], "#{path}.uri_redacted", 4096)
          validate_redacted_uri(uri, "#{path}.uri_redacted")
          Validation.string_array(raw["remotes"], "#{path}.remotes", 0, 4096)
          {"path" => raw["path"], "revision" => raw["revision"], "ref" => raw["ref"], "branch" => raw["branch"], "tag" => raw["tag"], "glob" => raw["glob"]}.each do |key, item|
            Validation.nullable_string(item, "#{path}.#{key}", key == "glob" ? 4096 : 200)
          end
          if raw["submodules"].raw.nil?
            # nullable boolean
          else
            Validation.boolean(raw["submodules"], "#{path}.submodules")
          end
          Validation.nullable_string(raw["plugin_type"], "#{path}.plugin_type", 200)
          Validation.dynamic_object(raw["lock_options"], "#{path}.lock_options")
          Validation.enum(raw["materialization"], "#{path}.materialization", %w[pure_data path git plugin unknown])
          raw
        end

        private def self.validate_requirement(value : JSON::Any, path : String, source_ids : Array(String)) : JSON::Any
          raw = Validation.object(value, path, REQUIREMENT_KEYS)
          name = Validation.gem_name(raw["name"], "#{path}.name")
          requirements = Validation.string_array(raw["requirements"], "#{path}.requirements", 1, 500)
          source_id = Validation.nullable_string(raw["source_id"], "#{path}.source_id", 200)
          raise ValidationError.new("#{path}.source_id is unknown") if source_id && !source_ids.includes?(source_id)
          groups = Validation.string_array(raw["groups"], "#{path}.groups", 0, 200)
          platforms = Validation.string_array(raw["platforms"], "#{path}.platforms", 0, 100)
          autorequire = Validation.string_array(raw["autorequire"], "#{path}.autorequire", 0, 200)
          force_ruby_platform = Validation.boolean(raw["force_ruby_platform"], "#{path}.force_ruby_platform")
          gemspec_dev_dep = Validation.boolean(raw["gemspec_dev_dep"], "#{path}.gemspec_dev_dep")
          direct = Validation.boolean(raw["direct"], "#{path}.direct")
          JSON::Any.new({
            "name" => JSON::Any.new(name), "requirements" => JSON::Any.new(requirements.map { |item| JSON::Any.new(item) }),
            "source_id" => JSON::Any.new(source_id), "groups" => JSON::Any.new(groups.map { |item| JSON::Any.new(item) }),
            "platforms" => JSON::Any.new(platforms.map { |item| JSON::Any.new(item) }),
            "autorequire" => JSON::Any.new(autorequire.map { |item| JSON::Any.new(item) }),
            "force_ruby_platform" => JSON::Any.new(force_ruby_platform), "gemspec_dev_dep" => JSON::Any.new(gemspec_dev_dep),
            "direct" => JSON::Any.new(direct),
          })
        end

        private def self.validate_promotion(value : JSON::Any) : Hash(String, JSON::Any)
          raw = Validation.object(value, "promotion", PROMOTION_KEYS)
          Validation.enum(raw["level"], "promotion.level", %w[patch minor major])
          %w[strict pre unlock conservative prefer_local local_only].each do |key|
            Validation.boolean(raw[key], "promotion.#{key}")
          end
          raw
        end

        private def self.validate_constraints(value : JSON::Any) : Hash(String, JSON::Any)
          raw = Validation.object(value, "constraints", CONSTRAINT_KEYS)
          Validation.version(raw["ruby_version"], "constraints.ruby_version")
          patchlevel = Validation.nullable_integer(raw["ruby_patchlevel"], "constraints.ruby_patchlevel")
          raise ValidationError.new("constraints.ruby_patchlevel is out of range") if patchlevel && patchlevel < -1
          Validation.string(raw["ruby_engine"], "constraints.ruby_engine", false, 100)
          Validation.version(raw["ruby_engine_version"], "constraints.ruby_engine_version")
          Validation.version(raw["rubygems_version"], "constraints.rubygems_version")
          Validation.enum(raw["bundler_version"], "constraints.bundler_version", [BUNDLER_VERSION])
          platforms = Validation.array(raw["platforms"], "constraints.platforms").map_with_index { |item, index| Validation.platform(item, "constraints.platforms[#{index}]") }
          raise ValidationError.new("constraints.platforms must not be empty") if platforms.empty?
          raise ValidationError.new("constraints.platforms has too many items") if platforms.size > 100
          raise ValidationError.new("constraints.platforms has duplicate items") unless platforms.uniq.size == platforms.size
          %w[added_platforms removed_platforms].each do |key|
            values = Validation.array(raw[key], "constraints.#{key}").map_with_index { |item, index| Validation.platform(item, "constraints.#{key}[#{index}]") }
            raise ValidationError.new("constraints.#{key} has too many items") if values.size > 100
            raise ValidationError.new("constraints.#{key} has duplicate items") unless values.uniq.size == values.size
          end
          Validation.boolean(raw["force_ruby_platform"], "constraints.force_ruby_platform")
          raw
        end

        private def self.validate_closure(value : JSON::Any) : Hash(String, JSON::Any)
          raw = Validation.object(value, "candidate_closure", CLOSURE_KEYS)
          Validation.boolean(raw["complete"], "candidate_closure.complete")
          Validation.sha256(raw["digest"], "candidate_closure.digest")
          name_count = Validation.integer(raw["name_count"], "candidate_closure.name_count")
          candidate_count = Validation.integer(raw["candidate_count"], "candidate_closure.candidate_count")
          raise ValidationError.new("candidate_closure.name_count is out of range") unless name_count >= 0 && name_count <= MAX_NAMES
          raise ValidationError.new("candidate_closure.candidate_count is out of range") unless candidate_count >= 0 && candidate_count <= MAX_CANDIDATES
          raw
        end

        private def self.validate_locked_base(value : JSON::Any, source_ids : Array(String)) : Hash(String, JSON::Any)
          raw = Validation.object(value, "locked_base", %w[sha256 specs])
          Validation.sha256(raw["sha256"], "locked_base.sha256")
          specs = Validation.array(raw["specs"], "locked_base.specs").map_with_index do |spec, index|
            parsed = Digest.locked_spec(spec, "locked_base.specs[#{index}]")
            raise ValidationError.new("locked_base.specs contains an unknown source_id") unless source_ids.includes?(parsed["source_id"].as_s)
            parsed
          end
          digest = Digest.locked_digest(specs)
          raise ValidationError.new("locked_base.sha256 does not match specs") unless raw["sha256"].as_s == digest
          raw.merge({"specs" => JSON::Any.new(specs)})
        end

        private def self.validate_locked_candidates!(locked_base : Hash(String, JSON::Any), candidate_map : Hash(String, Candidate)) : Nil
          locked_base["specs"].as_a.each do |spec|
            key = candidate_key(spec, spec["source_id"].as_s)
            candidate = candidate_map[key]?
            raise ValidationError.new("locked_base selects an unknown candidate") unless candidate
            unless candidate.payload["dependencies"].as_a.map { |dep| Canonical.json(dep) } == spec["dependencies"].as_a.map { |dep| Canonical.json(dep) }
              raise ValidationError.new("locked_base dependencies do not match candidate")
            end
            unless Canonical.json(candidate.checksum || JSON::Any.new(nil)) == Canonical.json(spec["checksum"])
              raise ValidationError.new("locked_base checksum does not match candidate")
            end
          end
        end

        private def self.validate_candidate_dependencies!(candidate_map : Hash(String, Candidate)) : Nil
          candidate_map.each_value do |candidate|
            candidate.payload["dependencies"].as_a.each do |dependency|
              unless candidate_map.values.any? { |target| target.name == dependency["name"].as_s }
                raise ValidationError.new("candidate dependency is outside the complete candidate set")
              end
            end
          end
        end

        private def self.candidate_key(value : JSON::Any, source_id : String) : String
          "#{source_id}\0#{value["name"].as_s}\0#{value["version"].as_s}\0#{value["platform"].as_s}"
        end

        private def self.validate_redacted_uris!(sources : Array(JSON::Any)) : Nil
          sources.each do |source|
            raw = validate_source(source, "evaluation.sources")
            uri = raw["uri_redacted"].as_s?
            validate_redacted_uri(uri, "evaluation.sources.uri_redacted") if uri
            if raw["type"].as_s != "Rubygems" || raw["materialization"].as_s != "pure_data"
              raise IneligibleError.new("solve_batch only accepts Rubygems pure_data sources")
            end
          end
        end

        private def self.validate_redacted_uri(value : String?, path : String) : Nil
          return if value.nil?
          uri = URI.parse(value)
          unless uri.scheme && %w[http https file].includes?(uri.scheme)
            raise ValidationError.new("#{path} has an unsupported scheme")
          end
          if uri.scheme != "file" && !uri.host
            raise ValidationError.new("#{path} must include a host")
          end
          raise ValidationError.new("#{path} must not include userinfo") if uri.userinfo
          raise ValidationError.new("#{path} must not include a query or fragment") if uri.query || uri.fragment
        rescue URI::Error
          raise ValidationError.new("#{path} is not a valid redacted URI")
        end
      end

      struct Edge
        getter payload : JSON::Any

        def initialize(@payload : JSON::Any)
        end

        def from : String
          @payload["from"].as_s
        end

        def to : String
          @payload["to"].as_s
        end

        def requirements : Array(String)
          @payload["requirements"].as_a.map(&.as_s)
        end
      end

      struct Failure
        getter payload : JSON::Any

        def initialize(@payload : JSON::Any)
        end

        def category : String
          @payload["category"].as_s
        end

        def message : String
          @payload["message"].as_s
        end
      end

      struct Response
        getter payload : JSON::Any
        getter chosen : Array(Candidate)
        getter edges : Array(Edge)
        getter variants : Hash(String, Array(String))
        getter failure : Failure?
        getter stats : JSON::Any

        def initialize(@payload : JSON::Any, @chosen : Array(Candidate), @edges : Array(Edge),
                       @variants : Hash(String, Array(String)), @failure : Failure?, @stats : JSON::Any)
        end

        def self.parse(value : JSON::Any, request : Request) : Response
          raw = Validation.object(value, "response", %w[schema ok result])
          raise ProtocolError.new("unsupported solve_batch response schema") unless raw["schema"].as_s == SCHEMA
          ok = Validation.boolean(raw["ok"], "response.ok")
          result = Validation.object(raw["result"], "response.result", RESULT_KEYS)
          chosen_values = Validation.array(result["chosen"], "response.result.chosen")
          edge_values = Validation.array(result["edges"], "response.result.edges")
          variants_value = Validation.dynamic_object(result["variants"], "response.result.variants")
          stats_value = result["stats"]

          if ok
            if chosen_values.empty? && !request.requirements.empty?
              raise ProtocolError.new("successful solve_batch response has no chosen candidate")
            end
            if !result["failure"].raw.nil?
              raise ProtocolError.new("successful solve_batch response must not contain failure")
            end
            stats = validate_success_stats(stats_value, request)
          else
            unless chosen_values.empty? && edge_values.empty? && variants_value.empty?
              raise ProtocolError.new("failed solve_batch response must be empty")
            end
            failure = validate_failure(result["failure"])
            stats_raw = Validation.dynamic_object(stats_value, "response.result.stats")
            stats = stats_raw.empty? ? stats_value : validate_success_stats(stats_value, request)
            return new(JSON::Any.new(raw), [] of Candidate, [] of Edge, {} of String => Array(String), failure, stats)
          end

          chosen = chosen_values.map_with_index do |chosen_value, index|
            validate_chosen(chosen_value, "response.result.chosen[#{index}]", request)
          end
          raise ProtocolError.new("solve_batch response contains a duplicate chosen candidate") unless chosen.map(&.output_key).uniq.size == chosen.size
          chosen.sort_by! { |candidate| [candidate.name, candidate.version, candidate.platform, candidate.payload["source_id"].as_s] }
          edges = edge_values.map_with_index do |edge, index|
            parse_edge(edge, "response.result.edges[#{index}]")
          end
          edges.sort! { |left, right| Ordering.edge(left.payload, right.payload) }
          expected_edges = expected_edges(chosen, request.requirements)
          actual_edges = edges
          unless actual_edges.map(&.payload) == expected_edges
            raise ProtocolError.new("solve_batch response edges do not match the chosen closure")
          end

          variants = {} of String => Array(String)
          variants_value.each do |key, value|
            raise ProtocolError.new("solve_batch response variants has an unknown key") unless chosen.any? { |candidate| candidate.output_key == key }
            variants[key] = Validation.string_array(value, "response.result.variants.#{key}").sort
          end
          expected_variants = expected_variants(chosen)
          raise ProtocolError.new("solve_batch response variants do not match chosen candidates") unless variants == expected_variants

          new(JSON::Any.new(raw), chosen, edges, variants, nil, stats)
        end

        def self.parse(raw : String, request : Request) : Response
          raise TooLargeError.new("solve_batch response exceeds #{MAX_RESPONSE_BYTES} bytes") if raw.bytesize > MAX_RESPONSE_BYTES
          begin
            parse(JSON.parse(raw), request)
          rescue JSON::ParseException
            raise ProtocolError.new("solve_batch response JSON is truncated or invalid")
          end
        end

        def ok? : Bool
          @payload["ok"].as_bool
        end

        private def self.validate_chosen(value : JSON::Any, path : String, request : Request) : Candidate
          raw = Validation.object(value, path, CHOSEN_KEYS)
          name = Validation.gem_name(raw["name"], "#{path}.name")
          version = Validation.version(raw["version"], "#{path}.version")
          platform = Validation.platform(raw["platform"], "#{path}.platform")
          source_id = Validation.string(raw["source_id"], "#{path}.source_id", false, 200)
          candidate = request.candidate(source_id, name, version, platform)
          raise ProtocolError.new("solve_batch response selected an unknown candidate or source") unless candidate
          dependencies = Digest.dependencies(raw["dependencies"], "#{path}.dependencies")
          checksum = Validation.checksum(raw["checksum"], "#{path}.checksum")
          ruby_requirement = Validation.nullable_string(raw["required_ruby_version"], "#{path}.required_ruby_version", 500)
          rubygems_requirement = Validation.nullable_string(raw["required_rubygems_version"], "#{path}.required_rubygems_version", 500)
          unless Canonical.json(JSON::Any.new(dependencies)) == Canonical.json(candidate.payload["dependencies"])
            raise ProtocolError.new("solve_batch response dependencies do not match candidate")
          end
          unless Canonical.json(checksum || JSON::Any.new(nil)) == Canonical.json(candidate.payload["checksum"])
            raise ProtocolError.new("solve_batch response checksum does not match candidate")
          end
          unless ruby_requirement == candidate.payload["required_ruby_version"].as_s? && rubygems_requirement == candidate.payload["required_rubygems_version"].as_s?
            raise ProtocolError.new("solve_batch response requirements do not match candidate")
          end
          payload = JSON::Any.new({
            "name" => JSON::Any.new(name), "version" => JSON::Any.new(version), "platform" => JSON::Any.new(platform),
            "source_id" => JSON::Any.new(source_id), "dependencies" => JSON::Any.new(dependencies),
            "checksum" => checksum || JSON::Any.new(nil), "required_ruby_version" => JSON::Any.new(ruby_requirement),
            "required_rubygems_version" => JSON::Any.new(rubygems_requirement),
          })
          Candidate.new(payload)
        end

        private def self.parse_edge(value : JSON::Any, path : String) : Edge
          raw = Validation.object(value, path, EDGE_KEYS)
          from = Validation.string(raw["from"], "#{path}.from", false)
          to = Validation.string(raw["to"], "#{path}.to", false)
          requirements = Validation.string_array(raw["requirements"], "#{path}.requirements", 1, 500).sort
          Edge.new(JSON::Any.new({"from" => JSON::Any.new(from), "to" => JSON::Any.new(to), "requirements" => JSON::Any.new(requirements.map { |item| JSON::Any.new(item) })}))
        end

        private def self.expected_edges(chosen : Array(Candidate), requirements : Array(JSON::Any)) : Array(JSON::Any)
          edges = [] of JSON::Any
          requirements.each do |requirement|
            chosen.select { |candidate| candidate.name == requirement["name"].as_s }.each do |candidate|
              edges << JSON::Any.new({"from" => JSON::Any.new("root"), "to" => JSON::Any.new(candidate.output_key), "requirements" => JSON::Any.new(requirement["requirements"].as_a.map(&.as_s).sort.map { |item| JSON::Any.new(item) })})
            end
          end
          chosen.each do |source|
            source.payload["dependencies"].as_a.each do |dependency|
              chosen.select { |target| target.name == dependency["name"].as_s }.each do |target|
                edges << JSON::Any.new({"from" => JSON::Any.new(source.output_key), "to" => JSON::Any.new(target.output_key), "requirements" => JSON::Any.new(dependency["requirements"].as_a.map(&.as_s).sort.map { |item| JSON::Any.new(item) })})
              end
            end
          end
          edges.uniq.sort { |left, right| Ordering.edge(left, right) }
        end

        private def self.expected_variants(chosen : Array(Candidate)) : Hash(String, Array(String))
          variants = {} of String => Array(String)
          chosen.group_by { |candidate| {candidate.name, candidate.version} }.each do |key, group|
            next if group.size < 2
            group.each do |candidate|
              variants[candidate.output_key] = group.reject { |item| item.output_key == candidate.output_key }.map(&.platform).sort
            end
          end
          variants
        end

        private def self.validate_failure(value : JSON::Any) : Failure
          raw = Validation.object(value, "response.result.failure", FAILURE_KEYS)
          Validation.string(raw["class"], "response.result.failure.class", false)
          Validation.string(raw["message"], "response.result.failure.message")
          Validation.string(raw["category"], "response.result.failure.category", false)
          incompatibilities = Validation.array(raw["incompatibilities"], "response.result.failure.incompatibilities")
          Failure.new(JSON::Any.new(raw.merge({"incompatibilities" => JSON::Any.new(incompatibilities)})))
        end

        private def self.validate_success_stats(value : JSON::Any, request : Request) : JSON::Any
          raw = Validation.object(value, "response.result.stats", STATS_KEYS)
          candidate_bytes = Validation.integer(raw["candidate_bytes"], "response.result.stats.candidate_bytes")
          candidate_count = Validation.integer(raw["candidate_count"], "response.result.stats.candidate_count")
          source_count = Validation.integer(raw["source_count"], "response.result.stats.source_count")
          name_count = Validation.integer(raw["name_count"], "response.result.stats.name_count")
          bridge_pid = Validation.integer(raw["bridge_pid"], "response.result.stats.bridge_pid")
          materialize_ms = Validation.number(raw["materialize_ms"], "response.result.stats.materialize_ms")
          solve_ms = Validation.number(raw["solve_ms"], "response.result.stats.solve_ms")
          {candidate_bytes, candidate_count, source_count, name_count, bridge_pid}.each do |number|
            raise ProtocolError.new("solve_batch response stats must be nonnegative") if number < 0
          end
          raise ProtocolError.new("solve_batch response timings must be nonnegative") if materialize_ms < 0 || solve_ms < 0
          raise ProtocolError.new("solve_batch response candidate_count does not match request") unless candidate_count == request.candidates_by_source.values.sum(&.size)
          raise ProtocolError.new("solve_batch response source_count does not match request") unless source_count == request.sources.size
          expected_names = request.candidates_by_source.values.flat_map(&.map(&.name)).uniq.size
          raise ProtocolError.new("solve_batch response name_count does not match request") unless name_count == expected_names
          digest = Validation.sha256(raw["candidate_digest"], "response.result.stats.candidate_digest")
          raise ProtocolError.new("solve_batch response candidate_digest does not match request") unless digest == request.candidate_digest
          relaxations = Validation.array(raw["relaxations"], "response.result.stats.relaxations")
          Validation.nullable_string(raw["fallback_reason"], "response.result.stats.fallback_reason")
          JSON::Any.new(raw.merge({"relaxations" => JSON::Any.new(relaxations)}))
        end
      end

      module Diagnostics
        extend self

        def enabled? : Bool
          ENV[DIAGNOSTICS_ENV]? == "1"
        end

        def emit(event : String, category : String, io : IO = STDERR) : Nil
          return unless enabled?
          safe_event = event.gsub(/[^A-Za-z0-9_.-]/, "_")
          safe_category = DIAGNOSTIC_CATEGORIES.includes?(category) ? category : "unknown"
          io.puts "[celerite solve_batch] event=#{safe_event} category=#{safe_category}"
        end
      end
    end
  end
end
