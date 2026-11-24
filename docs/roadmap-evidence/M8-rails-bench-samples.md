# M8 / roadmap L166 — Rails 规模性能对照：实测样本

本文件记录 `script/bench-m8` 在真实 Rails 规模依赖图上的原始样本与汇总。报告的判断见
[`M8-rails-bench.md`](M8-rails-bench.md)。

## 0. 为什么是 Markdown 表而不是 CSV

`docs/roadmap-evidence/` 下没有任何 CSV 文件（全部是 `.md`），仓内没有 CSV 惯例，所以按
task-241 任务书的备选分支，只落 Markdown 表，并把逐次原始样本一并列出（每行一次运行，不做
隐藏聚合）。原始 TSV 未入库：它落在 `--scratch` 下（`.tmp-scratch/` 已被 `.gitignore` 忽略），
重跑命令即可再生。

## 1. 采样环境

| 项 | 值 |
| --- | --- |
| 主机 | `DESKTOP-IBMH65K`，11th Gen Intel Core i7-1165G7 @ 2.80 GHz（4 核 / 8 逻辑核），15.7 GiB RAM，Windows 10.0.26300 |
| 采样日期 | 2026-11-24（Asia/Shanghai，UTC+8） |
| celerite | 本工作树 `7ea8333` 现编译的 `bin/celerite.exe`（13 199 572 字节，`--version` → `4.0.24`） |
| 参考侧 | `C:\Ruby40-x64\bin\ruby.exe`（Ruby 4.0.6，`x64-mingw-ucrt`）+ `bundler-4.0.24` 的 `exe/bundle` |
| Bundler 版本 | 4.0.24（`bundle --version`） |
| Gemfile | `source "https://rubygems.org"` + `gem "rails", "8.0.2"`，解析出 **64 个 gem**，`Gemfile.lock` 由两侧各自生成 |
| 网络 | `SSL_CERT_FILE=C:/msys64/usr/ssl/cert.pem`，rubygems.org 可达 |
| YJIT | **本机不可验证**：Ruby 4.0.6 编译时未带 YJIT（见 §5） |

隔离：每次运行独占 `--scratch` 下一个目录，内含自己的 `HOME`/`USERPROFILE`、`BUNDLE_PATH`、
`BUNDLE_APP_CONFIG`、`TMPDIR`/`TMP`/`TEMP`；不读写用户真实 `~/.bundle` 或系统 gem home。
`PATH` 同时提供 MSYS2 `ucrt64/bin`（见 §6 的 DLL 依赖）与 `C:\Ruby40-x64\bin`。

## 2. 度量定义与精度

| 指标 | 采集方式 | 精度 / 局限 |
| --- | --- | --- |
| wall | PowerShell `[Diagnostics.Stopwatch]`，包住 `Start-Process`→`WaitForExit` | 100 ns tick；含进程创建与解释器启动 |
| CPU（进程树） | 每 `--poll-ms`（默认 200 ms）`Get-CimInstance Win32_Process` 取 `KernelModeTime+UserModeTime`，对整棵后代树逐 pid 取最大值后求和 | 100 ns tick，但受 200 ms 轮询粒度限制；短命子进程可能漏记 |
| CPU（根进程） | `Process.TotalProcessorTime` | 精确到内核记账，但只含根进程（celerite 的 ruby 桥、bundle 的子进程不在内） |
| 峰值 RSS（进程树） | 轮询 `WorkingSetSize` 求和取峰值 | 200 ms 粒度，**可能漏掉瞬时尖峰** |
| 峰值 RSS（根进程） | 轮询峰值，辅以 `PeakWorkingSet64` | `Start-Process -PassThru` 在进程退出后常把 `PeakWorkingSet64` 报成 0，故以轮询峰值为主 |
| RPC 计数 | 仅 celerite：`CELERITE_BRIDGE_STATS=1` 时 stderr 打印 `bridge: procs=… rpc=… req_bytes=… resp_bytes=…`（`src/celerite/bridge/client.cr:19,31`） | **参考侧没有对应物**，表中 `-` 表示"无此指标"，不是 0 |
| I/O | **未采集** | 本机没有在进程树级别取块设备读写字节的现成手段（未用 ETW/Procmon），如实留空 |

