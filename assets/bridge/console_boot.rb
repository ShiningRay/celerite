# frozen_string_literal: true

# Console boot helper for `celerite console [GROUP]`.
#
# Mirror of the reference's in-process console entry point
# (bundler-4.0.24/lib/bundler/cli/console.rb:11-45, identical apart from the
# `Gem::BUNDLED_GEMS.force_activate` branch in 2.7.2):
#
#   group ? Bundler.require(:default, *group.split(" ").map!(&:to_sym)) : Bundler.require
#   ARGV.clear
#   console = get_console(Bundler.settings[:console] || "irb")
#   console.start
#
# The console command runs this script in a child Ruby process instead of
# calling `console.start` inside the CLI process, so the bundle's gem require
# and group semantics happen exactly like the reference before the console's
# `start` takes over the terminal.
#
# Inputs (set by the console command):
#   BUNDLE_GEMFILE          - project Gemfile (absolute, forward slashes)
#   CELERITE_CONSOLE        - console name from BUNDLE_CONSOLE, defaults to irb
#   CELERITE_CONSOLE_GROUPS - the GROUP argument as given on the command line

require "bundler/setup"

groups = ENV["CELERITE_CONSOLE_GROUPS"].to_s
if groups.empty?
  Bundler.require
else
  Bundler.require(:default, *groups.split(" ").map!(&:to_sym))
end
ARGV.clear

# cli/console.rb:38-45: only these three names have a start constant.
CONSOLE_CONSTANTS = {
  "pry" => :Pry,
  "ripl" => :Ripl,
  "irb" => :IRB,
}.freeze

def console_constant(name)
  # `Object.const_get(nil)` is what the reference does for unknown names.
  Object.const_get(CONSOLE_CONSTANTS[name])
end

name = ENV["CELERITE_CONSOLE"].to_s
name = "irb" if name.empty?

begin
  require name
  console = console_constant(name)
rescue LoadError
  # cli/console.rb:22-35. The 4.0.24 `Gem::BUNDLED_GEMS.force_activate "irb"`
  # retry is deliberately not mirrored (declared deviation): it only exists for
  # Ruby builds that ship irb/racc as bundled gems, and it fails on this host
  # anyway.
  unless name == "irb"
    Bundler.ui.error "Couldn't load console #{name}, falling back to irb"
    begin
      require "irb"
      console = Object.const_get(:IRB)
    rescue LoadError
      Bundler.ui.error "irb is not available"
      exit 1
    end
  else
    Bundler.ui.error "irb is not available"
    exit 1
  end
end

console.start
