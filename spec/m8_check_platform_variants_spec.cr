require "./spec_helper"

# task-290: `check` materializes the current platform's best locked variant,
# not every platform row in a multi-platform lockfile.

private def t290_capture_check : {Int32, String, String}
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  code = Celerite::Commands.check(stdout, stderr, [] of String)
  {code, stdout.to_s, stderr.to_s}
end

private def t290_native_platform : String
  Celerite::Gem::Platform.local.to_s
end

private def t290_foreign_platform : String
  native = t290_native_platform
  native.starts_with?("x86_64-linux-musl") ? "x86_64-linux-musl2" : "x86_64-linux-musl"
end

private def t290_lock(variants : Array(String), platforms : Array(String), dependencies : String = "nokogiri") : String
  specs = variants.map { |variant| "    nokogiri (1.19.7#{variant})" }.join("\n")
  platform_lines = platforms.map { |platform| "  #{platform}" }.join("\n")
  <<-LOCK
  GEM
    remote: https://rubygems.org/
    specs:
  #{specs}

  PLATFORMS
  #{platform_lines}

  DEPENDENCIES
    #{dependencies}

  BUNDLED WITH
     4.0.24
  LOCK
end

private def t290_project(lockfile : String, extra : Hash(String, String) = {} of String => String,
                         gemfile : String = "source \"https://rubygems.org\"\n\ngem \"nokogiri\"\n") : Hash(String, String)
  {
    "Gemfile"        => gemfile,
    "Gemfile.lock"   => lockfile,
    ".bundle/config" => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
  }.merge(extra)
end

private def t290_spec_file(full_name : String) : String
  "vendor/bundle/ruby/3.4.0/specifications/#{full_name}.gemspec"
end

