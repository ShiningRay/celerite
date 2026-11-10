# Celerite compatibility report — M7 baseline snapshot (2026-11-10)

Generated for iteration 1 baseline alignment. Git evidence at time of this update:
`HEAD=8e91a2f` (`test(M7): add installed-tree fixtures for differential comparisons`)
was pushed to `origin/main` in this iteration; this documentation/script commit is
pending (see commit recorded in the iteration report). Environment: Ruby 4.0.6
x64-mingw-ucrt, Crystal 1.22.1, git 2.55.0.windows.3 (Windows x64, win32).

This file remains a **recorded snapshot** of prior evidence, not a new verification
run for this iteration. Differential (`script/differential`, both profiles),
upstream `script/upstream-specs` rspec, and full gate reruns were **not rerun**
in this iteration; all counts/results below must be read as unverified against the
current HEAD unless explicitly stated otherwise.

What prior snapshot results prove is **observable-behavior equivalence for the
enumerated fixtures after the harness's documented normalization** (exit codes,
stdout/stderr, project-relative file presence and explicitly selected file-content
probes). It is not a percentage of RubyGems or full Bundler compatibility.

Current normalization (as previously documented) includes sandbox paths,
dates/timestamps, sorting `Fetching` lines, removing selected environment-report
sections and Ruby backtrace lines. The general tree comparison is primarily
path-based; selected markers check content, but it is not a general byte-for-byte
comparison of the whole installed tree. M7 tightens these comparisons and records
every normalization rule (not yet complete).

## Differential evidence (prior snapshot, **unverified this iteration**)

| Bundler | Result |
|---|---|
| 4.0.24 | 97 passed, 0 failed (`script/differential` full suite) — **未重跑验证** |
| 2.7.2 | 96 passed, 0 failed, 1 skipped (`add-group`, documented deferral: the 2.7.2 reference auto-installs Bundler 4.0.24 from rubygems.org, which the offline sandbox cannot prove; `BUNDLER_REF_VERSION=2.7.2 script/differential`) — **未重跑验证** |

Prior mapping of those 97 fixtures to milestones (historical, not revalidated):

- **M0** (contract & differential harness): every lockfile-driven fixture is
  executed differentially — unresolved lockfile coverage (`check-*`,
  `list-missing`, `show-missing`, `issue-*`).
- **M1** (read-only commands): `version`, `platform`, `check`, `list`,
  `show`/`info`, `config get` fixtures.
- **M2** (index + PubGrub resolution): `lock-*`, `update-*`,
  `update-patch` (`--patch`/`--minor` ceilings), `update-strict` (`--strict`
  patch ceiling + `Bundler attempted to update ... stayed the same` report),
  `update-source` (`--source <name>` named-source filter; unknown name unlocks
  nothing), `update-ruby` (`--ruby` rewrite),
  `multi-platform-lock`, `platform-variant-fail`, `cooldown`,
  `cooldown-flag`, `cooldown-source` (HTTP v2 `created_at`, 4.0.24-only;
  2.7.2 rejects `--cooldown` with `Unknown switches "--cooldown"`), `lock-bundler-bare`
  (bare `--bundler` no-op in the pinned fixture source).
- **M3** (install/cache/runtime): `install-fresh`, `install-rerun`,
  `install-standalone`, `install-frozen` (flag rejection per profile),
  `install-flag-frozen` (`--force/--local/--prefer-local/--no-lock/--trust-policy`),
  `install-local` (`--local` local-installed-gems rejection, exit 7),
  `cache-path` (`--cache-path` + 2.7.x remembered config),
  `cache-all-platforms` (`--all-platforms` copy of all platform variants +
  4.x re-fetch line, 2.7.x `BUNDLE_CACHE_ALL` remembered config),
  `lock-normalize` (`--normalize-platforms` rewrite ordering),
  `binstubs-flags`, `binstubs-shebang`, `binstubs-shebang-line` (`--shebang`
  first-line content proof via harness `first-line` marker, incl. 2.7.x remembered `shebang` config),
  `pristine(-named)`, `git-pristine`, `clean-unused`, `clean-force`, `native-ext`,
  `native-ext-target`,
  `ruby-api`, `bundler-inline`, `exec-missing` (105-127 evidence),
  `exec-loader`, `exec-loader-disabled`, `exec-thor-version`
  (directly loadable Ruby scripts via the `Kernel.load` runtime adapter;
  `disable_exec_load` bypasses it; PATH/GIT source binstubs materialized),
  `bundler-fallback` (PATH fallback for `bundler-<>` commands).
