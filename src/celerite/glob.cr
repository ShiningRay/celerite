module Celerite
  # `Dir.glob` on Windows treats `\` as an escape character, so a pattern built
  # with `File.join` (which yields `\` separators) never matches: an absolute
  # `C:\...\vendor\cache\*.gem` pattern returns an empty array even though the
  # directory exists. The same pattern written with `/` separators does match
  # (verified on Crystal 1.22.1). Listing the directory and matching entry
  # basenames with `File.match?` sidesteps the separator question entirely.
  #
  # `pattern` is a basename pattern (no separators): the call sites use
  # `*.gem`, `*.gemspec`, `<name>-*` and `*`.
  module Glob
    def self.paths(dir : String, pattern : String) : Array(String)
      path = dir.gsub('\\', "/")
      return [] of String unless Dir.exists?(path)
      Dir.children(path)
        .select { |name| File.match?(pattern, name) }
        .map { |name| File.join(path, name) }
        .sort
    end
  end
end
