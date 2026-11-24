# M8 fast-path plan: L163 批量大小控制 / L164 零 Ruby 无变化快路径

- 任务：task-242（只读可行性调研，未改 `src/`、`spec/`、`fixtures/`、`script/`）。
- 基线：worktree `C:\temp\celerite-t242`，detached `ae658bd`。
- 实机：Windows + `C:\Ruby40-x64`（Ruby 4.0.6，RubyGems 4.0.16，profile Bundler 4.0.24），
  `bin/celerite.exe` 为本次现场 `crystal build src/cli.cr` 的产物（`/bin/` 已在 `.gitignore`）。
- 实测夹具：`.tmp-scratch/proj`（`Gemfile` + `source "file:///C:/temp/celerite-t242/fixtures/gem-index"` +
  `gem "thor", "1.3.2"`），`HOME`/`USERPROFILE`/`BUNDLE_PATH`/`CELERITE_CACHE_DIR` 全部隔离到 `.tmp-scratch`。

## 0. 结论速览

| 行 | 判定 | 推荐解释 / 结论 | 成本 |
| --- | --- | --- | --- |
| L163 | 可勾（改一处协议边界 + 补 spec） | 「批量大小控制」= 单次 `evaluate_batch` 的 **include 段数上限** 与 **响应体字节上限**，超限回结构化错误；不碰 PubGrub 候选集，不改任何现有命令的可观察输出 | 0.5–1 天（S7） |
| L164 | 可勾，但不能复用现成 F4 缓存直接交差 | 零 spawn 需要三块新地基：无 Ruby 的运行时事实来源（`rbconfig.rb` + 上次桥运行记录）、决策记录（锁文件哈希 + 已解析依赖 + 安装计划签名）、lock/install 前置判定与输出复用 | 8–12 天（S8a–S8e） |

两条硬结论（均为本机实测，不是推断）：

1. `CELERITE_BRIDGE_STATS=1` **在没有桥时也会打印统计行**：`bin/celerite.exe version` 输出
   `bridge: procs=0 rpc=0 req_bytes=0 resp_bytes=0`。因此「零 spawn」可以用 `procs=0` 直接断言，
   不需要外部计数器（依据 `src/celerite/bridge/client.cr:19-90` 的 `BridgeStats.finish`，
   `src/cli.cr:49` 在 `ensure` 里无条件 `finish(stderr)`）。
2. 当前 F4 持久缓存命中 **仍会起一个 Ruby 进程**：`CELERITE_EVAL_CACHE=1` 预热后第二次
   `lock` 打印 `eval-cache: hit (persistent)`，统计仍是 `procs=1 rpc=2`
   （原因：`client.cr:931` 传入的 `cache_runtime` 走 `ruby_environment` RPC，
   `client.cr:239-248` 用它校验运行时记录）。所以 L164 不能写成「打开 F4 即可」。

## 1. L163 批量大小控制

### 1.1 现状（审计缺项的准确位置）

- `docs/roadmap.md:163` 要求「…加入 idle 回收、协议超时、结构化错误和批量大小控制；统计一次命令的
  Ruby 进程数、RPC 次数和传输字节数」。前四项与统计均已实现（`C-M8-1-002`、`C-M8-1-005`），
  `docs/roadmap-evidence/M8-closure-audit.md` 判缺 1：批量大小控制无实现、无 spec、`C-M8-1-004` 未声明上限。
- 客户端：`src/celerite/bridge/client.cr:928-953`。`evaluate_batch` 只按 `include` 数组追加段，
  可缓存段的判定在 `:929`，请求负载只有 `gemfile` + `include`（`:940-943`）。
- 服务端：`assets/bridge/server.rb:567-579`。`sections = payload["include"]`，非数组则空；
  一次 `bridge_evaluate_gemfile` 后按 `sections.include?` 追加 `gemspecs`/`fingerprint`；
  注释明说未知段忽略、不拒绝，**没有任何条数或字节上限**。
- 唯一入口：`src/celerite/gemfile_evaluation.cr:30` 的 `KNOWN_SECTIONS = ["fingerprint", "gemspecs"]`，
  `:35-47` 的 `fetch` 校验段名后**无条件**请求两段（`GemfileEvaluation.fetch` 目前不给调用方选择段数的机会）。
