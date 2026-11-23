# M8 起点盘点：批次桥接与无 Ruby 快路径

## 2026-11-24：M8 起点盘点（task-217）

盘点对象：`docs/roadmap.md` §M8（第 155 行）6 项任务 + 第 168 行验收标准。工作树 `3fd7a8d`，只读盘点，未改 `src/`、`spec/`、`fixtures/`。

测量环境（下文所有实测数字共用）：Windows x64，`ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [x64-mingw-ucrt]`，`celerite` profile `4.0.24`（`bin/celerite.exe --version` → `4.0.24`，本地 `shards build` 产出 12,790,825 B）。夹具：`C:\temp\t217-probe\app`，`Gemfile` 仅 `source "https://rubygems.org"` + `gem "rake"`（1 个依赖，**不是 Rails 规模**）。

计数手段：把 `assets/bridge/server.rb` **复制到仓外**（`C:\temp\t217-probe\server-trace.rb`），在 `bridge_dispatch` 入口注入一行日志（pid / op / payload 字节数），用 `CELERITE_BRIDGE_SERVER` 指向该副本。仓内文件未改。因此下表的「Ruby 进程数」= 发出过 op 的不同 pid 数，是**下界**（启动后未发 op 的 ruby 不计）。

### 协议与 op 面

**`src/celerite/bridge/` 只有 `client.cr`（577 行）**，职责是单一：拉起 ruby 子进程 + 保持一条 JSON 行 RPC 通道。命令面、序列化、超时、错误映射全在这一个文件里。

- 进程拉起：`client.cr:232-250`，`ruby = ruby_exe || ENV['CELERITE_RUBY'] || "ruby"`（`client.cr:233`），`Process.new(ruby, [server], input: pipe, output: pipe, error: inherit, ...)`（`client.cr:241-246`）。
- server 定位：`client.cr:265-281`，`CELERITE_BRIDGE_SERVER` 优先，否则取可执行文件旁的 `assets/bridge/server.rb`。
- 请求：`client.cr:496-513`（一行 JSON，写完 flush）；响应：`client.cr:515-541`（另起 reader + select 超时，超时抛 `BridgeError 'Timeout'`）；协议/序号校验：`client.cr:560-574`（`ProtocolError 'response id mismatch: expected X, got Y'`）。
- 协议版本：`client.cr:8` `PROTOCOL=1` 与 `assets/bridge/server.rb:24` `BRIDGE_PROTO=1`；信封形状见 `server.rb:11-13`：`{proto,id,op,payload}` → `{proto,id,ok,result}` 或 `{proto,id,ok:false,error:{class,message,status}}`。非法 proto 由 `server.rb:956-970` 的主循环拒绝；未知 op 走 `server.rb:948-949` `UnknownOp`；任何异常在 `server.rb:952-953` 被兜住（`rescue Exception`，带 `status_code`），不会有进程级崩溃泄漏给客户端。

**`assets/bridge/` 三个文件，职责不同**，不可合并视之：

| 文件 | 职责 | 证据 |
| --- | --- | --- |
| `server.rb`（970 行） | 长驻 JSON 行 RPC 服务，20 个 `op_*` + `ping` | 分发表 `server.rb:925-950`，主循环 `server.rb:956-970` |
| `console_boot.rb`（72 行） | `celerite console` 的一次性 boot（`Bundler.require` + 起 irb），不是 RPC 通道 | 文件头注释 `console_boot.rb:3-10` |
| `plugin_command.rb`（73 行） | 一次性 helper：`--commands` 列插件命令/hook，或直接 exec 插件命令；独立进程以免污染 bridge 的 stdout | 文件头注释 `plugin_command.rb:2-9` |

