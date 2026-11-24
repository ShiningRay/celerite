require "json"
require "./spec_helper"
require "../src/celerite/gem/platform"
require "../src/celerite/runtime_facts"
require "../src/celerite/resolution"

private IFP_INDEX    = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
private IFP_STATS    = /^bridge: procs=(\d+) rpc=(\d+) req_bytes=(\d+) resp_bytes=(\d+)$/
private IFP_HIT      = /^fast-path: install hit \(digest=([0-9a-f]{12})\)$/
private IFP_MISS     = /^fast-path: install miss \((.+)\)$/
private IFP_SWITCHES = %w[
  CELERITE_FAST_PATH CELERITE_FAST_PATH_DEBUG CELERITE_EVAL_CACHE
  CELERITE_CACHE_DIR CELERITE_BRIDGE_STATS CELERITE_BRIDGE_SERVER
  CELERITE_REFERENCE_BUNDLER_LIB CELERITE_VERBOSE
]
private IFP_ISOLATED = %w[HOME USERPROFILE BUNDLE_PATH BUNDLE_WITHOUT TMPDIR TMP TEMP]

private def ifp_bin : String
  path = ENV["CELERITE_TEST_BINARY"]? || File.expand_path("../bin/celerite.exe", __DIR__)
  fail "test binary is not built: #{path}" unless File.exists?(path)
  path
end

private def ifp_env(*switches : String) : Hash(String, String)
  env = {"CELERITE_BRIDGE_STATS" => "1"}
  switches.each { |name| env[name] = "1" }
  env
end

private def ifp_with_env(project : String, overrides : Hash(String, String), &)
  keys = (IFP_ISOLATED + IFP_SWITCHES + overrides.keys).uniq!
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]? }
  keys.each { |key| ENV.delete(key) }
  tmp = File.join(project, "tmp")
  Dir.mkdir_p(tmp)
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, "bundle")
  ENV["TMPDIR"] = tmp
  ENV["TMP"] = tmp
  ENV["TEMP"] = tmp
  overrides.each { |key, value| ENV[key] = value }
  begin
    yield
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

private def ifp_run(project : String, args : Array(String)) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(ifp_bin, args, chdir: project, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

private def ifp_stats(errors : String) : {Int32, Int32, Int32, Int32}
  line = errors.lines.find(&.starts_with?("bridge: procs="))
  fail "missing bridge stats: #{errors.inspect}" unless line
  match = line.match(IFP_STATS).not_nil!
  {match[1].to_i, match[2].to_i, match[3].to_i, match[4].to_i}
end

private def ifp_lines(errors : String, regex : Regex) : Array(String)
  errors.lines.compact_map { |line| line.match(regex).try(&.[1]) }
end

private def ifp_ready(project : String) : Nil
  pending!("no Ruby interpreter on PATH for the bridge") unless ruby_available?
  File.write(File.join(project, "Gemfile"), %(source "#{IFP_INDEX}"\n\neval_gemfile "extra.rb"\n))
  File.write(File.join(project, "extra.rb"), %(gem "json_pure"\n))
  FileUtils.mkdir_p(File.join(project, ".bundle"))
  File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "false"\n))
  env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
  ifp_with_env(project, env) do
    status, output, errors = ifp_run(project, ["install"])
    fail "cold install failed (#{status}): #{output} #{errors}" unless status == 0
    ifp_stats(errors)[0].should be >= 1
  end
end

private def ifp_hot(project : String, args = ["install"], overrides = {} of String => String) : {Int32, String, String, Tuple(Int32, Int32, Int32, Int32)}
  env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
  env.merge!(overrides)
  result = {0, "", "", {0, 0, 0, 0}}
  ifp_with_env(project, env) do
    status, output, errors = ifp_run(project, args)
    result = {status, output, errors, ifp_stats(errors)}
  end
  result
end

private def ifp_abi : String
  Celerite::RuntimeFacts.detect.try(&.abi.value) || fail("RuntimeFacts ABI is unavailable")
end

private def ifp_installed_file(project : String, kind : String, full_name : String) : String
  root = File.join(project, "bundle", "ruby", ifp_abi)
  File.join(root, kind, full_name)
