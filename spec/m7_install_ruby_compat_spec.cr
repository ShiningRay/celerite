require "./spec_helper"
require "../src/celerite"

# M7(3) task-21: install-time `required_ruby_version` / `required_rubygems_version`
# recheck. Reference `Bundler::Installer#ensure_specs_are_compatible!`
# (4.0.24 `bundler/installer.rb:234-245`, 2.7.2 `:227-238`) is only reached when
# `setup_domain!` re-resolved, so the user-visible behavior for a locked
# incompatible gem is the solver's exit 6 (the reference never materializes the
# pinned spec). The helper below mirrors the reference messages as a defense for
# specs that still reach install with requirement metadata.
private def with_bridge_script(& : ->) : Nil
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
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

private def locked_index_url : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index-locked-ruby")))
end

private def incompatible_lock(url : String) : String
  <<-LOCK
  GEM
    remote: #{url}/
    specs:
      incompat_ruby (1.0.0)

  PLATFORMS
    x64-mingw-ucrt

  DEPENDENCIES
    incompat_ruby
  LOCK
end

describe "M7 install-time Ruby/RubyGems compatibility" do
  it "re-resolves a locked Ruby-incompatible gem and fails like the reference" do
    pending! "ruby not available" unless ruby_available?
    url = locked_index_url
    ruby_version = ""
    with_client { |client| ruby_version = client.ruby_environment.ruby_version }
    with_bridge_script do
      with_project({
        "Gemfile"      => %(source "#{url}"\n\ngem "incompat_ruby"\n),
        "Gemfile.lock" => incompatible_lock(url),
      }) do
        previous_path = ENV["BUNDLE_PATH"]?
        ENV["BUNDLE_PATH"] = File.join(Dir.current, "bundle")
        begin
          code, stdout, stderr = run_cli(["install"])
          code.should eq(6)
          stdout.should contain("Fetching source index from #{url}/")
          stdout.should contain("Resolving dependencies...")
          stderr.chomp.should eq(<<-ERR)
          Could not find compatible versions

          Because every version of incompat_ruby depends on Ruby >= 99
            and Gemfile depends on incompat_ruby >= 0,
            Ruby >= 99 is required.
          So, because current Ruby version is = #{ruby_version},
            version solving has failed.
          ERR
        ensure
          if previous_path
            ENV["BUNDLE_PATH"] = previous_path
          else
            ENV.delete("BUNDLE_PATH")
          end
        end
      end
    end
  end

  it "leaves a compatible locked resolution untouched (no Resolving line)" do
    pending! "ruby not available" unless ruby_available?
    url = file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
    lock = <<-LOCK
    GEM
      remote: #{url}/
      specs:
        json_pure (2.8.1)

    PLATFORMS
      x64-mingw-ucrt

    DEPENDENCIES
      json_pure (= 2.8.1)
    LOCK
    with_project({
      "Gemfile"      => %(source "#{url}"\n\ngem "json_pure", "2.8.1"\n),
      "Gemfile.lock" => lock,
    }) do
      with_client do |client|
        resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
        progress = IO::Memory.new
        resolution.progress = progress
        specs = resolution.resolve!(true, verify_locked_compat: true)
        specs.map(&.name).should eq(["json_pure"])
        progress.to_s.should eq("Fetching source index from #{url}/\n")
      end
    end
  end

  it "raises the reference InstallError messages for requirement metadata" do
    ruby_spec = Celerite::Resolution::ResolvedSpec.new(
      "incompat_ruby", Celerite::Gem::Version.new("1.0.0"), nil,
      [] of Celerite::Lockfile::SpecDependency, nil, 0,
      required_ruby_version: Celerite::Gem::Requirement.new([">= 99"]))
    ex = expect_raises(Celerite::InstallError) do
      Celerite::Installer.ensure_specs_are_compatible!([ruby_spec], "4.0.6", "4.0.6")
    end
    ex.message.should eq("incompat_ruby-1.0.0 requires ruby version >= 99, which is incompatible with the current version, 4.0.6")

    rubygems_spec = Celerite::Resolution::ResolvedSpec.new(
      "incompat_rg", Celerite::Gem::Version.new("1.0.0"), nil,
      [] of Celerite::Lockfile::SpecDependency, nil, 0,
      required_rubygems_version: Celerite::Gem::Requirement.new([">= 99"]))
    ex = expect_raises(Celerite::InstallError) do
      Celerite::Installer.ensure_specs_are_compatible!([rubygems_spec], "4.0.6", "4.0.6")
    end
    ex.message.should eq("incompat_rg-1.0.0 requires rubygems version >= 99, which is incompatible with the current version, 4.0.6")
  end
end