- **M4** (all sources, platforms, extensions): `git-path-install`,
  `multi-platform-lock`, `platform`, `platform-install` (nokogiri
  platform-variant rejection, exit 7 both profiles), `native-ext`,
  `pristine-named`.
- **M5** (partial CLI/plugins/Ruby API coverage): `plugin-install`, `plugin-uninstall`,
  `plugin-source` (remote source resolution failure path on HTTP, exit 7),
  `plugin-source-ok` (remote `--source` success: `Fetching`/`Installing`
  output + plugin-tree materialization `gems/` `specifications/` `cache/`
  + `extensions/` `doc/` `build_info/` `plugins/` dirs and index),
  `plugin-git-local`, `plugin-git-local2` (git `--branch` local plugin, incl.
  `plugins.rb`-root malformatted 29 exit),
  `add-group`, `binstubs-*`,
  `ruby-api`, `bundler-inline`, `init-fresh`, `outdated-list`,
  `outdated-parseable`, `outdated-parseable-current`, `outdated-filter-*`,
  `outdated-cooldown-http`, `outdated-cooldown-table`, `outdated-source`,
  `outdated-verbose`,
  `outdated-strict`, `outdated-update-strict`, `outdated-only-explicit`, `outdated-local`,
  `outdated-group`, `outdated-named`, `outdated-groups`, `add-source`, `scoped-source-lock`, config set/get/
  unset fixtures. `add` feature fixtures: `add-skip-install`, `add-version`,
  `add-strict`, `add-optimistic`, `add-require`, `add-path`, `add-git`, `add-ref`
  (Gemfile lines pinned by the harness `file-contains` content probe).
- **M6** (performance): see `docs/benchmarks/results-2026-11-09.md` and
  `docs/benchmarks/profile-results-2026-11-09.md` (raw numbers reproducible
  via `script/benchmark 3` and `script/profile`).

## Explicitly unsupported / untested (no false claims)

- `bundle exec`: on Unix the exec'd child is terminated when the parent
  receives SIGINT/SIGTERM (`Signal::INT/TERM` trap + `Process#terminate`,
  matching the Bundler trap-the-group semantics); on Windows the child shares
  the console since Crystal's `Signal` traps are unimplemented there.
- Directly loadable Ruby-script executables run through a `Kernel.load`
  runtime adapter (`exec-loader`, `exec-loader-disabled`, `exec-thor-version`
  dual-passed). The adapter sets `$0`/ARGV/process title, restores SIGINT to
  DEFAULT, and loads the script with `Kernel.load`; `disable_exec_load`
  bypasses it like the reference. This is a Ruby-process adapter rather than
  a literal native in-Crystal load, and script-level in-process state
  mutation is not otherwise claimed.
- Multi-process write-locking: install/update/pristine acquire an exclusive
  file lock on `<bundle_path>/bundler` (`ProcessLock`, stdlib `flock_exclusive`
  / Win32-equivalent), so concurrent runs serialize on the same path rather
  than corrupt it. `spec/process_lock_spec.cr` proves a second nonblocking
  holder is excluded until release, and `spec/process_race_spec.cr` proves a
  separate OS process holding the lock blocks the contender until it exits.
- `--cooldown` flag values are validated per Bundler (`Expected numeric value
  for '--cooldown'`, non-negative check), but `--cooldown` on `exec` or other
  non-applicable commands is not separately hardened; Gemfile per-source
  `cooldown:` is enforced for the primary remote only (multi-source fan-in
  across remotes is resolved by canonical source priority).
- `add --group` on Bundler 2.7.2 (`add-group` fixture) is deferred, not passed:
  the 2.7.2 reference auto-installs Bundler 4.0.24 from rubygems.org for the
  lockfile it was generated with, and the offline sandbox has no network.
  The 4.0.24 profile result for this fixture is green; the 2.7.2 path is
  documented rather than claimed.
- Install ordering: pure-Ruby gems install before native-extension gems
  (pinned `cache-all-platforms` probe); this order is pinned for fresh
  installs/updates.

## Additional known implementation gaps (M7, evidence-aligned)

