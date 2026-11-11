# Differential 4.0.24 run — 2026-11-11 (task-2 local verification)

## Provenance

- Code under test: `ec4680792cfe01e7247f95e22f13fb80a184bf0a` plus this
  change's git-source listing/path alignment (short revision in human-readable
  output and forward-slash paths). It includes the earlier `SolveFailure`
  fix (Ruby/RubyGems-metadata-only candidates exit 6; genuinely missing
  versions exit 7), path/multi-group fixtures, and Ruby/RubyGems
  candidate-filter/runtime-validation work.
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
crystal spec <107-example M7 + base subset>    # 107 examples, 0 failures, EXIT 0
crystal spec spec/cli_spec.cr --link-flags "<shim.o>"   # 24 examples, 0 failures, EXIT 0
crystal spec spec/m7_installed_discovery_spec.cr spec/m7_platform_spec.cr \
  --link-flags "<shim.o>"                     # 22 examples, 0 failures, EXIT 0

TMPDIR=/c/temp CELERITE_BIN="$PWD/bin/celerite.exe" \
  bash script/differential ruby-version-mismatch platform-ruby-mismatch \
  ruby-engine-mismatch ruby-patchlevel-mismatch check-missing check-unresolved \
  list-missing show-missing list-multi-group check-path list-path \
  no-matching-version platform-variant-fail ruby-metadata-fail \
  git-installed-discovery install-check show-info-installed
# 17 passed, 0 failed, 0 skipped, EXIT 0

TMPDIR=/c/temp CELERITE_BIN="$PWD/bin/celerite.exe" bash script/differential
# 95 passed, 14 failed, 0 skipped, EXIT 1
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
- `ruby-engine-mismatch` (`ruby "4.0.6", engine: "jruby",
  engine_version: "9.4.0.0"`, `check`): both exit 18 with the "Your Ruby
  engine is ruby, but your Gemfile specified jruby" diagnostic — **PASS**.
- `ruby-patchlevel-mismatch` (`ruby "4.0.6", patchlevel: "1"`, `check`): both
  exit 18 with the patchlevel diagnostic — **PASS**. This exercises the
  Gemfile target Ruby options preserved through the bridge evaluation.
- `install-check` (local compact-index `json_pure`, `install`, `check`): both
  exit 0 and the installed `gems`/`specifications` trees match — **PASS**.
  This pins the post-install recheck path.
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

- The 17 targeted fixtures (`ruby-version-mismatch`, `ruby-engine-mismatch`,
  `ruby-patchlevel-mismatch`, `platform-ruby-mismatch`, `list-multi-group`,
  `check-path`, `list-path`, `no-matching-version`, `platform-variant-fail`,
  `ruby-metadata-fail`, `git-installed-discovery`, `install-check`,
  `show-info-installed`, and the four check/list/show fixtures) all passed; the 14 failures above are
  outside the M7(1)-(3) paths
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
- 2.7.2 profile was not re-run in this verification.
- The M7(1) full matrix (engine/patchlevel/ABI/Gemfile target, install
  re-check), more M7(2) path/Git combinations and additional platform
  variants, and M7(3) broader differential evidence remain incomplete.
