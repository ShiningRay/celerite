<!-- 治理说明（2026-11-22）：本文件原先同时承载「现状报告」与「按日追加证据日志」，共 7410 行。治理后：
     正文（原行 1-401）逐字快照到 docs/compat-evidence/2026-11-11.md，按日证据日志（原行 402-7410）拆分为 docs/compat-evidence/YYYY-MM-DD.md，
     本文件只保留当前状态与索引。正文结论未改写；仅将被后续迭代取代的指标就地标注取代关系。 -->

# Celerite compatibility report — current status (updated 2026-11-23)

本文件是 **当前状态报告**：现在支持到什么程度、哪些明确不支持、已声明的差异、怎么复现。
逐条原始证据（oracle、参考锚点、实现位置、spec/差分计数、日志路径、历史结论）已按日移入
[docs/compat-evidence/](compat-evidence/README.md)，本文件不再追加流水。

## Current metrics (last recorded runs, not rerun by this documentation change)

| 家族 | 命令 | 最近记录 | 采集日期 | 日志 / 出处 |
| --- | --- | --- | --- | --- |
| 差分 4.0.24（全量） | `script/differential` | **218 passed, 14 failed, 3 skipped** | 2026-11-17 | `.tmp-scratch/differential-full-71.log` 为上一档 210/14/2；本条见 [compat-evidence/2026-11-17.md](compat-evidence/2026-11-17.md) |
| 差分 2.7.2（全量） | `BUNDLER_REF_VERSION=2.7.2 script/differential` | **133 fixtures: 126 passed, 6 failed, 1 skipped**（`add-group` deferred） | 2026-11-13 | `C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log`；此后只做定向复跑，**未在 424 夹具上重跑全量** |
| 差分夹具总数 | — | 454 个目录（全量分母 = 454 − 该 profile 的 deferred 数） | 2026-11-23 | `fixtures/differential/*/command`（`Get-ChildItem fixtures\differential -Directory` 实测；上一档 443 见 2026-11-22） |
| 全量 `crystal spec` | `crystal spec` | **1003 examples, 0 failures, 0 errors, 0 pending**（`Finished in 15:40 minutes`，EXIT 0；结果绑定 `a9b08c4`，隔离 `TMPDIR`/`HOME` 指向工作区内）。演进：`b99bf12` 编译期失败（`spec/m7_verbose_echo_spec.cr:18`，task-127 `ae1248c` 修）→ `40ad324` 991/86/10 → `eed51d7` 999/5/11（task-128/129 修掉两条 spec 间环境泄漏链，86→5）→ `d9884ff` 1001/0/0/0（task-132/133/134 清掉剩余 5 条）→ `a9b08c4` 1003/0/0/0（task-135 新增 2 例）。前提：不满足「`TMPDIR`/`HOME` 指向工作区内」时套件在编译阶段即失败（见 [roadmap-evidence/M7-suite.md](roadmap-evidence/M7-suite.md)）。此前 **656 examples, 0 failures, 4 errors**（2026-11-18/19）已取代，原记录见 [compat-evidence/2026-11-18.md](compat-evidence/2026-11-18.md) | 2026-11-22（task-132/133/134/135 收尾） | [compat-evidence/2026-11-22.md](compat-evidence/2026-11-22.md)、[roadmap-evidence/M7-suite.md](roadmap-evidence/M7-suite.md) |
| 上游 lockfile 套件 | `script/upstream-specs`（`CELERITE_SKIP_TEST_DEPS=1`） | **64 examples, 47 failures**（17 passed；分桶 artifice-unreachable 41、fixture:fetch-failed 3、product:candidates 3；real-drive 69 次、`harness verdict: ok`）。取代 2026-11-22 的 64/48——那 1 条差是 `lockfile_spec.rb:586`（git branch requirement）在 flaky 的 msys Low-IL 上转绿，非产品修复；`script/upstream-specs` 现已自证真驱动并对「环境不可用/未驱动」分别以 69/70 退出（见 [roadmap-evidence/M7-8-upstream-specs.md](roadmap-evidence/M7-8-upstream-specs.md)） | 2026-11-23（task-146/148） | [roadmap-evidence/M7-8-upstream-specs.md](roadmap-evidence/M7-8-upstream-specs.md) |

差分 4.0.24 的历史演进（同一文件里仍并存，读旧条目时注意口径）：115:101/14/0 → 130:123/7/0 → 133:126/7/0 → 135:135/0/1 → 160:160/16/2 → 210:210/14/2 → **218/14/3**。
其中 2026-11-14 的 `135 passed, 0 failed` 与 2026-11-15 装具 `git-init` 修复期的 `77 passed, 59 failed` 属装具口径轮次，不作产品结论（原证据见 [compat-evidence/2026-11-14.md](compat-evidence/2026-11-14.md)、[compat-evidence/2026-11-15.md](compat-evidence/2026-11-15.md)）。

