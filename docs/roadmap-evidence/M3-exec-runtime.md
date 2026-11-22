# M3 exec / runtime setup / ruby -rbundler/setup

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 81 -->

**2026-11-20（task-48 补记）：`exec` 的 `RUBYOPT`/`RUBYLIB` 注入已与参考对齐（单 `-r`、正斜杠去重），显式缺失 Gemfile 改由子进程 `-rbundler/setup` 抛 `Bundler::GemfileNotFound`（exit 1）；差分 `exec-env-injected`/`exec-no-gemfile` 双 profile 通过，旧二进制两例均失败。**
