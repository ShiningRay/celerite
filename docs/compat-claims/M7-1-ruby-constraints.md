# M7-1 Ruby / RubyGems / engine / patchlevel / ABI 约束过滤（claims）

本文件是 M7-1 的断言账本：把 `../compat-evidence/` 里已取证的 Ruby / RubyGems / engine / patchlevel / ABI 约束过滤结论逐条固化为可复跑断言。原始建档、逐字输出与探针目录仍留在 evidence，本文件只写结论与判据。

## C-M7-1-001 Ruby 运行时声明与当前解释器不一致时，check / show / binstubs 以 18 退出

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:494-523 validate_runtime!` → `:499 validate_ruby!` 用 `ruby_version.diff(Bundler::RubyVersion.system)` 取 `problem, expected, actual`，按 `:engine` / `:version` / `:engine_version` / `:patchlevel` 四分支组装消息后 `raise RubyVersionMismatch, msg`；`lib/bundler/errors.rb:44 class RubyVersionMismatch < BundlerError; status_code(18); end`；`lib/bundler/cli/check.rb:11-16`、`lib/bundler/cli/show.rb:15`、`lib/bundler/cli/binstubs.rb:12` 都是先 `validate_runtime!` 再做各自逻辑，故坏 ruby 声明下 binstubs 报 18 而不是用法错误。
- 我方行为：`src/celerite/cli/commands.cr:1310 def self.validate_ruby_runtime!(definition : Definition, bridge : Bridge::Client? = nil) : Nil`（真 mismatch 一律上抛）；`src/celerite/ruby_runtime.cr:17 raise RubyVersionMismatch.new(msg)`；`src/celerite/errors.cr:512 class RubyVersionMismatch < Error` status 18；binstubs 侧 `src/celerite/cli/commands_install.cr:2086 Commands.validate_runtime!(definition)` 位于用法检查之前（`src/celerite/cli/commands_install.cr:2073` 为顺序注释）。
- 判据：`bash script/differential ruby-requirement-mismatch`；`crystal spec spec/m7_ruby_runtime_enforcement_spec.cr`
- 边界：bridge 不可用时该校验被整体跳过（已声明 best-effort），跳过不等于通过；`install` / `exec` / `clean` / `outdated` 的同类校验见 C-M7-1-006。
- 生效：task-1（55be109）
- 取代：无

## C-M7-1-002 gem 元数据 required_ruby_version 不满足时该候选被排除

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/match_metadata.rb:9 def matches_current_ruby?` → `@required_ruby_version.satisfied_by?(Gem.ruby_version)`；`lib/bundler/match_remote_metadata.rb:8` 为远程同形。比较基准是运行时 `Gem.ruby_version`，不含 patchlevel。
- 我方行为：`src/celerite/resolver/source.cr:312 private def ruby_requirement_satisfied?(spec : IndexSpec) : Bool`，`src/celerite/resolver/source.cr:313 return false unless spec.required_ruby_version.satisfied_by?(Gem::Version.new(running_ruby_version))`；`:321 private def running_ruby_version : String` 取 bridge 报告的 `ruby_environment.ruby_version`；调用点 `src/celerite/resolver/source.cr:228` 与 `:455 excluded = platform_specs.reject { |spec| ruby_requirement_satisfied?(spec) }`。
- 判据：`bash script/differential ruby-metadata-match ruby-metadata-exact-match ruby-metadata-boundary-match ruby-metadata-fail ruby-metadata-boundary-fail ruby-metadata-remote-fail`；`crystal spec spec/m7_resolver_ruby_constraints_spec.cr`
- 边界：远程负例走本地 `http_index_server.js`（`http-index` 夹具标记），真实 rubygems.org 未触达；`fixtures/gem-index-ruby-constraints` 的 checksum 是占位零值，该索引只服务 `lock`，不能用于 `install` / `check`。
- 生效：task-2（066a646）
- 取代：无

