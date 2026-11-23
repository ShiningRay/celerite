# M8 「无 Ruby 快路径」可行性调研（task-223）

- 仓库：`C:\temp\celerite-t223`（detached HEAD `9098d29`，即 task-219 的 `docs(M8 task-219): claim C-M8-1-001 and record the measured bridge baseline`）
- 依据条目：`docs/roadmap.md:164`（无变化 lock/install 直接用 lockfile 与安装计划，不加载 Bundler、不启动 Ruby）、`docs/roadmap.md:166`（check/list/show 复用已安装 gem 索引）、`docs/roadmap.md:168`（验收：无变化 lock/install 的 Ruby 启动次数为零）
- 参考实现：Bundler 4.0.24，`C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\lib\bundler\`（下文简写 `ref:`）
- 前序证据：`docs/roadmap-evidence/M8-batch-bridge.md`（`### 只读命令`、`### RPC 粒度`、`### 计数点`）；指纹切片 `docs/roadmap-evidence/M8-evaluation-fingerprint.md`（task-222）**在本工作树不存在**，本文不假设其内容。
- 只读声明：本文为唯一写盘产物；未构建二进制（`bin/` 不存在），未跑 `script/differential`（端口 8765 被占）。所有"实测"数字均转引 `M8-batch-bridge.md` 在 `3fd7a8d` 的探针测量，标注为「转引」；HEAD `9098d29` 的进程数本文**未实测**。

## 0. 结论先行

1. **现在就能免 Ruby 的命令：0 条。** 严格口径下，`lock`/`install`/`check`/`list`/`show`/`pristine`/`exec`/`binstubs` 在 HEAD 上都至少有一次 `Bridge::Client.new`（`src/celerite/cli/commands.cr:3054`、`src/celerite/cli/commands_install.cr:266`、`src/celerite/cli/commands.cr:1570`、`:1769`、`:2077`、`src/celerite/cli/commands_surface.cr:3075`、`src/celerite/cli/commands_install.cr:1764`、`:2188`）。
2. **数据已在手、只差去掉 spawn 的：4 条**——`lock`（无变化）、`check`、`list`（无组过滤）、`show`（非 verbose）。四者的判定输入落在 lockfile、已装目录与 `Platform.local`（`src/celerite/gem/platform.cr:96-118`）里，无一项必须问 Ruby；唯一例外是 `lock` 的「Gemfile 未变」证明，无缓存时只能退化为 lockfile `DEPENDENCIES` 段弱判据（见 R3 与 §5-S5）。
3. **需要先补数据（缓存求值结果）的：4 条**——`list`/`show` 的组归属、`check` 的 `BUNDLE_WITHOUT` 分支、`install`（无变化）、`binstubs`/`pristine` 的可执行文件与 ABI。前三条依赖 task-222 的求值指纹；`binstubs` 还额外缺 gemspec 文本解析器（现只有 `src/celerite/cli/commands.cr:2640` 的 summary/homepage/metadata 三字段）。
4. **必须 Ruby 的：5 条**——`add`、`remove`、`update`、`install`（首装/变更）、`lock` 的编辑类开关（`--update`、`--add-platform`、`--remove-platform`、`--add-checksums`、`--normalize-platforms`）。它们要产生新的 resolution，不是"证明不变"。
5. **最危险的三条漂移**：`check` 的满足判据（静默降级已被实测成 exit 0）、`list` 的组归属与顺序、`lock` 的"不改写"判定与 `BUNDLED WITH` 版本来源。
6. 切片 5 个：S1 已装判定去桥 → S2 check 窄快路径 → S5 lock 短路前移；S3 组归属缓存（依赖 task-222）→ S4 install 无变化快路径（依赖 S1+S3）。

## 1. 命令 × 是否需要 Ruby 矩阵

列义：「现状」= HEAD 是否会 spawn ruby；「补齐数据后」= 是否可做到零 spawn。所有"我方"行号为 `src/celerite/` 下路径，参考为 `ref:`。

