# M7(1)-(3) 阶段性闭环汇总快照（HEAD=35fa404 evidence baseline + M7(4)/(6) 审计/修复 + config_spec docs-only + M7(1)/(2) 回归证据，2026-11-13）

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 131 -->

- **结论**：M7(1)(2)(3) 均为**部分证据化/未闭环**；M7(1)-(3) 复选框保持未勾选，不得据此视为 M7 整体验收通过。实现证据快照源头 HEAD=`35fa404`（`fix(M7 task-2): print lock-ruby unlock notice before empty-deps return in list`）在 582b099 satisfied-issue fixture、a482329 satisfied-`issue` doctor 对齐与 b4fe095/5949cc2 B2 修复基础上新增 B3 nolock deps-satisfied fixture（`check-satisfied-ruby-nolock`/`list-satisfied-ruby-nolock`）并修复 `list` 空 deps 早返回前打印 lock-ruby unlock notice；双 profile 4/0/0 PASS。582b099+ 受控探针（`6488b8a` docs-only）：`gem` 模板/选项/`--help` 显式 unsupported（`C:\temp\m7s3-gemopts-cel` 等），env/issue 归一化外字段差异取证，IRB-in-bundle ≤2 次未获稳定可用对照（阻塞+复现）。**docs 证据/边界同步至当前 HEAD=`1eeaefb`（task-2/task-3, in_progress）**；全量差分引用 1882f53/517f69a-rerun 实测（133 口径，全量本轮未重跑标注保留），本轮 combo-fixture 双 profile 实测随 497e293 提交；post-497e293 新增 e77c6cb normalization/installed-tree 对齐、94ec377 M7(4) 审计+redirect typing、a59d50f M7(6) plugin 审计、10e0a52 plugin hook after-install 对齐修复、1eeaefb config_spec 环境耦合 docs-only 记录。 2026-11-15（插件 hook 失败语义）：按参考实现 BUNDLE_PLUGINS 关闭跳过、加载失败 exit 1、hook 异常 exit 1、缺失 load_path 路径 warn 后 exit 0；见 `docs/compat-evidence/2026-11-15.md`「M7(6)：插件 hook 失败语义」节；复选框保持 [ ]。

<!-- 原 roadmap.md 行 132 -->

- **证据索引（关键 commit）**：`a8753b6`、`7c446d9`、`3c4f55d`、`34a8cad`、`f3ad8a5`、`ae8eafc`、`20690ff`、`8d20c17`、`0032664`、`14ccb9d`、`5949cc2`、`8f1ef39`、`b4fe095`、`7a4f1bc`、`bce1138`、`a482329`、`340f050`、`582b099`、`35fa404`、`6488b8a`、`b5cfa51`、`0423b2f`、`044aacb`、`bba7949`、`6eee96a`、`37b4287`、`1882f53`、`517f69a`、`4c2404a`、`497e293`、`206d749`、`e77c6cb`、`a59d50f`、`94ec377`、`10e0a52`、`1eeaefb`。详见 ``docs/compat-evidence/2026-11-12.md`` “M7(1)-(3) 阶段性闭环汇总（事实快照，14ccb9d/5949cc2 docs 基线 + b4fe095 B2 同步 + a482329/582b099 M7(3) issue/env/gem/IRB 边界证据同步，2026-11-12）”及 “Stage acceptance summary (docs aligned to HEAD=0423b2f, 2026-11-12)”。 2026-11-15（M7(2) check/list/show/info 选项面与 --gemfile）：按参考收敛白名单与未知开关报错，--gemfile 经 BUNDLE_GEMFILE 真生效（见 `docs/compat-evidence/2026-11-15.md`「选项面收敛」节）；复选框保持 [ ]。

<!-- 原 roadmap.md 行 133 -->

- **代表性 fixture/spec（既有实测/本轮部分复跑）**：M7 子集 8 文件 **70 examples, 0 failures, 0 errors, 0 pending, EXIT 0**（`ae8eafc` 前次记录；本轮 2026-11-13 @4c2404a+worktree 重跑 70/0/0/0 EXIT 0, 17.91s，证据随 497e293 提交）；M7(3) 子集 `spec/m7_console_spec.cr spec/m7_gem_spec.cr spec/m7_fund_spec.cr` **8/0/0/0 EXIT 0**（a482329 本轮手工/回归证据）。定向 differential：M7(2) 回归 6/6 双 profile EXIT 0（`ae8eafc`）、M7(3) env/issue 稳定集 `env-report issue-no-gemfile issue-missing-gems` **3/0/0 EXIT 0** 双 profile（`34a8cad` 既有；**a482329 后本轮复跑** shim bin 4.0.24/2.7.2，log `C:\temp\m7s3-diff-4024.log`/`C:\temp\m7s3-diff-272.log`）、2.7.2 M7 定向扩展 36/36（`7c446d9`）。

