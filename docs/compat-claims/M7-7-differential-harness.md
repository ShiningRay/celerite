# M7-7 差分 harness：归一化规则与比较强度（claims）

本文件是 M7-7 的断言账本：把 `../compat-evidence/` 与 `../../script/differential` 已取证的结论逐条固化为可复跑断言。原始建档、逐字输出与探针目录仍留在 evidence，本文件只写结论与判据。范围 = `script/differential` 的归一化规则清单与比较强度（含安装树比较、内容探针、`file-absent`/`file-exists`/`stderr-contains` 三条夹具级通道）；不含被比较的产品行为本身（那在 M7-1…M7-6 各文件）。

## C-M7-7-001 `script/differential` 头部逐条列出 N1–N10 十条归一化规则

- 状态：已实现
- 参考行为（4.0.24）：harness 自身契约，非 Bundler 侧行为；规范声明「本文件是权威清单，脚本头部携带同一批标识符，新增规则须先改文档再改脚本并双 profile 重跑」（`docs/differential-normalization.md:3-7`），ID 表见 `docs/differential-normalization.md:9-19`。
- 我方行为：`script/differential:15-46` 头部编号列出 N1 沙箱路径、N2 CRLF、N3 ISO 时间戳、N4 日历日期、N5 `## Environment` 体、N6 backtrace 帧、N7 连续 `Fetching ` 行、N8 原生扩展编译器 PATH、N9 安装树二进制产物、N10 `env` 夹具文件；`:45` 明写 `# Exit codes, all other line ordering, trees and file contents must match.`，`:46` 为 `set -uo pipefail`。
- 判据：`bash script/differential env-report install-check`
- 边界：文档 ID 表未收录 N8，且 `stderr-contains` 通道与 `env` 夹具文件规则共用 N10 标识符（见 C-M7-7-007）。
- 生效：task-3（M7(7) 于 2026-11-14 验收，证据 `../compat-evidence/2026-11-14.md` 的 M7(7) acceptance 节）
- 取代：无

## C-M7-7-002 退出码与 N1–N7 之外的 stdout/stderr 逐字且同序比较

- 状态：已实现
- 参考行为（4.0.24）：规范「What is *not* normalized」要求 exit codes 必须精确，N1–N7 之外的 stdout/stderr 必须逐字且有序（`docs/differential-normalization.md:21-35`）。
- 我方行为：`script/differential:510-511` 逐值比较两侧 exit code、`:513-514` 对 stdout 用 `diff -q`、`:546-547` 在未声明 `stderr-contains` 时对 stderr 用 `diff -q`；`:554` 的项目树用 `diff -r --brief` 后只保留路径级差异。
- 判据：`bash script/differential install-fresh`
- 边界：项目树比较按设计只比路径集合与内容归一化结果，不比文件内字节顺序之外的元数据（见 C-M7-7-008）。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-003 只有 N7 对连续 `Fetching ` 行排序，其余语义行序不变

- 状态：已取代
- 参考行为（4.0.24）：规范只允许「runs of consecutive `Fetching ` lines are sorted」（并行下载顺序非语义），其余行序精确（`docs/differential-normalization.md:17`、`:21-22`）。
- 我方行为：`script/differential:125-147` 用 awk 只把连续 `^Fetching ` 行读进缓冲、遇到非 `Fetching` 行先对缓冲插入排序再原样打印，END 再冲刷一次。
- 判据：`bash script/differential install-fresh`
- 边界：不连续的 `Fetching` 行不排序（同一实现与 `docs/differential-normalization.md:17` 一致）。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：C-cross-013

## C-M7-7-004 N5 只删除 `## Environment` 体、保留标题，删到下一个 `## ` 标题为止