| 命令 | 现状 | 补齐数据后 | 依据（我方 / 参考） |
| --- | --- | --- | --- |
| `lock`（无变化、无开关） | 需要 | **可不启动** | 我方：`:3054` 先 `Resolution.new`（建桥+求值），短路判定在 `:3085-3090` 之后才生效；判定量 `lockfile_exists?`、`lockfile_matches_dependencies?`（`src/celerite/definition.cr:182`）、`dependency_sources_changed?`（`:348`）、`lockfile_platforms_cover_local?`（`:2941`）、`incomplete_locked_spec_names`、平台覆盖。参考：`ref:cli/lock.rb:45` 无条件 `Bundler.definition`，`no_resolve_needed?` 在 `ref:definition.rb:556-558`、`something_changed?` 在 `:630-645` |
| `lock --add-platform` / `--remove-platform` | 需要 | 需要 | 我方：`:2956-2965`、`:2986-3000` 校验后 `:3086` 显式排除短路，`:3140-3141` 写入 `added_platforms`。参考：`ref:cli/lock.rb:54-61`、`ref:definition.rb:538-550` |
| `lock --update` / `--normalize-platforms` / `--add-checksums` / `--print` | 需要 | 需要（`--print` 无变化时**可不启动**） | 我方：`:3085` 的 `!checksum_refresh && !update && update_names.empty? && !add_checksums && !normalize_platforms`；`--print` 仍需正文 `:3092/:3104`，正文来自 `resolution.generated_lockfile`。参考：`ref:cli/lock.rb:70-79`、`:92-93` |
| `install`（无变化） | 需要 | 视缓存（见 S4） | 我方：`src/celerite/cli/commands_install.cr:266` 无条件建桥、`:274` 求值、`:281-282` ruby 校验、`:287` 平台校验、`:293` Resolution、`:299` ABI、`:308` frozen 校验。参考：`ref:cli/install.rb:45-53`（`Bundler.definition(strict: true)` + `validate_runtime!` + `Installer.install` + `Bundler.load.cache`） |
| `install`（首装/变更/`--local`/git·path 源） | 需要 | 需要 | 同上；install plan 由 resolution 产生，无 cache 不可能 |
| `check` | 需要 | **可不启动**（无 `BUNDLE_WITHOUT` 时）；有 with/without 时视缓存 | 我方：`:1570` `validate_runtime!`（→`:1369` 建桥），`:1618`/`:1623` 三元组求值，`:1641` `lock_ruby_unlock_kind`（`:1396` 桥不可用即 `:none`），`:1665-1693` PATH 漂移 probe，`:1723-1731` 已装判定，`:1742` 满足时重写锁，`:1758` 成功文案。参考：`ref:cli/check.rb:14-34`（`ensure_equivalent_gemfile_and_lockfile` + `validate_runtime!` + `check!`/`missing_specs` + `definition.lock(true)`） |
| `list`（无组过滤、无 `--paths`/`--name-only` 交互） | 需要 | **可不启动** | 我方：`:1769-1778` `available_groups` **无 gate** 直调 `lockfile_groups`（`:2729` 建桥）；`:1839` 使用；`:1849` 排序。参考：`ref:cli/list.rb:19-29`（`Bundler.load.specs` → reject bundler → `sort_by(&:name)`）、`:61-70` |
| `list --only-group` / `--without-group` | 需要 | 视缓存 | 我方：`:1840-1845` 未知组 exit 15（依据求值结果 `gem_groups_for:2745`）、`:2790` 的组比较会**再开**一个 client。参考：`ref:cli/list.rb:73-95`（`verify_group_exists` ← `definition.groups`；`specs_for(show_groups)`） |
| `show` / `info`（非 verbose） | 需要 | **可不启动** | 我方：`:2077` `validate_runtime!`，`:2109` `available_groups`，`:2113` 组过滤，`:2123` `installed_spec_dir?`，`:2640` gemspec 文本兜底。参考：`ref:cli/show.rb:14-17`（`Bundler.load.lock`，**show 会写锁**）、`:33-52`；`ref:cli/info.rb:13-14`、`:76` |
| `show --paths` | 需要 | **可不启动** | 同上；只打印 `installed_gem_dir`（`src/celerite/cli/commands_surface.cr:1676-1763`），纯文件系统 |
| `show --verbose` / `--outdated`（2.x） | 需要 | 需要 | 我方：`:2069` `Resolution.new(definition, true)` 远端解析 + `:2111-2122`。参考：`ref:cli/show.rb:10`、`:58-64`（`definition(true).remotely!`） |
| `pristine` | 需要 | 视输入（缓存 .gem 路径 + ABI 可推导时可不启动） | 我方：`src/celerite/cli/commands_surface.cr:3044` `validate_runtime!`、`:3075`/`:3077` 桥、`:3078` `InstallPaths.ruby_abi(bridge)`、`:3079` `default_gem_dir`、`:3102-3107`/`:3116-3133` 提示。参考：`ref:cli/pristine.rb:10-60`（`spec.cache_file`、`full_gem_path`、git/path 分类） |
| `exec` | 需要 | **可不启动**（需先证明 ruby 版本校验可后移） | 我方：`src/celerite/cli/commands_install.cr:1764` 建桥、`:1766` `ruby_environment`、`:1770` 求值、`:1772` `validate_version!`；注释 `:1757-1761` 说明参考只导出 `RUBYOPT`/`BUNDLE_GEMFILE`。参考：`ref:cli/exec.rb:11`、`:18`（不读 Gemfile） |
| `binstubs` | 需要 | 视缓存（executables 只能经 gemspec） | 我方：`src/celerite/cli/commands_install.cr:2188` `validate_runtime!`、`:2240`/`:2350` `read_gem_spec`、`:2361`/`:2388` `load_installed_spec`、`:2394` 取 `executables`。参考：`ref:cli/binstubs.rb:12`、`:17`、`:25-35`、`:42-53` |
| `add` | 需要 | 需要 | 我方：`src/celerite/cli/commands_surface.cr:422`，桥 `:519`/`:611`，写锁 `:921`。参考：`ref:cli/add.rb:28-29` |
| `remove` | 需要 | 需要 | 我方：`:951`，桥 `:1167`。参考：`ref:cli/remove.rb:14` |
| `update` | 需要 | 需要 | 我方：`:41`（`run_update:47`，桥 `:135`），`:91` `validate_runtime!`。参考：`ref:cli/update.rb:38-40`、`:54`、`:72`、`:81` |

