# Build metadata of the reference Bundler releases this CLI emulates.
#
# `bundle version` prints `Bundler.verbose_version` plus
# `Bundler::BuildMetadata` info (" (2026-11-05 commit 3b396e4)"); the metadata
# is a build-time constant of each release (`bundler/build_metadata.rb`), so it
# is baked in here rather than read from the machine at runtime.
module Celerite
  module ReleaseMetadata
    # version => {built_at, git_commit_sha}
    RELEASES = {
      "2.7.2"  => {"2025-09-09", "b463ced1459"},
      "4.0.24" => {"2026-11-05", "3b396e4"},
    }

    # Build metadata for a reference release, or nil when the release ships no
    # `build_metadata.rb` (e.g. 4.0.16), in which case `bundle version` prints
    # the bare version number.
    def self.for(version : String) : Tuple(String, String)?
      RELEASES[version]?
    end
  end
end
