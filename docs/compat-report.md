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

- **Ruby/RubyGems 约束过滤（进行中，未达 M7(1) 完整验收）**：已实现并接线（`032a531` 起，本迭代继续）`src/celerite/ruby_version.cr`/`src/celerite/ruby_runtime.cr`、`Celerite::RubyVersionMismatch`（exit 18）、bridge `ruby_environment.patchlevel` 与结构化 Gemfile `ruby` 选项（`ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`）、`ResolutionSource` 对 gem `required_ruby_version`/`required_rubygems_version` 的候选过滤（gem metadata 只按 `RUBY_VERSION` 比较，与 Bundler 4.0.24 `matches_current_ruby?` 一致；patchlevel 只在 Gemfile 目标 Ruby 校验中参与）、lockfile Ruby 复用比较 `RubyVersion` diff、`ruby_update` 写入正确 patchlevel。CLI runtime 校验（best-effort：bridge 不可用时跳过，**不视为通过**）已接入 check/install/show/info/fund/exec/cache/clean/doctor/pristine/outdated/update/licenses/console 等命令；`platform` 在 bridge 可用时输出 mismatch 文案但 exit 0，bridge 不可用时输出 "Ruby version requirement not validated (bridge unavailable); cannot confirm runtime match."；`list`/`lock`/`env` 按参考探针不因 mismatch 失败。可运行证据（2026-11-11）：`spec/ruby_version_spec.cr`（10）+ `spec/m7_ruby_runtime_spec.cr`（9，含 version/engine/engine_version/patchlevel mismatch 文案与 exit 18、matching version/patchlevel 与 matching engine/engine_version 正例、bridge 结构化 Gemfile `patchlevel: "1"`/`engine: "jruby"`/`engine_version` 传递）+ `spec/m7_platform_spec.cr`（2，bridge 不可用时不声称满足、`--ruby` 可解析输出）+ `spec/m7_ruby_constraints_spec.cr`（10，ABI 派生、lock 复用、`RubyRuntime` 结构化 diff）+ `spec/m7_resolver_ruby_constraints_spec.cr`（8，`required_ruby_version`/`required_rubygems_version` 候选过滤、patchlevel 不参与 gem metadata、Ruby/RubyGems-only 排除报 `SolveFailure` exit 6、纯无匹配版本仍报 `GemNotFoundError` exit 7）均通过；本轮 M7 相关 spec 合计 **111 examples, 0 failures, 0 errors, 0 pending**（退出码 0，含 `spec/m7_installed_discovery_spec.cr` 20、`spec/m7_fund_spec.cr` 3、`spec/m7_gem_spec.cr` 4、`spec/m7_console_spec.cr` 1）。已新增并**实际运行**最小 differential fixtures：`fixtures/differential/ruby-version-mismatch`（`check`，exit 18 + Bundler mismatch 文案）、`fixtures/differential/platform-ruby-mismatch`（`platform`，exit 0 + mismatch 文案）、`fixtures/differential/list-multi-group`（`list --only-group default test`，exit 0，多组空格列表）与 PATH 源的 `check-path`/`list-path`（exit 0）、`ruby-target-match`/`ruby-patchlevel-match`/`ruby-engine-match`（`install` + `check`，exit 0，Gemfile 目标 Ruby 正例）、`ruby-patchlevel-match-list`（`install` + `list`，exit 0，Gemfile patchlevel 与 lock `RUBY VERSION` 不一致时 `list` 重解通知）、`check-missing-ruby-nolock`（`check`，Gemfile 声明 `ruby` 但 lock 无 `RUBY VERSION` 且依赖未安装，exit 1 + `Resolving dependencies...` 与 missing 文案）与 `list-missing-ruby-nolock`（同场景 `list`，exit 1 + `Resolving dependencies...` 与 missing 文案）、`no-matching-version`（`lock --print`，无可用版本，exit 7）与 `platform-variant-fail`（`lock --add-platform x86_64-linux`，exit 7）均实跑 PASS；`ruby-metadata-fail`（PATH gem `required_ruby_version >= 99.0`）已修复为与参考一致的语义：仅因 Ruby/RubyGems 元数据被排除时报告 `SolveFailure`（exit 6 + 同形解释），而纯无匹配版本仍报 `GemNotFound`（exit 7）；`deferred-4.0.24` 已移除；`rubygems-metadata-fail`（PATH gem `required_rubygems_version >= 99.0`）同样报 SolveFailure exit 6，与参考一致。`rubygems-metadata-match`（PATH gem `required_rubygems_version = ">= 0"`，exit 0）与 `ruby-metadata-match`（PATH gem `required_ruby_version = ">= 1.0"`，`lock --print`，exit 0，satisfied required_ruby_version 正例）为满足正例对称通过（4.0.24/2.7.2）；lockfile 生成现对声明的 rubygems/GEM 源在无 GEM spec 时仍输出空 `GEM` section（PATH-only 解析 parity）。定向子集 28 passed / 0 failed / 0 skipped（exit 0，含 GIT 安装态 `git-installed-discovery`、PATH 源 funding `fund-path`、Gemfile engine/engine_version/patchlevel 变体与目标 Ruby 正例 `ruby-target-match`/`ruby-patchlevel-match`/`ruby-engine-match`、`ruby-patchlevel-match-list`、Gemfile 有 ruby 但 lock 无 `RUBY VERSION` 且依赖未安装时的 `check`/`list` 通知 `check-missing-ruby-nolock`/`list-missing-ruby-nolock`、RubyGems 元数据 SolveFailure、install-then-check 与 `show/info` 安装态）；4.0.24 全量 differential 为 **101 passed / 14 failed / 0 skipped**，14 项失败分类见下节“Local verification run”。**未验证/未达验收**：Gemfile 目标 Ruby/engine/patchlevel 正例与 mismatch 反例已覆盖，ABI/平台变体正例；Gemfile 声明 `ruby` 但 lock 无 `RUBY VERSION` 且依赖未安装时 `check`/`list` 的 `Resolving dependencies...` 通知已由 `check-missing-ruby-nolock`/`list-missing-ruby-nolock`（4.0.24/2.7.2）钉住。手工 harness-style 取证（4.0.24/2.7.2，依赖已满足、lock 无 `RUBY VERSION`）显示 reference `check` 与 `list` 均打印 `Resolving dependencies...`；`Commands.list` 已对齐为 `:missing_from_lock` 时同样打印（bridge 可用路径），但该已满足场景尚未 differential-fixture 化：harness-like 手工探针（隔离 env，预置 `BUNDLE_PATH/ruby/4.0.0/{gems,specifications}/json_pure-2.8.1`，Gemfile `ruby "4.0.6"`，lock 有 specs/PLATFORMS/DEPENDENCIES/BUNDLED WITH 无 `RUBY VERSION`，`CELERITE_REFERENCE_BUNDLER_LIB`/`CELERITE_PROFILE_BUNDLER_VERSION` 指向 4.0.24，shim-built celerite）显示 reference 4.0.24 与 celerite `check`/`list` 均输出 `Resolving dependencies...` 后 EXIT 0（2026-11-11，probe base `C:\temp\nolock-sat-harnesslike-eZPd5c`）；2.7.2 reference 同形。**阻塞**：`script/differential` 无命令前预填充 `BUNDLE_PATH` 且保留 lock 无 `RUBY VERSION` 的 primitive（`extra/` 仅进 project，`install` 通常会写回 lock 并补 `RUBY VERSION`），暂无法固化为 fixture；bridge 不可用时通知为 fail-safe 可能省略；`show`/`info` 在 patchlevel-unlock 场景与参考一致均无通知（手工对照），其他重解通知场景未验证；bridge 缺失场景仅有纯逻辑 spec，无 CLI 集成证据；2.7.2 profile 定向子集 28/28 已跑，全量未跑。
- **本机 codegen/OpenSSL 阻塞与本地 shim（2026-11-11，环境问题非项目缺陷）**：Crystal 1.22.1 标准库 `openssl/digest.cr:77` 绑定 OpenSSL 1.1 的 `EVP_MD_size`，而本机 MSYS2 ucrt64 为 OpenSSL 3.6.5，`libcrypto.dll.a`/`libcrypto.a` 仅导出 `EVP_MD_get_size`（`nm` 已验证无 `EVP_MD_size`），故 stock `crystal build src/cli.cr` 报 `undefined reference to 'EVP_MD_size'`。本轮用**仓库外临时 C shim**（`#undef EVP_MD_size` + `int EVP_MD_size(const EVP_MD *md){ return EVP_MD_get_size(md); }`）配合 `--link-flags "<shim.o>"` 成功完成本地 codegen（EXIT 0），并据此重建 `bin/celerite.exe`（`--version` 0.1.0）；**shim 与二进制均不入库**（`bin/` 被 gitignore），stock 构建仍失败。CLI 集成 spec 与 differential 的计数/分类见下节。
- **安装后 gem 发现（部分修复）**：`Commands.installed_gem_dir` 对 RubyGems 安装放宽为 gem 目录存在即可视为已发现（容忍缺 `specifications/*.gemspec`），`check`/`list`/`show`/`info`/`doctor` 受益；同时修复 `show --paths <name>` 把 `--paths` 当作 gem 名的问题（`name = names.first?`），并将 `list` 的人类可读默认格式对齐 4.0.24（无论是否给组过滤都输出 `Gems included by the bundle:` + `  * name (version)` + `bundle info` 提示；此前默认只输出 `name-version`）。可运行证据：`spec/m7_installed_discovery_spec.cr` **20 examples, 0 failures**，覆盖 check/list/show/show --paths 的“仅 gem 目录”场景、缺 gem 目录/仅 specification 文件的负例、PATH 源与 GIT checkout 解析、`--only-group`/`--without-group`、空格分隔多组 `--only-group default test` 与 `--without-group test development`、`BUNDLE_WITH`（with 显式包含）以及平台特定 gem（`nokogiri-x64-mingw-ucrt`）的 check/list/show；`fixtures/differential/list-multi-group`、`check-path`、`list-path`、`git-installed-discovery` 均已实跑 PASS；`git-installed-discovery` 先 `install` 本地 `:git` 源，再覆盖 `check`/`list`/`show --paths`/`info --version`，并固定了 4.0.24 的 git 短 revision 显示（`name (version rev)`）与 Windows 路径正斜杠渲染。本轮另对齐 `show <gem>`/`info <gem>`：`show` 仅打印安装路径（参考 `print_gem_path`），`info` 按 4.0.24 顺序输出 tab 缩进的 Summary/Homepage/Documentation/Source Code/Funding/Wiki/Changelog/Bug Tracker/Mailing List/Path，仅在 `default_gem?` 时打印 Default Gem，并在有反向依赖时打印 Reverse Dependencies；`fixtures/differential/show-info-installed`（install → show → info）实跑 PASS。仍需补齐：更多平台变体与 path/Git + group 组合的 differential 证据；当前不可宣称 M7(2) 完成。
- **占位/诊断路径（部分修复，M7(3) 本轮补证据）**：`fund` 从已安装 specifications/`.gem` metadata 以及 PATH/GIT source 的 gemspec `funding_uri` 读取资助信息（`read_source_funding_uri` 优先），`spec/m7_fund_spec.cr`（3 examples，0 failures）覆盖安装树 metadata、PATH source funding 与无 funding；`fixtures/differential/fund-path`（command `fund`，PATH gem `s.metadata["funding_uri"]`）本轮用 shim-built binary 复核 **4.0.24 PASS (exit=0)**、**2.7.2 PASS (exit=0)**。`gem` 为最小可用 scaffold（下划线 lib 文件名、gemspec `require_relative` + `Module::VERSION`、README.md、LICENSE.txt、files/summary/required_ruby_version），对不完全支持选项输出 warning + `Generating a minimal scaffold only...` 但仍生成最小 scaffold；`spec/m7_gem_spec.cr`（4 examples，0 failures）与 CLI 探针证实：无参数 stderr `Please provide a gem name` **exit 1**；`gem my_sample --test` stdout `Creating gem 'my_sample'...`、stderr 明示 `--test` 不完全支持并仅生成最小 scaffold，**exit 0** 且生成 `Gemfile, lib/my_sample.rb, LICENSE.txt, my_sample.gemspec, README.md`（未伪装完整 Bundler 模板/选项矩阵）。`console` 为显式未完整实现的交互 console：IRB 缺失时 stderr `bundle console requires IRB (\`irb\`) in PATH; IRB not found. (Celerite: full interactive bundle console not implemented; install IRB to exec irb in bundle context)` **exit 127**（`spec/m7_console_spec.cr`，1 example，隔离 PATH，0 failures；Windows 下直接做 PATH 隔离 CLI 探针易破坏 Ruby 运行依赖，不作为行为结论，spec 为可运行证据）。`env`/`issue` 输出 `Bundler <profile> (Celerite #{Celerite::VERSION}, compatibility profile)` 与 `## Bundler Build Metadata`（`Timestamp`/`Git SHA`）：`build_timestamp` 改为 `git log -1 --format=%cs HEAD` 并校验首行 `YYYY-MM-DD`，否则回落 `"unknown"`（修复 Windows Git 2.55 下 `git rev-parse --format=%cs -s HEAD` 返回非日期输出仍 success 的可移植性问题）；`git_sha` 优先取可执行文件所在仓库 `.git` 的 short SHA，否则 cwd `git rev-parse --short=7 HEAD`，失败 `"unknown"`。CLI 证据（shim-built binary）：仓库 cwd 子目录临时项目 `env` **exit 0** 输出 compat profile 与真实 `Timestamp  2026-11-11`、`Git SHA    50c005a`；非 git cwd 临时项目 `env` **exit 0** 输出 `Timestamp  unknown`、`Git SHA    50c005a`（fallback/来源证据）；`env`（无 Gemfile）**exit 10** `Could not locate Gemfile`；`issue`（缺 gem 临时项目）**exit 1** 输出 compat profile/Build Metadata/`## Bundle Doctor` 并报告 missing gem（doctor 语义）。M7(3) 相关 spec 本轮复跑 **8 examples, 0 failures**（`m7_console_spec`/`m7_gem_spec`/`m7_fund_spec`，EXIT 0）。**未验证/未达验收**：未新增 `env`/`issue` 与 Bundler reference 的完整 differential fixture（仅 CLI/实现/spec 取证）；`console` 在 IRB 可用时的交互/exec-in-bundle-context 行为未做 differential；`gem` 仅最小 scaffold 与已验证选项路径，未覆盖完整 Bundler 模板/选项矩阵；Build Metadata 中 Timestamp 取决于可用 git/cwd（已验证真实与 fallback），跨发布产物/无 git 场景仍需按环境判断。
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
- **Specs**: the 111-example base subset passed (0 failures, exit 0);
  `spec/cli_spec.cr` passed with the shim (24 examples, 0 failures, exit 0);
  the M7 installed-discovery/platform subset passed with the shim
  (22 examples, 0 failures, exit 0).