- 状态：已实现
- 参考行为（4.0.24）：`## Environment` 体按规范剥离（`docs/differential-normalization.md:15`）；`:173-186` 记录 2026-11-15 的修正——旧的 sed 区间规则把 `bundle env` 输出一路删到 EOF，两侧都成 0 字节，`env-report` 长期在做空比较并假 PASS。
- 我方行为：`script/differential:115-124` 的 awk（判定在 `:120-123`）以 `^## Environment$` 进入删除态、打印该标题、遇任意 `^## ` 标题退出删除态并打印，其后正文参与比较。
- 判据：`bash script/differential env-report`
- 边界：文档措辞是「up to `## Bundle Doctor`」，实现是「到下一个 `## `」，在 doctor 报告上二者等价；在 `bundle env` 报告上实现更窄，正文因此仍被比较。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-005 N8 把两侧的 C 编译器统一到 Ruby 自带工具链，`CELERITE_DIFF_EXTRA_PATH` 可追加目录

- 状态：已实现
- 参考行为（4.0.24）：原生扩展的 `.so` 字节随编译器版本变化（Ruby 自带 gcc 与独立 msys64 gcc 不同），因此只能统一编译环境，不能放宽比较结果。
- 我方行为：`script/differential:24-29` 定义 N8，`:60-75` 把 Ruby 自带 `C:\Ruby40-x64\msys64\ucrt64\bin` 与 `usr/bin` 前置进两侧 PATH，并按 `CELERITE_DIFF_EXTRA_PATH` 追加目录；`:38-43` 注释说明构建 CLI 本身必须用原始 PATH（N8 归一后的 PATH 会让 `cc` 报 `liblto_plugin.dll not found`），N8 只作用于夹具运行。
- 判据：`bash script/differential native-ext`
- 边界：`:40-43` 记录的「class A 夹具缺 make」已定性为环境问题（`make.exe` 存在但不在 PATH），不是缺工具。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-006 N9 对安装树里的编译产物只比存在性与可加载性，不比字节

- 状态：已实现
- 参考行为（4.0.24）：native 构建非确定性，可观察契约是「编译成功且可加载」，不是字节相同（`docs/differential-normalization.md:9-19` 的 N9 行）。
- 我方行为：`script/differential:29-33` 定义 N9；`script/differential-installed-tree:20-27` 记录该规则，`:122-135` 对 `.so`/`.dll`/`.bundle`/`.o`/`.a` 走「两侧都存在 + 非空 + 可选 `ruby -e "require <rel>"` 可加载」判定，其余文件仍走 N1–N7 归一化后的逐字节比较。
- 判据：`bash script/differential native-ext`
- 边界：不校验 ABI 兼容性，只查存在性与可加载性（`docs/differential-normalization.md:37-67` 的 N9 补充）。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-007 归一化清单在文档与脚本头部已不一一对应：文档缺 N8，N10 被两条规则共用

- 状态：未实现
- 参考行为（4.0.24）：规范自称权威清单并要求与脚本头部「carry the same identifiers」（`docs/differential-normalization.md:3-7`），ID 表在 `:9-19`。
- 我方行为：`docs/differential-normalization.md:9-19` 的表只有 N1–N7、N9、N10，无 N8；而 `script/differential:24-29` 用了 N8。同一份材料里 `stderr-contains` 通道被称作 N10（`docs/differential-normalization.md:19`、`script/differential:520`、`:524`、`:544`），`script/differential:33` 又把 `env` 夹具文件规则编号为 N10。
- 判据：`bash script/differential plugin-hook-raise env-report`
- 边界：两条规则行为互不干扰（各自只看自己的标记文件），但编号唯一性已破，新增规则前必须先重排编号，否则文档的「same identifiers」不再成立。
- 生效：task-3（N8 加入时）；task-7（`stderr-contains` 引入时叠加冲突）
- 取代：无

## C-M7-7-008 安装树比较覆盖匹配目录集合、相对路径集合、内容、可执行位、symlink 目标五类判定

