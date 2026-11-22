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

## 2026-11-23：上游 lockfile 套件基线的 HEAD 复采（task-146）

### oracle

参考 Bundler 4.0.24 的上游套件 `rubygems/rubygems@v4.0.24` → `bundler/spec/lock/lockfile_spec.rb`，经 `script/upstream-specs` 的 shim 把 in-example 的 `bundle` 真驱动到本仓库二进制（`CELERITE_SKIP_TEST_DEPS=1`，未设 `CELERITE_BUNDLE_HELPER_OVERRIDE=0`）。oracle 即上游 rspec 自身的 examples/failures 计数与异常消息，不是本仓库自造的判据。

### 参考锚点

- 套件入口：`script/upstream-specs`（`repo_root="$(cd "$(dirname "$0")/.." && pwd)"`，`rev="${UPSTREAM_REV:-v4.0.24}"`，报告落 `.upstream-specs/upstream-lockfile-$rev-<UTC>.md`；第 41-46 行解析 `bin/celerite`，不存在时才回落 `bin/celerite.exe`；第 88-92 行 `shim/bundle` 导出 `CELERITE_BRIDGE_SERVER` 并 `exec "$celerite_bin" "$@"`）。
- 真驱动注入点：`script/upstream-specs-celerite-override.rb:44`（`Spec::Helpers#bundle`）。
- 被驱动二进制：`bin/celerite.exe`，12,647,441 B，SHA256 `4763E7079E6578A1AB74E308EA44AFCC35614059E78A430188F6CF23DA238DE8`（跑前跑后各核一次，未变）；无扩展名的 `bin/celerite` 在本机不存在。
- 采集时点：主工作区 HEAD `155639ca0f97263a03115b9b988fab41427ee4ea`（其父 `4a513a4`；`git diff --stat 4a513a4 155639c` 只有 `docs/compat-evidence/2026-11-23.md` +101/-1，即 HEAD 相对 `4a513a4` 只加文档、无源码变化）。
- 复现命令：`CELERITE_SKIP_TEST_DEPS=1 bash script/upstream-specs`，msys bash `C:\msys64\usr\bin\bash.exe`，`PATH=/c/msys64/usr/bin:/c/msys64/ucrt64/bin:/c/Ruby40-x64/bin:/c/Program Files/Git/cmd:...`，`TMPDIR=/c/temp`；**git 必须在 PATH 上**，否则上游 `spec/support/filters.rb:21` 的 `git --version` 直接 `Errno::ENOENT`、整套件报 `0 examples ... 1 error occurred outside of examples`。

### 实现位置

本次为复采，不改产品代码。产物与快照位置：

- 新基线报告：`.upstream-specs/upstream-lockfile-v4.0.24-20261122T174318Z.md`（16,688 B）。
- 分桶明细：`.upstream-specs/failure-buckets.md`（由 `script/upstream-specs-buckets.rb` 的 `UpstreamSpecsBuckets.classify` 生成，本机快照 8,828 B）。
- 原始输出（gitignored）：`.upstream-specs/rspec-output.txt`（367,059 B）、`.upstream-specs/rspec-output.json`（339,817 B）。
- 旧基线（未删除，仅对照）：`.upstream-specs/upstream-lockfile-v4.0.24-20261122T024315Z.md`（16,683 B），对应 task-118 第五次复采。

### 证据

环境与耗时：`ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [x64-mingw-ucrt]`、`git version 2.55.0.windows.3`；START `2026-11-22T17:43:17Z` / END `2026-11-22T17:52:21Z`（墙钟约 9 分 04 秒；rspec 自报 `Finished in 8 minutes 47 seconds (files took 3.6 seconds to load)`，seed 31249）。

原始结果行与退出码：

| 项目 | 本次（HEAD `155639c`） | 旧基线（`e71ed06`） |
|---|---|---|
| 结果行 | `64 examples, 48 failures`（16 passed） | `64 examples, 48 failures`（16 passed） |
| rspec 退出码 | 1 | 1 |
| real-drive | 51 celerite invocations | 51 celerite invocations |
| JSON summary | `{"duration":526.7974374,"example_count":64,"failure_count":48,"pending_count":0,"errors_outside_of_examples_count":0}` | — |
| seed / rspec 自报耗时 | 31249 / `Finished in 8 minutes 47 seconds` | 16550 / `Finished in 7 minutes 57 seconds` |

分桶表（本次）：