- 参考 Bundler 侧没有「批量求值」这个概念：`C:\Ruby40-x64\lib\ruby\4.0.0\bundler\` 全树 grep `batch`
  零命中；参考实现是一次进程内 DSL 求值（`Bundler::Dsl#eval_gemfile`），不存在要限制的 RPC 批。
  因此这个短语只能解释为**我方 bridge 协议自身**的规模控制。

### 1.2 候选解释

| # | 解释 | 参考 Bundler 对应物 | 我方现状 | 实现后可观察输出会变吗 |
| --- | --- | --- | --- | --- |
| A | 限制单次 `evaluate_batch` 的 include 段数（≤ N，未知段结构化报错） | 无（参考无 batch 概念；`bundler/installer.rb:197,204` 的 `jobs` 是安装并发，不是请求批） | 无上限、未知段静默忽略（`server.rb:567-579`） | 否。现有命令恒请求 2 段（`gemfile_evaluation.cr:47`），上限取 4 时任何现有路径都不触发 |
| B | 限制单次响应体字节数，超限退化或分片 | 无直接对应物；`bundler/worker.rb:22-28,97-98` 的 worker 池是有界并发，不是响应分片 | 无上限；实测 `lock` 单命令响应总量 1499 B、`install` 首装 289382 B（含索引，非单次 batch） | 会。超过上限时从「正常返回」变成「结构化错误」或「分两次请求」；分片需要改协议与客户端，退化则改变结果形状 |
| C | 限制送入 PubGrub 的候选集大小 | `bundler/resolver.rb` 有候选裁剪但无「批大小」概念；`Gem::Resolver` 也无 | 解析器无此旋钮 | 会。候选集大小直接决定能否解析出解，任何裁剪都可能改锁文件 |
| D | 限制安装并发（`--jobs` 语义） | 有：`bundler/settings.rb:308-309` `installation_parallelization` = `self[:jobs] \|\| processor_count`，`bundler/installer.rb:197,204` 传给 `ParallelInstaller`，`bundler/worker.rb:22-28` 建线程池 | 我方安装是顺序的（`commands_install.cr:884-886` 注释明说 sequential） | 不加并发则不变；加了只改时序与日志前缀，不改锁文件/退出码，但会把 worker 前缀 `0:` 变成真并行编号，属可观察输出变化，需对照参考逐行确认 |

### 1.3 推荐：A + 有界 B（上限远高于实际用量，触发即结构化错误）

组合方案，理由是二者分别对应「请求形状」和「响应规模」，且都能做到对现有路径零可观察变化：

1. **段数上限**：`MAX_INCLUDE_SECTIONS = 4`（当前恒 2）。客户端 `evaluate_batch` 在**发请求前**拒绝超限
   与未知段（`client.cr:928` 入口），返回结构化错误；服务端 `op_evaluate_batch` 同样拒绝，
   避免旧客户端把上限当摆设（`server.rb:567`）。
2. **响应字节上限**：`MAX_RESPONSE_BYTES = 1 MiB`（实测单次 batch 响应远低于此；`install` 的 289 KB
   里绝大部分是 compact index 数据，不走 `evaluate_batch`）。服务端序列化后测长，超限回
   `BatchTooLarge`，**不返回半截响应**；上限可用 `CELERITE_BATCH_MAX_BYTES` 覆盖，供 spec 用极小值触发。
3. **统计**：`BridgeStats.response(bytes)` 已记录字节（`client.cr:19-90`），补一条诊断行
   （`CELERITE_EVAL_DEBUG=1` 时打印 `batch: sections=N bytes=M`），不进默认输出。

为什么不推荐 C/D：C 改变解析语义、必然改锁文件；D 是安装并发而非「批量」，且参考的 `jobs`
默认 `processor_count` 会让输出编号变化，属另一条 roadmap 语义，不该借 L163 夹带。

### 1.4 最小实现点

| 文件 | 位置 | 改动 |
| --- | --- | --- |
| `src/celerite/bridge/client.cr` | `:928` 入口 | 段数/未知段校验，超限 raise `Bridge::BatchTooLarge`（沿用现有 `BridgeError` 家族，带 `limit`/`actual` 字段） |
| `assets/bridge/server.rb` | `:567-579` | 同样的段数校验 + 序列化后字节校验；错误走 `bridge_error(id, "BatchTooLarge", msg)` |
| `src/celerite/bridge/client.cr` | `:124` 附近或 `client.cr` 错误模块 | 新错误类型与文案；不得复用 `ProtocolError`（语义不同，会造成误判为桥崩溃） |
| `src/celerite/gemfile_evaluation.cr` | `:35-47` | 无需改：`fetch` 恒请求 2 段，天然在限内；只在注释里注明上限来自协议层 |