private def t290_with_bridge(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

describe "task-290 locked platform selection" do
  it "selects the most specific native match rather than ruby or another matching native" do
    native = Celerite::Lockfile::Spec.new("nokogiri", "1.19.7", "x86_64-linux")
    musl = Celerite::Lockfile::Spec.new("nokogiri", "1.19.7", "x86_64-linux-musl")
    ruby = Celerite::Lockfile::Spec.new("nokogiri", "1.19.7", nil)
    racc = Celerite::Lockfile::Spec.new("racc", "1.8.1", nil)

    selected = Celerite::Commands.best_match_locked_specs([ruby, musl, racc, native], Celerite::Gem::Platform.new("x86_64-linux"))
    selected.map(&.full_name).should eq(["nokogiri-1.19.7-x86_64-linux", "racc-1.8.1"])
    selected[0].should eq(native)
  end

  it "falls back to ruby only when no local native variant exists" do
    foreign = Celerite::Lockfile::Spec.new("nokogiri", "1.19.7", "x64-mingw-ucrt")
    ruby = Celerite::Lockfile::Spec.new("nokogiri", "1.19.7", nil)

    selected = Celerite::Commands.best_match_locked_specs([foreign, ruby], Celerite::Gem::Platform.new("x86_64-linux"))
    selected.map(&.full_name).should eq(["nokogiri-1.19.7"])
    selected[0].should eq(ruby)
  end

  it "preserves rows when neither native nor ruby can satisfy the local platform" do
    mingw = Celerite::Lockfile::Spec.new("nokogiri", "1.19.7", "x64-mingw-ucrt")
    darwin = Celerite::Lockfile::Spec.new("nokogiri", "1.19.7", "arm64-darwin-24")

    selected = Celerite::Commands.best_match_locked_specs([darwin, mingw], Celerite::Gem::Platform.new("x86_64-linux"))
    selected.map(&.full_name).should eq([
      "nokogiri-1.19.7-arm64-darwin-24",
      "nokogiri-1.19.7-x64-mingw-ucrt",
    ])
  end
end

describe "task-290 check with multi-platform locks" do
  it "succeeds when only the current native variant is installed" do
    native = t290_native_platform
    foreign = t290_foreign_platform
    lockfile = t290_lock(["-#{native}", "-#{foreign}", ""], [native, foreign, "ruby"])

    with_project(t290_project(lockfile, {
      t290_spec_file("nokogiri-1.19.7-#{native}") => "Gem::Specification.new\n",
    })) do
      code, out, err = t290_capture_check
      code.should eq(0)
      out.should eq("The Gemfile's dependencies are satisfied\n")
      err.should eq("")
    end
  end

  it "reports only the selected native variant when foreign and ruby variants are installed" do
    native = t290_native_platform
    foreign = t290_foreign_platform
    lockfile = t290_lock(["-#{native}", "-#{foreign}", ""], [native, foreign, "ruby"])

    with_project(t290_project(lockfile, {
      t290_spec_file("nokogiri-1.19.7-#{foreign}") => "Gem::Specification.new\n",
      t290_spec_file("nokogiri-1.19.7")            => "Gem::Specification.new\n",
    })) do
      code, out, err = t290_capture_check
      code.should eq(1)
      out.should eq("")
      err.should eq("The following gems are missing\n * nokogiri (1.19.7)\nInstall missing gems with `bundle install`\n")
    end
  end

  it "uses the ruby variant when the lock has no current native variant" do
    foreign = t290_foreign_platform
    lockfile = t290_lock(["-#{foreign}", ""], [foreign, "ruby"])

    with_project(t290_project(lockfile, {
      t290_spec_file("nokogiri-1.19.7") => "Gem::Specification.new\n",
    })) do
      code, out, err = t290_capture_check
      code.should eq(0)
      out.should eq("The Gemfile's dependencies are satisfied\n")
      err.should eq("")
    end
  end

  it "does not fall back to an installed ruby variant when the current native variant is locked but missing" do
    native = t290_native_platform
    lockfile = t290_lock(["-#{native}", ""], [native, "ruby"])

    with_project(t290_project(lockfile, {
      t290_spec_file("nokogiri-1.19.7") => "Gem::Specification.new\n",
    })) do
      code, out, err = t290_capture_check
      code.should eq(1)
      out.should eq("")
      err.should eq("The following gems are missing\n * nokogiri (1.19.7)\nInstall missing gems with `bundle install`\n")
    end
  end

  it "applies group and dependency closure filters after selecting the current platform" do
    native = t290_native_platform
    foreign = t290_foreign_platform
    lockfile = <<-LOCK
    GEM
      remote: https://rubygems.org/
      specs:
        parent (1.0.0-#{native})
          native_child (~> 1.0)
        parent (1.0.0-#{foreign})
          foreign_child (~> 1.0)
        parent (1.0.0)
          ruby_child (~> 1.0)
        native_child (1.0.0)
        foreign_child (1.0.0)
        ruby_child (1.0.0)
        optional (2.0.0)

    PLATFORMS
      #{native}
      #{foreign}
      ruby

    DEPENDENCIES
      parent
      optional

    BUNDLED WITH
       4.0.24
    LOCK
    gemfile = <<-GEMFILE
    source "https://rubygems.org"

    gem "parent"
    gem "optional", group: :test
    GEMFILE

    t290_with_bridge do
      with_project(t290_project(lockfile, {
        ".bundle/config"                         => "---\nBUNDLE_PATH: \"vendor/bundle\"\nBUNDLE_WITHOUT: \"test\"\n",
        t290_spec_file("parent-1.0.0-#{native}") => "Gem::Specification.new\n",
        t290_spec_file("native_child-1.0.0")     => "Gem::Specification.new\n",
      }, gemfile)) do
        code, out, err = t290_capture_check
        code.should eq(0), "stdout=#{out}\nstderr=#{err}"
        out.should eq("The Gemfile's dependencies are satisfied\n")
        err.should eq("")
      end
    end
  end
end
