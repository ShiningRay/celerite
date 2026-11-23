# M7 文档与状态同步（README/兼容报告/roadmap）

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 163 -->

**（进行中，2026-11-10：compat-report/roadmap/README 已按 HEAD=8e91a2f 与本迭代脚本/文档变更做保守对齐，未重跑门禁的结果标未验证；需后续迭代持续同步。）** 

**2026-11-19（task-30 收口）：判据拆为三组逐条清零——README A1–A7（安装命令、沙箱网络、断言清单、能力状态、矩阵来源、开发前置、上游基线）、compat-matrix generated B（CLI 头注与上游基线）、roadmap C（L154/155/156/159/161/162 内联补记）；本轮仅改文档，不改产品代码。复选框保持 `[ ]`。** 

**2026-11-19（task-39 漂移校正）：README/roadmap/compat-matrix 的过期能力、基线数字与锚点已按实测更正，历史结论用“已被…取代/历史快照”标注，未改旧文。复选框保持 `[ ]`。** 

**2026-11-20（task-61 同步）：README 状态块补 task-52…60 能力、上游基线改注 33–59、deferred 计数改为 12/5 并列出名单、探针锚点按 `script/differential` 实测行号更新、补 cmdglob 机制与运行期/开发期差分边界；compat-matrix README 区分手写四文件与 `generated/*` 并登记生成物 mtime；差分报告标题与文件名对齐；task-55 的 `*.gemspec` 归一化改指 cmdglob。仍未闭：A3 探针锚点随脚本改动会再漂移、B 组矩阵索引未覆盖全部生成物、C 组 cmdglob 机制仅在 README 与 `docs/compat-evidence/2026-11-20.md` 说明。**

## 2026-11-23：README 度量与 spec 前提的实测校正（task-176）

**oracle**
- 差分 deferred 计数：`fixtures/differential/*/deferred-<version>` 标记文件本身；`script/differential:742-743` 按该标记跳过，标记是唯一真源，别处数字均为派生。
- 上游 lockfile 套件：`.upstream-specs/upstream-lockfile-v4.0.24-20261122T190748Z.md` 的 `Result summary`（`:19-22`）、`Failure buckets` 三段标题（`:26`、`:70`、`:76`）与 `Output tail`（`:91`）。
- 探针与标记行号：`script/differential` 本体（`Select-String` 实测行号）。
- spec 前提：`spec/m7_add_strict_write_spec.cr` 的 `code.should eq(7)`（`:79`、`:95`，改后行号）；环境约束以 `docs/compat-claims/M7-suite.md` 的 `C-M7-suite-004` 前提 (f) 为准。
- 本轮只改描述文字与注释，不改任何断言、不改 spec 名、不碰 `src/`。

**参考锚点**
- `docs/compat-report.md` 的 `## Current metrics`「上游 lockfile 套件」行：`64 examples, 47 failures`（17 passed；artifice-unreachable 41、fixture:fetch-failed 3、product:candidates 3；real-drive 69、`harness verdict: ok`）。
- `docs/compat-claims/M7-suite.md` 的 `C-M7-suite-004` 前提 (f)：临时根距盘符 67 字符断点（67 → 0 failures；68 → 4；69–70 → 6；71 及以上 → 7），断点与 `Dir.tempdir` 下 `.bundle/cache/compact_index/…` 的深度吻合。
- 上游源码（spec 头注释原有引用，未改）：`bundler-4.0.24/lib/bundler/injector.rb:44-50`、`lib/bundler/cli/add.rb:22`。
- 宽度来源：`src/celerite/cli.cr:57-63`——`THOR_COLUMNS` 合法（≥10）则取之，否则回落 `DEFAULT_TERMINAL_WIDTH = 80`（`src/celerite/cli.cr:19`）。

