# M7(1) Ruby/RubyGems/Gemfile 目标与 ABI 约束过滤

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 154 -->

（进展 032a531+本迭代：新增 `RubyVersion`/`RubyRuntime`、`RubyVersionMismatch` exit 18、bridge `ruby_environment.patchlevel` 与结构化 Gemfile `ruby` 选项、运行时校验接线与 `platform` mismatch 文案语义、gem metadata 按 `RUBY_VERSION` 过滤（patchlevel 只在 Gemfile 目标校验参与，与 Bundler `matches_current_ruby?` 一致）、`ruby_compatible?`/lock reuse/ruby_update patchlevel 处理；`spec/ruby_version_spec.cr`（10）+`spec/m7_ruby_runtime_spec.cr`（9，含 version/engine/engine_version/patchlevel mismatch 文案与 exit 18、matching version/patchlevel 与 matching engine/engine_version 正例、bridge 结构化 Gemfile `patchlevel: "1"`/`engine: "jruby"`/`engine_version` 传递）+`spec/m7_platform_spec.cr`（2，bridge 不可用输出“未校验”而非满足）+`spec/m7_ruby_constraints_spec.cr`（10）+`spec/m7_resolver_ruby_constraints_spec.cr`（8，含 Ruby/RubyGems-only 排除的 SolveFailure exit 6 与纯无匹配 exit 7）通过，本轮 M7 spec 合计 111 examples/0 failures（含安装后发现 20、fund 3、gem 4、console 1）；已新增 `fixtures/differential/ruby-version-mismatch`（check）、`platform-ruby-mismatch`（platform）、`list-multi-group`（list 多组）、`no-matching-version`（无可用版本，exit 7 与参考一致）与 `platform-variant-fail`（平台变体，exit 7 与参考一致）与 `ruby-engine-mismatch`（engine 变体，exit 18）、`ruby-engine-version-mismatch`（engine_version 变体，exit 18）、`ruby-patchlevel-mismatch`（patchlevel 变体，exit 18）、`ruby-metadata-fail`（Ruby 元数据 SolveFailure，exit 6 与参考一致）、`rubygems-metadata-fail`（RubyGems 元数据 SolveFailure，exit 6 与参考一致）、`rubygems-metadata-match`（`required_rubygems_version = ">= 0"`，exit 0）/`rubygems-metadata-boundary-match`（`>= 4.0.16`，边界等于运行中 RubyGems 4.0.16，exit 0）与 `ruby-metadata-match`（`required_ruby_version = ">= 1.0"`，exit 0）/`ruby-metadata-boundary-match`（`>= 4.0.6`，边界等于运行中 Ruby 4.0.6，exit 0）正例（4.0.24/2.7.2 PASS）与 `install-check`（install 后 check，exit 0），以及 `ruby-target-match`/`ruby-patchlevel-match`/`ruby-engine-match`（Gemfile 目标 Ruby 正例，install+check，exit 0）与 `check-missing-ruby-nolock`/`list-missing-ruby-nolock`（Gemfile 声明 `ruby` 但 lock 无 `RUBY VERSION` 且依赖未安装时 `check`/`list` 的 `Resolving dependencies...` 通知与缺失报错，exit 1），并用本地 OpenSSL shim 实际运行通过（定向 differential 30 passed/0 skipped，含 PATH 源 `check-path`/`list-path`/`fund-path` 与 GIT 源 `git-installed-discovery`；2.7.2 定向子集 30/30 已跑；全量 4.0.24 为 101 passed / 14 failed / 0 skipped，14 项分类见 `docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`，均不在 M7 路径）。**已修复**：`ruby-metadata-fail`（PATH gem `required_ruby_version >= 99.0`）现与参考一致——仅因 Ruby/RubyGems 元数据排除时报告 SolveFailure（exit 6 + 同形解释），纯无匹配版本仍报 GemNotFound（exit 7）；`deferred-4.0.24` 已移除。**未达验收**：version/patchlevel/engine/engine_version 正反例与安装复核已覆盖，Gemfile 有 `ruby` 但 lock 无 `RUBY VERSION` 且依赖未安装时 `check`/`list` 通知已钉住；仍缺 ABI/平台变体正例、该场景依赖已满足/其他命令/其他形态的行为取证与 fixture、`show`/`info` 其他重解通知场景；bridge 不可用时校验 best-effort 跳过，**不得视为通过**；依赖 bridge 环境时需复核。**本机 codegen/CLI 集成 spec/differential 受阻**：Crystal 1.22.1 绑定 OpenSSL 1.1 `EVP_MD_size`，MSYS2 ucrt64 OpenSSL 3.6.5 仅导出 `EVP_MD_get_size`（`nm` 验证），stock 链接失败；本轮已用**仓库外** C shim + `--link-flags` 本地重建 `bin/celerite.exe`（EXIT 0，`--version` 0.1.0，不入库），据此跑通 CLI spec（24/0）与 differential（定向 30 passed/0 skipped、2.7.2 定向 30/30、全量 101/14/0

