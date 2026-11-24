# M8 六行闭合判据审计（task-238）

> 基线：`05402b6`（工作树 `C:\temp\celerite-t238`）。本轮只读：未改 `docs/roadmap.md` 复选框、`docs/compat-claims/`、`src/`、`spec/`、`fixtures/`、`script/`；未跑 `script/differential`。
> 证据口径：claims 断言 ID + 夹具/spec 文件名 + 提交 hash；证据报告只引节标题，不引主报告行号。凡本轮未实测者，见 §8。

## 0. 结论速览

| 行 | 判据（原文摘要） | 判定 | 缺项 | 一句话理由 |
|---|---|---|---|---|
| L161 | 版本化批次级求值协议 | 不可勾 | 3 | 版本化与 `evaluate_batch` 已落地，但插件声明与运行平台不在同一次导出内，「一次提交完整候选集」按设计未实现。 |
| L162 | 求值指纹 | 不可勾 | 2 | 指纹覆盖 Gemfile/eval 链/gemspec/版本，ENV 由缓存键全量覆盖；配置与 ABI 未入键。 |
| L163 | 桥复用与可观测性 | 不可勾 | 1 | 复用/idle/超时/结构化错误/统计均有实现与 spec，唯「批量大小控制」无实现。 |
| L164 | 无变化 `lock`/`install` 走快路径 | 不可勾 | 2 | 两条命令都在空操作短路之前起桥（`lock` 1 proc/2 rpc、`install` 1 proc/9 rpc）。 |
| L165 | 持久化解析/安装计划缓存 | 不可勾 | 5 | 持久化缓存存在，但缓存对象是求值结果而非解析/安装计划；键缺 source 身份、checksum、ABI、build 配置。 |
| L166 | 只读命令索引复用 + Rails 规模性能对照 | 不可勾 | 2 | 仅 `list` 无组选择零 spawn；`check`/`show` 仍起桥；无任何 Rails 规模 wall/CPU/RSS+RPC+I/O 报告。task-241 已提供 `docs/roadmap-evidence/M8-rails-bench.md` 的 Rails 8.0.2 三档壁钟/CPU/峰值 RSS+RPC 对照与两侧退出码比对（YJIT 本机不可验证、I/O 未采集），故「无报告」一项已改观，但该分句仍不成立。 |

缺项合计 15。六行无一可勾。

## 1. L161 — 版本化、批次级求值协议

> 原文（逐字）：`- [ ] 定义版本化、批次级求值协议：一次导出完整 dependencies、groups、source、autorequire、platform、Ruby 约束和插件声明；一次提交完整候选集并返回解，禁止在 PubGrub 循环中逐版本跨桥。`

### 分句判定

| # | 分句 | 判定 | 证据 / 缺口 |
|---|---|---|---|
| 1 | 定义版本化、批次级求值协议 | 满足 | `C-M8-1-003`（`PROTOCOL = 2`、`PROTOCOL_MIN = 1`、`BRIDGE_PROTO = 2`、`BRIDGE_PROTO_SUPPORTED = [1, 2]`、`ping.features`，见 `src/celerite/bridge/client.cr:14-15`、`assets/bridge/server.rb:32-48`）+ `C-M8-1-004`（`evaluate_batch` 单请求）；`spec/m8_bridge_proto_spec.cr`、`spec/m8_batch_eval_spec.cr`；`1f69d2f`、`65c69c2` |
| 2 | 一次导出完整 dependencies、groups、source、autorequire | 满足 | `bridge_serialize_evaluation`（`assets/bridge/server.rb:269-307`）逐依赖返回 `name`/`requirements`/`groups`/`platforms`/`autorequire`/`force_ruby_platform`/`gemspec_dev_dep`/`source`，并附全局 `sources`；`C-M8-1-004`；`spec/m8_batch_eval_spec.cr`；`65c69c2` |
| 3 | …platform | 不满足（缺 1 项：运行平台） | 同一次响应里只有依赖声明的 `platforms`；运行平台 `Gem::Platform.local` 由另一个 op `op_ruby_environment`（`assets/bridge/server.rb:198-245`）单独 RPC 返回。据 `docs/roadmap-evidence/M8-batch-protocol.md` §2 表「platform 只到依赖声明层」 |
| 4 | Ruby 约束 | 满足 | 同一响应含 `ruby`/`ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`（`assets/bridge/server.rb:290-296`）；`C-M8-1-004`；`spec/m8_batch_eval_spec.cr`；`65c69c2` |
| 5 | 插件声明 | 不满足（缺 1 项） | `evaluate_batch` 只服务 `include:["gemspecs"]`（后加 `fingerprint`），`plugins` 被显式推迟：`C-M8-1-004` 边界与 `assets/bridge/server.rb:558` 注释「Only `gemspecs` and `fingerprint` are served for now」；插件声明仍走独立 `op_plugin_gemfile_eval`，且要求插件已安装。见 `docs/roadmap-evidence/M8-batch-protocol.md` §2 插件行、§5.3 |
| 6 | 一次提交完整候选集并返回解 | 不满足（缺实现，已有设计豁免） | 求解器在 Crystal（`src/celerite/resolver/` 内无 `Bridge::Client`），Ruby 侧无求解器、无 `solve_batch`；`docs/roadmap-evidence/M8-batch-protocol.md` §5.3 表末行明写「**不实现**」 |
| 7 | 禁止在 PubGrub 循环中逐版本跨桥 | 满足 | 候选按 gem 名一次性取回并记忆化（`src/celerite/resolver/source.cr:204-217`、`:350`），solver 只做内存过滤、无桥调用；`spec/m8_batch_eval_spec.cr` 断言旧「两次 op」= 2 RPC、batch = 1 RPC；`65c69c2`。证据节：`docs/compat-evidence/2026-11-23.md` 的 `## 2026-11-24：evaluate_batch 合并求值面（task-227）` |

### 缺口与最小补法

1. **运行平台未并入单次导出**（缺实现，小）：在 `bridge_serialize_evaluation` 增加运行平台字段（或让 `evaluate_batch` 默认回 `platform`），与每依赖的 `platforms` 分名，补一条 batch 响应字段断言。
2. **插件声明未并入单次导出**（缺实现，中）：按 S3 计划把 `plugins` 并进同一 `evaluate_batch`，复用同一次 `builder`（不二次执行 DSL、不重复 `GemfileWarnings`）；若插件 hook 副作用不可接受，则把判据改为「经 `ping.features` 声明的独立 op 导出插件声明」并在 roadmap 登记豁免。
3. **「一次提交完整候选集」未实现**（缺实现，但无消费者）：保留则需 Ruby 侧 `solve_batch`；建议直接在 L161 改写该分句为「不在 PubGrub 循环中跨桥」，或登记豁免理由（求解在 Crystal 侧，Ruby 侧无求解器）。

## 2. L162 — 求值指纹

> 历史注记（task-251，2026-11-24，HEAD ae6a135）：本节为 task-238 时点判定。第 4 行「配置」与第 6 行「ABI」两项已由 task-246（`C-M8-1-014`）落地，并经 task-249 §11 复审改为满足，第 7 行「任一输入变化」随之成立；请以 §11 为准。保留原文以存审计历史，本节判定不再代表当前状态。

