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
## 2026-11-23：锁缺 spec 行的自愈（task-149）

### oracle

- 上游用例：`.upstream-specs/v4.0.24/bundler/spec/lock/lockfile_spec.rb:2214-2279`，`shared_examples "a lockfile missing dependent specs"` → `it "auto-heals"`，两个 context 各一条失败：`with both ruby and specific platform behaves like a lockfile missing dependent specs auto-heals`、`with just specific platform behaves like …`（task-118 基线均落在 `lockfile_spec.rb:2215`，`RSpec::Expectations::ExpectationNotMetError`）。
- 用例形状：`build_repo4` 造 `minitest-bisect 1.6.0`（`add_dependency "path_expander", "~> 1.1"`）与 `path_expander 1.1.1`；Gemfile 为 `source "https://gem.repo4"` + `gem "minitest-bisect"`；`Gemfile.lock` 的 `GEM`/`specs` 段**只有** `minitest-bisect (1.6.0)` 一行——没有 `path_expander` 的边、也没有 `path_expander (1.1.1)` 行；`cache_gems "minitest-bisect-1.6.0", "path_expander-1.1.1", gem_repo: gem_repo4` 只往 `vendor/cache` 放这两个 `.gem`；断言 `bundle :install` 后锁为
  `minitest-bisect (1.6.0)` / `  path_expander (~> 1.1)` / `path_expander (1.1.1)`，`PLATFORMS` 为 `#{platforms}`（`lockfile_platforms` 或 `lockfile_platforms("ruby")`），`DEPENDENCIES` 为 `minitest-bisect`。
- 触发条件是**源索引不可达**：索引可达时 HEAD 的 stale 探针已能把两条自愈（实验 vE），上游 harness 用 artifice 注入 `RUBYOPT`，celerite 原生进程拿不到该桩，故真驱动下这一形态恒为「索引不可达 + 只有 `vendor/cache`」。
- 离线可差分形态（本次据此建夹具）：不可达源 `http://127.0.0.1:9/` + `vendor/cache` 里的两个 `.gem` + `install --local`。参考侧在此形态 `exit 0` 并把锁补全；不带 `--local` 时参考侧直接 `exit 17`（`Could not reach host 127.0.0.1:9. Check your network connection and try again.`），不是差分区。

### 参考锚点

- `lazy_specification.rb:260-268`（`validate_dependencies`）：strict 物化时比较锁行记录的 `dependencies` 与源物化 spec 的 `runtime_dependencies`，不等即 `raise IncorrectLockfileDependencies.new(self)`。这是参考「察觉」缺行的唯一入口。
- `definition.rb:699-708`（`materialize`）：`rescue IncorrectLockfileDependencies => e` → 非 frozen 时 `reresolve_without([e.spec])` 后 `retry`；frozen 时原样抛出。
- `definition.rb:782-785`（`reresolve_without`）：`resolution_base.delete(incomplete_specs)` + `@resolve = start_resolution`。只从解析基底删行，**不**写 `@gems_to_unlock`，`@originally_locked_specs` 仍是原对象，所以已存在行的锁定版本不被抬升。
- `spec_set.rb:125-129` / `:241-264` / `:266-268`（`materialize` / `materialize_dependencies` / `materialized_specs`）：重解析按依赖闭包物化——`deps.concat(materialization.dependencies) if materialization.complete?` 把新发现的边重新入队，`@materializations << materialization` 为每个访问到的名字留下物化项，缺的 spec 行就是这样被补出来的（**补行发生在 resolve 阶段，不是安装阶段事后追加**）。
- `spec_set.rb:86-96`（`validate_deps`）：`check_lockfile` 用的校验；空依赖集返回 `:valid`，所以「锁内完全没有该 spec 行」这种形态不靠它察觉（本次也未改 `lockfile_covers_dependencies?`）。
- 安装顺序：`spec_set.rb:316-323`（`sorted`）= `[@specs.find { "rake" }] + tsort`，`tsort_each_node` 按名字排序（`:339-341`）、`tsort_each_child` 按依赖名排序（`:344-353`）；`installer.rb:203-219` 把 `definition.specs` 交给 `ParallelInstaller`，`jobs == 1` 时 `install_serially`（`parallel_installer.rb:161-170`）按该序列逐个 `ready_to_enqueue?` 安装。故参考在本形态下打 `Installing path_expander 1.1.1` 在 `Installing minitest-bisect 1.6.0` **之前**（依赖先装，非字典序）。

### 实现位置

- `src/celerite/resolution.cr:1130-1131`（`resolve!` 的 `--local` 早退块内）：`healed = available && heal_missing_locked_spec_rows`；随后
  `@progress.puts "Resolving dependencies..." if @show_resolving && (healed || (available && !platform_ready))`。自愈确实发生时只打**一行** `Resolving dependencies...`（参考在本形态下同样是一行），并且因为父行边已在 resolve 阶段改写完毕，`commands_install.cr:727` 的 `refresh_locked_dependencies` 返回 `false`，`commands_install.cr:740-742` 的两行补打不再触发。
- `src/celerite/resolution.cr:1194-1196`（`reuse` 复用路径，索引不可达时的静默返回点）：`if stale.empty?` → `heal_missing_locked_spec_rows` → `return @resolved_specs`。stale 探针在索引不可达时被 `rescue next` 吞成空集，这里是它之后的同一段补行逻辑，**没有**改动 `stale_locked_dependency_full_names` 的 `@local_only` 短路（`:1248`）。
- `src/celerite/resolution.cr:1776-1839`（新增 `private def heal_missing_locked_spec_rows : Bool`，紧邻 `refresh_locked_dependencies` / `run_resolution` 之前）：以已物化的 GEM 行为队列，对每行用 `local_index_specs(name)` 取 `full_name` 相同的候选；把候选比锁行多出的 runtime 边（剔除 `bundler`）作为「缺行」的线索，子行也只从本地候选（已装 spec + `vendor/cache`）里选，且必须满足该边的 `Gem::Requirement`。任一边无法在本地满足时不动那行，安装器照旧报缺包。确认有缺行后：给父行追加缺失的边（写 `Lockfile::SpecDependency`，6 空格缩进由 `to_lock_line` 负责），并把子行以新 `ResolvedSpec` 追加到 `@resolved_specs`（`source_type "GEM"`、`source_index 0`、checksum 取自本地候选）。补出的行会被 `installable_specs`（`commands_install.cr:1189-1223`）顺着刚补上的边纳入安装集，并由 `vendor_cache_path`（`:591-594`）命中 `vendor/cache` 里的包。
- 未改动：`stale_locked_dependency_full_names`（含 `@local_only` 短路与 `rescue next`）、`lockfile_covers_dependencies?`、`lockfile_covers_all_dependencies?`、安装顺序（仍是 `pending.sort_by(&.full_name)`，见「已声明差异」）。

### 证据

新夹具 `fixtures/differential/lock-missing-spec-row/`（`command` = `install --local`，`env` = `BUNDLE_JOBS=1`，`Gemfile` 指向 `http://127.0.0.1:9/` + `gem "zroot-gem"`，`Gemfile.lock` 只有 `zroot-gem (1.6.0)` 行，`extra/vendor/cache/{zroot-gem-1.6.0,child-gem-1.1.1}.gem` 为 4096 B 最小合成桩，`installed-tree` 覆盖 `ruby/*/gems`、`ruby/*/specifications`、`ruby/*/bin`）。`zroot-gem 1.6.0` 声明 `child-gem ~> 1.1`，`child-gem 1.1.1` 无依赖；两个名字的字典序与依赖序一致，用来把「补行」这一件事与安装顺序差异隔开（顺序差异本身见下）。

修复后双 profile 原始结果行：

