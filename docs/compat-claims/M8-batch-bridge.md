# M8 批次桥接断言

`docs/roadmap.md` §M8（批次桥接与无 Ruby 快路径）的兼容性与测量断言。

## C-M8-1-001 桥统计计数：CELERITE_BRIDGE_STATS 开启时输出 procs/rpc/req_bytes/resp_bytes 一行

- 状态：已实现
- 参考行为（4.0.24）：参考 Bundler 没有对应开关，`--verbose` 只回显命令，不提供 Ruby 进程数、RPC 次数或传输字节计数；本项是测量设施，不对参考行为作兼容声明
- 我方行为：`src/celerite/bridge/client.cr:15-56` 的 `BridgeStats` 在 `Client` 成功 `Process.new` 时计进程（`:299`）、请求行写入并 flush 后计 RPC 与请求字节（`:560`）、`IO#gets` 读到响应行后计响应字节（`:574`）；`src/celerite/cli.cr:25` 在每次 `CLI.run` 开始时复位，`:46` 在该入口的 `ensure` 向 stderr 输出恰好一行 `bridge: procs=<N> rpc=<M> req_bytes=<X> resp_bytes=<Y>`，stdout 不变
- 判据：`crystal spec spec/m8_bridge_stats_spec.cr`
- 边界：开关未设、空串或 `"0"` 时关闭且无任何输出，其它非空值开启也未开启时一样不改变 op 语义、错误映射、超时与协议版本；只统计 `Bridge::Client` 拉起的 Ruby 进程（`console_boot.rb`/`plugin_command.rb` 等一次性进程不计，`Process.new` 失败不计）；`req_bytes`/`resp_bytes` 是含行尾换行的线上字节，不是 payload 字节；计数按一次 `CLI.run` 复位，不做跨调用累计
- 生效：M8 期间
- 取代：无

## C-M8-1-002 桥复用：一次命令单进程、idle 回收可配置、同一求值不重复

- 状态：已实现
- 参考行为（4.0.24）：参考 Bundler 在 Ruby 进程内完成 check/list/show，没有可切换的"进程复用"开关，也没有多进程计数输出；本项是我方进程结构与求值次数的内部约束，不改变对参考输出的兼容承诺——输出、退出码、锁文件内容仍须逐字一致
- 我方行为：`src/celerite/bridge/client.cr:423` 的 `Client.shared` 以 `:472` 的 ENV 签名作键持有进程级共享连接；无显式参数的 `Bridge::Client.new` 全部改为 `Bridge::Client.shared`（`src/celerite/cli/commands.cr`、`commands_surface.cr`、`commands_install.cr`、`gemfile_warnings.cr`、`plugin_gemfile.cr`、`resolution.cr` 共 39 处），`close`（`:710`）对共享句柄只归还管道；`src/celerite/cli.cr:47` 在 `CLI.run` 的 `ensure` 统一 `Client.shutdown`；`CELERITE_BRIDGE_IDLE_MS`（`:455`，未设/空/非法/`<=0` = 不回收）到期后由 `:464` 判定过期并 `dispose`（`:486`），下次取用时重建；`ruby_environment` 在 `:501` 做进程内 memo（一次命令一次 RPC）；`src/celerite/bridge/client.cr:81` 的 `EvaluationCache` 在 `CLI.run` 期间（`src/celerite/cli.cr:26`、`:48`）缓存 `GemfileEvaluation`，键为 gemfile 绝对路径 + ENV 签名，命中前在 `:112` 复核磁盘字节的 `Digest::SHA256` 与 bridge 返回的 `gemfile_sha256`（`:118`），不一致即重新求值；命中不重复 `GemfileWarnings.record`（首次求值已记账，`:504` 只在未命中时记录）；`src/celerite/resolution.cr:812-817` 的 `project_spec_dir` 加 memo（算得 `nil` 也缓存）
- 判据：`crystal spec spec/m8_bridge_reuse_spec.cr`（check/list 的 `procs=1`、`CELERITE_BRIDGE_IDLE_MS=1` 时后续取用 `procs>1`、关闭 stats 后 stderr 无 `bridge:` 行且 stdout 与开启时逐字相同）；`crystal spec spec/m8_bridge_stats_spec.cr`；改动前后五项计数对照表见 `docs/compat-evidence/2026-11-23.md` 的 2026-11-24 节
- 边界：只复用无显式参数的连接，`Client.new(ruby_exe:/server_path:/timeout:)`（`spec/m7_bridge_long_operations_spec.cr`、`spec/spec_helper.cr`）仍是独立进程；ENV 签名变化（`BUNDLE_GEMFILE`/`BUNDLE_PATH` 等临时改写）即弃旧建新，语义与逐次新建一致；求值命中以文件内容摘要为判据，命令中途改写 Gemfile（`add` 追加 gem 后 install）必然重新求值，`spec/m8_bridge_reuse_spec.cr` 的改写用例固定该行为；`rescue` 静默降级分支原样保留（`lockfile_groups` → `[] of String`、`filter_locked_specs_by_groups` → 原 specs）；`check` 冻结分支仍有第二次求值，文件未变时命中缓存、诊断数据不变；输出、退出码、锁文件内容不变；共享取用加锁但 `request` 仍按连接串行，不声明多 fiber 并发复用安全
- 生效：M8 期间
- 取代：无

