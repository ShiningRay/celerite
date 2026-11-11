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
  `ruby-api`, `bundler-inline`, `exec-missing` (106-127 evidence),
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

- **Ruby/RubyGems 约束过滤（进行中，未达 M7(1) 完整验收）**：已实现并接线（`032a531` 起，本迭代继续）`src/celerite/ruby_version.cr`/`src/celerite/ruby_runtime.cr`、`Celerite::RubyVersionMismatch`（exit 18）、bridge `ruby_environment.patchlevel` 与结构化 Gemfile `ruby` 选项（`ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`）、`ResolutionSource` 对 gem `required_ruby_version`/`required_rubygems_version` 的候选过滤（gem metadata 只按 `RUBY_VERSION` 比较，与 Bundler 4.0.24 `matches_current_ruby?` 一致；patchlevel 只在 Gemfile 目标 Ruby 校验中参与）、lockfile Ruby 复用比较 `RubyVersion` diff、`ruby_update` 写入正确 patchlevel。CLI runtime 校验（best-effort：bridge 不可用时跳过，**不视为通过**）已接入 check/install/show/info/fund/exec/cache/clean/doctor/pristine/outdated/update/licenses/console 等命令；`platform` 在 bridge 可用时输出 mismatch 文案但 exit 0，bridge 不可用时输出 "Ruby version requirement not validated (bridge unavailable); cannot confirm runtime match."；`list`/`lock`/`env` 按参考探针不因 mismatch 失败。可运行证据（2026-11-11）：`spec/ruby_version_spec.cr`（10）+ `spec/m7_ruby_runtime_spec.cr`（5，含 version/engine/patchlevel mismatch 文案与 exit 18、bridge 结构化 Gemfile `patchlevel: "1"` 传递）+ `spec/m7_platform_spec.cr`（2，bridge 不可用时不声称满足、`--ruby` 可解析输出）+ `spec/m7_ruby_constraints_spec.cr`（10，ABI 派生、lock 复用、`RubyRuntime` 结构化 diff）+ `spec/m7_resolver_ruby_constraints_spec.cr`（8，`required_ruby_version`/`required_rubygems_version` 候选过滤、patchlevel 不参与 gem metadata、Ruby/RubyGems-only 排除报 `SolveFailure` exit 6、纯无匹配版本仍报 `GemNotFoundError` exit 7）均通过；本轮 M7 相关 spec 合计 **107 examples, 0 failures, 0 errors, 0 pending**（退出码 0，含 `spec/m7_installed_discovery_spec.cr` 20、`spec/m7_fund_spec.cr` 2、`spec/m7_gem_spec.cr` 4、`spec/m7_console_spec.cr` 1）。已新增并**实际运行**最小 differential fixtures：`fixtures/differential/ruby-version-mismatch`（`check`，exit 18 + Bundler mismatch 文案）、`fixtures/differential/platform-ruby-mismatch`（`platform`，exit 0 + mismatch 文案）、`fixtures/differential/list-multi-group`（`list --only-group default test`，exit 0，多组空格列表）与 PATH 源的 `check-path`/`list-path`（exit 0）、`no-matching-version`（`lock --print`，无可用版本，exit 7）与 `platform-variant-fail`（`lock --add-platform x86_64-linux`，exit 7）均实跑 PASS；`ruby-metadata-fail`（PATH gem `required_ruby_version >= 99.0`）已修复为与参考一致的语义：仅因 Ruby/RubyGems 元数据被排除时报告 `SolveFailure`（exit 6 + 同形解释），而纯无匹配版本仍报 `GemNotFound`（exit 7）；`deferred-4.0.24` 已移除。定向子集 16 passed / 0 failed / 0 skipped（exit 0，含 GIT 安装态 `git-installed-discovery`、Gemfile engine/patchlevel 变体与 install-then-check）；4.0.24 全量 differential 为 **94 passed / 14 failed / 0 skipped**，14 项失败分类见下节“Local verification run”。**未验证/未达验收**：Gemfile 目标 Ruby/engine/patchlevel/ABI 全矩阵正反例与安装复核；bridge 缺失场景仅有纯逻辑 spec，无 CLI 集成证据；2.7.2 profile 未重跑。
- **本机 codegen/OpenSSL 阻塞与本地 shim（2026-11-11，环境问题非项目缺陷）**：Crystal 1.22.1 标准库 `openssl/digest.cr:77` 绑定 OpenSSL 1.1 的 `EVP_MD_size`，而本机 MSYS2 ucrt64 为 OpenSSL 3.6.5，`libcrypto.dll.a`/`libcrypto.a` 仅导出 `EVP_MD_get_size`（`nm` 已验证无 `EVP_MD_size`），故 stock `crystal build src/cli.cr` 报 `undefined reference to 'EVP_MD_size'`。本轮用**仓库外临时 C shim**（`#undef EVP_MD_size` + `int EVP_MD_size(const EVP_MD *md){ return EVP_MD_get_size(md); }`）配合 `--link-flags "<shim.o>"` 成功完成本地 codegen（EXIT 0），并据此重建 `bin/celerite.exe`（`--version` 0.1.0）；**shim 与二进制均不入库**（`bin/` 被 gitignore），stock 构建仍失败。CLI 集成 spec 与 differential 的计数/分类见下节。
- **安装后 gem 发现（部分修复）**：`Commands.installed_gem_dir` 对 RubyGems 安装放宽为 gem 目录存在即可视为已发现（容忍缺 `specifications/*.gemspec`），`check`/`list`/`show`/`info`/`doctor` 受益；同时修复 `show --paths <name>` 把 `--paths` 当作 gem 名的问题（`name = names.first?`），并将 `list` 的人类可读默认格式对齐 4.0.24（无论是否给组过滤都输出 `Gems included by the bundle:` + `  * name (version)` + `bundle info` 提示；此前默认只输出 `name-version`）。可运行证据：`spec/m7_installed_discovery_spec.cr` **20 examples, 0 failures**，覆盖 check/list/show/show --paths 的“仅 gem 目录”场景、缺 gem 目录/仅 specification 文件的负例、PATH 源与 GIT checkout 解析、`--only-group`/`--without-group`、空格分隔多组 `--only-group default test` 与 `--without-group test development`、`BUNDLE_WITH`（with 显式包含）以及平台特定 gem（`nokogiri-x64-mingw-ucrt`）的 check/list/show；`fixtures/differential/list-multi-group`、`check-path`、`list-path`、`git-installed-discovery` 均已实跑 PASS；`git-installed-discovery` 先 `install` 本地 `:git` 源，再覆盖 `check`/`list`/`show --paths`/`info --version`，并固定了 4.0.24 的 git 短 revision 显示（`name (version rev)`）与 Windows 路径正斜杠渲染。仍需补齐：更多平台变体与 path/Git + group 组合的 differential 证据；当前不可宣称 M7(2) 完成。
- **占位/诊断路径（部分修复）**：`fund` 从已安装 specifications/`.gem` metadata 读取 `funding_uri`，并以 `spec/m7_fund_spec.cr`（2 examples，真实 Ruby bridge + gemspec metadata）验证有 funding 与无 funding 两种输出；`gem` 改为最小可用 scaffold（下划线 lib 文件名、gemspec `require_relative` + `Module::VERSION`、README.md、LICENSE.txt、gemspec files/summary/required_ruby_version），对常见生成选项输出 "not fully supported ... Generating a minimal scaffold only"，并由 `spec/m7_gem_spec.cr`（4 examples）验证；`console` 在 `irb` 缺失时返回 127 与明确说明（非完整交互 console），由 `spec/m7_console_spec.cr`（1 example，隔离 PATH）验证。`env`/`issue` Build Metadata 改为 `Celerite #{Celerite::VERSION}, compatibility profile` + 仓库真实 `Git SHA`/`Timestamp`（`git rev-parse`，失败回落 `"unknown"`），**Celerite 运行在兼容 profile 下，非上游 Bundler 构建**。仍需更多 M7(3) 行为/输出证据与差分。
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

