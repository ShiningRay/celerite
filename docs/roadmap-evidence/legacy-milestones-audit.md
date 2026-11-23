## 2026-11-24：M1–M5 遗留行审计（task-218）

审计对象：`docs/roadmap.md` 中 M1–M5 的全部未勾任务行。判定只以 `docs/compat-claims/` 的断言状态（已实现 / 已声明差异 / 未验证 / 未实现 / 已取代）为口径来源；M7 十一行全部勾选（2026-11-24）只作「M7 已收口」的前提，不自动把 M1–M5 的遗留行判为完成。本轮未跑 `script/differential`（本机另有全量差分占用端口 8765），也未跑 `crystal spec`；差分与套件结论一律按其采集日引用，不当作 HEAD 现状。

**口径更正：M1–M5 实际未勾 17 行**（L53、L65、L66、L67、L68、L81、L82、L92、L93、L94、L95、L96、L106、L107、L108、L109、L111），与派单所称「13 行」不符；本报告按逐条枚举的 17 行全审。

| 行号 | 里程碑 | 判定 | 一句话理由 |
| --- | --- | --- | --- |
| L53 | M1 | 可勾 [x] | 五类负向场景均有 spec 级判据，Ruby 不匹配另有差分级判据 |
| L65 | M2 | 不可勾（缺 4 项证据） | yank 全库零判据；预发布只有版本排序 unit；source 优先级仅已声明差异；engine/ABI 矩阵本机不可验证 |
| L66 | M2 | 不可勾（缺 1 项） | 稳定求值指纹无任何断言，随 M8 第二行未开工 |
| L67 | M2 | 部分达成，建议改写后勾选 | 差分夹具齐备，残留的 Ruby/ABI 跨宿主矩阵属已声明差异 |
| L68 | M2 | 可勾 [x] | Rails 规模锁逐字节比对 + 安装树差异全归因、未解释差异 0 |
| L81 | M3 | 不可勾（缺 2 项） | 信号边界与独立 runtime setup 均为已声明差异 |
| L82 | M3 | 不可勾（缺 1 项） | 磁盘错误已补齐，中断清理仍无 oracle |
| L92 | M4 | 不可勾（缺 1 项，本机不可验证） | submodule 两侧无可执行证据；tag/glob/离线回落已达成 |
| L93 | M4 | 不可勾（缺 1 项） | 完整本地变更失效指纹归 M8 |
| L94 | M4 | 本机不可验证 | Linux gnu/musl 与多 Ruby ABI 需其它宿主 |
| L95 | M4 | 部分达成，建议改写后勾选 | build args 与失败清理已达成，跨 ABI 隔离本机不可验证 |
| L96 | M4 | 本机不可验证 | CI 矩阵已配置但无运行记录入库；受支持 Ruby 仅 4.0 一档 |
| L106 | M5 | 不可勾（缺 1 项） | `doctor` 完整诊断面未实现（C-M7-3-031） |
| L107 | M5 | 不可勾（缺 2 项） | legacy 全量索引回退未实现、`--full-index` 未验证 |
| L108 | M5 | 可勾 [x] | 插件面断言已实现，五行有意差异已登记 |
| L109 | M5 | 不可勾（缺 3 项） | 公开 Ruby API、`bundler/inline`、插件可见对象均走参考 runtime |
| L111 | M5 | 部分达成，建议改写后勾选 | 64/45 口径成立，但「全部失败」已失真（19 passed） |

### L53 M1 负向测试（未知格式 / 无效版本 / 缺失 gem / Ruby 不匹配 / 权限错误）

