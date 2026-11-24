# M8 L164「无 Ruby 快路径」闭合审计（task-268）

- 审计基线：`148f8556bbd15e96103b991be77a1029ef654df4`（detached worktree `C:\temp\celerite-t268`）。
- 审计方式：只读代码、文档、spec、git 历史与工作树状态；未运行 `crystal build/spec`、`shards`、Ruby harness 或 differential。
- 历史测试数字均来自仓库证据，不是本轮实测；本审计不把它们改写成“已复跑”。

## 一、结论

**现在暂不可勾 `docs/roadmap.md:164` 的 L164。**

| 验收块 | 现在可勾？ | 裁断 |
| --- | --- | --- |
| S8c（lock） | **暂不可勾 `[ ]`** | 热 lock 已有零进程实现和历史绿灯，但未闭合判据 7（runtime 可执行文件变化）、判据 9 的原文（`PluginHooks.enabled?`）、判据 10 的任意锁字节变化；判据 11 还缺直接负例。 |
| S8d（install） | **暂不可勾 `[ ]`** | 继承 S8c 的共享门缺口；并且默认启用插件时会先做一次 Ruby 插件预检，因此“默认配置热 install 四计数全零”尚未成立。现有零计数夹具显式关闭插件。 |
| S8e（负向矩阵） | **暂不可勾 `[ ]`** | 代码层矩阵较完整，但计划要求的旧二进制 FAIL 固定进 CI、完整负向矩阵的 Bundler 参考差分、Linux/macOS 与第二 ABI 等仍未提供。 |

已成立的部分：

1. 在现有夹具条件下，第二次无变化 bare `lock` 与 bare `install` 的历史测试确实是 `procs=0 rpc=0 req_bytes=0 resp_bytes=0`；坏 bridge 热命中也不访问 bridge。
2. 多数输入、runtime、锁、指纹、插件根、安装树缺失与输出配置变化均保守回落 Ruby。
3. lock 输出、锁字节、install 两行汇总、组/路径提示、项目树/安装树与退出码均有 parity 断言。
4. task-265 已修正 Bundler 2.7 的无变化 install 汇总计数，并与 Bundler 4.0.24 分别对齐。

未成立的核心是：**“默认 install 不需要 Ruby”以及“判据所列的 runtime/lock/plugin 变化都必然回落”仍各有实现缺口；S8e 的自动化与平台证据也不足。**

## 二、审计依据与范围

### 2.1 L164 与 M8 总验收

- `docs/roadmap.md:155-164`：M8 的目标是减少进程与 Ruby 分配，不改变 M7 的依赖选择和输出；L164 要求无变化 lock/install 不使用 Bundler/Ruby，动态 DSL、插件或指纹不确定时明确走兼容路径。
- `docs/roadmap.md:165-166`：L165（plan cache）与 L166（只读命令/index/benchmark）是独立行，本审计不把它们并入 L164。
- `docs/roadmap.md:168`：M8 总验收还要求指纹失效差分反例、缓存复用保持输出/依赖/文件字节/exit，以及 benchmark 的 wall/CPU/RSS/RPC/I/O。L164 只承担其中快路径正确性与零进程部分；最终 M8 仍需另看 L165/L166。

### 2.2 闭合判据

- `docs/roadmap-evidence/M8-fast-path-plan.md:234-257` 列出 12 条判据；`:278-288` 把 L164 绑定为 S8c + S8d + S8e 全绿，并要求旧二进制 FAIL 进入 CI。
- `docs/roadmap-evidence/M8-fast-path-plan.md:273-274` 明确声明：安装树不逐字节校验已安装 gem 内容，与 Bundler 边界一致。
- `docs/compat-claims/M8-batch-bridge.md:205-219` 为 C-M8-1-018/S8c；`:221-234` 为 C-M8-1-019/S8d；`:271-283` 为 C-M8-1-022/S8e；`:261-269` 为 C-M8-1-025/task-265。

## 三、逐项覆盖矩阵

