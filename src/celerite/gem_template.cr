module Celerite
  # Renders the `bundle gem` scaffold through bundler's own ERB templates
  # (`assets/gem_templates/<profile>/newgem`, copied from the installed
  # bundler 4.0.24 / 2.7.2 gems). The Ruby helper mirrors the config hash and
  # template selection in `.upstream-specs/v4.0.24/bundler/lib/bundler/cli/gem.rb`
  # (4.0.24 :62-98, :105-250); 2.7.2 uses the same branches with the Go
  # extension removed and the `--rubocop` option retained.
  module GemTemplate
    record FileEntry, path : String, content : String

    record Options,
      test : String? = nil,
      ci : String? = nil,
      linter : String? = nil,
      ext : String? = nil,
      exe : Bool = false,
      mit : Bool = false,
      coc : Bool = false,
      changelog : Bool = false,
      bundle : Bool = false

    def self.render(name : String, author : String, email : String,
                    github_username : String, use_git : Bool, profile : String,
                    options : Options, git_default_branch : String? = nil) : Array(FileEntry)
      script = asset_path("gem_render.rb")
      templates = asset_path(File.join("gem_templates", profile, "newgem"))
      payload = JSON.build do |json|
        json.object do
          json.field "name", name
          json.field "author", author
          json.field "email", email
          json.field "github_username", github_username
          json.field "git", use_git
          json.field "bundler_version", profile
          json.field "template_root", templates
          json.field "test", options.test
          json.field "ci", options.ci
          json.field "linter", options.linter
          json.field "ext", options.ext
          json.field "exe", options.exe
          json.field "mit", options.mit
          json.field "coc", options.coc
          json.field "changelog", options.changelog
          json.field "bundle", options.bundle
          json.field "git_default_branch", git_default_branch
        end
      end

      ruby = ENV["CELERITE_RUBY"]? || "ruby"
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run(ruby, [script], input: IO::Memory.new(payload), output: output, error: error)
      unless status.success?
        raise "bundle gem renderer failed: #{error.to_s.strip}"
      end
      JSON.parse(output.to_s).as_a.map do |entry|
        FileEntry.new(entry["path"].as_s, entry["content"].as_s)
      end
    end

    def self.help_text(profile : String) : String
      File.read(asset_path(File.join("gem_help", "#{profile}.txt")))
    end

    private def self.asset_path(relative : String) : String
      source_relative = File.expand_path("../../assets/#{relative}", __DIR__)
      return source_relative if File.file?(source_relative) || Dir.exists?(source_relative)

      exe_dir = begin
        File.dirname(Process.executable_path || "")
      rescue
        ""
      end
      unless exe_dir.empty?
        candidates = [
          File.join(exe_dir, "assets", relative),
          File.join(exe_dir, "..", "assets", relative),
          File.join(exe_dir, "..", "..", "assets", relative),
        ]
        candidates.each do |candidate|
          expanded = File.expand_path(candidate)
          return expanded if File.file?(expanded) || Dir.exists?(expanded)
        end
      end
      source_relative
    end
  end
end
