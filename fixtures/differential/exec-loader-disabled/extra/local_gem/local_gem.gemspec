Gem::Specification.new do |s|
  s.name = "local_gem"
  s.version = "0.1.0"
  s.summary = "exec loader fixture"
  s.authors = ["test"]
  s.files = ["lib/local_gem.rb", "bin/loader"]
  s.executables = ["loader"]
  s.bindir = "bin"
  s.required_ruby_version = ">= 2.6.0"
end
