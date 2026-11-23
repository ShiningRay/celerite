# M8 L161 盘点：版本化批次级求值协议

对象：`docs/roadmap.md:161`

> - [ ] 定义版本化、批次级求值协议：一次导出完整 dependencies、groups、source、autorequire、platform、Ruby 约束和插件声明；一次提交完整候选集并返回解，禁止在 PubGrub 循环中逐版本跨桥。

相关验收（`docs/roadmap.md:168`）：无变化 lock/install 的 Ruby 启动次数为零（明确需要 Ruby 的 source/插件除外）；缓存复用前后输出、依赖、文件内容与退出码一致。

任务 task-224，只读盘点。工作树 `C:\temp\celerite-t224`，HEAD `96941b3`；未改 `src/`、未跑 `script/differential`、未 push。文中行号均对应该 HEAD。

## 0. 结论速览

1. **RPC 面 21 个 op**：20 个 `op_*` 加内联 `ping`，分发一张表 `assets/bridge/server.rb:925-950`。协议只有 `PROTOCOL = 1`（`src/celerite/bridge/client.cr:8-9`）与 `BRIDGE_PROTO = 1`（`assets/bridge/server.rb:24`）的双向严格相等；两个文件里 `capabilit` / `handshake` **零命中**，即无能力协商、无握手、无版本区间。
2. **七类数据已到齐五类**：dependencies、groups、source、autorequire、Ruby 顶层约束由 `op_evaluate_gemfile`（`server.rb:174-223`）一次导出；platform 只到「依赖声明的平台」层，**运行平台**在 `op_ruby_environment`（`server.rb:122`）；**插件声明**根本不在这里，另发 `op_plugin_gemfile_eval`（`server.rb:916-923`）；每个 gem 的 `required_ruby_version` 只能从 `op_installed_specs`（`server.rb:277`）或索引行拿到。
3. **「禁止在 PubGrub 循环中逐版本跨桥」当前事实上已成立**，没有待改的桥调用：solver 只做内存过滤（`src/celerite/resolver/solver.cr:609`、`:618-619`、`:630-631` → `src/celerite/resolver/source.cr:353`），候选按 **gem 名** 一次性取回并记忆化（`source.cr:204-217`，`@sorted_versions` 于 `source.cr:350`），索引走 Crystal 侧 compact-index HTTP（`resolution.cr:1020`），`src/celerite/resolver/` 内没有任何 `Bridge::Client`（桥只以注入的标量参数出现，`source.cr:77-81`）。
4. **调用次数已经不是旧基线的样子**：`check` 已满足场景本轮实测 `procs=1 rpc=2 req_bytes=182 resp_bytes=1698`；`install` 无变化 `procs=1 rpc=9`（`docs/compat-evidence/2026-11-23.md:3177`）。旧盘点表（`docs/roadmap-evidence/M8-batch-bridge.md:44-47`：check 6 进程 8 RPC、install 无变化 18 RPC）是桥复用落地前的历史值，不能再当现状引用。
5. **因此 L161 的收益不在减 check 的 RPC**（2 次都是必需数据：求值 + Ruby 环境），而在三处结构性收益：把分散在 3 个 op、由不同调用点各自拼装的求值面收成单一真相源；协议版本化（op 面变更时不再靠一个整数常量硬碰）；把 `install` 无变化的 9 次压到 8 次（`plugin_gemfile_eval` 与 `evaluate_gemfile` 合并）。
6. **建议方案**：`proto` 升 2，`ping` 响应加 `features` 数组（不新增 op）；新增 `evaluate_batch`，作为 `evaluate_gemfile` 的**向后兼容超集**（字段名不动，按 `include` 追加 `gemspecs` / `plugins`）；L161 后半句「一次提交完整候选集并返回解」**不实现**——Celerite 的 PubGrub 在 Crystal 侧，Ruby 侧没有求解器，没有消费者（详见 §3）。

## 1. 当前 RPC 面与调用次数

### 1.1 客户端方法与服务端 op 对照

信封形状（`server.rb:11-13`）：请求 `{"proto":1,"id":N,"op":"...","payload":{...}}`；成功 `{"proto":1,"id":N,"ok":true,"result":{...}}`；失败 `{"proto":1,"id":N,"ok":false,"error":{"class":..,"message":..,"status":..}}`。

