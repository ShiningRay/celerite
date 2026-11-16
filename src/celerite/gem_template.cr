module Celerite
  # Renders the `bundle gem` scaffold with the same content as
  # bundler-4.0.24's templates/newgem (see bundler/cli/gem.rb:88-98).
  #
  # Values mirror gem.rb:
  # * author/email come from `git config user.name` / `user.email`, with the
  #   same "TODO: Write your name" / "TODO: Write your email address"
  #   fallbacks (gem.rb:47-49,69-70);
  # * github_username comes from `git config github.user` and defaults to the
  #   literal "[USERNAME]" (gem.rb:16,48,77), which also selects the TODO
  #   homepage/source URIs (gem.rb:52-60);
  # * the constant name follows the hyphen/underscore rules at gem.rb:39-41
  #   ("foo-bar" => Foo::Bar, "foo_bar" => FooBar);
  # * `year` is not used by any 4.0.24 default template.
  #
  # Non-default options (--test/--mit/--coc/--changelog/--linter/--exe/
  # --ext/--bin/--edit/--bundle/--github-username) are rejected by the caller
  # instead of being rendered; that is a declared deviation.
  module GemTemplate
    DEFAULT_GITHUB_USERNAME = "[USERNAME]"

    record FileEntry, path : String, content : String

    def self.render(name : String, author : String, email : String,
                    github_username : String, use_git : Bool) : Array(FileEntry)
      underscored = name.tr("-", "_")
      namespaced = name.tr("-", "/")
      constant = constant_name(name)
      github = github_username.empty? ? DEFAULT_GITHUB_USERNAME : github_username

      if github == DEFAULT_GITHUB_USERNAME
        homepage_uri = "TODO: Put your gem's website or public repo URL here."
        source_code_uri = "TODO: Put your gem's public repo URL here."
      else
        homepage_uri = "https://github.com/#{github}/#{name}"
        source_code_uri = "https://github.com/#{github}/#{name}"
      end

      entries = [
        FileEntry.new("Gemfile", gemfile(name)),
        FileEntry.new("lib/#{namespaced}.rb", library(namespaced, constant)),
        FileEntry.new("lib/#{namespaced}/version.rb", version(constant)),
        FileEntry.new("sig/#{namespaced}.rbs", rbs(constant)),
        FileEntry.new("#{name}.gemspec",
          gemspec(name, namespaced, constant, author, email, homepage_uri, source_code_uri, use_git)),
        FileEntry.new("Rakefile", rake_file),
        FileEntry.new("README.md", readme(name, namespaced, constant, github, use_git)),
        FileEntry.new("bin/console", console(namespaced)),
        FileEntry.new("bin/setup", setup_script),
      ]
      # gem.rb:113-116 only adds gitignore.tt when the git scaffold is enabled.
      entries << FileEntry.new(".gitignore", gitignore) if use_git
      # Crystal heredocs do not include the final newline; the reference
      # templates all end with exactly one LF.
      entries.map { |entry| FileEntry.new(entry.path, terminate(entry.content)) }
    end

    private def self.terminate(text : String) : String
      text.sub(/\n*\z/, "\n")
    end

    # gem.rb:39-41: `-` becomes "::", `_` only splits words ("foo-bar" =>
    # Foo::Bar, "foo_bar" => FooBar) and each segment is capitalized.
    def self.constant_name(name : String) : String
      name.split("-").map do |segment|
        segment.split("_").map do |part|
          next "" if part.empty?
          part[0].upcase + (part.size > 1 ? part[1..] : "")
        end.join
      end.reject(&.empty?).join("::")
    end

    private def self.gemfile(name : String) : String
      <<-TEXT
      # frozen_string_literal: true

      source "https://rubygems.org"

      # Specify your gem's dependencies in #{name}.gemspec
      gemspec

      gem "irb"
      gem "rake", "~> 13.0"
      TEXT
    end

    private def self.library(namespaced : String, constant : String) : String
      parts = constant.split("::")
      String.build do |io|
        io << "# frozen_string_literal: true\n\n"
        io << %(require_relative "#{File.basename(namespaced)}/version"\n\n)
        open_modules(io, parts)
        io << "  " * parts.size << "class Error < StandardError; end\n"
        io << "  " * parts.size << "# Your code goes here...\n"
        close_modules(io, parts)
      end
    end

    private def self.version(constant : String) : String
      parts = constant.split("::")
      String.build do |io|
        io << "# frozen_string_literal: true\n\n"
        open_modules(io, parts)
        io << "  " * parts.size << %(VERSION = "0.1.0"\n)
        close_modules(io, parts)
      end
    end

    private def self.rbs(constant : String) : String
      parts = constant.split("::")
      String.build do |io|
        open_modules(io, parts)
        io << "  " * parts.size << "VERSION: String\n"
        io << "  " * parts.size << "# See the writing guide of rbs: https://github.com/ruby/rbs#guides\n"
        close_modules(io, parts)
      end
    end

    private def self.gemspec(name : String, namespaced : String, constant : String,
                             author : String, email : String,
                             homepage_uri : String, source_code_uri : String,
                             use_git : Bool) : String
      ignore_paths = use_git ? "bin/ Gemfile .gitignore" : "bin/ Gemfile"
      <<-TEXT
      # frozen_string_literal: true

      require_relative "lib/#{namespaced}/version"

      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = #{constant}::VERSION
        spec.authors = [#{author.inspect}]
        spec.email = [#{email.inspect}]

        spec.summary = "TODO: Write a short summary, because RubyGems requires one."
        spec.description = "TODO: Write a longer description or delete this line."
        spec.homepage = "#{homepage_uri}"
        spec.required_ruby_version = ">= 3.2.0"
        spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
        spec.metadata["homepage_uri"] = spec.homepage
        spec.metadata["source_code_uri"] = "#{source_code_uri}"

        # Uncomment the line below to require MFA for gem pushes.
        # This helps protect your gem from supply chain attacks by ensuring
        # no one can publish a new version without multi-factor authentication.
        # See: https://guides.rubygems.org/mfa-requirement-opt-in/
        # spec.metadata["rubygems_mfa_required"] = "true"

        # Specify which files should be added to the gem when it is released.
        # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
        gemspec = File.basename(__FILE__)
        spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
          ls.readlines("\\x0", chomp: true).reject do |f|
            (f == gemspec) ||
              f.start_with?(*%w[#{ignore_paths}])
          end
        end
        spec.bindir = "exe"
        spec.executables = spec.files.grep(%r{\\Aexe/}) { |f| File.basename(f) }
        spec.require_paths = ["lib"]

        # Uncomment to register a new dependency of your gem
        # spec.add_dependency "example-gem", "~> 1.0"

        # For more information and examples about making a new gem, check out our
        # guide at: https://guides.rubygems.org/make-your-own-gem/
      end
      TEXT
    end

    private def self.rake_file : String
      <<-TEXT
      # frozen_string_literal: true

      require "bundler/gem_tasks"
      task default: %i[]
      TEXT
    end

    private def self.readme(name : String, namespaced : String, constant : String,
                            github : String, use_git : Bool) : String
      String.build do |io|
        io << <<-TEXT
        # #{constant}

        TODO: Delete this and the text below, and describe your gem

        Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/#{namespaced}`. To experiment with that code, run `bin/console` for an interactive prompt.

        ## Installation

        TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

        Install the gem and add to the application's Gemfile by executing:

        ```bash
        bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
        ```

        If bundler is not being used to manage dependencies, install the gem by executing:

        ```bash
        gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
        ```

        ## Usage

        TODO: Write usage instructions here

        ## Development

        After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

        To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).
        TEXT
        if use_git
          # The heredoc above has no trailing newline, so start with two:
          # one closes the Development paragraph, one is the blank separator.
          io << "\n\n## Contributing\n\n"
          io << "Bug reports and pull requests are welcome on GitHub at " \
                "https://github.com/#{github}/#{name}.\n"
        end
      end
    end

    private def self.console(namespaced : String) : String
      <<-TEXT
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "bundler/setup"
      require "#{namespaced}"

      # You can add fixtures and/or initialization code here to make experimenting
      # with your gem easier. You can also use a different console, if you like.

      require "irb"
      IRB.start(__FILE__)
      TEXT
    end

    private def self.setup_script : String
      <<-TEXT
      #!/usr/bin/env bash
      set -euo pipefail
      IFS=$'\\n\\t'
      set -vx

      bundle install

      # Do any other automated setup that you need to do here
      TEXT
    end

    private def self.gitignore : String
      <<-TEXT
      /.bundle/
      /.yardoc
      /_yardoc/
      /coverage/
      /doc/
      /pkg/
      /spec/reports/
      /tmp/
      TEXT
    end

    private def self.open_modules(io : IO, parts : Array(String)) : Nil
      parts.each_with_index do |part, index|
        io << "  " * index << "module " << part << "\n"
      end
    end

    private def self.close_modules(io : IO, parts : Array(String)) : Nil
      (parts.size - 1).downto(0) do |index|
        io << "  " * index << "end\n"
      end
    end
  end
end