**`op_*` 全集（20 个，按行号）**：`op_ruby_environment:122`、`op_evaluate_gemfile:174`、`op_gemspec_paths:227`、`op_bundler_cache_file:240`、`op_installed_specs:277`、`op_default_gem_spec:317`、`op_ssl_openssl_versions:349`、`op_ssl_probe:361`、`op_read_gem_spec:392`、`op_load_installed_spec:422`、`op_write_installed_spec:456`、`op_generate_bin_stubs:489`、`op_generate_plugins:535`、`op_build_extension:556`、`op_load_gemspec_dir_specs:614`、`op_load_gemspec_dir:641`、`op_exec_plugin_hook:698`、`op_plugin_source_specs:789`、`op_plugin_source_install:827`、`op_plugin_gemfile_eval:916`。

**载荷形状（代表性 4 个）**：

- `evaluate_gemfile`：`{gemfile}`。返回 `gemfile`、`dependencies[]`（每项 `{name, requirements, groups[], platforms[], autorequire, force_ruby_platform, gemspec_dev_dep, source}`，形状见 `server.rb:186-198`）、`sources[]`、`ruby`、`ruby_version`、`ruby_patchlevel`、`ruby_engine`、`ruby_engine_version`、`bundler_version`、`gemfile_sha256`（`server.rb:214`）、`warnings[]`。
- `installed_specs`：`{dir?}`（`client.cr:332-338`）。
- `read_gem_spec`：`{path}`（`client.cr:340`）；`load_installed_spec`：`{path}`（`client.cr:347`）。
- `build_extension`：`{gem_dir, destination, name, gem_path, target_rbconfig?, build_args?, build_jobs?, jobs_mode?}`（`client.cr:471-478`）；`exec_plugin_hook`：`{event, index_path, spec_name?, spec_full_name?, gemfile_path?}`（`client.cr:424-436`）。

**一次命令实际发了什么（实测）**：

| 命令 | 场景 | RPC | Ruby 进程 | 请求字节 | op 构成 |
| --- | --- | --- | --- | --- | --- |
| `lock` | 冷（需解析，联网取 metadata） | 6 | 1 | 76 | `evaluate_gemfile`×1, `bundler_cache_file`×1, `ruby_environment`×3, `installed_specs`×1 |
| `lock` | 无变化（锁已在、Gemfile 未动） | 2 | 1 | 68 | `evaluate_gemfile`×1, `bundler_cache_file`×1 |
| `install` | 首次真装（1 gem） | 27 | 2 | 2241 | `plugin_gemfile_eval`×1, `evaluate_gemfile`×2, `ruby_environment`×10, `bundler_cache_file`×1, `exec_plugin_hook`×4, `installed_specs`×1, `default_gem_spec`×1, `read_gem_spec`×4, `write_installed_spec`×1, `generate_bin_stubs`×1, `generate_plugins`×1 |
| `install` | 无变化重跑 | 18 | 2 | 1007 | `plugin_gemfile_eval`×1, `evaluate_gemfile`×2, `ruby_environment`×9, `bundler_cache_file`×1, `exec_plugin_hook`×4, `installed_specs`×1 |
| `check` | 已满足 | 8 | 6 | 310 | `evaluate_gemfile`×6, `ruby_environment`×1, `bundler_cache_file`×1 |
| `list` | 已安装 | 3 | 3 | 144 | `evaluate_gemfile`×3 |
| `show rake` | 已安装 | 4 | 3 | 146 | `evaluate_gemfile`×3, `ruby_environment`×1 |

顺序（由代码与实测共同确定）。`lock`：`Definition.build` → 校验/开关 → `Resolution.new`（`commands.cr:3054`）→ `evaluate_gemfile` → `bundler_cache_file` → 无变化时直接 close+改写 BUNDLED WITH，于是只有 2 个 op。`install`：`plugin_gemfile_eval`（`commands_install.cr:260-264`，先于一切）→ `evaluate_gemfile`（274）→ `ruby_environment`（282/287/299 反复调）→ `Resolution.new(..., bridge)`（293）→ 复用同一个 client 做 `installed_specs`/`read_gem_spec`/`write_installed_spec`/`generate_bin_stubs`/`generate_plugins`（`commands_install.cr:693/719/739` 等）。`check`：`evaluate_gemfile`（`commands.cr:1533`）→ 冻结分支再 `evaluate_gemfile`（1554）→ `validate_runtime!`（1570）→ `lockfile_groups`（1618）→ `filter_locked_specs_by_groups`（1623）→ 可选 PATH probe/heal（1670/1681）。

