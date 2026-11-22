# M7(3) 占位路径（fund / gem 模板 / console / env）

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 156 -->

（进展，本迭代补证据 2026-11-11/2026-11-12，HEAD=3c4f55d）：`fund` 读取已安装 specifications/`.gem` metadata 与 PATH/GIT source gemspec `funding_uri`（`read_source_funding_uri` 优先），`spec/m7_fund_spec.cr` 3/0；`fixtures/differential/fund-path` 用 shim-built binary 复核 4.0.24 **PASS exit 0**、2.7.2 **PASS exit 0**。`gem` 最小可用 scaffold（`require_relative`+`Module::VERSION`、README/LICENSE/Gemfile），不完全支持选项显式 warning + “Generating a minimal scaffold only…” 但仍生成；`spec/m7_gem_spec.cr` 4/0，CLI：无参数 stderr `Please provide a gem name` exit 1，`gem my_sample --test` exit 0 且仅最小 scaffold。`console` 已由 bridge 引导脚本接管

（2026-11-19，见下方 M7(3) 注记与 `docs/compat-evidence/2026-11-19.md`「`console` 的进程内引导与组 require 语义」节）：控制台缺失时按参考文案 `irb is not available` 并 exit 1，旧实现的 exit 127 与自有文案已移除（`spec/m7_console_spec.cr` 8/0）。`env`/`issue` 使用 `Bundler <profile> (Celerite <version>, compatibility profile)` + `## Bundler Build Metadata`；修复 `build_timestamp` 为 `git log -1 --format=%cs HEAD` 并校验 `YYYY-MM-DD` 否则 `unknown`；CLI 证据：repo-cwd `env` exit 0、`Timestamp 2026-11-11`/`Git SHA 50c005a`；非 git cwd `env` exit 0、`Timestamp unknown`/`Git SHA 50c005a`；无 Gemfile `env` exit 10；`issue`（缺 gem）exit 1 且含 doctor/missing。M7(3) specs **8/0 EXIT 0**。**M7(3) 部分修复

（2026-11-12，shim 本地 bin）**：新增 differential fixture `fixtures/differential/env-report`（`env`，repo/Gemfile cwd 正常输出场景，exit 0）并与既有 `issue-no-gemfile`（exit 10）/`issue-missing-gems`（exit 1）组成 env/issue 稳定场景集；定向 differential **4.0.24 3/0/0 EXIT 0**、**2.7.2 3/0/0 EXIT 0**（命令 `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp [BUNDLER_REF_VERSION=2.7.2] bash script/differential env-report issue-no-gemfile issue-missing-gems`；harness N5 归一化剥离 `## Environment` 机体后比对）。`console`/`gem` 边界证据（本轮实测）：IRB 缺失 PATH 下 `console` stderr 含 `bundle console requires IRB (`irb`) in PATH...` 且 EXIT 127（历史记录，已被 2026-11-19 的 bridge 引导脚本取代：现按参考文案 `irb is not available` + exit 1，并有 `console-group` 差分夹具双 profile PASS，不再需要「同受限 PATH 不可比对」的旁证）；`gem` 生成最小 scaffold（6 文件）+ 对 `--test=rspec` 警告 `bundle gem options not fully supported by Celerite... Generating a minimal scaffold only...`（EXIT 0），参考 bundler 4.0.24 `bundle gem` 为交互式完整模板（14 文件、提示 test/CI/license/coc/changelog/linter），模板/选项矩阵差异大，完整 differential 未覆盖。未达验收：`env`/`issue` 超出上述稳定场景的完整输出未 fixture 化、satisfied `issue`（含 lock）差分未实跑（先前探针显示 celerite 侧 `install`/`issue` 路径未与 harness 预期一致，**未验证**，复现：在含 file-index Gemfile+已生成 lock 的沙箱分别跑 `CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential` 对应 issue 场景）；`console` IRB 可用/交互路径差分未覆盖；`gem` 完整模板/选项矩阵差分未覆盖；stock OpenSSL `EVP_MD_size` 阻塞，CLI 证据为 shim 本地 binary（shim 仅本地、不入库）。2026-11-15（env 对齐）：`env` 输出已与参考逐字对齐（Bundler 行去 `(Celerite … compatibility profile)` 后缀、补 `## Bundler settings` 段、缺锁文件打印 `<No <路径> found>`、去掉尾空行），`fixtures/differential/env-report` 在真比较下 `PASS (exit=0)`（此前为空比较假 PASS）；仍未对齐 `bundle #!`（原生二进制无 shebang，归一化为 `{BUNDLE_SHEBANG}`）（`## Gemspecs` 与 `OpenSSL` 块已在段 C 实现），详见 `docs/compat-evidence/2026-11-15.md` M7(3) 节。复选框保持 `[ ]`。2026-11-15（env 段 C）：OpenSSL 块与 `## Gemspecs` 已按参考实现（`env.rb:106-112`、`:51-58`），新增 `env-gemspec` 差分夹具双 profile PASS，详见 `docs/compat-evidence/2026-11-15.md` M7(3) 节。2026-11-15（console）：`bundle console` 改为参考语义（`BUNDLE_CONSOLE` 选择、缺失时回退消息 / `irb is not available`、多余组参数 exit 15），新增 `spec/m7_console_spec.cr` 5 例；执行仍为外部控制台 + `-rbundler/setup`，`GROUP` 的 `Bundler.require` 未实现，详见 `docs/compat-evidence/2026-11-15.md`。2026-11-15（gem 模板）：`bundle gem` 已按 4.0.24 模板逐字节实现（10 文件 + 15 行 stdout + `git init`/`git add`），新增 `spec/m7_gem_template_spec.cr`（3 例）与差分夹具 `gem-default`（4.0.24 PASS、2.7.2 deferred），非默认选项 fast-fail（已声明偏差），详见 `docs/compat-evidence/2026-11-15.md`。2026-11-15（fund --group）：`bundle fund --group` 已对齐参考语义（标量选项、重复后者覆盖、逗号不切分、默认集合 = 声明组 − `without` + `with`；缺 PATH 源按参考 `PathError` 输出 `The path `<abs>`. does not exist.` 并按终端宽度折行、exit 13；funding 只读已安装 specifications，删除 `cache/*.gem` 兜底），新增 `spec/m7_fund_group_spec.cr`（9 例）与差分夹具 `fund-groups`/`fund-group-development`/`fund-groups-without`（4.0.24 与 2.7.2 各 3/0/0）。**已声明偏差**：`BUNDLE_WITHOUT` 命中 `--group` 时参考崩溃（`fund.rb:24` `NoMethodError`），本实现打印 None 并 exit 0，不复刻崩溃。仍未验证：多组并集、真实 GEM 源 funding、2.7.2 的崩溃偏差；`console`（exec 与进程内差异）与 `env`（多 gemspec 顺序）使 M7(3) 复选框保持 `[ ]`，详见 `docs/compat-evidence/2026-11-16.md`。。

