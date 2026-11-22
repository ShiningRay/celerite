require "process"

module Celerite
  # Bundled manpages: `bundle help <cmd>` and `bundle <cmd> --help` print the
  # rendered roff source (`.ronn`), exactly like the reference `Bundler::CLI#help`
  # does when `man` is unavailable (bundler/cli.rb:155-185):
  #
  #     puts File.read("#{man_path}/#{File.basename(man_page)}.ronn")
  #
  # The reference ships one manpage per bundler profile, so we vendor one
  # directory per profile under `assets/man/<version>/`. Ruby's `puts` writes
  # through a text-mode IO on Windows, which turns the file's LF into CRLF; we
  # reproduce that byte-for-byte by translating line endings when
  # `flag?(:windows)` is set.
  module Manpages
    PROFILE_DEFAULT = Celerite::Profile::DEFAULT_BUNDLER_VERSION

    # Reference `cli.rb:161-165`: the page name is derived from the command,
    # with `gemfile` being the only page that is not `bundle-<cmd>.1`.
    def self.page_name(command : String) : String
      case command
      when "bundle"
        "bundle.1.ronn"
      when "gemfile"
        "gemfile.5.ronn"
      else
        "bundle-#{command}.1.ronn"
      end
    end

    # Directories that may hold the vendored pages. Mirrors the bridge server
    # lookup in `Bridge::Client.locate_server`: explicit override, then
    # relative to the running executable, then relative to this source tree.
    def self.search_dirs(profile : String) : Array(String)
      dirs = [] of String
      if given = ENV["CELERITE_MAN_DIR"]?
        dirs << given unless given.empty?
      end
      if exe = Process.executable_path
        base = File.dirname(exe)
        dirs << File.join(base, "assets", "man", profile)
        dirs << File.join(base, "..", "assets", "man", profile)
      end
      dirs << File.expand_path("../../assets/man/#{profile}", __DIR__)
      dirs
    end

    # Path of the vendored page for `command`, or nil when the profile has no
    # page for it (the reference then falls back to Thor's default help).
    def self.path_for(command : String, profile : String = Commands.bundle_profile_version) : String?
      page = page_name(command)
      search_dirs(profile).each do |dir|
        candidate = File.join(dir, page)
        return candidate if File.file?(candidate)
      end
      nil
    end

    def self.content_for(command : String, profile : String = Commands.bundle_profile_version) : String?
      path_for(command, profile).try { |path| File.read(path) }
    end

    # Writes the page as the reference does: the file contents plus the text
    # mode line-ending translation, with no extra trailing newline.
    def self.render(command : String, stdout : IO, profile : String = Commands.bundle_profile_version) : Bool
      text = content_for(command, profile)
      return false if text.nil?
      stdout.print(normalize_newlines(text))
      true
    end

    # Ruby's text-mode `puts` translates the file's LF into CRLF on Windows and
    # `File.read` keeps whichever endings the file already has; the macro form
    # of `flag?` is required because it is a compile-time flag.
    def self.normalize_newlines(text : String) : String
      {% if flag?(:windows) %}
        return text if text.includes?("\r\n")
        text.gsub("\n", "\r\n")
      {% else %}
        text
      {% end %}
    end
  end
end