```
PASS lock-missing-spec-row (exit=0)

differential (4.0.24): 1 passed, 0 failed, 0 skipped (documented deferrals)
```
```
PASS lock-missing-spec-row (exit=0)

differential (2.7.2): 1 passed, 0 failed, 0 skipped (documented deferrals)
```

反假绿：`CELERITE_BIN=C:\temp\celerite-pre149\bin\celerite-old.exe`（`C:\temp\celerite-pre149` detached @ `3e0cebb`，与本次 base 相同）+ 工作区的 `script/differential`，同一夹具必须 FAIL，原文：

```
FAIL lock-missing-spec-row (install --local)
      stdout differs:
    2c2
    < Installing child-gem 1.1.1
    ---
    > Resolving dependencies...
    5,6c5,6
    < Bundle complete! 1 Gemfile dependency, 2 gems now installed.
    < Bundled gems are installed into `C:\temp\celerite-t149\.d-anfi/pz3zAa/ref/bundle`
    ---
    > Bundle complete! 1 Gemfile dependency, 1 gem now installed.
    > Bundled gems are installed into `C:\temp\celerite-t149\.d-anfi/pz3zAa/cel/bundle`
      installed tree differs:
      ruby/4.0.0/gems path set differs:
        Only in 'C:\temp\celerite-t149\.d-anfi/pz3zAa/ref/bundle/ruby/4.0.0/gems': child-gem-1.1.1
      ruby/4.0.0/specifications path set differs:
        Only in 'C:\temp\celerite-t149\.d-anfi/pz3zAa/ref/bundle/ruby/4.0.0/specifications': child-gem-1.1.1.gemspec  file-equals differs (Gemfile.lock, cel):
    4d3
    <     child-gem (1.1.1)

    sandboxes kept at: C:\temp\celerite-t149\.d-anfi/pz3zAa

differential (4.0.24): 0 passed, 1 failed, 0 skipped (documented deferrals)
```

同一棵 `celerite-pre149` 上跑新增 spec（把 spec 与夹具原样拷入该树）——修前 1 条失败、修后 0 条：

```
  1) task-149 locked spec row missing and the source index unreachable heals the missing row and edge from vendor/cache under --local
     Failure/Error: out.should contain("Installing child-gem 1.1.1")
       Expected:   "Resolving dependencies...\n" +
3 examples, 1 failures, 0 errors, 0 pending
```

受影响 spec 家族（修复后，`crystal spec` 逐文件列出，原始尾行）：

```
spec/m7_lockfile_locked_deps_spec.cr spec/m7_install_failure_spec.cr spec/m7_lock_autoheal_spec.cr \
spec/m7_check_missing_dependency_spec.cr spec/m7_lock_missing_spec_row_spec.cr spec/m7_local_install_step_spec.cr \
spec/m7_vendor_cache_spec.cr spec/m7_local_install_spec.cr spec/m7_local_install_missing_dep_spec.cr \
spec/m7_prefer_local_spec.cr
38 examples, 0 failures, 0 errors, 0 pending
```

同名族扩到 `install|lock|local|prefer_local|vendor|reuse|frozen|update` 共 49 个 spec 文件：

```
225 examples, 0 failures, 0 errors, 0 pending
```

新增 `spec/m7_lock_spec_row_heal_spec.cr`（3 例）：①`install --local` 在不可达源 + `vendor/cache` 下补出 `child-gem (1.1.1)` 行与 `zroot-gem` 的边，输出含 `Installing child-gem 1.1.1` / `Installing zroot-gem 1.6.0` / `Bundle complete! 1 Gemfile dependency, 2 gems now installed.`，且 `bundle/ruby/<abi>/specifications` 里两个 `.gemspec` 都在；②两行齐、边齐时锁逐字不变且没有 `Resolving dependencies...`，`child-gem (1.1.1)` 行只出现一次（补行不重复）；③既无索引也无 `vendor/cache` 时仍 `exit 7` 且报 `Could not find zroot-gem-1.6.0 in locally installed gems`，锁里不得凭空长出 `child-gem`。

门禁：`crystal tool format --check src spec` → exit 0；`git diff 3e0cebb..HEAD --check` → exit 0。

### 已声明差异

- **安装顺序**：参考按 `SpecSet#sorted` 的 tsort 拓扑序安装（依赖先装），celerite 仍按 `pending.sort_by(&.full_name)` 的字典序（`commands_install.cr:480`）。本夹具因此选用「字典序 = 依赖序」的两个合成 gem（`child-gem` / `zroot-gem`），使这条差异不混进本用例；一旦父子名序反向（如上游 oracle 的 `minitest-bisect` → `path_expander`，字典序把父排在子前），celerite 的 `Installing` 两行顺序会与参考相反。这是**未修**的既有差异，本次不重构安装顺序。
- **stale 探针的 `rescue next`**：`stale_locked_dependency_full_names`（`resolution.cr:1264-1268`）在索引不可达时仍把异常吞成「与锁一致」，本次按要求未动它；补行改由 `heal_missing_locked_spec_rows` 在 materialize 之后独立完成。因此该探针的语义缺陷仍在（`--frozen` 下索引不可达时不会报 `IncorrectLockfileDependencies`，而是直接复用锁）。
- **`--local` 与不带 `--local` 的行为仍不同**：不带 `--local` 且源不可达时，参考侧 `exit 17`（`Could not reach host …`），celerite 侧只要 `vendor/cache` 有包就 `exit 0` 并（修复后）补全锁。这条差异属既有声明（task-146 记于 `docs/roadmap-evidence/M7-8-upstream-specs.md` 之外的产品差异清单），本次未改。
- **未验证**：未跑上游 `script/upstream-specs` 真驱动（本机 artifice 不可用，`env:artifice-unreachable` 族）；未验证 `PLATFORMS` 含 `ruby` 的第二种 context（上游 `with both ruby and specific platform`）在本夹具形态下的输出行数；未跑全量 `crystal spec`。

## 2026-11-23：M7-8 基线数字与 product 桶的取代说明（task-158）

本节是 supersession 条目：旧陈述原文保留不删，仅在此写明取代关系。

被取代的旧陈述（逐字，未改）：

- `docs/roadmap.md` 的 M7-8 行：「保留当前 64 failures 作为失败基线，再逐项关闭。」
- 本节 task-146 段与 task-148 段给出的旧基线口径「`64 examples, 48 failures`」中关于 **failures 总数**的那部分数字（分桶明细与差集仍有效，未被取代）。

### 新基线

`docs/compat-report.md` 的 `## Current metrics`（**唯一对外口径**）与入库产物 `.upstream-specs/upstream-lockfile-v4.0.24-20261122T190748Z.md` 一致为 **`64 examples, 47 failures`**（17 passed，real-drive 69 次 celerite 调用，`harness verdict: ok`）。取代 `64 examples, 48 failures` 与 roadmap 里的 `64 failures`；64 − 47 = 17 passed，pass 数与 failures 数须成对引用（旧产物 `…T174318Z.md` 为 64 − 48 = 16 passed）。

### 48 → 47 的原因

减少的 1 例是 `spec/lock/lockfile_spec.rb:586`（git branch requirement 用例）**转绿**，**不是产品修复**：该例在 `…T174318Z.md`（48 failures，收录于 `env:low-il-shm` 桶，`:68` 原文 `… git gem with a branch requirement` :: RuntimeError）里失败，在 `…T190748Z.md`（47 failures）里通过；两次采集之间该用例的通过/失败变化不伴随任何 `src/` 改动，属宿主 msys Low-IL 环境抖动。因此 47 只是新采集基线，不得读作「已修好一项 product 缺陷」。

### 分桶口径：对外口径与入库产物

**唯一对外口径**是 `docs/compat-report.md` 的 `## Current metrics`：`env:artifice-unreachable 41` / `fixture:fetch-failed 3` / `product:candidates 3`（合计 47）。本节以下数字只作为该口径对应的入库原始产物对照，不改写、也不替代它。