**2026-11-16

（本迭代，M7(3) env/version 对齐）：`bundle env` 的 `Gem Path` 改按平台分隔符并用 `Gem.path`（用户设 GEM_PATH 时追加默认目录）、`Config Dir` 取系统配置目录正斜杠形态、`Bin Dir` 取 `Gem.bindir`、`## Bundler Build Metadata` 改用发布常量（2.7.2=2025-09-09/b463ced1459、4.0.24=2026-11-05/3b396e4）；`bundle version` 输出 `4.0.24 (2026-11-05 commit 3b396e4)`（2.x 带 `Bundler version ` 前缀），`-v`/`--version` 只打版本，多余参数 exit 15；桥新增 `bridge_activate_bundler` 修正自定义 `GEM_PATH` 下 `env` exit 1。证据：spec `m7_env_output_spec`+`m7_version_spec` 13/0、差分 `version-plain`/`version-extra` 4.0.24 4 passed 与 2.7.2 3 passed、负对照 1 FAIL 后复原、全量 486/0/4。未显式设 `GEM_HOME` 时本机 `Gem Home`/`Bin Dir` 仍因 RubyGems 低完整性回退 user dir 而不同（环境，已声明）；全局 `--verbose` 回显与 `version extra` 的 CRLF 属已声明差异。复选框保持 [ ]。** 2026-11-16（fund 的无锁路径）：fund 与 clean/binstubs 同改走 materialize_lockfile(local_only: true)，无锁时不再要求 Gemfile.lock，缺失 gem 报 `Could not find gem '<name> (<req>)' in locally installed gems.`，与参考逐字一致；差分 fund-no-lockfile 双 profile PASS，spec 4/0。 

**2026-11-16（gem 的否定开关）：`bundle gem` 接受 Thor 自动生成的 `--no-<bool>`（`--no-git` 时 9 个文件、无 `.gitignore`、gemspec 保留 TODO 作者与 `%w[bin/ Gemfile]` 清单），`--rubocop`/`--no-rubocop` 按 cli.rb:607-608 报 removed 文案 exit 15；git 初始化行补前置空行。A/B 两场景 10 个文件逐字节相同，spec 7/0，差分 gem-default/gem-no-git 4.0.24 PASS、2.7.2 deferred。 

**2026-11-17 二十一补（`install --standalone`）**：`--standalone` 且无 `path` 时按 `cli/install.rb` L112-114 用 `set_command_option :path, "bundle"`（仅本次命令、不落盘），安装与 `./bundle/bundler/setup.rb` 都落在 `./bundle`；setup.rb 按 `definition.specs_for(groups)` 生成（`--standalone=development` 只含该组闭包、跳过 bundler），Windows 按文本模式写 CRLF，groups 非空时补一行 `Fetching source index from …`。A/B 三场景 setup.rb 逐字节相同（1126/1016 字节、CR=38/37），spec 3/0，两次负对照各 1 FAIL 后复原，全量 spec 611/0/4。 

**2026-11-17 二十二补（403 的抛出点）**：`compact_index/cache.cr` 的 403 改报 `AuthenticationForbiddenError`（完整源 URI，含尾斜杠）并在 `resolution.cr` 的 `index_specs_from_remote` 中先按 legacy 回退打印 `Fetching source index from …` 与空行再抛出，`downloader.cr` 的 403 改报 host 形态；顺手订正 `errors.cr` 里「403 报成 AuthenticationRequired」的错误断言。A/B 全 403 场景 stdout/stderr 逐字相同（exit 17），spec `m7_forbidden_spec` 2/0 与 `m7_authentication_errors_spec` 6/0，负对照 1 FAIL 后复原，全量 spec 613/0/4。gem 下载 403 参考走 RubyGems 重试 + 回溯 exit 5，未复刻（已声明）。 