| 桶 | 数量 |
|---|---|
| `env:artifice-unreachable` | 40 |
| `env:low-il-shm` | 2 |
| `fixture:fetch-failed` | 3 |
| `product:candidates` | 3 |
| 合计 | 48 |

`product:candidates` 逐条（标题 :: 异常类，行号取自 `rspec-output.json` 的 `file_path:line_number`）：

1. `the lockfile format fills empty CHECKSUMS entries when not frozen, even if every gem is already installed` :: `RSpec::Expectations::ExpectationNotMetError` — `./spec/lock/lockfile_spec.rb:1682`
2. `the lockfile format with both ruby and specific platform behaves like a lockfile missing dependent specs auto-heals` :: 同类 — `./spec/lock/lockfile_spec.rb:2215`
3. `the lockfile format with just specific platform behaves like a lockfile missing dependent specs auto-heals` :: 同类 — `./spec/lock/lockfile_spec.rb:2215`

三条均为锁体断言失败（非环境抛出），与旧基线同一集合、消息未见变化。

与旧基线的差集（按 example 标题集合比对，两次均 64 例）：

- 新增通过（1 条）：`the lockfile format generates a lockfile with a ref for a single pinned source, git gem with a tag requirement` — `./spec/lock/lockfile_spec.rb:622`（旧基线中该例在失败集）。
- 新增失败（1 条）：`the lockfile format generates a lockfile with a ref for a single pinned source, git gem with a branch requirement` — `./spec/lock/lockfile_spec.rb:586`，`RuntimeError`，调用链 `spec/lock/lockfile_spec.rb:594` ← `spec/support/helpers.rb:288 install_gemfile` ← `script/upstream-specs-celerite-override.rb:44 bundle` ← `spec/support/helpers.rb:191 sys_exec` ← `spec/support/subprocess.rb:97 sh` ← `spec/support/command_execution.rb:25 raise_error!`；消息含 `git command failed: git clone --mirror ...` 与 `1 [main] sh (30648) C:\Program Files\Git\usr\bin\sh.exe: *** fatal error - NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-1888ae32e00d56aa): 0xC0000022`、`fatal: Could not read from remote repository.`，属下方声明的 msys Low-IL 环境族，不是产品缺陷。
- 仍失败（47 条）：48 条失败减去 1 条新增失败，47 条与旧基线共有且状态未变。
- 合计口径自洽：16 通过 + 48 失败 = 64；通过数 16 与旧基线相同（1 进 1 出）。
- 桶间漂移（状态仍是 failed，非转绿/转红）：`... correct GIT section, but also under an incorrect GEM section, with a higher version, and with no explicit Gemfile requirement` 由 `env:artifice-unreachable` 移到 `env:low-il-shm`；`the lockfile format is conservative with dependencies of git gems` 由 `env:low-il-shm` 移到 `env:artifice-unreachable`。

16 条通过例（`file:line`）：`:1119`、`:777`、`:1154`、`:744`、`:1648`、`:2144`、`:1479`、`:477`、`:2088`、`:1468`、`:622`、`:1933`、`:2410`、`:1084`、`:550`、`:1189`（均在 `./spec/lock/lockfile_spec.rb`）。

2.7.2 profile：**未复采成功**。`UPSTREAM_REV=v2.7.2 CELERITE_SKIP_TEST_DEPS=1 bash script/upstream-specs` 于 `2026-11-22T17:54:50Z` 起、`17:55:49Z` 止（约 1 分钟），得 `0 examples, 0 failures, 1 error occurred outside of examples`、`real-drive: 0 celerite invocations`、`WARNING: NOT driving celerite`、退出码 1，报告 `.upstream-specs/upstream-lockfile-v2.7.2-20261122T175451Z.md`（3,204 B），报错 `LoadError: cannot load such file -- .../.upstream-specs/v2.7.2/bundler/spec/lock/lockfile_spec.rb`。诊断：该 checkout 的 `git sparse-checkout list` 仍写着 `bundler/bin`/`bundler/exe`/`bundler/lib`/`bundler/spec`，但 `bundler/` 在磁盘上为空（脚本先 re-clone 再 reindex、未校验 sparse 路径是否落地）。既有 `upstream-lockfile-v2.7.2-20261113T161443Z.md` 报的是逐字相同的 `LoadError` 与同一计数行，即本机从未采到过 2.7.2 baseline；此为装具/检出缺陷，非本次改动所致。

