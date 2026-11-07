require "openssl"
require "base64"
require "../errors"

module Celerite
  module CompactIndex
    SUPPORTED_DIGESTS = {"sha-256" => "SHA256"}

    class Error < Celerite::Error
    end

    class MismatchedChecksumError < Error
      def initialize(path : String, message : String)
        super("The checksum of /#{path} does not match the checksum provided by the server! Something is wrong. #{message}")
      end
    end

    class DigestMismatchError < Error
      getter calculated : Hash(String, String)
      getter expected : Hash(String, String)

      def initialize(@calculated : Hash(String, String), @expected : Hash(String, String))
        super("Calculated checksums #{calculated.inspect} did not match expected #{expected.inspect}.")
      end
    end

    # Write cache files in a way that is robust to concurrent modification:
    # data goes to a per-process temp file, digests are verified, then the
    # file is atomically renamed over the original (pinned contract:
    # `Bundler::CompactIndexClient::CacheFile`).
    class CacheFile
      def self.write(path : String, data : String, digests : Hash(String, String)? = nil) : Nil
        file = new(path)
        file.perform_write(data, digests)
      ensure
        file.try(&.close)
      end

      # Copies the original file into the temp file while digesting, appends
      # +tail+, verifies the combined digests, then atomically replaces the
      # original. Returns false when verification is impossible (no digests).
      def self.append(original_path : String, tail : String, expected : Hash(String, String)?) : Bool
        return false if expected.nil? || expected.empty?

        file = new(original_path)
        file.perform_append(tail, expected)
      ensure
        file.try(&.close)
      end

      def initialize(@original_path : String)
        @path = "#{original_path}.#{Process.pid}.#{rand(1 << 30)}.tmp"
      end

      def perform_write(data : String, expected : Hash(String, String)?) : Nil
        digests = build_digests(expected)
        bytes = data.to_slice
        digests.try(&.each_value(&.update(bytes)))
        File.open(@path, "wb") do |io|
          io.write(bytes)
        end
        verify!(digests, expected)
        File.rename(@path, @original_path)
      end

      def perform_append(tail : String, expected : Hash(String, String)?) : Bool
        digests = build_digests(expected)
        return false unless digests

        tail_bytes = tail.to_slice
        File.open(@original_path, "rb") do |src|
          File.open(@path, "wb") do |dst|
            buffer = Bytes.new(65_536)
            while (read = src.read(buffer)) > 0
              digests.each_value(&.update(buffer[0, read]))
              dst.write(buffer[0, read])
            end
            digests.each_value(&.update(tail_bytes))
            dst.write(tail_bytes)
          end
        end
        verify!(digests, expected)
        File.rename(@path, @original_path)
        true
      end

      private def build_digests(expected : Hash(String, String)?) : Hash(String, OpenSSL::Digest)?
        return nil if expected.nil? || expected.empty?

        expected.keys.map { |algo| {algo, OpenSSL::Digest.new(SUPPORTED_DIGESTS[algo])} }.to_h
      end

      private def verify!(digests : Hash(String, OpenSSL::Digest)?, expected : Hash(String, String)?) : Nil
        return unless expected && digests && !digests.empty?

        calculated = digests.transform_values { |d| Base64.encode(d.final).rstrip }
        unless expected.all? { |algo, value| calculated[algo]? == value }
          raise DigestMismatchError.new(calculated, expected)
        end
      end

      # Remove the temp file without replacing the original.
      def close : Nil
        File.delete(@path) if File.file?(@path)
      rescue File::NotFoundError
      end
    end
  end
end
