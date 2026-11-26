require "./spec_helper"
require "../src/celerite/bridge/client"

private def components : JSON::Any
  parsed = JSON.parse <<-JSON
  {"sources":[{"type":"gem","remote":"https://rubygems.org"}],
   "credential_namespace":"0123456789abcdef",
   "checksums":[{"name":"native","version":"1.0.0","platform":"ruby","checksums":["#{"a" * 64}"]}],
   "platform":{"local":"x86_64-linux","locked":["ruby","x86_64-linux"],"force_ruby_platform":false},
   "abi":{"ruby_api_version":"3.4.0","extension_api_version":"3.4.0-static","rbconfig_ruby_version":"4.0.7"},
   "build":{"native":["--verbose","--jobs=2"]}}
  JSON
  parsed.as_h["credential_namespace"] = JSON::Any.new(Celerite::PlanCache.namespace)
  JSON::Any.new(parsed.as_h)
end

private def in_cache(& : String ->)
  saved = {} of String => String?
  root = File.expand_path("../.tmp-t259/spec-cache", __DIR__)
  FileUtils.rm_rf(root)
  Dir.mkdir_p(root)
  saved = {"CELERITE_PLAN_CACHE"       => ENV["CELERITE_PLAN_CACHE"]?,
           "CELERITE_PLAN_CACHE_DEBUG" => ENV["CELERITE_PLAN_CACHE_DEBUG"]?,
           "CELERITE_CACHE_DIR"        => ENV["CELERITE_CACHE_DIR"]?,
           "PATH"                      => ENV["PATH"]?}
  ENV["CELERITE_PLAN_CACHE"] = "1"
  ENV.delete("CELERITE_PLAN_CACHE_DEBUG")
  ENV["CELERITE_CACHE_DIR"] = root
  yield root
ensure
  if saved
    saved.each do |k, v|
      if v
        ENV[k] = v
      else
        ENV.delete(k)
      end
    end
  end
  if root
    FileUtils.rm_rf(root)
  end
end

private def fixture(key : String, value : JSON::Any,
                    payload : JSON::Any = JSON.parse(%({"specs":[],"plan":{},"installed_snapshot":[]})),
                    filename : String? = nil) : String
  path = Celerite::PlanCache.entry_path(key).not_nil!
  Dir.mkdir_p(File.dirname(path))
  entry = {"format" => Celerite::PlanCache::FORMAT, "written_at" => "2026-11-24T08:00:00Z",
           "digest" => Digest::SHA256.hexdigest(Celerite::PlanCache.canonical_json(payload)),
           "key" => value, "payload" => payload}
  target = filename ? File.join(File.dirname(path), filename) : path
  File.write(target, entry.to_json)
  target
end

private def cache_components(version : String = "1.0.0") : JSON::Any
  h = components.as_h.dup
  checksums = h["checksums"].as_a.dup
  row = checksums[0].as_h.dup
  row["version"] = JSON::Any.new(version)
  checksums[0] = JSON::Any.new(row)
  h["checksums"] = JSON::Any.new(checksums)
  JSON::Any.new(h)
end

private def cache_payload(marker : String = "ok") : JSON::Any
  JSON.parse(%({"specs":[{"name":"native","version":"1.0.0"}],"plan":{"marker":"#{marker}"},"installed_snapshot":[]}))
end

private def cache_key(value : JSON::Any) : String
  Celerite::PlanCache.key_for(value).not_nil!
end

private def set_cache_mtime(path : String, seconds : Int64) : Nil
  time = Time.unix(1_700_000_000_i64 + seconds)
  File.utime(time, time, path)
end

private def with_cache_debug_io(&)
  saved = Celerite::PlanCache.debug_io
  io = IO::Memory.new
  Celerite::PlanCache.debug_io = io
  yield io
ensure
  Celerite::PlanCache.debug_io = saved if saved
end

