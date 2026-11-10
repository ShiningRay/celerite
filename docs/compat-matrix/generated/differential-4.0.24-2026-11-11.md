# Differential 4.0.24 run — 2026-11-11 (task-2 local verification)

## Provenance

- Code under test: `066a646` plus the local task-2 differential fixtures
  (`no-matching-version`, `ruby-metadata-fail` with its documented deferral,
  and the earlier path/multi-group fixtures). The source changes include the
  4.0.24 `bundle list` human-output format, multi-group parsing, and the
  Ruby/RubyGems candidate-filter/runtime-validation work.
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
crystal spec <103-example M7 + base subset>    # 103 examples, 0 failures, EXIT 0
crystal spec spec/cli_spec.cr --link-flags "<shim.o>"   # 24 examples, 0 failures, EXIT 0
crystal spec spec/m7_installed_discovery_spec.cr spec/m7_platform_spec.cr \
  --link-flags "<shim.o>"                     # 21 examples, 0 failures, EXIT 0

TMPDIR=/c/temp CELERITE_BIN="$PWD/bin/celerite.exe" \
  bash script/differential ruby-version-mismatch platform-ruby-mismatch \
  check-missing check-unresolved list-missing show-missing list-multi-group \
  check-path list-path no-matching-version platform-variant-fail ruby-metadata-fail
# 11 passed, 0 failed, 1 skipped (documented deferral), EXIT 0

TMPDIR=/c/temp CELERITE_BIN="$PWD/bin/celerite.exe" bash script/differential
# 89 passed, 14 failed, 1 skipped (documented deferral), EXIT 1
```

Full local log: `C:\temp\celerite-diff-full-3.log` (temporary; the failure
list below is the durable record). On this host `diff`/`cmp` are taken from
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
  `required_ruby_version = ">= 99.0"`): **deferred** for 4.0.24. Reference
  exits 6 with the PubGrub explanation ("Because every version of future_gem
  depends on Ruby >= 99.0 ... version solving has failed."), while Celerite
  exits 7 with `GemNotFoundError` listing the source candidates. This is a
  real error-semantics gap in the Ruby-incompatible-only candidate path, not a
  harness issue; the fixture is committed with an explicit deferral so the
  suite stays honest. Removing the deferral requires the resolver to report a
  solve failure (exit 6) for this case.

## Interpretation

- The M7 fixtures (`ruby-version-mismatch`, `platform-ruby-mismatch`,
  `list-multi-group`, `check-path`, `list-path`) and the four check/list/show
  fixtures passed; the 14 failures above are outside the M7(1)-(3) paths
  (native-extension tooling and generated binstub byte content), but the suite
  is **not green** and these failures are not claimed as fixed.
- `list-path` also pins the 4.0.24 human-readable `bundle list` format for a
  PATH source (header + `  * example (1.0.0)` + `bundle info` hint); the
  previous Celerite default printed only `example-1.0.0`. `cli_spec.cr` and
  `m7_installed_discovery_spec.cr` were updated to the same format.
- 2.7.2 profile was not re-run in this verification.
- The M7(1) full matrix (engine/patchlevel/ABI/Gemfile target, install
  re-check), more M7(2) path/Git combinations and additional platform
  variants, and M7(3) broader differential evidence remain incomplete.
