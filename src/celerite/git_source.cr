require "./errors"
require "./definition"
require "digest/sha1"
require "file_utils"

module Celerite
  # Git source orchestration (pinned contract: `Bundler::Source::Git`).
  #
  # Layout (observed from the reference):
  # - bare mirror: `<bundle_path>/ruby/<abi>/cache/bundler/git/<base_name>-<sha1(uri)>/`
  # - checkout:    `<bundle_path>/ruby/<abi>/bundler/gems/<base_name>-<revision[0,12]>/`
  # - the checkout keeps its .git: `git clone --no-checkout` from the mirror,
  #   then `git fetch --depth 1 <revision>` + `git reset --hard`, exactly as
  #   `Source::GitProxy#copy_to` does (hence its FETCH_HEAD/ORIG_HEAD/shallow).
  class GitSource
    getter base_name : String
    getter scope : String
    getter mirror : String
    getter checkout_root : String
    getter remote : String
    # Revision the last `checkout` materialized, and the directory it produced.
    # Callers that need the checkout (the plugin installer) take it from here
    # rather than re-deriving it from a filesystem glob.
    property revision : String?
    property checkout_dir : String?

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

    # True when `revision` is present in the local mirror, mirroring the
    # reference's `GitProxy#has_revision_cached?` (`git cat-file -e <rev>`):
    # the question is whether the *revision* is cached, not whether the mirror
    # directory exists.
    def revision_cached?(revision : String) : Bool
      return false unless Dir.exists?(mirror)
      run("git", ["cat-file", "-e", revision], mirror)
      true
    rescue GitError
      false
    end

    # Clones/updates the bare mirror and returns the revision for the ref.
    #
    # Branch/tag names are resolved against the mirror's namespaced refs so a
    # tag or branch with the same name as a local ref cannot be picked up by
    # accident (reference: `Bundler::Source::Git#revision_for`).
    def fetch(branch : String? = nil, tag : String? = nil, ref : String? = nil) : String
      FileUtils.mkdir_p(File.dirname(mirror))
      begin
        unless Dir.exists?(mirror)
          run("git", ["clone", "--mirror", @remote, mirror])
        else
          run("git", ["fetch", "--quiet", "origin", "+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*"], mirror)
        end
      rescue ex : GitError
        # Reference: `Source::Git#fetch` (`source/git.rb:416-420`) warns and
        # keeps going when the remote cannot be reached. Degrade only when the
        # mirror already holds the revision we are about to use — otherwise the
        # error stands (`git_proxy.rb:400-406` decides cache freshness by
        # probing the revision, not by the directory existing).
        raise ex unless revision_cached_for?(branch: branch, tag: tag, ref: ref)
        Definition.default_warning_sink.puts "Using cached git data because of network errors:\n#{ex.message}"
      end
      revision_for(branch: branch, tag: tag, ref: ref)
    end

    # Resolves a revision without fetching (used when the lockfile already
    # pins a revision and the mirror is present).
    def revision_for(branch : String? = nil, tag : String? = nil, ref : String? = nil) : String
      target = revision_target(branch: branch, tag: tag, ref: ref)
      output = run("git", ["rev-parse", "--verify", "#{target}^{commit}"], mirror).strip
      raise Error.new("git revision not found for #{target} in #{@remote}") if output.empty?
      output
    end

    # Ensures the checkout for the revision exists; returns its directory.
    #
    # The clone/fetch sequence mirrors `Bundler::Source::Git::GitProxy#copy_to`
    # (`source/git/git_proxy.rb:137-175`): clone the bare mirror without a
    # checkout, point `origin` back at the real remote, fetch the pinned
    # revision, then `reset --hard` it into the working tree. A plain
    # `clone` + `checkout` produces the same files but a *different* `.git`
    # (no `FETCH_HEAD` / `ORIG_HEAD` / `shallow`, and `origin` left pointing at
    # the local mirror), and the reference's checkout directory is part of the
    # plugin materialization tree compared by the differential harness.
    def checkout(revision : String, submodules : Bool) : String
      short = revision[0, 12]
      destination = File.join(checkout_root, "#{base_name}-#{short}")
      @revision = revision
      @checkout_dir = destination
      unless Dir.exists?(destination)
        FileUtils.mkdir_p(File.dirname(destination))
        run("git", ["clone", "--no-checkout", "--quiet", mirror, destination])
        run("git", ["remote", "set-url", "origin", @remote], destination)
        # `GitProxy#copy_to` then does `File.chmod((mode | 0o777) & ~File.umask)`;
        # Crystal's stdlib has no `File.umask` and the call is a no-op on
        # Windows, so it is intentionally omitted here.
        run("git", ["config", "uploadpack.allowAnySHA1InWant", "true"], mirror)
        run("git", ["fetch", "--force", "--quiet", *extra_fetch_args, mirror, revision], destination)
        run("git", ["reset", "--hard", revision], destination)
        if submodules
          run("git", submodule_update_args, destination)
        end
      end
      destination
    end

    # `GitProxy#copy_to` fetches the pinned revision with
    # `extra_fetch_args(ref)` (`git_proxy.rb:551-555`), which is
    # `[path, *depth_args, ref]`; `depth_args` is `["--depth", "1"]` for a
    # shallow source (`:545-549`, and `shallow?` is true for a branch ref,
    # `:561-563`). The mirror is passed as the fetch *source* instead of the
    # configured URI because `run` already resolved it.
    #
    # Do not add `--` before the positionals: the mirror is a `C:\...` path,
    # and git then parses it as a pathspec and aborts with
    # `fatal: invalid refspec 'C:\...'`.
    private def extra_fetch_args : Array(String)
      ["--depth", "1"]
    end

    # `git submodule update` refuses `file://` transports since git 2.38
    # (CVE-2022-39253 mitigation). Celerite resolves submodules from the
    # local mirror, so a local source needs the protocol explicitly allowed —
    # only for local remotes, never for network sources.
    private def submodule_update_args : Array(String)
      args = ["submodule", "update", "--init", "--recursive"]
      return args unless local_remote?
      ["-c", "protocol.file.allow=always"] + args
    end

    private def local_remote? : Bool
      remote = @remote
      return true if remote.starts_with?("file:")
      return true if remote.starts_with?("/") || remote.starts_with?("\\")
      return true if remote.matches?(/\A[A-Za-z]:[\\\/]/)
      !remote.includes?("://") && !remote.matches?(/\A[\w.-]+@[\w.-]+:/)
    end

    private def revision_target(branch : String? = nil, tag : String? = nil, ref : String? = nil) : String
      if branch
        "refs/heads/#{branch}"
      elsif tag
        "refs/tags/#{tag}"
      elsif ref
        ref
      else
        "HEAD"
      end
    end

    private def revision_cached_for?(branch : String? = nil, tag : String? = nil, ref : String? = nil) : Bool
      revision_cached?(revision_target(branch: branch, tag: tag, ref: ref))
    end

    private def run(executable : String, args : Array(String), chdir : String? = nil) : String
      output = IO::Memory.new
      errors = IO::Memory.new
      result = chdir ? Process.run(executable, args, chdir: chdir, output: output, error: errors) : Process.run(executable, args, output: output, error: errors)
      unless result.success?
        raise GitError.new("git command failed: #{executable} #{args.join(" ")} — #{errors.to_s.chomp}")
      end
      output.to_s
    rescue ex : IO::Error
      raise GitError.new("git command failed: #{executable} #{args.join(" ")} — #{ex.message}")
    end
  end
end
