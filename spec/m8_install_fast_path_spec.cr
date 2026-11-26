require "json"
require "./spec_helper"
require "./m8_fast_path_matrix_support"
require "../src/celerite/gem/platform"
require "../src/celerite/runtime_facts"
require "../src/celerite/resolution"
require "../src/celerite/install_fast_path"

private IFP_INDEX    = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))
private IFP_STATS    = /^bridge: procs=(\d+) rpc=(\d+) req_bytes=(\d+) resp_bytes=(\d+)$/
private IFP_HIT      = /^fast-path: install hit \(digest=([0-9a-f]{12})\)$/
private IFP_MISS     = /^fast-path: install miss \((.+)\)$/
private IFP_SWITCHES = %w[
  CELERITE_FAST_PATH CELERITE_FAST_PATH_DEBUG CELERITE_EVAL_CACHE
  CELERITE_CACHE_DIR CELERITE_BRIDGE_STATS CELERITE_BRIDGE_SERVER
  CELERITE_PROFILE_BUNDLER_VERSION CELERITE_REFERENCE_BUNDLER_VERSION
  CELERITE_REFERENCE_BUNDLER_LIB CELERITE_VERBOSE
  CELERITE_PLAN_CACHE CELERITE_PLAN_CACHE_DEBUG
]
private IFP_ISOLATED = %w[HOME USERPROFILE GEM_HOME GEM_PATH BUNDLE_PATH BUNDLE_WITHOUT BUNDLE_APP_CONFIG BUNDLE_USER_HOME BUNDLE_USER_PLUGIN TMPDIR TMP TEMP]

private def ifp_bin : String
  path = ENV["CELERITE_TEST_BINARY"]? || File.expand_path("../bin/celerite.exe", __DIR__)
  fail "test binary is not built: #{path}" unless File.exists?(path)
  path
end

private def ifp_env(*switches : String) : Hash(String, String)
  env = {
    "CELERITE_BRIDGE_STATS"  => "1",
    "CELERITE_BRIDGE_SERVER" => File.expand_path("../assets/bridge/server.rb", __DIR__),
  }
  switches.each { |name| env[name] = "1" }
  env
end

private def ifp_profile_env(profile : String) : Hash(String, String)
  reference_lib = if profile == "2.7.2"
                    "C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-2.7.2/lib"
                  else
                    File.expand_path("../.upstream-specs/v4.0.24/bundler/lib", __DIR__)
                  end
  {
    "CELERITE_PROFILE_BUNDLER_VERSION"   => profile,
    "CELERITE_REFERENCE_BUNDLER_VERSION" => profile,
    "CELERITE_REFERENCE_BUNDLER_LIB"     => reference_lib,
  }
end

private def ifp_dependency(name : String, gemspec_dev_dep : Bool = false) : Celerite::Bridge::EvaluatedDependency
  Celerite::Bridge::EvaluatedDependency.from_json(%({
    "name":#{name.to_json},
    "requirements":[],
    "groups":["default"],
    "platforms":[],
    "autorequire":null,
    "force_ruby_platform":null,
    "gemspec_dev_dep":#{gemspec_dev_dep},
    "source":null
  }))
end

private def ifp_evaluation(profile : String, names : Array(String),
                           dev_names : Array(String) = [] of String) : Celerite::Bridge::GemfileEvaluation
  dependencies = names.map { |name| ifp_dependency(name) }
  dependencies.concat(dev_names.map { |name| ifp_dependency(name, true) })
  Celerite::Bridge::GemfileEvaluation.from_json(%({
    "gemfile":"Gemfile",
    "dependencies":#{dependencies.to_json},
    "sources":[],
    "ruby":null,
    "ruby_version":null,
    "ruby_patchlevel":null,
    "ruby_engine":null,
    "ruby_engine_version":null,
    "bundler_version":#{profile.to_json},
    "gemfile_sha256":#{("0" * 64).to_json},
    "warnings":[]
  }))
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

private def ifp_ready(project : String, profile : String = "4.0.24",
                      overrides : Hash(String, String) = {} of String => String) : Nil
  pending!("no Ruby interpreter on PATH for the bridge") unless ruby_available?
  File.write(File.join(project, "Gemfile"), %(source "#{IFP_INDEX}"\n\neval_gemfile "extra.rb"\n))
  File.write(File.join(project, "extra.rb"), %(gem "json_pure"\n))
  FileUtils.mkdir_p(File.join(project, ".bundle"))
  # Leave BUNDLE_PLUGINS unset: task-269's zero-Ruby guarantee is for the
  # default plugins=true configuration, not the legacy explicit-false fixture.
  env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
  env.merge!(ifp_profile_env(profile))
  env.merge!(overrides)
  ifp_with_env(project, env) do
    status, output, errors = ifp_run(project, ["install"])
    fail "cold install failed (#{status}): #{output} #{errors}" unless status == 0
    ifp_stats(errors)[0].should be >= 1
    ifp_assert_install_certificate(project)
  end
end

private def ifp_assert_install_certificate(project : String) : Nil
  record_path = ifp_record_path(project)
  fail "cold install did not publish a v2 RuntimeRecord" unless record_path
  record = JSON.parse(File.read(record_path)).as_h
  nonce = record["certificate_nonce"].as_s
  nonce.should match(/\A[0-9a-f]{32}\z/)

  entry_path = ifp_entry_path(project, record["eval_digest"].as_s)
  fail "cold install did not publish a v2 eval entry" unless entry_path
  entry = JSON.parse(File.read(entry_path)).as_h
  certificate = entry["certificates"].as_h[nonce]?.not_nil!
  certificate["command"].as_s.should eq("install")
  certificate.as_h.keys.should_not contain("plan_digest")
  certificate["install"].as_h["plan_digest"].as_s.should match(/\A[0-9a-f]{64}\z/)
  certificate["plugin"].as_h["certificate_nonce"].as_s.should eq(nonce)

  plugin_path = ifp_plugin_path(project, entry["digest"].as_s)
  fail "cold install did not publish a v2 plugin certificate" unless plugin_path
  plugin = JSON.parse(File.read(plugin_path)).as_h
  plugin["format"].as_s.should eq("celerite-plugin-gemfile-cache/2")
  plugin["digest"].as_s.should eq(entry["digest"].as_s)
  plugin["certificate_nonce"].as_s.should eq(nonce)
end

private def ifp_plan_cache_root(project : String) : String
  File.join(File.dirname(project), "#{File.basename(project)}-plan-cache")
end

private def ifp_plan_entries(project : String, root : String = ifp_plan_cache_root(project)) : Array(String)
  layout = File.join(root, "plan", "v1")
  Celerite::Glob.paths(layout, "*").flat_map do |namespace|
    Celerite::Glob.paths(namespace, "*.json")
  end
end

