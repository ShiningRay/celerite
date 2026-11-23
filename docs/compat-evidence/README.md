<!-- 治理说明：本目录由 docs/compat-report.md 的追加式证据日志按日拆分而来，正文逐字保留、未改写任何结论。 -->

# 兼容性证据日志（compat-evidence）

本目录保存治理前 `docs/compat-report.md` 的原始内容：`2026-11-11.md` 是报告头部快照（原行 1-401），其余按日文件是追加式证据日志（原行 402-7410）。
拆分只做「搬运 + 定位」：正文逐字保留，未删改任何结论、数字或锚点引用；
每个节前补一行 `<!-- 原 compat-report.md 行 N-M -->` 注释，用于回溯原始位置。

当前状态、未支持清单、已声明差异与复现命令见 [../compat-report.md](../compat-report.md)；
主报告只保留现状快照，不再追加流水。

按断言组织的结论账本（现在有哪些兼容性断言成立、凭什么成立、怎么重跑）见
[../compat-claims/README.md](../compat-claims/README.md)；本目录只保留过程档案。

## 写入规则

- 新证据写到**当日的 `YYYY-MM-DD.md`**；同一天多条按时间顺序追加到文件末尾。
- 每条新证据用二级标题 `## <日期>：<主题>`（子项用 `###`），写清：oracle（参考 Bundler 行为）、参考锚点（`vendor/reference` 中的文件:行）、实现位置（`src/...` 文件:行）、证据（spec 计数 / 差分夹具名与 PASS-FAIL / 日志路径）、已声明差异。
- 只引用**当前还成立**的事实；过期结论在被后续条目取代时，保留原文并在新条目里写明取代关系，不回去改旧条目。
- 主报告 `../compat-report.md` 只放当前状态与索引；不要把流水写回主报告。
- 文内引用同一目录的文件用相对路径（如 `2026-11-20.md`），引用主报告用 `../compat-report.md`。
- **本目录是过程档案，不是结论所在**：一条证据跑出来、被复核并稳定后，把结论抽成 `../compat-claims/` 里的一条断言（按子项而非按日期组织）。查「现在有哪些兼容性断言成立」应读 compat-claims，不要逐日翻本目录。

## 逐日文件

| 日期 | 文件 | 节数 | 字节 | 原始行区间 |
| --- | --- | ---: | ---: | --- |
| 2026-11-11 | [2026-11-11.md](2026-11-11.md) | 8 | 79,085 | 1-401 |
| 2026-11-12 | [2026-11-12.md](2026-11-12.md) | 5 | 50,821 | 402-526 |
| 2026-11-13 | [2026-11-13.md](2026-11-13.md) | 9 | 48,236 | 462-673 |
| 2026-11-14 | [2026-11-14.md](2026-11-14.md) | 10 | 46,486 | 674-907 |
| 2026-11-15 | [2026-11-15.md](2026-11-15.md) | 27 | 143,415 | 908-1868 |
| 2026-11-16 | [2026-11-16.md](2026-11-16.md) | 29 | 152,710 | 1869-2802 |
| 2026-11-17 | [2026-11-17.md](2026-11-17.md) | 15 | 75,519 | 2803-3556 |
| 2026-11-18 | [2026-11-18.md](2026-11-18.md) | 3 | 26,956 | 3557-3720 |
| 2026-11-19 | [2026-11-19.md](2026-11-19.md) | 32 | 163,065 | 3721-4874 |
| 2026-11-20 | [2026-11-20.md](2026-11-20.md) | 25 | 102,628 | 4875-5592 |
| 2026-11-21 | [2026-11-21.md](2026-11-21.md) | 44 | 157,134 | 5593-7071, 7093-7169 |
| 2026-11-22 | [2026-11-22.md](2026-11-22.md) | 26 | 159,369 | 7072-7092, 7170-7410 |
| 2026-11-23 | [2026-11-23.md](2026-11-23.md) | 59 | 385,873 | 治理后新建，无原始行区间 |

合计 292 个证据节（13 个日期文件，按 `^## ` 计数；字节列为 `[System.IO.File]::ReadAllBytes(...).Length` 的 UTF-8 原始字节数，与字符数不同：`2026-11-23.md` 实测 286,300 字符 / 385,873 字节）：其中 `2026-11-11.md` 的治理前报告头部快照 8 节（行 1-401），其余按日文件 284 节（行 402-7410；另有 `2026-11-23.md` 为治理后新建，无原始行区间）；
上表「原始行区间」是当日在原文件中的跨度，逐节精确行区间见各文件节前注释。

