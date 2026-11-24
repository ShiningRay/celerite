require "./spec_helper"

private ENV_ISOLATION_WINDOWS = {{ flag?(:windows) }}

private def env_isolation_name(name : String) : String
  ENV_ISOLATION_WINDOWS ? name.downcase : name
end

SPEC_ENV_PATH_KEY   = ENV.keys.find { |key| env_isolation_name(key) == env_isolation_name("PATH") }.not_nil!
SPEC_ENV_PATH_VALUE = ENV[SPEC_ENV_PATH_KEY]

describe "spec environment isolation" do
  it "sets a key inside an example" do
    ENV["CELERITE_T257_ENV_PROBE"] = "leak"
    ENV["CELERITE_T257_ENV_PROBE"].should eq("leak")
  end

  it "restores the key before the next example" do
    ENV["CELERITE_T257_ENV_PROBE"]?.should be_nil
  end

  it "creates an alternate-case PATH inside a Windows example" do
    pending!("Windows environment keys are case-insensitive") unless ENV_ISOLATION_WINDOWS

    ENV.delete(SPEC_ENV_PATH_KEY)
    ENV["PATH"] = "t257-polluted-path"
    ENV["PATH"].should eq("t257-polluted-path")
  end

  it "restores one canonical PATH before the next example" do
    if ENV_ISOLATION_WINDOWS
      keys = ENV.keys.select { |key| env_isolation_name(key) == env_isolation_name("PATH") }
      keys.should eq([SPEC_ENV_PATH_KEY])
      ENV[SPEC_ENV_PATH_KEY].should eq(SPEC_ENV_PATH_VALUE)
    else
      ENV["PATH"].should eq(SPEC_ENV_PATH_VALUE)
    end
  end
end