| 计划判据 | 代码/测试证据 | 审计结果 |
| --- | --- | --- |
| 1. 无变化 lock 零 spawn，第二次 stdout 与第一次逐字节相同 | `spec/m8_lock_fast_path_spec.cr:223-240,435-489` | **通过（历史证据，未复跑）**。第二次 `procs=0 rpc=0 req_bytes=0 resp_bytes=0`，stdout 精确为 `Writing lockfile to ...\n`。 |
| 2. 无变化 install 零 spawn 且汇总逐字对齐 | `spec/m8_install_fast_path_spec.cr:303-345,547-571` | **部分通过**。关闭插件后的 install 已断言四计数为零；默认插件启用时会先 spawn。计划原文固定 `1 gem`，对 Bundler 2.7.2 已被 task-265 修正为 `2 gems`，需按 profile 对齐。 |
| 3. 坏 bridge 服务端热命中仍成功；旧二进制必须 FAIL | `spec/m8_lock_fast_path_spec.cr:435-489`；`spec/m8_install_fast_path_spec.cr:338-345`；`docs/compat-evidence/2026-11-25.md:55-64` | **代码层通过，CI 未固定**。热路径四计数为零且不访问 bridge；旧二进制反例有历史证据，但 CI 无此作业。`CELERITE_BRIDGE_SERVER` 不参与环境签名，见 `src/celerite/bridge/client.cr:235-256`。 |
| 4. 冷路径 `procs=1`，状态文件在命令结束后才出现 | `spec/m8_lock_fast_path_spec.cr:151-167,465-489`；`spec/m8_install_fast_path_spec.cr:303-312` | **通过（历史证据，未复跑）**。spec 实际断言 `procs >= 1`，不是严格的 `== 1`；若判据要求逐字 `1`，应补严。 |
| 5. Gemfile 内容变化失效，下一次回热 | `spec/m8_lock_fast_path_spec.cr:243-415`；`spec/m8_install_fast_path_spec.cr:347-383,625-644` | **通过**。文件哈希、扩展 Gemfile、项目 gemspec 均有正/负例。 |
| 6. install 计划缺项失效并重装 | `spec/m8_install_fast_path_spec.cr:385-449,573-623`；`src/celerite/install_fast_path.cr:211-238` | **通过**。缺 gemspec、gem 目录、native marker、InstalledIndex 不可解析均回落。安装内容不逐字节校验是已声明边界。 |
| 7. runtime 变化失效 | `spec/m8_lock_fast_path_spec.cr:491-564`；`spec/m8_install_fast_path_spec.cr:601-623`；`spec/m8_fast_path_store_spec.cr:232-358` | **不完整**。engine/version/platform/RubyGems/Bundler/default-gem-dir 与三 ABI 视图精确比较；缺少计划要求的 Ruby 可执行文件身份/大小/mtime。 |
| 8. 动态 DSL 永不产生状态 | `spec/m8_lock_fast_path_spec.cr:451-470`；`spec/m8_install_fast_path_spec.cr:451-470,646-666`；`assets/bridge/server.rb:475-524` | **通过**。ENV、glob、动态 `eval_gemfile` 等为 unknown，不能写/复用确定性记录。 |
| 9. 插件 index 或 `PluginHooks.enabled?` 为真即失效 | `spec/m8_lock_fast_path_spec.cr:653-700`；`spec/m8_install_fast_path_spec.cr:461-517,646-666` | **不满足判据原文**。非空本地插件根、声明插件、启用 hooks 有覆盖；但 `PluginHooks.enabled?` 默认为 true，lock 仍可在空插件根命中，install 会先 spawn。 |
| 10. 锁文件被手工改版本即失效 | `spec/m8_lock_fast_path_spec.cr:399-415,491-564`；`src/celerite/lock_fast_path.cr:122-176` | **部分通过**。CHECKSUMS 空、附加平台、PATH source 有负例；任意锁文件字节变化没有摘要门。 |
| 输出/锁/树/exit 对齐（补充） | `spec/m8_lock_fast_path_spec.cr:418-432,491-564,628-643`；`spec/m8_install_fast_path_spec.cr:315-345,547-666`；`spec/m8_fast_path_matrix_support.cr:53-99` | **代码层通过**。共享 writer/summary；负向 full parity 是路径/换行归一化后比较，不是所有平台逐字节输出。Bundler 参考只覆盖两条无变化路径。 |
| 11. 失败命令不写半截状态 | `src/celerite/lock_fast_path.cr:178-223`；`src/celerite/cli/commands_install.cr:153-176` | **实现顺序正确，证据不足**。只在成功路径后 remember，持久化错误被吞掉；未找到“命令失败不得写 record”的专门 spec。 |
| 12. 同时断言 `req_bytes=resp_bytes=0` | `spec/m8_lock_fast_path_spec.cr:435-489`；`spec/m8_install_fast_path_spec.cr:303-345,547-571` | **通过（历史证据，未复跑）**。需连同插件缺口一起看默认 install。 |