## 3. 分档定义与实测

档位（三档 × 两侧，均由同一驱动执行，命令两侧完全相同）：

- `cold` — 无锁文件、`vendor/cache` 不存在、无已装 gem：每次运行一个全新 `BUNDLE_PATH` + 全新 `HOME`，命令 `install`。
- `cold-lock` — 附加档，仅为拆分 `cold` 的成本：同样全新 `HOME`/`BUNDLE_PATH`，只跑 `lock`（解析 + 写锁文件，不下载安装 gem）。
- `hot` — 有锁 + 已装 gem，只读命令 `check`。
- `noop` — 有锁 + 已装 gem，命令 `install`（无变化）。

每档先跑 1 次预热并丢弃，再记 n 次；下表"中位数 [范围]"按 n 次计算。

### 3.1 汇总

| 侧 | 档 | n | wall (s) 中位数 [范围] | CPU 树 (s) | 峰值 RSS 树 (KiB) | procs | rpc | exit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| celerite | cold | 3 | 257.11 [248.13..270.47] | 129.98 | 462 256 | 1 | 312 | **5** |
| celerite | cold-lock | 3 | 144.87 [144.64..145.74] | 85.64 | 232 480 | 1 | 4 | 0 |
| celerite | hot（参考侧装的树） | 3 | 0.927 [0.878..0.938] | 0.234 | 36 000 | 1 | 2 | 0 |
| celerite | noop（参考侧装的树） | 3 | 136.52 [133.22..139.10] | 135.64 | 235 440 | 1 | 72 | 0 |
| bundle | cold | 3 | 123.57 [123.42..135.04] | 167.55 | 1 321 636 | - | - | 0 |
| bundle | cold-lock | 1 | 34.91 [34.91..34.91] | 7.22 | 274 776 | - | - | 0 |
| bundle | hot | 3 | 0.971 [0.906..1.105] | 0.234 | 23 444 | - | - | 0 |
| bundle | noop | 3 | 1.041 [0.949..1.528] | 0.266 | 23 476 | - | - | 0 |

`celerite` 的 `hot`/`noop` 无法用自建树测量：`celerite install` 在 Rails 8.0.2 上直接失败（§3.3），
没有锁文件。上表这两行是在**参考侧装好的同一棵树上**跑的，属补充样本，明细见 §3.4。

补充：`bundle cold` 的波动面很大（另有一次单独的 `--timeout 240` 复跑为 80.13 s，bootstrap 安装为
112.73 s），说明 `cold` 的 wall 由网络下载主导，不是稳态指标。

### 3.2 逐次原始样本（未聚合）

`celerite`（自建树，`install`/`lock`）：

| 档 | label | exit | wall (s) | CPU 树 (s) | CPU 根 (s) | RSS 树 (KiB) | RSS 根 (KiB) | procs | rpc | req_bytes | resp_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| cold | cold-1 | 5 | 270.474 | 136.766 | 1.688 | 470 724 | - | 1 | 312 | 102 257 | 436 771 |
| cold | cold-2 | 5 | 257.105 | 124.609 | - | 462 256 | - | 1 | 312 | 102 275 | 436 763 |
| cold | cold-3 | 5 | 248.126 | 129.984 | - | 451 780 | - | 1 | 312 | 102 137 | 436 771 |
| cold-lock | cold-lock-1 | 0 | 144.644 | 87.109 | - | 206 376 | - | 1 | 4 | 372 | 286 789 |
| cold-lock | cold-lock-2 | 0 | 145.736 | 85.641 | - | 232 480 | - | 1 | 4 | 372 | 286 789 |
| cold-lock | cold-lock-3 | 0 | 144.870 | 83.656 | - | 257 216 | - | 1 | 4 | 372 | 286 789 |

`bundle`（参考侧）：

