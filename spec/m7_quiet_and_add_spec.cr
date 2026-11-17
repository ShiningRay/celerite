require "./spec_helper"
require "../src/celerite"

# Reference anchors for this round:
# * `bundler/cli/install.rb:11`, `cli/update.rb:12`, `cli/add.rb:15`,
#   `cli/cache.rb:12` — `Bundler.ui.level = "warn" if options[:quiet]`; because
#   `Bundle complete!` / ``Use `bundle info …` `` are `ui.confirm`, `--quiet`
#   silences the whole stdout while warnings and errors keep flowing.
# * `bundler/cli/lock.rb:24` — `Bundler.ui.output_stream = :stderr if print`,
#   and `:70-76` add-checksums/normalize-platforms force a resolution; the
#   `Resolving dependencies...` line (`resolver.rb:34`) therefore appears
#   whenever no lockfile exists yet.
# * `bundler/cli.rb` binstubs options have no `quiet`, so `--quiet` must fail as
#   an unknown switch (Thor exits 15), and the removed `--path` switch
#   (`lazy_default: "bin"`) reports the value it would have remembered.
# * `bundler/dsl.rb:255-327` — a repeated `add` with the same requirement is
#   dropped by `Injector#inject` (`@deps -= builder.dependencies`) and leaves
#   the Gemfile untouched; a different requirement raises a DSLError framed
#   against the synthetic `injected gems` file.
private def quiet_index_remote : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

private def quiet_gemfile : String
  %(source "#{quiet_index_remote}"\ngem "json_pure", "2.6.0"\n)
end

# `with_project` changes directory, so the bridge cannot be located relative to
# the running executable anymore: pin CELERITE_BRIDGE_SERVER and give the run a
# private HOME/GEM_HOME so the install lands inside the sandbox, mirroring the
# reference's isolated `--path` free layout.
private def with_bundler_profile(version : String, & : ->) : Nil
  previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
  ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = version
  begin
    yield
  ensure
    previous ? (ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous) : ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
  end
end

private def with_add_env(dir : String, & : ->) : Nil
  keys = {"HOME", "USERPROFILE", "GEM_HOME", "GEM_PATH", "CELERITE_BRIDGE_SERVER"}
  saved = keys.map { |key| {key, ENV[key]?} }
  home = File.join(dir, "home")
  gems = File.join(dir, "gems")
  Dir.mkdir_p(home)
  Dir.mkdir_p(gems)
  ENV["HOME"] = home
  ENV["USERPROFILE"] = home
  ENV["GEM_HOME"] = gems
  ENV["GEM_PATH"] = gems
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    saved.each do |(key, value)|
      value ? (ENV[key] = value) : ENV.delete(key)
    end
  end
end

describe "--quiet" do
  it "silences install output but keeps the install itself" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, out, _err = run_cli(["install", "--quiet"])
        out.should eq("")
        code.should eq(0)
      end
    end
  end

  it "keeps stderr on the error path" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, out, err = run_cli(["install", "nosuchgem", "--quiet"])
        out.should eq("")
        err.should_not be_empty
        code.should_not eq(0)
      end
    end
  end

  it "is rejected by commands whose Thor table has no quiet option" do
    with_project({"Gemfile" => quiet_gemfile}) do
      {"check", "lock", "binstubs", "init", "pristine", "clean"}.each do |command|
        code, _out, err = run_cli([command, "--quiet"])
        code.should eq(15)
        err.should contain(%(Unknown switches "--quiet"))
      end
    end
  end

  # `print_command` runs in Thor's dispatch callback, before the command body
  # lowers the UI level (`bundler/cli.rb:34-39` vs `cli/install.rb:11`), so the
  # echo still appears while every `info`/`confirm` line is silenced.
  it "still echoes the command under --verbose" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, out, _err = run_cli(["install", "--quiet", "--verbose"])
        code.should eq(0)
        out.should eq("Running `bundle install --quiet --verbose` with bundler 4.0.24\n")
      end
    end
  end
end

describe "lock progress lines" do
  it "announces the resolution under --print without a lockfile" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, out, err = run_cli(["lock", "--print"])
        code.should eq(0)
        err.should contain("Resolving dependencies...")
        out.should contain("GEM")
      end
    end
  end

  it "keeps the resolution line for forcing switches without a lockfile" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, out, _err = run_cli(["lock", "--add-checksums"])
        code.should eq(0)
        out.should contain("Resolving dependencies...")
        out.should contain("Writing lockfile to")
      end
    end
  end

  it "stays quiet about resolving once a lockfile exists" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        run_cli(["lock"])
        code, _out, err = run_cli(["lock", "--print"])
        code.should eq(0)
        err.should eq("")
      end
    end
  end
