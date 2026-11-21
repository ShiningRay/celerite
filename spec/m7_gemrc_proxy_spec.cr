require "./spec_helper"

# `~/.gemrc`'s `:http_proxy` is the first proxy source the reference consults
# (`fetcher.rb:262`, `:313-316` reads `Gem.configuration[:http_proxy]`), and a
# `:no_proxy` value disables proxying outright. The string-key form and the
# environment fallback are covered too.
private def with_gemrc_env(dir : String, gemrc : String?, &)
  sandbox = File.join(".tmp-scratch", "spec-gemrc", dir)
  FileUtils.rm_rf(sandbox)
  FileUtils.mkdir_p(sandbox)
  home = File.join(sandbox, "home")
  FileUtils.mkdir_p(home)
  unless gemrc.nil?
    File.write(File.join(home, ".gemrc"), gemrc)
  end
  saved = {} of String => String?
  %w[HOME USERPROFILE http_proxy HTTP_PROXY no_proxy NO_PROXY].each do |key|
    saved[key] = ENV[key]?
    ENV.delete(key)
  end
  ENV["HOME"] = File.expand_path(home)
  ENV["USERPROFILE"] = File.expand_path(home)
  saved_env = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("assets/bridge/server.rb")
  begin
    yield sandbox
  ensure
    saved.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    if saved_env.nil?
      ENV.delete("CELERITE_BRIDGE_SERVER")
    else
      ENV["CELERITE_BRIDGE_SERVER"] = saved_env
    end
  end
end

private def gemrc_config(gemrc : String?, key = "proxy") : String?
  with_gemrc_env("config-#{key}", gemrc) do
    config = Celerite::Config.new(File.expand_path(".tmp-scratch/spec-gemrc"))
    Celerite::Proxy.resolve(config).try(&.uri.to_s)
  end
end

describe "gemrc proxy" do
  it "uses the gemrc :http_proxy entry" do
    gemrc_config("---\n:http_proxy: http://127.0.0.1:9\n").should eq("http://127.0.0.1:9")
  end

  it "accepts a plain string key" do
    gemrc_config("---\nhttp_proxy: http://127.0.0.1:8\n").should eq("http://127.0.0.1:8")
  end

  it "lets the gemrc win over the environment" do
    with_gemrc_env("precedence", "---\n:http_proxy: http://127.0.0.1:9\n") do
      ENV["http_proxy"] = "http://127.0.0.1:10"
      config = Celerite::Config.new(File.expand_path(".tmp-scratch/spec-gemrc"))
      Celerite::Proxy.resolve(config).try(&.uri.to_s).should eq("http://127.0.0.1:9")
    end
  end

  it "treats :no_proxy as proxy disabled even with http_proxy exported" do
    with_gemrc_env("noproxy", "---\n:http_proxy: :no_proxy\n") do
      ENV["http_proxy"] = "http://127.0.0.1:9"
      config = Celerite::Config.new(File.expand_path(".tmp-scratch/spec-gemrc"))
      Celerite::Proxy.resolve(config).should be_nil
    end
  end

  it "falls back to the environment without a gemrc" do
    with_gemrc_env("fallback", nil) do
      ENV["http_proxy"] = "http://127.0.0.1:10"
      config = Celerite::Config.new(File.expand_path(".tmp-scratch/spec-gemrc"))
      Celerite::Proxy.resolve(config).try(&.uri.to_s).should eq("http://127.0.0.1:10")
    end
  end
end
