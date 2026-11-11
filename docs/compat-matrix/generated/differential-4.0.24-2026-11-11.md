# Differential 4.0.24/2.7.2 run — 2026-11-12 (task-2 local verification, M7(1) boundary metadata)

## Provenance

- Code under test: working tree on top of `24eef35` (HEAD, `main`,
  `origin/main`) plus uncommitted WIP for this subtask: add differential
  fixtures `ruby-metadata-boundary-match` (PATH gem with
  `required_ruby_version = ">= 4.0.6"`, equal to runtime Ruby 4.0.6,
  `lock --print`, exit 0) and `rubygems-metadata-boundary-match` (PATH gem with
  `required_rubygems_version = ">= 4.0.16"`, equal to runtime RubyGems 4.0.16,
  `lock --print`, exit 0) as positive/boundary counterparts to
  `ruby-metadata-fail`/`rubygems-metadata-fail` and
  `ruby-metadata-match`/`rubygems-metadata-match`, and sync this evidence doc
  and `docs/roadmap.md` with the actual measured results below. Builds on
  `0f78548`/`9d8426e`/`f6a4413`/`5a5310b`/`f549de3` M7(1)/(2) work: positive
  ruby-target fixtures, patchlevel-unlock and ruby-nolock `check`/`list`
  re-resolve notice parity, SolveFailure exit 6 vs GemNotFound exit 7,
  path/multi-group fixtures, fund PATH/GIT metadata, and Ruby/RubyGems
  candidate-filter/runtime-validation.
- Binary: `bin/celerite.exe` rebuilt locally in this run with an **uncommitted,
  out-of-repo OpenSSL shim** (see below); `--version` prints `0.1.0`.
- `bin/` is gitignored. Neither the shim nor the binary is part of the
  repository.
- Stock `crystal build src/cli.cr` still fails on this host with
  `undefined reference to 'EVP_MD_size'`; the shim only works around that
  local toolchain mismatch (Crystal 1.22.1 binds OpenSSL 1.1
  `EVP_MD_size`, MSYS2 ucrt64 ships OpenSSL 3.6.5, which exports
  `EVP_MD_get_size`). Not a product fix.

## Environment (2026-11-12 02:27 CST, task-2 subitem verification)

- Host: Windows, PowerShell; `C:\temp` exists.
- PATH prefix used for Crystal/Bundler/differential runs:
  `C:\Program Files\Git\usr\bin;C:\Program Files\Git\cmd;C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin`
  (ensures `git/diff/cmp/ruby/crystal/gcc` as needed; `TMPDIR=/c/temp` for
  MSYS-visible temp paths).
- Crystal `1.22.1 [23828b0a40] (2026-10-23)`, LLVM 23.1.3, default target
  `x86_64-w64-windows-gnu`.
- Ruby `ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [x64-mingw-ucrt]`;
  `ruby -e "puts RUBY_VERSION; puts RUBY_PATCHLEVEL; puts Gem::VERSION"` ->
  `4.0.6`, `0`, `4.0.16` (EXIT 0). Boundary fixtures use these runtime values.
- `bundle _4.0.24_ -v` -> `4.0.24`; `bundle _2.7.2_ -v` -> `Bundler version 2.7.2`.
- Shim (out-of-repo, not committed): `C:\Users\ShiningRay\AppData\Local\Temp\celerite-shim-m7wip\evp_md_size_shim.c`
  declares `int EVP_MD_get_size(const void *md);` and defines
  `int EVP_MD_size(const void *md) { return EVP_MD_get_size(md); }`.
  `gcc -c ... -o evp_md_size_shim.o` -> GCC_EXIT 0; `nm` shows
  `U EVP_MD_get_size` and `T EVP_MD_size`.
- `crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`
  -> BUILD_EXIT 0 (warnings: `src\celerite\cli\commands_install.cr:567:43` and
  `:631:20` `Deprecated File.executable?`), `bin/celerite.exe --version` ->
  `0.1.0` (VER_EXIT 0), mtime `2026-11-12 02:27:58`, size 9959936. `bin/`
  gitignored.

## Baseline checks (PASS)