end

private def ifp_full_name(project : String) : String
  lock = File.read(File.join(project, "Gemfile.lock"))
  version = lock.match(/json_pure \((\d+\.\d+\.\d+)\)/).not_nil![1]
  "json_pure-#{version}"
end

private def ifp_cache_entries(project : String) : Array(String)
  base = File.join(project, ".celerite", "cache", "eval")
  Celerite::Glob.paths(base, "*").flat_map do |namespace|
    Celerite::Glob.paths(File.join(namespace, "v1"), "*").compact_map do |digest|
      path = File.join(digest, "entry.json")
      path if File.file?(path)
    end
  end
end

private def ifp_rename_indexed_spec(project : String, full_name : String,
                                    renamed_name : String, renamed : String) : Nil
  File.rename(ifp_installed_file(project, "specifications", "#{full_name}.gemspec"),
    ifp_installed_file(project, "specifications", "#{renamed}.gemspec"))
  File.rename(ifp_installed_file(project, "gems", full_name),
    ifp_installed_file(project, "gems", renamed))
  lock_path = File.join(project, "Gemfile.lock")
  lock = File.read(lock_path)
    .gsub("  json_pure\n", "  #{renamed_name}\n")
    .gsub("  json_pure (", "  #{renamed_name} (")
  File.write(lock_path, lock)
  ifp_cache_entries(project).each do |path|
    json = JSON.parse(File.read(path))
    json["evaluation"].as_h["dependencies"].as_a.each do |dep|
      dep.as_h["name"] = JSON::Any.new(renamed_name) if dep["name"].as_s? == "json_pure"
    end
    File.write(path, json.to_json)
  end
end

private def ifp_mark_native_complete(project : String, full_name : String) : Nil
  gemspec = ifp_installed_file(project, "specifications", "#{full_name}.gemspec")
  text = File.read(gemspec)
  closing = text.rindex("end")
  fail "unexpected gemspec shape" unless closing
  File.write(gemspec, text[0...closing] + "  s.extensions = [\"extconf.rb\"]\n" + text[closing..])
  ext = File.join(File.dirname(File.dirname(gemspec)), "extensions",
    Celerite::Gem::Platform.local.to_s, ifp_abi, full_name)
  Dir.mkdir_p(ext)
  File.write(File.join(ext, "gem.build_complete"), "")
end

