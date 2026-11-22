# M7-2 安装后 gem 发现与命令面（claims）

本文件是 M7-2 的断言账本：把 `../compat-evidence/` 里已取证的结论逐条固化为可复跑断言。原始建档、逐字输出与探针目录仍留在 evidence，本文件只写结论与判据。

参考锚点的路径前缀统一为 `<参考检出>/lib/bundler/`（4.0.24 检出的位置见 `../compat-evidence/2026-11-19.md` 的门禁段）。

## C-M7-2-001 已安装判定改用 `<root>/specifications/<full_name>.gemspec`，只有 gem 目录而没有 specification 即判缺失

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/check.rb:27-31` 取 `definition.check!` 的 `missing_specs` 逐条打 ` * name (version)`；`definition.rb:261-264` 的 `missing_specs` 走 `spec_set.rb:154-162` 的 `missing_specs_for`，只对 `completely_missing_specs` 报缺；`lazy_specification.rb:224-229` 的 `materialize` 调 `source.specs.search`，RubyGems 侧清单来自 `rubygems_integration.rb:434-440` 的 `find_name` = `Gem::Specification.stubs_for(name).map(&:to_spec)`，即读 `<root>/specifications/<full_name>.gemspec`；`cli/show.rb:19-30` 另用 `spec.full_gem_path` 判断解包目录是否存在
- 我方行为：`Commands.installed_gem_dir` 的 RubyGems 分支先查 `<path>/specifications/<full_name>.gemspec`，命中后仍返回 `gems/<full_name>` 供 show 判断目录（`src/celerite/cli/commands_surface.cr:1632`），判据函数 `installed_spec_file?` 在 `:1721`；PATH 分支在 `:1638-1641`、GIT 分支在 `:1642-1645`（实现 `installed_git_checkout`，`:1783`）、bundle `<install_path>/ruby/<abi>` 分支在 `:1676-1685`
- 判据：`bash script/differential check-installed-spec-without-gemdir check-gemdir-without-spec`；`crystal spec spec/m7_installed_discovery_spec.cr`
- 边界：`install` 幂等仍用 `Installer#installed?`（spec + 目录，`src/celerite/installer.cr:70`），未与只读发现统一；平台变体 `platgem (1.0.0-x64-mingw-ucrt)` 只有单元夹具、无差分
- 生效：task-22（短哈希未记录）
- 取代：无

## C-M7-2-002 specification 在而解包目录缺时 list 仍通过，show 与 info --path 打警告后 exit 0，info 整块信息改走 stderr

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/list.rb:19-25` 只加载 `Bundler.load.specs`，有 specification 即通过；`cli/show.rb:19-30` 在 `File.directory?(spec.full_gem_path)` 为假时打 `The gem <name> is missing. It should be installed at <path>, but was not found` 后仍 exit 0；`cli/info.rb:36-48` 的 `--path` 与 show 同形，`:68-72` 在 `installation_missing?` 时把整块 gemspec 信息经 `ui.warn` 写 stderr，前缀 `The gem <name> is missing. Gemspec information is still available though:`
- 我方行为：info 分支先构造整块文本，缺目录时先打 stderr 前缀再 `stderr.print` 整块（`src/celerite/cli/commands.cr:2372`，紧接 `:2373` 的 `stderr.print info.to_s`），`show`、`show --paths` 与 `info --path` 打同一警告并返回 0（`:2313`、`:2324`、`:2342`）
- 判据：`bash script/differential check-installed-spec-without-gemdir list-installed-spec-without-gemdir info-installed-spec-without-gemdir`；`crystal spec spec/m7_installed_discovery_spec.cr`
- 边界：`info --version` 在目录缺失时未取 oracle；「解包目录存在时的 info」未纳入差分
- 生效：task-37（短哈希未记录）
- 取代：无

## C-M7-2-003 specification 与解包目录都缺时 list exit 1、show 与 info exit 7，文案为 `Could not find <full_name> in locally installed gems`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/list.rb:19-25` 在 `GemNotFound` 时 `ui.error e.message` 加 `ui.warn "Install missing gems with \`bundle install\`."` 后 exit 1；`cli/show.rb:19-30` 与 `cli/info.rb:11-24` 经 `cli/common.rb:68-96 select_spec` 走到 not-found，源描述由 `source/rubygems.rb:122-136` 在 `@allow_remote` 关闭时给 `locally installed gems`
- 我方行为：list 缺失分支 stderr 打 `Could not find <full_names> in locally installed gems` 与安装提示后返回 1（`src/celerite/cli/commands.cr:1910-1912`）；show 与 info 走同一分支（`:2110`）后返回 7
- 判据：`bash script/differential list-gem-entirely-missing check-gemdir-without-spec`
- 边界：多个 gem 同时缺失时的逗号连接只在单元层覆盖，无对应差分
- 生效：task-37（短哈希未记录）
- 取代：无

