require "./spec_helper"

# `Gem::Installer#install` always creates build_info/doc/plugins/extensions
# under the gem home (installer.rb:902-918 `write_build_info_file`,
# :475-484 `generate_plugins` → `Gem.plugindir`), even for a pure-Ruby gem.
# The reference also leaves no `bundler.lock` behind once a run finishes, while
# our `Bundler::ProcessLock` port used to keep one in the bundle root.
describe "bundle layout" do
  it "creates the RubyGems bookkeeping directories" do
    root = File.join(Dir.tempdir, "celerite-layout-#{Process.pid}-#{rand(1 << 30)}")
    begin
      Celerite::Installer.ensure_layout(root)
      %w[build_info doc plugins extensions].each do |name|
        Dir.exists?(File.join(root, name)).should be_true
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "keeps existing content when the layout is ensured again" do
    root = File.join(Dir.tempdir, "celerite-layout-#{Process.pid}-#{rand(1 << 30)}")
    begin
      Celerite::Installer.ensure_layout(root)
      marker = File.join(root, "build_info", "keep")
      File.write(marker, "keep")
      Celerite::Installer.ensure_layout(root)
      File.read(marker).should eq("keep")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "removes the process lock file when the lock closes" do
    path = File.join(Dir.tempdir, "celerite-lock-#{Process.pid}-#{rand(1 << 30)}")
    begin
      lock = Celerite::Commands::ProcessLock.lock(path)
      File.exists?(File.join(path, "bundler.lock")).should be_true
      lock.close
      File.exists?(File.join(path, "bundler.lock")).should be_false
    ensure
      FileUtils.rm_rf(path)
    end
  end
end
