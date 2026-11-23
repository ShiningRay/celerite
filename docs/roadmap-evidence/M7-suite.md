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
## 2026-11-24：折行用例的几何依赖与钉宽（task-225）

### 前因

全量 `crystal spec` 在 `9e01625` 上有 2 failures，且只在临时根为 10 字符时复现（首辅在 `C:\temp\celerite-t225` 实测，机制详记于 `docs/compat-evidence/2026-11-23.md` 的 task-225 节）：

| 临时根 | 长度 | 结果 |
|---|---|---|
| `C:\t\sp225` | 10 | `1086 examples, 2 failures, 0 errors, 22 pending` |
| `C:\t\cel\.tmp-scratch\sp225` | 27 | `1086 examples, 0 failures, 0 errors, 22 pending` |

失败点是 `spec/m7_filesystem_errors_spec.cr:65`（断言 `:77`）与 `spec/m7_fund_group_spec.cr:183`（断言 `:192`）。机制：`src/celerite/cli.cr:63-70` 的 `CLI.terminal_width`（`THOR_COLUMNS` 存在且 ≥10 才采用，否则 80）配上 `src/celerite/cli/commands.cr:1205-1214` 的 `Commands.word_wrap`（正则 `(.{1,#{width}})(\s+|$)`，与参考 `bundler-4.0.24/lib/bundler/ui/shell.rb` 的 `word_wrap` 逐字同形）决定断点；两条消息内嵌临时项目的绝对路径，断点因此随临时根长度漂移，而用例把其中一种几何当成了常量。

### 做法

- 钉宽：`spec/m7_filesystem_errors_spec.cr` 新增 `with_permission_columns`，`spec/m7_fund_group_spec.cr` 新增 `with_fund_columns`，把 `THOR_COLUMNS` 钉为 `"30"`，`ensure` 里恢复或删除（与 `spec/m7_add_options_spec.cr:41-53`、`spec/m7_source_index_missing_spec.cr:75-91` 同形）。30 列下 `There was an error while`、`trying to write to`、`It is likely that you need to`、`grant write permissions for` 各自占满一行，路径又总是远宽于 30 列，断点不再随临时根变化。
- 期望改字面量：删掉 `permission_expected_stderr`（它用 `Commands.word_wrap` 反算期望，属自证），改为逐行写出的字面串；`contain` 级粗检保留，按 30 列的断行取词。`m7_fund_group_spec.cr` 的三行字面量（`The path` / 反引号路径 / `does not exist.`）不变，只改由钉住的宽度保证；同一例里 `THOR_COLUMNS=1000` 的单行对照保留。
- 边界用例：新增 `spec/m7_word_wrap_boundary_spec.cr`，直接调 `Celerite::Commands.word_wrap(..., 80)`，覆盖 63/64/65 字符路径。

### 判据

`PathError` 消息首行宽 `16 + path.size` 列（前 10 列是 `The path ` 加起始反引号，末 6 列是收尾反引号加 ` does`）：64 字符恰为 80 列，`does` 仍在首行；65 字符溢出，`does` 换行、路径独占一行。63 与 65 正是 task-225 两种几何（63 字符 vs ≥65 字符）各自落到的断点，这条用例把阈值钉死，防止将来改宽度逻辑时无声漂移。

### 证据（命令与结果行）

工作树 `C:\temp\celerite-t225b` @ `c55e1d9`，`THOR_COLUMNS` 由用例自身钉住；环境按 M7 约定隔离 `TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE`/`CRYSTAL_CACHE_DIR`：

| 检查 | 命令 | 结果 |
|---|---|---|
| 格式 | `crystal tool format --check src spec` | 退出码 0 |
| 编译 | `crystal build --no-codegen src/cli.cr` | 退出码 0（仅 `commands_install.cr:1847`/`:1910` 两条既有 `File.executable?` 弃用警告） |
| 短临时根 `C:\t\cel225b` | `crystal spec --no-color spec/m7_filesystem_errors_spec.cr spec/m7_fund_group_spec.cr` | `13 examples, 0 failures, 0 errors, 0 pending` |
| 长临时根 `C:\t\cel\.tmp-scratch\sp225b` | 同上再并 `spec/m7_word_wrap_boundary_spec.cr` | `14 examples, 0 failures, 0 errors, 0 pending` |
| 回归（长根） | `crystal spec --no-color spec/m7_gemfile_not_found_message_spec.cr spec/m7_lock_gemfile_missing_spec.cr spec/m7_source_index_missing_spec.cr spec/m7_add_options_spec.cr` | `11 examples, 0 failures, 0 errors, 0 pending` |
| 空白 | `git diff 19f9a93..HEAD --check` | 无输出，退出码 0 |

### 未验证项

- 未重跑全量 `crystal spec`（1086 例）：本轮只跑受影响的 2 个文件、新增边界用例与 4 个回归文件，「全量在短根下转绿」留给首辅的最终验收。
- 未在 Linux/macOS 复验，结论只在 Windows + `C:/Ruby40-x64` 取得。
- 63/64/65 阈值按我方 `word_wrap` 实测；参考侧本轮未重跑差分，只核对了正则与 `shell.rb` 逐字同形。
- 30 列这个取值绑定当前文案：若固定句子改短，钉宽结论需按新文案重算（边界用例只固定阈值，不固定文案）。