分档合计：需要 5（add/remove/update/install 变更/lock 编辑类）、可不启动（补齐数据后）4（lock 无变化、check、list 无组、show 非 verbose；exec 单列不计入，因校验顺序未定）、视输入 6（install 无变化、pristine、list/show 的组、binstubs、check 带 with/without、lock --print）。

### 1.1 两套现实：`bridge_available?` 是探针开关，不是能力探测

`src/celerite/cli/commands.cr:2831-2837` 的 `bridge_available?` 只在 `CELERITE_BRIDGE_SERVER` 指向存在的文件、或 `CELERITE_REFERENCE_BUNDLER_LIB` 指向存在的目录时为真。普通用户环境两者都不存在 → **恒假**，于是 `check` 的组过滤（`:1618`/`:1623`）、锁重写（`:1739`）、`read_gemspec_info_via_bridge`（`:2664-2665`）、`default_gem?`（`:2688-2689`）、`installed_gem_dir` 的 default-gem 分支（`src/celerite/cli/commands_surface.cr:1749`）全部被跳过。

后果：`M8-batch-bridge.md` 的计数（check 6 进程/8 RPC 等）是在 `bridge_available? == true` 的探针配置下取得；plain 环境的真实计数不同（`check` 只剩 `:1570` 的 `validate_runtime!` 一次 spawn，`list` 因 `:1769` 无 gate 仍有 1–2 次）。`spec/m7_list_groups_plain_env_spec.cr` 的文件名表明 plain 环境的 list 组行为已被 spec 覆盖，但本文未读其内容，覆盖范围未验证。**这是本任务实测数字与代码读解之间最大的一处不一致，须以 HEAD 实测收口（本文未做，见 §7）；收口可复用 `spec/m8_bridge_stats_spec.cr` 的计数设施。**

## 2. 「不启动 Ruby」需要哪些数据

通用底座（三条命令共用）：

| 数据 | 现在从哪读 | 还差什么 |
| --- | --- | --- |
| 锁定 spec 集合（name/version/platform/deps） | lockfile `specs` 段，`src/celerite/cli/commands.cr:2111`（`lockfile.specs`）、`:2705`（反向依赖取自 lockfile specs） | 无。lockfile 已含每个 spec 的依赖列表 |
| Gemfile 依赖（名称+需求） | 只能经求值：`:2731` `evaluate_gemfile`；`src/celerite/bridge/client.cr:216` 的 `gemfile_sha256` 无消费者 | 无 Ruby 时只能读 lockfile `DEPENDENCIES` 段（它是求值结果之一），或读 task-222 的缓存 |
| 组归属（gem → groups） | 只能经求值：`:2728-2743` `lockfile_groups`、`:2745` `gem_groups_for` | lockfile **不存**组归属；缓存之外无来源 |
| 本机平台 | `src/celerite/gem/platform.cr:96-118`（`CELERITE_LOCAL_PLATFORM` 覆盖，Windows 取 `PROCESSOR_ARCHITECTURE`） | 已足够（不需要 Ruby）。但与 `Gem::Platform.local` 的等价性只在差分用例覆盖 |
| ruby 版本/engine/ABI | 只能经桥：`:281-282`、`:299`、`:3078`；`src/celerite/ruby_runtime.cr:8-19` 消费 `ruby_environment` | 缓存时须记录 ruby 可执行文件路径/版本/ABI，且以"变化即失效"为唯一失效信号 |
| 配置（frozen/with/without/checksum） | `.bundle/config` + `BUNDLE_*`，`src/celerite/definition.cr`（config 读取）+ `:2760` `requested_groups_for` | 需纳入指纹（文件哈希 + 相关 ENV 名/value 摘要） |

