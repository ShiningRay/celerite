<!-- 规范文件：本文件是「断言账本」的唯一格式定义。修改格式必须同步改 script/compat-claims-index。 -->

# 兼容性断言账本（compat-claims）

本目录回答一个问题：**现在有哪些关于兼容性的断言是成立的，凭什么成立，怎么重跑。**

`docs/compat-evidence/` 保存原始运行记录（oracle 原文、日志、逐次复采），是**过程档案**；
本目录保存**结论**，按 M7 子项组织，与日期无关。两者不重复：档案写「那天跑了什么」，
账本写「现在是什么状态」。

## 一条断言是什么

一条断言 = 一个**可判定的行为** + 一条**能重跑的判据**。
不可判定的表述（「基本对齐」「大体支持」）不是断言，不允许出现在本目录。

## 文件与编号

| 子项 | 文件 | 覆盖范围 |
| --- | --- | --- |
| M7-1 | `M7-1-ruby-constraints.md` | Ruby / RubyGems / engine / patchlevel / ABI 约束过滤 |
| M7-2 | `M7-2-installed-discovery.md` | 安装后 `check` / `list` / `show` / `info` 的 gem 发现与命令面 |
| M7-3 | `M7-3-placeholders.md` | `fund` / `gem` / `console` / `env` / `issue` 等占位路径 |
| M7-4 | `M7-4-network-options.md` | mirror / proxy / redirect / retry / SSL / legacy index 等网络选项 |
| M7-5 | `M7-5-sources-platforms.md` | Git 源、多 gemspec、私有 source、离线、磁盘错误、平台 ABI |
| M7-6 | `M7-6-plugins.md` | 插件命令注册、自定义 source、hook 异常、第三方 fixture |
| M7-7 | `M7-7-differential-harness.md` | `script/differential` 的归一化与比较强度 |
| M7-8 | `M7-8-upstream-specs.md` | `script/upstream-specs` 与锁定文件族 |
| M7-9 | `M7-9-rails-regression.md` | Rails 规模真实项目回归 |
| M7-docs | `M7-docs-sync.md` | README / 兼容报告 / roadmap 与代码状态同步 |
| M7-suite | `M7-suite.md` | 全量 `crystal spec` 的可运行性 |
| cross | `cross-cutting.md` | M0–M6 遗留、宿主环境限制、贯穿多子项的结论 |

编号格式 `C-<子项>-<三位序号>`，例：`C-M7-8-014`。
序号在文件内连续、不复用；条目删除后序号留空，不回收。

断言标题（`## C-...` 之后的部分）必须是**事实句**：主语 + 行为 + 结果。
反例：「关于 CHECKSUMS 的处理」；正例：「CHECKSUMS 段整行缺失时 install 打印 `Resolving dependencies...`」。

## 固定字段（七项，缺一不可）

```
## C-M7-8-008 CHECKSUMS 段整行缺失时 `install` 打印 `Resolving dependencies...` 并真解析

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:626-628` `install_needed?` = `resolve_needed? || missing_specs?`；
  `:647-649` `resolve_needed?` = `unlocking? || something_changed?`；`:641` 的
  `@locked_spec_with_missing_checksums` 无条件参与判定，故缺行必然解析，由 `lib/bundler/resolver.rb:34` 打印
- 我方行为：`src/celerite/definition.cr:598` `checksums_need_refresh?` 返回 `ChecksumsRefreshReason?`，
  `:619` 对缺行返回 `Missing`；`src/celerite/cli/commands_install.cr:369` 据此放弃复用
