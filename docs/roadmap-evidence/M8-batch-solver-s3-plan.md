# M8 L161 S3：Crystal 调用 `solve_batch` 并接入解析——实施设计

> 任务：`task-266`
> 基线：`148f8556bbd15e96103b991be77a1029ef654df4`
> 工作树：`C:\temp\celerite-t266`（detached）
> 状态：**实施设计，未实现、未运行验证**。本文只新增设计文档，不改源码、spec、claims 或 roadmap 复选框。

## 1. 结论

1. **S3 只对 Bundler `4.0.24`、fingerprint 为 `deterministic`、所有参与求解的 source 均为 `Rubygems` / `pure_data` 的请求启用。** `2.7.2`、PATH/GIT/PLUGIN/Metadata/未知 typed source、动态 DSL、local-only、frozen/autoheal 的严格校验场景全部保留旧解析路径。
2. 调用顺序保持：**命令级 `LockFastPath` / `InstallFastPath` → `resolve!` 的 local-only 锁复用 → 纯数据 eligibility → 一次候选闭包采集 → 一次 `solve_batch` 请求/响应 → 回填既有 `Resolution` 结构**。不得先走旧 `evaluate_batch` 再走 `solve_batch`；S2 的结构化求值结果必须原样复用。
3. 当前基线**尚无 server 端 `solve_batch` dispatch/feature**：`assets/bridge/server.rb:70` 的 feature 列表没有该 op，`assets/bridge/server.rb:1407-1433` 会返回 `UnknownOp`。因此 **S2 的 server 注册、feature 协商、字节/超时/凭据门是 S3b 的硬前置**；S3a 可先做独立 DTO 与纯转换，但不能把当前基线称为已接通。
4. 求解器给出的语义失败必须映射为既有错误，**不得再静默 fallback 后把失败报成功**。仅协议不兼容、超时、响应超限、schema/identity/closure 不一致等“无法采用 batch 结果”的情况允许兼容回落；回落必须留诊断与“非 L161 命中”标记。
5. S3 **不新增 SolveCache 接线**。`EvalCache`、`FastPathStore`、`PlanCache` 各自边界不变；旧 RPC 与旧 Crystal PubGrub 路径继续作为兼容实现。

## 2. 依据与边界

### 2.1 已核实的实现事实

| 主题 | 证据 | 对 S3 的约束 |
| --- | --- | --- |
| 既有总体设计 | `docs/roadmap-evidence/M8-batch-solver-design.md:97-111` | S2 负责 server op/feature/限制；S3 负责 Crystal 预物化与一次提交；快路优先，fallback 不计 L161 |
| 无变化快路 | `src/celerite/cli/commands.cr:3114-3127`、`src/celerite/cli/commands_install.cr:277-289` | lock/install 的命令级快路必须保持在 batch 之前 |
| 安装解析入口 | `src/celerite/cli/commands_install.cr:520` | `resolution.resolve!(reuse, verify_locked_compat: verify_locked_compat)` 是接线面 |
| `resolve!` 全路径 | `src/celerite/resolution.cr:1101-1255` | local-only、source change、frozen/autoheal、reuse、drop incomplete 均在 `run_resolution` 前 |
| 真正求解入口 | `src/celerite/resolution.cr:1890-1927` | `run_resolution` 会 `build_index`、`build_locked` 并安装 lazy fetcher；batch 必须在其之前完成 |
| 旧 materialization | `src/celerite/resolution.cr:2189-2248`、`src/celerite/resolution.cr:2290-2351` | scoped remote fetch、PATH/GIT/PLUGIN 物化不得混入 pure-data batch |
| S2 求值 | `src/celerite/bridge/client.cr:1023-1069` | `evaluate_batch` 已返回结构化 dependencies/sources/fingerprint；不得再次求值 Gemfile |
| envelope/限制 | `src/celerite/bridge/client.cr:1307-1402` | 复用 proto/id envelope；solve 需要独立 op 文案与 32/8 MiB 限制，不能沿用 evaluate 的 4 MiB 文案 |
| S1 协议 | `assets/bridge/solve_batch.schema.json:7-240`、`assets/bridge/solve_batch.rb:15-21` | schema `/3`、完整 candidates/locked/promotion/constraints/closure；参考 Bundler 固定 `4.0.24` |
| S1 身份与摘要 | `assets/bridge/solve_batch.rb:244-290` | source identity、candidate digest、locked digest 必须逐字复现 Ruby canonical JSON 算法 |
| S1 纯数据门 | `assets/bridge/solve_batch.rb:397-509`、`assets/bridge/solve_batch.rb:542-567` | 非纯 source、fingerprint 非 deterministic、local-only、身份/闭包/checksum 不一致均拒绝；凭据字段/userinfo 拒绝 |
| 缓存边界 | `src/celerite/eval_cache_store.cr:11-16,68-102`、`src/celerite/fast_path_store.cr:20-59,82-123`、`src/celerite/plan_cache.cr:11-30,116-183` | 三类 store 均不是 solve result cache；只能复用 credential namespace 思路 |
| profile | `src/celerite/profile.cr:15-25` | 默认 `4.0.24`，环境变量可原样覆盖；S3 必须精确比较 `4.0.24`，不能做前缀或 semver 近似 |

