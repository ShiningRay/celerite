require "./spec_helper"
require "../src/celerite"
require "json"

private T272_SERVER = File.expand_path("../assets/bridge/server.rb", __DIR__)
private T272_INDEX  = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
private T272_TMP    = File.join(Dir.tempdir, "celerite-m8-task272-#{Process.pid}")

private def t272_run_ruby(script : String, server : String, payload : String)
  Dir.mkdir_p(T272_TMP)
  suffix = Process.pid.to_s
  script_path = File.join(T272_TMP, "task272-static-#{suffix}.rb")
  output_path = File.join(T272_TMP, "task272-static-#{suffix}.out")
  error_path = File.join(T272_TMP, "task272-static-#{suffix}.err")
  File.write(script_path, "STDOUT.reopen(ENV.fetch(\"T272_RUBY_OUTPUT\"))\nSTDERR.reopen(ENV.fetch(\"T272_RUBY_ERROR\"))\n" + script)
  env = {"T272_RUBY_OUTPUT" => output_path, "T272_RUBY_ERROR" => error_path, "T272_RUBY_PAYLOAD" => payload}
  status = Process.run(ENV.fetch("CELERITE_RUBY", "ruby"), [script_path, server], env: env, input: Process::Redirect::Close)
  {status, File.read(output_path), File.read(error_path)}
ensure
  [script_path, output_path, error_path].each do |path|
    File.delete(path) if path && File.exists?(path)
  end
end

private def t272_static_proofs : JSON::Any
  script = <<-RUBY
    require "json"
    load ARGV.fetch(0)
    cases = JSON.parse(ENV.fetch("T272_RUBY_PAYLOAD"))
    result = cases.to_h { |item| [item["name"], bridge_fingerprint_static_proof(item["text"])] }
    puts JSON.generate(result)
  RUBY
  cases = [
    {name: "plain", text: %(source "#{T272_INDEX}"\ngem "json_pure"\n), reason: nil},
    {name: "gemspec", text: "Gem::Specification.new do |spec|\n  spec.name = \"demo\"\n  spec.version = \"1.0.0\"\n  spec.authors = [\"demo\"]\nend\n", reason: nil},
    {name: "bare-gemspec", text: "source \"rubygems.org\"\n\ngemspec\n", reason: nil},
    {name: "group", text: "group :development do\n  gem \"rake\"\nend\n", reason: nil},
    {name: "evalchain", text: "eval_gemfile \"nested/Gemfile.local\"\n", reason: nil},
    {name: "rand", text: "gem \"json_pure\" if rand(2) == 0\n", reason: "unknown:unproven-static"},
    {name: "time", text: "gem \"json_pure\" if Time.now.to_i > 0\n", reason: "unknown:unproven-static"},
    {name: "reflection", text: "gem \"json_pure\" if Kernel.respond_to?(:system)\n", reason: "unknown:unproven-static"},
    {name: "send", text: "gem \"json_pure\" if Object.new.send(:nil?)\n", reason: "unknown:unproven-static"},
    {name: "eval", text: "gem \"json_pure\" if eval(\"true\")\n", reason: "unknown:unproven-static"},
    {name: "heredoc", text: "source <<~URL\n#{T272_INDEX}\nURL\n", reason: "unknown:unproven-static"},
    {name: "alias", text: "alias current_ruby ruby\ngem \"json_pure\"\n", reason: "unknown:unproven-static"},
    {name: "syntax", text: "gem \"unterminated\n", reason: "unknown:unproven-static"},
    {name: "interpolation", text: %q(gem "json_#{'pure'}"\n), reason: "unknown:unproven-static"},
    {name: "dir-index", text: "Dir['*.gemspec'].each { |path| gemspec path }\n", reason: "unknown:unproven-static"},
    {name: "dir-glob", text: "Dir.glob('*.gemspec').each { |path| gemspec path }\n", reason: "unknown:unproven-static"},
    {name: "file-join", text: "gemspec File.join(__dir__, 'demo.gemspec')\n", reason: "unknown:unproven-static"},
    {name: "unknown-call", text: "custom_dependency 'demo'\n", reason: "unknown:unproven-static"},
  ]
  status, stdout, stderr = t272_run_ruby(script, T272_SERVER, cases.to_json)
  fail(stderr) unless status.success?
  JSON.parse(stdout)
end

describe "task-272 positive static DSL proof" do
  it "accepts only static DSL and rejects dynamic, reflective and file-dependent syntax" do
    proofs = t272_static_proofs
    %w[plain gemspec bare-gemspec group evalchain].each do |name|
      proofs[name].raw.should be_nil
    end
    %w[rand time reflection send eval heredoc alias syntax interpolation dir-index dir-glob file-join unknown-call].each do |name|
      proofs[name].as_s.should eq("unknown:unproven-static")
    end
  end

  it "keeps the evaluate_batch fingerprint response shape for a static Gemfile" do
    pending! "ruby not available" unless ruby_available?
    with_project({"Gemfile" => %(source "#{T272_INDEX}"\ngem "json_pure"\n)}) do |project|
      request = %({"proto":1,"id":1,"op":"evaluate_batch","payload":{"gemfile":"#{File.join(project, "Gemfile").gsub('\\', '/')}","include":["fingerprint"]}})
      script = <<-RUBY
        require "json"
        load ARGV.fetch(0)
        request = JSON.parse(ENV.fetch("T272_RUBY_PAYLOAD"))
        puts JSON.generate({"ok" => true, "result" => op_evaluate_batch(request["payload"])})
      RUBY
      status, stdout, stderr = t272_run_ruby(script, T272_SERVER, request)
      status.success?.should be_true
      fail(stderr) unless status.success?
      response = JSON.parse(stdout.lines.reject(&.empty?).first)
      response["ok"].as_bool.should be_true
      fingerprint = response["result"]["fingerprint"]
      fingerprint.as_h.keys.sort.should eq(%w[digest state state_reason text verify])
      fingerprint["state"].as_s.should eq("deterministic")
      fingerprint["state_reason"].raw.should be_nil
    end
  end
end
