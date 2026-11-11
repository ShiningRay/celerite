# 实施计划

日期：2026-11-06；正确性与性能阶段更新：2026-11-10
范围：完整 Bundler 兼容的 Crystal 原生核心 + 受控 Ruby 边界，而不是重写全部 RubyGems。
M0–M6 是历史实施记录；`[x]` 只表示已有实现或场景证据，不表示整个里程碑达到完整产品验收。
未满足验收的项目在 M7 重新打开，当前从 M7 开始，不沿用“全部完成”的旧结论。

## 决策

- 名称：Celerite；仓库：`ShiningRay/celerite`，公开，默认分支 `main`。
- 语言：Crystal >= 1.21.1；优先标准库，第三方 shard 需按能力与维护状态单独评估。
- 默认命令：`celerite`；`bundle` shim 只在用户明确选择后安装。
- 目标：完整产品兼容。采用 Crystal 原生热路径 + 受控 Ruby 兼容桥。
- 参考：固定 Bundler 4.0.24 与仍受支持的 2.7.2，在 CI 记录 Ruby/RubyGems 版本和上游 revision。

## 执行规则

1. 每个阶段先建立失败用例，再实现；每个兼容性结论绑定参考版本。
2. 依赖顺序串行，只有独立 fixture、文档或不同模块可并行。
3. 不把整个安装静默委托给 Bundler；显式兼容引擎与原生引擎均可观测。
4. 每阶段运行 Crystal spec、格式检查、差分测试和负向测试；真实安装后再验收。
5. 性能基准在功能正确后执行；禁止降低校验与一致性来达标。
6. 默认采用独立 Crystal 可执行程序 + Ruby 适配层。Ruby C API/FFI 仅作为 M10 的可选 spike，不在边界未稳定时引入。
7. 每个桥调用尽量处理完整批次；每个优化必须记录 Ruby 启动、bridge 调用、I/O、CPU 和内存变化，不能只报告 CLI 总耗时。
8. 不用“命令数”“配置键数”或经过强归一化的 fixture 通过率替代完整兼容率。

## M0–M6：历史实施记录

### M0：契约与测试基线（已有基线，门禁修复转入 M7）

**目标**：先确定“与什么一致”，避免实现错误语义。

任务：

- [x] 建立 `docs/compat-matrix/` 的版本化功能清单，展开 CLI flags、配置键、Gemfile DSL 和 lockfile section。（CLI flags 由 `script/gen-cli-baseline` 从固定版本生成）
- [x] CI 安装固定 Ruby/Bundler 组合，锁定 `rubygems/rubygems` 测试 revision。（本地先行：Bundler 4.0.24 + 2.7.2 安装并记录于 `vendor/reference/MANIFEST.md`；CI 矩阵已建（.github/workflows/ci.yml））
- [x] 实现 `script/differential`：隔离 HOME、项目、gem 安装目录与网络 fixture，收集退出码、输出、锁文件和文件树。
- [x] 创建最小 fixture：纯 Ruby 依赖、冲突、预发布、多平台、多 source、动态 Gemfile、Git/path、原生扩展和插件。（M0 先交付锁文件驱动的 7 个差分 fixture；预发布/多平台/Git/path/扩展/插件 fixture 随 M2–M4 的实现路径补充）
- [x] 运行上游 Bundler spec 的可行性 spike，记录不适用项及原因。（spike 记录见 docs/upstream-spec-spike.md；64 例记录于 docs/compat-matrix/generated/upstream-lockfile-v4.0.24.md。**实际记录为 64 failures，不是通过；上游门禁在 M7 重新打开。**）

验收：同一 fixture 两次参考运行结果确定；基线产物无 token/绝对路径等非确定泄漏。✅（差分 sandbox 无 HOME 泄漏；路径正规化）

## M1：基础模型与只读锁定工作流（锁定夹具已实现，完整验收转入 M7）

**目标**：实现可靠的只读路径，再开放写入。

任务：

