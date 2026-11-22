# M7 文档与状态同步（README/兼容报告/roadmap）

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 163 -->

**（进行中，2026-11-10：compat-report/roadmap/README 已按 HEAD=8e91a2f 与本迭代脚本/文档变更做保守对齐，未重跑门禁的结果标未验证；需后续迭代持续同步。）** 

**2026-11-19（task-30 收口）：判据拆为三组逐条清零——README A1–A7（安装命令、沙箱网络、断言清单、能力状态、矩阵来源、开发前置、上游基线）、compat-matrix generated B（CLI 头注与上游基线）、roadmap C（L154/155/156/159/161/162 内联补记）；本轮仅改文档，不改产品代码。复选框保持 `[ ]`。** 

**2026-11-19（task-39 漂移校正）：README/roadmap/compat-matrix 的过期能力、基线数字与锚点已按实测更正，历史结论用“已被…取代/历史快照”标注，未改旧文。复选框保持 `[ ]`。** 

**2026-11-20（task-61 同步）：README 状态块补 task-52…60 能力、上游基线改注 33–59、deferred 计数改为 12/5 并列出名单、探针锚点按 `script/differential` 实测行号更新、补 cmdglob 机制与运行期/开发期差分边界；compat-matrix README 区分手写四文件与 `generated/*` 并登记生成物 mtime；差分报告标题与文件名对齐；task-55 的 `*.gemspec` 归一化改指 cmdglob。仍未闭：A3 探针锚点随脚本改动会再漂移、B 组矩阵索引未覆盖全部生成物、C 组 cmdglob 机制仅在 README 与 `docs/compat-evidence/2026-11-20.md` 说明。**
