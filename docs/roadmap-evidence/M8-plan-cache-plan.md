# M8 L165 落地设计：持久化、版本化的解析/安装计划缓存

题目原文（`docs/roadmap.md:165`）：

> - [ ] 实现持久化、版本化的解析/安装计划缓存，键包含 source 身份、凭据隔离标识、checksum、平台、Ruby ABI 和 build 配置；缓存损坏安全回退，不把未校验产物视为可用。

验收线（`docs/roadmap.md:168`）：无变化 lock/install 的 Ruby 启动次数为零；缓存复用前后输出/依赖/文件内容/退出码一致；基准含 wall/CPU/RSS、RPC 与 I/O。

本文档为只读调研产出：所有锚点均为本工作树（`C:\temp\celerite-t254` @ `053036e`）现场读码或实测所得；未跑的项目在第 9 节逐条列明。

## 0. 结论速览

- **能覆盖什么**：`lock`、`install` 共用同一入口 `Resolution#resolve!`（`src/celerite/cli/commands_install.cr:490`），`cache` 命令复用 `install`（`src/celerite/cli/commands_install.cr:1405`）。计划缓存的主收益对象是**无变化 install**（10 rpc / 315,715 B / 1053–1146 ms，实测见第 6 节）与**无变化 lock**（2 rpc / 1,911 B / 404–794 ms）。`check` 同为 2 rpc 量级（3115 B / 366 ms），是可顺带受益的第三个命令。`update`/`--force` 走 `no_reuse` 分支（`src/celerite/cli/commands_install.cr:152` 参数 `no_reuse`），本条缓存对它们无收益（该分支未逐行读，标「未验证」）。
- **能省多少**：无变化 install 的 10 次 RPC 里，只有约 2 次属「解析/求值」（与 lock 同量：`src/celerite/resolution.cr:1096` → `:1183` 复用分支），另 8 次与约 300 KB 响应属 install 独占的宿主侧 spec 枚举与该命令自身的安装流水线动作。实测把 `GEM_HOME`/`GEM_PATH` 指向空目录后，同一无变化 install 的 `resp_bytes` 由 315,715 降到 15,553 而 `rpc` 仍是 10（第 6 节），即 **~300 KB 与项目内 gem 数无关、随宿主已装 gem 规模变化**。若计划缓存只承载「解析结果」，上限收益 = 2 rpc/1.9 KB；若同时承载「已装 spec 快照」，才可能逼近 L168 的「零 Ruby 启动」，代价是必须用文件系统校验兜底（第 4 节失效矩阵「已装目录被删」行）。
- **墙钟上限**：本机 `--version`（不启桥）28 ms（首次 272 ms，冷页缓存），是进程底；因此命中路径的合理目标是 100–200 ms 量级（= 进程底 + 缓存读 + 安装目录存在性校验），相对 1053–1146 ms 降一个数量级。
- **最大风险**：extensions 目标目录名**不含 build 配置**——`<root>/extensions/<Gem::Platform.local>/<abi>/<full_name>`（`src/celerite/installer.cr:51`），而 build args 来自 `cfg["build.#{name}"]`（`src/celerite/installer.cr:62`）。同一 ABI 下两套 build 配置共享同一扩展目录，键里若漏了 build 配置，缓存会把「用另一套 flags 编出来的产物」判为可用，直接违反 L165 后半句。

## 1. 负载定义

### 1.1 「解析结果」是什么对象

解析产物不是单一结构体，而是三件：`Resolution#resolved_specs`（`Array(Resolution::ResolvedSpec)`，`src/celerite/resolution.cr:203`）、`Resolution#sources`（`Hash(String, SourceInfo)`，`src/celerite/resolution.cr:253`）、以及由二者渲染出的锁文本（`src/celerite/resolution.cr:2525` `lockfile_rewrite_text`）。锁文件模型的落地形态见 `src/celerite/lockfile/model.cr:288`（`Data`）与各段结构 `:18`/`:31`/`:52`/`:82`/`:125`/`:137`/`:167`/`:190`/`:211`/`:229`/`:243`/`:257`。

