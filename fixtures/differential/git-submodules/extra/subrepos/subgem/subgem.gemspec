Gem::Specification.new do |s|
  s.name = "subgem"
  s.version = "0.1.0"
  s.summary = "subgem"
  s.authors = ["test"]
  s.required_ruby_version = ">= 2.6.0"
  s.files = Dir["lib/**/*.rb"] + Dir["subdep/**/*"]
end
