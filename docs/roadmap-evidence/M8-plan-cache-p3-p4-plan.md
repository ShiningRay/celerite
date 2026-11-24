# M8 task-264：PlanCache P3/P4 集成与安全设计

- 基线：`95e19a0db3945f416ad45e6706d516ce93374ec5`
- 性质：设计稿；本文不修改 `src/`、`spec/`、claims 或 roadmap 勾选。
- 验证状态：未运行 `shards build`、`crystal spec`、Crystal 格式化检查或指定 Bundler 差分。所有性能收益均为待测命题，不是实测结论。

## 1. 结论先行

1. HEAD 的 `PlanCache` 只有 P1 的键构造与读取，没有 writer，也没有命令接线。P3/P4 不能绕过这个前置条件。
2. task-253/258 已经提供可信无变化 `lock` / `install` 的零 Ruby 路径。PlanCache 不新增第二套 `lock` 快路径，也不把“少 2 RPC”重复计入收益。
3. P3 的唯一增量场景是：**已通过 `LockFastPath.trusted_attempt` 的 remote-only、锁定复用安装，但现有 no-op 安装路径因缺 gem 等原因未命中**。此时用持久化 locked plan 重建 `Resolution`，跳过 `evaluate_batch`；`bundler_cache_file` 只有在缓存路径与当前 Ruby 默认缓存逐项核对后才可跳过。Bridge 进程仍然存在。
4. P4 不另写零 Ruby 安装器。现有 `InstallFastPath` 继续作为权威路径；PlanCache 的 installed snapshot 只作为可选完整性层，且不得削弱现有门禁。
5. 现有 `InstallFastPath` 的 2.7 no-op 计数与普通安装不一致：普通路径为 Bundler 额外 `+1`，快路径没有。P4 宣称输出一致前必须先修正，并让两条路径共用纯汇总函数。
6. `CELERITE_PLAN_CACHE=1` 本身不授予信任。P3/P4 的读写都必须以现有 FastPath/EvalCache 信任链为前置；独立开启 PlanCache 不得产生 hit。

## 2. HEAD 事实与锚点