末日两行的区间是**交错**的（`5593-7071, 7093-7169` 与 `7072-7092, 7170-7410`）：原追加日志并非严格按日期排序，
`2026-11-22` 的 task-108 条目（原行 7072-7092）写在 `2026-11-21` 的 task-112 条目（原行 7093-7169）之前。
按日期取文件时请以各节前注释的原始行区间为准；两行的区间并集覆盖原行 402-7410，无空隙、无重叠。

「节数」列自本次（task-144）起按各文件 `^## ` 标题的实测计数填写（`grep -c '^## ' <文件>`，与上表字节列同源回读）：`2026-11-11` 由标签 `头部快照` 改为实测 8；`2026-11-12` 由 7 改为 5、`2026-11-13` 由 10 改为 9、`2026-11-14` 由 13 改为 10——旧口径把那三天文件里的 `# ` 一级标题节与一条无标题裸条目一并计入，新口径只数 `## `，故分别差 2 / 1 / 3，差异原因是「迁移后同日新增条目与裸条目未按新口径回填」；`2026-11-22` 由 6 改为 26、字节由 32,172 改为 159,369——旧值只覆盖当时已回填锚点行注释的 6 节，同日新增的 20 节未回填。下方节标题索引同步补齐 `2026-11-22` 缺失的 20 行；这 20 节在拆分时未补 `<!-- 原 compat-report.md 行 N-M -->` 注释，故其「原行」列记 `—`。

## 节标题索引

「锚点行」是拆分后当日文件中的行号，可直接拼成 `文件#L行号`。


### 2026-11-12 → [2026-11-12.md](2026-11-12.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 402 | 12 | （无标题条目） |
| 404 | 15 | M7(1)-(3) 阶段性闭环汇总（事实快照，14ccb9d/5949cc2 docs 基线 + b4fe095 B2 同步 + a482329/582b099 M7(3) issue/env/gem/IRB 边界证据同步，2026-11-12） |
| 476 | 74 | Subitem evidence: B1/B2 system gem discovery fix (2026-11-12, post-044aacb) |
| 485 | 84 | Post-37b4287 probe evidence (2026-11-12, 37b4287, docs-only sync) |
| 495 | 95 | Subitem evidence: differential harness CELERITE_BIN skip-rebuild (2026-11-12, post-bba7949) |
| 505 | 106 | Subitem evidence: post-6eee96a constraint regression rerun (2026-11-12) |
| 517 | 119 | Subitem evidence: post-37b4287 full 4.0.24 differential rerun (2026-11-12, HEAD=1882f53) |

### 2026-11-13 → [2026-11-13.md](2026-11-13.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 462 | 12 | Stage acceptance summary (docs aligned to HEAD=35fa404 evidence baseline + M7(4)/(6) audit/fix + config_spec docs-only + M7(1)/(2) regression evidence, 2026-11-13) |
| 527 | 27 | Subitem evidence: post-37b4287 full 2.7.2 differential rerun (2026-11-13, HEAD=517f69a) |
| 540 | 41 | Subitem evidence: M7(1)/(2) combo fixtures list-path-only-group + multi-platform-install-ruby (2026-11-13, HEAD=4c2404a) |
| 554 | 56 | Subitem evidence: M7(4) read-code audit + redirect typing fix (2026-11-13, HEAD=e77c6cb, shim local bin) |
| 579 | 82 | Subitem evidence: M7(4) silent-ignore disposition (2026-11-13, HEAD=3c3f52e, docs-only) |
| 605 | 109 | Subitem evidence: M7(6) plugin command/hook audit (2026-11-13, HEAD=94ec377, docs-only) |
| 615 | 120 | Subitem evidence: M7(6) plugin hook event-name alignment fix (2026-11-13, HEAD=a59d50f+worktree, shim local bin) |
| 628 | 134 | Subitem evidence: config_spec round-trip pre-existing failure (2026-11-13, HEAD=10e0a52, docs-only) |
| 639 | 146 | Subitem evidence: M7(4) WIP closure — timeout/ssl wiring, redirect error, proxy softening, fast-fail (HEAD=e6f0086 后，本子项) |
| 657 | 165 | Subitem evidence: M7(7) differential installed-tree symlink presence/type comparison + selftest (2026-11-13, updated) |