两处可去掉的浪费（不是设计如此，是调用点各开一进程）：无变化 `install` 仍发 `exec_plugin_hook`×4（Gemfile 没声明插件）、`ruby_environment`×9（`resolution.cr:806-811` 无 memo）。

### RPC 粒度

**PubGrub 循环里没有「逐候选版本跨桥」。** 跨桥的单位是 **gem 名字**，且同名只取一次：

- 取候选的回调是 `Proc(String, Array(Resolver::IndexSpec)) { index_specs_for(name) }`（`resolution.cr:1890-1893`）。
- 上层 `Resolver::ResolutionSource#all_specs` 记忆化：`@all_specs[name] ||= ...`，且只在 `@index[name]` 为空时才调 `@spec_fetcher`（`src/celerite/resolver/source.cr:204-217`，判空在 `:208-210`）。所以同一 name 在一次求解内只触发一次 fetcher。
- 但**一个 name 的首次取候选要串 3–4 个 op**：`index_specs_for`（`resolution.cr:946`）→ `local_index_specs`（`:813-858`，整体记忆化于 `:814`，调 `bridge.installed_specs(project_spec_dir)` 于 `:816`）→ `vendor_cache_specs`（`:871-893`，每个 `<name>-*.gem` 一次 `read_gem_spec`，`:876`）→ `prefer_local_candidates`（`:919-944`，每个 `specifications/*.gemspec` 一次 `load_installed_spec`，`:923`）→ `default_gem_index_spec`（`:982` 起，`default_gem_spec` 于 `:987`，结果存 `@default_gem_specs_cache`）。

**循环内其余跨桥点（按调用频率）**：

- `resolution.cr:1267` `index_specs_for(spec.name)`，在 `stale_locked_dependency_full_names` 内，按 locked spec 计。
- `resolution.cr:1622` `index_specs_for(locked.name)`，在 `incompatible_locked_spec_names` 内，**每个 locked spec 一次**。
- `resolution.cr:2193` `index_specs_for(name)`，在 `build_index` 内，按 root dependency 急取。
- `resolution.cr:1112-1113` `--local` 路径对同一 spec 重复 `index_specs_for` + `vendor_cache_specs`。
- `project_spec_dir`（`resolution.cr:806-811`）**每次调用**都 `bridge.ruby_environment`（`:807`，无 memo）；`make_source` 再调一次（`:1923`）。实测 `ruby_environment` 在一个 `lock` 里出现 3 次、一个 `install` 里 9 次。

**量级结论**：RPC 数 ≈ O(gem 名数 × 首个候选路径的 op 数) + O(locked spec 数) + O(`ruby_environment` 调用点)，**与候选版本数无关**。当前的真实倍数浪费不在「每版本一桥」，而在（a）同名多 op 重复（`ruby_environment` 无 memo、`installed_specs` 之外的多次探测）、（b）**每条命令按调用点开新进程**。进程侧的证：`src/` 内 `Bridge::Client.new` 共 **39 处**（`resolution.cr:329`、`commands.cr:1276/1339/1369/1397/1533/1554/1967/1992/2493/2666/2691/2729/2746/2791`、`commands_install.cr:266/1418/1504/1764/2078/2206`、`commands_surface.cr:135/519/611/1167/1524/1750/1799/1871/1980/2229/2417/2639/3075/3176/3479/3584`、`plugin_gemfile.cr:25`、`gemfile_warnings.cr:32`），零复用、零池化。实测最刺眼的一例：`check` 用 6 个进程做 6 次 `evaluate_gemfile`——**同一份 Gemfile 求值 6 遍**。

### 计数点

