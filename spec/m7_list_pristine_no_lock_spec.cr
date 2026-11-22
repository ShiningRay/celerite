require "./spec_helper"

# `bundle list` / `bundle pristine` without a lockfile (task-125).
#
# Reference anchors (bundler-4.0.24):
#   cli/list.rb:19-29     `Bundler.load.specs` (materializes + resolves on
#                         demand), rescuing GemNotFound -> ui.error e.message +
#                         ui.warn "Install missing gems with `bundle install`."
#                         + exit 1.
#   cli/pristine.rb:10    `ensure_all_gems_in_lockfile!` is a no-op without a
#                         lockfile (common.rb:125-132 `return unless locked_gems`).
#   cli/pristine.rb:17    `definition.specs` materializes + resolves on demand.
#   definition.rb:249-251 `specs` -> `materialize` -> `resolve`.
#   definition.rb:401-405 `write_lock` returns unless `definition.lock` ran, and
#                         neither command calls it: the lockfile stays absent.
#   resolver.rb:34        the only printer of "Resolving dependencies...".
#   source/rubygems.rb:122-141  local-only sources describe themselves as
#                         "locally installed gems".
# Measured oracle (BUNDLER_REF_VERSION 4.0.24 and 2.7.2, identical):
#   empty Gemfile  list     -> exit 0, "Resolving dependencies...\nNo gems in the Gemfile"
#                  pristine -> exit 0, "Resolving dependencies..."
#   resolvable gem list     -> exit 0, "Resolving dependencies...\nGems included by the bundle:\n  * json_pure (2.6.0)\nUse `bundle info` to print more detailed information about a gem"
#                  pristine -> exit 0, "Resolving dependencies...\nInstalling json_pure 2.6.0"
#   missing gem    list     -> exit 1, stderr "Could not find gem 'myrack (= 1.0.0)' in locally installed gems.\nInstall missing gems with `bundle install`.\n"
#                  pristine -> exit 7, stderr "Could not find gem 'myrack (= 1.0.0)' in locally installed gems.\n"
# No combination writes Gemfile.lock.
private GEM_INDEX_URL_NO_LOCK = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def no_lock_gemfile(body : String) : String
  "source \"#{GEM_INDEX_URL_NO_LOCK}\"\n\n#{body}"
end

private def with_no_lock_env(project : String, &)
  previous = {
    "HOME"                   => ENV["HOME"]?,
    "USERPROFILE"            => ENV["USERPROFILE"]?,
    "BUNDLE_PATH"            => ENV["BUNDLE_PATH"]?,
    "CELERITE_BRIDGE_SERVER" => ENV["CELERITE_BRIDGE_SERVER"]?,
  }
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, ".bundle-test")
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
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

private def run_no_lock(project : String, args : Array(String)) : {Int32, String, String}
  with_no_lock_env(project) do
    run_cli(args)
  end
end

describe "bundle list / bundle pristine without a lockfile" do
  it "list resolves an empty Gemfile instead of demanding a lockfile" do
    with_project({"Gemfile" => no_lock_gemfile("")}) do |project|
      lock = File.join(project, "Gemfile.lock")
      File.exists?(lock).should be_false
      status, output, errors = run_no_lock(project, ["list"])
      status.should eq(0)
      output.should eq("Resolving dependencies...\nNo gems in the Gemfile\n")
      errors.should eq("")
      File.exists?(lock).should be_false
    end
  end

  it "pristine resolves an empty Gemfile instead of demanding a lockfile" do
    with_project({"Gemfile" => no_lock_gemfile("")}) do |project|
      lock = File.join(project, "Gemfile.lock")
      status, output, errors = run_no_lock(project, ["pristine"])
      status.should eq(0)
      output.should eq("Resolving dependencies...\n")
      errors.should eq("")
      File.exists?(lock).should be_false
    end
  end

  it "list resolves and prints an installed gem while leaving the lockfile absent" do
    with_project({"Gemfile" => no_lock_gemfile("gem \"json_pure\", \"2.6.0\"\n")}) do |project|
      install_status, _, _ = run_no_lock(project, ["install"])
      install_status.should eq(0)
      lock = File.join(project, "Gemfile.lock")
      File.exists?(lock).should be_true
      # The scenario under test is "gems installed, no lockfile".
      File.delete(lock)

      status, output, errors = run_no_lock(project, ["list"])
      status.should eq(0)
      output.should eq("Resolving dependencies...\n" \
                       "Gems included by the bundle:\n" \
                       "  * json_pure (2.6.0)\n" \
                       "Use `bundle info` to print more detailed information about a gem\n")
      errors.should eq("")
      File.exists?(lock).should be_false
    end
  end

  it "pristine resolves and reinstalls from the cache while leaving the lockfile absent" do
    with_project({"Gemfile" => no_lock_gemfile("gem \"json_pure\", \"2.6.0\"\n")}) do |project|
      install_status, _, _ = run_no_lock(project, ["install"])
      install_status.should eq(0)
      lock = File.join(project, "Gemfile.lock")
      File.delete(lock)

      status, output, errors = run_no_lock(project, ["pristine"])
      status.should eq(0)
      output.should eq("Resolving dependencies...\nInstalling json_pure 2.6.0\n")
      errors.should eq("")
      File.exists?(lock).should be_false
    end
  end

  it "list reports a gem that is not installed as a local-only GemNotFound, exit 1" do
    with_project({"Gemfile" => no_lock_gemfile("gem \"myrack\", \"1.0.0\"\n")}) do |project|
      lock = File.join(project, "Gemfile.lock")
      status, output, errors = run_no_lock(project, ["list"])
      status.should eq(1)
      output.should eq("")
      errors.should eq("Could not find gem 'myrack (= 1.0.0)' in locally installed gems.\n" \
                       "Install missing gems with `bundle install`.\n")
      File.exists?(lock).should be_false
    end
  end

  it "pristine reports a gem that is not installed as a local-only GemNotFound, exit 7" do
    with_project({"Gemfile" => no_lock_gemfile("gem \"myrack\", \"1.0.0\"\n")}) do |project|
      lock = File.join(project, "Gemfile.lock")
      status, output, errors = run_no_lock(project, ["pristine"])
      status.should eq(7)
      output.should eq("")
      errors.should eq("Could not find gem 'myrack (= 1.0.0)' in locally installed gems.\n")
      File.exists?(lock).should be_false
    end
  end
end
