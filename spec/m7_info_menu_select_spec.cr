require "./spec_helper"

# `bundle info`/`show` ask the user to pick a spec when the name matches more
# than one installed spec (`cli/common.rb:98-111`, `ask_for_spec_from`). The
# in-process `run_cli` helper in `spec_helper.cr` cannot supply stdin, so these
# examples run the built binary and feed the answer through a pipe, exactly as
# a terminal user would.
private def info_menu_bin : String
  path = File.expand_path("../bin/celerite.exe", __DIR__)
  pending!("bin/celerite.exe is not built") unless File.exists?(path)
  path
end

private def info_menu_index_url : String
  index = File.expand_path("../fixtures/gem-index", __DIR__).gsub('\\', "/")
  "file:///#{index.sub(%r{^/}, "")}"
end

private def info_menu_gemfile : String
  %(source "#{info_menu_index_url}"\n\ngem "json_pure", "2.6.0"\n)
end

private def info_menu_lock : String
  <<-LOCK
    GEM
      remote: #{info_menu_index_url}/
      specs:
        json_pure (2.6.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      json_pure (= 2.6.0)

    BUNDLED WITH
        4.0.24
    LOCK
end

private def info_menu_restore(name : String, value : String?) : Nil
  value.nil? ? ENV.delete(name) : (ENV[name] = value)
end

private def with_info_menu_project(& : String ->) : Nil
  saved_home = ENV["HOME"]?
  saved_profile = ENV["USERPROFILE"]?
  saved_path = ENV["BUNDLE_PATH"]?
  saved_bridge = ENV["CELERITE_BRIDGE_SERVER"]?
  with_project({"Gemfile" => info_menu_gemfile, "Gemfile.lock" => info_menu_lock}) do |dir|
    ENV["HOME"] = dir
    ENV["USERPROFILE"] = dir
    ENV["BUNDLE_PATH"] = File.join(dir, "bundle")
    ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
    begin
      run_cli(["install", "--quiet"]).first.should eq(0)
      yield dir
    ensure
      info_menu_restore("HOME", saved_home)
      info_menu_restore("USERPROFILE", saved_profile)
      info_menu_restore("BUNDLE_PATH", saved_path)
      info_menu_restore("CELERITE_BRIDGE_SERVER", saved_bridge)
    end
  end
end

private def run_info_menu(project : String, stdin : String) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  env = {
    "HOME"                   => project,
    "USERPROFILE"            => project,
    "BUNDLE_PATH"            => File.join(project, "bundle"),
    "CELERITE_BRIDGE_SERVER" => File.expand_path("../assets/bridge/server.rb", __DIR__),
  }
  status = Process.run(info_menu_bin, ["info", "json"], chdir: project, env: env,
    input: IO::Memory.new(stdin), output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

# `json_pure` is the locked and installed spec; the running Ruby also ships
# `json` as a default gem, so `info json` matches both and prints the menu
# before asking. The oracle (reference 4.0.24, same project) is:
#   1 : json_pure
#   2 : json
#   0 : - exit -
#   >    * <selected> ...
private def info_menu_expected_menu : String
  "1 : json_pure\n2 : json\n0 : - exit -\n"
end

describe "info/show numbered menu selection" do
  # `cli/info.rb:11-24` silences the runtime load, so the prompt is the only
  # output before `print_gem_info`: answer 1 selects the locked spec.
  it "selects the locked spec by number" do
    with_info_menu_project do |dir|
      code, out, err = run_info_menu(dir, "1\n")
      code.should eq(0)
      err.should be_empty
      out.should start_with(info_menu_expected_menu)
      out.should contain(">    * json_pure (2.6.0)")
      out.should contain("Summary: JSON Implementation for Ruby")
      out.should contain("Path: #{File.join(dir, "bundle").gsub('\\', "/")}/ruby/4.0.0/gems/json_pure-2.6.0")
      out.should_not contain("Default Gem: yes")
    end
  end

  # `cli/common.rb:98-101`: `Gem::Specification.find_all_by_name` appends the
  # default gem, and `cli/info.rb:59-65` adds the `Default Gem: yes` marker.
  it "selects the default gem by number" do
    with_info_menu_project do |dir|
      code, out, err = run_info_menu(dir, "2\n")
      code.should eq(0)
      err.should be_empty
      out.should start_with(info_menu_expected_menu)
      out.should contain(">    * json (")
      out.should contain("Documentation: https://docs.ruby-lang.org/en/master/JSON.html")
      out.should contain("Default Gem: yes")
    end
  end

  # `0` exits the menu without a selection (`cli/common.rb:104-111`): the menu
  # and the prompt remain, no gem block follows, and the exit status is 0.
  it "exits the menu on 0" do
    with_info_menu_project do |dir|
      code, out, err = run_info_menu(dir, "0\n")
      code.should eq(0)
      err.should be_empty
      out.should eq("#{info_menu_expected_menu}>  ")
    end
  end

  # An answer outside the candidate range selects nothing, same as 0.
  it "exits the menu on an out-of-range answer" do
    with_info_menu_project do |dir|
      code, out, err = run_info_menu(dir, "99\n")
      code.should eq(0)
      err.should be_empty
      out.should eq("#{info_menu_expected_menu}>  ")
    end
  end

  # EOF is the same silent exit; `cli/common.rb:107-109` answers nil and the
  # prompt is still printed with its two trailing spaces.
  it "exits the menu on EOF" do
    with_info_menu_project do |dir|
      code, out, err = run_info_menu(dir, "")
      code.should eq(0)
      err.should be_empty
      out.should eq("#{info_menu_expected_menu}>  ")
    end
  end
end