| # | 客户端方法（`src/celerite/bridge/client.cr`） | op | 服务端实现（`assets/bridge/server.rb`） | 入参 → 出参摘要 |
| --- | --- | --- | --- | --- |
| 1 | `ping` :493 | `ping` | 内联 :927 | `{}` → `{proto, ruby}` |
| 2 | `ruby_environment` :500 | `ruby_environment` | :122 | `{}` → 20 字段（`ruby_version`/`platform`/`default_gem_dir`/`loaded_bundler_version`/`openssl_*` 等，结构 `client.cr:190`） |
| 3 | `evaluate_gemfile` :504 | `evaluate_gemfile` | :174-223 | `{gemfile}` → `GemfileEvaluation`（13 字段，`client.cr:323`） |
| 4 | `plugin_source_specs` :521 | `plugin_source_specs` | :789 | `{gemfile, remote}` → 插件源物化索引 |
| 5 | `plugin_source_install` :530 | `plugin_source_install` | :827 | `{gemfile, remote, full_name, bundle_root}` → `String?` |
| 6 | `gemspec_paths` :541 | `gemspec_paths` | :227-238 | `{gemfile}` → `{gemspecs:[loaded_from], warnings}` |
| 7 | `installed_specs` :552 | `installed_specs` | :277 | `{dir?}` → 全部可见 spec（含 `required_ruby_version`/`required_rubygems_version`/`from_dir`） |
| 8 | `read_gem_spec` :560 | `read_gem_spec` | :392 | `{path}` → 单 gem 元数据 |
| 9 | `load_installed_spec` :567 | `load_installed_spec` | :422 | `{path}` → 单 gemspec |
| 10 | `default_gem_spec` :577 | `default_gem_spec` | :317 | `{name, version?}` → 默认 gem 元数据 |
| 11 | `ssl_openssl_versions` :611 | `ssl_openssl_versions` | :349 | `{}` → OpenSSL 版本面 |
| 12 | `ssl_probe` :622 | `ssl_probe` | :361 | 探针参数 → 结果 |
| 13 | `write_installed_spec` :636 | `write_installed_spec` | :456 | 安装后的 spec 落盘 |
| 14 | `exec_plugin_hook` :644 | `exec_plugin_hook` | :698 | `{event, index_path, spec_name?, spec_full_name?, gemfile_path?}` → `{status, plugin, message, paths, missing}` |
| 15 | `plugin_gemfile_eval` :660 | `plugin_gemfile_eval` | :916-923 | `{gemfile_path}` → `{plugin_names:[...]}` |
| 16 | `generate_bin_stubs` :665 | `generate_bin_stubs` | :489 | 生成 binstub |
| 17 | `generate_plugins` :672 | `generate_plugins` | :535 | 生成插件索引 |
| 18 | `load_gemspec_dir` :676 | `load_gemspec_dir` | :641 | `{dir, glob?, name?}` → 按 gemspec 自身名字匹配 |
| 19 | `load_gemspec_dir_specs` :685 | `load_gemspec_dir_specs` | :614 | `{dir, glob?}` → `{specs:[{name,version}]}` |
| 20 | `build_extension` :691 | `build_extension` | :556 | `{gem_dir, destination, name, gem_path, target_rbconfig?, build_args?, build_jobs?, jobs_mode?}` |
| 21 | `bundler_cache_file` :700 | `bundler_cache_file` | :240 | `{}` → Bundler 工具路径 |

错误映射：服务端把任何异常兜成 `{class, message, status?}`（`server.rb:952-953`），客户端还原 `BridgeError#error_class` 与 `#status_code`（`client.cr:797-798`）；未知 op → `UnknownOp`（`server.rb:949`）；proto 不符 → `ProtocolError`（`server.rb:965-967`、`client.cr:787-788`）。

### 1.2 一次命令实际发了多少

本轮实测（Windows x64；二进制 `C:\temp\celerite-t224\bin\celerite.exe` 12,866,071 B，`--version` → `4.0.24`；夹具 `.tmp-scratch\probe\app`，Gemfile 为 `source "https://rubygems.org"` + `gem "rake"`，锁文件 rake 13.4.2；`CELERITE_BRIDGE_STATS=1`）：

```text
--version   bridge: procs=0 rpc=0 req_bytes=0 resp_bytes=0
check       bridge: procs=1 rpc=2 req_bytes=182 resp_bytes=1698   (exit 1，rake 不在 bundle path)
```