**现状：没有任何计数/统计开关。** 全部 `CELERITE_*` 环境变量为：`CELERITE_BRIDGE_SERVER`、`CELERITE_CLI_RETRY`、`CELERITE_CONSOLE`、`CELERITE_CONSOLE_BOOT`、`CELERITE_CONSOLE_GROUPS`、`CELERITE_DEBUG_RESOLVER`、`CELERITE_EXEC_COMMAND`、`CELERITE_LOCAL_PLATFORM`、`CELERITE_MAN_DIR`、`CELERITE_PLUGIN_COMMAND`、`CELERITE_PROFILE_BUNDLER_VERSION`、`CELERITE_REFERENCE_BUNDLER_LIB`、`CELERITE_REFERENCE_BUNDLER_VERSION`、`CELERITE_RUBY`、`CELERITE_SOLVER_DEBUG`、`CELERITE_VERBOSE`。其中 `CELERITE_VERBOSE` 只在 `commands.cr:57-60` 置位、`commands.cr:1597` 消费（`print_debug_reason`），不含进程/RPC/字节；`--verbose`/`-V` 见 `commands.cr:25`、`:45-58`、`:273-293`，只回显命令。

**最小可加计数点（3 处，全在 `client.cr`，不改任何命令文件即可拿到三项指标）**：

1. **Ruby 进程数**：`client.cr:241`（`Process.new` 前后各一次自增；每个 `Client` 恰好一个 ruby）。
2. **RPC 次数 + 请求字节**：`client.cr:496-513`，序列化那一行就是 `line = JSON.build ... ; @stdin.puts(line)`，`line.bytesize` 现成可取。
3. **响应字节**：`client.cr:515-541`（`read_response` 里刚从 `@stdout.gets` 拿到的 raw `line`）。

输出通道需要新增开关（建议 `CELERITE_BRIDGE_STATS=1`）：命令写的是固定 stdout，统计行应走 stderr，并只在 env 打开时输出，格式 `bridge: procs=N rpc=M req_bytes=X resp_bytes=Y`，一行、稳定排序，便于夹具断言。

**零源码改动的替代探针**（本次实测所用，可用于 M8 期间的临时基线）：复制 `server.rb` 到仓外、分发表入口注入一行日志，`CELERITE_BRIDGE_SERVER` 指过去。缺点是数不到「启动了但未发 op」的 ruby，且注入副本与真本存在漂移风险，只宜做过渡。

### 指纹与缓存

**求值指纹：不存在。** 全仓 `fingerprint` / `cache_key` 无命中；`digest`/`etag` 只有两处，且都跟 Gemfile 求值无关：

- compact-index 的 HTTP 缓存：`src/celerite/compact_index/cache.cr:212-284`（`write_etag:259`、`etag_from_response:272`）。
- 安装期 checksum：`Digest::SHA256`（`commands_install.cr:605-609`、`commands_surface.cr:348-349`）。

`GemfileEvaluation` **带着** `gemfile_sha256`（`client.cr:216`，服务端 `server.rb:214`），但没有任何消费者拿它做 cache key——它只是被序列化着，白带。

**求值结果是一次导出还是分批**：**一半一半，且当前一次命令要 3 个 op 才拼齐**。

- 已由单个 `evaluate_gemfile` 一次导出：`dependencies`（含 `groups`/`platforms`/`autorequire`/`source`）、`sources`、ruby 约束（`ruby`/`ruby_version`/`ruby_patchlevel`/`ruby_engine`/`ruby_engine_version`）、`bundler_version`、`gemfile_sha256`（`server.rb:174-223`）。
- 仍需另发：**被引用的 gemspec**（`gemspec_paths`，`server.rb:227-238`，返回 `{gemspecs:[loaded_from], warnings}`）、**插件声明**（`plugin_gemfile_eval`，`server.rb:916`）。

**持久化 resolution / install-plan 缓存：不存在**（`docs/roadmap.md:165` 要求的键——source 身份、凭据隔离 id、checksum、platform、Ruby ABI、build config——一个都没有落地）。

### 无 Ruby 快路径

**现状：`lock` / `install` 在「Gemfile 未变、锁已完整」时仍然启动 Ruby，没有任何零 Ruby 分支。**