> 原文（逐字）：`- [ ] 完成求值指纹：Gemfile/eval_gemfile、引用 gemspec、读取的 ENV、配置、Ruby/RubyGems/Bundler 版本与 ABI；任一输入变化必须使缓存失效，不使用内容哈希代替完整环境指纹。`

### 分句判定

| # | 分句 | 判定 | 证据 / 缺口 |
|---|---|---|---|
| 1 | Gemfile/eval_gemfile | 满足 | 指纹含 `gemfile.path`/`gemfile.sha256`、`evalchain.count` 与逐项 `evalchain.<i>.path/sha256`，`verify.files[]` 带 `role=evalchain`；`C-M8-1-007`；`spec/m8_eval_fingerprint_spec.cr`（V4 改 `eval_gemfile` 目标后 digest 变）；`c657fce`。证据节：`docs/compat-evidence/2026-11-23.md` 的 `## 2026-11-24：求值指纹的桥侧产出（M8 F1，task-233）` |
| 2 | 引用 gemspec | 满足 | 指纹含 `gemspec.count` 与逐项 `gemspec.<i>.path/sha256`，`verify.files[]` 带 `role=gemspec`；`C-M8-1-007`；`spec/m8_eval_fingerprint_spec.cr`（V3+V9 只改被引 gemspec 的 dev 依赖：`gemfile_sha256` 相等而 digest 不等）；`c657fce` |
| 3 | 读取的 ENV | 满足（有效覆盖在缓存键，不在指纹文本） | 全量 ENV 排序后取 SHA-256 作缓存键/条目字段（`src/celerite/bridge/client.cr:182-189`、`:214`、`:286`），任一 ENV 变化即 miss；`C-M8-1-008`；`spec/m8_eval_fingerprint_cache_spec.cr`；`6a2dfc0`。注意：F1 指纹文本本身不含 ENV（`C-M8-1-007` 边界），「求值指纹」与「缓存键」是两个对象。 |
| 4 | 配置 | 不满足（缺 1 项） | `.bundle/config` 等配置文件的求值相关键既不在指纹、也不在 ENV 签名里（`C-M8-1-009` 边界 D1：仅由全量 ENV 签名兜底）。 |
| 5 | Ruby/RubyGems/Bundler 版本 | 满足 | 指纹含 `ruby.version`/`ruby.patchlevel`/`ruby.engine`/`ruby.engine_version`/`rubygems.version`/`bundler.version`；`C-M8-1-007`；`spec/m8_eval_fingerprint_spec.cr`；`c657fce` |
| 6 | ABI | 不满足（缺 1 项，缺判据） | 运行时记录无 `abi` 键（`C-M8-1-009` 边界「ABI 记录」）；`InstallPaths.ruby_abi` 只由 `ruby_version` 推导（`src/celerite/resolution.cr:164-165`），既未记录也未断言「version+platform 可推出 ABI」。 |
| 7 | 任一输入变化必须使缓存失效 | 不满足（缺第 4、6 两项） | 现有失效面：Gemfile/eval 链/gemspec/ENV/版本/平台（F1+F2+F3+F4）；配置与 ABI 不在其中。 |
| 8 | 不使用内容哈希代替完整环境指纹 | 满足 | 指纹含路径、eval 链与 gemspec 内容摘要、运行时版本与平台，不是单一内容哈希；`spec/m8_eval_fingerprint_spec.cr` V12 断言 gemspec 仅 CRLF→LF 时 `gemfile_sha256` 相等而 digest 不等；`c657fce` |

### 缺口与最小补法

1. **配置未入键**（缺实现，小）：把 `Bundler.app_config_path` 下 `.bundle/config` 的内容哈希并入指纹或缓存键（`env_signature` 之外单列），补一条「只改 config → miss」的 spec。
2. **ABI 未入键**（缺实现 + 缺判据，小）：桥侧 `ruby_environment` 增加 `abi`（`RbConfig::CONFIG["ruby_version"]` 或 `Gem.ruby_api_version`），加入指纹并升 magic 到 `celerite-eval-v2`；补断言「ABI 变 → digest 变」。

## 3. L163 — 桥复用与可观测性

> 原文（逐字）：`- [ ] 同一求值复用 bridge，加入 idle 回收、协议超时、结构化错误和批量大小控制；统计一次命令的 Ruby 进程数、RPC 次数和传输字节数。`

### 分句判定

| # | 分句 | 判定 | 证据 / 缺口 |
|---|---|---|---|
| 1 | 同一求值复用 bridge | 满足 | `C-M8-1-002`：`Client.shared` 以 ENV 签名作键（`src/celerite/bridge/client.cr:423`、`:472`），39 处 `new`→`shared`，`EvaluationCache` 在 `CLI.run` 内复用求值（`src/celerite/cli.cr:26`、`:48`）；`spec/m8_bridge_reuse_spec.cr`；`1a89a7a`。证据节：`docs/compat-evidence/2026-11-23.md` 的 `## 2026-11-24：桥复用与 idle 回收（task-221）` |
| 2 | idle 回收 | 满足 | `CELERITE_BRIDGE_IDLE_MS`（`client.cr:455`，未设/空/非法/`<=0` = 不回收），`:464` 判过期、`:486` `dispose`；`spec/m8_bridge_reuse_spec.cr` 断言 `IDLE_MS=1` 后 `procs>1`；`1a89a7a` |
| 3 | 协议超时 | 满足（既有能力，非本轮新增） | 每请求 deadline 默认 30s（`client.cr:742`），`request` 的 `limit`（`:1150`）到期抛 `BridgeError("Timeout")`（`:1192-1193`）；`spec/m7_bridge_long_operations_spec.cr` 负控断言文案 `bridge request timed out after 0.2s`。`C-M8-1-001` 边界并声明统计开关不改超时语义。 |
| 4 | 结构化错误 | 满足 | 错误信封回显请求 `proto` 并带 `error.class`/`error.message`（`assets/bridge/server.rb:48-51`、`:968`），`C-M8-1-003`，`spec/m8_bridge_proto_spec.cr`；共享桥的 `BundlerVersionMismatch` 结构化错误，`C-M8-1-006`，`spec/m8_bridge_bundler_activation_spec.cr`，`af4c654`。证据节：`## 2026-11-24：共享桥进程的 Bundler 版本污染与修复（task-230）` |
| 5 | 批量大小控制 | 不满足（缺实现） | `git grep -n "batch_size\|MAX_BATCH" -- src assets/bridge/server.rb` 无命中；`op_evaluate_batch` 只按 `include` 数组追加段，无条数/字节上限、无分片、无对应 spec；`C-M8-1-004` 未声明上限。 |
| 6 | 统计一次命令的 Ruby 进程数、RPC 次数和传输字节数 | 满足 | `C-M8-1-001`：`CELERITE_BRIDGE_STATS` 开启时 stderr 一行 `bridge: procs=<N> rpc=<M> req_bytes=<X> resp_bytes=<Y>`，`CLI.run` 复位/输出（`src/celerite/cli.cr:25`、`:46`）；`spec/m8_bridge_stats_spec.cr`；`edefe17`。证据节：`## 2026-11-24：桥统计计数与可回归基线（task-219）` |