| 字段（`ResolvedSpec`，`resolution.cr:203`） | 存 / 派生 | 判据 |
| --- | --- | --- |
| `name`、`version` | 存 | 锁段 `Spec`（`lockfile/model.cr:52`）同字段，无重算可能 |
| `platform` | 存 | 同 `Spec#platform`；`platform_ruby?`（`resolution.cr:244`）可由它派生，不另存 |
| `dependencies` | 存 | 来自 gemspec 边，重算需读 `.gem`/已装 spec，代价高于存 |
| `checksum` | 存（缺失则整条不可用） | `resolution.cr:2675-2701` 三源优先级见 2.3 |
| `source_index` | 派生 | 同一 remote 内的位置，索引刷新后可重算 |
| `source_remote`、`source_type` | 存 | 决定下载器与安装动作（`commands_install.cr:586-588`） |
| `source_info` | 存（`SourceInfo`：type/remote/branch/tag/ref/submodules/glob/revision/plugin_type/lock_options，`resolution.cr:253`） | git 的 `revision` 只在 clone 后可得（`resolution.cr:2246-2260`、`:1723`），不可重算 |
| `source_declared` | 派生 | 来自 Gemfile 文本；以 Gemfile 摘要入键即可，不入载荷 |
| `required_ruby_version`、`required_rubygems_version` | 存 | `Installer#ensure_specs_are_compatible!`（`installer.cr:99`）在解析后立即校验，命中路径必须能免 Ruby 复现该检查 |
| `default_gem` | 存 | 决定「内置 gem 不下载只警告」（`commands_install.cr:534-543`） |
| `full_name` | 派生 | `resolution.cr:248`，由 name/version/platform 拼 |

### 1.2 「安装计划」是什么对象

**当前代码里没有一等公民的「计划」对象**：计划是 `run_install` 内联算出的流水线状态，按出现顺序为——`installable`（`commands_install.cr:504`）→ `pending = installable…select(source_type=="GEM")`（`:505`）→ 剔除已装（`:511-514`）→ 剔除 default gem（`:534-543`）→ 按 remote 惰性建 `Installer`（`:585-595`）→ 事件流 `install_events`（`:598-611`）。所以缓存要落地的不是「一个对象」，而是一组**决策**：装哪些、从哪个 remote 取、落到哪个 gem_root、是否需要编扩展、需要哪些 bin/plugin 动作。

| 计划要素 | 存 / 派生 | 判据 |
| --- | --- | --- |
| 待装集合（full_name 列表、顺序按 full_name 排序） | 存 | `commands_install.cr:505` 的 `sort_by(&.full_name)` 是输出顺序的来源 |
| 每个 spec 的 remote | 存 | `resolution.remote_for(spec.name)`（`commands_install.cr:586`） |
| 目标 gem_root + abi | 存（键的一部分，不入载荷正文） | `commands_install.cr:299` + `InstallPaths.gem_root`（`resolution.cr:132`，非 system gem 时追加 `ruby/<abi>`） |
| 每 spec 的 build args | 存（键的一部分） | `installer.cr:62`、`assets/bridge/server.rb:1050` |
| jobs（并发度） | 只入「是否可复用 extensions」判据，不入内容键 | `installer.cr:72`、`server.rb:1059-1063`；改变并发不改产物字节，但会改 build 日志顺序 |
| `Fetching`/`Installing` 行文本、`was_suffix`、`native_suffix` | 派生 | `commands_install.cr:559-565`、`:598-611`；命中路径必须重算而非回放，否则输出一致性无法证明 |
| `gem_file` 路径 | 派生 | 下载缓存内容寻址：`<cache_root>/downloads/<sha256[0,16]>-<name>-<version>.gem`（`src/celerite/downloader.cr:85`、`:155-157`） |

### 1.3 最小可持久化闭包

存：`{format, written_at, key(六成分), specs[]:{name,version,platform,dependencies,checksum,source_type,remote,source_info,required_ruby_version,required_rubygems_version,default_gem}, plan:{gem_root,abi,extensions_root,entries[]:{full_name,remote,build_args_digest,needs_extension}}, installed_snapshot[]:{full_name,spec_digest}}`。

不存：任何渲染文本、任何 `full_name`/`platform_ruby?` 派生值、任何凭据明文、任何 `.gem` 字节。

## 2. 缓存键的六个成分

键 = `canonical_json(六成分)` 的 SHA-256；六项中任一项「读不到/不确定」，**一律不得命中**（下文每项单列处置）。

### 2.1 source 身份