- **判定**：可勾 [x]。括号内「权限错误与 Ruby 不匹配尚无完整证据」已过期，两项现均有判据（权限错误为 spec 级，见下）。
- **依据**：未知格式与无效版本——`spec/lockfile/parser_spec.cr` 的 `preserves unknown sections verbatim`、`marks lockfiles without known sections invalid`、`fails on malformed spec versions with position info`、`rejects merge conflicts`；缺失 gem——`C-M7-2-003`（已实现，`Could not find <full_name> in locally installed gems`，exit 7）；Ruby 不匹配——`C-M7-1-001`（已实现，exit 18，判据 `bash script/differential ruby-requirement-mismatch` 与 `spec/m7_ruby_runtime_enforcement_spec.cr`）；权限错误——`C-M7-5-024`（已实现，锁文件写出被拒 → `PermissionError` exit 23，`spec/m7_filesystem_errors_spec.cr`）、`C-M7-5-025`（已实现，文件系统错误分档映射，`spec/m7_filesystem_error_mapping_spec.cr`）。
- **建议陈述**：「对未知格式、无效版本、缺失 gem、Ruby 不匹配与权限错误做负向测试。（权限错误为 spec 级判据，只读锁文件形态无差分级夹具。）」
- **未验证**：只读锁文件形态在差分装具里不可表达（`C-M7-5-035` 边界），故权限错误无端到端差分取证；ENOSPC/EROFS 同样造不出。

### L65 M2 Ruby/RubyGems 约束、预发布、yank、source 优先级、cooldown

- **判定**：不可勾（缺 4 项证据：① yank ② 预发布的解析/锁场景 ③ source 优先级的独立判据 ④ engine/ABI/Gemfile 目标 Ruby 的完整矩阵）。括号内「预发布、yank 和 cooldown 已有场景」只在 cooldown 一侧成立。
- **依据**：已达成部分——`C-M7-1-002`/`C-M7-1-003`（已实现，required_ruby / required_rubygems 候选排除）、`C-M7-1-005`（已实现）、`C-cross-004`（已声明差异，`--cooldown` 只校验数值与主远程 per-source）。缺口：`yank` 在 `docs/compat-claims/`、`docs/compat-report.md`、`docs/roadmap-evidence/` 全目录零命中（`anked` 仅出现在 `docs/architecture.md` 的 fixture 覆盖要求里），即**无判据**；`预发布`/`prerelease` 在 claims 零命中，只有 `spec/m7_resolver_ruby_constraints_spec.cr` 的 `still honors prerelease-style gem requirements using RubyGems ordering` 与 `spec/m7_resolver_version_union_intersect_spec.cr` 的版本排除用例（纯排序，无解析与锁结果）；source 优先级无独立断言，只有 `C-cross-004` 的多源注入口径；完整 Ruby/ABI 矩阵为 `C-M7-1-015`、`C-M7-1-016`（均已声明差异）。
- **建议陈述**：「接入 Ruby/RubyGems 约束与 cooldown；预发布与 yank 仅有版本排序层判据，无解析与锁场景。」
- **未验证**：未读 `src/` 复核 yank 是否已有实现代码；本报告只断言「无判据」，未断言「未实现」。

### L66 M2 Gemfile bridge 求值、gemspec 求值与稳定指纹

- **判定**：不可勾（缺 1 项：稳定求值指纹）。
- **依据**：bridge 求值与 gemspec 求值已有覆盖——`C-cross-008`（已声明差异，Ruby 运行时经参考 `bundler/setup`，判据 `bash script/differential ruby-api`）、`C-M7-5-007`/`C-M7-5-008`（已实现，path 源默认三档 glob、按 gemspec 自身 name 匹配）；指纹无任何断言，`docs/compat-claims/` 检索「指纹」零命中，且 M8 的求值指纹行仍未勾选。
- **建议陈述**：「实现 Gemfile bridge 求值与 gemspec 求值；稳定指纹归 M8。」
- **未验证**：Gemfile 内容 SHA-256 之外的指纹缺口按 roadmap 原文与 M8 行判定，未读实现代码复核现状。

### L67 M2 `lock`、`install` 解析阶段、`update --conservative`、平台管理

- **判定**：部分达成，建议改写陈述后勾选。括号内「Ruby/平台约束完整验收在 M7」的欠账在 M7 已结为「已声明差异」，可写死进陈述而不再挂 M7。
- **依据**：夹具齐备——`fixtures/differential/` 的 `lock-file-pin`、`lock-file-unlock`、`lock-file-update`、`update-conservative`、`update-prefer-patch`、`multi-platform-lock`、`platform`、`platform-variant-fail`；断言——`C-M7-1-011`（已实现，platform 命令）、`C-M7-1-017`（已实现，`--ruby` 更新锁内 RUBY VERSION）、`C-M7-9-002`（已实现，锁按本地平台变体物化，判据含 `platform-variant-fail` 与 `multi-platform-lock`）；残留为 `C-M7-1-015`/`C-M7-1-016`、`C-M7-5-030`/`C-M7-5-031`/`C-M7-5-036`（已声明差异，多 ABI 本机不可验证）。
- **建议陈述**：「实现 `lock`、`install` 的解析阶段、`update --conservative` 与平台管理；Ruby/ABI 跨宿主矩阵记为已声明差异（多 ABI 本机不可验证）。」
- **未验证**：本轮未复跑这些夹具，PASS 结论取自 `docs/compat-report.md` 的 `## Current metrics` 及其采集日，不绑定 HEAD `3fd7a8d`。