**实现位置**
- `README.md`：Goals 的上游基线条目（改后 `:47-56`）、Development 的 deferred 与探针段落（改后 `:137-152`）。
- `spec/m7_add_strict_write_spec.cr`：文件头注释块，新增 12 行（`:9-20`）。
- 证据本文件：`docs/roadmap-evidence/M7-docs-sync.md` 末尾。

**证据**

README「原文 → 实测 → 出处 → 改后」逐条：

| # | 改前位置 | 原文 | 实测 | 出处 | 改后 |
| --- | --- | --- | --- | --- | --- |
| A | `README.md:48-51` | `current v4.0.24 lockfile baseline: 64 examples, 54 failed / 10 passed; buckets artifice 38 / low-IL 8 / fetch 6 / product 2, collected 2026-11-19 16:32 by task-32; not recollected after tasks 33–59` | `64 examples, 47 failures`（17 passed）；artifice-unreachable 41 / fixture:fetch-failed 3 / product:candidates 3；real-drive 69；harness verdict `ok` | 锁文件 `:19`、`:21`、`:26`、`:70`、`:76`、`:91`；`docs/compat-report.md` `Current metrics` 同值 | 当前值改 47 failed / 17 passed + 新分桶 + real-drive 69，采集日改 2026-11-22 并指向 `Current metrics`；2026-11-19 的 `64 / 54 / 10` 与旧分桶按原文保留在括注，标 superseded，未删 |
| B | `README.md:133` | `12 fixtures are deferred for the 2.7.2 profile`（后列 12 名） | 26（实测名单：add-group、add-option-conflicts、cache-all-path、cache-all-platforms、cache-path-removed、cache-rerun-existing-cache、check-frozen-extra-locked-spec、check-frozen-locked-version-mismatch、check-frozen-missing-locked-spec、check-path-removed、config-deprecated-get、config-get-user-cache、doctor-default-cli-command、gem-default、gem-did-you-mean、gem-no-git、git-submodules、install-force-ruby-platform-locked、install-path-source-app-cache-first、issue-no-gemfile、plugin-source-disabled、pristine-name-suggestion、removed-viz、update-group-missing、update-group-present、update-name-suggestion） | `(Get-ChildItem -Recurse fixtures\differential -Filter deferred-2.7.2).Count` = 26 | 改 26 并列全 26 名；原 12 名一字未删，只是补齐为全量 |
| C | `README.md:137-138` | `5 for 4.0.24 (cache-all-platforms, git-submodules, issue-no-gemfile, plugin-source-disabled, show-outdated-verbose-272)` | 5，名单逐字一致 | `(Get-ChildItem -Recurse fixtures\differential -Filter deferred-4.0.24).Count` = 5 | 数值与名单未改 |
| D | `README.md:139` | 标记锚点 `script/differential:638-639` | 742-743 | `script/differential:742`（`if [ -f "$fixture/deferred-$bundler_version" ]`）、`:743`（SKIP 输出） | `:742-743` |
| E | `README.md:141-142` | `installed-tree` (`:509`)、`first-line` (`:520`)、`file-equals` (`:528-535`)、`file-contains` (`:553`)、`file-absent` (`:569`) | `:593`、`:604`、`:612-629`、`:634-645`、`:648-664` | `script/differential` 同名标记实现块（`:590-593`、`:601-604`、`:612-629`、`:634-645`、`:648-664`） | 五个锚点按实测改正 |
| F | — | README 无夹具总数断言 | 460（`e05a50d`）；`75bafcc` 为 457；460 个目录全部含 `command` | `(Get-ChildItem fixtures\differential -Directory).Count` = 460；`git ls-tree -d --name-only 75bafcc fixtures/differential/` = 457 | 未在 README 新增（计数归 `docs/compat-report.md` 的 `Current metrics`，该文件本轮禁改；其旧值 457 见「已声明差异」） |
| G | — | README 无 spec 文件数断言 | `spec/*.cr` = 200；`spec/m7_*.cr` = 179 | `(Get-ChildItem spec -Filter "*.cr" -Recurse).Count`、`(Get-ChildItem spec -Filter "m7_*.cr").Count` | 未改 |
| H | — | README 无 HEAD 短哈希断言 | `e05a50d` | `git log --oneline -1` | 未改 |