## C-M7-2-004 裸 show 与 show --paths 按 gem 名排序列举，运行中的 Bundler 参与排序而非固定首行

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/show.rb:37-53` 无 gem 名时先打 `Gems included by the bundle:`，再按 `Bundler.load.specs.sort_by(&:name)` 逐条输出 `  * name (version)`；`Bundler.load.specs` 含运行中的 Bundler 自身，其位置由名字决定；`cli/show.rb:33-36` 的 `--paths` 只打印路径、不打 header
- 我方行为：列举分支先构造 `(name, line)` 再 `sort_by!` 打印（`src/celerite/cli/commands.cr:2108-2172`，`--paths` 排序在 `:2127`、人读排序在 `:2172`），`--paths` 形态不打 header；运行中 Bundler 的版本与目录由 `profile_bundler_version`（`:2426`）与 `bundler_gem_dir`（`:2455`）给出
- 判据：`bash script/differential show-listing-order show-paths-order show-listing-bundler show-paths-bundler`；`crystal spec spec/m7_show_order_spec.cr spec/m7_show_listing_spec.cr`
- 边界：已声明差异——未设 `CELERITE_REFERENCE_BUNDLER_LIB` 且宿主无已安装 bundler 时 `--paths` 省略该行（参考恒有）；不同安装布局下的路径字面值未逐形态取 oracle
- 生效：task-93（`39bea33`）
- 取代：无

## C-M7-2-005 show bundler 与 info bundler --path 输出单行 gem 根路径，回落基准是 `lib/bundler/cli`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/show.rb:19-21` 对 `show bundler` 直接用 `File.expand_path("../../..", __dir__)` 输出 gem 根，`--paths` 同值；`cli/info.rb:39-40` 的 `print_gem_path` 对 bundler 用同一表达式，故两侧必然同值；该表达式以 `<gem>/lib/bundler/cli`（`__dir__`）为基准上溯三级
- 我方行为：`show_bundler_path`（`src/celerite/cli/commands.cr:2446`）在设了 `CELERITE_REFERENCE_BUNDLER_LIB` 时取 `File.expand_path("..", reference_lib)`，否则以 `File.join(gem_dir, "lib", "bundler", "cli")` 为基准上溯三级；`show bundler` 与 `show bundler --paths` 在 `:2273` 调用该函数并短路返回 0，`info bundler --path` 在 `:2286` 复用同一函数，故两侧同值；task-135 前该基准少一级、落成 `<gems>`
- 判据：`bash script/differential show-bundler show-bundler-paths show-bundler-path info-bundler-path`；`crystal spec spec/m7_show_bundler_path_spec.cr`
- 边界：`info bundler` 的整块元数据输出未在本轮取证；无参考 lib 且宿主无已安装 bundler 时该分支不可达
- 生效：task-135（`833be83`）、task-136（提交短哈希未记录）
- 取代：无

## C-M7-2-006 list 的 --format=json、两组互斥与校验顺序按 4.0.24 收敛

