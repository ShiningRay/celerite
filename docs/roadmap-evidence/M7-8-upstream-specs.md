# M7(8) script/upstream-specs 与锁文件族真实驱动

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 161 -->

**代码进展

（2026-11-10）：已移除 `|| true` 使 rspec 非零经 `pipefail` 传播（未重跑 rspec，64 failures 仍为既有记录）；“真实驱动 Celerite/失败基线逐项关闭”未完成。** **证据进展

（2026-11-13，HEAD 链 e5b35ec/93716bd/4d110ae/254e493）：setup 已解锁（预置 `pristine_system` 后 `helpers.rb:528` ENOENT 消失），锁文件族已在例内真实驱动 Celerite（trace 57 次调用）；实测 `64 examples, 55 failures`（9 通过，exit 1，两 run 失败集合一致）；55 失败分类：环境 39 / 夹具 12 / 产品差异 4 / shim 未覆盖 0；4 条产品差异已有断言级证据，M7(8) 尚不能宣称完成（逐条分类见 `docs/compat-matrix/generated/upstream-lockfile-v4.0.24.md` D/D2 节）；D2 纠正

（2026-11-14）：D 轮 SSL 32 为陈旧二进制假象，当前 HEAD 重建后重跑仍为 `64 examples, 55 failures`（9 通过，seed 35224，57 次 celerite 调用），SSL 归零、形态变为 DNS 31 + HTTP 403 1（进程内网络桩/出口策略，harness 限制，非产品差异），四桶分布不变 39/12/4/0，重建纪律与命令见上游文档 D2 节）。** **G 轮

（2026-11-14，HEAD=ff66c83 链）：exe 位于仓库树内（bin/ 等）被环境策略禁写，②③ 归环境（非产品）；仓库外二进制重跑 harness 64 examples/53 failures/11 pass（seed 31121，Commands ×16 真实驱动 celerite）；四桶 环境 36/夹具 12/产品 5/shim 0；产品差异新增 #27 bridge autorequire 数组形态解析缺陷（`Couldn't parse (String | Nil) from ["myrack/obama"]`），4 条内容差异与 D2 同例同形；M7(8) 仍不能宣称完成（逐条见上游文档 G 节）。** 每次 re-pin 复核排除理由，不把 pending/未执行/调用参考实现记为通过。 **M7(8) 进展注记

（2026-11-14，HEAD=93e7df9 链）：例内真实驱动 64 例、11 通过、53 失败（环境 36 / 夹具 12 / 产品 5）——G2 轮实测（seed 31121，57 次 celerite 调用）。产品 5 条：① stores relative paths when the path is provided in an absolute fashion but is relative（期望 remote: foo，实得绝对路径，未 relativize）——

**2026-11-15 已实现（M7(8) 产品差异①）**：`Resolution#generated_lockfile` 的 PATH 段 remote 改为经私有 `lockfile_path_for` 归一（项目内绝对路径→相对 Gemfile 目录、相对保持相对、项目外绝对保持绝对、统一 `/` 分隔且无前导 `./`，分组 key 同用归一值），语义锚点 `bundler-4.0.24/lib/bundler/source/path.rb:136-139` 与 `:210-215`，上游用例 `lockfile_spec.rb:1154`（`expected "PATH\n  remote: foo\n"`）；`spec/m7_path_lockfile_relative_spec.cr` 4 examples 0 failures（修复前实测 3 failures），本轮 format --check/build --no-codegen/全量 spec 见 `docs/compat-evidence/2026-11-15.md` 对应节；复选框保持未勾（其余产品差异 ②③④⑤ 未动）。

**2026-11-15（M7(8) 产品差异②）：锁文件 `specs:` 为空/依赖边缺失时强制重解析**——`Resolution#reuse_locked_resolution?` 新增私有谓词 `lockfile_covers_dependencies?`（每个顶层依赖须有锁定 spec；每条锁定依赖边须指向已锁定且满足 requirement 的版本，等价 `definition.rb:630-645` 的 `@missing_lockfile_dep`/`@locked_spec_with_missing_deps`/`@locked_spec_with_invalid_deps`，锚点 `definition.rb:973-1014,1051-1076`，上游用例 `lockfile_spec.rb:1882`）；`spec/m7_lockfile_regen_spec.cr` 4 examples 0 failures（修复前实测 2 failures：空 specs 与缺边均误判可复用），全量 276 examples 1 failure（仅既有 `spec/config_spec.cr:97`），格式/build/门禁与覆盖见 `docs/compat-evidence/2026-11-15.md`「M7(8) 第二子项」节；复选框保持未勾。② regenerates a lockfile with no specs（期望 direct_dependency 4.5.6 + indirect_dependency 1.2.3，实得空 specs:）——

