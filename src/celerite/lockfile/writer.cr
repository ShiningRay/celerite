require "file"

module Celerite
  module Lockfile
    # Reference `Bundler::Definition#lock` (bundler-4.0.24 definition.rb:428-434)
    # keeps the on-disk line-ending style: when the existing lockfile uses
    # CRLF, the freshly generated contents are converted before writing;
    # a brand-new lockfile stays LF. Reading with `File.read` is binary in
    # Crystal (no CRLF translation), so the check sees the raw bytes.
    def self.write(path : String, contents : String, preserve_crlf : Bool = true) : Nil
      text = contents
      if preserve_crlf && File.file?(path) && File.read(path).includes?("\r\n")
        # Only lift *lone* LFs; a CRLF already present must not become CRCRLF.
        text = contents.gsub(/(?<!\r)\n/, "\r\n")
      end
      File.write(path, text)
    end
  end
end
