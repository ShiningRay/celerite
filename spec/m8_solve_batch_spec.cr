require "./spec_helper"

describe "M8 L161 S2 solve_batch Ruby bridge" do
  it "runs the pinned Bundler 4.0.24 resolver and bridge boundary tests" do
    root = File.expand_path("..", __DIR__)
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("ruby", ["test/solve_batch_harness_test.rb"], chdir: root, output: output, error: error)

    status.success?.should be_true, "#{output}\n#{error}"
    output.to_s.should contain("35 checks, 0 failures")
  end

  it "dispatches solve_batch under protocol 1 and 2 with nested solver envelopes" do
    root = File.expand_path("..", __DIR__)
    fixture = IO::Memory.new
    fixture_error = IO::Memory.new
    status = Process.run("ruby", ["script/solve_batch_fixture.rb", "promotion_patch"], chdir: root, output: fixture, error: fixture_error)
    status.success?.should be_true, fixture_error.to_s
    payload = JSON.parse(fixture.to_s)

    requests = String.build do |io|
      [1, 2].each do |proto|
        io << JSON.build do |json|
          json.object do
            json.field "proto", proto
            json.field "id", proto
            json.field "op", "solve_batch"
            json.field "payload", payload
          end
        end
        io << '\n'
      end
    end

    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("ruby", ["assets/bridge/server.rb"],
      input: IO::Memory.new(requests),
      env: {"CELERITE_REFERENCE_BUNDLER_VERSION" => "4.0.24"},
      chdir: root,
      output: output,
      error: error)
    status.success?.should be_true, error.to_s
    error.to_s.should be_empty

    responses = output.to_s.lines.reject(&.empty?).map { |line| JSON.parse(line) }
    responses.size.should eq(2)
    responses.zip([1, 2]).each do |response, proto|
      response["proto"].as_i.should eq(proto)
      response["ok"].as_bool.should be_true
      solver = response["result"]
      solver["schema"].as_s.should eq("celerite.solve_batch/3")
      solver["ok"].as_bool.should be_true
      solver["result"]["chosen"].as_a.any? { |spec| spec["name"].as_s == "app" }.should be_true
    end
  end
end