历史同口径表（桥复用落地后，`docs/compat-evidence/2026-11-23.md:3171-3177`）：

| 命令 | 场景 | procs / rpc | req / resp bytes |
| --- | --- | --- | --- |
| `check` | 已满足 | 1 / 2 | 185 / 1785 |
| `list` | 已安装 | 1 / 1 | 129 / 655 |
| `show rake` | 已安装 | 1 / 2 | 185 / 1785 |
| `lock` | 无变化 | 1 / 2 | 205 / 776 |
| `install` | 无变化 | 1 / 9 | 1719 / 286367 |

`check` 的 2 次 RPC 落点（读码，与实测数吻合）：

- `commands.cr:1533` `evaluate_gemfile`（第 1 次，真实 RPC）；
- `commands.cr:1570` `validate_runtime!` → `:1375` → `:1345` 再求值（`EvaluationCache` 命中，`client.cr:509-511`，不发 RPC）+ `:1348` `ruby_environment`（第 2 次，进程内 memo `client.cr:501`）；
- `commands.cr:1376` `.platform`、`:1618` `lockfile_groups`（`:2728-2743`）、`:1623` `filter_locked_specs_by_groups`（`:2784-2809`）都只命中缓存，不发 RPC。

`install` 无变化的 9 次推定构成（**推定，未逐 op 实测**，见 §7）：`plugin_gemfile_eval` ×1（`commands_install.cr:260-264` → `plugin_gemfile.cr:27`）+ `evaluate_gemfile` ×1（`:274`）+ `ruby_environment` ×1（`:282`/`:287`/`:299` 共用 memo）+ `bundler_cache_file` ×1（`resolution.cr:388`）+ `installed_specs` ×1（`resolution.cr:822`，`@installed_local_specs ||=` 于 `:820`）+ `exec_plugin_hook` ×4（`plugin_hooks.cr:85`，单调用点按事件各发一次，无插件时服务端回 `skipped`）= 9。

## 2. 求值结果的完整性缺口（按 L161 的七类数据）

`op_evaluate_gemfile`（`server.rb:174-223`）当前的返回面：读文件 `:183` → 收集警告 `:184` → 逐依赖 `:186-198` → `sources` `:205` → `ruby` `:206` → `ruby_version` `:209` → `ruby_patchlevel` `:210` → `ruby_engine` `:211` → `ruby_engine_version` `:212` → `bundler_version` `:213` → `gemfile_sha256` `:214` → `warnings` `:221`。

| L161 的数据类 | 状态 | 字段与出处 | 缺口 / 现在由谁补 |
| --- | --- | --- | --- |
| dependencies | 完整 | `dependencies[].name` / `.requirements`（`server.rb:186-198`，结构 `client.cr:226`） | 无 |
| groups | 完整 | `dependencies[].groups`；空数组语义为 `default`（消费方 `commands.cr:2734`、`:2797`） | 无 |
| source | 完整 | `dependencies[].source`（`client.cr:239`）+ 顶层 `sources`（`server.rb:205`）；`serialize_source` 覆盖 Rubygems/Git/Path/Metadata/Plugin（Plugin 分支给 `type/plugin_type/remote/lock_options/name`） | 无；但 `sources[]` 里没有 `revision`（`resolution.cr:599` 显式给 `nil`） |
| autorequire | 完整 | `dependencies[].autorequire`（`client.cr:236`，`server.rb:186-198` 内） | 无 |
| platform | **部分** | 仅「依赖声明的平台」`dependencies[].platforms`（`client.cr:232`） | 运行平台 = `op_ruby_environment` 的 `platform`（`server.rb:122`，消费点 `commands.cr:1376`、`commands_install.cr:287`）。一次导出里拿不到，必须第二次 RPC 或合并 |
| Ruby 约束 | **部分** | 顶层 `ruby`/`ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`（`server.rb:206-212`） | 每个 gem 的 `required_ruby_version`/`required_rubygems_version` 不在求值结果里：只能从 `op_installed_specs`（`server.rb:277`）或索引行（`resolver/source.cr:228` 过滤时用）拿 |
| 插件声明 | **未返回** | 无 | `op_plugin_gemfile_eval`（`server.rb:916-923`）另发一次，返回仅 `plugin_names`，且要求插件已安装；插件**源**的 spec 还要 `op_plugin_source_specs`（`server.rb:789`） |
| （附）被引用的 gemspec | 未返回 | 无 | `op_gemspec_paths`（`server.rb:227-238`）另发，`{gemspecs:[loaded_from], warnings}` |