## 四、产品缺口

### P1：默认 install 仍先启动 Ruby 插件预检

调用序是：

1. `src/celerite/cli/commands_install.cr:263-271` 在 `InstallFastPath.attempt`（`:277`）之前调用 `install_gemfile_plugins`。
2. `src/celerite/plugin_gemfile.cr:25-30` 取得 `Bridge::Client.shared` 并 RPC `GemfileEvaluator.plugin_names`。
3. `src/celerite/plugin_hooks.cr:59-69` 仅在 false / `"false"` 时关闭；未设置时启用。
4. `spec/m8_install_fast_path_spec.cr:123-135` 的所有热夹具在 `:128` 写入 `BUNDLE_PLUGINS=false`。

所以现有“热 install 四计数全零”证明的是**关闭插件后的 install**，不是默认配置。`docs/compat-claims/M8-batch-bridge.md:225` 所称“插件预检之后、第一次 `Bridge::Client.shared` 之前”与实际调用序矛盾：预检本身就会调用 shared。

最小修正有二选一，必须由首辅裁定：

- **保持 L164 默认零 Ruby**：把插件判定改成无 spawn 的保守门。例如本地插件根为空、Gemfile/eval chain 确定性已证明且没有任何 `plugin` 声明时跳过 Ruby 预检；根非空、声明插件或扫描不确定时直接回落。相应修改 `src/celerite/cli/commands_install.cr`、`src/celerite/plugin_gemfile.cr`、`assets/bridge/server.rb`/缓存指纹，并补默认配置热 install 与坏 bridge 用例。
- **收窄 L164 边界**：明文要求 `BUNDLE_PLUGINS=false` 才能声明 install 无 Ruby，并同步改计划、claim 与 roadmap 描述；不能继续用当前夹具代表默认配置。

### P2：锁文件字节变化没有摘要门

- 计划要求任何锁文件字节变化/hash 不匹配都回落：`docs/roadmap-evidence/M8-fast-path-plan.md:177,255,265`。
- 实际 `src/celerite/lock_fast_path.cr:122-176` 检查 CHECKSUMS、精确平台、依赖相等、source 与 incomplete spec，但没有锁文件 SHA-256。
- `find_entry` 在 `src/celerite/lock_fast_path.cr:265-276` 只哈希 Gemfile/eval chain/gemspec；`src/celerite/fast_path_store.cr:43-123` 的 record 也没有 lock digest 字段。
- 现有反例只改 DEPENDENCIES（`spec/m8_install_fast_path_spec.cr:369-382`）或移除 checksum（`spec/m8_lock_fast_path_spec.cr:399-415`）。保持 checksum、依赖、平台与 source 合法而只改锁中版本时，没有测试证明会回落。

最小工作：在 record 中加入锁文件 SHA-256，`trusted_attempt` 精确比较；补“合法 checksum 不变、仅锁版本变化”的 lock/install 负例与 full parity。

### P3：runtime 记录不含 Ruby 可执行文件身份

