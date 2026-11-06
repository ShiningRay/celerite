require "./errors"
require "digest/sha1"
require "file_utils"

module Celerite
  # Git source orchestration (pinned contract: `Bundler::Source::Git`).
  #
  # Layout (observed from the reference):
  # - bare mirror: `<bundle_path>/ruby/<abi>/cache/bundler/git/<base_name>-<sha1(uri)>/`
  # - checkout:    `<bundle_path>/ruby/<abi>/bundler/gems/<base_name>-<revision[0,12]>/`
  # - the checkout keeps its .git (shallow clone from the mirror)
  class GitSource
    getter base_name : String
    getter scope : String
    getter mirror : String
    getter checkout_root : String
    getter remote : String

    def initialize(@remote : String, @bundle_root : String)
      @base_name = GitSource.base_name(remote)
      @scope = "#{base_name}-#{GitSource.uri_hash(remote)}"
      @mirror = File.join(bundle_root, "cache", "bundler", "git", scope)
      @checkout_root = File.join(bundle_root, "bundler", "gems")
    end

    def self.base_name(uri : String) : String
      stripped = uri.sub(%r{^(\w+://)?([^/:]+:)?(//\w*/)?(\w*/)*}, "")
      File.basename(stripped, ".git")
    end

    def self.uri_hash(uri : String) : String
      # Pinned: SHA1 of the uri; for scheme URIs the normalized form without a
      # trailing slash, for plain paths the uri as-is.
      input = if uri.matches?(/^\w+:\/\/(\w+@)?/)
                normalized = URI.parse(uri).normalize.to_s
                normalized.sub(%r{/$}, "")
              else
                uri
              end
      Digest::SHA1.hexdigest(input)
    end

    def revision_cached? : Bool
      Dir.exists?(mirror)
    end

    # Clones/updates the bare mirror and returns the revision for the ref.
    def fetch(ref : String?) : String
      FileUtils.mkdir_p(File.dirname(mirror))
      unless Dir.exists?(mirror)
        run("git", ["clone", "--mirror", @remote, mirror])
      else
        run("git", ["fetch", "--quiet", "origin", "+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*"], mirror)
      end
      revision_for(ref)
    end

    private def remote_ref_argument : String
      # read from the original remote captured at construction
      @remote
    end

    def revision_for(ref : String?) : String
      args = ["rev-parse", ref || "HEAD"]
      run("git", args, mirror).strip
    end

    # Ensures the checkout for the revision exists; returns its directory.
    def checkout(revision : String, submodules : Bool) : String
      short = revision[0, 12]
      destination = File.join(checkout_root, "#{base_name}-#{short}")
      unless Dir.exists?(destination)
        FileUtils.mkdir_p(File.dirname(destination))
        run("git", ["clone", "--quiet", "--no-hardlinks", mirror, destination])
        run("git", ["checkout", "--quiet", revision], destination)
        if submodules
          run("git", ["submodule", "update", "--init", "--recursive"], destination)
        end
      end
      destination
    end

    private def run(executable : String, args : Array(String), chdir : String? = nil) : String
      output = IO::Memory.new
      errors = IO::Memory.new
      result = chdir ? Process.run(executable, args, chdir: chdir, output: output, error: errors) : Process.run(executable, args, output: output, error: errors)
      unless result.success?
        raise Error.new("git command failed: #{executable} #{args.join(" ")} — #{errors.to_s.chomp}")
      end
      output.to_s
    end
  end
end
