require "./spec_helper"
require "http/server"

# M7(5): a source whose *metadata* is readable but whose gem downloads answer
# 403. RubyGems' own downloader (`RubygemsIntegration#download_gem`,
# `rubygems_integration.rb:379`) retries three times through `Bundler::Retry`
# and then raises `Bundler::HTTPError`, so the install fails with status 5:
#
#   Retrying download gem from <source> due to error (2/4): \
#     Gem::RemoteFetcher::FetchError bad response Forbidden 403 (<url>)
#   … (3/4, 4/4)
#   Bundler::HTTPError: Could not download gem from <source> due to underlying
#     error <bad response Forbidden 403 (<url>)>
#   An error occurred while installing <gem> (<version>), and Bundler cannot
#     continue.
#   In Gemfile:
#     <gem>
#
# `Bundler::Retry#fail_attempt` writes a blank line to stdout before each
# warning (`retry.rb:60-64`), which is why the `Fetching <gem>` line ends up
# followed by one blank line per attempt.
private def with_download_forbidden_bridge(&)
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

private def with_download_forbidden_env(dir : String, &)
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

# Serves the shared gem index but rejects every download with 403.
private def with_download_forbidden_server(&)
  root = File.expand_path("../fixtures/gem-index", __DIR__)
  server = HTTP::Server.new do |context|
    path = context.request.path
    if path.starts_with?("/gems/") || path.starts_with?("/quick/")
      context.response.status_code = 403
      context.response.print ""
      next
    end
    file = File.join(root, path.lchop("/"))
    if !path.empty? && File.file?(file)
      context.response.content_type = "application/octet-stream"
      context.response.print File.read(file)
    else
      context.response.status_code = 404
      context.response.print ""
    end
  end
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  begin
    yield address.port
  ensure
    server.close
  end
end

private def download_retry_lines(port : Int32) : Array(String)
  source = "http://127.0.0.1:#{port}/"
  gem_url = "http://127.0.0.1:#{port}/gems/json_pure-2.6.0.gem"
  (2..4).map do |attempt|
    "Retrying download gem from #{source} due to error (#{attempt}/4): " \
    "Gem::RemoteFetcher::FetchError bad response Forbidden 403 (#{gem_url})"
  end
end

describe "M7(5) gem download 403" do
  it "retries three times and fails the install with status 5" do
    with_download_forbidden_bridge do
      with_download_forbidden_server do |port|
        gemfile = "source \"http://127.0.0.1:#{port}/\"\n\ngem \"json_pure\", \"2.6.0\"\n"
        with_project({"Gemfile" => gemfile}) do |dir|
          with_download_forbidden_env(dir) do
            code, out, err = run_cli(["install"])
            code.should eq(5)
            err.should_not contain("celerite internal error")
            # Three retries (attempts 2..4) precede the reference's HTTP error.
            retries = download_retry_lines(port)
            retries.each { |line| err.should contain(line) }
            # The final block is word-wrapped at 80 columns like
            # `Bundler.ui.error …, wrap: true`.
            err.should contain(Celerite::Commands.word_wrap(
              "Bundler::HTTPError: Could not download gem from " \
              "http://127.0.0.1:#{port}/ due to underlying error " \
              "<bad response Forbidden 403 " \
              "(http://127.0.0.1:#{port}/gems/json_pure-2.6.0.gem)>", 80
            ))
            err.should contain("An error occurred while installing json_pure (2.6.0)")
            err.should contain("In Gemfile:\n  json_pure")
            # `Fetching <gem>` is printed before the retries, so it must appear
            # ahead of the blank lines that `Bundler::Retry` writes.
            out.should contain("Fetching json_pure 2.6.0")
            out.should_not contain("Installing json_pure")
            # One blank line per failed attempt (2/4 .. 4/4) plus the final one.
            expected_tail = "Fetching json_pure 2.6.0" + ("\n" * 5)
            out.should end_with(expected_tail)
          end
        end
      end
    end
  end
end
