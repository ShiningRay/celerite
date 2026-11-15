require "http/server"
require "./spec_helper"

# Reference mapping (bundler-4.0.24 fetcher/downloader.rb:70-73): a 401 with no
# credentials is AuthenticationRequiredError, a 401 after credentials were sent
# is BadAuthenticationError, and (measured oracle) a 403 without
# `WWW-Authenticate` also surfaces as AuthenticationRequiredError. All are
# HTTPError subclasses: status 17, wrap: true.
private def with_auth_status_server(status : Int32, &)
  server = HTTP::Server.new do |context|
    context.response.status_code = status
    context.response.print "denied"
  end
  address = server.bind_tcp("127.0.0.1", 0)
  port = address.port
  spawn { server.listen }
  begin
    yield port
  ensure
    server.close
  end
end

# The bridge env var must be set while the example *runs*, not while the
# describe block is merely registered.
private def with_auth_bridge(&)
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

private def auth_gemfile(port : Int32) : String
  %(source "http://127.0.0.1:#{port}/"\n\ngem "json_pure"\n)
end

# The differential fixtures (lock-platform-variant, lock-path-absolute-relative)
# prove 4.0.24 prints "Writing lockfile to ..." before it fetches the index, so
# the command does emit this one line before an authentication failure. Only
# the rest of stdout stays empty.
private def auth_stdout(dir : String) : String
  "Writing lockfile to #{File.expand_path(File.join(dir, "Gemfile.lock")).gsub(/\\/, "/")}\n"
end

private def auth_required_message : String
  "Authentication is required for 127.0.0.1.\n" \
  "Please supply credentials for this source. You can do this by running:\n" \
  "`bundle config set --global 127.0.0.1 username:password`\n" \
  "or by storing the credentials in the `BUNDLE_127__0__0__1` environment variable\n"
end

private def bad_credentials_message : String
  "Bad username or password for 127.0.0.1.\n" \
  "Please double-check your credentials and correct them.\n"
end

describe "private source authentication errors" do
  it "maps a credential-less 401 to AuthenticationRequiredError text and exit 17" do
    with_auth_bridge do
      with_auth_status_server(401) do |port|
        with_project({"Gemfile" => auth_gemfile(port)}) do |dir|
          code, out, err = run_cli(["lock"])
          code.should eq(17)
          out.should eq(auth_stdout(dir))
          err.should eq(auth_required_message)
        end
      end
    end
  end

  it "maps a 401 after wrong credentials to BadAuthenticationError text and exit 17" do
    with_auth_bridge do
      with_auth_status_server(401) do |port|
        with_project({"Gemfile" => auth_gemfile(port)}) do |dir|
          Dir.mkdir_p(File.join(dir, ".bundle"))
          File.write(File.join(dir, ".bundle", "config"),
            %(BUNDLE_HTTP://127.0.0.1:#{port}/: "alice:wrong"\n))
          code, out, err = run_cli(["lock"])
          code.should eq(17)
          out.should eq(auth_stdout(dir))
          err.should eq(bad_credentials_message)
        end
      end
    end
  end

  it "maps a 403 without WWW-Authenticate to the same AuthenticationRequiredError text" do
    with_auth_bridge do
      with_auth_status_server(403) do |port|
        with_project({"Gemfile" => auth_gemfile(port)}) do |dir|
          code, out, err = run_cli(["lock"])
          code.should eq(17)
          out.should eq(auth_stdout(dir))
          err.should eq(auth_required_message)
        end
      end
    end
  end

  it "raises the same errors from the gem downloader" do
    with_auth_status_server(401) do |port|
      with_project({} of String => String) do |dir|
        remote = "http://127.0.0.1:#{port}/"
        cache_root = File.join(dir, "cache")
        anon = Celerite::Downloader.new(remote, cache_root, 0)
        expect_raises(Celerite::AuthenticationRequiredError, "Authentication is required for 127.0.0.1.") do
          anon.fetch("json_pure", "2.8.1", nil, nil)
        end
        with_creds = Celerite::Downloader.new(remote, cache_root, 0, credentials: {"alice", "wrong"})
        expect_raises(Celerite::BadAuthenticationError, "Bad username or password for 127.0.0.1.") do
          with_creds.fetch("json_pure", "2.8.1", nil, nil)
        end
      end
    end
  end
end