仓库内有、且可复核的两份同代产物（`.upstream-specs/` 下，未入 git，本机实存，本节用 `Select-String` 逐行取得）：

- `upstream-lockfile-v4.0.24-20261122T174318Z.md`（16,688 B）：`:17` `64 examples, 48 failures`（16 passed）、`:19` `- real-drive: 51 celerite invocations`；分桶 `:23` `### env:artifice-unreachable (40)`、`:66` `### env:low-il-shm (2)`、`:71` `### fixture:fetch-failed (3)`、`:77` `### product:candidates (3)`。
- `upstream-lockfile-v4.0.24-20261122T190748Z.md`（16,726 B）：`:19` `64 examples, 47 failures`（17 passed）、`:21` `- real-drive: 69 celerite invocations`、`:22` `- harness verdict: ok (rspec exit 1)`；分桶 `:26` `### env:artifice-unreachable (41)`、`:70` `### fixture:fetch-failed (3)`、`:76` `### product:candidates (3)`——**无 `env:low-il-shm` 节**。

48 → 47 的分桶变化（**据两表数字推导，未逐例复核**）：`env:low-il-shm` 的 2 条里，一条并入 `env:artifice-unreachable`（40 → 41），另一条即 `spec/lock/lockfile_spec.rb:586`（git branch requirement）转通过（passed 16 → 17）。两表 failures 差 1、passed 差 1，与上述推导自洽；本节未逐例核对分桶成员，故这是推导而非实测结论。

task-148 交付者另报告过一份 `env:artifice-unreachable 43` / `fixture:fetch-failed 1` 的实跑，那是 task-148 私有 worktree 的产物（**未入库、本机已不存在该文件、不可复核**；task-148 段 `:219` 记录其写入路径为 `/c/temp/celerite-t148/.upstream-specs/…`），**不作为口径来源，也不与上两份并列**；如需引用须先入库再复核。

### product:candidates 三条的现状

- `spec/lock/lockfile_spec.rb:1682`（`fills empty CHECKSUMS entries when not frozen, even if every gem is already installed`）：**判为「离线不可验证」**。该例走 artifice（宿主缺 `sinatra`/`artifice`，`spec/support/artifice/helpers/compact_index.rb:3` 报 `cannot load such file -- sinatra/base`），且在可复现形态下**双侧行为一致**（file:// + 已装包字节形态下参考侧同样留裸行，diff 显示 ref 与 cel 同形）⇒ 既非 celerite 缺陷、亦无法离线证成或证伪。依据见 `docs/compat-evidence/2026-11-23.md` 的「install 回填空 CHECKSUMS 条目的可行边界（task-140）」节；该节明确未提交任何 `src/` 守卫补丁。
- `spec/lock/lockfile_spec.rb:2215`（missing dependent specs auto-heals）的 **`--local` 形态已由 task-149 修好**：新增夹具 `fixtures/differential/lock-missing-spec-row/`、新增 `spec/m7_lock_spec_row_heal_spec.cr` 3 例、双 profile PASS、反假绿 3e0cebb FAIL。**仍未关闭**的部分见 task-149 段的已声明差异（安装顺序未修、stale 探针 `rescue next` 未动、`--local` 与不带 `--local` 行为不同、未跑真驱动），故该条**不得**整条读作已修。
- 第三条第 2215 的另一参数化形态同理仍以 task-149 段的声明为准。

### 取代关系

- 「保留当前 64 failures 作为失败基线，再逐项关闭。」由本节的「新基线」取代：基线应为 `47 failures`；`docs/roadmap.md` 的同一处已同步改为 `47 failures`，复选框保持 `[ ]`（M7-8 未完成）。
- task-146 段 `64 examples, 48 failures` 的 **failures 总数**由本节与 task-148 段的 `64 examples, 47 failures` 取代；task-146 段其余事实（分桶明细、差集、旧基线 e71ed06 已被 155639c 取代的声明）继续有效，旧文保留。
- 本节不新增 roadmap 行号引用；引用点位置一律用文本（如「M7-8 行」）指代。

### 已声明差异

- 本节为数字与归属的登记条目，未跑编译、未跑差分、未新增或修改任何 `src/`、`spec/`、`fixtures/` 文件；47 与两个分桶表均转述既有原始记录，未重采。
- 48→47 归因（`:586` 转通过）依据 task-148 段的差集记录（新增通过 `:622`、新增失败 `:586`）与两份入库产物（`…T174318Z.md`、`…T190748Z.md`）；分桶成员归属为据两表数字的推导，未逐例复核；本条未独立重跑该用例。

## 2026-11-23：artifice 桶（41 条）的可判定化尝试（task-178）

### 结论（先行）

- **段二成功**：`sinatra 4.2.2` + `rack-protection 4.2.2` 装入系统 GEM_HOME，`require "sinatra/base"` / `require "rack/test"` 均通过。`artifice` gem **不需要**安装：bundler 自带 vendored 实现（`spec/support/artifice/helpers/artifice.rb:1-45`）。
- **段三证明 41 条 artifice 桶不是「缺 gem」**：装 sinatra 后新基线 `64 examples, 50 failures`，`cannot load such file -- sinatra` 出现 **0 次**，38 条失败体的 stderr 是 `Could not reach host gem.repo2`。真因在 `spec/support/helpers.rb:154-177`：RSpec 侧把 artifice 作为 `RUBYOPT=-r<artifice>.rb` 注入**子进程**，而 celerite 覆盖层把 `:artifice` 直接丢弃并以原生 exe 执行（`script/upstream-specs-celerite-override.rb:39-40`、`:52-57`），故 celerite 永远拿不到桩。
- 该桶在 real-drive 下**不可判定为通过**：宜改判 `env:out-of-process-artifice`（不适用 / 需参考侧 Ruby 驱动），而不是继续等 gem 清单补全。

### 需求清单（带 文件:行号）

- 上游快照**没有** `bundler/Gemfile`；`bundler.gemspec:1-47` 无任何 `add_development_dependency`。开发依赖由 `tool/bundler/{test_gems,dev_gems,rubocop_gems,standard_gems}.rb` 提供（`spec/support/path.rb:32-45`、`:350-359`），而快照缺 `tool/` 目录（`.upstream-specs/v4.0.24/` 下无 `tool`）⇒ `install_test_deps` 在本快照里无输入可装。这才是 `CELERITE_SKIP_TEST_DEPS=1` 才能跑通的真实原因，不是"网络问题"。
- artifice 桩本身：`spec/support/artifice/helpers/artifice.rb:1-45`（模块内 `replace_net_http` 换 `Gem::Net::HTTP` 常量），`spec/support/artifice/helpers/rack_request.rb:3` `require "rack/test"`、`:12-20` `include Rack::Test::Methods` + `def connect; end`（不开 socket）。
- sinatra 侧：`spec/support/artifice/helpers/endpoint.rb:5` `$LOAD_PATH.unshift(*Spec::Path.sinatra_dependency_paths)`，`:7` `require "sinatra/base"`；同类 `spec/support/artifice/windows.rb:5,7`、`spec/support/artifice/endpoint_500.rb:5,7`。
- sinatra 运行依赖清单由 `spec/support/path.rb:306-317` 写死：`mustermann`、`rack`、`tilt`、`sinatra`、`ruby2_keywords`、`base64`、`logger`、`cgi`；取法为 `Dir[scoped_base_system_gem_path.join("gems/{…}-*/lib")]`（**无版本约束**）。
- rack/test：`spec/support/artifice/helpers/rack_request.rb:3`；`spec/support/helpers.rb:612-618`（临时把 `GEM_HOME` 切到 `scoped_base_system_gem_path` 再 require）。
- 套件启动链：`spec/spec_helper.rb:90` `config.before :suite` → `:93` `require_relative "support/rubygems_ext"` → `:94` `Spec::Rubygems.test_setup`；`spec/support/rubygems_ext.rb:30-32` = `install_test_deps unless ENV["RSPEC_FORMATTER_OUTPUT_ID"]`，`:58-65` = 三次 `dev_bundle("install", …)` + `Helpers.install_dev_bundler` + `install_vendored_compact_index`，`:129` `dev_bundle` 用 ``ruby #{Path.dev_binstub}`` 起子进程。`script/upstream-specs:352-356` 在 `CELERITE_SKIP_TEST_DEPS=1` 时导出 `RSPEC_FORMATTER_OUTPUT_ID=celerite-harness` 跳过整段。
- gem 可得性/扩展：`sinatra 4.2.2` 纯 Ruby、**无原生扩展**（`gem install --no-document` 未触发编译器），依赖 `rack-protection 4.2.2`。本机原已在位：`rack 3.2.9`、`rack-test 2.3.0`、`mustermann 3.1.1`、`tilt 2.9.0`、`base64 0.3.0`、`logger 1.7.0`、`cgi 0.5.2`、`ruby2_keywords 0.0.5`——即 `path.rb:306-317` 清单里**除 sinatra 外全部早已在位**。
- artifice 引用面：`grep -rl artifice spec --include=*.rb | grep -v '^spec/support/'` = **43 个 spec 文件**；直接 `require` 的仅 `spec/bundler/installer/parallel_installer_spec.rb:16,:106`、`spec/realworld/double_check_spec.rb:29`、`spec/realworld/edgecases_spec.rb:6`，其余靠 `bundle … artifice:` 选项注入（`spec/support/helpers.rb:154-177`）。本套件只跑 `spec/lock/lockfile_spec.rb`，其 artifice 引用 5 处：`:287`、`:380`、`:384`、`:388`、`:440`（均 `artifice: "endpoint_strict_basic_authentication"`）。

