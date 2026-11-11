# Differential 4.0.24 run — 2026-11-11 (task-2 local verification)

## Provenance

- Code under test: `f549de3` plus this change: adds differential fixture
  `rubygems-metadata-match` (PATH gem with `required_rubygems_version = ">= 0"`,
  `lock --print`, exit 0) as the positive counterpart to
  `rubygems-metadata-fail`, verifying RubyGems metadata constraints accept a
  satisfied requirement on 4.0.24/2.7.2. It builds on
  `0f78548`/`9d8426e`/`f6a4413`/`5a5310b`/`f549de3` M7(1)/(2) work: positive
  ruby-target fixtures, patchlevel-unlock and ruby-nolock `check`/`list`
  re-resolve notice parity, SolveFailure exit 6 vs GemNotFound exit 7,
  path/multi-group fixtures, fund PATH/GIT metadata, and Ruby/RubyGems
  candidate-filter/runtime-validation.
- Binary: `bin/celerite.exe` rebuilt locally with an **uncommitted,
  out-of-repo OpenSSL shim** (see below); `--version` prints `0.1.0`.
- `bin/` is gitignored. Neither the shim nor the binary is part of the
  repository.
- Stock `crystal build src/cli.cr` still fails on this host with
  `undefined reference to 'EVP_MD_size'`; the shim only works around that
  local toolchain mismatch (Crystal 1.22.1 binds OpenSSL 1.1
  `EVP_MD_size`, MSYS2 ucrt64 ships OpenSSL 3.6.5, which exports
  `EVP_MD_get_size`).

## Commands and results

```sh
crystal tool format --check src spec          # EXIT 0
crystal build --no-codegen src/cli.cr         # EXIT 0 (2 pre-existing deprecation warnings)
crystal spec <111-example M7 + base subset>    # 111 examples, 0 failures, EXIT 0
crystal spec spec/cli_spec.cr --link-flags "<shim.o>"   # 24 examples, 0 failures, EXIT 0
crystal spec spec/m7_installed_discovery_spec.cr spec/m7_platform_spec.cr \
  --link-flags "<shim.o>"                     # 22 examples, 0 failures, EXIT 0

TMPDIR=/c/temp CELERITE_BIN="$PWD/bin/celerite.exe" \
  bash script/differential ruby-version-mismatch platform-ruby-mismatch \
  ruby-engine-mismatch ruby-engine-version-mismatch ruby-patchlevel-mismatch \
  ruby-metadata-fail rubygems-metadata-fail rubygems-metadata-match \
  no-matching-version platform-variant-fail install-check check-missing \
  check-unresolved list-missing show-missing list-multi-group check-path \
  list-path git-installed-discovery show-info-installed fund-path \
  ruby-target-match ruby-patchlevel-match ruby-engine-match \
  ruby-patchlevel-match-list check-missing-ruby-nolock \
  list-missing-ruby-nolock
# 27 passed, 0 failed, 0 skipped, EXIT 0

TMPDIR=/c/temp CELERITE_BIN="$PWD/bin/celerite.exe" \
  BUNDLER_REF_VERSION=2.7.2 bash script/differential ruby-version-mismatch \
  platform-ruby-mismatch ruby-engine-mismatch ruby-engine-version-mismatch \
  ruby-patchlevel-mismatch ruby-metadata-fail rubygems-metadata-fail \
  rubygems-metadata-match no-matching-version platform-variant-fail \
  install-check check-missing check-unresolved list-missing show-missing \
  list-multi-group check-path list-path git-installed-discovery \
  show-info-installed fund-path ruby-target-match ruby-patchlevel-match \
  ruby-engine-match ruby-patchlevel-match-list check-missing-ruby-nolock \
  list-missing-ruby-nolock
# 27 passed, 0 failed, 0 skipped, EXIT 0

TMPDIR=/c/temp CELERITE_BIN="$PWD/bin/celerite.exe" bash script/differential
# 101 passed, 14 failed, 0 skipped, EXIT 1
```

The full run above was streamed to the terminal; the failure list below is the
durable record. On this host `diff`/`cmp` are taken from
`C:\Program Files\Git\usr\bin` and `TMPDIR=/c/temp` is used so the MSYS path
is visible to those tools; this is a test-environment workaround, not a
product change.

## The 14 failures (classified)

### A. `make` not available in the test environment — 7 failures

`make failedNo such file or directory - make` while building `racc-1.8.1`
native extension; the reference run had a working `make`.

| Fixture | Secondary difference |
|---|---|
| `add-group` (`add racc --group dev`) | celerite exit 1 vs reference 0; extension build error |
| `add-optimistic` (`add racc --optimistic`) | celerite exit 1 vs reference 0; extension build error |
| `add-remove` (`install`, `add racc`, `remove racc`) | celerite exit 1; additionally stdout `racc (~> 1.8) was removed.` vs `racc was removed.` (secondary to failed add) |
| `add-version` (`add racc --version=1.8.1`) | celerite exit 1 vs reference 0; extension build error |
| `cache-all-platforms` (`cache --all-platforms`) | celerite exit 1 vs reference 0; extension build error |
| `native-ext` (`install`, `exec ruby inline.rb`) | celerite exit 1 vs reference 0; extension build error |
| `native-ext-target` (`install --target-rbconfig=rbconfig.rb`, `exec ruby inline.rb`) | celerite exit 1 vs reference 0; extension build error |