### 缺口与最小补法

**批量大小控制**（缺实现，小）：给 `evaluate_batch` 的 `include` 与响应体加上限（例如 ≤4 段、≤256 KiB），超限回结构化错误或按段分片；补一条「超限」spec，并在 `C-M8-1-004` 边界写明上限值。

## 4. L164 — 无变化 lock/install 直接使用 lockfile 与安装计划

> 原文（逐字）：`- [ ] 无变化 `lock`/`install` 直接使用 lockfile 和安装计划：不加载 Bundler、不启动 Ruby；有动态 DSL、插件或指纹不确定时显式走兼容路径。`

### 分句判定

| # | 分句 | 判定 | 证据 / 缺口 |
|---|---|---|---|
| 1 | 无变化 `lock` 直接使用 lockfile，不加载 Bundler、不启动 Ruby | 不满足（缺 1 项） | `src/celerite/cli/commands.cr:3075` 的 `Resolution.new(definition, unlock)` 在 `:3106-3129` 的空操作短路之前执行；`Resolution#initialize` 走 `@bridge.not_nil!.evaluate_gemfile`（`src/celerite/resolution.cr:382`）。实测（`docs/roadmap-evidence/M8-no-ruby-fast-path.md` §8.2，基线 `5018400`）：`lock` 无变化 = 1 proc / 2 rpc。 |
| 2 | 无变化 `install` 直接使用安装计划，不加载 Bundler、不启动 Ruby | 不满足（缺 1 项） | `src/celerite/cli/commands_install.cr:266` 无条件取 `Bridge::Client.shared`，`:274` `evaluate_gemfile`，`:282` `ruby_environment`，`:293` `Resolution.new`，`:299` 取 `default_gem_dir`/`ruby_abi`。实测 §8.2：`install` 无变化 = 1 proc / 9 rpc。 |
| 3 | 有动态 DSL、插件或指纹不确定时显式走兼容路径 | 满足（机制层） | F3 三态：`unknown`/`broken` 从不入缓存、每次重新求值（`C-M8-1-009`，`spec/m8_eval_cache_state_spec.cr`，`0826f63`）；F4 命中要求 format/env 签名/指纹 digest/state/verify 全部通过，否则 miss 并正常求值（`C-M8-1-010`，`spec/m8_eval_cache_store_spec.cr`，`8032aaf`）；插件索引目录存在即 `unknown`。注记：`lock`/`install` 尚未接入该缓存，故该分句对这两条命令目前等于「总是兼容路径」。 |

### 缺口与最小补法

1. **`lock` 零 spawn**（缺实现，中）：把空操作判定所需的指纹提前到 `Resolution.new` 之前——用 F1/F2 指纹证明「Gemfile 与 lockfile 均未变」并跳过 `Resolution.new`；`resolution.path_specs_changed?` 等判定需要移到无桥路径或用已存条目回放，保留「指纹不确定 → 起桥」的显式分支。
2. **`install` 零 spawn**（缺实现，中）：同上，安装计划需持久化（当前无 install-plan 缓存，见 §5），至少先做到「lockfile + 已装目录 + 指纹一致 → 不取 `Bridge::Client.shared`」，`ruby_abi` 改从缓存的运行时记录读。
3. 两条命令补 `CELERITE_BRIDGE_STATS=1` 下 `procs=0` 的 spec，作为 L164 的验收判据。

## 5. L165 — 持久化、版本化的解析/安装计划缓存

> 原文（逐字）：`- [ ] 实现持久化、版本化的解析/安装计划缓存，键包含 source 身份、凭据隔离标识、checksum、平台、Ruby ABI 和 build 配置；缓存损坏安全回退，不把未校验产物视为可用。`

### 分句判定

| # | 分句 | 判定 | 证据 / 缺口 |
|---|---|---|---|
| 1 | 持久化 | 满足 | `src/celerite/eval_cache_store.cr` 落盘 `<root>/<namespace>/v1/<hex64 digest>/entry.json`（`CELERITE_EVAL_CACHE=1` 开启）；`C-M8-1-010`；`spec/m8_eval_cache_store_spec.cr`；`8032aaf`。证据节：`## 2026-11-24：跨命令持久化求值缓存（task-237）` |
| 2 | 版本化 | 满足 | 布局 `v1` + 条目格式 `celerite-eval-cache/1`（`eval_cache_store.cr:24-25`），`persisted_entry` 校验 format（`client.cr:283`）；`C-M8-1-010`；`spec/m8_eval_cache_store_spec.cr` |
| 3 | 解析/安装计划缓存 | 不满足（缺 1 项：缓存对象错位） | store 头注释明写只持久化求值结果，「never persists a lockfile, an install plan, or an installed spec」（`src/celerite/eval_cache_store.cr:11-17`）；`GemfileEvaluation` 字段只有求值面（`client.cr:612-627`）。没有 resolution 解或 installation plan 的持久化。 |
| 4 | 键包含 source 身份 | 不满足（缺 1 项） | 地址 = F1/F3 指纹 digest（gemfile/evalchain/gemspec/runtime/platform），source 内容与 URL 只在 payload 内、不入键；`C-M8-1-010` 边界自陈键成分不含 source 身份。 |
| 5 | 凭据隔离标识 | 满足 | namespace = 排序后 `BUNDLE_*` 环境对的 SHA-256 前 16 位，落盘不含明文（`eval_cache_store.cr:64-70`）；含凭据 URI 的求值直接拒绝持久化（`persistable?`，`:96-98`）；`spec/m8_eval_cache_store_spec.cr` 的凭据用例；`8032aaf` |
| 6 | checksum | 不满足（缺 1 项） | 键无任何 gem checksum；checksum 只出现在 lockfile/安装域（M7 的 `CHECKSUMS` 工作），未进入求值缓存键。 |
| 7 | 平台 | 满足 | 指纹含 `platform`（`C-M8-1-007`）；`spec/m8_eval_fingerprint_spec.cr` |
| 8 | Ruby ABI | 不满足（缺 1 项） | 同 §2 第 6 项：运行时记录无 `abi` 键（`C-M8-1-009` 边界），指纹只有 `ruby.version` 等。 |
| 9 | build 配置 | 不满足（缺 1 项） | 键无 `BUNDLE_BUILD__*`/`--with-*` 等构建配置；无对应字段与 spec。 |
| 10 | 缓存损坏安全回退 | 满足 | 解析失败 → `discard` 并当 miss（`eval_cache_store.cr:139-144`、`:197-203`）；写盘用同目录临时文件 + rename（`:100-129`）；`spec/m8_eval_cache_store_spec.cr` 的损坏用例；`8032aaf` |
| 11 | 不把未校验产物视为可用 | 满足 | `persisted_entry` 依次校验 format/env 签名/指纹 digest/state=deterministic/文档完整性/`verify` 逐文件重哈希（`client.cr:279-316`）；`C-M8-1-010`；`spec/m8_eval_cache_store_spec.cr`；`8032aaf` |

### 缺口与最小补法

