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
- 边界：只接受整数 `proto`（非整数同样 `ProtocolError`）；越界请求的错误信封发 `2`——对端读不懂的信封无法携带错误，只能发本服务端最高版本；`features` 只列**本进程真能服务**的 op；`evaluate_batch` 由 L161 S2 在实现 op 的同一批加入 `BRIDGE_FEATURES`（见 C-M8-1-004），提前声明会让「探测 feature 再调用」直接变成 `UnknownOp`；「旧服务端兼容」特指副本缺 `features` 键但仍接受 `proto 1..2`，真正的 v1 副本（`BRIDGE_PROTO = 1` 严格相等）仍会拒绝 `proto 2` 并以 `ProtocolError` 失败——那是升级前就存在的边界，本切片不加握手、不猜版本；`features` 不参与任何命令分支，不改输出、退出码与锁文件内容；不声明多 fiber 并发协商
- 生效：M8 期间
- 取代：无

## C-M8-1-004 `evaluate_batch` 合并求值面：单请求返回求值结果并按需追加 `gemspecs`

- 状态：已实现
- 参考行为（4.0.24）：参考 Bundler 没有 JSON Lines 桥，也没有「一次 RPC 返回多项求值产物」的接口；本项的等价对象是**本项目旧的两次 op 调用**（`evaluate_gemfile` + `gemspec_paths`），参考侧只约束「命令输出、退出码、锁文件内容不变」
- 我方行为：`assets/bridge/server.rb:282-296` 的 `op_evaluate_batch` 读 `payload["include"]`（非数组按空数组处理），只跑一次 `bridge_evaluate_gemfile`（`:196-208`，即 `bridge_activate_bundler` + 一个 `Bundler::Dsl#eval_gemfile`），用 `bridge_serialize_evaluation`（`:210-250`）产出与 `evaluate_gemfile` 逐键同序的对象，`include` 含 `"gemspecs"` 时在末尾追加 `"gemspecs" => builder.gemspecs.map(&:loaded_from)`（`:291`）；`op_evaluate_gemfile`（`:252-260`）与 `op_gemspec_paths`（`:262-268`）改为调用同一对内部函数，`gemspec_paths` 因此不再做第二次求值；分发表 `:985` 加 `when "evaluate_batch"`；`BRIDGE_FEATURES`（`:42`）加入 `evaluate_batch`；客户端 `src/celerite/bridge/client.cr:562-583` 的 `evaluate_batch(path, include:)` 返回 `BatchGemfileEvaluation{evaluation, gemspecs}`（`:350-358`，未请求的段保持 `nil`），`request`（`:785`）的 payload 类型放宽到含 `Hash(String, JSON::Any)` 以承载数组，信封不变
- 判据：`crystal spec spec/m8_batch_eval_spec.cr`——直驱 `server.rb` 的 JSON 行，同一离线夹具（含 `gemspec` 与两组重复 `gem` 声明）上断言：`include` 缺省时 `evaluate_batch` 结果与 `evaluate_gemfile` 结果**逐字节相同**；`include:["gemspecs"]` 时结果字节以旧结果为前缀、仅追加 `gemspecs`，其余字段与旧结果逐字段相等、`gemspecs` 与 `gemspec_paths` 相等、`warnings` 顺序一致（两条：`rake` 在前、`json` 在后）；`CELERITE_BRIDGE_STATS=1` 下旧「两次 op」计 2 次 RPC、batch 计 1 次。`crystal spec spec/m8_bridge_proto_spec.cr` 断言 `ping.features` 含 `evaluate_batch`
- 边界：只服务 `include:["gemspecs"]`；`include:["plugins"]` 留待 S3——插件声明走 `Bundler::Plugin::DSL`，在同一请求内并进来会让同一 Gemfile 执行第二次 DSL，重复 `GemfileWarnings` 记账与插件 hook 的写盘副作用，`op_plugin_gemfile_eval` 保持独立；未识别的 `include` 值被忽略而非报错（探测型调用方应降级到旧 op，不得整体失败）；`include` 缺省时结果对象与旧 op 逐字节相同，故不追加 `features`/`runtime` 等段（能力声明由 `ping.features` 承担，这是对 `docs/roadmap-evidence/M8-batch-protocol.md` §5.1 草案的刻意偏离）；带段的请求不经 `EvaluationCache`（缓存存的是求值结果而非段），无段请求与旧 `evaluate_gemfile` 同等吃缓存；本切片**不切换任何命令调用点**（属 S4），`check`/`install`/`show` 的计数与输出不变
- 生效：M8 期间
- 取代：无

