require "./errors"

module Celerite
  # Raised when a gem install fails mid-way (native extension build errors are
  # the main path). Mirrors `Bundler::InstallError` (bundler/errors.rb:21):
  # status 5 and a word-wrapped message.
  class InstallError < Error
    def status_code : Int32
      5
    end

    def wrap? : Bool
      true
    end
  end
end