- **Ruby/RubyGems 约束过滤（部分进展，未达 M7(1) 验收）**：`src/celerite/resolver/source.cr:265-277`
  中 `ResolutionSource#ruby_requirement_satisfied?` 已按 `spec.required_ruby_version` /
  `spec.required_rubygems_version` 对 `running_ruby_version`/`running_rubygems_version`
 （当前由 bridge 版本字段 `@bridge_ruby_version`/`@bridge_rubygems_version` 提供）
  执行 `satisfied_by?` 并在不满足时返回 `false`（非恒真）。但 M7(1) 仍未满足：
  需覆盖当前运行/目标 Ruby、engine、patchlevel、ABI、Gemfile 目标 Ruby 等完整约束，
  以及无匹配版本、平台变体与安装复核的正反例/差分证据；实现与验收仍待完成。
- `check` and `list` have locked/missing-gem fixture paths, not complete
  installed-gem discovery; `fund` currently prints a fixed no-funding response.
  The `gem` template and environment diagnostics also have partial implementations.
- Global `--retry` is stripped rather than executing the configured retry policy.
  Mirror, proxy, redirect, SSL and legacy/full-index configuration cannot be
  inferred to work merely because a config key is recognized.
- `--trust-policy` validates the policy name; that is not a claim of full RubyGems
  signature/certificate trust-policy enforcement.
- The Ruby runtime scenarios use the reference `bundler/setup`. They demonstrate
  compatibility through that boundary, not an independent lightweight runtime.
  Native extension builds and plugin hooks similarly remain Ruby operations.

The implementation order for these gaps and the subsequent performance work is
in [roadmap.md](roadmap.md): M7 correctness/evidence, M8 batch bridge and cache
hits, M9 native install plans/runtime, M10 optional in-process extension spike.

## Flag-level boundaries (25 Bundler flags audit)

These flags exist on the reference CLI but are not fully honored where noted;
each was checked against the reference `4.0.24` help/validation paths and is
documented instead of silently emulated:

