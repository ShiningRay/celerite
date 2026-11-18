module Pry
  def self.start(*)
    puts "PROBE_START default=#{defined?(ProbeDefault) ? 1 : 0} foo=#{defined?(ProbeFoo) ? 1 : 0} argv=#{ARGV.inspect}"
    exit 0
  end
end