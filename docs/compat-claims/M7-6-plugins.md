# M7-6 插件（claims）

插件子命令注册与命令分发、hook 事件注册与异常语义、自定义 source（typed plugin source）的求值 / 锁段 / 安装、第三方插件 fixture 与插件树物化。原始 oracle 与逐次复采见 `../compat-evidence/`，实证流水见 `../roadmap-evidence/M7-6-plugins.md`。

> 本轮（2026-11-22）**未能复跑任何判据**：工作树在执行中途失去 `.git`，且本机 msys `bash.exe` 报 `fatal error - couldn't create signal pipe, Win32 error 5`、`crystal build` 的 `sh -c` 探测被沙箱拒绝（`openssl/lib_crypto.cr:24` 编译期 `sh`）。下列「判据」的通过状态来自 `docs/compat-evidence/` 中记录的运行，不是本轮实测。

## C-M7-6-001 `plugin install --path` 把 plugins.rb 声明的命令写入项目索引 `commands:`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/index.rb:54-74 register_plugin` 把 `commands` 逐项登记为 `@commands[c] = name` 并 `save_index`；`lib/bundler/plugin.rb:309-340 register_plugin` 负责求值 `plugins.rb` 并交出 `spec.load_paths`
- 我方行为：桥探针一次取回声明后由 `src/celerite/plugin_commands.cr:106 declared` 归一，`src/celerite/cli/commands_surface.cr:2404` 起合并进索引 `commands:`（`write_plugin_index` 见 `:2923`）
- 判据：`crystal spec spec/m7_plugin_commands_spec.cr` 与 `bash script/differential plugin-command-list`
- 边界：命令声明来自一次独立 Ruby 进程（`assets/bridge/plugin_command.rb`），不是参考的进程内 `register_plugin`
- 生效：task-6（`5ec40bb`）
- 取代：无

## C-M7-6-002 索引中登记的插件命令先于 `bundler-<name>` PATH 回退分发

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli.rb:187-195 handle_no_command_error` 在未命中内置命令时先判 `Bundler.settings[:plugins] && Plugin.command?`，命中即 `Plugin.exec_command`，之后才回退 PATH 上的 `bundler-<name>`
- 我方行为：`src/celerite/cli/commands.cr:3955 dispatch_plugin_command` 在 PATH 回退之前分发，索引缺失或 `BUNDLE_PLUGINS=false` 时静默回落
- 判据：`crystal spec spec/m7_plugin_commands_spec.cr`
- 边界：`BUNDLE_PLUGINS=false` 与无索引两种回落路径同由该 spec 覆盖，但未对参考取「PATH 上同时存在同名 bundler-」的对照
- 生效：task-6（`5ec40bb`）
- 取代：无

## C-M7-6-003 `help <插件命令>` 以 `--help` 执行插件命令

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli.rb:155-160` 对 `help <cmd>` 走 `Plugin.exec_command(cli, ["--help"])`
- 我方行为：`src/celerite/cli/commands.cr` 的 help 分支对插件命令复用同一分发入口，参数为 `["--help"]`
- 判据：`crystal spec spec/m7_plugin_commands_spec.cr`
- 边界：第三方插件 `--help` 的实际输出内容未逐字对照；`Did you mean?` 建议未实现
- 生效：task-6（`5ec40bb`）
- 取代：无

## C-M7-6-004 `plugin list` 按索引插入序输出插件名、`-----` 分隔线与该插件的命令

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:81-97 list` 遍历 `index.installed_plugins`（= `index.rb:128-130 @plugin_paths.keys` 插入序，从不排序），逐插件打印名 / `-----` / 两空格缩进的命令 / 空行
- 我方行为：`src/celerite/cli/commands_surface.cr:2330 list` 分支读 `plugin_paths` 键序输出，命令来自 `PluginCommands.commands`（`src/celerite/plugin_commands.cr:65`）
- 判据：`bash script/differential plugin-command-list`
- 边界：空索引时输出 `No plugins installed`（同参考 `plugin.rb:93-94`）由 spec 断言，无差分夹具
- 生效：task-6（`5ec40bb`）
- 取代：无

## C-M7-6-005 重复安装同一插件只打印一次 `Installed plugin`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:260-271 save_plugins` 以 `index.up_to_date?(spec)`（`index.rb:122-127`）跳过已注册插件，故不再打印 `Installed plugin`（`plugin.rb:284-300`）
- 我方行为：`src/celerite/cli/commands_surface.cr:2482-2483` 用 `first_install = !plugin_path_map.has_key?(info.name)` 门控该行
- 判据：`bash script/differential plugin-command-reinstall`
- 边界：未覆盖参考 `up_to_date?` 里 `path == spec.full_gem_path` 的路径相等判定
- 生效：task-6（`5ec40bb`）
- 取代：无

