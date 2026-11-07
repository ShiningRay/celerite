# Compatibility matrix (M0 baseline)

Generated from the pinned reference revisions in `vendor/reference/MANIFEST.md`
(Bundler 4.0.24 primary; 2.7.2 still-supported reference). Every entry states which
reference version it was derived from. Behavior not listed here must not be
implemented ad hoc — extend the matrix first, then implement, then differential-test.

## Files

| File | Content |
|---|---|
| [lockfile-sections.md](lockfile-sections.md) | Lockfile sections, grammar, ordering, per-version quirks |
| [gemfile-dsl.md](gemfile-dsl.md) | Gemfile DSL methods and their observable effects |
| [cli-commands.md](cli-commands.md) | Command inventory, flags, exit codes (expandable per command) |
| [config-keys.md](config-keys.md) | Config keys, env names, priority, persistence |

## Reference version policy

- The oracle for differential tests is the pinned upstream revision, executed in an
  isolated environment (`script/differential`).
- When upstream moves, re-pin, regenerate fixtures, and review changed behavior;
  never refresh expectations silently to make a diff go green.
- 2.7.2 vs 4.0.24 deltas are recorded per topic in each file; where behavior diverges
  the implementation selects by the resolved reference profile (`BUNDLED WITH`,
  `BUNDLE_LOCKFILE`, or user-selected profile), never by guessing.
