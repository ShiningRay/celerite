require "./spec_helper"
require "digest/sha256"

# M8 task-246 (roadmap L162): the evaluation fingerprint must cover the
# configuration that can change what `Bundler::Dsl#eval_gemfile` returns and
# the Ruby ABI the evaluation ran under. Both were missing (see
# `docs/roadmap-evidence/M8-closure-audit.md`).
#
# * Configuration: the only configuration input the DSL reads is the plugin
#   index root (`source "...", type: <plugin>` asks `Bundler::Plugin.source?`),
#   so the fingerprint records `config.app_config` / `config.plugin_root` and a
#   digest over them. `BUNDLE_WITHOUT`/`ONLY`/`FROZEN`/`LOCKFILE`/`PLUGINS`
#   are read after the Definition exists or by install-time hooks only; the
#   task-246 oracle shows none of them changes the evaluated dependencies, so
#   recording them would only cost hits.
# * ABI: `abi.ruby_api_version`, `abi.extension_api_version` (the `-static`
#   suffix distinguishes shared-library builds), `abi.rbconfig_ruby_version`
#   and `abi.source`. This host has a single Ruby, so the ABI comparison is
#   exercised at the `Document#verify` level by forging the recorded values;
#   no spec can run the same project under two interpreters here.
#
# The cache keeps its other two components untouched: the whole-ENV signature
# stays conservative, and a hit still costs no RPC when the entry belongs to
# the same client.
private F3_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)

private F3_ENV_NAMES = %w[
  HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE BUNDLE_APP_CONFIG
  BUNDLE_USER_HOME BUNDLE_USER_CONFIG CELERITE_BRIDGE_SERVER
  CELERITE_BRIDGE_STATS CELERITE_PROFILE_BUNDLER_VERSION
  CELERITE_REFERENCE_BUNDLER_VERSION
]