1. **缓存对象错位**（缺实现，大）：L165 要的是解析/安装计划缓存。最小可行：以 F4 的 store 为骨架，新增 `celerite-plan-cache/1`，条目存「lockfile 解 + 安装计划（含平台变体与 build 配置）」，键在现有指纹上追加 source 身份与 checksum。
2. **source 身份 / checksum**（缺实现，中）：键内加入每个 source 的规范化身份（URL/类型/是否镜像）与 lockfile `CHECKSUMS` 段的摘要。
3. **ABI / build 配置**（缺实现，小）：同 §2；`BUNDLE_BUILD__<gem>` 与 `--with-*` 纳入键。

## 6. L166 — 只读命令复用索引 + Rails 规模性能对照

> 原文（逐字）：`- [ ] 让 `check/list/show` 等只读命令复用已安装 gem 索引；为真实 Rails 规模冷/热/无变化运行建立性能对照，包含 Bundler + YJIT。`

### 分句判定

| # | 分句 | 判定 | 证据 / 缺口 |
|---|---|---|---|
| 1 | `list` 复用已安装 gem 索引 | 满足 | `C-M8-1-005`：无组选择时不起桥，plain 环境 `list`/`--paths`/`--name-only`/`--format=json` 均 `procs=0 rpc=0`；`spec/m8_list_no_group_zero_spawn_spec.cr`；`e3ede75`。证据节：`## 2026-11-24：list 无组选择的零 spawn 快路径（task-229）` |
| 2 | `check` 复用已安装 gem 索引 | 不满足（缺 1 项） | `check` 仍在 `validate_runtime!`（`src/celerite/cli/commands.cr:1570`）与求值处起桥；实测（M8-no-ruby §8.2，基线 `5018400`）`check` = 1 proc / 2 rpc。§8.4 并记：把 `:1570` 条件化会改 ruby/平台不符的报错时机与退出码，违反判据②，故该快路径被有意否决。 |
| 3 | `show` 复用已安装 gem 索引 | 不满足（缺 1 项） | 非 verbose `show` 实测 1 proc / 2 rpc（同 §8.2）；SQL 同因被 §8.4 否决（同一 `validate_runtime!` 前置）。 |
| 4 | 真实 Rails 规模冷/热/无变化性能对照，含 Bundler + YJIT | 不满足（缺 oracle + 缺判据，部分本机不可验证） | 仓内无任何基准报告：`git grep -i "yjit" -- docs` 只命中 `docs/architecture.md:176`、`docs/roadmap.md:194`、各证据文档的「未做」条目；`docs/roadmap-evidence/M8-batch-bridge.md:130`/`:160` 明记「Rails 规模 + 参考 Bundler + YJIT 对比本机不可验证」；`docs/roadmap-evidence/M7-9-rails-regression.md:107` 明记未跑 rails 规模双侧性能比较。M7-9 只证明正确性可跑通（rails 8.0.2 lock `10663 B`/64 spec、install 64 gem 双侧）。 |

### 缺口与最小补法

1. **`check`/`show` 索引复用**（缺实现，大）：需要一条不依赖 `validate_runtime!` 的判定输入路径——用已装目录 + lockfile + 运行时记录（ABI 从缓存读）替代起桥；若维持「不改报错时机」的结论，则把 L166 判据收窄为「`list` 等只读命令」，并在 roadmap 登记 `check`/`show` 的豁免。
2. **Rails 规模性能对照**（缺 oracle/缺判据，中；本机可做到正确性与单侧计数，双侧+YJIT 需夹具）：最小可行方案——复用 M7-9 的 rails-min Gemfile（`source "https://rubygems.org"` + `gem "rails", "8.0.2"`）与已装 64 gem 树；写 `script/bench-m8`（PowerShell 驱动即可）：三档（冷/热/无变化）× 两侧（`celerite` 与 `bundle _4.0.24_`）× YJIT 开关（`RUBY_YJIT_ENABLE=1`）；采集 wall（秒表）、CPU（`Process.TotalProcessorTime`）、RSS（peak working set）、RPC/字节（`CELERITE_BRIDGE_STATS=1`）、I/O（安装目录读写字节，ETW/`Get-Counter` 二选一）。成本估：1 个任务 4–8 h；网络下载复用本机缓存后每档 < 2 min，输出 `docs/roadmap-evidence/M8-rails-bench.md` 表 + CSV。

## 7. 交叉不一致清单

| # | 位置 | 冲突内容 | 建议 |
|---|---|---|---|
| 1 | `docs/compat-claims/M8-batch-bridge.md` 的 `C-M8-1-003` 我方行为（`:29`）vs `assets/bridge/server.rb:48` | claim 写 `BRIDGE_FEATURES = [evaluate_gemfile, gemspec_paths, plugin_gemfile_eval]`；代码实为 5 项（另含 `evaluate_batch`、`fingerprint`），且同文件 `C-M8-1-004`/`C-M8-1-007` 记后两者已加入。 | 把 `C-M8-1-003` 的「我方行为」改成「初始 3 项；后续切片追加…见 C-M8-1-004/007」，或直接列当前 5 项。 |
| 2 | `docs/compat-claims/M8-batch-bridge.md`（10 条均「状态：已实现」）vs `docs/roadmap.md` L161–L166（全 `[ ]`） | 切片级「已实现」与行级不可勾并存；`C-M8-1-010` 边界自己写「L165 仍不可勾」。 | 在 claims README 或 roadmap 注明口径：claim 只覆盖切片，「行闭合」另由判据表裁定（本文件即该表）。 |
| 3 | `docs/roadmap-evidence/M8-batch-protocol.md` §1-5、§5.3 vs `docs/roadmap.md` L161 | 设计文档明写「一次提交完整候选集**不实现**」（Ruby 侧无求解器），L161 原文仍要求该分句；豁免只存在于实现计划文档。 | 在 roadmap L161 改写该分句，或在该行括注「候选集提交不适用（求解在 Crystal）」。 |
| 4 | `docs/roadmap-evidence/M8-no-ruby-fast-path.md:12` vs 同文件 `:317-319` | `:12` 把 `check`/`show` 列为「数据已在手、只差去掉 spawn 的 4 条」；`:317-319` 以「改报错时机与退出码」为由否决 `check`（S2）与 `show` 快路径；`:201` 表仍称「仍成立」。 | 在 `:12` 与 `:201` 加注「`check`/`show` 因判据②被否决，见 §8.4」，避免被读成待做项。 |
| 5 | `docs/roadmap-evidence/M8-no-ruby-fast-path.md:148`/`:153` vs F1–F4 已落地 | 文档称 S5 的零 spawn 验收点依赖 task-222 指纹（当时只有设计文档）、YJIT 未测；指纹三态与持久化缓存已于 `c657fce`/`6a2dfc0`/`0826f63`/`8032aaf` 落地，文档未复评。 | 用一句话更新前置条件，并写明「指纹已落地但仍缺 config/ABI，故 L164 仍未可做」。 |
| 6 | `docs/roadmap-evidence/M8-batch-bridge.md:13` vs 现状 | 文档称 `src/celerite/bridge/` 只有 `client.cr`（577 行）；现 `client.cr` 为 1235 行（含 F2–F4 与统计）。 | 更新行数与职责描述，或删去易腐的行数。 |
| 7 | `src/celerite/eval_cache_store.cr:11-13` vs `src/celerite/bridge/client.cr:612-627` / `C-M8-1-004` | store 注释称持久化内容含「plugin declarations」；`GemfileEvaluation` 无插件声明字段，`evaluate_batch` 也不服务 `plugins`。 | 删掉注释里的「plugin declarations」，或在 S3 落地后再写。 |

