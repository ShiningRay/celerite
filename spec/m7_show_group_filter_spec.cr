require "./spec_helper"

# Reference `bundler/cli/common.rb:68-96` (`select_spec`): when the gem is a
# dependency whose every group is filtered out by the `without` setting, the
# reference raises `GemNotFound` (exit 7) with
# `Could not find gem '<name>', because it's in the group '<g>', configured to
# be ignored.` (wrapped at the terminal width) instead of the generic
# missing-gem message. `bundler/cli/common.rb:60-66` verbalizes several groups
# as `groups 'a' and 'b'`.
private SHOW_GROUP_INDEX = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private def show_group_bridge(& : ->) : Nil
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

private def show_group_gemfile(group_line : String) : String
  <<-GEMFILE
  source "#{SHOW_GROUP_INDEX}"

  gem "json_pure"

  #{group_line} do
    gem "thor"
  end
  GEMFILE
end

private def with_without_groups(value : String, & : ->)
  previous = ENV["BUNDLE_WITHOUT"]?
  ENV["BUNDLE_WITHOUT"] = value
  begin
    yield
  ensure
    if previous
      ENV["BUNDLE_WITHOUT"] = previous
    else
      ENV.delete("BUNDLE_WITHOUT")
    end
  end
end

private def show_group_message(name : String, groups : String) : String
  Celerite::Commands.word_wrap(
    "Could not find gem '#{name}', because it's in the #{groups}, configured to be ignored.",
    Celerite::CLI.terminal_width
  ) + "\n"
end

describe "show/info when the gem's groups are filtered out" do
  it "raises the reference group message for show" do
    show_group_bridge do
      with_project({"Gemfile" => show_group_gemfile("group :development")}) do |project|
        run_cli(["install"]).first.should eq(0)

        with_without_groups("development") do
          code, out, err = run_cli(["show", "thor"])
          code.should eq(7)
          out.should eq("")
          err.should eq(show_group_message("thor", "group 'development'"))
        end
      end
    end
  end

  it "raises the reference group message for info" do
    show_group_bridge do
      with_project({"Gemfile" => show_group_gemfile("group :development")}) do |project|
        run_cli(["install"]).first.should eq(0)

        with_without_groups("development") do
          code, out, err = run_cli(["info", "thor"])
          code.should eq(7)
          out.should eq("")
          err.should eq(show_group_message("thor", "group 'development'"))
        end
      end
    end
  end

  it "verbalizes several filtered groups like the reference" do
    show_group_bridge do
      with_project({"Gemfile" => show_group_gemfile("group :development, :test")}) do |project|
        run_cli(["install"]).first.should eq(0)

        with_without_groups("development:test") do
          code, out, err = run_cli(["show", "thor"])
          code.should eq(7)
          out.should eq("")
          err.should eq(show_group_message("thor", "groups 'development' and 'test'"))
        end
      end
    end
  end

  it "still reports gems from the requested groups" do
    show_group_bridge do
      with_project({"Gemfile" => show_group_gemfile("group :development")}) do |project|
        run_cli(["install"]).first.should eq(0)

        with_without_groups("development") do
          code, out, err = run_cli(["show", "json_pure"])
          code.should eq(0)
          err.should eq("")
          out.strip.should contain("json_pure-2.8.1")
        end
      end
    end
  end
end
