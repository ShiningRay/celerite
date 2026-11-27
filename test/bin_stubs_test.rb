#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

root = File.expand_path("..", __dir__)
server_path = File.expand_path(ENV.fetch("CELERITE_BRIDGE_SERVER", File.join(root, "assets", "bridge", "server.rb")))
gem_path = File.join(root, "fixtures", "gem-index", "gems", "thor-1.3.2.gem")

begin
  raise "missing thor fixture: #{gem_path}" unless File.file?(gem_path)
  raise "missing bridge server: #{server_path}" unless File.file?(server_path)

  Dir.mktmpdir("celerite-bin-stubs") do |dir|
    install_root = File.join(dir, "install")
    destination = File.join(install_root, "bin")
    gem_dir = File.join(install_root, "gems", "thor-1.3.2")
    Gem::Package.new(gem_path).extract_files(gem_dir)
    request = {
      "proto" => 2,
      "id" => 1,
      "op" => "generate_bin_stubs",
      "payload" => {
        "gem_path" => gem_path,
        "destination" => destination,
        "gem_dir" => gem_dir,
      },
    }
    env = {
      "CELERITE_REFERENCE_BUNDLER_LIB" => nil,
      "CELERITE_PROFILE_BUNDLER_VERSION" => nil,
    }
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, server_path,
      stdin_data: "#{JSON.generate(request)}\n", chdir: root)
    raise "bridge exited #{status.exitstatus}: #{stderr}" unless status.success?

    response = JSON.parse(stdout)
    result = response["result"] || {}
    unless response["ok"] && response["proto"] == 2 && response["id"] == 1 &&
           result["executables"] == ["thor"] && result["error"].nil?
      raise "unexpected bridge response: #{JSON.generate(response)}; stderr=#{stderr.inspect}"
    end

    script_path = File.join(destination, "thor")
    raise "thor script was not generated: #{script_path}" unless File.file?(script_path)
    raise "thor script is empty: #{script_path}" if File.size(script_path).zero?

    if Gem.win_platform?
      bat_path = "#{script_path}.bat"
      raise "Windows thor batch stub was not generated: #{bat_path}" unless File.file?(bat_path)
    else
      raise "thor script is not executable: #{script_path}" unless File.executable?(script_path)
    end
  end

  puts "bin_stubs_test: 1 checks, 0 failures"
rescue StandardError => error
  warn "not ok - generate_bin_stubs: #{error.class}: #{error.message}"
  exit 1
end