```sh
cd C:\Users\ShiningRay\projects\ShiningRay\celerite
PATH="C:\Program Files\Git\usr\bin;C:\Program Files\Git\cmd;C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;$PATH"
crystal tool format --check src spec   # FORMAT_EXIT=0
crystal build --no-codegen src/cli.cr  # NOCODEGEN_EXIT=0 (2 deprecation warnings in src\celerite\cli\commands_install.cr:567:43,631:20)
git diff --check                       # DIFFCHECK_EXIT=0 (after doc/fixture updates, before commit)
```

## Spec subset (PASS)

```sh
crystal spec spec/ruby_version_spec.cr spec/m7_ruby_runtime_spec.cr \
  spec/m7_ruby_constraints_spec.cr spec/m7_resolver_ruby_constraints_spec.cr \
  spec/m7_platform_spec.cr
# 39 examples, 0 failures, 0 errors, 0 pending
# Finished in 593.09 milliseconds
# SPEC_EXIT=0
```

## Differential (shim-built `bin/celerite.exe`, `TMPDIR=/c/temp`)

### Boundary-match pair (new fixtures), Bundler 4.0.24

```sh
CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp \
  bash script/differential ruby-metadata-boundary-match rubygems-metadata-boundary-match
```

- `PASS ruby-metadata-boundary-match (exit=0)`
- `PASS rubygems-metadata-boundary-match (exit=0)`
- `differential (4.0.24): 2 passed, 0 failed, 0 skipped (documented deferrals)`
- RC=0

### Boundary-match pair (new fixtures), Bundler 2.7.2

```sh
BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp \
  bash script/differential ruby-metadata-boundary-match rubygems-metadata-boundary-match
```

- `PASS ruby-metadata-boundary-match (exit=0)`
- `PASS rubygems-metadata-boundary-match (exit=0)`
- `differential (2.7.2): 2 passed, 0 failed, 0 skipped (documented deferrals)`
- RC=0

### Targeted 30-fixture set, Bundler 4.0.24 (PASS)

Fixtures (30): `ruby-version-mismatch`, `platform-ruby-mismatch`,
`ruby-engine-mismatch`, `ruby-engine-version-mismatch`,
`ruby-patchlevel-mismatch`, `ruby-metadata-fail`, `ruby-metadata-match`,
`ruby-metadata-boundary-match`, `rubygems-metadata-fail`,
`rubygems-metadata-match`, `rubygems-metadata-boundary-match`,
`no-matching-version`, `platform-variant-fail`, `install-check`,
`check-missing`, `check-unresolved`, `list-missing`, `show-missing`,
`list-multi-group`, `check-path`, `list-path`, `git-installed-discovery`,
`show-info-installed`, `fund-path`, `ruby-target-match`, `ruby-patchlevel-match`,
`ruby-engine-match`, `ruby-patchlevel-match-list`,
`check-missing-ruby-nolock`, `list-missing-ruby-nolock`.

Per-case results (in run order): `PASS ruby-version-mismatch (exit=18)`,
`PASS platform-ruby-mismatch (exit=0)`, `PASS ruby-engine-mismatch (exit=18)`,
`PASS ruby-engine-version-mismatch (exit=18)`,
`PASS ruby-patchlevel-mismatch (exit=18)`, `PASS ruby-metadata-fail (exit=6)`,
`PASS ruby-metadata-match (exit=0)`,
`PASS ruby-metadata-boundary-match (exit=0)`,
`PASS rubygems-metadata-fail (exit=6)`, `PASS rubygems-metadata-match (exit=0)`,
`PASS rubygems-metadata-boundary-match (exit=0)`,
`PASS no-matching-version (exit=7)`, `PASS platform-variant-fail (exit=7)`,
`PASS install-check (exit=0)`, `PASS check-missing (exit=1)`,
`PASS check-unresolved (exit=1)`, `PASS list-missing (exit=1)`,
`PASS show-missing (exit=7)`, `PASS list-multi-group (exit=0)`,
`PASS check-path (exit=0)`, `PASS list-path (exit=0)`,
`PASS git-installed-discovery (exit=0)`, `PASS show-info-installed (exit=0)`,
`PASS fund-path (exit=0)`, `PASS ruby-target-match (exit=0)`,
`PASS ruby-patchlevel-match (exit=0)`, `PASS ruby-engine-match (exit=0)`,
`PASS ruby-patchlevel-match-list (exit=0)`,
`PASS check-missing-ruby-nolock (exit=1)`,
`PASS list-missing-ruby-nolock (exit=1)`.

