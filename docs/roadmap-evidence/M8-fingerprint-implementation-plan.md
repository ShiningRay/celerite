# M8 求值指纹：落地实施方案（task-232）

- 性质：**只读调研 + 方案**。`src/`、`spec/`、`fixtures/`、`script/`、`docs/roadmap.md` 未改；唯一写入是本文件。
- 基线：工作树 `C:\temp\celerite-t232`，detached HEAD `c21a9d3`。任务书称该工作树已建好，实查不存在（`Test-Path` 为假），本任务重新 `git worktree add --detach` 建出，建后 `git status --porcelain` 为空。
- 上游：`docs/roadmap.md:162`（L162）与 task-222 的 `docs/roadmap-evidence/M8-evaluation-fingerprint.md`（280 行，提交 `2df7313`，下称「222 报告」）。222 报告已通读；本文只把它落成可执行计划，不重复盘点。
- 证据等级：**读码实测**＝本轮读过原文并核对行号；**运行时实测**＝真跑命令（本轮只有 `git`/`grep`/文件读取；`script/differential` 按令禁跑）；**推断**＝未跑、由代码路径与 222 报告推出。
- 行号口径：全部按 `c21a9d3`。222 报告基于 `9098d29`，`commands.cr` 的 `lock` 段已漂移（222 记 `:3054`/`:3085-3111`，现为 `:3075`/`:3106-3132`），本文对每个引用点重新核对。

## 0. 结论速览

- 形状：版本化、定序、一行一条的 `key<TAB>value` 文本；文本整体 SHA-256 的 hex64 才是指纹。字段顺序固定，重复族按「规范化绝对路径的字节序」排序后重编索引。
- 结构决定：指纹**必须分两半**。
  - 产出半只能由 Ruby 侧在**同一次求值内**给出：`@gemfiles`（eval 链）、`builder.gemspecs`、`ruby file:` 实际读到的文件，只有 `Bundler::Dsl` 实例知道。
  - 校验半必须让 Crystal 侧**不启动 Ruby**也能重算：文件清单与内容哈希、glob 模式、白名单 ENV、配置摘要、runtime 锚。
  - 因此持久化条目必须**自描述**（存 verify 集），命中时重算 verify 集，而不是「再算一遍指纹」——没有 Ruby 就没有指纹。
- 现状那层不叫指纹：`EvaluationCache`（`src/celerite/bridge/client.cr:87-132`）的键是「绝对路径 + 全量 ENV 明文拼接」（`:101-110`），命中只校验主 Gemfile 一个文件的字节（`:124`）。缺 eval 链、gemspec、`ruby file:`、插件、ABI；且 ENV 明文拼接把凭据类变量的值留在内存键里，**不得**原样升级成磁盘键。
- 落点：产出在 `assets/bridge/server.rb:237-247`（唯一一次求值）与 `:252-290`（序列化），新增 `fingerprint` 段随 `evaluate_batch` 的 `include` 返回（`:324-335`）；消费在 `src/celerite/bridge/client.cr:118-131`（`fetch`）与 `:541-580`（两个求值入口）；生命周期挂 `src/celerite/cli.cr:26`/`:48`。新模块建议 `src/celerite/eval_fingerprint.cr`。
- 切片 5 片：F1 桥侧产出 → F2 进程内校验换血 → F3 三态判定 → F4 跨命令持久化 → F5 调用点收口。F4 先以 `CELERITE_EVAL_CACHE` 默认关闭落地；开关翻转属 L164 验收。
- 最危险：漏一项输入 → 错误命中 → 静默复用错误依赖图。缓解是「保守方向只能多失效」：三态判定、自描述 verify 集、每次命中重算文件哈希与 glob、任何不一致即 miss 并删条目。
- 输入口径对账：222 报告称 22 项，其清单实为 **26 个编号行**；差 4 来自 C7 一行同时覆盖 5 个 ENV（`BUNDLE_PATH`/`WITHOUT`/`ONLY`/`FROZEN`/`DEPLOYMENT`）。本文按 26 行逐条落，不改 222 的编号。

## 1. 指纹的形状与落点

### 1.1 编码

文法：

```
text    := magic LF record*
magic   := "celerite-eval-v1"
record  := key TAB value LF
key     := [a-z0-9._]+
value   := escaped UTF-8（不含 TAB/LF/CR 原文）
escape  := "\\" → 反斜杠，"\\t" → TAB，"\\n" → LF，"\\r" → CR
```

- 文本以单个 LF 结尾（无尾随空行、无 CRLF）；`digest = SHA-256(UTF-8 bytes of text)`，hex64 小写。
- 固定字段顺序（自上而下，段内按表列顺序）：

```
celerite-eval-v1
fp.format=1
gemfile.path=<abs>
gemfile.sha256=<hex64>
gemfile.source=<env|search|config>
evalchain.count=<n>
evalchain.<i>.path=<abs>
evalchain.<i>.sha256=<hex64>
gemspec.count=<n>
gemspec.<i>.path=<abs>
gemspec.<i>.sha256=<hex64>
gemspec.<i>.root=<abs>
gemspec.<i>.glob={,*}.gemspec
gemspec.candidates=<n>
gemspec.candidate.<i>=<abs>          # 排序后的 glob 命中集
rubyfile.count=<n>
rubyfile.<i>.path=<abs>
rubyfile.<i>.sha256=<hex64>
ruby.version=<str>
ruby.patchlevel=<str>
ruby.engine=<str>
ruby.engine_version=<str>
ruby.description=<str>
rubygems.version=<str>
bundler.version=<loaded Bundler::VERSION>
bundler.profile=<celerite profile>
platform=<str>
abi.ruby_api_version=<str|->
abi.extension_api_version=<str|->
abi.source=<real|derived>
runtime.exe.path=<abs>
runtime.exe.size=<bytes>
runtime.exe.mtime_ns=<int>
config.digest=<hex64>
config.app_config=<abs>
config.plugins=<true|false>
config.gemfile=<str|->
config.path=<str|->
config.force_ruby_platform=<true|false>
env.<WHITELIST_KEY>=<value|->      # 未设置写 "-"，空串写 "" + 标记 <empty>
env.scope=<hex16>
plugins.enabled=<true|false>
plugins.count=<n>
plugins.<i>.name=<str>
plugins.<i>.version=<str>
plugins.index.sha256=<hex64|->
mode=<deterministic|unknown|broken>
mode.reason=<token[,token]>
```

