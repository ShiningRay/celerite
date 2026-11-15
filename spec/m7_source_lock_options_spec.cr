require "./spec_helper"

private def lock_source_info(json : String) : Celerite::Resolution::SourceInfo
  Celerite::Resolution::SourceInfo.from_json(json)
end

# Reference `Source::Path#to_lock` / `Source::Git#to_lock` ordering
# (bundler-4.0.24 source/path.rb:45-49, source/git.rb:53-61). These units pin
# the exact key order and the default-glob suppression without spinning up a
# project or a bridge.
describe Celerite::Resolution do
  describe ".path_lock_options" do
    it "writes remote then a non-default glob" do
      info = lock_source_info(%({"type":"PATH","remote":"vendor/mono","glob":"gems/*/*.gemspec"}))
      options = Celerite::Resolution.path_lock_options("vendor/mono", info)
      options.map(&.key).should eq(["remote", "glob"])
      options[1].value.should eq("gems/*/*.gemspec")
    end

    it "writes only remote when the source has no glob" do
      info = lock_source_info(%({"type":"PATH","remote":"vendor/example"}))
      Celerite::Resolution.path_lock_options("vendor/example", info).map(&.key).should eq(["remote"])
    end

    it "suppresses the default glob" do
      info = lock_source_info(%({"type":"PATH","remote":"vendor/example","glob":"{,*,*/*}.gemspec"}))
      Celerite::Resolution.path_lock_options("vendor/example", info).map(&.key).should eq(["remote"])
    end
  end

  describe ".git_lock_options" do
    it "orders ref before branch, then tag, submodules and glob" do
      info = lock_source_info(%({"type":"GIT","remote":"https://example.test/repo.git","branch":"main","tag":"v1","ref":"abc1234","submodules":true,"glob":"gems/*/*.gemspec"}))
      options = Celerite::Resolution.git_lock_options("https://example.test/repo.git", info)
      options.map(&.key).should eq(["remote", "revision", "ref", "branch", "tag", "submodules", "glob"])
      options[1].value.should eq("")
      options[5].value.should eq("true")
    end

    it "writes remote and revision only when no other option is set" do
      info = lock_source_info(%({"type":"GIT","remote":"https://example.test/repo.git"}))
      options = Celerite::Resolution.git_lock_options("https://example.test/repo.git", info)
      options.map(&.key).should eq(["remote", "revision"])
    end
  end
end
