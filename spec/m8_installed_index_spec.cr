require "./spec_helper"

# M8 (roadmap:166, first half, task-248): the read-only commands reuse a
# disk-only index of the installed gems (`Celerite::InstalledIndex`) instead of
# asking the Ruby bridge "which gems are installed?" (`installed_specs`,
# `default_gem_spec`). RubyGems stores name/version/platform in the *file name*
# of every specification file, so the answer needs no Ruby process.
#
# What these specs pin:
#   1. the index derives identity from those file names (`parse_full_name`,
#      `load`), including `specifications/default/` and multi-part platforms;
#   2. resolving a locked default gem from the index costs zero processes and
#      zero RPC (`BridgeStats.procs`/`rpc`), which is the point of the slice;
#   3. `check`/`info` now agree with the reference for a default gem without a
#      bridge (`bundle check` exits 0, `bundle info date` prints the block),
#      while a gem the index cannot see is still reported missing — the safety
#      gate that keeps `check` from turning into a permanent exit 0.
#
# The in-process tests point `GEM_HOME` at a synthetic RubyGems root, so they
# do not depend on which gems this machine has installed. `RuntimeFacts` reads
# `GEM_HOME` for the default gem dir (`runtime_facts.cr:344`), which is how a
# run without a bridge learns where to look; when no interpreter is reachable,
# these tests are skipped rather than weakened (the same requirement every
# bridge-backed spec in this family has).
PROBE_GEM     = "grapefruitprobe"
PROBE_VERSION = "1.0.0"

private PROBE_LOCKFILE = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:
    #{PROBE_GEM} (#{PROBE_VERSION})

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  #{PROBE_GEM}

BUNDLED WITH
   4.0.24
LOCK

private OTHER_LOCKFILE = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:

PLATFORMS
  ruby

DEPENDENCIES

BUNDLED WITH
   4.0.24
LOCK

# A RubyGems root that has one *default* gem (`specifications/default/`) and one
# ordinary installed gem, laid out the way `gem install` leaves them.
private def mi_gem_home(& : String ->) : Nil
  root = File.tempname("celerite-m8-index", "gemhome")
  Dir.mkdir_p(File.join(root, "specifications", "default"))
  Dir.mkdir_p(File.join(root, "specifications"))
  Dir.mkdir_p(File.join(root, "gems", "#{PROBE_GEM}-#{PROBE_VERSION}"))
  Dir.mkdir_p(File.join(root, "gems", "plainprobe-2.0.0"))
  File.write(File.join(root, "specifications", "default", "#{PROBE_GEM}-#{PROBE_VERSION}.gemspec"),
    "Gem::Specification.new do |s|\n  s.name = \"#{PROBE_GEM}\"\n  s.version = \"#{PROBE_VERSION}\"\n  s.summary = \"probe summary\"\n  s.homepage = \"https://example.com/probe\"\nend\n")
  File.write(File.join(root, "specifications", "plainprobe-2.0.0.gemspec"),
    "Gem::Specification.new do |s|\n  s.name = \"plainprobe\"\n  s.version = \"2.0.0\"\nend\n")
  begin
    yield root
  ensure
    FileUtils.rm_rf(root)
  end
end

# Runs the block with `GEM_HOME`/`GEM_PATH` pointing at `root` and no bridge
# configured, restoring the environment afterwards.
private def mi_with_gem_home(root : String, &) : Nil
  names = %w(GEM_HOME GEM_PATH CELERITE_BRIDGE_SERVER CELERITE_REFERENCE_BUNDLER_LIB CELERITE_BRIDGE_STATS)
  saved = {} of String => String?
  names.each { |name| saved[name] = ENV[name]? }
  begin
    ENV["GEM_HOME"] = root
    ENV["GEM_PATH"] = root
    ENV.delete("CELERITE_BRIDGE_SERVER")
    ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
    ENV.delete("CELERITE_BRIDGE_STATS")
    yield
  ensure
    names.each do |name|
      if value = saved[name]
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

private def mi_capture(&block : (IO, IO) -> Int32) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  code = yield output, errors
  {code, output.to_s, errors.to_s}
end

private def mi_project_files(lockfile : String, gemfile : String) : Hash(String, String)
  {
    "Gemfile"        => gemfile,
    "Gemfile.lock"   => lockfile,
    ".bundle/config" => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
  }
end

# A project that installs into the system gem dir (`GEM_HOME` in these tests),
# so the locked gem is present and only the *queried* name needs the
# default-gem fallback.
private def mi_system_project_files(lockfile : String, gemfile : String) : Hash(String, String)
  {
    "Gemfile"      => gemfile,
    "Gemfile.lock" => lockfile,
  }