### 2026-11-14 → [2026-11-14.md](2026-11-14.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 674 | 12 | M7(9) Rails 可行性探测（2026-11-14，未验证/阻塞） |
| 695 | 34 | 2026-11-14 G：环境根因定位（exe 位置写/TLS 限制）+ ① 已修复落地 + ②③ 验收 |
| 740 | 80 | 2026-11-14 H1：rails 8.0.2 伪冲突修复（`!=` 多排除的 union 截断）——本轮实测 |
| 759 | 100 | 2026-11-14 #27：bridge autorequire 数组形态解析修复——本轮实测 |
| 769 | 111 | 2026-11-14 M7(7) acceptance：差分脚本健壮性——本轮实测（roadmap L160 四要求逐条映射） |
| 777 | 120 | 2026-11-14 #27 补充：修复后定向差分回归（双 profile，本轮实测） |
| 783 | 127 | 2026-11-14 K：平台变体选择修复（本地平台精确匹配 > ruby）——本轮实测 |
| 807 | 152 | 2026-11-14 K/K'/K''：平台变体 + checksum 归一化 + bundler 自列入修复——本轮实测 |
| 833 | 179 | 2026-11-14 rerun after K/K'/K'' fixes |
| 865 | 212 | 2026-11-14 N1：native-ext “缺 make”更正为 harness PATH 未配置 + PATH 归一化（本轮实测） |
| 898 | 246 | A 类双 profile（树外 exe） |
| 901 | 250 | 全量 4.0.24 |
| 903 | 253 | Rails e2e（环境阻塞，复现用） |

### 2026-11-15 → [2026-11-15.md](2026-11-15.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 908 | 12 | 2026-11-15 M7(4) 子项：`mirror.<url>.fallback_timeout` 真实生效——本轮实测 |
| 955 | 60 | 2026-11-15 M7(4) 第二子项：`ssl_client_cert` 的 mTLS 私钥接线（客户端证书真实生效）——本轮实测 |
| 1001 | 107 | 2026-11-15 M7(8) 产品差异①：path 源锁文件相对化 |
| 1055 | 162 | M7(8) 第二子项：锁文件 specs 为空时重解析（2026-11-15，HEAD=8de9eb4 + 本工作树） |
| 1073 | 181 | M7(8) 第三子项：冲突标记消息使用相对 lockfile 路径（2026-11-15） |
| 1092 | 201 | 2026-11-15 M7(8) 第四子项：锁定 spec 的依赖边缺失时 install 补齐（产品差异④） |
| 1122 | 232 | 2026-11-15 M7(4) 第三子项：HTTP(S) proxy 路由真实生效 |
| 1143 | 254 | 2026-11-15 M7(4) 第四子项：`path.system` 真实语义 |
| 1152 | 264 | 2026-11-15 M7(4) 收口审计 |
| 1177 | 290 | 2026-11-15 M7(8) 第五子项：两条产品差异的 differential 固化 |
| 1217 | 331 | 2026-11-15 M7(4) 证书校验失败：CertificateFailureError（对齐 bundler 4.0.24） |
| 1244 | 359 | 2026-11-15 clean：撤销 2.7.2 profile 特例 |
| 1269 | 385 | 2026-11-15 M7(8) 装具 git-init 暂存路径缺陷（已修） |
| 1295 | 412 | 2026-11-15 M7(8) spec 自包含化：lock platform 往返用例改用离线索引 |
| 1305 | 423 | 2026-11-15 M7(1) 约束矩阵审计：远程 compact index 负例 + 根级解释文案纠正 |
| 1373 | 492 | 2026-11-15 M7(5)：git tag / glob 的差分载体（诚实记录：本机环境阻塞） |
| 1418 | 538 | 2026-11-15 M7(5)/M7(8) 环境失败根因：Low 完整性级别导致 msys sh 无法建共享内存 |
| 1450 | 571 | 2026-11-15 M7(3)：`fund --group` 的组选择、缺 PATH 源报错与 funding 来源对齐 |
| 1510 | 632 | 2026-11-15 M7(6)：插件 hook 失败语义 |
| 1538 | 661 | 2026-11-15 M7(6)：插件命令注册 |
| 1569 | 693 | 2026-11-15 M7(6)：Gemfile 声明的插件预装 |
| 1612 | 737 | 2026-11-15 M7(5)：`--local` / `--prefer-local` |
| 1633 | 759 | 2026-11-15 M7(1)：平台变体正例 |
| 1680 | 807 | 2026-11-15 M7(1)：`check` 重解通知的「依赖已满足」取证 + `bundle-preset` 装具能力 |
| 1719 | 847 | 2026-11-15 M7(1)：`show` / `show --paths` 的列表形态对齐 |
| 1759 | 888 | 2026-11-15 M7(1)：frozen 模式下 ruby 解锁拒绝 |
| 1790 | 920 | 2026-11-15 M7(2)/L157：install 家族未知开关拒绝 |