## C-M7-1-003 gem 元数据 required_rubygems_version 不满足时该候选被排除

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/match_metadata.rb:13-14 def matches_current_rubygems?` → `@required_rubygems_version.satisfied_by?(Gem.rubygems_version)`；`lib/bundler/match_remote_metadata.rb:18` 缺省回退 `Gem::Requirement.default`。
- 我方行为：`src/celerite/resolver/source.cr:314 return false unless spec.required_rubygems_version.satisfied_by?(Gem::Version.new(running_rubygems_version))`；`:325 private def running_rubygems_version : String` 取 `env.rubygems_version`；`:490 required = spec.required_rubygems_version.to_s` 供排除原因文案。
- 判据：`bash script/differential rubygems-metadata-match rubygems-metadata-boundary-match rubygems-metadata-pessimistic-match rubygems-metadata-fail rubygems-metadata-boundary-fail rubygems-metadata-remote-fail`；`crystal spec spec/m7_resolver_ruby_constraints_spec.cr`
- 边界：边界正例（`>= 4.0.16` 与 bridge 报告版本相等）与负例（`>= 4.0.17`）都以「bridge 报告的 RubyGems 版本」为基准，宿主 RubyGems 版本变化会改变结论；本机只验证过 Ruby 4.0.6 一档。
- 生效：task-2（066a646）
- 取代：无

## C-M7-1-004 根级依赖被元数据排除时，解释文案按版本范围表达被排除的候选

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/vendor/pub_grub/lib/pub_grub/incompatibility.rb:63` → `"#{terms[0].to_s(allow_every: true)} depends on #{terms[1].invert}"`，`lib/bundler/vendor/pub_grub/lib/pub_grub/failure_writer.rb:140` → `"Because #{cause.conflict}\nand #{cause.other},\n#{incompatibility}."`。故根依赖被过滤时参考打印的是具体版本范围（`future_gem >= 1.0.0`），不是 `every version of future_gem`。
- 我方行为：`src/celerite/resolver/source.cr:448 private def raise_metadata_or_not_found!(package : Package, requirement : Gem::Requirement) : NoReturn`；`subject` 三分支——全部候选被排除→`every version of <name>`，被排除集恰为 `>= min` 的连续后缀→`<name> >= <min>`，其余→`<name> = <min>` 保守回退；消息首行 `Because #{subject} depends on …`，其余四行与 exit 6 未动。
- 判据：`bash script/differential ruby-metadata-remote-fail rubygems-metadata-remote-fail`；`crystal spec spec/m7_resolver_ruby_constraints_spec.cr`
- 边界：分支「只有中间版本被排除（非连续后缀）」的参考逐字形态未实测，我方按保守回退 `= <min>` 处理；两条 remote-fail 夹具原先的 `deferred-*` 标记已删除，现为逐字节比较。
- 生效：task-1（f43b02d）
- 取代：无

## C-M7-1-005 gem 元数据匹配只比 RUBY_VERSION，patchlevel 只参与 Gemfile 目标校验

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/match_metadata.rb:9-10` 用 `Gem.ruby_version` 判 `required_ruby_version`，`Gem.ruby_version` 不含 patchlevel；patchlevel 只在 `lib/bundler/definition.rb:512-517` 的 `validate_ruby!`（Gemfile 目标）里比对。
- 我方行为：`src/celerite/resolver/source.cr:321 private def running_ruby_version : String` 明确取 bridge 的 `ruby_environment.ruby_version`（无 patchlevel），原 `running_ruby_version_for_gem` 死代码已删除；`ruby_requirement_satisfied?` 本体未改动。patchlevel 校验在 `src/celerite/ruby_runtime.cr`。
- 判据：`bash script/differential ruby-patchlevel-match`；`crystal spec spec/m7_resolver_ruby_constraints_spec.cr`
- 边界：只在 gem 元数据侧断言；Gemfile 目标 side 的 patchlevel 见 C-M7-1-006。
- 生效：task-2（12202d4）
- 取代：无

## C-M7-1-006 Gemfile 声明的 patchlevel 在 install / clean / exec / outdated 也拒绝，而不只是 check

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli/install.rb:45-46 definition = Bundler.definition(strict: true)` + `definition.validate_runtime!`、`lib/bundler/cli/outdated.rb:32 Bundler.definition.validate_runtime!`（在 `:27 check_for_deployment_mode!` 之后、`:33` 解析之前）；`lib/bundler/cli/clean.rb:11-14` 与 `lib/bundler/cli/exec.rb` 本身没有 `validate_runtime!` 调用，运行时校验是经 `Bundler.load` / 定义构建间接生效。`lib/bundler/definition.rb:512-517` patchlevel 分支产 `"Your Ruby patchlevel is #{actual}, but your Gemfile specified #{expected}"`。故声明 `patchlevel: "999"` 时四条路径都以 18 退出，且不可达 source 也先给 18。
- 我方行为：`src/celerite/cli/commands.cr:1310 validate_ruby_runtime!` 统一入口；四处调用点改用 `Commands.requested_ruby_version(evaluation)`（`src/celerite/cli/commands.cr:1225`）而非 `GemfileEvaluation#ruby` 的人类可读串；`outdated` 把校验移到 `materialize_lockfile` 之前；接线见 `src/celerite/cli/commands_install.cr:245-260` 与 `src/celerite/cli/commands_surface.cr:91` / `:1935` / `:2977`。
- 判据：`bash script/differential install-patchlevel-mismatch install-patchlevel-mismatch-unreachable`；`crystal spec spec/m7_ruby_patchlevel_spec.cr`
- 边界：只对齐运行时校验层；Gemfile patchlevel 与锁文件 / `CHECKSUMS` 的交互未另取 oracle；`BUNDLE_FROZEN` / deployment 与 patchlevel 同时出错时的优先级未逐组合测。
- 生效：task-75（d20cde0）
- 取代：无

