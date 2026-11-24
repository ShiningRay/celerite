require "./spec_helper"

describe "spec environment isolation" do
  it "sets a key inside an example" do
    ENV["CELERITE_T257_ENV_PROBE"] = "leak"
    ENV["CELERITE_T257_ENV_PROBE"].should eq("leak")
  end

  it "restores the key before the next example" do
    ENV["CELERITE_T257_ENV_PROBE"]?.should be_nil
  end
end
