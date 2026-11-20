module Celerite
  # Renders Bundler's `Executable` stub template
  # (`lib/bundler/templates/Executable`, copied verbatim to
  # `assets/bundler_templates/<profile>/Executable`). The reference renders it
  # through ERB in `Bundler::Binstub#write` (4.0.24 `binstub.rb:20-27`,
  # 2.7.2 :14-22); the placeholder set is small enough to substitute directly.
  # The two profiles' templates are byte-identical today; they are kept apart so
  # a future divergence stays visible.
  module BinstubTemplate
    def self.render(profile : String, spec_name : String, executable : String,
                    relative_gemfile_path : String, shebang : String) : String
      template(profile)
        .gsub(%q(<%= Bundler.settings[:shebang] || RbConfig::CONFIG["ruby_install_name"] %>), shebang)
        .gsub("<%= executable %>", executable)
        .gsub("<%= relative_gemfile_path %>", relative_gemfile_path)
        .gsub("<%= spec.name %>", spec_name)
    end

    # `Bundler::Binstub` writes `relative_gemfile_path` as
    # `Pathname.new(gemfile).relative_path_from(bin_path)` (binstub.rb:35-37),
    # so the stub points at the Gemfile from the directory holding the stub.
    def self.relative_gemfile_path(from_dir : String, gemfile : String) : String
      target = File.expand_path(gemfile).gsub('\\', "/")
      from = File.expand_path(from_dir).gsub('\\', "/").split('/')
      to = target.split('/')
      # Different roots (e.g. two drives on Windows) cannot be expressed
      # relatively; binstub.rb keeps the absolute path in that case.
      return target if from.empty? || to.empty? || from.first != to.first

      common = 0
      limit = Math.min(from.size, to.size)
      while common < limit && from[common] == to[common]
        common += 1
      end
      parts = Array(String).new(from.size - common + to.size)
      (from.size - common).times { parts << ".." }
      parts.concat(to[common..])
      parts.join('/')
    end

    def self.template(profile : String) : String
      File.read(asset_path(File.join("bundler_templates", profile, "Executable")))
    end

    private def self.asset_path(relative : String) : String
      source_relative = File.expand_path("../../assets/#{relative}", __DIR__)
      return source_relative if File.file?(source_relative)

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
          return expanded if File.file?(expanded)
        end
      end
      source_relative
    end
  end
end