## C-M7-1-007 锁文件钉住的版本与索引 requirements 冲突时先复核再复用，冲突则重解或以 exit 6 失败

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/installer.rb:79-82` 在 `setup_domain!(options)` 为真时才执行 `ensure_specs_are_compatible!`；正常流程里解析器已按 `required_ruby_version` / `required_rubygems_version` 过滤候选，故锁内不兼容版本表现为重解（换低版本）或 `SolveFailure`（`lib/bundler/errors.rb:24 class SolveFailure < BundlerError; status_code(6); end`），而 `lib/bundler/installer.rb:234-245 ensure_specs_are_compatible!` 的 `InstallError`（`lib/bundler/errors.rb:21`，status_code 5）在 CLI 下不可达。
- 我方行为：`src/celerite/resolution.cr:1545 private def incompatible_locked_spec_names : Array(String)` 比对锁内钉住版本与索引 requirements；`:1152 incompatible = verify_locked_compat ? incompatible_locked_spec_names : [] of String`（`src/celerite/resolution.cr:1058 def resolve!(reuse : Bool = false, verify_locked_compat : Bool = false)`）；命中名字加入解锁集后重解。`src/celerite/installer.cr:82 def self.ensure_specs_are_compatible!` 逐字复刻参考两条 InstallError 消息，但 CLI 路径不可达，仅由单元例覆盖。
- 判据：`bash script/differential install-locked-ruby-incompatible install-ruby-constraint-locked-resolve install-rubygems-constraint-locked-resolve install-rubygems-constraint-solve-failure`；`crystal spec spec/m7_install_ruby_compat_spec.cr`
- 边界：`ensure_specs_are_compatible!` 的 exit 5 分支未经 CLI 差分；`file://` 参考走 legacy index 需 `specs.4.8.gz`，compact-index 的 `file://` 组合未覆盖；锁内不兼容且无可选低版本时四条夹具只覆盖 `rubygems` 一档的 SolveFailure。
- 生效：task-21（9bceb3f）
- 取代：无

## C-M7-1-008 无 lockfile 的 check 先解析（必要时写锁），再报缺 gem 或满足

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli/check.rb:11-36` 先 `definition.check!` 建定义并解析；缺失非空则 `The following gems are missing` + 逐条 ` * name (version)` + `` Install missing gems with `bundle install` `` + exit 1；否则 `definition.lock(true) unless options[:"dry-run"]` 写锁后打印 `The Gemfile's dependencies are satisfied`。`file:` 源走 `Fetching source index from` 而非 `Fetching gem metadata from`。
- 我方行为：`src/celerite/cli/commands.cr` 的 `run_check` 分支——`resolved_from_gemfile = !definition.lockfile_exists?` 为真时用 `Resolution.new(definition, false)` 现场解析并取 `generated_lockfile`；满足分支前仅当无锁、未带 `--dry-run` 且与磁盘 `semantic_content` 不同才 `Lockfile.write(...)`；`assets/bridge/server.rb` 的 `op_bundler_cache_file` 补 `Gem.default_dir/cache/bundler-<version>.gem` 回退，避免隔离 `GEM_PATH` 下 `CHECKSUMS` 少 `bundler` 行。
- 判据：`bash script/differential check-no-lockfile-missing check-no-lockfile-installed`；`crystal spec spec/m7_check_no_lockfile_spec.cr`
- 边界：无锁且依赖已满足时参考与实现都会写锁，`check-no-lockfile-missing` 只覆盖「都不写锁」这一半；`--dry-run` 只有单元例，未加差分夹具。
- 生效：task-1（4e17691）
- 取代：无