- `env.scope` = 对「白名单之外的 `BUNDLE_*` 键名集合」排序后做 SHA-256，取前 16 hex；**只表达凭据/主机配置的形态**，不含值（见 §2.7）。
- 规范化规则：

| 对象 | 规则 | 理由 |
|---|---|---|
| 路径 | `File.expand_path` → 分隔符统一 `/`；**不做**大小写折叠、**不用** `realpath` | 折叠在大小写敏感卷上会并掉两个文件（误命中）；`realpath` 会让「换软链但内容相同」不失效 |
| 内容 | 对原始字节做 SHA-256；不做 CRLF/编码归一 | 参考按字节读（222 报告 `bundler.rb:499-503`）；行尾是语义 |
| 集合 | 排序后逐项记录，索引在排序后重编；同路径去重 | DSL 发现顺序不是输入；顺序变化不应改变指纹 |
| 数值 | 十进制、无前导零；布尔小写 `true`/`false` | 文本解析确定性 |
| 版本串 | 原样，不做 `Gem::Version` 归一 | 归一化本身是行为 |
| 缺失 | 写 `-`，不省略字段 | 省略会让「字段不存在」与「字段为空」不可区分 |
| 日志/mtime | 目录 mtime、ctime 一律不入键（`runtime.exe.mtime_ns` 是唯一例外，且只作锚） | 目录 mtime 会因无关文件增删而变 → 失效风暴 |

指纹**不含**解析分区键（`BUNDLE_WITHOUT`/`ONLY`/`FROZEN`/`DEPLOYMENT`/`LOCKFILE`/`PATH`/`FORCE_RUBY_PLATFORM`/`JOBS` 等），它们写入条目里独立的 `partition` 段，不参与 digest（见 §3）。

### 1.2 计算点（产出半）

| 角色 | 位置 | 现状（读码实测） | 计划 |
|---|---|---|---|
| 求值执行 | `assets/bridge/server.rb:237-247` `bridge_evaluate_gemfile` | 返回 `builder, contents, warnings`；注释 `:230-236` 明确 batch 不得二次求值 | 在此之后调用 `bridge_fingerprint(builder, gemfile, contents)`（新函数，+90~120 行） |
| 序列化 | `assets/bridge/server.rb:252-290` `bridge_serialize_evaluation` | 已用 `instance_variable_get(:@ruby_version)`（`:267`）、`:@sources`（`:272`） | 同一先例读 `:@gemfiles`、`builder.gemspecs`；`fingerprint` 段只在被请求时附上，不改变旧键序 |
| 分段出口 | `assets/bridge/server.rb:324-335` `op_evaluate_batch` | `include` 目前只认 `gemspecs`（`:333`）；未知段忽略（`:321-323`） | 加 `fingerprint` 段；`BRIDGE_FEATURES`（`:42`）追加能力名 |
| 单 op 出口 | `assets/bridge/server.rb:294-300` `op_evaluate_gemfile` | 不带段 | **不加字段**：老出口形状是差分夹具与旧客户端的基准 |
| 独立 gemspec op | `assets/bridge/server.rb:304-310` `op_gemspec_paths` | 每次再求值一次 | F5 收口后由 batch 的 `fingerprint`+`gemspecs` 取代 |

计算点选在 Ruby 侧的理由（不是偏好）：`@gemfiles` 由 `Bundler::Dsl#eval_gemfile` 维护（222 报告 `dsl.rb:41`、`:46-61`、`:329-337`），`builder.gemspecs` 只在求值后存在，`ruby file:` 的目标由 `ruby_dsl.rb:43-66` 内部解析。Crystal 侧重算等于重实现 Bundler 的路径决议，且必然与参考漂移。

### 1.3 消费点（校验半）

| 位置 | 现状 | 计划 |
|---|---|---|
| `src/celerite/bridge/client.cr:87-132` `EvaluationCache` | 键＝`expand_path(path)+全 ENV`（`:101-110`）；`fetch` 复算主文件哈希（`:118-126`） | 改成 `fetch(path, verify)` / `store(path, verify, evaluation)`；删除 `environment_signature`（`:108-110`）的全量拼接 |
| `client.cr:329-344` `GemfileEvaluation` | 无指纹字段 | 不改；新结构 `EvalFingerprint`（`text`/`digest`/`verify`）挂在 `BatchGemfileEvaluation`（`:350-356`） |
| `client.cr:541-553` `evaluate_gemfile` | 命中即返回，不重复记 warnings（`:542-545`） | 命中判定换成 verify 重算；warnings 语义不变 |
| `client.cr:562-580` `evaluate_batch` | `include` 非空时**从不**走缓存（`:562-567`） | `include` 只含 `fingerprint`/`gemspecs` 时可走缓存（两者都在条目里） |
| `src/celerite/cli.cr:26` / `:48` | `begin_run`/`finish` 管进程内表 | 持久化装载/落盘/GC 挂这里（进程级） |
| `src/celerite/resolution.cr:326-330`、`:381-383` | 无条件求值 | **不改**：它只是 `evaluate_gemfile` 的调用者，命中对它透明 |

