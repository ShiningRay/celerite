rubyopt = ENV["RUBYOPT"].to_s.split
normalized = rubyopt.map { |arg| arg.tr("\\", "/") }
setup_entries = normalized.count { |arg| arg.end_with?("/bundler/setup") }
puts "setup_entries=#{setup_entries}"