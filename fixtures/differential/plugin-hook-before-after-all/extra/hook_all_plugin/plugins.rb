require "bundler/plugin/api"

Bundler::Plugin.add_hook("before-install-all") do |deps|
  groups = begin
    deps.map { |d| d.groups.to_a.sort.join("+") }.join(",")
  rescue StandardError => e
    "ERR:#{e.class}"
  end
  puts "BEFORE_ALL class=#{deps.class} elems=#{deps.map(&:class).uniq.join("+")} names=#{deps.map(&:name).join(",")} groups=#{groups}"
end

Bundler::Plugin.add_hook("after-install-all") do |deps|
  puts "AFTER_ALL class=#{deps.class} elems=#{deps.map(&:class).uniq.join("+")} names=#{deps.map(&:name).join(",")}"
end