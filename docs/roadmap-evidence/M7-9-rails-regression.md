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

## 2026-11-23：task-166 修复后在 rails 8.0.2 规模上复跑 install（task-174）

### oracle

- Gemfile（2 行，53 B）：`source "https://rubygems.org"` + `gem "rails", "8.0.2"`。
- 起始锁 = 本文件「2026-11-23：Rails 规模回归的本机可行性判定（task-160）」探针 1 取得的 rails 规模 oracle 的**逐字节副本**：`10663 B / 64 条 spec`（`^    [a-z]` 计数），SHA256 `C76C7DF696DA12C829933AA0A22904AA2742BC73F7F19A971FB3E92D86A199B1`（拷贝前后同哈希、同字节数、同 spec 行数）。
- 修复基线：worktree `C:\temp\celerite-t174`，detached HEAD = `6d1506d`（已含 `fa3eca2`）。

### 参考锚点

- 参考实现 = `bundler 4.0.24`（oracle 锁内 `BUNDLED WITH 4.0.24`，平台 `x64-mingw-ucrt`）。
- 判据一（决定性，针对 task-166 的缺陷）：`install` 后锁是否仍为 `10663 B / 64 条 spec`；缺陷形态是收缩为 `698 B / 1 条 spec`。
- 判据二：安装集合是否来自 64 条锁（缺陷形态是只装 `rails` 本体一个 gem）。
- 判据三（强）：`install` 写出的锁与 oracle 是否逐字节相同。
- 本轮未联网重跑参考侧 `install`（参考侧锚点沿用 task-160 记录：`RAILS_CEL_ISO_REF_EXIT=0 MS=149323`、`Bundle complete! 1 Gemfile dependency, 64 gems now installed.`），故判据三只比「我方 install 产物 vs 既有 oracle」。

### 实现位置

- `src/celerite/resolution.cr:1477` `lockfile_covers_dependencies?`；`bundler` 边跳过两处：`:1487`（顶层 dep 循环）与 `:1503`（锁内 spec 的依赖边循环，task-166 的修复点）。
- 复用决策入口 `src/celerite/resolution.cr:1383` `reuse_locked_resolution?`，其中 `:1410` 调用 `lockfile_covers_dependencies?`，`:1425` 调用 `covers_local_platform?`（本锁 `PLATFORMS` 为 `x64-mingw-ucrt`，与宿主机一致）。
- 该 rails 锁共 122 条依赖边；用 Ruby `Gem::Requirement` 逐边核验结果：`edges_without_spec_row=[["bundler", ">= 1.15.0"]]`、`requirement_failures=[]`（64 条 spec 全部满足各自约束）。即**唯一**能触发「锁不完整」判定的边就是 `bundler (>= 1.15.0)`，与 `:1503` 的跳过点一一对应；其余边（含 `date`、`nio4r (~> 2.0)`、`nokogiri (>= 1.8.5)`、`prism` 平台变体行）均有 spec 行且满足约束。

### 证据

构建（环境：`C:\msys64\{usr,ucrt64}\bin` + `C:\Ruby40-x64\bin` 前置，`TMPDIR/TMP/TEMP/HOME/USERPROFILE/CRYSTAL_CACHE_DIR` 指向 worktree 内目录，`SSL_CERT_FILE=C:/msys64/usr/ssl/cert.pem`）：

```
$ crystal build src/cli.cr -o bin/celerite.exe
exit=0  elapsed=34.1s  bin/celerite.exe = 12758720 B
（stderr 仅 2 条 File.executable? deprecation warning：commands_install.cr:1752、commands_install.cr:1815）
```

跑 1（首辅指定 PATH，未设 `BUNDLE_PATH`）：

```
exit=5  elapsedSec=271
stdout（全文 13 行，逐字）:
Fetching gem metadata from https://rubygems.org/.
Fetching connection_pool 3.0.3
Fetching net-smtp 0.5.2
Fetching prism 2.1.0 (x64-mingw-ucrt)
Fetching rack 3.2.9
Fetching websocket-driver 0.9.0
Fetching websocket-extensions 0.2.0
Installing connection_pool 3.0.3
Installing net-smtp 0.5.2
Installing prism 2.1.0 (x64-mingw-ucrt)
Installing rack 3.2.9
Installing websocket-extensions 0.2.0
Installing websocket-driver 0.9.0 with native extensions
stderr（首行与末三行，逐字）:
Gem::Ext::BuildError: ERROR: Failed to build gem native extension.
make failedNo such file or directory - make
Gem files will remain installed in
C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/websocket-driver-0.9.0 for inspection.
An error occurred while installing websocket-driver (0.9.0), and Bundler cannot
continue.
```

- 跑 1 后锁：`bytes=10663 specs=64 sha256=C76C7DF6…A199B1`（与 oracle **同哈希**）⇒ 未收缩。
- 跑 1 失败属**环境**：`C:\msys64\usr\bin\make.exe`、`C:\msys64\ucrt64\bin\make.exe`、`C:\msys64\mingw64\bin\make.exe` 实测均 `exists=False`；`C:\Ruby40-x64\msys64\usr\bin\make.exe` 存在。与本文件 task-160 节「make 可用的准确表述是默认 PATH 未含 Ruby 自带 msys64 的 `usr/bin`」一致。
- 跑 1 已装 6 个 gem（系统 gem 目录 `C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems`，mtime 2026-11-23 15:43）：`connection_pool-3.0.3`、`net-smtp-0.5.2`、`prism-2.1.0-x64-mingw-ucrt`、`rack-3.2.9`、`websocket-driver-0.9.0`、`websocket-extensions-0.2.0` —— 即按 64 条锁的依赖闭包字母序推进，而非缺陷形态的「只装 rails」。

跑 2（PATH 前置 `C:\Ruby40-x64\msys64\usr\bin`，`BUNDLE_PATH=<probe>\bundle`；较跑 1 唯一的差异是 make 可见与安装落点）：

```
exit=0  elapsedSec=553.2  stderr 空（0 B）
stdout 全文 133 行，末 15 行逐字:
Installing tzinfo 2.0.6
Installing uri 1.1.2
Installing useragent 0.16.11
Installing websocket-extensions 0.2.0
Installing zeitwerk 2.8.3
Installing bigdecimal 4.1.3 with native extensions
Installing date 3.6.0 with native extensions
Installing erb 6.0.7 with native extensions
Installing io-console 0.9.5 with native extensions
Installing nio4r 2.7.5 with native extensions
Installing racc 1.8.1 with native extensions
Installing rbs 4.2.0 with native extensions
Installing websocket-driver 0.9.0 with native extensions
Bundle complete! 1 Gemfile dependency, 64 gems now installed.
Bundled gems are installed into `./bundle`
```

跑 2 后计数与锁：