**2026-11-18 二十五补（`help`/`--help` 渲染 vendored manpage）**：参考 `bundler/cli.rb:155-185 #help` 在没有 `man` 时直接 `puts File.read(<man>/<page>.1.ronn)`，Thor `HELP_MAPPINGS`（`base.rb:17` = `-h -? --help -D`）把 dash 首参转成 help，无页面的隐藏命令落 `super`（`thor.rb:252-280 command_help`）。实现：新 `src/celerite/manpages.cr`（页名映射 + `CELERITE_MAN_DIR`/可执行文件旁/源码树三路查找 + Windows CRLF 折行），`assets/man/4.0.24`（31 页 121444 字节）与 `assets/man/2.7.2`（33 页 121322 字节）入库（两版 20 页不同，不可共用）；`Commands.help` 重写为「未知开关 → 多余位置参数两行 15 → 别名归一 → 插件委派 → 页面渲染 → Thor 兜底 → 未知命令 + `Suggestions` 建议」，`dispatch` 的 dash 映射补 `-?`/`-D`，`<cmd> --help` 带 `stderr` 转 `help`，`reference_commands` 在 2.x 剔除 `tree`/`install_or_cli_help`（2.7.2 命令表 32 个 vs 4.0.24 33 个）。A/B 22 例双 profile 全 SAME（`help install` 4.0.24 13090 / 2.7.2 16260 字节，`help tree` 4.0.24 Thor 兜底 359 字节而 2.7.2 exit 15，`help viz`/`inject` 2.7.2 走各自页面）；6 个新差分夹具双 profile 各 6/0；`spec/m7_help_manpage_spec.cr` 12/0，全量 spec 646/0/4（4 为既有 msys 环境族）。未复刻并已声明：Thor 前缀命令解析（`instal`/`co`）、`[REMOVED]`（`viz`/`inject` exit 9）、无参 `bundle` 的 default_command 警告块、`-t`/`--tree`。

**2026-11-18 二十六补（`cli_help` / 无参 `bundle`）**：`PRINTABLE_COMMANDS`（4.0.24 的 30 条 `printable_commands(true)`，2.x 剔除 `tree`/`clean`）+ `CLI_HELP_PRIMARY` + `render_command_table`（复刻 Thor `TablePrinter`：首列 `maxima+2`、末列原样、超长 `chars[0, truncate-3-indent] + "..."`、`indent` 前缀）实现 `cli_help`（4.0.24 = 2718 字符 / 44 行、2.7.2 = 2560 字符 / 42 行，双 profile 逐字 SAME，`Utilities:` 分别 24 / 22 行）；`dispatch` 增「`raw_args` 为空，或首 token 以 `-` 开头且不在 `DASH_MAPPED_COMMANDS`（`--help -h -? -D -t --tree --version -v`）→ 落回 `default_cli_command`」路径：4.0.24 先打 5 行 `DEFAULT_CLI_COMMAND_NOTICE` 后走 `install`，2.7.2 无警告块（`cli.rb:110` 用 `default_task` 固定默认命令），前置类开关成为默认命令的开关、其余 token 成为位置参数 → 15（`--no-color install` 双 profile 均 `ERROR: "bundle install" was called with arguments ["install"]`）；`config_store` 在写盘前按 4.x 校验 `default_cli_command`（非法值 15 + 三行 `must be one of: install, cli_help`，2.7.2 静默 0）；4.x 的 `install` 遇 `GemfileNotFound` 先打 `cli_help` 表再 re-raise（exit 10 / out 3218），2.7.2 直接抛（out 0）；删除 `CLI::USAGE`（裸 `bundle` 不再打印自有 usage 屏）。A/B 23 例 × 2 profile 仅剩 `--verbose` 调试图层 1 处差异；新差分夹具 6 个双 profile 各 6/0，回归集 14 夹具 14/0、删 `USAGE` 后复跑 6/0；`spec/m7_cli_help_spec.cr` 10/0（含 `with_cli_help_home` 隔离 `~/.bundle/config` 与 `ensure ENV.delete("CELERITE_VERBOSE")` 防跨例污染）；全量 spec 656/0/4（4 为既有 msys 环境族）。 

**2026-11-19（task-27 补记）：`gem` 支持参考 4.0.24 的 `--help`（逐字 6060 字节）、`--test/--ci/--linter/--ext/--mit/--coc/--changelog/--exe/--github-username/--no-*` 模板分支与 Thor 枚举/未知开关拒绝；`--edit`/`--bundle` 显式不支持并 exit 1；差分 `gem-options`/`gem-ext`/`gem-invalid` 4.0.24 与 2.7.2 各 3/0，`gem-default`/`gem-no-git` 4.0.24 2/0（2.7.2 沿用已声明 skip）；`spec/m7_gem_options_spec.cr` 4/0。复选框保持 `[ ]`。** 

**2026-11-19（L163 收口）：`--edit`/`--bundle` 显式 exit 1 是已声明的不支持边界（参考会打开编辑器/自动 `bundle install`），不是参考行为对齐；记录价值在于拒绝而非静默忽略。复选框保持 `[ ]`。** 

**2026-11-19（task-42 补记）：`install`/`update` 收尾补上参考 `cli/common.rb:34-47` 的直接依赖 funding 汇总（1 个用 is、≥2 用 are，第二行为 `bundle fund` 提示；`ignore_funding_requests` 置真、`--quiet` 或无命中时静默）；新差分 `install-fund-summary`/`install-fund-summary-two`/`install-fund-summary-ignored`/`update-fund-summary` 双 profile 各 4/0、回归 9 夹具双 profile 9/0，`spec/m7_funding_summary_spec.cr` 5/0。仍缺：参考的 auto-clean 未实现，故“汇总相对 auto-clean 的位置”无法对齐（标未验证）；`--without` 收窄下的人数未取到干净 oracle。复选框保持 `[ ]`。** 

