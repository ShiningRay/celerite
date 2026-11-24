require "./spec_helper"

describe "M8 L161 S1 pure-data solve_batch harness" do
  it "runs the pinned Bundler 4.0.24 resolver and boundary tests" do
    root = File.expand_path("..", __DIR__)
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("ruby", ["test/solve_batch_harness_test.rb"], chdir: root, output: output, error: error)

    status.success?.should be_true, "#{output}\n#{error}"
    output.to_s.should contain("0 failures")
  end
end