### 2.2 本轮明确不做

- 不修改 `assets/bridge/solve_batch.rb`、schema、server dispatch；这些属于 S1/S2。
- 不修改 roadmap 复选框或 compat claims。
- 不运行 `crystal build`、`crystal spec`、Ruby harness、`script/differential` 或 Rails benchmark；当前处于完整 spec 安静窗口。
- 不把设计中的阈值、调用次数或性能收益写成实测结果。

## 3. 精确调用序与插入点

### 3.1 目标顺序

```text
lock/install command
  └─ LockFastPath.attempt / InstallFastPath.attempt       # 保持第一优先
       └─ Resolution 构造：S2 evaluate_batch 一次          # 不重复求值
            └─ resolve!(reuse, verify_locked_compat)
                 ├─ local-only + 已有锁复用分支             # 保持旧语义
                 ├─ BuildSolveBatchPlan.from_resolution    # 只读 Parsed Data，无 fetch/物化
                 ├─ eligibility miss → 旧 resolve! 全路径
                 └─ eligibility hit 且非 frozen/autoheal/local_only
                      ├─ 采集完整 GEM candidate closure   # 唯一前置索引 I/O
                      ├─ client.solve_batch(request)       # 一个 envelope，一次响应
                      ├─ 严格验证 response
                      └─ chosen/variants → ResolvedSpec → 既有 lock/install
```

“任何 fetcher/materialization 之前”指：**在 `run_resolution` 的 `build_index`、`ensure_source_dir`、`plugin_source_specs`、lazy `index_specs_for` 以及 PATH/GIT/PLUGIN 物化之前结束 batch 调用**。纯 GEM 候选闭包本身需要读取 compact index；这是唯一允许的前置索引 I/O，不得借此调用 Gemfile/gemspec/plugin 求值，也不得触发旧 resolver source callback。

### 3.2 `resolve!` 的具体改法

在 `src/celerite/resolution.cr:1252` 的：

```crystal
@resolved_specs = run_resolution(deps)
```

之前插入纯数据 gate，目标形态为：

```crystal
plan = BatchSolvePlan.from_resolution(self, deps)
if plan.eligible? && !@frozen && !@autoheal && !@local_only
  @resolved_specs = BatchSolver.resolve!(plan) || run_resolution(deps)
else
  @resolved_specs = run_resolution(deps)
end
```

但实现时必须同时调整 gate 的位置，不能只在 `:1252` 做判断：

