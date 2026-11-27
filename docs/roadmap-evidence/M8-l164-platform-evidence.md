# M8 L164 跨平台证据矩阵与剩余验收清单（task-276）

## 1. 结论

- **L164 最终可勾选。** 最低硬门已由 GitHub Actions run [`45975413773`](https://github.com/ShiningRay/celerite/actions/runs/45975413773) 在 `4e1faee0827fec85a6a18752a4db0e9ef288b995` 上闭合：Windows/Ubuntu × Bundler 4.0.24/2.7.2 四格均 success，四格 `summary.json` 均 `status=passed`，lock/install hot 四计数均 `{0,0,0,0}`；固定旧 binary `d9009b14a0bf18da62b7a85cfc68b2442c4446de` 在四格均非零且精确失败 `expected_miss_after_lock_tamper: stats={0, 0, 0, 0}`。task-276 当时的“不可勾”结论保留为历史，由本文 §9 最终闭合说明取代。
- 本机 Windows 只有 task-269/272/273/274 的历史实证与当前基线内的测试面；**task-276 没有复跑任何 Crystal、build、spec、differential 或 Rails**，不能把历史结果改写成本轮实测。
- Ubuntu 本机仍未验证；GitHub Actions 四格 CI 已全绿，但 CI 不等于 Ubuntu 本机实测。task-276 本身未复跑门禁；task-291 只独立核对 run/job/artifact 与旧 binary 精确失败证据，未运行 Crystal、build、spec、differential 或 Rails。
- 第二 ABI、JRuby/TruffleRuby/shim、真实 ACL、多进程并发、bridge idle-timeout、Windows rename/ACL/symlink/junction、大小写与路径边界、跨文件非原子、硬终止均未验证。
- 本文只做证据审计与补证设计，不实现产品，不修改 roadmap 复选框、claims、CI 或任何 `src/spec` 文件。

## 2. 证据口径

| 标记 | 含义 | 能否关闭 L164 |
|---|---|---|
| `W-HIST` | 先前任务在本机 Windows 上的真实命令/spec 结果，有仓库记录或任务回报 | 只能证明历史 Windows 局部覆盖 |
| `W-SPEC` | 当前基线源码/spec 显示的测试面；task-276 未执行 | 不能单独作为本轮实测 |
| `DESIGN` | workflow、脚本、schema 或测试设计已写入参考树 | 不能写成 CI 已通过 |
| `UNVERIFIED` | 没有对应环境或命令的实际结果 | 保持开放 |
| `CI-GREEN` | 指定提交的 GitHub Actions 单元、日志和 artifact 均实际成功 | 四格齐备才满足最低 CI 正门 |

路径行号均以本次只读检查的基线或参考树为准。历史计数只标历史，不冒充 task-276 复跑。

## 3. 基线与参考树

- task-276 基线：`C:/Temp/celerite-t276`，HEAD `811569cb762e604d8cac54efd451cc1ca455b9ab`，检查时工作树干净。
- task-275 参考树：`C:/Temp/celerite-t275`，最终 HEAD `05d57daa4bd277b05234dac8da55468729d99db7`；该树是只读旁证，不是 task-276 基线。
- task-275 的门禁文件在 task-276 检查时尚未进入 `811569c`；首辅后续已将其并入 main 并完成本机真实门禁。本文保留 task-276 当时判定，另在 task-275 证据节记录合流后结果，不回写历史。

## 4. task-269/272/273/274/275 覆盖矩阵

“已覆盖”指测试或任务证据覆盖该行为面，不等于跨平台闭合。“回滚”特指失败后旧证书/旧 nonce/旧锁字节是否保持可用；“parity”区分输出、锁、树与 exit，不混为一体。

| 任务 | 正门 | 负门 | 回滚/失败路径 | 输出/锁/树/exit parity | stats-off | 旧 binary 能力门 |
|---|---|---|---|---|---|---|
| task-269 | `W-HIST`：默认 `plugins=true`、空插件证书、热 install 四计数 `{0,0,0,0}`；目标族 65/0 | `W-HIST`：plugin_names/warnings、unknown/broken/变化 fingerprint、缺坏证书、非空插件根/索引、动态 eval 回落 | `W-HIST`：证书同目录 temp+fsync+rename，损坏删除；尚未形成 task-274 的完整跨文件事务 | `W-HIST`：Bundler 4.0.24/2.7.2 的 `install-noop-summary`、`install-rerun` 各 1 passed，含 stdout/stderr/lock/tree/exit | 无 | 有 b916df7 旧 binary 热路径反假绿，但不是 d9009b1 定向 capability 门 |
| task-272 | `W-HIST`：六叶层 57/0；RubyIdentity 纯文件事实、v2 success certificate、静态 DSL allowlist | `W-HIST`：首个 shim 不跳过、batch shim、错误 PATH 分隔符、断链/循环链、布局不成立、legacy/v2 evaluation-only、身份/证书不匹配、动态/反射/文件依赖 DSL | `W-HIST`：非法 certificate 写入保留旧字节，独立 nonce 可共存，失败无 `.tmp` | 叶子层不以命令级完整 parity 为交付；不能替代 lock/install 端到端门 | 无 | 无 |
| task-273 | `W-HIST`：三目标 54/0；锁原始 SHA/大小/行尾/语义段、根迁移不变、CHECKSUMS 固定投影 | `W-HIST`：任意字节/注释、LF↔CRLF、BUNDLED WITH、CHECKSUMS、PLATFORMS、parser revision、legacy/evaluation-only、`lock --print` 不发证书、输出前重渲染校验 | `W-HIST`：无效事务保留旧 nonce；Windows 只读锁替换失败 exit 23，旧锁/entry/record 保留且无 temp | `W-HIST`：负门走兼容路径，锁字节与 `Writing lockfile` 行有断言；未做四格全项目树 manifest parity | 无 | 无 |
| task-274 | `W-HIST`：focused 309/0；install/plugin nonce 轮换、plan digest、ProcessLock 内重验锁与安装树、双 profile 热四计数 0 | `W-HIST`：attempt→lock 间篡改、树内容变化、缺 RuntimeRecord、错 command certificate、eval/plugin/record 写失败、after-install hook 失败 | `W-HIST`：旧 nonce/commit markers 保持，plugin 证书回滚，最终 record 失败不假命中，恢复旧 nonce 可用 | `W-HIST`：双 profile 无变化 stdout/stderr/lock/exit parity；安装树完整性与 stale 重验已覆盖；四格全项目树 manifest 仍待 task-275 | 无 | 无 |
| task-275 | `W-LOCAL`：首辅本机 Windows 构建当前 binary，4.0.24/2.7.2 driver 均 PASS；lock/install hot 四计数严格为 0，并比较 exit、归一化 stdout、去 stats stderr、锁原始字节、树 manifest | `W-LOCAL`：锁行尾/注释、安装树内容、插件索引四类负门；stats-off 真实失败关闭 | 未新增跨文件崩溃回滚覆盖 | `W-LOCAL`：双 profile 五类 parity 已跑；CI 四格仍未运行 | `W-LOCAL`：driver 内 stats-off 门与纯 Ruby parser 测试通过 | `W-LOCAL`：固定 d9009b1 旧 binary focused 例精确失败 `expected_miss_after_lock_tamper: stats={0, 0, 0, 0}`；CI 四格仍未运行 |

### 4.1 task-269：默认插件正门与残余动态 DSL

- 证书只含 `format/digest/plugin_names`，由真实成功求值绑定，不静态猜测 `Plugin::DSL`；见 `docs/compat-evidence/2026-11-25.md:224-243`。
- 默认热 install 四计数为 0；plugin_names 非空、warnings、unknown/broken fingerprint、缺坏证书、非空插件根/索引均回落。
- 双 profile `install-noop-summary`/`install-rerun` 是历史 Windows 定向差分，不是四格 CI。
- 未识别 `rand`/time/反射生成的 plugin 声明仍是残余；证书不能证明任意动态 Ruby 无副作用，见 `docs/compat-evidence/2026-11-25.md:247-252`。

### 4.2 task-272：身份、v2 证书与静态 DSL

- `RubyIdentity` 只从文件路径、大小、mtime、SHA-256 与唯一 rbconfig 推导，不启动 Ruby；见 `src/celerite/cache_identity.cr:297-397,399-475`。
- 测试面覆盖 path-free JSON、`CELERITE_RUBY`→PATH、首个 shim、batch shim、断链/循环链、同秒内容变化与根迁移；见 `spec/m8_task272_identity_spec.cr:82-205`。
- v2 证书按 nonce 提交，非法证书不覆盖旧字节；见 `spec/m8_task272_identity_spec.cr:208-251`。
- 静态 DSL 只接受 plain/gemspec/group/evalchain；rand/time/reflection/send/eval/heredoc/alias/interpolation/Dir/File/未知调用均 `unknown:unproven-static`；见 `spec/m8_task272_static_dsl_spec.cr:25-67`。
- 这些 spec 在 task-276 未运行；其存在不证明 Ubuntu、第二 ABI 或真实 symlink/junction 行为。

### 4.3 task-273：锁原始字节门与写失败

- `LockIdentity` 覆盖 raw SHA-256、byte size、LF/CRLF/mixed、parser revision、BUNDLED WITH、CHECKSUMS 投影与 PLATFORMS；见 `src/celerite/cache_identity.cr:80-188`、`spec/m8_task273_lock_bytes_spec.cr:47-121`。
- 同目录原子替换与 CRLF 保留有测试；Windows 只读属性触发 `PermissionError`，旧字节保留且无 temp；见 `spec/m8_task273_lock_bytes_spec.cr:124-157`。
- 命令级负门覆盖 LF→CRLF、BUNDLED WITH、CHECKSUMS、PLATFORMS、parser revision、legacy/evaluation-only；输出前发现渲染字节变化时仍走兼容路径；见 `spec/m8_lock_fast_path_spec.cr:792-943`。
- 热路径写失败要求 exit 23、`procs=0`、旧锁/entry/record 不变；最终 record 写失败继续兼容回落；见 `spec/m8_lock_fast_path_spec.cr:966-1009`。
- Windows read-only attribute 不是真实 NTFS ACL；同目录 rename 成功也不等于跨盘、打开句柄、杀毒软件或目录 ACL 场景已验证。

### 4.4 task-274：install 最终化与有限回滚

- 热命中轮换 install/plugin nonce，旧 eval certificate 保留；见 `spec/m8_install_fast_path_spec.cr:510-526`。
- 在 ProcessLock 内重验安装树与锁，attempt→lock 间变化必须 stale 回落；见 `spec/m8_install_fast_path_spec.cr:568-628`。
- plan digest 对安装内容敏感，对 cache/vendor/cache/其它平台噪声不敏感；见 `spec/m8_install_fast_path_spec.cr:630-664`。
- after-install hook 失败、最终 RuntimeRecord 写失败、plugin 证书写失败、eval entry 不可写均有旧状态/无假命中断言；见 `spec/m8_install_fast_path_spec.cr:666-794`。
- 双 profile 无变化 stdout、用户 stderr、锁字节与 exit 对齐；见 `spec/m8_install_fast_path_spec.cr:796-817`。
- 这些是单进程故障注入与 TOCTOU 窗口测试，不是多进程竞争、真实 ACL、磁盘满、断电或 SIGKILL 证明。

### 4.5 task-275：本机真实门禁已通过，四格 CI 尚未运行

- 四格 matrix 定义在 `.github/workflows/fast-path-gates.yml:14-22`；每格安装 Crystal/Ruby/Bundler、构建当前 binary、运行 driver、stats-off 负门、当前 capability 正门，再构建旧 binary 并运行同一 capability 负门。
- 首辅合流后在短路径 `C:\temp\celerite-gate275` 构建当前 binary，修正 Ruby `File.write` 的 Windows CRLF 指纹偏差与 tree manifest 大小写前缀偏差；Bundler 4.0.24 与 2.7.2 的 `script/fast-path-gates` 均 PASS/EXIT=0。
- driver 严格解析唯一四计数行，固定一次 PATH，file:// 本地源；lock/install 各比较 exit、归一化 stdout、去 stats stderr、锁原始字节与树 manifest。四类负门先 hot0 再真实 `procs>=1`；stats-off 必须失败关闭。
- focused capability 先以 legacy explicit-false 热路径证明 0，再追加锁注释，要求 `procs>=1`、无 hit、miss `verdict:certificate-lock`。
- 固定 `d9009b1` 旧 binary 已在本机构建并跑同一例：EXIT=1、1 failure，精确 `expected_miss_after_lock_tamper: stats={0, 0, 0, 0}`，证明到达锁篡改点而非提前证书/环境失败。
- **workflow 文件存在和本机 Windows 局部 PASS 都不是 CI-GREEN。** 四格 run URL、commit SHA、binary SHA、日志与 artifact 仍缺。

## 5. 平台与边界证据矩阵

| 环境/边界 | 当前证据 | 状态 | 关闭所需证据 |
|---|---|---|---|
| 本机 Windows，当前提交 | 完整 spec 1393/0/0/0；M8 家族 309/0；task-275 双 profile driver PASS；固定旧 binary 定向负门精确失败 | `W-LOCAL`，局部 | 四格 CI 与下述平台边界 |
| Ubuntu 本机 | 无 | `UNVERIFIED` | Ubuntu 实机命令与日志；若验收只接受 CI，也须明确记录本机仍未验证 |
| GitHub Windows × 4.0.24 | run `45975413773` @ `4e1faee`；job `140425798675`；artifact `15185899854`；`summary=passed`、hot `{0,0,0,0}`、旧 binary 精确 tamper FAIL | `CI-GREEN` | 无（本行最低门已闭合） |
| GitHub Windows × 2.7.2 | run `45975413773` @ `4e1faee`；job `140425798221`；artifact `15187555618`；`summary=passed`、hot `{0,0,0,0}`、旧 binary 精确 tamper FAIL | `CI-GREEN` | 无（本行最低门已闭合） |
| GitHub Ubuntu × 4.0.24 | run `45975413773` @ `4e1faee`；job `140425798534`；artifact `15186722159`；`summary=passed`、hot `{0,0,0,0}`、旧 binary 精确 tamper FAIL | `CI-GREEN` | 无（本行最低门已闭合） |
| GitHub Ubuntu × 2.7.2 | run `45975413773` @ `4e1faee`；job `140425798626`；artifact `15187376171`；`summary=passed`、hot `{0,0,0,0}`、旧 binary 精确 tamper FAIL | `CI-GREEN` | 无（本行最低门已闭合） |
| 旧 binary d9009b1 定向负门 | 四格均从 `d9009b14a0bf18da62b7a85cfc68b2442c4446de` 构建，均 `1 examples, 1 failures, 0 errors, 0 pending`，精确 `expected_miss_after_lock_tamper: stats={0, 0, 0, 0}` | `CI-GREEN`（四格） | 无（本行最低门已闭合） |
| 第二 Ruby ABI / target-rbconfig | 三 ABI 视图的结构性 spec 存在 | `UNVERIFIED` | 第二 ABI 的真实 cold/warm/hot、输出/锁/树/exit parity 与负门 |
| JRuby / TruffleRuby | 无 | `UNVERIFIED` | 真实解释器矩阵；不支持时须证明 `RubyIdentity=unknown` 并安全回落 |
| shim / wrapper | task-272 有“首个 shim 不跳过”的 Windows spec | `UNVERIFIED`（跨平台/真实 wrapper） | Windows/Unix shim、batch、wrapper、断链、循环链实跑 |
| 真实 NTFS/POSIX ACL | 只有 Windows read-only attribute 与路径占位失败 | `UNVERIFIED` | 拒绝目录/文件/rename 的真实 ACL，旧状态与 exit parity |
| Windows rename | 同目录 `File.rename` 与只读替换 spec | `UNVERIFIED`（真实边界） | 目标存在、只读、打开句柄、目录 ACL、大小写/短名等场景 |
| symlink / junction | task-272 文件 symlink spec；无权限时 symlink 专属断言条件化，非 symlink 身份/布局断言仍执行且完整 spec 0 pending | `UNVERIFIED`（跨平台/真实权限差异） | Unix symlink、Windows symlink/junction、项目根/缓存根/锁路径重定向 |
| 大小写与路径 | driver 有 Windows file URL/路径归一化纯 Ruby 测试 | `UNVERIFIED`（真实 FS） | 大小写敏感 FS、仅大小写差异路径、空格、Unicode、盘符/UNC/长路径 |
| 跨文件非原子 | 设计顺序 EvalCache→Plugin→RuntimeRecord，失败有限回滚 | `UNVERIFIED`（故障一致性） | 每个提交点注入失败，验证旧 nonce 可用、无半状态假命中 |
| 硬终止 / 断电 / SIGKILL | 无 | `UNVERIFIED` | 明确契约后做 kill/断电注入；若要求 exit 与证书原子，则当前设计不满足 |
| 多进程并发 | ProcessLock 获取与单进程 TOCTOU 重验 spec | `UNVERIFIED` | 多进程同时 lock/install/热命中/篡改，验证锁、树、证书与 exit |
| bridge idle-timeout | 既有 bridge reuse spec 不等于 L164 四格证据 | `UNVERIFIED` | 冷/温/热跨 idle-timeout 的真实命令与四计数/parity |
| mtime 精度 | task-272 合成 second/ns 数据测试 | `UNVERIFIED`（平台实测） | Windows/Unix 文件系统实际 mtime 精度与同秒替换 |
| 真实 gem index / Rails | task-275 只使用仓库内 `file://` gem index | `UNVERIFIED` | 如纳入验收，补真实 index/Rails 的 cold/warm/hot 与失败路径 |
| 完整 spec / 全量 differential | 合流后完整 spec 1393/0/0/0；受影响双 profile 定向差分通过 | `W-LOCAL`；全量 differential 未跑 | 最终提交上重跑受影响 differential 并保存结果；完整 spec 在后续产品变更后重跑 |

设计依据：`docs/roadmap-evidence/M8-l164-remaining-plan.md:182-223,239-317,415-446`；`docs/roadmap-evidence/M8-fast-path-plan.md:278-301`。二者都明确：跨文件事务不是硬终止原子性，单平台通过或把硬终止伪称解决均不能勾选 L164。

## 6. 剩余验收清单

### 6.1 L164 最低硬门

- [ ] **G1 四格 CI 正门实际全绿。** 同一提交、同一当前 binary，四格均完成 lock/install hot 四计数 0、五类 parity、四类负门、stats-off 失败关闭、当前 capability 正门；保留 run URL、commit SHA、binary SHA-256、`summary.json` 与日志。
- [ ] **G2 旧 binary 定向负门实际全绿。** 四格均从 `d9009b14a0bf18da62b7a85cfc68b2442c4446de` 构建，能力例非零且命中 `expected_miss_after_lock_tamper: stats=`；不得接受编译错误、缺证书错误或例名匹配。
- [ ] **G3 证据回填。** 将实际 run/日志/artifact 写入证据文档，更新四格状态为 `CI-GREEN`；不得只写 workflow 路径或“已配置”。
- [ ] **G4 最终复核。** 在最终提交上重跑受影响门禁；若合并 task-275 后代码/配置/环境有变，必须重跑，不得复用旧绿灯。

### 6.2 平台与故障边界补证

- [ ] **B1 Windows rename/ACL/symlink/junction。** 覆盖目标存在、只读、真实 ACL 拒绝、打开句柄、symlink/junction 重定向；验证旧锁/证书与 exit。
- [ ] **B2 大小写与路径。** 在大小写敏感 FS 与 Windows 分别覆盖仅大小写差异、空格、Unicode、UNC/盘符/长路径；不得只用字符串归一化单测代替真实命令。
- [ ] **B3 第二 ABI 与解释器。** 第二 ABI、JRuby/TruffleRuby、shim/wrapper 逐一给出支持矩阵；不支持者必须真实回落且无假命中。
- [ ] **B4 多进程并发。** 同时运行 lock/install/热命中/篡改，验证 ProcessLock、安装树、证书 nonce 与输出/exit。
- [ ] **B5 idle-timeout。** 跨 `CELERITE_BRIDGE_IDLE_MS` 的冷/温/热序列，确认热路径仍 0/0/0/0，温路径按真实 bridge 计数回落。
- [ ] **B6 跨文件故障与硬终止。** 注入 EvalCache/Plugin/RuntimeRecord 各提交点失败；另对 SIGKILL/断电明确“best-effort 回滚”还是“原子提交”契约。若验收要求后者，当前设计不得通过。
- [ ] **B7 完整回归。** 最终提交运行完整 spec、受影响 differential 与 format/build/diff 门禁；真实 index/Rails 是否属于 L164 关闭条件须由验收人明确，不得默默略过。

### 6.3 task-276 文档验收条件

- [ ] 只新增 `docs/roadmap-evidence/M8-l164-platform-evidence.md`，一笔提交，不 push。
- [ ] 明确区分 `W-HIST`、`W-SPEC`、`DESIGN`、`UNVERIFIED`、`CI-GREEN`，没有把历史或静态存在写成本轮/CI 实测。
- [ ] 逐任务覆盖正门、负门、回滚、输出/锁/树/exit parity、stats-off、旧 binary capability。
- [ ] 四格 CI 与旧 binary 实际绿灯前明确写出“L164 不可勾选”。
- [ ] 未验证项完整列出：Ubuntu 本机、四格 CI、第二 ABI、JRuby/shim、真实 ACL、并发、idle-timeout、Windows rename/symlink/junction、大小写/路径、跨文件非原子、硬终止。
- [ ] 给出后续补证顺序与每项所需证据；不实现产品。
- [ ] 提交前 `git diff --check` 通过，CodeRabbit `CR=0`，文件尾为一个 LF，正文无 CR。

## 7. 后续补证顺序

1. **集成 task-275 门禁文件。** 将参考树 `05d57da` 的 workflow/driver/test/capability 变更加入目标基线，固定旧 commit 与当前提交 SHA；此步只集成门禁，不借机改产品语义。
2. **重做静态与轻量门。** Ruby 语法、driver 单测、YAML 解析、diff check；随后构建当前 binary 与 d9009b1 旧 binary，记录 SHA-256。
3. **先跑四格当前正门。** 每格独立保存 lock/install hot、五类 parity、四类负门、stats-off 与当前 capability 日志；任一失败先修门或产品，不以 skip 代替。
4. **再跑四格旧 binary 负门。** 必须到达锁篡改断言并出现精确 stats 失败文本；这是反假绿门，不与当前正门合并计数。
5. **补 Windows/Unix 文件系统边界。** rename、真实 ACL、symlink/junction、大小写、路径、mtime、跨盘行为；Ubuntu 本机若未跑，继续标未验证。
6. **补解释器/ABI/并发/idle-timeout。** 第二 ABI、JRuby/TruffleRuby/shim、多进程与 idle 窗口逐一形成真实证据。
7. **裁定跨文件与硬终止契约。** 先注入普通提交点失败；若要求硬终止原子性，先改设计再验证，否则明确接受 best-effort 边界并保留风险。
8. **最终安静窗口。** 在最终提交运行完整 spec、受影响 differential、format/build/diff；收齐四格与旧 binary artifact 后，才可讨论勾选 L164。

## 8. task-276 本轮实际执行边界

- 已做：只读检查基线/参考树、源码/spec、历史 claims/evidence、task-275 workflow/driver/test/capability；形成本矩阵与补证清单。
- 未做：Crystal、build、spec、differential、Rails、真实 lock/install、GitHub Actions、当前/旧 binary 构建与能力门、Ubuntu、第二 ABI、真实 ACL、并发、idle-timeout、硬终止。
- 因此本文所有产品行为结果均继承历史证据或标为未验证；本文不宣告 L164 闭合。

## 9. task-291 最终闭合说明（2026-11-27）

- 最终基线：`C:\Temp\celerite-t291`，HEAD `4e1faee0827fec85a6a18752a4db0e9ef288b995`。GitHub Actions run [`45975413773`](https://github.com/ShiningRay/celerite/actions/runs/45975413773) 为 `completed/success`；四格 job 均 `completed/success`，`Lightweight driver checks`、`Build current binary`、`Run fast-path CI gates`、`Require stats-off`、`Verify current capability`、`Build old binary`、`Require old binary fail` 关键步骤均 success。
- 四格证据矩阵：

| 平台 / Bundler | job | artifact | `summary.json` | lock/install hot | lock / install 锁 SHA-256 |
|---|---|---|---|---|---|
| Windows / 2.7.2 | [`140425798221`](https://github.com/ShiningRay/celerite/actions/runs/45975413773/job/140425798221) | `15187555618` | `status=passed`，`platform=mingw32` | `{0,0,0,0}` / `{0,0,0,0}` | `9ee90536714d0debaf1f6cce4d614ce5c436256a01845f729a40f68519911f31` / `01cd1b24d5d70aad634cf64fb6110c81fc77df0a9bee6c3a91299a683ad59ada` |
| Ubuntu / 4.0.24 | [`140425798534`](https://github.com/ShiningRay/celerite/actions/runs/45975413773/job/140425798534) | `15186722159` | `status=passed`，`platform=linux` | `{0,0,0,0}` / `{0,0,0,0}` | `d39afaa9e77a1e004b599d8dcfe5314091d1a14802b57dff13f3f200819804a4` / `3be3b6be54551428aa46bfacb30686893c2492efe32cb550a492f22ef237f80f` |
| Ubuntu / 2.7.2 | [`140425798626`](https://github.com/ShiningRay/celerite/actions/runs/45975413773/job/140425798626) | `15187376171` | `status=passed`，`platform=linux` | `{0,0,0,0}` / `{0,0,0,0}` | `9c5760c39ec86fcce956870cfb04a2adcd81e7cbe55a107a696926e95433900e` / `d7fd45b91b3ac201382318754ac7a8c3464647a89599bfcb691d9eb6a2d467d9` |
| Windows / 4.0.24 | [`140425798675`](https://github.com/ShiningRay/celerite/actions/runs/45975413773/job/140425798675) | `15185899854` | `status=passed`，`platform=mingw32` | `{0,0,0,0}` / `{0,0,0,0}` | `86d43878a6c1d15b39862864719fb75e8d492a5f8ae014ed55c1285dbc688c90` / `58600f5368ad2c72607828be429918a950b40bef45040d539e9153c462630221` |

- 四格日志共同实测：`bin_stubs_test: 1 checks, 0 failures`、`fast_path_gates_test: 12 checks, 0 failures`、`fast-path-gates: PASS profile=<版本>`；stats-off 负门精确失败 `expected exactly one bridge stats line, got []`。四类锁字节/锁注释/安装树/插件索引负门均包含在 driver 的 `summary.json` 中，current capability 步骤均 success。
- 固定旧 commit `d9009b14a0bf18da62b7a85cfc68b2442c4446de` 构建的旧 binary 在四格均得到 `1 examples, 1 failures, 0 errors, 0 pending`，精确失败 `expected_miss_after_lock_tamper: stats={0, 0, 0, 0}`；断言位置 `spec/m8_install_fast_path_spec.cr:1564`，failure trace 另见 `:1577`。这证明到达锁篡改点，而非编译、证书或环境提前失败。
- 逐项复核 L164：无变化 `lock`/`install` 使用 lockfile/安装计划且不启动 Ruby，由四格 lock/install hot 四计数全 0 证明；动态 DSL、插件或指纹不确定时显式走兼容路径，由静态 Unknown 回落与四类真实 `procs>=1` 负门证明；输出、锁、树与退出码 parity 由 driver 对 `CELERITE_FAST_PATH=0` 的比较证明。最低 CI 正门与旧 binary 反假绿门闭合，故只勾 `docs/roadmap.md:164`。
- 残余未验证：Ubuntu 本机、第二 ABI、JRuby/TruffleRuby/shim、真实 ACL、多进程并发、idle-timeout、Windows rename/symlink/junction、大小写与真实路径边界、跨文件非原子、硬终止、真实 index/Rails 与全量 differential 仍未验证；artifact 未单独归档 current binary SHA-256。以上均不冒充本行已闭合，也不宣称 L161/L165/L166 完成。
- task-291 执行边界：只独立核对 GitHub Actions run/job/artifact、更新文档、机械重建并校验 claims 索引；未运行 Crystal、build、spec、differential 或 Rails，未改源码/spec/其他 claim/甘特图，一笔提交不 push。