- **Differential**: the targeted subset
  (`ruby-version-mismatch`, `platform-ruby-mismatch`, `ruby-engine-mismatch`,
  `ruby-engine-version-mismatch`, `ruby-patchlevel-mismatch`, `ruby-metadata-fail`,
  `rubygems-metadata-fail`, `no-matching-version`,
  `platform-variant-fail`, `install-check`, `check-missing`,
  `check-unresolved`, `list-missing`, `show-missing`, `list-multi-group`,
  `check-path`, `list-path`, `git-installed-discovery`,
  `show-info-installed`, `fund-path`, `ruby-target-match`,
  `ruby-patchlevel-match`, `ruby-engine-match`)
  passed 27/27 (exit 0); `ruby-metadata-fail` and `rubygems-metadata-fail`
  now match Bundler's Ruby/RubyGems-metadata `SolveFailure` (exit 6) while a
  genuinely missing version still reports `GemNotFound` (exit 7).
  `git-installed-discovery` installs a local `:git` gem and then exercises
  `check`, `list`, `show --paths`, and `info --version`; it also pins the git
  short revision in human-readable output and forward-slash path rendering.
  `fund-path` pins PATH-source funding metadata (`s.metadata["funding_uri"]`)
  and the `* example (1.0.0)` / `  Funding: ...` output on both profiles.
  The same 23-fixture targeted subset also passed on the 2.7.2 profile
  (23 passed, 0 failed, 0 skipped, exit 0).
  Full 4.0.24 run (2026-11-11 基线, 115 fixtures): **101 passed, 14 failed, 0
  skipped, exit 1**.
- The 14 failures split into: **7 × `make` unavailable** (racc native
  extension: `add-group`, `add-optimistic`, `add-remove`, `add-version`,
  `cache-all-platforms`, `native-ext`, `native-ext-target`) and
  **7 × generated `.bat`/`loader` content differences** (`binstubs`,
  `exec-loader`, `install-force`, `install-fresh`, `install-rerun`,
  `pristine`, `pristine-named`). None are on the M7(1)-(3) paths; the suite is
  nevertheless not green.
- **Differential 全量刷新（2026-11-12，HEAD=`a8753b6` 已推送，shim-built bin）**：
  全量 `script/differential`（Bundler 4.0.24，无 fixture 参数，122 fixtures）实测
  **114 passed, 8 failed, 0 skipped，wrapper exit 1**（log
  `C:\temp\celerite-diff-full-4.0.24-a8753b6.log`，mtime 03:18:50 CST，汇总行在
  log 第 295 行）。8 个 FAIL = 7× racc `make` 不可用（`add-group`/`add-optimistic`/
  `add-remove`/`add-version`/`cache-all-platforms`/`native-ext`/`native-ext-target`，
  块内均有 `make failedNo such file or directory - make`，racc-1.8.1/ext/racc/cparse）
  + 1× `exec-loader`（`ruby/4.0.0/bin/loader` 与 `loader.bat` 归一化后内容差异）。
  按名字比对：当前 8 个 FAIL 全部落在先前记录的 14 个 FAIL 名单内（⊆），即无新增失败
  用例；先前 7 个 `.bat`/`loader` 失败中除 `exec-loader` 外的 6 个（`binstubs`/
  `install-force`/`install-fresh`/`install-rerun`/`pristine`/`pristine-named`）本轮转
  PASS。为何从 7 降为 1 不作因果断言（本轮未取证）。与 101/14 基线相比 delta 为
  +13 passed / −6 failed，同期新增 7 个 fixtures（含 2 个 boundary fixtures，均 PASS）。
  **2.7.2 全量本轮未重跑——未验证**；复现：
  `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`。
  逐例证据与分类见
  [`docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`](compat-matrix/generated/differential-4.0.24-2026-11-11.md)。
- **M7(1) 矩阵补强（2026-11-12，HEAD=`7c446d9` + 同轮 worktree 未提交改动，shim-built bin，后随 3c4f55d 提交）**：
  新增 6 个 differential fixtures（`ruby-metadata-boundary-fail` `>= 4.0.7`、
  `rubygems-metadata-boundary-fail` `>= 4.0.17`、`ruby-metadata-exact-match`
  `= 4.0.6`、`rubygems-metadata-pessimistic-match` `~> 4.0`、
  `ruby-engine-patchlevel-match`（engine/engine_version/patchlevel 全匹配，
  install+check）、`multi-platform-install`（`lock --add-platform x86_64-linux`
  + install + check；首跑 racc ext 落 Class A `make` 阻塞，已移除 racc 保留
  json_pure+thor 后复跑 PASS））；spec 新增 3 个 `RubyRuntime.diff` 优先级例 +
  新 `spec/m7_platform_match_spec.cr` 4 例（Platform 解析/匹配/特异度）。实测：
  spec 子集 46 examples, 0 failures, 0 errors, 0 pending（EXIT 0）；4.0.24 定向
  6/6 PASS（含修正后单跑 `differential (4.0.24): 1 passed, 0 failed, 0 skipped`）；
  2.7.2 定向 6/6 PASS、扩展 36 例定向集 36/36 PASS（`differential (2.7.2): 36
  passed, 0 failed, 0 skipped`，DIFF_272_36_EXIT=0）；4.0.24 全量重跑 128 fixtures
  **120 passed, 8 failed, 0 skipped，wrapper exit 1**（log
  `C:\temp\celerite-diff-full-4.0.24-7c446d9.log`，mtime 04:36:56 CST，汇总行在
  log 第 301 行），8 个 FAIL 名字与 03:18 轮完全一致（⊆ 先前 14 名单，按名字无比对
  新增回归），6 个新 fixture 全 PASS，delta +6 passed / ±0 failed / +6 fixtures。
  **后续 B:1 exec-loader 修复子项（2026-11-12，本轮，shim 本地 bin）追加实测**：`exec-loader`/`exec-loader-disabled` 定向双 profile PASS（见上文 B:1 bullet），4.0.24 全量重跑 **130 fixtures, 123 passed, 7 failed, 0 skipped, wrapper exit 1**（`C:\temp\celerite-diff-full-4.0.24-execloader-final.log`，mtime 08:02:07，299 行），7 FAIL 仅 `add-group`/`add-optimistic`/`add-remove`/`add-version`/`cache-all-platforms`/`native-ext-target`/`native-ext`（class A racc/make，`make failedNo such file or directory - make`），`exec-loader` 与 `exec-loader-disabled` 均 PASS；较 128:120/8/0 按实测计数 +3 passed / -1 failed / +2 fixtures，按名字无新增失败。
  **2.7.2 全量已实跑（2026-11-12 08:34–08:45 CST，HEAD=`20690ff`，shim 本地 bin）**：130 fixtures，**121 passed / 8 failed / 1 skipped（documented deferral），wrapper exit 1**，log `C:\temp\celerite-diff-full-2.7.2-20690ff.log`（12228 bytes，mtime 08:45:20，293 lines）。FAIL 8 = A:6 racc/make（add-optimistic/add-remove/add-version/cache-all-platforms/native-ext/native-ext-target，`make` 不可用，环境阻塞）+ C:2 clean 输出（`clean-force`/`clean-unused`，2.7.2 特有：ref 打印 `Removing ...`、cel 未打印；4.0.24 PASS，根因未定位）；SKIP 1 = `add-group`（harness documented deferral，network-required；4.0.24 为 class A FAIL）。按名对比 4.0.24 全量 130:123/7/0：6×racc/make 共现、exec-loader/exec-loader-disabled PASS、无 B:1。复现：`BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`。
  逐例证据与分类见
  [`docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`](compat-matrix/generated/differential-4.0.24-2026-11-11.md)。
- Durable details and per-fixture notes:
  [`docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`](compat-matrix/generated/differential-4.0.24-2026-11-11.md).