逐命令缺口：

- `lock`（无变化）：缺"Gemfile 未变"的证明。`lockfile_matches_dependencies?`（`src/celerite/definition.cr:182`）与 `dependency_sources_changed?`（`:348`）都吃 `Bridge::EvaluatedDependency`/`EvaluatedSource`，无求值即不可比。→ 需 task-222 指纹（文件闭包 + 求值摘要），或退化为"只比 lockfile `DEPENDENCIES` 段"（弱判据，见 R3）。
- `check`：缺组归属（仅 `BUNDLE_WITHOUT` 非空时需要）、ruby 指令比对（Gemfile `ruby` 行需求值）、checksum 策略（lockfile `CHECKSUMS` 段 + config，已可读）。缺失判定（`:1723-1731`）与平台判定（`:2941`）不需 Ruby。
- `list`（无组过滤）：不缺（`:1849` `lockfile.specs.sort_by(&.full_name)`）。但排序键与参考不同（`ref:cli/list.rb:29` 是 `sort_by(&:name)`）：同一个 gem 有多个平台条目时，两者的相对次序可能不同——需 fixture 收口，`spec/m7_list_format_spec.cr`、`spec/m7_show_order_spec.cr` 是现成回归面。
- `list`/`show`（组过滤）：缺组归属缓存；`:2790` 的"组相同则跳过"也必须用缓存，否则每次多一次 spawn。
- `show`（非 verbose）：不缺路径与依赖；verbose 的 Summary/Homepage 有 `:2640` 兜底，但 executables 无兜底。
- `pristine`：缺 `InstallPaths.ruby_abi`（`:3078`）的离线来源与 `full_gem_path` 的推导（可 glob `<install_path>/ruby/*/gems/<full_name>`，多 ABI 时不确定）。
- `binstubs`：缺 gemspec `executables`/`bindir` 的离线来源；`Gem::Specification.load` 是 Ruby DSL，文本解析不可行（除缓存）。
- `install`（无变化）：输出 `Bundle complete! N Gemfile dependencies, M gems now installed` 的 N 可取自 lockfile `DEPENDENCIES` 条数；缺的是"全部已装 + 无 plugin + 无未 checkout 的 git/path 源 + frozen 一致"的合并判定，以及 `Bundler.load.cache` 副作用是否要复刻（`ref:cli/install.rb:53`）。
- `exec`：缺 ruby 版本校验的等价时机。参考侧 `ref:cli/exec.rb:18` 不读 Gemfile，但子进程加载 `bundler/setup` 时仍会校验；我方把校验前移（`:1772`），去掉即改变错误出现的进程与退出码归属。**未验证**。

## 3. 参考行为一致性风险清单