private def ifp_wait_for_plan_entry(project : String, root : String = ifp_plan_cache_root(project)) : String
  200.times do
    if entry = ifp_plan_entries(project, root).first?
      return entry
    end
    sleep 10.milliseconds
  end
  fail "locked-plan cache entry was not published for #{project}"
end

private def ifp_ready_remote(project : String, profile : String = "4.0.24",
                             overrides : Hash(String, String) = {} of String => String) : Nil
  ifp_ready(project, profile, overrides)
  remote = "https://example.invalid/"
  File.write(File.join(project, "Gemfile"), %(source "#{remote}"\n\neval_gemfile "extra.rb"\n))
  lockfile = File.join(project, "Gemfile.lock")
  File.write(lockfile, File.read(lockfile).gsub(IFP_INDEX, remote))
  cache = File.join(project, "vendor", "cache")
  Dir.mkdir_p(cache)
  Celerite::Glob.paths(File.expand_path("../fixtures/gem-index/gems", __DIR__), "*.gem").each do |gem|
    FileUtils.cp(gem, File.join(cache, File.basename(gem)))
  end
  FileUtils.rm_rf(File.join(project, ".celerite"))
  env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
  env["CELERITE_PLAN_CACHE"] = "0"
  env["CELERITE_CACHE_DIR"] = ifp_plan_cache_root(project)
  env.merge!(ifp_profile_env(profile))
  env.merge!(overrides)
  ifp_with_env(project, env) do
    status, output, errors = ifp_run(project, ["install", "--local"])
    fail "remote cold install failed (#{status}): #{output} #{errors}" unless status == 0
    ifp_stats(errors)[0].should be >= 1
    # trusted_attempt itself requires a persistent EvalCache entry. The cold
    # --local install creates it; a no-op install makes the fixture genuinely
    # warm before any P3 hit/miss assertion.
    status, output, errors = ifp_run(project, ["install"])
    fail "remote warm install failed (#{status}): #{output} #{errors}" unless status == 0
    status, output, errors = ifp_run(project, ["install"])
    fail "remote trusted warm install failed (#{status}): #{output} #{errors}" unless status == 0
    errors.should_not contain("fast-path: install miss (entry)")
  end
end

