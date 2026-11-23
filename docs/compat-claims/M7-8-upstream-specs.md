# M7-8 上游 lockfile 套件：真实驱动、退出码与失败分桶（claims）

本文件是 M7-8 的断言账本：把 `../compat-evidence/` 与 `../../script/upstream-specs` 已取证的结论逐条固化为可复跑断言。原始建档、逐字输出与分桶快照仍留在 evidence，本文件只写结论与判据。范围 = `script/upstream-specs`（上游 Bundler lockfile 家族 harness）的驱动方式、退出码语义、覆盖边界与失败分桶，以及被该套件点出的 lockfile 行为断言；度量数字归 `../compat-report.md` 的 Current metrics，不进本文件。

## C-M7-8-001 套件经 PATH 上的 `bundle` shim 把上游例内的 `bundle` 调用真实路由到 Celerite

- 状态：已实现
- 参考行为（4.0.24）：上游 `bundle` 调用统一走 `spec/support/helpers.rb:70-100` 的 `def bundle(cmd, options = {}, &block)`，它取 `bundle_bin`（默认 `installed_bindir.join("bundle")`）并把 `:env`/`:dir`/`:raise_on_error` 从 options 里摘出来，其余转成 `" --#{k} #{v}"` 形式的 argv。
- 我方行为：`script/upstream-specs:86-105` 在 shim 目录写 `bundle`/`bundle.cmd`/`bundle.bat` 并把该目录前置进 `PATH`；`:174-176` 默认把 `rspec_pre_args` 设为 `-r script/upstream-specs-celerite-override.rb`；`script/upstream-specs-celerite-override.rb:15-30` 重写 `Spec::Helpers#bundle`，按 `CELERITE_BIN` 取二进制、映射 `:env`/`:raise_on_error`/`:dir` 并清空 `BUNDLE_GEMFILE`。
- 判据：`bash script/upstream-specs`
- 边界：`CELERITE_SKIP_TEST_DEPS=1` 时跳过上游 `install_test_deps`（`spec/support/rubygems_ext.rb:30-32`、`:58-67`），故部分用例依赖的 dev 依赖不在场。
- 生效：task-8（默认加载 override）
- 取代：无

## C-M7-8-002 `CELERITE_BUNDLE_HELPER_OVERRIDE=0` 退回基线驱动，报告打印 `WARNING: NOT driving celerite`

- 状态：已实现
- 参考行为（4.0.24）：基线驱动即上游 binstub 自身，此时套件结果不代表 Celerite。
- 我方行为：`script/upstream-specs:175` 只在 `CELERITE_BUNDLE_HELPER_OVERRIDE` 不为 `0` 时才注入 `-r` override；`:193` 用 `grep -c -E 'celerite(\.exe)? '` 统计真实驱动次数写进 `- real-drive: <n> celerite invocations`（`:255`），为 0 时打印 `- WARNING: NOT driving celerite (helper override disabled or not applied)`（`:257`）。
- 判据：`CELERITE_BUNDLE_HELPER_OVERRIDE=0 bash script/upstream-specs`
- 边界：警告只是报告行，不改变退出码；误以为「跑过」的风险由该行与 real-drive 计数共同承担。
- 生效：task-8
- 取代：无

## C-M7-8-003 rspec 的非零退出经 `pipefail` 传成 harness 的退出码

- 状态：已实现
- 参考行为（4.0.24）：上游套件以 rspec 退出码表达「有失败」，harness 不得吞掉。
- 我方行为：`script/upstream-specs:29` 为 `set -uo pipefail`；`:179-183` 的 rspec 调用行不带 `|| true`；`:184` 记 `rspec_status=$?`，报告仍照常写完（`:201-274`），`:277` 为 `exit $rspec_status`。
- 判据：`bash script/upstream-specs`
- 边界：脚本里仍有若干 `|| true`（`:64` 的 sparse-checkout、`:76-78` 的 gem fetch/generate_index、`:93` 的 chmod、`:144-147` 的探测、`:185`/`:187`/`:193` 的 tail/grep 统计），它们都不在 rspec 退出码通路上；`docs/compat-report.md` 里「移除 line 64 附近 `|| true`」的措辞指向那次 rspec 管道改动，而非 `:64` 本身。
- 生效：task-8（2026-11-10）
- 取代：无

## C-M7-8-004 套件只跑 lockfile 家族的 `spec/lock/lockfile_spec.rb`，不作 full upstream suite 声明