（2026-11-11 基线，115 fixtures）；2026-11-12 全量刷新（HEAD=a8753b6 已推送，shim-built bin，122 fixtures）：114 passed/8 failed/0 skipped、wrapper exit 1（7× racc make 不可用 + 1× exec-loader loader/.bat 内容差异）；当前失败集 ⊆ 先前 14 失败名单，按名字无比对新增回归；2.7.2 全量未重跑（未验证，复现 BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential）；复现命令与 shim 说明见 ``docs/compat-evidence/2026-11-11.md`` 的 Local verification run 节。修复需 OpenSSL 1.1 工具链或升级 Crystal 绑定）。 M7(1) 矩阵补强

（2026-11-12，HEAD=7c446d9 + 同轮 worktree 未提交改动，shim-built bin）：新增 6 个 differential fixtures（ruby-metadata-boundary-fail `>= 4.0.7`、rubygems-metadata-boundary-fail `>= 4.0.17`、ruby-metadata-exact-match `= 4.0.6`、rubygems-metadata-pessimistic-match `~> 4.0`、ruby-engine-patchlevel-match（engine/engine_version/patchlevel 全匹配 install+check）、multi-platform-install（lock --add-platform x86_64-linux + install + check；首跑 racc ext 落 Class A make 阻塞，移除 racc 保留 json_pure+thor 后复跑 PASS））+ spec 3 例 RubyRuntime.diff 优先级 + 新 spec/m7_platform_match_spec.cr 4 例；spec 子集 46 examples 0 failures 0 errors 0 pending EXIT 0；4.0.24 定向 6/6 PASS（含修正后单跑 1 passed/0 failed）、2.7.2 定向 6/6 与扩展 36 例定向集 36/36 PASS（DIFF_272_36_EXIT=0）；4.0.24 全量重跑 128 fixtures 120 passed/8 failed/0 skipped、wrapper exit 1（log C:\temp\celerite-diff-full-4.0.24-7c446d9.log，汇总行在 log 第 301 行），8 个 FAIL 名字与 03:18 轮完全一致（⊆ 先前 14 名单，按名字无比对新增回归；7× racc make 不可用 + 1× exec-loader loader/.bat），6 个新 fixture 全 PASS，delta +6 passed / ±0 failed / +6 fixtures；2.7.2 全量仍未重跑（未验证，复现 BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential）；逐例证据见 docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md 与 `docs/compat-evidence/2026-11-12.md`。 B:1 exec-loader 修复