end

# The interpreter facts the fallback needs (`RuntimeFacts`); a machine without a
# reachable Ruby cannot exercise the no-bridge path at all.
private def mi_index_usable? : Bool
  !Celerite::RuntimeFacts.detect.nil?
end

describe Celerite::InstalledIndex do
  describe ".parse_full_name" do
    it "splits name, version and platform like RubyGems" do
      Celerite::InstalledIndex.parse_full_name("json_pure-2.8.1").should eq({"json_pure", "2.8.1", nil})
      Celerite::InstalledIndex.parse_full_name("json_pure-2.8.1-java").should eq({"json_pure", "2.8.1", "java"})
      Celerite::InstalledIndex.parse_full_name("nokogiri-1.17.2-x86_64-linux").should eq({"nokogiri", "1.17.2", "x86_64-linux"})
      Celerite::InstalledIndex.parse_full_name("nokogiri-1.17.2-x86_64-linux-gnu").should eq({"nokogiri", "1.17.2", "x86_64-linux-gnu"})
      Celerite::InstalledIndex.parse_full_name("json-2.15.1").should eq({"json", "2.15.1", nil})
    end

    it "refuses names it cannot attribute to a version" do
      Celerite::InstalledIndex.parse_full_name("json_pure").should be_nil
      Celerite::InstalledIndex.parse_full_name("-1.0").should be_nil
      Celerite::InstalledIndex.parse_full_name("2.8.1").should be_nil
      Celerite::InstalledIndex.parse_full_name("json_pure-").should be_nil
    end
  end

  describe ".load" do
    it "reads both specifications dirs and derives gem_dir from the file name" do
      mi_gem_home do |root|
        index = Celerite::InstalledIndex.load([root])
        index.size.should eq(2)

        default_entry = index.default_gem(PROBE_GEM).not_nil!
        default_entry.version.should eq(PROBE_VERSION)
        default_entry.platform.should be_nil
        default_entry.full_name.should eq("#{PROBE_GEM}-#{PROBE_VERSION}")
        default_entry.default_gem.should be_true
        default_entry.gem_dir.gsub('\\', "/").should end_with("/gems/#{PROBE_GEM}-#{PROBE_VERSION}")

        plain = index.find("plainprobe").not_nil!
        plain.default_gem.should be_false
        plain.gem_dir.gsub('\\', "/").should end_with("/gems/plainprobe-2.0.0")
      end
    end

    it "treats a missing root as an empty index instead of failing" do
      index = Celerite::InstalledIndex.load([File.join(File.tempname("celerite-m8-absent", "root"), "none")])
      index.empty?.should be_true
      index.default_gem(PROBE_GEM).should be_nil
    end

    it "keeps the newest version of a duplicated default gem" do
      root = File.tempname("celerite-m8-dup", "gemhome")
      Dir.mkdir_p(File.join(root, "specifications", "default"))
      begin
        %w(1.0.0 2.0.0 1.9.9).each do |version|
          File.write(File.join(root, "specifications", "default", "dup-#{version}.gemspec"), "Gem::Specification.new\n")
        end
        Celerite::InstalledIndex.load([root]).default_gem("dup").not_nil!.version.should eq("2.0.0")
      ensure
        FileUtils.rm_rf(root)
      end
    end

    it "prefers the plain-Ruby platform when both variants are installed" do
      root = File.tempname("celerite-m8-plat", "gemhome")
      Dir.mkdir_p(File.join(root, "specifications"))
      begin
        File.write(File.join(root, "specifications", "both-1.0.0-java.gemspec"), "Gem::Specification.new\n")
        Celerite::InstalledIndex.load([root]).find("both").not_nil!.platform.should eq("java")
        File.write(File.join(root, "specifications", "both-1.0.0.gemspec"), "Gem::Specification.new\n")
        Celerite::InstalledIndex.load([root]).find("both").not_nil!.platform.should be_nil
      ensure
        FileUtils.rm_rf(root)
      end
    end
  end
end