### 三步尝试与原始输出

1. `gem install artifice sinatra --no-document`（系统 GEM_HOME `C:\Ruby40-x64\lib\ruby\gems\4.0.0`）实际只装 sinatra：

```
Successfully installed rack-protection-4.2.2
Successfully installed sinatra-4.2.2
2 gems installed
```

`gem list -l` 实测（节选，全为本机真输出）：

```
sinatra (4.2.2)
rack-protection (4.2.2, 4.2.1)
rack (3.2.9, 3.2.8, 3.2.7, 3.2.6, 3.2.4, 3.1.12)
rack-test (2.3.0, 2.2.0)
tilt (2.9.0, 2.7.0, 2.6.0)
mustermann (3.1.1)
base64 (0.3.0)
cgi (0.5.2)
logger (1.7.0)
ruby2_keywords (0.0.5)
```

`artifice` 不在列表里，也不该在——该 gem 与 bundler 自带实现无关。

2. 隔离装 `--install-dir <worktree>\gems` + `GEM_PATH`：**未执行**。第 1 步已成功，按任务给定的优先序无需回退；未做无意义叠装。

3. require 验证（在 `.upstream-specs/v4.0.24/bundler` 下）：

```
SINATRA OK 4.2.2
RACKTEST OK 2.3.0
$ ruby -Ilib -Ispec -e "require 'artifice'"
-e:1:in 'Kernel#require': cannot load such file -- artifice (LoadError)   # 预期：不需要该 gem
$ ruby -Ilib -Ispec -e "require 'support/artifice/helpers/artifice'"
VENDORED-ARTIFICE OK
```

### 新基线（段三）

- 报告：主工作区 `.upstream-specs/upstream-lockfile-v4.0.24-20261123T085454Z.md`（17,218 B；`.upstream-specs/` 被 `.gitignore:8` 忽略，故不入库）。摘要原文：

```
## Result summary

64 examples, 50 failures

- real-drive: 69 celerite invocations
- harness verdict: ok (rspec exit 1)
```

- 脚本分桶：`env:artifice-unreachable (38)` / `env:low-il-shm (9)` / `fixture:fetch-failed (3)`；`product:candidates` 已归零。
- 按 `rspec-output.txt` 50 个失败块逐个扫 stderr 重判（不复用脚本按文案的归桶）：

| 签名 | 条数 | 原文关键行 |
| --- | --- | --- |
| artifice 桩不可达 | 38 | `Could not reach host gem.repo2. Check your network connection and try again.` |
| msys Low-IL git | 9 | `0 [main] sh (…): *** fatal error - NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-…): 0xC0000022` |
| 真网络 fetch | 3 | `Could not verify the SSL certificate for https://rubygems.org/.` → `Fetching bundler 1.8.2` |
| sinatra 加载失败 | **0** | —（旧桶的「加载缺口」已消除） |

### 例子级差集（旧 `47 failures` → 新 `50 failures`）

- **fail → pass（2）**：`lockfile_spec.rb[1:57:1:1]`、`[1:56:1:1]`（`with both ruby / just specific platform behaves like a lockfile missing dependent specs auto-heals`）。旧表在 `product:candidates` 桶，`RSpec::Expectations::ExpectationNotMetError`。**未证明与 sinatra 有关**：两例不走 artifice（只断言锁自愈），两次采集之间 `src/` 无改动，而 `tmp/2.1` 下的 fixture 缓存跨次复用，故按宿主/缓存态差异记，不计作修复。
- **fail → fail（45）**：其中 38 条为 `Could not reach host`（见下），7 条为 msys git clone。
- **改桶（1）**：`:1682`（`fills empty CHECKSUMS entries when not frozen, even if every gem is already installed`）旧在 `product:candidates` 桶，新表落进 `env:artifice-unreachable`——其失败体（第 40/50 块）与前 38 条同一签名 `Invoking … celerite install failed` + `Could not reach host`。故 `product:candidates` 归零是「2 条转绿 + 1 条改桶」的结果，不是三条都修好；`:1682` 的「离线不可验证」判断（见上文 task-140 段）不变。
- **新增失败（5）**：`:550`（serializes global git sources）、`:586`（git branch requirement）、`:477`（single pinned source, gem with a version requirement）、`:2144`（new gem includes a gem that shouldn't be included）、`:622`（git tag requirement）。五条全部止于同一处 msys 报错，随后 `fatal: Could not read from remote repository.`——与 task-158 记的 `:586` Low-IL 抖动同源，**不是 sinatra 装出来的，也不是产品回归**。
- 38 条仍失败的真因，原文样板（`generates a simple lockfile for a single source, gem`）：

```
RuntimeError:
  Invoking `C:/Users/ShiningRay/projects/ShiningRay/celerite/bin/celerite install` failed with output:
  ----------------------------------------------------------------------
  Could not reach host gem.repo2. Check your network connection and try again.
  ----------------------------------------------------------------------
# ./spec/support/command_execution.rb:25:in 'Spec::CommandExecution#raise_error!'
```

- 3 条 fetch 桶真因：`updates the lockfile's bundler version if current ver. is newer, and version was forced through BUNDLER_VERSION` 等三条要求按 `BUNDLER_VERSION` 回落到 bundler 1.8.2，输出为 `Could not verify the SSL certificate for https://rubygems.org/.`，即需要真网络，本机拿不到。

### 为什么不可达（机制，本次实证）

- `spec/support/helpers.rb:154-177`：`:artifice` 不是起服务器，而是 `requires << "#{Path.spec_dir}/support/artifice/#{artifice}.rb"`，再 `env["RUBYOPT"] = opt_add("-r#{r}", env["RUBYOPT"])`——让**子进程自己**加载桩；桩在子进程内替换 `Gem::Net::HTTP`，用 `Rack::Test` 直接投递请求（`rack_request.rb:12-20` 的 `def connect; end`）。全程**不开 socket**。
- celerite 是原生 exe：`script/upstream-specs-celerite-override.rb:39-40` 先 `options.delete(:load_path)` / `options.delete(:artifice)`，`:52-57` 再 `sys_exec("#{celerite} #{cmd}…")`。因此 celerite 无法加载 `-r` 的 Ruby 桩，只能真解析 `gem.repo1/2/4` 并连网。
- 推论：装 sinatra 只解除**参考侧进程**的加载障碍（0 处 LoadError），解除不了「原生子进程拿不到桩」。该桶的判定结论是 **real-drive 下恒不可达**，与 gem 清单无关。