private def ifp_matrix_parity(project : String, args : Array(String) = ["install"]) : Nil
  archive = File.join(Dir.tempdir, "celerite-m8-install-matrix-#{Process.pid}-#{Random.rand(1_000_000)}")
  m8_matrix_snapshot(project, archive)
  begin
    reference_env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_BRIDGE_STATS")
    reference_env["CELERITE_FAST_PATH"] = "0"
    ifp_with_env(project, reference_env) do
      m8_matrix_restore(project, archive)
      reference = m8_matrix_run(project, args)
      reference_tree = m8_matrix_tree(project)
      ifp_with_env(project, ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_BRIDGE_STATS")) do
        m8_matrix_restore(project, archive)
        candidate = m8_matrix_run(project, args)
        candidate_tree = m8_matrix_tree(project)
        m8_matrix_assert_compat_parity(reference, candidate, project, reference_tree, candidate_tree)
      end
    end
  ensure
    FileUtils.rm_rf(archive)
  end
end

private def ifp_compatible(project : String, profile : String = "4.0.24") : {Int32, String, String}
  env = ifp_env("CELERITE_EVAL_CACHE")
  env.merge!(ifp_profile_env(profile))
  result = {0, "", ""}
  ifp_with_env(project, env) do
    result = ifp_run(project, ["install"])
  end
  result
end

private def ifp_hot(project : String, args = ["install"], overrides = {} of String => String,
                    profile : String = "4.0.24") : {Int32, String, String, Tuple(Int32, Int32, Int32, Int32)}
  env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
  env["CELERITE_PLAN_CACHE_DEBUG"] = "1" if overrides["CELERITE_PLAN_CACHE"]? == "1"
  env.merge!(ifp_profile_env(profile))
  env.merge!(overrides)
  result = {0, "", "", {0, 0, 0, 0}}
  ifp_with_env(project, env) do
    status, output, errors = ifp_run(project, args)
    result = {status, output, errors, ifp_stats(errors)}
  end
  result
end

private def ifp_user_stderr(errors : String) : String
  errors.lines.reject do |line|
    line.starts_with?("bridge: procs=") || line.starts_with?("fast-path: install ")
  end.join
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

private def ifp_cache_entries(project : String, root : String = File.join(project, ".celerite", "cache", "eval")) : Array(String)
  Celerite::Glob.paths(root, "*").flat_map do |namespace|
    Celerite::Glob.paths(File.join(namespace, "v2"), "*").compact_map do |digest|
      path = File.join(digest, "entry.json")
      path if File.file?(path)
    end
  end
end

private def ifp_plugin_certificates(project : String) : Array(String)
  base = File.join(project, ".celerite", "cache", "plugin-gemfile", "v2")
  Celerite::Glob.paths(base, "*").map { |digest| File.join(digest, "certificate.json") }
end

private def ifp_entry_path(project : String, digest : String? = nil) : String
  digest ||= JSON.parse(File.read(ifp_record_path(project)))["eval_digest"].as_s
  path = ifp_cache_entries(project).find { |entry| File.basename(File.dirname(entry)) == digest }
  fail "missing v2 eval entry #{digest} for #{project}" unless path
  path.not_nil!
end

private def ifp_plugin_path(project : String, digest : String? = nil) : String
  digest ||= JSON.parse(File.read(ifp_record_path(project)))["eval_digest"].as_s
  path = ifp_plugin_certificates(project).find { |entry| File.basename(File.dirname(entry)) == digest }
  fail "missing v2 plugin certificate #{digest} for #{project}" unless path
  path.not_nil!
end

private def ifp_plugin_trusted?(project : String, digest : String, nonce : String) : Bool
  env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH")
    .merge(ifp_profile_env("4.0.24"))
  trusted = false
  ifp_with_env(project, env) do
    trusted = Celerite::PluginGemfileCache.trusted?(digest, nonce)
  end
  trusted
end

private def ifp_record_path(project : String, root : String = File.join(project, ".celerite", "cache")) : String
  layout = File.join(root, "fast-path", "v2")
  Celerite::Glob.paths(layout, "*").flat_map do |namespace|
    Celerite::Glob.paths(namespace, "*.json")
  end.first? || fail("missing v2 RuntimeRecord for #{project}")
end

private def ifp_record_nonce(project : String, root : String = File.join(project, ".celerite", "cache")) : String
  JSON.parse(File.read(ifp_record_path(project, root)))["certificate_nonce"].as_s
end

private def ifp_trusted_install_result(project : String) : {Celerite::LockFastPath::Hit?, String?}
  env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH")
    .merge(ifp_profile_env("4.0.24"))
  hit : Celerite::LockFastPath::Hit? = nil
  reason : String? = nil
  ifp_with_env(project, env) do
    hit, reason = Celerite::LockFastPath.trusted_attempt(Celerite::Definition.build, "install")
  end
  {hit, reason}
end

private def ifp_trusted_install(project : String) : Celerite::LockFastPath::Hit?
  hit, _reason = ifp_trusted_install_result(project)
  hit
end

private def ifp_assert_trusted_install(project : String, nonce : String) : Celerite::LockFastPath::Hit
  hit, reason = ifp_trusted_install_result(project)
  fail "old nonce #{nonce} is not trusted: #{reason.inspect}" unless hit
  hit.not_nil!.record.certificate_nonce.should eq(nonce)
  hit.not_nil!
end

private def ifp_plan_digest(project : String) : String
  nonce = ifp_record_nonce(project)
  entry = JSON.parse(File.read(ifp_entry_path(project)))
  entry["certificates"].as_h[nonce].as_h["install"].as_h["plan_digest"].as_s
end

private def ifp_computed_plan_digest(project : String) : String
  lock = Celerite::Lockfile::Parser.parse(File.read(File.join(project, "Gemfile.lock")))
  install_root = File.join(project, "bundle", "ruby", ifp_abi)
  Celerite::InstallFastPath.plan_digest(lock, install_root, ifp_abi).not_nil!
end

private def ifp_ruby_files(root : String) : Array(String)
  Celerite::Glob.paths(root, "*").flat_map do |path|
    if File.symlink?(path)
      [] of String
    elsif File.directory?(path)
      ifp_ruby_files(path)
    elsif File.file?(path) && path.ends_with?(".rb")
      [path]
    else
      [] of String
    end
  end.sort
end

private def ifp_mutate_installed_content(project : String) : {String, String}
  full_name = ifp_full_name(project)
  gem_dir = ifp_installed_file(project, "gems", full_name)
  path = ifp_ruby_files(gem_dir).first? || fail("missing installed Ruby content")
  original = File.read(path)
  File.write(path, original + "\n# task-274 plan digest mutation\n")
  {path, original}
end

private def ifp_failing_hook(project : String) : Nil
  plugin_root = File.join(project, "failing-plugin")
  Dir.mkdir_p(File.join(plugin_root, "lib"))
  File.write(File.join(plugin_root, "plugins.rb"), "require \"failing_plugin\"\n")
  File.write(File.join(plugin_root, "lib", "failing_plugin.rb"),
    %(Bundler::Plugin.add_hook("after-install") { |_ctx| raise "task-274 hook failure" }\n))
  index = File.join(project, ".bundle", "plugin", "index")
  Dir.mkdir_p(File.dirname(index))
  File.write(index, <<-YAML)
  ---
  commands:
  hooks:
    after-install:
    - "failing_plugin"
  load_paths:
    failing_plugin:
    - "#{File.join(plugin_root, "lib").gsub('\\', "/")}"
  plugin_paths:
    failing_plugin: "#{plugin_root.gsub('\\', "/")}"
  sources:
  YAML
end

private def ifp_rename_indexed_spec(project : String, full_name : String,
                                    renamed_name : String, renamed : String) : Nil
  File.rename(ifp_installed_file(project, "specifications", "#{full_name}.gemspec"),
    ifp_installed_file(project, "specifications", "#{renamed}.gemspec"))
  File.rename(ifp_installed_file(project, "gems", full_name),
    ifp_installed_file(project, "gems", renamed))
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

describe "Celerite::InstallSummary" do
  it "counts Bundler for 2.x and switched runs without counting gemspec development dependencies" do
    evaluation = ifp_evaluation("4.0.24", ["json_pure"], ["dev_only"])
    current = Celerite::InstallSummary.build(evaluation, ["json_pure"], [] of String,
      [] of String, false, "4.0.24", :empty, "")
    current.deps_count.should eq(1)
    current.gems_count.should eq(1)
    Celerite::InstallSummary.complete_line(current).should eq(
      "Bundle complete! 1 Gemfile dependency, 1 gem now installed.")

    legacy = Celerite::InstallSummary.build(evaluation, ["json_pure"], [] of String,
      [] of String, false, "2.7.2", :empty, "")
    legacy.gems_count.should eq(2)
    Celerite::InstallSummary.complete_line(legacy).should eq(
      "Bundle complete! 1 Gemfile dependency, 2 gems now installed.")

    switched = Celerite::InstallSummary.build(evaluation, ["json_pure"], [] of String,
      [] of String, true, "4.0.24", :empty, "")
    switched.gems_count.should eq(2)
  end

  it "hides an inferred typed-source gem from both dependency and spec counts" do
    evaluation = ifp_evaluation("4.0.24", ["stub-gem", "bundler-source-mpath"], ["dev_only"])
    summary = Celerite::InstallSummary.build(evaluation,
      ["stub-gem", "bundler-source-mpath"], ["bundler-source-mpath"],
      [] of String, false, "4.0.24", :relative, "./vendor/bundle")
    summary.deps_count.should eq(1)
    summary.gems_count.should eq(1)
    Celerite::InstallSummary.complete_line(summary).should eq(
      "Bundle complete! 1 Gemfile dependency, 1 gem now installed.")
    Celerite::InstallSummary.path_line(summary).should eq(
      "Bundled gems are installed into `./vendor/bundle`")
  end

  it "renders skipped groups and all path hints with the compatible wording" do
    evaluation = ifp_evaluation("4.0.24", [] of String)
    summary = Celerite::InstallSummary.build(evaluation, [] of String, [] of String,
      ["test", "development"], false, "4.0.24", :relative, "./bundle")
    Celerite::InstallSummary.skipped_groups_line(summary).should eq(
      "Gems in the groups 'test' and 'development' were not installed.")
    Celerite::InstallSummary.path_line(summary).should eq(
      "Bundled gems are installed into `./bundle`")

    empty = Celerite::InstallSummary.build(evaluation, [] of String, [] of String,
      [] of String, false, "4.0.24", :empty, "")
    Celerite::InstallSummary.skipped_groups_line(empty).should be_nil
    Celerite::InstallSummary.path_line(empty).should eq("Bundled gems are installed into `./.`")

    system = Celerite::InstallSummary.build(evaluation, [] of String, [] of String,
      ["test"], false, "4.0.24", :system, "")
    Celerite::InstallSummary.skipped_groups_line(system).should eq(
      "Gems in the group 'test' were not installed.")
    Celerite::InstallSummary.path_line(system).should eq(
      "Use `bundle info [gemname]` to see where a bundled gem is installed.")
  end
end

describe "install takes the no-Ruby fast path on an unchanged project" do
  it "uses one Ruby process on the cold install and zero processes/rpc/bytes on the default-plugin hot install" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      status, output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats.should eq({0, 0, 0, 0})
      ifp_lines(errors, IFP_HIT).size.should eq(1)
      output.should contain("Bundle complete! 1 Gemfile dependency, 1 gem now installed.")
    end
  end

  it "rotates the install and plugin nonce on a hot hit while retaining the old eval certificate" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      old_nonce = ifp_record_nonce(project)
      entry_path = ifp_entry_path(project)
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats.should eq({0, 0, 0, 0})
      new_nonce = ifp_record_nonce(project)
      new_nonce.should_not eq(old_nonce)

      entry = JSON.parse(File.read(entry_path))
      entry["certificates"].as_h.keys.should contain(old_nonce)
      entry["certificates"].as_h.keys.should contain(new_nonce)
      plugin = JSON.parse(File.read(ifp_plugin_certificates(project).first))
      plugin["certificate_nonce"].as_s.should eq(new_nonce)
    end
  end

  it "misses when only RuntimeRecord is deleted even if both certificates remain" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      entry_path = ifp_entry_path(project)
      plugin_path = ifp_plugin_path(project)
      File.delete(ifp_record_path(project))
      File.file?(entry_path).should be_true
      File.file?(plugin_path).should be_true
      ifp_trusted_install(project).should be_nil

      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("record")
    end
  end

  it "does not accept a lock command certificate for install" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      nonce = ifp_record_nonce(project)
      entry_path = ifp_entry_path(project)
      payload = JSON.parse(File.read(entry_path)).as_h
      certificate = payload["certificates"].as_h[nonce].as_h
      certificate["command"] = JSON::Any.new("lock")
      certificate.delete("plugin")
      certificate.delete("install")
      payload["certificates"].as_h[nonce] = JSON::Any.new(certificate)
      File.write(entry_path, payload.to_json)

      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("verdict:certificate-command")
    end
  end

  it "revalidates the installed tree under ProcessLock before emitting a hot hit" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      mutated_path : String? = nil
      original : String? = nil
      env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
        .merge(ifp_profile_env("4.0.24"))
      begin
        Celerite::InstallFastPath.after_attempt =
          ->(_definition : Celerite::Definition, _config : Celerite::Config) do
            path, bytes = ifp_mutate_installed_content(project)
            mutated_path = path
            original = bytes
            nil
          end
        code, output, errors = ifp_with_env(project, env) do
          Dir.cd(project) { run_cli(["install"]) }
        end
        fail "stale compatibility fallback failed: #{output}\n#{errors}" unless code == 0
        code.should eq(0)
        ifp_stats(errors)[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        ifp_lines(errors, IFP_MISS).should contain("stale")
        output.scan("Bundle complete!").size.should eq(1)
      ensure
        Celerite::InstallFastPath.after_attempt = nil
        if path = mutated_path
          File.write(path, original.not_nil!)
        end
      end
    end
  end

  it "revalidates raw lock identity under ProcessLock and discards the stale trusted result" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      lock_path = File.join(project, "Gemfile.lock")
      original = File.read(lock_path)
      env = ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_FAST_PATH_DEBUG")
        .merge(ifp_profile_env("4.0.24"))
      begin
        Celerite::InstallFastPath.after_attempt =
          ->(_definition : Celerite::Definition, _config : Celerite::Config) do
            File.write(lock_path, original + "\n# task-274 attempt-to-lock mutation\n")
            nil
          end
        code, output, errors = ifp_with_env(project, env) do
          Dir.cd(project) { run_cli(["install"]) }
        end
        fail "stale compatibility fallback failed: #{output}\n#{errors}" unless code == 0
        code.should eq(0)
        ifp_stats(errors)[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        ifp_lines(errors, IFP_MISS).should contain("stale")
        output.scan("Bundle complete!").size.should eq(1)
      ensure
        Celerite::InstallFastPath.after_attempt = nil
        File.write(lock_path, original)
      end
    end
  end

  it "hashes installed plan content deterministically and ignores cache, vendor/cache and unrelated platforms" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      old_digest = ifp_computed_plan_digest(project)
      ifp_plan_digest(project).should eq(old_digest)
      FileUtils.mkdir_p(File.join(project, ".celerite", "cache", "noise"))
      File.write(File.join(project, ".celerite", "cache", "noise", "payload"), "ignored")
      FileUtils.mkdir_p(File.join(project, "vendor", "cache"))
      File.write(File.join(project, "vendor", "cache", "payload"), "ignored")
      extra = "#{ifp_full_name(project)}-x86_64-unknown"
      File.write(ifp_installed_file(project, "specifications", "#{extra}.gemspec"), "ignored")
      FileUtils.mkdir_p(ifp_installed_file(project, "gems", extra))
      ifp_computed_plan_digest(project).should eq(old_digest)
      FileUtils.rm_rf(File.join(project, ".celerite", "cache", "noise"))
      FileUtils.rm_rf(File.join(project, "vendor", "cache"))

      path, original = ifp_mutate_installed_content(project)
      begin
        ifp_computed_plan_digest(project).should_not eq(old_digest)
        status, _output, errors, stats = ifp_hot(project)
        status.should eq(0)
        stats[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        ifp_lines(errors, IFP_MISS).should contain("plan-digest")
        ifp_plan_digest(project).should_not eq(old_digest)

        status, _output, errors, stats = ifp_hot(project)
        status.should eq(0)
        stats.should eq({0, 0, 0, 0})
        ifp_lines(errors, IFP_HIT).size.should eq(1)
      ensure
        File.write(path, original)
      end
    end
  end

  it "preserves the old nonce and all commit markers when an after-install hook fails" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      old_nonce = ifp_record_nonce(project)
      record_path = ifp_record_path(project)
      record_before = File.read(record_path)
      plugin_path = ifp_plugin_path(project)
      plugin_before = File.read(plugin_path)
      ifp_failing_hook(project)

      status, _output, _errors, stats = ifp_hot(project)
      status.should_not eq(0)
      stats[0].should be >= 1
      ifp_record_nonce(project).should eq(old_nonce)
      File.read(record_path).should eq(record_before)
      File.read(plugin_path).should eq(plugin_before)
    end
  end

  it "rolls back the replaced plugin certificate when the final RuntimeRecord write fails" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      old_nonce = ifp_record_nonce(project)
      record_path = ifp_record_path(project)
      record_before = File.read(record_path)
      lock_path = File.join(project, "Gemfile.lock")
      lock_before = File.read(lock_path)
      entry_path = ifp_entry_path(project)
      entry_before = File.read(entry_path)
      plugin_path = ifp_plugin_path(project)
      plugin_before = File.read(plugin_path)
      path, original = ifp_mutate_installed_content(project)
      File.delete(record_path)
      Dir.mkdir_p(record_path)
      begin
        status, _output, errors, stats = ifp_hot(project)
        status.should eq(0)
        stats[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        File.read(entry_path).should eq(entry_before)
        File.read(plugin_path).should eq(plugin_before)
        Dir.exists?(record_path).should be_true
        ifp_trusted_install(project).should be_nil
      ensure
        FileUtils.rm_rf(record_path)
        File.write(record_path, record_before)
        File.write(lock_path, lock_before)
        File.write(path, original)
      end

      trusted = ifp_assert_trusted_install(project, old_nonce)
      trusted.record.certificate_nonce.should eq(old_nonce)
      ifp_plugin_trusted?(project, trusted.digest, old_nonce).should be_true
    end
  end

  it "keeps the old RuntimeRecord and restores old-nonce usability when the plugin certificate write fails" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      old_nonce = ifp_record_nonce(project)
      record_path = ifp_record_path(project)
      record_before = File.read(record_path)
      lock_path = File.join(project, "Gemfile.lock")
      lock_before = File.read(lock_path)
      entry_path = ifp_entry_path(project)
      entry_before = File.read(entry_path)
      plugin_path = ifp_plugin_path(project)
      plugin_before = File.read(plugin_path)
      path, original = ifp_mutate_installed_content(project)
      File.delete(plugin_path)
      Dir.mkdir_p(plugin_path)
      begin
        status, _output, errors, stats = ifp_hot(project)
        status.should eq(0)
        stats[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        File.read(entry_path).should eq(entry_before)
        ifp_record_nonce(project).should eq(old_nonce)
        File.read(record_path).should eq(record_before)
        trusted = ifp_trusted_install(project)
        trusted.should_not be_nil
        trusted.not_nil!.record.certificate_nonce.should eq(old_nonce)
        ifp_plugin_trusted?(project, trusted.not_nil!.digest, old_nonce).should be_false
      ensure
        FileUtils.rm_rf(plugin_path)
        File.write(plugin_path, plugin_before)
        File.write(lock_path, lock_before)
        File.write(path, original)
      end

      trusted = ifp_assert_trusted_install(project, old_nonce)
      trusted.record.certificate_nonce.should eq(old_nonce)
      ifp_plugin_trusted?(project, trusted.digest, old_nonce).should be_true
    end
  end

  it "never false-hits from the old record while the eval entry cannot be written" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      old_nonce = ifp_record_nonce(project)
      record_path = ifp_record_path(project)
      record_before = File.read(record_path)
      lock_path = File.join(project, "Gemfile.lock")
      lock_before = File.read(lock_path)
      entry_path = ifp_entry_path(project)
      entry_before = File.read(entry_path)
      plugin_path = ifp_plugin_path(project)
      plugin_before = File.read(plugin_path)
      File.delete(entry_path)
      Dir.mkdir_p(entry_path)
      begin
        status, _output, errors, stats = ifp_hot(project)
        status.should eq(0)
        stats[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        ifp_record_nonce(project).should eq(old_nonce)
        File.read(record_path).should eq(record_before)
        File.read(plugin_path).should eq(plugin_before)
        ifp_trusted_install(project).should be_nil
      ensure
        FileUtils.rm_rf(entry_path)
        File.write(entry_path, entry_before)
        File.write(lock_path, lock_before)
      end

      trusted = ifp_assert_trusted_install(project, old_nonce)
      trusted.record.certificate_nonce.should eq(old_nonce)
    end
  end

  {"4.0.24" => 1, "2.7.2" => 2}.each do |profile, expected_gems|
    it "prints the same no-op transcript and lock bytes as the compatible install under #{profile}" do
      with_project({} of String => String) do |project|
        ifp_ready(project, profile)
        lock_path = File.join(project, "Gemfile.lock")
        lock_before = File.read(lock_path)
        baseline = ifp_compatible(project, profile)
        baseline[0].should eq(0)
        baseline[1].should contain("Bundle complete! 1 Gemfile dependency, #{expected_gems} gem#{expected_gems == 1 ? "" : "s"} now installed.")
        File.read(lock_path).should eq(lock_before)
        2.times do
          status, output, errors, stats = ifp_hot(project, ["install"], {} of String => String, profile)
          status.should eq(baseline[0])
          stats.should eq({0, 0, 0, 0})
          ifp_lines(errors, IFP_HIT).size.should eq(1)
          output.should eq(baseline[1])
          ifp_user_stderr(errors).should eq(ifp_user_stderr(baseline[2]))
          File.read(lock_path).should eq(lock_before)
        end
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
      ifp_lines(errors, IFP_MISS).should contain("install-index:#{full_name}")
    end
  end

  it "invalidates native marker content and re-mints only after a compatible install" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      ifp_mark_native_complete(project, ifp_full_name(project))
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("plan-digest")

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

  it "falls back when the global plugin root or index is nonempty" do
    with_project({} of String => String) do |project|
      global_root = File.join(project, "global-plugin")
      override = {"BUNDLE_USER_PLUGIN" => global_root}
      ifp_ready(project, "4.0.24", override)
      FileUtils.mkdir_p(File.join(global_root, "cache"))
      _status, _output, errors, stats = ifp_hot(project, ["install"], override)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("hooks")

      FileUtils.rm_rf(global_root)
      FileUtils.mkdir_p(global_root)
      File.write(File.join(global_root, "index"), %(---\nplugins:\n- name: example\n))
      _status, _output, errors, stats = ifp_hot(project, ["install"], override)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("hooks")
    end
  end

  it "still hits with zero-byte local and global plugin indexes" do
    with_project({} of String => String) do |project|
      local_root = File.join(project, ".bundle", "plugin")
      global_root = File.join(project, "global-plugin")
      override = {"BUNDLE_USER_PLUGIN" => global_root}
      ifp_ready(project, "4.0.24", override)
      FileUtils.mkdir_p(local_root)
      FileUtils.mkdir_p(global_root)
      File.write(File.join(local_root, "index"), "")
      File.write(File.join(global_root, "index"), "")
      status, _output, errors, stats = ifp_hot(project, ["install"], override)
      status.should eq(0)
      stats.should eq({0, 0, 0, 0})
      ifp_lines(errors, IFP_HIT).size.should eq(1)
    end
  end

  it "falls back when the empty-plugin certificate is missing or corrupt" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      certificate = ifp_plugin_certificates(project).first
      payload = JSON.parse(File.read(certificate))
      payload["format"].as_s.should eq("celerite-plugin-gemfile-cache/2")
      payload["plugin_names"].as_a.should be_empty
      payload["certificate_nonce"].as_s.should match(/\A[0-9a-f]{32}\z/)
      payload.as_h.keys.sort.should eq(["certificate_nonce", "digest", "format", "plugin_names"])

      File.delete(certificate)
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("hooks")

      certificate = ifp_plugin_certificates(project).first
      File.write(certificate, "{not-json")
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("hooks")
    end
  end

  it "falls back when the plugin certificate nonce does not match the RuntimeRecord" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      certificate = ifp_plugin_certificates(project).first
      payload = JSON.parse(File.read(certificate)).as_h
      payload["certificate_nonce"] = JSON::Any.new("f" * 32)
      File.write(certificate, payload.to_json)
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("hooks")
    end
  end

  it "replaces a preexisting certificate by direct rename without target deletion or temp residue" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      certificate = ifp_plugin_certificates(project).first
      payload = JSON.parse(File.read(certificate))
      digest = payload["digest"].as_s
      replacement = payload.to_json + "\n"

      ifp_with_env(project, ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH")) do
        Celerite::PluginGemfileCache.write(digest, replacement).should be_true
      end
      File.read(certificate).should eq(replacement)
      Dir.children(File.dirname(certificate)).sort.should eq(["certificate.json"])

      source_path = File.expand_path("../src/celerite/plugin_gemfile_cache.cr", __DIR__)
      source = File.read(source_path)
      source.should_not contain("File.delete(target)")
      source.should contain("File.rename(temp, target)")
    end
  end

  it "invalidates the plugin certificate when the evaluation chain changes" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      old_certificate = ifp_plugin_certificates(project).first
      extra = File.join(project, "extra.rb")
      File.write(extra, File.read(extra) + "\n# fingerprint invalidation\n")
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("entry")
      ifp_plugin_certificates(project).size.should eq(2)
      File.exists?(old_certificate).should be_true
    end
  end

  it "does not skip plugin preflight when the cached evaluation has warnings" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      certificate = ifp_plugin_certificates(project).first
      certificate_before = File.read(certificate)
      entry = ifp_cache_entries(project).first
      payload = JSON.parse(File.read(entry)).as_h
      payload["evaluation"].as_h["warnings"] = JSON::Any.new([JSON::Any.new("fixture warning")])
      File.write(entry, payload.to_json)

      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("warnings")
      File.read(certificate).should eq(certificate_before)
    end
  end

  it "does not statically guess a plugin declared through dynamic DSL" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      gemfile = File.join(project, "Gemfile")
      File.write(gemfile, File.read(gemfile) + %(\neval("plugin 'example'")\n))
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
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

  it "never hits when plugin hooks are enabled and the plugin root is nonempty" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "true"\n))
      FileUtils.mkdir_p(File.join(project, ".bundle", "plugin"))
      File.write(File.join(project, ".bundle", "plugin", "index"), %(---\nplugins:\n- name: example\n  hooks:\n    after-install: example\n))
      _status, _output, errors, stats = ifp_hot(project)
      stats[0].should be >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("plugin-index")
    end
  end

  it "conservatively falls back for output-affecting Bundler settings" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      warm = File.join(Dir.tempdir, "celerite-m8-install-settings-#{Process.pid}-#{Random.rand(1_000_000)}")
      m8_matrix_snapshot(project, warm)
      begin
        variants = [
          {"BUNDLE_FROZEN", "frozen"},
          {"BUNDLE_DEPLOYMENT", "frozen"},
          {"BUNDLE_DISABLE_SHARED_GEMS", "shared-gems"},
          {"BUNDLE_FORCE_RUBY_PLATFORM", "force-ruby-platform"},
        ]
        variants.each do |(key, reason)|
          m8_matrix_restore(project, warm)
          File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "false"\n#{key}: "true"\n))
          _status, _output, errors, stats = ifp_hot(project)
          stats[0].should be >= 1
          ifp_lines(errors, IFP_HIT).should be_empty
          ifp_lines(errors, IFP_MISS).should contain(reason)
        end
        m8_matrix_restore(project, warm)
        Dir.mkdir_p(File.join(project, "custom-cache"))
        File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "false"\nBUNDLE_CACHE_PATH: "custom-cache"\n))
        _status, _output, errors, stats = ifp_hot(project)
        stats[0].should be >= 1
        ifp_lines(errors, IFP_HIT).should be_empty
        ifp_lines(errors, IFP_MISS).should contain("app-cache")
      ensure
        FileUtils.rm_rf(warm)
      end
    end
  end

  it "keeps CELERITE_FAST_PATH=0 on the compatibility path and preserves full hot-path parity" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      reference = nil.as(M8MatrixRun?)
      reference_tree = {} of String => String
      ifp_with_env(project, ifp_env("CELERITE_EVAL_CACHE", "CELERITE_BRIDGE_STATS").merge({"CELERITE_FAST_PATH" => "0"})) do
        reference = m8_matrix_run(project, ["install"])
        reference_tree = m8_matrix_tree(project)
      end
      ifp_with_env(project, ifp_env("CELERITE_EVAL_CACHE", "CELERITE_FAST_PATH", "CELERITE_BRIDGE_STATS")) do
        candidate = m8_matrix_run(project, ["install"])
        candidate_tree = m8_matrix_tree(project)
        reference.not_nil!.procs.should be >= 1
        candidate.status.should eq(reference.not_nil!.status)
        m8_matrix_normalize(candidate.stdout, project).should eq(m8_matrix_normalize(reference.not_nil!.stdout, project))
        m8_matrix_normalize(m8_matrix_observable_stderr(candidate), project)
          .should eq(m8_matrix_normalize(m8_matrix_observable_stderr(reference.not_nil!), project))
        candidate_tree.should eq(reference_tree)
        candidate.procs.should eq(0)
        candidate.rpc.should eq(0)
        candidate.req_bytes.should eq(0)
        candidate.resp_bytes.should eq(0)
      end
    end
  end

  it "rejects missing specifications, gem directories and native markers with full compatibility parity" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      full_name = ifp_full_name(project)
      warm = File.join(Dir.tempdir, "celerite-m8-install-warm-#{Process.pid}-#{Random.rand(1_000_000)}")
      m8_matrix_snapshot(project, warm)
      begin
        m8_matrix_restore(project, warm)
        File.delete(ifp_installed_file(project, "specifications", "#{full_name}.gemspec"))
        ifp_matrix_parity(project)

        m8_matrix_restore(project, warm)
        FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
        ifp_matrix_parity(project)

        m8_matrix_restore(project, warm)
        ifp_mark_native_complete(project, full_name)
        ext = File.join(File.dirname(File.dirname(ifp_installed_file(project, "specifications", "#{full_name}.gemspec"))),
          "extensions", Celerite::Gem::Platform.local.to_s, ifp_abi, full_name)
        File.delete(File.join(ext, "gem.build_complete"))
        Dir.exists?(ext).should be_true
        ifp_matrix_parity(project)
      ensure
        FileUtils.rm_rf(warm)
      end
    end
  end

  it "rejects broken fingerprints, unknown runtimes and corrupt records with full compatibility parity" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      entry = ifp_cache_entries(project).first
      original_entry = File.read(entry)
      payload = JSON.parse(original_entry).as_h
      payload["fingerprint"].as_h["state"] = JSON::Any.new("broken")
      File.write(entry, payload.to_json)
      ifp_matrix_parity(project)

      File.write(entry, original_entry)
      record_path = ifp_record_path(project)
      original_record = File.read(record_path)
      record = JSON.parse(original_record).as_h
      record["engine"] = JSON::Any.new("jruby")
      record["engine_version"] = JSON::Any.new("9.4.0.0")
      File.write(record_path, record.to_json)
      ifp_matrix_parity(project)

      File.write(record_path, "not json\n")
      ifp_matrix_parity(project)
    end
  end

  it "rejects project gemspec additions and changes with full compatibility parity" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      gemspec = File.join(project, "demo.gemspec")
      File.write(gemspec, <<-CRYSTAL)
        Gem::Specification.new do |s|
          s.name = "demo"
          s.version = "1.0.0"
          s.summary = "first"
          s.authors = ["celerite"]
          s.files = []
        end
        CRYSTAL
      gemfile = File.join(project, "Gemfile")
      File.write(gemfile, File.read(gemfile) + "\ngemspec\n")
      ifp_matrix_parity(project)
      File.write(gemspec, File.read(gemspec).sub(%q(s.summary = "first"), %q(s.summary = "changed")))
      ifp_matrix_parity(project)
    end
  end

  it "rejects dynamic DSL and plugin hooks with full compatibility parity" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      warm = File.join(Dir.tempdir, "celerite-m8-install-dsl-#{Process.pid}-#{Random.rand(1_000_000)}")
      m8_matrix_snapshot(project, warm)
      begin
        gemfile = File.join(project, "Gemfile")
        File.write(gemfile, File.read(gemfile) + "\neval(\"gem 'json_pure'\")\n")
        ifp_matrix_parity(project)

        m8_matrix_restore(project, warm)
        File.write(File.join(project, ".bundle", "config"), %(BUNDLE_PLUGINS: "true"\n))
        plugin_root = File.join(project, ".bundle", "plugin")
        Dir.mkdir_p(plugin_root)
        File.write(File.join(plugin_root, "index"), %(---\nplugins:\n- name: example\n  hooks:\n    after-install: example\n))
        ifp_matrix_parity(project)
      ensure
        FileUtils.rm_rf(warm)
      end
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

  it "rehydrates a trusted locked plan after an install no-op miss" do
    with_project({} of String => String) do |project|
      ifp_ready_remote(project)
      full_name = ifp_full_name(project)
      env = {"CELERITE_PLAN_CACHE" => "1",
             "CELERITE_CACHE_DIR"  => ifp_plan_cache_root(project)}
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      status, output, errors, stats = ifp_hot(project, ["install"], env)
      status.should eq(0)
      stats[0].should eq(1)
      errors.should contain("[plan-cache] status=miss")
      errors.should contain("[plan-cache] operation=write status=written")
      output.should contain("Bundle complete!")

      ifp_wait_for_plan_entry(project)
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      status, hit_output, hit_errors, hit_stats = ifp_hot(project, ["install"], env)
      status.should eq(0)
      hit_stats[0].should eq(1)
      hit_errors.should contain("[plan-cache] status=hit reason=ok")
      hit_output.should eq(output)
    end
  end

  it "rejects a locked plan when the runtime record namespace or ABI is tampered" do
    with_project({} of String => String) do |project|
      ifp_ready_remote(project)
      root = ifp_plan_cache_root(project)
      record_path = ifp_record_path(project, root)
      original_record = File.read(record_path)
      entry_path = ifp_cache_entries(project, root).first
      original_entry = File.read(entry_path)
      full_name = ifp_full_name(project)
      env = {"CELERITE_PLAN_CACHE" => "1", "CELERITE_CACHE_DIR" => root}

      [
        {field: "credential_namespace", value: "ffffffffffffffff", reason: "namespace-mismatch"},
        {field: "abi.ruby_api_version", value: "tampered", reason: "facts-mismatch:ruby_api_version"},
      ].each do |test_case|
        record = JSON.parse(original_record).as_h
        if test_case[:field].starts_with?("abi.")
          record["abi"].as_h[test_case[:field].split('.').last] = JSON::Any.new(test_case[:value])
          # Keep the persisted fingerprint internally consistent so the miss is
          # proved by FastPathStore.decision's ABI check, not by document.verify.
          payload = JSON.parse(original_entry).as_h
          fingerprint = payload["fingerprint"].as_h
          key = "abi.#{test_case[:field].split('.').last}"
          text = fingerprint["text"].as_s.gsub(/#{Regex.escape(key)}\t[^\r\n]+/, "#{key}\t#{test_case[:value]}")
          digest = Digest::SHA256.hexdigest(text)
          fingerprint["text"] = JSON::Any.new(text)
          fingerprint["digest"] = JSON::Any.new(digest)
          payload["digest"] = JSON::Any.new(digest)
          record["eval_digest"] = JSON::Any.new(digest)
          old_dir = File.dirname(entry_path)
          new_dir = File.join(File.dirname(old_dir), digest)
          File.rename(old_dir, new_dir)
          File.write(File.join(new_dir, "entry.json"), payload.to_json)
        else
          record[test_case[:field]] = JSON::Any.new(test_case[:value])
        end
        File.write(record_path, record.to_json)
        FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))

        status, _output, errors, stats = ifp_hot(project, ["install"], env)
        status.should eq(0)
        stats[0].should eq(1)
        errors.should contain("[plan-cache] status=miss reason=trusted:verdict:#{test_case[:reason]}")
        errors.should_not contain("[plan-cache] operation=write status=written")
        ifp_plan_entries(project).should be_empty
      end
    end
  end

  it "keeps corrupt, mistyped, escaping and credential-bearing plan payloads on the compatible path" do
    with_project({} of String => String) do |project|
      ifp_ready_remote(project)
      full_name = ifp_full_name(project)
      env = {"CELERITE_PLAN_CACHE" => "1",
             "CELERITE_CACHE_DIR"  => ifp_plan_cache_root(project)}
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      miss_status, _miss_output, miss_errors, _miss_stats = ifp_hot(project, ["install"], env)
      miss_status.should eq(0)
      miss_errors.should contain("[plan-cache] status=miss")
      ifp_wait_for_plan_entry(project)
      miss_errors.should contain("[plan-cache] operation=write status=written")
      entry = ifp_wait_for_plan_entry(project)
      original = File.read(entry)
      ["not json", "[]", %({"schema":"celerite-locked-plan/1","plan":{"specs":"../escape"}})].each do |broken|
        File.write(entry, broken)
        FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
        status, _output, errors, stats = ifp_hot(project, ["install"], env)
        status.should eq(0)
        stats[0].should eq(1)
        errors.should_not contain("[plan-cache] status=hit")
      end
      File.write(entry, original)
    end
  end

  it "uses zero Bundler cache RPCs for the optimized default layout without double-counting a warm EvalCache" do
    with_project({} of String => String) do |project|
      ifp_ready_remote(project)
      # Bundler 4.0.24 can self-checksum from metadata_source without a
      # explicit `bundler` spec row; this fixture proves the local optimized
      # candidate does not depend on that row.
      Celerite::Definition.build.lockfile!.specs.map(&.name).should_not contain("bundler")
      full_name = ifp_full_name(project)
      eval_env = {"CELERITE_CACHE_DIR" => ifp_plan_cache_root(project)}
      plan_env = eval_env.merge({"CELERITE_PLAN_CACHE" => "1"})

      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      miss_status, _miss_output, miss_errors, _miss_stats = ifp_hot(project, ["install"], plan_env)
      miss_status.should eq(0)
      miss_errors.should contain("[plan-cache] status=miss")
      ifp_wait_for_plan_entry(project)

      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      warm_status, _warm_output, warm_errors, _warm_stats = ifp_hot(project, ["install"], plan_env)
      warm_status.should eq(0)
      warm_errors.should contain("[plan-cache] status=hit reason=ok")

      # The persistent EvalCache is warm in all three runs, so evaluate_batch is
      # already zero-RPC. The only honest default-layout delta is the eliminated
      # authoritative bundler_cache_file request; do not claim it twice.
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      base_status, _base_output, _base_errors, base_stats = ifp_hot(project, ["install"], eval_env.merge({"CELERITE_PLAN_CACHE" => "0"}))
      base_status.should eq(0)
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      hit_status, _hit_output, hit_errors, hit_stats = ifp_hot(project, ["install"], plan_env)
      hit_status.should eq(0)
      hit_errors.should contain("[plan-cache] status=hit reason=ok")
      base_stats[0].should eq(1)
      hit_stats[0].should eq(1)
      (base_stats[1] - hit_stats[1]).should eq(1)
    end
  end

  it "keeps exactly the authoritative Bundler cache RPC for a custom layout" do
    with_project({} of String => String) do |project|
      custom_home = File.join(project, "custom-gem-home")
      Dir.mkdir_p(custom_home)
      layout = {"GEM_HOME" => custom_home, "GEM_PATH" => custom_home}
      ifp_ready_remote(project, "4.0.24", layout)
      full_name = ifp_full_name(project)
      eval_env = {"CELERITE_CACHE_DIR" => ifp_plan_cache_root(project)}.merge(layout)
      plan_env = eval_env.merge({"CELERITE_PLAN_CACHE" => "1"})

      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      miss_status, _miss_output, miss_errors, _miss_stats = ifp_hot(project, ["install"], plan_env)
      miss_status.should eq(0)
      miss_errors.should contain("[plan-cache] status=miss")
      ifp_wait_for_plan_entry(project)
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      warm_status, _warm_output, warm_errors, _warm_stats = ifp_hot(project, ["install"], plan_env)
      warm_status.should eq(0)
      warm_errors.should contain("[plan-cache] status=hit reason=ok")

      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      base_status, _base_output, _base_errors, base_stats = ifp_hot(project, ["install"], eval_env.merge({"CELERITE_PLAN_CACHE" => "0"}))
      base_status.should eq(0)
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      hit_status, _hit_output, hit_errors, hit_stats = ifp_hot(project, ["install"], plan_env)
      hit_status.should eq(0)
      hit_errors.should contain("[plan-cache] status=hit reason=ok")
      base_stats[0].should eq(1)
      hit_stats[0].should eq(1)
      hit_stats[1].should eq(base_stats[1])
    end
  end

  it "never re-queries a custom Bundler cache candidate whose path is nil" do
    Celerite::Resolution.bundler_cache_query_needed?(nil).should be_true
    Celerite::Resolution.bundler_cache_query_needed?(
      {path: "/custom/bundler-4.0.24.gem", sha256: nil, optimized: false}).should be_false
    Celerite::Resolution.bundler_cache_query_needed?(
      {path: nil, sha256: nil, optimized: false}).should be_false
    Celerite::Resolution.bundler_cache_query_needed?(
      {path: "/default/bundler-4.0.24.gem", sha256: Digest::SHA256.hexdigest("cache"), optimized: true}).should be_true
  end

  it "charges evaluate_batch to ordinary construction but not trusted evaluation hydration" do
    pending!("no Ruby interpreter on PATH for the bridge") unless ruby_available?
    with_project({} of String => String) do |project|
      ifp_ready(project)
      ifp_with_env(project, ifp_env("CELERITE_BRIDGE_STATS")) do
        Celerite::Bridge::BridgeStats.begin_run
        with_client do |client|
          definition = Celerite::Definition.build
          evaluation = Celerite::GemfileEvaluator.evaluation(definition.gemfile_path, client)
          before = Celerite::Bridge::BridgeStats.evaluations
          _ordinary = Celerite::Resolution.new(definition, false, client)
          Celerite::Bridge::BridgeStats.evaluations.should eq(before + 1)
          _hydrated = Celerite::Resolution.from_evaluation(definition, evaluation, client)
          Celerite::Bridge::BridgeStats.evaluations.should eq(before + 1)
        end
      end
    end
  end

  it "CI capability: expected_miss_after_lock_tamper" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      stats.should eq({0, 0, 0, 0})
      ifp_lines(errors, IFP_HIT).size.should eq(1)

      lock_path = File.join(project, "Gemfile.lock")
      File.open(lock_path, "ab") { |file| file.write("\n# task-275 old-binary capability gate\n") }
      status, _output, errors, stats = ifp_hot(project)
      status.should eq(0)
      fail "expected_miss_after_lock_tamper: stats=#{stats}" unless stats[0] >= 1
      ifp_lines(errors, IFP_HIT).should be_empty
      ifp_lines(errors, IFP_MISS).should contain("verdict:certificate-lock")
    end
  end

  it "misses for semantic flags and falls back for Bundler 2.7.2" do
    with_project({} of String => String) do |project|
      ifp_ready(project)
      env = {"CELERITE_PLAN_CACHE" => "1"}
      status, _output, errors, stats = ifp_hot(project, ["install", "--local"], env)
      status.should eq(0)
      stats[0].should be >= 1
      errors.should_not contain("[plan-cache] status=hit")
    end

    with_project({} of String => String) do |project|
      ifp_ready(project, "2.7.2")
      full_name = ifp_full_name(project)
      env = {"CELERITE_PLAN_CACHE" => "1",
             "CELERITE_CACHE_DIR"  => ifp_plan_cache_root(project)}
      FileUtils.rm_rf(ifp_installed_file(project, "gems", full_name))
      status, _output, errors, stats = ifp_hot(project, ["install"], env, "2.7.2")
      status.should eq(0)
      stats[0].should be >= 1
      errors.should_not contain("[plan-cache] status=hit")
    end
  end
end