- [x] 实现 RubyGems 兼容 `Version`、`Requirement`、平台模型及性质测试；不套用 SemVer 规则。（含由参考 Ruby 生成的排序/满足性 oracle fixture）
- [x] 实现 lockfile parser/AST/serializer；覆盖 `GEM`、`PATH`、`GIT`、`PLUGIN SOURCE`、`PLATFORMS`、`DEPENDENCIES`、`CHECKSUMS`、`RUBY VERSION`、`BUNDLED WITH`、`CONTENT ADDRESSES`。（未知 section 保真保留；`CONTENT ADDRESSES` 作为未知 section 保真，4.0.24 基线无此 section）
- [x] 实现 CLI、配置发现和 Ruby 环境探测；建立 bridge 协议版本和错误模型。（配置发现与错误模型完成；Ruby 环境探测经 bridge 属 M2，本地平台解析已原生实现）
- [x] 实现 `version`、`platform`、`check`、`show`/`info`、`list` 的锁定路径。
- [ ] 对未知格式、无效版本、缺失 gem、Ruby 不匹配与权限错误做负向测试。（未知格式/无效版本/缺失 gem/merge 冲突已测；权限错误与 Ruby 不匹配尚无完整证据。）

验收：**未完整通过**。无网络锁定夹具与参考一致且不改锁文件；安装后 gem 发现、Ruby 不匹配与权限错误在 M7 补齐。

## M2：索引与依赖解析（常规夹具已实现，约束与网络边界转入 M7）

**目标**：Crystal 独立完成常规 RubyGems source 的解析和锁定。

任务：

- [x] 实现 Compact Index parser、持久化缓存、ETag、Range、206/200 和 `Repr-Digest`。（`spec/compact_index` 覆盖 parser/created_at 解析；HTTP cooldown 差分走真实增量缓存路径。）
- [x] 实现 PubGrub solver、候选分组、锁版本偏好、冲突推导、可解释错误和有界放宽重试。（`spec/resolver/solver_spec` + lock/update 大组差分双 profile 通过。）
- [ ] 接入 Ruby/RubyGems 约束、预发布、yank、source 优先级和 cooldown。（预发布、yank 和 cooldown 已有场景；索引已读取 required Ruby/RubyGems 字段；`ResolutionSource#ruby_requirement_satisfied?` 已按运行时 `RUBY_VERSION`/RubyGems 版本过滤（与 Bundler `matches_current_ruby?` 一致，`032a531` 起），但 engine/ABI/Gemfile 目标 Ruby 的完整矩阵与安装复核仍在 M7 收敛。）
- [ ] 实现 Gemfile bridge 求值、gemspec 求值与稳定指纹。（桥求值已实现；目前仅 Gemfile 内容 SHA-256，不含 ENV、引用 gemspec、配置和 Ruby 环境的完整指纹，M8 继续。）
- [ ] 实现 `lock`、`install` 的解析阶段、`update --conservative` 和平台管理。（`lock-file-pin/unlock/update`、`update-conservative`、`multi-platform-lock`、`platform` 差分双 profile 通过；Ruby/平台约束完整验收在 M7。）
- [ ] 用真实项目锁文件做解与 diff 回归，不将结果差异常化忽略。（真实 Bundler 锁 fixture 字节往返和锁驱动差分已做；Rails 规模真实项目回归在 M7。）

验收：**未完整通过**。常规小夹具已验证，但 Ruby/RubyGems 约束、Rails 规模与真实网络/平台边界未关闭。

## M3：安装、缓存与运行时

**目标**：常规 rubygems.org 项目能真实安装并启动。

任务：

- [x] 实现 gem 下载、SHA-256 校验、内容寻址缓存与并发去重。（`spec/downloader_spec`（下载/hex 校验）+ `install-fresh/install-rerun` 差分。）
- [x] 实现 gem package 读取、原子安装、specification、executables 和 binstubs。（基础安装路径与固定夹具已做；通用安装文件树内容比较和完整故障清理由 M7/M9 补齐。）
- [x] 实现 `install`、`cache`/`package`、`clean`、`pristine`、`binstubs` 的相关路径。（`install-fresh`、`pristine({,-named})`、`git-pristine`、`clean-unused` 差分覆盖 Rubygems/Git/path 的重装与清理语义（双 profile）；`cache` 由 `install` 后 `vendor/cache` 检查复核路径。）
- [ ] 实现 `exec`、runtime setup 与 `ruby -rbundler/setup` 适配；覆盖嵌套调用、信号、退出码、Ruby shebang 的 `Kernel.load` 和 `disable_exec_load`。（已有参考 Bundler runtime、Ruby `Kernel.load` 和退出码场景；轻量独立 runtime 属 M9，Windows 信号边界未关闭。）
- [ ] 验证中断、磁盘错误、校验失败、无网络、重复安装及多进程竞争。（校验失败、重复安装、无网络和锁互斥已有测试；磁盘错误、中断及安装失败原子清理未完整验证。）