### L68 M2 真实项目锁文件的解与 diff 回归

- **判定**：可勾 [x]。
- **依据**：`docs/roadmap-evidence/M7-9-rails-regression.md` 的「task-175 之后 rails 规模 install 的锁逐字节比对（task-179）」（`Gemfile.lock` 10663 字节 / 64 specs，SHA-256 已记录）；`C-M7-9-005`（已实现，rails 规模 install 不再把锁收缩成 1 条 spec）、`C-M7-9-009`（已声明差异，安装树集合级一致、27 处内容差异全部归因、未解释差异 0）；归一化规则逐条登记于 `C-M7-7-001`（已实现，N1–N10）。
- **建议陈述**：（不改；可在括号补「差异按 N1–N10 归一化规则登记，不静默忽略」）
- **未验证**：rails 规模夹具不入库，`C-M7-9-003`（已取代）边界明写「端到端无入库判据」，故该回归是一次性证据，不能在 HEAD 重跑为门禁。

### L81 M3 `exec`、runtime setup、`ruby -rbundler/setup` 适配

- **判定**：不可勾（缺 2 项：① 信号覆盖 ② 独立 runtime setup）。
- **依据**：`Kernel.load` 与 `disable_exec_load` 见 `C-cross-002`（已声明差异，判据 `bash script/differential exec-loader exec-loader-disabled exec-thor-version`）；runtime 见 `C-cross-008`（已声明差异，`ruby-api`，边界明写「不声称 Crystal 自带 Ruby API」）；信号见 `C-cross-001`（已声明差异，`bundle exec` 子进程在 Windows 共享控制台，INT/TERM 不随父进程）；`C-M7-5-035` 的 task-213 更新记 Crystal 在 Windows 上 `Signal::INT.trap` 抛 `NotImplementedError`。
- **建议陈述**：「实现 `exec`、runtime setup 与 `ruby -rbundler/setup` 适配；嵌套调用、退出码、`Kernel.load` 与 `disable_exec_load` 有差分；信号与轻量 runtime 记为已声明差异（Windows 无法捕获 INT，独立 runtime 归 M9）。」
- **未验证**：参考侧真实长 install 的 Ctrl-C 行为未取证（`docs/compat-evidence/2026-11-23.md` 的「M7-5 的磁盘错误 oracle 与 Windows 中断行为（task-213）」记连续投递未生效）。

### L82 M3 中断、磁盘错误、校验失败、无网络、重复安装、多进程竞争

- **判定**：不可勾（缺 1 项：中断与安装失败原子清理）。
- **依据**：磁盘错误已由 task-214 补齐为差分级——夹具 `install-lockfile-path-is-directory`（exit 32）与 `install-bundle-path-is-file`（exit 13）双 profile PASS、旧二进制负对照 FAIL，见 `C-M7-5-035` 的 task-214 更新与 `docs/compat-evidence/2026-11-23.md` 的「磁盘错误两形态的错误映射与退出码对齐（task-214）」；校验失败 / 重复安装 / 无网络见 `C-M7-5-019`/`C-M7-5-020`/`C-M7-5-021`（已实现）；锁互斥与并发串行化见 `C-cross-003`（已实现）；安装失败清理见 `C-M7-5-027`/`C-M7-5-028`（已实现，`spec/m7_install_failure_spec.cr`，只删 `specifications/<full>.gemspec`、cache 不留 `.gem`）。
- **建议陈述**：「验证磁盘错误、校验失败、无网络、重复安装与多进程竞争；中断清理记为已声明差异（Windows 无 INT 捕获）。」
- **未验证**：ENOSPC / EROFS / 只读锁文件形态无 oracle；中断侧参考行为只有源码锚点，无逐字输出。