### 1.5 判据（spec 草案）

1. `Bridge::Client#evaluate_batch(path, ["fingerprint", "gemspecs", "gemspecs", "fingerprint", "x"])`
   在**未起桥**时即 raise `BatchTooLarge`，且 `BridgeStats` 的 `procs` 保持 0（用 `CELERITE_BRIDGE_STATS=1`
   捕获 stderr，或直接读 `BridgeStats` 计数）。
2. 合法 2 段请求的响应与基线逐字节相同（对 `fixtures` 中带 gemspec 的 Gemfile 做一次快照比较：
   同一 Gemfile 下 `evaluation`/`gemspecs`/`fingerprint` 三段 JSON 不变）。
3. 服务端超限：设 `CELERITE_BATCH_MAX_BYTES=64` 起桥，请求 2 段 → 收到 `BatchTooLarge`，
   错误体含 `limit` 与 `actual`，且响应里没有 `evaluation` 字段（证明不会半截返回）。
4. 未知段：`include: ["evaluation"]` → `BatchTooLarge`（或专门的 `UnknownSection`），
   而不是像今天那样静默返回少一段（`server.rb:567-579` 的现状）。
5. 现有 CLI 不回归：`lock`/`install --local`/`check` 在夹具上的 stdout/stderr 与改动前逐字节相同。

### 1.6 反假绿

- 变异测试：把 `MAX_INCLUDE_SECTIONS` 改成 `Int32::MAX` 后第 1 条 spec 必须失败；把服务端字节检查
  改成 `> 0` 后第 3/4 条必须失败。即 spec 断言的是「上限存在且按上限报错」，不是「代码里出现过某个常量」。
- 第 2 条用快照而非「不抛异常」，否则删掉整个 `evaluate_batch` 段追加逻辑也能过。
- 禁止用 `rescue` 吞掉上限错误来「过 spec」：spec 必须断言错误类名与字段。

## 2. L164 零 Ruby 快路径

### 2.1 不启动 Ruby 时的运行时事实来源

先给结论：**没有任何一个纯本地来源能独立、无条件地重建全部运行时事实**；可行方案是
「上次桥运行写下的运行时记录 + 本次用 `rbconfig.rb`/磁盘常量重建的校验值」，两者不一致即走兼容路径。
纯本地可重建的字段如下（本机实测值）：

| 字段 | 无 Ruby 来源 | 本机实测 | 可靠度 |
| --- | --- | --- | --- |
| `ruby_version` | `rbconfig.rb` 的 `CONFIG["ruby_version"]`，或 `<ruby_root>/lib/ruby/<ver>/` 目录名 | `4.0.0`（`rbconfig.rb:58`） | 高（纯字面量） |
| `platform` | `CONFIG["arch"]`，与 `Gem::Platform.local` 同一推导 | `x64-mingw-ucrt`（`rbconfig.rb:60`） | 高（`:13-18` 仅对 `mswin(?:32\|64)` 追加 `_60`） |
| ABI | **不是** `Gem.extension_api_version`；我方 ABI = `ruby_abi_for(ruby_version)` = `<major>.<minor>.0` | `4.0.0`（`resolution.cr:164-173`） | 高（派生自版本串） |
| `patchlevel` | `CONFIG["PATCHLEVEL"]` | `0`（`rbconfig.rb:25`） | 中（dev 构建的 `PATCHLEVEL` 可能与 `RUBY_PATCHLEVEL` 不一致） |
| `engine` / `engine_version` | **无本地来源**（编译期常量，rbconfig 不含） | `ruby` / `4.0.6` | 低：只能来自上次桥运行记录，或假定 CRuby |
| `rubygems_version` | `lib/ruby/<ver>/rubygems.rb:12` 的 `VERSION = "4.0.16"` 字面量 | `4.0.16` | 中（可直接解析，但后续 gem 升级可能只改 `specifications`） |
| `bundler_version` | 二进制常量 `Celerite::Profile::DEFAULT_BUNDLER_VERSION`（或 `CELERITE_PROFILE_BUNDLER_VERSION`） | `4.0.24`（`profile.cr:16,24`） | 高（不需要磁盘） |
| `default_gem_dir` | `ENV["GEM_HOME"]`，否则 `CONFIG["rubylibprefix"]/gems/<ruby_version>`（`rubygems/defaults.rb:37-38`） | `C:/Ruby40-x64/lib/ruby/gems/4.0.0` | 高（`rubylibprefix` 可由 `$(...)` 展开得到） |