- 判据：`bash script/differential checksums-refresh-cache-deleted`；`crystal spec spec/m7_checksums_trigger_spec.cr`
- 边界：空值形态在 2.7.2 上未实测（见 C-M7-8-009）
- 生效：task-116
- 取代：无
```

（上面这条是 `M7-8-upstream-specs.md` 里的真实条目，此处仅作格式示例；改动示例时不要改动原始条目。）

### 状态（五选一）

| 状态 | 含义 |
| --- | --- |
| `已实现` | 我方行为与参考一致，判据可复现通过 |
| `已声明差异` | 有意不一致，理由写在「边界」；不谎报为一致 |
| `未实现` | 参考有、我方无，且已确认 |
| `未验证` | 未取得参考 oracle 或未跑判据；**不得**当作已实现 |
| `已取代` | 结论已被另一条断言推翻或收紧，`取代` 字段指向新的那条 |

「未验证」与「已实现」的区别是取证状态，不是置信度形容词。写「已实现」必须有一条跑过的判据。

### 字段细则

- **参考行为**：必须带版本（`4.0.24` / `2.7.2` / 两者）与 `文件:行` 锚点（如
  `lib/bundler/source/rubygems.rb:122-136`）；逐字输出用行内代码，超过两行的输出贴进
  `docs/compat-evidence/` 并链回，不抄进本目录。
- **我方行为**：写差异或对齐点，落到 `src/` 的 `文件:行`。未改代码的条目写「未改代码」。
- **判据**：必须是**可直接执行的命令**——`bash script/differential <夹具名>`、
  `crystal spec spec/<文件>.cr`、或两者。不允许写「见 evidence 某节」代替判据；
  evidence 用于存原始输出，不作为判据本身。
- **边界**：未覆盖的形态、已知的取证缺口、有意差异的理由。没有就写「无」——
  写「无」表示已核查过边界，不是省略。
- **生效**：任务号 + 提交短哈希（如 `task-116（fe648c8）`）。跨多任务写主要那条。
- **取代**：被本条取代的断言 ID 列表，或「无」。

## 硬规则

1. **一条断言只讲一个可判定的行为。** 复合结论拆开写。
2. **判据必须能重跑。** 判据失效（夹具改名、spec 删除）时，本条降级为「未验证」。
3. **一次性数据不进本目录**：完整 stdout、日志路径、计数快照、commit 长串、时间戳。
   需要时贴进 `docs/compat-evidence/<日期>.md` 并链回。
4. **结论变化不改写旧正文**：在旧条目的 `状态` 改 `已取代`、`取代` 指向新 ID；
   新条目在 `取代` 里反向列出旧 ID。两条并存，判据演进史保留。
5. **计数不进断言。** 「218 passed / 14 failed」这类度量写在
   [`../compat-report.md`](../compat-report.md) 的 Current metrics 表；本条只写行为。

## 与其它文档的关系

- [`../compat-report.md`](../compat-report.md)：现状度量、未支持清单、复现命令。**度量归它。**
- [`../compat-evidence/README.md`](../compat-evidence/README.md)：原始运行档案与按日索引。
- [`../roadmap-evidence/`](../roadmap-evidence/README.md)：roadmap 清单行的实证流水。
- 本目录：行为断言与判据。**结论归它。**

新写一条流水时：先把结论落到本目录（新建或更新断言），再把原始输出落到
`docs/compat-evidence/<当日>.md`，两者互相链接。

引用其它目录的文件用相对路径（`../compat-evidence/2026-11-22.md`）。

## 索引

索引由 `script/compat-claims-index` 从各文件机械生成，勿手改。

<!-- BEGIN GENERATED INDEX -->
| ID | 断言 | 状态 | 文件 | 判据 |
| --- | --- | --- | --- | --- |
| C-M7-1-001 | Ruby 运行时声明与当前解释器不一致时，check / show / binstubs 以 18 退出 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential ruby-requirement-mismatch'；'crystal spec spe…` |
| C-M7-1-002 | gem 元数据 required_ruby_version 不满足时该候选被排除 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential ruby-metadata-match ruby-metadata-exact-matc…` |
| C-M7-1-003 | gem 元数据 required_rubygems_version 不满足时该候选被排除 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential rubygems-metadata-match rubygems-metadata-bo…` |
| C-M7-1-004 | 根级依赖被元数据排除时，解释文案按版本范围表达被排除的候选 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential ruby-metadata-remote-fail rubygems-metadata-…` |
| C-M7-1-005 | gem 元数据匹配只比 RUBY_VERSION，patchlevel 只参与 Gemfile 目标校验 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential ruby-patchlevel-match'；'crystal spec spec/m7…` |
| C-M7-1-006 | Gemfile 声明的 patchlevel 在 install / clean / exec / outdated 也拒绝，而不只是 check | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential install-patchlevel-mismatch install-patchlev…` |
| C-M7-1-007 | 锁文件钉住的版本与索引 requirements 冲突时先复核再复用，冲突则重解或以 exit 6 失败 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential install-locked-ruby-incompatible install-rub…` |
| C-M7-1-008 | 无 lockfile 的 check 先解析（必要时写锁），再报缺 gem 或满足 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential check-no-lockfile-missing check-no-lockfile-…` |
| C-M7-1-009 | lockfile 缺 RUBY VERSION 而依赖已满足时，check 打印 Resolving dependencies... | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential check-satisfied-nolock-ruby'；'crystal spec s…` |
| C-M7-1-010 | frozen 模式下需要解锁 ruby 时 check 以 16 拒绝，2.7.2 不拒绝 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential check-frozen-ruby-nolock check-deploy-ruby-n…` |
| C-M7-1-011 | platform 的版本操作数取自 requirement，且判定结果始终以 0 退出 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential platform-gemfile-ruby platform-ruby-mismatch…` |
| C-M7-1-012 | 写锁时 RUBY VERSION 记录运行中的解释器版本，2.7.2 额外带 p<patchlevel> | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential ruby-target-match'；'crystal spec spec/m7_rub…` |
| C-M7-1-013 | 解析到平台变体时，进度行带平台后缀 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential lock-platform-variant install-platform-varia…` |
| C-M7-1-014 | BUNDLE_FORCE_RUBY_PLATFORM 为真时只锁 / 装 ruby 变体 | 已实现 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential install-force-ruby-platform install-force-ru…` |
| C-M7-1-015 | ABI 约束（ruby_api_version / major.minor.0）只有单元证据 | 未验证 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'crystal spec spec/m7_ruby_constraints_spec.cr'（describe 'Celerite::In…` |
| C-M7-1-016 | bridge 不可用时运行时校验被跳过，check 省略重解通知 | 已声明差异 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential check-satisfied-nolock-ruby'；'crystal spec s…` |
| C-M7-1-017 | 用 --ruby 更新锁内 RUBY VERSION 的路径未加差分夹具 | 未验证 | [M7-1-ruby-constraints.md](M7-1-ruby-constraints.md) | `'bash script/differential update-ruby'；'crystal spec spec/m7_ruby_runt…` |
| C-M7-2-001 | 已安装判定改用 `<root>/specifications/<full_name>.gemspec`，只有 gem 目录而没有 specification 即判缺失 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential check-installed-spec-without-gemdir check-ge…` |
| C-M7-2-002 | specification 在而解包目录缺时 list 仍通过，show 与 info --path 打警告后 exit 0，info 整块信息改走 stderr | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential check-installed-spec-without-gemdir list-ins…` |
| C-M7-2-003 | specification 与解包目录都缺时 list exit 1、show 与 info exit 7，文案为 `Could not find <full_name> in locally installed gems` | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential list-gem-entirely-missing check-gemdir-witho…` |
| C-M7-2-004 | 裸 show 与 show --paths 按 gem 名排序列举，运行中的 Bundler 参与排序而非固定首行 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential show-listing-order show-paths-order show-lis…` |
| C-M7-2-005 | show bundler 与 info bundler --path 输出单行 gem 根路径，回落基准是 `lib/bundler/cli` | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential show-bundler show-bundler-paths show-bundler…` |
| C-M7-2-006 | list 的 --format=json、两组互斥与校验顺序按 4.0.24 收敛 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential list-json list-json-name list-format-invalid…` |
| C-M7-2-007 | list 的分组发现在无桥环境下同样生效，--only-group 不再误报组不存在 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'crystal spec spec/m7_list_groups_plain_env_spec.cr'；'bash script/diff…` |
| C-M7-2-008 | show 与 info 对被忽略组的依赖抛 GemNotFound 7，且未安装的锁定 gem 优先于组消息 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential show-group-ignored show-missing-installed'；'…` |
| C-M7-2-009 | 无 lockfile 时 show 与 info 先解析 Gemfile 再发现，缺失文案取依赖显示名 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential show-no-lockfile-missing show-no-lockfile-in…` |
| C-M7-2-010 | info 与 show 在精确名未命中时回退解释器默认 gem，多候选时打印编号菜单 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential info-default-gem-fallback info-regex-menu'；'…` |
| C-M7-2-011 | info 按固定顺序输出 gemspec 字段，PATH 与 GIT 源的元数据在已装 specifications 缺位时回退读 gem 目录 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential info-metadata-escapes show-info-installed in…` |
| C-M7-2-012 | check 在依赖已满足时按定义落盘 lockfile，--dry-run 与 frozen 下不写 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential check-rewrites-lock check-dry-run-keeps-lock…` |
| C-M7-2-013 | check 在 Gemfile 依赖集不在锁内时先重新解析，缺失打印三行后 exit 1 且不写锁 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential check-gemfile-new-dependency'；'crystal spec …` |
| C-M7-2-014 | frozen 模式下 ruby 解锁被拒：check exit 16，show 与 info 仍 exit 0，list 不打印解析通知 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential check-frozen-ruby-nolock show-frozen-ruby-no…` |
| C-M7-2-015 | install --local 未命中文案随 vendor/cache 是否存在分档 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential install-local-vendor-cache install-local-ind…` |
| C-M7-2-016 | info 与 show 拒绝第二个位置参数，list 的 usage 行不带 [OPTIONS] | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential info-extra-argument show-extra-argument list…` |
| C-M7-2-017 | check、list、show、info 在读 Gemfile 之前拒绝未知开关 | 已实现 | [M7-2-installed-discovery.md](M7-2-installed-discovery.md) | `'bash script/differential unknown-switch-check unknown-switch-list unk…` |
| C-M7-3-001 | `fund` 从已安装 specifications 的 `funding_uri` metadata 打印资助信息 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_fund_spec.cr'` |
| C-M7-3-002 | `fund` 优先从 PATH/GIT 源的 gemspec 读 `funding_uri` | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential fund-path'` |
| C-M7-3-003 | `fund --group` 按标量语义取组、重复后者覆盖且不切分逗号 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential fund-groups fund-group-development'` |
| C-M7-3-004 | `fund` 的默认组集合等于声明组减 `without` 加 `with` | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential fund-groups-without'` |
| C-M7-3-005 | `fund` 遇缺失 PATH 源按参考 `PathError` 折行报错并 exit 13 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_fund_group_spec.cr'` |
| C-M7-3-006 | `BUNDLE_WITHOUT` 命中 `--group` 时参考崩溃，本实现不复刻 | 已声明差异 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_fund_group_spec.cr'` |
| C-M7-3-007 | `fund` 无锁文件时走 local-only 解析而不是报缺 `Gemfile.lock` | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential fund-no-lockfile'` |
| C-M7-3-008 | `gem --no-git` 生成 9 个文件且不写 `.gitignore` 与 `.git` | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential gem-no-git'` |
| C-M7-3-009 | `gem --rubocop` 与 `--no-rubocop` 按参考 removed 文案 exit 15 且不创建文件 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_gem_template_spec.cr'` |
| C-M7-3-010 | `gem <name>` 目标为同名文件时 exit 32 且不写文件 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_gem_template_spec.cr'` |
| C-M7-3-011 | `gem --help` 渲染 pinned 版本的参考手册页文本 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_gem_options_spec.cr'` |
| C-M7-3-012 | `gem` 的 test/CI/linter/mit/coc/changelog/exe/ext 模板分支按选项渲染 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential gem-options gem-ext'` |
| C-M7-3-013 | `gem` 的枚举值与未知开关按 Thor 文案拒绝并 exit 15 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential gem-invalid'` |
| C-M7-3-014 | `gem --edit` 与 `--bundle` 显式报不支持并 exit 1 | 已声明差异 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_gem_options_spec.cr'` |
| C-M7-3-015 | `gem` 的交互式问卷（test/CI/linter/license/COC/changelog）未实现 | 未实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential gem-default'` |
| C-M7-3-016 | 2.7.2 的 `gem` 模板与成功链接不同，两个 gem 夹具在该 profile 下 deferred | 已声明差异 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential gem-default'` |
| C-M7-3-017 | `console [GROUP]` 在 bundle 语境里 require 依赖后再启动控制台 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential console-group'` |
| C-M7-3-018 | 配置的控制台不在 bundle 内时回退 irb，irb 亦不可用时 exit 1 且末行 `irb is not available` | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_console_spec.cr'` |
| C-M7-3-019 | `console` 的多余位置参数按 Thor 报错并 exit 15 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_console_spec.cr'` |
| C-M7-3-020 | 控制台在独立 ruby 子进程中运行，不是参考的进程内 `console.start` | 已声明差异 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_console_spec.cr'` |
| C-M7-3-021 | IRB 可用时的交互式 console 会话行为未验证 | 未验证 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_console_spec.cr'` |
| C-M7-3-022 | `env` 的 Gem Path 用平台分隔符并按 `Gem.path` 追加默认目录 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_env_output_spec.cr'` |
| C-M7-3-023 | `env` 的 Config Dir 取系统配置目录并以正斜杠渲染 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_env_output_spec.cr'` |
| C-M7-3-024 | `env` 的 Bin Dir 取 `Gem.bindir` | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_env_output_spec.cr'` |
| C-M7-3-025 | `env` 与 `issue` 的 `## Bundler Build Metadata` 用发布常量而非本仓 git 值 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_env_output_spec.cr'` |
| C-M7-3-026 | `bundle version` 追加发布构建元数据，而 `-v` 与 `--version` 只打版本 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential version-plain'` |
| C-M7-3-027 | `bundle version` 的多余位置参数按 Thor 报错并 exit 15 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential version-extra'` |
| C-M7-3-028 | `bundle issue` 在只有 Gemfile、无锁文件时正常解析、写锁并给 `No issues found...` | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential issue-no-lockfile'` |
| C-M7-3-029 | `env` 与 `issue` 共用 Gemfile 段与 `<No <abs> found>` 占位 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_issue_report_spec.cr'` |
| C-M7-3-030 | 无 Gemfile 时参考 `issue` 回溯宿主机 user config，双方输出不可逐字比对 | 未验证 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential issue-no-gemfile'` |
| C-M7-3-031 | `doctor` 的完整诊断面（home 权限、路径组件、Gem path 规则）未实现 | 未实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential doctor-no-lockfile'` |
| C-M7-3-032 | `help` 与 `<cmd> --help` 渲染参考自带的 `.ronn` 手册页 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential help-install'` |
| C-M7-3-033 | 无手册页的命令回退 Thor `command_help`，本命令 option 表未复刻 | 已声明差异 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential help-tree-fallback'` |
| C-M7-3-034 | `env` 的 OpenSSL 块按解释器加载情况打印 | 已实现 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'crystal spec spec/m7_env_output_spec.cr'` |
| C-M7-3-035 | `env` 的多 `gemspec` 指令顺序与去重未验证 | 未验证 | [M7-3-placeholders.md](M7-3-placeholders.md) | `'bash script/differential env-gemspec'` |
| C-M7-4-001 | 配置 `mirror.<url>` 后抓取先走镜像，镜像失败再回退原 remote | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_download_settings_spec.cr'；'crystal spec spec/co…` |
| C-M7-4-002 | `mirror.<url>.fallback_timeout` 按 Bundler 语义解析：true→0.1 秒、false→0、其余按 `to_i` 整数截断 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_download_settings_spec.cr'` |
| C-M7-4-003 | HTTP 代理按 `http_proxy`/`HTTP_PROXY` 或 config `proxy` 生效：http 用绝对 URI 请求行，https 先 CONNECT 建隧道 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_proxy_spec.cr'` |
| C-M7-4-004 | `no_proxy` 按主机后缀匹配绕过代理，`*` 绕过全部 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_proxy_spec.cr'` |
| C-M7-4-005 | `https_proxy`/`ALL_PROXY` 不参与取代理，与参考一致 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_proxy_spec.cr'` |
| C-M7-4-006 | `~/.gemrc` 的 `:http_proxy` 优先于 `http_proxy` 环境变量 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_gemrc_proxy_spec.cr'；'bash script/differential l…` |
| C-M7-4-007 | `~/.gemrc` 把 `:http_proxy` 设为 `:no_proxy` 时禁用代理，即使环境变量另给了地址 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_gemrc_proxy_spec.cr'；'bash script/differential l…` |
| C-M7-4-008 | `.bundle/config` 的 `proxy`/`http_proxy` 参与取代理，参考不参与 | 已声明差异 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_proxy_spec.cr'` |
| C-M7-4-009 | gem 下载路径的重定向次数受 `redirect`（默认 5）限制，超限抛 `DownloadError` | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_transport_evidence_spec.cr'；'crystal spec spec/m…` |
| C-M7-4-010 | 302 重定向的 `Location` 为相对路径时按 base URI 解析，且跳转后沿用重定向目标路径而非重新拼 `/gems/…` | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_transport_evidence_spec.cr'` |
| C-M7-4-011 | 紧凑索引路径跟随 301/302/303/307/308 时不计数、无上限 | 未实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/compact_index/http_fetcher_spec.cr'` |
| C-M7-4-012 | gem 下载路径对 404 与 5xx 都重试，`retries: 0` 时只请求一次 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_transport_evidence_spec.cr'` |
| C-M7-4-013 | 紧凑索引只对 408/429/5xx 重试，404 等其余状态立即失败 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/compact_index/http_fetcher_spec.cr'` |
| C-M7-4-014 | `timeout` 配置映射为连接超时，且小于 1 的值回落到默认值 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_download_settings_spec.cr'` |
| C-M7-4-015 | `ssl_ca_cert` 指向 PEM 文件时装入该文件、指向目录时按 CApath 装入、未配置时用默认信任库 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_tls_trust_store_spec.cr'` |
| C-M7-4-016 | `ssl_verify_mode` 为 `none` 时跳过校验，默认 peer 校验失败转成 `CertificateFailureError` 并以 17 退出 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_transport_evidence_spec.cr'；'crystal spec spec/m…` |
| C-M7-4-017 | `ssl_client_cert` 指向的同一 PEM 内同时装载证书链与私钥，因而客户端证书认证（mTLS）可用 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_client_cert_spec.cr'` |
| C-M7-4-018 | `ssl_client_key` 被显式配置时快速失败，因为参考没有该配置键 | 已声明差异 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_build_args_spec.cr'` |
| C-M7-4-019 | `legacy_index`/`full_index` 被显式配置时快速失败，因为参考没有这两个配置键 | 已声明差异 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_build_args_spec.cr'` |
| C-M7-4-020 | 紧凑索引不可用时没有回退到 legacy 全量索引（`specs.4.8.gz`）的路径 | 未实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'bash script/differential install-platforms-add-local'；'crystal spec s…` |
| C-M7-4-021 | `--full-index` 开关被接受但没有对应语义 | 未验证 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_install_family_switches_spec.cr'` |
| C-M7-4-022 | `path.system` 为真且无显式 `path` 时安装根为 `Gem.dir`，且不追加 `ruby/<abi>` 层 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_path_system_spec.cr'` |
| C-M7-4-023 | 显式 `path` 与 `path.system` 同时成立时抛 `PathConflictError`，以 15 退出 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'bash script/differential install-path-conflict'；'crystal spec spec/m7…` |
| C-M7-4-024 | 完全没有 `path` 配置时仍安装到 `<home>/.bundle/ruby/<abi>`，参考装进系统 gems | 已声明差异 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_path_system_spec.cr'` |
| C-M7-4-025 | 部署模式且无显式 `path` 时安装根默认 `vendor/bundle` | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_deployment_path_spec.cr'；'bash script/differenti…` |
| C-M7-4-026 | 自定义 `path` 的安装提示按项目根相对化，并以 `./` 前缀输出 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'bash script/differential install-custom-path-summary'；'crystal spec s…` |
| C-M7-4-027 | `build.<gem>` 参数经桥传到原生扩展编译，按 gem 名分别取用 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_build_args_spec.cr'` |
| C-M7-4-028 | 目标主机不可达时输出参考措辞并以 17 退出，不打印内部错误 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_network_down_spec.cr'；'bash script/differential …` |
| C-M7-4-029 | 同进程内连续调用时，`--retry` 只作用于当次调用，不泄漏到下一次 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_cli_state_isolation_spec.cr'；'crystal spec spec/…` |
| C-M7-4-030 | 索引返回 403 时先打印 `Fetching source index from <完整源 URI>` 再以 17 退出 | 已实现 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_forbidden_spec.cr'；'crystal spec spec/m7_network…` |
| C-M7-4-031 | gem 下载遇 403 时重试三次后抛 `Bundler::HTTPError: Could not download gem` 并以 5 退出，但不再打印参考的 Ruby 回溯 | 已声明差异 | [M7-4-network-options.md](M7-4-network-options.md) | `'crystal spec spec/m7_forbidden_download_spec.cr'；'crystal spec spec/m…` |
| C-M7-5-001 | 判据装具把 git 源夹具的暂存仓库建在工作目录内并以 Windows 路径交给 `git -C` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential add-git add-ref'` |
| C-M7-5-002 | GIT 锁段按 `ref, branch, tag, submodules, glob` 的固定顺序写选项，非默认 glob 才写 `glob:` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_source_lock_options_spec.cr'；'bash script/differ…` |
| C-M7-5-003 | git 源 `tag:` 与 `glob:` 的锁段语义在本机无法取证 | 未验证 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential git-tag git-glob'` |
| C-M7-5-004 | git 源 `submodules:` 选项两侧都没有可执行证据 | 未验证 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential git-submodules'` |
| C-M7-5-005 | git / path 源的身份包含 uri、ref、branch、glob、submodules，源变化必须重解而非复用锁定路径 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_git_source_reuse_spec.cr'` |
| C-M7-5-006 | PATH 锁段只在 glob 非默认值时写 `glob:`，默认值是 `{,*,*/*}.gemspec` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential path-glob-monorepo'；'crystal spec spec/m7_so…` |
| C-M7-5-007 | path 源按默认 glob 的三档深度取 gemspec，未命中时归属串为 `source at \`<path>\`` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential path-glob-default-root path-glob-default-nes…` |
| C-M7-5-008 | path 源按 gemspec 自身的 name 匹配请求，未命中即报错且不写锁 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential path-source-missing-gem plugin-source-missin…` |
| C-M7-5-009 | glob 变化是否重解由「锁侧 path+glob 下可见 gemspec 的 name/version 集」决定，而非 glob 字符串 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential path-gemspec-bump-reresolves check-frozen-pa…` |
| C-M7-5-010 | `check` 重写锁文件时保留 PATH / GIT / PLUGIN SOURCE 段与既有 CHECKSUMS | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential check-rewrite-keeps-path-source check-rewrit…` |
| C-M7-5-011 | `cache` / `package` 把工程外 path 源整目录复制进 `<cache>/<gem name>/` 并打 `.bundlecache` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential cache-all-path cache-no-all-path'；'crystal s…` |
| C-M7-5-012 | `install` / `update` / `add` 在工程内存在 `vendor/cache` 时刷新缓存并逐包打印 `  * <file>.gem` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential install-refreshes-app-cache'；'crystal spec s…` |
| C-M7-5-013 | 首次 `install` 也把工程外 path 源复制进 `vendor/cache`，绝对 `BUNDLE_PATH` 原样渲染 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential install-path-source-app-cache-first'；'crysta…` |
| C-M7-5-014 | 私有 source 的 401 按是否带凭据分派 `AuthenticationRequiredError` / `BadAuthenticationError`，均以 17 退出且不重试 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_authentication_errors_spec.cr'` |
| C-M7-5-015 | 索引期 403 归因到完整源 URI（含尾斜杠），紧凑索引 403 回退 legacy 索引后再报错 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_forbidden_spec.cr'` |
| C-M7-5-016 | gem 下载 403 按 4 轮重试并逐轮打印 `Retrying download gem …`，最终以 `InstallError`（5）失败 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_forbidden_download_spec.cr'` |
| C-M7-5-017 | `~/.gemrc` 的 `:http_proxy` 参与代理解析，取值为 `:no_proxy` 时关闭代理 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential lock-gemrc-proxy lock-gemrc-no-proxy'；'cryst…` |
| C-M7-5-018 | `~/.gemrc` 凭据源、`WWW-Authenticate: Basic` 与代理 CONNECT 后的 401 尚未实现 | 未实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_authentication_errors_spec.cr'` |
| C-M7-5-019 | `--local` 只从已安装 gems 与 `vendor/cache` 取材，不查任何索引（含 `file://`），缺失即以 exit 7 报参考文案 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential install-local install-local-no-cache install…` |
| C-M7-5-020 | `install --local` 直接从 `vendor/cache` 取包，不打印 `Fetching`，并打印 `Updating files in vendor/cache` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential install-local-vendor-cache'；'crystal spec sp…` |
| C-M7-5-021 | `--local` 下新增非本地依赖以 exit 7 失败，且不写出被改坏的锁 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential install-local-new-dep-not-installed'；'crysta…` |
| C-M7-5-022 | `--prefer-local` 先取远端索引再以本工程已安装 gems / `vendor/cache` 为候选，本地为空才回落远端 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_prefer_local_spec.cr'` |
| C-M7-5-023 | Windows 下 `Dir.glob` 把 `\` 当转义符，glob 枚举改用 `Dir.children` + `File.match?` 的 `Glob.paths` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_vendor_cache_spec.cr'；'bash script/differential …` |
| C-M7-5-024 | 锁文件写入被拒映射为 `PermissionError` 并以 23 退出 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_filesystem_errors_spec.cr'` |
| C-M7-5-025 | 文件系统错误按参考分档映射为 `PermissionError` / `TemporaryResourceError` / `NoSpaceOnDeviceError` / `ReadOnlyFileSystemError` / `OperationNotPermittedError` / `OperationNotSupportedError` / `VirtualProtocolError` / `GenericSystemCallError` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_filesystem_error_mapping_spec.cr'` |
| C-M7-5-026 | 既有锁文件含 CRLF 时写回保持 CRLF，新建锁文件用 LF | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential lock-preserve-crlf'；'crystal spec spec/m7_lo…` |
| C-M7-5-027 | 原生扩展编译失败映射为 `InstallError`（5）：消息含真实回溯与 `In Gemfile:` 依赖树，半装目录保留、只删 `specifications/<full>.gemspec` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_install_failure_spec.cr'` |
| C-M7-5-028 | 扩展编译失败后不在 `<bundle>/cache/` 留下该 gem 的 `.gem` | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/m7_install_failure_spec.cr'` |
| C-M7-5-029 | 安装结束后不留 `bundler.lock`，并按参考补齐 `ruby/<abi>` 下的记账目录 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential install-bundle-layout'；'crystal spec spec/m7…` |
| C-M7-5-030 | Linux gnu / musl 平台匹配只做到平台字符串归一，真实 Linux ABI 运行矩阵未验证 | 未验证 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'crystal spec spec/gem/platform_spec.cr'` |
| C-M7-5-031 | 多 Ruby ABI 的平台变体选择只在宿主 `x64-mingw-ucrt` 上取证，跨 ABI 矩阵未验证 | 未验证 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential multi-platform-lock multi-platform-install m…` |
| C-M7-5-032 | `add --strict` 在 install 阶段失败时保留已追加的 Gemfile 与已改写的锁，注入阶段失败时不写盘 | 已实现 | [M7-5-sources-platforms.md](M7-5-sources-platforms.md) | `'bash script/differential add-strict'；'crystal spec spec/m7_add_strict…` |
| C-M7-6-001 | `plugin install --path` 把 plugins.rb 声明的命令写入项目索引 `commands:` | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_commands_spec.cr' 与 'bash script/differen…` |
| C-M7-6-002 | 索引中登记的插件命令先于 `bundler-<name>` PATH 回退分发 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_commands_spec.cr'` |
| C-M7-6-003 | `help <插件命令>` 以 `--help` 执行插件命令 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_commands_spec.cr'` |
| C-M7-6-004 | `plugin list` 按索引插入序输出插件名、`-----` 分隔线与该插件的命令 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-command-list'` |
| C-M7-6-005 | 重复安装同一插件只打印一次 `Installed plugin` | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-command-reinstall'` |
| C-M7-6-006 | 两个插件声明同名命令时安装失败 exit 29 且索引保持不变 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-conflict-command' 与 'crystal spec spe…` |
| C-M7-6-007 | 两个插件注册同名 source 类型时安装失败 exit 29 且索引保持不变 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-conflict-source' 与 'crystal spec spec…` |
| C-M7-6-008 | `--path` 插件注册失败时其源目录被删除 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-conflict-source plugin-conflict-comma…` |
| C-M7-6-009 | plugins.rb 的 `add_hook` 事件写入索引 `hooks:` 段 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-install-hooks' 与 'crystal spec spec/m…` |
| C-M7-6-010 | `plugin uninstall` 删除索引 hooks 段，之后的 install 不再触发该 hook | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-hook-uninstall' 与 'crystal spec spec/…` |
| C-M7-6-011 | `after-install` 按安装集逐个 spec 触发，running Bundler 的伪 spec 最先 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-hook-per-gem' 与 'crystal spec spec/m7…` |
| C-M7-6-012 | `before-install-all` 在解析前触发、`after-install-all` 在 `Bundle complete!` 前触发 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-hook-before-after-all' 与 'crystal spe…` |
| C-M7-6-013 | hook 块抛异常时 install exit 1 且不写 Gemfile.lock | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-hook-raise' 与 'crystal spec spec/m7_p…` |
| C-M7-6-014 | 插件加载期抛异常时 install exit 1 | 已声明差异 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_hook_failure_spec.cr'` |
| C-M7-6-015 | 插件 load path 目录缺失时打印告警并继续，exit 0 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_hook_failure_spec.cr'` |
| C-M7-6-016 | `BUNDLE_PLUGINS=false` 时插件不加载、hook 不触发 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_hook_failure_spec.cr spec/m7_plugin_hook_…` |
| C-M7-6-017 | plugins.rb 声明未定义 hook 事件时 install exit 29 且不留索引 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-install-bad-event' 与 'crystal spec sp…` |
| C-M7-6-018 | 插件安装失败消息按终端宽度折行，只认 `THOR_COLUMNS` | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-install-bad-event plugin-install-bad-…` |
| C-M7-6-019 | Gemfile 的 `source …, type: :x` 预装推断插件 `bundler-source-x`，缺 gem 时 exit 7 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-gemfile-missing install-typed-source-…` |
| C-M7-6-020 | 插件关闭时 Gemfile 中的 `type:` source 使 install exit 15 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_gemfile_plugins_spec.cr'` |
| C-M7-6-021 | typed plugin source 的 `lock` 写出完整 `PLUGIN SOURCE` 段 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-typed' 与 'crystal spec spec/m7…` |
| C-M7-6-022 | 锁内已有的 `PLUGIN SOURCE` 在再次 `lock` 时复用而不重解析 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-locked'` |
| C-M7-6-023 | 插件未安装时含 typed source 的 Gemfile 在 `lock` / `check` 报 exit 15 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-locked-missing'` |
| C-M7-6-024 | 锁内 typed source 的 spec 视为已安装，`check` exit 0 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-locked-check'` |
| C-M7-6-025 | typed plugin source 的 install 成功路径输出安装行与 post-install 消息，并隐藏推断依赖 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-install' 与 'crystal spec spec/…` |
| C-M7-6-026 | 真实打包的第三方插件 gem 注册自定义 source 后端到端可用 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-gem-end-to-end'` |
| C-M7-6-027 | typed plugin source 中不存在的 gem 按插件源归因报 exit 7 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-missing-gem' 与 'crystal spec s…` |
| C-M7-6-028 | `plugin install <gem> --source` 把插件 gem 物化到项目插件树 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-install-source' 与 'crystal spec spec/…` |
| C-M7-6-029 | 无 Gemfile 时插件命令面走全局 `~/.bundle/plugin` | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_install_source_spec.cr'` |
| C-M7-6-030 | 非规范 `file://C:/…` 远程在索引与下载器两侧归一到同一本地路径 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-install-source-noncanonical' 与 'cryst…` |
| C-M7-6-031 | `plugin uninstall` 的选项与空参语义跟参考一致 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-uninstall-args' 与 'crystal spec spec/…` |
| C-M7-6-032 | `plugin uninstall` 删除插件树内的 checkout 目录 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-uninstall-index'` |
| C-M7-6-033 | `plugin new` 报未知子命令 exit 15 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-new-unknown' 与 'crystal spec spec/m7_…` |
| C-M7-6-034 | 远端 `--source` 插件安装的失败路径 exit 7 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source'` |
| C-M7-6-035 | 插件 source 的非空 `options_to_lock` 落进 `PLUGIN SOURCE` 段 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-lock-options'` |
| C-M7-6-036 | 远端 `--source` 插件安装的成功路径（`plugin-source-ok`） | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-source-ok'` |
| C-M7-6-037 | 无 Gemfile / 全局插件根下安装时 hooks 的落盘 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-global-hook-root'；'crystal spec spec/…` |
| C-M7-6-038 | `plugin install --git/--branch/--ref` 的 git checkout 端到端 | 已实现 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-git-install'（新夹具，双 profile PASS）+ 'cr…` |
| C-M7-6-039 | 缺失 load path 的告警在参考里按每次 hook 重复，我方每命令一次 | 已声明差异 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_hook_failure_spec.cr'` |
| C-M7-6-040 | 失败回滚删除 `--path` 源目录只对三类注册失败复刻 | 已声明差异 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-conflict-command plugin-conflict-sour…` |
| C-M7-6-041 | 参考同进程二次加载导致每 spec 触发两次的重复注册未复刻 | 已声明差异 | [M7-6-plugins.md](M7-6-plugins.md) | `'bash script/differential plugin-hook-per-gem'` |
| C-M7-6-042 | 插件加载失败的 `--- ERROR REPORT TEMPLATE ---` 段未复刻 | 已声明差异 | [M7-6-plugins.md](M7-6-plugins.md) | `'crystal spec spec/m7_plugin_hook_failure_spec.cr'` |
| C-M7-7-001 | `script/differential` 头部逐条列出 N1–N10 十条归一化规则 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential env-report install-check'` |
| C-M7-7-002 | 退出码与 N1–N7 之外的 stdout/stderr 逐字且同序比较 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential install-fresh'` |
| C-M7-7-003 | 只有 N7 对连续 `Fetching ` 行排序，其余语义行序不变 | 已取代 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential install-fresh'` |
| C-M7-7-004 | N5 只删除 `## Environment` 体、保留标题，删到下一个 `## ` 标题为止 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential env-report'` |
| C-M7-7-005 | N8 把两侧的 C 编译器统一到 Ruby 自带工具链，`CELERITE_DIFF_EXTRA_PATH` 可追加目录 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential native-ext'` |
| C-M7-7-006 | N9 对安装树里的编译产物只比存在性与可加载性，不比字节 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential native-ext'` |
| C-M7-7-007 | 归一化清单在文档与脚本头部已不一一对应：文档缺 N8，N10 被两条规则共用 | 未实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential plugin-hook-raise env-report'` |
| C-M7-7-008 | 安装树比较覆盖匹配目录集合、相对路径集合、内容、可执行位、symlink 目标五类判定 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential install-check'` |
| C-M7-7-009 | symlink 按相对路径与 `readlink` 目标比较，并区分目标不同、类型不同、单侧存在 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential-installed-tree-selftest'` |
| C-M7-7-010 | 无法创建真符号链接时安装树自测记 SKIP 并输出复现命令 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential-installed-tree-selftest'` |
| C-M7-7-011 | 可执行位只在非 Windows 宿主上比较 | 已声明差异 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential install-check'` |
| C-M7-7-012 | `first-line` 探针按字节比较指定文件的首行 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential binstubs-shebang-line'` |
| C-M7-7-013 | `file-contains` 探针按 `<path>\t<needle>` 在两侧做字节命中 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential lock-missing-dependency-edges'` |
| C-M7-7-014 | `file-equals` 探针逐字比较整份文件，并支持按 profile 的变体标记 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential checksums-refresh-cache-deleted'` |
| C-M7-7-015 | `file-crlf` 在 4.x 断言锁文件至少含一个 CRLF 且无孤立 LF、在 2.x 断言纯 LF | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential lock-preserve-crlf'` |
| C-M7-7-016 | `file-absent` 通道要求两侧都不存在指定相对路径 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential plugin-hook-raise'` |
| C-M7-7-017 | `file-exists` 通道要求两侧都存在指定相对路径 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential install-refreshes-app-cache'` |
| C-M7-7-018 | 空的 `file-absent`/`stderr-contains` 标记等同「未提供该标记」 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential harness-assert-selftest'` |
| C-M7-7-019 | `stderr-contains` 命中后跳过逐字 stderr 比较并打印 N10 提示 | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'bash script/differential plugin-hook-raise'` |
| C-M7-7-020 | `deferred-<profile>` 标记把夹具在该 profile 记为 skipped | 已实现 | [M7-7-differential-harness.md](M7-7-differential-harness.md) | `'BUNDLER_REF_VERSION=2.7.2 bash script/differential add-group'` |
| C-M7-8-001 | 套件经 PATH 上的 `bundle` shim 把上游例内的 `bundle` 调用真实路由到 Celerite | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-002 | `CELERITE_BUNDLE_HELPER_OVERRIDE=0` 退回基线驱动，报告打印 `WARNING: NOT driving celerite` | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'CELERITE_BUNDLE_HELPER_OVERRIDE=0 bash script/upstream-specs'` |
| C-M7-8-003 | rspec 的非零退出经 `pipefail` 传成 harness 的退出码 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-004 | 套件只跑 lockfile 家族的 `spec/lock/lockfile_spec.rb`，不作 full upstream suite 声明 | 已声明差异 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-005 | 失败按异常类与消息特征分到七个桶，harness 与离线重算共用同一规则模块 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-006 | 断言失败一律归 `product:candidates`，不因消息里出现 `Fetching ` 落入夹具桶 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-007 | 环境类桶先于产品类桶判定 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-008 | CHECKSUMS 段整行缺失时 `install` 打印 `Resolving dependencies...` 并真解析 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/differential checksums-refresh-cache-deleted'；'crystal sp…` |
| C-M7-8-009 | CHECKSUMS 条目存在但值空时不触发解析，`install` 不打印 `Resolving dependencies...` | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/differential checksums-empty-lock'；'crystal spec spec/m7_…` |
| C-M7-8-010 | 锁依赖边缺失时自愈保持锁定版本，不升级到索引里的更高版本 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/differential install-autoheals-locked-dependency-edges'；'…` |
| C-M7-8-011 | 锁定 spec 行缺失但依赖边仍在时，`lock` 按参考剔除该行并重解析 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/differential lock-missing-locked-spec-line'；'crystal spec…` |
| C-M7-8-012 | `--local` 且锁已存在时不再无条件复用锁定集合，Gemfile 新增的未安装依赖报 exit 7 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/differential install-local-new-dep-not-installed'；'crysta…` |
| C-M7-8-013 | 上游夹具仓被毒化时 harness 自愈，取不到本机 rake 缓存则 fail-open 并告警 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'CELERITE_SKIP_TEST_DEPS=1 bash script/upstream-specs'` |
| C-M7-8-014 | harness 的报告只写 `.upstream-specs/`，不写 `docs/` | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-015 | harness 只探测既有 celerite 二进制，不自行重建 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-016 | 套件结论只覆盖 4.0.24 profile，2.7.2 未复采 | 未验证 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'UPSTREAM_REV=v2.7.2 bash script/upstream-specs'` |
| C-M7-8-017 | 补充 CHECKSUMS digest 与 `path_expander` 锁体行的两处未对齐 | 已声明差异 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/upstream-specs'` |
| C-M7-8-018 | 完整锁里指向 `bundler` 的依赖边不再让锁被误判为不完整而重写 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/differential install-keeps-lock-with-bundler-edge'；'cryst…` |
| C-M7-8-019 | `install` 重写锁时依赖行按字母序输出，锁内容与 `lock` 的产物一致 | 已实现 | [M7-8-upstream-specs.md](M7-8-upstream-specs.md) | `'bash script/differential install-rewrites-lock-in-lock-order'；'crysta…` |
| C-M7-9-001 | `VersionUnion` 的区间扫描不再提前耗尽无上界一侧，多 `!=` 排除的 union 保持完整 | 已实现 | [M7-9-rails-regression.md](M7-9-rails-regression.md) | `'crystal spec spec/m7_resolver_version_union_intersect_spec.cr'` |
| C-M7-9-002 | 锁文件按本地平台变体物化，不退回 ruby 变体 | 已实现 | [M7-9-rails-regression.md](M7-9-rails-regression.md) | `'crystal spec spec/m7_platform_variant_selection_spec.cr'；'bash script…` |
| C-M7-9-003 | Rails 8.0.2 真实应用的端到端安装未通过，该 profile 的兼容声明未恢复 | 已取代 | [M7-9-rails-regression.md](M7-9-rails-regression.md) | `'bash script/differential install-check'（同形态的入库回归门禁；rails 规模夹具不入库，端到端无…` |
| C-M7-9-004 | 锁文件渲染不在 GEM 段列出 bundler 自身，其 CHECKSUMS 条目由自校验块唯一写出 | 已实现 | [M7-9-rails-regression.md](M7-9-rails-regression.md) | `'bash script/differential lock-normalize'；'crystal spec spec/m7_lock_r…` |
| C-M7-9-005 | rails 8.0.2 规模下锁已完整时 `install` 不再把锁收缩成 1 条 spec，装出的 gem 集合与 oracle 锁一致 | 已实现 | [M7-9-rails-regression.md](M7-9-rails-regression.md) | `'bash script/differential install-check'；端到端复跑步骤与原始数字见 '../roadmap-evi…` |
| C-M7-docs-001 | 新证据写入当日的 `docs/compat-evidence/YYYY-MM-DD.md`，同日多条追加到文件末尾 | 已实现 | [M7-docs-sync.md](M7-docs-sync.md) | `'bash script/differential install-check'；'ls docs/compat-evidence/2026…` |
| C-M7-docs-002 | 主报告只保留当前状态与索引，不再追加流水 | 已实现 | [M7-docs-sync.md](M7-docs-sync.md) | `'bash script/differential install-check'；'grep -n "不再追加流水" docs/compat…` |
| C-M7-docs-003 | 引用历史结论写「compat-evidence 日期文件 + 节标题」，不写 `compat-report.md:<行号>` | 已实现 | [M7-docs-sync.md](M7-docs-sync.md) | `'bash script/differential install-check'；'grep -rn "compat-report\.md:…` |
| C-M7-docs-004 | `docs/roadmap.md` 只维护任务陈述与复选框，流水落 `docs/roadmap-evidence/`，不写行号 | 已实现 | [M7-docs-sync.md](M7-docs-sync.md) | `'bash script/differential install-check'；'grep -rn "roadmap\.md:[0-9]"…` |
| C-M7-docs-005 | 被取代的旧结论保留原文，由新条目写明取代关系，不回改旧条目 | 已实现 | [M7-docs-sync.md](M7-docs-sync.md) | `'bash script/differential install-check'；'grep -n "保留原文" docs/compat-e…` |
| C-M7-suite-001 | verbose 回显 spec 的实参对齐六参签名，全套件编译期失败消除 | 已实现 | [M7-suite.md](M7-suite.md) | `'crystal spec spec/m7_verbose_echo_spec.cr'` |
| C-M7-suite-002 | spec 间 `BUNDLE_GEMFILE` 泄漏链已被 env 复原切断 | 已实现 | [M7-suite.md](M7-suite.md) | `'crystal spec spec/m7_binstubs_path_source_spec.cr'` |
| C-M7-suite-003 | CLI 每次调用重算 verbose 与 retry 开关，不继承上一次调用 | 已实现 | [M7-suite.md](M7-suite.md) | `'crystal spec spec/m7_cli_state_isolation_spec.cr'` |
| C-M7-suite-004 | 全量 `crystal spec` 在本机能跑到 `Finished` 汇总行 | 已实现 | [M7-suite.md](M7-suite.md) | `'crystal spec'` |
| C-M7-suite-005 | `m7_clean` 的期望按参考 `use_system_gems?` 守卫更正为 exit 15 | 已实现 | [M7-suite.md](M7-suite.md) | `'crystal spec spec/m7_clean_spec.cr'；'bash script/differential clean-n…` |
| C-M7-suite-006 | `m7_show_order` 在参考 lib 缺席时记 `pending!`，不硬失败 | 已实现 | [M7-suite.md](M7-suite.md) | `'crystal spec spec/m7_show_order_spec.cr'` |
| C-cross-001 | `bundle exec` 的子进程在 Unix 上随父进程收到 SIGINT/SIGTERM 而终止，Windows 上共享控制台 | 已声明差异 | [cross-cutting.md](cross-cutting.md) | `'crystal spec spec/m7_exec_spec.cr'` |
| C-cross-002 | 可直接加载的 Ruby 脚本走 `Kernel.load` 运行时适配器，`disable_exec_load` 可绕过 | 已声明差异 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential exec-loader exec-loader-disabled exec-thor-v…` |
| C-cross-003 | install / update / pristine 在 `<bundle_path>/bundler` 上取独占锁，并发运行串行化 | 已实现 | [cross-cutting.md](cross-cutting.md) | `'crystal spec spec/process_lock_spec.cr spec/process_race_spec.cr'` |
| C-cross-004 | `--cooldown` 只校验数值与主远程的 Gemfile per-source，非适用命令未单独加固 | 已声明差异 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential outdated-cooldown-http outdated-cooldown-tab…` |
| C-cross-005 | `add --group` 在 2.7.2 profile 下 deferred，不是 passed | 已声明差异 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential add-group'` |
| C-cross-006 | 纯 Ruby gem 先于原生扩展 gem 安装，顺序由 `cache-all-platforms` 探针钉住 | 已实现 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential cache-all-platforms'` |
| C-cross-007 | 安装后的 `.gemspec` 采用 RubyGems stub 格式，与参考模式一致 | 已实现 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential install-force'` |
| C-cross-008 | Ruby 运行时场景走参考的 `bundler/setup`，不是独立轻量 Ruby 运行时 | 已声明差异 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential ruby-api'` |
| C-cross-009 | 并发下载按 name/version/platform 做进程内 single-flight 去重，不声称分布式互斥 | 已声明差异 | [cross-cutting.md](cross-cutting.md) | `'crystal spec spec/process_lock_spec.cr'` |
| C-cross-010 | `BUNDLE_GEMFILE` 指向缺失路径时，读类命令统一报单行 `<绝对路径> not found` 并 exit 10 | 已实现 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential gemfile-env-missing'；'crystal spec spec/m7_g…` |
| C-cross-011 | `BUNDLE_GEMFILE` 指向缺失路径时，写类命令保留 exit 1 的裸 `Errno::ENOENT`，未复刻参考的崩溃报告 | 已声明差异 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential gemfile-env-missing'` |
| C-cross-012 | `--gemfile` 指向缺失文件时报单行 `<展开路径> not found` 并 exit 10，折行交给统一的 word_wrap | 已取代 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential check-gemfile-missing'` |
| C-cross-013 | 连续 `Installing` 行的行序在参考侧由并行安装线程决定，差分归一化把 `Fetching` 与 `Installing` 连续行一并排序 | 已实现 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential pristine-named binstubs-shebang'` |
| C-cross-014 | `GemfileNotFound` 消息按统一的 `word_wrap` 折行：短路径单行、超列宽折行，与参考三形态逐字一致 | 已实现 | [cross-cutting.md](cross-cutting.md) | `'bash script/differential check-gemfile-missing'；'crystal spec spec/m7…` |

合计 243 条断言（已实现 197 · 已声明差异 26 · 未实现 6 · 未验证 11 · 已取代 3）。
<!-- END GENERATED INDEX -->