### 已声明差异

- **旧基线 `64 examples, 48 failures` 采集于 `e71ed06`（task-118，2026-11-22 02:43Z），已被本条 HEAD `155639c` 的复采结果取代。** 总数、real-drive、桶总数均未变，故 M7-8 的待办状态不因本次复采改变；取代关系仅在于「基线时点」与上列 ±1 例的构成变化。
- 环境族在本机不可消除，本节不据其判定产品差异：① 宿主 Ruby 缺 `sinatra`/`artifice`（`require 'sinatra/base'` → LoadError），`env:artifice-unreachable` 40 条属此类；② msys Low-IL 下的 `0xC0000022`（`NtCreateDirectoryObject`）使部分 git 源用例在任何二进制下都失败，本轮新增失败的 `lockfile_spec.rb:586` 即此族；③ 上游 `tmp/2.1/gems/` 只有 `base`/`remote1`、缺 `remote2`/`system`，`fixture:fetch-failed` 3 条属此类。
- 本次未做多次采样，`8 minutes 47 seconds` 与 seed 31249 均为单次观测；`product:candidates` 三条选在本次未做逐条差分定位，故只记入桶、不宣称产品结论变化。
- 2.7.2 profile 未取得有效 baseline（见上），本条不对 2.7.2 作任何结论。
## 2026-11-23：装具的真驱动自检与 checkout 完整性（task-148）

### oracle

`docs/roadmap.md` L148 原文：「修复 `script/upstream-specs`：使锁文件族真实驱动 Celerite，退出码反映失败；保留当前 64 failures 作为失败基线，再逐项关闭。」

拆成可判定的三条：

1. 装具必须自证「真的驱动了 celerite」，不能只靠 rspec 自己的退出码——`real-drive == 0` 或 `examples == 0` 都要立即非零退出并打印明确错误。
2. checkout 不存在「有 spec 文件就算可用」的假设：`bundler/spec/lock/lockfile_spec.rb` 在而 `bundler/lib` 缺失或为空时必须重取，仍失败要带明确错误退出，不得静默产出 `0 examples` 的假报告。
3. 退出码要区分「上游失败」与「环境不可用」两类；既有的 `0 = 全绿` 语义不变。

### 参考锚点

- `docs/roadmap.md:148`：本条要求原文（复选框保持 `[ ]`，未勾）。
- task-146 复采（不带 `git` 的 PATH）：`0 examples, 0 failures, 1 error occurred outside of examples`、`real-drive: 0 celerite invocations`、`WARNING: NOT driving celerite (helper override disabled or not applied)`。该形态下 rspec 仍退 1，但装具本身无法区分「跑过但失败」与「根本没跑起来」——正是本任务要消除的假绿缝。
- 基线（4.0.24、PATH 含 git、`CELERITE_SKIP_TEST_DEPS=1`）：`64 examples, 48 failures`、real-drive 51 次，报告 `.upstream-specs/upstream-lockfile-v4.0.24-20261122T174318Z.md`。
- 上游锚点：`bundler/spec/support/filters.rb:21`（`git --version`，无 git 即 `Errno::ENOENT`）；`bundler/spec/spec_helper.rb:16` 与 `:20`（`rspec ~> 3.6`，以及 `abort "Run rake spec:deps to install development dependencies"`）；`bundler/spec/support/rubygems_ext.rb:32`（`install_test_deps unless ENV["RSPEC_FORMATTER_OUTPUT_ID"]`，即 `CELERITE_SKIP_TEST_DEPS=1` 的落点）。
- `v2.7.2` tag 的 `.gitmodules`：`[submodule "bundler"] path = bundler url = https://github.com/bundler/bundler.git`；`git ls-tree HEAD -- bundler` = `160000 commit 10f20fa33bc36371cbad00106487c6eb22616ec7 bundler`。子模块内的 `bundler/` 才是 `lib` 与 `spec` 所在。

### 实现位置

`script/upstream-specs`：

