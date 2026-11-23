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
## 2026-11-23：Rails 规模回归的本机可行性判定（task-160）

### 任务陈述（逐字引用 `docs/roadmap.md`）

> - [ ] 建立 Rails 规模真实项目回归，记录所有有意兼容差异及理由；未解释差异为零后才恢复"该 profile 兼容"的声明。（实证流水逐字迁出至 `docs/roadmap-evidence/M7-9-rails-regression.md`）

### 本轮实测（工作树 detached HEAD = `c1d4125`；探针目录 `.tmp-scratch/m79`）

环境更正两条（推翻本仓库既有记录）：

- **网络可用**：Ruby `Net::HTTP` HEAD 探针 `https://rubygems.org/versions` → `NET_OK HTTP=200`；`https://index.rubygems.org/versions` → `IDX_OK HTTP=200`（open/read 超时各 6s）。
- **`make` 可用**：`C:\Ruby40-x64\msys64\usr\bin\make.exe` 存在，`make --version` → `GNU Make 4.4.1`。`C:/msys64/ucrt64/bin/make.exe` 与 `C:/msys64/usr/bin/make.exe` 确实不存在。故「make 不可用」的准确表述是**默认 PATH 未含 Ruby 自带 msys64 的 `usr/bin`**，而非缺 make。
- 本 shell 完整性级别实测 `Mandatory Label\Medium Mandatory Level S-1-16-8192`（Medium IL）；Low-IL 只出现在 Crystal 产物子进程树中。

探针 1 —— `lock`，真实网络，Gemfile 为 `source "https://rubygems.org"` + `gem "rails", "8.0.2"`：

```
$ bin/celerite.exe lock
Writing lockfile to .../.tmp-scratch/m79/cel/Gemfile.lock
Fetching gem metadata from https://rubygems.org/.
Resolving dependencies...
CEL_EXIT=0 ELAPSED_MS=157912

$ ruby .../bundler-4.0.24/exe/bundle lock
REF_EXIT=0 ELAPSED_MS=14906
```

逐字节比对（`File.binread`）：

```
IDENTICAL=true bytes=10663/10663
ref_specs=64 cel_specs=64 common=64
only_ref=[]  only_cel=[]
PLATFORMS: same=true   DEPENDENCIES: same=true
BUNDLED WITH: same=true   RUBY VERSION: same=true
```

即：**Rails 规模（64 条 spec）的锁解析在真实网络上与 4.0.24 参考逐字节一致**。这是本仓库首次取得的 rails 规模锁级 oracle。

探针 2 —— `install`，同一 Gemfile、同一锁：

```
$ bin/celerite.exe install
Resolving dependencies...
Bundle complete! 1 Gemfile dependency, 1 gem now installed.
```

- 安装后锁由 `10663 B / 64 条 spec` **收缩为 `698 B / 1 条 spec`**（仅剩 `rails (8.0.2)`）。
- `$BUNDLE_PATH/ruby/4.0.0/gems` 下只有 `rails-8.0.2` 一个目录；随后 `celerite check` 报 `The Gemfile's dependencies are satisfied`、`celerite list` 仅列 `* rails (8.0.2)`，**退出码 0 且无任何警告**。
- 三态复现一致：先 `lock` 再 `install` → 698 B / 1 spec；把参考产出的 64 条锁拷入再 `install` → 698 B / 1 spec；指定 `BUNDLE_PATH` 与不指定结果相同。
- 参考侧对照：隔离 `GEM_HOME`/`GEM_PATH`（指向探针目录）后，参考侧 `RAILS_CEL_ISO_REF_EXIT=0 MS=149323`，输出 `Bundle complete! 1 Gemfile dependency, 64 gems now installed.`，实测 `iso_ref gems=64 lock_specs=64 so=22`（22 个 `.so`，即含原生扩展与平台变体）；**参考侧锁始终为 64 条，未出现收缩**。另一轮未隔离 `GEM_HOME` 时参考侧 `RAILS_REF_INSTALL_EXIT=5 MS=24927`，报 `An error occurred while installing date (3.6.0)`（`net-imap 0.6.8 → date` 链），只装 62 gems —— 属**环境隔离不足**所致，非 Bundler 行为差异。