## 8. 本轮未验证的事项

- **未 build、未运行任何 celerite 命令**：本轮为只读审计，§4/§6 的 `procs`/`rpc` 数字全部引自既有证据文档（`docs/roadmap-evidence/M8-no-ruby-fast-path.md` §8.2，基线 `5018400`；以及 `docs/compat-evidence/2026-11-23.md` 的 task-235 节），未在 `05402b6` 上复测。
- **未重跑任何 spec**：`spec/m8_*.cr` 的 examples 数与通过状态引自 claims 判据，未在本工作树执行（避免与 lead 的全量差分争用端口）。
- **未实测 `CELERITE_BRIDGE_STATS=1`**：`lock`/`install` 的 1 proc/2 rpc、1 proc/9 rpc 是文档数值，不是本轮输出。
- **`.bundle/config` 是否真的参与求值**：按 `C-M8-1-009` 边界 D1 判定为「未入键」，未构造 config-only 变更做实测。
- **ABI 推导等价性**：`ruby_abi_for` 只吃 `ruby_version`（`src/celerite/resolution.cr:164-165`），「version+platform 足以定 ABI」未验证。
- **Rails 规模性能**：未跑；YJIT 在 `C:\Ruby40-x64`（4.0.24）下的可用性与 `RUBY_YJIT_ENABLE` 行为未实测；本机是否有可复用的 64 gem 安装树未核实。
- **`include:["plugins"]` 并入的副作用**：按 `C-M8-1-004` 边界的论证采信（二次 DSL、重复 warning、hook 副作用），未实测。

## 9. 交叉不一致的处理结果（task-240）

工作树 `C:\temp\celerite-t240`（detach 于 `7ea8333`）。逐条对应 §7 的编号；核对以代码与文档实际内容为准，改动保留原说法并标注「已被取代 / 误记」，未静默改写历史判断。

1. **第 1 条：已改。** 实测 `assets/bridge/server.rb:45` 为 5 项（`evaluate_gemfile`、`gemspec_paths`、`plugin_gemfile_eval`、`evaluate_batch`、`fingerprint`）。`docs/compat-claims/M8-batch-bridge.md` 的 `C-M8-1-003`「我方行为」改为：初始 3 项（原记 `:41`，已被后续切片取代）+ 追加 `evaluate_batch`（C-M8-1-004）与 `fingerprint`（C-M8-1-007），现为 5 项；行号改为 `:45`。
2. **第 2 条：已改。** `docs/compat-claims/M8-batch-bridge.md` 头部（首条 claim 之前）新增口径块：「本文件的断言覆盖的是**切片**，行级闭合由 `docs/roadmap-evidence/M8-closure-audit.md` 的分句判据表裁定。」原文件无同义说明，未重复。
3. **第 3 条：已改（只改证据文档）。** `docs/roadmap-evidence/M8-batch-protocol.md` §5.3 表后加注：`docs/roadmap.md:161` 的「一次提交完整候选集并返回解」在 Crystal 侧求解的架构下不适用（Ruby 侧无接收候选集的求解器，PubGrub 在 `src/celerite/resolver/`）；`docs/roadmap.md` 未改。
4. **第 4 条：已改。** `docs/roadmap-evidence/M8-no-ruby-fast-path.md:12` 与 `:201` 各加 task-240 注：`check`/`show` 因判据②（不得改报错时机与退出码）被否决，见 §8.4；`:12` 的「4 条」保留为 task-223 的盘点口径。
5. **第 5 条：已改。** 核对 hash 与 claims 对应：`c657fce`=F1（C-M8-1-007）、`6a2dfc0`=F2（C-M8-1-008）、`0826f63`=F3（C-M8-1-009）、`8032aaf`=F4（C-M8-1-010），与审计所列一致。`:148` 依赖图后与 `:153` 各加一句：指纹三态与持久化缓存已落地，仍缺 config/ABI 入键，故 L164 仍未可做；`:153` 的 YJIT 未测结论不变。
6. **第 6 条：已改。** `docs/roadmap-evidence/M8-batch-bridge.md:13` 删去易腐行数，改为「task-217 盘点时 577 行；task-240 复核为 1235 行，此后不再记数」。
7. **第 7 条：已改（仅注释）。** `src/celerite/eval_cache_store.cr:11-19` 删去「plugin declarations」，注明该段曾误记、`plugins` include 仍留待 S3（C-M8-1-004）；持久化逻辑未动。
8. **附带发现（同一缺陷的第二处）：已改。** `docs/compat-claims/M8-batch-bridge.md` 的 `C-M8-1-010`「我方行为」也把「插件声明」列入持久化产物；`GemfileEvaluation`（`src/celerite/bridge/client.cr:612-627`）无该字段，故同步标注为误记。

审计结论有误之处：

- §7 第 1 条把 `BRIDGE_FEATURES` 定在 `assets/bridge/server.rb:48`，实际在 `:45`（`:48` 是 `bridge_emit` 的定义）；把 claim 的「我方行为」定在 `:29`，实际在 `:21`。
- §7 第 7 条漏记 `C-M8-1-010` 的同一处「插件声明」误记（见上第 8 点）。
- 其余引用行（`M8-no-ruby-fast-path.md:12`/`:148`/`:153`/`:201`/`:317-319`、`M8-batch-bridge.md:13`、`eval_cache_store.cr:11-13`）与 `7ea8333` 一致。
## 10. L163 勾选裁定（首辅，task-243 之后）

`docs/roadmap.md` 第 163 行的复选框已由首辅勾为 `[x]`。逐分句依据：

| 分句 | 判定 | 依据 |
| --- | --- | --- |
| 同一求值复用 bridge | 满足 | `C-M8-1-002`（`Client.shared` + `shutdown` + idle 回收）；`C-M8-1-011`（F5 单一入口，一次命令最多求值一次） |
| 加入 idle 回收 | 满足 | `C-M8-1-002`，`CELERITE_BRIDGE_IDLE_MS` 超时即 `dispose` 重建；`spec/m8_bridge_reuse_spec.cr` |
| 协议超时 | 满足 | `C-M8-1-002`（`Client#request` 的 `limit` 与 `BridgeError("Timeout", …)`） |
| 结构化错误 | 满足 | `C-M8-1-002`（`BridgeError` 带 `error_class` 与可选 `status_code`）；`C-M8-1-012`（`BatchTooLarge`） |
| 批量大小控制 | 满足 | `C-M8-1-012`（`MAX_INCLUDE_SECTIONS = 4`、`MAX_BATCH_RESPONSE_BYTES = 4 MiB`，两侧超限均结构化拒绝；`spec/m8_batch_size_limit_spec.cr` 7 例；task-243） |
| 统计一次命令的 Ruby 进程数、RPC 次数和传输字节数 | 满足 | `CELERITE_BRIDGE_STATS=1` 输出 `bridge: procs=… rpc=… req_bytes=… resp_bytes=…`；无桥时也会输出（`procs=0`），见 `docs/roadmap-evidence/M8-fast-path-plan.md` §0 的实测与 `docs/compat-evidence/2026-11-23.md` 的 task-219 节 |