**2026-11-20（task-49 补记）：`bundle issue` 无锁时改走共享 `doctor_report`（exit 0、写锁、`No issues found`），`env`/`issue` 共用 Gemfile 段与 `<No … found>` 占位；差分 N5 收紧为只丢 `## Environment` 正文，新增 `issue-no-lockfile`/`doctor-no-lockfile` 双 profile PASS，`issue-no-gemfile` 因参考读取宿主机 user config 记为 deferred。** 

**2026-11-20（task-51 补记）：`bundle cache` 目标改为 Gemfile 根（`--cache-path` 相对根），`BUNDLE_APP_CONFIG` 决定本地配置与插件根；差分工具支持夹具 `env` 文件；新增 `cache-into-gemfile-root`/`config-app-config-env` 双 profile PASS、旧二进制 2 FAIL，spec 7 examples，家族 60 examples 0 failures。未验证：2.7.2 `cache --all`/`--path` 废弃开关探针、deployment/exec 交互。复选框保持 `[ ]`。** cache-all-platforms 因宿主机 msys 原生扩展构建限制记为 deferred（见 `docs/compat-evidence/2026-11-20.md` task-51 小节）。 

**2026-11-20（task-52 补记）：install/update 按 BUNDLE_CLEAN 在收尾清理非锁文件 gem，见 `docs/compat-evidence/2026-11-20.md` task-52 小节。** 

**2026-11-20（task-54 补记）：`doctor ssl` 与 `diagnose --ssl` 对齐参考（退出码恒 0、OpenSSL 三行取自解释器、Bundler/net-http 走 bridge 探测）；见 `docs/compat-evidence/2026-11-20.md` 对应小节。** 

**2026-11-20（task-55 补记）：`bundle add` 的 `--glob`/`--version`/`--path` 失败面与 `update --redownload` 别名对齐参考，见 `docs/compat-evidence/2026-11-20.md` 对应小节。** ** 

**2026-11-20（task-56 补记）：`plugin new` 未知命令措辞、`licenses` 按 license 降序（含 bundler 自身）、`config` 本地路径保留原生分隔符、删除 `known_unimplemented?` 死代码；见 `docs/compat-evidence/2026-11-20.md` 对应小节。** 

**2026-11-20（task-57 补记）：`bundle update --bundler` 的目标解析（远端 bundler 版本、裸值 4.x `>= 当前` / 2.x `> 0.a`）、失败 exit 15 的原文措辞与 `BUNDLED WITH` 更新；见 `docs/compat-evidence/2026-11-20.md` 对应小节。** 

**2026-11-20（task-58 补记）：`lock --normalize-platforms` 补 `ruby` 平台（`spec_set.rb:66-89`）、`lock --lockfile` 只改写出路径不改读入路径；见 `docs/compat-evidence/2026-11-20.md` 对应小节。** 

**2026-11-20（task-59 补记）：undle add 的位置参数按 Thor 解析（选项值不再当 gem 名，空位置参数 ⇒ 15 Please specify gems to add.），install --target-rbconfig 缺文件在解析前以 LoadError/exit 1 中止并打印错误报告模板；通配展开属宿主 ruby.exe argv 行为，差分见 `docs/compat-evidence/2026-11-20.md` 对应小节。** 

**2026-11-20（task-60 补记）：update --redownload 命中缓存包时不再打印 Fetching（与参考一致）；缓存缺失时参考 exit 5 GemNotFound，celerite 仍重下载，已在 `docs/compat-evidence/2026-11-20.md` 声明。** 

**2026-11-20（本轮同步）：`add --glob` 的通配在宿主 `ruby.exe` argv 层展开（非 Bundler 归一化），机制见 `docs/compat-evidence/2026-11-20.md` 的 task-59 节（对应治理前的 compat-report.md 第 5422 行），README 差分段已同步说明。** 

**2026-11-20（task-62 补记）：四个「已声明未取 oracle」的组合已收口——`lock --lockfile … --print` 与 `install --redownload` 本就对齐；`lock --lockfile` 指向缺失目录时改为参考同形的 `--- ERROR REPORT TEMPLATE`/`Errno::ENOENT` 崩溃报告（原为一行 `celerite internal error`）；`install --target-rbconfig <存在文件>` 对纯 Ruby gem 不可观测。夹具 4 个、spec 扩到 8 例，详见 `docs/compat-evidence/2026-11-20.md`。** 

**2026-11-20（task-63 补记）：`bundle binstubs` 改为渲染 Bundler 的 `Executable` 模板（原为 gem 自带 executable 原文），产物与参考逐字节相同（`bin/thor` 347 B、`bin/thor.cmd` 389 B，`--shebang`/`bin` 子目录/2.7.2 `--path` 均对齐）；模板入库 `assets/bundler_templates/<profile>/Executable`，渲染与相对路径见 `src/celerite/binstub_template.cr`。新夹具 `binstubs-template` 双 profile PASS，spec 4/0，旧二进制 FAIL。** 

**2026-11-20（task-64 补记）：install 在 `BUNDLE_FROZEN`/`BUNDLE_DEPLOYMENT` 且无锁时改打参考文案（`The <flag> setting requires a lockfile…`，exit 16；4.x frozen 优先、2.7.2 deployment 优先），`check`/`update` 路径不动；`lock --add-platform <旧平台>` 现保留原生 ruby spec 行与对应 CHECKSUMS 行，并复刻 4.x/2.7.2 的 `x64-mingw32` 弃用告警（2.7.2 同时删平台）。夹具 4 个、spec 9 例，详见 `docs/compat-evidence/2026-11-20.md`。** 