`verify` 的结构（条目自描述集，JSON）：

```json
{"files":[{"role":"gemfile|evalchain|gemspec|rubyfile","path":"...","sha256":"..."}],
 "globs":[{"role":"gemspec","root":"...","pattern":"{,*}.gemspec","candidates":["..."]}],
 "env":{"BUNDLE_PLUGINS":"true","BUNDLE_GEMFILE":"..."},
 "env_scope":"<hex16>",
 "config":{"digest":"<hex64>","values":{"plugins":true,"gemfile":null,"path":null,"force_ruby_platform":false}},
 "runtime":{"exe":"...","size":123,"mtime_ns":0,"ruby_version":"...","rubygems_version":"...","bundler_version":"...","platform":"...","abi":{"ruby_api_version":"...","extension_api_version":null,"source":"derived"}},
 "mode":"deterministic"}
```

### 1.4 为什么「进程内」这层还不叫指纹

1. **覆盖不到求值内容边界**：只比主 Gemfile（`client.cr:124`），反例 1（gemspec 变）与反例 3（插件卸载）都会误命中。
2. **没有运行时身份**：`ruby_version`/ABI/`Gem::VERSION`/Bundler profile 都不在键里（反例 2）。进程内这些量不变，跨进程必变。
3. **键的构造不可持久化**：`environment_signature`（`client.cr:108-110`）把**全部** ENV 的键值明文拼成字符串；一旦写盘即泄密（`BUNDLE_GEMS__EXAMPLE__COM=user:pass` 这类主机键）。
4. **没有载体**：`@@entries`（`client.cr:89`）在 `finish` 清空（`:96-99`），进程退出即无。

所以它是「同一进程、同一命令内的 memo」，只解决重复 RPC，不解决「上次命令的求值还能不能用」。

### 1.5 跨命令持久化：写到哪里、什么格式、坏了怎么办

- 目录：`$CELERITE_CACHE_DIR`（新环境变量，可选覆盖）→ 否则 `<Config.user_home>/.celerite/cache/eval/v1/`（`Config.user_home` 见 `src/celerite/config.cr:329`）。
- 为什么不用项目内 `.bundle/`：① `.bundle` 是配置根，`config list` 与 git 会看到派生产物；② 项目目录可能只读/被清理；③ 内容寻址（digest 含绝对路径与 runtime 锚）已天然区分项目，不需要目录再分。
- 文件名 `<digest>.json`；内容 `{"format":"celerite-eval-cache/1","fingerprint":"<hex64>","fingerprint_text":"...","verify":{...},"evaluation":{...},"partition":{...},"created_at":"...","celerite_version":"..."}`。
- 原子写：同目录 `.<digest>.<pid>.tmp` → `File.rename`。Windows 上 rename 不覆盖已存在目标：先 `File.delete` 再 `rename`，任一步失败即放弃写（缓存丢一次无害，**不得**影响退出码）。
- 读回校验（全过才算命中，任一失败即 miss 并按需删除）：`format` 精确相等 → 文件名与 `fingerprint` 相等 → `SHA-256(fingerprint_text) == fingerprint` → `verify` 每项重算相等 → `evaluation.gemfile_sha256 == 重算的主文件哈希`。**不认「部分可读」**。
- 损坏回退：任何异常（含 JSON 解析、缺字段、权限）→ 返回 miss，删除条目，继续走桥。`CELERITE_EVAL_DEBUG=1` 时向 stderr 打一行原因，默认静默。
- 版本：`fp.format`（文本内）与 `format`（JSON 内）双版本；任一不匹配即 miss，旧条目由 GC 清。
- GC：目录内按 mtime 保留最近 50 条；在 `cli.cr:48` 的 `finish` 做，失败静默。
- 默认关闭：`CELERITE_EVAL_CACHE` 未设或 `0` → 只写进程内、不读写磁盘。理由：跨命令命中是本行最危险的新语义，必须先有 F3 的失效反例与 F4 的损坏/并发用例，才谈默认开启。

## 2. 逐项输入的采集方式

口径：**采** = 从哪里取（文件:行号）；**粒度** = 记到多细；**补/标** = 缺失项怎么补，补不了怎么标不确定。

### 2.1 A 类：Gemfile 与其递归链

| 编号 | 采集方式与粒度 | 补法 / 标注 |
|---|---|---|
| A1 | `Definition.find_gemfile`（`src/celerite/definition.cr:56-63`）给路径；记 `gemfile.path`（绝对化）+ `gemfile.source=env|search` | 我方**不读配置 `gemfile` 键**（`definition.cr:56-63` 只有 `ENV["BUNDLE_GEMFILE"]` 与 `search_up`）。可观测判据：`config["gemfile"]`（`cfg` 见 `src/celerite/config.cr:440`）非空而我们用了 search 结果 → `mode=unknown`。F1 补优先级 `ENV → config gemfile → search_up`（对齐 222 报告 `settings.rb:59-77`，转引） |
| A2 | 主文件内容哈希：复用桥已算的 `gemfile_sha256`（`assets/bridge/server.rb:244`、`:281`），Crystal 侧用 `Digest::SHA256`（`src/celerite/bridge/client.cr:1`）按磁盘字节复算 | 粒度＝原始字节。无缺口 |
| A3 | `builder` 内 `@gemfiles`（`instance_variable_get(:@gemfiles)`，先例见 `server.rb:267`/`:272`）：逐项绝对路径 + 内容哈希，按路径排序 | 现状零覆盖（`server.rb:252-290` 无此字段）。F1 前一律 `mode=unknown`——没有链清单就无法证明求值闭包。相对基准由 Bundler 内部解析（222 报告 `dsl.rb:329-337`，转引），我方不重算 |
| A4 | prepend 探针到 `Bundler::RubyDsl#ruby`，记录 `file:` 实参及**实际读到的文件**（`.ruby-version`、`.tool-versions`），逐项 `rubyfile.<i>.path/sha256` | 我方零实现。探针失败/目标不存在但求值成功 → `mode=unknown`（不能假设「没读」） |
| A5 | 对 Gemfile 与每个被求值 gemspec 的**源文本**做保守 token 扫描：`ENV[`、`ENV.fetch`、`File.`、`IO.`、`Dir.`、`require`、`load`、`eval`、`system`、反引号、`%x`、`open`；命中记 `mode=unknown` 与 `mode.reason=<token>` | 只记 token 名，**不记源码片段**（源码可能含凭据字面量）。这是「不可静态判定」的唯一诚实处理：不放行 |