## C-M7-6-006 两个插件声明同名命令时安装失败 exit 29 且索引保持不变

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/index.rb:54-76 register_plugin` 先算 `commands & @commands.keys`，非空即 `raise CommandConflict.new(name, common)`（`:58`）；`lib/bundler/errors.rb:49` 给 `PluginError` `status_code(29)`；`register_plugin` 的 `rescue StandardError` 回滚 `@commands` 且不 `save_index`
- 我方行为：`src/celerite/cli/commands_surface.cr:2418-2424` 检测冲突后打印参考措辞并 `return 29`，索引写入发生在其后
- 判据：`bash script/differential plugin-conflict-command` 与 `crystal spec spec/m7_plugin_conflicts_spec.cr`
- 边界：夹具用 `stderr-contains` 断两行（折行位置由宽度决定），不逐字比较整段 stderr
- 生效：task-73（`eaa2e9d`）
- 取代：无

## C-M7-6-007 两个插件注册同名 source 类型时安装失败 exit 29 且索引保持不变

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/index.rb:58-64 register_plugin` 对 `sources & @sources.keys` 非空即 `raise SourceConflict`，回滚 `@commands` 后重抛，索引不落盘
- 我方行为：`src/celerite/cli/commands_surface.cr:2432-2437` 比对既有 `sources` map 后按参考措辞报错并 `return 29`
- 判据：`bash script/differential plugin-conflict-source` 与 `crystal spec spec/m7_plugin_conflicts_spec.cr`
- 边界：同 C-M7-6-006，stderr 用 contains 断言
- 生效：task-73（`eaa2e9d`）
- 取代：无

## C-M7-6-008 `--path` 插件注册失败时其源目录被删除

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:45-49` 在 `PluginError` 上按 `names.include?(k)` 删 `spec.full_gem_path`；`:298-306` 失败回滚走 `uninstall`，而 path source 的 `full_gem_path` 就是源目录本身（`lib/bundler/plugin/installer/path.rb`）
- 我方行为：`src/celerite/cli/commands_surface.cr:2569 remove_failed_plugin_source`（`FileUtils.rm_rf` + `Dir.exists?` 守卫），在 `:2412`（MalformattedPlugin）/`:2423`（CommandConflict）/`:2436`（SourceConflict）三处 `return 29` 前调用；远端安装路径不删
- 判据：`bash script/differential plugin-conflict-source plugin-conflict-command`
- 边界：只对上述三类失败分支按参考删除，其余 `--path` 失败分支未取 oracle（见 C-M7-6-040）
- 生效：task-73（`eaa2e9d`）
- 取代：无

## C-M7-6-009 plugins.rb 的 `add_hook` 事件写入索引 `hooks:` 段

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:216-220 add_hook` 经 `Events.defined_event?` 校验后 `@hooks_by_event[event.to_s] << block`（校验失败在 `:217-218` 抛 `ArgumentError`）；`:309-340` 把 `@hooks_by_event.keys` 交给 `index.rb:54-74 register_plugin`（`(@hooks[event] ||= []) << name; uniq!`）
- 我方行为：`assets/bridge/plugin_command.rb --commands` 同时读回 `hooks` 键，`src/celerite/plugin_commands.cr:106 declared` 归一，`src/celerite/cli/commands_surface.cr:2448-2460` 按事件去重保序合并、`write_plugin_index` 写 `hooks:` 段
- 判据：`bash script/differential plugin-install-hooks` 与 `crystal spec spec/m7_plugin_hooks_registration_spec.cr`
- 边界：夹具用 `file-contains` 断索引内含 `after-install:` 与 `- "hook_plugin"`，不做整份索引逐字比较（两侧行尾 CRLF/LF 有别，互可读）
- 生效：task-6（`12350ab`）
- 取代：无

## C-M7-6-010 `plugin uninstall` 删除索引 hooks 段，之后的 install 不再触发该 hook

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/index.rb:78-88 unregister_plugin` 删插件名并清空数组后就地 `save_index`；`lib/bundler/plugin.rb:228-240 hook` 以 `index.hook_plugins(event)` 为门控
- 我方行为：`src/celerite/cli/commands_surface.cr:2923 write_plugin_index` 的 hooks 段按 `removed` 过滤插件名、空数组丢键；卸载分支在 `:2524` 仅在确有移除时重写
- 判据：`bash script/differential plugin-hook-uninstall` 与 `crystal spec spec/m7_plugin_uninstall_hooks_spec.cr`
- 边界：夹具以 sentinel 文件（`hook-after-uninstall`）+ `file-absent` 证明卸载后不再触发，索引骨架内容由 spec 断言
- 生效：task-9（`a5ee4d2`）
- 取代：无

## C-M7-6-011 `after-install` 按安装集逐个 spec 触发，running Bundler 的伪 spec 最先

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/installer/parallel_installer.rb:205-219 do_install` 对每个 spec 调 `Plugin.hook(GEM_AFTER_INSTALL, spec_install)`（与是否本次新装无关），`:8-59 SpecInstallation` 暴露 `name`/`full_name`/`state`；参考的实际触发顺序不保证（hook 在并行 worker 线程内）
- 我方行为：`src/celerite/cli/commands_install.cr:816-850` 构造 `hook_specs`（先 `{"bundler", "bundler-<profile 版本>"}` 再 specs）逐个调 `PluginHooks.call`；`src/celerite/plugin_hooks.cr:82 call` 把 `spec_name`/`spec_full_name` 传给桥；`assets/bridge/server.rb` 的 `op_exec_plugin_hook` 以 `PluginHookSpec` 作 context
- 判据：`bash script/differential plugin-hook-per-gem` 与 `crystal spec spec/m7_plugin_hook_per_gem_spec.cr`
- 边界：参考在「同进程二次加载 plugins.rb」时会对每个 spec 触发两次（blocks=2），我方每次 install 只加载一次（见 C-M7-6-041）；`bundler` 伪 spec 只复刻 `name`，`SpecInstallation` 的 spec/依赖边 API 未复刻
- 生效：task-11（`3b03f9c`）
- 取代：无

