require "./spec_helper"
require "../src/celerite"

# `Bundler::Source::Git#eql?` (source/git.rb:76-81) includes uri, ref, branch,
# glob and submodules; a changed source must therefore re-resolve instead of
# taking the locked path. `Bundler::Source::Path#eql?` (path.rb:64-67) is the
# analogous rule for PATH sources. These examples drive the public reuse gate,
# so the pre-fix code (which only compared GEM remotes) fails the changed-source
# cases by returning true.
private def git_reuse_index : String
  file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))
end

private def git_reuse_gemfile(index : String, specifiers : String) : String
  String.build do |io|
    io << "source \"" << index << "\"\n\n"
    io << "gem \"ckeditor\", git: \"https://example.com/repo.git\", " << specifiers << "\n"
  end
end

private def git_reuse_lock(index : String, options : String, version : String = "4.0.7") : String
  String.build do |io|
    io << "GIT\n"
    io << "  remote: https://example.com/repo.git\n"
    io << "  revision: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
    options.each_line { |line| io << line << '\n' }
    io << "  specs:\n"
    io << "    ckeditor (" << version << ")\n"
    io << "\nGEM\n"
    io << "  remote: " << index << "/\n"
    io << "  specs:\n"
    io << "\nPLATFORMS\n"
    io << "  ruby\n"
    io << "\nDEPENDENCIES\n"
    io << "  ckeditor!\n"
    io << "\nBUNDLED WITH\n"
    io << "   4.0.24\n"
  end
end

describe "git source reuse" do
  it "re-resolves when the Gemfile tag differs from the lockfile" do
    pending! "ruby not available" unless ruby_available?
    index = git_reuse_index
    with_client do |client|
      with_project({
        "Gemfile"      => git_reuse_gemfile(index, "tag: \"v4.0.8\""),
        "Gemfile.lock" => git_reuse_lock(index, "  tag: v4.0.7\n"),
      }) do |_dir|
        resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
        resolution.progress = IO::Memory.new
        resolution.reuse_locked?.should be_false
      end
    end
  end

  it "reuses when the Git source specifiers match" do
    pending! "ruby not available" unless ruby_available?
    index = git_reuse_index
    with_client do |client|
      with_project({
        "Gemfile"      => git_reuse_gemfile(index, "tag: \"v4.0.7\""),
        "Gemfile.lock" => git_reuse_lock(index, "  tag: v4.0.7\n"),
      }) do |_dir|
        resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
        resolution.progress = IO::Memory.new
        resolution.reuse_locked?.should be_true
      end
    end
  end

  it "re-resolves when ref, branch, glob or submodules differ" do
    pending! "ruby not available" unless ruby_available?
    index = git_reuse_index
    cases = {
      {"ref: \"v4.0.7\"", "tag: v4.0.7"},
      {"branch: \"main\"", "branch: \"stable\""},
      {"glob: \"*.gemspec\"", "glob: \"extra/*.gemspec\""},
      {"submodules: true", "tag: v4.0.7"},
    }
    cases.each do |(gemfile_option, lock_option)|
      with_client do |client|
        with_project({
          "Gemfile"      => git_reuse_gemfile(index, gemfile_option),
          "Gemfile.lock" => git_reuse_lock(index, "  #{lock_option}\n"),
        }) do |_dir|
          resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
          resolution.progress = IO::Memory.new
          resolution.reuse_locked?.should be_false
        end
      end
    end
  end

  it "re-resolves when a PATH source glob differs" do
    pending! "ruby not available" unless ruby_available?
    index = git_reuse_index
    lock = <<-LOCK
      GEM
        remote: #{index}/
        specs:

      PATH
        remote: ./pathgem
        glob: extra/*.gemspec
        specs:
          pathgem (1.0.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        pathgem!

      BUNDLED WITH
         4.0.24
      LOCK
    with_client do |client|
      with_project({
        "Gemfile"      => %(source "#{index}"\n\ngem "pathgem", path: "./pathgem", glob: "*.gemspec"\n),
        "Gemfile.lock" => lock,
      }) do |_dir|
        resolution = Celerite::Resolution.new(Celerite::Definition.build, false, client)
        resolution.progress = IO::Memory.new
        resolution.reuse_locked?.should be_false
      end
    end
  end
end