## C-M8-1-005 `bundle list` 无组选择时不启动 Ruby 桥（plain 环境 procs=0）

- 状态：已实现
- 参考行为（4.0.24）：`cli/list.rb:19-29` 先 `Bundler.load.specs` 再按 `definition.rb:1251-1254` 的 `values = groups - without - optional + with`（`only` 非空时再取交集）过滤；`with`/`without`/`only` 与两个 group flag 全空时 `values` 等于全部组，`spec_set` 过滤是恒等变换。参考实现本身没有「是否启动 Ruby」这一可观测面，故本项不改任何参考可见输出，只改我方进程结构。
- 我方行为：`src/celerite/cli/commands.cr:1844` 计算 `groups_requested = !only_groups.empty? || !without_groups.empty? || group_settings_configured?(config)`；`:1845` 仅在为真时求值 `available_groups`（否则占位 `["default"]`，不参与输出），`:1853` 仅在为真时求值 `requested_groups_for`，`:1881-1889` 为假时 `filtered_specs = locked_specs`、为真时保留原 `begin/rescue` 静默降级；新增 `:2798-2804` 的 `group_settings_configured?`（按 `Config#[]` 转换后的值判空：`with`/`without`/`only` 未设时是 `[] of String`，其 `to_s` 为 `"[]"`，不能直接判字符串空），`:2809` 的 `filter_locked_specs_by_groups` 改为复用它，避免两处判定漂移。
- 判据：`crystal spec spec/m8_list_no_group_zero_spawn_spec.cr`——plain 环境（隔离 `HOME`/`USERPROFILE`/`TMP*`，不设 `CELERITE_BRIDGE_SERVER`/`CELERITE_REFERENCE_BUNDLER_LIB`）下 `CELERITE_BRIDGE_STATS=1` 时 `list`、`list --paths`、`list --name-only`、`list --format=json` 的 `bridge:` 行均为 `procs=0 rpc=0 req_bytes=0 resp_bytes=0`，`list --only-group default` 为 `procs=1`，未知组 `--only-group nope` 仍为 exit 15 与 `` `nope` group could not be found. ``；`Gemfile.lock` 字节前后不变。回归：`crystal spec spec/m7_list_format_spec.cr spec/m7_list_groups_plain_env_spec.cr spec/m7_only_group_spec.cr spec/m7_show_listing_spec.cr spec/m8_bridge_stats_spec.cr`。
- 边界：验收口径是 **plain 环境**；探针环境（设 `CELERITE_BRIDGE_SERVER`）下 `lock_ruby_unlock_kind`（`commands.cr:1396` 的 `bridge_available?` gate）与 `installed_gem_dir` 的 default-gem 分支（`commands_surface.cr:1749`）会照旧 spawn，`list` 仍为 `procs=1`。`--only-group`/`--without-group` 或 `BUNDLE_WITH`/`BUNDLE_WITHOUT`/`BUNDLE_ONLY`/`.bundle/config` 中任一生效即走旧路径，行为与改动前逐字一致；`available_groups`、未知组校验（`:1846-1851`）、`filter_locked_specs_by_groups` 的 `rescue` 降级、输出分支（`:1895-1944`）均未改动；`list` 本来就只读，不写 `Gemfile.lock`。
- 生效：M8 期间
- 取代：无

## C-M8-1-006 共享桥进程不得让求值沿用别的 op 先加载的 Bundler 版本；版本不符必须报结构化错误

