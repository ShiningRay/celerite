require "./spec_helper"

# M8 / task-234: `CELERITE_REFERENCE_BUNDLER_LIB` is usually the reference
# release's lib dir, but a caller may deliberately leave it *set and empty* so
# RubyGems resolves the pinned release instead (the differential fixture
# `fixtures/differential/info-bundler-path` writes exactly
# `CELERITE_REFERENCE_BUNDLER_LIB=`). "" is truthy in Ruby, so before the fix
# `bridge_activate_bundler` took the explicit-lib branch, skipped the unshift
# and returned: activation was a no-op, the first `require "bundler"` loaded the
# host's default gem (4.0.16) and `bridge_ensure_bundler_version!` refused the
# whole evaluation with `BundlerVersionMismatch` (loaded 4.0.16 / expected
# 4.0.24). A lib path that does not exist is just as unusable and must fall back
# the same way.
#
# Both cases drive the real `assets/bridge/server.rb` over stdin/stdout, one
# bridge process per case, with an isolated GEM_PATH: that is the state a
# Celerite command creates and it is what makes the host default Bundler the
# release a non-activated process would load.
private BRIDGE_EMPTY_LIB_SERVER = File.expand_path("../assets/bridge/server.rb", __DIR__)

private EMPTY_LIB_PINNED_VERSION = "4.0.24"

private EMPTY_LIB_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gem "rake"
  GEMFILE

# Builds a home/gem home root plus the env a Celerite command hands the bridge.
# `CELERITE_REFERENCE_BUNDLER_LIB` is the value under test (empty or a path that
# does not exist); only the profile pin names the release, which is all
# `script/differential` exports (it sets the lib var and the profile version).
private def with_empty_lib_env(lib_value : String, & : Hash(String, String?) ->) : Nil
  root = File.tempname("celerite-bridge-empty-lib", "root")
  home = File.join(root, "home")
  gems = File.join(root, "gems")
  Dir.mkdir_p(home)
  Dir.mkdir_p(gems)
  env = {
    "HOME"                               => home,
    "USERPROFILE"                        => home,
    "GEM_HOME"                           => gems,
    "GEM_PATH"                           => gems,
    "BUNDLE_PATH"                        => File.join(root, "bundle"),
    "RUBYOPT"                            => nil,
    "CELERITE_BRIDGE_SERVER"             => BRIDGE_EMPTY_LIB_SERVER,
    "CELERITE_REFERENCE_BUNDLER_LIB"     => lib_value,
    "CELERITE_PROFILE_BUNDLER_VERSION"   => EMPTY_LIB_PINNED_VERSION,
    "CELERITE_REFERENCE_BUNDLER_VERSION" => nil,
  } of String => String?
  begin
    yield env
  ensure
    FileUtils.rm_rf(root)
  end
end

private def empty_lib_exchange(requests : Array(String), env : Hash(String, String?)) : Array(String)
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(
    "ruby",
    [BRIDGE_EMPTY_LIB_SERVER],
    input: IO::Memory.new(requests.join('\n') + "\n"),
    output: output,
    error: errors,
    env: env,
  )
  status.success?.should be_true, "bridge failed: #{errors.to_s}"
  output.to_s.lines.reject(&.empty?)
end

private def empty_lib_request(id : Int32, op : String, payload : Hash(String, String)) : String
  %({"proto":2,"id":#{id},"op":#{op.to_json},"payload":#{payload.to_json}})
end

# What a plain `require "bundler"` resolves to under the same isolated GEM_PATH:
# the host's default release, i.e. what a no-op activation would pin.
private def empty_lib_ambient_bundler_version(env : Hash(String, String?)) : String?
  probe_env = env.dup
  probe_env.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  output = IO::Memory.new
  status = Process.run(
    "ruby",
    ["-e", %(require "bundler"; print Bundler::VERSION)],
    output: output,
    error: Process::Redirect::Close,
    env: probe_env,
  )
  status.success? ? output.to_s.strip : nil
end

# The evaluation must name the pinned release and must not report the mismatch
# the no-op activation produced.
private def assert_empty_lib_evaluation(env : Hash(String, String?), gemfile : String) : Nil
  responses = empty_lib_exchange([
    empty_lib_request(1, "evaluate_gemfile", {"gemfile" => gemfile}),
  ], env)

  responses.size.should eq(1)
  response = JSON.parse(responses[0])
  response["ok"].as_bool.should be_true,
    "evaluate_gemfile failed: #{response["error"]?.try(&.to_s)}"
  response["error"]?.should be_nil

  result = response["result"]
  result["bundler_version"].as_s.should eq(EMPTY_LIB_PINNED_VERSION)
end

describe "M8 task-234 empty reference Bundler lib" do
  it "falls back to the pinned Bundler when the reference lib is set to an empty string" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => EMPTY_LIB_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      with_empty_lib_env("") do |env|
        ambient = empty_lib_ambient_bundler_version(env)
        pending! "host default Bundler is the pinned release; nothing to fall back from" if ambient == EMPTY_LIB_PINNED_VERSION

        assert_empty_lib_evaluation(env, gemfile)
      end
    end
  end

  it "falls back to the pinned Bundler when the reference lib path does not exist" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => EMPTY_LIB_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      missing = File.join(File.tempname("celerite-bridge-absent-lib", "root"), "gems", "bundler-4.0.24", "lib")
      File.directory?(missing).should be_false
      with_empty_lib_env(missing) do |env|
        ambient = empty_lib_ambient_bundler_version(env)
        pending! "host default Bundler is the pinned release; nothing to fall back from" if ambient == EMPTY_LIB_PINNED_VERSION

        assert_empty_lib_evaluation(env, gemfile)
      end
    end
  end
end
