# Celerite 架构方案

日期：2026-11-06；性能与原生边界更新：2026-11-10
状态：实施中的架构基线。原生解析、安装和 Ruby 桥已有实现；本文中的目标态不等于当前完成度。
当前实测与未覆盖边界以 [compat-report.md](compat-report.md) 为准，执行顺序以
[roadmap.md](roadmap.md) 为准。

## 1. 目标与判断

Celerite 用 Crystal 实现 Ruby Bundler 的高性能兼容替代。目标是**可观察行为兼容**，而不只是读取 Gemfile 和下载 gem。

兼容对象包括 Gemfile DSL、Gemfile.lock、CLI/配置、依赖解析、source、安装与原生扩展、`bundle exec`/运行时、插件，以及相应的输出与退出码。兼容完成以指定 Bundler 版本的差分测试和上游测试通过为准。

Bundler 4.0.24 是当前官方命令参考的生成基线；同时覆盖仍受支持的 2.7.2。每个发布版本固定已验证的参考版本矩阵，不声称尚未验证的历史版本兼容。

### 核心约束

1. Gemfile 是可执行的 Ruby，不能靠静态解析器实现完整语义。
2. Bundler 插件是 Ruby 代码，可以注册命令、source 和安装生命周期钩子。
3. gemspec、Git/path source 和原生扩展也涉及 Ruby 语义或 Ruby 工具链。
4. 正确性优先于“纯 Crystal”标签。Ruby 兼容桥是正式架构组件，不是临时补丁；目标是减少不必要的桥调用，而不是为消除 Ruby 牺牲语义。
5. 不允许缺功能时静默执行整个 `bundle install` 来伪装原生实现。
6. 优化对象是可批处理、可缓存、算法密集或 I/O 密集的路径；不以重写全部 RubyGems（`gem build/push/yank/sign` 等）为默认目标。
7. 先修正语义和证据，再优化。命令入口、配置键或可解析文件的存在，不代表机制已生效。

## 2. 总体架构

```text
                       ┌──────────────────────────────┐
 celerite / opt-in     │ CLI、环境发现、配置求值      │
 bundle shim          │ 错误码与终端输出             │
                       └──────────────┬───────────────┘
                                      │
                       ┌──────────────▼───────────────┐
                       │ Operation planner            │
                       │ install/update/lock/exec/... │
                       └───────┬───────────────┬──────┘
                               │               │
                  ┌────────────▼─────┐  ┌──────▼──────────────────┐
                  │ Native core      │  │ Ruby compatibility      │
                  │                  │  │ bridge                  │
                  │ Gem/Requirement  │  │                         │
                  │ Lockfile codec   │  │ Gemfile/gemspec eval    │
                  │ Compact Index    │  │ Bundler Ruby API        │
                  │ PubGrub resolver │  │ plugins/custom sources  │
                  │ Download/verify  │  │ native extension tools  │
                  │ install planner  │  └─────────────────────────┘
                  └────────┬─────────┘
                           │
               ┌───────────▼────────────────────┐
               │ Content-addressed artifact    │
               │ cache + atomic project store  │
               └────────────────────────────────┘
```

### 2.1 Crystal 原生核心