### 边界

- 本次只改**本机 gem 环境**（`C:\Ruby40-x64\lib\ruby\gems\4.0.0` 新增 `sinatra 4.2.2`、`rack-protection 4.2.2`），**不在仓库里**；别人 clone 不会自动获得，CI 也不会。
- 未跑 `v2.7.2` 复采；未跑全量差分；未改 `src/`、`spec/`、`fixtures/`、`script/`、`docs/compat-claims/`、`docs/compat-report.md`、`docs/roadmap.md`。
- 主工作区 `bin/celerite.exe`（12,763,959 B，2026-11-23 16:43:33）为 `38021fc` 构建，本次未重建；本次仅在主工作区跑 `script/upstream-specs`，副作用是新增 1 份报告并覆写 `.upstream-specs/rspec-output.txt`、`rspec-output.json`、`celerite-invocations.log`；**未删任何既有报告**。
- 若要真跑这 38 条，需二者之一：(a) 参考侧 Ruby 驱动（非 real-drive）下跑，`-r` 桩可用；(b) 为 celerite 造「桩代理」通道（把 Rack app 跑成真 HTTP server，并让 celerite 的源 host 可改）。二者均为新工作量，本次未做。

### 已声明差异

- 「fail→pass 2 条与 sinatra 无关」是据机制（两例不走 artifice）与「`src/` 未改」推出的判断；旧 run 的原始 `rspec-output.txt` 已被本次覆写，无法逐字复核其 stderr，故标为**推断**而非实测。
- `env:low-il-shm` 9 条与新增 5 条同属宿主 msys 抖动，未重跑消抖；故 47→50 的净增 3 不得读作 sinatra 造成的回归，也不得读作产品劣化。
- 本节新基线与分桶不替代 `docs/compat-report.md` 的 `## Current metrics`（唯一对外口径）；如需改口径须另开任务并复采。

## 2026-11-23：50 条失败的逐条定性与分桶改名（task-193）

采集环境：worktree `C:\temp\celerite-t193`（HEAD `954f2d5`）；`bin/celerite.exe` 自工作区复制（SHA256 与主工作区一致 `C85A43CC…`）；`.upstream-specs` 为指向主工作区同名目录的 junction，复用同一 4.0.24 checkout 与夹具。命令 `/c/msys64/usr/bin/bash script/upstream-specs`，环境 `CELERITE_SKIP_TEST_DEPS=1 RSPEC_FORMATTER_OUTPUT_ID=celerite-harness`、`TMPDIR/TMP/TEMP/HOME=/c/temp`。harness exit 1（＝rspec status），报告 `.upstream-specs/upstream-lockfile-v4.0.24-20261123T132826Z.md`，`real-drive: 69 celerite invocations`。

结果：`64 examples, 45 failures`（19 passed），分桶 `env:out-of-process-artifice (44)` / `fixture:fetch-failed (1)` / `env:low-il-shm (0)` / `product:candidate (0)`。

与 task-178 末次基线（`64/50`，报告 `…T130235Z.md`）逐例比对：两轮失败用例的 full_description 集合只有 5 例差异，且这 5 例在 task-178 全属 `env:low-il-shm`，本轮转绿；反向差集为空（`only in new = 0`）。本轮 `rspec-output.txt` 中 `0xC0000022`、`NtCreateDirectoryObject`、`LoadError`、`sinatra` 各 0 次（task-178 的 `0xC0000022` 为 9 次），`Could not reach host` 49 次。据此：

- 5 例「转绿」是宿主 msys Low-IL 抖动，不是产品修复，不得记作关闭；
- 4 例原 low-il-shm 本轮错误面变为 `Could not reach host`，按规则表落入 artifice 桶（`script/upstream-specs-buckets.rb:44`）；
- 2 例原 `fixture:fetch-failed`（`:36`、`:87`）本轮同样以 `Could not reach host` 失败，改落 artifice 桶；
- 净失败数 50 → 45 全部可由上三条解释，无一例属于产品侧变化。

### 分桶前后对照

| task-178（`…T130235Z.md`） | 条数 | 本轮（`…T132826Z.md`） | 条数 | 说明 |
| --- | --- | --- | --- | --- |
| `env:artifice-unreachable` | 38 | `env:out-of-process-artifice` | 44 | 38 + 4（原 low-il 改判）+ 2（原 fetch 改判） |
| `env:low-il-shm` | 9 | `env:low-il-shm` | 0 | 5 例转绿、4 例改判 artifice |
| `fixture:fetch-failed` | 3 | `fixture:fetch-failed` | 1 | 2 例改判 artifice，余 1 例 `:175` |
| `product:candidate` | 0 | `product:candidate` | 0 | 两轮皆 0 |
| 合计 | 50 | | 45 | |

### 逐条定性表（50 条，按最终归因排序）

口径：本表覆盖 task-178 的 50 条失败；「本轮表现」列区分「失败（本轮，45 条）」与「本轮通过（5 条，task-178 为 `env:low-il-shm`）」。归因只取四类之一：`env:out-of-process-artifice`（桩无法跨进程注入，结构性）、`env:low-il-shm`（msys `0xC0000022` 族）、`fixture:fetch-failed`（夹具/宿主 fetch 缺件）、`product:candidate`（真产品分歧）。