**2026-11-15 已实现（M7(8) 产品差异②），见上方注记**；③ refuses to install if Gemfile.lock contains conflict markers（期望 /Your Gemfile.lock contains merge conflicts/i，实得消息在「Your」与「Gemfile.lock」间插入绝对 Windows 路径，exit 20 正确）——

**2026-11-15 已实现（M7(8) 产品差异③）**：`Lockfile::Parser` 新增私有 `display_lockfile_path`，消息里的 lockfile 路径按 `SharedHelpers.relative_lockfile_path`（`lockfile_parser.rb:105-109`，即 `Pathname#relative_path_from(Dir.pwd)`）显示为相对形式并以 `/` 分隔（同目录 `Gemfile.lock`、子目录 `sub/Gemfile.lock`、父目录 `../Gemfile.lock`；跨盘/UNC 无法相对化时回退原绝对路径，等价上游 `rescue ArgumentError`），冲突消息与 unreadable 消息同用一个值；`Lockfile::Data#lockfile_path` 未改，退出码仍为 20；`spec/m7_lockfile_conflict_spec.cr` 5 examples 0 failures（修复前实测 4 failures，负对照见 `docs/compat-evidence/2026-11-15.md`「第三子项」节）；复选框保持未勾；④ automatically fixes the lockfile when it has incorrect deps, keeping the locked version（期望 net-smtp 0.5.0 嵌套 net-protocol 依赖边，实得缺失）；

**2026-11-15（M7(8) 产品差异④）：已实现**——`Resolution#refresh_locked_dependencies` 在复用路径下用本次取到的 `.gem` 的真实 runtime gemspec 依赖重建 `ResolvedSpec.dependencies`（仅 GEM、仅边集合变化时重建，其余字段原样；PATH/GIT 与 fresh resolve 不刷新），`commands_install.cr` 在写锁文件前调用（`bridge.read_gem_spec`，无新增网络请求），锁定版本保持不变；语义锚点 `spec_set.rb#materialize` 与上游 `lockfile_spec.rb:2088-2142`（Bundler 的 `LazySpecification` 不携带依赖边，`check_lockfile` 看不到该差异）；`spec/m7_lockfile_locked_deps_spec.cr` 2 examples 0 failures（修复前实测 1 failure：锁文件缺 `      net-protocol` 边），负对照与门禁见 `docs/compat-evidence/2026-11-15.md`「第四子项」节；复选框保持未勾；⑤ #27 does not add the :require option to the lockfile（原崩溃 Couldn't parse (String | Nil) from ["myrack/obama"]，93e7df9 已修：client.cr 类型 Array(String)|Nil + 离线 spec 6/0/0 EXIT 0；上游单例修复后转环境 DNS 失败，该例本轮仍未验证）。修复后产品差异 5→4（#27 转环境类）；全量 64 例本轮未用修复后二进制重跑（未验证），单例重跑证据见 `docs/compat-evidence/2026-11-14.md` #27 节。；L 重跑

（2026-11-14，二进制含 K/K'/K''，HEAD=7ad5bb1 之上）：例内真实驱动 64 例、11 通过、53 失败（环境 37 / 夹具 12 / 产品 4 / shim 0，加总=53），#27 已修转 env-DNS，4 项产品差异按名称列于 `docs/compat-evidence/2026-11-14.md` L 节（编号 #12/#30/#33/#44 映射未确认）；make 入 PATH 不影响本轮计数（0 例达原生构建）。** 

