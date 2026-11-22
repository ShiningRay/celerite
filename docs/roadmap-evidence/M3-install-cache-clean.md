# M3 install/cache/package/clean/pristine/binstubs 路径

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 80 -->

**2026-11-15 订正（clean）**：参考 2.7.2 与 4.0.24 的 `clean`/`clean --force` 一致，均按当前锁文件保留；早先「2.7.x 清空保留集」是装具缺陷期（`>>` 截断参考输出）的误判，profile 特例代码已撤销，新增 `spec/m7_clean_spec.cr` 4 例（移除未锁定 gem、`--force` 全保留、`--dry-run` 不删、二次 clean 幂等），双 profile 定向差分 `clean-force`/`clean-unused` 2/0/0。