### 2026-11-16 → [2026-11-16.md](2026-11-16.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 1869 | 12 | 2026-11-16 M7(8)/L161：`script/upstream-specs` 默认真实驱动 + 自动失败分桶 |
| 1888 | 32 | 2026-11-16 M7(4)：TLS 信任库默认 CA 与 CA 目录（`ssl_ca_cert`） |
| 1989 | 134 | 2026-11-16（M7(5)：锁文件写入保留既有 CRLF 行尾） |
| 2011 | 157 | 2026-11-16（M7(5)：锁文件写入失败的权限错误映射） |
| 2026 | 173 | 2026-11-16（M7(5)：`Dir.glob` 绝对模式与 `vendor/cache` 安装） |
| 2039 | 187 | 2026-11-16（M7(5)：扩展编译失败 → `InstallError` + 半装目录保留） |
| 2053 | 202 | 2026-11-16（M7(2)：`bundle list` 的 `--format`/互斥选项与普通环境分组发现） |
| 2065 | 215 | 2026-11-16（M7(5)：扩展编译失败后不留 bundle 缓存） |
| 2078 | 229 | 2026-11-16（M7(6)：`plugin install <gem> --source` 的插件树与无 Gemfile 行为） |
| 2116 | 268 | 2026-11-16（M7(5)：文件系统错误按参考映射，含 ENOSPC/EROFS/EPERM/ENOTSUP/EPROTO） |
| 2141 | 294 | 2026-11-16 续（全量差分复测 160/16/2 与两处修复） |
| 2171 | 325 | 2026-11-16（M7(2)：`bundle add` 的开关面、`bundle remove` 的消息与 remove/clean 分工） |
| 2211 | 366 | 2026-11-16（M7(2)：removed-flag 专属文案与 `Did you mean?` 建议） |
| 2263 | 419 | 2026-11-16（M7(2)：`show`/`info` 的组过滤语义与 `Bundler.load` 先决顺序） |
| 2302 | 459 | 2026-11-16（M7(3)：`bundle env` 的 Gem 目录行与 `bundle version` 的构建元数据） |
| 2351 | 509 | 2026-11-16（M7(2)/M7(3)：无 lockfile 的 `show`/`info` 发现与用户主目录语义） |
| 2394 | 553 | 2026-11-16（M7(1)：Ruby 运行时校验无条件化、RUBY VERSION 写运行版本、platform 的版本操作数） |
| 2427 | 587 | 2026-11-16（M7(1)：无 lockfile 的 `bundle check` 解析与写锁） |
| 2453 | 614 | 2026-11-16（M7(4)：`--verbose` 的 `Running ...` 回显） |
| 2467 | 629 | 2026-11-16（M7(2)/M7(3)：无 lockfile 的 `fund`/`clean`/`binstubs` 走 local-only 解析） |
| 2482 | 645 | 2026-11-16（M7(2)：`bundle config` 的 base 弃用接口、作用域校验与取值呈现） |
| 2497 | 661 | 2026-11-16（M7(2)：命令面的 unknown-switch 拒绝与只读命令的本地/远程解析分工） |
| 2528 | 693 | 2026-11-16（M7(3)：`bundle gem` 的 Thor 否定开关、removed `--rubocop` 与 git 门控） |
| 2574 | 740 | 2026-11-16（M7(2)：`bundle exec` 的自有开关与 bundler lib 解析） |
| 2614 | 781 | 2026-11-16（M7(2)：`bundle open` 的参数校验、编辑器顺序与 select_spec 选 gem） |
| 2648 | 816 | 2026-11-16（M7(4)：`install` 目标目录的 `Settings::Path` 语义与 `path`/`path.system` 冲突） |
| 2693 | 862 | 2026-11-16（M7(4)：部署模式 `vendor/bundle` 默认目标与 frozen CHECKSUMS 校验） |
| 2734 | 904 | 2026-11-16（M7(4)：无 `path` 配置时的安装目标与自定义 path 的物化边界） |
| 2767 | 938 | 2026-11-16（M7(4)：frozen 模式的 Gemfile 差异理由与加/删条目） |