「谁在补」的调用点证据：

- `gemspec_paths` 只有 1 个消费者：`commands_surface.cr:1275`（`show`/`info` 类），不在 `check`/`install` 路径上。
- `plugin_gemfile_eval` 只有 1 个消费者：`plugin_gemfile.cr:27`，由 `commands_install.cr:260-264` 在 `PluginGemfile.enabled?` 为真时调用（`plugin_hooks.cr:61-69`：`plugins` 未配置即视为启用，所以**默认会发**）。
- `installed_specs` 在解析期被 `resolution.cr:822` 调一次（全名共用的 memo `:820`），与「取候选」共用。
- 结论：**今天没有任何一条命令同时需要 `evaluate_gemfile` + `gemspec_paths` + `plugin_gemfile_eval` 三家**。三 op 拼装是「求值面分散」的证据，不是「某条命令多付 2 次 RPC」的证据。

## 3. 候选集与 PubGrub 的跨桥模式

**独立复核结论：跨桥单位是 gem 名，不是候选版本；同名在一次求解内只取一次。** 逐层证据：

1. solver 只调三个入口，且全部是内存操作：`solver.cr:609`（`most_preferred_version_of`）、`:618`、`:619`；`:630-631` 是该 helper 内部对 `versions_for` 的一次调用。
2. `versions_for`（`source.cr:353`）读 `@sorted_versions[package] ||= filtered_versions_for(package).sort`（`:350`），自身不再触碰 fetcher。
3. 真正取数据的是 `all_specs(name)`（`source.cr:204-217`）：`@all_specs[name] ||= begin ... end`（`:205`），且**只有** `index.nil?` 且有 fetcher 时才调用（`:208`）——同名第二次进不来。
4. fetcher 的接线在 `resolution.cr:1893-1899`：`Proc(String, Array(Resolver::IndexSpec)) { index_specs_for(name) }` → `make_source(..., fetcher)`。所以 fetcher 的参数是 `String`（gem 名），签名层面就不接受版本。
5. `index_specs_for`（`resolution.cr:952-983`）三条腿：本地（`local_index_specs`，整体 memo 于 `:820`，一次 `installed_specs` 覆盖所有名字，`:822`）、vendor cache（`:862`）、远端索引（`index_specs_from_remote`，memo `@index_specs_cache[name] ||=` 于 `:1017-1018`，HTTP 取数 `client.info(name)` 于 `:1020`——**Crystal 侧的 compact index 客户端，不是桥**）。
6. `src/celerite/resolver/` 内没有 `Bridge::Client`：命中的 `bridge` 字样都是注入的标量（`source.cr:77-81` 的 `@bridge_ruby_version` 等五个参数，`:321-336` 只读它们）。

**一次 `install` 的 9 次 RPC 里，来自「索引候选获取」的只有 1 次**（`installed_specs`，`resolution.cr:822`）。其余 8 次与候选集无关：`evaluate_gemfile`（`commands_install.cr:274`）、`plugin_gemfile_eval`（`:261`）、`ruby_environment`（`:282`/`:287`/`:299` 与 `resolution.cr:813` 共用）、`bundler_cache_file`（`resolution.cr:388`）、`exec_plugin_hook` ×4（`plugin_hooks.cr:85`）。

残余的跨桥点不在 PubGrub 循环里，但按 **gem** 计费，值得在设计时点名：

- path / git 源的 gemspec 扫描：`load_source_gem_spec`（`resolution.cr:613-630`）每次调用都发 `load_gemspec_dir`（`:617`），**没有客户端 memo**；同一 path 源被多个依赖引用时会重复扫盘。
- 锁文件陈旧检测：`load_gemspec_dir_specs`（`resolution.cr:1468`）按 PATH 段各发一次。

这两处与 L161 的后半句无关（都不是「逐版本」），但属于「一次导出」应该顺带覆盖的求值面。

## 4. 协议版本化现状与最小落点

**现状：只有版本号，没有协商。**

