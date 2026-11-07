# CLI commands — reference: Bundler 4.0.24 / 2.7.2

Authoritative per-command flags live in
[generated/cli-4.0.24.md](generated/cli-4.0.24.md) and
[generated/cli-2.7.2.md](generated/cli-2.7.2.md), regenerated from the pinned oracles
by `script/gen-cli-baseline`. This file fixes the inventory, global behavior, and
exit-code contract; per-command expansion happens as each command is implemented
(M1 read-only first, M3 install paths, M5 full coverage).

## Inventory (identical in both references)

- Primary: `install`, `update`, `cache` (`package`, `pack` aliases), `exec`, `config`, `help`.
- Utilities: `add`, `binstubs`, `check`, `show`, `info`, `list`, `licenses`, `fund`,
  `outdated`, `console` (deprecated), `open`, `lock`, `init`, `gem`, `platform`,
  `clean`, `pristine`, `doctor`, `env`, `issue`, `remove`, `plugin`, `version`.
- Plugin/PATH fallback: unknown command → try plugin command registry, then
  `bundler-<command>` executable on PATH.
- `bundle gem` sub-templates and `bundle plugin` subcommands (`install`, `list`,
  `new` in 2.7.2; 4.0.24 drops `new`) — bridge/deferred to M5.

## Global options (before subcommand)

`--no-color`, `--retry=NUMBER` (`-r`), `--verbose` (`-V`); version flag via
`--version` resolves to the `version` command.

## Exit-code contract (observed from the reference binaries)

| Situation | Code |
|---|---|
| success | 0 |
| generic failure (M1 locked-path messages) | 1 |
| `Bundler::SolveFailure` (resolution failed) | 6 |
| `Bundler::GemNotFound` (missing gem) | 7 |
| `Bundler::GemfileNotFound` | 10 |
| unknown command (Thor::Error) | 15 |
| frozen mode without a lockfile / frozen lockfile missing a Gemfile dep (`ProductionError`) | 16 |
| `Bundler::LockfileError` (unreadable/conflicted lockfile) | 20 |
| checksum mismatch (`SecurityError`) | 37 |

Exception-path errors render through the friendly-errors pipeline: the message
is word-wrapped at 80 columns (THOR_COLUMNS override) on stderr; direct
`ui.error` calls (check/list locked-path messages) are not wrapped.
| `check` with missing gems / lockfile mismatch | 1 |
| Gemfile/lockfile parse or resolve errors | 1 |
| unknown command | 1 (`Could not find command "<cmd>".` on stderr) |
| unimplemented-by-engine operations | fail fast with an explicit engine message; never silently degrade (architecture constraint 5) |

stdout/stderr split is asserted in differential tests, not derived from docs.

## Behavior rules

1. Commands that only read an existing lockfile must never write the lockfile.
2. `--gemfile`/`--lockfile` overrides shift the project root resolution
   (Gemfile dir becomes the root).
3. Errors print to stderr with a trailing blank line where the reference does;
   exact text differential-tested per case.
4. Non-TTY output must be identical byte-for-byte after normalization
   (paths, temp dirs, timings).
5. `lock` always re-resolves (never takes a locked shortcut) and ignores
   frozen mode entirely; progress lines ("Fetching source index from <remote>",
   "Resolving dependencies...") go to stdout in write mode and stderr with
   `--print`.