end

describe "binstubs switch surface" do
  it "reports the removed --path flag with its remembered default" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, _out, err = run_cli(["binstubs", "json_pure", "--path"])
        code.should eq(15)
        err.should contain("The `--path` flag has been removed")
        err.should contain("config set bin 'bin'")
      end
    end
  end

  it "uses the given --path value when one is supplied" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, _out, err = run_cli(["binstubs", "json_pure", "--path", "vendor/bin"])
        code.should eq(15)
        err.should contain("config set bin 'vendor/bin'")
      end
    end
  end

  it "treats a switch after --path as the lazy default" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, _out, err = run_cli(["binstubs", "json_pure", "--path", "--force"])
        code.should eq(15)
        err.should contain("config set bin 'bin'")
      end
    end
  end
end

describe "--cooldown profile gate" do
  it "is unknown at bundler 2.7.2" do
    previous = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?
    ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = "2.7.2"
    begin
      with_project({"Gemfile" => quiet_gemfile}) do
        code, _out, err = run_cli(["lock", "--cooldown", "5"])
        code.should eq(15)
        err.should contain(%(Unknown switches "--cooldown"))
      end
    ensure
      previous ? (ENV["CELERITE_PROFILE_BUNDLER_VERSION"] = previous) : ENV.delete("CELERITE_PROFILE_BUNDLER_VERSION")
    end
  end
end

