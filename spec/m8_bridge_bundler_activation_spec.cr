require "./spec_helper"

# M8 / task-230: one bridge process serves every op of a command
# (`Bridge::Client.shared`, task-221), so the Bundler version a Gemfile is
# evaluated with must not depend on which op ran first. Before the fix, an op
# that started with `require "bundler"` (the pre-install plugin pass,
# `assets/bridge/server.rb` `op_plugin_gemfile_eval`) loaded the host's default
# release first, and every later `require "bundler"` in the same process was a
# no-op: evaluation, lock rendering and the verbose banner all described 4.0.16
# while the command had pinned 4.0.24.
#
# Both cases drive the real server over stdin/stdout, in one process per case.
# They run with an isolated GEM_PATH on purpose: that is the state a Celerite
# command creates, and it is what makes the host's default Bundler (the copy in
# Ruby's own default gem dir) the thing a non-activated process would load.
private BRIDGE_ACTIVATION_SERVER = File.expand_path("../assets/bridge/server.rb", __DIR__)

private ACTIVATION_BUNDLER_VERSION = "4.0.24"

private ACTIVATION_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gem "rake"
  GEMFILE

# `.upstream-specs/` is machine-local (`.gitignore:8`), so a worktree does not
# carry it; the pinned reference Bundler lives in the checkout the worktree
# belongs to, which `git rev-parse --git-common-dir` names. The RubyInstaller
# copy is the same release and is what the differential fixtures pin. Probe for
# `bundler/dsl.rb`, a file — `File.directory?` rejected every candidate once
# already (`spec/m8_batch_eval_spec.cr:69-74`).
private def activation_reference_lib : String
  if value = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?
    return value unless value.empty?
  end

  candidates = [] of String
  candidates << File.expand_path("../.upstream-specs/v4.0.24/bundler/lib", __DIR__)
  candidates << "C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-4.0.24/lib"

  output = IO::Memory.new
  status = Process.run(
    "git",
    ["-C", __DIR__, "rev-parse", "--path-format=absolute", "--git-common-dir"],
    output: output,
    error: Process::Redirect::Close,
  )
  if status.success?
    common = output.to_s.strip
    unless common.empty?
      candidates << File.join(File.dirname(common), ".upstream-specs", "v4.0.24", "bundler", "lib")
    end
  end

  candidates.each do |candidate|
    return candidate if File.file?(File.join(candidate, "bundler", "dsl.rb"))
  end

  raise "reference Bundler 4.0.24 not materialised; run script/upstream-specs"
end

private def activation_request(id : Int32, op : String, payload : Hash(String, String)) : String
  %({"proto":2,"id":#{id},"op":#{op.to_json},"payload":#{payload.to_json}})
end

# A home and a gem home the child can write, plus the pinned reference Bundler.
# The child gets this env instead of the spec process's, so no developer
# configuration (BUNDLE_*, RUBYOPT, GEM_PATH) leaks into the exchange.
private def with_activation_env(rubyopt : String?, & : Hash(String, String?) ->) : Nil
  root = File.tempname("celerite-bridge-activation", "root")
  home = File.join(root, "home")
  gems = File.join(root, "gems")
  Dir.mkdir_p(home)
  Dir.mkdir_p(gems)
  env = {
    "HOME"                             => home,
    "USERPROFILE"                      => home,
    "GEM_HOME"                         => gems,
    "GEM_PATH"                         => gems,
    "BUNDLE_PATH"                      => File.join(root, "bundle"),
    "RUBYOPT"                          => rubyopt,
    "CELERITE_BRIDGE_SERVER"           => BRIDGE_ACTIVATION_SERVER,
    "CELERITE_REFERENCE_BUNDLER_LIB"   => activation_reference_lib,
    "CELERITE_PROFILE_BUNDLER_VERSION" => ACTIVATION_BUNDLER_VERSION,
  } of String => String?
  begin
    yield env
  ensure
    FileUtils.rm_rf(root)
  end
end

private def activation_exchange(requests : Array(String), env : Hash(String, String?)) : Array(String)
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(
    "ruby",
    [BRIDGE_ACTIVATION_SERVER],
    input: IO::Memory.new(requests.join('\n') + "\n"),
    output: output,
    error: errors,
    env: env,
  )
  status.success?.should be_true, "bridge failed: #{errors.to_s}"
  output.to_s.lines.reject(&.empty?)
end

# What a plain `require "bundler"` resolves to under this isolated GEM_PATH: the
# host's default release, i.e. the one a non-activated bridge process would pin.
private def activation_ambient_bundler_version(env : Hash(String, String?)) : String?
  probe_env = env.dup
  probe_env["RUBYOPT"] = nil
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

describe "M8 task-230 shared bridge Bundler activation" do
  it "evaluates with the pinned Bundler when plugin_gemfile_eval runs first" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => ACTIVATION_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      with_activation_env(nil) do |env|
        responses = activation_exchange([
          activation_request(1, "plugin_gemfile_eval", {"gemfile_path" => gemfile}),
          activation_request(2, "ruby_environment", {} of String => String),
          activation_request(3, "evaluate_gemfile", {"gemfile" => gemfile}),
        ], env)

        responses.size.should eq(3)
        responses.each { |response| response.should contain(%("ok":true)) }

        # Same process, after the plugin pass: the version that was actually
        # loaded is the pinned one, not whatever `require "bundler"` found first.
        environment = JSON.parse(responses[1])["result"]
        environment["loaded_bundler_version"].should eq(ACTIVATION_BUNDLER_VERSION)

        evaluation = JSON.parse(responses[2])["result"]
        evaluation["bundler_version"].should eq(ACTIVATION_BUNDLER_VERSION)
      end
    end
  end

  it "reports BundlerVersionMismatch when another Bundler was already loaded" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => ACTIVATION_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      with_activation_env("-rbundler") do |env|
        ambient = activation_ambient_bundler_version(env)
        pending! "host default Bundler is the pinned release; nothing to mismatch" if ambient == ACTIVATION_BUNDLER_VERSION
        ambient.should_not be_nil

        responses = activation_exchange([
          activation_request(1, "evaluate_gemfile", {"gemfile" => gemfile}),
        ], env)

        response = JSON.parse(responses[0])
        response["ok"].as_bool.should be_false
        # Structured error on the existing bridge channel, not a result computed
        # by the wrong release.
        response["error"]["class"].as_s.should eq("BundlerVersionMismatch")
        message = response["error"]["message"].as_s
        message.should contain("loaded #{ambient}")
        message.should contain("expected #{ACTIVATION_BUNDLER_VERSION}")
        response["result"]?.should be_nil
      end
    end
  end
end
