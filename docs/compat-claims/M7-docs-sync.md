# M7-docs 文档与代码状态同步（claims）

本文件是 M7-docs 的断言账本：把 `../compat-evidence/2026-11-19.md` 与 `../roadmap-evidence/M7-docs-sync.md` 里已取证的文档治理结论逐条固化为可核查断言。本子项本身就是文档纪律，故「参考行为」一栏引用的是本仓治理规范的行锚点，而非 Bundler 上游 oracle；原始流水仍留在 evidence。

## C-M7-docs-001 新证据写入当日的 `docs/compat-evidence/YYYY-MM-DD.md`，同日多条追加到文件末尾

- 状态：已实现
- 参考行为（治理规范，2026-11-22）：`docs/compat-evidence/README.md:17`「新证据写到**当日的 `YYYY-MM-DD.md`**；同一天多条按时间顺序追加到文件末尾」
- 我方行为：`docs/compat-evidence/` 下按日文件 `2026-11-11.md`…`2026-11-22.md` 承载全部流水；`docs/compat-report.md:1-3` 声明按日日志已拆出本文
- 判据：`bash script/differential install-check`；`ls docs/compat-evidence/2026-11-*.md`
- 边界：本条的可判定部分是 `ls` 一段（按日文件按日期命名且存在）；`bash script/differential install-check` 是文档所索引的差分回归仍可执行的门禁，不单独证明本条
- 生效：文档治理轮（2026-11-22）
- 取代：无

## C-M7-docs-002 主报告只保留当前状态与索引，不再追加流水

- 状态：已实现
- 参考行为（治理规范，2026-11-22）：`docs/compat-evidence/README.md:20`「主报告 `../compat-report.md` 只放当前状态与索引；不要把流水写回主报告」
- 我方行为：`docs/compat-report.md:9` 逐字声明「本文件不再追加流水」；`:1-3` 记录治理前后结构（原 7410 行拆为按日文件，本文只留现状与索引）；`:47` 明写「本文件**未重新运行**任何差分 / rspec / 全量门禁，只做搬运与现状汇总」
- 判据：`bash script/differential install-check`；`grep -n "不再追加流水" docs/compat-report.md`
- 边界：本条的可判定部分是 `grep` 一段（约束句在位）；「主报告此后未增长」由治理轮的一次性拆分保证，无逐次自动检查
- 生效：文档治理轮（2026-11-22）
- 取代：无

## C-M7-docs-003 引用历史结论写「compat-evidence 日期文件 + 节标题」，不写 `compat-report.md:<行号>`

- 状态：已实现
- 参考行为（治理规范，2026-11-22）：`docs/compat-report.md:221`「引用上文某个历史节时，请引「compat-evidence 的日期文件 + 节标题」，不要引本文件的旧行号」
- 我方行为：治理类文档（`README.md`、`docs/compat-report.md`、`docs/compat-evidence/`、`docs/roadmap.md`、`docs/roadmap-evidence/`）内不存在 `compat-report.md:<行号>` 形式的引用；历史结论统一指向按日文件与节标题
- 判据：`bash script/differential install-check`；`grep -rn "compat-report\.md:[0-9]" README.md docs/compat-report.md docs/compat-evidence/ docs/roadmap.md docs/roadmap-evidence/`（应无输出）
- 边界：本条的可判定部分是 `grep` 一段（该范围内无输出）；`docs/compat-claims/` 不在检查范围内——断言需要钉住它据以立论的 evidence 行，属正常用法
- 生效：文档治理轮（2026-11-22）
- 取代：无

## C-M7-docs-004 `docs/roadmap.md` 只维护任务陈述与复选框，流水落 `docs/roadmap-evidence/`，不写行号

- 状态：已实现
- 参考行为（治理规范，2026-11-22）：`docs/roadmap-evidence/README.md:10`「`docs/roadmap.md` 只维护任务陈述与复选框状态。需要指向证据时写「见 `docs/roadmap-evidence/<文件>`」，不写行号」；`:8`「新流水写本目录，不写回 roadmap 清单行」
- 我方行为：`docs/roadmap.md:149`、`:150`、`:151` 三行只留任务陈述与「实证流水逐字迁出至 `docs/roadmap-evidence/<文件>`」指针；治理类文档内不存在 `roadmap.md:<行号>` 形式的引用
- 判据：`bash script/differential install-check`；`grep -rn "roadmap\.md:[0-9]" README.md docs/roadmap.md docs/roadmap-evidence/ docs/compat-report.md docs/compat-evidence/`（应无输出）
- 边界：本条的可判定部分是 `grep` 一段（该范围内无输出）；迁移时旧流水里的历史行号引用（如「roadmap L160」）按 `docs/roadmap-evidence/README.md` 的映射表解读，不视为违规
- 生效：文档治理轮（2026-11-22）
- 取代：无

## C-M7-docs-005 被取代的旧结论保留原文，由新条目写明取代关系，不回改旧条目

- 状态：已实现
- 参考行为（治理规范，2026-11-22）：`docs/compat-evidence/README.md:19`「只引用**当前还成立**的事实；过期结论在被后续条目取代时，保留原文并在新条目里写明取代关系，不回去改旧条目」；`docs/roadmap-evidence/README.md:13`「**过期结论不删**：保留原文，由新条目写明取代关系」
- 我方行为：`docs/roadmap-evidence/M7-9-rails-regression.md` 以追加注记保留原结论并标注当前状态（复选框保持 `[ ]`），未改写原文；`docs/roadmap-evidence/M7-docs-sync.md` 用「已被…取代 / 历史快照」标注而不删旧文
- 判据：`bash script/differential install-check`；`grep -n "保留原文" docs/compat-evidence/README.md docs/roadmap-evidence/README.md`
- 边界：本条的可判定部分是 `grep` 一段（两处规则句在位）；「旧文是否真未被回改」需人工比对历史节与追加节，无自动检查
- 生效：文档治理轮（2026-11-22）
- 取代：无
## C-M7-docs-006 README、compat-report、roadmap 三处对同一度量给出口径一致的陈述