1. `BuildSolveBatchPlan.from_resolution` 必须在 `src/celerite/resolution.cr:1155-1187` 的 frozen/autoheal materialization/stale probe，以及 `:1189-1235` 的 reuse materialization/stale/compat probe **之前**完成 eligibility。
2. 对 eligible 的非 frozen/autoheal/local-only 请求，直接进入 batch，不先调用 `path_specs_changed?`、`stale_locked_dependency_full_names`、`incompatible_locked_spec_names`。前者的 PATH 分支会调用 bridge，后两者会 fetch，见 `src/celerite/resolution.cr:1261-1302,1395-1481,1617-1647`。
3. `reuse == true` 时，命令级 `InstallFastPath` 仍是最高优先；若它已 miss，batch 可以抢占内部 reuse 探测，以避免 fetch 先于 solve。该选择可能让“不受信任的 no-op”多一次求解，但不得改变输出；必须由 S3c 的 no-op/RPC 断言证明可信快路没有被绕过。
4. frozen/autoheal/local-only 一律 eligibility miss，完整保留现有严格锁校验、stale 检查和本地解析语义。
5. source change 的排除逻辑必须在 plan 中体现：被 `changed_dependency_sources` 排除的 locked row 不得进入 `locked_base`，否则会把旧 source 的锁错误带入新 source。

### 3.3 防重复 Ruby 求值

- `Resolution` 构造时已经通过 S2 `evaluate_batch` 得到 `GemfileEvaluation`，见 `src/celerite/bridge/client.cr:743-758,1023-1069`。
- `BuildSolveBatchPlan` 只接受该 evaluation、当前 `deps`、lockfile、source registry、runtime/profile/promotion/constraints；**禁止传入 `Definition` 后重新调用 Ruby evaluator**。
- `solve_batch` 的 payload 只含纯数据。server 的 S1 实现也不会重新执行 Gemfile；其核心是真 `Bundler::Resolver`，见 `assets/bridge/solve_batch.rb:296-395`。
- 任何 miss 都发生在发出 `solve_batch` 之前。发出后若结果不可采用，允许进入旧 Crystal resolver，但不得再次调用 `evaluate_batch`/`evaluate_gemfile`。

## 4. 请求构造：从现有结构到完整纯数据

建议新增 `src/celerite/bridge/solve_batch.cr`，集中放 DTO、canonical serializer、请求/响应校验；`client.cr` 只增加薄方法。建议新增 `src/celerite/resolution/batch_solver.cr` 承载闭包采集与响应回填，`resolution.cr` 只保留 gate 和少量上下文接线。

### 4.1 eligibility 门

全部满足才可发请求：

- `profile.bundler_version == "4.0.24"`，不是 `2.7.2`、不是空值、不是近似版本。
- evaluation fingerprint 存在且 `state == deterministic`；`unknown`/`broken`/缺 section 均 miss。
- `evaluation_config`、Ruby/RubyGems/engine/platform/ABI 完整，且与当前 bridge runtime 一致。
- 所有 root/source/locked source 均为 `Rubygems` + `materialization == pure_data`，remote 已解析且可脱敏。
- 不存在 PATH/GIT/PLUGIN/Metadata/未知 typed source；即使锁文件能纯数据表示，也一律 miss。
- 不存在 local-only、prefer-local、frozen、autoheal；promotion/cooldown/unlock 能无损映射到 S1 字段。
- checksum 来源可证且无冲突；缺 checksum 的 locked candidate 需要旧路径回填时，本切片 miss。
- root dependency 能在 S2 evaluation 中找到唯一对应项，groups/platforms/autorequire/force_ruby_platform/gemspec_dev_dep 不丢失。
- 候选名数、候选总数、source 数、请求字节数、预计响应字节数均在上限内。

### 4.2 `ResolutionSource` 与 `source_id`

`source_id` 是协议内稳定键，不是 Ruby session id。S1 的 pure-data 路径不需要 session-local Source 对象；`assets/bridge/solve_batch.rb:276-279,422-424` 只校验 `identity_sha256`。

生成规则：