`rbconfig.rb` 不是纯数据文件，解析必须处理三件事（本机样例，`C:\Ruby40-x64\lib\ruby\4.0.0\x64-mingw-ucrt\rbconfig.rb`）：

1. **路径纠正**：任务书假设的 `C:\Ruby40-x64\lib\ruby\4.0.0\rbconfig.rb` 不存在；真实路径多一层 arch 目录
   （`<root>/lib/ruby/<ruby_version>/<arch>/rbconfig.rb`，15181 B）。
2. **表达式与变量引用**：首行 `# encoding: ascii-8bit`，`TOPDIR = File.dirname(__FILE__).chomp!("/lib/ruby/4.0.0/x64-mingw-ucrt")`
   （`:12-16`）；`CONFIG["prefix"] = (TOPDIR || DESTDIR + "/.")`（`:28`）；`host_os = "$(target_os)"`（`:211`）；
   `rubylibprefix = "$(libdir)/$(RUBY_BASE_NAME)"`（`:132`）。纯正则抓字面量会拿到 `$(...)` 原文，
   必须按 `CONFIG` 自引用递归展开（`$(MAJOR)`→`:22`），并对 `TOPDIR` 用文件位置代入。
3. **注释与守卫**：文件里含 `RUBY_VERSION.start_with?("4.0.") or raise`（`:13`）以及大量注释行（`:275`、`:294`），
   解析器要忽略注释、只认 `CONFIG["..."] = "..."` 形状。

解析代价：读 15 KB + 一次线性扫描 + 少量递归展开，量级低于 1 ms（**未精确计时**，仅按文件规模估算）。
比一次 `ruby -e` 便宜三个数量级：后者要 1 个进程（≈100 ms 级）且直接违反「零 Ruby」判据。

推荐落地：

- 新增 `Celerite::RuntimeFacts`（无桥模块）：入参 `ruby_exe`（`ENV["CELERITE_RUBY"]` 或 PATH 上的 `ruby`），
  推出 `<root>`，读 `rbconfig.rb`，返回上表可导出的字段 + 来源标注（`rbconfig` / `record`）。
- 每个字段附 `Source` 枚举；`RuntimeFacts` 无法覆盖的 `engine`/`engine_version` 只能取自
  **上次桥运行写下的运行时记录**（`server.rb:198-234` 的 `op_ruby_environment` 输出：
  `ruby_version`/`platform`/`engine`/`engine_version`/`patchlevel`/`rubygems_version`/`ruby_exe`/
  `default_gem_dir`），并用 `rbconfig` 交叉校验。交叉校验失败、记录缺失、`ruby.exe` 的 size/mtime 变了
  → 兼容路径。
- 注意：`EvalFingerprint::Runtime`（`eval_fingerprint.cr:97-103`）需要 7 个字段，其中 `engine`
  和 `engine_version` 是本地推不出的；这正是「必须持久化上次运行时记录」的根本原因。

### 2.2 短路点

`Resolution.new` 必须在短路判定之后。现状：
`src/celerite/cli/commands.cr:3050` `Definition.build` → `:3075` `Resolution.new(definition, unlock)`
（其 `initialize` 走 `eval_gemfile` → `resolution.cr:381-383` → 起桥）→ `:3106-3111` 才判断无操作。

- **lock**：在 `commands.cr:3074`（`checksum_refresh` 之后、`Resolution.new` 之前）插入前置判定。
  命中时**不能**直接 `return 0` 了事：`:3112-3130` 还负责 `resolution.close`、`to_lock` 渲染、
  BUNDLED WITH 重写（`:3118`）、2.x 删 bundler 自校验行（`:3122-3124`）、`--print` 分支（`:3125-3126`）、
  `Writing lockfile to …` + `lockfile_write_result`（`:3128-3129`）。最小改造是**把这段抽成
  `write_locked_lockfile(definition, resolution, text, print_mode, lockfile_write_path)`**，
  由现分支与快路径共用；快路径提供缓存里的渲染文本与 `bridge_bundler_version`（= `Profile.bundler_version`）。
