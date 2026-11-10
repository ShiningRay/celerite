# Upstream Bundler spec feasibility spike (M5, updated M7 iteration 2)

Reference revision: `rubygems/rubygems` @ `v4.0.24`, `bundler/spec/` (271 spec
files). Initial spike: 2026-11-07. M7 iteration 2 update: 2026-11-10.
Scope: assess how the upstream suite can drive Celerite and record
lockfile-family baseline evidence (roadmap M0/M5/M7(8)).

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
- `support/helpers.rb` resolves `bundle_bin` to `installed_bindir.join("bundle")`
  (test tmp gem path) and executes via `#{Gem.ruby} #{bundle_bin} ...`/Open3, not
  `bundle` from `PATH`. `support/path.rb` resolves `dev_binstub`/`installed_bindir`
  under `tmp/`. `support/rubygems_ext.rb#install_test_deps` bootstraps base/system
  gem env, vendored compact_index, and test deps unless `RSPEC_FORMATTER_OUTPUT_ID`
  is set. `spec_helper.rb` builds fixture repos (`build_repo1` in before(:suite))
  and copies pristine system gems per example around hook (`default_system_gems`).

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

## Iteration 2 (2026-11-10, M7(8)) — real harness execution & classification

### Environment and harness state

- Host: Windows (git 2.55, Crystal 1.22.1, ruby 4.0.6 x64-mingw-ucrt, bundler 4.0.24, rspec 3.13). `bin/celerite.exe` present. `.upstream-specs/v4.0.24` sparse checkout present; `bundler/bin`/`bundler/exe` added via sparse-checkout (initially missing).
- `script/upstream-specs` hardened (iteration 2): resolves `bin/celerite(.exe)`, sparse checkout includes `bundler/spec bundler/lib bundler/bin bundler/exe`, prepares gem-index, creates `bundle` bash/cmd/bat shims exporting `CELERITE_BRIDGE_SERVER`, runs rspec from `.upstream-specs/$rev/bundler` with `CELERITE_BRIDGE_SERVER`/`CELERITE_BIN`, optional `CELERITE_SKIP_TEST_DEPS=1` (`RSPEC_FORMATTER_OUTPUT_ID`), invokes `ruby -S rspec` for Windows/Git Bash portability, propagates rspec exit status, and writes raw-output summary/tail to generated report.
- Added optional `script/upstream-specs-celerite-override.rb`: rspec `-r` helper override routing in-example `bundle`/`bundler` helper calls to `CELERITE_BIN` (not enabled by default; only relevant once examples reach helper calls).

### Runs and evidence

| Run | Mode | Result | Classification |
|---|---|---|---|
| Historical local (`.upstream-specs/rspec-output.txt` prior snapshot) | prior harness state | 64 examples, 64 failures | **Harness precondition/unexecuted**: all `NameError: undefined local variable or method 'build_repo2'` at `spec/lock/lockfile_spec.rb:5` before-hook. |
| Probe (no skip) | full upstream setup path | 0 examples, 1 error outside examples (single) / before(:suite) failure | **Harness precondition/unexecuted**: `TypeError: no implicit conversion of nil into String` at `support/builders.rb:31` `FileUtils.cp rake_path, "#{gem_repo1}/gems/"` (`rake_path` nil; base/system gem fixtures not provisioned) or `dev_bundle`/install_test_deps bootstrap issues in Windows env. |
| Direct authoritative run (2026-11-10, seed 55658) | `CELERITE_SKIP_TEST_DEPS=1`, `ruby -S rspec` from bundler dir, shim on PATH | **64 examples, 64 failures**, rspec exit 1, ~0.38s | **Harness precondition/unexecuted (64/64)**: uniform `Errno::ENOENT @ realpath_rec .../bundler/tmp/gems` from `support/helpers.rb:528 default_system_gems` (`spec_helper.rb` around hook) before example bodies/assertions. No pending. |
| `bash script/upstream-specs` rerun attempt | updated script | script exit 127 (`/mnt/c/Ruby40-x64/bin/rspec: cannot execute` under this Git Bash/WSL interop path) | **Harness/script portability blocker** for unattended run; not a compatibility result. Direct `ruby -S rspec` evidence above remains authoritative. |

### 64-failure baseline classification (current)

- **Harness precondition / not executed against Celerite:** 64/64.
- **Real Celerite compatibility gap (example executed to assertion):** 0/64 (no evidence).
- **Passed:** 0/64. **Pending/skipped:** 0/64.
- **Conclusion:** the lockfile family baseline is currently a **non-execution baseline** driven by upstream Bundler spec environment dependencies (pristine/base/system gem trees under `tmp/`, repo builder fixtures, install_test_deps/compact_index setup). It must not be recorded as 64 compatibility failures, 64 passes, or pending-as-green. Prior interpretation that treated these as merely “pending/unexecuted” is directionally right but now backed by concrete per-run error evidence and should be kept specific to the observed precondition mode.

### Real-driver assessment

- PATH shims and `CELERITE_BRIDGE_SERVER`/`CELERITE_BIN` wiring are in place; Windows `.cmd/.bat` shims added.
- Upstream in-example bundle calls go through helpers that default to `installed_bindir`/test-env bundle paths (not PATH), so helper-level override or installed-bin substitution is required for true driving once examples execute. `script/upstream-specs-celerite-override.rb` provides a best-effort override, **unvalidated** because no example reached bundle helper execution in this run.
- Therefore “real driving of Celerite by upstream lockfile specs” is **partially prepared but not yet demonstrated**.

### Follow-up to reach executed compatibility evidence

1. Bootstrap or faithfully emulate upstream spec fixture environment on Windows (pristine/system gems, `build_repo1/2` artifacts, compact_index/vendor deps) so around/before hooks complete.
2. Re-run with helper override / installed-bin alignment and verify `bundle` helper invocations exec celerite (`CELERITE_BIN`).
3. Capture per-example pass/fail/error and split into harness-precondition vs real compatibility gap vs pass.
4. Validate `script/upstream-specs` end-to-end on the target Windows shell/CI environment.

## Not applicable items (with cause)

| Suite | Cause |
|---|---|
| `spec/resolver/*` | drives Ruby `Gem::Resolver::SpecSet` internals; Celerite resolves via native PubGrub with its own spec model. Behavioral parity is covered by our differential fixtures instead. |
| `spec/runtime/*` | requires `Bundler.setup` inside real Ruby processes (bridge M5+ scope; Celerite provides the environment contract, not the Ruby runtime). |
| `spec/plugins/*` | plugin hooks execute Ruby plugin code through the bridge; specs assert Ruby-side `Bundler::Plugin` API objects. Native command dispatch is covered by `plugin list/install` specs we add. |
| `spec/realworld/*` | network-dependent by design. |
| `spec/quality_*` | lint the Ruby Bundler codebase itself. |