- **CLI**：保持命令、参数别名、环境变量、配置文件优先级、stdout/stderr 和退出码兼容。`celerite` 为默认入口；后续提供显式安装的 `bundle` 兼容 shim，不自动覆盖现有 Bundler。
- **模型**：实现 `Gem::Version`、`Gem::Requirement`、平台和 source 标识的语义等价版本。不能把版本号当整数或字符串排序。
- **锁文件**：保留 source、依赖、平台、checksum、Ruby/Bundler 版本及格式规则。未知 section 与 field 要有明确的保真或失败策略，不能悄悄丢弃。
- **索引**：实现 RubyGems Compact Index、ETag、Range 增量更新和 `Repr-Digest` 校验；兼容历史缓存格式但不复用其私有实现细节。
- **解析器**：实现 PubGrub，并把已锁版本作为强偏好而非随意升级。候选分组、解锁范围、失败后的有界放宽重试、冲突解释、预发布、Ruby/RubyGems 约束和平台选择都要与参考实现比较。
- **source**：优先支持 rubygems.org，再实现 path、Git、gemspec 和插件 source。source 身份必须进入缓存键。
- **安装器**：并行下载、校验、解包、创建 specification 和 executable；原生扩展通过 Ruby/RubyGems 工具链执行，并复现 build 参数和失败清理行为。
- **运行时**：生成与 Bundler 兼容的 load path、binstub 和 exec 环境。Ruby 应用仍运行在其原 Ruby 上；`Bundler.setup`/`require` 和 `bundler/inline` 由 Ruby 适配层实现。`exec` 的 Ruby shebang `Kernel.load` 优化及 `disable_exec_load` 行为单独做差分测试。

### 2.2 Ruby 兼容边界与迁移顺序

桥是短生命周期或按需存活的子进程，使用带版本的 JSON Lines 协议。每条消息包含协议版本、request ID、操作和 payload；响应使用稳定的结构化错误，不解析 Ruby 异常文本来推断状态。

迁移按以下优先级推进，不把“已经能用 Ruby 完成”计作“Crystal 已实现”：

1. **优先原生**：版本/约束、PubGrub、Compact Index、lockfile、`.gem` 流式校验与解包、安装计划和缓存。
2. **逐步原生**：source 的 mirror/proxy/redirect/retry/鉴权、Git orchestration、已安装 gem 索引、activation/load-path 规划、plugin index 和命令发现。
3. **保留 Ruby 边界**：任意 Gemfile DSL、动态 gemspec、Ruby 插件代码、`Gem::Ext::Builder`、公开 Ruby 对象的动态行为、Marshal 和签名/证书兼容入口。
4. **可选嵌入**：边界稳定后，才评估以 Ruby C API/FFI 暴露 Crystal 原生扩展，保留 `gem`/`Bundler` API 而减少进程启动。这不是第一阶段前提，也不引入逐对象跨语言调用。

当前桥协议与目标协议需要区分：文档中的协议名称是设计契约，未在代码中注册的操作不算已实现。

协议操作：

- `evaluate_gemfile`：返回正规化 dependencies、groups、source、Ruby 约束、插件声明及求值指纹。
- `evaluate_gemspec`：读取本地或 Git source 的 gemspec；不把不可信 gemspec 当作静态 YAML。
- `ruby_environment`：返回 Ruby、RubyGems、平台、默认 gem、bundled gem 和扩展构建环境。
- `load_plugin` / `invoke_plugin`：加载插件、枚举命令/hook/source，并执行无法迁移的扩展。
- `build_extension` / `runtime_setup`：执行需要 Ruby 的安装和运行时步骤。
- `compat_command`：显式兼容引擎入口，用于尚未原生支持且必须保持行为的操作。

兼容桥的“受控”指协议、环境、路径、生命周期和错误传播受控，**不是 Ruby 代码沙箱**。Bundler 本身会执行项目 Gemfile、gemspec 和扩展代码；Celerite 不虚构隔离保证，也不放宽现有权限。

桥接口必须是**批次级**：一次导出完整 Gemfile 依赖模型，一次提交完整候选集并返回解，一次生成完整安装计划。禁止在求解循环里逐版本、逐对象询问 Ruby，避免进程、序列化和 Ruby 对象分配成本抵消原生收益。

### 2.3 执行路径

1. **锁定安装**：校验 Gemfile、lockfile、配置与 Ruby 环境指纹；未变化时无需重新求值 Gemfile，直接验证锁文件仍满足声明并安装。
2. **需要解析**：执行 Gemfile/gemspec 的 Ruby 兼容求值；索引、求解、下载、校验及安装规划走 Crystal。
3. **插件/扩展操作**：在 bridge 中注册并执行 Ruby 扩展，按事件顺序与原生 orchestration 交互。
4. **显式兼容引擎**：由用户配置或尚未支持的操作选择，明确显示引擎；失败时报告不支持，不暗改依赖或配置。