### B. Binstub `.bat` / `loader` content differs after normalization — 7 failures

No exit-code difference in these fixtures; `installed-tree` comparison reports
generated Windows binstub content differences.

| Fixture | Difference |
|---|---|
| `binstubs` (`install`, `binstubs thor`) | `ruby/4.0.0/bin/thor.bat` content differs |
| `exec-loader` (`install`, `exec loader one,comma,space`) | `ruby/4.0.0/bin/loader` and `loader.bat` content differ |
| `install-force` (`install --force`) | `ruby/4.0.0/bin/thor.bat` content differs |
| `install-fresh` (`install`) | `ruby/4.0.0/bin/thor.bat` content differs |
| `install-rerun` (`install`) | `ruby/4.0.0/bin/thor.bat` content differs |
| `pristine` (`install`, `pristine`) | `ruby/4.0.0/bin/thor.bat` content differs |
| `pristine-named` (`install`, `pristine thor`, `pristine nonexistentgem`) | `ruby/4.0.0/bin/thor.bat` content differs |

## M7(1) constraint fixtures added in this pass

- `no-matching-version` (`lock --print`, `json_pure >= 99.0` against the local
  compact index): reference and Celerite both exit 7 with a "Could not find"
  error — **PASS**.
- `platform-variant-fail` (`lock --add-platform x86_64-linux` with `racc` +
  `nokogiri`): both exit 7 — **PASS** (regression confirmation for the
  platform/ABI variant path).
- `ruby-metadata-fail` (`lock --print` with a PATH gem whose
  `required_ruby_version = ">= 99.0"`): both exit 6 — **PASS** after the
  resolver fix. Celerite now emits the same `Could not find compatible
  versions` / "Because every version of future_gem depends on Ruby >= 99.0"
  explanation as Bundler 4.0.24. The distinction is preserved: a requirement
  with no matching version at all (for example `no-matching-version`) still
  exits 7 with `GemNotFound`.
- `rubygems-metadata-fail` (`lock --print` with a PATH gem whose
  `required_rubygems_version = ">= 99.0"`): both exit 6 — **PASS**. This pins
  the RubyGems-metadata-only exclusion path with the same SolveFailure
  semantics as the Ruby-metadata case.
- `ruby-engine-mismatch` (`ruby "4.0.6", engine: "jruby",
  engine_version: "9.4.0.0"`, `check`): both exit 18 with the "Your Ruby
  engine is ruby, but your Gemfile specified jruby" diagnostic — **PASS**.
- `ruby-engine-version-mismatch` (`ruby "4.0.6", engine: "jruby",
  engine_version: "9.3.0.0"`, `check`): both exit 18 with the "Your jruby
  version is 9.4.0.0, but your Gemfile specified jruby 9.3.0.0" diagnostic —
  **PASS**. This pins the structured Gemfile `engine_version` option through
  the bridge evaluation and the runtime mismatch message.
- `ruby-patchlevel-mismatch` (`ruby "4.0.6", patchlevel: "1"`, `check`): both
  exit 18 with the patchlevel diagnostic — **PASS**. This exercises the
  Gemfile target Ruby options preserved through the bridge evaluation.
- `install-check` (local compact-index `json_pure`, `install`, `check`): both
  exit 0 and the installed `gems`/`specifications` trees match — **PASS**.
  This pins the post-install recheck path.
- `ruby-target-match` (`ruby "4.0.6"`, `install` + `check`), `ruby-engine-match`
  (`ruby "4.0.6", engine: "ruby", engine_version: "4.0.6"`, `install` +
  `check`), and `ruby-patchlevel-match` (`ruby "4.0.6", patchlevel: "0"`,
  `install` + `check`): all exit 0 on both profiles — **PASS**. These pin the
  positive/matching side of the Gemfile target Ruby matrix. The patchlevel
  case also pins the reference quirk that an explicit Gemfile patchlevel the
  lockfile RUBY VERSION string does not preserve makes Bundler re-resolve on
  `check` and print `Resolving dependencies...` (`definition.rb`
  `@unlocking_ruby`); `Commands.check` mirrors that notification via
  `lock_ruby_declaration_mismatch?` before reporting satisfaction, while still
  using the lockfile.
- `show-info-installed` (local compact-index `json_pure`, `install`, `show
  json_pure`, `info json_pure`): both exit 0 — **PASS**. This pins the 4.0.24
  read-only formats: `show <gem>` prints only the installed path, and `info
  <gem>` prints tab-indented Summary/Homepage/Documentation/Source
  Code/Wiki/Changelog/Bug Tracker/Path in reference order (metadata URIs from
  the installed gemspec).
- `git-installed-discovery` (local `:git` source): `install`, `check`, `list`,
  `show --paths gitgem`, `info --version gitgem` all match Bundler 4.0.24 —
  **PASS**. This pins git-source discovery after a real install, the short
  revision in human-readable listings (`gitgem (0.2.0 f967e49)`), and
  forward-slash path rendering on Windows.

