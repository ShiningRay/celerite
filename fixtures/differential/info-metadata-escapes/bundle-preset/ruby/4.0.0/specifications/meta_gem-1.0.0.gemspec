Gem::Specification.new do |s|
  s.name = "meta_gem"
  s.version = "1.0.0"
  s.summary = 'Summary with "quotes" and \\ backslash'
  s.description = "A gem whose metadata needs Ruby string decoding."
  s.authors = ["Celerite"]
  s.files = ["lib/meta_gem.rb"]
  s.require_paths = ["lib"]
  s.homepage = "https://example.com/meta_gem"
  s.license = "MIT"
  s.metadata = {
    "documentation_uri" => "path\\with\\backslashes",
    "changelog_uri" => "line1\nline2",
    "source_code_uri" => "https://example.com/src",
    "homepage_uri" => "https://example.com/home",
  }
end