- 状态：已实现
- 参考行为（4.0.24）：`installed-tree` marker 每行一个相对 `BUNDLE_PATH` 的 glob，两侧展开后按固定顺序比较五类事实（`docs/differential-normalization.md:37-67`）。
- 我方行为：`script/differential:558-563` 在夹具带 `installed-tree` 标记时调用 `compare_installed_tree "$ref_sandbox" "$cel_sandbox" "$fixture_dir/installed-tree" "$ref_sandbox/bundle" "$cel_sandbox/bundle"`；`script/differential-installed-tree:30` 起按 ①匹配目录集合 ②symlink 目标 ③相对路径集合 ④内容（N1–N7 归一化后一致，否则 `content differs after normalization`）⑤可执行位（仅非 Windows）判定。
- 判据：`bash script/differential install-check`
- 边界：可执行位判定在 Windows 上跳过（见 C-M7-7-011）；带该 marker 的夹具清单随仓库演进，权威来源是 `ls fixtures/differential/*/installed-tree`。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-009 symlink 按相对路径与 `readlink` 目标比较，并区分目标不同、类型不同、单侧存在

- 状态：已实现
- 参考行为（4.0.24）：符号链接的可观察契约是「指向哪里」，不是 inode；比较须自行枚举链接并读目标，不依赖 `diff -r --no-dereference` 的版本差异（`docs/differential-normalization.md:37-67`）。
- 我方行为：`script/differential-installed-tree:62-63` 用 `find . -type l` 加 `sed 's|^\./||'` 与 `LC_ALL=C sort` 自遍历两侧；`:78-79` 两侧 `readlink` 取目标；`:81` 目标不同输出 `symlink target differs: ref=<x> cel=<y>`，`:85`/`:91` 类型不同输出 `entry type differs: ref=<file|symlink> cel=<file|symlink>`，`:87`/`:93` 单侧存在输出 `symlink missing on celerite side` / `unexpected symlink on celerite side`；symlink 本身跳过内容与可执行位比较（避免解引用误判）。
- 判据：`bash script/differential-installed-tree-selftest`
- 边界：自测在无法创建真符号链接的宿主上记 SKIP（见 C-M7-7-010），不伪报 PASS。
- 生效：task-2（比较目标）；task-3（比较存在性与类型，M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-010 无法创建真符号链接时安装树自测记 SKIP 并输出复现命令

- 状态：已实现
- 参考行为（4.0.24）：Windows/git 默认不产生真符号链接，若自测在这种宿主上直接断言 FAIL 或 PASS 都会失真；正确行为是显式 SKIP 并给出复现方式（`docs/differential-normalization.md:37-67`）。
- 我方行为：`script/differential-installed-tree-selftest:14` 用 `MSYS=winsymlinks:nativestrict` 探测；`:59` 记录复现命令 `MSYS=winsymlinks:nativestrict ln -s target link && test -L link`；`:64` 起先探测能力，`:118`/`:137`/`:156`/`:175` 在能力不足时调 `report_skip`（`:44`，输出 `SKIP <name>: <原因>` 与 `  repro: <命令>`）。
- 判据：`bash script/differential-installed-tree-selftest`
- 边界：SKIP 只覆盖 (c)(d)(e)(f) 四条与链接相关的断言，(a)(b) 与链接无关仍照常判定。
- 生效：task-2 / task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-011 可执行位只在非 Windows 宿主上比较

- 状态：已声明差异
- 参考行为（4.0.24）：POSIX 上 `bundle` 生成的可执行位属于可观察契约；参考实现在 Windows 上不产生该位。
- 我方行为：`script/differential-installed-tree:162` 在可执行位不一致时输出 `executable bit differs`，但该判定被 `uname -s` 的 MINGW/MSYS 判断跳过（`docs/differential-normalization.md:37-67` 第 5 条）。
- 判据：`bash script/differential install-check`
- 边界：Windows 与 git 通常不保留可执行位，宿主上无法取到参考侧真值，故该维度在 Windows 上不可判定，不作兼容声明；该差异只影响 Windows 宿主。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-012 `first-line` 探针按字节比较指定文件的首行