- **install**：在 `commands_install.cr:264`（插件检查结束）与 `:266`（`Bridge::Client.shared`）之间插入。
  此时 `definition`（`:219`）、`config`、`install_path`、frozen 检查（`:234-248`）、removed-flag/未知开关
  （`:191-212`）都已执行，未起桥。命中时需复刻 `:935`、`:951-959` 的输出（`Bundle complete! …`、
  `Bundled gems are installed into …` / `Use bundle info …` 分支），以及 `:300` 的 `ProcessLock`
  （空操作也要互斥？参考实现是拿锁的，建议保留：`ProcessLock.lock` 不依赖 Ruby）。
  未命中则原样落入 `:266` 起的兼容路径。
- **不可行的替代**：只在 `:3106` 前插判定不行 —— 那时 `Resolution.new` 已经 spawn；把 `Resolution`
  改成惰性求值面更大、且 `resolution.evaluation` 在 `:3108` 就被读，收益不成立。

### 2.3 必须走兼容路径的清单

| 条件 | 依据 | 后果 |
| --- | --- | --- |
| 指纹 state ≠ `deterministic`（动态 token、`eval_gemfile` 非字面量、`install_if` 非 `true/false`、`ruby file:`、`source type:`） | `server.rb:389-403,458-475`；`client.cr:312-313` | 求值不可从文件集合重放，必须真跑 DSL |
| 插件已装（plugin index 非空）或 `PluginHooks.enabled?` | `server.rb:445-454`；`commands_install.cr:260`；`plugin_gemfile.cr:17` | 插件可在任意阶段打印/改动安装，输出不可预测 |
| 无持久化状态 / 命中状态被裁剪 / format 不符 | `eval_cache_store.cr:33-40,104-120` | 没有可信证据，必须重算 |
| 环境签名不一致（`BUNDLE_*` 等） | `client.cr:198-206,302` | 同文件不同环境结果可不同 |
| 任一 gemfile/evalchain/gemspec 的 sha256 变化或缺失 | `eval_fingerprint.cr:165`、`server.rb:344-361` | 输入变了，锁文件结论失效 |
| 运行时记录不一致（7 字段任一，含 ABI/`default_gem_dir`） | `eval_fingerprint.cr:97-103`、`server.rb:198-234` | 装错 ABI 目录是硬故障 |
| `ruby.exe` 路径解析失败 / PATH 上是 shim（rbenv、asdf）、非 CRuby、rbconfig 缺失 | 本机实测：真实路径含 arch 子目录 | 无本地事实来源 |
| 锁文件不存在、不可读、或字节哈希与记录不符 | `commands.cr:3068`、`definition.cr:171` | 锁文件被手工改过，必须重新校验依赖 |
| `checksums_need_refresh?` 非 nil | `commands.cr:3073`；实测：CHECKSUMS 空条目会让 `lock` 每次都真的解析 | 需要远程索引才能补 CHECKSUMS |
| lockfile 的 DEPENDENCIES 与已解析依赖不符，或 PLATFORMS 不覆盖本机 | `commands.cr:3111`、`definition.cr:182`、`commands.cr:2962` | 无操作条件不成立 |
| 存在 path / git source（`path_specs_changed?` 需要求值 path 内 gemspec） | `resolution.cr:1442` | 需要读目录/gemspec，等于要 Ruby |
| 安装计划不完整：任一 locked spec 的 `<install_root>/specifications/<full_name>.gemspec` 缺失；native spec 的 `extensions/<platform>/<abi>/<full_name>` 缺失 | `commands_install.cr:461,508,677`；`installer.cr:51,254` | 「该装没装」 |
| `BUNDLE_PATH`/`path`/`path.system`/`without`/`with` 与记录不一致，或安装根不可推导 | `resolution.cr:51,132-135`；`commands_install.cr:299` | 会装到另一个根 |
| `BUNDLE_FROZEN`/deployment、`--local`、`--standalone`、`--no-lock`、`--force`/`--redownload`、`--clean`、`--target-rbconfig`、`--add-platform`/`--remove-platform`/`--normalize-platforms`/`--add-checksums`/`-u` | `commands.cr:3046-3073`、`commands_install.cr:173-248,496` | 语义分支必须真跑 |
| `--verbose`/`BUNDLE_VERBOSE`（`Using bundler …`、`0: spec …` 需要桥侧事实） | `commands_install.cr:887-905`、`commands.cr:3144` 起 | 调试输出需要真实加载 |
| 缓存目录不可写、`CELERITE_FAST_PATH=0` | `eval_cache_store.cr:58-66` | 显式关闭/无持久化 |

