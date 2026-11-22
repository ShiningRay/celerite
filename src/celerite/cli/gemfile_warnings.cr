require "../bridge/client"
require "../definition"

module Celerite
  module Commands
    # Commands whose reference implementation evaluates the Gemfile inside
    # `Bundler.ui.silence`, so a repeated-declaration warning never reaches the
    # terminal: `show`/`info` (`bundler/cli/show.rb:13-17`,
    # `bundler/cli/info.rb:11-15`) and `exec` (`bundler/setup.rb:16/32`).
    SILENT_GEMFILE_WARNING_COMMANDS = ["show", "info", "exec"]

    # Opens the per-command ledger for Gemfile warnings. The bridge returns the
    # warnings raised by each evaluation (repeated `gem` declarations,
    # `dsl.rb:307-323`) instead of printing them, because one command evaluates
    # the same Gemfile from several bridge processes; the ledger prints every
    # distinct message once, which is what the reference does within a single
    # process (`bundler.rb` `@definition ||=` plus the `@warning_history` dedup
    # in `ui/shell.rb:39-45`). `CLI.run` closes the ledger in its ensure block.
    def self.begin_gemfile_warnings(stderr : IO, command : String) : Nil
      Bridge::GemfileWarnings.begin(stderr, SILENT_GEMFILE_WARNING_COMMANDS.includes?(command))
    end

    # `bundle remove` rewrites the Gemfile, and the reference reports the
    # duplicate declarations it is about to delete: `Injector#remove` reaches
    # `Bundler.definition` (injector.rb:65), which evaluates the *original*
    # Gemfile before the rewrite, and `Installer.install` (cli/remove.rb:14)
    # then reuses that cached definition. Evaluating here reproduces both the
    # warning and its position ahead of the rewrite; the failure path is
    # best-effort so a missing bridge still lets `remove` run.
    def self.evaluate_gemfile_before_rewrite(definition : Definition) : Nil
      client = begin
        Bridge::Client.new
      rescue
        return
      end
      begin
        client.evaluate_gemfile(definition.gemfile_path)
      rescue
        nil
      ensure
        client.close
      end
    end
  end
end
