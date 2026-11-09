require "./spec_helper"

describe "ProcessLock across processes" do
  it "blocks a nonblocking lock in a different OS process" do
    dir = File.tempname("celerite-process-race", "dir")
    Dir.mkdir_p(dir)
    begin
      lock_path = File.join(dir, "bundler.lock")
      ready_path = File.join(dir, "ready")
      File.write(lock_path, "")
      holder = File.expand_path("fixtures/process_lock_holder.cr", __DIR__)
      process = Process.new(
        "crystal",
        ["run", holder, "--", lock_path, ready_path],
        input: :inherit, output: :inherit, error: :inherit,
      )

      begin
        ready = false
        300.times do
          if File.file?(ready_path)
            ready = true
            break
          end
          sleep 100.milliseconds
        end
        ready.should eq(true)

        contender = File.open(lock_path, "a+")
        begin
          expect_raises(IO::Error) { contender.flock_exclusive(false) }
        ensure
          contender.close
        end
      ensure
        # `crystal run` wraps the actual holder process; terminating the
        # compiler alone would orphan that child, so wait for the bounded
        # 3-second holder run to release the lock instead.
        process.wait
      end

      after = File.open(lock_path, "a+")
      begin
        after.flock_exclusive(false)
        after.flock_unlock
      ensure
        after.close
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
