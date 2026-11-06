require "./tar"
require "./downloader"
require "./bridge/client"
require "./gem/platform"
require "./errors"
require "file_utils"

module Celerite
  # Installs resolved gems into the bundle path with the reference tree
  # layout: `<path>/ruby/<abi>/{cache,gems,specifications,bin,extensions}`
  # (pinned observation from the reference oracle). Writes happen into
  # per-gem temp directories and are renamed into place atomically.
  class Installer
    getter install_path : String
    getter ruby_abi : String

    def initialize(@install_path : String, @ruby_abi : String, @bridge : Bridge::Client,
                   @downloader : Downloader, progress : IO)
      @progress = progress
      @install_root = File.join(install_path, "ruby", ruby_abi)
    end

    def installed?(name : String, version : String, platform : String?) : Bool
      full_name = (platform.nil? || platform == "ruby") ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      spec_path = File.join(@install_root, "specifications", "#{full_name}.gemspec")
      gem_dir = File.join(@install_root, "gems", full_name)
      File.file?(spec_path) && Dir.exists?(gem_dir)
    end

    # Installs one gem; skips when already installed (idempotent parity).
    # Returns true when work was done.
    def install(name : String, version : String, platform : String?, checksum : String?) : Bool
      return false if installed?(name, version, platform)

      full_name = (platform.nil? || platform == "ruby") ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"

      gem_file = @downloader.fetch(name, version, platform, checksum)
      read_spec(gem_file)

      # extraction root (temp, renamed per part at the end)
      work = File.join(@install_root, ".celerite-install-#{Process.pid}-#{rand(1 << 30)}")
      gem_dir = File.join(work, "gems", full_name)
      cache_dir = File.join(work, "cache")
      spec_dir = File.join(work, "specifications")
      bin_dir = File.join(work, "bin")
      Dir.mkdir_p(gem_dir)
      Dir.mkdir_p(cache_dir)
      Dir.mkdir_p(spec_dir)

      # cache copy + payload extraction
      FileUtils.cp(gem_file, File.join(cache_dir, "#{full_name}.gem"))
      extract_payload(gem_file, gem_dir)

      # installed specification (Marshal, written by the Ruby bridge)
      spec_destination = File.join(spec_dir, "#{full_name}.gemspec")
      written = Bridge::WrittenSpec.from_json(
        @bridge.write_installed_spec(gem_file, spec_destination, gem_dir).to_json
      )

      # executables
      unless written.executables.empty?
        Dir.mkdir_p(bin_dir)
        bindir = written.bindir.empty? ? "bin" : written.bindir
        written.executables.each do |executable|
          source = File.join(gem_dir, bindir, executable)
          next unless File.file?(source)
          copy_executable(source, File.join(bin_dir, executable), full_name)
          write_windows_stub(File.join(bin_dir, "#{executable}.bat"), executable, full_name) if windows?
        end
      end

      # publish atomically: move each part into place
      target_cache = File.join(@install_root, "cache")
      target_gems = File.join(@install_root, "gems")
      target_specs = File.join(@install_root, "specifications")
      target_bin = File.join(@install_root, "bin")
      FileUtils.mkdir_p(target_cache)
      FileUtils.mkdir_p(target_gems)
      FileUtils.mkdir_p(target_specs)

      File.rename(File.join(cache_dir, "#{full_name}.gem"), File.join(target_cache, "#{full_name}.gem"))
      File.rename(gem_dir, File.join(target_gems, full_name))

      # native extensions (Ruby toolchain via the bridge, architecture §2.1)
      unless written.extensions.empty?
        extension_dir = File.join(@install_root, "extensions", Gem::Platform.local.to_s,
          @ruby_abi, full_name)
        build_result = @bridge.build_extension(
          File.join(target_gems, full_name), extension_dir, name
        )
        if build_result["error"]?
          raise Error.new("extension build failed for #{full_name}: #{build_result["error"].as_s}")
        end
      end

      File.rename(spec_destination, File.join(target_specs, "#{full_name}.gemspec"))
      if Dir.exists?(bin_dir) && !Dir.empty?(bin_dir)
        FileUtils.mkdir_p(target_bin)
        Dir.children(bin_dir).each do |child|
          File.rename(File.join(bin_dir, child), File.join(target_bin, child))
        end
      end

      FileUtils.rm_rf(work)
      true
    end

    private def windows? : Bool
      {% if flag?(:windows) %}
        true
      {% else %}
        false
      {% end %}
    end

    private def read_spec(gem_file : String) : Bridge::GemSpecInfo
      Bridge::GemSpecInfo.from_json(@bridge.read_gem_spec(gem_file).to_json)
    end

    # Extracts `data.tar.gz` from the .gem into destination.
    private def extract_payload(gem_file : String, destination : String) : Nil
      File.open(gem_file, "rb") do |io|
        Tar.each_entry(io) do |entry, data|
          next unless entry.name == "data.tar.gz"
          payload = data.not_nil!
          Tar.each_gzip_entry(payload) do |file_entry, file_data|
            destination_entry = File.expand_path(file_entry.name, destination)
            unless destination_entry.starts_with?(File.expand_path(destination))
              raise Error.new("path traversal in gem payload: #{file_entry.name}")
            end
            if file_entry.directory
              Dir.mkdir_p(destination_entry)
            else
              parent = File.dirname(destination_entry)
              Dir.mkdir_p(parent)
              File.write(destination_entry, file_data.not_nil!.gets_to_end)
            end
          end
          return
        end
      end
      raise Error.new("gem package has no data.tar.gz: #{gem_file}")
    end

    # RubyGems-style executable wrapper (ruby script shebang + gem require).
    private def copy_executable(source : String, destination : String, full_name : String) : Nil
      content = File.read(source)
      shebang = content.starts_with?("#!") ? "" : "#!/usr/bin/env ruby\n"
      File.write(destination, shebang + content)
      File.chmod(destination, 0o755) unless windows?
    end

    private def write_windows_stub(path : String, executable : String, full_name : String) : Nil
      File.write(path, <<-BAT)
      @ECHO OFF
      IF NOT "%~f0" == "~f0" GOTO :WinNT
      @"ruby.exe" "%~dpn0" %*
      GOTO :EOF
      :WinNT
      @"ruby.exe" "%~dpn0" %*
      BAT
    end
  end
end
