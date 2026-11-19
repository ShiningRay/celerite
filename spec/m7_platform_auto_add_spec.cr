require "./spec_helper"

# M7(6) task-33: `Bundler::Definition#initialize` adds the current platform
# unless frozen (definition.rb:150), so `validate_platforms!`
# (definition.rb:524-530) never rejects a non-frozen lock that only lists
# another platform. Frozen mode keeps the reference rejection verbatim.
private def platform_auto_add_project
  {
    "Gemfile"      => "source \"https://rubygems.org\"\n\ngem \"json_pure\"\n",
    "Gemfile.lock" => "GEM\n  remote: https://rubygems.org/\n  specs:\n    json_pure (2.8.1)\n\nPLATFORMS\n  java\n\nDEPENDENCIES\n  json_pure\n\nBUNDLED WITH\n   4.0.24\n",
  }
end

private def with_frozen_env(& : ->)
  previous = ENV["BUNDLE_FROZEN"]?
  ENV["BUNDLE_FROZEN"] = "true"
  begin
    yield
  ensure
    if previous
      ENV["BUNDLE_FROZEN"] = previous
    else
      ENV.delete("BUNDLE_FROZEN")
    end
  end
end

describe "M7 platform auto-add" do
  it "accepts a non-frozen lock that lists only another platform" do
    with_project(platform_auto_add_project) do
      definition = Celerite::Definition.build
      definition.validate_platforms!(Celerite::Gem::Platform.local.to_s)
    end
  end

  it "keeps the reference rejection in frozen mode" do
    with_frozen_env do
      with_project(platform_auto_add_project) do
        definition = Celerite::Definition.build
        local = Celerite::Gem::Platform.local.to_s
        error = expect_raises(Celerite::ProductionError) do
          definition.validate_platforms!(local)
        end
        error.message.should eq(
          "Your bundle only supports platforms [\"java\"] but your local platform is " \
          "#{local}. Add the current platform to the lockfile with\n" \
          "`bundle lock --add-platform #{local}` and try again."
        )
      end
    end
  end
end