- 计划把 `ruby.exe` 大小/mtime 变化或替换列为必然回落：`docs/roadmap-evidence/M8-fast-path-plan.md:140-141,250-251,267`。
- `src/celerite/runtime_facts.cr:141-217,267-320` 只从 rbconfig/RubyGems/Bundler 路径读取版本、平台、default gem dir 与 ABI；`engine`/`engine_version` 来自 bridge 记录。
- `src/celerite/fast_path_store.cr:43-123` 没有可执行文件路径、大小、mtime 或 hash。fast-path specs 也未找到对应变化用例。
- `docs/compat-claims/M8-batch-bridge.md:271-281` 明说“不加入 Ruby executable summary”。这与计划判据冲突，不能同时宣称两者都已闭合。

最小工作：把实际解析到的 Ruby 可执行文件身份（至少路径 + size + mtime，最好内容 hash）纳入 runtime facts/record，并补替换、touch/大小变化与 `CELERITE_RUBY` 切换负例。若决定不采纳此判据，必须显式修改计划与 claim，不能以“未声明”默认通过。

### P4：插件启用判据与 lock 实现不一致

- 计划 `docs/roadmap-evidence/M8-fast-path-plan.md:171,254` 要求 `PluginHooks.enabled?` 为 true 时回落，`procs=1`。
- lock 门 `src/celerite/lock_fast_path.cr:122-176` 不检查该设置；只检查本地 `<app_config>/plugin` 根（`:95-105`）。
- `spec/m8_lock_fast_path_spec.cr:27-33,54-77` 未关闭插件；`:686-700` 明确断言空插件根、默认插件启用时仍命中 `procs=0`。

这在“空根且 lock 不会执行 hook”的场景下可以是安全实现，但它不是计划原文。最小工作：要么让 lock 也遵守 `PluginHooks.enabled?` 原文，要么把判据修订为“已安装/声明且可能影响该命令的插件才回落”，并同步修改 spec 与 claim。

## 五、已覆盖的保守回落

| 变化 | 证据 |
| --- | --- |
| 任一开关关闭、非 `1`、eval cache 关闭 | `spec/m8_lock_fast_path_spec.cr:243-271`；`spec/m8_install_fast_path_spec.cr:473-484` |
| Gemfile/eval chain/项目 gemspec | `spec/m8_lock_fast_path_spec.cr:273-415`；`spec/m8_install_fast_path_spec.cr:347-383,625-644` |
| 缺失/损坏/错格式/错项目/错 namespace 的 record | `spec/m8_lock_fast_path_spec.cr:319-415`；`spec/m8_install_fast_path_spec.cr:601-623`；`spec/m8_fast_path_store_spec.cr:169-231,325-358` |
| 环境签名变化 | `spec/m8_install_fast_path_spec.cr:486-493`；`src/celerite/bridge/client.cr:245-256` |
| 三 ABI 视图独立篡改、runtime engine 变化 | `spec/m8_lock_fast_path_spec.cr:491-564`；`spec/m8_install_fast_path_spec.cr:601-623`；`spec/m8_fast_path_store_spec.cr:299-321` |
| 动态 DSL、声明插件、启用 hooks、非空插件根 | `spec/m8_lock_fast_path_spec.cr:451-470,653-700`；`spec/m8_install_fast_path_spec.cr:451-517,646-666` |
| CHECKSUMS 空、附加平台、PATH source | `spec/m8_lock_fast_path_spec.cr:399-415,524-564` |
| 安装树缺 spec/gem/native marker、索引损坏 | `spec/m8_install_fast_path_spec.cr:385-449,573-623` |
| frozen/deployment/shared-gems/force-ruby-platform/app-cache/local 等行为开关 | `spec/m8_install_fast_path_spec.cr:520-545,668-676`；`spec/m8_lock_fast_path_spec.cr:566-643` |

## 六、输出、锁、树与 exit 对齐

### lock