- 常量：`client.cr:8-9` `PROTOCOL = 1`；`server.rb:24` `BRIDGE_PROTO = 1`。
- 双向硬相等：客户端在 `client.cr:787-788` 校验响应 `proto`，不等即 `BridgeError("ProtocolError", "unsupported bridge proto ...")`；服务端在 `server.rb:965-967` 校验请求，不等即 `bridge_error(id, "ProtocolError", ...)` 并 `next`（连接不断，下一条请求继续处理）。
- 响应恒回常量：`server.rb:951` `bridge_emit("proto" => BRIDGE_PROTO, ...)`，`bridge_error` 同（`:34`）。所以服务端无法表达「我能说 1 也能说 2」。
- 无能力面：`capabilit` / `handshake` 在两文件零命中；`ping`（`server.rb:927`）只回 `{proto, ruby}`，客户端 `ping`（`client.cr:493-496`）只读 `ruby` 字段——现成的协商通道空着没用。

**最小落点（不新增 op）：**

| 落点 | 文件:行号 | 改什么 |
| --- | --- | --- |
| 版本常量 | `src/celerite/bridge/client.cr:8-9` | `PROTOCOL = 2`；保留 `PROTOCOL_MIN = 1` 供降级判断 |
| 版本常量 | `assets/bridge/server.rb:24` | `BRIDGE_PROTO = 2`；加 `BRIDGE_PROTO_SUPPORTED = [1, 2]` |
| 请求校验 | `assets/bridge/server.rb:965-967` | 由 `==` 改为 `SUPPORTED.includes?`，接受 1 与 2 |
| 响应回显 | `assets/bridge/server.rb:951`、`:34` | 回显**请求的** proto（而不是常量），使老客户端收到 1、新客户端收到 2 |
| 响应校验 | `src/celerite/bridge/client.cr:787-788` | 接受 `1..PROTOCOL`；`>PROTOCOL` 仍报 `ProtocolError`（文案不变，便于既有断言） |
| 能力声明 | `assets/bridge/server.rb:927` + `client.cr:493-496` | `ping` 结果加 `features: ["evaluate_batch", ...]`；客户端 `ping` 返回结构体而非裸 `String` |

**向后兼容策略：同装具内不需要握手，理由有三条，都可核。**

1. 客户端与服务端同仓同版本：server 路径由可执行文件旁定位（旧盘点 `docs/roadmap-evidence/M8-batch-bridge.md:16`，`client.cr:265-281` 的实现未变），`celerite.exe` 与 `assets/bridge/server.rb` 一起发布，不存在「新客户端配旧服务端」的发行场景。
2. 唯一可能的错配是 `CELERITE_BRIDGE_SERVER` 指向外部副本（调试/过渡探针用，旧盘点 `:83` 的用法）——这时 `features` 列表已足够：**缺 feature 就当不支持**，走现有 op，不猜版本。
3. 严格相等已经保证「无法静默错配」：不是协议不兼容，而是**没有降级路径**——`proto` 加一就必须同时改两侧。握手只是把这件必须做的事变成可选，不解决任何现存缺陷。

**结论**：做「版本常量 + `features` 声明」即可；**不做**握手协商（协议层无状态复制成本）。真正的兼容负担在 op 语义（`evaluate_batch` 必须是超集），不在握手。

## 5. 批次协议设计草案

### 5.1 载荷形状

新增 op `evaluate_batch`（第 22 个），语义是 `evaluate_gemfile` 的**超集**：顶层字段名、类型、形状一律沿用 `GemfileEvaluation`（`client.cr:323`、`server.rb:174-223`），只追加可选的段。这样老消费方可以继续用 `GemfileEvaluation.from_json` 读同一份响应，新消费方读追加字段。

请求：

```json
{
  "gemfile": "C:/proj/Gemfile",
  "include": ["gemspecs", "plugins", "warnings"]
}
```

| 字段 | 类型 | 必选 | 说明 |
| --- | --- | --- | --- |
| `gemfile` | string | 是 | 绝对路径；相对路径由客户端先 expand（现 `evaluate_gemfile` 同） |
| `include` | array<string> | 否 | 取值 `"gemspecs"` / `"plugins"` / `"warnings"`；缺省 = 只给 `evaluate_gemfile` 现有面（等价旧 op） |
| `include` 里的未知值 | — | — | 忽略并在 `features` 里不回填，客户端据此判定降级 |

响应（`result` 内）：

