# M8 求值指纹：输入清单与设计（task-222）

- 性质：**只读调研**。未修改 `src/`、`spec/`、`script/`；唯一写入文件是本文件。
- 基线：detached HEAD `9098d29`，调研前 `git status --porcelain` 为空。
- 参考实现：`C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\lib\bundler\`（下文简写 `bundler/...`）。2.7.x 未用作依据。
- 方法：读 `dsl.rb`、`ruby_dsl.rb`、`ruby_version.rb`、`settings.rb`、`plugin.rb`、`definition.rb`、`source/path.rb`、`source/git.rb`、`bundler.rb`；用 grep 穷举 `ENV["BUNDLE_*`/`@env_config[` 的读取点（不靠猜）。我方一侧用 grep + read 定位到行。
- roadmap 依据：`docs/roadmap.md:162`（求值指纹的六类输入 + 「任一输入变化必须使缓存失效，不使用内容哈希代替完整环境指纹」）、`docs/roadmap.md:165`（持久化缓存键：source 身份、凭据隔离标识、checksum、平台、Ruby ABI、build 配置）。

## 0. 结论速览

- 输入清单 **22 项**：我方**已具备 8 项**、**部分具备 7 项**、**完全缺失 7 项**。已具备的 8 项集中在「身份与运行时环境」（Gemfile 路径、lockfile 路径、Ruby/引擎/补丁级、Bundler profile、平台、RubyGems 版本字段、配置目录解析、`plugins` 门控）；缺失的 7 项集中在「求值**内容**边界」（`eval_gemfile` 递归链、`ruby file:`、path/git 的 gemspec、gemspec 求值副作用、Gemfile 体内任意 Ruby、plugin 根、eval 指纹本身）。
- 更关键的是：全仓 `gemfile_sha256` **只有生产端与声明端，没有任何消费者**（`src/celerite/bridge/client.cr:265` 声明、`assets/bridge/server.rb:214` 生产）。也就是说现状连「用 Gemfile 内容哈希当键」这一步都没做——**没有任何求值缓存**，每次构造 `Resolution` 都重求值（`src/celerite/resolution.cr:326-340` → `:381-383`）。
- 参考侧同样没有跨进程求值缓存：`bundler.rb:229-235` `@definition ||= ...` 只在**单个 Ruby 进程内** memoize。因此「求值指纹 + 缓存」是 Celerite 新增能力，正确性必须靠差分证明，不能靠「Bundler 也这么做」背书。
- 三条最容易漏的输入：
  1. **`gemspec` DSL 的 glob 与 path/git 不同**：`gemspec` 用固定 `{,*}.gemspec`（`bundler/dsl.rb:71`），path/git source 用 `{,*,*/*}.gemspec`（`bundler/source/path.rb:14`，`git.rb:15` 继承）或 `glob:` 选项。漏掉这一层会以为「gemspec 都在根目录」。
  2. **插件根与插件索引**：`Bundler::Plugin.root` 在项目内取 `app_config_path/plugin`（`bundler/plugin.rb:138-148`），随 `BUNDLE_APP_CONFIG` 移动；`source "...", type: :x` 是否合法、`Plugin::Source` 是否存在，取决于该目录下的索引与已装插件（`bundler/dsl.rb:129-133`、`plugin.rb:245-247`）。同一份 Gemfile 在「装过插件 / 没装过插件」两种状态下求值结果不同。
  3. **`ruby file:` 的间接输入**：`bundler/ruby_dsl.rb:43-66` 读 `gemfile.dirname/.ruby-version`、`.tool-versions` 并写入求值结果；Gemfile 文本一字不变，输入却变了。

## 1. 逐项输入清单

判定口径：
- **具备** = 我方已有该数据且在正确语义下取得（可能尚未接入指纹）。
- **部分** = 有相关数据/实现，但覆盖不完整（缺一条路径、缺一个字段、或只覆盖解析不覆盖求值）。
- **缺失** = 我方没有任何对应读取。

### A. Gemfile 与其递归链

| # | 输入 | 参考锚点 | 我方现状 | 判定 |
|---|---|---|---|---|
| A1 | Gemfile 路径决议：`BUNDLE_GEMFILE` → 逐级向上找 `Gemfile`/`gems.rb` → 配置 `gemfile` 键 | `bundler/shared_helpers.rb:263-264`；`settings.rb:59-77`（`STRING_KEYS` 含 `gemfile`）；`bundler.rb:442` | `src/celerite/definition.cr:56-63` 只认 `ENV["BUNDLE_GEMFILE"]?` + `search_up("Gemfile")`/`gems.rb`，**不读配置 `gemfile` 键** | 部分 |
| A2 | Gemfile 原始字节内容 | `bundler.rb:499-503`（`File.open(file,"r:UTF-8",&:read)`，即按字节读、不做行尾归一） | `assets/bridge/server.rb:183` 读内容；`:214` 算 `Digest::SHA256.hexdigest(contents)`；`src/celerite/bridge/client.cr:265` 收下但**无消费者** | 部分 |
| A3 | `eval_gemfile` 递归链（嵌套 Gemfile 的绝对路径清单） | `bundler/dsl.rb:41`（`@gemfiles`）、`:46-61`（`eval_gemfile`）、`:329-337`（`with_gemfile`，相对基准 = **当前 Gemfile 的父目录**）、`:333`（入链） | `assets/bridge/server.rb:174-223` **未序列化 `@gemfiles`**，`GemfileEvaluation` 也无对应字段（`client.cr:254-269`） | 缺失 |
| A4 | `ruby file:` / `ruby file: ".tool-versions"` 指向的文件内容 | `bundler/ruby_dsl.rb:43-66` | 无 | 缺失 |
| A5 | 运行期 Ruby 侧「Gemfile 体内任意 Ruby」：`ENV[...]`、`File.read`、`require`、网络、`system` | `bundler/dsl.rb:52`（`instance_eval(contents, current_gemfile, 1)`） | `assets/bridge/server.rb:184` 同样 `instance_eval`；无标记、无沙箱、无降级策略 | 缺失 |

A5 是**不可静态判定**的根源：Gemfile 是可执行 Ruby，任何「白名单 + 内容哈希」在这类 Gemfile 上都不完备。指纹设计必须给出「不确定就整体失效 / 拒绝缓存」的显式分支，而不是假设 Gemfile 只用了 DSL 方法。

### B. 被引用的 gemspec

| # | 输入 | 参考锚点 | 我方现状 | 判定 |
|---|---|---|---|---|
| B1 | `gemspec` DSL 立即求值的 gemspec 文件（glob 固定 `{,*}.gemspec`，可 `name:`/`path:` 收窄） | `bundler/dsl.rb:63-99`：`:69` `gemfile_root.join(path)`、`:71` glob、`:80` `@gemspecs <<`、`:82` `path path, "glob"=>glob, ...`、`:94` 无 gemspec 报错、`:95-97` 多组合法性 | `assets/bridge/server.rb:227-238` 的 `op_gemspec_paths` 单独再 eval 一次并返回 `loaded_from`；结果只给 `env`/`issue` 展示用（`src/celerite/cli/commands_surface.cr:1275-1279`），**不进求值结果、不参与任何键** | 部分 |
| B2 | `path:` / `git:` source 的 gemspec（默认 `{,*,*/*}.gemspec`，或 `glob:` 覆盖；浅层覆盖深层） | `bundler/source/path.rb:14`、`:19`、`:159-179`（`:163` 注释「sort depth-first，`<<` 覆盖先找到的」）；`bundler/source/git.rb:15`；`bundler/source/gemspec.rb:11` | 解析侧已有 glob 与默认值（`spec/m7_path_glob_default_spec.cr`、`spec/m7_git_source_glob_spec.cr` 覆盖），但**求值指纹不记录**该集合与其内容 | 缺失 |
| B3 | gemspec 求值副作用：以**gemspec 自身目录为 cwd** 执行，可读任意相对文件与 ENV；进程内 `@gemspec_cache` 以绝对路径为键 | `bundler.rb:642-666`（`:650` `chdir(path.dirname)`、`:659` `eval`）；`bundler.rb:518-535`（缓存键 `File.expand_path(file)`、返回 `dup`） | 未建模；`assets/bridge/server.rb` 未隔离 cwd 语义，也未把「gemspec 读了哪些文件」纳入输入 | 缺失 |

B1/B2/B3 合起来说明：**gemspec 是「二级可执行输入」**。它既不是纯数据（内容哈希不够，因为它能读 ENV 与相对文件），也不是纯代码（改了它必须失效）。失效语义必须对它两层都覆盖：内容哈希 + cwd 语义说明 + 「未识别的副作用」降级路径。

### C. ENV：方法而非猜测

取证方法：`grep -rn 'ENV\["BUNDLE_'` + `ENV.fetch("BUNDLE_` + `@env_config\[`，覆盖整个 `bundler/`。命中只有 19 处，分布在 7 个文件。据此可以把「求值期真正影响结果的 ENV」与「只影响安装/下载的 ENV」分开：

| # | ENV 键 | 参考锚点 | 是否改变求值结果 | 我方现状 | 判定 |
|---|---|---|---|---|---|
| C1 | `BUNDLE_GEMFILE` | `shared_helpers.rb:263-264`、`inline.rb:46-47` | **改变「读哪个文件」**（输入身份，不是键值） | `definition.cr:56-63` | 具备 |
| C2 | `BUNDLE_LOCKFILE` | `shared_helpers.rb:25-35`、`cli.rb:71`、`cli/lock.rb:84` | 只改 lockfile 位置，**不改 DSL 求值结果** | `definition.cr:77-89` | 具备（且**不应**进指纹） |
| C3 | `BUNDLE_IGNORE_CONFIG` | `settings.rb:300-302` | **改变**：忽略全部配置文件后 `plugins`/`path` 回到默认，间接改变求值 | `config.cr:135-156` | 具备 |
| C4 | `BUNDLE_APP_CONFIG` | 经 `settings.rb:94-107` 收进 `@env_config`；实际消费在 `bundler.rb:355`、`plugin.rb:146-148` | **改变**：项目配置目录 + 插件根位置 | `config.cr:121-133`（配置目录） | 部分（未接插件根） |
| C5 | `BUNDLE_CONFIG` / `BUNDLE_USER_CONFIG` / `BUNDLE_USER_HOME` | `settings.rb:464-474` | **改变**：全局配置来源 | `config.cr:314-322` | 具备 |
| C6 | `BUNDLE_PLUGINS`（`settings[:plugins]`） | `settings.rb:39` 键表；门控见 `cli.rb:158`、`cli/install.rb:41`、`cli/update.rb:18`、`plugin.rb:229`、`inline.rb:56` | **改变**：`source type:` 插件 source 与 hook 是否可用 | `plugin_gemfile.cr:16-18` | 具备 |
| C7 | `BUNDLE_PATH` / `BUNDLE_WITHOUT` / `BUNDLE_ONLY` / `BUNDLE_FROZEN` / `BUNDLE_DEPLOYMENT` | `definition.rb:1252-1253`（`groups - without - optional + with`、`& only`）、`bundler.rb:237-242`（frozen/deployment） | **不改变 DSL 求值结果**：分组过滤与 frozen 判定发生在 `Definition` 建成之后 | `config.cr:14-27` 已有键 | 具备，但**必须标为「非求值输入」** |
| C8 | `BUNDLE_FORCE_RUBY_PLATFORM` | `settings.rb:33`；消费点 `definition.rb:662`、`lazy_specification.rb:221` | **不改变** DSL 求值结果，但改变候选平台集合 | `config.cr:23` 有键；`resolution.cr:2362`、`:2610` 有分支 | 具备，归入「分区失效」 |
| C9 | `BUNDLE_GEMFILE` 之外的任意 ENV（由 Gemfile/gemspec 正文读取） | 不在 Bundler 内，属用户代码 | **可改变**，且不可枚举 | 无追踪 | 缺失（不可穷举，须策略兜底） |

由此得出的第一类误用风险：把 `BUNDLE_WITHOUT`/`BUNDLE_ONLY`/`BUNDLE_FROZEN`/`BUNDLE_LOCKFILE` 当求值输入 → 每次 `--without` 都要重求值，缓存命中率归零，还会让「同一求值结果」被误判为不同。反过来，把它们当作**同一指纹下的不同视图**，需要解析阶段（不是求值阶段）分区。第二类误用风险：只把 `BUNDLE_GEMFILE` 当一个值哈希，忽略它指向的**文件身份**（同一路径被替换内容 / 同一内容出现在两个路径）——路径与内容必须两字段并存。

### D. 配置文件中真正参与求值的键

| # | 输入 | 参考锚点 | 我方现状 | 判定 |
|---|---|---|---|---|
| D1 | 项目 `.bundle/config` + 全局 `~/.bundle/config`，其中**求值相关**键：`plugins`、`gemfile`、`path`（仅因插件根与 `in_bundle?` 分支）、`force_ruby_platform`（解析分区） | `settings.rb:9-42`（`BOOL_KEYS`）、`:59-77`（`STRING_KEYS`）；`definition.rb:662`；`plugin.rb:146-148` | `config.cr` 有完整键表与加载（`config.cr:29-43`、`:347+`），但**没有「哪些键进求值指纹」的分类** | 部分 |

`with`/`without`/`only`/`frozen`/`deployment`/`cache_path`/`jobs`/`retry`/`ssl_verify_mode` 等属安装与下载域，**不进求值指纹**。

### E. 运行时版本与 ABI

| # | 输入 | 参考锚点 | 我方现状 | 判定 |
|---|---|---|---|---|
| E1 | Ruby 版本 / 补丁级 / 引擎 / 引擎版本 | `ruby_version.rb:108-115`（`RUBY_ENGINE`、`Gem.ruby_version`、`RUBY_ENGINE_VERSION`、`RUBY_PATCHLEVEL`）；`ruby_dsl.rb:5-28` | `bridge/client.cr:254-269` 的 `GemfileEvaluation` 已有 `ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`；`server.rb:214-218` 填充 | 具备 |
| E2 | RubyGems 版本（`Gem::VERSION`；path source 会写入 `spec.installed_by_version`） | `source/path.rb:151`；`bundler.rb` 全线走 `Gem::*` | `bridge/client.cr:121-155` `RubyEnvironment#rubygems_version` 已有，但**未进入求值结果** | 部分 |
| E3 | Bundler profile 版本 | `bundler.rb:229-235`（参考自身即 profile）；我方对应 `src/celerite/profile.cr:9-25`、`server.rb:214-218` 的 `Bundler::VERSION` | 具备 | 具备 |
| E4 | 平台三元组 / host | `ruby_version.rb:77-83`（`host_cpu`-`host_vendor`-`host_os`）；`Gem::Platform.local` | `RubyEnvironment#platform`（`client.cr:121-155`）；`Gem::Platform.local` 多处（`resolution.cr:1122-1124`、`installer.cr:51-52`、`commands.cr:1298-1304`） | 具备 |
| E5 | ABI：`Gem.ruby_api_version`、`Gem.extension_api_version`；`ruby_scope` | `installer/standalone.rb:36`、`:43`、`:47`；`rubygems_ext.rb:404`（`extensions/<platform>/Gem.extension_api_version`）；`bundler.rb:254-256`（`"#{ruby_engine}/#{RbConfig::CONFIG["ruby_version"]}"`） | 我方以字符串推导近似：`InstallPaths.ruby_abi_for`（`src/celerite/resolution.cr:170-173`，注释 `:169` 声称 `<major>.<minor>.0`）；**全仓无 `ruby_api_version`/`extension_api_version` 读取**（grep 仅命中生成脚本模板 `commands_install.cr:1063-1071`） | 部分 |

E5 的风险：`<major>.<minor>.0` 对 MRI 恰好等于 `Gem.ruby_api_version`，但（a）不等于 `Gem.extension_api_version`（后者可能带 `-static` 等后缀，见我方自己的模板 `commands_install.cr:1069`），（b）非 MRI 引擎未验证。指纹里应显式写「ABI 来源 = derived」或改为问桥要真实常量。

### F. 插件与不可静态判定的形态

| # | 输入 | 参考锚点 | 我方现状 | 判定 |
|---|---|---|---|---|
| F1 | 插件索引与已装插件集合（`<app_config>/plugin/index`、`plugin_paths`） | `plugin.rb:130-153`、`:245-247`、`plugin/index.rb:105-106`、`:178`、`:191` | 无（我方 `PluginGemfile` 只读 Gemfile 文本与配置，`plugin_gemfile.cr:24-47`） | 缺失 |
| F2 | `source "...", type: :x` 依赖插件提供 source | `dsl.rb:119-145`（未知 type 直接报错）、`plugin/api/source.rb:317` | 有 typed source 的解析实现与 spec（`spec/m7_plugin_source_typed_spec.cr`、`spec/m7_typed_source_spec.cr`），但**求值指纹不含插件可用性** | 部分 |
| F3 | `bundler/inline`、`Gemfile` 内 `require`/`eval`/`system` 等使求值不可静态判定的形态 | `inline.rb:46-47`、`:95-103`；`dsl.rb:52` | 无检测、无降级 | 缺失 |

F 类与 A5 一起决定：指纹系统必须允许「本 Gemfile 不可缓存」这一显式结论。设计见 §2.3。

## 2. 失效语义

### 2.1 必须整体失效（同一指纹域内全灭）

任一变化都必须让**所有**以该指纹为键的缓存条目失效，且不得回落到「部分复用」：

1. `eval_gemfile` 递归链上任何一个文件的路径集合或内容变化（A2/A3）。
2. 任一被 `gemspec` DSL 立即求值的 gemspec 文件内容变化，或 glob 展开结果集合变化（B1）。
3. `ruby file:` 目标文件内容变化（A4）。
4. Ruby 版本/补丁级/引擎、`Gem::VERSION`、Bundler profile 版本、平台三元组、ABI 任一变化（E1-E5）。
5. `plugins` 门控状态、插件索引内容、插件集合任一变化（C6/F1）。
6. 求值相关配置键（D1）或 `BUNDLE_IGNORE_CONFIG`/`BUNDLE_APP_CONFIG`/`BUNDLE_CONFIG`/`BUNDLE_USER_CONFIG`/`BUNDLE_USER_HOME` 的值变化（C3-C5）。

理由：这些输入共同决定 `dependencies`、`sources`、`ruby` 约束这三样产出，而它们是**同一个整体**——`Definition.build` 的输入。分区复用这三样中的任意子集，等价于伪造一个 Bundler 从未见过的求值结果。

### 2.2 可分区失效（独立键段，不进求值指纹）

| 输入 | 分区键归属 | 参考依据 |
|---|---|---|
| `BUNDLE_LOCKFILE` | lockfile 段 | `shared_helpers.rb:25-35`、`cli.rb:71` |
| `with`/`without`/`only` | 视图段（求值后过滤） | `definition.rb:1252-1253` |
| `frozen`/`deployment` | 写入策略段 | `bundler.rb:237-242` |
| `force_ruby_platform` | 候选平台段 | `definition.rb:662` |
| `path`/`cache_path`/`jobs`/`retry`/`ssl_verify_mode`/`bin` | 安装与网络段 | `settings.rb:9-51` |
| path:/git: source 的 gemspec（B2） | 解析段（fetch 后才有内容） | `source/path.rb:159-179` |

B2 归解析段的代价必须写明：**path/git 的 gemspec 变了，求值缓存可以命中，但解析结果与 lockfile 必须失效**。这正是 `bundler/definition.rb:906-921` 把「gemspecs for path gems changed」「gemspecs for git local gems changed」列为 `lockfile_changed_reason` 的原因（该表共 12 条）。

### 2.3 不可静态判定时的策略

Gemfile/gemspec 是可执行 Ruby（A5/B3/F3）。建议三态：

- `Deterministic`：只观察到 DSL 方法调用与已知的 `ruby file:` 读取 → 指纹有效，可缓存。
- `Unknown`：观察到 `ENV[...]`、`File.*`、`require`、`eval`、`system`、`inline` 等 → 指纹降级为「本次求值结果不可缓存」（或只允许进程内复用，进程退出即弃）。
- `Broken`：求值抛错 → 不缓存任何东西（连负结果也不缓存，因为错误可能依赖 ENV）。

检测手段（不在本任务实现，只给形状）：对 `Dsl` 实例用 `TracePoint`/`method_missing` 钩子记录调用序列，或对源码做保守静态扫描后**标 Unknown 而非放行**。保守方向必须是「多失效」，绝不能「多命中」。

### 2.4 反例：为什么不得用 Gemfile 内容哈希代替完整环境指纹

**反例 1（同 Gemfile、不同 gemspec）**：项目 `Gemfile` 只有

```ruby
source "https://rubygems.org"
gemspec
```

`foo.gemspec` 里 `spec.add_development_dependency "rake", "13.0.6"` 改为 `"13.1.0"`。Gemfile 字节完全相同 → 内容哈希相同 → 误命中缓存 → 复用旧的 `dependencies` → 生成与参考不同的 Gemfile.lock（`Bundler::Definition` 会把 gemspec 的 dev deps 注入依赖图，`dsl.rb:88-92`）。参考侧每次重求值，不会读到旧结果。

**反例 2（同 Gemfile、不同 ABI/Ruby）**：同一份 Gemfile 在 Ruby 3.3.6 与 4.0.6 下求值。`ruby ">= 3.3"` 通过，但 `Gemfile.lock` 的 `RUBY VERSION`、平台集合、extension 目录（`rubygems_ext.rb:404` 用 `Gem.extension_api_version`）都不同；若用 Gemfile 内容哈希做键，两个环境会共用同一份求值结果与同一份持久化缓存，`install` 会按错误的 ABI 目录安装 native gem。Celerite 侧已有对应近似（`resolution.cr:170-173`），一旦缓存键不含它，就会把 3.3 与 4.0 混为一谈。

**反例 3（同 Gemfile、不同插件状态）**：Gemfile 含 `source "https://example.test", type: :my_plugin_source`。装了插件 → 求值成功；卸载插件 → 参考侧在 `dsl.rb:129-133` 抛 "No plugin sources available for …"。Gemfile 未变，缓存会给出「成功」的旧结果，掩盖真实错误。

**反例 4（同 Gemfile、`ruby file:` 变）**：`ruby file: ".ruby-version"`，文件从 `3.3.6` 改为 `4.0.6`。Gemfile 未变，求值结果中的 `ruby_version` 约束改变（`ruby_dsl.rb:43-66`）。

四个反例对应同一条判据：**指纹必须覆盖「求值期间读到的每一份输入」及其身份，而不是「主文件的内容哈希」**。

## 3. 指纹编码建议

### 3.1 形状

版本化、可读、确定性的一行一条：

```
celerite-eval-v1
gemfile.path=/abs/path/Gemfile
gemfile.sha256=<hex64>
evalchain=<n>
evalchain.0.path=/abs/path/Gemfile
evalchain.0.sha256=<hex64>
evalchain.1.path=/abs/path/sub/Gemfile.local
evalchain.1.sha256=<hex64>
gemspec=<n>
gemspec.0.path=/abs/path/foo.gemspec
gemspec.0.sha256=<hex64>
rubyfile=<0|1>
rubyfile.0.path=/abs/path/.ruby-version
rubyfile.0.sha256=<hex64>
ruby.version=4.0.6
ruby.patchlevel=0
ruby.engine=ruby
ruby.engine_version=4.0.6
rubygems.version=4.0.0
bundler.version=4.0.24
platform=x64-mingw-ucrt
abi.ruby_api_version=4.0.0
abi.extension_api_version=4.0.0
abi.source=derived
env.plugins=true
env.ignore_config=false
env.app_config=/abs/path/.bundle
config.digest=<hex64>
plugins.enabled=true
plugins.index.sha256=<hex64>
plugins.count=<n>
plugins.0.name=my_plugin
plugins.0.version=1.2.0
mode=deterministic
```

指纹值 = 对上述规范化文本整体做 SHA-256。字段顺序固定（按上表字面顺序），未知/不适用写 `-` 而不是省略——**省略会让「字段不存在」与「字段为空」不可区分**。

### 3.2 各字段规范化

| 字段族 | 规范化 | 理由 |
|---|---|---|
| 所有路径 | `File.expand_path`（绝对化）→ 分隔符统一为 `/`；**不做大小写折叠** | 折叠会在大小写敏感卷（WSL 挂载、开启 case sensitivity 的 NTFS 目录）上把两个不同文件并成一个 → 误命中。多路径指向同一树只会造成多余失效（安全方向） |
| 符号链接 | 只用 `expand_path`，不用 `realpath` | `realpath` 会让「换了一条软链但内容相同」不失效；且 realpath 依赖运行期目录状态 |
| 文件内容 | 对**原始字节**做 SHA-256（不做 CRLF 归一、不做编码转换） | 参考按 `r:UTF-8` 读字节（`bundler.rb:499-503`）；仓内已有行尾差异 spec（`spec/m7_lockfile_line_endings_spec.cr`）说明行尾是语义 |
| 目录 mtime / ctime / size | **不参与** | 目录 mtime 会因任何无关文件增删而变（编辑器临时文件、`.git` 操作）→ 失效风暴；`size` 会被「同长改写」骗过 |
| glob 展开结果 | 记录**排序后的绝对路径清单 + 各自内容哈希**；不记录目录 mtime | 新 gemspec 文件出现必须触发失效，且集合本身就是输入 |
| ENV | 只哈希白名单键的**值**（`C1`、`C3`-`C6`），键名也进文本；空字符串与未设置视为不同（`settings.rb:301` 用 `ENV[...]` 真值判断，`shared_helpers.rb:26` 区分空串） | 参考对二者的行为不同 |
| 配置 | 对「求值相关键」按 `键=值` 排序后整体哈希（`config.digest`），而非哈希配置文件原文 | 注释、键顺序、无关键（`jobs` 等）不应引发失效 |
| ABI | 优先取真值（`Gem.ruby_api_version`、`Gem.extension_api_version`）；取不到时写推导值并置 `abi.source=derived` | 现状是推导（`resolution.cr:170-173`），必须让「推导」在指纹里可见 |
| 版本串 | 原样字符串，不做 `Gem::Version` 归一 | 归一化本身是行为，不能混进键 |

### 3.3 Crystal 侧可用摘要工具

- 标准库 `Digest::SHA256` 已在仓内使用：`src/celerite/resolution.cr:377` `"sha256=#{Digest::SHA256.hexdigest(File.read(cached))}"`（`--add-checksums` 从下载缓存算）。
- `GemfileEvaluation#gemfile_sha256`（`src/celerite/bridge/client.cr:265`）已由 `assets/bridge/server.rb:214` 用 Ruby `Digest::SHA256.hexdigest(contents)` 生成，hex64、小写。**可以直接作为 §3.1 的 `gemfile.sha256` 字段复用**，但它只覆盖 A2 一项。
- 仓内**没有**通用的「文件 → SHA-256」工具模块：`src/celerite/checksum.cr:11-33` 只做 `normalize_hex`（HEX64/BASE64 → 小写 hex）。新增摘要工具应落在 `checksum.cr` 或新的 `fingerprint.cr`，并复用 `normalize_hex` 校验格式。
- 注意：Crystal 侧对 Ruby 侧已算的哈希要**校验格式**再采信（`Checksum.normalize_hex` 正合适），否则桥返回空串会静默变成「空文件哈希」。

### 3.4 与 `roadmap.md:165` 持久化缓存键的关系

`roadmap.md:165` 要求的持久化缓存键（source 身份、凭据隔离标识、checksum、平台、Ruby ABI、build 配置）与本节指纹是**两层**：

- 指纹回答「这次求值结果还能不能用」（依赖图层面）。
- 缓存键回答「这个 .gem / 这个 build 产物还能不能用」（制品层面）。

两层都含平台与 ABI，且必须来自**同一个** `RubyEnvironment` 快照，否则会出现「求值按 3.3 缓存、安装按 4.0 查找」的撕裂。建议指纹文本里同时写入该快照的摘要（`runtime.snapshot=<hex64>`），让两层可对账。

## 4. 落点清单（只列，不改）

「现在会不会重复求值」= 现状实测/代码路径判断，未跑新实验的已注明。

| # | 调用点 | 现状 | 现在会不会重复求值 |
|---|---|---|---|
| 1 | `src/celerite/resolution.cr:326-340`（`Resolution#initialize` → `:381-383` `eval_gemfile` → `@bridge.evaluate_gemfile`） | 无条件求值 | **会**：每次 `Resolution.new` 一次；无任何缓存判断 |
| 2 | `src/celerite/cli/commands_install.cr:274` + `:293` | 先内联求值做 ruby/platform 校验，再 `Resolution.new` 求值一次 | **会，同命令 2 次**（同 bridge 进程） |
| 3 | `src/celerite/cli/commands.cr:1485`（check 前 Resolution）、`:1533`（`Bridge::Client.new` + `evaluate_gemfile`）、`:1555`（frozen 时再起进程求值）、`:1594`（re-resolve 再 `Resolution.new`） | 分散求值 | **会，frozen 路径最多 3 次 / 3 个 Ruby 进程**（依据 M8 基线记忆：no-change check 8 RPC/6 ruby，属历史测量，未本轮复测） |
| 4 | `src/celerite/cli/commands.cr:1670`、`:1681`、`:1742`（check heal 分支各自 `Resolution.new`） | 分支内新建 | 会（每条分支各 1 次） |
| 5 | `src/celerite/cli/commands_surface.cr:141`（`--group`）、`:158`（`--source`）、`:165`（`Resolution.new`） | update 预先求值做过滤 | **会，update 最多 3 次** |
| 6 | `src/celerite/cli/commands_surface.cr:521`、`:831`、`:924`（add/remove 流程）；`:1902`/`:1982`（licenses/fund）；`:2260`（open）；`:2671`（plugin）；`:3077`（pristine）；`:3178`+`:3194`（outdated） | 各自独立求值 | 会（多数命令 1 次，add/remove 分支内 2 次量级） |
| 7 | `src/celerite/cli/commands_surface.cr:1275-1279`（env/issue 的 `### Gemspecs`） | 走 `bridge.gemspec_paths`，桥内**再 eval 一次**（`server.rb:227-238`） | **会**，额外 1 次求值只为列 gemspec 路径 |
| 8 | `src/celerite/cli/gemfile_warnings.cr:37` | 命令没有求值结果时补一次 | 会（条件触发，1 次） |
| 9 | `src/celerite/plugin_gemfile.cr:24-32` | 为拿插件名另起 `Bridge::Client` 调 `plugin_gemfile_eval` | **会**，额外 1 个 Ruby 进程 |
| 10 | `src/celerite/cli/commands.cr:3054`（`lock` 的 `run_lock`，`run_lock` 起于 `:2946`） | 无条件 `Resolution.new`（`：3054`），随后 no-op 门在 `:3085-3111` 判定，且该门的条件直接吃求值结果（`:3087` `dependency_sources_changed?(resolution.evaluation.dependencies, resolution.evaluation.sources)`、`:3088` `resolution.path_specs_changed?`） | **会**：求值在 no-op 判定之前，且 no-op 门本身依赖求值结果，无法先判定再跳过求值。注：`:3055`、`:3064`、`:3033` 注释里的 `cli/lock.rb:NN` 指**参考侧** `bundler/cli/lock.rb`，非本仓路径（本仓无 `src/celerite/cli/lock.rb`，已验证该文件不存在） |
| 11 | 指纹落点（建议位置，非现状） | 无 | `client.cr:342`（`evaluate_gemfile`）与 `resolution.cr:330` 之间是唯一合理的「读/写指纹」层；`server.rb:174-223` 需要扩展返回字段 |

结论：现状**没有任何地方读取指纹**，且同一逻辑命令内存在 2-3 次重复求值。指纹缓存的第一收益不是磁盘持久化，而是把 #2、#3、#5、#7、#9 这些同进程/同命令重复压掉；持久化只在跨进程（#3 的独立 `Bridge::Client.new`、#9）才有意义。

第二个天然消费者是 `lock` 的 no-op 门（`commands.cr:3085-3111`）：它已经在吃求值结果（`:3087`/`:3088`），若能命中指纹，就可以把 no-op 判定提到求值之前。但该门同时依赖 `resolution.path_specs_changed?`（解析段证据，`commands.cr:3088`），因此「跳过求值」的可行域少于「跳过解析」——这条边界必须在实现前钉死，否则会先把「无变化 lock 不走 Ruby」（`docs/roadmap.md:164`）做成不可达目标。

## 5. 可验证判据草案（只给形状，不写测试代码）

| # | 判据 | 夹具 | 观测 |
|---|---|---|---|
| V1 | 指纹确定且稳定：同一项目连续两次 `lock`，第二次命中缓存 | `with_project` 单 Gemfile + `file_source_url(fixtures/gem-index)`（同 `spec/m8_bridge_stats_spec.cr:6`） | `CELERITE_BRIDGE_STATS=1` 下第二次的 `procs`/`rpc` 严格小于第一次；且 lockfile 字节相等 |
| V2 | Gemfile 内容变化必失效 | 改写 Gemfile 的 `gem` 行 | 第二次仍产生 1 次求值 RPC；lockfile 反映新依赖 |
| V3 | **gemspec 内容变化必失效**（反例 1 的正向证明） | Gemfile 只含 `gemspec`；改 `foo.gemspec` 的 dev dep 版本 | 缓存不得命中；lockfile 的 DEPENDENCIES 段变化 |
| V4 | `eval_gemfile` 链上第二层文件变化必失效 | `Gemfile` 尾部 `eval_gemfile "sub/Gemfile.local"`；改被嵌套文件 | 失效；依赖集合变化 |
| V5 | 嵌套相对基准正确 | 只在 `sub/` 下存在 `sub/other.rb`，`sub/Gemfile.local` 内 `eval_gemfile "other.rb"` | 指纹记录的是 `<proj>/sub/other.rb`（对照 `dsl.rb:329-337`），不是项目根 |
| V6 | ENV 白名单边界：非求值 ENV 不得使缓存失效 | 只设 `BUNDLE_WITHOUT=development` / `BUNDLE_FROZEN=true` / `BUNDLE_LOCKFILE` 指向别的文件 | 求值缓存仍命中（求值 RPC 不增加）；但输出（分组/写入/路径）按各自语义变化 |
| V7 | 求值 ENV 必须失效 | 切换 `BUNDLE_PLUGINS` 0/1；或 `BUNDLE_IGNORE_CONFIG` 0/1 且项目 `.bundle/config` 含 `plugins: true` | 失效，且 `source type:` 的成功/失败随参考行为变化 |
| V8 | ABI 隔离：不同 Ruby 不得共用条目 | 两次运行分别伪造 `CELERITE_PROFILE_BUNDLER_VERSION` 无关；用 `RubyEnvironment` 注入不同 `ruby_version` 的夹具（或两个 Ruby 安装） | 指纹不同；持久化缓存目录不同 |
| V9 | **内容哈希不足以作键**的反证 | 同上 V3 + V8，构造「Gemfile 哈希相同但指纹不同」的两个场景，断言指纹不等而 `gemfile.sha256` 相等 | 直接钉死 §2.4 的反例 |
| V10 | 动态形态降级 | Gemfile 内 `ENV.fetch("CUSTOM_FLAG", "a")` 参与 `gem` 名或版本 | `mode=unknown`（或等价字段），缓存不写入；对照 `device: :deterministic` 的默认路径 |
| V11 | 目录 mtime 不入键 | 只 `touch` 项目目录（不改任何文件） | 指纹不变、缓存命中（防止失效风暴） |
| V12 | 行尾与编码按字节 | 把 gemspec 从 CRLF 改成 LF、内容"等价" | 指纹变化（字节变），与参考读字节一致 |
| V13 | 与参考差分 | `script/differential` 跑同一夹具在参考 Bundler 与 Celerite 下 | 输出/lockfile/退出码一致；指纹缓存开关不改变任何可观测输出（缓存是纯加速） |

V13 是总门禁：**指纹缓存必须对可观测行为透明**。任何 V1-V12 通过但 V13 失败的情况，说明缓存改变了语义。

## 6. 本机不可验证项

1. **多 Ruby ABI**：本机只有 `C:\Ruby40-x64` 一个 Ruby。E5 的 `Gem.extension_api_version` 真值、`-static` 后缀分支（我方模板 `commands_install.cr:1069`）无法实测；只能给推导值并标 `abi.source=derived`。
2. **非 MRI 引擎**（JRuby/TruffleRuby）：`ruby_version.rb:108-115` 的 engine 分支、`ruby_scope`（`bundler.rb:254-256`）路径形状均未验证。
3. **Linux/macOS**：路径大小写敏感语义、`/` 与 `\`、`RbConfig::CONFIG["host_os"]` 取值、`Gem::Platform.local` 取值均未验证；§3.2「不做大小写折叠」的取舍在大小写敏感卷上才有完整证据。
4. **YJIT / 编译选项**：`RbConfig::CONFIG` 中与 YJIT、`--enable-shared` 相关的项是否影响求值，未测（预期不影响求值，但属未验证）。
5. **插件真实安装/卸载**：本机未安装任何 Bundler 插件，F1 的「插件索引内容变化 → 失效」只有代码路径证据（`plugin.rb:130-153`、`index.rb:178`），无运行时证据。
6. **`bundler/inline`**：未在 Celerite 下跑过 inline 形态（参考侧 `inline.rb:46-47` 会改写 `BUNDLE_GEMFILE`/`BUNDLE_LOCKFILE`），`mode=unknown` 的实际触发未验证。
7. **`ruby file:` 的 `.tool-versions` 解析细节**：`ruby_dsl.rb:43-66` 已读，但未实测 Celerite 侧是否会读到同名文件（我方无实现，属缺失而非差异）。
8. **持久化缓存跨进程失效**：本轮未实现、未测；V1 的「第二次进程内命中」与「第二次跨进程命中」需分别取证。
9. **本文件所有 Celerite 行号**：基于 `9098d29` 工作树静态阅读，未跑 `crystal spec`/`shards build` 复核（只读任务，未编译）。
