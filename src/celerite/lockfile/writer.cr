require "file"
require "random/secure"
require "../errors"
require "../filesystem_errors"

module Celerite
  module Lockfile
    # Reference `Bundler::Definition#lock` (bundler-4.0.24 definition.rb:428-434)
    # keeps the on-disk line-ending style: when the existing lockfile uses
    # CRLF, the freshly generated contents are converted before writing;
    # a brand-new lockfile stays LF. Reading with `File.read` is binary in
    # Crystal (no CRLF translation), so the check sees the raw bytes.
    def self.render(path : String, contents : String, preserve_crlf : Bool = true) : String
      if preserve_crlf && File.file?(path) && File.read(path).includes?("\r\n")
        # Only lift *lone* LFs; a CRLF already present must not become CRCRLF.
        contents.gsub(/(?<!\r)\n/, "\r\n")
      else
        contents
      end
    end

    # Replace in the same directory: flush and fsync the temporary file, close
    # it, then rename over the target. The target is never deleted first, so a
    # failed write/rename preserves the previous bytes. Temporary files are
    # cleaned on every path; rename is the final operation.
    def self.write(path : String, contents : String, preserve_crlf : Bool = true) : Nil
      text = render(path, contents, preserve_crlf)
      temp = File.join(File.dirname(path), ".#{File.basename(path)}.#{Process.pid}.#{Random::Secure.hex(8)}.tmp")
      begin
        File.open(temp, "wb") do |file|
          file.print(text)
          file.flush
          file.fsync
        end
        File.rename(temp, path)
      ensure
        begin
          File.delete(temp) if File.exists?(temp)
        rescue File::Error
          # Cleanup is best-effort and must not hide the original write error.
        end
      end
    rescue ex : File::Error
      # Reference: `filesystem_access(file) { File.open(p, "wb") { ... } }`
      # maps EACCES/EPERM/ENOSPC/... to their Bundler error classes; ENOENT
      # and EEXIST keep bubbling unchanged.
      mapped = FilesystemErrors.map(ex, :write, path)
      mapped ? raise mapped : raise ex
    end
  end
end
