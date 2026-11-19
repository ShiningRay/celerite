require "./spec_helper"

# M7(3) task-50: `info`/`show` must read the installed specification the way the
# reference does (`Gem::Specification.load`), so Ruby escapes such as `\\`,
# `\"` and `\n` in `summary` and `metadata` are already decoded when printed.
# Before this change the Crystal side regex-parsed the .gemspec text and printed
# the escapes literally.
private def meta_gemspec : String
  bs = "\\"
  String.build do |io|
    io << "Gem::Specification.new do |s|\n"
    io << "  s.name = \"meta_gem\"\n"
    io << "  s.version = \"1.0.0\"\n"
    io << "  s.summary = 'Summary with \"quotes\" and " << bs << bs << " backslash'\n"
    io << "  s.homepage = \"https://example.com/meta_gem\"\n"
    io << "  s.metadata = {\n"
    io << "    \"documentation_uri\" => \"path" << bs << bs << "with" << bs << bs << "backslashes\",\n"
    io << "    \"changelog_uri\" => \"line1" << bs << "nline2\",\n"
    io << "  }\n"
    io << "end\n"
  end
end

META_LOCKFILE_TEXT = <<-LOCK
GEM
  remote: https://rubygems.org/
  specs:
    meta_gem (1.0.0)

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  meta_gem

BUNDLED WITH
   4.0.24
LOCK

private def capture_command(&block : (IO, IO) -> Int32) : {Int32, String, String}
  output_io = IO::Memory.new
  error_io = IO::Memory.new
  code = yield output_io, error_io
  {code, output_io.to_s, error_io.to_s}
end

private def meta_project(with_gem_dir : Bool) : Hash(String, String)
  files = {
    "Gemfile"                                                        => "source \"https://rubygems.org/\"\n\ngem \"meta_gem\"\n",
    "Gemfile.lock"                                                   => META_LOCKFILE_TEXT,
    ".bundle/config"                                                 => "---\nBUNDLE_PATH: \"vendor/bundle\"\n",
    "vendor/bundle/ruby/3.4.0/specifications/meta_gem-1.0.0.gemspec" => meta_gemspec,
  }
  if with_gem_dir
    files["vendor/bundle/ruby/3.4.0/gems/meta_gem-1.0.0/lib/meta_gem.rb"] = ""
  end
  files
end

private def with_bridge_server(&)
  server = File.expand_path("../assets/bridge/server.rb", __DIR__)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = server
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

describe "M7 gem info metadata decoding" do
  it "decodes backslash escapes from summary and metadata" do
    with_bridge_server do
      with_project(meta_project(with_gem_dir: true)) do
        code, out, err = capture_command { |o, e| Celerite::Commands.show_info("info", o, e, ["meta_gem"]) }
        code.should eq(0)
        err.should eq("")
        out.should contain("  * meta_gem (1.0.0)\n")
        out.should contain("\tSummary: Summary with \"quotes\" and \\ backslash\n")
        out.should contain("\tDocumentation: path\\with\\backslashes\n")
      end
    end
  end

  it "prints a newline escape in metadata as a real newline" do
    with_bridge_server do
      with_project(meta_project(with_gem_dir: true)) do
        code, out, _err = capture_command { |o, e| Celerite::Commands.show_info("info", o, e, ["meta_gem"]) }
        code.should eq(0)
        out.should contain("\tChangelog: line1\nline2\n")
        out.should_not contain("line1\\nline2")
      end
    end
  end

  it "keeps decoded gemspec information when only the specification exists" do
    with_bridge_server do
      with_project(meta_project(with_gem_dir: false)) do
        code, out, err = capture_command { |o, e| Celerite::Commands.show_info("info", o, e, ["meta_gem"]) }
        code.should eq(0)
        out.should eq("")
        err.should contain("The gem meta_gem is missing. Gemspec information is still available though:\n")
        err.should contain("\tDocumentation: path\\with\\backslashes\n")
        err.should contain("\tChangelog: line1\nline2\n")
      end
    end
  end
end