动态 Gemfile 的原生解析只能作为后续可选优化：必须证明 Ruby 求值结果相同；否则走 bridge。不能通过忽略未知 Ruby 代码实现“快速成功”。

## 3. 性能设计

### 3.1 优化优先级与目标态

按 profile 收益实施，而非按“还剩多少 Ruby 代码”排序：

1. **无变化快路径**：Gemfile、gemspec、配置、lockfile 与 Ruby 环境指纹不变时，直接读取锁定安装计划，不加载 Bundler、不启动 bridge。
2. **减少 Ruby 初始化**：Gemfile 只在需要动态求值时执行；同一求值过程复用 bridge，设置空闲回收、协议超时和批量请求上限。
3. **不可变安装计划**：下载时流式 SHA-256，Crystal 解出 `metadata.gz` 并解析静态 gemspec 子集；一次生成包含依赖、executables、extensions 和 installed-spec 输入的计划，禁止各阶段重复读取同一个 `.gem`。动态 gemspec、非标准 Marshal 或安全敏感边界显式回退 Ruby。
4. **并发 I/O**：Fiber worker pool 调度下载、校验和安装准备，按 source/host 限流并逐包 single-flight。原生扩展构建保持独立、有序、可观察的阶段。
5. **轻量 Ruby runtime**：Crystal 从 lockfile 和安装计划生成版本化 runtime manifest；Ruby 适配层只负责激活 gem、设置 load path 和 `Kernel.require`，逐步摆脱对完整 `bundler/setup` 启动的依赖。`Bundler.setup`/`require` 和 `bundler/inline` 的行为必须先由差分与真实应用证明。
6. **最后才是求解器 CPU**：当前 profile 未证明 PubGrub 是主要瓶颈，保持单线程确定性求解。Crystal Fiber 不等于多核 CPU 并行，不能为并行而共享可变 Hash/Array。

目标数据流：

```text
Ruby（仅需要时）                Crystal
执行 Gemfile/gemspec ──批次──▶ 索引 → 求解 → 平台选择
                                │
                                ▼
                    不可变安装计划 + lockfile + runtime manifest
                                │
                     下载 → 校验 → 解包 → 原子发布
                                │
              Ruby 仅处理插件、动态边界和原生扩展构建
```

### 3.2 已选优化

- **避免重复工作**：内容寻址的 `.gem` 与解压产物缓存；依据 checksum、平台、Ruby ABI 和 build 配置区分安装结果。
- **减少启动开销**：锁文件命中时不加载 Bundler；无需 Ruby 求值的命令不启动 bridge。按需复用 bridge，但必须有空闲回收与协议超时。
- **并发 I/O**：Crystal Fiber 配合 Channel/WaitGroup 构造有界 worker pool，调度下载、校验和可并行的安装准备；按 source/host 限流、逐包 single-flight。每个 worker 独占 HTTP::Client 或使用真正的连接池，不并发共享单个客户端。
- **并发 CPU 工作**：首版保持单线程确定性 PubGrub，不并行回溯；只有 profile 证明值得时才启用多线程处理独立校验/解包。共享状态使用 Channel 或明确的同步原语，不并发写普通 Hash/Array。Crystal 默认 Fiber 并发不等于 CPU 并行。
- **索引增量更新**：ETag、Range、`Repr-Digest`，避免每次下载完整 `/versions`；按需读取 `/info/<gem>`。兼容 Bundler 从 `cached_size - 1` 请求、206 时去除首字节再追加的策略；完整文件 digest 校验失败或缺失时全量回退。
- **安全文件操作**：同文件系统临时文件 + fsync（按所需 durability）+ 原子 rename；不可变产物可硬链接，无法硬链接时复制。绝不把未校验文件放入最终缓存。
- **内存控制**：流式读取大文件，避免将 `/versions` 和所有包同时载入内存；热路径减少重复 String 分配，以 profile 决定优化。
- **真实配置路径**：mirror、proxy、redirect、retry、SSL、`with/without`、`path.system` 和 `build.<gem>` 必须先有生效路径与负向测试，不能只为通过快路径而绕过。

