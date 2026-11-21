require "./spec_helper"

# With `--local` and a lock whose PLATFORMS already cover this host, the
# reference materialises every spec from the bundle/cache and prints no
# `Resolving dependencies...` line at all; the line only appears when the lock
# still needs a resolve (a `ruby`-only platform list, or a platform we cannot
# satisfy). Measured on 4.0.24 with `fixtures/gem-index-locked-deps`.
private def local_quiet_index : String
  url = file_source_url(File.expand_path("../fixtures/gem-index-locked-deps", __DIR__))
  url.ends_with?("/") ? url : url + "/"
end

private def local_quiet_lock(platforms : String) : String
  String.build do |str|
    str << "GEM\n"
    str << "  remote: " << local_quiet_index << "\n"
    str << "  specs:\n"
    str << "    net-protocol (0.2.2)\n"
    str << "    net-smtp (0.5.0)\n"
    str << "      net-protocol (>= 0)\n\n"
    str << "PLATFORMS\n"
    platforms.each_line { |line| str << "  " << line << "\n" }
    str << "\nDEPENDENCIES\n  net-smtp\n\nBUNDLED WITH\n   4.0.24\n"
  end
end

private def local_quiet_run(with_cache : Bool, platforms : String = Celerite::Gem::Platform.local.to_s,
                            args : Array(String) = ["--local"]) : {Int32, Array(String), String}
  code = 0
  lines = [] of String
  err_text = ""
  with_project({"Gemfile" => %(source "#{local_quiet_index}"\n\ngem "net-smtp"\n)}) do |dir|
    File.write(File.join(dir, "Gemfile.lock"), local_quiet_lock(platforms))
    if with_cache
      cache = File.join(dir, "vendor", "cache")
      Dir.mkdir_p(cache)
      gems = File.expand_path("../fixtures/gem-index-locked-deps/gems", __DIR__)
      %w[net-smtp-0.5.0.gem net-protocol-0.2.2.gem].each do |name|
        File.copy(File.join(gems, name), File.join(cache, name))
      end
    end
    previous = {} of String => String?
    values = {
      "BUNDLE_PATH"                      => File.join(dir, "bundle"),
      "BUNDLE_APP_CONFIG"                => File.join(dir, ".bundle"),
      "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
      "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    }
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

describe "install --local skips the resolution announcement" do
  it "prints exactly the five install lines for a platform-ready lock" do
    code, lines, err = local_quiet_run(true)
    code.should eq(0)
    err.should eq("")
    lines.size.should eq(5)
    lines.first.should eq("Installing net-protocol 0.2.2")
    lines.should_not contain("Resolving dependencies...")
    lines.should contain("Updating files in vendor/cache")
    lines.should contain("Bundle complete! 1 Gemfile dependency, 2 gems now installed.")
    lines.last.should start_with("Bundled gems are installed into ")
  end

  it "still announces the resolve when the lock only lists the ruby platform" do
    code, lines, _err = local_quiet_run(true, platforms: "ruby")
    code.should eq(0)
    lines.first.should eq("Resolving dependencies...")
  end

  it "never prints a remote source-index fetch under --local" do
    _code, lines, _err = local_quiet_run(true)
    lines.any?(&.starts_with?("Fetching source index from ")).should be_false
  end
end
