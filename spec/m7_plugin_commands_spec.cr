require "./spec_helper"

# Plugin command registration (M7(6)): `Bundler::Plugin::API.command` entries
# must be recorded in the project plugin index, listed, dispatched before the
# `bundler-<name>` PATH fallback, and rejected on conflicts (exit 29).
private def with_plugin_commands_bridge(&)
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

private def plugin_command_project_files : Hash(String, String)
  {"Gemfile" => "source \"file:///#{File.expand_path("../fixtures/gem-index", __DIR__).gsub(/\\/, "/")}\"\n"}
end

# Creates a plugin source directory shaped like the reference fixtures:
#   <dir>/<name>.gemspec, <dir>/plugins.rb, <dir>/lib/<name>.rb
private def write_plugin_source(dir : String, name : String, commands : Hash(String, String))
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "#{name}.gemspec"), <<-GEMSPEC)
    Gem::Specification.new do |s|
      s.name = "#{name}"
      s.version = "0.1.0"
      s.summary = "#{name}"
      s.authors = ["Fixture"]
      s.files = ["plugins.rb", "lib/#{name}.rb"]
      s.require_paths = ["lib"]
    end
    GEMSPEC
  File.write(File.join(dir, "lib", "#{name}.rb"), "module #{name.split('-').map(&.capitalize).join};\nend\n")

  body = String.build do |io|
    io.puts %(require "bundler")
    io.puts %(require "bundler/plugin")
    commands.each do |command, class_name|
      io.puts <<-RUBY
        class #{class_name}
          def exec(command, args)
            if marker = ENV["CELERITE_CMD_MARKER"]
              File.write(marker, "\#{command}:\#{args.join(",")}")
            end
            0
          end
        end
        Bundler::Plugin::API.command "#{command}", #{class_name}
        RUBY
    end
  end
  File.write(File.join(dir, "plugins.rb"), body)
end

private def plugin_index_path(dir : String) : String
  File.join(dir, ".bundle", "plugin", "index")
end