- 读取点：主源 `resolution.cr:479` `primary_remote`（缺省 `https://rubygems.org/`，且归一化补尾斜杠，`resolution.cr:504` `normalize_rubygems_remote`）；按 gem 分源 `resolution.cr:568` `scoped_remote_for`；非 gem 源 `resolution.cr:589` `non_gem_sources`；git/path 的源描述来自锁段 `SourceSection`（`lockfile/model.cr:82`）与 `SourceInfo`（`resolution.cr:253`）。
- 规范化：GEM 源 —— scheme/host 小写、去尾斜杠、剥离 userinfo（`://user:pass@` 部分，正则参照 `eval_cache_store.cr:45`）；PATH 源 —— `File.expand_path` 后统一 `/` 分隔（Windows 盘符保留，`resolution.cr:105` 已有同样处理）；GIT 源 —— URL + 40 位 `revision` + `submodules`/`glob` 布尔与串；自定义 `type:` —— `type` 原样 + `plugin_type`（`resolution.cr:253`）。
- 未知处置：源不能归一（例如 git 无 `revision`、自定义源无 `plugin_type`）→ 该条不写缓存、不命中；跨源共享同一缓存条目视为缺陷（V7 断言）。

### 2.2 凭据隔离标识

- 读取点：`EvalCacheStore.namespace`（`src/celerite/eval_cache_store.cr:68-75`）是既有做法——对排序后的凭据型 `BUNDLE_*` 键值对做 SHA-256，取前 16 位十六进制；判定哪些键算凭据用 `credential?`（`:80-83`：`BUNDLE_` 前缀 + 键名含 `__` 或值内含 userinfo），常量 `CREDENTIAL_URI`（`:45`）与 `NAMESPACE` 长度（`:47`）。
- 规范化：本缓存把 `namespace` 扩成「源 URL 去 userinfo + 凭据对哈希」，仍只取哈希前 16 位当作目录名，明文凭据不落盘；`persistable?`（`:100`）与 `persist skipped (credential)`（`bridge/client.cr:456`）说明既有层在凭据无法安全归一时选择**不持久化**，本缓存沿用同一策略。
- 未知处置：配置里存在凭据但无法识别键形态（非 `BUNDLE_*`、无 `__`、值不像 userinfo）→ 不写不命中，并在 A/B 报告里显式打印 `plan-cache: skipped (credential)`（与 `bridge/client.cr:456` 同风格）。

### 2.3 checksum

- 读取点：`resolution.cr:2675-2701` 的三级优先——本次运行实际产物的 digest > 锁内既有 `CHECKSUMS` 条目 > 索引 spec 的 `checksum`；归一化为 `sha256=<hex>`（`resolution.cr:185` `info_checksum_value`，注释说明索引侧可能是裸 hex / base64 / `sha256=`）；三源皆空时写入空数组（`:2690`）；4.x 另有 bundler 自校验和（`:2703`）。锁段结构见 `lockfile/model.cr:190`/`:211`。
- 规范化：统一小写 hex；多平台条目按 `(name, version, platform)` 索引（`lockfile/model.cr:190`）。
- 未知处置：checksum 缺失（空数组）或格式非法 → 该 spec 不可入缓存、命中时视为未校验产物 → 必须 miss 并回落真实安装（L165「不把未校验产物视为可用」）。`BUNDLE_LOCKFILE_CHECKSUMS` 缺省为真（`src/celerite/config.cr:37`），因此「缺失」是真实可达状态，不是理论分支。

### 2.4 平台

- 读取点：解析期 `resolution.cr:2362-2369` `resolution_platforms`（`BUNDLE_FORCE_RUBY_PLATFORM` 为真时用 `Gem::Platform.new("ruby")`，否则 `Gem::Platform.local`）；锁内 `PLATFORMS` 写入 `resolution.cr:2614-2618`；设置开关 `force_ruby_platform?`（`resolution.cr:2392-2393`，读 `config["force_ruby_platform"]`，键名见 `config.cr:17`）。注意 `reuse_locked?` 在 `force_ruby_platform?` 时直接返回 false（`resolution.cr:1402`），说明该设置改变「materialize 哪一行」，属键级成分而非装饰。
- 规范化：平台字符串原样（`x86_64-linux` 等不做别名折叠），并额外记 `force_ruby_platform` 布尔；`platform: "ruby"` 是明确值，**不是通配**。
- 未知处置：既无锁内 `PLATFORMS`、又无法取到 `Gem::Platform.local`（在不启动 Ruby 的前提下无法判定）→ 不命中。

### 2.5 Ruby ABI

