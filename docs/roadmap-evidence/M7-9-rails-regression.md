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