## Interpretation

- The 26 targeted fixtures (`ruby-version-mismatch`, `ruby-engine-mismatch`,
  `ruby-engine-version-mismatch`, `ruby-patchlevel-mismatch`,
  `platform-ruby-mismatch`, `list-multi-group`,
  `check-path`, `list-path`, `no-matching-version`, `platform-variant-fail`,
  `ruby-metadata-fail`, `rubygems-metadata-fail`, `git-installed-discovery`,
  `install-check`, `show-info-installed`, `fund-path`, `ruby-target-match`,
  `ruby-patchlevel-match`, `ruby-engine-match`, `ruby-patchlevel-match-list`,
  `check-missing-ruby-nolock`, `list-missing-ruby-nolock`, and the four
  check/list/show fixtures) all passed on 4.0.24 and 2.7.2; the 14 failures in
  the full 4.0.24 run above are outside the M7(1)-(3) paths
  (native-extension tooling and generated binstub byte content), but the suite
  is **not green** and these failures are not claimed as fixed.
- `list-path` also pins the 4.0.24 human-readable `bundle list` format for a
  PATH source (header + `  * example (1.0.0)` + `bundle info` hint); the
  previous Celerite default printed only `example-1.0.0`. `cli_spec.cr` and
  `m7_installed_discovery_spec.cr` were updated to the same format.
- `show-info-installed` pins the 4.0.24 read-only formats: `show <gem>` prints
  only the installed path, and `info <gem>` prints tab-indented metadata fields
  in reference order. `show <gem>` no longer prints the old Celerite detail
  block; `info <gem>` now omits `Default Gem` unless the gem is actually a
  default gem and adds the metadata URI fields.
- `fund-path` pins the PATH-source funding metadata path: a PATH gem whose
  gemspec contains `s.metadata = { "funding_uri" => ... }` is reported as
  `* example (1.0.0)` / `  Funding: https://example.com/path-funding`, not as
  the fixed no-funding response. `read_funding_uri` now checks PATH/GIT source
  gemspecs before the installed RubyGems tree.
- The same 26 targeted fixtures also passed on the 2.7.2 profile
  (26 passed, 0 failed, 0 skipped, exit 0). The full 2.7.2 suite was not
  re-run in this verification.
- The M7(1) positive matrix (matching version/patchlevel/engine/
  engine_version) and patchlevel-unlock `check`/`list` notification parity are
  covered; `check-missing-ruby-nolock` and `list-missing-ruby-nolock` pin the
  case where Gemfile declares `ruby` but the lock has no `RUBY VERSION` and
  locked gems are not installed (4.0.24/2.7.2 PASS, exit 1 with
  `Resolving dependencies...`). `rubygems-metadata-match` pins satisfied
  `required_rubygems_version` (PATH gem, lock --print, exit 0) as the positive
  counterpart to `rubygems-metadata-fail`. Manual harness-style evidence
  (isolated env, preinstalled `json_pure-2.8.1` gem+gemspec under
  `BUNDLE_PATH/ruby/4.0.0`, Gemfile declares `ruby "4.0.6"`, lock has
  specs/PLATFORMS/DEPENDENCIES/BUNDLED WITH but no `RUBY VERSION`) shows
  reference Bundler 4.0.24 and 2.7.2 print `Resolving dependencies...` for both
  `check` and `list` when dependencies are satisfied (EXIT 0); with
  `CELERITE_REFERENCE_BUNDLER_LIB`/`CELERITE_PROFILE_BUNDLER_VERSION` set (as
  in `script/differential`), shim-built celerite reproduced the same
  `Resolving dependencies...` + satisfied/listing output for both commands
  (harness-like probe, `C:\temp\nolock-sat-harnesslike-eZPd5c`, 2026-11-11).
  This satisfied ruby-nolock case is **not yet differential-fixture-pinned**:
  `script/differential` provides `extra/` (copied into project) and
  `installed-tree` comparison but has no mechanism to seed `BUNDLE_PATH` before
  command execution; a `install` step would typically add `RUBY VERSION` to the
  lock, changing the scenario. Blocker: no harness primitive to pre-populate a
  satisfied bundle state with lock lacking RUBY VERSION while preserving that
  lock. Reproduction (reference): create isolated project with above Gemfile/lock
  and preinstalled gem/spec in `BUNDLE_PATH`, run
  `HOME=... GEM_HOME=BUNDLE_PATH GEM_PATH=BUNDLE_PATH BUNDLE_PATH=... RUBYOPT=`
  `ruby -I <bundler-4.0.24/lib> <bundle> check|list` → both print
  `Resolving dependencies...` then succeed. Bridge unavailable remains
  best-effort/fail-safe (notice may be omitted). Remaining gaps: satisfied
  nolock differential fixture/harness support, ABI/platform positive variants,
  `show`/`info` other re-resolve notification scenarios, more M7(2) path/Git
  combinations and additional platform variants, and M7(3) broader differential
  evidence.
