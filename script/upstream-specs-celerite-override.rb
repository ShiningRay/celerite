# frozen_string_literal: true

# Helper for script/upstream-specs: when loaded with `rspec -r`, redirects
# upstream spec `bundle`/`bundler` helper invocations to the Celerite binary so
# in-example commands exercise Celerite instead of the upstream test-env bundle.
# Harness/precondition failures outside these helpers (spec_helper suite setup,
# fixture repo building, pristine system gems) remain upstream-harness concerns
# and must be classified separately.
module Spec
  module Helpers
    def celerite_bundle_bin
      ENV["CELERITE_BIN"] || ENV["CELERITE_BUNDLE_BIN"]
    end

    def bundle(cmd, options = {}, &block)
      celerite = celerite_bundle_bin
      return super unless celerite && !celerite.empty?

      env = (options.delete(:env) || {}).dup
      raise_on_error = options.delete(:raise_on_error)

      # Best-effort mapping of common upstream bundle helper options.
      dir = options.delete(:dir) || bundled_app
      options.delete(:bundle_bin)
      options.delete(:requires)
      options.delete(:load_path)
      options.delete(:artifice)

      env["CELERITE_BRIDGE_SERVER"] ||= ENV["CELERITE_BRIDGE_SERVER"].to_s if ENV["CELERITE_BRIDGE_SERVER"]
      env["BUNDLE_GEMFILE"] = "" unless env.key?("BUNDLE_GEMFILE")

      args = options.map do |k, v|
        case v
        when true
          " --#{k}"
        when false
          " --no-#{k}"
        else
          " --#{k} #{v}"
        end
      end.join

      # Invoke celerite directly (native exe on Windows) rather than via ruby.
      sys_exec("#{celerite} #{cmd}#{args}", { env: env, dir: dir, raise_on_error: raise_on_error }, &block)
    end

    def bundler(cmd, options = {})
      bundle(cmd, options)
    end
  end
end