未验证：① 4 MiB 上限没有真实超大 Gemfile 的端到端触发证据（只有 spec 级注入小上限 + 2,125 B 实测响应规模作余量依据）；② 客户端读行无单行长度上限，字节上限只防「接受超限结果」，不防对端先灌满内存；③ 该切片未跑差分（task-243 期间端口 8765 被全量差分占用），全量差分门禁以 `## Current metrics` 记的最近一次为准。

## 11. L162 闭合判据复审（task-249，2026-11-24，HEAD 456f8d1，只读）

复审对象：`docs/roadmap.md` 第 162 行原文（逐字）：

`- [ ] 完成求值指纹：Gemfile/eval_gemfile、引用 gemspec、读取的 ENV、配置、Ruby/RubyGems/Bundler 版本与 ABI；任一输入变化必须使缓存失效，不使用内容哈希代替完整环境指纹。`

本轮为只读审计：未改 `docs/roadmap.md`、claims、`src/**`、`spec/**`、`fixtures/**`、`script/**`。

### 11.1 本轮实测

**一、五个 fingerprint 相关 spec 文件，一次跑完**

```
crystal.exe spec spec\m8_eval_fingerprint_spec.cr spec\m8_eval_fingerprint_cache_spec.cr
  spec\m8_eval_fingerprint_config_abi_spec.cr spec\m8_eval_cache_state_spec.cr
  spec\m8_eval_cache_store_spec.cr
→ 34 examples, 0 failures, 0 errors, 0 pending   (EXIT=0, 33.27s)
```

stderr 仅两条 `File.executable?` 弃用警告，加端到端一例的 `eval-cache: state=unknown reason=token:ENV`（该例故意让指纹不可判定，属预期）。

**二、失效实验**：`crystal build src\cli.cr -o bin\celerite.exe` 退出 0（13,283,294 B）；夹具 `.tmp-scratch\exp-proj` 用 `source "file:///C:/temp/celerite-t249/fixtures/gem-index"` + `gemspec`；每次一个**新进程**跑 `celerite.exe lock`，环境 `CELERITE_EVAL_CACHE=1 CELERITE_EVAL_DEBUG=1 CELERITE_BRIDGE_STATS=1`。

| 轮次 | 改动 | 观测（逐字摘录） | 说明 |
| --- | --- | --- | --- |
| R1 | 首次 | `eval-cache: state=deterministic`／`persisted 17050b512751`／`bridge: procs=1 rpc=5 req_bytes=541 resp_bytes=288270` | 指纹判定为可缓存并落盘 |
| R2 | 无 | `eval-cache: hit (persistent)`／`procs=1 rpc=4 req_bytes=382 resp_bytes=285932` | 命中；rpc 由 5 降到 4，未起第二个进程 |
| R3 | Gemfile 末尾加一行无关注释 | `persistent miss (sha256:gemfile:Gemfile)`／`miss (persistent:sha256:gemfile:Gemfile)`／persisted `da0377c88d9e`／`rpc=5` | Gemfile 字节变即失效（含无害注释，方向保守） |
| R4 | 无 | `hit (persistent)`／`rpc=4` | 命中 |
| R5 | gemspec 的 `add_development_dependency "racc"` 改为 `"json_pure"` | `persistent miss (sha256:gemspec:exp-proj.gemspec)`／`rpc=5` | 被引用 gemspec 变更即失效 |
| R6 | 新增与求值无关的 ENV `CELERITE_T249_UNRELATED=1` | `persistent miss (env)`／`rpc=5` | 全量 ENV 签名导致保守失效 |

**三、HEAD 上真实指纹键序**（从 R6 落盘的 `entry.json` 逐字读出，1 条魔数行 + 21 条记录）：

```
celerite-eval-v1 / fp.format / gemfile.path / gemfile.sha256 / evalchain.count / gemspec.count /
gemspec.0.path / gemspec.0.sha256 / ruby.version / ruby.patchlevel / ruby.engine /
ruby.engine_version / rubygems.version / bundler.version / platform / abi.ruby_api_version /
abi.extension_api_version / abi.rbconfig_ruby_version / abi.source / config.app_config /
config.plugin_root / config.digest
```

`state=deterministic`，`digest=2f3c7ade…718c45b`，`abi.source=real`，`evalchain.count=0`（该夹具没有 `eval_gemfile`）。**指纹文本内没有 ENV 记录、没有 `gemfile.source`、没有 `bundler.profile`。**

### 11.2 逐分句判定表