```json
{
  "gemfile": "C:/proj/Gemfile",
  "dependencies": [
    { "name": "rake", "requirements": ["~> 13.0"], "groups": ["default"],
      "platforms": [], "autorequire": null, "force_ruby_platform": false,
      "gemspec_dev_dep": false, "source": { "type": "Rubygems", "remotes": ["https://rubygems.org/"] } }
  ],
  "sources": [ { "type": "Rubygems", "remotes": ["https://rubygems.org/"] } ],
  "ruby": ">= 3.0",
  "ruby_version": ">= 3.0",
  "ruby_patchlevel": null,
  "ruby_engine": null,
  "ruby_engine_version": null,
  "bundler_version": "4.0.24",
  "gemfile_sha256": "…",
  "warnings": [],
  "gemspecs": ["C:/proj/proj.gemspec"],
  "plugins": ["my-plugin"],
  "features": ["evaluate_gemfile", "gemspecs"],
  "runtime": { "platform": "x64-mingw-ucrt", "ruby_version": "4.0.6" }
}
```

| 追加字段 | 类型 | 可选性 | 说明 |
| --- | --- | --- | --- |
| `gemspecs` | array<string> \| null | include 含 `gemspecs` 才出现 | 等价 `op_gemspec_paths` 的 `gemspecs`（`server.rb:227-238`） |
| `plugins` | array<string> \| null | include 含 `plugins` 才出现 | 等价 `op_plugin_gemfile_eval` 的 `plugin_names`（`server.rb:916-923`）；插件不可用时为 `null` 且 `features` 不含 `plugins` |
| `features` | array<string> | 恒出现 | 本次**实际填满**的段；缺省面恒含 `evaluate_gemfile` |
| `warnings` | array<string> | 恒出现（沿用） | 与旧 op 同一收集器（`server.rb:184`），不重复记账 |
| `runtime` | object \| null | include 含 `runtime` 才出现（建议延后） | `ruby_environment` 的 `platform`/`ruby_version` 子集；合并进 batch 可把 `check` 的 2 次 RPC 降到 1 次，但会让「求值」与「环境」两个生命周期不同的数据同帧，**建议单独切片评估** |

`gemfile_sha256` 必须在 batch 里同样返回：`EvaluationCache` 的命中判据依赖它复核磁盘字节（`client.cr:112-120`），C-M8-1-002 已把这一行为固定，batch 不得绕过。

### 5.2 错误形状

完全复用现有信封，不新增字段：

```json
{"proto":2,"id":N,"ok":false,"error":{"class":"Bundler::GemfileError","message":"…","status":4}}
```

- `class` 原样映射到 `BridgeError#error_class`（`client.cr:797-798`）。
- `status` 保留案号：Gemfile / DSL 错误必须是 4 或 15，`check` 依赖这两个值决定是否上抛（`commands.cr:1535`）。
- `include` 中某段失败但主求值成功时，**不报错**：该段为 `null`、`features` 缺该段。理由：现有调用点对「拿不到」的处理是静默降级（`commands.cr:2738-2739`、`plugin_gemfile.cr` 的 `rescue`），batch 若改成硬失败会翻转 exit code——这正是 `docs/roadmap-evidence/M8-batch-bridge.md:119` 记录的隐患，不能扩大。
- 未知 op / proto 不符的错误类不变（`UnknownOp` / `ProtocolError`）。

### 5.3 「一次导出 + 一次候选集提交」的边界条件

| 场景 | 边界 | 降级路径 |
| --- | --- | --- |
| 动态 DSL | Gemfile 是任意 Ruby：`eval_gemfile`、`source ... do`、`if ENV[...]`、`install_if`、gemspec 里的条件依赖。结果只能由真实执行得到 | 不做静态解析、不做跨命令缓存（缓存留给 M8-2 的求值指纹）；batch 与旧 op 在同一进程里执行同一份代码，结果必须逐字段相等 |
| 插件 | `op_plugin_gemfile_eval` 需要插件已装；未装时该段失败 | `plugins: null` + `features` 缺 `plugins`，调用方走旧 op（`plugin_gemfile.cr:27`），退出码不变 |
| path / git 源 | gemspec 要扫盘（`op_load_gemspec_dir` 每次枚举 glob，`resolution.cr:617` 无 memo） | `gemspecs` 只承担 Gemfile 里被**引用**的 gemspec 路径（旧 `gemspec_paths` 语义）；path/git 源的 spec 扫描**留在独立 op**，不进 batch——否则 batch 的耗时与 Ruby 侧 I/O 不可控 |
| 需要 gemspec 扫描的项目 | 有 `gemspec` 声明的项目，`gemspec_paths` 要读 `Dir` 并 `load` | 同上：include 才做；不做时 `features` 缺 `gemspecs`，消费方退回 `op_gemspec_paths` |
| 「一次提交完整候选集」 | 需要 Ruby 侧有求解器接收候选集并返回解 | **不实现**：Celerite 的 PubGrub 在 Crystal（`src/celerite/resolver/`），Ruby 侧只有元数据读取与安装能力；`all_specs` 已按名记忆化（§3），不存在逐版本跨桥。若未来把求解下放到参考 Bundler，才需要 `solve_batch`，届时载荷为 `{candidates:[{name, versions:[...]}], constraints:[...]}`，与本协议解耦 |