### 2026-11-17 → [2026-11-17.md](2026-11-17.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 2803 | 12 | 2026-11-17（M7(4)：`validate_platforms!` 与冻结模式下的平台错误） |
| 2852 | 62 | 2026-11-17（M7(2)：`--gemfile` 的缺失校验与 `outdated --verbose` 的重复回显） |
| 2894 | 105 | 2026-11-17（M7(2)：`bundle lock` 的平台编辑、命名更新与开关面） |
| 2944 | 156 | 2026-11-17（M7(2)：`bundle cache` 的开关面、`--path` 的移除文案与 `--no-install`） |
| 2989 | 202 | 2026-11-17（M7(2)：`bundle outdated` 的命名 gem 校验顺序） |
| 3012 | 226 | 2026-11-17（M7(2)：`bundle update` 的更新范围、锁文件前置条件与 stayed-same 报告） |
| 3060 | 275 | 2026-11-17（M7(2)：Thor 解析期的参数校验：数值选项、位置参数与 `show --outdated`） |
| 3115 | 331 | 2026-11-17（M7(2)：`show --verbose` 的 outdated 检查与 Summary/Homepage/Status 块） |
| 3142 | 359 | 2026-11-17（M7(4)：frozen 模式的源变更理由与 `You have changed in the Gemfile:`） |
| 3196 | 414 | 2026-11-17（M7(2)：`bundle info` 的 `--verbose` 回显） |
| 3234 | 453 | 2026-11-17（M7(2)：`lock` 的无操作静默、`check --path` 的移除文案与 `show --paths` 的 bundler 行） |
| 3283 | 503 | 2026-11-17（M7(2)：`install --standalone` 的默认 path、组过滤与 CRLF） |
| 3341 | 562 | 2026-11-17（M7(5)：403 的两处抛出点与紧凑索引的 legacy 回退） |
| 3399 | 621 | 2026-11-17（M7(5)：gem 下载 403 的重试与失败文案） |
| 3453 | 676 | 2026-11-17（M7(2)/M7(4)：`--quiet` 的抑制面、`lock --print` 的解析行、`add` 的重复声明语义） |

### 2026-11-18 → [2026-11-18.md](2026-11-18.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 3557 | 12 | 2026-11-18（M7(3)/M7(2)：`help` / `--help` 渲染 vendored manpage） |
| 3609 | 65 | 2026-11-18（M7(2)/M7(3)：`cli_help` 与无参 `bundle` 的 default_command 语义） |
| 3661 | 118 | 2026-11-18（M7(2)/M7(3)：命令名解析 / `tree` / `[REMOVED]`） |

### 2026-11-19 → [2026-11-19.md](2026-11-19.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 3721 | 12 | 2026-11-19（M7(3)：`console` 的进程内引导与组 require 语义） |
| 3755 | 47 | 2026-11-19（M7(6) G1：插件 hook 事件写入索引） |
| 3789 | 82 | 2026-11-19（M7(6) task-7：hook 失败时序与差分断言通道） |
| 3822 | 116 | 2026-11-19（M7(6) task-9：`plugin uninstall` 之后的 hook 收口） |
| 3867 | 162 | 2026-11-19（M7(6) task-11：`after-install` 按安装 spec 逐个触发） |
| 3916 | 212 | 2026-11-19（M7(6) task-15：未定义 hook 事件时 `plugin install` 报错退出） |
| 3951 | 248 | 2026-11-19（M7(6) task-17：`plugin install` 失败消息的折行宽度与锚点订正） |
| 3990 | 288 | 2026-11-19（M7(6) task-19：非规范 `file://C:/…` file URL 归一化对齐） |
| 4041 | 340 | 2026-11-19（M7(6) task-19 验收补记：全量 `crystal spec` 的本机限制） |
| 4063 | 363 | 2026-11-19（M7(6) task-20：`plugin uninstall` 选项/空参语义与注册表清理对齐） |
| 4100 | 401 | 2026-11-19（M7(3) task-21：安装期 `required_ruby_version` / `required_rubygems_version` 复核对齐） |
| 4148 | 450 | 2026-11-19（M7(2) task-22：`check`/`list`/`show` 以 installed specification 判定已安装） |
| 4185 | 488 | 2026-11-19（M7 L161 task-23：upstream-specs 装具缺失 gem 文件诊断） |
| 4223 | 527 | 2026-11-19（M7(6) task-24：typed source 独存时 install 失败面对齐） |
| 4259 | 564 | 2026-11-19（M7(8) task-25：空 CHECKSUMS 触发重解析与 sha256 回填） |
| 4290 | 596 | 2026-11-19（M7(8) task-26：`lock --add-checksums` 计算路径与 frozen 空 CHECKSUMS 拒绝） |
| 4325 | 632 | 2026-11-19（M7(3) task-27：`bundle gem` 选项面与 `--help` 对齐） |
| 4349 | 657 | 2026-11-19（M7(6) task-28：自定义 source 的 S1——求值、specs 与 `PLUGIN SOURCE` 锁段） |
| 4371 | 680 | 2026-11-19（M7(6) task-29：自定义 source 的 S2——锁定 `PLUGIN SOURCE` 复用与缺插件语义） |
| 4420 | 730 | 2026-11-19（L163 收口：README、兼容矩阵与 roadmap 同步） |
| 4457 | 768 | 2026-11-19（M7(6) task-31：typed plugin source 安装成功路径） |
| 4501 | 813 | 2026-11-19（M7 L161 task-32：上游 lockfile 基线二次重采集与 product 候选定性） |
| 4533 | 846 | 2026-11-19（M7(6) task-33：非 frozen 自动补本地平台） |
| 4572 | 886 | 2026-11-19（M7(6) task-34：Git source 变化必须重解析） |
| 4613 | 928 | 2026-11-19（M7(8) task-35：`bundle check` 成功落盘与失败三元组） |
| 4650 | 966 | 2026-11-19（M7(8) task-36：path 源默认 glob 与失败归属） |
| 4683 | 1000 | 2026-11-19（M7(8) task-37：`list`/`show`/`info` 在已装 spec、目录缺失时的语义） |
| 4715 | 1033 | 2026-11-19（M7(3) task-38：锁内 ruby/rubygems 约束的解析证据） |
| 4747 | 1066 | 2026-11-19（M7(6) task-40：合成规模离线证据链） |
| 4784 | 1104 | 2026-11-19（L163 task-39：文档漂移清理） |
| 4802 | 1123 | 2026-11-19（M7(3) task-41：default gem 参与解析、`info` 回退与未知 gem 文案） |
| 4837 | 1159 | 2026-11-19（M7(8) task-42：`install`/`update` 收尾的 funding 汇总） |