1. 主 Rubygems source 固定 `source_id = "default"`。
2. scoped source 先按“去掉 `source_id` 与 `identity_sha256` 后的规范化 source 对象”排序，依次分配 `source-0001`、`source-0002`。**不能直接用 identity digest 当 source_id**：S1 计算 identity 时对象包含 `source_id`，否则会形成循环依赖。
3. 同一规范化身份去重；若两个 source 获得同一 ID 但身份不同，或同一身份出现冲突 remote/options，直接 miss。
4. 构造完整 source 对象后，按 `assets/bridge/solve_batch.rb:244-279` 的算法计算 `identity_sha256`：递归排序 hash key、`remotes` 排序、去掉 `identity_sha256`、无空格 canonical JSON、SHA256 hex。
5. `uri_redacted` 只保留 scheme/host/path；删除 userinfo、query、fragment 中可能的 token。请求不得出现 header、env 原值、密码或 credential URI。

source 对象必须显式包含 schema 要求的全部键，包括空值为 `null` 的 path/revision/ref/branch/tag/glob/submodules/plugin_type/lock_options；不得靠省略字段通过 `additionalProperties: false`。

### 4.3 requirements

- 遍历 `resolve!` 的 `deps : Array(Resolver::DepSpec)`，按 name + source_id 关联 S2 `EvaluatedDependency`。
- `requirements` 使用现有 `Gem::Requirement` 的 lock 形式数组，保持顺序语义并与 S1 fixture 一致；不得把多个约束压成一个字符串。
- `groups`、`platforms`、`autorequire`、`force_ruby_platform`、`gemspec_dev_dep`、`direct` 从 evaluation 原样映射；缺失或歧义即 miss。
- 根 requirement 的 `source_id` 必须指向 4.2 的 source registry；不得默认全部落到 `default`。

### 4.4 candidate closure

采集算法：

1. 初始化 name 集合 = 所有 root dependency names ∪ 所有 `locked_base` names。
2. 对每个 name，从**每个 eligible Rubygems source** 取该 name 的全部版本、全部平台变体；不能只取当前平台或最高版本。
3. 每个 candidate 的 dependencies 加入 name 集合，继续 BFS，直到无新 name。
4. 按 `(source_id, name, version, platform)` 去重；完全相同的重复项可去重，checksum/dependencies/metadata 冲突必须 miss。
5. 采集完成后才允许 solve；不得由 solver 再回调 fetcher 补候选。
6. `candidate_closure.complete = true`，并计算 S1 canonical digest；`name_count`/`candidate_count` 必须与请求实际内容一致。schema 只限制“每 source 100000”，客户端必须另限**所有 source 合计 100000**，见 `assets/bridge/solve_batch.schema.json:7-184`。

字段映射：

| S1 candidate 字段 | Crystal 来源 | 规则 |
| --- | --- | --- |
| `name` / `version` | `Resolver::IndexSpec#name/#version` | version 用 canonical gem version 字符串 |
| `platform` | `IndexSpec#platform` | `platform.ruby?` 时序列化 `"ruby"`，否则用既有 platform 字符串；保留所有 lock extras |
| `dependencies` | `IndexSpec#dependencies` | name + requirements 数组；顺序不敏感，但内容不得丢失 |
| `required_ruby_version` | `IndexSpec#required_ruby_version` | 使用 canonical requirement；不得以运行时版本替换候选声明 |
| `required_rubygems_version` | `IndexSpec#required_rubygems_version` | 同上 |
| `created_at` | compact-index entry | 当前 `Resolver::IndexSpec` **没有该字段**，见 `src/celerite/resolver/source.cr:9-25`；S3a 需增加可选 `created_at : Int64?` 并从 `src/celerite/compact_index/cache.cr:442-445` 保留。按 schema 类型转换；无值时不得伪造当前时间，schema 不允许则 miss |
| `checksum` | compact index / lock CHECKSUMS / 已有 store | 统一 `{algorithm, value}`，value 小写；来源冲突即 miss，不读取 `.gem` 字节临时凑值 |

候选 digest 必须复现 `assets/bridge/solve_batch.rb:261-273`：依赖按 name/requirements 排序、requirements 排序、checksum value 小写、候选按 name/version/platform 排序，再 canonical JSON + SHA256。Crystal 默认 JSON 输出格式不能直接当作 Ruby canonical JSON；S3a 必须实现独立 byte-stable serializer，并用同一组 fixture 对拍。

### 4.5 locked_base

