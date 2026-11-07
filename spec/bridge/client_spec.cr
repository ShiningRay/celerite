require "../spec_helper"
require "../../src/celerite"

# Bridge protocol specs require a working `ruby` on PATH (the bridge is a
# Ruby subprocess by design); they are skipped when Ruby is absent.
def ruby_available? : Bool
  # Windows Crystal: `shell: true` with args is unsupported; use the command
  # string form (or plain exec on other platforms).
  result = Process.run("ruby -v", shell: true)
  result.success?
rescue
  false
end

def with_client(& : Celerite::Bridge::Client ->) : Nil
  server = File.expand_path("../../assets/bridge/server.rb", __DIR__)
  client = Celerite::Bridge::Client.new(server_path: server)
  begin
    yield client
  ensure
    client.close
  end
end

module Celerite
  describe Bridge::Client do
    it "pings across the protocol" do
      pending! "ruby not available" unless ruby_available?
      with_client do |client|
        client.ping.should match(/\d+\.\d+\.\d+/)
      end
    end

    it "reports the Ruby environment" do
      pending! "ruby not available" unless ruby_available?
      with_client do |client|
        env = client.ruby_environment
        env.ruby_version.should match(/\d+\.\d+\.\d+/)
        env.platform.should_not be_empty
        env.gem_paths.should_not be_empty
      end
    end

    it "evaluates a Gemfile through the real Bundler DSL" do
      pending! "ruby not available" unless ruby_available?
      with_project({
        "Gemfile" => "source \"https://rubygems.org\"\n\ngem \"json_pure\", \">= 2.0\", group: :test\ngem \"rake\", \"~> 13.0\"\nruby \">= 3.2.0\"\n",
      }) do
        with_client do |client|
          evaluation = client.evaluate_gemfile(File.join(Dir.current, "Gemfile"))
          evaluation.dependencies.map(&.name).should eq(["json_pure", "rake"])
          evaluation.dependencies[0].requirements.should eq([">= 2.0"])
          evaluation.dependencies[0].groups.should eq(["test"])
          evaluation.dependencies[1].groups.should eq(["default"])
          evaluation.ruby.should eq("ruby >= 3.2.0")
          evaluation.sources.map(&.type).should contain("Rubygems")
          evaluation.gemfile_sha256.size.should eq(64)
        end
      end
    end

    it "reports structured errors for broken Gemfiles" do
      pending! "ruby not available" unless ruby_available?
      with_project({
        "Gemfile" => "source \"https://rubygems.org\"\ngem \"x\"\nundefined_method_call_here\n",
      }) do
        with_client do |client|
          expect_raises(Bridge::BridgeError) do
            client.evaluate_gemfile(File.join(Dir.current, "Gemfile"))
          end
        end
      end
    end

    it "resolves and generates a lockfile against the local file:// index" do
      pending! "ruby not available" unless ruby_available?
      index = File.expand_path(File.join(__DIR__, "..", "..", "fixtures", "gem-index")).gsub(/\\/, "/")
      with_project({
        "Gemfile" => "source \"file:///#{index}\"\n\ngem \"json_pure\"\ngem \"racc\"\n",
      }) do |dir|
        with_client do |client|
          definition = Definition.build
          resolution = Resolution.new(definition, false, client)
          resolution.progress = IO::Memory.new
          data = resolution.generated_lockfile
          text = data.to_lock
          text.should contain("    json_pure (2.8.1)")
          text.should contain("    racc (1.8.1)")
          text.should contain("  remote: file:///#{index}/")
          text.should contain("BUNDLED WITH")
          # read-only guarantee
          File.exists?(File.join(dir, "Gemfile.lock")).should be_false
        end
      end
    end

    it "applies version constraints with lockfile relaxation" do
      pending! "ruby not available" unless ruby_available?
      index = File.expand_path(File.join(__DIR__, "..", "..", "fixtures", "gem-index")).gsub(/\\/, "/")
      with_project({
        "Gemfile"      => "source \"file:///#{index}\"\n\ngem \"json_pure\", \"2.6.0\"\ngem \"racc\"\n",
        "Gemfile.lock" => "GEM\n  remote: file:///#{index}/\n  specs:\n    json_pure (2.8.1)\n    racc (1.8.1)\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  json_pure\n  racc\n\nBUNDLED WITH\n  4.0.24\n",
      }) do
        with_client do |client|
          definition = Definition.build
          resolution = Resolution.new(definition, false, client)
          resolution.progress = IO::Memory.new
          text = resolution.generated_lockfile.to_lock
          text.should contain("    json_pure (2.6.0)")
        end
      end
    end
  end
end