（2026-11-12，本子项，shim 本地 bin，`src/celerite/installer.cr` PATH/GIT 安装改为 RubyGems-style wrapper + CRLF `.bat`，`src/celerite/cli/commands_install.cr` `ruby_shebang?` 识别 `#! ruby` 以兼容 `BUNDLE_DISABLE_EXEC_LOAD`/exec 路径）：修复前 `exec-loader` 4.0.24/2.7.2 均 0/1/0 EXIT 1（installed tree `ruby/4.0.0/bin/loader`、`loader.bat` 内容差异，logs `C:\temp\celerite-diff-execloader-4024-before.log`、`C:\temp\celerite-diff-execloader-272-before.log`）；修复后 4.0.24 `exec-loader` 1/0/0 EXIT 0、2.7.2 1/0/0 EXIT 0，`exec-loader-disabled` 4.0.24/2.7.2 各 1/0/0 EXIT 0（2.7.2 成对 2/0/0；4.0.24 成对+原 8 FAIL 子集 2 passed,7 failed,0 skipped EXIT 1，7 FAIL 全为 class A racc/make 环境阻塞）。4.0.24 全量重跑 **130 fixtures, 123 passed, 7 failed, 0 skipped, wrapper exit 1**（log `C:\temp\celerite-diff-full-4.0.24-execloader-final.log`，mtime 2026-11-12 08:02:07，299 行；7 FAIL 仅 `add-group`/`add-optimistic`/`add-remove`/`add-version`/`cache-all-platforms`/`native-ext-target`/`native-ext`，`exec-loader` 与 `exec-loader-disabled` PASS；较 128:120/8/0 按实测计数 +3/-1/+2，按名字无新增失败）。`crystal tool format --check src spec` EXIT 0；`crystal build --no-codegen src/cli.cr` EXIT 0（2 known deprecation warnings）；`git diff --check` EXIT 0；M7 子集 70 examples 0 failures 0 errors 0 pending EXIT 0。2.7.2 全量仍未重跑（未验证，复现 `BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`）；stock EVP_MD_size 阻塞、shim 仅本地持续记录。 2026-11-15（M7(1) 平台变体正例）：新增 `fixtures/gem-index-platform/`（`platdemo` 的 ruby 与 `x64-mingw-ucrt` 双变体）与 `lock-platform-variant`/`install-platform-variant` 差分夹具，双 profile PASS；进度行补 ` (...) ` 平台后缀（`Commands.platform_suffix`），复选框保持 `[ ]`。同轮附带修复 compact-index `info` 行的无空格 requirements 形态（`1.0.0|checksum:…`）：修复前对同一 index 参考 `lock` EXIT 0 而我方 EXIT 20 `bad compact index data …: Malformed version number string`，修复后 `src/celerite/compact_index/cache.cr:498-511` 在版本段按 `|` 切开并把 `|…` 交回 requirements 流程，空格形态行为不变；新增 `spec/m7_compact_info_space_spec.cr`（2 例）与负对照（条件改 `if false` → 2 errors），夹具 info 现混用两种写法同时覆盖；全量 `381 examples, 0 failures, 4 errors`（4 = 既有 msys `0xC0000022`）。2026-11-15（frozen ruby 解锁拒绝）：`check` 在 frozen 且 Gemfile ruby 与锁不一致时按参考 exit 16（`ProductionError`，两行消息；`BUNDLE_DEPLOYMENT`/配置文件 frozen 另加 4 段提示，env `BUNDLE_FROZEN` 仅两行），`list` 保持 exit 0 且不打印 `Resolving dependencies...`，非 frozen 通知与 profile 无关（2.7.2 同样打印），2.7.2 frozen 无通知；`show`/`info` 实测参考不检查（保持原行为）；新增差分 `check-frozen-ruby-nolock`/`show-frozen-ruby-nolock`/`check-deploy-ruby-nolock`（装具支持 `frozen`/`deploy` 标记）与 `spec/m7_frozen_ruby_unlock_spec.cr` 10 例，双 profile 4/4 PASS。复选框保持 `[ ]`。 

**2026-11-16