## C-M7-6-012 `before-install-all` 在解析前触发、`after-install-all` 在 `Bundle complete!` 前触发

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/installer.rb:12-20` 在 `installer.run` 之前 `Plugin.hook(GEM_BEFORE_INSTALL_ALL, definition.dependencies)`、之后 `GEM_AFTER_INSTALL_ALL`；`lib/bundler/cli/update.rb:81` 复用同一入口；`lib/bundler/plugin/events.rb:45-58` 定义三个事件名
- 我方行为：`src/celerite/plugin_hooks.cr:24 EVENTS` 列三个事件、`:124 run` 统一处理未启用/缺路径告警/加载失败/钩子失败；`src/celerite/cli/commands_install.cr:442`（解析前）与 `:855`（汇总输出前）各调一次；`update` 路径同样接线
- 判据：`bash script/differential plugin-hook-before-after-all` 与 `crystal spec spec/m7_plugin_hook_all_events_spec.cr`
- 边界：桥对 `*-all` 参数在 Ruby 侧重 `Bundler::Dsl.evaluate` 取 `builder.dependencies`，不是复用 CLI 已算好的 definition；Gemfile 解析失败时参考先报错、我方退化为空数组（未取 oracle）；与 auto-clean / funding 汇总的相对位置未覆盖
- 生效：task-45（`d2134bc`）
- 取代：无

## C-M7-6-013 hook 块抛异常时 install exit 1 且不写 Gemfile.lock

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:228-240 hook` 对块不加 rescue；锁文件在安装后写、`Bundle complete!` 由 `lib/bundler/cli/install.rb` 在 installer 返回后打印，故两者都不出现
- 我方行为：`src/celerite/cli/commands_install.cr:841-848` 对 `hook_failed` 打印一行并 `return 1`，该处位于 `Lockfile.write` 之前（task-7 前移）
- 判据：`bash script/differential plugin-hook-raise` 与 `crystal spec spec/m7_plugin_hook_failure_spec.cr`
- 边界：夹具用 `stderr-contains boom` + `file-absent Gemfile.lock`（参考打完整 ERROR REPORT，我方一行，故不逐字比较）；夹具用 path gem，因 rubygems gem 崩溃路径的 stdout 不稳定
- 生效：task-7（`c6ae153`）
- 取代：无

## C-M7-6-014 插件加载期抛异常时 install exit 1

- 状态：已声明差异
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:345-381 load_plugin` 报告加载失败并重抛，首行形如 `Failed loading plugin <name>: <msg> at plugin load`，其后附 `--- ERROR REPORT TEMPLATE ---` 段
- 我方行为：`src/celerite/cli/commands_install.cr:842-844` 打印 `Failed loading plugin <name>: <message>` 后 `return 1`；`assets/bridge/server.rb` 的 `load_failed` 状态携带同一消息
- 判据：`crystal spec spec/m7_plugin_hook_failure_spec.cr`
- 边界：有意不复刻参考的 ERROR REPORT 模板段，故只声明 exit 码与首行措辞一致
- 生效：task-6（`12350ab`）
- 取代：无

## C-M7-6-015 插件 load path 目录缺失时打印告警并继续，exit 0

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:345-381`（调用点 `:237-239`）对缺失路径打印五段警告（`The following plugin paths don't exist: <abs>.` … `Continuing without installing plugin <name>.`），跳过该插件但其余插件照常加载
- 我方行为：桥返回 `missing` 数组，`src/celerite/plugin_hooks.cr:130-140`（install-all 事件）与 `src/celerite/cli/commands_install.cr:827-839`（每 spec 事件）逐字打印同样五段
- 判据：`crystal spec spec/m7_plugin_hook_failure_spec.cr`
- 边界：参考在每次 `Plugin.hook` 调用时都会告警，我方为保持 pinned stderr 每命令只警告一次（见 C-M7-6-039）
- 生效：task-6（`12350ab`）
- 取代：无