**2026-11-20（task-65 补记）：两项真 bug 已修——① `lock-missing-dependency-edges` 长期失败的根因是安装期「内建 gem」判据按「同名同版本」而非「来源」，`net-protocol 0.2.2` 被误判为默认 gem 而跳过安装；改为 `ResolvedSpec#default_gem` 后双 profile PASS，此前「环境差异」的记录更正为产品缺陷。② 无锁时 `BUNDLE_FROZEN`/`BUNDLE_DEPLOYMENT` 的 `update --all` 应报平台缺项（exit 16）而非 `Frozen mode is set`，scoped update 仍 exit 22。** **（task-65 补记 2）`lock-missing-dependency-edges` 的 `Installing` 顺序非确定性来自参考侧并行安装，夹具加 `env: BUNDLE_JOBS=1` 并在 `jobs == 1` 时按串行对输出，stability: 10/10 runs；该夹具依赖宿主 gem 目录内容，判据只取 resolution 规格集。** 

**2026-11-21（task-68 补记）：`remove` 族四条失败面对齐参考——① `remove --install` 4.x 在命令体开头 raise `InvalidOption`（exit 15）且不动 Gemfile，2.7.2 打 `[DEPRECATED]` 软弃用后继续；② `remove <未声明 gem>` 先打 `Removing gems from …` 再 `GemfileError`（exit 4，按 80 列折行），不再 exit 1；③ `remove` 无参 `InvalidOption`（exit 15）`Please specify gems to remove.`；④ `Removing gems from …` 移到改文件之前，并在删空的 `group`/`source`/`env`/`install_if` 块上连同 `end` 整块删除、落盘按参考 `join.chomp` 加 `puts` 语义（缺结尾换行才补、LF 转平台 eol）。改动在 `src/celerite/cli/commands_surface.cr:730-896` 与 `src/celerite/errors.cr:68-113`（`GemfileError#wrap?` 为真、`DSLError#wrap?` 为假）。三夹具双 profile 全 PASS，spec 5/0，反假绿 `d0b9b7a` 旧二进制 3 failed；`add-*` 侧 5 条失败经复核为宿主 Low IL 下 msys 子进程 `0xC0000022`（同二进制从 `C:/temp` 运行 6/0、5/0），非产品差异。** 

**2026-11-21（task-69A 补记）：`outdated --parseable` 只在依赖为特定版本时拼 `, requested <req>`（`cli/outdated.rb:210-226` `dependency&.specific?`），表格 Requested 列不变（`:248-263`）；新夹具 `outdated-parseable-nonspecific` 双 profile PASS，`outdated-*` 全绿。** 

**2026-11-21（task-69B 补记）：`install --local` 不启用远程源，文案随 `vendor/cache` 存在与否在 `cached gems or installed locally` / `locally installed gems` 间切换，并在 app cache 存在时追加 ` or in gems cached in vendor/cache`（`definition.rb:190-203`、`source/rubygems.rb:69-76`、`:122-136`、`resolver.rb:334-361`）；新夹具 `install-local-index-unreachable` 双 profile exit 7 PASS，`install-local*`/`outdated-local` 回归绿。** 

**2026-11-21（task-70 补记）：`pristine` 缺缓存包时按参考只报错并跳过（不再打印 `Installing`，路径用正斜杠）；`info`/`show` 的多余位置参数按 Thor 面报错（各自 `GEM [OPTIONS]` 横幅），`list` 的 usage 串去 `[OPTIONS]` 后缀；夹具 4 个、spec 4 例，详见 `docs/compat-evidence/2026-11-21.md` 对应小节。** 

**2026-11-21（task-71 补记）：`info`/`show` 的 `select_spec` 补齐默认 gem 回退（`cli/common.rb:98-101`）与正则多选菜单（`:103-111`），bundler 走「运行中的 bundler」分支；夹具 `info-default-gem-fallback`、`info-regex-menu` 双 profile 通过，spec `m7_info_select_spec.cr` 4 例；`Did you mean` 建议与菜单选中分支未覆盖，见 `docs/compat-evidence/2026-11-21.md` 对应小节。** 

**2026-11-21（task-74A 补记）：`bundle clean` 在系统 gem 目录（未配置 `path`）且无 `--force` 时按参考抛 InvalidOption（exit 15、两行文案），不再删除系统 gem；`--dry-run` 与 `--force` 行为不变，夹具 `clean-system-gems-guard`。** 

**2026-11-21（task-74B 补记）：`config get/list` 的数组值按 Ruby `Symbol#inspect` 渲染（`[:"test,dev"]`），`--list --parseable` 同源；夹具 `config-array-symbol-render`。** 

**2026-11-21（task-78 补记）：`BUNDLE_VERBOSE` 与 `--verbose` 等价，verbose 转录补齐 `Found no changes…`/`Using …`/`0: … from …`/本地服务器行；已知未复现：下载计时行与并行工作线程序号（我方串行固定 0）。** 

**2026-11-21（task-79 补记）：verbose 的重解析原因行按 oracle 补齐三形态（`gems: (…)`、空名并接本地服务器行、`the dependencies in your gemfile changed`）；其余 12 条 `lockfile_changed_reason` 条件无触发取证，未实现。** 