- 状态：已实现
- 参考行为（4.0.24）：参考 `bundle` 在一个 Ruby 进程内先加载自己的 Bundler 再求值，进程内只有一个版本——`Bundler::VERSION` 是 `4.0.24`，锁文件 `BUNDLED WITH 4.0.24` 且 `CHECKSUMS` 带 `bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc` 自校验行（`fixtures/differential/checksums-refresh-cache-deleted/file-equals-4.0.24`），`install --verbose` 打 `Using bundler 4.0.24`。参考没有「同一进程先后加载两个 Bundler 版本」的面：`require "bundler"` 命中一次后不再重载。
- 我方行为：`assets/bridge/server.rb:67-96` 的 `bridge_activate_bundler` 幂等（`defined?(Bundler)` 即返回；`$LOAD_PATH` 已含该路径时不重复 unshift），`:1066` 在 `loop do`（`:1068`）之前调用一次，`:795` 的 `op_exec_plugin_hook` 与 `:1018` 的 `op_plugin_gemfile_eval` 在首个 `require "bundler"` 之前各调一次；`:114-125` 的 `bridge_ensure_bundler_version!` 在 `bridge_evaluate_gemfile`（`:237-241`）`require "bundler"` 之后校验 `Bundler::VERSION` 与 `CELERITE_PROFILE_BUNDLER_VERSION`（未设时回退 `CELERITE_REFERENCE_BUNDLER_VERSION`，`:104-112`），不符抛 `BundlerVersionMismatch`（`:98-99`），经既有 `bridge_dispatch` 错误信封报 `error.class = "BundlerVersionMismatch"`（消息 `Bundler version mismatch in the shared bridge process: loaded X / expected Y; refusing to evaluate with the wrong release`）。clients 侧未改。
- 判据：`crystal spec spec/m8_bridge_bundler_activation_spec.cr`——同一进程先 `plugin_gemfile_eval` 再 `ruby_environment`/`evaluate_gemfile`，断言 `loaded_bundler_version` 与 `bundler_version` 均为 `4.0.24`；`RUBYOPT=-rbundler` 预载宿主默认 Bundler（隔离 `GEM_PATH` 下为 `4.0.16`）后发 `evaluate_gemfile`，断言 `ok=false`、`error.class == "BundlerVersionMismatch"`、消息含 `loaded 4.0.16` / `expected 4.0.24`、无 `result`。离线端到端：`checksums-refresh-cache-deleted`、`install-ruby-constraint-locked-resolve`、`install-verbose-existing-lock` 用 `file://` 索引跑 `install`，修后 `BUNDLED WITH 4.0.24`、checksums 夹具含上述 `bundler (4.0.24) sha256=…` 行、锁与 `file-equals-4.0.24` 逐字相同、verbose 打 `Using bundler 4.0.24`；修前二进制（`5018400`）同流程为 `4.0.16` 且缺该行。见 `docs/compat-evidence/2026-11-23.md` 的 2026-11-24 节。
- 边界：v1 协议下桥进程启动即激活（`:1066`）；若宿主默认 bundler 已被前置加载（`RUBYOPT=-rbundler`、任何先于激活的 `require "bundler"`），报 `BundlerVersionMismatch` 而非静默求值。`CELERITE_PROFILE_BUNDLER_VERSION` 与 `CELERITE_REFERENCE_BUNDLER_VERSION` 都未设时不校验（旧调用点、`console_boot.rb` 等一次性进程不受影响）；`plugin_gemfile_eval`/`exec_plugin_hook` 只激活不校验——校验点设在求值路径，因为锁渲染与 verbose 文案都读求值结果的 `bundler_version`。校验只比版本号，不比对 lib 路径，也不切换已加载的 Bundler（`require` 已 no-op，换版本只能换进程）。
- 生效：M8 期间
- 取代：无

## C-M8-1-007 桥在一次求值内产出可复算的求值指纹（文本 + digest + verify 集）