| # | 漂移点 | 参考在哪算出来 | 静默降级的具体后果 |
| --- | --- | --- | --- |
| R1 | `check` 的满足判据与文案 | `ref:cli/check.rb:18-25`（`check!` + `missing_specs`，SolveFailure → 两行文案 + exit 1）、`:27-31`（逐 gem `* name (version)`）、`:33`（`definition.lock(true)` **写锁**）、`:34`（成功文案） | 现状已实测：桥不可用时 `check` **exit 0** 并打印 `The Gemfile's dependencies are satisfied`（`M8-batch-bridge.md`）。快路径若沿用 `rescue → 默认值`，会把"无法证明"输出成"已满足" |
| R2 | `list` 的组归属与顺序 | `ref:cli/list.rb:73-77`（未知组文案 + exit）、`:79-95`（`definition.groups` → `specs_for`）、`:29`（`reject bundler` + `sort_by(&:name)`）、`:61-70` | 现状 `lockfile_groups` 的 `rescue → [] of String`（`:2738-2739`）使 `all_groups` 退化为 `["default"]`；实测 `list` 在桥故障时 **exit 0** 并正常列出。缓存 stale 会让 `--only-group` 的 exit 15 与真组选择同时错 |
| R3 | `lock` 的"不改写"判定与 `BUNDLED WITH` | `ref:cli/lock.rb:45`（无条件求值）、`ref:definition.rb:630-645`（13 个变更位）、`:647-649`、`:655-659`；`BUNDLED WITH` 写入见 `ref:cli/lock.rb:92-93` | 我方短路条件（`:3085-3090`）用同一批比较。若以缓存替代求值且缓存失配未判出，会静默跳过重解析：写旧锁、漏报 frozen 冲突、`BUNDLED WITH` 取到旧 bundler 版本（`:3097` 用 `resolution.bridge_bundler_version`） |
| R4 | `check`/`show` 的 frozen 分支 | `ref:definition.rb:475-492`（`Frozen mode is set, but there's no lockfile`；`lockfile_changes_summary`；非显式 flag 追加 `bundle config set frozen false` 提示）、`ref:cli/check.rb:15`、`ref:cli/show.rb:14-17`（show/info **不**跑 frozen 检查，只写锁） | 我方 `:1647-1656` 只在 `check` 抛 ProductionError；`:2104-2108` 注释确认 show/info 不走该检查。快路径若省略求值，"锁与 Gemfile 不一致"无法被发现，frozen 冲突静默通过 |
| R5 | `show` 的依赖/可执行文件 | `ref:cli/info.rb:76`（`definition.specs.filter_map` 依赖）、`ref:cli/show.rb:41-48`（verbose 输出 Summary/Homepage/Status） | 依赖可取自 lockfile specs；`executables` 无来源，`:2640` 的文本兜底只覆盖 summary/homepage/metadata。快路径下 `binstubs` 会输出"no executables"（`src/celerite/cli/commands_install.cr:2252`）而参考会生成 stub |
| R6 | `install` 的完成文案与缓存副作用 | `ref:cli/install.rb:50-53`；`ref:runtime.rb:102`（`lock(preserve_unknown_sections: true)`） | 无变化时参考仍 `Bundler.load.cache` 与写锁；我方快路径若只打印文案，`.bundle/cache` 与锁文件的 mtime/内容可能不同（`lockfile` 不改写的判定见 R3） |
| R7 | `pristine` 的 git/path 分支 | `ref:cli/pristine.rb:33-50`（`Cannot pristine <gem>. Gem is locally overridden.` / `... is sourced from local path.`） | 我方 `:3116-3133` 已有同文案；无 Ruby 时若靠 lockfile `GIT`/`PATH` 段分类则等价，但 `extension_dir`/`full_gem_path` 的删除目标需 ABI，缺失会误删或漏删 |
| R8 | `exec` 的错误时机 | `ref:cli/exec.rb:18`（不读 Gemfile）；`ref:definition.rb:499-522`（`RubyVersionMismatch`）、`:524-530`（平台文案） | 我方 `:1772` 前移校验：去掉后 ruby 版本不匹配的报错由子进程抛出，退出码与 stderr 归属变化 |

### 3.1 已有的静默降级（快路径不能继承）

四处，均把"未知"折叠成"无事发生"：

1. `lockfile_groups`：`src/celerite/cli/commands.cr:2728-2743`，`rescue → [] of String`（`:2738-2739`）。实测：桥故障 → `list` exit 0、`check` exit 0 且打印成功文案。
2. `show` 的组过滤：`:2112-2116`，`rescue → sorted_specs`（退化为不过滤）。
3. `validate_runtime!`：`:1365-1385`，非 `RubyVersionMismatch`/`ProductionError` 的异常被 `:1380-1385` 吞成 `nil`。
4. `installed_gem_dir` 的 default-gem 分支：`src/celerite/cli/commands_surface.cr:1749-1761`，桥不可用即跳过解释器 default gem 探测（可能把 default gem 判为未安装）。

**为什么快路径不能继承**：快路径的语义是"我已证明无变化"，降级的语义是"我不知道，但我继续"。两者在 exit 0 上不可区分，于是 roadmap:168 的"Ruby 启动次数为零"可以在判据未成立时也判达标——这正是 `docs/roadmap.md` 与 `AGENTS.md`（"不将空实现或未测的兼容声明标记为完成"）禁止的形状。快路径必须满足：判据不成立 → 显式走兼容路径（启动 Ruby），而不是折叠成默认值。