- **M7(3) 部分修复（2026-11-12，HEAD=`3c4f55d`，shim-built bin）**：新增 differential fixture
  `fixtures/differential/env-report`（`env`，Gemfile cwd 正常输出，exit 0）并与既有
  `issue-no-gemfile`（exit 10）/`issue-missing-gems`（exit 1）组成 env/issue 稳定场景集
  （lead 要求的 repo-cwd 正常输出/无 Gemfile exit 10/缺 gem issue exit 1）。定向 differential
  **4.0.24：3 passed, 0 failed, 0 skipped，DIFF_EXIT=0**；**2.7.2：3 passed, 0 failed, 0
  skipped，DIFF_EXIT=0**（命令
  `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp [BUNDLER_REF_VERSION=2.7.2] bash script/differential env-report issue-no-gemfile issue-missing-gems`；
  harness N5 归一化剥离 `## Environment` 机体至 `## Bundle Doctor` 后比对）。`console`/`gem`
  边界证据（shim 本地、非 differential）：IRB 缺失 PATH 下 `console` stderr 含
  `bundle console requires IRB (`irb`) in PATH... (Celerite: full interactive bundle console not implemented; install IRB to exec irb in bundle context)`
  且 EXIT 127（同受限 PATH 下 reference 为 `bundle: command not found`，不可差分比对）。

  **B2 取证与修复进展（5949cc2 + b4fe095，2026-11-12，`src/celerite/cli/commands_install.cr`，已推送 `origin/main`）**：

  **(1) 5949cc2（`fix(M7 task-2): normalize Windows PATH env var casing in exec command (B2 console/exec)`，+9/-1）修复内容/根因（历史，≤8f1ef39 已同步）**：Windows 环境变量名大小写不敏感，但 `ENV.to_h` 保留原始 casing（如 `Path`）；`exec` 在注入 `bundle bin`/`RUBYOPT`/`BUNDLE_*` 后仍可能保留旧 `Path` key，子进程收到的 PATH 被旧值遮蔽，导致 `find_executable` 与被 exec 命令解析失败。修复：收集 `ENV["PATH"]?` 为 `path_value`，删除所有 `downcase=="path"` 的 key，再设置 canonical `PATH = "#{bin_dir}#{path_delimiter}#{path_value}"`。门禁（工部回报，5949cc2）：`crystal tool format --check src spec` EXIT 0、`crystal build --no-codegen src/cli.cr` EXIT 0（2 known deprecations）、`git diff --check` EXIT 0，shim build EXIT 0（**本轮未独立重跑门禁/探针**，仅据代码 diff 与回报记录同步）。

  **修复前探针（≤14ccb9d，工部回报记录，shim 本地 bin）**：`C:\temp\defaultgem-test`（Gemfile `json >= 0`，lock json_pure 2.8.1，`BUNDLE_PATH=C:/temp/defaultgem-test/gems` 含已安装 json_pure 3.1.0，`GEM_HOME/GEM_PATH=C:/Ruby40-x64/lib/ruby/gems/4.0.0`，PATH 含 `C:\Ruby40-x64\bin`，`CELERITE_BIN`=shim bin）下 `celerite console` 与 `celerite exec irb --version` 均 stderr `bundler: command not found: irb` / `Install missing gem executables with \`bundle install\`` EXIT 127；`celerite exec ruby -e "puts 123"` 亦 EXIT 127 `bundler: command not found: ruby`（当时未定性，`Get-Command ruby` => `C:\Ruby40-x64\bin\ruby.exe`）。

  **5949cc2 后探针（同环境/设定，工部回报，未独立重跑）**：`celerite exec ruby --version` **EXIT 0**，stdout `ruby 4.0.6`（**127→0**，证实 PATH/可执行文件解析问题已修复）；`celerite exec irb --version` **EXIT 1**，stderr 含 `LoadError: cannot load such file -- C:\Ruby40-x64\lib\bundler/setup`；`celerite console` **EXIT 1**，同类 LoadError（**127→1**，失败阶段从“找不到 irb 可执行文件”前移到 bundle setup 加载）。当时剩余原因（取证，未修代码）：`bundler_lib` 默认 `File.expand_path("../lib", dirname(env.ruby_exe))`（Ruby 安装 lib，非 bundler gem lib）；`CELERITE_REFERENCE_BUNDLER_LIB` 常规未设导致 setup 路径错误（见下 b4fe095 修复）。

  **(2) b4fe095（`fix(M7 task-2): discover bundler gem lib for exec/console setup (B2)`，2026-11-12，`src/celerite/cli/commands_install.cr` +22/-4，已推送 `origin/main`；本轮 shim 本地 bin 实测取证）修复内容/根因**：`Commands.exec` 在 `CELERITE_REFERENCE_BUNDLER_LIB` 未设时回退 `File.expand_path("../lib", dirname(env.ruby_exe))`（如 `C:/Ruby40-x64/lib`），该目录无 `bundler/setup.rb`；注入 `RUBYOPT=-r<bundler_lib>/bundler/setup`/`RUBYLIB`/`BUNDLE_BIN_PATH` 后，在脚本执行/`-e` 触发 require 或 Bundler 激活时失败（`LoadError` 或 `Could not find 'bundler'`）。`console`（`commands_surface.cr`）IRB 存在性检查后委托 `exec ["irb", ...]`。修复：`exec` 统一 `bundler_version = ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"`；`bundler_lib = ENV["CELERITE_REFERENCE_BUNDLER_LIB"]?` 或 `find_bundler_lib(env, bundler_version)`；始终设置 `process_env["BUNDLER_VERSION"]=bundler_version`。新增 `find_bundler_lib(env, version)`：遍历 `env.gem_paths + default_gem_dir + user_gem_dir`，命中 `<dir>/gems/bundler-<version>/lib/bundler/setup.rb` 即返回；否则回退 `File.expand_path("../lib", dirname(env.ruby_exe))`（兼容）。harness 显式 `CELERITE_REFERENCE_BUNDLER_LIB` 优先级保留。门禁（本轮实跑）：`crystal tool format --check src spec` EXIT 0、`crystal build --no-codegen src/cli.cr` EXIT 0（2 known deprecations：`File.executable?` L584/L648）、`git diff --check` EXIT 0；shim build EXIT 0（`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`，PATH 含 `C:\msys64\usr\bin`，bin mtime 2026-11-12T13:18:52，未入库）。

  **b4fe095 受控取证与前后对比（shim 本地 bin，未跑全量 differential，Ruby 4.0.6）**：probe `C:\temp\m7b2-probe\project`，Gemfile `source "file:///C:/Users/ShiningRay/projects/ShiningRay/celerite/fixtures/gem-index"` + `gem "json_pure", "2.8.1"`，lock BUNDLED WITH 4.0.24；隔离 env `USERPROFILE/GEM_HOME/GEM_PATH/BUNDLE_PATH` 指向 probe、`RUBYOPT=''`、`TMPDIR=C:\temp`、PATH 含 `C:\Ruby40-x64\bin;...\Git\...\usr\bin;...\cmd`；`bundle _4.0.24_ install` EXIT 0。系统 bundler gem `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-4.0.24/lib/bundler/setup.rb` 存在。诊断：`ruby -rC:/Ruby40-x64/lib/bundler/setup --version` EXIT 0 但 `ruby -rC:/Ruby40-x64/lib/bundler/setup -e "puts 1"` EXIT 1 `LoadError: cannot load such file -- C:/Ruby40-x64/lib/bundler/setup`（`C:/Ruby40-x64/lib/bundler/setup.rb` 不存在）。

  - **Case A（修复后，无 `CELERITE_REFERENCE_BUNDLER_LIB`，`GEM_PATH=C:/temp/m7b2-probe/gems;C:/Ruby40-x64/lib/ruby/gems/4.0.0`，`CELERITE_PROFILE_BUNDLER_VERSION=4.0.24`）**：`celerite exec ruby --version` EXIT 0 stdout `ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [x64-mingw-ucrt]`；`celerite exec ruby -e "puts 123"` EXIT 0 stdout `123`；`celerite exec irb --version` EXIT 1 stderr `bundler: failed to load command: irb ... Gem::Exception ... can't find executable irb for gem irb. irb is not currently included in the bundle...`；`echo exit | celerite console` EXIT 1 同类 Gem::Exception（console 委托 exec irb）。前后对比：常规可见 bundler gem 场景下 `exec ruby`/`-e` 不再因错误 setup/lib 回退或激活失败；`exec irb` 在 IRB 不在 bundle 时错误类别转为与 reference `bundle exec irb` 对齐的 Gem::Exception（非 5949cc2 后的 setup LoadError）。
  - **Case B（reference bundle 4.0.24，对照）**：`bundle exec irb --version` EXIT 1 同语义 Gem::Exception “irb is not currently included in the bundle” → **exec irb 与 reference 对齐（IRB 不在 bundle 场景，exit/错误类别）**。`echo exit | bundle console` EXIT 1 `LoadError: cannot load such file -- irb` + Bundler 环境报告（Ruby 4.0 irb 非默认 gem）→ **reference console UX 与 exec irb 不同；celerite console 走 exec irb 路径返回 Gem::Exception，console UX 未完全对齐（残留）**。
  - **Case C（环境/配置约束，修复后）**：GEM_PATH 仅 probe gems 且无 bundler-4.0.24 gem 时，`celerite exec ruby -e "puts 123"` EXIT 1 `Could not find 'bundler' (= 4.0.24) - did find: [bundler-4.0.16] Checked in 'GEM_PATH=C:/temp/m7b2-probe/gems'`。`BUNDLER_VERSION` 激活要求对应 bundler gem 可见；若 profile bundler gem 不在可见 gem 路径且未提供 `CELERITE_REFERENCE_BUNDLER_LIB`，属**环境/配置约束**（harness 常设 REF_LIB 可绕过），非本次 setup 路径发现缺陷。

  **残留未对齐与未验证（截至 b4fe095 + subitem 2 取证，2026-11-12）**：`celerite console` 在 IRB 不在 bundle 时 UX/错误形态与 reference `bundle console` 不同（Gem::Exception vs LoadError+环境报告，≤2 次尝试内未做低成本对齐修复）；IRB 在 bundle 内且可用时的 `exec irb`/`console` 行为与交互路径**未验证**；Case C 下无可见 bundler gem 且无 `CELERITE_REFERENCE_BUNDLER_LIB` 的激活失败为环境约束；M7 子集 spec、4.0.24/2.7.2 全量 differential **未在 b4fe095 后重跑**（既有基线 130:123/7/0、130:123/6/1 计数保持不变）；5949cc2/b4fe095 相关探针除本节 Case A/B/C 外未全部独立重跑。bridge 不可用不得视为通过。

  **子项 2（console UX 对齐评估，IRB 不在 bundle，≤2 次尝试，本轮 docs-only 取证，未改代码）**：受控 probe `C:\temp\m7b2-ux\project`（新建，Gemfile `source "file:///C:/Users/ShiningRay/projects/ShiningRay/celerite/fixtures/gem-index"` + `gem "json_pure", "2.8.1"`，lock BUNDLED WITH 4.0.24，platforms ruby/x64-mingw-ucrt；隔离 `HOME/USERPROFILE=C:\temp\m7b2-ux\home`、`GEM_HOME=C:\temp\m7b2-ux\gems`、`GEM_PATH=C:\temp\m7b2-ux\gems;C:\Ruby40-x64\lib\ruby\gems\4.0.0`、`BUNDLE_PATH=C:\temp\m7b2-ux\gems\bundle`、`RUBYOPT=''`、`TMPDIR=C:\temp`、`CELERITE_PROFILE_BUNDLER_VERSION=4.0.24`、无 `CELERITE_REFERENCE_BUNDLER_LIB`，PATH 含 Ruby/Git/msys；`bundle _4.0.24_ install` EXIT 0，`bundle _4.0.24_ check` EXIT 0；IRB 不在 bundle，IRB 在 PATH；shim bin `bin/celerite.exe` mtime 2026-11-12T13:18:52+08:00 b4fe095，Ruby 4.0.6/bundler 4.0.24）。
  - `bundle _4.0.24_ exec irb --version`：EXIT 1，stderr `bundler: failed to load command: irb ... Gem::Exception ... can't find executable irb for gem irb. irb is not currently included in the bundle...`。
  - `celerite exec irb --version`：EXIT 1，同类 Gem::Exception（**exec irb 与 reference `bundle exec irb` 对齐**，exit/错误类别）。
  - `echo exit | bundle _4.0.24_ console`：EXIT 1，stderr 含 warning `irb used to be loaded from the standard library, but is not part of the default gems since Ruby 4.0.0...`、`Failed to activate irb, please install it with 'gem install irb'`、`LoadError: cannot load such file -- irb` 与 Bundler 环境报告模板（`bundler/cli/console.rb` 路径、Environment/Build Metadata/Bundler settings/Gemfile/Gemfile.lock、`Unfortunately, an unexpected error occurred...`）。
  - `echo exit | celerite console`：EXIT 1，同 `celerite exec irb` Gem::Exception（**console UX 未对齐 `bundle console`**；与 exec-irb 路径一致）。
  - 回归（同 env）：`celerite exec ruby --version` EXIT 0 `ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [x64-mingw-ucrt]`；`celerite exec ruby -e 'puts 123'` EXIT 0 `123`。
  - 可行性探针（同 env）：`echo exit | ruby -IC:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-4.0.24/lib C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-4.0.24/exe/bundle console` EXIT 1 复现 reference console UX（LoadError+环境报告）；`ruby -I... bundle exec irb --version` EXIT 1 复现 Gem::Exception。差异为实现语义：Bundler CLI `console`（in-process require/start IRB）vs celerite `console`（`src/celerite/cli/commands_surface.cr`，IRB 在 PATH 时委托 `exec irb`）。对齐在技术上可行但**非低成本/有行为契约风险**（需 bundler lib/exe 发现与 console 专用调用路径；`spec/m7_console_spec.cr` 固定 IRB 不在 PATH 时 EXIT 127 + `bundle console requires IRB (\`irb\`) in PATH...`/`full interactive bundle console not implemented` 契约；IRB 在 bundle 内/交互路径未验证）。**结论：不改代码，归类为实现语义差异/残留阻塞（记录取证+复现），未在 ≤2 次尝试内做 UX 对齐修复。**
  - **未验证**：IRB 在 bundle 内且可用时 `exec irb`/`console` 行为与交互路径（file fixture 无 irb gem，隔离 probe 未网络安装 irb）；其他 bundler 版本/Ruby 版本组合。
  **复现**：`cd C:\temp\m7b2-probe\project`（或同构 bundle）作 Case A/B/C；`cd C:\temp\m7b2-ux\project`（新建并 `bundle _4.0.24_ install`，IRB 不在 bundle）按上述隔离 env 与命令对照 `celerite exec irb --version`/`echo exit | celerite console`/`bundle _4.0.24_ exec irb --version`/`echo exit | bundle _4.0.24_ console` 及回归 `exec ruby --version`/`exec ruby -e 'puts 123'`。
  `gem`：reference `bundle _4.0.24_ gem` 提供丰富选项（`--exe/--bin/-b`、`--coc/--no-coc`、`--changelog/--no-changelog`、`--ext=c|go|rust/--no-ext`、`--git`、`--github-username`、`--mit/--no-mit`、`-t/--test=minitest|rspec|test-unit/--no-test`、`--ci/--ci=circle|github|gitlab/--no-ci`、`--linter/--linter=rubocop|standard/--no-linter`、`--edit/-e`、`--bundle/--no-bundle` 等）与交互/配置驱动模板；受控配置（`BUNDLE_GEM__COC/MIT/CHANGELOG/TEST/CI/LINTER/EXT/GIT=false`）下 `bundle gem samplegem`（`C:\temp\m7s3-gemref\samplegem`）EXIT 0 仍生成 10 文件 `.gitignore, bin/console, bin/setup, Gemfile, lib/samplegem.rb, lib/samplegem/version.rb, Rakefile, README.md, samplegem.gemspec, sig/samplegem.rbs`。
  **582b099+ 受控取证（2026-11-12，docs-only，`C:\temp\m7s3-gemref`/`C:\temp\m7s3-gemcel`/`C:\temp\m7s3-gemopts-cel`，Ruby 4.0.6 x64-mingw-ucrt/Bundler 4.0.24，shim bin `bin/celerite.exe` mtime 2026-11-12T14:45:11+08:00，未入库）逐例**：`celerite gem samplegem` EXIT 0 stdout `Creating gem 'samplegem'...`，5 文件 `Gemfile, lib/samplegem.rb, LICENSE.txt, README.md, samplegem.gemspec`；`celerite gem sample_rspec --test=rspec` EXIT 0 stderr `bundle gem options not fully supported by Celerite: --test=rspec` + `Generating a minimal scaffold only (no option-specific files/config).`，仍同 5 文件；`celerite gem sample_ci --ci=github` EXIT 0 stderr 同类 warning（`--ci=github`）+ 同 5 文件；`celerite gem`（缺名）EXIT 1 stderr `Please provide a gem name`；`celerite gem --help` EXIT 1 stderr `Please provide a gem name`（未实现 `--help` 专用路径，reference `bundle gem --help` EXIT 0）；`celerite gem sample_exists`（目录已存在）EXIT 1 stderr `Directory sample_exists already exists`。**分类**：模板/选项/`--help` 矩阵与 reference 差异大，对齐非低成本稳定，维持**显式 unsupported/未覆盖**（无 src/spec/fixture 变更）。

  `issue`（satisfied，含 lock、依赖满足）：**a482329（`fix(M7 task-2): print doctor success lines for satisfied issue`，2026-11-12，`src/celerite/cli/commands_surface.cr` +2/-0，HEAD/origin 已推送）** 在 `missing.empty?` 分支补齐输出 `The Gemfile's dependencies are satisfied` 与 `No issues found with the installed bundle`（对齐 `doctor` 与 reference satisfied issue）。手工探针（shim bin `bin/celerite.exe` mtime 2026-11-12T14:45:11+08:00，`CELERITE_PROFILE_BUNDLER_VERSION=4.0.24`）：`C:\temp\m7s3-cel-envissue2\proj`（空 lock、BUNDLED WITH 4.0.24）`celerite issue` **EXIT 0** 且尾部含两行 success；`C:\temp\m7s3-issue-nolock`（无 lock）**EXIT 10** stderr `Could not locate Gemfile`；fixture `fixtures/differential/issue-no-gemfile` **EXIT 10** 同文案；`fixtures/differential/issue-missing-gems` **EXIT 1** 含 `json_pure (2.8.1)` 与 install 提示；`fixtures/differential/env-report` `celerite env` **EXIT 0**。门禁：`crystal tool format --check src spec` EXIT 0、`crystal build --no-codegen src/cli.cr` EXIT 0（2 known deprecations `src\celerite\cli\commands_install.cr:584:43,648:20` `Deprecated File.executable?`）、`git diff --check` EXIT 0，shim build EXIT 0；`crystal spec spec/m7_console_spec.cr spec/m7_gem_spec.cr spec/m7_fund_spec.cr` **8/0/0/0 EXIT 0**。**differential rerun（shim bin，`TMPDIR=C:\temp`，env/issue 稳定集 `env-report issue-no-gemfile issue-missing-gems`）**：4.0.24（`BUNDLER_REF_VERSION=4.0.24 bash script/differential ...`）`PASS env-report (exit=0)`, `PASS issue-no-gemfile (exit=10)`, `PASS issue-missing-gems (exit=1)`, `differential (4.0.24): 3 passed, 0 failed, 0 skipped` **EXIT 0**（log `C:\temp\m7s3-diff-4024.log`）；2.7.2 同三项 **3/0/0 EXIT 0**（log `C:\temp\m7s3-diff-272.log`）。**satisfied-`issue` differential fixture 化（本子项，2026-11-12，shim bin 2026-11-12T14:45:11+08:00）**：新增 `fixtures/differential/issue-satisfied/`（`Gemfile`：`source "file:///@INDEX_DIR@"`；`Gemfile.lock`：GEM remote `file:///@INDEX_DIR@/` specs 空、PLATFORMS `x64-mingw-ucrt`、DEPENDENCIES 空、BUNDLED WITH `4.0.24`；`command`：`issue`）。`CELERITE_BIN=<repo>\bin\celerite.exe TMPDIR=C:\temp BUNDLER_REF_VERSION=4.0.24 bash script/differential issue-satisfied` **EXIT 0**，`PASS issue-satisfied (exit=0)`，`1 passed, 0 failed, 0 skipped`（log `C:\temp\issue-satisfied-4024.log`）；`BUNDLER_REF_VERSION=2.7.2` 同命令 **EXIT 0**，`PASS issue-satisfied (exit=0)`，`1 passed, 0 failed, 0 skipped`（log `C:\temp\issue-satisfied-272.log`）。**边界/未验证（582b099+ 受控探针补充，docs-only）**：`env`/`issue` 稳定集 + `issue-satisfied` 在 harness 归一化范围内双 profile 通过，但 reference vs celerite 在 N5 归一化外仍有可观察字段差异（来自 `C:\temp\m7s3-ref\` vs `C:\temp\m7s3-cel-envissue2\`，空 Gemfile+空 lock satisfied 场景，shim bin/`CELERITE_PROFILE_BUNDLER_VERSION=4.0.24`，未 rerun 归一化差分）：Bundler 行 `Bundler       4.0.24` vs `Bundler       4.0.24 (Celerite 0.1.0, compatibility profile)`；Gem Path `C:/Users/ShiningRay/.local/share/gem/ruby/4.0.0;C:/Ruby40-x64/lib/ruby/gems/4.0.0`（`;` 分隔）vs `C:/temp/m7s3-cel-envissue2/home/.local/share/gem/ruby/4.0.0, C:/Ruby40-x64/lib/ruby/gems/4.0.0`（`,` 分隔且含隔离 home 路径）；Bin Dir `C:/Ruby40-x64/bin` vs `C:/Ruby40-x64/lib/ruby/gems/4.0.0/bin`；Build Metadata Timestamp/Git SHA `2026-11-05`/`3b396e4` vs `unknown`/`bce1138`（探针时 bin）；reference 含 `## Bundler settings` 块而 celerite 该隔离 env 输出未含。`issue` 满足路径 doctor success 行在 a482329 后与 reference 对齐（`The Gemfile's dependencies are satisfied` / `No issues found with the installed bundle`）。env/issue 超出稳定 3 场景+`issue-satisfied` 的完整输出/设置组合仍**未覆盖/未验证**。
  **IRB-in-bundle/交互（582b099+，≤2 次尝试，未获稳定可用对照，阻塞+复现）**：probe `C:\temp\m7s3-irb-bundle\project`（Gemfile `gem "irb"`，Gemfile.lock 含 irb-1.18.0 + io-console/psych/rdoc/reline/erb/rbs/pp/prettyprint/prism/logger/tsort，BUNDLED WITH 4.0.24，Ruby 4.0.6/bundler 4.0.24，shim bin，`CELERITE_PROFILE_BUNDLER_VERSION=4.0.24` 无 `CELERITE_REFERENCE_BUNDLER_LIB`）。尝试 1（隔离 HOME + `BUNDLE_PATH` 指向系统 gems）：`bundle check`/`bundle exec irb --version`/`celerite exec irb --version`/`echo exit | celerite console` 均 EXIT 1 `Bundler::GemNotFound` “The following gems are missing * irb (1.18.0) * pp (0.6.4) * prism (1.9.0) * rdoc (8.1.0) * reline (0.7.0) * prettyprint (0.2.1) * erb (6.0.7) * rbs (4.2.0) * io-console (0.9.5) * logger (1.7.0)”（lock deps 未在该 bundle 上下文 materialize），非“IRB 在 bundle 内可用”场景。尝试 2（清理 BUNDLE_PATH，`GEM_PATH` 含系统 gem dir，移除 `HOME/USERPROFILE` 污染）：`celerite exec ruby --version` EXIT 0 `ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [x64-mingw-ucrt]`；`celerite exec irb --version` EXIT 1 `LoadError: cannot load such file -- fiddle/import`（`bundled_gems.rb` → `reline-0.7.0/lib/reline/io/windows.rb:1` → irb 1.18.0 加载链，Ruby 4.0 Windows reline/fiddle 依赖在该上下文未稳定可用）；`bundle`/`bundle exec` 在该 env 变体下未形成稳定可比对照（`bundle _4.0.24_` 形式出现 `Could not find command "_4.0.24_"`/路径脆弱）。**结论**：IRB-in-bundle 可用/交互路径未获低成本稳定证据（≤2 次），归类**未验证/阻塞**（需可复现安装 irb+deps 且规避 Windows/Ruby 4.0 reline-fiddle 脆弱性的受控 fixture/env）；console 交互完整对齐仍属显式未实现范围（`spec/m7_console_spec.cr`）。无代码修复。- **B:1 exec-loader 修复（2026-11-12，本子项，HEAD=`395442c` worktree，shim-built bin）**：修复 PATH/GIT source gem 安装 binstub 与 `bundle exec` 对 RubyGems 生成 shebang 的兼容性，使 `exec-loader` 与 `exec-loader-disabled` 双 profile 通过，并消除 4.0.24 全量中的 loader/.bat 类失败（B:1）。
  - **根因（M7 域内安装/bin 兼容缺口，非 harness/环境伪影）**：`src/celerite/installer.cr` `install_source_gem` 将 PATH/GIT gem 可执行文件直接复制并在 Windows 生成 6 行 LF `WinNT` `.bat`；reference Bundler/RubyGems 生成 RubyGems wrapper（`#! ruby` + `Gem.use_gemdeps`/`_version_`/`Gem.activate_and_load_bin_path` 或 `load Gem.activate_bin_path`）与 2 行 CRLF `.bat`（`@ECHO OFF\r\n@ruby.exe "%~dpn0" %*\r\n`），导致 `fixtures/differential/exec-loader` `installed-tree` 对 `ruby/4.0.0/bin/loader`、`loader.bat` 内容归一化后 diff（修复前 4.0.24/2.7.2 均 0/1/0，见 `C:\temp\celerite-diff-execloader-4024-before.log`、`C:\temp\celerite-diff-execloader-272-before.log`）。修复后 Windows `find_executable` 优先返回无扩展名 wrapper；`exec-loader-disabled`（`BUNDLE_DISABLE_EXEC_LOAD: "true"`）因 `ruby_shebang?` 不识别 `#! ruby`、无扩展名脚本被当 Win32 程序执行出现回归（`exit code: reference=42 celerite=1`，stderr `Error executing process ... 不是有效的 Win32 应用程序`，`C:\temp\celerite-diff-execloader-disabled-after.log`，sandbox `/c/temp/tmp.WNZCVKmlaD`），补充识别后恢复。
  - **源码改动**：`src/celerite/installer.cr` — PATH/GIT 安装写入 RubyGems-style wrapper（`rubygems_executable_stub`）+ CRLF `rubygems_windows_stub`，非 Windows chmod 0755。`src/celerite/cli/commands_install.cr` — `ruby_shebang?` 两重载识别 `#! ruby`（含 `\r\n`），使 `disable_exec_load`/直接 Ruby 执行路径可加载 wrapper。
  - **前后定向 differential（shim 本地 bin，`CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp`）**：修复前 `exec-loader` 4.0.24 **FAIL**（installed tree differs）0/1/0 EXIT 1；2.7.2 0/1/0 EXIT 1。修复后 4.0.24 **PASS exec-loader (exit=42)** 1/0/0 EXIT 0（`C:\temp\celerite-diff-execloader-4024-after.log`）；2.7.2 **PASS exec-loader (exit=42)** 1/0/0 EXIT 0（`C:\temp\celerite-diff-execloader-272-after.log`）。`exec-loader-disabled`：exec 修复后 4.0.24 **PASS (exit=42)** 1/0/0 EXIT 0（`C:\temp\celerite-diff-execloader-disabled-4024-after2.log`），2.7.2 **PASS (exit=42)** 1/0/0 EXIT 0（`C:\temp\celerite-diff-execloader-disabled-272-after2.log`）；2.7.2 成对 **2/0/0 EXIT 0**（`C:\temp\celerite-diff-execloader-pair-272.log`）；4.0.24 成对+原 8 FAIL 子集 **2 passed, 7 failed, 0 skipped EXIT 1**（`C:\temp\celerite-diff-execloader-reg-4024.log`，7 FAIL 全为 class A racc/make 环境阻塞：`add-group`/`add-optimistic`/`add-remove`/`add-version`/`cache-all-platforms`/`native-ext`/`native-ext-target`，`make failedNo such file or directory - make`）。
  - **4.0.24 全量 differential（本子项实跑，最终 bin）**：`CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential` → **130 fixtures, 123 passed, 7 failed, 0 skipped, wrapper exit 1**（`C:\temp\celerite-diff-full-4.0.24-execloader-final.log`，mtime 2026-11-12 08:02:07，299 行；123+7=130 全跑）。7 FAIL 全部 class A racc/make（同上 7 名）；**`exec-loader` 与 `exec-loader-disabled` 均 PASS (exit=42)**，无 loader/.bat 类失败。较 128-fixture 120/8/0 按实测计数 **+3 passed / -1 failed / +2 fixtures**（fixture 集合随仓库演进），按名字无新增失败。
  - **2.7.2 全量**：**未重跑（未验证）**，复现：`BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`。
  - **验证/门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（2 known deprecation warnings `src\celerite\cli\commands_install.cr:567:43,631:20` `Deprecated File.executable?`）；`git diff --check` EXIT 0；M7 子集 `crystal spec spec/m7_reverse_dependencies_spec.cr spec/m7_installed_discovery_spec.cr spec/m7_platform_match_spec.cr spec/m7_ruby_constraints_spec.cr spec/m7_resolver_ruby_constraints_spec.cr spec/ruby_version_spec.cr spec/m7_ruby_runtime_spec.cr spec/m7_platform_spec.cr` **70 examples, 0 failures, 0 errors, 0 pending, EXIT 0**。shim bin 本地重建（未入库）：`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"` BUILD_EXIT=0，`bin/celerite.exe --version` 0.1.0；stock OpenSSL `EVP_MD_size` 阻塞与 shim 仅本地持续记录。