**2026-11-21（task-80 补记）：`add --version` 按逗号列表逐条渲染 requirement（不再强行加 `= `），补 `--github` 并改用参考的选项顺序，补 4.x 独有的四条 option 互斥校验（2.7.2 无此块）。** 

**2026-11-21（task-81 补记）：`add` 在解析/安装失败后回滚 Gemfile 到调用前字节，并去掉失败路径多打的一行 `Resolving dependencies...`；`m7_gemfile_plugins_spec` 的两条断言是过期（那是 `plugin install --source` 的措辞），已按参考改为 `installed locally.`，非产品缺陷。** 

**2026-11-21（task-82 补记）：`add --github` 的源选择已与参考一致（`github:` ⇒ git 源 + `https://github.com/<repo>.git`），端到端因本机 msys git `0xC0000022` 无法验证，改由 spec 在求值边界断言；另记一条刻意不对齐：`install --redownload` 在 cache 缺失时参考 exit 5 崩溃，我方 exit 0 重下并回填。** 

**2026-11-21（task-83 补记）：`install --local` 只限制来源、不跳过安装步骤——参考仍把 `vendor/cache` 里的 gem 装进 bundle（跳过条件仅为「已在 bundle 中」），我方原先按 `local_installed_full_names` 过滤，把 GEM_HOME 里的同名同版本副本当成已安装而完全不装、bundle 留空；已删该过滤（`src/celerite/cli/commands_install.cr`）。差分夹具 `install-local-vendored-install` 为回归护栏（harness 隔离 GEM_HOME，无法复现前置条件，无区分力），区分力由 `spec/m7_local_install_step_spec.cr` 提供（基线 1 例失败）。** 

**2026-11-21（task-89 补记）：`install --standalone` 现按真实 `require_paths` 渲染，并对 `path:` 源（工程内外）输出 `#{__dir__}` 相对行，`require` 可用；夹具 `standalone-path-source` 双 profile 通过，已声明「声明绝对路径的 path 源我方相对化」。** 

**2026-11-21（task-90 补记）：`update --group <无成员组>` 现与参考一致——零解锁集时只打印 `Bundle updated!`，不取索引、不重解析、不写锁；夹具 `update-group-missing`/`update-group-present` 4.0.24 通过（2.7.2 因锁内 `BUNDLED WITH 4.0.24` 触发 self-manager 联网而 deferred）。** 

**2026-11-21（task-95 补记）：`install` 已按 `without` 过滤安装集合（未下载、未安装，计数同步），并在 `Bundle complete!` 后打印 `Gems in the group(s) '…' were not installed.`；锁内容仍写全，`--without` 旗标在 4.0.24 已移除故不实现。** 

**2026-11-21（task-98 补记）：`doctor` 的 settings 校验补齐 `with`/`without` 交集（stderr 四行，exit 15）与 4.x 专属的 `default_cli_command` 值域（stderr 三行，exit 15），均在解析前触发；差分 4.0.24 11/0、2.7.2 10/0/1（`default_cli_command` 在 2.7.2 无该规则，`deferred-2.7.2`）。** 

**2026-11-21（task-99 补记）：首次 `install` 现已把工程外 `path` 源拷入 `vendor/cache/<name>/`（拷贝路径改收调用方的 in-memory `generated_lockfile`，`lockfile_exists?` 短路仅留在 `cache` 自己的循环），`Bundled gems are installed into` 的路径文本按 `settings.rb:253-285` 重写：相对值加 `./`、绝对值原样（含反斜杠）、显式空 `BUNDLE_PATH` 打印 `./.`。夹具 `install-path-source-app-cache-first`（4.0.24；2.7.2 deferred）与 spec `m7_bundle_path_rendering_spec.cr` 覆盖；绝对路径无法用差分夹具表达（harness 无沙箱根占位符），只在 spec 覆盖。** 

**2026-11-21（task-100 补记）：`licenses` 改为从运行期 spec 读 license（`<bundle>/specifications/<full_name>.gemspec`，`PATH` 源按锁内 `remote` 找 `*.gemspec`，缓存 `.gem` 仅兜底），因此 path 源与「cache 被删」的 bundle 不再落 `Unknown`；排序按 license 降序、平局按「bundler 优先 + Gemfile 依赖顺序」，与参考逐行一致。夹具 `licenses-path-source`/`licenses-after-cache-removal` 双 profile 通过，spec `m7_licenses_spec.cr` 4 例。** 

**2026-11-21（task-101）：install --local 不再取索引/自愈，缺包按参考 exit 7；夹具 `install-local-lock-missing-edges` 双 profile 通过；已声明：锁内版本被索引刷新、--local+endor/cache 选择、缺包仍打印 Fetching 行。** **（三次窗口更正：install-local-lock-missing-edges 系 harness 假绿已删，该形状改由 spec+手工 oracle 覆盖。）** **（四窗口：--local 改为不解析、缺包走 installer 形态，5 变体矩阵入 `docs/compat-evidence/2026-11-21.md`。）** **（task-103 补记：单次 cache --all-platforms 与参考逐行一致，已补 path 源夹具作回归网；缓存已存在时重跑仍多打   * …gem 与一次 Updating files …，未修，待单列任务。）** **（task-104 补记：cache 重跑不再重复打印 Updating files …/  * …gem，缓存已存在时只留头部；新增两夹具作回归网。）** **（task-105 补记：bundle 骨架补齐 build_info/doc/plugins/extensions，进程锁文件随 close 删除；夹具 install-bundle-layout 逐树对比，负对照 8b9de5b 失败。）** **（task-106 补记：`install --local` 跳过 `BUNDLED WITH` 的 self-install，不打印、不联网，缺包仍报 installer 形态 exit 7；负对照为 stash 修复后跑 spec。）** **（task-107 补记：install --local 在锁平台覆盖本机且缓存齐备时不再多打 Resolving dependencies...，仅真正解析时打印。）** **（task-108 补记：lock --update 现按 --patch/--minor/--major 限制升级级别，多个级别同给在解析前 exit 15；update 侧共用同一校验。）** 

