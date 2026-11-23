#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuilds fixtures/gem-index-build-args from spec/fixtures/build-args.
#
# `spec/m7_build_args_spec.cr` drives `bundle install` of the prebuilt
# `build-args-demo` gem through a `file:` source. The reference serves a
# `file:` GEM source from the legacy index only (`bundler-4.0.24
# fetcher.rb:271-280`), so the source directory must carry `specs.4.8.gz`;
# without it both implementations fail with `Could not fetch specs ...` exit 17
# before any `build.<gem>` argument can reach extconf.
#
# The gem itself stays in spec/fixtures (the spec builds no package); this
# script only produces the index the two implementations read.
require "rubygems"
require "rubygems/indexer"
require "fileutils"

root = File.expand_path("..", __dir__)
source_dir = File.expand_path(ARGV[0] || File.join(root, "spec/fixtures/build-args"), root)
output_dir = File.expand_path(ARGV[1] || File.join(root, "fixtures/gem-index-build-args"), root)

gemspec = Dir[File.join(source_dir, "*.gemspec")].sort.first
raise "no gemspec under #{source_dir}" unless gemspec

FileUtils.rm_rf(output_dir)
FileUtils.mkdir_p(File.join(output_dir, "gems"))

built = Dir[File.join(source_dir, "gems", "*.gem")].sort
raise "no prebuilt gem under #{source_dir}/gems" if built.empty?

built.each { |path| FileUtils.cp(path, File.join(output_dir, "gems", File.basename(path))) }

Gem::Indexer.new(output_dir, build_compact: true).generate_index

# The indexer writes text files with CRLF on Windows; the repository keeps LF.
Dir.glob(File.join(output_dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
  next unless File.file?(path)
  next unless path.end_with?("/names", "/versions") || path.include?("/info/")

  File.binwrite(path, File.binread(path).gsub("\r\n", "\n"))
end

puts "built #{output_dir} (#{built.size} gem(s))"