## 6. 切片与判据

依赖顺序 S1 → S2 → S3 → S4（S3 依赖 S2 的 `include` 机制；S4 依赖 S2/S3 落地后才测得出数字）。四片都可独立验收，都不需要全量差分。

### S1 协议版本号与能力声明（不改语义）

- 目标：`proto` 2 + `ping.features`，两侧都能读 1 与 2。
- 改动面：`client.cr:8-9`、`:493-496`、`:787-788`；`server.rb:24`、`:34`、`:927`、`:951`、`:965-967`。
- 判据：`proto` 不匹配仍抛 `ProtocolError`（文案不变）；新客户端对新服务端 `ping` 拿到 `features`；`CELERITE_BRIDGE_SERVER` 指向旧副本时按「缺 feature」降级而不是崩。
- 差分：不需要。RPC/字节计数变化会被 `bridge:` 行体现，但语义不变。
- 风险：低。唯一实质风险是把 `:951`/`:34` 的「回常量」改成「回请求值」时漏改一处，导致客户端读到自己不认识的 proto。
- 最小可验证证据：新 spec（放 `spec/m8_bridge_proto_spec.cr`）直接驱动 `server.rb` 的 JSON 行：发 `proto:1` 期望回 `proto:1`，发 `proto:2` 期望回 `proto:2`，发 `proto:3` 期望 `ProtocolError`；再加一条 `ping` 的 `features` 断言。现有 `spec/m8_bridge_stats_spec.cr`、`spec/bridge/client_spec.cr` 必须仍绿。

### S2 `evaluate_batch` 合并求值面（无插件、无 gemspec 项目）

- 目标：一次 RPC 拿到 `evaluate_gemfile` 全字段；`include:["gemspecs"]` 时附带 `gemspecs`。
- 改动面：`server.rb` 新增 `op_evaluate_batch`（分发表 `:925-950` 加一行）+ 复用 `op_evaluate_gemfile` 与 `op_gemspec_paths` 的内部函数；`client.cr` 新增方法（`GemfileEvaluation` 结构扩可选字段或并列读 `gemspecs`）。
- 判据：字段级金样——同一 Gemfile 上用 `server.rb` 直连，`evaluate_batch` 结果与「旧 `evaluate_gemfile` + 旧 `gemspec_paths`」逐字段相等（`warnings` 顺序也一致）；`include` 缺省时与旧 op 输出**逐字节同形**（可断言 `JSON.build` 后字符串相等）。
- 差分：可选。若把 `commands_surface.cr:1275` 切到 batch，则 `show` 类命令要跑 `script/differential` 的相关夹具（本机受 §7 限制）。
- 风险：中。求值缓存（`client.cr:509`）与 batch 的组合要先想清楚：batch 响应同样带 `gemfile_sha256`，缓存仍按「绝对路径 + ENV 签名 + 摘要复核」判命中，否则会重现 `m7_add_strict_write_spec` 的等长改写坑（`docs/compat-evidence/2026-11-23.md:3184-3186`）。
- 最小可验证证据：`crystal spec spec/m8_batch_eval_spec.cr`（新）：真起 bridge、对 `spec/fixtures/bridge/` 下带 gemspec 的夹具跑 batch 与双 op 拼装，断言两棵 JSON 树相等；并用 `CELERITE_BRIDGE_STATS=1` 断言「2 次 op → 1 次 op」。

### S3 插件声明并入 batch