describe Celerite::PlanCache do
  it "is disabled by default and enabled only by exact 1" do
    saved = ENV["CELERITE_PLAN_CACHE"]?
    ENV.delete("CELERITE_PLAN_CACHE"); Celerite::PlanCache.enabled?.should be_false
    ENV["CELERITE_PLAN_CACHE"] = "true"; Celerite::PlanCache.enabled?.should be_false
    ENV["CELERITE_PLAN_CACHE"] = "1"; Celerite::PlanCache.enabled?.should be_true
  ensure
    if saved
      ENV["CELERITE_PLAN_CACHE"] = saved
    else
      ENV.delete("CELERITE_PLAN_CACHE")
    end
  end

  it "has six components and lowercase SHA256" do
    Celerite::PlanCache.key_for(components).not_nil!.should match(/\A[0-9a-f]{64}\z/)
    components.as_h.keys.sort.should eq(%w[abi build checksums credential_namespace platform sources])
  end

  it "returns unknown for each missing component" do
    components.as_h.each_key do |name|
      Celerite::PlanCache.key_for(JSON::Any.new(components.as_h.reject { |k, _| k == name })).should be_nil
    end
  end

  it "rejects empty and malformed checksums" do
    [JSON.parse("[]"), JSON.parse(%([{"name":"native","version":"1.0.0","platform":"ruby","checksums":["bad"]}]))].each do |v|
      h = components.as_h.dup; h["checksums"] = v
      Celerite::PlanCache.key_for(JSON::Any.new(h)).should be_nil
    end
  end

  it "normalizes GEM case, trailing slash and userinfo" do
    a = Celerite::PlanCache.normalize_source("GEM", "HTTPS://user:secret@EXAMPLE.COM/")
    b = Celerite::PlanCache.normalize_source("GEM", "https://example.com")
    a.should eq(b); a.not_nil!.to_json.should_not contain("secret")
    a.not_nil!["remote"].as_s.should eq("https://example.com")
  end

  it "accepts uppercase checksums as the same lowercase key component" do
    upper = components.as_h.dup
    row = upper["checksums"].as_a[0].as_h.dup
    row["checksums"] = JSON::Any.new([JSON::Any.new("A" * 64)])
    upper["checksums"] = JSON::Any.new([JSON::Any.new(row)])
    normalized = Celerite::Checksum.normalize_hex("A" * 64).not_nil!
    lower = components.as_h.dup
    lower_row = lower["checksums"].as_a[0].as_h.dup
    lower_row["checksums"] = JSON::Any.new([JSON::Any.new(normalized)])
    lower["checksums"] = JSON::Any.new([JSON::Any.new(lower_row)])
    Celerite::PlanCache.key_for(JSON::Any.new(upper)).should be_nil
    Celerite::PlanCache.key_for(JSON::Any.new(lower)).should eq(Celerite::PlanCache.key_for(components))
  end

  it "expands PATH with slash" do
    Celerite::PlanCache.normalize_source("PATH", "vendor\\gem", project_root: "C:/work").not_nil!["remote"].as_s.should eq("C:/work/vendor/gem/")
  end

  it "requires 40-hex GIT revision and includes glob/submodules" do
    a = Celerite::PlanCache.normalize_source("GIT", "https://user:secret@EXAMPLE.COM/repo.git/", revision: "A" * 40, submodules: true, glob: "ext/*")
    a.not_nil!["revision"].as_s.should eq("a" * 40)
    a.not_nil!["remote"].as_s.should eq("https://example.com/repo.git")
    Celerite::PlanCache.normalize_source("GIT", "https://example.com/repo").should be_nil
    Celerite::PlanCache.normalize_source("GIT", "https://example.com/repo", revision: "abc").should be_nil
  end

  it "preserves custom type and requires plugin_type" do
    Celerite::PlanCache.normalize_source("PLUGIN", "", plugin_type: "rubygems").not_nil!["type"].as_s.should eq("PLUGIN")
    Celerite::PlanCache.normalize_source("PLUGIN", "https://secret.example").should be_nil
  end

  it "changes credential namespace without exposing it" do
    ENV["BUNDLE_TOKEN__PRIVATE"] = "secret-one"
    a = Celerite::PlanCache.build_key(components["sources"], components["checksums"], components["platform"], components["abi"], components["build"])
    ENV["BUNDLE_TOKEN__PRIVATE"] = "secret-two"
    b = Celerite::PlanCache.build_key(components["sources"], components["checksums"], components["platform"], components["abi"], components["build"])
    a.should_not eq(b)
  ensure
    ENV.delete("BUNDLE_TOKEN__PRIVATE")
  end

  it "normalizes checksums, platforms and build args from lock/config" do
    with_project({"Gemfile" => "source 'https://rubygems.org'\n", "Gemfile.lock" => <<-LOCK}) do |root|
      GEM
        remote: https://rubygems.org/
        specs:
          native (1.0.0)
      PLATFORMS
        ruby
        x86_64-linux
      CHECKSUMS
        native (1.0.0) #{"A" * 64}
      BUNDLED WITH
         4.0.24
      LOCK
      abi = Celerite::FastPathStore::Abi.new("3.4", "3.4-static", "4.0")
      cfg = Celerite::Config.new(root, {"BUNDLE_BUILD__NATIVE" => "--verbose   --jobs=2"} of String => Celerite::Config::Value)
      v = Celerite::PlanCache.components_for("https://rubygems.org/", Celerite::Definition.build.lockfile!, root, "x86_64-linux", abi, cfg).not_nil!
      v["checksums"][0]["checksums"][0].as_s.should eq("a" * 64)
      v["build"]["native"].as_a.map(&.as_s).should eq(["--verbose", "--jobs=2"])
      v["platform"]["locked"].as_a.map(&.as_s).should contain("ruby")
    end
  end

  it "returns unknown for missing checksum, local platform or incomplete ABI" do
    with_project({"Gemfile" => "source 'https://rubygems.org'\n", "Gemfile.lock" => <<-LOCK}) do |root|
      GEM
        remote: https://rubygems.org/
        specs:
          native (1.0.0)
      PLATFORMS
        ruby
      BUNDLED WITH
         4.0.24
      LOCK
      lock = Celerite::Definition.build.lockfile!; cfg = Celerite::Config.new(root)
      Celerite::PlanCache.components_for("https://rubygems.org", lock, root, "x86_64-linux", Celerite::FastPathStore::Abi.new("3", "3", "4"), cfg).should be_nil
      Celerite::PlanCache.components_for("https://rubygems.org", lock, root, nil, Celerite::FastPathStore::Abi.new("3", "3", "4"), cfg).should be_nil
      Celerite::PlanCache.components_for("https://rubygems.org", lock, root, "x86_64-linux", Celerite::FastPathStore::Abi.new("", "3", "4"), cfg).should be_nil
    end
  end

  it "changes platform and force_ruby_platform independently" do
    p = components["platform"].as_h.dup; h = components.as_h.dup
    p["local"] = JSON::Any.new("arm64-linux"); h["platform"] = JSON::Any.new(p)
    Celerite::PlanCache.key_for(JSON::Any.new(h)).should_not eq(Celerite::PlanCache.key_for(components))
    p["local"] = JSON::Any.new("x86_64-linux"); p["force_ruby_platform"] = JSON::Any.new(true)
    Celerite::PlanCache.key_for(JSON::Any.new(h)).should_not eq(Celerite::PlanCache.key_for(components))
  end

  it "rejects incomplete ABI and preserves build order" do
    h = components.as_h.dup; a = components["abi"].as_h.dup; a["extension_api_version"] = JSON::Any.new(""); h["abi"] = JSON::Any.new(a)
    Celerite::PlanCache.key_for(JSON::Any.new(h)).should be_nil
    h = components.as_h.dup; b = components["build"].as_h.dup; b["native"] = JSON::Any.new(["--jobs=2", "--verbose"].map { |v| JSON::Any.new(v) }); h["build"] = JSON::Any.new(b)
    Celerite::PlanCache.key_for(JSON::Any.new(h)).should_not eq(Celerite::PlanCache.key_for(components))
  end

  it "canonicalizes object order and preserves arrays" do
    a = JSON.parse(%({"z":[1,2],"a":{"b":true,"a":"x"}})); b = JSON.parse(%({"a":{"a":"x","b":true},"z":[1,2]}))
    Celerite::PlanCache.canonical_json(a).should eq(%({"a":{"a":"x","b":true},"z":[1,2]}))
    Celerite::PlanCache.canonical_json(a).should eq(Celerite::PlanCache.canonical_json(b))
  end

  it "reads a manual fixture as hit and misses when disabled" do
    in_cache do
      key = Celerite::PlanCache.key_for(components).not_nil!
      fixture(key, components); Celerite::PlanCache.read(key).hit?.should be_true
      Celerite::PlanCache.read("unknown").unknown?.should be_true
      ENV["CELERITE_PLAN_CACHE"] = "0"; Celerite::PlanCache.read(key).miss?.should be_true
    end
  end

  it "deletes truncated and invalid JSON" do
    in_cache do
      key = Celerite::PlanCache.key_for(components).not_nil!
      path = fixture(key, components); File.write(path, File.read(path)[0, 30])
      Celerite::PlanCache.read(key).corrupt?.should be_true; File.exists?(path).should be_false
      path = fixture(key, components); File.write(path, "{bad")
      Celerite::PlanCache.read(key).corrupt?.should be_true; File.exists?(path).should be_false
    end
  end

  it "deletes wrong format" do
    in_cache do
      key = Celerite::PlanCache.key_for(components).not_nil!; path = fixture(key, components)
      h = JSON.parse(File.read(path)).as_h; h["format"] = JSON::Any.new("bad"); File.write(path, h.to_json)
      Celerite::PlanCache.read(key).corrupt?.should be_true; File.exists?(path).should be_false
    end
  end

  it "deletes wrong filename" do
    in_cache do
      key = Celerite::PlanCache.key_for(components).not_nil!; wrong = "f" * 64
      fixture(key, components, filename: "#{wrong}.json")
      Celerite::PlanCache.read(wrong).corrupt?.should be_true
      File.exists?(File.join(File.dirname(Celerite::PlanCache.entry_path(wrong).not_nil!), "#{wrong}.json")).should be_false
    end
  end

  it "deletes tampered embedded key" do
    in_cache do
      key = Celerite::PlanCache.key_for(components).not_nil!; path = fixture(key, components)
      h = JSON.parse(File.read(path)).as_h; h["key"].as_h["credential_namespace"] = JSON::Any.new("fedcba9876543210"); File.write(path, h.to_json)
      Celerite::PlanCache.read(key).corrupt?.should be_true; File.exists?(path).should be_false
    end
  end

  it "rejects an embedded credential namespace from another context" do
    in_cache do
      other = "fedcba9876543210"
      h = components.as_h.dup; h["credential_namespace"] = JSON::Any.new(other); foreign = JSON::Any.new(h)
      key = Celerite::PlanCache.key_for(foreign).not_nil!
      path = fixture(key, foreign)
      Celerite::PlanCache.read(key).corrupt?.should be_true
      File.exists?(path).should be_false
      current = Celerite::PlanCache.key_for(components).not_nil!
      current_path = fixture(current, components)
      Celerite::PlanCache.read(current).hit?.should be_true
      File.exists?(current_path).should be_true
    end
  end

  it "deletes wrong payload digest" do
    in_cache do
      key = Celerite::PlanCache.key_for(components).not_nil!; path = fixture(key, components)
      h = JSON.parse(File.read(path)).as_h; h["payload"] = JSON.parse(%({"specs":["x"],"plan":{},"installed_snapshot":[]})); File.write(path, h.to_json)
      Celerite::PlanCache.read(key).corrupt?.should be_true; File.exists?(path).should be_false
    end
  end

  it "keeps credentials out of files and debug diagnostics" do
    in_cache do |root|
      ENV["BUNDLE_TOKEN__PRIVATE"] = "credential-marker-259"; ENV["CELERITE_PLAN_CACHE_DEBUG"] = "1"
      key = Celerite::PlanCache.build_key(components["sources"], components["checksums"], components["platform"], components["abi"], components["build"]).not_nil!
      fixture(key, components)
      Dir.glob(File.join(root, "**/*")).each { |p| File.read(p).should_not contain("credential-marker-259") if File.file?(p) }
      line = Celerite::PlanCache.debug_line(Celerite::PlanCache::Status::Hit, "ok")
      line.should contain("status=hit"); line.should_not contain("credential-marker-259")
    ensure
      ENV.delete("BUNDLE_TOKEN__PRIVATE"); ENV.delete("CELERITE_PLAN_CACHE_DEBUG")
    end
  end

  it "keeps canonical key independent of project root without PATH sources" do
    lock = <<-LOCK
    GEM
      remote: https://rubygems.org/
      specs:
        native (1.0.0)

    PLATFORMS
      ruby
      x86_64-linux

    DEPENDENCIES
      native

    CHECKSUMS
      native (1.0.0-ruby) sha256=#{"a" * 64}

    BUNDLED WITH
       4.0.24
    LOCK
    abi = Celerite::FastPathStore::Abi.new("3.4.0", "3.4.0-static", "4.0.7")
    base_root = File.expand_path("../.tmp-t259", __DIR__)
    keys = [] of String?
    [File.join(base_root, "root-one"), File.join(base_root, "root-two")].each do |root|
      FileUtils.mkdir_p(root)
      with_project({"Gemfile.lock" => lock, "Gemfile" => "source 'https://rubygems.org'\ngem 'native'\n"}) do
        definition = Celerite::Definition.build
        keys << Celerite::PlanCache.key_for(Celerite::PlanCache.components_for("https://rubygems.org", definition.lockfile!, root, "x86_64-linux", abi, definition.config).not_nil!)
      end
    end
    keys[0].should_not be_nil
    keys[0].should eq(keys[1])
  end

  it "does not write or prune while disabled" do
    in_cache do |root|
      ENV["CELERITE_PLAN_CACHE"] = "0"
      value = cache_components
      result = Celerite::PlanCache.write(cache_key(value), value, cache_payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::Disabled)
      Celerite::PlanCache.prune.should be_false
      Dir.exists?(File.join(root, "plan")).should be_false
    end
  end

  it "round-trips a portable payload without leaving temp files" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      payload = cache_payload("round-trip")
      Celerite::PlanCache.write(key, value, payload).written?.should be_true
      Celerite::PlanCache.read(key).hit?.should be_true
      Celerite::PlanCache.canonical_json(Celerite::PlanCache.read(key).payload.not_nil!).should eq(Celerite::PlanCache.canonical_json(payload))
      dir = File.dirname(Celerite::PlanCache.entry_path(key).not_nil!)
      Dir.children(dir).any?(&.ends_with?(".tmp")).should be_false
    end
  end

  it "stores through the alias with a verified canonical digest" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      payload = cache_payload
      digest = Digest::SHA256.hexdigest(Celerite::PlanCache.canonical_json(payload))
      Celerite::PlanCache.store(key, value, payload, digest).written?.should be_true
      entry = JSON.parse(File.read(Celerite::PlanCache.entry_path(key).not_nil!))
      entry["digest"].as_s.should eq(digest)
    end
  end

  it "atomically replaces an existing entry for the same key" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      Celerite::PlanCache.write(key, value, cache_payload("first")).written?.should be_true
      Celerite::PlanCache.write(key, value, cache_payload("second")).written?.should be_true
      Celerite::PlanCache.read(key).payload.not_nil!["plan"]["marker"].as_s.should eq("second")
      dir = File.dirname(Celerite::PlanCache.entry_path(key).not_nil!)
      Dir.children(dir).select(&.ends_with?(".json")).size.should eq(1)
    end
  end

  it "replaces a pre-existing entry on disk and leaves no temp file" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      target = fixture(key, value, cache_payload("old-entry"))
      File.exists?(target).should be_true

      payload = cache_payload("new-entry")
      Celerite::PlanCache.write(key, value, payload).written?.should be_true
      entry = JSON.parse(File.read(target))
      Celerite::PlanCache.canonical_json(entry["payload"]).should eq(Celerite::PlanCache.canonical_json(payload))
      entry["digest"].as_s.should eq(Digest::SHA256.hexdigest(Celerite::PlanCache.canonical_json(payload)))
      Celerite::PlanCache.read(key).hit?.should be_true

      dir = File.dirname(target)
      Dir.children(dir).select(&.ends_with?(".json")).size.should eq(1)
      Dir.children(dir).any?(&.ends_with?(".tmp")).should be_false
    end
  end

  it "rejects a key that does not match the supplied components" do
    in_cache do
      result = Celerite::PlanCache.write("0" * 64, cache_components, cache_payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::InvalidKey)
    end
  end

  it "returns invalid components instead of raising for a malformed source" do
    in_cache do
      malformed = JSON.parse(%({"sources":[{"remote":"https://example.test"}],"credential_namespace":"0123456789abcdef","checksums":[],"platform":{},"abi":{},"build":{}}))
      result = Celerite::PlanCache.write("f" * 64, malformed, cache_payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::InvalidComponents)
    end
  end

  it "rejects a valid key whose credential namespace is not current" do
    in_cache do
      value = cache_components.as_h.dup
      value["credential_namespace"] = JSON::Any.new("fedcba9876543210")
      foreign = JSON::Any.new(value)
      key = cache_key(foreign)
      result = Celerite::PlanCache.write(key, foreign, cache_payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::InvalidNamespace)
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
    end
  end

  it "rejects missing or ill-typed payload sections" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      [JSON.parse("{}"), JSON.parse(%({"specs":{},"plan":{},"installed_snapshot":[]}))].each do |payload|
        result = Celerite::PlanCache.write(key, value, payload)
        result.status.should eq(Celerite::PlanCache::WriteStatus::InvalidPayload)
      end
    end
  end

  it "rejects malformed and mismatched supplied digests" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      payload = cache_payload
      Celerite::PlanCache.write(key, value, payload, "bad").status.should eq(Celerite::PlanCache::WriteStatus::InvalidDigest)
      Celerite::PlanCache.write(key, value, payload, "f" * 64).status.should eq(Celerite::PlanCache::WriteStatus::InvalidDigest)
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
    end
  end

  it "refuses root-dependent payload paths instead of caching them as portable" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      ["C:/work/gem", "/work/gem", "~/gem", "../gem", "file:///work/gem"].each do |path|
        result = Celerite::PlanCache.write(key, value, cache_payload(path))
        result.status.should eq(Celerite::PlanCache::WriteStatus::NonPortablePayload)
      end
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
    end
  end

  it "rejects parent-directory segments anywhere in unused payload fields" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      ["foo/../bar", "foo\\..\\bar", "foo/..\\bar", "foo\\../bar", "foo/..", "foo\\..", "foo/../../bar"].each do |path|
        payload = cache_payload
        payload["specs"].as_a[0].as_h["unused_path"] = JSON::Any.new(path)
        result = Celerite::PlanCache.write(key, value, payload)
        result.status.should eq(Celerite::PlanCache::WriteStatus::NonPortablePayload)
        File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
      end
    end
  end

  it "accepts payload strings whose dot runs are not parent-directory segments" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      ["gems/foo..bar", "foo.../metadata", "foo/..bar/baz"].each do |marker|
        Celerite::PlanCache.write(key, value, cache_payload(marker)).written?.should be_true
        Celerite::PlanCache.read(key).payload.not_nil!["plan"]["marker"].as_s.should eq(marker)
      end
    end
  end

  it "rejects credential-bearing payload keys" do
    in_cache do
      value = cache_components
      payload = cache_payload
      payload["plan"].as_h["token"] = JSON::Any.new("secret-marker-262")
      result = Celerite::PlanCache.write(cache_key(value), value, payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::CredentialPayload)
    end
  end

  it "rejects an active credential value even when the JSON key is innocuous" do
    in_cache do
      ENV["BUNDLE_TOKEN__WRITE"] = "credential-marker-262"
      value = cache_components
      result = Celerite::PlanCache.write(cache_key(value), value, cache_payload("credential-marker-262"))
      result.status.should eq(Celerite::PlanCache::WriteStatus::CredentialPayload)
    ensure
      ENV.delete("BUNDLE_TOKEN__WRITE")
    end
  end

  it "does not persist the plaintext credential namespace material" do
    in_cache do |root|
      ENV["BUNDLE_TOKEN__PRIVATE"] = "credential-marker-262"
      value = cache_components
      Celerite::PlanCache.write(cache_key(value), value, cache_payload).written?.should be_true
      Dir.glob(File.join(root, "**/*")).each do |path|
        File.read(path).should_not contain("credential-marker-262") if File.file?(path)
      end
    ensure
      ENV.delete("BUNDLE_TOKEN__PRIVATE")
    end
  end

  it "rejects an entry larger than the byte budget before writing" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      payload = cache_payload("x" * (16 * 1024 * 1024))
      result = Celerite::PlanCache.write(key, value, payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::TooLarge)
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
    end
  end

  it "reports rename failure and removes its temp file" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      target = Celerite::PlanCache.entry_path(key).not_nil!
      Dir.mkdir_p(target)
      result = Celerite::PlanCache.write(key, value, cache_payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::IoError)
      Dir.children(File.dirname(target)).any?(&.ends_with?(".tmp")).should be_false
      Dir.exists?(target).should be_true
    end
  end

  it "deletes a writer-produced entry after payload tampering" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      Celerite::PlanCache.write(key, value, cache_payload).written?.should be_true
      path = Celerite::PlanCache.entry_path(key).not_nil!
      entry = JSON.parse(File.read(path))
      entry["payload"]["plan"].as_h["marker"] = JSON::Any.new("tampered")
      File.write(path, entry.to_json)
      Celerite::PlanCache.read(key).corrupt?.should be_true
      File.exists?(path).should be_false
    end
  end

  it "prunes the oldest entries when the namespace exceeds its count budget" do
    in_cache do
      entries = (1..3).map do |index|
        value = cache_components("1.0.#{index}")
        key = cache_key(value)
        Celerite::PlanCache.write(key, value, cache_payload("entry-#{index}")).written?.should be_true
        path = Celerite::PlanCache.entry_path(key).not_nil!
        set_cache_mtime(path, index.to_i64)
        {key: key, path: path}
      end
      Celerite::PlanCache.prune(2).should be_true
      File.exists?(entries[0][:path]).should be_false
      File.exists?(entries[1][:path]).should be_true
      File.exists?(entries[2][:path]).should be_true
    end
  end

  it "prunes oldest entries until the namespace byte budget holds" do
    in_cache do
      specs = [{"a" * 1024, 1_i64}, {"b" * 2048, 2_i64}, {"c" * 512, 3_i64}]
      paths = specs.map do |(marker, seconds)|
        value = cache_components("1.0.#{seconds}")
        key = cache_key(value)
        Celerite::PlanCache.write(key, value, cache_payload(marker)).written?.should be_true
        path = Celerite::PlanCache.entry_path(key).not_nil!
        set_cache_mtime(path, seconds)
        path
      end
      max_bytes = File.info(paths[1]).size + File.info(paths[2]).size
      Celerite::PlanCache.prune(10, max_bytes).should be_true
      File.exists?(paths[0]).should be_false
      File.exists?(paths[1]).should be_true
      File.exists?(paths[2]).should be_true
    end
  end

  it "never prunes or overwrites another credential namespace" do
    in_cache do |root|
      saved = ENV["BUNDLE_TOKEN__FOREIGN"]?
      ENV["BUNDLE_TOKEN__FOREIGN"] = "foreign-marker-262"
      foreign = cache_components("2.0.0")
      foreign_key = cache_key(foreign)
      foreign_path = fixture(foreign_key, foreign)
      ENV.delete("BUNDLE_TOKEN__FOREIGN")

      value = cache_components
      key = cache_key(value)
      Celerite::PlanCache.write(key, value, cache_payload).written?.should be_true
      Celerite::PlanCache.prune(0, 0).should be_true
      File.exists?(foreign_path).should be_true
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
      result = Celerite::PlanCache.write(foreign_key, foreign, cache_payload)
      result.status.should eq(Celerite::PlanCache::WriteStatus::InvalidNamespace)
    ensure
      if saved
        ENV["BUNDLE_TOKEN__FOREIGN"] = saved
      else
        ENV.delete("BUNDLE_TOKEN__FOREIGN")
      end
    end
  end

  it "treats a missing namespace as pruned and rejects negative budgets" do
    in_cache do
      Celerite::PlanCache.prune.should be_true
      Celerite::PlanCache.prune(-1).should be_false
      Celerite::PlanCache.prune(1, -1_i64).should be_false
    end
  end

  it "deletes a written entry and rejects invalid delete keys" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      Celerite::PlanCache.write(key, value, cache_payload).written?.should be_true
      Celerite::PlanCache.delete(key).should be_true
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
      Celerite::PlanCache.delete(key).should be_true
      Celerite::PlanCache.delete("../escape").should be_false
      Celerite::PlanCache.write(key, value, cache_payload).written?.should be_true
      ENV["CELERITE_PLAN_CACHE"] = "0"
      Celerite::PlanCache.delete(key).should be_false
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_true
    end
  end

  it "keeps successful write and read diagnostics silent by default" do
    with_cache_debug_io do |io|
      in_cache do
        value = cache_components
        key = cache_key(value)
        Celerite::PlanCache.write(key, value, cache_payload).written?.should be_true
        Celerite::PlanCache.read(key).hit?.should be_true
        io.to_s.should be_empty
      end
    end
  end

  it "emits credential-free diagnostics only when debug is exactly 1" do
    with_cache_debug_io do |io|
      in_cache do
        ENV["CELERITE_PLAN_CACHE_DEBUG"] = "1"
        value = cache_components
        key = cache_key(value)
        Celerite::PlanCache.write(key, value, cache_payload).written?.should be_true
        Celerite::PlanCache.read(key).hit?.should be_true
        io.to_s.should contain("operation=write status=written")
        io.to_s.should contain("status=hit")
        io.to_s.should_not contain("credential")
      end
    end
  end

  it "reads a portable writer entry after the cache root moves" do
    in_cache do |root|
      moved_root = "#{root}-moved"
      FileUtils.rm_rf(moved_root)
      value = cache_components
      key = cache_key(value)
      Celerite::PlanCache.write(key, value, cache_payload("relocatable")).written?.should be_true
      FileUtils.mv(root, moved_root)
      ENV["CELERITE_CACHE_DIR"] = moved_root
      Celerite::PlanCache.read(key).hit?.should be_true
      Celerite::PlanCache.read(key).payload.not_nil!["plan"]["marker"].as_s.should eq("relocatable")
    ensure
      FileUtils.rm_rf(moved_root) if moved_root
    end
  end

  it "leaves temp and unrelated files untouched while pruning entries" do
    in_cache do
      value = cache_components
      key = cache_key(value)
      Celerite::PlanCache.write(key, value, cache_payload).written?.should be_true
      dir = File.dirname(Celerite::PlanCache.entry_path(key).not_nil!)
      temp = File.join(dir, ".plan-stale.tmp")
      notes = File.join(dir, "notes.txt")
      File.write(temp, "partial")
      File.write(notes, "keep")
      Celerite::PlanCache.prune(0, 0).should be_true
      File.exists?(temp).should be_true
      File.exists?(notes).should be_true
      File.exists?(Celerite::PlanCache.entry_path(key).not_nil!).should be_false
    end
  end

  it "accepts only remote GEM source spellings in locked-plan provenance" do
    Celerite::PlanCache.gem_sources_only?(["GEM"], ["GEM"]).should be_true
    Celerite::PlanCache.gem_sources_only?(["GEM"], ["Rubygems", "Metadata"]).should be_true
    Celerite::PlanCache.gem_sources_only?(["Rubygems"], ["Rubygems"]).should be_true
    ["PATH", "GIT", "PLUGIN", "Plugin", "METADATA", "Unknown", ""].each do |type|
      Celerite::PlanCache.gem_sources_only?([type], ["GEM"]).should be_false
      Celerite::PlanCache.gem_sources_only?(["GEM"], [type]).should be_false
    end
  end

  it "starts no Ruby with empty PATH" do
    in_cache do |root|
      saved = ENV["PATH"]?; saved_stats = ENV["CELERITE_BRIDGE_STATS"]?; ENV["PATH"] = File.join(root, "empty"); Dir.mkdir_p(ENV["PATH"]); ENV["CELERITE_BRIDGE_STATS"] = "1"
      key = Celerite::PlanCache.key_for(components).not_nil!; fixture(key, components)
      Celerite::PlanCache.read(key).hit?.should be_true
      Celerite::Bridge::BridgeStats.begin_run; Celerite::PlanCache.namespace.should match(/\A[0-9a-f]{16}\z/)
      Celerite::Bridge::BridgeStats.procs.should eq(0)
    ensure
      if saved
        ENV["PATH"] = saved
      else
        ENV.delete("PATH")
      end
      if saved_stats
        ENV["CELERITE_BRIDGE_STATS"] = saved_stats
      else
        ENV.delete("CELERITE_BRIDGE_STATS")
      end
    end
  end
end
