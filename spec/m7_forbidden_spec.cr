require "./spec_helper"
require "http/server"

# M7(5) 403 responses: the reference raises
# `Bundler::Fetcher::AuthenticationForbiddenError` from two places. A source
# that rejects the compact index with 403 falls back to the legacy index, whose
# fetch logs `Fetching source index from <remote>` and then reports the *full
# source URI* (fetcher/compact_index.rb L9-23, fetcher/index.rb L14-19,
# fetcher.rb L67-72).
private def with_forbidden_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def with_forbidden_env(dir : String, &)
  names = ["HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "BUNDLE_PATH"]
  saved = {} of String => String?
  names.each { |name| saved[name] = ENV[name]? }
  gem_home = File.join(dir, "gem-home")
  ENV["HOME"] = dir
  ENV["USERPROFILE"] = dir
  ENV["GEM_HOME"] = gem_home
  ENV["GEM_PATH"] = gem_home
  ENV.delete("BUNDLE_PATH")
  begin
    yield
  ensure
    saved.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def with_forbidden_server(&)
  server = HTTP::Server.new do |context|
    context.response.status_code = 403
    context.response.print ""
  end
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  begin
    yield address.port
  ensure
    server.close
  end
end

private def with_forbidden_server_401(&)
  server = HTTP::Server.new do |context|
    context.response.status_code = 401
    context.response.headers["WWW-Authenticate"] = "Basic realm=\"probe\""
    context.response.print ""
  end
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  begin
    yield address.port
  ensure
    server.close
  end
end

private def forbidden_message(port : Int32) : String
  "Access token could not be authenticated for http://127.0.0.1:#{port}/.\n" +
    "Make sure it's valid and has the necessary scopes configured.\n"
end

describe "M7(5) 403 responses" do
  it "reports AuthenticationForbiddenError with the source URI" do
    with_forbidden_bridge do
      with_forbidden_server do |port|
        gemfile = "source \"http://127.0.0.1:#{port}/\"\n\ngem \"json_pure\", \"2.6.0\"\n"
        with_project({"Gemfile" => gemfile}) do |dir|
          with_forbidden_env(dir) do
            code, out, err = run_cli(["install"])
            code.should eq(17)
            err.should_not contain("celerite internal error")
            err.should eq(forbidden_message(port))
            # The legacy fallback logs its own fetch line and a blank line.
            out.should eq("Fetching source index from http://127.0.0.1:#{port}/\n\n")
          end
        end
      end
    end
  end

  it "keeps 401 on the authentication-required message" do
    with_forbidden_bridge do
      with_forbidden_server_401 do |port|
        gemfile = "source \"http://127.0.0.1:#{port}/\"\n\ngem \"json_pure\", \"2.6.0\"\n"
        with_project({"Gemfile" => gemfile}) do |dir|
          with_forbidden_env(dir) do
            code, _out, err = run_cli(["install"])
            code.should eq(17)
            err.should contain("Authentication is required for 127.0.0.1.")
            err.should_not contain("Access token could not be authenticated")
          end
        end
      end
    end
  end
end