### L92 M4 Git 源 branch/ref/tag/revision/submodule、缓存、锁 revision

- **判定**：不可勾（缺 1 项：submodule 端到端证据），该项本机双侧不可验证。
- **依据**：`C-M7-5-002`/`C-M7-5-003`（已实现；GIT 锁段顺序；`git-tag` 与 `git-glob` 双 profile PASS，task-211 更新见 `docs/compat-evidence/2026-11-23.md` 的「M7-5 收口与剩余声明的定性（task-211）」）；源身份含 uri/ref/branch/glob/submodules 见 `C-M7-5-005`（已实现）；离线回落见 `docs/compat-evidence/2026-11-23.md` 的「GIT 源失败时回落到缓存数据（task-155）」；submodule 见 `C-M7-5-004`（已声明差异，参考侧 git ≥2.38 拒 `fatal: transport 'file' not allowed`，双侧跳过）。
- **建议陈述**：「实现 Git 的 branch/ref/tag/revision/glob、缓存与锁 revision；submodule 记为已声明差异（本机双侧不可验证）。」
- **未验证**：submodule 需真实网络 URL 或装具级 `protocol.file.allow=always`，本机均未取得。

### L93 M4 path、gemspec、monorepo 与本地变更失效策略

- **判定**：不可勾（缺 1 项：完整本地变更失效指纹）。
- **依据**：`C-M7-5-007`（已实现，path 源默认三档 glob）、`C-M7-5-008`（已实现，按 gemspec 自身 name 匹配）、`C-M7-5-009`（已实现，glob 变化按可见 name/version 集决定是否重解）、`C-M7-5-033`（已实现，显式深层 glob）；多 gemspec 与 monorepo 见 `docs/compat-evidence/2026-11-23.md` 的「多 gemspec path 源的 cache/package 与显式深层 glob（task-187）」；失效指纹无任何断言，M8 的指纹行未勾。
- **建议陈述**：「实现 path、gemspec 与 monorepo 的解析/安装，并按 gemspec 的 name/version 集判定重解；完整失效指纹归 M8。」
- **未验证**：未读 `src/` 复核是否另有基于 mtime 或内容哈希的失效实现。

### L94 M4 平台专有 gem、多 ABI、锁平台规范化、离线 cache

- **判定**：本机不可验证（缺 2 项需其它宿主：Linux gnu/musl 的真实 ABI 行为、多 Ruby ABI；离线 cache 已达成）。
- **依据**：`C-M7-5-030`（已声明差异，gnu/musl 只到平台字符串归一）、`C-M7-5-031`（已声明差异，多 ABI 只在宿主 `x64-mingw-ucrt` 取证）、`C-M7-5-036`（已声明差异，本机仅 `ruby 4.0.6 [x64-mingw-ucrt]` 一套，`BUNDLER_REF_VERSION=2.7.2` 不改变 ABI）；锁平台规范化见 `C-M7-9-002`（已实现）与夹具 `multi-platform-lock`、`multi-platform-install`；离线见 `C-M7-5-019`/`C-M7-5-020`/`C-M7-5-021`（已实现）。
- **建议陈述**：「完成平台专有 gem 与锁平台规范化、离线 cache；Linux gnu/musl 与多 Ruby ABI 记为已声明差异（本机不可验证）。」
- **未验证**：真实离线缓存矩阵（真实 https 离线、`--local` + git 源、`--local` + `--frozen`、`BUNDLE_LOCAL` 设置项）见 `C-M7-5-019` 边界，未取证。

### L95 M4 经 bridge 执行原生扩展构建

- **判定**：部分达成，建议改写陈述后勾选（跨 Ruby ABI 隔离一项本机不可验证）。
- **依据**：`build.<gem>` 经桥传参见 `C-M7-4-027`（已实现，`spec/m7_build_args_spec.cr`）；失败清理见 `C-M7-5-027`/`C-M7-5-028`（已实现，`spec/m7_install_failure_spec.cr`）；racc 与 target-rbconfig 取证见 `docs/compat-evidence/2026-11-23.md` 的「M7-5 收口与剩余声明的定性（task-211）」；跨 ABI 隔离见 `C-M7-5-031`（已声明差异）。
- **建议陈述**：「经 bridge 执行原生扩展构建，复现 build args 与失败清理；跨 Ruby ABI 隔离记为已声明差异（本机无第二 ABI）。」
- **未验证**：`extensions/<platform>/<abi>/` 子目录形态未单独夹具断言（`C-M7-1-015` 边界）。