- 读取点：`src/celerite/runtime_facts.cr` 可在**不 spawn Ruby** 的前提下从文件解析运行时事实（`detect` `:135-158`，`Facts#matches?` `:104-115`）；ABI 目录名由 `InstallPaths.ruby_abi_for(version)`（`resolution.cr:170`）算出，`<major>.<minor>.0`，在 `runtime_facts.cr:283` 被赋值。
- 规范化：三字段并列入键——`ruby_api_version`、`extension_api_version`（可能带 `-static` 后缀，`eval_fingerprint.cr:95`、`bridge/client.cr:611-616`）、`rbconfig` 的 `ruby_version`；`Abi#complete?`（`fast_path_store.cr:78`）给出「三字段皆非空」的既有判定可直接复用。
- 未知处置：任一字段缺失（`RuntimeFacts::Source::Unknown`，`runtime_facts.cr:27-35`/`:42-60`）→ 不命中；`Facts#matches?` 已确立「unknown 视为 mismatch，绝不当通配」（`runtime_facts.cr:104-115`），本条沿用。

### 2.6 build 配置

- 读取点：`Installer#config_build_args` 读 `cfg["build.#{name}"]` 并按空格切分（`src/celerite/installer.cr:62`）；配置键归一化在 `src/celerite/config.cr:211-213`（`build.` 前缀视为字符串键），反向映射 `key_for` 把 `__` 还原为 `.`（`config.cr:419`），因此环境变量形态是 `BUNDLE_BUILD__<GEM>`；桥侧 `op_build_extension` 接收 `build_args`（`assets/bridge/server.rb:1050`）与 `build_jobs`（`:1059-1063`），最终调 `Gem::Ext::Builder#build_extensions`（`:1067`）并写 `gem.build_complete`（`:1068`）。
- 规范化：对每个带扩展的 gem，取 `build.<gem>` 切分后的参数数组（顺序敏感，空白折叠），哈希后入键；无该键时为**空数组**（确定值，不是未知）。
- 未知处置：配置解析失败、或该 gem 在锁内有 `extensions` 但无法确定 build args 的归属（例如 `BUNDLE_BUILD__<GEM>` 中的 `<GEM>` 与锁内名字大小写/连字符不一致）→ 不命中。

## 3. 存储布局与版本

- **版本字段**：条目首字段 `format: "celerite-plan-cache/1"`，与 `celerite-eval-cache/1`（`eval_cache_store.cr:33`）、`celerite-fast-path/1`（`fast_path_store.cr:43`）同构；布局段 `plan/v1`（参照 `eval_cache_store.cr:34` `LAYOUT = "v1"`）。
- **位置**：根目录解析沿用既有优先级——`CELERITE_CACHE_DIR` 优先，否则 `$HOME/.celerite/cache`（`eval_cache_store.cr:36`/`:58-66`，`fast_path_store.cr:45`/`:185`）。计划缓存放 `<root>/plan/v1/<namespace16>/<sha256(key)>.json`。
- **条目格式**（JSON，单条一项）：

  ```
  {"format":"celerite-plan-cache/1","written_at":"<RFC3339 UTC>","digest":"<sha256 of canonical payload>",
   "key":{"sources":[...],"credential_namespace":"<16 hex>","checksums":[...],"platform":{...},
          "abi":{...},"build":{...},"inputs":{"gemfile":"<sha256>","lockfile":"<sha256>","vendor_cache":"<sha256|absent>"}},
   "payload":{"specs":[...],"plan":{...},"installed_snapshot":[...]}}
  ```

  `digest` 只覆盖 `payload` 的规范化 JSON，用于识别截断/篡改；`key` 不参与自校验，但条目被读取时**重算键并比对**（`<sha256(key)>.json` 文件名即键哈希，重算不符即 miss）。
- **原子写**：同目录临时文件 `.plan-<pid>-<hex>.tmp` → `flush` → `fsync`（失败可忽略）→ 删除目标再 `rename`，这与 `eval_cache_store.cr:104-133` 完全同构；Windows 上「删除再改名」避免目标存在时的替换失败。
- **损坏即删**：解析失败、`format` 不符、`digest` 不符、`key` 重算不符 → `delete` 后 miss，不抛异常（参照 `eval_cache_store.cr:135-156`、`:201-209`、`:211-216`）。
- **上限与淘汰**：`MAX_ENTRIES = 256`、`MAX_BYTES = 16 MiB`（既有层是 128 / 8 MiB，`eval_cache_store.cr:38-39`；计划条目比求值条目大，故翻倍）；淘汰按 mtime 跨 namespace 全局裁剪，做法照搬 `eval_cache_store.cr:167-199`。
- **开关**：新增 `CELERITE_PLAN_CACHE=1`（默认关），根沿用 `CELERITE_CACHE_DIR`。理由三条：① 与 F4（`eval_cache_store.cr:35`/`:51`）、FastPath（`fast_path_store.cr:44`）保持一致的「默认关、显式开」策略；② L165 要求「不把未校验产物视为可用」，默认关可用作影子期（只算键、写日志、不用结果）；③ L168 的「零 Ruby 启动」判据需要 A/B 开关才能证伪。**不建议**复用 `CELERITE_CACHE_DIR` 单独作开关——它的语义是「根目录」，两个既有层都把它当路径而非布尔。

