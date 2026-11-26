<!-- 治理说明（2026-11-22）：本文件原先同时承载「现状报告」与「按日追加证据日志」，共 7410 行。治理后：
     正文（原行 1-401）逐字快照到 docs/compat-evidence/2026-11-11.md，按日证据日志（原行 402-7410）拆分为 docs/compat-evidence/YYYY-MM-DD.md，
     本文件只保留当前状态与索引。正文结论未改写；仅将被后续迭代取代的指标就地标注取代关系。 -->

# Celerite compatibility report — current status (updated 2026-11-26)

本文件是 **当前状态报告**：现在支持到什么程度、哪些明确不支持、已声明的差异、怎么复现。
逐条原始证据（oracle、参考锚点、实现位置、spec/差分计数、日志路径、历史结论）已按日移入
[docs/compat-evidence/](compat-evidence/README.md)，本文件不再追加流水。

## Current metrics (last recorded runs, not rerun by this documentation change)

| 家族 | 命令 | 最近记录 | 采集日期 | 日志 / 出处 |
| --- | --- | --- | --- | --- |
| 差分 4.0.24（全量） | `script/differential`（不带夹具名；`TMPDIR=/c/t/cel-d7`，`CELERITE_BIN=C:\temp\celerite-diff7\bin\celerite.exe`，不设 `BUNDLER_REF_VERSION`、不设 `CELERITE_EVAL_CACHE`） | **481 passed, 0 failed, 5 skipped**（5 条均为 `deferred-4.0.24`；基线 `05402b6`（**非 HEAD**），分母 481 = 486 个夹具目录 − 5 个 deferred） | 2026-11-24（task-245 记账，首辅在 `05402b6` 实测：`script/differential` 全量 4.0.24、EXIT 0、日志 530 行；分母 481 = 486 目录 − 5 个 `deferred-4.0.24`） | 日志（本机临时、不入库）`C:\t\full-diff-4.0.24-05402b6.txt`（44,350 B、530 行；`^PASS ` 481 / `^FAIL ` 0 / `^SKIP ` 5）；逐条证据见 [compat-evidence/2026-11-23.md](compat-evidence/2026-11-23.md) 的「2026-11-24：全量差分 4.0.24 在 05402b6 的重跑（task-245）」。**已取代（superseded）**：2026-11-24 task-215 于 `3fd7a8d` 的 **481 passed, 0 failed, 5 skipped**（分母 481 = 486 − 5；日志 `C:\temp\celerite-t215\.tmp-scratch\full-diff-4.0.24.txt`，44,350 B、531 行，EXIT 0；该轮采集时同表「差分夹具总数」行仍记 484 / 30 / 5，本轮复核为 486 / 30 / 5，以「差分夹具总数」行的 486 / 30 / 5 为准）、2026-11-23 task-188 于 `4bdc20a` 的 **468 passed, 0 failed, 5 skipped**（分母 468 = 473 − 5；日志 `C:\temp\celerite-t188\.tmp-scratch\full-diff-4.0.24.txt`，96.34 分钟，EXIT 0）与 2026-11-17 的 **218 passed, 14 failed, 3 skipped**（`.tmp-scratch/differential-full-71.log`）均保留为历史；14 条旧环境族失败仍未复现。**基线提示**：本轮采集点是 `05402b6` 而非 HEAD `c99061f`；其后 `9092151`（task-239 求值收口）、`6d790a8`（注释）、`f58c523`（task-243 批量上限，含 `assets/bridge/server.rb`）改过 `src/`（对应文档提交 `ae658bd`/`7ce5753`），需在下一轮重新门禁 |
| 差分 2.7.2（全量） | `BUNDLER_REF_VERSION=2.7.2 script/differential`（不带夹具名；`PATH` 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;`，`TMPDIR=/c/temp`，`CELERITE_BIN=C:\temp\celerite-t208\bin\celerite.exe`） | **453 passed, 1 failed, 30 skipped**（30 条均为 `deferred-2.7.2`；HEAD `302cbae`，分母 454 = 484 个夹具目录 − 30 个 deferred；唯一 FAIL：`removed-flag-path`，按真产品分歧登记、**未修**，逐条归因见证据文件） | 2026-11-24（task-208；`START=2026-11-24T00:58:20`、`END=02:24:11`，耗时 85.85 分钟，脚本 EXIT 1） | 日志（本机临时、不入库）`C:\temp\celerite-t208\.tmp-scratch\full-diff-2.7.2.txt`（52,240 B、524 行）；逐条证据见 [compat-evidence/2026-11-23.md](compat-evidence/2026-11-23.md) 的「全量差分 2.7.2 在 HEAD（302cbae）的重跑（task-208）」。**已取代（superseded）**：2026-11-23 task-191 于 `954f2d5` 的 **441 passed, 5 failed, 29 skipped**（5 条 FAIL：`clean-force`、`clean-no-lockfile`、`clean-unused`、`install-clean-after-install`、`removed-flag-path`；分母 446 = 475 − 29；日志 `C:\temp\celerite-t191\.tmp-scratch\full-diff-2.7.2.txt`，耗时 122.26 分钟，EXIT 1）保留为历史；本轮其中 4 条已转 PASS，仅 `removed-flag-path` 仍 FAIL。更早一档 **133 fixtures: 126 passed, 6 failed, 1 skipped**（2026-11-13，`add-group` deferred；日志 `C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log`；分母 424 在采集当日即已过期）同样保留为历史。分母自 task-191 的 475 / 29 / 446 增至本轮实测的 484 / 30 / 454（task-191 之后新增 9 个夹具目录、1 个 `deferred-2.7.2`） |
| 差分夹具总数 | — | **486** 个目录（全量分母 = 486 − 该 profile 的 deferred 数：2.7.2 = 456（30 个 `deferred-2.7.2`）、4.0.24 = 481（5 个 `deferred-4.0.24`）） | 2026-11-24（task-215 同轮，首辅在 `96941b3` 实测：目录 486 / 带 `command` 486 / `deferred-2.7.2` 30 / `deferred-4.0.24` 5；task-212 于 `114c8ba` 复测 484 / 30 / 5 为上一档，task-214 新增 `install-bundle-path-is-file`、`install-lockfile-path-is-directory` 两个目录） | `fixtures/differential/*/command`（`Get-ChildItem fixtures\differential -Directory` 实测 484（目录数，task-212 于 `114c8ba`）；`command` 文件存在性仅 task-188 同轮对当时 475 个目录全量核过，其后新增目录未逐一复核（未验证）。461 是 task-181 于 `2ad9b66` 的口径，其后 task-184/186/187 新增 12 个目录；上一档 484（task-212 于 `114c8ba` 口径，30 个 `deferred-2.7.2`）；475（task-188/189 口径，29 个 `deferred-2.7.2`）、457（task-169）、454、443 依次保留为历史：454 见 [compat-evidence/2026-11-23.md](compat-evidence/2026-11-23.md) 的「M7-docs 文档-代码一致性清单（task-160）」，443 见 2026-11-22） |
| 全量 `crystal spec` | `crystal spec` | **1393 examples, 0 failures, 0 errors, 0 pending**（2026-11-26 21:47 采集、绑定 `811569c` + `spec/m8_task272_identity_spec.cr` 未提交 symlink 条件化修复；EXIT 0，`Finished in 28:37 minutes`；首辅短路径隔离验收树 `C:\temp\celerite-acc41\.tmp-scratch-clean`，完整 PATH 与全新树内 TMP/HOME/CACHE、`CELERITE_RUBY=C:\Ruby40-x64\bin\ruby.exe`，日志 `C:\temp\celerite-acc41\.tmp-scratch-clean\full-spec-clean.txt`；task-272/273/274 合流与锁写入错误路径 followup 已合并）。**已取代（superseded）**：**1309 examples, 0 failures, 0 errors, 0 pending**（2026-11-25 04:23 采集、绑定 `b916df7`；EXIT 0，`Finished in 20:31 minutes`；首辅短路径隔离验收树 `C:\temp\celerite-acc39`，完整 PATH 与树内 TMP/HOME/CACHE、`CELERITE_RUBY=C:\Ruby40-x64\bin\ruby.exe`，日志 `C:\temp\celerite-acc39\.tmp-scratch\full-spec-b916df7.txt`；task-257 及 Windows ENV 大小写 followup 已合并）。**已取代（superseded）**：**1078 examples, 0 failures, 0 errors, 0 pending**（2026-11-23 21:21 采集、绑定 `302cbae`；**本任务未在 HEAD（`114c8ba`）重跑，也未复核原始日志，故按「最近一次」而非 HEAD 现状记录**）。**已取代（superseded）**：**1058 examples, 0 failures, 0 errors, 17 pending**（`Finished in 21:30 minutes`，EXIT 0；task-185 于 2026-11-23 在 `2ad9b66` 实测，隔离环境：临时根 `C:\t\cel\.tmp-scratch\sp6`（绝对长度 25），`TMPDIR`/`TMP`/`TEMP` 同指该短根，`HOME`/`USERPROFILE` = `C:\t\cel\.tmp-scratch\h6`、`CRYSTAL_CACHE_DIR` = `C:\t\cel\.tmp-scratch\c6` 均隔离，并显式清除 `BUNDLE_GEMFILE`、`CELERITE_VERBOSE`；原始日志 `C:\temp\lead-full6.txt` 为本机临时产物、不入库）。**已取代（superseded）**：task-181 于 2026-11-23 在 `2ad9b66` 的 worktree 记录 **1058 examples, 10 failures, 0 errors, 17 pending**（`Finished in 20:46 minutes`，EXIT 1；临时根 `C:\t\cel`，`TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE`/`CRYSTAL_CACHE_DIR` 全指工作区内绝对目录，缺一即假红）；10 条失败为 `spec/cli_spec.cr:61`、`:78`、`:199`、`:226`、`:238`（missing-gem 参考格式与 bundle 头部行）、`spec/m7_filesystem_errors_spec.cr:65`、`spec/m7_fund_group_spec.cr:183`、`spec/m7_list_pristine_no_lock_spec.cr:87`、`:107`、`spec/m7_show_listing_spec.cr:143`。这 10 条在三种配置下均**不可复现**：配置 A（`C:\t\cel` @ `2ad9b66`，临时根绝对长度 21）、配置 B（`C:\temp\celerite-t181`，临时根绝对长度 42）、配置 C（`C:\temp\celerite-t181`，`HOME=C:\Users\ShiningRay`，机器级 `.bundle/config` 含 `BUNDLE_PATH: "vendor/x"`），5 个涉事 spec 文件合跑各得 **`48 examples, 0 failures`**；故原文「隔离重跑这 10 例得 `10 examples, 10 failures`，**可复现、非 flaky，真因未定位（未验证）**」的表述**已被取代**，该次 10 条红**不作为产品缺陷或 HEAD 现状记录**。上一条记录（采集于 `38021fc`，现由 `2ad9b66` 的权威复跑确认）：**1058 examples, 0 failures, 0 errors, 17 pending**（`Finished in 23:06 minutes`，EXIT 0；`38021fc` 之后至 `2ad9b66` 只有文档提交）；两者 example 总数相同而失败数不同，差额不是用例增减。上一条历史记录：**1039 examples, 0 failures, 0 errors, 0 pending**（`Finished in 45:58 minutes`，EXIT 0；结果绑定 `17f163e`，临时根 `TMPDIR`=`HOME`=`<工作区>/.tmp-scratch/d/{tmp,home}`，距盘符 67 字符）。演进：`b99bf12` 编译期失败（`spec/m7_verbose_echo_spec.cr:18`，task-127 `ae1248c` 修）→ `40ad324` 991/86/10 → `eed51d7` 999/5/11（task-128/129 修掉两条 spec 间环境泄漏链，86→5）→ `d9884ff` 1001/0/0/0（task-132/133/134 清掉剩余 5 条）→ `a9b08c4` 1003/0/0/0（task-135）→ `17f163e` **1039/0/0/0**（task-137 修掉索引失败吞并、task-157/161 等新增用例；同轮修掉 `spec/m7_build_args_spec.cr` 缺索引与 `spec/m7_remove_failure_modes_spec.cr` 折行断言两条假红）→ `38021fc` **1058/0/0/17** → `2ad9b66` **1058/0/0/17**（task-185 隔离短根权威复采，见本行抬头；其间 task-181 的 1058/10/17 已由该次复跑取代）。前提六条（原生形态 / 落在 checkout 内 / 真实而非 junction / `core.longpaths` / 不与并发会话共享 / 临时根距盘符 ≤67 字符）见 [compat-claims/M7-suite.md](compat-claims/M7-suite.md) C-M7-suite-004 与 [compat-evidence/2026-11-23.md](compat-evidence/2026-11-23.md)；不满足时套件可能编译期即失败或带一批路径几何假红。此前 **656 examples, 0 failures, 4 errors**（2026-11-18/19）已取代，原记录见 [compat-evidence/2026-11-18.md](compat-evidence/2026-11-18.md) | 2026-11-23 | [compat-evidence/2026-11-23.md](compat-evidence/2026-11-23.md) 的「2026-11-23：全量 `crystal spec` 的 1058/10 复现失败与权威复跑（task-185）」节、[compat-claims/M7-suite.md](compat-claims/M7-suite.md) |
| L164 快路径门 | `script/fast-path-gates`；`crystal spec spec/m8_install_fast_path_spec.cr -e "CI capability"` | **4.0.24 PASS / 2.7.2 PASS**；当前 binary focused **1/0**；固定 `d9009b1` 旧 binary **1 failure / EXIT=1**（`expected_miss_after_lock_tamper: stats={0, 0, 0, 0}`）；Ruby driver **11 checks, 0 failures**；GitHub Actions 首轮 Windows/4.0.24 success、其余三格装具失败，`7bcdf6f` 修复后待四格复跑 | 2026-11-26（task-275 合流后首辅短路径实测；CI 复跑未完成） | [compat-evidence/2026-11-26.md](compat-evidence/2026-11-26.md) 的「2026-11-26：L164 快路径 CI 正门与旧二进制负向能力门（task-275）」 |
| 上游 lockfile 套件 | `script/upstream-specs`（`CELERITE_SKIP_TEST_DEPS=1`；worktree `C:\temp\celerite-t193` @ `954f2d5`，经 junction 复用主工作区 `.upstream-specs` 的 4.0.24 checkout 与夹具） | **64 examples, 45 failures**（19 passed；脚本分桶 `env:out-of-process-artifice` 44 / `fixture:fetch-failed` 1 / `env:low-il-shm` 0 / `product:candidates` 0；real-drive 69 次、`harness verdict: ok (rspec exit 1)`；报告 `.upstream-specs/upstream-lockfile-v4.0.24-20261123T132826Z.md`），2026-11-23 task-193 复采。**artifice 桶已改判为 `env:out-of-process-artifice`，属装具跨进程限制而非产品缺口**——真因是 celerite 以原生 exe 执行，拿不到 RSpec 经 `RUBYOPT=-r` 注入子进程的 artifice 桩（本轮 `LoadError` 与 `sinatra` 各 0 次，排除缺 gem）。构成（相对上一条 50 failures）：5 条转绿，全部是上一条的「新增宿主 msys `0xC0000022` 抖动」那 5 条（`:477`、`:550`、`:586`、`:622`、`:2144`），即抖动复原、不计作修复；4 条原 `env:low-il-shm`（`:658`、`:813`、`:1974`、`:2031`）与 2 条原 `fixture:fetch-failed`（`:36`、`:87`）本轮错误面改为 `Could not reach host`，按规则表落入 artifice 桶，失败签名变化但归因不属产品；`product:candidates` 仍为 0，50 条逐条定性见 [roadmap-evidence/M7-8-upstream-specs.md](roadmap-evidence/M7-8-upstream-specs.md) 的 task-193 节。上一条历史记录（**superseded**）：**64 examples, 50 failures**（14 passed；分桶 artifice-unreachable 38 / env:low-il-shm 9 / fixture:fetch-failed 3，product 归零；real-drive 69、`harness verdict: ok`），2026-11-23 task-178 复采；其构成相对 64/47 是 2 条转绿（`[1:57:1:1]`、`[1:56:1:1]`）、1 条改桶（`:1682`）、5 条新增 msys `0xC0000022` 抖动。更早一档（**superseded**）：**64 examples, 47 failures**（17 passed；artifice-unreachable 41、fixture:fetch-failed 3、product:candidates 3；real-drive 69），2026-11-22 采集，取代 64/48（差 1 条是 `:586` 在 flaky 的 msys Low-IL 上转绿）。`script/upstream-specs` 现已自证真驱动并对「环境不可用/未驱动」分别以 69/70 退出。 | 2026-11-23（task-193 复采 45 failures；上一档 task-178 为 50） | [roadmap-evidence/M7-8-upstream-specs.md](roadmap-evidence/M7-8-upstream-specs.md) |

夹具 deferred 标记实测（task-212 于 2026-11-23 在 `114c8ba`（worktree `C:\temp\celerite-t212`）复测，`Get-ChildItem fixtures\differential -Recurse -File -Filter deferred-<profile>`）：**2.7.2 profile = 30 个**、**4.0.24 profile = 5 个**（`cache-all-platforms`、`git-submodules`、`issue-no-gemfile`、`plugin-source-disabled`、`show-outdated-verbose-272`）。按本表的分母口径，2.7.2 全量分母现为 484 − 30 = **454**、4.0.24 现为 484 − 5 = **479**（task-212 于 2026-11-23 在 `114c8ba` 实测：目录 484、`deferred-2.7.2` 30、`deferred-4.0.24` 5；上一档 2026-11-23 首辅在 `cb62ace` 实测 475 / 29 / 5；task-189 相对 task-188 的 473/28/5 新增 `env-gemspec-multi`、`gem-questionnaire` 两个目录并带来第 29 个 2.7.2 deferred。上一档 475 派生的 446 / 470、473 派生的 445 / 468、461 派生的 435 / 456、457 派生的 431 / 452 依次保留为历史）；这两个分母都尚未在 HEAD 上重跑全量，上面的全量行仍只是各自采集日的记录，**未在 HEAD 重跑全量差分，故两个 profile 的既有全量结果分母已过期**。

差分 4.0.24 的历史演进（同一文件里仍并存，读旧条目时注意口径）：115:101/14/0 → 130:123/7/0 → 133:126/7/0 → 135:135/0/1 → 160:160/16/2 → 210:210/14/2 → **218/14/3**。
其中 2026-11-14 的 `135 passed, 0 failed` 与 2026-11-15 装具 `git-init` 修复期的 `77 passed, 59 failed` 属装具口径轮次，不作产品结论（原证据见 [compat-evidence/2026-11-14.md](compat-evidence/2026-11-14.md)、[compat-evidence/2026-11-15.md](compat-evidence/2026-11-15.md)）。

## Scope and limits of what this report proves

This file remains a **recorded snapshot** of prior evidence. Differential
(`script/differential`, both profiles) and upstream `script/upstream-specs` rspec
were **not rerun at `811569c`**; the per-row runs behind this revision are only the
ones named in `## Current metrics` (4.0.24 full at `05402b6` / task-245, 2.7.2 full at
`302cbae` / task-208, upstream at `954f2d5` / task-193, full `crystal spec` last run at
`811569c` plus the uncommitted symlink test fix with `1393/0/0/0`, fixture counts at
`96941b3` / task-215; the task-257 `1309/0/0/0`, `1078/0/0/0`, and older
task-181/task-185 records are superseded).
All other counts/results below must be read as unverified against the current HEAD
unless explicitly stated otherwise.

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

> 治理后的补充：上表每行都标注了采集日期与出处；本文件**未重新运行**差分与上游 rspec，全量门禁里只有 `crystal spec` 一行有实测采集点（最近一次 `811569c` + symlink 条件化修复，`1393/0/0/0`，2026-11-26 21:47；task-257 的 `1309/0/0/0` 与 task-185 的 `1058/0/0/17`、task-181 的 `1058/10/17` 均已被取代），其余各行按其采集点读取。

## Environment

| 项 | 值 |
| --- | --- |
| 报告依据的最后已知 HEAD | `7bcdf6f`（task-275 CI 路径/双 Bundler 安装可移植性 followup；GitHub Actions 首轮 Windows/4.0.24 success、其余三格装具失败后已修，四格复跑待观察）。**已取代（superseded）**：`dace1c2`（task-275 门禁可移植性修正；task-272/273/274 产品代码已合入，完整 `crystal spec` 最近一次绑定 `811569c` + identity symlink 条件化修复，**1393/0/0/0**，2026-11-26 21:47；task-275 双 profile 门在短路径 `C:\temp\celerite-gate275` 实测 PASS，旧 binary 负门精确失败）。**已取代（superseded）**：`811569c`（task-274 锁写入错误路径 followup；主仓 identity spec 当时含未提交 symlink 条件化修复，task-272/273/274 文档随后已提交）。**已取代（superseded）**：`b916df7`（`b916df748519eb5360a4170bef51936f310d1c0c`，task-257 Windows ENV 大小写 followup；全量 `crystal spec` 在短路径验收树 `C:\temp\celerite-acc39` 实测 **1309/0/0/0**，EXIT 0，2026-11-25 04:23 采集）。**已取代（superseded）**：`114c8ba`（`114c8ba6c47ba7f526088c6b9de2908a731280db`，`docs(M7 task-211): restate the M7-5 roadmap row`；**task-212 复核本文件时的 HEAD**）。各行采集点：4.0.24 全量 `4bdc20a`（task-188）、2.7.2 全量 `954f2d5`（task-191）、上游 `954f2d5`（task-193，worktree `C:\temp\celerite-t193`）、全量 `crystal spec` 最近一次 `302cbae`（2026-11-23 21:21，`1078/0/0/0`）、夹具计数 `114c8ba`（task-212）；历史快照 HEAD 原文保留：`2ad9b66`（`2ad9b66ca3d5263466a7c9e96bbdecaaf1dd3719`，task-181 实测的 worktree HEAD；task-185 的 `1058/0/0/17` 与 task-181 的 `1058/10/17` 均已被 `302cbae` 的 `1078/0/0/0` 取代）、`75bafcc`（`75bafcc13c83befa49fc8e2bc7402cace5b52871`，`docs(M7): record the GEM_HOME prefix-comparison gap as a known implementation gap`；task-169 实测的当时 HEAD）、`c3b9a6f`（`docs(M7 task-117): 补记锁定 spec 行缺失时的重解析差异与证据`）、`8e91a2f` |
| Ruby 参考 | 4.0.6 x64-mingw-ucrt（另测 2.7.2 profile） |
| Crystal | 1.22.1 |
| git | 2.55.0.windows.3 (Windows x64, win32) |
| 宿主限制 | msys Low-IL 下子进程 `0xC0000022`（git 源夹具与原生扩展构建）；`make` 默认不在 `PATH`（`Get-Command make` 未命中；`C:\Ruby40-x64\msys64\usr\bin\make.exe` = GNU Make 4.4.1，把该目录前置到 `PATH` 后可编译 nio4r 2.7.5 原生扩展）——此前「`make` 不可用」的判断已过期（task-169 订正）；`racc` 1.8.1 随 Ruby 4.0.6 安装且可运行（`racc.bat --version` → `racc version 1.8.1`，`cparse.so` 位于 `C:\Ruby40-x64\lib\ruby\gems\4.0.0\extensions\x64-mingw-ucrt\4.0.0\racc-1.8.1\racc\`），但它在原生扩展构建中的作用**未验证**；http-index 夹具需 `CELERITE_DIFF_EXTRA_PATH='/c/Program Files/nodejs'` |

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
- **`GEM_HOME` 归属判定用字符串前缀比较，symlink/junction 拼法下丢 gem（未修，留待后续任务）**：`src/celerite/resolution.cr` 的 `local_index_specs`（`:813`）在 `:825-829` 用 `home_prefix = home.gsub('\\', "/").chomp("/") + "/"` 与 `gem_path.starts_with?(home_prefix)` 判断 bridge 返回的已装 gem 是否属于本项目的 `GEM_HOME`（该过滤器由 `1c0c214 feat(M7 task-5): honor --local and --prefer-local during install` 引入，作用是让 `--local` 只认本项目装的 gem、把宿主 user/system 目录里的同名新版排除掉）。问题在于两侧的路径视图不一致：RubyGems 会把 symlink/junction 解析成真实路径再写进 `full_gem_path`（`assets/bridge/server.rb:308`），而 Crystal 的 `File.real_path` **不解析 junction**，于是当 `GEM_HOME` 经 symlink/junction 拼出时，前缀比较必然失败，该项目里的所有已装 gem 都被当作「不属于本项目」直接 `next` 掉，`install --local` 与无 lockfile 的解析随即报 `Could not find gem '<name>' in locally installed gems.`、exit 7。参考 `bundler-4.0.24` 走 RubyGems 自身视图，不受影响。**只在 symlink/junction 拼法下可见**，真实路径的 `GEM_HOME` 行为正确。实测（同一 HEAD，4 个 spec：`spec/m7_no_lockfile_commands_spec.cr`、`spec/m7_local_install_spec.cr`、`spec/m7_local_install_missing_dep_spec.cr`、`spec/m7_remove_failure_modes_spec.cr`）：临时根为 junction 时 `17 examples / 5 failures`，换成真实路径 `17/1`；`a9b08c4` 上同形，故**不是回归**，此前没有被记录。**建议修法**：比较前把两侧都归一为真实路径（对 `ENV["GEM_HOME"]` 与 `entry["full_gem_path"]` 各取一次 `File.real_path`，失败时回落到原字符串），或改为按路径分段比较；同时补一条 junction/symlink 场景的 spec 钉住它。代价约一个辅助函数 + 一条 spec + 复核 `local_index_specs` 的另一处调用点（`--prefer-local`）。**当前规避**：运行 `crystal spec` 时把 `TMPDIR`/`HOME` 指向真实（非 junction）路径，见 [compat-claims/M7-suite.md](compat-claims/M7-suite.md) 的 `C-M7-suite-004` 前提 (c)；根因与两组对照数据见 [compat-evidence/2026-11-23.md](compat-evidence/2026-11-23.md)。
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
| `plugin install --source/--version/--git/--branch/--ref` | **Partial** — `--source` remote install: failure path on HTTP v2 (`plugin-source` exit 7) verified on both profiles; success path with plugin-tree materialization + `Fetching`/`Installing` output (`plugin-source-ok`, passing on both profiles when re-run 2026-11-23, but a native-extension build failure is on record for the same fixture, so the plugin-side claim stays unverified); `--version` is accepted with no fixture of its own; `plugin install --git/--branch/--ref` likewise has **no fixture of its own** — `plugin-git-local`/`plugin-git-local2` (dual-passed) exercise `install` with a *gem* git source, not the plugin-install flag path, and the plugin checkout tree has no independent oracle. |
| `add --group/--version/--source/--path/--git/--branch/--ref/--skip-install/--strict/--optimistic` | **Partial** — `--group` (`add-group`), `--skip-install` (`add-skip-install`), `--version` (`add-version`), `--strict` (`add-strict`, exit 7 on the reference `= 1.8` error), `--optimistic` (`add-optimistic`), `--require` (`add-require`), `--path` (`add-path`), `--git`/`--branch` (`add-git`), and scoped `--source` (`add-source`), distinct-remotes scoped lock (`scoped-source-lock`), and `--ref` (`add-ref`) are differential-verified: requirement probes and candidate resolution use the scoped compact-index remote, installations route downloads/installers by resolved `remote_for` per gem, and generated lock GEM sections are grouped by that remote; `--github` remains suffix-only/not fixture-proven. |
| `binstubs --force/--standalone/--all-platforms/--shebang/--all` | **Supported** — `--force`/`--all`/`--all-platforms` honored with skip message (`binstubs-flags` dual-passed); `--shebang` rewrites the stub first line (`binstubs-shebang-line` dual-passed via harness `first-line` content probe; 2.7.x remembers `shebang` in local config). |

## Upstream spec suite coverage boundary

The committed `script/upstream-specs` targets only the **lockfile family** of
the upstream Bundler spec suite (pinned `v4.0.24` revision). Three successive
baselines are recorded below, newest first; all three are kept.

- **Current baseline: 64 examples, 45 failures** (19 passed; buckets
  `env:out-of-process-artifice` 44 / `fixture:fetch-failed` 1 /
  `env:low-il-shm` 0 / `product:candidates` 0; real-drive 69; collected
  2026-11-23 by task-193). This is the authoritative number in `## Current
  metrics` above; it supersedes the 47-failure intermediate below.
- **Intermediate baseline: 64 examples, 47 failures** (17 passed; buckets
  `env:out-of-process-artifice` 41 / `fixture:fetch-failed` 3 /
  `product:candidates` 3; collected 2026-11-22, task-146/task-158). It
  superseded the 53-failure collection and is itself superseded by the
  45-failure run above.
- **Earliest historical collection: 64 examples, 53 failures** (11 passed;
  collected 2026-11-22 by task-114; recorded under
  `docs/compat-matrix/generated/upstream-lockfile-v4.0.24.md`). It is the oldest
  of the three and has been superseded twice — first by 47, then by 45 — and is
  retained as a failure baseline for M7 only as history.

> 取代关系（task-209 更新，2026-11-24）：**53**（2026-11-22 task-114，最早的历史采集）→ **47**（2026-11-22 task-146/task-158，中间态）→ **45**（2026-11-23 task-193，当前口径，见 `## Current metrics`）。三值均保留，不删历史；见 [roadmap-evidence/M7-8-upstream-specs.md](roadmap-evidence/M7-8-upstream-specs.md) 与 [compat-evidence/2026-11-23.md](compat-evidence/2026-11-23.md) 的「过期证据结论的取代条目（task-158）」及 task-193 节。

**本迭代脚本变更（未重跑 rspec）**：移除 `script/upstream-specs` 中吞掉失败的
`|| true`（line 64 附近），使 rspec 非零退出时脚本按 `pipefail` 传播非零退出码；
保留既有 64 failures 失败基线记录逻辑/文案。由于本迭代未执行上游 spec，
上述 64 failures 仍为既有记录，不能视为本次运行结果。（task-209 加注：这些历史值已依次被 47 与当前的 45 取代；本节的脚本变更陈述仍成立，但不得再引 64/53、64/48 或 64/47 当作当前基线，当前口径见 `## Current metrics` 的 45。）

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
- 逐日证据日志（过程档案）：[docs/compat-evidence/README.md](compat-evidence/README.md)（含 12 个文件清单与 233 个节的标题索引 + 锚点行；task-169 复测：233 是按 `^## ` 实测的节数，211 为治理拆分当时的旧值，见 [compat-evidence/README.md](compat-evidence/README.md) 的「节数」列说明）。
- 治理前的报告头部（原行 1-401，含 2026-11-11 task-2 本地校验、2026-11-15 env/console/gem 模板子节、97 夹具的 M0–M6 归类清单、当时的环境与免责声明）：[docs/compat-evidence/2026-11-11.md](compat-evidence/2026-11-11.md)。
- 夹具证据转储（生成的逐例对比）：`docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`、`cli-4.0.24.md`、`cli-2.7.2.md`、`upstream-lockfile-v4.0.24.md`。
- 主题矩阵（手写）：`docs/compat-matrix/`（lockfile-sections.md、gemfile-dsl.md、cli-commands.md、config-keys.md）。
- 基准与 profile：`docs/benchmarks/`。
- 引用上文某个历史节时，请引「compat-evidence 的日期文件 + 节标题」，不要引本文件的旧行号。