（本迭代，M7(1) 运行时校验）：`validate_ruby_runtime!` 去掉 `bridge_available?` 门控（普通 CLI 下 check/show/fund/update/outdated/pristine/install/platform/binstubs 均按参考 exit 18），`platform` 改为参考 rescue 语义（mismatch 打印消息、exit 0；无锁时按 Gemfile 声明取 `single_version_string` = `ruby 3.1`），`binstubs` 校验前移到用法检查之前，锁文件 `RUBY VERSION` 改由 `RubyVersion.system` 序列化（4.0.24 `ruby 4.0.6`、2.7.2 `ruby 4.0.6p0`；声明仍兼容时保留锁内旧值）。证据：`spec/m7_ruby_runtime_enforcement_spec.cr`（4 例）+ 重写的 `spec/m7_platform_spec.cr` 联跑 6/0，全量 496/0/4；新差分 `ruby-requirement-mismatch`（exit 18）与 `platform-gemfile-ruby`（exit 0）双 profile PASS，回归集 7/0；负对照插入 `return` 后 `ruby-requirement-mismatch` FAIL（reference=18 celerite=20）再复原复绿。**未修**：无 lockfile 时 `check` 仍 exit 20，参考先解析写锁后 exit 0（新发现缺口，待下轮）。；2026-11-16 补：无 lockfile 时 `check` 改为先解析（打印 `Fetching source index from <remote>/` 与 `Resolving dependencies...`），缺失时 exit 1 三行 stderr 且不写锁，满足且非 `--dry-run` 时写锁；同时给 `op_bundler_cache_file` 增加 `Gem.default_dir/cache/bundler-<version>.gem` 回退，隔离 `GEM_PATH` 下 `CHECKSUMS` 的 bundler 行与参考一致。证据：新 spec `spec/m7_check_no_lockfile_spec.cr` 3 例、差分 `check-no-lockfile-missing`/`check-no-lockfile-installed` 双 profile PASS、2.7.2 回归集 6/0；全量 499 examples, 0 failures, 4 errors（4 为既有 msys Low-IL）；负对照硬置 `resolved_from_gemfile = false` 后两夹具 0 passed/2 failed（exit 20 + 缺锁文件）。 

**2026-11-19（task-21 补记）：安装期 `required_ruby_version`/`required_rubygems_version` 复核已落地（`src/celerite/installer.cr:65-90` 的 `ensure_specs_are_compatible!`；锁定不兼容时经 `build_locked_index` 排除后重解析，输出参考 exit 6 求解文案）。剩余＝复核路径的差分夹具 + 多 ABI/多 Ruby 矩阵（本机仅 Ruby 4.0.6）。复选框保持 `[ ]`。** 

**2026-11-19（task-38 补记）：锁内 ruby/rubygems 约束已补差分证据——rc_gem/rg_gem 锁 1.0.0 时参考与 celerite 均重解到 0.9.0（`Fetching ... (was 1.0.0)`）；only_rg 锁 1.0.0 仍为 SolveFailure exit 6（RubyGems >= 99.0）。参考无可触发的 install 期 `ensure_specs_are_compatible!` 路径，故本轮无产品改动；剩余＝多 ABI/多 Ruby 宿主矩阵（本机仅 4.0.6）与全量差分未重跑。复选框保持 `[ ]`。** 

**2026-11-19（task-39 漂移校正）：上述“剩余＝复核路径的差分夹具”已过期——`install-locked-ruby-incompatible` 早已存在且双 profile PASS，task-38 又补 3 个 ruby/rubygems 约束夹具；剩余只余多 ABI/多 Ruby 矩阵与全量 spec/全量差分未重跑。复选框保持 `[ ]`。** 

**2026-11-21（task-75）：install/clean/exec/outdated 统一走结构化 RubyVersion，patchlevel 不再丢失；新增 install-patchlevel-mismatch 夹具。复选框保持 `[ ]`。** 

**2026-11-21（task-76）：`BUNDLE_FORCE_RUBY_PLATFORM` 现按参考只锁通用平台、原生锁会重解析并保留平台行；新增 install-force-ruby-platform 夹具（2.7.2 locked 变体 deferred）。复选框保持 `[ ]`。** 

**2026-11-21（task-77）：`bundle cache` 现读 `cache_path` 设置（env 与 `.bundle/config`），`--cache-path` 优先，输出打印设置原值；`app_config_env` spec 的期望串按 task-56 的正斜杠形态归一（该 spec 在基线即红）。复选框保持 `[ ]`。** 