- **2.7.2 全量 differential（修复前基线，2026-11-12 08:34–08:45 CST，HEAD=`20690ff`，shim 本地 bin，已实跑）**：130 fixtures，**121 passed / 8 failed / 1 skipped（documented deferral），wrapper exit 1**；命令 `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`；log `C:\temp\celerite-diff-full-2.7.2-20690ff.log`（12228 bytes，mtime 08:45:20，293 lines，末行 `differential (2.7.2): 121 passed, 8 failed, 1 skipped (documented deferrals)`）。FAIL 8：class A racc/make 6（`add-optimistic`、`add-remove`、`add-version`、`cache-all-platforms`、`native-ext`、`native-ext-target`，ref=0/cel=1，`extension build failed for racc-1.8.1`/`make` 不可用，环境阻塞，与 4.0.24 同名项一致）+ class C clean 输出 2（`clean-force`、`clean-unused`：当时 2.7.2 下 stdout 缺 `Removing <name> (<version>)`，4.0.24 全量中两者 PASS）。SKIP 1：`add-group`（harness documented deferral：`reference 2.7.2 auto-installs Bundler 4.0.24 from rubygems.org (network-required); offline sandbox cannot prove this path`；4.0.24 全量中 `add-group` 为 class A FAIL）。
- **Class C `clean-force`/`clean-unused` 修复与 2.7.2 全量复测（2026-11-12，HEAD=`8d20c17`，shim 本地 bin，已实跑）**：根因——2.7.2 profile `bundle clean` 在 fixture 行为上移除 BUNDLE_PATH 下已安装 gem（含 lockfile 中 gem）并输出 `Removing <name> (<version>)`（KEEP_DIFFERENTIAL 证据：`/c/temp/tmp.IfRBIUQ33n` clean-force、`/c/temp/tmp.gv4YXooyBD` clean-unused，ref side `ruby/4.0.0/{gems,specifications,cache,bin}` 清空、cel side 仍保留，`C:\temp\celerite-diff-clean-c-272.log` stdout 仅缺 Removing 行）；celerite `clean` 原以 lockfile specs 作为 keep set（`src/celerite/cli/commands_install.cr`），在 2.7.2 profile 下语义不兼容。修复（commit `8d20c17`）：`CELERITE_PROFILE_BUNDLER_VERSION` 为 2.7.x 时 clean 使用空 keep set 且不保留 locked git checkout base（4.0.24 路径不变）。**前后定向 differential**：修复前 2.7.2 `clean-force`/`clean-unused` **0/2/0 EXIT 1**（`C:\temp\celerite-diff-clean-c-272.log`）；4.0.24 control **2/0/0 EXIT 0**（`C:\temp\celerite-diff-clean-c-4024.log`）。修复后 2.7.2 **2/0/0 EXIT 0**（`C:\temp\celerite-diff-clean-c-272-after.log`，`PASS clean-force (exit=0)`、`PASS clean-unused (exit=0)`）；4.0.24 **2/0/0 EXIT 0**（`C:\temp\celerite-diff-clean-c-4024-after.log`）。**全量复测（实测）**：命令 `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`（log `C:\temp\celerite-diff-full-2.7.2-8d20c17.log`，12029 bytes，mtime 2026-11-12 10:12:15，末行 `differential (2.7.2): 123 passed, 6 failed, 1 skipped (documented deferrals)`，wrapper DIFF_FULL_EXIT=1）；130 fixtures，**123 passed / 6 failed / 1 skipped**。FAIL 6（均 class A racc/make，环境阻塞，ref=0/cel=1，`extension build failed for racc-1.8.1`/`make failedNo such file or directory - make`）：`add-optimistic`（`add racc --optimistic`）、`add-remove`（install/add racc/remove racc；stdout 同时见 `racc (~> 1.8) was removed.` vs `racc was removed.` 差异）、`add-version`（`add racc --version=1.8.1`）、`cache-all-platforms`（`cache --all-platforms`）、`native-ext-target`（install --target-rbconfig/exec ruby inline.rb）、`native-ext`（install/exec ruby inline.rb）。SKIP 1：`add-group`（documented deferral，同前）。与修复前 130:121/8/1（20690ff）按名对比：`clean-force`、`clean-unused` 由 FAIL→PASS，其余 FAIL/SKIP 集合不变；与 4.0.24 全量 130:123/7/0 对比：2.7.2 仅 A:6 racc/make + SKIP 1（add-group 在 4.0.24 为 A:7 FAIL 之一，形态因 harness deferral 不同），`exec-loader`/`exec-loader-disabled` 双 profile 全量 PASS。**验证/门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（2 known deprecation warnings `src\celerite\cli\commands_install.cr:577:43,641:20` `Deprecated File.executable?`）；`git diff --check` EXIT 0；M7 子集 70 examples, 0 failures, 0 errors, 0 pending EXIT 0；shim bin 本地重建（未入库）BUILD_EXIT 0 / 0.1.0 / VER_EXIT 0。
- **Still unverified**: release-form/published-binary behavior,
  M7(1) remaining matrix (ABI positive variants beyond the local
  x64-mingw-ucrt arch; Gemfile target Ruby without lock `RUBY VERSION` with
  dependencies satisfied; other `check`/`list`/`show`/`info`
  re-resolve-notification scenarios beyond the pinned missing-deps fixtures
  and the patchlevel-unlock `check`/`list` fixtures),
  M7(2): `Reverse Dependencies` 已补 path-source differential/spec 证据（`info-reverse-dependencies-path` 4.0.24/2.7.2 各 1/0/0 EXIT 0，`spec/m7_reverse_dependencies_spec.cr` 4/0/0/0，M7(2) 回归定向集 `info-reverse-dependencies-path check-path list-path git-installed-discovery show-info-installed list-multi-group` 双 profile 各 6/0/0 EXIT 0，M7 子集 8 文件 70/0/0/0 EXIT 0，commit `ae8eafc`，shim 本地 bin）且 `info` path gemspec 元数据回退已修复；`Default Gem` 标记稳定取证仍受默认 gem 布局/安装态与 differential sandbox 隔离限制（**未验证**）。**B1 取证（2026-11-12，已试≤2，未修代码）**：`C:\temp\defaultgem-test2`（Gemfile pin `json 2.15.1`，Ruby 4.0.6 default gem dir 含 `json-2.15.1`）手工对照探针中 `celerite install --local`/`install` 多次失败 `celerite internal error: SSL_CTX_load_verify_locations: error:80092004:system library::Unknown error` EXIT 1（含设 `SSL_CERT_FILE=C:/msys64/ucrt64/ssl/cert.pem` 仍失败），无法完成安装后 bundle-vs-celerite 对照；`script/differential` 隔离 GEM_HOME/GEM_PATH/BUNDLE_PATH 与本地 file index 难以稳定构造可差分 fixture（阻塞，复现见上述命令/路径与 `bundle _4.0.24_ info json` 基线探测）。path/Git + `--with/--without/--only-group`/平台组合仍未穷尽。M7(3):
  `fund-path` differential 已在 4.0.24/2.7.2 取证，但 `env`/`issue` 全量输出
  与 Bundler reference 的 differential 尚未 fixture 化，`console` IRB 可用/交互
  路径与 `gem` 完整模板/选项矩阵差分未覆盖（详见“M7(3) 部分修复”证据）。

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

