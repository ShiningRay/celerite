require "./spec_helper"
require "http/client"

# M7(8) task-25: a lockfile with missing/empty CHECKSUMS entries must trigger a
# remote re-resolution and backfill `sha256=` (`definition.rb:630-659`,
# `empty_checksums_actionable?`). `--local` keeps the locked resolution because a
# local resolve cannot fill the entry. The reference writes the digest from the
# compact-index `checksum` field (`endpoint_specification.rb:175`,
# `checksum.rb:42-52`), which the fixtures' gem-index serves.
private def checksums_free_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

private def with_http_index(& : Int32 ->) : Nil
  port = checksums_free_port
  script = File.expand_path("../script/http_index_server.js", __DIR__)
  index = File.expand_path("../fixtures/gem-index", __DIR__)
  process = Process.new("node", [script, index, port.to_s],
    output: Process::Redirect::Close, error: Process::Redirect::Close)
  begin
    deadline = Time.instant + 10.seconds
    loop do
      begin
        HTTP::Client.get("http://127.0.0.1:#{port}/versions") { |response| response.status_code }
        break
      rescue
        raise "http index server did not start" if Time.instant > deadline
        sleep 50.milliseconds
      end
    end
    yield port
  ensure
    process.terminate rescue nil
  end
end

private def checksums_lock(url : String) : String
  <<-LOCK
  GEM
    remote: #{url}/
    specs:
      json_pure (2.8.1)

  PLATFORMS
    x64-mingw-ucrt

  DEPENDENCIES
    json_pure

  CHECKSUMS
    bundler (4.0.24)
    json_pure (2.8.1)

  BUNDLED WITH
     4.0.24
  LOCK
end

private def no_checksums_lock(url : String) : String
  <<-LOCK
  GEM
    remote: #{url}/
    specs:
      json_pure (2.8.1)

  PLATFORMS
    x64-mingw-ucrt

  DEPENDENCIES
    json_pure

  BUNDLED WITH
     4.0.24
  LOCK
end

private def with_bundle_path(path : String, & : ->) : Nil
  previous = ENV["BUNDLE_PATH"]?
  ENV["BUNDLE_PATH"] = path
  begin
    yield
  ensure
    if previous
      ENV["BUNDLE_PATH"] = previous
    else
      ENV.delete("BUNDLE_PATH")
    end
  end
end

private def json_pure_sha : String
  "json_pure (2.8.1) sha256=6a877929ba9d4fa0808ccc38656d1b15d138b2aa0aa32037ee05abea13427ace"
end

describe "M7 empty CHECKSUMS entries" do
  before_each do
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  end

  after_each do
    ENV.delete("CELERITE_BRIDGE_SERVER")
  end

  it "backfills an already-installed lockfile on install" do
    pending! "ruby not available" unless ruby_available?
    with_http_index do |port|
      url = "http://127.0.0.1:#{port}"
      preset = File.expand_path("../fixtures/differential/check-no-lockfile-installed/bundle-preset", __DIR__)
      with_project({
        "Gemfile"      => %(source "#{url}/"\n\ngem "json_pure"\n),
        "Gemfile.lock" => checksums_lock(url),
      }) do |dir|
        bundle = File.join(dir, "bundle")
        FileUtils.cp_r(preset, bundle)
        with_bundle_path(bundle) do
          code, stdout, _stderr = run_cli(["install"])
          code.should eq(0)
          stdout.should contain("Fetching gem metadata from #{url}/.")
          File.read(File.join(dir, "Gemfile.lock")).should contain(json_pure_sha)
        end
      end
    end
  end

  it "backfills the lockfile on lock" do
    pending! "ruby not available" unless ruby_available?
    with_http_index do |port|
      url = "http://127.0.0.1:#{port}"
      with_project({
        "Gemfile"      => %(source "#{url}/"\n\ngem "json_pure"\n),
        "Gemfile.lock" => checksums_lock(url),
      }) do |dir|
        code, stdout, _stderr = run_cli(["lock"])
        code.should eq(0)
        stdout.should contain("Fetching gem metadata from #{url}/.")
        File.read(File.join(dir, "Gemfile.lock")).should contain(json_pure_sha)
      end
    end
  end

  it "keeps the locked resolution under --local (no remote fetch can fill it)" do
    pending! "ruby not available" unless ruby_available?
    with_http_index do |port|
      url = "http://127.0.0.1:#{port}"
      with_project({
        "Gemfile"      => %(source "#{url}/"\n\ngem "json_pure"\n),
        "Gemfile.lock" => checksums_lock(url),
      }) do |dir|
        definition = Celerite::Definition.build
        definition.checksums_need_refresh?(true).should be_false
        definition.checksums_need_refresh?(false).should be_true
        code, stdout, _stderr = run_cli(["lock", "--local"])
        code.should eq(0)
        stdout.should_not contain("Fetching gem metadata")
        File.read(File.join(dir, "Gemfile.lock")).should contain("  json_pure (2.8.1)\n")
      end
    end
  end

  it "computes checksums for a file source with --add-checksums" do
    pending! "ruby not available" unless ruby_available?
    url = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    preset = File.expand_path("../fixtures/differential/check-no-lockfile-installed/bundle-preset", __DIR__)
    with_project({
      "Gemfile"      => %(source "#{url}"\n\ngem "json_pure"\n),
      "Gemfile.lock" => no_checksums_lock(url),
    }) do |dir|
      bundle = File.join(dir, "bundle")
      FileUtils.cp_r(preset, bundle)
      with_bundle_path(bundle) do
        code, stdout, _stderr = run_cli(["lock", "--add-checksums"])
        code.should eq(0)
        stdout.should contain("Fetching source index from #{url}/")
        stdout.should contain("Fetching json_pure 2.8.1")
        lock = File.read(File.join(dir, "Gemfile.lock"))
        lock.should contain(json_pure_sha)
        lock.should contain("bundler (4.0.24) sha256=")
      end
    end
  end

  it "rejects an empty CHECKSUMS entry in frozen mode" do
    pending! "ruby not available" unless ruby_available?
    url = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
    with_project({
      "Gemfile"      => %(source "#{url}"\n\ngem "json_pure"\n),
      "Gemfile.lock" => checksums_lock(url),
    }) do |dir|
      previous = ENV["BUNDLE_FROZEN"]?
      ENV["BUNDLE_FROZEN"] = "true"
      begin
        code, _stdout, stderr = run_cli(["install"])
        code.should eq(16)
        stderr.chomp.should eq(<<-ERR.chomp)
        Your lockfile has an empty CHECKSUMS entry for "json_pure", but can't be updated
        because frozen mode is set

        Run `bundle install` elsewhere and add the updated Gemfile.lock to version
        control.
        ERR
        File.read(File.join(dir, "Gemfile.lock")).should eq(checksums_lock(url))
      ensure
        if previous
          ENV["BUNDLE_FROZEN"] = previous
        else
          ENV.delete("BUNDLE_FROZEN")
        end
      end
    end
  end
end
