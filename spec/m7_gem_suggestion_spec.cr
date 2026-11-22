require "./spec_helper"

# `lock --update NAME` (`cli/lock.rb:36`), `update NAME` (`cli/update.rb:47`) and
# `pristine NAME` (`cli/pristine.rb:10`) all run
# `CLI::Common.ensure_all_gems_in_lockfile!` (`cli/common.rb:125-132`), which
# raises `gem_not_found_message(name, locked_names)` for a name the lockfile
# does not carry (`cli/common.rb:113-123`): the plain `Could not find gem
# 'NAME'.` line, plus a `Did you mean ...?` line when the lowercased name is
# itself locked or when `Suggestions` finds a near miss. celerite wires
# `lock --update` (`src/celerite/cli/commands.cr:2993`), `update`
# (`src/celerite/cli/commands_surface.cr:126`) and `pristine`
# (`src/celerite/cli/commands_surface.cr:3004`) to that helper; these examples
# pin the helper's three text shapes and both newly wired commands.
private def gem_suggestion_index_url : String
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  "file:///#{index.sub(%r{^/}, "")}"
end

private def gem_suggestion_gemfile : String
  %(source "#{gem_suggestion_index_url}"\n\ngem "json_pure", "2.6.0"\n)
end

private def gem_suggestion_lock(specs : Array(String)) : String
  body = specs.map { |spec| "    #{spec}" }.join('\n')
  String.build do |io|
    io << "GEM\n"
    io << "  remote: " << gem_suggestion_index_url << "/\n"
    io << "  specs:\n"
    io << body << '\n'
    io << '\n'
    io << "PLATFORMS\n"
    io << "  ruby\n"
    io << '\n'
    io << "DEPENDENCIES\n"
    specs.each { |spec| io << "  " << spec << '\n' }
    io << '\n'
    io << "BUNDLED WITH\n"
    io << "    4.0.24\n"
  end
end

private def gem_suggestion_restore(name : String, value : String?) : Nil
  value.nil? ? ENV.delete(name) : (ENV[name] = value)
end

private def with_gem_suggestion_project(specs : Array(String) = ["json_pure (2.6.0)"], & : String ->) : Nil
  saved_home = ENV["HOME"]?
  saved_profile = ENV["USERPROFILE"]?
  saved_path = ENV["BUNDLE_PATH"]?
  saved_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  files = {
    "Gemfile"      => gem_suggestion_gemfile,
    "Gemfile.lock" => gem_suggestion_lock(specs),
  }
  with_project(files) do |dir|
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    begin
      yield dir
    ensure
      gem_suggestion_restore("HOME", saved_home)
      gem_suggestion_restore("USERPROFILE", saved_profile)
      gem_suggestion_restore("BUNDLE_PATH", saved_path)
      gem_suggestion_restore("CELERITE_BRIDGE_SERVER", saved_bridge)
    end
  end
end

describe "gem name suggestions" do
  # `cli/common.rb:120-121`: `DidYouMean::SpellChecker#correct` returns the one
  # near miss and `word_list` renders it as a single quoted name. Verified
  # verbatim against bundler 4.0.24 (`Did you mean 'json_pure'?`).
  it "suggests the near miss for a misspelled locked name" do
    with_gem_suggestion_project do
      code, out, err = run_cli(["lock", "--update", "json_pur"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'json_pur'.\nDid you mean 'json_pure'?\n")
    end
  end

  # `cli/common.rb:115-117`: when the *lowercased* request is itself a locked
  # name, the reference short-circuits before the spell checker and echoes the
  # lowercased form, so a case-only mismatch reports the lockfile spelling.
  it "reports the lowercased locked name for a case-only mismatch" do
    with_gem_suggestion_project do
      code, out, err = run_cli(["lock", "--update", "JSON_PURE"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'JSON_PURE'.\nDid you mean 'json_pure'?\n")
    end
  end

  # `cli/common.rb:122`: `unless suggestions.empty?` -- no near miss means the
  # message keeps the single line and no `Did you mean` is emitted.
  it "keeps the plain message when no suggestion exists" do
    with_gem_suggestion_project do
      code, out, err = run_cli(["lock", "--update", "zzzz"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'zzzz'.\n")
      err.should_not contain("Did you mean")
    end
  end

  # `cli/common.rb:158-170` `word_list` joins several suggestions as
  # `quote(a), quote(b) ... or quote(last)`; measured against bundler 4.0.24,
  # which prints `Did you mean 'aac' or 'aab'?` for `aad` with `aab`/`aac`
  # locked.
  it "joins several suggestions with `or`" do
    with_gem_suggestion_project(["aab (1.0.0)", "aac (1.0.0)"]) do
      code, out, err = run_cli(["lock", "--update", "aad"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'aad'.\nDid you mean 'aac' or 'aab'?\n")
    end
  end

  # `cli/update.rb:47` runs `ensure_all_gems_in_lockfile!` for a scoped update,
  # so the misspelled name carries the same suggestion line. Measured against
  # bundler 4.0.24: exit 7, empty stdout, the two lines below verbatim.
  it "suggests the near miss for `update NAME`" do
    with_gem_suggestion_project do
      code, out, err = run_cli(["update", "json_pur"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'json_pur'.\nDid you mean 'json_pure'?\n")
      err.lines.size.should eq(2)
    end
  end

  # Case-only mismatch through the `update` wiring: the lowercased locked name
  # is echoed (same short-circuit as `lock --update`).
  it "reports the lowercased locked name for `update NAME`" do
    with_gem_suggestion_project do
      code, out, err = run_cli(["update", "JSON_PURE"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'JSON_PURE'.\nDid you mean 'json_pure'?\n")
      err.lines.size.should eq(2)
    end
  end

  # `cli/pristine.rb:10` shares the guard; the reference prints the identical
  # pair and exits 7.
  it "suggests the near miss for `pristine NAME`" do
    with_gem_suggestion_project do
      code, out, err = run_cli(["pristine", "json_pur"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'json_pur'.\nDid you mean 'json_pure'?\n")
      err.lines.size.should eq(2)
    end
  end

  # And the case-only branch through `pristine`.
  it "reports the lowercased locked name for `pristine NAME`" do
    with_gem_suggestion_project do
      code, out, err = run_cli(["pristine", "JSON_PURE"])
      code.should eq(7)
      out.should be_empty
      err.should eq("Could not find gem 'JSON_PURE'.\nDid you mean 'json_pure'?\n")
      err.lines.size.should eq(2)
    end
  end
end