## C-M7-6-016 `BUNDLE_PLUGINS=false` 时插件不加载、hook 不触发

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:228-240 hook` 首行 `return unless Bundler.settings[:plugins]`；`lib/bundler/settings.rb` 只把 `false` 与字符串 `"false"` 视为关闭
- 我方行为：`src/celerite/plugin_hooks.cr:61 enabled?` 与 `src/celerite/plugin_commands.cr:60 enabled?` 同判据（`Bool`/`String`/未设三分支），install 路径在 `src/celerite/cli/commands_install.cr:816` 门控
- 判据：`crystal spec spec/m7_plugin_hook_failure_spec.cr spec/m7_plugin_hook_all_events_spec.cr`
- 边界：从 `.bundle/config` 读取（而非进程环境）的关闭路径未取 oracle
- 生效：task-6（`12350ab`）
- 取代：无

## C-M7-6-017 plugins.rb 声明未定义 hook 事件时 install exit 29 且不留索引

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:215-220 add_hook` 对未定义事件 `raise ArgumentError, "Event '<event>' not defined in Bundler::Plugin::Events"`；`:309-340 register_plugin` 的 `load path.join(PLUGIN_FILE_NAME)` 被 `rescue StandardError` 包成 `MalformattedPlugin, "#{e.class}: #{e.message}"`（`:324-325`）；`:292-298 save_plugin` 再包成单条 `Failed to install plugin \`<name>\`, due to <Class> (<cause>)`；`lib/bundler/errors.rb:49` 给 `PluginError` status 29；`lib/bundler/friendly_errors.rb:31-36` 以 `wrap: true` 打印
- 我方行为：`src/celerite/plugin_commands.cr:104 Declared` 携带 `error` 字段，`src/celerite/cli/commands_surface.cr:2405-2413`（本地 `--path`）与 `:2735-2741`（远端）打印两行并 `return 29`；`Dir.mkdir_p` 已前移到 `File.write` 之前，失败路径不留 `.bundle/plugin`
- 判据：`bash script/differential plugin-install-bad-event` 与 `crystal spec spec/m7_plugin_bad_event_spec.cr`
- 边界：参考在失败回滚时删除 `--path` 源目录，我方保留（夹具把源目录放 `bundle-preset/` 以避开树比较）
- 生效：task-15（`61d1424`）
- 取代：无

## C-M7-6-018 插件安装失败消息按终端宽度折行，只认 `THOR_COLUMNS`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/ui/shell.rb:167-171 word_wrap(text, line_width = Thor::Terminal.terminal_width)`；`vendor/thor/lib/thor/shell/terminal.rb:4-18` 只读 `THOR_COLUMNS`（`to_i`，<10 忽略），非 unix 恒 80，`COLUMNS` 完全无效
- 我方行为：`src/celerite/cli/commands_surface.cr:2557 put_plugin_install_failure` 拼单条消息后交 `Commands.word_wrap`（`src/celerite/cli/commands.cr:1180`）+ `CLI.terminal_width`（`src/celerite/cli.cr:53`，`THOR_COLUMNS` ≥10 优先否则 80）；三条失败分支共用
- 判据：`bash script/differential plugin-install-bad-event plugin-install-bad-event-long`
- 边界：夹具不设 `THOR_COLUMNS`，只覆盖默认 80 列的折行形态
- 生效：task-17（`2216e39`）
- 取代：无

## C-M7-6-019 Gemfile 的 `source …, type: :x` 预装推断插件 `bundler-source-x`，缺 gem 时 exit 7

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli/install.rb:41` 在 build definition 前调 `Plugin.gemfile_install`；`lib/bundler/plugin/dsl.rb:39-49` 把 `source …, type:` 变成 `<gem "bundler-source-x">`（不登记 source）；`lib/bundler/plugin.rb:104-127`；缺 gem 报参考 `GemNotFoundError`（exit 7）
- 我方行为：`src/celerite/plugin_gemfile.cr:24 plugin_names`/`:36 primary_source` 解析声明，`src/celerite/cli/commands_install.cr:95-133 install_gemfile_plugins` 在首次求值前预装，`:103` 只透传 `{4,7,15,29}` 四个状态码
- 判据：`bash script/differential plugin-gemfile-missing install-typed-source-missing-plugin` 与 `crystal spec spec/m7_gemfile_plugins_spec.cr spec/m7_typed_source_spec.cr`
- 边界：`plugin "x"` 指向存在但缺 `plugins.rb` 的 gem 我方也 exit 29，但该形态无差分夹具
- 生效：task-6（`1510268`）、task-24（`0f8b506`）
- 取代：无

## C-M7-6-020 插件关闭时 Gemfile 中的 `type:` source 使 install exit 15

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/dsl.rb:129-131` 在 `Plugin.source?(type)` 为假时 `raise InvalidOption, "No plugin sources available for <type>"`（exit 15）；`plugin "x"` 行在关闭时被忽略（exit 0）
- 我方行为：install 预装前 `src/celerite/cli/commands_install.cr:236` 以 `PluginGemfile.enabled?` 门控，关闭时不预装、由正常求值路径报同样状态
- 判据：`crystal spec spec/m7_gemfile_plugins_spec.cr`
- 边界：差分夹具 `plugin-source-disabled` 登记为 deferred（`fixtures/differential/plugin-source-disabled/deferred-4.0.24` 记明 harness 不能逐夹具设环境变量），该面只由 spec 覆盖
- 生效：task-6（`1510268`）
- 取代：无

