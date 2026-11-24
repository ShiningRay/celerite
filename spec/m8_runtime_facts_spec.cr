require "./spec_helper"

# S8a (`docs/roadmap-evidence/M8-fast-path-plan.md` §2.1): the zero-Ruby fast
# path needs the seven `EvalFingerprint::Runtime` fields without starting Ruby.
# `RuntimeFacts` reads them from the interpreter's own build files. These specs
# pin four things: what the real `C:/Ruby40-x64` tree yields, that `$(...)`
# expansion and `TOPDIR` substitution are correct, that comments/guards cannot
# inject values, and that nothing spawns.
private REAL_RUBY_EXE  = "C:/Ruby40-x64/bin/ruby.exe"
private REAL_RUBY_ROOT = "C:/Ruby40-x64"

private def real_ruby? : Bool
  File.file?(REAL_RUBY_EXE)
end

# Builds `<dir>/RubyFake/bin/ruby.exe` plus, unless `with_rbconfig` is false, a
# synthetic `lib/ruby/9.9.0/fake-arch/rbconfig.rb`. The rbconfig carries a
# commented-out `CONFIG["arch"]`, a `RUBY_VERSION.start_with? ... or raise`
# guard and a non-literal `prefix`, so a passing parse proves the parser only
# accepts the literal assignment shape.
private def with_fake_ruby(with_rbconfig = true, &)
  dir = File.join(Dir.tempdir, "celerite-runtime-facts-#{Process.pid}-#{Random.rand(1_000_000)}")
  root = File.join(dir, "RubyFake")
  bin = File.join(root, "bin")
  arch_dir = File.join(root, "lib", "ruby", "9.9.0", "fake-arch")
  Dir.mkdir_p(bin)
  File.write(File.join(bin, "ruby.exe"), "")
  if with_rbconfig
    Dir.mkdir_p(arch_dir)
    lines = [
      %q(# encoding: ascii-8bit),
      %q(# CONFIG["arch"] = "commented-arch"),
      %q(module RbConfig),
      %q(  RUBY_VERSION.start_with?("9.9.") or),
      %q(    raise "ruby lib version (9.9.7) doesn't match executable version (#{RUBY_VERSION})"),
      %q(  CONFIG = {}),
      %q(  CONFIG["MAJOR"] = "9"),
      %q(  CONFIG["MINOR"] = "9"),
      %q(  CONFIG["TEENY"] = "7"),
      %q(  CONFIG["PATCHLEVEL"] = "0"),
      %q(  CONFIG["DESTDIR"] = DESTDIR),
      %q(  CONFIG["prefix"] = (TOPDIR || DESTDIR + "/.")),
      %q(  CONFIG["exec_prefix"] = "$(prefix)"),
      %q(  CONFIG["libdir"] = "$(exec_prefix)/lib"),
      %q(  CONFIG["rubylibprefix"] = "$(libdir)/$(RUBY_BASE_NAME)"),
      %q(  CONFIG["RUBY_BASE_NAME"] = "ruby"),
      %q(  CONFIG["arch"] = "fake-arch"),
      %q(  CONFIG["ruby_version"] = "9.9.0"),
      %q(end),
    ]
    File.write(File.join(arch_dir, "rbconfig.rb"), lines.join('\n') + '\n')
  end
  begin
    yield root
  ensure
    FileUtils.rm_rf(dir)
  end
end

private def facts_for(ruby_exe : String) : Celerite::RuntimeFacts::Facts
  facts = Celerite::RuntimeFacts.detect(ruby_exe)
  facts.should_not be_nil
  facts.not_nil!
end

describe Celerite::RuntimeFacts do
  it "reads the real C:/Ruby40-x64 tree without starting Ruby" do
    pending! "no C:/Ruby40-x64 on this host" unless real_ruby?
    facts = facts_for(REAL_RUBY_EXE)

    facts.ruby_version.value.should eq("4.0.6")
    facts.ruby_version.source.should eq(Celerite::RuntimeFacts::Source::Rbconfig)
    facts.platform.value.should eq("x64-mingw-ucrt")
    facts.platform.source.should eq(Celerite::RuntimeFacts::Source::Rbconfig)
    facts.patchlevel.value.should eq("0")
    facts.rubygems_version.value.should eq("4.0.16")
    facts.rubygems_version.source.should eq(Celerite::RuntimeFacts::Source::RubyLib)
    facts.bundler_version.value.should eq(Celerite::Profile.bundler_version)
    facts.bundler_version.source.should eq(Celerite::RuntimeFacts::Source::Profile)
    facts.abi.value.should eq("4.0.0")
    facts.ruby_exe.should eq(REAL_RUBY_EXE)
  end

  it "expands $(...) references recursively (libdir -> exec_prefix -> prefix)" do
    pending! "no C:/Ruby40-x64 on this host" unless real_ruby?
    facts = facts_for(REAL_RUBY_EXE)

    # rbconfig sets `libdir = "$(exec_prefix)/lib"` and
    # `exec_prefix = "$(prefix)"`, neither of which is a literal.
    facts.libdir.value.should eq("#{REAL_RUBY_ROOT}/lib")
    facts.libdir.source.should eq(Celerite::RuntimeFacts::Source::Rbconfig)
  end

  it "substitutes TOPDIR from the rbconfig file position" do
    pending! "no C:/Ruby40-x64 on this host" unless real_ruby?
    facts = facts_for(REAL_RUBY_EXE)

    # `CONFIG["prefix"] = (TOPDIR || DESTDIR + "/.")` is not a literal; the
    # parser must derive TOPDIR as `<root>` from
    # `<root>/lib/ruby/4.0.0/x64-mingw-ucrt/rbconfig.rb`.
    facts.prefix.value.should eq(REAL_RUBY_ROOT)
    facts.prefix.source.should eq(Celerite::RuntimeFacts::Source::Rbconfig)
  end

  it "derives the default gem dir from rubylibprefix when GEM_HOME is unset" do
    pending! "no C:/Ruby40-x64 on this host" unless real_ruby?
    previous = ENV["GEM_HOME"]?
    ENV.delete("GEM_HOME")
    begin
      facts = facts_for(REAL_RUBY_EXE)
      facts.default_gem_dir.value.should eq("#{REAL_RUBY_ROOT}/lib/ruby/gems/4.0.0")
      facts.default_gem_dir.source.should eq(Celerite::RuntimeFacts::Source::Rbconfig)
    ensure
      ENV["GEM_HOME"] = previous
    end
  end

  it "lets GEM_HOME win over the rbconfig-derived gem dir" do
    pending! "no C:/Ruby40-x64 on this host" unless real_ruby?
    previous = ENV["GEM_HOME"]?
    ENV["GEM_HOME"] = "C:/fake/gem-home"
    begin
      facts = facts_for(REAL_RUBY_EXE)
      facts.default_gem_dir.value.should eq("C:/fake/gem-home")
      facts.default_gem_dir.source.should eq(Celerite::RuntimeFacts::Source::Environment)
    ensure
      ENV["GEM_HOME"] = previous
    end
  end

  it "ignores commented assignments and guard lines in rbconfig" do
    with_fake_ruby do |root|
      facts = facts_for(File.join(root, "bin", "ruby.exe"))

      # The commented `CONFIG["arch"] = "commented-arch"` must not win.
      facts.platform.value.should eq("fake-arch")
      # MAJOR/MINOR/TEENY are read, the lib version is not the Ruby version.
      facts.ruby_version.value.should eq("9.9.7")
      # TOPDIR comes from the fixture's own location.
      facts.prefix.value.should eq(root.gsub('\\', "/"))
      facts.libdir.value.should eq("#{root.gsub('\\', "/")}/lib")
    end
  end

  it "returns nil for a ruby_exe that does not exist" do
    missing = File.join(Dir.tempdir, "no-such-ruby-#{Random.rand(1_000_000)}.exe")
    File.exists?(missing).should be_false
    Celerite::RuntimeFacts.detect(missing).should be_nil
  end

  it "returns nil when the tree has no rbconfig.rb" do
    with_fake_ruby(with_rbconfig: false) do |root|
      Celerite::RuntimeFacts.detect(File.join(root, "bin", "ruby.exe")).should be_nil
    end
  end

  it "matches a runtime record only when all seven fields are known and equal" do
    values = ["4.0.6", "0", "ruby", "4.0.6", "4.0.16", "4.0.24", "x64-mingw-ucrt"]
    field = ->(value : String) { Celerite::RuntimeFacts::Field.new(value, Celerite::RuntimeFacts::Source::Rbconfig) }
    facts = Celerite::RuntimeFacts::Facts.new(
      "C:/fake/bin/ruby.exe",
      field.call(values[0]), field.call(values[1]), field.call(values[2]),
      field.call(values[3]), field.call(values[4]), field.call(values[5]),
      field.call(values[6]),
      field.call("C:/fake/lib/ruby/gems/4.0.0"), field.call("4.0.0"),
      field.call("C:/fake"), field.call("C:/fake/lib"),
    )

    build = ->(v : Array(String)) do
      Celerite::EvalFingerprint::Runtime.new(v[0], v[1], v[2], v[3], v[4], v[5], v[6])
    end

    facts.matches?(build.call(values)).should be_true

    7.times do |index|
      changed = values.dup
      changed[index] = "#{changed[index]}-changed"
      facts.matches?(build.call(changed)).should be_false
    end
  end

  it "never matches while engine/engine_version are unknown" do
    pending! "no C:/Ruby40-x64 on this host" unless real_ruby?
    facts = facts_for(REAL_RUBY_EXE)

    # Even a runtime record with the exact locally-known values must not match:
    # `engine` and `engine_version` have no local source, and the module must
    # never treat "unknown" as "probably the same".
    facts.engine.source.should eq(Celerite::RuntimeFacts::Source::Unknown)
    facts.engine_version.source.should eq(Celerite::RuntimeFacts::Source::Unknown)

    runtime = Celerite::EvalFingerprint::Runtime.new(
      "4.0.6", "0", "ruby", "4.0.6", "4.0.16",
      Celerite::Profile.bundler_version, "x64-mingw-ucrt")
    facts.matches?(runtime).should be_false
  end

  it "does not spawn a process" do
    pending! "no C:/Ruby40-x64 on this host" unless real_ruby?
    previous = ENV["CELERITE_BRIDGE_STATS"]?
    ENV["CELERITE_BRIDGE_STATS"] = "1"
    begin
      Celerite::Bridge::BridgeStats.begin_run
      Celerite::RuntimeFacts.detect(REAL_RUBY_EXE).should_not be_nil
      Celerite::Bridge::BridgeStats.procs.should eq(0)
      Celerite::Bridge::BridgeStats.rpc.should eq(0)
    ensure
      ENV["CELERITE_BRIDGE_STATS"] = previous
    end
  end
end
