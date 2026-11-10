require "./spec_helper"
require "../src/celerite/git_source"

# Small git-fixture helpers: each example builds throwaway local repositories
# so tag/branch/ref resolution, checkout and submodule initialization are
# proven against real `git` behavior instead of mocks.
private def git_run(dir : String, args : Array(String)) : String
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run("git", args, chdir: dir, output: output, error: errors)
  unless status.success?
    raise "git #{args.join(" ")} failed in #{dir}: #{errors.to_s.chomp}"
  end
  output.to_s
end

private def git_available? : Bool
  Process.run("git", ["--version"], output: IO::Memory.new, error: IO::Memory.new).success?
rescue
  false
end

private def init_repo(dir : String) : Nil
  Dir.mkdir_p(dir)
  git_run(dir, ["init", "-q", "-b", "master"])
  git_run(dir, ["config", "user.email", "spec@example.test"])
  git_run(dir, ["config", "user.name", "Spec"])
  git_run(dir, ["config", "commit.gpgsign", "false"])
end

private def commit_file(dir : String, name : String, content : String, message : String) : String
  path = File.join(dir, name)
  Dir.mkdir_p(File.dirname(path))
  File.write(path, content)
  git_run(dir, ["add", "-A"])
  git_run(dir, ["commit", "-q", "-m", message])
  git_run(dir, ["rev-parse", "HEAD"]).strip
end

# Reads a checked-out file ignoring the CRLF conversion Windows git applies.
private def read_text(path : String) : String
  File.read(path).delete('\r')
end

describe Celerite::GitSource do
  it "resolves branch, tag and ref to their own commits" do
    next pending "git is not available" unless git_available?

    root = File.tempname("celerite-git", "repo")
    begin
      init_repo(root)
      master_sha = commit_file(root, "lib/a.rb", "VERSION = 1\n", "first")
      git_run(root, ["tag", "-a", "v1.0", "-m", "release 1.0"])
      tagged_sha = git_run(root, ["rev-parse", "HEAD"]).strip

      git_run(root, ["checkout", "-q", "-b", "feature"])
      feature_sha = commit_file(root, "lib/a.rb", "VERSION = 2\n", "second")

      bundle_root = File.tempname("celerite-git", "bundle")
      source = Celerite::GitSource.new(root, bundle_root)

      source.fetch(branch: "master").should eq(master_sha)
      source.fetch(branch: "feature").should eq(feature_sha)
      source.fetch(tag: "v1.0").should eq(tagged_sha)
      source.fetch(ref: master_sha).should eq(master_sha)
      # branch wins when several options are present
      source.fetch(branch: "feature", tag: "v1.0").should eq(feature_sha)
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "raises a clear error for an unknown ref" do
    next pending "git is not available" unless git_available?

    root = File.tempname("celerite-git", "repo")
    begin
      init_repo(root)
      commit_file(root, "lib/a.rb", "VERSION = 1\n", "first")

      bundle_root = File.tempname("celerite-git", "bundle")
      source = Celerite::GitSource.new(root, bundle_root)
      source.fetch(branch: "master")

      expect_raises(Celerite::Error, /revision not found|single revision/) do
        source.fetch(ref: "0000000000000000000000000000000000000000")
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "checks out the requested revision into the bundle layout" do
    next pending "git is not available" unless git_available?

    root = File.tempname("celerite-git", "repo")
    begin
      init_repo(root)
      commit_file(root, "lib/a.rb", "VERSION = 1\n", "first")
      git_run(root, ["tag", "-a", "v1.0", "-m", "release 1.0"])
      old_sha = git_run(root, ["rev-parse", "HEAD"]).strip
      commit_file(root, "lib/a.rb", "VERSION = 2\n", "second")

      bundle_root = File.tempname("celerite-git", "bundle")
      source = Celerite::GitSource.new(root, bundle_root)
      revision = source.fetch(tag: "v1.0")
      revision.should eq(old_sha)

      dir = source.checkout(revision, false)
      dir.should eq(File.join(bundle_root, "bundler", "gems", "#{source.base_name}-#{revision[0, 12]}"))
      read_text(File.join(dir, "lib", "a.rb")).should eq("VERSION = 1\n")
      # the checkout keeps its .git so later git commands work on it
      Dir.exists?(File.join(dir, ".git")).should be_true
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "initializes submodules only when requested" do
    next pending "git is not available" unless git_available?

    sub = File.tempname("celerite-git", "sub")
    root = File.tempname("celerite-git", "repo")
    begin
      init_repo(sub)
      commit_file(sub, "inner.txt", "inner\n", "sub first")

      init_repo(root)
      commit_file(root, "lib/a.rb", "VERSION = 1\n", "first")
      git_run(root, ["-c", "protocol.file.allow=always", "submodule", "add", "-q", sub, "vendor/inner"])
      git_run(root, ["commit", "-q", "-m", "add submodule"])
      revision = git_run(root, ["rev-parse", "HEAD"]).strip

      bundle_root = File.tempname("celerite-git", "bundle")
      source = Celerite::GitSource.new(root, bundle_root)
      source.fetch(ref: revision)

      with_submodules = source.checkout(revision, true)
      read_text(File.join(with_submodules, "vendor", "inner", "inner.txt")).should eq("inner\n")
    ensure
      FileUtils.rm_rf(sub)
      FileUtils.rm_rf(root)
    end
  end
end