- 状态：已实现
- 参考行为（4.0.24）：参考 Bundler 没有求值指纹、没有 JSON Lines 桥，也没有「求值输入规范文本 + 摘要」这一可观测面；本项是我方自有内部协议，不对参考行为作兼容声明，参考侧仍只约束命令输出、退出码与锁文件内容不变
- 我方行为：`assets/bridge/server.rb:295-400` 的 `bridge_fingerprint` 复用 `bridge_evaluate_gemfile`（`:240-248`）已产出的 `builder`/`contents`，不再执行 Gemfile；正文为 `celerite-eval-v1\n` + 定序 `key\tvalue\n` 记录（`fp.format`、`gemfile.path`、`gemfile.sha256`、`evalchain.count` 与逐项 `evalchain.<i>.path/sha256`、`gemspec.count` 与逐项 `gemspec.<i>.path/sha256`、`ruby.version/patchlevel/engine/engine_version`、`rubygems.version`、`bundler.version`、`platform`），`\\`/TAB/LF/CR 逐个转义（`:306-313`），路径 `File.expand_path` 后统一 `/`（`:317-320`）；`digest` 为 text 原始 UTF-8 字节的 SHA-256 hex64（`:397`）；`verify.files[]` 带 `role`（`gemfile|evalchain|gemspec`）、相对主 Gemfile 目录的 `path` 与 `sha256`（`:385-393`）；eval 链取 `Bundler::Dsl` 的 `@gemfiles`（`bundler/dsl.rb:328-336`）去掉主文件后排序去重（`:339-343`），gemspec 取 `builder.gemspecs.map(&:loaded_from)` 排序去重（`:345-349`）；仅 `include` 含 `"fingerprint"` 时 `op_evaluate_batch` 追加该段（`:446`），`BRIDGE_FEATURES`（`:45`）声明 `fingerprint` 能力供旧服务端降级；客户端 `src/celerite/bridge/client.cr:349-376` 的 `EvalFingerprint{text,digest,verify}` 与 `:364-375` 的 `parse`（缺字段/类型错返回 `nil`，不抛错），`BatchGemfileEvaluation`（`:383-390`）增可空 `fingerprint`，`evaluate_batch`（`:597-615`）从同一响应解析
- 判据：`crystal spec spec/m8_eval_fingerprint_spec.cr`——直驱 `assets/bridge/server.rb`（一进程一次请求，proto 取 `Celerite::Bridge::PROTOCOL`，payload `{"gemfile":…,"include":["fingerprint"]}`，离线夹具 `Gemfile` + `fingerprint_fixture.gemspec`）：V1 同输入两次 `text`/`digest` 相等且 `digest == SHA256(text)`；V2 改主 Gemfile 后 `digest` 变；V3+V9 只改 gemspec 后 `gemfile_sha256` 相等而 `digest` 不等；V4 改 `eval_gemfile` 目标后 `digest` 变且 `verify.files` 的 `evalchain` 项为相对路径 `nested/Gemfile.local`；V11 建删目录项改变目录 mtime 后 `digest` 不变；V12 gemspec 以 CRLF 与 LF 字节求值，`gemfile_sha256` 相等而 `digest` 不等；未请求或只请求未知段时结果无 `fingerprint` 键；客户端 `evaluate_batch(gemfile, ["fingerprint"])` 解析出非空 `fingerprint`，不带段时为 `nil`
- 边界：F1 只产出不缓存——不落盘、不读不写 `EvaluationCache`、不改任何 stdout/stderr/exit；带 `fingerprint` 的请求与带 `gemspecs` 的请求一样绕过进程内缓存（`client.cr:597-603` 仅空 `include` 才查缓存），缓存与失效语义见后续切片 F2-F4；旧服务端无该 feature 时客户端降级——`EvalFingerprint.parse` 对缺失/畸形段返回 `nil`，`BatchGemfileEvaluation.fingerprint` 保持可空，命令不因指纹段失败；正文只覆盖本切片能观测的输入（不含 rubyfile、config、env、plugins、mode），`verify` 只列主 Gemfile、eval 链与被引用 gemspec 的内容摘要，不含目录 mtime/ctime；路径不做大小写折叠与 realpath，内容按原始字节摘要（CRLF 不归一）；未识别 `include` 值继续忽略；不新增 op、不二次执行 Gemfile
- 生效：M8 期间
- 取代：无