对照探针 —— 原生扩展单点（`gem "nio4r", "2.7.5"` + 显式 `BUNDLE_PATH`）：

```
# make 不在 PATH：
Installing nio4r 2.7.5 with native extensions
make failedNo such file or directory - make
Gem::Ext::BuildError: ERROR: Failed to build gem native extension.   NIO_CEL_EXIT=5
# gem_make.out: make failedNo such file or directory - make

# 把 C:\Ruby40-x64\msys64\usr\bin 前置到 PATH 后：
Bundle complete! 1 Gemfile dependency, 1 gem now installed.          NIO3_EXIT=0
.../gems/nio4r-2.7.5/ext/nio4r/nio4r_ext.so
```

即原生扩展构建链在本机**可跑通**；本轮实测到的失败根因是 PATH 缺 `make`，**不是** `0xC0000022` 权限阻断。

### 结论：**本机部分可做**

- **可做**：rails 规模 Gemfile 的**真实网络 `lock` 回归**。判据 = 与 `bundler 4.0.24` 产出的锁逐字节相同（本轮 64/64 spec、10663 B 相同，四个节段 same=true）。另可做原生扩展**单点**构建回归（补 PATH 后 `nio4r_ext.so` 生成成功）。
- **不可做**：rails 规模 Gemfile 的**`install` 回归**。`celerite install` 在 64 条 spec 的锁上把锁收缩为 1 条、只装 1 个 gem，退出码仍 0 —— 属**静默降级的兼容差异**（根因未定位）。在它修好之前，M7-9 的「未解释差异为零」无法达成，复选框必须保持 `[ ]`。
- 既有归因需更正：「原生扩展被 msys Low-IL `0xC0000022` 阻塞」这一条在本轮**未被复现**；本轮原生扩展失败原因是 PATH 缺 `make`。`0xC0000022` 仍在本仓库既有的 git 源夹具记录中出现，本任务未复测。

### 替代方案：离线索引规模回归（做法与判据已存在且已跑通，无需新写代码）

1. `ruby script/synthetic-index.rb --count N --out DIR` 生成 `file://` 离线索引（每个 gem 含 `gems/<full>.gem`、`quick/Marshal.4.8/<full>.gemspec.rz`、compact `info/<name>` + `versions`）。
2. `script/synthetic-scale --count 20 --count 100 --count 300 --runs 5`，A/B 交替序跑 `lock` 与 `install`。
3. 判据：**锁逐字节相同**（硬判据）；**锁耗时比 ≤ 1.35**（对 N=100/300）；安装计数须 `ref_gems == ref_specs == cel_gems == cel_specs == N`。

已有结果 `docs/benchmarks/results-20261119.md`：N=20/100/300 锁全部 `identical`（1621/6982/20382 B），锁耗时比 1.39/1.22/1.33，安装计数两侧均等于 N。

**该替代的边界（不得当作 rails 规模等价物）**：合成索引只覆盖**纯 Ruby** gem 的依赖图与安装，不含 `extensions`/原生扩展声明，也不含 `nokogiri`/`prism` 的平台变体行；它只能替代「依赖图规模 + 锁等价性」这一维，不能替代真实平台变体回归。若要补平台变体，需给 `script/synthetic-index.rb` 增加带 `platform`/`extensions` 的 gem 元数据（本轮未做，未验证）。

### 未验证 / 未做到

- 未定位 `celerite install` 收缩锁的实现位置（本任务为只读审计，未读 install 侧写锁代码路径）；也未判定它是「设计如此」还是缺陷。
- 未跑 rails 规模 `install` 的双侧性能比较（我方 153524 ms 含网络下载，参考 149323 ms 为复用本机缓存，两者不可直接比）。
- 未重跑全量 `crystal spec` 与全量差分（越出本任务范围）。