| # | 输入项 | 是否进指纹 / 以何载体参与失效 | 判据（claim + spec） | 是否有「改动后重跑」的失效反例 | 判定 |
| --- | --- | --- | --- | --- | --- |
| 1 | Gemfile 本体 | 进指纹：`gemfile.path` + `gemfile.sha256`，并作为 `verify.files[]` 的 `role=gemfile` 条目重算 | `C-M8-1-007`；`spec/m8_eval_fingerprint_spec.cr` V3；`spec/m8_eval_fingerprint_cache_spec.cr` 第 3 例（`:189`，`misses >= 1`） | 有真反例：spec 第 3 例 + 本轮 R3（`sha256:gemfile:Gemfile`） | 满足 |
| 2 | `eval_gemfile` 链 | 进指纹：`evalchain.count` + 每条 `evalchain.<i>.path/.sha256`（桥侧 `bridge_fingerprint_eval_chain`，`assets/bridge/server.rb:439`，取 `@gemfiles` 去主文件） | `C-M8-1-007`；cache spec 第 1 例（`:136`） | 有 spec 级反例（改 eval 链文件 → `misses >= 1`）；**无进程级反例**（夹具无 `eval_gemfile`，实跑 `evalchain.count=0`） | 满足（证据仅 spec 级） |
| 3 | 被引用的 gemspec | 进指纹：`gemspec.count` + `gemspec.<i>.path/.sha256`（`bridge_fingerprint_gemspecs`，`server.rb:445`，取 `builder.gemspecs.map(&:loaded_from)`） | `C-M8-1-007`；cache spec 第 2 例（`:168`） | 有真反例：spec 第 2 例 + 本轮 R5（`sha256:gemspec:exp-proj.gemspec`） | 满足 |
| 4 | 读取的 ENV | **不在指纹文本**；载体是缓存键 `environment_signature`（`src/celerite/bridge/client.cr:221-233`，全量 `ENV.to_h` 排序 `k=v` 拼接后 SHA-256），持久化条目另存 `env` 字段并在载入时比对（`load_persisted`，`client.cr:329`） | `C-M8-1-008`；cache spec 第 6 例（`:260`，`misses >= 1`） | 有真反例：spec 第 6 例 + 本轮 R6（`persistent miss (env)`） | 满足（载体不是指纹文本，强度更高：非 `BUNDLE_` 前缀也覆盖） |
| 5 | 配置 | 进指纹：`config.app_config`、`config.plugin_root`、`config.digest`（`bridge_fingerprint_config`，`server.rb:412-419`，`app_config`=`Bundler.app_config_path`、`plugin_root`=`Bundler::Plugin.root`，`nil` 记 `-`） | `C-M8-1-014`；`spec/m8_eval_fingerprint_config_abi_spec.cr` 第 2 例（`:193`，同 ENV、cwd 换到 `other/` 使 `Bundler.app_config_path` 变成 `other/.bundle` → `misses >= 1`）与第 5 例（`:267-283` 伪造三键 → `runtime:config.*`／`config.digest`） | 有真实运行期反例（在 spec 内执行，非伪造）；未用 CLI 独立复现 | 满足（配置键面窄于 plan D1，见 §11.6） |
| 6 | `ruby.version`／`patchlevel`／`engine`／`engine_version`／`rubygems.version`／`bundler.version`／`platform` | 进指纹：七条独立记录（`bridge_fingerprint` 组装，`server.rb:566-627`） | `C-M8-1-014`；cache spec 第 5 例（`:234`、`:237`，伪造 `bundler.version`／`platform` → `runtime:bundler.version`／`runtime:platform`） | **只有伪造记录级反例**；无第二解释器实测 | 记录满足；失效反例仅单元级 |
| 7 | ABI（`ruby_api_version`／`extension_api_version`／`rbconfig_ruby_version`） | 进指纹：三条真值记录 + `abi.source`（`bridge_fingerprint_abi`，`server.rb:427`；`source` 恒 `real`） | `C-M8-1-014`；config_abi spec 第 4 例（`:241`、`:244`，伪造两条 ABI → `runtime:abi.*`） | **只有伪造记录级反例**；`-static` 分支与跨 ABI 均未实测 | 同上 |
| 8 | 附加约束：任一输入变化必须使缓存失效 | 命中须连过四道闸：`@@withheld`（`client.cr:251`）→ `load_persisted` 的目录名/`format`/`env`/`state==deterministic`/`Document.parse`/`integrity_reason`/`verify`（`:288` 起）→ `env_signature` 相等（`:257`）→ 归一路径相等（`:258`）→ `document.verify`（`:267`）。`Document#verify`（`src/celerite/eval_fingerprint.cr:221-288`）逐条覆盖：`verify.files[]` 重算 sha256（`:226-235`）、7 项 runtime（`:237-251`）、4 项 abi（`:253-264`）、2 项 config（`:266-275`）、`config.digest` 自洽（`:279-285`） | `C-M8-1-007`／`C-M8-1-008`／`C-M8-1-014` | 四项主输入有进程级反例；配置有 spec 内真实反例；版本与 ABI 只有伪造记录级反例 | 满足（证据分层，见 §11.5 第 1、2 项） |
| 9 | 附加约束：不使用内容哈希代替完整环境指纹 | 指纹 = 魔数 `celerite-eval-v1`（`server.rb:361`）+ 定序 `key\tvalue` 文本（`:605-606`）+ 整体 SHA-256（`:622`）；缓存键 = 指纹 `digest` + 全量 ENV 签名 + 归一项目路径（`client.cr:257-267`），**没有任何分支以 `gemfile.sha256` 作唯一键** | `C-M8-1-007`；设计文档 `docs/roadmap-evidence/M8-evaluation-fingerprint.md` §2.4 的反例要求 | `git grep -n gemfile_sha256 -- src spec`：生产侧只有 `src/celerite/bridge/client.cr:730` 的 `getter gemfile_sha256 : String`（供 `GemfileEvaluation` 暴露给上层），其余命中全在 spec（`spec/m8_eval_fingerprint_spec.cr:222,277`、`spec/m8_eval_fingerprint_cache_spec.cr:188,213`、`spec/m8_bridge_reuse_spec.cr:138-139`、`spec/bridge/client_spec.cr:59`） | 满足 |

### 11.3 两个附加约束的判定

**约束一：「任一输入变化必须使缓存失效」——满足（证据分层）。**

结构上每类输入都有独立的失效分支，且失效原因是可读的短字符串（`sha256:<role>:<path>`、`missing:<role>:<path>`、`runtime:<key>`、`record:<key>`、`config.digest`、`env`、`persistent:<reason>`），本轮 R3/R5/R6 的实际输出与 spec 断言的原因字符串一致。

但「有分支」与「有改动后重跑的实测反例」不是一回事，逐项分档：

- **有进程级真反例**：Gemfile（spec 第 3 例 + R3）、`eval_gemfile` 链（spec 第 1 例）、被引用 gemspec（spec 第 2 例 + R5）、ENV（spec 第 6 例 + R6）。
- **有真实运行期反例但只在 spec 内**：配置（config_abi 第 2 例靠换 cwd 改变 `Bundler.app_config_path`，不是伪造记录）。本轮没有用 CLI 独立复现。
- **只有伪造记录级反例**：七项版本/platform（cache 第 5 例）与四项 ABI（config_abi 第 4 例）。伪造「已记录值」正是跨版本/跨 ABI 命中时的真实形态，故比对逻辑被测到；但桥侧读真值的分支（`Gem.ruby_api_version` 等）在第二解释器下未跑过。

**约束二：「不使用内容哈希代替完整环境指纹」——满足。**

指纹既含文件内容哈希（gemfile、各 gemspec、各 eval 链文件），也含环境项（版本 7 条、ABI 4 条、配置 3 条），并且是整体 `SHA-256(text)` 而非某个文件哈希；缓存键再叠加全量 ENV 签名与归一路径。反方向的「过度失效」（R3 一行注释也 miss、R6 一个无关变量也 miss）是保守方向，不违反本条。

**结构性注记（不计缺项，但需落账）**：`Document#verify` 对 runtime/abi/config 三段都写成 `next if current.nil?`（`eval_fingerprint.cr:249`、`:262`、`:273`），即**同一 client 的进程内命中不重比这三段**——`fetch` 只对外来条目才计算 runtime（`client.cr:266`）。实际不可达：进程内版本/ABI 不可变，ENV 变化由 `env_signature` 兜住、cwd 变化由路径键兜住。但这是设计捷径，不是实测结论（见 §11.5 第 9 项）。

### 11.4 结论

**L162 可勾 [x]（缺 0 项）。**

三条依据：① 六类输入全部落到具体记录或缓存键，并在 `Document#verify` 有对应比较分支；② 四项主输入有进程级失效反例，配置有 spec 内真实反例，版本/ABI 有伪造记录级反例；③ 缓存键未退化为内容哈希。

勾选时应同时落账、但不构成缺项的限制：`abi.source` 恒 `real`（无 `derived`）、`-static` 分支未实测、gemspec 候选集与 `.bundle/config` 正文/插件索引内容不覆盖、`ruby file:` 目标内容不入指纹（降级 `unknown`）、版本/ABI 的进程级反例缺失。这些都已写在 `C-M8-1-009`「边界」与 `C-M8-1-014`「边界」中，属已声明残余风险，不是未实现的判据。

### 11.5 未验证事项（本轮没能跑到的）