# One project, isolated HOME/BUNDLE_PATH, one cache lifetime (one `CLI.run`).
private def with_f3_project(files : Hash(String, String), *,
                            stats : Bool = false, & : String ->) : Nil
  with_project(files) do |project|
    saved = {} of String => String?
    F3_ENV_NAMES.each { |name| saved[name] = ENV[name]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("BUNDLE_APP_CONFIG")
    ENV.delete("BUNDLE_USER_HOME")
    ENV.delete("BUNDLE_USER_CONFIG")
    ENV["CELERITE_BRIDGE_SERVER"] = F3_SERVER_PATH
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    if stats
      ENV["CELERITE_BRIDGE_STATS"] = "1"
    else
      ENV.delete("CELERITE_BRIDGE_STATS")
    end
    begin
      Celerite::Bridge::BridgeStats.begin_run
      Celerite::Bridge::EvaluationCache.begin_run
      yield project
    ensure
      Celerite::Bridge::EvaluationCache.finish
      saved.each do |name, value|
        if value
          ENV[name] = value
        else
          ENV.delete(name)
        end
      end
    end
  end
end

private def f3_client : Celerite::Bridge::Client
  Celerite::Bridge::Client.new(server_path: F3_SERVER_PATH)
end

# Spawns the bridge while `cwd` is the process directory: the bridge inherits
# it, and `Bundler.app_config_path` is derived from the Gemfile Bundler finds
# from there. `ping` forces the spawn so the later `Dir.cd` cannot move it.
private def f3_client_at(cwd : String) : Celerite::Bridge::Client
  client = Dir.cd(cwd) do
    spawned = f3_client
    spawned.ping
    spawned
  end
  client
end

private F3_MAIN_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gem "rake"
  GEMFILE

private def f3_names(evaluation : Celerite::Bridge::GemfileEvaluation) : Array(String)
  evaluation.dependencies.map(&.name)
end

private def f3_fingerprint(client : Celerite::Bridge::Client,
                           gemfile : String) : Celerite::EvalFingerprint::Document
  wire = client.evaluate_batch(gemfile, ["fingerprint"]).fingerprint.not_nil!
  Celerite::EvalFingerprint::Document.parse(wire.text, wire.digest, wire.verify).not_nil!
end

# The runtime a fresh bridge process would report, rebuilt from the records so
# the unit-level checks below compare like with like.
private def f3_runtime(document : Celerite::EvalFingerprint::Document) : Celerite::EvalFingerprint::Runtime
  records = document.records
  abi = Celerite::EvalFingerprint::Abi.new(
    records["abi.ruby_api_version"],
    records["abi.extension_api_version"],
    records["abi.rbconfig_ruby_version"],
    records["abi.source"],
  )
  config = Celerite::EvalFingerprint::EvaluationConfig.new(
    records["config.app_config"],
    records["config.plugin_root"],
  )
  Celerite::EvalFingerprint::Runtime.new(
    ruby_version: records["ruby.version"],
    patchlevel: records["ruby.patchlevel"],
    engine: records["ruby.engine"],
    engine_version: records["ruby.engine_version"],
    rubygems_version: records["rubygems.version"],
    bundler_version: records["bundler.version"],
    platform: records["platform"],
    abi: abi,
    config: config,
  )
end

private def f3_forge(document : Celerite::EvalFingerprint::Document, key : String,
                     value : String) : Celerite::EvalFingerprint::Document
  text = document.text.sub(/\n#{Regex.escape(key)}\t[^\n]*/, "\n#{key}\t#{value}")
  # Recompute the digest so `integrity_reason` passes and the check under test
  # is the one that rejects the document.
  Celerite::EvalFingerprint::Document.parse(text, Digest::SHA256.hexdigest(text), document.verify).not_nil!
end

describe "M8 evaluation fingerprint: configuration and ABI (task-246)" do
  it "records the configuration and ABI keys in the fingerprint text" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project({"Gemfile" => F3_MAIN_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f3_client
      begin
        document = f3_fingerprint(client, gemfile)
        records = document.records

        # Configuration: the app-level configuration root and the plugin index
        # root the DSL consults, plus a digest binding them together.
        records["config.app_config"].should_not be_empty
        records["config.plugin_root"].should contain("plugin")
        records["config.digest"].should eq(
          Celerite::EvalFingerprint::EvaluationConfig.digest_of(
            records["config.app_config"], records["config.plugin_root"]),
        )

        # ABI: RubyGems' own values, not a recomputation from `ruby.version`.
        records["abi.ruby_api_version"].should_not be_empty
        records["abi.extension_api_version"].should_not be_empty
        records["abi.rbconfig_ruby_version"].should_not be_empty
        records["abi.source"].should eq("real")
        document.verify(File.dirname(gemfile), f3_runtime(document)).should be_nil
      ensure
        client.close
      end
    end
  end

  it "misses when the bridge's configuration differs from the recorded one" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project({"Gemfile"       => F3_MAIN_GEMFILE,
                     "other/Gemfile" => F3_MAIN_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      baseline = f3_client
      begin
        baseline.evaluate_gemfile(gemfile)
        baseline_app_config = f3_fingerprint(baseline, gemfile).records["config.app_config"]
        baseline_app_config.should_not contain("other")
      ensure
        baseline.close
      end

      # Same ENV, different working directory: with a Gemfile one directory
      # deeper, `Bundler.app_config_path` resolves against that directory
      # instead of HOME, so the recorded configuration no longer describes
      # this bridge. The whole-ENV signature is unchanged, which is what
      # makes this a configuration-only invalidation.
      moved = f3_client_at(File.join(project, "other"))
      begin
        f3_names(moved.evaluate_gemfile(gemfile)).should eq(["rake"])
        moved_app_config = f3_fingerprint(moved, gemfile).records["config.app_config"]
        moved_app_config.should eq(File.join(project, "other", ".bundle").gsub('\\', '/'))
        Celerite::Bridge::EvaluationCache.misses.should be >= 1
      ensure
        moved.close
      end
    end
  end

  it "still hits when another client sees the same configuration" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project({"Gemfile" => F3_MAIN_GEMFILE}, stats: true) do |project|
      gemfile = File.join(project, "Gemfile")
      first = f3_client
      begin
        first.evaluate_gemfile(gemfile)
        first_rpc = Celerite::Bridge::BridgeStats.rpc
        first_rpc.should eq(1)

        # A second bridge with the same configuration must accept the first
        # entry: verification costs one `ruby_environment` RPC, never another
        # evaluation.
        second = f3_client
        begin
          f3_names(second.evaluate_gemfile(gemfile)).should eq(["rake"])
          Celerite::Bridge::BridgeStats.rpc.should eq(first_rpc + 1)
          Celerite::Bridge::EvaluationCache.hits.should eq(1)
        ensure
          second.close
        end
      ensure
        first.close
      end
    end
  end

  it "misses when the recorded ABI differs from the answering process" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project({"Gemfile" => F3_MAIN_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      base = File.dirname(gemfile)
      client = f3_client
      begin
        document = f3_fingerprint(client, gemfile)
        runtime = f3_runtime(document)
        document.verify(base, runtime).should be_nil

        # A different ABI (a `-static` build, or an extension API bump such as
        # 3.1.0 -> 3.2.0) must refuse the cached evaluation.
        forged_abi = f3_forge(document, "abi.extension_api_version", "3.2.0-static")
        forged_abi.verify(base, runtime).should eq("runtime:abi.extension_api_version")

        forged_ruby_api = f3_forge(document, "abi.ruby_api_version", "3.2.0")
        forged_ruby_api.verify(base, runtime).should eq("runtime:abi.ruby_api_version")

        # Same client semantics: the values are equal by construction, so a
        # nil runtime only requires the records to exist.
        document.verify(base, nil).should be_nil
      ensure
        client.close
      end
    end
  end

  it "rejects configuration records that no longer hang together" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project({"Gemfile" => F3_MAIN_GEMFILE}) do |project|
      gemfile = File.join(project, "Gemfile")
      base = File.dirname(gemfile)
      client = f3_client
      begin
        document = f3_fingerprint(client, gemfile)
        runtime = f3_runtime(document)

        # A plugin root that the answering process does not agree with.
        forged = f3_forge(document, "config.plugin_root", "/nonexistent/plugin")
        forged.verify(base, runtime).should eq("runtime:config.plugin_root")

        # An app-config path that the answering process does not agree with.
        forged_app = f3_forge(document, "config.app_config", "/nonexistent/.bundle")
        forged_app.verify(base, runtime).should eq("runtime:config.app_config")

        # One value edited without recomputing the digest: both records can
        # agree with the process and the document still must not pass.
        digest_forged = f3_forge(forged, "config.digest", "0" * 64)
        digest_forged.verify(base, f3_runtime(forged)).should eq("config.digest")

        # A fingerprint recorded before this slice has no config records and
        # can never answer again (that is the intended one-time miss).
        text = document.text.sub(/\nconfig\.digest\t[^\n]*/, "")
        without_digest = Celerite::EvalFingerprint::Document.parse(
          text, Digest::SHA256.hexdigest(text), document.verify).not_nil!
        without_digest.verify(base, runtime).should eq("record:config.digest")
      ensure
        client.close
      end
    end
  end

  it "still hits an unchanged project without another RPC" do
    pending! "ruby not available" unless ruby_available?
    with_f3_project({"Gemfile" => F3_MAIN_GEMFILE}, stats: true) do |project|
      gemfile = File.join(project, "Gemfile")
      client = f3_client
      begin
        first = client.evaluate_gemfile(gemfile)
        first_rpc = Celerite::Bridge::BridgeStats.rpc
        first_rpc.should eq(1)

        # The new records are compared on the foreign/persisted path; a hit
        # this client can vouch for must not pay an extra RPC for them.
        second = client.evaluate_gemfile(gemfile)
        Celerite::Bridge::BridgeStats.rpc.should eq(first_rpc)
        Celerite::Bridge::BridgeStats.procs.should eq(1)
        Celerite::Bridge::EvaluationCache.hits.should eq(1)
        Celerite::Bridge::EvaluationCache.misses.should eq(0)
        f3_names(second).should eq(f3_names(first))
      ensure
        client.close
      end
    end
  end
end