### 2.4 前置判定伪代码

```text
# 共同部分：无桥事实 + 状态装载
facts   = RuntimeFacts.detect(ruby_exe)                 # rbconfig 解析；失败→compat
state   = FastPathStore.load(project_root, gemfile_abs) # 见 §3 S8b；缺失/损坏→compat
return compat unless state.format == "celerite-fastpath/1"
return compat unless state.env_signature == env_signature(ENV)
return compat unless state.fingerprint_state == "deterministic"
return compat unless state.plugin_index_empty
# 1) 输入仍逐字节一致
return compat unless sha256(gemfile) == state.gemfile_sha256
state.files.each { |f| return compat unless sha256(f.path) == f.sha256 }
# 2) 运行时仍一致（7 字段 + ABI + default_gem_dir）
return compat unless state.runtime.matches?(facts, profile_bundler_version)
return compat unless state.abi == ruby_abi_for(facts.ruby_version)
return compat unless FileInfo(state.ruby_exe).size_mtime == state.ruby_exe_stat
# 3) 锁文件仍是同一份
return compat unless sha256(lockfile) == state.lockfile_sha256
return compat unless state.deps == definition.lockfile_dependencies   # 由缓存 evaluation 反序列化
return compat unless lockfile_platforms_cover_local?(lockfile.platforms)
return compat unless definition.checksums_need_refresh?(local?).nil?
# 4) 安装计划仍完整（install 才需要）
install_root = InstallPaths.gem_root(config, facts.default_gem_dir, state.abi)
state.installed_specs.each { |s|
  return compat unless File.file?(File.join(install_root, "specifications", "#{s.full_name}.gemspec"))
  return compat unless s.native? ? Dir.exists?(extension_dir(install_root, s)) : true
}
return compat if state.manifest_digest != manifest_digest(install_root, state.installed_specs)

# 命中
lock:    print/write state.rendered_lock_text   (复用 §2.2 抽出的 helper，exit 0)
install: ProcessLock.lock(install_path, install_root)   # 与兼容路径一致
         stdout.puts "Bundle complete! N Gemfile dependencies, M gems now installed."
         print_bundle_path_notice(config, facts.default_gem_dir)   # 复刻 :951-959 分支
         exit 0
```

`FastPathStore` 建议独立于 `EvalCacheStore`：后者文档契约明确「只持久化 evaluation，绝不持久化
lockfile / install plan / installed spec」（`eval_cache_store.cr:11-16`），把它扩成决策记录会破坏该契约
与 `persistable?` 的凭据约束。新存储沿用同一根目录与 namespace 规则（`CELERITE_CACHE_DIR` 或
`$HOME/.celerite/cache/`，`<namespace>/fastpath/v1/<sha256(gemfile_abs)>.json`），原子写，
显式 `format`，读失败一律当 miss。

写入时机：**每次桥路径成功完成 `lock`/`install` 且指纹为 deterministic 后**追加写决策记录
（不改动已有 evaluation 条目）；这样冷启动永远走兼容路径，热路径才有资格命中。

### 2.5 判据草案

所有断言都要求 `CELERITE_BRIDGE_STATS=1`（无桥也会输出统计行，§0 已实测）。

1. **无变化 lock 零 spawn**：夹具跑两次 `lock`，第二次 stderr 含 `bridge: procs=0 rpc=0`，
   exit 0，stdout 与第一次逐字节相同（含 `Writing lockfile to …`）。
2. **无变化 install 零 spawn**：同上，`procs=0`，stdout 仍为
   `Bundle complete! 1 Gemfile dependency, 1 gem now installed.` + `Bundled gems are installed into …`。