### 2.2 B 类：被引用的 gemspec

| 编号 | 采集方式与粒度 | 补法 / 标注 |
|---|---|---|
| B1 | `builder.gemspecs.map(&:loaded_from)`（`server.rb:309` 已有同型调用）：每项 path + sha256 + `root`（项目根）+ `glob={,*}.gemspec`；另用 `Dir.glob` 重展开同一 `root/glob`，把排序后的候选集写 `gemspec.candidate.<i>` | 现状只在 `env`/`issue` 展示用（`commands_surface.cr:1275-1279`），不进任何键。候选集是必需项：**新增**一个 gemspec 文件会让参考在 `dsl.rb:95-97` 报多组合法性错误，Gemfile 字节却没变 |
| B2 | path:/git: source 的 gemspec（默认 `{,*,*/*}.gemspec`，可 `glob:`）→ 写条目 `partition.gemspecs`（`source`+`glob`+排序路径集+哈希），**不进** digest | 归解析段（222 报告 §2.2）：求值可命中，解析与锁必须失效。代价必须写进兼容声明 |
| B3 | `gemspec.<i>.root` 已表达「以 gemspec 目录为 cwd」；gemspec 自身源码参与 A5 扫描 | 未识别的副作用（`git ls-files` 之类）只可能靠 A5 token 覆盖，覆盖不到即未知；不假装完备 |

### 2.3 C 类：ENV

| 编号 | 采集方式与粒度 | 补法 / 标注 |
|---|---|---|
| C1 | `BUNDLE_GEMFILE` 值入 digest；路径身份由 `gemfile.path`/`gemfile.source` 表达 | 无缺口（`definition.cr:57-59`） |
| C2 | `BUNDLE_LOCKFILE` 值写 `partition.lockfile`，不进 digest | 它只改 lockfile 位置（222 报告 `shared_helpers.rb:25-35` 转引），不改 DSL 求值 |
| C3 | `BUNDLE_IGNORE_CONFIG` 值入 digest（`config.cr:138` 是唯一读取点） | 无缺口 |
| C4 | `BUNDLE_APP_CONFIG` 值入 digest + `config.app_config`（`config.cr:121-133`） | 插件根随之移动（222 报告 `plugin.rb:138-148` 转引）；F1 前无法验证插件根，故插件存在时 unknown |
| C5 | `BUNDLE_CONFIG`/`BUNDLE_USER_CONFIG`/`BUNDLE_USER_HOME` 值入 digest + 实际全局配置文件路径（`config.cr:313-322`） | 三者都是路径，不是秘密；可按值入摘要 |
| C6 | `BUNDLE_PLUGINS` 值入 digest + 生效值 `config.plugins`（默认 `true`，`config.cr:40`） | 门控点见 222 报告 `cli.rb:158` 等（转引） |
| C7 | `BUNDLE_PATH`/`WITHOUT`/`ONLY`/`FROZEN`/`DEPLOYMENT` 值写 `partition`，不进 digest | **不得**当求值输入：分组过滤与 frozen 判定在 `Definition` 建成之后（222 报告 `definition.rb:1252-1253`、`bundler.rb:237-242` 转引）。否则 `--without` 一次就整段失效 |
| C8 | `BUNDLE_FORCE_RUBY_PLATFORM` 写 `partition.force_ruby_platform` | 改候选平台集合，不改 DSL 求值 |
| C9 | 非白名单 `BUNDLE_*` 只记**键名集合** → `env.scope`；非 `BUNDLE_` 前缀的任意 ENV **无观测手段** | 明写「未观测」；兜底是 A5：Gemfile 里出现 `ENV` token 即 `mode=unknown`。不要在文档或注释里暗示「ENV 已全覆盖」 |

### 2.4 D 类：配置文件中参与求值的键

| 编号 | 采集方式与粒度 | 补法 / 标注 |
|---|---|---|
| D1 | `config.digest = SHA-256` over 排序后的 `k=v`：`plugins`、`gemfile`、`path`、`force_ruby_platform`；值统一从 `Config#[]`（`config.cr:440`，已合并 CLI/ENV/本地/全局）取；另记 `config.app_config` 与全局文件路径 | 不哈希配置文件原文：注释、键序、无关键（`jobs` 等）不该引发失效。分级与 `config.cr:14-27` 的键表对齐，避免另造一份键名 |

### 2.5 E 类：运行时版本与 ABI

