require "./spec_helper"

# M7 task-119: the three frozen-mode lock-validation shapes that the reference
# and Celerite used to disagree on. All three fixtures under
# `fixtures/differential/` carry a `frozen` marker plus canonical lock bytes
# (blank line between every section), so `script/differential <name>` pins the
# same behaviour against bundler 4.0.24.
#
# Reference anchors (`.upstream-specs/v4.0.24/bundler`):
#   * A `definition.rb:1068-1069` (`@missing_lockfile_dep`), reported through
#     `:906-921` / `:475-492` as `Your lockfile is missing "<name>", …`.
#   * B `definition.rb:973-1015` + `spec_set.rb:87-96`: `check_lockfile` only
#     validates the dependency edges of locked rows, and `:342-345` makes
#     `resolve` return `@locked_specs` under frozen mode, so a locked row
#     nothing refers to is neither reported nor installed.
#   * C `definition.rb:1075-1078` (`dep.matches_spec?`), reported as
#     `The dependencies in your gemfile changed, …`.
A_TEXT = "Your lockfile is missing \"json_pure\", but can't be updated because frozen mode\n" +
         "is set\n" +
         "\n" +
         "Run `bundle install` elsewhere and add the updated Gemfile.lock to version\n" +
         "control.\n"
C_TEXT = "The dependencies in your gemfile changed, but the lockfile can't be updated\n" +
         "because frozen mode is set\n" +
         "\n" +
         "Run `bundle install` elsewhere and add the updated Gemfile.lock to version\n" +
         "control.\n"
B_MISSING_THREE_LINES = "The following gems are missing\n * thor (1.3.2)\n" +
                        "Install missing gems with `bundle install`\n"

# Builds the project files from the fixture, substituting the fixture-local
# index path and copying the preset install tree into the project bundle path.
private def frozen_lock_fixture_files(name : String) : Hash(String, String)
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  files = {} of String => String
  {% for file in %w[Gemfile Gemfile.lock] %}
    path = File.join(dir, {{file}})
    if File.file?(path)
      files[{{file}}] = File.read(path).gsub("@INDEX_DIR@", index)
    end
  {% end %}
  files
end

# `frozen: true` mirrors the fixture's `frozen` marker (both sides run with
# `BUNDLE_FROZEN=true`); `frozen: false` is the non-frozen control.
private def with_frozen_lock_env(name : String, frozen : Bool = true, & : String ->) : Nil
  dir = File.expand_path("../fixtures/differential/#{name}", __DIR__)
  with_project(frozen_lock_fixture_files(name)) do |project|
    FileUtils.cp_r(File.join(dir, "bundle-preset"), File.join(project, "bundle"))
    keys = {
      "HOME"                             => project,
      "USERPROFILE"                      => project,
      "GEM_HOME"                         => File.join(project, "gems"),
      "GEM_PATH"                         => File.join(project, "gems"),
      "BUNDLE_PATH"                      => File.join(project, "bundle"),
      "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
      "CELERITE_BRIDGE_SERVER"           => File.expand_path("../assets/bridge/server.rb", __DIR__),
      "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
    }
    previous = {} of String => String?
    keys.each do |key, value|
      previous[key] = ENV[key]?
      ENV[key] = value
    end
    previous["BUNDLE_FROZEN"] = ENV["BUNDLE_FROZEN"]?
    if frozen
      ENV["BUNDLE_FROZEN"] = "true"
    else
      ENV.delete("BUNDLE_FROZEN")
    end
    begin
      yield project
    ensure
      previous.each do |key, value|
        if value
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end
  end
end

private def frozen_lock_run(name : String, args : Array(String), frozen : Bool = true) : {Int32, String, String}
  code = 0
  out = ""
  err = ""
  with_frozen_lock_env(name, frozen) do |_|
    code, out, err = run_cli(args)
  end
  {code, out, err}
end