### L96 M4 macOS/Linux/受支持 Ruby 矩阵与 Windows 单列计划

- **判定**：本机不可验证（缺 3 项：CI 各组合的实跑证据、受支持 Ruby 多版本矩阵、Windows 单列实现计划）。
- **依据**：`.github/workflows/ci.yml` 已配置四宿主 job（`ubuntu-latest`、`macos-latest`、`macos-15-intel`、`windows-latest`）但 `ruby-version` 只有 `"4.0"` 单档；仓库内 `docs/compat-matrix/generated/` 只有本机生成的差分与上游报告（`differential-4.0.24-2026-11-11.md`、`upstream-lockfile-v4.0.24.md`、`cli-2.7.2.md`、`cli-4.0.24.md`），无 CI 运行记录；`C-M7-5-036`（已声明差异）记本机只一套 Ruby。
- **建议陈述**：「建立 macOS/Linux/Windows CI 矩阵并以运行记录佐证；受支持 Ruby 多版本矩阵与 Windows 单列实现计划随后补齐。」
- **未验证**：CI 是否已在远端执行、结果如何，本机无记录可查（未验证）；四宿主 job 的实际覆盖深度未核。

### L106 M5 内置命令、flags、alias、help、错误格式、配置持久化

- **判定**：不可勾（缺 1 项：`doctor` 完整诊断面；另 2 项为未验证与已声明差异）。
- **依据**：`C-M7-3-031`（**未实现**，`doctor` 的 home 权限、路径组件与 Gem path 规则未做，判据 `bash script/differential doctor-no-lockfile`）；`C-M7-3-021`（未验证，IRB 可用时的交互式 console）；`C-M7-3-033`（已声明差异，无手册页命令只渲染 usage 加 class options）；`C-M7-3-006`/`C-M7-3-014`/`C-M7-3-016`/`C-M7-3-018`/`C-M7-3-020`（已声明差异）。
- **建议陈述**：「完成内置命令、flags、help 与错误格式；`doctor` 诊断面、console 交互与 option 表记为未实现/已声明差异。」
- **未验证**：`alias` 与「配置持久化」在 claims 未找到独立断言（检索仅命中 `C-M7-3-015` 的 `gem` 问卷持久化），可能由斜杠命令夹具间接覆盖，但我未找到判据。

### L107 M5 Gemfile 任意 Ruby DSL 语义与全部 source 行为

- **判定**：不可勾（缺 2 项：legacy 全量索引回退、`--full-index` 语义）。
- **依据**：`C-M7-4-020`（**未实现**，紧凑索引不可用时无 legacy `specs.4.8.gz` 回退，判据 `bash script/differential install-platforms-add-local` 与 `spec/m7_forbidden_spec.cr`，边界明写「判据只作回归锚点，不能自证缺口」）；`C-M7-4-011`（**未实现**，紧凑索引 301/302/303/307/308 跟随不计数、无上限）；`C-M7-4-021`（未验证，`--full-index` 被白名单接受但无语义，现有 spec 未直接断言）；source 面见 `C-M7-4-001`（已实现）至 `C-M7-4-019`（已声明差异）区间，以及 `C-M7-6-019`、`C-M7-6-026`（均已实现）所在的插件 source 族。
- **建议陈述**：「完成 Gemfile 任意 Ruby DSL 语义与 source 的 mirror/proxy/SSL/鉴权行为；legacy 全量索引回退与 `--full-index` 记为未实现/未验证。」
- **未验证**：Gemfile DSL 的「任意 Ruby 语义」无单独断言，只由求值夹具与 `C-cross-008` 边界间接覆盖。

### L108 M5 插件安装、index、命令分发、hook、自定义 source、PATH fallback