## Scope and limits of what this report proves

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

> 治理后的补充：上表每行都标注了采集日期与出处；本文件**未重新运行**任何差分 / rspec / 全量门禁，只做搬运与现状汇总。

## Environment

| 项 | 值 |
| --- | --- |
| 报告依据的最后已知 HEAD | `c3b9a6f`（`docs(M7 task-117): 补记锁定 spec 行缺失时的重解析差异与证据`）；历史快照 HEAD=`8e91a2f` |
| Ruby 参考 | 4.0.6 x64-mingw-ucrt（另测 2.7.2 profile） |
| Crystal | 1.22.1 |
| git | 2.55.0.windows.3 (Windows x64, win32) |
| 宿主限制 | msys Low-IL 下子进程 `0xC0000022`（git 源夹具与原生扩展构建）；`make`/racc 不可用；http-index 夹具需 `CELERITE_DIFF_EXTRA_PATH='/c/Program Files/nodejs'` |

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

- **Ruby/RubyGems 约束过滤（进行中，未达 M7(1) 完整验收）**：已实现并接线（`032a531` 起，本迭代继续）`src/celerite/ruby_version.cr`/`src/celerite/ruby_runtime.cr`、`Celerite::RubyVersionMismatch`（exit 18）、bridge `ruby_environment.patchlevel` 与结构化 Gemfile `ruby` 选项（`ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`）、`ResolutionSource` 对 gem `required_ruby_version`/`required_rubygems_version` 的候选过滤（gem metadata 只按 `RUBY_VERSION` 比较，与 Bundler 4.0.24 `matches_current_ruby?` 一致；patchlevel 只在 Gemfile 目标 Ruby 校验中参与）、lockfile Ruby 复用比较 `RubyVersion` diff、`ruby_update` 写入正确 patchlevel。CLI runtime 校验（best-effort：bridge 不可用时跳过，**不视为通过**）已接入 check/install/show/info/fund/exec/cache/clean/doctor/pristine/outdated/update/licenses/console 等命令；`platform` 在 bridge 可用时输出 mismatch 文案但 exit 0，bridge 不可用时输出 "Ruby version requirement not validated (bridge unavailable); cannot confirm runtime match."；`list`/`lock`/`env` 按参考探针不因 mismatch 失败。可运行证据（2026-11-11）：`spec/ruby_version_spec.cr`（10）+ `spec/m7_ruby_runtime_spec.cr`（9，含 version/engine/engine_version/patchlevel mismatch 文案与 exit 18、matching version/patchlevel 与 matching engine/engine_version 正例、bridge 结构化 Gemfile `patchlevel: "1"`/`engine: "jruby"`/`engine_version` 传递）+ `spec/m7_platform_spec.cr`（2，bridge 不可用时不声称满足、`--ruby` 可解析输出）+ `spec/m7_ruby_constraints_spec.cr`（10，ABI 派生、lock 复用、`RubyRuntime` 结构化 diff）+ `spec/m7_resolver_ruby_constraints_spec.cr`（8，`required_ruby_version`/`required_rubygems_version` 候选过滤、patchlevel 不参与 gem metadata、Ruby/RubyGems-only 排除报 `SolveFailure` exit 6、纯无匹配版本仍报 `GemNotFoundError` exit 7）均通过；本轮 M7 相关 spec 合计 **111 examples, 0 failures, 0 errors, 0 pending**（退出码 0，含 `spec/m7_installed_discovery_spec.cr` 20、`spec/m7_fund_spec.cr` 3、`spec/m7_gem_spec.cr` 4、`spec/m7_console_spec.cr` 1）。已新增并**实际运行**最小 differential fixtures：`fixtures/differential/ruby-version-mismatch`（`check`，exit 18 + Bundler mismatch 文案）、`fixtures/differential/platform-ruby-mismatch`（`platform`，exit 0 + mismatch 文案）、`fixtures/differential/list-multi-group`（`list --only-group default test`，exit 0，多组空格列表）与 PATH 源的 `check-path`/`list-path`（exit 0）、`ruby-target-match`/`ruby-patchlevel-match`/`ruby-engine-match`（`install` + `check`，exit 0，Gemfile 目标 Ruby 正例）、`ruby-patchlevel-match-list`（`install` + `list`，exit 0，Gemfile patchlevel 与 lock `RUBY VERSION` 不一致时 `list` 重解通知）、`check-missing-ruby-nolock`（`check`，Gemfile 声明 `ruby` 但 lock 无 `RUBY VERSION` 且依赖未安装，exit 1 + `Resolving dependencies...` 与 missing 文案）与 `list-missing-ruby-nolock`（同场景 `list`，exit 1 + `Resolving dependencies...` 与 missing 文案）、`no-matching-version`（`lock --print`，无可用版本，exit 7）与 `platform-variant-fail`（`lock --add-platform x86_64-linux`，exit 7）均实跑 PASS；`ruby-metadata-fail`（PATH gem `required_ruby_version >= 99.0`）已修复为与参考一致的语义：仅因 Ruby/RubyGems 元数据被排除时报告 `SolveFailure`（exit 6 + 同形解释），而纯无匹配版本仍报 `GemNotFound`（exit 7）；`deferred-4.0.24` 已移除；`rubygems-metadata-fail`（PATH gem `required_rubygems_version >= 99.0`）同样报 SolveFailure exit 6，与参考一致。`rubygems-metadata-match`（PATH gem `required_rubygems_version = ">= 0"`，exit 0）与 `ruby-metadata-match`（PATH gem `required_ruby_version = ">= 1.0"`，`lock --print`，exit 0，satisfied required_ruby_version 正例）为满足正例对称通过（4.0.24/2.7.2）；lockfile 生成现对声明的 rubygems/GEM 源在无 GEM spec 时仍输出空 `GEM` section（PATH-only 解析 parity）。定向子集 28 passed / 0 failed / 0 skipped（exit 0，含 GIT 安装态 `git-installed-discovery`、PATH 源 funding `fund-path`、Gemfile engine/engine_version/patchlevel 变体与目标 Ruby 正例 `ruby-target-match`/`ruby-patchlevel-match`/`ruby-engine-match`、`ruby-patchlevel-match-list`、Gemfile 有 ruby 但 lock 无 `RUBY VERSION` 且依赖未安装时的 `check`/`list` 通知 `check-missing-ruby-nolock`/`list-missing-ruby-nolock`、RubyGems 元数据 SolveFailure、install-then-check 与 `show/info` 安装态）；4.0.24 全量 differential 为 **101 passed / 14 failed / 0 skipped**（2026-11-11 快照，已被后续迭代取代；当前指标见本文件「Current metrics」表），14 项失败分类见 [compat-evidence/2026-11-11.md](compat-evidence/2026-11-11.md) 的「Local verification run (2026-11-11, task-2)」节。**未验证/未达验收**：Gemfile 目标 Ruby/engine/patchlevel 正例与 mismatch 反例已覆盖，ABI/平台变体正例；Gemfile 声明 `ruby` 但 lock 无 `RUBY VERSION` 且依赖未安装时 `check`/`list` 的 `Resolving dependencies...` 通知已由 `check-missing-ruby-nolock`/`list-missing-ruby-nolock`（4.0.24/2.7.2）钉住。手工 harness-style 取证（4.0.24/2.7.2，依赖已满足、lock 无 `RUBY VERSION`）显示 reference `check` 与 `list` 均打印 `Resolving dependencies...`；`Commands.list` 已对齐为 `:missing_from_lock` 时同样打印（bridge 可用路径），但该已满足场景尚未 differential-fixture 化：harness-like 手工探针（隔离 env，预置 `BUNDLE_PATH/ruby/4.0.0/{gems,specifications}/json_pure-2.8.1`，Gemfile `ruby "4.0.6"`，lock 有 specs/PLATFORMS/DEPENDENCIES/BUNDLED WITH 无 `RUBY VERSION`，`CELERITE_REFERENCE_BUNDLER_LIB`/`CELERITE_PROFILE_BUNDLER_VERSION` 指向 4.0.24，shim-built celerite）显示 reference 4.0.24 与 celerite `check`/`list` 均输出 `Resolving dependencies...` 后 EXIT 0（2026-11-11，probe base `C:\temp\nolock-sat-harnesslike-eZPd5c`）；2.7.2 reference 同形。**阻塞**：`script/differential` 无命令前预填充 `BUNDLE_PATH` 且保留 lock 无 `RUBY VERSION` 的 primitive（`extra/` 仅进 project，`install` 通常会写回 lock 并补 `RUBY VERSION`），暂无法固化为 fixture；bridge 不可用时通知为 fail-safe 可能省略；`show`/`info` 在 patchlevel-unlock 场景与参考一致均无通知（手工对照），其他重解通知场景未验证；bridge 缺失场景仅有纯逻辑 spec，无 CLI 集成证据；2.7.2 profile 定向子集 28/28 已跑，全量未跑。
- **本机 codegen/OpenSSL 阻塞与本地 shim（2026-11-11，环境问题非项目缺陷）**：Crystal 1.22.1 标准库 `openssl/digest.cr:77` 绑定 OpenSSL 1.1 的 `EVP_MD_size`，而本机 MSYS2 ucrt64 为 OpenSSL 3.6.5，`libcrypto.dll.a`/`libcrypto.a` 仅导出 `EVP_MD_get_size`（`nm` 已验证无 `EVP_MD_size`），故 stock `crystal build src/cli.cr` 报 `undefined reference to 'EVP_MD_size'`。本轮用**仓库外临时 C shim**（`#undef EVP_MD_size` + `int EVP_MD_size(const EVP_MD *md){ return EVP_MD_get_size(md); }`）配合 `--link-flags "<shim.o>"` 成功完成本地 codegen（EXIT 0），并据此重建 `bin/celerite.exe`（`--version` 0.1.0）；**shim 与二进制均不入库**（`bin/` 被 gitignore），stock 构建仍失败。CLI 集成 spec 与 differential 的计数/分类见 [compat-evidence/2026-11-11.md](compat-evidence/2026-11-11.md)。
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
**64 examples, 53 failures** (11 passed; 2026-11-22 task-114 采集), still not a passing gate. It is retained as a failure
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

