require "base64"

module Celerite
  # Normalizes compact-index checksum values to bare lowercase hex SHA-256.
  #
  # The reference ecosystem emits three shapes: raw 64-char hex
  # (rubygems.org `/info`), standard or url-safe base64 (43 chars unpadded or
  # 44 padded), and `sha256=<hex>`. Lockfile writing and download verification
  # share this normalization so the two paths cannot drift (the lockfile path
  # previously base64-decoded raw hex and wrote 96-char garbage).
  module Checksum
    HEX64  = /\A[0-9a-f]{64}\z/i
    BASE64 = /\A[-0-9a-z_+\/]{43}={0,2}\z/i

    def self.normalize_hex(raw : String) : String?
      value = raw.lchop("sha256=").strip
      return nil if value.empty?
      return value.downcase if value.matches?(HEX64)
      return nil unless value.matches?(BASE64)
      padded = value.tr("-_", "+/")
      case padded.size % 4
      when 0 then # already padded
      when 2 then padded += "=="
      when 3 then padded += "="
      else        return nil
      end
      begin
        Base64.decode_string(padded).bytes.map { |b| b.to_s(16, precision: 2) }.join
      rescue
        nil
      end
    end
  end
end