- **M7(2) 补强（2026-11-12，HEAD=`f3ad8a5` worktree，commit `ae8eafc` 已推送，shim-built bin）**：修复 `src/celerite/cli/commands.cr` `read_gemspec_info` 的 PATH/GIT gemspec 元数据回退（安装 `specifications`/abi 目录未命中时读取 `gem_dir` 下 gemspec；`File.file?`/`Dir.exists?`/目录遍历加 `rescue`，修复 Windows 临时路径 `File::Error` 导致 spec 失败），使 path gem `info` 输出 `Summary` 等元数据。新增 `fixtures/differential/info-reverse-dependencies-path/`（`lock\ninfo dependee`；path gems `depender`→`dependee`，校验 `Reverse Dependencies`/`Path`/`Summary`）：4.0.24 **`differential (4.0.24): 1 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0**（log `/c/temp/celerite-diff-rdep-4024.log`），2.7.2 **`differential (2.7.2): 1 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0**（log `/c/temp/celerite-diff-rdep-272.log`）。新增 `spec/m7_reverse_dependencies_spec.cr` **4 examples, 0 failures, 0 errors, 0 pending, EXIT 0**（path-source reverse dependencies + path gemspec Summary；leaf 无 `Reverse Dependencies:`；`check --without-group` 忽略缺失 test 组 path gem；`list --without-group` 仅列 included path gem）。M7(2) 回归定向集 `info-reverse-dependencies-path check-path list-path git-installed-discovery show-info-installed list-multi-group`：4.0.24 **6/0/0 EXIT 0**（log `/c/temp/celerite-diff-m72-reg-4024.log`），2.7.2 **6/0/0 EXIT 0**（log `/c/temp/celerite-diff-m72-reg-272.log`）。M7 子集 spec（8 文件：`spec/m7_reverse_dependencies_spec.cr spec/m7_installed_discovery_spec.cr spec/m7_platform_match_spec.cr spec/m7_ruby_constraints_spec.cr spec/m7_resolver_ruby_constraints_spec.cr spec/ruby_version_spec.cr spec/m7_ruby_runtime_spec.cr spec/m7_platform_spec.cr`）**70 examples, 0 failures, 0 errors, 0 pending, EXIT 0**（Finished in 14.65 seconds）。Gates：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（2 known deprecation warnings `src\celerite\cli\commands_install.cr:567:43,631:20` `Deprecated File.executable?`）；`git diff --check` EXIT 0。shim 本地 bin 重建（未入库，`bin/` gitignored）：`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"` BUILD_EXIT 0，`bin/celerite.exe --version` 0.1.0，mtime 2026-11-12 05:51:53。`Default Gem` 标记稳定差分/spec 证据 **未验证**（本地 `bundle _4.0.24_ info json` 未输出 `Default Gem: yes`，shim `celerite info json` 在未安装到 bundle 的默认 gem 场景 EXIT 7 缺失；复现：`bundle _4.0.24_ info json` 与 `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp celerite info json` 在可控 default-gem 发现场景对照）。