## C-M7-6-021 typed plugin source 的 `lock` 写出完整 `PLUGIN SOURCE` 段

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/api/source.rb:41`（`uri`/`options`/`name`）、`:73 options_to_lock`、`:136 specs`、`:283-295 to_lock`；锁读门禁 `lib/bundler/lockfile_parser.rb:195`（`1.13`）
- 我方行为：`assets/bridge/server.rb serialize_source` 识别 `Bundler::Plugin::API::Source` 并新增 `plugin_source_specs` 操作（客户端 `src/celerite/bridge/client.cr:301`）；`src/celerite/resolution.cr` 为 Plugin 源跳过文件系统索引、按桥返回的 specs 建 `IndexSpec` 与锁段；`src/celerite/definition.cr` 的源标签接受 `Plugin`/`PLUGIN SOURCE`
- 判据：`bash script/differential plugin-source-typed` 与 `crystal spec spec/m7_plugin_source_typed_spec.cr`
- 边界：夹具用 `file-equals-4.0.24`/`file-equals-2.7.2` 逐字断锁；非空 `options_to_lock` 与插件 source 的 checksum 由另一夹具（`plugin-source-lock-options`）固定，见 C-M7-6-035
- 生效：task-28（`af962ae`）
- 取代：无

## C-M7-6-022 锁内已有的 `PLUGIN SOURCE` 在再次 `lock` 时复用而不重解析

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:202-211` 在锁内 type 未注册时返回 `UnloadedSource`，`lib/bundler/plugin/unloaded_source.rb` 的 `fetch_gemspec_files` 为空仍可解析锁段，故 `lock` 只打印 `Writing lockfile to …`
- 我方行为：`src/celerite/resolution.cr materialize_locked` 按锁段 `source.type` 区分、`build_locked_index` 增 `PLUGIN SOURCE` 分支（桥 `plugin_source_specs`，失败时跳过该条）；`hide_inferred_plugins!`（`src/celerite/resolution.cr:2205`）
- 判据：`bash script/differential plugin-source-locked`
- 边界：区分力由 `87a69a4` 旧二进制在 `plugin-source-locked-check` 上 FAIL 反证，该反证只覆盖 `check` 面
- 生效：task-29（`cdf20fb`）
- 取代：无

## C-M7-6-023 插件未安装时含 typed source 的 Gemfile 在 `lock` / `check` 报 exit 15

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/dsl.rb:129-131` 抛 `No plugin sources available for <type>`（exit 15），求值阶段即在 `lock`/`check` 生效
- 我方行为：`src/celerite/cli/commands.cr:1495 run_check` 在锁定路径前先 `evaluate_gemfile`，`BridgeError` 状态 4/15 原样上抛；`lock` 走同一求值门
- 判据：`bash script/differential plugin-source-locked-missing`
- 边界：缺插件时的 `install`（参考 exit 7）未加夹具
- 生效：task-29（`cdf20fb`）
- 取代：无

## C-M7-6-024 锁内 typed source 的 spec 视为已安装，`check` exit 0

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/unloaded_source.rb` 的 specs 由锁段重建，`check` 对已锁 spec 直接判满足并打印 `The Gemfile's dependencies are satisfied`
- 我方行为：`src/celerite/cli/commands_surface.cr:1632 installed_gem_dir` 对 `PLUGIN SOURCE` 用锁段 `remote` 展开为项目内绝对路径；`build_locked_index` 把该 spec 标 `"PLUGIN"` 并复原 `SourceInfo`
- 判据：`bash script/differential plugin-source-locked-check`
- 边界：区分力由 `87a69a4` 旧二进制 FAIL（exit ref=0 cel=1）反证
- 生效：task-29（`cdf20fb`）
- 取代：无

## C-M7-6-025 typed plugin source 的 install 成功路径输出安装行与 post-install 消息，并隐藏推断依赖

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/dsl.rb:39-49` 注入 `bundler-source-<type>`；`lib/bundler/plugin/api/source.rb:90-92` 默认 install 抛 `MalformattedPlugin`；`lib/bundler/installer/gem_installer.rb:67-75` 调 `source.install(...)` 并把返回值作 post-install 消息；4.0.24 装后锁里 `GEM` specs 空、`DEPENDENCIES` 只剩真实依赖
- 我方行为：桥新增 `plugin_source_install`（客户端 `src/celerite/bridge/client.cr:310`）；`src/celerite/cli/commands_install.cr:644-690` 走插件自己的 install、收集消息并在汇总后打印 `Post-install message from <name>:`，`resolution.add_inferred_plugin_dependencies!` / `hide_inferred_plugins!`（`src/celerite/resolution.cr:2205`/`:2218`）隐藏推断依赖；2.x 额外把插件 gem 解包到 `.bundle/plugin/gems`
- 判据：`bash script/differential plugin-source-install` 与 `crystal spec spec/m7_plugin_source_typed_spec.cr`
- 边界：干净 lock 未带 CHECKSUMS 时我方不主动创建；spec 未断言 bundle 内落盘路径（`Dir.glob` 反斜杠不稳，由 installed-tree 覆盖）；2.7.2 的解包未逐文件比对
- 生效：task-31（`4769dae`）
- 取代：无

## C-M7-6-026 真实打包的第三方插件 gem 注册自定义 source 后端到端可用

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/api.rb:43-46`（`self.source` include `Plugin::API::Source` 并登记）、`lib/bundler/plugin.rb:309-340 register_plugin`、`lib/bundler/plugin/index.rb:54-76`（`sources` 冲突抛 `SourceConflict`）、`lib/bundler/source/rubygems.rb:122-136`（cached 分支措辞）
- 我方行为：`assets/bridge/plugin_command.rb` 额外返回 `sources`；`src/celerite/plugin_commands.cr:82 sources` 与 `:104 Declared` 携带声明类型；`src/celerite/cli/commands_surface.cr:2432-2444` 写回 `sources:` 并按参考措辞报 `SourceConflict`；`src/celerite/resolution.cr` 新增 `property remote_only` 以输出 `…, cached gems or installed locally`
- 判据：`bash script/differential plugin-source-gem-end-to-end`
- 边界：插件 gem 由本仓脚本 `script/build-plugin-gem-index.rb` 本地构建，不代表真实第三方生态；只验证单插件注册单个 source；需原生扩展的插件未测；真实远端（非 `file://`）源未验证
- 生效：task-47（`85cdc56`）
- 取代：无

