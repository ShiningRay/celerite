# Forces Thor::LineEditor to fall back to its Basic backend, so the answers
# echoed to a pipe are plain bytes instead of readline repaint sequences.
# Thor's Readline backend is chosen when `Readline.available?`, which is
# `require "readline"; Object.const_defined?(:Readline)`. Requiring it here
# puts it in $LOADED_FEATURES, and dropping the constant makes that check
# false for the rest of the process.
begin
  require "readline"
  Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
rescue LoadError
end