## Declared deviations referenced from source comments

源码注释（`src/`）与 roadmap 中写「declared deviation / declared difference, see compat-report」的位置，其完整论证在治理后位于 compat-evidence；逐条指针如下（本节只做指针，不复制证据）：

- `--path` / `--without` / `--with` 在 4.0.24 是「已移除」报错（exit 15）、2.7.x 仅告警（exit 10），本实现实现其语义并接受（三态差异）：[compat-evidence/2026-11-15.md](compat-evidence/2026-11-15.md)「2026-11-15 M7(2)/L157：install 家族未知开关拒绝」。
- frozen 模式下缺平台/缺 path-git gemspec 的拒绝原因仍开放（已实现 source/依赖/CHECKSUMS 三类原因）：[compat-evidence/2026-11-15.md](compat-evidence/2026-11-15.md)「2026-11-15 M7(1)：frozen 模式下 ruby 解锁拒绝」。
- Thor `command_help` 的「本命令 option 表」未复刻（只渲染 usage + class options + 描述）：[compat-evidence/2026-11-16.md](compat-evidence/2026-11-16.md)「2026-11-16（M7(2)：命令面的 unknown-switch 拒绝与只读命令的本地/远程解析分工）」、[compat-evidence/2026-11-18.md](compat-evidence/2026-11-18.md)「2026-11-18（M7(3)/M7(2)：`help` / `--help` 渲染 vendored manpage）」。
- 2.7.2 `viz` 缺 `ruby-graphviz` 时参考多打印一行 `#<Gem::MissingSpecError: …among N total gem(s)…GEM_PATH=…>`，宿主 gem 计数与路径内嵌、不可逐字复现（夹具记为 documented deferral）：[compat-evidence/2026-11-18.md](compat-evidence/2026-11-18.md)「2026-11-18（M7(2)/M7(3)：命令名解析 / `tree` / `[REMOVED]`）」。
- `bundle gem` 的 `--edit` / `--bundle` 属交互/网络副作用，显式报「不支持 + 参考行为 + exit 1」，不静默忽略：[compat-evidence/2026-11-19.md](compat-evidence/2026-11-19.md)「2026-11-19（M7(3) task-27：`bundle gem` 选项面与 `--help` 对齐）」。
- `add --glob` 的通配在宿主 `ruby.exe` argv 层（Ruby cmdglob）展开，不在 Bundler；celerite 不模拟：[compat-evidence/2026-11-20.md](compat-evidence/2026-11-20.md)「2026-11-20（M7(2) task-59：`bundle add` 位置参数解析与 `install --target-rbconfig`）」。

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

## Evidence index

- 兼容性断言账本（按子项组织的结论：现在有哪些断言成立、凭什么成立、怎么重跑）：[docs/compat-claims/README.md](compat-claims/README.md)。
- 逐日证据日志（过程档案）：[docs/compat-evidence/README.md](compat-evidence/README.md)（含 12 个文件清单与 211 个节的标题索引 + 锚点行）。
- 治理前的报告头部（原行 1-401，含 2026-11-11 task-2 本地校验、2026-11-15 env/console/gem 模板子节、97 夹具的 M0–M6 归类清单、当时的环境与免责声明）：[docs/compat-evidence/2026-11-11.md](compat-evidence/2026-11-11.md)。
- 夹具证据转储（生成的逐例对比）：`docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`、`cli-4.0.24.md`、`cli-2.7.2.md`、`upstream-lockfile-v4.0.24.md`。
- 主题矩阵（手写）：`docs/compat-matrix/`（lockfile-sections.md、gemfile-dsl.md、cli-commands.md、config-keys.md）。
- 基准与 profile：`docs/benchmarks/`。
- 引用上文某个历史节时，请引「compat-evidence 的日期文件 + 节标题」，不要引本文件的旧行号。