- 状态：已实现
- 参考行为（4.0.24）：`cli/list.rb:15` 先拒 `--only-group` 与 `--without-group` 并用，`:17` 再拒 `--name-only` 与 `--paths` 并用，`:19-25` 之后才加载 specs（缺 gem 先 exit 1），`:30-38` 最后校验 `--format`，非法值报 `Unknown option\`--format=<v>\`. Supported formats: \`json\``（`option` 与反引号间无空格）；JSON 键序为 name/version/git_version(/path)，git 短版本取 `rubygems_ext.rb:264-267` 的 7 字符；2.7.2 无 `--format`，按未知开关拒绝
- 我方行为：`Commands.list`（`src/celerite/cli/commands.cr:1755`）按同一顺序校验（互斥在 `:1769` 与 `:1783`，未知开关在 `:1760`、位置参数在 `:1763`），JSON 在 `:1868-1886` 用保序哈希输出，非法格式文案在 `:1864`，`spec_git_version`（`:2394`）取 `revision[0,7]`；`--format` 按 `profile_bundler_version`（`:2426`）门控
- 判据：`bash script/differential list-json list-json-name list-format-invalid list-option-conflict`；`crystal spec spec/m7_list_format_spec.cr`
- 边界：已声明差异——普通环境探针里参考把宿主已安装的 `thor` 纳入候选，我方非 `--local`/`--prefer-local` 路径只看索引
- 生效：2026-11-16 批次（task 号未记录）
- 取代：无

## C-M7-2-007 list 的分组发现在无桥环境下同样生效，--only-group 不再误报组不存在

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/list.rb:19-25` 直接读 `Bundler.load.specs`，`--only-group <真实组>` 在普通用户环境 exit 0；只有组名确实不存在时才报 `` `<g>` group could not be found.``
- 我方行为：`available_groups`（`src/celerite/cli/commands.cr:1744`）在取不到锁分组时降级为 `["default"]`，`filter_locked_specs_by_groups`（`:2757`）加 rescue；修前 `bridge_available?` 门控使普通环境误报组不存在并返回 15
- 判据：`crystal spec spec/m7_list_groups_plain_env_spec.cr`；`bash script/differential list-only-group list-multi-group`
- 边界：该 spec 依赖已构建的 `bin/celerite.exe`，产物缺失时 `pending!`；组名误报与真实缺失的区分只在单元层断言
- 生效：2026-11-16 批次（task 号未记录）
- 取代：无

## C-M7-2-008 show 与 info 对被忽略组的依赖抛 GemNotFound 7，且未安装的锁定 gem 优先于组消息

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/common.rb:60-66 verbalize_groups` 单组给 `group 'x'`、多组给 `groups 'x' and 'y'`；`cli/common.rb:68-96 select_spec` 对该依赖抛 `Could not find gem '<name>', because it's in the <group(s)>, configured to be ignored.`；`cli/show.rb:13-17` 与 `cli/info.rb:11-15` 都先 `Bundler.load.lock` 再 `select_spec`，故未安装先于组消息
- 我方行为：`show_info` 的组解析改无条件，`verbalize_groups`（`src/celerite/cli/commands.cr:2691`）经 `word_wrap`（`:1180`）输出后返回 7；锁定 gem 的缺失检查前移到解析请求 gem 之前（`:2098`）
- 判据：`bash script/differential show-group-ignored show-missing-installed`；`crystal spec spec/m7_show_group_filter_spec.cr`
- 边界：`show --paths <被过滤 gem>` 手工实测一致但未入差分；`BUNDLE_WITH` 与 `BUNDLE_WITHOUT` 同时设置未对照
- 生效：2026-11-16 批次（task 号未记录）
- 取代：无