- 状态：已声明差异
- 参考行为（4.0.24）：上游 Bundler 的 spec 树包含 resolver/runtime/resource/plugins 等多个家族；只跑 lockfile 家族不能替代整体兼容性结论。
- 我方行为：`script/upstream-specs:179` 只把 `spec/lock/lockfile_spec.rb` 传给 rspec。
- 判据：`bash script/upstream-specs`
- 边界：其余家族只有选定差分行为覆盖；`docs/upstream-spec-spike.md` 记录初始适用性评估；pending 与未执行用例、以及「由参考 Ruby runtime 提供」的行为都不算通过——覆盖边界的正式措辞在 `../compat-report.md` 的 `## Upstream spec suite coverage boundary` 节。
- 生效：task-8
- 取代：无

## C-M7-8-005 失败按异常类与消息特征分到七个桶，harness 与离线重算共用同一规则模块

- 状态：已实现
- 参考行为（4.0.24）：上游失败原因分环境（artifice 不可达、网络策略、Low-IL 共享内存、跳过 dev 依赖）与产品两类，混在一起无法判断兼容性缺口。
- 我方行为：`script/upstream-specs-buckets.rb:7-19` 的规则表自上而下首命中，`:42` 的 `classify(klass, message, backtrace)` 产出 `env:artifice-unreachable`/`env:network-policy`/`env:low-il-shm`/`env:test-deps-skipped`/`fixture:missing-gem-files`/`fixture:fetch-failed`/`product:candidates` 七个桶；`script/upstream-specs:199-234` 用 `-r script/upstream-specs-buckets.rb` 调同一函数写 `failure-buckets.md`，`:210-212` 的注释明写「规则表放在该模块里，离线重算也走同一分类」。
- 判据：`bash script/upstream-specs`
- 边界：桶名与顺序由 `:30-37` 的 `ORDER` 固定；分桶只用于归因，不改变 rspec 退出码。
- 生效：task-91
- 取代：无

## C-M7-8-006 断言失败一律归 `product:candidates`，不因消息里出现 `Fetching ` 落入夹具桶

- 状态：已实现
- 参考行为（4.0.24）：锁体断言失败是产品行为差异；夹具问题不会表现为 `RSpec::Expectations::ExpectationNotMetError`。
- 我方行为：`script/upstream-specs-buckets.rb:48` 在 `klass == ASSERTION_CLASS`（`RSpec::Expectations::ExpectationNotMetError`）时直接返回 `product:candidates`，`:49` 对消息同时含 `expected:` 与 `got:` 的也归产品桶，两者都排在 `:53` 的 `text.include?("Fetching ")` 判定之前；`:26` 的注释记录该顺序来自 task-86 发现「`got:` 文本合法包含 `Fetching source index ...` 导致锁体断言被扫进夹具桶」。
- 判据：`bash script/upstream-specs`
- 边界：仅对异常类与该消息形态成立；其他失败仍按 `Fetching ` 归 `fixture:fetch-failed`。
- 生效：task-91
- 取代：无

## C-M7-8-007 环境类桶先于产品类桶判定

- 状态：已实现
- 参考行为（4.0.24）：引用环境字符串（`Could not reach host`、`HTTP 403`、`0xC0000022`、`sinatra/base`）的断言失败仍属环境问题。
- 我方行为：`script/upstream-specs-buckets.rb:44-47` 的四条环境判定（artifice 不可达、403、`NtCreateDirectoryObject`/`0xC0000022`、缺 dev 依赖）都排在 `:48` 的异常类判定之前；`:21-26` 的注释说明该顺序的理由。
- 判据：`bash script/upstream-specs`
- 边界：环境桶由宿主条件决定，同一用例在不同宿主上可能换桶；换桶不等于产品行为改变。
- 生效：task-91
- 取代：无

## C-M7-8-008 CHECKSUMS 段整行缺失时 `install` 打印 `Resolving dependencies...` 并真解析

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:626-628` `install_needed?` = `resolve_needed? || missing_specs?`；`:647-649` `resolve_needed?` = `unlocking? || something_changed?`；`:630-645` `something_changed?` 里 `:641` 的 `@locked_spec_with_missing_checksums` 无条件参与，故缺行必然触发解析，`:342-363` 的 `resolve` 走 `start_resolution` 后由 `lib/bundler/resolver.rb:34` 打印该行。缺行由 `lib/bundler/lockfile_parser.rb:259-288` 登记 nil、经 `lib/bundler/checksum.rb:204-206` 的 `missing?` 判定。
- 我方行为：`src/celerite/definition.cr:598` 的 `checksums_need_refresh?` 返回 `ChecksumsRefreshReason?`（`:580-583` 定义 `Missing`/`Empty`），`:619` 对缺行返回 `Missing`；`src/celerite/cli/commands_install.cr:369` 据此放弃复用、`:376` 只在成因为 `Empty` 且 profile 非 2.x 时抑制 `show_resolving`。
- 判据：`bash script/differential checksums-refresh-cache-deleted`；`crystal spec spec/m7_checksums_trigger_spec.cr`
- 边界：该夹具用预置初态替代中间步骤；`file://` 索引不写 digest，故两侧只补回裸行；空值形态在 2.7.2 上未实测（见 C-M7-8-009）。
- 生效：task-116
- 取代：无