| # | `spec/lock/lockfile_spec.rb` | 用例（full_description） | 归因 | 本轮表现 |
| --- | --- | --- | --- | --- |
| 1 | `:8` | the lockfile format generates a simple lockfile for a single source, gem | `env:out-of-process-artifice` | 失败（本轮） |
| 2 | `:36` | the lockfile format updates the lockfile's bundler version if current ver. is newer, and version was forced through BUNDLER_VERSION | `env:out-of-process-artifice` | 失败（本轮） |
| 3 | `:87` | the lockfile format does not update the lockfile's bundler version if nothing changed during bundle install, but uses the locked version | `env:out-of-process-artifice` | 失败（本轮） |
| 4 | `:138` | the lockfile format adds the BUNDLED WITH section if not present | `env:out-of-process-artifice` | 失败（本轮） |
| 5 | `:222` | the lockfile format generates a simple lockfile for a single source, gem with dependencies | `env:out-of-process-artifice` | 失败（本轮） |
| 6 | `:253` | the lockfile format generates a simple lockfile for a single source, gem with a version requirement | `env:out-of-process-artifice` | 失败（本轮） |
| 7 | `:284` | the lockfile format generates a lockfile without credentials | `env:out-of-process-artifice` | 失败（本轮） |
| 8 | `:331` | the lockfile format does not add credentials to lockfile when it does not have them already | `env:out-of-process-artifice` | 失败（本轮） |
| 9 | `:392` | the lockfile format keeps credentials in lockfile if already there | `env:out-of-process-artifice` | 失败（本轮） |
| 10 | `:445` | the lockfile format generates lockfiles with multiple requirements | `env:out-of-process-artifice` | 失败（本轮） |
| 11 | `:511` | the lockfile format does not asplode when a platform specific dependency is present and the Gemfile has not been resolved on that platform | `env:out-of-process-artifice` | 失败（本轮） |
| 12 | `:658` | the lockfile format is conservative with dependencies of git gems | `env:out-of-process-artifice` | 失败（本轮） |
| 13 | `:813` | the lockfile format sorts serialized sources by type | `env:out-of-process-artifice` | 失败（本轮） |
| 14 | `:861` | the lockfile format removes redundant sources | `env:out-of-process-artifice` | 失败（本轮） |
| 15 | `:889` | the lockfile format lists gems alphabetically | `env:out-of-process-artifice` | 失败（本轮） |
| 16 | `:932` | the lockfile format orders dependencies' dependencies in alphabetical order | `env:out-of-process-artifice` | 失败（本轮） |
| 17 | `:981` | the lockfile format orders dependencies by version | `env:out-of-process-artifice` | 失败（本轮） |
| 18 | `:1022` | the lockfile format does not add the :require option to the lockfile | `env:out-of-process-artifice` | 失败（本轮） |
| 19 | `:1053` | the lockfile format does not add the :group option to the lockfile | `env:out-of-process-artifice` | 失败（本轮） |
| 20 | `:1222` | the lockfile format keeps existing platforms in the lockfile | `env:out-of-process-artifice` | 失败（本轮） |
| 21 | `:1268` | the lockfile format adds compatible platform specific variants to the lockfile, even if resolution fallback to ruby due to some other incompatible platform specific variant | `env:out-of-process-artifice` | 失败（本轮） |
| 22 | `:1313` | the lockfile format persists the spec's specific platform to the lockfile | `env:out-of-process-artifice` | 失败（本轮） |
| 23 | `:1348` | the lockfile format does not add duplicate gems | `env:out-of-process-artifice` | 失败（本轮） |
| 24 | `:1384` | the lockfile format does not add duplicate dependencies | `env:out-of-process-artifice` | 失败（本轮） |
| 25 | `:1412` | the lockfile format does not add duplicate dependencies with versions | `env:out-of-process-artifice` | 失败（本轮） |
| 26 | `:1440` | the lockfile format does not add duplicate dependencies in different groups | `env:out-of-process-artifice` | 失败（本轮） |
| 27 | `:1490` | the lockfile format works correctly with multiple version dependencies | `env:out-of-process-artifice` | 失败（本轮） |
| 28 | `:1517` | the lockfile format captures the Ruby version in the lockfile | `env:out-of-process-artifice` | 失败（本轮） |
| 29 | `:1548` | the lockfile format automatically fixes the lockfile when it's missing deps | `env:out-of-process-artifice` | 失败（本轮） |
| 30 | `:1589` | the lockfile format raises a clear error when frozen mode is set and lockfile is missing deps, and does not install any gems | `env:out-of-process-artifice` | 失败（本轮） |
| 31 | `:1615` | the lockfile format raises a clear error when frozen mode is set and lockfile is missing entries in CHECKSUMS section, and does not install any gems | `env:out-of-process-artifice` | 失败（本轮） |
| 32 | `:1682` | the lockfile format fills empty CHECKSUMS entries when not frozen, even if every gem is already installed | `env:out-of-process-artifice` | 失败（本轮） |
| 33 | `:1712` | the lockfile format automatically fixes the lockfile when it's missing deps, they conflict with other locked deps, but conflicts are fixable | `env:out-of-process-artifice` | 失败（本轮） |
| 34 | `:1771` | the lockfile format automatically fixes the lockfile when it's missing multiple deps, they conflict with other locked deps, but conflicts are fixable | `env:out-of-process-artifice` | 失败（本轮） |
| 35 | `:1834` | the lockfile format raises a resolution error when lockfile is missing deps, they conflict with other locked deps, and conflicts are not fixable | `env:out-of-process-artifice` | 失败（本轮） |
| 36 | `:1882` | the lockfile format regenerates a lockfile with no specs | `env:out-of-process-artifice` | 失败（本轮） |
| 37 | `:1974` | the lockfile format automatically fixes the lockfile when it includes a gem under the correct GIT section, but also under an incorrect GEM section, with a higher version, and with no explicit Gemfile requirement | `env:out-of-process-artifice` | 失败（本轮） |
| 38 | `:2031` | the lockfile format automatically fixes the lockfile when it includes a gem under the correct GIT section, but also under an incorrect GEM section, with a higher version | `env:out-of-process-artifice` | 失败（本轮） |
| 39 | `:2281` | the lockfile format auto-heals when the lockfile is missing specs | `env:out-of-process-artifice` | 失败（本轮） |
| 40 | `:2349` | the lockfile format a line ending generates Gemfile.lock with \n line endings | `env:out-of-process-artifice` | 失败（本轮） |
| 41 | `:2355` | the lockfile format a line ending during updates preserves Gemfile.lock \n line endings | `env:out-of-process-artifice` | 失败（本轮） |
| 42 | `:2367` | the lockfile format a line ending during updates preserves Gemfile.lock \r\n line endings | `env:out-of-process-artifice` | 失败（本轮） |
| 43 | `:2386` | the lockfile format a line ending when nothing changes preserves Gemfile.lock \n line endings | `env:out-of-process-artifice` | 失败（本轮） |
| 44 | `:2395` | the lockfile format a line ending when nothing changes preserves Gemfile.lock \r\n line endings | `env:out-of-process-artifice` | 失败（本轮） |
| 45 | `:477` | the lockfile format generates a simple lockfile for a single pinned source, gem with a version requirement | `env:low-il-shm` | 本轮通过 |
| 46 | `:550` | the lockfile format serializes global git sources | `env:low-il-shm` | 本轮通过 |
| 47 | `:586` | the lockfile format generates a lockfile with a ref for a single pinned source, git gem with a branch requirement | `env:low-il-shm` | 本轮通过 |
| 48 | `:622` | the lockfile format generates a lockfile with a ref for a single pinned source, git gem with a tag requirement | `env:low-il-shm` | 本轮通过 |
| 49 | `:2144` | the lockfile format successfully updates the lockfile when a new gem is added in the Gemfile includes a gem that shouldn't be included | `env:low-il-shm` | 本轮通过 |
| 50 | `:175` | the lockfile format update the bundler major version just fine | `fixture:fetch-failed` | 失败（本轮） |

### 四个归因类别的判据出处

- `env:out-of-process-artifice`（44 条）：上游 `bundler/spec/support/helpers.rb:154-177` 用 `env["RUBYOPT"] = opt_add("-r#{r}", env["RUBYOPT"])` 把 artifice 桩注入 **Ruby 子进程**；装具 `script/upstream-specs-celerite-override.rb:39-41` 删掉 `:requires`/`:load_path`/`:artifice`，`:57-59` 用 `sys_exec` 起原生 `bin/celerite` ⇒ 桩永不加载，celerite 按真网访问 `https://gem.repo{1..4}` 得到 `Could not reach host`。本轮 `LoadError` 与 `sinatra` 各 0 次，排除「缺 gem」解释。该桶在 real-drive 下结构性不可判定，非产品缺口。
- `env:low-il-shm`（5 条，本轮通过）：task-178 报 `NtCreateDirectoryObject … 0xC0000022`，属宿主 msys Low-IL 限制；本轮未复现，故按「环境族、未消除」保留。
- `fixture:fetch-failed`（1 条，`:175`）：`rspec-output.txt` 原文为 `Bundler 4.0.24 is running, but your lockfile was generated with 1.8.2 … Installing Bundler 1.8.2 and restarting using that version.` 与 `Fetching bundler 1.8.2`，即 celerite 自装 bundler 时访问真 `https://rubygems.org/`；严格说不是夹具缺件，而是宿主真网 fetch 失败。桶名按规则表保持 `fixture:fetch-failed`，判定逻辑未改。
- `product:candidate`（0 条）：3 条 `RSpec::Expectations::ExpectationNotMetError`（`:43`、`:44`、`:49`）经查其记录里子命令以 `# $? => 17` 结束、输出为 `Could not reach host …`，断言失败源于命令报错而非锁体字节差异；全表无一例能给出「参考行为 vs 我方输出」的逐字差异，故不判 product。

