require "./spec_helper"

private def kv_checksum(raw : String) : String
  Celerite::Resolution.info_checksum_value(raw)
end

describe "Resolution.info_checksum_value" do
  it "passes raw hex through as sha256=<hex>" do
    hex = "7bcce2df62e91a80143592600e16583c273e98aab50ae40a9f6a2604bb3289a0"
    kv_checksum(hex).should eq("sha256=#{hex}")
  end

  it "downcases uppercase raw hex" do
    hex = "7BCCE2DF62E91A80143592600E16583C273E98AAB50AE40A9F6A2604BB3289A0"
    kv_checksum(hex).should eq("sha256=7bcce2df62e91a80143592600e16583c273e98aab50ae40a9f6a2604bb3289a0")
  end

  it "decodes raw base64 to hex" do
    b64 = Base64.strict_encode("\0" * 32)
    kv_checksum(b64).should eq("sha256=#{"00" * 32}")
  end

  it "passes sha256=<hex> through unchanged" do
    hex = "9ab6ea96ab479a5ff391196de73b5abf660926ea7e4c57cb1f35adf754f1d066"
    kv_checksum("sha256=#{hex}").should eq("sha256=#{hex}")
  end

  it "does not mangle raw hex into 96 chars (rubygems.org /info shape)" do
    hex = "7bcce2df62e91a80143592600e16583c273e98aab50ae40a9f6a2604bb3289a0"
    kv_checksum(hex).size.should eq(7 + 64)
  end
end