| 编号 | 采集方式与粒度 | 补法 / 标注 |
|---|---|---|
| E1 | `GemfileEvaluation` 已有 `ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`（`client.cr:334-338`，填充于 `server.rb:276-279`）；另取 `RubyEnvironment` 同名字段（`client.cr:198-202`）交叉校验 | 双源不一致 → `mode=unknown`。版本串原样，不归一 |
| E2 | `RubyEnvironment#rubygems_version`（`client.cr:203`，填充于 `server.rb:189` = `Gem::VERSION`） | 它不在 `GemfileEvaluation` 里，指纹从 runtime 快照取，不要求扩求值协议 |
| E3 | `bundler.version` = `server.rb:280`（加载后 `Bundler::VERSION`）；`bundler.profile` = `Profile.bundler_version`（`src/celerite/profile.cr:11-25`） | 两者**必须都记**：task-230 修的正是「参考 Bundler 在激活前被加载」导致的版本污染（`c21a9d3`）；不一致 → `mode=unknown` |
| E4 | `platform`：`RubyEnvironment#platform`（`client.cr:206`，`server.rb:192`） | 只在本机形态验证过（`x64-mingw-ucrt`）；其他平台形态标未验证 |
| E5 | 现状：`InstallPaths.ruby_abi_for`（`src/celerite/resolution.cr:164-173`）按 `<major>.<minor>.0` 推导，`abi.source=derived` | F1 在 `op_ruby_environment`（`server.rb:181-228`）加 `Gem.ruby_api_version`/`Gem.extension_api_version` 真值；取到即 `abi.source=real`。推导值**不等于** `extension_api_version`（可能带 `-static` 后缀），跨 ABI 必须判 miss，见 §6 |

### 2.6 F 类：插件与不可静态判定的形态

| 编号 | 采集方式与粒度 | 补法 / 标注 |
|---|---|---|
| F1 | 由 server 读插件索引：`<app_config>/plugin` 存在性 + 索引文件哈希 + 已装插件 `(name, version)` 排序列表（参考 `plugin.rb:130-153`、`plugin/index.rb:105-106`，转引） | 我方零读取（`plugin_gemfile.cr:24-47` 只读 Gemfile 文本）。读失败或目录存在但不可解析 → `mode=unknown`，绝不当作「无插件」 |
| F2 | typed source 可用性由 F1 派生；`source ..., type:` 出现且 F1 不可判定 → `mode=unknown` | 反例 3 的正确形状：卸载插件后必须报 `dsl.rb:129-133` 的错，而不是命中旧成功结果 |
| F3 | `require "bundler/inline"`、`eval`、`system` 等由 A5 扫描；命中即 unknown，且 negative（抛错）结果**不落盘** | `mode=broken`（求值抛错）不缓存任何东西：错误可能依赖 ENV，缓存错误等于伪造行为 |

### 2.7 ENV 白名单 / 黑名单

| 类别 | 变量 | 进摘要的形式 | 理由 |
|---|---|---|---|
| 值 | `BUNDLE_GEMFILE`、`BUNDLE_APP_CONFIG`、`BUNDLE_CONFIG`、`BUNDLE_USER_CONFIG`、`BUNDLE_USER_HOME`、`BUNDLE_IGNORE_CONFIG`、`BUNDLE_PLUGINS`、`CELERITE_PROFILE_BUNDLER_VERSION`、`CELERITE_RUBY`、`RUBYOPT`、`RUBYLIB` | `env.<KEY>=<value>`，未设置写 `-`，空串写 `""` 并带 `<empty>` 标记 | 前 8 个直接决定读哪个文件、读哪份配置、插件是否可用（`config.cr:138`、`:147-151`；`profile.cr:11-25`）。`RUBYOPT`/`RUBYLIB` 改变 `require` 与 load path，Gemfile 内 `require` 会受影响——**推断**，本机未实测 |
| 仅「是否设置」 | 所有 `BUNDLE_USER_*`；主机/凭据键（键名含 `__`，如 `BUNDLE_GEMS__EXAMPLE__COM`）；键名匹配 `/(PASSWORD|TOKEN|SECRET|CREDENTIAL|API_?KEY|AUTH)/i` | 只进 `env.scope`（键名集合的 SHA-256 前 16 hex）；不记值、不记键名可见文本 | 任务要求与安全底线：凭据类变量的值不得进摘要。`env.scope` 只能表达「凭据配置形态变了」，**不能**表达「密码换了」——凭据内容属 L165 的「凭据隔离标识」，本行不复制 |
| 不进 | `BUNDLE_WITH`、`WITHOUT`、`ONLY`、`FROZEN`、`DEPLOYMENT`、`LOCKFILE`、`PATH`、`CACHE_PATH`、`JOBS`、`RETRY`、`TIMEOUT`、`SSL_*`、`MIRROR*`、`FORCE_RUBY_PLATFORM`、`CLEAN`、`NO_PRUNE`、`VERBOSE`、`SILENCE_DEPRECATIONS`、`GEM_HOME`、`GEM_PATH` | 值写条目 `partition` 段，不参与 digest | 求值后消费（222 报告 §2.2）；`GEM_HOME`/`GEM_PATH` 只影响候选与安装根，不改 DSL 求值 |

为什么用白名单而不是黑名单：黑名单要求枚举「所有可能泄密的键」，而 Bundler 的主机键是用户自定义的（`BUNDLE_<HOST>`），枚举不完备；白名单的失效方向是「少观测 → 多失效」，安全。

## 3. 失效矩阵

### 3.1 输入类别 × 缓存层