<!-- 原 roadmap.md 行 134 -->

- **双 profile 全量 differential（既有实测；497e293+本轮未重跑全量，引用后期实测日志）**：

<!-- 原 roadmap.md 行 135 -->

  - 4.0.24：**133 fixtures, 126 passed, 7 failed, 0 skipped, harness exit 1**（日志无显式 exit 标记，按 `[ "$fail" -eq 0 ]` 语义；tee wrapper exit 0；log `C:\temp\celerite-diff-full-4.0.24-1882f53.log`，post-37b4287 独立核实；FAIL 仅 A:7 racc/make 环境阻塞，按名零回归；`exec-loader`/`exec-loader-disabled` PASS；早期 130:123/7/0 log `C:\temp\celerite-diff-full-4.0.24-execloader-final.log` 保留为历史）。

<!-- 原 roadmap.md 行 136 -->

  - 2.7.2：**133 fixtures, 126 passed, 6 failed, 1 skipped, harness exit 1（日志无显式 exit 标记；tee wrapper exit 0）**（log `C:\temp\celerite-diff-full-2.7.2-517f69a-rerun.log`，2026-11-13 00:24:35 CST；FAIL A:6 racc/make；SKIP 1 `add-group` harness documented deferral；37b4287 按名零回归）。复现：`BUNDLER_REF_VERSION=2.7.2 CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`。

<!-- 原 roadmap.md 行 137 -->

- **本轮 combo-fixture 实测（证据基线 HEAD=497e293，fixtures 随 497e293 提交）**：`list-path-only-group` + `multi-platform-install-ruby` 双 profile 定向 **2/0/0 EXIT 0**（logs `C:\temp\celerite-diff-m7combos-4024.log`/`-272.log`）；43 例 M7 回归集双 profile **43/0/0 EXIT 0**（logs `C:\temp\celerite-diff-m7combos-reg-4024.log`/`-reg-272.log`）；M7 spec 子集 **70/0/0/0 EXIT 0**（17.91s）；该轮 gates format/no-codegen/diff-check EXIT 0。

<!-- 原 roadmap.md 行 138 -->

- **M7(1)（部分）**：约束过滤/RubyVersionMismatch exit 18/元数据 match+boundary+fail/多平台 lock+install、通知与安装复核证据已覆盖；B:1 exec-loader 已修复。B3 nolock deps-satisfied 通知已 fixture 化：`check-satisfied-ruby-nolock` + `check-missing-ruby-nolock`（lock 无 `RUBY VERSION`，Gemfile 声明 `ruby "4.0.6"`）双 profile **4/0/0 PASS EXIT 0**（`35fa404`，含 list 空 deps 早返回前通知修复）。未达/未验证：本地外 ABI/平台变体/gnu-musl 穷举、`show`/`info` 其他重解通知场景。本轮

（2026-11-13，HEAD=4c2404a+worktree）新增平台变体正例 fixture `multi-platform-install-ruby`（`lock --add-platform ruby`+install+check）双 profile 定向 PASS（4.0.24/2.7.2 各 2/0/0 EXIT 0 之一）。

**2026-11-15（M7(1) 约束矩阵审计，提交本轮）**：六机制（gem `required_ruby_version`、gem `required_rubygems_version`、Gemfile 目标 ruby/patchlevel/engine/engine_version、平台变体、ABI）逐条给出正反例与源码/夹具锚点，约束矩阵 33 例双 profile `33 passed, 0 failed, 0 skipped`；删除无调用的 `running_ruby_version_for_gem` 死代码（`src/celerite/resolver/source.cr`）；新增远程 compact index 索引 `fixtures/gem-index-ruby-constraints` 与 4 个远程元数据夹具（`ruby-metadata-remote-*`/`rubygems-metadata-remote-*`，因参考不对 `file://` 源走 compact index，改用本地 http 索引），把「远程过滤」从零负例补到双 profile 逐字节 PASS；并修复根级元数据排除的解释文案（原 `Because every version of future_gem depends on Ruby >= 99.0` 事实错误，现按连续后缀打印 `Because future_gem >= 1.0.0 depends on Ruby >= 99.0`，非连续回退 `= <min>`）。剩余：ABI 仍无差分夹具、分支 ③ 保守回退无参考逐字证据、真实 rubygems.org 未触达；复选框保持未勾。

<!-- 原 roadmap.md 行 139 -->

- **M7(2)（部分）**：