**2026-11-21（task-112 补记）：`bundle binstubs` 对 PATH/GIT 源改为经「已装 gemspec（bridge `load_installed_spec`）」读取 `executables`/`bindir`，不再要求 `<install>/cache/<full_name>.gem`；`--all` 一并覆盖。双 profile 夹具 `binstubs-path-source` 通过，负对照 `90d0391` 0/1。GIT 源因本机 msys `0xC0000022` 未做夹具。** 

**2026-11-22（task-113 补记）：`install --prefer-local` 只把本 bundle 已装的 spec（`specifications/*.gemspec` + `vendor/cache`）当候选，不再泄漏宿主 gem；本机 `Dir.glob` 对绝对 Windows 路径零命中，改用 `Celerite::Glob`。见 `docs/compat-evidence/2026-11-22.md` 对应小节。**

## 2026-11-23：默认参考 bundler 版本常量化（task-143）

### 五要素之一 · oracle

`Celerite::Profile.bundler_version`（环境未设时取 `Profile::DEFAULT_BUNDLER_VERSION`）必须与改前的内联表达式逐字同语义。改前基线在 `1af3a0d` 上以裸探针实测（Crystal 1.22.1 / Windows）：

- 未设 `CELERITE_PROFILE_BUNDLER_VERSION` → `"4.0.24"`；
- 设为空串 `""` → `"4.0.24"`（Windows 上空环境值被 OS 删除，`ENV[...]?` 得 `nil`，与「未设」不可区分）；
- 设为 `"   "` → `"   "`；设为 `" 2.7.2 "` → `" 2.7.2 "`；设为 `"9.9.9"` → `"9.9.9"`（不 trim、不校验、不回退）。

因此本次收敛**不得**新增「空/空白回退常量」——那会改变可观测行为。收敛后 `Profile.bundler_version` 即上述表达式的原样搬迁，并新增 spec 以独立 oracle 钉住默认值（见证据）。默认值另受两条既有约束交叉验证：它必须是 `Celerite::ReleaseMetadata::RELEASES` 的键（`"4.0.24" => {"2026-11-05", "3b396e4"}`），且 `Commands.profile_2_x?` 必须为 `false`，且 `assets/man/<默认值>/` 目录存在。

### 五要素之二 · 参考锚点

- `src/celerite/release_metadata.cr` 的 `RELEASES`（各发布编译期元数据表，本次**未改动**）——默认值必须能在其中解析；
- 参考实现侧 `bundle version` 的渲染形状（4.x 打印 `4.0.24 (2026-11-05 commit 3b396e4)`，2.x 打印 `Bundler version …`），由 `spec/m7_version_spec.cr` 既有断言覆盖；
- `assets/man/4.0.24`、`assets/man/2.7.2` 两套已 vendored 的 manpage 目录，是默认 profile 的下游消费者；
- 差分夹具 `fixtures/differential/cli-help`（该仓无 `gem-help`；`bundle help` 族以 `cli-help` 为准）、`install-fresh`、`lock-noop`。

### 五要素之三 · 实现位置

新增 `src/celerite/profile.cr`（21 行，唯一出处）：

- `src/celerite/profile.cr:11` `ENV_KEY = "CELERITE_PROFILE_BUNDLER_VERSION"`
- `src/celerite/profile.cr:15` `DEFAULT_BUNDLER_VERSION = "4.0.24"`
- `src/celerite/profile.cr:24-26` `def self.bundler_version : String` → `ENV[ENV_KEY]? || DEFAULT_BUNDLER_VERSION`

接线与替换：

- `src/celerite.cr:5` 新增 `require "./celerite/profile"`（置于 `errors` 等所有消费者之前）；`cli/commands` 经 `spec_helper`/`cli.cr` 各自 require，均可见。
- `src/celerite/manpages.cr:16` `PROFILE_DEFAULT = Celerite::Profile::DEFAULT_BUNDLER_VERSION`（原为 `"4.0.24"` 字面量，全仓仅此一处定义、无其它引用）。
- 其余 23 处内联惯用法全部改为 `Celerite::Profile.bundler_version`：`definition.cr` 1、`bridge/client.cr` 1、`errors.cr` 1、`cli/commands.cr` 8、`cli/commands_install.cr` 7、`cli/commands_surface.cr` 5。所有站点均为「取值后做 `starts_with?("2.")` 判定 / 透传打印 / 传给 `frozen_flag_exit`」，替换前后只动了取值表达式本身。

刻意**未**改动（核过语义后判为异事）：

- `src/celerite/cli/commands_install.cr:657/698/708` 用 `ENV["CELERITE_PROFILE_BUNDLER_VERSION"]?.try(&.starts_with?("2."))`——「显式设了才算」的三路或判定，本身不含默认字面量，改它即改判定；
- `src/celerite/cli/commands_install.cr` 中 `profile_2_x? ? "2.7.2" : "4.0.24"` 选的是 binstub 模板目录名，非环境默认值，若改走访问器会在非默认 4.x profile 下改变行为；
- `release_metadata.cr` 的 `RELEASES` 属另一关切（各发布元数据表）。