| 输入类别 | 进程内条目（`EvaluationCache`） | 持久化条目（`v1/*.json`） | 解析段（lock/候选） | 依据 |
|---|---|---|---|---|
| 主 Gemfile 内容（A2） | 整体失效 | 条目 miss + 删除 | 重解析 | 已实现（`client.cr:124`） |
| eval 链新增/删除/内容（A3） | 整体失效 | miss + 删除 | 重解析 | 222 §2.1-1 |
| gemspec 内容或候选集（B1） | 整体失效 | miss + 删除 | 重解析 | 222 §2.1-2、反例 1 |
| `ruby file:` 目标（A4） | 整体失效 | miss + 删除 | 重解析 | 反例 4 |
| 白名单 ENV 值（C3-C6、C1） | 整体失效 | miss + 删除 | 重解析 | 222 §2.1-6 |
| 非白名单 `BUNDLE_*` 键集合（C9） | 整体失效（`env.scope` 变） | miss + 删除 | 视键而定 | 保守：集合变即不信任 |
| 配置求值键（D1） | 整体失效 | miss + 删除 | 重解析 | 222 §2.1-6 |
| Ruby/RubyGems/Bundler/平台（E1-E4） | 整体失效 | miss（runtime 锚不符） | 安装根随之变 | 反例 2 |
| ABI（E5） | 整体失效 | miss；无 Ruby 时靠 `runtime.exe` stat 锚 | 安装根变 | 见 §6 残余风险 |
| 插件集合/索引（F1/F2） | 整体失效 | miss + 删除 | 重解析 | 反例 3 |
| 动态形态（A5/F3） | 不写条目（`mode=unknown`） | 不写 | 每次重算 | 222 §2.3 |
| 求值抛错（`mode=broken`） | 不缓存（含负结果） | 不写 | 每次重算 | 222 §2.3 |
| path/git gemspec（B2） | **不失效**（写 `partition`） | 不失效 | 解析段失效 | 222 §2.2 |
| 目录 mtime、`jobs`/`retry` 等 | 不失效 | 不失效 | 不失效 | 防失效风暴（222 V11） |
| 行尾/编码变化 | 失效（字节变） | miss | 重解析 | 参考按字节读 |

### 3.2 四个反例的落到字段

| 反例 | 由哪个字段捕获 | 命中的判据 |
|---|---|---|
| 1 同 Gemfile、gemspec dev dep 变 | `gemspec.<i>.sha256`（B1） | V3 |
| 2 同 Gemfile、ABI/Ruby 变 | `ruby.*`、`rubygems.version`、`abi.*`、`platform`、`runtime.exe.*` | V8、V9 |
| 3 同 Gemfile、插件卸载 | `plugins.*`、`plugins.index.sha256`、`config.plugins` | V7 |
| 4 同 Gemfile、`ruby file:` 变 | `rubyfile.<i>.sha256` | V4 同型 |

### 3.3 「缓存命中但实际输入变了」的兜底

1. **每次命中前重算 verify 集**，不是写入时算一次：文件桶逐项复算 SHA-256；glob 桶重展开并比较候选集（检测新增/删除）；配置桶重算 digest；ENV 桶重读白名单。
2. **条目自证**：`SHA-256(fingerprint_text) == fingerprint`。被手改、被截断、半写完成的文件都在这一步被拒。
3. **交叉证**：`evaluation.gemfile_sha256` 必须等于重算的主文件哈希（沿用 `client.cr:124` 的现有防线），且 `evaluation.gemfile` 与条目键的路径一致（防「同内容不同路径」串条）。
4. **大文件不降级**：单个输入文件超过 1 MiB（path 源 gemspec、巨型 Gemfile）时不改用 stat 近似，直接判 `mode=unknown`（不可缓存）。用命中率换安全，方向不许反。
5. **runtime 只能锚不能证**：`runtime.exe.size`/`mtime_ns` 只防「换了 ruby 路径/重装」。原地同尺寸替换 ruby 可执行文件会漏判——列为已知残余风险（§6），不用「指纹已覆盖 ABI」的说法掩盖。
6. **写侧失败不降级**：原子写失败、目录不可写、GC 失败一律静默走桥；缓存存在与否不得改变 stdout/stderr/exit。

## 4. 分片与依赖顺序

| 切片 | 目标 | 改动面（估算行数） | 可离线验证 | 与已落切片的关系 |
|---|---|---|---|---|
| **F1** 桥侧产出 | 一次求值产出 `fingerprint` 段（文本+digest+verify），只在 `include:["fingerprint"]` 时返回；不改缓存判定 | `assets/bridge/server.rb:237-247`/`:252-290`（+90~120）、`:324-335`（+6）、`:42` 能力表（+1）；`client.cr:350-356` 新结构（+40）；新 spec `spec/m8_eval_fingerprint_spec.cr`（+150） | 是 | 依赖 **S1**（`features`，`1f69d2f`）与 **S2**（`include`，`65c69c2`） |
| **F2** 进程内校验换血 | 用 verify 集替换「全 ENV 明文 + 只比主文件」；命中率不降、误命中归零 | `client.cr:87-132`（重写 ~90）+ 新 `src/celerite/eval_fingerprint.cr`（~150）+ spec（~200） | 是 | 依赖 F1；与 S6 正交 |
| **F3** 三态与失效语义 | `deterministic/unknown/broken` 判定；unknown 不落盘；broken 不缓存 | `server.rb` 静态扫描+探针（~60）；`client.cr` 三态与 miss 原因（~30） | 是 | 依赖 F1/F2 |
| **F4** 跨命令持久化 | 内容寻址条目、原子写、损坏回退、GC；默认关闭 | 新 `src/celerite/eval_cache_store.cr`（~120）；`cli.cr:26`/`:48`（~10）；`client.cr` 读写（~40）；spec（~200） | 是（并发/损坏用临时目录） | 依赖 F2/F3；是 L164 S3/S5 的前置 |
| **F5** 调用点收口 | `gemspec_paths` 与重复求值并入 batch 一次求值 | `commands_surface.cr:1275`、`commands_install.cr:274`、`commands.cr:1533`（~30） | 是 | 依赖 F1/F2 |

