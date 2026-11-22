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
- 我方行为：`docs/compat-report.md:9` 逐字声明「本文件不再追加流水」；`:1-3` 记录治理前后结构（原 7410 行拆为按日文件，本文只留现状与索引）；`:44` 明写「本文件**未重新运行**任何差分 / rspec / 全量门禁，只做搬运与现状汇总」
- 判据：`bash script/differential install-check`；`grep -n "不再追加流水" docs/compat-report.md`
- 边界：本条的可判定部分是 `grep` 一段（约束句在位）；「主报告此后未增长」由治理轮的一次性拆分保证，无逐次自动检查
- 生效：文档治理轮（2026-11-22）
- 取代：无

## C-M7-docs-003 引用历史结论写「compat-evidence 日期文件 + 节标题」，不写 `compat-report.md:<行号>`

- 状态：已实现
- 参考行为（治理规范，2026-11-22）：`docs/compat-report.md:201`「引用上文某个历史节时，请引「compat-evidence 的日期文件 + 节标题」，不要引本文件的旧行号」
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