- 状态：已实现
- 参考行为（4.0.24）：binstub 的 shebang 首行是直接可比的内容事实，须逐字节一致（`docs/differential-normalization.md:21-35`）。
- 我方行为：`script/differential:569-578` 读夹具 `first-line` 标记的首行为工程相对路径，取两侧该文件首行逐字节比较，不一致输出 `first-line differs ($rel): ref=<..> cel=<..>`。
- 判据：`bash script/differential binstubs-shebang-line`
- 边界：只比较首行，其余行由 `file-contains`/`file-equals` 或树比较覆盖。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-013 `file-contains` 探针按 `<path>\t<needle>` 在两侧做字节命中

- 状态：已实现
- 参考行为（4.0.24）：lockfile/Gemfile 的关键行是直接可比的内容事实（`docs/differential-normalization.md:21-35`）。
- 我方行为：`script/differential:602-613` 逐行读 TSV，路径与 needle 都做占位符替换（`@INDEX_DIR@`/`@SCOPED_INDEX_DIR@`/`@BUNDLER_VERSION@` 等），两侧都必须命中同一 needle，否则输出 `file-contains differs ($rel): needle=<needle>`。
- 判据：`bash script/differential lock-missing-dependency-edges`
- 边界：命中是子串字节匹配、不校验行序；需要整份文件逐字时用 `file-equals`（C-M7-7-014）。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无

## C-M7-7-014 `file-equals` 探针逐字比较整份文件，并支持按 profile 的变体标记

- 状态：已实现
- 参考行为（4.0.24）：lockfile 的完整内容是直接可比的事实，不同 profile 的期望体不同。
- 我方行为：`script/differential:580-599` 以标记首行为工程相对路径、其余行为期望体，先在 `$work/file-equals.expected` 落盘再逐字 `diff`；存在 `file-equals-<BUNDLER_VERSION>` 时优先用它（`:586-587`），差异输出 `file-equals differs ($rel, $side)`。
- 判据：`bash script/differential checksums-refresh-cache-deleted`
- 边界：期望体按 profile 分文件维护，新增 profile 须补对应变体；占位符替换与 `file-contains` 共用同一套 `@...@`。
- 生效：task-116（4.0.24 / 2.7.2 两份变体同时落地）
- 取代：无

## C-M7-7-015 `file-crlf` 在 4.x 断言锁文件至少含一个 CRLF 且无孤立 LF、在 2.x 断言纯 LF

- 状态：已实现
- 参考行为（4.0.24）：参考在写锁时检测磁盘字节，原有 CRLF 则整体转 CRLF（`lib/bundler/definition.rb:428-437`，注释说明文本模式读盘会剥掉 `\r` 故必须读字节）。2.7.2 在 Windows 上以文本模式读锁，`lib/bundler/definition.rb:383-385` 的分支不触发，故产物是 LF。
- 我方行为：`script/differential:655-678` 对 4.x 用 `ruby -e` 读二进制，缺 CRLF 报 `missing CRLF`、出现孤立 LF 报 `lone LF at byte <n>`；对 2.x 反向断言不含 `\r\n`；差异统一输出 `file-crlf differs ($rel, $side): <msg>`。
- 判据：`bash script/differential lock-preserve-crlf`
- 边界：只覆盖标记文件；两侧行尾语义由产品侧的 `Commands.preserve_lockfile_crlf?` 按 profile 门控。
- 生效：task-5
- 取代：无

## C-M7-7-016 `file-absent` 通道要求两侧都不存在指定相对路径

- 状态：已实现
- 参考行为（4.0.24）：某些失败场景的可观察契约是「不写锁文件」，纯树路径比较无法表达「不得存在」——两侧都写出该文件反而会 PASS（`docs/differential-normalization.md:68-109`）。
- 我方行为：`script/differential:618-633` 逐行读工程相对路径，任一存在即输出 `file-absent violated ($rel): ref_exists=<yes|no> cel_exists=<yes|no>`；`plugin-hook-raise` 用它断言 hook 抛异常后不留 `Gemfile.lock`。
- 判据：`bash script/differential plugin-hook-raise`
- 边界：只收紧不放松，与树比较叠加生效；空标记文件等同未提供（C-M7-7-018）。
- 生效：task-7
- 取代：无