**2026-11-16（L161 第一步：真实驱动 + 自动分桶）**：`script/upstream-specs` 现在**默认**加载 `script/upstream-specs-celerite-override.rb`（`CELERITE_BUNDLE_HELPER_OVERRIDE=0` 退回基线），报告新增 `real-drive: <n> celerite invocations`（0 时显式打印 `WARNING: NOT driving celerite`）与自动失败分桶（`env:artifice-unreachable` / `env:network-policy` / `env:low-il-shm` / `env:test-deps-skipped` / `fixture:missing-gem-files` / `fixture:fetch-failed` / `product:candidates`），并把 rspec JSON formatter 落盘为 `.upstream-specs/rspec-output.json` 供分类。首辅实测：默认真实驱动 `64 examples, 55 failures`（9 通过，**48** 次 celerite 调用；桶 34/1/8/11/1、**product 0**）；基线 `64 examples, 62 failures`（real-drive 0、桶 50/12）。产品差异 ①③④ 对应的上游用例 `:1154` / `:2410` / `:2436` / `:2088` 本轮已通过；`:1882` 仍被进程内 artifice `gem.repo4` 阻塞（harness 限制，差分夹具 `lock-missing-dependency-edges` 双 profile PASS 覆盖）。

**2026-11-19（task-23 补记）：已定位 11 例缺失 gem 文件为夹具毒化——`build_repo1` 在缺 rake 缓存时以 nil 的 `rake_path` 抛 TypeError，`build_repo` 已建的 `remote1/gems` 留下空壳且后续早退，`build_repo2` 复制空仓（`builders.rb:31`、`path.rb:322-324`）。`script/upstream-specs` 已在 rspec 前清理空 remote1 并用本机 rake 播种 `tmp/gems/base`；从毒化状态复跑 64 例：54 失败（artifice 37 / low-il 8 / fetch 6 / product 3），`fixture:missing-gem-files` 归零，11 例去向 9 artifice、1 low-il、1 product（CHECKSUMS 缺 sha256）。仅 4.0.24，v2.7.2 未跑。** 复选框保持 `[ ]`（环境 44 + 夹具 12 未清零，`install_test_deps` 完整链未跑，`:1882` 无断言级证据）。 

**2026-11-19（task-25 补记）：空/缺失 CHECKSUMS 条目现触发远程重解析并回填 `sha256=`（`src/celerite/definition.cr:362 checksums_need_refresh?`；`commands_install.cr` 据此关闭锁复用并在 4.x 抑制 `Resolving dependencies...`；`commands.cr` 的 lock no-op 放行）。4.0.24 锁文件回填 `bundler (4.0.24)` 自校验行、install 不打印 `Resolving dependencies...`；2.7.2 不写该行且 install 保留 `Resolving dependencies...`；差分 `checksums-empty-install`/`checksums-empty-lock` 双 profile 均 PASS。声明差异：`lock --local` 与 frozen 文案未取参考 oracle、bundler 自校验依赖本机 gem 缓存、`file:` 源清空校验和保持既有行为。环境桶未清零，复选框保持 `[ ]`。** 

**2026-11-19（task-26 补记）：`lock --add-checksums` 计算路径已对齐——4.0.24 从安装缓存/下载 gem 计算 sha256 并回填（含 bundler 自校验行），2.7.2 只写空 CHECKSUMS 段；frozen 空条目两条命令均 exit 16 且锁不变；差分 `lock-add-checksums`/`lock-add-checksums-frozen` 双 profile PASS。复选框保持 `[ ]`。** 

**2026-11-19（task-30 收口）：当前上游基线为 64 examples / 54 failed（10 passed；artifice 37 / low-il 8 / fetch 6 / product 3，见 task-23 节）；`.upstream-specs/rspec-output.json` 采集时点早于 task-25…29，product 候选「空 CHECKSUMS sha256」疑已被 task-25 消除但未复跑确认（未确认）。复选框保持 `[ ]`。** 

**2026-11-19（task-32 补记）：二次重采集为 64/54（10 passed；artifice 38 / low-il 8 / fetch 6 / product 2，real-drive 58），product 候选 3→2 但 ① 只是移入 artifice（`gem.repo2` 进程内不可达）而非修复；② git tag 选错（v4.0.7 vs v4.0.8）、③ 缺本地平台补全为真产品候选，仅回报未修。复选框保持 `[ ]`。** 

