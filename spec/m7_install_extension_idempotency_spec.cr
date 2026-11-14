require "./spec_helper"

# Regression (N3 defect 1): an extension dir left behind by an interrupted
# previous install made the next install raise `File exists @ dir_s_mkdir`
# from the bridge/RubyGems Dir.mkdir path.  The installer now reuses a
# completed build (gem.build_complete marker) and clears a stale dir first.
describe "Installer extension directory idempotency" do
  it "builds extension dir as <root>/extensions/<platform>/<abi>/<full_name>" do
    root = File.join(Dir.tempdir, "m7-ext-idem-#{Process.pid}-#{rand(UInt32)}")
    Dir.mkdir_p(root)
    begin
      dir = Celerite::Installer.extension_dir_for(root, "4.0.0", "bigdecimal-4.1.3")
      expected_platform = Celerite::Gem::Platform.local.to_s
      dir.should eq(File.join(root, "extensions", expected_platform, "4.0.0", "bigdecimal-4.1.3"))
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "needs a build for a fresh dir" do
    root = File.join(Dir.tempdir, "m7-ext-idem-#{Process.pid}-#{rand(UInt32)}")
    Dir.mkdir_p(root)
    begin
      dir = File.join(root, "e")
      Dir.mkdir_p(dir)
      Celerite::Installer.extension_build_needed?(dir).should be_true
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "reuses a completed build (gem.build_complete marker present)" do
    root = File.join(Dir.tempdir, "m7-ext-idem-#{Process.pid}-#{rand(UInt32)}")
    Dir.mkdir_p(root)
    begin
      dir = File.join(root, "e")
      Dir.mkdir_p(dir)
      File.write(File.join(dir, "gem.build_complete"), "")
      Celerite::Installer.extension_build_needed?(dir).should be_false
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "needs a build for a stale dir without the marker (interrupted install)" do
    root = File.join(Dir.tempdir, "m7-ext-idem-#{Process.pid}-#{rand(UInt32)}")
    Dir.mkdir_p(root)
    begin
      dir = File.join(root, "e")
      Dir.mkdir_p(dir)
      File.write(File.join(dir, "partial.o"), "x")
      Celerite::Installer.extension_build_needed?(dir).should be_true
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
