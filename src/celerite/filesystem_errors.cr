require "file"
require "./errors"

module Celerite
  # Reference `Bundler::SharedHelpers.filesystem_access`
  # (bundler-4.0.24/lib/bundler/shared_helpers.rb:105-127): map the OS error to
  # the matching Bundler error class, leaving EEXIST/ENOENT untouched.
  #
  # `Errno::EPROTO` / `Errno::EOPNOTSUPP` do not exist in Crystal's Windows
  # errno table, so those two branches are compiled only on POSIX hosts;
  # Windows exposes the same conditions through WinError values below.
  module FilesystemErrors
    def self.map(error : File::Error, action : Symbol = :write, path_override : String? = nil) : Celerite::Error?
      path = (path_override || error.target || "").gsub('\\', "/")

      # Crystal's dedicated subclass already narrows the common case.
      return PermissionError.new(path, action) if error.is_a?(File::AccessDeniedError)

      os = error.os_error
      if os.is_a?(Errno)
        # Reference: `raise` (bubble unchanged) for EEXIST/ENOENT.
        return nil if os == Errno::EEXIST || os == Errno::ENOENT
        return PermissionError.new(path, action) if os == Errno::EACCES
        return TemporaryResourceError.new(path, action) if os == Errno::EAGAIN
        return NoSpaceOnDeviceError.new(path, action) if os == Errno::ENOSPC
        return OperationNotPermittedError.new(path, action) if os == Errno::EPERM
        return ReadOnlyFileSystemError.new(path, action) if os == Errno::EROFS
        {% unless flag?(:win32) %}
          return VirtualProtocolError.new if os == Errno::EPROTO
          return OperationNotSupportedError.new(path, action) if os == Errno::EOPNOTSUPP
        {% end %}
      end

      {% if flag?(:win32) %}
        if os.is_a?(WinError)
          case os
          when WinError::ERROR_DISK_FULL, WinError::ERROR_HANDLE_DISK_FULL
            return NoSpaceOnDeviceError.new(path, action)
          when WinError::ERROR_WRITE_PROTECT
            return ReadOnlyFileSystemError.new(path, action)
          when WinError::ERROR_ACCESS_DENIED
            return PermissionError.new(path, action)
          end
        end
      {% end %}

      case error
      when File::NotFoundError, File::AlreadyExistsError
        return nil
      end

      verb = {:create, :write}.includes?(action) ? "creating" : "accessing"
      GenericSystemCallError.new("There was an error #{verb} `#{path}`.", error)
    end
  end
end
