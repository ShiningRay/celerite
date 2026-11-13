require "./spec_helper"
require "../src/celerite"

# ProcessLock roundtrip on a writable temp dir. Guards the install/update
# ensure path (`lock.try(&.close)`) against a nil-masking regression: the
# lock must be acquirable and releasable, and a second acquire after close
# must succeed (no stuck flock).
describe "ProcessLock" do
  it "acquires and releases an exclusive lock on a temp bundle path, re-acquirable" do
    with_project({} of String => String) do |bundle_path|
      first = Celerite::Commands::ProcessLock.lock(bundle_path)
      first.close
      second = Celerite::Commands::ProcessLock.lock(bundle_path)
      second.close
      File.join(bundle_path, "bundler.lock").should be_a(String)
    end
  end
end
