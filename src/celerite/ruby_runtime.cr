require "./ruby_version"
require "./errors"

module Celerite
  module RubyRuntime
    # Validates Gemfile-declared ruby requirement against the running system.
    # Raises RubyVersionMismatch (status 18) on mismatch, matching Bundler 4.0.24.
    def self.validate!(requested_ruby : String?, env) : Nil
      return unless requested_ruby
      requested = Celerite::RubyVersion.parse_requirement(requested_ruby)
      return unless requested
      system = Celerite::RubyVersion.system_from_env(env)
      if diff = requested.diff(system)
        msg = Celerite::RubyVersion.mismatch_message(diff[0], diff[1], diff[2], requested, system)
        raise RubyVersionMismatch.new(msg)
      end
    end

    def self.diff(requested_ruby : String?, env) : Tuple(Symbol, String, String)?
      return nil unless requested_ruby
      requested = Celerite::RubyVersion.parse_requirement(requested_ruby)
      return nil unless requested
      system = Celerite::RubyVersion.system_from_env(env)
      requested.diff(system)
    end
  end
end