1. **换解释器的真反例**：本机只有 `C:\Ruby40-x64` 一个 Ruby，也没有 `-static`/无扩展构建，无法构造「ABI 或版本变化后重跑」的进程级证据，只能引用 spec 内伪造记录（`config_abi` 第 4 例、cache 第 5 例）。
2. **`eval_gemfile` 链的进程级反例**：夹具没有 `eval_gemfile`（实跑 `evalchain.count=0`），该项只有 cache 第 1 例。
3. **配置的 CLI 级复现**：config_abi 第 2 例在 spec 内换 cwd，本轮未用 `celerite.exe` 独立复现同一现象。
4. **`ruby file:`（plan A4）**：未构造反例；实现按 token 降级为 `state=unknown`（不写缓存），逻辑上既不误命中也不失效，但本轮未实测该降级。
5. **gemspec 候选集（plan B1）**：未跑「再放一个 `*.gemspec` 让参考报多组合法性错误」的反例；其可达性（需 `CELERITE_EVAL_CACHE=1`、且同一路径第二次命令）也未实测。
6. **`.bundle/config` 正文与插件索引内容**：未构造反例（`C-M8-1-009`「边界」已声明不覆盖）。
7. **未跑 `script/differential`**（端口 8765 被他人全量差分占用的禁令），跨 Bundler 差分结论沿用既有记录。
8. **`CELERITE_EVAL_CACHE` 默认关闭路径**：6 次实验全部开启持久化缓存，未跑关闭态对照（关闭时 `EvaluationCache.active?` 为 false，走桥直算）。
9. **同一 client 命中不重比 runtime/abi/config**：结论来自读码（`eval_fingerprint.cr:249/262/273` + `client.cr:266`），未写反例证明「进程内换配置也不会误命中」。

### 11.6 交叉不一致

以下按节标题/claim 编号定位，便于逐个回改。

1. **claims 的行号已整体漂移（`docs/compat-claims/M8-batch-bridge.md`）**，逐条核对 HEAD：
   - `C-M8-1-007`「我方行为」：`bridge_fingerprint` 记 `assets/bridge/server.rb:295-400` → HEAD 实际 `:566-627`（`:361` 魔数、`:605-606` 文本、`:622` digest）。
   - `C-M8-1-009`「我方行为」：`FINGERPRINT_DYNAMIC_TOKENS` `:389` → `:475`；`bridge_fingerprint_source` `:405` → `:491`；`bridge_fingerprint_dynamic_reason` `:420` → `:506`；`bridge_fingerprint_literal_argument` `:414` → `:500`；`bridge_fingerprint_plugin_reason` `:445` → `:531`；`bridge_fingerprint_state` `:458` → `:544`；`bridge_fingerprint` `:480` → `:566`。同一条还把 `client.cr` 的 `EvalFingerprint` 记 `:492` → 实际 `:740`、`@@withheld` 记 `:124-128` → 实际 `:165`、`fetch` 记 `:196` → 实际 `:244`；`eval_fingerprint.cr` 的 `integrity_reason` 记 `:138` → 实际 `:194`、`verify` 记 `:165` → 实际 `:221`。
   - 只有 `C-M8-1-014`「我方行为」的 `:405`/`:412`/`:427`、`client.cr:181`/`:994`/`:1054-1057` 与 `eval_fingerprint.cr:103`/`:125`/`:221`/`:254-257`/`:267-268`/`:280`/`:285` 与 HEAD 一致。
   - 结论：F1/F2 之后 F4（持久化）与 F5（单入口）又改了这两个文件，旧 claim 的坐标没回写；同一文件里两条 claim 对同一函数给出相差数百行的坐标（见第 8 条）。按 claim 里的行号导航会落到无关代码上。
2. **计划 §2.2 B1 与实现相反**（`docs/roadmap-evidence/M8-fingerprint-implementation-plan.md`，B1 明写「候选集是必需项」）：实现只对 `builder.gemspecs.map(&:loaded_from)` 求到的已加载 gemspec 取哈希（`server.rb:445`），不记录 glob 候选集；`C-M8-1-009`「边界」把同一情形降级为「属残余风险」。计划文档仍是「必需项」的口径，未回写。
3. **计划 §2.1 A1 要求 `gemfile.source=env|search`**：HEAD 指纹（本轮 11.1 第三段的 22 行）没有该键；`C-M8-1-007`「我方行为」的记录清单也没有。计划未回写，claims 未说明为何省。
4. **计划 §2.4 D1 与 `C-M8-1-014` 的覆盖键不一致**：D1 要求 `config.digest` 覆盖 `plugins`/`gemfile`/`path`/`force_ruby_platform` 四个求值键；实现覆盖 `app_config`/`plugin_root` 两项（`server.rb:412-419`）。claims 已按 oracle 收窄并给理由，计划未回写——按计划读会以为覆盖 4 键。
5. **计划 §2.5 E3 的 `bundler.profile` 未落指纹**：E3 要求 `bundler.version` 与 `bundler.profile` 都记；HEAD 只有 `bundler.version`，跨版本一致性由 `Profile.bundler_version` 作期望值比对、桥侧先抛 `BundlerVersionMismatch`。等效但计划文字未更新。
6. **本文件 §2「分句判定」与 §11 结论相反**：§2 第 4/6/7 行判「配置 不满足」「ABI 不满足」「任一输入变化 不满足」，§11 判全部满足。原因是 task-246（`C-M8-1-014`）在 task-238 之后落地了 config/abi 两段，而 §2 未标注「已被 §11 取代」。本轮只读，未改 §2；是否补历史注记请首辅裁。
7. **L162 字面「指纹…读取的 ENV」与实现载体不符**：ENV 不进指纹文本，进的是缓存键 `environment_signature` 与持久化条目的 `env` 字段。`C-M8-1-008`「我方行为」与 §2 第 3 行都按「有效覆盖」判满足，但没写明载体不是指纹文本，字面读者会判不满足。
8. **`C-M8-1-009` 与 `C-M8-1-014` 同文件内互相矛盾，且取代句越权**：
   - 坐标矛盾：009「我方行为」把 `Document#verify` 记在 `src/celerite/eval_fingerprint.cr:165`，014「我方行为」记 `:221`；HEAD 是 `:221`。两条 claim 并存且都可读，前者已失效。
   - 内容矛盾：009「边界」列「ABI 记录（runtime 无 `abi` 键）」「D1 `.bundle/config` 等配置文件的求值相关键（F1 不含，仅由客户端全量 ENV 签名兜底）」为未覆盖项；014 在「取代」句里声明取代 009 边界中「F1 指纹不含 D1 配置求值键、runtime 无 `abi.*` 键」的部分。ABI 部分确实已被取代（HEAD 有 4 条 `abi.*`），但 **D1 部分没有被取代**：014 实际只加 `config.app_config`/`config.plugin_root` 两条路径记录 + 对这两条的 `config.digest`（`server.rb:412-419`），并不含 plan D1 要求的四个配置求值键（`plugins`/`gemfile`/`path`/`force_ruby_platform`）。故 009 那条边界在实质上仍成立，014 的取代句覆盖过头。
   - 009「边界」正文内没有行内标记指出哪几句已被 014 取代，读者必须读到 014 的「取代」行才能判断。