## C-M7-7-017 `file-exists` 通道要求两侧都存在指定相对路径

- 状态：已实现
- 参考行为（4.0.24）：`install` 在 `vendor/cache` 存在且非 `--no-cache`、非 frozen 时会把包 cp 进缓存（`lib/bundler/cli/install.rb:52-53` → `lib/bundler/runtime.rb:108-146` → `lib/bundler/source/rubygems.rb:233-242`）。
- 我方行为：`script/differential:635-653` 逐行读工程相对路径，任一缺失即输出 `file-exists violated ($rel): ref_exists=<yes|no> cel_exists=<yes|no>`；`install-refreshes-app-cache` 用它断言 `vendor/cache/json_pure-2.8.1.gem` 存在。
- 判据：`bash script/differential install-refreshes-app-cache`
- 边界：只断言单个文件存活，不断言缓存目录整体内容；二进制包无法用 `file-contains` 断言故需要本通道。
- 生效：task-87
- 取代：无

## C-M7-7-018 空的 `file-absent`/`stderr-contains` 标记等同「未提供该标记」

- 状态：已实现
- 参考行为（4.0.24）：空标记若被当作断言，会产生「断言 stderr 为空」这种无法用 contains 表达的语义，故规范定义退化语义（`docs/differential-normalization.md:68-109`）。
- 我方行为：`script/differential:619-621` 与 `:516-525` 的注释分别写明退化语义，`:621-633`/`:528-545` 的实现都只对非空行生效；空或只含空行时不产生断言、不打印 N10 提示，stderr 回到逐字比较。
- 判据：`bash script/differential harness-assert-selftest`
- 边界：需要「断言 stderr 为空」时只能走逐字比较路径，不能靠空标记。
- 生效：task-7
- 取代：无

## C-M7-7-019 `stderr-contains` 命中后跳过逐字 stderr 比较并打印 N10 提示

- 状态：已实现
- 参考行为（4.0.24）：参考在用户代码抛异常时打印含机器路径的完整 backtrace，N6 只剥 `   from ...` 帧，异常后的上下文仍在，逐字比较不可能稳定（`docs/differential-normalization.md:68-109`）。
- 我方行为：`script/differential:516-548` 逐行读整行 needle（不做 tab 拆分，与 `file-contains` 不同），两侧 `grep -Fq` 都必须命中；命中时打印 `stderr compared by contains only (declared normalization N10)` 并跳过逐字 stderr，任一未命中则输出 `stderr-contains differs: needle=<needle>` 并不再去比 stderr。
- 判据：`bash script/differential plugin-hook-raise`
- 边界：只在夹具显式提供标记时生效；规范要求启用该通道的夹具必须同时精确断言 exit code、stdout 与受影响文件状态（当前唯一使用点 `plugin-hook-raise` 即如此）。
- 生效：task-7
- 取代：无

## C-M7-7-020 `deferred-<profile>` 标记把夹具在该 profile 记为 skipped

- 状态：已实现
- 参考行为（4.0.24）：同一夹具在不同 Bundler 版本下的可观察行为可能不同，显式延后优于放宽断言。
- 我方行为：`script/differential:710-713` 发现 `deferred-$bundler_version` 时打印 `SKIP <name> (deferred for <profile>: <首行原因>)` 并计入 skipped；`:719` 汇总行按 `passed / failed / skipped (documented deferrals)` 三态输出，`:720` 只在 failed 非零时失败。
- 判据：`BUNDLER_REF_VERSION=2.7.2 bash script/differential add-group`
- 边界：延后项不计入通过，只是不计入失败；每项须在夹具目录留下 `deferred-<profile>` 文件说明原因。
- 生效：task-3（M7(7) 于 2026-11-14 验收）
- 取代：无