**2026-11-22（task-119）：frozen 锁校验对齐参考三处——锁 `specs:` 空但 `DEPENDENCIES` 有条目（参考 `definition.rb:1068-1069` 的 `@missing_lockfile_dep`，修前我方 `check` exit 1 / `install` exit 0 静默重解析）、锁里多一行无人引用的 spec 行（参考 `definition.rb:973-1015` 只校验已锁定 spec 的依赖边，修前我方 `check` 误报缺 thor 且 `install` 真装 thor）、锁版本不满足 Gemfile 需求（参考 `definition.rb:1075-1078` 的 `matches_spec?`，修前我方 `install` exit 0 装下不满足约束的 2.6.0）；修后 A/C 两侧均 exit 16 且 stderr 逐字一致，B `check` 两侧 exit 0 且不再多装 thor。新增差分夹具 `check-frozen-missing-locked-spec`/`check-frozen-extra-locked-spec`/`check-frozen-locked-version-mismatch`（4.0.24 三条 PASS，2.7.2 标 deferred）与 `spec/m7_frozen_lock_validation_spec.cr`（5 例 0 失败）；反假绿：21fb01f 旧二进制跑三个新夹具 0 passed / 3 failed；4.0.24 全部 `*frozen*`/`*check*` 回归 47 passed / 0 failed。非 frozen 路径按任务书未改（A/B 的 `check` 在非 frozen 下仍与参考不同，见 `docs/compat-evidence/2026-11-22.md` task-119 节）。复选框保持 `[ ]`。**
## 2026-11-23：M7-1 行的闭合判据审计（task-182）

本节为首辅裁断 `docs/roadmap.md:141` 的 M7-1 行提供依据，**不动复选框**。状态以 `docs/compat-claims/M7-1-ruby-constraints.md` 的 17 条账本为准（本轮实测：已实现 14、未验证 2、已声明差异 1）；claims 正文内的源码行号已整体漂移，下表行号为本轮实测现值。本节未执行 `crystal spec` 或 `bash script/differential`。

### 子项拆解与逐项状态

| # | 子项 | 证据（文件:行号 / claim / 夹具） | 状态 |
|---|---|---|---|
| 1 | 当前 Ruby 的约束过滤（gem 元数据 `required_ruby_version`） | `src/celerite/resolver/source.cr:312-316`（`:313`）；C-M7-1-002；`ruby-metadata-fail`、`ruby-metadata-remote-fail`、`ruby-metadata-boundary-fail`、`ruby-metadata-exact-match` | 已实现 |
| 2 | RubyGems 的约束过滤（`required_rubygems_version`） | `src/celerite/resolver/source.cr:314`；C-M7-1-003；`rubygems-metadata-fail`、`rubygems-metadata-remote-fail`、`rubygems-metadata-boundary-fail`、`rubygems-metadata-pessimistic-match` | 已实现 |
| 3 | Gemfile 目标 Ruby 的运行时校验 | `src/celerite/cli/commands.cr:1335` `validate_ruby_runtime!`；`src/celerite/ruby_runtime.cr:17`；`src/celerite/errors.cr:522` `RubyVersionMismatch`（exit 18）；C-M7-1-001；`ruby-requirement-mismatch`、`ruby-target-match`、`check-satisfied-nolock-ruby` | 已实现 |
| 4 | engine / engine_version | 同 #3 校验链；C-M7-1-001；`ruby-engine-match`、`ruby-engine-mismatch`、`ruby-engine-version-mismatch`、`ruby-engine-patchlevel-match`；`spec/m7_ruby_runtime_spec.cr` | 已实现 |
| 5 | patchlevel | `src/celerite/ruby_runtime.cr:17`；C-M7-1-006、C-M7-1-012；`ruby-patchlevel-match`、`ruby-patchlevel-mismatch`、`install-patchlevel-mismatch`；`spec/m7_ruby_patchlevel_spec.cr` | 已实现 |
| 6 | ABI 约束过滤 | `src/celerite/resolution.cr:164-172` `InstallPaths.ruby_abi(_for)`；C-M7-1-015；仅 `spec/m7_ruby_constraints_spec.cr` 的 `Celerite::InstallPaths` 纯逻辑例 | 未验证 |
| 7 | `ResolutionSource#ruby_requirement_satisfied?` 完整实现 | `src/celerite/resolver/source.cr:312-316`：`:313` 比 `required_ruby_version`，`:314` 比 `required_rubygems_version`，二者同时满足才 true；调用点 `:228`、`:455`；C-M7-1-002/003 | 已实现 |
| 8 | `--ruby` 更新锁内 `RUBY VERSION` | C-M7-1-017；`fixtures/differential/update-ruby` 只含 `command`/`Gemfile`/`Gemfile.lock`，`grep RUBY VERSION` 无命中；claims 自述仅手工探针 | 未验证 |