## C-M7-1-009 lockfile 缺 RUBY VERSION 而依赖已满足时，check 打印 Resolving dependencies...

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli/check.rb:11-16` 一进来即 `Bundler.load`；`lib/bundler/resolver.rb:34` → `Bundler.ui.info "Resolving dependencies...", true` 是该行的唯一产出点，`@unlocking_ruby`（Gemfile 声明与锁不一致时为真）成立时才走到解析，故依赖已满足也会打印。参考实测还会把 `RUBY VERSION` 写回 lockfile。2.7.2 无此通知。
- 我方行为：`src/celerite/cli/commands.cr:1370 private def self.lock_ruby_unlock_kind(definition : Definition, lockfile : Lockfile::Data) : Symbol`（`:diff` / `:missing_from_lock` / `:none`）；`:1623 stdout.puts "Resolving dependencies..."` 在其非 `:none` 时打印。
- 判据：`bash script/differential check-satisfied-nolock-ruby`；`crystal spec spec/m7_check_ruby_notice_spec.cr`
- 边界：参考会写回 `RUBY VERSION`，我方 `check` 只读、不改写锁文件（已声明差异）；`show` / `info` 的其他重解通知形态未取证。
- 生效：task-1（812af2b）
- 取代：无

## C-M7-1-010 frozen 模式下需要解锁 ruby 时 check 以 16 拒绝，2.7.2 不拒绝

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:421-425` 在 `Bundler.frozen_bundle?` 且需要更新锁文件时 `raise ProductionError, msg`，`msg` 由 `lockfile_changes_summary` 给出；`lib/bundler/definition.rb:890-903 unlocking_reason` 在 `@unlocking_ruby` 为真时给 `ruby`，与 `:616` 的 `change_reason[0].upcase` 合成 `Bundler is unlocking ruby, but the lockfile can't be updated because frozen mode is set`；`lib/bundler/errors.rb:35 class ProductionError < BundlerError; status_code(16); end`。`lib/bundler/definition.rb:475-492 ensure_equivalent_gemfile_and_lockfile` 只在 `Bundler.settings.locations("frozen").keys` 不含 `:env` 时才追加 `bundle config set frozen false` 提示段——这正是 env frozen 不加提示段的根因。2.7.2 的 `check` 在同样场景下 exit 0。
- 我方行为：`src/celerite/cli/commands.cr` 的 `run_check` 在算出 `lock_ruby_unlock_kind` 后、任何 stdout 之前判断：非 frozen 且 kind 非 `:none` 打印 `Resolving dependencies...`；frozen 且 kind 非 `:none` 且 4.x profile 时组装同句并 `raise ProductionError`（`src/celerite/errors.cr:260 class ProductionError < Error` status 16）；`src/celerite/cli/commands.cr:1395 private def self.frozen_from_environment? : Bool` 控制提示段。
- 判据：`bash script/differential check-frozen-ruby-nolock check-deploy-ruby-nolock show-frozen-ruby-nolock`；`crystal spec spec/m7_frozen_ruby_unlock_spec.cr`
- 边界：提示段的锁文件名我方用 `File.basename(definition.lockfile_path)`，参考用相对 `Dir.current` 的 `SharedHelpers.relative_lockfile_path`（`lib/bundler/shared_helpers.rb:223-229`），Gemfile 位于子目录时输出会不同；`.bundle/config` 里 `BUNDLE_FROZEN: "true"` 的变体未单独建夹具；参考在此路径下仍会重解并写锁，我方拒绝后不写锁。
- 生效：task-1（ebd75de）
- 取代：无