### 不做的事

- 不牺牲锁文件一致性换取“更快解析”。
- 不默认跳过 checksum、TLS 或权限校验。
- 不在多个进程共享可写安装目录而无锁。
- 不预先承诺固定加速倍数；性能目标必须由可复现基准证明。

## 4. 一致性、安全与故障行为

- 同一 source/名称/版本/平台/校验和的下载由 single-flight 合并；不同凭据隔离的 source 不共享认证上下文。
- 凭据只在进程内和系统既有凭据位置使用；日志、trace、bridge 协议与 benchmark 中脱敏，不新增持久化明文凭据。
- 缓存元数据用原子更新和版本化 schema；锁粒度覆盖“下载—校验—发布”，崩溃留下临时文件而非半成品。
- 安装前形成完整计划；失败按 Bundler 的可见行为清理，禁止部分写入 lockfile。
- frozen/deployment 模式下，任何需要修改锁文件的输入都先失败。
- 对损坏索引、短读、重定向、HTTP 206/200、digest 不符、并发删除、无权限、磁盘满和扩展编译失败均有负向测试。
- 不自动执行全局 `bundle` 替换；shim 必须能检测递归并透传目标 Ruby/Bundler 环境。

## 5. 验证策略

### 三层验证

1. **单元/性质测试**：版本、约束、平台、lockfile 和 Compact Index。性质测试覆盖排序等价类、约束组合、parse/serialize 往返及增量缓存。
2. **差分测试**：同一 fixture 下分别运行参考 Bundler 与 Celerite，比较退出码、stdout/stderr、锁文件、安装文件树、Gemfile 变化和 exec 环境。正规化只用于沙箱路径、时间等非确定差异，必须在报告逐项列出；不得排序行为有语义的输出行、删除环境诊断或仅比较文件路径后宣称安装树字节一致。
3. **上游测试**：以 CI pinned revision 获取 `rubygems/rubygems` 的 Bundler specs；先复用 fixture/期望并驱动真实 CLI，再评估直接测试的适配。对不适用项提交具体理由，不用宽泛 exclude 列表凑通过率。上游 harness 本身运行 Ruby，不能把调用上游 Ruby 实现的测试计为 Celerite 通过。失败、pending 和未执行均不是通过，不将 spike 结果写成常态化绿色门禁。

参考测试位置（实施时按 pinned revision 复核）：

- `rubygems/rubygems` 仓库 `bundler/spec/`：CLI、install、lockfile、resolver、plugins 等行为测试。
- `bundler/lib/bundler/`：行为契约实现；包括 `resolver/`、`compact_index_client/`、`source/`、`plugin/`、`cli/`。

测试 fixture 至少覆盖：Rails 规模 bundle、预发布/yanked、多个 source、平台专有 gem、Git/path/gemspec、锁文件迁移、冻结部署、原生扩展、Bundler 插件与私有 source 鉴权。

### 性能基准

基准至少包含 Rails 规模 Gemfile，以及冷缓存 lock/install、热缓存、无变化 install、`bundle exec ruby app.rb`、`ruby -rbundler/setup`、原生扩展、多 source、多平台、Git/path、代理、离线和损坏缓存恢复。不能用只有少量 gem 的 fixture 推断 Rails 规模收益。

记录 wall time、CPU、RSS、Ruby 进程启动次数、bridge 调用次数与序列化字节数、请求数、索引读取量、下载/写盘字节数和 gem 解析次数。对照组包含相同 Ruby 的 YJIT 配置，不只比较未启用 YJIT 的 Bundler。

