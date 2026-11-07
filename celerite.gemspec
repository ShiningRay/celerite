# frozen_string_literal: true

# Celerite gem packaging (roadmap M6). The engine is a native Crystal binary,
# so gems are published per platform (nokogiri-style): script/gem assembles a
# staging tree with the platform binary and builds with
# CELERITE_GEM_PLATFORM=<platform> gem build celerite.gemspec.
#
# `gem build celerite.gemspec` without CELERITE_GEM_PLATFORM produces a
# metadata-only ruby-platform gem (no binary) — useful for linting, not for
# distribution.

version = File.read(File.join(__dir__, "shard.yml"))[/^version:\s*(\S+)/, 1]
raise "cannot read version from shard.yml" unless version

Gem::Specification.new do |spec|
  spec.name = "celerite"
  spec.version = version
  spec.authors = ["ShiningRay"]
  spec.summary = "A high-performance, Bundler-compatible Ruby dependency manager"
  spec.description = "Celerite is a native (Crystal) engine for Bundler workflows: " \
                     "compact-index resolution, lockfiles, checksummed installs, and " \
                     "the public Bundler Ruby API via a compatibility bridge. " \
                     "Differential-tested against Bundler 4.0.24 and 2.7.2."
  spec.homepage = "https://github.com/ShiningRay/celerite"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.executables = ["celerite"]
  spec.bindir = "exe"
  spec.require_paths = ["lib"]

  spec.files = ["exe/celerite", "assets/bridge/server.rb", "THIRD_PARTY_LICENSES.md",
                "README.md", "LICENSE"]
  spec.files += Dir.glob("assets/licenses/*").sort

  if (platform = ENV["CELERITE_GEM_PLATFORM"]) && !platform.empty?
    spec.platform = Gem::Platform.new(platform)
    bin_name = platform.include?("mingw") || platform.include?("mswin") ? "celerite.exe" : "celerite"
    platform_dir = "lib/celerite/#{platform}"
    spec.files += ["#{platform_dir}/#{bin_name}"]
    # script/bundle-dylibs makes the macOS binary self-contained; those dylibs
    # are part of the platform gem too.
    spec.files += Dir.glob("#{platform_dir}/*.dylib").sort if platform.include?("darwin")
  end
end