describe "add on an already declared gem" do
  # `gem "json_pure"` normalises to `>= 0`, so `add json_pure` asks for exactly
  # the requirement the Gemfile already declares and `Injector#inject` drops the
  # dependency before any Gemfile write happens. A pinned `= 2.6.0` instead
  # conflicts with the requested `>= 0` — that case lives in the `Gem already
  # added` example below.
  #
  # `Injector#inject` still runs `to_definition` → `remotely!` → `@definition.lock`
  # (injector.rb:40-53) even when the dependency list empties out, so an existing
  # lockfile makes the whole run silent (`write_lock` only touches the file when
  # the regenerated contents match, definition.rb:401-419) whereas a missing
  # lockfile still announces the fetch and the resolution.
  it "leaves the Gemfile byte-identical and stays silent once a lockfile exists" do
    [%(gem "json_pure"), %(gem "json_pure", ">= 0")].each do |line|
      with_project({"Gemfile" => %(source "#{quiet_index_remote}"\n#{line}\n)}) do |dir|
        original = File.read(File.join(dir, "Gemfile"))
        with_add_env(dir) do
          run_cli(["lock"])
          code, out, err = run_cli(["add", "json_pure", "--skip-install"])
          out.should eq("")
          err.should eq("")
          code.should eq(0)
        end
        File.read(File.join(dir, "Gemfile")).should eq(original)
      end
    end
  end

  it "still resolves and writes the lockfile when none exists yet" do
    with_project({"Gemfile" => %(source "#{quiet_index_remote}"\ngem "json_pure"\n)}) do |dir|
      original = File.read(File.join(dir, "Gemfile"))
      with_add_env(dir) do
        code, out, err = run_cli(["add", "json_pure", "--skip-install"])
        code.should eq(0)
        err.should eq("")
        out.should contain("Fetching source index from #{quiet_index_remote}/")
        out.should contain("Resolving dependencies...")
        lockfile = File.join(dir, "Gemfile.lock")
        File.file?(lockfile).should be_true
        File.read(lockfile).should contain("DEPENDENCIES")
      end
      File.read(File.join(dir, "Gemfile")).should eq(original)
    end
  end

  it "raises the injected-gems conflict when the requirement differs" do
    with_project({"Gemfile" => %(source "#{quiet_index_remote}"\ngem "json_pure", "~> 2.6"\n)}) do |dir|
      original = File.read(File.join(dir, "Gemfile"))
      captured = ""
      with_add_env(dir) do
        code, out, err = run_cli(["add", "json_pure", "--version", "2.6.0", "--skip-install"])
        code.should eq(4)
        out.should eq("")
        captured = err
      end
      captured.should contain("There was an error parsing `injected gems`")
      captured.should contain("You specified: json_pure (~> 2.6) and json_pure (= 2.6.0)")
      captured.should contain("If you want to update the gem version, run `bundle update json_pure`")
      captured.should contain("from #{File.dirname(File.join(dir, "Gemfile")).gsub('\\', '/')}/injected gems:1")
      captured.should contain(%(>  gem "json_pure", "= 2.6.0"))
      File.read(File.join(dir, "Gemfile")).should eq(original)
    end
  end

  it "reports `Gem already added` when only the existing requirement is specific" do
    with_project({"Gemfile" => %(source "#{quiet_index_remote}"\ngem "json_pure", "~> 2.6"\n)}) do |dir|
      captured = ""
      with_add_env(dir) do
        code, _out, err = run_cli(["add", "json_pure", "--skip-install"])
        code.should eq(4)
        captured = err
      end
      captured.should contain("You specified: json_pure (~> 2.6) and json_pure (>= 0). Gem already added.")
    end
  end

  it "appends a single new line and keeps the original bytes" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      original = File.read(File.join(dir, "Gemfile"))
      with_add_env(dir) do
        code, _out, _err = run_cli(["add", "racc", "--group", "dev", "--skip-install"])
        code.should eq(0)
      end
      appended = File.read(File.join(dir, "Gemfile"))
      appended.starts_with?(original).should be_true
      appended.should contain(%(gem "racc", "~> 1.8", group: :dev))
      appended.scan(/gem "racc"/).size.should eq(1)
    end
  end

  it "renders several groups as an inspect list" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        code, _out, _err = run_cli(["add", "racc", "--group", "dev,test", "--skip-install"])
        code.should eq(0)
      end
      File.read(File.join(dir, "Gemfile")).should contain(%(gem "racc", "~> 1.8", groups: [:dev, :test]))
    end
  end
end

# The bundler 2.7.x profile keeps the features 4.x removed or reworded:
# * `cli/binstubs.rb:15` remembers `--path` in `.bundle/config` because `bin` is
#   a `REMEMBERED_KEY` (settings.rb:46-52), so the deprecated switch still
#   persists state before the installer runs.
# * `dsl.rb:611` parses the frame line with `trace_line.split(":")[1].to_i`, and
#   a Windows path (`C:/…/injected gems:1`) splits into `C:`, `/…/injected gems`,
#   `1`; `[1].to_i` is therefore 0, `line_number` becomes -1 and the single
#   injected line is rendered twice (once as the context line, once as the
#   marked line).
describe "bundler 2.7.2 profile" do
  it "remembers --path in .bundle/config before failing on a missing gem" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        with_bundler_profile("2.7.2") do
          code, _out, err = run_cli(["binstubs", "json_pure", "--path"])
          code.should eq(7)
          err.should contain("[DEPRECATED]")
          err.should contain("config set bin 'bin'")
          err.should contain("Could not find gem 'json_pure (= 2.6.0)' in locally installed gems.")
        end
      end
      config = File.join(dir, ".bundle", "config")
      File.file?(config).should be_true
      File.read(config).should contain(%(BUNDLE_BIN: "bin"))
      # `Bundler.bin_path` is only reached once a spec with executables exists
      # (bundler.rb:120-126), which never happens for the missing gem.
      Dir.exists?(File.join(dir, "bin")).should be_false
    end
  end

  it "keeps the lazy default when another switch follows --path" do
    with_project({"Gemfile" => quiet_gemfile}) do |dir|
      with_add_env(dir) do
        with_bundler_profile("2.7.2") do
          code, _out, _err = run_cli(["binstubs", "json_pure", "--path", "--force"])
          code.should eq(7)
        end
      end
      File.read(File.join(dir, ".bundle", "config")).should contain(%(BUNDLE_BIN: "bin"))
    end
  end

  it "renders the injected gem line twice because of the colon split" do
    with_project({"Gemfile" => %(source "#{quiet_index_remote}"\ngem "json_pure", "~> 2.6"\n)}) do |dir|
      captured = ""
      with_add_env(dir) do
        with_bundler_profile("2.7.2") do
          code, out, err = run_cli(["add", "json_pure", "--version", "2.6.0", "--skip-install"])
          code.should eq(4)
          out.should eq("")
          captured = err
        end
      end
      frames = captured.lines.select { |line| line.includes?(%(gem "json_pure", "= 2.6.0")) }
      frames.size.should eq(1)
      frames.first.should contain(%( #   >  gem "json_pure", "= 2.6.0" #  gem "json_pure", "= 2.6.0"))
    end
  end
end
