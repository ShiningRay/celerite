module Celerite
  class Error < Exception
  end

  class UsageError < Error
  end

  class UnsupportedCommandError < Error
  end
end