## 4. 「指纹不确定」的边界

快路径的前置是"能证明这次输入与上次求值等价"。以下五类信号任一出现，必须判不确定并走兼容路径（宁可多起一次 Ruby）：

1. **动态 DSL**：`eval_gemfile`（被引用文件进入文件闭包）、`gemspec`（`.gemspec` 本身是 Ruby，且可 `git ls-files` 动态生成 files）、`if`/`case` 条件分支、`source ... do` 内的 `ENV[...]` 插值。现有 `GemfileEvaluation.gemfile_sha256`（`src/celerite/bridge/client.cr:216`，服务端 `assets/bridge/server.rb:214`）只覆盖 Gemfile 单文件且**无消费者**，不足以表达闭包。
2. **插件**：`.bundle/plugin` 存在（`PluginGemfile.enabled?`，`src/celerite/cli/commands_install.cr:260-264`）即判不确定——插件 hook 会改 Gemfile 求值结果（服务端 op `op_exec_plugin_hook`、`op_plugin_gemfile_eval`）。
3. **`.bundle/config` 变化**：`BUNDLE_FROZEN`、`BUNDLE_WITH`/`WITHOUT`、`BUNDLE_PATH`、`BUNDLE_CHECKSUM`、`BUNDLE_DEPLOYMENT` 都改变判定或输出。指纹须含配置文件内容哈希 + CLI 相关 `BUNDLE_*` 环境变量摘要。
4. **ruby 运行时身份**：Ruby 可执行文件换版本/换 ABI 后，`Platform.local` 不变但 `ruby_environment.platform`、ABI 目录与 `ruby` 指令校验结果会变。无 Ruby 时无法探测，只能以"缓存记录的 ruby 路径 + 版本 + ABI"为失效锚，且路径 mtime 不可靠（重新安装）——须标为已知残余风险。
5. **锁与 Gemfile 一致性检查成本**：无 Ruby 时只能比 lockfile `DEPENDENCIES` 段与缓存摘要，成本 O(deps) 字符串比较（毫秒级），**不能**覆盖"Gemfile 里改了 requirement 但 lockfile 恰好同一行"的情形（弱判据）。因此快路径的判据强度必须写进兼容声明：`check` 的零 Ruby 快路径只能声明"已装 + 平台 + 锁内容未变"，不能声明"已验 Gemfile 与锁等价"。

## 5. 实施顺序与最小可用切片

顺序原则：先做**不依赖 task-222** 的（S1→S2→S5），再做依赖指纹的（S3→S4）。每片独立可验收、独立回滚。

**S1（无依赖）已装判定全链路去桥**
- 目标：让 `installed_spec_dir?`/`installed_gem_dir` 在无桥时对 default gem 与系统 gem 给出与桥等价的结果。
- 改动面：`src/celerite/cli/commands_surface.cr:1676-1763`（`:1738-1744` 兜底、`:1749-1761` 桥分支）、`src/celerite/cli/commands.cr:2688-2693`（`default_gem?`）。
- 判据形状：同一 fixture 下"有桥/无桥"两次 `bundle check`、`bundle show GEM` 的 stdout+exit 完全一致；`CELERITE_BRIDGE_STATS=1` 下无桥运行 spawn 数为 0。
- 回归面：`spec/m7_installed_discovery_spec.cr`、`spec/m7_default_gem_spec.cr`、`spec/m7_default_gem_origin_spec.cr`、`spec/m7_check_missing_dependency_spec.cr`、`spec/m7_show_listing_spec.cr`；不涉及 resolution。

**S2（无依赖，接 S1）`check` 窄快路径**
- 目标：`check` 在 lockfile 存在、无 `BUNDLE_WITHOUT`、无 `ruby` 指令、无 frozen 冲突可疑时，只用 lockfile + 文件系统 + `Platform.local` 完成判定，0 spawn。
- 改动面：`src/celerite/cli/commands.cr:1444`（入口）、`:1570`（`validate_runtime!` 后移/条件化）、`:1618`/`:1623`（组过滤改为"有缓存才过滤，否则显式兼容"）、`:1665-1693`（PATH 漂移 probe 属 Ruby 侧，快路径须跳过并记录"未验证"而非静默）。
- 判据形状：4 类 fixture（已满足 / 缺 gem / 平台不符 / ruby 不符）的 stdout 逐字 + exit code；spin 计数 0（前三类）与 1+（ruby 不符类必须仍能报 18）。
- 回归面：`spec/m7_check_rewrite_spec.cr`、`spec/m7_check_missing_dependency_spec.cr`、`spec/m7_check_no_lockfile_spec.cr`、`spec/m7_check_ruby_notice_spec.cr`、`spec/m7_frozen_lock_validation_spec.cr`、`spec/m7_platform_validation_spec.cr`、`spec/m7_list_groups_plain_env_spec.cr`。