## M7(1)-(3) 阶段性闭环汇总（事实快照，14ccb9d/5949cc2 docs 基线 + b4fe095 B2 同步 + a482329/582b099 M7(3) issue/env/gem/IRB 边界证据同步，2026-11-12）

> 范围：仅 M7(1) Ruby/平台/引擎/patchlevel/元数据约束与通知、M7(2) 安装后 gem 发现、M7(3) 占位路径真实化/显式 unsupported。依据仓库已提交证据（`docs/roadmap.md`、`docs/compat-report.md`、`docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`、`spec/`、`fixtures/differential/` 与 commit 记录）与前序/本轮可复核实测。**当前 HEAD=`0423b2f66aec54ae78a9f6aa1667efebdad018ce`（docs 证据同步至该 HEAD；M7(1)-(3) 实现证据快照源头至 `0fabf9e36b5463bd17ad9f591d3e10f3f8f15f2c` `fix(M7 task-2): print lock-ruby unlock notice before empty-deps return in list`，已推送 `origin/main`）**：`a482329` 补齐 satisfied `issue` doctor success 行，`340f050` docs 同步，`582b099` 新增 `issue-satisfied` fixture 并双 profile 1/0/0 PASS，`0fabf9e` 修复 `list` 空 deps 早返回前打印 lock-ruby unlock notice 并 fixture 化 B3 两分支（check/list satisfied+missing）双 profile 4/0/0 PASS。**582b099 后追加受控探针（docs-only，2026-11-12，`6488b8a`）**：`gem` 模板/选项/`--help` 行为与 env/issue 归一化外字段差异取证、IRB-in-bundle 尝试（≤2 次，未获稳定可用对照，阻塞+复现）。`b5cfa51`/`0423b2f` 为 docs 汇总/对齐提交（本子项同步证据与边界至 HEAD `0423b2f`）。本节计数/全量差分仍沿用既有可复核实测，**未在 5949cc2/b4fe095/a482329/582b099/0fabf9e 及后续 docs-only 提交后重跑全量 differential 或 M7 spec 子集**；M7(1)-(3) 复选框保持未勾选，**不得视为 M7 整体验收通过**。

### 1) 证据索引

| 类别 | 证据（commit / 路径 / 日志） | 计数/结论（与实测一致） |
|---|---|---|
| 关键 commit（至 HEAD） | `a8753b6`、`f168d6f`、`7c446d9`、`3c4f55d`、`34a8cad`、`f3ad8a5`、`ae8eafc`、`20690ff`、`8d20c17`、`bdd0ca6`、`0032664`、`14ccb9d`、`5949cc2`、`8f1ef39`、`b4fe095`、`7a4f1bc`、`bce1138`、`a482329`、`340f050`、`582b099`、`0fabf9e`、`6488b8a`、`b5cfa51`、`0423b2f` | 实现/fixture/spec/差分修复与文档证据链；`14ccb9d`/`8f1ef39`/`7a4f1bc`/`bce1138`/`340f050`/`6488b8a`/`b5cfa51`/`0423b2f` 为 docs 同步/汇总；`5949cc2`/`b4fe095` 修复 B2 exec/console；`a482329` 修复 satisfied `issue` doctor success 行；`582b099` 新增 `fixtures/differential/issue-satisfied` 并双 profile 1/0/0 PASS；`6488b8a` 追加 gem/env-issue 字段/IRB-in-bundle 受控探针记录（docs-only，未重跑全量差分/子集 spec） |
| M7 子集 spec（既有实测，未重跑） | `spec/m7_reverse_dependencies_spec.cr spec/m7_installed_discovery_spec.cr spec/m7_platform_match_spec.cr spec/m7_ruby_constraints_spec.cr spec/m7_resolver_ruby_constraints_spec.cr spec/ruby_version_spec.cr spec/m7_ruby_runtime_spec.cr spec/m7_platform_spec.cr` | **70 examples, 0 failures, 0 errors, 0 pending, EXIT 0**（`ae8eafc` 轮，14.65s） |
| M7(3) spec（既有实测，未重跑） | `spec/m7_console_spec.cr spec/m7_gem_spec.cr spec/m7_fund_spec.cr` | **8 examples, 0 failures, 0 errors, 0 pending, EXIT 0** |
| M7(2) 定向回归（既有实测） | `info-reverse-dependencies-path check-path list-path git-installed-discovery show-info-installed list-multi-group`（双 profile） | 4.0.24 **6/0/0 EXIT 0**、2.7.2 **6/0/0 EXIT 0**（`ae8eafc`） |
| M7(3) env/issue 稳定集 + satisfied-issue（`34a8cad`/a482329/582b099） | `env-report issue-no-gemfile issue-missing-gems` 双 profile 3/0/0（`C:\temp\m7s3-diff-4024.log`/`C:\temp\m7s3-diff-272.log`，shim bin 2026-11-12T14:45:11+08:00，harness N5）+ `fixtures/differential/issue-satisfied` 双 profile **PASS (exit=0) 各 1/0/0**（`C:\temp\issue-satisfied-4024.log`/`C:\temp\issue-satisfied-272.log`，582b099） | 4.0.24 3/0/0 + 1/0/0；2.7.2 3/0/0 + 1/0/0；稳定集无回归，satisfied-issue 已 harness 归一化验证 |
| M7 定向扩展 2.7.2（既有实测） | M7 相关扩展定向集 | **36/36 PASS, EXIT 0**（`7c446d9`） |
| 4.0.24 全量 differential（既有实测，未重跑） | `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`，shim-built bin；log `C:\temp\celerite-diff-full-4.0.24-execloader-final.log`（2026-11-12 08:02:07，299 行） | **130 fixtures, 123 passed, 7 failed, 0 skipped, wrapper exit 1**。FAIL（A:7 racc/make，`make failedNo such file or directory - make`）：`add-group`、`add-optimistic`、`add-remove`、`add-version`、`cache-all-platforms`、`native-ext-target`、`native-ext`。`exec-loader`/`exec-loader-disabled` PASS；较早期 128:120/8/0 按实测计数 +3/-1/+2，按名字无新增失败 |
| 2.7.2 全量 differential（既有实测，未重跑） | `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`；log `C:\temp\celerite-diff-full-2.7.2-8d20c17.log`（2026-11-12 10:12:15 CST，12029 bytes） | **130 fixtures, 123 passed, 6 failed, 1 skipped, wrapper exit 1**。FAIL（A:6）：`add-optimistic`、`add-remove`、`add-version`、`cache-all-platforms`、`native-ext`、`native-ext-target`。SKIP 1：`add-group`（harness documented deferral，network-required）。对比 `bdd0ca6`/`20690ff` 前 130:121/8/1：class C `clean-force`/`clean-unused` 已转绿（`8d20c17`），按名字无新增失败；与 4.0.24 对比少 `add-group` FAIL 因 2.7.2 profile 下该 fixture 为 SKIP |
| 代表性 fixtures（部分） | `fixtures/differential/info-reverse-dependencies-path`、`env-report`、`issue-no-gemfile`、`issue-missing-gems`、`fund-path`、`check-missing-ruby-nolock`、`list-missing-ruby-nolock`、`ruby-*`/`rubygems-*` metadata & boundary、`multi-platform-install`、`git-installed-discovery`、`show-info-installed`、`list-multi-group`、`check-path`/`list-path` 等 | 见上文 M7(1)-(3) 分项与 generated differential 报告 |

### 2) 已覆盖与达成（按 M7(1)/(2)/(3)）

- **M7(1) 约束过滤 / install recheck / lock reuse / re-resolve 通知（部分）**：`RubyVersion`/`RubyRuntime`、`RubyVersionMismatch` exit 18、Gemfile `ruby` 结构化选项（version/engine/engine_version/patchlevel）与 bridge patchlevel、gem metadata `required_ruby_version`/`required_rubygems_version` 过滤、SolveFailure exit 6 vs GemNotFound exit 7 区分、平台 mismatch 文案/正反例、`lock --add-platform`+install+check（`multi-platform-install`）等已实现并有 spec/fixture 证据；B3 nolock deps-satisfied 通知已 fixture 化：`check-satisfied-ruby-nolock` + `check-missing-ruby-nolock`（lock 无 `RUBY VERSION`，Gemfile 声明 `ruby "4.0.6"`）双 profile **4/0/0 PASS EXIT 0**（`0fabf9e`，含 list 空 deps 早返回前通知修复）；`ruby-patchlevel-match-list`、`check-missing-ruby-nolock`/`list-missing-ruby-nolock` 等通知/缺依赖场景已 fixture 化；`exec-loader`（B:1，PATH/GIT binstub/shebang 对齐）已修复并在 4.0.24 全量中转绿（双 profile 定向 PASS，`20690ff`）。
- **M7(2) 安装后发现（部分）**：`installed_gem_dir` 容忍缺 specifications、`show --paths`/`list` 格式与 git 短 revision/路径渲染对齐、group/`--with`/`--without`/`--only-group`（含空格分隔多组与 `BUNDLE_WITH`）/PATH/GIT/平台特定 gem 发现已有 spec 与 differential 覆盖；`read_gemspec_info` PATH/GIT gemspec 元数据回退与 Windows 路径 `rescue` 加固使 path gem `info` 可显示 Summary/metadata（`ae8eafc`）；`info-reverse-dependencies-path` 双 profile PASS、`spec/m7_reverse_dependencies_spec.cr` 4/0 覆盖 reverse dependencies 与 `check/list --without-group` 排除缺失 test 组 path gem。
- **M7(3) 占位路径真实化 / 显式 unsupported（部分）**：`fund` 读取 installed specs/`.gem` metadata 与 PATH/GIT gemspec `funding_uri`（`fund-path` 双 profile PASS，`spec/m7_fund_spec.cr` 3/0）；`env`/`issue` Build Metadata 与 timestamp/git_sha 行为（非 git cwd `Timestamp unknown`）已实现。**a482329（`src/celerite/cli/commands_surface.cr` +2/-0，2026-11-12，已推送）** 修复 satisfied `issue`（含 lock、依赖满足）缺失 doctor success 行（现输出 `The Gemfile's dependencies are satisfied` / `No issues found with the installed bundle`，对齐 `doctor`/reference）；env/issue 稳定集 `env-report`+`issue-no-gemfile`+`issue-missing-gems` **a482329 后本轮 shim bin 复跑**：4.0.24 `3/0/0 EXIT 0`、2.7.2 `3/0/0 EXIT 0`（`script/differential ...`，log `C:\temp\m7s3-diff-4024.log`/`C:\temp\m7s3-diff-272.log`）。`console` IRB 缺失 PATH 明确 stderr+EXIT 127（`spec/m7_console_spec.cr` 1/0）为显式 unsupported 边界；`gem` 最小 scaffold（6 文件）与不支持选项 warning+降级行为（`spec/m7_gem_spec.cr` 4/0）已取证（完整模板/选项矩阵仍未覆盖）。**B2（5949cc2 + b4fe095 + subitem 2）**：5949cc2 修复 Windows PATH casing（回报/未独立重跑：`exec ruby` 127→0）但 `exec irb`/`console` 仍因 `bundler_lib`/setup 解析错误转为 EXIT 1 `LoadError .../bundler/setup`；b4fe095（`src/celerite/cli/commands_install.cr` +22/-4，`find_bundler_lib` 从 gem paths/default/user gem dir 发现 `<dir>/gems/bundler-<version>/lib/bundler/setup.rb`，保留 `CELERITE_REFERENCE_BUNDLER_LIB` 优先，始终注入 `BUNDLER_VERSION`）在受控 probe（`C:\temp\m7b2-probe\project`，4.0.24，shim 本地 bin）Case A 无 REF_LIB 且 bundler gem 可见时：`exec ruby --version`/`exec ruby -e "puts 123"` EXIT 0，`exec irb --version`/`echo exit | celerite console` EXIT 1 Gem::Exception “irb not in bundle”，与 `bundle _4.0.24_ exec irb --version`（Case B）同类对齐。残留未对齐/未验证：`bundle console`（IRB 不在 bundle）EXIT 1 为 LoadError+Bundler 环境报告，`celerite console` 仍返回 Gem::Exception（UX 未完全对齐）；IRB 在 bundle 内且可用时 `exec irb`/`console` 行为与交互路径未验证；Case C（bundler gem 不可见且无 REF_LIB）为 `BUNDLER_VERSION` 激活环境/配置约束；satisfied-issue differential fixture 未创建、`env`/`issue` 其余字段/设置/元数据/profile 标识等与 reference 差异及全量输出边界仍未验证；4.0.24/2.7.2 全量与 M7 子集 spec 未在 b4fe095/a482329 后重跑。**命令入口存在不等同功能完成** 的边界持续成立（B1/B2/B3）。

