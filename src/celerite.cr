# Celerite is a Bundler-compatible Ruby dependency manager written in Crystal.
#
# Core semantic modules are required here so both the binary and the spec
# suite see the same world.
require "./celerite/profile"
require "./celerite/errors"
require "./celerite/uri_credentials_filter"
require "./celerite/gem/version"
require "./celerite/gem/requirement"
require "./celerite/gem/platform"
require "./celerite/ruby_version"
require "./celerite/ruby_runtime"
require "./celerite/checksum"
require "./celerite/lockfile/model"
require "./celerite/lockfile/parser"
require "./celerite/config"
require "./celerite/release_metadata"
require "./celerite/definition"
require "./celerite/resolver/package"
require "./celerite/resolver/ranges"
require "./celerite/resolver/solver"
require "./celerite/resolver/source"
require "./celerite/bridge/client"
require "./celerite/gemfile_evaluation"
require "./celerite/file_url"
require "./celerite/compact_index/cache"
require "./celerite/resolution"

module Celerite
  VERSION = "0.1.0"
end