spec 头注释最终文本（`spec/m7_add_strict_write_spec.cr:9-20`，插在 task-167 的 `# keeps its original bytes.` 之后、`private def add_strict_index` 之前）：

```text
#
# Prerequisite: run this spec with its temporary root at most 67 characters from
# the drive letter, and point `TMPDIR`, `TMP`, `TEMP`, `HOME` and `USERPROFILE`
# all at that one root (see `docs/compat-report.md`, `Environment`, and
# precondition (f) of `C-M7-suite-004` in `docs/compat-claims/M7-suite.md`).
# With a longer root the bridge's own bundle cache path
# `home/.bundle/cache/compact_index/<hash>-<slug>/info-*` crosses the Windows
# `MAX_PATH` limit and the run dies with
# `celerite internal error: Unable to create directory: …: 文件名或扩展名太长。`,
# which makes `add` exit 1 instead of the 7 asserted below. That is an
# environment constraint of the same family as precondition (f), **not** a
# difference in product behaviour.
```

四条「写死列宽」隐患的逐条判断（只判断，未改这些文件）：

| 位置 | 断言形态 | 判断 | 理由 |
| --- | --- | --- | --- |
| `spec/m7_certificate_failure_spec.cr:82-101` | `THOR_COLUMNS=200`；`err.gsub(/\s+/, " ").strip.should eq(certificate_failure_message(port).gsub(/\s+/, " ").strip)` | **不脆** | 断言折叠空白后的整句，折行位置被显式抹平，列宽只决定折不折、不决定措辞；200 列远宽于该句，也不会因路径长度变化而红 |
| `spec/m7_fund_group_spec.cr:189-209` | `err.should eq("The path\n`#{missing}`\ndoes not exist.\n")`（整行文本，未设宽）+ 随后 `THOR_COLUMNS=1000` 的单行对照 | **脆** | `:192` 把折行点写死，而折行点由默认 80 列与 `missing` 的绝对路径长度共同决定；该 spec 未先清 `THOR_COLUMNS`，外层环境若带合法 `THOR_COLUMNS` 或临时根长度变化使路径跨列，`:192` 即假红（同机理见 `spec/m7_remove_failure_modes_spec.cr:91` 与 `C-M7-suite-004` 前提 (f)）；`:196-202` 的 1000 列对照本身不脆，只证明宽度由终端决定，替代不了默认宽度下的真实折行 |
| `spec/m7_network_down_spec.cr:40-59` | `THOR_COLUMNS=200`；`err.chomp.should eq("Could not reach host 127.0.0.1:#{port}. Check your network connection and try again.")` | **不脆** | 断言 chomp 后整串等于单行原句，等于要求 200 列下不得折行——真折了立即红，不掩盖；端口 4/5 位的变化远在 200 列内 |
| `spec/m7_plugin_bad_event_spec.cr:129-147` | 不设 `THOR_COLUMNS`；`err.lines.map(&.chomp).reject(&.empty?).should eq([...3 条写死文本])` | **脆** | 折行点写死成 80 列形态，宽度却继承外层环境；`src/celerite/cli.cr:57-63` 只在 `THOR_COLUMNS` 缺失或 <10 时回落 80，外层带一个合法值即换折法而假红。它不掩盖真实重折（换折会红），风险是环境继承造成的假红；缺的正是第 1、3 条那种显式钉宽 |