describe "M7 task-119 frozen lock validation" do
  # A: the lock lists the dependency but carries no spec row for it. The
  # reference raises `ProductionError` (exit 16) from `check` *and* `install`;
  # Celerite used to exit 1 from `check` and silently re-resolve on `install`.
  it "reports a locked dependency without a spec row for check and install" do
    code, out, err = frozen_lock_run("check-frozen-missing-locked-spec", ["check"])
    code.should eq(16), "stdout=#{out}\nstderr=#{err}"
    out.should eq("")
    err.should eq(A_TEXT)

    code, out, err = frozen_lock_run("check-frozen-missing-locked-spec", ["install"])
    code.should eq(16), "stdout=#{out}\nstderr=#{err}"
    out.should eq("")
    err.should eq(A_TEXT)
  end

  # B: a locked row nothing refers to. The reference ignores it (exit 0, no
  # output on stderr) and installs only the Gemfile dependency; Celerite used
  # to report `* thor (1.3.2)` missing on `check` and install it.
  it "ignores a locked spec row outside the Gemfile dependency closure" do
    code, out, err = frozen_lock_run("check-frozen-extra-locked-spec", ["check"])
    code.should eq(0), "stdout=#{out}\nstderr=#{err}"
    err.should eq("")
    out.should eq("The Gemfile's dependencies are satisfied\n")
  end

  it "does not install the unreferenced locked spec row" do
    with_frozen_lock_env("check-frozen-extra-locked-spec") do |project|
      code, out, err = run_cli(["install"])
      code.should eq(0), "stdout=#{out}\nstderr=#{err}"
      err.should eq("")
      out.should contain("1 gem now installed")
      out.should_not contain("thor")
      specs_dir = File.join(project, "bundle", "ruby", "4.0.0", "specifications").gsub('\\', "/")
      Dir.glob("#{specs_dir}/*.gemspec").map { |path| File.basename(path) }.sort
        .should eq(["json_pure-2.8.1.gemspec"])
    end
  end

  # C: the locked version no longer satisfies the Gemfile requirement even
  # though the DEPENDENCIES requirement *string* still matches. `check` used to
  # report the gem missing and `install` used to install the unsatisfying
  # version.
  it "reports a locked version that no longer satisfies the Gemfile" do
    code, out, err = frozen_lock_run("check-frozen-locked-version-mismatch", ["check"])
    code.should eq(16), "stdout=#{out}\nstderr=#{err}"
    out.should eq("")
    err.should eq(C_TEXT)

    code, out, err = frozen_lock_run("check-frozen-locked-version-mismatch", ["install"])
    code.should eq(16), "stdout=#{out}\nstderr=#{err}"
    out.should eq("")
    err.should eq(C_TEXT)
  end

  # Control: none of the three shapes may start misfiring on the non-frozen
  # path. A re-resolves and installs the row the lock omitted, C re-resolves to
  # the Gemfile's requirement, and in no shape does the frozen-mode wording or
  # exit 16 leak onto the non-frozen path. B keeps its pre-existing non-frozen
  # reading (the unreferenced row is reported), which is recorded as a declared
  # divergence in `docs/compat-evidence/2026-11-22.md` and left out of scope.
  it "does not change the non-frozen path for the same three shapes" do
    code, out, err = frozen_lock_run("check-frozen-missing-locked-spec", ["install"], frozen: false)
    code.should eq(0), "stdout=#{out}\nstderr=#{err}"
    err.should eq("")

    code, out, err = frozen_lock_run("check-frozen-locked-version-mismatch", ["install"], frozen: false)
    code.should eq(0), "stdout=#{out}\nstderr=#{err}"
    err.should eq("")
    out.should contain("Bundle complete!")

    ["check-frozen-missing-locked-spec", "check-frozen-extra-locked-spec",
     "check-frozen-locked-version-mismatch"].each do |name|
      code, out, err = frozen_lock_run(name, ["check"], frozen: false)
      code.should_not eq(16), "#{name}: stdout=#{out}\nstderr=#{err}"
      err.should_not contain("because frozen mode is set"), name
    end

    code, _, err = frozen_lock_run("check-frozen-extra-locked-spec", ["check"], frozen: false)
    code.should eq(1), "stderr=#{err}"
    err.should eq(B_MISSING_THREE_LINES)
  end
end
