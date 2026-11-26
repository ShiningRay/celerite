require "./spec_helper"
require "../src/celerite"

private T273_LOCK = <<-LOCK
GEM
  remote: https://example.test/
  specs:
    rack (3.0.0)
      small (1.0.0)

PLATFORMS
  x64-mingw-ucrt
  x86_64-linux

DEPENDENCIES
  rack

CHECKSUMS
  rack (3.0.0) sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  small (1.0.0) sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

BUNDLED WITH
    4.0.24
LOCK

private def t273_write(path : String, body : String) : Nil
  Dir.mkdir_p(File.dirname(path))
  File.write(path, body)
end

private def t273_lock(body : String, project : String) : Celerite::CacheIdentity::LockIdentity
  path = File.join(project, "Gemfile.lock")
  t273_write(path, body)
  Celerite::CacheIdentity::LockIdentity.detect(path, project_root: project)
end

private def t273_with_lock(&block) : Nil
  project = File.join(Dir.tempdir, "celerite-t273-lock-#{Process.pid}-#{Random.rand(1_000_000)}")
  Dir.mkdir_p(project)
  begin
    yield project
  ensure
    FileUtils.rm_rf(project)
  end
end

describe Celerite::CacheIdentity::LockIdentity do
  it "detects the raw byte digest, size, line ending and semantic sections" do
    t273_with_lock do |project|
      identity = t273_lock(T273_LOCK, project)
      identity.slot.should eq("default")
      identity.sha256.should eq(Digest::SHA256.hexdigest(T273_LOCK))
      identity.byte_size.should eq(T273_LOCK.bytesize.to_i64)
      identity.line_ending.should eq("lf")
      identity.parser_revision.should eq(Celerite::CacheIdentity::LOCK_PARSER_REVISION)
      identity.bundled_with.should eq("4.0.24")
      identity.platforms.should eq(["x64-mingw-ucrt", "x86_64-linux"])
      canonical = "rack (3.0.0) sha256=#{"a" * 64}\nsmall (1.0.0) sha256=#{"b" * 64}\n"
      identity.checksums_sha256.should eq(Digest::SHA256.hexdigest(canonical))
    end
  end

  it "uses a fixed CHECKSUMS projection independent of order and CRLF" do
    t273_with_lock do |project|
      first = t273_lock(T273_LOCK, project)
      reversed = T273_LOCK.sub(
        "  rack (3.0.0) sha256=#{"a" * 64}\n  small (1.0.0) sha256=#{"b" * 64}",
        "  small (1.0.0) sha256=#{"b" * 64}\n  rack (3.0.0) sha256=#{"a" * 64}")
      t273_write(File.join(project, "Gemfile.lock"), reversed.gsub("\n", "\r\n"))
      second = Celerite::CacheIdentity::LockIdentity.detect(File.join(project, "Gemfile.lock"), project_root: project)
      second.checksums_sha256.should eq(first.checksums_sha256)
      second.line_ending.should eq("crlf")
      second.sha256.should_not eq(first.sha256)
      second.same?(first).should be_false
    end
  end

  it "does not enter an absolute path and does not miss on a root migration" do
    t273_with_lock do |first_root|
      first = t273_lock(T273_LOCK, first_root)
      second_root = "#{first_root}-moved"
      begin
        t273_write(File.join(second_root, "Gemfile.lock"), T273_LOCK)
        second = Celerite::CacheIdentity::LockIdentity.detect(File.join(second_root, "Gemfile.lock"), project_root: second_root)
        second.same?(first).should be_true
        second.to_json.should_not contain(first_root)
        second.to_json.should_not contain(second_root)
      ensure
        FileUtils.rm_rf(second_root)
      end
    end
  end

  it "distinguishes every required byte and semantic change" do
    t273_with_lock do |project|
      baseline = t273_lock(T273_LOCK, project)
      variants = [
        T273_LOCK + "# byte\n",
        T273_LOCK.gsub("\n", "\r\n"),
        T273_LOCK.sub("4.0.24", "4.0.23"),
        T273_LOCK.sub("a" * 64, "c" * 64),
        T273_LOCK.sub("  x86_64-linux\n", ""),
      ]
      variants.each do |body|
        t273_write(File.join(project, "Gemfile.lock"), body)
        Celerite::CacheIdentity::LockIdentity.detect(File.join(project, "Gemfile.lock"), project_root: project)
          .same?(baseline).should be_false
      end
      Celerite::CacheIdentity::LockIdentity.detect(File.join(project, "Gemfile.lock"), project_root: project,
        parser_revision: "celerite-lockfile/0").same?(baseline).should be_false
    end
  end

  it "uses a path-free hash for a configured lockfile slot" do
    first = Celerite::CacheIdentity::LockIdentity.slot_for("/one/project/Other.lock", "/one/project")
    second = Celerite::CacheIdentity::LockIdentity.slot_for("/two/project/Other.lock", "/two/project")
    first.should eq(second)
    first.should start_with("configured:")
    first.should_not contain("/one")
    Celerite::CacheIdentity::LockIdentity.slot_for("/one/project/Gemfile.lock", "/one/project").should eq("default")
  end
end

describe Celerite::Lockfile do
  it "replaces a pre-existing file atomically and preserves CRLF without temp files" do
    t273_with_lock do |project|
      path = File.join(project, "Gemfile.lock")
      File.write(path, "old bytes\r\n")
      Celerite::Lockfile.write(path, "new one\r\nnew two\r\n", preserve_crlf: true)
      File.read(path).should eq("new one\r\nnew two\r\n")
      Dir.children(project).any?(&.ends_with?(".tmp")).should be_false
    end
  end

  it "maps a failed replacement while retaining the old bytes and cleaning temp" do
    {% if flag?(:windows) %}
      t273_with_lock do |project|
        path = File.join(project, "Gemfile.lock")
        File.write(path, "old bytes\r\n")
        attrib = "C:\\Windows\\System32\\attrib.exe"
        Process.run(attrib, ["+R", path], output: Process::Redirect::Close, error: Process::Redirect::Close).success?.should be_true
        begin
          expect_raises(File::AccessDeniedError) { File.open(path, "w") { |io| io << "probe" } }
          expect_raises(Celerite::PermissionError) do
            Celerite::Lockfile.write(path, "new bytes\r\n", preserve_crlf: true)
          end
        ensure
          Process.run(attrib, ["-R", path], output: Process::Redirect::Close, error: Process::Redirect::Close).success?.should be_true
        end
        File.read(path).should eq("old bytes\r\n")
        Dir.children(project).any?(&.ends_with?(".tmp")).should be_false
      end
    {% else %}
      pending!("read-only replacement probe is Windows-specific")
    {% end %}
  end
end