**已声明差异**
- README 的 2026-11-19（task-32）快照按治理规则保留原文：`64 examples, 54 failed / 10 passed` 与旧分桶（artifice 38 / low-IL 8 / fetch 6 / product 2）仍在文中，只标 superseded 并注明是历史记录；数字未删未改。
- `fixtures/differential` 实测 460，而 `docs/compat-report.md` 的「差分夹具总数」仍记 457（task-169 于 `75bafcc` 实测）。差额来自 `75bafcc..e05a50d` 新增的 3 个夹具目录（`gemfile-env-missing`、`install-keeps-lock-with-bundler-edge`、`plugin-git-install`；`add-strict` 是在已有目录内加 `file-contains`）。README 无夹具总数断言故未动；按本轮禁令未改 `docs/compat-report.md`，仅在此登记，待派后续任务订正。
- 上游套件的采集日在锁文件里写作 2026-11-22（`Generated by script/upstream-specs on 2026-11-22`），与 `Current metrics` 的 2026-11-23 记录日相差一天；两者数值一致（64 / 47 / real-drive 69 / verdict ok），README 采用锁文件自述日期并指向 `Current metrics`，不合并两个日期。
- 四条列宽隐患只判断、不改文件（任务明令不改）：`m7_fund_group_spec.cr:192` 与 `m7_plugin_bad_event_spec.cr:143-147` 判脆，`m7_certificate_failure_spec.cr:99-101` 与 `m7_network_down_spec.cr:57-59` 判不脆。
- 本轮未运行 `crystal spec`：改动只涉及注释与 README，不进入断言执行路径；门禁只跑格式检查、diff 空白检查与工作区清洁检查（原始输出见下）。

门禁原始输出（工作树上先跑，两笔提交后复跑同命令，结果相同）：

```text
$ crystal tool format --check src spec
（无输出）FORMAT_EXIT=0

$ git diff e05a50d --check
（无输出）CHECK_EXIT=0
```

## 2026-11-23：M7-docs 收口：四处口径对齐与历史标注复核（task-212）