## C-M7-2-009 无 lockfile 时 show 与 info 先解析 Gemfile 再发现，缺失文案取依赖显示名

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/show.rb:13-17` 与 `cli/info.rb:11-15` 都先 `Bundler.load.lock`，再走 `definition.rb:249-251` 的 `specs` = `materialize(requested_dependencies)`，无 lockfile 时先解析 Gemfile；未命中再走 `cli/common.rb:98-101 default_gem_spec`；缺失文案带依赖显示名与 requirement
- 我方行为：`show_info` 以 `resolved_from_gemfile = !definition.lockfile_exists?` 触发现场解析（`src/celerite/cli/commands.cr:1995` 函数入口、`:2056` 判定、`:2060-2070` 记录 `dependency_displays`、`:2105` 使用显示名）；`system_gem_search_dirs` 去掉桥门控（`src/celerite/cli/commands_surface.cr:1743`）；`Config.user_home` 先认 `HOME`（`src/celerite/config.cr:329`）
- 判据：`bash script/differential show-no-lockfile-missing show-no-lockfile-installed`；`crystal spec spec/m7_show_no_lockfile_spec.cr`
- 边界：已声明差异——`file://C:/...` 两斜杠写法参考可解析、我方 URI 归一化后报不同源的 not-found（规范写法 `file:///C:/...` 两侧一致）
- 生效：2026-11-16 批次（task 号未记录）
- 取代：无

## C-M7-2-010 info 与 show 在精确名未命中时回退解释器默认 gem，多候选时打印编号菜单

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/common.rb:68-96 select_spec` 精确名未命中时按 `Regexp.new(name)` 收窄并追加 `default_gem_spec`，候选 0 走 not-found、1 直接取、多于 1 走 `cli/common.rb:103-111 ask_for_spec_from` 的 `<n> : <name>` 加 `0 : - exit -` 与 `> ` 菜单（EOF 取 0 不选）；`cli/common.rb:98-101 default_gem_spec` 要求 `default_gem?`
- 我方行为：新增 `DefaultGemInfo`、`parse_spec_name_regex`、`lookup_default_gem`、`append_gemspec_metadata`（`src/celerite/cli/commands.cr:1923-1984`），菜单从 `STDIN.gets` 取序号，EOF 时补一个空格对齐 `>  ` 的字节
- 判据：`bash script/differential info-default-gem-fallback info-regex-menu`；`crystal spec spec/m7_info_select_spec.cr`
- 边界：菜单「输入序号选中」分支无端到端用例，只覆盖 EOF 退出 0；`gem_not_found_message` 的 `Did you mean …?` 未实现；`info bundler` 的 `Path` 不入断言（差分里参考经检出树加载、无对应 gemspec）
- 生效：task-71（`e932fe6`）
- 取代：无

## C-M7-2-011 info 按固定顺序输出 gemspec 字段，PATH 与 GIT 源的元数据在已装 specifications 缺位时回退读 gem 目录

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli/info.rb:50-73 print_gem_info` 依次输出 `  * name (version)`、Summary、Homepage、Documentation、Source Code、Funding、Wiki、Changelog、Bug Tracker、Mailing List、`Path:`、`Default Gem: yes`（仅默认 gem）与 `Reverse Dependencies: ` 加逐条 `\t\t<line>`；`cli/info.rb:36-48` 的 `--path` 只打路径
- 我方行为：`read_gemspec_info`（`src/celerite/cli/commands.cr:2474`）在已装 specifications 与 abi 目录均未命中时回退读 `gem_dir` 下 gemspec，经 `read_gemspec_info_via_bridge`（`:2637`）与 `Bridge::Client#load_installed_spec`（`src/celerite/bridge/client.cr:347`）取真实 `Gem::Specification`；字段拼装在 `:2349-2363`（`Default Gem` 在 `:2362`、反向依赖块在 `:2364-2367`）
- 判据：`bash script/differential info-metadata-escapes show-info-installed info-reverse-dependencies-path`；`crystal spec spec/m7_reverse_dependencies_spec.cr`
- 边界：`git-installed-discovery` 长期受本机 msys Low-IL `0xC0000022` 阻塞，不作本条通过判据；GIT 与 group 组合、更多平台变体未穷尽
- 生效：task-50（`7c3806b`）
- 取代：无