### 改桶的代码位置

- `script/upstream-specs-buckets.rb:11`（规则表第 1 行）、`:31`（`ORDER` 首元素）、`:44`（`classify` 首条 `return`）：字符串 `env:artifice-unreachable` → `env:out-of-process-artifice`，并把规则表列宽 24 放宽到 28 以容纳新名。
- 文件末尾追加 12 行 `# task-193 renamed bucket 1 …` 注释，写明跨进程不可判定的机制与「非产品缺口」边界。
- `classify` 的判定条件（`text.include?("Could not reach host")`）与桶序**未改**；`script/upstream-specs` 未改；新增的 12 行注释落在 `end` 之后（第 57 行起），`:7-19`、`:11`、`:30-37`、`:31`、`:42`、`:44` 等既有行号引用不变。`ruby -c script/upstream-specs-buckets.rb` 输出 `Syntax OK`。
- 历史节里的旧桶名（本文件 `:31`、`:124`、`:144`、`:153`、`:233`、`:258`、`:366`、`:387`、`:391-396`、`:487`、`:501` 以及 `docs/compat-evidence/2026-11-19.md`、`2026-11-20.md`、`2026-11-21.md`、`2026-11-22.md` 的相关行）一律保留原样，不回改。

### product:candidate 结论

`product:candidate = 0`：50 条失败全部落在 `env:out-of-process-artifice`（44）、`env:low-il-shm`（5）、`fixture:fetch-failed`（1）三类环境/结构桶，没有一例具备「参考行为 vs 我方行为」的逐字差异证据。本轮**没有**新的产品候选需要逐项关闭。

### 三个分句的判定与 M7-8 勾选建议

1. ①「真实驱动」：成立——`real-drive: 69 celerite invocations`，harness 同时自证 `upstream checkout integrity: ok`；60 秒内起 69 次原生 exe 不可能是空转。
2. ②「退出码反映失败」：成立——harness exit 1 ＝ rspec status；69（环境不可用）/70（未驱动）分支未触发，也不是 0。
3. ③「保留当前失败基线，再逐项关闭」：形式上成立——两轮基线（`64/50` 与 `64/45`）并列保留、50 条逐条定性完成、`product:candidate` 归零；但「逐项关闭」的剩余对象只剩环境/结构桶：artifice 桶在 real-drive 下结构性不可判定，low-il 与 fetch 两桶依赖宿主环境，均无产品侧可关闭项。
4. 勾选建议：M7-8 可以勾 `[x]`——三个分句都有可复核证据，剩余失败无产品候选，且 bucket 语义已如实改判。但 `docs/roadmap.md:148` 的复选框改动由首辅决定，本节不改该文件。

### 未验证 / 已知缺口

- 本轮失败数比 task-178 少 5（50→45），其中 5 例转绿属宿主抖动、4+2 例改判；两次采集未在**相同启动路径**下重复（本轮经 junction 路径、task-178 经主工作区路径），故「45 与 50 谁更接近稳态」未验证，基线按各自环境如实并列记录，不改写历史节。
- artifice 桶的 44 条没有一条取得过参考侧（Ruby 驱动、桩可用）下的期望输出，因此「改判为环境族」依据的是机制（桩进不了子进程）而非逐条 oracle 对照；若要逐条 oracle，需另做「桩代理」通道。
- `product:candidate = 0` 是对**本轮 45 条实测失败**与 50 条全集定性后的结论；若将来宿主环境变得干净（无 low-il、无 fetch 失败）而失败数不降，则必须重开 product 定性。

## 2026-11-23：M7-8 行闭合判据复审（task-205）

审题：只读复审 `docs/roadmap.md` 的 M7-8 行能否勾 `[x]`。被审行逐字（`docs/roadmap.md:148`）：

`- [ ] 修复 `script/upstream-specs`：使锁文件族真实驱动 Celerite，退出码反映失败；保留当前 47 failures 作为失败基线，再逐项关闭。（实证流水逐字迁出至 `docs/roadmap-evidence/M7-8-upstream-specs.md`）`

同段 :153 验收标准逐字：「锁文件上游族真实执行且结果如实」。

### oracle

- 上游基线口径：`docs/compat-report.md` 的 `Current metrics` 节（本轮读到时为 `64 examples, 45 failures`）与 `docs/compat-matrix/generated/upstream-lockfile-v4.0.24.md`。
- 文档自证 oracle：task-193 采集产物 `.upstream-specs/upstream-lockfile-v4.0.24-20261123T132826Z.md`（44 artifice / 1 fetch / 0 low-il / 0 product）。
- 判据命令 oracle：`script/differential` 的 reference Bundler 4.0.24 对照（reference 与 celerite 的 stdout/退出码/文件内容逐项 assert）与 `crystal spec`。

### 参考锚点

- task-178 节记录的桩注入机制：`spec/support/helpers.rb:154-177` 用 `RUBYOPT=-r<artifice>.rb` 把桩注入子进程；`script/upstream-specs-celerite-override.rb:39-40` 删掉 `:load_path`/`:artifice`、`:52-57` 用 `sys_exec` 起原生 exe。
- claims `C-M7-8-001`（PATH shim 路由）、`C-M7-8-002`（`CELERITE_BUNDLE_HELPER_OVERRIDE=0` 退回基线并打印 `WARNING: NOT driving celerite`）、`C-M7-8-003`（pipefail 传退出码）、`C-M7-8-005`（七桶规则模块）、`C-M7-8-020`（桶改名依据）。

### 实现位置

- `script/upstream-specs:52` 为 `set -uo pipefail`；`:369` 为 `rspec_status=$?`；`:445-446` 为 `harness_rc=$rspec_status` 与 `verdict="ok (rspec exit $rspec_status)"`；`:482` 打印 `real-drive:` 计数；`:484` 打印 `WARNING: NOT driving celerite`。
- 桶规则：`script/upstream-specs-buckets.rb`（claims 005/020 所指的规则表、`ORDER`、`classify` 与文件末注释）。
- 本轮抽跑触发的失败点：`src/celerite/cli/commands_install.cr:44` `class ProcessLock`、`:50` path 为 `<bundle_path>/bundler.lock`、`:51` `io = File.open(path, "a+")`。

### 证据

1. 本机抽跑（2026-11-24，worktree `C:\temp\celerite-t205` @ 302cbae，PATH 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;`，TMP/TMPDIR/TEMP/HOME=`C:\temp`）：
   - `crystal spec spec/m7_checksums_trigger_spec.cr` → `8 examples, 0 failures, 0 errors, 0 pending`，EXIT 0（13.9s）。首次不带 msys PATH 时编译中断：`Error: error executing command: sh -c 'hash pkg-config ...': 系统找不到指定的文件。`
   - `crystal spec spec/m7_lock_autoheal_spec.cr` → `6 examples, 0 failures, 0 errors, 0 pending`，EXIT 0（9.0s）。
   - `bash script/differential checksums-refresh-cache-deleted`（`CELERITE_BIN` 指主工作区 2026-11-24 00:28 构建的 `bin/celerite.exe`，12,787,736 B；主工作区 HEAD 同为 302cbae）→ FAIL，EXIT 1，三处工作根各复现一次（worktree 默认 `.d`、`CELERITE_DIFF_WORK_ROOT=C:\temp\d205`、主工作区 `C:\temp\d205m`），失败原文：`celerite internal error: Error opening file with mode 'a+': 'C:\\temp\\...\\cel\\bundle\\bundler.lock': 拒绝访问。`；reference=0 / celerite=1；celerite 侧 stdout 全缺（`Fetching source index from file:///…/fixtures/gem-index/`、`Resolving dependencies...`、`Bundle complete! …`、`Bundled gems are installed into …` 均无）；`file-equals` 差为 ref 有 `bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc` 与 `json_pure (2.8.1)`、cel 只有 `bundler (4.0.24)`。
   - `ruby -c script/upstream-specs-buckets.rb` → `Syntax OK`。
   - 按任务书禁跑 `script/upstream-specs`，故 harness 侧本轮无新采集。