```
bundle/ruby/4.0.0/gems 目录数 = 64
bundle/ruby/4.0.0/specifications 下 *.gemspec 数 = 64
（随附 .so 文件数 = 15）
Gemfile.lock bytes=10663  specs=64
Gemfile.lock sha256=7C21E7936DA22F1E0A959B69AF562D3357922F164BE977175CDB01DE67DC13A2
oracle       sha256=C76C7DF696DA12C829933AA0A22904AA2742BC73F7F19A971FB3E92D86A199B1
逐字节相同 = false；spec 集合与版本 = 64/64 相同；依赖边内容逐条相同，差异为顺序
specs_with_different_dep_lines=16  order_only=16  content_different=0
例（A=install 产物，B=oracle）:
-- actioncable
   A: ["activesupport (= 8.0.2)", "actionpack (= 8.0.2)", "nio4r (~> 2.0)", "websocket-driver (>= 0.6.1)", "zeitwerk (~> 2.6)"]
   B: ["actionpack (= 8.0.2)", "activesupport (= 8.0.2)", "nio4r (~> 2.0)", "websocket-driver (>= 0.6.1)", "zeitwerk (~> 2.6)"]
-- actionpack
   A: ["activesupport (= 8.0.2)", "nokogiri (>= 1.8.5)", "rack (>= 2.2.4)", "rack-session (>= 1.0.1)", "rack-test (>= 0.6.3)", "rails-html-sanitizer (~> 1.6)", "rails-dom-testing (~> 2.2)", "useragent (~> 0.16)", "actionview (= 8.0.2)"]
   B: ["actionview (= 8.0.2)", "activesupport (= 8.0.2)", "nokogiri (>= 1.8.5)", "rack (>= 2.2.4)", "rack-session (>= 1.0.1)", "rack-test (>= 0.6.3)", "rails-dom-testing (~> 2.2)", "rails-html-sanitizer (~> 1.6)", "useragent (~> 0.16)"]
```

### 结论

- **task-166 的修复在 rails 规模成立**：两次 `install` 后锁都保持 `10663 B / 64 条 spec`，未再出现 `698 B / 1 条 spec` 收缩；完成态跑 2 装了 64 个 gem、写入 64 个 gemspec，输出 `Bundle complete! 1 Gemfile dependency, 64 gems now installed.`。
- **新发现（不得当作收缩，但属未解释差异）**：跑 2 结束后锁被重写，`64` 条 spec 的集合、版本、每条依赖约束都相同，但 **16 条 spec 的依赖行次序**与 oracle 不同（我方按 gemspec 声明序，oracle 按字母序）；字节数巧合仍为 10663 B，SHA256 不同。跑 2 stdout 出现两次 `Resolving dependencies...`（跑 1 为 0 次），提示 install 末段仍走了一次解析/重写；该重写路径的依赖序排序与 `lock` 命令的写锁路径不一致——`lock` 与参考逐字节一致是 task-160 已实测结论（本轮未重跑交叉验证，标「未验证」）。
- 该顺序差异是否计入 M7「已解释差异为零」，需按治理口径裁定；本轮**只记录、不改 `src/`**。若认定需修，落点应在 install 末段写锁时对单条 spec 的依赖边排序（`src/celerite/resolution.cr` 内的锁渲染路径，具体行号本轮未定位，标「未验证」）。

### 已声明差异

- 未联网重跑参考侧 `install`（参考侧数字全部引自 task-160 记录），故 `10663 B` 之外无同轮双侧对照；未跑 `bundle check`、`bundle exec`、`rails new` 等后续命令。
- 未做冷/热性能对照：跑 1 `271 s`（网络冷缓存、停在原生扩展）、跑 2 `553.2 s`（含 8 个原生扩展编译、`BUNDLE_PATH` 全新目录），两次环境不同，**不可互为性能基线**，也不与参考侧 `149323 ms` 直接比较。
- 跑 1 未设 `BUNDLE_PATH`，gem 落入**系统** gem 目录（`C:\Ruby40-x64\lib\ruby\gems\4.0.0`，计数 847 目录 / 808 gemspec，含本轮新增 6 个），与 task-160 探针「显式 `BUNDLE_PATH`」的落点不同；跑 2 用 `BUNDLE_PATH=<probe>\bundle` 才得到 64/64 的项目内计数。
- 跑 2 比首辅规定的环境配方多前置了 `C:\Ruby40-x64\msys64\usr\bin`（跑 1 因该目录不在 PATH 而 `make` 不可见、exit 5），并显式设 `BUNDLE_PATH`；这是**两次** install 调用，不是循环重试：跑 1 的失败为环境缺 `make`，未改动任何源码或锁内容。
- 未跑全量 `crystal spec` / 全量差分；未验证 `install` 后 `celerite check`/`list`/`exec` 在本锁上的行为；未定位跑 2 两次 `Resolving dependencies...` 的确切来源。

## 2026-11-23：install 重写锁时的依赖行次序（task-175）

- **现象（rails 8.0.2 规模，首辅实测，本任务未重跑）**：`celerite lock` 与 bundler 4.0.24 逐字节相同（10663 B / 64 条 spec）；随后 `celerite install` 不再收缩锁（task-166 成立），但把锁重写：spec 集合、版本、每条约束都相同，`specs_with_different_dep_lines=16`、`order_only=16`、`content_different=0`，SHA256 因此不同；install stdout 出现两次 `Resolving dependencies...`。
- **离线最小复现形态**：`source "http://127.0.0.1:9/"`（不可达，全程离线）+ `extra/vendor/cache/` 内三个自造桩 gem，其中 `zdep-root-1.0.0` 的 gemspec 先声明 `zchild-gem (~> 1.0)`、再声明 `achild-gem (~> 1.0)`（与字母序相反）；fixture 自带已按字母序的 `Gemfile.lock`，先跑 `lock`（重序列化），再跑 `install --local`。旧二进制在 install 后把 `achild-gem` 行移到 `zchild-gem` 之后，并多打印一次 `Resolving dependencies...`；参考侧不变。
- **机制**：写锁统一走 `src/celerite/lockfile/model.cr:103-124` 的 `SourceSection#to_lock`，原先按 `spec.dependencies` 的存储序逐条输出；参考侧是 `vendor/reference/v4.0.24/bundler/lazy_specification.rb:113-123` 的 `dependencies.sort_by(&:to_s).uniq`（`lockfile_generator.rb:44-55` 的 `add_specs` 只负责 spec 行排序）。install 侧的偏差来自 `src/celerite/cli/commands_install.cr:726-743`：`reuse && cached_paths.any?` 时用 bridge 读回的真实 gemspec 依赖（声明序）调用 `Resolution#refresh_locked_dependencies`（`src/celerite/resolution.cr:1764-1779`），其中 `next spec if dependencies == spec.dependencies` 是**有序**比较，纯次序差异也被当成修复，于是锁被重写、并再打印一次 `Resolving dependencies...`。
- **修复前后对照**：base 72398c0 的二进制跑新夹具 FAIL —— `file-equals` 差异为依赖行换位，stdout 多两行 `Resolving dependencies...`；修复后 4.0.24 与 2.7.2 双 profile PASS，锁与参考逐字节相同，stdout 只余一次 `Resolving dependencies...`（与参考一致）。改动两处：`SourceSection#to_lock` 输出前按渲染行 `uniq.sort!`；`refresh_locked_dependencies` 改用 `dependency_lock_lines` 做无序比较，纯换序不再触发重写。六个相关差分回归全 PASS，`spec/m7_lock*_spec.cr` + `spec/m7_install*_spec.cr` 共 112 examples 0 failures。
- **未验证项**：未在 rails 8.0.2 规模重跑（单次 271–553 秒且需联网 + 原生扩展），rails 侧逐字节一致以离线夹具 + 4.0.24 差分为准；`PATH`/`GIT` 源下多依赖边的排序未单独跑差分（改动只发生在渲染层，现有回归未覆盖该形态）；`spec/m7_lock_gemfile_missing_spec.cr` 在超长 `TMPDIR` 下会因 80 列换行失败（base 72398c0 同样失败，短路径通过），与本任务无关。