3. **铁证不生成**：`CELERITE_BRIDGE_SERVER=C:\nope\server.rb`（指向不存在的脚本）下，热路径 `lock`/`install`
   仍 exit 0 且 `procs=0`；同一命令在**改动前二进制**上 exit 1（本机实测：
   `ruby: No such file or directory -- C:/nope/server.rb (LoadError)`、`response id mismatch: expected 1, got -1`、
   `procs=1 rpc=1`）。这条同时是「旧二进制必须 FAIL」的反假绿判据。
4. **冷启动必 spawn**：清空缓存目录后第一次 `lock`/`install`，`procs=1`，且状态文件在命令结束后才出现。
5. **内容变即失效**：`echo >> Gemfile` 后 `lock`，`procs=1`，锁文件与参考解析一致；再下一次回到 `procs=0`。
6. **计划缺项即失效**：删掉 `install_root/specifications/thor-1.3.2.gemspec` 后 `install`，`procs=1`、
   重新安装、exit 0，且 stdout 含 `Installing thor 1.3.2`。
7. **运行时变即失效**：把记录里的 `ruby_version` 改成 `4.0.6`（或 touch `ruby.exe` 改 size/mtime），
   `lock` 必须 `procs=1`。
8. **动态 DSL 永不产生状态**：Gemfile 写入 `puts ENV["HOME"]` / `eval_gemfile ENV["X"]` 之类，
   两次运行均 `procs=1`，fastpath 目录下无该 Gemfile 的记录（`server.rb:389-403` 判 unknown）。
9. **插件即失效**：存在 plugin index（或 `PluginHooks.enabled?` 为真）时 `procs=1`。
10. **锁文件被改即失效**：手工改 `Gemfile.lock` 的一个版本号，`lock` 走兼容路径并重新解析。
11. **无状态时不写半截**：断言 fastpath 文件只在命令成功后出现（失败命令不产出可信状态）。
12. **统计字段**：断言同时覆盖 `req_bytes`/`resp_bytes` 为 0，避免「起了桥但只发心跳」被当作零开销。

### 2.6 风险与负向夹具

| 风险 | 具体场景 | 防住方式 |
| --- | --- | --- |
| 陈旧状态导致「该装没装」 | 用户 `rm -rf vendor/bundle/ruby/4.0.0/gems/thor-*` 但留下 `specifications` 或反之；手工 `gem uninstall` | 计划校验同时检查 `specifications/<full_name>.gemspec`、`gems/<full_name>/`、native 的 `extensions/<platform>/<abi>/<full_name>`，并把三者摘要写进 `manifest_digest`；负向夹具：分别删三者之一，断言回兼容路径并重装 |
| 该解析没解析 | 只改了一个 `gemspec` 文件（path/gemspec 依赖）；`eval_gemfile` 目标文件被改 | 状态记录保存全部 `evalchain`/`gemspec` 的 path+sha256（F1 已有），逐个重算；负向夹具：改 gemspec 一个字节 → `procs=1` |
| 锁文件被外部改写但仍满足依赖 | CI 里 `git checkout` 了另一份锁文件；`bundle update` 由别的工具跑过 | 命中条件含锁文件 sha256；不等即回兼容路径（此时会像今天一样重新解析/校验） |
| 跨机器/跨 ABI 复制 | 把 `vendor/bundle` 从别的机器拷来，同一 Ruby 版本但不同 arch | 计划校验要求 `ruby/<abi>` 与 `extensions/<platform>/<abi>` 同时匹配 `state.platform`/`state.abi`；任一不符→兼容 |
| 运行时被原地升级 | Windows installer 覆盖 `C:\Ruby40-x64`，`ruby.exe` 变了但路径没变 | 记录 `ruby.exe` 的 size+mtime，并交叉校验 `rbconfig.rb` 的 `ruby_version`/`arch`；不符→兼容 |
| 残留可信状态被重放 | 用户回滚代码后 `Gemfile` 字节恰好相同但环境不同（`BUNDLE_FROZEN` 等） | 状态含 `env_signature`（沿用 `client.cr:198-206` 的哈希规则）+ config 摘要 |
| 缓存目录被并发写坏 | 两个 celerite 同时写同一状态 | 沿用原子写（同目录 temp + rename，`eval_cache_store.cr:104-120`）；读失败即 miss，绝不报错 |
| 快路径绕过插件/钩子 | 用户在 `.bundle/config` 里启用插件后热路径仍命中 | 每次判定都读 `PluginHooks.enabled?(config)` 与 plugin index；真值→兼容 |
| 输出漂移 | `Bundled gems are installed into …` 的三种分支（`:951-959`）依赖 `default_gem_dir` 与相对路径 | 判据 2 用逐字节输出断言；`default_gem_dir` 必须来自 `RuntimeFacts`（`GEM_HOME` 优先，与 `server.rb:220` 一致） |