顺序：**F1 → F2 → F3 → F4 →（F5）**。F1/F2 必须串行（F2 消费 F1 的字段）；F3 依赖 F2 的 miss 语义；F4 只在 F3 之后才有资格谈持久化；F5 最后，因为它只影响计数，不影响正确性。

与已落切片（S1/S2/S6）的说明：

- **S1**（L161 协议版本与能力声明，task-226，`1f69d2f`）提供 `ping.features`（`assets/bridge/server.rb:42`），F1 必须把 `fingerprint` 加进该表，旧 server 才会被正确判为「没有这个段」并降级到旧 op，而不是收到 `UnknownOp`。
- **S2**（L161 `evaluate_batch`，task-227，`65c69c2`）提供 `include` 载体（`server.rb:324-335`），指纹段骑在它上面，**不得**另开一个会二次执行 Gemfile 的 op（`server.rb:230-236` 已把这个约束写进注释）。
- **S6**（L164 `list` 无组选择零 spawn，task-229，`e3ede75`）与指纹正交：它跳过的是组过滤（`commands.cr:2728-2743` 量级的分支），不需要指纹。若以后让 `list` 复用「组归属缓存」（222 报告的 L164 S3），那才是 F4 的消费者，不在本行。
- 本行**不**依赖 S1/S2 之外的 M8 切片；若 F1 之前有人先做 L164 的 S5（`lock` 短路前移），它只能做到「少一次求值」，不能做到零 spawn——零 spawn 的判据必须等 F4。

## 5. 判据草案

级别：**spec** = 仓内 `crystal spec` 可断言（离线、可用 `CELERITE_BRIDGE_STATS=1`）；**差分** = 必须 `script/differential` 与参考同页；**spec+差分** = 先 spec 后差分。本轮禁跑差分，差分列只给形状。

| # | 断言 | 构造 | 期望 | 级别 |
|---|---|---|---|---|
| V1 | 指纹稳定且可命中 | 单 Gemfile + 本地索引（同 `spec/m8_bridge_stats_spec.cr` 夹具）连跑两次 | 第二次 `procs`/`rpc` 严格更小；lockfile 字节相等 | spec |
| V2 | 主 Gemfile 变必失效 | 改一个 `gem` 行 | 第二次仍有 1 次求值；锁的 DEPENDENCIES 变化 | spec |
| V3 | gemspec 变必失效 | Gemfile 只含 `gemspec`，改 `foo.gemspec` 的 dev dep | 不得命中；DEPENDENCIES 段变 | spec |
| V4 | eval 链第二层变必失效 | `eval_gemfile "sub/Gemfile.local"` 后改该文件 | 失效；依赖集合变 | spec |
| V5 | 嵌套相对基准 | 只在 `sub/` 下有 `sub/other.rb`，由 `sub/Gemfile.local` 引用 | 指纹记 `<proj>/sub/other.rb` | spec |
| V6 | 非求值 ENV 不得失效 | 只设 `BUNDLE_WITHOUT`/`BUNDLE_FROZEN`/`BUNDLE_LOCKFILE` | 求值 RPC 不增加；输出按各自语义变 | spec+差分 |
| V7 | 求值 ENV 必须失效 | 切 `BUNDLE_PLUGINS` 0/1；`BUNDLE_IGNORE_CONFIG` 0/1 且本地配置含 `plugins: true` | 失效；`source type:` 成败随参考 | spec |
| V8 | ABI 隔离 | 注入两个不同 `ruby_version` 的 `RubyEnvironment` 夹具 | 指纹不同；持久化目录不同 | spec（本机单 Ruby，见 §6） |
| V9 | 内容哈希不足以作键 | V3+V8 组合，断言 `gemfile.sha256` 相等而指纹不等 | 直接钉死反例 | spec |
| V10 | 动态形态降级 | Gemfile 内 `ENV.fetch("CUSTOM_FLAG","a")` 参与 gem 名 | `mode=unknown`；不写盘；仍能求值 | spec |
| V11 | 目录 mtime 不入键 | 只 `touch` 项目目录 | 指纹不变、命中 | spec |
| V12 | 行尾按字节 | gemspec CRLF→LF | 指纹变 | spec |
| V13 | 缓存对可观测行为透明 | 同夹具在参考 Bundler 与 Celerite 下跑 | stdout/锁/exit 一致；开关缓存不改变任何输出 | 差分 |
| V14 | 条目自证 | 手改缓存 JSON 的 `fingerprint_text` 一位 | miss + 删除 + 走桥；退出码不变 | spec |
| V15 | 损坏安全回退 | 截断 JSON、空文件、目录当文件、`format` 改版本 | 一律 miss；stderr 默认无输出 | spec |
| V16 | 原子写/并发 | 两进程同时写同一 digest；kill 在 rename 前 | 无半写文件被读到；最坏丢一次缓存 | spec（Windows rename 覆盖语义须专门覆盖） |

V13 是总门禁：**指纹缓存必须对可观测行为透明**。V1-V12/V14-V16 全绿但 V13 红，说明缓存改变了语义，先回滚缓存开关再查。

## 6. 风险与本机不可验证项

### 6.1 Rails 规模性能不可验证