## C-M7-2-012 check 在依赖已满足时按定义落盘 lockfile，--dry-run 与 frozen 下不写

- 状态：已实现
- 参考行为（4.0.24）：`cli/check.rb:27-35` 在 `not_installed` 为空时先 `definition.lock(true) unless options[:"dry-run"]`（`:33`），再打 `The Gemfile's dependencies are satisfied`（`:34`）；仅 `BUNDLED WITH` 过期时不改写锁（`definition.rb:415-417` 的 `lockfiles_equal?` 早退）
- 我方行为：`Commands.run_check`（`src/celerite/cli/commands.cr:1495`）成功路径按定义落盘，`--dry-run` 与 frozen 走只读分支；`materialize_lockfile`（`:1458`）负责无锁时的内存锁；frozen 且无锁时在 `:1516` 抛 `ProductionError`
- 判据：`bash script/differential check-rewrites-lock check-dry-run-keeps-lock`；`crystal spec spec/m7_check_rewrite_spec.cr`
- 边界：无 Ruby 桥时成功落盘分支跳过（fail-safe），未单独 fixture
- 生效：task-35（短哈希未记录）
- 取代：无

## C-M7-2-013 check 在 Gemfile 依赖集不在锁内时先重新解析，缺失打印三行后 exit 1 且不写锁

- 状态：已实现
- 参考行为（4.0.24）：`definition.rb:172-182 check!` 在 `@dependency_changes` 为真时 `resolve_remotely!`（注释逐字说明否则会把 gem 锁到错误源并丢 CHECKSUMS）；`cli/check.rb:18-25` 在解析抛 `GemNotFound`/`GitError`/`SolveFailure` 时报 `Bundler can't satisfy your Gemfile's dependencies.`（`:22`）加 `` Install missing gems with `bundle install`. ``（`:23`）并 exit 1
- 我方行为：`Definition#gemfile_dependency_changes?`（`src/celerite/definition.cr:179`）判定后由 `run_check` 走 `Resolution#resolve!`（重解标记在 `src/celerite/cli/commands.cr:1562-1568`），逐段打印 `Fetching source index from …` 与 `Resolving dependencies...`（`:1623`、`:1655`、`:1680`）；解析失败的两行 cannot-satisfy 文本在 `:1584-1585`，缺失三行文案在 `:1700-1704`（stale 变体在 `:1690-1695`）
- 判据：`bash script/differential check-gemfile-new-dependency`；`crystal spec spec/m7_check_missing_dependency_spec.cr`
- 边界：索引不可达时参考 exit 17、我方 exit 1 加两行 cannot-satisfy；放宽 requirement 时参考重写 `DEPENDENCIES`、我方不改写
- 生效：task-67（`ab91101`）
- 取代：无

## C-M7-2-014 frozen 模式下 ruby 解锁被拒：check exit 16，show 与 info 仍 exit 0，list 不打印解析通知

- 状态：已实现
- 参考行为（4.0.24）：`definition.rb:421-425` 在 `Bundler.frozen_bundle?` 且锁内容不一致时 `raise ProductionError`，消息由 `lockfile_changes_summary("frozen mode is set")` 拼装（`definition.rb:616-622` 取 `change_reason` 首字母大写 + `the lockfile can't be updated because …`），`unlocking_reason` 在 `definition.rb:890-903` 给出 `bundler is unlocking ruby`；`errors.rb:35` 给状态 16，`friendly_errors.rb:26-36` 按 `wrap: true` 折行；show 与 info 不触发该检查；2.7.2 frozen `check` exit 0 且无通知
- 我方行为：`run_check` 在算出 `lock_ruby_unlock_kind` 后、任何 stdout 之前按 profile 决定打印 `Resolving dependencies...` 或 `raise ProductionError`（`src/celerite/cli/commands.cr:1616-1630`，另两处通知在 `:1655`、`:1680`），`show_info` 不加守卫
- 判据：`bash script/differential check-frozen-ruby-nolock show-frozen-ruby-nolock`；`crystal spec spec/m7_frozen_ruby_unlock_spec.cr`
- 边界：提示段锁文件名用 `File.basename`，参考用相对 `Dir.current` 的路径；`.bundle/config` 中 `BUNDLE_FROZEN: "true"` 的变体未单独 fixture
- 生效：2026-11-15 批次（task 号未记录）
- 取代：无

