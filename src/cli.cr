require "./celerite/cli"

exit Celerite::CLI.run(ARGV, STDOUT, STDERR)
