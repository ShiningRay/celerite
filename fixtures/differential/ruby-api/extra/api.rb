require "thor"
puts "Bundler.bundle_path: #{Bundler.bundle_path}"
puts "Bundler.root: #{Bundler.root}"
puts "deps: #{Bundler.definition.dependencies.map(&:name).sort.inspect}"
puts "locked specs: #{Bundler.definition.resolve.map(&:full_name).sort.inspect}"
Bundler.require(:default)
puts "Thor defined: #{defined?(Thor) != nil}"
puts "Bundler.settings[:frozen]: #{Bundler.settings[:frozen]}"