**2026-11-19（task-22 补记）：`check`/`list`/`show` 的已安装判据改为参考的 `specifications/<full_name>.gemspec`（平台后缀保留），目录存在但缺 spec 视为缺失，spec 在而目录缺时 `show` 按参考警告；新增差分 `check-installed-spec-without-gemdir`/`check-gemdir-without-spec`，4.0.24/2.7.2 均 PASS，定向回归 35/1/1（唯一失败为既有 Low-IL git 夹具）。详见 `docs/compat-evidence/2026-11-19.md` 同名节。** 安装后发现、path/GIT/group/with-without、`show-info-installed`/`info-reverse-dependencies-path` 等证据与双 profile 定向回归已覆盖（`ae8eafc`）。未达/未验证：B1 Default Gem 稳定差分/spec 取证受限（探针阻塞/布局与 sandbox 限制）；path/GIT+group/平台组合部分补强：本轮新增 `list-path-only-group`（path 源+group+`--only-group default`）双 profile 定向 PASS，GIT+group、`--with/--without`、更多平台变体仍未穷尽。

**2026-11-18（M7(2) 命令名解析 / `tree` / `[REMOVED]`，提交 `e806aa6` + 本条注记所在 commit）**：Thor 前缀解析（`instal`→`install`、4.0.24 `cl`→`clean`、2.7.2 `cl` 歧义）、歧义报错 exit 15、`tree` 与 `-t`/`--tree` 映射、4.0.24 `viz`/`inject` `[REMOVED]` exit 9、`install_or_cli_help` 三行告警均已实现；11 组 A/B 逐字相等（`tree` 2178 字符 / 2326 字节、41 行；`viz` 125 字节、`inject` 70 字节）；新增差分夹具 `ambiguous-command-prefix`/`removed-viz`/`removed-inject`/`tree-command`（裸名跑；首版 `command` 缺行尾换行导致空比较假绿，已补换行并复测）：4.0.24 `4 passed, 0 failed, 0 skipped`（co 15/viz 9/inject 9/tree 0，保留产物 err 47/125/70、out 2326 字节全非空）；2.7.2 `3 passed, 0 failed, 1 skipped`（`removed-viz` 为 documented deferral：参考多打一行内嵌宿主 gem 计数与 GEM_PATH 的 `Gem::MissingSpecError`）；`spec/m7_cli_dispatch_spec.cr` 9 examples 0 failures。剩余：`clean` 的 `--force` 守卫位置差异（我方先撞 `Could not locate Gemfile` exit 10，参考 exit 15 打危险提示）、2.7.2 `viz`/`inject` 的 `[DEPRECATED]` 告警路径未做逐字 A/B。复选框保持未勾。

<!-- 原 roadmap.md 行 140 -->

- **M7(3)（部分）**：

**2026-11-19（task-21 补记）：锁文件钉死不兼容 gem 时安装期复核对齐参考——复用前用 `required_ruby_version`/`required_rubygems_version` 识别不兼容钉子并回退解析，复现参考 exit 6 的 Molinillo 文案；另加 `Installer.ensure_specs_are_compatible!` 兜底（参考 `installer.rb:234-245`，CLI 下不可达，仅单测）。差分 `install-locked-ruby-incompatible` 4.0.24/2.7.2 均 PASS exit 6，spec 3/0；详见 `docs/compat-evidence/2026-11-19.md` 同名节。** `fund-path`；env/issue 稳定集 `env-report issue-no-gemfile issue-missing-gems` 双 profile 3/0/0 + `fixtures/differential/issue-satisfied` 双 profile 1/0/0 PASS（582b099）+ B3 `check-satisfied-ruby-nolock`/`list-satisfied-ruby-nolock` 双 profile 2/0/0 PASS（`35fa404`，含 list 通知修复）。B2：`exec ruby`/IRB-not-in-bundle exec-irb 对齐（5949cc2+b4fe095），console UX exec-irb 语义差异残留阻塞（bce1138）。582b099+ 受控探针（docs-only）：`gem` 固定 5 文件 scaffold，`--test=rspec`/`--ci=github` EXIT 0 仅 warning+同 scaffold，`gem`/`--help` EXIT 1 `Please provide a gem name`，目录已存在 EXIT 1 `Directory ... already exists`（ref 10 文件+丰富选项）—**显式 unsupported/未覆盖**；IRB-in-bundle（`C:\temp\m7s3-irb-bundle\project`，≤2 次）尝试 1 materialization 缺 gem、尝试 2 `celerite exec ruby` EXIT 0 但 `exec irb` EXIT 1 `LoadError ... fiddle/import`（reline/fiddle 链），未获稳定可用对照—**未验证/阻塞+复现**；env/issue 归一化外字段差异取证（profile 标识/Gem Path 分隔符与组成/Bin Dir/Build Metadata/settings 块）维持边界。`setup:windows:*` bridge 不可用。