- **判定**：可勾 [x]。
- **依据**：命令索引与分发 `C-M7-6-001`/`C-M7-6-002`/`C-M7-6-029`（已实现，含 PATH 上 `bundler-<name>` 兜底）；生命周期 hook `C-M7-6-009`…`C-M7-6-013`（已实现）；自定义 source `C-M7-6-019`…`C-M7-6-027`（已实现，含真实打包第三方插件 gem 的端到端 `C-M7-6-026`）；安装与 index `C-M7-6-028`/`C-M7-6-034`/`C-M7-6-036`/`C-M7-6-038`（已实现）；五行有意差异 `C-M7-6-014`、`C-M7-6-039`、`C-M7-6-040`、`C-M7-6-041`、`C-M7-6-042`（已声明差异）。
- **建议陈述**：（不改）
- **未验证**：第三方插件生态只做抽样（`C-M7-6-039` 边界），不代表全生态。

### L109 M5 公开 Ruby API、`bundler/inline`、插件可见对象

- **判定**：不可勾（缺 3 项：公开 `Bundler` Ruby API 面、`bundler/inline` 适配、插件可见对象）。
- **依据**：`C-cross-008`（已声明差异，Ruby 运行时场景走参考 `bundler/setup`，判据 `bash script/differential ruby-api`，边界明写「不声称 Crystal 自带 Ruby API」）；`inline` 在 `docs/compat-claims/` 零命中；第三方插件 fixture 存在（`C-M7-6-026`/`C-M7-6-038`）但都在参考 runtime 之上。
- **建议陈述**：「在参考 Bundler runtime 上提供插件可见对象与第三方插件 fixture；公开 Ruby API 与 `bundler/inline` 归 M9。」
- **未验证**：是否存在独立 Ruby 适配层代码未读 `src/` 复核；本报告只断言无判据。

### L111 M5 运行适用的上游 Bundler suite

- **判定**：部分达成，建议改写陈述后勾选。当前口径仍是 **64 examples / 45 failures**（19 passed；桶 `env:out-of-process-artifice` 44 / `fixture:fetch-failed` 1 / `env:low-il-shm` 0 / `product:candidates` 0，2026-11-23 task-193 复采，2.7.2 profile 未复采），但原文「现存 64 例记录全部失败」已失真。
- **依据**：`docs/compat-report.md` 的 `## Current metrics` 与 `## Upstream spec suite coverage boundary`（三条基线并列，45 failures 为当前权威值）；覆盖边界仅 lockfile 家族见 `C-M7-8-004`（已声明差异，`script/upstream-specs` 固定 `v4.0.24` revision）；`C-M7-8-021`（已实现，task-193 复采后 product 候选为 0）；逐条定性见 `docs/roadmap-evidence/M7-8-upstream-specs.md` 的「50 条失败的逐条定性与分桶改名（task-193）」；复审与口径统一见 `docs/compat-evidence/2026-11-23.md` 的「M7-8 行闭合判据复审（task-205）」与「M7-8 口径统一与陈述改写（task-209）」。
- **建议陈述**：「运行适用的上游 Bundler lockfile 家族 suite（固定 v4.0.24 revision），逐项记录例外并复审确认；当前基线 64 examples / 45 failures（19 passed，env 桶 44+1，product 候选 0），不是绿色上游测试。」
- **未验证**：「由评审确认」未找到具名评审记录，只有 task-205 的闭合判据复审与 task-209 的口径统一；`C-M7-8-016`（未验证）记 2.7.2 profile 未复采；45 failures 未在 HEAD `3fd7a8d` 重跑。

### 审计自身的边界

- 未执行 `script/differential`（端口 8765 被本机另一全量差分占用）与 `crystal spec`，所有差分/套件 PASS 均按其采集日引用，**不绑定本次工作树的 HEAD `3fd7a8d`**。
- 判定以 claims 状态为准；claims 的「判据失效即降级为未验证」规则（`docs/compat-claims/README.md`）意味着凡判据文件在 HEAD 被改名或删除，上述「已实现」需重新取证 —— 本轮只核了判据文件存在性于我引用到的几个 spec（`parser_spec.cr`、`m7_filesystem_errors_spec.cr`、`m7_filesystem_error_mapping_spec.cr`、`m7_install_failure_spec.cr`、`m7_build_args_spec.cr`、`m7_installed_discovery_spec.cr`、`m7_resolver_ruby_constraints_spec.cr`），未全量核 259 条断言。
- 未读 `src/` 实现代码，故「无判据」不等同「未实现」；两者在逐行文字中已分开表述。