## 4. 失效矩阵

判定列中「零 Ruby」= 不启动 Ruby、仅凭文件可判。

| # | 输入变化 | 命中？ | 判据（零 Ruby 可判？） |
| --- | --- | --- | --- |
| 1 | `Gemfile` 内容变化 | 必须 miss | 比对 `inputs.gemfile` 摘要。零 Ruby 可判（读文件）。 |
| 2 | `Gemfile.lock` 文本变化（依赖/版本/平台/CHECKSUMS 任一段） | 必须 miss | 比对 `inputs.lockfile` 摘要 + 逐 spec 的 `(name,version,platform,checksum)` 对照锁段（`lockfile/model.cr:52`/`:190`/`:125`）。零 Ruby 可判。 |
| 3 | 源 URL 变化（含多源与新 scope） | 必须 miss | 六成分之 source 身份逐项比较（`resolution.cr:479`/`:568`）。零 Ruby 可判。 |
| 4 | 凭据变化（token 轮换、新增 `BUNDLE_*` 凭据键） | 必须 miss | `namespace` 由凭据对哈希算出（`eval_cache_store.cr:68-75`），变化即目录切换。零 Ruby 可判。 |
| 5 | 平台变化（换机器/`BUNDLE_FORCE_RUBY_PLATFORM` 翻转） | 必须 miss | 键内 `platform` 成分；`force_ruby_platform?` 已是解析级开关（`resolution.cr:2392`、`:1402`）。零 Ruby 可判。 |
| 6 | Ruby ABI 变化（升级 Ruby、`-static` 变体） | 必须 miss | 三字段 `ruby_api_version`/`extension_api_version`/`rbconfig.ruby_version`（`runtime_facts.cr:104-115`、`fast_path_store.cr:78`）。`RuntimeFacts` 保证零 spawn（`runtime_facts.cr:135-158`）。 |
| 7 | build 配置变化（`BUNDLE_BUILD__<GEM>`） | 必须 miss | 键内 `build` 成分（`installer.cr:62`、`config.cr:211-213`/`:419`）。零 Ruby 可判。**注意**：extensions 路径不含 build args（`installer.cr:51`），故此项是唯一能从「路径层面看不出来」的成分。 |
| 8 | gemspec 内 `extensions` 变化（同一 name/version 的 `.gem` 被替换成带/不带扩展） | 必须 miss | 需要 spec 级判据：条目存 `needs_extension` 与 spec 摘要，命中前比对 `.gem` 文件 sha256 或锁内 checksum 是否变化。若 `.gem` 不在本地且无 checksum → 不予命中（2.3）。零 Ruby 可判（比对摘要）。 |
| 9 | `vendor/cache` 内容变化（新增/删除/替换 `.gem`） | 必须 miss | `resolution.cr:797` `vendor_cache_path`、`:878` `vendor_cache_specs`；条目存 `inputs.vendor_cache`（目录内 `*.gem` 名+大小的摘要），变化即 miss。零 Ruby 可判。 |
| 10 | 已装目录被删/被替换（`gems/<full>` 或 `specifications/<full>.gemspec` 消失） | 必须 miss | `Installer#installed?`（`installer.cr:87`）要求两者同时存在；命中路径必须先跑该文件检查，失败即 miss 并回落安装。零 Ruby 可判（只 stat 文件）。 |
| 11 | 扩展产物缺失（`gem.build_complete` 不存在） | 必须 miss（对带扩展的 spec） | `installer.cr:58` `extension_build_needed?` 以标记文件为准。零 Ruby 可判。 |
| 12 | 缓存文件被截断 / JSON 非法 / `digest` 不符 | 必须 miss（并删除该条目） | `format`+`digest`+键重算三重校验（第 3 节）。零 Ruby 可判。 |
| 13 | 缓存条目被篡改（payload 合法但换了 specs） | 必须 miss | 同上：`digest` 覆盖 payload；且命中后仍需 `installed?` 文件校验兜底。零 Ruby 可判。 |
| 14 | 只改 `Gemfile` 注释/顺序（语义等价） | 可以 hit（但实现选择 miss） | 摘要级比对会让它 miss；若追求命中需要语义摘要（解析后依赖集合）。建议 V1 期用「摘要即 miss」的保守方案，零 Ruby 可判。 |
| 15 | `jobs`/并发度变化 | 可以 hit | 不影响产物字节，只影响构建日志顺序；`installer.cr:72`。零 Ruby 可判。 |

