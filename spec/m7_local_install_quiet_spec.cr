require "./spec_helper"

# `install --local` with a complete lock and a populated `vendor/cache` still
# announces the resolution: the reference calls `definition.resolve_with_cache!`
# (cli/install.rb / definition.rb), which prints `Resolving dependencies...`
# whenever it walks the local/cached index — measured on 4.0.24 and 2.7.2 for
# the cached, no-cache, stale-lock and BUNDLE_JOBS=1 shapes. The line is
# therefore NOT suppressed by `--local`; only the remote `Fetching source
# index ...` line is.
private def local_quiet_index : String
  url = file_source_url(File.expand_path("../fixtures/gem-index-locked-deps", __DIR__))
  url.ends_with?("/") ? url : url + "/"
end

private def local_quiet_lock(with_edge : Bool = true) : String
  String.build do |str|
    str << "GEM\n"
    str << "  remote: " << local_quiet_index << "\n"
    str << "  specs:\n"
    str << "    net-protocol (0.2.2)\n"
    str << "    net-smtp (0.5.0)\n"
    str << "      net-protocol (>= 0)\n\n" if with_edge
    str << "\nPLATFORMS\n  ruby\n\n"
    str << "DEPENDENCIES\n  net-smtp\n\n"
    str << "BUNDLED WITH\n   4.0.24\n"
  end
end

private def local_quiet_run(with_cache : Bool, args : Array(String),
                            jobs : String? = nil) : {Int32, Array(String), String}
  code = 0
  lines = [] of String
  err_text = ""
  with_project({"Gemfile" => %(source "#{local_quiet_index}"\n\ngem "net-smtp"\n)}) do |dir|
    File.write(File.join(dir, "Gemfile.lock"), local_quiet_lock)
    if with_cache
      cache = File.join(dir, "vendor", "cache")
      Dir.mkdir_p(cache)
      fixtures_gems = File.expand_path("../fixtures/gem-index-locked-deps/gems", __DIR__)
      %w[net-smtp-0.5.0.gem net-protocol-0.2.2.gem].each do |name|
        File.copy(File.join(fixtures_gems, name), File.join(cache, name))
      end
    end
    previous = {} of String => String?
    values = {
      "BUNDLE_PATH"                      => File.join(dir, "bundle"),
      "BUNDLE_APP_CONFIG"                => File.join(dir, ".bundle"),
      "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
      "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    }
    previous["BUNDLE_JOBS"] = ENV["BUNDLE_JOBS"]?
    ENV["BUNDLE_JOBS"] = jobs.not_nil! if jobs
    values.each do |key, value|
      previous[key] = ENV[key]?
      ENV[key] = value
    end
    begin
      Dir.mkdir_p(File.join(dir, ".bundle"))
      code, out, err = Dir.cd(dir) { run_cli(["install"] + args) }
      lines = out.lines.reject(&.empty?).map(&.rstrip)
      err_text = err
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
  {code, lines, err_text}
end

describe "install --local keeps the resolution announcement" do
  it "prints Resolving dependencies... for the cached shape" do
    code, lines, err = local_quiet_run(true, ["--local"])
    code.should eq(0)
    err.should eq("")
    lines.first.should eq("Resolving dependencies...")
    lines.should contain("Installing net-protocol 0.2.2")
    lines.should contain("Installing net-smtp 0.5.0")
    lines.should contain("Updating files in vendor/cache")
    lines.should contain("Bundle complete! 1 Gemfile dependency, 2 gems now installed.")
    lines.last.should start_with("Bundled gems are installed into ")
  end

  it "prints the same set with BUNDLE_JOBS=1" do
    code, lines, _err = local_quiet_run(true, ["--local"], jobs: "1")
    code.should eq(0)
    lines.first.should eq("Resolving dependencies...")
    lines.size.should eq(6)
  end

  it "never prints a remote source-index fetch under --local" do
    code, lines, _err = local_quiet_run(true, ["--local"])
    code.should eq(0)
    lines.any?(&.starts_with?("Fetching source index from ")).should be_false
  end
end
