require "./spec_helper"

# Reference: bundler/shared_helpers.rb:105-127 `filesystem_access` maps a set
# of Errno values to dedicated errors (statuses from bundler/errors.rb).
private def fs_error(errno : Errno) : File::Error
  File::Error.from_os_error("boom", errno, file: "C:\\tmp\\f")
end

private def map_errno(errno : Errno, action : Symbol = :write) : Celerite::Error?
  Celerite::FilesystemErrors.map(fs_error(errno), action)
end

describe "M7(5) filesystem error mapping" do
  it "maps EAGAIN to TemporaryResourceError (26) with the reference wording" do
    mapped = map_errno(Errno::EAGAIN)
    mapped.should be_a(Celerite::TemporaryResourceError)
    error = mapped.not_nil!
    error.status_code.should eq(26)
    error.wrap?.should be_true
    # Reference errors.rb:156-164 has the missing-space typo "trythe".
    error.message.should eq(
      "There was an error while trying to write to `C:/tmp/f`. " \
      "Some resource was temporarily unavailable. It's suggested that you trythe operation again."
    )
    error.should be_a(Celerite::PermissionError)
  end

  {% unless flag?(:win32) %}
    it "maps EPROTO to VirtualProtocolError (27) without path" do
      mapped = map_errno(Errno::EPROTO)
      mapped.should be_a(Celerite::VirtualProtocolError)
      error = mapped.not_nil!
      error.status_code.should eq(27)
      error.wrap?.should be_true
      error.message.should eq(
        "There was an error relating to virtualization and file access. " \
        "It is likely that you need to grant access to or mount some file system correctly."
      )
    end
  {% end %}

  it "maps ENOSPC to NoSpaceOnDeviceError (31)" do
    mapped = map_errno(Errno::ENOSPC)
    mapped.should be_a(Celerite::NoSpaceOnDeviceError)
    error = mapped.not_nil!
    error.status_code.should eq(31)
    error.message.should eq(
      "There was an error while trying to write to `C:/tmp/f`. " \
      "There was insufficient space remaining on the device."
    )
  end

  {% unless flag?(:win32) %}
    it "maps EOPNOTSUPP to OperationNotSupportedError (28)" do
      mapped = map_errno(Errno::EOPNOTSUPP)
      mapped.should be_a(Celerite::OperationNotSupportedError)
      error = mapped.not_nil!
      error.status_code.should eq(28)
      error.message.should eq("Attempting to write to `C:/tmp/f` is unsupported by your OS.")
    end
  {% end %}

  {% if flag?(:win32) %}
    it "maps Windows ERROR_DISK_FULL to NoSpaceOnDeviceError (31)" do
      error = File::Error.from_os_error("boom", WinError::ERROR_DISK_FULL, file: "C:\\tmp\\f")
      mapped = Celerite::FilesystemErrors.map(error, :write)
      mapped.should be_a(Celerite::NoSpaceOnDeviceError)
      mapped.not_nil!.status_code.should eq(31)
    end

    it "maps Windows ERROR_WRITE_PROTECT to ReadOnlyFileSystemError (42)" do
      error = File::Error.from_os_error("boom", WinError::ERROR_WRITE_PROTECT, file: "C:\\tmp\\f")
      mapped = Celerite::FilesystemErrors.map(error, :write)
      mapped.should be_a(Celerite::ReadOnlyFileSystemError)
      mapped.not_nil!.status_code.should eq(42)
    end
  {% end %}

  it "maps EPERM to OperationNotPermittedError (43)" do
    mapped = map_errno(Errno::EPERM)
    mapped.should be_a(Celerite::OperationNotPermittedError)
    error = mapped.not_nil!
    error.status_code.should eq(43)
    error.message.should eq(
      "There was an error while trying to write to `C:/tmp/f`. " \
      "Underlying OS system call raised an EPERM error."
    )
  end

  it "maps EROFS to ReadOnlyFileSystemError (42)" do
    mapped = map_errno(Errno::EROFS)
    mapped.should be_a(Celerite::ReadOnlyFileSystemError)
    error = mapped.not_nil!
    error.status_code.should eq(42)
    error.message.should eq(
      "There was an error while trying to write to `C:/tmp/f`. File system is read-only."
    )
  end

  it "keeps EEXIST and ENOENT bubbling unchanged" do
    map_errno(Errno::EEXIST).should be_nil
    map_errno(Errno::ENOENT).should be_nil
    Celerite::FilesystemErrors.map(
      File::Error.from_os_error("boom", Errno::EEXIST, file: "x"), :create
    ).should be_nil
  end

  it "maps other system errors to GenericSystemCallError (32)" do
    mapped = map_errno(Errno::EINVAL)
    mapped.should be_a(Celerite::GenericSystemCallError)
    error = mapped.not_nil!
    error.status_code.should eq(32)
    error.wrap?.should be_true
    error.message.not_nil!.should contain("There was an error creating `C:/tmp/f`.")
    error.message.not_nil!.should contain("The underlying system error is File::Error:")
  end

  it "maps EACCES to PermissionError (23) like before" do
    mapped = map_errno(Errno::EACCES)
    mapped.should be_a(Celerite::PermissionError)
    error = mapped.not_nil!
    error.status_code.should eq(23)
    error.message.should eq(
      "There was an error while trying to write to `C:/tmp/f`. " \
      "It is likely that you need to grant write permissions for that path."
    )
  end

  it "keeps the existing :create permission description" do
    error = Celerite::PermissionError.new("C:\\tmp\\f", :create)
    error.message.not_nil!.should contain(
      "executable permissions for all parent directories and write permissions for `C:/tmp`"
    )
  end
end
