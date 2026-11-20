# Compatibility matrix (baseline index)

Two kinds of material live here:

- The four topic files below (`lockfile-sections.md`, `gemfile-dsl.md`,
  `cli-commands.md`, `config-keys.md`) are **hand-collected** from the pinned
  reference revisions in `vendor/reference/MANIFEST.md` (Bundler 4.0.24 primary;
  2.7.2 still-supported reference). Every entry states which reference version it
  was derived from.
- `generated/*` holds **script output and manual evidence dumps**, not curated
  matrix files: the two `cli-*.md` files come from `script/gen-cli-baseline`, and
  the differential/upstream reports are collected run logs. Do not hand-edit
  generator-controlled files; record collection dates here instead.

Behavior not listed here must not be implemented ad hoc — extend the matrix first,
then implement, then differential-test.

## Files

| File | Content |
|---|---|
| [lockfile-sections.md](lockfile-sections.md) | Lockfile sections, grammar, ordering, per-version quirks |
| [gemfile-dsl.md](gemfile-dsl.md) | Gemfile DSL methods and their observable effects |
| [cli-commands.md](cli-commands.md) | Command inventory, flags, exit codes (expandable per command) |
| [config-keys.md](config-keys.md) | Config keys, env names, priority, persistence |

### Generated evidence (`generated/`)

| File | Content | Collected |
|---|---|---|
| [cli-4.0.24.md](generated/cli-4.0.24.md) | `bundle <cmd> --help` text for 4.0.24 (`script/gen-cli-baseline`) | generated 2026-11-19 15:08:52 (mtime) |
| [cli-2.7.2.md](generated/cli-2.7.2.md) | `bundle <cmd> --help` text for 2.7.2 (`script/gen-cli-baseline`) | generated 2026-11-19 15:09:17 (mtime) |
| [differential-4.0.24-2026-11-11.md](generated/differential-4.0.24-2026-11-11.md) | Differential run logs and classification (run started 2026-11-11) | mtime 2026-11-20 14:45:46 (task-61 title edit) |
| [upstream-lockfile-v4.0.24.md](generated/upstream-lockfile-v4.0.24.md) | Upstream lockfile-spec evidence, manually maintained | mtime 2026-11-20 14:44:42 (task-61 note edit) |

## Reference version policy

- The oracle for differential tests is the pinned upstream revision, executed in an
  isolated environment (`script/differential`).
- When upstream moves, re-pin, regenerate fixtures, and review changed behavior;
  never refresh expectations silently to make a diff go green.
- 2.7.2 vs 4.0.24 deltas are recorded per topic in each file; where behavior diverges
  the implementation selects by the resolved reference profile (`BUNDLED WITH`,
  `BUNDLE_LOCKFILE`, or user-selected profile), never by guessing.

For hand-maintained evidence files, appending later notes moves the mtime; the
dates above are the mtimes observed while writing this index (task-61,
2026-11-20), not a claim about the original run time.