## 5. 与既有缓存的关系

| 层 | 位置/开关 | 存什么 | 生命周期 | 与计划缓存的边界 |
| --- | --- | --- | --- | --- |
| `EvaluationCache`（进程内） | `src/celerite/bridge/client.cr:144` 起；`begin_run` `:170`、`finish` `:185-195`、`fetch` `:244-263`、`environment_signature` `:225-233` | Gemfile 求值结果 + 指纹文档 + gemspec 路径，按进程存活 | 单进程 | 计划缓存**不得**再存求值文档；命中计划后仍需签名/路径一致性时，复用该层的内存命中而非另存一份 |
| `EvalCacheStore`（持久求值） | `src/celerite/eval_cache_store.cr`，`CELERITE_EVAL_CACHE=1`，`<root>/<ns>/v1/<hex>/entry.json`，128 条 / 8 MiB | 单次求值的指纹 + 文档（`format`+`digest`+`evaluation` 必填，`:201-209`） | 跨命令 | 计划缓存**不得**复制 evaluation 文档；两者共享 `namespace` 与根目录，但布局前缀不同（`plan/` vs 无前缀）。若要省多次求值，应扩大 `EvalCacheStore` 而非塞进计划缓存 |
| `FastPathStore`（运行时事实） | `src/celerite/fast_path_store.cr`，`CELERITE_FAST_PATH=1`，`<root>/fast-path/v1/<ns>/<sha256(project)>.json`，纯文件 IO，未接任何命令（`:37` 注释） | 7 个运行时字段 + ABI + 项目摘要 + 凭据命名空间 | 跨命令 | 计划缓存**可以复用**它的运行时记录来满足 2.4/2.5 的零 spawn 读取，但**不得**复用它的 decision（它的语义是「能不能跳过 Ruby」，不是「装什么」）；也不得把 plan 塞进它的条目 |
| 本 L165 计划缓存 | `<root>/plan/v1/<ns>/<sha256(key)>.json`，`CELERITE_PLAN_CACHE=1` | 解析闭包 + 安装计划 + 已装快照（第 1.3） | 跨命令 | 唯一职责：让无变化 install/lock 免解析、免桥、免宿主 spec 枚举 |

替代代价：
- 若计划缓存要**替代** `EvalCacheStore`（即不再持久求值文档），代价是丢失「指纹三态 + 文档校验」这套已实现的确定性证据链（`src/celerite/eval_fingerprint.cr:60-80`/`:221-244`），且求值结果无法被 `check`/`outdated` 之外的新命令单独消费；不建议替代。
- 若计划缓存要**替代** `FastPathStore`，代价是丢掉「不 spawn 也能算运行时事实」的纯文件实现（`runtime_facts.cr:135-158`），而计划缓存的键恰恰依赖它；方向相反，禁止替代。
- 下载缓存（`InstallPaths.downloader_cache_root` = `<home>/.bundle/cache`，`resolution.cr:159`；`.gem` 存 `<cache_root>/downloads/<sha256[0,16]>-<name>-<version>.gem`，`downloader.cr:85`/`:155-157`）与计划缓存无重叠：前者存字节、后者存决策；计划条目引用 `.gem` 路径时必须校验其校验和（`downloader.cr:160` `verify`）。

## 6. 收益实测（本机）

方法：`crystal build src/cli.cr -o bin\celerite.exe` 构建本工作树二进制（`--version` 输出 `4.0.24`）；测试项目 `C:\temp\t254-proj`，`Gemfile` 为两行依赖（`json_pure`、`thor`），源为本地 `file:///C:/temp/celerite-t254/fixtures/gem-index`（无网络抖动）；`BUNDLE_PATH=<proj>\vendor\bundle`；`CELERITE_CACHE_DIR=C:\temp\t254-cache-a`；每次运行设 `CELERITE_BRIDGE_STATS=1` 并抓取 stderr 的 `bridge: procs=… rpc=… req_bytes=… resp_bytes=…`（格式见 `bridge/client.cr:93-95`）；墙钟用 `Stopwatch` 包住整次进程调用。冷场景先删 `vendor/` 与 `Gemfile.lock`。