### 2026-11-20 → [2026-11-20.md](2026-11-20.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 4875 | 12 | 2026-11-20（M7(8) task-44a：`check` 改写的非 gem 段保真与空 GEM remote） |
| 4925 | 63 | 2026-11-20（M7(8) task-44b：PATH 源身份与可见 spec 集判据） |
| 4977 | 116 | 2026-11-20（M7(6) task-45：before-install-all / after-install-all 插件钩子） |
| 5022 | 162 | 2026-11-20（M7(8) task-46：PATH 源按名匹配与 PLUGIN 源归属） |
| 5075 | 216 | 2026-11-20（M7(6) task-47：第三方插件 gem 的端到端 source） |
| 5128 | 270 | 2026-11-20（M7(2) task-48：`exec` 的 RUBYOPT 注入与显式 Gemfile 缺失语义） |
| 5158 | 301 | 2026-11-20（M7(3) task-49：`issue` 无锁报告的失败面与 doctor 共用路径） |
| 5196 | 340 | 2026-11-20（M7(3) task-50：`info`/`show` 读取真实 gemspec 元数据） |
| 5235 | 380 | 2026-11-20（M7(8) task-51：`bundle cache` 根目录与 `BUNDLE_APP_CONFIG`） |
| 5252 | 398 | 2026-11-20（M7(3) task-52：安装后自动清理） |
| 5262 | 409 | 2026-11-20（M7(3) task-53：`bundle doctor` 子命令面与 Windows dylib 警告） |
| 5299 | 447 | 2026-11-20（M7(3) task-54：`doctor ssl` 与 `diagnose --ssl`） |
| 5323 | 472 | 2026-11-20（M7(2) task-55：`bundle add` 的 glob/version/path 选项面） |
| 5355 | 505 | 2026-11-20（M7(2) task-56：plugin new / licenses 顺序 / config 本地路径 / 死代码） |
| 5373 | 524 | 2026-11-20（M7(3) task-57：`bundle update --bundler` 的目标解析与 `BUNDLED WITH`） |
| 5391 | 543 | 2026-11-20（M7(2) task-58：`bundle lock` 的 `--normalize-platforms` 与 `--lockfile`） |
| 5409 | 562 | 2026-11-20（M7(2) task-59：`bundle add` 位置参数解析与 `install --target-rbconfig`） |
| 5428 | 582 | 2026-11-20（M7(2) task-60：`update --redownload` 的 `Fetching` 行） |
| 5440 | 595 | 2026-11-20（M7(2) task-62：四个「已声明未取 oracle」的组合收口） |
| 5459 | 615 | 2026-11-20（M7(2) task-63：`bundle binstubs` 渲染 Bundler 模板） |
| 5479 | 636 | 2026-11-20（M7(3) task-64 项 1：`BUNDLE_FROZEN`/`BUNDLE_DEPLOYMENT` 无锁时的 install 文案） |
| 5498 | 656 | 2026-11-20（M7(3) task-64 项 2：`lock --add-platform` 保留原生 spec 行与 CHECKSUMS） |
| 5518 | 677 | 2026-11-20（M7(2) task-65：内建 gem 判据改为「来源」而非「同名同版本」） |
| 5547 | 707 | 2026-11-20（M7(2) task-65：无锁时 frozen/deployment 的 `update --all`） |
| 5563 | 724 | 2026-11-20（M7(2) task-66：上游 lockfile 套件第三次重采集与候选去向） |

