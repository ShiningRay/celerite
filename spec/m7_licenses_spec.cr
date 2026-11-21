require "./spec_helper"

# `cli.rb:571-581`: `Bundler.load.specs.sort_by {|s| s.license.to_s }.reverse_each`
# with `license || licenses`, printing `#{name}: #{license}` on stdout and
# `#{name}: Unknown` on stderr. The values come from the live specs, so a `path`
# source and a bundle without cached `.gem` files still report their license.
describe "celerite licenses" do
  it "reads the license of a path source" do
    with_licenses_env do |project, root|
      write_licenses_gem(root, "multilic", "MIT", nil)
      write_licenses_gemfile(project, ["gem \"json_pure\"", "gem \"multilic\", path: \"../multilic\""])
      ic, _, ierr = run_cli(["install", "--quiet"])
      ic.should eq(0), ierr
      code, out, err = run_cli(["licenses"])
      code.should eq(0)
      out.should contain("multilic: MIT")
      err.should_not contain("multilic")
    end
  end

  it "keeps reporting after the cached packages are removed" do
    with_licenses_env do |project, root|
      write_licenses_gemfile(project, ["gem \"json_pure\""])
      ic, _, ierr = run_cli(["install", "--quiet"])
      ic.should eq(0), ierr
      specs = Dir.glob("#{project.gsub('\\', "/")}/**/specifications/json_pure-*.gemspec")
      specs.empty?.should be_false
      # The license has to come from the installed gemspec, not from a cached
      # package: drop every cache directory the install may have produced.
      Dir.glob("#{project.gsub('\\', "/")}/**/cache").each { |dir| FileUtils.rm_rf(dir) }
      code, out, _ = run_cli(["licenses"])
      code.should eq(0)
      out.should contain("json_pure: Ruby")
    end
  end

  it "reports a gem without a license on stderr" do
    with_licenses_env do |project, root|
      write_licenses_gem(root, "nolic", nil, nil)
      write_licenses_gemfile(project, ["gem \"json_pure\"", "gem \"nolic\", path: \"../nolic\""])
      ic, _, ierr = run_cli(["install", "--quiet"])
      ic.should eq(0), ierr
      code, out, err = run_cli(["licenses"])
      code.should eq(0)
      err.should contain("nolic: Unknown")
      out.should_not contain("nolic")
    end
  end

  it "keeps the Gemfile order inside one license group" do
    with_licenses_env do |project, root|
      write_licenses_gem(root, "alpha", "MIT", nil)
      write_licenses_gem(root, "omega", "MIT", nil)
      write_licenses_gemfile(project, [
        "gem \"json_pure\"",
        "gem \"thor\"",
        "gem \"alpha\", path: \"../alpha\"",
        "gem \"omega\", path: \"../omega\"",
      ])
      ic, _, ierr = run_cli(["install", "--quiet"])
      ic.should eq(0), ierr
      code, out, _ = run_cli(["licenses"])
      code.should eq(0)
      order = out.lines.map(&.split(":").first)
      order.should eq(["json_pure", "bundler", "thor", "alpha", "omega"])
    end
  end
end

private def licenses_index_path : String
  File.expand_path("../fixtures/gem-index", __DIR__)
end

private def licenses_root : String
  File.join(Dir.current, ".tmp-scratch", "spec-licenses")
end

private def write_licenses_gemfile(project : String, lines : Array(String))
  body = String.build do |io|
    io << "source " << file_source_url(licenses_index_path).inspect << "\n\n"
    lines.each { |line| io << line << '\n' }
  end
  File.write(File.join(project, "Gemfile"), body)
end

private def write_licenses_gem(root : String, name : String, license : String?, licenses : Array(String)?)
  dir = File.join(root, name)
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "lib", "#{name}.rb"), "module #{name.capitalize}\nend\n")
  spec = String.build do |io|
    io << "Gem::Specification.new do |s|\n"
    io << "  s.name = " << name.inspect << "\n"
    io << "  s.version = \"1.0.0\"\n"
    io << "  s.summary = \"fixture gem\"\n"
    io << "  s.authors = [\"fixture\"]\n"
    io << "  s.files = [" << "lib/#{name}.rb".inspect << "]\n"
    io << "  s.license = " << license.inspect << "\n" if license
    if licenses
      io << "  s.licenses = [" << licenses.map(&.inspect).join(", ") << "]\n"
    end
    io << "end\n"
  end
  File.write(File.join(dir, "#{name}.gemspec"), spec)
end

private def with_licenses_env(&)
  root = licenses_root
  FileUtils.rm_rf(root)
  project = File.join(root, "project")
  home = File.join(root, "home")
  Dir.mkdir_p(project)
  Dir.mkdir_p(home)
  env = {
    "HOME"                             => home,
    "USERPROFILE"                      => home,
    "BUNDLE_PATH"                      => File.join(project, "bundle"),
    "BUNDLE_APP_CONFIG"                => File.join(project, ".bundle"),
    "BUNDLE_GEMFILE"                   => File.join(project, "Gemfile"),
    "CELERITE_BRIDGE_SERVER"           => File.join(Dir.current, "assets", "bridge", "server.rb"),
    "CELERITE_PROFILE_BUNDLER_VERSION" => "4.0.24",
  }
  saved = {} of String => String?
  env.each { |key, _| saved[key] = ENV[key]? }
  begin
    env.each { |key, value| ENV[key] = value }
    Dir.cd(project) { yield project, root }
  ensure
    saved.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
