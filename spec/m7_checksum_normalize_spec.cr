require "./spec_helper"

private def kv_hex : String
  (0...32).map { |i| i.to_s(16, precision: 2) }.join
end

private def kv_bytes : String
  kv_hex.scan(/../).map { |m| m[0].to_u8(16).chr }.join
end

private def kv_b64 : String
  Base64.strict_encode(kv_bytes)
end

describe "Celerite::Checksum.normalize_hex" do
  it "passes raw 64-char hex through, downcased" do
    Celerite::Checksum.normalize_hex(kv_hex.upcase).should eq(kv_hex)
  end

  it "decodes standard padded base64" do
    Celerite::Checksum.normalize_hex(kv_b64).should eq(kv_hex)
  end

  it "decodes url-safe unpadded base64" do
    url = kv_b64.tr("+/", "-_").sub(/=+$/, "")
    Celerite::Checksum.normalize_hex(url).should eq(kv_hex)
  end

  it "accepts the sha256= prefix on both shapes" do
    Celerite::Checksum.normalize_hex("sha256=#{kv_hex}").should eq(kv_hex)
    Celerite::Checksum.normalize_hex("sha256=#{kv_b64}").should eq(kv_hex)
  end

  it "returns nil for invalid input instead of mangling it" do
    Celerite::Checksum.normalize_hex("zzz").should be_nil
    Celerite::Checksum.normalize_hex("abc").should be_nil
    Celerite::Checksum.normalize_hex("").should be_nil
    Celerite::Checksum.normalize_hex("sha256=").should be_nil
    Celerite::Checksum.normalize_hex("a" * 45).should be_nil
  end

  it "yields identical hex for the same gem in hex and base64 shapes" do
    Celerite::Checksum.normalize_hex(kv_hex).should eq(Celerite::Checksum.normalize_hex(kv_b64))
  end
end

describe "Celerite::Resolution.info_checksum_value" do
  it "renders sha256=<hex> for every accepted input shape" do
    expected = "sha256=#{kv_hex}"
    Celerite::Resolution.info_checksum_value(kv_hex).should eq(expected)
    Celerite::Resolution.info_checksum_value(kv_b64).should eq(expected)
    Celerite::Resolution.info_checksum_value("sha256=#{kv_hex}").should eq(expected)
  end

  it "raises a readable error on invalid input" do
    expect_raises(ArgumentError, "invalid compact-index checksum") do
      Celerite::Resolution.info_checksum_value("zzz")
    end
  end
end