验收：**未完整通过**。最小应用与原生扩展 fixture 可运行；Rails 规模、完整安装树内容比较、独立 runtime 和故障注入在 M7/M9 继续。

## M4：所有内置 source、平台与扩展

**目标**：超出纯 Ruby、单一 rubygems.org 的简单场景。

任务：

- [ ] 实现 Git 的 branch/ref/tag/revision/submodule、缓存和锁 revision。（branch/ref 已有 fixture；tag/submodule/glob 和离线恢复需要独立差分。）
- [ ] 实现 path、gemspec、monorepo 与本地变更失效策略。（基础 path/gemspec 安装已做；多 gemspec、monorepo 和完整失效指纹待 M8。）
- [ ] 完成平台专有 gem、多 ABI、锁平台规范化、离线 cache。（已有固定场景；Linux gnu/musl、多 Ruby ABI 与真实离线缓存矩阵待补。）
- [ ] 经 bridge 执行原生扩展构建，复现 build args、Ruby ABI 隔离和失败清理。（基础 racc 构建和 target-rbconfig 已验证；`build.<gem>`、完整失败清理和跨 Ruby ABI 待补。）
- [ ] 建立 macOS/Linux 和受支持 Ruby 矩阵；评估 Windows 后单列实现计划。（已有 CI 配置和本机证据，不等于所有组合实际通过。）

验收：**未完整通过**。先保留 Ruby/RubyGems 扩展构建边界，跨平台、source 变体和失败清理由 M7/M9 收敛。

## M5：CLI、插件与 Ruby API（部分实现，完整兼容验收转入 M7）

**目标**：覆盖用户所选“完整产品兼容”，不只常规安装。

任务：

- [ ] 完成所有内置命令、flags、alias、help、错误格式和配置持久化。（命令入口较多，但 `check/list` 的安装后路径、`fund`、完整 `gem` 模板、重试和若干配置并未完整生效；以 M7 和 compat-report 为准。）
- [ ] 完成 Gemfile 任意 Ruby DSL 语义和全部 source 行为。（Gemfile 经真实 `Bundler::Dsl` 求值；source 的 mirror/proxy/SSL/legacy index 和插件 source 完整边界未关闭。）
- [ ] 实现插件安装/index、命令分发、生命周期 hook、自定义 source 和 PATH fallback。（安装/index/hook 和部分远端/Git 路径已实现；插件命令注册、自定义 source 与第三方插件生态需要实证。）
- [ ] 实现公开 `Bundler` Ruby API 与 `bundler/inline` 适配及插件可见对象；建立第三方插件 fixture。（当前 fixture 通过真实参考 Bundler runtime 运行，不代表独立 Ruby 适配层已实现。）
- [x] 实现显式 `bundle` shim、`BUNDLED WITH` 版本选择与回退机制。（script/bundle opt-in shim；install 自动切换双向并记录切换版本；update 记录运行版本；回退见 docs/upgrade-and-uninstall.md）
- [ ] 运行适用的上游 Bundler suite，逐项记录例外并由评审确认。（已完成可行性 spike；现存 64 例记录全部失败，不是绿色上游测试。）

验收：**未达到**。M7 先关闭正确性与证据缺口；不以命令入口或参考 Bundler 运行时通过来代替完整兼容。

## M6：性能、发布与采用

**目标**：在正确性已证明后优化并提供可回退的采用路径。

任务：

