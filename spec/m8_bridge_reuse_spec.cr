require "./spec_helper"

# M8 task-221: one command must borrow a single bridge process instead of
# spawning one per call site, `CELERITE_BRIDGE_IDLE_MS` must recycle an idle
# shared client, and turning the counters off must not change what a command
# prints. The fixtures are the offline differential ones (`fixtures/` at the
# repository root) so the specs need no network.
private M8_REUSE_STATS_LINE = /^bridge: procs=(\d+) rpc=(\d+) req_bytes=(\d+) resp_bytes=(\d+)$/

private def m8_reuse_fixture_files(name : String) : Hash(String, String)
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  files = {} of String => String
  {% for file in %w[Gemfile Gemfile.lock] %}
    path = File.join(dir, {{file}})
    if File.file?(path)
      files[{{file}}] = File.read(path).gsub("@INDEX_DIR@", index)
    end
  {% end %}
  files
end

# The fixture declares `json_pure` and an unlocked `thor`; dropping the thor
# line leaves a Gemfile every gem of which is locked and present in the
# `bundle-preset` tree, so `check` and `list` both succeed without the network.
private def m8_reuse_satisfied_files(name : String) : Hash(String, String)
  files = m8_reuse_fixture_files(name)
  files["Gemfile"] = files["Gemfile"].sub("gem \"thor\"\n", "")
  files
end

private def with_m8_reuse_project(name : String, files : Hash(String, String), & : String ->) : Nil
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  with_project(files) do |project|
    FileUtils.cp_r(File.join(dir, "bundle-preset"), File.join(project, "bundle"))
    names = %w[HOME USERPROFILE BUNDLE_PATH CELERITE_BRIDGE_SERVER CELERITE_PROFILE_BUNDLER_VERSION CELERITE_BRIDGE_STATS CELERITE_BRIDGE_IDLE_MS]
    previous = {} of String => String?
    names.each { |n| previous[n] = ENV[n]? }
    ENV["HOME"] = project
    ENV["USERPROFILE"] = project
    ENV["BUNDLE_PATH"] = File.join(project, "bundle")
    ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    ENV["CELERITE_BRIDGE_STATS"] = "1"
    ENV.delete("CELERITE_BRIDGE_IDLE_MS")
    begin
      yield project
    ensure
      previous.each do |key, value|
        if value
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end
  end
end

private def m8_reuse_stats(errors : String) : Array(Int32)
  line = errors.lines.find(&.starts_with?("bridge: procs="))
  return [] of Int32 if line.nil?
  match = line.match(M8_REUSE_STATS_LINE).not_nil!
  (1..4).map { |i| match[i].to_i }
end

describe "M8 task-221 bridge reuse" do
  it "runs check on one bridge process" do
    with_m8_reuse_project("check-gemfile-new-dependency", m8_reuse_satisfied_files("check-gemfile-new-dependency")) do |_|
      code, output, err = run_cli(["check"])
      code.should eq(0), "stdout=#{output}\nstderr=#{err}"
      output.should contain("The Gemfile's dependencies are satisfied")
      stats = m8_reuse_stats(err)
      stats.size.should eq(4), "missing stats line: #{err}"
      stats[0].should eq(1)
    end
  end

  it "runs list on one bridge process" do
    with_m8_reuse_project("check-gemfile-new-dependency", m8_reuse_satisfied_files("check-gemfile-new-dependency")) do |_|
      code, output, err = run_cli(["list"])
      code.should eq(0), "stdout=#{output}\nstderr=#{err}"
      output.should contain("json_pure (2.6.0)")
      stats = m8_reuse_stats(err)
      stats.size.should eq(4), "missing stats line: #{err}"
      stats[0].should eq(1)
    end
  end

  it "recycles the shared client once CELERITE_BRIDGE_IDLE_MS elapses" do
    files = m8_reuse_satisfied_files("check-gemfile-new-dependency")
    with_m8_reuse_project("check-gemfile-new-dependency", files) do |_|
      code, output, err = run_cli(["check"])
      code.should eq(0), "stdout=#{output}\nstderr=#{err}"
      m8_reuse_stats(err)[0].should eq(1)
    end
    with_m8_reuse_project("check-gemfile-new-dependency", files) do |_|
      ENV["CELERITE_BRIDGE_IDLE_MS"] = "1"
      code, output, err = run_cli(["check"])
      code.should eq(0), "stdout=#{output}\nstderr=#{err}"
      # `check` borrows the shared client at least twice; with a 1ms idle
      # window the second borrow has to spawn a new process.
      m8_reuse_stats(err)[0].should be > 1
    end
  end

  it "leaves stdout unchanged when the counters are off" do
    files = m8_reuse_satisfied_files("check-gemfile-new-dependency")
    with_m8_reuse_project("check-gemfile-new-dependency", files) do |_|
      code, output, err = run_cli(["check"])
      code.should eq(0), "stdout=#{output}\nstderr=#{err}"
      m8_reuse_stats(err).size.should eq(4)

      ENV.delete("CELERITE_BRIDGE_STATS")
      code, output_without, err_without = run_cli(["check"])
      code.should eq(0), "stdout=#{output_without}\nstderr=#{err_without}"
      err_without.should_not contain("bridge: procs=")
      output_without.should eq(output)
    end
  end
end
