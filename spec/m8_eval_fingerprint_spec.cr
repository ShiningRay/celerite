require "./spec_helper"

# M8 / roadmap L162 slice F1 (task-233): one bridge evaluation produces an
# evaluation fingerprint next to its ordinary answer. F1 only produces the
# section — no cache reads it and nothing is persisted — so the properties
# asserted here are the ones a future cache will depend on:
#
# * V1  the same inputs digest identically;
# * V2  a changed main Gemfile changes the digest;
# * V3  a changed gemspec changes the digest;
# * V4  a changed `eval_gemfile` target changes the digest;
# * V9  `gemfile.sha256` equality does not imply digest equality (a changed
#       gemspec is invisible to the main-file hash);
# * V11 a directory timestamp is not an input;
# * V12 line endings are hashed as bytes, not normalised.
#
# Each case drives the real server over stdin/stdout in one process, and asks
# for the section through the documented batch envelope.
private FINGERPRINT_SERVER_PATH = File.expand_path("../assets/bridge/server.rb", __DIR__)

private FINGERPRINT_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  gemspec

  gem "rake"
  GEMFILE

private FINGERPRINT_GEMSPEC = <<-RUBY
  Gem::Specification.new do |spec|
    spec.name = "fingerprint_fixture"
    spec.version = "0.1.0"
    spec.summary = "evaluation fingerprint fixture"
    spec.authors = ["celerite"]
    spec.files = []
    spec.require_paths = ["lib"]

    spec.add_development_dependency "rspec", ">= 3.0"
  end
  RUBY

private FINGERPRINT_CHAIN_GEMFILE = <<-GEMFILE
  source "https://rubygems.org"

  eval_gemfile "nested/Gemfile.local"

  gem "rake"
  GEMFILE

private FINGERPRINT_CHAIN_TARGET = <<-GEMFILE
  gem "json"
  GEMFILE

# Same probe as `spec/m8_bridge_bundler_activation_spec.cr:32-60`: the pinned
# reference Bundler lives in the checkout the worktree belongs to, which
# `git rev-parse --git-common-dir` names; the RubyInstaller copy is the same
# release. Probe `bundler/dsl.rb` as a file.
private def fingerprint_reference_lib : String
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

# Runs the real bridge over a batch of request lines; one process, one response
# line per request. Every response must be a success: a fingerprint case that
# turns into an error must fail loudly rather than assert on a missing field.
private def fingerprint_exchange(requests : Array(String)) : Array(JSON::Any)
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(
    "ruby",
    [FINGERPRINT_SERVER_PATH],
    input: IO::Memory.new(requests.join('\n') + "\n"),
    output: output,
    error: errors,
  )
  status.success?.should be_true, "bridge failed: #{errors.to_s}"

  output.to_s.lines.reject(&.empty?).map do |line|
    parsed = JSON.parse(line)
    parsed["ok"].as_bool.should be_true, "bridge request failed: #{line}"
    parsed["result"]
  end
end