| 场景 | 第几次 | procs | rpc | req_bytes | resp_bytes | wall_ms |
| --- | --- | --- | --- | --- | --- | --- |
| 冷 `install` | 1 | 1 | 21 | 4285 | 320366 | 2172 |
| 冷 `install` | 2 | 1 | 21 | 4283 | 320366 | 1305 |
| 无变化 `install` | 1 | 1 | 10 | 1675 | 315715 | 1053 |
| 无变化 `install` | 2 | 1 | 10 | 1675 | 315715 | 1146 |
| 无变化 `lock` | 1 | 1 | 2 | 207 | 1911 | 404 |
| 无变化 `lock` | 2 | 1 | 2 | 207 | 1911 | 794 |

补充实测（用于归因，同一项目、同一开关）：

| 场景 | 结果 |
| --- | --- |
| `--version`（不启桥） | procs=0 rpc=0，wall 272 ms（首次）/ 28 ms（暖） |
| 无变化 `check` | rpc=2、req=211、resp=3115、wall 366 ms |
| 单 gem 项目（仅 `thor`）冷 / 热 `install` | 15 rpc / 317786 B；9 rpc / 315470 B；wall 1504 / 1229 ms |
| 无变化 `install`，`GEM_HOME`/`GEM_PATH` 指向空目录 | rpc=10（不变）、req=1675（不变）、resp=**15553**、wall 1087 ms、输出仍为 `Bundle complete! 2 Gemfile dependencies, 2 gems now installed.` |

归因（哪些是「解析」、哪些是「安装动作」）：

- **解析侧**：`lock` 的 2 rpc / 1,911 B / 404–794 ms 就是解析+锁写成本。按代码路径（`commands_install.cr:490` → `resolution.cr:1096` → 复用分支 `:1183`）这 2 rpc 是「桥启动 + 求值」，但**未逐 op 打点验证**（标「未验证」）。
- **安装动作侧**：install 比 lock 多 8 rpc 与约 313.8 KB 响应；其中约 300 KB 与项目内 gem 数无关（1 gem 项目 315,470 B，2 gem 项目 315,715 B），且随宿主已装 gem 规模变化（`GEM_HOME` 置空后降到 15,553 B，rpc 不变）。结论：**~300 KB / 部分 rpc 是宿主 Ruby 已装 spec 枚举**，属 install 命令独有开销，不是解析产物。具体是哪个 RPC、由哪个调用点触发，本次未定位（标「未定位」）。
- **冷/热差**：21 rpc → 10 rpc、320,366 → 315,715 B，差值为下载与落盘（`installer.cr:132`/`:236-291`）。

上限收益推算：

- 只缓存「解析结果」：省掉 lock 那 2 rpc / 1.9 KB，install 的 wall 由 1053–1146 ms 降到约 700–900 ms（按 lock 的 404–794 ms 中解析占比估计），**收益有限**。
- 同时缓存「已装 spec 快照」：install 的 10 rpc 可望降到 0–2，resp 315 KB 可望降到 0，wall 逼近进程底 `--version` 28 ms + 缓存读 + 目录校验，**100–200 ms 量级**（估）。这是 L168「零 Ruby 启动」可达的唯一路径，但必须满足第 4 节 #10/#11 的文件校验兜底。
- 本机为 2 gem 小项目，绝对收益（约 0.9–1.1 s）不代表 Rails 规模；Rails 规模下解析与索引成本放大，而 315 KB 宿主枚举基本恒定（未验证，见第 9 节）。

## 7. 切片 P1–P4

| 片 | 一句话目标 | 验收判据 | 依赖 |
| --- | --- | --- | --- |
| P1 | 只算键、只读缓存、从不使用：实现六成分规范化 + 键哈希 + 条目读取/校验/删除，输出 `plan-cache: key=<hex> hit/miss reason=<…>` 诊断 | 在 `CELERITE_PLAN_CACHE=1` 下 `lock`/`install`/`check` 的 stdout/stderr/退出码与关闭时逐字节一致；六成分任一缺失时诊断固定为 `reason=unknown` 且不读缓存；新增 spec 覆盖六成分齐全与三态（hit/miss/corrupt） | 无，可立即并行 |
| P2 | 写入侧：原子写 + 自校验 + prune，仍不读用 | 强制 kill 进程后目录内无 `.tmp` 残留（未验证项见第 9 节）；写坏文件被下次运行删除；`MAX_ENTRIES/MAX_BYTES` 裁剪后条目数与字节数达标 | 依赖 P1 的键与格式 |
| P3 | 命中侧接入 `install`/`lock` 的解析入口（`commands_install.cr:490` 之前），先只省解析 RPC，宿主 spec 枚举与已装校验保持原样 | 命中路径 `celerite install` 的 `bridge: rpc=` 比未命中少 2（不强制零）；输出/依赖/文件内容/退出码与未命中逐项一致；命中时 `CELERITE_BRIDGE_STATS` 的 `procs` 可仍为 1 | 依赖 P2 |
| P4 | 达到零 Ruby：把已装 spec 快照纳入条目，命中路径用文件校验替代枚举；补齐失效矩阵全部 15 行 | `procs=0 rpc=0`（无变化 install/lock）；第 4 节 15 行逐行有 spec；基准表含 wall/CPU/RSS/RPC/IO | 依赖 P3；P4 内部「快照」与「校验」两半可并行 |