基线必须与相同 Bundler 版本、Ruby、平台、网络 fixture 和缓存状态比较。首版目标：在本地 fixture 与相同热缓存条件下，无变化 `check` 和 `install` 的 wall-time 不劣于 Bundler，并显示稳定改善；解析与下载目标待首批 profile 后量化。性能改善不是兼容门禁的替代品。

## 6. 当前实施阶段

M0–M6 的历史实施记录及重新打开的验收项见 [roadmap.md](roadmap.md)。后续按依赖顺序推进：

| 阶段 | 交付 | 通过条件 |
|---|---|---|
| M7 | 正确性与证据收敛 | Ruby/平台约束生效；只读命令反映安装状态；上游失败不再被记录为通过 |
| M8 | 批次桥与无 Ruby 快路径 | 无变化 lock/install 不启动 Ruby；批次调用及缓存指纹可观测 |
| M9 | 原生安装计划与轻量 runtime | `.gem` 单次解析、流式 I/O；真实应用不加载完整 Bundler 即可运行 |
| M10 | 可选 Ruby 原生扩展 | 仅在独立进程边界已成为实测瓶颈时进行 spike，兼容与 ABI 成本有评审结论 |

详细任务和验收见 [roadmap.md](roadmap.md)。

## 7. 兼容 profile 与未决问题

- 支持矩阵固定 Bundler 4.0.24、2.7.2 的参考 gem、Ruby/RubyGems 与上游 revision；旧 2.x 只按实测声明。
- 2.7.2 与 4.0.24 均使用 PubGrub，但 4.x 的新锁全平台、默认 checksum 和 cooldown 等行为不能倒灌 2.7.2。
- `Gemfile.lock` 对应 `Gemfile`，`gems.locked` 对应 `gems.rb`；Gemfile 搜索优先级、自定义 lockfile 与 `BUNDLE_GEMFILE` 在 M0 按 profile 固定并测试。
- 锁文件未知 section/field 按 profile 保真；当前在线文档可能含更新版本字段，实施时必须读取对应 tag，不把 4.1 主线字段当作 4.0.24 既有行为。
- 原生 bridge 的进程复用需在实现后用 profile 决定；协议先保持无状态可恢复。
- 若评估 Ruby C API/FFI 原生扩展，必须先验证 Ruby GC 对象保活、异常跨边界、线程/GVL、Ruby ABI、Crystal runtime 初始化和各平台打包；每次调用应处理完整批次，不能只把现有逐对象调用换成本地函数。
- 上游 spec 的接入形式需遵守其许可证，记录 revision，不把第三方测试代码混入本仓 MIT 许可声明。
- Windows、Linux gnu/musl 和 macOS 的 ABI 差异必须进入运行矩阵，不能仅验证平台字符串解析。

## 8. 参考

以下为 2026-11-06 查阅的官方资料；实现时固定到具体上游 revision：

- [Bundler command reference（由 4.0.24 生成）](https://guides.rubygems.org/command-reference/bundle/)
- [Bundler compatibility with Ruby](https://guides.rubygems.org/bundler-compatibility/)
- [How dependency resolution works](https://guides.rubygems.org/dependency-resolution/)
- [How Gemfile.lock works](https://guides.rubygems.org/gemfile-lock/)
- [RubyGems.org Compact Index API](https://guides.rubygems.org/rubygems-org-compact-index-api/)
- [How to write a Bundler plugin](https://guides.rubygems.org/bundler_plugins/)
- [Bundler 2.7.2 resolver 与 PubGrub 重试](https://github.com/rubygems/rubygems/blob/bundler-v2.7.2/bundler/lib/bundler/resolver.rb)
- [Bundler 2.7.2 Compact Index 增量更新](https://github.com/rubygems/rubygems/blob/bundler-v2.7.2/bundler/lib/bundler/compact_index_client/updater.rb)
- [Bundler 2.7.2 上游 specs](https://github.com/rubygems/rubygems/tree/bundler-v2.7.2/bundler/spec)
- [Crystal concurrency](https://crystal-lang.org/reference/latest/guides/concurrency.html)