- `:55-56` 退出码常量 `exit_env_unusable=69`（EX_UNAVAILABLE）、`exit_not_driving=70`（EX_SOFTWARE）；文件头 Notes 补退出码表（`0` 全绿 / `<rspec status>` 上游红 / `69` 环境不可用 / `70` 未驱动 / `127` 二进制缺失）。
- `:87-95` `init_bundler_submodule()`：`git ls-files -s -- bundler` 命中 `160000*` 时执行 `git submodule update --init --depth 1 bundler`；新树在 `:109` 之后调用，`repair_checkout` 内在稀疏重放与重 clone 之间（`:161`）调用一次，重 clone 分支内（`:173` 之后）再调用一次。
- `:122-198` checkout 完整性预检：`checkout_markers` 为 `bundler/lib/bundler.rb`、`bundler/lib/bundler/version.rb`、`bundler/spec/lock/lockfile_spec.rb`、`bundler/spec/support/helpers.rb`，另要求 `bundler/bin`、`bundler/exe` 为非空目录；`repair_checkout` 三级修复（稀疏重放 → 子模块初始化 → 重 clone），仍失败则打印 `refusing to run the upstream suite against an incomplete checkout` 并 `exit 69`。
- `:210-222` 缺 git 闸：`command -v git` 失败即打印 `error: git is not on PATH, but the upstream suite requires it` 等四行并 `exit 69`；`rev-parse` 取不到 HEAD（等于 `unknown`）同样 `exit 69`。
- `:250-252` `drive_counter="$repo_root/.upstream-specs/celerite-invocations.log"`；shim 的 `bundle`/`bundle.cmd`/`bundle.bat` 各自在启动时向 `$CELERITE_DRIVE_COUNTER` 追加一行 PID；跑 rspec 前 `: > "$drive_counter"` 清空。
- `:300-301` 跑 rspec 前 `: > "$rspec_out"` 与 `: > "$json_out"` 截断，堵住「上次残留冒充本次证据」。
- `:351` 子 shell 导出 `CELERITE_DRIVE_COUNTER`。
- `:379-393` 真驱动自检：`drive_counter_count`（计数文件行数）与 `celerite_invocations`（`grep -c -E 'celerite(\.exe)? ' "$rspec_out"`）取大者。
- `:397-399` 由 `summary` 解析 `examples_total` 与 `failures_total`。
- `:442-459` 判词：`examples_total -eq 0` → `harness_rc=69`；否则 `celerite_invocations -eq 0` → `harness_rc=70`；否则 `harness_rc=$rspec_status`（既有语义不变）。
- `:473`、`:476`、`:486` 报告新增 `- Checkout HEAD:`、`- real-drive counter file:`、`- harness verdict:` 三行。
- `:504-514` 判词非 ok 时向 stderr 打 `error: $verdict`、`harness exit N (rspec exited M)`、`report: <path>`，然后 `exit "$harness_rc"`。

`script/upstream-specs-celerite-override.rb`：

- `:15-24` `celerite_record_drive`：以 append 模式向 `ENV["CELERITE_DRIVE_COUNTER"]` 写 `Process.pid`，`rescue StandardError` 静默——计数是旁证，写不进去也不能改变套件行为。
- `:58` 在 `:59` 的 `sys_exec(...)` 之前调用。这是 in-example 驱动的唯一注入点，与 shim 计数互为独立旁证。

### 证据

命令与结果行（worktree `C:\temp\celerite-t148`，detached；PATH 前缀 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin`，`TMPDIR=/c/temp`，`CELERITE_SKIP_TEST_DEPS=1`）。

反假绿负对照（PATH 显式去掉 `C:\Program Files\Git\cmd`，其余全同）：

```
git=NONE
error: git is not on PATH, but the upstream suite requires it
       (bundler/spec/support/filters.rb:21 runs 'git --version'; without it
        rspec loads 0 examples and reports no real compatibility evidence)
       add git to PATH and re-run