- 目标：`include:["plugins"]` 时一次返回 `plugins`；无插件/插件缺失时 `null` + `features` 缺段。
- 改动面：`server.rb` 的 `op_evaluate_batch` 内复用 `op_plugin_gemfile_eval`（`:916-923`）逻辑；客户端在 `commands_install.cr:260-264` 改为一次 batch。
- 判据：`install` 无变化场景 `procs=1 rpc=8`（现为 9，见 §1.2）；stdout/stderr（除 `bridge:` 行）/退出码/`Gemfile.lock` 字节与改动前逐字相同；插件缺失时行为与现在一致（不新增失败）。
- 差分：需要（`install` 输出面）。可用既有夹具离线跑，不依赖 8765 端口的全量差分。
- 风险：中。插件求值会**重新执行 Gemfile**（`plugin_gemfile.cr:24-31`），把它并进 batch 后同一请求内可能执行两次 DSL；必须确认副作用（`GemfileWarnings` 记账、插件 hook 的 `index` 写盘）没有重复——`GemfileWarnings.record` 的「命中不重复记账」约束（`client.cr:505-513`）要延伸到 batch。
- 最小可验证证据：`spec/m7_6_*`/`spec/m7_*plugin*` 相关文件回归 + 一条 `CELERITE_BRIDGE_STATS=1` 的 install 计数断言；现有 `spec/m8_bridge_reuse_spec.cr` 的计数用例（`procs=1`）必须仍绿。

### S4 调用点收口与计数回归

- 目标：`check`/`install` 的求值面只走 batch，计数与基线逐项对齐并写进对照表。
- 改动面：`commands.cr:1533`/`:1555`/`:1345`/`:2731`/`:2793`（求值点）、`commands_install.cr:274`（`plugin_gemfile_eval` 与求值合并）。只改「走哪个 op」，不改任何判定分支。
- 判据：五项命令（`check`/`list`/`show`/`lock` 无变化/`install` 无变化）的 `procs`/`rpc` 不高于 §1.2 表；stdout、除 `bridge:` 行外 stderr、退出码、`Gemfile.lock` 字节全部不变（沿用 task-221 的对照口径，`docs/compat-evidence/2026-11-23.md:3179`）。
- 差分：需要（`check` 的组过滤与降级路径）。`check` 的 `rescue → [] of String` 降级（`commands.cr:2738-2739`）必须原样保留。
- 风险：高（触碰 `check` 的静默降级与 `lockfile_groups` 的失败语义）。这是唯一可能翻转 exit code 的切片，建议最后做、单独提交。
- 最小可验证证据：`spec/m8_bridge_reuse_spec.cr` + `spec/m8_bridge_stats_spec.cr` + `m7_check_*` 全家族；再加一条「`CELERITE_RUBY` 指向不存在路径时 `check` 仍 exit 0」的回归用例（固定 `M8-batch-bridge.md:119` 记录的现状）。

## 7. 本机不可验证项

- **真实网络**：本轮所有测量都走本地夹具与已装 gem，未对 rubygems.org 拉过索引；`index_specs_from_remote`（`resolution.cr:1015-1059`）的失败/重试路径未验证。
- **`script/differential` 全量差分**：按令禁用（端口 8765 被另一任务占用）。S2/S3/S4 的「输出逐字相同」只能靠已有离线夹具与自比，未与参考 Bundler 同页对比。
- **Rails 规模**：无 Rails 夹具（依赖数、多 source、大锁文件、插件），本机测不出批次协议在真实项目上的 RPC/耗时收益。
- **跨 ABI**：只有 `ruby 4.0.6 [x64-mingw-ucrt]` 一个 ABI；`2.7.2` profile、Linux/macOS 下的 op 顺序与计数未测，`platform` 差异对 batch 的影响未验证。
- **`install` 无变化的 9 次 RPC 的 op 级拆分**：本节 §1.2 是读码推定，未用注入日志的 `server.rb` 副本重新采样（task-217 的探针法可做，本轮预算内未做）。因此「9→8」的收益数字属**待实测**。
- **并发**：共享连接按连接串行（C-M8-1-002 边界已声明「不声明多 fiber 并发复用安全」），batch 的并发行为同样未验证。
- **参考 Bundler 侧**：参考实现没有「批次求值协议」这个可观测面，也没有对应 oracle；本协议的判据只能是自比（新旧 op 等价）+ 输出不变，不能声称与参考行为一致。
