require "./ruby_version"
require "./errors"

module Celerite
  module RubyRuntime
    # Validates Gemfile-declared ruby requirement against the running system.
    # Raises RubyVersionMismatch (status 18) on mismatch, matching Bundler 4.0.24.
    def self.validate!(requested_ruby : String?, env) : Nil
      validate_version!(Celerite::RubyVersion.parse_requirement(requested_ruby), env)
    end

    def self.validate_version!(requested : Celerite::RubyVersion?, env) : Nil
      return unless requested
      system = Celerite::RubyVersion.system_from_env(env)
      if diff = requested.diff(system)
        msg = Celerite::RubyVersion.mismatch_message(diff[0], diff[1], diff[2], requested, system)
        raise RubyVersionMismatch.new(msg)
      end
    end

    def self.diff(requested_ruby : String?, env) : Tuple(Symbol, String, String)?
      diff_version!(Celerite::RubyVersion.parse_requirement(requested_ruby), env)
    end

    def self.diff_version!(requested : Celerite::RubyVersion?, env) : Tuple(Symbol, String, String)?
      return nil unless requested
      system = Celerite::RubyVersion.system_from_env(env)
      requested.diff(system)
    end
  end
end