**S5（无依赖，接 S2）`lock` 短路前移**
- 目标：把 `Resolution.new`（`:3054`）推到短路判定之后，短路时 0 spawn 且不写盘。
- 改动面：`src/celerite/cli/commands.cr:3047-3110`；`:3097` 的 `BUNDLED WITH` 需在短路时保留锁文件原值（避免以 `resolution.bridge_bundler_version` 覆盖）。
- 判据形状：`lock`（无变化）锁文件字节不变、stdout 为空、spawn 0；`lock --print`（无变化）stdout 等于锁文件正文、spawn 0；所有 forcing flag 仍走兼容路径（spawn ≥1，输出与今天一致）。
- 回归面：`spec/m7_lock_rewrite_fidelity_spec.cr`、`spec/m7_lockfile_regen_spec.cr`、`spec/m7_lock_options_spec.cr`、`spec/m7_frozen_ruby_unlock_spec.cr`、`spec/m7_check_rewrite_spec.cr`。
- 注：短路仍需 `lockfile_matches_dependencies?` 的输入。无缓存时此片只能做到"少一次求值"，不能做到 0 spawn ——**因此 S5 的零 spawn 形态实际依赖 S3 的缓存**；先落地"前移 + 兼容路径"，零 spawn 作为 S3 的验收项。

**S3（依赖 task-222）求值缓存与组归属**
- 目标：缓存 `{gemfile 指纹 → deps、sources、gem→groups、ruby 指令}`，供 `list`/`show`/`check`/`lock` 共用；指纹按 §4 的保守规则判定不确定。
- 改动面：新缓存读写点 + `src/celerite/cli/commands.cr:2728-2743`（`lockfile_groups` 加缓存层）、`:1769-1778`、`:2784-2791`。
- 判据形状：`list --only-group`/`--without-group`/`BUNDLE_WITHOUT` 组合的 stdout+exit；未知组 exit 15；缓存命中时 spawn 0、失配时 spawn 与今天一致；指纹不确定（DSL/插件/ENV）时强制 spawn。
- 回归面：`spec/m7_list_groups_plain_env_spec.cr`、`spec/m7_only_group_spec.cr`、`spec/m7_show_group_filter_spec.cr`、`spec/m7_gemfile_plugins_spec.cr`。

**S4（依赖 S1+S3）`install` 无变化快路径**
- 目标：锁文件当前 + 全部已装 + 无 plugin + 无未 checkout 的 git/path 源 → 打印 `Bundle complete! N Gemfile dependencies, M gems now installed`，0 spawn。
- 改动面：`src/celerite/cli/commands_install.cr:260-308`（把桥构造与求值移到判定之后）。
- 判据形状：stdout 逐字、exit 0、spawn 0、锁文件与 `.bundle/cache` 状态与参考一致；有缺 gem / 有 plugin / git 源变化时回落到今天的路径（spawn ≥1）。
- 回归面：`spec/m7_install_after_lock_keeps_transitive_spec.cr`、`spec/m7_install_without_spec.cr`、`spec/m7_local_install_spec.cr`、`spec/m7_frozen_source_normalization_spec.cr`、`spec/m7_path_source_missing_gem_spec.cr`、`spec/m7_plugin_hook_all_events_spec.cr`。

依赖图：`S1 → S2 → S5(前移) → S3 → S4`；`S3` 的前置是 task-222（指纹）；`S5` 的零 spawn 验收点落在 `S3` 之后。

## 6. 本机不可验证项

- **Rails 规模**：仓库内无 Railties 量级 fixture；100+ gem 时快路径判定的耗时与缓存体积未测。
- **YJIT / 解释器差异**：只装了 4.0.24 一个参考；YJIT 开关改变 `ruby_environment` 的取值形状未测。
- **Linux / macOS**：`Platform.local` 的 `uname` 分支（`src/celerite/gem/platform.cr:112-116`）与 `ruby_abi` 目录形态未在本机跑过。
- **多 ABI / 多解释器共存**：`<install_path>/ruby/*` 出现多个 ABI 时，`pristine`/`binstubs` 的目标推导未测（推测需以缓存记录 ABI，否则须回退兼容路径）。
- **真网络**：无变化场景本不该联网，但 `--verbose`/`--outdated`/`--add-checksums` 会；离线行为未测。
- **进程计数**：HEAD `9098d29` 无 `bin/celerite.exe`（本章节所有"spawn 数"来自 `M8-batch-bridge.md` 在 `3fd7a8d` 的探针测量，属转引）。

