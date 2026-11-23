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
- 我方行为：`src/celerite/bridge/client.cr:403` 的 `Client.shared` 以 `:452` 的 ENV 签名作键持有进程级共享连接；无显式参数的 `Bridge::Client.new` 全部改为 `Bridge::Client.shared`（`src/celerite/cli/commands.cr`、`commands_surface.cr`、`commands_install.cr`、`gemfile_warnings.cr`、`plugin_gemfile.cr`、`resolution.cr` 共 39 处），`close`（`:687`）对共享句柄只归还管道；`src/celerite/cli.cr:47` 在 `CLI.run` 的 `ensure` 统一 `Client.shutdown`；`CELERITE_BRIDGE_IDLE_MS`（`:435`，未设/空/非法/`<=0` = 不回收）到期后由 `:443` 判定过期并 `dispose`（`:466`），下次取用时重建；`ruby_environment` 在 `:481` 做进程内 memo（一次命令一次 RPC）；`src/celerite/bridge/client.cr:76` 的 `EvaluationCache` 在 `CLI.run` 期间（`src/celerite/cli.cr:26`、`:48`）以 gemfile 绝对路径 + 大小 + mtime 缓存 `GemfileEvaluation`，`evaluate_gemfile`（`:485`、`:491`）命中时仍执行 `GemfileWarnings.record`；`src/celerite/resolution.cr:812-817` 的 `project_spec_dir` 加 memo（算得 `nil` 也缓存）
- 判据：`crystal spec spec/m8_bridge_reuse_spec.cr`（check/list 的 `procs=1`、`CELERITE_BRIDGE_IDLE_MS=1` 时后续取用 `procs>1`、关闭 stats 后 stderr 无 `bridge:` 行且 stdout 与开启时逐字相同）；`crystal spec spec/m8_bridge_stats_spec.cr`；改动前后五项计数对照表见 `docs/compat-evidence/2026-11-23.md` 的 2026-11-24 节
- 边界：只复用无显式参数的连接，`Client.new(ruby_exe:/server_path:/timeout:)`（`spec/m7_bridge_long_operations_spec.cr`、`spec/spec_helper.cr`）仍是独立进程；ENV 签名变化（`BUNDLE_GEMFILE`/`BUNDLE_PATH` 等临时改写）即弃旧建新，语义与逐次新建一致；`rescue` 静默降级分支原样保留（`lockfile_groups` → `[] of String`、`filter_locked_specs_by_groups` → 原 specs）；`check` 冻结分支仍有第二次求值，只是命中缓存，诊断数据不变；输出、退出码、锁文件内容不变；共享取用加锁但 `request` 仍按连接串行，不声明多 fiber 并发复用安全
- 生效：M8 期间
- 取代：无