**2026-11-19（task-33 补记）：③ 非 frozen 自动补本地平台已修（`validate_platforms!` 非 frozen 放行，install/check 写回 `PLATFORMS`；frozen 保持参考三行文案/exit 16），差分 `install-platforms-add-local`/`install-platforms-frozen-error` 双 profile PASS，旧二进制反假绿 FAIL；上游 `lockfile_spec.rb:1222` 仍被 artifice `gem.repo2` 阻塞，未复跑通过，故上游基线仍记 64/54、product 候选 2→1（② 保留）。复选框保持 `[ ]`。** 

**2026-11-19（task-34 补记）：Git/PATH/Plugin source 标签改为 Gemfile↔锁逐依赖比较（GIT 补 submodules、PATH 补 glob、Plugin 补 type），source 变化时禁用锁复用并排除旧锁定项，`lock` 的 no-op 分支也要求 source 未变。构造态（锁 v4.0.7、Gemfile v4.0.8）参考 4.0.24 已 bump；旧 Celerite 锁原样，修复后进入解析并尝试 clone，但本机 msys sh `0xC0000022` 阻断端到端；反假绿 spec 在 b350607 上 3/4 失败。上游 `lockfile_spec.rb:658` 未复跑，故上游基线仍 64/54，② 的真实状态是「判据已修、构造态参考已 bump、我方端到端与上游单例未验证」，不宣称上游通过。** 

**2026-11-19（task-39 漂移校正）：更早的“55 failures（9 通过）”是首测历史，当前为 54 failures / 10 passed；task-32 于 2026-11-19 16:32 采集的分桶为 38/8/6/2（37/8/6/3 属 task-23 历史）；空 CHECKSUMS 例已确认转 env:artifice `Could not reach host gem.repo2`，product 候选仍为 2（②、③ 未复跑）。复选框保持 `[ ]`。** 

**（2026-11-20：task-53…60 未复采上游；最近一次仍为 task-32 的 2026-11-19 16:32 采集。）** 

**2026-11-20（task-66 复采）：64 例 / 53 失败 / 11 通过，桶 artifice 38 / low-il 9 / fetch 6 / product 0；候选 ② 落 low-il、③ 落 artifice（旧平台门禁报错已消失）、① 仍 artifice；新增通过 \serializes pinned path sources to the lockfile even when packaging\；三桶属宿主条件，本机不可转绿。** 

**2026-11-21（task-86 三次复采）：HEAD `710e06e` 下 64 examples / 53 failures / 11 passed（task-66 为 64/53/10），逐 example 零变化（`CHANGES=0`），分桶 artifice 38 / low-il 9 / fetch 6 / product 0；6 条 fetch 桶里 3 条（`[1:2]`/`[1:3]`/`[1:5]`）是沙箱无 CA 的 SSL 环境噪声，另 3 条（`[1:51]`/`[1:56:1:1]`/`[1:57:1:1]`）是 `missing dependent specs auto-heals` 的产品候选、被「文本含 `Fetching `」的分桶规则误归夹具桶。** 

**2026-11-21（task-91 补记）：上游套件分桶改为按异常类判定（环境特征优先、`RSpec::Expectations::ExpectationNotMetError` 一律 product），离线重算 task-86 产物得「artifice 38 / low-il 9 / fetch 3 / product 3」，product 候选由 0 变 3，总例数与失败数不变；三条候选均为锁体断言（`missing dependent specs auto-heals` 族），未重跑套件。** 

**2026-11-21（task-92 补记）：三条 product 候选中「frozen 语义」已对齐（BUNDLE_FROZEN=true install 现在 exit 41 + Bundler found incorrect dependencies in the lockfile for net-smtp-0.5.0，并把桥/锁两侧 ile: remote 拼写归一后不再误报 exit 16）；「非 frozen 自愈」仍未对齐——我方走锁刷新、只一条 Resolving dependencies...、只装一个 gem，且锁里会出现依赖边而缺 spec 行（当前缺陷，见 `docs/compat-evidence/2026-11-21.md` 对应节）。同夹具下 lock 补平台行、install --local 的 exit 7 均未修。复选框保持未勾。** 