## C-M7-8-009 CHECKSUMS 条目存在但值空时不触发解析，`install` 不打印 `Resolving dependencies...`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:642` 把空值形态交给 `:651-659` 的 `empty_checksums_actionable?`，后者读 `sources.local_mode?`，求值发生在 `setup_domain!` 的 `remote!` 之前故为 local，返回 false，于是 `something_changed?` 不成立、只 debug 一句 `Found no changes, using resolution from the lockfile`。空值由 `lib/bundler/checksum.rb:207-212` 的 `empty?` 判定。
- 我方行为：`src/celerite/definition.cr:620` 对空值返回 `ChecksumsRefreshReason::Empty`；`src/celerite/cli/commands_install.cr:376` 在成因为 `Empty` 且 bridge profile 不以 `2.` 开头时把 `show_resolving` 置 false；`src/celerite/cli/commands.cr:3025` 的 `lock` 侧只看成因是否为 nil。
- 判据：`bash script/differential checksums-empty-lock`；`crystal spec spec/m7_checksums_trigger_spec.cr`
- 边界：2.7.2 的 `lib/bundler/definition.rb:599-600` 把 `@locked_spec_with_empty_checksums` 直接并入 `resolve_needed?`，预计会打印该行，但我方抑制只作用于非 2.x；该形态在 2.7.2 上未实测（见 C-M7-8-016）。
- 生效：task-116
- 取代：无

## C-M7-8-010 锁依赖边缺失时自愈保持锁定版本，不升级到索引里的更高版本

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:699-708` 的 `materialize` 捕获 `IncorrectLockfileDependencies` 后调 `reresolve_without([e.spec])`；`:782-785` 的 `reresolve_without` 只做 `resolution_base.delete(incomplete_specs)`；`:1321-1328` 的 `new_resolution_base` 仍把 `@originally_locked_specs` 交给 `Resolver::Base`（`lib/bundler/resolver/base.rb:10-33`），`@gems_to_unlock` 未被触碰，故 `Package#locked_version` 仍指向锁定版本、由 `lib/bundler/gem_version_promoter.rb:134-145` 的 `post_sort` 提到首位。
- 我方行为：`src/celerite/resolution.cr:1704` 的 `refresh_locked_dependencies` 负责补边；自愈分支不再写 `@unlock`，改为 `@excluded_locked_names << name` 并置 `@heal_locked_edges`，另新增 `preferred_locked_versions` 经 `make_source` 传入 `Resolver::ResolutionSource`，使被移出候选表的行仍贡献 `locked_version`。
- 判据：`bash script/differential install-autoheals-locked-dependency-edges`；`crystal spec spec/m7_lock_autoheal_spec.cr`
- 边界：宿主 gem 可见形态下我方多打 3–4 行 `Resolving dependencies...` 而参考 2 行，该形态依赖宿主安装状态故未做夹具；自愈只覆盖 GEM 源的锁定行，PATH/GIT 行的依赖边未纳入；`lock` 仍不补依赖边。
- 生效：task-115
- 取代：无

