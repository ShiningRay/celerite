# Upstream Bundler spec feasibility spike (M5)

Reference revision: `rubygems/rubygems` @ `v4.0.24`, `bundler/spec/` (271 spec
files). Date: 2026-11-07. Scope: assess how the upstream suite can drive
Celerite, per roadmap M0/M5.

## Harness anatomy (what the specs require)

- RSpec with `bundler/spec/spec_helper.rb`; heavy global fixtures:
  `build_repo2`/`build_repo4` construct in-process gem servers
  (`Gem::Resolver::APISet`-compatible index + `.gem` files served from a local
  `tmp` dir), `install_gemfile`/`gem` helpers shell out to `bundle` via
  `Bundler.bundleExecutable`, and `system_gems` installs real gems into an
  isolated GEM_HOME.
- The suite runs the **real Ruby Bundler binary**; every expectation compares
  stdout/stderr text, lockfile bytes, or installed file trees.
- Many specs exercise Ruby-only internals (`Bundler::Definition`,
  `Gem::Specification` marshaling) that belong to the bridge by design.

## Options assessed

1. **Drive Celerite through a `bundle` shim.** The suite resolves `bundle` via
   `system("bundle ...")`; a PATH shim pointing at `bin/celerite` makes text/
   lockfile/tree expectations run against Celerite unmodified. Feasible; the
   shim must export `CELERITE_BRIDGE_SERVER` and a pinned
   `CELERITE_REFERENCE_BUNDLER_LIB` — doable via a wrapper script.
2. **Selective per-file suites.** The lockfile-format specs
   (`spec/lock/lockfile_spec.rb`, ~30 examples) and resolver specs
   (`spec/resolver/*`, pure-logic fixtures via `SpecSet` Ruby internals) are
   the two families. The lockfile family only needs `build_repo2`-equivalent
   fixtures — reproducible with `gem generate_index` from checked-in `.gem`
   files (our `fixtures/gem-index` pattern scales to this). The resolver
   family requires Ruby `Gem::Resolver` internals — **not applicable to
   Celerite's native PubGrub** without reimplementing the harness; excluded
   with cause.
3. **Full suite.** Not feasible in CI: `quality_spec` (rubocop on bundler
   sources), `realworld` (network), and plugin suites require Ruby Bundler
   semantics (hooks, `Gem::Specification` mutation) that belong to the bridge.

## Decision

- Adopt option 2's lockfile family via the shim (option 1) as the CI harness
  for M6: a `script/upstream-specs` wrapper that (a) checks out the pinned
  revision, (b) builds `repo2` fixtures from checked-in gems, (c) runs
  `rspec spec/lock/lockfile_spec.rb` with the `bundle` shim on PATH,
  (d) records per-example pass/fail into `docs/compat-matrix/generated/`.
- Resolver, runtime, plugin, realworld and quality suites: excluded with the
  causes above; reviewed at each upstream re-pin (compatibility.md rule 6).
- Recorded exclusions are reviewed against the pinned tag, not silently
  dropped.

## Not applicable items (with cause)

| Suite | Cause |
|---|---|
| `spec/resolver/*` | drives Ruby `Gem::Resolver::SpecSet` internals; Celerite resolves via native PubGrub with its own spec model. Behavioral parity is covered by our differential fixtures instead. |
| `spec/runtime/*` | requires `Bundler.setup` inside real Ruby processes (bridge M5+ scope; Celerite provides the environment contract, not the Ruby runtime). |
| `spec/plugins/*` | plugin hooks execute Ruby plugin code through the bridge; specs assert Ruby-side `Bundler::Plugin` API objects. Native command dispatch is covered by `plugin list/install` specs we add. |
| `spec/realworld/*` | network-dependent by design. |
| `spec/quality_*` | lint the Ruby Bundler codebase itself. |