- `lock`：`run_lock`（`commands.cr:2946`）在 **`:3054` 先** `Resolution.new(definition, unlock)`，而「无需解析」的短路判定在 **`:3085-3090`**（`checksum_refresh` / `--update` / `--add-checksums` / `--normalize-platforms` / `dependency_sources_changed?` / `path_specs_changed?` / `incomplete_locked_spec_names` / `lockfile_matches_dependencies?` / `lockfile_platforms_cover_local?`）。命中后 `:3091` close、`:3097` 改 `BUNDLED WITH`、`:3107-3108` 打印并写盘。而 `Resolution#initialize`（`resolution.cr:326-334`）无条件 `@bridge = @bridge || Bridge::Client.new`（`:329`）与 `@evaluation = eval_gemfile`（`:332`，实现于 `:381-382` 调 `bridge.evaluate_gemfile`）。实测：无变化 `lock` = 1 个 ruby、2 个 RPC。
- `install`：`commands_install.cr:266` 无条件 `Bridge::Client.new`，`:274` `evaluate_gemfile`，`:282` `RubyRuntime.validate_version!`，`:293` `Resolution.new(definition, false, bridge)`。实测：无变化 `install` = 2 个 ruby、18 个 RPC。

**要改成零 Ruby，两处结构性阻塞**（不是加一个 if 就完）：(a) 判定所需数据本身来自求值——`:3087`/`:3090` 吃的是 `resolution.evaluation.dependencies/sources`，判定必须先能脱离 Ruby 完成；(b) `lock` 打印的 `BUNDLED WITH` 取自 `resolution.bridge_bundler_version`（`:3097`、`:3101`），这个值也来自桥。所以「无 Ruby 快路径」必须先有本地可判定的求值指纹（M8-2）与本地 bundler 版本来源。

### 只读命令

**没有持久化的已安装 gem 索引；`check`/`list`/`show` 每次都重新求值 + 反复扫盘/起桥。**

- `check`（`commands.cr:1444` → `run_check:1520`）：有锁时 `:1533` 一次 `evaluate_gemfile`；冻结分支 `:1554` 再来一次；`:1570` `validate_runtime!`（→ `:1369`）；`:1618` `lockfile_groups`（→ `:2729` 新建 client）；`:1623` `filter_locked_specs_by_groups`（→ `:2790` **再调一次** `lockfile_groups`，`:2791` 再新建 client）；`:1670` PATH probe、`:1681` heal。实测 **6 进程 / 8 RPC / 6 次 Gemfile 求值**。
- `list`（`:1780`）：有锁时跳过 `Resolution`，但 `available_groups`（`:1769`）与 `lockfile_groups`（`:2728`，每次调用都 `Bridge::Client.new` + `evaluate_gemfile` + `close`，见 `:2729-2742`）仍起桥。实测 **3 进程 / 3 RPC**。
- `show`/`info`（`show_info:2020`）：bin 路径经 `read_gemspec_info_via_bridge`（`:2664`，新建 client 于 `:2666`）、`lookup_default_gem`（`:1965`→`:1967`）。实测 **3 进程 / 4 RPC**。
- 已安装判定本身也靠桥：`bridge.installed_specs` / `read_gem_spec` / `load_installed_spec`（`resolution.cr:816/876/923`），结果只活在进程内记忆化里，进程退即丢。

**附带发现的现存隐患**：桥不可用时 `check`/`list` **静默降级**。实测把 `CELERITE_RUBY` 指向不存在路径后：`lock` → exit 1 `celerite internal error: Error executing process: 'C:\\nonexistent-t217\\ruby.exe ...'`；`check` → **exit 0** 且输出 `The Gemfile's dependencies are satisfied`；`list` → **exit 0** 且正常列出 `rake (13.4.2)`。降级原因是 `lockfile_groups` 的 `rescue` 返回 `[] of String`（`commands.cr:2738-2739`），组过滤退化为 `["default"]`（`requested_groups_for:2760-2782`）。M8 若改复用/降级路径，这条 exit code 行为会被翻转。

### 本机可验证性

逐项判定（本机 = Windows，单 ruby 4.0.6，无 Rails 夹具）：

