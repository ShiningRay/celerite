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