## C-M7-6-027 typed plugin source 中不存在的 gem 按插件源归因报 exit 7

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/source/path.rb:159-179` 载入 glob 全集、`lib/bundler/resolver/base.rb:113-118` 以 `specs.search(ls.name).empty?` 判未命中；`lib/bundler/plugin/api/source.rb:293-296` 的 `to_s` 给出 `plugin source for <type> with uri <uri>`
- 我方行为：桥 `op_load_gemspec_dir` 增可选 `name`（`src/celerite/bridge/client.cr:449 load_gemspec_dir(dir, glob, name)`），`src/celerite/resolution.cr load_source_gem_spec` 只在 `info.name == name` 时构造 `IndexSpec`，`make_source` 的 `source_descriptions` 增 Plugin 分支
- 判据：`bash script/differential plugin-source-missing-gem` 与 `crystal spec spec/m7_path_source_missing_gem_spec.cr`
- 边界：修复前会把调用方给的 name 当成 spec 名、从兄弟 gemspec 抄版本；反向对照 `e058de4` 旧二进制双 profile `0 passed / 2 failed`
- 生效：task-46（短哈希未记录于 evidence）
- 取代：无

## C-M7-6-028 `plugin install <gem> --source` 把插件 gem 物化到项目插件树

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:138-158 root` 在 bundle 内为 `<app>/.bundle/plugin`；插件 gem 的 `gems/` `cache/` `specifications/` 落在该树而非应用 bundle；输出 `Fetching`/`Installing` 两行后 `Installed plugin <name>`
- 我方行为：`src/celerite/cli/commands_surface.cr plugin_install_remote`（`:2579`）把索引 `load_paths`/`plugin_paths` 指向 `<project>/.bundle/plugin/gems/<full>`，用纯 Crystal `copy_tree`（`:2540`）复制（msys `cp` 在 Low IL 下 `0xC0000022`）；合成 Gemfile 目录改 `<project>/.bundle/tmp/celerite-plugin-<pid>-<rand>`
- 判据：`bash script/differential plugin-install-source` 与 `crystal spec spec/m7_plugin_install_source_spec.cr`
- 边界：`plugin install --git` 的插件树路径（`<plugin_root>/bundler/gems/<name>-<version>`）无 oracle；真实 https 索引源未测
- 生效：task-6（`53d321d`）
- 取代：无

## C-M7-6-029 无 Gemfile 时插件命令面走全局 `~/.bundle/plugin`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:138-158 root` 在非 bundle 时用 `Bundler.user_bundle_path("plugin")`
- 我方行为：`src/celerite/cli/commands_surface.cr:2852-2885` 的 `plugin_project_dir`/`plugin_tree_root`/`plugin_index_path`（无 Gemfile → `Config.user_home/.bundle/plugin`）；`src/celerite/cli/commands.cr:3972-3979` 的分发与 `src/celerite/plugin_hooks.cr:74 index_path` 同判据
- 判据：`crystal spec spec/m7_plugin_install_source_spec.cr`
- 边界：无 Gemfile 时参考对 `plugin install --source` 的行为未取证（我方装到全局 root）；无 Gemfile 下 `plugin uninstall` 未差分
- 生效：task-6（`53d321d`）
- 取代：无

## C-M7-6-030 非规范 `file://C:/…` 远程在索引与下载器两侧归一到同一本地路径

- 状态：已实现
- 参考行为（4.0.24）：参考完全忽略 URI host 只用 path；`Gem::Util.correct_for_windows_path` 只去掉 `/`+盘符+`:` 三字符；`//` 前缀保留 UNC（`lib/bundler/source/rubygems.rb:369-376`、`lib/bundler/uri_normalizer.rb:15-21`、`lib/bundler/fetcher.rb:151-155`）
- 我方行为：新增 `src/celerite/file_url.cr`（`local_path:20`、`directory:27`），`src/celerite/compact_index/cache.cr:604-612` 与 `src/celerite/downloader.cr:193-199` 改用它
- 判据：`bash script/differential plugin-install-source-noncanonical` 与 `crystal spec spec/m7_file_url_spec.cr`
- 边界：跨盘与 UNC 的端到端未实测；`file:C:/x`（opaque path）参考崩 exit 1、我方 exit 0，属既有分歧；`Resolution#normalize_remote` 未改
- 生效：task-19（`fb662b0`）
- 取代：无

