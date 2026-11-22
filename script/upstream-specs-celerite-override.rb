# frozen_string_literal: true

# Helper for script/upstream-specs: when loaded with `rspec -r`, redirects
# upstream spec `bundle`/`bundler` helper invocations to the Celerite binary so
# in-example commands exercise Celerite instead of the upstream test-env bundle.
# Harness/precondition failures outside these helpers (spec_helper suite setup,
# fixture repo building, pristine system gems) remain upstream-harness concerns
# and must be classified separately.
module Spec
  module Helpers
    # Real-drive counter (task-148): script/upstream-specs points this at a file
    # it truncates before the run and reads afterwards. One line per in-example
    # celerite launch proves the suite drove celerite even when the PATH shim is
    # bypassed (upstream helpers exec the binary directly via sys_exec).
    def celerite_record_drive
      path = ENV["CELERITE_DRIVE_COUNTER"]
      return if path.nil? || path.empty?

      File.open(path, "a") { |file| file.puts(Process.pid) }
    rescue StandardError
      # Counting is evidence, never a reason to fail an example.
      nil
    end

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
      celerite_record_drive
      sys_exec("#{celerite} #{cmd}#{args}", { env: env, dir: dir, raise_on_error: raise_on_error }, &block)
    end

    def bundler(cmd, options = {})
      bundle(cmd, options)
    end
  end
end