残余风险（写进 roadmap 的「已知限制」）：安装树内容本身不做逐字节校验（Bundler 也不校验已安装 gem），
因此「文件在但内容被人改过」不会被发现；这与参考行为一致，不构成新增差异。

## 3. 切片与顺序

| 切片 | 做什么 | 依赖 | 预估 |
| --- | --- | --- | --- |
| **S7**（L163） | `evaluate_batch` 段数上限 + 响应字节上限 + 结构化错误 + 5 条 spec + `C-M8-1-004` 补上限声明 | 无（`client.cr:928`、`server.rb:567`、`gemfile_evaluation.cr:30` 已在手） | 0.5–1 天，改动 ~80 行 |
| **S8a** | `RuntimeFacts`：PATH/`CELERITE_RUBY` 解析 ruby，读 `rbconfig.rb`，`$(...)` 展开 + `TOPDIR` 代入，输出 7 字段中可导出的 5 项 + ABI + `default_gem_dir`，来源标注 | 无 | 1.5–2 天 |
| **S8b** | `FastPathStore`：format、namespace、原子写、索引 = `sha256(gemfile_abs)`、环境签名、锁文件哈希、渲染文本、依赖快照、安装计划摘要；与 `EvalCacheStore` 分离 | S8a（记录里要存运行时） | 2–3 天 |
| **S8c** | lock 短路：抽出 `:3112-3130` 的写/打 helper，`commands.cr:3074` 前插入判定，命中 exit 0；spec 1/3/4/5/7/8/9/10 | S8a、S8b | 1–2 天 |
| **S8d** | install 短路：`commands_install.cr:264/266` 之间插入，复刻 `:935`/`:951-959` 输出与 `ProcessLock`；spec 2/6 | S8a、S8b、S8c 的判定模块 | 2–3 天 |
| **S8e** | 兼容矩阵与负向夹具：§2.3 全表逐条断言、`CELERITE_FAST_PATH=0`、CI 开启 `CELERITE_BRIDGE_STATS=1` 的零 spawn 门禁 | S8c、S8d | 1–2 天 |

顺序：S7 可与 S8a/S8b 并行（文件不重叠）；S8c 必须先于 S8d（共用判定模块，install 的输出复刻更复杂）。
L164 勾选条件：S8c+S8d+S8e 全绿，且 §2.5 第 3 条（旧二进制 FAIL）在 CI 中固定执行。

## 4. 本机不可验证项

- 真实 rubygems.org 索引（本机只用 `fixtures/gem-index` 的 `file://` 源）；网络源下 `checksums_need_refresh?`
  与缓存交互未测。
- Rails 级 Gemfile（上百依赖、`eval_gemfile` 链、native 扩展）的规模效应未测。
- Linux/macOS：`rbconfig.rb` 的 `prefix`/`DLEXT`/`arch` 不同，`Gem::Platform.local` 的 `mswin _60` 分支未覆盖。
- rbenv/asdf/scoop shim、`CELERITE_RUBY` 指向 wrapper、JRuby/TruffleRuby：本文按「解析失败即兼容」处理，
  未实机验证。
- 多 ABI / 多 Ruby 并存、`--target-rbconfig`、`BUNDLE_PATH__SYSTEM`、`path.system`：只做了代码级判读。
- `--standalone`、`--clean`、vendor/cache 刷新（`commands_install.cr:932`）在快路径下的等价性未验证，
  当前按 §2.3 一律走兼容路径。
- 空闲回收（`CELERITE_BRIDGE_IDLE_MS`）与协议超时在快路径下无桥可回收，未做运行时验证。
- `rbconfig.rb` 解析耗时未精确计时（只按 15181 B 规模估算 <1 ms）。