## C-M8-1-003 桥协议版本区间与 `ping.features` 能力声明

- 状态：已实现
- 参考行为（4.0.24）：参考 Bundler 没有 JSON Lines 桥，也没有协议版本或能力声明面；版本区间与 `features` 是我方自有内部协议，不对参考行为作兼容声明，参考侧只约束「命令输出、退出码、锁文件内容不变」
- 我方行为：`src/celerite/bridge/client.cr:14-15` 发 `PROTOCOL = 2`、接受 `PROTOCOL_MIN..PROTOCOL`（=1..2）的响应，越界仍抛 `ProtocolError("unsupported bridge proto …")`（`client.cr:812-815`，文案与升级前逐字相同）；`assets/bridge/server.rb:32-34` 的 `BRIDGE_PROTO = 2`、`BRIDGE_PROTO_SUPPORTED = [1, 2]`，`:41` 的 `BRIDGE_FEATURES = [evaluate_gemfile, gemspec_paths, plugin_gemfile_eval]`；请求校验改为整数 + 区间判定（`server.rb:982-990`），成功与失败信封都回显请求自带的 `proto`（`server.rb:48-51`、`:968`），`ping` 结果带 `proto`（回显）与 `features`（`server.rb:944`）；客户端 `ping` 返回 `Bridge::Ping{ruby, features}`（`client.cr:350-362`、`:519-521`），`features` 缺失即空集合、非字符串元素逐个跳过（`client.cr:357-361`）
- 判据：`crystal spec spec/m8_bridge_proto_spec.cr`——直驱 `server.rb` 的 JSON 行断言 proto 1 回 1、proto 2 回 2、proto 3 与 0 报 `ProtocolError`（文案 `unsupported proto 3` / `unsupported proto 0`）、`UnknownOp` 错误信封同样回显请求版本、`features` 为数组且只含已实现的 op；旧副本缺 `features` 时 `ping.features` 为空、`lock` 的退出码与 `Gemfile.lock` 字节不变。回归：`crystal spec spec/bridge/client_spec.cr`
- 边界：只接受整数 `proto`（非整数同样 `ProtocolError`）；越界请求的错误信封发 `2`——对端读不懂的信封无法携带错误，只能发本服务端最高版本；`features` 只列**本进程真能服务**的 op，`evaluate_batch` 属 L161 S2/S3，实现前不声明（提前声明会让「探测 feature 再调用」直接变成 `UnknownOp`），留待该切片同时加 op 与 `BRIDGE_FEATURES` 条目；「旧服务端兼容」特指副本缺 `features` 键但仍接受 `proto 1..2`，真正的 v1 副本（`BRIDGE_PROTO = 1` 严格相等）仍会拒绝 `proto 2` 并以 `ProtocolError` 失败——那是升级前就存在的边界，本切片不加握手、不猜版本；`features` 不参与任何命令分支，不改输出、退出码与锁文件内容；不声明多 fiber 并发协商
- 生效：M8 期间
- 取代：无