- [x] 建立冷/热缓存、无变化、解析、下载和扩展构建 benchmark。（`script/benchmark 3` 覆盖冷锁/热锁/无变化锁、安装供给/原生扩展随包构建；原始结果见 `docs/benchmarks/results-2026-11-09.md`，可复现。解析（resolve）与下载分开计量归 profile 跟进。）
- [x] profile 启动、分配、锁竞争、I/O 与 CPU，按数据优化 Fiber 并发及必要的多线程。（`script/profile`（[results](docs/benchmarks/profile-results-2026-11-09.md)）：启动 26ms vs 274ms、桥分配 ~13k vs 参考锁 ~123k；数据证明瓶颈不在 solver CPU，为新瓶颈继续保留单线程确定性求解，不引入 Fiber/多线程。锁竞争按单进程 mutex 实现。）
- [x] 完成缓存 GC、损坏恢复、诊断、脱敏、升级和卸载文档。（`clean` 差分覆盖过期 gem 的 GC 语义（`clean-unused`）；损坏缓存由 `Repr-Digest` 校验与文件 MD5 回退处理；凭据与诊断变量见 `docs/upgrade-and-uninstall.md`；脱敏在 UI/桥协议层执行。）
- [x] 提供构建产物、校验和、安装脚本与显式 shim；默认不替换系统 `bundle`。（script/release 产出 dist 二进制+bundle shim+install-celerite.sh+checksums，资产名规范化为 celerite-<version>-<os>-<arch> 三元组；curl|bash 安装通道：install.sh 由 releases/latest/download 分发——平台探测、从 checksums 发现最新版本、SHA-256 验证后才安装、bundle shim 仅在无系统 bundle 时落盘（否则 celerite-bundle）；已本地 file:// 假 release 端到端验证（latest/pinned/篡改拒绝三探针）；script/publish + tag 触发 release.yml（三平台构建、按平台 checksums 合并后 gh release 上传）；另建 rubygem 分发通道：script/gem 平台 gem 冒烟验证，exe/celerite shim 自动导出 bridge 环境，CI gem-package job 三平台产物，gem shim 经 CELERITE_BIN 差分子集双 profile 验证；实际发布（tag 推送/gem push）待用户执行）
- [x] 发布兼容报告与基准原始结果，不以营销数字代替数据。（`docs/compat-report.md`（含明确未覆盖清单）；基准原始结果与 profile 见 `docs/benchmarks/results-2026-11-09.md`、`profile-results-2026-11-09.md`；2026-11-07 版结果保留可复核废弃/变化。）

验收：基准可复现；兼容报告对应 commit；用户可明确切换与回退，且不会丢失现有配置。

## 当前阶段：M7–M10

### M7：正确性与兼容证据收敛（当前优先）

**目标**：修复会影响依赖选择和真实项目正确性的缺口；使兼容声明与测试证据一致。

任务：