## 8. 判据草案 V1–V12

- **V1**：`CELERITE_PLAN_CACHE` 未设或 `"0"` 时，`lock`/`install`/`check` 的输出字节、退出码、`bridge: procs/rpc/req_bytes/resp_bytes` 与关闭前完全一致（零回归）。
- **V2**：缓存命中与未命中的两次 `install` 产生逐字节相同的 `Gemfile.lock` 与相同的 `vendor/bundle` 文件集合（路径+大小+sha256）。
- **V3**：缓存命中与未命中的两次运行 stdout/stderr 逐字节一致（`Fetching`/`Installing` 行必须重算而非回放）。
- **V4**：条目被截断（写入前 N 字节）后下一次运行必须 miss、删除该条目、并成功完成安装，退出码与原语义一致。
- **V5**：条目 payload 被替换为合法 JSON 但 `digest` 不符时，必须 miss 且删除。
- **V6**：条目文件名哈希与重算键不符时，必须 miss（跨键串用不可发生）。
- **V7**：不同 `credential_namespace` 下同名同版本依赖不得互相命中；缓存目录中不出现任何凭据明文（对整棵缓存树做 token 子串扫描）。
- **V8**：`checksum` 缺失的 spec 不入缓存；构造「锁内 CHECKSUMS 为空」的项目跑两次，第二次仍 miss。
- **V9**：`extensions` 变化（同名同版本 `.gem` 换成带扩展的版本）、build 配置变化、ABI 变化三例各自独立触发 miss。
- **V10**：删除 `vendor/bundle` 下任一 `gems/<full>` 或 `specifications/<full>.gemspec` 后，下一次 `install` 必须 miss 并把该 gem 重新装回（不得把未校验产物视为可用）。
- **V11**：缓存目录整体设为只读时，命令必须仍成功（写入失败按 miss 处理，不得报错退出）。
- **V12**：P4 之后，无变化 `lock`/`install` 的 `procs=0 rpc=0`，且 wall 不超过关闭缓存时的 1/3（本机基线 1053–1146 ms）。

## 9. 本机不可验证与未验证

1. **未逐 op 打点**：install 比 lock 多的 8 次 RPC 中，具体哪一次返回约 300 KB、由哪个调用点发起，未定位；仅有「与宿主已装 gem 规模相关、与项目 gem 数无关」的间接证据（第 6 节三组对照）。
2. **未验证 Rails 规模**：本机仅 2 gem 项目与 1 gem 对照项目；Rails 级依赖树（数百 spec）下解析成本、缓存条目大小、prune 行为均未测。
3. **未验证多 ABI / Linux**：本机只有 Ruby 4.0（`C:\Ruby40-x64`）单一 ABI；`-static` 变体（`extension_api_version` 带后缀，`eval_fingerprint.cr:95`）与 Linux 平台未构造。
4. **未验证真并发写**：两个进程同时写同一键、同时 prune 的竞争未测；原子写只做了单进程逻辑审阅（`eval_cache_store.cr:104-133` 同构）。
5. **未做崩溃注入**：进程被 kill、断电、写盘半途的恢复行为未测（P2 验收项因此标为「待验证」）。
6. **未验证 Windows 跨卷 rename/替换语义**：目标已存在时「删除再改名」的失败窗口未构造。
7. **未验证 `update`/`--force` 路径**：`no_reuse` 分支（`commands_install.cr:152`）未逐行读，缓存对这些命令无收益的结论来自参数名而非实测。
8. **未验证 `check` 的解析入口细节**：只测到 rpc=2 / 3115 B / 366 ms，未读其代码路径。
9. **未验证凭据形态覆盖**：只按 `eval_cache_store.cr:80-83` 的判定逻辑推演，未构造真实凭据配置文件测试 `persistable?` 分支。
10. **未跑 `script/differential`**（按任务约束，lead 的全量差分占用端口 8765），因此「零输出变化」在差分基准层面的证据缺失，仅靠本机逐字节比对。
