# roadmap 实证流水

本目录承接 `docs/roadmap.md` 中原本内联在清单条目行尾的**追加流水**（逐次迭代补记）。
治理日期：2026-11-22；治理前 `docs/roadmap.md` 为 218 行 / 187,218 字节，其中约 91% 的字符是这些追加流水。

## 写入规则

1. **新流水写本目录，不写回 roadmap 清单行。** 追加到对应子项文件末尾，用二级标题分段：
   `## <YYYY-MM-DD>：<主题>`，子项用 `###`。内容仍按既有习惯写清：oracle、参考锚点、实现位置、证据（spec/fixture/日志）、已声明差异。
2. **`docs/roadmap.md` 只维护任务陈述与复选框状态。** 需要指向证据时写「见 `docs/roadmap-evidence/<文件>`」，不写行号。
3. **引用既有流水写「`docs/roadmap-evidence/<文件>` 的 `<标题>`」，不引用 roadmap 行号**（与 `docs/compat-evidence/README.md` 的规则一致）。
4. **迁移不改字**：本目录内所有内容都是治理时逐字迁出的原文，只按追加边界重新分行；原文中的旧行号引用（如「roadmap L160」）保持原样，用下方映射表解读。
5. **过期结论不删**：保留原文，由新条目写明取代关系。

## 旧 roadmap 行号映射表

治理前的行号（218 行版本）与本目录文件的对应关系。历史证据里出现的「roadmap L<n>」按此表解读。

| 旧行号 | 内容 | 现位置 |
| --- | --- | --- |
| L68 | 用真实项目锁文件做解与 diff 回归，不将结果差异常化忽略。（真实 Bundler… | `M2-lockfile-diff-regression.md` |
| L80 | 实现 `install`、`cache`/`package`、`clean`、`pr… | `M3-install-cache-clean.md` |
| L81 | 实现 `exec`、runtime setup 与 `ruby -rbundler/… | `M3-exec-runtime.md` |
| L131 | - **结论**：M7(1)(2)(3) 均为**部分证据化/未闭环**；M7(1)-(3) 复… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L132 | - **证据索引（关键 commit）**：`a8753b6`、`7c446d9`、`3c4f5… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L133 | - **代表性 fixture/spec（既有实测/本轮部分复跑）**：M7 子集 8 文件 *… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L134 | - **双 profile 全量 differential（既有实测；497e293+本轮未重跑… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L135 |   - 4.0.24：**133 fixtures, 126 passed, 7 failed,… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L136 |   - 2.7.2：**133 fixtures, 126 passed, 6 failed, … | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L137 | - **本轮 combo-fixture 实测（证据基线 HEAD=497e293，fixtur… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L138 | - **M7(1)（部分）**：约束过滤/RubyVersionMismatch exit 18… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L139 | - **M7(2)（部分）**：**2026-11-19（task-22 补记）：`check`… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L140 | - **M7(3)（部分）**：**2026-11-19（task-21 补记）：锁文件钉死不兼… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L141 | - **通用阻塞与硬约束**：stock `crystal build` OpenSSL `EV… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L142 | - **task-2 收口建议（供首辅裁断）**：不建议宣告 M7(1)-(3) 整体验收收口/… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L144 | - **config_spec round-trip 既存失败（2026-11-13，docs-… | `M7-1-3-closure-snapshot-2026-11-13.md` |
| L154 | 实现当前 Ruby、RubyGems、Gemfile 目标 Ruby、engine、… | `M7-1-ruby-constraints.md` |
| L155 | 修复安装后 `check`、`list`、`show`/`info` 的 gem 发… | `M7-2-installed-discovery.md` |
| L156 | 移除或实现占位路径：`fund` 的真实 metadata、`gem` 模板、完整 … | `M7-3-placeholders.md` |
| L157 | 让 mirror、proxy、redirect、retry、SSL CA/clien… | `M7-4-network-options.md` |
| L158 | 补齐 Git tag/submodules/glob、多个 gemspec、mono… | `M7-5-sources-platforms.md` |
| L159 | 插件命令注册、自定义 source、hook 异常和第三方插件 fixture 分别… | `M7-6-plugins.md` |
| L160 | 修复 `script/differential`：列出所有归一化规则；对有语义的输出… | `M7-7-differential-harness.md` |
| L161 | 修复 `script/upstream-specs`：使锁文件族真实驱动 Celer… | `M7-8-upstream-specs.md` |
| L162 | 建立 Rails 规模真实项目回归，记录所有有意兼容差异及理由；未解释差异为零后才恢… | `M7-9-rails-regression.md` |
| L163 | 更新 README、兼容报告、roadmap 和实际代码状态；历史报告标明对应 co… | `M7-docs-sync.md` |
| L164 | 修复在本机无法跑完全量 `crystal spec` 的问题（2026-11-19 … | `M7-suite.md` |
| L166 | **2026-11-15（M7(8) 第五子项）：两条产品差异的 differential 固化… | `M7-8-upstream-specs.md` |
| L215 | 1. 修复兼容报告、上游测试退出码与归一化声明，保留可复核的失败基线。**（进行中，2026-1… | `first-review-increment.md` |
| L218 | 4. 之后才实现 M8 的批次求值和完整指纹；每个阶段独立提交、独立 benchmark，不把正… | `first-review-increment.md` |

治理后 `docs/roadmap.md` 的 M7 清单行对应的子项见 `docs/roadmap.md` 正文中的指针。

## 文件清单

| 文件 | 内容 |
| --- | --- |
| `M2-lockfile-diff-regression.md` | M2「真实项目锁文件做解与 diff 回归」的追加流水。 |
| `M3-exec-runtime.md` | M3 `exec`/runtime setup 的追加流水。 |
| `M3-install-cache-clean.md` | M3 install/cache/package/clean/pristine/binstubs 路径的追加流水。 |
| `M7-1-3-closure-snapshot-2026-11-13.md` | 2026-11-13 的 M7(1)(2)(3) 阶段性闭环汇总快照整节（L131–L142 + L144 逐字迁出）。 |
| `M7-1-ruby-constraints.md` | M7(1) 约束过滤、`ruby_requirement_satisfied?`、运行时/engine/ABI 校验的追加流水。 |
| `M7-2-installed-discovery.md` | M7(2) 安装后 `check`/`list`/`show --paths` 的 gem 发现与 group/Git/path 状态的追加流水。 |
| `M7-3-placeholders.md` | M7(3) 占位路径（`fund` metadata、`gem` 模板、`console`/`env`）的追加流水。 |
| `M7-4-network-options.md` | M7(4) mirror/proxy/redirect/retry/TLS/`path.system`/`build.<gem>`/legacy index 的追加流水。 |
| `M7-5-sources-platforms.md` | M7(5) Git tag/submodule/glob、多 gemspec、monorepo、私有 source、离线与平台矩阵的追加流水。 |
| `M7-6-plugins.md` | M7(6) 插件命令注册、自定义 source、hook 异常的追加流水。 |
| `M7-7-differential-harness.md` | M7(7) `script/differential` 归一化与安装树比较的追加流水。 |
| `M7-8-upstream-specs.md` | M7(8) `script/upstream-specs` 锁文件族真实驱动、上游基线复采的追加流水。 |
| `M7-9-rails-regression.md` | M7(9) Rails 规模真实项目回归探测的追加流水。 |
| `M7-docs-sync.md` | M7 文档/README/兼容报告同步判据的追加流水。 |
| `M7-suite.md` | M7 全量 `crystal spec` 可跑通问题的追加流水。 |
| `first-review-increment.md` | 「首个可评审增量」第 1、4 项的追加流水。 |