**2026-11-21（task-94 补记）：非 frozen 的锁依赖表失配已按 `definition.rb:699-708` 的 `reresolve_without` 自愈（`install` 打印两条 `Resolving dependencies...`、补齐 `net-protocol (0.2.2)` 行并真正安装），`lock` 仍只补本地平台、不补依赖边；`lock` 的 no-op 短路改为要求 `PLATFORMS` 含本地平台。已声明：`lock` 的依赖边仍由我方生成器从索引写入，`update` 未接入自愈。** 

**2026-11-22（task-114 补记）：第四次复采上游 lockfile 套件（HEAD `b2f5f88`，349 s，seed 31786）：总数仍 64/53，但分桶移动两处——`[1:51]` 转绿退出失败集，`[1:46]` 由 env 桶移入产品桶（命令已跑通，锁内 CHECKSUMS 缺 `myrack` digest），`[1:54]` 新增进失败集（自愈未保持锁定版本 `net-smtp 0.5.0`，被升到 0.5.1）；产品候选 3→4，env artifice 38→37、low-il 9、fetch 3 未变。详见 `docs/compat-evidence/2026-11-22.md` 对应小节。** 

**2026-11-22（task-115 补记）：锁依赖边自愈不再把行推入 `@unlock`，`net-smtp` 保持锁定 0.5.0 并补回 `      net-protocol` 边（S1/S2 一行 `Resolving dependencies...`、S3 两行）；差分与 spec 双 profile 通过，负对照旧二进制升到 0.5.1。宿主 gem 可见形态下我方多打 2 行 `Resolving dependencies...`，未夹具化，见 `docs/compat-evidence/2026-11-22.md` task-115 节。** 

**2026-11-22（task-116 补记）：CHECKSUMS 段「缺行」（不是空值）时参考会真解析并打印 `Resolving dependencies...`，我方原先把两种成因合成一个布尔、一并静默；现按成因分流（Missing 打印 / Empty 静默），新夹具 `checksums-refresh-cache-deleted` 双 profile 通过，负对照旧二进制在 4.0.24 缺该行（2.7.2 本来就打印）。见 `docs/compat-evidence/2026-11-22.md` task-116 节。** 

**2026-11-22（task-117 补记）：`lock` 在「锁定 spec 行缺失但依赖边仍在」时不再静默 no-op——按参考 `definition.rb:973-1015 check_lockfile`（`spec_set.rb:87-96 validate_deps`）的 `:missing`/`:invalid` 判定剔除不完整锁定行，候选、preferred version 与 `>= locked` 下限同时消失，于是重解析并升级到索引里的 0.5.1；两行齐备（含边缺）形态保持 no-op。新夹具 `lock-missing-locked-spec-line` 双 profile PASS，`spec/m7_lock_missing_spec_row_spec.cr` 3/0，见 `docs/compat-evidence/2026-11-22.md` task-117 节。** 2026-11-22（task-118 补记）：第五次复采上游 lockfile 套件（HEAD `e71ed06`，483 s，seed 16550）：64 例不变，失败 53→48、通过 11→16；桶 artifice 37→40、low-il 9→2、fetch 3→3、product 4→3。转绿 5 例中 `[1:54]`（`spec/lock/lockfile_spec.rb:2088`）可归因 task-115 修复（自愈保持锁定版本），`[1:12]`/`[1:14]`/`[1:15]`/`[1:55]` 为 msys Low-IL 环境波动；`[1:20]`/`[1:52]`/`[1:53]` 由 low-il 移入 artifice（状态仍 failed）；产品候选 `[1:46]`/`[1:56:1:1]`/`[1:57:1:1]` 消息逐字节未变。见 `docs/compat-evidence/2026-11-22.md` task-118 节。 

**2026-11-22（task-120 补记）：`--local` 且锁已存在时不再无条件复用锁定 spec 集合——`resolve!` 的早返回条件加 `lockfile_covers_all_dependencies?`（`src/celerite/resolution.cr:1077`/`:1324`），Gemfile 新增、锁里完全没有的依赖（thor）不再被静默丢弃，改按参考由 local-only source 报 `Could not find gem 'thor' in locally installed gems.` 并 exit 7、不写锁；参考锚点 `definition.rb:190 setup_domain!`/`:342 resolve`/`:1051 converge_dependencies` + `resolver.rb:334`。新夹具 `install-local-new-dep-not-installed`（`bundle-preset/` 为最小合成预置：`specifications/json_pure-2.8.1.gemspec` + `gems/json_pure-2.8.1/lib/celerite_fixture.rb`，无真实 gem 树与 cache 包）双 profile PASS，`spec/m7_local_install_missing_dep_spec.cr` 3/0；反假绿：`21fb01f` 旧二进制 0 passed / 1 failed（`8b1e0df` 结果同）；差分回归 4.0.24 54/0/0、spec 家族 32/0/0。`update --local` 同形分歧亦被同一修复消除（手工 A/B，无常驻夹具）。见 `docs/compat-evidence/2026-11-22.md` task-120 节。复选框保持 `[ ]`。**