Summary: `differential (4.0.24): 30 passed, 0 failed, 0 skipped (documented deferrals)`, RC30_4024=0.

### Targeted 30-fixture set, Bundler 2.7.2 (PASS)

Same 30 fixtures and run order as 4.0.24.

Per-case results: `PASS ruby-version-mismatch (exit=18)`,
`PASS platform-ruby-mismatch (exit=0)`, `PASS ruby-engine-mismatch (exit=18)`,
`PASS ruby-engine-version-mismatch (exit=18)`,
`PASS ruby-patchlevel-mismatch (exit=18)`, `PASS ruby-metadata-fail (exit=6)`,
`PASS ruby-metadata-match (exit=0)`,
`PASS ruby-metadata-boundary-match (exit=0)`,
`PASS rubygems-metadata-fail (exit=6)`, `PASS rubygems-metadata-match (exit=0)`,
`PASS rubygems-metadata-boundary-match (exit=0)`,
`PASS no-matching-version (exit=7)`, `PASS platform-variant-fail (exit=7)`,
`PASS install-check (exit=0)`, `PASS check-missing (exit=1)`,
`PASS check-unresolved (exit=1)`, `PASS list-missing (exit=1)`,
`PASS show-missing (exit=7)`, `PASS list-multi-group (exit=0)`,
`PASS check-path (exit=0)`, `PASS list-path (exit=0)`,
`PASS git-installed-discovery (exit=0)`, `PASS show-info-installed (exit=0)`,
`PASS fund-path (exit=0)`, `PASS ruby-target-match (exit=0)`,
`PASS ruby-patchlevel-match (exit=0)`, `PASS ruby-engine-match (exit=0)`,
`PASS ruby-patchlevel-match-list (exit=0)`,
`PASS check-missing-ruby-nolock (exit=1)`,
`PASS list-missing-ruby-nolock (exit=1)`.

Summary: `differential (2.7.2): 30 passed, 0 failed, 0 skipped (documented deferrals)`, RC30_272=0.

## Interpretation (this subitem scope)

- Added fixtures `ruby-metadata-boundary-match` (`lock --print`, PATH gem with
  `spec.required_ruby_version = ">= 4.0.6"` equal to runtime Ruby 4.0.6) and
  `rubygems-metadata-boundary-match` (`lock --print`, PATH gem with
  `spec.required_rubygems_version = ">= 4.0.16"` equal to runtime RubyGems
  4.0.16) as positive/boundary counterparts to existing fail/match fixtures;
  both PASS on 4.0.24 and 2.7.2 (exit 0).
- The targeted 30-fixture set above (including the two new boundary fixtures)
  passed in full on Bundler 4.0.24 and 2.7.2 in this verification. This does not
  assert full differential suite pass and does not close M7(1)-(3).

## Known blockers / not verified (as of this run)

- Stock `crystal build src/cli.cr` remains blocked on this host:
  `undefined reference to 'EVP_MD_size'` (Crystal 1.22.1 / MSYS2 ucrt64 OpenSSL
  3.6.5 mismatch). CLI/differential evidence here used a local shim-built binary
  (`bin/` and shim out-of-repo, not committed); shim is a local workaround, not
  a product fix.
- Bridge unavailable is not a pass condition for scenarios requiring reference
  bridge behavior.
- Full `script/differential` suite on 4.0.24 and 2.7.2 was **not** rerun in
  this subitem (only the boundary pair and targeted 30-fixture set were run).
- Prior full-run failures recorded in earlier evidence (native-extension tooling
  `make` unavailable in that environment; binstub `.bat`/`loader` content
  differences) were not re-verified in this subitem.
- `shard.lock` remains untracked (`??`) and is not part of this subitem.

(removed - replaced above with accurate subitem-scoped interpretation and blockers)