1. **批次/版本化求值协议（M8-1）**：**可做（单元级 + 结构级）**。`server.rb` 是独立 Ruby 脚本，可用 JSON 行直接驱动做金样；「一次导出完整求值面」可做 field-by-field 差分（新单 op 结果 vs 现 `evaluate_gemfile` + `gemspec_paths` + `plugin_gemfile_eval` 三 op 拼装）。性能无判据。
2. **求值指纹（M8-2）**：**可做（差分夹具级）**。反例矩阵逐项改一个维度——touch/改 `Gemfile`、改被 `eval_gemfile` 引用的文件、改被引用 gemspec、改被读取的 ENV、改 `config`、改 ruby 版本/ABI——每项必须使指纹变化并触发重算（可用探针数「是否出现 `evaluate_gemfile`」观测）。正向：全同则 RPC=0。
3. **桥复用 + idle 回收 + 超时 + 结构化错误 + 批次上限 + 计数（M8-3）**：**可做，但须先落计数**。没有计数（上节 3 处）就没有判据；有了以后「一次命令的 ruby 进程数」「idle N 秒后进程是否退出」「超时是否抛结构化错误」都是本机可断言的。
4. **无 Ruby 快路径（M8-4）**：**lock 可做、install 受限、check/list 不可用黑盒**。`lock` 可用 `CELERITE_RUBY=<不存在路径>` 做黑盒差分：现在必须 exit 1（已实测），改完后无变化 `lock` 必须 **exit 0 且 stdout 只含 `Writing lockfile to ...`**、锁文件逐字节不变。`install` 同理但更弱（install 还要落盘/校验，需先把 `commands_install.cr:274` 的求值移出必走路径；且「已安装」判定本身依赖桥）。`check`/`list` 因静默降级（见上），黑盒判据无效，只能靠计数。
5. **持久化 resolution / install-plan 缓存（M8-5）**：**可做（离线）**。同输入二次运行 RPC=0 或命中缓存；输出、锁文件、依赖集、文件内容、退出码逐字节相同；损坏缓存（截断 / 坏 JSON / 版本不符 / 键缺字段）必须安全回退且不污染。但「凭据隔离 id」的语义尚未定义，属设计先行项。
6. **只读命令复用已安装索引（M8-6）**：**部分可做**。冷/温/无变化三档的 wall/RPC/进程数、以及 `check`/`list`/`show` 输出与现基线逐字相同，本机可断言。**「Rails 规模 + 参考 Bundler + YJIT」的对比报告本机不可验证**（无 Rails 夹具、无参考侧基准脚本），只能标未验证。

### 实施顺序与回归面

**强依赖链**：计数 → 桥复用 → 求值指纹 → 无 Ruby 快路径 → 持久化计划缓存 → 基准报告。理由：没有计数则 1/4/5/6 全无判据；没有指纹则「Gemfile 未变」不可本地判定，快路径无法安全开门；没有复用则任何「RPC=0」类断言都会被别的调用点的噪声淹没。

建议顺序（含可并行）：

0. **先落计数（M8-3 的计数子项提前）**：`client.cr:241` / `:496-513` / `:515-541` + `CELERITE_BRIDGE_STATS`。它不改语义、风险最低，且立刻把 `check` 6 进程 / `list` 3 进程 / 无变化 `install` 18 RPC 固化成可回归的数字。
1. **桥复用**（单命令单桥 + 按求值复用 + idle 回收 + 结构化错误 + 批次上限）。收益：`check` 6→1、`list` 3→1、`install` 2→1，并顺带消掉 `ruby_environment`×9 这类重复。
2. **求值指纹**（依赖 1 提供的缓存落点）。
3. **无 Ruby 快路径**（`lock` 先、`install` 后）。必须排在 2 之后，否则「未变」不可判定。
4. **只读命令复用已安装索引**（依赖 1、2；与 3 无数据依赖，但同改 `commands.cr` 的 check/list 段，**建议串行**以免冲突）。
5. **持久化 resolution/install-plan 缓存**（最后；键设计含凭据/ABI，须先定稿）。
6. **性能对比报告**（最后；Rails 规模本机不可验证）。