| Flag | Status |
|---|---|
| `install --force` / `--redownload` | **Supported** — `install-force` differential-verified forced reinstall (Installed already-installed_specs) on both profiles. |
| `install --standalone[=GROUP]` | **Supported** — `install-standalone` differential (setup.rb byte parity) on both profiles. |
| `install --local/--prefer-local/--no-cache/--no-lock/--trust-policy/--target-rbconfig` | `--local`/`--prefer-local` local-gem rejection; `--no-lock` no-reuse; `--trust-policy` validation; `--target-rbconfig` **supported** (`native-ext-target` dual-passed; bridge passes the target rbconfig to `Gem.set_target_rbconfig` before `Gem::Ext::Builder`). |
| `lock --add-checksums` | **Supported** — differential-covered on both profiles. |
| `lock --normalize-platforms` | **Supported** — `lock-normalize` differential dual-passed. |
| `lock --bundler[=VERSION]` | **Unsupported** — documented; bare form does not re-lock without update. |
| `update --bundler[=VERSION]` | **Unsupported** — requires network version fetch; offline probes exit 17. |
| `update --major/--minor/--patch/--strict/--ruby/--group/--source` | **Supported** — `--patch/--minor/--major` candidate ceiling (`update-patch` dual-passed); `--strict` patch ceiling + stayed-same report (`update-strict` dual-passed); `--source <name>` named-source filter, unknown name unlocks nothing (`update-source` dual-passed); `--ruby` ruby-rewrite + group-limit (`update-ruby` dual-passed). |
| `outdated --local/--source/--filter-strict/--update-strict/--porcelain/--group/--groups/--filter-*` | **Partial** — `--parseable`/`--porcelain` (`outdated-parseable`, dual-passed), `--filter-major/minor/patch` (`outdated-filter-*`), `--strict`/`--filter-strict` (`outdated-strict`), `--only-explicit` (`outdated-only-explicit`), `--local` cache candidates (`outdated-local`), `--group` (`outdated-group`), `--groups` (`outdated-groups`), `--update-strict` (accepted with no additional cap in `outdated`; `outdated-update-strict`), `--cooldown` annotation (`outdated-cooldown-http` parseable + `outdated-cooldown-table` table; 2.7.2 rejects the flag), `--source` candidate-index selection (`outdated-source`), deterministic diagnostic table header and `Path` column (`outdated-verbose`), and named gems (`outdated-named`) are differential-verified. Other option annotation paths remain **unsupported**. |
| `cache --all-platforms/--cache-path/--no-install` | **Supported** — `--cache-path=<path>` honored (`cache-path` dual-passed); `--no-install` honored (skip install); `--all-platforms` copies every platform variant of locked specs from the download cache + 4.x re-fetch line / 2.7.x `BUNDLE_CACHE_ALL` remembered config (`cache-all-platforms` dual-passed). |
| `clean --dry-run/--force` | **Supported** — `--dry-run` wired (`Would have removed`); `--force` accepted (`clean-force` dual-passed in Celerite's bundle-path mode; the Bundler system-gems mode is not used by Celerite). |
| `config list/get/set/unset --parseable` | `--parseable` handled for `get`; `config get/set/unset` work without a Gemfile (`config-local`/`config-global` dual-passed, array settings render as symbols like the reference). |
| `plugin install --source/--version/--git/--branch/--ref` | **Supported** — `--source` remote install: failure path on HTTP v2 (`plugin-source` exit 7) and success path with plugin-tree materialization + `Fetching`/`Installing` output (`plugin-source-ok` dual-passed; fixture plugin gem `my_plugin` ships `plugins.rb`); `--git/--branch/--ref` flag validation + git checkout materialization (`plugin-git-local`/`plugin-git-local2` dual-passed, incl. malformatted 29 exit). |
| `add --group/--version/--source/--path/--git/--branch/--ref/--skip-install/--strict/--optimistic` | **Partial** — `--group` (`add-group`), `--skip-install` (`add-skip-install`), `--version` (`add-version`), `--strict` (`add-strict`, exit 7 on the reference `= 1.8` error), `--optimistic` (`add-optimistic`), `--require` (`add-require`), `--path` (`add-path`), `--git`/`--branch` (`add-git`), and scoped `--source` (`add-source`), distinct-remotes scoped lock (`scoped-source-lock`), and `--ref` (`add-ref`) are differential-verified: requirement probes and candidate resolution use the scoped compact-index remote, installations route downloads/installers by resolved `remote_for` per gem, and generated lock GEM sections are grouped by that remote; `--github` remains suffix-only/not fixture-proven. |
| `binstubs --force/--standalone/--all-platforms/--shebang/--all` | **Supported** — `--force`/`--all`/`--all-platforms` honored with skip message (`binstubs-flags` dual-passed); `--shebang` rewrites the stub first line (`binstubs-shebang-line` dual-passed via harness `first-line` content probe; 2.7.x remembers `shebang` in local config). |

## Upstream spec suite coverage boundary

The committed `script/upstream-specs` targets only the **lockfile family** of
the upstream Bundler spec suite (pinned `v4.0.24` revision). The recorded result
under `docs/compat-matrix/generated/upstream-lockfile-v4.0.24.md` is
**64 examples, 64 failures**, not a passing gate. It is retained as a failure
baseline for M7.

**本迭代脚本变更（未重跑 rspec）**：移除 `script/upstream-specs` 中吞掉失败的
`|| true`（line 64 附近），使 rspec 非零退出时脚本按 `pipefail` 传播非零退出码；
保留既有 64 failures 失败基线记录逻辑/文案。由于本迭代未执行上游 spec，
上述 64 failures 仍为既有记录，不能视为本次运行结果。

The remaining families (resolver, runtime, resource, plugins, etc.) have selected
differential behavior only; `docs/upstream-spec-spike.md` records the initial
applicability assessment. Neither pending/unexecuted examples nor behavior
provided by the reference Ruby runtime counts as Celerite passing upstream specs.
No "full upstream suite" claim is made.

## Known divergences from reference (documented, not hidden)

1. Installed `.gemspec` files use the RubyGems stub format (same as the
   reference mode, whose installed specs are Ruby stub files, not Marshal) —
   verified across install/exec differential fixtures.
2. `setup` currently loads the reference `bundler/setup` (`Bundler.setup`) in
   the runtime compatibility path; an independent lightweight Ruby adapter is
   planned for M9. The `ruby-api` fixture proves behavior through that reference
   boundary, not a standalone Crystal-provided Ruby API.
3. Concurrent install requests are de-duplicated in-process
   single-flight (docs/architecture.md §3); a distributed lock is not claimed.

## How to re-run

```sh
shards build
crystal spec
crystal tool format --check src spec
script/differential               # 4.0.24
BUNDLER_REF_VERSION=2.7.2 script/differential
script/upstream-specs             # lockfile family; expect non-zero until failures closed
script/benchmark 3                # refresh results
script/profile                    # refresh profile numbers
```

> The 4.0.24 ↔ 2.7.2 differences in lockfile `BUNDLED WITH` indentation and
> CHECKSUMS handling are version-pinned (see
> `docs/compat-matrix/generated/cli-*.md` and `vendor/reference/MANIFEST.md`).
> "Compatible"/prior pass statements in this report are historical snapshot
> evidence for the pinned profiles and Ruby/platform noted above and are
> **未重跑验证** in this iteration.