不能只使用 `@locked_specs`：`LockedSpec` 当前不含 dependencies/checksum/source_id，见 `src/celerite/resolution.cr:191-251,397-412`。

必须直接遍历 `Definition#lockfile` 的 sources/specs：

- `name/version/platform` 原样映射；ruby platform 规范化与 candidate 一致。
- `source_id` 由 lock source 的 type/remote/options 映射到 4.2 registry；无法映射即 miss。
- dependencies 保留锁文件边，转换为 S1 dependency 数组。
- checksum 从锁 CHECKSUMS/同一 candidate store 获取；锁定 candidate 必须能在对应 source 的候选集中找到，且 dependencies/checksum 与 S1 校验一致，见 `assets/bridge/solve_batch.rb:397-509`。
- locked digest 复现 `assets/bridge/solve_batch.rb:282-290`。
- source change 已排除的 spec 不进入 locked_base；不得为了“锁稳定”偷偷保留。

### 4.6 promotion / constraints / limits

- `promotion` 来自 `src/celerite/resolution.cr:718-733` 与 CLI 设置；level/strict/pre/unlock/conservative/prefer_local/local_only 逐项映射。任一无法无损表达即 miss。
- `constraints.bundler_version` 固定 `"4.0.24"`；runtime/platforms/added/removed/force_ruby_platform 来自当前 profile 与 resolution platforms，见 `src/celerite/resolution.cr:2366-2399`。
- 初始上限沿用 S1：请求 32 MiB、响应 8 MiB、候选总数 100000、source 4096、name 10000、timeout 60000 ms，见 `assets/bridge/solve_batch.rb:15-21`。这些是**未实测提案**，S3c/Rails 必须量化后再调整。
- timeout 是客户端整次 RPC 上限；server `timeout_ms` 传同一预算。不得截断请求/响应来冒充成功。

## 5. 客户端方法、响应验证与回填

### 5.1 client DTO/method

建议接口：

```crystal
def solve_batch(request : SolveBatchRequest) : SolveBatchResponse
```

职责：

- 构造 `{proto, id, op: "solve_batch", payload}`，复用 `src/celerite/bridge/client.cr:1307-1325` 的单行 envelope。
- 使用独立 `max_response_bytes = 8 * 1024 * 1024` 和 solve 专属错误文案；不得沿用 evaluate 的 4 MiB 常量。
- 发出前检查 request bytes、候选总数、凭据字段/userinfo；超限不发送。
- 读取一响应后立即校验 proto/id/schema；`ok` 与 `failure` 互斥。
- 不接受缺字段、未知字段、错误类型、重复 source_id、空 chosen 的成功响应或截断 JSON。
- 响应解析与回填不得调用 Ruby，不得触发 `index_specs_for`。

### 5.2 响应验证

`ok == true` 时至少验证：

1. `schema == "celerite.solve_batch/3"`。
2. `chosen` 非空；每项 name/version/platform/source_id/dependencies/checksum 均存在请求候选集中。
3. 每个 root requirement 至少被一条 chosen edge 满足；chosen 的 runtime dependencies 递归闭包完整。
4. `edges` 与 chosen/dependencies 一致；不得用 edges 再跑一次 solver。
5. `variants` 中每项仍属于请求 candidate；非本地 platform 只能形成 lock extra。
6. candidate/locked/closure digest、stats 与请求规模一致；server 若少返候选或多返未知 source，判协议失败。
7. checksum 与 locked_base/store 一致；不一致不得“修复”后继续。

### 5.3 转回内部结构

- chosen → `ResolvedSpec`，复用 `src/celerite/resolution.cr:2072-2142` 的字段语义：name/version/platform/dependencies/checksum/source_index/source_type/source_info/source_remote/required_ruby_version/required_rubygems_version/default_gem。
- `source_id` 反查 4.2 registry，恢复 GEM source 与 remote；不得把 source_id 当 remote 写入锁。
- dependencies → 既有锁依赖结构；checksum object → 锁文件 `sha256=<hex>` 形式。
- required versions → `Gem::Requirement`；platform `ruby`/nil 按现有规范化处理。
- 本地 best match 复用 `src/celerite/resolution.cr:2148-2158` 的 `best_match_variants` 逻辑；非本地变体写入 `@lock_extra_specs`，不得进入当前 install set。
- 回填后直接进入既有 lock writer/installer；不得再次 `evaluate_batch`、再次 solve 或偷偷调用旧 resolver 补边。
- 若回填过程中发现无法无损转换，整次 batch 结果作废并进入明确的兼容回落；不得返回部分解。