**必须回归的 M7 面（改桥/复用/降级都会碰到）**：

- 桥本身：`spec/m7_bridge_autorequire_spec.cr`、`spec/m7_bridge_long_operations_spec.cr`。
- `check`：`m7_check_missing_dependency_spec.cr`、`m7_check_no_lockfile_spec.cr`、`m7_check_path_gemspec_spec.cr`、`m7_check_rewrite_spec.cr`、`m7_check_ruby_notice_spec.cr`。
- `lock`：`m7_lock_autoheal_spec.cr`、`m7_lock_gemfile_missing_spec.cr`、`m7_lock_missing_spec_row_spec.cr`、`m7_lock_options_spec.cr`、`m7_lock_progress_spec.cr`、`m7_lock_rewrite_fidelity_spec.cr`、`m7_lock_spec_row_heal_spec.cr`、`m7_lock_switches_spec.cr`。
- 锁文件：`m7_lockfile_conflict_spec.cr`、`m7_lockfile_line_endings_spec.cr`、`m7_lockfile_locked_deps_spec.cr`、`m7_lockfile_regen_spec.cr`、`m7_path_lockfile_relative_spec.cr`、`m7_source_lock_options_spec.cr`。
- `list` / `show`：`m7_list_format_spec.cr`、`m7_list_groups_plain_env_spec.cr`、`m7_list_pristine_no_lock_spec.cr`、`m7_show_bundler_path_spec.cr`、`m7_show_group_filter_spec.cr`、`m7_show_listing_spec.cr`、`m7_show_no_lockfile_spec.cr`、`m7_show_order_spec.cr`、`m7_show_verbose_spec.cr`。
- 其余相邻：`m7_no_lockfile_commands_spec.cr`、`m7_frozen_lock_validation_spec.cr`、`m7_frozen_nolockfile_message_spec.cr`、`m7_frozen_ruby_unlock_spec.cr`、`m7_install_after_lock_keeps_transitive_spec.cr`、`m7_install_keeps_lock_with_bundler_edge_spec.cr`、`m7_install_lock_dep_order_spec.cr`、`m7_checksums_trigger_spec.cr`、`m7_checksum_normalize_spec.cr`、`m7_process_lock_spec.cr`、`synthetic_scale_lock_spec.cr`。
- 夹具：`spec/fixtures/bridge/`、`spec/fixtures/locked-deps/`、`spec/fixtures/gem-template/`、`spec/fixtures/lockfile_rubygems_4.0.24.lock`（其余 m7 spec 自带临时目录夹具）。
- 优先回归理由：`check` 的静默降级（`commands.cr:2738-2739` 的 `rescue → [] of String`）与 `lockfile_groups` 每调用一次就新建 ruby（`:2728-2743`）是 M7 已验收行为的一部分；复用/降级一旦改动，exit code 与组过滤输出会翻。

### 未验证

- **未跑 `crystal spec`**（本单只读，未改源码；预算内未跑全量套件）。`shards build` 成功产出 `bin/celerite.exe`（profile 4.0.24，12,790,825 B），仅用于测量，未提交。
- **Rails 规模、参考 Bundler 的性能/内存/RSS 对比、YJIT 开关差异**：未做，本机无对应夹具与基准脚本。
- **Ruby ABI 维度只覆盖 4.0.6 一个版本**；`2.7.2` profile 的 op 顺序与进程数未测（探针只跑了 4.0.24 profile）。
- op 序列与计数来自**注入日志的 `server.rb` 副本**（`C:\temp\t217-probe\server-trace.rb`，仅多一行日志），未逐分支验证与真本等价；因此上表「Ruby 进程数」是**下界**。
- 无变化 `install` 的 `exec_plugin_hook`×4 来自哪 4 个调用点未逐个定位（`server.rb:698` 的 op 已确认，调用方未逐一核对）。
- `console` / `exec` / 插件命令路径的 op 面未盘（不属本单 8 问）。
- 未检查 `docs/compat-report.md`（按令不引用其行号）。