**2026-11-18（M7(3) 侧的同类收口，与 M7(2) 注记同批）**：`tree` / `viz` / `inject` 在 2.7.2 下的 profile 门控已实现并 A/B 一致——`tree`/`-t` 按未知命令/未知开关 exit 15（31 / 22 字节），与 4.0.24 的 `tree` exit 0 分属两条路径；`spec/m7_cli_dispatch_spec.cr` 覆盖双 profile 断言。2.7.2 的 `viz`/`inject` 仍走 `major_deprecation 2` 的 `[DEPRECATED]` 告警路径，未做逐字 A/B（显式未验证）。

**2026-11-19（M7(3) `console` 语义，本注记所在 commit，基线 `a5fc605`）**：`console` 由「exec 控制台可执行文件 + `RUBYOPT=-rbundler/setup`」改为 `assets/bridge/console_boot.rb` 引导——`require "bundler/setup"` → 有 GROUP 时 `Bundler.require(:default, *groups)`、无 GROUP 时无参 `Bundler.require`（实测只 require 默认组）→ `ARGV.clear` → require 控制台 gem 并 `start`，`LoadError` 按参考文案回退 irb / `irb is not available` exit 1；`GROUP` 自此真正参与组 require（旧实现只计数）。参考实测两 profile 一致：`console foo` → `PROBE_START default=1 foo=1` exit 0、`console` → `default=1 foo=0` exit 0；新增差分夹具 `console-group` 双 profile `1 passed, 0 failed, 0 skipped`（`KEEP_DIFFERENTIAL=1` 抽查两侧 37 字节逐字一致、stderr 空，非假绿）；`spec/m7_console_spec.cr` 8 examples 0 failures（含负对照：改回仅 `bundler/setup` 时 4 条组断言失败）；既有 10 夹具回归 4.0.24 `10 passed, 0 failed, 0 skipped`、2.7.2 `8 passed, 0 failed, 2 skipped`。已声明差异：仍为独立 `ruby` 子进程而非进程内 `console.start`、不镜像 `Gem::BUNDLED_GEMS.force_activate`、交互 TTY 会话未逐字 A/B。复选框保持未勾。

<!-- 原 roadmap.md 行 141 -->

- **通用阻塞与硬约束**：stock `crystal build` OpenSSL `EVP_MD_size` 阻塞（本次基线检查 `crystal build --no-codegen src/cli.cr` EXIT 1，`sh` 不可用/`pkg-config` 探测失败），证据依赖 shim 本地 bin（未入库）；A:7/A:6 为 `make` 缺失环境阻塞，2.7.2 `add-group` 为 harness deferral；bridge 不可用不得视为通过。全量差分未在 5949cc2/b4fe095/a482329/582b099/35fa404/6488b8a/b5cfa51/0423b2f/4c2404a 及本子项后重跑（引用 1882f53/517f69a 实测）；M7 spec 子集本轮已重跑 70/0/0/0 EXIT 0。复现：`CELERITE_BIN="$PWD/bin/celerite.exe" TMPDIR=/c/temp bash script/differential`；`BUNDLER_REF_VERSION=2.7.2 ...`。

<!-- 原 roadmap.md 行 142 -->

- **task-2 收口建议（供首辅裁断）**：不建议宣告 M7(1)-(3) 整体验收收口/不勾选 M7 复选框；task-2 保持 `in_progress`。582b099 已 fixture 化 satisfied-issue（双 profile 1/0/0 PASS）；本子项（docs-only）固化 gem/env-issue 字段/IRB-in-bundle 边界 probe 证据（显式 unsupported/未验证+阻塞+复现）；`35fa404` 修复 B3 list 空 deps 早返回前打印 lock-ruby unlock notice 并 fixture 化 B3 两分支（check/list satisfied+missing）双 profile 4/0/0 PASS。剩余：IRB-in-bundle/交互可用路径、Case C、`gem` 完整模板/选项/`--help`、env/issue 归一化外字段与稳定集外输出、B1 Default Gem、`show`/`info` 其他重解通知场景、path/GIT+group/platform 等 M7(1)/(2) 补强与阶段验收汇总。后续按 lead 指示继续低成本可行子项，达当前环境最大可行闭环后提交汇总报首辅裁断 task-2 收口与 task-3 启动。

<!-- 原 roadmap.md 行 144 -->

- **config_spec round-trip 既存失败

（2026-11-13，docs-only）**：`crystal spec spec/config_spec.cr` 在本环境失败 1/9（L97/L113），根因 global `~/.bundle/config` 6 个非 nil `BUNDLE_GEM__*` 键（gem.changelog/ci/coc/linter/mit/test=false） survives `Config#all`（返回 @local.keys）。nil-filter 尝试无效（global keys 非 nil）。裁断 docs-only：不改 `all` 语义、不改 spec 期望、回退 src/celerite/config.cr；环境耦合记录 + 复现 `crystal spec spec/config_spec.cr`。M7 复选框不勾。
