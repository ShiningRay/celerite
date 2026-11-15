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
- Baselines (measured, unchanged): 4.0.24 133:126/7/0 (log C:\temp\celerite-diff-full-4.0.24-1882f53.log, 2026-11-12, HEAD=1882f53, FAIL 7 = class A racc/make, zero-regression by name vs 130:123/7/0); 2.7.2 133:126/6/1 (log C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log, 2026-11-13 00:24:35 CST, HEAD=517f69a, wrapper exit 1; FAIL 6 = class A racc/make + SKIP 1 dd-group deferral; zero-regression by name vs 130:123/6/1, 37b4287 confirmed); M7 spec subset 70/0/0/0 (ae8eafc 前次记录；本轮 2026-11-13 @4c2404a+worktree 重跑 70/0/0/0 EXIT 0, 17.91s，证据随 497e293 提交).
- Recent fixture evidence (updated): issue-satisfied 1/0/0 (582b099); B3 nolock satisfied+missing 4/0/0 (0fabf9e); env/issue stable set 3/0/0 (34a8cad/a482329 证据); M7(3) spec 8/0/0/0 (既有); post-37b4287 新 fixture issue-satisfied/check-satisfied-ruby-nolock/list-satisfied-ruby-nolock 2.7.2 全量中均 PASS (exit=0)；list-path-only-group/multi-platform-install-ruby 双 profile 定向 2/0/0 EXIT 0 + 43 例 M7 回归集双 profile 43/0/0 EXIT 0（logs C:\temp\celerite-diff-m7combos-4024.log/-272.log/-reg-4024.log/-reg-272.log；fixtures 与证据随 497e293 提交）；show-info-installed 双 profile 1/0/0 EXIT 0（logs C:\temp\celerite-diff-show-info-installed.log/-272.log，本轮新增）；M7(1)/(2) 回归集 6 fixture 双 profile 6/0/0 EXIT 0（logs C:\temp\celerite-diff-m712-regression-4024.log/-272.log，本轮新增）。
- M7(4): 94ec377/e77c6cb 审计与 redirect typing 修复为历史证据；本子项（e6f0086 WIP 收尾）将 timeout/ssl_client_cert 接线至 Downloader+HttpFetcher+调用点，redirect 超限抛 `DownloadError`（含限额/URL），proxy 环境变量改为 warn+continue、显式 config proxy/`ssl_client_key`/`legacy_index`/`full_index` 通过 `Commands.unsupported_setting_error` 在 install/update/lock/cache 快速失败。仍 GAP：proxy 路由、`mirror.<url>.fallback_timeout` 无 consumer、legacy/full index 未实现、`ssl_client_key` 未接线（仅 fast-fail）。详见本子项证据节与 `spec/m7_download_settings_spec.cr`。
- M7(6) plugin evidence (a59d50f + 10e0a52): audit found installer event post-install != reference index layout fter-install -> reference-compatible plugin index hooks silently never fire. Fix 10e0a52 aligns EVENTS + call site; spec/plugin_hooks_spec.cr before 5 examples 1 failure (pin example) -> after 5/0/0/0 EXIT 0; canary+install 8 fixtures dual profile 8/0/0 EXIT 0; plugin fixtures post-fix 6/0/0 dual profile. 6 existing plugin fixtures cover install/uninstall/source/git/malformatted; third-party plugin/custom-source/hook-exception differential vs vendored partial reference infeasible (system reference gem feasible, not constructed this round).
- config_spec round-trip (1eeaefb, docs-only): crystal spec spec/config_spec.cr -> 9 examples, 1 failures, 0 errors, 0 pending, SPEC_EXIT=1; failing example L97/L113
eloaded.all.should eq([] of String) got 6 gem.* keys. Root cause: global ~/.bundle/config 6 non-nil BUNDLE_GEM__* keys survive Config#all (@local.keys); environment-coupled, not logic error. nil-filter attempt ineffective (global keys non-nil); reverted per lead docs-only decision; ll semantics unchanged (include global keys); spec expectation unchanged.
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
- **Repro for follow-up implementation**: set BUNDLE_PROXY/BUNDLE_TIMEOUT/BUNDLE_SSL_CLIENT_CERT/BUNDLE_SSL_CLIENT_KEY/BUNDLE_MIRROR_..._FALLBACK_TIMEOUT/BUNDLE_REDIRECT and run undle install against a remote source; observe current behavior (ignored). Follow-up subitem should land real-effect or fast-fail + spec + differential affected-set regression.

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
- 已声明偏差：①回溯段是本实现真实栈（与参考帧不同）；②bundle 缓存：从 `vendor/cache` 安装时我方仍把 `.gem` 复制进 `<bundle>/cache/`，参考不复制（A/B 残留树唯一差异，下一轮处理）；③参考 `current directory:` 一行在 80 列下折行受沙箱路径长度影响，我方同样折行，故只在等长沙箱下逐字比对。
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