### 2026-11-21 → [2026-11-21.md](2026-11-21.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 5593 | 12 | 2026-11-21（M7 task-67：`check` 遇 Gemfile 新增未锁定依赖时的重解析） |
| 5622 | 42 | 2026-11-21（M7 task-68：`remove` 族的四条失败面） |
| 5654 | 75 | 2026-11-21（M7 task-69A：`outdated --parseable` 的 `, requested` 段） |
| 5672 | 94 | 2026-11-21（M7 task-69B：`install --local` 的 source 描述与缓存后缀） |
| 5693 | 116 | 2026-11-21（M7 task-70：`pristine` 缺缓存、`info`/`show`/`list` 的多余位置参数） |
| 5734 | 158 | 2026-11-21（M7 task-71：`info`/`show` 的 `select_spec`——默认 gem 回退与正则多选菜单） |
| 5769 | 194 | 2026-11-21（M7(6) task-73：`plugin install --path` 冲突回滚与源目录删除） |
| 5815 | 241 | 2026-11-21（M7(6) task-74A：`bundle clean` 的 system gems 护栏） |
| 5837 | 264 | 2026-11-21（M7(2) task-74B：`config` 数组值的 `Symbol#inspect` 渲染） |
| 5855 | 283 | 2026-11-21（M7 task-75：install/clean/exec/outdated 的结构化 Ruby 校验） |
| 5881 | 310 | 2026-11-21（M7 task-76：`BUNDLE_FORCE_RUBY_PLATFORM`） |
| 5904 | 334 | 2026-11-21（M7 task-77：`bundle cache` 的 `BUNDLE_CACHE_PATH`） |
| 5932 | 363 | 2026-11-21（M7 task-78：`BUNDLE_VERBOSE` 与 verbose 调试行） |
| 5960 | 392 | 2026-11-21（M7 task-79：verbose 的「重解析原因行」） |
| 5985 | 418 | 2026-11-21（M7 task-80：`bundle add` 的 requirement 渲染与 option 冲突） |
| 6007 | 441 | 2026-11-21（M7 task-81：`add` 失败后的 Gemfile 回滚、多余的重解析行、一条过期 spec） |
| 6036 | 471 | 2026-11-21（M7 task-82：`add --github` 的源选择，以及一条「故意不对齐」） |
| 6057 | 493 | 2026-11-21（M7 task-83：`install --local` 只限制来源，不跳过安装） |
| 6089 | 526 | 2026-11-21（M7 task-84：`cache_all` 下的工程外 `path` 源复制） |
| 6127 | 565 | 2026-11-21（M7 task-85：`~/.gemrc` 的 `:http_proxy`） |
| 6171 | 610 | 2026-11-21（M7 task-86：上游 lockfile 套件第三次复采） |
| 6213 | 653 | 2026-11-21（M7 task-87：install/update/add 刷新 `vendor/cache`） |
| 6249 | 690 | 2026-11-21（M7 task-88：首次 install 复制工程外 path 源、`BUNDLE_PATH` 绝对路径原样渲染） |
| 6279 | 721 | 2026-11-21（M7 task-89：`install --standalone` 对非 GEM 源与 `require_paths` 的渲染） |
| 6309 | 752 | 2026-11-21（M7 task-90：`update --group <无成员组>` 不再多余重解析） |
| 6349 | 793 | 2026-11-21 分桶规则修正（task-91，离线重算未重跑） |
| 6432 | 877 | 2026-11-21（M7 task-92：锁文件依赖表失配的 frozen 语义与 file:// remote 归一） |
| 6453 | 899 | 2026-11-21（M7 task-93：`show` 的列举排序与 `show bundler` 形态） |
| 6474 | 921 | 2026-11-21（M7 task-94：非 frozen 的锁依赖表失配自动修复） |
| 6504 | 952 | 2026-11-21（M7 task-95：`install` 按 `without` 过滤安装集合） |
| 6538 | 987 | 2026-11-21（M7 task-96：`doctor` 的 settings 互斥通知行 + `options_to_lock` 锁段夹具） |
| 6576 | 1026 | 2026-11-21（M7 task-97：`BUNDLE_ONLY` 与 `update` 的排除组提示） |
| 6609 | 1060 | 2026-11-21（M7 task-98：`doctor` 的 setting 校验余下两条规则） |
| 6642 | 1094 | 2026-11-21（M7 task-99：首次 install 的 path 源缓存与 `Bundled gems are installed into` 的分隔符与空值形态） |
| 6672 | 1125 | 2026-11-21（M7 task-100：`licenses` 从运行期 spec 读取，而非缓存包） |
| 6706 | 1160 | 2026-11-21（M7 task-101：`install --local` 不得取索引、不得自愈） |
| 6803 | 1258 | 2026-11-21（M7 task-102：`check` 自愈 `PATH` 段缺失/漂移的 spec） |
| 6856 | 1312 | 2026-11-21（M7 task-103：`cache --all-platforms` 的 path 源回归网） |
| 6916 | 1373 | 2026-11-21（M7 task-104：`cache` 重跑面的输出） |
| 6953 | 1411 | 2026-11-21（M7 task-105：bundle 目录骨架与进程锁清理） |
| 6983 | 1442 | 2026-11-21（M7 task-106：`install --local` 不做 self-install） |
| 7015 | 1475 | 2026-11-21（M7 task-107：`install --local` 的 `Resolving dependencies...` 复核） |
| 7043 | 1504 | 2026-11-21（M7 task-107：`install --local` 只在真正解析时打 `Resolving dependencies...`） |
| 7093 | 1534 | 2026-11-21（M7(2) task-112：`bundle binstubs` 支持 PATH/GIT 源） |