HARNESS_EXIT=69
```

未写出任何新报告（最新报告仍是上一次正对照的），计数文件 0 字节。即：不再产出 `0 examples` 的体面报告来冒充证据。

正对照（PATH 含 git）：

```
upstream checkout integrity: ok (HEAD 3b396e42bdf993c7cbf64647fca2a31177eab734)
wrote /c/temp/celerite-t148/.upstream-specs/upstream-lockfile-v4.0.24-20261122T184550Z.md
HARNESS_EXIT=1
```

报告 `upstream-lockfile-v4.0.24-20261122T184550Z.md` 正文：

```
- Checkout HEAD: `3b396e42bdf993c7cbf64647fca2a31177eab734` (integrity pre-check passed)
- rspec exit status: 1
- real-drive counter file: `.../.upstream-specs/celerite-invocations.log` (69 lines)
## Result summary
64 examples, 47 failures
- real-drive: 69 celerite invocations
- harness verdict: ok (rspec exit 1)
buckets: env:artifice-unreachable (43) / fixture:fetch-failed (1) / product:candidates (3)
```

计数文件 69 行多于输出扫描 50 行，取大者生效——`real-drive: 69` 由计数文件给出，不依赖输出里的巧合子串。

`real-drive == 0` 判词实测（正对照首次跑到 fixture 未预置的形态）：`- real-drive: 0 celerite invocations`、`- harness verdict: the upstream suite did not drive celerite (0 invocations)`、`HARNESS_EXIT=70`、stderr `error: the upstream suite did not drive celerite (0 invocations)`。即「64 examples 全失败但一次都没驱动」与「上游失败」被分成两个不同退出码。

`examples == 0` 判词实测：首次正对照漏了 `CELERITE_SKIP_TEST_DEPS=1`，上游 `bundler/lib/bundler.rb:501` 读 `tool/bundler/test_gems.rb` 得 `Errno::ENOENT`（稀疏 checkout 不含 `tool/`），套件报 `0 examples, 0 failures, 1 error occurred outside of examples`，装具判 `69` 并打 `error: the upstream suite ran 0 examples (environment/checkout unusable)`。

v2.7.2 checkout 修复实测（`UPSTREAM_REV=v2.7.2`）：

```
Cloning rubygems/rubygems @ v2.7.2 (sparse)...
initialising upstream bundler submodule (gitlink in v2.7.2)
upstream checkout integrity: ok (HEAD 01e797f6aa045fd09df7813d0b5448e3667172a9)
```

修复前该 tree 的 `bundler/` 恒为空（`git sparse-checkout list` 列得出 `bundler/spec` 却不能落盘），装具现在报 `upstream checkout incomplete: ...` 并拒绝开跑；修复后四个 marker 与 `bin`（7 个文件）、`exe`（3 个文件）全部在位。

本机既有检查：`crystal tool format --check src spec` → exit `0`；`git diff 155639c..HEAD --check` → exit `0`。

### 已声明差异

1. **v2.7.2 仍未采到基线**（目标 4 未完成）。子模块修复后 2.7.2 的 checkout 已完整，但套件在 `bundler/spec/spec_helper.rb:20` 直接 `abort "Run rake spec:deps to install development dependencies"`，根因 `Gem::MissingSpecError: Could not find 'rspec' (~> 3.6) among 850 total gem(s)`（`GEM_PATH` 只含宿主默认路径）。`CELERITE_SKIP_TEST_DEPS=1` 正是跳过 `spec:deps` 的开关，2.7.2 的 spec_helper 却硬依赖它；4.0.24 profile 因装具改用 `ruby -S rspec` 而未触发。要采 2.7.2 基线还需在 2.7.2 tree 内另装其开发依赖，或改 rspec 解析路径；本任务未做。`docs/compat-claims` 中 C-M7-8-016「2.7.2 未复采」的状态不变。
2. **截断前存在真绿假象（已修）**：`rspec --out` 只在套件结束后写文件，跑挂了就留着上一次的文件。v2.7.2 在 spec_helper 崩溃的那次，报告一度写出 `64 examples, 47 failures`、`- real-drive: 50 celerite invocations`、`- harness verdict: ok (rspec exit 1)`——每个数字都是上一次 4.0.24 运行的残留。`:300-301` 的两行截断即为堵这个洞。
3. **本机新基线是 64/47，不是 64/48**：分桶 `env:artifice-unreachable (43)`、`fixture:fetch-failed (1)`、`product:candidates (3)`，合 47；主工作区参考报告为 artifice 40 / fetch 3 / product 3。差异来自本 worktree 的 fixture 预置状态（`bundler/tmp/gems/pristine_system` 需用宿主 `spec/support/helpers.rb` 的 `Spec::Helpers.install_dev_bundler` 预置），非本次改动所致，也不主张与旧基线逐字节相同。此处只登记新基线数值，未改任何分类桶逻辑。
4. **未做**：`docs/roadmap.md` 复选框、`docs/compat-report.md`、`docs/compat-claims/` 均未改；失败基线未删；分类桶未调。新增退出码 69/70 未接入任何断言方（`.github/workflows/ci.yml:55-74` 只上传报告、不检查退出码），故不破坏既有 CI 调用，但也意味着**没有回归测试锁住这套自检**——只有本次手工 A/B 双跑为证。
