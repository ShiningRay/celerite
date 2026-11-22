# M7-suite 全量 `crystal spec` 的可运行性（claims）

本文件是 M7-suite 的断言账本：把 `../compat-evidence/2026-11-22.md` 与 `../roadmap-evidence/M7-suite.md` 里已取证的结论逐条固化为可复跑断言。本子项没有上游 oracle——比对对象是修复前后的同一套件与参考 Bundler 的语义；计数与运行时长归 `../compat-report.md` 的 Current metrics 表，不进断言。

## C-M7-suite-001 verbose 回显 spec 的实参对齐六参签名，全套件编译期失败消除

- 状态：已实现
- 参考行为（4.0.24）：参考每进程只执行一条命令，在构造期据 `settings[:verbose]` 定 UI 层级；本仓 `print_command_echo` 取六参，签名在 `src/celerite/cli/commands.cr:537` `def self.print_command_echo(command : String, rest : Array(String), verbose : Bool, flag_verbose : Bool,`（续行 `retry_value : String?, stdout : IO) : Nil`）
- 我方行为：只改 `spec/m7_verbose_echo_spec.cr:24`，调用改为 `Celerite::Commands.print_command_echo(stripped[0], stripped[1..], verbose, verbose, retry_value, io)`（第 3、4 实参同为 `verbose`）；`src/` 未改，未削弱或删除任何既有断言
- 判据：`crystal spec spec/m7_verbose_echo_spec.cr`
- 边界：修的是 spec 侧实参数量，不改变产品行为；判据本轮未执行，仅核实文件存在
- 生效：task-127（`ae1248c`）
- 取代：无

## C-M7-suite-002 spec 间 `BUNDLE_GEMFILE` 泄漏链已被 env 复原切断

- 状态：已实现
- 参考行为（4.0.24）：参考不共享进程内环境，不存在跨调用残留；同进程顺序跑多个 spec 是本实现的测试形态（`spec/spec_helper.cr:60` `def run_cli(args : Array(String)) : {Int32, String, String}` 驱动 `Celerite::CLI.run`），故每个 helper 必须自己复原所改环境
- 我方行为：`spec/m7_binstubs_path_source_spec.cr:36` `private def with_binstub_path_env(dir : String, & : ->) : Nil` 的 keys 列表 `:42` 含 `"BUNDLE_GEMFILE"`，`:57` 的 `saved.each { |key, value| value.nil? ? ENV.delete(key) : (ENV[key] = value) }` 在 ensure 中复原；`:69`/`:101`/`:124` 设置后由 `:88`/`:111`/`:132` 断言复原
- 判据：`crystal spec spec/m7_binstubs_path_source_spec.cr`
- 边界：只覆盖此文件的写出点；`spec/spec_helper.cr:56` 的 `FileUtils.rm_rf(dir)` 使泄漏值指向不存在路径，这一点靠复原而非清理解决；判据本轮未执行，仅核实文件存在
- 生效：task-129（`eed51d7`）
- 取代：无

## C-M7-suite-003 CLI 每次调用重算 verbose 与 retry 开关，不继承上一次调用

- 状态：已实现
- 参考行为（4.0.24）：参考每进程一条命令，在 `CLI#initialize` 内据 settings 定 UI 层级；本实现同进程可连续调用，故必须在入口重算而非仅在存在时写入
- 我方行为：`src/celerite/cli/commands.cr:45` `verbose_requested = args.includes?("--verbose") || args.includes?("-V")`，`:57-61` 未请求时 `ENV.delete("CELERITE_VERBOSE")`（`:308` `def self.verbose_debug? : Bool` 只读该变量）；retry 同类，`:68` `cli_retry = extract_retry_switch(args)`、`:82-85` 未请求时 `ENV.delete("CELERITE_CLI_RETRY")`
- 判据：`crystal spec spec/m7_cli_state_isolation_spec.cr`
- 边界：只覆盖 verbose 与 retry 两个每调用开关；其它跨调用状态未逐项复核；判据本轮未执行，仅核实文件存在
- 生效：task-128（`633c5f9`）
- 取代：无

## C-M7-suite-004 全量 `crystal spec` 在本机能跑到 `Finished` 汇总行

- 状态：已实现
- 参考行为（4.0.24）：无上游 oracle；判定标准是 Crystal spec 打印 `Finished in <t>` 汇总行，而非进程零退出
- 我方行为：仓库根执行 `crystal spec` 可跑完整套件并打印 `Finished` 汇总行；起点 `b99bf12` 的编译期一票否决已由 task-127 消除
- 判据：`crystal spec`
- 边界：**前提**是 `TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE` 指向工作区内，否则套件在编译/链接阶段即失败（`Cannot create temporary file in C:\WINDOWS\: Permission denied`）；判据本轮未执行；示例数与失败数见 `../compat-report.md` 的 Current metrics 表，本文件不记计数
- 生效：task-131（`3725a9a`）起，task-135（`a9b08c4`）复跑确认
- 取代：无

## C-M7-suite-005 `m7_clean` 的期望按参考 `use_system_gems?` 守卫更正为 exit 15

- 状态：已实现
- 参考行为（4.0.24）：`bundler-4.0.24/lib/bundler/cli/clean.rb:19-22` 的守卫 `return unless Bundler.use_system_gems? && !options[:force]` 不成立时 `raise InvalidOption`（exit 15）；`bundler-4.0.24/lib/bundler/settings.rb:260-264` 的 `use_system_gems?` 只看 `system_path`/`explicit_path`，无 `path` 配置即为真
- 我方行为：只改 `spec/m7_clean_spec.cr` 的期望与新增夹具，`src/` 未改；`:97`、`:159`、`:164` 断言 `code.should eq(15)`，`:146` 另加无 path 配置下连跑两次的幂等例；产品侧守卫在 `src/celerite/cli/commands_install.cr:1471` 的 `InstallPaths.use_system_gems?(definition.config, bridge.ruby_environment.default_gem_dir)`（`:921` 同类判定）
- 判据：`crystal spec spec/m7_clean_spec.cr`；`bash script/differential clean-no-path`
- 边界：只覆盖无 `path` 配置的守卫分支；有 `path` 配置时 clean 的正常删除路径由既有用例覆盖；判据本轮未执行，仅核实文件与夹具存在
- 生效：task-132（`fd549f0`）
- 取代：无

## C-M7-suite-006 `m7_show_order` 在参考 lib 缺席时记 `pending!`，不硬失败

- 状态：已实现
- 参考行为（4.0.24）：`bundler-4.0.24/lib/bundler/cli/show.rb:20-21` 用 `File.expand_path("../../..", __dir__)` 定位 gem 根；该路径只在 `spec/.upstream-specs/`（被 `.gitignore` 忽略）或已安装的 bundler gem 中存在
- 我方行为：只改 `spec/m7_show_order_spec.cr`，`src/` 未改；`:53` `private def show_order_pick_reference_lib(upstream : String, installed : String?) : String` 在 `:55` 返回 `installed || pending!("needs #{upstream} or an installed bundler 4.0.24 gem")`，`:175` 回落用例同样以 `pending!` 收尾
- 判据：`crystal spec spec/m7_show_order_spec.cr`
- 边界：参考 lib 缺席时该家族记 pending 而非红；参考 lib 在场时的断言由同一 spec 覆盖；判据本轮未执行，仅核实文件存在
- 生效：task-133（`1303546`）
- 取代：无