2. 四处口径核对（节标题定位），不一致 5 条：
   - ① `docs/roadmap.md` 的 M7-8 行与非复选框正文仍写「保留当前 47 failures 作为失败基线」；`docs/compat-report.md` 的 `Current metrics` 已是 `64 examples, 45 failures`（2026-11-23 task-193 复采）。47 只在更早的 superseded 记录与 task-158 节出现。
   - ② `README.md` 的上游基线 bullet 逐字称「current v4.0.24 lockfile baseline: 64 examples, 50 failed / 14 passed; buckets artifice-unreachable 38 / low-IL 9 / fixture:fetch-failed 3, with product:candidates at zero; real-drive 69 celerite invocations, harness verdict `ok`; collected 2026-11-23 by task-178, kept current in [the compatibility report](docs/compat-report.md) under `Current metrics`.」——它把 50 称作 current 并指向 `Current metrics`，而该节实为 45/44/1/0。
   - ③ 同一 README bullet 仍用旧桶名 `artifice-unreachable`（及 `low-IL` 简写），与 task-193 改名后的 `env:out-of-process-artifice` / `env:low-il-shm` 不一致；claims `C-M7-8-020` 与 `docs/compat-report.md` 的 `Current metrics` 用新名。
   - ④ `docs/compat-report.md` 的 `Upstream spec suite coverage boundary` 节仍称「The recorded result under `docs/compat-matrix/generated/upstream-lockfile-v4.0.24.md` is **64 examples, 53 failures** (11 passed; 2026-11-22 task-114 采集), still not a passing gate. It is retained as a failure baseline for M7.」，其紧随的加注又称该值已被 `64 examples, 47 failures`（17 passed）取代；同一文件并存 45（Current metrics）/ 53（boundary 的 recorded result）/ 47（加注的取代值）三个「基线」。
   - ⑤ `docs/compat-claims/M7-8-upstream-specs.md` 的 `C-M7-8-017`（已声明差异）仍记两条 product 候选 `spec/lock/lockfile_spec.rb:1682` 与 `:2215` 未取 oracle、未修，而 task-193 节与 `docs/compat-report.md` 的 `Current metrics` 记 `product:candidates 0`（`:1682` 已归 env 桶、`:2215` 因 `--local` 修好而转绿）；claims 未随 task-193 复采更新。
   - 另：任务分派文字给出的「50 failures / artifice 36 / low-il 8 / fetch 3」与任何文档均不符——50 的分桶在 task-178 节是 38/9/3，且 36+8+3=47 与 50 自相矛盾。
3. claims 状态分布（本轮只读统计，不改）：共 20 条，`已实现 16`（001-003、005-015、018、019）、`已声明差异 3`（004、017、020）、`未验证 1`（016）。
4. claims 精确行号可复核性：003 记 `script/upstream-specs:29` 为 `set -uo pipefail`、`:184` 为 `rspec_status=$?`、`:257` 为 `WARNING: NOT driving celerite`；实际为 `:52`、`:369`、`:484`。退出码通路实质存在，但 claims 记的行号已漂移。

### 已声明差异

- 44 条 `env:out-of-process-artifice`：RSpec 经 `RUBYOPT` 把 artifice 桩注入子进程，而 override 删 `:load_path`/`:artifice` 并用 `sys_exec` 起原生 exe，桩进不了 celerite 进程 ⇒ real-drive 下结构性不可判定（claims 020）。不算缺口。
- 1 条 `fixture:fetch-failed`（`spec/lock/lockfile_spec.rb:175`）：需真实网络取源，宿主离线即失败。不算缺口。
- 本轮 `env:low-il-shm` 为 0（task-178 的 9 条在本轮转绿，归宿主抖动）。
- claims 004：M7 基线只覆盖 lockfile 家族，不含全套上游 spec。不算缺口。
- claims 016：2.7.2 分支本轮未复采。
- 顺序：`docs/roadmap.md` 的 M7-8 行要求「47 failures」，与 task-193 的 45 属两轮采集并列，非矛盾；但 checkbox 与行内数字未随复采更新。

### 未验证

- 「45 与 50 谁更接近稳态」仍未验证：两次采集启动路径不同（task-193 经 worktree 路径，task-178 经主工作区），本轮未重跑 9 分钟套件。
- 44 条 artifice 无逐条 oracle，改判依据是机制而非参考侧期望输出（延续 task-193 缺口）。
- 本机 `bash script/differential checksums-refresh-cache-deleted` 三处工作根全红，根因未定性：`ProcessLock` 以 `a+` 打开 `<bundle_path>/bundler.lock` 被拒（`拒绝访问`），三处同形，疑宿主写权限/低完整性级，亦可能是 HEAD 回归；与 `docs/compat-report.md` 记 4.0.24 全量差分 468 passed/0 failed 矛盾，须在官方装具环境复跑才能定性。
- 「逐项关闭」是否有产品侧剩余对象：本机只抽跑 3 条判据、未重跑套件，故只能依据 task-193 的 50 条逐条表，不能独立确认 `product:candidates` 仍为 0。

### 三分句判定与勾选

1. ①「使锁文件族真实驱动 Celerite」：**满足**。依据 task-193 的 `real-drive: 69 celerite invocations`、`upstream checkout integrity: ok`、`harness verdict: ok`，claims 001/002/015；本轮未独立复跑（未验证项）。
2. ②「退出码反映失败」：**满足**。`script/upstream-specs:52` pipefail、`:369` 捕 rspec status、`:445-446` 传出，task-193 harness exit 1（`ok (rspec exit 1)`）。
3. ③「保留当前 47 failures 作为失败基线，再逐项关闭」：**不满足（字面）**。47 已非当前口径（report 45 / README 50 / boundary 53）；45 条仍红，「关闭」实际是改判环境桶，`product:candidates 0` 只说明无产品对象可关，不等于「逐项关闭」达成；且 claims 017 仍列两条未处置的 product 候选，与 0 的结论冲突。
4. 结论：**按现文不勾 `[x]`**。可收口项（纯文档）：把 roadmap 行、README bullet、report 的 `Upstream spec suite coverage boundary`、claims 017 统一到 45/44/1/0 与新桶名；③ 的判据措辞需首辅裁决改写为「`product:candidates` 归零 + 环境桶逐条定性并声明不可判定」后方可勾选，本轮不改 roadmap。已声明差异（44 artifice + 1 fetch + low-il 0 + 只覆盖 lockfile 家族 + 2.7.2 未复采）不计入缺口。
### 首辅复核（2026-11-24）

- 上节「未验证」里那条 checksums-refresh-cache-deleted 三处工作根全红，经首辅在本仓官方配方下复核**不复现**：worktree ` `C:\temp\celerite-acc202` ` @ `302cbae`、TMPDIR=/c/temp、CELERITE_BIN=<该 worktree>\bin\celerite.exe、PATH 前置 msys/ucrt64/Ruby40 后跑 ash script/differential checksums-refresh-cache-deleted → `PASS checksums-refresh-cache-deleted (exit=0)` / `1 passed, 0 failed` / EXIT 0。审计者那次把 `TMP`/`TMPDIR`/`TEMP`/`HOME` 都指向 `C:\temp`（而非工作区内目录），与本仓既定配方不符，其 undler.lock 被拒属该配置下的宿主权限现象，**不是产品回归**，也不构成对 4.0.24 全量 468/0 的否定。
- 因此该条从「未验证（疑回归）」下调为「已排除（审计环境配置问题）」；其余未验证项（45 与 50 的稳态、artifice 逐条 oracle、product:candidates 独立复核）保持不变。