## C-M7-8-011 锁定 spec 行缺失但依赖边仍在时，`lock` 按参考剔除该行并重解析

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:973-1015` 的 `check_lockfile` 用 `@locked_specs.validate_deps(s)` 分流 `:missing`/`:invalid`（`lib/bundler/spec_set.rb:87-96`），`:1001-1002` 记下首个缺行名，缺行/无效则把该 spec 从锁定集合删掉再解析；`lib/bundler/cli/lock.rb:78-97` 是 `lock` 的落盘路径。
- 我方行为：`src/celerite/resolution.cr:447` 提供 `incomplete_locked_spec_names`、`:669` 的 `drop_incomplete_locked_specs` 开关在 `:1195-1203` 把命中行并入 `@dropped_locked_names` 与 `@excluded_locked_names`，`:2113` 在构造时跳过这些名字；`src/celerite/cli/commands.cr:3032` 在 `lock` 路径打开该开关。
- 判据：`bash script/differential lock-missing-locked-spec-line`；`crystal spec spec/m7_lock_missing_spec_row_spec.cr`
- 边界：只覆盖 GEM 源的锁定行；`lock` 不补依赖边（那是 install 侧的自愈，见 C-M7-8-010）。
- 生效：task-117
- 取代：无

## C-M7-8-012 `--local` 且锁已存在时不再无条件复用锁定集合，Gemfile 新增的未安装依赖报 exit 7

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:190` 的 `setup_domain!` 决定是否走远端源，`:342` 的 `resolve` 据 `no_resolve_needed?` 早返回，`:1051` 的 `converge_dependencies` 处理收敛；本地模式下缺失依赖由 `lib/bundler/resolver.rb:334` 的 `raise_not_found!` 报 `Could not find gem '<name>' in locally installed gems.`。
- 我方行为：`src/celerite/resolution.cr:1076` 的早返回条件加上 `lockfile_covers_all_dependencies?(deps)`（`:1323`，实现为「锁里 spec 名集合覆盖全部依赖名」），故锁里完全没有的依赖不会被静默丢弃，改由本地源报未找到并 exit 7、不写锁。
- 判据：`bash script/differential install-local-new-dep-not-installed`；`crystal spec spec/m7_local_install_missing_dep_spec.cr`
- 边界：该夹具用 `file://` 索引 + 预置 `bundle-preset`，只覆盖 `install --local`；`update --local` 的同形分歧靠同一修复消除但只有手工 A/B，无常驻夹具。
- 生效：task-120
- 取代：无

## C-M7-8-013 上游夹具仓被毒化时 harness 自愈，取不到本机 rake 缓存则 fail-open 并告警

- 状态：已实现
- 参考行为（4.0.24）：`spec/spec_helper.rb:141` 的 `before(:suite)` 调 `build_repo1`；`spec/support/builders.rb:29-31` 复制 `rake_path` 到 `gem_repo1/gems/`；`rake_path` 由 `spec/support/path.rb:298-300`/`:322-324` 在 `tmp/gems/base/<engine>/<ruby_version>` 下 glob `rake-*.gem` 解析，而该缓存只由 `spec/support/rubygems_ext.rb:58-67` 的 `install_test_deps` 播种——`CELERITE_SKIP_TEST_DEPS=1` 跳过它。缺 gem 时 `builders.rb:269-275` 的 `build_repo` 已 `mkdir_p` 过目录、`return if File.directory?(path)` 使空仓永久保留，`:183-186` 的 `build_repo2` 再 `cp_r` 复制空仓。
- 我方行为：`script/upstream-specs:121-156` 在 rspec 之前检查：`remote1/gems` 存在但无 `*.gem` 则删 `remote1` 与 `remote2`；`tmp/gems/base` 下无 `rake-*.gem` 则从 `Gem::Specification.find_by_name("rake").cache_file`（回退 `Gem.default_dir/cache/rake-*.gem`）复制进 `<engine>/<ruby_version>/cache/`；两者都取不到时打印 warning 并保留旧空仓库，不伪造成通过。
- 判据：`CELERITE_SKIP_TEST_DEPS=1 bash script/upstream-specs`
- 边界：修复依赖本机 rake gem 缓存；不改上游 spec 源码、不跳过也不弱化任何断言。
- 生效：task-23
- 取代：无

## C-M7-8-014 harness 的报告只写 `.upstream-specs/`，不写 `docs/`

- 状态：已实现
- 参考行为（4.0.24）：策展证据文档由人工追加，机器跑出来的快照不能直接进文档树。
- 我方行为：`script/upstream-specs:117-118` 把 `rspec-output.json` 与 `failure-buckets.md` 落在 `.upstream-specs/`；注释（`:34-35`）明写 harness 不得写 `docs/`。
- 判据：`bash script/upstream-specs`
- 边界：`.upstream-specs/` 是工作目录产物，不入库；`docs/compat-matrix/generated/` 下的策展文件由人工从产物摘录。
- 生效：task-8
- 取代：无

## C-M7-8-015 harness 只探测既有 celerite 二进制，不自行重建

- 状态：已实现
- 参考行为（4.0.24）：上游套件测的是 CLI 行为，二进制从哪来不属于套件职责。
- 我方行为：`script/upstream-specs:40-52` 只检查 `bin/celerite` 或 `bin/celerite.exe` 是否存在，缺失则 `:51` 退出 127，全程不调用 `shards build`。
- 判据：`bash script/upstream-specs`
- 边界：套件结果绑定当时的二进制时间戳，结论只在同一构建上可比；换构建后必须重采。
- 生效：task-8
- 取代：无