## 6. profile、缓存与旧 RPC 边界

### 6.1 分档

| 场景 | S3 行为 |
| --- | --- |
| Bundler 4.0.24 + deterministic + 全 Rubygems/pure_data | 允许 batch |
| Bundler 2.7.2 | 一律旧路径；不得发送 solve_batch |
| 4.0.24 + fingerprint unknown/broken | 旧路径 |
| Ruby/RubyGems/engine/platform/ABI/evaluation_config 变化 | eligibility miss；缓存与 runtime 记录均不得跨 ABI 复用 |
| PATH/GIT/PLUGIN/Metadata/未知 source | RPC 前 fallback |
| local-only/prefer-local/frozen/autoheal | 保留旧路径 |
| 请求/响应超限、timeout、UnknownOp、schema mismatch | 可兼容 fallback，但不计 L161 |

`src/celerite/profile.cr:15-25` 的环境变量不做 trim/校验，因此比较必须精确；`"4.0.24 "` 或空值都不能命中。

### 6.2 缓存

- `EvalCache` 只缓存 evaluation，见 `src/celerite/eval_cache_store.cr:11-16`。S3 可读取它得到 fingerprint/evaluation，但不得把 solve 结果写入 evaluation entry。
- `FastPathStore` 只记录 runtime/decision，见 `src/celerite/fast_path_store.cr:20-59,82-123`。batch 命中/回落可作为未来决策字段，但本切片不写入 lock/plan/chosen。
- `PlanCache` 当前未接命令，见 `src/celerite/plan_cache.cr:11-14`。S3 不改其接线，也不把 solve response 当 plan cache。
- 未来独立 SolveCache 的 key 至少包括：schema/client build、fingerprint digest/state、evaluation runtime+ABI+config、credential namespace、source identities、locked digest、candidate closure digest、promotion、constraints、profile。unknown/broken 不写；credential namespace 复用 `src/celerite/eval_cache_store.cr:68-83` 的 `BUNDLE_*` 哈希思路，明文不得进入 key/value/log。
- 本切片不实现 SolveCache，避免把尚未验证的 candidate closure 持久化。

### 6.3 何时保留旧 RPC

以下情况保留旧 `evaluate_batch` / 旧 resolver RPC：

- 所有 eligibility miss，尤其 `2.7.2` 与 typed source。
- 命令级或 local-only 快路命中。
- batch 协议不可采用：UnknownOp、proto/id 错、EOF、timeout、请求/响应超限、schema mismatch、identity/closure/checksum 不一致、server internal/source_unsupported/candidate_incomplete。
- frozen/autoheal 的严格路径。

兼容 fallback 必须标记 `solver_path=compatibility`，不得计入 L161 的 batch 成功数。默认成功回落不得新增用户可见 stderr，以免破坏差分；诊断通过 opt-in 环境变量开启。

## 7. 错误分类、exit code 与脱敏诊断

CLI 通用 rescue 使用 `ex.status_code`，见 `src/celerite/cli.cr:56-58`。既有错误定义见 `src/celerite/errors.cr:205-239`。