### 3) 缺口与未验证（不得冒充完成）

| 分项 | 缺口 / 未验证 | 状态 |
|---|---|---|
| M7(1) | 本地 x64-mingw-ucrt 外 ABI/平台变体/gnu-musl/多 Ruby 矩阵穷举；`show`/`info` 其他重解通知场景；更多 engine/engine_version/patchlevel 与 lock-reuse 组合 | **未验证**（未实跑/未 fixture 化） |
| M7(1)/B3 | Gemfile 声明 `ruby` 但 lock 无 `RUBY VERSION` 时 `check`/`list` `Resolving dependencies...` 通知（deps satisfied/missing 两分支） | **已 fixture 化并修复 list**（`check-satisfied-ruby-nolock` + `check-missing-ruby-nolock`，lock 无 `RUBY VERSION`，Gemfile 声明 `ruby "4.0.6"`；`src/celerite/cli/commands.cr` 修复 list 空 deps 早返回前打印通知）：4.0.24/2.7.2 **4/0/0 PASS EXIT 0**（check-satisfied/list-satisfied/check-missing/list-missing，log `C:\temp\m7s3-nolock-satisfied-4024.log`/`-272.log`）；`Resolving dependencies...` 在 satisfied/missing 两分支均 firing 且与 reference 对齐。未 fixture 化残余：`show`/`info` 其他重解通知场景（Gemfile ruby decl vs lock，非 B3 这两项） |
| M7(2)/B1 | `Default Gem` 稳定差分/spec 取证（`info`/`show` `Default Gem: yes` 等） | **未验证**（环境/ harness 限制 + 探针阻塞） |
| M7(2) | path/GIT + `--with/--without/--only-group`/平台组合补强；Reverse Dependencies 更多来源形态/输出边界 | **未验证/覆盖有限** |
| M7(3) | satisfied-`issue` 已 fixture 化（582b099，双 profile 1/0/0 PASS）且 env/issue 稳定集 3/0/0 无回归；582b099+ 受控探针已取证 env/issue 归一化外字段差异（profile 标识/Gem Path/Bin Dir/Build Metadata/settings 块）与 IRB-in-bundle（≤2 次未获稳定可用对照）边界/阻塞+复现 | **部分进展、仍有未验证/阻塞**：稳定集+`issue-satisfied` 外完整输出/设置组合、IRB-in-bundle 可用/交互路径、其余场景仍未全量验证 |
| M7(3)/B2 | `console` 在 IRB 不在 bundle 时与 reference `bundle console` UX/错误形态对齐；IRB 在 bundle 内且可用时 `exec irb`/`console` 行为与交互路径；Case C（bundler gem 不可见且无 `CELERITE_REFERENCE_BUNDLER_LIB`）下激活策略 | **部分进展、未闭环**：b4fe095 修复 `bundler_lib`/setup 发现与 `BUNDLER_VERSION` 注入后，Case A `exec ruby`/`-e` EXIT 0 且 `exec irb` 在 IRB 不在 bundle 时与 `bundle exec irb` 同类 Gem::Exception（受控 probe，未独立重跑全量）；subitem 2（2026-11-12，`C:\temp\m7b2-ux`，≤2 次尝试）取证：`celerite console` 仍返回 Gem::Exception 而 `bundle console` 返回 LoadError+Bundler 环境报告（UX 未对齐，exec-irb 路径语义差异），对齐技术可行但非低成本/有契约与回归风险（`spec/m7_console_spec.cr` 固定 IRB 缺失 PATH 行为），**未改代码、归类残留阻塞**；IRB-in-bundle/交互、Case C 环境约束处理未验证/未覆盖 |
| M7(3) | `gem` 完整模板/选项/`--help` 矩阵（ref 10 文件+丰富选项 vs celerite 固定 5 文件最小 scaffold；`--test`/`--ci` 等仅 warning 仍同 scaffold；`gem`/`--help` EXIT 1 `Please provide a gem name`） | **显式 unsupported/未覆盖**（582b099+ 受控取证 `C:\temp\m7s3-gemref/gemcel/gemopts-cel`，docs-only，非低成本对齐） |
| 全量差分 | 4.0.24/2.7.2 全量与 M7 spec 子集未在 5949cc2/b4fe095/a482329/582b099 及本子项后重跑 | **未重跑（引用既有）**；582b099 增 `issue-satisfied` 双 profile 1/0/0 PASS；本子项追加 gem/env-issue 字段/IRB-in-bundle 受控探针（docs-only）；既有全量计数仍引用 HEAD≤8d20c17/20690ff 实测日志 |

### 4) 阻塞与复现（已试≤2 的取证/阻塞记录）

| 项 | 阻塞/现象 | 已试与证据 | 精确复现/指引 |
|---|---|---|---|
| stock OpenSSL 构建 | Crystal 1.22.1 链接 `EVP_MD_size`，MSYS2 ucrt64 OpenSSL 3.6.5 导出 `EVP_MD_get_size`，stock `crystal build src/cli.cr` 失败 | CLI/diff 改用仓库外 shim 本地 bin（`C:\Users\ShiningRay\AppData\Local\Temp\celerite-shim-m7wip\evp_md_size_shim.c` + `--link-flags ...evp_md_size_shim.o`）；`bin/` gitignored，shim 未入库 | `crystal build src/cli.cr`（stock 失败）；本地构建：`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:\Users\ShiningRay\AppData\Local\Temp\celerite-shim-m7wip\evp_md_size_shim.o"` |
| 4.0.24 全量残余 | 7 FAIL（A:7 racc/make） | 引用既有 log `C:\temp\celerite-diff-full-4.0.24-execloader-final.log`（130:123/7/0, exit 1） | `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential` |
| 2.7.2 全量残余 | 6 FAIL（A:6）+ 1 SKIP `add-group`（network-required deferral） | 引用既有 log `C:\temp\celerite-diff-full-2.7.2-8d20c17.log`（130:123/6/1, exit 1, 12029 bytes） | `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential` |
| B1 Default Gem（M7(2)） | default-gem 布局/安装态 + differential sandbox 隔离；手工安装对照受内部错误阻塞 | `C:\temp\defaultgem-test2`（Gemfile pin `json 2.15.1`，Ruby 4.0.6 default gem dir 含 `json-2.15.1`）：`celerite install --local`/`install` 多次失败 `celerite internal error: SSL_CTX_load_verify_locations: error:80092004:system library::Unknown error` EXIT 1（含 `SSL_CERT_FILE=C:/msys64/ucrt64/ssl/cert.pem` 仍失败）；`script/differential` 隔离 GEM_HOME/GEM_PATH/BUNDLE_PATH 与本地 file index 难稳定构造可差分 fixture；对照 `bundle _4.0.24_ info json` 未输出 `Default Gem: yes`，未安装场景 shim `celerite info json` EXIT 7。**未修代码，已试≤2 后停止重试** | 同上命令/环境（`C:\temp\defaultgem-test2`，`CELERITE_BIN` 指向 shim bin，PATH 含 Ruby/msys2）；需可控 default-gem 发现场景或 harness 扩展 |
| B2 console/exec（M7(3)） | 5949cc2 修复 PATH casing 后 b4fe095 修复 `bundler_lib`/setup 发现与 `BUNDLER_VERSION` 注入；subitem 2 评估 console（IRB 不在 bundle）UX 与 `bundle console` 对齐可行性 | **5949cc2**：规范化 PATH key（+9/-1）；修复前 ≤14ccb9d 探针 `C:\temp\defaultgem-test` 下 `exec ruby -e`/`exec irb --version`/`console` EXIT 127；5949cc2 后回报 `exec ruby --version` EXIT 0、`exec irb`/`console` EXIT 1 `LoadError ... C:\Ruby40-x64\lib\bundler/setup`（未独立重跑）。**b4fe095**（+22/-4，`find_bundler_lib`+始终注入 `BUNDLER_VERSION`，保留 `CELERITE_REFERENCE_BUNDLER_LIB` 优先）：受控 probe `C:\temp\m7b2-probe\project`（Gemfile json_pure 2.8.1, lock BUNDLED WITH 4.0.24, isolated env, `bundle _4.0.24_ install` EXIT 0, Ruby 4.0.6, shim bin mtime 13:18:52）。Case A（无 REF_LIB，GEM_PATH 含系统 gem dir）：`exec ruby --version` EXIT 0、`exec ruby -e "puts 123"` EXIT 0、`exec irb --version` EXIT 1 Gem::Exception “irb not in bundle”、`echo exit \| console` EXIT 1 同类。Case B（reference）：`bundle exec irb --version` EXIT 1 同类 Gem::Exception（对齐），`echo exit \| bundle console` EXIT 1 LoadError+Bundler 环境报告（celerite console 未对齐）。Case C（GEM_PATH 无 bundler-4.0.24 gem，无 REF_LIB）：`exec ruby -e "puts 123"` EXIT 1 `Could not find 'bundler' (= 4.0.24)`（环境约束）。门禁 format/no-codegen/diff-check EXIT 0，shim build EXIT 0（2 known deprecations）。**subitem 2（2026-11-12，≤2 次尝试，未改代码）**：probe `C:\temp\m7b2-ux\project`（IRB 不在 bundle，bundle satisfied）显示 `bundle exec irb`/`celerite exec irb` 均 EXIT 1 Gem::Exception 对齐，`bundle console` EXIT 1 LoadError+Bundler 环境报告 vs `celerite console` EXIT 1 Gem::Exception 未对齐；回归 `exec ruby --version`/`exec ruby -e "puts 123"` EXIT 0；可行性探针可复现 reference console 语义但对齐需 bundler console 专用调用/发现且触及 `spec/m7_console_spec.cr` 契约与 IRB-in-bundle/交互未验证风险，**判定非低成本、归类实现语义差异/残留阻塞**。**未验证**：IRB 在 bundle 内/交互、Case C 规避策略、全量/子集未重跑；本节外探针未全部独立重跑。 | 探针复现：`C:\temp\m7b2-probe\project`（Case A/B/C，见 B2 节）；`C:\temp\m7b2-ux\project`（json_pure-only bundle，IRB 不在 bundle，隔离 env，`bundle _4.0.24_ install`）运行 `bundle _4.0.24_ exec irb --version`、`celerite exec irb --version`、`echo exit \| bundle _4.0.24_ console`、`echo exit \| celerite console`、`celerite exec ruby --version`、`celerite exec ruby -e 'puts 123'`。 |
| B3 nolock deps-satisfied 通知（M7(1)/(2)） | 依赖已满足 + lock 无 `RUBY VERSION` 的 `Resolving dependencies...` 通知无法固化为 differential fixture | 手工 harness-like 取证（probe base `C:\temp\nolock-sat-harnesslike-eZPd5c`，预置 BUNDLE_PATH gems+specifications，Gemfile `ruby "4.0.6"`，lock 无 `RUBY VERSION`，bridge/profile 同 harness）：ref 4.0.24/2.7.2 与 shim celerite `check`/`list` 均输出 `Resolving dependencies...` 后 EXIT 0；`script/differential` 缺少“命令前预填充 BUNDLE_PATH 且保留无 `RUBY VERSION` lock” primitive | 按 probe 条件手工对照；或扩展 harness 后新增 fixture |
| bridge 不可用 | runtime 校验 best-effort 跳过 | 设计/历史记录约束 | 任何 bridge 不可用结论不得视为通过 |

