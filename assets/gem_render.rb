# frozen_string_literal: true

# Renders bundler's newgem templates with the same ERB context as
# Bundler::CLI::Gem (4.0.24 / 2.7.2). Invoked by Celerite's `bundle gem`.
#
# Input: JSON on stdin, see Celerite::GemTemplate.
# Output: JSON array of {"path": ..., "content": ...} in template order.

require "erb"
require "json"

payload = JSON.parse($stdin.read)

version = payload.fetch("bundler_version")
template_root = payload.fetch("template_root")
name = payload.fetch("name")
github_username = payload.fetch("github_username")
use_git = payload.fetch("git")

# Templates reference Bundler::VERSION; the real bundler is not loaded here.
unless defined?(Bundler)
  module Bundler
  end
end
Bundler.const_set(:VERSION, version) unless Bundler.const_defined?(:VERSION)

underscored_name = name.tr("-", "_")
namespaced_path = name.tr("-", "/")
constant_name = name.gsub(/-[_-]*(?![_-]|$)/) { "::" }.gsub(/([_-]+|(::)|^)(.|$)/) { $2.to_s + $3.upcase }
constant_array = constant_name.split("::")
minitest_constant_name = constant_array.clone.tap { |a| a[-1] = "Test#{a[-1]}" }.join("::")

if github_username.empty?
  homepage_uri = "TODO: Put your gem's website or public repo URL here."
  source_code_uri = "TODO: Put your gem's public repo URL here."
  changelog_uri = "TODO: Put your gem's CHANGELOG.md URL here."
else
  homepage_uri = "https://github.com/#{github_username}/#{name}"
  source_code_uri = "https://github.com/#{github_username}/#{name}"
  changelog_uri = "https://github.com/#{github_username}/#{name}/blob/main/CHANGELOG.md"
end

config = {
  name: name,
  underscored_name: underscored_name,
  namespaced_path: namespaced_path,
  makefile_path: "#{underscored_name}/#{underscored_name}",
  constant_name: constant_name,
  constant_array: constant_array,
  author: payload.fetch("author"),
  email: payload.fetch("email"),
  test: payload["test"],
  ext: payload["ext"],
  exe: payload["exe"],
  bundle: payload["bundle"],
  bundler_version: version,
  git: use_git,
  github_username: github_username.empty? ? "[USERNAME]" : github_username,
  required_ruby_version: "3.2.0",
  rust_builder_required_rubygems_version: "3.3.11",
  minitest_constant_name: minitest_constant_name,
  ignore_paths: %w[bin/],
  homepage_uri: homepage_uri,
  source_code_uri: source_code_uri,
  changelog_uri: changelog_uri,
  git_default_branch: payload["git_default_branch"],
}

templates = {
  "Gemfile.tt" => "Gemfile",
  "lib/newgem.rb.tt" => "lib/#{namespaced_path}.rb",
  "lib/newgem/version.rb.tt" => "lib/#{namespaced_path}/version.rb",
  "sig/newgem.rbs.tt" => "sig/#{namespaced_path}.rbs",
  "newgem.gemspec.tt" => "#{name}.gemspec",
  "Rakefile.tt" => "Rakefile",
  "README.md.tt" => "README.md",
  "bin/console.tt" => "bin/console",
  "bin/setup.tt" => "bin/setup",
}
config[:ignore_paths] << "Gemfile"

if use_git
  templates["gitignore.tt"] = ".gitignore"
  config[:ignore_paths] << ".gitignore"
end

case config[:test]
when "rspec"
  config[:test_framework_version] = "3.0"
  templates.merge!(
    "rspec.tt" => ".rspec",
    "spec/spec_helper.rb.tt" => "spec/spec_helper.rb",
    "spec/newgem_spec.rb.tt" => "spec/#{namespaced_path}_spec.rb"
  )
  config[:test_task] = :spec
  config[:ignore_paths] << ".rspec" << "spec/"