## C-M7-1-011 platform 的版本操作数取自 requirement，且判定结果始终以 0 退出

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli/platform.rb:11-15` 无锁文件时用 `Bundler.definition.ruby_version&.single_version_string`，有锁时用 `Bundler.locked_gems.ruby_version&.gsub(/p\d+\Z/, "")`；`:35-40` 先 `validate_runtime!`，成功打印 `Your current platform satisfies the Ruby version requirement.`，`rescue RubyVersionMismatch => e` 时只把 `e.message` 拼进输出，仍 exit 0。`lib/bundler/ruby_version.rb:67-69 single_version_string` = `to_s(gem_version)`，`gem_version` 是 requirement 的版本操作数。
- 我方行为：`src/celerite/ruby_version.cr:79 def single_version_string : String` 返回 `ruby #{gem_version}`，`gem_version` 按空白切 requirement 取末段；`src/celerite/cli/commands.cr:1290-1291` 成功分支打印满足行，mismatch 分支在 rescue 中打印消息，两条路径都 exit 0。
- 判据：`bash script/differential platform-gemfile-ruby platform-ruby-mismatch`；`crystal spec spec/m7_platform_spec.cr`
- 边界：bridge 不可用时我方直接降级（见 C-M7-1-016），参考无此分支；`--ruby` 的更新路径未加夹具（见 C-M7-1-017）。
- 生效：task-1（55be109）
- 取代：无

## C-M7-1-012 写锁时 RUBY VERSION 记录运行中的解释器版本，2.7.2 额外带 p<patchlevel>

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/ruby_version.rb:44-49 to_s` 只输出 `ruby <versions>`（engine 非 ruby 时再追加 `(<engine> <versions>)`）；2.7.2 的 `lib/bundler/ruby_version.rb:44-50` 多一行 `:46 output << "p#{patchlevel}" if patchlevel && patchlevel != "-1"`，故同一场景 4.0.24 写 `ruby 4.0.6`、2.7.2 写 `ruby 4.0.6p0`。`lib/bundler/definition.rb:445-452 locked_ruby_version` 决定复用锁内旧值还是取 `Bundler::RubyVersion.system`。
- 我方行为：`src/celerite/resolution.cr:2501` / `:2515` `ruby_section_value`（旧锁存在、非 `--ruby` 更新且声明与锁一致时保留锁内值，否则取 `system_ruby_string`）；`:2522` / `:2534 system_ruby_string` 输出 `ruby <运行版本>`，2.x 且 patchlevel 非空非 `-1` 时追加 `p<patchlevel>`，非 CRuby 追加 ` (<engine> <version>)`。
- 判据：`bash script/differential ruby-target-match`；`crystal spec spec/m7_ruby_runtime_enforcement_spec.cr`
- 边界：`--ruby` 更新路径只有手工探针，未加夹具（见 C-M7-1-017）；锁内已有 `RUBY VERSION` 且与 Gemfile 声明不同的变体未逐条 fixture 化。
- 生效：task-1（55be109）
- 取代：无

## C-M7-1-013 解析到平台变体时，进度行带平台后缀

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/resolver.rb:56 specs[name] = matches.sort_by {|s| [s.version, s.platform.to_s] }` 与 `lib/bundler/resolver.rb:259 ... .uniq {|spec| [spec.version.hash, spec.platform] }` 决定同版本不同平台并存；`lib/bundler/lockfile_generator.rb:48` 按 `spec.full_name` 写出，故参考进度行为 `Fetching platdemo 1.0.0 (x64-mingw-ucrt)` / `Installing platdemo 1.0.0 (x64-mingw-ucrt)`。
- 我方行为：`src/celerite/cli/commands_install.cr:82 def self.platform_suffix(platform : String?) : String`（`nil` / 空 / `"ruby"` → `""`，否则 `" (#{platform})"`），用于三处进度行（install_spec 的 Installing、pending 的 Fetching、force_install 的 Installing）。
- 判据：`bash script/differential lock-platform-variant install-platform-variant`；`crystal spec spec/m7_platform_variant_selection_spec.cr`
- 边界：只断言进度行与锁文件形态；`--local` 与平台变体组合、多平台同时锁定、`CHECKSUMS` 段的逐字比较未做。
- 生效：task-1（f3bc683）
- 取代：无