- [ ] 实现当前 Ruby、RubyGems、Gemfile 目标 Ruby、engine、patchlevel 和 ABI 的约束过滤；将 `ResolutionSource#ruby_requirement_satisfied?` 完整实现并验证（进展 032a531+本迭代：新增 `RubyVersion`/`RubyRuntime`、`RubyVersionMismatch` exit 18、bridge `ruby_environment.patchlevel` 与结构化 Gemfile `ruby` 选项、运行时校验接线与 `platform` mismatch 文案语义、gem metadata 按 `RUBY_VERSION` 过滤（patchlevel 只在 Gemfile 目标校验参与，与 Bundler `matches_current_ruby?` 一致）、`ruby_compatible?`/lock reuse/ruby_update patchlevel 处理；`spec/ruby_version_spec.cr`（10）+`spec/m7_ruby_runtime_spec.cr`（7，含 version/engine/engine_version/patchlevel mismatch 文案与 exit 18、bridge 结构化 Gemfile `patchlevel: "1"`/`engine: "jruby"`/`engine_version` 传递）+`spec/m7_platform_spec.cr`（2，bridge 不可用输出“未校验”而非满足）+`spec/m7_ruby_constraints_spec.cr`（10）+`spec/m7_resolver_ruby_constraints_spec.cr`（8，含 Ruby/RubyGems-only 排除的 SolveFailure exit 6 与纯无匹配 exit 7）通过，本轮 M7 spec 合计 108 examples/0 failures（含安装后发现 20、fund 2、gem 4、console 1）；已新增 `fixtures/differential/ruby-version-mismatch`（check）、`platform-ruby-mismatch`（platform）、`list-multi-group`（list 多组）、`no-matching-version`（无可用版本，exit 7 与参考一致）与 `platform-variant-fail`（平台变体，exit 7 与参考一致）与 `ruby-engine-mismatch`（engine 变体，exit 18）、`ruby-patchlevel-mismatch`（patchlevel 变体，exit 18）、`ruby-metadata-fail`（Ruby 元数据 SolveFailure，exit 6 与参考一致）、`rubygems-metadata-fail`（RubyGems 元数据 SolveFailure，exit 6 与参考一致）与 `install-check`（install 后 check，exit 0），并用本地 OpenSSL shim 实际运行通过（定向 differential 18 passed/0 skipped，含 PATH 源 `check-path`/`list-path` 与 GIT 源 `git-installed-discovery`；2.7.2 定向子集 18/18 已跑；全量 4.0.24 为 96 passed / 14 failed / 0 skipped，14 项分类见 `docs/compat-matrix/generated/differential-4.0.24-2026-11-11.md`，均不在 M7 路径）。**已修复**：`ruby-metadata-fail`（PATH gem `required_ruby_version >= 99.0`）现与参考一致——仅因 Ruby/RubyGems 元数据排除时报告 SolveFailure（exit 6 + 同形解释），纯无匹配版本仍报 GemNotFound（exit 7）；`deferred-4.0.24` 已移除。**未达验收**：仍缺 engine/patchlevel/ABI/Gemfile 目标 Ruby 全矩阵正反例与安装复核；bridge 不可用时校验 best-effort 跳过，**不得视为通过**；依赖 bridge 环境时需复核。**本机 codegen/CLI 集成 spec/differential 受阻**：Crystal 1.22.1 绑定 OpenSSL 1.1 `EVP_MD_size`，MSYS2 ucrt64 OpenSSL 3.6.5 仅导出 `EVP_MD_get_size`（`nm` 验证），stock 链接失败；本轮已用**仓库外** C shim + `--link-flags` 本地重建 `bin/celerite.exe`（EXIT 0，`--version` 0.1.0，不入库），据此跑通 CLI spec（24/0）与 differential（定向 18 passed/0 skipped、2.7.2 定向 18/18、全量 96/14/0）；复现命令与 shim 说明见 `docs/compat-report.md` 的 Local verification run 节。修复需 OpenSSL 1.1 工具链或升级 Crystal 绑定）。
- [ ] 修复安装后 `check`、`list`、`show`/`info` 的 gem 发现，不再把所有锁定 gem 固定视为 missing；补齐 group、`with/without` 和 path/Git 安装状态（进展：`installed_gem_dir` 容忍缺 specifications 文件；修复 `show --paths <name>` 将 `--paths` 误作 gem 名；`list` 人类可读默认格式对齐 4.0.24（header + `  * name (version)` + `bundle info` 提示）；`spec/m7_installed_discovery_spec.cr` 20 examples 0 failures，覆盖 check/list/show/show --paths、缺目录/仅 specification 负例、PATH 与 GIT checkout、`--only-group`/`--without-group`、空格分隔多组 `--only-group default test` 与 `--without-group test development`、`BUNDLE_WITH`（with 显式包含）以及平台特定 gem（`nokogiri-x64-mingw-ucrt`）发现；新增 `fixtures/differential/list-multi-group`、PATH 源 `check-path`/`list-path`、GIT 安装态 `git-installed-discovery`（install → check/list/show --paths/info --version）并实跑 PASS；同时对齐 4.0.24 的 git 短 revision 显示（`name (version rev)`）与 Windows 路径正斜杠渲染；另对齐 `show <gem>` 仅打印安装路径、`info <gem>` 按 4.0.24 顺序输出 tab 缩进元数据字段（`show-info-installed` 实跑 PASS）。未达验收：仍缺更多平台变体与 path/Git + group 组合的 differential 证据）。
- [ ] 移除或实现占位路径：`fund` 的真实 metadata、`gem` 模板、完整 `console`/`env` 行为；避免硬编码 Bundler 版本、时间戳和运行环境（进展：fund 读取已安装 specifications/`.gem` metadata，`spec/m7_fund_spec.cr` 2 examples 通过（有/无 funding）；gem 最小可用 scaffold（下划线 lib 文件名、`require_relative`+`Module::VERSION`、README/LICENSE、显式 unsupported 选项提示），`spec/m7_gem_spec.cr` 4 examples 通过；console 在无 irb 时 127+明确说明，`spec/m7_console_spec.cr` 1 example 通过；env/issue Build Metadata 使用 `Celerite <version>, compatibility profile` + 真实 checkout SHA/Timestamp 且失败回落 `unknown`，不伪装上游 Bundler 构建。未达验收：缺更多行为/差分证据）。
- [ ] 让 mirror、proxy、redirect、retry、SSL CA/client cert、`path.system`、`build.<gem>`、legacy/full index 回退具有真实生效路径；为不支持项快速失败，禁止只解析 flag/config 后静默忽略。
- [ ] 补齐 Git tag/submodules/glob、多个 gemspec、monorepo、私有 source 鉴权、离线安装、磁盘错误与中断清理；验证 Linux gnu/musl 和多 Ruby ABI。
- [ ] 插件命令注册、自定义 source、hook 异常和第三方插件 fixture 分别验证；不把 Ruby hook 能运行当作完整插件兼容。
- [ ] 修复 `script/differential`：列出所有归一化规则；对有语义的输出禁止排序/删除；安装文件树同时比较相对路径、文件内容、可执行权限和关键 symlink；lockfile 和 Gemfile 直接比较内容。
- [ ] 修复 `script/upstream-specs`：使锁文件族真实驱动 Celerite，退出码反映失败；保留当前 64 failures 作为失败基线，再逐项关闭。**代码进展（2026-11-10）：已移除 `|| true` 使 rspec 非零经 `pipefail` 传播（未重跑 rspec，64 failures 仍为既有记录）；“真实驱动 Celerite/失败基线逐项关闭”未完成。** 每次 re-pin 复核排除理由，不把 pending/未执行/调用参考实现记为通过。
- [ ] 建立 Rails 规模真实项目回归，记录所有有意兼容差异及理由；未解释差异为零后才恢复“该 profile 兼容”的声明。
- [ ] 更新 README、兼容报告、roadmap 和实际代码状态；历史报告标明对应 commit/工作树，不随新 fixture 静默改写旧结论。**（进行中，2026-11-10：compat-report/roadmap/README 已按 HEAD=8e91a2f 与本迭代脚本/文档变更做保守对齐，未重跑门禁的结果标未验证；需后续迭代持续同步。）**