describe "M8 installed gem index" do
  it "indexes the installed specs with zero processes and zero RPC" do
    mi_gem_home do |root|
      ENV["CELERITE_BRIDGE_STATS"] = "1"
      begin
        Celerite::Bridge::BridgeStats.begin_run
        index = Celerite::InstalledIndex.load([root])
        index.default_gem(PROBE_GEM).not_nil!.version.should eq(PROBE_VERSION)
        Celerite::Bridge::BridgeStats.procs.should eq(0)
        Celerite::Bridge::BridgeStats.rpc.should eq(0)
      ensure
        ENV.delete("CELERITE_BRIDGE_STATS")
      end
    end
  end

  it "resolves a locked default gem through the index without the bridge" do
    pending!("needs a reachable Ruby for RuntimeFacts") unless mi_index_usable?
    mi_gem_home do |root|
      mi_with_gem_home(root) do
        mi_project_files(PROBE_LOCKFILE, "source \"https://rubygems.org\"\n\ngem \"#{PROBE_GEM}\"\n").tap do |files|
          with_project(files) do
            definition = Celerite::Definition.build
            lockfile = definition.lockfile!
            spec = lockfile.specs.find(&.name.==(PROBE_GEM)).not_nil!
            ENV["CELERITE_BRIDGE_STATS"] = "1"
            begin
              Celerite::Bridge::BridgeStats.begin_run
              gem_dir = Celerite::Commands.installed_gem_dir(definition, spec, lockfile)
              gem_dir.should_not be_nil
              gem_dir.not_nil!.gsub('\\', "/").should end_with("/gems/#{PROBE_GEM}-#{PROBE_VERSION}")
              Celerite::Commands.installed_spec_dir?(definition, spec, lockfile).should be_true
              # The default-gem answer came from the disk index: no Ruby process
              # was started and no RPC was sent while resolving it.
              Celerite::Bridge::BridgeStats.procs.should eq(0)
              Celerite::Bridge::BridgeStats.rpc.should eq(0)
            ensure
              ENV.delete("CELERITE_BRIDGE_STATS")
            end
          end
        end
      end
    end
  end

  it "reports check as satisfied when the index answers the locked default gem" do
    pending!("needs a reachable Ruby for RuntimeFacts") unless mi_index_usable?
    mi_gem_home do |root|
      mi_with_gem_home(root) do
        with_project(mi_project_files(PROBE_LOCKFILE, "source \"https://rubygems.org\"\n\ngem \"#{PROBE_GEM}\"\n")) do
          code, out, err = mi_capture { |o, e| Celerite::Commands.check(o, e, [] of String) }
          code.should eq(0)
          out.should eq("The Gemfile's dependencies are satisfied\n")
          err.should be_empty
        end
      end
    end
  end

  it "still reports a gem the index cannot see as missing" do
    # Safety gate: an empty/unreadable index must not degrade into "nothing is
    # missing" (which would make `check` exit 0 forever).
    mi_gem_home do |root|
      empty_root = File.join(root, "empty")
      Dir.mkdir_p(empty_root)
      mi_with_gem_home(empty_root) do
        with_project(mi_project_files(PROBE_LOCKFILE, "source \"https://rubygems.org\"\n\ngem \"#{PROBE_GEM}\"\n")) do
          code, out, err = mi_capture { |o, e| Celerite::Commands.check(o, e, [] of String) }
          code.should eq(1)
          out.should be_empty
          err.should contain("The following gems are missing")
          err.should contain("#{PROBE_GEM} (#{PROBE_VERSION})")
        end
      end
    end
  end

  it "prints the default gem block for info without the bridge" do
    pending!("needs a reachable Ruby for RuntimeFacts") unless mi_index_usable?
    mi_gem_home do |root|
      mi_with_gem_home(root) do
        # The probe is *not* in this project's lockfile, which is when the
        # reference falls back to the interpreter's default gem for the name
        # (`cli/common.rb:68-101`).
        with_project(mi_system_project_files(OTHER_LOCKFILE, "source \"https://rubygems.org\"\n")) do
          code, out, err = mi_capture { |o, e| Celerite::Commands.show_info("info", o, e, [PROBE_GEM]) }
          code.should eq(0), "out=#{out.inspect} err=#{err.inspect}"
          err.should be_empty
          out.should contain("  * #{PROBE_GEM} (#{PROBE_VERSION})\n")
          out.should contain("\tPath: ")
          out.should contain("/gems/#{PROBE_GEM}-#{PROBE_VERSION}\n")
          out.should contain("\tDefault Gem: yes\n")
        end
      end
    end
  end

  it "prints the default gem path for show without the bridge" do
    pending!("needs a reachable Ruby for RuntimeFacts") unless mi_index_usable?
    mi_gem_home do |root|
      mi_with_gem_home(root) do
        with_project(mi_system_project_files(OTHER_LOCKFILE, "source \"https://rubygems.org\"\n")) do
          code, out, err = mi_capture { |o, e| Celerite::Commands.show_info("show", o, e, [PROBE_GEM]) }
          code.should eq(0)
          err.should be_empty
          out.gsub('\\', "/").should contain("/gems/#{PROBE_GEM}-#{PROBE_VERSION}\n")
        end
      end
    end
  end
end