- oracle：Bundler 参考实现与 `fixtures/differential` 装具本身；文档侧 oracle 为治理规范 `docs/compat-evidence/README.md:17-20` 与 `docs/roadmap-evidence/README.md:8-13`。
- 参考锚点：`vendor/reference/bundler/lib/bundler/definition.rb:984-1002`（CHECKSUMS 理由，经 `src/celerite/definition.cr:566` 注释引用）；install-time ruby/rubygems 复核经 `src/celerite/installer.cr:99-120` 对齐参考实现。
- 实现位置：本次只改文档，未改 `src/`、`fixtures/`、`script/`。被文档引用的锚点已复核：`src/celerite/installer.cr:99-120`（`Installer.ensure_specs_are_compatible!`，`:104` ruby、`:109` rubygems）；`src/celerite/definition.cr:566-590`（`lockfile_update_reason`，missing/empty 文案在 `:588`/`:589`）；`src/celerite/cli/commands_surface.cr:1671`（`installed_gem_dir` 起点，PATH/GIT/PLUGIN SOURCE 分支 `:1675-1694`）；`script/differential:794-795`（`deferred-<version>` 判定与 SKIP）；`script/differential:622`、`:633`、`:646-661`、`:666-679`、`:686-697`（`installed-tree`/`first-line`/`file-equals`/`file-contains`/`file-absent`）。
- 证据：
  - worktree `C:\temp\celerite-t212` @ `114c8ba`；`git merge-base --is-ancestor 302cbae 114c8ba` EXIT 0、`git rev-list --count 114c8ba..302cbae` = 0 ⇒ 21:21 的 `1078/0/0/0` 采集点（`302cbae`）早于本 HEAD。
  - 夹具实测：`Get-ChildItem fixtures/differential -Directory` = **484**；`Get-ChildItem fixtures/differential -Recurse -File -Filter deferred-2.7.2` = **30**；`-Filter deferred-4.0.24` = **5**；派生分母 2.7.2 = 484−30 = 454、4.0.24 = 484−5 = 479。README 两段名单与实测名单 `Compare-Object` 差集 0（30 名 / 5 名逐一相等）。
  - 门禁：`shards build` EXIT 0（仅 2 条 `File.executable?` 弃用告警）；`bash script/differential install-check` → `PASS install-check (exit=0)`、`differential (4.0.24): 1 passed, 0 failed, 0 skipped (documented deferrals)`，EXIT 0。
  - `script/compat-claims-index` 重建输出 `compat-claims: 258 claims, index written (12 files)`，EXIT 0；`--check` 输出 `compat-claims: 258 claims, index up to date`，EXIT 0。
  - `docs/compat-report.md`（只改 `## Current metrics`）：`:17` 夹具 475→**484**、deferred 29→**30**、分母 446/470→**454/479**；`:21` 同步该三个数并保留「475 派生的 446/470」为历史档；`:15` 4.0.24 全量行加「自采集日后未在 HEAD 重跑、分母 468 已过期」，并删去与 `:17` 冲突的自指句「本文件 `:17` 的 461 仍为 task-181 口径，待单独订正」；`:16` 2.7.2 全量行加同款括注（分母 446 过期，现 454）；`:18` 全量 `crystal spec` 以 `1078 examples, 0 failures, 0 errors, 0 pending`（`302cbae`，21:21）为「最近一次」，原 `1058/0/0/17`（`2ad9b66`）原文保留并标「已取代（superseded）」。
  - `README.md`：`26 fixtures carry the deferred-2.7.2 marker` → `30`，名单补 `gem-questionnaire`、`path-cache-multi-gemspec`、`path-cache-out-of-project`、`path-package-multi-gemspec`；`script/differential:742-743` → `:794-795`；五个 marker 探针行号 `:593`/`:604`/`:612-629`/`:634-645`/`:648-664` → `:622`/`:633`/`:646-661`/`:666-679`/`:686-697`；`src/celerite/installer.cr:65-90` → `:99-120`、`src/celerite/definition.cr:362` → `:566-590`、`src/celerite/cli/commands_surface.cr:860-931` → `:1671`。上游基线 bullet（`64 examples, 45 failed`，分桶 44/1/0/0）与报告 `:19`、roadmap `:148` 一致，未改。
  - `docs/compat-claims/M7-docs-sync.md`：新增 C-M7-docs-006（README/报告/roadmap 三处口径一致）、007（历史行标注 commit/工作树、旧值只标取代）、008（计数只在 `## Current metrics`）；并把 C-M7-docs-002 的 `:44`→`:47`、C-M7-docs-003 的 `:201`→`:221` 修到治理句实际行号。
  - roadmap 复核（只读）：M7-1…M7-suite 各行只留任务陈述与「实证流水逐字迁出至 …」指针，无流水、无行号；M7-8「45 failures 基线 44/1/0/0」与报告 `:19` 一致；M7-docs 仍为 `[ ]`（本任务收口后由首辅勾选），未发现与 claims/证据冲突的陈述。
- 已声明差异：本任务不重跑全量 `crystal spec`、两个 profile 的全量差分与上游 rspec，故 `:15`/`:16`/`:18` 只能记「最近一次在 <sha>」并注明未在 HEAD 重跑；上游 45/44/1/0 沿用 task-193（`C:\temp\celerite-t193` @ `954f2d5`），未复采。

### 未验证
- 未在 `114c8ba` 重跑 `crystal spec`：`1078/0/0/0` 取自首辅 21:21 采集（`302cbae`），原始日志未复核。
- 未在 `114c8ba` 重跑 `script/differential`（2.7.2 / 4.0.24 全量）与 `script/upstream-specs`：报告对应行只加「自采集日后未在 HEAD 重跑」括注，数值仍是旧采集点。
- 484 个目录中 `command` 文件的存在性只对 task-188 的 475 个目录全量核过，其后新增目录未逐一复核。
- `README.md` 的 `src/celerite/resolution.cr:1362`、`:1371`、`:1494` 三个锚点未核（不在本次实测范围）。
- `src/celerite/cli/commands_surface.cr` 的 `installed_gem_dir` 结束行未定，故只写起点 `:1671`。
- `docs/compat-report.md:53`「报告依据的最后已知 HEAD `2ad9b66`」与 `## Current metrics` 的 `4bdc20a`/`954f2d5`/`114c8ba` 不一致；不在「只改 `## Current metrics`」授权内，未改，待首辅裁定。
## 2026-11-23：M7-docs 行勾选裁定（首辅，task-212 之后）

