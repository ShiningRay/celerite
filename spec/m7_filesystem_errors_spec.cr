require "./spec_helper"

private def with_permission_bridge(&)
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

private def permission_index_remote : String
  file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
end

private def permission_gemfile : String
  "source \"#{permission_index_remote}\"\n\ngem \"json_pure\"\n"
end

# A valid lockfile that still misses the resolved spec, so `lock` must rewrite
# it (the write is what hits the read-only attribute).
private def permission_lockfile : String
  remote = permission_index_remote.chomp("/") + "/"
  "GEM\n" \
  "  remote: #{remote}\n" \
  "  specs:\n" \
  "\n" \
  "PLATFORMS\n" \
  "  ruby\n" \
  "\n" \
  "DEPENDENCIES\n" \
  "  json_pure\n" \
  "\n" \
  "BUNDLED WITH\n" \
  "    4.0.24\n"
end

# Windows read-only attribute blocks `File.open(path, "w")` with
# File::AccessDeniedError (measured: .NET write -> UnauthorizedAccessException,
# celerite -> `Error opening file with mode 'w' ... 拒绝访问`).
private def with_read_only(path : String, &)
  {% if flag?(:windows) %}
    attrib = "C:\\Windows\\System32\\attrib.exe"
    set = Process.run(attrib, ["+R", path], output: Process::Redirect::Close, error: Process::Redirect::Close)
    set.success?.should be_true
    original = File.read(path)
    begin
      # `attrib +R` returning 0 is not enough: prove this file really rejects a
      # write in this process before trusting any exit code from the CLI.
      expect_raises(File::AccessDeniedError) do
        File.open(path, "w") { |io| io << "t257-write-probe" }
      end
      yield
    ensure
      clear = Process.run(attrib, ["-R", path], output: Process::Redirect::Close, error: Process::Redirect::Close)
      clear.success?.should be_true
      File.write(path, original)
    end
  {% else %}
    pending!("read-only file attribute is Windows-specific")
  {% end %}
end

# `lock` reports the `PermissionError` through the unified word wrap
# (`src/celerite/cli.cr:52-61` -> `Commands.word_wrap`, `commands.cr:1205-1214`),
# and the message embeds the *expanded* lockfile path. At the 80-column default
# the break points therefore move with the temp root's length (the geometry that
# made `9e01625` red under `C:\t\sp225` and green under
# `C:\t\cel\.tmp-scratch\sp225`). Pinning 30 columns removes that coupling: the
# fixed words already exhaust each line and the path is far wider than 30
# columns, so every break below holds for any temp root. Same restore shape as
# `spec/m7_add_options_spec.cr:41-53` and `spec/m7_source_index_missing_spec.cr:75-91`.
private def with_permission_columns(columns : String, &) : Nil
  previous = ENV["THOR_COLUMNS"]?
  begin
    ENV["THOR_COLUMNS"] = columns
    yield
  ensure
    if previous
      ENV["THOR_COLUMNS"] = previous
    else
      ENV.delete("THOR_COLUMNS")
    end
  end
end

describe "filesystem permission errors" do
  it "maps a read-only lockfile write to PermissionError (exit 23)" do
    with_permission_bridge do
      with_project({
        "Gemfile"      => permission_gemfile,
        "Gemfile.lock" => permission_lockfile,
      }) do |dir|
        lock_path = File.join(dir, "Gemfile.lock")
        with_read_only(lock_path) do
          with_permission_columns("30") do
            code, output, errors = run_cli(["lock"])
            code.should eq(23)
            output.should contain("Resolving dependencies...")
            # Coarse wording checks, then the 30-column rendering written out
            # literally. The expectation must not be produced by the code under
            # test (`word_wrap`) or it would only prove self-consistency.
            errors.should contain("There was an error while")
            errors.should contain("It is likely that you need to")
            errors.should contain("that path.")
            errors.should eq(
              "There was an error while\n" \
              "trying to write to\n" \
              "`#{File.expand_path(lock_path).gsub('\\', "/")}`.\n" \
              "It is likely that you need to\n" \
              "grant write permissions for\n" \
              "that path.\n"
            )
          end
        end
      end
    end
  end

  it "names the parent folder for :create" do
    error = Celerite::PermissionError.new("/tmp/x/Gemfile.lock", :create)
    error.message.should contain("executable permissions for all parent directories and write permissions for `/tmp/x`")
  end

  it "uses reference actions for :read and :executable" do
    Celerite::PermissionError.new("/tmp/x/Gemfile.lock", :read).message.should contain("read from")
    Celerite::PermissionError.new("/tmp/x/Gemfile.lock", :executable).message.should contain("execute")
  end

  it "has status 23 and wraps" do
    error = Celerite::PermissionError.new("/tmp/x/Gemfile.lock")
    error.status_code.should eq(23)
    error.wrap?.should be_true
  end
end