### oracle

- 参考侧：4.0.24 与 2.7.2 的 `Bundler::Definition#validate_runtime!`、`Bundler::RubyVersion`、RubyGems `Gem::Specification#required_ruby_version` / `required_rubygems_version` 与 ABI 口径；逐条结论已固化在 C-M7-1-001…017。
- 可重跑判据：上表夹具对应的 `bash script/differential <fixture>`，以及 `crystal spec spec/m7_ruby_constraints_spec.cr spec/m7_ruby_runtime_spec.cr spec/m7_ruby_patchlevel_spec.cr spec/m7_ruby_runtime_enforcement_spec.cr spec/m7_resolver_ruby_constraints_spec.cr`。

### 参考锚点

- `lib/bundler/definition.rb:494-523` `validate_runtime!`、`lib/bundler/resolver.rb:34`（C-M7-1-016 正文所载）。
- `lib/bundler/definition.rb:445-452` `locked_ruby_version`（C-M7-1-017 正文所载）。
- `rubygems.rb:906-907` `ruby_api_version`（C-M7-1-015 正文所载）。
- 以上参考行号引自 claims 正文，本轮未打开参考检出复核。

### 实现位置

- `src/celerite/resolver/source.cr:312-316`（过滤谓词）、`:321` / `:325`（运行中 Ruby/RubyGems 版本）。
- `src/celerite/ruby_runtime.cr:17`；`src/celerite/errors.cr:522`。
- `src/celerite/cli/commands.cr:1335`（`validate_ruby_runtime!`）。
- `src/celerite/resolution.cr:164-172`（ABI 推导，仅被安装路径/extensions 目录消费，未参与候选过滤）。

### 证据

- 夹具与 spec 文件名均经本轮 `Test-Path`/列目录核实存在；claims 记为已跑 PASS，本轮未重跑。
- 首辅交底的 `38021fc` 全量 spec（1058 examples / 0 failures / 0 errors / 17 pending）只覆盖 spec，不覆盖差分；`git diff --stat 38021fc..HEAD` 只动 docs 5 文件，代码态可折算。
- 全量差分最近一次记录仍是本文件 2026-11-12 行：130 fixtures、123 passed、7 failed（失败均为 racc/make 环境类），此后只有定向轮次，**未全量重跑**。

### 已声明差异

- C-M7-1-016：无 bridge 的降级构建跳过运行时校验、`check` 省略重解通知；属有意 best-effort，不计为通过。
- ABI 一项另有一层口径问题：参考 Bundler 侧未发现独立 ABI 过滤分支，ABI 只进入安装路径；M7-1 行文把 ABI 写成「约束过滤」，与参考行为不完全对齐。

### 裁断建议

**不可勾，还缺 2 项**：

1. C-M7-1-015（ABI）：只有纯逻辑单元例，无差分夹具。本机可做单 ABI（4.0.0 路径）差分，或把本项改写成「ABI 仅参与安装路径」并标已声明差异；多 ABI 矩阵本机不可做（无第二 Ruby 宿主）。
2. C-M7-1-017（`--ruby` 更新锁内 `RUBY VERSION`）：现有 `update-ruby` 夹具未断言该行。本机可做：扩展夹具断言更新前后 `RUBY VERSION`，或新增专用夹具。