| 档 | label | exit | wall (s) | CPU 树 (s) | CPU 根 (s) | RSS 树 (KiB) | procs | rpc |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| cold | cold-1 | 0 | 123.571 | 167.547 | 1.672 | 1 329 780 | - | - |
| cold | cold-2 | 0 | 135.044 | 678.359 | 1.766 | 1 321 636 | - | - |
| cold | cold-3 | 0 | 123.422 | 163.906 | 1.641 | 1 285 324 | - | - |
| hot | hot-1 | 0 | 0.906 | 0.234 | 0.063 | 23 404 | - | - |
| hot | hot-2 | 0 | 1.105 | 0.297 | 0.078 | 23 444 | - | - |
| hot | hot-3 | 0 | 0.971 | 0.234 | 0.063 | 23 460 | - | - |
| noop | noop-1 | 0 | 1.528 | 0.813 | 0.078 | 39 104 | - | - |
| noop | noop-2 | 0 | 1.041 | 0.266 | 0.063 | 23 428 | - | - |
| noop | noop-3 | 0 | 0.949 | 0.234 | 0.047 | 23 476 | - | - |

`bundle cold` 的 `cold-2` CPU 树 678.359 s 是离群值：该次运行包含 native 扩展（bigdecimal）并行
编译，`BUNDLE_JOBS=4` 下多核并行使 CPU 汇总远超 wall。这正是"CPU 与 wall 必须分开看"的例子。

### 3.3 `celerite` 在 Rails 规模上的 `install` 失败

`celerite cold` 三次全部 **exit 5**，stdout 停在最后一行：

```
Installing bigdecimal 4.1.3 with native extensions
```

stderr：

```
An error occurred while installing bigdecimal (4.1.3), and Bundler cannot
continue.

In Gemfile:
  rails was resolved to 8.0.2, which depends on
    activesupport was resolved to 8.0.2, which depends on
      bigdecimal
bridge: procs=1 rpc=312 req_bytes=102275 resp_bytes=436763
```

exit 5 是 celerite 的安装失败码（`src/celerite/cli/commands_install.cr:643-646` 注释说明该码对齐
RubyGems 的待安装 gem 失败路径 `gem_installer.rb:38-49`、`parallel_installer.rb:198`）。同一
Gemfile 同一环境下参考侧 `install` 成功（exit 0，64 个 gem 装完），故这是**两侧行为差异**，不是
环境不可用。因为失败发生在写锁文件之前，`celerite` 没有任何锁文件，`hot`/`noop` 自建档因此不可得。

### 3.4 补充样本：`celerite` 在参考侧装好的树上跑 `check` / `install`

为了不把"celerite 装不了"变成"celerite 的只读命令无从测量"，用同一个测量助手
（`bench-m8` 生成的 `measure.ps1`）在 `bundle` 侧装好的树上补测 `celerite check` 与 `celerite install`。

`celerite check`（`BUNDLE_PATH` 指向参考侧已装 64 个 gem 的目录）：

| label | exit | wall (s) | CPU 树 (s) | CPU 根 (s) | RSS 树 (KiB) | procs | rpc | req_bytes | resp_bytes | stdout |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hot-4 | 0 | 0.878 | 0.203 | 0.047 | 35 612 | 1 | 2 | 227 | 2 538 | `The Gemfile's dependencies are satisfied` |
| hot-5 | 0 | 0.927 | 0.266 | 0.094 | 36 180 | 1 | 2 | 227 | 2 538 | 同上 |
| hot-6 | 0 | 0.938 | 0.234 | 0.063 | 36 000 | 1 | 2 | 227 | 2 538 | 同上 |

同一棵树上更早取的 4 次（含预热）为 1.359 / 1.251 / 1.191 / 1.252 s，比后 3 次慢，属页缓存未热
的漂移；上表取后 3 次，报告同时给出这组漂移。

`celerite install`（同一棵已装好、无变化的树）：