## 2026-11-23：task-175 之后 rails 规模 install 的锁逐字节比对（task-179）

- **现象（task-174 遗留）**：task-166 修复后 install 不再把锁收缩成 1 条 spec，但结束时会重写锁：`specs_with_different_dep_lines=16`、`order_only=16`、`content_different=0`，SHA256 由 `C76C7DF6…A199B1` 变为 `7C21E793…13A2`，stdout 两次 `Resolving dependencies...`。task-175 的修复（`src/celerite/lockfile/model.cr:103-124` 渲染前 `uniq.sort!`；`src/celerite/resolution.cr:1777`/`1788-1790` 用 `dependency_lock_lines` 做无序比较）只过了离线夹具，本任务在 rails 8.0.2 规模复验。
- **环境与配方（可复现）**：worktree `C:\temp\celerite-t179`（base `38021fc`，含 `dedb3b1`/`f518737`/`1cd8d16`），Crystal 1.22.1 执行 `crystal build src/cli.cr -o bin/celerite.exe`（exit 0，二次构建 18.6 s，产物 12759863 B）。探针 `C:\temp\celerite-t179\.tmp-t179\proj`：`Gemfile` 恰两行（`source "https://rubygems.org"` + `gem "rails", "8.0.2"`，51 B），`Gemfile.lock` 为 oracle 逐字节副本（10663 B / 64 条 spec / sha256 `c76c7df696da12c829933aa0a22904aa2742bc73f7f19a971fb3e92d86a199b1`）。运行环境：`PATH` 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;C:\Ruby40-x64\msys64\usr\bin`，`SSL_CERT_FILE=C:/msys64/usr/ssl/cert.pem`，`BUNDLE_PATH=<probe>\bundle`，`TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE`/`CRYSTAL_CACHE_DIR` 全指 worktree 内绝对目录。
- **结果（单次 install，未重试）**：耗时 606.1 s，stdout 131 行、stderr 0 行，末两行 `Bundle complete! 1 Gemfile dependency, 64 gems now installed.` 与 `Bundled gems are installed into ./bundle`。锁：10663 B / 64 条 spec / sha256 `c76c7df696da12c829933aa0a22904aa2742bc73f7f19a971fb3e92d86a199b1`，与 oracle **逐字节相同**（Ruby 侧 `File.binread` 直比 `byte_identical=true`）；`specs_with_different_dep_lines=0`、`order_only=0`、`content_different=0`、`extra_in_b=[]`、`missing_in_b=[]`。`Resolving dependencies...` 出现 **0 次**（task-174 为 2 次）。安装落点：`bundle/ruby/4.0.0/gems` 64 个目录、`specifications/*.gemspec` 64 个、`.so` 15 个。锁文件 `LastWriteTime` 仍为复制时的 `2026-11-23T09:04:14`（本次运行起点 16:52），即 install 本轮**没有改写**锁。
- **判定与机制**：task-175 的两处改动在真实规模成立。①渲染层排序使「从真实 gemspec 读回的声明序依赖」不再落盘，避免了 order-only 差异；②`refresh_locked_dependencies` 改无序比较后，纯换序不再被当成需要修复，因而不再触发「重写锁 + 第二次解析」。task-174 的 16 条 order-only 差异与两次 `Resolving` 同时消失，两者互为因果链的两端，与修复描述一致。
- **已声明差异（M7-9 行 `docs/roadmap.md:149` 目前剩余项，逐条点名）**：①锁内 spec 依赖行之外的其它差异 = 无（整文件 `byte_identical=true`，逐行差集为空）；②`Resolving dependencies...` 次数 = 0，与 task-174 的 2 次对照后不再构成差异；③原生扩展/宿主限制 = 本轮无失败（racc 1.8.1、rbs 4.2.0、websocket-driver 0.9.0 等原生扩展全部编译成功，15 个 `.so`），`make` 只在 `C:\Ruby40-x64\msys64\usr\bin`、不在任务书给的 `C:\msys64\{usr,ucrt64}\bin`，属宿主配方事实而非产品差异；④参考侧本轮**未重跑**，oracle 锁与参考行为锚点沿用 task-160/task-174 的记录，未用本轮新证据替代；⑤尚未覆盖的验证缺口（非差异）：安装文件树逐文件内容/权限/symlink 比较、重复 install 幂等、冷/热/无变化性能对照、Linux gnu/musl 与多 Ruby ABI。
- **未验证项**：①install 进程的数值退出码未取到——`Start-Process -PassThru` 在本环境返回空 `ExitCode`（对照命令 `celerite --version` 同样为空，而直调 `$LASTEXITCODE=0`），成功仅由末两行完成提示与 stderr 0 行推定；②如④，参考侧未在本轮重跑；③只跑一次 install，未验证二次运行是否仍不重写锁。

**结论：锁维度未解释差异 = 0。** M7-9 的 Rails 规模行在 task-175 之后于本机锁层面闭合，但因参考侧未重跑、安装树未逐文件比较，仍不据此恢复「该 profile 兼容」的声明。


## 2026-11-23：安装树、`check`、`exec` 的逐项比对与未解释差异收口（task-194）

### 任务

`docs/roadmap.md:149` 的闭合判据是「记录所有有意兼容差异及理由；未解释差异为零后才恢复『该 profile 兼容』的声明」。task-179 只把**锁维度**做到逐字节相同（10663 B / 64 条 spec / `c76c7df6…a199b1`），本任务在同一把 oracle 锁下把**安装树**、`check`、`exec`、`binstubs` 一并比完，并给出未解释差异清单。全程不改产品代码；发现可修处只报最小落点。

### 环境与配方

- worktree `C:\temp\celerite-t194`，HEAD `954f2d5`；`crystal build src/cli.cr -o bin/celerite.exe` exit 0，产物 12772691 B（两条 `File.executable?` 弃用告警，`src/celerite/cli/commands_install.cr:1760`、`:1823`）。
- 两侧探针 `.tmp-scratch/probe-cel`、`.tmp-scratch/probe-ref`：`Gemfile` 两行（`source "https://rubygems.org"` + `gem "rails", "8.0.2"`，51 B）、`Gemfile.lock` = oracle 副本（10663 B，sha256 `c76c7df696da12c829933aa0a22904aa2742bc73f7f19a971fb3e92d86a199b1`），各自隔离的 `bundle/`、`home/`、`tmp/`。
- 运行环境（两侧相同）：`PATH` 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;C:\Ruby40-x64\msys64\usr\bin`，`SSL_CERT_FILE=C:/msys64/usr/ssl/cert.pem`，`BUNDLE_PATH=<probe>\bundle`、`BUNDLE_GEMFILE=<probe>\Gemfile`、`BUNDLE_USER_HOME=<probe>\home`，`TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE`/`CRYSTAL_CACHE_DIR` 全在 worktree 内。
- 参考侧：`& 'C:\Ruby40-x64\bin\ruby.exe' 'C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\exe\bundle'`。install 两侧各只跑一次，未重试。

### 实测一：`install` 与安装树

- cel：`bin\celerite.exe install` exit 0，705 s，stdout 131 行、stderr 0 行；ref：exit 0，148 s，stdout 131 行、stderr 0 行。两侧 stdout 形状相同：`Fetching ` 各 65 行（首行 `Fetching gem metadata from https://rubygems.org/.........`）、`Installing ` 各 64 行且逐行集合完全相同，末两行逐字同为 `Bundle complete! 1 Gemfile dependency, 64 gems now installed.` 与 `Bundled gems are installed into ./bundle`；`Resolving dependencies...` 两侧均 0 次。
- 两侧锁均未被改写：10663 B / sha256 `c76c7df696da12c829933aa0a22904aa2742bc73f7f19a971fb3e92d86a199b1`。
- 全树逐文件比对（`Get-ChildItem -Recurse -File` + SHA256，两侧探针路径归一后再比；脚本与结果 `.tmp-scratch/compare.ps1`、`.tmp-scratch/compare.json`、`.tmp-scratch/sets-summary.txt`）：文件数 cel 4479 / ref 4480，`only_in_cel=0`、`only_in_ref=1`、`content_diff=39`、纯路径差异 0。
- 集合级全部相等（`only_*` 均为 0）：`gems` 目录名 64/64；`specifications/*.gemspec` 文件名 + 内容 sha256 64/64；`cache/*.gem` 文件名 + 内容 sha256 64/64；`extensions/` 递归相对路径 28/28；`*.so` 相对路径 22/22；`bin/` 文件名 24/24。
- 差异明细（共 40 个文件条目）：(a) `only_in_ref` 唯一一条 `ruby/4.0.0/plugins/rdoc_plugin.rb`（61 B，内容 `require_relative '../gems/rdoc-8.1.0/lib/rubygems_plugin.rb'`），cel 侧 `plugins/` 为空；(b) 12 个 `bin/*.bat`（cel 32 B / ref 34 B，去掉 CR 后逐字节相同 ⇒ 仅 LF vs CRLF）；(c) 14 个 `.so`（`extensions/x64-mingw-ucrt/4.0.0/<gem>/` 与 `gems/<gem>/lib/` 各 7 个，cel 侧均更小：date_core 232960/236544、rbs_extension 296448/299008、bigdecimal 125952/128512、console 47616/50688、cparse 20992/24576、escape 14848/17920、websocket_mask 9728/12800；22 个 `.so` 中 8 个逐字节相同）；(d) 13 个构建日志（8 个 `gem_make.out` + 5 个 `mkmf.log`，后者只在 bigdecimal/date/erb/io-console/rbs 出现）。

### 实测二：`.so` 与构建日志的差因

- `racc/cparse.so` 内嵌标识：cel `GCC: (Rev6, Built by MSYS2 project) 16.2.0`，ref `GCC: (Rev5, Built by MSYS2 project) 16.1.0`；`C:\msys64\ucrt64\bin\gcc.exe --version` = Rev6 16.2.0，`C:\Ruby40-x64\msys64\ucrt64\bin\gcc.exe --version` = Rev5 16.1.0。
- 两侧 `mkmf.log` 的 PATH 串前缀不同：ref 为 `.;C:/Ruby40-x64/lib;C:\Ruby40-x64\bin;C:\Ruby40-x64\msys64\ucrt64\bin;C:\Ruby40-x64\msys64\usr\bin;` + 本任务前置项 + 基线；cel 为 `.;C:/Ruby40-x64/lib;` + 本任务前置项 + 基线（无 Ruby 自带 msys64 目录）。故 extconf 解析到不同发行版的 `gcc`，`.so` 字节随工具链而变。**是谁在扩展构建前把 Ruby 自带 msys64 目录加进 PATH，本轮未定位（未验证）。** 对照组：plain ruby / `celerite exec ruby` / `bundle exec ruby` 打印的 PATH 前 6 段只差各自 `bundle/ruby/4.0.0/bin` 前置，其余完全一致，故不是 shell 层的 PATH 差异。
- 13 个日志把探针路径、`.gem.<日期>-<pid>-<rand>` 临时名与 CR 归一后仍不同，唯一实质差：ref 用 `make -j3`（并带 GNU make 4.4 的 jobserver 告警 4 行），cel 用不带 `-j` 的 `make`，故 ref 每个 `gem_make.out` 多 4 行、尺寸大 279–355 B。机制：`assets/bridge/server.rb:551` 为 `Gem::Ext::Builder.new(spec, build_args).build_extensions`，未传 `build_jobs`（`n_jobs` 为 nil ⇒ 串行）；参考侧 `bundler-4.0.24/lib/bundler/rubygems_gem_installer.rb:108-112` 的 `build_jobs` 取 `acquired_jobs || Bundler.settings[:jobs] || super`，`settings.rb:309` 回落 `processor_count`，本机 `Etc.nprocessors=8`，实测为 `-j3`。两侧 `gem_make.out` 的其余差异只是探针路径与 gem 临时名。

### 实测三：`check`

- cel `celerite check`：exit 0，stdout 恰一行 `The Gemfile's dependencies are satisfied`，stderr 空。
- ref `bundle check`：exit 0，stdout 同一行，stderr 空。**两侧逐字相同。**

### 实测四：`exec`

- `celerite exec ruby -e "require 'rails'; puts Rails::VERSION::STRING"` exit 0 → `8.0.2`；ref 侧 `bundle exec ...` 同样 exit 0 → `8.0.2`。
- `-e "puts $LOAD_PATH.grep(/bundle|gems/).first(3)"`：cel 为 `C:/Ruby40-x64/lib/ruby/gems/4.0.0\gems\bundler-4.0.24\lib`、`<probe-cel>/bundle/ruby/4.0.0/gems/rails-8.0.2/lib`、`.../railties-8.0.2/lib`；ref 同序同条目，但分隔符全为 `/`。路径集合与顺序等价，仅分隔符拼法不同。
- 首跑因 PowerShell 吞掉双引号变成 `require rails`，两侧同为 `-e:1:in '<main>': undefined local variable or method 'rails' ... (NameError)` exit 1 —— 命令构造问题，不计入产品差异。

### 实测五：`binstubs`

- `binstubs rack`：两侧 exit 0，stderr 同为 `There are no executables for the gem rack.`，未生成 `bin/`。
- `binstubs rails`：两侧 exit 0，stderr 首句同为 `rails has no executables, but you may want one from a gem it depends on.`；候选清单不同：cel 只有 `railties has: rails`，ref 另有 `bundler has: bundle, bundler`。
- `binstubs railties`：两侧 exit 0 且无输出，`bin/rails`（353 B，sha256 `fc2e5c7c95ab2e6ae244c28ec6d921f3397ed86849058ea7654fff6c66992ea2`）与 `bin/rails.cmd`（395 B，sha256 `a39627abd96a42071ff5390e8b694c9181f4ffe4aa92afb20723d11ce6676e70`）**逐字节相同**。

### 未解释差异清单

| # | 差异内容 | 是否有意（锚点 / 已声明） | 是否已解释 |
| --- | --- | --- | --- |
| 1 | `plugins/rdoc_plugin.rb` 仅参考侧存在（cel 侧 `plugins/` 为空） | 未声明；无参考行为锚点可援引，我方 `src/` 全库无 `plugins`/`plugindir` 处理，即未实现 RubyGems 写 plugin 的副作用 | **否** |
| 2 | 12 个 `bin/*.bat` 行结束符 LF vs CRLF（去 CR 后逐字节相同） | 未声明；我方 stub 写出用 LF，参考侧写 CRLF | **否**（机制已定位，可一句话修或声明为等价差异） |
| 3 | 14 个 `.so` 字节不同（嵌入 GCC Rev6 16.2.0 vs Rev5 16.1.0） | 未声明；属宿主工具链族，按治理口径不得记为已解释 | **否**（根因未定位） |
| 4 | 13 个构建日志不同（`make` vs `make -j3`、PATH 串前缀） | 未声明；`-j3` 一侧机制明确（我方未传 `build_jobs`），PATH/工具链一侧与 #3 同源 | **否** |
| 5 | `binstubs rails` 候选清单少 `bundler has: bundle, bundler` | 未声明；机制未定位（疑与参考侧把 bundler 自身算入可建议 gem 有关，本轮未读码确认） | **否** |

- 已排除的差异：来自 `gem_make.out` 的探针路径与 `.gem.<pid>-<rand>` 临时名（归一后相同）；`exec` 的 `$LOAD_PATH` 分隔符拼法（条目与顺序相同，功能等价）。两侧 `check` 输出、`install` 完成提示、`Installing` 行集合、`binstubs railties` 产物均逐字节相同。

### 判定

**未解释差异 = 5（类），共 40 个文件条目 + 1 条 stderr 文本差异。** 构成：plugin 写出缺失 1 条文件、`bin/*.bat` 换行 12 条、`.so` 工具链 14 条、构建日志 13 条、`binstubs rails` 候选清单 1 处文本。

因此 `docs/roadmap.md:149` 的闭合判据**未满足**：M7-9 行不勾选，「该 profile 兼容」的声明不恢复。其中 #1/#2/#4 的机制已定位，若要归零需先决定「实现」还是「登记为有意差异」；#3/#5 的机制未定位，按治理口径不得计入已解释。

最小落点（本轮不改码，仅记录）：#1 我方安装路径未调用 RubyGems 写 plugin 的步骤（`assets/bridge/server.rb:499` 构造 `Gem::Installer` 前后，未验证具体需调 `write_plugins`）；#2 stub 生成的 bat 模板使用 LF（模板位置未定位，未验证）；#4 `assets/bridge/server.rb:551` 的 `Gem::Ext::Builder.new(spec, build_args)` 未传 `n_jobs`。

### 未验证项

- 扩展构建前 PATH 被谁改写（#3/#4 的根因）未定位；只证明了「两侧 PATH 在该时刻不同」与「`.so` 内嵌 GCC 版本不同」。
- 两侧 install 耗时 705 s vs 148 s **不可互为基线**（工具链不同、我方全程串行构建、缓存状态不同）。
- 未跑全量 `crystal spec`、未跑 `script/differential` 门禁；本任务只做端到端实测与文档。
- 未在 Linux / 其它 Ruby ABI 复验；未验证重复 install 的幂等性。
- #1 缺失 plugin 的实际功能影响（在该 `BUNDLE_PATH` 下 `gem` CLI 是否加载 rdoc plugin）未跑。
- #5 的机制未读码确认，仅记录观测差异。
## 2026-11-23：安装副作用三项的对齐（task-196）

### oracle

- plugin：`Gem::Installer#install` 内部 `generate_plugins` 写 `plugins/<gem>_plugin.rb`（`C:\Ruby40-x64\lib\ruby\4.0.0\rubygems\installer.rb:268,290,475-488`；实际写出在 `installer_uninstaller_utils.rb:7-22`，plugin 发现于 `basic_specification.rb:317-319`）。4.0.24 与 2.7.2 两侧夹具 `install-writes-rubygems-plugin` 均产出 `vendor/bundle/ruby/4.0.0/plugins/plugin-gem_plugin.rb`。
- bat：`installer.rb:427-437` 以文本模式 `File.open(..., "w") { |f| f.puts }` 写 stub，Windows 上为 CRLF。参考侧 `bat-stub-demo.bat` 34 B，十六进制以 `...\r\n@ruby.exe "%~dpn0" %*\r\n` 收尾；我方修复前 32 B、两处为孤立 `0A`。
- jobs：4.0.24 `build_jobs = acquired_jobs || settings[:jobs] || super`（`bundler-4.0.24/lib/bundler/rubygems_gem_installer.rb:108-115`），`BUNDLE_JOBS=2` 时 `gem_make.out` 出现 `make -j2`；2.7.2 无该覆写（`bundler-2.7.2/lib/bundler/rubygems_gem_installer.rb:104-127` 直接 `super`），走 RubyGems 默认 `Etc.nprocessors + 1`，本机（`Etc.nprocessors=8`）为 `make -j9`。
- 关键前提：**带 `Gemfile.lock` 的单 gem 安装无法观察参考并行**。4.0.24 把 job 数压到待装 spec 数，实测 hook 记录 `n_jobs=1 settings_jobs=1`；去掉锁后同一夹具得 `n_jobs=2 settings_jobs=2 MAKEFLAGS="--jobserver-auth=4,5"`，`make` 打印「强制 -j2: 重置 jobserver 模式」。故 `install-ext-jobs` 不带锁；带锁的旧观测（`-j3`）应视为多 gem 场景的结论。

### 参考锚点

- `C:\Ruby40-x64\lib\ruby\4.0.0\rubygems\installer.rb:253-255`：`Gem::Installer#spec` 返回 `@package.spec`，不是 `@spec`；`instance_variable_set(:@spec, ...)` 对 `generate_plugins` 无效，必须改 package spec 的 `full_gem_path`，且反斜杠路径会让 `plugins` glob 返回空——实现里已 `tr("\\", "/")`。
- `...\rubygems\ext\builder.rb:24-47`：`n_jobs > 1` 且 `MAKEFLAGS` 无 `-j` 时才追加 `-jN`；`:208-225` 把命令行写入 `gem_make.out`，这是判据可钉的依据。
- `vendor/reference/v4.0.24/settings.rb:230,309`：`settings[:jobs]` 缺省回落 `Etc.nprocessors`。

### 实现位置

- `assets/bridge/server.rb:520`：bat 改为文本模式 `File.open(..., "w")` 调 `windows_stub_script`，CRLF 交给 RubyGems。
- `assets/bridge/server.rb:535-553`：新增 `op_generate_plugins`，`Gem::Installer.at` + package spec 的 `full_gem_path` + `send(:generate_plugins)`；`bridge_dispatch` 注册 `generate_plugins`。
- `assets/bridge/server.rb:556-590`：`op_build_extension` 按 `jobs_mode` 传第四参；`rubygems` 模式传 `Etc.nprocessors + 1`。
- `src/celerite/bridge/client.cr:452,471`：`generate_plugins` 与 `build_extension(..., build_jobs, jobs_mode)`。
- `src/celerite/installer.cr:83,263,284-288`：`build_jobs_mode`/`build_jobs` 取自 profile 与 `config["jobs"]`，扩展构建下传；`bin` 发布后调用 plugin 生成，失败即 `Error`。

### 证据

- 4.0.24：`install-writes-rubygems-plugin`、`install-binstub-bat-crlf`、`install-ext-jobs` 3 passed 0 failed；2.7.2 同 3 passed。
- 反假绿（`C:\temp\celerite-pre196\bin\celerite.exe`，两 profile 均 3 failed）逐字：
  - `Only in SANDBOX/project/vendor/bundle/ruby/4.0.0/plugins: plugin-gem_plugin.rb` + `file-exists violated (...): ref_exists=yes cel_exists=no`
  - `file-crlf-both differs (vendor/bundle/ruby/4.0.0/bin/bat-stub-demo.bat, cel): missing CRLF`
  - 4.0.24 `needle=make -j2`、2.7.2 `needle=make -j` 的 `file-contains differs (...gem_make.out)`
- 回归：`install-check install-rewrites-lock-in-lock-order install-keeps-lock-with-bundler-edge lock-missing-spec-row install-after-lock-keeps-transitive binstubs-shebang` 6 passed。
- `crystal spec spec/m7_install*.cr spec/m7_binstubs*.cr`：66 examples，1 failure（`spec/m7_install_app_cache_spec.cr:103`）；该用例在基线 `cec5daa`（stash 掉本轮 `installer.cr` 改动后）同样失败，与本任务无关。

### 已声明差异与未验证

- `install-ext-jobs` 用无锁的最小合成 gem，2.7.2 判据只钉 `make -j`（具体并发数取宿主 `Etc.nprocessors + 1`，不入库断言）；4.0.24 钉 `make -j2`。
- 新增 harness 判据 `file-crlf-both`（两 profile 都要求 CRLF 且无孤立 LF）与 `file-contains-<version>` 覆盖；说明见 `docs/differential-normalization.md`。
- 未复跑 rails 规模端到端；#3（`.so` gcc 版本）与 #5（`binstubs rails` 候选清单）未动，仍按 task-194 记为未解释。
- 未在 Linux/其它 Ruby ABI 复验；plugin 在真实 `BUNDLE_PATH` 下由 `gem` CLI 加载的功能影响未跑。
- `m7_install_app_cache_spec.cr:103` 的既存失败未修（超出本任务范围），仅证明与本次改动无关。
## 2026-11-23：binstubs 运行时依赖候选与 M7-9 差异收口（task-202）

### oracle

- 最小探针 `C:\temp\bs-probe`：`Gemfile` 为 `source "file:///<repo>/fixtures/gem-index"` 加 `gem "a", path: "a"`；`a.gemspec` 中 `s.files = []` 且 `s.add_dependency "bundler", ">= 1.15.0"`。参考 4.0.24 `bundle lock --local` exit 0，锁的 PATH 段为 `a (1.0.0)` 带 `bundler (>= 1.15.0)` 边、**无** bundler spec 行；CHECKSUMS 段为 `a (1.0.0)` 与 `bundler (4.0.24) sha256=16ca64e20816a0cf151a948fb141d788602996d2b4d73577b74388fe84fa98bc`。
- 参考 `bundle binstubs a`（4.0.24 与 2.7.2 各自独立跑，均 exit 0）stderr 逐字两行：
  `a has no executables, but you may want one from a gem it depends on.`
  `  bundler has: bundle, bundler`
- 修改前 celerite 在同一探针（喂入参考 4.0.24 生成的 `Gemfile.lock`）上 exit 0，stderr 只有 `There are no executables for the gem a.`，即复现 #5。
- 无种子锁时 celerite 侧 `install --local` 打印 `version solving has failed`、exit 6：celerite 解析器不为 path gem 的 bundler 边合成 spec（C-M7-9-004 只覆盖锁写出），属另一问题。夹具因此随附锁文件，且 `binstubs` 前不跑 `install`（参考侧不装也能出候选，且锁逐字节不变）。

### 参考锚点

- `cli/binstubs.rb:34-40`：`spec = Bundler.definition.specs.find { |s| s.name == gem_name }`，随后 `installer.generate_bundler_executable_stubs(spec, installer_opts)`。
- `installer.rb:92-118`：`spec.name == "bundler"` 时直接告警返回；`binstubs` 命令且 `spec.executables.empty?` 时遍历 `spec.runtime_dependencies`，取 `@definition.specs[dep].first.executables`，非空者收集后打印 `"#{spec.name} has no executables, but you may want one from a gem it depends on."` 与逐条 `  #{name} has: #{bins.join(", ")}`；全空才打印 `There are no executables for the gem #{spec.name}.`。
- `definition.rb:249-251` 的 `specs = materialize(requested_dependencies)` 与 `definition.rb:756-757` 把运行中的 bundler 注入 `specs["bundler"]`，故 `definition.specs["bundler"].first.executables == ["bundle", "bundler"]`，而 `locked_gems.specs["bundler"] == []`（锁里没有 bundler 的 spec 行）。
- `spec_set.rb:98-101` 的 `SpecSet#[]` 返回数组，参考取 `.first`。

### 我方行为与实现位置

- `src/celerite/cli/commands_install.cr:2157-2172`：显式 `binstubs <gem>` 的无可执行文件分支不再只查锁内 `targets`，每个运行时依赖改由 `runtime_dependency_spec_info` 解析。
- `:2285-2304` 新增 `private def self.runtime_dependency_spec_info(...)`：依赖已在 `targets` 中则沿用 `binstub_spec_info`；否则仅对 `bundler` 回落到 Ruby 安装自身的 `<ruby_default_dir || default_gem_dir>/specifications/bundler-<profile 版本>.gemspec`（缺失时 `Dir.glob("bundler-*.gemspec")` 且优先精确文件名），经 `bridge.load_installed_spec` 读取可执行文件与 bindir；读不到即按「不可用」跳过。无锁行、非已装 gem 的依赖不会被凭空补出。
- `:2306-2314` 抽出 `binstub_payload_info`，GEM/PATH/GIT/已装 bundler 四条路径共用同一份 `executables`/`bindir`/`dependencies` 解析；`:2264-2269` 对 GEM 源的依赖名按名字排序——参考从锁物化的 GEM spec 其依赖行即锁文件顺序（字典序），rails 实测参考先 `bundler` 后 `railties`，与我方 `s.gemspec` 声明序相反。
- 既有 `binstubs` 成功路径（写 `bin/` 文件）与文件内容未改：`binstubs railties` 的两侧产物仍逐字节相同（task-194 已测，本轮回归夹具覆盖）。

### 证据

- 新夹具 `fixtures/differential/binstubs-runtime-dependency-candidates`（`Gemfile` + 参考 4.0.24 锁 + `extra/a/a.gemspec`，`command` 仅 `binstubs a`）：`bash script/differential binstubs-runtime-dependency-candidates` 在 4.0.24 与 2.7.2 均 `1 passed, 0 failed`。
- 反假绿：`CELERITE_BIN=C:\temp\celerite-pre202\bin\celerite.exe`（同 commit `2cbc9f6`、改动前二进制）跑同一夹具，两 profile 均 FAIL，逐字：
  `1,2c1`
  `< a has no executables, but you may want one from a gem it depends on.`
  `<   bundler has: bundle, bundler`
  `---`
  `> There are no executables for the gem a.`
- 回归：`bash script/differential binstubs binstubs-flags binstubs-path-removed binstubs-path-source binstubs-shebang binstubs-shebang-line binstubs-template`，4.0.24 与 2.7.2 均 `7 passed, 0 failed`。
- `crystal spec spec/m7_binstubs_path_source_spec.cr spec/m7_binstubs_template_spec.cr`：7 examples、0 failures；`crystal tool format --check src spec` exit 0；`git diff --check` exit 0。
- rails 规模终验（两侧各一次 `install` 加一次 `binstubs rails`，同一把 oracle 锁 `c76c7df696da12c829933aa0a22904aa2742bc73f7f19a971fb3e92d86a199b1`，隔离 `bundle/`/`home/`/`tmp/`，`SSL_CERT_FILE=C:/msys64/usr/ssl/cert.pem`，`PATH` 含 `C:\Ruby40-x64\msys64\usr\bin`）：两侧 install 均 exit 0、末两行相同；安装树 cel 4480 / ref 4480 个文件，`only_in_cel=0`、`only_in_ref=0`、`content_diff=27`（14 个 `.so` + 13 个构建日志，与 task-199 同类同数）；三把锁（oracle、ref、cel）sha256 均 `c76c7df6…199b1`，未被改写。
- `binstubs rails` 候选文本两侧现为同样三行：`rails has no executables, but you may want one from a gem it depends on.` / `  bundler has: bundle, bundler` / `  railties has: rails`。字节层仍差换行：ref 129 B（CRLF）、cel 126 B（LF），系 Ruby 文本模式重定向与 Crystal 直接写 stderr 的平台差异，非候选内容差异。

### 已声明差异与未验证

- 剩余安装树差异只有两类，均已归因为宿主工具链而非产品行为：① 14 个 `.so` 的内嵌 GCC 版本（ref 经 `Gem.pre_install` 钩子前置 RubyInstaller MSYS2，`Rev5 16.1.0`；cel 的 bridge 直调 `Gem::Ext::Builder`，PATH 保持探针 `Rev6 16.2.0`）；② 13 个构建日志因 `make` 的 `-j` 与 PATH 串文本不同（cel 固定 `-j8`，ref 为 jobserver 动态 `-j3`/`-j2`）。两类都不改变产物集合与可执行语义。
- 未覆盖：多可执行依赖的候选**顺序**只有 rails 规模实测支撑（GEM 源按锁行序），PATH/GIT 源多依赖顺序未单独取证；夹具只有一个可执行依赖，未钉顺序。
- 未覆盖：无种子锁时 celerite 对「path gem 依赖 bundler」的解析失败（exit 6）未修，属解析器合成 bundler spec 的问题，与本任务候选层改动无关。
- 未复跑：本次 rails 终验只各跑一次 `install`，未验证重复 install 的幂等与耗时；未在 Linux/其它 Ruby ABI 复验。
- 反假绿只跑新夹具；既有 binstubs 夹具的改动前对照沿用 task-194/196 记录。

### 判定

`binstubs` 候选清单的产品侧差异已对齐（含候选顺序），安装树剩余 27 个内容差异全部归因为宿主工具链，集合级差异为 0；M7-9 的最后一处产品侧可见差异关闭。是否勾选 `docs/roadmap.md:149` 由首辅按本文件与 claims 结论裁定（本任务禁改该文件）。

## 2026-11-23：task-196/202 之后的安装树终验与 M7-9 判据（task-204）

工作树 `C:\temp\celerite-t204`@`302cbae`（`git status` 干净；本轮只写文档，`src/`、`spec/`、`fixtures/`、`script/` 未改）。反假绿源 `C:\temp\celerite-pre204` 与工作树同 commit，本轮无实现改动，未使用其二进制（见「未验证」）。二进制由 `crystal build src/cli.cr -o bin/celerite.exe` 现编：EXIT 0、28 s、12786522 B；`crystal` 在 `C:\msys64\ucrt64\bin`，构建前须把 `C:\msys64\usr\bin` 前置，否则 Crystal stdlib `openssl/lib_crypto.cr:24` 的 `sh -c` 会失败。

### oracle

- 锁：`C:\Users\ShiningRay\projects\ShiningRay\celerite\.tmp-scratch\lead-rails-oracle\Gemfile.lock.full`（10663 B、64 spec、sha256 `c76c7df696da12c829933aa0a22904aa2742bc73f7f19a971fb3e92d86a199b1`）。
- 两个隔离探针 `C:\temp\celerite-t204\.tmp-scratch\probe-cel`、`probe-ref`（绝对路径 44 字符 ≤67）：`Gemfile` 只有 `source "https://rubygems.org"` 与 `gem "rails", "8.0.2"`；锁为 oracle 拷贝；`BUNDLE_PATH=<probe>\bundle`；`SSL_CERT_FILE=C:/msys64/usr/ssl/cert.pem`；`PATH` 前置 `C:\Ruby40-x64\msys64\usr\bin;C:\Ruby40-x64\bin`；`TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE` 都指到探针内的 `tmp`/`home`。
- 两侧各跑一次 `install`，均 exit 0：cel `bin\celerite.exe install` 470 s；ref `ruby.exe ...\bundler-4.0.24\exe\bundle install` 141 s。两侧 stdout 各 131 行、末两行相同：`Bundle complete! 1 Gemfile dependency, 64 gems now installed.` 与 `Bundled gems are installed into `./bundle``；两侧锁 sha256 仍 `c76c7df6…199b1`，未被改写。
- `binstubs rails` 两侧各一次、均 exit 0：cel stdout 0 B / stderr 126 B（LF，sha256 `4DB03856…`）；ref stdout 0 B / stderr 129 B（CRLF，sha256 `9B898911…`）。三行内容逐字相同：`rails has no executables, but you may want one from a gem it depends on.` / `  bundler has: bundle, bundler` / `  railties has: rails`；LF 归一后完全相等；两侧均未生成 `probe\bin`（rails 本身无 executables，与参考一致）。两把锁在 `binstubs` 后仍是 `c76c7df6…199b1`。

### 参考锚点

- `C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\lib\bundler\installer.rb:92-118`：`binstubs` 的候选打印（运行中 bundler 恒注入，`executables == ["bundle", "bundler"]`）；rails 规模实测参考 stderr 即上文三行。
- `C:\Ruby40-x64\lib\ruby\4.0.0\rubygems\ext\builder.rb:24-47,89-101,208-225`：`n_jobs > 1` 且 `MAKEFLAGS` 无 `-j` 才追加 `-jN`；`gem_make.out` 记 `current directory` 与逐条命令行。参考侧 rails 规模实测：`date` 等走 plain `make`（MAKEFLAGS 带 jobserver，子 make 报 `jobserver 不可用: 正使用 -j1`），`nio4r` 走 `make -j2`——即本轮**不是固定 `-j3`**。
- 参考侧扩展构建的 `gcc`：`mkmf.log` 的 `PATH` 头部为 `.;C:/Ruby40-x64/lib;C:\Ruby40-x64\bin;C:\Ruby40-x64\msys64\ucrt64\bin;C:\Ruby40-x64\msys64\usr\bin;…`（RubyInstaller MSYS2 的 `ucrt64` 在前，`gcc` 解析到 16.1.0）；该前置由 `Gem.pre_install` 钩子完成（task-199 已定位，本轮未重验钩子代码行）。
- `plugins/rdoc_plugin.rb` 参考侧存在（61 B）、`bin/*.bat` 文本模式写 CRLF：task-196 已按 `rubygems/installer.rb` 的 `generate_plugins` 与 `generate_windows_script` 对齐，本轮只做端到端复核。

### 实现位置

- 本轮无实现改动（只写文档）。复核对象是 task-196/202 已落地的路径：`assets/bridge/server.rb:520`（bat 文本模式）、`:535-553`（`op_generate_plugins`）、`:556-590`（`op_build_extension` 传 jobs）；`src/celerite/bridge/client.cr:452,471`；`src/celerite/installer.cr:83,263,284-288`；`src/celerite/cli/commands_install.cr:2157-2172,2264-2269,2285-2304`（binstubs 运行时依赖候选）。
- 二进制即上述工作树状态（`302cbae` + 未改 `src`）的编译产物。

### 证据

- 安装树（路径归一 `/`、去探针前缀、SHA256）：cel 4480 / ref 4480 文件；`only_in_cel=0`、`only_in_ref=0`、`content_diff=27`。27 个差异逐类：
  - 14 个 `.so`：`bigdecimal-4.1.3`（`bigdecimal.so`）、`date-3.6.0`（`date_core.so`）、`erb-6.0.7`（`erb/escape.so`）、`io-console-0.9.5`（`io/console.so`）、`racc-1.8.1`（`racc/cparse.so`）、`rbs-4.2.0`（`rbs_extension.so`）、`websocket-driver-0.9.0`（`websocket_mask.so`）各两份（`extensions/x64-mingw-ucrt/4.0.0/<gem>/` 与 `gems/<gem>/lib/`）。
  - 8 个 `gem_make.out`：上述 7 个加 `nio4r-2.7.5`（该 gem 两侧均无 `.so`，集合一致）。
  - 5 个 `mkmf.log`：`bigdecimal`、`date`、`erb`、`io-console`、`rbs`。
- `.so` 字节差归因：取 `bigdecimal.so` 内嵌版本串，cel 为 `GCC: (Rev6, Built by MSYS2 project) 16.2.0`，ref 为 `GCC: (Rev5, Built by MSYS2 project) 16.1.0`。`mkmf.log` 的 `PATH` 证实机制：cel 的 PATH 头是 `.;C:/Ruby40-x64/lib;C:\Ruby40-x64\msys64\usr\bin;C:\Ruby40-x64\bin;…;C:\msys64\ucrt64\bin;…`（无 `Ruby40-x64\msys64\ucrt64\bin`，`gcc` 落到全局 `C:\msys64\ucrt64\bin` 的 16.2.0）；ref 的 PATH 头是 `.;C:/Ruby40-x64/lib;C:\Ruby40-x64\bin;C:\Ruby40-x64\msys64\ucrt64\bin;C:\Ruby40-x64\msys64\usr\bin;C:\Ruby40-x64\msys64\usr\bin;…`（RubyInstaller MSYS2 16.1.0 在前）。与 task-199 的 `Gem.pre_install` 归因一致。
- 13 个构建日志：逐行比对并归一（`probe-cel`/`probe-ref`→`PROBE`、`.gem.<date>-<pid>-xxxxxx`→`.gem.X`、`make -jN`→`make`）后仍有纯文本残差：① ref 侧每个 make 调用多一行 `make: 警告: jobserver 不可用: 正使用 -j1。…`（`date` 的 `gem_make.out` cel 27 行 vs ref 31 行，差额即 4 行警告）；② `nio4r` 的 make 错误文本本地化不同（cel `make: *** No rule to make target 'clean'.  Stop.`，ref `make: *** 没有规则可制作目标“clean”。 停止。`）；③ `mkmf.log` 的 PATH 串不同。四段 make 调用两侧一一对应（clean / build / install / clean），无缺失构建步骤。
- `plugins/rdoc_plugin.rb`：两侧均存在、61 B、sha256 前缀 `5512116D…`，内容相同。`bin/*.bat`：两侧各 12 个，12/12 SHA256 相同且均含 CRLF（`bat_mismatch=0`）。`.so` 两侧各 22 个，14 个不同、8 个相同。
- install stdout：两侧各 131 行；行内容集合仅一处不同——`Fetching gem metadata from https://rubygems.org/` 后的进度点 cel 1 个、ref 9 个；其余 130 行文本相同。**但顺序不同**：cel 先按锁序（字典序）打印 64 条 `Fetching`，再按同一序打印 `Installing`（8 个原生扩展排最后）；ref 按依赖顺序 fetch/install 交错。两侧退出码、安装集合、锁均一致。
- `binstubs rails` 逐字：见 oracle 段；LF 归一后两侧相等，字节差仅 LF（126 B）vs CRLF（129 B）。

### 已声明差异与未验证

- 差异清单（合计 6 类，全部有机制，**未解释差异 = 0**）：
  1. 14 个 `.so` 字节不同——宿主工具链：gcc 16.1.0（ref，RubyInstaller MSYS2 经 `Gem.pre_install` 前置）vs 16.2.0（cel，bridge 直调 `Gem::Ext::Builder`，PATH 无 RubyInstaller `ucrt64`）。产品语义无差（同一 gem、同一版本、同一 `.so` 名，安装树集合一致）。
  2. 13 个构建日志文本不同——仅日志：`-j` 文本、jobserver 警告、PATH 串、`make` 本地化错误文本；产物不变。
  3. `binstubs` 的 stderr 换行——cel LF、ref CRLF；内容三行相同。
  4. install stdout **顺序**——cel 两阶段（先 fetch 全部再 install），ref 交错；行内容与最终状态一致。
  5. install stdout 元数据进度点——cel 1 个、ref 9 个；进度显示，不入判据。
  6. 两侧 install 耗时 470 s / 141 s——实现差异（并发与阶段），不作为兼容判据。
- ④ 的裁定（`make -j8` vs 参考）：**仅日志文本差异，不是产品可见差异**。cel 的 `gem_make.out` 恒 `make -j8`（最后一次 `clean` 无 `-j`）；ref 侧 `date` 等为 plain `make`（实际回落 `-j1`）、`nio4r` 为 `make -j2`——task-194 记的 `make -j3` 不是本机本轮实测形态。make 调用序列与参数（除 `-jN`）两侧一致，产物集合一致；`.so` 字节差已由 gcc 版本串解释。严格隔离「同 gcc、不同 `-j`」的对照未做（见未验证）。
- 未验证：① 未用反假绿二进制 `celerite-pre204` 跑同一端到端（该二进制只用于差分夹具，本轮未跑；改动前行为由 task-194 记录，且本轮无实现改动）；② 未复跑 `celerite check` / `exec ruby`（task-194 已验，本轮未重验）；③ 未跑 `script/differential` 与全量 `crystal spec`（本任务只写文档，未改码）；④ 单次运行，未验证重复 `install` 的幂等与耗时稳定性；⑤ 未覆盖 Linux/其它 Ruby ABI；⑥ 未做「同 gcc、不同 `-j`」的隔离对照，`-j` 对 `.so` 零影响由版本串归因而非隔离实验；⑦ `Gem.pre_install` 钩子的代码行本轮未重验（沿用 task-199）。

### 判定

M7-9 的闭合判据是「未解释差异为零」而非「逐字节相等」。本轮复核：安装树集合级 4480/4480、`only_in_* = 0`；27 个内容差异全部归因为宿主工具链（14 个 `.so`）与日志文本（13 个构建日志）；`plugins`、`bin/*.bat` 已对齐；`binstubs rails` 三行文本两侧相同；锁未被改写。剩 3 类输出层差异（换行、顺序、进度点）均已归因。**建议 `docs/roadmap.md:149` 勾 `[x]`**，并在 claims 记一条终验断言（C-M7-9-009）承载上述差异；理由：判据要求「解释为零」且有意差异有记录，本轮两者都满足。仍需（非阻塞）的判据：把 rails 规模 install 的 stdout 顺序/换行纳入差分规则、补「同 gcc 不同 `-j`」对照、重复 install 幂等、Linux/其它 ABI。若首辅把「stdout 逐行同序」也视为产品契约，则应保持 `[ ]`，唯一拦路项是第 4 类顺序差异（需先定契约再改实现或加归一化规则）。
