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
- [ ] 接入 Ruby/RubyGems 约束、预发布、yank、source 优先级和 cooldown。（预发布、yank 和 cooldown 已有场景；索引已读取 required Ruby/RubyGems 字段，但 `ResolutionSource#ruby_requirement_satisfied?` 当前恒为 true，约束过滤在 M7 重新打开。）
- [ ] 实现 Gemfile bridge 求值、gemspec 求值与稳定指纹。（桥求值已实现；目前仅 Gemfile 内容 SHA-256，不含 ENV、引用 gemspec、配置和 Ruby 环境的完整指纹，M8 继续。）
- [ ] 实现 `lock`、`install` 的解析阶段、`update --conservative` 和平台管理。（`lock-file-pin/unlock/update`、`update-conservative`、`multi-platform-lock`、`platform` 差分双 profile 通过；Ruby/平台约束完整验收在 M7。）
- [ ] 用真实项目锁文件做解与 diff 回归，不将结果差异常化忽略。（真实 Bundler 锁 fixture 字节往返和锁驱动差分已做；Rails 规模真实项目回归在 M7。）

验收：**未完整通过**。常规小夹具已验证，但 Ruby/RubyGems 约束、Rails 规模与真实网络/平台边界未关闭。

## M3：安装、缓存与运行时

**目标**：常规 rubygems.org 项目能真实安装并启动。

任务：

- [x] 实现 gem 下载、SHA-256 校验、内容寻址缓存与并发去重。（`spec/downloader_spec`（下载/hex 校验）+ `install-fresh/install-rerun` 差分。）
- [x] 实现 gem package 读取、原子安装、specification、executables 和 binstubs。（安装树差分随各 fixture 双 profile 落地。）
- [x] 实现 `install`、`cache`/`package`、`clean`、`pristine`、`binstubs` 的相关路径。（`install-fresh`、`pristine({,-named})`、`git-pristine`、`clean-unused` 差分覆盖 Rubygems/Git/path 的重装与清理语义（双 profile）；`cache` 由 `install` 后 `vendor/cache` 检查复核路径。）
- [ ] 实现 `exec`、runtime setup 与 `ruby -rbundler/setup` 适配；覆盖嵌套调用、信号、退出码、Ruby shebang 的 `Kernel.load` 和 `disable_exec_load`。（已有参考 Bundler runtime、Ruby `Kernel.load` 和退出码场景；轻量独立 runtime 属 M9，Windows 信号边界未关闭。）
- [ ] 验证中断、磁盘错误、校验失败、无网络、重复安装及多进程竞争。（校验失败、重复安装、无网络和锁互斥已有测试；磁盘错误、中断及安装失败原子清理未完整验证。）

验收：**未完整通过**。最小应用与原生扩展 fixture 可运行；Rails 规模、完整安装树内容比较、独立 runtime 和故障注入在 M7/M9 继续。

## M4：所有内置 source、平台与扩展

**目标**：超出纯 Ruby、单一 rubygems.org 的简单场景。

任务：

- [x] 实现 Git 的 branch/ref/tag/revision/submodule、缓存和锁 revision。（`git-path-install`（branch 源 + revision 锁）与 `git-pristine`（重物化）差分通过；ref/tag/submodule 走既有 Git 编排，fixture 仅覆盖 branch 形态。）
- [x] 实现 path、gemspec、monorepo 与本地变更失效策略。（`git-path-install` 的 gemspec path 源与本地依赖安装差分通过。）
- [x] 完成平台专有 gem、多 ABI、锁平台规范化、离线 cache。（`multi-platform-lock`、`platform` 差分 + `lock-file-update`（平台规范化）通过；平台专有 gem 二进制安装在多平台 CI 矩阵下持续验证。）
- [x] 经 bridge 执行原生扩展构建，复现 build args、Ruby ABI 隔离和失败清理。（`native-ext` fixture（racc 原生扩展编译并加载）双 profile 通过；失败清理路径经 bridge build_extension 错误面覆盖。）
- [x] 建立 macOS/Linux 和受支持 Ruby 矩阵；评估 Windows 后单列实现计划。（CI specs/differential/gem-package 三平台矩阵（ubuntu/macos/windows）+ 本机 Windows（msvcrt/mingw）二进制已验证；Windows 支持不再单列为未评估项。）

验收：跨平台 lock/install 差分通过；至少一个原生扩展 gem 编译、加载和重装成功。

## M5：CLI、插件与 Ruby API（部分实现，完整兼容验收转入 M7）

**目标**：覆盖用户所选“完整产品兼容”，不只常规安装。

任务：

- [ ] 完成所有内置命令、flags、alias、help、错误格式和配置持久化。（命令入口较多，但 `check/list` 的安装后路径、`fund`、完整 `gem` 模板、重试和若干配置并未完整生效；以 M7 和 compat-report 为准。）
- [ ] 完成 Gemfile 任意 Ruby DSL 语义和全部 source 行为。（Gemfile 经真实 `Bundler::Dsl` 求值；source 的 mirror/proxy/SSL/legacy index 和插件 source 完整边界未关闭。）
- [ ] 实现插件安装/index、命令分发、生命周期 hook、自定义 source 和 PATH fallback。（安装/index/hook 和部分远端/Git 路径已实现；插件命令注册、自定义 source 与第三方插件生态需要实证。）
- [ ] 实现公开 `Bundler` Ruby API 与 `bundler/inline` 适配及插件可见对象；建立第三方插件 fixture。（当前 fixture 通过真实参考 Bundler runtime 运行，不代表独立 Ruby 适配层已实现。）
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

## 第一阶段建议

下一步从 M0 开始，先实现差分 harness 和 Gem::Version/Gem::Requirement 的语义验证。不要先写下载器或 CLI 外壳来堆积“支持命令数”。

首个可评审增量应包含：固定参考版本、5 类基础 fixture、lockfile AST、只读 parser 与一组可重复的 Bundler 差分结果。