## C-M7-1-014 BUNDLE_FORCE_RUBY_PLATFORM 为真时只锁 / 装 ruby 变体

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/settings.rb:18-23` 的 BOOL_KEYS 含 `:21 force_ruby_platform`；`lib/bundler/definition.rb:662 should_add_extra_platforms?` 在强制时短路；`lib/bundler/lazy_specification.rb:221` 与 `lib/bundler/match_platform.rb:28` 强制时取 ruby 变体，已有原生锁不被复用。
- 我方行为：`src/celerite/config.cr:17` 布尔键列表含 `"force_ruby_platform"`；`src/celerite/resolution.cr:2185 private def force_ruby_platform? : Bool` = `@definition.config["force_ruby_platform"] == true`，供 `resolution_platforms`（`:2390-2391`）与 `decisions_to_specs` 判定。
- 判据：`bash script/differential install-force-ruby-platform install-force-ruby-platform-locked`；`crystal spec spec/m7_force_ruby_platform_spec.cr`
- 边界：预置锁缺 `CHECKSUMS` 段时，4.0.24 参考会整段重建三行，我方仍略去该段（既有差异，未修）；强制平台与 `clean` / `frozen` 的组合未逐项取 oracle。
- 生效：task-76（b447794）
- 取代：无

## C-M7-1-015 ABI 约束（ruby_api_version / major.minor.0）只有单元证据

- 状态：未验证
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/rubygems_ext.rb` 路径下由 RubyGems 提供 ABI 口径，`C:/Ruby40-x64/lib/ruby/4.0.0/rubygems.rb:906-907 def self.ruby_api_version` → `@ruby_api_version ||= target_rbconfig["ruby_version"].dup`；Bundler 侧消费该值，无独立过滤分支。
- 我方行为：`Celerite::InstallPaths` 由运行版本推导 `major.minor.0`；不存在对应的差分夹具。
- 判据：`crystal spec spec/m7_ruby_constraints_spec.cr`（describe `Celerite::InstallPaths` / it "derives the Ruby ABI as major.minor.0"）
- 边界：**无差分夹具**，只有纯逻辑单元例；`spec/m7_platform_spec.cr` 在 bridge 不可用时输出「未校验」而非满足，因此本项不得计为已实现。
- 生效：M7(1) 期间
- 取代：无

## C-M7-1-016 bridge 不可用时运行时校验被跳过，check 省略重解通知

- 状态：已声明差异
- 参考行为（4.0.24）：参考自身就是 Ruby 进程，`lib/bundler/definition.rb:494-523 validate_runtime!` 与 `lib/bundler/resolver.rb:34` 的 `Resolving dependencies...` 无条件执行，没有「解释器信息拿不到就静默放过」的分支。
- 我方行为：`src/celerite/cli/commands.cr:1310 validate_ruby_runtime!` 在未显式传入 bridge 时尝试 `Bridge::Client.new`，构造失败即 `return`（不校验、不算通过）；`src/celerite/cli/commands.cr:1370 lock_ruby_unlock_kind` 在同样的桥缺失下返回 `:none`，于是 `:1623` 不打印 `Resolving dependencies...`。
- 判据：`bash script/differential check-satisfied-nolock-ruby`；`crystal spec spec/m7_check_ruby_notice_spec.cr`（it "omits notice when bridge unavailable (documented best-effort fallback)"）
- 边界：降级构建（无 bridge）下本条即行为差异本身，属已知 best-effort 设计，不视为通过；桥缺失路径只有纯逻辑 spec，没有 CLI 集成证据。
- 生效：M7(1) 期间
- 取代：无

## C-M7-1-017 用 --ruby 更新锁内 RUBY VERSION 的路径未加差分夹具

- 状态：未验证
- 参考行为（4.0.24）：`lib/bundler/definition.rb:445-452 locked_ruby_version` 在「新锁或 ruby 被更新」时取 `Bundler::RubyVersion.system`，声明仍兼容则保留锁内旧值；`--ruby` 走的就是这条更新分支。
- 我方行为：`src/celerite/resolution.cr:2501` / `:2515 ruby_section_value` 已按同一条件分流（旧锁存在、非 `--ruby` 更新且声明与锁一致时保留锁内值），但该分支只做过手工探针。
- 判据：`bash script/differential update-ruby`；`crystal spec spec/m7_ruby_runtime_enforcement_spec.cr`
- 边界：`update-ruby` 夹具未逐字断言 `RUBY VERSION` 的更新前后形态；本节证据来自手工探针，故状态记未验证，不得升级为已实现。
- 生效：M7(1) 期间
- 取代：无
