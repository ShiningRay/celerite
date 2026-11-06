require "compress/gzip"
require "./errors"

module Celerite
  # Minimal tar reader covering the subset used inside .gem packages
  # (ustar/gnu regular files and directories). Long-name (gnu 'L') entries
  # and pax headers ('x'/'g') are handled for name purposes.
  module Tar
    class Error < Celerite::Error
    end

    struct Entry
      getter name : String
      getter size : Int64
      getter directory : Bool

      def initialize(@name : String, @size : Int64, @directory : Bool)
      end
    end

    # Iterates entries of a tar stream, yielding (Entry, data_io_or_nil).
    # File data is read fully into memory (gem payloads are modest and this
    # keeps the reader simple and seek-free).
    def self.each_entry(io : IO, & : Entry, IO? ->) : Nil
      loop do
        header = Bytes.new(512)
        read = read_full(io, header)
        break if read == 0

        if read < 512
          raise Error.new("truncated tar header (#{read} bytes)")
        end

        name = header_string(header, 0, 100)
        size_field = header_string(header, 124, 12)
        typeflag = header[156].chr
        prefix = header_string(header, 345, 155)
        link_or_long = header_string(header, 157, 100)

        break if name.empty? && size_field.empty?

        size = size_field.empty? ? 0_i64 : size_field.to_i64?(base: 8) || 0_i64

        case typeflag
        when 'L' # GNU long name: next entry's name
          data = Bytes.new(size)
          read_full(io, data)
          skip_padding(io, size)
          long_name = String.new(data).chomp('\0')
          long_name_ref = long_name
          each_entry_with_long_name(io, long_name_ref) do |entry, data_io|
            yield entry, data_io
          end
          next
        when 'x', 'g' # pax headers: skip
          skip_bytes(io, size)
          skip_padding(io, size)
          next
        end

        full_name = prefix.empty? ? name : "#{prefix}/#{name}"
        directory = typeflag == '5' || full_name.ends_with?("/")

        if directory
          yield Entry.new(full_name.chomp('/'), 0, true), nil
          next
        elsif typeflag == '0' || typeflag == '\0'
          if link_or_long.empty?
            data = Bytes.new(size)
            read_full(io, data)
            yield Entry.new(full_name, size, false), IO::Memory.new(data)
            skip_padding(io, size)
            next
          end
        end

        # unsupported entry types (links, devices): skip their data
        skip_bytes(io, size)
        skip_padding(io, size)
      end
    end

    private def self.each_entry_with_long_name(io : IO, long_name : String, & : Entry, IO? ->) : Nil
      header = Bytes.new(512)
      read = read_full(io, header)
      return if read < 512

      name = header_string(header, 0, 100)
      size_field = header_string(header, 124, 12)
      typeflag = header[156].chr
      size = size_field.empty? ? 0_i64 : size_field.to_i64?(base: 8) || 0_i64

      if typeflag == '0' || typeflag == '\0'
        data = Bytes.new(size)
        read_full(io, data)
        yield Entry.new(long_name, size, false), IO::Memory.new(data)
        skip_padding(io, size)
      else
        skip_bytes(io, size)
        skip_padding(io, size)
      end
    end

    def self.header_string(header : Bytes, offset : Int32, length : Int32) : String
      slice = header[offset, length]
      end_index = 0
      while end_index < length && slice[end_index] != 0
        end_index += 1
      end
      # strip trailing spaces (numeric fields are right-aligned)
      text = String.new(slice[0, end_index]).rstrip
      text
    end

    def self.read_full(io : IO, buffer : Bytes) : Int32
      total = 0
      while total < buffer.size
        read = io.read(buffer[total..])
        break if read == 0
        total += read
      end
      total
    end

    def self.skip_bytes(io : IO, size : Int64) : Nil
      remaining = size
      buffer = Bytes.new(8192)
      while remaining > 0
        read = io.read(buffer[0, Math.min(remaining, 8192)])
        break if read == 0
        remaining -= read
      end
    end

    def self.skip_padding(io : IO, size : Int64) : Nil
      padding = (512 - (size % 512)) % 512
      skip_bytes(io, padding) if padding > 0
    end

    # Iterates entries of a .tar.gz stream.
    def self.each_gzip_entry(io : IO, & : Entry, IO? ->) : Nil
      Compress::Gzip::Reader.open(io) do |reader|
        each_entry(reader) do |entry, data|
          yield entry, data
        end
      end
    end
  end
end