验收：双 profile 单元/格式/差分门禁通过；锁文件上游族真实执行且结果如实；Ruby/平台约束和安装后只读命令有正反例；没有未声明的占位命令、恒真约束或无效配置。M8 的性能改动不得先于本阶段正确性修复合入。

### M8：批次桥接与无 Ruby 快路径

**目标**：减少进程启动、序列化和 Ruby 对象分配，不改变 M7 已验证的依赖选择与输出。

任务：

- [ ] 定义版本化、批次级求值协议：一次导出完整 dependencies、groups、source、autorequire、platform、Ruby 约束和插件声明；一次提交完整候选集并返回解，禁止在 PubGrub 循环中逐版本跨桥。
- [ ] 完成求值指纹：Gemfile/eval_gemfile、引用 gemspec、读取的 ENV、配置、Ruby/RubyGems/Bundler 版本与 ABI；任一输入变化必须使缓存失效，不使用内容哈希代替完整环境指纹。
- [ ] 同一求值复用 bridge，加入 idle 回收、协议超时、结构化错误和批量大小控制；统计一次命令的 Ruby 进程数、RPC 次数和传输字节数。
- [ ] 无变化 `lock`/`install` 直接使用 lockfile 和安装计划：不加载 Bundler、不启动 Ruby；有动态 DSL、插件或指纹不确定时显式走兼容路径。
- [ ] 实现持久化、版本化的解析/安装计划缓存，键包含 source 身份、凭据隔离标识、checksum、平台、Ruby ABI 和 build 配置；缓存损坏安全回退，不把未校验产物视为可用。
- [ ] 让 `check/list/show` 等只读命令复用已安装 gem 索引；为真实 Rails 规模冷/热/无变化运行建立性能对照，包含 Bundler + YJIT。

验收：无变化 lock/install 的 Ruby 启动次数为零（明确需要 Ruby 的 source/插件除外）；指纹失效有差分反例；缓存复用前后输出、依赖、文件内容与退出码一致；基准报告包含 wall/CPU/RSS、RPC 和 I/O，而不只是加速倍数。