## Local verification run (2026-11-11, task-2)

- **Codegen workaround**: a temporary, out-of-repo C shim
  (`EVP_MD_size` → `EVP_MD_get_size`) was compiled with MSYS2 gcc and passed via
  `--link-flags`; `crystal build src/cli.cr -o bin/celerite.exe --link-flags "<shim.o>"`
  exited 0 and the rebuilt binary prints `0.1.0`. The shim and binary are
  **not committed** (`bin/` is gitignored); stock `crystal build src/cli.cr`
  still fails with `undefined reference to 'EVP_MD_size'`.
- **Specs**: the 107-example base subset passed (0 failures, exit 0);
  `spec/cli_spec.cr` passed with the shim (24 examples, 0 failures, exit 0);
  the M7 installed-discovery/platform subset passed with the shim
  (21 examples, 0 failures, exit 0).
- **Differential**: the targeted subset
  (`ruby-version-mismatch`, `platform-ruby-mismatch`, `check-missing`,
  `check-unresolved`, `list-missing`, `show-missing`, `list-multi-group`,
  `check-path`, `list-path`, `no-matching-version`,
  `platform-variant-fail`, `ruby-metadata-fail`, `git-installed-discovery`)
  passed 13/13 (exit 0); the previously deferred `ruby-metadata-fail` now
  matches Bundler's Ruby-metadata `SolveFailure` (exit 6) while a genuinely
  missing version still reports `GemNotFound` (exit 7). `git-installed-discovery`
  installs a local `:git` gem and then exercises `check`, `list`,
  `show --paths`, and `info --version`; it also pins the git short revision in
  human-readable output and forward-slash path rendering.
  Full 4.0.24 run: **94 passed, 14 failed, 0 skipped, exit 1**.
- The 14 failures split into: **7 × `make` unavailable** (racc native
  extension: `add-group`, `add-optimistic`, `add-remove`, `add-version`,
  `cache-all-platforms`, `native-ext`, `native-ext-target`) and
  **7 × generated `.bat`/`loader` content differences** (`binstubs`,
  `exec-loader`, `install-force`, `install-fresh`, `install-rerun`,
  `pristine`, `pristine-named`). None are on the M7(1)-(3) paths; the suite is
  nevertheless not green.
- Durable details and per-fixture notes:
  [`docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`](compat-matrix/generated/differential-4.0.24-2026-11-11.md).
- **Still unverified**: 2.7.2 profile, release-form/published-binary behavior,
  M7(1) full matrix (engine/patchlevel/ABI/Gemfile target + install re-check),
  M7(2) path/Git combinations and additional platform variants, broader
  M7(3) differential evidence.

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