## C-M7-6-031 `plugin uninstall` 的选项与空参语义跟参考一致

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli/plugin.rb:25-32 uninstall` 只声明 `--all`，Thor 把其余 token 当位置参数；`lib/bundler/plugin.rb:55-77` 空参且无 `--all` 时打两行 stderr 并返回、无插件时 `No plugins installed`、未装插件时 `Plugin <name> is not installed `（尾空格）
- 我方行为：`src/celerite/cli/commands_surface.cr:2491` 只剔除 `--all`、`:2492-2496` 空参两行、`:2505-2508` 空列表、`:2510-2514` 逐个判定并打尾空格消息（`:2522` 打印 `Uninstalled plugin <name>`）
- 判据：`bash script/differential plugin-uninstall-args` 与 `crystal spec spec/m7_plugin_uninstall_hooks_spec.cr`
- 边界：`--all` 多插件的输出顺序无差分夹具
- 生效：task-20（`74d3497`）
- 取代：无

## C-M7-6-032 `plugin uninstall` 删除插件树内的 checkout 目录

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:63-73` 对 `index.installed_in_plugin_root?(name)` 为真者 `Bundler.rm_rf(index.plugin_path(name))`；`lib/bundler/plugin/index.rb:192-196 installed_in_plugin_root?` 以 `path.start_with?("#{Plugin.root}/")` 判定
- 我方行为：`src/celerite/cli/commands_surface.cr:2915 plugin_owned_path?` 统一分隔符后比对 `plugin_tree_root/` 前缀，`:2519` 命中才 `rm_rf`；`:2923 write_plugin_index` 以 `by_value` 参数按 value 删 `sources` 条目
- 判据：`bash script/differential plugin-uninstall-index`
- 边界：差分夹具用相对 `plugin_paths`，两侧都不删 checkout（绝对路径删除只在 spec 覆盖）；真实 `--git` 安装→卸载端到端被本机 `0xC0000022` 挡住
- 生效：task-20（`74d3497`）
- 取代：无

## C-M7-6-033 `plugin new` 报未知子命令 exit 15

- 状态：已实现
- 参考行为（4.0.24）：`bundle plugin new foo` → exit 15、stderr `Could not find command "new".`（Thor 子命令分派，`lib/bundler/cli.rb` 的 `handle_no_command_error`）
- 我方行为：`src/celerite/cli/commands_surface.cr:2329 case sub` 删去 `new` 分支，落入 `:2526-2530` 的未知子命令分支打印 `Could not find command "<sub>".` 并返回 15
- 判据：`bash script/differential plugin-new-unknown` 与 `crystal spec spec/m7_micro_divergences_spec.cr`
- 边界：无 Gemfile 目录下 `plugin new` 的表现未单独取 oracle；旧 `known_unimplemented?` 死代码已删
- 生效：task-56（`7fb756a`）
- 取代：无

## C-M7-6-034 远端 `--source` 插件安装的失败路径 exit 7

- 状态：已实现
- 参考行为（4.0.24）：HTTP 索引上解析不到插件 gem 时按 `GemNotFoundError` 退出 7，stdout 只打 `Fetching` 前缀
- 我方行为：`src/celerite/cli/commands_surface.cr:2579 plugin_install_remote` 复用 Source/PubGrub 决议，把桥错误码原样作为退出码
- 判据：`bash script/differential plugin-source`
- 边界：夹具走本地 HTTP 索引（`fixtures/differential/plugin-source/http-index`），未覆盖真实远端鉴权/重定向；同批 `plugin-source-ok` 在本机曾因原生扩展环境失败（见 C-M7-6-036）
- 生效：M5 期间
- 取代：无

## C-M7-6-035 插件 source 的非空 `options_to_lock` 落进 `PLUGIN SOURCE` 段

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/plugin/api/source.rb:73 options_to_lock` 的返回被并入锁段选项
- 我方行为：`assets/bridge/server.rb` 透传 `options_to_lock`，`src/celerite/resolution.cr` 的锁段渲染逐项写出；无产品改动，本夹具只固定既有行为
- 判据：`bash script/differential plugin-source-lock-options`
- 边界：用 `file-contains` 断三条 `PLUGIN SOURCE` 行而非整份 `file-equals`（2.x 的 `BUNDLED WITH` 与 CHECKSUMS 段本就不同）；无负对照（无产品改动）
- 生效：task-96（短哈希未记录于 evidence）
- 取代：无

## C-M7-6-036 远端 `--source` 插件安装的成功路径（`plugin-source-ok`）

- 状态：未验证
- 参考行为（4.0.24）：HTTP 索引上装成插件后打印 `Fetching`/`Installing` 两行、把 gem 物化进插件树 `gems/` `specifications/` `cache/` 与 `extensions/` `doc/` `build_info/` `plugins/` 目录
- 我方行为：同 C-M7-6-028 的物化路径；该夹具同一二进制在 `docs/compat-evidence/2026-11-19.md` 记为 PASS，在 `docs/compat-evidence/2026-11-15.md:320` 记为因本机原生扩展构建（`racc-1.8.1`）与 `cp.exe 0xC0000022` 失败
- 判据：`bash script/differential plugin-source-ok`
- 边界：本机结果不稳定（成功与原生扩展环境失败均有记录），故不声明为已实现；`docs/compat-report.md:128` 的 `dual-passed` 措辞未反映该不稳定
- 生效：M5 期间
- 取代：无

## C-M7-6-037 无 Gemfile / 全局插件根下安装时 hooks 的落盘

- 状态：未验证
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:138-158 root` 在非 bundle 时用全局根，`index.rb:54-74` 的 `hooks` 应随之落到 `~/.bundle/plugin/index`
- 我方行为：`assets/bridge/plugin_command.rb` 与 `src/celerite/plugin_commands.cr:106 declared` 返回 `hooks`，全局 root 的索引写入复用同一 `write_plugin_index`；无专例
- 判据：`crystal spec spec/m7_plugin_install_source_spec.cr`
- 边界：该 spec 不覆盖 hooks 落盘；全局根的 hooks 写入既无差分夹具也无 spec，属已知取证缺口
- 生效：—
- 取代：无

