require "uri"

module Celerite
  # Base error for all Celerite failures surfaced to the CLI.
  #
  # Status codes mirror `Bundler::Error#status_code` at the pinned revision
  # (see docs/compat-matrix/cli-commands.md).
  class Error < Exception
    def status_code : Int32
      1
    end

    # Exception-path errors render through the friendly-errors pipeline,
    # which word-wraps the message at the terminal width (Thor parity).
    def wrap? : Bool
      false
    end
  end

  # Raised for user-facing CLI usage mistakes (unknown command, bad flags).
  # Thor::Error maps to exit code 15.
  class UsageError < Error
    def status_code : Int32
      15
    end
  end

  # `Bundler::InvalidOption` (raised by `CLI::Clean#require_path_or_force` and
  # friends): friendly-errors prints the message word-wrapped at the terminal
  # width and exits 15.
  class InvalidOptionError < UsageError
    def wrap? : Bool
      true
    end
  end

  # `Bundler::RemovedError` (`shared_helpers.rb#feature_removed!`): the message
  # already carries the `[REMOVED] ` prefix and the status code is 9.
  class RemovedError < Error
    def status_code : Int32
      9
    end
  end

  # `Bundler::Settings::Path#validate!` (settings.rb L287-297): a custom `path`
  # cannot be combined with system gems. The reference raises `InvalidOption`,
  # which friendly-errors prints word-wrapped at the terminal width.
  class PathConflictError < Error
    def status_code : Int32
      15
    end

    def wrap? : Bool
      true
    end
  end

  # Raised when an operation has no native implementation yet; the CLI reports
  # the engine explicitly instead of silently degrading (architecture §2.3).
  class UnsupportedCommandError < Error
  end

  # bundler/errors.rb:20 (`GemfileError < BundlerError`, `status_code(4)`).
  # `friendly_errors.rb:31-36` renders every BundlerError through
  # `ui.error error.message, wrap: true`, so the message is word-wrapped at the
  # terminal width: `bundle remove <unknown>` prints the three-line form
  # measured from the 4.0.24 oracle.
  class GemfileError < Error
    def status_code : Int32
      4
    end

    def wrap? : Bool
      true
    end
  end

  # bundler/errors.rb:32 (`PathError < BundlerError`, status 13). Raised when a
  # `path:`/`--path` source directory is missing or not a directory
  # (source/path.rb:198-204); the message is word-wrapped by friendly errors.
  class PathError < Error
    def status_code : Int32
      13
    end

    def wrap? : Bool
      true
    end
  end

  # bundler/dsl.rb:542-640 (`DSLError < GemfileError`). The reference frames the
  # offending DSL line between `#  from <path>:<line>` markers and subtracts one
  # from the trace line number, so the marker quotes line `n+1` while the
  # enclosing context is rendered around index `n`. `message` is rstripped
  # because Thor's `say` rstrips before writing the single trailing newline
  # (`bundler/vendor/thor/lib/thor/shell/basic.rb`), and friendly-errors prints
  # DSLErrors unwrapped (`bundler/friendly_errors.rb:26-27`).
  class DSLError < GemfileError
    getter description : String
    getter dsl_path : String
    getter contents : String
    getter line_number : Int32

    def initialize(@description : String, @dsl_path : String, @contents : String, @line_number : Int32)
      super(nil)
    end

    # `friendly_errors.rb:26-27` prints a DSLError's already-framed message
    # verbatim (the indentation is load-bearing), so it opts out of the
    # BundlerError word-wrapping inherited from GemfileError.
    def wrap? : Bool
      false
    end

    def message : String
      indent = " #  "
      indicator = " >  "
      build = String::Builder.new
      build << "\n[!] " << @description << ". Bundler cannot continue.\n"

      lines = @contents.lines(chomp: false)
      return build.to_s.rstrip if @line_number < 0 || lines.empty?

      # The reference derives the frame's array index from the rendered trace
      # line (`"<dsl_path>:<n>"`), and the two profiles derive it differently:
      # 4.x regex-scans for the trailing `:<digits>` (`dsl.rb:611`), while 2.7.x
      # uses `trace_line.split(":")[1].to_i - 1` (`dsl.rb:611` of that tree).
      # On Windows every absolute path starts with a drive colon, so the 2.7.x
      # split picks the path segment instead of the line number: `to_i` yields
      # 0 and the index becomes -1, which Ruby then resolves as the *last*
      # line.  Reproducing that (rather than the 4.x form) is what makes the
      # 2.7.2 profile frame a single duplicated line, e.g.
      # ` #   >  gem "x", "= 1.0" #  gem "x", "= 1.0"`.
      trace_line = "#{@dsl_path}:#{@line_number + 1}"
      frame_index = if profile_2_x?
                      parts = trace_line.split(":")
                      ((parts.size > 1 ? (parts[1].to_i? || 0) : 0) - 1)
                    else
                      @line_number
                    end
      first_line = frame_index.zero?
      last_line = frame_index == lines.size - 1

      build << "\n"
      build << "#{indent}from #{trace_line}\n"
      build << "#{indent}-------------------------------------------\n"
      # `lines(chomp: false)` keeps each line's terminator, so the trailing-newline
      # bookkeeping mirrors `m << "\n" unless m.end_with?("\n")` without re-reading
      # the builder (String::Builder#to_s may only be called once).
      ends_with_newline = true
      unless first_line
        if previous = ruby_line_at(lines, frame_index - 1)
          build << "#{indent}#{previous}"
          ends_with_newline = previous.ends_with?('\n')
        else
          # Ruby interpolates `nil` into the indented marker, leaving the
          # indent alone (dsl.rb:623 `unless first_line`).
          build << indent
          ends_with_newline = false
        end
      end
      if line = ruby_line_at(lines, frame_index)
        build << "#{indicator}#{line}"
        ends_with_newline = line.ends_with?('\n')
      end
      unless last_line
        if following = ruby_line_at(lines, frame_index + 1)
          build << "#{indent}#{following}"
          ends_with_newline = following.ends_with?('\n')
        else
          build << indent
          ends_with_newline = false
        end
      end
      build << "\n" unless ends_with_newline
      build << "#{indent}-------------------------------------------\n"
      build.to_s.rstrip
    end

    # Ruby's `Array#[]`: a negative index counts from the end and out-of-range
    # reads yield nil instead of raising.
    private def ruby_line_at(lines : Array(String), index : Int32) : String?
      actual = index < 0 ? index + lines.size : index
      return nil if actual < 0 || actual >= lines.size
      lines[actual]
    end

    # `CELERITE_PROFILE_BUNDLER_VERSION` selects the emulated reference tree
    # (default 4.0.24, matching Commands.bundle_profile_version).
    private def profile_2_x? : Bool
      (Celerite::Profile.bundler_version).starts_with?("2.")
    end
  end

  # Raised when input violates the RubyGems version grammar (mirrors Ruby's
  # ArgumentError from Gem::Version.new).
  class VersionError < Error
  end

  # Raised when a requirement string is malformed (mirrors
  # Gem::Requirement::BadRequirementError).
  class BadRequirementError < Error
  end

  # Bundler::SolveFailure — dependency resolution failure.
  class SolveFailureError < Error
    def status_code : Int32
      6
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::GemNotFound.
  class GemNotFoundError < Error
    def status_code : Int32
      7
    end

    def wrap? : Bool
      true
    end
  end

  # `errors.rb:264-275` (`IncorrectLockfileDependencies < BundlerError`,
  # `status_code(41)`): the lockfile records different dependencies than the
  # spec materialized from the index. Raised from `lazy_specification.rb:259-270`
  # and repaired by `definition.rb:699-708` unless frozen.
  class IncorrectLockfileDependenciesError < Error
    def status_code : Int32
      41
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::GitError — a `git` subprocess failed to run or reported failure.
  class GitError < Error
    def status_code : Int32
      11
    end

    def wrap? : Bool
      true
    end
  end

  # Raised when a Gemfile cannot be located (mirrors Bundler::GemfileNotFound).
  #
  # friendly_errors.rb:35 renders every `BundlerError` through
  # `Bundler.ui.error message, wrap: true`, and ui/shell.rb:167-169 word-wraps at
  # the terminal width (80 when stdout is not a terminal). A long expanded path
  # therefore breaks at the space before `not found`, so the width has to be
  # part of the contract, not an afterthought.
  class GemfileNotFound < Error
    def status_code : Int32
      10
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::ProductionError — frozen-mode validation failures.
  class ProductionError < Error
    def status_code : Int32
      16
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::AuthenticationRequiredError (fetcher.rb:45-52, status 17):
  # the source answered 401 and no usable credentials were supplied. The
  # message names the host (not the full URL) and the BUNDLE_* key the user
  # would have to set, matching the reference's `Settings.key_for(host)`.
  class AuthenticationRequiredError < Error
    getter host : String

    def initialize(@host : String)
      super("Authentication is required for #{@host}.\n" \
            "Please supply credentials for this source. You can do this by running:\n" \
            "`bundle config set --global #{@host} username:password`\n" \
            "or by storing the credentials in the `#{Config.key_for(@host)}` environment variable")
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::BadAuthenticationError (fetcher.rb:54-58, status 17):
  # credentials were sent but the source still answered 401.
  class BadAuthenticationError < Error
    getter host : String

    def initialize(@host : String)
      super("Bad username or password for #{@host}.\n" \
            "Please double-check your credentials and correct them.")
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::AuthenticationForbiddenError (fetcher.rb:67-72, status
  # 17): the source answered 403. The reference raises it from two places with
  # different subjects — `fetcher/index.rb:18` passes `remote_uri` (the full
  # source URI, trailing slash included) while `fetcher/downloader.rb:73`
  # passes `uri.host` — so call sites format accordingly.
  class AuthenticationForbiddenError < Error
    getter host : String

    def initialize(@host : String)
      super("Access token could not be authenticated for #{@host}.\n" \
            "Make sure it's valid and has the necessary scopes configured.")
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::PermissionError (errors.rb:94-128, status 23): a filesystem
  # operation was denied. The reference raises this from
  # `SharedHelpers#filesystem_access` (shared_helpers.rb:105-127) and the lock
  # writer wraps the write in it (definition.rb:436-442). Most filesystem
  # errors subclass this and only replace the closing sentence; `action` is the
  # `filesystem_access` action (:read/:write/:create/:executable) and `:create`
  # names the parent folder because creating a file needs write access to it.
  class PermissionError < Error
    getter path : String
    getter permission_type : Symbol

    def initialize(path : String, @permission_type : Symbol = :write)
      @path = path.gsub('\\', "/")
      super(message)
    end

    protected def action_phrase : String
      case permission_type
      when :read       then "read from"
      when :write      then "write to"
      when :executable then "execute"
      when :exec       then "execute"
      else                  permission_type.to_s
      end
    end

    protected def permission_description : String
      if permission_type == :create
        "executable permissions for all parent directories and write permissions for `#{parent_folder}`"
      else
        "#{permission_type} permissions for that path"
      end
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. It is likely that you need to grant #{permission_description}."
    end

    def message : String
      default_message
    end

    def parent_folder : String
      File.dirname(path)
    end

    def status_code : Int32
      23
    end

    def wrap? : Bool
      true
    end
  end

  # bundler/errors.rb:156-164. The reference concatenates "try" and
  # "the operation again." without a space, so the message really says
  # "trythe"; kept verbatim for parity.
  class TemporaryResourceError < PermissionError
    def status_code : Int32
      26
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. Some resource was temporarily unavailable. It's suggested that you trythe operation again."
    end
  end

  # bundler/errors.rb:166-173 (a BundlerError, not a PermissionError: the
  # message carries no path/action).
  class VirtualProtocolError < Error
    def initialize
      super(nil)
    end

    def status_code : Int32
      27
    end

    def message : String
      "There was an error relating to virtualization and file access. It is likely that you need to grant access to or mount some file system correctly."
    end

    def wrap? : Bool
      true
    end
  end

  # bundler/errors.rb:175-181.
  class OperationNotSupportedError < PermissionError
    def status_code : Int32
      28
    end

    protected def default_message : String
      "Attempting to #{action_phrase} `#{path}` is unsupported by your OS."
    end
  end

  # bundler/errors.rb:183-190.
  class NoSpaceOnDeviceError < PermissionError
    def status_code : Int32
      31
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. There was insufficient space remaining on the device."
    end
  end

  # bundler/errors.rb:192-199.
  class ReadOnlyFileSystemError < PermissionError
    def status_code : Int32
      42
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. File system is read-only."
    end
  end

  # bundler/errors.rb:201-208.
  class OperationNotPermittedError < PermissionError
    def status_code : Int32
      43
    end

    protected def default_message : String
      "There was an error while trying to #{action_phrase} `#{path}`. Underlying OS system call raised an EPERM error."
    end
  end

  # bundler/errors.rb:210-219.
  class GenericSystemCallError < Error
    getter underlying_error : Exception

    def initialize(message : String, @underlying_error : Exception)
      super(message)
    end

    def message : String
      "#{super}\nThe underlying system error is #{underlying_error.class}: #{underlying_error}"
    end

    def status_code : Int32
      32
    end

    def wrap? : Bool
      true
    end
  end

  # Raised when a command needs the lockfile but the bundle has never been
  # installed (mirrors Bundler::GemfileLockNotFound, status 22).
  class GemfileLockNotFound < Error
    def status_code : Int32
      22
    end

    def wrap? : Bool
      true
    end
  end

  # Raised for lockfile parse/validation failures (mirrors Bundler::LockfileError).
  class LockfileError < Error
    def status_code : Int32
      20
    end

    def wrap? : Bool
      true
    end
  end

  # Raised when the running Ruby does not satisfy the Gemfile/lockfile Ruby
  # requirement (mirrors Bundler::RubyVersionMismatch).
  class RubyVersionMismatch < Error
    def status_code : Int32
      18
    end
  end

  # Raised when a download fails due to too many redirects or other
  # transport-level failures (mirrors Bundler::HTTPError).
  class DownloadError < Error
    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::NetworkDownError (an HTTPError, exit 17): the connection
  # could not be established at all. The reference labels the host from the
  # request URI and keeps `:port` only when the URL spells out a non-default
  # port (bundler/fetcher/downloader.rb:96-103).
  class NetworkDownError < Error
    # The original socket/DNS error, kept for diagnostics (never swallowed).
    getter socket_error : Exception?

    def initialize(message : String, @socket_error : Exception? = nil)
      super(message)
    end

    def self.message_for(uri : URI) : String
      host = uri.host || "unknown host"
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
      host_port = "#{host}:#{port}"
      host = host_port if uri.to_s.includes?(host_port)
      "Could not reach host #{host}. Check your network connection and try again."
    end

    def self.for(uri : URI, socket_error : Exception? = nil) : NetworkDownError
      new(message_for(uri), socket_error)
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # Bundler::Fetcher::CertificateFailureError (an HTTPError, exit 17): the TLS
  # handshake could not verify the peer certificate. Message and layout mirror
  # bundler/fetcher.rb:25-34 verbatim (newline after the URI). Bundler filters
  # credentials with URICredentialsFilter; this port has no equivalent helper,
  # so `display_uri` drops userinfo instead of printing secrets.
  class CertificateFailureError < Error
    # The original OpenSSL error, kept for diagnostics (never swallowed).
    getter ssl_error : Exception?

    def initialize(message : String, @ssl_error : Exception? = nil)
      super(message)
    end

    def self.message_for(uri : URI) : String
      "Could not verify the SSL certificate for #{display_uri(uri)}.\n" \
      "There is a chance you are experiencing a man-in-the-middle attack, but most " \
      "likely your system doesn't have the CA certificates needed for verification. " \
      "For information about OpenSSL certificates, see " \
      "https://railsapps.github.io/openssl-certificate-verify-failed.html."
    end

    def self.for(uri : URI, ssl_error : Exception? = nil) : CertificateFailureError
      new(message_for(uri), ssl_error)
    end

    def self.display_uri(uri : URI) : String
      return uri.to_s if uri.user.nil? && uri.password.nil?
      host = uri.host || ""
      port = uri.port ? ":#{uri.port}" : ""
      query = uri.query ? "?#{uri.query}" : ""
      "#{uri.scheme}://#{host}#{port}#{uri.path}#{query}"
    end

    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end

  # A GEM source that cannot serve its legacy index. The reference always
  # fetches `<remote>specs.4.8.gz` for a `file:` source — such remotes never
  # use the compact index (`fetcher.rb:271-280`) — retries that read three
  # times and then reports the wrapped message below
  # (`fetcher/index.rb:8-22`, `retry.rb#fail_attempt`).
  class SourceIndexFetchError < Error
    # `display_uri` of the source that could not be fetched (trailing slash
    # included, matching the reference's `remote_uri.to_s`).
    getter remote : String

    def initialize(message : String, @remote : String)
      super(message)
    end

    def self.message_for(remote : String, local_path : String) : String
      "Could not fetch specs from #{remote} due to underlying error " \
      "<Errno::ENOENT: No such file or directory @ rb_sysopen - #{local_path} " \
      "(#{remote}specs.4.8.gz)>"
    end

    # The reference re-raises the `Gem::RemoteFetcher::FetchError` as
    # `Bundler::HTTPError`, whose status code is 17.
    def status_code : Int32
      17
    end

    def wrap? : Bool
      true
    end
  end
end