**判定：可勾 `[x]`，缺项 0。**

逐分句对账（该行原文三件事）：

1. **「更新 README、兼容报告、roadmap 和实际代码状态」** —— 满足。task-212 把 `README.md` 的上游基线条目、per-profile deferred 计数（30 / 5）与五个 marker 探针行号、三个 `src/` 锚点（`src/celerite/installer.cr:99-120`、`src/celerite/definition.cr:566-590`、`src/celerite/cli/commands_surface.cr:1671`）按实测改正；`docs/compat-report.md` 的 `## Current metrics` 把夹具总数改为 484（分母 2.7.2 = 454、4.0.24 = 479）、全量 `crystal spec` 改为最近一次 `1078 examples, 0 failures, 0 errors, 0 pending`（`302cbae`，2026-11-23 21:21）。首辅在同轮补正了该文件的「报告依据的最后已知 HEAD」行与 `## Scope and limits` 的治理补充：原行只绑 `2ad9b66` 且称「全量门禁只有 crystal spec 一行重跑过」，与 task-212 之后一行一采集点（`4bdc20a` / `954f2d5` / `302cbae` / `114c8ba`）的事实不符，现改为逐行点名采集点（提交 `416041b`）。
2. **「历史报告标明对应 commit/工作树」** —— 满足。`## Current metrics` 五行各带采集点：4.0.24 全量 `4bdc20a`（task-188）、2.7.2 全量 `954f2d5`（task-191）、夹具计数 `114c8ba`（task-212）、全量 spec `302cbae`（task-212 记录）、上游 `954f2d5`（task-193，worktree `C:\temp\celerite-t193`）。两条全量差分行另加「自采集日后未在 HEAD 重跑、本行分母已过期」括注。
3. **「不随新 fixture 静默改写旧结论」** —— 满足。旧值一律以「已取代（superseded）」留在原位（`218/14/3`、`126/6/1`、`1058/10/17`、`1058/0/0/17`、461/475/473 四档夹具总数），未删行、未回改；claims `C-M7-docs-005`（旧结论保留原文）与 `C-M7-docs-007`（历史行标采集点、只标取代）分别钉住这两条可判定性。

新增的可重跑判据（本轮写入 claims）：`C-M7-docs-006`（README / 报告 / roadmap 三处同口径：上游 45 failures + 分桶 44/1/0/0、per-profile deferred 30 / 5）、`C-M7-docs-007`（每行至少一个采集点;旧值可检索且未被替换）、`C-M7-docs-008`（夹具总数/用例例数这类现状计数只在 `## Current metrics`，不外溢到 README/roadmap）。`script/compat-claims-index --check` = 258 条 up to date。

**未验证（不构成缺项，但须留档）**：

- 未在 `114c8ba` 重跑全量 `crystal spec`；`1078/0/0/0` 取自首辅 2026-11-23 21:21 在 `302cbae` 的采集，原始日志未复核。
- 未在 `114c8ba` 重跑 `script/differential`（4.0.24 / 2.7.2 全量）与 `script/upstream-specs`：三条全量行仍是各自采集日的记录，只加过期括注。
- `README.md` 引用的 `src/celerite/resolution.cr:1362`/`:1371`/`:1494` 三个锚点未核；`src/celerite/cli/commands_surface.cr` 的 `installed_gem_dir` 只写起点。
- 判据里的 PowerShell `Select-String` 片段依赖本机路径，换宿主需按节标题重新定位。