## C-M7-6-038 `plugin install --git/--branch/--ref` 的 git checkout 端到端

- 状态：未验证
- 参考行为（4.0.24）：`lib/bundler/plugin/installer/git.rb` 把插件 checkout 到 `<plugin_root>/bundler/gems/<name>-<rev>`，并复用 `--branch`/`--ref`
- 我方行为：`src/celerite/cli/commands_surface.cr:2358-2368` 接受三个 flag 并走 `plugin_install_remote`；`plugin-git-local`/`plugin-git-local2` 在 2026-11-13 记为双 profile PASS，其后多轮回归记为 msys `sh.exe` Low IL `0xC0000022` 环境失败
- 判据：`bash script/differential plugin-git-local plugin-git-local2`
- 边界：本机 git 子进程被 Low IL 阻断，无法区分产品行为与环境；插件树路径无独立 oracle；`--branch` 与 `--ref` 同给的 exit 1 断言只在 install 主路径取过 oracle
- 生效：—
- 取代：无

## C-M7-6-039 缺失 load path 的告警在参考里按每次 hook 重复，我方每命令一次

- 状态：已声明差异
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:228-240 hook` 每次调用都重载插件索引，故缺失路径的五段告警按 `Plugin.hook` 调用次数重复
- 我方行为：`src/celerite/cli/commands_install.cr:826-839` 用 `first_hook` 标志只打印一次，以保持 pinned stderr 稳定
- 判据：`crystal spec spec/m7_plugin_hook_failure_spec.cr`
- 边界：有意差异；参考的具体重复次数依安装集大小变化，我方不跟随
- 生效：task-11（`3b03f9c`）
- 取代：无

## C-M7-6-040 失败回滚删除 `--path` 源目录只对三类注册失败复刻

- 状态：已声明差异
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:45-49` 的删除条件是「该 name 的 spec 存在且其 command 未登记」，凡是走 `PluginError` 的回滚都会删 path source 目录
- 我方行为：`src/celerite/cli/commands_surface.cr:2412`/`:2423`/`:2436` 三处显式调用 `remove_failed_plugin_source`（MalformattedPlugin / CommandConflict / SourceConflict），其余 `--path` 失败分支保留目录
- 判据：`bash script/differential plugin-conflict-command plugin-conflict-source`
- 边界：其他失败分支（如远端解析失败、`--version` 找不到版本）未取 oracle，故不声称覆盖参考的全部回滚形态
- 生效：task-73（`eaa2e9d`）
- 取代：无

## C-M7-6-041 参考同进程二次加载导致每 spec 触发两次的重复注册未复刻

- 状态：已声明差异
- 参考行为（4.0.24）：`lib/bundler/plugin.rb:309-340 register_plugin` 每次 `load_plugin` 都往 `@hooks_by_event[event]` 追加块；同一进程内二次加载 `plugins.rb` 会让每个 spec 触发两次（oracle 记为 `blocks=2`）
- 我方行为：`src/celerite/cli/commands_install.cr:816-850` 每次 install 只加载一次，`hook-log-<name>` 行数为参考的一半；夹具只断言行数递增与按名命中
- 判据：`bash script/differential plugin-hook-per-gem`
- 边界：参考该重复机制未定位到具体调用点，我方不复刻；不以行数相等断言
- 生效：task-11（`3b03f9c`）
- 取代：无

## C-M7-6-042 插件加载失败的 `--- ERROR REPORT TEMPLATE ---` 段未复刻

- 状态：已声明差异
- 参考行为（4.0.24）：`lib/bundler/friendly_errors.rb` 在 `Bundler::Plugin::PluginError` 上报时附 ERROR REPORT 模板段
- 我方行为：`src/celerite/cli/commands_install.cr:843`（`Failed loading plugin …`）与 `:846`（`Plugin hook after-install failed: …`）都只打一行，不含插件名以外的报告段
- 判据：`crystal spec spec/m7_plugin_hook_failure_spec.cr`
- 边界：有意差异；exit 码与首行措辞对齐，报告段不复刻
- 生效：task-6（`12350ab`）
- 取代：无