when "minitest"
  config[:test_framework_version] = "5.16"
  paths = namespaced_path.rpartition("/")
  paths[2] = "test_#{paths[2]}"
  templates.merge!(
    "test/minitest/test_helper.rb.tt" => "test/test_helper.rb",
    "test/minitest/test_newgem.rb.tt" => "test/#{paths.join}"
  )
  config[:test_task] = :test
  config[:ignore_paths] << "test/"
when "test-unit"
  config[:test_framework_version] = "3.0"
  templates.merge!(
    "test/test-unit/test_helper.rb.tt" => "test/test_helper.rb",
    "test/test-unit/newgem_test.rb.tt" => "test/#{namespaced_path}_test.rb"
  )
  config[:test_task] = :test
  config[:ignore_paths] << "test/"
end

config[:ci] = payload["ci"]

case config[:ci]
when "github"
  templates["github/workflows/main.yml.tt"] = ".github/workflows/main.yml"
  if config[:ext] == "rust"
    templates["github/workflows/build-gems.yml.tt"] = ".github/workflows/build-gems.yml"
  end
  config[:ignore_paths] << ".github/"
when "gitlab"
  templates["gitlab-ci.yml.tt"] = ".gitlab-ci.yml"
  config[:ignore_paths] << ".gitlab-ci.yml"
when "circle"
  templates["circleci/config.yml.tt"] = ".circleci/config.yml"
  config[:ignore_paths] << ".circleci/"
end

if payload["mit"]
  config[:mit] = true
  templates["LICENSE.txt.tt"] = "LICENSE.txt"
end
if payload["coc"]
  config[:coc] = true
  templates["CODE_OF_CONDUCT.md.tt"] = "CODE_OF_CONDUCT.md"
end
if payload["changelog"]
  config[:changelog] = true
  templates["CHANGELOG.md.tt"] = "CHANGELOG.md"
end

case config[:linter] = payload["linter"]
when "rubocop"
  config[:linter_version] = "1.21"
  templates["rubocop.yml.tt"] = ".rubocop.yml"
  config[:ignore_paths] << ".rubocop.yml"
when "standard"
  config[:linter_version] = "1.3"
  templates["standard.yml.tt"] = ".standard.yml"
  config[:ignore_paths] << ".standard.yml"
end

if config[:exe]
  templates["exe/newgem.tt"] = "exe/#{name}"
end

case config[:ext]
when "c"
  templates.merge!(
    "ext/newgem/extconf-c.rb.tt" => "ext/#{name}/extconf.rb",
    "ext/newgem/newgem.h.tt" => "ext/#{name}/#{underscored_name}.h",
    "ext/newgem/newgem.c.tt" => "ext/#{name}/#{underscored_name}.c"
  )
when "rust"
  templates["Cargo.toml.tt"] = "Cargo.toml"
  templates["ext/newgem/Cargo.toml.tt"] = "ext/#{name}/Cargo.toml"
  # 4.0.24 added build.rs to the Rust scaffold, before extconf; 2.7.2 has no
  # such template (2.7.2 gem.rb:228-232 vs 4.0.24 gem.rb:229-237).
  templates["ext/newgem/build.rs.tt"] = "ext/#{name}/build.rs" if version.start_with?("4.")
  templates["ext/newgem/extconf-rust.rb.tt"] = "ext/#{name}/extconf.rb"
  templates["ext/newgem/src/lib.rs.tt"] = "ext/#{name}/src/lib.rs"
when "go"
  templates.merge!(
    "ext/newgem/go.mod.tt" => "ext/#{name}/go.mod",
    "ext/newgem/extconf-go.rb.tt" => "ext/#{name}/extconf.rb",
    "ext/newgem/newgem.h.tt" => "ext/#{name}/#{underscored_name}.h",
    "ext/newgem/newgem.go.tt" => "ext/#{name}/#{underscored_name}.go",
    "ext/newgem/newgem-go.c.tt" => "ext/#{name}/#{underscored_name}.c"
  )
  config[:go_module_username] = config[:github_username] == "[USERNAME]" ? "username" : config[:github_username]
end

entries = templates.map do |src, dst|
  content = ERB.new(File.read(File.join(template_root, src)), trim_mode: "-").result(binding)
  { "path" => dst, "content" => content }
end

$stdout.write(JSON.generate(entries))
