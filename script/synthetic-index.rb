#!/usr/bin/env ruby
# frozen_string_literal: true

# Test fixture generator only: this script is not part of any product path.
# It builds a self-contained, offline gem index so the scale harness can
# compare Celerite with the pinned reference Bundler without network access.
#
# Each generated gem needs all three artifacts a file:// source is read through:
#   1. gems/<name>-<version>.gem
#   2. quick/Marshal.4.8/<name>-<version>.gemspec.rz
#   3. compact info/<name> + versions (Gem::Indexer emits both index formats)
#
# Usage: script/synthetic-index.rb --count N --out DIR

require "fileutils"
require "optparse"
require "rubygems"
require "rubygems/indexer"
require "rubygems/package"
require "tmpdir"

count = 300
out = nil
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} --count N --out DIR"
  opts.on("--count N", Integer, "number of synthetic gems (default 300)") { |n| count = n }
  opts.on("--out DIR", String, "output directory (recreated)") { |d| out = d }
end.parse!

abort "synthetic-index: --count must be positive" unless count.positive?
abort "synthetic-index: --out is required" unless out

out = File.expand_path(out)
abort "synthetic-index: refusing to recreate a filesystem root" if File.dirname(out) == out
abort "synthetic-index: refusing to recreate the home directory" if out == Dir.home
abort "synthetic-index: refusing to recreate a git worktree" if File.directory?(File.join(out, ".git"))
FileUtils.rm_rf(out)
FileUtils.mkdir_p(File.join(out, "gems"))

specs = []
Dir.mktmpdir("celerite-synthetic") do |build_dir|
  Dir.chdir(build_dir) do
    count.times do |index|
      name = format("synth_%04d", index + 1)
      spec = Gem::Specification.new do |s|
        s.name = name
        s.version = "1.0.0"
        s.summary = "synthetic gem #{name}"
        s.description = s.summary
        s.authors = ["Celerite"]
        s.files = []
        s.require_paths = ["lib"]
      end
      Gem::Package.build(spec)
      FileUtils.mv(File.join(build_dir, "#{spec.full_name}.gem"), File.join(out, "gems"))
      specs << spec
    end
  end
end

# This produces the legacy specs/latest_specs files and, with build_compact,
# the compact info/<name> and versions files required by Celerite.
Gem::Indexer.new(out, build_compact: true).generate_index

fragment = specs.map { |spec| %(gem "#{spec.name}", "#{spec.version}") }.join("\n")
File.write(File.join(out, "Gemfile.fragment"), "#{fragment}\n")
puts "generated #{count} synthetic gems in #{out}"