## C-M7-8-016 套件结论只覆盖 4.0.24 profile，2.7.2 未复采

- 状态：未验证
- 参考行为（2.7.2）：上游在 2.7.2 与 4.0.24 上的 lockfile 行为存在已知差异（例如空 CHECKSUMS 条目会直接并入 `resolve_needed?`，见 `lib/bundler/definition.rb:599-600`）。
- 我方行为：未改代码；`script/upstream-specs` 的 `UPSTREAM_REV` 默认 `v4.0.24`（`:32`），`.upstream-specs/v2.7.2` 下无 bundler checkout，故 2.7.2 从未在本 harness 上跑过。
- 判据：`UPSTREAM_REV=v2.7.2 bash script/upstream-specs`
- 边界：该组合当前跑不起来（缺 checkout），因此 2.7.2 侧的套件结论为空——不是「无差异」，只是未验证；2.7.2 的兼容结论目前只由差分夹具的定向用例支撑。
- 生效：task-118（复采记录中明确标注该 profile 未复采）
- 取代：无

## C-M7-8-017 补充 CHECKSUMS digest 与 `path_expander` 锁体行的两处未对齐

- 状态：已声明差异
- 参考行为（4.0.24）：`spec/lock/lockfile_spec.rb:1682`（`fills empty CHECKSUMS entries when not frozen, even if every gem is already installed`）要求把每个已安装 gem 的 CHECKSUMS digest 补齐；`spec/lock/lockfile_spec.rb:2215` 要求自愈后锁体含 `path_expander (1.1.1)` 行。
- 我方行为：未改代码；复采中该两处仍为失败，归入 `product:candidates`，尚未取到 oracle 也未修复。
- 判据：`bash script/upstream-specs`
- 边界：本轮只做到「定性为产品候选」，具体差异字节与参考写法的对照仍需一轮离线 oracle；在取到 oracle 之前不得当作已对齐。
- 生效：task-118
- 取代：无

## C-M7-8-018 完整锁里指向 `bundler` 的依赖边不再让锁被误判为不完整而重写

- 状态：已实现
- 参考行为（4.0.24；2.7.2 同族）：`bundler` 没有自己的 spec 行，参考只在 CHECKSUMS 里合成 `LazySpecification`（`lib/bundler/lockfile_parser.rb:274-276`），它永不进解析器；`SpecSet#validate_deps`（`spec_set.rb:87-96`）在依赖边校验里同层跳过该名字，故指向 `bundler` 的边不会让完整锁看起来未被覆盖。
- 我方行为：`src/celerite/resolution.cr` 的 `lockfile_covers_dependencies?` 在 spec 依赖边循环首行跳过 `bundler`（与 `:1488` 依赖名循环的 `next if dep.name == "bundler"`、`incomplete_locked_names` 的同类跳过一致），rails 规模的 `bundler (>= 1.15.0)` 边因此不再把 `install` 推回 `run_resolution` 重写锁。
- 判据：`bash script/differential install-keeps-lock-with-bundler-edge`；`crystal spec spec/m7_install_keeps_lock_with_bundler_edge_spec.cr`
- 边界：修复与夹具在 task-166 的分支上（main 为 `1a66a38`/`74fb6e4`），双 profile PASS、spec 1 例通过；本账本所在提交（`045f778`）尚未并入该夹具与 spec，在本树跑判据只会得到 0 例静默通过，合入前不得据此判为已验证。
- 生效：task-166（1a66a38）
- 取代：无

## C-M7-8-019 `install` 重写锁时依赖行按字母序输出，锁内容与 `lock` 的产物一致

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/lazy_specification.rb:117` 的 `to_lock` 把 spec 的依赖行按 `dep.to_s` 排序并去重，故 `lock` 与任何重写路径写出的行序都相同
- 我方行为：`src/celerite/lockfile/model.cr:110-124` 在 GEM 段渲染前对依赖行 `String.build` → `.uniq` → `.sort!`；`src/celerite/resolution.cr:1769-1775` 与 `:1785-1789` 用 `dependency_lock_lines` 做集合比较，纯换序不再算需要修复，故不会多写一次锁或多打一行 `Resolving dependencies...`
- 判据：`bash script/differential install-rewrites-lock-in-lock-order`；`crystal spec spec/m7_install_lock_dep_order_spec.cr`
- 边界：夹具用本地合成桩（`extra/vendor/cache`）而非真实 gem；`lock` 之后 `install --local` 不多出 `Resolving dependencies...` 由该夹具的 stdout 对照间接钉住，未单独断写盘次数；渲染时的排序与去重由 spec 钉住
- 生效：task-175（4b757bc）
- 取代：无