| 位置 | 当前事实 | 对设计的约束 |
| --- | --- | --- |
| [plan_cache.cr:141–228](<src/celerite/plan_cache.cr#L141-L228>) | 六类键成分：sources、credential namespace、checksums、platform、ABI、build；不包含 Gemfile/evaluation digest | payload 必须携带 provenance，并在读取时与当前可信 evaluation 对照 |
| [plan_cache.cr:232–261](<src/celerite/plan_cache.cr#L232-L261>) | GEM URI 去 userinfo/query/fragment；PATH 归一为项目根下绝对路径；GIT 要求 40-hex revision | remote-only 才可跨项目根复用；PATH/GIT/plugin 一律不进入 P3/P4 hit |
| [plan_cache.cr:282–321](<src/celerite/plan_cache.cr#L282-L321>) | 校验 envelope、重算键 hash、当前凭据命名空间和 payload digest；损坏删除，I/O 错误按 miss | P3 必须增加语义校验，不能弱化 P1 |
| [lock_fast_path.cr:122–175](<src/celerite/lock_fast_path.cr#L122-L175>) | 可信命中需锁文件、无 checksum 刷新、本地平台、空 plugin root、项目 runtime record、已验证持久 evaluation、空 warning、remote-only、依赖/源匹配、完整锁定边、本地 RuntimeFacts、CRuby 不变量、Allowed 决策 | 这是 P3/P4 唯一信任入口，不复制、不绕开 |
| [lock_fast_path.cr:183–221](<src/celerite/lock_fast_path.cr#L183-L221>) | runtime record 只在成功的 lock/install 后写入；持久化失败不影响命令 | PlanCache writer 同样只在成功后写入，失败必须静默 |
| [commands.cr:3119–3131](<src/celerite/cli/commands.cr#L3119-L3131>) | `run_lock` 先走 `LockFastPath`，命中直接重写锁；只有 miss 才构造 `Resolution` | 可信 lock 已在创建 bridge 前返回；P3 没有可重复节省的 2 RPC |
| [commands.cr:3294–3315](<src/celerite/cli/commands.cr#L3294-L3315>) | `write_locked_lockfile` 负责保存锁的重写、BUNDLED WITH 与 2.x Bundler 自行 | lock 继续沿用该函数，不由 PlanCache 重写输出 |
| [commands_install.cr:277–330](<src/celerite/cli/commands_install.cr#L277-L330>) | 现有 `InstallFastPath` 在 `Bridge::Client.shared` 之前；普通路径随后求值并构造 `Resolution` | P3 插在 no-op attempt 之后、普通 `Resolution.new` 之前，复用同一次可信求值 |
| [commands_install.cr:937–1003](<src/celerite/cli/commands_install.cr#L937-L1003>) | 普通汇总、2.x Bundler `+1`、安装路径、funding/clean/cooldown 文案 | no-op 必须共用同一纯汇总逻辑，不能只复制两行文案 |
| [install_fast_path.cr:26–85](<src/celerite/install_fast_path.cr#L26-L85>) | no-op 路径拒绝 verbose/hooks、Bundler 不匹配、groups、frozen/deployment、shared gems、force-ruby-platform、clean、cooldown、app cache、funding 与不完整树 | P4 保留全部拒绝条件；P3 可复用 locked plan，但仍须由普通命令流处理这些 flag |
| [install_fast_path.cr:90–103](<src/celerite/install_fast_path.cr#L90-L103>) | hit 只输出汇总与安装路径 | 修正 2.7 计数前不得宣称双 profile 输出一致 |
| [install_fast_path.cr:150–177](<src/celerite/install_fast_path.cr#L150-L177>) | 仅检查 gemspec、gem 目录、filename-only index 与扩展 marker；遍历全部锁平台行 | 不证明文件内容完整；多平台锁会产生安全但过宽的 false miss |
| [resolution.cr:326–340](<src/celerite/resolution.cr#L326-L340>) | 构造器立即取 bridge、求值、记录 Bundler 版本并查询 `bundler_cache_file` | `from_plan` 必须显式重建这些字段，不能留下半初始化对象 |
| [resolution.cr:1649–1695](<src/celerite/resolution.cr#L1649-L1695>) | `materialize_locked` 从锁重建本地安装行，并分离额外平台行 | P3 payload 只缓存这一纯锁定结果，不缓存 solver 决策 |
| [resolution.cr:2538–2729](<src/celerite/resolution.cr#L2538-L2729>) | 生成锁使用现有 checksum；4.x 还可能写入 Bundler 自 checksum | 省略 `bundler_cache_file` 前必须证明不会增删 Bundler checksum |
| [installed_index.cr:25–161](<src/celerite/installed_index.cr#L25-L161>) | index 只记录文件名元数据，不读取/哈希 gemspec 内容或依赖 | snapshot 如要检测篡改，必须自行保存内容 digest |
| [installer.cr:43–68](<src/celerite/installer.cr#L43-L68>) | 扩展路径不含 build args；复用 marker 仅 `gem.build_complete` | build args 已进入 PlanCache 键；marker 只证明“曾完成”，不证明内容未变 |
| [runtime_facts.cr:77–115](<src/celerite/runtime_facts.cr#L77-L115>) | `Facts#matches?` 要求七个运行字段全部已知且相等，不使用通配符 | P3/P4 不得以 ABI 相同替代完整 runtime 匹配 |
| [eval_cache_store.cr:104–132](<src/celerite/eval_cache_store.cr#L104-L132>) | 同目录临时文件、flush/fsync、删除旧目标后 rename；失败清理 | P2 writer 复用该原子写模式；并发同键写入必须产生等价 canonical bytes |

历史文档 `docs/roadmap-evidence/M8-plan-cache-plan.md` 的 10 RPC/315715 B、2 RPC/1911 B、1053–1146 ms、404–794 ms 与 ~300 KB 均属于旧基线 `053036e` 的测量，不能作为 HEAD 或 P3/P4 收益证据。

## 3. 不可破坏的安全不变量

### 3.1 信任来源

- P3/P4 的 evaluation 只能来自 `LockFastPath::Hit.evaluation`，不得从 PlanCache payload 反推出 Gemfile 语义。
- 每次 hit 前重新执行 `trusted_attempt` 的全部检查；不能仅信任 payload 内的自述字段。
- payload 的 `evaluation_digest`、lockfile digest、精确 Bundler 版本、平台、ABI、build 配置必须与当前可信上下文逐项相等。
- 任何 unknown、缺字段、类型错误、超限、源类型不受支持、warning 非空、runtime record 不匹配，一律 miss。
- 缓存 I/O、解析、writer 失败不得改变 stdout/stderr、退出码或锁文件；只有 `CELERITE_PLAN_CACHE_DEBUG=1` 可输出原因，且不得打印凭据或完整 source URI。

### 3.2 键与 payload 分离

- 保留 P1 的六类键与 `plan/v1/<namespace>/<key>.json` 布局，避免破坏已有读取契约。
- P3 locked-plan payload 必须可跨项目根：只存相对路径、去凭据 URI 和纯数据；不存绝对 `install_root`、绝对 gemspec 路径或原始 ENV/config。
- provenance 至少包含：`schema`、`evaluation_digest`、`lockfile_sha256`、`bundler_version`、`local_platform`、ABI 三元组、build 配置 digest、去凭据 `primary_remote`。
- 如未来 payload 必须含绝对路径，则该版本不得复用 root-independent 键；必须在读取时逐项核对当前 project/install root，不相等即 miss。
- credential namespace 继续只以 hash 形式落盘。writer 在最终 canonical JSON 字节上再做一次凭据 URI 扫描，拒绝写入，不只扫描已知字段。

### 3.3 缓存投毒边界

- SHA-256 与 payload digest 只证明内部一致性，不提供恶意本地写入者的身份认证。同机恶意进程不在本设计的安全承诺内。
- reader 必须拒绝绝对路径、`..`、盘符/UNC、symlink 逃逸与重复/冲突相对路径；所有文件访问限制在当前 install root 内。
- snapshot 不得跟随指向 root 外的链接；遇链接或特殊文件按 miss，不读取目标内容。
- 写者只在命令成功后、最终锁文件与安装树稳定后发布 payload；半安装、失败安装、回滚中状态不得入缓存。

## 4. P2 writer 前置契约

P3/P4 实施前，P2 必须提供确定性 writer。建议 envelope 继续使用 `celerite-plan-cache/1`，在 payload 内独立演进 schema。

### 4.1 locked-plan payload

```json
{
  "schema": "celerite-locked-plan/1",
  "provenance": {
    "evaluation_digest": "<64-hex>",
    "lockfile_sha256": "<64-hex>",
    "bundler_version": "<exact-version>",
    "local_platform": "<platform>",
    "abi": {
      "ruby_api_version": "<value>",
      "extension_api_version": "<value>",
      "rbconfig_ruby_version": "<value>"
    },
    "build_digest": "<64-hex>",
    "primary_remote": "<sanitized-uri>"
  },
  "plan": {
    "specs": ["<serialized ResolvedSpec>"],
    "extra_platform_specs": ["<serialized ResolvedSpec>"]
  },
  "bundler_cache": {
    "version": "<exact-version>",
    "path": "<optional-absolute-path>",
    "sha256": "<optional-64-hex>"
  }
}
```

约束：

- `specs` 只序列化 `materialize_locked` 的本地行；`extra_platform_specs` 原样保留，供生成锁使用。
- `ResolvedSpec` 的可空字段必须保留 `null` 语义，不能用缺键冒充 nil；locked reuse 的 required Ruby/RubyGems/default_gem 继续为 nil。
- 不保存 solver 候选、完整 evaluation、Gemfile 文本、原始 ENV、config 值或凭据。
- writer 只接受“普通命令最终选择锁定复用且语义锁未变化”的成功结果。source/path/incomplete 变化、checksum 刷新、解锁、更新语义一律不写。
- 沿用现有 256 entries / 16 MiB 上限；超限不写，不截断 JSON。
- 原子写复用 `src/celerite/eval_cache_store.cr:104-132` 的模式。canonical JSON 必须稳定排序，保证同键并发写得到等价字节。

### 4.2 installed snapshot（P4 可选层）

snapshot 不与 P3 payload 混放，建议使用现有 `FastPathStore::RuntimeRecord.project_digest` 作为项目作用域：

```text
installed/v1/<runtime_record.project_digest>/<plan_key>.json
```

payload 至少包含：

- `schema = celerite-installed-snapshot/1`；
- `evaluation_digest`、精确 Bundler 版本、平台、ABI、build digest；
- 当前 install root 的规范化 digest（只用于核对，不据此跨根命中）；
- 每个本地安装项的相对路径、文件类型与 SHA-256；
- 生成时的 runtime record digest。

最低内容集：

1. 每个本地 `specifications/<full_name>.gemspec` 的内容 digest；
2. `gems/<full_name>` 下参与运行的文件 digest；
3. 有扩展时的扩展输出与 `gem.build_complete` digest；
4. 对应 `InstalledIndex` 条目 digest。

`cache/*.gem`、binstubs、doc 不进入最低集；若未来把它们纳入输出/文件一致性承诺，再单独扩矩阵并重测 I/O。全树 manifest 超过现有 16 MiB 上限时拒绝发布 snapshot，不得静默截断。

## 5. P3：可信 locked-plan 重建

### 5.1 接入点与顺序

`run_install` 的顺序改为：

1. `Definition.build` 与现有参数/配置校验；
2. 只做一次 `LockFastPath.trusted_attempt`，得到 `Hit?`；
3. 把同一 `Hit` 交给现有 `InstallFastPath.attempt`；命中则沿用 task-258 的零 Ruby no-op，P3 不参与；
4. no-op miss 且 `Hit` 存在时，读取并语义校验 PlanCache；
5. PlanCache hit：仍创建普通 install 所需的 bridge，但用 `Resolution.from_plan(...)` 替代 `Resolution.new(...)`；
6. 任意 miss：完全沿用现有 `Resolution.new` 兼容路径。

请求更新、解锁、`--add-checksums` 或其他会改变 resolution/lock 语义的 flag 时，P3 必须 miss；不得用旧 plan 代替本次请求的解析结果。

不得让 `InstallFastPath` 与 P3 各自重跑一遍文件哈希和 runtime 校验。提取一次可信上下文，是正确性与性能共同要求。

### 5.2 `Resolution.from_plan`

新增显式构造入口，至少设置：

- `@definition`、`@bridge`、`@owned_bridge`；
- `@evaluation = hit.evaluation`；
- `@sources = hit.evaluation.sources`；
- `@bridge_bundler_version = hit.bundler_version`；
- 从 payload 恢复的 `@resolved_specs`、额外平台行、`@root_dependency_names`；
- `@resolved = true`，且只能对应锁定复用；
- 普通路径需要的索引/候选缓存空容器。

禁止通过 `allocate` 后零散赋值来绕过构造不变量；必须集中构造并让类型系统覆盖必填字段。

### 5.3 两个 RPC 的真实归属

普通冷路径中，`Resolution.new` 会触发：

- `evaluate_batch`；
- `bundler_cache_file`。

P3 用 `hit.evaluation` 跳过前者。后者只有在以下条件全部成立时才可跳过：

- payload 的 Bundler 版本与当前精确相等；
- payload 路径等于当前 `RuntimeFacts.default_gem_dir/cache/bundler-<version>.gem`；
- 该文件存在且当前 SHA-256 等于 payload；
- 当前 profile 为 4.x，且生成锁确实需要 Bundler 自 checksum。

任一条不成立，必须延迟调用现有 `bundler_cache_file`，不能把 `nil` 当作“没有缓存文件”。因此：

- 常见默认 Ruby 布局：P3 可省 `evaluate_batch` + `bundler_cache_file` 两个 RPC；
- 自定义/隔离 GEM_PATH 或缓存文件变化：只省 `evaluate_batch`，或回退普通路径；
- EvalCache 已命中时 `evaluate_batch` 本来可能无 RPC，此时不得重复宣称 2 RPC 收益；
- install 仍会调用 `ruby_environment`，且 bridge 进程仍为 1；P3 不是零 Ruby 路径。

### 5.4 lock 不新增 P3 hit

`run_lock` 的可信命中已在 `Resolution.new` 之前返回。冷 EvalCache 时 PlanCache 又不能替代 evaluation 信任，故 P3 对 lock 没有独立增量。保留现有顺序与 `write_locked_lockfile`，不新增第二写锁逻辑，也不把 lock 的零 Ruby 收益重复归给 PlanCache。

### 5.5 P3 验收

- 双 Bundler profile 下，缺一个已锁 gem 的 install：输出、锁文件、安装树、退出码与普通路径一致。
- 常见默认缓存布局下，冷 EvalCache 的 RPC 计数减少 2；自定义布局只减少 1；EvalCache warm 单独报告。
- Bridge `procs` 不因 P3 变成 0；现有 no-op 路径仍为 0。
- 无 runtime record、EvalCache miss、fingerprint unknown/broken、warning 非空、PATH/GIT/plugin、checksum 缺失、Bundler 版本变化、payload 语义不符均回退。
- payload 损坏、超限、字段类型错误、路径逃逸、凭据 URI 写入拒绝均不影响命令结果。
- 不同项目根但相同 remote-only 键：必须使用当前 `Hit.evaluation` 与当前 install root，不能套用旧根路径。
- `CELERITE_PLAN_CACHE=0` 与 writer 失败时，行为与 HEAD 一致。

## 6. P4：复用零 Ruby 路径，snapshot 只做可选加固

### 6.1 不复制安装器

P4 的权威 hit 仍是 `InstallFastPath`。PlanCache snapshot 不负责输出摘要、不负责创建 bridge、不负责安装 gem，也不绕过 ProcessLock。

推荐两级语义：

- **P4a（必需）**：沿用现有结构性 no-op 路径，修正已知偏差；L164/L168 由 task-253/258 与回归测试闭环。
- **P4b（可选加固）**：`CELERITE_PLAN_CACHE=1` 且 snapshot 存在时，在结构性检查后追加内容校验。snapshot 缺失仍可使用 P4a；snapshot 损坏、root/runtime 不匹配或 digest 不符则放弃 hit，走普通兼容路径以修复/重算。

P4b 不得宣称“snapshot 缺失时仍能检测篡改”；其承诺仅覆盖存在且校验通过的 snapshot。

### 6.2 命中顺序

1. 现有 flag、Bundler、groups、frozen/deployment、shared gems、force-ruby-platform、clean、cooldown、app cache、plugin/hook、funding 门禁；
2. `LockFastPath.trusted_attempt`；
3. 结构性完整检查；
4. 如启用 P4b，核对 snapshot scope 与文件 digest；
5. 获取 install root 的 `ProcessLock`；
6. **在锁内重新执行受影响的结构/snapshot 检查**，避免 attempt 到 emit 之间安装树变化；
7. 调用共享纯汇总函数与 `emit`，返回 0。

当前 attempt 在锁外、锁在 hit 后获取。P4 必须把树校验移到锁内或做锁内复验；仅靠缓存 payload 无法消除 TOCTOU。

### 6.3 结构检查修正

- 只检查 `materialize_locked` 选出的本地行，不要求非本地平台变体也已安装；这消除多平台锁的 false miss，不扩大 hit 范围。
- 保留 gemspec + gem dir + index entry + 扩展 marker 的最低结构要求。
- funding 判断继续读取真实 gemspec；snapshot 的 funding 标记只能加速，不能替代当前文件判断。
- 内容 digest 是 P4b 的额外保证；P4a 仍只声称“结构完整”，不声称“未被篡改”。

### 6.4 2.7 汇总缺陷修复

已确认普通路径在 `src/celerite/cli/commands_install.cr:950-956` 对 2.x 执行 `gems_count += 1`，而 `src/celerite/install_fast_path.cr:73-75` 直接使用 reachable specs 数量，`emit` 不再补 1。

修复要求：

- 提取共享纯函数，输入 evaluation、installable/reachable specs、skipped groups、精确 Bundler 版本、switched Bundler 状态与安装路径；
- 输出普通路径与 no-op 路径使用的相同计数值、单复数、路径提示；
- 2.7.2 与 4.0.24 各加无变化 install 差分，断言 stdout、锁文件与退出码；
- plugin 继续被快路径拒绝，不把 plugin 隐藏计数带入 P4。

### 6.5 writer 时机

- P3 plan 在成功 lock/install 后写入，沿用 `remember_after_*` 的“成功才记”原则。
- P4 snapshot 只能在安装完成、锁文件写入完成且仍持 ProcessLock 时采集；锁释放后再扫描会产生竞态。
- 写失败、只读缓存目录、并发 writer 均不得改变命令结果。

### 6.6 P4 验收

- 无变化 lock/install：`bridge: procs=0`；双 profile stdout、锁文件、安装树与退出码一致。
- 2.7 汇总计数回归通过。
- 缺 gemspec、缺 gem dir、缺 index、缺扩展 marker、扩展内容变化、gemspec 内容变化分别按预期 miss。
- 多平台锁只要求本地变体，不因额外平台行 false miss。
- snapshot 超限、字段损坏、root 不符、runtime 变化、symlink 逃逸均安全回退。
- wall/CPU/RSS/RPC/bytes/file I/O 分冷/热、snapshot 开/关、P4a/P4b 报告；在全树 hash 成本高于收益时保留 P4a，不硬推 P4b。

## 7. 失效矩阵

| 变化 | P3 locked plan | P4 no-op / snapshot |
| --- | --- | --- |
| Gemfile/evaluation digest 变化 | miss | miss |
| 锁内容、checksum、依赖边变化 | miss | miss |
| source identity 或 credential namespace 变化 | miss | miss |
| PATH/GIT/plugin 源 | miss | miss |
| 平台、ABI、Ruby/RubyGems/Bundler runtime 变化 | miss | miss |
| build args 变化 | miss | miss |
| project/install root 变化 | payload 不含绝对根；重新核对 provenance；不匹配 miss | snapshot scope 不匹配 miss |
| Bundler cache 文件路径/内容变化 | 回退查询或 miss | 不影响 no-op；如参与锁 checksum 则回退 |
| 单个 gem/扩展文件缺失 | P3 可继续普通安装 | 结构 miss |
| gemspec/扩展内容被改 | P3 不负责已安装完整性 | P4a 仍可能 hit；P4b digest miss |
| 非本地平台行未安装 | 不影响本地 plan | 不应 false miss |
| flag 进入未知输出/副作用域 | 普通命令流处理；不能由 plan 替代 | no-op 门禁 miss |
| payload 损坏/超限/类型错误 | miss | miss |
| 缓存不可写 | 不影响本次命令 | 不影响本次命令 |

## 8. 实施切片与依赖

1. **P2 前置**：payload schema、canonical serializer、原子 writer、限额与脱敏测试。P3/P4 均依赖。
2. **P3.1 纯 helper**：从 `LockFastPath::Hit` 提取 `primary_remote`；将 `materialize_locked` 的计划构造提为不创建 bridge 的纯函数。
3. **P3.2 重建入口**：`Resolution.from_plan`、Bundler cache 延迟核对、install 命令单次可信上下文接线。
4. **P3.3 验证**：双 profile 差分、RPC 分解、冷/热 EvalCache 对照、回退矩阵。
5. **P4.1 偏差修复**：共享汇总函数、2.7 `+1` 回归、本地平台集合修正。此切片不依赖 snapshot。
6. **P4.2 可选 snapshot**：项目作用域存储、锁内采集/复验、有界 manifest、篡改与竞态测试、I/O 基准。

依赖顺序：P2 → P3.1 → P3.2 → P3.3；P4.1 可与 P3 并行；P4.2 依赖 P2、P4.1 与锁内复验改造。

## 9. 风险、未决项与不宣称事项

- HEAD 没有 P2 writer；在它落地前，P3/P4 只能设计，不能宣称可用。
- “省 2 RPC”依赖默认 Bundler 缓存布局与冷 EvalCache；必须按场景实测，不能沿用 task-254 数字。
- P4 snapshot 的全树 hash 成本未知；若不优于现有结构检查，保留 P4a，不把完整性层设为强制。
- 现有 `InstallFastPath` 的 2.7 计数偏差是当前代码事实；未修复前 P4 的“输出一致”验收不得通过。
- 缓存不抵抗同机恶意写入者；snapshot 的 TOCTOU 只能通过 ProcessLock 缩小竞态，不能承诺对抗不遵守该锁的外部进程。
- 未运行构建、spec、格式化或差分；本文所有新增行为均是待实施、待验证设计。

## 10. 记忆检索依据

本轮记忆检索使用 `celerite M8 plan cache P3 P4`、`celerite task-264 plan cache P3 P4 design` 等词。`rsrs` 未返回可直接采用的 task-264 条目；memlite 命中 `d10c9672`、`9dd1267b`、`9bed9125`，分别对应 task-254 设计、task-242 快路径裁断与 task-259 凭据命名空间收口。上述记忆只作历史旁证，当前结论均以 HEAD 文件锚点为准。