| label | exit | wall (s) | CPU 树 (s) | RSS 树 (KiB) | procs | rpc | req_bytes | resp_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| noop-ref1 | 0 | 139.097 | 138.484 | 189 864 | 1 | 72 | 23 038 | 292 926 |
| noop-ref2 | 0 | 136.522 | 135.641 | 235 440 | 1 | 72 | 23 038 | 292 926 |
| noop-ref3 | 0 | 133.224 | 132.984 | 265 032 | 1 | 72 | 23 038 | 292 926 |

补充样本的取证方式说明：这组样本由一个临时包装脚本驱动同一个 `measure.ps1`，其 TSV 输出列序有
错位（包装脚本的格式化 bug），因此本表数值取自该包装脚本逐次打印的运行行与保留下来的
`refhot-*.out/.err`；`bench-m8` 主流程的样本不受影响。

## 4. 两侧正确性（退出码与 stdout 首末行）

| 档 | 退出码 | stdout 首行 | stdout 末行 | 结论 |
| --- | --- | --- | --- | --- |
| cold | celerite 5 / bundle 0 | 两侧同为 `Fetching gem metadata from https://rubygems.org/.` | celerite 停在失败点，bundle 为 `Bundled gems are installed into \`<run>\bundle\`` | **不一致（本轮最重要的发现）** |
| hot | 两侧 0 | 两侧同为 `The Gemfile's dependencies are satisfied` | 同左（单行输出） | 一致 |
| noop | 两侧 0 | 两侧同为 `Bundle complete! 1 Gemfile dependency, 64 gems now installed.` | 两侧都是 `Bundled gems are installed into \`…\``，仅目录名不同（`<run>` vs 种子目录） | 一致（末行的差异只是安装目录名） |

比较前已把各自 scratch 运行目录替换成 `<run>`，否则两侧永远"不同"而原因与行为无关。

`hot`/`noop` 的 celerite 数据来自 §3.4 的补充样本；其 stdout 与参考侧逐字相同（41 字节、同一句），
故"一致"结论成立。

## 5. YJIT 探测

```
$ ruby -e 'p defined?(RubyVM::YJIT)'
C:\Ruby40-x64\bin\ruby.exe: warning: Ruby was built without YJIT support.
  You may need to install rustc to build Ruby with YJIT.
nil
```

`RubyVM::YJIT` 未定义，`RUBY_YJIT_ENABLE=1` 也无从生效。**本机不可验证**，因此没有任何
YJIT 样本；补做需要的环境：一个启用 YJIT 的 Ruby（官方 `--enable-yjit` 构建或 Rust 工具链自建，
Ruby ≥ 3.1 的 x64-mingw-ucrt 包亦可）。驱动已实现 `--yjit`：在支持的主机上为 `hot`/`noop` 追加
`RUBY_YJIT_ENABLE=1` 的一组样本，不支持时打印 `yjit: not sampled - …` 并以退出码 3 明确标为未采样。

## 6. 复现命令

```bash
export PATH=/usr/bin:/bin                     # 驱动内部会把 PATH 译成 Windows 形式并补 ucrt64/bin
cd /c/temp/celerite-t241
crystal build src/cli.cr -o bin/celerite.exe  # 需全新 CRYSTAL_CACHE_DIR/TMPDIR（见 M8 记录）
bash script/bench-m8 --runs 3 \
  --scratch .tmp-scratch/bench-rails \
  --out .tmp-scratch/bench-rails/samples.tsv
```

单侧/单档：

```bash
bash script/bench-m8 --side bundle --tiers hot,noop --runs 3 \
  --scratch .tmp-scratch/bench-rails --out .tmp-scratch/bench-rails/hot-noop.tsv
```

`bin/celerite.exe` 依赖 MSYS2 UCRT64 运行库（`libgc-1.dll`、`libssl-3-x64.dll`、
`libcrypto-3-x64.dll`、`libpcre2-8-0.dll`、`libyaml-0-2.dll`、`zlib1.dll`、`libiconv-2.dll`）；
`objdump -p bin/celerite.exe` 可见这些导入。缺任一目录时进程在 `main()` 前以 `0xC0000135`
退出且不打印任何东西，驱动为此加了 preflight，拒绝把这种失败记成"很快的样本"。