## 7. 未验证与待收口

- [未验证] HEAD `9098d29` 上各命令的真实 ruby spawn 数（未构建二进制）。特别是 `bridge_available? == false` 的 plain 环境：`check` 应只剩 `:1570` 一次 spawn，`list` 因 `:1769` 无 gate 仍有 1–2 次。此推断与 `M8-batch-bridge.md` 的计数不同，须实测收口，否则矩阵的"现状"列只有代码读解支撑。
- [未验证] `exec` 在参考侧是否真的不求值 Gemfile（`ref:cli/exec.rb` 只读了 `initialize`/`run`，未追 `CLI` 分派层是否先建 `Bundler.definition`）。
- [未验证] `lock --add-platform <已在锁中的平台>` 的参考是否跳过解析：`ref:definition.rb:538-543` 的 `add_platform` 在已存在时直接 return，理论上 `resolve_needed?` 为假；我方 `:3086` 无条件把该 flag 排除出短路，可能多解析一次（推测：行为差异在输出上体现为多一行 `Resolving dependencies...`）。
- [未验证] `install` 无变化时参考是否仍写 `vendor/cache`（`ref:cli/install.rb:53` → `Bundler.load.cache`，其写入条件未追到 `runtime.rb` 之外）。
- [未验证] 组归属缓存与本机 `BUNDLE_WITH`/`WITHOUT` 交互下的 `specs_for` 顺序（`ref:cli/list.rb:94` 之后未再排序，顺序取决于 lockfile specs 顺序）。
- 已知未做：未跑 `script/differential`（端口 8765 被占），未构建，未改 `src/`。

### 1.2 首辅实测（2026-11-24，HEAD `9098d29`，plain 环境）

上面 §1.1 的推断（"plain 环境下 check 只剩 1 次 spawn、list 1–2 次"）**未被实测支持**，实测与之不同，以此表为准：

配方：`C:\temp\celerite-t219\bin\celerite.exe`（构建自 `9098d29`），临时项目 `C:\temp\m8-measure2`，Gemfile = `source "file:///<repo>/fixtures/gem-index"` + `gem "thor"`，隔离 `HOME`/`USERPROFILE`/`BUNDLE_PATH`，**不设** `CELERITE_BRIDGE_SERVER` 与 `CELERITE_REFERENCE_BUNDLER_LIB`（即 plain 环境），`CELERITE_BRIDGE_STATS=1`，退出码与计数行分别取自 `Start-Process` 的 `ExitCode` 与 stderr。

| 命令 | 场景 | exit | procs | rpc | req_bytes | resp_bytes |
| --- | --- | --- | --- | --- | --- | --- |
| `lock` | 冷（无锁、file 源） | 0 | 1 | 6 | 397 | 288102 |
| `check` | 安装前（缺 gem） | 1 | 2 | 3 | 252 | 2529 |
| `install` | 首装 | 0 | 2 | 25 | 3429 | 299114 |
| `install` | 无变化重跑 | 0 | 2 | 18 | 1943 | 295607 |
| `list` | 已安装 | 0 | 2 | 2 | 196 | 1468 |
| `show thor` | 已安装 | 0 | 3 | 4 | 350 | 3263 |
| `lock` | 无变化 | 0 | 1 | 2 | 174 | 855 |

与 §1.1 的差异：`check` 实测 **2** 个进程（不是 1），`list` 实测 **2** 个（不是 1–2 的下界）。结论：`bridge_available?` 只 gate 特定分支的输出/兜底（`:2664-2665`、`:2688-2689`、`commands_surface.cr:1749`），**并不 gate 主 spawn 路径**，故 plain 与探针环境的进程数量级接近；§1.1 后半段的"须以 HEAD 实测收口"已由本表收口，但两张表的夹具不同（本节 1 依赖、`file://` 源；`M8-batch-bridge.md` 是 1 依赖、`BUNDLE_PATH` 双进程实测），**跨表不可逐格相减**。

仍未验证：探针环境（设 `CELERITE_BRIDGE_SERVER`）在同一夹具下的同表数字；`check` 成功路径（安装后）的计数；Rails 规模。