- 命中仍调用共享 `write_locked_lockfile`：`src/celerite/cli/commands.cr:3111-3131,3294-3315`。
- 共享 writer 负责序列化、BUNDLED WITH、2.x Bundler self-spec、stdout 和最终写入，因此正常 Ruby no-op 与快路径不会各写一套格式。
- `spec/m8_lock_fast_path_spec.cr:223-240` 断言精确 stdout、锁字节与 evaluation digest；`:418-432` 与 Ruby 路径逐字节比较 stdout；`:628-643` 保证 `lock --print` 继续走 Ruby。
- 已声明差异：lock 会重写文件，mtime 可变，但字节相同（`docs/compat-claims/M8-batch-bridge.md:205-219`）。

### install

- 热路径输出由 `src/celerite/install_fast_path.cr:158-164` 统一发出；普通路径在 `src/celerite/cli/commands_install.cr:937-973` 复用同一个 `Celerite::InstallSummary`。
- `spec/m8_install_fast_path_spec.cr:315-345` 对 Bundler 4.0.24/2.7.2 断言两行汇总、锁字节、连续热运行与 exit；`:547-571` 比较完整项目树/安装树。
- `spec/m8_fast_path_matrix_support.cr:53-99` 的树比较排除 `.celerite/cache`，其余项目/安装树按路径与内容哈希精确比较。
- stdout/stderr 的负向 full parity 会归一化路径分隔符、项目根与 CRLF（`:72-90`），所以不能表述为“所有负向用例在所有平台逐字节相等”；热路径正例则有直接字符串断言。

## 七、2.7 汇总修正

task-265 的修正成立：

- `src/celerite/install_fast_path.cr:9-68` 的 `InstallSummary.build` 在 `switched_bundler` 或 Bundler 版本以 `2.` 开头时把运行中的 Bundler 计为 +1；4.0.24 不计。
- 同一 `json_pure` 无变化安装：2.7.2 为 `2 gems now installed`，4.0.24 为 `1 gem now installed`；typed source 的隐藏 gem 在依赖侧与 spec 侧都不计入。
- `spec/m8_install_fast_path_spec.cr:246-345` 有精确文本与双 profile 断言。
- `docs/compat-evidence/2026-11-25.md:117-157` 记录 target 23/0、family 46/0、旧 `e65a80e` 反例 1 failure（expected 2, got 1）、合并后独立 58/0，以及两个 profile 的 `install-noop-summary` 各 1/0。
- 相关提交：`edd0ef5`（共享汇总）、`2ecb5e8`（双 profile 差分）、`415dd15`（证据记录）。

以上均为历史结果，本轮未复跑。C-M8-1-019 仍写 19/0，已被 C-M8-1-025 的 23/0 取代；闭合文档应避免继续引用旧计数。

## 八、S8e 与未验证项

### 已声明但未验证

`docs/compat-evidence/2026-11-25.md:59-64,152` 与 `docs/compat-claims/M8-batch-bridge.md:231-234,271-283` 明确列出：

- Linux / macOS；
- 第二 Ruby ABI、多 ABI / target-rbconfig；
- JRuby 或其他 shim；
- Rails 真实项目；
- 真实 index / 网络；
- 真实 ACL；
- 多进程并发与 ProcessLock 争用；
- bridge idle / timeout；
- 完整负向矩阵的 Bundler 参考差分。

当前 fast-path 的“full parity” oracle 是同一 celerite 二进制关闭快路径后的 compat 路径，不是 Bundler：`spec/m8_fast_path_matrix_support.cr:3-8`。Bundler 参考只跑了 `lock-noop` 与 `install-rerun`：`docs/compat-evidence/2026-11-25.md:22,55-64`。

### CI 缺口

- `.github/workflows/ci.yml:24-31` 未设置 `CELERITE_BRIDGE_STATS=1`，也没有零 spawn 快路径门。
- `:33-53` 只运行 `script/differential`；该脚本没有 `lock-noop`、`install-rerun`、`install-noop-summary` 或 fast-path 矩阵用例。
- 105 行 workflow 中没有旧二进制必须 FAIL 的作业，未满足 `docs/roadmap-evidence/M8-fast-path-plan.md:288`。
- spec job 是 Ubuntu，而 `spec/m8_fast_path_matrix_support.cr:18-20` 固定寻找 `bin/celerite.exe`；现有 CI 不能直接证明 Linux/macOS 快路径。

