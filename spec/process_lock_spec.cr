require "./spec_helper"
require "../src/celerite/cli"

describe Celerite::Commands::ProcessLock do
  it "excludes a second nonblocking lock attempt until released" do
    dir = File.tempname("celerite-process-lock", "dir")
    Dir.mkdir_p(dir)
    begin
      held = Celerite::Commands::ProcessLock.lock(dir)
      contender = File.open(File.join(dir, "bundler.lock"), "a+")
      begin
        expect_raises(IO::Error) { contender.flock_exclusive(false) }

        held.close

        locked_after_release = false
        begin
          contender.flock_exclusive(false)
          locked_after_release = true
          contender.flock_unlock
        rescue IO::Error
          locked_after_release = false
        end
        locked_after_release.should eq(true)
      ensure
        contender.close
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
