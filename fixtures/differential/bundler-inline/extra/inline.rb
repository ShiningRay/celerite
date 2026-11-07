require "bundler/inline"
gemfile(true) do
  source "file:///@INDEX_DIR@"
  gem "thor"
end
puts "inline Thor defined: #{defined?(Thor) != nil}"
