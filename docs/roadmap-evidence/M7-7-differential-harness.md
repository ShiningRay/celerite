# M7(7) script/differential 健壮性

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 160 -->

（进展 2026-11-13, M7(7), HEAD=b8f7638 基线：`script/differential-installed-tree` 已增加符号链接目标比较，使用 `find . -type l` + `readlink` 自行遍历，不依赖 `diff -r --no-dereference`；目标不一致输出 `symlink target differs: ref=<x> cel=<y>` 并返回 1；新增 `script/differential-installed-tree-selftest`（Windows `MSYS=winsymlinks:nativestrict`，不可创建真实链接则 SKIP 并记录错误/复现命令）。实测：selftest 4 passed, 0 failed, 0 skipped, EXIT 0；installed-tree 定向 fixture `install-check`/`show-info-installed`/`install-fresh`/`install-rerun` 双 profile 各 4/0/0 EXIT 0（`git-installed-discovery` 无 installed-tree marker，不适用）。`docs/differential-normalization.md` 已补“安装树比较内容”小节。其余项未完成；M7(7) 已于 2026-11-14 验收通过（提交 `docs(M7 task-3): record M7(7) acceptance evidence`，证据映射见 `docs/compat-evidence/2026-11-14.md` M7(7) acceptance 节：归一化 N1–N7 权威表 + 脚本头部镜像；语义输出不排序、仅 N7 排连续 Fetching 行；installed-tree 五类判定 + selftest 6/0/0 EXIT 0 + 双 profile installed-tree 定向夹具 12/12；lockfile/Gemfile 内容由 first-line/file-contains 探针直接比对（本轮 11 探针夹具双 profile 各 9 passed/2 failed，2 失败为 racc 原生构建缺 make + 平台 gap，非内容比较）。）