describe "M7(6) plugin commands" do
  it "records declared commands in the plugin index" do
    with_plugin_commands_bridge do
      with_project(plugin_command_project_files) do |dir|
        source = File.join(dir, "mah-plug")
        write_plugin_source(source, "mah-plug", {"mahcommand" => "MahCommand"})
        code, out, err = run_cli(["plugin", "install", "mah-plug", "--path", source])
        code.should eq(0)
        err.should be_empty
        out.should contain("Installed plugin mah-plug")
        index = File.read(plugin_index_path(dir))
        index.should contain("commands:")
        index.should contain(%(  mahcommand: "mah-plug"))
        index.scan(/^  mah-plug: "/m).size.should eq(1)
      end
    end
  end

  it "lists installed plugins in index order with their commands" do
    with_plugin_commands_bridge do
      with_project(plugin_command_project_files) do |dir|
        first = File.join(dir, "mah-plug")
        second = File.join(dir, "raiser")
        write_plugin_source(first, "mah-plug", {"mahcommand" => "MahCommand"})
        write_plugin_source(second, "raiser", {"boomer" => "BoomCommand"})
        run_cli(["plugin", "install", "mah-plug", "--path", first])[0].should eq(0)
        run_cli(["plugin", "install", "raiser", "--path", second])[0].should eq(0)
        code, out, err = run_cli(["plugin", "list"])
        code.should eq(0)
        err.should be_empty
        out.should eq("mah-plug\n-----\n  mahcommand\n\nraiser\n-----\n  boomer\n\n")
      end
    end
  end

  it "dispatches a plugin command with its arguments" do
    with_plugin_commands_bridge do
      with_project(plugin_command_project_files) do |dir|
        source = File.join(dir, "mah-plug")
        write_plugin_source(source, "mah-plug", {"mahcommand" => "MahCommand"})
        run_cli(["plugin", "install", "mah-plug", "--path", source])[0].should eq(0)
        marker = File.join(dir, "cmd-marker.txt")
        previous = ENV["CELERITE_CMD_MARKER"]?
        ENV["CELERITE_CMD_MARKER"] = marker
        begin
          code, _out, err = run_cli(["mahcommand", "a", "b"])
          code.should eq(0)
          err.should be_empty
          File.read(marker).should eq("mahcommand:a,b")
        ensure
          if previous
            ENV["CELERITE_CMD_MARKER"] = previous
          else
            ENV.delete("CELERITE_CMD_MARKER")
          end
        end
      end
    end
  end

  it "runs `help <plugin-command>` with --help" do
    with_plugin_commands_bridge do
      with_project(plugin_command_project_files) do |dir|
        source = File.join(dir, "mah-plug")
        write_plugin_source(source, "mah-plug", {"mahcommand" => "MahCommand"})
        run_cli(["plugin", "install", "mah-plug", "--path", source])[0].should eq(0)
        marker = File.join(dir, "help-marker.txt")
        previous = ENV["CELERITE_CMD_MARKER"]?
        ENV["CELERITE_CMD_MARKER"] = marker
        begin
          code, _out, err = run_cli(["help", "mahcommand"])
          code.should eq(0)
          err.should be_empty
          File.read(marker).should eq("mahcommand:--help")
        ensure
          if previous
            ENV["CELERITE_CMD_MARKER"] = previous
          else
            ENV.delete("CELERITE_CMD_MARKER")
          end
        end
      end
    end
  end

  it "keeps plugin commands disabled with BUNDLE_PLUGINS=false" do
    with_plugin_commands_bridge do
      with_project(plugin_command_project_files) do |dir|
        source = File.join(dir, "mah-plug")
        write_plugin_source(source, "mah-plug", {"mahcommand" => "MahCommand"})
        run_cli(["plugin", "install", "mah-plug", "--path", source])[0].should eq(0)
        previous = ENV["BUNDLE_PLUGINS"]?
        ENV["BUNDLE_PLUGINS"] = "false"
        begin
          code, _out, err = run_cli(["mahcommand"])
          code.should eq(15)
          err.should eq(%(Could not find command "mahcommand".\n))
        ensure
          if previous
            ENV["BUNDLE_PLUGINS"] = previous
          else
            ENV.delete("BUNDLE_PLUGINS")
          end
        end
      end
    end
  end

  it "rejects a conflicting command declaration with exit 29 and leaves the index untouched" do
    with_plugin_commands_bridge do
      with_project(plugin_command_project_files) do |dir|
        first = File.join(dir, "mah-plug")
        second = File.join(dir, "conflicter")
        write_plugin_source(first, "mah-plug", {"mahcommand" => "MahCommand"})
        write_plugin_source(second, "conflicter", {"mahcommand" => "ClashCommand"})
        run_cli(["plugin", "install", "mah-plug", "--path", first])[0].should eq(0)
        before = File.read(plugin_index_path(dir))
        code, out, err = run_cli(["plugin", "install", "conflicter", "--path", second])
        code.should eq(29)
        out.should eq("Resolving dependencies...\n")
        # The reference wraps this error at the terminal width; compare on the
        # whitespace-normalized text so the 80-column fold does not matter.
        normalized = err.gsub(/\s+/, " ")
        normalized.should contain("Failed to install plugin `conflicter`, due to Bundler::Plugin::Index::CommandConflict")
        normalized.should contain("(Command(s) `mahcommand` declared by conflicter are already registered.)")
        File.read(plugin_index_path(dir)).should eq(before)
      end
    end
  end

  it "keeps earlier plugins' commands when installing another plugin" do
    with_plugin_commands_bridge do
      with_project(plugin_command_project_files) do |dir|
        first = File.join(dir, "mah-plug")
        second = File.join(dir, "raiser")
        write_plugin_source(first, "mah-plug", {"mahcommand" => "MahCommand"})
        write_plugin_source(second, "raiser", {"boomer" => "BoomCommand"})
        run_cli(["plugin", "install", "mah-plug", "--path", first])[0].should eq(0)
        run_cli(["plugin", "install", "raiser", "--path", second])[0].should eq(0)
        index = File.read(plugin_index_path(dir))
        index.should contain(%(  mahcommand: "mah-plug"))
        index.should contain(%(  boomer: "raiser"))
        index.scan(/^  mah-plug: "/m).size.should eq(1)
        index.scan(/^  raiser: "/m).size.should eq(1)
      end
    end
  end
end