| batch 结果 | 处理 | exit / stderr |
| --- | --- | --- |
| `requirements_conflict` | 直接抛 `SolveFailureError`，**不 fallback** | 6；沿用既有 solver 文案 |
| `ruby_incompatible` | Gemfile 目标 runtime mismatch 已由既有校验处理；候选 metadata 导致无解映射 `SolveFailureError` | 6；若既有 runtime 校验先触发则为 18 |
| `platform_unavailable` | 映射 `GemNotFoundError` | 7；沿用 platform/no matching spec 文案 |
| `source_unsupported` / `candidate_incomplete` / `checksum_invalid` | 协议/输入不可采用，兼容 fallback | fallback 自身结果决定 exit；默认不新增 stderr |
| `internal` / schema mismatch / 未知字段 / 空成功解 | 兼容 fallback，记录协议诊断 | fallback 自身结果决定 exit |
| `UnknownOp` | 说明 S2 未接通，兼容 fallback | fallback 自身结果决定 exit |
| timeout | 兼容 fallback，不做第二次 batch 重试 | fallback 自身结果决定 exit |
| request/response 超限 | `BatchTooLargeError` 分类后兼容 fallback；不截断 | fallback 自身结果决定 exit |
| proto/id 错、EOF、bridge crash | 兼容 fallback；不泄漏 payload | fallback 自身结果决定 exit |
| 凭据字段/userinfo 命中 | 发送前拒绝；server 拒绝则作废本次结果 | 不输出 URI/token/header；fallback 只走既有受控凭据路径 |
| fallback 也失败 | 报告旧路径的真实异常 | 既有 exit/stderr，不得用 batch 成功覆盖 |

S1 的分类是消息文本启发式，见 `assets/bridge/solve_batch.rb:742-752`；`ruby_incompatible` 不能简单等同于 exit 18。S3c 必须分别覆盖 runtime mismatch、候选 required-ruby 无解、platform unavailable、普通版本冲突。

诊断格式仅允许：op、category、request/response bytes、schema、source_id、digest、耗时、`solver_path`。禁止输出完整 payload、URI userinfo、query token、header、env 值或 exception backtrace 中的敏感字段。建议 opt-in `CELERITE_SOLVE_BATCH_DIAG=1`；成功兼容回落默认静默。

## 8. 可执行切片

### S3a：client DTO/method + 纯数据转换

- **目标**：在不接 resolution 的情况下，构造/解析 `/3` 请求响应，验证 canonical identity/digest、字节上限和脱敏。
- **写入范围**：新增 `src/celerite/bridge/solve_batch.cr`；改 `src/celerite/bridge/client.cr`；在 `src/celerite/resolver/source.cr:9-25` 增加可选 `created_at : Int64?` 并由 compact-index 转换处赋值；新增 `spec/m8_solve_batch_client_spec.cr`。
- **依赖**：S1 schema/solver 已存在；server feature 不是 S3a 单测前置，可用脚本化响应。
- **验收**：canonical digest 与 Ruby fixture 一致；缺字段/未知字段/错 schema 拒绝；32 MiB/8 MiB 边界与超 1 byte；credential sentinel 不出现在 request/stderr/cache；`created_at` 缺失不伪造。
- **反假绿**：至少一个 fixture 故意改变 dependencies 顺序/checksum 大小写，验证“规范化”而不是“偶然相同”；一个 fixture 改变 source_id，验证 identity 必须重算。

### S3b：resolution 接线

- **目标**：pure-data 4.0.24 请求在快路后一次 solve，回填 chosen/variants 并继续既有 lock/install；所有 miss 保留旧路径。
- **写入范围**：新增 `src/celerite/resolution/batch_solver.cr`；改 `src/celerite/resolution.cr`；新增 `spec/m8_solve_batch_resolution_spec.cr`。
- **依赖**：S3a；**S2 server dispatch/feature/limits 必须已合入**。
- **验收**：eligible 用例仅一次 `solve_batch`、零次二次 evaluate；响应后不调用旧 `build_index`/typed source materialization；2.7.2 与 PATH/GIT/PLUGIN/Unknown 用例零 batch RPC；chosen/variants/lock extras 与既有结构一致；语义失败不 fallback。
- **反假绿**：用桥统计断言 RPC op 序列，而不只断言最终 exit 0；在响应中删一条 edge/改 source_id，必须 fallback 或失败，不能产出部分锁。

### S3c：负向 spec + 双 profile 定向差分 + Rails 冒烟