### 5) task-2 收口建议与剩余风险（供首辅裁断）

- **当前可行闭环程度（事实）**：M7(1) 约束/过滤/通知与安装复核的大量正反例、`exec-loader` B:1 修复、M7(2) 安装后发现（含 path/GIT reverse-dependencies）与 M7(3) fund/env/issue 稳定集（含 `fixtures/differential/issue-satisfied` 双 profile 1/0/0 PASS，582b099）均已有可复核 spec/fixture/differential 或 CLI 证据；582b099+ 本子项受控探针补充 `gem` 模板/选项/`--help`（显式 unsupported，`C:\temp\m7s3-gemref/gemcel/gemopts-cel`）与 env/issue 归一化外字段差异（`C:\temp\m7s3-ref`/`m7s3-cel-envissue2`）证据，IRB-in-bundle/交互 ≤2 次尝试未获稳定可用对照（`C:\temp\m7s3-irb-bundle\project`，materialization/reline-fiddle 依赖链阻塞，未验证+复现）。双 profile 全量在既有实测中为 4.0.24 **130:123/7/0**、2.7.2 **130:123/6/1**（A:racc/make 与 2.7.2 `add-group` deferral，未在 5949cc2/b4fe095/a482329/582b099/本子项后重跑）。B2 `exec ruby`/IRB-not-in-bundle exec-irb 已对齐（5949cc2+b4fe095），console UX exec-irb 语义差异残留阻塞（bce1138）；Case C 环境约束未变。B1 Default Gem、B3 nolock deps-satisfied 通知、`gem` 完整矩阵、env/issue 稳定集外完整输出、ABI/平台矩阵等关键缺口仍**显式 unsupported/未验证/未闭环**。
- **收口建议（基于证据，供裁断）**：**不建议**在当前证据下宣告 M7(1)-(3) 整体验收收口或勾选 roadmap M7 复选框；task-2 保持 `in_progress`。582b099 已 fixture 化 satisfied-issue，本子项已固化 gem/env-issue 字段/IRB-in-bundle 边界 probe 证据；由首辅裁断是否在承认剩余风险/阻塞前提下阶段性挂起并启动 task-3，或继续派工补强可行子项/阶段验收汇总。
- **若阶段性挂起/收口的剩余风险**：IRB-in-bundle 可用/交互路径（本子项 ≤2 次未获稳定对照）、console UX（IRB 不在 bundle，非低成本对齐）、Case C bundler gem 激活策略、`gem` 完整模板/选项/`--help` 矩阵、env/issue 归一化外字段与稳定集+`issue-satisfied` 外完整输出、B1 Default Gem、B3 nolock deps-satisfied 通知、ABI/平台/gnu-musl 等仍缺 green 可比证据；全绿 differential 仍受本机 `make`/stock OpenSSL 链接与 harness primitive 限制。后续承接需在具备对应环境/工具能力时补证据并重评。
- **若继续推进的最小可行方向**：补 IRB-in-bundle 稳定受控 fixture/env（可安装 irb+deps、规避 reline-fiddle 脆弱性）与 Case C 文档化边界、M7(1)/(2) 可低成本 fixture/spec 化项（B3 harness 扩展、nolock deps-satisfied 通知、Default Gem ≤1 次再试、path/GIT+group/platform 组合、show/info 重解通知等可行子项）并回归；M7(3) 仅在可构造稳定可比场景时补差分，否则维持显式 unsupported/边界记录（gem 矩阵/console UX 已取证为非低成本对齐点）。达当前环境最大可行闭环时提交阶段验收汇总报首辅裁断 task-2 收口与 task-3 启动。

（本节末：以上结论与计数均来自既有实测 commit/日志与本轮 docs 核实；未重跑 differential/spec 的条目已标注。）
# Stage acceptance summary (docs aligned to HEAD=0423b2f, 2026-11-12)

- Current HEAD: 0423b2f66aec54ae78a9f6aa1667efebdad018ce (docs-only sync commits on main; prior snapshot commit 0423b2f titled with HEAD=b5cfa51); source implementation evidence HEAD 0fabf9e. task-2 remains in_progress; M7 checkboxes not checked.
- Baselines (unchanged, no rerun): 4.0.24 130:123/7/0 (log `C:\temp\celerite-diff-full-4.0.24-execloader-final.log`, 2026-11-12 08:02:07); 2.7.2 130:123/6/1 (log `C:\temp\celerite-diff-full-2.7.2-8d20c17.log`, 2026-11-12 10:12:15 CST); M7 spec subset 70/0/0/0 (ae8eafc, 未重跑)。
- Recent fixture evidence (unchanged): issue-satisfied 1/0/0 (582b099); B3 nolock satisfied+missing 4/0/0 (0fabf9e); env/issue stable set 3/0/0 (34a8cad/a482329 证据)；M7(3) spec 8/0/0/0（既有）。尾段原记“M7 spec subset 68/0/0/0”为笔误（正文/基线均为 70/0/0/0），本次更正为 70/0/0/0。
- Unverified/blocked（未实跑/未闭环，复现见正文对应条目）：B1 Default Gem stable diff/spec；B2 IRB-in-bundle/交互/console UX（Case A exec-irb 对齐、console UX 未对齐；IRB-in-bundle ≤2 次未获稳定对照，reline/fiddle/LoadError；Case C bundler gem 不可见且无 `CELERITE_REFERENCE_BUNDLER_LIB`）；B3 nolock 其他 `show`/`info` 重解通知场景；`gem` 完整模板/选项/`--help` 显式 unsupported；env/issue 归一化外字段与稳定集外完整输出；ABI/平台/gnu-musl 矩阵；全量 differential/M7 子集 spec 未在 5949cc2/b4fe095/a482329/582b099/0fabf9e 及后续 docs-only 提交后重跑。bridge 不可用不得视为通过。
- docs aligned to HEAD 044aacb baseline; 本次子项在 044aacb 上修复 B1/B2（system gem fallback）并补充取证，证据同步至本提交 HEAD（见下条）。no bin/shim/shard.lock committed. M7 checkboxes not checked.
- Recommendation: stage acceptance summary/evidence boundaries synced at 044aacb baseline + 本次 B1/B2 修复取证; await lead adjudication for task-2 closure and task-3 start.

# Subitem evidence: B1/B2 system gem discovery fix (2026-11-12, post-044aacb)

- **Scope/HEAD baseline**: 044aacba92773925965ebecdfe29bad09c20e3ab (`## main...origin/main`, worktree only `?? shard.lock` before edits). Modified `src/celerite/cli/commands_surface.cr` (+system gem fallback in `installed_gem_dir` for RubyGems sources and cached `system_gem_search_dirs` via bridge `ruby_environment` `default_gem_dir`/`gem_paths`/`user_gem_dir`, bridge-available only; PATH/GIT behavior unchanged). No bin/shim/shard.lock committed. Docs updated for evidence.
- **Baseline checks (cmd/exit)**: `crystal tool format --check src spec` EXIT 0; `crystal build --no-codegen src/cli.cr` EXIT 1 (stock OpenSSL/pkg-config blocker: `In C:\msys64\ucrt64\share\crystal\src\openssl\lib_crypto.cr:24:27 ... error executing command: sh -c 'hash pkg-config 2> /dev/null || printf %s false': 系统找不到指定的文件。`, known env limit, 非本修复引入); `git diff --check` EXIT 0 (post-edit). Build with shim for runtime verification: `PATH=C:\msys64\usr\bin;C:\msys64\ucrt64\bin;... crystal build src/cli.cr -o %TEMP%\celerite-b1b2-fix.exe --link-flags C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o` EXIT 0 (2 known deprecation warnings in `src\celerite\cli\commands_install.cr:584:43,648:20` `Deprecated File.executable?`, unchanged).
- **B1 Default Gem (≤1, repro C:\temp\defaultgem-test2, Gemfile pins `json 2.15.1`, gem present at `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1` spec `.../specifications/json-2.15.1.gemspec`)**: Before (044aacb-era celerite, probed earlier this session, `BUNDLE_GEMFILE` set) — `celerite info json` EXIT 7 `Could not find json-2.15.1 in locally installed gems`; `celerite show --paths json` EXIT 7 same. Reference `bundle _4.0.24_ info json` EXIT 0 (Path `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1`), `bundle _4.0.24_ show --paths json` EXIT 0 same path. After (patched temp bin, `CELERITE_BRIDGE_SERVER=assets/bridge/server.rb`) — `celerite-b1b2-fix info json` EXIT 0, output includes `Path: C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1` and `Default Gem: yes`; `celerite-b1b2-fix show --paths json` EXIT 0 `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1`. Before/after 对比: celerite 由“找不到本地 gem”转为与 bundle 一致定位 system/default gem 路径与元数据（本受控场景）。未验证/阻塞保留: `C:\temp\defaultgem-test2` `celerite install --local`/`install` 历史阻塞 `SSL_CTX_load_verify_locations: error:80092004:system library::Unknown error` EXIT 1（含 `SSL_CERT_FILE=C:/msys64/ucrt64/ssl/cert.pem` 仍失败）未在本轮重试（≤1/非本修复路径）；Default Gem 稳定 diff/spec 全覆盖仍未验证。
- **B2 check 依赖发现 (≤1, repro C:\temp\m7s3-irb-bundle\project, Gemfile irb, lock irb 1.18.0+deps satisfied from `GEM_PATH=C:/Ruby40-x64/lib/ruby/gems/4.0.0`)**: Before — `bundle _4.0.24_ check` EXIT 0 "The Gemfile's dependencies are satisfied"; `celerite check` (044aacb-era/local bin behavior probed earlier) EXIT 1 "The following gems are missing" listing locked gems not found in bundle path. After (patched temp bin, bridge server set) — `celerite-b1b2-fix check` EXIT 0 "The Gemfile's dependencies are satisfied". Root cause confirmed: `installed_gem_dir` 仅查 bundle install path，未查 system GEM_PATH/default gem dirs；修复为 RubyGems 源在 bundle 未命中时回退系统 gem 目录（bridge 可用）。
- **B2 console/exec IRB-in-bundle 行为（本轮未改代码，仅记录边界）**: 受控 probe `C:\temp\m7s3-irb-bundle\project`（HOME `C:\temp\m7b2-irbin-home`）下 `bundle _4.0.24_ exec irb --version` 与 `celerite exec irb --version` 均 EXIT 1，reline 0.7.0/fiddle `LoadError cannot load such file -- fiddle/import`（Ruby 4.0 Windows 环境依赖链问题，同类根因）；`bundle console`/`celerite console` exit/UX 仍存在已知差异（历史取证）。IRB-in-bundle 稳定可用正例 **未验证/阻塞**（依赖 materialization/reline-fiddle 链，≤1 尝试未获稳定对照）；console UX 对齐非低成本，本子项未改。
- **Targeted regression**: `PATH=C:\msys64\usr\bin;... crystal spec spec/m7_installed_discovery_spec.cr --link-flags ...evp_md_size_shim.o` EXIT 0, **20 examples, 0 failures, 0 errors, 0 pending**.
- **未重跑/未验证（保持）**: M7 spec 全子集/全量 differential 4.0.24 130:123/7/0、2.7.2 130:123/6/1 未在本修复后重跑（不得虚报）；B1 Default Gem install/SSL 及 diff/spec 全覆盖未验证；B2 IRB-in-bundle 可用/交互、console UX 完全对齐、Case C、`gem` 完整矩阵、env/issue 外字段全量、ABI/平台/gnu-musl、其他 show/info 重解通知等仍未验证/阻塞（复现见上文及本条）。M7 复选框未勾，task-2 in_progress。