### 五要素之四 · 证据

改前/改后计数（对 `src/**/*.cr` 逐文件正则统计 `ENV["CELERITE_PROFILE_BUNDLER_VERSION"]? || "4.0.24"` 精确串）：

```
BEFORE: src/celerite/definition.cr 1, errors.cr 1, bridge/client.cr 1,
        cli/commands.cr 8, cli/commands_install.cr 7, cli/commands_surface.cr 5
TOTAL = 23
AFTER : TOTAL = 1   # 唯一残留是 src/celerite/profile.cr 注释里对该旧写法的说明文字
Celerite::Profile.bundler_version 调用点 TOTAL = 23（分布同 BEFORE 各文件）
```

门禁（全部本机实跑，工作树 `C:\temp\celerite-t143`，HEAD `c3709a1`）：

- `crystal tool format --check src spec` → `exit=0`；
- `crystal spec spec/m7_profile_version_spec.cr` → `7 examples, 0 failures, 0 errors, 0 pending`（新增 spec，见下）；
- `crystal spec spec/m7_ruby*.cr` → `30 examples, 0 failures, 0 errors, 0 pending`；
- `crystal spec spec/m7_help_manpage_spec.cr` → `12 examples, 0 failures, 0 errors, 0 pending`；
- `crystal spec spec/m7_cli_help_spec.cr` → `10 examples, 0 failures, 0 errors, 0 pending`；
- `crystal spec spec/m7_version_spec.cr spec/m7_version_promotion_spec.cr` → `11 examples, 0 failures, 0 errors, 0 pending`。

新增 `spec/m7_profile_version_spec.cr`（`test(M7 task-143)` 提交）7 例，断言**不**复写 `"4.0.24"` 字面量：

1. 未设环境时，`Profile.bundler_version` 必须是 `ReleaseMetadata.for` 能解析的版本（常量写错即失败），形如 `x.y.z`，且 `Commands.profile_2_x?` 为 `false`；
2. 未设环境时，`assets/man/<默认值>/` 目录必须存在；
3. 未设环境时，`bundle version` 的输出必须等于 `<版本> (<日期> commit <提交>)`，其中日期与提交取自 `ReleaseMetadata`；
4. 设为 `"2.7.2"` 时，`Profile.bundler_version` 与 `Commands.bundle_profile_version` 均取 `"2.7.2"`，`profile_2_x?` 为 `true`；
5. 设为未知名 `"9.9.9"` 时原样取值（不校验）；
6. 设为 `"   "` / `" 2.7.2 "` 时原样取值（不 trim、不空白回退），且 `profile_2_x?` 为 `false`；
7. `Manpages::PROFILE_DEFAULT` 与 `Profile::DEFAULT_BUNDLER_VERSION` 同值，未设环境时等于 `Profile.bundler_version`。

差分抽查（`script/differential`，本轮三组，引擎为本次构建的 `bin/celerite.exe`）：

```
=== A: reference 4.0.24 ===        PASS cli-help (exit=0) / PASS install-fresh (exit=0) / PASS lock-noop (exit=0)
                                   differential (4.0.24): 3 passed, 0 failed, 0 skipped
=== B: reference 2.7.2 ===         PASS cli-help (exit=0) / PASS install-fresh (exit=0) / PASS lock-noop (exit=0)
                                   differential (2.7.2): 3 passed, 0 failed, 0 skipped
=== C: CELERITE_PROFILE_BUNDLER_VERSION=2.7.2, reference 4.0.24 ===
                                   PASS cli-help (exit=0) / PASS install-fresh (exit=0) / PASS lock-noop (exit=0)
                                   differential (4.0.24): 3 passed, 0 failed, 0 skipped
```

C 组刻意用「引擎侧 profile 环境变量 = 2.7.2、参考侧仍 4.0.24」——两侧不一致时 `cli-help` 期望会分歧（2.x 打印 `Bundler version …` 前缀）；此处仍 PASS，说明本轮夹具的命令路径不经过该渲染分支，**该组只证明版本取值路径未被改坏，不构成 2.7.2 语义的覆盖**。2.7.2 语义由 B 组（参考侧亦 2.7.2）与 spec 第 4 例承担。

### 五要素之五 · 已声明差异

- **未覆盖**：全部 23 处站点的「取值之后的判定分支」未逐一做差分举证，仅由既有 spec 族（`m7_ruby*`、`m7_help_manpage`、`m7_cli_help`、`m7_version*`、`m7_profile_version`）与三组差分夹具间接覆盖；替换是纯表达式搬迁，逐站点已在改动前核对过原语义（含 `starts_with?("2.")` 各分支）。
- **未覆盖**：`fixtures/differential/gem-help` 不存在，`bundle help` 族以 `cli-help` 代替；任务书给的该夹具名在本仓无效。
- **未覆盖**：`docs/compat-claims/M7-3-placeholders.md` 断言账本本轮**未**同步（该路径属禁改范围），本轮证据仅落在本文件。
- **未勾选**：`docs/roadmap.md` 的 M7-3 行本轮不动（尚未到勾选条件），本文件为 M7-3 子项实证流水。
- **已声明**：Windows 上空环境值被 OS 删除，故「设为空串」在 Windows 上与「未设」不可区分；spec 第 6 例因此只钉 `"   "`/`" 2.7.2 "` 的原样语义，空串的等价性以裸探针实测结论记录，未写成可跨平台的断言。