- **目标**：证明 batch 不破坏既有输出，并给 S4 的真实 Rails/性能闭环提供入口。
- **写入范围**：新增 `spec/m8_solve_batch_negative_spec.cr`；如差分夹具确需新增，限定 `fixtures/differential/m8-solve-batch-*`；不改 roadmap/claims。
- **依赖**：S3b；双 profile/Rails 必须等完整 spec 安静窗口结束并由 lead 安排。
- **验收**：
  - spec：timeout、超限、UnknownOp、schema mismatch、identity/closure/checksum 错、凭据脱敏、typed source fallback、profile fallback、语义失败不二次 RPC。
  - 4.0.24 与 2.7.2：对同一目标夹具运行 `bash script/differential <fixture>`，断言 stdout、stderr、lock bytes、exit code；2.7.2 必须零 solve_batch。
  - Rails：复用 `docs/roadmap-evidence/M8-rails-bench.md:19-20` 的 Rails 8.0.2 / 64-gem 最小样本，比较双侧 lock 与退出码，并记录 RPC/字节；冷/热/noop 性能归 S4，不在 S3c 冒充完成。
- **反假绿**：旧二进制或强制 `try_solve_batch = nil` 作为负对照；新正例必须实际出现 `solve_batch` 统计，不能只靠“输出相同”证明新路径执行。

### S4（不在本任务实现）

真实 Rails 规模、双 profile 全量定向回归、冷/热/noop 性能与字节统计、候选/响应上限量化。S3c 的 Rails 冒烟通过不等于 S4 完成。

## 9. 风险与未验证项

1. **未运行任何 build/spec/harness/differential/Rails**；所有调用次数、阈值和输出等价均为设计断言，不是实测。
2. 当前基线 server 无 `solve_batch` feature/dispatch；S2 未合入前，eligible 请求会得到 `UnknownOp` 并走兼容路径。
3. `Resolver::IndexSpec` 当前无 `created_at`，见 `src/celerite/resolver/source.cr:9-25`；从 compact-index 保留该元数据并保持所有构造调用兼容，尚未实现/验证。
4. Crystal canonical JSON 与 Ruby `JSON.generate` 的字节一致性尚未实现对拍；哈希键排序、数字/字符串、nil、UTF-8 均需 fixture 固化。
5. source scoping 下“每个 name 从每个 pure source 取全部候选”可能放大请求；Rails 64-gem 样本的真实候选数、32/8 MiB 是否够用未测。
6. checksum store 在 compact index、lock CHECKSUMS、vendor/cache 之间的优先级与冲突处理尚未对真实 Rails 锁验证；S1 本身不校验 gem 字节。
7. `created_at` 缺失时 schema 的可空性与 S1 resolver 行为需以 fixture 确认；不得填当前时间。
8. S1 failure category 依赖消息正则；平台/Ruby 边界文案变化可能改变分类，需双 profile 负向用例锁定。
9. timeout 后 Ruby 子进程清理、Windows 管道残留、超限响应内存峰值未验证。
10. 兼容 fallback 默认静默是零输出要求与可诊断性的折中；opt-in 诊断字段和指标命名尚未实现。
11. 真实 Rails lock 是否逐字节等价、lock extras 是否完整、install 是否触发二次 materialization 均未验证。
12. 本文所有未来文件与代码形态都是建议；不得据此勾选 L161 或声称 S3 已完成。

## 10. 完成定义

S3 只有在以下条件全部满足后才可声明实现完成：

- S2 server op/feature 已存在，S3a/S3b/S3c 全部合入。
- eligible 4.0.24 pure-data 用例有一次且仅一次 solve RPC，无二次 evaluate/materialization。
- chosen/variants 回填后 lock/install 输出、锁文件、退出码与参考一致。
- 2.7.2 与所有 typed source/unknown/broken/profile mismatch 保持旧路径。
- 负向协议/超时/超限/凭据用例有可复现证据，兼容回落不计 L161。
- 双 profile 定向差分与 Rails 64-gem 冒烟有实际记录；未跑项明确保留为未验证。

在此之前，L161 S3 状态只能是“设计已提交，实现未验证”。