private def fingerprint_request(id : Int32, gemfile : String, sections : Array(String) = ["fingerprint"]) : String
  payload = String.build do |io|
    io << %({"gemfile":)
    io << gemfile.to_json
    io << %(,"include":)
    io << sections.to_json
    io << '}'
  end
  %({"proto":#{Celerite::Bridge::PROTOCOL},"id":#{id},"op":"evaluate_batch","payload":#{payload}})
end

private def fingerprint_section(result : JSON::Any) : JSON::Any
  result["fingerprint"]
end

private def fingerprint_digest(result : JSON::Any) : String
  fingerprint_section(result)["digest"].as_s
end

private def fingerprint_text(result : JSON::Any) : String
  fingerprint_section(result)["text"].as_s
end

# Creates the fixture and runs the block with the environment the bridge needs:
# the pinned reference Bundler plus a HOME/BUNDLE_PATH inside the temp project.
private def with_fingerprint_project(files : Hash(String, String), & : String ->) : Nil
  with_project(files) do |project|
    names = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_GEMFILE BUNDLE_FROZEN CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB]
    previous = {} of String => String?
    names.each { |name| previous[name] = ENV[name]? }

    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("BUNDLE_GEMFILE")
    ENV.delete("BUNDLE_FROZEN")
    ENV["CELERITE_BRIDGE_SERVER"] = FINGERPRINT_SERVER_PATH
    ENV["CELERITE_REFERENCE_BUNDLER_LIB"] = fingerprint_reference_lib
    begin
      yield project
    ensure
      previous.each do |name, value|
        if value
          ENV[name] = value
        else
          ENV.delete(name)
        end
      end
    end
  end
end

private def fingerprint_fixture(project : String) : String
  File.join(project, "Gemfile")
end

describe "M8 task-233 evaluation fingerprint" do
  it "V1: the same inputs digest identically and the text has the documented shape" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_GEMFILE, "fingerprint_fixture.gemspec" => FINGERPRINT_GEMSPEC}) do |project|
      gemfile = fingerprint_fixture(project)
      results = fingerprint_exchange([
        fingerprint_request(1, gemfile),
        fingerprint_request(2, gemfile),
      ])

      fingerprint_text(results[0]).should eq(fingerprint_text(results[1]))
      fingerprint_digest(results[0]).should eq(fingerprint_digest(results[1]))
      digest = fingerprint_digest(results[0])
      digest.size.should eq(64)
      digest.should match(/\A[0-9a-f]{64}\z/)
      # The digest covers exactly the text (UTF-8).
      Digest::SHA256.hexdigest(fingerprint_text(results[0])).should eq(digest)

      text = fingerprint_text(results[0])
      text.starts_with?("celerite-eval-v1\n").should be_true
      text.ends_with?("\n").should be_true
      text.lines[1].should eq("fp.format\t1")

      verify = fingerprint_section(results[0])["verify"]
      files = verify["files"].as_a
      files.map { |file| file["role"].as_s }.should contain("gemfile")
      files.map { |file| file["role"].as_s }.should contain("gemspec")
      files.each { |file| file["sha256"].as_s.size.should eq(64) }
    end
  end

  it "V2: a changed main Gemfile changes the digest" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_GEMFILE, "fingerprint_fixture.gemspec" => FINGERPRINT_GEMSPEC}) do |project|
      gemfile = fingerprint_fixture(project)
      before = fingerprint_exchange([fingerprint_request(1, gemfile)])[0]

      File.write(gemfile, FINGERPRINT_GEMFILE.sub(%(gem "rake"), %(gem "json")))
      after = fingerprint_exchange([fingerprint_request(2, gemfile)])[0]

      fingerprint_digest(after).should_not eq(fingerprint_digest(before))
      fingerprint_text(after).should_not eq(fingerprint_text(before))
    end
  end

  it "V3 + V9: a changed gemspec changes the digest although gemfile.sha256 is equal" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_GEMFILE, "fingerprint_fixture.gemspec" => FINGERPRINT_GEMSPEC}) do |project|
      gemfile = fingerprint_fixture(project)
      gemspec = File.join(project, "fingerprint_fixture.gemspec")
      before = fingerprint_exchange([fingerprint_request(1, gemfile)])[0]

      # Only the gemspec changes; the main Gemfile bytes (and its hash) do not.
      File.write(gemspec, FINGERPRINT_GEMSPEC.sub(%(rspec), %(minitest)))
      after = fingerprint_exchange([fingerprint_request(2, gemfile)])[0]

      before["gemfile_sha256"].as_s.should eq(after["gemfile_sha256"].as_s)
      fingerprint_digest(after).should_not eq(fingerprint_digest(before))
    end
  end

  it "V4: a changed eval_gemfile target changes the digest and the verify set names it" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_CHAIN_GEMFILE, "nested/Gemfile.local" => FINGERPRINT_CHAIN_TARGET}) do |project|
      gemfile = fingerprint_fixture(project)
      target = File.join(project, "nested", "Gemfile.local")
      before = fingerprint_exchange([fingerprint_request(1, gemfile)])[0]

      File.write(target, FINGERPRINT_CHAIN_TARGET.sub(%(json), %(rake)))
      after = fingerprint_exchange([fingerprint_request(2, gemfile)])[0]

      fingerprint_digest(after).should_not eq(fingerprint_digest(before))

      files = fingerprint_section(before)["verify"]["files"].as_a
      chained = files.select { |file| file["role"].as_s == "evalchain" }
      chained.size.should eq(1)
      # `verify` paths are relative to the Gemfile's directory, with `/`.
      chained[0]["path"].as_s.should eq("nested/Gemfile.local")
      chained[0]["sha256"].as_s.size.should eq(64)
    end
  end

  it "V11: touching the project directory does not change the digest" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_GEMFILE, "fingerprint_fixture.gemspec" => FINGERPRINT_GEMSPEC}) do |project|
      gemfile = fingerprint_fixture(project)
      before = fingerprint_exchange([fingerprint_request(1, gemfile)])[0]

      # Creating and removing an entry bumps the directory mtime; no input the
      # fingerprint covers changes.
      scratch = File.join(project, "scratch-entry")
      File.write(scratch, "temporary\n")
      File.delete(scratch)
      after = fingerprint_exchange([fingerprint_request(2, gemfile)])[0]

      fingerprint_digest(after).should eq(fingerprint_digest(before))
    end
  end

  it "V12: CRLF and LF inputs digest differently and gemfile.sha256 stays equal" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_GEMFILE, "fingerprint_fixture.gemspec" => FINGERPRINT_GEMSPEC}) do |project|
      gemfile = fingerprint_fixture(project)
      gemspec = File.join(project, "fingerprint_fixture.gemspec")

      File.write(gemspec, FINGERPRINT_GEMSPEC.gsub("\n", "\r\n"))
      crlf = fingerprint_exchange([fingerprint_request(1, gemfile)])[0]

      File.write(gemspec, FINGERPRINT_GEMSPEC)
      lf = fingerprint_exchange([fingerprint_request(2, gemfile)])[0]

      crlf["gemfile_sha256"].as_s.should eq(lf["gemfile_sha256"].as_s)
      fingerprint_digest(crlf).should_not eq(fingerprint_digest(lf))
    end
  end

  it "is absent unless include names it, and unknown sections stay ignored" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_GEMFILE, "fingerprint_fixture.gemspec" => FINGERPRINT_GEMSPEC}) do |project|
      gemfile = fingerprint_fixture(project)
      results = fingerprint_exchange([
        fingerprint_request(1, gemfile, [] of String),
        fingerprint_request(2, gemfile, ["no_such_section"]),
      ])

      results.each { |result| result.as_h.has_key?("fingerprint").should be_false }
    end
  end

  it "parses into BatchGemfileEvaluation.fingerprint, and stays nil when not requested" do
    pending! "ruby not available" unless ruby_available?
    with_fingerprint_project({"Gemfile" => FINGERPRINT_GEMFILE, "fingerprint_fixture.gemspec" => FINGERPRINT_GEMSPEC}) do |project|
      gemfile = fingerprint_fixture(project)
      with_client do |client|
        answer = client.evaluate_batch(gemfile, ["fingerprint"])
        fingerprint = answer.fingerprint
        fingerprint.should_not be_nil
        fingerprint.not_nil!.digest.size.should eq(64)
        fingerprint.not_nil!.text.starts_with?("celerite-eval-v1\n").should be_true

        plain = client.evaluate_batch(gemfile)
        plain.fingerprint.should be_nil
      end
    end
  end
end