<!-- 原 roadmap.md 行 166 -->

**2026-11-15（M7(8) 第五子项）：两条产品差异的 differential 固化

**（补记 2026-11-15：装具修复后双 profile 全量基线 4.0.24=`121 passed, 15 failed, 2 skipped`、2.7.2=`119 passed, 16 failed, 3 skipped`；A 双 profile PASS，B 仍为 documented SKIP（

**2026-11-15 第六子项已修复：修复路径改为缓冲 `Fetching`/`Installing` 事件，`refresh_locked_dependencies` 返回 Bool 决定是否先打印两行 `Resolving dependencies...`，2.7 profile 按 gem 成对刷出；B 双 profile PASS，4.0.24 全量 `129 passed, 13 failed, 1 skipped`、2.7.2 `129 passed, 12 failed, 2 skipped`，13 失败仍为 msys `0xC0000022` 环境类**）此前「58 失败、根因产品 `Commands.word_wrap`」的结论已撤回：真因是 `script/differential` 在同一输出文件上第二次 `>>` 复开时写偏移归零、后一命令覆写前一命令输出（`install-check` 首行变成 check 的 40 字节行）；修复为每命令独立 `ref.part.$n.out`/`cel.part.$n.out` 后单次 `cat a b > out` 拼接，5 个抽查夹具随即全部 PASS。剩余 15/16 例失败分类：**git 源 7 例

（2026-11-15 定位为装具 `git-init` 缺陷并修复）**——`mktemp -d` 的 POSIX 路径交给 `git -C` 时 Git for Windows 与 msys `cp` 解析不同根，`.git` 落到复制目录之外，参考侧因此报 `fatal: repository './gitgem' does not exist`；改为 `$work/gitstage.*` 暂存 + `cygpath -w` 传 `git -C` 后 `add-git`/`add-ref` 双 profile PASS，其余 5 例失败形态转为 celerite 子进程 `sh.exe: *** fatal error - NtCreateDirectoryObject(...): 0xC0000022`（环境；bash 直连 `git clone --mirror` 连跑 3 次均 EXIT 0）、本机 native 构建 `0xC0000022` 8 例（环境）与 2.7.2-only 的 `clean-*` 2 例（已于 2026-11-15 撤销 profile 特例后 PASS），详见 `docs/compat-evidence/2026-11-15.md`）——新增 `fixtures/differential/lock-path-absolute-relative`（`lock`，4.0.24/2.7.2 PASS，负对照回退 PATH 归一即 `remote: foo` 断言失败）与 `fixtures/differential/lock-missing-dependency-edges`（`install`，两侧锁文件逐字相同、`file-contains` 全过；仅参考多打印两次 `Resolving dependencies...`，已按 documented deferral 标记）；装具新增 `@LOCKED_DEPS_INDEX_DIR@` 与 `CELERITE_DIFF_WORK_ROOT` 及每命令输出分片。

**2026-11-15（spec 自包含化）**：`spec/cli_spec.cr` 的 lock platform 往返用例原先只在 `~/.bundle/cache/compact_index` 热缓存存在时通过（隔离 HOME 下 `crystal spec spec/cli_spec.cr:288` 得 `Expected: 0 got: 17`），已改为离线 `fixtures/gem-index` + `file_source_url`、不预置锁文件、三步断言（lock → remove-platform → add-platform 逐字节还原）；`crystal spec spec/cli_spec.cr` 24 examples 0 failures，全量 `crystal spec` 317 examples 0 failures 4 errors（既有 GitSource msys `0xC0000022` 环境）。复选框保持未勾。
