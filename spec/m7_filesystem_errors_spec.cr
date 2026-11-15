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
    Process.run("cmd.exe", ["/c", "attrib", "+R", path], output: Process::Redirect::Close, error: Process::Redirect::Close)
    begin
      yield
    ensure
      Process.run("cmd.exe", ["/c", "attrib", "-R", path], output: Process::Redirect::Close, error: Process::Redirect::Close)
    end
  {% else %}
    pending!("read-only file attribute is Windows-specific")
  {% end %}
end

private def permission_expected_stderr(path : String) : String
  message = Celerite::PermissionError.new(path, :write).message
  Celerite::Commands.word_wrap(message, Celerite::CLI.terminal_width) + "\n"
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
          code, output, errors = run_cli(["lock"])
          code.should eq(23)
          output.should contain("Resolving dependencies...")
          errors.should contain("There was an error while trying to write to")
          errors.should contain("It is likely that you need to grant write permissions for that path.")
          errors.should eq(permission_expected_stderr(File.expand_path(lock_path).gsub('\\', "/")))
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
