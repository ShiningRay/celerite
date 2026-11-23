require "./spec_helper"

# Reference anchor: bundler-4.0.24 lib/bundler/uri_credentials_filter.rb is the
# helper every `Fetching ... from <uri>` progress line goes through. The helper
# itself keeps `user@host` and only drops the password, but 4.0.24's observed
# output for `source "http://user:pass@host/"` renders the bare origin
# (`Fetching gem metadata from http://127.0.0.1:8931/.`), so celerite strips the
# whole userinfo section to stay byte-identical with the reference output.
private def filtered(remote : String) : String
  Celerite::URICredentialsFilter.credential_filtered_uri(remote)
end

describe Celerite::URICredentialsFilter do
  it "leaves a source without userinfo untouched" do
    filtered("http://127.0.0.1:8765/").should eq("http://127.0.0.1:8765/")
    filtered("https://gems.example.com/private/?a=1").should eq("https://gems.example.com/private/?a=1")
    filtered("file:///tmp/index").should eq("file:///tmp/index")
  end

  it "strips user and password from a source URI" do
    filtered("http://user:pass@127.0.0.1:8931/").should eq("http://127.0.0.1:8931/")
  end

  it "strips a user-only userinfo and keeps path and query" do
    filtered("https://user@gems.example.com/private/?token=1").should eq("https://gems.example.com/private/?token=1")
  end

  it "returns the input unchanged when it cannot be parsed" do
    filtered("http://user:pass@host:notaport/").should eq("http://user:pass@host:notaport/")
  end

  it "accepts a pre-parsed URI" do
    Celerite::URICredentialsFilter.credential_filtered_uri(URI.parse("http://user:pass@host:9000/a"))
      .should eq("http://host:9000/a")
  end
end
