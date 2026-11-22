module Celerite
  # The compatibility profile: which Bundler release Celerite mirrors, and the
  # single source of truth for the "default reference bundler version".
  #
  # Before task-143 this env lookup, with the default release inlined as a
  # bare `"4.0.24"` after `||`, was copy-pasted at two dozen call sites (and
  # mirrored once as `Manpages::PROFILE_DEFAULT`), so the default could drift
  # between them. Every site now goes through `Profile.bundler_version`.
  module Profile
    # Environment variable that selects the reference Bundler release.
    ENV_KEY = "CELERITE_PROFILE_BUNDLER_VERSION"

    # The reference Bundler release used when the environment selects none.
    # `Celerite::ReleaseMetadata::RELEASES` must carry a matching entry.
    DEFAULT_BUNDLER_VERSION = "4.0.24"

    # Exact pre-refactor semantics, preserved deliberately:
    #
    # * unset  -> the default. (On Windows an empty environment value is
    #   deleted by the OS, so it is indistinguishable from "unset" here.)
    # * set    -> the value is used verbatim. No validation and no trimming:
    #   `"   "` stays `"   "` and `"9.9.9"` stays `"9.9.9"`, exactly as the
    #   inlined `||` expression behaved.
    def self.bundler_version : String
      ENV[ENV_KEY]? || DEFAULT_BUNDLER_VERSION
    end
  end
end