- 状态：已实现
- 参考行为（M7-docs 行要求）：`docs/roadmap.md:150`「更新 README、兼容报告、roadmap 和实际代码状态；历史报告标明对应 commit/工作树，不随新 fixture 静默改写旧结论」
- 我方行为：上游基线三处同口径 64 examples / 45 failures（README 的 Goals 块记 45 failed / 19 passed；`docs/compat-report.md:19` 记 64 examples, 45 failures 并分桶 44/1/0/0；`docs/roadmap.md:148` 记 45 failures 基线 44/1/0/0）；夹具 deferred 计数 README 与 `docs/compat-report.md:17`、`:21` 同为 30（2.7.2）/ 5（4.0.24）；夹具**总数**只有 compat-report 记（484）
- 判据：门禁 `bash script/differential install-check`（EXIT 0）；三处口径 `Select-String -Path README.md,docs/compat-report.md,docs/roadmap.md -Pattern '45 fail|64 examples'`（命中 `README.md:48`、`:53`、`:58`、`:64`，`docs/compat-report.md:19`、`:142`、`:147`、`:152`，`docs/roadmap.md:148`）；名单比对 `Get-ChildItem fixtures/differential -Directory`（计 484，其中带 `deferred-2.7.2` 者 30、带 `deferred-4.0.24` 者 5）与 README 两段名单 `Compare-Object` 差集 0
- 预期：三处 45 与分桶 44/1/0/0 不矛盾；两处 deferred 计数与实测相等。
- 边界：只覆盖这三类口径（上游基线、per-profile deferred 计数、夹具总数归属）；spec 例数/耗时/日志路径由 M7-suite、M7-7 的断言管，本条不重复。
- 生效：2026-11-23（task-212）
- 取代：无

## C-M7-docs-007 历史度量行标注对应 commit / 工作树，旧值只标取代、不静默改写

- 状态：已实现
- 参考行为（治理规范）：M7-docs 行「历史报告标明对应 commit/工作树，不随新 fixture 静默改写旧结论」；`docs/compat-evidence/README.md:19`「过期结论在被后续条目取代时，保留原文并在新条目里写明取代关系，不回去改旧条目」
- 我方行为：`docs/compat-report.md` 的 `## Current metrics` 各行均绑定采集点——`:15` 4.0.24 全量 HEAD `4bdc20a`；`:16` 2.7.2 全量 HEAD `954f2d5`；`:17` 夹具总数 task-212 @ `114c8ba`；`:18` 全量 crystal spec 最近一次 `302cbae`（同格保留 `2ad9b66` 的 `1058/0/0/17` 并标 superseded）；`:19` 上游 worktree `C:\temp\celerite-t193` @ `954f2d5`。过期分母以「自采集日后未在 HEAD 重跑」括注、旧值以「已取代（superseded）」保留，不删行、不回改历史值
- 判据：门禁 `bash script/differential install-check`（EXIT 0）；采集点与旧值 `$l=(Get-Content docs/compat-report.md); $l[10..20] | Select-String -Pattern '[0-9a-f]{7}'`（含 `4bdc20a`、`954f2d5`、`114c8ba`、`302cbae`、`2ad9b66`）与 `$l[10..20] | Select-String -Pattern '457|461|473|475|1058|50 failures|47 failures'`（命中行 15、16、17、19、21）
- 预期：每行至少一个采集点；旧值可检索且未被替换。
- 边界：判据证明「有采集点、旧值在位」，不证明这些 sha 仍是 main 的 HEAD（报告不承诺跟随 HEAD），也不替代各行自身的实测复核。
- 生效：2026-11-23（task-212）
- 取代：无

## C-M7-docs-008 度量计数只出现在 `docs/compat-report.md` 的 `## Current metrics`，不外溢到 README / roadmap

- 状态：已实现
- 参考行为（治理规范）：`docs/compat-evidence/README.md:20`「主报告 `../compat-report.md` 只放当前状态与索引」的镜像约束——现状数字集中一处，README 与 roadmap 不复述
- 我方行为：README 全文无夹具目录总数、无 spec 例数、无上游失败数的分桶明细重复；`docs/roadmap.md` 的 M7 各行只写任务陈述与「实证流水逐字迁出至 …」指针，不含计数。唯一例外是 README 的 per-profile deferred 计数（30/5）：它是装具事实而非夹具总数，且受 C-M7-docs-006 的实测约束
- 判据：门禁 `bash script/differential install-check`（EXIT 0）；外溢检查 `Select-String -Path README.md,docs/roadmap.md -Pattern '个夹具|个目录'`（无输出）；归属检查 `Select-String -Path docs/compat-report.md -Pattern '484'`（命中 `:15`、`:16`、`:17`、`:21`，均在 `## Current metrics` 内）
- 边界：只约束「夹具总数 / 用例例数」这类现状计数；任务书、证据流水、claims 自身可含计数。
- 生效：2026-11-23（task-212）
- 取代：无
