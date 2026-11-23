require "./spec_helper"

# S6 (`docs/roadmap-evidence/M8-no-ruby-fast-path.md` §8.4): `bundle list`
# without a group selection is an identity transform, so it must not start the
# Ruby bridge at all. The acceptance environment is a *plain* one: no
# `CELERITE_BRIDGE_SERVER` / `CELERITE_REFERENCE_BUNDLER_LIB` hints, isolated
# HOME/TMP. The probe environment still spawns once for
# `lock_ruby_unlock_kind`, which is why the zero-spawn claim is scoped to the
# plain environment.
private S6_GEM_INDEX = file_source_url(File.expand_path("../fixtures/gem-index", __DIR__))

private S6_STATS_LINE = /^bridge: procs=(\d+) rpc=(\d+) req_bytes=(\d+) resp_bytes=(\d+)$/

private def s6_bin : String?
  path = File.expand_path("../bin/celerite.exe", __DIR__)
  File.exists?(path) ? path : nil
end

private def s6_gemfile : String
  <<-GEMFILE
  source "#{S6_GEM_INDEX}"

  gem "json_pure"
  GEMFILE
end

private def s6_with_env(project : String, &)
  keys = [
    "CELERITE_BRIDGE_SERVER", "CELERITE_REFERENCE_BUNDLER_LIB",
    "HOME", "USERPROFILE", "BUNDLE_PATH", "TMPDIR", "TMP", "TEMP",
  ]
  previous = {} of String => String?
  keys.each { |key| previous[key] = ENV[key]? }
  tmp = File.join(project, "tmp")
  Dir.mkdir_p(tmp)
  ENV.delete("CELERITE_BRIDGE_SERVER")
  ENV.delete("CELERITE_REFERENCE_BUNDLER_LIB")
  ENV["HOME"] = project
  ENV["USERPROFILE"] = project
  ENV["BUNDLE_PATH"] = File.join(project, ".bundle-test")
  ENV["TMPDIR"] = tmp
  ENV["TMP"] = tmp
  ENV["TEMP"] = tmp
  begin
    yield
  ensure
    previous.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

private def s6_run(project : String, args : Array(String)) : {Int32, String, String}
  bin = s6_bin.not_nil!
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(bin, args, chdir: project, output: output, error: errors)
  {status.exit_code, output.to_s, errors.to_s}
end

private def s6_stats(errors : String) : Array(String)
  errors.lines.select(&.starts_with?("bridge: procs="))
end

private def s6_counters(errors : String) : {Int32, Int32}
  line = s6_stats(errors).first?
  fail "missing bridge stats line in #{errors.inspect}" unless line
  match = line.match(S6_STATS_LINE).not_nil!
  {match[1].to_i, match[2].to_i}
end

describe "bundle list without a group selection starts no bridge" do
  it "reports procs=0 rpc=0 for every output form and keeps the default group on the old path" do
    pending!("bin/celerite.exe is not built") unless s6_bin
    with_project({"Gemfile" => s6_gemfile}) do |project|
      s6_with_env(project) do
        install_status, install_out, install_err = s6_run(project, ["install"])
        fail "install failed (#{install_status}): #{install_out} #{install_err}" unless install_status == 0

        lock_before = File.read(File.join(project, "Gemfile.lock"))
        previous_stats = ENV["CELERITE_BRIDGE_STATS"]?
        ENV["CELERITE_BRIDGE_STATS"] = "1"
        begin
          {"list", "list --paths", "list --name-only", "list --format=json"}.each do |command|
            args = command.split(" ")
            status, output, errors = s6_run(project, args)
            status.should eq(0)
            procs, rpc = s6_counters(errors)
            procs.should eq(0)
            rpc.should eq(0)
            output.should contain("json_pure")
          end

          status, output, errors = s6_run(project, ["list", "--only-group", "default"])
          status.should eq(0)
          output.should contain("Gems included by the bundle:")
          procs, _rpc = s6_counters(errors)
          procs.should eq(1)

          status, output, errors = s6_run(project, ["list", "--only-group", "nope"])
          status.should eq(15)
          output.should eq("")
          errors.should contain("`nope` group could not be found.")
        ensure
          if previous_stats
            ENV["CELERITE_BRIDGE_STATS"] = previous_stats
          else
            ENV.delete("CELERITE_BRIDGE_STATS")
          end
        end

        File.read(File.join(project, "Gemfile.lock")).should eq(lock_before)
      end
    end
  end
end
