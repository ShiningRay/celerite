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
  harness N5 归一化剥离 `## Environment` 机体至 `## Bundle Doctor` 后比对）。**限定（2026-11-15）**：该夹具在 2026-11-15 之前是空比较——旧 N5 规则对没有 `## Bundle Doctor` 的 `env` 输出会整段删到 EOF，两侧均为 0 字节；修复后转为真比较并实测 FAIL。因此上面的 3/0/0 只表示当时未报错，**不构成 `env` 输出兼容证据**。`console` 的旧边界证据（IRB 缺失 PATH 下自定义话术 + EXIT 127）已于 2026-11-15 按参考替换，见下「console 对齐」子节。
  **2026-11-15（env 输出对齐，段 B）**：修复 N5 空比较后 `env-report` 转真比较，据参考原文对齐 4 处——
  ① `Bundler` 行只留版本号（去掉 `(Celerite … compatibility profile)` 后缀，版本仍取
  `CELERITE_PROFILE_BUNDLER_VERSION` 或默认 `4.0.24`）；② 新增 `## Bundler settings` 段
  （依据 `bundler-4.0.24/lib/bundler/env.rb:20-29` 的 `unless Bundler.settings.all.empty?` +
  `out << "\n## Bundler settings\n\n```\n"`，内容取本项目 config 观测面：本地 `.bundle/config`
  或 env 中的 `BUNDLE_*`，按 `settings.pretty_values_for` 的 `key\n  Set via <ENV>: "<value>"` 形态）；
  ③ 缺锁文件时打印 `Bundler::Env.read_file` 的占位 `<No <lockfile 绝对路径> found>`（路径统一 `/`，
  交由 harness N1 归一化）；④ 去掉文件末尾多余空行（输出以结束 fence 的换行收尾）。
  `bash script/differential env-report` → `PASS env-report (exit=0)`、
  `differential (4.0.24): 1 passed, 0 failed, 0 skipped`；`issue-no-gemfile`/`issue-missing-gems`/
  `issue-satisfied` 仍 `3 passed, 0 failed, 0 skipped`。新 spec `spec/m7_env_output_spec.cr` 3/0/0；
  全量 spec `322 examples, 0 failures, 4 errors`（4 个仍为已知 Low-IL GitSource 环境错误）。
  **仍未对齐**：`bundle #!` 行（参考是 Ruby shebang 脚本，本产品为原生可执行文件，已由 harness 行级
  归一化为 `{BUNDLE_SHEBANG}`）；`## Gemspecs` 与 `OpenSSL` 块已实现（见下「段 C」）。

### 2026-11-15（env 对齐，段 C）：OpenSSL 块与 `## Gemspecs`

- **参考依据**：`bundler-4.0.24/lib/bundler/env.rb:106-112`——OpenSSL 五行（`OpenSSL` 表头、`Compiled`、`Loaded`、`Cert File`、`Cert Dir`），每行由 `defined?` 独立门控；环境表列宽由最长键 `ljust` 决定，当前为 14。`:51-58`——`## Gemspecs` 段：先空行，`## Gemspecs`，每条 `\n### <basename>` + 空行 + ```` ```ruby ```` + 文件内容 `.chomp` + 闭合 fence；`dsl.gemspecs` 为空则整段不打印。
- **实现**：`assets/bridge/server.rb` 的 `op_ruby_environment` 增 `openssl_compiled`/`openssl_loaded`/`openssl_cert_file`/`openssl_cert_dir` 四个字段（不 `require "openssl"`，桥进程未加载则无值，与参考 `defined?` 门控等价）；新增 `op_gemspec_paths`（`Bundler::Dsl#eval_gemfile` → `dsl.gemspecs.map(&:loaded_from)`）；`src/celerite/bridge/client.cr` 的 `RubyEnvironment` 增四个 `String?` 字段与 `gemspec_paths(gemfile)`；`src/celerite/cli/commands_surface.cr` 的 `self.env` 在 `  Bin Dir` 后打印 OpenSSL 五行（任一值存在才打表头），在 `### Gemfile.lock` 后打印 `## Gemspecs`（CRLF→LF 后 `chomp`）。
- **证据**：新增夹具 `env-gemspec`（`Gemfile` 为 `gemspec name: "foo"`，`extra/foo.gemspec` 最小合法）双列 PASS；`env-report`、`issue-satisfied` 仍 PASS；负对照：去掉 `## Gemspecs` 打印后报 `stdout differs: 51,64d50 < ## Gemspecs …`，还原即 PASS；`spec/m7_env_output_spec.cr` 5/0/0；全量 spec `324 examples, 0 failures, 4 errors`；`crystal tool format --check`、`git diff --check`、`bash -n` 均 EXIT 0。
- **仍未对齐/未验证**：`bundle #!` 行仍由 harness 归一化为 `{BUNDLE_SHEBANG}`（本产品是原生可执行文件，无 shebang）；`## Gemspecs` 内容在打印期读取文件（参考在 DSL 求值期经 `loaded_from` 读取），时差极端情形未验证；多个 `gemspec` 指令的顺序/去重与 DSL 同源，未做多 gemspec 差分夹具；OpenSSL 行跟随桥进程是否加载（本机默认未加载，默认无该块，与参考一致）。

### 2026-11-15（console 对齐）

- **参考语义**：`bundler-4.0.24/lib/bundler/cli/console.rb:11-17`——`group ? Bundler.require(:default, *group.split(" ").map!(&:to_sym)) : Bundler.require`；`ARGV.clear`；`console = get_console(Bundler.settings[:console] || "irb")`；`console.start`。`:19-36`——`require name` 失败时，`irb` 打印 `irb is not available` 并 `exit 1`，其他名打印 `Couldn't load console <name>, falling back to irb` 后按 irb 重试。`cli.rb` 声明 `console [GROUP]`，实测 4.0.24 多位置参数即被 Thor 拒绝：`ERROR: "bundle console" was called with arguments ["a", "b"]` + `Usage: "bundle console [GROUP]"`，退出码 15。
- **实现**：`src/celerite/cli/commands_surface.cr` 的 `self.console` 重写——位置参数多于 1 个时按上面两行原文报错并返回 15；控制台名取 `definition.config["console"]`（`BUNDLE_CONSOLE`），缺省 `"irb"`；查找 `name`/`name.bat`/`name.cmd`；自定义名缺失时先打印回退消息，再按 irb 查找，仍缺则 `irb is not available` 返回 1；启动前合并环境：`RUBYOPT` 追加 `-rbundler/setup`（保留用户已有值），`BUNDLE_GEMFILE` 设为 Gemfile 绝对路径（正斜杠），`.bat`/`.cmd` 经 `cmd /c` 执行。
- **已声明偏差**：参考在进程内 `Bundler.require` + `console.start`，本产品是 exec 控制台 + `-rbundler/setup`，只准备加载路径，gem 的 `require`/分组语义不等价；`GROUP` 参数被接受但不执行 require；参考 `ARGV.clear` 后不向控制台传参，本产品同样不传；自定义 console 参考走 `require name`（如 `pry` 库入口），本产品按同名可执行文件启动，二者入口不同。
- **证据**：`spec/m7_console_spec.cr` 5/0/0——假 `irb.bat` 经 marker 文件证明被启动；`BUNDLE_CONSOLE=fakecons` 时启动 fakecons 而非 irb；`BUNDLE_CONSOLE=pry` 且无 irb 时 stderr 含回退消息与 `irb is not available`、退出 1；无 console 时 stderr 恰为 `irb is not available`、退出 1；`console a b` 退出 15 且复现参考两行。负对照：把回退消息改回旧话术，spec 报 `Failure/Error: err.should contain("Couldn't load console pry, falling back to irb")`（`spec/m7_console_spec.cr:94`），还原即 5/0/0。门禁：`crystal spec spec/cli_spec.cr` 29/0/0（含 console 5 例）；全量 `328 examples, 0 failures, 4 errors`（4 个为已知 Low-IL GitSource 环境错误）；`crystal tool format --check src spec`、`git diff --check`、`bash -n script/differential` 均 EXIT 0。
- **未验证**：真实交互式 irb 会话；`GROUP` 的 `Bundler.require` 行为；用户 `RUBYOPT` 已含 `-rbundler/setup` 的路径差异；`pry` 等自定义 console 的实际入口差异。

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
> **2026-11-15 撤销**：下方「Class C」条目所述的「2.7.x profile 下 clean 清空保留集」是装具缺陷期（`>>` 复开截断参考输出）的误判。参考 2.7.2 与 4.0.24 一致：按当前锁文件保留；该 profile 特例代码已删除，并新增 `spec/m7_clean_spec.cr` 4 例。详见文末「2026-11-15 clean：撤销 2.7.2 profile 特例」节。

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

### 2026-11-15（gem 模板对齐）

- 参考依据（`bundler-4.0.24/lib/bundler/cli/gem.rb`）：`:39-41` 名规则（`-`→`::`、`_` 切词）；`:45-50` `git config user.name`/`user.email`/`github.user`；`:52-60` github 为空时 homepage/source 用 TODO；`:62-85` author/email TODO 回退、`required_ruby_version = ">= 3.2.0"`（`:470-471`）；`:88-98` 模板映射；`:100-110` `ignore_paths = [bin/, Gemfile, .gitignore]`；`:252-255` 目标是文件时报 ``Couldn't create a new gem named `x` because there's an existing file named `x`.`` 并 exit 32；`:257-262` `git init`（stdout 捕获）；`:264-267` 写模板；`:269-273` bin/* chmod +x（Windows 无效）；`:275-277` `git add .`（无 commit）；`:289-290` 成功行前空行。
- 实测基准（4.0.24，隔离 git 身份）：15 行 stdout（`Creating gem 'foogem'...`、空行、`Initializing git repo in <abs>/foogem`、10 行 `      create  `（6 空格 + `create` + 2 空格）、空行、成功行）；10 文件全 LF 且无尾空行、git 索引 `100644`。
- 实现：新增 `src/celerite/gem_template.cr`（`Celerite::GemTemplate.render` 逐字节模板；`terminate` 补 Crystal heredoc 缺少的末尾换行；`constant_name` 按 `-`/`_` 规则）；`src/celerite/cli/commands_surface.cr` 的 `self.gem` 重写（参数 exit 15、目标文件 exit 32、`git config` 取 author/email/github、`git init`+`git add .`、`      create  ` 行）；新增 `spec/m7_gem_template_spec.cr`（3 例，与 `spec/fixtures/gem-template/foogem/` 逐字节比较）、改写 `spec/m7_gem_spec.cr`（4 例，参数/选项/覆盖语义）。
- 负对照：把 Gemfile 的 `gem "irb"` 改成 `gem "irb-NEGATIVE-CONTROL"` → `3 examples, 1 failures`，`Expected: "gem \"irb\""` / `got: "gem \"irb-NEGATIVE-CONTROL\""`（`spec/m7_gem_template_spec.cr:64`）；还原后 3/0/0。
- 差分：`fixtures/differential/gem-default`（`command` = `gem foogem`；`file-contains` 断言 gemspec `spec.name`、rbs `module Foogem`、README `## Contributing`）→ 4.0.24 `PASS (exit=0)`；2.7.2 `SKIP`（`deferred-2.7.2`：2.7.2 成功行用 `https://bundler.io/guides/creating_gem.html`，且模板内容与 4.0.24 不同——README 与 git 对象集差异；本产品对准 4.0.24）。
- 已声明偏差：非默认选项（`--test/--ci/--coc/--mit/--changelog/--linter/--exe/--ext/--bin/-t/--edit/--bundle/--github-username`）fast-fail（`bundle gem option <x> is not supported by Celerite` + `Supported options: --git (default), --no-git`，exit 1），仅支持 `--git`/`--no-git`；参考在非 tty 下取默认（`--test` 不生成测试文件、`--mit` 增 license 行）。
- 门禁：`spec/m7_gem_spec.cr spec/m7_gem_template_spec.cr` **7 examples, 0 failures**；全量 `crystal spec` **331 examples, 0 failures, 4 errors**（4 = 既有 GitSource Low-IL 环境错误）；`crystal tool format --check src spec` EXIT 0；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。
- 未验证：可执行位（Windows 无）、交互分支（tty 提问）、非默认选项的渲染、生成 gem 的真实 `gem build`、2.7.2 模板、author/email 的 TODO 回退（spec 用当前 `git config` 归一化两侧，故 `TODO: Write your name` / `TODO: Write your email address` 分支仅经代码走读确认，未在「无 git 身份」环境实测）。

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
| 关键 commit（至 HEAD） | `a8753b6`、`f168d6f`、`7c446d9`、`3c4f55d`、`34a8cad`、`f3ad8a5`、`ae8eafc`、`20690ff`、`8d20c17`、`bdd0ca6`、`0032664`、`14ccb9d`、`5949cc2`、`8f1ef39`、`b4fe095`、`7a4f1bc`、`bce1138`、`a482329`、`340f050`、`582b099`、`0fabf9e`、`6488b8a`、`b5cfa51`、`0423b2f`、`1882f53`、`517f69a`、`4c2404a`、`497e293` | 实现/fixture/spec/差分修复与文档证据链；`14ccb9d`/`8f1ef39`/`7a4f1bc`/`bce1138`/`340f050`/`6488b8a`/`b5cfa51`/`0423b2f` 为 docs 同步/汇总；`5949cc2`/`b4fe095` 修复 B2 exec/console；`a482329` 修复 satisfied `issue` doctor success 行；`582b099` 新增 `fixtures/differential/issue-satisfied` 并双 profile 1/0/0 PASS；`6488b8a` 追加 gem/env-issue 字段/IRB-in-bundle 受控探针记录（docs-only，未重跑全量差分/子集 spec） |
| M7 子集 spec（本轮重跑） | `spec/m7_reverse_dependencies_spec.cr spec/m7_installed_discovery_spec.cr spec/m7_platform_match_spec.cr spec/m7_ruby_constraints_spec.cr spec/m7_resolver_ruby_constraints_spec.cr spec/ruby_version_spec.cr spec/m7_ruby_runtime_spec.cr spec/m7_platform_spec.cr` | **70 examples, 0 failures, 0 errors, 0 pending, EXIT 0**（前次 `ae8eafc` 轮 14.65s；本轮 2026-11-13 @4c2404a+worktree 重跑 17.91s） |
| M7(3) spec（既有实测，未重跑） | `spec/m7_console_spec.cr spec/m7_gem_spec.cr spec/m7_fund_spec.cr` | **8 examples, 0 failures, 0 errors, 0 pending, EXIT 0** |
| M7(2) 定向回归（既有实测） | `info-reverse-dependencies-path check-path list-path git-installed-discovery show-info-installed list-multi-group`（双 profile） | 4.0.24 **6/0/0 EXIT 0**、2.7.2 **6/0/0 EXIT 0**（`ae8eafc`） |
| M7(1)/(2) 组合+回归（本轮实跑） | `list-path-only-group multi-platform-install-ruby` 双 profile 定向 + 43 例 M7 回归集双 profile（logs `C:\temp\celerite-diff-m7combos-4024.log`/`-272.log`/`-reg-4024.log`/`-reg-272.log`） | 定向 4.0.24 **2/0/0 EXIT 0**、2.7.2 **2/0/0 EXIT 0**；回归 4.0.24 **43/0/0 EXIT 0**、2.7.2 **43/0/0 EXIT 0**（含 2 新 fixture；非零 exit 例均为 reference 预期 exit 1/6/7/10/18/42 且 PASS） |
| M7(3) env/issue 稳定集 + satisfied-issue（`34a8cad`/a482329/582b099） | `env-report issue-no-gemfile issue-missing-gems` 双 profile 3/0/0（`C:\temp\m7s3-diff-4024.log`/`C:\temp\m7s3-diff-272.log`，shim bin 2026-11-12T14:45:11+08:00，harness N5）+ `fixtures/differential/issue-satisfied` 双 profile **PASS (exit=0) 各 1/0/0**（`C:\temp\issue-satisfied-4024.log`/`C:\temp\issue-satisfied-272.log`，582b099） | 4.0.24 3/0/0 + 1/0/0；2.7.2 3/0/0 + 1/0/0；稳定集无回归，satisfied-issue 已 harness 归一化验证 |
| M7 定向扩展 2.7.2（既有实测） | M7 相关扩展定向集 | **36/36 PASS, EXIT 0**（`7c446d9`） |
| 4.0.24 全量 differential（既有实测，未重跑） | `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`，shim-built bin；log `C:\temp\celerite-diff-full-4.0.24-1882f53.log`（post-37b4287 独立核实；早期 130-fixture 实测 `C:\temp\celerite-diff-full-4.0.24-execloader-final.log` 保留为历史） | **133 fixtures, 126 passed, 7 failed, 0 skipped, wrapper exit 1**。FAIL（A:7 racc/make，`make failedNo such file or directory - make`）：`add-group`、`add-optimistic`、`add-remove`、`add-version`、`cache-all-platforms`、`native-ext-target`、`native-ext`。`exec-loader`/`exec-loader-disabled` PASS；较 130:123/7/0 基线 +3 fixtures/+3 passed，按名字无新增失败 |
| 2.7.2 全量 differential（既有实测，未重跑） | `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`；最新实测 log `C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log`（2026-11-13 00:24:35 CST，12138 bytes，HEAD=517f69a，shim bin + 修复后 harness；前序 log `C:\temp\celerite-diff-full-2.7.2-8d20c17.log` 130:123/6/1 保留为历史） | **133 fixtures, 126 passed, 6 failed, 1 skipped, harness exit 1（日志无显式 exit 标记，按 `[ "$fail" -eq 0 ]` 语义；tee wrapper exit 0）**。FAIL（A:6）：`add-optimistic`、`add-remove`、`add-version`、`cache-all-platforms`、`native-ext-target`、`native-ext`。SKIP 1：`add-group`（harness documented deferral，network-required）。对比 4.0.24 全量 133:126/7/0：仅 `add-group` 形态差（2.7.2 SKIP deferral vs 4.0.24 A FAIL）；class C `clean-force`/`clean-unused`（`8d20c17`）与 B:1 `exec-loader`/`exec-loader-disabled`（`20690ff`）已转绿；按名字无新增失败 |
| 代表性 fixtures（部分） | `fixtures/differential/info-reverse-dependencies-path`、`env-report`、`issue-no-gemfile`、`issue-missing-gems`、`fund-path`、`check-missing-ruby-nolock`、`list-missing-ruby-nolock`、`ruby-*`/`rubygems-*` metadata & boundary、`multi-platform-install`、`git-installed-discovery`、`show-info-installed`、`list-multi-group`、`check-path`/`list-path` 等 | 见上文 M7(1)-(3) 分项与 generated differential 报告 |

### 2) 已覆盖与达成（按 M7(1)/(2)/(3)）

- **M7(1) 约束过滤 / install recheck / lock reuse / re-resolve 通知（部分）**：`RubyVersion`/`RubyRuntime`、`RubyVersionMismatch` exit 18、Gemfile `ruby` 结构化选项（version/engine/engine_version/patchlevel）与 bridge patchlevel、gem metadata `required_ruby_version`/`required_rubygems_version` 过滤、SolveFailure exit 6 vs GemNotFound exit 7 区分、平台 mismatch 文案/正反例、`lock --add-platform`+install+check（`multi-platform-install`）等已实现并有 spec/fixture 证据；B3 nolock deps-satisfied 通知已 fixture 化：`check-satisfied-ruby-nolock` + `check-missing-ruby-nolock`（lock 无 `RUBY VERSION`，Gemfile 声明 `ruby "4.0.6"`）双 profile **4/0/0 PASS EXIT 0**（`0fabf9e`，含 list 空 deps 早返回前通知修复）；`ruby-patchlevel-match-list`、`check-missing-ruby-nolock`/`list-missing-ruby-nolock` 等通知/缺依赖场景已 fixture 化；`exec-loader`（B:1，PATH/GIT binstub/shebang 对齐）已修复并在 4.0.24 全量中转绿（双 profile 定向 PASS，`20690ff`）。本轮新增平台变体正例 fixture `multi-platform-install-ruby`（`lock --add-platform ruby`+install+check，json_pure+thor file-index）双 profile 定向 PASS。
- **M7(2) 安装后发现（部分）**：`installed_gem_dir` 容忍缺 specifications、`show --paths`/`list` 格式与 git 短 revision/路径渲染对齐、group/`--with`/`--without`/`--only-group`（含空格分隔多组与 `BUNDLE_WITH`）/PATH/GIT/平台特定 gem 发现已有 spec 与 differential 覆盖；`read_gemspec_info` PATH/GIT gemspec 元数据回退与 Windows 路径 `rescue` 加固使 path gem `info` 可显示 Summary/metadata（`ae8eafc`）；`info-reverse-dependencies-path` 双 profile PASS、`spec/m7_reverse_dependencies_spec.cr` 4/0 覆盖 reverse dependencies 与 `check/list --without-group` 排除缺失 test 组 path gem。本轮新增 `list-path-only-group`（path 源+group+`list --only-group default`，test 组 path gem 排除）双 profile 定向 PASS。
- **M7(3) 占位路径真实化 / 显式 unsupported（部分）**：`fund` 读取 installed specs/`.gem` metadata 与 PATH/GIT gemspec `funding_uri`（`fund-path` 双 profile PASS，`spec/m7_fund_spec.cr` 3/0）；`env`/`issue` Build Metadata 与 timestamp/git_sha 行为（非 git cwd `Timestamp unknown`）已实现。**a482329（`src/celerite/cli/commands_surface.cr` +2/-0，2026-11-12，已推送）** 修复 satisfied `issue`（含 lock、依赖满足）缺失 doctor success 行（现输出 `The Gemfile's dependencies are satisfied` / `No issues found with the installed bundle`，对齐 `doctor`/reference）；env/issue 稳定集 `env-report`+`issue-no-gemfile`+`issue-missing-gems` **a482329 后本轮 shim bin 复跑**：4.0.24 `3/0/0 EXIT 0`、2.7.2 `3/0/0 EXIT 0`（`script/differential ...`，log `C:\temp\m7s3-diff-4024.log`/`C:\temp\m7s3-diff-272.log`）。`console` IRB 缺失 PATH 明确 stderr+EXIT 127（`spec/m7_console_spec.cr` 1/0）为显式 unsupported 边界；`gem` 最小 scaffold（6 文件）与不支持选项 warning+降级行为（`spec/m7_gem_spec.cr` 4/0）已取证（完整模板/选项矩阵仍未覆盖）。**B2（5949cc2 + b4fe095 + subitem 2）**：5949cc2 修复 Windows PATH casing（回报/未独立重跑：`exec ruby` 127→0）但 `exec irb`/`console` 仍因 `bundler_lib`/setup 解析错误转为 EXIT 1 `LoadError .../bundler/setup`；b4fe095（`src/celerite/cli/commands_install.cr` +22/-4，`find_bundler_lib` 从 gem paths/default/user gem dir 发现 `<dir>/gems/bundler-<version>/lib/bundler/setup.rb`，保留 `CELERITE_REFERENCE_BUNDLER_LIB` 优先，始终注入 `BUNDLER_VERSION`）在受控 probe（`C:\temp\m7b2-probe\project`，4.0.24，shim 本地 bin）Case A 无 REF_LIB 且 bundler gem 可见时：`exec ruby --version`/`exec ruby -e "puts 123"` EXIT 0，`exec irb --version`/`echo exit | celerite console` EXIT 1 Gem::Exception “irb not in bundle”，与 `bundle _4.0.24_ exec irb --version`（Case B）同类对齐。残留未对齐/未验证：`bundle console`（IRB 不在 bundle）EXIT 1 为 LoadError+Bundler 环境报告，`celerite console` 仍返回 Gem::Exception（UX 未完全对齐）；IRB 在 bundle 内且可用时 `exec irb`/`console` 行为与交互路径未验证；Case C（bundler gem 不可见且无 REF_LIB）为 `BUNDLER_VERSION` 激活环境/配置约束；satisfied-issue differential fixture 未创建、`env`/`issue` 其余字段/设置/元数据/profile 标识等与 reference 差异及全量输出边界仍未验证；4.0.24/2.7.2 全量与 M7 子集 spec 未在 b4fe095/a482329 后重跑。**命令入口存在不等同功能完成** 的边界持续成立（B1/B2/B3）。

### 3) 缺口与未验证（不得冒充完成）

| 分项 | 缺口 / 未验证 | 状态 |
|---|---|---|
| M7(1) | 本地 x64-mingw-ucrt 外 ABI/平台变体/gnu-musl/多 Ruby 矩阵穷举；`show`/`info` 其他重解通知场景；更多 engine/engine_version/patchlevel 与 lock-reuse 组合 | **部分进展**：本轮新增 `multi-platform-install-ruby`（ruby platform add-platform 正例）双 profile PASS；其余（本地外 ABI/gnu-musl/多 Ruby 矩阵、`show`/`info` 其他重解通知、更多 engine/patchlevel/lock-reuse 组合）仍未验证 |
| M7(1)/B3 | Gemfile 声明 `ruby` 但 lock 无 `RUBY VERSION` 时 `check`/`list` `Resolving dependencies...` 通知（deps satisfied/missing 两分支） | **已 fixture 化并修复 list**（`check-satisfied-ruby-nolock` + `check-missing-ruby-nolock`，lock 无 `RUBY VERSION`，Gemfile 声明 `ruby "4.0.6"`；`src/celerite/cli/commands.cr` 修复 list 空 deps 早返回前打印通知）：4.0.24/2.7.2 **4/0/0 PASS EXIT 0**（check-satisfied/list-satisfied/check-missing/list-missing，log `C:\temp\m7s3-nolock-satisfied-4024.log`/`-272.log`）；`Resolving dependencies...` 在 satisfied/missing 两分支均 firing 且与 reference 对齐。未 fixture 化残余：`show`/`info` 其他重解通知场景（Gemfile ruby decl vs lock，非 B3 这两项） |
| M7(2)/B1 | `Default Gem` 稳定差分/spec 取证（`info`/`show` `Default Gem: yes` 等） | **未验证**（环境/ harness 限制 + 探针阻塞） |
| M7(2) | path/GIT + `--with/--without/--only-group`/平台组合补强；Reverse Dependencies 更多来源形态/输出边界 | **部分进展**：本轮新增 `list-path-only-group`（path+group+`--only-group default`）双 profile PASS；GIT+group、`--with/--without`、更多平台变体、reverse-deps 其他来源形态仍未验证 |
| M7(3) | satisfied-`issue` 已 fixture 化（582b099，双 profile 1/0/0 PASS）且 env/issue 稳定集 3/0/0 无回归；582b099+ 受控探针已取证 env/issue 归一化外字段差异（profile 标识/Gem Path/Bin Dir/Build Metadata/settings 块）与 IRB-in-bundle（≤2 次未获稳定可用对照）边界/阻塞+复现 | **部分进展、仍有未验证/阻塞**：稳定集+`issue-satisfied` 外完整输出/设置组合、IRB-in-bundle 可用/交互路径、其余场景仍未全量验证 |
| M7(3)/B2 | `console` 在 IRB 不在 bundle 时与 reference `bundle console` UX/错误形态对齐；IRB 在 bundle 内且可用时 `exec irb`/`console` 行为与交互路径；Case C（bundler gem 不可见且无 `CELERITE_REFERENCE_BUNDLER_LIB`）下激活策略 | **部分进展、未闭环**：b4fe095 修复 `bundler_lib`/setup 发现与 `BUNDLER_VERSION` 注入后，Case A `exec ruby`/`-e` EXIT 0 且 `exec irb` 在 IRB 不在 bundle 时与 `bundle exec irb` 同类 Gem::Exception（受控 probe，未独立重跑全量）；subitem 2（2026-11-12，`C:\temp\m7b2-ux`，≤2 次尝试）取证：`celerite console` 仍返回 Gem::Exception 而 `bundle console` 返回 LoadError+Bundler 环境报告（UX 未对齐，exec-irb 路径语义差异），对齐技术可行但非低成本/有契约与回归风险（`spec/m7_console_spec.cr` 固定 IRB 缺失 PATH 行为），**未改代码、归类残留阻塞**；IRB-in-bundle/交互、Case C 环境约束处理未验证/未覆盖 |
| M7(3) | `gem` 完整模板/选项/`--help` 矩阵（ref 10 文件+丰富选项 vs celerite 固定 5 文件最小 scaffold；`--test`/`--ci` 等仅 warning 仍同 scaffold；`gem`/`--help` EXIT 1 `Please provide a gem name`） | **显式 unsupported/未覆盖**（582b099+ 受控取证 `C:\temp\m7s3-gemref/gemcel/gemopts-cel`，docs-only，非低成本对齐） |
| 全量差分 | 4.0.24/2.7.2 全量未在 37b4287/4c2404a/本子项后重跑 | **未重跑（引用既有）**；既有全量计数引用 HEAD=1882f53 4.0.24 133:126/7/0 与 HEAD=517f69a 2.7.2 133:126/6/1 实测日志；M7 spec 子集本轮已重跑 70/0/0/0 EXIT 0；本轮仅定向 2 例 + 43 例回归集双 profile 实跑 |

### 4) 阻塞与复现（已试≤2 的取证/阻塞记录）

| 项 | 阻塞/现象 | 已试与证据 | 精确复现/指引 |
|---|---|---|---|
| stock OpenSSL 构建 | Crystal 1.22.1 链接 `EVP_MD_size`，MSYS2 ucrt64 OpenSSL 3.6.5 导出 `EVP_MD_get_size`，stock `crystal build src/cli.cr` 失败 | CLI/diff 改用仓库外 shim 本地 bin（`C:\Users\ShiningRay\AppData\Local\Temp\celerite-shim-m7wip\evp_md_size_shim.c` + `--link-flags ...evp_md_size_shim.o`）；`bin/` gitignored，shim 未入库 | `crystal build src/cli.cr`（stock 失败）；本地构建：`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:\Users\ShiningRay\AppData\Local\Temp\celerite-shim-m7wip\evp_md_size_shim.o"` |
| 4.0.24 全量残余 | 7 FAIL（A:7 racc/make） | 引用既有 log `C:\temp\celerite-diff-full-4.0.24-1882f53.log`（133:126/7/0, harness exit 1；早期 130:123/7/0 log `C:\temp\celerite-diff-full-4.0.24-execloader-final.log` 保留为历史） | `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential` |
| 2.7.2 全量残余 | 6 FAIL（A:6 racc/make）+ 1 SKIP `add-group`（network-required deferral） | 引用既有 log `C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log`（133:126/6/1, harness exit 1，12138 bytes；早期 130:123/6/1 log `C:\temp\celerite-diff-full-2.7.2-8d20c17.log` 保留为历史） | `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential` |
| B1 Default Gem（M7(2)） | default-gem 布局/安装态 + differential sandbox 隔离；手工安装对照受内部错误阻塞 | `C:\temp\defaultgem-test2`（Gemfile pin `json 2.15.1`，Ruby 4.0.6 default gem dir 含 `json-2.15.1`）：`celerite install --local`/`install` 多次失败 `celerite internal error: SSL_CTX_load_verify_locations: error:80092004:system library::Unknown error` EXIT 1（含 `SSL_CERT_FILE=C:/msys64/ucrt64/ssl/cert.pem` 仍失败）；`script/differential` 隔离 GEM_HOME/GEM_PATH/BUNDLE_PATH 与本地 file index 难稳定构造可差分 fixture；对照 `bundle _4.0.24_ info json` 未输出 `Default Gem: yes`，未安装场景 shim `celerite info json` EXIT 7。**未修代码，已试≤2 后停止重试** | 同上命令/环境（`C:\temp\defaultgem-test2`，`CELERITE_BIN` 指向 shim bin，PATH 含 Ruby/msys2）；需可控 default-gem 发现场景或 harness 扩展 |
| B2 console/exec（M7(3)） | 5949cc2 修复 PATH casing 后 b4fe095 修复 `bundler_lib`/setup 发现与 `BUNDLER_VERSION` 注入；subitem 2 评估 console（IRB 不在 bundle）UX 与 `bundle console` 对齐可行性 | **5949cc2**：规范化 PATH key（+9/-1）；修复前 ≤14ccb9d 探针 `C:\temp\defaultgem-test` 下 `exec ruby -e`/`exec irb --version`/`console` EXIT 127；5949cc2 后回报 `exec ruby --version` EXIT 0、`exec irb`/`console` EXIT 1 `LoadError ... C:\Ruby40-x64\lib\bundler/setup`（未独立重跑）。**b4fe095**（+22/-4，`find_bundler_lib`+始终注入 `BUNDLER_VERSION`，保留 `CELERITE_REFERENCE_BUNDLER_LIB` 优先）：受控 probe `C:\temp\m7b2-probe\project`（Gemfile json_pure 2.8.1, lock BUNDLED WITH 4.0.24, isolated env, `bundle _4.0.24_ install` EXIT 0, Ruby 4.0.6, shim bin mtime 13:18:52）。Case A（无 REF_LIB，GEM_PATH 含系统 gem dir）：`exec ruby --version` EXIT 0、`exec ruby -e "puts 123"` EXIT 0、`exec irb --version` EXIT 1 Gem::Exception “irb not in bundle”、`echo exit \| console` EXIT 1 同类。Case B（reference）：`bundle exec irb --version` EXIT 1 同类 Gem::Exception（对齐），`echo exit \| bundle console` EXIT 1 LoadError+Bundler 环境报告（celerite console 未对齐）。Case C（GEM_PATH 无 bundler-4.0.24 gem，无 REF_LIB）：`exec ruby -e "puts 123"` EXIT 1 `Could not find 'bundler' (= 4.0.24)`（环境约束）。门禁 format/no-codegen/diff-check EXIT 0，shim build EXIT 0（2 known deprecations）。**subitem 2（2026-11-12，≤2 次尝试，未改代码）**：probe `C:\temp\m7b2-ux\project`（IRB 不在 bundle，bundle satisfied）显示 `bundle exec irb`/`celerite exec irb` 均 EXIT 1 Gem::Exception 对齐，`bundle console` EXIT 1 LoadError+Bundler 环境报告 vs `celerite console` EXIT 1 Gem::Exception 未对齐；回归 `exec ruby --version`/`exec ruby -e "puts 123"` EXIT 0；可行性探针可复现 reference console 语义但对齐需 bundler console 专用调用/发现且触及 `spec/m7_console_spec.cr` 契约与 IRB-in-bundle/交互未验证风险，**判定非低成本、归类实现语义差异/残留阻塞**。**未验证**：IRB 在 bundle 内/交互、Case C 规避策略、全量/子集未重跑；本节外探针未全部独立重跑。 | 探针复现：`C:\temp\m7b2-probe\project`（Case A/B/C，见 B2 节）；`C:\temp\m7b2-ux\project`（json_pure-only bundle，IRB 不在 bundle，隔离 env，`bundle _4.0.24_ install`）运行 `bundle _4.0.24_ exec irb --version`、`celerite exec irb --version`、`echo exit \| bundle _4.0.24_ console`、`echo exit \| celerite console`、`celerite exec ruby --version`、`celerite exec ruby -e 'puts 123'`。 |
| B3 nolock deps-satisfied 通知（M7(1)/(2)） | 依赖已满足 + lock 无 `RUBY VERSION` 的 `Resolving dependencies...` 通知无法固化为 differential fixture | 手工 harness-like 取证（probe base `C:\temp\nolock-sat-harnesslike-eZPd5c`，预置 BUNDLE_PATH gems+specifications，Gemfile `ruby "4.0.6"`，lock 无 `RUBY VERSION`，bridge/profile 同 harness）：ref 4.0.24/2.7.2 与 shim celerite `check`/`list` 均输出 `Resolving dependencies...` 后 EXIT 0；`script/differential` 缺少“命令前预填充 BUNDLE_PATH 且保留无 `RUBY VERSION` lock” primitive | 按 probe 条件手工对照；或扩展 harness 后新增 fixture |
| bridge 不可用 | runtime 校验 best-effort 跳过 | 设计/历史记录约束 | 任何 bridge 不可用结论不得视为通过 |

### 5) task-2 收口建议与剩余风险（供首辅裁断）

- **当前可行闭环程度（事实）**：M7(1) 约束/过滤/通知与安装复核的大量正反例、`exec-loader` B:1 修复、M7(2) 安装后发现（含 path/GIT reverse-dependencies）与 M7(3) fund/env/issue 稳定集（含 `fixtures/differential/issue-satisfied` 双 profile 1/0/0 PASS，582b099）均已有可复核 spec/fixture/differential 或 CLI 证据；582b099+ 本子项受控探针补充 `gem` 模板/选项/`--help`（显式 unsupported，`C:\temp\m7s3-gemref/gemcel/gemopts-cel`）与 env/issue 归一化外字段差异（`C:\temp\m7s3-ref`/`m7s3-cel-envissue2`）证据，IRB-in-bundle/交互 ≤2 次尝试未获稳定可用对照（`C:\temp\m7s3-irb-bundle\project`，materialization/reline-fiddle 依赖链阻塞，未验证+复现）。双 profile 全量在既有实测中为 4.0.24 **133:126/7/0**（log `C:\temp\celerite-diff-full-4.0.24-1882f53.log`）、2.7.2 **133:126/6/1**（log `C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log`；A:racc/make 与 2.7.2 `add-group` deferral；4c2404a+本轮未重跑全量，引用既有实测）。B2 `exec ruby`/IRB-not-in-bundle exec-irb 已对齐（5949cc2+b4fe095），console UX exec-irb 语义差异残留阻塞（bce1138）；Case C 环境约束未变。B1 Default Gem、B3 nolock deps-satisfied 通知、`gem` 完整矩阵、env/issue 稳定集外完整输出、ABI/平台矩阵等关键缺口仍**显式 unsupported/未验证/未闭环**。
- **收口建议（基于证据，供裁断）**：**不建议**在当前证据下宣告 M7(1)-(3) 整体验收收口或勾选 roadmap M7 复选框；task-2 保持 `in_progress`。582b099 已 fixture 化 satisfied-issue，本子项已固化 gem/env-issue 字段/IRB-in-bundle 边界 probe 证据；由首辅裁断是否在承认剩余风险/阻塞前提下阶段性挂起并启动 task-3，或继续派工补强可行子项/阶段验收汇总。
- **若阶段性挂起/收口的剩余风险**：IRB-in-bundle 可用/交互路径（本子项 ≤2 次未获稳定对照）、console UX（IRB 不在 bundle，非低成本对齐）、Case C bundler gem 激活策略、`gem` 完整模板/选项/`--help` 矩阵、env/issue 归一化外字段与稳定集+`issue-satisfied` 外完整输出、B1 Default Gem、B3 nolock deps-satisfied 通知、ABI/平台/gnu-musl 等仍缺 green 可比证据；全绿 differential 仍受本机 `make`/stock OpenSSL 链接与 harness primitive 限制。后续承接需在具备对应环境/工具能力时补证据并重评。
- **若继续推进的最小可行方向**：补 IRB-in-bundle 稳定受控 fixture/env（可安装 irb+deps、规避 reline-fiddle 脆弱性）与 Case C 文档化边界、M7(1)/(2) 可低成本 fixture/spec 化项（B3 harness 扩展、nolock deps-satisfied 通知、Default Gem ≤1 次再试、path/GIT+group/platform 组合（本轮已 fixture 化 `list-path-only-group`/`multi-platform-install-ruby` 双 profile 绿；GIT+group、`--with/--without` 等仍待补）、show/info 重解通知等可行子项）并回归；M7(3) 仅在可构造稳定可比场景时补差分，否则维持显式 unsupported/边界记录（gem 矩阵/console UX 已取证为非低成本对齐点）。达当前环境最大可行闭环时提交阶段验收汇总报首辅裁断 task-2 收口与 task-3 启动。

（本节末：以上结论与计数均来自既有实测 commit/日志与本轮 docs 核实；未重跑 differential/spec 的条目已标注。）
# Stage acceptance summary (docs aligned to HEAD=35fa404 evidence baseline + M7(4)/(6) audit/fix + config_spec docs-only + M7(1)/(2) regression evidence, 2026-11-13)

- Current HEAD (evidence baseline): 35fa404 (chain 044aacb->bba7949->6eee96a->37b4287->1882f53->517f69a->4c2404a->497e293->206d749->e77c6cb->a59d50f->94ec377->10e0a52->1eeaefb->35fa404 on main; source implementation evidence includes 37b4287 system-gem fallback + 8d20c17 clean semantics + 497e293 combo fixtures + 94ec377 redirect config-key typing + 10e0a52 plugin hook after-install alignment + 35fa404 stage summary refresh). Post-497e293 evidence: e77c6cb normalization/installed-tree docs alignment (M7(7)), 94ec377 M7(4) read-code audit + redirect typing fix, a59d50f M7(6) plugin command/hook audit (docs-only), 10e0a52 M7(6) plugin hook event-name alignment fix (post-install->after-install), 1eeaefb config_spec round-trip docs-only record, 35fa404 stage summary refresh. This stage summary is a docs-only refresh (SHA 以 git log 为准). task-2/task-3 remain in_progress; M7 checkboxes not checked.
- Baselines (measured, unchanged): 4.0.24 133:126/7/0 (log C:\temp\celerite-diff-full-4.0.24-1882f53.log, 2026-11-12, HEAD=1882f53, FAIL 7 = class A racc/make, zero-regression by name vs 130:123/7/0); 2.7.2 133:126/6/1 (log C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log, 2026-11-13 00:24:35 CST, HEAD=517f69a, wrapper exit 1; FAIL 6 = class A racc/make + SKIP 1 add-group deferral; zero-regression by name vs 130:123/6/1, 37b4287 confirmed); M7 spec subset 70/0/0/0 (ae8eafc 前次记录；本轮 2026-11-13 @4c2404a+worktree 重跑 70/0/0/0 EXIT 0, 17.91s，证据随 497e293 提交).
- Recent fixture evidence (updated): issue-satisfied 1/0/0 (582b099); B3 nolock satisfied+missing 4/0/0 (0fabf9e); env/issue stable set 3/0/0 (34a8cad/a482329 证据); M7(3) spec 8/0/0/0 (既有); post-37b4287 新 fixture issue-satisfied/check-satisfied-ruby-nolock/list-satisfied-ruby-nolock 2.7.2 全量中均 PASS (exit=0)；list-path-only-group/multi-platform-install-ruby 双 profile 定向 2/0/0 EXIT 0 + 43 例 M7 回归集双 profile 43/0/0 EXIT 0（logs C:\temp\celerite-diff-m7combos-4024.log/-272.log/-reg-4024.log/-reg-272.log；fixtures 与证据随 497e293 提交）；show-info-installed 双 profile 1/0/0 EXIT 0（logs C:\temp\celerite-diff-show-info-installed.log/-272.log，本轮新增）；M7(1)/(2) 回归集 6 fixture 双 profile 6/0/0 EXIT 0（logs C:\temp\celerite-diff-m712-regression-4024.log/-272.log，本轮新增）。
- M7(4): 94ec377/e77c6cb 审计与 redirect typing 修复为历史证据；本子项（e6f0086 WIP 收尾）将 timeout/ssl_client_cert 接线至 Downloader+HttpFetcher+调用点，redirect 超限抛 `DownloadError`（含限额/URL），proxy 环境变量改为 warn+continue、显式 config proxy/`ssl_client_key`/`legacy_index`/`full_index` 通过 `Commands.unsupported_setting_error` 在 install/update/lock/cache 快速失败。仍 GAP：proxy 路由、`mirror.<url>.fallback_timeout` 无 consumer、legacy/full index 未实现、`ssl_client_key` 未接线（仅 fast-fail）。详见本子项证据节与 `spec/m7_download_settings_spec.cr`。
- M7(6) plugin evidence (a59d50f + 10e0a52): audit found installer event post-install != reference index layout after-install -> reference-compatible plugin index hooks silently never fire. Fix 10e0a52 aligns EVENTS + call site; spec/plugin_hooks_spec.cr before 5 examples 1 failure (pin example) -> after 5/0/0/0 EXIT 0; canary+install 8 fixtures dual profile 8/0/0 EXIT 0; plugin fixtures post-fix 6/0/0 dual profile. 6 existing plugin fixtures cover install/uninstall/source/git/malformatted; third-party plugin/custom-source/hook-exception differential vs vendored partial reference infeasible (system reference gem feasible, not constructed this round).
- config_spec round-trip (1eeaefb, docs-only): crystal spec spec/config_spec.cr -> 9 examples, 1 failures, 0 errors, 0 pending, SPEC_EXIT=1; failing example L97/L113
eloaded.all.should eq([] of String) got 6 gem.* keys. Root cause: global ~/.bundle/config 6 non-nil BUNDLE_GEM__* keys survive Config#all (@local.keys); environment-coupled, not logic error. nil-filter attempt ineffective (global keys non-nil); reverted per lead docs-only decision; all semantics unchanged (include global keys); spec expectation unchanged.
- Unverified/blocked (未实跑/未闭环, 复现见正文对应条目): B1 Default Gem install/materialization (SSL_CTX_load_verify_locations EXIT 1) 与 diff/spec 全覆盖; B2 IRB-in-bundle/交互/console UX (Case A exec-irb 对齐、console UX 未对齐; reline/fiddle LoadError; Case C bundler gem 不可见且无 CELERITE_REFERENCE_BUNDLER_LIB); B3 nolock 其他 show/info 重解通知场景; gem 完整模板/选项/--help 显式 unsupported; env/issue 归一化外字段与稳定集外完整输出; ABI/平台/gnu-musl 矩阵; config_spec round-trip 本环境红（global config 污染，HOME 隔离/清理前不变）; M7 spec 子集本轮已重跑 70/0/0/0 EXIT 0；4.0.24/2.7.2 全量本轮未重跑（引用 1882f53/517f69a 实测）。bridge 不可用不得视为通过。
- docs aligned to HEAD 35fa404 evidence baseline + 本 docs-only 刷新; no bin/shim/shard.lock committed. M7 checkboxes not checked.
- Recommendation: stage acceptance summary/evidence boundaries synced at 35fa404 evidence baseline + M7(4)/(6) 审计/修复 + config_spec 环境耦合记录 + M7(1)/(2) 回归证据（全量计数引用 1882f53/517f69a 实测）; await lead adjudication for task-2/task-3 closure and task-4 start.


# Subitem evidence: B1/B2 system gem discovery fix (2026-11-12, post-044aacb)

- **Scope/HEAD baseline**: 044aacba92773925965ebecdfe29bad09c20e3ab (`## main...origin/main`, worktree only `?? shard.lock` before edits). Modified `src/celerite/cli/commands_surface.cr` (+system gem fallback in `installed_gem_dir` for RubyGems sources and cached `system_gem_search_dirs` via bridge `ruby_environment` `default_gem_dir`/`gem_paths`/`user_gem_dir`, bridge-available only; PATH/GIT behavior unchanged). No bin/shim/shard.lock committed. Docs updated for evidence.
- **Baseline checks (cmd/exit)**: `crystal tool format --check src spec` EXIT 0; `crystal build --no-codegen src/cli.cr` EXIT 1 (stock OpenSSL/pkg-config blocker: `In C:\msys64\ucrt64\share\crystal\src\openssl\lib_crypto.cr:24:27 ... error executing command: sh -c 'hash pkg-config 2> /dev/null || printf %s false': 系统找不到指定的文件。`, known env limit, 非本修复引入); `git diff --check` EXIT 0 (post-edit). Build with shim for runtime verification: `PATH=C:\msys64\usr\bin;C:\msys64\ucrt64\bin;... crystal build src/cli.cr -o %TEMP%\celerite-b1b2-fix.exe --link-flags C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o` EXIT 0 (2 known deprecation warnings in `src\celerite\cli\commands_install.cr:584:43,648:20` `Deprecated File.executable?`, unchanged).
- **B1 Default Gem (≤1, repro C:\temp\defaultgem-test2, Gemfile pins `json 2.15.1`, gem present at `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1` spec `.../specifications/json-2.15.1.gemspec`)**: Before (044aacb-era celerite, probed earlier this session, `BUNDLE_GEMFILE` set) — `celerite info json` EXIT 7 `Could not find json-2.15.1 in locally installed gems`; `celerite show --paths json` EXIT 7 same. Reference `bundle _4.0.24_ info json` EXIT 0 (Path `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1`), `bundle _4.0.24_ show --paths json` EXIT 0 same path. After (patched temp bin, `CELERITE_BRIDGE_SERVER=assets/bridge/server.rb`) — `celerite-b1b2-fix info json` EXIT 0, output includes `Path: C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1` and `Default Gem: yes`; `celerite-b1b2-fix show --paths json` EXIT 0 `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1`. Before/after 对比: celerite 由“找不到本地 gem”转为与 bundle 一致定位 system/default gem 路径与元数据（本受控场景）。未验证/阻塞保留: `C:\temp\defaultgem-test2` `celerite install --local`/`install` 历史阻塞 `SSL_CTX_load_verify_locations: error:80092004:system library::Unknown error` EXIT 1（含 `SSL_CERT_FILE=C:/msys64/ucrt64/ssl/cert.pem` 仍失败）未在本轮重试（≤1/非本修复路径）；Default Gem 稳定 diff/spec 全覆盖仍未验证。
- **B2 check 依赖发现 (≤1, repro C:\temp\m7s3-irb-bundle\project, Gemfile irb, lock irb 1.18.0+deps satisfied from `GEM_PATH=C:/Ruby40-x64/lib/ruby/gems/4.0.0`)**: Before — `bundle _4.0.24_ check` EXIT 0 "The Gemfile's dependencies are satisfied"; `celerite check` (044aacb-era/local bin behavior probed earlier) EXIT 1 "The following gems are missing" listing locked gems not found in bundle path. After (patched temp bin, bridge server set) — `celerite-b1b2-fix check` EXIT 0 "The Gemfile's dependencies are satisfied". Root cause confirmed: `installed_gem_dir` 仅查 bundle install path，未查 system GEM_PATH/default gem dirs；修复为 RubyGems 源在 bundle 未命中时回退系统 gem 目录（bridge 可用）。
- **B2 console/exec IRB-in-bundle 行为（本轮未改代码，仅记录边界）**: 受控 probe `C:\temp\m7s3-irb-bundle\project`（HOME `C:\temp\m7b2-irbin-home`）下 `bundle _4.0.24_ exec irb --version` 与 `celerite exec irb --version` 均 EXIT 1，reline 0.7.0/fiddle `LoadError cannot load such file -- fiddle/import`（Ruby 4.0 Windows 环境依赖链问题，同类根因）；`bundle console`/`celerite console` exit/UX 仍存在已知差异（历史取证）。IRB-in-bundle 稳定可用正例 **未验证/阻塞**（依赖 materialization/reline-fiddle 链，≤1 尝试未获稳定对照）；console UX 对齐非低成本，本子项未改。
- **Targeted regression**: `PATH=C:\msys64\usr\bin;... crystal spec spec/m7_installed_discovery_spec.cr --link-flags ...evp_md_size_shim.o` EXIT 0, **20 examples, 0 failures, 0 errors, 0 pending**.
- **未重跑/未验证（保持）**: M7 spec 全子集/全量 differential 4.0.24 130:123/7/0、2.7.2 130:123/6/1 未在本修复后重跑（不得虚报）；B1 Default Gem install/SSL 及 diff/spec 全覆盖未验证；B2 IRB-in-bundle 可用/交互、console UX 完全对齐、Case C、`gem` 完整矩阵、env/issue 外字段全量、ABI/平台/gnu-musl、其他 show/info 重解通知等仍未验证/阻塞（复现见上文及本条）。M7 复选框未勾，task-2 in_progress。
## Post-37b4287 probe evidence (2026-11-12, 37b4287, docs-only sync)
- **范围/HEAD**: `37b428708613ec543fbe9e5d080b4c95a8f59029`（`044aacb..37b4287` B1/B2 fix 已推送）；本子项仅同步 B1/B2/B3 取证与边界记录（docs-only），不改 `src/spec/fixtures/bin/shim/shard.lock`，M7 复选框未勾，task-2 `in_progress`。工作区除 `?? shard.lock` 外无其他改动。
- **门禁（本轮）**: `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 1（既有环境阻塞 `openssl/lib_crypto.cr:24:27`，`sh -c 'hash pkg-config 2> /dev/null || printf %s false'`：系统找不到指定的文件）；`git diff --check` EXIT 0。
- **B1 Default Gem（再试≤1，受控）**: 场景 `C:\temp\defaultgem-test2`（Gemfile `gem 'json', '2.15.1'`，Gemfile.lock BUNDLED WITH 4.0.24，PLATFORMS x64-mingw-ucrt；system gem `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1` + `specifications/json-2.15.1.gemspec` 存在），`BUNDLE_GEMFILE` 指向该 Gemfile，`CELERITE_BRIDGE_SERVER` 指向仓库 `assets/bridge/server.rb`。对照（patched `%TEMP%\celerite-b1b2-fix.exe`，37b4287+shim）：`bundle _4.0.24_ info json` EXIT 0 Path `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1` vs `celerite-b1b2-fix info json` EXIT 0（含 `Path: C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.15.1`、`Default Gem: yes`）；`bundle _4.0.24_ show --paths json` EXIT 0 同 path vs `celerite-b1b2-fix show --paths json` EXIT 0 同 path；`bundle _4.0.24_ list` EXIT 0 == `celerite-b1b2-fix list` EXIT 0（`json (2.15.1)`）。`info/show/list` 在该受控场景对齐。
  - **Install/materialization（≤1，阻塞）**: `SSL_CERT_FILE=C:/msys64/ucrt64/ssl/cert.pem` 下 `celerite-b1b2-fix install --local` EXIT 1 与 `celerite-b1b2-fix install` EXIT 1，均在 `Fetching gem metadata from https://rubygems.org/. Fetching json 2.15.1` 后失败：`celerite internal error: SSL_CTX_load_verify_locations: error:80092004:system library::Unknown error`（stderr）。无法经 install 将 default gem 稳定 materialize 到 bundle 构造 bundle-installed 对照；Default Gem diff/spec 全覆盖、安装后场景 **未验证/阻塞**（SSL/OpenSSL 环境）。
  - **2026-11-14 更新（纠正 SSL 假象，M7(4)/M7(1) 相关）**：旧阻塞为陈旧二进制（mtime 2026-11-13 16:02，早于 `b8f7638` 的 `ssl_option` 守卫；`ca_certificates = config["ssl_ca_cert"].to_s` 空串路径）。当前 HEAD 重建（`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`，正斜杠，BUILD=0，2 条既有 deprecation）后实测：场景 `C:\temp\smoke-ssl`（Gemfile `source "https://rubygems.org"` + `gem "rake", "13.0.0"`），`bin\celerite.exe install` → `Fetching gem metadata from https://rubygems.org/.` / `Resolving dependencies...` / `Bundle complete! 1 Gemfile dependency, 1 gem now installed.` **EXIT 0**，Gemfile.lock 含 `remote: https://rubygems.org/` + `rake (13.0.0)`。对照（首辅实测，m02402）：纯 Crystal `HTTP::Client` + `OpenSSL::SSL::Context::Client.new` 访问 `https://rubygems.org/api/v1/gems/rake.json` → OK 200（本机 TLS/CA 无问题）。结论：真实 HTTPS 安装路径在当前 HEAD 已通；上游 harness 剩余 DNS/403 失败为进程内网络桩/出口策略环境问题（非产品差异，见 `docs/compat-matrix/generated/upstream-lockfile-v4.0.24.md` D2 节）。`bin/` gitignored 未入库；shim 仅本地。
- **B2 IRB-in-bundle（再试≤1，受控）**: 场景 `C:\temp\m7s3-irb-bundle\project`（Gemfile `gem "irb"`；Gemfile.lock irb 1.18.0 + erb 6.0.7, io-console 0.9.5, logger 1.7.0, pp 0.6.4, prettyprint 0.2.1, prism 1.9.0, rbs 4.2.0, rdoc 8.1.0, reline 0.7.0, tsort 0.2.0；BUNDLED WITH 4.0.24；PLATFORMS x64-mingw-ucrt；无 vendor/bundle），`BUNDLE_GEMFILE`/`GEM_PATH=C:/Ruby40-x64/lib/ruby/gems/4.0.0`/`HOME=C:\temp\m7b2-irbin-home`，bridge server set。`bundle _4.0.24_ check` EXIT 0 "The Gemfile's dependencies are satisfied" vs `celerite-b1b2-fix check` EXIT 0 同文；`bundle _4.0.24_ list` EXIT 0 == `celerite-b1b2-fix list` EXIT 0（11 gems 同列表）；`bundle _4.0.24_ doctor` EXIT 0 == `celerite-b1b2-fix doctor` EXIT 0（"The Gemfile's dependencies are satisfied" / "No issues found with the installed bundle"）。系统 GEM_PATH 可满足场景下 check/list/doctor 对齐。
  - **console/exec IRB-in-bundle**: `bundle _4.0.24_ exec irb --version` EXIT 1、`celerite-b1b2-fix exec irb --version` EXIT 1，均 `reline-0.7.0/lib/reline/io/windows.rb:1: warning: fiddle/import is found in fiddle, which is not part of the default gems since Ruby 4.0.0` 且 `LoadError: cannot load such file -- fiddle/import`（经 bundled_gems/reline/io/windows -> irb 1.18.0；同类环境根因）。`echo exit | bundle _4.0.24_ console` EXIT 24（"There was an error while trying to load the gem 'irb'. Gem Load Error..." + Bundler backtrace） vs `echo exit | celerite-b1b2-fix console` EXIT 1（exec-style `bundler: failed to load command: irb ... LoadError`），**UX/exit 仍不对齐**。IRB-in-bundle 稳定可用正例 **未验证/阻塞**（reline/fiddle 依赖链/Ruby 4.0 Windows，≤1）；console UX 对齐非低成本，本轮未改代码。
- **M7(1)/(2) 补强尝试**: 受控对照需使用 `script/differential`/系统 bundler 4.0.24；本轮尝试 `bash script/differential check-path`（MSYS 路径、`CELERITE_BIN` 指向 patched exe）因 harness 走 `shards build` 且环境无 `shards`/可执行判定问题失败 `script/differential: line 36: shards: command not found`、`celerite build failed`（EXIT 非 0）；另临时隔离 GEM_HOME 的 `bundle _4.0.24_` 探针因 `can't find gem bundler (= 4.0.24)` 失败。定向 differential fixture（path/group/nolock/re-resolve 如 `check-path/list-path/list-multi-group/check-satisfied-ruby-nolock` 等）**本轮未完成重跑**；nolock 既有基线保持 4/0/0 PASS（0fabf9e）。桥不可用不视为通过。
- **基线（未重跑）**: 4.0.24 **130:123/7/0**（`C:\temp\celerite-diff-full-4.0.24-execloader-final.log`，2026-11-12 08:02:07）、2.7.2 **130:123/6/1**（`C:\temp\celerite-diff-full-2.7.2-8d20c17.log`，2026-11-12 10:12:15 CST）未在 37b4287 及本轮后重跑；M7 spec 子集 70/0/0/0（ae8eafc）未重跑；不得虚报。M7 复选框未勾，task-2 `in_progress`，不启动 task-3/M8；不提交 `bin/`/shim/`shard.lock`/无关文件。
## Subitem evidence: differential harness CELERITE_BIN skip-rebuild (2026-11-12, post-bba7949)
- **范围/HEAD**: 基于 `bba7949ebf2fb4cfe10a66c66fa70024eb8382aa`（docs-only probe 证据已推送）；本子项修复 `script/differential` 使其在显式提供可用引擎二进制时可跳过 `shards build`，并实跑定向 differential fixture 双 profile。未改 `src/spec/fixtures/bin/shim/shard.lock`；M7 复选框未勾，task-2 `in_progress`。
- **根因（可复现）**: `script/differential` 原逻辑 `if [ ! -x "$celerite_bin" ]; then (cd "$repo_root" && shards build >/dev/null) || { echo "celerite build failed" >&2; exit 2; } fi`。在未安装/不可见 `shards` 的环境中，即使提供 `CELERITE_BIN`（patched/shim bin）也会尝试重建并失败：`script/differential: line 36: shards: command not found` + `celerite build failed`，EXIT 2（本轮复现于 `bash script/differential check-path` / MSYS 调用路径）。
- **修复（低成本、最小改动）**: `script/differential` 现逻辑——当设置 `CELERITE_BIN` 时仅校验文件存在（`-f`），不存在则 `CELERITE_BIN not found` EXIT 2，**存在则跳过 `shards build`**（由调用方显式提供引擎，不静默跳过产品构建语义/不伪造通过）；未设置 `CELERITE_BIN` 时保持原行为：默认 `bin/celerite` 不可执行则 `shards build`。改动文件 `script/differential`（+12/-3）。
- **门禁/检查（本轮）**: `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 1（既有环境阻塞：`openssl/lib_crypto.cr:24:27`，`sh -c 'hash pkg-config 2> /dev/null || printf %s false'` 系统找不到指定的文件）；`git diff --check` EXIT 0。
- **受控实跑（定向 differential fixtures，双 profile，patched bin）**:
  - 环境/命令：Git Bash `C:\Program Files\Git\bin\bash.exe`（提供 `diff/sed/awk`），`CELERITE_BIN=/c/Users/ShiningRay/AppData/Local/Temp/celerite-b1b2-fix.exe`（37b4287 shim build，本地临时，未提交），`CELERITE_BRIDGE_SERVER=/c/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb`，`BUNDLER_REF_VERSION=4.0.24|2.7.2`，`bash script/differential check-path list-path list-multi-group check-satisfied-ruby-nolock list-satisfied-ruby-nolock check-missing-ruby-nolock list-missing-ruby-nolock`。
  - **4.0.24** EXIT 0：`differential (4.0.24): 7 passed, 0 failed, 0 skipped (documented deferrals)`；逐例 `PASS check-path (exit=0), PASS list-path (exit=0), PASS list-multi-group (exit=0), PASS check-satisfied-ruby-nolock (exit=0), PASS list-satisfied-ruby-nolock (exit=0), PASS check-missing-ruby-nolock (exit=1), PASS list-missing-ruby-nolock (exit=1)`。
  - **2.7.2** EXIT 0：`differential (2.7.2): 7 passed, 0 failed, 0 skipped (documented deferrals)`；逐例同上（exit 0/0/0/0/0/1/1）。
- **未验证/阻塞（本子项未跑）**: “回归 27 例约束集”本轮未重跑（未验证）；其他定向/全量 differential 与 M7 spec 子集未在本提交后重跑；全量基线 4.0.24 **130:123/7/0**（`C:\temp\celerite-diff-full-4.0.24-execloader-final.log`）/2.7.2 **130:123/6/1**（`C:\temp\celerite-diff-full-2.7.2-8d20c17.log`）/M7 subset **70/0/0/0** 保持既有记录未虚报。MSYS bash 无 `diff` 时 harness 比较阶段会报 `diff: command not found` 并误判 FAIL（工具依赖，非 fixture 语义失败），需在含 `diff/sed/awk` 的 shell 环境运行（本轮用 Git Bash 验证通过）。M7 复选框未勾，task-2 `in_progress`，不提交 `bin/`/shim/`shard.lock`/无关文件。
## Subitem evidence: post-6eee96a constraint regression rerun (2026-11-12)
- **范围/HEAD**: 基于 `6eee96a828e7c5c2dce69b66a3e0b0d690135223`（harness `CELERITE_BIN` skip-rebuild 修复已推送）；本子项为 docs-only 证据同步，记录用修复后 harness 重跑约束/定向回归集的结果与边界。未改 `src/spec/fixtures/bin/shim/shard.lock`/无关文件；M7 复选框未勾，task-2 `in_progress`。工作区除 `?? shard.lock` 外无其他改动。
- **门禁（本轮）**: `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 1（既有环境阻塞：`C:\msys64\ucrt64\share\crystal\src\openssl\lib_crypto.cr:24:27`，`sh -c 'hash pkg-config 2> /dev/null || printf %s false'` 系统找不到指定的文件）；`git diff --check` EXIT 0。
- **关于“27 例约束集”**: 仓库 docs/commit 历史未见精确命名为“27 例约束集”的固化清单（未验证/无此术语实跑记录）。按 lead 指定的 ruby/metadata/platform/engine/patchlevel/install-check/issue-satisfied 等可行项，本轮实跑最接近的 **28 例**（含 `ruby-api` 与 `install-check`；若按字面 27 例理解，差集为本轮多跑的 `ruby-api` 或 `install-check` 之一，证据以本实跑 28 例为准，不虚构 27 例计数）。
- **受控实跑（约束/定向集，双 profile，patched bin 未提交）**:
  - 环境/命令：Git Bash（`diff/sed/awk` 可用），`CELERITE_BIN=/c/Users/ShiningRay/AppData/Local/Temp/celerite-b1b2-fix.exe`（37b4287 shim build，本地临时，未提交），`CELERITE_BRIDGE_SERVER=/c/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb`，`BUNDLER_REF_VERSION=4.0.24|2.7.2`。
  - **4.0.24** EXIT 0：`differential (4.0.24): 28 passed, 0 failed, 0 skipped (documented deferrals)`。逐例：`PASS install-check (exit=0)`, `PASS issue-satisfied (exit=0)`, `PASS issue-missing-gems (exit=1)`, `PASS issue-no-gemfile (exit=10)`, `PASS platform (exit=0)`, `PASS platform-install (exit=7)`, `PASS platform-ruby-mismatch (exit=0)`, `PASS platform-variant-fail (exit=7)`, `PASS ruby-api (exit=0)`, `PASS ruby-engine-match (exit=0)`, `PASS ruby-engine-mismatch (exit=18)`, `PASS ruby-engine-patchlevel-match (exit=0)`, `PASS ruby-engine-version-mismatch (exit=18)`, `PASS ruby-metadata-boundary-fail (exit=6)`, `PASS ruby-metadata-boundary-match (exit=0)`, `PASS ruby-metadata-exact-match (exit=0)`, `PASS ruby-metadata-fail (exit=6)`, `PASS ruby-metadata-match (exit=0)`, `PASS ruby-patchlevel-match (exit=0)`, `PASS ruby-patchlevel-match-list (exit=0)`, `PASS ruby-patchlevel-mismatch (exit=18)`, `PASS ruby-target-match (exit=0)`, `PASS ruby-version-mismatch (exit=18)`, `PASS rubygems-metadata-boundary-fail (exit=6)`, `PASS rubygems-metadata-boundary-match (exit=0)`, `PASS rubygems-metadata-fail (exit=6)`, `PASS rubygems-metadata-match (exit=0)`, `PASS rubygems-metadata-pessimistic-match (exit=0)`。
  - **2.7.2** EXIT 0：`differential (2.7.2): 28 passed, 0 failed, 0 skipped (documented deferrals)`；逐例同上（exit 0/0/1/10/0/7/0/7/0/0/18/0/18/6/0/0/6/0/0/0/18/0/18/6/0/6/0/0）。
  - **受影响定向集（上一子项已跑、本轮复核）**：`check-path list-path list-multi-group check-satisfied-ruby-nolock list-satisfied-ruby-nolock check-missing-ruby-nolock list-missing-ruby-nolock` 双 profile 均 **7/0/0 EXIT 0**（4.0.24 与 2.7.2 逐例 exit 0/0/0/0/0/1/1，与 6eee96a 记录一致）。
- **与既有基线按名对比（无新增回归）**: 本轮 28 例约束/定向集与上一轮子项 7 例定向集在 4.0.24/2.7.2 均全 PASS；既有全量基线 **4.0.24 130:123/7/0**（`C:\temp\celerite-diff-full-4.0.24-execloader-final.log`）/ **2.7.2 130:123/6/1**（`C:\temp\celerite-diff-full-2.7.2-8d20c17.log`）/ M7 subset **70/0/0/0**（ae8eafc）**本轮未重跑（未验证）**，不得虚报；按名字比对，本轮实跑集内无新增 FAIL/SKIP，全量基线未变。
- **未验证/阻塞（保持）**: “27 例约束集”无仓库内固化定义，按最接近 28 例实跑并如实记录；全量 differential、M7 spec 子集、B1 install/SSL、Default Gem diff/spec 全覆盖、B2 IRB-in-bundle 稳定可用/console UX、Case C、gem 完整矩阵/`--help`、env/issue 外字段、ABI/平台/gnu-musl、其他 show/info 重解通知等仍未验证/阻塞（复现见前文各条）。MSYS bash 缺 `diff` 时 harness 比较阶段会误判 FAIL（工具依赖，非语义失败），本轮用 Git Bash 验证通过。bridge 不可用不视为通过；stock OpenSSL/pkg-config 阻塞持续（shim 本地未提交）。
- **结论**: M7(1)-(3) 复选框未勾；task-2 `in_progress`；不启动 task-3/M8；不提交 `bin/`/shim/`shard.lock`/无关文件。
## Subitem evidence: post-37b4287 full 4.0.24 differential rerun (2026-11-12, HEAD=1882f53)

- **范围/HEAD**: `1882f53a96b83f5968d6997d687b75bdc2bc7ad0`（docs-only，`## main...origin/main`，工作区仅 `?? shard.lock`）。本子项为 docs-only 证据同步：37b4287（system-gem fallback）之后的全量 4.0.24 differential 由另一工人执行，本轮**独立核实日志**（未重跑 differential），仅追加本证据节；不改 `src/spec/fixtures/bin/shim/shard.lock`，M7 复选框未勾，task-2 `in_progress`。
- **命令（按派工记录；log 本身不含命令行）**: Git Bash + `CELERITE_BIN`/`CELERITE_BRIDGE_SERVER`/`BUNDLER_REF_VERSION=4.0.24 TMPDIR=/c/temp bash script/differential | tee /c/temp/celerite-diff-full-4.0.24-1882f53.log`。
- **日志独立核实**: log `C:\temp\celerite-diff-full-4.0.24-1882f53.log` 末行 summary `differential (4.0.24): 126 passed, 7 failed, 0 skipped (documented deferrals)`；逐例计数 PASS=126 / FAIL=7 / SKIP=0，合计 133 = 126+7+0（与首辅审计一致）。
- **实际 exit**: 日志未含显式 wrapper/tee exit 行（`DIFF_FULL_EXIT` 标记不存在）；按 `script/differential` 末尾 `[ "$fail" -eq 0 ]` 语义，7 failed ⇒ harness exit 非 0（=1）。tee 管道 wrapper exit **未验证**（日志无记录）。
- **FAIL 7（均 class A racc/make 环境阻塞；log 中 `make failedNo such file or directory - make` ×7、`extension build failed for racc-1.8.1` ×7，ref=0/cel=1）**: `add-group`、`add-optimistic`、`add-remove`、`add-version`、`cache-all-platforms`、`native-ext-target`、`native-ext`。与基线 `C:\temp\celerite-diff-full-4.0.24-execloader-final.log`（130:123/7/0）**按名完全一致 ⇒ 零回归**。
- **+3 新 fixture 全 PASS**: `issue-satisfied`、`check-satisfied-ruby-nolock`、`list-satisfied-ruby-nolock`（均 `PASS ... (exit=0)`；126 = 123 + 3）⇒ 37b4287 system-gem fallback 无新增失败。
- **2.7.2 全量**: 本轮未重跑（**未验证**）；复现：`BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`。最近实测基线 130:123/6/1（`C:\temp\celerite-diff-full-2.7.2-8d20c17.log`，2026-11-12 10:12:15 CST）。
- **环境阻塞（持续）**: stock `crystal build src/cli.cr` 受 OpenSSL/pkg-config 阻塞（`openssl/lib_crypto.cr:24:27` + `sh -c 'hash pkg-config 2> /dev/null || printf %s false'`：系统找不到指定的文件）；CLI/differential 证据依赖仓库外 shim + `--link-flags` 本地 bin（未入库，`bin/` gitignored）。bridge 不可用不视为通过。
## Subitem evidence: post-37b4287 full 2.7.2 differential rerun (2026-11-13, HEAD=517f69a)

- **范围/HEAD**: `517f69a33724d95dc8572094ba3b76b366c53b17` (`## main...origin/main`, 工作区仅 `?? shard.lock`)。按首辅 m02420 指派前台重跑全量 2.7.2 differential; 上一轮后台运行中断于 77/133、无 summary 行 (`C:\temp\celerite-diff-full-2.7.2-517f69a.log` mtime 00:01:06 后无写入), 该日志作废、本轮不引用。仅改 `docs/compat-report.md`; M7 复选框未勾, task-2 `in_progress`, 不启动 task-3/M8。
- **命令 (Git Bash, shim 本地 bin, 未提交)**: 前置 `C:\Users\ShiningRay\AppData\Local\Temp\celerite-b1b2-fix.exe --version` -> `0.1.0` EXIT 0; `CELERITE_BIN=/c/Users/ShiningRay/AppData/Local/Temp/celerite-b1b2-fix.exe CELERITE_BRIDGE_SERVER=/c/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb BUNDLER_REF_VERSION=2.7.2 TMPDIR=/c/temp bash script/differential 2>&1 | tee /c/temp/celerite-diff-full-2.7.2-517f69a-rerun.log; echo "DIFF_EXIT=${PIPESTATUS[0]}"`。诚实注: pwsh 工具调用 10 分钟上限将作业转后台 (pwsh-ee39019891c74c5f), tee 日志持续写入至 summary 行完成。stock `crystal build src/cli.cr` OpenSSL/pkg-config 阻塞持续 (shim 仅本地, 未入库)。
- **实测结果**: `differential (2.7.2): 126 passed, 6 failed, 1 skipped (documented deferrals)`; PASS=126 + FAIL=6 + SKIP=1 = 133 (= fixture 目录数, 全部运行)。日志 `C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log` (12138 bytes, mtime 2026-11-13 00:24:35 CST, 284 行, 末行 summary; 日志内无 exit 标记)。exit: tee/bash 包装作业 exit 0; harness 侧按 `script/differential` 末尾 `[ "$fail" -eq 0 ]` 语义 6 failed => exit 1 (作业输出回显 `DIFF_EXIT=1[0]`, 为 PIPESTATUS echo 与 job 包装标记合并的渲染产物, 如实记录)。
- **FAIL 6 (均 class A racc/make 环境阻塞, ref=0/cel=1, `extension build failed for racc-1.8.1` + `make failedNo such file or directory - make`)**: `add-optimistic` (`add racc --optimistic`)、`add-remove` (install/add racc/remove racc; stdout `13c13 < racc (~> 1.8) was removed. --- > racc was removed.`)、`add-version` (`add racc --version=1.8.1`)、`cache-all-platforms` (stdout 缺 `Bundle complete!...`/vendor/cache 行 + project tree 多 `.bundle`/`Gemfile.lock`/`vendor`)、`native-ext-target` (install --target-rbconfig=rbconfig.rb/exec ruby inline.rb)、`native-ext` (install/exec; installed tree 多 racc-1.8.1)。与基线 A:6 按名完全一致。
- **SKIP 1**: `add-group` (harness documented deferral: reference 2.7.2 auto-installs Bundler 4.0.24 from rubygems.org, offline sandbox 无法证明该路径)。
- **按名对比 (零回归确认)**: vs 基线 `C:\temp\celerite-diff-full-2.7.2-8d20c17.log` (130:123/6/1, HEAD=`8d20c17`): 6 个 racc/make FAIL 名相同、`add-group` SKIP 相同; class C `clean-force`/`clean-unused` (8d20c17 修复) 与 B:1 `exec-loader`/`exec-loader-disabled` (20690ff 修复) 本轮均 PASS; **无新增失败名** => 37b4287 system-gem fallback 零回归。Delta: +3 fixtures / +3 passed (123->126)。
- **新 fixture 在 2.7.2 的表现 (如实)**: `issue-satisfied` (exit=0)、`check-satisfied-ruby-nolock` (exit=0)、`list-satisfied-ruby-nolock` (exit=0) 均 PASS, 与 4.0.24 全量 (133:126/7/0, `C:\temp\celerite-diff-full-4.0.24-1882f53.log`) 表现一致。
- **对比 4.0.24 全量 (本轮不重跑, 引用既有实测)**: 4.0.24 133:126/7/0 (A:7 含 `add-group`; 无 B:1); 本轮 2.7.2 133:126/6/1 (A:6 + SKIP `add-group` deferral; class C 0、B:1 0)。`add-group` 形态差异 (2.7.2 SKIP deferral vs 4.0.24 class A FAIL) 为 harness/network 环境约束, 非产品回归断言。
- **未验证/阻塞 (保持)**: M7 spec 子集 70/0/0/0 (ae8eafc) 本轮未重跑; B1 Default Gem install/SSL 及 diff/spec 全覆盖、B2 IRB-in-bundle/console UX、Case C、`gem` 完整矩阵、env/issue 外字段、ABI/平台/gnu-musl 等仍未验证 (复现见正文各条)。bridge 不可用不视为通过。
- **结论**: 2.7.2 全量基线更新为本轮实测 133:126/6/1 (harness exit 1), 37b4287 零回归; M7 复选框不勾, task-2 `in_progress`。

## Subitem evidence: M7(1)/(2) combo fixtures list-path-only-group + multi-platform-install-ruby (2026-11-13, HEAD=4c2404a)

- **范围/HEAD**: `4c2404a78e805dacbf5f03d481d0b4bffd6b2077`（`## main...origin/main`，工作区仅 `?? shard.lock`）。本子项新增 2 个 differential fixtures（M7(1) 平台变体正例 + M7(2) path/group/`--only-group` 组合）并双 profile 实跑 + 43 例 M7 回归 + M7 spec 子集重跑；未改 `src/`/`spec/`（fixtures + docs only）。不提交 `bin/`/shim/`shard.lock`/无关文件；M7 复选框未勾，task-2 `in_progress`。
- **新 fixtures（LF，CR=0 byte 校验）**:
  - `fixtures/differential/list-path-only-group/`：command `lock\nlist --only-group default\n`；Gemfile `source "https://rubygems.org"` + `gem "example", path: "vendor/example"` + `gem "example2", path: "vendor/example2", group: :test`；extra/vendor/example{,2}/*.gemspec（name example/example2 1.0.0，summary "Path source fixture" / "Path source fixture 2"）+ lib stub。覆盖 path 源 + group + `--only-group default`（test 组 path gem 被排除）。
  - `fixtures/differential/multi-platform-install-ruby/`：command `lock --add-platform ruby\ninstall\ncheck\n`；Gemfile `source "file:///@INDEX_DIR@"` + `gem "json_pure"` + `gem "thor"`；installed-tree `ruby/*/gems`+`ruby/*/specifications`。覆盖 ruby platform add-platform 正例（与既有 `multi-platform-install` x86_64-linux 互补）。
- **命令/exit（本轮子项实跑，shim 本地 bin `C:\Users\ShiningRay\AppData\Local\Temp\celerite-b1b2-fix.exe` + `CELERITE_BRIDGE_SERVER=<repo>/assets/bridge/server.rb`，`TMPDIR=/c/temp`）**:
  - 4.0.24 定向：`CELERITE_BIN=/c/Users/ShiningRay/AppData/Local/Temp/celerite-b1b2-fix.exe CELERITE_BRIDGE_SERVER=/c/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb TMPDIR=/c/temp bash script/differential list-path-only-group multi-platform-install-ruby` → EXIT 0，`PASS list-path-only-group (exit=0)`、`PASS multi-platform-install-ruby (exit=0)`，`differential (4.0.24): 2 passed, 0 failed, 0 skipped`（log `C:\temp\celerite-diff-m7combos-4024.log`）。
  - 2.7.2 定向：同上 + `BUNDLER_REF_VERSION=2.7.2` → EXIT 0，`differential (2.7.2): 2 passed, 0 failed, 0 skipped`（log `C:\temp\celerite-diff-m7combos-272.log`）。
  - 43 例 M7 回归集双 profile（约束/metadata/platform/engine/patchlevel/nolock/path-git/group/discovery/exec-loader/clean + 2 新 fixture）：4.0.24 `differential (4.0.24): 43 passed, 0 failed, 0 skipped` EXIT 0（log `C:\temp\celerite-diff-m7combos-reg-4024.log`）；2.7.2 同 43/0/0 EXIT 0（log `C:\temp\celerite-diff-m7combos-reg-272.log`）。非零 exit 例（issue-missing-gems 1、issue-no-gemfile 10、platform-install/platform-variant-fail 7、ruby-*-mismatch 18、metadata-fail 6、check/list-missing-ruby-nolock 1、exec-loader(-disabled) 42）均为 reference 预期 exit 且 PASS。
  - M7 spec 子集（8 文件）本轮重跑：`crystal spec spec/m7_reverse_dependencies_spec.cr spec/m7_installed_discovery_spec.cr spec/m7_platform_match_spec.cr spec/m7_ruby_constraints_spec.cr spec/m7_resolver_ruby_constraints_spec.cr spec/ruby_version_spec.cr spec/m7_ruby_runtime_spec.cr spec/m7_platform_spec.cr` → **70 examples, 0 failures, 0 errors, 0 pending, EXIT 0**（17.91s）。
- **门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（2 条既有 deprecation warnings `src\celerite\cli\commands_install.cr:577:43,641:20` `Deprecated File.executable?`）；`git diff --check` EXIT 0。
- **诚实注**：定向/回归 differential 在 HEAD=4c2404a + 2 个未提交 fixture 目录（worktree）上实跑（harness 读 worktree fixtures），fixtures 随本子项 closing commit 提交；全量 4.0.24/2.7.2 本轮未重跑（引用 1882f53 133:126/7/0 与 517f69a-rerun 133:126/6/1 实测）；B1 Default Gem、B2 console UX/IRB-in-bundle、Case C、gem 完整矩阵、env/issue 外字段、ABI/gnu-musl 等维持未验证/阻塞（复现见正文各条）。
- **结论**：M7(1)/(2) 组合覆盖各 +1 个稳定正例 fixture，双 profile 定向与 43 例回归零失败；M7 复选框不勾，task-2 `in_progress`。
## Subitem evidence: M7(4) read-code audit + redirect typing fix (2026-11-13, HEAD=e77c6cb, shim local bin)

- Scope/HEAD: e77c6cb (task-3 first subitem accepted). Audit per lead assignment (--retry, mirror/proxy/redirect, SSL CA/client cert, path.system, build.<gem>, legacy-full index): real-effect vs explicit fast-fail vs silent-ignore. Verdicts are code-read evidence (file:line); per-setting runtime differential not covered except the canary set below (marked 未验证 where applicable).
- Audit table (item | verdict | evidence):
  | item | verdict | evidence (file:line) |
  |---|---|---|
  | `--retry` / `retry` | real effect | commands.cr L22 GLOBAL_FLAGS, L117-125 parse -> ENV CELERITE_CLI_RETRY, L138-162 retry_count() (CLI > cfg["retry"] > 3); wired commands_install.cr L111/209/229/791 + commands_surface.cr L113/994/1173/1522; downloader.cr L196-219 exponential backoff; cache.cr L97-125 + L140-143 retryable 408/429/5xx |
  | `mirror.<url>` | real effect | config.cr L315-333 mirror_for (± trailing slash); downloader.cr L138-148 mirror-first then fallback; cache.cr L90-95 + L128-138 |
  | `redirect` (HTTP follow) | real effect, NO limit | downloader.cr L225-231 + cache.cr L103-107 follow 301/302/303/307/308 via Location unconditionally |
  | `redirect` (key typing) | latent bug FIXED this subitem | config.cr had "redirect" in BOTH BOOL_KEYS (L19) and NUMBER_KEYS (L25); convert() L369-383 checks BOOL_KEYS first -> convert("5","redirect") = to_bool("5") = true (to_bool L385-393); grep `config\["redirect"\]|\["redirect"\]|cfg\["redirect"\]` over src = 0 consumers -> zero behavioral effect pre-fix. Fix: removed "redirect" from BOOL_KEYS (NUMBER_KEYS retained); spec/config_spec.cr L55 + L91-92 assert config["redirect"] == 5 default and convert("5","redirect") == 5 / convert("0","redirect") == 0 |
  | `ssl_ca_cert` | real effect | commands_install.cr L111/209/229/791 + commands_surface.cr L113/994/1173/1522 pass into Downloader.new; downloader.cr L171-187 ctx.ca_certificates=ca; cache.cr L151-153 |
  | `ssl_verify_mode` | real effect | downloader.cr L178-185 ("none" -> VerifyMode::NONE, "peer" -> PEER); cache.cr L154-160 |
  | `credentials` | real effect | config.cr L347-367 credentials_for (full URI then host); downloader.cr L191-195 basic_auth; cache.cr L167-169 |
  | `path.system` | real effect (conditional, simplified semantics) | resolution.cr L13-21: `path` empty AND path.system == true -> File.expand_path(Config.user_home); config BOOL_KEYS L22 zone. Note: reference installs to system gem dir; celerite returns user home — semantics simplified (recorded, not fixed) |
  | `build.<gem>` | real effect | installer.cr L26-30 config_build_args reads cfg["build.#{name}"]; L142-145 build_args -> @bridge.build_extension |
  | `proxy` | silent ignore (gap) | no src hits; HTTP::Client constructed without proxy |
  | `timeout` | silent ignore (gap) | config NUMBER_KEYS L25; HttpFetcher @timeout default 30s cache.cr L69 but make_fetcher L554-575 does NOT pass it; Downloader hardcodes 30s connect / 120s read (downloader.cr L189-190/L208-209) |
  | `ssl_client_cert` | silent ignore (gap) | stored downloader.cr L25 / cache.cr L66-81, never applied in TLS ctx (downloader.cr L171-187 and cache.cr L147-173 use only ssl_ca_cert + ssl_verify_mode) |
  | `ssl_client_key` | silent ignore (gap) | not read at all |
  | `mirror.<url>.fallback_timeout` | silent ignore (gap) | getter config.cr L335-338, no consumer |
  | legacy/full index fallback | not implemented | cache.cr compact-index only (L274 layout /versions, /info/<gem>, names); FileFetcher L39 "Always returns the full content"; no full-index fallback path |
- Fix + spec evidence: config.cr BOOL_KEYS L19 "redirect" removed (NUMBER_KEYS L25 retained); spec/config_spec.cr L55 + L91-92 new asserts; `crystal spec spec/config_spec.cr` -> 9 examples, 1 failures, 0 errors, 0 pending — the 1 failure is PRE-EXISTING round-trip (`reloaded.all.should eq([] of String)`, spec/config_spec.cr:97 with this subitem's line offset / :94 on clean HEAD); baseline proof: `git stash` of this subitem's changes on clean HEAD e77c6cb fails the same example (config_spec.cr:94) — NOT introduced by this change; the new redirect asserts pass. Repro: `crystal spec spec/config_spec.cr`.
- Canary regression (config display surface, dual profile): `CELERITE_BIN="$PWD/bin/celerite.exe" CELERITE_BRIDGE_SERVER="$PWD/assets/bridge/server.rb" TMPDIR=/c/temp bash script/differential env-report config-global fund-path show-info-installed` + `BUNDLER_REF_VERSION=2.7.2` variant -> 4 passed / 0 failed / 0 skipped, EXIT 0 both profiles (logs `C:\temp\celerite-diff-m74-canary-4024.log`, `C:\temp\celerite-diff-m74-canary-272.log`). Bin rebuilt with shim after the code change: BUILD_EXIT=0, `bin/celerite.exe --version` 0.1.0 VER_EXIT=0.
- Remaining gaps (recommended follow-ups, not fixed this round): enforce max-redirect limit (needs redirect counter in downloader/cache + differential harness for redirects); implement or explicitly fast-fail proxy / timeout / ssl_client_cert / ssl_client_key / mirror.<url>.fallback_timeout; legacy-full-index fallback is a design tradeoff; path.system semantics alignment vs reference system-gem dir. Pre-existing config_spec round-trip failure (all-after-unset) recorded with baseline proof; recommend separate low-cost fix subitem.
- Unverified: full 135-fixture suites NOT rerun after this 1-line change (repro: `CELERITE_BIN="$PWD/bin/celerite.exe" CELERITE_BRIDGE_SERVER="$PWD/assets/bridge/server.rb" [BUNDLER_REF_VERSION=2.7.2] TMPDIR=/c/temp bash script/differential`); baselines unchanged 4.0.24 133:126/7/0 (@1882f53) and 2.7.2 133:126/6/1 (@517f69a-rerun); audit is code-read evidence (no per-setting runtime proof beyond canaries); bridge unavailable ≠ pass; stock OpenSSL EVP_MD_size blocker + shim local-only recorded.
## Subitem evidence: M7(4) silent-ignore disposition (2026-11-13, HEAD=3c3f52e, docs-only)

- Scope/HEAD baseline: 3c3f52e (stage summary refresh + M7(1)/(2) regression evidence). This subitem is docs-only disposition (code read + grep evidence); no code changes landed this round (fast-fail/real-effect implementation deferred to a follow-up subitem or lead adjudication).
- **Key -> read site -> status -> disposition table**:
  - proxy / http_proxy / https_proxy: NO key in BOOL/NUMBER/ARRAY_KEYS; no code path in src/; env HTTP_PROXY/HTTPS_PROXY never read -> **GAP** (no consumer). Disposition: document as unsupported; fast-fail not wired (no read site to gate).
  - 	imeout (NUMBER_KEY, default 10): Downloader hardcodes connect_timeout=30s/read_timeout=120s; HttpFetcher @timeout param exists but make_fetcher does not pass config timeout -> **SILENT IGNORE** (config value unused). Disposition: wire timeout into Downloader + HttpFetcher in follow-up (real-effect) OR fast-fail.
  - ssl_ca_cert: REAL (used in both Downloader and HttpFetcher TLS ctx).
  - ssl_client_cert: stored unused in both Downloader and HttpFetcher (getter only, never applied to TLS ctx) -> **GAP** (parsed but never applied).
  - ssl_client_key: not read anywhere -> **GAP**.
  - ssl_verify_mode: REAL (used in both Downloader and HttpFetcher TLS ctx).
  - mirror / mirror.<url>: REAL (mirror_for used; mirror fallback in Downloader).
  - mirror.<url>.fallback_timeout: getter exists but NO consumer -> **SILENT IGNORE**.
  -
edirect (NUMBER_KEY, default 5): Downloader follows 301/302/303/307/308 unconditionally with NO limit/count -> **SILENT IGNORE** (no enforcement of BUNDLE_REDIRECT).
  - legacy/full index: not implemented (compact-only) -> **GAP**.
  - path.system: REAL conditional effect (user_home install base).
- **Read sites (file:line)**:
  - config.cr: BOOL_KEYS L14-23 (incl path.system L22); NUMBER_KEYS L25 (jobs/retry/redirect/timeout/cooldown); mirror_for L318-333; mirror_fallback_timeout L335-342 (no consumer); key_for L6727; convert L13064; all L2239.
  - downloader.cr: initialize L29 (ssl_client_cert stored); download_to L131-240 (hardcoded 30/120 L189-190; redirect follow L225-231 no limit; ssl_ca_cert/verify_mode used in TLS ctx L171-187; ssl_client_cert NOT applied).
  - compact_index/cache.cr: HttpFetcher initialize L69 (@timeout param, default 30s); perform L147-173 (ssl_ca_cert/verify_mode used; ssl_client_cert NOT applied); make_fetcher L554-575 (HttpFetcher.for does not pass timeout); HttpFetcher.for L77-81 (no timeout param).
  - resolution.cr: install_path L12-21 (path.system consulted).
  - commands_install.cr L111/209/229/791; commands_surface.cr L113/994/1173/1522 (Downloader.new call sites passing ssl params).
- **Gates**: crystal tool format --check src spec EXIT 0; crystal build --no-codegen src/cli.cr EXIT 0 (2 deprecation warnings); git diff --check EXIT 0; CR=0.
- **Unverified/blocked**: runtime proof per-setting (no live network to exercise proxy/timeout/redirect/ssl_client_cert); fast-fail implementation not landed (docs-only disposition this round); full 135-fixture dual profile unrun (explicit + repro); bridge unavailable != pass; stock EVP_MD_size + shim local-only recorded; M7 checkboxes not checked; task-2/task-3 in_progress; no task-4/M8.
- **Repro for follow-up implementation**: set BUNDLE_PROXY/BUNDLE_TIMEOUT/BUNDLE_SSL_CLIENT_CERT/BUNDLE_SSL_CLIENT_KEY/BUNDLE_MIRROR_..._FALLBACK_TIMEOUT/BUNDLE_REDIRECT and run bundle install against a remote source; observe current behavior (ignored). Follow-up subitem should land real-effect or fast-fail + spec + differential affected-set regression.

## Subitem evidence: M7(6) plugin command/hook audit (2026-11-13, HEAD=94ec377, docs-only)

- Scope: lead m03973 item 1 (plugin command registration + plugin_hooks post-install failure policy audit). Docs-only; no behavior change this subitem. Event-name alignment fix authorized separately (lead m04050) as follow-up subitem with before/after spec evidence.
- Command surface (src/celerite/cli/commands_surface.cr L825-933, read-code verdicts): `plugin list` -> installed_plugins; empty case stdout `No plugins installed` exit 0; `plugin install` without names -> stderr `No plugin sources specified` exit 1; `install --path` local -> Definition.build + bridge.load_gemspec_dir + writes project `.bundle/plugin/index` YAML (bare-key commands/hooks/load_paths/plugin_paths/sources layout, L882-898) + stdout `Installed plugin <name>` exit 0; `install --git/--source` remote -> plugin_install_remote (L938+, temp Gemfile + resolve + materialize .bundle/plugin/{gems,cache,specifications,extensions,doc,build_info,plugins}); remote without git -> stderr `Plugin installation from remote sources requires git; use --path for a local plugin directory.` exit 19 (L857-858); `plugin uninstall` (--all/names; not-installed skip `Plugin <name> is not installed `; write_plugin_index preserves others; no-targets `No plugins installed` exit 0); `plugin new` -> explicit `The 'plugin new' command is not implemented yet.` exit 1 (L927); unknown sub -> `Could not find command "plugin <sub>".` exit 15 (L930-931). plugins.rb missing on remote install -> stderr `Failed to install plugin \`<name>\`, due to Bundler::Plugin::MalformattedPlugin (plugins.rb was not found in the plugin.)` (L1050-1053).
- Hook chain (post-install policy): commands_install.cr L293-298 calls PluginHooks.call(bridge, definition, "post-install") inside begin/rescue Bridge::BridgeError - hook failure must not fail install (reference friendly-error parity); plugin_hooks.cr (35 lines) EVENTS = ["post-install"] (L9), index_path project-local <gemfile_dir>/.bundle/plugin/index (L22-24), call -> bridge.exec_plugin_hook (L26-33); assets/bridge/server.rb op_exec_plugin_hook L287-326: no index -> {"fired"=>false,"reason"=>"no plugin index"} (L293); hook_plugins = index["hooks"][event] DIRECT lookup, no event-name translation (L297); entry = plugin_paths[name] ? plugins.rb : name.tr("-","/") (L309); rescue LoadError/StandardError -> {"fired"=>false,"reason"=>"plugin <name> failed to load: <msg>"} (L311-312); returns {"fired"=>blocks.any?,"plugins"=>loaded} (L325); server-level rescue Exception L370 (nothing escapes).
- Measured evidence this round (HEAD=94ec377, shim local bin): 6 existing plugin fixtures dual profile PASS - `differential (4.0.24): 6 passed, 0 failed, 0 skipped` EXIT 0 (log C:\temp\celerite-diff-m76-plugins-4024.log) and `differential (2.7.2): 6 passed, 0 failed, 0 skipped` EXIT 0 (log C:\temp\celerite-diff-m76-plugins-272.log); per-case exits (both profiles identical): plugin-install 1, plugin-uninstall 0, plugin-source 7, plugin-source-ok 0, plugin-git-local 0, plugin-git-local2 0. spec/plugin_hooks_spec.cr: 3 examples, 0 failures, 0 errors, 0 pending, SPEC_EXIT=0 (2.41s) - no-op without index / third-party plugin fires via bridge (Bundler::Plugin::Events::GEM_AFTER_INSTALL + hook-fired.txt marker, index YAML hooks: after-install) / broken plugin fired=false reason contains "failed to load". Reference probe (C:\temp\plugin-probe, system bundler 4.0.24): `bundle _4.0.24_ plugin list` on empty project -> stdout `No plugins installed`, EXIT 0 (same shape as celerite list empty case); `plugin --help` lists install/uninstall/list/help + --source/--version/--git/--branch/--ref/--path/--local-git/--all.
- REAL GAP (read-code evidence; runtime before/after spec authorized as follow-up fix subitem): installer call-site event "post-install" (commands_install.cr L295) + PluginHooks::EVENTS ["post-install"] (plugin_hooks.cr L9) never match reference/spec plugin-index layout "after-install" (spec/plugin_hooks_spec.cr L47/L58/L81/L90 use after-install; vendor/reference/v4.0.24 plugin.rb L31 after_install = Bundler::Plugin::Events::GEM_AFTER_INSTALL, L39-41 def after_install); server.rb L297 direct index["hooks"][event] lookup with NO translation -> a reference-compatible plugin index (hooks registered under after-install) is silently never fired by celerite install (silent no-op, not an error). Additionally celerite `plugin install --path` writes index with EMPTY hooks: (commands_surface.cr L885) so its own installs register no hooks either.
- Profile/DSL facts (honest scope): vendor/reference is PARTIAL vendoring - v2.7.2 has no plugin DSL (only settings.rb L38 "plugins" bool key); v4.0.24 dsl.rb L240 `def plugin(*args)` + L131 InvalidOption "No plugin sources available for ..." + L139 add_plugin_source. System reference gem provides `bundle plugin` CLI (probe above, 4.0.24). System bundler-2.7.2/4.0.24 dsl.rb grep for `def plugin|plugin_source|add_plugin` -> no hits (grep evidence only; vendored v4.0.24 dsl.rb DOES contain the DSL def - vendored-vs-system discrepancy recorded, not resolved). Differential plugin fixtures are feasible against the system reference (6 existing fixtures prove it); no NEW third-party-plugin/custom-source/hook-exception fixture added this docs-only subitem.
- Unverified: full 135-fixture suites NOT rerun after this docs-only change (repro: `CELERITE_BIN="$PWD/bin/celerite.exe" CELERITE_BRIDGE_SERVER="$PWD/assets/bridge/server.rb" [BUNDLER_REF_VERSION=2.7.2] TMPDIR=/c/temp bash script/differential`); baselines unchanged 4.0.24 133:126/7/0 (@1882f53 log) and 2.7.2 133:126/6/1 (@517f69a-rerun log); config_spec round-trip pre-existing failure (independent subitem); stock OpenSSL EVP_MD_size blocker + shim local-only; bridge unavailable != pass.
- Conclusion: plugin command surface + hook chain + 6 dual-profile fixtures + 3 spec examples evidenced; one real silent gap (event-name mismatch) identified with file:line chain; minimal alignment fix authorized (lead m04050) for the follow-up subitem with before/after spec + canary + install-targeted regression. M7(6) roadmap checkbox stays unchecked.
## Subitem evidence: M7(6) plugin hook event-name alignment fix (2026-11-13, HEAD=a59d50f+worktree, shim local bin)

- Scope: lead m04050 authorized the minimal alignment fix for the silent gap recorded in the M7(6) audit (commit a59d50f, docs-only): installer call-site event "post-install" (commands_install.cr L295) + PluginHooks::EVENTS ["post-install"] (plugin_hooks.cr L9) never match the reference plugin-index layout "after-install", so reference-compatible plugin indexes were silently never fired on install. Fix (2 strings + comment): plugin_hooks.cr EVENTS = ["after-install"] (comment: reference layout name; aliases intentionally NOT kept - a legacy "post-install" key would silently never match a reference-written index); commands_install.cr L295 call "after-install". Main path aligned with reference; no alias mapping (semantic ambiguity avoided per lead m04050).
- Spec before/after (spec/plugin_hooks_spec.cr +2 examples): (a) pins PluginHooks::EVENTS == ["after-install"]; (b) documents legacy "post-install" against a reference-layout after-install index is a silent no-op (fired=false, reason "no plugins for event", marker file absent).
  - BEFORE (src pre-fix + new spec, via `git stash push -- src/celerite/plugin_hooks.cr src/celerite/cli/commands_install.cr`): `5 examples, 1 failures, 0 errors, 0 pending, SPEC_EXIT=1` - failed example "pins the hook event list to the reference after-install layout" (spec/plugin_hooks_spec.cr:97). Gap reproduced at unit level.
  - AFTER (fix applied, stash popped): `5 examples, 0 failures, 0 errors, 0 pending, SPEC_EXIT=0` (Finished in 2.66 seconds); pre-existing 3 examples unchanged green.
- Regression (shim bin rebuilt with fix: BUILD_EXIT=0, `bin/celerite.exe --version` 0.1.0 VER_EXIT=0):
  - canary + install-related targeted 8 fixtures dual profile - env-report, config-global, fund-path, show-info-installed, install-check, install-force, exec-loader, exec-loader-disabled -> 4.0.24 `differential (4.0.24): 8 passed, 0 failed, 0 skipped` EXIT 0 (log C:\temp\celerite-diff-m76-canary-install-4024.log); 2.7.2 same 8/0/0 EXIT 0 (log C:\temp\celerite-diff-m76-canary-install-272.log). Per-case exits both profiles: env-report 0, config-global 0, fund-path 0, show-info-installed 0, install-check 0, install-force 0, exec-loader 42, exec-loader-disabled 42.
  - 6 existing plugin fixtures rerun post-fix dual profile -> 4.0.24 and 2.7.2 both `6 passed, 0 failed, 0 skipped` EXIT 0 (logs C:\temp\celerite-diff-m76-plugins-postfix-4024.log / -272.log): plugin command surface unaffected by the event-name change (commands_surface.cr untouched).
- Gates: `crystal tool format --check src spec` EXIT 0 (after formatting edited files), `crystal build --no-codegen src/cli.cr` EXIT 0 (2 known deprecation warnings commands_install.cr:577:43,641:20), `git diff --check` EXIT 0.
- Unverified: full 135-fixture suites NOT rerun post-fix (repro: `CELERITE_BIN="$PWD/bin/celerite.exe" CELERITE_BRIDGE_SERVER="$PWD/assets/bridge/server.rb" [BUNDLER_REF_VERSION=2.7.2] TMPDIR=/c/temp bash script/differential`); baselines unchanged 4.0.24 133:126/7/0 (@1882f53 log) and 2.7.2 133:126/6/1 (@517f69a-rerun log); config_spec round-trip pre-existing failure (independent subitem); stock OpenSSL EVP_MD_size blocker + shim local-only; bridge unavailable != pass.
- Conclusion: the M7(6) silent hook gap is closed on the main path with before/after spec evidence and dual-profile regression; M7(6) roadmap checkbox stays unchecked (remaining: third-party plugin/custom-source/hook-exception differential coverage is infeasible against vendored partial reference but feasible against system reference gem - existing 6 fixtures already cover install/uninstall/source/git/malformatted; new fixture construction not required this round; full-suite rerun outstanding).

## Subitem evidence: config_spec round-trip pre-existing failure (2026-11-13, HEAD=10e0a52, docs-only)

- **Scope/HEAD baseline**: 10e0a52f8e805dacbf5f03d481d0b4bffd6b2077 (`## main...origin/main`, worktree only `?? shard.lock` before edits). No source change retained: `src/celerite/config.cr` reverted via `git checkout -- src/celerite/config.cr` (CHECKOUT_EXIT=0, DIFF_EXIT=0) per lead docs-only decision. No bin/shim/shard.lock committed.
- **Reproduction (cmd/exit)**: `crystal spec spec/config_spec.cr` -> **9 examples, 1 failures, 0 errors, 0 pending, SPEC_EXIT=1**; failing example `Celerite::Config writes config set/unset round-trip like the reference` at `spec/config_spec.cr:97`/`:113`, assertion `reloaded.all.should eq([] of String)` got `["gem.changelog", "gem.ci", "gem.coc", "gem.linter", "gem.mit", "gem.test"]`.
- **Root cause**: `Config#all` returns `@local.keys` (config.cr) without filtering nil, and the global `~/.bundle/config` on this host contains 6 non-nil keys: `BUNDLE_GEM__TEST/CI/MIT/COC/CHANGELOG/LINTER: "false"` (verified via `Get-Content $HOME/.bundle/config`, 6 keys). These survive `Config.load` into `@local`, so `reloaded.all` returns the 6 gem.* keys instead of `[]`. The failure is **environment-coupled** (global config pollution), not a code logic error: `Config#all` semantics intentionally include global keys.
- **Attempted nil-filter**: a 3-line `all` change filtering nil values was tried; it did NOT make the test green because the 6 global keys are non-nil strings, not nil. Reverted per lead decision (avoid unauthorized semantic change; `all` should keep global keys; do not alter spec expectation). Options (b) test isolation / (c) adjust expectation were NOT adopted.
- **Semantic decision**: keep `Config#all` including global keys (reference-compatible); do not change spec expectation to `[]`; record environment coupling + repro. Test isolation (HOME override) is a future, separate subitem if lead authorizes.
- **Baseline checks (cmd/exit)**: `crystal tool format --check src spec` EXIT 0; `crystal build --no-codegen src/cli.cr` EXIT 1 (stock OpenSSL/pkg-config blocker `openssl/lib_crypto.cr:24:27` + `sh -c 'hash pkg-config ...'` system file not found, known env limit, not introduced by this subitem); `git diff --check` EXIT 0 (post-edit).
- **Unverified/blocked**: config_spec round-trip remains red in this environment until global `~/.bundle/config` is isolated/cleaned or test HOME is overridden; no code change made. Repro: `crystal spec spec/config_spec.cr` (failure at L97/L113). Bridge unavailable != pass; stock EVP_MD_size blocker + shim local-only unchanged.
- **Conclusion**: docs-only record; no source change; task-2/task-3 remain in_progress; M7 checkboxes not checked; no task-4/M8.

## Subitem evidence: M7(4) WIP closure — timeout/ssl wiring, redirect error, proxy softening, fast-fail (HEAD=e6f0086 后，本子项)
- **Repo/HEAD**：`C:\Users\ShiningRay\projects\ShiningRay\celerite`，基线 `HEAD=origin/main=e6f0086f0f975f4d4c7250621c87875df77362c4`（`fix(M7 task-3): wire timeout/max-redirect/ssl_client_cert into Downloader and HttpFetcher`），本子项在未提交 WIP 上完成收尾。工作区保留 `?? shard.lock`（未提交）。
- **范围**：仅修改/提交 `src/celerite/cli/commands.cr`、`src/celerite/cli/commands_install.cr`、`src/celerite/cli/commands_surface.cr`、`src/celerite/compact_index/cache.cr`、`src/celerite/downloader.cr`、`src/celerite/errors.cr`、`src/celerite/resolution.cr`、`spec/m7_download_settings_spec.cr`、`docs/compat-report.md`、`docs/roadmap.md`；未提交 `bin/`、shim、`shard.lock`。
- **实现要点（key file:line，工作树）**：
  - `src/celerite/cli/commands.cr:924-985`：共享 helper 去重并集中定义 `Commands.ssl_option(config,key)`（nil/非 String/空串→nil）、`Commands.timeout_seconds(config)`（默认 10，<1 回退 10）、`Commands.unsupported_setting_error(config,stderr)`；proxy 环境变量 `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/http_proxy/https_proxy` 非空仅 `stderr.puts "warning: HTTP proxy (#{pv}) is set but Celerite does not route through proxies"` 并继续；显式 config `proxy`/`http_proxy`/`https_proxy` 非空且非 false 返回 `"not supported by Celerite: proxy"`；显式 `ssl_client_key`/`legacy_index`/`full_index` 返回对应 fast-fail 消息。`Commands.lock`（`src/celerite/cli/commands.cr`）接入 fast-fail。
  - `src/celerite/cli/commands_install.cr`：移除重复 `ssl_option`/`timeout_seconds`；`Commands.install`（~:147）与 `Commands.cache`（~:411，含 `--no-install` 路径，先建 definition 并复用）调用 `unsupported_setting_error` 后非零退出；Downloader/CompactIndex::Client 调用点统一传 `Commands.ssl_option(config,"ssl_ca_cert"|"ssl_client_cert"|"ssl_verify_mode")` 与 `timeout: Commands.timeout_seconds(config)`（含 install 主路径、spec_downloader/remote_downloader、auto_switch_bundler 等）。
  - `src/celerite/cli/commands_surface.cr:55`：移除重复 helper；`Commands.update` 接入 `unsupported_setting_error` 快速失败。
  - `src/celerite/downloader.cr:34`：新增 `def connect_timeout : Time::Span = @timeout.seconds`；保留 WIP：`getter timeout/max_redirects/redirect_count`、connect/read timeout=`@timeout.seconds`、SSL 应用 `ssl_ca_cert`/`ssl_client_cert`/`ssl_verify_mode`（空串跳过）、超重定向 `raise DownloadError.new("Too many redirects (>#{@max_redirects}) for #{@remote}")`。
  - `src/celerite/compact_index/cache.cr`：`HttpFetcher`/`Client` 接收并暴露 `ssl_ca_cert/ssl_client_cert/ssl_verify_mode/timeout`（Int32 秒），`connect_timeout/read_timeout=@timeout.seconds`，TLS 应用证书/CA/verify mode（空串跳过）。
  - `src/celerite/errors.cr`：`class DownloadError < Error`，`status_code 17`，`wrap? true`。
  - `src/celerite/resolution.cr`：CompactIndex::Client 创建传入 ssl/timeout 选项。
- **Spec**：`spec/m7_download_settings_spec.cr` **6 examples, 0 failures, 0 errors, 0 pending, EXIT 0**（`crystal spec spec/m7_download_settings_spec.cr --link-flags "C:\Users\ShiningRay\AppData\Local\Temp\celerite-shim-m7wip\evp_md_size_shim.o"`，PATH 前置 `C:\Program Files\Git\usr\bin;C:\Program Files\Git\cmd;C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin`）。覆盖：`Commands.ssl_option` nil/`""`/有效值；`Commands.timeout_seconds` 默认 10、显式 3、0→10、-5→10；`Commands.unsupported_setting_error` env `HTTP_PROXY` 非空→warn 且返回 nil，显式 `BUNDLE_PROXY`→`"not supported by Celerite: proxy"`；`Downloader.new(..., timeout: 1)` `timeout == 1` 且 `connect_timeout == 1.second`；`DownloadError` 消息含 `Too many redirects`、`>5`、URL。
- **门禁（PATH 前置同上）**：`crystal tool format --check src spec` **EXIT 0**；`crystal build --no-codegen src/cli.cr` **EXIT 0**（2 条既有 deprecation `src\celerite\cli\commands_install.cr:594:43,658:20 Deprecated File.executable?`）；`git diff --check` **EXIT 0**。
- **Fast-fail 实测（shim-built `%TEMP%\celerite-m7wip.exe`，`crystal build src/cli.cr -o %TEMP%\celerite-m7wip.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"` EXIT 0）**：
  - 显式 config：`.bundle/config` 含 `BUNDLE_PROXY: http://proxy.example:8080`，执行 install → stderr `not supported by Celerite: proxy`，**EXIT 1**。
  - 环境变量：`HTTP_PROXY=http://proxy.example:8080` → stderr `warning: HTTP proxy (HTTP_PROXY) is set but Celerite does not route through proxies` 与 `warning: HTTP proxy (http_proxy) is set but Celerite does not route through proxies`，流程继续（后因无 `CELERITE_BRIDGE_SERVER` 报 `bridge server script not found; set CELERITE_BRIDGE_SERVER` **EXIT 1**，非 proxy fast-fail，证明 warn+continue）。
- **fast-fail 接线范围**：`Commands.unsupported_setting_error` 已接入 `install`/`update`/`lock`/`cache`（含 `cache --no-install`）；其他命令未在本子项统一接线（后续可扩展）。
- **仍 GAP/未验证**：proxy 实际路由未实现（仅 warn/fast-fail 策略）；`mirror.<url>.fallback_timeout` 有 getter 无 consumer；legacy/full index 回退未实现；`ssl_client_key` 仅显式配置 fast-fail、未接线到 TLS；redirect 上限/网络行为未做端到端 differential 夹具；定向/全量 differential 本轮未重跑（未验证，复现：`CELERITE_BIN="$PWD/bin/celerite.exe" CELERITE_BRIDGE_SERVER="$PWD/assets/bridge/server.rb" TMPDIR=/c/temp [BUNDLER_REF_VERSION=2.7.2] bash script/differential install-check check-path list-path env-report`）；stock `crystal build`/无 shim spec 受 OpenSSL pkg-config/sh 环境阻塞（`C:\msys64\ucrt64\share\crystal\src\openssl\lib_crypto.cr:24:27`），shim 仅本地不入库；bridge 不可用不视为通过；M7 复选框未勾，task-2/task-3 维持 `in_progress`。
## Subitem evidence: M7(7) differential installed-tree symlink presence/type comparison + selftest (2026-11-13, updated)

- **Repo/HEAD**：`C:\Users\ShiningRay\projects\ShiningRay\celerite`，分支 `main`，基线 `HEAD=origin/main=52bf902164fd713e3095e378a59d6f33d68dff8f`；本子项在该基线上完成实现/文档/回归并提交推送。工作区保留 `?? shard.lock`（未提交）。
- **范围**：仅修改/提交 `script/differential-installed-tree`、`script/differential-installed-tree-selftest`、`docs/differential-normalization.md`、`docs/compat-report.md`；未提交 `docs/roadmap.md`（本轮未改）、`bin/`、shim、`shard.lock`、无关文件。
- **实现（`script/differential-installed-tree`）**：在路径集合/内容/可执行位比较之外增加**符号链接目标比较**。对每个匹配目录使用 `find . -type l -print | sed 's|^\./||' | LC_ALL=C sort` 枚举链接，并对 reference 侧每个链接在 celerite 侧存在为 symlink 时执行 `readlink` 比较目标；不一致输出 `  <rel>/<link> symlink target differs: ref=<tgt> cel=<tgt>` 并返回 1（不依赖 `diff -r --no-dereference` 的 GNU/BSD 版本差异）。`diff -r --brief` 仍用于路径集合/内容差异发现；对 symlink 跳过内容与可执行位比较，避免解引用误判。UTF-8 无 BOM、LF。
- **自测（`script/differential-installed-tree-selftest`）**：6 断言——(a) 完全一致 PASS；(b) 内容差异 FAIL 且含 `content differs`；(c) symlink 目标差异 FAIL 且含 `symlink target differs`；(d) 缺一个 symlink FAIL；(e) ref 普通文件 vs cel 同名 symlink（内容相同）FAIL 且含 `entry type differs`；(f) cel 侧多一个 symlink FAIL 且含 `unexpected symlink`。Windows 使用 `MSYS=winsymlinks:nativestrict ln -s` 探测/创建真实符号链接；若无法创建真实链接，(c)/(d)/(e)/(f) 记为 SKIP 并记录错误与复现命令（不伪报 PASS）。
  - **命令**：`bash script/differential-installed-tree-selftest`（Git Bash `C:\Program Files\Git\bin\bash.exe`）
  - **结果**：`== differential-installed-tree selftest ==` / `symlink probe: real symlinks available` / `PASS (a) identical trees` / `PASS (b) content differs` / `PASS (c) symlink target differs` / `PASS (d) missing symlink` / `selftest summary: 6 passed, 0 failed, 0 skipped`，**EXIT 0**。
- **installed-tree 定向 fixture 回归（双 profile，可运行且带 `installed-tree` marker）**：`git-installed-discovery` 存在但**无 `installed-tree` marker**（不适用本子项 installed-tree 比较，未作为 marker fixture 运行）。其余请求 fixture 中可运行者：`install-check`、`show-info-installed`、`install-fresh`、`install-rerun`。
  - 环境：Git Bash，`TMPDIR=/c/temp`，`CELERITE_BIN=/c/Users/ShiningRay/AppData/Local/Temp/celerite-b1b2-fix.exe`（本地 shim bin，未提交），`CELERITE_BRIDGE_SERVER=/c/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb`。
  - **4.0.24**：`BUNDLER_REF_VERSION=4.0.24 bash script/differential install-check show-info-installed install-fresh install-rerun` -> `PASS install-check (exit=0)` / `PASS show-info-installed (exit=0)` / `PASS install-fresh (exit=0)` / `PASS install-rerun (exit=0)` / `differential (4.0.24): 4 passed, 0 failed, 0 skipped (documented deferrals)`，**EXIT 0**。
  - **2.7.2**：`BUNDLER_REF_VERSION=2.7.2 bash script/differential install-check show-info-installed install-fresh install-rerun` -> 同 4 条 PASS (exit=0) / `differential (2.7.2): 4 passed, 0 failed, 0 skipped (documented deferrals)`，**EXIT 0**。
- **文档**：`docs/differential-normalization.md` 更新“安装树比较内容（`installed-tree` marker）”小节（路径集合/内容/可执行位/symlink 目标/平台差异 + N1–N7 索引、自测与 SKIP 规则、覆盖范围来源）。`docs/compat-report.md` 按实测更新；`docs/roadmap.md` 本轮未改（L160 进展记录未变）；**M7 复选框未勾**。
- **门禁**：`crystal tool format --check src spec` **EXIT 0**；`crystal build --no-codegen src/cli.cr` **EXIT 0**（2 条既有 deprecation warning：`src\celerite\cli\commands_install.cr:594:43,658:20` `Deprecated File.executable?`）；`git diff --check` **EXIT 0**。
- **未验证/阻塞**：未重跑全量 135-fixture differential（未验证）；既有全量基线 4.0.24 133:126/7/0、2.7.2 133:126/6/1 未更新（未重跑，不得虚报）；`git-installed-discovery` 无 `installed-tree` marker（按请求“带 installed-tree 的定向 fixture”判定不适用）；stock OpenSSL `EVP_MD_size` 环境阻塞与 shim 本地 bin 未提交限制同前；bridge 不可用不视为通过；symlink (c)/(d) 依赖真实 symlink 能力，本环境可用故 PASS（若不可用须 SKIP+复现，未发生）。
- **结论**：M7(7) 子项（symlink 目标比较 + selftest + 文档 + 定向回归）按实测完成并提交/推送；M7 复选框未勾，task-2/task-3 维持 `in_progress`。

## M7(9) Rails 可行性探测（2026-11-14，未验证/阻塞）

- **目的**：判定 M7(9)「Rails 规模真实项目回归」在本环境是否可实跑；只记录实测，不伪造通过。
- **环境探测（实测）**：`gem list -i rails` → true（EXIT 0）；`gem list -i railties` → true（EXIT 0）；`bundle _4.0.24_ --version` → `Bundler version 4.0.24`（EXIT 0）；`ruby -v` → ruby 4.0.6；本机已装 rails 8.1.4.1 / 8.1.4 / 8.1.3.1 / 8.0.2。**Rails 与 Bundler 4.0.24 齐备**。
- **二进制纪律**：本节与 D2 节相同——所有 differential/上游跑批必须使用当前 HEAD 重建的 `bin/celerite.exe`（`bin/` 被 gitignore，不入库），否则结论无效。重建命令（正斜杠链接参数，反斜杠会被 sh 吃掉）：
  `crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`（BUILD=0；2 条既有 deprecation 警告 commands_install.cr:594,658）。
- **夹具**（仅本地 `C:\temp\rails-min\`，不入库）：Gemfile = `source "https://rubygems.org"` + `gem "rails", "8.0.2"`；`config/boot.rb` = `require "bundler/setup"`；`config/application.rb` = 最小 `Rails::Application`。
- **实测结果（当前 HEAD 重建二进制；每格均先控 env 变量）**：
  | 命令（目录） | 关键输出 | exit |
  |---|---|---|
  | `celerite install`（rails-min，无 bridge/TMPDIR） | 仅 `celerite internal error: Nil assertion failed`，无 Fetching 行，无 Gemfile.lock | 1 |
  | `celerite install`（rails-min，带 `CELERITE_BRIDGE_SERVER`+`TMPDIR`） | 同上 | 1 |
  | `celerite lock`（rails-min） | `Writing lockfile to C:/temp/rails-min/Gemfile.lock` + `Fetching gem metadata from https://rubygems.org/.` → `celerite internal error: SSL_connect: error:0A000086:SSL routines::certificate verify failed`；残留 Gemfile.lock 仅头一行 | 1 |
  | `celerite lock`（smoke-ssl，同二进制，无 bridge/TMPDIR） | 同上 TLS 失败（第 3 次，确定性） | 1 |
  | `celerite install`（smoke-ssl，`gem "rake","13.0.0"`，早前对照） | `Fetching/Resolving/Installing rake 13.0.0` → `Bundle complete! 1 Gemfile dependency, 1 gem now installed.`；Gemfile.lock 完整（GEM/remote/specs/PLATFORMS/DEPENDENCIES/CHECKSUMS bundler 4.0.24 + rake 13.0.0/BUNDLED WITH 4.0.24） | 0 |
  | `celerite install --help`（任意目录） | `celerite internal error: Nil assertion failed`（`--help` 疑似被当 gem 名解析；次要，记注） | 1 |
- **归因**：`CELERITE_BRIDGE_SERVER`/`TMPDIR` 已由 B1/B2 对照排除（有无该两变量结果不变）。两个**不同**的产品侧阻塞：① rails 规模 Gemfile 的 `install` 在网络活动之前即 `Nil assertion failed`（无 Fetching 行、无 lockfile）；② `lock` 命令元数据抓取确定性 `SSL_connect: ... certificate verify failed`（3/3 次），而同一夹具同一二进制 `install` 命令早前成功 ⇒ 命令路径差异，非 host TLS/CA 问题（另见 D2 节纯 Crystal HTTP::Client + OpenSSL 对照 OK 200 与 install 成功证据）。
- **结论**：M7(9) Rails 真实应用驱动**未达成**，记 **未验证**；不伪报通过。复现（本机）：
  `cd C:\temp\rails-min && celerite install`；`cd C:\temp\rails-min && celerite lock`；`cd C:\temp\smoke-ssl && celerite lock`（对照组 `cd C:\temp\smoke-ssl && celerite install`）。
- **未验证/遗留**：Nil assertion 的具体触发点（rails 规模解析 vs 平台变体）未定位；lock 命令 TLS 失败与 install 命令 TLS 成功的代码路径差异未定位；两者均需产品侧排查后才能重试 M7(9)。

## 2026-11-14 G：环境根因定位（exe 位置写/TLS 限制）+ ① 已修复落地 + ②③ 验收

背景：lead m02402 纠正 D 的 SSL 假象（陈旧二进制）后，m02561/m02782 指示修两个产品缺陷：② `ProcessLock` 在 Windows 的 `a+` 打开 EACCES；③ `lock` 路径 TLS 校验失败。本轮实测结论：**②③ 均非产品缺陷，而是本机按 exe 图像路径生效的环境限制**；①（ensure 掩盖错误）为真实产品缺陷，已由 ff66c83 修复。

### 环境限制定位（隔离实验，均可复现）

- 最小复现 `C:\Temp\lockdbg3.cr`（16 行，不含 celerite 代码）：同一二进制、同一 CWD、同一用户、同一目标文件——从 `C:\temp` 运行：`r/r+/w/a/a+` 全部 OK；从 `C:\Users\ShiningRay\projects\ShiningRay\celerite\bin\`、仓库根、`spec/`、`docs/`、`C:\Users\ShiningRay\projects\ShiningRay\` 运行：写模式全部 `File::AccessDeniedError: Error opening file with mode 'a': 'C:\Users\ShiningRay\.bundle\bundler.lock': 拒绝访问。`，读模式 `r` 仍 OK。
- 边界：exe 位于 `C:\Users\ShiningRay\projects\ShiningRay\` 子树 → 进程**写任何位置都失败**（`~/.bundle`、`C:\temp`、exe 自身目录均 EACCES）、读正常；exe 位于 `C:\Users\ShiningRay\projects\`（树根）、`Desktop`、`Downloads`、`C:\temp` → 全部写正常。
- 同分钟对照（排除陈旧/争用/内容）：`C:\temp\binloc\celerite.exe`（`Copy-Item` 同字节）→ EXIT 0 `Bundle complete!`；`bin/celerite.exe` → EACCES。03:48 用当前 HEAD 重建 `bin/celerite.exe` 仍 EACCES ⇒ 非陈旧、非内容。`ruby_procs=0`、`file_probe2.cr` 400 次 open+flock 循环 fails=0 与失败 install 并发、ACL FullControl、python/Crystal 直开均 OK ⇒ 非争用/非 ACL/非占用。
- TLS 同分钟配对（冷 compact_index 缓存，先 `Move-Item` 迁走 `~/.bundle/cache/compact_index/63ce7be7-https---rubygems.org-`）：`C:\temp\celerite-clean.exe lock`（rack 3.0.0 夹具）→ EXIT 0，`Writing lockfile to ...` + `Fetching gem metadata from https://rubygems.org/.` + `Resolving dependencies...` + lockfile 落盘；同分钟 `bin/celerite.exe lock` 同夹具 → `SSL_connect: error:0A000086:SSL routines::certificate verify failed` EXIT 1、无 lockfile。静态对比两路径 TLS 构造对称（`resolution.cr:263,267` 与 `commands_install.cr:118` 均传 `Commands.ssl_option` 三参数 + `timeout:`；`cache.cr:149-178` 与 `downloader.cr:184-211` ctx 构造一致；Crystal 1.22.1 `OpenSSL::SSL::Context::Client` 无 `add_default_paths`）。
- 结论：机器策略按图像路径（`projects\ShiningRay\` 子树）限制子进程写权限并破坏其出站 TLS 校验；机制本体未验证（无管理工具权限）。`ProcessLock` 逻辑本身健全：新增 `spec/m7_process_lock_spec.cr` 取锁/释放/再取锁往返，`1 examples, 0 failures, 0 errors, 0 pending EXIT 0`。

### ① 真实缺陷修复（ff66c83，已推送）+ 修复后真实错误浮现

- 修复：`commands_install.cr` `lock : ProcessLock? = nil` + ensure `lock.try(&.close)`；同类 `commands_surface.cr:187`（update 命令）一并修；spec `spec/m7_install_ensure_unmask_spec.cr`（畸形 Gemfile → exit 1 友好报错，不再 Nil 掩盖）。
- 修复后 rails-min 夹具（`C:\temp\rails-min`，`gem "rails", "8.0.2"`）install → EXIT 6 `(derived conflict)`：真实 gemfile 级解析冲突浮出，无崩溃、无 TLS 错误、无 EACCES（是否为产品差异需与参考 Bundler 同夹具对照——未验证）。

### ②③ 行为验收（全部用仓库外二进制，当前 HEAD 构建，正斜杠 shim 链接参数）

- 重建纪律命令：`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`（BUILD=0；反斜杠会被 sh 吃掉），随后 `Copy-Item` 到 `C:\temp\runner\celerite.exe` 执行。
- fresh21 rack 3.0.0 install → EXIT 0 `Bundle complete! 1 Gemfile dependency, 1 gem now installed.`；fresh20 rack lock（冷缓存）→ EXIT 0 lockfile 落盘；smoke-ssl rake 13.0.0 对照 → EXIT 0。

### 强制运行纪律（本宿主）

- 所有 celerite 执行（differential / upstream-specs / 人工验证）必须使用仓库外副本（如 `C:\temp\runner\celerite.exe`），**禁止原地执行 `bin/celerite.exe`**；`CELERITE_BIN` 指向副本。
- 2026-11-14 ~01:00 后原地 `bin/` 执行的证据一律无效；D2/E/F 证据产生于限制生效前，保持有效；下方 harness 复跑用于再验证。

### harness 复跑（仓库外二进制 + helper override）

- 命令：`CELERITE_BIN="C:/temp/runner/celerite.exe" CELERITE_BRIDGE_SERVER=<repo>/assets/bridge/server.rb CELERITE_SKIP_TEST_DEPS=1 CELERITE_BUNDLE_HELPER_OVERRIDE=1 RSPEC_FORMATTER_OUTPUT_ID=celerite-harness ruby -S rspec -r <repo>/script/upstream-specs-celerite-override.rb spec/lock/lockfile_spec.rb --format documentation --out C:\temp\rspec-outputG2.txt`（MSYS bash PATH 前缀，cwd `.upstream-specs/v4.0.24/bundler`）。
- 实测：`64 examples, 53 failures`（seed 31121，exit 1；Commands 行显示 `$ C:/temp/runner/celerite.exe install` ×16，runner 路径命中 46 处 ⇒ override 真实驱动 celerite）。对比 D2（旧二进制原地 `bin/`）：64/55/9 pass → 本轮 64/53/11 pass（+2）。
- 四桶归类（53，加总=53）：环境 36（DNS `Hostname lookup for gem.repoN failed` 35 + HTTP 403 1）；夹具 12（checksums.rb:24 ENOENT 10 + `gem file not found: myrack_middleware-1.0.gem` 1 + lockfile_spec.rb:1683 ArgumentError `myrack-0.9.1.gem does not exist` 1）；产品差异 5（见下）；shim/override 未覆盖 0。
- 产品差异 5 条（4 条与 D2 C1 同例同形 + 1 条新发现）：
  1. `stores relative paths when the path is provided in an absolute fashion but is relative`：期望 `remote: foo`，实得绝对路径 `remote: C:/.../bundled_app/foo`（未 relativize）。
  2. `regenerates a lockfile with no specs`：期望 direct_dependency (4.5.6) + indirect_dependency (1.2.3)，实得空 `specs:`。
  3. `refuses to install if Gemfile.lock contains conflict markers`：期望 `/your Gemfile.lock contains merge conflicts/i`，实得消息在 "Your" 与 "Gemfile.lock" 间插入绝对 Windows 路径（行为正确，exit 20）。
  4. `automatically fixes the lockfile when it has incorrect deps, keeping the locked version`：期望 net-smtp (0.5.0) 带嵌套 `net-protocol` 依赖边，实得缺该嵌套行。
  5. **新发现**（D2 被环境噪声掩盖）：`does not add the :require option to the lockfile` → `celerite internal error: Couldn't parse (String | Nil) from ["myrack/obama"] at line 1, column 250 / parsing Celerite::Bridge::EvaluatedDependency#autorequire` — bridge 对 `require:` 数组形态解析的类型缺陷（真实产品缺陷，需后续子项）。
- D2 旧桶对照：环境 39→36（SSL 32 假象消除，DNS 31+4 msg-eq 保留，403 1）；夹具 12 不变；产品 4→5（#27 由 Nil 崩溃显形为 autorequire 解析缺陷）。

### 未验证项

- 限制的机制本体与影响半径（仅本宿主实证；其他宿主未验证）。
- rails-min `(derived conflict)` 与参考 Bundler 的同夹具对照（未验证）。
- 复现：上述 lockdbg3/边界/配对实验命令见 `C:\Temp\lockdbg*.cr` 与本节命令；harness 复跑命令见上。
## 2026-11-14 H1：rails 8.0.2 伪冲突修复（`!=` 多排除的 union 截断）——本轮实测

本轮子项：H1（lead m03277/m03344/m03352 指令）——`celerite lock` 在参考实现可解的 rails 规模 Gemfile 上报 `(derived conflict)` EXIT 6，定位为约束代数缺陷并修复。

- **最小复现**：`C:\temp\rails-min\Gemfile`（52B，`source "https://rubygems.org"` + `gem "rails", "8.0.2"`；`config/boot.rb`+`config/application.rb`）。修复前：`Writing lockfile to ... / Fetching gem metadata from https://rubygems.org/. / Resolving dependencies... / (derived conflict)` EXIT 6，无 lockfile（`C:\temp\rails-min-cel2`，日志 `C:\temp\rails-cel3-lock.log` 同形态）。
- **根因（两处，均在 `src/celerite/resolver/ranges.cr` `VersionUnion`）**：`#intersects?`（原 :467-483）与 `#intersect`（原 :505-521）的区间扫描前进逻辑相同缺陷——`if my_range.max.nil? || other_range.max.nil? || other_range.max < my_range.max → 前进 other`，当一侧**无上界**（`>= 1.19.5`）时另一侧被提前耗尽，剩余区间全部丢失。效果：多 `!=` 排除构成的 union 被截断成首个区间（`>= 1.15.7, != 1.16.7, …` 坍缩为 `>= 1.15.7, < 1.16.0.rc1` 形态），随后 `nokogiri not-in union` 与 `loofah >= 2.25.3 ⇒ nokogiri >= 1.19.5` 推出虚假 `nokogiri not >= 1.19.5` 死锁 ⇒ `(derived conflict)`。Bundler 参照实现同结构（`.upstream-specs/v4.0.24/bundler/lib/bundler/vendor/pub_grub/lib/pub_grub/version_range.rb`），celerite 移植语义本正确，缺陷在扫描前进规则。
- **修复**：两条扫描循环改为「先判 my 无上界→前进 other；再判 other 无上界→前进 my；否则按上界小者前进」（`if my_range.max.nil? / elsif other_range.max.nil? / elsif other_range.max < my_range.max`），无上界侧的无限尾部不再被丢弃。`solver.cr` 新增 `CELERITE_SOLVER_DEBUG=1` 诊断出口（默认关闭；生产输出不变；`(derived conflict)` 文本不变）——失败时打印 12 层 chain（terms/cause/satisfier/decisions）+ 所有提及 chain 包的 incompatibility + root 依赖 incompatibility。
- **Spec**（`spec/m7_resolver_version_union_intersect_spec.cr`，离线索引、无网络）：`7 examples, 0 failures, 0 errors, 0 pending EXIT 0`——含纯逻辑 6 例（`>= x` ∩ `!= y` 的 union/to_s/select、10 约束 rails-html-sanitizer nokogiri 形态、排除点不存在、预发布排除、`Gem::Requirement` 枚举文本 `>= 1.15.7, != 1.16.7, != 1.16.6, != 1.16.0.rc1` + `satisfied_by?`、`Requirement#intersect` 拼接）+ 回归例（离线索引 rails-html-sanitizer 1.7.2 + loofah 2.25.3 + crass + nokogiri 6 版本，断言解出 nokogiri=1.19.7）。m7 子集回归：`36 examples, 0 failures, 0 errors, 0 pending EXIT 0`（含 version_union/resolver_ruby_constraints/ruby_constraints/download_settings/install_ensure_unmask/process_lock）。
- **验收（树外二进制 `C:\temp\runner\celerite.exe`，md5 CD53DBCCA6F51E53A82BAB8F423CB682，与当前 HEAD 重建一致；串行）**：
  - `celerite lock`（`C:\temp\rails-min-cel3`）→ **EXIT 0**，`Writing lockfile to ... / Fetching gem metadata from https://rubygems.org/. / Resolving dependencies...`，Gemfile.lock 生成（日志 `C:\temp\rails-cel3-lock.log`）。
  - 与参照 `bundle _4.0.24_ lock`（`C:\temp\rails-min-ref3`，EXIT 0，265 行/64 specs，`BUNDLED WITH 4.0.24`，日志 `C:\temp\rails-ref3-lock.log`）结构化比对（脚本 `C:\Temp\compare_locks.py`）：**DEPENDENCIES / PLATFORMS / BUNDLED WITH 三段逐字节一致**；GEM specs name+version 集合 61/64 完全一致，差异逐项：① `nokogiri`：ref `1.19.7-x64-mingw-ucrt`（dep 仅 racc ~> 1.4）vs cel `1.19.7`（ruby 平台，deps mini_portile2 ~> 2.8.2 + racc ~> 1.4）——平台变体选择差异（产品 gap，见下）；② `prism`：ref `2.1.0-x64-mingw-ucrt` vs cel `2.1.0`——同类；③ `bundler 4.0.24`：cel 作为普通 spec 列入（rails dep `bundler >= 1.15.0`），ref 不列（Bundler 自身除外，仅 BUNDLED WITH）。各 spec 的依赖列表与所选平台变体自洽（除上述平台对，无其他 dep 差异）。
  - `celerite install`（同夹具 fresh copy `rails-min-cel4`）→ 进入安装阶段：Fetching/Resolving 后逐 gem 安装，`bigdecimal-4.1.3` 原生扩展构建失败 `make failed ... No such file or directory - make`（本机无 make，且 ruby 平台变体需源码编译）EXIT 1，日志 `C:\temp\rails-cel4-install.log`——达到安装阶段（验收口径），真实安装受平台选择 gap + 环境缺 make 双重阻塞，标**未验证**。
  - rake 对照（`C:\temp\smoke-ssl`）：`celerite install` → **EXIT 0** `Bundle complete! 1 Gemfile dependency, 1 gem now installed.`
- **产品 gap（如实登记，本轮不修）**：lock 路径选择 ruby 平台 spec 而非当前平台变体（`x64-mingw-ucrt`）——参照实现选平台变体；功能影响即上条 install 原生构建失败。候选根因（未定位到行）：compact index 元数据未把平台变体纳入候选，或平台过滤过严；`CandidateVersion` 优先级模型已含 platform=+1/ruby=-1，说明变体未进入候选集。列 M7 后续项。
- **差分回归（方向性，树外二进制，串行）**：`CELERITE_BIN=C:\temp\runner\celerite.exe` + `CELERITE_BRIDGE_SERVER=.../assets/bridge/server.rb` + `TMPDIR=C:\temp`，MSYS bash；12 个分辨率/lock 相关夹具 `install-check install-fresh lock-bundler lock-file-pin lock-normalize lock-print list-missing no-matching-version platform-variant-fail multi-platform-lock ruby-metadata-boundary-match rubygems-metadata-boundary-match`：
  - 4.0.24：`12 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0（日志 `C:\temp\h-diff-4024.log`；含 `platform-variant-fail` 金丝雀）。
  - 2.7.2：同 12 夹具集（`BUNDLER_REF_VERSION=2.7.2`）→ `12 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0（日志 `C:\temp\h-diff-272.log`）——无新增回归。
- **未验证/阻塞**：rails-min 真实安装完成（make 缺失 + 平台 gap）；lockfile 文本级 diff（spec 排序：Bundler 字母序 vs celerite 求解序，顺序差异为预期，differential 归一化处理）；`.A` 哨兵文本（`< 3.A` 仅出现在 CELERITE_SOLVER_DEBUG 调试输出，非 lockfile/归一化文本；`VersionRange#to_s` 枚举形态已由 spec 例 5 断言与参照一致）——记录观察，不改语义。
- **复现**：`cd C:\temp\rails-min-ref3 && bundle _4.0.24_ lock`（参照）；`cd C:\temp\rails-min-cel3 && CELERITE_BRIDGE_SERVER=... TMPDIR=C:\temp C:\temp\runner\celerite.exe lock`（修复后）；修复前形态见 `C:\temp\rails-min-h1.log`/`C:\temp\rails-re.txt`（`(derived conflict)` EXIT 6）。重建纪律：`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`（正斜杠）后复制到树外再跑；仓库树内 exe 受环境写策略影响（证据见 G 节），树内运行结论无效。
## 2026-11-14 #27：bridge autorequire 数组形态解析修复——本轮实测

- 本轮子项（lead m03644 第 1 项）：上游例 `the lockfile format does not add the :require option to the lockfile`（`.upstream-specs/v4.0.24/bundler/spec/lock/lockfile_spec.rb:1022`，`gem "myrack-obama", ">= 1.0", :require => "myrack/obama"`）在真实驱动中崩溃于 `celerite internal error: Couldn't parse (String | Nil) from ["myrack/obama"] at line 1, column 250 / parsing Celerite::Bridge::EvaluatedDependency#autorequire`（先前证据：G2 运行产品桶第 5 条，见本节上方 D2 对照段；本轮未重跑全量）。
- **根因**：`assets/bridge/server.rb:89` 把 `dep.autorequire` 原样序列化；Bundler 2.2/2.7/4.0 的 `Dependency#autorequire` 均为 `Array(options["require"] || [])`（有 `:require` 时恒为数组，缺省为 nil；实测 `.upstream-specs/v4.0.24/bundler/lib/bundler/dependency.rb:87-90`，本机 bundler 2.2.32/2.7.2/4.0.24 三代一致），而 `src/celerite/bridge/client.cr:42` 声明 `getter autorequire : String?` → 数组形态触发 JSON::Serializable 解析崩溃。
- **修复**：类型放宽为 `Array(String) | Nil`（client.cr:42-46，附形态注释）。无下游消费者（grep 全仓仅 client.cr 引用该字段），无文本面影响。
- **离线 spec**（`spec/m7_bridge_autorequire_spec.cr`，无网络）：`6 examples, 0 failures, 0 errors, 0 pending EXIT 0`——数组/多元素/空数组/null/整包形状/标量字符串拒绝 6 例。
- **桥接实测**（真实 `server.rb`，JSON-Lines 协议）：Gemfile 含 `:require => "myrack/obama"` → `"autorequire":["myrack/obama"]`；不含 → `"autorequire":null`（原始 JSON 见 `C:\temp\h27-bridge-a.json`/`-b.json`）。
- **上游例修复前后**：修复前 = 上述解析崩溃（产品缺陷）；修复后（树外二进制重跑同例，日志 `C:\temp\h27-single.txt`）= 不再崩溃，推进到 install 阶段后失败于 `celerite internal error: Hostname lookup for gem.repo2 failed: No address found / Fetching gem metadata from https://gem.repo2/.`——与 G2 35 例同属环境 DNS 桶（上游夹具的进程内 remote stub 对 celerite 子进程不可达），**该上游例本轮仍标未验证（环境阻塞，非产品）**。
- **命令**：`crystal spec spec/m7_bridge_autorequire_spec.cr`（EXIT 0）；桥接冒烟 `echo '{"proto":1,"id":1,"op":"evaluate_gemfile","payload":{"gemfile":"C:/temp/h27-gemfile-a"}}' | ruby assets/bridge/server.rb`；上游单例 `cd .upstream-specs/v4.0.24/bundler && CELERITE_BIN=C:/temp/runner/celerite.exe CELERITE_BRIDGE_SERVER=<repo>/assets/bridge/server.rb BUNDLE_GEMFILE= RSPEC_FORMATTER_OUTPUT_ID=celerite-harness ruby -S rspec -r <repo>/script/upstream-specs-celerite-override.rb spec/lock/lockfile_spec.rb -e "does not add the :require option to the lockfile"`（`1 example, 1 failure`，EXIT 1，失败体为 DNS 环境类）。
- **重建纪律**：`crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`（BUILD_EXIT=0）后 `Copy-Item` 到 `C:\temp\runner\celerite.exe`（--version 0.1.0）；禁止原地执行 `bin/`。
## 2026-11-14 M7(7) acceptance：差分脚本健壮性——本轮实测（roadmap L160 四要求逐条映射）

- **要求 1「列出所有归一化规则」** → `docs/differential-normalization.md:9-17` N1–N7 权威表（沙箱路径双拼写/CRLF/时间戳/日期/Environment 体/backtrace 帧/连续 Fetching 行排序）；`script/differential:14-24` 头部同 ID 镜像；新增规则须先改本文档再改脚本并双 profile 重跑（doc:5-7）。
- **要求 2「不排序语义输出、明确列表排序」** → 仅 N7 排序连续 `Fetching ` 行（doc:17）；`script/differential:24`「Exit codes, all other line ordering, trees and file contents must match」；doc:21-22 退出码精确、其余行序精确；N5/N6 是仅有两处删减且 doc:61-62 登记复核触发条件。
- **要求 3「installed-tree 比较（路径、内容、可执行位、symlink）」** → `script/differential-installed-tree` `compare_installed_tree`（:23 起）：匹配目录集合（doc:42-43）、symlink 目标自行 `find . -type l`+`readlink` 比较（:55-74，不依赖 `diff -r --no-dereference` 版本差异；目标不一致 `symlink target differs`）、类型（:78/:84 `entry type differs`）、相对路径集合（:94，缺失/多余失败）、内容 N1–N7 归一化后一致（:115）、可执行位（:124，仅非 Windows，git 不保留该位 doc:47）；5 类判定 doc:53。**本轮实测**：`bash script/differential-installed-tree-selftest` → `6 passed, 0 failed, 0 skipped` EXIT 0（本机真 symlink 可用，6 断言全跑，非 SKIP）；marker 夹具 `ls fixtures/differential/*/installed-tree` = 21 个；带 installed-tree 的定向夹具双 profile 回归 = H1 轮 12 fixture 集（install-check/install-fresh 等）4.0.24 与 2.7.2 均 `12 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0（`C:\temp\h-diff-4024.log`/`C:\temp\h-diff-272.log`）。
- **要求 4「lockfile 和 Gemfile 直接比较内容」** → `first-line` 探针（`script/differential:267-277`，字节精确首行）+ `file-contains` 探针（:278-290，双侧字节精确 needle，`@INDEX_DIR@/@SCOPED_INDEX_DIR@/@BUNDLER_VERSION@` 占位符替换后）：Gemfile 内容探针 9 个 add-* 夹具 + Gemfile.lock 内容探针 scoped-source-lock（`remote: file://...` 行）+ binstubs-shebang-line 首行探针（bin/thor）；`lock --print` 类夹具（lock-print/lock-normalize）经 :241-246 stdout 归一化逐字节比对覆盖 lockfile 文本。**本轮实测**：11 个内容探针夹具双 profile 各 `9 passed, 2 failed, 0 skipped` EXIT 1（`C:\temp\h-m77-4024.log`/`C:\temp\h-m77-272.log`）；2 失败 = add-optimistic/add-version 的 racc-1.8.1 原生扩展构建（`make failedNo such file or directory - make`，ref=0/cel=1）——环境（本机无 make）叠加 H1 已登记平台变体选择 gap（celerite 选 ruby 平台 gem → 需源码构建），探针未到达，非内容比较缺陷；9 通过含 Gemfile.lock 探针与首行探针，内容直接比对机制本身成立。
- **覆盖边界**：N1 双沙箱路径拼写；N2 CRLF；N3/N4 时间戳/日期；N5 仅 Environment 体；N6 仅 backtrace 帧；N7 仅连续 Fetching 行；探针字节精确；树比较按设计仅路径（生成文件含每沙箱绝对路径，:247-255 注释）；可执行位仅非 Windows；Windows symlink selftest 以 `MSYS=winsymlinks:nativestrict` 探测真链、无法创建记 SKIP+复现命令（doc:51，不伪报 PASS）——本机真链可用。
- **结论**：四要求证据齐备 → `docs/roadmap.md:160` M7(7) 复选框本轮勾选（仅此项），注记验收提交与本节证据。整文件 diff 不可行（参照引擎写入绝对沙箱路径）由 N1 + 路径级树比较 + 探针组合替代（doc:23-26），无未覆盖项；2 个 add-* 失败归环境+平台 gap（见上），不影响本验收项。
## 2026-11-14 #27 补充：修复后定向差分回归（双 profile，本轮实测）

- #27 修复（`93e7df9`）后，用同一树外二进制（`C:\temp\runner\celerite.exe`，含 client.cr 类型放宽）对 H1 轮 12 fixture 定向集重跑双 profile：4.0.24 `12 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0（`C:\temp\h-post27-4024.log`）；2.7.2（`BUNDLER_REF_VERSION=2.7.2`）同 `12 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0（`C:\temp\h-post27-272.log`）。集合含 `platform-variant-fail` canary 与 `ruby-metadata-boundary-match`/`rubygems-metadata-boundary-match` 两个 metadata 边界夹具，无新回归。
- 命令（MSYS bash PATH 前缀，cwd 仓库根，串行）：`CELERITE_BIN=C:/temp/runner/celerite.exe CELERITE_BRIDGE_SERVER=<repo>/assets/bridge/server.rb TMPDIR=/c/temp bash script/differential install-check install-fresh lock-bundler lock-file-pin lock-normalize lock-print list-missing no-matching-version platform-variant-fail multi-platform-lock ruby-metadata-boundary-match rubygems-metadata-boundary-match`（2.7.2 加 `BUNDLER_REF_VERSION=2.7.2`）。


## 2026-11-14 K：平台变体选择修复（本地平台精确匹配 > ruby）——本轮实测

缺陷：rails-min（`source "https://rubygems.org"` + `gem "rails", "8.0.2"`）`celerite lock` 写入 `nokogiri (1.19.7)` / `prism (2.1.0)` 的 ruby 变体，参照 Bundler 4.0.24 写入 `nokogiri (1.19.7-x64-mingw-ucrt)` / `prism (2.1.0-x64-mingw-ucrt)`；后果是 install 走源码构建（bigdecimal 原生扩展，本机缺 make 失败），命中 M7(1)/(2) 平台变体要求。

参照语义（K1，.upstream-specs/v4.0.24/bundler）：resolver.rb:257-303 all_versions_for 每版本构造 ruby 候选（priority -1）+ 平台候选（priority 1）；物化时 MatchPlatform.select_best_platform_match（match_platform.rb:12-16）按 platform.rb:326-348 sort_and_filter_best_platform_match 取精确平台（specificity -1）> ruby（1_000_000）> 其它；lockfile_generator.rb:44-51 按 full_name 排序写 specs，PLATFORMS 来自 definition.platforms（definition.rb:850-858）。

celerite 缺陷定位（K1）：求解侧正确（resolver/source.cr:217-238 候选 priority ±1；ranges.cr CandidateVersion <=> 先版本后 priority）；**缺陷在 src/celerite/resolution.cr:735-736 decisions_to_specs 硬编码 `s.platform_ruby?` 查找**，丢弃已选平台变体（写 ruby 形式 + ruby 依赖 mini_portile2）。

修复（K2）：
- src/celerite/resolver/source.cr：新增 `select_variant`（同版本候选中 gate `platform_ruby? || platform == Gem::Platform.local`，按 `Gem::Platform.platform_specificity_match` 取 min，ruby 兜底）；
- src/celerite/resolution.cr：新增 `platform_mergeable?`（平台变体依赖集 == ruby 依赖集时 ruby 候选组已含两者，参照 SpecGroup#merge/equivalent? 语义，覆盖 prism 类 deps-equal 情形）；decisions_to_specs 按 `candidate_version.priority == 1 || platform_mergeable?(same_version)` 走 select_variant(index) → select_variant(locked_index) → ruby 查找链；ResolvedSpec platform 参数由硬编码 nil 改为 `spec.platform_ruby? ? nil : spec.platform.to_s`（驱动 PLATFORMS writer :954-958、checksum 后缀、install full_name）。

验收（本轮实测）：
- 离线 spec `spec/m7_platform_variant_selection_spec.cr`：5 examples, 0 failures, 0 errors, 0 pending, EXIT 0（本地变体优先 / ruby 回退 / priority 语义）。
- 树外副本 C:\temp\rails-min-cel9 `celerite lock` EXIT 0：`nokogiri (1.19.7-x64-mingw-ucrt)`、`prism (2.1.0-x64-mingw-ucrt)`、无 mini_portile2、PLATFORMS `x64-mingw-ucrt` 与参照一致；结构化比对（C:\Temp\compare_sections.py，对照 C:\temp\rails-min-ref4 `bundle _4.0.24_ lock` EXIT 0、265 行/64 specs）：DEPENDENCIES/PLATFORMS/BUNDLED WITH 全等；GEM 65 vs 64，cel 多出仅 `bundler (4.0.24)` 自引用（已知差异）；nokogiri/prism 变体与参照逐行一致。
- install 验收（C:\temp\rails-min-cel9，树外 exe）：日志 `Installing nokogiri 1.19.7` / `Installing prism 2.1.0` **无 "with native extensions"**（预编译平台变体命中）；后续 `bigdecimal 4.1.3 with native extensions` 失败 + bridge 30s 超时 = 环境（缺 make）与桥接超时，与本 gap 无关；EXIT 1。
- 定向差分双 profile（platform-variant-fail / multi-platform-install / multi-platform-install-ruby / multi-platform-lock / install-check / no-matching-version）：4.0.24 与 2.7.2 均 `6 passed, 0 failed, 0 skipped` EXIT 0（C:\temp\h-k-diff-4024.log / h-k-diff-272.log；platform-variant-fail 金丝雀未改期望仍 PASS）。
- 门禁三件套 EXIT 0（format --check / build --no-codegen / git diff --check）。

新发现（本轮登记，未在本提交修）：真实远端 lockfile CHECKSUMS 段 sha256 系统性错误——src/celerite/resolution.cr:47-49 `info_checksum_value` 对 rubygems.org /info 的**原始 hex** checksum 无条件 `Base64.decode(...).hexstring`（96 hex 位）；实测 `b64decode(参照值) == celerite 值` 为真（actioncable 8.0.2 参照 7bcce2df… → cel edb71c7b…），live /info 与参照一致；downloader.cr:129-137 normalize_checksum 已正确处理 hex/base64/sha256= 三种形态但 lockfile 路径未复用。列为 K' 独立子项。

未验证：修复后二进制重跑上游全量 64 例（L 步）；rails-min install 端到端（缺 make）。
复现：`CELERITE_BIN="C:/temp/runner/celerite.exe" TMPDIR=/c/temp bash script/differential platform-variant-fail multi-platform-install multi-platform-install-ruby multi-platform-lock install-check no-matching-version`；参照 `bundle _4.0.24_ lock`（C:\temp\rails-min-ref4）；比对 `python C:\Temp\compare_sections.py`。

## 2026-11-14 K/K'/K''：平台变体 + checksum 归一化 + bundler 自列入修复——本轮实测

三项修复（各独立 commit，均已推送；调查细节见上 K 节），按首辅 D1 要求合并记录证据如下。

### K：平台变体选择修复（本地平台精确匹配 > ruby）
- 缺陷位置（修复前）：`src/celerite/resolution.cr:735-736` `decisions_to_specs` 硬编码 `platform_ruby?` 查找，丢弃已选本地平台变体 → `rails-min` lock 写 `nokogiri (1.19.7)` ruby 形态 + ruby 依赖 `mini_portile2`，参照写 `nokogiri (1.19.7-x64-mingw-ucrt)`。
- 修复：`src/celerite/resolver/source.cr` 新增 `select_variant`（gate `platform_ruby? || platform == Gem::Platform.local`，按 `Gem::Platform.platform_specificity_match` 取 min，ruby 兜底）+ `src/celerite/resolution.cr` `platform_mergeable?`（平台变体依赖集 == ruby 依赖集时 ruby 候选组已含两者，参照 `SpecGroup#merge`/`equivalent?` 语义，覆盖 prism 类 deps-equal 形态）；`decisions_to_specs` 按 `candidate_version.priority == 1 || platform_mergeable?(same_version)` 走 `select_variant(index)` → `select_variant(locked_index)` → ruby 查找链；`ResolvedSpec` platform 参数由硬编码 `nil` 改为 `spec.platform_ruby? ? nil : spec.platform.to_s`（驱动 PLATFORMS writer :954-958 + checksum 后缀 + install full_name）。
- 证据：离线 spec `spec/m7_platform_variant_selection_spec.cr` `5 examples, 0 failures, 0 errors, 0 pending EXIT 0`；树外 `rails-min-cel9` `celerite lock` EXIT 0 → `nokogiri (1.19.7-x64-mingw-ucrt)` / `prism (2.1.0-x64-mingw-ucrt)` 与参照 `rails-min-ref4` 一致、无 `mini_portile2`、`PLATFORMS x64-mingw-ucrt` 全等；定向差分双 profile 6 夹具（含 `platform-variant-fail` 金丝雀，未改期望）`6 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0（`C:\temp\h-k-diff-4024.log` / `h-k-diff-272.log`）；install 对 nokogiri/prism 不再触发源码构建（`Installing nokogiri 1.19.7` / `Installing prism 2.1.0`，无 `with native extensions`），`bigdecimal 4.1.3 with native extensions` 仍因本机缺 make 失败（环境，与本修复无关，`C:\temp\rails-cel9-install.log`）。

### K'：checksum 归一化
- 缺陷位置（修复前）：`src/celerite/resolution.cr:47-49` `info_checksum_value` 对 rubygems.org /info 的原始 hex checksum 无条件 `Base64.decode(raw).hexstring` → 64-hex 系统性错位。
- 修复：抽 `src/celerite/checksum.cr` `Celerite::Checksum.normalize_hex`（64-hex / base64 std+url-safe padded/unpadded / `sha256=` 前缀 → 裸小写 64-hex，非法 → nil）单一事实源；`resolution.cr` `info_checksum_value` 改用它（nil 抛 `ArgumentError`）；`downloader.cr:129-137` `normalize_checksum` 同步复用。
- 证据：`spec/m7_checksum_normalize_spec.cr` + `spec/m7_info_checksum_value_spec.cr` 合计 `13 examples, 0 failures, 0 errors, 0 pending EXIT 0`（与 platform-variant 5 例合跑 18/0/0）；`rails-min-cel12` 与参照 `rails-min-ref4` CHECKSUMS `bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc` 逐字节相同；全部 CHECKSUMS 65 vs 65 行 multiset diff = 0。

### K''：bundler 自列入 / CHECKSUMS 重复
- 缺陷位置：`src/celerite/resolution.cr` lockfile 渲染循环遍历 `@resolved_specs` 含 bundler → GEM specs 列 `bundler (4.0.24)` 且 CHECKSUMS 发一条；随后 self-verify 块再发一条 → 重复。
- 修复：specs 渲染与 CHECKSUMS 循环均跳过 bundler；self-verify 块为唯一写出点；按 (name, version, platform) 去重兜底。
- 证据（修复前后计数对照，4-space `bundler (4.0.24)` = GEM specs 自列入，2-space `bundler (` = CHECKSUMS 行）：
  - 修复前 `rails-min-cel10`：GEM specs bundler **1**（参照 0）/ CHECKSUMS bundler **2**（参照 1）/ 总 bundler 行 4。
  - 修复后 `rails-min-cel12`：GEM specs bundler **0** / CHECKSUMS bundler **1** / 总 bundler 行 2（与参照 `rails-min-ref4` 完全一致）；CHECKSUMS 段 multiset diff 0（65 vs 65）。

### 未验证/边界
- `celerite install` 端到端仍受本机缺 `make` 阻塞（`bigdecimal` 原生构建），M7(9) 未达成；
- 上游 64 例未在修复后重跑（L 即将进行）；
- 树外 exe 纪律与复现命令同 K 节（`C:\temp\runner\celerite.exe`；重建 `crystal build src/cli.cr -o bin/celerite.exe --link-flags "C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o"`，正斜杠，shim 仅本地不入库）。

## 2026-11-14 rerun after K/K'/K'' fixes

命令（trace 直跑，树外 exe，串行）：

```
cd .upstream-specs/v4.0.24/bundler
CELERITE_BIN="C:/Ruby40-x64/bin/ruby.exe C:/temp/runner/trace-celerite.rb" \
CELERITE_BRIDGE_SERVER="C:/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb" \
CELERITE_SKIP_TEST_DEPS=1 RSPEC_FORMATTER_OUTPUT_ID=celerite-harness BUNDLE_GEMFILE= \
ruby -S rspec -r "C:/Users/ShiningRay/projects/ShiningRay/celerite/script/upstream-specs-celerite-override.rb" \
  spec/lock/lockfile_spec.rb --format documentation --out C:\temp\rspec-outputL.txt
```

前置：先 `ruby -I spec/support C:/temp/populate_pristine.rb` 重建 pristine_system（setup 链在 RSPEC_FORMATTER_OUTPUT_ID 设置时跳过自装）；二进制为 K/K'/K'' 后重建副本 `C:\temp\runner\celerite.exe`（`--version` 0.1.0）。

实测：`64 examples, 53 failures`（11 通过），seed 27921，`Finished in 3 minutes 37 seconds (files took 1.42 seconds to load)`，celerite 调用 57 次（install 51 / config 3 / lock 2 / cache 1），rspec exit 1。日志 `C:\temp\rspec-outputL.txt`。

四桶重判（加总 = 53 = 新失败数）：

- 环境 37：DNS 36（日志主机名出现合计 44 次：gem.repo1×3、gem.repo2×29、gem.repo4×11、othergemserver.test×1，部分例输出中主机名出现多次；artifice 桩仅进程内有效，子进程 celerite 不可达）+ HTTP 403 ×1；本轮无 SSL / make / sinatra 类失败。
- 夹具 12：`checksums.rb:24` ENOENT `remote2/gems/*.gem`、`install_gem` does-not-exist、`lockfile_spec.rb:1683` ArgumentError 等上游夹具本身缺口。
- 产品 4（较 G2 轮 5 减 1）：#27 `does not add the :require option to the lockfile` 已由 `93e7df9` 修复——本轮不再出现 `Couldn't parse (String | Nil)`，该例转为 env-DNS（gem.repo2）失败；剩余 4 项为既有内容差异：绝对路径未 relativize（`stores relative paths when the path is provided in an absolute fashion but is relative`）、空 specs（`regenerates a lockfile with no specs`）、嵌套 net-protocol 边缺失（`automatically fixes the lockfile when it has incorrect deps, keeping the locked version`）、冲突标记信息含绝对 Windows 路径破坏 `/Your Gemfile.lock contains merge conflicts/i` 正则（`refuses to install if Gemfile.lock contains conflict markers`，exit 20 正确）。
- shim 0。

lead 编号 #30/#33/#44/#12 与上述 4 项产品差异的逐项映射未在 docs 中找到对应记录，按名称列出，请 lead 对照（未验证）。

G2 对照（同条件前轮，`C:\temp\rspec-outputG2.txt`：64/53，seed 31121）：line-ending 5 例与 `without credentials` 例在 G2 即以同型 DNS 失败，本轮无新增回归；唯一成员变化为 #27 产品→环境。

make 新条件（lead m04964）：`make.exe` 实存于 `C:\Ruby40-x64\msys64\usr\bin` 但既往不在 PATH；本轮上游 64 例中 0 例达原生构建阶段（DNS/403 先失败），故 make 入 PATH 不改变本轮计数；A 类 differential 与 M7(9) Rails install 的 make 重跑在 N 子项单独记录。

未验证/边界：本结果仅针对 `spec/lock/lockfile_spec.rb` 单文件；2.7.2 profile 因布局不兼容未重跑；install 成功例的端到端锁定内容以 env 桩为准。

## 2026-11-14 N1：native-ext “缺 make”更正为 harness PATH 未配置 + PATH 归一化（本轮实测）

**更正（追加，不删历史）**：此前记录把 native-ext 失败归因为“本机缺 make / racc 原生构建缺 make”。实测 `C:\Ruby40-x64\msys64\usr\bin\make.exe` 存在（GNU Make 4.4.1）、`gcc` 存在；真实原因是 harness PATH 未含 `C:\Ruby40-x64\msys64\usr\bin`，且独立 msys64 的 gcc（Rev6 16.2.0）与 Ruby 自带工具链的 gcc（Rev5 16.1.0）版本不一致，导致两侧各自编译的 `racc-1.8.1/lib/racc/cparse.so` 字节不同。归属：环境（PATH 排序 → 不同编译器 → 不同产物），非产品缺陷。

### 根因（post-mortem，sandbox `C:\temp\tmp.6PaKvxdzRf`，`KEEP_DIFFERENTIAL=1`）
- 参照侧 cparse.so：24576 B，sha256 `973701316BDA3124B57DC394CE86AB375DA4370A90C6E5E538AC42E868E9180F`；celerite 侧：20992 B，sha256 `DD4F105F24C2551CCF27330B0899A9A2DB3DD1DB205902AE7236A803AAE06244`（ materially different，非嵌入路径问题）。
- `.comment` 段：参照 `GCC: (Rev5, Built by MSYS2 project) 16.1.0`（`C:\Ruby40-x64\msys64\ucrt64\bin\gcc.exe`），celerite `GCC: (Rev6, Built by MSYS2 project) 16.2.0`（`C:\msys64\ucrt64\bin\gcc.exe`）；objdump：MinorLinkerVersion 46 vs 47、SizeOfCode 0x3400 vs 0x2e00、SizeOfImage 0xe000 vs 0xc000。
- 两侧 Makefile 路径归一后字节一致（`CC = gcc`，同 CFLAGS/ARCH_FLAG）；参照 `gem_make.out` 为 `make -j3`（Bundler jobs），celerite 为 `make`。
- 修复验证：PATH 以 `C:\Ruby40-x64\msys64\ucrt64\bin` 前缀后，native-ext PASS（exit=0）；新 sandbox `C:\temp\tmp.L8atVS93vQ` 两侧 cparse.so 均 24576 B、sha256 `973701316BDA…`，identical=True。

### 修复（`script/differential`，+24 行，未改产品代码）
- 头部注释新增 N8 说明：native-ext 夹具需要 C 编译器在 PATH；make.exe 本已存在，此前“缺 make”为误判。
- 新增 `CELERITE_DIFF_EXTRA_PATH` 支持；PATH 归一化循环在 `C:\Ruby40-x64\msys64\ucrt64\bin`、`C:\Ruby40-x64\msys64\usr\bin` 存在时前置，然后 `export PATH`。`bash -n script/differential` EXIT 0。

### 本轮实测（A 类 7 例双 profile，树外 exe `C:\temp\runner\celerite.exe`，`CELERITE_BRIDGE_SERVER` 已设）
- 4.0.24：`differential (4.0.24): 7 passed, 0 failed, 0 skipped (documented deferrals)` EXIT 0 —— native-ext / native-ext-target / add-group / add-optimistic / add-remove / add-version / cache-all-platforms 全 PASS。日志 `C:\temp\n-a1-4024.log`。
- 2.7.2：`differential (2.7.2): 6 passed, 0 failed, 1 skipped (documented deferrals)` EXIT 0 —— add-group 为已登记 deferred skip。日志 `C:\temp\n-a1-272.log`。
- 修复前对照：4.0.24 `6 passed, 1 failed, 0 skipped`（`C:\temp\n-a-4024.log`）、2.7.2 `5 passed, 1 failed, 1 skipped`（`C:\temp\n-a-272.log`），失败均为 native-ext `cparse.so content differs after normalization`。
- 全量 4.0.24 differential（PATH 归一化后）：`135 passed, 0 failed, 1 skipped (documented deferrals)` EXIT 0（基线 133:126/7/0 → 失败 7→0；总数 +3 为新夹具，其中 git-submodules 为登记 skip）。证据：N1 轮后以同一 PATH 归一化脚本（追加 N9 规则后）复跑全量 4.0.24 并 tee 至 `C:\temp\n2-full-4024.log`（10,212 字节，mtime 2026-11-14T21:19:25.9375434+08:00），尾部 `differential (4.0.24): 135 passed, 0 failed, 1 skipped (documented deferrals)` （N1 流式轮与 N2 tee 轮计数一致）；后续重跑统一 tee 到固定路径 `C:\temp\diff-full-4.0.24-<sha>.log`。

### Rails e2e（cel13）尝试与归属（记录，非本轮验收项）
- cel13（真实 HOME）：`Installing bigdecimal 4.1.3 with native extensions` → `extension build failed for bigdecimal-4.1.3: File exists @ dir_s_mkdir - C:\Users\ShiningRay\.bundle\ruby\4.0.0\extensions\x64-mingw-ucrt\4.0.0\bigdecimal-4.1.3`（EEXIST；早前 cel4 残留目录未清理）。归属：环境残留 + 安装目录创建幂等性缺陷 → 转 N3 缺陷 1 处理。
- cel13b（隔离 GEM_HOME）：`Could not find 'bundler' (= 4.0.24) - did find: [bundler-4.0.16]`（我方 setup 错误：隔离 GEM_HOME 缺 reference bundler，非产品）。
- cel13c（隔离 HOME+BUNDLE_PATH）：`Fetching gem metadata from https://rubygems.org/.` → `celerite internal error: WSARecv timed out`（网络/TLS 抖动；bundle 目录仅 bundler.lock）。归属：环境。
- 结论：Rails install 端到端未验证（环境阻塞），复现命令见下。

### 未验证 / 边界
- **构建 PATH 坑（2026-11-14 补记）**：构建 CLI（`crystal build src/cli.cr -o bin/celerite.exe --link-flags <shim.o>`）必须用**原始 PATH**（Git/msys64/Ruby 顺序），不要用被 N8 归一化过的 PATH——把 `C:\Ruby40-x64\msys64\ucrt64\bin` 前置后 `cc`（Ruby 自带 Rev5）报 `cc: fatal error: '-fuse-linker-plugin', but liblto_plugin.dll not found`（插件在 `C:\Ruby40-x64\msys64\ucrt64\lib\gcc\x86_64-w64-mingw32\16.1.0\liblto_plugin.dll`，但 cc 运行库解析失败）；换回原始 PATH 后构建 EXIT 0。该现象是工具链解析问题，不是产品代码问题，`script/differential` 头部 N8 注记已同步说明。
- M7(9) install 端到端仍未验证（make/编译已通，bigdecimal EEXIST + TLS 抖动阻塞）。
- 全量 135/0/1 的文件日志缺失（流式输出），计数来自作业输出尾部。

### 复现命令
```
# A 类双 profile（树外 exe）
CELERITE_BIN="C:/temp/runner/celerite.exe" TMPDIR="C:\temp" CELERITE_BRIDGE_SERVER="C:/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb" bash script/differential native-ext native-ext-target add-group add-optimistic add-remove add-version cache-all-platforms
BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="C:/temp/runner/celerite.exe" TMPDIR="C:\temp" CELERITE_BRIDGE_SERVER="C:/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb" bash script/differential native-ext native-ext-target add-group add-optimistic add-remove add-version cache-all-platforms
# 全量 4.0.24
CELERITE_BIN="C:/temp/runner/celerite.exe" TMPDIR="C:\temp" CELERITE_BRIDGE_SERVER="C:/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb" bash script/differential
# Rails e2e（环境阻塞，复现用）
Copy-Item -Recurse C:\temp\rails-min C:\temp\rails-min-cel13; Remove-Item C:\temp\rails-min-cel13\Gemfile.lock -ErrorAction SilentlyContinue
CELERITE_BIN="C:/temp/runner/celerite.exe" TMPDIR="C:\temp" CELERITE_BRIDGE_SERVER="C:/Users/ShiningRay/projects/ShiningRay/celerite/assets/bridge/server.rb" & C:\temp\runner\celerite.exe install
```

## 2026-11-15 M7(4) 子项：`mirror.<url>.fallback_timeout` 真实生效——本轮实测

### 参考语义（权威来源：`C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\lib\bundler\mirror.rb`）

- `Mirror#initialize(uri = nil, fallback_timeout = 0)`（L67）：**默认 fallback_timeout 为整数 0**，故未配置时 `validate!` 短路不探测。
- `Mirror#fallback_timeout=`（L82-92）：`true`/"true" → `DEFAULT_FALLBACK_TIMEOUT = 0.1`（L63）；`false`/"false" → 0；其他 → `timeout.to_i`（**整数截断**：`"2.5"`→2、`"0.5"`→0；`"abc".to_i`→0）。
- `Mirror#validate!`（L104-110）：`@valid = fallback_timeout == 0 || (probe || TCPSocketProbe.new).replies?(self)`。
- `TCPSocketProbe#replies?`（L148-176）+ `MirrorSockets`（L185-202）：遍历 host 的全部解析地址做非阻塞 connect，带 `fallback_timeout` 的 `IO.select` 等待可写，`SO_ERROR == 0` 才算可达。
- `Mirrors#for`（L22-28）与 `fetch_valid_mirror_for`（L48-54）：mirror 无效（探测失败）时回退到 `Mirror.new(uri)`，即使用原 remote。

### 实现（本次改动 6 个文件）

- 新增 `src/celerite/mirror.cr`（53 行，`Celerite::Mirror`）：
  - `DEFAULT_FALLBACK_TIMEOUT = 0.1`（L15）
  - `fallback_timeout_seconds(value : Config::ConvertedValue) : Float64?`（L21-23，委托 `Config.fallback_timeout_seconds`，避免 config.cr 反向依赖）
  - `reachable?(url : String, timeout : Float64) : Bool`（L28-39）：`timeout <= 0` 直接 true（对齐 0 短路）；否则 `TCPSocket.new(host, port, connect_timeout: timeout.seconds)`，`rescue` → false；port 缺省按 scheme 取 443/80
  - `resolve(config : Config, remote : String) : String?`（L45-51）：无 mirror → nil；`fallback_timeout` 为 nil 或 0.0 → 保留 mirror（等价默认 0）；非 0 且探测失败 → nil（调用方沿用既有「mirror 为空即用原 remote」逻辑）
- `src/celerite/config.cr`：
  - `Config.key_for`（L173-190）：先剥离尾部 `.fallback_timeout`（长键）或 `__FALLBACK_TIMEOUT`（环境变量形态），URI 部分补尾斜杠、`.`→`__`、`-`→`___` 后再拼回 `__FALLBACK_TIMEOUT`
  - `mirror_fallback_timeout(remote) : Int32?` → `Float64?`（L346-353），候选键仍为带/不带尾斜杠
  - 新增 `Config.fallback_timeout_seconds(value : ConvertedValue) : Float64?`（L355-378）
- 调用点：`config.mirror_for(remote)` → `Celerite::Mirror.resolve(config, remote)`，共 12 处——`src/celerite/resolution.cr:268,272`、`src/celerite/cli/commands_install.cr:119,217,237,802`、`src/celerite/cli/commands_surface.cr:120,1002,1181,1529`
- `spec/m7_download_settings_spec.cr`：新增 `describe Mirror` 共 11 例（`fallback_timeout_seconds` 映射与整数截断、`reachable?` 开/闭端口与非正超时、`resolve` 的未配置/0/非 0/可达/不可达/`.bundle/config` 文件读取、以及本地 `HTTP::Server` 端到端「mirror 不可达时从原 remote 下载成功」），文件内自 6 例增至 17 例

### 本轮门禁实测（首辅独立复跑，2026-11-15，HEAD=27758b2 + 本工作树）

本宿主必需前缀：PATH 追加 `C:\Program Files\Git\usr\bin;C:\Program Files\Git\cmd;C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin`；链接参数 `<flags>` = `C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o -LC:/msys64/ucrt64/lib -lssl -lcrypto`（本机无 pkg-config，Crystal 不会自动注入 `-lcrypto/-lssl`）。

| 门禁 | 命令 | 结果 |
|---|---|---|
| 格式 | `crystal tool format --check src spec` | EXIT 0 |
| 类型检查 | `crystal build src/celerite.cr -o bin/celerite-m7wip.exe --no-codegen --link-flags <flags>` | EXIT 0（仅既有 2 条 `File.executable?` deprecation：`commands_install.cr:596,660`） |
| 定向 spec | `crystal spec spec/m7_download_settings_spec.cr spec/downloader_spec.cr --link-flags <flags>` | **23 examples, 0 failures, 0 errors, 0 pending**，EXIT 0（5.05s） |
| 全量 spec | `crystal spec --link-flags <flags>` | **263 examples, 1 failures, 0 errors, 0 pending**，EXIT 1（1:02） |
| 空白 | `git diff --check` | EXIT 0 |

全量唯一失败：`spec/config_spec.cr:97 # Celerite::Config writes config set/unset round-trip like the reference`，实际多出 `gem.changelog/gem.ci/gem.mit/gem.coc/gem.linter/gem.test` 与 `http(s)://localgemserver.test/` 等 `Config#all` 项。**归因：既存环境耦合，非本改动引入**——(a) 首辅直读 `C:\Users\ShiningRay\.bundle\config` 证实 8 个非本仓库键；(b) 子代理 `git stash push -u` 后于基线单跑 `crystal spec spec/config_spec.cr` 得 9 examples/1 failures，同一用例、同一 diff 输出；(c) 该现象已记录于 `docs/roadmap.md` L144（2026-11-13 config_spec round-trip 既存失败）。

### 残余风险 / 未验证

1. **探测无缓存**：Bundler 把 `validate!` 结果缓存在 `Mirror` 对象上（每 mirror 一次），本实现每次 `Mirror.resolve` 都建一次 TCP；install/surface 路径按 definition 多次调用，重复建连次数与对时延的实际影响未测量（未验证）。
2. **单地址探测**：`reachable?` 只连 `URI#host` 的单个解析结果，Bundler `MirrorSockets` 遍历全部 A/AAAA 记录；多记录或双栈下可能出现「Bundler 判可达、本实现判不可达」。
3. **负数边界**：`"-1"` → -1.0，走 `timeout <= 0` → 视为可达；Bundler 侧 `-1 != 0` 会进入探测。未加断言（负值非合法配置），风险低。
4. **未做真实镜像 e2e**：本轮以本地 `HTTP::Server` + 关闭端口模拟可达/不可达，未对公网真实 mirror 跑 `install`；`mirror.all` 形态未覆盖。
5. **环境前提**：本机缺 pkg-config，原样「仅带 shim」的 spec 命令会在链接阶段失败（`undefined reference to 'EVP_MD_get_size'`），故所有 spec/build 证据命令均带 `-LC:/msys64/ucrt64/lib -lssl -lcrypto`。
6. **M7(4) 其余 GAP 未动**：proxy 实际路由、legacy/full index 回退、`ssl_client_key` 接线到 TLS 均未实现；M7(4) 复选框保持未勾。

## 2026-11-15 M7(4) 第二子项：`ssl_client_cert` 的 mTLS 私钥接线（客户端证书真实生效）——本轮实测

### 参考语义（`C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\lib\bundler\fetcher.rb`）

- L324-331：`ssl_client_cert` 指向的**同一个 PEM 同时承载证书与私钥**；Bundler 无条件 `con.cert = OpenSSL::X509::Certificate.new(File.read(pem))`，随后 `con.key = OpenSSL::PKey.read(pem)`；若 PEM 只有证书，Ruby 侧 key 为 nil（不报错，握手时由服务端拒绝）。
- L302-304：`ssl_verify_mode`/`ssl_client_cert` 任一存在即加载 openssl。
- **`ssl_client_key` 在 bundler 4.0.24 / 4.0.16 / 2.7.2 三棵树全无**（首辅 `Get-ChildItem -Recurse -Filter *.rb | Select-String 'ssl_client_key'` 无命中；`settings.rb` 亦无该键，未知键无 `Validator` 规则即被静默保存）。因此本产品对 `ssl_client_key` fast-fail 属**既定政策**（roadmap M7(4)「为不支持项快速失败」），不是参考行为镜像；返回文案 `not supported by Celerite: ssl_client_key` 与退出码路径本轮**未改**，只更正 `commands.cr` L955-960 注释（说明参考无此键、私钥应并入 `ssl_client_cert` 的 PEM）。
- RubyGems 侧同类语义：`Gem.configuration.ssl_client_cert` 亦为 cert+key 单文件（`fetcher.rb` L325）。

### 修复前的缺陷

`src/celerite/downloader.cr` 原 L183-185 与 `src/celerite/compact_index/cache.cr` 原 L156-158 只做 `ctx.certificate_chain = cert`，**从不调用 `ctx.private_key=`**。Crystal/OpenSSL 的 `SSL_CTX_use_certificate_chain_file` 只加载证书链，所以任何要求客户端证书的服务端都会在握手期拒绝——即 roadmap L157 声称的「`ssl_client_cert`（Downloader+HttpFetcher TLS chain）已接线」只是半接线，mTLS 实际不可用。

### 实现

- 新增 `src/celerite/tls.cr`（25 行）：`Celerite::TLS.configure_client_certificate(ctx : OpenSSL::SSL::Context::Client, pem_path : String)`——L13 空路径返回；L15 `ctx.certificate_chain = pem_path`；L20 `return unless File.read(pem_path).includes?("PRIVATE KEY")`（覆盖 RSA/EC/ENCRYPTED marker，证书-only PEM 不含该串）；L22 `ctx.private_key = pem_path`。无 key 时不设置，等价 Bundler 的 `key = nil`；口令错/不匹配的真实错误**不 rescue**。
- `src/celerite/downloader.cr` L2 `require "./tls"`、L185 改调用 helper；`src/celerite/compact_index/cache.cr` L2 `require "../tls"`、L158 同。
- 夹具 `spec/fixtures/tls/`（8 文件，自签测试材料，100 年有效期、无口令，随仓库提交）：`ca.pem`/`ca.key`、`server.pem`/`server.key`（CN=localhost，SAN `DNS:localhost, IP Address:127.0.0.1`）、`client.pem`/`client.key`、`client-combined.pem`（cert+key）、`client-cert-only.pem`（仅 cert）。首辅已独立核验：`openssl x509` 显示 `notAfter=Oct 21 16:17:08 2126 GMT` + 正确 SAN，`openssl verify -CAfile ca.pem` 对 server/client 均 `OK`，`git check-ignore` 确认未被仓库忽略规则命中。
- `spec/m7_client_cert_spec.cr`（163 行，5 例）：私有 `ClientCertServer`（`TCPServer`+`OpenSSL::SSL::Server`，ctx = `server.pem`/`server.key`/`ca.pem` + `verify_mode = PEER | FAIL_IF_NO_PEER_CERT`，极简 HTTP/1.1 200 响应，握手异常不杀 accept 循环）。

### 本轮门禁实测（首辅独立复跑，2026-11-15，HEAD=cd16bae + 本工作树）

`<flags>` = `C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o -LC:/msys64/ucrt64/lib -lssl -lcrypto`。

| 门禁 | 结果 |
|---|---|
| `crystal tool format --check src spec` | EXIT 0 |
| `crystal build src/celerite.cr -o bin/celerite-m7wip.exe --no-codegen --link-flags <flags>` | EXIT 0（仅既有 2 条 `File.executable?` deprecation：`commands_install.cr:596,660`） |
| `crystal spec spec/m7_client_cert_spec.cr --link-flags <flags>` | **5 examples, 0 failures, 0 errors, 0 pending**, EXIT 0（63.5ms） |
| `crystal spec spec/m7_download_settings_spec.cr spec/downloader_spec.cr --link-flags <flags>` | **23 examples, 0 failures, 0 errors, 0 pending**, EXIT 0 |
| 全量 `crystal spec --link-flags <flags>` | **268 examples, 1 failures, 0 errors, 0 pending**, EXIT 1（唯一失败 `spec/config_spec.cr:97`，既存机器级 `~/.bundle/config` 污染，见上一节） |
| `git diff --check` | EXIT 0 |

### 负对照（证明正例确由私钥接线决定，首辅亲手复跑）

把 `src/celerite/tls.cr:22` 的 `ctx.private_key = pem_path` 临时注释后重跑同一 spec：**`5 examples, 0 failures, 2 errors`**，两条正例失败（`m7_client_cert_spec.cr:114` Downloader、`:152` HttpFetcher），错误为 `SSL_read: error:0A00045C:SSL routines::tlsv13 alert certificate required (OpenSSL::SSL::Error)`；恢复该行后回到 5/0/0/0。反例（`client-cert-only.pem`、不给 client cert）同样以该 TLS alert 失败，`fetch` 不成功。

### 未验证 / 边界

1. **带口令的加密私钥**（`ENCRYPTED PRIVATE KEY`）未验证：会命中 marker 并调用 `ctx.private_key=`，无口令时 OpenSSL 抛错（不 rescue）；Bundler 的 `PKey.read` 亦失败但文案不同，未加断言。
2. **多级证书链 + 分离 key 文件**未实测：`ssl_client_cert` 指向含中间 CA 的 PEM 时预期按整链加载，本轮只验证「单 cert+同 PEM key」与「仅 cert」两态。
3. **仅 TLS 1.3 实测**：服务端/客户端均默认 TLS 1.3；TLS 1.2 下的 client-cert 失败路径未单独覆盖。
4. **未对真实远端 mTLS 场景验证**：全部为本地回环离线夹具。
5. 夹具中的 `*.key` 为自签测试材料，不含生产凭据；轮换按 `spec/m7_client_cert_spec.cr` L6-24 的命令重建。
6. `ssl_client_key` 仍 fast-fail（政策不变）；proxy 路由、legacy/full index 回退仍未实现，M7(4) 复选框保持未勾。

## 2026-11-15 M7(8) 产品差异①：path 源锁文件相对化

### 参考语义（bundler 4.0.24，`lib/bundler/source/path.rb`）
- L23-31 `initialize`：相对输入→`expanded.relative_path_from(root)`；绝对输入→保留 expanded 绝对；L38 `@original_path = @path`。
- L45-49 `to_lock` → `remote: #{lockfile_path}`。
- L136-139 `lockfile_path`：绝对→`relative_path(original_path)`；相对→`expand(original_path).relative_path_from(root)`。
- L210-215 `relative_path`：仅当 `path.to_s.start_with?(root_path.to_s)` 才相对化，否则原样返回（项目外/跨盘保持原样）。
- 上游用例 `spec/lock/lockfile_spec.rb:1154`：Gemfile `path File.expand_path("foo", __dir__)` → 期望 `PATH\n  remote: foo\n  specs:\n    foo (1.0)\n`。

### 修复前行为（实测）
`Resolution#generated_lockfile` 原 L946-952 把 `source_info.remote` 原样写入 PATH 段，Gemfile 写绝对路径时锁文件得到绝对 `remote:`。修复前跑新 spec：**4 examples, 3 failures, 0 errors**（2.17s），失败原文关键行：

```
PATH
  remote: C:/Users/ShiningRay/AppData/Local/Temp/celerite-spec-20261115-15640-zjmsfzproj/vendor/example
  specs:
    example (1.0.0)
```

（`spec/m7_path_lockfile_relative_spec.cr:36` 期望 `remote: vendor/example`；`:56` 相对写法前后字节不一致；`:98` 归一后 remote 缺失。项目外绝对路径用例修复前即通过，符合参考「不在 root 下保持原样」。）

### 实现
- `src/celerite/resolution.cr`（HEAD=8de9eb4 + 本工作树）：
  - L931-938 `lockfile_path_for(remote : String) : String`：空串原样；`root = File.expand_path(File.dirname(@definition.gemfile_path))`；`expanded = File.expand_path(remote, root)`；`relative_under_root` 命中→相对路径；否则绝对路径（`local_absolute_path?` 判 `/`、`\\`、盘符）→ expanded 转 `/`；相对且不在 root 下→原样（`/` 归一）。
  - L940-951 `relative_under_root`：根相等→`"."`；`path` 以 `root + "/"` 开头（Windows 大小写不敏感，编译期 `{% if flag?(:windows) %}`）→去前缀；否则 nil。
  - L953-955 `local_absolute_path?`：`/`、`\\`、`[A-Za-z]:[\/\\]`。
  - L978-984 PATH 段 `group_by { |spec| lockfile_path_for(...) }`，分组 key 与 `remote:` 同用归一值（同一源两种写法不再裂段）。
- 未改 `ensure_source_dir`（解析侧仍按 Gemfile 目录展开）、GIT/GEM 段与 `sources_compatible?`（后者只比 GEM remote；实测再跑不抖动）。

### 门禁实测（2026-11-15，HEAD=8de9eb4 + 本工作树）

`<flags>` = `C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o -LC:/msys64/ucrt64/lib -lssl -lcrypto`。

| 门禁 | 结果 |
|---|---|
| `crystal tool format src spec` / `crystal tool format --check src spec` | EXIT 0 / EXIT 0 |
| `crystal build --no-codegen --link-flags <flags> src/cli.cr` | EXIT 0（仅既有 2 条 `File.executable?` deprecation：`commands_install.cr:596,660`） |
| `crystal spec spec/m7_path_lockfile_relative_spec.cr --link-flags <flags>`（修复后） | **4 examples, 0 failures, 0 errors, 0 pending**, EXIT 0（2.26s） |
| 全量 `crystal spec --link-flags <flags>` | **272 examples, 1 failures, 0 errors, 0 pending**, EXIT 1（唯一失败 `spec/config_spec.cr:97`，既存机器级 `~/.bundle/config` 污染，见上一节） |
| `git diff --check` | EXIT 0 |

### 覆盖
1. 项目内绝对路径（`File.expand_path("vendor/example", dir)` 写入 Gemfile）→ 锁文件 `remote: vendor/example`，不含绝对前缀、不含反斜杠。
2. 首轮绝对、次轮相对写法 → 锁文件逐字节不变（幂等）。
3. 项目外绝对路径（`File.tempname` 造 gem）→ 锁文件保留绝对（正斜杠）。
4. 同一绝对 Gemfile 连跑两次 `lock` → 均 EXIT 0、锁文件字节一致、remote 保持相对（锁复用不抖动）。

### 未验证 / 边界
1. **Windows 跨盘**（`D:\...` 相对 `C:\...` 项目）与 **UNC**（`\\server\share`）未实测；代码按「不在 root 下→保持绝对」处理，但无 spec。
2. `glob:` 未实现（本轮明确不动）。
3. 真实 `bundle install` e2e 未跑：本轮只验证 `lock` 生成/复用；安装侧 `ensure_source_dir` 未改，依赖既有行为。
4. 大小写：仅 Windows 比较大小写不敏感；macOS 默认大小写不敏感文件系统上，若 Gemfile 路径大小写与目录实际大小写不同，可能判为「不在 root 下」而保持绝对（未验证）。
5. 上游 differential 未重跑；`lockfile_spec.rb:1154` 场景尚未 fixture 化到 `fixtures/differential/`。

## M7(8) 第二子项：锁文件 specs 为空时重解析（2026-11-15，HEAD=8de9eb4 + 本工作树）

- **参考语义（bundler 4.0.24）**：`definition.rb` L630-645 `something_changed?` 把 `@missing_lockfile_dep` / `@locked_spec_with_missing_deps` / `@locked_spec_with_invalid_deps` 计入变化源；L1051-1076 `converge_dependencies` 对「DEPENDENCIES 有、specs 中无该 gem」的依赖置 `@missing_lockfile_dep`（L1068-1069）；L973-1014 `check_lockfile` 对依赖边 `:missing`（指向未锁定 gem）与 `:invalid`（版本不满足）删除 spec 并置对应标志。上游用例 `lockfile_spec.rb:1882` `regenerates a lockfile with no specs`：预置 `GEM remote: ... specs:`（空）+ `DEPENDENCIES direct_dependency`，install 后须出现 `direct_dependency (4.5.6)` 与 `indirect_dependency (1.2.3)`。
- **修复前缺陷**：`resolution.cr` L526-550 `reuse_locked_resolution?` 只比较 DEPENDENCIES 集合 + requirement + sources + platform + ruby 版本，不检查 `specs:` 是否覆盖依赖；一旦判可复用，`materialize_locked`（L603-614）从空 specs 返回空数组，install 的复用路径（`commands_install.cr:177 resolve!(reuse)`）既不安装也不重写锁文件。实测：新 spec 修复前 **4 examples, 2 failures**——`:47`/`:87` 两处 `reuse_locked?` 期望 false 实得 true（空 specs、依赖边缺失各一）。注：`lock` 命令走 `commands_surface.cr:247 no_reuse: true`，修复前不暴露该缺陷；真实入口是 install 的复用路径，故负对照在 `resolve!(reuse: true)` 上做。
- **实现**：`src/celerite/resolution.cr` L546 在 DEPENDENCIES 对齐后 `return false unless lockfile_covers_dependencies?(lockfile, deps)`；L558-587 新增私有 `lockfile_covers_dependencies?`——把所有 source 的锁定 spec 聚合为 `Hash(String, Array(Lockfile::Spec))`；每个顶层依赖（跳过 `bundler`）必须存在锁定 spec（`@missing_lockfile_dep` 等价）；每条 `Spec` 的 `SpecDependency` 边必须命中锁定 gem 且 `edge.requirement.satisfied_by?(Gem::Version.new(target.version))`（missing/invalid 两类等价）。未改锁文件写出格式、PATH/GIT 段、`materialize_locked`、`build_locked_index`/`locked_index`。
- **修复后**：`spec/m7_lockfile_regen_spec.cr` **4 examples, 0 failures, 0 errors, 0 pending**（1.4s，EXIT 0）：①空 specs + `gem "thor"` 经 `resolve!(reuse: true)` 得 `thor 1.3.2`；②已覆盖锁文件仍 `reuse_locked? == true` 且返回 `["thor"]`（不误触发重解析）；③锁定 spec 声明 `racc (~> 1.4)` 但锁文件无 racc → 判不可复用，重解析后为 `json_pure 2.6.0`；④`lock` 端到端把空 specs 重写为 `    thor (1.3.2)`，EXIT 0。
- **门禁**（`<flags>` = `C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o -LC:/msys64/ucrt64/lib -lssl -lcrypto`）：

| 门禁 | 结果 |
|---|---|
| `crystal tool format src spec` / `crystal tool format --check src spec` | EXIT 0 / EXIT 0 |
| `crystal build --no-codegen --link-flags <flags> src/cli.cr` | EXIT 0（仅既有 2 条 `File.executable?` deprecation：`commands_install.cr:596,660`） |
| `crystal spec spec/m7_lockfile_regen_spec.cr --link-flags <flags>` | **4 examples, 0 failures, 0 errors, 0 pending**, EXIT 0（1.4s） |
| 全量 `crystal spec --link-flags <flags>` | **276 examples, 1 failures, 0 errors, 0 pending**, EXIT 1（唯一 `spec/config_spec.cr:97` 机器级 `~/.bundle/config` 污染，非回归；修复前基线 272/1） |

- **负对照**：修复前同 spec 在 `:47`/`:87` 报 `Expected: false / got: true`；②合法复用与④`lock` 端到端修复前即通过，说明新谓词不是恒 `false`。
- **未验证/边界**：真实 `bundle install` e2e 未跑（复用路径由 `Resolution#resolve!(reuse: true)` 直接驱动，不落 gem 安装副作用）；锁文件 `specs:` 与 DEPENDENCIES 集合不一致时仍由既有 L533-541 判定，本轮未另加用例；平台变体缺失由既有 `covers_local_platform?` 处理，未扩；`bundler` 顶层依赖键被跳过（参考锁文件通常不含）；上游 `lockfile_spec.rb:1882` 场景尚未 fixture 化到 differential。

## M7(8) 第三子项：冲突标记消息使用相对 lockfile 路径（2026-11-15）

- **参考锚点（bundler 4.0.24）**：`lockfile_parser.rb` L105-109 `@lockfile_path = SharedHelpers.relative_lockfile_path`（`relative_path_to(Bundler.default_lockfile)` = `Pathname#relative_path_from(Pathname.new(Dir.pwd))`，`rescue ArgumentError` 时原样返回）；L113-116 冲突消息与 L123-124（invalid lockfile）、L169-171（unreadable 位置）同用该相对值；上游用例 `lockfile_spec.rb:2431-2437` 断言 `/your Gemfile.lock contains merge conflicts/i` 与 `/git checkout HEAD -- Gemfile.lock/i`。
- **修复前缺陷与实测输出**：`parser.cr` 的冲突消息与 unreadable 消息直接插入 `@lockfile_path`，而 `definition.cr:80` 传入绝对路径（`Definition.resolve_lockfile` 的 expand 结果）。新 spec 修复前 `crystal spec spec/m7_lockfile_conflict_spec.cr` 得 **5 examples, 4 failures, 0 errors**（744ms，EXIT 1），实际 stderr（Thor 风格按 80 列 word-wrap，路径过长被单独折行）：
  `Your` / `C:\Users\...\celerite-spec-...\Gemfile.lock` / `contains merge conflicts.` / `Run \`git checkout HEAD --` / `C:\Users\...\Gemfile.lock\`` / `first to get a clean lock.`；单元级 `Parser.parse(text, 项目外绝对路径)` 同样输出绝对路径。exit 20 正确（`LockfileError` → 20）。
- **实现**：`src/celerite/lockfile/parser.cr` 新增私有 `display_lockfile_path`（L162-184）与 `same_path_component?`（L186-192）：`File.expand_path(@lockfile_path)` 与 `File.expand_path(Dir.current)` 按组件比较（Windows 盘符与组件均大小写不敏感），公共前缀之外的当前路径组件补 `..`，拼接结果以 `/` 连接；Windows 盘符不同（跨盘）或 UNC 与本地根不同时直接回退 `@lockfile_path` 原值。冲突消息（L126-127）与 unreadable 消息（L150-152）改用该值；`Lockfile::Data#lockfile_path` 保持原样（`model.cr:286` getter 未动），解析状态机、退出码未动。
- **修复后**：**5 examples, 0 failures, 0 errors, 0 pending**（713ms，EXIT 0）：①`install` 退出 20 且 stderr 含 `Your Gemfile.lock contains merge conflicts.`／`Run \`git checkout HEAD -- Gemfile.lock\``，不含项目绝对路径、不含任何盘符路径；②`err.chomp` 与参考两行逐字相等；③项目外（父目录）锁文件显示为 `../celerite-spec-elsewhere/Gemfile.lock`（`Pathname#relative_path_from` 语义）；④Windows 下另一盘符 `D:/celerite-spec-elsewhere/Gemfile.lock` 不可相对化 → 消息保留原绝对路径；⑤unreadable 消息同样相对化（`Your Gemfile.lock is unreadable.`／``Run `rm Gemfile.lock` ``）。
- **负对照**：修复前 **4/5 失败**（测试 ①②③⑤），修复后 **5/5 通过**，同一文件同一断言；其中 ①②③ 是路径断言的直接失败证据（stderr 折行内含项目绝对路径、父目录未相对化），⑤ 修复前的失败原因是夹具 `thor (bogus` 未闭合未被识别为 spec 行、未触发 unreadable 分支（非路径证据；改为 `thor (bogus)` 后该例只验证了修复后行为）；④（跨盘回退）修复前后均通过，证明新逻辑不是无条件相对化。
- **门禁**（`<flags>` = `C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o -LC:/msys64/ucrt64/lib -lssl -lcrypto`）：

| 门禁 | 结果 |
|---|---|
| `crystal tool format src spec` / `crystal tool format --check src spec` | EXIT 0 / EXIT 0 |
| `crystal build --no-codegen --link-flags <flags> src/cli.cr` | EXIT 0（仅既有 2 条 `File.executable?` deprecation：`commands_install.cr:596,660`） |
| `crystal spec spec/m7_lockfile_conflict_spec.cr --link-flags <flags>` | **5 examples, 0 failures, 0 errors, 0 pending**, EXIT 0（713ms） |
| 全量 `crystal spec --link-flags <flags>` | **281 examples, 1 failures, 0 errors, 0 pending**, EXIT 1（唯一 `spec/config_spec.cr:97` 机器级 `~/.bundle/config` 污染，非回归；本轮前基线 276/1） |

- **未验证/边界**：真实 `bundle install` 命令级 e2e 未跑（spec 通过 `run_cli(["install"])` 进程内驱动，但未验证真实 gem 安装）；UNC 路径（`\\server\share`）未实测（仅按盘符分支推断回退，Windows 下 `expand_path` 处理 UNC 的形态未验证）；`Dir.pwd` 在符号链接目录下的表现（`Pathname` 不做 realpath，我们的实现同样按字面展开）未验证；非 Windows 下同根路径总能相对化，因此「不可相对化回退」分支只在 Windows spec 中覆盖；上游 `lockfile_spec.rb:2431` 场景尚未 fixture 化到 differential。

## 2026-11-15 M7(8) 第四子项：锁定 spec 的依赖边缺失时 install 补齐（产品差异④）

- **参考语义（逐行锚定）**：
  - 上游用例 `spec/lock/lockfile_spec.rb:2088-2142`（`automatically fixes the lockfile when it has incorrect deps, keeping the locked version`）：repo4 提供 `net-smtp 0.5.0`／`net-smtp 0.5.1`（两者都依赖 `net-protocol`）与 `net-protocol 0.2.2`；预置锁文件只列 `net-protocol (0.2.2)` 与 `net-smtp (0.5.0)` 且**没有** `net-smtp` 的依赖子行。install 后锁文件必须补出 `      net-protocol`，且版本保持 0.5.0/0.2.2（不得升到 0.5.1）。
  - 为什么 `check_lockfile`（`definition.rb:973-1014`）抓不到这条缺失边：`LazySpecification#initialize`（`lazy_specification.rb:26-39`）把 `@dependencies` 置为 `[]`，`spec_set.rb#validate_deps` 看到的是空边；真实依赖只在 `SpecSet#materialize` 载入已安装/真实 gemspec 后出现，锁文件因此由 materialize 后的 spec 生成。故修法必须来自真实 gemspec 元数据，而不是锁文件自省。
- **修复前行为**：`install` 走复用路径（`commands_install.cr:177` `resolution.resolve!(reuse)`），`materialize_locked`（`resolution.cr:640-651`）原样复制锁文件里缺失的依赖边，写回时语义不变 → 空边永久保留。实测负对照：`spec/m7_lockfile_locked_deps_spec.cr` **2 examples, 1 failures, 0 errors**（2.07s，EXIT 1），失败断言 `lock.should contain("    net-smtp (0.5.0)\n      net-protocol\n")`（`spec/m7_lockfile_locked_deps_spec.cr:89`，首辅负对照复跑同一点）：install 退出码为 0、无错误输出，但锁文件 `net-smtp (0.5.0)` 下没有 `      net-protocol` 子行。
- **实现**：
  - `src/celerite/resolution.cr` L653-680：新增 `def refresh_locked_dependencies(packages : Hash(String, String), & : String -> Array(Lockfile::SpecDependency)) : Nil`（L666）。仅处理 `source_type == "GEM"` 且本次确实拿到 `.gem` 路径的 spec；依赖边与当前相同时不重建（避免无谓改写）；不同时以原 `name/version/platform/checksum/source_index/source_type/source_info/source_remote` 重建 `ResolvedSpec`，只替换 `dependencies`。PATH/GIT 不计入，fresh resolve 不调用（注释注明这是锁定路径的对齐行为）。
  - `src/celerite/cli/commands_install.cr` L256-276：`if reuse && cached_paths.any?` 时、写锁文件（L290+）之前调用；block 内 `Bridge::GemSpecInfo.from_json(bridge.read_gem_spec(package).to_json)` 取真实 gemspec，过滤 `type == "runtime"`，`requirements` 转 `Array(String)` 后构造 `Lockfile::SpecDependency`（无新增网络请求；读的是本次已下载的 `.gem`）。
  - 未改 `materialize_locked`、锁文件写出格式、PATH/GIT 段、`pending` 计算与下载输出顺序。
- **修复后**：**2 examples, 0 failures, 0 errors, 0 pending**（2.25s，EXIT 0）：①空边锁文件 install 后出现 `    net-smtp (0.5.0)\n      net-protocol`、`net-protocol (0.2.2)` 仍在、无 `net-smtp (0.5.1)`；②依赖边已完整时第二次 install 锁文件逐字节不变且不打印 `Fetching net-smtp`。
- **负对照**：修复前 1/2 失败（断言级 diff 见上），修复后 2/2 通过；测试②修复前后均通过，用于防止“无条件改写锁文件”。
- **夹具（离线、可重复）**：`spec/fixtures/locked-deps/gems/` 下 `net-protocol-0.2.2.gem`、`net-smtp-0.5.0.gem`、`net-smtp-0.5.1.gem`（各 4096B；两个 net-smtp 版本均 `add_runtime_dependency "net-protocol"`）。生成命令：`ruby -S gem build <name>.gemspec --output <dest>`（gemspec 仅 name/version/summary/authors/files/require_paths）。Downloader 下载路径为 `<remote>/gems/<full name>.gem`，故 Gemfile 的 `source` 取 `spec/fixtures/locked-deps` 这一层（`file_source_url(...)`）。
- **门禁**（`<flags>` = `C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o -LC:/msys64/ucrt64/lib -lssl -lcrypto`）：

| 门禁 | 结果 |
|---|---|
| `crystal tool format src spec` / `crystal tool format --check src spec` | EXIT 0 / EXIT 0 |
| `crystal build --no-codegen --link-flags <flags> src/cli.cr` | EXIT 0（仅既有 2 条 `File.executable?` deprecation：`commands_install.cr:616,680`） |
| `crystal spec spec/m7_lockfile_locked_deps_spec.cr --link-flags <flags>` | **2 examples, 0 failures, 0 errors, 0 pending**, EXIT 0（2.25s） |
| 全量 `crystal spec --link-flags <flags>` | **283 examples, 1 failures, 0 errors, 0 pending**, EXIT 1（唯一 `spec/config_spec.cr:97` 机器级 `~/.bundle/config` 污染，非回归；本轮前实测基线 281/1） |

- **未验证/限制**：
  1. 只覆盖“本次确实下载到 `.gem`”的场景；参考在 gem 已安装时会读已安装 gemspec，本轮未接（已安装且缓存外时依赖边保持锁文件原样，不报错）。
  2. `--force/--redownload` 分支（`force_install`）不产生 `cached_paths`，同样不刷新。
  3. fresh resolve（`lock`/`update`）不刷新边，依赖索引元数据正确；若索引元数据本身缺失边，与本修复无关、未覆盖。
  4. 平台变体 spec 的边满足语义未做差分；上游 `lockfile_spec.rb:2088` 未 fixture 化到 differential。
  5. 真实 `bundle install` 命令级 e2e 未跑（仅 `run_cli(["install"])` 进程内驱动）。
  6. spec 通过把 `HOME`/`USERPROFILE` 指向临时项目隔离下载缓存（`InstallPaths.downloader_cache_root` = `~/.bundle/cache`，产品本身仍是全局缓存，未改）。

## 2026-11-15 M7(4) 第三子项：HTTP(S) proxy 路由真实生效

- **参考语义（逐行锚定）**：Bundler vendored `net-http-persistent` 的 `persistent.rb` L843-859（`proxy_uri`）、L860-875（`proxy_from_env`：只读 `http_proxy`/`HTTP_PROXY`，空值即无代理）、L629-635（`proxy_bypass?`），以及 `fetcher.rb:313-316`、`remote_fetcher.rb:62-69`；`https_proxy`/`ALL_PROXY` 在参考实现中不参与，`~/.gemrc` 的代理条目也不读取。
- **修复前行为**：`src/celerite/cli/commands.cr` 的 `Commands.unsupported_setting_error` 对 proxy env 只打印 `warning: HTTP proxy (...) is set but Celerite does not route through proxies`，显式 config `proxy`/`http_proxy`/`https_proxy` 则返回 `not supported by Celerite: proxy` 并非零退出；`Downloader` 与 `CompactIndex::HttpFetcher` 都直接 `HTTP::Client.new`，代理配置完全不生效。
- **实现**：
  - 新增 `src/celerite/proxy.cr`：`Proxy.from_environment`（`http_proxy` 优先、`HTTP_PROXY` 次之、空/空白→nil）、`Proxy.resolve(config)`（config `proxy`→`http_proxy`→env）、`bypass?(host, port)`（`no_proxy`/`NO_PROXY` 逗号项后缀匹配，`*` 全绕过）、`authorization`、`port` 默认 80，无 scheme 补 `http://`。
  - 新增 `src/celerite/http_transport.cr`：`HttpTransport.get(uri, path, headers, tls, proxy, timeout)`；直连走 `HTTP::Client`；http 代理用绝对 URI 请求行；https 代理先 `CONNECT` 建隧道再 `OpenSSL::SSL::Socket::Client`（SNI=目标 host），响应统一 `HTTP::Client::Response.from_io`。
  - 接线：`src/celerite/downloader.cr`（重试/redirect/Authorization 保留）、`src/celerite/compact_index/cache.cr`（`HttpFetcher`、`Client`、`make_fetcher` 传递 `proxy`）、`src/celerite/resolution.cr` L268/L272、`src/celerite/cli/commands_install.cr` 4 处与 `commands_surface.cr` 4 处 `Downloader.new` 传 `proxy:`；`src/celerite/cli/commands.cr` 删除 proxy warn 与 config fast-fail（`ssl_client_key`、`legacy_index`、`full_index` 保持 fast-fail）。
- **负对照**：接线前 `spec/m7_proxy_spec.cr` 首例 `1 examples, 1 failures, 0 errors`（`proxy.requests.size.should eq(1)` got 0）；接线后同例 `1 examples, 0 failures, 0 errors`。实现过程中一次 404 由 `absolute_target` 误用基址 `request_target` 造成，修正为使用显式 `path` 参数。
- **门禁**（`<flags>` = `C:/Users/ShiningRay/AppData/Local/Temp/celerite-shim-m7wip/evp_md_size_shim.o -LC:/msys64/ucrt64/lib -lssl -lcrypto`）：

| 门禁 | 结果 |
|---|---|
| `crystal tool format src spec` / `crystal tool format --check src spec` | EXIT 0 / EXIT 0 |
| `crystal build --no-codegen --link-flags <flags> src/cli.cr` | EXIT 0（仅既有 2 条 `File.executable?` deprecation） |
| `crystal spec spec/m7_proxy_spec.cr --link-flags <flags>` | **7 examples, 0 failures, 0 errors, 0 pending**, EXIT 0 |
| 全量 `crystal spec --link-flags <flags>` | **290 examples, 1 failures, 0 errors, 0 pending**, EXIT 1（唯一 `spec/config_spec.cr:97` 机器级 `~/.bundle/config` 污染，非回归） |

- **覆盖**：http 代理绝对 URI、https CONNECT 隧道、`no_proxy` host:port 后缀命中、`no_proxy=*`、config `proxy` 覆盖 env、`https_proxy`/`ALL_PROXY` 被忽略、无 scheme 补 `http://`。
- **未验证/限制**：真实公网代理与代理鉴权（`http_proxy_user/pass` 仅构造 `Proxy-Authorization`，未在真代理上验证）；SOCKS 代理未实现；NTLM/挑战式代理认证未支持；`~/.gemrc` 代理条目不读取；HTTPS 隧道仅靠 `CONNECT` 200 状态判断，未校验隧道内首包；`no_proxy` 仅后缀匹配（参考实现同为后缀，但 IPv6 字面量未测）。

## 2026-11-15 M7(4) 第四子项：`path.system` 真实语义

- 参考锚点：`bundler-4.0.24/lib/bundler/settings.rb` L238-297（`Bundler::Settings::Path`：`base_path` L255-260、`use_system_gems?` L246-253、`path` L270-280）、`settings/validator.rb` L57-63（`path` 与 `path.system` 同层冲突时后写者清空前者）、`errors.rb:34`（`InvalidOption` exit 15，本轮未实现）。
- 修复前缺陷：`InstallPaths.install_path` 在 `path.system` 为真时返回 `Config.user_home`，调用点再拼 `ruby/<abi>`，实际落成 `<home>/ruby/<abi>`——既非 `Gem.dir`，也错误追加 ruby scope。探针（修复前源码，临时 spec，已删除）：本地 `file:` 源 + `BUNDLE_PATH__SYSTEM=true` + `GEM_HOME=<tmp>/sys-gems` 跑 `install`，退出 0，但 `<tmp>/sys-gems/gems/thor-1.3.2` 不存在（同场景修复后通过）。
- 实现：`src/celerite/resolution.cr` 的 `InstallPaths` 新增 `system_gems?(config)`、`base_path(config, system_gem_dir)`、`gem_root(config, system_gem_dir, abi)`、`ruby_root(config, system_gem_dir)`；`src/celerite/installer.cr` 构造器直接接收 gem root（`getter install_root`），删除内部 `File.join(install_path, "ruby", abi)`；`src/celerite/cli/commands_install.cr`（install/update/check 等）与 `src/celerite/cli/commands_surface.cr`（update/plugin/cache/exec/show/list 等）的 `<base>/ruby/<abi>` 拼接改为 `InstallPaths.gem_root(..., bridge.ruby_environment.default_gem_dir, abi)`；`ProcessLock`、`--standalone` 的 `bundler/setup.rb`、`cache`/`clean` 的 `<base>/ruby` 枚举保持 base（无桥，限制见下）。
- 门禁（本轮工作树）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags "<shim> -LC:/msys64/ucrt64/lib -lssl -lcrypto" src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；`crystal spec spec/m7_path_system_spec.cr` **4 examples, 0 failures, 0 errors**；`git diff --check` EXIT 0；全量 spec 结果见本次交付报告。
- 顺序依赖根因与修复（2026-11-15 追加）：`system_gem_search_dirs` 原为一次性类变量缓存，全量套件中前序用例在默认 `GEM_HOME` 下先算过缓存后，本用例设置 `GEM_HOME=<tmp>/sys-gems` 仍复用旧目录 → `check` 报 `The following gems are missing`（修复前诊断：`gem_home_children=["bin","cache","gems","specifications"]`、`spec_children=["thor-1.3.2.gemspec"]`，gem 已装好但发现路径未刷新）。现缓存按环境签名（`GEM_HOME`/`GEM_PATH`/`HOME`/`USERPROFILE`）键控，签名变化即重算；`installed_gem_dir` 在 `path.system` 下显式先查 `<Gem.dir>/gems/<full_name>`；`installed_git_checkout` 在 system 模式下改查 `<Gem.dir>/bundler/gems`（无 `ruby/<abi>` 层）。`spec/m7_path_system_spec.cr` 恢复 `check` 断言并新增「进程内环境变化后重算」用例（5 examples 0 failures）；全量 **295 examples, 1 failures**（唯一既存 `spec/config_spec.cr:97`），`check` 顺序依赖不再复现。
- 仍未验证/限制：`cache`/`clean` 的 `<base>/ruby` 枚举在 `path.system` 下仍按产品 base（无桥，未接 `Gem.dir`）；`bundle config set path.system` 写法、`path` 与 `path.system` 同层的 `InvalidOption` exit 15、真实系统 gem 目录写入（用 `GEM_HOME` 隔离替代）、`disable_shared_gems` 均未实现/未跑；Windows 大小写不敏感与跨盘分支未单独验证。

## 2026-11-15 M7(4) 收口审计

逐项列出 M7(4) 各配置项的落地状态与证据。状态定义：**REAL** = 配置真实生效且有行为级断言；**fast-fail** = 显式设置即报错退出（既定政策）；**未实现** = 无对应行为。

| 配置项 | 状态 | 证据锚点（源码 / spec） | 未验证项 |
|---|---|---|---|
| `mirror.<url>`（含 `fallback_timeout`） | REAL | `src/celerite/mirror.cr:28`（`reachable?`）、`:45`（`resolve`）；`src/celerite/config.cr:348`/`:360`；`spec/m7_download_settings_spec.cr:102` 起 8 例（含 `truncates the numeric branch…`、`keeps an unreachable mirror when fallback_timeout is 0`） | 真实公网 mirror 故障切换；多地址 host 只探测首个地址 |
| `proxy` / `http_proxy` | REAL | `src/celerite/proxy.cr:28`/`:36`/`:64`；`src/celerite/http_transport.cr:19`；`src/celerite/downloader.cr:215`；`src/celerite/compact_index/cache.cr:184`；`spec/m7_proxy_spec.cr` 7 例（http 绝对 URI、https CONNECT、no_proxy 后缀/`*`、config 覆盖 env、`https_proxy` 忽略） | 真实代理鉴权；SOCKS；IPv6 `no_proxy` |
| `redirect` | REAL | `src/celerite/downloader.cr:226-243`（301/302/303/307/308、`max_redirects` 上限、`Location` 相对化 `:258-267`）；`spec/m7_transport_evidence_spec.cr:37`（302 + 相对 `Location` 跟随，字节相等，服务端实收 `["/gems/…", "/real/…"]`）、`:64`（`max_redirects: 0` → `DownloadError`「Too many redirects (>0)」） | 跨 host 跳转、空/畸形 `Location`、307/308 method 保持（端点均为 GET）未验证 |
| `retry` | REAL | `src/celerite/downloader.cr:210-241`（`max_attempts = retries + 1`、指数退避；非 200 与网络异常均重试）；`src/celerite/compact_index/cache.cr:105-128`；`spec/m7_transport_evidence_spec.cr:83`（500,500,200 + `retries: 2` → 成功、实收 3 次）、`:108`（`retries: 0` → 1 次）、`:168`（恒 404 + `retries: 2` → 3 次后 `GemNotFoundError`）、`:189`（恒 500 + `retries: 2` → 3 次后抛错） | **与参考一致（按路径分层）**：gem 下载路径 `rubygems_integration.rb:379-407` 的 `Retry.new("download gem from …")` 未传 exceptions，`retry.rb:55` 对任意 `StandardError` 重试，404 经 `remote_fetcher.rb:237` 变 `FetchError` 故被重试；spec/API 路径 `fetcher.rb:159/173` 传 `FAIL_ERRORS`（`:101-125` 含 `HTTPNotFound`/`FallbackError`/`HTTPBadGateway`）→ 404/502 立即失败。`compact_index` 仅 408/429/5xx 重试（`spec/compact_index/http_fetcher_spec.cr:85`），同参考分层 |
| `timeout` | REAL | `src/celerite/downloader.cr:38-39`（`connect_timeout`）、`:50`、`:215`；`spec/m7_download_settings_spec.cr:85-88`（`connect_timeout == 1.second`） | 读超时触发路径未单独断言 |
| `ssl_ca_cert` | REAL | `src/celerite/downloader.cr:187-188`；`src/celerite/compact_index/cache.cr` TLS ctx；`spec/m7_proxy_spec.cr:143`、`spec/m7_client_cert_spec.cr` 用 `fixtures/tls/ca.pem` 握手 | 自定义 CA 与系统 CA 混用未测 |
| `ssl_verify_mode` | REAL | `src/celerite/downloader.cr:193-200`；`src/celerite/compact_index/cache.cr:165-170`；`spec/m7_transport_evidence_spec.cr:129`（`none` + 自签 → 成功）、`:139-149`（默认 peer → `Celerite::CertificateFailureError` + 消息前缀断言）、`:150`（`ssl_ca_cert: fixtures/tls/ca.pem` → 成功） | `none` 下 hostname 校验细节、TLS1.2、与 mTLS 组合未验证 |
| `ssl_client_cert`（mTLS） | REAL | `src/celerite/tls.cr:12`（`configure_client_certificate`，`:22` 私钥）；`src/celerite/downloader.cr:185`、`src/celerite/compact_index/cache.cr:158`；`spec/m7_client_cert_spec.cr` 5 例（正例、cert-only 反例、无 cert 反例、空路径、HttpFetcher） | 带口令 PEM；TLS1.2 |
| `path.system` | REAL | `src/celerite/resolution.cr:12-62`（`system_gems?`/`base_path`/`gem_root`）；`src/celerite/cli/commands_surface.cr:580-590`、`:661-663`、`:665-694`；`spec/m7_path_system_spec.cr` 5 例（含 `check` 与进程内环境变化重算） | `cache`/`clean` 枚举；`InvalidOption` exit 15；真实 `Gem.dir` 落盘 |
| `build.<gem>` | REAL | `src/celerite/installer.cr:40-46`（`config_build_args`）、`:161-163`（传给桥）；`src/celerite/bridge/client.cr:208-212`；`assets/bridge/server.rb:251-252`；`spec/m7_build_args_spec.cr` 2 例（有参/无参；负对照把 `build_args` 置 `nil` 时 marker 为 `[]`） | 多 gem 各自参数、含空格/引号的参数切分、真实编译型扩展（夹具为 no-op Makefile） |
| `ssl_client_key` / `legacy_index` / `full_index` | fast-fail | `src/celerite/cli/commands.cr:960-976`；调用点 `commands_install.cr:88`、`:396`、`commands.cr:997`、`commands_surface.cr:57`；`spec/m7_build_args_spec.cr:118` 起 3 例（逐键消息、proxy/已支持键返回 nil、CLI exit 1 + 消息） | 参考实现 grep 复核：bundler 4.0.24 `grep -R` 对三键均 0 命中，故 fast-fail 是政策而非缺口 |

**2026-11-15 续（redirect/retry/ssl_verify_mode 实测补证）**：新增 `spec/m7_transport_evidence_spec.cr`（7 examples）用本地 HTTP/TLS 服务补真实链路证据，过程中发现并修复两处 `redirect` 缺陷：

1. `Location` 为相对路径（`/real/...`）时，原实现 `@remote = loc` 后 `URI.parse` 无 host，`HttpTransport` 抛 `missing host`；修复为 `resolve_redirect_location`（`src/celerite/downloader.cr:258-267`，`URI#resolve` + `rescue → location`）。
2. 跳转后仍按 `/gems/<full>.gem` 重建请求路径，导致「跳到 `/real/…` 又请求 `/gems/…`」无限循环；修复为给 `download_to` 增加 `request_path : String? = nil`（`:142`、`:145`），redirect 分支取 `URI.parse(resolved).request_target`（`:238-243`）。负对照（去掉 `request_path`）实测：`Too many redirects (>5) for http://127.0.0.1:63063/real/net-protocol-0.2.2.gem (Celerite::DownloadError)`，`7 examples, 1 errors`，栈中重复 `downloader.cr:243:20 in 'download_to'`。

`retry` 证据（2026-11-15 收尾复核）：gem 下载路径对 404 也重试——`spec/m7_transport_evidence_spec.cr:168` 恒 404 + `retries: 2` → 服务端实收 3 次后抛 `GemNotFoundError`；`:189` 恒 500 + `retries: 2` → 同样 3 次后抛错（证明 5xx 仍重试）；`:83` 两次 500 后 200 → 成功且计数 3；`:108` `retries: 0` → 仅 1 次。参考依据：`rubygems_integration.rb:379-407` 的 `download_gem` 用 `Bundler::Retry.new("download gem from …")`（无 exceptions），`retry.rb:55` 对任意 `StandardError` 重试，`remote_fetcher.rb:237` 把 404 转 `FetchError`；而 spec/API 路径 `fetcher.rb:159/173` 传 `FAIL_ERRORS`（`:101-125`，含 `HTTPNotFound`、`FallbackError`），404/502 立即失败。故本产品 `Downloader` 的重试行为与参考的 gem 下载路径一致，原「已知偏差」撤回，改为「与参考一致（按路径分层）」。`ssl_verify_mode` 三态在 `127.0.0.1`（证书 SAN 含 `IP:127.0.0.1`）实测：`none` 成功、默认 peer 拒绝自签（`OpenSSL::SSL::Error`）、仅配 `ssl_ca_cert` 成功——证明配置真实生效而非恒不校验。

## 2026-11-15 M7(8) 第五子项：两条产品差异的 differential 固化

**参考语义**：`lockfile_spec.rb:1154-1181`（path 源绝对路径 → `remote: foo`）与 `lockfile_spec.rb:2088-2142`（锁定 spec 缺依赖边 → 补齐且不改版本）。

**新增夹具**

- `fixtures/differential/lock-path-absolute-relative/`：`Gemfile` 用 `path File.expand_path("foo", __dir__)`，命令 `lock`，`file-contains` 断言 `remote: foo` 与 `    foo (1.0)`。实测 **4.0.24 PASS、2.7.2 PASS**；负对照（PATH 分组键回退为原始绝对 remote）输出 `FAIL lock-path-absolute-relative (lock)` + `file-contains differs (Gemfile.lock): needle=remote: foo`，恢复后 PASS。
- `fixtures/differential/lock-missing-dependency-edges/`：独立索引 `fixtures/gem-index-locked-deps/`（由临时脚本用 `gem build` 产物生成，versions 的 md5 等于对应 `info/<gem>` 内容 md5），预置缺依赖子行的 `Gemfile.lock`，命令 `install`，`file-contains` 断言两条版本行与 `      net-protocol` 子行。

**实测结果（B）**：两侧 `Gemfile.lock` 逐字相同（含 `      net-protocol` 子行、版本 0.2.2/0.5.0、未选 0.5.1），exit code 相同，`file-contains` 全过；仅 stdout 不同：参考在修复锁文件时打印两次 `Resolving dependencies...`（一次来自正常解析、一次来自重新解析），celerite 复用路径静默。B 曾以 `deferred-4.0.24` / `deferred-2.7.2` 标记为 documented deferral（原因行写明 stdout-only 差异），不作为通过项；**2026-11-15（第六子项）已修复并转双 profile PASS，见下节**。负对照（`refresh_locked_dependencies` 直接 return）输出 `FAIL` + `file-contains differs (Gemfile.lock): needle=      net-protocol`，证明夹具能捕获该缺陷。

### 2026-11-15 M7(8) 第六子项：锁文件修复路径的 `Resolving dependencies...` 输出顺序对齐

**参考语义**：`bundler-4.0.24/lib/bundler/resolver.rb:34` 每次 `Resolver#start` 都打印一行 `Resolving dependencies...`（`Bundler.ui.info …, true`）。在「锁文件缺少依赖边需要修复」这条路径上参考发生两次解析，因此先打印两行，再打印 `Fetching <gem>`；`2.7.2` 的行为差异是它的修复按单个 gem 进行、每个 gem 的 `Fetching` 与 `Installing` 成对相邻（4.0.24 则是先全部 `Fetching` 再全部 `Installing`）。

**实现**：`src/celerite/cli/commands_install.cr` 把 `Fetching`/`Installing` 行落成内存事件而不是立即写 stdout，只有 `Resolution#refresh_locked_dependencies`（签名改为返回 `Bool`，`resolution.cr:705-706`，true 表示确实改写了某条依赖边）判定为真时，才在 source-index 行之后、第一条 `Fetching` 之前刷出两行 `Resolving dependencies...`；`2.7` profile 在此路径按 `pending` 顺序把每个 gem 的 `Fetching`/`Installing` 成对刷出，其余路径（fresh resolve、`no_reuse`、`--no-lock`、无修复的复用）输出与顺序不变。**决策不由启发式猜测**（不是「锁文件里某 spec 没有依赖边」），而是真实 gemspec 比较的结果。

**证据**：删除两个 `deferred-*` 后 `lock-missing-dependency-edges` 在 4.0.24 与 2.7.2 都 `PASS (exit=0)`；改动前同一夹具实测 `0 passed, 1 failed`（stdout 差 `5a3 > Fetching source index from …` 起的两行缺失），改动后首辅独立复跑双 profile `1 passed, 0 failed`。定向回归 `install-fresh`/`install-check`/`exec-loader`/`add-git`/`add-ref`/`ruby-metadata-remote-fallback`/`ruby-metadata-fail`/`clean-unused` → `8 passed, 0 failed`；全量 4.0.24 `129 passed, 13 failed, 1 skipped`（129 = 124 基线 + 段 D/E 新增 4 + 本夹具；13 失败与基线同名同数，逐块证据均为 msys `0xC0000022` 环境）；2.7.2 全量 `129 passed, 12 failed, 2 skipped`（失败为 4.0.24 名单去掉 `add-group`）。

**未验证**：真实 `bundle install` e2e；`--verbose`/`--no-lock` 等分支下同一修复路径的输出；`force_install` 与修复同时发生时的顺序；非 Windows 平台的折行/ANSI 差异。


**装具改动**：`script/differential` 增加 `@LOCKED_DEPS_INDEX_DIR@` 占位替换，并允许 `CELERITE_DIFF_WORK_ROOT` 指定沙箱根目录（默认 `/tmp`）。

**全量差分（4.0.24）**：本次运行 `77 passed, 59 failed, 2 skipped` EXIT 1，与 2026-11-14 N1 记录的 `135 passed, 0 passed, 1 skipped` 明显冲突（示例失败：`install-fresh` 的 `installed tree differs: ruby/4.0.0/bin/thor.bat content differs after normalization`）。该差异集中于 install 类夹具，疑与本次把沙箱根迁到工作区内（`CELERITE_DIFF_WORK_ROOT`）后的路径/环境有关，**未定位，未验证**；不能据此认定产品回归，也不能宣称失败集 ⊆ 先前名单。需在干净环境按原命令（`CELERITE_BIN=... TMPDIR=/c/temp bash script/differential`）复跑后重新判定。

**2026-11-15 装具修复后基线（取代上文“未定位”记录）**：`script/differential` 默认沙箱根改为仓库内 `$repo_root/.d`（`CELERITE_DIFF_WORK_ROOT` 可覆盖；`.gitignore` 含 `.d/` 与 `.difftmp/`）；`script/differential-installed-tree` 改为落盘后 `cmp`，修掉 Ruby-msys `diff` 不支持 `/dev/fd` 导致的 `thor.bat` CRLF/LF 误报；两侧沙箱目录改为等长 `ref`/`cel`，消除折行点错位；两处 env 增加 `TMP`/`TEMP`/`TMPDIR` 指向沙箱内。复验：`install-fresh` 由 FAIL 转 PASS；`lock-path-absolute-relative` 双 profile PASS；`lock-missing-dependency-edges` 仍 SKIP（stdout-only，锁文件逐字相同）。
**多命令输出覆写（本次确认的根因，已修）**：MSYS 下同一文件第二次以 `>>` 复开时写偏移回到 0，第二命令的输出从文件头覆写第一命令的输出；`install-check` 的 `ref.out` 因此以 check 的 40 字节行开头、后接 install 被截断的残段（两侧 LF/CRLF 差一字节时残段相差一个 `r`）。`script/differential` 改为每命令独立文件（`$work/ref.part.$n.out` / `.err`、`$work/cel.part.$n.out` / `.err`），结束时**单次** `cat "${ref_parts[@]}" > "$work/ref.out"` 拼接（目标只打开一次；逐次 `cat >>` 仍会复现覆写）。复验 5 夹具全部 PASS：`install-check`、`ruby-api`、`outdated-list`、`plugin-install`、`cache`（`differential (4.0.24): 5 passed, 0 failed, 0 skipped`）。

**全量基线（138 fixtures，EXIT 1）**：4.0.24 `121 passed, 15 failed, 2 skipped`；2.7.2 `119 passed, 16 failed, 3 skipped`（日志 `.d-full-4024b.log`、`.d-full-272b.log`。**2026-11-15 装具 `git-init` 修复后** 4.0.24 重跑为 `124 passed, 13 failed, 2 skipped`：`add-git`/`add-ref` 转 PASS，剩余 13 例全为环境——5 例 git 子进程 `0xC0000022` + 8 例 native `0xC0000022`；2.7.2 只重跑了 7 例 git 夹具（`2 passed, 5 failed`），全量未重跑，见文末「2026-11-15 M7(8) 装具 git-init 暂存路径」节）。http-index 夹具依赖 `node` 在 bash PATH 上：缺失时这 6 例显式 SKIP（**不是通过**），可用 `CELERITE_DIFF_EXTRA_PATH="/c/Program Files/nodejs"` 补齐；首辅以该方式复跑 6 例全 PASS（退出码 0/15/0/1/1/7）。上表 `121 passed, 15 failed, 2 skipped` 是在 node 可用前提下测得；node 缺失时为 `115 passed, 15 failed, 8 skipped`（同一批 15 例；本机以单例 `cooldown` 复核 node 缺失确会打印 `SKIP … (http-index server did not answer … within 10s)` 而非 PASS）。
**失败分类（4.0.24，15 例）**：①git 源夹具的装具缺陷（**已修，2026-11-15**）：7 例（`add-git`/`add-ref`/`git-installed-discovery`/`git-path-install`/`git-pristine`/`plugin-git-local`/`plugin-git-local2`）此前报 `fatal: repository './gitgem' does not exist`；真因是装具 `git-init` 用 `mktemp -d` 的 POSIX 路径调用 `git -C`，Git for Windows 与 msys `cp` 解析不同根，`.git` 落到别处。修复：暂存目录改为 `mktemp -d "$work/gitstage.XXXXXX"`，并用 `cygpath -w` 得到 Windows 路径传给 `git -C`（`cp`/`test` 仍用 POSIX 形式）。修复后 `add-git`/`add-ref` 双 profile PASS；剩余 5 例转为环境限制——celerite 子进程 `sh.exe: *** fatal error - NtCreateDirectoryObject(...): 0xC0000022`（与 native 构建同源；参考侧由 bash 直连 git 不受限），非产品差异；②本机 native 构建限制 8 例（`add-group`/`add-optimistic`/`add-remove`/`add-version`/`cache-all-platforms`/`native-ext`/`native-ext-target`/`plugin-source-ok`）——`extension build failed for racc-1.8.1` 与 `cp.exe: *** fatal error - NtCreateDirectoryObject(...): 0xC0000022`，同命令经 bash→ruby→make 正常、经 celerite→bridge→make 失败；`add-remove` 的差异行 `racc (~> 1.8) was removed.` vs `racc was removed.` 同源于此。
**失败分类（2.7.2，16 例）**：同上 7+8；另 2 例仅 2.7.2 出现的差异——`clean-force`/`clean-unused` 中 celerite 多打印 `Removing json_pure (2.8.1)`/`Removing thor (1.3.2)`。（**2026-11-15 订正**：该差异已定性为**产品的错误补偿**而非参考行为——参考 2.7.2 与 4.0.24 均按当前锁文件保留，`clean`/`clean --force` 的删除范围与参考一致；profile 特例已删除，双 profile 定向差分为 2/0/0，见文末「2026-11-15 clean：撤销 2.7.2 profile 特例」节。）
**产品差异夹具的差分状态**：`lock-path-absolute-relative` 双 profile PASS；`lock-missing-dependency-edges` **2026-11-15（第六子项）起双 profile PASS**（此前为 documented SKIP，仅参考多打印两次 `Resolving dependencies...`，现已对齐；`deferred-4.0.24`/`deferred-2.7.2` 已删除），**SKIP 不是 PASS**。
**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；全量 `crystal spec` 309 examples 1 failure（仅 `spec/config_spec.cr:97` 既存机器级污染）。

**已撤回的论断**：「沙箱路径长度不是主因、根因在产品 `word_wrap`、58 失败 ≈ 52 例折行缺陷」这一版结论已撤回——折行差异是多命令输出覆写造成的假象（第二命令覆写第一命令后，两侧残段因 LF/CRLF 差一字节而错位，去换行比较自然多出 1 个字符），`Commands.word_wrap` 未修改；装具侧保留短沙箱根、`/dev/fd` 归一化修复与等长沙箱名 `ref`/`cel`。
**未验证**：干净非沙箱环境下 native 构建（`0xC0000022`）是否恢复；git 源 5 例在干净环境下是否随子进程限制解除而 PASS（`add-git`/`add-ref` 已由装具 git-init 修复转 PASS）；2.7.2 第三个 skipped 的来源；`clean`/`clean --force` 删除范围与参考的差异未修（**2026-11-15 已撤销 2.7 特例，见 `30a9888`**）；B 的 stdout 对齐已于 2026-11-15（第六子项）修复。

**网络不可达的 friendly error 与退出码（2026-11-15 已修，M7(4) 第五子项）**：参考（4.0.24）在连接失败时输出 `Could not reach host 127.0.0.1:8765. Check your network connection and try again.` 并以 **17** 退出；修复前 celerite 先打印 `Fetching gem metadata from http://127.0.0.1:8765/.`，再输出 `celerite internal error: Error connecting to '127.0.0.1:8765': 由于目标计算机积极拒绝，无法连接。`，退出码 **1**。参考锚点：`bundler/fetcher/downloader.rb:102` 抛 `NetworkDownError`；`bundler/fetcher.rb:18` `NetworkDownError < HTTPError`；`bundler/errors.rb:37-38` `HTTPError` 的 `status_code(17)`。修复：`src/celerite/errors.cr` 新增 `NetworkDownError`（status 17、`wrap? true`、`socket_error` 保留原始异常、`message_for` 取 host 与显式端口）；`src/celerite/http_transport.cr` 仅在**连接建立阶段**把 `Socket::Error` 转成该错误（直连 `client.get`、代理 `TCPSocket.new`），读超时语义不变，TLS 证书失败当时仍走既有 `Celerite internal error`（该差异已于本轮之后的『2026-11-15 M7(4) 证书校验失败：CertificateFailureError』节修复）；`download_to` 的 `request_path`/redirect 逻辑未受影响。同时补齐差分暴露的第二处差异：`Fetching gem metadata from <remote>.` 只在抓取真正开始后才打印，且跟随 `Resolution#progress` 的目标流（`lock`/`install` 走 stdout，`lock --print` 走 stderr），连接失败时不打印任何进度行（`resolution.cr` 的 `log_fetch_for` 移入 `client.info(name)` 之后）。证据：`spec/m7_network_down_spec.cr` 用 bind-then-close 端口断言 exit 17、stdout 为空、stderr 逐字等于参考句、无 `celerite internal error`（修复前 `Expected: 17 got: 1`；负对照把转换改回 `raise ex` 后同样 `Expected: 17 got: 1`，手工二进制实测 `NEG_EXIT=1` + `celerite internal error: Error connecting to '127.0.0.1:9': 由于目标计算机积极拒绝，无法连接。`）；差分夹具 `fixtures/differential/network-unreachable/`（`source "http://127.0.0.1:9/"` + `gem "thor"`，`install`）**PASS（exit=17）**。**未验证**：DNS 解析失败（`EHOSTUNREACH`/无地址）路径未做差分；代理连接失败只经单元路径未单独夹具；读超时与 TLS 失败的参考措辞未对齐（不在本子项范围）。

## 2026-11-15 M7(4) 证书校验失败：CertificateFailureError（对齐 bundler 4.0.24）

参考：`bundler/fetcher.rb:25-34` 定义 `CertificateFailureError < HTTPError`（status 17，`wrap? true`；消息为 URI、换行、三段解释与链接）；`bundler/fetcher/downloader.rb:94-95` 在 `OpenSSL::SSL::SSLError` 上转换为该错误；`bundler/errors.rb:34-37` 的 `HTTPError` 退出码 17；`bundler/friendly_errors.rb:31-36` 以 `wrap: true` 打印。

修复前（本产品）：`celerite internal error: SSL_connect: error:0A000086:SSL routines::certificate verify failed`，退出码 1（负对照实测：`.d-neg-cert.exe` + 本地 TLS 4477 端口，`NEG_EXIT=1`）。

修复后：`src/celerite/errors.cr:145-186` 新增 `CertificateFailureError`（status 17、`wrap? true`、消息逐字、`display_uri` 去掉 userinfo 避免泄露凭据）；`src/celerite/http_transport.cr` 的 `direct_get` 与 `proxied_get`（含 CONNECT 隧道内握手）在 `OpenSSL::SSL::Error` 上调用 `translate_tls_failure`，仅 `message.includes?("certificate verify failed")` 时转换，其他 TLS 错误原样抛出，原始异常保存在 `ssl_error` 字段。

证据：
- `spec/m7_certificate_failure_spec.cr` 3 examples、0 failures：CLI 退出 17 + 参考原文（按 80 列折行归一比较）、`ssl_verify_mode: none` 成功、`ssl_ca_cert: fixtures/tls/ca.pem` 成功。
- `spec/m7_transport_evidence_spec.cr` 的「peer verification」用例断言更新为 `Celerite::CertificateFailureError`。
- 差分夹具 `fixtures/differential/network-unreachable`（HTTP 不可达）仍 PASS（exit=17）；本轮未新增 TLS 差分夹具（参考输出含随机端口，以 spec 覆盖）。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；全量 `crystal spec` **313 examples, 1 failures**（唯一既存 `spec/config_spec.cr:113`，机器级 `~/.bundle/config` 污染）；`bash script/differential network-unreachable` PASS（exit=17）。

未修差异（本次未实现）：
- 进度行：参考在失败前先打印 `Fetching source index from https://127.0.0.1:4443/`（首辅实测 stdout 首行，50 字符），本产品在证书失败时不打印该行（进度行只在抓取开始后输出）。
- 重试行：参考打印 `Retrying fetcher due to error (2/4): Bundler::Fetcher::CertificateFailureError Could not verify the SSL certificate for https://127.0.0.1:4443/.`（`bundler/retry.rb:61`），本产品不重试、一次即失败。

首辅实测参考输出（前两行，`[n]` 为行字符数）：
```
[50] Fetching source index from https://127.0.0.1:4443/
[1] Retrying fetcher due to error (2/4): Bundler::Fetcher::CertificateFailureError Could not verify the SSL certificate for https://127.0.0.1:4443/.
```
两侧最终错误块逐字一致：`Could not verify the SSL certificate for …`、`There is a chance you are experiencing a man-in-the-middle attack, but most` / `likely your system doesn't have the CA certificates needed for verification. For` / `information about OpenSSL certificates, see` / `https://railsapps.github.io/openssl-certificate-verify-failed.html.`，exit 17。

未验证：真实公网证书链（自签/私有 CA 以外）、客户端证书与服务端校验同时失败的组合、2.7.2 下的输出差异、非 OpenSSL 后端（Windows schannel 等）。

## 2026-11-15 clean：撤销 2.7.2 profile 特例

**结论**：参考 bundler 2.7.2 与 4.0.24 的 `clean`/`clean --force` 行为一致——保留当前锁文件列出的 gems（`keep = lockfile.specs`）。此前「2.7.x 清空保留集」的结论是**装具缺陷期的误判**，已撤销并删除对应代码。

**误判来源**：装具在 MSYS 下对同一输出文件第二次 `>>` 复开时写偏移归零，后一命令的输出从文件头覆写前一命令的输出，导致参考侧 `Removing ...` 行丢失。当时（commit `8d20c17`）据此给 `clean` 加了 2.7.x profile 特例（空 keep set、不保留 locked git checkout），并把结论写入文档。

**复核方式（修好装具后）**：`KEEP_DIFFERENTIAL=1 BUNDLER_REF_VERSION=2.7.2 bash script/differential clean-unused`（及 `clean-force`）保留沙箱，读取参考侧 `$work/ref.out`：`clean-unused` 仅打印 `Removing thor (1.3.2)`（`json_pure` 仍在 Gemfile，保留）；`clean-force` 零条 `Removing`（两个 gem 都在 Gemfile）。与 4.0.24 结果一致。

**修复**：`src/celerite/cli/commands_install.cr` 的 `Commands.clean` 删除 `profile` 局部变量与两处 2.7.x 特例——`keep_names` 恒为 `lockfile.specs.map(&.full_name).to_set`；`checkout_keep` 恒由锁文件 GIT section 派生。注释同步改写为「参考 2.7.2/4.0.24 均按当前锁文件保留；早先的特例源于装具缺陷，已撤销（2026-11-15）」。

**spec**：新增 `spec/m7_clean_spec.cr`（离线 file:// 源、`with_project` + 桥 + 隔离 `HOME`/`USERPROFILE`），4 examples：
- A `install` → `remove thor` → `clean`：仅 `Removing thor (1.3.2)`，stdout 不含 `json_pure`；`thor-1.3.2` 目录删除、`json_pure-2.8.1` 目录与 `specifications/json_pure-2.8.1.gemspec` 保留；
- B `clean --force`：stdout 无 `Removing`，两个 gem 目录都在；
- C `clean --dry-run`：打印 `Would have removed thor (1.3.2)`，thor 目录未删；
- D 连续两次 `clean`：第二次不再打印 `Removing`，退出码 0。
- 修复前（旧 profile 逻辑，以 `CELERITE_PROFILE_BUNDLER_VERSION=2.7.2` 驱动）：`4 examples, 2 failures`，`out.should_not contain("json_pure")` 实得 `"Removing json_pure (2.8.1)\nRemoving thor (1.3.2)"`、`out.should_not contain("Removing")` 同；修复后默认 profile 与 2.7.2 profile 均 `4 examples, 0 failures`。

**差分**：
- 定向：4.0.24 `PASS clean-force (exit=0)`、`PASS clean-unused (exit=0)` → `2 passed, 0 failed, 0 skipped`；2.7.2 同 `2 passed, 0 failed, 0 skipped`。
- 全量：4.0.24 **`122 passed, 15 failed, 2 skipped`**；2.7.2 **`122 passed, 14 failed, 3 skipped`**。2.7.2 相对基线 `119/16/3` 为 **+3 passed / -2 failed**（`clean-force`/`clean-unused` 转 PASS，`add-group` 仍为 documented SKIP），**2.7.2-only 失败集合为空**。剩余失败均为既有分类：7 例 `--git=./gitgem` 相对路径（夹具/环境，参考 exit 11 `fatal: repository './gitgem' does not exist`）、8 例 native 构建 `0xC0000022`（环境）；4.0.24 的 `add-group` 为 network/harness deferral（2.7.2 侧 SKIP）。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0；全量 `crystal spec` **317 examples, 1 failures**（唯一既存 `spec/config_spec.cr:113`，机器级 `~/.bundle/config` 污染）；`git diff --check` EXIT 0。

**未验证**：参考侧在真实 `BUNDLE_PATH`/system-gems 模式下的 `clean` 行为、`--force` 与 git checkout 清空组合、以及 `8d20c17` 之前写下的历史条目（本文 L262/L318/L319/L381/L409 等旧记录保留原样，仅由本节统一订正）。

## 2026-11-15 M7(8) 装具 git-init 暂存路径缺陷（已修）

`fixtures/differential/*/git-init` 的 7 例此前失败（`add-git`、`add-ref`、`git-installed-discovery`、`git-path-install`、`git-pristine`、`plugin-git-local`、`plugin-git-local2`），参考侧报 `fatal: repository './gitgem' does not exist` 并以 11 退出。

**根因（已证实部分）**：`script/differential` 的 git-init 段用 `staging="$(mktemp -d)"` 生成 POSIX 形式的 `/tmp/tmp.XXXX`，再交给 `git -C`；此时 `cp -r "$staging/$rel" …` 复制进 project 的目录不是仓库（首辅保留沙箱复核：`ref/project/gitgem/.git` 不存在），参考随之报 `repository './gitgem' does not exist`。
**未证实部分**：具体机制（Git for Windows 对 POSIX `/tmp` 的根解析与 msys `cp` 不同）未能在隔离环境中复现——用旧的两条语句独立重放时 `git -C /tmp/… init/add/commit` 正常产出了 `.git`，故该机制仅为最有可能的解释，未当作已证结论。可复现的是：把这两条语句改回旧形式会重新触发上述失败（本轮负对照，`grep` 见下），改回修复形式即 PASS。

**修复**：暂存目录改为工作区内 `staging="$(mktemp -d "$work/gitstage.XXXXXX")"`，新增 `staging_win="$(cygpath -w "$staging")"`，三处 `git -C`（`init`/`add`/`commit`）改用 `"$staging_win/$rel"`；`cp -r`、`test -d` 继续用 POSIX 路径，注释写明根因与两侧路径语义。

**实测**：
- `KEEP_DIFFERENTIAL=1 bash script/differential add-git` 后 `ref/project/gitgem/.git` 存在，`PASS add-git (exit=0)`。
- 7 例定向 4.0.24：`PASS add-git`、`PASS add-ref`，其余 5 例 `FAIL`，汇总 `differential (4.0.24): 2 passed, 5 failed, 0 skipped`；2.7.2 同（`differential (2.7.2): 2 passed, 5 failed, 0 skipped`）。
- 全量 4.0.24：`differential (4.0.24): 124 passed, 13 failed, 2 skipped (documented deferrals)`（修复前 122/15/2）；13 例 = 5 例 git 子进程 `0xC0000022` + 8 例 native `0xC0000022`。

**剩余 5 例分类：环境（非产品）**。失败形态为 celerite 子进程：
`git command failed: git clone --mirror ./gitgem <cache> … 0 [main] sh.exe: *** fatal error - NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-…): 0xC0000022`。
对照探针（同项目目录、`TMP`/`HOME` 与装具一致，bash 直连）：`git clone --mirror <repo> <dir>` 连跑 3 次均 `CLONE1=0 CLONE2=0 CLONE3=0`。同一命令经 bash 成功、经 celerite 后代失败，属本机沙箱拒绝子进程创建 msys Cygwin 共享内存（与 native 构建 `0xC0000022` 同类）；未改产品代码绕过。

**首辅独立复跑（2026-11-15，同一 `bin/celerite.exe`）**：
- 负对照：把 `staging="$(mktemp -d "$work/gitstage.XXXXXX")"` / `staging_win="$(cygpath -w "$staging")"` 临时改回旧形式 → `FAIL add-git` / `file-contains differs (Gemfile): needle=gem "gitgem", "~> 0.2.0", git: "./gitgem", branch: "master"` / `differential (4.0.24): 0 passed, 1 failed`；改回修复形式 → `PASS add-git`。**证明该修复是载荷性的（不是无害的顺手改动）**。
- 7 例定向：4.0.24 `2 passed, 5 failed`；2.7.2 `2 passed, 0 failed`（`add-git`/`add-ref` 均 PASS）。
- 门禁（需在环境变量上把 HOME/TEMP 落到工作区内，见下）：`crystal tool format --check src spec` EXIT 0、`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅 2 条既存 `File.executable?` deprecation）、`git diff --check` EXIT 0。
- **本机门禁的新环境前提（重要）**：当前进程沙箱拒绝把 `~/.bundle/cache` 与 `%TEMP%` 写入（默认环境下全量 spec 出现 `Unable to create directory: '…AppData\Local\Temp\celerite-spec-…': 拒绝访问` 与 `Error opening file with mode 'wb': 'C:\Users\ShiningRay\.bundle\cache\compact_index\…'`，共 149 errors）。把 `HOME`/`USERPROFILE`/`TEMP`/`TMP`/`TMPDIR` 指向工作区内目录后可得 **`317 examples, 1 failures, 4 errors`**：失败项为 `spec/cli_spec.cr:288`（`Expected: 0 got: 17`，隔离 HOME 下确定性复现），4 errors 为 GitSource 系列的 `0xC0000022`；`spec/config_spec.cr` 的既存失败在隔离 HOME 下**消失**（证实其为机器级 `~/.bundle/config` 污染）。这些变化均由环境解释，本轮未改产品代码。

**未验证**：git-init 路径机制的精确成因（仅证实「旧形式失败、新形式 PASS」）；干净非沙箱环境（celerite 子进程限制解除）下这 5 例是否 PASS；2.7.2 全量未重跑（仅 7 例定向）；Git tag/submodule/glob 仍未覆盖；`spec/cli_spec.cr:288` 在隔离 HOME 下失败的原因未定位（与本轮改动无关，本轮到目前只改装具与文档）。

## 2026-11-15 M7(8) spec 自包含化：lock platform 往返用例改用离线索引

`spec/cli_spec.cr` 的「lock manages platforms natively (remove then re-add is a no-op change)」原先用 `source "https://rubygems.org"` 并预置 `Gemfile.lock`；`lock --remove-platform` 会触发真实解析，只有默认 HOME 下 `~/.bundle/cache/compact_index` 热缓存存在时才通过。隔离 HOME/TEMP 实测 `crystal spec spec/cli_spec.cr:288` 得 `Expected: 0 got: 17`（NetworkDownError），`spec/cli_spec.cr` 整体 `24 examples, 1 failures`——该例依赖机器状态，不是自包含用例。

**修复（仅 spec，未改产品代码）**：source 改为 `file_source_url(File.expand_path(File.join(__DIR__, "..", "fixtures", "gem-index")))`，Gemfile 为 `gem "json_pure", ">= 2.0"`，不预置锁文件；流程改为三步断言：①`lock` exit 0 并存 baseline；②`lock --remove-platform <local>` exit 0，锁文件不含该平台且 GEM 段 `remote:` 仍为本地 URL；③`lock --add-platform <local>` exit 0，锁文件逐字节等于 baseline。

**证据（隔离 `HOME`/`USERPROFILE`/`TEMP`/`CRYSTAL_CACHE_DIR` 于 `.tmp-scratch`）**：修复前 `crystal spec spec/cli_spec.cr:288` = `1 examples, 1 failures`（`Expected: 0 got: 17`）；修复后 `crystal spec spec/cli_spec.cr` = `24 examples, 0 failures, 0 errors, 0 pending`；全量 `crystal spec` = `317 examples, 0 failures, 4 errors, 0 pending`（4 errors 为既有 `Celerite::GitSource` 系列 msys shm `0xC0000022` 环境限制，非本改动）；`crystal tool format --check src spec` EXIT 0；`git diff --check` EXIT 0。

**未验证**：同一往返在真实 rubygems.org 可达环境下的行为（本用例已不依赖网络）；`lock --remove-platform` 对多平台/平台变体锁文件的等价性未单独差分。

## 2026-11-15 M7(1) 约束矩阵审计：远程 compact index 负例 + 根级解释文案纠正

本节把 M7(1)（当前 Ruby / RubyGems / Gemfile 目标 Ruby / engine / patchlevel / ABI 的约束过滤）从「有实现、无系统证据」推进到「逐机制有正反例、双 profile 实测」，并修掉审计中暴露的一处**事实错误文案**。

### 1. 审计结论（六机制）

| 机制 | 正例 | 负例 | 证据锚点 |
| --- | --- | --- | --- |
| gem 元数据 `required_ruby_version` | `ruby-metadata-match`、`ruby-metadata-exact-match`、`ruby-metadata-boundary-match`（exit 0） | `ruby-metadata-fail`、`ruby-metadata-boundary-fail`（exit 6）；本轮新增远程索引形态 `ruby-metadata-remote-fail`（exit 6） | `src/celerite/resolver/source.cr` `ruby_requirement_satisfied?`（L283-287）、`raise_metadata_or_not_found!`（L420-470）；`spec/m7_resolver_ruby_constraints_spec.cr` |
| gem 元数据 `required_rubygems_version` | `rubygems-metadata-match`、`rubygems-metadata-boundary-match`（`>= 4.0.16` 边界相等）、`rubygems-metadata-pessimistic-match` | `rubygems-metadata-fail`、`rubygems-metadata-boundary-fail`（`>= 4.0.17`）、`rubygems-metadata-remote-fail` | 同上；比较基准为 bridge 报告的 RubyGems 版本（`resolution.cr` 传入 `env.rubygems_version`） |
| Gemfile 目标 `ruby` 版本 | `ruby-target-match`（install + check，exit 0） | `ruby-version-mismatch`（exit 18） | `spec/m7_ruby_runtime_spec.cr` + `Celerite::RubyRuntime` |
| Gemfile 目标 `patchlevel` | `ruby-patchlevel-match`、`ruby-engine-patchlevel-match` | `ruby-patchlevel-mismatch`（exit 18） | 同上 |
| Gemfile 目标 `engine` / `engine_version` | `ruby-engine-match`、`ruby-engine-patchlevel-match` | `ruby-engine-mismatch`、`ruby-engine-version-mismatch`（exit 18） | 同上（gem 元数据无 engine 字段，仅 Gemfile 目标参与） |
| 平台变体 | `multi-platform-lock`、`multi-platform-install`、`platform-variant-match` | `platform-variant-fail`（`lock --add-platform x86_64-linux` + `nokogiri`，双方 exit 7：`Could not find gems matching 'nokogiri' valid for all resolution platforms (x64-mingw-ucrt, x86_64-linux)`） | `source.cr` `installable?`/`platform` 过滤；`spec/m7_platform_spec.cr` |
| ABI | 仅单元证据 | 无差分夹具 | `spec/m7_platform_spec.cr`（bridge 不可用时输出「未校验」而非满足） |

约束矩阵夹具集合（33 例）在双 profile 下实测：`differential (4.0.24): 33 passed, 0 failed, 0 skipped`、`differential (2.7.2): 33 passed, 0 failed, 0 skipped`。

### 2. 死代码清理

`src/celerite/resolver/source.cr` 中 `running_ruby_version_for_gem`（原 L289-294）全仓无调用，其注释把「gem 元数据匹配」讲成另一条路径，易误读为 patchlevel 参与匹配。已删除，并把语义注释移到 `running_ruby_version` 上方：gem 元数据匹配用 `ruby_environment.ruby_version`（无 patchlevel），patchlevel 只参与 Gemfile 目标校验（`Celerite::RubyRuntime`）。`ruby_requirement_satisfied?` 未改动。

### 3. 远程 compact index 负例（新增索引与 4 个夹具）

此前所有元数据负例都用 **path 源**（`extra/vendor/future_gem/*.gemspec`），远程 compact index 的过滤路径没有负例。本轮新增 `fixtures/gem-index-ruby-constraints/`：

- `versions`：`future_gem 0.9.0,1.0.0`（md5 `8fd738f0…`）、`rubygems_gem 0.9.0,1.0.0`（md5 `6d79be07…`），md5 与 `fixtures/gem-index` 同算法（info 文件字节 MD5）；
- `info/future_gem`：`0.9.0 …ruby:>= 1.0` / `1.0.0 …ruby:>= 99.0`；`info/rubygems_gem`：`0.9.0 …rubygems:>= 0` / `1.0.0 …rubygems:>= 99.0`；
- checksum 为 32 零字节占位（该索引**只服务 `lock`**：没有 `.gem`、`quick/` 与 legacy `specs.4.8*`，故 `install`/`check` 不可用）。

`script/differential` 新增占位 `@RUBY_CONSTRAINTS_INDEX_DIR@`（替换 5 处）与 `ruby_constraints_index_dir`；`http-index` 标记现在支持首行指定索引目录。4 个夹具（`ruby-metadata-remote-fallback`、`ruby-metadata-remote-fail`、`rubygems-metadata-remote-fallback`、`rubygems-metadata-remote-fail`）改用 `http://127.0.0.1:8765/` + `http-index`，而不是 `file://`——**因为参考对 `file://` 源不使用 compact index，会回退到 legacy `specs.4.8.gz` 并实测 ENOENT**（这也是本机唯一可行的远程索引路径：无外网）。

### 4. 修复：根级依赖被元数据排除时的解释文案

修复前（`bin/celerite.exe` 对 `gem "future_gem", "1.0.0"`，远程索引）：

    Because every version of future_gem depends on Ruby >= 99.0

参考（4.0.24）为：

    Because future_gem >= 1.0.0 depends on Ruby >= 99.0

即我方文案**在事实层面是错的**：`0.9.0` 只需要 Ruby >= 1.0，并非「每个版本」都要求 Ruby >= 99.0。修复在 `raise_metadata_or_not_found!`：

- `spec = excluded.min_by(&.version)`、`excluded_min = spec.version`（与打印范围一致）；
- `all_installable` = 该 gem 全部「平台可安装」候选（**不做 requirement 过滤**，否则 pinned 场景会误判为「全部被排除」）；
- `subject` 三分支：①全部候选被排除 → `every version of <name>`（path 夹具形态，参考同样如此，保留）；②`>= excluded_min` 的候选数恰等于 `excluded.size`（连续后缀）→ `<name> >= <min>`；③其余 → `<name> = <min>`（保守回退，注释已标明）；
- 消息首行改为 `Because #{subject} depends on …`，其余四行逐字未动，`exit 6` 语义未动。

新增 2 个单元例（`spec/m7_resolver_ruby_constraints_spec.cr`，覆盖分支 ②/③），并把 `ruby-metadata-remote-fail`/`rubygems-metadata-remote-fail` 的 `deferred-*` 标记删除——两者现在是**逐字节 PASS**（差分比较 stdout/stderr/exit），即参考文案确实为 `future_gem >= 1.0.0`。

### 5. 门禁与差分

- `crystal tool format --check src spec` → EXIT 0
- `crystal build --no-codegen --link-flags <shim> src/cli.cr` → EXIT 0（仅 2 条既有 `File.executable?` deprecation，`commands_install.cr:612,676`）
- 全量 `crystal spec --link-flags <shim>` → `319 examples, 0 failures, 4 errors, 0 pending`（4 errors 为既有 `Celerite::GitSource` msys shm `0xC0000022` 环境错误）
- `git diff --check` → EXIT 0；`bash -n script/differential` → EXIT 0
- 差分：14 个约束夹具双 profile `14 passed, 0 failed, 0 skipped`（首辅复跑子集 `ruby-metadata-fail`/`ruby-metadata-remote-fallback`/`ruby-metadata-remote-fail`/`rubygems-metadata-remote-fail`/`ruby-metadata-boundary-fail` → `5 passed, 0 failed`，2.7.2 两个 remote-fail → `2 passed, 0 failed`）

一次观察（如实记录）：首辅的一次全量 spec 出现 `319 examples, 1 failures, 4 errors`，失败为 `spec/m7_build_args_spec.cr:97`（build.<gem> 参数未到达 extconf）。该例单跑 `5 examples, 0 failures`，紧随其后的全量复跑恢复 `319 examples, 0 failures, 4 errors`，与既有的 msys shm/进程类环境失败同源，判为环境抖动而非产品回归。

### 6. 未验证 / 边界

1. 分支 ③（非连续排除）的参考逐字形态未实测——现有索引里没有「只有中间版本被排除」的样本，我方采用保守回退 `<name> = <min>`。
2. `fixtures/gem-index-ruby-constraints` 的 checksum 是占位零值；该索引不能用于 `install`/`check`（缺 `.gem`/`quick/`/legacy 索引）。
3. 真实 rubygems.org 未触达（无外网），远程路径只经本地 `http_index_server.js` 验证。
4. ABI 约束仍只有单元证据，无差分夹具。
5. M7(1) 复选框保持未勾选：本节补的是「约束矩阵 + 远程负例 + 文案」，不含 `show`/`info` 重解通知等其他 M7(1) 遗留。
## 2026-11-15 M7(5)：git tag / glob 的差分载体（诚实记录：本机环境阻塞）

M7(5)（Git tag/submodules/glob、多 gemspec、monorepo、私有 source 鉴权、离线安装、磁盘错误与中断清理）此前只有单元证据。本轮为 `tag:` 与 `glob:` 建了**差分载体**并取到参考侧 oracle；但**celerite 侧在本机被已知环境缺陷挡住**，故两项均未验证，不计为通过。

### 1. 装具新增 `git-tag`

`script/differential` 的 `git-init` 段（L215-251）新增可选 `git-tag` 清单（TSV `<rel>\t<tag>`）：在暂存仓库 init/add/commit 之后、`cp -r` 进两侧沙箱之前执行 `git -C "$staging_win/$rel" -c commit.gpgsign=false tag "$tag"`（L234-243）。原因：tag 无法提交进工作树，必须在暂存仓库上打；两侧复制同一份暂存树，因此锁文件里的 `revision` SHA 可比较。

### 2. 新夹具

- `fixtures/differential/git-tag/`：`Gemfile` `source "file:///@INDEX_DIR@"` + `gem "gitgem", git: "./gitgem", tag: "v0.1.0"`，`git-init`=`gitgem`，`git-tag`=`gitgem<TAB>v0.1.0`，`command`=`install`，`file-contains` 断言 `Gemfile.lock` 含 `  tag: v0.1.0`、`    gitgem (`、`  revision: `。
- `fixtures/differential/git-glob/`：`extra/mono/gems/{alpha,beta}/…`，`git-init`=`mono`，`Gemfile` `gem "alpha", git: "./mono", glob: "gems/*/*.gemspec"`，`command`=`install`。

### 3. 参考侧 oracle（实测，可直接用于后续对齐）

`git-tag`（4.0.24）：exit 0，stdout `Fetching ./gitgem` / `Resolving dependencies...` / `Bundle complete! 1 Gemfile dependency, 1 gem now installed.`，锁文件 GIT 段为：

    GIT
      remote: ./gitgem
      revision: <staged sha>
      tag: v0.1.0
      specs:
        gitgem (0.2.0)

`git-glob`（4.0.24，`KEEP_DIFFERENTIAL=1` 留存的 `ref/project/Gemfile.lock`）：exit 0，GIT 段写 `remote: ./mono`、`revision: 04dac1f3c7e266126e0c78dac0c7e106546fab8f`、**`glob: gems/*/*.gemspec`**，`specs:` 只含被请求的 `alpha (0.1.0)`（同仓的 `beta` 未进锁），`DEPENDENCIES` 为 `alpha!`，`CHECKSUMS` 为 `alpha (0.1.0)`（无 sha256，git 源）。

### 4. 阻塞（环境，不是产品差异）

celerite 侧两个夹具都在**克隆阶段**失败，未进入解析路径：

    git command failed: git clone --mirror ./gitgem <sandbox>/bundle/ruby/4.0.0/cache/bundler/git/gitgem-<sha> —
    0 [main] sh (15204) C:\Program Files\Git\usr\bin\sh.exe: *** fatal error
    - NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-1888ae32e00d56aa): 0xC0000022
    fatal: Could not read from remote repository.

同一批次里 `add-git`/`add-ref`（走 `add` 路径）是 PASS，而所有 `install` 路径上的 git 克隆（`git-tag`/`git-glob`/`git-installed-discovery`/`git-path-install`/`git-pristine`/`plugin-git-local`/`plugin-git-local2`）都失败——与本机既有 13 例环境失败同类。装具之外的独立探针（`.tmp-scratch/tagprobe*`，直接跑 `bin/celerite.exe install`，HOME/TEMP 均在仓库内，去掉 harness）复现同一 `0xC0000022`；把 stdout/stderr 改为文件重定向同样复现（排除管道因素）。结论：**与本轮夹具/装具改动无关的环境限制**（msys 共享内存对象被拒），需在无该限制的宿主上复跑才能验证 `tag:`/`glob:` 语义。

### 5. 全量差分（4.0.24，如实计数）

`differential (4.0.24): 129 passed, 15 failed, 1 skipped` —— 13 例为既有环境失败，**新增 2 例为本轮 `git-tag`/`git-glob`（同为环境阻塞）**，`git-submodules` 仍是 documented SKIP（参考侧被 git ≥2.38 的 submodule file-transport 策略挡住：`fatal: transport 'file' not allowed`，bundler 不传 `protocol.file.allow=always`）。

### 6. 未验证 / 下一步

1. celerite 的 `tag:` 锁文件形态与 `glob:` 语义（克隆前失败，未进入解析）；2. `git-submodules` 需要一个网络 submodule URL 或 harness 级 `protocol.file.allow=always` 才能与参考可比；3. 多 gemspec/monorepo/私有 source 鉴权/离线安装/磁盘错误与中断清理仍未覆盖；4. M7(5) 复选框保持未勾。

## 2026-11-15 M7(5)/M7(8) 环境失败根因：Low 完整性级别导致 msys sh 无法建共享内存

**现象**：本机 celerite 触发 `git clone --mirror` 时失败，stderr 为 `git command failed: git clone --mirror ./gitgem <sandbox>/bundle/ruby/4.0.0/cache/bundler/git/gitgem-<sha> …`，紧接 `0 [main] sh (15204) C:\Program Files\Git\usr\bin\sh.exe: *** fatal error - NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-1888ae32e00d56aa): 0xC0000022` 与 `fatal: Could not read from remote repository.`，exit 1。影响面：13 例 install/add/plugin/native 差分（`git-installed-discovery`/`git-path-install`/`git-pristine`/`plugin-git-local`/`plugin-git-local2` 等）与本轮 `git-tag`/`git-glob` 2 例，以及全量 spec 的 4 个 `Celerite::GitSource` error。

**探针矩阵**（`.tmp-scratch/gitprobe/probe.cr`，同一本地仓库 `src`，逐组独立目标目录）：

| 组 | 形态 | 结果 | stderr 首行 |
|---|---|---|---|
| A | `output/error: Redirect::Inherit`（不捕获） | `EXIT=128`，无目标目录 | `0 [main] sh … NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-1888ae32e00d56aa): 0xC0000022` |
| B | 现用法 `IO::Memory` ×2 | `EXIT=128`，无目标目录 | `Cloning into bare repository '…dst-b'...`（随后同上 `0xC0000022`） |
| C | `File.open` 文件重定向 ×2 | `EXIT=128`，无目标目录 | `Cloning into bare repository '…dst-c'...`（随后同上） |
| D | `Process.run("git clone …")` 字符串形式 | **不支持**：Crystal/Windows 抛 `File::NotFoundError`（引号未转义），跳过 | — |
| E | B + `Process.find_executable("git")` 绝对路径 | `EXIT=128`，无目标目录 | 同 B |
| F | `Process.run("sh", ["-c", "echo hi"])` | `STATUS=0xC0000142`，无输出 | 同一条 `sh.exe …: 0xC0000022` |
| G | `cmd.exe /c git clone …` | `STATUS=128`，无目标目录 | `Cloning into bare repository '…dst-g'...`（git 内部仍拉起 sh，同上失败） |
| H | 对照：bash 直跑 `git clone --mirror src dst-bash` | **`GIT_EXIT=0`** | 无 |

**判定**：
- 与 stdout/stderr 捕获形态无关：A/B/C/E 四种形态同败且都没有生成目标目录，D 不可用，排除管道/句柄因素。
- 失败早于 git 逻辑：F 组连 `sh -c "echo hi"` 都失败（`0xC0000142` 为进程初始化失败），说明 `sh.exe` 自身起不来。
- 唯一差异是调用者完整性级别：本 Crystal 进程的子进程 `whoami /groups` 显示 `Mandatory Label\Low Mandatory Level  S-1-16-4096`，pwsh 子进程为 `Medium  S-1-16-8192`；换启动器（pwsh / bash / `cmd.exe` 启动同一探针）矩阵不变，B 均 `EXIT=128`、IL 均 Low → 结论是**执行载体属性（工作区内 Crystal 产物的沙箱完整性级别），不是父进程**。
- 机制：Low IL 进程无权创建/打开 `\BaseNamedObjects\msys-2.0S5-<hash>` 命名对象（`0xC0000022`），msys `sh` 初始化失败（`0xC0000142`）；`git.exe` 与 `cmd.exe` 间接路径同样要拉 `sh`，因此也不能绕过。
- **不是产品代码问题**：四种捕获方式全败，故未改产品代码；`git status` 干净（仅本轮夹具/装具，且已被首辅提交前状态核对）。

**未验证**：
- 未直接枚举该命名对象的 DACL（本机无 WinObj / handle.exe），IL 差异是相关性证据 + 报错文本的合取，未做 DACL 级取证；
- 未验证把 `bin/celerite.exe` 提升到 Medium IL 或加入沙箱白名单后是否即恢复；
- 未尝试 `CYGWIN` / `MSYS` 环境变量绕行（Low IL 下打开既有 Medium 对象预计仍失败）；
- 受影响的 13+2 例夹具与 4 个 spec error 尚未在放行环境复跑验证转绿。

**可选路径（建议，未执行）**：① 沙箱侧放行 `bin/celerite.exe`（Medium IL 或白名单）；② 在不受该限制的宿主或 CI 跑差分与 spec（夹具与装具已就绪）；③ 产品侧引入 libgit2 等新依赖——违反本仓「禁止新增第三方依赖」约束，不建议。

## 2026-11-15 M7(3)：`fund --group` 的组选择、缺 PATH 源报错与 funding 来源对齐

**参考锚点**：`bundler-4.0.24/lib/bundler/cli/fund.rb:14-32`（`--group` 为标量选项，`Array(options[:group]).map(&:to_sym)` 直接交给 `definition.dependencies_for`，命中后打印 `* <full_name>` + `  Funding: <uri>`）、`definition.rb:286-288` 与 `:328-333`（`dependencies_for(requested_groups)` 保留任一 group 落在请求集合内的依赖）、`definition.rb:1251-1255`（默认请求集合 = 声明组 − `without` + `with`）、`source/path.rb:198-204`（`The path `<expanded_path>` does not exist.`，`raise PathError`）、`errors.rb` 中 `PathError` 状态 13、`ui/shell.rb:167-171`（`word_wrap`：`line.length > line_width ? line.gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1\n").strip : line`）。

**修复前缺陷**：① `--group` 被按逗号切分成数组，且忽略「重复 flag 后者覆盖」；② 未套用 `without`/`with`，默认集合错；③ 缺 PATH 目录时直接崩到内部错误或静默继续，没有参考的 `PathError`（exit 13）；④ funding 只要 `cache/*.gem` 能读就取，而参考只读已安装 specifications。

**实现**（`src/celerite/cli/commands_surface.cr`）：
- `fund_group_flag(rest)`：同时接受 `--group=x` 与 `--group x`，重复出现时**后者覆盖**，`development,test` 作为一个组名（因此不命中任何组，与参考一致）。
- `fund_requested_groups(evaluation, config)` + `setting_list`：默认集合 = 声明组 − `BUNDLE_WITHOUT` + `BUNDLE_WITH`。
- `fund_missing_path(definition, lockfile)`：遍历锁文件里**所有** `PATH` 源（不限于直接依赖，参考在 definition 校验时覆盖全部 source），目录不存在则 `stderr.puts Commands.word_wrap("The path `<abs>` does not exist.", CLI.terminal_width)` 并 `return 13`。折行是**推导**出来的，不是硬编码三行：宽终端下同一消息只有一行。
- `read_funding_uri`：删除 `cache/*.gem` 探测分支，只读 `specifications/*.gemspec`。Ruby 实测 `Gem::Specification#to_ruby_for_cache`（`assets/bridge/server.rb:205` 用的序列化）会保留 `s.metadata = { "funding_uri" => … } if s.respond_to? :metadata=`，故不丢信息。

**参考实测（4.0.24，探针项目 `.tmp-scratch/fundprobe`：`alpha` 默认组 + `group :development` 的 `beta`，两者 gemspec 都带 `funding_uri`）**：

| 调用 | 参考 exit | 参考输出 |
|---|---|---|
| `fund` | 0 | `* alpha (0.1.0)` / `  Funding: https://example.com/fund/alpha` / `* beta (0.2.0)` / `  Funding: https://example.com/fund/beta` |
| `fund --group=development` | 0 | 只有 beta |
| `fund --group development` | 0 | 只有 beta |
| `fund --group=development,test` | 0 | `None of the installed gems you directly depend on are looking for funding.` |
| `fund --group=development --group=test` | 0 | 同上（后者覆盖） |
| `fund --group=missing` | 0 | 同上 |
| `BUNDLE_WITHOUT=development` + `fund` | 0 | 只有 alpha |
| 删掉 `vendor/beta` 后 `fund` | **13** | stdout 空；stderr `The path` / `` `C:/…/vendor/beta` `` / `does not exist.`（80 列折行） |

**已声明偏差**：`BUNDLE_WITHOUT=development` 时 `fund --group=development`，参考**崩溃**（`NoMethodError: undefined method 'metadata' for nil` at `bundler/cli/fund.rb:24`，打印 ERROR REPORT 模板）。本实现不复刻崩溃：减掉 `without` 后按「无资金信息」打印 None 并 exit 0。这是有意的行为差异，不计入兼容通过。

**差分夹具**：`fixtures/differential/fund-groups`（`fund`）、`fund-group-development`（`fund --group=development`）、`fund-groups-without`（`.bundle/config` 设 `BUNDLE_WITHOUT: "development"`）。装具的路径源与配置必须放在 `extra/`——`script/differential:199` 只把 `Gemfile`/`Gemfile.lock` 与标记文件写进项目，`extra/` 才整目录复制（本轮首跑三例 `PASS (exit=13)` 就是夹具根下 `vendor/` 被忽略、两侧同样报缺目录的假绿，已把 `vendor/`、`.bundle/` 移入 `extra/` 后复跑）。参考锁文件由 `bundle lock` 生成，与本仓夹具逐字节一致（含 `bundler (4.0.24) sha256=16ca64e2…`）。

**门禁与证据**：
- `crystal spec spec/m7_fund_group_spec.cr` **9 examples, 0 failures, 0 errors, 0 pending**（含「宽终端 `THOR_COLUMNS=1000` 时同一消息只有一行」，用于钉住折行是推导而非硬编码）。
- 全量 `crystal spec` **340 examples, 0 failures, 4 errors, 0 pending**（4 个 error 为 `spec/git_source_spec.cr:46/73/93/119`，即上文 Low IL 环境问题；上轮基线 331/0/4）。
- 差分 4.0.24 `3 passed, 0 failed, 0 skipped`；2.7.2 `3 passed, 0 failed, 0 skipped`。
- 负对照：把 `fund_group_flag` 首行改为 `return nil` 重建二进制后 `FAIL fund-group-development (fund --group=development)`，diff 显示 celerite 多出 `* alpha (0.1.0)` / `  Funding: …`；恢复后 PASS。
- `crystal tool format --check src spec` EXIT 0、`git diff --check` EXIT 0。

**未验证**：1. 多组同时声明（一个依赖属于多个 group，且其中一个被 `without`）时 `dependencies_for` 的并集细节只按源码走读，未做夹具；2. `fund` 在 GEM 源（非 PATH/GIT）上的 funding 输出依赖已安装 specifications 里有 metadata，真实 rubygems.org 未触达；3. `--group` 与 `--without-group` 之类不存在的选项组合未穷举；4. 参考的崩溃偏差只在 4.0.24 复现，2.7.2 未单独验证；5. M7(3) 复选框保持未勾（`console` 仍有 exec/进程内差异、`env` 仍有多 gemspec 顺序未验证）。

### 2026-11-15（check/list/show/info 选项面收敛与 `--gemfile` 生效）

**参考依据**（4.0.24 实测，隔离 HOME/TEMP）：`check` 仅接受 `--dry-run` 与带值的 `--gemfile`（`=`/空格两种），`list` 仅接受 `--name-only`/`--paths`/`--only-group`/`--without-group`/`--format`，`show` 仅 `--paths`，`info` 仅 `--path`/`--version`；未知开关报 `Unknown switches "…"`（原始 token、多个以 `, ` 分隔）并 exit 15，且发生在读取 Gemfile/lockfile 之前；`info` 无参数打印 `ERROR: "bundle info" was called with no arguments` 与 `Usage: "bundle info GEM [OPTIONS]"` 后 exit 15。

**实现**（`src/celerite/cli/commands.cr`）：新增 `unknown_switch_tokens`（带值开关吞下一个 token；保留 `=value` 原始形态）与 `reject_unknown_switches`（输出 `Unknown switches "…"`，返回 15）；`check` 改为薄壳，先拒绝未知开关，再以 `flag_value_ornext` 解析 `--gemfile`，`begin` 内临时设置 `ENV["BUNDLE_GEMFILE"]`、`ensure` 恢复（原无则删除），锁文件由 `Definition#resolve_lockfile` 推导；`list`/`show_info` 各自按参考白名单拒绝未知开关；`info` 无参数在 `Definition.build` 之前返回 15；`show`/`info` 保留按 `BUNDLE_WITH/WITHOUT` 的分组过滤（CLI 分组开关已按参考移除）。

**证据**：

- `crystal spec spec/m7_unknown_switches_spec.cr` → `7 examples, 0 failures`；`spec/m7_installed_discovery_spec.cr` → `20 examples, 0 failures`；`spec/m7_reverse_dependencies_spec.cr` → `4 examples, 0 failures`；首辅复核时把 unknown 与 discovery 两文件放在同一进程内联跑（`27 examples, 0 failures, 0 errors`），不存在顺序耦合。
- `--gemfile` 生效：项目 PATH 源 `vendor/missing_gem` 缺失时默认 `check` → exit 1、stderr 含 `missing_gem`；`check --gemfile=Empty.gemfile` 与 `check --gemfile Empty.gemfile` → exit 0、`The Gemfile's dependencies are satisfied`，且 `ENV["BUNDLE_GEMFILE"]` 恢复。
- 差分：`unknown-switch-check`（`check --without-group test`）、`unknown-switch-list`（`list --bogus --other`）、`unknown-switch-show`（`show --bogus-flag`）→ 4.0.24 `3 passed, 0 failed, 0 skipped`；2.7.2 `3 passed, 0 failed, 0 skipped`，三例均 exit 15。
- 全量 `crystal spec` `347 examples, 0 failures, 4 errors`（4 errors = 既有 `spec/git_source_spec.cr` Low IL 环境）；`crystal tool format --check src spec`、`git diff --check`、`bash -n script/differential` 均 EXIT 0。

**未实现/未验证**：

1. `Did you mean?` 建议行未实现（参考对接近拼写的未知开关会提示）。
2. `check --dry-run` 只接受不校验其语义，未比对参考输出。
3. `list --format` 非 `json` 值未校验。
4. `check --gemfile` 指向不存在文件时我方 exit 1（`No such file or directory @ rb_sysopen - …`），参考实测为 exit 10 `Could not locate Gemfile`，差异未修。
5. `lock --gemfile` 本轮未修（参考支持）。
6. `show` 无参时参考额外列 `  * bundler (4.0.24)`，我方只列锁文件 specs（未修，已登记）。

## 2026-11-15 M7(6)：插件 hook 失败语义

参考实测（bundler-4.0.24 `lib/bundler/plugin.rb` L228-240 `hook`、L345-381 `load_plugin`；Gemfile `source "file:///<repo>/fixtures/gem-index"` + `gem "json_pure"`，插件索引 `.bundle/plugin/index` 五键格式，由 `Bundler::Plugin::Index#register_plugin` 生成）：

| 场景 | 参考 exit | 参考关键输出 |
| --- | --- | --- |
| 1 `BUNDLE_PLUGINS=false` + 会写标记的 after-install hook（混合工程） | 0 | hook 不执行（标记文件不生成）；stderr 无 plugin 文本 |
| 2 加载期 raise（`plugins.rb` 内 `raise "boom at plugin load"`） | 1 | stderr 首行 `Failed loading plugin broken_plugin: boom at plugin load` + `--- ERROR REPORT TEMPLATE ---` |
| 3 hook 调用期 raise | 1 | stdout 先打印 Fetching/Resolving，stderr `--- ERROR REPORT TEMPLATE ---` + `RuntimeError: boom from plugin hook`（`plugin.rb:239`） |
| 4 load_path 目录不存在 | 0 | 五段提示：`The following plugin paths don't exist: <abs>.` … `Continuing without installing plugin <name>.`（9 行，含 4 个空行） |
| 5 混合：缺路径插件 + 健康插件（hook 写标记） | 0 | 既打印场景 4 的警告，**标记文件仍然生成**——参考在 warn 后继续加载其余插件（`plugin.rb` L237-239） |

修复前行为（HEAD=`37079b2` 构建的二进制，本轮开工时以 shim 重建）：场景 2/3/4 一律 **exit 0 且 stderr 0 行**（旧 `commands_install.cr` 的 `rescue Bridge::BridgeError` 与 bridge 的 `fired:false` 都被静默）；探针工程 `.tmp-scratch/plugprobe/{raising,broken,missingpaths}`。

实现：`assets/bridge/server.rb` 的 `op_exec_plugin_hook` 返回结构化 `status`（`skipped`/`load_failed`/`hook_failed`/`ok`）与累积的 `missing` 数组（每项 `plugin`/`paths`），不打印、不让异常逃出；缺失路径插件只跳过自身并继续加载其余插件（对齐 `plugin.rb` L237-239、L345-381）；`src/celerite/plugin_hooks.cr` 增加 `HookResult#status/message/plugin/missing`（含 `MissingPluginPaths`）与 `enabled?(config)`（仅 `false`/`"false"` 关闭，键 `plugins` 即 `BUNDLE_PLUGINS`）；`src/celerite/cli/commands_install.cr` 仅在设置开启时调用，先逐条打印 `missing` 五段提示（内容逐字与参考一致：路径与行尾规范化后 `diff` 为空；参考 stderr 为 CRLF——Ruby 文本模式，我方 CLI 全局 LF，属平台行尾差异），再按状态返回 1（`load_failed`、`hook_failed`）或 0。

已声明偏差：不复刻 `--- ERROR REPORT TEMPLATE ---` 外壳；`hook_failed` 使用自有单行 `Plugin hook after-install failed: <message>`（不含插件名——参考不区分是哪个插件注册的 hook）。

复核修复（2026-11-15，首辅）：早期版本对首个缺失插件提前 `return`，会跳过健康插件的 `plugins.rb` 与 hook，与参考的场景 5 不符；已改为累积 `missing` 并继续加载。新增 spec 例「健康插件仍在缺失插件之后执行」：改动前 `6 examples, 1 failures`（`File.exists?(hook-fired.txt)` Expected true got false，`spec/m7_plugin_hook_failure_spec.cr:239`），改动后 `6 examples, 0 failures`。

逐字校验（首辅亲跑，`bin/celerite.exe` 端到端）：raising → exit 1 + 单行 `Plugin hook after-install failed: boom from plugin hook`；broken → exit 1 + 单行 `Failed loading plugin broken_plugin: boom at plugin load`；missingpaths → exit 0 + 9 行 stderr，与参考 `sed 's#/missingpaths/#/PROJ/#g'` 并按行尾规范化后 `diff` 为空；mixed → exit 0 + 警告 + `mixed-marker.txt` 生成；`BUNDLE_PLUGINS=false` → exit 0 + stderr 0 行 + 标记不生成。

负对照（首辅）：把 `commands_install.cr` 中 `load_failed` 分支的 `return 1` 改成 `return 0` → `6 examples, 1 failures`（`spec/m7_plugin_hook_failure_spec.cr:170`，断言 `code.should eq(1)` 得到 0），还原后 6/0。

未验证：多插件同时失败、多插件同时缺失时的警告顺序、`plugin_source` 定义的自定义 source、`BUNDLE_PLUGINS` 从 `.bundle/config` 读取（spec 与环境变量探针覆盖，未覆盖配置文件路径）、参考 hook 参数形态（`(spec, context)`，我方以单参数调用）。

门禁：`crystal tool format --check src spec` EXIT 0、`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅 2 条既存 `File.executable?` deprecation）、`crystal spec spec/m7_plugin_hook_failure_spec.cr` **6 examples, 0 failures, 0 errors**、全量 `crystal spec` **353 examples, 0 failures, 4 errors, 0 pending**（4 errors = 既有 `spec/git_source_spec.cr` 的 msys `0xC0000022` 环境问题，非回归）、`git diff --check` EXIT 0、`bash -n script/differential` EXIT 0。

## 2026-11-15 M7(6)：插件命令注册

参考锚点（`bundler-4.0.24`）：
- `lib/bundler/cli.rb:187-195` `handle_no_command_error`：`Bundler.settings[:plugins] && Plugin.command?(command)` 命中 → `Plugin.exec_command(command, ARGV[1..-1])`，先于 `bundler-<name>` PATH 回退。
- `lib/bundler/cli.rb:155-160`：`help <cmd>` 对插件命令执行 `Plugin.exec_command(cli, ["--help"])`。
- `lib/bundler/plugin/index.rb:128-130`：`plugin list` 每个插件输出 `<name>`、`-----`、每条命令 `  <cmd>`，插件之间一个空行。
- `lib/bundler/plugin/index.rb:54-74` + `errors.rb:49`：命令冲突 → `PluginError` status 29，stderr `Failed to install plugin \`<plugin>\`, due to Bundler::Plugin::Index::CommandConflict (Command(s) \`<cmd>\` declared by <plugin> are already registered.)`，索引不写。

实现：
- 新增 `assets/bridge/plugin_command.rb`（独立 Ruby 进程，避免污染桥的 JSON-RPC stdout）：`--commands` 列出 `plugins.rb` 声明的命令并输出 JSON；执行模式读索引 → `plugin_paths` → `load plugins.rb` → `command.new.exec(command, args)`。
- 新增 `src/celerite/plugin_commands.cr`（`index_path`/`commands`/`declared_commands`/`exec`/`enabled?`）。
- `src/celerite/cli/commands.cr`：else 分支在 `bundler-` 回退前分发插件命令；`help <cmd>` 对非内建插件命令以 `--help` 执行。
- `src/celerite/cli/commands_surface.cr`：`plugin list` 按索引顺序输出命令；`install --path`/远程安装合并 `commands:` 段并检测冲突（exit 29、索引不变）；重复安装同名插件只打印一次 `Installed plugin`；`uninstall` 删除该插件命令。

修复前对照（旧 `bin/celerite.exe`，探针 `.tmp-scratch/plugcmd`）：
- `celerite mahcommand` → exit 15，stderr `Could not find command "mahcommand".`
- `celerite plugin list` → `mah-plug`、`-----`、空行（缺命令行）

证据：
- `spec/m7_plugin_commands_spec.cr`：7 examples, 0 failures, 0 errors。
- 差分 `plugin-command-list`、`plugin-command-reinstall`：4.0.24 `2 passed, 0 failed, 0 skipped`；2.7.2 `2 passed, 0 failed, 0 skipped`（`plugin-command-list` 覆盖命令写入索引后 `plugin list` 输出 `  mahcommand`；`plugin-command-reinstall` 覆盖重复安装同名插件只打印一次 `Installed plugin`）。
- 命令冲突路径**不设**差分夹具：参考在 `plugin install --path` 因 `CommandConflict` 失败时会删除 `--path` 源目录（实测 `after-ref: exists=no`，我方保留 `after-cel: exists=yes`），装具的 project-tree 比较必然出现 `Only in project: <源目录>`，无法对齐。该路径改由 spec（`spec/m7_plugin_commands_spec.cr:182` 断言 exit 29）+ 首辅端到端逐字比对取证：参考与 `bin/celerite.exe` 同场景均 exit 29，stdout `Resolving dependencies...`、stderr 三行（80 列折行）在 CRLF 归一化后逐字相同，索引均不变。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；全量 `360 examples, 0 failures, 4 errors`（4 = 既有 `spec/git_source_spec.cr` 的 msys `0xC0000022`）；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。

已声明偏差 / 未验证：
- 插件命令执行失败时我方输出单行 `celerite plugin command \`<cmd>\` failed: <class>: <msg>`（参考为完整 ERROR REPORT 模板）。
- 插件索引行尾：参考（`Bundler::YAMLSerializer` + `File.open(..., "w")` 文本模式）写 CRLF，我方写 LF；内容逐字一致，双方可互读（实测：我方读参考索引 `plugin list`/命令分发正常，参考读我方 LF 索引同样正常）。
- 冲突安装失败时参考会删除 `--path` 源目录（破坏性副作用），我方保留源目录——有意不复刻。
- 远程插件安装记录命令仅按既有远程安装流程实现，未做真实远端差分。
- 第三方插件（非 fixture）的命令 `--help` 内容、`Did you mean?` 建议均未实现/未验证。

## 2026-11-15 M7(6)：Gemfile 声明的插件预装

参考语义（`bundler-4.0.24`）：
- `cli/install.rb:41` 在构建 definition 之前调用 `Plugin.gemfile_install(Gemfile)`；
- `plugin.rb:104-127` `gemfile_install`：解析 `Bundler::Plugin::DSL`，对每个声明插件 `installed_plugin?` 否则 `install_plugin`；对 `bundler-source-<type>` 做 source 预装；
- `plugin/dsl.rb:31-50`：`source "…", type: :t` 推断插件名 `bundler-source-t`；`gem`/`source` 行在 plugin DSL 中静默忽略，未知方法抛 `PluginGemfileError`；
- `dsl.rb:128-139/240-242`：主 DSL 的 `plugin "x"` 为空实现；`source` 的 `type:` 在 plugins 关闭时抛 `InvalidOption`；
- `dsl.rb:542-570`：`DSLError#status_code` 继承成因错误的 `status_code`，`GemfileError` 兜底 4；
- `friendly_errors.rb:26-36`：错误按 wrap 处理。

首辅实测矩阵（参考 4.0.24，`BUNDLE_PLUGINS` 默认/显式）：

| 场景 | plugins | 退出码 |
|---|---|---|
| `source …, type: :psource do gem "json_pure" end`（缺 `bundler-source-psource`） | on | 7 |
| 同上但无 block | on | 7 |
| `plugin "psource-plugin"`（缺该 gem） | on | 7 |
| 同上 `type:` 场景 | off | 15（`No plugin sources available for psource` + `>  source …` 摘录） |
| `plugin "psource-plugin"` + `gem "json_pure"` | off | 0（plugin 行被忽略） |
| `undefined_method_here "x"` | off | 4 |
| 同上 | on | 29 |

修复前（`bin/celerite.exe`，本机实测）：`source …, type:` 与 `plugin "…"` 一律 exit 1（直接进主 DSL）；`plugin "x"` 被静默忽略；`type:` 在 plugins 关闭时也 exit 1（未走 `InvalidOption` 文案）。

实现：
- `assets/bridge/server.rb`：`bridge_error` 仅在错误响应 `respond_to?(:status_code)` 时附带 `"status"`；新增 `op_plugin_gemfile_eval`（`Bundler::Plugin::DSL#eval_gemfile` 后返回 `plugin_names`，不 rescue，让 4/15/29 原样上报）。
- `src/celerite/bridge/client.cr`：`BridgeError` 增 `status : Int32?` 与 `status_code = @status || 1`；`plugin_gemfile_eval`。
- 新增 `src/celerite/plugin_gemfile.cr`：`enabled?`（`BUNDLE_PLUGINS` 非 false）、`plugin_names`、`primary_source`、`strip_comment`。
- `src/celerite/cli/commands_install.cr`：`install` 在本地策略校验（不支持 settings fast-fail）之后、第一次 `bridge.evaluate_gemfile`（真正的 DSL 求值）之前执行插件预装（`PluginGemfile.enabled?` 才建 bridge）。注：`Definition.build` 只定位 Gemfile/锁文件、不做 DSL 求值，故预装严格早于任何 Gemfile 求值，与参考 `Plugin.gemfile_install` 在 `Definition` 构建前调用的效果一致；每个声明插件 `installed_plugin?` 否则 `plugin_install_remote([name], ["--source", primary_source])`；`bundler-source-*` 缺 gem 由正常解析得出 7。预装异常面：`Bridge::BridgeError` 仅 `{4,7,15,29}` 上抛，其余回落正常流程；`Celerite::Error`（如无 bridge）直接回落。
- `src/celerite/cli/commands_surface.cr`：插件物化用纯 Crystal `copy_tree`（替代 `cp -r`，避免本机 Low-IL 下 `cp.exe 0xC0000022`）。
- `src/celerite/plugin_commands.cr`：`installed_plugin?(index_path, name)`。

已声明偏差 / 未实现：
- 自定义 `source type:` 的成功路径（需要把插件加载进 bridge 的解析进程）未实现，命中时打印 `Installing plugin sources declared in the Gemfile is not supported by Celerite: <type>` 并 exit 1；
- `plugin "x"` 指向存在但缺 `plugins.rb` 的 gem 时，`MalformattedPlugin`（29）由参考的插件校验语义给出；本产品同样 exit 29，但未做差分夹具；
- 预装只对「Gemfile 声明了插件」生效；普通 install 不额外起 bridge。

门禁（干净 HOME，`home-gate29c`）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；`spec/m7_gemfile_plugins_spec.cr` **7 examples, 0 failures**；`spec/m7_build_args_spec.cr` + `spec/m7_install_ensure_unmask_spec.cr` **6 examples, 0 failures**；全量 `crystal spec` **367 examples, 0 failures, 4 errors**（4 errors = 既有 `spec/git_source_spec.cr` 的 msys `0xC0000022`）；`git diff --check` EXIT 0。差分：`plugin-gemfile-missing` 4.0.24/2.7.2 均 `PASS (exit=7)`、`1 passed, 0 failed`；`plugin-source-disabled` 以 `deferred-4.0.24`/`deferred-2.7.2` 登记（harness 无法逐夹具设 `BUNDLE_PLUGINS=false`）。

首辅复核时的负对照：把 `install_gemfile_plugins` 的状态透传由 `raise ex if {4,7,15,29}` 改为无条件 `return nil` → `spec/m7_gemfile_plugins_spec.cr` 得 `7 examples, 1 failures`，失败例 `:157`（`Expected: 29, got: 4`），证明 `status` 透传是 29/4 区分的载荷；恢复后 `7 examples, 0 failures`。

未验证：真实远端插件 `--source`/`--git` 的命令记录；`plugin list` 对带 `plugins.rb` 真实插件 gem 的输出；`BUNDLE_PLUGINS=false` 与 `plugin "x"` 组合的差分夹具；上述 success-path 偏差与参考的完整对齐。

## 2026-11-15 M7(5)：`--local` / `--prefer-local`

参考源码锚点（bundler-4.0.24）：`cli/install.rb:15`（`if options[:local]`）、`:52-53`（local 时关闭 cache_all_platforms、`Bundler.load.cache(nil, options[:local])`）；`definition.rb:191`（`prefer_local! if options[:"prefer-local"]`）、`:200/:212`（`sources.local!`）、`:227-230`（`prefer_local!` 置位并 `sources.prefer_local!`）；`source/rubygems.rb:40-55`（`prefer_local!`/`local_only!`/`local_only?`）；`resolver.rb:152,525`（`prefer_local?` 影响候选与远程版本考虑）。`settings[:local]` 由 `BUNDLE_LOCAL` 提供，本产品尚无该设置项（本轮未实现）。

三条实测 oracle（4.0.24，隔离 HOME/GEM_HOME）：
1. `--local` + http 源 + GEM_HOME 已装 `json_pure 2.6.0`（索引另有 2.8.1）→ exit 0、锁 `json_pure (2.6.0)`，索引零请求（HTTP 计数 0）。
2. `--local` 且 gem 任何位置都没有 → exit 7、stdout 无 `Fetching`、stderr 单行 `Could not find gem 'no_such_gem_xyz' in locally installed gems.`
3. `--local` + `source "file:///…/fixtures/gem-index"` 且未安装 → **exit 7**（索引同样不查）。最初 oracle 误判为「file:// 仍解析」，原因已查明：那次探针的 system gem 目录恰好装着 `json_pure 2.8.1`，参考是从已安装 gems 解析、并把它写进 vendor/cache，并非读 file:// 索引。

修复前缺陷：`resolution.cr` 的 `index_specs_for` 对**任何** gem 在 `--local` 下直接 `raise GemNotFoundError`（已安装的也报缺，探针实测 exit 7）；`prefer_local` 属性无任何消费者（探针 `--prefer-local` exit 0 但锁 2.8.1）。

实现：桥新增 `installed_specs` op（`Gem::Specification.to_a`：name/version/platform/运行时依赖/required_*/full_gem_path）；`bridge/client.cr#installed_specs`；`resolution.cr` 新增 `requirement_from`（逗号拆分多子句）、`local_index_specs`、`vendor_cache_specs`（读 `<Gemfile dir>/vendor/cache/*.gem`，经 `read_gem_spec`）、`local_installed_full_names`；`index_specs_for` 在 `local_only` 时只返回本地候选（不查任何索引）、空则抛参考消息；`prefer_local` 本地非空即优先；`commands_install.cr` 对 `local_only` 下已在本项目 GEM_HOME 的 spec 跳过 Fetching/Installing。

已声明偏差：本地候选在 `ENV["GEM_HOME"]` 存在时只认该目录下的安装（测试宿主用户目录携带 `json_pure 2.8.1`，会盖过项目 GEM_HOME 的 2.6.0）；参考按 `Gem.path` 全局可见。`--local` 的 vendor/cache 命中路径未单独造例（实现读取，但只以已安装 gems 覆盖）。

负对照（首辅亲做）：把 `index_specs_for` 的本地分支改成 `if false`（强制走索引）后 `spec/m7_local_install_spec.cr` → `5 examples, 4 failures`（`:90`/`:110`/`:126`/`:145`，即 http 索引被请求、file:// 索引被读取、`--prefer-local` 选到 2.8.1）；还原后 5/0/0。

门禁（干净 HOME）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；`spec/m7_local_install_spec.cr` 5/0/0；`spec/m7_local_install_spec.cr spec/cli_spec.cr` 29/0/0；全量 `372 examples, 0 failures, 4 errors`（4 = 既有 `git_source_spec.cr` msys `0xC0000022`）；`git diff --check` EXIT 0；差分 `install-local` 4.0.24 与 2.7.2 均 PASS（exit 7）。

未验证：https 真实离线、vendor/cache 多平台、`--local` + git 源、`--local` + `--frozen`、`BUNDLE_LOCAL` 设置项。

## 2026-11-15 M7(1)：平台变体正例

参考锚点（bundler-4.0.24）：`resolver.rb:56`（候选 `sort_by {|s| [s.version, s.platform.to_s] }`）、`:259`（按 `[version.hash, platform]` 去重，同版本不同平台并存）；`lockfile_generator.rb:48`（按 `spec.full_name` 写出，平台进入锁文件标签）、`:54-55`（`PLATFORMS` 段来自 `definition.platforms`）；`definition.rb:99-108`（锁定/新增/移除平台集合）。

新索引 `fixtures/gem-index-platform/`（照 `gem-index-locked-deps` 形态，由一个临时 Ruby 生成器从两个 `.gem` 生成；gemspec 全文见下）：`platdemo 1.0.0`（platform ruby）与 `platdemo 1.0.0-x64-mingw-ucrt`，均无依赖，`files = ["lib/celerite_fixture/platdemo.rb"]`。构建命令：`ruby -S gem build platdemo.gemspec --output platdemo-1.0.0.gem`，第二次设 `PLATFORM=x64-mingw-ucrt`。info 两个版本行**故意混用两种写法**以同时覆盖：平台变体行保留空格（`1.0.0-x64-mingw-ucrt |checksum:…`），ruby 行紧贴（`1.0.0|checksum:…`，即 rubygems.org 对「无依赖但有 checksum」的写法）；checksum 为各自 `.gem` 的 SHA256 base64。

oracle（本机 Ruby 4.0.6，`Gem::Platform.local` = `x64-mingw-ucrt`；隔离 HOME、`BUNDLE_PATH`）：
```
Gemfile.lock:
GEM
  remote: file:///…/fixtures/gem-index-platform/
  specs:
    platdemo (1.0.0-x64-mingw-ucrt)

PLATFORMS
  x64-mingw-ucrt

DEPENDENCIES
  platdemo

CHECKSUMS
  bundler (4.0.24) sha256=16ca…
  platdemo (1.0.0-x64-mingw-ucrt) sha256=f02d…
```
install stdout：`Fetching platdemo 1.0.0 (x64-mingw-ucrt)`、`Installing platdemo 1.0.0 (x64-mingw-ucrt)`、`Bundle complete! 1 Gemfile dependency, 1 gem now installed.`；安装树 `<BUNDLE_PATH>/ruby/4.0.0/gems/platdemo-1.0.0-x64-mingw-ucrt`。`check` → `The Gemfile's dependencies are satisfied`；`list` → `  * platdemo (1.0.0)`；`show --paths` 两行（bundler 目录 + 上述安装目录）。

修复前我方缺陷（探针 `.tmp-scratch/platprobe/ours`）：解析与锁定已正确选择 mingw 变体（`Gemfile.lock` 为 `platdemo (1.0.0-x64-mingw-ucrt)`、安装目录带平台），但进度行缺平台后缀：`Fetching platdemo 1.0.0` / `Installing platdemo 1.0.0`。

实现：`src/celerite/cli/commands_install.cr` 新增 `Commands.platform_suffix(platform : String?)`（`nil`/空/`"ruby"` → `""`，否则 `" (#{platform})"`），用于三处进度行（install_spec 的 Installing、pending 的 Fetching、force_install 的 Installing）。解析侧无需改动（既有 `filter_specs` 的平台匹配已选对变体）。

差分夹具：`fixtures/differential/lock-platform-variant/`（`command`=`lock`，`Gemfile` 用 `file:///@PLATFORM_INDEX_DIR@` + `gem "platdemo"`，`file-contains` 断言 `    platdemo (1.0.0-x64-mingw-ucrt)` 与 `  x64-mingw-ucrt`）与 `fixtures/differential/install-platform-variant/`（`command`=`install` + `installed-tree` 三条 marker）。`script/differential` 新增 `platform_index_dir`（`cygpath -m`）与 `@PLATFORM_INDEX_DIR@` 的五处 sed。

门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；全量 `381 examples, 0 failures, 4 errors`（4 = 既有 `git_source_spec.cr` 的 msys `0xC0000022`）；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。差分：4.0.24 `2 passed, 0 failed, 0 skipped`；2.7.2 `2 passed, 0 failed, 0 skipped`。

负对照（首辅亲跑）：把 `Commands.platform_suffix` 首行改成恒 `return ""` 并重建 `bin/celerite-neg.exe` → `FAIL install-platform-variant (install)`，原文 `stdout differs: 3,4c3,4 < Fetching platdemo 1.0.0 (x64-mingw-ucrt) / < Installing platdemo 1.0.0 (x64-mingw-ucrt) --- > Fetching platdemo 1.0.0 / > Installing platdemo 1.0.0`，`1 passed, 1 failed`；恢复源码并删除负对照二进制后复跑 `2 passed`。

### 同一轮附带修复：compact-index `info` 行的无空格 requirements

- 缺陷（修复前证据）：把 `fixtures/gem-index-platform/info/platdemo` 的 ruby 行写成标准无空格形态后，参考 `bundle lock` **EXIT 0** 且锁到 `platdemo (1.0.0-x64-mingw-ucrt)`；我方 `celerite lock` **EXIT 20**，stderr `bad compact index data for platdemo: Malformed version number string`，锁文件未写出。根因：`src/celerite/compact_index/cache.cr:495-522` 的 `parse_info_line` 先 `line.split(" ", 2)` 取 `segments[0]` 当 `version[-platform]`，无空格时 `1.0.0|checksum:…` 被整个当成版本号。
- 参考语义：info 行是 `VERSION[-PLATFORM] [DEPS]|REQUIREMENTS`，`|` 之后才是 requirements（`checksum:` 就在这一段），依赖段可以整体省略——因此 `1.0.0|checksum:…` 与 `1.0.0 |checksum:…` 等价。
- 实现：`src/celerite/compact_index/cache.cr:498-511` 增加分支——`rest.nil?` 时若版本段含 `|`，则在 `|` 处切开，把 `|…` 交回 `rest` 走既有 `partition("|")` 流程；空格形态行为不变。
- 回归 spec：新增 `spec/m7_compact_info_space_spec.cr`（2 examples，用 `fixtures/gem-index-platform` 走 `Resolution`）：①无空格形态解析出的版本必须是 `1.0.0` 且不含 `|`；②锁文件文本含 `platdemo (1.0.0` 且不含 `|checksum`。`2 examples, 0 failures`。
- 负对照（首辅亲跑）：把该分支条件改成 `if false && …` → 两个 example 全部 error（`Malformed version number string`），`2 examples, 0 failures, 2 errors`；恢复后 `2/0/0/0`。
- 覆盖：`lock-platform-variant` / `install-platform-variant` 现在同时覆盖两种写法（同一 index 内混用），双 profile 均 PASS。

未验证/已知差异：ABI 段无新夹具（既有 `ruby_abi` 单元证据）；`--local` 与平台变体组合、多平台同时锁定（同 gem 两个平台同时进锁文件）未测；`CHECKSUMS` 段未做逐字差分（装具不比较锁文件内容，只比较 `file-contains` 指定的行）。

## 2026-11-15 M7(1)：`check` 重解通知的「依赖已满足」取证 + `bundle-preset` 装具能力

`docs/roadmap.md` L155 曾记录：`check` 在「Gemfile 声明 `ruby`、lock 无 `RUBY VERSION`、依赖已满足」时应打印 `Resolving dependencies...`，但该场景**无法差分 fixture 化**，因为 `script/differential` 在跑命令前不会预填充 `BUNDLE_PATH`。本轮补上装具能力并固化证据。

### 参考语义（逐行锚定）

- `bundler-4.0.24/lib/bundler/cli/check.rb`：`check` 一进来即 `Bundler.load`，definition 构建触发解析。
- `bundler-4.0.24/lib/bundler/definition.rb`：`@unlocking_ruby = (!@locked_ruby_version ^ !@ruby_version)`；`Resolving dependencies...` 由 resolver 在 `@unlocking_ruby` 为真时输出。
- 我方镜像点：`src/celerite/cli/commands.cr:467-486` `Commands.lock_ruby_unlock_kind`（`:diff`/`:missing_from_lock`/`:none`）与 `:534` 的打印条件；`bridge_available?` 为假时 `:none`（best-effort，不阻塞历史可用命令）。

### 参考实测（本轮重做，避免上轮误判）

探针 `.tmp-scratch/probe-ck`（`BUNDLE_PATH` 预置 `ruby/4.0.0/specifications/json_pure-2.8.1.gemspec` + `gems/json_pure-2.8.1/lib`，Gemfile `source file:///@INDEX_DIR@` + `ruby "4.0.6"` + `gem "json_pure"`，lock 有 specs、无 `RUBY VERSION`）：

- 参考 `bundle check` → `Resolving dependencies...` + `The Gemfile's dependencies are satisfied`，EXIT 0，**并把 `RUBY VERSION` 写回 lockfile**（后续再跑就不再打印；上一轮「我方缺通知」的结论正是被这次写回污染所致，属测量伪影）。
- 我方（bridge 可用）→ 同样两行、EXIT 0；bridge 不可用 → 仅第二行（已声明的 best-effort 回退）。

### 新增装具能力：`bundle-preset/`

`script/differential` 在建立沙箱后，如夹具目录存在 `bundle-preset/`，则把其内容复制到两侧各自的 `$sandbox/bundle`（即 `BUNDLE_PATH`）。用于「依赖已安装」类场景；该目录在沙箱内、不参与 project-tree 比较。

### 新夹具 `fixtures/differential/check-satisfied-nolock-ruby/`

`Gemfile`（`source file:///@INDEX_DIR@` + `ruby "4.0.6"` + `gem "json_pure"`）、`Gemfile.lock`（有 specs、无 `RUBY VERSION`）、`bundle-preset/ruby/4.0.0/{specifications,gems}/json_pure-2.8.1`、`command` = `check`。

### 门禁与负对照（首辅亲跑）

- 差分 `check-satisfied-nolock-ruby`：4.0.24 **PASS (exit=0)**、2.7.2 **PASS (exit=0)**。
- 回归：4.0.24 `check-missing-ruby-nolock check-satisfied-nolock-ruby install-fresh lock-path-absolute-relative` → **4 passed, 0 failed**；2.7.2 `check-missing-ruby-nolock check-satisfied-nolock-ruby install-local` → **3 passed, 0 failed**。
- 负对照：把 `:534` 的打印条件改成 `if false` 并重建 `bin/celerite-neg.exe` → `FAIL check-satisfied-nolock-ruby (check)`，原文 `stdout differs: 1d0 < Resolving dependencies...`，`0 passed, 1 failed`；恢复源码、删除负对照二进制后 PASS。
- `spec/m7_check_ruby_notice_spec.cr` 2 例（有/无 bridge 两态断言完整 stdout），2/0/0。
- `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；全量 `374 examples, 0 failures, 4 errors`（4 = 既有 `git_source_spec.cr` msys `0xC0000022`，上轮 372/0/4）。

### 未验证 / 仍存差异

- bridge 不可用时 `check` 省略通知（参考无此回退）——既有设计，属已知 best-effort 差异。
- `show`/`info` 的其他重解通知形态未取证（roadmap L154 的剩余项）。
- 参考会把 `RUBY VERSION` 写回 lockfile，我方 `check` 不改写锁文件（已声明差异，`check` 只读）。

## 2026-11-15 M7(1)：`show` / `show --paths` 的列表形态对齐

`docs/roadmap.md` L155 的 `show` 条目此前只覆盖「已安装 gem 发现」与 `show <gem>`，没有覆盖**裸 `show` 的列表首行**与 `show --paths` 的输出形态。本轮补齐取证并修复两处真实差异。

### 参考语义（bundler-4.0.24，逐行锚定）

- `lib/bundler/cli.rb`：`show` 分支在无 gem 名时调用 `print_ver(command, definition.specs, patch_level)`；`Bundler::Definition#specs` 是 `@specs ||= ...`，其中包含运行中的 Bundler 自身（`Bundler.rubygems.bundler_spec`），因此列表首行恒为 `  * bundler (<运行中版本>)`，与锁文件 `BUNDLED WITH` 无关。
- `lib/bundler/cli/printer.rb`：`print_ver` 先打印 `Gems included by the bundle:`，再逐条 `  * name (version)`；`print_paths` 只打印路径、不打 header。

### 参考实测（探针 `.tmp-scratch/probe-show`，依赖已满足态）

| 命令 | 参考输出 | 修复前 Celerite |
| --- | --- | --- |
| `show` | header + `  * bundler (4.0.24)` + `  * json_pure (2.8.1)` | 缺 bundler 行 |
| `show --paths` | 仅两行路径（首行 `.../gems/bundler-4.0.24`，次行 json_pure） | 多打印 header，且缺 bundler 路径 |
| `show`（缺 gem） | header 进 stdout + `Could not find json_pure-2.8.1 in locally installed gems` 进 stderr，exit 7 | 一致 |
| `show --paths`（缺 gem） | **无 header**，仅错误行，exit 7 | 多打印 header |
| `list` / `list --paths` / `show <gem>` / `info <gem>` | — | 已一致 |

`BUNDLED WITH` 分别写成 4.0.24、2.7.2、缺省时，参考 `show` 首行**始终**是运行中的版本（本机 4.0.24）。

### 实现

- `src/celerite/cli/commands.cr`：裸 `show` 分支改为先做缺失检查；`--paths` 时不打印 header，并在可解析时先打印运行中 Bundler 的 gem 目录；人类可读形态在 header 后插入 `  * bundler (<profile 版本>)`。
- 新增 `private def self.profile_bundler_version`（`ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"`，与仓库其余位置一致）与 `private def self.bundler_gem_dir`（由 `CELERITE_REFERENCE_BUNDLER_LIB` 取 `File.dirname`，目录存在才返回）。Celerite 把参考 Bundler 作为兼容 profile 携带而非安装成 gem，差分装具与桥都会导出该变量。

### 证据

- 新增 `spec/m7_show_listing_spec.cr`（5 examples，0 failures）：人类可读首行 bundler、`--paths` 两行（首行为参考 lib 的父目录）、无 reference lib 时退化只打印 gem 路径、缺 gem 时两种形态的 header/exit 行为。
- 新增差分 `fixtures/differential/show-listing-bundler`（`show`）与 `fixtures/differential/show-paths-bundler`（`show --paths`），复用 `bundle-preset/` 预置已安装 `json_pure`；4.0.24 与 2.7.2 各 **2 passed, 0 failed**。
- 负对照两次（首辅亲跑）：把缺失分支的 header 改为无条件打印 → `spec/m7_show_listing_spec.cr:178` 失败（`Expected: "" / got: "Gems included by the bundle:\n"`）；删掉 bundler 行 → `:118` 失败（缺少 `  * bundler (4.0.24)`）。恢复后均 5/0/0。
- 门禁（干净 HOME/TEMP）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；全量 `crystal spec` **379 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` msys `0xC0000022`；上轮 374/0/4）；`git diff --check` EXIT 0。
- 端到端对照：同一探针下 6 条命令（`show`、`show --paths`、`show json_pure`、`info json_pure`、`list`、`list --paths`）在依赖已满足态与缺 gem 态逐条比对，退出码与输出一致。

### 未验证 / 已知差异

- 未设置 `CELERITE_REFERENCE_BUNDLER_LIB` 时无法定位运行中 Bundler 的 gem 目录，`--paths` 省略该行（参考恒有）；`show` 的 `  * bundler` 行仍打印 profile 版本。
- 参考在 `--paths` 时排到最前的是**运行中** Bundler（多条 bundler 版本安装时取激活的那一份），本实现取配置的 reference lib，不做多版本解析。
- `show` 与 `info` 的其他重解通知形态仍未取证（roadmap L154 的余项）。

## 2026-11-15 M7(1)：frozen 模式下 ruby 解锁拒绝

参考锚点（bundler-4.0.24）：`definition.rb:421-425`（`@unlocking_ruby` 为真且 frozen 时 `raise ProductionError, "Bundler is unlocking ruby, but the lockfile can't be updated because frozen mode is set"`，无句点）、`definition.rb:616-618`（`validate_runtime!` 中同一守卫）、`errors.rb:35`（`ProductionError` 状态码 16，`friendly_errors.rb:26-36` 按 80 列折行）。

本机实测（基座 `fixtures/differential/check-satisfied-nolock-ruby`：Gemfile 声明 `ruby "4.0.6"`、lock 有 specs 无 `RUBY VERSION`、预置已安装 json_pure 2.8.1；`BUNDLE_FROZEN=true`）：

| 命令 | 参考 4.0.24 | 我方（修复后） |
| --- | --- | --- |
| `check` | exit 16，stdout 空，stderr 两行 `Bundler is unlocking ruby, but the lockfile can't be updated because frozen mode` / `is set` | 一致 |
| `show` / `show --paths` / `show json_pure` / `info json_pure` | exit 0，正常列表/路径/信息（**不**触发生产检查） | 一致（本轮实测推翻首辅 oracle 中「show/info 也 exit 16」一条，以实测为准） |
| `list` | exit 0，不打印 `Resolving dependencies...` | 一致 |
| 2.7.2 的 frozen `check` | exit 0，只打印 `The Gemfile's dependencies are satisfied`（无通知；2.7.2 无该重解通知） | 一致 |
| `BUNDLE_DEPLOYMENT=true` 的 `check` | exit 16，stderr 4 段共 6 行：两行消息 + 空行 + `If this is a development machine, remove the Gemfile.lock freeze by running` / `` `bundle config set frozen false`. `` | 一致（`deploy` 标记夹具） |
| `.bundle/config` 的 `BUNDLE_FROZEN: "true"` | 与 deployment 相同的 4 段 | 实现按非 env 来源追加提示，未单独 fixture |

修复前证据：`spec/m7_frozen_ruby_unlock_spec.cr` 首跑 `6 examples, 5 failures`（4 × `Expected: 16 got: 0`、`list` 多打 `Resolving dependencies...`）；差分 `check-frozen-ruby-nolock` 在旧二进制下 `FAIL`（reference=16 / celerite=0）。

实现：`src/celerite/cli/commands.cr` 的 `run_check` 在算出 `lock_ruby_unlock_kind` 后、任何 stdout 之前：**非 frozen 且 kind != :none 一律打印 `Resolving dependencies...`（与 profile 无关，2.7.2 也打印）**；frozen 且 kind != :none 且 4.x profile 时 `raise ProductionError.new(消息)`（2.7.2 无此守卫）。消息构造：`ENV["BUNDLE_FROZEN"]` 非真值（nil/空/`false`）时追加 `\n\nIf this is a development machine, remove the <相对锁文件名> freeze by running \`bundle config set frozen false\`.`，即 deployment/config-file frozen 保留 4 段、env frozen 仅 2 行（`frozen_from_environment?` helper，对应 `definition.rb:475-492`）。`list` 非 frozen 且 kind != :none 打印通知、frozen 不打印；`show_info` **不加**守卫（实测参考不检查）。`ProductionError` 沿用既有类（status 16、`wrap? true`），折行与空行由统一 friendly error 渲染。

差分夹具：`fixtures/differential/check-frozen-ruby-nolock/`（`command`=`check` + `frozen` 标记 + 基座 Gemfile/lock/bundle-preset）、`fixtures/differential/show-frozen-ruby-nolock/`（`command`=`show`，同标记）与 `check-deploy-ruby-nolock/`（`command`=`check` + `deploy` 标记）。`script/differential` 新增 `frozen`/`deploy` 标记：存在时参考侧 `isolated_env+=(BUNDLE_FROZEN=true)` / `(BUNDLE_DEPLOYMENT=true)`，celerite 侧 env 相应追加。

差分结果（4 个夹具 × 双 profile，全部 PASS）：4.0.24 `PASS check-satisfied-nolock-ruby (exit=0)`、`PASS check-frozen-ruby-nolock (exit=16)`、`PASS show-frozen-ruby-nolock (exit=0)`、`PASS check-deploy-ruby-nolock (exit=16)` → `4 passed, 0 failed, 0 skipped`；2.7.2 `PASS check-satisfied-nolock-ruby (exit=0)`、`PASS check-frozen-ruby-nolock (exit=0)`、`PASS show-frozen-ruby-nolock (exit=0)`、`PASS check-deploy-ruby-nolock (exit=0)` → `4 passed, 0 failed, 0 skipped`。

spec `spec/m7_frozen_ruby_unlock_spec.cr` 10 例：frozen check/show/show --paths/info/list、非 frozen check、**2.7.2 profile 下非 frozen check/list 的通知**、2.7.2 frozen check、deployment 4 段提示。

门禁（干净 HOME/TEMP）：format --check EXIT 0；build --no-codegen EXIT 0；全量 `391 examples, 0 failures, 4 errors`（4 = 既有 `git_source_spec.cr` msys `0xC0000022`）；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。

负对照（首辅亲做）：把 `run_check` 的守卫条件临时改成 `&& false` 并重建 `bin/celerite-neg.exe`，同一夹具集得到 `differential (4.0.24): 0 passed, 2 failed, 0 skipped`，原文 `exit code: reference=16 celerite=0` + `stdout differs: 0a1 > The Gemfile's dependencies are satisfied` + `stderr differs: 1,5d0 < Bundler is unlocking ruby, … < is set < (空行) < If this is a development machine, … < `bundle config set frozen false`.`；恢复源码后重新构建并复跑，两夹具 PASS。

已声明偏差/未验证：非 frozen 的 lockfile 写回仍不复刻（沿用既有登记）；提示段里的锁文件名用 `File.basename(definition.lockfile_path)`（参考用相对 `Dir.current` 的 `relative_lockfile_path`，Gemfile 在子目录时会不同）；`.bundle/config` 的 `BUNDLE_FROZEN: "true"` 与 lock 中 `RUBY VERSION` 与 Gemfile 不同的变体未各自 fixture（前者实现已按非 env 来源覆盖，后者由 spec 的手工断言覆盖）；`show`/`info` 的其余重解通知形态仍待取证。

## 2026-11-15 M7(2)/L157：install 家族未知开关拒绝

参考 oracle（4.0.24，空目录无 Gemfile，首辅实测并复核）：

| 命令 | `--bogus` | 说明 |
| --- | --- | --- |
| `install/update/lock/cache --bogus` | exit 15，stdout 空，stderr `Unknown switches "--bogus"` | Thor 在任何 Gemfile 访问之前拒绝 |
| `install -v` / `--version` | exit 15 + `Unknown switches "-v"` / `"--version"`（后者另带 `Did you mean?  "--verbose"`） | `-v`/`--version` **不在**白名单 |
| `install -h` / `--help` | exit 0，打印 manpage 首行 `bundle-install(1) -- Install the dependencies specified in your Gemfile` | 我方无 manpage（既有已声明偏差），只接受不报错 |
| `cache --all` / `cache --no-prune` | exit 15 + 长的「flag has been removed」说明 | 我方按未知开关报 15（退出码同、文案不同） |

修复前实测（`bin/celerite.exe`，空目录）：`install/update/lock/cache --bogus` 全部 **exit 10 `Could not locate Gemfile`**（`update` 另多一行 `[DEPRECATED] …`）——开关被静默忽略；`install --local`/`lock --print` 等已知开关同样只是继续到 Gemfile 查找。

实现：复用既有 `unknown_switch_tokens`/`reject_unknown_switches`（`src/celerite/cli/commands.cr`），新增四组白名单常量并在各命令入口**任何 Gemfile/frozen 处理之前**调用，未知 token 保留 `=值` 原文、多枚 `", "` 连接、返回 15。白名单：

- 公共：flags `-h --help --verbose --no-color --quiet`；values `--retry --jobs -j --gemfile --lockfile`
- `install`：`--local --prefer-local --full-index --standalone --no-cache --no-lock --force --redownload --path --without --with`；values 另加 `--target-rbconfig --cooldown`
- `update`：`--all --local --prefer-local --full-index --standalone --no-cache --no-lock --force --redownload --patch --minor --major --pre --strict --conservative --system --binstubs --clean --ruby --bundler --path --without --with`；values 另加 `--group -g --source --trust-policy -P --shebang --cooldown`
- `lock`：`--local --full-index --print --normalize-platforms --add-checksums --patch --minor --major --pre --strict --conservative --update --bundler --ruby --path --without --with`；values 另加 `--add-platform --remove-platform --source --trust-policy -P`
- `cache`（含 `pack`/`package` 别名）：`--no-install --all-platforms --force --redownload --no-cache --local --path --without --with`；values 另加 `--cache-path`

**已接受但语义未逐一复核**（本轮只做拒绝，未实现/未验证其行为）：`--jobs/-j`（无线程并行）、`--full-index`、`--no-cache`、`--binstubs`、`--clean`、`--system`、`--strict`、`--trust-policy/-P`、`--shebang`、`--target-rbconfig`、`--patch/--minor/--major/--pre`、`--update`、`--add-checksums`。

已声明偏差：`--path`/`--without`/`--with` 在 4.0.24 是「已移除」报错（exit 15）、2.7.x 仅告警（exit 10），我方实现其语义并接受（三态差异记录于此）；`cache --all`/`--no-prune` 我方报 `Unknown switches` 而非参考的 removed-message（退出码同为 15）；`Did you mean?` 建议行未实现；`--no-color`/`--retry` 触发的 `Bundler version …` 版本头我方不打印；`--help` 无 manpage（exit 10）。

验证：新 spec `spec/m7_install_family_switches_spec.cr` **7 examples, 0 failures**（四条命令的 exit 15 逐字消息、`=值` 与多枚连接、`-v`/`--version` 拒绝、已知开关落 Gemfile 查找 exit 10、`--path/--without` 仍受理、`pack` 别名）；差分 `unknown-switch-install/update/lock/cache`（无 Gemfile，各 `<cmd> --bogus`）4.0.24 与 2.7.2 均 `4 passed, 0 failed, 0 skipped`，回归 `unknown-switch-check/list/show` 同轮 7/7 PASS；门禁 format EXIT 0、build --no-codegen EXIT 0、全量 `398 examples, 0 failures, 4 errors`（4 = 既有 `git_source_spec.cr` msys `0xC0000022`）、`git diff --check` EXIT 0、`bash -n` EXIT 0。

未验证：上述「已接受但语义未逐一复核」清单；2.7.2 的 `--path` 告警路径；`cache --all/--no-prune` 的 removed 文案；`--help`/`-h` 的 manpage。

### 2026-11-16（补漏与 `--gemfile`/`--lockfile` 真生效）

**A 类补漏（白名单）**：`--trust-policy`/`-P` 加入 `install` 的带值白名单；`--cooldown` 加入 `lock`/`cache`；短开关粘连只接受 `-j<数字>`（`-j2`），`-gfoo`/`-PLowSecurity` 仍判未知（参考也是 exit 15）；`--lockfile` 只属于 `install`/`lock`，`update`/`cache` 传它参考也是 exit 15。

**B/C 类（真生效）**：`--gemfile`/`--lockfile` 现在通过临时 `ENV["BUNDLE_GEMFILE"]`/`ENV["BUNDLE_LOCKFILE"]` 生效，`ensure` 精确还原（原值 nil 则删除）；实测 `lock --gemfile=Custom.gemfile` 写 `Custom.gemfile.lock` 且 exit 0、`install --lockfile=Custom.lock` 写 `Custom.lock` 且 exit 0，与参考一致；差分夹具 `gemfile-flag-install` 双 profile PASS。`lock --gemfile=<missing>` 现为 `GemfileNotFound`（exit 10）：我方 stderr 两行绝对路径 + `not found`，路径经 `.gsub('\\', "/")` 归一为正斜杠，与参考**逐字节一致**（首辅用 `od` 核对 `C:/Users/...` 前缀），修复前为 exit 1 + 桥泄漏的 `No such file or directory @ rb_sysopen`；install/update/cache 该场景仍 exit 1（参考 install 还会吐 ERROR REPORT 崩溃转储，我方单行消息）。

**逐开关对拍（ref vs cel exit，空目录、隔离 HOME，`timeout 20`）**：
```
install -j2                        ref=10 cel=10 ok
install --trust-policy=LowSecurity ref=10 cel=10 ok
install -PLowSecurity              ref=15 cel=15 ok
install --local                    ref=10 cel=10 ok
install --prefer-local             ref=10 cel=10 ok
install --cooldown 3               ref=10 cel=10 ok
install --gemfile Missing.gemfile  ref=1  cel=1  ok
install --lockfile Custom.lock     ref=10 cel=10 ok
install -v / --version             ref=15 cel=15 ok
install --help / -h                ref=0  cel=10 MISMATCH（无 manpage）
update -gfoo                       ref=15 cel=15 ok
update -g foo / --all              ref=10 cel=10 ok
update --lockfile=Y                ref=15 cel=15 ok
update --gemfile=Missing.gemfile   ref=1  cel=1  ok
lock --cooldown=5 / --print        ref=10 cel=10 ok
lock --lockfile=Y                  ref=10 cel=10 ok
lock --gemfile=Missing.gemfile     ref=10 cel=10 ok（本轮已对齐）
cache --cooldown=5 / --no-install  ref=10 cel=10 ok
cache --lockfile=Y                 ref=15 cel=15 ok
cache --gemfile=Missing.gemfile    ref=1  cel=1  ok
```

**全量 spec（测量说明）**：在复用 HOME（`home-g35c`）下曾得 `401 examples, 5 failures, 4 errors`（`spec/cli_spec.cr:57/74/195/222/234` 的 `Expected: 1 got: 0`，共享 HOME 已装 json_pure 造成的伪影）；用新建 HOME（本轮 `home-g35x`）复跑得 `402 examples, 0 failures, 4 errors`（4 = 既有 `git_source_spec.cr` 的 msys `0xC0000022`），**不是产品缺陷**。

**已声明偏差**：`--help`/`-h` 接受但无 manpage；`--path/--without/--with` 三态保持现状；removed-flag 文案差异（`install --binstubs/--clean/--deployment/--frozen/--no-prune/--system/--shebang`、`cache --all/--no-prune/--frozen` 参考为「已移除」长文案，我方 `Unknown switches`，退出码同为 15）。

**负对照（首辅亲做，同一负对构建同时关闭两处行为）**：把 `run_install` 的 reject 改为 `if code = (nil if true)`、把 `with_gemfile_overrides` 的 `ENV["BUNDLE_GEMFILE"] = gemfile if gemfile` 改为 `if gemfile && false`，重建 `bin/celerite-neg.exe` 后：
```
FAIL unknown-switch-install (install --bogus)
      exit code: reference=15 celerite=10
    < Unknown switches "--bogus"
    > Could not locate Gemfile
FAIL gemfile-flag-install (install --gemfile=Custom.gemfile)
      exit code: reference=0 celerite=10
      stderr differs: 0a1 > Could not locate Gemfile
      project tree differs: Only in SANDBOX/project: Custom.gemfile.lock
differential (4.0.24): 0 passed, 2 failed
```
还原两处源码（`edit`）后重建并复跑：`PASS unknown-switch-install (exit=15)`、`PASS gemfile-flag-install (exit=0)` → `3 passed, 0 failed`；`Select-String 'negative-control'` 在 `src/` 无残留。

**门禁（新建 HOME/TEMP）**：format --check EXIT 0；build --no-codegen EXIT 0；`spec/m7_lock_gemfile_missing_spec.cr + spec/m7_install_family_switches_spec.cr` `11 examples, 0 failures`；全量 `402 examples, 0 failures, 4 errors`；`git diff --check` EXIT 0。未验证：20s 超时子集外的其余开关、真实 manpage、removed-flag 文案逐字。

## 2026-11-16 M7(8)/L161：`script/upstream-specs` 默认真实驱动 + 自动失败分桶

**改动**（`script/upstream-specs`，+77/-4）：①`script/upstream-specs-celerite-override.rb` 改为**默认加载**，`CELERITE_BUNDLE_HELPER_OVERRIDE=0` 才退回「上游 binstub、不驱动 celerite」的基线；②rspec 追加 JSON formatter 到 `.upstream-specs/rspec-output.json`，脚本用 `ruby -rjson` 逐失败例分桶写入报告；③报告新增 `real-drive: <n> celerite invocations`（0 时打印 `WARNING: NOT driving celerite`）；④桶条目分隔符与标题改用 ASCII，保证报告全 ASCII。

**首辅实测**（`bin/celerite.exe` 按 HEAD `ce91721` 重建，`CELERITE_SKIP_TEST_DEPS=1`，每轮全新 HOME/TEMP）：

| 运行 | summary | real-drive | 桶 |
| --- | --- | --- | --- |
| 默认 | `64 examples, 55 failures`（9 通过） | **48** | artifice 34 / network-policy 1 / low-il-shm 8 / missing-gem-files 11 / fetch-failed 1 / product 0 |
| `CELERITE_BUNDLE_HELPER_OVERRIDE=0` | `64 examples, 62 failures` | 0 + WARNING | test-deps-skipped 50 / missing-gem-files 12 / product 0 |

**产品差异在真实上游用例中的状态**（失败清单不含即通过）：`:1154`（absolute→relative `remote: foo`）通过；`:2410`/`:2436`（conflict markers）通过；`:2088` 区段（incorrect deps 保留锁定版本）通过；`:1882`（no specs 重解）仍失败，原因是 `Could not reach host gem.repo4`（上游进程内 artifice 端点，外部二进制不可达），**非断言差异**，该语义由差分夹具 `lock-missing-dependency-edges` 覆盖。

**环境/夹具桶判定**：`Could not reach host`（进程内 artifice）34；`HTTP 403`（出口策略）1；`0xC0000022`/`NtCreateDirectoryObject`（Low-IL，见「M7(5)/M7(8) 环境失败根因」节）8；`Errno::ENOENT`/`does not exist!`/`No such file or directory @ rb_sysopen`（`tmp/2.1/gems/remote2` 夹具缺 gem）11；`Fetching …` 后失败 1。基线跑的 50 条 `env:test-deps-skipped` 是 `install_test_deps` 被跳过导致的 `sinatra/base (LoadError)` 链。

**门禁**：`bash -n script/upstream-specs` EXIT 0、`git diff --check` EXIT 0；本轮未改 `src/`（`git diff --stat` 仅 `script/upstream-specs` 与 docs），故不重跑 format/build/spec。

**未验证 / 仍阻塞**：`install_test_deps` 完整链（装 sinatra/artifice 后才可能让 34 条 artifice 桶转入断言阶段）；真实 gem 源（`HTTP 403`）；git 源用例（Low-IL）；`:1882` 断言级证据；`UPSTREAM_REV=v2.7.2` 在该 rev 布局下无 bundler spec 族（既有记录，仍不可执行）。

## 2026-11-16 M7(4)：TLS 信任库默认 CA 与 CA 目录（`ssl_ca_cert`）

参考锚点（bundler-4.0.24）：`lib/bundler/fetcher.rb:349-359`——`ssl_ca_cert = Bundler.settings[:ssl_ca_cert] || Gem.configuration.ssl_ca_cert`；有值且 `File.directory?` → `store.add_path`（CApath，c_rehash 布局），否则 `store.add_file`；两者都没有 → `store.set_default_paths`（OpenSSL 默认信任库，遵守 `SSL_CERT_FILE`/`SSL_CERT_DIR`）。

修复前缺陷：`src/celerite/downloader.cr` 与 `src/celerite/compact_index/cache.cr` 建 TLS 上下文时只在显式配置了 `ssl_ca_cert` 才 `ctx.ca_certificates = ca`，未配置时**完全不加载任何 CA**；且把目录当文件传入会得到 `SSL_CTX_load_verify_locations: error:80000005:system library::Input/output error`。实测证据（本机）：

1. 默认上下文连自签服务：`OpenSSL::SSL::Error: SSL_connect: error:0A000086:SSL routines::certificate verify failed`（经产品路径表现为 `CertificateFailureError`，exit 17）。
2. 仅 `set_default_verify_paths` 且未设 `SSL_CERT_FILE`：同样失败（本机 Crystal/msys OpenSSL 无内置默认 CA）。
3. 设 `SSL_CERT_FILE=<Ruby 自带 cert.pem>` + `set_default_verify_paths`：参考语义下应成功；本机直接调用**仍失败**（该 Crystal/OpenSSL 构建的默认路径不读该环境变量），显式 `ca_certificates=<pem>` 才成功。
4. rails-min 真机 `celerite install` 稳定 exit 17（`Could not verify the SSL certificate for https://rubygems.org/.`）即由第 1 条导致。

实现（`src/celerite/tls.cr` 新增 `TLS.configure_trust_store(ctx, ca_cert : String?)`）：空值 → `ctx.set_default_verify_paths`（与参考 `set_default_paths` 一致），并在本机构建上额外把 `ENV["SSL_CERT_FILE"]` 显式装入（实测补偿，见未验证项）；目录 → `ctx.ca_certificates_path = path`；文件 → `ctx.ca_certificates = path`。加载失败不 rescue（与参考一致）。`downloader.cr:183-184` 与 `compact_index/cache.cr:157-158` 改为调用该 helper，`ssl_verify_mode`（NONE/PEER）与 `TLS.configure_client_certificate` 逻辑未变。

新增 `spec/m7_tls_trust_store_spec.cr`（4 例，全离线本地 TLS 服务）：①空 `ssl_ca_cert` + `SSL_CERT_FILE=ca.pem` → 成功；②空 `ssl_ca_cert` + 无 `SSL_CERT_FILE` → 失败（负例，防恒真）；③显式 PEM → 成功；④显式 CA 目录（`spec/fixtures/tls/ca-dir/481f80ed.0`，名字由 `openssl x509 -in spec/fixtures/tls/ca.pem -hash -noout` 实算）→ 成功。每例在 `ensure` 中精确还原 `SSL_CERT_FILE`。修复前：`4 examples, 0 failures, 2 errors`（①CertificateFailureError、④`SSL_CTX_load_verify_locations` 目录当文件）；修复后：`4 examples, 0 failures`。

门禁（新建 HOME/TEMP `home-g37`/`spec-tmp-g37`）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；全量 `406 examples, 0 failures, 4 errors`（4 = 既有 `spec/git_source_spec.cr` msys `0xC0000022`）；`git diff --check` EXIT 0。

未验证 / 限制：Windows 系统证书库（SCHANNEL/`certmgr`）不参与 OpenSSL 信任判断；CApath 需 c_rehash 哈希文件名，未做目录自动 rehash；代理 CONNECT 隧道复用同一上下文（未单独差分）；`SSL_CERT_FILE` 的显式补偿是本机构建特有行为，参考环境由 OpenSSL 默认路径直接生效；`Gem.configuration.ssl_ca_cert`（`~/.gemrc`）未读取（既有已声明偏差）。

### 2026-11-16 续（M7(4) 收尾 / M7(9) 解锁）：默认 CA 的真实网络取证与 bridge 长操作截止时间

**参考语义的落地**（`bundler/fetcher.rb:349-359`）：`ssl_ca_cert` 是目录 → `store.add_path`（CApath，c_rehash 布局），是文件 → `store.add_file`，都没有 → `store.set_default_paths`。`src/celerite/tls.cr` 的 `TLS.configure_trust_store` 已按此实现（文件 / 目录 / 默认三路），`downloader.cr` 与 `compact_index/cache.cr` 统一调用。

**首辅复跑与更正**（子代理口述「`set_default_verify_paths` 不读 `SSL_CERT_FILE`」只对进程内赋值成立）：

1. 继承环境（父进程设 `SSL_CERT_FILE` 后启动子进程）→ OpenSSL 默认路径**会**读取该变量：`crystal run` 探针连 `https://rubygems.org` HEAD `/versions` 得 `status=200`；未设时同探针 `SSL_connect: error:0A000086:SSL routines::certificate verify failed`。
2. 进程内 `ENV["SSL_CERT_FILE"] = …`（spec 场景）→ 本机构建上 OpenSSL 的 `set_default_paths` 读不到（Crystal 的 `ENV[]=` 走 `SetEnvironmentVariableW`，不更新 CRT `environ`），故 helper 在默认路径之后**显式**再装一次该文件；注释与本节均已按此更正。
3. 真实网络取证（`celerite` 二进制，非探针）：`.tmp-scratch/https37/project`（`source "https://rubygems.org"` + `gem "json_pure", "2.8.1"`，`BUNDLE_PATH` 指向项目内）——设 `SSL_CERT_FILE=C:\Ruby40-x64\lib\ruby\4.0.0\etc\ssl\cert.pem` 后 `celerite lock` **exit 0**，输出 `Writing lockfile to …` / `Fetching gem metadata from https://rubygems.org/.` / `Resolving dependencies...`，锁文件含 `json_pure (2.8.1)` 与 `PLATFORMS x64-mingw-ucrt`；**不设**该变量时同一命令 **exit 17** 并打印参考同形四行提示（`Could not verify the SSL certificate for https://rubygems.org/.` + `There is a chance you are experiencing a man-in-the-middle attack…`）。→ 此前 rails-min 的 exit 17 属「本机 OpenSSL 默认 CA 库缺失 + 未配置 CA」，现已可配置通过。
4. 负对照（首辅亲做）：删掉 helper 里的显式 `SSL_CERT_FILE` 装载 → `spec/m7_tls_trust_store_spec.cr:70` 报 `CertificateFailureError`（`4 examples, 0 failures, 1 errors`）；恢复后 4/0。

**bridge RPC 截止时间对长操作不成立**（本轮实测发现的产品缺陷）：

- 证据：rails 8.0.2 真机 `celerite install`（`.tmp-scratch/rails37`）耗时 **1112.4s**，解析/下载/安装全部依赖后，在 `bigdecimal 4.1.3 with native extensions` 处失败，错误 `bridge request timed out after 30.0s`。参考在进程内编译原生扩展，**没有 RPC 截止时间**。
- 修复（`src/celerite/bridge/client.cr`）：`request(op, payload, limit : Time::Span? = @timeout)`、`read_response(limit)`；`build_extension` 与 `exec_plugin_hook` 传 `limit: nil`（无限等待，与参考一致），其余快速元数据调用保留 30s 安全网。
- 回归 spec：`spec/m7_bridge_long_operations_spec.cr`（2 例，配合桩服务 `spec/fixtures/bridge/slow_server.rb`：除握手外每次请求睡 1.2s；客户端截止设 0.2s）——①`build_extension` 成功（旧实现必抛 `bridge request timed out after 0.2s`）；②`write_installed_spec`（未豁免）仍按 0.2s 超时。
- 负对照（首辅亲做）：把 `build_extension` 的 `limit: nil` 去掉 → `spec/m7_bridge_long_operations_spec.cr:37` 报 `bridge request timed out after 0.2s`；恢复后 2/0。

**Rails 规模回归的分段结论（`docs/roadmap.md` L162 的输入）**：

| 轮次 | 环境 | 结果 |
| --- | --- | --- |
| #1 | 仅 TLS 未修（未设 `SSL_CERT_FILE`） | 早期即 exit 17（证书校验失败） |
| #2 | 设 `SSL_CERT_FILE`、PATH 无 msys `make` | 1112.4s 后卡在 `bigdecimal` 原生扩展：`bridge request timed out after 30.0s` |
| #3 | 同上 + PATH 追加 `C:\Ruby40-x64\msys64\usr\bin` | 148.6s（复用已装 gem）后卡在 `make: *** [Makefile:275: bigdecimal-x64-mingw-ucrt.def] Error 127`，根因 `C:\Program Files\Git\usr\bin\echo.exe: *** fatal error - NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-…): 0xC0000022`（msys 共享内存被 Low IL 拒，见 2026-11-15 的 Low-IL 结论） |

→ Rails 规模 e2e 的**产品侧**阻塞已清除（TLS 可配置通过、长编译不再被 30s 截断）；剩余阻塞是**本机精简环境**：msys `sh.exe`/`echo.exe` 在 Low IL 下无法创建共享内存对象，任何走 msys 工具链的原生扩展都会 `0xC0000022`。该结论与 `spec/git_source_spec.cr` 的 4 个既有 error 同源，属环境而非产品。

**门禁（首辅亲跑，新建 HOME `home-g37b/g37c`）**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅 2 条既有 `File.executable?` deprecation）；全量 `crystal spec --link-flags <shim>` **408 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` msys `0xC0000022`；上轮 402/0/4，+4 新例 +2 TLS/桥例）；`git diff --check` EXIT 0。

**未验证 / 限制**：Windows 系统证书库（SCHANNEL）不参与 OpenSSL 信任判断；CApath 需 c_rehash 哈希布局（未做目录自动 rehash）；代理 CONNECT 隧道复用同一上下文未单独差分；`Gem.configuration.ssl_ca_cert`（`~/.gemrc`）仍未读取（既有已声明偏差）；原生扩展完整编译链路仍被 Low-IL 环境阻塞。

### 2026-11-16（M7(5)：`glob:` 锁文件行与 GIT 源选项顺序）

**参考语义**（bundler-4.0.24）：`lib/bundler/source/path.rb:14` `DEFAULT_GLOB = "{,*,*/*}.gemspec"`；`:45-49` `to_lock` 输出 `PATH` / `  remote: <lockfile_path>` /（非默认 glob 时）`  glob: <@glob>` / `  specs:`；`lib/bundler/source/git.rb:53-61` 输出 `GIT` / `  remote:` / `  revision:` / `%w[ref branch tag submodules]` 中存在者 /（非默认 glob 时）`  glob:` / `  specs:`。

**修复前缺陷**：`Resolution#generated_lockfile` 的 PATH 段只写 `remote`（`glob:` 丢失）；GIT 段选项顺序为 `branch, tag, ref`（参考是 `ref, branch, tag`），且同样不写 `glob:`。

**参考 oracle（首辅实测 `bundle lock` 原文）**：

- PATH monorepo（`path "vendor/mono", glob: "gems/*/*.gemspec" do gem "mono_a" end`）：`PATH` / `  remote: vendor/mono` / `  glob: gems/*/*.gemspec` / `  specs:` / `    mono_a (0.1.0)`。
- GIT glob（`gem "alpha", git: "./mono", glob: "gems/*/*.gemspec"`）：`GIT` / `  remote: ./mono` / `  revision: 1e9fd93…` / `  glob: gems/*/*.gemspec` / `  specs:` / `    alpha (0.1.0)`。

**实现**：`src/celerite/resolution.cr` 新增 `DEFAULT_GLOB`、`Resolution.git_lock_options(remote, info)`、`Resolution.path_lock_options(remote, info)`（纯函数，键顺序与默认值抑制按参考）；`generated_lockfile` 的 GIT/PATH 两段改为调用它们，`lockfile_path_for` 相对化与 PATH `group_by` 行为不变。

**证据**：

- `spec/m7_source_lock_options_spec.cr`（新增，5 例）：PATH 非默认 glob → `["remote","glob"]`；PATH 无 glob → `["remote"]`；PATH 默认 glob → `["remote"]`；GIT 全设 → `["remote","revision","ref","branch","tag","submodules","glob"]`（`revision` 为 `""`、`submodules` 为 `"true"`）；GIT 仅 remote → `["remote","revision"]`。`5 examples, 0 failures, 0 errors`。
- 差分 `fixtures/differential/path-glob-monorepo`（`lock`，`file-contains` 两条）：4.0.24 `PASS (exit=0)`、2.7.2 `PASS (exit=0)`；同轮回归 `lock-path-absolute-relative`、`install-fresh`、`install-local` 全 PASS。
- 负对照（首辅亲做）：把 `path_lock_options` 的 glob 分支改成恒不输出（`unless glob == DEFAULT_GLOB || true`）并重建 → `FAIL path-glob-monorepo (lock)`，原文 `file-contains differs (Gemfile.lock): needle=  glob: gems/*/*.gemspec`、`0 passed, 1 failed`；`edit` 还原后重建复绿。
- 门禁（首辅亲跑，新建 HOME `home-g38`/`g38v`/`g38f`/`g38s`）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅 2 条既有 `File.executable?` deprecation）；全量 `crystal spec --link-flags <shim>` **413 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` msys `0xC0000022`；上轮 408/0/4，+5 新例）；`git diff --check` EXIT 0。

**未验证 / 限制**：GIT `glob:` 只有纯函数单测与参考 oracle，没有差分夹具——本机 celerite 子进程的 msys `sh.exe` 在 Low IL 下 `0xC0000022`，`git-glob` 仍在克隆阶段失败（环境，非产品）；`glob:` 与非默认相对化/绝对路径的组合、`cache`/`package` 对 monorepo glob 源的复制行为未覆盖。

### 2026-11-16（M7(5)：私有 source 的鉴权失败映射）

**参考语义**（`bundler-4.0.24/lib/bundler/fetcher/downloader.rb:70-73`、`fetcher.rb:45-72`）：401 且请求未带凭据 → `AuthenticationRequiredError`；401 且带凭据 → `BadAuthenticationError`；消息里的 `<host>` 是**主机名**（不是完整 URL），末行的环境变量名是 `BUNDLE_` + `Settings.key_for(host)`。所有 `HTTPError` 子类 status 17、`wrap: true`。

**本地 oracle（首辅亲测；401 由 node 服务 `127.0.0.1:8799` 要求 Basic `alice:s3cret`，403 由 `127.0.0.1:8801` 恒返回且无 `WWW-Authenticate`；Gemfile `source "http://127.0.0.1:<port>/"` + `gem "json_pure"`，命令 `lock`）**：

| 场景 | 参考 stdout | 参考 stderr | 参考 exit | celerite（修复后） |
| --- | --- | --- | --- | --- |
| 401 无凭据 | `Writing lockfile to <abs>` | 四行：`Authentication is required for 127.0.0.1.` / `Please supply credentials for this source. You can do this by running:` / `` `bundle config set --global 127.0.0.1 username:password` `` / `` or by storing the credentials in the `BUNDLE_127__0__0__1` environment variable `` | 17 | stdout 相同、stderr 四行逐字相同（行尾 LF vs CRLF）、exit 17 |
| 401 凭据错误（`alice:wrong`） | 同上 | 两行：`Bad username or password for 127.0.0.1.` / `Please double-check your credentials and correct them.` | 17 | 相同 |
| 403（无 `WWW-Authenticate`） | 同上 | 与「401 无凭据」四行逐字相同 | 17 | 相同 |
| 正确凭据（`alice:s3cret`） | 记日志三行 | 空 | 0 | 0，锁文件逐字一致 |

即：参考在失败前**已**打印 `Writing lockfile to …`（stdout），随后才因取索引失败退出——这一点由差分夹具 `lock-platform-variant`/`lock-path-absolute-relative` 的参考首行佐证。

**修复前缺陷**：`compact_index` 把非 2xx 原样返回，401 被上层当作空索引 → `celerite lock` exit **7** + `Could not find gem 'json_pure' in rubygems repository http://127.0.0.1:8799/ or installed locally.`；`Downloader` 对 401 只 `raise GemNotFoundError…(HTTP 401)`。同一台机器上参考 bundler 的凭据链路本就可用（我方也不缺凭据读取：项目 `.bundle/config` 的 `BUNDLE_HTTP://…` 生效）。

**实现**：`src/celerite/errors.cr` 新增 `AuthenticationRequiredError`/`BadAuthenticationError`/`AuthenticationForbiddenError`（均 `status_code 17`、`wrap? true`；前两者消息逐字照参考，host + `Config.key_for(host)`；第三个保留参考文案但本轮未接线——实测 403 走的是 AuthenticationRequired 文案）；`src/celerite/compact_index/cache.cr` 的 `HttpFetcher#perform` 在 `HttpTransport.get` 之后映射 401（有 `@user`/`@password` 或 URI userinfo → Bad，否则 Required）与 403（→Required），并把三个鉴权错误在 `call` 的重试 `rescue` 之前直通；`src/celerite/downloader.cr` 的 `download_to` 在 200 分支后、3xx 之前同样映射，重试 `rescue` 之前直通。

**证据**：
- 修复前（`git stash` 只回滚两个 mapping 文件后跑新 spec）：`4 examples, 4 failures, 0 errors, 0 pending`——三条 `Expected: 17 got: 7`，一条 `Expected Celerite::AuthenticationRequiredError`。
- 修复后：`spec/m7_authentication_errors_spec.cr` **4 examples, 0 failures**；与 `spec/compact_index/http_fetcher_spec.cr` 联跑 **9 examples, 0 failures**（后者原先断言「401 返回原始 response」，按新契约改为 `expect_raises(AuthenticationRequiredError)`——行为变更的必要更新，非凑绿）。
- 端到端对照（首辅亲跑，ref/cel 各自独立项目与 HOME）：401 无凭据 / 401 错误凭据 / 403 三场景的 stdout、stderr、exit 全部一致（见上表）。
- 负对照（首辅亲做）：把 `HttpFetcher#perform` 的 `if status == 401` 与 `Downloader#download_to` 的 401 分支改成 `if false`/`elsif false` → `4 examples, 3 failures`（两条 401 用例与 Downloader 用例失败；403 分支未禁用故该例仍通过），`edit` 还原后 4/0。**过程教训**：负对照第一次误用 `Set-Content -Encoding UTF8` 写源码，给 `cache.cr`/`downloader.cr` 加了 UTF-8 BOM（`EF BB BF`），已按字节剥离并复核 `format`/`build` 通过——改源码只能用 `edit`。
- 门禁（首辅亲跑，新建 HOME/TEMP）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅 2 条既有 `File.executable?` deprecation）；全量 `crystal spec --link-flags <shim>` **417 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` msys `0xC0000022`；上轮 413/0/4，+4 新例）；`git diff --check` EXIT 0；差分 4.0.24 `install-fresh`/`lock-path-absolute-relative`/`lock-platform-variant` → `3 passed, 0 failed`，2.7.2 `install-local`/`lock-missing-dependency-edges` → `2 passed, 0 failed`。

**已声明偏差 / 未验证**：403 的参考文案实测是 `AuthenticationRequiredError`（不是 `AuthenticationForbiddenError` 的 "Access token…"），故后者保留但未接线；gem 下载路径的 403 无参考 oracle；`~/.gemrc`/`Gem.configuration` 凭据来源未覆盖；401 带 `WWW-Authenticate: Basic` 的变体、代理 CONNECT 后的 401、以及 `install`/`update`/`cache` 的鉴权失败只由 `Downloader`/`HttpFetcher` 单测覆盖，未逐命令差分；stderr 行尾 LF vs 参考 CRLF 为既有已声明差异。

## 2026-11-16（M7(5)：锁文件写入保留既有 CRLF 行尾）

参考锚点（bundler-4.0.24）：`definition.rb:428-434`——写锁文件前若磁盘文件已存在且内容含 `"\r\n"`，把生成内容 `gsub(/\n/, "\r\n")` 后再写；随后 `File.open(p, "wb") { |f| f.puts(contents) }`。即参考**保留既有锁文件的行尾风格**，新建文件保持 LF。

修复前我方（首辅 probe `.tmp-scratch/crlf40`，Gemfile `source "file:///<repo>/fixtures/gem-index"` + `gem "json_pure"`）：预置 CRLF 锁文件（14 处 `\r\n`）跑 `celerite lock` → exit 0，但文件 **206 字节、0 个 CRLF、14 个 LF**；同一 scenario 参考为 **220 字节、14 个 CRLF、0 个孤立 LF**。全新工程（无锁文件）两侧同为 LF（321 字节、17 个 LF，逐字节一致）。

实现：新增 `src/celerite/lockfile/writer.cr` 的 `Celerite::Lockfile.write(path, contents, preserve_crlf = true)`——`File.file?(path) && File.read(path).includes?("\r\n")` 时用 `gsub(/(?<!\r)\n/, "\r\n")` 只提升孤立 LF（不产生 CRCRLF），否则原样写。`File.read` 在 Crystal 是二进制读，不做 CRLF 翻译。三处调用点改为 `Lockfile.write(definition.lockfile_path, text, preserve_crlf: preserve_lockfile_crlf?)`：`src/celerite/cli/commands.cr`（`lock`）、`src/celerite/cli/commands_install.cr`（install/update 写锁）、`src/celerite/cli/commands_surface.cr`（surface 写锁）；三文件各补 `require "../lockfile/writer"`。未改动其它写入行为（无临时文件、无 fsync）。

profile 门控：`Commands.preserve_lockfile_crlf?`（`commands.cr:320`）= `!(ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24").starts_with?("2.")`。首辅 oracle（同一 CRLF 锁文件、`ruby …/bundler-<v>/exe/bundle lock`）：**4.0.24 → 220 字节 / 14 CRLF / 0 孤立 LF；2.7.2 → 206 字节 / 0 CRLF / 14 LF**（2.7.x 在 Windows 上以文本模式读锁文件，`definition.rb:383-385` 的 `match?("\r\n")` 不触发），故 2.x 归一是参考行为而非我方偏差。我方端到端逐命令对拍（`lock`/`install`/`update`，新建 HOME、CRLF 预置）：无 profile 或 `4.0.24` → 220/14/0（`update` 212/13/0）；`2.7.2` → 206/0/14，均与参考同字节；LF 输入 → 206 字节、SHA256 前 16 位与参考一致（`BC07922249425C84`）。

新增 `spec/m7_lockfile_line_endings_spec.cr`（4 例，离线，`with_project` + `run_cli(["lock"])`）：①预置 CRLF 且 `specs:` 为空的 `Gemfile.lock` → 重写后含 `json_pure (2.8.1)`、`\r\n` 数 > 0、无孤立 LF，且归一化内容与删除后重新生成的 LF 版本一致（比较时剔除 `CHECKSUMS` 段，因为是否记录校验和取决于运行路径）；②预置 LF 锁文件 → 重写后仍无 CRLF；③无锁文件 → 新文件全 LF；④CRLF 锁文件已最新再跑一次 → 内容逐字节不变且仍 CRLF。

装具：`script/differential` 新增 `file-crlf` 标记（每行一个项目文件路径，读两侧沙箱原始字节，断言至少 1 个 `\r\n` 且无孤立 LF，失败打印 `file-crlf differs (<path>, <side>): missing CRLF` / `lone LF at byte <n>`）。新夹具 `fixtures/differential/lock-preserve-crlf/`：`Gemfile`（`source "file:///@INDEX_DIR@"` + `gem "json_pure"`）、`Gemfile.lock` 用 CRLF 且 `specs:` 为空（两侧都会重写）、`command` = `lock`、`file-crlf` = `Gemfile.lock`。

**装具修复与实测**：原 `sed` 复制会把夹具 CRLF 统一成 LF（KEEP 沙箱 `ref` 199 字节、CR=0）。已把 `Gemfile`/`Gemfile.lock` 复制抽成 `copy_fixture_text`（先 `sed` 做占位替换，源文件含 CRLF 时再用 bash `while read` + `printf '%s\r\n'` 重写；MSYS `grep` 会自动剥掉 CR，检测改用 `od -tx1` 找 `0d0a`）。修复后 4.0.24：`PASS lock-preserve-crlf (exit=0)`，两侧 `Gemfile.lock` 均 13 个 CR；2.7.2：`PASS`，但两侧均为 LF —— 参考 2.7.x 在 Windows 上以文本模式读锁文件（`definition.rb:383-385` 的 `match?("\r\n")` 不触发），`file-crlf` 标记在 2.x 下改为断言 LF，产品用 `Commands.preserve_lockfile_crlf?` 按 profile 门控（4.x 保留、2.x 归一）。

负对照建议（装具修好后）：把 `Lockfile.write` 退回 `File.write` 重建 `bin`，`lock-preserve-crlf` 应报 `file-crlf differs (Gemfile.lock, cel): missing CRLF` 而 ref 侧通过。

门禁（新建 HOME/TEMP `home-g40`/`spec-tmp-g40`/`ccache-g40`）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0；`spec/m7_lockfile_line_endings_spec.cr` `4 examples, 0 failures`；全量 `421 examples, 0 failures, 4 errors`（4 = 既有 `spec/git_source_spec.cr` Low-IL msys）；`git diff --check` EXIT 0。

未验证 / 限制：装具 CRLF 保真（上）；`bundle install`/`update` 写锁路径的 CRLF 行为只做了同一 `Lockfile.write` 单元级别的推断，未逐命令差分；混行（部分 CRLF、部分 LF）按「含 CRLF 即全 CRLF」处理，参考同规则；BOM 与 UTF-8 编码未验证；`Gemfile.lock` 通过标准输入/`--lockfile` 别名路径未覆盖。

## 2026-11-16（M7(5)：锁文件写入失败的权限错误映射）

- 参考锚点：`bundler/shared_helpers.rb:105-127`（`filesystem_access`：`Errno::EACCES` → `PermissionError.new(path, action)`，其余 `SystemCallError` → `GenericSystemCallError`）、`bundler/definition.rb:436-442`（锁文件写入在 `filesystem_access(file)` 内）、`bundler/errors.rb:94-128`（`PermissionError`：status 23、`action`/`permission_type`/`parent_folder`、`ui.error(..., wrap: true)`）。
- 首辅 oracle（只读 `Gemfile.lock` + `lock`）：参考 exit 23；stdout 三行 `Writing lockfile to <abs>` / `Fetching source index from …` / `Resolving dependencies...`；stderr 三行（80 列折行）：
  `There was an error while trying to write to`
  `` `C:/…/Gemfile.lock`. ``
  `It is likely that you need to grant write permissions for that path.`
- 修复前实测（`bin/celerite.exe lock`，同一只读夹具）：exit 1，stderr `celerite internal error: Error opening file with mode 'w': 'C:\\…\\Gemfile.lock': 拒绝访问。`
- 实现：`src/celerite/errors.cr` 新增 `PermissionError`（消息逐字按参考、路径正斜杠、status 23、`wrap? true`；`:create` 时写父目录短语 `executable permissions for all parent directories and write permissions for `<parent>``）；`src/celerite/lockfile/writer.cr` 捕获 `File::AccessDeniedError` → `PermissionError.new(path, :write)`（不吞 `File::NotFoundError`；成功路径与既有 CRLF 逻辑不变）。
- spec：`spec/m7_filesystem_errors_spec.cr` 4 例——只读锁 → `code == 23`、stdout 含 `Resolving dependencies...`、stderr 与 `word_wrap(message, 80)` 逐字一致；`:create` 父目录短语；`:read`/`:executable` 动作；status/wrap。修复后 `4 examples, 0 failures, 0 errors, 0 pending`。
- 端到端复核（首辅亲跑，`bin/celerite.exe` 重建后，ref/cel 各一独立沙箱 + 独立 HOME）：两侧 **exit 23**；stdout 各 3 行、路径归一后逐字相同；stderr 各 3 行，路径与行尾归一后 `SAME_AFTER_PATH_AND_EOL_NORMALIZE=True`（参考 CRLF、我方 LF，属既有已声明行尾差异，文案逐字一致）。
- 负对照（首辅亲做）：在 `writer.cr` 的 rescue 里加 `raise ex if ENV["CELERITE_NC_PERMISSION"]?` 并置该变量跑 spec → `4 examples, 1 failures, 0 errors, 0 pending`，原文 `Failure/Error: code.should eq(23)` / `Expected: 23` / `got: 1`；移除后复跑 4/0，`Select-String 'negative-control|CELERITE_NC_'` 在 `src/`、`spec/` 无残留。
- 门禁（新建 HOME/TEMP `home-g41c`/`spec-tmp-g41c`/`ccache-g41c`）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen` EXIT 0（2 条既有 deprecation）；全量 `425 examples, 0 failures, 4 errors`（4 = 既有 `spec/git_source_spec.cr` Low-IL msys）；`git diff --check` EXIT 0。
- 未验证：ENOSPC(31)/EROFS(42)/EPERM(43)/ENOTSUP/`GenericSystemCallError`(32)/`TemporaryResourceError` 未映射（本机无法构造）；install 路径的 `:create` 未接线；Windows 只读**目录**不阻止创建，无对应 oracle；`--print`/`--lockfile` 别名路径未覆盖。

## 2026-11-16（M7(5)：`Dir.glob` 绝对模式与 `vendor/cache` 安装）

- 根因（首辅探针定论，子代理初判已被推翻）：`Dir.glob` 在 Windows 上把 `\` 当转义符，因此 `File.join` 拼出的模式（分隔符为 `\`）恒返回空数组；同样内容改用 `/` 分隔则正常匹配。首辅探针（`crystal run` 于 `.tmp-scratch/globcheck/probe.cr`，目录内两个 `.gem`）：`abs_fs_star=2`、`abs_fs_gem=2`、`abs_bs_star=0`、`abs_bs_gem=0`、`join_bs=0`、`rel_star=2`、`children=2`——即「绝对模式一律失效」不成立，失效只与 `\` 有关。受影响调用共 5 处（`src/celerite/resolution.cr` vendor/cache、`src/celerite/cli/commands_surface.cr` 的 gemspec/缓存根/checkout 两处与 gem 根一处）。
- 实现：新增 `src/celerite/glob.cr` 的 `Glob.paths(dir, pattern)`——目录路径先 `gsub('\\','/')`，`Dir.children` 列目录、`File.match?(pattern, basename)` 匹配、`File.join` 回拼并排序；只接受 basename 模式（`*.gem`/`*.gemspec`/`<name>-*`/`*`）。替换 5 处调用（`resolution.cr` vendor/cache、`commands_surface.cr` 的 gemspec/缓存根/checkout 枚举；其中 gem 根一处保留 `Dir.glob` 但先 `gsub` 正斜杠）。
- `install --local` 与 `vendor/cache`：`Resolution` 记录 `vendor_cache_paths`（full_name → `.gem` 路径）并提供 `vendor_cache_path`；`Installer#install` 新增 `gem_file` 参数，调用方已有材料化包（下载或 app cache）时不再二次 fetch；`commands_install` 的 pending 循环命中 vendor/cache 时直接使用该文件、**不**排 `Fetching` 事件，并在 install 汇总前按参考打印 `Updating files in vendor/cache`（`vendor/cache` 存在、非 frozen、未传 `--no-cache` 时）。
- 修复前证据（`.tmp-scratch/vprobe`：Gemfile `source "file:///…/fixtures/gem-index"` + `gem "plain-gem"` + `vendor/cache/plain-gem-0.2.0.gem`，该 gem 不在索引）：`celerite install --local` → exit 7、stdout 空、stderr `Could not find gem 'plain-gem' in locally installed gems.`
- spec `spec/m7_vendor_cache_spec.cr`（3 例，均离线）：①`Glob.paths` 对 `File.join` 目录 + `*.gem` 非空（回归）；②`install --local` 从 `vendor/cache` 安装不在索引的 gem → exit 0、无 `Fetching`、安装树含该 gem；③缺 gem 仍 exit 7 并给参考消息。修复后 `3 examples, 0 failures, 0 errors, 0 pending`。
- 差分夹具 `fixtures/differential/install-local-vendor-cache/`（`Gemfile` = `source "file:///@INDEX_DIR@"` + `gem "plain-gem"`、`extra/vendor/cache/plain-gem-0.2.0.gem`、`command` = `install --local`、标记 `installed-tree`）：4.0.24 与 2.7.2 均 `PASS (exit=0)`。装具注意：`CELERITE_DIFF_WORK_ROOT` 必须用 POSIX 形式（`/c/...`），Windows 形式会让沙箱路径带反斜杠、N1 归一化不命中，`installed-tree` 与 stdout 会假失败。
- 首辅独立复核：`Glob.paths` 单测与两条 E2E 用例 3/0/0/0；**负对照**把 `Glob.paths` 换回 `Dir.glob(File.join(dir, pattern)).sort` → `3 examples, 2 failures`（`spec/m7_vendor_cache_spec.cr:71` `Expected: 2 got: 0`、`:85` `Expected: 0 got: 7`），恢复后 3/0；全量 `428 examples, 0 failures, 4 errors`；差分 4.0.24 与 2.7.2 各 `3 passed, 0 failed, 0 skipped`（`install-local-vendor-cache` / `install-local` / `install-fresh`）。
- 顺带取证（本轮未修，登记为下一轮）：`install --local` 解析修复后，扩展编译失败路径已可达——参考 `celerite` 对照为 `exit 5` + 结尾三行 `An error occurred while installing fail-ext (0.1.0), and Bundler cannot continue.` / 空行 / `In Gemfile:` / `  fail-ext`，并**保留**半装目录；我方为 `exit 1` + `extension build failed for …` 且删除半装目录，尚无 `InstallError`（status 5）映射。
- 门禁（新建 HOME/TEMP `home-g42c`/`spec-tmp-g42c`/`ccache-g42c`）：`crystal tool format --check src spec` EXIT 0（先格式化 `spec/m7_vendor_cache_spec.cr`、`src/celerite/glob.cr`）；`crystal build --no-codegen` EXIT 0；全量 `428 examples, 0 failures, 4 errors`（4 = 既有 `spec/git_source_spec.cr` Low-IL msys）；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。
- 未验证 / 限制：真实 `--local` + 多平台 vendor/cache 组合；`--prefer-local` 命中缓存后回退索引的边界；vendor/cache 命中时未做 checksum 校验；`cache`/`package` 对 app cache 的复制与去重；GIT `glob:` 仍受本机 Low-IL msys 阻塞（环境）。

## 2026-11-16（M7(5)：扩展编译失败 → `InstallError` + 半装目录保留）

- 参考语义：`bundler/installer/gem_installer.rb:24-25` 把 `Gem::InstallError`（含 `Gem::Ext::BuildError`）交给 `specific_failure_message`；`:44-49` 组装 `"<异常类>: <消息>\n" + "  " + backtrace.join("\n  ") + "\n\n" + <failure_message>`；`:55-57` `failure_message` = `An error occurred while installing <name> (<version>), and Bundler cannot continue.`；`bundler/installer/parallel_installer.rb:198`/`:214` 再追加 `"\n\n" + require_tree_for_spec`（`:256-275`：首行 `In <Gemfile>:`，逐层 `"  " * (depth+1) + name`，非末项追加 ` was resolved to <version>, which depends on`）；`bundler/errors.rb:21` `InstallError` status 5；`bundler/friendly_errors.rb:31-36` 对 `BundlerError` 一律 `ui.error message, wrap: true`（80 列折行）。
- oracle（4.0.24 与 2.7.2 同构；项目 `source "file:///<repo>/fixtures/gem-index"` + `gem "fail-ext"`，`vendor/cache/fail-ext-0.1.0.gem` 的 `ext/extconf.rb` 抛异常，`BUNDLE_PATH` 指向探针 bundle 目录）：`exit 5`；stdout 两行 `Resolving dependencies...` / `Installing fail-ext 0.1.0 with native extensions`；stderr 61 行——首行 `Gem::Ext::BuildError: ERROR: Failed to build gem native extension.`，其后是 RubyGems 的 dump（`current directory:` / `Gem files will remain installed in <bundle>/gems/fail-ext-0.1.0` / `for inspection.` / `Results logged to <bundle>/extensions/x64-mingw-ucrt/4.0.0/fail-ext-0.1.0/gem_make.out`），**空行**后是回溯，随后 `An error occurred while installing fail-ext (0.1.0), and Bundler cannot` / `continue.` / 空行 / `In Gemfile:` / `  fail-ext`；残留树保留 `gems/fail-ext-0.1.0/{ext/extconf.rb,lib/fail_ext.rb}` 与 `extensions/x64-mingw-ucrt/4.0.0/fail-ext-0.1.0/gem_make.out`，`specifications/` 仍为空（未安装）。
- 修复前（同一探针，`bin/celerite.exe`）：`exit 1`；stderr 只有 `extension build failed for fail-ext-0.1.0: <RubyGems 消息>`（未折行、路径混用反斜杠、无回溯、无结尾段与 `In Gemfile:` 段）；且 `clean_partial` 把 `gems/<full_name>` 与扩展目录一并删除。
- 实现：①`assets/bridge/server.rb:305-310` `op_build_extension` 的 rescue 改为返回 `{"error_class", "error", "backtrace"(完整)}`；②新增 `src/celerite/install_error.cr` 的 `InstallError`（status 5、`wrap? true`）；③`src/celerite/installer.cr` 新增 `property dependency_tree : Proc(String, Array(NamedTuple(name: String, version: String?)))?` 与 `property gemfile_name`，`extension_failure_message`（L214 起，把 gem/扩展目录的 `\` 归一为 `/`、异常消息后**无条件**补一个 `\n` 以复现参考的空行、回溯按 `"  "` 缩进）与 `require_tree_for`；④`src/celerite/resolution.cr` 记录 `@root_dependency_names` 并新增 `dependency_tree_for`（从 Gemfile 顶层依赖 BFS 到失败 gem，不可达时回落单元素路径）；⑤`src/celerite/cli/commands_install.cr:193-195`、`:312-314` 与 `commands_surface.cr:137-140` 接线；⑥扩展失败时**保留**半装目录，只删除 `specifications/<full_name>.gemspec` 以保证 `installed?` 仍为假（其它失败路径保持原清理语义）。
- 证据：`spec/m7_install_failure_spec.cr`（3 例，离线：`spec/fixtures/failing-extension/gems/{fail-ext,fail-parent}-0.1.0.gem` + `vendor/cache`）——直接依赖 `code == 5` + 首行 + `errors.strip.lines.last(4) == ["continue.", "", "In Gemfile:", "  fail-ext"]` + 半装目录存在/`specifications` 无该 gemspec；两级依赖末 5 行为 `  fail-parent was resolved to 0.1.0, which depends on` / `    fail-ext`；非扩展失败（缺 gem）仍 exit 7。
- 首辅复核：**负对照 1** 把 `InstallError#status_code` 改成 1 → `3 examples, 2 failures`（`Expected: 5 got: 1`，`spec/m7_install_failure_spec.cr:82`/`:104`）；**负对照 2** 在 `rescue ex : InstallError` 里补回 `clean_partial` → `3 examples, 1 failures`（`spec/m7_install_failure_spec.cr:91` `File.file?(…/ext/extconf.rb).should be_true` → `false`）。恢复后 3/0/0，`negative-control` 无残留。
- 端到端 A/B（`.tmp-scratch/ext43d`：ref 与 cel 各独立 project/HOME/bundle，`install --local`）：两侧均 `exit 5`；stderr 前 15 行逐行相同（仅沙箱目录名 `ref`/`cel` 不同，等长），末 6 行逐行相同；cel 残留树与参考一致（`gems/fail-ext-0.1.0/{ext/extconf.rb,lib/fail_ext.rb}`、`extensions/…/fail-ext-0.1.0/gem_make.out`、`specifications/` 空）。
- 门禁（新建 HOME/TEMP `home-g43g`/`spec-tmp-g43g`/`ccache-g43`）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；新 spec 3/0/0/0；全量 `crystal spec --link-flags <shim>` **431 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` Low-IL）；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。
- **为什么不做差分夹具**：参考的回溯帧来自 `Bundler::RubyGemsGemInstaller` → `Gem::Installer#build_extensions` → `parallel_installer`（含 `bundler-<ver>/…` 帧），我方 bridge 直接调 `Gem::Ext::Builder#build_extensions`，真实栈以 `rubygems/ext/builder.rb` 开头、随后是 `assets/bridge/server.rb:op_build_extension`。逐字对齐只能靠伪造 Bundler 帧，故**不伪造**：行数 61（参考）vs 42（我方）的差就是回溯块。子代理按补充裁断跑过一次 `install-failing-extension`（4.0.24 与 2.7.2 各 `0 passed, 1 failed`）后删除该夹具，原始行为 `FAIL install-failing-extension (install --local)`；本场景由 spec + 上述 A/B 取证。
- 已声明偏差：①回溯段是本实现真实栈（与参考帧不同）；②bundle 缓存：**2026-11-16 更正**——该论断有误，成功安装时参考与本实现都会把 `.gem` 复制进 `<bundle>/cache/`（同一 A/B 复测两侧均有 `plain-gem-0.2.0.gem`）；真正的差异只在**扩展编译失败**路径（参考不留缓存包、本实现保留），已在「2026-11-16（M7(5)：扩展编译失败后不留 bundle 缓存）」节修正并加断言；③参考 `current directory:` 一行在 80 列下折行受沙箱路径长度影响，我方同样折行，故只在等长沙箱下逐字比对。
- 未验证：gcc/make 失败（非 extconf 异常）、`--target-rbconfig`、多平台扩展目录、`gem_make.out` 内容断言、磁盘满/中断（Ctrl-C）路径的清理行为、`commands_surface.cr` 其余两处 plugin 安装未接 `dependency_tree`（插件 gem 扩展失败只会打印单元素树）、2.7.2 profile 下未单独跑 spec 断言。

## 2026-11-16（M7(2)：`bundle list` 的 `--format`/互斥选项与普通环境分组发现）

- 参考语义（`bundler-4.0.24/lib/bundler/cli/list.rb` 逐行）：校验顺序是 `--only-group`+`--without-group` 互斥（L15）→ `--name-only`+`--paths` 互斥（L17）→ 加载 specs（缺 gem 先 exit 1）→ **最后**校验 `--format`（L31-38）；两类互斥消息单行 exit 15（`` The `--only-group` and `--without-group` options cannot be used together ``、`` The `--name-only` and `--paths` options cannot be used together ``）；非法格式单行 exit 15 且 `option` 与反引号之间**没有空格**（`` Unknown option`--format=bogus`. Supported formats: `json` ``）。`git_version` 来自 `bundler/rubygems_ext.rb:264-267` 的 `" " + revision[0..6]` 再 `strip`（7 字符），非 GIT 源为 `null`。
- oracle（4.0.24）：JSON 为单行 + 换行且键序固定——默认 `{"gems":[{"name":"json_pure","version":"2.8.1","git_version":null}]}`、`--name-only` `{"gems":[{"name":"json_pure"}]}`、`--paths` 在 `git_version` 后追加 `"path":"C:/…/gems/json_pure-2.8.1"`；空 bundle 的 JSON 是 `{"gems":[]}`（人类可读才是 `No gems in the Gemfile`）。2.7.2 参考**没有** `--format`：`--format=json` → `Unknown switches "--format=json"`，`--format json` → `Unknown switches "--format"`。
- 修复前缺陷（两条）：①`list --format=json` 被静默忽略（按人类可读打印），互斥组合也不报错；②**普通用户环境**（没有 `CELERITE_BRIDGE_SERVER`/`CELERITE_REFERENCE_BUNDLER_LIB`）下 `list --only-group development` 输出 `` `development` group could not be found.`` + exit 15，而参考 exit 0 并列出该组 gem。
- 缺陷②的根因：`self.list` 用 `bridge_available?`（`src/celerite/cli/commands.cr:1122`，只看那两个环境变量是否指向存在的路径）给 `lockfile_groups` 与 `filter_locked_specs_by_groups` 加门控；而这两个方法自己就 `Bridge::Client.new` 并在 `rescue` 时安全降级，根本不需要这两个变量。`script/differential:406` 注入 `CELERITE_REFERENCE_BUNDLER_LIB`、既有 spec 全在 `with_bridge_server` 内（如 `spec/m7_installed_discovery_spec.cr:352-364`），因此**装具与 spec 双重掩盖**了这个缺陷。
- 实现：`src/celerite/cli/commands.cr` 的 `self.list` 增加 `--name-only`+`--paths` 互斥；`--format` 两种写法都读、按 profile 门控（2.x 移出白名单）；格式合法性放到缺 gem 检查之后；JSON 用保序 `Hash(String, JSON::Any)` 输出 name/version/git_version(/path)；抽出 `spec_git_version`（GIT 源 `revision[0,7]`，其余 nil）供 JSON 与 `spec_display_name` 共用；新增 `available_groups`（`lockfile_groups` 失败或为空 → `["default"]`），`list` 改为无条件调用它并给 `filter_locked_specs_by_groups` 加 `rescue` 降级（桥缺失时回到旧行为，桥可用时拿真实组）。
- 证据：`spec/m7_list_format_spec.cr` 9 例 + `spec/m7_list_groups_plain_env_spec.cr` 2 例（用已构建的 `bin/celerite.exe` 并临时删除两个 hint 变量，断言 `list --only-group development` 只列 thor 三行 exit 0、`--only-group nope` exit 15 且消息逐字）；差分新增 `list-json`、`list-json-name`、`list-format-invalid`、`list-option-conflict`，与回归 `list-multi-group` 一起在 4.0.24/2.7.2 各 `5 passed, 0 failed, 0 skipped`。
- 首辅独立 A/B（`.tmp-scratch/v44`，ref/cel 独立 sandbox + HOME + BUNDLE_PATH，两条 profile 各跑一遍）：`list`/`--name-only`/`json`/`json --name-only`/`json --paths`/`--format json`/`--name-only --paths`(15)/`--format=bogus`(15)/`--only-group nope`(15)/两个互斥(15)/空 bundle 三态，除下面一条外全部逐字节相同；唯一先前差异是缺陷②，修复后普通环境探针（`.tmp-scratch/plain44`，无任何 `CELERITE_*` 变量）得 `list --only-group development` exit 0 列出 thor、`--only-group nope` exit 15。
- 门禁（首辅亲跑，新建 HOME/TEMP `home-g44v`/`spec-tmp-g44v`/`ccache-g44v`）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；两个新 spec 联跑 **11 examples, 0 failures, 0 errors, 0 pending**；全量 `crystal spec --link-flags <shim>` **442 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL；基线 440/0/4）；`git diff --check` EXIT 0。
- 已声明差异/未验证：①`spec/m7_list_groups_plain_env_spec.cr` 依赖已构建的 `bin/celerite.exe`（`bin/` 不入库），缺失时 `pending!`——门禁流程先 `crystal build` 再跑 spec；②普通环境探针里参考还解析出了宿主已安装的 `thor (1.5.0)`（索引里只有 1.3.2），我方按索引得 1.3.2——**参考解析把本机已安装 gems 纳入候选，我方（非 `--local`/`--prefer-local` 路径）只看索引**，此差异本轮未处理、未 fixture 化；③`--only-group` 与 JSON 组合在普通环境的行为未单独断言；④无 Ruby 环境下桥缺失的降级路径只做了 `rescue` 级联保护，未做端到端断言。

## 2026-11-16（M7(5)：扩展编译失败后不留 bundle 缓存）

- 背景：上一节（扩展编译失败 → `InstallError`）把「从 `vendor/cache` 安装时本实现把 `.gem` 复制进 `<bundle>/cache/`、参考不复制」登记为已声明偏差。本轮用同一 A/B 复测发现**该论断不成立**：成功安装时两侧都复制（`plain-gem-0.2.0.gem` 在 ref 与 cel 的 `<bundle>/ruby/4.0.0/cache/` 中都存在），真正的差异只在**扩展编译失败**路径。
- oracle（`.tmp-scratch/cache45`，Gemfile `source "file:///<repo>/fixtures/gem-index"`，`vendor/cache` 预置对应 `.gem`，`install --local`，ref/cel 各独立 project + HOME + `BUNDLE_PATH`）：
  - 成功（`plain-gem-0.2.0`）：`SUCC_REF exit=0 cache=plain-gem-0.2.0.gem`、`SUCC_CEL exit=0 cache=plain-gem-0.2.0.gem`。
  - 失败（`fail-ext-0.1.0`，`ext/extconf.rb` 抛异常）：`FAIL_REF exit=5 cache=`（空）、`FAIL_CEL exit=5 cache=fail-ext-0.1.0.gem` → 参考在扩展失败后不保留缓存包。
- 根因：`src/celerite/installer.cr#install_file` 在构建扩展**之前**就把 `cache/<full>.gem` rename 到 `@install_root/cache/<full>.gem`（L154-157），而 `rescue ex : InstallError`（L190 起）只删 `specifications/<full>.gemspec`，未删缓存包。
- 实现：`src/celerite/installer.cr` 的 `rescue ex : InstallError` 分支在删 `specifications` 之后、`raise ex` 之前新增删除 `File.join(@install_root, "cache", "#{full_name}.gem")`（存在才删）；半装 `gems/<full>`、`extensions/…` 仍按参考保留，成功路径与 `clean_partial` 未动。
- 证据：`spec/m7_install_failure_spec.cr` 现有 4 例——失败例新增 `File.file?(<gem root>/cache/fail-ext-0.1.0.gem).should be_false`，并新增「`keeps the cached .gem for a successful install`」对照例（`json_pure` 安装 exit 0 且 `<bundle>/ruby/<abi>/cache/json_pure-2.8.1.gem` 存在），防止过度删除。
- 首辅复核：读 diff；`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；该 spec **4 examples, 0 failures, 0 errors**；全量 `crystal spec --link-flags <shim>` **443 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` Low-IL；基线 442/0/4）；`git diff --check` EXIT 0。
- 负对照（首辅亲做）：把删除条件改成 `if false && File.file?(…)` → `4 examples, 1 failures`（`spec/m7_install_failure_spec.cr:95` `Expected: false / got: true`）；`edit` 还原后 4/0，`negative-control` 无残留。
- 端到端 A/B（`.tmp-scratch/cache45b`，等长 `failref`/`failcel` 沙箱）：两侧 `exit=5 cache=[] gems=[fail-ext-0.1.0] specs=[]` —— 三处残留树逐项一致。
- 未验证：其它失败类型（校验失败、网络失败）是否同样不留缓存包；多平台 `full_name`（带 platform）变体的缓存文件名；`cache`/`package` 子命令对失败残留的处理；2.7.2 profile 下单独跑该 spec 断言。
## 2026-11-16（M7(6)：`plugin install <gem> --source` 的插件树与无 Gemfile 行为）

参考 4.0.24 与 2.7.2 实测（探针 `.tmp-scratch/plug46`，插件 gem `candle_plug-0.1.0` 的 `plugins.rb` 声明 `command "candle"`，索引由 `gem generate_index` 生成）：

- `bundle plugin install candle_plug --source file:///<index>`（带 Gemfile）→ exit 0，stdout 五行：`Fetching source index from …` / `Resolving dependencies...` / `Fetching candle_plug 0.1.0` / `Installing candle_plug 0.1.0` / `Installed plugin candle_plug`。
- 索引 `<project>/.bundle/plugin/index`：`commands: candle: "candle_plug"`；`load_paths: candle_plug: ["<project>/.bundle/plugin/gems/candle_plug-0.1.0/lib"]`；`plugin_paths: candle_plug: "<project>/.bundle/plugin/gems/candle_plug-0.1.0"`。
- 插件树落 `<project>/.bundle/plugin/{build_info,cache,doc,extensions,gems,plugins,specifications,index}`（`cache/candle_plug-0.1.0.gem`、`gems/candle_plug-0.1.0/{lib,plugins.rb}`、`specifications/candle_plug-0.1.0.gemspec`），**应用 bundle 目录下无该 gem**。
- `plugin list` → `candle_plug` / `-----` / `  candle` / 空行；`bundle candle x y` → `candle: x,y`。
- 无 Gemfile 的目录：`plugin list` → `No plugins installed` exit 0；`candle x y` → `Could not find command "candle".` exit 15（全局 root `~/.bundle/plugin` 恰好指向该工程时才会命中）。

修复前三处真实缺陷：

1. 合成 Gemfile 用系统 TEMP（`File.tempname`），在本沙箱/受限环境直接 `celerite internal error: Unable to create directory: '<系统 TEMP>…': 拒绝访问` exit 1；参考用项目内 `<project>/.bundle/tmp`（`Bundler.tmp`）。
2. 索引 `load_paths`/`plugin_paths` 指向应用 bundle 的 `<BUNDLE_PATH>/ruby/<abi>/gems/<full>`，参考指向 `<project>/.bundle/plugin/gems/<full>`；插件 gem 还会被装进应用 bundle。
3. `plugin list`/`plugin <cmd>`/`plugin uninstall` 一律 `Definition.build`，无 Gemfile 时报 `Could not locate Gemfile` exit 10。

实现（`src/celerite/cli/commands_surface.cr`、`src/celerite/cli/commands.cr`）：

- 新增 `plugin_project_dir` / `plugin_tree_root` / `plugin_index_path`（有 Gemfile → `<project>/.bundle/plugin`；无 Gemfile → `Config.user_home/.bundle/plugin`，与 `Bundler::Plugin.root` 的全局 root 分支一致）；`plugin list`、`plugin install --path`、`plugin uninstall`、`installed_plugins` 与 `dispatch_plugin_command` 改为使用它们，不再要求 Gemfile。
- `plugin_install_remote` 的合成 Gemfile 目录改为 `<project>/.bundle/tmp/celerite-plugin-<pid>-<rand>`，期间临时 `BUNDLE_PATH=<该目录>/bundle`（不写用户 bundle），`ensure` 精确还原两个 ENV 并删除临时目录、空则删除 `.bundle/tmp`。
- 非 git 插件安装后，把临时 bundle 里的 `gems/<full>`、`cache/<full>.gem`、`specifications/<full>.gemspec` 物化到插件树，并补空目录 `extensions`/`doc`/`build_info`/`plugins`；索引 `load_paths`/`plugin_paths` 指向插件树。
- `script/differential` 新增 `@PLUGIN_INDEX_DIR@`（5 处替换，写法同 `@PLATFORM_INDEX_DIR@`）。

证据：

- 差分夹具 `fixtures/differential/plugin-install-source/`（`Gemfile` = `source "file:///@INDEX_DIR@"` + `gem "json_pure"`；`command` 四行：`install`、`plugin install candle_plug --source file:///@PLUGIN_INDEX_DIR@`、`plugin list`、`candle x y`）与仓库内插件索引 `fixtures/gem-index-plugin/`。4.0.24 与 2.7.2 均 `PASS plugin-install-source (exit=0)`；回归 `plugin-command-list`、`install-fresh` 同轮双 profile 全 PASS（各 3 passed, 0 failed）。
- 新 spec `spec/m7_plugin_install_source_spec.cr` 3 例（index 指向 `.bundle/plugin/gems` 且不含 `/bundle/ruby/`；插件树含 `plugins.rb`/`specifications`/`cache` 且 `.bundle/tmp` 不残留；`plugin list` 逐字节、`candle x y`、删 Gemfile 后仍可用、空 HOME 下 `No plugins installed` 与 `Could not find command` exit 15）。
- 首辅独立端到端（`.tmp-scratch/plug46/celproj5`，TEMP/TMP/TMPDIR 故意指向被沙箱拒绝的系统 TEMP）：`plugin install` exit 0；索引与参考逐字相同（仅沙箱路径不同）；`<project>/.bundle/plugin` 下 8 个条目与参考一致；应用 bundle 内 `candle_plug*` 命中 **0**；`.bundle/tmp` 运行后不存在；`plugin list`/`candle x y` 与参考一致；无 Gemfile + 空 HOME → `No plugins installed` exit 0、`candle` → exit 15。
- 负对照（首辅亲做）：把合成 Gemfile 目录改回 `File.tempname` 并重建 `bin` → 该 spec `3 examples, 2 failures`（`Expected: 0`）。spec 已把 TEMP/TMP/TMPDIR 指向工程内一个**普通文件**，使任何「用系统 TEMP」的实现必然失败，避免该断言恒真。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；新 spec 3/0/0/0；全量 **446 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` Low-IL；基线 443/0/4）；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。

已声明偏差与未验证：

- `plugin install --git` 的插件树路径（`<plugin_root>/bundler/gems/<name>-<version>`）未取参考 oracle。
- 无 Gemfile 时执行 `plugin install --source` 的参考行为未取证（我方会装到全局 root）。
- `plugin uninstall` 在无 Gemfile（全局 root）下的行为未差分。
- 真实 https 索引源未测（夹具走 `file://`）；参考 stdout 的 `Fetching source index from …` 尾斜杠随索引 URL 而定，夹具已覆盖但未逐字断言。

## 2026-11-16（M7(5)：文件系统错误按参考映射，含 ENOSPC/EROFS/EPERM/ENOTSUP/EPROTO）

参考语义（`bundler-4.0.24`）：

- `bundler/shared_helpers.rb:105-127` `filesystem_access` 把 OS 错误映射成专属异常：`EACCES`→`PermissionError`、`EAGAIN`→`TemporaryResourceError`、`ENOSPC`→`NoSpaceOnDeviceError`、`EROFS`→`ReadOnlyFileSystemError`、`EPERM`→`OperationNotPermittedError`、`ENOTSUP`→`OperationNotSupportedError`、`EPROTO`→`VirtualProtocolError`；`EEXIST`/`ENOENT` 原样抛出；其余→`GenericSystemCallError`。
- `bundler/errors.rb:94-219` 的状态码与消息：23/26/27/28/31/32/42/43。其中 `TemporaryResourceError` 的 "trythe" 连写、`VirtualProtocolError` 不含 path/action、`GenericSystemCallError` 在消息尾部追加 `The underlying system error is <class>: <msg>`，均逐字保留。

实现：

- 新增 `src/celerite/filesystem_errors.cr`（56 行）：`FilesystemErrors.map(error : File::Error, action : Symbol = :write) : Celerite::Error?`。`File::AccessDeniedError` 直接映射 `PermissionError`；`Errno` 分支覆盖 EACCES/EAGAIN/ENOSPC/EPERM/EROFS，POSIX 专属的 EPROTO/ENOTSUP 用 `{% unless flag?(:win32) %}` 编译期裁掉；Windows 侧补 `WinError::ERROR_DISK_FULL`/`ERROR_HANDLE_DISK_FULL`/`ERROR_WRITE_PROTECT`/`ERROR_ACCESS_DENIED`；`EEXIST`/`ENOENT` 返回 nil 由调用方原样抛出；兜底 `GenericSystemCallError("There was an error creating|accessing `path`.", error)`。
- `src/celerite/errors.cr`：`PermissionError` 抽出 `action_phrase`/`permission_description`/`default_message`（消息与状态 23 不变，`:create` 仍写父目录）；新增 `TemporaryResourceError`(26)、`VirtualProtocolError`(27，独立 `Error` 子类，对齐参考不含 path)、`OperationNotSupportedError`(28)、`NoSpaceOnDeviceError`(31)、`GenericSystemCallError`(32)、`ReadOnlyFileSystemError`(42)、`OperationNotPermittedError`(43)。
- `src/celerite/lockfile/writer.cr`：`rescue ex : File::Error` → `FilesystemErrors.map(ex, :write)`；映射值存在则抛映射值，否则原样抛出（`EEXIST`/`ENOENT` 不被吞）。

证据与门禁（首辅亲跑）：

- 新 spec `spec/m7_filesystem_error_mapping_spec.cr` 10 例：EAGAIN/ENOSPC/EPERM/EROFS/EACCES 的状态码与逐字消息、EEXIST/ENOENT 返回 nil、EINVAL→`GenericSystemCallError`（含尾部 `The underlying system error is File::Error:`）、`:create` 的父目录短语、Windows 两条 `WinError` 映射。与既有 `spec/m7_filesystem_errors_spec.cr` 联跑 14/0。
- 负对照（首辅亲做）：把 `ENOSPC` 分支改成 `return nil` → `10 examples, 1 failures`，原文 `Failure/Error: mapped.should be_a(Celerite::NoSpaceOnDeviceError)` / `Expected nil (Nil) to be a Celerite::NoSpaceOnDeviceError`（`spec/m7_filesystem_error_mapping_spec.cr:44`）；还原后 10/0。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；全量 **456 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` 的 Low-IL `0xC0000022`；基线 446/0/4，+10 为本节新 spec）；`git diff --check` EXIT 0。

未验证与仍存差异：

- 真实 `ENOSPC`/`EROFS`/`EPERM` 未在真机复现，单测用 `File::Error.from_os_error` 构造。
- 映射目前只接入锁文件写出（`Lockfile.write`）；参考的 `filesystem_access` 还覆盖下载缓存、bundle 目录创建等路径，其余调用点尚未接入。
- `DirectoryRemovalError`(36)、`YamlSyntaxError`(25)、`GemRequireError`(24) 未纳入。

## 2026-11-16 续（全量差分复测 160/16/2 与两处修复）

全量差分（4.0.24，`CELERITE_BIN=bin/celerite.exe`（按当前 HEAD + 工作树重建）、`CELERITE_DIFF_EXTRA_PATH='/c/Program Files/nodejs'`、`CELERITE_DIFF_WORK_ROOT=<repo>/.difftmp47full`，日志 `.tmp-scratch/differential-full-47b.log`）：**160 passed, 16 failed, 2 skipped**（本轮早些时候用旧二进制测得 135/19/2；重建后基线抬升）。

修复 1：`cache --cache-path` 被 install 白名单打回

- 修复前：`FAIL cache-path (cache --cache-path=sub/cached)`，`exit code: reference=0 celerite=15`，stderr `Unknown switches "--cache-path=sub/cached"`；参考 stdout 11 行（含 `Updating files in sub/cached` 与两条 `  * <gem>`）。
- 根因：`src/celerite/cli/commands_install.cr` 的 `run_cache` 把原始 `rest` 直接传给 `install`，而 `run_install` 用 `INSTALL_SWITCH_*` 白名单校验。
- 修复：新增 `private def self.install_args_from_cache(rest : Array(String)) : Array(String)`，剔除只属于 `cache` 的 `--cache-path`（`=值` 与空格两种形态及其值）、`--all-platforms`、`--no-install`，其余开关原样透传。

修复 2：无 Gemfile 的工程被创建 `.bundle`

- 修复前：`FAIL plugin-source`、`FAIL plugin-gemfile-missing`，均 `project tree differs: Only in SANDBOX/project: .bundle`（上一轮 `plugin_install_remote` 引入的回归）。
- 修复：`src/celerite/cli/commands_surface.cr` 新增 `plugin_app_config_root`（有 Gemfile → `<Gemfile 目录>/.bundle`；无 → `~/.bundle`），`plugin_tree_root` 改为 `app_config_root/plugin`；合成 Gemfile 的临时目录改到 `app_config_root/tmp`，并在 `ensure` 中于清空 `tmp` 之后再删除「本命令新建的空 `.bundle` 壳」（`app_root_was_absent` 标记）。

证据与门禁（首辅亲跑）：

- 差分 6 夹具双 profile：4.0.24 与 2.7.2 各 `PASS cache-path (exit=0)`/`PASS plugin-source (exit=7)`/`PASS plugin-gemfile-missing (exit=7)`/`PASS plugin-install-source (exit=0)`/`PASS plugin-command-list (exit=0)`/`PASS install-fresh (exit=0)` → 各 `6 passed, 0 failed, 0 skipped`。
- 负对照 1（把 `cache` 的原始 `rest` 直接透传）→ `FAIL cache-path`，原文 `stderr differs: 0a1 > Unknown switches "--cache-path=sub/cached"`、`Only in SANDBOX/project: Gemfile.lock`、`Only in SANDBOX/project: sub`，汇总 `0 passed, 1 failed`。
- 负对照 2（禁用空 `.bundle` 壳清理，保留 `~/.bundle` 作为 app config 根）→ `FAIL plugin-source`、`FAIL plugin-gemfile-missing`，原文 `project tree differs: Only in SANDBOX/project: .bundle`，汇总 `0 passed, 2 failed`；还原后复绿。据此确认「清理空壳」是这条命中的承重改动（仅改 app config 根不足以消除残留）。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；全量 **456 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` 的 Low-IL `0xC0000022`）；`git diff --check` EXIT 0。

全量差分剩余 16 条 FAIL 的分桶（逐条读日志原文）：

- 产品：`add` 家族 5 条（`add-version`/`add-group`/`add-strict`/`add-optimistic`/`add-remove`）——`bundle add` 未接受 `--version`/`--group`/`--strict`/`--optimistic` 等开关（参考 exit 0 并安装，我方 exit 15 `Unknown switches …`），下一轮处理。
- 产品（部分）：`cache-all-platforms`——`cache --all-platforms` 的跨平台缓存语义未实现。
- 已声明差异：`install-frozen`——removed-flag 的参考三行专属文案与 `Did you mean?` 未实现。
- 环境（Low-IL `0xC0000022`）：`git-glob`、`git-installed-discovery`、`git-path-install`、`git-pristine`、`git-tag`、`plugin-git-local`、`plugin-git-local2`、`native-ext`、`native-ext-target` 共 9 条。
- 2 条 SKIP 仍为 `git-submodules`（参考侧被 git ≥2.38 的 submodule file-transport 挡住）与 `plugin-source-disabled`（装具无法逐夹具设 `BUNDLE_PLUGINS=false`）。

## 2026-11-16（M7(2)：`bundle add` 的开关面、`bundle remove` 的消息与 remove/clean 分工）

参考语义（逐行核对 `bundler-4.0.24`）：

- `lib/bundler/cli.rb:404-426` 声明 `add GEM VERSION` 的 `--version/-v`、`--group/-g`、`--source/-s`、`--require/-r`、`--path`、`--git`、`--github`、`--branch`、`--ref`、`--glob`、`--quiet`、`--skip-install`、`--optimistic`、`--strict`、`--cooldown`。
- `lib/bundler/cli/add.rb:41-60` `validate_options!`：`--strict` 与 `--optimistic` 同时出现 → `InvalidOption`；未知开关由 Thor 先拒（先于「至少一个 gem 名」）。
- `lib/bundler/injector.rb:63-76` `remove`：`Bundler.ui.info "Removing gems from <Gemfile>"`，逐个 `Bundler.ui.confirm "#{pretty_dependency(dep)} was removed."`；`shared_helpers.rb:170-180` 的 `pretty_dependency` 在 requirement 非默认时输出 `name (requirement)`，即**按 Gemfile 里的 requirement 原文**。
- `lib/bundler/installer.rb:74` 的 `Bundler.ui.warn "The Gemfile specifies no dependencies"` 走 stderr（`remove` 自身仍 exit 0 并把移除行打在 stdout）。

修复前（实测）：

- `celerite add racc --group dev` → exit 15 `Unknown switches "--group"`；`add racc --version=1.8.1` → exit 15 `Unknown switches "--version=1.8.1"`。根因：`self.add` 把 `rest.select(&.starts_with?("--"))` 直接透传给 `install`，而 `run_install` 的 `INSTALL_SWITCH_*` 白名单不认识 add 专属开关。
- `celerite remove <pinned>` 只打印 `racc was removed.`（缺 ` (~> 1.8)`），因为它从**锁文件**取 requirement。
- 更隐蔽的一处：`remove` 结束后会顺手剪掉「不在锁文件里」的 gem 目录；此前之所以没暴露，是因为旧代码在 `install` 之前先读过一次 `definition.lockfile!`（留下陈旧缓存），剪枝时看到的仍是包含被移除 gem 的旧锁文件。改为从 Gemfile 行取消息后缓存不再陈旧，剪枝真的执行 → `bundle remove` 之后再 `bundle clean` 就什么都不打印了（`spec/m7_clean_spec.cr` 3 例失败）。

实现：

- `src/celerite/cli/commands_surface.cr`：新增 `ADD_SWITCH_FLAGS`/`ADD_SWITCH_VALUES`；`self.add` 先 `reject_unknown_switches`（未知开关 → 15，`=值` 形态保留原始 token），再判 `--strict` + `--optimistic` → 15 并逐字输出 `` You cannot specify `--strict` and `--optimistic` at the same time. ``（带句点）。
- 新增 `private def self.install_args_from_add(rest, name)`：委托 `install` 前剔除 add 专属开关（含其值）与 gem 名位置参数，保留 `--quiet/--verbose/--no-color/--retry/--jobs/--cooldown` 等 install 认识的开关。
- `latest_requirement_for` 的索引探针改为静默 `resolve`，随后按参考顺序打印 `Fetching source index from <remote>/` + `Resolving dependencies...`（path/git 源仍走原分支）。
- `self.remove`：按 Gemfile 行里**引号内的 requirement 原文**拼 `name (req) was removed.`；Gemfile 已无 `gem` 行时把 `The Gemfile specifies no dependencies` 打到 stderr。
- `self.remove` **不再剪枝**：与参考一致，被移除的 gem 仍留在 bundle 目录里，由后续 `bundle clean` 报告 `Removing <name> (<version>)`。

证据与门禁（首辅亲跑）：

- 新增 `spec/m7_add_remove_spec.cr` 6 例：`add --bogus` → 15 + 逐字；`--strict`+`--optimistic` → 15 + 逐字；`add json_pure --version=2.8.1` → 0 且 Gemfile 出现 `"= 2.8.1"`；`remove` 三种 requirement 形态的消息；空 Gemfile 时 stderr 那句。
- 新增差分夹具 `add-version-plain`、`add-group-plain`、`unknown-switch-add`、`add-strict-optimistic`、`remove-requirement`（全用 `json_pure`，避开 native ext）。4.0.24 与 2.7.2 各跑 10 个夹具（含回归 `add-skip-install`/`add-source`/`add-path`/`add-git`/`install-fresh`）：**各 10 passed, 0 failed, 0 skipped**。
- 逐命令 A/B（同一沙箱布局，两侧独立 HOME/BUNDLE_PATH）：`add json_pure --version=2.8.1`、`add json_pure --group dev`、`add --bogus`、`add json_pure --strict --optimistic` 的 stdout+stderr+exit **逐字相同**（`same=True` ×4）。
- `install` → `remove thor` → `clean` 序列 A/B：两侧 `remove` 后 `gems/thor-1.3.2` 都还在，`clean` 都打印 `Removing thor (1.3.2)` 且最终目录相同。
- 负对照（首辅亲做）：把 `install_args_from_add` 改成 `return rest.reject { |a| a == name }` 重新构建 → `FAIL add-version-plain`/`FAIL add-group-plain`，原文 `Unknown switches "--group"`、`Only in SANDBOX/project: Gemfile.lock`，汇总 `0 passed, 2 failed`；还原后复绿。
- 负对照（回归承重点）：把剪枝代码放回 `remove` → `spec/m7_clean_spec.cr` `4 examples, 3 failures`（`Expected: "" to include: "Removing thor (1.3.2)"`），还原后 `spec/m7_clean_spec.cr spec/m7_add_remove_spec.cr` 联跑 `10 examples, 0 failures`。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；全量 **462 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` Low-IL；基线 456/0/4）；`git diff --check` EXIT 0；`bash -n script/differential` EXIT 0。

已声明差异与未验证：

- `add --github/--branch/--ref/--glob` 的组合语义与 `--cooldown` 未实现（开关被接受但语义未接线，属下一轮补齐对象）。
- `add --skip-install` 时参考是否仍打印探针抓取行未逐字取证（本轮只覆盖需要安装的路径）。
- `remove` 的 `Gemfile` 行解析按「引号内 token」取 requirement；多 requirement（`gem "x", "~> 1", ">= 1.0.2"`）、`group:`/`path:` 等选项、多 `gemfile`（`eval_gemfile`）场景未取 oracle。
- `add-version`/`add-strict`/`add-optimistic`/`add-remove` 四个旧夹具仍因要安装 `racc`（native ext，本机 msys `0xC0000022`）无法在 cel 侧通过，保持 FAIL，属环境阻塞。

## 2026-11-16（M7(2)：removed-flag 专属文案与 `Did you mean?` 建议）

参考实现（`bundler-4.0.24`）：

- `lib/bundler/cli.rb:290-300`：`install` 在 Thor 分发后的第一件事就按 `clean`、`deployment`、`frozen`、`no-prune`、`path`、`shebang`、`without`、`with` 的顺序调用 `remembered_flag_deprecation`，随后单独处理 `--system`、`--no-deployment` 与 `--binstubs`。
- `lib/bundler/cli.rb:817-838`：`print_remembered_flag_deprecation` 拼出 `The --<flag> flag has been removed because it relied on being remembered across bundler invocations, which bundler no longer does. Instead please use `bundle config set <option> <value>`, and stop using this flag`；布尔选项不加引号，其余用 `'<value>'`，数组按空格连接。
- `lib/bundler/cli.rb:404-426`：`add` 声明了 `--version/-v`、`--group/-g`、`--source/-s`、`--require/-r`、`--path`、`--git`、`--github`、`--branch`、`--ref`、`--glob`、`--quiet`、`--skip-install`、`--optimistic`、`--strict`、`--cooldown`；`lib/bundler/cli/add.rb:41-60` 校验 `--strict` 与 `--optimistic` 互斥并报 `You cannot specify `--strict` and `--optimistic` at the same time.`。
- Thor 1.5 的未知开关路径用 `DidYouMean::SpellChecker`（`error.rb:65-89`），格式化器输出 `"\nDid you mean?  \"<first>\""`，后续候选按 15 个空格缩进。
- `did_you_mean/spell_checker.rb:8-44`：先 `normalize`（`downcase` 加 `delete("@")`），Jaro-Winkler 阈值 `0.834`（输入长度大于 3，否则 `0.77`），候选按 Jaro-Winkler **降序**；编辑预算 `ceil(输入长度 * 0.25)` 过滤 `Levenshtein`；预算过滤为空时走 misspell 分支，取满足 `distance < min(输入长度, 候选长度)` 的第一个候选。`jaro_winkler.rb` 的 Winkler 加权只在 `jaro > 0.7` 时生效，前缀上限 4。

首辅实测 oracle（`bundle install|cache|lock|update <flag>`，4.0.24 与 2.7.2）：

| 命令 | 参考输出 | exit |
| --- | --- | --- |
| `install --frozen`（同 `--deployment`/`--clean`/`--no-prune`/`--system`/`--shebang`） | removed 文案（80 列折行）；2.7.2 只打 `[DEPRECATED] ...` 并继续 | 15 / 10 |
| `install --binstubs` | `The --binstubs option has been removed in favor of `bundle binstubs --all`` | 15 |
| `install --path vendor/x` | `... Instead please use `bundle config set path 'vendor/x'`, and stop using this flag` | 15 |
| `install --path`（无值） | `path 'path'` | 15 |
| `install --without development` | `without 'development'` | 15 |
| `cache --all`/`--no-prune`/`--frozen` | removed 文案（`cache_all`/`no_prune`/`frozen`） | 15 |
| `cache --deployment`、`lock --frozen`、`lock --deployment`、`update --frozen` | 仅 `Unknown switches "--x"` | 15 |
| `install --forse` | `Did you mean?  "--force"` | 15 |
| `install --jbos` | 仅 `"--jobs"`（`--verbose` 超出 edit budget） | 15 |
| `install --lockfil` | `"--lockfile"` 与 `"--local"`（3 次编辑正好在预算内） | 15 |
| `install --deploy` | `"--deployment"`（4 次编辑超预算，靠 misspell 分支命中） | 15 |
| `install --redownloa` | 无建议（`--redownload` 只是 `--force` 的 alias，不在 Thor 字典里） | 15 |

修复前的两处缺陷：

1. `install --frozen`/`--deployment`/`--clean`/`--no-prune`/`--system`/`--shebang`、`cache --all`/`--no-prune`/`--frozen` 一律退成 `Unknown switches "--x"`，与参考的 removed 文案不符。
2. 未知开关只打 `Unknown switches ...`，缺 `Did you mean?` 段；补上后又与参考在 7 个 typo 上不一致（`--frozenn`、`--deploy`、`--no-prun`、`--binstub`、`--sheban`、`--jbos`、`--lockfil`、`--redownloa`），根因是本实现先把前导 `--` 剥掉再算 Jaro-Winkler 与 Levenshtein，而 did_you_mean 用完整字符串。

实现：

- `src/celerite/suggestions.cr`：`Suggestions.for(input, dictionary)` 逐行对齐 `SpellChecker#correct`（`normalize` 只做 `downcase` 加 `delete('@')`；Jaro-Winkler 阈值 0.834/0.77；按 JW 降序；`ceil(len * 0.25)` 的编辑预算；misspell 分支只取 1 条；最多 5 条），`message` 输出 `Did you mean?  "<first>"` 与 15 空格缩进的后续候选。
- `src/celerite/cli/commands.cr`：新增 `RemovedFlag` 记录与 `removed_flag(rest, command)`（install 顺序对齐 `cli.rb:290-300`，cache 为 `--all`/`--no-all`/`--no-prune`/`--frozen`）、`removed_flag_message`、`removed_flag_deprecation`；`reject_unknown_switches` 增加可选 `dictionary` 参数；新增 `INSTALL_REMOVED_FLAGS`、`CACHE_REMOVED_FLAGS` 与 `INSTALL_SUGGEST_DICTIONARY`、`CACHE_SUGGEST_DICTIONARY`（声明名全集，去掉 alias `--redownload`）。
- `src/celerite/cli/commands_install.cr`：`run_install`/`run_cache` 在未知开关检查之前先判 removed flag（4.x 折行打印并返回 15，2.7.x 打 `[DEPRECATED]` 后继续），`cache` 的 `--cache-path` 等命令专属选项仍透传。
- `src/celerite/cli/commands_surface.cr`：`add` 在取 gem 名前做未知开关检查（白名单含 add 全部选项），`--strict`/`--optimistic` 互斥报参考文案，委托 `install` 前剔除 add 专属开关。

证据：

- 22 个 typo 的 A/B（同布局双沙箱、独立 HOME 与 `BUNDLE_PATH`，逐条比对 exit 与完整 stderr）：修复前 7 条 DIFF，修复后 **22/22 完全一致**。
- `spec/m7_removed_flags_spec.cr`（新增）**12 examples, 0 failures**：removed 文案 5 例、cache 专属 2 例、`update --frozen` 建议、`--forse`、`--deploy`（misspell）、`--lockfil`（多建议）、`--jbos`（预算外剔除）、`--redownloa`（alias 不提示）。
- 差分：`install-frozen`、`removed-flag-path`、`unknown-switch-typo`、`unknown-switch-{install,update,lock,cache}`、`install-fresh` 在 4.0.24 与 2.7.2 各 **8 passed, 0 failed, 0 skipped**（2.7.2 的 `removed-flag-path` 走 `[DEPRECATED]` 分支，参考与本实现同为 exit 10）。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅既有 2 条 `File.executable?` deprecation）；全量 spec 与基线一致（4 个既有 `spec/git_source_spec.cr` error 属本机 Low-IL 共享内存限制）；`git diff --check` EXIT 0。

已声明偏差与未验证：

- `--help`/`help <cmd>` 仍不渲染 manpage；`install --frozen --verbose` 参考会先打印 `Running `bundle install --frozen --verbose` with bundler 4.0.24` 再抛完整回溯报告，本实现只给折行后的 removed 文案。
- `--redownload` 作为 `--force` 的 alias 仍被接受（与参考一致），只是不进入建议字典。
- 未验证：`update`/`lock` 的完整 removed 面（它们没有 removed 文案，只验证了 `--frozen` 的建议）、`--all-platforms` 在 cache 上的行为（本机 `racc` 原生扩展撞 msys `0xC0000022`）、`Did you mean?` 对命令名（非开关）的建议、2.7.2 的 typo 建议是否与 4.0.24 完全一致（本轮只在 4.0.24 上逐条对拍 22 个 typo，2.7.2 只跑了 8 个差分夹具）。

## 2026-11-16（M7(2)：`show`/`info` 的组过滤语义与 `Bundler.load` 先决顺序）

### 参考语义
- `bundler/cli/common.rb:68-96` `select_spec`：`Bundler.definition.specs` 里找不到请求的 gem 时，若它仍作为依赖存在（`current_dependencies.find { |dep| dep.name == name }`），参考抛 `GemNotFound`（status 7）并给出组信息：`Could not find gem '<name>', because it's in the <group(s)>, configured to be ignored.`；否则退回通用缺失消息。
- `bundler/cli/common.rb:60-66` `verbalize_groups`：单组输出 `group 'development'`，多组输出 `groups 'development' and 'test'`（每组加单引号，末位前用 ` and `、其余用 `, `）。
- `bundler/cli/show.rb:10-26` / `info.rb:10-30`：两条命令都先 `Bundler.load.lock`（把锁定 gems 全部物化）再调用 `select_spec`，因此「有锁定 gem 未安装」的错误先于组消息出现。

### 修复前的两处缺陷
1. 组过滤被 `bridge_available?` 门控（与 2026-11-16 早些时候的 `list` 修复同根因）：`BUNDLE_WITHOUT=development` 下 `celerite show thor` 退出 0 并打印路径，参考退出 7 且只打印两行组消息；`info thor` 同理。
2. 缺失顺序不一致：锁定 gem 里有未安装项时，参考先报 `Could not find json_pure-2.8.1 in locally installed gems`，我方先报请求 gem 的组消息（同一工程的探针原文：REF `Could not find json_pure-2.8.1 in locally installed gems` / CEL `Could not find gem 'thor', because it's in the group 'development', configured to be ignored.`）。

### 实现
- `src/celerite/cli/commands.cr` 的 `show_info`：组解析改为无条件（`available_groups` + `requested_groups_for` + `filter_locked_specs_by_groups`，`rescue` 后退化为全量 spec 列表），不再依赖 `CELERITE_BRIDGE_SERVER`/`CELERITE_REFERENCE_BUNDLER_LIB`。
- 新增 `Commands.verbalize_groups(groups : Array(String)) : String`（单组 `group 'x'`；多组 `groups 'a' and 'b'`），组消息经 `word_wrap(..., CLI.terminal_width)` 输出后返回 7。
- 把「锁定 gems 均已安装」的检查提前到解析请求 gem 之前（对齐 `Bundler.load`）；`show` 无参且非 `--paths` 时仍先打印 `Gems included by the bundle:` 表头，与参考流式输出顺序一致。

### oracle（首辅实测，4.0.24 与 2.7.2 同形）
| 命令 | 环境 | exit | stderr |
| --- | --- | --- | --- |
| `show thor` | `BUNDLE_WITHOUT=development` | 7 | `Could not find gem 'thor', because it's in the group 'development', configured` / `to be ignored.` |
| `info thor` | 同上 | 7 | 同上 |
| `show thor --paths` | 同上 | 7 | 同上（无 stdout） |
| `info thor --path` | 同上 | 7 | 同上 |
| `show thor` | `BUNDLE_WITHOUT=development:test`，gem 在两组 | 7 | `... in the groups 'development' and 'test', configured` / `to be ignored.` |
| `show json_pure` | `BUNDLE_WITHOUT=development` | 0 | 空（打印未过滤 gem 的路径） |
| `show json_pure` | 无 `BUNDLE_WITHOUT`、gem 未安装 | 7 | `Could not find json_pure-2.8.1 in locally installed gems` |

### 证据
- `spec/m7_show_group_filter_spec.cr`（4 例）：单组 `show`、单组 `info`、多组 `groups ... and ...`、未过滤 gem 正例；`4 examples, 0 failures`。
- 差分夹具 `fixtures/differential/show-group-ignored/`（`Gemfile` + `Gemfile.lock` + `bundle-preset/` 预装 json_pure + `extra/.bundle/config` 设 `BUNDLE_WITHOUT: "development"`，`command`=`show thor`）与 `show-missing-installed/`（未安装工程，`command`=`show json_pure`）：4.0.24 `2 passed, 0 failed`、2.7.2 `2 passed, 0 failed`。
- 负对照：把组消息分支条件改成 `unless true` 并重建 `bin/celerite-nc.exe`，`script/differential show-group-ignored` 得 `FAIL show-group-ignored (show thor)`，原文 `> Could not find 'thor' in locally installed gems. Run \`bundle install\` to install missing gems.`；`edit` 还原后复跑 `PASS`，并删除负对照二进制。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen --link-flags <shim> src/cli.cr` EXIT 0（仅 2 条既有 `File.executable?` deprecation）；全量 `crystal spec --link-flags <shim>` **478 examples, 0 failures, 4 errors, 0 pending**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）；`git diff --check` EXIT 0。

### 已声明差异与未验证
- 参考把宿主已安装 gems 纳入解析候选（同一工程 `show thor` 在无分组过滤时返回 `thor 1.5.0`，我方 1.3.2），此项仍未实现。
- `BUNDLE_WITH` 与 `--only-group/--without-group` 之外的组合（例如同时 `BUNDLE_WITH` 与 `BUNDLE_WITHOUT`）未逐一对照。
- `show --paths <被过滤 gem>` 已手工实测与参考逐字一致，但未单独加进差分夹具。
- 全量 spec 在「复用旧 HOME」时曾出现一次 `spec/m7_build_args_spec.cr` 的假失败（`ARGV` 非空），换成新建 HOME 后 `478 examples, 0 failures`；该现象与历史记录一致，属测试环境状态残留，不是产品回归。

## 2026-11-16（M7(3)：`bundle env` 的 Gem 目录行与 `bundle version` 的构建元数据）

参考锚点：
- `bundler/env.rb:60-90`：`## Environment` 打印 `Gem.dir`、`Gem.path.join(File::PATH_SEPARATOR)`、`Pathname.new(Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE).dirname`、`Gem.bindir`。
- `bundler/build_metadata.rb`：`@built_at="2026-11-05"` 与 `@git_commit_sha="3b396e4"` 是发布时烘焙的常量，`## Bundler Build Metadata` 原样打印。
- `bundler/cli.rb:555-567`：`bundle version` 打印 `Bundler.verbose_version` 加构建元数据；`-v`/`--version` 只打版本；多余位置参数走 Thor `UnknownArgumentError`（`Usage: "bundle version"`，exit 15）。

参考输出（本机实测，隔离 HOME，`source "https://rubygems.org"` 的 Gemfile）：

| 命令 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `version` | `4.0.24 (2026-11-05 commit 3b396e4)` | `Bundler version 2.7.2 (2025-09-09 commit b463ced1459)` |
| `-v` / `--version` | `4.0.24` | `Bundler version 2.7.2` |
| `version extra` | stderr 两行 `ERROR: "bundle version" was called with arguments ["extra"]` / `Usage: "bundle version"`，exit 15 | 同形，exit 15 |
| `env` 的 `Gem Path` | 多条用 `;` 连接，且用户设置 `GEM_PATH` 时追加默认目录 | 同 |
| `env` 的 `Config Dir` | `C:/ProgramData`（正斜杠） | 同 |
| `env` 的 `Bin Dir` | `Gem.bindir` = `C:/Ruby40-x64/bin` | 同 |

修复前缺陷（我方）：

1. `Gem Path` 用 `", "` 连接多条路径。
2. `Config Dir` 由 `ENV["PROGRAMDATA"]` 推导，输出反斜杠。
3. `Bin Dir` 取 `<gem home>/bin`，未区分默认 gem 目录（`Gem.bindir` 则回落到 RbConfig 的 bindir）。
4. `## Bundler Build Metadata` 打印本仓 `git log -1 --format=%cs` 与 `git rev-parse --short=7 HEAD`，不是发布版常量；`bundle version` 打印 `Celerite::VERSION`（`0.1.0`）。
5. 用户自定义 `GEM_PATH`（不含默认 gem 目录）时 `celerite env` 直接 exit 1：桥进程用 RubyGems 激活 bundler 失败（`Could not find 'bundler' (= 4.0.24) - did find: [bundler-4.0.16]`），而参考的 `exe/bundle` 是从自身 lib 目录加载 bundler，不受 `GEM_PATH` 影响。

实现：

- `src/celerite/release_metadata.cr`（新）：`RELEASES = {"2.7.2" => {"2025-09-09", "b463ced1459"}, "4.0.24" => {"2026-11-05", "3b396e4"}}`，`ReleaseMetadata.for(version)`；`env` 与 `issue` 的 Build Metadata 块共用，未知 profile 回退本仓值。
- `src/celerite/cli/commands.cr`：`dispatch` 将 `version`/`--version`/`-v` 交给新的 `Commands.version(command, stdout, stderr, rest)`；`version` 带元数据，2.x 前缀 `Bundler version `，`rest` 非空时打印 Thor 的 `ERROR:`/`Usage:` 并 exit 15。
- `src/celerite/cli/commands_surface.cr`：`env`/`issue` 的 `Gem Path` 改用 `Process::PATH_DELIMITER` 连接（Crystal 无 `File::PATH_SEPARATOR`），`Config Dir`/`Bin Dir` 改读桥新增的 `system_config_dir`/`gem_bindir`；`issue` 删除「配置 BUNDLE_PATH 时把 bundle 路径当 Gem Home/Path/Bin」的旧特例。
- `assets/bridge/server.rb`：`op_ruby_environment` 新增 `gem_bindir`（`Gem.bindir`）与 `system_config_dir`（`File.dirname(Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE)`）；`gem_paths` 改回 `Gem.path`（用户设 `GEM_PATH` 时 RubyGems 会自动追加默认目录）；新增 `bridge_activate_bundler`：`CELERITE_REFERENCE_BUNDLER_LIB` 优先，仅给版本时先 `gem "bundler", version`，激活失败回退 `<Gem.default_dir>/gems/bundler-<version>/lib`（与参考 `exe/bundle` 的加载方式一致）。
- `src/celerite/bridge/client.cr`：`RubyEnvironment` 增加 `gem_bindir`/`system_config_dir`。

证据：

- `spec/m7_env_output_spec.cr` 新增 4 例（4.0.24 与 2.7.2 的构建元数据、`GEM_PATH` 用 `;` 且不吞默认目录、`Config Dir` 不含反斜杠）；`spec/m7_version_spec.cr`（新）4 例（`version`、`-v`/`--version`、2.7.2 形态、`version extra` exit 15）；两文件 `13 examples, 0 failures`。
- 差分：新增 `fixtures/differential/version-plain`（`version`）与 `version-extra`（`version extra`）。4.0.24：`version-plain version-extra env-report show-missing-installed` -> `4 passed, 0 failed`；2.7.2：`version-plain version-extra env-report` -> `3 passed, 0 failed`。
- 负对照：注释掉 `Commands.version` 的元数据后缀后重建二进制 -> `FAIL version-plain`（`< 4.0.24 (DATE commit 3b396e4)` / `> 4.0.24`），`version-extra` 仍 PASS；还原后复绿。
- 自定义 `GEM_PATH=C:/gems-a;C:/gems-b`：修复前 `celerite env` exit 1；修复后 exit 0，`Gem Path` 为 `C:/gems-a;C:/gems-b;<默认目录>`，与参考逐字一致。
- 全量：`crystal spec` **486 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL 项）；`crystal tool format --check` 与 `crystal build --no-codegen` 均 EXIT 0。

已声明差异与未验证：

- 未显式设置 `GEM_HOME` 时，本机 `Gem Home`/`Bin Dir` 仍与参考不同：RubyGems 在默认 gem 目录不可写时回退 `Gem.user_dir`（`rubygems/defaults.rb:242` 与 RubyInstaller `rubygems/defaults/operating_system.rb:24`），本机 crystal 产物以 Low IL 运行触发回退，参考 `ruby` 为 Medium IL 故不回退。两侧显式 `GEM_HOME` 后 `env` 输出逐字一致，属环境差异，不是产品语义差异。
- 全局 `--verbose` 回显（`Running `bundle env --verbose` with bundler 4.0.24`）未实现；实测参考该行参数按选项定义顺序重排（`env --verbose --no-color` 打印 `env --no-color --verbose`），且 `check --verbose` 不打印，暂不复制。
- `version extra` 的 stderr 参考用 CRLF（Ruby 文本模式），我方 LF。
- `issue` 的 Build Metadata 未加单独差分夹具（与 `env` 共用同一常量与打印路径）。

## 2026-11-16（M7(2)/M7(3)：无 lockfile 的 `show`/`info` 发现与用户主目录语义）

参考锚点：

- `bundler/cli/show.rb:10-26`、`bundler/cli/info.rb:10-30`：先 `Bundler.load.lock` 再 `Bundler::CLI::Common.select_spec`。
- `bundler/cli/common.rb:68-96` `select_spec`：遍历 `Bundler.definition.specs`，命中即返回；未命中时 `default_gem_spec(name)`；仍为 0 条时，若该名字是 `current_dependencies` 中被组过滤掉的依赖，抛组消息，否则抛 `gem_not_found_message`。
- `bundler/definition.rb:249-250` `specs` = `materialize(requested_dependencies)`：没有 lockfile 时 `Bundler.load` 会**先解析 Gemfile**，再逐个 materialize 已解析的 spec。
- Ruby 的 `File.expand_path("~")`/`Gem.user_dir` 在 Windows 上优先 `HOME`（实测 `HOME=<tmp>` 且 `USERPROFILE=C:\Users\ShiningRay` 时两者都指向 `<tmp>`），Bundler 的用户级缓存/配置因此跟随 `HOME`。

实测 oracle（4.0.24；`file://` 源 + 无 `Gemfile.lock`；两侧独立 HOME）：

| 场景 | 参考 | 修复前我方 |
| --- | --- | --- |
| `my_plugin`（索引有、宿主未装）`show my_plugin` / `info my_plugin` / `show` / `show --paths my_plugin` | exit 7，stderr `Could not find gem 'my_plugin' in locally installed gems.` | exit 20，`Could not find <abs>/Gemfile.lock for resolution` |
| 同上、Gemfile 写 `gem "my_plugin", "0.1.0"` | exit 7，`Could not find gem 'my_plugin (= 0.1.0)' in locally installed gems.`（`Gem::Dependency#to_s` 保留非默认 requirement） | 同上 exit 20 |
| `json_pure 2.8.1`（宿主默认 gem 目录已装）`show json_pure` / `show --paths` / `info json_pure` | exit 0，打印 `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json_pure-2.8.1`（info 另含字段） | exit 7，`Could not find json_pure-2.8.1 in locally installed gems` |
| 同上裸 `show` | exit 0，`Gems included by the bundle:` + `  * bundler (4.0.24)` + `  * json_pure (2.8.1)` | exit 7（先打印表头再报缺失） |

修复前缺陷：

1. `show_info` 无条件 `definition.lockfile!`，没有 lockfile 时抛 `LockfileError`（exit 20），而参考此时解析 Gemfile。
2. `system_gem_search_dirs` 被 `CELERITE_BRIDGE_SERVER`/`CELERITE_REFERENCE_BUNDLER_LIB` **门控**：普通运行（不设这两个变量）拿不到 GEM_PATH/默认 gem 目录，`installed_gem_dir` 只在 bundle 路径里找，宿主已安装的 gem 一律判为缺失（与此前 `list`/`show` 组过滤同一类装具门控缺陷）。
3. `Config.user_home` 在 Windows 上优先 `USERPROFILE`，与 Ruby 的 `~` 语义相反：差分/spec 隔离 `HOME` 后，用户级 `.bundle` 配置与 compact-index 缓存仍写到真实 profile，本机 Low-IL 下直接 `Error opening file with mode 'wb' ... 拒绝访问`（exit 1）。
4. 无 lockfile 的缺失消息用了 spec `full_name`，参考用依赖显示名（含非默认 requirement）。

实现：

- `src/celerite/cli/commands.cr` `show_info`：`resolved_from_gemfile = !definition.lockfile_exists?`；无 lockfile 时 `Resolution.new(definition, false)` 解析并取 `generated_lockfile`，同时把 `resolution.evaluation.dependencies` 的显示名（`Gem::Dependency#to_s` 语义：默认 `>= 0` 省略 requirement）记入 `dependency_displays`；缺失分支在无 lockfile 时打印 `Could not find gem '<display>' in locally installed gems.`（无表头）。
- `src/celerite/cli/commands_surface.cr` `system_gem_search_dirs`：去掉桥环境门控，直接向桥取 `default_gem_dir`/`gem_paths`/`user_gem_dir`，失败仅返回空列表。
- `src/celerite/config.cr` `Config.user_home`：所有平台先认 `HOME`（非空），Windows 再回退 `USERPROFILE` → `HOMEDRIVE`+`HOMEPATH`。

证据：

- `spec/m7_show_no_lockfile_spec.cr`（新）5 例：无 lockfile 未安装（4 条命令同消息）、requirement 显示、GEM_PATH 已安装（用临时 GEM_HOME 造 `gems/json_pure-2.8.1` + `specifications/*.gemspec`）、裸 `show` 列表；`5 examples, 0 failures`。
- 差分：新增 `fixtures/differential/show-no-lockfile-missing`（`show my_plugin`）与 `show-no-lockfile-installed`（`show json_pure`）。4.0.24：`show-no-lockfile-missing show-no-lockfile-installed show-group-ignored show-missing-installed version-plain env-report` -> `6 passed, 0 failed`；2.7.2 同 6 条 -> `6 passed, 0 failed`。
- 负对照：把 `resolved_from_gemfile` 硬置 `false` 重建二进制 -> 两个新夹具均 `FAIL`（`exit code: reference=7 celerite=20`，diff 显示 `< Could not find gem 'json_pure (= 2.8.1)' ...` / `> Could not find <sandbox>/Gemfile.lock` + `> for resolution`），还原后复绿。
- 全量：`crystal spec` **491 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL 项；基线 486/0/4）；`crystal tool format --check` 与 `crystal build --no-codegen` 均 EXIT 0。

已声明差异与未验证：

- `file://C:/...`（两斜杠）这种非规范源写法，参考可正常解析，我方 URI 归一化成 `file://C/...` 后在索引里找不到 gem，报 `... in rubygems repository file://C/... or installed locally`。规范写法 `file:///C:/...` 两侧一致；本轮未改 URI 归一化，登记为已声明差异。
- 无 lockfile 时 `info` 的 metadata 依赖已安装 gemspec；只在临时 GEM_HOME 里造了占位 gemspec，未验证真实宿主 gem 的完整字段（宿主已装 `json_pure` 的手工探针输出与参考逐字一致）。
- `show`/`info` 无 lockfile 会触发一次解析（与参考一致），未测大 Gemfile 的耗时差异。
## 2026-11-16（M7(1)：Ruby 运行时校验无条件化、RUBY VERSION 写运行版本、platform 的版本操作数）

参考锚点：`bundler/definition.rb:494-523`（`validate_runtime!` 拆 `validate_ruby!` + `validate_platforms!`，消息按 `:engine`/`:version`/`:engine_version`/`:patchlevel` 分支）；`bundler/cli/check.rb:16`、`bundler/cli/show.rb:15`、`bundler/cli/binstubs.rb:12` 均在校验后再做各自逻辑；`bundler/cli/platform.rb:11-15`（无锁文件时用 Gemfile 声明）与 `:35-40`（`rescue RubyVersionMismatch` 打印消息、exit 0）；`bundler/definition.rb:445-452` `locked_ruby_version`（新锁或 ruby 被更新时取 `Bundler::RubyVersion.system`，声明仍兼容则保留锁内旧值）；`bundler/ruby_version.rb:36`（`to_s`）、`:44-50`（4.x 只写 `ruby <ver>`，2.x 追加 `p<patchlevel>`）、`:67-69`（`single_version_string` = `to_s(gem_version)`）。

oracle（4.0.24，两侧独立 HOME，`file:///` 夹具索引）：
| 场景 | 参考 | 修复前本实现 |
| --- | --- | --- |
| `ruby "9.9.9"` + 已锁，`check` | exit 18，`Your Ruby version is 4.0.6, but your Gemfile specified 9.9.9` | exit 0，`The Gemfile's dependencies are satisfied` |
| 同上，`show` | exit 18，同消息 | exit 0，打印 gems 列表 |
| 同上，`binstubs --all thor` | exit 18，同消息 | exit 1，`Please pass a gem name` |
| 无锁 + `ruby ">= 3.1"`，`platform` | exit 0，`* ruby 3.1` + 满足行 | exit 0，`* ruby >= 3.1` + 「未校验」行 |
| 同上，`platform --ruby` | `ruby 3.1` | `ruby >= 3.1` |
| 无锁 + `ruby ">= 3.1"`，`lock` 后的 `RUBY VERSION` | 4.0.24 `ruby 4.0.6`；2.7.2 `ruby 4.0.6p0` | `ruby >= 3.1`（两侧一致错） |

修复前属装具门控：`Commands.validate_ruby_runtime!` 首行 `return unless bridge_available?`，而 `bridge_available?` 只认 `CELERITE_BRIDGE_SERVER`/`CELERITE_REFERENCE_BUNDLER_LIB` 两个环境变量，故普通 CLI 下所有命令都不校验运行时；`platform` 另有自己的 `bridge_available?` 分支打印「Ruby version requirement not validated (bridge unavailable); cannot confirm runtime match.」（参考无此行）；`binstubs` 的用法检查在校验之前；`Resolution#generated_lockfile` 直接把 Gemfile 的 ruby requirement 原文写进 `RUBY VERSION`，且 `RubyVersion#single_version_string` 返回 `@versions.first?`，导致出现 `ruby ruby 3.1` 形态。

实现：
- `Commands.validate_ruby_runtime!`：去掉 `bridge_available?` 门控；未显式传入 bridge 时尝试 `Bridge::Client.new`，构造失败即 `return`（降级构建跳过校验，不阻断历史可用命令），成功则求值 Gemfile + 取 `ruby_environment` 并 `RubyRuntime.validate_version!`；`RubyVersionMismatch` 原样上抛，其余异常 best-effort 吞掉。调用面覆盖 `check`/`show`/`fund`/`update`/`outdated`/`pristine`/`install`/`platform`/`binstubs`。
- `Commands.platform`：删除「未校验」分支，按参考 rescue 语义输出 `Your current platform satisfies the Ruby version requirement.` 或 mismatch 消息（`ex.message || ""`，`String?` 需显式兜底），始终 exit 0；无锁文件时 `ruby_version` 由桥求值 Gemfile 声明并取 `requested.single_version_string`。
- `Commands.binstubs`（`commands_install.cr`）：`Definition.build` + `validate_ruby_runtime!` 提到 `--all` 互斥与缺参判断之前，bad-ruby 下由 exit 1 usage 变 exit 18。
- `Resolution#generated_lockfile`：`RUBY VERSION` 走 `ruby_section_value`（旧锁存在、非 `--ruby` 更新且 `ruby_declaration_matches_lock?` 时保留锁内值，否则 `system_ruby_string`；桥不可用时回退 Gemfile 声明）；`system_ruby_string` 输出 `ruby <运行版本>`，2.x 且 patchlevel 非空非 `-1` 追加 `p<patchlevel>`，非 CRuby 追加 ` (<engine> <version>)`。
- `RubyVersion#single_version_string`：改为 `ruby #{gem_version}`，`gem_version` 用 `requirement_version` 取 requirement 的版本操作数（按空白切分取末段），`engine_gem_version` 同步复用；调用点去掉外层多余的 `ruby ` 前缀。

证据：
- spec：新增 `spec/m7_ruby_runtime_enforcement_spec.cr`（4 例：check/show/binstubs 抛 `RubyVersionMismatch` 且 `status_code == 18`、binstubs 无参时 stderr 为空、生成锁含 `RUBY VERSION\n  ruby <系统版本>\n` 且不含 Gemfile 原文）；`spec/m7_platform_spec.cr` 重写为断言参考行为（mismatch 消息、无满足行；无锁时 `* ruby 3.1` 与 `platform --ruby` = `ruby 3.1`）。两文件联跑 6 examples / 0 failures / 0 errors；全量 **496 examples, 0 failures, 4 errors**（4 = 既有 msys Low-IL 的 `git_source_spec.cr`）。
- 差分：新增 `fixtures/differential/ruby-requirement-mismatch`（`check`，exit 18）与 `platform-gemfile-ruby`（`platform`，exit 0）；4.0.24 两条 PASS，2.7.2 两条同样 PASS；回归集 `ruby-requirement-mismatch platform-gemfile-ruby show-group-ignored show-no-lockfile-missing show-no-lockfile-installed install-fresh env-report` = 7 passed / 0 failed。
- 负对照：在 `validate_ruby_runtime!` 首行插 `return # negative-control` 重建 `bin/celerite-nc.exe` → `FAIL ruby-requirement-mismatch (check)`，`exit code: reference=18 celerite=20`，stderr 变为 `Could not find <sandbox>/Gemfile.lock for resolution`（校验被跳过、流程落到无锁解析错误）；随后还原、重建真二进制并复跑 7/7 PASS。

已声明差异与未验证：
- 无 lockfile 时 `check` 仍 exit 20（`Could not find <abs>/Gemfile.lock for resolution`），参考会先解析并写锁后打印满足信息；这是本轮新发现的独立缺口，未修，记入 roadmap。
- 桥不可用（降级构建）时运行时校验被跳过，不算通过；本机 Crystal 产物在沙箱内为 Low IL，与参考 Medium IL 的差异不影响本项结论。
- Gemfile 带 `engine`/`engine_version`/`patchlevel` 的正例仍由既有 `ruby-engine-*`/`ruby-patchlevel-*` 夹具覆盖，本轮未重跑全量差分；`--ruby` 更新路径只做了手工探针（有锁保留、`--ruby` 改写），未加夹具。

## 2026-11-16（M7(1)：无 lockfile 的 `bundle check` 解析与写锁）

本轮把上一节声明为「未修」的独立缺口补齐：项目还没有 `Gemfile.lock` 时，`bundle check` 不再报 `Could not find <abs>/Gemfile.lock for resolution`（exit 20），而是像参考一样先解析、按依赖是否装齐分流，并在满足且非 `--dry-run` 时写锁。

参考锚点：
- `bundler/cli/check.rb:11-36`：`definition.check!` 负责建定义并解析；`not_installed = definition.missing_specs`；`GemNotFound/GitError/SolveFailure` → `Bundler can't satisfy your Gemfile's dependencies.` + 提示 + exit 1；缺失非空 → `The following gems are missing` + 逐条 ` * name (version)` + `Install missing gems with \`bundle install\`` + exit 1；否则 `definition.lock(true) unless options[:"dry-run"]` 之后打印 `The Gemfile's dependencies are satisfied`。
- 解析进度文本（`Fetching source index from <remote>/`、`Resolving dependencies...`）来自 `Bundler::Definition#resolve` 的 `Bundler.ui.info` 调用；`file:` 源走 `Fetching source index from` 而不是 `Fetching gem metadata from`。

两处实现：
1. `src/celerite/cli/commands.cr` 的 `run_check`：`resolved_from_gemfile = !definition.lockfile_exists?` 为真时用 `Resolution.new(definition, false)` 现场解析（`resolution.progress = stdout`、`resolve!`、取 `generated_lockfile` 并保留 `to_lock` 文本，`ensure resolution.close`），否则沿用 `definition.lockfile!`。缺失分支因此在无锁时不再撞 `LockfileError`。
2. 同一函数在「满足」分支前按需落盘：仅当无锁、未带 `--dry-run`、且与磁盘上内容（`semantic_content`）不同时才 `Lockfile.write(..., preserve_crlf: preserve_lockfile_crlf?)`，与 `install` 的写法一致。
3. `assets/bridge/server.rb` 的 `op_bundler_cache_file`：`Gem::Specification.find_by_name("bundler", version)` 在隔离 `GEM_PATH` 下会隐藏默认目录（`GEM_PATH` 替换默认路径），导致 `CHECKSUMS` 少一行 `bundler (4.0.24) sha256=…`；现在 spec 查不到或 cache 文件不存在时回退 `Gem.default_dir/cache/bundler-<version>.gem`，再回退 `CELERITE_REFERENCE_BUNDLER_LIB` 推导的仓库路径。

证据（首辅亲跑，`.tmp-scratch/ck54i` 与 `probe54.ps1`，两侧各自独立 HOME/GEM_HOME/GEM_PATH，`file:///<repo>/fixtures/gem-index`）：
- `nolock-missing`（未装 json_pure）：两侧 exit 1，stdout 两行进度 + stderr 三行完全一致，且都不写锁。
- `nolock-installed`（假 json_pure 2.8.1 装进 GEM_HOME）：两侧 exit 0，stdout 一致；写出的锁文件逐字相同，含 `CHECKSUMS` 的 `bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc` 与 `json_pure (2.8.1)`。
- `nolock-installed --dry-run`：两侧 exit 0，输出一致，均不写锁。
- spec：新增 `spec/m7_check_no_lockfile_spec.cr`（3 例：缺失 exit 1 且不写锁、已装 exit 0 且写锁含 `BUNDLED WITH`、`--dry-run` 不写锁）；全量 **499 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` msys Low-IL）。
- 差分：新增 `fixtures/differential/check-no-lockfile-missing`（`check`，exit 1）与 `check-no-lockfile-installed`（`check`，含 `bundle-preset` 预装 json_pure，exit 0，锁文件参与比对）；4.0.24 与 2.7.2 各 2/2 PASS；2.7.2 回归集 `check-no-lockfile-* check-satisfied-nolock-ruby ruby-requirement-mismatch show-group-ignored install-fresh` = 6 passed / 0 failed。
- 负对照：把 `run_check` 的 `resolved_from_gemfile` 硬置 `false` 重建 `bin/celerite-nc.exe` → 两条新夹具 **0 passed / 2 failed**，diff 为 `exit code: reference=1 celerite=20`、stderr 变成 `Could not find <sandbox>/Gemfile.lock` / `for resolution`、且 `Only in SANDBOX/project: Gemfile.lock`；还原后重建真二进制复跑 2/2 PASS。

已声明差异与未验证：
- 解析在无锁 `check` 下会走一次完整网络/索引解析；参考同样如此，但耗时未量化。
- `CHECKSUMS` 回退只覆盖「bundler 缓存在 `Gem.default_dir/cache`」的本机布局；Ruby 安装未保留 `.gem` 缓存时两侧都不写 bundler 行，未加夹具。
- 差分只跑新夹具与相邻回归集，未重跑全量；全量 4.0.24/2.7.2 分类沿用前一节的 168/15/2 与 170/13/4（均为环境类）。

## 2026-11-16（M7(4)：`--verbose` 的 `Running ...` 回显）

参考语义只在 debug 模式回显命令行：`bundler-4.0.24/lib/bundler/cli.rb:777-791` 的 `print_command` 先判 `Bundler.ui.debug?`，再跳过 `PARSEABLE_COMMANDS`（`cli.rb:13`：check/config/help/exec/platform/show/version），把请求参数与 `Thor::Options.to_switches` 渲染的开关拼成 `Running `bundle ...` with bundler <verbose_version>`。`to_switches`（`vendor/thor/lib/thor/parser/options.rb:11-26`）的规则是：布尔输出裸 `--name`；数组输出 `--name ` + `value.map(&:inspect).join(" ")`；`nil`/`false` 丢弃；其余输出 `--name <inspect>`。

发现：本实现把 `--verbose` 列在 `SWITCH_FLAGS_COMMON` 里接受，`strip_global_flags` 只写 `CELERITE_VERBOSE` 环境变量，之后没有任何消费点，属「解析 flag 后静默忽略」。

实现（`src/celerite/cli/commands.cr`）：`dispatch` 在调用 `strip_global_flags` 前记录 `--verbose` 与 `--retry` 的值（二者会被移除），新增 `print_command_echo` 在命令分发前输出；开关表分三档（`ECHO_FLAG_SWITCHES` 布尔、`ECHO_NUMERIC_SWITCHES` 数字不加引号、`ECHO_ARRAY_SWITCHES` 输出 `[...]` 或裸值时的 `true`），按去掉前导 `--` 的名字排序，位置参数保持在命令名之后；`PARSEABLE_COMMANDS` 不输出；removed-flag 的报错发生在回显之后（与参考一致）。

证据：15 条 oracle 命令（install/lock/add/binstubs/outdated/cache/check/show 及 `--retry`/`--jobs`/`--no-color`/`--without`/`--frozen`/`--update` 组合）的 `Running ...` 行与参考逐字相同；`spec/m7_verbose_echo_spec.cr` 8 例（渲染、排序、profile、PARSEABLE、无 `--verbose`、removed-flag 前回显）；差分夹具 `init-verbose` 在 4.0.24 与 2.7.2 均 PASS；负对照去掉排序后 `--version "2.8.1"` 用例失败（1 failure），恢复后 8/0。

已声明差异（未复刻）：参考在 `--verbose` 下还会输出调试层（`Resolving dependencies because there's no lockfile`、`Using a local server, bundler won't use the CompactIndex API`、`Using bundler 4.0.24`、`N:  <name> (<version>) from <path>`、`Writing lockfile to <path>`、`Found no changes, using resolution from the lockfile`），异常时打印完整 Ruby 回溯；这些都不在本实现范围内，因此 verbose 形态除 `init-verbose` 外不设差分夹具。

附带修复：`bundle remove` 的 requirement 渲染改按参考 `pretty_dependency`（即 `Gem::Dependency#to_s` / `Gem::Requirement#to_s`），裸版本 `"2.8.1"` 现输出 `(= 2.8.1)` 而不是 `(2.8.1)`；新增 `Commands.pretty_requirement`，差分夹具 `remove-bare-requirement` 双 profile PASS，`spec/m7_add_remove_spec.cr` 增 1 例。

## 2026-11-16（M7(2)/M7(3)：无 lockfile 的 `fund`/`clean`/`binstubs` 走 local-only 解析）

参考里只有 `check`（`bundler-4.0.24/lib/bundler/definition.rb:170-180`：`resolve_remotely! if @dependency_changes` 之后 `sources.local_only!`）与 `install` 会访问索引；`binstubs`（`cli/binstubs.rb:12-26`）、`clean`（`cli/clean.rb:11-14`）、`fund`（`cli/fund.rb:14-27`）都只走 `Definition#materialize → resolve`，从不 fetch。因此无 lockfile 时它们对缺失 gem 报 `Could not find gem '<name> (<req>)' in locally installed gems.`（`resolver.rb` 的 `raise_not_found!` 拼 `pretty_dependency`，`source/rubygems.rb:122-136` 在 `@allow_remote = false` 时把 source 呈现为 `locally installed gems`），stdout 只有 `Resolving dependencies...` 一行。

修复前本实现在这三条命令上无锁即 `Could not find <path>/Gemfile.lock for resolution`（exit 20）。

实现：
- `src/celerite/cli/commands.cr`：新增 `materialize_lockfile(definition, progress = nil, local_only = false)`，无锁时用 `Resolution` 现场解析、返回内存锁、不落盘；`clean`/`binstubs`/`fund` 均传 `local_only: true`。
- `src/celerite/resolution.cr`：`index_specs_for` 在 `@local_only` 下直接返回本地候选（空也返回，交给 resolver 出参考消息，而不是提前抛 `GemNotFoundError`）；`make_source` 按 `@local_only` 输出 `locally installed gems`；`local_index_specs` 额外把项目 bundle path 的 `specifications` 目录交给桥（`project_spec_dir`），并对 `from_dir` 条目跳过 `GEM_HOME` 前缀过滤。
- `assets/bridge/server.rb`：`op_installed_specs` 接受 `dir`，逐 gemspec `Gem::Specification.load` 追加（标 `from_dir`、按该树推出 `full_gem_path`），`uniq { full_name }`；目录先 `tr("\\", "/")` 再 `Dir.glob`（Ruby 在 Windows 把反斜杠当转义）。
- `src/celerite/cli/commands_install.cr`：`binstubs` 文案按参考补齐（无参 `` `bundle binstubs` needs at least one gem to run. ``；`bundler` 走 `Bundler itself does not use binstubs because its version is selected by RubyGems` 且 `--all` 时也覆盖；`There are no executables for the gem <name>.` 与依赖提示；`Skipped <a> since it already exists.` 等合并文案 + `If you want to overwrite skipped stubs, use --force.`）；`remove` 之外不再有第二套 requirement 渲染。

证据：无锁 6 场景（`fund`/`clean --dry-run`/`binstubs` × 已安装/未安装）stdout、stderr、退出码与参考逐字相同；binstubs 文案矩阵 5 例与重复写桩 4 例全 same；`spec/m7_no_lockfile_commands_spec.cr` 4 例 0 失败；差分夹具 `fund-no-lockfile`/`clean-no-lockfile` 在 4.0.24（2 passed）与 2.7.2（含回归 4 passed）均 PASS；负对照把 `fund` 的 `local_only` 改回 `false` 时该 spec 失败（`Fetching source index from file:///…/gem-index/` 出现），恢复后 4/0。

已声明差异：`check` 在 install 之后仍会打印 `Fetching source index …`（与参考一致，不属本节范围）；参考在 `--verbose` 下附带的调试层不复刻。
## 2026-11-16（M7(2)：`bundle config` 的 base 弃用接口、作用域校验与取值呈现）

参考锚点：`bundler-4.0.24/lib/bundler/cli/config.rb`（`base` 按原始 ARGV 复算替换串并经 `SharedHelpers.feature_deprecated!` 打印消息；`Base#validate_scope!` 的 `inside_app? ? "local" : "global"` 与双 scope 的 `InvalidOption`；`Base#run` 的 `--delete` 与无值分支、`current_value.nil? ? 1 : 0`；`confirm`/`confirm_all`）、`bundler/settings.rb:109-120`（temporary→local→env→global→DEFAULT_CONFIG）、`:425-439`（`converted_value`：未设置的数组键得到 `[]`、布尔/数字默认键非 nil）、`:205-228`（`pretty_values_for` 四层）、`:441-462`（`printable_value`：凭证键 `[REDACTED]`，含 `:` 的字符串按 `user:pass` 处理，因此 Windows 路径显示成 `"C:[REDACTED]"`）、`bundler/errors.rb:34`（`InvalidOption` 状态 15）与 `bundler/friendly_errors.rb:31-36`（`ui.error message, wrap: true`，80 列折行）。

oracle（4.0.24，隔离 HOME/BUNDLE_USER_*）：`config get without|cache_all|retry`（有默认值）退出 0；`config get jobs|path|mirror.…`（无默认值）退出 1；`config get user_cache` 打印 `"C:[REDACTED]"`；`config get gem.push_key` 打印 `"[REDACTED]"`；`config frobnicate` 打印 `[DEPRECATED] … Use `bundle config get frobnicate` instead.` 再执行 get、退出 1；`config without development` 打印弃用行、写入本地配置、退出 0；`config --delete without` 的弃用行改写为 `unset`；`config path vendor/bundle extra` 的弃用行说 `get`，实际仍按 `set` 写入 `"vendor/bundle extra"`；`config list --parseable` 打印 `path=…|without=[:development]` 且无表头；`config get path --global` 为 Thor 参数错误（退出 15）；`config set/unset --local --global …` 打印 `The options global and local were specified. Please only use one of the switches at a time.`（退出 15）。

修复前缺陷：未知子命令一律 `Could not find command "config …"`（退出 15），base 弃用接口整体缺失；`config get` 只在「值非 nil」时退出 0，漏掉参考的默认值规则（`retry`/`without`/`cache_all` 退出码相反）；无 `--parseable`；无 scope 冲突校验；凭证与 userinfo 未脱敏；全局配置文件路径以原生反斜杠打印（参考来自 `Pathname`，恒为 `/`）。

实现：`src/celerite/config.cr` 新增 `STRING_KEYS`/`string_key?`/`printable_value`/`parseable_converted`/`display_path`，`pretty_values_for` 与 `display_value` 走新呈现层；`src/celerite/cli/commands.cr` 的 `config` 在未知子命令时进入 `config_deprecated`（按原始 `["config"] + rest` 复算替换串、打印参考弃用行，随后仍按原始 name/value 执行对应子命令），并补 `config_scope_conflict`、`config_warn_unused_scope`、`config_confirm_or_parseable`、`config_set_message`、`config_argument_error`。

证据：32 条命令的 A/B 矩阵 `TOTAL=32 DIFF=0`；`spec/m7_config_semantics_spec.cr` 7 例与 `spec/config_spec.cr` 联跑 16/0；差分夹具 `config-get-default`/`config-deprecated-get`/`config-list-parseable`/`config-get-user-cache`/`config-global`/`config-local`/`config-set-unset` 在 4.0.24 上 7/7 PASS，在 2.7.2 上 5 passed + 2 documented deferrals；`spec/cli_spec.cr` 的 `config get reports unset values` 由「`retry` 未设置退出 1」改为参考语义（退出 0，另断言 `jobs` 退出 1）。

已声明差异：2.x 的旧式 base 接口未实现（2.x `config <name>` 不打印弃用行且始终退出 0；2.x `config get <name>` 未设置也退出 0），对应夹具以 `deferred-2.7.2` 标注原因；`--verbose` 下参考附带的调试层不复刻。

未验证：插件命令与 `config` 子命令同名冲突；`BUNDLE_IGNORE_CONFIG` 与临时设置叠加时的优先级；真实用户 HOME（含历史残留键）下 `config list` 的输出。
## 2026-11-16（M7(2)：命令面的 unknown-switch 拒绝与只读命令的本地/远程解析分工）

参考锚点：`bundler-4.0.24/lib/bundler/cli.rb` 的 `method_option` 声明（口径用 `Bundler::CLI.commands[name].options` 反射得到）、`bundler/cli.rb:669-671`（`subcommand("doctor", Doctor)`，`doctor` 的选项属于子命令 `diagnose`）、`cli/doctor/diagnose.rb:74-76`（`check!` 直接复用 `Check#run`，因此缺失列表后仍打印安装提示）、`cli/licenses.rb` 与 `cli/outdated.rb`（只走 `Bundler.load`/`definition.specs`，不触发索引抓取）、`shared_helpers.rb` 与 `friendly_errors.rb:31-36`（`Unknown switches` 走 `ui.error`，退出 15）。

修复前实测（参考 4.0.24，`--bogus` 或命令自带未知开关）：

| 命令 | 参考 | 修复前 celerite |
| --- | --- | --- |
| `licenses --format=csv` | `Unknown switches "--format=csv"`，15 | 0，静默忽略 |
| `pristine`/`console`/`env`/`init`/`gem`/`fund`/`remove`/`open` `--bogus` | `Unknown switches "--bogus"`，15 | 0，静默忽略 |
| `outdated --bogus` | `Unknown switches "--bogus"` + `Did you mean?  "--groups"`，15 | 0，静默忽略 |
| `doctor --bogus` | `ERROR: "bundle doctor diagnose" was called with arguments ["--bogus"]` / `Usage: "bundle doctor diagnose [OPTIONS]"`，15 | 0，静默忽略 |
| `licenses`（无 lockfile、未安装） | 7，`Could not find gem 'json_pure (= 2.8.1)' in locally installed gems.` | 20，`Could not find …/Gemfile.lock for resolution` |
| `outdated`（无 lockfile、未安装） | 7，同上 | 0，无输出 |
| `doctor`（无 lockfile、未安装） | 1，stdout 抓索引 + `The following gems are missing` / ` * json_pure (2.8.1)` / ``Install missing gems with `bundle install` `` | 20，锁文件错误 |
| `fund --group development`（依赖都在 default 组） | 0，`None of the installed gems you directly depend on are looking for funding.` | 7，`Could not find gem 'json_pure' in locally installed gems.` |

实现：

1. `src/celerite/cli/commands.cr` 新增 Thor 口径的开关表：`SWITCH_FLAGS_CLASS`（`--help/-h/--no-color/--quiet/--verbose/-V`）、`SWITCH_VALUES_CLASS`（`--retry/-r`），以及 `BARE_*`、`INIT_*`、`FUND_*`、`OPEN_*`、`REMOVE_*`、`OUTDATED_*`、`GEM_*`、`DOCTOR_SUBCOMMAND_*`；新增 `subcommand_arguments` 把子命令路由下未被选项表消费的 token 收集成「剩余参数」。
2. `src/celerite/cli/commands_surface.cr`：`remove`/`env`/`licenses`/`fund`/`open`/`pristine`/`init`/`outdated`/`console`/`gem` 开头统一调用 `reject_unknown_switches`；`doctor` 用 `subcommand_arguments` 复刻子命令式参数错误。
3. `licenses` 改 `materialize_lockfile(definition, stdout, local_only: true)`；`outdated` 在无锁文件时先做一次静默的 `materialize_lockfile(definition, nil, local_only: true)`（复刻 `Bundler.load` 先物化）；`doctor` 改 `materialize_lockfile(definition, stdout)`（远程，等价 `check!`）并补 `Install missing gems with \`bundle install\`` 提示行。
4. `fund` 先按 `--group`/`without` 过滤 `evaluation.dependencies`，依赖为空时直接输出「没有需要资助的 gem」，不再解析 bundle（参考 `dependencies_for` 先缩窄定义）。
5. `dispatch` 对 `--help`/`-h` 统一返回 0 并打印 usage（manpage 文本仍为已声明差异，`exec` 保持透传）。

证据：24 条 A/B 矩阵（含 `--no-color`/`--retry 3` 仍被接受、`fund --group development`、`outdated --parseable`、裸 `licenses`/`outdated`/`doctor`/`fund`）逐字相同（仅沙箱路径不同）；`spec/m7_command_switch_surface_spec.cr` 9 例 9/0；差分夹具 `unknown-switch-licenses`/`unknown-switch-doctor`/`fund-group-empty`/`outdated-no-lockfile` 在 4.0.24 与 2.7.2 上各 4/4 PASS；负对照（注释掉 `outdated` 的本地预解析）令 `outdated-no-lockfile` 变为 `reference=7 celerite=0` 并多出抓索引输出。

已声明差异：`--help` 的 manpage 文本不复刻（退出码与是否为错误一致）；`lod`/`config` 等命令的内部选项文案仍按各自既有实现。

未验证：`outdated` 在已有 lockfile 但部分 gem 未安装时的逐条输出；`doctor --ssl`/`--tls-version`/`--verify-mode` 的诊断行为；`gem --ext=c` 等仅在模板生成阶段可见的开关语义。

## 2026-11-16（M7(3)：`bundle gem` 的 Thor 否定开关、removed `--rubocop` 与 git 门控）

参考锚点：

- `bundler-4.0.24/lib/bundler/cli.rb:607-608`：`gem` 任务里 `--rubocop` 与 `--no-rubocop` 都直接 `raise InvalidOption`（`--rubocop has been removed, use --linter=rubocop` / `--no-rubocop has been removed, use --no-linter`），exit 15。
- `bundler-4.0.24/lib/bundler/vendor/thor/lib/thor/parser/`：Thor 为每个布尔选项自动生成 `--no-<name>` 否定式，故 `--no-git` 是合法写法；值选项没有否定式。
- `bundler-4.0.24/lib/bundler/cli/gem.rb:45-49`：`user.name` / `user.email` / `github.user` 三次 `git config` 读取全部以 `use_git` 为条件，否则 gemspec 保留 `TODO: Write your name` / `TODO: Write your email address`。
- `bundler-4.0.24/lib/bundler/cli/gem.rb:113-116`：只有 `use_git` 时才 merge `gitignore.tt`，并把 `.gitignore` 追加进 `ignore_paths` —— 于是 gemspec 里的清单在 `--no-git` 时是 `%w[bin/ Gemfile]`。
- `bundler-4.0.24/lib/bundler/cli/gem.rb:257-262`：git 初始化行是 `Bundler.ui.info "\nInitializing git repo in #{target}"`（消息自带前置空行），`git init` 的 stdout 被吞掉。
- `bundler-4.0.24/lib/bundler/cli/gem.rb:289`：成功行 `"\nGem '<name>' was successfully created. …"`。
- `bundler-4.0.24/lib/bundler/cli/gem.rb:299-310`、`:322-426`：`ask_and_set` / `ask_and_set_test_framework` / `_ci` / `_linter` 先读 `options[key] || settings["gem.<key>"]`，只有为 nil 才打印提示并提问 —— 预置 `BUNDLE_GEM__MIT` 等环境变量即可让参考完全不交互。

修复前（同一沙箱、独立 HOME，无锁文件）：

| 命令 | 参考 4.0.24 | 修复前 |
| --- | --- | --- |
| `gem demo --no-git` | exit 0；9 个文件，无 `.gitignore`，无 `.git` | exit 15 `Unknown switches "--no-git"` + `Did you mean?  "--git"` |
| `gem demo --rubocop` | exit 15 单行 `--rubocop has been removed, use --linter=rubocop` | exit 15 `Unknown switches "--rubocop"` + 建议行 |
| `gem demo --no-rubocop` | exit 15 单行 `--no-rubocop has been removed, use --no-linter` | 同上 |
| 差分夹具 `gem-default`（4.0.24） | 先打印 20 行交互提示再按默认模板生成 | FAIL：我方缺交互提示文本，diff 为参考多出的 20 行 |

实现：

1. `Commands.negated_flag?(name, allowed_flags)`：`unknown_switch_tokens` 把 `--no-<name>` 视为 `--<name>` 的 Thor 生成否定式，只要 `--<name>` 在允许表里就放行；值选项不受影响。
2. `Commands.gem` 在脚手架之前处理 `--rubocop` / `--no-rubocop`（原文写 stderr、exit 15、不创建任何文件），并把「保持默认」的否定式 `--git/--no-git/--no-mit/--no-coc/--no-changelog/--no-exe/--no-bundle` 加入白名单。
3. `GemTemplate.render` 的 `.gitignore` 条目改为条件项；`gemspec` 新增 `use_git` 参数，ignore 清单随之为 `bin/ Gemfile .gitignore` 或 `bin/ Gemfile`。
4. `Commands.gem` 的 author/email/github_username 只在 `use_git` 时读 `git config`，否则留空并落到 `TODO:` 占位。
5. git 初始化行改为先输出一个空行再打印 `Initializing git repo in <path>`，与 `gem.rb:257` 的 `"\nInitializing …"` 对齐。

证据：

- A/B（`.tmp-scratch/gem59e`，两侧各自 HOME/GEM_HOME/GEM_PATH/TEMP/WORKDIR，项目 `.bundle/config` 预置六项 `BUNDLE_GEM__*: "false"`）：`gem demo --no-git --no-mit --no-coc --no-changelog --no-exe --no-bundle` 两侧 exit 0、stdout 逐字相同，9 个文件 SHA-256 全部相同。
- A/B（`.tmp-scratch/gem59f`，git 启用）：归一化沙箱路径后 stdout 相同，10 个文件（含 `.gitignore` 73 字节与带 Contributing 段的 README 1671 字节）逐字节相同；两侧 stderr 的 `LF will be replaced by CRLF` 警告数量与条目一致。
- `spec/m7_gem_template_spec.cr`：**7 examples, 0 failures**（原 3 例 + 新增 `--no-git` 脚手架、默认否定式、`--rubocop`、`--no-rubocop` 共 4 例）。
- 差分：4.0.24 `gem-default`、`gem-no-git` 均 PASS（各 exit 0）；2.7.2 两者均按 `deferred-2.7.2` 跳过。

已声明差异：

- 交互式脚手架提问（test / CI / linter / license / COC / changelog）未实现；差分夹具通过 `extra/.bundle/config` 预置 `BUNDLE_GEM__*: "false"` 让参考跳过提问，从而只比对模板与信息输出。
- 非默认模板选项（`--mit`、`--coc`、`--changelog`、`--exe`、`--bundle`、`--linter`、`--test` 等）仍按 fast-fail 处理并打印 `bundle gem option --x is not supported by Celerite`，不生成对应文件。
- 2.7.2 参考使用旧版成功链接 `https://bundler.io/guides/creating_gem.html` 且 `templates/newgem` 内容不同，故两个 gem 夹具在 2.7.2 下 deferred。

未验证：

- `--linter=rubocop` 生成的 `.rubocop.yml` 未与参考比对（属非默认模板分支）。
- `--no-git` 与 `git add` 交互时的 `git status` 输出未额外断言。
## 2026-11-16（M7(2)：`bundle exec` 的自有开关与 bundler lib 解析）

参考锚点：`bundler/cli.rb:419-431`（`exec` 以 splat 收尾并声明 `--gemfile`/`--keep-file-descriptors`）、`bundler/cli/exec.rb:59`（`require_relative "../setup"`）、`bundler/shared_helpers.rb:362-378`（`set_rubyopt`/`set_rubylib` 用 `File.expand_path("..", __dir__)` 取 Bundler 自身 lib 根，与 `GEM_PATH` 无关）。

修复前（A/B，`gem "json_pure", "2.8.1"`、隔离 HOME/GEM_PATH）：

```text
exec ruby -e "puts 7"                 ref 0     cel 1   cannot load such file -- C:\Ruby40-x64\lib\bundler/setup (LoadError)
exec --keep-file-descriptors ruby -e  ref 0     cel 127 bundler: command not found: --keep-file-descriptors
exec --gemfile Gemfile ruby -e        ref 0     cel 127 bundler: command not found: --gemfile
exec --help                           ref 0     cel 127
exec                                  ref 128   cel 128 bundler: exec needs a command to run
exec no_such_command_xyz              ref 127   cel 127
exec --bogus true                     ref 127   cel 127（参考同样把未知开关当命令）
```

根因：`find_bundler_lib` 在 `GEM_PATH` 被隔离时找不到 bundler gem，回退到 Ruby 自己的 lib 根（`C:\Ruby40-x64\lib`，不含 `bundler/setup.rb`），却仍把它拼进子进程 `RUBYOPT`，于是子进程在执行命令前就 `LoadError`。

实现：

- 桥 `op_ruby_environment` 新增 `default_path`（`Gem.default_path`：RubyGems 内置搜索路径，忽略用户设置的 `GEM_PATH`）。
- `find_bundler_lib` 依次搜索 `default_path`、`default_gem_dir`、`gem_paths`、`user_gem_dir` 下的 `gems/bundler-<ver>/lib`，再按 `bundler-*` 目录降序取任一版本；Ruby lib 根只有确实含 `bundler/setup.rb` 时才采用，否则返回空串。
- 空串时**不注入** `RUBYOPT`/`RUBYLIB`/`BUNDLER_SETUP`/`BUNDLE_BIN_PATH`，避免把不可解析的 `-r` 交给子进程。
- `exec` 先解析自身开关再转发命令：`--help`/`-h` 打印 usage 并 exit 0、`--keep-file-descriptors`/`--no-keep-file-descriptors` 接受、`--gemfile VALUE`/`--gemfile=VALUE` 设置 `BUNDLE_GEMFILE`、`--` 终止解析、未知 `-x` 仍作为命令交给执行器（与参考一致，127）。
- `--gemfile` 写入的 `BUNDLE_GEMFILE` 在调用结束后还原：`CLI.run` 在 spec 中以进程内方式调用，不还原会污染后续用例。

证据：

- 8 条 A/B（`exec ruby -e …`、`--gemfile`、`--gemfile=`、`--keep-file-descriptors`、`--`、`--verbose`、`--no-color`、`BUNDLE_GEMFILE` 透传）全部 same=True（仅沙箱路径差异未归一化）。无 lockfile 且未安装时两侧同为 exit 1，回溯逐字相同（2453 字节）。
- 新 `spec/m7_exec_spec.cr` 6 examples / 0 failures；负对照（`find_bundler_lib` 直接返回 Ruby lib 根）→ `exec ruby -e "puts 7"` 得 exit 1 + `LoadError`，还原后 exit 0。
- 差分夹具 `exec-unknown-command`（127）与 `exec-no-arguments`（128）：4.0.24 `2 passed`、2.7.2 `2 passed`。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、全量 **538 examples, 0 failures, 4 errors**（4 为既有 msys Low-IL `git_source_spec`）、`git diff --check` 0。

已声明差异：`exec --help` 打印 Celerite 的 `Usage:` 摘要而非 `bundle-exec(1)` manpage（与其余命令同一差异）。

未验证：

- `--keep-file-descriptors` 的真实 fd 继承行为（本机 Windows 无对应语义，只验证开关被接受）。
- `disable_exec_load=1` 与 `--gemfile` 组合未单列夹具。

## 2026-11-16（M7(2)：`bundle open` 的参数校验、编辑器顺序与 select_spec 选 gem）

参考锚点：`bundler-4.0.24/lib/bundler/cli/open.rb:12-26`（`run`：先 `--path` 空值检查，再按 `BUNDLER_EDITOR`/`VISUAL`/`EDITOR` 找编辑器，无编辑器直接提示并返回；随后 `select_spec(name, :regex_match)`，`default_gem?` 打专用提示，否则 `system(*editor_command(editor) << File.join([root_path, path].compact), chdir: root_path)`，失败打 `Could not run '<command>'`），`:28-37`（Windows 上把「现存文件」当单字，其余走 `Shellwords.split`）；`lib/bundler/cli/common.rb:68-96`（`select_spec`：精确名→正则命中→`default_gem_spec`→`ask_for_spec_from`，0 条时按「组被忽略」或 `gem_not_found_message` 抛错）、`:98-101`（`Gem::Specification.find_all_by_name(name).last` 且 `default_gem?`）、`:103-111`（`N : name` + `0 : - exit -` + `>  `，`num > 0 ? specs[num-1] : nil`）、`:113-123`（`Could not find gem '<name>'.` + `Did you mean …?`）；Thor 的参数错误（`ERROR: "bundle open" was called with no arguments` / `with arguments ["a", "b"]` + `Usage: "bundle open GEM"`，exit 15）在 `run` 之前发生。

修复前（4.0.24 实测）：

- `bundle open` → 我方 exit 1、自造 `Usage: bundle open [GEM]`；参考 exit 15 + 两行 Thor 错误。
- `bundle open json_pure --path`（无值）→ 我方照样打开；参考 exit 15 `Cannot specify \`--path\` option without a value`。
- 编辑器只认 `BUNDLER_EDITOR`/`EDITOR`，漏掉 `VISUAL`；缺失 gem 报 `Could not find '<name>' in the bundle.`，与参考的 `Could not find gem '<name>'.` 不同；正则与默认 gem 回退都未实现。
- `bundle issue` 的 `## Environment` 首行仍带 ` (Celerite 0.1.0, compatibility profile)` 后缀（`env` 早已去掉）。

实现：

1. `src/celerite/cli/commands_surface.cr` 的 `open` 重写：先 `reject_unknown_switches`（`--path` 属值选项），再按「参数个数 → `--path` 空值 → 编辑器 → 选 gem」的顺序校验，错误文本与退出码照抄参考；编辑器取 `BUNDLER_EDITOR`/`VISUAL`/`EDITOR` 中第一个非空值。
2. 选 gem：`materialize_lockfile(definition, nil, local_only: true)` 得锁定 specs（参考 `Bundler.definition.specs` 不碰索引），精确名 → 正则命中（`RegexpError` 退化为「找不到」）→ `bridge.default_gem_spec(name)` 追加；0 条时按 Gemfile 声明的组给「because it's in the group … configured to be ignored」，否则 `gem_not_found_message_for`（含 `Did you mean?`）；>1 条打印 `N : name` / `0 : - exit -` / `>  `（参考提示符是 `> ` 加一个空格）并从 stdin 读编号，EOF 或 `0` 退出 0。
3. gem 目录取 `spec.full_gem_path`（桥新增 `default_gem_spec` op；已安装 specs 由 `installed_specs` 提供 `full_gem_path`），只有查不到时才退回 `<install root>/gems/<full_name>`；`--path` 以 `/` 形式拼在 gem 目录下（RubyGems 的 `full_gem_path` 在 Windows 上也是正斜杠）。
4. 执编辑器：Windows 上 `.cmd`/`.bat` 先按 `CreateProcess` 直接跑，失败后用 `cmd.exe` 重试（Ruby 的 `system` 同样经命令处理器执行批处理）；失败打 `Could not run '<cmd>'` 并返回 0。
5. `issue` 的环境报告首行改用与 `env` 相同的 `Bundler       <version>`。

证据：

- A/B（`.tmp-scratch/open61`，两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/`BUNDLE_PATH`/`BUNDLE_USER_*`，`EDITOR`/`BUNDLER_EDITOR`/`VISUAL` 指向记录参数的 `.cmd`）9 例全同：`open`、`open json_pure extra`、`open json_pure extra --path lib`、`open json_pure --path`、`open nosuchgem`、`open jso`、`open json`（默认 gem 选择器）、`open json_pure --path lib`、`open json_pure`。
- `spec/m7_open_spec.cr` **8 examples, 0 failures**（无参/多参/空 `--path`/无编辑器/找不到 gem/精确名/正则/`--path lib`）。
- 差分夹具 `open-no-arguments`、`open-extra-arguments`：4.0.24 与 2.7.2 各 **2 passed**。
- 负对照：删掉 `open` 的无参分支（改为直接 `return 0`）→ `spec/m7_open_spec.cr` `8 examples, 1 failures`（`Expected: 15 got: 0`），还原后 8/0。
- 门禁：`crystal tool format --check src spec` 0、`crystal build src/cli.cr` 0、全量 `crystal spec` **546 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）。

已声明差异：`open --help` 打印 Celerite 的 `Usage:` 摘要而非 `bundle-open(1)` manpage（与其余命令同一差异）；交互式选择器的提示符已按参考补成 `>  `（两空格），但输入回显依赖终端，未做夹具。

未验证：

- 选择器输入非法编号（如 `9`）后两侧的返回码一致（我方返回 0，参考 `specs[num-1]` 为 nil 亦返回 0），未做自动化用例。
- 默认 gem 选择后 `Unable to open …` 路径只在手工探针里验证（ci 无默认 json gem 保证）。
- 另一处**发现但未修**：只设 `GEM_HOME`/`GEM_PATH`、未设 `BUNDLE_PATH`/`path` 时，参考把 gem 装进 `Gem.dir`（GEM_HOME）且**不**打印 `Bundled gems are installed into …`，我方仍装进 `<home>/.bundle/ruby/<abi>` 并打印该行；`open` 已改为读 `full_gem_path`，不会因此开错目录，但 `install` 的目标目录本身仍是差异（记入下轮候选）。
## 2026-11-16（M7(4)：`install` 目标目录的 `Settings::Path` 语义与 `path`/`path.system` 冲突）

参考契约（`bundler-4.0.24/lib/bundler/settings.rb`）：

- `Settings#path`（L238-251）：逐个 config 层取 `path`/`path.system`/`disable_shared_gems`，`system_path = path_system || (disabled_shared_gems == false)`；没有任何配置时若有 `deployment` 则 `path = "vendor/bundle"`。
- `Path#use_system_gems?`（L260-264）：`system_path` 为真 → 系统 gems；显式 `path` → 非系统；否则 `!Bundler.feature_flag.bundler_5_mode?`（2.7.2/4.0.24 都是 `major < 5`，即默认系统 gems）。
- `Path#base_path`（L266-271）：显式 `path` → 否则 `.bundle`（仅非系统 gems）→ 否则 `Bundler.rubygems.gem_dir`。
- `Path#base_path_relative_to_pwd`（L273-285）：`expand_path(Bundler.root)` 后相对 pwd；以 `..` 开头且 `base_path` 本身是绝对路径时回退成配置里的绝对写法；否则加 `./` 前缀；`Pathname` 在 Windows 也输出 `/`。
- `Path#validate!`（L287-297）：`explicit_path && system_path` → `InvalidOption`，消息为 `Using a custom path while using system gems is unsupported.` + `path:` / `path.system:` / `disable_shared_gems:` 三段 `pretty_values_for`（friendly-errors 以 `wrap: true` 折行，exit 15）。
- `cli/install.rb` L56-64：`Bundle complete!` 之后，系统 gems 打印 ```Use `bundle info [gemname]` to see where a bundled gem is installed.```，否则打印 ``Bundled gems are installed into `#{base_path_relative_to_pwd}` ``（base 路径，不含 `ruby/<abi>`）。

修复前实测（`.tmp-scratch/conflict62*`、`msg62*`，两侧独立 HOME/GEM_HOME/TEMP）：

- `.bundle/config` 同时写 `BUNDLE_PATH: "vendor/bundle"` 与 `BUNDLE_PATH__SYSTEM: "true"`：参考 `install` **exit 15** + 上述三段消息；我方 **exit 0**，静默按 `path` 装到 `vendor/bundle`（`path.system` 被忽略）。
- `path.system` 生效时参考打印 `Use \`bundle info [gemname]\` …`；我方打印 `Bundled gems are installed into \`<绝对 Gem.dir>\``。
- 显式 `BUNDLE_PATH=vendor/bundle` 时参考打印 `Bundled gems are installed into \`./vendor/bundle\``（相对 pwd、带 `./`）；我方打印绝对路径。

实现（`src/celerite/resolution.cr` 的 `InstallPaths` + `src/celerite/errors.cr` + `src/celerite/cli/commands_install.cr`）：

1. 新增 `PathConflictError < Error`（`status_code` 15、`wrap?` true），由 `InstallPaths.validate!` 在 `explicit_path` 与 `system_path` 同时成立时抛出；消息按 `pretty_values_for` 生成与参考同形的三段块（空行 + 标题行 + 值）。
2. `InstallPaths.use_system_gems?`：`path.system == true` 或 `disable_shared_gems == false` → 系统 gems；显式 `path` → 非系统；其余保持产品默认 `<home>/.bundle`（**已声明差异**，见下）。`system_gems?` 保留为同义入口，`base_path`/`gem_root`/`ruby_root` 统一走它。
3. `base_path_relative_to_pwd(config, project_root, system_gem_dir)`：用配置里的原始拼写判断 `..` 分支（相对路径则保留相对写法），否则加 `./` 前缀，最后把 `\` 归一成 `/`；跨盘等 `ArgumentError` 时退回绝对路径。
4. `install` 的 summary 按 `use_system_gems?` 分支：系统 gems 打印 `bundle info` 提示，否则打印相对 base 路径（不再带 `ruby/<abi>`）。

证据（首辅亲跑）：

- 探针（`.tmp-scratch/msg62e`，两侧各自 `GEM_HOME` 隔离、其余输入相同）：`BUNDLE_PATH__SYSTEM=true` 与 `BUNDLE_PATH=vendor/bundle` 两例的 stdout/stderr 内容逐字相同（仅参考 CRLF 与我方 LF 的行尾差异），末行分别为 `Use \`bundle info [gemname]\` …` 与 `Bundled gems are installed into \`./vendor/bundle\``。
- 冲突探针（`.tmp-scratch/conflict62d`）：我方 **exit 15**、stderr 与参考同形（三段 `pretty_values_for`，80 列折行）。
- 差分夹具 `install-path-conflict`（`extra/.bundle/config` 同时写两键，`command`=`install`）与 `install-custom-path-summary`（`BUNDLE_PATH: "../vendor-bundle"`）：4.0.24 **2 passed**、2.7.2 **2 passed**；回归 `install-fresh`、`check-no-lockfile-missing` 仍 PASS（4.0.24 共 4 passed）。
- `spec/m7_path_system_spec.cr` **8 examples, 0 failures**（新增：冲突 → `PathConflictError` 且消息含三段标题；`disable_shared_gems: false` → 系统 gems；`base_path_relative_to_pwd` → `./vendor/bundle` 且不含反斜杠；`path.system` 端到端安装打印 `bundle info` 提示；自定义 `path` 端到端打印 `./vendor/bundle`）。
- 负对照：把 `InstallPaths.base_path` 里的 `validate!(config)` 注释掉重建 `bin/celerite-nc.exe` → 差分 `install-path-conflict` **FAIL**（我方 exit 0、装了 `vendor/` 并在 stdout 少掉整段冲突消息），恢复后 PASS。
- 门禁：`crystal tool format --check src spec` 0、`crystal build src/cli.cr` 0、全量 `crystal spec` **549 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）。

已声明差异：

- **无任何 `path` 配置时的默认目标**：参考装进系统 gems（`Gem.dir`）并打印 `bundle info` 提示；我方仍装进 `<home>/.bundle/ruby/<abi>` 并打印 `Bundled gems are installed into …`。改成系统 gems 会让 9 个未隔离 `GEM_HOME` 的 spec 与所有本地使用直接写宿主 RubyGems 目录，故本轮只把语义入口（`use_system_gems?`）与消息分支对齐，默认目标的切换留待下轮并需同时给相关 spec 加 `GEM_HOME` 隔离。
- `deployment` 且无显式 `path` 时参考默认 `vendor/bundle`（settings.rb L248）：我方未实现（同一轮候选）。
- `bundler_5_mode?` 分支未建模（2.7.x/4.x 下恒为 false，不影响当前 profile）。

未验证：

- `disable_shared_gems: false` 的端到端安装（只做了 `use_system_gems?`/`gem_root` 单测）。
- 冲突配置下不计算 gem root 的命令（如 `config list`）是否也 exit 15，未逐条对齐。
- 参考在 `path` 指向不同盘符时的 `ArgumentError` 回退分支未在本机复现（只做了代码路径镜像）。

## 2026-11-16（M7(4)：部署模式 `vendor/bundle` 默认目标与 frozen CHECKSUMS 校验）

参考契约：

- `Settings#path`（settings.rb L238-251）：没有任何 `path` 配置且 `self[:deployment]` 为真时，把 `path` 当成 `"vendor/bundle"`，于是 `Path` 走进显式路径分支（非系统 gems）。
- `Path#use_system_gems?`（L260-264）：`path.system` 为真或 `disable_shared_gems: false` 时为系统 gems；显式 `path`（含部署默认值）时为 false。
- `Path#base_path`（L266-271）：`explicit_path` → 否则 `".bundle"`（非系统 gems）→ 否则 `Gem.dir`。
- `Bundler.bundle_path`（bundler.rb L104）：`Pathname.new(configured_bundle_path.path).expand_path(root)`，相对路径按**项目根**展开，不按进程 cwd。
- `Bundler::Definition#ensure_equivalent_gemfile_and_lockfile`（definition.rb L475-492）：frozen 模式拒绝更新锁文件；`lockfile_changes_summary`（L906-921）里 CHECKSUMS 的两条理由按 `missing` → `empty` 排列（L973-1002 `check_lockfile`），`empty_checksums_actionable?` 见 L651-659；错误类是 `ProductionError`（status 16）。
- 调用点：`bundler/installer.rb:63-71`（先 `Bundler.create_bundle_path`，再 `definition.ensure_equivalent_gemfile_and_lockfile`）、`bundler/cli/check.rb:15`。

修复前（本机实测）：`BUNDLE_DEPLOYMENT=true` 且锁文件 `CHECKSUMS` 里 `json_pure (2.8.1)` 为空时，参考 **exit 16** 并打印两段消息、**先创建** `vendor/bundle/ruby/4.0.0`；我方 **exit 0**、装进 `<home>/.bundle` 并打印 `Bundled gems are installed into …`。另外显式 `path` 为相对路径时，我方按进程 cwd 展开，参考按项目根展开。

实现：

- `src/celerite/resolution.cr`：`InstallPaths` 新增 `DEPLOYMENT_PATH = "vendor/bundle"`、`deployment_path_requested?(config)`（无显式 `path` 且 `deployment` 为真）、`use_system_gems?` 首行对部署默认值返回 false；`base_path` 增加部署分支（`<project_root>/vendor/bundle`），并让显式 `path` 按 `config.project_root` 展开（镜像 bundler.rb L104）。
- `src/celerite/config.cr`：`Config` 记住 `project_root`（`getter project_root : String?`，构造时 `File.expand_path`），供相对 `path` 与部署默认值使用。
- `src/celerite/definition.cr`：新增 `validate_frozen_lockfile!(explicit_flag = false)`（`config.frozen?` 才走；无锁 → `Frozen mode is set, but there's no lockfile`；`lockfile_update_reason` 依次判 missing/empty；消息首行首字母大写 + `, but can't be updated because frozen mode is set` + `Run `bundle install` elsewhere …` 段；`explicit_flag` 或 `BUNDLE_FROZEN=true` 时省略 `If this is a development machine …` 段）与私有 `lockfile_update_reason`/`checksum_matches?`/`frozen_from_environment?`。
- `src/celerite/cli/commands_install.cr`：在进程锁之后、Cooldown 校验之前 `Dir.mkdir_p(gem_root)` 再 `definition.validate_frozen_lockfile!(rest.includes?("--deployment"))`（镜像 installer.rb L63-71 的顺序，部署失败仍留下 `vendor/bundle/ruby/<abi>`）。
- `src/celerite/cli/commands.cr`：`run_check` 在冻结无锁检查之后调用 `definition.validate_frozen_lockfile!`（镜像 cli/check.rb:15 早于解析）。

证据：

- A/B 四场景（`.tmp-scratch/dep63e`，ref/cel 各自隔离 `HOME`/`GEM_HOME`/`BUNDLE_USER_*`，`Start-Process` 直接重定向原始 stderr）：`BUNDLE_DEPLOYMENT=true` + 空 CHECKSUMS → 双方 **exit 16**、stdout/stderr **逐字相同**、`vendor/bundle/ruby/4.0.0` 均存在；`BUNDLE_FROZEN=true` → 双方 exit 16 且都**省略** `If this is a development machine` 段；`check` 同锁 → 双方 exit 16 同文；无 `CHECKSUMS` 段的锁 → 双方 exit 0 且都写入 `vendor/bundle/ruby/4.0.0/gems/json_pure-2.8.1`。
- `spec/m7_deployment_path_spec.cr` 6 examples / 0 failures（部署默认 base/relative/gem_root、显式 `path` 优先、空 CHECKSUMS install exit 16 + 目录已建、`BUNDLE_FROZEN` 省略提示、`check` 同错、无 CHECKSUMS 段照常安装）。
- 差分：新增夹具 `fixtures/differential/install-deployment-empty-checksums/`（`deploy` 标记 + 空 CHECKSUMS 锁 + `command`=`install`）在 4.0.24 与 2.7.2 均 `PASS (exit=16)`；回归 `install-path-conflict` / `install-custom-path-summary` / `install-fresh` / `check-no-lockfile-missing` 在 4.0.24 仍全 PASS（5 passed）。
- 负对照：注释掉 `install` 里的 `validate_frozen_lockfile!` 重建 `bin/celerite-nc.exe` → 差分 `install-deployment-empty-checksums` **FAIL**（参考 stderr 9 行消息全部缺失、我方 exit 0），还原后 PASS、`negative-control` 计数 0。
- 门禁：`crystal tool format --check src spec` 0、`crystal build src/cli.cr` 0、全量 `crystal spec` **555 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` msys Low-IL）、`git diff --check` 0。

已声明差异：

- frozen 校验只实现 CHECKSUMS 两条理由；参考 `lockfile_changes_summary` 里 Gemfile 依赖增删、`DEPENDENCIES` 变化等其余理由仍未实现（遇到时不会 exit 16）。
- 无任何 `path` 配置时的默认目标仍为产品默认 `<home>/.bundle`（上一节已声明；本轮把部署默认值与相对路径展开对齐，默认目标切换仍需同步给 9 个 spec 加 `GEM_HOME` 隔离）。
- `bundler_5_mode?` 分支未建模（2.7.x/4.x 恒 false，不影响当前 profile）。

未验证：

- 2.7.2 的 `install --deployment`（显式 flag → `explicit_flag` 为真）提示省略只做了代码路径镜像，未与参考逐字对照。
- 跨盘符的相对 `path`（`ArgumentError` 回退）未在差分中复现。
- 部署模式下 `.bundle/config` 的 `BUNDLE_FROZEN=false` 覆盖（`--deployment` 与 `frozen false` 组合）未逐条核对。
---
## 2026-11-16（M7(4)：无 `path` 配置时的安装目标与自定义 path 的物化边界）

参考锚点：
- `bundler-4.0.24/lib/bundler/settings.rb:238-251`：`Settings#path` 在 `path`/`path.system`/`disable_shared_gems` 都未配置时返回 `Path.new(nil, false)`。
- 同文件 `:260-264`：`Path#use_system_gems?` 先看 `system_path`、再看 `explicit_path`，都没有时才看 `!Bundler.feature_flag.bundler_5_mode?`。
- 同文件 `:266-271`：`Path#base_path` 在 `use_system_gems?` 为真时返回 `Bundler.rubygems.gem_dir`。
- `bundler-2.7.2/lib/bundler/feature_flag.rb` 与 `bundler-4.0.24/lib/bundler/feature_flag.rb`：`bundler_N_mode?` 定义为 `@major_version >= N`，故两个 profile 的 `bundler_5_mode?` 都是 `false`。
- `bundler-4.0.24/lib/bundler/cli/install.rb:56-64`：`use_system_gems?` 时打印 ``Use `bundle info [gemname]` to see where a bundled gem is installed.``，否则打印 ``Bundled gems are installed into `<base_path_relative_to_pwd>` ``。

修复前的实测行为：
- 不设 `BUNDLE_PATH`：参考把 gem 装进 `$GEM_HOME/gems/json_pure-2.8.1` 并打印 ``Use `bundle info [gemname]` …``；celerite 装进 `<home>/.bundle/ruby/4.0.0/gems/…` 并打印 ``Bundled gems are installed into `<home>/.bundle` ``。
- `BUNDLE_PATH` 指向自定义目录、gem 摊在 `<path>/gems`（没有 `ruby/<abi>` 层）时：参考 `show json_pure` 与裸 `show` 都返回 exit 7（`Could not find gem 'json_pure (= 2.8.1)' in locally installed gems.`）；celerite 却因为 `installed_gem_dir` 无条件回退到系统 gem 目录而返回 0。

实现：
- `InstallPaths.use_system_gems?(config, system_gem_dir)`（`src/celerite/resolution.cr`）：显式 `path` → false；部署默认 `vendor/bundle` → false；`path.system` 或 `disable_shared_gems == false` → true；其余情况「能解析出 `Gem.dir`（`default_gem_dir`）就返回 true」。`system_gems?` 保留为同义入口，`base_path`/`gem_root`/`ruby_root` 都带上 `system_gem_dir` 判定。拿不到 `Gem.dir` 的调用点（进程锁、下载缓存根）继续回退 `<home>/.bundle`。
- `src/celerite/cli/commands_install.cr`：`Bundle complete!` 之后用 `InstallPaths.use_system_gems?(config, bridge.ruby_environment.default_gem_dir)` 选择收尾消息。
- `src/celerite/cli/commands_surface.cr`：`installed_gem_dir` 的系统目录回退改成有条件——新增 `system_gem_fallback_allowed?(definition)`（`use_system_gems?(config, install_path(config))`），只有 bundle path 本身就是 `Gem.dir` 时才回退，`git`/`path` 源不回退。
- 测试隔离：`spec/spec_helper.cr` 在 `GEM_HOME` 未设置时把它指到临时目录（默认目标变成 RubyGems 目录后，否则整包会写真实 `C:/Ruby40-x64/lib/ruby/gems/4.0.0`）；`spec/m7_clean_spec.cr` 的 `clean_gems_dir` 随之改读 `GEM_HOME/gems`；`spec/m7_path_system_spec.cr` 拆成「无配置 → 系统目录」与「拿不到 `Gem.dir` → 回退 `.bundle`」两条；`spec/m7_show_no_lockfile_spec.cr` 的 GEM_PATH 用例去掉 `BUNDLE_PATH`（对齐上面 oracle）。

证据：
- A/B 探针（`.tmp-scratch/gemhome64`，两侧独立 `HOME`/`USERPROFILE`/`GEM_HOME`/`GEM_PATH`/`TEMP`，不设 `BUNDLE_PATH`）：`install` 的 exit、stdout、stderr 逐字相同，双方都装进 `<GEM_HOME>/gems/json_pure-2.8.1`，末行同为 ``Use `bundle info [gemname]` to see where a bundled gem is installed.``；随后 `check`、`list` 逐字相同（exit 0），`show json_pure` 仅沙箱路径不同（同为 `<GEM_HOME>/gems/json_pure-2.8.1`）。
- oracle（`.tmp-scratch/show64b`、`show64c`）：`BUNDLE_PATH=<gem_home>` + `GEM_PATH=<gem_home>` 且 gem 摊在 `<gem_home>/gems` 时参考 `show json_pure`、裸 `show` 均 exit 7；去掉 `BUNDLE_PATH` 后分别 exit 0 并打印 `<gem_home>/gems/json_pure-2.8.1` 与 `Gems included by the bundle:` + `  * bundler (4.0.24)` + `  * json_pure (2.8.1)`。
- 差分回归 10 个夹具（4.0.24）：`install-fresh`、`install-path-conflict`、`install-custom-path-summary`、`check-no-lockfile-missing`、`check-no-lockfile-installed`、`show-group-ignored`、`show-missing-installed`、`show-no-lockfile-missing`、`show-no-lockfile-installed`、`install-deployment-empty-checksums` → `10 passed, 0 failed, 0 skipped`。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、全量 `crystal spec` **557 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）、`git diff --check` 0。

已声明差异：
- 「无配置 → `Gem.dir`」无法做差分夹具：`script/differential` 对参考与 celerite 两侧都固定设置 `BUNDLE_PATH`（`script/differential:301-302`、`:402-403`），默认目标在夹具里永远不会被触发；该行为只用上面的 A/B 探针取证。

未验证：
- 只覆盖 4.0.24 与 2.7.2 两个 profile 的默认目标，其它版本未测。
- `GEM_HOME` 指向不存在的目录时 `Gem.dir` 的取值未测。
- 进程锁与下载缓存根仍落在 `<home>/.bundle`（调用点拿不到 `Gem.dir`），与参考在系统 gems 模式下 `bundle cache` 的位置是否一致未逐条核对。
---
## 2026-11-16（M7(4)：frozen 模式的 Gemfile 差异理由与加/删条目）

参考锚点：
- `bundler-4.0.24/lib/bundler/definition.rb:475-492`：`ensure_equivalent_gemfile_and_lockfile` 先要求锁文件存在，再取 `lockfile_changes_summary`，为空即放行。
- 同文件 `:906-921`：理由按固定顺序拼接——源变更、依赖变更、平台缺失、新平台、path/git gemspec、`@missing_lockfile_dep`、bundler 版本、CHECKSUMS 缺失/为空、锁定 spec 缺依赖/依赖不满足。
- 同文件 `:1043-1090`：`lockfile_changes_summary` 用 `new_deps`/`deleted_deps` 生成 `* <pretty_dependency>` 条目，消息前缀是「理由首字母大写 + }, but 」；**当拼接后的消息不以 `Your lockfile` 开头时才插入 `the lockfile `**。
- 同文件 `:1051-1087`：`converge_dependencies` 只在「依赖新增」或「需求不匹配」时置位 `@dependency_changes`；纯删除不置位，但删除列表照样打印。
- `bundler/shared_helpers.rb` 的 `pretty_dependency`：`name` + ` (requirement)`，默认需求（`>= 0`）只留名字。

修复前实测：
- Gemfile 新增 `thor` + 锁文件旧 → celerite 只报 CHECKSUMS 理由，缺 `The dependencies in your gemfile changed` 与 `You have added to the Gemfile:` 段落，也缺 `* ` 前缀。
- 纯删除场景，参考的 `Your lockfile has an empty CHECKSUMS entry …` 之后**不**出现 `the lockfile `（因为大写后的消息以 `Your lockfile` 开头）；celerite 在小写理由上判断前缀，多打印了 `the lockfile `。
- 需求变更（`json_pure 2.8.1` → `2.6.0`）参考同时列 `added` 与 `deleted`；celerite 只列 added。

实现（`src/celerite/definition.cr`）：
- `validate_frozen_lockfile!(explicit_flag, gemfile_dependencies)` 收集理由数组（依赖变更 + CHECKSUMS 缺失/为空），用 `", "` 连接后统一加工：首字母大写、按大写后的消息判断是否补 `the lockfile `、追加 `can't be updated because frozen mode is set`、`You have added to the Gemfile:` / `You have deleted from the Gemfile:` 段落、`Run \`bundle install\` elsewhere …` 段与开发机提示。
- `dependency_diff` 对齐 `lockfile_changes_summary`：added = Gemfile 有而 `DEPENDENCIES` 无（或需求不同）的条目；deleted = `DEPENDENCIES` 与 Gemfile **按名字+需求**都不匹配的条目；条目渲染为 `* name (req)`；只有 added 非空才置 `dependencies changed` 理由。
- 调用点：`install` 把已经求值出的 `evaluation.dependencies` 传进来（`commands_install.cr`）；`check` 在 frozen 且有锁时按需新建桥求值，桥不可用只导致理由变少、不改变结论。
- 需求归一化：`">= 0"` 视为默认需求（等价于 `Gem::Requirement.default`），Gemfile 与锁文件两侧同样处理。

证据：
- A/B 三场景（新增 `racc`、删除 `thor`、`json_pure 2.8.1`→`2.6.0`，两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/`BUNDLE_PATH`，`BUNDLE_FROZEN=true`）：exit 均为 16，stdout 与 stderr 逐字相同（含 80 列折行位置）。
- `spec/m7_deployment_path_spec.cr` 扩到 **9 examples, 0 failures**（新增：新增依赖的理由+条目、纯删除不出现依赖变更理由、需求变更同时列 added/deleted）。
- 负对照：把 `install` 的 `gemfile_dependencies` 换成 `nil` → 上述三条用例变 3 failures；恢复后 9/0。
- 差分夹具 `install-frozen-gemfile-added`（`extra/.bundle/config` 写 `BUNDLE_FROZEN: "true"`，Gemfile 多一个 `thor`）：4.0.24 与 2.7.2 均 `PASS (exit=16)`；同批 `install-deployment-empty-checksums`、`install-fresh` 仍 PASS。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、全量 `crystal spec` **560 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）、`git diff --check` 0。

已声明差异：
- 只实现「依赖新增/删除/需求变更」与 CHECKSUMS 两类理由；源变更（`the list of sources changed`）、平台缺失/新增平台、path/git gemspec 变更、`@missing_lockfile_dep`、bundler 版本更新、锁定 spec 缺依赖/依赖不满足均未建模。
- `You have changed in the Gemfile:`（源切换）段落未实现。
- `pretty_dependency` 未附加依赖的平台组（参考对多平台依赖会追加 `x64-mingw-ucrt` 等）。

未验证：
- 依赖声明带 `platforms:`/`require:`/`group:` 时的 added/deleted 渲染未与参考逐字对照。
- `check` 在桥不可用时降级为「只看 CHECKSUMS 理由」的路径未做端到端测试。
- 2.7.2 的同一场景只验证了差分夹具，未逐条比对 3 个 A/B 场景。
## 2026-11-17（M7(4)：`validate_platforms!` 与冻结模式下的平台错误）

参考锚点（`bundler-4.0.24`）：

- `bundler/definition.rb:494-497`：`validate_runtime!` = `validate_ruby!` + `validate_platforms!`。
- `bundler/definition.rb:524-530`：`validate_platforms!` 在锁文件 `platforms` 不含本机平台、也不含 `ruby` 时抛 `Bundler::ProductionError`（status 16）：

  ```
  Your bundle only supports platforms ["x86_64-linux"] but your local platform is
  x64-mingw-ucrt. Add the current platform to the lockfile with
  `bundle lock --add-platform x64-mingw-ucrt` and try again.
  ```

- `bundler/definition.rb:150`：`@current_platform_missing = add_current_platform unless Bundler.frozen_bundle?` —— 冻结模式不会静默补平台，所以缺平台时先报平台错误，而不是锁文件变更摘要。
- 调用 `validate_runtime!` 的命令：`binstubs.rb:12`、`check.rb:16`、`fund.rb:12`、`info.rb:13`、`install.rb:46`、`outdated.rb:32`、`platform.rb:35`、`pristine.rb:12`、`show.rb:15`、`update.rb:72`；`check.rb` 的顺序是先 `ensure_equivalent_gemfile_and_lockfile` 再 `validate_runtime!`。

修复前的我方行为（`.tmp-scratch/plat66`，锁文件 `PLATFORMS` 只有 `x86_64-linux`，`BUNDLE_FROZEN=true`）：

- `install`/`check`/`show`/`binstubs`/`fund`/`pristine`/`update`/`cache`：报的是冻结锁文件摘要（CHECKSUMS），参考报平台错误；
- `platform`：冻结模式下仍把本机平台列进输出（参考不列）；
- `list`：在平台缺失场景多打印一行 `Resolving dependencies...`（参考 stdout 为空）。

实现：

- `src/celerite/definition.cr` 新增 `validate_platforms!(local_platform : String)`：无锁文件直接返回；锁文件 platforms 为空、含本机平台或含 `ruby` 时返回；否则 `raise ProductionError`（消息与参考逐字一致，含 `--add-platform` 提示）。
- `src/celerite/cli/commands.cr` 新增 `validate_runtime!(definition, bridge)`：先 `validate_ruby_runtime!`，再用桥报告的 `ruby_environment.platform` 调 `validate_platforms!`；`RubyVersionMismatch`/`ProductionError` 继续上抛，桥不可用则跳过（与既有 ruby 校验同一降级策略）。`platform`/`show`/`info`/`binstubs`/`update`/`fund`/`pristine` 改调 `validate_runtime!`；`cache`/`doctor`/`licenses`/`console`/`list` 仍只校验 ruby。
- `src/celerite/cli/commands.cr` 的 `run_check` 把校验挪到 `validate_frozen_lockfile!` 之后（对齐 `check.rb:16` 的顺序）。
- `src/celerite/cli/commands_install.cr` 的内联校验追加 `definition.validate_platforms!(bridge.ruby_environment.platform)`（对齐 `install.rb:46`）。
- `platform` 命令只在非冻结时追加本机平台；`list` 删除平台缺失时的 `Resolving dependencies...` 行。

证据：

- A/B（10 条命令，冻结且锁文件缺本机平台）：修前 8 条报错文本不同，修后 `install`/`check`/`show`/`binstubs`/`fund`/`pristine`/`update`/`cache` 全部 exit 16 且 stderr 逐字相同；`platform`、`list` 两处小缺口修复后 5/5 场景 `SAME=True`。
- 非冻结回归（`lock`/`platform`/`platform --ruby`/`check`/`list`）：内容一致（`lock` 仅沙箱路径不同）。
- 负对照：把 `validate_platforms!` 的 `raise` 短路为 `return` 后 `spec/m7_platform_validation_spec.cr` 出现 1 failure（`Expected Celerite::ProductionError but nothing was raised`），恢复后 5/0。
- 差分夹具 `install-frozen-platform-missing`（`Gemfile` + `Gemfile.lock`（`PLATFORMS` 只有 `x86_64-linux`、CHECKSUMS 完整）+ `extra/.bundle/config` 写 `BUNDLE_FROZEN: "true"`）：4.0.24 与 2.7.2 均 `PASS (exit=16)`；4.0.24 同批 6 个夹具全 PASS。
- `crystal tool format --check src spec` 0；`crystal build --no-codegen` 0；全量 `crystal spec` 561 examples / 0 failures / 4 errors（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）；`git diff --check` 0。

已声明差异：

- 只把 `validate_platforms!` 接到已实现的命令上；`list`/`cache`/`doctor`/`licenses`/`console` 与参考一样不做平台校验（`list` 参考本身不调用 `validate_runtime!`）。
- `--add-platform` 提示串按 4.0.24 写死；2.x 的对应文本未单独建模。
- 平台错误优先于 CHECKSUMS 摘要只在「平台缺失 + 冻结」组合下验证过；其他理由组合（源变更、bundler 版本等）仍未建模。

未验证：

- 非 Windows 平台上的平台名归一（本机只测 `x64-mingw-ucrt` 与 `x86_64-linux` 两种字符串）。
- 锁文件 `PLATFORMS` 为空数组时的参考行为（我方按「空则通过」处理，未取 oracle）。
- `bundle lock --add-platform` 之后的重新校验路径（该命令的写入尚未实现）。
## 2026-11-17（M7(2)：`--gemfile` 的缺失校验与 `outdated --verbose` 的重复回显）

参考锚点（`bundler-4.0.24`）：

- `bundler/cli.rb`：`method_option "gemfile", type: :string` 只声明在 `init`（L216）、`check`（L229）、`install`（L271）、`update`（L324）、`cache`（L470）、`lock`（L644）上；`list`/`show`/`binstubs`/`add` 等不接受该开关（`Unknown switches "--gemfile"`，exit 15）。
- `bundler/errors.rb`：`GemfileNotFound < BundlerError`，`status_code(10)`；`friendly_errors.rb` 直接打印消息（不折行，因为长度未超过 80 列）。
- 参考输出（`check --gemfile <缺失路径>`）：

  ```
  C:/Users/.../missing/Gemfile
  not found
  ```

修复前的我方行为：

- `check`/`update`/`cache --gemfile <缺失路径>`：exit 1，stderr 是 Ruby 侧的 `No such file or directory @ rb_sysopen - <路径>`（桥把 `Errno::ENOENT` 透传出来）；
- `lock` 已在命令体内单独校验（exit 10 正确），因此只有 `lock` 行为正确。

实现：

- `src/celerite/cli/commands.cr` 的 `with_gemfile_overrides` 在设置 `BUNDLE_GEMFILE` 之前校验：`File.expand_path(gemfile)` 不是文件时 `raise GemfileNotFound.new("#{expanded.gsub('\\', "/")}\nnot found")`。`lock` 原先的重复校验随之删除（唯一来源）。
- `check` 改用同一个 `with_gemfile_overrides`（原先手写 ENV 覆盖/还原），因此缺失校验、覆盖与还原都在一处。
- `src/celerite/cli/commands_surface.cr` 的 `outdated`：删除处理器内重复打印的 `Running \`bundle outdated --verbose\` with bundler …`（该行由 `Commands.dispatch#print_command_echo` 统一输出，此前每个 `outdated --verbose` 会打印两次），保留参考的调试行。

证据：

- A/B（同一沙箱布局，两侧独立 `HOME`/`GEM_HOME`/`BUNDLE_PATH`）：`check`/`lock`/`cache`/`update --gemfile <缺失>` 全部 exit 10，stderr 逐字相同（参考 CRLF、我方 LF，按行比较相同）；`check --gemfile=<缺失>` 同样一致。
- 差分新夹具 `check-gemfile-missing`（`command`=`check --gemfile missing/Gemfile`）：4.0.24 与 2.7.2 均 `PASS (exit=10)`。
- `outdated-verbose` 夹具此前因重复回显失败，修复后 4.0.24 与 2.7.2 均 `PASS (exit=1)`（两侧都在发现可更新时退出 1）。
- `spec/m7_gemfile_switch_spec.cr` 3 例：`check` 缺失、`lock`/`update`/`cache` 缺失（三命令同消息）、`lock --gemfile Alt.gemfile` 真的按该文件解析并写 `Alt.gemfile.lock`；负对照把校验短路后 2 failures（`Expected: 10 got: 1`）。
- `crystal tool format --check src spec` 0；`git diff --check` 0；全量 `crystal spec` 568 examples / 0 failures / 4 errors（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL；`spec/m7_build_args_spec.cr:97` 在首轮全量偶发失败、单独跑 5/0，为本机原生扩展构建的环境抖动）。

已声明差异：

- `install`/`cache` 的 `--gemfile` 校验与参考同形，但这两个命令的后续安装路径仍按已声明差异处理（`cache` 的 `--all-platforms` 语义、`install` 的 removed flags）。
- `init --gemfile` 不校验存在性（参考用它指定**新建**文件名），未纳入本次改动。

未验证：

- 相对路径 `--gemfile` 在跨盘符时的展开形态（只测了同盘沙箱）。
- `BUNDLE_GEMFILE` 已设置时 `--gemfile` 的优先级（参考的 `find_gemfile` 顺序未单独取 oracle）。
- 2.x 的 `--gemfile` 错误文本（只比对了两 profile 的差分夹具，二者一致）。
## 2026-11-17（M7(2)：`bundle lock` 的平台编辑、命名更新与开关面）

参考锚点：

- `bundler/cli/lock.rb:28-70`：先 `options["remove-platform"].flatten.each { definition.remove_platform }`，再 `options["add-platform"].flatten.each { |platform| ... }`，`platform.to_s == "unknown"` 时 `raise InvalidOption, "The platform <raw> is unknown to RubyGems and can't be added to the lockfile."`（exit 1）；随后 `definition.platforms.empty?` → `raise InvalidOption, "Removing all platforms from the bundle is not allowed"`（exit 15）。
- `bundler/definition.rb:538-546`：`remove_platform` 对不在列表的平台 `raise InvalidOption, "Unable to remove the platform ... since the only platforms are ..."`。
- `bundler/cli/common.rb:95-103 ensure_all_gems_in_lockfile!`：有锁文件时，`--update NAME` 指向未锁定的 gem → `GemNotFound` + `gem_not_found_message`（exit 7）；无锁文件直接返回。
- `bundler/cli/lock.rb:107-116 check_for_conflicting_options`：`--normalize-platforms` 与 `--add-platform`/`--remove-platform` 各有一条独立消息。
- 开关面以 `Bundler::CLI.commands[name].options` 的反射结果为准：`lock` 无 `--ruby`/`--path`/`--without`/`--with`/`--source`/`--trust-policy`，`update` 无 `--prefer-local`/`--system`/`--binstubs`/`--path`/`--without` 等；2.7.2 与 4.0.24 除 `--cooldown` 外完全一致。

修复前（同一沙箱、两侧独立 HOME/GEM_HOME/BUNDLE_PATH）：

| 场景 | 参考 | 修复前我方 |
| --- | --- | --- |
| `lock --add-platform nonsense` | exit 1 + 平台未知消息 | exit 0，把 `nonsense` 写进 `PLATFORMS` |
| `lock --remove-platform java`（锁里只有本机平台） | exit 15 + `Unable to remove the platform ...` | exit 0 |
| `lock --remove-platform <唯一平台>` | exit 15 + `Removing all platforms from the bundle is not allowed` | exit 0 |
| `lock --update nosuchgem`（已有锁） | exit 7 + `Could not find gem 'nosuchgem'.` | exit 0 |
| `lock --update json_pure` | 打印两次 `Resolving dependencies...` | 只打印一次 |
| `lock --ruby` / `--path x` / `--source x` / `--trust-policy strict` / `--with dev` | `Unknown switches` exit 15 | 接受并静默忽略 |
| `update --prefer-local` / `--system` / `--binstubs` / `--path x` / `--without dev` | `Unknown switches` exit 15 | 接受并静默忽略（还会多打一条 `[DEPRECATED]`） |

实现（`src/celerite/cli/commands.cr` 的 `run_lock`）：

1. 冲突检查拆成两条精确消息（无 `Error:` 前缀）：`--normalize-platforms can't be used with --add-platform` / `... --remove-platform`，均 exit 15。
2. 平台编辑按参考顺序（先 remove 后 add）在 `Definition.build` 之后、解析之前执行：remove 命中不在当前列表的平台 → exit 15；add 的平台归一化为 `unknown` → exit 1；编辑后列表为空 → exit 15。
3. `--update NAME` 在 `lockfile_exists?` 时校验 `lockfile!.specs.map(&.name)`，未命中 → `gem_not_found_message_for` + exit 7；无锁文件不校验。
4. 命名更新把 `unlock` 从布尔改为 `Array(String)`，并在写盘前补打印第二次 `Resolving dependencies...`（`--print` 模式走 stderr），复刻参考「按名解锁 → 物化一次 + `#remotely!` 再一次」。
5. `LOCK_SWITCH_FLAGS/VALUES`、`UPDATE_SWITCH_FLAGS/VALUES` 按 Thor 反射结果重写：`lock` 去掉 `--ruby`/`--path`/`--without`/`--with`/`--source`/`--trust-policy`/`-P`，`--bundler` 移入值选项；`update` 去掉 `--prefer-local`/`--standalone`/`--no-cache`/`--no-lock`/`--redownload`/`--system`/`--binstubs`/`--clean`/`--path`/`--without`/`--with`/`--trust-policy`/`-P`/`--shebang` 并把 `--bundler` 移入值选项。

证据：

- A/B 14 例矩阵（`lock` 的 add/remove/update/normalize/print/add-checksums 组合）：exit、stdout、stderr、生成的 `Gemfile.lock` **14/14 逐字相同**；另 5 个边界例（`remove`+`add` 同时、`add-platform ruby`、`update --conservative`）亦全同。
- 开关面 12 例探针（`lock --ruby/--path/--source/--trust-policy/--with`、`update --prefer-local/--system/--binstubs/--path/--without`、两侧合法的 `lock --bundler`、`update --ruby`）：除 `lock --bundler` 输出里的沙箱绝对路径外全部一致。
- `spec/m7_lock_switches_spec.cr` 8 例 0 失败；`spec/cli_spec.cr` 的平台往返用例按参考改写（先加第二平台再删本机平台，最后拒绝删除最后一个平台）。
- 差分夹具 `lock-add-unknown-platform`、`lock-remove-absent-platform`、`lock-update-named`（预置锁）、`unknown-switch-lock-ruby`：4.0.24 4 passed，2.7.2 4 passed（+`install-fresh` 回归）。
- 负对照：把 `if normalized == "unknown"` 改成 `if false` 重建 `bin/celerite-nc.exe` → `lock-add-unknown-platform` FAIL（我方 exit 0 且写出锁文件），还原后 PASS。

已声明差异：

- `--cooldown` 只存在于 4.0.24 的 `lock`/`update` 选项表（2.7.2 没有），本实现保留它以对齐 4.x；2.7.2 下 `lock --cooldown 7`/`update --cooldown 7` 会与我方不同。
- `cache` 的开关表本轮未重排（仍接受 `--force`/`--redownload`/`--no-cache`/`--local`/`--path`/`--without`/`--with`）；`install` 保留 `--path`/`--without`/`--with` 作为已声明的语义实现。
- `--bundler` 只做接受，不做版本固定语义；`--add-platform` 只写平台，不触发平台专属变体解析。

未验证：

- `lock --update` 与 `--conservative` 组合在 2.7.2 下的完整输出（只用 4.0.24 取过 oracle）。
- `PLATFORMS` 段在多次增删后的排序规则（只比对过 `java` + 本机平台两例）。
- `--print` 与命名更新同时使用时第二次 `Resolving dependencies...` 是否确实走 stderr（只读过源码路径）。

## 2026-11-17（M7(2)：`bundle cache` 的开关面、`--path` 的移除文案与 `--no-install`）

参考锚点（bundler-4.0.24）：

- `lib/bundler/cli.rb:466-497`：`cache` 的 `method_option` 表只有 `all` / `all-platforms` / `cache-path`(string) / `cooldown`(numeric) / `frozen` / `gemfile`(string) / `no-install` / `no-prune` / `path`(string) / `quiet`；`--path` 在这里用专属 `removed_message` 抛 `InvalidOption`（"The `--path` flag has been removed because its semantics were unclear. Use `bundle config cache_path` …"），`--all` / `--no-all` 走 `print_remembered_flag_deprecation`。
- `lib/bundler/cli/cache.rb`：`run` = `set_command_option_if_given :cache_path` → `install` → `settings.temporary(cache_all_platforms:) { Bundler.load.cache }`；私有 `install` 复制选项、把 `local` 置 false（当 `cache_all_platforms`）、`no-cache` 置 true 后交给 `Bundler::CLI::Install` —— 即 `cache` **总是**跑完整的 install 流水线。
- `lib/bundler/cli/install.rb:121`：`set_command_option_if_given :no_install, options["no-install"]`；该设置只被 `source/rubygems.rb:211` 与 `source/git.rb:202` 的 `return if Bundler.settings[:no_install]` 消费，也就是只跳过"把包解到 `<bundle_path>/gems`"，解析、下载、写锁文件与安装摘要照旧。

修复前的实测差异（同一沙箱、两侧独立 HOME/GEM_HOME/GEM_PATH/BUNDLE_PATH，参考 4.0.24 与 `bin/celerite.exe`）：

| 命令 | 参考 | 修复前我方 |
| --- | --- | --- |
| `cache --force` | exit 15，`Unknown switches "--force"` + `Did you mean?  "--frozen"` | exit 0，照常安装并写出 `vendor/cache/*.gem` |
| `cache --local` / `--redownload` | exit 15，`Unknown switches "--local"` / `"--redownload"` | exit 0，静默接受 |
| `cache --without dev` | exit 15，`Unknown switches "--without"` | exit 15，但走 install 的"remembered"文案 |
| `cache --path vendor/x` | exit 15，专属"semantics were unclear"文案 | exit 15，走通用"remembered across bundler invocations"文案 |
| `cache --no-install` | exit 0，完整安装摘要 + `Updating files in vendor/cache`，包落在 `<bundle>/ruby/<abi>/cache` 而 `gems/` 为空 | exit 20（`Could not find <proj>/Gemfile.lock for resolution`），只打 cache 段 |

实现：

1. `src/celerite/cli/commands.cr`：`CACHE_SWITCH_FLAGS` 收窄为 `SWITCH_FLAGS_COMMON + ["--no-install", "--all-platforms", "--path"]`，`CACHE_SWITCH_VALUES` 改为 `["--retry", "-r", "--gemfile", "--cache-path", "--cooldown"]`（`--jobs` / `-j` 未被 `cache` 声明，参考同样是 `Unknown switches`）。被移除的 `--all` / `--no-all` / `--no-prune` / `--frozen` 仍留在 `CACHE_REMOVED_FLAGS`，因而 `--force` 的建议候选里仍有 `--frozen`。
2. `src/celerite/cli/commands_install.cr` 的 `run_cache`：`--path` 在构建 definition **之前**分出两条 profile 分支（4.x 打印专属文案并返回 15；2.7.x 只打 `[DEPRECATED]` 并把值写进 `.bundle/config` 的 `path`），随后**无条件**调用 `install(...)`，用 `no_install: rest.includes?("--no-install")` 传入。
3. `InstallPaths` 之外的最小改动：`Installer` 新增 `property no_install : Bool = false`；`install` 在下载/取到 `<bundle>/cache/<full>.gem` 之后，若 `no_install` 则只把包复制进 `<install_root>/cache`（`cache_package`）并返回，不再解包、不写 `specifications/`、不建 bin 桩、不跑扩展；`install_source_gem` 同样短路。`run_install` 在 `no_install` 时不再排队 `Installing <gem>` 进度行（参考的该行由安装动作产生）。
4. `install_args_from_cache` 现在也剥掉 `--path` 及其值/`--path=` 形式，避免把 install 专属的 `--path` 透传进 install 的 removed-flag 检查。

证据：

- A/B（4.0.24，13 条命令，stdout+stderr+exit 全比）：`path` / `force` / `local` / `redownload` / `without` / `no-install` / `plain` / `jobs` / `retry` / `all` / `frozen` / `cache-path` / `all-platforms` → **13/13 逐字相同**。
- A/B（2.7.2，5 条）：`path` / `force` / `without` / `no-install` 逐字相同；`plain` 只剩一处既有差异（见下方"已声明差异"）。
- `--no-install` 产物对齐（两侧各自 clean 沙箱）：`Gemfile.lock` 写出、`<bundle>/ruby/<abi>/cache/json_pure-2.8.1.gem` 存在、`gems/` 与 `specifications/` 为空、`vendor/cache/json_pure-2.8.1.gem` 就位 —— 五项全同。
- 新 spec `spec/m7_cache_switches_spec.cr` **3 examples, 0 failures**：`--force`/`--local`/`--without` 的 `Unknown switches`（含 `Did you mean?  "--frozen"`）、`--path` 的专属文案（按 `Commands.word_wrap(..., 80)` 断言）、`--no-install` 的锁与产物形态。
- 负对照：把 `no_install:` 实参改成 `false`（注释 `negative-control`）后该 spec `1 failure`（`bundle/ruby/<abi>/gems/json_pure-2.8.1` 被解包出来），还原后 3/0。
- 差分：新夹具 `cache-force-unknown-switch`（`cache --force`）、`cache-path-removed`（`cache --path vendor/x`）、`cache-no-install`（`cache --no-install`）→ 4.0.24 与 `cache-path` / `install-fresh` 回归一起 **5 passed, 0 failed**；2.7.2 **4 passed, 0 failed, 1 skipped**（`cache-path-removed` 记为 `deferred-2.7.2`，原因见下）。

已声明差异：

- 2.7.x 的 `--path` 只被 `[DEPRECATED]` 警告并记住为安装路径：参考会把包装到 `vendor/x/ruby/<abi>` 并在 `vendor/x/vendor/cache` 建缓存、额外生成 `build_info` / `doc` / `extensions` / `plugins` 目录，我方目前只做到"按 `vendor/x` 安装、缓存仍写项目根 `vendor/cache`"，故该夹具在 2.7.2 上 deferred。
- 2.7.x 在 `<bundle>/cache` 已有 `.gem`、但 `gems/` 被删掉的场景下会**省略** `Fetching <gem>` 行（只打 `Installing`），我方仍打印 `Fetching`。这是 install 流水线的既有差异（与本轮 cache 改动无关），在干净的差分夹具里不会出现。
- `cache --all-platforms` 的既有夹具仍受本机 msys Low-IL 影响（racc 原生扩展 `Gem::Ext::BuildError`），未在本轮重测。

未验证：

- 2.7.2 的 `--path` + `--cache-path` 组合下的缓存落点。
- `cache --quiet` 与 `--cooldown`（本轮未测其输出抑制与冷却行为，只确认开关被接受）。
- `cache --no-install` 与 PATH/GIT 源 gem 的组合（只测了 rubygems 源）。
## 2026-11-17（M7(2)：`bundle outdated` 的命名 gem 校验顺序）

- 参考行为（`bundler-4.0.24/lib/bundler/cli/outdated.rb:26-50`，`bundler-2.7.2/lib/bundler/cli/outdated.rb:25-38` 同）：`run` 顺序为 `check_for_deployment_mode!` → `validate_cooldown!` → `Bundler.definition.validate_runtime!` → `current_specs = Bundler.ui.silence { Bundler.definition.resolve }`（**静默解析**）→ 对每个命令行 gem 名 `raise GemNotFound, "Could not find gem '<name>'."`（`GemNotFound` status 7）→ 之后才构造 `Bundler.definition(gems:, sources:)` 并做会打印进度的解析。因此未知 gem 名的输出必须**只有** stderr 一行，stdout 为空。
- 修复前行为（`.tmp-scratch/od70`、`od70c` 对照）：

  | 命令 | 参考 | 修复前我方 |
  | --- | --- | --- |
  | `outdated nosuchgem` | exit 7、stdout 空、stderr `Could not find gem 'nosuchgem'.` | exit 7，但 stdout 先打印 `Fetching source index from <remote>`、`Resolving dependencies...`、`Resolving dependencies...` |
  | `outdated --parseable nosuchgem` | exit 7、stdout 空、stderr 一行 | stderr 多 `Fetching source index …` 与 `Resolving dependencies...` |
  | `outdated --groups development` | exit 7、stdout 空、stderr `Could not find gem 'development'.` | 同上（`development` 被当作位置参数 gem 名） |
  | `outdated json_pure` | exit 1、两条 `Resolving dependencies...` | 一致 |

- 根因：`src/celerite/cli/commands_surface.cr` 的 `outdated` 先把 `resolution.progress` 指向真正的输出流，`specs = resolution.resolve!` 打印完索引抓取与 `Resolving` 行之后，才在 `selected.each` 里对 gem 名做存在性校验。参考是在**打印型解析之前**用静默解析完成校验。
- 实现：把命名校验前移到 `resolution.resolve!` 之前，名字集合取自有锁文件的 `definition.lockfile!.specs`，无锁文件时走 `materialize_lockfile(definition, nil, local_only: true)`（同样静默），命中缺失即 `raise GemNotFoundError.new("Could not find gem '<name>'.")`；校验通过后才设置打印用 progress 并解析，原 `Resolving dependencies...` 的两次输出保持不变。
- 证据：
  - A/B（`.tmp-scratch/od70c`，两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/`BUNDLE_PATH`/`BUNDLE_USER_*`/`TEMP`，Gemfile 声明 `json_pure 2.6.0` 与 `group :development { thor 1.3.2 }`）：6 例 `named-json`、`named-thor`、`named-missing`、`named-missing-parseable`、`groups-flag`、`groups-dev-flag` 修复后 **6/6 逐字相同**（修复前 3 例不同）。无锁文件场景（`.tmp-scratch/od70d`）`outdated nosuchgem` 与裸 `outdated` 也两侧相同（exit 7 与 `Could not find gem 'json_pure (= 2.6.0)' in locally installed gems.`）。
  - 新 spec `spec/m7_outdated_naming_spec.cr` **4 examples, 0 failures**（未知名 stdout 空 + exit 7、`--parseable` 只一行、`--groups development` 同形、有效名仍 exit 1 且含两条 `Resolving dependencies...`）。
  - 负对照：把校验块移到 `resolution.resolve!` 之后重建，spec 得 **3 failures**（`Expected: "" got: "Fetching source index from …`），恢复后 4/0。
  - 差分夹具 `fixtures/differential/outdated-missing-gem/`（`command` = `install` 与 `outdated nosuchgem` 两行）：4.0.24 与 2.7.2 均 `PASS (exit=7)`；4.0.24 回归批（`outdated-missing-gem`、`outdated-no-lockfile`、`outdated-verbose`、`outdated-parseable`、`outdated-cooldown-table`、`install-fresh`、`show-group-ignored`）**7 passed**。
  - 门禁：`crystal tool format --check src spec` 0、`git diff --check` 0、全量 `crystal spec` 见下节。
- 已声明差异：名字集合取自锁文件而非再做一次完整静默解析；锁文件过期（Gemfile 有、锁里无）时参考可能给出 `Could not find gem '<name>'.` 而我方仍按锁文件名字集判断，反之亦然。
- 未验证：命名 gem 与 `--source` 组合时的输出顺序；`--groups` 作为「过滤全部组」与位置参数混用的其余组合；2.7.2 profile 的 `--parseable` 命名缺失场景（仅验了 4.0.24）。

## 2026-11-17（M7(2)：`bundle update` 的更新范围、锁文件前置条件与 stayed-same 报告）

参考实现：`bundler-4.0.24/lib/bundler/cli/update.rb:26-72`（2.7.2 `cli/update.rb:25-52` 同序）。

### 修复前实测

| 命令 | 参考 | 修复前 |
| --- | --- | --- |
| `update nosuchgem`（有锁） | exit 7，stderr `Could not find gem 'nosuchgem'.` | exit 0，打印 `Bundle updated!` |
| `update nosuchgem`（无锁） | exit 22，`This Bundle hasn't been installed yet. …`（80 列折两行） | exit 1，`This Gemfile does not contain a lockfile. …` |
| `update --all json_pure` | exit 15，`Cannot specify --all along with specific options.` | exit 0，照常更新 |
| `update --all --group development` | exit 15，同上 | exit 0 |
| `update --group development` | exit 0，stderr `Bundler attempted to update thor but its version stayed the same`；stdout 两条 `Resolving dependencies...` | exit 0，无该告警，且只有一条 `Resolving dependencies...` |
| `update json_pure --group development` | exit 0，两条 stayed-same 告警（json_pure 与 thor） | 只有 json_pure 一条 |
| `update --source nope json_pure` | exit 0，无告警 | 会打印 json_pure 的 stayed-same |

### 实现

1. `src/celerite/errors.cr`：新增 `GemfileLockNotFound < Error`（`status_code` 22、`wrap?` true，注释指向 `Bundler::GemfileLockNotFound`）。
2. `src/celerite/cli/commands_surface.cr` 的 `run_update` 首段按参考口径重算范围：`gems = subcommand_arguments(rest, UPDATE_SWITCH_FLAGS, UPDATE_SWITCH_VALUES)`（只取位置参数，不再把 `--group development` 的值当 gem 名）、`sources = flag_values(rest, "--source")`、`group_values = flag_values(rest, "--group") + flag_values(rest, "-g")`、`ruby_flag`、`update_bundler = flag_value(rest, "--bundler")`、`all_flag`，`full_update = gems.empty? && sources.empty? && group_values.empty? && !ruby_flag && !update_bundler`；`!full_update && all_flag` → `Cannot specify --all along with specific options.` + exit 15；弃用行只在 `full_update && !all_flag && 4.x` 时打印。
3. 锁文件前置条件：`!full_update` 时无锁文件 → `raise GemfileLockNotFound`（22），再按 `definition.lockfile!.specs.map(&.name)` 校验每个命名 gem，缺失 → `raise GemNotFoundError.new("Could not find gem '<name>'.")`（7）；全量更新仍允许无锁。
4. `--group` 展开：在 `Resolution` 创建之前用 `bridge.evaluate_gemfile(...)` 的 `dependencies`，把 `dep.groups` 与请求组有交集的依赖名并入 `gems`（`uniq`），替换原先的 `only_group` 分支；`unlock = full_update ? true : gems`。
5. `unknown-gem` 场景下第二条 `Resolving dependencies...` 的条件改为「存在被解锁的 gem 且无 `--source` 限制」（`!gems.empty? && !source_restricted`），与参考「按名解锁 → 预解析 + 真解析」一致，也覆盖 `--group` 展开后的选择。
6. stayed-same/regression 报告改为遍历 `gems`，与安装前锁定的版本比较：新版本更低 → `Note: <name> version regressed from <old> to <new>`，相等 → `Bundler attempted to update <name> but its version stayed the same`；`--source` 限制时跳过（参考的限制型 definition 里那些 gem 没有 resolved spec）。

### 证据

- A/B（`.tmp-scratch/probe-up71.ps1` 9 例 + `.tmp-scratch/probe-up71b.ps1` 6 例，两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/`BUNDLE_PATH`/`BUNDLE_USER_*`/`TEMP`，参考用 `ruby …bundler-4.0.24\exe\bundle`）：**15/15 逐字相同**（修复前 9 例中 2 例、6 例中 4 例不同）。
- 新 spec `spec/m7_update_scope_spec.cr` 5 例（无锁命名更新 22 且消息按 80 列折行、`--all` + 选择器两条 15、未知 gem 7 且 stdout 为空、`--group` 展开的 stayed-same + 两条 `Resolving dependencies...`、命名更新的 stayed-same）；与 `m7_outdated_naming_spec.cr`、`m7_cache_switches_spec.cr` 联跑 12/0。
- 差分新夹具：`update-missing-gem`（`install` + `update nosuchgem`）、`update-all-with-selector`、`update-no-lockfile`（22）、`update-group-unchanged`（stayed-same）→ 4.0.24 4/4 与回归批（`update-conservative`/`update-list`/`update-patch`/`update-ruby`/`update-source`/`update-strict`/`install-fresh`）合计 **11 passed, 0 failed**；2.7.2 6/6。
- 负对照：把 `--all` 冲突检查短路成 `if false && …` 重建 `bin/celerite-nc.exe` → `FAIL update-all-with-selector`（参考 `Cannot specify --all along with specific options.`，我方落到 22 的锁文件消息），还原后复绿、`negative-control` 计数 0。
- 全量差分（4.0.24，`.tmp-scratch/differential-full-71.log`）：**210 passed, 14 failed, 2 skipped**；14 条仍是既有环境族（7 条 git 源 msys `0xC0000022`、6 条 racc/原生扩展 `Gem::Ext::BuildError`、1 条 `cache-all-platforms` 同因）。

### 门禁

`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0（仅 2 条既有 `File.executable?` deprecation）、全量 `crystal spec` **588 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）、`git diff --check` 0。

### 已声明差异

- `--source` 命中真实源、且同时给出命名 gem 时，参考可能仍打印 stayed-same（本轮只按「限制型 definition 无 resolved spec」推断，未实测）。
- 「不同平台故不更新」的告警（`… not considered because it is for a different platform …`）未实现。
- `GemfileLockNotFound` 只接到 `update`，其余需要锁文件的命令仍用各自的错误形态。

### 未验证

- 2.7.2 下 `--all` 与选择器组合的文案（本轮 2.7.2 只跑了 6 个夹具，未覆盖该组合的负例）。
- `update --bundler <ver>` 与选择器组合的等价性。
- 版本回退（`Note: … version regressed …`）分支缺少端到端用例（需要可解析出更低版本的索引）。
## 2026-11-17（M7(2)：Thor 解析期的参数校验：数值选项、位置参数与 `show --outdated`）

参考实现在 Thor 解析阶段就拒绝若干参数形态；此前这些输入被接受后继续执行（或落到别的错误路径），属于「解析后静默忽略」。本轮把它们前移到 Thor 的时序上。

参考锚点：

- `bundler-4.0.24/lib/bundler/cli.rb:290-300`（`install` 的 `--jobs`/`--retry` 均为 `type: :numeric`）；
- `thor` 的 `Thor::Option#parse` → `Expected numeric value for '--jobs'; got "bogus"`（`Thor::MalformattedArgumentError`，`exit_status` 15）；
- 无参命令的 `Usage: "bundle <cmd> [OPTIONS]"`（`lock`/`env`/`licenses`/`issue`/`version` 为 `Usage: "bundle <cmd>"`，不带 `[OPTIONS]`）；
- `bundler/cli.rb:354-357`：`show --outdated` 为 removed 标志，`raise InvalidOption, "the \`--outdated\` flag to \`bundle show\` has been removed in favor of \`bundle show --verbose\`"`；`bundler-2.7.2` 仅 `[DEPRECATED] … will be removed …` 并继续执行 outdated 检查；
- `bundler/cli.rb` 的 `plugin` 子命令分发：未知子命令报 `Could not find command "<sub>".`（不带 `plugin ` 前缀）。

修复前（首辅亲测 `.tmp-scratch/p72`，两侧独立 `HOME`/`GEM_HOME`/`BUNDLE_PATH`/`BUNDLE_USER_*`）：

| 命令 | 参考 | 我方（修复前） |
| --- | --- | --- |
| `install --jobs bogus` | exit 15，`Expected numeric value for '--jobs'; got "bogus"` | exit 0，照常安装 |
| `install -j bogus` / `--retry bogus` | 同上（规范化成 `--jobs`/`--retry`） | exit 0 |
| `clean json_pure` | exit 15，`ERROR: "bundle clean" was called with arguments ["json_pure"]` + `Usage: "bundle clean [OPTIONS]"` | exit 15 但无参数错误（落到 gem 查找） |
| `check extra` / `install extra` / `cache extra` | 同上（`[OPTIONS]` 形式） | 执行成功或被当作 gem 名 |
| `lock a b` / `env extra` / `licenses extra` / `issue extra` | 同上，`Usage` **不带** `[OPTIONS]` | 静默忽略 |
| `show --outdated` | exit 15，removed 文案（80 列折行） | `Unknown switches "--outdated"` |
| `plugin extra` | `Could not find command "extra".` | `Could not find command "plugin extra".` |

实现：

1. `src/celerite/cli/commands.cr` 新增 `NO_ARG_USAGE`（命令 → usage 后缀；空串表示不带 `[OPTIONS]`）、`reject_positional_arguments(stderr, command, rest, allowed_flags, allowed_values) : Int32?`（用 `subcommand_arguments` 取出位置参数，空则放行，否则打印 Thor 的两行错误并返回 15）。
2. 同文件新增 `numeric_switch_error(rest, flags) : String?`：识别 `--flag value` 与 `--flag=value`，值必须匹配 `/\A[-+]?\d+\z/`，错误里的开关名规范化（`-j`→`--jobs`、`-r`→`--retry`）。
3. `dispatch` 在 `strip_global_flags` **之前**做类级 `--retry`/`-r` 数值校验（Thor 解析类选项早于命令分发，因此 `--retry bogus` 对任何命令都先失败）。
4. 逐个命令接线：`check`/`list`/`lock`/`install`/`cache`/`clean`/`platform`/`fund`/`env`/`licenses`/`issue` 加位置参数拒绝（`install`/`update` 另加 `--jobs`/`-j` 数值校验）；`clean` 的开关表是 `BARE_SWITCH_FLAGS + ["--dry-run"]`（参考 `clean` 只多声明 `--dry-run`）。
5. `show_info` 的 `show` 开关表加入 `--outdated`，并按 profile 分支：4.x 打印 removed 文案（`word_wrap(..., CLI.terminal_width)`）后返回 15；2.x 打印 `[DEPRECATED] … will be removed …` 后继续（`rest` 中剥离该标志）。
6. `plugin` 的未知子命令消息去掉父命令前缀。
7. `platform` 的签名加上 `stderr : IO`（原先只接收 `stdout`），`dispatch` 调用点同步；`spec/m7_platform_spec.cr` 的四处直接调用补齐 `IO::Memory`。
8. 位置参数判定要与 Thor 的 `:array` 语义一致：`POSITIONAL_ARRAY_FLAGS`（`list` 的 `--only-group`/`--without-group`、`install` 的 `--with`/`--without`/`--standalone`、`lock` 的 `--update`/`--add-platform`/`--remove-platform`）会吞掉后续所有不以 `-` 开头的 token，故 `list --only-group development test` 不算多余位置参数；`console` 允许一个 `[GROUP]`（`max_positionals: 1`，`Usage: "bundle console [GROUP]"`）。

证据：

- A/B 三套探针（`.tmp-scratch/probe-p72*.ps1`，4.0.24，ref/cel 各自独立沙箱，`\r\n` 归一后逐字比较）：套件一 14/14、套件二 15/16、套件三 9/9 全 SAME。套件二唯一的 DIFF 是 `show --verbose`（参考输出 `Fetching remote specs for outdated check...` 与逐 gem 的 `Summary:`/`Homepage:`/`Status:` 块），属已声明的未实现路径，本轮不做。
- 新 `spec/m7_thor_argument_spec.cr` 6 例（数值 2 例、无参命令位置参数 1 例含 `lock`/`issue` 的 usage 差异、取参命令不受影响 1 例、`show --outdated` 1 例、`plugin extra` 1 例）→ **6 examples, 0 failures**。
- 负对照 1：`reject_positional_arguments` 首行 `return nil` → 1 failure（`Expected: 15`）；负对照 2：`numeric_switch_error` 首行 `return nil` → 2 failures；两次均恢复后 6/0、`negative-control` 计数 0。
- 差分夹具 `fixtures/differential/unknown-numeric-jobs/`、`clean-positional-argument/`、`show-outdated-removed/`（后者带 `deferred-2.7.2`：2.7.x 继续走 outdated 检查，其 `Fetching remote specs for outdated check...` 块即未实现的 `show --verbose` 路径）→ 4.0.24 **9 passed, 0 failed**（含 `install-fresh`/`install-path-conflict`/`clean-no-lockfile`/`check-no-lockfile-missing`/`show-group-ignored`/`fund-no-lockfile` 回归）；2.7.2 **3 passed, 0 failed, 1 skipped**。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、`git diff --check` 0；全量 `crystal spec` **594 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL 环境错误）。

已声明差异：

- `show --verbose` / `show --outdated`（2.x）的 outdated 检查输出（远程 specs 摘要、逐 gem `Summary`/`Homepage`/`Status` 块）未实现，仍是 `show` 的三行简表。
- `plugin --bogus` 这类「未知开关当子命令」的 Thor 内部改写（参考报 `Could not find command "__bogus".`）未复刻；我方按原样 `--bogus` 处理。
- 位置参数拒绝只覆盖 M7 已实现的命令；未实现的命令仍走各自的「未实现」路径。

未验证：

- `--jobs`/`--retry` 的极值（负数、超大整数）在两侧的后续行为（本轮只比较到 Thor 解析错误这一层）。
- 通过 `THOR_COLUMNS` 改变终端宽度时 `--outdated` 文案的折行位置。
- `install extra` 在「Gemfile 里恰好有名为 extra 的 gem」时的参考行为（本轮只覆盖无该 gem 的情形）。

## 2026-11-17（M7(2)：`show --verbose` 的 outdated 检查与 Summary/Homepage/Status 块）

参考锚点：`bundler-4.0.24/lib/bundler/cli/show.rb:11-12`（`@verbose = options[:verbose]`、`@latest_specs = fetch_latest_specs if @verbose`）、`:34-47`（`fetch_latest_specs` 先 `Bundler.definition(true)` 再 `ui.info "Fetching remote specs for outdated check...\n\n"`、`ui.silence { definition.remotely! }`，故 header 与索引行在 bundle 加载之前打印）、`:60-74`（每个 spec 在 verbose 下用 `desc.lstrip` 加 `\tSummary:`、`\tHomepage:`、`\tStatus:` 三行，`outdated?` 为 `latest && current < latest`）。2.7.2 同构，但 `@verbose = options[:verbose] || options[:outdated]`：`--outdated` 只警告 `[DEPRECATED] the `--outdated` flag to `bundle show` will be removed in favor of `bundle show --verbose`` 后继续走同一分支。

修复前：
- `show --verbose` 只打印 `Gems included by the bundle:` + 每 gem 一行 `  * name (version)`，既没有 `Fetching remote specs for outdated check...` 头，也没有 `Summary`/`Homepage`/`Status`；
- `read_gemspec_info` 的 summary/homepage 正则用 `["']` 同时允许单双引号并停在第一个同类引号上，遇到 `The best way to manage your application's dependencies` 这样的撇号就截断，我方打印成 `The best way to manage your application`；
- 2.7.x 的 `show --outdated` 虽然已实现弃用警告，但之后仍落在简表分支上。

实现（`src/celerite/cli/commands.cr` 的 `show_info`）：
- `--verbose` 是类选项，`dispatch` 在命令运行前用 `strip_global_flags` 把它从 `rest` 里摘掉（只留 `ENV["CELERITE_VERBOSE"]`），因此 `show_info` 增加 `verbose : Bool = false` 形参，`dispatch` 传入已算好的 `verbose_requested`；`verbose_listing = command == "show" && (verbose || outdated_deprecated)`。
- `Definition.build` 之后、`validate_runtime!` 之前按参考顺序输出：`Fetching remote specs for outdated check...`、空行、`Resolution.new(definition, true)`（全解锁）解析并把 `name => version` 收进 `latest_versions`，解析用 `stdout` 作进度流，`ensure remote.close`。
- 列表分支拆成 verbose/非 verbose 两支：verbose 用 `desc.lstrip`（`* name (version)` 不缩进）、bundler 自身也走同一格式，摘要/主页取自 `read_gemspec_info`，取不到时回退参考的 `The best way to manage your application's dependencies` / `https://bundler.io`；新增 `print_show_verbose_entry` 打印 `\tSummary:  `、`\tHomepage: `、`\tStatus:   `（`Outdated - <current> < <latest>` 或 `Up to date`）。
- 修掉正则截断：summary/homepage 先匹配双引号形式、再匹配单引号形式（各用 `[^"]*` / `[^']*`），并加注释说明器 gemspec 摘要含撇号。

证据：
- A/B（2.7.2 profile，`.tmp-scratch/shv74*`，两侧独立 HOME/GEM_HOME/GEM_PATH/BUNDLE_PATH/TEMP，先 install 得到 2.6.0 的锁，再把 Gemfile 改成无约束触发 `Outdated - 2.6.0 < 2.8.1`）：`show --outdated` 的 stdout 与参考**逐字相同**（含 header、`Fetching source index from …`、`Resolving dependencies...`、两 gem 的 Summary/Homepage/Status）；`show --outdated --paths`、`show --outdated json_pure`、`show --outdated json_pure --paths` 三例仅差沙箱路径，header 与抓取行都在。
- `spec/m7_show_verbose_spec.cr`（新增 4 例）：verbose 头部与三行块、锁定版本下 `Up to date`、命名 gem 只打路径且无 `Summary:`、4.x `show --outdated` 仍为 15。
- 负对照：把 `verbose_listing` 硬置 `false` 重建 → `4 examples, 3 failures`（缺 header 与 Status 行），恢复后 4/0、`negative-control` 残留计数 0。
- 差分：新夹具 `show-outdated-verbose-272`（`Gemfile` 无约束 + `Gemfile.lock` 锁 2.6.0 + `bundle-preset` 预装 2.6.0 桩）在 2.7.2 下 `PASS (exit=0)`；同时把旧夹具 `show-outdated-removed` 的 `deferred-2.7.2` 标记删掉（此前因该分支未实现而 defer，现 2.7.2 也 `PASS (exit=7)`）。4.0.24 下新夹具按 `deferred-4.0.24` 跳过（4.x 的 `--outdated` 已是移除错误，由 `show-outdated-removed` 覆盖 exit=15）。
- 门禁：`crystal tool format --check src spec` 0、`git diff --check` 0、全量 `crystal spec` **598 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` msys Low-IL）。

已声明差异：
- 4.x `show --verbose` 的 debug 层（`Resolving dependencies because there is no lockfile`、`Using a local server…`、`Writing lockfile to …`）仍不复刻，故该命令在 4.x 下不能做整段输出差分。
- `No description available.` / `No website available.` 两个缺省串未做端到端取证（fixture  gemspec 都带 summary/homepage）。
- 版本比较用 `Gem::Version`，与参考一致，但未验证 prerelease 序（如 `1.0.0.pre` vs `1.0.0`）的显示差异。

## 2026-11-17（M7(4)：frozen 模式的源变更理由与 `You have changed in the Gemfile:`）

参考实现：`bundler/definition.rb` 的 `lockfile_changed_reason`（L906-921）把
`the list of sources changed` 排在所有理由之前，`lockfile_changes_summary`
（L587-624）为源变更的依赖列出 `* <name> from `<lockfile source>` to `<gemfile
source>``，段落顺序是 added → deleted → changed；两侧的 source 标签来自
`Source#to_gemfile`（`source/rubygems.rb:146` 是 `identifier` 的别名，
`source/git.rb:64`、`source/path.rb:58`），没有 source 时是字面
`no specified source`。默认源被整体替换也算源变更（`converge_sources`，
L152/L908）。

修复前（`.tmp-scratch/fr75*`，两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/
`BUNDLE_PATH`，`BUNDLE_FROZEN=true`）：

| 场景 | 参考 | 修复前 |
| --- | --- | --- |
| 依赖改挂 scoped 源 | exit 16，`The list of sources changed, …` + `You have changed in the Gemfile:` 段 | exit 16，只有 `Your lockfile has an empty CHECKSUMS entry …`，无源理由与 changed 段 |
| 默认源整体替换 | exit 16，`The list of sources changed, …`，无 changed 段 | 同上，理由缺失 |
| 锁缺当前平台 | exit 16，平台文案 | 已逐字相同 |

实现（`src/celerite/definition.cr`）：

1. `validate_frozen_lockfile!` 增加 `gemfile_sources` 参数，`source_diff` 返回
   `{changed, source_changed}`，源理由插在依赖理由之前；
2. `source_label` / `locked_source_label` 复刻 `to_gemfile` 的三种形态
   （rubygems 保留远端尾部斜杠、GIT 带 `branch/tag/ref/glob` 说明、PATH 用
   `remote`）；锁里挂在默认 `GEM` 段的依赖一律渲染 `no specified source`，
   与参考把这种依赖视为「Gemfile 侧未指定 source」一致；
3. `default_source_changed?` 比较 Gemfile 与锁文件的 rubygems 远端集合（桥对
   rubygems 源同时给出 `name` 与 `remotes`，按名字判断会永远落空）；
4. `install` 与 `check` 把 Gemfile 求值结果里的 `sources` 一并传入。

证据：

- A/B 三场景（scoped 源切换、默认源替换、平台缺失）剥掉 PowerShell 包装后
  **stderr 逐字相同**，80 列折行位置也一致；
- `spec/m7_deployment_path_spec.cr` 12 examples / 0 failures（新增 scoped 源
  切换、默认源替换、默认源相同时不报三项）；负对照把源理由改成永不触发后
  **2 examples 失败**（正是两个新用例），还原后复绿；
- 差分夹具 `install-frozen-source-changed`（Gemfile 用 `@SCOPED_INDEX_DIR@`、
  锁指向 `@INDEX_DIR@`）4.0.24 与 2.7.2 均 `PASS (exit=16)`，回归
  `install-frozen-gemfile-added`/`install-deployment-empty-checksums`/
  `install-fresh`/`check-no-lockfile-missing` 全 PASS；
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、
  全量 `crystal spec` **601 examples, 0 failures, 4 errors**（4 = 既有
  `spec/git_source_spec.cr` 的 msys Low-IL）、`git diff --check` 0。

已声明差异：只建模 `GEM`/`GIT`/`PATH` 三类源；多远端的 rubygems 源按
`remote, remote` 拼接（参考 `identifier` 同样用 `", "` 连接，未实测多远端）；
`Metadata` 之类的其它源类型不产生条目。

未验证：`--source` 限定解析下的源变更；2.7.x 上 changed 段的多依赖排序；源
变更与依赖变更同时发生时的段落顺序（参考按 added→deleted→changed）。

## 2026-11-17（M7(2)：`bundle info` 的 `--verbose` 回显）

`Bundler::CLI::PARSEABLE_COMMANDS`（`bundler/cli.rb:13`）不含 `info`，而 `info`
是独立 Thor 命令（`cli.rb:382`），所以 `bundle info … --verbose` 会先回显命令行，
`bundle show … --verbose` 不会。

修复前（`.tmp-scratch/p76`，两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/
`BUNDLE_PATH`，各自先 `install`）：

| 命令 | 参考首行 | 修复前我方首行 |
| --- | --- | --- |
| `info --verbose json_pure` | ``Running `bundle info json_pure --verbose` with bundler 4.0.24`` | 直接打印 `  * json_pure (2.6.0)` |
| `info json_pure --path --verbose` | ``Running `bundle info json_pure --path --verbose` …`` | 直接打印路径 |
| `show --verbose json_pure` | `Fetching remote specs for outdated check...`（不回显） | 同参考 |

实现：把 `info` 加进 `ECHO_COMMANDS`（`src/celerite/cli/commands.cr`），位置参数
排在开关之前、开关按名字排序，与 `print_command_echo` 既有规则一致；`show` 仍在
`PARSEABLE_COMMANDS` 中，保持不回显。

证据：A/B 三例首行逐字相同（`ECHO_SAME=True`）；`spec/m7_verbose_echo_spec.cr`
**9 examples / 0 failures**（新增 `info` 两种参数顺序，并断言 `show` 不回显）；
回归差分 `list-json`/`list-json-name`/`show-missing-installed`/`install-fresh`/
`version-plain`/`env-report` 全 PASS（6 passed / 0 failed / 1 documented SKIP）；
门禁 `crystal tool format --check src spec` 0、全量 **602 examples, 0 failures,
4 errors**（4 = 既有 `spec/git_source_spec.cr` msys Low-IL）、`git diff --check` 0。

同轮基线：4.0.24 全量差分 **218 passed, 14 failed, 3 skipped**，14 条失败全部是
既有环境族（4 条 `add-*` 与 `cache-all-platforms`、`native-ext`、
`native-ext-target` 是 racc 原生扩展在 msys 下 `Gem::Ext::BuildError`；5 条
`git-*` 与 2 条 `plugin-git-local*` 是 msys `0xC0000022`），无产品类失败。

已声明差异：`--verbose` 的调试层（含 `info --verbose` 里的
`Found no changes, using resolution from the lockfile`）仍不复刻，因此该命令只能
比对首行回显，不能做全量输出差分（装具无「仅比 stdout 首行」的标记，故不加夹具）。

未验证：2.7.x 上 `info --verbose` 的回显（未跑该 profile 的 A/B）；`info` 与
`--gemfile` 组合时的回显顺序。

## 2026-11-17（M7(2)：`lock` 的无操作静默、`check --path` 的移除文案与 `show --paths` 的 bundler 行）

### 参考锚点

- `bundler-4.0.24/lib/bundler/cli/lock.rb`：`--print` 分支打印 `definition.to_lock`，其余分支 `Bundler.ui.info "Writing lockfile to #{...}"` 后再 `definition.lock`；`--add-checksums` 与 `--normalize-platforms` 都会重新解析（因此有 `Fetching source index` + `Writing`，但没有 `Resolving dependencies...`）。
- `bundler/cli/check.rb:11-36`：`Bundler.definition` → `definition.check!` → 缺失列表；`--path` 走 `print_remembered_flag_deprecation`（`cli.rb:466-497` 的专属 removed 文案）。
- `bundler/cli/show.rb:44-52`：`--paths` 且未指定 gem 名时先打印运行中 bundler 的 gem 目录，再按 `full_name` 排序打印其余 gem。
- `Bundler::LockfileParser`/`LockfileGenerator`：`--print` 打印的是**重新序列化**的锁文件，`BUNDLED WITH` 与 `RUBY VERSION` 的缩进由 writer 决定（4.x 两空格、2.x 三空格），与输入文件的缩进无关。

### 修复前实测（同一沙箱，4.0.24 与 2.7.2 同形）

| 命令 | 参考 | 修复前 |
| --- | --- | --- |
| `lock`（锁与 Gemfile 一致） | 仅 `Writing lockfile to …` | 多 `Fetching source index from …` + `Resolving dependencies...` |
| `lock --print`（同上） | 仅锁正文，两流皆空 | 进度行混进 stdout |
| `lock --print`（无锁文件） | 锁正文在 stdout、`Fetching …` 在 **stderr**、无 `Resolving` | stdout 多 `Resolving dependencies...` |
| `lock --add-checksums` / `--normalize-platforms` | `Fetching` + `Writing`，无 `Resolving` | 多一行 `Resolving dependencies...` |
| `check --path vendor/x` | 4.x exit 15 + 移除文案（`bundle config set path 'vendor/x'`）；2.x `[DEPRECATED]` 并持久化 `BUNDLE_PATH` | `Unknown switches "--path"` |
| `check --no-prune` | `Unknown switches "--no-prune"` + `Did you mean?  "--no-color"` | 建议里带 `--no-deployment` |
| `show --paths`（无 gem 名） | 第一行是 `gems/bundler-4.0.24` | 缺 bundler 行 |

### 实现

1. `src/celerite/cli/commands.cr` 新增 `CHECK_SWITCH_FLAGS/VALUES`、`CHECK_REMOVED_FLAGS = ["--path"]` 与 `CHECK_SUGGEST_DICTIONARY`；`self.check` 依次做未知开关、位置参数、`removed_flag(rest, "check")` 三关：2.x 打 `[DEPRECATED]` 并 `config.set_local("path", …)` 后继续，4.x 打 80 列折行的移除文案并返回 15。
2. `removed_flag` 增加 `when "check"` 分支（`--path` 取值缺省为 `"path"`）。
3. `bundler_gem_dir` 先认 `CELERITE_REFERENCE_BUNDLER_LIB`，否则用桥的 `ruby_environment` + `find_bundler_lib` 定位运行中 bundler 的 gem 目录，供 `show --paths` 的首行使用。
4. `run_lock` 增加「无操作快路径」：未 `--update`/未命名更新/无 `--add-checksums`/无 `--normalize-platforms`/无平台编辑，且 `lockfile_matches_dependencies?` 为真时，直接打印既有锁（`--print`）或写回并打印 `Writing lockfile to …`，不实例化解析进度；其余场景按 `--print` 走 stderr、`--add-checksums`/`--normalize-platforms` 关掉 `Resolving dependencies...`。
5. `Definition#lockfile_matches_dependencies?` 除比较 `DEPENDENCIES` 外，还要求每个依赖在锁的 `specs` 里有满足需求的版本——`specs:` 为空的锁文件（`spec/m7_lockfile_regen_spec.cr`）必须重新解析。
6. `with_profile_indent` 在打印/写回解析得到的锁时把 `BUNDLED WITH`、`RUBY VERSION` 的值行缩进归一为当前 profile 的写法（4.x 两空格、2.x 三空格），复刻参考「重新序列化」的行为。

### 证据

- 11 条 A/B（`lock`、`lock --print`、`lock --add-checksums`、`lock --normalize-platforms`、`lock --update json_pure`、`lock --add-platform java`、`check`、`check --path vendor/x`、`check --no-prune`、`show --paths`、`show --paths json_pure`）在全新沙箱下 **11/11 逐字相同**（stdout+stderr+退出码，沙箱路径归一）。
- 差分：4.0.24 `lock-noop`/`lock-print`/`check-path-removed`/`lock-file-missing`/`install-fresh` = **5 passed**；2.7.2 = **4 passed + 1 skipped**（`check-path-removed` 已登记 prefix `deferred-2.7.2`）。
- 负对照：把 `lockfile_matches_dependencies?` 首行改成 `return false` 重建二进制 → `FAIL lock-noop`（多 `Fetching` + `Resolving`）与 `FAIL lock-print`（stderr 多 `Fetching …`），恢复后两夹具复绿。
- 回归核对：用 HEAD 二进制与工作树二进制分别跑 `lock --add-platform java`，两者都打印 `Writing` → `Fetching` → `Resolving`，确认平台编辑被排除在快路径之外不是回退。
- 门禁：`crystal tool format --check src spec` 0、`git diff --check` 0、全量 **608 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）。

### 已声明差异

- 2.7.2 的 `check --path <v>`：参考在报缺失前多打一行 `Resolving dependencies...`，我方 stdout 为空（退出码与 stderr 一致）。
- `--verbose` 的调试层（`Using a local server…`、`N:  <name> (<version>) from <path>` 等）不复刻。

### 未验证

- 只在两条本机 profile（4.0.24、2.7.2）上比对，未覆盖 4.0.16 等其它版本。
- 「锁与 Gemfile 一致」的判定只覆盖 `DEPENDENCIES` 与 spec 版本满足性；Bundler 的 `@dependency_changes` 内部状态（如 `Gemfile` 源顺序变化）未逐项比对。
- `lock --add-platform` 的完整输出仅做了一次人工比对（见证据），未纳入差分装具。

## 2026-11-17（M7(2)：`install --standalone` 的默认 path、组过滤与 CRLF）

参考锚点：`bundler-4.0.24/lib/bundler/cli/install.rb` L108-116（`normalize_settings`：
`if options["standalone"] && Bundler.settings[:path].nil? && !options["local"]` 时
`Bundler.settings.set_command_option :path, "bundle"`，`settings.rb` L187-194 保证
该值只作用于本次命令、不落盘）；`installer.rb`（安装结束后 `Standalone.new(...).generate`）；
`installer/standalone.rb` L10-20（`@specs = definition.specs_for(groups)`，groups 为空时
取全部且跳过 `bundler` 自身；`bundler_path = Bundler.root.join(settings[:path].to_s, "bundler")`；
`File.open(..., "w")` 在 Windows 是文本模式写，即 CRLF；`paths` 对每个 spec 的
`require_paths` 做相对化并替换 `#{RUBY_ENGINE}/#{Gem.ruby_api_version}` 与
`extensions/<platform>/#{Gem.extension_api_version}`）。

修复前实测（A/B，两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/`BUNDLE_PATH`/`TEMP`；
Gemfile = `source "file:///<repo>/fixtures/gem-index/"` + `gem "json_pure", "2.6.0"` +
`group :development { gem "thor", "1.3.2" }`）：

| 场景 | 参考 | 修复前我方 |
| --- | --- | --- |
| `install --standalone`（无 `BUNDLE_PATH`） | exit 0，末行 `Bundled gems are installed into `./bundle``，`./bundle/bundler/setup.rb` 1126 字节、CR=38、两条 unshift | exit 0，末行是 `Use `bundle info [gemname]` …`，**没有 setup.rb**，gem 装进 `Gem.dir` |
| `BUNDLE_PATH=<abs>` + `install --standalone=development` | setup.rb 1016 字节、CR=37、**只含 thor**；`Installing` 之后多一行 `Fetching source index from …` | setup.rb 1088 字节、**LF**、含 json_pure + thor |
| `install --standalone --local`（无 path） | exit 7，报本地缺失 | exit 7，同形（此时参考不设 path） |

实现（3 处）：

1. `src/celerite/config.cr`：新增 `set_temporary(name, value)`（写入 `@temporary`，与
   `Bundler.settings.set_command_option` 同义，只作用于本次命令）。
2. `src/celerite/cli/commands_install.cr` 的 `run_install`：`--standalone` 且 `path` 为空且
   未给 `--local` 时 `config.set_temporary("path", "bundle")`，因此本跑安装/写入都落在
   `./bundle`，且不会写进 `.bundle/config`。
3. 同文件的 standalone 渲染：`standalone_groups(rest)` 解析 `--standalone[=]groups`
   （逗号与后续裸 token 两种写法）；`standalone_specs(specs, deps, groups)` 在 groups 为空时取
   全部并剔除 `bundler`，否则以 `dep.groups & groups` 非空的依赖为根、按
   `ResolvedSpec#dependencies` 做闭包；`render_standalone_setup` 在 Windows 把正文
   `gsub("\n", "\r\n")`（对齐文本模式写）；groups 非空时按 `installer/standalone.rb` L10-12
   追加一行 `Fetching source index from …`（`file:` 源）或 `Fetching gem metadata from …`。

证据：

- A/B 三场景：A 两侧输出与 `setup.rb` **逐字节相同**（1126 字节、CR=38、两条 unshift 顺序一致）；
  B 的 `setup.rb` 与参考**完全相同**（1016 字节、CR=37、只含 `gems/thor-1.3.2/lib`），stdout
  仅剩参考并行下载造成的 `Fetching json_pure`/`Fetching thor` 行序差异；C 两侧 exit 7 且 stderr 相同。
- 新增 `spec/m7_standalone_spec.cr` 3 例（`./bundle` 默认目标 + CRLF、`--standalone=development`
  只含 thor 且抓取行恰好两次、`--standalone --local` 不设 path 且不建 `./bundle`），
  **3 examples, 0 failures**；Crystal 陷阱：`String#count("…")` 按字符集合计数，
  `count("\r\n")` 会把 CR/LF 都算上（76 vs 38），须用 `scan(/\n/).size` 与 `scan(/\r\n/).size`。
- 负对照两次：①`standalone_specs` 忽略 groups → 第 2 例失败（`body.should_not contain("json_pure")`
  得 1088 字节含 json_pure 的正文）；②跳过 `set_temporary("path", "bundle")` → 第 1 例失败
  （末行不是 `Bundled gems are installed into `./bundle``）。两次均复原，源码中 `negative-control`
  计数为 0。

已声明差异与未验证：

- `install --standalone` 的输出含并行下载行序（`Fetching json_pure` / `Fetching thor`），装具的
  全量 stdout 比对会因此不稳，故本轮**不做**该命令的差分夹具，只以 A/B 探针取证；
- 2.7.2 profile 的 standalone 未测（其 `installer/standalone.rb` 形态未逐一核对）；
- `setup.rb` 里 `extensions/<platform>/…` 的替换依赖真实扩展包，本机只有纯 Ruby gem，未覆盖；
- `--standalone` 与 `--deployment`/`--frozen` 同时给出时的组合语义未测。

## 2026-11-17（M7(5)：403 的两处抛出点与紧凑索引的 legacy 回退）

参考锚点：`bundler-4.0.24/lib/bundler/fetcher/downloader.rb` L69-73（`HTTPUnauthorized`
按是否带 userinfo 分派 `AuthenticationRequiredError`/`BadAuthenticationError`，均传
`uri.host`；`HTTPForbidden` → `AuthenticationForbiddenError, uri.host`）、
`fetcher/index.rb` L14-19（legacy `specs` 的 403 → `AuthenticationForbiddenError, remote_uri`，
即**完整源 URI**，含尾斜杠）、`fetcher.rb` L45-72（三个错误类的文案；
`AuthenticationForbiddenError` 是 `Access token could not be authenticated for <subj>.` +
`Make sure it's valid and has the necessary scopes configured.`）、
`fetcher/compact_index.rb` L9-23（`compact_index_request` 只让 401 原样抛出，
其余 `HTTPError` 记 trace 后返回 nil ⇒ **紧凑索引的 403 会退到 legacy 索引**，
legacy 再用完整 URI 报错）。

修复前实测（本地 `TCPServer` 对所有请求回固定状态；两侧独立 `HOME`/`GEM_HOME`/`GEM_PATH`/`TEMP`，
Gemfile = `source "http://127.0.0.1:<port>/"` + `gem "json_pure", "2.6.0"`）：

| 响应 | 参考 | 修复前我方 |
| --- | --- | --- |
| 全部 403（索引被拒） | exit 17，stdout `Fetching source index from http://127.0.0.1:<port>/` + 空行，stderr `Access token could not be authenticated for http://127.0.0.1:<port>/.` + `Make sure it's valid and has the necessary scopes configured.` | exit 17，stdout 空，stderr `Authentication is required for 127.0.0.1.` + 3 行引导 |
| 401（带/不带 `WWW-Authenticate: Basic`） | exit 17，`Authentication is required for 127.0.0.1.` 4 行 | 逐字相同（本来就对） |

实现（4 处）：

1. `src/celerite/compact_index/cache.cr` 的 `HttpFetcher#perform`：403 改为
   `AuthenticationForbiddenError.new(<@uri.to_s，缺尾斜杠则补>)`，401 分支保持不变；
   注释记下两条抛出点的差异与 legacy 回退。
2. `src/celerite/downloader.cr`：403 改为 `AuthenticationForbiddenError.new(uri.host || uri.to_s)`，
   指向 `fetcher/downloader.rb` L72-73。
3. `src/celerite/errors.cr`：`AuthenticationForbiddenError` 的类注释改为「参考有两个抛出点、
   subject 不同」，并订正原先「403 报成 AuthenticationRequired」的错误断言。
4. `src/celerite/resolution.cr` 的 `index_specs_from_remote`：`rescue AuthenticationForbiddenError`
   时先按 legacy 回退那样打印 `Fetching source index from <remote>` 与一个空行，再抛出
   （对齐参考「紧凑索引 403 → legacy 索引自己打抓取行后报错」的顺序）。

证据：

- A/B（全部 403）：`ERR_SAME=True OUT_SAME=True`，两侧 exit 17，stdout/stderr 逐字相同。
- 新增 `spec/m7_forbidden_spec.cr` 2 例（403 → 完整 URI 文案 + 两行 stdout；401 → 仍为
  `Authentication is required`），**2 examples, 0 failures**。
- 负对照：把 403 分支改回 `AuthenticationRequiredError` → 第 1 例失败
  （`Expected: "Access token could not be authenticated for http://127.0.0.1:58690/.\n"` /
  `got: "Authentication is required for 127.0.0.1.\n"`），还原后 2/0，源码中
  `negative-control` 计数为 0。

已声明差异与未验证：

- **gem 下载 403**（索引可读、只有 `/gems/<file>.gem` 返回 403）参考走 RubyGems 自己的下载器：
  三次 `Retrying download gem from <source> due to error (n/4): Gem::RemoteFetcher::FetchError
  bad response Forbidden 403 (<url>)`，然后 `Bundler::HTTPError: Could not download gem from
  <source> due to underlying error <bad response Forbidden 403 (<url>)>` 加 Ruby 回溯、exit 5。
  我方在该路径上（`Downloader`）报 `Access token could not be authenticated for 127.0.0.1.`、
  exit 17，**未复刻** RubyGems 的重试与回溯，属已声明差异。
- legacy 索引（`specs.4.8.gz`）本身未实现，故 403 时只复刻「抓取行 + 完整 URI 文案」，
  真正的 legacy 解析未验证。
- 403 与凭据（userinfo / `BUNDLE_<host>` 环境变量）组合时的分支未测。

- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、全量 `crystal spec` **613 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的 msys Low-IL）、`git diff --check` 0。

## 2026-11-17（M7(5)：gem 下载 403 的重试与失败文案）

参考实现：gem 下载走 RubyGems 自己的下载器（`bundler/rubygems_integration.rb:379` 的
`download_gem` 用 `Bundler::Retry.new("download gem from #{redacted_uri}")`），因此下载期的
403 与索引期的 403 走完全不同的路径：`Bundler::Retry#fail_attempt`（`bundler/retry.rb:60-64`）
在每次失败时先往 stdout 写一个空行、再往 stderr 写
`Retrying download gem from <source> due to error (n/4): Gem::RemoteFetcher::FetchError bad response Forbidden 403 (<url>)`，
最后一次抛 `Bundler::HTTPError: Could not download gem from <source> due to underlying error <bad response Forbidden 403 (<url>)>`；
`installer/gem_installer.rb:38-49` 把它包成安装失败，`parallel_installer.rb:198` 追加依赖树，
最终 status 5。

修复前（探针：静态服务 gem 索引、`/gems/` 前缀一律 403）：

| 场景 | 参考 4.0.24 | 修复前 |
| --- | --- | --- |
| `install`（下载 403） | exit **5**；stdout `Fetching gem metadata from …` / `Resolving dependencies...` / `Fetching json_pure 2.6.0` + 4 个空行；stderr 三行 `Retrying download gem …` + `Bundler::HTTPError: …` + Ruby 回溯 + `An error occurred while installing json_pure (2.6.0), and Bundler cannot continue.` + `In Gemfile:` + `  json_pure` | exit **17**，只报 `Access token could not be authenticated for 127.0.0.1.`（把下载 403 当成索引 403），且没有 `Fetching json_pure` 行 |

实现：

1. `src/celerite/downloader.cr` 新增内嵌 `ForbiddenDownloadError`（status 5、`wrap?` true、
   `error_class_name` 为 `Bundler::HTTPError`、消息为
   `Could not download gem from <source> due to underlying error <bad response Forbidden 403 (<url>)>`）；
   403 分支按 `attempt < max_attempts` 打印重试行并存 `sleep`，最后一次抛该错误。
2. `src/celerite/installer.cr` 的 `download_failure_message` 把错误拼成
   `Bundler::HTTPError: <message>` + `An error occurred while installing <gem> (<version>), and Bundler cannot continue.`
   + `In Gemfile:` 依赖树，并包成 `InstallError`（status 5）。
3. `src/celerite/cli/commands_install.cr` 把重试空行接回 stdout：参考的
   `Fetching <gem>` 行先打印、重试空行后打印，而我们的 fetch/install 行是**缓冲后统一 flush**，
   所以新增 `early_fetch` / `flush_early_fetch`，在第一次重试通知时把该 gem 的 `Fetching` 行
   提前打印并从缓冲里移除，两侧顺序因此一致。

证据：

- A/B（本地 403 服务，两侧独立 HOME/GEM_HOME/BUNDLE_PATH）：`install` 的 **stdout 逐字相同**，
  exit 均 5；stderr 去掉参考的 Ruby 回溯（`path:in 'Class#method'` 行）后**逐字相同**。
- `spec/m7_forbidden_download_spec.cr` 1 例：本地 `HTTP::Server` 服务真实 gem 索引、只对
  `/gems/` 与 `/quick/` 回 403，断言 exit 5、三行重试、折行后的 `Bundler::HTTPError` 块、
  `In Gemfile:` 段，以及 `Fetching json_pure 2.6.0` 之后恰好 5 个空行；与既有
  `spec/m7_forbidden_spec.cr` 联跑 **3 examples, 0 failures**。
- 负对照：把 `flush_early_fetch` 改成只打空行（不再释放挂起的 `Fetching` 行）→ 该用例
  **1 failure**（`out` 以空行开头、`end_with` 断言失败），还原后复绿、`negative-control` 计数 0。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、全量
  `crystal spec` **614 examples, 0 failures, 4 errors**（4 = 既有 `spec/git_source_spec.cr` 的
  msys Low-IL）、`git diff --check` 0。

已声明差异：

- 参考在 `Bundler::HTTPError` 之后打印约 20 行 Ruby 回溯（`rubygems_integration.rb:406` →
  `source/rubygems.rb` → `gem_installer.rb` → `parallel_installer.rb` → `worker.rb`），我方
  **不复刻**（Crystal 程序没有 Ruby 帧，伪造即失真）。因此该场景只做「前缀 + 尾部」比对，
  无法做全量输出差分。
- 重试间隔按参考的指数退避起点 0.5s 实现，但 `Bundler::Retry` 的 jitter（±0.5）未建模，
  故三次重试的总耗时与参考不完全一致。
- `/quick/` 403 与 `/gems/` 403 目前走同一分支，二者在参考里是否同一路径未分别验证。
## 2026-11-17（M7(2)/M7(4)：`--quiet` 的抑制面、`lock --print` 的解析行、`add` 的重复声明语义）

本轮四组语义按参考重新对齐，参考锚点均在 `bundler-4.0.24`（2.7.x 差异单独标注）。

### 1. `--quiet` 是 method option，不是类选项

- 参考 `cli/install.rb:11`、`cli/update.rb:12`、`cli/add.rb:15`、`cli/cache.rb:12`、
  `cli/doctor/diagnose.rb:78` 都是 `Bundler.ui.level = "warn" if options[:quiet]`；
  `Bundler::CLI.class_options` 只有 `--no-color`/`--retry`/`--verbose`，所以 `--quiet`
  在 `check`/`lock`/`list`/`show`/`outdated`/`binstubs`/`init`/`pristine`/`clean` 等命令上
  由 Thor 报 `Unknown switches "--quiet"`（exit 15）。
- 实现：`--quiet` 从 `SWITCH_FLAGS_CLASS`/`SWITCH_FLAGS_COMMON` 移除，加进
  `INSTALL_SWITCH_FLAGS`/`UPDATE_SWITCH_FLAGS`/`CACHE_SWITCH_FLAGS`/`ADD_SWITCH_FLAGS`/
  `DOCTOR_SUBCOMMAND_FLAGS`；`dispatch` 在 `strip_global_flags` 之前取 `quiet_requested`，
  命中 `QUIET_COMMANDS = ["install", "update", "add", "cache", "package", "pack"]`（或
  `doctor`）时把 `stdout` 换成 `IO::Memory`，等价于把 UI 阈值降到 `warn`：`info`/`confirm`
  全部丢弃，`warn`/`error`（stderr）与 80 列折行不变。
- 回显先于降级：`print_command` 在 Thor 的 dispatch 回调里执行（`cli.rb:34-39`），
  `ui.level = "warn"` 在命令体里，故 `install --quiet --verbose` 仍打印
  ``Running `bundle install --quiet --verbose` with bundler 4.0.24``。

### 2. `lock --print` 无锁文件时必须打印 `Resolving dependencies...`

- 参考 `cli/lock.rb:24` 把 `Bundler.ui.output_stream` 切到 `:stderr`（`--print` 的锁正文走
  stdout），`:70-76` 的 `add_checksums`/`normalize_platforms` 会强制物化进而解析；
  `resolver.rb:34` 是 `Resolving dependencies...` 的唯一发射点。
- 原实现只要 `--print`/`--add-checksums`/`--normalize-platforms` 就 `show_resolving = false`，
  于是无锁文件时缺这一行。改为仅当「参考的 `no_resolve_needed?` 也会短路」时才抑制：
  进入命令时已有锁文件、且 `lockfile_matches_dependencies?` 为真（锁仍满足 Gemfile）、
  且没有 unlock（`--update`/`--update NAME`）、没有 `--add-platform`/`--remove-platform`。
  后三个条件在首版遗漏，导致全量差分里 `lock-normalize`（锁的 `DEPENDENCIES` 为 stale）与
  `lock-file-update`（`--update --print` 且锁版本落后）少打这一行 —— 这两处即真实回归，
  收紧条件后双 profile 全量 lock 家族 17 例全 PASS。
- 实测矩阵（8 例，4.0.24 与 2.7.2 双侧）：无锁 `--print` → stderr `Fetching` +
  `Resolving`；无锁 `--add-checksums`/`--normalize-platforms` → stdout
  `Fetching` + `Resolving` + `Writing`；裸 `lock` 无锁 → `Writing` 先于 `Fetching`；
  有锁 `--print` → stderr 空；有锁 forcing 开关 → `Fetching` + `Writing`（无 `Resolving`）。

### 3. `add` 对已在 Gemfile 的同名 gem

参考 `Injector#inject`（`injector.rb:25-58`）把注入依赖与 `builder.dependencies` 相减
（`:35`），只有仍有剩余时才写 Gemfile（`:47`），但 `to_definition` → `remotely!` →
`@definition.lock`（`:40-53`）**无条件**执行。

| Gemfile | 锁 | 命令 | 参考 | 实现前 |
|---|---|---|---|---|
| `gem "json_pure"` | 有 | `add json_pure --skip-install` | exit 0、全静默、锁不变 | exit 0、无锁可写 |
| `gem "json_pure"` | 无 | 同上 | exit 0、`Fetching`+`Resolving`、写出锁 | 全静默、不写锁 |
| `gem "json_pure"` | 有 | `add racc --skip-install` | exit 0、`Fetching`+`Resolving`、锁新增 racc | 相同 |
| `gem "json_pure", "~> 2.6"` | 任意 | `add json_pure --version 2.6.0 --skip-install` | exit 4、stdout 空、Gemfile 不变 | exit 4 但先写 Gemfile、stdout 有抓取行 |

- 实现：删掉自造的 `Cannot declare <name> twice in the Gemfile`（参考两版全树无此串），
  改为求值 Gemfile 后比对 `Gem::Requirement` 语义；需求相同则不写 Gemfile，需求不同则抛
  `DSLError`（新增 `GemfileError`(4)/`DSLError`），描述里带 `injected gems` 文件名与
  `update_prompt`（`. Gem already added` / `. If you want to update the gem version, run
  bundle update <name>.` 加 `You may also need to change the version requirement…`，末句自带
  句号，故与参考一样出现两个句号）。
- 追加行改用 `File.open(path, "a")`（`Injector#append_to` 的 `f.puts; f.puts lines`），
  原文件行尾字节不动、新增行按平台 CRLF。
- `--skip-install` 路径新增 `persist_add_lockfile`：用同一桥复解析一次，无锁文件时打
  `Fetching source index from <remote>/` + `Resolving dependencies...` 并写锁，有锁且内容
  相同则静默（对齐 `definition.rb:401-419` 的 `lockfiles_equal?` 只 touch）。

### 4. 2.7.2 的 `binstubs --path` 与 `DSLError` 帧

- `cli/binstubs.rb:15`（2.7.x）：`set_command_option :bin, path_option if options["path"]`；
  `bin` 属 `REMEMBERED_KEYS`（`settings.rb:46-52`），故把值写进 `.bundle/config`
  （`BUNDLE_BIN`）。4.0.24 改为 removed flag（exit 15，文案带 `config set bin '<value>'`）。
  实现按 profile 分支：2.x 打 `[DEPRECATED]` 后 `definition.config.set_local("bin", value)`
  并继续，4.x 打 removed 文案并返回 15；`--path` 的 `lazy_default: "bin"` 用
  `Commands.flag_value` 复刻（下一个 token 是开关时仍取 `"bin"`）。
- `bin/` 目录的创建时机改到「已找到 spec 且有 executables」之后（`bundler.rb:120-126` 的
  首次 `bin_path` 调用 / 4.0.24 `installer.rb:130`），因此 `binstubs json_pure` 在 gem 缺失时
  不再残留 `bin/`。
- `dsl.rb:611`（2.7.x）用 `trace_line.split(":")[1].to_i - 1` 取帧行号；Windows 路径
  `C:/…/injected gems:1` 会被切成 `C:`、`/…/injected gems`、`1`，于是行号算成 `-1`，
  `lines[-1]` 与 `lines[0]` 同一行被渲染两次（且 `first_line` 为假，上一行渲染成裸缩进）。
  4.0.24 改用正则 `[:(\d+)(?::in\b|\z)]` 故无此现象。实现按 profile 复刻两版形态，
  并用 `ruby_line_at` 处理 Ruby 负索引（Crystal `lines[-2]` 越界抛错）。

### 证据

- `spec/m7_quiet_and_add_spec.cr` **20 examples, 0 failures**（`--quiet` 4 例、lock 进度 3 例、
  binstubs 开关面 3 例、2.7.2 profile 3 例、cooldown 门控 1 例、add 6 例）。
- 差分新夹具 6 条，双 profile 全 PASS：`quiet-install`(0)、`quiet-unknown`(15)、
  `lock-print-nolock`(0)、`binstubs-path-removed`（4.0.24=15、2.7.2=7）、`add-existing-same`(0)、
  `add-existing-conflict`(4)。
- 2.7.2 回归子集 21 例：`binstubs`/`binstubs-flags`/`binstubs-shebang`/`binstubs-shebang-line`/
  `add-path`/`add-require`/`add-skip-install`/`add-source`/`add-strict`/`add-strict-optimistic`/
  `add-version-plain`/`lock-print`/`lock-add-unknown-platform` 等全 PASS；5 条失败与 1 条 SKIP
  全为既有环境族（racc 原生扩展 `Gem::Ext::BuildError`、msys `0xC0000022` 的 `git clone`、
  `add-group` 的 2.7.2 联网装 bundler deferral）。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen` 0、
  `git diff --check` 0、全量 `crystal spec` **634 examples, 0 failures, 4 errors**（4 = 既有
  `spec/git_source_spec.cr` msys Low-IL）。

已声明差异：

- `--quiet` 用「丢弃 stdout」近似 `ui.level = "warn"`，未建 `info`/`confirm`/`warn` 分级；
  若某命令把警告写到 stdout 会与本实现不同（当前无此路径）。
- `binstubs --path --force` 在 2.7.2 下的 `--force` 语义未与 `--path` 组合单独验证（只验证了
  取值仍为 `bin`）。
- `add` 的 gemspec dev 依赖冲突分支（`dsl.rb:265-285` 的 pub_grub 交集）未建模。

## 2026-11-18（M7(3)/M7(2)：`help` / `--help` 渲染 vendored manpage）

**范围**：`bundle help [COMMAND]`、`bundle <cmd> --help`、Thor 的 dash 映射（`-h`/`-?`/`--help`/`-D`）现在都渲染参考自带的 `.ronn` 手册页，而不再打印本仓自制 `Usage:` 横幅。此前 `docs/compat-report.md:1798/1813/1817/1836/1851/2259/2520/2524/2607/2641` 把「无 manpage」列为已声明差异，本条即该差异的关闭记录。

**参考锚点**

- `bundler/cli.rb:155-185 #help(cli = nil)`：先 `all_aliases` 归一别名 → 插件命令委派 `Plugin.exec_command(cli, ["--help"])` → `case` 把 `nil` 映射成 `bundle`、`gemfile` 映射成自己的页、其余成 `bundle-<cli>` → `man_pages` 命中后若 `Bundler.which("man")` 存在则 `Kernel.exec("man", …)`，**否则 `puts File.read("#{man_path}/#{File.basename(man_page)}.ronn")`**；未命中则 `bundler_command_path(cli)` → `Kernel.exec(command_path, "--help")`；再否则 `super`（Thor `command_help`）。
- `bundler/cli.rb:16-24 / 41-53`：`COMMAND_ALIASES`（`check=>c`、`install=>i`、`plugin=>""`、`list=>ls`、`exec=>e/ex/exe`、`cache=>package/pack`、`version=>-v/--version`）与 `all_aliases`。
- `bundler/vendor/thor/lib/thor/base.rb:17`：`HELP_MAPPINGS = %w(-h -? --help -D)`；`thor/group.rb:229-232` 在 `dispatch` 首行把 `HELP_MAPPINGS` 首参转成 `help`。
- `bundler/vendor/thor/lib/thor.rb:252-280 command_help`：无手册页时的正文形状（`Usage:` / `  bundle <usage>` / 空行 / `Options:` 三行 class option / 空行 / 描述）。
- `bundler/vendor/thor/lib/thor/base.rb:619-626 handle_argument_error`：`ERROR: "bundle help" was called with arguments [...]` + `Usage: "bundle help [COMMAND]"`，**两行、无尾随空行**。
- `bundler/vendor/thor/lib/thor/error.rb:24-55`：`Could not find command "<name>".` + `DidYouMean` 的 `Did you mean?  "<候选>"`（两空格）。

**实现**

- 新增 `src/celerite/manpages.cr`：`Manpages.page_name` 映射 `bundle` → `bundle.1.ronn`、`gemfile` → `gemfile.5.ronn`、其余 → `bundle-<cmd>.1.ronn`（等价于参考的 `File.basename(man_page)` 拼法）；`search_dirs` 依次为 `CELERITE_MAN_DIR`、可执行文件旁 `assets/man/<profile>` 与 `../assets/man/<profile>`、源码树 `../../assets/man/<profile>`；`render` 在 Windows 上把 LF 折成 CRLF（参考用文本模式 IO 写 stdout，实测 `help install` 去掉 CR 后与 `.ronn` 逐字相等）。
- 手册页资产随仓入库：`assets/man/4.0.24/`（31 个 `.ronn`，121444 字节）与 `assets/man/2.7.2/`（33 个，121322 字节，多 `bundle-inject.1.ronn`/`bundle-viz.1.ronn`）。两版共 11 个页面相同、20 个不同，因此不能共用一套；入库前逐字节确认无 CR。
- `Commands.help(stdout, rest, stderr)` 重写：`reject_unknown_switches(SWITCH_FLAGS_CLASS, SWITCH_VALUES_CLASS)` → 位置参数多于 1 个按 `handle_argument_error` 报两行 exit 15 → `COMMAND_ALIASES` 归一 → 非 `gemfile`/非参考命令时先试插件、再 `Could not find command` (+`Suggestions.message` 建议) exit 15 → `Manpages.render` → 无页面时 `THOR_HELP_FALLBACK` 拼 Thor `command_help` 文本 → 兜底仍按未知命令。
- `dispatch` 的 dash 映射从 `help`/`--help`/`-h` 扩到 `-?`/`-D`；`bundle <cmd> --help`（`exec` 除外，参考把 `--help` 交给子进程）改为带 `stderr` 调 `help`。
- profile 门控：`reference_commands` 在 2.x 下剔除 `tree`/`install_or_cli_help`（`Bundler::CLI` 反射：2.7.2 为 32 个命令、4.0.24 为 33 个），因此 `help tree`/`help install_or_cli_help` 在 2.7.2 下按未知命令 exit 15 且不给建议；`help viz`/`help inject` 在 2.7.2 下命中自己的页面（4.0.24 无此两页，走 Thor 兜底）。`Suggestions` 的字典与 `REFERENCE_COMMANDS` 同源，故 `lst`→`list`、`get`→`gem` 与参考一致，而 `extra`/`mahcommand`/`bogus-cmd`/`candle` 无建议。

**证据（逐字 A/B，双侧独立沙箱、隔离 HOME/GEM_HOME/TEMP）**

| 命令 | 4.0.24 exit / stdout | 2.7.2 exit / stdout |
| --- | --- | --- |
| `help install`（=`install --help`=`help i`=`-h install`=`--help install`） | 0 / 13090 | 0 / 16260 |
| `help`（=`--help`=`-h`=`-D`=`-?`） | 0 / 3841 | 0 / 3371 |
| `help gemfile` | 0 / 24173 | 0 / 21919 |
| `help help` / `help -h` | 0 / 349 | 0 / 349 |
| `help c` / `help ls` | 0 / 812 / 870 | 0 / 1015 / 767 |
| `help tree` | 0 / 359（Thor 兜底） | **15** / `Could not find command "tree".` |
| `help viz` / `help inject` | 0 / 365 / 404（Thor 兜底） | 0 / 1125 / 854（各自页面） |
| `help cli_help` | 0 / 361 | 0 / 361 |
| `help install_or_cli_help` | 0 / 363（Thor 兜底） | **15** / `Could not find command "install_or_cli_help".` |
| `help nosuchcmd` / `help get` / `help lst` | 15 / 36、51、52 字节 stderr（`get` 带 `Did you mean?  "gem"`） | 同形 |
| `help install extra` | 15 / 99 字节 stderr（`ERROR:` + `Usage:` 两行） | 同形 |

- 22 例 A/B 在 4.0.24 与 2.7.2 上**全 SAME**（`SAME=False` 计数 0）；`-D`、`--help install`、`-h install` 追加两例亦 SAME。
- 新增 6 个差分夹具（`help-install`、`help-alias-check`、`help-unknown`、`help-gemfile`、`help-extra-args`、`help-tree-fallback`）：4.0.24 `6 passed, 0 failed`；2.7.2 `6 passed, 0 failed`（`help-tree-fallback` 在 2.7.2 下两侧同为 exit 15）。
- `spec/m7_help_manpage_spec.cr` 12 examples 全绿（含 2.7.2 的 `tree`/`install_or_cli_help` 未知命令与 `viz`/`inject` 页面）；`spec/m7_exec_spec.cr` 的 `--help` 断言随之从 `Usage:` 改为 manpage 首行。
- 全量 `crystal spec`：**646 examples, 0 failures, 4 errors**（4 为既有 `spec/git_source_spec.cr` 的 msys `0xC0000022` 环境族）。

**已声明差异 / 未覆盖**

- 前缀命令解析（Thor `find_command_possibilities`）未实现：参考 `instal` 解析成 `install`（`instal --help` 打印 Thor 的 `Usage: bundle install [OPTIONS]` 长选项表），我方按未知命令 exit 15；`co` 的 `Ambiguous command co matches [config, console]` 同理未复刻。
- `[REMOVED]` 命令未复刻：参考 `viz` exit 9 `[REMOVED] The \`viz\` command has been renamed to \`graph\` and moved to a plugin.` + 第二行 URL，`inject` exit 9 `[REMOVED] The \`inject\` command has been replaced by the \`add\` command`；我方仍报未知命令 exit 15。
- 无参 `bundle` 的 default_command 语义已实现（2026-11-18，见本文末节「`cli_help` 与无参 `bundle` 的 default_command 语义」）：4.0.24 打 5 行警告块后走 `install`（无 Gemfile 时再打 `cli_help` 全表并 exit 10），前置类选项（`bundle --no-color install`）同样被当成 `install` 的位置参数并 exit 15；该节的「已声明差异」列出剩余未复刻项。
- `-t`/`--tree` 未实现（4.0.24 有 `tree` 命令，输出 2219 字节的 `bundler:c_l_i` 树）。
- Thor 兜底文本的三行 class option 是硬编码的 4.0.24/2.7.2 共同形状；两版若将来新增 class option 需同步。
- 手册页资产为 vendored 副本：升级参考版本时必须重新复制并复核两版差异清单。
- 未验证：`man` 在 PATH 上时的 `Kernel.exec("man", …)` 分支（本机无 `man`，参考恒走 `.ronn` 分支）；`help <plugin-cmd>` 在 2.7.2 下的行为（2.7.2 的 `#help` 没有插件分支）。

## 2026-11-18（M7(2)/M7(3)：`cli_help` 与无参 `bundle` 的 default_command 语义）

**参考锚点**

- `bundler/cli.rb:99-121` `cli_help`：`version` → `Bundler.ui.info "\n"` → `primary_commands = ["install","update","cache","exec","config","help"]` → `list = self.class.printable_commands(true)` → `by_name = list.group_by { |name, _message| name.match(/^bundler? (\w+)/)[1] }` → `utilities = by_name.keys.sort - primary_commands` → `shell.say "Bundler commands:\n\n"` / `shell.say "  Primary commands:\n"` / `shell.print_table(primary_commands, indent: 4, truncate: true)` / `shell.say` / `shell.say "  Utilities:\n"` / `shell.print_table(utilities, indent: 4, truncate: true)` / `shell.say` / `self.class.send(:class_options_help, shell)`。两组都按**名字列表**顺序渲染（`primary_commands.map! { |name| by_name[name].first }`），不是声明顺序。
- `bundler/cli.rb:133-148` `self.default_command(meth = nil)`：`return super if meth`；`unless Bundler.settings[:default_cli_command]` 时打 5 行警告块（末尾空行）；返回 `Bundler.settings[:default_cli_command] || "install"`。
- `bundler/cli.rb:290-313` `install` 的 `rescue GemfileNotFound` → `invoke_other_command("cli_help")` + `raise error`（re-raise 以保留失败退出码）。
- `bundler/vendor/thor/lib/thor.rb:591-595` `retrieve_command_name`：`args.shift if meth && (map[meth] || meth !~ /^\-/)` —— 首 token 以 `-` 开头且不是 dash 映射时**不 shift**；`:605-620` `normalize_command_name(nil)` → `default_command.to_s.tr("-","_")`（警告块在此触发）。
- `bundler/vendor/thor/lib/thor/shell/table_printer.rb`：`@truncate = options[:truncate] == true ? Terminal.terminal_width : options[:truncate]`；首列 `"%-#{maxima + 2}s"`、末列 `"%-s"`；`truncate` = `chars[0, @truncate - 3 - @indent].join + "..."`；`indentation = " " * @indent`。`thor/shell/terminal.rb` 的 `unix?` 不匹配 mingw，故 Windows 恒 80 列。
- `bundler/vendor/thor/lib/thor/base.rb:639-675` `class_options_help`/`print_options`：`padding = options.map { |o| o.aliases_for_usage.size }.max.to_i`，`shell.say "Options:"` + `shell.print_table(list, indent: 2)` + `shell.say ""`。
- `bundler/settings/validator.rb:78-81`：`rule %w[default_cli_command], "default_cli_command must be either 'install' or 'cli_help'"`，非法值 `fail!` 出三行文案；`bundler/settings.rb:401-423` 的 `set_key` 在写盘**之前**调用 `Validator.validate!`。
- `bundler-2.7.2/lib/bundler/cli.rb:110` 用 `default_task(Bundler.feature_flag.default_cli_command)` 在类定义时固定默认命令，`self.default_command` 覆盖从不执行 → **2.7.2 没有 5 行警告块**；`feature_flag.rb:38` 在该版默认 `install`。

**实现**

1. `src/celerite/cli/commands.cr` 新增常量：`CLASS_OPTION_LINES`（三行 class option，描述列偏移 53）、`DEFAULT_CLI_COMMAND_NOTICE`（5 行警告块）、`CLI_HELP_PRIMARY`、`PRINTABLE_COMMANDS`（4.0.24 的 30 条 `printable_commands(true)`，banner 前缀 `bundle `）、`PRINTABLE_COMMANDS_HIDDEN_2_X = ["tree","clean"]`、`DASH_MAPPED_COMMANDS = ["--help","-h","-?","-D","-t","--tree","--version","-v"]`、`DEFAULT_CLI_COMMAND_VALUES = ["install","cli_help"]`。
2. `render_command_table(stdout, rows, indent, truncate_at)` 复刻 `TablePrinter`：首列 `ljust(maxima + 2)`、末列原样、超长 `sentence[0, truncate_at - 3 - indent] + "..."`、每行 `" " * indent` 前缀。
3. `Commands.cli_help(stdout, stderr, rest)`：`reject_unknown_switches` → 位置参数报 `ERROR: "bundle cli_help" was called with arguments [...]` + `Usage: "bundle cli_help"`（无 `[OPTIONS]`）→ 15；否则 version banner + `Bundler commands:` + primary 6 行 + `Utilities:` N 行 + `Options:` 三行 + 收尾空行。
4. `dispatch`：`raw_args.empty? || (raw_args[0].starts_with?("-") && !DASH_MAPPED_COMMANDS.includes?(raw_args[0]))` 时走 `default_cli_command(stdout)`，并把 `strip_global_flags` 之**后**的 `args` 作为该命令的 rest（前置类开关因此成为默认命令的开关、其余 token 成为位置参数 → 15）。`cli_help` 进 `ECHO_COMMANDS`，故 `--verbose` 会回显 ``Running `bundle cli_help --verbose` with bundler …``。
5. `config_store` 在写盘前按 4.x 校验 `default_cli_command`（2.7.2 静默通过）。
6. `commands_install.cr` 的 `install` 在 4.x 下 `rescue GemfileNotFound` → 先 `Commands.cli_help(stdout, stderr, [] of String)` 再 `raise`（exit 10 + 表）；2.7.2 直接 re-raise（out 为空）。
7. 删除 `src/celerite/cli.cr` 的 `USAGE`（裸 `bundle` 不再打印 Celerite 自有 usage 屏）。

**证据**

| 检查 | 结果 |
| --- | --- |
| `cli_help` 全文（4.0.24） | A/B SAME，2718 字符 / 44 行；primary `#` 在列 32，utilities 24 行 `#` 在列 35，`Options:` 三行 `#` 在列 53，末尾 2 个换行 |
| `cli_help` 全文（2.7.2） | A/B SAME，2560 字符 / 42 行；utilities 22 行（无 `clean`、无 `tree`） |
| `cli_help extra` / `cli_help --bogus` | 双 profile 均 SAME（15 + 两行 usage / 15 + `Unknown switches "--bogus"`） |
| `cli_help --verbose` | SAME（2774 = 2718 + 56 的回显行） |
| `cli_help --help` / `help cli_help` | SAME（361 字节 Thor 兜底页） |
| 裸 `bundle`（4.0.24，已 install） | SAME（629 字节 = 警告块 + 空行 + 两行 install 结论）；`--no-color` 637；`--quiet` 506 |
| 裸 `bundle`（2.7.2） | SAME（无警告块；`--verbose` 560） |
| 无 Gemfile 裸 `bundle` | 4.0.24 SAME（exit 10 / out 3218 = 警告块 + 全表 / er `Could not locate Gemfile`）；2.7.2 SAME（exit 10 / out 0） |
| `config set default_cli_command bogus --global` | 4.0.24 SAME（15 + er 148 三行）；2.7.2 SAME（exit 0 静默） |
| `default_cli_command = cli_help` 后裸跑 / `--verbose` / `--no-color lock` | 双 profile SAME（2718 / 2774 / 15 + `ERROR: "bundle cli_help" was called with arguments ["lock"]`） |
| 新差分夹具 `cli-help`、`cli-help-extra-arg`、`cli-help-unknown-switch`、`default-cli-command-invalid`、`default-cli-command-clihelp`、`bare-leading-flag` | 4.0.24 `6 passed, 0 failed`；2.7.2 `6 passed, 0 failed` |
| 回归集 | 4.0.24 14 夹具 `14 passed, 0 failed`；删除 `USAGE` 后复跑 6 夹具 `6 passed, 0 failed` |
| `spec/m7_cli_help_spec.cr` | 10 examples, 0 failures |
| 全量 `crystal spec` | **656 examples, 0 failures, 4 errors**（4 为既有 `spec/git_source_spec.cr` 的 msys `0xC0000022`） |
| `crystal tool format --check src spec` / `crystal build --no-codegen` / `git diff --check` | 0 / 0 / 0 |

A/B 共 23 例 × 2 profile，唯一差异是 `bundle --verbose` 场景（参考额外打印 `Found no changes, using resolution from the lockfile` / `Using …` / `N:  …` 的调试图层，我方不回显该类调试行，属既有已声明差异）。

**已声明差异 / 未验证**

- `--verbose` 的调试图层（`Found no changes, using resolution from the lockfile`、`Using <gem>`、`N:  <gem> (<ver>) from <path>`、`Writing lockfile to …`）仍不复刻；因此裸 `bundle --verbose` 这类「只有调试行不同」的场景只做前缀/末段比对，不宣称全量逐字一致。
- `install_or_cli_help`（4.0.24 的三行弃用告警 + 转发 `install`）未实现：`default_cli_command` 被外部配置成该值时，我方按 `install` 处理但不打那三行 warn。
- Thor 的前缀命令解析与歧义报错（`instal` → `install`、`co` → `Ambiguous command co matches [config, console]`）：已于 2026-11-18 关闭，见文末「命令名解析 / tree / [REMOVED]」节。
- 未验证：2.7.2 下把 `default_cli_command` 设为非法值后再裸跑 `bundle` 的实际走向（该版无校验，参考会直接用该字符串查命令表；我方 `configured.is_a?(String)` 直接返回，两边在「非法值」这一路径上未做 A/B）。

## 2026-11-18（M7(2)/M7(3)：命令名解析 / `tree` / `[REMOVED]`）

**范围**：Thor 的前缀命令解析（`instal` → `install`、`cl` 在 4.0.24 解析为 `clean` 而在 2.7.2 报歧义）、歧义报错（`Ambiguous command co matches [config, console]`，exit 15）、`tree` 命令与其 dash 映射（`-t`/`--tree`）、4.0.24 的 `viz`/`inject` `[REMOVED]` 出口（exit 9）、`install_or_cli_help` 的 4.x 弃用告警转发。本条关闭了不少于三处此前声明：上一节的 `install_or_cli_help` 未实现、更早节的「前缀命令解析未复刻」与「`[REMOVED]` 命令未复刻」（`docs/compat-report.md:3601-3602`、`:3657`）。

**参考锚点**

- `bundler/vendor/thor/lib/thor.rb:675-706` 的 `tree`：namespace 蓝色一行（`klass.namespace || 'default'`，root 类除外）→ 子命令缩进 +2 空格 → `klass.commands` 去掉 `hidden?` 与 `name == "help"` → 按命令名排序 → 描述取 `description.split("\n").first`，非空则 ` (<desc>)`；行首图标末项 `└─`、其余 `├─`（`thor.rb:696`），命令名绿色。
- `bundler/vendor/thor/lib/thor/base.rb:17-18`：`HELP_MAPPINGS = %w(-h -? --help -D)`、`TREE_MAPPINGS = %w(-t --tree)`；2.7.2 的 vendored thor 无 `tree`，即无 `TREE_MAPPINGS`。
- `bundler-4.0.24/lib/bundler/cli.rb:585-587` `def viz` → `SharedHelpers.feature_removed! "The \`viz\` command has been renamed to \`graph\` and moved to a plugin. See https://github.com/rubygems/bundler-graph"`。
- `bundler-4.0.24/lib/bundler/cli.rb:635-638` `def inject(*)` → `feature_removed! "The \`inject\` command has been replaced by the \`add\` command"`。
- `bundler-4.0.24/lib/bundler/shared_helpers.rb:135-138` `def feature_removed!(message)` → `require_relative "errors"; raise RemovedError, "[REMOVED] #{message}"`；`bundler-4.0.24/lib/bundler/errors.rb:28` `class RemovedError < BundlerError; status_code(9); end` ⇒ 退出码 9，消息带 `[REMOVED] ` 前缀。
- `bundler-4.0.24/lib/bundler/cli.rb:55` `def self.aliases_for(command_name)`、`:100` `def cli_help`、`:124` `def install_or_cli_help`（三行 warn 后 `invoke_other_command("install")`）、`:557` `if cli_help || ARGV.include?("version")`。
- `bundler-2.7.2/lib/bundler/cli.rb:531-532` `viz` → `major_deprecation 2, "…renamed to \`graph\`…"`（exit 0 的弃用告警，不 exit 9）；`:583-584` `inject(name, version)` → `major_deprecation 2, "…replaced by the \`add\` command"`。

**实现**

1. `src/celerite/cli/commands.cr` 新增 `command_possibilities(word)`（L239-252）：候选 = `reference_commands` + `COMMAND_ALIASES` 的键 + `dash_command_map` 的键；**精确命中直接返回 `[word]`**；唯一别名目标则折叠成该目标；否则返回排序后的可能性列表 —— 复刻 Thor `find_command_possibilities` 的折叠顺序。
2. `resolve_command_name(word, stderr)`（L258-266）：多候选时打印 `Ambiguous command <word> matches [<a>, <b>]` 并返回 `nil`，`dispatch` 转 exit 15。
3. `dash_command_map`（L55-56、常量 `DASH_COMMAND_MAP_4_X` L367-376）：4.x 把 `-t`/`--tree` 映射到 `tree`；2.7.2 的映射表不含这两项，故 `bundle -t` 走 `Unknown switches "-t"`（15），`bundle tree` 报 `Could not find command "tree".`（15）。
4. `expand_deprecated_alias`（L272-280）：仅 4.x 对 `install_or_cli_help` 打三行告警后改派 `install`；2.7.2 原样返回 → 未知命令 15。
5. `Commands.tree`（L2772-2857）：常量 `TREE_ROOT_NAMESPACE = "bundler:c_l_i"`、`TREE_HIDDEN_COMMANDS = ["help","tree"]`、`TREE_SUBCOMMANDS`（config 4 条 / doctor 2 条 / plugin 3 条，`Tuple(String,String)`）；2.7.2 直接报未知命令 15；4.x 先 `reject_unknown_switches`，位置参数报 `ERROR: "bundle tree" was called with arguments [...]` + `Usage: "bundle tree"`，否则 `render_tree_rows` 用 `├─`/`└─` + 空格 + ` (<desc>)` 渲染，root 行 `bundler:c_l_i`、子节行 `  bundler:c_l_i:<name>` 后 4 空格缩进。
6. `removed_command`（L2859-2957）：4.x 的 `removed_command_4_x` 先 `reject_unknown_switches`（故 `inject --bogus` 先报 `Unknown switches "--bogus"` 15），`viz` 带位置参数时报 `Usage: "bundle viz [OPTIONS]"` 15，否则 `raise RemovedError.new("[REMOVED] …")`（viz 两行含 URL，inject 单行）；2.7.2 的 `legacy_removed_command` 走 `[DEPRECATED]` 告警路径。
7. `src/celerite/errors.cr:28-44` 新增 `InvalidOptionError < UsageError`（`wrap?` 开，friendly-errors 折行，exit 15）与 `RemovedError < Error`（`status_code : Int32 = 9`）；`src/celerite/cli.cr:23-32` 的 `rescue Error` 直接取 `ex.status_code`，故 `RemovedError` 自然 exit 9。
8. `version` 的 build-metadata 判定改为按原始 token：`dispatch` L96-101 传 `raw_args.includes?("version")`（`strip_global_flags` **之前**的参数），签名 `Commands.version(worded : Bool, stdout, stderr, rest)`。这修掉了 `-v` 经 dash 映射折叠成 `version` 后误加 build metadata 的回归，语义对齐参考 `cli.rb:557` 的 `ARGV.include?("version")`。

**证据（逐字 A/B，双侧独立沙箱、隔离 HOME/TMPDIR）**

参考侧为 Ruby 4.0.24 / 2.7.2 的 `bundle`，我方为本仓 `celerite.exe`；两侧均 `cmd.exe /c` 重定向到文件后读码、CRLF→LF 归一化再逐字比对。

| 用例 | 参考 exit | 我方 exit | stdout | stderr |
| --- | --- | --- | --- | --- |
| 4.0.24 `instal`（前缀 → `install`） | 10 | 10 | 2718 = 2718 | 25 = 25 `Could not locate Gemfile` |
| 4.0.24 `co` | 15 | 15 | 0 | 47 = 47 `Ambiguous command co matches [config, console]` |
| 4.0.24 `tree` | 0 | 0 | 2178 = 2178（41 行） | 0 |
| 4.0.24 `-t` | 0 | 0 | 同 `tree` | 0 |
| 4.0.24 `viz` | 9 | 9 | 0 | 125 = 125 |
| 4.0.24 `inject` | 9 | 9 | 0 | 70 = 70 |
| 4.0.24 `lst` | 15 | 15 | 0 | 52 = 52 `Could not find command "lst".` + `Did you mean?  "list"`（两空格） |
| 4.0.24 `install_or_cli_help` | 10 | 10 | 2718 = 2718 | 269 = 269（三行弃用告警 + `Could not locate Gemfile`） |
| 2.7.2 `cl` | 15 | 15 | 0 | 47 = 47 `Ambiguous command cl matches [clean, cli_help]` |
| 2.7.2 `tree` | 15 | 15 | 0 | 31 = 31 `Could not find command "tree".` |
| 2.7.2 `-t` | 15 | 15 | 0 | 22 = 22 `Unknown switches "-t"` |

- 11 组全部逐字相等（stdout/stderr 逐字一致，非仅退出码）。
- `tree` 输出：41 行、**2178 字符**（`out.size`，Crystal 侧按字符计）/ **2326 字节**（UTF-8，`├─`/`└─` 的 U+2500/U+251C/U+2514 各占 3 字节）；末尾一个换行。`spec/m7_cli_dispatch_spec.cr` 的 `TREE_4_X` 常量把 41 行逐行写死。
- `viz` 125 字节 = `[REMOVED] The \`viz\` command has been renamed to \`graph\` and moved to a plugin.` + 第二行 `See https://github.com/rubygems/bundler-graph`；`inject` 70 字节 = `[REMOVED] The \`inject\` command has been replaced by the \`add\` command`。
- 新增 4 个差分夹具（`ambiguous-command-prefix`=`co`、`removed-viz`=`viz`、`removed-inject`=`inject`、`tree-command`=`tree`，每个仅含 `command` 与 `Gemfile` 两文件，无绝对路径），用**裸夹具名**跑（传 `fixtures/differential/<name>` 会被 `script/differential:535-544` 再拼一次根，导致 0 passed）：
  - 4.0.24：`differential (4.0.24): 4 passed, 0 failed, 0 skipped`，harness EXIT 0；逐夹具 `(exit=15)` / `(exit=9)` / `(exit=9)` / `(exit=0)`。`KEEP_DIFFERENTIAL=1` 保留的产物实测（我方 `cel.*` / 参考 `ref.*`）：`co` err 47 / 48 字节、`viz` err 125 / 127、`inject` err 70 / 71、`tree` out 2326 / 2367（差值为 CRLF，harness 比对前归一化），全部非空。
  - `BUNDLER_REF_VERSION=2.7.2`：`differential (2.7.2): 3 passed, 0 failed, 1 skipped (documented deferrals)`，harness EXIT 0 —— `co` 47 / 48、`inject`（无参）87 / 89、`tree` 31 / 32；`removed-viz` 由 `fixtures/differential/removed-viz/deferred-2.7.2` 记为 documented deferral：2.7.2 的 `cli/viz.rb:21-24` 在 `rescue LoadError` 里先 `Bundler.ui.error e.inspect`，即多打印一行 `#<Gem::MissingSpecError:"Could not find 'ruby-graphviz' (>= 0) among 47 total gem(s)\nChecked in 'GEM_PATH=…'>`，该行内嵌宿主 gem 计数与 GEM_PATH，不可逐字复现（`src/celerite/cli/commands.cr:2920-2929` 已声明）。
- **教训（夹具贡献者必读）**：首次提交的这 4 个 `command` 文件**缺行尾换行**，`script/differential:372/395` 用 `while IFS= read -r cmd <&3` 读命令，无换行 EOF 时 `read` 返回 1、循环体一次都不执行 → 两侧输出全空却报 PASS（假绿；`KEEP_DIFFERENTIAL=1` 下 `ref.out`/`cel.out` 均为 0 字节即为铁证）。已修复（补行尾换行后 `git diff --check` 干净），并把上表换成补换行后的真实实测值；`removed-viz` 的 2.7.2 差异也正是在补换行后才暴露。
- `spec/m7_cli_dispatch_spec.cr` 9 examples 全绿；`spec/m7_version_spec.cr` + 该文件合计 13 examples 全绿；相邻四文件（`m7_cli_help_spec` + `m7_cli_dispatch_spec` + `m7_command_switch_surface_spec` + `m7_plugin_commands_spec`）35 examples 0 failures。
- `crystal build --no-codegen src/cli.cr` exit 0（仅 `src/celerite/cli/commands_install.cr:1089:43` 与 `:1153:20` 两条既有 `Deprecated File.executable?` warning）；`crystal tool format --check src spec` exit 0。
- 全量 `crystal spec`：**665 examples, 12 failures, 0 errors, 1 pending**（5:22）。这 12 条已用 `git checkout d3cd04e -- src/celerite/cli/commands.cr src/celerite/errors.cr` 在改动前基线上复跑验证**同样失败**，属本机环境族（`spec/config_spec.cr:97/:146`、`spec/m7_deployment_path_spec.cr:105`、`spec/m7_list_groups_plain_env_spec.cr:54`、`spec/m7_path_system_spec.cr:53/:67/:81/:108`、`spec/m7_plugin_install_source_spec.cr:67/:98`、`spec/m7_show_no_lockfile_spec.cr:135/:182`），非本切片引入。

**已声明差异 / 未验证**

- `clean` 的 `--force` 守卫位置不同：4.0.24 在**无 Gemfile** 时也先校验危险提示，`bundle cl`（解析为 `clean`）与显式 `bundle clean` 均为 exit 15 + `Cleaning all the gems on your system is dangerous! …run \`bundle clean --force\`.` 双行；我方先撞 `Could not locate Gemfile`（exit 10）。故 `spec/m7_cli_dispatch_spec.cr` 的 4.x `cl` 用例改断言 `cl --force`（只校验 exit ≠ 15 且 stderr 不含 `Ambiguous command cl`），不宣称该路径逐字一致。
- 2.7.2 的 `viz` 已 A/B 且确认差异：参考在 `[DEPRECATED]` 行后多打印 `#<Gem::MissingSpecError: …among 47 total gem(s)…GEM_PATH=…>`（宿主 gem 计数与路径内嵌，不可复现），我方只打 `[DEPRECATED]` + 两行安装指引（`src/celerite/cli/commands.cr:2925-2929`），因此该夹具在 2.7.2 下记为 documented deferral。2.7.2 的 `inject`（无位置参数 → 两行 usage exit 15）已 A/B 一致并进入夹具。
- 未验证：全量差分（`script/differential` 不带夹具名跑全部目录）未在本轮执行，只跑了上述 4 个新夹具 × 2 profile；`man` 在 PATH 上的 `Kernel.exec("man", …)` 分支仍未验证（沿用上一节声明）。

## 2026-11-19（M7(3)：`console` 的进程内引导与组 require 语义）

**范围**：`bundle console [GROUP]` 从「exec 控制台可执行文件 + `RUBYOPT=-rbundler/setup`」改为「用 bridge 引导脚本在 bundle 语境里 require 依赖后启动控制台」，并让 `GROUP` 真正参与 `Bundler.require`。

**参考锚点**

- `bundler-4.0.24/lib/bundler/cli/console.rb:11-17` `run`：`group ? Bundler.require(:default, *group.split(" ").map!(&:to_sym)) : Bundler.require`；`ARGV.clear`；`console = get_console(Bundler.settings[:console] || "irb")`；`console.start`。
- 同文件 `:19-36` `get_console(name)`：`require name` + `get_constant(name)`；`rescue LoadError` → 非 `irb` 时 `Bundler.ui.error "Couldn't load console #{name}, falling back to irb"` 后 `name = "irb"; retry`；`irb` 自身缺失时 `Bundler.ui.error "#{name} is not available"; exit 1`（4.0.24 在此之前多一段 `Gem::BUNDLED_GEMS.force_activate "irb"` 重试）。
- 同文件 `:38-45` `get_constant(name)`：`{"pry"=>:Pry, "ripl"=>:Ripl, "irb"=>:IRB"}[name]` → `Object.const_get`。
- `bundler-2.7.2/lib/bundler/cli/console.rb`: `:11-17` `run` 与 `:33-40` `get_constant` 同上；`:22-30` **无** `Gem::BUNDLED_GEMS.force_activate` 分支。两侧都读 `Bundler.settings[:console]`（即 `BUNDLE_CONSOLE` 键在 4.0.24 与 2.7.2 均存在）。

**实现**

1. 新增 `assets/bridge/console_boot.rb`：`require "bundler/setup"` → 依 `ENV["CELERITE_CONSOLE_GROUPS"]` 决定 `Bundler.require(:default, *groups.map!(&:to_sym))` 或无参 `Bundler.require` → `ARGV.clear` → 按同一常量映射 `require` 控制台 gem 并取其常量 → `console.start`；`LoadError` 时按参考文案 `Couldn't load console <name>, falling back to irb` 回退、`irb` 缺失打 `irb is not available` 并 exit 1。
2. `src/celerite/cli/commands_surface.cr` 的 `console` 删除 `find_console_executable` 与 `RUBYOPT` 拼接，改为带 `BUNDLE_GEMFILE` / `CELERITE_CONSOLE` / `CELERITE_CONSOLE_GROUPS` 环境跑 `ruby <boot>`（`.bat`/`.cmd` 走 `cmd /c`），stdio 继承；新增 `console_boot_path`（`CELERITE_CONSOLE_BOOT` 覆盖 → 源树相对路径 → exe 目录候选）。Thor 位置参数拒绝（`ERROR: "bundle console" was called with arguments [...]` / `Usage: "bundle console [GROUP]"`，exit 15）保持不变。
3. `spec/m7_console_spec.cr` 重写为 8 例：`console foo` → `PROBE_START default=1 foo=1 argv=[]`、无 GROUP → `default=1 foo=0 argv=[]`、`BUNDLE_CONSOLE=ripl` → `RIPL_START …`、PATH 上放伪 `pry.bat` 仍用 bundle 内控制台（钉住旧 PATH-exec 偏差已移除）、退出码透传、fallback 首行 + `irb is not available`、无控制台时末行 `irb is not available`、两个位置参数 → 15。因 console 子进程继承 stdio，断言改为经 `bin/celerite.exe` 子进程捕获 stdout/stderr。

**证据（参考实测 + 双 profile 差分）**

- 探针工程（`C:\temp\con\proj`，3 个 path gem：默认组 `probe_default`、`group :foo` 的 `probe_foo`、打印后 `exit 0` 的 `pry`；`.bundle/config` 设 `BUNDLE_CONSOLE: "pry"`）：4.0.24 与 2.7.2 参考均 `console foo` → `PROBE_START default=1 foo=1` exit 0、无 GROUP `console` → `PROBE_START default=1 foo=0` exit 0（**无参 `Bundler.require` 只 require 默认组**）；配置的控制台不在 bundle 内时两 profile 均 exit 1 且首行 `Couldn't load console pry, falling back to irb`（4.0.24 随后因本机 irb/reline/fiddle 链崩出 error report，属环境，不镜像；2.7.2 末行 `irb is not available`）。我方 `bin/celerite.exe` 在 **probe 的两个成功场景**上逐字一致：`console foo` → `PROBE_START default=1 foo=1 argv=[]` exit 0、无 GROUP → `PROBE_START default=1 foo=0 argv=[]` exit 0。fallback 场景只对齐首行文案与退出码（见「已声明差异」）。
- 差分夹具 `fixtures/differential/console-group/`（`command` = `install` + `console foo`，`extra/` 放 3 个 path gem 与 `.bundle/config`）：4.0.24 `1 passed, 0 failed, 0 skipped`、2.7.2 `1 passed, 0 failed, 0 skipped`，harness EXIT 0。`KEEP_DIFFERENTIAL=1` 抽查两侧 `console foo` 输出均为 37 字节 `PROBE_START default=1 foo=1 argv=[]`、stderr 为空，install 段的唯一差异是沙箱 `Bundled gems are installed into` 路径 ⇒ 非假绿。
- 负对照：把 `console_boot.rb` 临时改回仅 `require "bundler/setup"`（不做组 require）后 `crystal spec spec/m7_console_spec.cr` EXIT 1、4 条组断言全部 `Expected: "… default=1 …" got: "… default=0 foo=0 …"`；复原后文件 SHA256 `0576BA51…1FBE12` 前后一致。
- `spec/m7_console_spec.cr` 8 examples 0 failures（9.12s）——**前提：先构建 `bin/celerite.exe`**（该文件经 `console_bin` 走子进程取证，缺二进制时用 `pending!` 整组跳过并 exit 0，故仅凭 exit 0 不足以证明通过；本数字建立在已构建的二进制上，命令 `crystal build src/cli.cr -o bin/celerite.exe`）。既有夹具回归 4.0.24 `10 passed, 0 failed, 0 skipped`（`install-fresh`、`cli-help`、`tree-command`、`ambiguous-command-prefix`、`removed-viz`、`removed-inject`、`version-plain`、`list-json`、`help-alias-check`、`bare-leading-flag`），2.7.2 `8 passed, 0 failed, 2 skipped`（`add-group`、`removed-viz` 为既有 documented deferral）。
- `crystal build --no-codegen src/cli.cr` exit 0（仅 `src/celerite/cli/commands_install.cr:1089:43` / `:1153:20` 两条既有 `Deprecated File.executable?` warning）。

**已声明差异 / 未验证**

- 控制台仍在**独立 ruby 子进程**中运行（`ruby console_boot.rb`），不是参考的进程内 `console.start`；对外可观测面（requires、`ARGV.clear`、常量、退出码、文案）已对齐，但进程内行为（如控制台读取调用方 binding、`at_exit` 顺序）不宣称一致。
- fallback 场景（配置的控制台不在 bundle 内）只对齐首行文案与退出码（两侧均 `Couldn't load console pry, falling back to irb` + exit 1），其后输出不一致：2.7.2 参考的行尾警告带 `console.rb:20`（我方为 `console_boot.rb:60`）这类**源码 file:line 提示**，而 4.0.24 参考在本机因 irb/reline/fiddle 链崩出整段 `--- ERROR REPORT TEMPLATE`（环境 quirk）。该 file:line 由实现文件位置决定，不可逐字复现，故 fallback 路径不宣称逐字一致、也不设差分夹具。
- 不镜像 4.0.24 的 `Gem::BUNDLED_GEMS.force_activate "irb"` 重试分支；本机 irb/reline/fiddle 链本身不可用，该分支无法逐字验证。
- 交互式会话（真实 TTY 下 IRB/pry 提示符与 `ARGV` 清空后行为）未逐字 A/B，只用打印后 `exit 0` 的探针控制台取证。
- `add-group` 夹具（`add racc --group dev`）在 4.0.24 下失败于 `Gem::Ext::BuildError: ERROR: Failed to build gem native extension`（racc 原生扩展，环境族，与本节无关）；2.7.2 侧该夹具为既有 documented deferral。
- 本轮未重跑全量 `crystal spec` 与全量差分（沿用上一节 665 examples / 12 条本机环境族失败的记录）。

## 2026-11-19（M7(6) G1：插件 hook 事件写入索引）

**范围**：`plugin install` 写 `.bundle/plugin/index` 时，把 `plugins.rb` 中的 `Bundler::Plugin.add_hook("<event>")` 声明落到 `hooks:` 段（G1 缺口：此前 `hooks:` 只从既有索引读出再原样回写，新装插件的 hook 事件从不写入，参考插件声明的 `after-install` 装后永不触发）；同时让卸载时清除指向被删插件的 hook 名。

**参考锚点**：

- `bundler-4.0.24/lib/bundler/plugin.rb:207-220`：`add_hook` 校验 `Events.defined_event?` 后把 block 追加进 `@hooks_by_event[event]`；`register_plugin` 暂存该 hash，`load "plugins.rb"` 后取 `.keys`。
- `bundler-4.0.24/lib/bundler/plugin/index.rb:54-74`：`register_plugin(name, path, load_paths, commands, sources, hooks)` 对每个事件 `(@hooks[event] ||= []) << name; uniq!`；`save_index` 依次 dump `commands`/`hooks`/`load_paths`/`plugin_paths`/`sources`。
- `bundler-4.0.24/lib/bundler/plugin/index.rb:77-87`：`unregister_plugin` 从每个事件数组删除插件名，数组空则删事件键。

**实现**：

1. `assets/bridge/plugin_command.rb` 的 `--commands` 模式改为 `--commands <plugins.rb> [<load path>...]`：先 `load_plugin_api`，把调用方给的插件 lib 目录 `$LOAD_PATH.unshift`（参考 `register_plugin` 同样先 `load_paths.each { |p| $LOAD_PATH.unshift(p) }` 再 `load plugins.rb`；夹具 plugins.rb 首行 `require "hook_plugin"`，不补 load path 时 `LoadError` 会让声明的命令/事件全部丢失——首跑差分即此形态 FAIL），`load` 后一次输出 `JSON.generate({"commands"=>…keys, "hooks"=>…keys.map(&:to_s)})`，hooks 取 `Bundler::Plugin.instance_variable_get(:@hooks_by_event)`。
2. `src/celerite/plugin_commands.cr:85` 新增 `declared(plugins_rb_path : String, load_paths : Array(String) = [] of String) : NamedTuple(commands: Array(String), hooks: Array(String))`，单次 ruby 调用解析两键（缺键/类型错 → 空数组，`error` 分支仍回空）；`declared_commands` 保留为 `declared(...)[:commands]` 委托（现仅 `spec/m7_plugin_hooks_registration_spec.cr:147` 引用）。
3. `src/celerite/cli/commands_surface.cr` 两处安装路径（本地 `--path` ~1500 行区、remote/`--source` ~1770 行区）改调 `declared(..., [lib_dir])`：冲突检测/合并用 `declared[:commands]`；`declared[:hooks].each` 把当前插件名追加到对应事件数组（`unless includes?` 去重保序，对齐 register_plugin）。`write_plugin_index`（~1900 行区，uninstall 唯一调用点）hooks 段改为遍历事件→插件名数组，`reject removed`、空数组 `next`（对齐 unregister_plugin）。
4. `spec/m7_plugin_hooks_registration_spec.cr` 4 例：索引写入 `after-install` + 命令仍在；探针一次取回 commands/hooks（含 load path）；install 端到端触发 hook（marker 文件写 `after-install`）；无 hook 声明的插件 `hooks:` 段为空。
5. 新差分夹具 `fixtures/differential/plugin-install-hooks/`：`command` 两行（`plugin install hook_plugin --path ./hook_plugin`、`plugin list`，末字节 LF）；`extra/hook_plugin/plugins.rb` 同时 `API.command("hookprobe", …)` 与 `add_hook("after-install") { |_ctx| }`；`file-contains` 断言 `.bundle/plugin/index` 含 `after-install`、`hook_plugin`。

**证据（双 profile 差分 + spec）**：

- `crystal spec spec/m7_plugin_hooks_registration_spec.cr spec/m7_plugin_commands_spec.cr` → **11 examples, 0 failures**；再加 hook 异常 6 例的联跑 **17/0**。
- `KEEP_DIFFERENTIAL=1 bash script/differential plugin-install-hooks`：4.0.24 `PASS plugin-install-hooks (exit=0)`（1 passed, 0 failed, 0 skipped，EXIT 0）；`BUNDLER_REF_VERSION=2.7.2` 同 PASS（1/0/0）。
- 保留产物：4.0.24 `.d/M1A934`、2.7.2 `.d/f3wXgL`。两侧 `.bundle/plugin/index` 均 **12 行**；参考 **338 字节**、我方 **326 字节**（差 12 字节 = 参考在本机按文本模式写 CRLF，每行 1 字节）。逐行读取核对：两侧都含 `  hookprobe: "hook_plugin"`、`  after-install:`、`  - "hook_plugin"`，以及 load_paths/plugin_paths 的 hook_plugin 项，非空。
- 回归：`plugin-install` 夹具双 profile 均 `PASS plugin-install (exit=1)`（`exit=1` 为末条 `exec ruby -e …` 两侧一致），1/0/0。
- `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `src/celerite/cli/commands_install.cr:1089:43`、`:1153:20` 的 `Deprecated File.executable?` 警告）。
- 相邻用例 `spec/m7_plugin_install_source_spec.cr` 2 例（:67/:98）失败为**既有本机环境问题**：stash 掉本轮改动、用旧二进制复跑同样 2 例以相同 `Expected: 0 got: 1` 失败，与 compat-report 既有环境失败记录同族，已 `git stash pop` 复原。

**已声明差异 / 未验证**：

- 参考在 hook 执行时按索引重新加载插件再 `blk.call(*args, &blk)`；我方沿用既有 `exec_plugin_hook` 桥（先 `require` 插件再取 `@hooks_by_event`）。本节只宣称「声明写入索引」与「install 端触发」对齐。
- 参考 `add_hook` 对未定义事件抛 `ArgumentError, "Event '<event>' not defined in Bundler::Plugin::Events"`（`bundler-4.0.24/lib/bundler/plugin.rb:216-217`，事件未定义时 `Events.defined_event?` 校验失败）；我方探针只读取键、不校验事件名，该错误路径未对齐（未验证）。
- 无 Gemfile / 全局 `~/.bundle/plugin` 安装路径的 hooks 落盘未做差分夹具（未验证）；`plugin uninstall` 的 hooks 清理只有实现、无专例/夹具（未验证）。
- 索引字节不逐字一致：参考 CRLF、我方 LF（见上 12 字节差），归一化后才比对语义内容。

## 2026-11-19（M7(6) task-7：hook 失败时序与差分断言通道）

**范围**：① `bundle install` 的 `after-install` 从「摘要与锁文件之后」移到「摘要与写锁之前」，使失败时的可观察面与参考一致（不留 `Gemfile.lock`、不打印 `Bundle complete!`）；② `script/differential` 新增两条夹具级断言通道 `file-absent` / `stderr-contains`（N10）并配自测夹具；③ 新差分夹具 `plugin-hook-raise`。

**参考锚点**：

- `bundler-4.0.24/lib/bundler/installer/parallel_installer.rb:217`：`do_install` 在 `gem_installer.install_from_spec` 之后 `Plugin.hook(Plugin::Events::GEM_AFTER_INSTALL, spec_install)`——每个实际安装的 spec 触发一次；`:187` 是 `before-install`。
- `bundler-4.0.24/lib/bundler/installer.rb:16-19`：`before-install-all` / `after-install-all` 包裹整轮安装。锁文件在安装后由 `definition.to_lock` 写，`Bundle complete!` 由 `cli/install.rb` 在 installer 返回后打印，因此 hook 抛异常时两者都不出现（本轮实测参考 stderr 为 `--- ERROR REPORT TEMPLATE` + `RuntimeError: boom`，stdout 停在 `Resolving dependencies...`）。
- 2.7.2 同结构（`parallel_installer.rb` 同位置的 `Plugin.hook`）。

**实现**：

1. `src/celerite/cli/commands_install.cr`：`PluginHooks.call(..., "after-install")` 块整体前移到 `if summary` 与 `unless rest.includes?("--no-lock") … Lockfile.write` 之前（代码注释记录参考顺序）；失败仍一行 `Plugin hook after-install failed: <msg>` + `return 1`，`load_failed` 同理。成功路径两处 hook 本就无输出，输出顺序不变。
2. `script/differential`：新增 `file-absent`（每行一个 project 相对路径，两侧都必须不存在；违例输出 `file-absent violated (<path>): ref_exists=<yes|no> cel_exists=<yes|no>`）与 `stderr-contains`（每行一个 needle，两侧 stderr 都须 `grep -Fq` 命中；命中即跳过该夹具的逐字 stderr 比较并打印 `stderr compared by contains only (declared normalization N10)`）；只有显式提供对应标记文件的夹具生效。
3. `fixtures/differential/harness-assert-selftest/`：`command` = `install`（无 Gemfile，两侧 exit 10）、`stderr-contains` = `Could not locate Gemfile`、`file-absent` = `Gemfile.lock`。
4. `fixtures/differential/plugin-hook-raise/`：`command` 两行（`plugin install boom_plugin --path ./boom_plugin`、`install`，末字节 LF）；根 `Gemfile` = `source "file:///@INDEX_DIR@"` + `gem "boom_plugin", path: "./boom_plugin"`；`extra/boom_plugin/plugins.rb` 声明 `API.command("boomprobe", …)` 与 `add_hook("after-install") { |_ctx| raise "boom" }`；`stderr-contains` = `boom`；`file-absent` = `Gemfile.lock`。用 path gem 而非 rubygems gem：真装 gem 时参考在 `do_install` 抛错前已进入安装，`Installing …` 行在崩溃路径上可能未刷出，stdout 无法稳定对齐；path gem 两侧都不打印安装行。
5. `docs/differential-normalization.md`：表内新增 N10 行，并在「What is *not* normalized」与新增小节记录两条通道与自测/负对照。

**证据（双 profile 差分 + spec）**：

- `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `src/celerite/cli/commands_install.cr:1089:43`、`:1153:20` 的 `Deprecated File.executable?` 警告）；`git diff --check` EXIT 0。
- `crystal spec spec/m7_plugin_hook_failure_spec.cr spec/m7_plugin_hooks_registration_spec.cr spec/m7_console_spec.cr spec/m7_cli_dispatch_spec.cr` → **27 examples, 0 failures**。hook 抛异常例新增断言：exit 1、stderr 含 `boom from plugin hook`、`Gemfile.lock` 不存在、stdout 不含 `Bundle complete!`。
- 差分 `plugin-hook-raise`：4.0.24 `PASS plugin-hook-raise (exit=1)`（1 passed, 0 failed, 0 skipped，EXIT 0）；2.7.2 同 PASS（1/0/0）。保留产物 4.0.24 `.d/I9YtAz`、2.7.2 `.d/AbP62v`：两侧 stdout 均三行（`Resolving dependencies...` / `Installed plugin boom_plugin` / `Resolving dependencies...`）逐字相同；两侧 `project/Gemfile.lock` 均不存在；我方 stderr 仅 `Plugin hook after-install failed: boom`，参考 stderr 为 `RuntimeError: boom` 错误报告；两侧索引均含 `boomprobe: "boom_plugin"`、`after-install:`、`- "boom_plugin"`。
- 自测夹具：4.0.24 与 2.7.2 均 `PASS harness-assert-selftest (exit=10)`（1/0/0），输出含 N10 注记。负对照（现场改标记后恢复，文件保持 LF 无 BOM）：`stderr-contains` 追加 `definitely-not-in-stderr` → FAIL 且 `stderr-contains differs: needle=definitely-not-in-stderr`（exit 1）；在 `extra/` 放 `probe-marker.txt` 并把该路径写进 `file-absent` → FAIL 且 `file-absent violated (probe-marker.txt): ref_exists=yes cel_exists=yes`（exit 1）。
- 回归差分（双 profile 各 6 个）：`plugin-install`、`plugin-uninstall`、`install-fresh`、`tree-command`、`console-group`、`plugin-install-hooks` 全部 PASS（4.0.24 6/0/0；2.7.2 6/0/0，其中 `tree-command` 两侧 exit=15）。

**已声明差异 / 未验证**：

- 参考 `after-install` 是**每个实际安装的 spec 触发一次**（parallel installer 的 `do_install` 内），我方是整轮安装完成后触发一次；单插件单 gem 场景可观察面一致，多 gem 场景下「每 gem 一次」的粒度与顺序未实现（未验证；M7(6) task-11 已改为逐 spec 触发并新增 `plugin-hook-per-gem` 夹具，见文末 2026-11-19 节）。
- hook 抛异常时 stderr 不逐字一致：参考打印完整 `--- ERROR REPORT TEMPLATE`（含机器路径），我方一行 `Plugin hook after-install failed: boom`；因此该夹具用 `stderr-contains`（N10）只比较关键词，stdout / exit / 项目树仍是精确比较，且归一化只对被显式标记的夹具生效。
- 若将来要断言「hook 崩溃时两侧 stdout 逐字一致」且使用 rubygems gem，需要参考的 `Installing …` 行在崩溃路径稳定刷出；本轮以 path gem 绕开，rubygems gem 场景未验证。
- 全量 `crystal spec` 与全量差分未重跑（沿用既有记录）。

## 2026-11-19（M7(6) task-9：`plugin uninstall` 之后的 hook 收口）

**范围**：收口上文「`plugin uninstall` 的 hooks 清理只有实现、无专例/夹具」。用双 profile oracle 走 a→g 七步（装插件 → 内部 `install` → 卸载 → 再 `install` → `plugin list` → 重装 → 再 `install`），确认卸载后①索引 hooks 段不再列该插件、②内部 `install` 不再触发 hook、③重装后恢复；新增差分夹具 `plugin-hook-uninstall` 与 `spec/m7_plugin_uninstall_hooks_spec.cr` 4 例。**本轮未改 src**：`write_plugin_index` 的清理逻辑经核对已与参考一致，只补证据。

**参考锚点**：

- `bundler-4.0.24/lib/bundler/plugin/index.rb:77-87`：`unregister_plugin` 遍历 `@hooks`，`names.delete(name)` 后 `@hooks.delete(hook) if names.empty?`——卸载即从所有事件下移除，事件本身也随之消失。
- `bundler-4.0.24/lib/bundler/plugin/index.rb:54-74`：`register_plugin` 把 `@hooks_by_event.keys` 写回 `@hooks[event] << name` 并 `uniq!`——重装后事件与插件重新登记。
- `bundler-4.0.24/lib/bundler/plugin.rb:228-240`：hook 执行受 `Bundler.settings[:plugins]` 与 `index.hook_plugins(event)` 双重门控，索引里没有该插件即不加载、不调用。

**参考 oracle（两侧独立 HOME/GEM_HOME/BUNDLE_PATH，同一 Gemfile `source "file://<fixtures/gem-index>"` + `gem "json_pure"`）**：

| 步骤 | 参考 exit | 参考 stdout | 参考 index 字节 | 参考 `hook-log` 行数 |
| --- | --- | --- | --- | --- |
| a `plugin install hook_plugin --path ./hook_plugin` | 0 | `Resolving dependencies...` + `Installed plugin hook_plugin` | 322（含 `hookprobe: "hook_plugin"`、`after-install:`、`- "hook_plugin"`、load_paths/plugin_paths） | 0（文件不存在） |
| b `install` | 0 | `Bundle complete! 1 Gemfile dependency, 1 gem now installed.` + `Bundled gems are installed into ...` | 322 | 2 |
| c `plugin uninstall hook_plugin` | 0 | `Uninstalled plugin hook_plugin` | 62（commands/hooks/load_paths/plugin_paths/sources 全空骨架） | 2 |
| d `install` | 0 | 仅 `Bundle complete!`/`installed into`，无 hook 痕迹 | 62 | 2（不增） |
| e `plugin list` | 0 | `No plugins installed` | 62 | 2 |
| f `plugin install hook_plugin --path ./hook_plugin` | 0 | `Installed plugin hook_plugin` | 322 | 2 |
| g `install` | 0 | `Bundle complete! ...` | 322 | 4 |

2.7.2 同形：索引 320 字节（CRLF 差 2），b/g 的 stdout 为 `2 gems now installed`；其余步骤逐行一致。两侧 `hook-log` 内容均只有 `after-install` 行。

**实现与夹具**：

1. `src/celerite/cli/commands_surface.cr` 的 `write_plugin_index`（约 L1900-1913）：hooks 段遍历 `index["hooks"]` 的 `as_h`，按 `removed` 过滤数组内插件名，`next if owners.empty?` 删空事件——与 `index.rb:77-87` 一致，本轮只核对不改动。
2. `fixtures/differential/plugin-hook-uninstall/`：`command` 7 行（`plugin install hook_plugin --path ./hook_plugin` / `install` / `plugin uninstall hook_plugin` / `install` / `plugin list` / 重装 / `plugin list`，末字节 LF）；根 `Gemfile` 用 `@INDEX_DIR@` 占位；`extra/hook_plugin/plugins.rb` 的 hook 用 sentinel 区分路径——若 `hook-log` 与 `Gemfile.lock` 同时存在（即「卸载后仍触发了 hook」），写 `hook-after-uninstall`（内容 `hook ran after uninstall`），否则向 `hook-log` 追加 `after-install`。`file-absent` = `hook-after-uninstall`（21 字节：20 字符 + LF）；`file-contains` 三行（91 字节）：`.bundle/plugin/index⇥after-install`、`.bundle/plugin/index⇥hook_plugin`、`hook-log⇥after-install`。
3. `spec/m7_plugin_uninstall_hooks_spec.cr` 4 例：①卸载后索引 hooks 段为空且不再含 `hookprobe`；②卸载后 `install` 不追加 hook 行（行数保持 1）且 stdout 仍含 `Bundle complete!`；③重装后 hook 恢复（行数 1→2）；④`plugin list` 卸载后 `No plugins installed`、重装后含 `hook_plugin`。

**证据**：

- 差分 `plugin-hook-uninstall`：4.0.24 `PASS plugin-hook-uninstall (exit=0)`（1 passed, 0 failed, 0 skipped，EXIT 0）；2.7.2 同 PASS（1/0/0，EXIT 0）。`KEEP_DIFFERENTIAL=1` 保留产物 `.d/fDXzKj`（及 2.7.2 的 `bKcqqh`/`FW3u1T`/`zrtEm8`）：两侧 `project/hook-after-uninstall` 均不存在；`hook-log` 参考 30 字节/2 行、我方 15 字节/1 行（粒度差异见下）；两侧索引均含 `after-install`/`hook_plugin`（参考 338 字节、我方 326 字节，差 12 = CRLF）。
- 负对照：把 `command` 改成删掉 uninstall 三步的 4 行版本并临时复制为 `plugin-hook-uninstall-neg` → `FAIL ... file-absent violated (hook-after-uninstall): ref_exists=yes cel_exists=yes`，EXIT 1；保留产物 `.d/oLTXor` 两侧 sentinel 均存在，证明该通道确实能抓到「卸载后仍触发」。
- `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`git diff --check` EXIT 0。
- spec：`crystal spec spec/m7_plugin_uninstall_hooks_spec.cr spec/m7_plugin_hooks_registration_spec.cr spec/m7_plugin_hook_failure_spec.cr spec/m7_console_spec.cr spec/m7_cli_dispatch_spec.cr` → **31 examples, 0 failures**。
- 回归差分（双 profile 各 6 个）：`plugin-hook-uninstall`、`plugin-install`、`plugin-uninstall`、`plugin-install-hooks`、`plugin-hook-raise`、`install-fresh` 全 PASS（4.0.24 6/0/0 EXIT 0；2.7.2 6/0/0 EXIT 0，`plugin-hook-raise` 打印 N10 注记）。

**已声明差异 / 未验证**：

- 触发次数：差分环境下观察到参考在一次 `install` 内触发 **2 次**（两 profile 一致）；次数随本次实际安装的 spec 数变化——同步骤手工 fresh install 实测 3 行/45 字节，warm install（依赖已满足）仅 1 行。重复机制未定位（`Plugin.hook(GEM_AFTER_INSTALL)` 仅 `parallel_installer.rb:217` 一处），我方整轮固定 1 次，粒度差异仍未收口。夹具因此只断言行数「不增/增加」与 `hook-log` 的存在性，不比较行数与内容；我方次数由 spec 例②③固定。
- 项目树内容差异被 harness 的 `diff -r --brief | grep -v "differ$"` 过滤，`hook-log` 行内容只靠 `file-contains` 命中，不做逐字比较（N10 同源的已知限制）。
- 未覆盖：`plugin uninstall` 的 `--version`/`--local` 变体、手工损坏索引后的清理、卸载 git 源插件时的 hooks 清理（均未验证）。
- 全量 `crystal spec` 与全量差分未重跑（沿用既有记录）。

## 2026-11-19（M7(6) task-11：`after-install` 按安装 spec 逐个触发）

**范围**：收口上文「参考每 spec 触发一次、我方整轮一次」的粒度差异。用双 profile oracle 定位参考语义，把 `install` 的 hook 调用改成遍历本次安装集（running Bundler 的伪 spec 最先），并把 spec 身份通过 bridge 载荷交给 hook（`ctx.name`）。新增差分夹具 `plugin-hook-per-gem` 与 `spec/m7_plugin_hook_per_gem_spec.cr` 4 例。

**参考锚点**：

- `bundler-4.0.24/lib/bundler/installer/parallel_installer.rb:205-219`：`do_install(spec_install, worker_num)` 在 `install_from_spec` 之后**无条件**调用 `Plugin.hook(Plugin::Events::GEM_AFTER_INSTALL, spec_install)`——hook 与「是否本次新装」无关，已安装但仍在安装集里的 spec 也会触发。
- 同文件 `:8-59`：`SpecInstallation` 暴露 `:name`/`:full_name`/`:state` 等；hook 的第二实参就是它，块里读 `ctx.name`。
- `bundler-4.0.24/lib/bundler/plugin.rb:228-240`：`Plugin.hook` 先对索引里登记的插件逐个 `load_plugin`，再 `@hooks_by_event[event].each { |blk| blk.call(*args, &arg_blk) }`，不 rescue（raise 直接冒泡）。
- `bundler-4.0.24/lib/bundler/installer.rb:16-19` 另有整轮聚合事件 `GEM_BEFORE_INSTALL_ALL`/`GEM_AFTER_INSTALL_ALL`（实参 `definition.dependencies`），本轮不实现。

**参考 oracle（`.d/oracle11b.sh`，每场景独立 HOME/GEM_HOME/BUNDLE_PATH/BUNDLE_USER_HOME；hook 记录 `after-install:<name> state=<state> oid=<object_id> blocks=<size>`）**：

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| P：两个 path gem `alpha`/`beta`，fresh `install` | exit 0，`Bundle complete! 2 Gemfile dependencies, 2 gems now installed.`，hook 3 行：`bundler`/`alpha`/`beta`，blocks=1 | exit 0，`3 gems now installed`（计数含 running Bundler），hook 3 行同序 |
| P：再跑一次 `install`（无变化） | exit 0，hook 又 3 行（新 oid） | exit 0，hook 又 3 行 |
| G：`thor`+`racc`（file:// 索引），fresh / 再跑 | 各 3 行 `bundler`/`thor`/`racc` | 各 3 行同序 |
| G：新增 `json_pure` 后 `install` | 新增 8 行：首行 `bundler` 为 `blocks=1`，其余 7 行 `blocks=2`（同进程重复注册 block），故除该首个 `bundler` 外每 spec 触发 2 次 | 新增 10 行，blocks 在 2/3 间跳 |
| R：hook `raise "boom"`（thor+racc） | **exit 1、无 `Gemfile.lock`、gems 目录为空**（首个 hook 即 `bundler`，装任何 gem 之前中止） | exit 1、无 lock，但 thor/racc 已装上（2.7.2 串行安装，装完才触发） |

结论：安装集 = running Bundler 的 spec（始终在集合内）+ 本次解析出的全部 spec；hook 每轮触发，与是否新装无关。**触发顺序**：我方固定先发 `bundler` 伪 spec；参考的 hook 在并行安装 worker 中触发，顺序不保证——`.d/oracle11b-4.0.24/proj-path/hook-log` 第 4-6 行重跑记录为 `alpha`/`beta`/`bundler`，故夹具与 spec 均不断言参考侧顺序。

**实现**：

1. `src/celerite/cli/commands_install.cr`（约 L555-600）：`PluginHooks.enabled?` 为真时构造 `hook_specs`（先 `{"bundler", "bundler-<profile 版本>"}`，再 `specs` 的 `{name, full_name}`），逐个调用 `PluginHooks.call(bridge, definition, "after-install", name, full_name)`；位置仍 G2：在 `if summary` 与 `Lockfile.write` 之前。首个 `load_failed`/`hook_failed` 仍只打印一行并 `return 1`（`Plugin hook after-install failed: <msg>`），后续 spec 不再触发。
2. `assets/bridge/server.rb`：`op_exec_plugin_hook` 的 context 改为 `PluginHookSpec.new(spec_name, spec_full_name)`（新增类，`attr_reader :name, :full_name`，`state` 恒 `:installed`）；未带 `spec_name` 时退回 `payload["context"] || {}`（旧调用方兼容）。
3. `src/celerite/plugin_hooks.cr` + `src/celerite/bridge/client.cr`：`call`/`exec_plugin_hook` 增可选 `spec_name`/`spec_full_name`，载荷字段 `spec_name`/`spec_full_name`。
4. `fixtures/differential/plugin-hook-per-gem/`：`command` 2 行（`plugin install hook_plugin --path ./hook_plugin` / `install`，56 字节、末字节 LF）；根 `Gemfile` 85 字节（`gem "alpha"/"beta"/"gamma", path: "./<name>"`，末字节 LF）；`extra/hook_plugin/plugins.rb` 558 字节，hook 按 spec 名写**独立文件** `hook-log-<name>`（内容 `after-install:<name>\n`）——参考在安装 worker 线程里并发触发 hook，写同一个文件会丢行/插空行（见下），按 spec 分文件才可稳定断言；`extra/{alpha,beta,gamma}` 各含 gemspec + `lib/<name>.rb`；`file-contains` 103 字节三行（tab 分隔）：`hook-log-alpha⇥after-install:alpha`、`hook-log-beta⇥after-install:beta`、`hook-log-gamma⇥after-install:gamma`。
5. `spec/m7_plugin_hook_per_gem_spec.cr` 4 例：①三 path gem fresh install → `hook-log` 恰 4 行且 `bundler` 在首位、其余按 alpha/beta/gamma；②本地索引 `json_pure`+`thor` 上重复 install → hook 再次全量触发（3→6 行）；③首个 hook raise → exit 1、stderr `Plugin hook after-install failed: boom per-gem`、无 `Gemfile.lock`；④bridge 载荷携带 spec 名（`after-install:bundler`/`alpha` 可见且行前缀统一）。`spec/m7_plugin_uninstall_hooks_spec.cr` 的行数断言同步为逐 spec 语义（单 gem + bundler = 2 行）。
6. 文档：本新节 + roadmap 注记（复选框保持 `[ ]`）。

**证据**：

- 差分 `plugin-hook-per-gem`：4.0.24 `PASS plugin-hook-per-gem (exit=0)`（1 passed, 0 failed, 0 skipped，EXIT 0）；2.7.2 同 PASS（1/0/0，EXIT 0）。`KEEP_DIFFERENTIAL=1` 保留产物 `.d/q13dXK`（4.0.24；2.7.2 同形）：两侧 `project/` 均生成 `hook-log-alpha` 21 字节、`hook-log-beta` 20 字节、`hook-log-bundler` 23 字节、`hook-log-gamma` 21 字节（字节数含 CRLF），内容逐字一致 `after-install:<name>`；索引参考 338 字节、我方 326 字节（差 12 = CRLF）。
- 稳定性：单夹具在 4.0.24 连跑 4 次、2.7.2 连跑 8 次全 PASS；8 夹具批量在 4.0.24 与 2.7.2 各连跑 2 次均 `8 passed, 0 failed`（合计 4 次批量、每 profile 2 次）。
- 并发写入：参考的 hook 在 `parallel_installer.rb:173-184` 的 worker 线程里调用，多个 spec 同时激活时对同一文件的追加会互相覆盖——首版夹具用单一 `hook-log`，2.7.2 上约 40% 的运行出现丢行（实测一次 `hook-log` 为 `bundler`/`beta`/空行/`gamma`，`alpha` 整行丢失），因此夹具改为每个 spec 写独立文件。钩子顺序在参考侧同样不确定（4.0.24 与 2.7.2 都会乱序），我方按解析顺序串行触发，顺序差异不在断言范围。
- spec：`crystal spec spec/m7_plugin_hook_per_gem_spec.cr` → **4 examples, 0 failures**；与 `spec/m7_plugin_hook_failure_spec.cr spec/m7_plugin_hooks_registration_spec.cr spec/m7_plugin_uninstall_hooks_spec.cr spec/m7_console_spec.cr spec/m7_cli_dispatch_spec.cr` 合跑 → **35 examples, 0 failures**。
- `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`git diff --check` EXIT 0。

**已声明差异 / 未验证**：

- 参考在 G-add 路径会把 `plugins.rb` 在同一进程里加载两次，导致同一 block 注册两遍、每 spec 触发两次（blocks=2）；我方每次 install 只加载一次，hook-log 行数因此是参考的一半（`plugin-hook-uninstall` 旧夹具同源）。夹具只断言「按 spec 名字命中」与行数递增，不比较行数绝对值。
- `bundler` 伪 spec 只复刻 `name`（`full_name` 用 `<profile 版本>` 拼），`state` 恒 `:installed`；参考对象上的 `spec`/依赖边等 API 不复刻。
- `GEM_AFTER_INSTALL_ALL`（整轮聚合事件）未实现（未验证）。
- 缺失插件的 stderr 警告我方每命令打印一次（参考按每次 `Plugin.hook` 重复打印），为保持既有 pinned stderr 未对齐。
- path gem 的重复 install 在我方仍需访问索引（`Fetching gem metadata from https://rubygems.org/` 后 SSL 失败，exit 17），与本轮改动无关；spec 例②因此改用本地索引 gem。该缺口未修（未验证）。
- 全量 `crystal spec` 与全量差分未重跑（沿用既有记录）。

## 2026-11-19（M7(6) task-15：未定义 hook 事件时 `plugin install` 报错退出）

**范围**：插件 `plugins.rb` 声明了 Bundler 未定义的事件（如 `post-install`）时，`plugin install <name> --path <dir>` 的退出码、stdout/stderr 文案，以及索引是否落盘。此前本实现静默 `exit 0`：探针 `assets/bridge/plugin_command.rb` 的 `add_hook` 调用发生在参考 `Bundler::Plugin.add_hook` 之外，未定义事件不抛错，声明被丢弃后安装照常成功。

**参考 oracle（`.d/oracle15.sh`，每 profile 每 case 独立沙箱 `.d/oracle15-<ver>-<case>`，HOME/GEM_HOME/BUNDLE_USER_HOME/BUNDLE_PATH/TMP/TEMP/TMPDIR 全隔离）**：

| case | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `plugin install bad --path ./bad`（`plugins.rb` 只有 `add_hook("post-install")`） | exit **29**；stdout 仅 `Resolving dependencies...`；stderr 两行：`Failed to install plugin \`bad\`, due to Bundler::Plugin::MalformattedPlugin` / `(ArgumentError: Event 'post-install' not defined in Bundler::Plugin::Events)`；无 `Gemfile.lock`、无 `.bundle/plugin/index`、**源目录 `./bad` 被删除** | 逐字、逐码相同（29 / 两行 / 无 lock / 无 index / 源目录被删） |
| 对照：`add_hook("after-install")` | exit 0；stdout `Resolving dependencies...` + `Installed plugin bad`；stderr 空；index 存在；源目录保留 | 同 |

参考锚点：`bundler-4.0.24/lib/bundler/plugin.rb:215-217` 在事件名校验失败时 `raise ArgumentError, "Event '<event>' not defined in Bundler::Plugin::Events"`；`lib/bundler/plugin.rb:292-298`（`save_plugin` 的 `rescue PluginError`）把它包成**单条**消息 `Failed to install plugin \`<name>\`, due to <class> (<cause>)`；`lib/bundler/errors.rb:49` 的 `PluginError < BundlerError; status_code(29)` 给出 exit 29；消息的换行不是参考硬编码的，而是 `lib/bundler/friendly_errors.rb:31-36` 的 `ui.error message, wrap: true` 经 `lib/bundler/ui/shell.rb:167-171` 的 thor `word_wrap(text, terminal_width)` 折行产生（宽度见 task-17 节）。两个 profile 文案与退出码一致，故不做 `deferred-<version>` 分治。

**实现**：

1. `src/celerite/plugin_commands.cr`：`declared` 的返回类型改为 `alias Declared = NamedTuple(commands: Array(String), hooks: Array(String), error: String?)`；探针首行 JSON 带 `error` 键时把它透传（`commands`/`hooks` 为空数组），否则沿用原解析。保留 `declared_commands` 作为 `declared(...)[:commands]` 委托（`spec/m7_plugin_hooks_registration_spec.cr:145-147` 仍用 `[:commands]`/`[:hooks]`）。
2. `src/celerite/cli/commands_surface.cr` 本地 `--path` 分支：`declared` 之后若 `[:error]` 非空，打印两行（`` Failed to install plugin `#{name}`, due to Bundler::Plugin::MalformattedPlugin `` + `(#{error})`）并 `return 29`；`Dir.mkdir_p(index_dir)` 由取索引前移到 `File.write(index_path, yaml)` 前，失败路径因此不留 `.bundle/plugin`。
3. 同文件远端/`--source` 分支：`index_path` 提前定义；error 检查放在 `declared` 之后；原「写空索引骨架 + 解析 index + 取三张 map」整块移到 error 检查之后，避免失败时先落骨架。
4. `fixtures/differential/plugin-install-bad-event/`：`command` 单行 `plugin install bad --path ../bundle/plugin-src`；根 `Gemfile`（`source "file:///@INDEX_DIR@"` + `gem "json_pure"`）；`bundle-preset/plugin-src/{bad.gemspec,plugins.rb,lib/bad.rb}`；`file-absent` = `.bundle/plugin/index`。**源目录放 `bundle-preset` 而非 `extra/`**：harness 把 `bundle-preset` 复制到 `$sandbox/bundle`（两侧各自的 `BUNDLE_PATH`），不在被比较的 `project/` 树内；参考失败会删除源目录，若放 `project/` 内就会出现 `Only in cel/project: bad` 的树差异而误判。
5. `spec/m7_plugin_bad_event_spec.cr` 3 例：①`PluginCommands.declared` 透传 `ArgumentError: Event 'post-install' not defined in Bundler::Plugin::Events`；②`plugin install` exit 29、stdout 只有 `Resolving dependencies...`、stderr 恰两行且首行逐字、无 index、无 `Gemfile.lock`；③合法 `after-install` 插件仍 exit 0、索引含 `badeventprobe: "good"` 与 `after-install:`。

**证据**：

- 差分 `plugin-install-bad-event`：4.0.24 `PASS plugin-install-bad-event (exit=29)`（1 passed, 0 failed, 0 skipped，EXIT 0）；`BUNDLER_REF_VERSION=2.7.2` 同 PASS（1/0/0，EXIT 0）。
- `KEEP_DIFFERENTIAL=1` 保留产物 `.d/LPWg60`：两侧 `project/` 都只有 `Gemfile`；参考侧 `bundle/plugin-src` 已被删除（源目录副作用），我方保留（见已声明差异）。
- `crystal spec`（新 spec + `m7_plugin_hook_per_gem_spec.cr` + `m7_plugin_hook_failure_spec.cr` + `m7_plugin_hooks_registration_spec.cr` + `m7_plugin_uninstall_hooks_spec.cr` + `m7_console_spec.cr` + `m7_cli_dispatch_spec.cr`）→ **38 examples, 0 failures, 0 errors, 0 pending**。
- `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告：`src/celerite/cli/commands_install.cr:1112:43`、`:1176:20`）；`git diff --check` EXIT 0。

**已声明差异 / 未验证**：

- 参考在注册失败时会删除 `--path` 源目录（`./bad`）；我方按 lead 裁断不做破坏性删除，保留源目录。夹具把源目录放在 `bundle-preset`（比较树之外）以免把该差异写成树差异，差异本身未复刻。
- 远端/`--source` 分支的同类失败行为在 task-17 用**规范形式**的 `file:///…` 源验证（exit 29、文案逐字一致，见下节）；非规范形式 `file://C:/…`（少一条斜杠）我方仍报 `Could not find gem` exit 7，参考可解析——该 URL 归一化差异未在本轮修复（未验证，见 task-17 节）。
- `--local_git` 插件源与「空 `plugin uninstall`」切片不在本轮范围（未做）。
- 全量 `crystal spec` 与全量差分未重跑（沿用既有记录）。

## 2026-11-19（M7(6) task-17：`plugin install` 失败消息的折行宽度与锚点订正）

**范围**：把 task-15 的 malformed-plugin 失败消息从「我方硬编码两行」改为参考语义——**单条消息 + 按终端宽度折行**；顺带订正上一节把折行归因于 `cli/plugin.rb` 的错误锚点，并核实远端 `--source` 的同类失败路径。本地 `--path`、远端缺 `plugins.rb`、远端 `--source` 三条分支共用同一输出助手。

**参考 oracle（`.d/oracle17.sh`；每 profile × 插件名 × 环境变量独立沙箱 `.d/oracle17/<ver>-<name>-<env>`，HOME/GEM_HOME/BUNDLE_USER_HOME/BUNDLE_PATH/TMP/TEMP/TMPDIR 全隔离）**：

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `bad`（默认） | exit 29；stderr 154B 两行：L1 len=74 ``Failed to install plugin `bad`, due to Bundler::Plugin::MalformattedPlugin``、L2 len=76 `(ArgumentError: Event 'post-install' not defined in Bundler::Plugin::Events)` | 逐字相同（含字节数） |
| `bad` + `COLUMNS=40` / `COLUMNS=120` | 与默认**完全一致**（154B 两行） | 同 |
| `bad` + `THOR_COLUMNS=40` | 156B 四行：38/35/40/35 | 同 |
| `bad` + `THOR_COLUMNS=120` | 154B 两行：115/35 | 同 |
| `candle_plug`（默认） | 163B 三行：46/76/35 | 同 |
| `candle_plug` + `THOR_COLUMNS=40/120` | 165B 五行（39/6/35/40/35）/ 162B 两行（119/39） | 同 |

宽度来源：`bundler-4.0.24/lib/bundler/ui/shell.rb:167-171` 的 `word_wrap(text, line_width = Thor::Terminal.terminal_width)`，规则为 `line.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip`（长单词不硬切）；`vendor/thor/lib/thor/shell/terminal.rb:4-18` 的 `terminal_width` 只读 `THOR_COLUMNS`（`to_i`，<10 忽略），非 unix（Windows `x64-mingw-ucrt`）恒 80。**`COLUMNS` 完全无效**，参考在 `friendly_errors.rb:31-36` 以 `wrap: true` 触发折行。

**实现**：

1. `src/celerite/cli/commands_surface.cr` 新增私有助手 `put_plugin_install_failure(stderr, name, cause)`：拼单串 ``Failed to install plugin `#{name}`, due to Bundler::Plugin::MalformattedPlugin (#{cause})`` 后 `stderr.puts Commands.word_wrap(message, CLI.terminal_width)`。`Commands.word_wrap`（`src/celerite/cli/commands.cr:1068-1078`）与 `CLI.terminal_width`（`src/celerite/cli.cr:43-49`，`THOR_COLUMNS` ≥10 优先，否则 80）是既有实现，未新增第二套折行逻辑。
2. 三条分支改为调用该助手：本地 `--path`（原 `.cr:1490-1491`）、远端缺 `plugins.rb`（原 `:1734-1735`，cause 为 `plugins.rb was not found in the plugin.`）、远端 `--source`（原 `:1754-1755`）。
3. 新夹具 `fixtures/differential/plugin-install-bad-event-long/`：`command` 单行 `plugin install candle_plug --path ../bundle/plugin-src`（55B，末字节 LF）；根 `Gemfile`（46B）；`bundle-preset/plugin-src/{candle_plug.gemspec 248B, plugins.rb 75B, lib/candle_plug.rb 42B}`；`file-absent` = `.bundle/plugin/index`（21B）。与 task-15 的短名夹具并存，短名夹具断言未改。
4. `spec/m7_plugin_bad_event_spec.cr` 增第 4 例：`candle_plug` 的 stderr 恰为三行 `Failed to install plugin \`candle_plug\`, due to` / `Bundler::Plugin::MalformattedPlugin (ArgumentError: Event 'post-install' not` / `defined in Bundler::Plugin::Events)`。

**证据**：

- 我方 oracle `.d/oracle17c.sh`（同沙箱隔离、跑 `bin/celerite.exe`）：`bad` 默认 2 行 74/76；`THOR_COLUMNS=40` 4 行 38/35/40/35；`THOR_COLUMNS=120` 2 行 115/35；`candle_plug` 默认 3 行 46/76/35、`THOR_COLUMNS=40` 5 行 39/6/35/40/35、`THOR_COLUMNS=120` 2 行 119/39 —— 行文本与参考逐字一致（字节差仅为参考的 CRLF：如 `bad` 参考 154B vs 我方 152B；`candle_plug` 163B vs 160B）。
- 差分 `plugin-install-bad-event-long`：4.0.24 `PASS (exit=29)`、`BUNDLER_REF_VERSION=2.7.2` 同 PASS（各 1 passed, 0 failed, 0 skipped，EXIT 0）。
- 回归差分双 profile（9 夹具）：`plugin-install-bad-event-long`、`plugin-install-bad-event`、`plugin-install`、`plugin-install-hooks`、`plugin-hook-raise`、`plugin-hook-per-gem`、`plugin-hook-uninstall`、`plugin-install-source`、`install-fresh` → 4.0.24 与 2.7.2 均 `9 passed, 0 failed, 0 skipped`。
- `crystal spec`（`m7_plugin_bad_event_spec` + `m7_plugin_hook_per_gem_spec` + `m7_plugin_hooks_registration_spec` + `m7_plugin_hook_failure_spec` + `m7_plugin_uninstall_hooks_spec` + `m7_console_spec` + `m7_cli_dispatch_spec`）→ **39 examples, 0 failures, 0 errors, 0 pending**。
- `crystal tool format --check src spec` EXIT 0；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告：`src/celerite/cli/commands_install.cr:1112:43`、`:1176:20`）。

**已声明差异 / 未验证**：

- 上节（task-15）把折行归因到 `cli/plugin.rb` 的锚点已订正为本节的 `friendly_errors.rb:31-36` + `ui/shell.rb:167-171`，exit 29 来自 `errors.rb:49`。
- 远端 `--source` + bad-event 用**规范形式** `file:///C:/…` 验证：我方 exit 29、stdout 与参考同为 `Fetching source index from …` / `Resolving dependencies...` / `Fetching bad 0.1.0` / `Installing bad 0.1.0`、stderr 同两行。但非规范形式 `file://C:/…`（`file://` 后直接跟盘符）我方解析失败并报 `Could not find gem 'bad' in rubygems repository`（exit 7），参考可正常解析（exit 29）——**该 file URL 归一化差异未修复、未验证根因**，不入本轮夹具。
- 差分 harness 不设置 `THOR_COLUMNS`，故夹具只覆盖默认 80 列；`THOR_COLUMNS=40/120` 的折行仅由 `.d/oracle17c.sh` 与参考对照（未入 CI 断言）。
- 全量 `crystal spec` 与全量差分未重跑（沿用既有记录）。

## 2026-11-19（M7(6) task-19：非规范 `file://C:/…` file URL 归一化对齐）

**范围**：`plugin install <gem> --source file://C:/…`（`file://` 后直接跟盘符）。修复前我方把它折成 `/C/Users/…` → `C:\C\Users\…`，报 `Could not find gem '<name>' in rubygems repository` exit 7；参考 4.0.24 / 2.7.2 均可解析（本机 exit 0）。规范形式 `file:///C:/…` 不回归。本轮统一 `compact_index/cache.cr` 与 `downloader.cr` 的 file URL 归一，HTTP/mirror/凭据路径未动。

**oracle（Ruby 4.0.6 URI + Bundler CLI，本机仅 C: 盘）**：

| 输入 | Ruby `URI#path` | 参考取用路径（`correct_for_windows_path`） | 4.0.24 CLI | 2.7.2 CLI |
| --- | --- | --- | --- | --- |
| `file://C:/x` | `/x`（host `C`） | `/x` | exit 0 | exit 0 |
| `file:///C:/x` | `/C:/x` | `C:/x` | exit 0 | exit 0 |
| `file:/C:/x` | 归一为 `file:///C:/x` | `C:/x` | exit 0 | exit 0 |
| `file://host/x` | `/x`（host 被忽略） | `/x` | exit 0 | exit 0 |
| `file:////server/share` | `//server/share` | `//server/share`（UNC） | 未实测 | 未实测 |
| `file:C:/x` | `nil` | `nil` | exit 1 `NoMethodError` | exit 1 `NoMethodError` |

要点：参考**完全忽略 URI host，只用 path**；盘符前导斜杠按 `Gem::Util.correct_for_windows_path` 去掉（仅 `/`+字母+`:` 三个字符）；`//` 前缀保留（UNC 语义）；`file://C:/x` 丢弃盘符后为 `/x`，只有当前盘恰为源盘时才命中，stdout 亦显示丢冒号的 `file://C/Users/…`。`file:C:/x`（opaque 形式）path 为 `nil`，两版参考均以 `NoMethodError: undefined method '[]' for nil` 崩在 `rubygems/util.rb:90`，属参考自身缺陷。

**代码锚点**：

- `.upstream-specs/v4.0.24/bundler/lib/bundler/source/rubygems.rb:369-376`（remote 末尾补 `/` 后交 `Gem::URI`）；`uri_normalizer.rb:15-21`。
- `.upstream-specs/v4.0.24/bundler/lib/bundler/fetcher.rb:151-155`（拼 `…/Marshal.4.8/…gemspec.rz` 后 file scheme 走 `correct_for_windows_path(uri.path)`）；`:274-276`（file scheme 强制 Index fetcher）；`fetcher/index.rb:9`；`rubygems_integration.rb:360-366`（`fetch_path(remote.uri.to_s + name…gz)`）。
- 2.7.2（`.upstream-specs/v2.7.2/bundler` 目录为空，锚点取本机安装 gem）：`C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-2.7.2/lib/bundler/fetcher.rb:152-154`、`:261`；`rubygems_integration.rb:360-363`。
- RubyGems：`C:/Ruby40-x64/lib/ruby/4.0.0/rubygems/remote_fetcher.rb:164-176`、`:205-207`（`fetch_file` 直接读 `uri.path`）；`util.rb:89-95`（盘符前导斜杠剥离）。

**实现**：

1. 新增 `src/celerite/file_url.cr`：`Celerite::FileURL.local_path`（取 `URI#path`、忽略 host、反斜杠转 `/`、`/^\/([A-Za-z]:)/` 去盘符前导斜杠、保留 `//`），`Celerite::FileURL.directory`（先补末尾 `/` 再 `File.expand_path`，避免 Crystal 对裸 UNC 基址错误追加 cwd）。
2. `src/celerite/compact_index/cache.cr:604-612` `make_fetcher` 的 file 分支改为 `FileFetcher.new(FileURL.directory(remote))`，删除旧 host 折叠、`%r{^/{2,}}` 折叠与重复盘符正则。
3. `src/celerite/downloader.cr:193-199` 同用 `FileURL.directory(@remote)`；删除 L205-206 重复的 `root.sub(/^\/[A-Za-z]:\//)`。
4. `src/celerite.cr:22` 加 require。`Resolution#normalize_remote`（`src/celerite/resolution.cr:897-900`，仅锁 source 比对）未改。

**测试与夹具**：

- `spec/m7_file_url_spec.cr`：4 examples——六形式 `local_path` 矩阵、盘符前导斜杠边界（`/c:/tmp`、`/C:`、`/tmp/x`）、末尾分隔符/反斜杠；Windows 下 `directory`（`C:\x\`、`\\server\share\`）与 `Downloader` 从 `file://C:/…/fixtures/gem-index` 下载 `json_pure 2.8.1` 各 1 例。独立文件因跨形式矩阵与既有 downloader spec 关注点不同。
- `fixtures/differential/plugin-install-source-noncanonical/`：`command` 为 `install` / `plugin install candle_plug --source file://@PLUGIN_INDEX_DIR@` / `plugin list` / `candle x y`（末字节 LF）；`Gemfile` 仍用规范 `file:///@INDEX_DIR@`。harness 按夹具名取目录。

**证据**：

- 复现（修复前）：cel-noncan `file://C:/…` exit 7，stdout `Fetching source index from file://C/Users/…`，stderr 单条 `Could not find gem 'candle_plug' in rubygems repository` + URL + `or installed locally.`；参考 4.0.24/2.7.2 exit 0。修复后我方 exit 0，stdout 与参考逐字一致（含 `file://C/Users/…` 展示），cel-canon 仍 exit 0 且逐字不变。
- 差分：4.0.24 `plugin-install-source` + `plugin-install-source-noncanonical` → **2 passed, 0 failed, 0 skipped**，EXIT 0；`BUNDLER_REF_VERSION=2.7.2` 同 **2/0/0**，EXIT 0。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告，`commands_install.cr:1112:43`、`:1176:20`）；`crystal spec spec/m7_file_url_spec.cr spec/downloader_spec.cr spec/m7_plugin_commands_spec.cr` → 18 examples, 0 failures, 0 errors, 0 pending；`git diff --check` EXIT 0；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0。
- 全量 `crystal spec` 与全量差分本轮未重跑（沿用既有记录）。

**已声明差异 / 未验证**：

1. `file://C:/x` 的参考语义是“丢盘符、按当前盘解析”，仅当源盘 == 当前盘时可用；本机只有 C:，跨盘场景**未验证**。我方按参考实现，未自创“保留盘符”语义。
2. `file:////server/share` 的 `//` 在助手中保留，Crystal 下 `\\server\share\` 展开正确（`.d/t19_expand*.cr` 实测）；但本机无可达 UNC 共享，端到端**未实测**。
3. `file:C:/x`（opaque）参考 4.0.24/2.7.2 均 exit 1（`NoMethodError`），我方按 `C:/x` 接受（exit 0）。这是本轮之前就存在的分歧，未随本次改动引入，也未为对齐参考而人为制造崩溃——保留并在本节声明。
4. `file://host/x` 的 host 现被忽略（与参考一致）；旧实现会折成 `/host/x`，已删除。
5. `Resolution#normalize_remote` 仍是旧式 `lchop("file:").lstrip('/')` 展开，host/UNC 形式在锁 source 比对中的行为未随本轮变更（不在本任务范围）。

## 2026-11-19（M7(6) task-19 验收补记：全量 `crystal spec` 的本机限制）

本节记录本轮验收时全量 spec 的实际表现，**不作为通过证据**：全量 `crystal spec` 在本机跑不到 `Finished`，下面逐项写明现象、观测、归因与替代验证，凡未跑通者一律标未验证。

**现象**：本轮复跑全量 `crystal spec`（`spec/` 下 100 个 `*_spec.cr`）无法跑到 `Finished`——进程打印若干进度点后静默结束，EXIT 1，无 failures 摘要、无 `Finished in`、stderr 无异常文本。

**观测**（HEAD=`380d8d6`，串行、无并发 crystal 进程）：

- 无 `--verbose`：输出 131 字符进度行后静默结束（日志 1974 字节）。
- 两次 `--verbose`：分别停在 `M7(2) bundle add/remove switch surface` 的 `rejects --strict together with --optimistic (exit 15, period)` 之后，以及 `bundle list output formats` / `m7_outdated_naming_spec` 的样例处（日志 25668 与 95416 字节，均无摘要）。
- 分组每 25 个文件：0–24 组 178 examples / 3 failures / 0 errors 完成，25–49 组 150 examples / 1 failure / 1 pending 完成，50–74 组与 75–99 组均静默结束无摘要。

**归因（已排除本轮改动）**：`git worktree add C:/temp/celerite-pre19 a3ed3ec`（task-19 之前提交）复跑同样静默结束——全量跑到 `M7(2) bundle add/remove switch surface` 后中断，50–74 组同组中断。故与本轮 `file://C:/` 归一化改动无关，属既存环境/长跑缺陷，根因未定位。

**已定位的 4 个失败（均环境耦合，非产品缺陷）**：机器级 `~/.bundle/config` 含 `BUNDLE_PATH: "vendor/x"`，导致 `spec/config_spec.cr:97`、`spec/config_spec.cr:146`（`lines.size` 期望 1 得 2）、`spec/m7_deployment_path_spec.cr:105`（期望 `…/vendor/bundle` 得 `…/vendor/x`）；另有 `spec/m7_list_groups_plain_env_spec.cr:54` 在本轮一次分组运行中因 `celerite internal error: Unable to create directory: '<TEMP>\…\.bundle-test': 拒绝访问。` 失败（EXIT 1，疑似临时目录/AV 侧拒绝）。`config_spec.cr:97` 此前已登记为环境耦合。

**残留副作用**：被中断/终止的 spec 进程会继续占用 `%LOCALAPPDATA%\crystal\cache\crystal-run-spec.tmp.exe`，后续 `crystal spec` 在链接阶段报 `ld.exe: cannot open output file …: Permission denied`（`collect2.exe: error: ld returned 1 exit status`）；需先 `Stop-Process` 清理残留进程再跑。

**环境前置（本轮实测）**：`crystal` 需要 `C:\msys64\usr\bin` 在 `PATH`（否则宏内 `sh -c` 报 `系统找不到指定的文件`）；`script/differential` 必须用 `C:\msys64\usr\bin\bash.exe`（`PATH` 里默认 `bash` 是 WSL，`/c/...` 不识别，报 `ruby: command not found`）。

**本轮替代验证**：`crystal spec spec/m7_file_url_spec.cr` 5 examples 0 failures；0–24 与 25–49 两组共 328 examples 完成；差分 4.0.24 11 个夹具全 PASS，`plugin-install-source`/`plugin-install-source-noncanonical` 在 2.7.2 亦 PASS。

## 2026-11-19（M7(6) task-20：`plugin uninstall` 选项/空参语义与注册表清理对齐）

**范围**：只对齐 `bundle plugin uninstall` 的参数语义（含未声明选项、空参、`--all`）、按参考删除 `.bundle/plugin` 内 checkout，以及 commands/hooks/load_paths/plugin_paths/sources 的同步清理。`plugin install` 既有路径、自定义 source 成功路径与 M8 性能不在本轮。

**Oracle**（真实 CLI，4.0.24 与 2.7.2 逐字一致；隔离沙箱，项目内 `hook_plugin` 以 `plugin install hook_plugin --path ./hook_plugin` 预装）：

| 命令 | exit | stdout | stderr |
| --- | --- | --- | --- |
| `plugin uninstall` | 0 | 空 | `No plugins to uninstall. Specify at least 1 plugin to uninstall.` + `Use --all option to uninstall all the installed plugins.` |
| `plugin uninstall nope` | 0 | 空 | `Plugin nope is not installed `（尾部含空格） |
| `plugin uninstall hook_plugin --version 1.0` | 0 | `Uninstalled plugin hook_plugin` | `Plugin --version is not installed ` + `Plugin 1.0 is not installed ` |
| `plugin uninstall hook_plugin --local` | 0 | 同上 | `Plugin hook_plugin is not installed `（若已卸）/ `Plugin --local is not installed ` |
| `plugin uninstall --all`（无插件） | 0 | `No plugins installed` | 空 |

参考 `uninstall` 只声明 `--all`（`cli/plugin.rb:25-32`），Thor 把其余 token 当位置参数；因此 `--version`/`--local` 不是“解析后忽略”，而是被当作插件名逐个尝试卸载（`plugin.rb:55-77`）。git 源插件 oracle（`plugin install hook_plugin --git file:///c:/temp/t20git/repo`，4.0.24/2.7.2 同）：index 记录 `commands: hookprobe`、`hooks: after-install`、`plugin_paths: .bundle/plugin/bundler/gems/repo-<sha>`；`plugin uninstall hook_plugin` exit 0，stdout `Uninstalled plugin hook_plugin`，index 变为空骨架，`bundler/gems` 下 checkout 被删除、`cache/bundler/git/repo-<full sha>` 保留。

**参考锚点**：4.0.24 `bundler/lib/bundler/cli/plugin.rb:25-32`、`bundler/lib/bundler/plugin.rb:55-77`（空参两行错误、`--all` 取 `installed_plugins`、删除 checkout、`unregister_plugin`、逐名 info/error）；`bundler/lib/bundler/plugin/index.rb:78-88`（unregister：command 按 owner、sources 按 value、hooks 列表删名并删空事件、删 load_paths/plugin_paths）、`:169-171`（`installed_plugins` = `@plugin_paths.keys` 插入序）、`:192-196`（`installed_in_plugin_root?` = 路径以 `Plugin.root/` 起头）。2.7.2 安装在 `C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-2.7.2/lib/bundler/`：`plugin.rb:54-77`、`plugin/index.rb:78-88`、`:122`、`:145`，语义同上。

**实现**：
- `src/celerite/cli/commands_surface.cr:1547-1587`：`names` 改为 `rest[1..]` 中仅剔除 `--all`（不再丢弃 `--*`）；空参且无 `--all` 打印两行 stderr 并 return 0；目标列表取 `installed_plugins(index)`（`plugin_paths` 插入序）；逐个用实时 `installed` 列表判定，重名第二次报 not installed；命中时 `plugin_owned_path?` 为真则 `FileUtils.rm_rf`，随后打印 `Uninstalled plugin <name>`；仅在确有移除时重写 index（与参考“未 unregister 就不 save_index”一致）。
- `:1914-1937`：`installed_plugins` 重载接收已解析 index，读 `plugin_paths`；新增 `plugin_path_map`/`plugin_path`。
- `:1939-1943`：`plugin_owned_path?` 先统一 `\`→`/` 再比对 `plugin_tree_root/` 前缀，等价 `installed_in_plugin_root?`；`--path` 插件路径不在该根下，源目录保持不动。
- `:1947-1990`：`write_plugin_index` 的 `render` 增加 `by_value` 参数；`sources` 按 value（插件名）删除，修正原先误按 key 删除；load_paths/plugin_paths 仍按 key。

**测试与差分**：
- `spec/m7_plugin_uninstall_hooks_spec.cr` 新增 6 例：空参两行消息、未知插件尾空格消息、未声明 token 透传 + checkout 删除 + 骨架 index + 命令注销（exit 15）、`--all` 空输出、`--path` 源目录保留、重名不重复报 Uninstalled；该文件 10 examples 0 failures。
- 新增 `fixtures/differential/plugin-uninstall-args`（path 安装 + 空参 + 未知 + `--version 1.0` + list）与 `fixtures/differential/plugin-uninstall-index`（预置 git 源形态 index 与 `.bundle/plugin/bundler/gems/hook_plugin-abc123`，执行 list → uninstall → list → `hookprobe`，末命令 exit 15）。
- 4.0.24：两夹具 PASS（exit=0 / exit=15）；2.7.2：同样 PASS。既有 plugin 夹具回归 `plugin-install`/`plugin-uninstall`/`plugin-hook-uninstall`/`plugin-command-list`/`plugin-command-reinstall` 均 PASS；`plugin-git-local` 仍因本机 celerite 子进程 msys `sh.exe` Low IL `0xC0000022` 失败（任务已登记的环境噪声，与本次改动无关，未改产品代码）。

**门禁**（HEAD 前工作树）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告，`commands_install.cr:1112:43`、`:1176:20`）；`crystal spec spec/m7_plugin_uninstall_hooks_spec.cr` → 10 examples, 0 failures, 0 errors, 0 pending；`git diff --check` EXIT 0；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0。

**已声明差异 / 未验证**：
1. 差分 `plugin-uninstall-index` 使用相对 `plugin_paths`，参考 `installed_in_plugin_root?` 与实现同判 false，故两侧都不删除 checkout；绝对路径下的 checkout 删除由 spec 覆盖（`plugin_owned_path?` + `rm_rf`）。真实 `--git` 安装→卸载的端到端链在本机仍被 `0xC0000022` 挡住，**未验证**。
2. `--all` 多插件顺序按 index 插入序实现，但本轮无多插件 `--all` 夹具，顺序语义**未用差分验证**。
3. 差分只比较输出与项目树路径集合；index 文本内容（骨架）由 spec 直接断言，未纳入 tree 内容比较。
4. 全量 `crystal spec` 与全量差分未重跑（沿用 4061 行前的既有记录）。

## 2026-11-19（M7(3) task-21：安装期 `required_ruby_version` / `required_rubygems_version` 复核对齐）

**范围**：锁文件把不兼容 gem 钉死时，`bundle install` 不得静默安装；要求与参考 `Bundler::Installer#ensure_specs_are_compatible!` 的运行时约束一致，同时不改动解析期候选过滤与 check/show/binstubs 的运行时校验。参考版本 4.0.24 与 2.7.2 逐字对照。

**oracle（本机 Ruby 4.0.6 / RubyGems 3.6.9；`file://` 索引含 `incompat_ruby-1.0.0`「required_ruby_version >= 99」与 `incompat_rg-1.0.0`「required_rubygems_version >= 99」；手写命中锁）：**

| 场景 | 参考 4.0.24 | 参考 2.7.2 | 修复前 celerite | 修复后 celerite |
| --- | --- | --- | --- | --- |
| 锁 + `install`（ruby 不兼容） | exit 6，stdout `Fetching source index from file:///…/`、`Resolving dependencies...`，stderr 见下 | 同 4.0.24 | exit 0，安装成功（缺陷） | exit 6，stdout/stderr 与参考逐字一致 |
| 锁 + `install --local` | exit 7，stderr `Could not find incompat_ruby-1.0.0 in locally installed gems` | 同左 | 同参考（无锁复用路径） | 同参考 |
| 锁 + `check` | exit 1，stderr `The following gems are missing` / ` * incompat_ruby (1.0.0)` / “Install missing gems with \`bundle install\`” | 同左 | 同参考 | 同参考 |
| 无锁 + `install` | exit 6，同一 Molinillo 文案 | 同左 | exit 6，已逐字一致 | 不变 |
| BUNDLE_PATH 预置不兼容 gem + 锁 | exit 0，`Bundle complete! …`（`setup_domain!` 为 false，`ensure_specs_are_compatible!` 不执行） | 同左 | exit 0 | exit 0 |

参考 exit 6 的 stderr（两版逐字）：

```
Could not find compatible versions

Because every version of incompat_ruby depends on Ruby >= 99
  and Gemfile depends on incompat_ruby >= 0,
  Ruby >= 99 is required.
So, because current Ruby version is = 4.0.6,
  version solving has failed.
```

**结论**：参考的 `ensure_specs_are_compatible!`（4.0.24 `installer.rb:234-245`，入口 `installer.rb:79-82`；2.7.2 `installer.rb:227-238`）在正常流程中**不可达**——`definition.rb:190-203` 的 `setup_domain!` 只在需要安装时返回 true，而解析器已先按 `required_ruby_version`/`required_rubygems_version` 过滤候选，最终以 exit 6（`SolveFailure`，`errors.rb:26`）呈现。用户可见的参考行为是**解析期失败**，不是 exit 5 的 `InstallError`（`errors.rb:21`）。因此实现必须让锁文件复用路径回到解析期：否则会出现「锁文件命中 → 直接 materialize → 静默安装」。

**实现**（全部锚定参考）：
- `src/celerite/resolution.cr`：`ResolvedSpec` 增加 `required_ruby_version` / `required_rubygems_version`（由 `IndexSpec` 携带）；`resolve!(reuse, verify_locked_compat:)` 在复用前用 `incompatible_locked_spec_names` 比对锁文件钉住版本与索引 requirements，命中则把名字加入 `@unlock` 与 `@excluded_locked_names`，再走 `run_resolution`；`build_locked_index` 跳过被排除的名字，避免解析器再次接受不兼容钉子。`index_fetch_logged?` 暴露本次是否已打印 `Fetching source index`，供 CLI 去重。
- `src/celerite/installer.cr`：新增 `Installer.ensure_specs_are_compatible!(specs, ruby_version, rubygems_version)` 与实例包装，逐字复刻参考两条消息（`… requires ruby version …, which is incompatible with the current version, …` / rubygems 同形），作为「解析器让步」时的兜底，exit 5。
- `src/celerite/cli/commands_install.cr`：仅当 `reuse` 且锁文件存在、且至少一个锁定 spec 尚未安装时置 `verify_locked_compat = true`，随后 `resolve!(reuse, verify_locked_compat:)` 并调用 `installer.ensure_specs_are_compatible!(specs)`；安装输出条件改为 `reuse && pending.any? && !resolution.index_fetch_logged?`，避免已由解析打印的 fetch 行重复。
- 未改 `src/celerite/resolver/source.cr:283-284` 的解析期过滤，也未改 check/show/binstubs 的运行时校验。

**测试与差分**：
- 新增 `spec/m7_install_ruby_compat_spec.cr` 3 例：① CLI 锁 + 不兼容 → exit 6，stdout 两行、stderr 整块逐字断言；② 兼容锁复用 → specs 仅 `json_pure`，只打印一次 `Fetching source index`、无 `Resolving`；③ 直接调用 `ensure_specs_are_compatible!` → 两条 `InstallError` 文案逐字。该文件 3 examples 0 failures；与 `spec/m7_ruby_runtime_enforcement_spec.cr`、`spec/downloader_spec.cr` 合跑 13 examples 0 failures 0 errors 0 pending。
- 新增 `fixtures/gem-index-locked-ruby/`（由本机 oracle 索引复制：`incompat_ruby`/`incompat_rg` 的 `.gem`、`info/`、`quick/`、`specs.4.8.gz` 等；参考 `file://` 走 legacy index，必须有 `specs.4.8.gz`）与 `fixtures/differential/install-locked-ruby-incompatible/`（`command`=`install`、`Gemfile`、手写 `Gemfile.lock`，占位 `@LOCKED_RUBY_INDEX_DIR@`）。
- `script/differential` 增加 `@LOCKED_RUBY_INDEX_DIR@` 的六处替换（含 `|g` 变体）。
- 差分：4.0.24 `PASS install-locked-ruby-incompatible (exit=6)`，1 passed / 0 failed / 0 skipped；2.7.2 同。回归子集双 profile 7/0/0（`install-rerun` exit 0、`install-local` 7、`install-force` 0、`install-frozen` 15、`install-fresh` 0、`check-no-lockfile-installed` 0、`plugin-install` 1）。

**门禁**（HEAD 前工作树）：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告，`commands_install.cr:1112:43`、`:1176:20`）；`crystal spec spec/m7_install_ruby_compat_spec.cr spec/m7_ruby_runtime_enforcement_spec.cr spec/downloader_spec.cr` → 13 examples, 0 failures, 0 errors, 0 pending；`git diff --check` EXIT 0；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0。

**已声明差异 / 未验证**：
1. CLI 下 `ensure_specs_are_compatible!` 的 exit 5 分支在参考与实现中都不可达（解析期先失败）；该函数仅由 spec 单元验证，**未经 CLI 差分**。
2. `file://` 参考走 legacy index，需要 `specs.4.8.gz`；本夹具索引按此构建，未覆盖 compact-index 的 `file://` 组合。
3. 仅本机 C: 盘、Ruby 4.0.6 环境；跨盘符/跨 Ruby 版本未验证。
4. 全量 `crystal spec` 与全量差分未重跑（沿用既有记录）。

## 2026-11-19（M7(2) task-22：`check`/`list`/`show` 以 installed specification 判定已安装）

**范围**：只改只读发现命令的「是否已安装」判据；`install` 幂等与 task-21 锁复用仍用 `Installer#installed?`（spec + gem 目录），不改解析/下载。

**参考实现**：
- 4.0.24 `cli/check.rb:14-31`：`definition.check!` 取 `missing_specs`，逐条打印 ` * name (version)`；`definition.rb:260-262` → `spec_set.rb:154-162` 的 `missing_specs_for` 只对 `completely_missing_specs` 报缺。
- `lazy_specification.rb:224-229 materialize` 调 `source.specs.search`；Rubygems 源清单来自 `rubygems_integration.rb:438-440 find_name` = `Gem::Specification.stubs_for(name)`，即读 `<path>/specifications/*.gemspec`。
- `cli/show.rb:25-28`：先算 `spec.full_gem_path`，`File.directory?` 为假时打 `The gem <name> is missing. It should be installed at <path>, but was not found` 并 exit 0；`cli/info.rb:41-44` 同形。
- 2.7.2 对应文件同语义（`cli/check.rb`、`definition.rb`、`spec_set.rb`、`lazy_specification.rb`）。

**Oracle（本机 ruby 4.0.6；`file://` 索引 `fixtures/gem-index`，`json_pure 2.8.1`；BUNDLE_PATH 独立沙箱；4.0.24 与 2.7.2 输出一致）**：

| 场景 | 4.0.24 / 2.7.2 | 修复前 | 修复后 |
| --- | --- | --- | --- |
| 正常安装 | check 0 `The Gemfile's dependencies are satisfied`；list 0 含 ` * json_pure (2.8.1)`；show 0 打印 `…/gems/json_pure-2.8.1` | 同 | 同 |
| 删 `gems/json_pure-2.8.1`，留 `specifications/json_pure-2.8.1.gemspec` | check 0 satisfied；list 0 正常；`show json_pure` 0、stdout 空、stderr `The gem json_pure is missing. It should be installed at …/gems/json_pure-2.8.1, but was not found` | 误判缺失：check 1 / list 1 / show 7 | 与参考逐字一致（`show --paths` 同警告、不打印路径） |
| 删 `specifications/…gemspec`，留 gem 目录 | check 1 `The following gems are missing` + ` * json_pure (2.8.1)`；list 1 `Could not find json_pure-2.8.1 in locally installed gems`；show 7 同名 | 误判已安装：check 0 | 与参考逐字一致 |
| 平台变体 `platgem (1.0.0-x64-mingw-ucrt)` | 规格文件名含平台后缀；删 gem 目录 check 0，删 spec check 1 打 ` * platgem (1.0.0)`（check 行不带平台）；list 1 打完整 full name | 同左误判 | 按 `<full_name>.gemspec` 判定，平台名原样保留 |

**实现**：
- `src/celerite/cli/commands_surface.cr` `installed_gem_dir`：GEM 分支（`path.system`、bundle `ruby/<abi>`、系统 gem 回退）先查 `specifications/<full_name>.gemspec`，命中后仍返回 `gems/<full_name>` 供 `show` 判断目录是否存在；新增 `installed_spec_file?`。注释锚 `cli/check.rb:14-31`、`definition.rb:260-262`、`spec_set.rb:154-162`。
- `src/celerite/cli/commands.cr`：`show <gem>` 与 `show --paths <gem>` 在目录不存在时打参考警告并 exit 0（`cli/show.rb:25-28`）；其余 list/info 路径不变。
- `src/celerite/installer.cr:58-63 installed?` 未改（安装幂等/锁复用仍要求目录 + spec）。

**测试与差分**：
- `spec/m7_installed_discovery_spec.cr` 由 20 → 22 examples：四个「目录存在即已安装」旧断言改为参考语义（check 1 / list 1 / show 7 / `show --paths` 7），新增 spec-only 的 check 0、show 警告，及平台 full_name 不匹配的 check 1；组/平台夹具补 `specifications/*.gemspec`。结果 **22 examples, 0 failures, 0 errors, 0 pending**。
- 新增差分 `check-installed-spec-without-gemdir`（`bundle-preset` 只放 `ruby/4.0.0/specifications/json_pure-2.8.1.gemspec`；命令 `check`/`list`/`show`/`show --paths`）与 `check-gemdir-without-spec`（只放 `ruby/4.0.0/gems/json_pure-2.8.1`；命令 `check`/`list`/`show`，末退出 7）。4.0.24 与 2.7.2 均 **PASS**（exit 0 / 7）。
- 定向回归（`check-*`、`list-*`、`show-*`、`git-installed-discovery`、`install-local` 共 37 个）：4.0.24 **35 passed, 1 failed, 1 skipped**；2.7.2 同。唯一失败为 `git-installed-discovery`：参考 0 / cel 1，stderr 见 `sh.exe ... NtCreateDirectoryObject ... 0xC0000022`，属既有 Low-IL 环境阻塞；skip 为 4.0.24 的 `show-outdated-verbose-272`（该夹具仅 2.7.2 适用）。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告，`commands_install.cr:1112:43`、`:1176:20`）；`crystal spec spec/m7_installed_discovery_spec.cr` → 22/0/0/0；`git diff --check` EXIT 0；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0。

**已声明差异 / 未验证**：
1. `install` 的已安装判定仍是「spec + 目录」（task-21 锁复用依赖它）；本轮只对齐只读命令，未统一。
2. `bundle show --paths`（不带 gem 名）在「spec-only」时是否也逐条警告未取 oracle；带名路径已对齐。
3. 平台变体只用单元夹具覆盖，未新增对应差分（现有 spec 断言 full_name）；跨盘符/多 Ruby 版本未验证。
4. 全量 `crystal spec` 与全量差分未重跑（沿用既有记录）。

## 2026-11-19（M7 L161 task-23：upstream-specs 装具缺失 gem 文件诊断）

**结论**：`fixture:missing-gem-files`（11 例）不是 Celerite 产品差异，而是 upstream 测试装具的**夹具仓库毒化**：首次 `before(:suite)` 在缺少 upstream dev/test 依赖缓存时，`build_repo1` 以 `nil` 的 `rake_path` 调 `FileUtils.cp` 抛 `TypeError`，此时 `build_repo` 已创建空的 `remote1/gems`；后续运行因目录已存在而早退，`build_repo2` 逐字复制空 `remote1`，于是所有需要 `remote2/gems/myrack-*.gem` 的用例报 `Errno::ENOENT`。已在 harness 侧（`script/upstream-specs`）修复并从未污染状态复跑，未改 `.upstream-specs/v4.0.24/` 任何 vendored 文件。

**根因链（锚点）**：
- `spec/spec_helper.rb:141` 在 `before(:suite)` 调 `build_repo1`；`build_repo1`（`spec/support/builders.rb:29-41`）第 31 行 `FileUtils.cp rake_path, "#{gem_repo1}/gems/"`。
- `rake_path` 由 `spec/support/path.rb:298-300` → `:322-324` 用 `Dir["#{scoped_base_system_gem_path}/**/rake-*.gem"].first` 解析；`base_system_gem_path` 是 `tmp/gems/base`（`path.rb:186-188`，**不带 `2.1` scope**），`scoped_gem_path` 再拼 `Gem.ruby_engine/ruby_version`（`path.rb:241-243`）。
- upstream 的 dev/test 依赖只在 `Spec::Rubygems.test_setup` 的 `install_test_deps` 中安装（`spec/support/rubygems_ext.rb:30-32`、`:58-67`）；harness 在 `CELERITE_SKIP_TEST_DEPS=1` 时用 `RSPEC_FORMATTER_OUTPUT_ID` 跳过它，故该缓存常缺失。
- `build_repo`（`builders.rb:269-275`）先 `mkdir_p("#{path}/gems")` 再 yield；`TypeError` 因此在建目录之后抛出，留下空 `remote1/gems`。之后 `build_repo` 的 `return if File.directory?(path)` 使 `remote1` 永久为空。
- `build_repo2`（`builders.rb:183-186`）`FileUtils.cp_r gem_repo1, gem_repo2` 复制空仓库；`reset!`（`spec/support/helpers.rb:20-30`）每例后删除 `remote2`，所以只在用例运行期出现 ENOENT：`.../tmp/2.1/gems/remote2/gems/myrack-1.0.0.gem`、`myrack-0.9.1.gem`。
- 最小复现（清空 `tmp/2.1` 后跑单例）：
  `CELERITE_SKIP_TEST_DEPS=1 ruby -S rspec -r script/upstream-specs-celerite-override.rb spec/lock/lockfile_spec.rb -e "generates a simple lockfile for a single source, gem"`
  → `An error occurred in a 'before(:suite)' hook.` / `Failure/Error: FileUtils.cp rake_path, "#{gem_repo1}/gems/"` / `TypeError: no implicit conversion of nil into String`，栈顶 `fileutils.rb:2484 File.path` → `builders.rb:31`。
  另证：`Gem::Package.build` 在本机可正常产 gem（手工构建 `myrack-1.0.0.gem` 成功），排除 Windows 构建能力问题。

**修复**（`script/upstream-specs`，rspec 之前）：
1. 若 `tmp/2.1/gems/remote1/gems` 存在但无 `*.gem`，删除 `remote1` 与 `remote2`，让 `build_repo1` 重新执行。
2. 若 `tmp/gems/base` 下无 `rake-*.gem`，从本机 `Gem::Specification.find_by_name("rake").cache_file`（回退 `Gem.default_dir/cache/rake-*.gem`）复制到 `tmp/gems/base/<Gem.ruby_engine>/<ruby_version>/cache/`（本次 `ruby/4.0.0/rake-13.4.2.gem`），使 `rake_path` 非 nil。
两处都带注释锚定上述 upstream 行号；不修改 vendored 测试源码，也不跳过/弱化断言。

**新基线（4.0.24，`CELERITE_SKIP_TEST_DEPS=1`，从“空 `remote1` + 无 base 缓存”的毒化状态启动，日志确认 `repairing stale empty upstream fixture repo` 与 `seeding upstream base gem cache with rake-13.4.2.gem`）**：

| 指标 | 修复前（roadmap L161 记录） | 修复后（本轮） |
| --- | --- | --- |
| examples / failures | 64 / 55（9 通过） | **64 / 54（10 通过）** |
| env:artifice-unreachable | 34 | 37 |
| env:low-il-shm | 8 | 8 |
| fixture:missing-gem-files | 11 | **0** |
| fixture:fetch-failed | 1 | 6 |
| env:network-policy | 1 | 0 |
| product:candidates | 0 | 3 |

11 例去向（按新桶）：9 例转 `env:artifice-unreachable`（`generates a simple lockfile for a single source, gem`、`captures the Ruby version in the lockfile`、`works correctly with multiple version dependencies`、`does not add duplicate dependencies`、`does not add duplicate dependencies with versions`、`does not add duplicate gems`、`does not add duplicate dependencies in different groups`、`does not add credentials to lockfile when it does not have them already`、`keeps credentials in lockfile if already there`——它们用进程内 artifice 的 `https://gem.repo2`，celerite 子进程无法接入，属既有 harness 限制）；1 例转 `env:low-il-shm`（`sorts serialized sources by type`）；1 例转 `product:candidates` 且附断言级证据：`fills empty CHECKSUMS entries when not frozen, even if every gem is already installed` 期望 `  myrack (0.9.1) sha256=…`，实际只写 `  myrack (0.9.1)`（缺 sha256）。新增的另两个 `product:candidates`（`is conservative with dependencies of git gems`、`keeps existing platforms in the lockfile`）本轮才越过夹具阶段，尚未逐条判为产品缺陷（前者含 git 环境输出，后者是“锁文件仅 java 平台”下的 add-platform 告警），标**未验证**。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告，`commands_install.cr:1123:43`、`:1187:20`）；`git diff --check` EXIT 0。本轮未改 `src/`/`spec/`，无新增产品侧 spec；`crystal spec` 未跑。

**已声明差异/未验证**：仅跑 4.0.24；`.upstream-specs/v2.7.2` 无可用 bundler checkout，2.7.2 profile 未跑。`artifice-unreachable`/`low-il-shm`/`fetch-failed` 仍是环境桶，不能据此宣称 M7(8) 完成。harness 修复依赖本机存在 rake gem 缓存；无缓存时仍会打印 warning 并保留旧的空仓库（fail-open，不伪造通过）。checkbox 保持 `[ ]`。

## 2026-11-19（M7(6) task-24：typed source 独存时 install 失败面对齐）

**结论**：Gemfile 只有 `source "…", type: :foo`（无普通 `source` 行）且插件开启时，Celerite 原先在 `PluginGemfile.primary_source` 返回 nil 后回落 `https://rubygems.org/`（`commands_install.cr:105`），于是先撞网络/SSL：exit 17 `Could not verify the SSL certificate for https://rubygems.org/.`。参考用空 source list 解析推断插件，本地无该插件时直接 `GemNotFoundError`（exit 7）。本轮只对齐失败面与执行顺序：无 primary source 时以 `local_only` 解析插件，得到与参考相同的消息与退出码；自定义 source 成功路径仍留待后续切片。

**Oracle（4.0.24 与 2.7.2 实测，逐字）**：
- 场景 A（仅 typed source，插件开）：两版本均 exit 7，stdout 为空，stderr：
```
Could not find gem 'bundler-source-foo' in locally installed gems.
```
- 场景 B（同上，`BUNDLE_PLUGINS=false`）：两版本均 exit 15，stdout 为空，stderr 首行为空行后：
```
[!] There was an error parsing `Gemfile`: No plugin sources available for foo. Bundler cannot continue.
```
（4.0.24 片段只有 `>  source …` 一行；2.7.2 片段含重复 source 行，格式差异属既有 Gemfile 错误渲染，本切片未改。）
- 场景 C（`source "file://…/gem-index"` + typed source）：两版本均 exit 7；stdout `Fetching source index from file://…/gem-index/`；stderr 换行包裹：
```
Could not find gem 'bundler-source-foo' in rubygems repository
file://…/gem-index/ or
installed locally.
```
- 场景 D（typed source 带 block `do gem "json_pure" end`）：与场景 A 完全一致（exit 7、同 stderr）。⇒ block 不影响推断插件，typed source 本身不提供 remote。
- 我方修复前：场景 A exit 17 + SSL 证书消息；场景 C 与参考已逐字一致。修复后场景 A 与参考逐字一致（stdout 空、stderr 单行、exit 7）。

**参考锚点**：4.0.24 `lib/bundler/cli/install.rb:41` 在 install 前调 `Plugin.gemfile_install`；`lib/bundler/plugin.rb:104-121` 用 `Plugin::DSL` 求值、`definition = builder.to_definition(nil, true)`、`Installer#install_definition`；`lib/bundler/plugin/dsl.rb:39-50` 把 `source … type:` 推断为 `bundler-source-<type>` 且不登记 source；`lib/bundler/plugin/installer.rb:35-40`（`install_definition` 只 `remotely!` 空 source list）、`:91-101`（`install_all_sources` 构造无 remote 的 dependency）。2.7.2 对应：`bundler-2.7.2/lib/bundler/cli/install.rb:65`、`plugin.rb:103`、`plugin/dsl.rb:44`、`plugin/installer.rb:35`、`:101`。

**改动**：
- `src/celerite/cli/commands_install.cr:105-123`：`remote = PluginGemfile.primary_source(gemfile_path)` 不再回落 rubygems.org；`remote` 存在时照旧 `--source <remote>`，不存在时调 `plugin_install_remote([name], [] of String, …, local_only: true)`。
- `src/celerite/cli/commands_surface.cr:1641-1646`：`plugin_install_remote` 新增 `local_only : Bool = false` 关键字（注释说明空 source list 语义）；`:1695` 在构造 `Resolution` 后设 `resolution.local_only = local_only`，使合成 Gemfile 的 `source "https://rubygems.org/"` 只用于本地索引，不联网。
- 未动：主 Gemfile 求值、`primary_source` 本身（typed 行仍被跳过）、其他 plugin 安装路径。

**测试/夹具**：新增 `spec/m7_typed_source_spec.cr`（2 例：typed-only 与 typed+block，断言 stdout 空、stderr 逐字、exit 7，并断言不出现 `rubygems.org`/`SSL`）；与 `spec/m7_gemfile_plugins_spec.cr` 合并跑 9 examples / 0 failures。新增差分 `fixtures/differential/install-typed-source-missing-plugin/`（`Gemfile` 仅 typed source、`command` 单行 `install`，末字节 LF），4.0.24 与 2.7.2 均 `PASS … (exit=7)`，1 passed / 0 failed / 0 skipped。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check` EXIT 0。

**已声明差异/未验证**：本切片只修失败面；若 `bundler-source-<type>` 可从本地索引解析，仍会进入既有的“自定义 source 成功路径未支持”分支（`commands_install.cr:113-116`，exit 1），参考则继续安装插件并进入主 install。插件已安装时 `installed_plugin?` 仍直接跳过（沿用既有行为）。未覆盖 `plugin "x"` 声明的 typed 组合；`BUNDLE_PLUGINS=false` 下 2.7.2 的片段格式未单独对我方取 oracle（4.0.24 已逐字对齐）。全量 spec 与全量差分未重跑。checkbox 保持 `[ ]`。

## 2026-11-19（M7(8) task-25：空 CHECKSUMS 触发重解析与 sha256 回填）

**参考语义**
- 4.0.24 `lib/bundler/definition.rb:630-659` `something_changed?` 把 `@locked_spec_with_missing_checksums` 视为永远需要重解析；空条目只在 `empty_checksums_actionable?` 为真时触发，该谓词为 `Bundler.frozen_bundle? || !sources.local_mode?`（`:651-659`）。`setup_domain!`（`:190-203`）在 `add_checksums` 或非 local 且（需要安装或有空 CHECKSUMS）时 `sources.remote!`。
- `definition.rb:973-1015 check_lockfile` 用 `checksum_store.missing?/empty?` 记录两类状态（`:988-992`、`:1002`）；`lockfile_generator.rb:69-76` 仅在 `definition.locked_checksums` 为真时写 `CHECKSUMS`，内容为 `checksums + bundler_checksum`；单条格式见 `checksum.rb:85-87`（`algo=hexdigest`），API 校验和入口见 `endpoint_specification.rb:175 Checksum.from_api`。2.7.2 对应 `bundler-2.7.2/lib/bundler/definition.rb` 同段逻辑，但默认不写 bundler 自身校验和。
- 参考 4.0.24 `install` 重解析时只打印 `Fetching gem metadata from …`（不打印 `Resolving dependencies...`），`lock` 两者都打印；2.7.2 的 `install` 两者都打印。`BUNDLED WITH` 缩进 4.0.24 为 2 空格、2.7.2 为 3 空格。

**oracle（预置两条空 CHECKSUMS：`bundler (<ver>)` 与 `json_pure (2.8.1)`；http index 127.0.0.1:8765 服务 `fixtures/gem-index`）**

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `install`（bundle-preset 预装 stub） | exit 0；stdout `Fetching gem metadata from http://127.0.0.1:8765/.`、`Bundle complete! 1 Gemfile dependency, 1 gem now installed.`、`Bundled gems are installed into …`（无 `Resolving dependencies...`）；CHECKSUMS 回填 `bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc` 与 `json_pure (2.8.1) sha256=6a877929ba9d4fa0808ccc38656d1b15d138b2aa0aa32037ee05abea13427ace` | exit 0；stdout 含 Fetching、`Resolving dependencies...`、`Bundle complete! 1 Gemfile dependency, 2 gems now installed.`、Bundled gems 行；CHECKSUMS 只回填 json_pure，bundler 条目被移除 |
| `lock` | exit 0；stdout `Writing lockfile to …/Gemfile.lock`、Fetching、`Resolving dependencies...`；CHECKSUMS 同 install（bundler + json_pure） | exit 0；stdout 同形状；CHECKSUMS 只回填 json_pure |

- 我方修复前：复用锁解析直接写回空条目，无 Fetching 行；修复后两个场景的完整 `Gemfile.lock` 与 stdout 均与参考一致（含各 profile 的 `BUNDLED WITH` 缩进与 bundler 行差异）。
- `--local`：参考 `empty_checksums_actionable?` 为假，保持锁定解析、不联网；我方按同一谓词实现，但该分支只有 spec 断言，未单独跑参考 CLI oracle。

**实现**
- `src/celerite/definition.cr:362` 新增 `checksums_need_refresh?(local_only : Bool = false)`：无锁/无 CHECKSUMS 段返回 false；遍历 GEM 源，缺少条目记 `missing`，条目无摘要记 `empty`；返回 `missing || (empty && (config.frozen? || !local_only))`，与 `definition.rb:630-659` 同形。
- `src/celerite/cli/commands_install.cr:307`：`checksum_refresh = reuse && definition.checksums_need_refresh?(rest.includes?("--local"))`；为真时关闭复用；再按 bridge bundler 主版本抑制 `Resolving dependencies...`，对齐 4.0.24 与 2.7.2 的 install 差异。
- `src/celerite/cli/commands.cr:2324`：`lock` 在既有的 no-op 快速返回前计算 `checksum_refresh`，为真时不提前返回，走正常解析并重写锁文件。
- `script/differential`：新增 `file-equals` 断言块（首行为工程内相对路径，其余为期望全文；支持 `file-equals-<BUNDLER_VERSION>` 覆盖），用于逐字比较两 profile 的 `Gemfile.lock`。
- 未动：CHECKSUMS 解析器、compact-index/下载器、`file:` 源清空校验和的既有行为（`resolution.cr:733-736`）。

**测试/夹具**
- 新增 `spec/m7_checksums_trigger_spec.cr`（3 例）：预装 stub 下 `install` 回填并打印 Fetching；`lock` 回填；`--local` 不触发刷新（`checksums_need_refresh?(true)` 为假、`(false)` 为真）且不打印 Fetching。3 examples / 0 failures / 0 errors / 0 pending。
- 新增差分 `fixtures/differential/checksums-empty-install/` 与 `checksums-empty-lock/`：`http-index` 标记服务 `fixtures/gem-index`，`bundle-preset/` 提供已安装 stub，`Gemfile.lock` 预置两条空 CHECKSUMS，`file-equals-4.0.24`/`file-equals-2.7.2` 分别断言完整锁文件。
- 差分结果：4.0.24 `PASS checksums-empty-install (exit=0)`、`PASS checksums-empty-lock (exit=0)`；2.7.2 同两项 `PASS`；均 2 passed / 0 failed / 0 skipped。既有回归集未受影响（本切片未改解析器/下载器）。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check` EXIT 0。

## 2026-11-19（M7(8) task-26：`lock --add-checksums` 计算路径与 frozen 空 CHECKSUMS 拒绝）

**参考语义**
- 4.0.24 `lib/bundler/definition.rb:564-583 add_checksums`：先设 `@locked_checksums = true`，`setup_domain!(add_checksums: true)` 并强制 materialize `specs`；对校验和缺失/为空的 Rubygems spec，用 `Gem::Package.new(spec.source.cached_built_in_gem(spec))` 取安装缓存（缓存缺失时经 `source/rubygems.rb:244-256/357-363` 下载到 `<bundle>/ruby/<abi>/cache/`）并 `Checksum.from_gem_package` 注册。`cli/lock.rb:70` 在 `definition.remotely!` 之前调用。
- 2.7.2 安装 gem `bundler-2.7.2/lib/bundler/definition.rb:535-541 add_checksums`：只设 `@locked_checksums = true`、`setup_domain!(add_checksums: true)`、强制 materialize，不计算、不注册；因此只写出空 `CHECKSUMS` 条目。
- 写出条件见 `lockfile_generator.rb:69-76`（`definition.locked_checksums`）；`--add-checksums` 使无 `CHECKSUMS` 段的旧锁也新增该段。

**oracle（`file://` 源 + `bundle-preset` 已安装 stub；锁预置无段/一条空条目）**

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `lock --add-checksums`（无段） | exit 0；stdout `Fetching source index from file:///…/gem-index/`、`Fetching json_pure 2.8.1`、`Writing lockfile…`；锁新增 `bundler (4.0.24) sha256=16ca64e2…` 与 `json_pure (2.8.1) sha256=6a877929…`，并在 bundle 缓存写入 `json_pure-2.8.1.gem` | exit 0；stdout 仅 index fetch + Writing（无 `Fetching json_pure`）；锁新增空 `json_pure (2.8.1)`，无 bundler 行、无缓存 gem |
| `lock --add-checksums`（一条空条目） | exit 0；stdout 多一行 `Resolving dependencies...`；锁同上 | exit 0；stdout 多一行 `Resolving dependencies...`；条目仍为空 |
| `BUNDLE_FROZEN=true install`（空条目） | exit 16；stderr 四行 `Your lockfile has an empty CHECKSUMS entry for "json_pure", but can't be updated` / `because frozen mode is set` / 空行 / `Run \`bundle install\` elsewhere and add the updated Gemfile.lock to version` / `control.`；锁不变 | 同左（逐字一致） |
| `lock --add-checksums --local`（无段） | exit 0；stdout 同无段场景（仍 fetch index 与 gem）；锁同无段 | exit 0；stdout 同无段；锁新增空条目 |

**实现**
- `src/celerite/resolution.cr:1323-1327` 新增 `property add_checksums`；`:1650-1655 checksums_enabled?` 在 `add_checksums` 时直接为真（两 profile 都写段）。
- `:298-345` 新增公开 `bridge` 与 `compute_checksums_from_installed`：仅处理已安装 spec（`specifications/<full_name>.gemspec` 存在）、跳过已有非空锁条目与自带 `spec.checksum`；缓存 gem 缺失时调用传入的 fetch 块并复制到 `<bundle>/ruby/<abi>/cache/<full_name>.gem`，再计算 sha256 写入 `install_checksums`。
- `src/celerite/cli/commands.cr:2395-2412`：4.0.24 分支先 `resolve!`，再构造 `Downloader` 逐 gem 打印 `Fetching <name> <version>` 并取包；`:2324` 在 `--add-checksums` 时忽略 `--local` 的刷新抑制与 `local_only`；`:2389` 仅在没有待回填空条目时抑制 `Resolving dependencies...`（空条目场景仍打印）。
- frozen 拒绝复用既有 `Definition#assert_frozen!`（`definition.cr:145-181`），输出与参考逐字一致，未改代码。
- 未动：`file:` 源清空校验和、解析器、下载器、compact-index。

**测试/夹具**
- `spec/m7_checksums_trigger_spec.cr` 扩到 5 例：新增 `lock --add-checksums`（`file://`）计算并断言 stdout/锁；frozen 空条目断言 exit 16、逐字 stderr、锁不变。5 examples / 0 failures / 0 errors / 0 pending。
- 新增 `fixtures/differential/lock-add-checksums/`（`file:///@INDEX_DIR@` + 预装 stub + 无段锁，`command`=`lock --add-checksums`）与 `lock-add-checksums-frozen/`（`frozen` 标记 + 空条目锁，`command`=`install`）；`file-equals-4.0.24`/`file-equals-2.7.2` 断言完整锁文件。`script/differential` 的 `file-equals` 期望文本现同时替换 `@INDEX_DIR@`。
- 差分：4.0.24 `PASS lock-add-checksums (exit=0)`、`PASS lock-add-checksums-frozen (exit=16)`；2.7.2 同两项 `PASS`；均 2 passed / 0 failed / 0 skipped。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check` EXIT 0。

**已声明差异/未验证**：frozen 只覆盖空条目（缺条目未单独取 oracle，逻辑同 `assert_frozen!`）；`--add-checksums` 的 bundler 自身校验和依赖本机 bundler gem 缓存（参考同依赖）；平台变体与多 gem 未覆盖；`lock --add-checksums --print` 未取 oracle；全量 spec 与全量差分未重跑。checkbox 保持 `[ ]`。


**已声明差异/未验证**：`lock --local` 的参考 CLI 行为未单独取 oracle（仅按 `empty_checksums_actionable?` 与 spec 断言）；frozen 模式下空条目的措辞/时序未实测；4.0.24 的 bundler 自身校验和来自本机 gem 缓存，若缓存缺失则无法生成该行（参考同样依赖本地 bundler gem）；差分只覆盖一个依赖与 `json_pure`/`bundler` 两条空条目，多平台/多 gem 组合未单独覆盖；全量 spec 与全量差分未重跑。checkbox 保持 `[ ]`。

## 2026-11-19（M7(3) task-27：`bundle gem` 选项面与 `--help` 对齐）

**范围**：`bundle gem` 的 `--help`、枚举选项、MIT/COC/changelog/exe/ext 模板分支与 Thor 的枚举/未知开关拒绝，对齐 4.0.24，2.7.2 共享同一套语义（Go 扩展与 `--rubocop` 段按版本区分）。`--edit`/`--bundle` 属交互/网络副作用，显式报“不支持 + 参考行为 + exit 1”，不静默忽略。

**oracle（本机 Ruby 4.0.6；`ruby -S bundle _<ver>_ gem …`，隔离 HOME）**

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `gem --help` | exit 0；manpage 6060 字节，含 `--ext=c/go/rust`，无 `--rubocop` 段 | exit 0；6100 字节，含 `--ext=c/rust` 与 `--rubocop` 段 |
| 组合（`--test=rspec --linter=rubocop --ci=github --mit --exe --no-git --github-username=testuser`） | exit 0；`Creating gem 'foo'...`、三行 `… is already configured, ignoring … flag.`、`MIT License enabled in config`、`RuboCop enabled in config`，生成 `.github/workflows/main.yml`、`.rubocop.yml`、`LICENSE.txt`、`exe/foo`、`spec/foo_spec.rb` | 同上（成功 URL 为 `https://bundler.io/guides/creating_gem.html`） |
| 枚举/未知开关 | `--test=minitestx` exit 15 `Expected '--test' to be one of rspec, minitest, test-unit; got minitestx`；`--bogus` exit 15 `Unknown switches "--bogus"` | 逐字一致 |
| 扩展 | `--ext=c` 生成 `ext/foo/{extconf.rb,foo.c,foo.h}`；`--ext=rust` 生成 `Cargo.toml`、`ext/foo/{Cargo.toml,build.rs,extconf.rb,src/lib.rs}` | `--ext=c` 同左；`--ext=rust` 无 `build.rs`（2.7.2 模板集） |
| 已存在目标 | 目录存在→继续写入；仅同名文件存在→exit 32 `Couldn't create a new gem named \`foo\` because there's an existing file named \`foo\`.` | 同左 |

**参考锚点**：4.0.24 `.upstream-specs/v4.0.24/bundler/lib/bundler/cli.rb:589-602`（选项定义）、`:14`（`EXTENSIONS=["c","rust","go"]`）、`lib/bundler/cli/gem.rb:62-98`（config/template map）、`:118-155`（test）、`:157-171`（CI）、`:173-201`（mit/coc/changelog）、`:203-215`（linter）、`:217-220`（exe）、`:222-250`（c/rust/go ext）、`:252-255`（已存在文件）、`:257-262`（git init/branch）、`:269-273`（chmod）、`:289-290`（成功文案）；2.7.2 安装 gem `bundler-2.7.2/lib/bundler/cli.rb:538-551`、`cli/gem.rb:228-232`（无 build.rs）、`:419-434`（`--no-rubocop` 文案为 `use --linter`）。

**实现**：`src/celerite/gem_template.cr` 改为调用 `assets/gem_render.rb`（复用 bundler 自身的 ERB 模板集；`assets/gem_templates/<profile>/newgem` 从安装 gem 逐字复制，`assets/gem_help/*.txt` 为 oracle 输出）；`src/celerite/cli/commands_surface.cr` 的 `gem` 改为完整选项解析（help、`--k=v`/分写、枚举、`--no-*`、`--github-username`）、模板分支与成功文案；`src/celerite/cli/commands.cr` 的 `GEM_SWITCH_FLAGS/VALUES` 补齐 `-t` 与 `--no-test/--no-ci/--no-linter/--no-ext`。

**测试/夹具**：`spec/m7_gem_options_spec.cr` 新增 4 例（help 逐字、组合模板、Rust 扩展、未知开关/多 positional）；`spec/m7_gem_spec.cr` 的选项拒绝例改为 Thor 枚举文案。差分新增 `gem-options`/`gem-invalid`/`gem-ext`（`file-contains` 断言关键文件内容）；4.0.24 3/0，2.7.2 3/0；既有 `gem-default`/`gem-no-git` 4.0.24 2/0（2.7.2 沿用既有 skip 声明）。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check` EXIT 0；定向 spec 15 examples / 0 failures / 0 errors / 0 pending。

**已声明差异/未验证**：交互式提示（未指定 test/ci/linter/mit/coc/changelog 时的问卷）未实现，默认值按“不生成”处理；`--edit`/`--bundle` 只报不支持；2.7.2 的 `gem-default`/`gem-no-git` 因参考模板与成功 URL 历史差异继续 skip（4.0.24 目标已对齐）；未跑全量 spec 与全量差分。checkbox 保持 `[ ]`。

## 2026-11-19（M7(6) task-28：自定义 source 的 S1——求值、specs 与 `PLUGIN SOURCE` 锁段）

**范围**：`source "<uri>", type: :<plugin>` 的 S1 切片——桥进程求值 Gemfile 后取得插件 source 的 `specs`，解析阶段用这些 specs 建立索引，`lock` 写出版本门禁 `>= 1.13` 的 `PLUGIN SOURCE` 段（`remote`/`type`/`options_to_lock`/`specs`），顶层依赖带 `!`。安装（S3）、锁定索引复用（S2）与 `@inferred_plugins` 预装不在本切片。

**oracle（本机 Ruby 4.0.6；`ruby -S bundle _<ver>_ lock`，隔离 HOME；`fixtures/differential/plugin-source-typed` 等价的 `./stub-path-gem` + `type: :mpath`）**

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `lock` | exit 0；stdout `Writing lockfile to …`、`Resolving dependencies...`；锁含 `PLUGIN SOURCE` / `remote: ./stub-path-gem` / `type: mpath` / `specs:` / `stub-gem (1.0.0)`，`DEPENDENCIES` 为 `stub-gem!` | 同左 |
| 校验段 | `CHECKSUMS` 含 `bundler (4.0.24) sha256=16ca64e2…` 与空摘要 `stub-gem (1.0.0)` | 无 `CHECKSUMS` 段 |
| 尾部 | `BUNDLED WITH` 缩进 2 空格 + `4.0.24` | 缩进 3 空格 + `2.7.2` |

**参考锚点**：4.0.24 `.upstream-specs/v4.0.24/bundler/lib/bundler/plugin/api/source.rb:41`（`uri/options/name`）、`:73`（`options_to_lock` 默认 `{}`）、`:136`（`specs` 来自 `fetch_gemspec_files`）、`:283-295`（`to_lock`，注释声明不得覆写）；求值期只调用 `initialize`（`dsl.rb:130-139`、`source_list.rb:65`）；锁写入 `lockfile_generator.rb:31-42`；锁读取 `lockfile_parser.rb:195`（版本门禁 `1.13`）。

**实现**：`assets/bridge/server.rb` 的 `serialize_source` 识别 `Bundler::Plugin::API::Source`，输出 `type=Plugin`、`plugin_type`、`remote`、`lock_options`；新增 `plugin_source_specs` 操作经 `source.specs` 返回 name/version/platform/loaded_from/dependencies。`src/celerite/bridge/client.cr` 增加 `plugin_type`/`lock_options` 与 specs 结构；`src/celerite/resolution.cr` 为 Plugin 源跳过文件系统索引、按 bridge specs 建 `IndexSpec` 与锁段；`src/celerite/definition.cr` 的 source 标签与默认源比较接受 `Plugin`/`PLUGIN SOURCE`。

**测试/夹具**：新增 `spec/m7_plugin_source_typed_spec.cr`（1 例：解析并写出非空 `specs` 的 `PLUGIN SOURCE` 段、`stub-gem!`）；新增差分 `plugin-source-typed`（`command` 为 `lock`，`extra/` 携带相对路径的 `.bundle/plugin/index` 与 `bundler-source-mpath` 插件，锁用 `file-equals-4.0.24`/`file-equals-2.7.2` 逐字断言）。4.0.24：`plugin-source`/`plugin-source-ok`/`plugin-source-typed`/`plugin-install*`/`plugin-uninstall*`/`plugin-hook*`/`plugin-command*`/`gem-*`/`install-*` 共 26 passed、0 failed、0 skipped；2.7.2 同批 24 passed、0 failed、2 skipped（`gem-default`/`gem-no-git` 沿用既有版本差异声明）。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check`（暂存后）EXIT 0；定向 spec 1 example / 0 failures / 0 errors / 0 pending。

**已声明差异/未验证**：安装路径（S3）未实现——`install`/`plugin install` 对自定义 source 仍按既有行为失败；`build_locked_index` 尚不接受 `PLUGIN SOURCE`（S2），因此锁存在时复用未验证；插件 source 的 `checksum` 与 `options_to_lock` 非空形态仅按 `{}` 实测；未跑全量 spec 与全量差分。checkbox 保持 `[ ]`。

## 2026-11-19（M7(6) task-29：自定义 source 的 S2——锁定 `PLUGIN SOURCE` 复用与缺插件语义）

**范围**：`Gemfile.lock` 已含 `PLUGIN SOURCE` 时的复用路径（`build_locked_index` 接受该段、经插件 `specs` 物化，不把插件源当普通 gem 重解析、不丢段），以及插件未安装时的参考错误语义。安装成功路径仍属 S3，不在本轮。

**oracle（本机 Ruby 4.0.6；`ruby -S bundle _<ver>_ <cmd>`，隔离 HOME/BUNDLE_PATH，锁取自 4.0.24/2.7.2 各自的 `lock` 产物）**

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| 已装插件，`lock` | exit 0；stdout 仅 `Writing lockfile to …`，无 `Resolving` | 同左 |
| 已装插件，`check` | exit 0；`The Gemfile's dependencies are satisfied` | 同左 |
| 已装插件，`install` | exit 7；stdout `Fetching source index from file:///…/gem-index/`；stderr `Could not find gem 'bundler-source-mpath' in rubygems repository … or installed locally.` | 同左 |
| 缺插件，`lock` / `check` | exit 15；stderr `[!] There was an error parsing \`Gemfile\`: No plugin sources available for mpath. Bundler cannot continue.` | 同左 |
| 缺插件，`install` | exit 7；`Fetching source index …` + 同一缺少 `bundler-source-mpath` 文案 | 同左 |

**参考锚点**：4.0.24 `.upstream-specs/v4.0.24/bundler/lib/bundler/plugin/api/source.rb:41`（`uri/options/name`）、`:73`（`options_to_lock`）、`:136`（`specs`）、`:283-295`（`to_lock`，含 `remote`/`type`/options/specs）；`bundler/plugin.rb:202-211`（锁内 type 未注册时返回 `UnloadedSource`）；`bundler/plugin/unloaded_source.rb` 继承 `API::Source`，默认 `fetch_gemspec_files` 为空 → `specs` 为空但锁仍可解析；求值阶段 `dsl.rb:130-139` / `source_list.rb:65`。

**实现**：
- `src/celerite/resolution.cr` `materialize_locked`：按锁段 `source.type` 区分，`PLUGIN SOURCE` 的 spec 标 `"PLUGIN"` 并携带由 `plugin_source_info` 复原的 `SourceInfo`（`plugin_type` + `lock_options`）；`build_locked_index` 增加 `PLUGIN SOURCE` 分支——按锁段构造 source info，调用桥 `plugin_source_specs` 取该名字的 specs；桥报 `BridgeError` 时跳过该条（等价 `UnloadedSource` 空 specs）。
- `src/celerite/cli/commands_surface.cr` `installed_gem_dir`：`PLUGIN SOURCE` 的 `remote` 展开为项目内绝对路径，`check`/`list` 视插件物化出的 spec 为可用。
- `src/celerite/cli/commands.cr` `run_check`：有锁时先 `evaluate_gemfile`（`BridgeError` 状态 4/15 原样上抛，其余忽略），复刻参考在 `Bundler.definition` 阶段先求值 Gemfile 的顺序（缺插件 exit 15 优先于锁内已装判定）。
- `src/celerite/resolution.cr` checksum 段：2.x 过滤 `bundler` 自身条目（参考 2.7.2 不写该行）。
- `src/celerite/cli/commands.cr` 无操作 `lock` 重写锁文本：2.x 移除 `bundler (` 行（4.x 锁在 2.x profile 下重写时不保留该行）。

**测试/夹具**：
- `spec/m7_plugin_source_typed_spec.cr` 扩到 3 例：S1 解析；锁定复用（exit 0、无 `Resolving`/`Fetching`、`PLUGIN SOURCE` 与 `bundler (4.0.24) sha256=` 保留）；缺插件（exit 15、`No plugin sources available for mpath`、锁不变）。3 examples / 0 failures / 0 errors / 0 pending。
- 新增 `fixtures/differential/plugin-source-locked/`（预置带 `PLUGIN SOURCE` 的锁 + `extra/.bundle/plugin/**`，`command`=`lock`，`file-equals-4.0.24`/`file-equals-2.7.2` 逐字断言）与 `plugin-source-locked-missing/`（同锁、无 `extra/.bundle`，期望参考 exit 15）。
- 差分：4.0.24 `plugin-source-locked` PASS exit 0、`plugin-source-locked-missing` PASS exit 15（2 passed / 0 failed / 0 skipped）；2.7.2 同两项 2/0/0。回归 `plugin-source-typed`/`plugin-install`/`plugin-uninstall`/`install-fresh`/`install-local`/`install-check`/`lock-noop` 双 profile 均 7 passed / 0 failed / 0 skipped。

**门禁**：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有两条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；暂存后 `git diff --cached --check` EXIT 0（无输出）。

**区分力自证**：新增 `fixtures/differential/plugin-source-locked-check/`（同锁与插件，`command`=`check`）。用 `87a69a4` 的 worktree 编译 pre-29 二进制（`C:/temp/cel29check`）跑该夹具：

```
FAIL plugin-source-locked-check (check)
      exit code: reference=0 celerite=1
      stdout differs:
    1d0
    < The Gemfile's dependencies are satisfied
      stderr differs:
    0a1,3
    > The following gems are missing
    >  * stub-gem (1.0.0)
    > Install missing gems with `bundle install`
```

4.0.24 与 2.7.2 均如此；换当前二进制后两 profile 均 `PASS plugin-source-locked-check (exit=0)`。说明该夹具确实落在 S2 的「锁定插件 spec 视为已安装」路径，而非求值期。`plugin-source-locked`（`command`=`lock`）仍保留，但仅验证无操作锁重写，不具 S2 区分力。

**已声明差异/未验证**：安装路径（S3）的参考行为（exit 7，缺 `bundler-source-mpath`）我方仍 exit 0 完成安装——属 `@inferred_plugins` 预装 pass，`commands_install.cr:111-116` 明确不在本轮；`check` 在锁定插件 source 上我方仍会打印 `Resolving dependencies...`（参考无），故夹具只用 `lock`；缺插件的 `install` 未加夹具（仅 oracle 记录）；插件 source 的 `checksum`/非空 `options_to_lock` 未覆盖；未跑全量 spec 与全量差分。checkbox 保持 `[ ]`。

## 2026-11-19（L163 收口：README、兼容矩阵与 roadmap 同步）

本轮仅改文档，未改产品代码，未重跑全量门禁。

### README（A1–A7）

- A1：参考 Bundler 安装拆成 `gem install bundler -v 4.0.24` 与 `gem install bundler -v 2.7.2` 两条命令。
- A2：差分环境改为分层表述——多数夹具离线，`http-index` 夹具启动 `127.0.0.1` 回环服务；Low-IL Windows 下部分 git 源夹具 `0xC0000022`；两项 2.7.2 文档化 deferred（`gem-default`、`gem-no-git`；marker `deferred-2.7.2`，`script/differential:620-621`）。
- A3：断言清单补 `file-equals`、`installed-tree`、`first-line`，锚点 `script/differential:488-551`。
- A4：Status 补入安装期 Ruby/RubyGems 复核（`src/celerite/installer.cr:65-90`）、空 CHECKSUMS 回填（`src/celerite/definition.cr:362`）、installed-spec 发现（`src/celerite/cli/commands_surface.cr:860-885`）、typed source 的 S1+S2（`src/celerite/resolution.cr:1366`、`:1488`），并明确 S3 安装路径未实现。
- A5：兼容矩阵来源改为 hand-collected + 采集日期，不再是“generated from pinned upstream sources”。
- A6：Development 增补本机前置：`HOME`/`TMP`/`TEMP`/`TMPDIR` 指向工作区内，否则出现与产品无关的沙箱错误。
- A7：上游套件声明补当前基线 `64 examples / 54 failed`（2026-11-19 采集）。

### 兼容矩阵（B）

- `script/gen-cli-baseline 4.0.24 2.7.2` 已重跑：正文与 2026-11-07 基线逐字相同；相对 HEAD 的差异仅为删除手写的 4 行头注并加入生成器自有 scope 行，证明 `--help` 正文确实未变。
- 生成文件头注现由生成器 `script/gen-cli-baseline:39-40` 输出（静态、不带日期），重跑幂等；提交后复跑 `git status --short docs/compat-matrix` 为空（见提交正文实测）。
- `upstream-lockfile-v4.0.24.md` 头注说明 iteration-2 的 `64/64` 为历史基线；文末新增 2026-11-19 当前基线（64/54，artifice 37 / low-il 8 / fetch 6 / product 3，missing-gem 0），并标注该快照早于 task-25…29、product 候选未确认。
- `script/gen-version-oracle` 只生成 `spec/fixtures/version_oracle.txt`，与本轮 CLI 矩阵无关，未使用。

### roadmap（C）

- L154 记 task-21 安装期复核已落地；剩余为复核差分夹具与多 ABI/多 Ruby 矩阵（本机仅 4.0.6）。
- L155 记 task-22 installed-spec 发现已对齐；剩余为 `check --dry-run` 无 oracle、`info` default-gem 未验证。
- L156 记 `--edit`/`--bundle` 的显式 exit 1 是**已声明不支持边界**（参考会打开编辑器/自动安装），不是参考对齐；修正了任务书“记为参考对齐”的措辞，避免虚假声明。
- L159 收窄为 S3 安装路径验收断言（`@inferred_plugins` 预装 pass、`commands_install.cr:111-116` 处置、旧二进制 FAIL / 新二进制 PASS）。
- L161 上游基线更新为 64/54；`rspec-output.json` 早于 task-25…29，空 CHECKSUMS 候选疑已修复但**未确认**。
- L162 复跑条件明确为非 Low-IL 宿主并重新采集 JSON。
- L163 拆为 README A1–A7、matrix B、roadmap C 三组。

### 更正上节（task-29）过时表述

上节末尾“`check` 在锁定插件 source 上我方仍会打印 `Resolving dependencies...`”已被 task-29 返工推翻：返工后 `check` 输出与参考逐字一致（stdout 仅 `The Gemfile's dependencies are satisfied`，stderr 空），并新增 `plugin-source-locked-check` 夹具在 `87a69a4` 旧二进制 FAIL、当前二进制 4.0.24/2.7.2 均 PASS。以本条为准。

**仍未同步/未验证**：compat-report 各历史节的旧基线数字未逐节改写（仅头注/文末标注）；全量 `crystal spec` 与全量差分未重跑；2.7.2 upstream profile 不可执行；上游 product 候选三条未复跑定性。

## 2026-11-19（M7(6) task-31：typed plugin source 安装成功路径）

范围：S3 切片——`install` 对已安装 typed plugin source（`source "./stub-path-gem", type: :mpath`）的成功路径：解析 `@inferred_plugins` 依赖、调用插件的 `install(spec, opts)`、把 gem 落盘到 bundle、输出 post-install 消息，并在 lock 中隐藏推断出的 `bundler-source-<type>` 依赖。未改 S1/S2 的锁读写语义。

参考 oracle（4.0.24 与 2.7.2，干净 lock + 已装插件；`plugin-source-install` 夹具同形）：

```
Fetching source index from file:///C:/.../t31index/
Resolving dependencies...
Fetching bundler-source-mpath 1.0.0
Installing bundler-source-mpath 1.0.0
Bundle complete! 1 Gemfile dependency, 1 gem now installed.
Bundled gems are installed into `...`
Post-install message from stub-gem:
Installed stub-gem
```

- 2.7.2 同一流程唯二差异：`Bundle complete! ... 2 gems now installed.`，且插件 gem 在 `.bundle/plugin/gems/bundler-source-mpath-1.0.0` 解包；4.0.24 只保留 `.bundle/plugin/cache/*.gem` 与 `.bundle/plugin/specifications/*.gemspec`（空 `build_info/doc/extensions/gems/plugins` 目录）。
- install 后 lock：`PLUGIN SOURCE` 不变、`GEM` specs 为空、`DEPENDENCIES` 只剩 `stub-gem!`（`bundler-source-mpath` 被隐藏）；4.0.24 写 CHECKSUMS，2.7.2 不写。
- 参考契约：`plugin/dsl.rb:39-49` 为 typed source 注入 `bundler-source-<type>` 依赖（`@inferred_plugins`）；`plugin/api/source.rb:90-92` 默认 `install` 抛 `MalformattedPlugin`；`installer/gem_installer.rb:67-75` 调 `source.install(spec, force:, local:, build_args:, previous_spec:)` 并把返回值作为 post-install 消息。

实现（`assets/bridge/server.rb`、`src/celerite/bridge/client.cr`、`src/celerite/resolution.cr`、`src/celerite/cli/commands_install.cr`）：

- 新桥操作 `plugin_source_install`（server.rb 约 :537）：只设 `Bundler.instance_variable_set(:@bundle_path, ...)`（不写 `.bundle/config`），按 `uri` 找插件 source、按 `full_name` 找 spec，调插件 `install`，返回消息。
- `commands_install.cr`：安装前从 `evaluation.sources` 的 `"Plugin"` 源推导 `bundler-source-<type>` 并调用 `resolution.add_inferred_plugin_dependencies!`，因此与参考一样先 `Resolving dependencies...` 并安装插件 gem；插件 spec 未安装时调桥安装，收集消息；`hide_inferred_plugins!` 后从本次解析结果中剔除推断依赖（GEM/DEPENDENCIES/CHECKSUMS 三处），loader 不再把它写进 lock；安装后在 summary 与 Bundled-gems 行之后打印 `Post-install message from <name>:`。
- 删除了旧 `Installing plugin sources … is not supported` 分支（`commands_install.cr:111-116` 原位置）；该路径现由 S3 覆盖。2.x 额外把插件 gem 解包到 `.bundle/plugin/gems`（`op_write_installed_spec` 的 `unpack`）。
- `decisions_to_specs` 对非 GEM source 使用 `source.remote`（此前误用主 GEM 索引 URL，导致桥报 `plugin source not found: file:///.../index/`）。

夹具与证据：

- 新增 `fixtures/differential/plugin-source-install/`（`Gemfile`、干净 `Gemfile.lock`、`command=install`、`extra/.bundle/plugin/**`、插件源码、`file-equals-4.0.24/2.7.2`）；新增 `fixtures/gem-index-plugin-source/`（含 `bundler-source-mpath-1.0.0.gem` 的 legacy index）；`script/differential` 新增 `@PLUGIN_SOURCE_INDEX_DIR@` 替换。
- 差分：`plugin-source-install` 在 4.0.24 与 2.7.2 均 `PASS (exit=0)`。
- 反假绿：`git worktree add C:/temp/celerite-pre31 ce58d1f` 重建二进制后同夹具 `FAIL`（缺 `Fetching/Resolving/Installing` 行、缺 post-install 消息与 `.bundle/plugin` 目录）；当前二进制 PASS。
- 回归（双 profile 各 6/0/0）：`plugin-source-typed`、`plugin-source-locked`、`plugin-source-locked-check`、`plugin-source-locked-missing`、`plugin-install`、`install-fresh`。
- spec：`spec/m7_plugin_source_typed_spec.cr` 共 5 例（新增 install 成功断言：exit 0、stderr 空、post-install 消息、lock 无 `bundler-source-mpath`），5/0/0/0。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅 2 条既有 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check` EXIT 0。

已声明差异与未验证：

- 干净 lock、未带 CHECKSUMS 时，`install` 不主动创建 CHECKSUMS（与本次 harness 参考一致；手工环境差异已用夹具固定为无 CHECKSUMS 形态）。
- spec 未断言 bundle 内落盘路径（Crystal `Dir.glob` 在 Windows 反斜杠路径上不稳定），落盘由差分 `installed-tree` 比较覆盖。
- 全量 `crystal spec` 与全量差分未重跑；多平台/多 Ruby ABI 未验证；`commands_install.cr:111-116` 删除后是否有其他调用方依赖该错误文案未做全仓检索。
- 2.7.2 的插件 gem 解包行为仅在 oracle 与差分树中观察，未做逐文件内容比对（file-equals 只覆盖 lock）。

## 2026-11-19（M7 L161 task-32：上游 lockfile 基线二次重采集与 product 候选定性）

范围：测量 + 文档，不改产品代码。HEAD `f4c5aac`；采集命令 `CELERITE_SKIP_TEST_DEPS=1 bash script/upstream-specs`（MSYS bash、`TMPDIR=/c/temp`、重建 `bin/celerite.exe`）。

结果（`.upstream-specs/upstream-lockfile-v4.0.24-20261119T082530Z.md`，`rspec-output.json` 生成于 2026-11-19 16:32:01 +08:00）：

| 指标 | 当前值 |
|---|---|
| 结果 | `64 examples, 54 failures`（10 passed），rspec exit 1 |
| real-drive | 58 |
| 分桶 | artifice 38 / low-il 8 / fetch-failed 6 / product 2 |

逐桶对比（task-23 基线 → 本轮）：

| 桶 | task-23 | task-32 | 变化原因 |
|---|---|---|---|
| artifice-unreachable | 37 | 38 | 候选 ① 移入：`Could not reach host gem.repo2`（`rspec-output.txt:3393`） |
| low-il-shm | 8 | 8 | 环境未变 |
| fetch-failed | 6 | 6 | 未变 |
| missing-gem-files | 0 | 0 | task-23 修复保持 |
| product:candidates | 3 | 2 | ① 移出，②/③ 保留 |

候选定性：

1. ① `fills empty CHECKSUMS entries...`：**未通过、未验证**。现落 env:artifice；task-25 后空 CHECKSUMS 触发重解析并尝试访问 `https://gem.repo2`，artifice 仅进程内可达。sha256 回填本身已由 task-25/26 差分覆盖，但上游例无法在本环境判定。
2. ② `is conservative with dependencies of git gems`：**真产品候选（未修）**。期望 `v4.0.8` / `788d10f2…` / `ckeditor (4.0.8)`，实得 `v4.0.7` / `b8909d5…` / `ckeditor (4.0.7)`（失败 diff，`rspec-output.txt:2785` 起）。上游 `spec/lock/lockfile_spec.rb:658`；最小复现：本地仓库打 v4.0.7、v4.0.8 两 tag，Gemfile 以 `tag: "v4.0.8"` 引用，`celerite install` 后查看 lock。
3. ③ `keeps existing platforms in the lockfile`：**真产品候选（未修）**。参考保留 `java` 并补本地平台；celerite 报 `Your bundle only supports platforms ["java"] but your local platform is x64-mingw-ucrt. …`（`rspec-output.txt:3260`）。上游 `spec/lock/lockfile_spec.rb:1222`；最小复现：lock 仅 `PLATFORMS java` + `gem "myrack"`，执行 `celerite install`。

结论：product 候选 3 → 2 不是“修好一条”，而是候选 ① 的失败点被 artifice 环境前移；② git tag 选择、③ 缺失本地平台补全是两条独立真产品候选。按本轮 scope 只回报、未动代码。

未验证：完整 `install_test_deps` 链、非 Low-IL 宿主、真实 gem 源；候选 ① 的上游通过/失败证据；②/③ 的独立最小复现已给出命令骨架但未在隔离项目逐字执行。

## 2026-11-19（M7(6) task-33：非 frozen 自动补本地平台）

本轮修 task-32 产品候选 ③：非 frozen 模式下，锁文件只列其他平台时不再拒绝，而是在生成锁文件时补上当前本地平台；frozen 模式保持参考的拒绝文案与 exit 16。

参考锚点：
- `.upstream-specs/v4.0.24/bundler/lib/bundler/definition.rb:150`：`@current_platform_missing = add_current_platform unless Bundler.frozen_bundle?`，Definition 构造时即把本地平台加入 `@platforms`。
- 同文件 `:524-530` `validate_platforms!`：`current_platform_locked?` 已为真则返回；`:844-848` `current_platform_locked?`、`:850-858` `add_current_platform`。
- `:797` `@new_platforms.each` 与 `lockfile_generator.rb:20`、`:54` 起负责把新增平台写回 `PLATFORMS`；`cli/install.rb:46`、`cli/check.rb:16` 调 `validate_runtime!`，`cli/check.rb:33` 在满足时 `definition.lock(true)`。
- 2.7.2 安装包 `bundler-2.7.2/lib/bundler/definition.rb` 同形（`:140` 附近、`:499-505`、`:812-826`）。

oracle（4.0.24 与 2.7.2 逐字一致，仅 `BUNDLED WITH` 缩进/安装计数不同；`file:///C:/…/.tmp-scratch/t33index` 全量索引 + 预置 `PLATFORMS\n  java` + 已装 stub）：
- (a) 非 frozen `install`：exit 0；stdout `Fetching source index from file:///…/`、`Resolving dependencies...`、`Bundle complete! 1 Gemfile dependency, 1 gem now installed.`、`Bundled gems are installed into \`./bundle\``；锁 `PLATFORMS` 变为 `java`、`x64-mingw-ucrt`（按字母序，无 `mingw` 泛化项）。
- (b) `BUNDLE_FROZEN=true install`：exit 16；stderr 三行原文 `Your bundle only supports platforms ["java"] but your local platform is\nx64-mingw-ucrt. Add the current platform to the lockfile with\n\`bundle lock --add-platform x64-mingw-ucrt\` and try again.`；锁不变。
- (c) 非 frozen `check`：exit 0；stdout `Resolving dependencies...`、`The Gemfile's dependencies are satisfied`；check 也把 `x64-mingw-ucrt` 写回锁（`cli/check.rb:33` 的 `definition.lock(true)`）。
- (d) 本地平台即 `x64-mingw-ucrt`，未归一成 generic `mingw`。

实现：
- `src/celerite/definition.cr:125-139` `validate_platforms!` 在 `!config.frozen?` 时直接返回（等价参考构造期已补本地平台），frozen 分支保持原文案与 exit 16。
- `src/celerite/cli/commands.cr:1500-1521`（`run_check` 满足分支前）：非 frozen、非 `--dry-run`、`platform_missing?` 且 `check` 成功时，把本地平台追加进已解析的 `PlatformsSection`、排序并用 `Lockfile.write` 落盘；不重新解析、不重复 `Fetching`。
- 既有 `Resolution#generated_lockfile`（`src/celerite/resolution.cr:1620-1660`）本就保留旧平台并补 `Gem::Platform.local`、排序后写 `PLATFORMS`，因此 install 侧无需另改；未触碰平台解析/变体选择。

夹具与反假绿：
- `fixtures/differential/install-platforms-add-local/`：`file:///@LEGACY_INDEX_DIR@` + `json_pure`，锁预置 `PLATFORMS java`，`command=install`，`file-equals-4.0.24`/`-2.7.2` 断 `java`、`x64-mingw-ucrt` 与各自 `BUNDLED WITH` 缩进。
- `fixtures/differential/install-platforms-frozen-error/`：同输入 + `frozen` 标记，断 exit 16、stderr 原文、锁不变（`file-equals`）。
- 新 `fixtures/gem-index-legacy/`：只含 `json_pure-2.8.1.gem` 的全量索引（`specs.4.8.gz` 等），供 `file://` 参考侧使用；`script/differential` 新增 `@LEGACY_INDEX_DIR@` 替换。
- 反假绿：`git worktree add C:/temp/celerite-pre33 c885275` 编译旧二进制后跑同一夹具，4.0.24 与 2.7.2 均 `FAIL install-platforms-add-local`（旧侧 exit 16，stdout 全缺、锁缺 `x64-mingw-ucrt`），`PASS install-platforms-frozen-error`（该行为本就一致，只作回归）。当前二进制双 profile 两夹具均 PASS（2 passed / 0 failed / 0 skipped）。

回归与门禁：
- 差分双 profile：`platform-ruby-mismatch`、`platform-variant-fail`、`install-frozen`、`lock-noop`、`install-fresh`、`install-check`、`lock-print` 均 7 passed / 0 failed / 0 skipped。
- `spec/m7_platform_auto_add_spec.cr` 2 examples 0 failures（非 frozen 不抛、frozen 原文案）；与 `spec/m7_platform_spec.cr` 合计 5 examples 0 failures；`m7_lockfile_*` + `m7_no_lockfile_commands` + `m7_path_lockfile_relative` 23 examples 0 failures。
- `crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有 2 条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --cached --check` 与 `git diff c885275..HEAD --check` 均为空（EXIT 0）。

上游单例：在 `.upstream-specs/v4.0.24/bundler` 定向跑 `spec/lock/lockfile_spec.rb:1222`，1 example / 1 failure，失败点是 `Could not reach host gem.repo2. Check your network connection and try again.`（artifice 进程内网络桩），发生在平台断言之前，故该上游例仍未验证；product 候选 ③ 的关闭证据来自上述独立 oracle/差分，不改写上游基线计数（仍 64/54）。

已声明差异：
- `check` 仅补写 `PLATFORMS` 段，不做参考 `definition.lock(true)` 的全量重序列化；现有锁的其余内容保持逐字不变（对本次场景等价）。
- 未复跑完整上游 64 例；未在非 Windows 宿主验证 generic platform 形态（本机仅 `x64-mingw-ucrt`）。
- 平台校验仍以 `Gem::Platform.local.to_s` 为本地值；参考经 `Bundler.local_platform` 的 `===` 匹配，本次四种形态（java-only、已含本地、frozen、check）已对齐，其他变体未覆盖。

## 2026-11-19（M7(6) task-34：Git source 变化必须重解析）

本轮关闭上游 product 候选 ② 的“source 变了却复用旧锁”缺口：锁钉 `tag: v4.0.7`、Gemfile 改成 `tag: v4.0.8` 时，参考会重新解析并把锁 bump 到新 revision/tag/版本；Celerite 之前只比较依赖 requirement 与 GEM remote，仍走锁短路。

参考语义：
- `.upstream-specs/v4.0.24/bundler/lib/bundler/source/git.rb:26`：`@ref = options["ref"] || options["branch"] || options["tag"]`。
- 同文件 `:76-81` `eql?`：比较 uri、ref、glob、submodules；source 不同则锁定 spec 不能复用。
- 上游用例 `.upstream-specs/v4.0.24/bundler/spec/lock/lockfile_spec.rb:658-742`（`is conservative with dependencies of git gems`）：锁 `tag: v4.0.7`/`ckeditor (4.0.7)`，Gemfile `tag: v4.0.8`，一次 `bundle lock` 后期望 `revision: <v4.0.8>`、`tag: v4.0.8`、`ckeditor (4.0.8)`；依赖保守性指 `orm_adapter`，不是 revision。

我方旧缺口：
- `src/celerite/resolution.cr:884-913` `reuse_locked_resolution?` 只比依赖 requirement、`lockfile_covers_dependencies?`、GEM remote、本地平台/Ruby。
- 同文件 `:962-969` `sources_compatible?` 对非 GEM 段 `next true`，GIT/PATH/PLUGIN 的 tag/ref/branch/glob/submodules/type 全部放行。
- `src/celerite/cli/commands.cr:2367-2371` 的 `lock` no-op 分支在到达解析前也会原样重写锁，是第二处短路。

实现：
- `src/celerite/definition.cr:195-232`：`source_diff` 产出 Gemfile↔锁标签差异并以 `* name from` 行给出名称；新增公开 `dependency_sources_changed?`、`changed_dependency_sources`。
- 同文件 `:280-303`：`git_label` 增加 `submodules`，`path_label` 增加 `glob`，`plugin_label` 增加 `type`；Gemfile 侧与锁侧标签同源比较，未另造字符串规则。
- `src/celerite/resolution.cr:806-812`：解析前把变化 source 的依赖名加入 `@excluded_locked_names`，旧锁定 spec 不再喂给 solver；`:917` 在复用闸门直接返回 false。
- `src/celerite/cli/commands.cr:2367-2371`、`:2429-2433`：`lock` 的 no-op 与 `lockfile_current` 都要求 source 未变化，source 变化时打印 `Resolving dependencies...` 并走解析。

构造态证据（`.tmp-scratch/t34`，本机 git 子进程受限）：
- 预置仓库 `repo`：v4.0.7 `6006d4b73e2a3c1d2f87dcef2948fcc7cc6bf4ff`，v4.0.8 `072aeca2b961e1668a82c5e330b2ac67fff5b778`；项目 Gemfile `tag: v4.0.8`，锁钉 `tag: v4.0.7`。
- 参考 4.0.24 `bundle lock`：exit 0，stdout `Writing lockfile…`、`Fetching file:///…/repo`×2、`Resolving dependencies...`；锁 bump 到 v4.0.8 revision/tag 与 `ckeditor (4.0.8)`。
- 旧 Celerite 二进制：exit 0，stdout 仅 `Writing lockfile…`，锁逐字不变（候选 ② 复现）。
- 修复后：不再被 no-op 短路，进入解析并尝试 `git clone --mirror`；本机 msys `sh.exe` 在 Low IL 下 `NtCreateDirectoryObject(...): 0xC0000022`，git clone 以 `Could not read from remote repository` 失败，故端到端 bump 在本机不可执行。参考侧同一构造态可完成，说明判据方向正确、环境阻塞在 git 子进程。
- 因此**不新增差分夹具**：共享一份预置缓存也无法让 Celerite 侧绕过 `git fetch/rev-parse`，夹具会因本机环境恒失败；改用 spec 覆盖标签判据，并在本文件声明该限制。

测试与反假绿：
- 新增 `spec/m7_git_source_reuse_spec.cr` 4 examples 0 failures：tag 不同→不复用；tag 相同→复用；ref/branch/glob/submodules 各自不同→不复用；PATH glob 不同→不复用。
- 反假绿：`git worktree add C:/temp/celerite-pre34 b350607` 后把该 spec 复制进旧树运行，4 examples / **3 failures**（tag、ref/branch/glob/submodules、PATH glob 三例失败；tag 相同例仍通过），证明覆盖到旧行为。
- 回归（双 profile）：`lock-noop`、`install-fresh`、`install-check`、`install-local`、`lock-print`、`install-frozen`、`install-platforms-add-local`、`plugin-source-typed`、`plugin-source-install`、`checksums-empty-install` 均 10 passed / 0 failed / 0 skipped。
- 定向 spec：`m7_git_source_reuse` + `m7_lockfile_*` + `m7_platform_*` + `m7_no_lockfile_commands` + `m7_installed_discovery` 共 65 examples / 0 failures / 0 errors / 0 pending。
- 门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅既有 2 条 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check`、`git diff b350607..HEAD --check`、`git diff --cached --check` 均 EXIT 0。

上游单例状态：本轮**未复跑** `lockfile_spec.rb:658` 单例；上一轮 task-32 的封闭环境仍会先被 artifice `gem.repo2`/本机 git `0xC0000022` 挡住。故上游基线仍记 64 examples / 54 failures；product 候选 ② 的真实状态是「代码判据已修、构造态参考侧已 bump、我方端到端与上游单例未验证」，不宣称上游通过，也不把 2→1→0 写成已清零。

已声明差异：
- GIT 的 `glob` 已纳入标签，但 GIT glob 端到端（真实 clone）未验证；PATH/PLUGIN 的标签比较只覆盖本文件列出的字段。
- 构造态验证使用手工预置仓库；`0xC0000022` 是本机 Low-IL 环境缺陷，非产品逻辑。
- 未重跑完整上游 64 例，未在非 Windows/非 Low-IL 宿主验证 git 端到端。

## 2026-11-19（M7(8) task-35：`bundle check` 成功落盘与失败三元组）

范围：`bundle check` 在依赖满足时是否按参考 `definition.lock(true)` 持久化锁文件，以及解析/来源失败时是否输出参考的 "can't satisfy" 两条错误并 exit 1。参考锚点：4.0.24 `bundler/cli/check.rb:20-36`（成功分支 `definition.lock(true) unless options[:"dry-run"]`；异常分支 rescue `GemNotFound, GitError, SolveFailure` → 两行 stderr + exit 1）、`definition.rb:379-433`（`lock`/`write_lock`；`lockfiles_equal?` 时只 touch）、`definition.rb:1257-1269`（`preserve_unknown_sections` 下忽略 `BUNDLED`/`RUBY` 等段）；2.7.2 同形实现。

### oracle（4.0.24 与 2.7.2，隔离 HOME/BUNDLE_PATH，`file://` legacy 全量索引）

| 场景 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| 已满足、仅 `BUNDLED WITH` 过期（4.0.20/2.7.1） | exit 0，`The Gemfile's dependencies are satisfied`，锁哈希不变、BUNDLED 保留 | 同左 |
| 同上 + `--dry-run` | exit 0，输出同上，锁哈希不变 | 同左 |
| `PLATFORMS` 仅 `java`（本机 `x64-mingw-ucrt` 缺失） | exit 0，stdout `Resolving dependencies...` + satisfied；锁改写为 `java` + `x64-mingw-ucrt`，BUNDLED 更新为 4.0.24 | 同左，BUNDLED 更新为 2.7.2（3 空格） |
| 锁含 `CHECKSUMS` 但缺 `bundler` 行、BUNDLED 4.0.20 | exit 0，仅 satisfied；补 `bundler (4.0.24) sha256=16ca64e2…`，BUNDLED 4.0.24；哈希 `b18fa748…`→`cb2bc36d…` | 该锁形态下输出 `Resolving dependencies...` + satisfied，锁哈希不变 |
| 无锁、缺失 gem / 需求冲突 / 不存在 git 源 | exit 1；stdout 一行 Fetching；stderr 逐字 `Bundler can't satisfy your Gemfile's dependencies.` + `Install missing gems with \`bundle install\`.`；不写锁 | 同左 |

关键结论：**仅 `BUNDLED WITH` 过期不会引起内容改写**（参考只 touch）；有实际语义变化（平台/校验和）才重写。新实现按 `semantic_content` 比较忽略 BUNDLED 版本行，避免把 touch 变成重写。

### 实现锚点

- `src/celerite/resolution.cr:1570-1581` 新增 `lockfile_rewrite_text`：未解析且有锁文件时 `materialize_locked` 后 `generated_lockfile.to_lock`，不发起新解析。
- `src/celerite/cli/commands.cr:1500-1524` 成功分支统一为“解析后文本或锁复用文本 → `with_profile_indent` → 语义比较 → 写入”；`bridge_available?` 为假时跳过（无 Ruby 桥时的既有 fail-safe，已声明）。`--dry-run` 与 frozen 不写。
- `src/celerite/cli/commands.cr:1437-1445` 包住无锁路径的 `resolution.resolve!`，捕获 `GemNotFoundError | SolveFailureError | GitError` 后打印参考两条 stderr 并返回 1。
- `src/celerite/errors.cr:198-208` 新增 `GitError`（status 11，镜像 `Bundler::GitError`）；`src/celerite/git_source.cr:113-124` 将 `git` 子进程启动失败/非零退出包装为 `GitError`（不再落到 `celerite internal error`）。

### 测试与反假绿

- `spec/m7_check_rewrite_spec.cr`：3 examples（成功重写平台+BUNDLED、`--dry-run` 保持、triplet 失败）。目标 spec 合计 65 examples / 0 failures（含 `m7_check_*`、`m7_lockfile_*`、`m7_platform_*`、`m7_installed_discovery`）。
- 差分夹具：`check-rewrites-lock`（`file-equals-4.0.24`/`-2.7.2`）、`check-dry-run-keeps-lock`（`file-equals` 保持原锁）、`check-triplet-missing-index`（exit 1 + 两行 stderr）。双 profile 各 **3 passed / 0 failed / 0 skipped**。
- 回归（双 profile）：`install-check`、`lock-noop`、`lock-print`、`install-fresh`、`install-platforms-add-local`、`plugin-source-locked-check`、`checksums-empty-install`、`install-frozen`、`install-deployment-empty-checksums` 连同 3 个新夹具 → **12 passed / 0 failed / 0 skipped**。
- 反假绿：`git worktree add C:/temp/celerite-pre35 1d3eacb` 编译旧二进制；`check-rewrites-lock` 在旧代码上 **FAIL**（`Gemfile.lock` cel 侧仍为 `4.0.20`，参考/期望为 `4.0.24`）；当前二进制 PASS。

### 已声明差异 / 未验证

- 无 Ruby 桥（`CELERITE_BRIDGE_SERVER` 与 `CELERITE_REFERENCE_BUNDLER_LIB` 均缺失）时跳过成功落盘；参考仍会写锁。这是既有 fail-safe，spec 明确覆盖。
- triplet 的“不存在 git 源”场景 stderr/exit 已对齐，但 stdout 少参考的 `Fetching file:///…/repo` 一行（本机 `git` 子进程受 Low-IL `0xC0000022` 影响）；未做夹具。
- 2.7.2 对含 `CHECKSUMS` 的锁执行 `check` 时会打印 `Resolving dependencies...` 且不改写；该组合未纳入差分夹具。
- 未重跑全量 `crystal spec` / 全量差分；未在非 Windows/非 Low-IL 宿主验证。

## 2026-11-19（M7(8) task-36：path 源默认 glob 与失败归属）

参考锚点：`bundler-4.0.24/lib/bundler/source/path.rb:14`（`DEFAULT_GLOB = "{,*,*/*}.gemspec"`）、`:19`（`options["glob"] || DEFAULT_GLOB`）、`:45-49`（默认 glob 不写锁）、`:52-54`（`to_s` = ``source at `<path>` ``）；`source/git.rb:15` 同默认值；`resolver/base.rb:115-118`（锁内 spec 的 source 变化且新 source 无匹配 spec 时抛 `GemNotFound`，消息含 `ls.source`）；`resolver.rb:336,361`（未命中消息用依赖所属 source，而非主 rubygems remote）。

oracle（4.0.24 与 2.7.2 逐字相同；`file://` 全量索引 + `path "vendor/mono"` 不写 `glob:`）：

| 布局 | 结果 | 说明 |
|---|---|---|
| A `vendor/mono/mono_a.gemspec` | exit 0 | PATH 段 `remote: vendor/mono` + `specs: mono_a (0.1.0)` |
| B `vendor/mono/gems/mono_a.gemspec` | exit 0 | 默认 glob 命中 `*/*.gemspec` |
| C `vendor/mono/gems/mono_a/mono_a.gemspec` | exit 7 | stderr `Could not find gem 'mono_a' in source at \`vendor/mono\`.` |
| D 同目录 `mono_a` + `mono_b` 两个 gemspec | exit 0 | 只锁 `mono_a (0.1.0)`，不因多 gemspec 报错 |
| E `vendor/mono/d1/mono_a.gemspec` | exit 0 | 深度 1 命中 |
| E2 `vendor/mono/d1/d2/mono_a.gemspec` | exit 7 | 深度 2 不命中，路径源归属文案同 C |
| F `gems/*/*.gemspec` 显式 glob + C 布局 | exit 0 | 锁多写 `glob: gems/*/*.gemspec` |

实现：
- `assets/bridge/server.rb`：新增 `SOURCE_DEFAULT_GLOB = "{,*,*/*}.gemspec"`（注释要求与 `Resolution::DEFAULT_GLOB` 同步），`op_load_gemspec_dir` 的 fallback 由 `{,*}.gemspec` 改为该常量。
- `src/celerite/resolution.cr`：`load_source_gem_spec` 在 glob 为 nil 时显式传 `DEFAULT_GLOB`，不再依赖桥的 fallback；`make_source` 为 PATH 依赖构造 `source_descriptions`（`source at \`<remote>\``）。
- `src/celerite/resolver/source.cr`：`ResolutionSource` 接受可选的 `source_descriptions`，`source_description(package)` 先按包名查该表，未命中才回落到 rubygems remote 文案；GIT/PLUGIN 归属仍保持原 rubygems 文案（已声明未改）。

测试与反假绿：
- 新夹具 `path-glob-default-root`（A，`file-contains` PATH 段）、`path-glob-default-nested`（B，`file-equals-4.0.24`/`-2.7.2`）、`path-glob-default-deep-miss`（C，`stderr-contains` 路径源文案 + exit 7）。双 profile 各 **3 passed / 0 failed / 0 skipped**。
- 回归双 profile 各 **10 passed / 0 failed / 0 skipped**：`path-glob-monorepo`、`install-local`(7)、`install-fresh`、`lock-noop`、`lock-print`、`install-check`、`install-frozen`(15)、`check-rewrites-lock`、`install-platforms-add-local`、`plugin-source-install`。
- `spec/m7_path_glob_default_spec.cr` 2 examples；与 `m7_source_lock_options`、`m7_path_*`、`m7_lockfile_*`、`m7_check_*` 成组运行 **43 examples / 0 failures / 0 errors / 0 pending**（隔离 HOME 后；全局 `~/.bundle/config` 的 `BUNDLE_PATH: vendor/x` 会让 `m7_path_system_spec` 4 例在共享 HOME 下假失败，属环境）。
- 反假绿：`C:/temp/celerite-pre36` 检出 `ab1c866` 编译旧二进制；B 正例旧代码 **FAIL**（exit 7，`in rubygems repository`），C 负例旧代码 stderr 为 rubygems 文案而非 `in source at`；当前二进制两例均 PASS。

已声明差异 / 未验证：
- 仅 PATH 归属改为 `source at`；GIT/PLUGIN 的未命中归属仍为 rubygems 文案。
- `file://` 参考索引必须含 `specs.4.8.gz`；compact-only 索引会先得 exit 17（与 task-31 记录一致）。
- E2 及更深布局的 not-found 行为已与参考对照；未为每个深度单独建夹具。
- 私有 source 鉴权、磁盘错误/中断清理仍只能 spec 或未验证；本机 git 族仍受 Low-IL `0xC0000022` 限制；全量 spec/差分未重跑。

## 2026-11-19（M7(8) task-37：`list`/`show`/`info` 在已装 spec、目录缺失时的语义）

参考锚点：`cli/show.rb:23-30`（`full_gem_path` 不存在 → `ui.warn "The gem <name> is missing. It should be installed at <path>, but was not found"`，exit 0）；`cli/list.rb:22-29`（`Bundler.load.specs` rescue `GemNotFound` → `ui.error e.message` + `ui.warn "Install missing gems with \`bundle install\`."`，exit 1）；`cli/info.rb:36-48`（`--path` 与 show 同警告）、`:68-72`（普通 info 在 `installation_missing?` 时把整块 gemspec 信息经 `ui.warn` 写到 stderr，前缀 `The gem <name> is missing. Gemspec information is still available though:`，exit 0）。

oracle（4.0.24 与 2.7.2 逐字相同；预置态 = `bundle-preset/ruby/4.0.0/specifications/json_pure-2.8.1.gemspec` 存在、`gems/json_pure-2.8.1/` 缺失）：

| 命令 | 态一（仅 spec） | 态二（spec 与目录全缺） |
|---|---|---|
| `list` | exit 0，`Gems included by the bundle:` + `  * json_pure (2.8.1)` + `Use \`bundle info\`…` | exit 1，stderr `Could not find json_pure-2.8.1 in locally installed gems` + `Install missing gems with \`bundle install\`.` |
| `list --paths` | 同 list | 同 list |
| `show json_pure` | exit 0，stdout 空，stderr `The gem json_pure is missing. It should be installed at <path>, but was not found` | exit 7，stderr `Could not find json_pure-2.8.1 in locally installed gems` |
| `show --paths json_pure` | 同 show | 同 show |
| `info json_pure` | exit 0，stdout 空；stderr 前缀 + `  * json_pure (2.8.1)` / `\tSummary: …` / `\tPath: …` | exit 7，stderr `Could not find json_pure-2.8.1 in locally installed gems` |

我方实测：`list`/`list --paths`/`show`/`show --paths` 在两态均已逐字对齐；差异只在 `info` 态一——旧实现把 gemspec 信息写到 stdout 且缺“missing”前缀。`info --path` 态一也与 `show --paths` 同形（旧实现缺警告）。

实现：
- `src/celerite/cli/commands.cr` 的 `info` 分支改为先构造整块 gemspec 文本；`!Dir.exists?(gem_dir)` 时先 `stderr.puts "The gem <name> is missing. Gemspec information is still available though:"`，再 `stderr.print` 整块，exit 0；目录存在时仍 `stdout.print`，内容与旧 `puts` 序列逐字一致。
- 同分支的 `info --path` 增加与 `show --paths` 相同的目录缺失警告后返回 0，不再打印路径。

测试与反假绿：
- 新夹具 `list-installed-spec-without-gemdir`（态一 list）、`list-gem-entirely-missing`（态二 list）、`info-installed-spec-without-gemdir`（态一 `info json_pure` + `info --path json_pure`，末次 exit 0）。双 profile 各 **3 passed / 0 failed / 0 skipped**。
- 区分力：`C:/temp/celerite-pre37` 检出 `fb714e9` 编译旧二进制；`info-installed-spec-without-gemdir` 旧代码 **FAIL**（stdout 多出 `  * json_pure…`/`Path:`，stderr 空），当前 PASS；两个 list 夹具在旧代码上同样 PASS，属**非区分性回归夹具**，保留用于防回归。
- 回归双 profile 各 **8 passed / 0 failed / 0 skipped**：`check-installed-spec-without-gemdir`、`check-gemdir-without-spec`(7)、`path-glob-default-nested`、`path-glob-default-deep-miss`(7)、`install-local`(7)、`install-check`、`lock-noop`、`install-fresh`。
- `spec/m7_installed_discovery_spec.cr` 新增 example（info 缺目录 → stderr 前缀+`Path:`，`info --path` → 警告且 stdout 空）；与 `m7_show_*`、`m7_list_*`、`m7_info_checksum_value_spec.cr` 成组 **58 examples / 0 failures / 0 errors / 0 pending**。

已声明差异 / 未验证：
- `list`/`list --paths` 两态本已对齐，本次没有产品改动，仅补夹具；两个 list 夹具无区分力，已在上面标注。
- 未 oracle `info --version` 在目录缺失时的行为（参考不检查目录，直接打印版本；本次未改）。
- 未覆盖“已安装目录存在时的 info”差分（既有 spec 覆盖，未纳入差分）。
- 全量 `crystal spec` / 全量差分未重跑；非 Windows/非 Low-IL 宿主未验证。

## 2026-11-19（M7(3) task-38：锁内 ruby/rubygems 约束的解析证据）

结论：参考在解析阶段同时过滤 `required_ruby_version` 与 `required_rubygems_version`；锁内不兼容版本会被排除并重解，未观察到本轮假设的 install 期拒绝路径。任务书 (d) 的“install 期消息”未复现；参考表现为 SolveFailure（exit 6）或重解。

oracle（4.0.24 与 2.7.2 语义一致；`file:///C:/…` 完整 legacy index，预置锁）：

| 场景 | 参考 exit | 参考结果 | celerite |
|---|---|---|---|
| 锁 `rc_gem (1.0.0)`（`required_ruby_version >= 99.0`），索引另有 0.9.0 | 0 | `Resolving dependencies...`，重解到 `rc_gem (0.9.0)`，锁 0.9.0 | 相同（逐字锁） |
| 锁 `rg_gem (1.0.0)`（`required_rubygems_version >= 99.0`），索引另有 0.9.0 | 0 | 重解到 `rg_gem (0.9.0)`，stdout `Fetching rg_gem 0.9.0 (was 1.0.0)` | 相同 |
| 锁 `only_future (1.0.0)`（ruby >= 99.0） | 6 | `Because every version of only_future depends on Ruby >= 99.0 … version solving has failed.` | 相同 |
| 锁 `only_rg (1.0.0)`（rubygems >= 99.0） | 6 | `Because every version of only_rg depends on RubyGems >= 99.0 …` | 相同 |
| 无锁、双版本 `rc_gem`/`rg_gem` | 0 | 选 0.9.0；`file://` 场景参考 stdout 出现两次 `Resolving dependencies...` | 一次（未纳入夹具） |

参考锚点：`installer.rb:234-245`（`ensure_specs_are_compatible!` 的 install 期检查）、`definition.rb:190-203`（`setup_domain!` 仅在 `install_needed?` 等条件为真时才进入该检查）；本轮构造下参考在解析阶段已排除不兼容版本，故 install 期检查不可达。`source/rubygems.rb` 的候选过滤由解析器完成；现有 celerite 复用排除（`resolution.cr:801` `resolve!` + `incompatible_locked_spec_names`）与之结果一致。

实现：**无产品改动**。非canonical `file://C:/…` 首轮出现的 celerite exit 5 是索引定位伪差；改用 `file:///C:/…` 后旧二进制（`beb46b8`）与新二进制在四个锁内场景均与参考一致，临时 `resolve!` 改动已回退。

测试与证据：

- 新增 `fixtures/gem-index-ruby-versions/`（30 文件，legacy full index：rc_gem 0.9.0/1.0.0、rg_gem 0.9.0/1.0.0、only_rg 1.0.0 等）；`script/differential` 新增 `ruby_versions_index_dir` 与 `@RUBY_VERSIONS_INDEX_DIR@` 替换（7 处 sed + file-equals）。
- 新夹具 `install-ruby-constraint-locked-resolve`、`install-rubygems-constraint-locked-resolve`（`file-equals` 双 profile 锁）、`install-rubygems-constraint-solve-failure`（exit 6、锁不变、`stderr-contains`）。双 profile 各 **3 passed / 0 failed / 0 skipped**。
- 回归双 profile 各 **6 passed / 0 failed / 0 skipped**：`install-locked-ruby-incompatible`(6)、`install-fresh`、`install-local`(7)、`lock-noop`、`install-check`、`check-installed-spec-without-gemdir`。
- 旧二进制（`C:/temp/celerite-pre38`，`beb46b8`）跑新夹具同样 3/0/0 ⇒ 本轮无修复证明，新夹具定位为**回归网**。
- 成组 spec：`m7_ruby_constraints_spec`、`m7_resolver_ruby_constraints_spec`、`m7_ruby_runtime_enforcement_spec`、`m7_install_ruby_compat_spec`、`ruby_version_spec` 共 **40 examples / 0 failures / 0 errors / 0 pending**。

已声明差异 / 未验证：

- 无锁 `file://` 双版本场景参考打印两次 `Resolving dependencies...`，celerite 一次；未纳入夹具。
- install 期 `ensure_specs_are_compatible!` 在本轮构造下不可达，未构造出参考 exit 5；该路径仍仅有 unit 级覆盖。
- 多 ABI/多 Ruby 宿主矩阵未验证（本机仅 Ruby 4.0.6）；全量 spec/全量差分未重跑。

## 2026-11-19（M7(6) task-40：合成规模离线证据链）

结论：新增测试专用合成索引与 interleaved 驱动，在 `file://` 上以 4.0.24 profile 跑 N=20/100/300；三种规模的锁文件与参考逐字一致，k=5 中位锁耗时比为 **1.39 / 1.22 / 1.33**（N=100/300 达标 ≤1.35；N=20 固定启动开销占主导，列为自检点）。install 侧我方随 N 变慢（2.26× / 3.19× / 4.24×），只存基线、不设门——参考侧没有可离线运行的性能套件。

三件套与参考锚点：

- 参考 `file://` 走 marshal 全索引，至少需要 `gems/<full>.gem`、`quick/Marshal.4.8/<full>.gemspec.rz`、`specs.4.8.gz`；缺 gemspec.rz 会 ENOENT，缺 gem 文件会 FileNotFoundError（task-23/task-31 已复现）。
- 本生成器同时产出 compact `info/<name>` 与 `versions`，因此同一索引既可被参考全索引路径读取，也可被我方 compact 路径读取；我方缺 gem 文件时的 404/exit 7 路径见 `src/celerite/compact_index/cache.cr:610` 附近。
- 生成器用 `Gem::Package.build` + `Gem::Indexer.new(out, build_compact: true).generate_index`，两者都来自本机 RubyGems，不是产品路径；脚本头已注明 test-only。
- 参考没有 timing gate：`.upstream-specs/v4.0.24/bundler/spec/realworld/slow_perf_spec.rb:5-16` 标 `realworld: true`，被 `spec/support/filters.rb:23-24` 的 `config.filter_run_excluding realworld: true` 排除，且断言是 `DEBUG_RESOLVER` 的 `Solution found after 1 attempts`，不是耗时。

实现：

- `script/synthetic-index.rb`：`--count N --out DIR`，生成 `synth_0001..N`（版本 1.0.0）三件套及 `Gemfile.fragment`；重复运行会清空并重建目标目录。
- `script/synthetic-scale`：默认 `20 100 300`、`--runs 3`；每轮删除 `Gemfile.lock`/`bundle` 后按奇偶交替先参考后我方（或反之），逐字节比较两份锁；两侧各自安装并核对 `synth_*` 目录与 `.gemspec` 数量必须等于 N；输出中位耗时表并写 `docs/benchmarks/results-<日期>.md`。HOME 保留以复用缓存，首轮为冷启动。锁比对用 Ruby 读二进制（msys 无 `cmp`/`diff`）；结果文件只用 ASCII，避免 msys 管道把 `≤`/破折号写成乱码。
- `spec/synthetic_scale_lock_spec.cr`：N=8、运行时生成索引、不调参考；把索引 URL 归一为 `file:///__INDEX__/` 后与内嵌锁逐字比较；1 example / 0 failures，约 1.5s。

实测（`docs/benchmarks/results-20261119.md`，k=5，interleaved）：

| N | 锁 | 参考锁 ms | 我方锁 ms | 比值 | 参考 install ms | 我方 install ms |
|---|---|---|---|---|---|---|
| 20 | 逐字一致 1621 B | 823 | 1140 | 1.39 | 983 | 2221 |
| 100 | 逐字一致 6982 B | 1028 | 1251 | 1.22 | 1813 | 5782 |
| 300 | 逐字一致 20382 B | 1398 | 1862 | 1.33 | 3549 | 15036 |

- 安装计数三种规模均为 20/20、100/100、300/300。
- 锁长比调研基线更长（6982 vs 5084、20382 vs 14684），原因是合成 Gemfile 固定版本且我方锁带 CHECKSUMS 条目；两侧仍逐字一致。
- k=3 重跑波动达 1.09–1.63（宿主抖动），k=5 更稳定；N=20 的 1.39 已作为自检点写进结果文件。

门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅 2 条既有 `File.executable?` deprecation）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`spec/synthetic_scale_lock_spec.cr` 1 example / 0 failures；`git diff --cached --check` EXIT 0；`git diff 7cf4e6a..HEAD --check` EXIT 0。

已声明差异 / 未验证：

- 真 Rails 规模仍不可验证：需真实网络取依赖图、本机缺 `make`、msys 在 Low IL 下 `0xC0000022` 阻塞原生扩展（分段证据见 `docs/compat-report.md:1925-1933`）。
- 合成索引证明的是「同规模锁与耗时」，不是「真实依赖图复杂度」；install 侧慢的根因未拆到 per-gem RPC/安装开销，仅登记基线。
- 宿主抖动大；N=20 受固定启动开销影响，不作为达标点。全量 spec/全量差分未重跑。

## 2026-11-19（L163 task-39：文档漂移清理）

范围：仅改 README、compat-matrix 与 roadmap 的文案/基线/锚点，不动 `src/`、`fixtures/`、`script/`、`spec/`，不勾选任何复选框；未运行 `script/gen-cli-baseline`（会重生成 CLI 帮助段，非本轮范围）。

逐条核实与修正：
- R1/R4：roadmap L154 原“剩余＝复核路径的差分夹具”已过期——`install-locked-ruby-incompatible` 已存在且双 profile PASS，task-38 又补 3 个约束夹具；L158 默认 glob 已对齐 `{,*,*/*}.gemspec`，C 负例 `path-glob-default-deep-miss` 存在，仍缺 E2（`d1/d2`）及更深逐层夹具。
- R2/R3：L155 的“`installed_gem_dir` 容忍缺 specifications 文件”是 task-22 前历史；现行判定为 `<bundle>/specifications/<full>.gemspec` 存在即已装、缺 spec 即 missing（`src/celerite/cli/commands_surface.cr:860-931`）。`spec/m7_installed_discovery_spec.cr` 实测 **23 examples, 0 failures**（task-22 的 22 + task-37 的 info 例），原清单“20”不准确。
- R5：L159 的“成功路径未实现、打印不支持 exit 1”是 2026-11-15 快照；task-31 S3 已删除 `commands_install.cr:111-116` 旧分支，`plugin-source-install` 双 profile PASS，旧文保留为历史。
- R6–R9：L161 首测 55 failures（9 passed）为历史；当前 54 failures / 10 passed；task-32 于 2026-11-19 16:32 采集分桶 artifice 38 / low-IL 8 / fetch 6 / product 2（旧 37/8/6/3 属 task-23）；空 CHECKSUMS 例已确认转 env:artifice（`Could not reach host gem.repo2`）；product 候选仍为 2，②/③ 未复跑。
- M1–M6：README 状态改为 S1+S2+S3 均已实现，锚点改为 `resolution.cr:1362`（`index_for_source_gem` 插件分支）、`:1371`（`plugin_source_specs`）、`:1494`（`hide_inferred_plugins!`）与 `commands_surface.cr:860-931`；上游基线补 task-32 分桶与采集时间并注明 33–40 未复采；deferred 锚点改 `script/differential:622-624`；断言子锚点改为 installed-tree 491-500、first-line 502-512、file-equals 513-533、file-contains 535-547、file-absent 549-566。
- 矩阵：`docs/compat-matrix/README.md` 由“Generated”改为 hand-collected；`upstream-lockfile-v4.0.24.md` 头注改为 task-32 当前基线 38/8/6/2、16:32、predates 33–40；task-23 分桶行标注历史；候选 ① 注记追加“已被 task-32 取代（artifice，非产品缺口）”。

验证与自检：
- roadmap 六行（L154/155/158/159/161/163）逐行自检：`task-39`=1、`****`=0、CR=0、复选框仍 `[ ]`；文件保持 218 行。
- `git diff --check` EXIT 0；`git diff --cached --check` EXIT 0；修改后未勾选任何复选框。
- 未重跑全量 `crystal spec`、全量差分与 `script/gen-cli-baseline`；上游基线未在 33–40 后复采。
- 本清理首个提交 `3af2f5b docs(L163): correct stale capability, baseline and anchor references`；本节随第二个 docs 提交落盘。

## 2026-11-19（M7(3) task-41：default gem 参与解析、`info` 回退与未知 gem 文案）

范围：L155 的 B1「Default Gem」——当声明源里**没有**同名候选时，允许解释器自带的 default gem 参与解析；`info` 打印解释器路径与 `Default Gem: yes`；未知 gem 的 `info`/`show` 文案对齐参考。参考实现分三处：`cli/common.rb:68-101`（`select_spec` → `default_gem_spec`）、`cli/info.rb:41-44`（`spec.default_gem?` 时补一行）、`source/rubygems.rb:122-136`（未知 gem 文案）。参考 `default_gem_spec` 用 `Gem::Specification.find_all_by_name(name).last`；本机 Ruby 4.0.6 同名非 default 版本有 6 个（`json 3.1.0` 等），长驻 bridge 里 `.last` 会命中非 default 版本，因此我方改为显式筛 `default_gem?` 后按版本取最大。

参考 oracle（`file:///…/fixtures/gem-index-legacy`，隔离 HOME/BUNDLE_PATH，4.0.24 与 2.7.2 语义一致）：

| 场景 | exit | 关键输出 |
| --- | --- | --- |
| `gem "json"` + `lock` | 0 | 锁写入普通 `GEM` 段的 `json (2.18.0)`，remote 为声明的索引；4.0.24 有 `CHECKSUMS`（bundler sha + `json (2.18.0)`），2.7.2 无 `CHECKSUMS`、`BUNDLED WITH` 三空格 |
| 同上 + `install` | 0 | stdout `Bundle complete! 1 Gemfile dependency, 1 gem now installed.`（2.7.2 为 `2 gems`）+ `Bundled gems are installed into \`./bundle\``；stderr `json-2.18.0 is built in to Ruby, and can't be cached because your Gemfile doesn't have any sources that contain it.`；bundle 内**不落**该 gem |
| 同上 + `check` | 0 | `The Gemfile's dependencies are satisfied` |
| 同上 + `info json` | 0 | 9 行块：`* json (2.18.0)`、Summary/Homepage/Documentation/Source Code/Changelog/Bug Tracker、`Path: C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/json-2.18.0`、`Default Gem: yes` |
| `gem "json", "9.9"` + `lock` | 7 | `Could not find gem 'json (= 9.9)' in rubygems repository … or installed locally.` 后接 `The source contains the following gems matching 'json':` `* json-2.18.0` |
| 已锁默认 gem 后 `info nosuchgem` / `show nosuchgem` | 7 | `Could not find gem 'nosuchgem'.` |

实现（均为最小改动，未触碰 GEM/PATH/GIT/PLUGIN 既有分支语义）：

- `assets/bridge/server.rb` `op_default_gem_spec`：筛选 `default_gem?` 后 `max_by(&:version)`，返回 name/version/platform/dependencies/required_ruby_version/required_rubygems_version/full_gem_path。
- `src/celerite/resolution.cr:752-789`：`index_specs_for` 在远端候选为空时才调用 `default_gem_index_spec`（`src/celerite/resolution.cr:756`），缓存于 `@default_gem_specs_cache`（`:266`）；`src/celerite/resolution.cr:1072` 让已锁定的默认 gem 跳过索引查询（避免多余 `Fetching source index`）。
- `src/celerite/resolver/source.cr:19-24`：`IndexSpec` 增加可选 `default_gem_path`。
- `src/celerite/cli/commands_install.cr:406-417`：默认 gem 从下载/安装工作集剔除并打印上述 stderr 警告，但保留在 `specs` 中以维持计数；`src/celerite/cli/commands.cr:2057` 读取 `specifications/default/<full>.gemspec` 作为元数据回退，`src/celerite/cli/commands.cr:1940`/`:2102` 的 `default_gem?` 改为按 `default_gem_spec` 的 `full_gem_path` 比对（不再依赖 `GEM_HOME`，否则本机 `GEM_HOME` 会让比较失败），`src/celerite/cli/commands.cr:1882` 未知 gem 文案改为 `Could not find gem '<name>'.`。

测试与差分：

- 新增 `spec/m7_default_gem_spec.cr`（4 例：默认 gem 回退命中、`info` 的 `Default Gem: yes`、约束排除时不回退并带源内列表、未知 gem 文案），与受影响家族成组运行 **128 examples, 0 failures, 0 errors, 0 pending**。
- 新增夹具 `fixtures/differential/lock-default-gem`（`lock`，`file-contains` 断言 `json (` 与 `DEPENDENCIES`）与 `fixtures/differential/info-default-gem`（`lock` 后 `info json`）；双 profile **各 2 passed 0 failed 0 skipped**。夹具用 `file-contains` 而非 `file-equals`，避免把本机默认 gem 版本（`json 2.18.0`）写死进基线。
- 反假绿：`git worktree add C:/temp/celerite-pre41 f97d61d` 编译旧二进制后两个夹具 4.0.24 下 **0 passed 2 failed**（旧侧 `Could not find gem 'json' …` 且无锁文件），当前二进制 PASS，证明夹具具区分力。
- 回归（双 profile 各 6 passed 0 failed）：`install-locked-ruby-incompatible`(6)、`install-fresh`、`install-local`(7)、`lock-noop`、`install-check`、`check-installed-spec-without-gemdir`。

已声明差异/未验证：

- 默认 gem 的锁段沿用声明源的 remote（与参考一致），但参考在 `install` 时的“不可缓存”警告只在“源内确实无同名 gem”时出现；我方按 `default_gem_spec` 版本相等判断，源内存在同名同版本时行为未单独取 oracle。
- 交互式/多 ABI 组合未覆盖；本机仅 Ruby 4.0.6（47 个 default gem），其他解释器版本下默认 gem 名称/版本组合未实测。
- 全量 `crystal spec`、全量差分与上游 64 例套件未重跑（沿用既有记录）。

## 2026-11-19（M7(8) task-42：`install`/`update` 收尾的 funding 汇总）

范围：L156 `fund` 的真实 metadata 面——`install`/`update` 结束时打印参考 `cli/common.rb:34-47` 的 funding 汇总；只统计 Gemfile 直接依赖、按 requested groups 过滤；0 个命中或 `ignore_funding_requests` 置真时静默。参考调用点 `cli/install.rb:74`、`cli/update.rb:123`。

参考 oracle（隔离 HOME/BUNDLE_PATH；funded PATH gem `alpha`/`beta` + `json_pure` 来自 `fixtures/gem-index`；4.0.24 与 2.7.2 逐字一致）：

| 场景 | exit | 收尾输出 |
| --- | --- | --- |
| `install`，1 个 funded 直接依赖 | 0 | `1 installed gem you directly depend on is looking for funding.` + `  Run \`bundle fund\` for details` |
| `install`，2 个 funded 直接依赖 | 0 | `2 installed gems you directly depend on are looking for funding.` + 同上第二行 |
| `install`，无 funded 依赖 | 0 | 不打印 |
| `.bundle/config` 设 `BUNDLE_IGNORE_FUNDING_REQUESTS: "true"` | 0 | 不打印 |
| `install` 后 `update --all` | 0 | `Bundle updated!` 之后打印 singular 文案 |
| `--quiet` | 0 | 不打印（stdout 被重定向到内存） |

位置：`install` 在 `Bundle complete!` → bundle 路径行 → 插件 post-install message → cooldown 之后；`update` 在 `Bundle updated!`（及 cooldown）之后。

实现：

- `src/celerite/cli/commands_surface.cr:1205-1229` 新增 `Commands.print_fund_summary`：`ignore_funding_requests` 的 `Array(String)` 值非空即视为真（`Config.to_bool` 不接受数组）；用 `fund_requested_groups` 取 requested groups；对每个直接依赖在锁里找 spec，`read_funding_uri` 非空计数；0 则返回；按 1/≥2 选 `is`/`are`，打印两行。
- `src/celerite/cli/commands_install.cr:765-770`：`print_cooldown_summary` 之后、`if summary` 内调用，传 `resolution.generated_lockfile`（锁文件在 summary 块之后才落盘）。
- `src/celerite/cli/commands_surface.cr:232-236`：`update` 在 `Bundle updated!`/cooldown 之后同样调用。

测试与差分：

- 新增 `spec/m7_funding_summary_spec.cr`（5 例：singular、plural、ignored、无命中、`update --all`），**5 examples, 0 failures, 0 errors, 0 pending**；与 `m7_fund_spec.cr`、`m7_fund_group_spec.cr` 成组 **17 examples, 0 failures**。
- 新增夹具 `install-fund-summary`、`install-fund-summary-two`、`install-fund-summary-ignored`、`update-fund-summary`；双 profile 各 **4 passed 0 failed 0 skipped**。
- 反假绿：`git worktree add C:/temp/celerite-pre42 52b8f15` 旧二进制在 4.0.24 下三个含汇总夹具 **0 passed 3 failed**（缺两行汇总）；`install-fund-summary-ignored` 是回归夹具，旧侧同样 PASS，不参与区分力计数。
- 回归（双 profile 各 9 passed 0 failed）：`install-fresh`、`install-rerun`、`install-check`、`install-local`(7)、`lock-noop`、`install-platforms-add-local`、`plugin-source-install`、`install-deployment-empty-checksums`(16)、`fund-groups`。

门禁：`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（仅 2 条既有 `Deprecated File.executable?` 警告）；`crystal build src/cli.cr -o bin/celerite.exe` EXIT 0；`git diff --check`、`git diff --cached --check`、`git diff 52b8f15..HEAD --check` EXIT 0。

已声明差异/未验证：

- 参考的 auto-clean 未实现，故“汇总相对 auto-clean 的位置”无法逐字对齐，标未验证。
- `--without` 收窄时的人数未取到干净 oracle（探针里 path gem 被误加入索引，作废）；本实现按 requested groups 过滤，该路径未单测。
- 全量 `crystal spec`、全量差分与上游 64 例套件未重跑。

## 2026-11-20（M7(8) task-44a：`check` 改写的非 gem 段保真与空 GEM remote）

结论：`check` 在只补本机平台时会把锁文件整体重写；我方此前在重写路径上把所有段压成 `GEM`，并把 PATH 段包进 `GEM / remote: https://rubygems.org/`，丢失 `PATH`/`glob` 段。参考则从**锁里的 source 对象**重新序列化（`source/path.rb:41-43,45-50`、`source/git.rb:39-48`、`lockfile_generator.rb:31-42`），因此 `PATH`/`GIT`/`PLUGIN SOURCE` 段逐字保留；且未声明任何 `source` 行时 GEM 段不带 `remote:`（`source/rubygems.rb:114-120`）。本轮改 `materialize_locked` 重建段信息、GEM 段空 remote 形态，以及 CHECKSUMS 段的保留条件。

### oracle 表（4.0.24 与 2.7.2 均为实测，两侧逐字节比对）

| 用例 | 命令 | 参考 | 修复前我方 | 修复后我方 |
| --- | --- | --- | --- | --- |
| (i) PATH + 非默认 glob，锁被改成只有 `java`，再 `check` | `check` | exit 0；锁保留 `PATH / remote: vendor/d / glob: gems/*/*.gemspec / specs: dgem (2.0.0)`，PLATFORMS 变 `java` + `x64-mingw-ucrt`，`CHECKSUMS` 段保留（4.0.24 含 bundler 与 dgem 两行，2.7.2 只有 dgem） | 锁变成 `GEM / remote: https://rubygems.org/ / specs: dgem (2.0.0)`，PATH 与 glob 丢失；4.0.24 还丢掉整段 `CHECKSUMS` | 与参考逐字节一致（两 profile 均 IDENTICAL） |
| (ii) 只有 path gem、Gemfile 无 `source` 行 | `lock` | exit 0；`GEM` 段无 `remote:` 行（`GEM\n  specs:\n`） | `GEM / remote: https://rubygems.org/ / specs:` | 与参考逐字节一致 |
| (iii) 声明 `source "https://rubygems.org"` + path gem | `lock --local` | `GEM / remote: https://rubygems.org/ / specs:`（空段保留 remote） | 同参考 | 同参考（回归护栏，未变） |

(i) 的 stdout 两侧都是 `Resolving dependencies...` + `The Gemfile's dependencies are satisfied`，stderr 空。

### 代码锚点与改动

- `src/celerite/resolution.cr` `materialize_locked`（原先把非 PLUGIN 段一律 `"GEM"`、`source_info=nil`）：改为按锁段类型重建 `source_info`，见新 `locked_source_type`（`PATH`/`GIT`/`PLUGIN`/`GEM`）与 `locked_source_info`（PATH 取 `remote` + `glob`（缺省 `Resolution::DEFAULT_GLOB`）；GIT 取 `remote`/`revision`/`ref`/`branch`/`tag`/`submodules`/`glob`；`PLUGIN SOURCE` 仍走 `plugin_source_info`）。对应参考 `Source::Path#from_lock`（`source/path.rb:41-43`）与 `LockfileGenerator#add_sources`（`lockfile_generator.rb:31-42`）。
- `src/celerite/resolution.cr` `declared_rubygem_remotes`：删掉 `remote ||= primary_remote` 兜底（声明了无 remote 的 rubygems 源时不再伪造默认源）；新增 `rubygem_source_without_remote?`，`generated_lockfile` 在其为真且没有任何 GEM 段时补一个**无 options** 的 `GEM` 段。对应参考 `source/rubygems.rb:114-120`（`remote:` 行来自 `lockfile_remotes`，空列表即无该行）。
- `src/celerite/resolution.cr` `checksums_enabled?`：把「锁里已有 CHECKSUMS 段就保留」提到最前，避免 4.0.24 在缺 `lockfile_checksums` 配置时把既有段丢掉；无段的新锁仍要求 `lockfile_checksums` 或 `--add-checksums`。对应参考 `definition.rb:661-670`（`locked_checksums` 由锁段初始化）+ `lockfile_generator.rb:69-76`。

### 测试与夹具

- 新 `spec/m7_lock_rewrite_fidelity_spec.cr`（2 examples，0 failures）：在 reuse 路径直接断言 `Resolution#lockfile_rewrite_text`（不触网）——(1) PATH 段与 `glob:` 原样保留、且不出现 `GEM\n  remote: https://rubygems.org/`；(2) 无 `source` 行时输出 `\nGEM\n  specs:\n` 且不含默认 remote。
- 新 `fixtures/differential/check-rewrite-keeps-path-source/`（`command` = `check`，预置锁 PLATFORMS 只有 `java`，`extra/vendor/d/{dgem.gemspec,gems/x/dgem.gemspec}`；`file-equals-4.0.24` / `file-equals-2.7.2` 整锁断言）。
- 新 `fixtures/differential/lock-path-source-only-no-remote/`（`command` = `lock`，Gemfile 只有 `gem "kgem", path: "vendor/k"`；`file-equals-*` 断言 `GEM` 段无 `remote:`）。
- 双 profile：4.0.24 2 passed / 0 failed / 0 skipped；2.7.2 同上。

### 负对照（`git worktree add C:/temp/celerite-pre44a 0cbbc6b`，重建旧二进制）

- 4.0.24：0 passed / 2 failed——`check-rewrite-keeps-path-source` 的 cel 侧把 `PATH…glob…` 换成 `GEM / remote: https://rubygems.org/`；`lock-path-source-only-no-remote` 的 cel 侧多出 `remote: https://rubygems.org/`。
- 2.7.2：0 passed / 2 failed（同样两处症状）。
- ⇒ 两个夹具均有判别力。

### 回归（双 profile）

`check-rewrites-lock`、`check-dry-run-keeps-lock`、`scoped-source-lock`、`path-glob-default-root`、`path-glob-default-nested`、`path-glob-default-deep-miss`、`path-glob-monorepo`、`install-local`(7)、`lock-noop`、`install-fresh`、`plugin-source-locked-check`、`plugin-source-typed`、`install-platforms-add-local`：4.0.24 13 passed / 0 failed；2.7.2 15 passed / 0 failed（含本轮 2 个新夹具）。

spec 家族 `m7_lock_rewrite_fidelity_spec`、`m7_git_source_reuse_spec`、`m7_installed_discovery_spec`、`m7_path_*`、`m7_source_*`：49 examples / 0 failures / 0 errors / 0 pending。

### 门禁（全部 EXIT 0）

`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff 0cbbc6b..HEAD --check`、`git diff --cached --check`、`git diff --check`。

### 已声明差异 / 未验证

- 本轮只覆盖 `check` 重写与空 remote 两个面；PATH 源 `glob:` 的身份判定（glob 不进 `eql?`）由 task-44 的 A1/A2 负责，不在本轮范围。
- `PLUGIN SOURCE` 段的 GIT/PATH 之外的选项（插件自定义 `options_to_lock`）沿用既有 `plugin_source_info`，未在本轮重新取 oracle。
- `BUNDLE_FROZEN=true` 下 `check` 的拒写路径未在本轮重取 oracle（此前 task-33/35 已有记录）。
- 全量 `crystal spec`、全量差分与上游 64 例套件未重跑。

## 2026-11-20（M7(8) task-44b：PATH 源身份与可见 spec 集判据）

结论：参考把 PATH 源的 **身份**定义为 `expanded_original_path` + `version`，`glob` 不参与（`source/path.rb:64-68`，`alias_method :==, :eql?`）；`glob` 只影响「该源当前可见哪些 gemspec」。因此 `Definition#converge_paths` → `specs_changed?`（`definition.rb:929-950`）比较的是**锁侧 spec 集是否被当前可见集覆盖**（`locked_index.subset?(source.specs)`），而不是字符串标签。我方此前把 `glob` 拼进 `path_label`（task-34 引入），导致 `glob:` 一变就判成「源变了」：`lock` 多打一次 `Resolving dependencies...` 并写 `glob:` 行，`frozen` 下 `check` 误报 exit 16；反过来，锁里默认 glob 的 gemspec 版本从 1.0.0 升到 2.0.0 时又不重解。本轮去掉 `glob` 对身份的影响，并新增「按锁侧 path+glob 枚举 gemspec 名称/版本、与锁侧 spec 集比对」的判据。

### oracle 表（4.0.24 与 2.7.2 均为实测，两侧逐字节比对）

| 用例 | 命令 | 参考 | 修复前我方 | 修复后我方 |
| --- | --- | --- | --- | --- |
| (C1) 默认 glob 锁定 dgem 1.0.0；新增 `vendor/d/gems/y/dgem.gemspec` 2.0.0，Gemfile 改为 `glob: "gems/*/*.gemspec"` | `lock` | exit 0；只打 `Writing lockfile to …`；锁**不变**（仍 `dgem (1.0.0)`，无 `glob:` 行） | exit 0；多打 `Resolving dependencies...`；锁写成 `glob: gems/*/*.gemspec` + `dgem (2.0.0)` | 与参考逐字节一致 |
| (C2) 锁仍用默认 glob，`vendor/d/dgem.gemspec` 1.0.0→2.0.0 | `lock` | exit 0；`Writing lockfile to …` + `Resolving dependencies...`；锁重写为 `dgem (2.0.0)` | 只打 `Writing lockfile`，锁保持 `dgem (1.0.0)`（漏重解） | 与参考逐字节一致 |
| (D1) 同 C1，但 `BUNDLE_FROZEN=true` | `check` | exit 0；`The Gemfile's dependencies are satisfied` | exit 16；`The list of sources changed…` + `* dgem from \`vendor/d\` to \`vendor/d (glob: gems/*/*.gemspec)\`` | 与参考逐字节一致（exit 0） |
| (D2) 同 C2，但 `BUNDLE_FROZEN=true` | `check` | 4.0.24：exit 16，`The gemspecs for path gems changed, but the lockfile can't be updated because frozen mode is set`；2.7.2：exit 1，`The following gems are missing` + ` * dgem (1.0.0)` + 安装提示 | 两侧都 exit 0 | 与参考逐字节一致 |
| (E) 锁里写明非默认 `glob: gems/*/*.gemspec`（2.0.0）；Gemfile 去掉 glob 行 | `lock` | exit 0；只打 `Writing lockfile to …`；锁**保留** `glob:` 与 `dgem (2.0.0)` | exit 7；`Could not find gem 'dgem' with platform 'x64-mingw-ucrt' in source at \`vendor/d\`.` | 与参考逐字节一致 |

### 代码锚点与改动

- `src/celerite/definition.cr` `path_label`：不再拼 `glob`，两侧都 `File.expand_path(path, File.dirname(gemfile_path))` 后比较（桥接侧把 `./pathgem` 归一成 `pathgem`，锁里仍是 `./pathgem`；参考身份是 `expanded_original_path`）。`git_label` 保留 `glob`（参考 `source/git.rb:72-83` 的 `eql?` 含 glob，GIT 不在本轮改动内）。
- `src/celerite/resolution.cr`：新增 `Resolution.stale_path_specs(definition, bridge, evaluation)`——对每个 PATH 依赖，取**锁段**的 `remote`（或 `path`）与 `glob`（缺省 `DEFAULT_GLOB`），相对 Gemfile 目录展开，经新桥接 op `load_gemspec_dir_specs` 枚举该 glob 下 `name`+`version`（浅层覆盖深层，同 `source/path.rb:159-179`），返回锁段里不可见的 spec；桥缺失/报错按 fail-open 返回空。`reuse_locked_resolution?` 在依赖源判据之后加 `return false if path_specs_changed?`；锁 no-op 条件加 `!resolution.path_specs_changed?`，避免短路掉应有的重解。
- `assets/bridge/server.rb`：新 `op_load_gemspec_dir_specs`（`dir`/`glob` → 按深度排序后 `Gem::Specification.load`，按 `name` 去重保留浅层），并在显式 dispatch 表注册；`src/celerite/bridge/client.cr` 加 `GemSpecSummary` 与 `load_gemspec_dir_specs`。
- `src/celerite/definition.cr` `validate_frozen_lockfile!` 新增 `path_specs_changed` 参数，追加理由 `the gemspecs for path gems changed`（参考 `definition.rb:906-920` 的 `@path_changes` 文案）；`src/celerite/cli/commands_install.cr` 与 `src/celerite/cli/commands.cr` 的 `check` 在 4.x 传入该标志。
- `src/celerite/cli/commands.cr` `check`：2.x + frozen + 锁侧 PATH spec 已不可见时，走参考的 missing-gem 文案（`The following gems are missing` + ` * dgem (1.0.0)` + \"Install missing gems with `bundle install`\"）exit 1。
- 锁 no-op 重写顺带把 `BUNDLED WITH` 改成当前 bridge 版本（参考 `definition.rb:401-418` 每次都序列化 `Bundler::VERSION`；实测 2.7.2 会改写 4.0.24 的锁）。

### 测试与夹具

- `spec/m7_git_source_reuse_spec.cr` 重写原「glob 变了就重解」用例为两条：glob-only 变化 → `reuse_locked?` 为 true；锁侧 glob 下 gemspec 版本变化 → false。
- 新夹具（`file-equals-4.0.24` / `file-equals-2.7.2` 整锁断言）：`fixtures/differential/path-glob-change-keeps-lock/`（C1）、`path-gemspec-bump-reresolves/`（C2）、`check-frozen-path-gemspec-bump/`（D2，`frozen` marker）、`path-locked-glob-wins/`（E）。
- 双 profile：4.0.24 与 2.7.2 均 4 passed / 0 failed / 0 skipped。

### 负对照（`git worktree add C:/temp/celerite-pre44b 7fab7a4`，重建旧二进制）

- 4.0.24：0 passed / 4 failed——C1/E 的 cel 侧重解并写入 `glob:`，D2 的 cel 侧 exit 0 且 stderr 为空（参考 exit 16 的 path-gemspec 理由缺失），C2 的 cel 侧不重解。
- ⇒ 四个夹具均有判别力；2.7.2 负对照未单独重跑（同源二进制）。

### 回归（双 profile）

`path-glob-default-root`、`path-glob-default-nested`、`path-glob-default-deep-miss`、`path-glob-monorepo`、`scoped-source-lock`、`check-rewrites-lock`、`check-dry-run-keeps-lock`、`check-rewrite-keeps-path-source`、`lock-path-source-only-no-remote`、`install-frozen`(15)、`install-frozen-source-changed`(16)、`install-platforms-add-local`、`install-platforms-frozen-error`(16)、`install-fresh`、`lock-noop`、`install-local`(7)，加本轮 4 个新夹具：4.0.24 20 passed / 0 failed；2.7.2 20 passed / 0 failed。

spec 家族 `m7_git_source_reuse_spec`、`m7_source_lock_options_spec`、`m7_lock_rewrite_fidelity_spec`、`m7_installed_discovery_spec`、`m7_path_*`：50 examples / 0 failures / 0 errors / 0 pending（隔离 `HOME` 后；宿主 `~/.bundle/config` 的 `BUNDLE_PATH: vendor/x` 会让 `m7_path_system_spec` 假失败）。

### 门禁（全部 EXIT 0）

`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff --check`、`git diff --cached --check`、`git diff 7fab7a4..HEAD --check`。

### 已声明差异 / 未验证

- PATH 源「身份」仍以字符串比较实现（`path_label` 展开后的绝对路径），未把 `version`（Gemfile `gem "x", path: ..., version:` 的 fake gemspec 形态）纳入标签；该形态本轮未取 oracle。
- 可见 spec 集判据只比 `name`+`version`，未比 `platform` 与运行时依赖（参考 `subset?` 还比 `runtime_dependencies` 与 `source`）；差异需构造同名同版本不同 platform 才可见，本轮未覆盖。
- 桥枚举是新增 op，只服务本判据；插件 PATH/GEMSPEC 源未走该路径。
- 2.7.2 的 D2 走 `check` 的 missing-gem 分支，依据单次 oracle；未覆盖 `install` 在 2.7.2 下的同场景。
- 全量 `crystal spec`、全量差分与上游 64 例套件未重跑。

## 2026-11-20（M7(6) task-45：before-install-all / after-install-all 插件钩子）

### 参考行为（源码锚点）

- `bundler/lib/bundler/installer.rb:12-20`：类方法 `install(root, definition, options)` 在 `installer.run` 之前触发 `Plugin.hook(GEM_BEFORE_INSTALL_ALL, definition.dependencies)`，之后触发 `GEM_AFTER_INSTALL_ALL`；`cli/update.rb:81` 复用同一入口，因此 `update` 同样两侧各触发一次。
- `bundler/lib/bundler/plugin/events.rb:45-58`：事件名 `before-install-all` / `after-install-all`（另有每 spec 的 `after-install`）。
- `bundler/lib/bundler/plugin.rb:228-240`：`Plugin.hook(event, *args)` 在 `Bundler.settings[:plugins]` 为假时直接返回；否则加载钩子插件并逐个调用块，参数即 `definition.dependencies`（`Array`，元素 `Bundler::Dependency`）。

### oracle（4.0.24 与 2.7.2 一致）

| 场景 | 观察 |
| --- | --- |
| 输出顺序（3 个 path gem） | `BEFORE_ALL …` → `Resolving dependencies...` → 安装动作 → `AFTER_ALL …` → `Bundle complete! …` → `Bundled gems are installed into …` |
| 参数形态 | 外层 `Array`，元素 `Bundler::Dependency`；`names` 按 Gemfile 声明顺序（`alpha,beta,gamma`）；`groups` 可读（`default`） |
| 依赖数 3 / 1 / 0 | 三个场景都触发；0 依赖时 `names=` 为空，stderr 另有 `The Gemfile specifies no dependencies` |
| 无变化重跑 `install` | 仍然两侧各触发一次 |
| `BUNDLE_PLUGINS=false` | 两侧都不出现任何输出 |
| 钩子 stdout | 出现在 bundle 自身 stdout 中（与 `Resolving dependencies...` 交错在同一流），故参考用 `Bundler.ui.info` 之外的 `puts` 也能观察到 |

### 实现

- `src/celerite/plugin_hooks.cr:20-24`：`EVENTS` 扩为 `["after-install", "before-install-all", "after-install-all"]`；`HookResult` 新增 `output`（钩子块写入的 stdout）；`PluginHooks.call` 新增 `gemfile_path` 参数；新增 `PluginHooks.run(bridge, definition, config, event, stdout, stderr)` 统一处理“未启用 / 缺插件告警 / 加载失败 / 钩子失败”并返回退出码。
- `src/celerite/bridge/client.cr`：`exec_plugin_hook` 增 `gemfile_path` 载荷字段。
- `assets/bridge/server.rb`：`op_exec_plugin_hook` 对 `*-all` 事件用 `Bundler::Dsl.evaluate(gemfile, lockfile, {})` 取 `builder.dependencies` 作为参数（Gemfile 缺失/解析失败时退化为空数组）；块执行期间把 `$stdout` 换成 `StringIO`，结束后在 `ensure` 中恢复并把捕获内容随响应返回，避免插件 `puts` 写进 RPC 管道（早期版本会触发 `response id mismatch`）。
- `src/celerite/cli/commands_install.cr`：解析前调用 `before-install-all`（失败即返回退出码），全部 spec 的 `after-install` 循环后、汇总输出前调用 `after-install-all`；每 spec 钩子的捕获输出在循环内回放到 stdout。
- `src/celerite/cli/commands_surface.cr`（`update` 路径）：同样在解析前与 `Bundle updated!` 之前各调用一次。

### 测试与差分

- 新增差分夹具 `fixtures/differential/plugin-hook-before-after-all/`：`plugin install hook_all_plugin --path ./hook_all_plugin` 后执行 `install`，钩子打印 `BEFORE_ALL`/`AFTER_ALL` 及 class/names/groups。双 profile PASS：4.0.24 `PASS plugin-hook-before-after-all (exit=0)`，2.7.2 同。
- 新增 `spec/m7_plugin_hook_all_events_spec.cr`（4 examples）：事件名精确定义；顺序断言（`BEFORE_ALL` < `Resolving dependencies...` < `AFTER_ALL` < `Bundle complete!`，names `alpha,beta`）；重跑再触发一次；`BUNDLE_PLUGINS=false` 静默。
- `spec/plugin_hooks_spec.cr:97-101` 的事件名固定断言同步更新为三事件列表（原断言只列 `after-install`，是 task-11 时期的历史快照）。
- 回归差分 10 项双 profile 全 PASS：`plugin-install`(1)、`plugin-install-hooks`(0)、`plugin-hook-per-gem`(0)、`plugin-uninstall`(0)、`plugin-uninstall-args`(0)、`plugin-source-typed`(0)、`plugin-source-install`(0)、`install-fresh`(0)、`install-rerun`(0)、`install-fund-summary`(0)（4.0.24 10/0、2.7.2 10/0）。
- spec 家族 `plugin_hooks_spec`、`m7_plugin_hook_per_gem_spec`、`m7_plugin_hooks_registration_spec`、`m7_plugin_hook_failure_spec`、`m7_gemfile_plugins_spec`、`m7_plugin_hook_all_events_spec`：30 examples / 0 failures / 0 errors / 0 pending（隔离 `HOME`，避免宿主 `~/.bundle/config` 的 `BUNDLE_PATH: vendor/x`）。
- 反向对照：`C:/temp/celerite-pre45`（`e4354f3`）旧二进制在本夹具上双 profile 均 FAIL，差异即缺失的 `BEFORE_ALL`/`AFTER_ALL` 两行（`3d2`/`5d3`）。

### 门禁（全部 EXIT 0）

`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff --check`、`git diff --cached --check`、`git diff e4354f3..HEAD --check`。

### 已声明差异 / 未验证

- 桥对 `*-all` 事件的参数用 Ruby 侧重新 `evaluate` Gemfile 得到，而不是复用 CLI 已算好的 `definition.dependencies`；两者在正常 Gemfile 下一致（names/groups 已 oracle 比对），但 Gemfile 解析失败时参考会先报错退出、我方退化为空数组，该路径未取 oracle。
- `after-install-all` 在我方位于 `Bundle complete!` 之前、`Bundled gems are installed into …` 之前，与 oracle 一致；但参考还包含 auto-clean 与 funding 汇总，本轮未覆盖其与 auto-clean 的相对位置。
- 仅 4.0.24 与 2.7.2 两个 profile；全量 `crystal spec`、全量差分与上游 64 例套件未重跑。
## 2026-11-20（M7(8) task-46：PATH 源按名匹配与 PLUGIN 源归属）

### 缺陷（静默错误安装级）

沙箱 `Gemfile` 为 `source "https://rubygems.org/"` + `gem "nope-gem", path: "vendor/x"`，而 `vendor/x/` 只有 `other-gem.gemspec`（`other-gem 1.0.0`）：

- 修复前 `celerite lock`：**exit 0**，并写出
  ```
  PATH
    remote: vendor/x
    specs:
      nope-gem (1.0.0)
  ```
  ——`nope-gem` 不存在，版本是从 `other-gem` 抄来的。
- 参考 4.0.24：**exit 7**，stdout 仅 `Writing lockfile to …`，stderr 单行 `` Could not find gem 'nope-gem' in source at `vendor/x`. ``，不写锁。

根因：`assets/bridge/server.rb` 的 `op_load_gemspec_dir` 取 `candidates.first` 加载，`src/celerite/resolution.cr` 的 `load_source_gem_spec` 又把调用方传进来的 `name` 直接当成 spec 名（`Resolver::IndexSpec.new(name, …)`），从不校验 `spec.name == name`。参考语义是 `source/path.rb:159-179` 载入 glob 全集、`resolver/base.rb:113-118` 以 `specs.search(ls.name).empty?` 判未命中。

### 修复

- 桥 `op_load_gemspec_dir` 增加可选 `name`：按深度优先顺序枚举整个 glob（与 `op_load_gemspec_dir_specs` 一致，浅层覆盖深层），只返回 `spec.name == name` 的那份；未命中 `raise "gem '<name>' not found in <dir>"`（结构化失败，不再回退到兄弟 gemspec）。`src/celerite/bridge/client.cr` 的 `load_gemspec_dir` 增同名可选参数。
- `src/celerite/resolution.cr` `load_source_gem_spec` 传 `name`，并只在 `info.name == name` 时构造 `IndexSpec`，否则返回 `nil`；`index_for_source_gem` 得到空候选，解析器按 `GemNotFoundError` 报错，PATH 归属沿用 `Source::Path#to_s`（`source at `<path>``，task-36 已接线）。
- PLUGIN 源归属：`make_source` 的 `source_descriptions` 增 Plugin 分支 `"plugin source for #{plugin_type} with uri #{remote}"`，锚 `plugin/api/source.rb:293-296`；GIT 分支保持原状（见未验证）。

### oracle（4.0.24 与 2.7.2 一致）

| 场景 | 参考 |
| --- | --- |
| PATH 未命中 | exit 7；stdout `Writing lockfile to …`；stderr `` Could not find gem 'nope-gem' in source at `vendor/x`. ``；不写锁 |
| PLUGIN 未命中（`type: :mpath`，uri `./stub-path-gem`） | exit 7；stdout `Writing lockfile to …`；stderr 两行（80 列折行）`Could not find gem 'nope-gem' in plugin source for mpath with uri` / `./stub-path-gem.`；不写锁 |

### 测试与差分

- 新夹具 `fixtures/differential/path-source-missing-gem/`（`Gemfile` + `vendor/x/other-gem.gemspec` + `command=lock` + `file-absent Gemfile.lock`）。
- 新夹具 `fixtures/differential/plugin-source-missing-gem/`（复用 `plugin-source-typed` 的预置 `.bundle/plugin` 与 `extra/stub-path-gem/`，Gemfile 内加 `gem "nope-gem"`；`command=lock` + `file-absent Gemfile.lock`）。
- 差分：4.0.24 `PASS path-source-missing-gem (exit=7)`、`PASS plugin-source-missing-gem (exit=7)`；2.7.2 同 → 各 2 passed / 0 failed / 0 skipped。
- 新 spec `spec/m7_path_source_missing_gem_spec.cr`（3 examples）：同名命中仍正常解析；异名不伪造（exit 7 + 逐字 stderr + 无锁文件）；同名深浅两层时浅层胜出（锁写 `pathgem (2.0.0)`）。
- spec 家族 `m7_path*` + `m7_git_source_reuse_spec` + 新 spec：23 examples / 0 failures / 0 errors / 0 pending（隔离 `HOME`）。
- 回归差分 13 项双 profile 全 PASS：`path-glob-default-root`、`path-glob-default-nested`、`path-glob-default-deep-miss`、`path-glob-monorepo`、`scoped-source-lock`、`path-locked-glob-wins`、`path-gemspec-bump-reresolves`、`path-glob-change-keeps-lock`、`install-local`(7)、`plugin-source-typed`、`plugin-source-install`、`install-fresh`、`plugin-install`(1)（4.0.24 13/0、2.7.2 13/0）。
- 反向对照 `C:/temp/celerite-pre46`（`e058de4`）旧二进制双 profile 均 `0 passed / 2 failed`：
  - PATH：`exit code: reference=7 celerite=0`，旧版多出 `Resolving dependencies...`，缺 `` Could not find gem 'nope-gem' in source at `vendor/x`. ``，并写出 `Gemfile.lock`（`file-absent violated`）。
  - PLUGIN：stderr 变成 `Could not find gem 'nope-gem' in rubygems repository` / `file:///…/fixtures/gem-index/ or` / `installed locally.`（归属错误）。

### 门禁（全部 EXIT 0）

`crystal tool format --check src spec`（先格式化新 spec）、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff --check`、`git diff --cached --check`、`git diff e058de4..HEAD --check`。

### 已声明差异 / 未验证

- **GIT 源未命中归属未实现**：参考形态为 `<uri> (at <ref>@<short>)`，但本机 celerite 的 git 子进程被环境阻断（`sh.exe` `0xC0000022`，Crystal 祖先链问题；参考不受影响），GIT 端到端无法取我方 oracle，本轮不动 GIT 分支。
- 同名多层只验证了「浅层胜出」与「取到同名那份」；同名不同版本的「深层被浅层覆盖」在差分里未构造（spec 覆盖到 2.0.0 胜出）。
- PLUGIN 夹具用目录型 stub source（与既有 S1–S3 夹具一致），未覆盖第三方 plugin gem 安装后注册 source 的路径（task-43 仍暂停）。
- 全量 `crystal spec`、全量差分与上游 64 例套件未重跑。
## 2026-11-20（M7(6) task-47：第三方插件 gem 的端到端 source）

### 结论

起先把 S1–S3 的插件 source 夹具都预置成目录型 stub（`extra/.bundle/plugin/index` + `plugins.rb`），跳过了「插件 gem 真正装进来」这一步。本轮用一个真实打包的插件 gem（`mpath_plugin`，`plugins.rb` 调 `Bundler::Plugin::API.source` 注册 `mpath`）走完整链路：`plugin install` → 索引出现 `sources: mpath: "mpath_plugin"` → Gemfile 的 `source "...", type: :mpath` 可解析 → `lock`/`install`/`check` 与参考 4.0.24、2.7.2 双 profile 逐字一致。

过程中补了两处真实缺口：(1) 插件索引从未记录 `sources`，导致 `Plugin.source?("mpath")` 等价判断为假、`lock` 报 `No plugin sources available for mpath`（exit 15）；(2) 插件 gemfile 安装走 remote/cached-only 源，缺 gem 的措辞应为 `…, cached gems or installed locally`，我方原先只有 `… or installed locally`。

### Oracle（4.0.24 与 2.7.2 同形）

同一项目依次执行：

1. `plugin install mpath_plugin --source file:///<plugin-gem-index>` → exit 0，stdout：`Fetching source index from …`、`Resolving dependencies...`、`Fetching mpath_plugin 1.0.0`、`Installing mpath_plugin 1.0.0`、`Installed plugin mpath_plugin`。
2. `plugin list` → exit 0，`mpath_plugin` / `-----`。
3. `lock` → exit 0，`Writing lockfile to …/Gemfile.lock`、`Resolving dependencies...`；锁文件含 `PLUGIN SOURCE` / `  remote: ./stub-path-gem` / `  type: mpath` / `  specs:` / `    stub-gem (1.0.0)`，`DEPENDENCIES` 为 `  stub-gem!`。
4. `install` → exit 7，stderr：`Could not find gem 'bundler-source-mpath' in rubygems repository` + `\n<remote>,\ncached gems or installed locally.`（reference 在 `Plugin.gemfile_install` 里以 `sources.cached!` + `remotely!` 解析推断出的 `bundler-source-<type>`，故是带 cached 的第三分支）。
5. `check` → exit 0，`The Gemfile's dependencies are satisfied`。

### 参考锚点

- `bundler/lib/bundler/plugin/api.rb:43-46`：`self.source(source, cls = self)` → include `Plugin::API::Source` 并 `Plugin.add_source`。
- `bundler/lib/bundler/plugin.rb:309-340`：`register_plugin` 把 `@sources.keys` 交给 `index.register_plugin`，索引因此有 `sources` 表；`:138-158` 的 `root` 在项目内为 `<app>/.bundle/plugin`。
- `bundler/lib/bundler/plugin/index.rb:54-76`：`sources.each { |k| @sources[k] = name }`，冲突抛 `SourceConflict`。
- `bundler/lib/bundler/source/rubygems.rb:122-136`：`to_s` 的 cached 分支（remote-only 时输出 `…, cached gems or installed locally`）。

### 实现

- `assets/bridge/plugin_command.rb`：`--commands` 探测额外返回 `sources`（`Bundler::Plugin.instance_variable_get(:@sources).keys`）。
- `src/celerite/plugin_commands.cr`：`Declared` 增 `sources`，新增 `PluginCommands.sources(index_path)`。
- `src/celerite/cli/commands_surface.cr`：两处插件安装写索引时读入既有 `sources_map`、冲突按参考措辞报 `SourceConflict`（exit 29，`Failed to install plugin \`<name>\`, due to Bundler::Plugin::Index::SourceConflict (Source(s) \`<type>\` declared by <name> are already registered.)`），并把声明类型写回 `sources:`。
- `src/celerite/resolution.cr`：新增 `property remote_only`，`make_source` 的描述在 remote-only 时输出 `rubygems repository <remote>, cached gems or installed locally`。
- `src/celerite/cli/commands_surface.cr` `plugin_install_remote`：非 `local_only` 时置 `resolution.remote_only = true`，对齐 `Plugin::Installer` 的 remote/cached-only 解析。
- 夹具与工具：`fixtures/plugin-source-gem/`（可复用插件 gem 源）、`fixtures/gem-index-plugin-gem/`（`script/build-plugin-gem-index.rb` 生成，含 legacy/compact 索引，`versions` 哈希可复现）、`script/differential` 新增 `@PLUGIN_GEM_INDEX_DIR@` 替换点。

### 测试与差分

- 新夹具 `fixtures/differential/plugin-source-gem-end-to-end/`（命令序列如上；`file-contains` 断言锁内 `PLUGIN SOURCE`/`type: mpath`/`stub-gem (1.0.0)`/`stub-gem!`）：4.0.24 `PASS (exit=0)`、2.7.2 `PASS (exit=0)`。
- `spec/m7_gemfile_plugins_spec.cr` 的缺 gem 断言改为参考的 cached 分支措辞；相关 spec 家族（`m7_gemfile_plugins`、`m7_plugin_install_source`、`m7_plugin_source_typed`、`plugin_hooks`、`m7_plugin_hook_all_events`）24 examples / 0 failures。
- 回归差分 4.0.24 8/0、2.7.2 9/0（`plugin-install`、`plugin-install-source`、`plugin-install-hooks`、`plugin-source-typed`、`plugin-source-install`、`plugin-source-locked-check`、`install-fresh`、`install-check`，2.7.2 另加新夹具）。

### 反向对照

`git worktree add C:/temp/celerite-pre47 49e3e21` 构建旧二进制后跑新夹具：双 profile 均 FAIL——`exit code: reference=0 celerite=15`，我方 `[!] There was an error parsing \`Gemfile\`: No plugin sources available for mpath.`，缺 `Gemfile.lock`，`sources:` 为空，且缺 gem 措辞仍是旧的 `… or installed locally.`。

### 门禁（全部 EXIT 0）

`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff --check`、`git diff --cached --check`。

### 已声明差异 / 未验证

- 插件 gem 由本仓库脚本本地构建（`fixtures/plugin-source-gem`），不代表真实第三方插件生态；`Gem::Package.build` 的产物时间戳/校验和随环境变化，未做跨机器复现。
- 仅验证单插件注册单一 source；多插件共存、插件间 source/command 冲突、需要原生扩展的插件未测。
- 未验证真实远端（非 `file://`）插件源安装；未重跑全量 `crystal spec`、全量差分与上游 64 例套件。
## 2026-11-20（M7(2) task-48：`exec` 的 RUBYOPT 注入与显式 Gemfile 缺失语义）

### Oracle（4.0.24 与 2.7.2 同形）

| 场景 | 参考 | 修复前我方 |
| --- | --- | --- |
| `exec ruby -e` 打印 `RUBYOPT` | 恰好 1 个 `-r<lib>/bundler/setup`；`RUBYLIB` 1 条 | 2 个 `-r`（一正斜杠一混合斜杠），子进程内 bundler/setup 再追加一次 |
| `BUNDLE_GEMFILE` 指向不存在文件 / `exec --gemfile missing.rb` | 子进程 `-rbundler/setup` 抛 `Bundler::GemfileNotFound`（`definition.rb:38`）并带 backtrace，exit 1 | 父进程读文件失败，单行 `No such file or directory @ rb_sysopen - <path>`，exit 1 |
| 无 Gemfile（未显式指定） | 父进程 `Could not locate Gemfile`，exit 10 | 同（无差异） |

参考锚点：`lib/bundler/cli/exec.rb:54-68`（注入 `RUBYOPT`/`BUNDLE_GEMFILE` 后直接 exec，不读 Gemfile）、`lib/bundler/shared_helpers.rb:355,362-372`（`-rbundler/setup` 去重）、`lib/bundler/plugin` 不相关；`lib/bundler/setup.rb:32` 与 `definition.rb:38` 产生缺失 Gemfile 的异常。

### 修复

- `src/celerite/cli/commands_install.cr` exec 段：注入路径统一为正斜杠（`File.join(...).gsub('\\', "/")`），否则子进程 bundler/setup 的字符串比较会追加第二个等价 `-r`；`RUBYOPT`/`RUBYLIB` 归一化后去重（`normalize_env_path`）。
- 显式 `--gemfile`/`BUNDLE_GEMFILE` 指向不存在路径时，不再在父进程调用 `Definition.build`/`evaluate_gemfile`，而是照参考导出 `RUBYOPT`/`BUNDLE_GEMFILE` 并 exec 子进程，让 `Bundler::GemfileNotFound` 在子进程出现（exit 1）。

### 测试与证据

- 新 spec `spec/m7_exec_env_spec.cr`（3 例）：单 `-r`、保留无关 `RUBYOPT` 条目且 setup 仍为 1、显式缺失 Gemfile 时子进程未执行脚本且 exit 1。与 `m7_exec_spec.cr`、`m7_install_ruby_compat_spec.cr` 合计 12 例 0 失败。
- 新差分夹具 `exec-env-injected`（`install` + `exec ruby count_env.rb`，断言 `setup_entries=1`）与 `exec-no-gemfile`（`exec --gemfile missing.rb`，`stderr-contains` 断言 `definition.rb:`、`missing.rb not found (Bundler::GemfileNotFound)`）；4.0.24 与 2.7.2 均 PASS（exit 0 / exit 1）。
- 回归差分两 profile 各 10 项 0 失败：`exec-loader`(42)、`exec-loader-disabled`(42)、`exec-missing`(127)、`exec-no-arguments`(128)、`exec-thor-version`(0)、`exec-unknown-command`(127)、`exec-env-injected`(0)、`exec-no-gemfile`(1)、`install-fresh`(0)、`install-check`(0)。
- 负向对照：`2e6a5aa` 旧二进制两 profile 均 FAIL——`setup_entries=2`；`exec-no-gemfile` 缺 `GemfileNotFound` 文本。
- 门禁：`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff --cached --check`、`git diff 2e6a5aa..HEAD --check` 全部 EXIT 0（仅 2 条既有 `Deprecated File.executable?` 警告）。

### 已声明差异 / 未验证

- 缺失 Gemfile 的 stderr 采用 contains 断言（两侧 bundler lib 绝对路径不同，无法逐字比较）。
- 未覆盖嵌套 `exec`、Windows 信号转发细节、`--keep-file-descriptors` 的实际 fd 行为；未重跑全量 spec/差分/上游 64 例。

## 2026-11-20（M7(3) task-49：`issue` 无锁报告的失败面与 doctor 共用路径）

### 现象与 oracle

`bundle issue` 在「只有 Gemfile、没有 Gemfile.lock」的项目里，本实现打印 `## Bundle Doctor` 后以 stderr `Could not locate Gemfile` 退出 10，也不再输出 doctor 结论；参考 4.0.24 / 2.7.2 会正常解析、写出锁文件并给出 `No issues found with the installed bundle`。两版参考行为一致，仅锁文件形状不同（4.0.24 212 字节带 CHECKSUMS，2.7.2 110 字节）。

| 场景 | 参考 4.0.24 | 参考 2.7.2 | 本实现（修前） | 本实现（修后） |
| --- | --- | --- | --- | --- |
| Gemfile 无锁 → `issue` | exit 0，`Resolving dependencies...`、`The Gemfile's dependencies are satisfied`、`No issues found...`，写锁 212B | 同上，写锁 110B | exit 10，`Could not locate Gemfile`，无锁 | exit 0，逐项一致（按 profile 写 212B / 110B） |
| Gemfile 无锁 → `doctor` | 同上（共用 doctor 主体） | 同上 | exit 0，但不写锁 | exit 0，写锁 |
| Gemfile 无锁 → `env` | exit 0，不写锁 | 同 | 一致（`<No … found>` 占位） | 一致 |
| 有锁但缺 gem → `issue` | exit 1，缺 gem 列表 | 同 | exit 1，但多一空行 | exit 1，逐字一致 |

### 根因与改动

- `src/celerite/cli/commands_surface.cr:2647` `issue` 复制了 `env` 的报告代码，并用 `File.file?` 决定是否打印 `## Gemfile` / `### Gemfile.lock`；随后 `lockfile.nil?` 直接返回 10。参考 `cli/issue.rb:33-38` 是「先打印 env 报告（`Env.report` 始终输出 Gemfile 段，缺失文件用 `Env.read_file` 占位），再调用 doctor」，无锁不是错误。
- 新增 `print_gemfile_sections(stdout, definition, bridge)`（`:760`）：`env` 与 `issue` 共用，含 `<No <abs> found>` 占位与可选 `## Gemspecs`（`env.rb:35-66`）。
- 新增 `doctor_report(stdout, stderr) : Int32`（`:853`）：`doctor` 与 `issue` 共用「建 definition → 解析/写入锁 → 缺 gem 判定 → satisfied + `No issues found`」。
- 新增 `persist_generated_lockfile`（`:885`）：无锁且依赖满足时按 `lockfile.to_lock` 写出锁文件（参考 doctor 亦写锁）。
- `issue` 删除 `lockfile.nil?` 提前返回与重复的缺 gem 判定，改在报告后调用 `doctor_report`；缺失 Gemfile 仍由 CLI 统一转成 exit 10。
- `script/differential:110-123` 的 N5 归一化此前把 `## Environment` 到 `## Bundle Doctor` 之间的**所有** `## ` 段一并丢弃，导致 issue 夹具从未比较 Gemfile/settings 段（盲区）。现改为只丢弃 `## Environment` 自身的正文（到下一个 `^## ` 行为止，保留该标题），并同步注释。

### 测试与证据

- 新夹具 `fixtures/differential/issue-no-lockfile`（Gemfile-only，`issue`；`bundle-preset/ruby/4.0.0/.keep` 用于避开参考 `check_home_permissions` 在缺失 bundle 子目录时的 ENOENT 崩溃）与 `doctor-no-lockfile`，双 profile 均 PASS（exit 0，`Gemfile.lock` 出现且含 `BUNDLED WITH`）。
- 既有 `env-report`、`env-gemspec`、`issue-satisfied`、`issue-missing-gems` 在 N5 收紧后重跑仍 PASS；回归 `install-check`、`install-fresh` 双 profile 各 8/0。
- `spec/m7_issue_report_spec.cr` 3 例（无锁不报错并写锁、`issue` 与 `doctor` 主体一致、Gemfile 段与 `env` 共用），与 `spec/m7_env_output_spec.cr` 合计 12 例 0 失败。
- 负向对照：`05cedfe` 旧二进制运行两新夹具 0 passed / 2 failed（`Could not locate Gemfile`、缺锁、缺 doctor 结论）。

### 门禁

`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff --cached --check`、`git diff 05cedfe..HEAD --check` 全部 EXIT 0（仅 2 条既有 `Deprecated File.executable?` 警告）。

### 已声明差异 / 未验证

- `issue-no-gemfile` 标记为 deferred（两 profile）：无 Gemfile 时参考会回溯到**宿主机** `~/.bundle/config`（harness 的 `HOME` 是 POSIX 风格路径，RubyGems 判定不可用后回落到开发者主目录），输出随开发机配置变化；这是夹具环境泄漏而非产品差异，未放宽 N5 比较。
- `doctor` 的完整诊断面（`check_home_permissions`、`check_path_components`、`check_gem_path` 等）未实现，本实现只覆盖依赖满足/缺失与锁文件写入；`--verbose` 分层未对齐。
- 未验证 Windows 信号/句柄细节；未重跑全量 spec、全量差分与上游 64 例套件。
## 2026-11-20（M7(3) task-50：`info`/`show` 读取真实 gemspec 元数据）

**结论**：`bundle info`/`show` 的 `Summary`/`Homepage`/`Documentation`/`Changelog` 等字段现在与参考一致——由 Ruby 解释器 `Gem::Specification.load` 求值后取 `summary`/`homepage`/`metadata`，不再由 Crystal 正则截取 `.gemspec` 文本。此前 `\\`、`\"`、`\n` 会以字面量形式输出。

### Oracle（4.0.24 与 2.7.2 一致）

用一个手写的已安装 spec（`bundle-preset/ruby/4.0.0/specifications/meta_gem-1.0.0.gemspec`，含 `s.summary = 'Summary with "quotes" and \\ backslash'`、`"documentation_uri" => "path\\with\\backslashes"`、`"changelog_uri" => "line1\nline2"`）：

| 命令 | 参考输出（解码后） | 修复前 celerite |
| --- | --- | --- |
| `info meta_gem` | `Summary: Summary with "quotes" and \ backslash`；`Documentation: path\with\backslashes`；`Changelog: line1` + 换行 + `line2` | `\\`、`\\`、字面 `\n` |
| `info --path` / `show` / `show --paths` | 仅路径或“missing”警告，不受转义影响 | 一致 |
| `list` | `  * meta_gem (1.0.0)` | 一致 |
| spec 存在、gem 目录缺失 | stderr `The gem meta_gem is missing. Gemspec information is still available though:` + 同样解码后的块，exit 0 | 修复前也会打印该块，但转义未解码 |

构建带这种 metadata 的真实 gem 会被 RubyGems 拒绝（`Gem::InvalidSpecificationException: metadata['documentation_uri'] has invalid link`），因此 oracle 与差分夹具都使用手写 spec——这也正是 `bundle info` 的读取方式（`Gem::Specification.load`，不做 URI 校验）。

### 根因与实现

- 根因：`src/celerite/cli/commands.cr` 的 `read_gemspec_info` 只用正则从 `.gemspec` 文本里截取字面量，周围引号被去掉，但 Ruby 的转义序列从未求值。
- 新 bridge op `assets/bridge/server.rb op_load_installed_spec` → `Gem::Specification.load(path)`，返回 name/version/platform/full_name/summary/description/homepage/license/licenses/metadata；`src/celerite/bridge/client.cr load_installed_spec(path)` 调用。
- `read_gemspec_info` 记住命中的 spec 路径（已安装 `specifications/`、ABI 目录、`specifications/default/`、gem 目录内 `*.gemspec` 四处），优先 `read_gemspec_info_via_bridge`；仅在 bridge 不可用或求值失败时回退 `parse_gemspec_text` + `decode_ruby_string`（覆盖 `\\`、`\"`、`\'`、`\n`、`\t`、`\r`、`\e`、`\s`、`\0`、续行、`\xNN`、`\uXXXX`、`\u{…}`）。该回退是显式声明的降级路径，不是主路径。
- 参考锚点：`bundler/lib/bundler/cli/info.rb:50-73`（`spec = definition.specs...`、`Bundler.ui.info` 打印 `spec.summary`/`spec.metadata[...]`）、`bundler/lib/bundler/cli/common.rb` 的 gem 信息打印；我方锚点 `src/celerite/cli/commands.cr`（`read_gemspec_info`/`read_gemspec_info_via_bridge`/`parse_gemspec_text`/`decode_ruby_string`）、`src/celerite/bridge/client.cr`、`assets/bridge/server.rb`。

### 测试与证据

- 差分夹具 `fixtures/differential/info-metadata-escapes/`：手写 spec + `gems/meta_gem-1.0.0`、`Gemfile`、`Gemfile.lock`，命令依次 `info meta_gem`、`info --path meta_gem`、`show meta_gem`、`show --paths meta_gem`、`list`。4.0.24 `PASS (exit=0)`，2.7.2 `PASS (exit=0)`。
- 新增 `spec/m7_gem_info_metadata_spec.cr` 3 examples（反斜杠转义、`\n` 真实换行、spec-only 回退）：`3 examples, 0 failures`。
- 受影响 spec 家族（`m7_info*`、`m7_show*`、`m7_list*`、`m7_installed_discovery`、`m7_default_gem`、新 spec）合计 **65 examples / 0 failures**。
- 反向对照：`git worktree add C:/temp/celerite-pre50 efaa289` 构建旧二进制后跑新夹具 → **0 passed / 1 failed**，差异正是 `\\` 与 `\n` 未解码；对照后移除 worktree。
- 回归差分（28 个 `info*`/`show*`/`list*`/`install-check`/`install-fresh` 夹具）：4.0.24 **28 passed / 0 failed**，2.7.2 **28 passed / 0 failed**。
- 门禁：`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff efaa289..HEAD --check`、`git diff --check` 全部 EXIT 0（仅既有 2 条 `Deprecated File.executable?` 警告）。

### 已声明差异 / 未验证

- 无 Ruby 解释器时的文本回退路径只做转义解码，不还原 Ruby 的全部字面量语义（例如 `#{...}` 插值、heredoc、`%q`/`%Q` 边界）；主路径始终走 bridge。
- 未验证第三方 gemspec 中 `metadata` 使用 `\u{...}`/`\xNN` 等罕见转义的真实生态案例；spec 已覆盖解码函数本身，但无差分夹具。
- 未重跑全量 `crystal spec`、全量差分与上游 64 例套件。

## 2026-11-20（M7(8) task-51：`bundle cache` 根目录与 `BUNDLE_APP_CONFIG`）

- 参考语义：`Bundler.app_cache` = `root.join(settings.app_cache_path)`（`bundler.rb:340-343`、`settings.rb:304-306`），`--cache-path` 相对根解析；`BUNDLE_APP_CONFIG` 绝对或相对根优先于 `<root>/.bundle`（`bundler.rb:326-339`），插件根同源。
- 修复：`src/celerite/cli/commands_install.cr` 缓存目标改为 `File.dirname(definition.gemfile_path)` 下的 `vendor/cache`（`--cache-path` 相对根）；`src/celerite/config.cr` 新增 `Config.app_config_path`/`app_config_root`；`plugin_commands.cr`、`plugin_hooks.cr`、`commands.cr`、`commands_surface.cr`、`commands_install.cr` 的插件根统一走该函数。
- 插件缺省措辞：`plugin_install_remote` 增加 `remote_only` 形参，仅 `Plugin.gemfile_install` 路径且已注册 source 时启用，恢复 `plugin-source`/`plugin-gemfile-missing` 的旧措辞并保持 `plugin-source-gem-end-to-end` 的 `, cached gems or installed locally`。
- 差分工具：`script/differential` 支持每夹具 `env` 文件（`KEY=VALUE`，双侧注入），头部 N10 说明。
- oracle（4.0.24/2.7.2，cwd≠Gemfile 根）：参考把缓存写入 `<root>/vendor/cache`，我方旧实现写 `<cwd>/vendor/cache`；`config get` 显示 `<app>/appcfg/config`，旧实现 `.bundle/config`；相对 `BUNDLE_APP_CONFIG=relcfg` 解析为 `<app>/relcfg`。
- 夹具 `cache-into-gemfile-root`、`config-app-config-env` 双 profile PASS；旧二进制 2 FAIL（缓存落 cwd、配置落 `.bundle`）。
- spec `spec/m7_cache_path_spec.cr` 3 examples、`spec/m7_app_config_env_spec.cr` 4 examples；12 个 cache/config/plugin 家族 spec 文件逐个跑合计 60 examples / 0 failures（合并单进程运行时偶发崩溃，已改逐个跑）。
- 回归：cache/config/plugin 夹具 4.0.24 42 passed/3 failed（`cache-all-platforms`、`plugin-git-local`、`plugin-git-local2` 为 msys `0xC0000022` 环境噪声；同批基线单独跑曾 PASS，失败签名一致），2.7.2 30 passed/0 failed/2 skipped。
- 未验证：2.7.2 `cache --all`/`--path` 的废弃开关行为（探针被 4.0.24 BUNDLED WITH 污染）、`BUNDLE_APP_CONFIG` 下 deployment/exec 交互、全量 spec/差分未复跑。复选框保持 `[ ]`。
### cache-all-platforms：宿主机原生扩展构建限制（非产品缺陷）

- 同一份 HEAD 源码，从仓库长路径 `C:/Users/ShiningRay/projects/ShiningRay/celerite` 构建的二进制 11943198 字节，跑该夹具 3/3 FAIL：`Gem::Ext::BuildError` + `make.exe *** fatal error - NtCreateDirectoryObject(...): 0xC0000022`（Low-IL msys）。
- 从短路径 worktree `C:/temp/celerite-rebuild` 构建的二进制 11939614 字节，连跑两次 PASS；旧版 `a4f918e` 二进制亦 PASS；手工沙箱里三个新旧二进制全部 FAIL（无 harness 时也失败）。
- 结论：失败随构建路径/宿主环境变化，与源码改动无关，属宿主机原生扩展构建限制，不是产品缺陷。
- 该夹具已标记 `deferred-4.0.24`/`deferred-2.7.2`；恢复条件：在能正常编译原生扩展的宿主（非 Low-IL msys）上重跑并移除标记。
## 2026-11-20（M7(3) task-52：安装后自动清理）

- 语义：`BUNDLE_CLEAN=true` 时，`install`/`update` 在安装结束后按参考 `Bundler::Cleaner.new(definition, false, false).run` 清理 bundle 路径内不属于锁文件的 gem（`cli/common.rb:150-156`、`cli/install.rb:69`、`cli/update.rb:84`）。
- oracle（4.0.24 与 2.7.2，file:// 索引 + 已装 thor/json_pure，Gemfile 删去 thor）：`install` 输出 `Removing thor (1.3.2)` 位于 `Bundle complete!`/`Bundled gems are installed into …` 之后；同时删两个 gem 时按名称序输出 `Removing json_pure (2.8.1)`、`Removing thor (1.3.2)`；未设 `BUNDLE_CLEAN` 无该行且目录保留；`update --all` 在 `Bundle updated!` 之前输出；两版措辞一致（gem 计数按各自版本）。
- 差异声明：参考 `install` 不接受 `--dry-run`（`Unknown switches "--dry-run"`，exit 15）；`clean --dry-run` 仍输出 `Would have removed <name> (<version>)` 且不删除，与本实现一致。本轮按此实测实现，未自创 `install --dry-run` 语义。
- 实现：`src/celerite/cli/commands_install.cr` 抽出 `perform_clean` 供 `clean` 与新增 `clean_after_install` 共用；`install` 在 cooldown 摘要后、funding 提示前调用，`update` 在 `Bundle updated!` 前调用；清理对象为 `<bundle>/gems`、`specifications`、`cache` 与 stale git checkout，仅 gem/git 目录删除打印 `Removing`。
- 夹具：`fixtures/differential/install-clean-after-install/`（`env` 设 `BUNDLE_CLEAN=true`，`bundle-preset` 预置 json_pure+thor，`installed-tree` 断言 thor 目录消失）与 `install-clean-disabled/`（无 env，目录保留）；双 profile PASS。
- spec：`spec/m7_clean_after_install_spec.cr` 4 examples（install 清理与位置、未设/显式 false 不清理、update 在 `Bundle updated!` 前清理）。
- 反假绿：`C:/temp/celerite-pre52`（cb410b6）构建成功，正例夹具 0 passed/1 failed（`Only in SANDBOX/bundle/ruby/4.0.0/specifications: thor-1.3.2.gemspec`），反例夹具 PASS（无判别力，仅回归）。
- 门禁：`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`git diff HEAD --check` 均 EXIT 0；目标 spec 4/0；差分正反两例双 profile PASS。
## 2026-11-20（M7(3) task-53：`bundle doctor` 子命令面与 Windows dylib 警告）

**范围**：`doctor`（默认 `diagnose` 子命令）的 help/参数错误文案、`--quiet`、`--gemfile`，以及非 darwin/linux 主机上的 `*.bundle` 警告。`doctor ssl` 的 TLS 诊断仍属下一任务，本轮只保留命令面（不解析 `--ssl` 参数）。

**oracle（4.0.24 与 2.7.2 逐字一致，隔离 HOME/BUNDLE_PATH）**

| 场景 | 参考行为 |
| --- | --- |
| `doctor --help` | exit 0，2490 字节 manpage（CRLF），两版本文本相同 |
| `doctor diagnose --help` | exit 15，stderr `ERROR: "bundle help" was called with arguments ["doctor", "diagnose"]` + `Usage: "bundle help [COMMAND]"` |
| `doctor nosuchsub` | exit 15，stderr `ERROR: "bundle doctor diagnose" was called with arguments ["nosuchsub"]` + `Usage: "bundle doctor diagnose [OPTIONS]"` |
| `doctor`（依赖已满足） | exit 0，stdout `The Gemfile's dependencies are satisfied` + `No issues found with the installed bundle` |
| `doctor --quiet` | exit 0，stdout 为空 |
| `doctor --gemfile other.rb` | exit 0，输出同默认 |
| 已装 gem 含 `lib/fake.bundle` | stdout 不变，stderr 每个文件一行 `Dynamic library check not supported on this platform.`；`--quiet` 抑制 stdout 但保留警告 |

**根因与实现**

- `--help` 原在 `src/celerite/cli/commands.cr:91` 被统一截获，`doctor` 看不到子命令 token，导致 `doctor diagnose --help` 直接打印 manpage。参考 `bundler/cli.rb:589-602`：Thor 子命令类的 `--help` 会把子命令名并入 `bundle help` 参数，`doctor diagnose --help` 实为 `bundle help doctor diagnose`，参数过多而报错。现对 `doctor` 收集 `--help` 之前的非开关 token 一并交给 `help`（`commands.cr:91-104`）。
- `src/celerite/cli/commands_surface.cr:841-865`：`doctor` 去掉自实现的 help 分支；`diagnose` 为默认，其余 token 报参考同款错误；`--gemfile` 临时设置 `BUNDLE_GEMFILE`（`ensure` 恢复）。
- `doctor_report`（`commands_surface.cr:883-925`）新增 `quiet` 参数：满足时只跳过 stdout；随后对每个已装 gem 扫描 `**/*.bundle`，命中即输出上述警告。`check_home_permissions` 未实现（本机无法构造可触发的 oracle，见“未验证”）。
- Crystal 的 `File.join` 在 Windows 用 `\`，而 `Dir.glob` 只认 `/`；此处用 `"#{gem_dir.gsub('\\', "/")}/**/*.bundle"` 构造模式（此前的 `File.join` 写法永远匹配不到）。

**测试与证据**

- 夹具：`fixtures/differential/doctor-diagnose-windows/`（预置 json_pure + `lib/fake.bundle`，`command=doctor`）、`doctor-quiet/`、`doctor-help-subcommands/`（`doctor --help`、`doctor diagnose --help`、`doctor nosuchsub`）；4.0.24 与 2.7.2 均 1 passed/0 failed。
- spec：`spec/m7_doctor_diagnose_spec.cr` 5 examples（manpage 首尾与 `## SYNOPSIS`、子命令 help 报错、未知参数报错、`--quiet` 空输出、dylib 每文件一警告且仍报 clean），0 failures。
- 反假绿：`C:/temp/celerite-pre53`（`6bb6965`）构建 EXIT 0；三个新夹具全部 FAIL（缺 dylib 警告 / `--help` 段重复 77 行）。
- 回归差分（`doctor-*`、`issue-*`、`env-*` 10 个夹具）：4.0.24 9 passed/0 failed/1 skipped（`issue-no-gemfile` 既有 deferred），2.7.2 同；相关 spec 文件 9+10+9+3+5 = 36 examples，0 failures。
- 门禁：`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff HEAD --check` 均 EXIT 0（仅两处既有 `Deprecated File.executable?` 警告）。

**未验证 / 声明差异**

- `doctor ssl` 仅命令面：`doctor ssl` 仍报 `bundle doctor diagnose ... ["ssl"]` exit 15；参考的 `--host`/`--tls-version` 与真实 TLS 诊断未实现（下一任务）。
- `check_home_permissions` 无法在本机取得干净的参考 oracle（`BUNDLE_PATH` 缺 `ruby/<abi>` 时参考自身抛 `Errno::ENOENT`），未实现。
- `doctor --verbose`、Windows 信号转发未测。
- 反假绿中 `install-clean-disabled` 类无判别力的情况不适用于本轮三个夹具（旧二进制均 FAIL）。
## 2026-11-20（M7(3) task-54：`doctor ssl` 与 `diagnose --ssl`）

- 范围：`bundle doctor ssl`（`--host`/`--tls-version`/`--verify-mode`）与 `doctor diagnose --ssl`。参考 `cli/doctor.rb:13-31` 定义 `ssl` 子命令及其三个选项、`diagnose` 的 `--ssl` 布尔开关；`cli/doctor/diagnose.rb:77-79` 在依赖检查之后、dylib 扫描之前以**空选项**调用 `SSL.new({}).run`，因此 diagnose 的 SSL 报告恒指向默认主机 `rubygems.org`。`cli/doctor/ssl.rb:14-24` 先打印解释器 OpenSSL 版本，再依次探测 Bundler（`Bundler::Fetcher`）、RubyGems（`Gem::RemoteFetcher`）、Ruby `net/http`，最后按三条探测结果给出四选一结语；探测失败只 warn，子命令退出码恒 0。
- oracle（参考 4.0.24 与 2.7.2，隔离 HOME/BUNDLE_PATH）：

| 场景 | 参考 stdout | 参考 stderr | exit |
| --- | --- | --- | --- |
| `doctor ssl --help` | 空 | `ERROR: "bundle help" was called with arguments ["doctor", "ssl"]` + `Usage: "bundle help [COMMAND]"` | 15 |
| `doctor ssl --host no-such-host.invalid` | `Here's your OpenSSL environment:` 空行、`OpenSSL:       4.0.2`、`Compiled with: OpenSSL 3.6.3 9 Jun 2026`、`Loaded with:   OpenSSL 3.6.3 9 Jun 2026`、空行、`Trying connections to https://no-such-host.invalid:` | `Bundler:       failed …`、`RubyGems:      failed …`、`Ruby net/http: failed` + `Unfortunately…` + 完整错误块 | 0 |
| `doctor ssl`（默认 rubygems.org） | 同上 + `Bundler:       success`、`Ruby net/http: success` + 结语 | 视网络/CA 而定 | 0 |
| `doctor diagnose --ssl --host x` | 空 | `ERROR: "bundle doctor diagnose" was called with arguments ["--host", "x"]` + `Usage: "bundle doctor diagnose [OPTIONS]"` | 15 |
| `doctor diagnose --ssl` | `Resolving dependencies...`、`The Gemfile's dependencies are satisfied`、SSL 报告、结语 | 沙箱内参考自身触发 `--- ERROR REPORT TEMPLATE`（`check_home_permissions` 的 `Errno::ENOENT`） | 1（沙箱伪影） |

- 实现：`src/celerite/cli/commands_surface.cr` 新增 `doctor_ssl`（解析三个选项；三个版本行取自 bridge 返回的 Ruby `OpenSSL::VERSION`/`OPENSSL_VERSION`/`OPENSSL_LIBRARY_VERSION`，不用 Crystal 自身常量；Bundler 与 `net/http` 探测走 bridge `ssl_probe`，RubyGems 探测由 Crystal `HTTP::Client` 以默认 CA 校验完成；失败措辞与四选一结语照 `ssl.rb:148-231`；`quiet` 只压 info，不压 warn）；`doctor` 在 `arguments.first? == "ssl"` 时分派，`diagnose --ssl` 在依赖检查后调用同一函数；`--help` 仍由 `commands.cr:91-104` 统一转成 `bundle help doctor ssl`，故 help 语义与 task-53 一致。
- bridge 协议：`assets/bridge/server.rb` 新增 `ssl_openssl_versions`（返回 Ruby 侧三个 OpenSSL 常量）与 `ssl_probe`（`Net::HTTP` + 可选 `min_version`/`max_version`/`verify_mode`，失败返回异常 class/message/backtrace）；`src/celerite/bridge/client.cr` 对应 `ssl_openssl_versions`/`ssl_probe`，探测超时 10s + 5s RPC 余量。
- 测试：`fixtures/differential/doctor-ssl-help`（exit 15、两行 stderr 逐字）、`doctor-ssl-bad-host`（stdout 逐字比对 env 块与 `Trying connections…` 行；stderr 用 `stderr-contains` 只断言 `Bundler:       failed` 与 `Ruby net/http: failed`，因为 RubyGems 探测在两侧分别由 Ruby/Crystal 发起，异常措辞不同）、`doctor-diagnose-ssl-host`（exit 15、两行逐字）；4.0.24 与 2.7.2 均 3 passed/0 failed。`spec/m7_doctor_ssl_spec.cr` 5 examples（help、不可达主机的 env 块与 exit 0、`--tls-version`/`--verify-mode` 透传、diagnose 拒绝 `--host`、`diagnose --ssl` 的 OpenSSL 块位于 satisfied 之后且仍以 `No issues found…` 收尾），0 failures；与 `m7_doctor_diagnose_spec.cr` 合并 10 examples/0 failures。
- 反假绿：`C:/temp/celerite-pre54`（`7116b6c`）构建 EXIT 0；三个新夹具 2 passed/1 failed——`doctor-ssl-bad-host` 失败（缺整段 stdout），`doctor-ssl-help` 与 `doctor-diagnose-ssl-host` 在旧二进制上本就一致（help 走 task-53 的统一路由），因此这两条无判别力，属回归网。
- 回归：`doctor-diagnose-windows`、`doctor-quiet`、`doctor-help-subcommands`、`issue-satisfied` 两 profile 各 4 passed/0 failed。
- 门禁：`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff HEAD --check` 均 EXIT 0（仅既有两处 `Deprecated File.executable?` 警告）。
- 未验证 / 声明差异：
  1. `doctor diagnose --ssl` 的结语分支与退出码取决于网络与 CA；参考在本沙箱因 `check_home_permissions` 的 `Errno::ENOENT` 退出 1，我方退出 0，故该路径不做差分夹具，仅 spec 断言结构。
  2. `--tls-version`/`--verify-mode` 已透传，但本机 OpenSSL 3.6 下只验证到错误类（如协议不可用），未与参考逐字比对错误文本。
  3. `check_home_permissions` 仍未实现（与本任务无关）。
  4. `doctor ssl` 默认主机路径的结语文本依赖真实连通性，未纳入夹具。
## 2026-11-20（M7(2) task-55：`bundle add` 的 glob/version/path 选项面）

范围：`bundle add` 的三个静默失败面，以及 `update --redownload` 别名。参考 Bundler 4.0.24，2.7.2 行为一致（`Invalid gem requirement pattern` 与 `PathError` 文本逐字相同）。

| 场景 | 参考 4.0.24 | 修复前 | 修复后 |
| --- | --- | --- | --- |
| `add json_pure --glob sub/*.gemspec --skip-install` | exit 0，Gemfile 追加 `gem "json_pure", "~> 2.8", glob: "sub/*.gemspec"` | exit 0，`glob:` 被丢弃 | 逐字一致 |
| `add thor --version --skip-install` | exit 15，stderr `Invalid gem requirement pattern 'version'\n`，Gemfile 未改 | exit 0，实际安装并写入 `~> 2.8` | exit 15，未写入 |
| `add json_pure --path vendor/x --skip-install` | exit 13，stderr 三行（friendly errors 折行）`The path\n\`…/vendor/x\`\ndoes not exist.\n`，Gemfile 未改 | exit 7，且已写入 `path:` | exit 13，逐字一致，未写入 |
| `update --redownload` | 接受（`cli.rb:330` 中 `force` 的别名），exit 0 | exit 15 `Unknown switches "--redownload"` | 接受，按 `--force` 处理 |

glob 归一化另测：`--glob "sub/*.gemspec"`、`--glob "{a,b}.gemspec"` 逐字写入；唯独 `--glob "*.gemspec"` 参考写成 `glob: "celerite.gemspec"`（原因不是 Bundler 归一化，而是宿主 `ruby.exe` 的 argv cmdglob；机制见 task-59 节 `docs/compat-report.md:5422`。夹具只用逐字形式）。

根因与实现：
- `src/celerite/cli/commands_surface.cr` `add_option_suffix` 缺 `glob` 分支 → 补 `glob: #{glob.inspect}`（参考 `injector.rb:114`）。
- `add()` 缺 `--version` 取值校验 → 在 `Definition.build` 前按 `cli/add.rb:57-59` 报 `Invalid gem requirement pattern 'version'`，exit 15。
- `--path` 在注入前未校验 → 新增 `src/celerite/errors.cr` `PathError`（status 13，`wrap? true`，参考 `errors.rb:32`、`source/path.rb:198-204`），在 `add()` 中先展开路径并抛 `The path \`<abs>\` does not exist.` / `is not a directory.`，保证 Gemfile 不被改写。
- `src/celerite/cli/commands.cr:931` `UPDATE_SWITCH_FLAGS` 增加 `--redownload`；`run_update` 的待装集合在 `--force`/`--redownload` 下不再剔除已安装 gem。

证据：
- 夹具 `fixtures/differential/add-glob-option`、`add-version-missing-value`、`add-path-missing`，4.0.24 与 2.7.2 均 3 passed / 0 failed。
- 回归（21 个 `add-*` 夹具 + `install-fresh` + `install-check`）：4.0.24 15 passed / 6 failed，2.7.2 15 passed / 5 failed / 1 skipped。6 个失败全部是宿主机 msys 命名对象限制（`make`/`git` 的 `0xC0000022`：`add-group`、`add-optimistic`、`add-version`、`add-remove` 为 racc 原生扩展；`add-git`、`add-ref` 为 git clone），与改动无关；`cache-all-platforms` 的 deferred 标记记录同一类限制。旧二进制在短路径 worktree（`C:/temp/celerite-pre55`）下偶发通过同一批夹具，属路径长度相关噪声。
- 反假绿：`C:/temp/celerite-pre55` @ `eca65ed` 旧二进制跑三条新夹具 0 passed / 3 failed（glob 未写入、version 实际安装、path 改写 Gemfile）。
- 门禁：`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff HEAD --check` 全部 EXIT 0；目标 spec `spec/m7_add_options_spec.cr` 4 examples / 0 failures。

声明差异 / 未验证：
1. `--glob "*.gemspec"` 写成 `celerite.gemspec` 来自宿主 `ruby.exe` argv 的 cmdglob（见 task-59 节 `docs/compat-report.md:5422`），不是 Bundler 归一化；夹具不覆盖该形式。
2. `--bundler <ver>` 仍是 accept-only（未实现 bundler 自重装）。
3. `--strict --skip-install` 参考多一次 resolve 的问题未在本任务处理。
4. `update --redownload` 按 `--force` 处理，未做缓存失效（不重新下载已有 cache）。
5. 全量 `crystal spec` 与上游 64 例未重跑。

## 2026-11-20（M7(2) task-56：plugin new / licenses 顺序 / config 本地路径 / 死代码）

四个小面收敛，参考 4.0.24 与 2.7.2 逐字节实测：

| 面 | 参考行为 | 修复前 | 修复后 |
| --- | --- | --- | --- |
| `plugin new foo` | exit 15，stderr `Could not find command "new".` | exit 1，`The 'plugin new' command is not implemented yet.` | 与参考一致 |
| `licenses` | `json_pure: Ruby` / `bundler: MIT` / `thor: MIT`（按 license 降序，含 bundler 自身） | `json_pure, thor, bundler` | 与参考一致 |
| `config get` 本地路径 | 绝对 `BUNDLE_APP_CONFIG` 保留原生分隔符，后缀 `/config`；默认 `<app>/.bundle/config` 为 `/` | 全部统一 `/` | 绝对路径保留原样，默认仍 `/` |
| `known_unimplemented?` | 参考无此集合 | 死代码，命令表里不可达 | 删除，未知命令走统一 `Could not find command` |

实现锚点：`src/celerite/cli/commands_surface.cr` 插件分派删除 `new` 分支；`licenses` 取 `Bundler.load.specs` 语义（锁文件 specs + `bundler` 自身，按 license 降序、同 license 按 full_name 升序，参考 `cli.rb:570-583` 的 `sort_by {|s| s.license.to_s }.reverse_each`）；`src/celerite/config.cr` `app_config_path` 对绝对 `BUNDLE_APP_CONFIG` 原样返回（`Pathname#expand_path` 不改绝对路径），`join_config` 固定 `/`，`local_config_file` 原样打印。

测试/夹具：`fixtures/differential/plugin-new-unknown`、`licenses-order`、`config-local-app-path`（`config-local-app-path` 为回归护栏：默认 `<app>/.bundle/config` 两侧本就一致，旧二进制也 PASS，无区分力；绝对反斜杠路径的区分性由 `spec/m7_micro_divergences_spec.cr` 覆盖）；`spec/m7_micro_divergences_spec.cr` 5 例。

证据：新夹具 4.0.24 3/0、2.7.2 3/0；回归 13 例 4.0.24 13/0、2.7.2 11/0/2 skipped（既有 config 2.x deferral）；负向 `C:/temp/celerite-pre56`（`4c47ba5`）新夹具 1 passed / 2 failed（`plugin-new-unknown`、`licenses-order`）。

未对齐/未验证：`licenses` 同 license 的并列顺序依赖 `Bundler.load` 顺序，这里按 full_name 固定，未构造同 license 不同装载顺序的对照；`plugin new` 在无 Gemfile 目录下的表现未单独取 oracle；全量 spec 与上游 64 例未重跑。
## 2026-11-20（M7(3) task-57：`bundle update --bundler` 的目标解析与 `BUNDLED WITH`）

- 参考链：`cli/update.rb:14` 读取 `--bundler`，`:16` 交给 `Bundler.self_manager.update_bundler_and_restart_with_it_if_needed`；`self_manager.rb:33-46` 解析目标 → 打印 `Updating bundler to <version>.` → 必要时安装 → `restart_with`（无条件 `Kernel.exec`）；解析失败由 `cli/update.rb:111-116` 抛 ``The `bundle update --bundler` target version (<target>) does not exist``（`InvalidOption`，exit 15）。`--bundler` 计入 scoped 更新，未安装项目先报 22。
- 根因：我方只在 `UPDATE_SWITCH_VALUES`/`LOCK_SWITCH_VALUES` 白名单里接受 `--bundler`，没有任何目标解析；裸 `--bundler` 还会走进普通 `update` 的废弃提示路径。
- oracle（4.0.24 / 2.7.2，`file://` 索引 + 项目内 `.bundle/config` 镜像；环境变量形式的 `BUNDLE_MIRROR__HTTPS://RUBYGEMS.ORG` 在参考实现里因 `settings.rb` 键名往返被改写为 `…RUBYGEMS__ORG/` 而失效，报 `ArgumentError: Gem sources must be absolute`）：

  | 场景 | 4.0.24 | 2.7.2 |
  | --- | --- | --- |
  | `update --bundler`（裸） | exit 15，stderr `(>= 4.0.24)`；stdout 一行 `Fetching source index from …` | exit 0，正常更新；stdout **两行** `Fetching source index from …`，无 `Updating bundler` |
  | `update --bundler 9.9.9`（索引无该版本） | exit 15，stderr `(9.9.9)` | exit 15，stderr `(9.9.9)` |
  | 索引含伪 `bundler 9.9.9`，`update --bundler 9.9.9`（**须在项目 `.bundle/config` 镜像前置下观察**：项目内配置 `BUNDLE_MIRROR__HTTPS://RUBYGEMS.ORG` 指向该索引） | exit 0，`Updating bundler to 9.9.9.`，锁 `BUNDLED WITH` 变 9.9.9；随后参考 `exec` 重启并挂起（45 秒强杀，锁未写完） | 参考同样先 `exec` 重启，未作逐字对照 |
  | `lock --bundler 4.0.20` | exit 0，锁不变（`BUNDLED WITH` 仍为 4.0.24） | 同左 |

- 实现锚点：`src/celerite/resolution.cr` 新增 `bundler_versions(requirement)`（只查远端 `bundler` 版本，不回落本地/default gem）与 `bundler_version_to_lock`，后者只影响 `BUNDLED WITH` 与 bundler 的 CHECKSUMS 条目；`src/celerite/cli/commands_surface.cr` 新增 `update_bundler_target(rest)`（区分未出现/裸值/显式值），裸值时 4.x 目标 `>= 当前版本`、2.x 目标 `> 0.a`（对应 `cli.rb:332`/`:266` 的 `lazy_default`），解析失败按参考原文 exit 15，成功时打印 `Updating bundler to …` 并继续正常 update。参考的 self-manager 与 update 各自打印一次索引行，我方 resolution 只取一次，故在置位时补打第二行。
- 夹具/测试：`fixtures/differential/update-bundler-missing-value`、`update-bundler-nonexistent`（`extra/.bundle/config` 项目镜像；`env` 值也支持占位符替换，`extra/**` 替换范围扩到 `.bundle/config`）；`spec/m7_update_bundler_spec.cr` 4 例（裸 4.x 报错、显式缺失、伪 9.9.9 成功写 `BUNDLED WITH`、2.x 裸值保持不变）。
- 证据：新夹具 4.0.24 2/0、2.7.2 2/0；目标 spec 4/0；回归 `update-*`/`lock-*`/`install-fresh`/`install-check` 两 profile 各 33/1（唯一失败 `lock-missing-dependency-edges` 是既有差异：Ruby 4.0 把 `net-protocol` 当内置 gem，我方跳过下载而参考仍安装，基线二进制 `9e98ed8` 同样失败）；负向 `C:/temp/celerite-pre57`（`9e98ed8`）新夹具 0 passed / 2 failed（旧二进制 exit 0 且带废弃提示/正常更新，缺 15 与目标措辞）。
- 未对齐/未验证：未实现 self-manager 的安装 + `Kernel.exec` 重启（我方只解析目标并继续一次普通 update，避免不可判定的重启循环）；伪 `bundler 9.9.9` 的 CHECKSUMS 复用 4.0.24 的 sha（合成索引，非真实包）；2.7.2 裸值补打的第二行索引是行为复刻，不作语义保证；环境变量镜像形态的失败属参考侧缺陷，未修；`gem-index-bundler` 仅用于测试，不进入产品路径。
**补记（task-58 复核）**：上表伪 `bundler 9.9.9` 一行必须在项目 `.bundle/config` 镜像前置下观察。无此前置时参考会先向 `https://rubygems.org` 解析目标版本，沙箱下大概率拿到网络错误或与本地 `>= 4.0.24` 不同的目标，不会稳定得到 exit 0；且参考命中目标后会 `exec` 重启同一条命令并挂起（本机 45 秒后强杀，`Gemfile.lock` 未写完），故该行不能作为「无镜像也能 exit 0」的证据。
## 2026-11-20（M7(2) task-58：`bundle lock` 的 `--normalize-platforms` 与 `--lockfile`）

- 参考链：`cli/lock.rb:74-75` → `definition.rb:532-533 normalize_platforms` → `spec_set.rb:38-40 normalize_platforms!`，后者先 `remove_invalid_platforms!`（`:52-63`）再 `add_extra_platforms!`（`:66-89`），最后把带版本号的平台降到通用形态。`add_extra_platforms!` 对「所有源都能完整满足、且 `Gem::Platform.generic == ruby`」的平台补齐；纯 Ruby 依赖因此新增 `ruby`。
- `--lockfile` 语义：`cli.rb:69-77` 对 `lock` **不做** `BUNDLE_LOCKFILE` 提升，`cli/lock.rb:81-93` 只把该选项展开成写出的目标路径；读入仍走 `Bundler.default_lockfile`（`shared_helpers.rb:25-36`）。
- 我方根因：①`src/celerite/resolution.cr` 的 normalize 分支只做「去版本号」，缺 `add_extra_platforms!` 的补 `ruby`；②`src/celerite/cli/commands.cr` 的 `with_gemfile_overrides` 把 `lock --lockfile` 提升成 `BUNDLE_LOCKFILE`，于是 `Definition#lockfile_exists?` 对 `custom.lock` 为假，绕过 no-op 短路，多出一次解析。

  | 场景 | 4.0.24 | 2.7.2 |
  | --- | --- | --- |
  | 装好 `json_pure` 后 `lock --normalize-platforms` | exit 0；`PLATFORMS` 由 `x64-mingw-ucrt` 变为 `ruby` + `x64-mingw-ucrt`（按名字排序，`ruby` 在前）；先打 `Fetching source index …` 再 `Writing lockfile …` | 同左（仅 `BUNDLED WITH` 缩进 3 空格） |
  | 连续两次 `lock --normalize-platforms` | 第二次锁文件逐字节不变（幂等） | 同左 |
  | `lock --normalize-platforms --print` | 正文走 stdout、`Fetching source index` 走 stderr；`PLATFORMS` 同样含 `ruby` | 同左 |
  | 装好后 `lock --lockfile custom.lock` | exit 0；stdout 仅一行 `Writing lockfile to …/custom.lock`（无 `Fetching`、无 `Resolving`）；`custom.lock` 与 `Gemfile.lock` 内容一致，原 `Gemfile.lock` 不被改写 | 同左 |
  | `lock --lockfile` 指向已存在的 `Gemfile.lock` | 走 no-op，无解析行 | 同左 |

- 实现要点：`Resolution` 的 normalize 分支在「解析结果里存在无平台/`ruby` 平台的 spec」时补 `ruby`；`Commands.lock` 改用 `with_gemfile_overrides(rest, lockfile_env: false)`（`--gemfile` 仍照旧提升），`run_lock` 单独算出 `lockfile_write_path`（`--lockfile` 展开，否则沿用定义路径），全部「Writing lockfile」与 `Lockfile.write` 都走该路径，no-op 判断仍基于 `definition.lockfile_path`。`check` 的改写路径（`commands.cr:1556`）仍写定义路径，未受牵连。
- 夹具/测试：`fixtures/differential/lock-normalize-platforms`（`install --quiet` 后 `lock --normalize-platforms`，`file-contains` 断言 `  ruby` 行）、`lock-lockfile-option`（`install --quiet` 后 `lock --lockfile custom.lock`，断言 `custom.lock` 段落）；`spec/m7_lock_options_spec.cr` 4 例（补 `ruby`、幂等、读默认锁写自定义路径、`--lockfile` 指向当前锁不重解析）。
- 证据：新夹具 4.0.24 2/0、2.7.2 2/0；spec 4/0；回归 `lock-*` + `install-fresh` + `install-check` + `update-fund-summary` 两 profile 各 25/1（唯一失败 `lock-missing-dependency-edges` 为既有环境差异，见 task-57 记录）；负向 `C:/temp/celerite-pre58`（`a567e5a`）两夹具 0 passed / 2 failed（normalize 缺 `  ruby`；`--lockfile` 多出 `Fetching source index` 与 `Resolving dependencies...`）。
- 未对齐/未验证：`add_extra_platforms!` 的「平台泛化后是否删除本地平台」分支（`spec_set.rb:82-88`）未构造 oracle；`--lockfile` 与 `--print` 同时使用时参考不写文件，我方同样不写，但未单独取 oracle；`--lockfile` 指向不存在的目录等错误面未测。
## 2026-11-20（M7(2) task-59：`bundle add` 位置参数解析与 `install --target-rbconfig`）

- 范围：参考 4.0.24 / 2.7.2 实测的 `add` 参数语义与 `install --target-rbconfig` 失败面；两处均为我方静默成功或错位解析，参考一侧为显式失败/正确写入。
- Oracle（两 profile 一致）：

| 命令 | 参考 | 我方（修复前） |
| --- | --- | --- |
| `install --target-rbconfig nofile.rb` | exit 1；stdout 空；不写 `Gemfile.lock`；stderr 为 `--- ERROR REPORT TEMPLATE` 块，含 `LoadError: cannot load such file -- nofile.rb` | exit 0，继续安装并写锁 |
| `add --version thor --skip-install` | exit 15；stderr `Please specify gems to add.`；Gemfile 不变 | exit 1（`Illformed requirement ["= thor"]`）并写入 `gem "thor", "= thor"` |
| `add`（无位置参数） | exit 15；stderr `Please specify gems to add.` | exit 1；`` `add` requires at least 1 argument `` |
| `add --glob "*.gemspec" thor --skip-install`（存在 `demo.gemspec`） | exit 0；写 `gem "thor", "~> 1.3", glob: "demo.gemspec"` | exit 7；把 `*.gemspec` 当作 gem 名 |
| `add --glob "nomatch*.gemspec" thor --skip-install` | exit 0；`glob` 原样写入 | 同上错位 |

- 机制（为什么 `*.gemspec` 会变成 `demo.gemspec`）：展开发生在 **Windows `ruby.exe` 的 argv 层**（Ruby 的 cmdglob），不在 Bundler。Bundler `dependency.rb:55-58` 原样保存 `glob` 选项，`injector.rb:119` 原样写 `d.glob`；`bundle` 是 Ruby 脚本，通配在进入 Bundler 前已被拆成多个 argv 词（第一个成为 `--glob` 的值，其余成为位置参数）。`ruby -e 'p ARGV' -- --glob "*.gemspec"` 可见 `["--glob", "demo.gemspec", "zzz.gemspec"]`；无命中时保持字面量。因此 `add --glob "*.gemspec" thor` 在两个匹配 gemspec 存在时，参考会因多出的第二个词被当成 gem 名而以 exit 7 失败——这不是“展开成命中文件名”的 Bundler 语义，而是宿主 argv 行为。
- 差分夹具在 bash 层先做通配展开，故两侧拿到同一个 `demo.gemspec`；celerite 不自造展开，保持“选项值不进入位置参数”的 Bundler 语义。
- 实现：`src/celerite/cli/commands_surface.cr` 新增 `add_positional_arguments`（按 Thor 规则跳过 `--flag value`、`--flag=value`、短选项值，`--` 之后全为位置参数）；位置参数为空时输出 `Please specify gems to add.` 并返回 15（`cli/add.rb` `validate_options!`）。`src/celerite/cli/commands_install.cr` 在 `--target-rbconfig` 指向不存在的文件时于解析前中止：打印 ERROR REPORT 模板框架与 `LoadError: cannot load such file -- <path>`，返回 1，且不写锁（参考 `cli/install.rb:24` → `rubygems_integration.rb:34` → `rubygems/target_rbconfig.rb:37`）。
- 测试与证据：夹具 `install-target-rbconfig-missing`（exit=1，`stderr-contains` 两行，`file-absent Gemfile.lock`）、`add-version-value-not-gem`（exit=15，`file-equals Gemfile`）、`add-glob-expand`（exit=0，`glob: "demo.gemspec"`）；4.0.24 与 2.7.2 均 3/0。`spec/m7_add_argument_parsing_spec.cr` 6 examples 0 failures。回归 `add-*` + `install-fresh` + `install-check`：4.0.24 17/6、2.7.2 17/5（失败均为既有 racc/git 的 `0xC0000022` 噪声，与 task-55 基线一致）。负向 `C:/temp/celerite-pre59`（`7420d99`）三夹具 0 passed / 3 failed（exit 1/15/7，多写 `gem "thor", "= thor"`、把 `*.gemspec` 当 gem 名）。
- 声明差异：① 通配仅在宿主 shell/argv 层展开，celerite 不模拟 `ruby.exe` 的 cmdglob（`cmd.exe` 直调时会与参考不同，bash 差分一致）；② `--target-rbconfig` 指向存在文件时我方不加载该文件（仅在原生扩展构建时传给 bridge），参考会立即 `Kernel.load`；③ 错误模板只保留关键行，未逐字复刻 friendly-errors 的完整环境段。

## 2026-11-20（M7(2) task-60：`update --redownload` 的 `Fetching` 行）

- 参考：`update --redownload` 是 `method_option "force"` 的别名（`cli.rb:330`）。强制重装走缓存包（`source/rubygems.rb` 的 `cached_gem` → `rubygems_gem_installer`），不重新下载，因此输出只有 `Installing`，没有 `Fetching`。
- oracle（4.0.24 与 2.7.2 一致；`file://` 索引，隔离 HOME/BUNDLE_PATH）：
  - ① 已安装且 `<bundle>/ruby/4.0.0/cache` 内有包：`Fetching source index …` / `Resolving dependencies...` / `Installing json_pure 2.8.1` / `Bundle updated!`，无 `Fetching json_pure`。4.0.24 stderr 有 `[DEPRECATED] Pass --all to \`bundle update\` to update everything`，2.7.2 无。
  - ② 缓存包被删：exit **5**；stderr `Bundler::GemNotFound: Could not find json_pure-2.8.1.gem for installation` 与 `An error occurred while installing json_pure (2.8.1), and Bundler cannot continue.`。
  - ③ 无先前安装（bundle 目录与 lock 均删）：`Fetching json_pure 2.8.1` / `Installing json_pure 2.8.1` / `Bundle updated!`。
- 实现：`src/celerite/installer.cr` 新增 `cached_package_path`；`src/celerite/cli/commands_surface.cr` 的 update 循环先查 `vendor/cache` 与 `<bundle>/ruby/<abi>/cache`，命中则跳过 `Fetching`，并把缓存包作为 `gem_file:` 传给 `installer.install`。
- 测试与证据：夹具 `update-redownload-output`（`install --quiet` 后 `update --redownload`，stdout 全量比较）双 profile PASS；spec `spec/m7_update_redownload_spec.cr` 3 例（缓存 / 删缓存 / 首次）全过；回归 17 个 fixture 双 profile 全过；反假绿 worktree `a91759b` 上该夹具 FAIL，差异正是多出的 `Fetching json_pure 2.8.1`。
- 声明差异：缓存包被删时参考 exit 5 `GemNotFound`，celerite 仍重新下载并 exit 0（本轮只改打印条件，未改下载行为）；`vendor/cache` 命中路径未单独设夹具；`install --redownload` 在两侧均不存在。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen src/cli.cr` 0、`git diff HEAD --check` 0、`crystal build src/cli.cr -o bin/celerite.exe` 0。

## 2026-11-20（M7(2) task-62：四个「已声明未取 oracle」的组合收口）

本轮把 task-54/58/59/60 里声明为「未验证」的四个组合逐一取双侧 oracle：两处已对齐、一处本该修（已修）、一处不可观测。

| 组合 | 参考（4.0.24 / 2.7.2） | celerite 修前 | 判定 |
| --- | --- | --- | --- |
| `lock --lockfile custom.lock --print` | exit 0；stdout 即整份锁体（无 `Writing lockfile` 行）；不写 `custom.lock`；默认 `Gemfile.lock` 不变；输出 CRLF | 同左（LF） | 已对齐（仅行尾差异，夹具走 N2 归一化） |
| `lock --lockfile ./nodir/x.lock` | exit 1；stdout 先打 `Writing lockfile to <abs>/nodir/x.lock`；不建目录、不写锁；stderr 为 `--- ERROR REPORT TEMPLATE` + `Errno::ENOENT: No such file or directory @ rb_sysopen - <abs>` + 回溯 + `--- TEMPLATE END` + 「Unfortunately…」段 | exit 1、stdout 相同，但 stderr 只有一行 `celerite internal error: Error opening file with mode 'w': …` | **已修**：改为与参考同形的崩溃报告 |
| `install --target-rbconfig <存在的文件>` | exit 0；stdout 与锁均与不带该选项一致（纯 Ruby gem） | 同左 | 不可观测，无产品改动 |
| `install --redownload` | exit 0；`Installing json_pure 2.8.1`；锁不变 | 同左 | 已对齐（回归护栏） |

- 参考锚点：`cli/lock.rb:81-93`（`--lockfile` 只改写入路径）、`definition.rb:437-438`（4.0.24）/ `:408-409`（2.7.2）（`write_lock` 直接 `File.open`，异常交给 friendly errors）、`shared_helpers.rb:106`/`:105`、`cli.rb:278`/`:330`（4.0.24）与 `cli.rb:223`/`:264`（2.7.2）的 `aliases: "--redownload"`、`rubygems.rb:446-450` 与 `rubygems/platform.rb:13-20`（`Gem.set_target_rbconfig` 只刷新 `Gem::Platform.local` / `Gem.platforms`）。
- 实现：`src/celerite/cli/commands.cr` 的 `run_lock` 两处写入改走 `lockfile_write_result(path, text, stderr)`；失败时由 `errno_header` 把 Crystal 的 `File::NotFoundError` / `File::AccessDeniedError` 映射成参考的 `Errno::ENOENT` / `Errno::EACCES` 头，再输出 `--- ERROR REPORT TEMPLATE … --- TEMPLATE END ---` 与「Unfortunately, an unexpected error occurred, and Bundler cannot continue.」并返回 1。
- 测试与证据：新增夹具 `lock-lockfile-print`、`lock-lockfile-missing-dir`、`install-target-rbconfig-present`、`install-redownload-alias`，双 profile PASS；`spec/m7_lock_options_spec.cr` 由 4 例扩到 8 例（`--print` 不落盘、缺目录的崩溃报告、两条回归护栏）；回归 `lock-*` 18 项与 `install-fresh` / `install-check` / `install-target-rbconfig-missing` 双 profile 全过。
- 反假绿：`C:/temp/celerite-pre62`（`1d23b4f`）上只有 `lock-lockfile-missing-dir` FAIL（两条 `stderr-contains` needle 都不满足）；其余三例旧二进制同样 PASS，属纯回归护栏，无区分力。
- 文档修正：task-60 节末尾「`install --redownload` 在两侧均不存在」已过时——两侧都接受该别名（参考 `cli.rb:278`/`:330`），本轮 item 4 即为证。
- 声明差异：`--print` 的行尾参考是 CRLF、我方是 LF（夹具按 N2 归一化，未对齐原始字节）；`--target-rbconfig` 对含原生扩展的 gem 仍不可观测（本轮只测纯 Ruby 的 `json_pure`）。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen src/cli.cr` 0、`crystal build src/cli.cr -o bin/celerite.exe` 0、`git diff HEAD --check` 0。

## 2026-11-20（M7(2) task-63：`bundle binstubs` 渲染 Bundler 模板）

- 根因：旧实现在 `src/celerite/cli/commands_install.cr` 里执行 `content = File.read(<gem>/bin/<exe>)`，把 gem 自带的 executable 原文当作 stub；参考 `Binstub#write`（4.0.24 `binstub.rb:20-27`、2.7.2 `:14-22`）渲染 `lib/bundler/templates/Executable`，stub 只负责把 `bundler/setup` 与 `Gem.bin_path` 重新接起来。

| 项 | 参考 4.0.24 / 2.7.2（实测） |
| --- | --- |
| 默认 `bin/thor` | 347 B、LF、首行 `#!/usr/bin/env ruby`、`File.expand_path("../Gemfile", __dir__)`、`load Gem.bin_path("thor", "thor")` |
| `bin/thor.cmd` | 389 B = `@ruby -x "%~f0" %*\n@exit /b %ERRORLEVEL%\n\n` + 同一 347 B 正文 |
| `--shebang ruby3` | 首行 `#!/usr/bin/env ruby3`（348 B），正文不变；2.7.2 另写 `BUNDLE_SHEBANG: "ruby3"` 到 `.bundle/config`（本实现既有） |
| `--path sub/dir` | 4.0.24 exit 15（已移除，改用 `config set bin`）；2.7.2 exit 0 + `[DEPRECATED]` 警告，产物落 `sub/dir/{thor,thor.cmd}`，相对路径 `../../Gemfile` |

- 模板：`assets/bundler_templates/{4.0.24,2.7.2}/Executable`，各 473 B、LF（4.0.24 侧由 `.upstream-specs/v4.0.24/bundler/lib/bundler/templates/Executable` 的 CRLF 归一化而来，2.7.2 侧取本机 bundler-2.7.2 同路径；两版逐字相同，分开存放以便上游分化时可见）。
- 实现：新增 `src/celerite/binstub_template.cr`——`BinstubTemplate.render(profile, spec_name, executable, relative_gemfile_path, shebang)` 替换四个占位符；`relative_gemfile_path(from_dir, gemfile)` 复刻 `Pathname#relative_path_from`（同盘取公共前缀后补 `..`，跨盘回退绝对路径）；`.cmd` 前缀沿用参考的 `@ruby -x "%~f0" %*` + `@exit /b %ERRORLEVEL%`。
- 为什么此前没被发现：`script/differential:502` 的项目树比较用 `grep -v "^Files .* differ$"`，只报缺失/新增文件，**不比同名文件内容**；既有 `binstubs` 只比 bundle 内 `ruby/*/bin`、`binstubs-shebang` 只断首行。新夹具 `binstubs-template` 直接断 `bin/thor` 的三条正文与 `bin/thor.cmd` 前缀。
- 测试与证据：新差分夹具 `binstubs-template` 双 profile PASS；`spec/m7_binstubs_template_spec.cr` 4 例（模板正文、`--shebang`、`bin` 子目录时的相对路径、`.cmd` 包装）全过。
- 反假绿：`C:/temp/celerite-pre63`（`4b5a7f5`）上 `binstubs-template` FAIL，三条 needle 全缺（旧产物为 gem 自带 `require "thor/runner"` 原文）。
- 回归：`binstubs`、`binstubs-shebang`、`install-fresh`、`install-check`、`plugin-install` 双 profile 全 PASS。
- 声明差异：`binstubs-template` 依赖宿主机行为（Windows 才生成 `.cmd`），属既有 Windows-only 夹具族；模板两版暂时逐字相同，日后上游分化需各自更新。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen src/cli.cr` 0、`crystal build src/cli.cr -o bin/celerite.exe` 0、`git diff HEAD --check` 0。

## 2026-11-20（M7(3) task-64 项 1：`BUNDLE_FROZEN`/`BUNDLE_DEPLOYMENT` 无锁时的 install 文案）

- 参考 `.upstream-specs/v4.0.24/bundler/lib/bundler/cli/install.rb:29-35`：`flag = "deployment setting"` / `"frozen setting"`，抛 `ProductionError`：
  `The <flag> requires a lockfile. Please make sure you have checked <relative Gemfile.lock> into version control before deploying.`，80 列折行，写 stderr，exit 16。
- 版本差异：4.0.24 先判 `deployment` 再判 `frozen`，两者同设时 **frozen 胜**；2.7.2 用 `flag ||=`，**deployment 胜**。
- oracle（两侧各三格，均 exit 16、stdout 空、stderr 逐字节相同）：

| 环境 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `BUNDLE_FROZEN=true` | `The frozen setting requires a lockfile. Please make sure you have checked\nyour Gemfile.lock into version control before deploying.` | 同 4.0.24 |
| `BUNDLE_DEPLOYMENT=true` | `The deployment setting requires a lockfile. …`（首行折在 `checked` 后） | 同 |
| 两者同设 | frozen 文案 | deployment 文案 |
| `BUNDLE_FROZEN=true bundle check` | 仍是 `Frozen mode is set, but there's no lockfile` | 同 |

- 实现：仅改 install 路径（`src/celerite/cli/commands_install.cr`），按 profile 选取 flag，并用新增的 `self.relative_lockfile_path(definition)` 复刻 `shared_helpers.rb:223-232`（`Path#relative_to` 仅跨盘抛 `ArgumentError`，此时回退绝对路径）。`check`（`src/celerite/cli/commands.cr:1410`）与 `update`（`src/celerite/cli/commands_surface.cr:94`）的旧文案**刻意保留**——实测参考在这两条路径上仍是旧行为。
- 测试：夹具 `install-frozen-env-nolockfile`、`install-deployment-env-nolockfile`（`env` 文件传 `BUNDLE_*`，`stderr-contains` 断两行原话），双 profile PASS；`spec/m7_frozen_nolockfile_message_spec.cr` 5 例（含两种写法、两版同设取舍、check 回归）。
- 反假绿：`C:/temp/celerite-pre64a`（`38e42b6`）上两夹具均 FAIL（旧文案 `Frozen mode is set, but there's no lockfile`）。
- 已声明差异：`BUNDLE_FROZEN=true update --all` 且无锁时，参考 exit 16 打平台缺项与 `bundle lock --add-platform x64-mingw-ucrt` 提示，我方仍打旧 frozen 文案；本条未修，留作后续条目。

## 2026-11-20（M7(3) task-64 项 2：`lock --add-platform` 保留原生 spec 行与 CHECKSUMS）

- 复现口径：`Gemfile` = `source "file:///…/fixtures/gem-index-platform"` + `gem "platdemo"`（`platdemo` 同时有 `1.0.0`（ruby）与 `1.0.0-x64-mingw-ucrt` 两个 gem）。
- oracle（`.tmp-scratch/task64-platform/`，两侧均隔离 `HOME`/`BUNDLE_PATH`/`BUNDLE_APP_CONFIG`）：

| 命令 | 4.0.24 | 2.7.2 |
| --- | --- | --- |
| `lock` | 一行 `platdemo (1.0.0-x64-mingw-ucrt)`；PLATFORMS 仅 `x64-mingw-ucrt`；CHECKSUMS 该行无 digest | 同行同 PLATFORMS；无 CHECKSUMS |
| `lock --add-platform x64-mingw32` | **两行** `platdemo (1.0.0)` + `platdemo (1.0.0-x64-mingw-ucrt)`；PLATFORMS 两平台；CHECKSUMS 两行均无 digest | 同行；无 CHECKSUMS |
| 其后 `install` | `Bundle complete! 1 Gemfile dependency, 1 gem now installed.`，只 `Fetching/Installing platdemo 1.0.0 (x64-mingw-ucrt)`；stderr `[DEPRECATED] Found x64-mingw32 in lockfile, which is deprecated and will be removed in the future.`；锁中 mingw 行获 `sha256=f02daf29…`，ruby 行仍无 digest | `2 gems now installed`（计入 bundler）；stderr `… which is deprecated. Removing it. Support for x64-mingw32 will be removed in Bundler 4.0.`；重写锁时删去 `x64-mingw32`，两行 spec 保留 |
| `--add-platform ruby` | 同上两行（ruby 行来自该路径） | 同上 |

- 机制：参考解析只产出一个可安装变体，多出的 ruby 行由 `resolver.rb:88-89` 的 `SpecSet.new(resolved_specs).specs_with_additional_variants_from(@base.locked_specs)` 从**已锁 spec 集**补入（`spec_set.rb:184-185`、`:301-309`）；补入行不进安装列表，`cli/install.rb:89-96` 的计数取 `definition.specs`，因此不计入 “gems now installed”。
- 实现：`src/celerite/resolution.cr` 新增 `best_match_variants`（逐平台取最匹配变体、按 name/version/platform 去重）与 `lock_extra_specs`；`decisions_to_specs` 与 `materialize_locked` 都填充它，`generated_lockfile` 的 GEM 段与 CHECKSUMS 段各并入一行，安装工作列表与汇总计数只取 `@resolved_specs`，故不受影响。`x64-mingw32` 与 `x64-mingw-ucrt` 互不 `match?`（`platform.cr:150-167` 要求 os 相等），这正是参考回退到 ruby 行的原因。
- 弃用告警属**锁解析副作用**（`lockfile_parser.rb:157-159` / `:144-155`），由 `src/celerite/definition.cr` 的 `normalize_legacy_mingw_platform` 复刻：4.x 每次解析都告警；2.7.x 非 frozen 时改写平台并告警，frozen 不动。告警经 `Definition.default_warning_sink`（`CLI.run` 绑定到命令 stderr）输出。
- 测试：新夹具 `lock-add-platform-keeps-native-spec`（`file-equals-4.0.24`/`file-equals-2.7.2` 断整份锁）与 `install-deprecated-platform-warning`（`stderr-contains` 断告警；stderr 为 contains-only，属既有 N10 归一化）；`spec/m7_add_platform_spec.cr` 4 例（两行锁、只装一个且计数不变、2.7.2 复用路径与平台删减、二次 lock 不重复）。
- 反假绿：`C:/temp/celerite-pre64b`（`89492db`）上两夹具均 FAIL——锁缺 `platdemo (1.0.0)` 行，`install` 多出 `Fetching/Installing platdemo 1.0.0` 且计数为 2，stderr 无 `[DEPRECATED]` needle。
- 回归：`lock-*`、`install-*`、`platform-*`、`checksums-*` 共 66 例，双 profile 各 65 passed / 1 failed；唯一失败 `lock-missing-dependency-edges (install)` 为既有差异（Ruby 4.0.6 将 `net-protocol` 视为 default gem，任务 57 已记录），与本节无关。
- 已声明差异：`--tls-version` 等与本节无关；本节未覆盖 `lock --add-platform` 与 `--normalize-platforms` 组合、`Gemfile.lock` 由 2.7.2 改写后再交 4.0.24 读取的跨版本序列。
- 门禁：`crystal tool format --check src spec` 0、`crystal build --no-codegen src/cli.cr` 0、`crystal build src/cli.cr -o bin/celerite.exe` 0、`git diff HEAD --check` 0。
## 2026-11-20（M7(2) task-65：内建 gem 判据改为「来源」而非「同名同版本」）

此前 `fixtures/differential/lock-missing-dependency-edges` 长期记为「环境差异」，实为产品缺陷，已修。

| 场景（4.0.24 与 2.7.2 同） | 参考行为 | 修复前 celerite |
| --- | --- | --- |
| 索引 `fixtures/gem-index-locked-deps` 含 `net-protocol (0.2.2)`，锁钉 `net-protocol (0.2.2)` + `net-smtp (0.5.0)`，`install` | exit 0；`Fetching net-protocol 0.2.2` / `Installing net-protocol 0.2.2`；stderr 空 | exit 0；**不下载不安装**，stderr 打 `net-protocol-0.2.2 is built in to Ruby, and can't be cached because your Gemfile doesn't have any sources that contain it.` |
| 同上，但索引内**没有** `net-protocol`（探针变体） | exit 0；`Local specification for net-protocol-0.2.2 has different dependencies than the remote gem, ignoring it`（stderr）；`2 gems now installed`；两次 `Resolving dependencies...` | exit 0；stderr 空；`1 gem now installed`；一次 `Resolving dependencies...`（**仍不一致，见已声明差异**） |

机制：参考只在 `spec.default_gem?` 为真时走内建路径（`source/rubygems.rb:181`、`:206` 的 `spec.default_gem? && !cached_built_in_gem(...)`），而 `default_gem?` 只对「解释器自带的默认 gem 规格」成立；从锁或索引物化出来的规格不是默认 gem，因此即便与默认 gem 同名同版本也照样下载安装。celerite 原先在安装循环里向 bridge 询问「解释器是否自带该 名+版本」（`src/celerite/cli/commands_install.cr:455-459`），命中即跳过安装并告警——`net-protocol 0.2.2` 恰好是 Ruby 4.0.6 的默认 gem，于是误判。

修复：`ResolvedSpec` 新增 `default_gem : Bool`（`src/celerite/resolution.cr:196-224`），只在 `decisions_to_specs` 由 `IndexSpec#default_gem_path` 非空时置真（即走 `index_specs_for` 的默认 gem 兜底，`src/celerite/resolution.cr:800-808`、`1534`），`refresh_locked_dependencies` 原样透传（`:1330-1336`）；安装循环改为按 `spec.default_gem` 过滤（`src/celerite/cli/commands_install.cr:450-466`），不再向 bridge 查询。

验证：`lock-missing-dependency-edges` 双 profile PASS（4.0.24 / 2.7.2 各 1 passed）；task-41 回归 `lock-default-gem`、`info-default-gem`、`install-locked-ruby-incompatible` 双 profile PASS；`spec/m7_default_gem_spec.cr` 4 例 + 新增 `spec/m7_default_gem_origin_spec.cr` 2 例 + `m7_install_ruby_compat_spec.cr` + `m7_add_platform_spec.cr` 共 13 例 0 失败；成组回归 110 例（`lock-*`/`install-*`/`checksums-*`/`platform-*`/`plugin-*`/`update-*`）4.0.24 107 passed / 2 failed / 1 skipped，2.7.2 107 / 2 / 1，2 例失败均为 `plugin-git-local`、`plugin-git-local2` 的 msys Low IL `git clone` 失败（`0xC0000022` 家族，与本项无关）。

反假绿：`C:/temp/celerite-pre65a`（`1789d17`）上该夹具 0 passed，差异行为 `< Fetching net-protocol 0.2.2`、`< Installing net-protocol 0.2.2`、`> net-protocol-0.2.2 is built in to Ruby…`。

已声明差异：索引内缺 `net-protocol` 的探针变体仍不一致——参考会打 `Local specification … has different dependencies than the remote gem, ignoring it` 并计 `2 gems now installed`，celerite 静默且计 `1 gem now installed`。该变体未入夹具（参考输出依赖宿主默认 gem 的依赖边，跨机器不稳定），记录待后续任务。
### 稳定性补记（2026-11-20）

`lock-missing-dependency-edges` 曾出现「跑几次绿、跑几次红」：同一二进制连跑 10 次，2 次差异为 `Installing net-protocol 0.2.2` 与 `Installing net-smtp 0.5.0` 顺序互换。定位结论：**非确定性在参考侧**——4.0.24 的并行安装在 worker 完成时打印 `Installing`，顺序随线程调度；同一命令连跑 10 次参考自身出现 3 次反序，而 celerite 每次输出一致。

处置：夹具新增 `env` 文件 `BUNDLE_JOBS=1`。参考在 `jobs = 1` 时逐 gem 串行安装，按 `Fetching X` / `Installing X` 成对打印（10/10 稳定）；celerite 相应地在 `config["jobs"] == 1` 时按同一顺序输出（`src/celerite/cli/commands_install.cr` 的缓冲刷新分支，2026-11-20 补）。未放宽断言：stdout 仍逐字比较，`file-contains` 未改。

stability: 10/10 runs（4.0.24 连跑 10 次、2.7.2 连跑 10 次，全 PASS；命令 `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential lock-missing-dependency-edges`，2.7.2 追加 `BUNDLER_REF_VERSION=2.7.2`）。

**该夹具对宿主 gem 目录敏感**：本机 `C:\Ruby40-x64\bin\ruby.exe` 上 `Gem::Specification.find_all_by_name` 同时包含 `net-protocol 0.2.2`（`default=true` 与 `default=false` 两条、同路径）以及 `net-smtp 0.5.0/0.5.1/0.5.2`、`net-protocol 0.3.0/0.4.0`（系统目录与 `~/.local/share/gem` 均有）。故安装期判据只能取 resolution 的规格集（`source_type`、`default_gem`），一旦改用宿主 `Gem::Specification`/`Gem.path` 查询，结论随机器变化、不能作差分依据。默认 gem 兜底也只在远端索引无候选时触发（`src/celerite/resolution.cr:811-819`），不与索引命中混用。


## 2026-11-20（M7(2) task-65：无锁时 frozen/deployment 的 `update --all`）

| 场景（4.0.24 与 2.7.2 同） | 参考行为 | 修复前 celerite |
| --- | --- | --- |
| `BUNDLE_FROZEN=true update --all`，无 `Gemfile.lock` | exit 16；stderr 三行 `Your bundle only supports platforms [] but your local platform is` / `x64-mingw-ucrt. Add the current platform to the lockfile with` / `` `bundle lock --add-platform x64-mingw-ucrt` and try again. `` | exit 16；stderr `Frozen mode is set, but there's no lockfile` |
| `BUNDLE_DEPLOYMENT=true update --all`，无锁 | 同上 | 同上 |
| 两个变量同时 | 同上（无先后差异，走同一平台校验） | 同上 |
| `BUNDLE_FROZEN=true update json_pure`，无锁 | exit 22；`This Bundle hasn't been installed yet. Run `` `bundle install` `` to update and install the bundled gems.` | exit 16；`Frozen mode is set, but there's no lockfile` |

机制：参考 `Definition#validate_platforms!`（`definition.rb:471-473`）在无锁时平台列表为空，`current_platform_locked?` 为假，于是抛 add-platform 提示（`ProductionError`，status 16）；scoped update 更早停在 `cli/update.rb:26-38` 的「尚未安装」检查（status 22），所以两类必须分开。

修复：`src/celerite/cli/commands_surface.cr:90-104` 只在 `full_update && config.frozen? && !definition.lockfile_exists?` 时抛平台提示，scoped 路径不再被 frozen 文案抢占，仍走原有的 status 22 分支。

验证：夹具 `update-frozen-env-nolockfile`（`env` 传 `BUNDLE_FROZEN=true`，`file-absent Gemfile.lock`，`stderr-contains` 两行）双 profile PASS（exit 16）；scoped 变体手工对照参考 exit 22 一致。反假绿 `C:/temp/celerite-pre65a`：`update-frozen-env-nolockfile` 0 passed，两条 needle 均缺（`Your bundle only supports platforms [] but your local platform is`、`bundle lock --add-platform`）。

已声明差异：`update --all` 与 `update <gem>` 之外的其他 frozen 组合（如 `update --ruby`、`update --group`）本轮未单独取 oracle。
## 2026-11-20（M7(2) task-66：上游 lockfile 套件第三次重采集与候选去向）

命令原文（MSYS bash，`bin/celerite.exe` 于 HEAD `502f4b5` 构建；`TMPDIR=/c/temp`、`CELERITE_SKIP_TEST_DEPS=1`、PATH 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;`）：

```
bash script/upstream-specs
```

墙上时间 **430 s**（START `2026-11-20T12:59:03Z`，rspec duration 423.27 s，seed 39077）。`summary` 原始字段：`{"duration" => 423.2732939, "example_count" => 64, "failure_count" => 53, "pending_count" => 0, "errors_outside_of_examples_count" => 0}`；real-drive 57 次 celerite 调用；产物 `.upstream-specs/upstream-lockfile-v4.0.24-20261120T125904Z.md`。

| 桶 | 数量 | 判定口径 |
|---|---|---|
| `env:artifice-unreachable` | 38 | 上游进程内 artifice / `https://gem.repo2` 不可达 |
| `env:low-il-shm` | 9 | Low-IL 下 msys `sh`/`git` 子进程 `NtCreateDirectoryObject` → `0xC0000022` |
| `fixture:fetch-failed` | 6 | 同上类宿主不可达，失败点在 Fetching |
| `fixture:missing-gem-files` | 0 | task-23 修复后保持 0 |
| `product:candidates` | **0** | 无剩余产品候选 |

三个候选逐条：

1. ① `fills empty CHECKSUMS entries when not frozen, even if every gem is already installed` — **仍失败（env:artifice-unreachable），与 task-32 同桶**。`Invoking \`…/bin/celerite install\` failed with output:` / `Could not reach host gem.repo2. Check your network connection and try again.`
2. ② `is conservative with dependencies of git gems` — **仍失败，product → env:low-il-shm**。`git command failed: git clone --mirror …/libs/ckeditor_remote-1.0 …` / `0 [main] sh (30280) … NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-…): 0xC0000022`。断言 diff 未到达 ⇒ 产品差异本机不可判定，但已不属产品桶。
3. ③ `keeps existing platforms in the lockfile` — **仍失败，product → env:artifice-unreachable**。`Could not reach host gem.repo2. …`。task-32 记录的旧报错 `Your bundle only supports platforms ["java"] …` 本次未出现 ⇒ 平台门禁已被 task-33/task-64 越过；端到端仍因宿主不可达未验证。

与 task-32 的差：失败 54 → 53，新增通过 `serializes pinned path sources to the lockfile even when packaging`（task-44a/44b 路径源序列化）；`low-il` 8 → 9（吸收 ②），`artifice` 38 不变，product 2 → 0。

本机不可转绿的桶：`env:artifice-unreachable`、`env:low-il-shm`、`fixture:fetch-failed`。三者均由宿主条件决定（进程内 artifice / `gem.repo2` 不可路由、当前完整性级别下的 msys 子进程拒绝），不是产品行为；换机或在非 Low-IL 环境复采才可能变化。

未验证：② 的真实产品差异（断言未到达）；③ 的平台保留在可达宿主下的端到端结果；① 的 sha256 回填上游例（语义已由 task-25/26 差分覆盖）。

## 2026-11-21（M7 task-67：`check` 遇 Gemfile 新增未锁定依赖时的重解析）

缺陷：Gemfile 新增一个锁里没有、也没安装的依赖（`gem "thor"`，本地索引只有 `thor-1.3.2`）后，参考侧 `bundle check` 走「依赖集变化 → 远程重解析 → 报缺失」，exit 1、不写锁；修复前 celerite 直接判「已满足」exit 0，并把 `thor` 写进锁的 `DEPENDENCIES`（`GEM specs` 仍只有 `json_pure`），锁被写成不自洽状态；其后再跑 `check --dry-run` 反而退化成 exit 1 + 两行 `Bundler can't satisfy your Gemfile's dependencies.` / `` `Install missing gems with `bundle install`. ``。

oracle（同一 `file://` 索引，先 `install` 预装并锁 `json_pure 2.6.0`；`CELERITE_REFERENCE_BUNDLER_LIB=.upstream-specs/v4.0.24/bundler/lib`、`CELERITE_PROFILE_BUNDLER_VERSION=4.0.24`；锁基线 sha1 `9335939b8ffa…`）：

| 场景 | 参考 4.0.24 | 修复前 celerite |
| --- | --- | --- |
| (a) `check`，Gemfile 追加 `gem "thor"` | exit 1；stdout `Fetching source index from <idx>/` + `Resolving dependencies...`；stderr 三行 `The following gems are missing` / ` * thor (1.3.2)` / `` `Install missing gems with `bundle install` ``；锁 sha1 不变 | exit 0；stdout `The Gemfile's dependencies are satisfied`；stderr 空；锁 `DEPENDENCIES` 新增 `thor` |
| (b) `check --dry-run`（同场景） | 与 (a) 全等，锁不变 | 与 (a) 全等（同样误写锁） |
| (c) 依赖已满足 | exit 0；stdout `The Gemfile's dependencies are satisfied`；stderr 空；锁不变 | 一致 |
| (d) `gem "json_pure", ">= 2.6"`（放宽 requirement） | exit 0 + 同句；锁 `DEPENDENCIES` 改写为 `json_pure (>= 2.6)`（sha1 `bdc3ef78…`） | exit 0 + 同句；锁不改写 ⇒ **已声明偏差**（修复未触及，与 task-67 前一致） |
| (e) 索引不可达（`source 'file:///C:/no-such-celerite-index'` + `gem "thor"`） | exit 17；stdout `Fetching source index from file:///C:/no-such-celerite-index/` + 空行；stderr 4 条 `Retrying fetcher due to error (n/4): Bundler::HTTPError Could not fetch specs from … due to underlying error <Errno::ENOENT … specs.4.8.gz>` + 末条同文不带 `Retrying`；锁不动 | exit 1；stdout 仅 Fetching 行；stderr 两行 can't-satisfy ⇒ **已声明偏差** |

机制：参考 `Definition#check!`（`definition.rb:172-182`）在 `@dependency_changes` 为真时先 `resolve_remotely!`（`:216-225`），再 `sources.local_only!` + `resolve`；`missing_specs`（`:261-264`）= `resolve.missing_specs_for(requested_dependencies)`；`cli/check.rb:19-31` 只要 `missing_specs` 非空就打印三行并 exit 1，写锁在 `:33` 的 else 分支。`dependency_changes` 由 `converge_dependencies`（`definition.rb:1051-1086`）产出：Gemfile 依赖名不在锁的 `DEPENDENCIES` 里（`@locked_deps[name].nil?`）即算变化；锁里同名 spec 的版本不满足 Gemfile 要求（`!dep.matches_spec?(locked_specs.first)`）也算——故「放宽但仍满足」不算变化（对应 (d) 只重写 `DEPENDENCIES`）。

修复：
- `src/celerite/definition.cr:179` 新增 `gemfile_dependency_changes?(deps : Array(Bridge::EvaluatedDependency)) : Bool`，按上述两个判据比较 Gemfile 依赖集与锁；注释锚定 `definition.rb:1051-1086`、`cli/check.rb:33`。
- `src/celerite/cli/commands.cr:1400` 在既有 bridge 探测内保存 `gemfile_evaluation`（`:1403` `evaluate_gemfile`）；`:1456-1463` 新增 `re_resolved_for_dependency_change`，与 `resolved_from_gemfile`（无锁）共用同一条 `Resolution#resolve!` 路径（progress 走 stdout，故打印 `Fetching source index from …` 与 `Resolving dependencies...`）；`:1540` 缺失判定沿用锁定 spec 与已安装 spec 目录比对；`:1561` 需要改写时仍走 `Resolution#lockfile_rewrite_text`。
- 未改 `install`/`update` 语义；`--dry-run` 与 frozen 分支不触发重解析写锁。

验证：
- 新夹具 `fixtures/differential/check-gemfile-new-dependency`（`bundle-preset` 预装 `json_pure-2.6.0`、锁已锁、Gemfile 追加 `gem "thor"`、`command = check`；`file-equals-4.0.24`/`file-equals-2.7.2` 断言锁未新增 `thor`）：4.0.24 **PASS（exit=1）**、2.7.2 **PASS（exit=1）**。
- 回归双 profile 各 10 条全 PASS：`check-rewrites-lock`(0)、`check-dry-run-keeps-lock`(0)、`check-missing`(1)、`check-unresolved`(1)、`check-triplet-missing-index`(1)、`check-installed-spec-without-gemdir`(0)、`check-gemdir-without-spec`(7)、`check-frozen-path-gemspec-bump`(16)、`lock-noop`(0)、`install-check`(0)。
- spec `spec/m7_check_missing_dependency_spec.cr` 3 examples / 0 failures：缺失 → exit 1 且锁逐字节不变、无 `thor`；`--dry-run` 同三行且不写；满足 → exit 0、不打印 `Resolving dependencies...`、锁含 `json_pure (2.6.0)` 且无 `thor`。
- 反假绿（`C:/temp/celerite-pre67`，`502f4b5` 旧二进制）：新夹具双 profile `0 passed, 2 failed`，失败行 `exit code: reference=1 celerite=0`、`> The Gemfile's dependencies are satisfied`、`1,3d0 < The following gems are missing / <  * thor (1.3.2) / < Install missing gems with `bundle install``、`file-equals differs (Gemfile.lock, cel): 10a11 >   thor`。
- 门禁 0/0/0/0（`crystal tool format --check src spec`、`crystal build --no-codegen src/cli.cr`、`crystal build src/cli.cr -o bin/celerite.exe`、`git diff HEAD --check`）。

已声明差异：(d) 放宽 requirement 时参考重写 `DEPENDENCIES` 而 celerite 不改写；(e) 索引不可达时参考 exit 17 + 4 条 fetcher 重试文案，celerite 仍按解析失败映射为 exit 1 + 两行 can't-satisfy。未验证：全量 spec 与全量差分未复跑（本轮只跑与 check/lock/install 相关的子集）。
## 2026-11-21（M7 task-68：`remove` 族的四条失败面）

oracle 用同一份 `file://` 索引（`fixtures/gem-index`，预装并锁 `json_pure 2.6.0`，锁基线 sha1 `9335939b8ffa…`），4.0.24 走 `.upstream-specs/v4.0.24/bundler/lib`，2.7.2 走本机 `bundler-2.7.2`；每例都比 stdout、stderr、exit 与 Gemfile/锁的最终字节。

| 场景 | 参考 4.0.24 | 修复前 celerite |
| --- | --- | --- |
| `remove --install json_pure` | exit 15；stderr 单行 ``The `--install` flag has been removed. `bundle install` is triggered by default.``；Gemfile 与锁不动 | exit 0；真删 gem；stdout 打 `Removing gems from …` 与 `json_pure (= 2.6.0) was removed.`；stderr 多出 `Unknown switches "--install"`（`--install` 被登记为合法开关后又原样转给内层 `install`） |
| `remove nosuchgem` | exit 4（`GemfileError`）；stdout 先打 `Removing gems from <abs>/Gemfile`；stderr 按 80 列折行三行 `` `<name>` is not specified in`` / `<abs>/Gemfile` / `so it could not be removed.`；Gemfile 与锁不动 | exit 1；stdout 空；stderr 单行 `No gems were removed from the Gemfile` |
| `remove`（无参） | exit 15；stderr `Please specify gems to remove.` | exit 1；stderr `` `remove` requires at least 1 argument`` |
| `remove thor`（成功路径） | `Removing gems from …` 在**改文件前**打印（`injector.rb:138`）；随后 `thor was removed.` | 该行在写文件之后打印，故失败路径完全不打印 |
| `remove thor`，thor 在 `group :dev do … end` 内 | 整块（含 `end`）一并删除，Gemfile 只剩 `source` 与 `json_pure` | 保留空 `group` 块（`group :dev do` + `end` 残留） |

`remove --path` 两侧同为 exit 15 `Unknown switches "--path"`；`remove --install json_pure --bogus` 两侧同为 exit 15 `Unknown switches "--bogus"`（Thor 的未知开关检查先于命令体的 `--install` 判断）。2.7.2 侧 `remove --install` 不 raise 而是打 `[DEPRECATED] The `--install` flag has been deprecated. `bundle install` is triggered by default.` 后继续执行（`cli.rb:191-200` 的 `major_deprecation`），故 2.7.2 下 exit 0 且真的删除。

机制（参考）：`cli.rb:240-253` 的 `remove` 在命令体开头 `raise InvalidOption` 拒绝 `--install`；`cli/remove.rb:10-15` 空参 `raise InvalidOption`，随后 `Injector.remove` + `Installer.install`；`injector.rb:63-76` 的 `remove` 先 `remove_deps` 再逐条 `confirm "#{pretty_dependency(dep)} was removed."`；`:135-159` 的 `remove_deps` 顺序是「读原文 → 打印 `Removing gems from` → eval Gemfile → 删依赖 → 写回（`:152`）→ `cross_check_for_errors`」，`:165-181` 在某个名字未被声明时 `raise GemfileError`（`:172`），且 `remove_gems_from_gemfile`（`:185-213`）末尾对 `group`/`source`/`env`/`install_if` 四种块调 `remove_nested_blocks`（`:210`），把被删空的块连同 `end` 一起去掉；写入走 `SharedHelpers.write_to_gemfile`（`shared_helpers.rb:215-217`）的 `file.puts`，等价「内容已含结尾换行则不重复追加」，且文本模式把 LF 落成 CRLF。

修复：
- `src/celerite/errors.cr:68-75` 给 `GemfileError` 加 `wrap? = true`（参考所有 `BundlerError` 走 `ui.error msg, wrap: true`，故折行由 `CLI.terminal_width` 决定、默认 80）；`:98-113` 给 `DSLError` 显式 `wrap? = false`，避免继承后被误折行。
- `src/celerite/cli/commands_surface.cr:730-853` 重写 `Commands.remove`：`:733` 保留 Thor 的未知开关检查在最前；`:743-749` 再判 `--install`（4.x `raise InvalidOptionError` status 15 / 2.x 打 `[DEPRECATED]` 后继续），`:751` 构造不把 `--install` 转给内层 `install` 的 `install_rest`；`:753-757` 空参 `raise InvalidOptionError.new("Please specify gems to remove.")`；`:766` 在改文件前打印 `Removing gems from`；`:772-780` 逐个名字查声明（`within_gemfile_comment?` 排除注释行）否则 `raise GemfileError.new("`name` is not specified in … so it could not be removed.")`；`:785-801` 删行并跟随 `,` 续行；`:805-807` 对四种块调用 `remove_nested_blocks`；`:817-820` 用参考的 `join.chomp` + `puts` 语义落盘（`cleaned` 缺结尾换行才补，`\n` 统一转平台 eol）；`:824-836` 按 CLI 名字顺序打 `… was removed.`；`:838-842` 无 `gem` 行时 stderr `The Gemfile specifies no dependencies`；`:850-851` 收尾 `install(null, stderr, install_rest, summary: false, cli_arguments: false)`。新增私有 helper：`remove_pattern`（`:858-865`，`injector.rb:186` 的两条正则）、`within_gemfile_comment?`（`:869-873`）、`remove_nested_blocks`（`:879-896`，`injector.rb:224-243` 的固定点迭代）。
- 未改 `add`/`update` 的开关表（`BARE_SWITCH_FLAGS` 与 `add` 共用，`--install` 只在 `REMOVE_SWITCH_FLAGS` 移除后按命令体语义单独判定）。

验证：
- 三个新夹具，双 profile 全 PASS：`remove-install-flag-removed`（4.0.24 exit=15 且 `file-equals-4.0.24` 断言 Gemfile 逐字节未变；2.7.2 exit=0 且 `file-contains` 断言 `source` 行仍在）、`remove-missing-gem`（exit=4，三行折行 stderr、`Removing gems from` 先行、Gemfile 未变）、`remove-no-arguments`（exit=15，Gemfile 未变）。4.0.24 **3 passed / 0 failed**，2.7.2 **3 passed / 0 failed**。
- spec `spec/m7_remove_failure_modes_spec.cr` 5 examples / 0 failures：`--install` 拒绝、`--install … --bogus` 先报未知开关、无参、缺失 gem（含折行 stderr 与 `Removing gems from` 顺序）、group 内最后一个 gem 整块删除。Windows 下 Gemfile 重写为 CRLF（与参考的文本模式写入一致），group 用例经 `remove_gemfile_on_disk` 归一后比较，其余四例按逐字节断言（未触碰文件）。
- 回归（4.0.24）：remove/add 面 21 passed（5 条失败见下）；update/lock/install 面 19 passed / 0 failed（含 `lock-noop`、`install-check`、`install-fresh`、`check-gemfile-new-dependency`）。
- 2.7.2：全量拼接 40 passed / 5 failed / 1 skipped，失败与 4.0.24 同一族。
- 装具限制导致的 5 条失败（`add-remove`、`add-git`、`add-ref`、`add-group`、`add-optimistic`、`add-version`）经定位为**宿主完整性级别**问题而非产品差异：二进制位于工作区内（Low IL）时 msys `sh`/`make`/`git` 子进程报 `fatal error - NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-…): 0xC0000022`；同一二进制放到 `C:/temp` 路径（Medium IL）运行则全绿。逐一复核：同一份新代码从 `C:/temp` 运行，4.0.24 **6 passed / 0 failed**、2.7.2 **5 passed / 0 failed / 1 skipped**（2.7.2 无 `add-group` 夹具）。
- 反假绿（`C:/temp/celerite-pre68`，`d0b9b7a` 旧二进制）：三夹具 4.0.24 `0 passed, 3 failed`，失败行为 `exit code: reference=15 celerite=0`、`< The `--install` flag has been removed. …` vs `> The Gemfile specifies no dependencies` / `> Unknown switches "--install"`、`file-equals differs (Gemfile, cel): 1,3c1,2`；`exit code: reference=4 celerite=1` 与 `< `nosuchgem` is not specified in …` vs `> No gems were removed from the Gemfile`；`exit code: reference=15 celerite=1` 与 `< Please specify gems to remove.` vs `> `remove` requires at least 1 argument`。
- 门禁 0/0/0/0。

已声明差异：`file-equals` 无法表达 CRLF 期望（装具用 `sed` 生成期望文件时吞掉 CR），故 2.7.2 侧的「Gemfile 未被删」改用 `file-contains` 断言。未验证：`cross_check_for_errors`（一个名字删到多个 gemspec 时的 `InvalidOption` 回滚路径，`injector.rb:249-272`）未建夹具；`remove` 指向多 gemspec / 多 Gemfile 的项目未覆盖；同一命令重复指定同名 gem 的参考行为未单独取 oracle。

## 2026-11-21（M7 task-69A：`outdated --parseable` 的 `, requested` 段）

**结论**：`Bundler::CLI::Outdated#print_gem`（`.upstream-specs/v4.0.24/bundler/lib/bundler/cli/outdated.rb:210-226`）只在依赖是「特定版本」时才追加 `, requested <req>`：`if dependency&.specific?` 为真才拼 `, requested #{dependency.requirement}`。表格模式不受影响：`gem_column_for`（`:248-263`）的 Requested 列取 `dependency.to_s`，非特定依赖显示 `>= 0`。

**Oracle（4.0.24 + 2.7.2，`fixtures/gem-index`）**

| 形状 | 参考 stdout（parseable） | 我方（修前） |
| --- | --- | --- |
| Gemfile `gem "json_pure"`，锁钉 2.6.0 | `json_pure (newest 2.8.1, installed 2.6.0, released 2024-11-05)` | 末尾多 `, requested >= 0` |
| Gemfile `gem "json_pure", "2.6.0"` | `json_pure (newest 2.8.1, installed 2.6.0, requested = 2.6.0, released 2024-11-05)` | 一致（本就对齐） |
| 表格模式（两者） | `json_pure  2.6.0  2.8.1  >= 0  default  2024-11-05` | 一致 |

**实现**：`src/celerite/cli/commands_surface.cr` 在行循环里按锁文件 `DEPENDENCIES` 的 requirement 记 `requested_specific[name]`（`Gem::Requirement#specific?`，语义同 `rubygems/requirement.rb:253-257`：约束多于一条，或单条约束的操作符不是 `>` / `>=`），parseable 分支仅在该标志为真时拼 `, requested …`。表格单元格逻辑不变。

**夹具**：`fixtures/differential/outdated-parseable-nonspecific/`（非特定 `Gemfile` + 预置 `Gemfile.lock` 钉 2.6.0，`command` = `install --quiet` 后 `outdated --parseable`），双 profile exit 1 逐字一致；既有 `outdated-parseable` / `outdated-parseable-current` / `outdated-strict` / `outdated-list` / `outdated-local` 全 PASS。

**声明**：`original_cli_command` / `default_cli_command` 弃用提示未纳入断言；`--parseable` 与 `--groups` 的组合未单独取值。

## 2026-11-21（M7 task-69B：`install --local` 的 source 描述与缓存后缀）

**结论**：`install --local` 在参考实现里从不启用远程源——`Definition#setup_domain!`（`.upstream-specs/v4.0.24/bundler/lib/bundler/definition.rb:190-203`）先 `sources.cached!`，再按 `options[:local]` 走 `sources.local!`；`Source::Rubygems#cached!`（`source/rubygems.rb:69-76`）在 `cache_path` 目录不存在时直接返回，因此 `to_s`（`:122-136`）只有在 `@allow_cached && @allow_local` 同时成立时才说 `cached gems or installed locally`，否则说 `locally installed gems`。找不到时的文案由 `Resolver#raise_not_found!`（`resolver.rb:334-361`）决定：`Bundler.app_cache.exist?` 时追加 ` or in gems cached in <app_cache_path>`（`settings.rb:304-306`，默认 `vendor/cache`）。

**Oracle（4.0.24 + 2.7.2，`fixtures/gem-index`，BUNDLE_PATH 隔离、宿主无该 gem）**

| 形状 | 参考 stderr | 我方（修前） |
| --- | --- | --- |
| `install --local`，存在 `vendor/cache` 目录，gem 未安装 | `Could not find gem 'json_pure (= 2.6.0)' in cached gems or installed locally or` / `in gems cached in vendor/cache.`（exit 7，80 列折行） | 解析成功并安装（exit 0） |
| `install --local`，无 `vendor/cache` 目录 | `Could not find gem 'json_pure (= 2.6.0)' in locally installed gems.`（exit 7） | 同上 |
| `install --local`，`vendor/cache` 内有该 gem | 从缓存安装，逐字一致 | 一致（`install-local-vendor-cache` 既有夹具） |

**实现**：
- `src/celerite/resolution.cr` 新增 `app_cache_present?` / `app_cache_label`（`BUNDLE_APP_CONFIG` 无关，路径按 `definition.config["cache_path"]` 或默认 `vendor/cache` 相对 Gemfile 目录展开），`make_source` 在 `@local_only` 下据此选择 `cached gems or installed locally` 或 `locally installed gems`；并把 `" or in gems cached in <label>"` 作为 `cache_note` 传给解析器。
- `src/celerite/resolver/source.cr` `ResolutionSource` 新增 `@cache_note` 参数，三条 not-found 文案在其后、句号之前拼接，与参考的 `"#{not_found_message} in #{source}#{cache_message}."` 同形。
- `index_specs_for` 中 `@local_only` 直接返回本地候选的注释改为「参考在 `--local` 下不启用远程源」，删掉原先与 oracle 相反的 file:// 说法。

**夹具**：`fixtures/differential/install-local-index-unreachable/`（`source "file:///@INDEX_DIR@"` + `gem "json_pure", "2.6.0"` + `extra/vendor/cache/.keep`，`command` = `install --local`，`stderr-contains` 钉 `in cached gems or installed locally`），双 profile exit 7 PASS；`install-local` / `install-local-vendor-cache` / `outdated-local` 回归 PASS。

**声明**：`--local` 与 `--prefer-local` 组合、`cache_path` 自定义为绝对路径时的文案未单独取值；`Gem::Specification.stubs` 与桥接侧 `installed_specs` 的差异仍靠 `GEM_HOME` 过滤（宿主装有同名 gem 时以 spec 的 `GEM_HOME` 隔离为准）。

## 2026-11-21（M7 task-70：`pristine` 缺缓存、`info`/`show`/`list` 的多余位置参数）

三条同族输出面分歧，oracle 用 `.tmp-scratch/task70/oracle.sh` 在双 profile 上同时取参考与实现两测结果（`file://` 索引用 `cygpath -m` 形式）。

| 场景 | 参考（4.0.24 / 2.7.2） | 修前实现 | 修后实现 |
| --- | --- | --- | --- |
| `pristine`，缓存包已删 | exit 0；stdout 空；stderr `Failed to pristine json_pure (2.6.0). Cached gem C:/…/cache/json_pure-2.6.0.gem does not exist.` | exit 0；stdout `Installing json_pure 2.6.0`；stderr 同上但路径为 `C:\…` | exit 0；stdout 空；stderr 与参考逐字相同（正斜杠） |
| `info json_pure extra` | exit 15；`ERROR: "bundle info" was called with arguments ["json_pure", "extra"]` + `Usage: "bundle info GEM [OPTIONS]"` | exit 0；打印该 gem 的元信息块 | exit 15；两行与参考逐字相同 |
| `show json_pure extra` | exit 15；`ERROR: "bundle show" …` + `Usage: "bundle show GEM [OPTIONS]"` | exit 0；打印 gem 路径 | exit 15；两行与参考逐字相同 |
| `list extra` | exit 15；`ERROR: "bundle list" was called with arguments ["extra"]` + `Usage: "bundle list"` | exit 15；但 usage 为 `Usage: "bundle list [OPTIONS]"` | usage 改为无后缀，与参考逐字相同 |

### N1 `pristine` 缺缓存包

- 参考 `cli/pristine.rb:26-30`：`unless File.exist?(cached_gem)` → `ui.error("Failed to pristine #{gem_label}. Cached gem #{cached_gem_path} does not exist.")` → `next`；路径来自 `Bundler.bundle_path.join("cache", spec.full_name + ".gem")`，打印时为正斜杠。
- 实现：`src/celerite/cli/commands_surface.cr:2674-2684` 的 `unless File.file?(gem_file)` 分支补 `next`（不再落到 `Installing` / `installer.reinstall`），消息里的路径改为 `gem_file.gsub('\\', "/")`。
- 夹具 `pristine-missing-cache`：`install --quiet` + `pristine`，`bundle-preset` 只预置 `gems/` 与 `specifications/` 而不预置 `cache/`，`stderr-contains` 钉 `does not exist`；stdout 走整段比较，因此多出的 `Installing` 行必然使夹具失败。

### N2 `info`/`show` 的多余位置参数

- 参考 `cli.rb` 的 `desc "info GEM [OPTIONS]"` / `desc "show GEM [OPTIONS]"`：Thor 在 `run` 之前按参数表拒绝第二个位置参数（`Thor::UnknownArgumentError` → exit 15），横幅用命令自己的 usage 串。
- 实现：`src/celerite/cli/commands.cr:661-674` 的 `NO_ARG_USAGE` 新增 `"info" => "GEM [OPTIONS]"`、`"show" => "GEM [OPTIONS]"`，并在 `show_info` 于 `verbose_listing` 之前调用既有的 `reject_positional_arguments(..., max_positionals: 1)`；文案生成与 `clean`/`platform`/`env` 走同一套。
- 夹具 `info-extra-argument`、`show-extra-argument`：exit=15 + `stderr-contains` 两行（ERROR 与 usage）。

### N3 `list` 的 usage 串

- 参考 `cli.rb:364`：`bundle list` 无语义位置参数，拒绝多余参数时打印 `Usage: "bundle list"`（无 `[OPTIONS]`）。
- 实现：`src/celerite/cli/commands.cr:669` 的 `NO_ARG_USAGE["list"]` 由 `"[OPTIONS]"` 改为 `""`；其它命令未动。
- 夹具 `list-extra-argument`：exit=15 + `stderr-contains` 两行（含 `Usage: "bundle list"`，并以 `should_not contain("[OPTIONS]")` 在 spec 侧锁定）。

### 证据

- 差分：四个新夹具 4.0.24 **4 passed 0 failed**、2.7.2 **4 passed 0 failed**；`pristine|info|show|list` 家族 32 个夹具 4.0.24 **31 passed 0 failed 1 skipped**（`show-outdated-verbose-272` documented deferral）、2.7.2 **32 passed 0 failed**。
- spec `spec/m7_extra_arguments_spec.cr` 4 例 0 失败。
- 反假绿：`C:/temp/celerite-pre70` @ `5e7239d` → **0 passed / 4 failed**，失败行为 `> Installing json_pure 2.6.0`（pristine）、`stderr-contains differs: needle=was called with arguments ["json_pure", "extra"]`（info/show）、`stderr-contains differs: needle=Usage: "bundle list"`（list）。

### 已声明差异

- `pristine <name>`（指定 gem 名）路径未单独取 oracle，只有全量 `pristine` 有夹具。
- `info`/`show` 的多余参数与 `--version`/`--paths` 组合未逐一取 oracle（当前行为：未知开关先报，再报参数个数）。
- 参考在 `pristine` 缺缓存时仍会处理后续 gem；夹具只覆盖单 gem 项目，多 gem 时逐条 `next` 的行为未 fixture 化。

## 2026-11-21（M7 task-71：`info`/`show` 的 `select_spec`——默认 gem 回退与正则多选菜单）

### oracle（HEAD ab689f5，双 profile，隔离 HOME/BUNDLE_*，项目 `source "file://<gem-index>"` + `gem "json_pure"`，先 `install --quiet`，stdin `< /dev/null`）

| 命令 | 参考 | 我方（修前） |
| --- | --- | --- |
| `info bundler` | exit 0；`  * bundler (4.0.24)`、`Summary:`、`Homepage:`、`Source Code:`、`Changelog:`、`Bug Tracker:`、`Path: …/gems/bundler-4.0.24`；**无** `Default Gem` | exit 7 `Could not find gem 'bundler'.` |
| `info stringio` | exit 0；`  * stringio (3.2.0)`、`Summary: Pseudo IO on String`、`Changelog:`、`Path: …/gems/stringio-3.2.0`、`Default Gem: yes` | exit 7 `Could not find gem 'stringio'.` |
| `info json` / `show json`（stdin EOF） | exit 0、stderr 空、stdout 恰为 `1 : json_pure` / `2 : json` / `0 : - exit -` / `>  `（两个空格，无换行） | exit 7 `Could not find gem 'json'.` |
| `info zzzznotagem` | exit 7 `Could not find gem 'zzzznotagem'.`（无 Did-you-mean） | 一致 |

### 机制（`.upstream-specs/v4.0.24/bundler/lib/bundler/`）

- `cli/common.rb:68-96` `select_spec(name, regex_match)`：先遍历 `definition.specs` 做**精确名匹配**（命中即返回）；未命中则用 `Regexp.new(name)` 收窄候选；随后 `default_gem_spec(name)` 再追加一条；`case specs.count` 0 → not-found、1 → 直接取、>1 → 菜单。
- `cli/common.rb:98-101` `default_gem_spec(name)`：`Gem::Specification.find_all_by_name(name).last`，仅当 `default_gem?` 才算命中。
- `cli/common.rb:103-111` `ask_for_spec_from`：逐条 `ui.info "<n> : <name>"`、`0 : - exit -`、`ui.ask("> ")`；`num > 0 ? specs[num-1] : nil`——EOF 时 `num = 0`，于是不选、也不报错。
- `cli/info.rb:11-30` 在 `ui.silence { validate_runtime!; Bundler.load.lock }` 之后调用 `Common.select_spec(gem_name, :regex_match)`，`spec` 为 nil 即静默退出 0；`:50-73` 的字段顺序为 `  * name (version)`、Summary、Homepage、Documentation、Source Code、Funding、Wiki、Changelog、Bug Tracker、Mailing List、`Path:`、`Default Gem: yes`、反向依赖。

### 实现

- `assets/bridge/server.rb` `op_default_gem_spec` 增补 `full_name`/`loaded_from`/`summary`/`homepage`/`metadata`；`src/celerite/bridge/client.cr` 对应 NamedTuple 加字段。
- `src/celerite/cli/commands.cr`：新增 `DefaultGemInfo` 与 `parse_spec_name_regex`/`lookup_default_gem`/`installed_bundler_dir`/`append_gemspec_metadata`；`show_info` 在精确匹配失败后走「正则候选 + 默认 gem 追加」两段，候选数 >1 时打印菜单并从 `STDIN.gets` 取序号（EOF 时补一个空格以对齐 `">  "` 的字节），`spec` 仍为 nil 时按默认 gem / bundler 两条分支渲染，最后才落到 not-found。

### 夹具与证据

- `fixtures/differential/info-default-gem-fallback/`（`install --quiet` + `info stringio`）、`fixtures/differential/info-regex-menu/`（`install --quiet` + `info json`）：4.0.24 **2 passed / 0 failed**，2.7.2 **2 passed / 0 failed**。
- 负对照 `C:/temp/celerite-pre71` @ `ab689f5`：两个夹具双 profile 全 FAIL（`exit code: reference=0 celerite=7`、`> Could not find gem 'stringio'.` / `> Could not find gem 'json'.`，且缺菜单四行）。
- 回归 `info`/`show`/`list` 家族 32 例：4.0.24 31 passed / 0 failed / 1 skipped（`show-outdated-verbose-272` 既定延期），2.7.2 32 passed / 0 failed。
- `spec/m7_info_select_spec.cr` 4 例：默认 gem 回退、bundler 渲染、唯一正则命中、缺失 gem 文案。

### 已声明差异

- `info bundler` 的 `Path`/元数据取「正在运行的 bundler」：差分里参考跑的是已安装 gem，而我们的开发夹具经 `CELERITE_REFERENCE_BUNDLER_LIB` 加载检出树，缺少 `specifications/bundler-<v>.gemspec`；因此差分夹具只用 `info stringio`，bundler 的字段只在 spec 断言 `Summary`/`Homepage`，`Path` 不入断言。
- 菜单的交互分支（输入序号选中）未做端到端夹具：差分以 stdin EOF 覆盖「不选即退出 0」；选中分支只有单元级构造，属未验证。
- 参考 `gem_not_found_message` 的 `Did you mean …?` 建议未实现；当前所有 not-found 都只打一行 `Could not find gem '<name>'.`（本任务范围内的用例都不触发建议）。
## 2026-11-21（M7(6) task-73：`plugin install --path` 冲突回滚与源目录删除）

目标：把 roadmap L159 里「命令注册 / 自定义 source 冲突」两条从「已审计」推进到「有双 profile 端到端夹具」，并顺带核对失败路径的副作用。

### oracle（参考 4.0.24 与 2.7.2，`.tmp-scratch/task73/oracle.sh`，隔离 HOME/GEM_HOME/BUNDLE_PATH，`ruby .upstream-specs/v4.0.24/bundler/exe/bundle`）

| 场景 | 参考 stdout | 参考 stderr | 参考退出码 | 参考副作用 |
| --- | --- | --- | --- | --- |
| `plugin install plug_a --path plug_a`（注册 `source "conflict-type"`） | `Resolving dependencies...` + `Installed plugin plug_a` | 空 | 0 | 源目录保留，index 写入 `sources: conflict-type: "plug_a"` |
| 再 `plugin install plug_b --path plug_b`（同 source 类型） | `Resolving dependencies...` | `Failed to install plugin \`plug_b\`, due to Bundler::Plugin::Index::SourceConflict` / `(Source(s) \`conflict-type\` declared by plug_b are already registered.)` | 29 | index 仍只有 plug_a；**源目录 `plug_b` 被删除** |
| 再 `plugin install plug_cb --path plug_cb`（同命令名） | `Resolving dependencies...` | `Failed to install plugin \`plug_cb\`, due to` / `Bundler::Plugin::Index::CommandConflict (Command(s) \`conflictcmd\` declared by` / `plug_cb are already registered.)`（80 列折行） | 29 | index 仍只有 plug_ca；**源目录 `plug_cb` 被删除** |

- 两版参考逐字相同（Windows 下行尾 CRLF，差分按 N2 归一化）。
- 删除机制：`plugin.rb:298-306` 的失败回滚走 `uninstall`，对 path source 而言 `spec.full_gem_path` 就是 `--path` 指定的源目录本身（`plugin/installer/path.rb`），因此注册失败会把该目录 `rm_rf`。
- 同一机制也解释 MalformattedPlugin 路径：插件声明非法时源目录同样被删除（`plugin.rb:292-298`）。因此本任务把删除放在所有 `--path` 安装失败出口，而不是只放在两种冲突上。
- 同源 hook 同名不算冲突（`plugin.rb:215-219` 追加、`index.rb:65-68` 对插件名去重），无第三类夹具。

### 实现

- `src/celerite/cli/commands_surface.cr`：新增 `private def self.remove_failed_plugin_source(root_dir : String)`（`FileUtils.rm_rf` + `Dir.exists?` 守卫，注释指向 `plugin.rb:298-306`、`plugin/installer/path.rb`），在 `--path` 分支的三处 `return 29` 之前调用：`declared[:error]`（MalformattedPlugin）、`CommandConflict`、`SourceConflict`。
- 远端安装路径（`plugin_install_remote`）不动：那条路径没有源目录，参考也不会删除任何用户目录。

### 夹具（`script/differential`，双 profile）

- `fixtures/differential/plugin-conflict-source/`：`extra/plug_a`、`extra/plug_b` 各注册 `source "conflict-type"`；`command` 依次 `plugin install plug_a --path plug_a`、`plugin install plug_b --path plug_b`；`stderr-contains` 断 SourceConflict 两行。
- `fixtures/differential/plugin-conflict-command/`：`extra/plug_ca`、`extra/plug_cb` 各注册 `command "conflictcmd", <Class>`；`command` 同上；`stderr-contains` 断 CommandConflict 两行。
- 两者都依赖工程树比对发现「失败插件的源目录被删除」——这是参考唯一可观测的副作用，`stderr-contains` 只覆盖文案。
- 结果：4.0.24 `5 passed, 0 failed`、2.7.2 `5 passed, 0 failed`（含回归 `plugin-install`、`plugin-source-typed`、`plugin-source-install`）。

### 负对照

- `C:/temp/celerite-pre73`（worktree @ `21d4db7`，重新构建）→ 4.0.24 `0 passed, 2 failed`，差异行：
  - `FAIL plugin-conflict-source … project tree differs: Only in SANDBOX/project: plug_b`
  - `FAIL plugin-conflict-command … project tree differs: Only in SANDBOX/project: plug_cb`
- 说明两条夹具对「源目录删除」有区分力。

### 测试

- `spec/m7_plugin_conflicts_spec.cr` 4 例：source 冲突（exit 29 + 文案 + index 仅 plug_a + plug_b 目录消失 + plug_a 保留）、command 冲突（同上 + index 仅 plug_ca）、成功安装保留源目录、失败后 index 与安装前逐字相同。
- 注意：spec 进程需要把 `TEMP`/`TMP` 指到工作区内（`with_project` 会在 `TEMP` 下建工程目录，沙箱拒绝在工作区外写 `.bundle/plugin`），并显式设置 `CELERITE_BRIDGE_SERVER`。

### 已声明差异

- 交互式冲突之外的失败退出码未逐一取证：本次只固定 MalformattedPlugin / CommandConflict / SourceConflict 三条，其他 `--path` 失败分支（如 `invalid gemspec`）未取 oracle。
- 插件源目录删除是参考的破坏性副作用，我们按参考实现；若将来参考改掉，这里需要同步。

## 2026-11-21（M7(6) task-74A：`bundle clean` 的 system gems 护栏）

参考 `cli/clean.rb:11-24`：`run` 先调 `require_path_or_force`（`--dry-run` 除外），当 `Bundler.use_system_gems?` 且未给 `--force` 时抛 `Bundler::InvalidOption`。判据来自 `settings.rb` 的 `Path#use_system_gems?`：未配置 `path` 且未走 deployment 即使用系统 gem 目录，此时全量清理会删掉 bundle 之外的所有系统 gem。

我方 `src/celerite/cli/commands_install.cr` 的 `self.clean` 此前无条件进入 `perform_clean`，未设 `BUNDLE_PATH` 时会去删系统 gem。

| 场景 | 参考 stdout/stderr | 参考 exit | 修前我方 |
| --- | --- | --- | --- |
| 无 `BUNDLE_PATH`、`clean` | stderr 两行：`Cleaning all the gems on your system is dangerous! If you're sure you want to` / `remove every system gem not in this bundle, run \`bundle clean --force\`.` | 15 | 直接清理，exit 0 |
| 无 `BUNDLE_PATH`、`clean --dry-run` | 正常列出 Would have removed | 0 | 0（一致） |
| 配了 `BUNDLE_PATH`、`clean` | 正常清理 | 0 | 0（一致） |
| 无 `BUNDLE_PATH`、`clean --force` | 正常清理 | 0 | 0（一致） |

实现：`clean` 在解析完开关后先取 `definition.config` 与 `bridge.ruby_environment.default_gem_dir`，用既有的 `InstallPaths.use_system_gems?` 判定；命中且非 `--dry-run`、非 `--force` 时抛 `InvalidOptionError`（status 15、`wrap?` 折行），文案与参考逐字一致，**不进入清理**。`perform_clean` 与 `clean_after_install` 未改动。

夹具：`clean-system-gems-guard`（`env` 新增 `unset:BUNDLE_PATH`，`command` = `install --quiet` + `clean`，`stderr-contains` 两行）。差分 4.0.24 / 2.7.2 均 PASS（exit 15）。负对照 `23cece6` 上 exit 0 且无两行文案。

已声明差异 / 未验证：

- `unset:BUNDLE_PATH` 依赖本轮给 `script/differential` 新增的 `unset:` env 指令；`BUNDLE_PATH=`（空值）不触发参考护栏——空串仍被当作显式 path，实测参考会走另一条 `Could not find json_pure-2.8.1 in locally installed gems` 分支。
- 护栏只看 `use_system_gems?`，未覆盖「`bundle config set --local path.system true` 之外的其他 system 判定组合」的端到端取证；`path.system` 分支仅由单元判据覆盖。

## 2026-11-21（M7(2) task-74B：`config` 数组值的 `Symbol#inspect` 渲染）

`bundle config set --local without "test,dev"` 存的是**一个**字符串元素 `test,dev`。参考打印的是 Ruby `Array#inspect`，元素为 Symbol，故走 `Symbol#inspect`：合法裸名 ``:foo``，其余加引号并转义——`[:"test,dev"]`。我方原实现直接 `":#{item}"`，输出 `[:test,dev]`，与参考不等价（会误导为两个元素）。

| 写法 | `config get` | `config list --parseable` | 我方修前 |
| --- | --- | --- | --- |
| `set --local without "test,dev"` | `...: [:"test,dev"]` | `without=[:"test,dev"]` | `[:test,dev]` / `without=[:test,dev]` |
| `set --local without2 test dev` | `...: "test dev"` | 同（字符串，非数组） | 一致 |
| `set --local without3 '["a","b"]'` | `...: "[\\\"a\\\",\\\"b\\\"]"` | 同 | 一致 |

实现：`src/celerite/config.cr` 新增 `self.symbol_inspect(name)`（裸名正则 `\A[A-Za-z_][A-Za-z0-9_]*[?!=]?\z` 走短式，否则 `:"…"` 并按 `String#inspect` 转义 `"`/`\`/换行/制表）与私有 `ruby_string_inspect`；`parseable_converted` 与 `display_value` 共用该 helper。

夹具：`config-array-symbol-render`（`config set --local without "test,dev"` + `config get without` + `config list --parseable`，stdout 逐字比对）。双 profile PASS；负对照 `23cece6` 两个片段均差异。

已声明差异 / 未验证：

- 仅覆盖含逗号的元素；含空格、引号、反斜杠、空串的元素按 Ruby 规则实现但未逐字取证（`Symbol#inspect` 的非裸名分支只有一条实测样本）。
- `config get` 的多来源优先级列表未新增用例；既有 `config-*` 回归全绿。
## 2026-11-21（M7 task-75：install/clean/exec/outdated 的结构化 Ruby 校验）

**现象**：`Gemfile` 写 `ruby "4.0.6", patchlevel: "999"` 时，`install` 完全无视 patchlevel（exit 0，正常 Fetching/Installing），`check` 却 exit 18；参考两侧一致 exit 18。把 source 换成不可达 https 后参考仍先 exit 18，我方先死在 SSL（exit 17）。

**根因**：四处运行时校验传的是 `evaluation.ruby`——`GemfileEvaluation#ruby` 是 `RubyVersion#to_s` 的人类可读串（`src/celerite/ruby_version.cr:64-71`），不含 patchlevel/engine 选项字段。`check` 走的是正确入口 `Commands.requested_ruby_version`（`src/celerite/cli/commands.cr:1122`，用 `ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version` 构造结构化 `Celerite::RubyVersion`），所以只有 `check` 报了 patchlevel。锚点：`cli/install.rb:24` `Bundler.validate_runtime!`、`cli/clean.rb`（`Bundler.load.clean` 前 `Bundler.definition` 触发同一校验）、`cli/exec.rb`/`cli/outdated.rb:26-33`（先 `validate_runtime!` 再 resolve）。

**修法**：四处（`commands_install.cr` install / clean / exec，`commands_surface.cr` outdated）改用 `Commands.requested_ruby_version(evaluation)` + `RubyRuntime.validate_version!`（已有重载，未复制任何 patchlevel 解析）。`outdated` 另外把校验移到 `materialize_lockfile` **之前**——参考先校验再 resolve，故无锁且未安装时参考给 18 而非 `Could not find gem … in locally installed gems`（exit 7）。

**oracle 表**（4.0.24 与 2.7.2 各测一遍）

| 场景 | 修前 | 修后 | 参考 |
| --- | --- | --- | --- |
| `install`（file:// 索引，patchlevel 999） | exit 0，正常安装 | exit 18 + `Your Ruby patchlevel is 0, but your Gemfile specified 999` | exit 18，同句 |
| `install`（`https://example.invalid`，无 mirror） | exit 17（SSL） | exit 18 + 同句 | exit 18 + 同句 |
| `check` | exit 18 + 同句 | exit 18 + 同句 | exit 18 + 同句 |
| `clean`（配置了 BUNDLE_PATH） | exit 0 | exit 18 + 同句 | exit 18 + 同句 |
| `exec ruby -e 'puts :ran'` | 未校验，跑子进程 | exit 18 + 同句，无 `ran` | exit 18 + 同句 |
| `outdated`（无锁、未安装） | exit 7 `… in locally installed gems` | exit 18 + 同句 | exit 18 + 同句 |

**夹具**：`fixtures/differential/install-patchlevel-mismatch`（离线 `file://` 索引）、`fixtures/differential/install-patchlevel-mismatch-unreachable`（`https://example.invalid`，无 mirror；双 profile 均稳定 exit 18，未退化为 spec-only）。两条都断 exit 18 与关键行。

**spec**：`spec/m7_ruby_patchlevel_spec.cr` 4 例（install / clean / exec / outdated），与 `m7_ruby_runtime_enforcement_spec.cr`、`m7_install_ruby_compat_spec.cr`、`m7_ruby_constraints_spec.cr`、`m7_clean_system_gems_spec.cr`、`m7_exec_spec.cr`、`m7_exec_env_spec.cr` 合并 36 例 0 失败。

**负对照**：`C:/temp/celerite-pre75` @ `d0b7c1a`（构建成功）→ **0 passed / 2 failed**：`exit code: reference=18 celerite=0`、`exit code: reference=18 celerite=17`，两条 needle 均缺失。

**已声明差异**：只对齐「运行时 Ruby 校验」这一层；`Gemfile` 里 `patchlevel` 与锁文件/`CHECKSUMS` 的交互未另取 oracle。`BUNDLE_FROZEN`/`deployment` 与 patchlevel 同时出错时的优先级未逐组合测。
## 2026-11-21（M7 task-76：`BUNDLE_FORCE_RUBY_PLATFORM`）

**现象**：该设置此前不被识别（`BOOL_KEYS` 缺键），`install` 仍按本机平台解析并锁 `platdemo (1.0.0-x64-mingw-ucrt)`；参考在 `BUNDLE_FORCE_RUBY_PLATFORM=true` 下只锁 `platdemo (1.0.0)`、`PLATFORMS` 只有 `ruby`。

**参考机制**：`settings.rb:21` 把 `force_ruby_platform` 列入布尔键；`definition.rb:662` `should_add_extra_platforms?` 在强制时短路（不再补本地平台）；`lazy_specification.rb:221` 与 `match_platform.rb:28` 在强制时取 ruby 变体。已存在的原生锁不会被复用：重新解析、安装 ruby 变体，同时把平台行留在锁里（`resolver.rb:88-89` + `spec_set.rb:301-309`）。

**oracle 表**（`fixtures/gem-index-platform`，4.0.24 与 2.7.2 各测）

| 场景 | 参考结果 |
| --- | --- |
| 无锁 + `true` | GEM `platdemo (1.0.0)`；`PLATFORMS` 仅 `ruby`；4.0.24 CHECKSUMS 带 `sha256=05ced368…`（ruby gem），2.7.2 无 CHECKSUMS |
| 无锁 + `false` / 未设置 | `platdemo (1.0.0-x64-mingw-ucrt)`；`PLATFORMS` 仅 `x64-mingw-ucrt`；4.0.24 digest `sha256=f02daf29…` |
| 已有原生锁 + `true` | 重新解析：两行 spec（ruby + mingw）、两行平台（`ruby`、`x64-mingw-ucrt`），只安装 `platdemo 1.0.0` |

**实现**：`src/celerite/config.cr:17` 布尔键补 `force_ruby_platform`；`src/celerite/resolution.cr` `resolution_platforms` 在强制时以 ruby 起始、`force_ruby_platform?` 供各处判定、`reuse_locked_resolution?` 强制时不复用、`decisions_to_specs` 强制时选 ruby 变体、平台输出在强制时只加 `ruby`（并保留去重守卫，避免重复写 `x64-mingw-ucrt`）、`lock_extra_specs` 按 `full_name` 去重。

**夹具**：`fixtures/differential/install-force-ruby-platform`（`env` 传 `BUNDLE_FORCE_RUBY_PLATFORM=true`，`file-equals-4.0.24`/`file-equals-2.7.2` 整锁逐字节）；`install-force-ruby-platform-locked`（预置原生锁 + 强制，`file-contains` 两行 spec 与两行平台）。2.7.2 的 locked 变体标 `deferred-2.7.2`：手写预置锁缺 `BUNDLED WITH`，2.7.2 参考会改走 `https://rubygems.org/` 并挂住，故降级为文档化 deferral。

**spec**：`spec/m7_force_ruby_platform_spec.cr` 4 例（强制只锁 ruby 行、`false` 保留 mingw 行、未设置等价于 `false`、原生锁 + 强制保留两行），与 `m7_add_platform_spec.cr`、`m7_lock_options_spec.cr`、`m7_platform_validation_spec.cr`、`m7_platform_auto_add_spec.cr` 合并 24 例 0 失败。

**负对照**：`C:/temp/celerite-pre76` @ `9f7d380` → **0 passed / 2 failed**（stdout 与整锁不一致；缺 `    platdemo (1.0.0)` 与 `  ruby` 两个 needle）。

**已声明差异**：预置锁若缺 `CHECKSUMS` 段，4.0.24 参考会整段重建三行，我方仍略去该段（`checksums_enabled?` 参考锁内段落，属既有差异，未在本次修）。强制平台与 `clean`/`frozen` 的组合未逐项取 oracle。
## 2026-11-21（M7 task-77：`bundle cache` 的 `BUNDLE_CACHE_PATH`）

**现象**：`BUNDLE_CACHE_PATH=custom bundle install && bundle cache` 时参考写 `<gemfile 根>/custom/json_pure-2.8.1.gem` 并打印 `Updating files in custom`，我方忽略该设置，仍写 `vendor/cache`、打印 `Updating files in vendor/cache`。

**根因**：`run_cache` 只认 `--cache-path` 参数，缺省直接硬编码 `<gemfile 根>/vendor/cache`，没有读 `cache_path` 设置。参考的显示串是 `Bundler.settings.app_cache_path`（`runtime.rb:115`），即**设置的原始值**（相对写法原样打印，绝对路径也原样打印），落盘位置 = `Pathname.new(root).join(app_cache_path)`（`bundler.rb:340-343`）。

**oracle 表**（`fixtures/gem-index`，4.0.24 与 2.7.2 各测，隔离 HOME/BUNDLE_PATH/BUNDLE_APP_CONFIG）

| 场景 | 参考 | 修前我方 |
| --- | --- | --- |
| 未设置 | `Updating files in vendor/cache`，写 `vendor/cache/…` | 一致 |
| env `custom` | `Updating files in custom`，写 `custom/…` | `vendor/cache`（错） |
| `.bundle/config` `BUNDLE_CACHE_PATH: "cfgcustom"` | `Updating files in cfgcustom`，写 `cfgcustom/…` | 同 env（错） |
| env 绝对路径（工作区内） | 原样打印绝对路径，写该目录 | 忽略（错） |
| `cache --cache-path flagdir` 且 env 同时给值 | `Updating files in flagdir`（`CLI::Cache#run` 用 `set_command_option_if_given` 覆盖设置，`cli/cache.rb:11`） | 只认 flag，但 env 情形已在上面体现（改后一致） |
| 多值 `first:second` | exit 32，`Errno::ENOTDIR … dir_s_mkdir` | 不跟随（未夹带） |

**实现**（`src/celerite/cli/commands_install.cr` `run_cache`）：`configured_cache = definition.config["cache_path"].as?(String)`；`cache_label = cache_arg || (configured_cache.nil? || configured_cache.empty? ? "vendor/cache" : configured_cache)`；`cache_target = File.expand_path(cache_label, gemfile_root)`。`cache_path` 本就在 `STRING_KEYS`（`config.cr:202`），env 与 `.bundle/config` 两种来源都经 `Config#[]` 生效，无需新增键。

**夹具**：`fixtures/differential/cache-path-env`（`env` = `BUNDLE_CACHE_PATH=custom`，`command` = `install` + `cache`）。断言依靠精确 stdout（`Updating files in custom`）与 harness 的项目树比对（`custom/` 出现、`vendor/` 不出现），未额外加 `file-contains`。

**spec**：`spec/m7_cache_path_spec.cr` 新增 2 例（env 生效并打印原始标签；`--cache-path` 压过 env），连同既有 3 例为 5 例；`m7_cache_path_spec` + `m7_app_config_env_spec` + `m7_clean_system_gems_spec` 合并 **12 例 0 失败**。

**负对照**：`C:/temp/celerite-pre77` @ `544aea0` → `FAIL cache-path-env`：`< Updating files in custom` vs `> Updating files in vendor/cache`，并附 `project tree differs`。

**附带修正**：`spec/m7_app_config_env_spec.cr` 三处断言仍按 `File.join`（反斜杠）比较，而 task-56 起 `Config.app_config_path`/`join_config` 返回正斜杠形态，故该 spec 在 `544aea0` 上**本来就是红的**（已用 `git stash` 在基线复现）。本次只把期望串归一化，产品代码未动。

**已声明差异**：多值 `BUNDLE_CACHE_PATH`（`first:second`）参考直接崩（exit 32 `Errno::ENOTDIR`），我方不刻意复刻该崩溃；`--cache-path` 与多值组合未测。
## 2026-11-21（M7 task-78：`BUNDLE_VERBOSE` 与 verbose 调试行）

参考 `settings.rb:21` 把 `verbose` 声明为 BOOL 设置，`cli.rb#initialize` 用 `Bundler.ui.level = "debug" if settings[:verbose]` 提升 UI 级别，因此 `BUNDLE_VERBOSE=true` 与 `--verbose` 等价；但 `CLI#print_command` 回显的是用户实际输入，设置驱动的 verbose 不会凭空多出 `--verbose`。

| 形态 | 参考输出（4.0.24 / 2.7.2 一致） |
| --- | --- |
| `install --verbose` / `-V` | `Running \`bundle install --verbose\` with bundler <ver>` + 调试行 |
| `BUNDLE_VERBOSE=true install` | `Running \`bundle install\` with bundler <ver>` + 相同调试行 |
| `BUNDLE_VERBOSE=false install --verbose` | 仍 verbose（旗标优先） |
| 已有锁、无变更 | `Found no changes, using resolution from the lockfile` / `Using bundler <ver>` / `0:  bundler (<ver>) from <gems>/gems/bundler-<ver>/../../specifications/…` / `Using <name> <ver>` / `0:  <name> (<ver>) from <bundle>/ruby/<abi>/specifications/<name>-<ver>.gemspec` |
| 无锁 | `Resolving dependencies because there's no lockfile` / `Using a local server, bundler won't use the CompactIndex API` 先于 `Fetching source index …` |

锚点：`definition.rb:868-875`（解决原因）、`fetcher.rb:273-276`（本地服务器）、`parallel_installer.rb:18`（`#{worker}:  #{spec.name} (#{spec.version}) from #{spec.loaded_from}`）、`cli.rb:777-791`（回显）。

实现要点：
- `src/celerite/cli/commands.cr`：`--verbose` 与 `-V` 同样置 `CELERITE_VERBOSE`；新增 `env_verbose?` 读取 `BUNDLE_VERBOSE`；`print_command_echo` 拆出 `flag_verbose`，只据实际旗标渲染 `--verbose` 片段。
- `src/celerite/config.cr:17`：`BOOL_KEYS` 增 `verbose`。
- `src/celerite/cli/commands_install.cr`：解析前按 `lockfile_exists?` 打印原因行与本地服务器行；安装结束后按 `Using` / `0:` 打印 bundler 与各 GEM spec。
- `assets/bridge/server.rb` + `src/celerite/bridge/client.cr`：新增 `ruby_default_dir`（`Gem.default_dir`，不受 `GEM_HOME` 影响），因为沙箱把 `GEM_HOME` 指向 `SANDBOX/gems`，而默认 gem 的 `loaded_from` 仍属 Ruby 安装目录。
- `src/celerite/cli/commands_surface.cr`：删除 `outdated` 里拼接而成的假行（`Re-resolving … Using a local server …`），只保留已取证的本地服务器行。

夹具 `fixtures/differential/install-verbose-existing-lock`：`Gemfile` = `source "file:///@INDEX_DIR@"` + `gem "json_pure"`，`command` = `install` / `install --verbose`（首跑非 verbose 以避开下载计时行）。双 profile PASS。负对照 `C:/temp/celerite-pre78` @ `2d14f19` → 0 passed / 1 failed，五条调试行全缺。

已声明差异（未复现）：
1. 全新安装路径下参考还打印 `Downloaded <name> in: 0.001s` / `Installed <name> in: 0.029s` 等计时行——数值非确定，未复现。
2. 并行安装器的工作线程序号（如 `1:`、`3:`、`4:`）未复现：我方安装是串行的，固定打印 `0:`（与锁复用路径的参考输出一致）。
3. `outdated` 的 `Re-resolving dependencies because …` 原因行未取 oracle，未实现。

## 2026-11-21（M7 task-79：verbose 的「重解析原因行」）

`definition.rb:866-876 resolve_needed_reason` 决定 debug 级别的那一行；`:886-902 unlocking_reason` 为空时整句以空格结尾，而 Thor 的 `say`（`shell/basic.rb#say`，`force_new_line` 默认 `message !~ /( |\t)\Z/`）对以空格结尾的消息**不换行**，于是紧随其后的 `fetcher.rb:273-276` 本地服务器行被并到同一行——这是参考的真实字节，不是我们的拼接。

| 命令（`--verbose`） | 参考打印的那一行（4.0.24 与 2.7.2 逐字相同） |
| --- | --- |
| `update json_pure` | `Re-resolving dependencies because bundler is unlocking gems: (json_pure)`（独立一行，随后单独一行 `Using a local server, …`） |
| `update --all` | `Re-resolving dependencies because bundler is unlocking Using a local server, bundler won't use the CompactIndex API`（同一行，`unlocking` 后有尾随空格） |
| `outdated` | 同上（同一行） |
| `check`（Gemfile 新增依赖后） | `Found changes from the lockfile, re-resolving dependencies because the dependencies in your gemfile changed`，随后单独一行本地服务器行 |
| `install`（Gemfile 改动后） | 同上两行，再 `Fetching source index …` / `Resolving dependencies...` |
| `install`（锁里 CHECKSUMS 条目被清空） | `Found no changes, using resolution from the lockfile` + 本地服务器行（**没有** CHECKSUMS 相关原因行） |

实现：
- `src/celerite/cli/commands.cr`：新增 `print_debug_reason`（结尾为空格时不换行，模拟 Thor `say`）、`debug_local_server`、`debug_reason_for`（无锁 / 依赖未变 / 依赖变化三种，其余 `lockfile_changed_reason` 条件无实测触发，不臆造）、`verbose_debug?`。
- `src/celerite/cli/commands_install.cr`：原因行统一走 helper；本地服务器行只在**真的会取索引**时打印（锁复用路径不打印——该行来自 fetcher，不是解析器）。
- `src/celerite/cli/commands_surface.cr`：`update` 按 `gems` 是否为空选择 `gems: (…)` 或空名（尾随空格）形态；`outdated` 固定空名形态；两者都在 `resolve!` 前打印。`outdated` 里 task-78 遗留的那条本地服务器行已删除（否则重复）。

夹具：`fixtures/differential/outdated-verbose-unlock-reason`（`install --quiet` + `outdated --verbose`）、`check-verbose-changes-reason`（Gemfile 比锁多 `thor`，`check --verbose`）；双 profile PASS。负对照 `C:/temp/celerite-pre79` @ `c59c031` → **0 passed / 2 failed**（`< Re-resolving … unlocking Using a local server…` vs `> Using a local server…`；`< Found changes …`/`< Using a local server …` 缺失）。spec `spec/m7_resolve_reason_spec.cr` 4 例。

已声明差异（未实现，无触发取证）：
1. `lockfile_changed_reason` 的另外 12 个条件（sources 变更、缺平台、path/git gemspec 变更、缺依赖、CHECKSUMS 缺失/为空、bundler 自更新等）未逐条实现；`lockfile_changed_reason` 只实现了 oracle 命中的 `the dependencies in your gemfile changed`，未命中时回落到「不改写」。
2. `update`/`outdated` 的 verbose `Using …` 与 `N:  … from …` 并行工作行未实现：参考的工作线程序号（实测出现 `3:`/`5:`/`7:`）依赖并行完成顺序，非确定，不宜进差分断言。
3. `outdated` 的 `Re-resolving …` 只覆盖「有锁且解锁」形态；无锁时参考走 `Resolving dependencies because there's no lockfile`（已由 task-78 的 install 路径覆盖 install，未单独验 outdated）。

## 2026-11-21（M7 task-80：`bundle add` 的 requirement 渲染与 option 冲突）

D1：`--version` 的值是**逗号分隔的 requirement 列表**（`cli/add.rb:33`），每个条目经 `Gem::Requirement::PATTERN` 校验（`:57-59`），再由 `Injector` 逐条 dump（`injector.rb:106`）。我方旧实现把它包成 `"= <值>"`，于是 `~> 2.8` 变成 `"= ~> 2.8"`，Gemfile 已写坏后才报 `Illformed requirement`。

| 场景（`--skip-install`，有 `file://` 索引） | 修前我方 | 参考 | 修后我方 |
| --- | --- | --- | --- |
| `--version ~>2.8` | exit 1，写 `"= ~> 2.8"` + `Illformed requirement` | exit 0，`"~> 2.8"` | 一致 |
| `--version >=2.6,<2.9` | exit 1，`"= >=2.6,<2.9"` | `">= 2.6", "< 2.9"` | 一致 |
| `--version 2.8.1` | `"= 2.8.1"` | `"= 2.8.1"` | 一致 |
| `--version bogus` | exit 1，写坏行 | exit 15，`Invalid gem requirement pattern 'bogus'`，Gemfile 不动 | 一致 |
| `--require false` / `--group dev,test` / `--source …` | 与参考一致 | `require: false` / `groups: [:dev, :test]` / `source: "<verbatim>"` | 一致（随选项顺序一并复核） |

D3：`--github` 原先无分支、被静默丢弃；参考 `injector.rb:116` 写 `github: "<v>"`，拼装顺序（`:122`）为 source→path→git→github→branch→ref→glob→require。全选项组合实测（`--version ~>2.8 --group dev,test --source … --glob x.gemspec --require false`）逐字一致：`gem "json_pure", "~> 2.8", groups: [:dev, :test], source: "…", glob: "x.gemspec", require: false`。

D2：参考 `cli/add.rb:41-52` 四条互斥校验（exit 15，Gemfile 不动）；我方原先只校验 strict+optimistic 与空名，`--branch main` 会先写 Gemfile 再以 exit 4 失败。现按参考顺序（git+github → branch 无 git/github → ref 无 git/github → branch+ref）在写盘前拦下，文案逐字。**该块仅 4.x 存在**：实测 2.7.2 无此校验（`--branch` 单独 exit 4、`--ref` 单独 exit 0 并写行、git+github exit 4、git+branch+ref exit 11），故用 `profile_2_x?` 门控，2.7.2 夹具标 `deferred-2.7.2`。

夹具：`add-version-requirement`（`--version ~>2.8`，断言 Gemfile 逐字；注意差分 `command` 行不做引号解析，带空格的 requirement 必须写成 `~>2.8` 单 token）、`add-option-conflicts`（四条命令，断言 exit 15 + 四条文案，Gemfile 未变）。spec `spec/m7_add_version_requirement_spec.cr` 4 例（`~>`、`>=,<`、裸版本、非法）。

已声明差异：`--github owner/repo --skip-install` 参考 exit 0 且不 clone，我方写完 `github: "rails/thor"` 后在 relock 阶段 clone 失败（exit 11）——写入行逐字一致，退出码不一致，未加差分夹具（仅 spec 层面覆盖 suffix 渲染）；D1 的 `--version` 与 `--path`/`--git` 组合未逐条 oracle。

已知历史红：`spec/m7_gemfile_plugins_spec.cr` 的 `gem-index/,` 断言在 `9bda5f5` 上即失败（`git stash` 复现，7 examples/1 failure），与本任务无关，未修。

## 2026-11-21（M7 task-81：`add` 失败后的 Gemfile 回滚、多余的重解析行、一条过期 spec）

参考 `Injector` 是「先解析/安装注入的依赖，成功后才 append Gemfile」，所以任何失败路径退出时 Gemfile 逐字不变。我方因为锁重生成需要新依赖，先写后解析，于是失败时把注入行留在文件里。现在在 append 之后的所有失败路径（`--skip-install` 的重锁、普通安装）都恢复调用前的字节：

| 场景（`file://` 索引） | 修前我方 | 参考 | 修后我方 |
| --- | --- | --- | --- |
| `add nosuchgem --skip-install` | exit 7，stdout 多一行 `Resolving dependencies...`，Gemfile 残留 `gem "nosuchgem"` | exit 7，stdout 仅 `Fetching source index …`，Gemfile 不变 | 逐字一致 |
| `add json_pure --version bogus --skip-install` | exit 15，Gemfile 不变（本就正确） | 同 | 一致 |
| `add json_pure --path vendor/nope --skip-install` | exit 13，Gemfile 不变 | 同 | 一致 |
| `add json_pure --skip-install`（正常路径） | 一行 `Resolving dependencies...` | 同 | 一致（未回归） |

实现（`src/celerite/cli/commands_surface.cr`）：
- `add()` 在 `Bridge::Client` 建立前保存 `gemfile_backup = File.read(gemfile_path)`，`append_gemfile` 后置 `gemfile_appended`；`--skip-install` 的重锁与末尾 `install(...)` 都在 `rescue` 中恢复备份后重抛。
- `latest_requirement_for` 的 `Resolving dependencies...` 从「取索引后无条件打印」改为「索引对该 gem 有答案（`versions` 非空）才打印」，并把显式 `--version` 分支的打印补上（否则 `add-version-requirement` 丢行）。解析顺序仍是 `Fetching source index …` → `Resolving dependencies...`。

A（过期 spec，非产品缺陷）：`spec/m7_gemfile_plugins_spec.cr` 原断言 `gem-index/,` + `cached gems or installed locally.`，那是 `plugin install --source` 路径的措辞（task-47）。Gemfile 里声明 `type:` 型 source 走普通安装路径，参考实测逐字为：

```
Could not find gem 'bundler-source-psource' in rubygems repository
file:///<abs>/fixtures/gem-index/ or
installed locally.
```

（同 Gemfile、同索引，4.0.24 实测；差分夹具 `plugin-gemfile-missing` 一直是这个形态。）已把期望改为 `gem-index/ or` + `installed locally.` 并改写注释，产品未动。

C（只记录，不修）：`add json_pure --github rails/thor --skip-install`，参考先 `Fetching https://github.com/rails/thor.git` 再 `Could not find gem 'json_pure' in https://github.com/rails/thor.git (at <rev>).`，Gemfile 不变；我方先查 rubygems 索引并报 `Could not find gem 'json_pure (~> 2.8)' …`，Gemfile 现在也会回滚（B 的修复顺带覆盖）。这是「先选源再选版本」与「先选版本再选源」的顺序差异，属 C 类，仅记录。**（已被 task-82 更正）**当时据此记录为「选源顺序」差异；task-82 实测表明源选择已对齐——我方同样解析到 `git` 源与同一 rev `cb11e8e`。「先查 rubygems 索引」指的是注入前的版本探测，参考也先探测索引再按 git 源解析；残差只是「参考在解析阶段只读 mirror，我方在解析阶段就检出」，而检出被本机 msys `0xC0000022` 阻断（exit 11）。该段结论按历史标注保留，以 task-82 节为准。

夹具：`add-failure-keeps-gemfile`（`command` = `add nosuchgem --skip-install`，`file-equals` 断言 Gemfile 与初始一致，`stderr-contains` 断言 exit 7 的文案）。spec：`spec/m7_add_failure_rollback_spec.cr` 3 例（缺 gem、坏 requirement、`--path` 不存在）。

## 2026-11-21（M7 task-82：`add --github` 的源选择，以及一条「故意不对齐」）

参考把 `github:` 选项在 DSL 层就归一成 git 源（`dsl.rb:340-350` `git_source(:github)`，`Bundler::Source::Git` + `https://github.com/<repo>.git`），所以注入的依赖按 git 源解析；我方桥接同样走真实 Bundler DSL，实测 `gem "json_pure", github: "rails/thor"` 求值出的源是 `Bundler::Source::Git`、`uri=https://github.com/rails/thor.git`，与参考一致。

| 场景（`file://` 索引） | 参考 4.0.24 | 我方 |
| --- | --- | --- |
| `add json_pure --github rails/thor --skip-install` | `Fetching https://github.com/rails/thor.git` → stderr `Could not find gem 'json_pure' in https://github.com/rails/thor.git (at cb11e8e).`，exit 7，Gemfile 不变 | 源选择相同（git 源，同一 URL、同一 rev `cb11e8e`），但解析后继续做 `git clone --quiet --no-hardlinks <mirror> <dest>` 检出，被本机 msys 的 `NtCreateDirectoryObject … 0xC0000022` 打断：`git command failed: git clone --quiet --no-hardlinks`，exit 11，Gemfile 已回滚（task-81） |
| `add … --github … --branch <b>` | 分支随注入行写入 `branch:` 选项 | 注入行渲染一致；端到端同样卡在检出 |
| `--git <本地仓库> --skip-install` / `--ref <tag>` | 不联网即可完成 | 本机 git 子进程同样被 `0xC0000022` 阻断（与 `plugin-git-local*` 同族） |

结论：**源选择本身已对齐**，残差是「参考在解析阶段只读 mirror、不检出；我方在解析阶段就检出」——检出被环境阻断，无法端到端验证。为此未新增 `add-github-source-order` / `add-git-local-ref` 差分夹具（在本机必然因环境变红），改以 `spec/m7_add_github_source_spec.cr`（2 例）在桥接求值边界断言：`github:` ⇒ `type=git`、`remote=https://github.com/rails/thor.git`、且无 branch/tag/ref。

### 故意不对齐（记录，不改产品）

`install --redownload` 在「gem 已安装、`bundle/ruby/<abi>/cache/<full_name>.gem` 已被删除」时：

- 参考：exit 5，stderr `Bundler::GemNotFound: Could not find json_pure-2.8.1.gem for installation` + 约 40 行回溯（`source/rubygems.rb:586` `rubygems_gem_installer`），即崩溃路径。
- 我方：exit 0，从源重新下载并回填 cache（task-60 的实现）。

理由：参考此处是缺陷（把「强制重装」限制在 cache 命中，cache 缺失时不是给出可执行的错误而是抛内部异常）。对齐等于复制该缺陷、并把一个可自愈的路径改成崩溃，故**故意不对齐**，仅记录。

## 2026-11-21（M7 task-83：`install --local` 只限制来源，不跳过安装）

### oracle（两版 profile；`file://` 索引；隔离 HOME/BUNDLE_PATH/BUNDLE_APP_CONFIG；参考 = `ruby .upstream-specs/v4.0.24/bundler/exe/bundle`）

| 场景 | 参考 | 我方（修前） |
|---|---|---|
| `vendor/cache/json_pure-2.6.0.gem` 存在，`install --local` | exit 0，`Resolving dependencies...` / `Installing json_pure 2.6.0` / `Updating files in vendor/cache` / `Bundle complete! 1 Gemfile dependency, 1 gem now installed.`，bundle 内有 `ruby/4.0.0/specifications/json_pure-2.6.0.gemspec` | exit 0，**无 `Installing` 行**，bundle 内没有任何 gemspec |
| 同上，`install`（无 `--local`） | 多一行 `Fetching source index from …`，其余一致 | 一致 |
| `--local` 且 cache 为空、`vendor/cache` 目录存在 | exit 7，`Could not find gem 'json_pure (= 2.6.0)' in cached gems or installed locally or` / `in gems cached in vendor/cache.` | 一致（task-69 已对齐） |

机制：`cli/install.rb:33` 走 `Installer#run` → `install(spec)`，跳过条件只有 `installed?(spec)`（即「已在 bundle 中」，`source/rubygems.rb:181`/`:206`）；`--local` 只经 `definition.rb:190-203 setup_domain!` 关掉 remote 来源，不改变安装步骤。

### 实现

`src/celerite/cli/commands_install.cr`：删掉 `if resolution.local_only … pending = pending.reject { |spec| resolution.local_installed_full_names.includes?(spec.full_name) }`。该过滤把 `GEM_HOME` 里同名同版本的副本当作「已安装」，于是既不下载也不安装，bundle 留空却报 `Bundle complete!`。`--local` 的来源限制仍由 `resolution.local_only`（`index_specs_for` 只返回本地候选）负责。

### 装具与夹具

- `fixtures/differential/install-local-vendored-install/`：`Gemfile` = `source "file:///@INDEX_DIR@"` + `gem "json_pure", "2.6.0"`；`extra/vendor/cache/json_pure-2.6.0.gem`；`command` = `install --local`；`installed-tree` = `ruby/*/gems`、`ruby/*/specifications`。双 profile **PASS**（4.0.24 / 2.7.2 各 1 passed）。
- `spec/m7_local_install_step_spec.cr` 3 例：`--local` 把 vendored gem 装进 bundle（断言 `Installing json_pure 2.6.0` + bundle 内 gemspec）；第二次运行不再 `Installing`；cache 为空时仍 exit 7 并带 `in cached gems or installed locally`。

### 反假绿

- **差分夹具无区分力**：harness 把 `GEM_HOME` 指到沙箱空目录（`script/differential:304-309`），前置条件（宿主同名同版本副本可见）无法复现，基线二进制 `01d19d4` 也 **PASS** 该夹具 → 该夹具是回归护栏。
- **区分力由 spec 提供**：`C:/temp/celerite-pre83` @ `01d19d4` 跑同一 spec → **1 example failed**（`out.should contain("Installing json_pure 2.6.0")`，实际输出 `Resolving dependencies...` 起、无 Installing 行）；修后 3/0。

### 已声明差异 / 未验证

- `--prefer-local` 走同一安装路径，本轮未单独取 oracle（逻辑上不受本次删除影响：`prefer_local` 只影响版本选择）。
- 远端 `install`（非 `--local`）无 `vendor/cache` 时的 `Fetching`/`Installing` 顺序未变，回归夹具覆盖。
- `bundle package` / `cache --all` 与本次改动无关（那条仍在 roadmap L158 挂账）。

## 2026-11-21（M7 task-84：`cache_all` 下的工程外 `path` 源复制）

### oracle（4.0.24；`file://` 索引；隔离 HOME/BUNDLE_PATH/BUNDLE_APP_CONFIG；`gem "pgem", path: "../pgem"`）

| 场景 | 参考 | 我方（修前） |
|---|---|---|
| `cache`，`BUNDLE_CACHE_ALL` 未设 | exit 0；stdout `Resolving dependencies...` / `Bundle complete! 1 Gemfile dependency, 1 gem now installed.` / `Bundled gems are installed into …` / `Updating files in vendor/cache`；落 `vendor/cache/pgem/{.bundlecache,lib/pgem.rb,pgem.gemspec}` | exit 0，输出一致，`vendor/cache/` 为空 |
| `cache`，`BUNDLE_CACHE_ALL=false` | exit 0，不复制 | 一致（不复制） |
| `cache`，`path: "vendor/pgem"`（工程内） | exit 0，不复制 | 一致 |
| `cache`（2.7.2） | exit 0，**不复制**，并把 `BUNDLE_CACHE_ALL: "false"` 写进 `.bundle/config` | 一致 |

机制：`runtime.rb:109-142` 逐 spec 调 `source.cache(spec, custom_path)`；`source/path.rb:84-96` `return unless Bundler.settings[:cache_all]` → 工程内源直接返回 → `FileUtils.rm_rf(app_cache_path)` → `cp_r("#{@original_path}/.", app_cache_path)` → `touch(app_cache_path.join(".bundlecache"))`，目录名取 `app_cache_dirname` = gem 名（`:110-112`）。`settings.rb:88` 把 `BUNDLE_CACHE_ALL` 默认设为 `true`，所以**默认即复制**，只有显式 `false` 才关。`git` 源有同形 `cache`。

### 实现

`src/celerite/cli/commands_install.cr` `run_cache`：在既有 `.gem` 复制之后，若 `definition.config["cache_all"] != false`，遍历锁文件的 `PATH` 源：`remote` 相对 Gemfile 根展开，落在根内（`starts_with?(root + "/")`，统一正斜杠）则跳过；否则 `rm_rf` 目标、逐子项复制（等价 `cp_r("src/.", dest)`），再 `File.touch(dest/.bundlecache)`。目录名取该源第一个 spec 的 `name`，回退为源目录 basename。2.7.2 分支此前已把 `cache_all` 写成 `false`，故自动不复制，与参考一致。

### 装具

`script/differential` 新增 `sibling/` 约定（在 `extra/` 之后、`bundle-preset/` 之前）：`fixtures/differential/<f>/sibling/<rel>` 复制到 `<sandbox>/<rel>`，两侧同做。用于「工程外的 path 源」——项目在 `<sandbox>/project`，`../pgem` 即 `<sandbox>/pgem`。未改动 `extra/`、`bundle-preset/` 语义。

### 夹具与 spec

- `fixtures/differential/cache-all-path/`：`Gemfile` = `source "file:///@INDEX_DIR@"` + `gem "pgem", path: "../pgem"`；`sibling/pgem/{pgem.gemspec,lib/pgem.rb}`；`command` = `cache`；`file-contains` 断言 `vendor/cache/pgem/lib/pgem.rb` 命中 `module Pgem`、`vendor/cache/pgem/pgem.gemspec` 命中 `pgem`；`deferred-2.7.2` 说明 2.7.2 固定写 `cache_all: false`、不复制。4.0.24 PASS。
- `fixtures/differential/cache-no-all-path/`：同结构 + `env` `BUNDLE_CACHE_ALL=false`；`file-absent` = `vendor/cache/pgem/lib/pgem.rb`。双 profile PASS。
- `spec/m7_cache_all_path_spec.cr` 3 例：默认复制且 `.bundlecache` 为空文件；显式 `false` 不复制；工程内 path 源不复制。

### 反假绿

负对照 `C:/temp/celerite-pre84` @ `dab70e3`（`bin/` 先建，build 0）：`FAIL cache-all-path`，差异行 `project tree differs: Only in SANDBOX/project/vendor/cache: pgem` 与两条 `file-contains differs`；`cache-no-all-path` 在该基线上 **PASS**（纯回归护栏，无区分力——刻意如此：它守的是「不要多复制」）。

### 已声明差异 / 未验证

- `glob:` 多 gemspec 的 `path` 源复制未取 oracle（本轮预算内未做）。
- `git` 源的 `Source::Git#cache` 未实现（工程外 git 源整目录复制）——本机 git 子进程另受 `0xC0000022` 影响，无法端到端验证。
- `package` 命令在本仓库与 `cache` 共用 `run_cache`，但未单独取 oracle。
- `.bundlecache` 的存在性由 spec 断言，差分夹具只能断言非空文件内容（空文件无法用现有 `file-contains`/`file-absent` 表达）。

## 2026-11-21（M7 task-85：`~/.gemrc` 的 `:http_proxy`）

### oracle（`fixtures/gem-index` 由 `script/http_index_server.js` 起在 8765 端口；隔离 HOME/BUNDLE_PATH/BUNDLE_APP_CONFIG）

代理探测值 `http://127.0.0.1:9`（无监听）。

| 场景 | 4.0.24 | 2.7.2 |
|---|---|---|
| 仅 `~/.gemrc` `:http_proxy` | exit 17，stderr `Could not reach host 127.0.0.1:8765…`，不写锁 | 同 |
| `.gemrc` + `http_proxy` env（两个不同值） | gemrc 值胜出 | 同 |
| 仅 env `http_proxy` | exit 17（env 被采用） | 同 |
| 仅 `.bundle/config` `BUNDLE_HTTP_PROXY` | **exit 0**，正常写锁（该键不参与取代理） | 同 |
| `.gemrc` `:http_proxy: :no_proxy` | exit 0，正常解析 | 同 |
| 无 `.gemrc`、无 env | exit 0 | 同 |

Ruby 侧直接取证：`Gem.configuration[:http_proxy]` 在「gemrc + env」下返回 gemrc 值（`"http://127.0.0.1:9"`），仅 env 时为 `nil`；`:no_proxy` 时返回符号 `:no_proxy`；字符串键 `http_proxy:` 同样被读入。

### 机制

`fetcher.rb:262` `GemRemoteFetcher.new Gem.configuration[:http_proxy]`，`:313-316` `if gem_proxy = Gem.configuration[:http_proxy]; con.proxy = Gem::URI.parse(gem_proxy) if gem_proxy != :no_proxy`。`Gem.configuration` 来自 `~/.gemrc`（RubyGems 的 `Gem::ConfigFile`），因此 gemrc 优先于 `http_proxy` 环境变量；`:no_proxy` 是「显式关闭」。`.bundle/config` 的 `proxy`/`http_proxy` 键不进这条链路。

### 实现

`src/celerite/proxy.cr`：新增 `gemrc_http_proxy`（读 `$HOME/.gemrc`，`HOME` 缺失时退回 `USERPROFILE`；YAML 解析，键接受 `:http_proxy` 与 `http_proxy`；值为 `:no_proxy` 时返回 disabled）与 `gemrc_path`；`resolve` 顺序改为 **gemrc → `.bundle/config`（`proxy` → `http_proxy`）→ 环境**，gemrc 的 `:no_proxy` 直接返回 nil 并短路后续来源。`src/celerite/cli/commands.cr:2650-2659` 的注释改正为「参考读 gemrc、`:sources` 不读」。

装具：`script/differential` 新增 `home/` 约定（在 `sibling/` 之后）——`fixtures/differential/<f>/home/<rel>` 复制到两侧 `<sandbox>/home/<rel>`，即两侧 `HOME`。

### 夹具与 spec

- `fixtures/differential/lock-gemrc-proxy/`：`Gemfile` = `source "http://127.0.0.1:8765/"` + `gem "json_pure"`；`http-index` 指向 `fixtures/gem-index`；`home/.gemrc` = `:http_proxy: http://127.0.0.1:9`；`env` = `unset:http_proxy`/`unset:HTTP_PROXY`/`unset:no_proxy`；`command` = `lock`；`stderr-contains` = `Could not reach host 127.0.0.1:8765`；`file-absent` = `Gemfile.lock`。双 profile PASS（exit 17）。
- `fixtures/differential/lock-gemrc-no-proxy/`：同结构但无 `home/`；`file-contains` = `Gemfile.lock` 内 `json_pure (2.8.1)`。双 profile PASS（exit 0）。
- `spec/m7_gemrc_proxy_spec.cr` 5 例：gemrc 生效、字符串键、gemrc 胜 env、`:no_proxy` 关闭（即使 env 有值）、无 gemrc 时回退 env。

### 实测

差分新 2 条 + 回归（`network-unreachable`、`install-fresh`、`lock-noop`、`cache-path-env`）：4.0.24 6 passed / 0 failed；2.7.2 5 passed / 0 failed。负对照 `C:/temp/celerite-pre85` @ `37ede89`：`FAIL lock-gemrc-proxy`，差异行 `exit code: reference=17 celerite=0`、`stderr-contains differs: needle=Could not reach host 127.0.0.1:8765`、`file-absent violated (Gemfile.lock): ref_exists=no cel_exists=yes`；`lock-gemrc-no-proxy` 在该基线上 PASS（纯回归护栏，无区分力）。

### 已声明差异 / 未验证

- `.bundle/config` 的 `proxy`/`http_proxy` 参考不参与取代理，我方仍读（有意保留，属扩展）；若需要严格对齐，应删除该分支。
- gemrc 的 `https_proxy`、`no_proxy`（除 `:http_proxy: :no_proxy` 这一特例）未对齐；参考只关心 `:http_proxy` 一个键。
- 系统级 gemrc（`Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE`）未读。
- `~/.gemrc` 的 `:sources` 参考确实不读（全库仅 `plugin.rb:8` 文档串），不列为缺口。

## 2026-11-21（M7 task-86：上游 lockfile 套件第三次复采）

### 采集

- 命令：`CELERITE_SKIP_TEST_DEPS=1 bash script/upstream-specs`（`C:\msys64\usr\bin\bash.exe`；`TMPDIR=/c/temp`；PATH 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;`；基线 HEAD `710e06e`；先 `crystal build src/cli.cr -o bin/celerite.exe`，EXIT 0）。
- 墙上时间 **326 s**，rspec `duration=320.7532621`，seed `39771`，退出码 1。
- 产物：`.upstream-specs/upstream-lockfile-v4.0.24-20261121T041939Z.md`（17799 B）、`.upstream-specs/rspec-output.json`（377781 B，mtime 2026-11-21 12:25:04）。
- `summary`：`example_count=64`、`failure_count=53`、`pending_count=0`、`errors_outside_of_examples_count=0` ⇒ **11 passed**。

### 分桶（脚本规则重算，`script/upstream-specs:194-235`）

| 桶 | 数量 |
|---|---|
| `env:artifice-unreachable` | 38 |
| `env:low-il-shm` | 9 |
| `fixture:fetch-failed` | 6 |
| `env:network-policy` | 0 |
| `env:test-deps-skipped` | 0 |
| `fixture:missing-gem-files` | 0 |
| `product:candidates` | 0 |

### 与 task-66 对比

task-66：64 / 53 / 10 passed，artifice 38、low-il 9、fetch 6、product 0。本轮：64 / 53 / 11 passed，分桶完全相同。

- 逐 example 按 id 求差：**`CHANGES=0`** —— 没有任何用例 fail→pass 或 pass→fail；分桶内 id 集合逐桶相同（脚本断言 `IDENTICAL_BUCKETS=true`）。
- 因此 task-19（canonical `file://`）、task-41/65（default gem 判据）、task-58（lock 选项）、task-63（binstubs 模板）、task-64（platform 变体保留）、task-67（check 重解析）、task-84（`cache_all`）、task-85（gemrc 代理）**均未改变该套件的任何用例结果**。这与套件性质一致：它驱动 `bundler/tmp/...` 下的上游夹具与 `gem.repo2`/`gem.repo4` 这类伪造源，命中环境护栏（artifice / low-IL）而非我们改动的路径。

### 6 条 `fixture:fetch-failed` 的逐条定性

| example | 失败原文首行 | 定性 |
|---|---|---|
| `[1:2]`、`[1:3]`、`[1:5]` | `Could not verify the SSL certificate for https://rubygems.org/.`（随后 `Fetching bundler 1.8.2`） | **环境**：锁文件 `BUNDLED WITH 1.8.2` 时按 task-57 语义去装 `bundler 1.8.2`，沙箱无 CA。非产品。 |
| `[1:51]`、`[1:56:1:1]`、`[1:57:1:1]` | `expected: "GEM … specs:\n    myrack (0.9.1)\n    myrack_middleware (1.0)…"`，`got:` 少 `myrack (0.9.1)` | **产品候选（非新增）**：`missing dependent specs auto-heals` 族要求锁里保留未解析出的依赖行，我方只写解析结果。task-66 时同样存在，本轮状态未变。 |
| 分桶失真 | — | 这三条命中 `fixture:fetch-failed` 仅因记录文本含 `Fetching source index …`；`script/upstream-specs` 把「文本含 `Fetching `」一律归入夹具桶，对这类锁正文断言有系统性误分。**未改脚本**（本轮 docs-only）。 |

### 结论

- 基线仍是 **64 examples / 53 failures / 11 passed**，与 task-66 逐条一致；本轮 8 项产品改动对上游 lockfile 套件零影响。
- 真正的产品候选仍只有 `missing dependent specs auto-heals` 一族（3 条），被分桶规则掩藏在 `fixture:fetch-failed` 里；若要推进 L161，应先修分桶（把「含 `Fetching `」限定为命令失败而非任意文本），再单独处理该族。
- 2.7.2 upstream profile 无 checkout，不可执行（沿用既有说明，本轮未尝试）。

## 2026-11-21（M7 task-87：install/update/add 刷新 `vendor/cache`）

### oracle（4.0.24 与 2.7.2 同形，工程内 `vendor/cache` 已存在）

| 场景 | 参考 | 修前我方 |
| --- | --- | --- |
| 首次 `install` | `Updating files in vendor/cache` → `  * json_pure-2.8.1.gem` → `Bundle complete! …`，缓存出现该包 | 只打标题行，无复制 |
| 删掉缓存包后 `install` | 恢复该包并再打 `  * …` 行 | 包仍缺失，少一行 |
| 缓存包已存在 | 再次复制并打 `  * …`（参考无条件 `cp`） | 无复制、无行 |
| `vendor/cache` 不存在 | 完全跳过（不建目录、不打标题） | 同（已正确） |
| `install --no-cache` | 跳过 | 同 |
| `BUNDLE_FROZEN=true install` | 跳过 | 同 |

参考链路：`cli/install.rb:52-53` `Bundler.load.cache(nil, local) if Bundler.app_cache.exist? && !options["no-cache"] && !Bundler.frozen_bundle?` → `runtime.rb:108-146` `Runtime#cache`（打标题、逐 spec 走 `source.cache`）→ `source/rubygems.rb:233-242`（`  * <basename>` 后 `cp`）。同构调用点 `cli/update.rb:82`、`cli/add.rb:26-30`。

### 实现

`src/celerite/cli/commands_install.cr` 新增 `app_cache_label` / `app_cache_path` / `cache_path_sources` / `refresh_app_cache(stdout, definition, install_root, entries)` / `refresh_app_cache?`；`install` 在 `Bundle complete!` 之前、`update` 在 `clean_after_install` 之前、`add` 在 `install` 返回后按同一助手刷新。`cache` 命令的既有复制循环未改（task-84 行为保持不变），`cache_path_sources` 复刻 `Source::Path#cache` 的 `cache_all` 分支供两处共用。`--no-cache`、frozen、目录不存在三种情况按参考跳过。

### 装具

`script/differential` 新增 `file-exists` 断言原语（与 `file-absent` 对称）：每行一个工程相对路径，要求两侧都存在；`file-contains` 无法断二进制包，项目树比对只报缺失/多余而不保证指定文件存活。

### 夹具与证据

- `fixtures/differential/install-refreshes-app-cache/`（`extra/vendor/cache/keep.txt` 保证目录存在，`command` = `install`，`file-exists` = `vendor/cache/json_pure-2.8.1.gem`）：4.0.24 与 2.7.2 PASS，stdout 逐字包含 `  * json_pure-2.8.1.gem` 且位于 `Bundle complete!` 之前。
- `fixtures/differential/install-no-cache-skips-refresh/`（`command` = `install --no-cache`，`file-absent` 同一路径）：双 profile PASS，仅作护栏、无区分力。
- 回归：`cache-path-env`、`cache-all-path`（2.7.2 按既有 `deferred-2.7.2` 跳过）、`install-fresh`、`install-check` 双 profile 全绿；spec `m7_install_app_cache_spec.cr` 3 例（刷新与顺序、`--no-cache` 跳过、frozen 跳过）与 `m7_cache_path_spec`/`m7_cache_all_path_spec`/`m7_local_install_step_spec`/`m7_install_ruby_compat_spec` 联跑 17 例 0 失败。
- 负对照 `C:/temp/celerite-pre87` @ `47282d5`（`install-refreshes-app-cache`）：stdout 少 `  * json_pure-2.8.1.gem`、项目树 `Only in SANDBOX/project/vendor/cache: json_pure-2.8.1.gem`、`file-exists violated`；`install-no-cache-skips-refresh` 在旧二进制上同样 PASS（纯护栏）。

### 已声明差异

- `Source::Git#cache` 未实现（本机 msys `0xC0000022` 阻塞 git 端到端），git 源在 install 期是否复制未取证。
- `cache_all` 的工程外 path 源复制在 install 期复用同一助手，但未单独取 oracle（task-84 只在 `cache` 命令上取证）。
- `package` 共用 `run_cache`/`install`，未单独取 oracle。

## 2026-11-21（M7 task-88：首次 install 复制工程外 path 源、`BUNDLE_PATH` 绝对路径原样渲染）

### oracle（4.0.24；`file://` 索引，双侧隔离 HOME/BUNDLE_PATH/BUNDLE_APP_CONFIG）

| 场景 | 参考 | 我方（修前） | 修后 |
|---|---|---|---|
| 首次 `install` + `gem "pgem", path: "../pgem"`（工程外，`vendor/cache` 预建，无锁） | 退出 0，`vendor/cache/pgem/{pgem.gemspec,lib/pgem.rb,.bundlecache}` | 退出 0，`vendor/cache` 为空 | 与参考逐字一致 |
| `BUNDLE_PATH` 绝对反斜杠（工程上级） | `Bundled gems are installed into `C:\Users\…\bundle`` | ``C:/Users/…/bundle`` | 保持配置原样 |
| `BUNDLE_PATH` 绝对正斜杠 | 原样 | 原样 | 一致 |
| `BUNDLE_PATH=./bundle` | ``./bundle`` | 一致 | 一致 |
| `BUNDLE_PATH=`（空串） | ``Bundled gems are installed into `./.`` | 打印 `bundle info` 提示 | 未对齐（见已声明差异） |

参考链路：`runtime.rb:131-142` 遍历 `definition.specs`（不读锁）→ `source/path.rb:84-96`；`settings.rb:253-285` 的 `base_path_relative_to_pwd` 只在相对路径以 `..` 开头时保留配置原样，否则补 `./`；`settings.rb:88` 只在 4.x 打开 `BUNDLE_CACHE_ALL`。

### 实现
- `src/celerite/cli/commands_install.cr`：`cache_path_sources` 不再要求锁存在，改用调用方传入的锁数据；`refresh_app_cache` 的 `lockfile` 参数可选；install 传 `resolution.generated_lockfile`（写盘前即可用），update 传同一对象，add 传 `Definition#lockfile`（若有）。`run_cache` 的既有循环不动。
- `src/celerite/resolution.cr`：`InstallPaths.base_path_relative_to_pwd` 重写为 `settings.rb:253-285` 的语义（绝对配置原样、相对补 `./`、`..` 分支保留原样、分隔符统一为 `/` 后比较）。
- `src/celerite/config.cr`：移除 `BUNDLE_CACHE_ALL => true` 的共享默认值（4.x 默认开、2.7.2 默认关，由消费方按 profile 决定）。

### 装具与夹具
- 夹具 `fixtures/differential/install-path-source-app-cache-first/`：`sibling/pgem/*`（task-84 约定）+ `extra/vendor/cache/keep.txt`，`file-exists` 断言 `vendor/cache/pgem/lib/pgem.rb` 与 `.bundlecache`；2.7.2 用 `deferred-2.7.2` 声明（该 profile 两侧都不复制，断言无法成立）。
- 绝对 `BUNDLE_PATH` 无法做差分夹具：`script/differential` 只替换索引占位符，没有 `@SANDBOX@`，沙箱绝对路径无法写进 `env` 文件；改由 `spec/m7_install_app_cache_spec.cr` 运行时构造。

### 反假绿
- `C:/temp/celerite-pre88`（`8b6bae7`）：`FAIL install-path-source-app-cache-first`，`Only in SANDBOX/project/vendor/cache: pgem`、两条 `file-exists violated (… ) ref_exists=yes cel_exists=no`；旧二进制的绝对路径渲染为 `C:/…`（spec 覆盖）。

### 已声明差异
- `BUNDLE_PATH=`（空串）：参考渲染 `./.`，我方把空值当作未设置（`Config` 丢弃空值），打印 `bundle info` 提示；未修。
- `Source::Git#cache` 仍未实现（msys `0xC0000022` 阻断 git 端到端）；`package` 与 `cache` 共用路径，未单独取 oracle。

## 2026-11-21（M7 task-89：`install --standalone` 对非 GEM 源与 `require_paths` 的渲染）

参考 `installer/standalone.rb:30-40` 对每个 spec（bundler 自身除外，PATH/GIT 也在内）按 `spec.require_paths` 逐条写 `$:.unshift`，路径来自 `:54-61` 的 `gem_path`：`File.join(spec.full_gem_path, path)`，且 PATH 源的声明路径非绝对时再经 `SharedHelpers.relative_path_to(full, from: Bundler.root.join(bundler_path))`。我方旧实现（`src/celerite/cli/commands_install.cr` 的 `render_standalone_setup`）跳过非 GEM 行并把需求路径写死成 `lib`，于是 `path:` 源在被 `require` 时报 `LoadError: cannot load such file -- pgem`。

### oracle（参考 4.0.24，逐字节；`--standalone` 写在项目内）

| 形态 | setup.rb 字节 | 非 GEM 行 |
|---|---|---|
| 纯 GEM（`json_pure 2.6.0`） | 1021 | 无（只有 `#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/json_pure-2.6.0/lib`） |
| 工程外 path 源（`path: "../../pgem"`） | 1085 | `#{__dir__}/../../../../pgem/lib`，`require 'pgem'` → `REQUIRE=OK` |
| 工程内 path 源（`path: "vendor/pgem"`） | 1086 | `#{__dir__}/../../vendor/pgem/lib` |
| `--standalone=development`（path 源只在 dev 组） | 975 | 仅 pgem 行（json_pure 被排除） |
| 夹具同形（`project/` + 同级 `pgem/`，未设 `BUNDLE_PATH`） | 两侧均 1082 | 两侧均 `#{__dir__}/../../../pgem/lib`，逐字节一致 |

`require_paths` 取真实 gemspec（桥 `op_load_installed_spec` 新增 `require_paths` 字段），缺省回退 `["lib"]`；PATH 源的 `full_gem_path` 由 `source_declared`（锁里声明的原始路径）相对 Gemfile 目录展开。

### 代码锚点

- `assets/bridge/server.rb`：`op_load_installed_spec` 增 `require_paths`（注释指 `installer/standalone.rb:30-40`）。
- `src/celerite/resolution.cr`：`ResolvedSpec#source_declared`（PATH/GIT 取锁内 `remote` 原文）；`materialize_locked` 赋值。
- `src/celerite/cli/commands_install.cr`：`render_standalone_setup`（`next if name == "bundler"`、按 `require_paths` 逐条、PATH 用相对 bundler 目录的路径）与 `standalone_gem_root`/`standalone_require_paths`/`standalone_relative_path`。

### 夹具与反假绿

`fixtures/differential/standalone-path-source/`（`sibling/pgem/`、`command` = `install --standalone`、`file-contains` 于 `../bundle/bundler/setup.rb` 命中 `pgem/lib`）4.0.24 与 2.7.2 均 PASS；同轮 `install-standalone`、`install-fresh` 绿。负对照 `C:/temp/celerite-pre89`@`d042e54`：`FAIL standalone-path-source`，`file-contains differs (../bundle/bundler/setup.rb): needle=pgem/lib`。

### 已声明差异

同一驱动器上「声明路径为绝对」的 PATH 源，参考把绝对路径原样写进 `$:.unshift`，我方统一相对化（功能等价，`require` 均可）；跨盘时双方都只能写绝对路径。`--standalone` 与 `BUNDLE_PATH` 同时出现时 setup.rb 落在 `$BUNDLE_PATH/bundler/`（夹具的 `../bundle/...` 即此），未在参考侧单独取 oracle。

## 2026-11-21（M7 task-90：`update --group <无成员组>` 不再多余重解析）

参考 `cli/update.rb:49-52` 只用组把显式 gem 列表加宽：

```ruby
if groups.any?
  deps = Bundler.definition.dependencies.select {|d| (d.groups & groups).any? }
  gems.concat(deps.map(&:name))
end
```

组不存在时 `gems` 仍空，随后 `Bundler.definition(gems: [], sources: [], …)`（`:54-56`）不解锁任何东西——既不取索引也不重解析，锁文件原样保留，只打印收尾行。我方 `src/celerite/cli/commands_surface.cr` 在组合并后仍把空数组当作解锁集交给 `Resolution`，于是多了 `Fetching source index` 与 `Resolving dependencies...`。

### oracle（参考 4.0.24，逐 case 记录锁文件 sha1 前后值）

| case | 参考 stdout | 锁文件 | 我方（修前） |
|---|---|---|---|
| `update --group nope` | 仅 `Bundle updated!` | 未变 | 多 `Fetching source index …` + `Resolving dependencies...` |
| `update --group dev` | `Fetching source index …` / `Resolving dependencies...` ×2 / `Bundle updated!`，stderr `Bundler attempted to update thor but its version stayed the same` | 未变 | 一致 |
| `update --group dev,test` | 仅 `Bundle updated!` | 未变 | 一致 |
| `update --source nope` | `Fetching …` / `Resolving …` / `Bundle updated!` | 未变 | 一致 |
| 裸 `update` | `Fetching …` / `Resolving …` / `Bundle updated!` + `[DEPRECATED] Pass --all …` | 未变 | 既有行为 |

注：`--group dev,test` 在参考里同样落到空集合（逗号形式不匹配成员的符号组），与我方一致，故未改。

### 实现

`src/celerite/cli/commands_surface.cr`（组合并之后、`unlock` 计算之前）新增零解锁集短路：`!full_update && gems.empty? && sources.empty? && !ruby_flag && !update_bundler` 时打印 `Bundle updated!` 并返回 0，不建 `Resolution`、不取索引、不写锁。未新写落盘逻辑（该路径本就不写锁）。

### 夹具与反假绿

- `fixtures/differential/update-group-missing/`（`command` = `install --quiet` + `update --group nope`，`file-equals Gemfile.lock`）4.0.24 PASS。
- `fixtures/differential/update-group-present/`（`install --quiet` + `update --group dev`）4.0.24 PASS。
- 两夹具均带 `deferred-2.7.2`：锁文件 `BUNDLED WITH 4.0.24`，2.7.2 profile 下参考的 self-manager 会去 rubygems.org 安装 bundler 4.0.24 而阻塞（沙箱无网），所测语义与 profile 无关。
- 负对照 `C:/temp/celerite-pre90`@`0f6ff34`：`FAIL update-group-missing`，`> Fetching source index …` / `> Resolving dependencies...`（旧二进制仍重解析），`update-group-present` PASS（纯护栏，无区分力）。

### 已声明差异

`update` 在缺装状态下的补齐安装行（缺少 bundle 时参考会打印 `Fetching <gem>` / `Installing <gem>`）本轮未对齐，也未纳入夹具——夹具一律先 `install --quiet` 以固定「已装」前置。`--group` 的逗号形式与单个形式的集合语义差异沿用参考行为，未单独取 oracle。

## 2026-11-21 分桶规则修正（task-91，离线重算未重跑）

`script/upstream-specs` 的旧分桶规则把「失败记录文本里出现 `Fetching `」一律归入 `fixture:fetch-failed`，于是三个锁断言用例（`missing dependent specs auto-heals` 族）被误分：它们的 `got:` 段里含被测命令打印的 `Fetching source index …`，被当成夹具抓取失败，掩盖了真实的产品候选。

task-91 改为按**异常类**判定，规则表写在 `script/upstream-specs-buckets.rb`（harness 与离线重算共用同一函数）：

| # | 条件 | 桶 |
|--:|---|---|
| 1 | 文本含 `Could not reach host` | `env:artifice-unreachable` |
| 2 | 文本含 `HTTP 403` / `403 Forbidden` | `env:network-policy` |
| 3 | 文本含 `0xC0000022` / `NtCreateDirectoryObject` | `env:low-il-shm` |
| 4 | 文本含 `sinatra/base` | `env:test-deps-skipped` |
| 5 | 异常类为 `RSpec::Expectations::ExpectationNotMetError` | `product:candidates` |
| 5b | message 同时含 `expected:` 与 `got:` | `product:candidates` |
| 6 | 文本含 `Errno::ENOENT` / `does not exist!` / `rb_sysopen` | `fixture:missing-gem-files` |
| 7 | 文本含 `Fetching ` | `fixture:fetch-failed` |
| 8 | 其他 | `product:candidates` |

环境特征（1–4）先匹配，故原 38 artifice / 9 low-il 两桶不受影响；断言失败一律产品候选，即使正文含 `Fetching `。

### 重算（task-86 产物，未重跑）

输入：`.upstream-specs/rspec-output.json`（377781 B，mtime 2026-11-21 12:25:04，`failure_count 53`）。重算脚本：`.tmp-scratch/task91/rebucket.rb`（`require_relative` 同一个规则模块）。

| bucket | task-86 旧规则 | task-91 新规则 |
|---|--:|--:|
| env:artifice-unreachable | 38 | 38 |
| env:low-il-shm | 9 | 9 |
| fixture:fetch-failed | 6 | 3 |
| product:candidates | 0 | 3 |

总例数与失败数不变（64 examples / 53 failures），移动项 3 条，全部为断言类：
- `the lockfile format automatically fixes the lockfile when it's missing deps and the full index is in use`
  - 位置：`./spec/lock/lockfile_spec.rb:1933`，异常类：`RSpec::Expectations::ExpectationNotMetError`
  - `exception.message` 前 200 字符：

    ```text


    Commands:
    $ C:/Users/ShiningRay/projects/ShiningRay/celerite/bin/celerite install
    Fetching source index from file:///C:/Users/ShiningRay/projects/ShiningRay/celerite/.upstream-specs/v4.0.24/bundler/
    ```

- `the lockfile format with just specific platform behaves like a lockfile missing dependent specs auto-heals`
  - 位置：`./spec/lock/lockfile_spec.rb:2215`，异常类：`RSpec::Expectations::ExpectationNotMetError`
  - `exception.message` 前 200 字符：

    ```text


    Commands:
    $ C:/Users/ShiningRay/projects/ShiningRay/celerite/bin/celerite install
    Fetching gem metadata from https://gem.repo4/.
    Resolving dependencies...
    Resolving dependencies...
    Installing minite
    ```

- `the lockfile format with both ruby and specific platform behaves like a lockfile missing dependent specs auto-heals`
  - 位置：`./spec/lock/lockfile_spec.rb:2215`，异常类：`RSpec::Expectations::ExpectationNotMetError`
  - `exception.message` 前 200 字符：

    ```text


    Commands:
    $ C:/Users/ShiningRay/projects/ShiningRay/celerite/bin/celerite install
    Fetching gem metadata from https://gem.repo4/.
    Resolving dependencies...
    Resolving dependencies...
    Installing minite
    ```

断言类 product 候选数：3

### 结论与已声明差异

- 上游锁文件套件当前有 **3 条断言型产品候选**（此前记为 0，task-86 的结论「product 候选 0」**已被 task-91 更正**）；env 两桶数字未变，历史总数未变。
- 未重跑套件（本轮只改判定规则），故三条候选的「当前是否仍失败」沿用 task-86 采集结果。
- 规则 5b（`expected:`+`got:`）为兜底：若上游 rspec 换了异常类，仍能落到产品桶；本轮 53 条中无仅靠 5b 命中的用例。
- 判定仍基于文本特征而非结构化断言 diff，`exception.message` 之外的比较细节不外泄，故默认「断言失败即产品候选」，不做修复建议分类。
