#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuilds fixtures/gem-index-plugin-gem from fixtures/plugin-source-gem:
# one plugin gem plus a legacy (specs.4.8 / quick) and compact (versions /
# info) index, so both the reference and Celerite can install the plugin from
# a file:// source.
require "rubygems"
require "rubygems/package"
require "rubygems/indexer"
require "fileutils"

root = File.expand_path("..", __dir__)
source_dir = File.expand_path(ARGV[0] || File.join(root, "fixtures/plugin-source-gem"), root)
output_dir = File.expand_path(ARGV[1] || File.join(root, "fixtures/gem-index-plugin-gem"), root)

spec_path = Dir[File.join(source_dir, "*.gemspec")].sort.first
raise "no gemspec under #{source_dir}" unless spec_path

spec = Gem::Specification.load(spec_path)
raise "cannot load #{spec_path}" unless spec

FileUtils.rm_rf(output_dir)
FileUtils.mkdir_p(File.join(output_dir, "gems"))

built = Dir.chdir(source_dir) { Gem::Package.build(spec) }
FileUtils.mv(File.join(source_dir, built), File.join(output_dir, "gems", built))

Gem::Indexer.new(output_dir, build_compact: true).generate_index

# The indexer writes text files with CRLF on Windows; the repository keeps LF.
Dir.glob(File.join(output_dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
  next unless File.file?(path)
  next unless path.end_with?(".versions", "/names", "/versions", "/names") || path.include?("/info/")

  data = File.binread(path)
  File.binwrite(path, data.gsub("\r\n", "\n"))
end

puts "built #{File.join(output_dir, "gems", built)}"
