# M7 全量 `crystal spec` 可跑通

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 164 -->

（2026-11-19 task-19 验收补记：进程中途静默结束、EXIT 1 无摘要；已在 `a3ed3ec` 复现，与本轮改动无关；4 个已定位失败为 `~/.bundle/config` 与临时目录的环境耦合；详见 `docs/compat-evidence/2026-11-19.md` 同名补记）。2026-11-22（task-131 补记）: 编译期失败已修（`ae1248c`），全套件现可跑到 Finished（999 examples / 5 failures / 11 pending，22:32），剩余 5 条属 m7_clean / m7_show_order / m7_quiet_and_add 三个既有家族，尚未清零。
