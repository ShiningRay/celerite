require "./spec_helper"

# Port of `Bundler::Definition#validate_platforms!` (definition.rb:524-530),
# which is half of `validate_runtime!` (definition.rb:494-497). A lockfile that
# does not list the local platform (and has no `ruby` platform) refuses to run
# instead of quietly resolving: that is what a frozen install reports before
# the lockfile-changes summary.
private def platform_validation_lockfile(platforms : Array(String), ruby_section : String = "") : String
  String.build do |io|
    io << "GEM\n"
    io << "  remote: https://rubygems.org/\n"
    io << "  specs:\n"
    io << "    json_pure (2.8.1)\n"
    io << "\nPLATFORMS\n"
    platforms.each { |platform| io << "  " << platform << "\n" }
    io << "\nDEPENDENCIES\n"
    io << "  json_pure (= 2.8.1)\n"
    io << ruby_section
    io << "\nBUNDLED WITH\n"
    io << "  4.0.24\n"
  end
end

private def platform_validation_gemfile : String
  "source \"https://rubygems.org/\"\n\ngem \"json_pure\", \"2.8.1\"\n"
end

private def local_platform : String
  Celerite::Gem::Platform.local.to_s
end

private def with_frozen_env(value : String?, &) : Nil
  original = ENV["BUNDLE_FROZEN"]?
  if value
    ENV["BUNDLE_FROZEN"] = value
  else
    ENV.delete("BUNDLE_FROZEN")
  end
  begin
    yield
  ensure
    if original
      ENV["BUNDLE_FROZEN"] = original
    else
      ENV.delete("BUNDLE_FROZEN")
    end
  end
end

describe "platform validation" do
  it "raises ProductionError when the lockfile omits the local platform" do
    local = local_platform
    other = local == "x86_64-linux" ? "x64-mingw-ucrt" : "x86_64-linux"
    with_project({
      "Gemfile"      => platform_validation_gemfile,
      "Gemfile.lock" => platform_validation_lockfile([other]),
    }) do |_dir|
      error = expect_raises(Celerite::ProductionError) do
        Celerite::Definition.build.validate_platforms!(local)
      end
      error.status_code.should eq(16)
      message = error.message || ""
      message.should contain("Your bundle only supports platforms [\"#{other}\"] but your local platform is #{local}")
      message.should contain("`bundle lock --add-platform #{local}` and try again.")
    end
  end

  it "accepts a lockfile that lists the local platform" do
    local = local_platform
    with_project({
      "Gemfile"      => platform_validation_gemfile,
      "Gemfile.lock" => platform_validation_lockfile([local]),
    }) do |_dir|
      Celerite::Definition.build.validate_platforms!(local)
    end
  end

  it "accepts a lockfile that only lists the ruby platform" do
    local = local_platform
    with_project({
      "Gemfile"      => platform_validation_gemfile,
      "Gemfile.lock" => platform_validation_lockfile(["ruby"]),
    }) do |_dir|
      Celerite::Definition.build.validate_platforms!(local)
    end
  end

  it "does nothing without a lockfile" do
    with_project({"Gemfile" => platform_validation_gemfile}) do |_dir|
      Celerite::Definition.build.validate_platforms!(local_platform)
    end
  end

  # `bundler/cli/platform.rb` prints `Bundler.definition.platforms`, and
  # `add_current_platform` only appends the local platform when the bundle is
  # not frozen (definition.rb:150).
  it "omits the local platform from `bundle platform` in frozen mode" do
    local = local_platform
    other = local == "x86_64-linux" ? "x64-mingw-ucrt" : "x86_64-linux"
    with_project({
      "Gemfile"      => platform_validation_gemfile,
      "Gemfile.lock" => platform_validation_lockfile([other]),
    }) do |_dir|
      with_frozen_env("true") do
        code, output, _error = run_cli(["platform"])
        code.should eq(0)
        output.should contain("* #{other}")
        output.should_not contain("* #{local}")
      end
      code, output, _error = run_cli(["platform"])
      code.should eq(0)
      output.should contain("* #{local}")
    end
  end
end