describe "install takes the no-Ruby fast path on an unchanged project" do
  it "uses one Ruby process on the cold install and zero processes/rpc/bytes on the hot install" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      status, output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats.should eq({0, 0, 0, 0})
      ifp_lines(errors, IFP_HIT).size.should eq(1)
      output.should contain("Bundle complete! 1 Gemfile dependency, 1 gem now installed.")
    end
  end

  it "prints the same stdout as the compatible no-op install, twice" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      baseline = {0, "", ""}
      ifp_with_env(project, ifp_env("CELERITE_EVAL_CACHE")) do
        baseline = ifp_run(project, ["install"])
      end
      baseline[0].should eq(0)
      2.times do
        status, output, errors, stats = ifp_hot(project)
        status.should eq(0)
        stats.should eq({0, 0, 0, 0})
        output.should eq(baseline[1])
      end
    end
  end

  it "does not consult a broken CELERITE_BRIDGE_SERVER on the hot path" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      status, _output, _errors, stats = ifp_hot(project, ["install"], {"CELERITE_BRIDGE_SERVER" => "http://127.0.0.1:1"})
      status.should eq(0)
      stats.should eq({0, 0, 0, 0})
    end
  end

  it "invalidates when the Gemfile changes" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      File.write(File.join(project, "Gemfile"), File.read(File.join(project, "Gemfile")) + "\n# changed\n")
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
    end
  end

  it "invalidates when the eval chain changes" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      File.write(File.join(project, "extra.rb"), %(gem "json_pure"\n# changed\n))
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
    end
  end

  it "invalidates when the lockfile changes" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      path = File.join(project, "Gemfile.lock")
      lock = File.read(path)
      changed = lock.sub("DEPENDENCIES\n  json_pure\n", "DEPENDENCIES\n  json_pure\n  thor\n")
      changed.should_not eq(lock)
      File.write(path, changed)
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("dependencies")
    end
  end

  it "invalidates when the installed gemspec is missing" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      full_name = ifp_full_name(project)
      File.delete(ifp_installed_file(project, "specifications", "#{full_name}.gemspec"))
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
    end
  end

  it "invalidates when the gem directory is missing" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      full_name = ifp_full_name(project)
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
    end
  end

  it "invalidates when native extensions are incomplete" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      full_name = ifp_full_name(project)
      gemspec = ifp_installed_file(project, "specifications", "#{full_name}.gemspec")
      text = File.read(gemspec)
      closing = text.rindex("end")
      fail "unexpected gemspec shape" unless closing
      File.write(gemspec, text[0...closing] + "  s.extensions = [\"extconf.rb\"]\n" + text[closing..])
      ext = File.join(File.dirname(File.dirname(gemspec)), "extensions",
        Celerite::Gem::Platform.local.to_s, ifp_abi, full_name)
      status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      fail "native extension dir unexpectedly exists" if Dir.exists?(ext)
    end
  end

  it "never hits when InstalledIndex cannot parse an installed full name" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      full_name = ifp_full_name(project)
      renamed = "0json_pure-#{full_name[/\d+\.\d+\.\d+$/]}"
      ifp_rename_indexed_spec(project, full_name, "0json_pure", renamed)
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("install-index:#{renamed}")
    end
  end

  it "still hits when a native extension marker is complete and indexed" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      ifp_mark_native_complete(project, ifp_full_name(project))
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats.should eq({0, 0, 0, 0})
      ifp_lines(errors, IFP_HIT).size.should eq(1)
    end
  end

  it "never hits for dynamic DSL" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      File.write(File.join(project, "Gemfile"), File.read(File.join(project, "Gemfile")) + "\neval(\"gem 'json_pure'\")\n")
      status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
    end
  end

  it "invalidates when the plugin root is nonempty" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      FileUtils.mkdir_p(File.join(project, ".bundle", "plugin", "cache"))
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("plugin-index")
    end
  end

  it "falls back when either switch is off" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH_DEBUG")
      ifp_with_env(project, env) do
        status, _output, errors = ifp_run(project, ["install"])
        status.should eq(0)
        ifp_stats(errors)[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
      end
    end
  end

  it "falls back on environment-signature changes" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      status, _output, errors, stats = ifp_hot(project, ["install"], {"BUNDLE_WITHOUT" => "default"})
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
    end
  end

  it "never hits when a Gemfile declares a plugin" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "true"\n))
      gemfile = File.join(project, "Gemfile")
      File.write(gemfile, File.read(gemfile) + "\nplugin \"example\"\n")
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
    end
  end

  it "never hits when plugin hooks are enabled" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "true"\n))
      FileUtils.mkdir_p(File.join(project, ".bundle", "plugin"))
      File.write(File.join(project, ".bundle", "plugin", "index"), %(---\nplugins:\n- name: example\n  hooks:\n    after-install: example\n))
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("hooks")
    end
  end

  it "conservatively falls back for output-affecting Bundler settings" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      variants = [
        {"BUNDLE_FROZEN", "frozen"},
        {"BUNDLE_DEPLOYMENT", "frozen"},
        {"BUNDLE_DISABLE_SHARED_GEMS", "shared-gems"},
        {"BUNDLE_FORCE_RUBY_PLATFORM", "force-ruby-platform"},
      ]
      variants.each do |(key, reason)|
        File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "false"\n#{key}: "true"\n))
        _status, _output, errors, stats = ifp_hot(project)
        stats[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        ifp_lines(errors, IFP_MISS).should contain(reason)
      end
      Dir.mkdir_p(File.join(project, "custom-cache"))
      File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "false"\nBUNDLE_CACHE_PATH: "custom-cache"\n))
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("app-cache")
    end
  end

  it "falls back for flags that can change install behavior" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      status, _output, errors, stats = ifp_hot(project, ["install", "--local"])
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("switches")
    end
  end
end
