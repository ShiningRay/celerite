require "./spec_helper"

# Regression: Commands.install/Commands.update assigned `lock` inside the
# `begin` body, so an early failure (e.g. a Gemfile the bridge cannot parse)
# left `lock` unassigned and the `ensure` raised NilAssertionError via
# `lock.not_nil!.close`, masking the real error. The lock is now nullable and
# closed with `try`; the original error must surface intact.
describe "install/update early-failure unmasking" do
  it "reports the real Gemfile parse error instead of NilAssertionError" do
    previous = ENV["CELERITE_BRIDGE_SERVER"]?
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    begin
      with_project({"Gemfile" => "gem \"rake\", "}) do
        status, _out, err = run_cli(["install"])
        status.should eq(1)
        err.should contain("There was an error parsing `Gemfile`")
        err.should_not contain("Nil assertion failed")
        err.should_not contain("internal error")
      end
    ensure
      if previous
        ENV["CELERITE_BRIDGE_SERVER"] = previous
      else
        ENV.delete("CELERITE_BRIDGE_SERVER")
      end
    end
  end
end