## C-M7-2-015 install --local 未命中文案随 vendor/cache 是否存在分档

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`source/rubygems.rb:122-136 Source::Rubygems#to_s` 在 `@allow_cached && @allow_local` 时给 `cached gems or installed locally`，否则给 `locally installed gems`；`definition.rb:190-203 setup_domain!` 先 `sources.cached!` 再按 `options[:local]` 走 `sources.local!`；`resolver.rb:334-361 raise_not_found!` 在 `Bundler.app_cache.exist?` 为真时追加 ` or in gems cached in <cache_path>`，`cache_path` 默认见 `settings.rb:304-306`
- 我方行为：`Resolution` 的 local-only 源描述按 `app_cache_present?` 分档（`src/celerite/resolution.cr:1770-1786`，`app_cache_present?` 在 `:899`、`app_cache_label` 在 `:906`），not-found 追加串在 `:1819`；本轮未改任何 `src/` 实现
- 判据：`bash script/differential install-local-vendor-cache install-local-index-unreachable install-local-no-cache`；`crystal spec spec/m7_install_failure_spec.cr`
- 边界：`--prefer-local` 的未命中文案未单独取 oracle；`vendor/cache` 之外的自定义 `cache_path` 未取 oracle
- 生效：task-121（短哈希未记录）
- 取代：无

## C-M7-2-016 info 与 show 拒绝第二个位置参数，list 的 usage 行不带 [OPTIONS]

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli.rb:377` 声明 `desc "info GEM [OPTIONS]"`、`cli.rb:348` 声明 `desc "show GEM [OPTIONS]"`、`cli.rb:364` 声明 `desc "list"`（无 `[OPTIONS]`）；Thor 在 `run` 之前拒绝多余位置参数，输出 `ERROR: "bundle info" was called with arguments [...]` 与对应 `Usage:` 行，exit 15
- 我方行为：`NO_ARG_USAGE`（`src/celerite/cli/commands.cr:764`）给 `info` 与 `show` 记 `GEM [OPTIONS]`、给 `list` 记空串；`reject_positional_arguments`（`:791`）在 `show_info` 以 `max_positionals: 1` 调用（`:2024`）
- 判据：`bash script/differential info-extra-argument show-extra-argument list-extra-argument`；`crystal spec spec/m7_extra_arguments_spec.cr`
- 边界：多余参数与 `--version`、`--paths` 的组合未逐一取 oracle
- 生效：task-70（`a67d1d8`）
- 取代：无

## C-M7-2-017 check、list、show、info 在读 Gemfile 之前拒绝未知开关

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`cli.rb` 的 `method_option` 声明决定各命令开关面；Thor 解析期报 `Unknown switches "…"`（原始 token，多个以 `, ` 分隔）并 exit 15，`friendly_errors.rb:31-36` 走 `ui.error`，发生在读 Gemfile 与 lockfile 之前
- 我方行为：`unknown_switch_tokens`（`src/celerite/cli/commands.cr:724`）与 `reject_unknown_switches`（`:840`）在 `Definition.build` 之前拦截，`check` 在 `:1420`、`list` 在 `:1760`、`show_info` 在 `:2001` 调用
- 判据：`bash script/differential unknown-switch-check unknown-switch-list unknown-switch-show`；`crystal spec spec/m7_unknown_switches_spec.cr`
- 边界：`Did you mean?` 建议行未实现；`--help` 的 manpage 文本不复刻
- 生效：2026-11-15 批次（task 号未记录）
- 取代：无