### 2026-11-22 → [2026-11-22.md](2026-11-22.md)

| 原行 | 锚点行 | 标题 |
| ---: | ---: | --- |
| 7072 | 12 | 2026-11-22（M7(2) task-108：`lock --update` 的版本提升级别与级别互斥） |
| 7170 | 34 | 2026-11-22（M7 task-113：`install --prefer-local` 只把本 bundle 已装的 gem 当候选） |
| 7225 | 90 | 2026-11-22（M7 task-114：第四次上游 lockfile 套件复采） |
| 7287 | 153 | 2026-11-22（M7 task-115：锁依赖边自愈保持锁定版本） |
| 7334 | 201 | 2026-11-22（M7 task-116：CHECKSUMS 缺行时补回 `Resolving dependencies...`） |
| 7374 | 242 | 2026-11-22（M7 task-117：锁定 spec 行缺失但依赖边仍在时重解析并升级） |
| — | 280 | 2026-11-22：上游 lockfile 套件第五次复采（task-118） |
| — | 324 | 2026-11-22：M7 task-119 frozen 模式锁定行合法性判定三处对齐 |
| — | 365 | 2026-11-22：M7 task-120 `--local` 下 Gemfile 新增未本地依赖被静默丢弃并写坏锁 |
| — | 405 | 2026-11-22：install --local 未命中时的文案分档（task-121） |
| — | 446 | 2026-11-22：locked-deps spec 夹具缺索引导致的两例假失败（task-122） |
| — | 491 | 2026-11-22：`lock`/`update` 的版本提升级别与 `BUNDLE_PREFER_PATCH`（task-126） |
| — | 589 | 2026-11-22：`bundle list` / `bundle pristine` 无 `Gemfile.lock` 时的解析分歧（task-125） |
| — | 732 | 2026-11-22：verbose 回显 spec 与六参签名不符导致全套件编译失败（task-127） |
| — | 780 | 2026-11-22：空 Gemfile 缺少 `The Gemfile specifies no dependencies` 提示（task-123） |
| — | 851 | 2026-11-22：重复 `gem` 声明警告按求值次数重放（task-124） |
| — | 945 | 2026-11-22：CLI 每次调用重置 verbose/retry 状态（task-128） |
| — | 1006 | 2026-11-22：spec 间环境泄漏清单与 BUNDLE_GEMFILE 缺失路径的双方行为（task-130） |
| — | 1094 | 2026-11-22：全套件 `crystal spec` 现可跑到 `Finished` 的现状同步（task-131） |
| — | 1152 | 2026-11-22：`bundle clean` 无 path 配置时的守卫语义（task-132） |
| — | 1199 | 2026-11-22：`m7_show_order_spec` 的参考 lib 环境前提（task-133） |
| — | 1233 | 2026-11-22：有锁文件时 `lock` 的 source index 抓取行（task-134） |
| — | 1273 | 2026-11-22：`show bundler` 在无差分装具时的 gem 根路径（task-135） |
| — | 1396 | 2026-11-22：`info bundler --path` 的回落分支与 `show bundler` 对齐（task-136） |
| — | 1434 | 2026-11-22：GEM 源索引抓取失败时的退出码与报错形态（task-137） |
| — | 1502 | 2026-11-22：gem 名 "Did you mean" 建议的覆盖补强（task-141） |