## 九、最小剩余工作

按依赖顺序：

1. **裁定插件边界**：决定默认 install 必须零 Ruby，还是 L164 明文要求关闭插件；同时决定 lock 是否遵守 `PluginHooks.enabled?` 原文。涉及 `src/celerite/cli/commands_install.cr`、`src/celerite/plugin_gemfile.cr`、`assets/bridge/server.rb`、`docs/roadmap-evidence/M8-fast-path-plan.md:171,254` 与两份 fast-path spec。
2. **补锁摘要门**：`src/celerite/fast_path_store.cr` 增加 lock digest，`src/celerite/lock_fast_path.cr:122-176` 精确校验；补合法 checksum 下仅版本变化的 lock/install 反例。对应判据 10。
3. **补 runtime 可执行文件身份**：`src/celerite/runtime_facts.cr`、`src/celerite/fast_path_store.cr` 与 runtime/store specs；对应判据 7。
4. **补半状态负例**：制造 lock/install 失败，断言不产生可复用 fast-path record；对应判据 11。实现顺序已正确，缺的是证据。
5. **固定 CI 门**：`.github/workflows/ci.yml` 增加四计数零断言、热路径正例、旧二进制反例必须 FAIL；计划要求见 `docs/roadmap-evidence/M8-fast-path-plan.md:288`。
6. **补参考差分**：`script/differential` 增加完整负向矩阵，至少覆盖 P1/P2/P3 与双 Bundler profile；不能继续用 compat 路径对齐代替 Bundler 对齐。
7. **补平台/边界证据**：Linux/macOS、第二 ABI、Rails、真实 ACL、并发/ProcessLock、真实 index、bridge idle/timeout；每项给出命令、版本、退出码与原始日志。
8. **最终安静窗口复跑**：在最终合并提交上重跑 format/build/spec/differential 与历史反假绿例，再改 roadmap。当前 task-268 安静窗口不执行这些命令。

## 十、首辅裁断所需输入

### A. 产品缺口（必须改码或显式改判据）

1. 默认 install 的 Ruby 插件预检是否允许存在？若不允许，需无 spawn 插件门；若允许，L164 必须写明关闭插件的边界。
2. 任意锁文件字节变化是否必须回落？当前无 lock digest；计划判据 10 的答案是“必须”。
3. Ruby 可执行文件替换/大小/mtime 变化是否必须回落？当前无该身份；计划判据 7 的答案是“必须”。
4. lock 是否必须在 `PluginHooks.enabled?` 为 true 时一律回落？当前实现与计划原文不一致。

### B. 证据缺口（实现可能正确，但不能据此勾选）

1. 失败命令不写 record 的直接 spec。
2. CI 的四计数零门与旧二进制 FAIL 门。
3. 完整负向矩阵的 Bundler 双 profile 差分。
4. Linux/macOS、第二 ABI、Rails、真实 ACL、并发、真实网络/index、bridge idle/timeout。
5. 若严格要求 cold `procs==1`，现有 spec 的 `>=1` 断言需收紧并留原始计数日志。

### C. 已声明边界（除非首辅改变范围，不应当作缺陷）

1. 已安装 gem 内容不逐字节校验：`docs/roadmap-evidence/M8-fast-path-plan.md:273-274`、`docs/compat-claims/M8-batch-bridge.md:231-234`。
2. `lock --print` 不走快路径，继续 Ruby 并逐字输出锁体：`spec/m8_lock_fast_path_spec.cr:628-643`。
3. 只接受可证明的 CRuby runtime；engine/ABI 不确定时回落，不猜 runtime。
4. lock 命中会重写锁文件，mtime 可变；承诺的是字节不变，不是 inode/mtime 不变。
5. 当前未加入 Ruby executable summary；这是与计划判据 7 的冲突项，不是自动豁免。

**建议裁断：L164 保持 `[ ]`；先关闭 A 中四项，再补 B 中 CI/差分/平台证据。仅补文档或仅重跑现有 Windows spec 不足以闭合。**
