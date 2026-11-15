require "./spec_helper"

private def lock_ending_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def lock_ending_gemfile : String
  "source \"#{lock_ending_remote}\"\n\ngem \"json_pure\"\n"
end

# Deliberately spec-less lockfile: `lock` must rewrite it, which is what
# exercises the line-ending preservation path.
private def lock_ending_lockfile : String
  [
    "GEM",
    "  remote: #{lock_ending_remote}/",
    "  specs:",
    "",
    "PLATFORMS",
    "  x64-mingw-ucrt",
    "",
    "DEPENDENCIES",
    "  json_pure",
    "",
    "BUNDLED WITH",
    "    4.0.24",
  ].join("\n") + "\n"
end

private def without_checksums_block(text : String) : String
  out = [] of String
  skipping = false
  text.lines.each do |line|
    if line == "CHECKSUMS"
      skipping = true
      next
    end
    if skipping
      skipping = false if line.empty?
      next
    end
    out << line
  end
  out.join("\n") + (text.ends_with?("\n") ? "\n" : "")
end

private def with_lock_ending_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

# Both sides of the CRLF contract (definition.rb:428-434): an existing CRLF
# lockfile keeps CRLF on rewrite; a new or LF lockfile stays LF.
describe "lockfile line endings" do
  it "rewrites a CRLF lockfile without introducing lone LFs" do
    with_lock_ending_bridge do
      crlf_lockfile = lock_ending_lockfile.gsub("\n", "\r\n")
      with_project({"Gemfile" => lock_ending_gemfile, "Gemfile.lock" => crlf_lockfile}) do |dir|
        code, _out, err = run_cli(["lock"])
        code.should eq(0)
        path = File.join(dir, "Gemfile.lock")
        text = File.read(path)
        text.should contain("json_pure (2.8.1)")
        text.scan(/\r\n/).size.should be > 0
        # `?m` is required for the multiline CRLF normalization below.
        text.matches?(/(?<!\r)\n/).should be_false
        err.should_not contain("ERROR")

        # The payload, normalized for the terminator check, must match a
        # clean LF generation. CHECKSUMS presence depends on whether the run
        # recorded checksums, so it is stripped before the byte comparison.
        normalized = without_checksums_block(text)
        File.delete(path)
        run_cli(["lock"])[0].should eq(0)
        without_checksums_block(File.read(path)).should eq(normalized)
      end
    end
  end

  it "keeps an LF lockfile LF on rewrite" do
    with_lock_ending_bridge do
      with_project({"Gemfile" => lock_ending_gemfile, "Gemfile.lock" => lock_ending_lockfile}) do |dir|
        run_cli(["lock"])[0].should eq(0)
        text = File.read(File.join(dir, "Gemfile.lock"))
        text.should contain("json_pure (2.8.1)")
        text.includes?("\r\n").should be_false
      end
    end
  end

  it "writes a brand-new lockfile with LF" do
    with_lock_ending_bridge do
      with_project({"Gemfile" => lock_ending_gemfile}) do |dir|
        run_cli(["lock"])[0].should eq(0)
        text = File.read(File.join(dir, "Gemfile.lock"))
        text.should contain("json_pure (2.8.1)")
        text.includes?("\r\n").should be_false
      end
    end
  end

  it "keeps CRLF when the CRLF lockfile is already up to date" do
    with_lock_ending_bridge do
      crlf_lockfile = lock_ending_lockfile.gsub("\n", "\r\n")
      with_project({"Gemfile" => lock_ending_gemfile, "Gemfile.lock" => crlf_lockfile}) do |dir|
        run_cli(["lock"])[0].should eq(0)
        path = File.join(dir, "Gemfile.lock")
        first = File.read(path)
        first.matches?(/(?<!\r)\n/).should be_false
        run_cli(["lock"])[0].should eq(0)
        second = File.read(path)
        second.should eq(first)
        second.matches?(/(?<!\r)\n/).should be_false
      end
    end
  end
end
