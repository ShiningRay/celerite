# M7 全量 `crystal spec` 可跑通

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 164 -->

（2026-11-19 task-19 验收补记：进程中途静默结束、EXIT 1 无摘要；已在 `a3ed3ec` 复现，与本轮改动无关；4 个已定位失败为 `~/.bundle/config` 与临时目录的环境耦合；详见 `docs/compat-evidence/2026-11-19.md` 同名补记）。2026-11-22（task-131 补记）: 编译期失败已修（`ae1248c`），全套件现可跑到 Finished（999 examples / 5 failures / 11 pending，22:32），剩余 5 条属 m7_clean / m7_show_order / m7_quiet_and_add 三个既有家族，尚未清零。
## 2026-11-22：全套件 `crystal spec` 在本机跑到 `Finished` 且零失败（task-132/133/134/135 收尾）

### oracle

参考 Bundler 4.0.24（`C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24`）不提供 Crystal 套件的 oracle；本节的可比对对象是**修复前的同一套件**与**修复后**的同一环境复跑。

### 参考锚点

本条对应 roadmap 的「修复在本机无法跑完全量 `crystal spec` 的问题」，其可勾选判据是「套件能跑到 `Finished` 且零失败」，锚在实测结果行，无上游参考行号。

### 实现位置（文件:行）

- 编译期失败：`spec/m7_verbose_echo_spec.cr:18` 对 `Celerite::Commands.print_command_echo` 传 5 个实参，签名（`src/celerite/cli/commands.cr:512-513`）要求 6 个；由 `ae1248c` 修好。
- 剩余 5 条失败：`bundle clean` 无 path 守卫（`spec/m7_clean_spec.cr`，`fd549f0`）、`spec/m7_show_order_spec.cr` 的参考 lib 环境前提（`1303546`）、`lock` 有锁时的 source index 行（`src/celerite/cli/commands.cr:3016`/`:3130`，`b07c948`）。
- 两条 spec 间环境泄漏链：`src/celerite/cli/commands.cr` 的每次调用状态重置（`633c5f9`）、`spec/m7_binstubs_path_source_spec.cr` 的 `BUNDLE_GEMFILE` 复原（`eed51d7`）。

### 证据（命令与结果行）

同一台机器、隔离 `CRYSTAL_CACHE_DIR` / `TMPDIR` / `HOME`（均指向工作区内）下三次全量运行：

| 代码状态 | 结果 |
|---|---|
| `b99bf12`（未修 `m7_verbose_echo_spec.cr`） | 编译失败：`In spec\m7_verbose_echo_spec.cr:18:22 … Error: wrong number of arguments for 'Celerite::Commands.print_command_echo' (given 5, expected 6)` |
| `40ad324`（task-123/125/126/127 后） | `991 examples, 86 failures, 10 errors, 0 pending`（`Finished in 22:32 minutes`） |
| `d9884ff`（task-132/133/134 后） | `1001 examples, 0 failures, 0 errors, 0 pending`，`Finished in 16:56 minutes`，退出码 0 |

86 条红中的 81 条由两条 spec 间环境泄漏链解释（`CELERITE_VERBOSE` 未复位、`BUNDLE_GEMFILE` 未复原），其余 5 条由 task-132（2 条）、task-133（2 条）、task-134（1 条）清零；详见 `docs/compat-evidence/2026-11-22.md` 对应小节。

### 已声明差异

- 本节结论仅在本机 Windows + `C:/Ruby40-x64` 环境取得；未在 Linux/macOS 复验。
- 全量运行 16:56 是「修后」的单次观测，未做多次取中位数。
- `d9884ff` 之后的 task-135 两笔（`9024e96`/`a9b08c4`）只改 `show bundler` 的回落路径并新增一个 spec，其全量复跑结果见追加行。
## 2026-11-22（task-135 后复跑）：`1003 examples, 0 failures, 0 errors, 0 pending`

### oracle

无可比对的上游 oracle（Crystal 套件是本仓库自身的测试）；可比对对象是**同一环境下的修复前后两次全量运行**。

### 参考锚点

对应 roadmap 的「修复在本机无法跑完全量 `crystal spec` 的问题」，判据是「跑到 `Finished` 汇总行且零失败」；锚在实测结果行，无上游参考行号。

### 实现位置（文件:行）

- `ae1248c`（`spec/m7_verbose_echo_spec.cr:18` 补第 4 个实参，对齐 `src/celerite/cli/commands.cr:512-513` 的 6 参签名）——编译期失败已除。
- task-132/133/134/135 的四处修复见 `docs/compat-evidence/2026-11-22.md` 对应小节。

### 证据（命令与结果行）

工作树 `C:\temp\celerite-acc32f` @ `a9b08c4`（含 task-132/133/134/135），隔离 `CRYSTAL_CACHE_DIR` / `TMPDIR` / `HOME`（均指向工作区内）：

```
$ crystal spec --no-color
Finished in 15:40 minutes
1003 examples, 0 failures, 0 errors, 0 pending      (EXIT 0)
```

对照（**不设**隔离，沿用机器默认 `HOME`/`TMPDIR`，同一工作树、同一 HEAD）：

```
$ crystal spec --no-color
crystal : Cannot create temporary file in C:\WINDOWS\: Permission denied
Error: execution of command failed with exit status 0xC0000409: cc _main.o3.obj -o C:\temp\celerite-acc32f\.tmp-scratch
                                                          (EXIT 1)
```

⇒ 「能跑完」的**前提是本机把 `TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE` 指向工作区内目录**（`spec/spec_helper.cr` 依赖 `Dir.tempdir` 与 `~/.bundle/cache`）。不满足该前提时套件在编译/链接阶段即失败，与本条的产品代码无关；此前记录的「进程中途静默结束、EXIT 1 无摘要」属同一环境族的另一种表现。

### 已声明差异

- 两次运行均在 Windows + `C:/Ruby40-x64` 取得，未在 Linux/macOS 复验。
- 16:56（`d9884ff`，1001 例）与 15:40（`a9b08c4`，1003 例）是两次单观测，未多次取中位数；例数差 2 来自 task-135 新增的 `spec/m7_show_bundler_path_spec.cr`。
- 上述环境前提**不是代码修复**：本机默认 `TMPDIR` 指向 `C:\WINDOWS\`，只要该前提不满足，套件仍不能跑完。