仓内无 Railties 量级夹具；100+ gem、多 source、多 path 源时，verify 集的文件数与哈希成本、glob 重展开成本、条目体积都未测。风险方向是**慢**而不是错：每次命中要哈希 eval 链 + 所有被引用 gemspec。缓解：① 记录条目内 `verify.files` 数量与总字节，超过阈值（如 64 文件/4 MiB）直接 `mode=unknown`；② 只对「本来就要 spawn Ruby」的命令默认开启，零 spawn 路径等 L164 再做；③ 基准报告必须给 wall/RSS/RPC，不只给倍数（`docs/roadmap.md:168` 的要求）。

### 6.2 跨 ABI 不可验证

本机只有 `C:\Ruby40-x64` 一个 Ruby（222 报告 §6-1）。`Gem.extension_api_version` 的真值、`-static` 后缀（我方模板 `commands_install.cr:1063-1071`）、非 MRI 引擎（JRuby/TruffleRuby）全部未验证。缓解：`abi.source=derived` 时**禁止**跨 ABI 复用（`resolution.cr:170-173` 的推导值只在本机 MRI 上恰好等于 `ruby_api_version`，不等于 `extension_api_version`）；F1 拿到真值后 `abi.source=real` 才允许持久化命中的 ABI 段。判据只能 spec 注入，不能声称「已跨 ABI 验证」。

### 6.3 持久化缓存的并发与损坏

- 半写：靠 temp+rename；Windows 上 rename 不覆盖目标，需 delete 后再 rename，其间存在窗口（读者可能 miss，不会读到半写）。
- 并发写同一 digest：两个进程各写各的 temp，最后 rename 者胜；两者内容应等价（同一指纹），但 `created_at` 不同 → GC 以 mtime 为准即可。
- 损坏来源：磁盘满、杀进程、手工编辑、跨版本格式漂移。缓解：§3.3 的五道校验；任何异常只导致 miss，不冒泡到命令。
- 目录权限/只读 HOME：写失败静默降级为「无持久化」，不得改变退出码。
- 残余：`runtime.exe` 原地同尺寸替换（重装同版本 ruby 到同路径）会漏判 ABI 变化——缓解是 `CELERITE_EVAL_CACHE=strict` 模式下每次 spawn 校验 ABI 并回写锚，或干脆让 L164 的零 spawn 路径承担该风险并在兼容声明中写明。

### 6.4 指纹漏项导致错误命中（最危险）

后果不是慢，而是**静默产出与参考不同的依赖图/锁文件**，且差分可能因为夹具简单而全绿。已知漏项：任意 Ruby 形态（A5）、gemspec 的副作用（B3）、插件钩子对 Gemfile 的改写（F1/F2）、非 `BUNDLE_` 前缀的 ENV（C9）。缓解：① 三态默认偏保守——扫描到任何动态 token 即 unknown，不放行；② 插件目录存在即 unknown，直到 F1 落地并有用例；③ 每次命中重算 verify，不信任条目的「自称」；④ 提供 `CELERITE_EVAL_DEBUG=1` 打印 `hit/miss + 首个不符字段`，让差分失败可定位；⑤ 新增「毒化矩阵」测试：对 26 项输入逐个做「只改这一项」的变异，断言全部 miss（一项没 miss 就是漏项）。

## 7. 不做的事

- **不做 L165**（`docs/roadmap.md:165`）：持久化解析/安装计划缓存本体、source 身份与 checksum 键、build 配置键都不在本行。本行只提供「求值结果还能不能用」的指纹与条目格式；两层共用同一 `RubyEnvironment` 快照，靠 `runtime.*` 字段对账（222 报告 §3.4）。
- **不做 L164**（`docs/roadmap.md:164`）：无 Ruby 快路径、零 spawn 判定、`lock`/`install` 短路都不在本行。F4 默认关闭，正是为了不把「未验证的零 spawn」变成默认行为。
- **不做 L161 S3**：插件声明并入 batch 需要第二次 DSL 执行（`server.rb:317-323` 注释已说明），属另一条线；本行的 `plugins.*` 字段由索引读取得到，不复用插件求值。
- **不做 L166**：Rails 规模基准、YJIT 对照不在本行（§6.1 只声明不可验证）。
- **不做 Gemfile 沙箱/完备静态判定**：不实现 Ruby 子集解释器，不承诺「静态分析覆盖所有 Gemfile」；只做保守扫描 + 三态。
- **不做跨机共享缓存**：条目含绝对路径与 `runtime.exe` 锚，天然不跨机；不设计签名/迁移，也不把缓存目录纳入仓库。
- **不把内容哈希当键**：`gemfile.sha256` 只是指纹的一个字段（`docs/roadmap.md:162` 的明确禁止项）。

## 8. 本轮实测与推断边界

- 读码实测（已核对行号）：`src/celerite/bridge/client.cr`、`src/celerite/resolution.cr`、`src/celerite/cli.cr`、`src/celerite/definition.cr`、`src/celerite/config.cr`、`src/celerite/profile.cr`、`assets/bridge/server.rb`、`src/celerite/cli/commands.cr`、`src/celerite/cli/commands_install.cr`、`src/celerite/cli/commands_surface.cr`、`docs/roadmap.md` 的相关段落。
- 运行时实测：0 次（未编译、未跑 spec、未跑差分）。本机是否有第二个 Ruby 未探测。
- 推断（未跑，需实现后取证）：F1-F5 的收益数字、verify 集成本、Windows rename 覆盖行为、`RUBYOPT`/`RUBYLIB` 对 Gemfile `require` 的实际影响、`mode=unknown` 在真实 Gemfile 上的触发率。
- 222 报告的参考侧行号（`dsl.rb`、`ruby_dsl.rb`、`plugin.rb`、`definition.rb`、`bundler.rb` 等）为**转引**，本轮未复读参考源。