### M9：原生安装计划与轻量 Ruby runtime

**目标**：消除 `.gem` 重复解析及完整 Bundler 运行时启动成本，同时保留必要的 Ruby 扩展边界。

任务：

- [ ] 下载时流式 SHA-256；Crystal 读取 `.gem` 容器、解出 `metadata.gz`，对可证明静态的 gemspec YAML 子集生成一次不可变安装计划。动态 gemspec、非标准 Marshal 或安全敏感边界显式回退 Ruby，不静默降级。
- [ ] 安装计划统一承载 spec 字段、依赖、executables、extensions、checksum、平台和文件操作；解包、binstub、installed-spec 和扩展构建共用计划，禁止同一 `.gem` 被多个 Ruby 调用重复读取。
- [ ] 流式 gzip/tar、逐文件路径/权限/大小检查、临时目录、原子 rename、失败清理；有界 Fiber worker 处理下载/校验/解包，扩展构建独立有序执行并传递 `build.<gem>`/target-rbconfig。
- [ ] Crystal 生成版本化 runtime manifest；小型 Ruby 适配层仅激活 gem、设置 load path 和执行 `Kernel.require`。逐步实现 `Bundler.setup`/`require`/`definition` 所需语义，避免无条件加载完整 `bundler/setup`。
- [ ] 为 `bundler/inline`、嵌套 exec、Ruby shebang、`disable_exec_load`、信号和退出码保留差分；公开 Ruby 对象未覆盖的部分继续使用明确的参考兼容路径。
- [ ] 基准覆盖 `bundle exec ruby app.rb`、直接 `ruby -r.../setup`、冷/热安装、原生扩展、失败恢复及磁盘写入；不能仅用 lock 解析微基准证明安装提速。

验收：常规 `.gem` 安装只需要一次元数据读取；原生扩展仍由真实 Ruby 工具链构建；目标 fixture 的 Ruby 应用无需完整 Bundler 即可加载，且安装文件内容/权限、运行结果和失败清理与参考一致。任何性能下降或兼容回归均阻止合入。

### M10：可选 Ruby 原生扩展嵌入 spike

**目标**：仅在 M8/M9 后证明独立进程边界仍是主要瓶颈时，评估在现有 `gem`/`Bundler` API 内嵌入 Crystal，而不是立即重写全部 RubyGems。

任务：

- [ ] 选择单个批量热点（例如整批 lockfile 解析、版本约束归一化或安装计划）做 spike；禁止逐 Ruby 对象/逐版本的细粒度 FFI 调用。
- [ ] 验证 Ruby C API、VALUE 生命周期与 GC 保活、异常跨边界、GVL/线程、Crystal runtime 初始化、Ruby ABI 和不同编译器/平台打包。
- [ ] 明确纯 Ruby fallback、feature detect、失败行为和分发方式；不默认替换用户的 RubyGems，不隐藏引擎选择。
- [ ] 对比独立进程、内嵌扩展和 Bundler + YJIT 的端到端 wall/CPU/RSS；把兼容维护、ABI 支持和分发成本纳入是否继续的决策。

验收：只有当端到端收益稳定、兼容测试不退化且 ABI/分发成本可接受时才进入正式实现；否则保留独立 Crystal + Ruby 适配层并记录否决原因。

## 首个可评审增量

1. 修复兼容报告、上游测试退出码与归一化声明，保留可复核的失败基线。**（进行中，2026-11-10 iteration 1：已推送既有 `8e91a2f`；`script/upstream-specs` 移除吞错 `|| true` 使 rspec 失败传播非零退出码，保留 64 failures 基线记录但未重跑 rspec；文档对齐 `ruby_requirement_satisfied?` 现状为“有版本检查实现/未达 M7(1) 验收”，快照项标未验证；diff/spec/differential 未重跑。）**
2. 用参考 Ruby 生成 Ruby/RubyGems 约束 oracle，实现候选过滤并覆盖不满足、平台变体和安装复核。
3. 修复安装后 `check/list/show`，再运行双 profile 全部检查。
4. 之后才实现 M8 的批次求值和完整指纹；每个阶段独立提交、独立 benchmark，不把正确性修复与大型性能重构混为一个变更。
