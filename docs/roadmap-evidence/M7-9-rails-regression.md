# M7(9) Rails 规模真实项目回归

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 162 -->

**2026-11-14 探测（HEAD=4aaed16 链，F 子项）：Rails 8.0.2/railties 与 Bundler 4.0.24 本机齐备；`celerite install` 于 rails 规模 Gemfile 在网络活动前 `celerite internal error: Nil assertion failed`（EXIT 1，无 lockfile）；`celerite lock` 元数据抓取确定性 `SSL_connect: error:0A000086:SSL routines::certificate verify failed`（EXIT 1，同夹具 install 早些时候成功 ⇒ 命令路径差异）；M7(9) 未验证/阻塞，复现与归因见 `docs/compat-evidence/2026-11-14.md` M7(9) 节。** **G 轮补充

（2026-11-14）：① 修复后 rails-min install 不再 Nil 崩溃，进网络至 `Fetching gem metadata... Resolving dependencies... (derived conflict)` EXIT 6（真实 gemfile 级解析错误浮出）；TLS/EACCES 均归环境（exe 位置策略），复现与归因详见 `docs/compat-evidence/2026-11-14.md` G 节。** **H1 轮补充

（2026-11-14，HEAD=70ac5df 链）：rails 8.0.2 伪冲突根因定位为 `VersionUnion#intersects?/#intersect` 区间扫描在无上界侧提前耗尽（`!=` 多排除 union 被截断出虚假上界 `nokogiri < 1.19.5`），修复后树外二进制 `celerite lock` EXIT 0 出 lockfile，与参照 `bundle _4.0.24_ lock` 的 GEM/DEPENDENCIES/PLATFORMS/BUNDLED WITH 结构化比对差异逐项登记（nokogiri/prism 平台变体选择 + bundler 自列项，详见 `docs/compat-evidence/2026-11-14.md` H1 节）；M7(9) 仍未验证（真实安装受平台变体选择 gap + 本机缺 make 阻塞）。** **M7(9) 进展注记

（2026-11-14，H1 轮 HEAD=44bee37）：Rails lock 已可解——树外二进制 `celerite lock` 于 rails-min（Gemfile `source "https://rubygems.org"` + `gem "rails", "8.0.2"`）EXIT 0 出 lockfile，与参照 `bundle _4.0.24_ lock` 结构化比对 DEPENDENCIES/PLATFORMS/BUNDLED WITH 逐字一致、GEM specs name+version 61/64 一致（差异仅 nokogiri/prism 平台变体 + bundler 自列项，逐项登记于 `docs/compat-evidence/2026-11-14.md` H1 节）；install 受本机缺 make（bigdecimal 原生构建）阻塞，未验证端到端。** **N1 更正

（2026-11-14）**：非缺 make——`make.exe`（GNU Make 4.4.1）本已存在于 `C:\Ruby40-x64\msys64\usr\bin`，失败源于 harness PATH 未含该目录，且独立 msys64 gcc Rev6 16.2.0 与 Ruby 自带 Rev5 16.1.0 不一致致两侧 cparse.so 字节不同（环境，非产品）；`script/differential` PATH 归一化后 native-ext 双 profile PASS、全量 4.0.24 `135 passed, 0 failed, 1 skipped` EXIT 0；install e2e 仍受 bigdecimal EEXIST + TLS 抖动阻塞，未验证端到端（详见 `docs/compat-evidence/2026-11-14.md` N1 节）。。2026-11-16：产品侧阻塞已清除——设 `SSL_CERT_FILE` 后 `celerite lock` 对 `https://rubygems.org` exit 0；rails 8.0.2 的 `celerite install` 能完成解析/下载/安装全部依赖，仅原生扩展构建被 msys 在 Low IL 下的 `0xC0000022` 阻塞（148.6s 复用缓存 / 1112.4s 冷启动，见 ``docs/compat-evidence/2026-11-16.md``「2026-11-16 续」），故该 profile 仍记「环境阻塞、未验证」，不恢复兼容声明。 

**2026-11-19（L163 收口）：复跑条件＝非 Low-IL 宿主（msys `0xC0000022` 与原生扩展构建限制消失），且需重新采集 `rspec-output.json`；本轮未复跑。复选框保持 `[ ]`。** 

**2026-11-19（task-40 补记）：合成规模 N=20/100/300 的离线索引（三件套）上，4.0.24 参考与 celerite 的锁逐字一致；k=5 中位锁耗时比 100/300=1.22/1.33（≤1.35），20=1.39 为启动开销自检点；install 我方随 N 变慢，基线存 docs/benchmarks/results-20261119.md。真 Rails 仍不可验证：需网络取图、缺 make、msys Low-IL 阻塞原生扩展（`docs/compat-evidence/2026-11-16.md` 的「2026-11-16 续（M7(4) 收尾 / M7(9) 解锁）」节，对应治理前的 compat-report.md 第 1925-1933 行）。复选框保持 [ ]。**
