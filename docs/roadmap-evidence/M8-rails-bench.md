# M8 / roadmap L166 — Rails 规模性能对照（Bundler + YJIT）

## 2026-11-24：task-241 实测报告

本报告只处理 `docs/roadmap.md:166` 的**后半句**——"为真实 Rails 规模冷/热/无变化运行建立性能对照，包含
Bundler + YJIT"。前半句"让 `check/list/show` 等只读命令复用已安装 gem 索引"由 task-228 以"会改报错
时机与退出码"为由否决，不在本报告范围。

对照口径按 `docs/roadmap.md:168` 的验收要求执行：报告必须同时给出 **wall / CPU / RSS、RPC 和 I/O**，
不能只给"加速 N 倍"。因此本报告不给单一倍数结论，只给分项数据与差异定性。

原始样本与逐次运行数据见 [`M8-rails-bench-samples.md`](M8-rails-bench-samples.md)；驱动见
`script/bench-m8`。

### 一、Oracle（本报告据什么判对错）

- **参考实现**：Ruby 4.0.6（`C:\Ruby40-x64\bin\ruby.exe`，x64-mingw-ucrt）+ bundler **4.0.24** 的
  `exe/bundle`，即 `C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\exe\bundle`。
- **输入**：`Gemfile` = `source "https://rubygems.org"` + `gem "rails", "8.0.2"`；参考侧解析出 **64 个
  gem** 并装成功。这是"真实 Rails 规模"的最小可复现替身——不是 Rails 应用骨架，而是 Rails 8.0.2 的
  完整传递依赖图（activesupport / nokogiri / bigdecimal / 各类 native 扩展在内）。
- **正确性判据**（性能对照同时看）：同一档位两侧的**退出码**、**stdout 首行**、**stdout 末行**是否一致。
  两侧不一致本身就是结论，不因"性能数字更好看"而被忽略。
- **性能判据**：`wall`、`CPU`（进程树 + 根进程）、峰值 `RSS`（进程树 + 根进程）、celerite 侧 RPC 计数、
  I/O。**I/O 本轮未采集**，理由见第五节。

### 二、参考锚点（这些数字落在什么坐标系里）

- 主机：`DESKTOP-IBMH65K`，11th Gen Intel Core i7-1165G7 @ 2.80 GHz（4 核 / 8 逻辑核），15.7 GiB RAM，
  Windows 10.0.26300。四核笔记本，绝对时间只对本机有效，**不可外推为产品性能承诺**。
- 三档 × 两侧，每档 **1 次预热丢弃 + ≥3 次计入**，报中位数与范围；`celerite` 的 `cold`/`cold-lock` 与
  `bundle` 的 `cold`/`hot`/`noop` 满足 n=3；`bundle` 的 `cold-lock` 只有 **n=1**（原因见第六节）。
- 冷档的"无已装 gem"用**全新 `BUNDLE_PATH` + 全新 `HOME`** 实现，**不清下载缓存**；因此冷档必然包含
  gem 下载时间，这一项无法与"解析 + 安装"分离到秒级——附加的 `cold-lock` 档（只 `lock`、不安装）就是
  为把解析成本单独量出来而加的。
- 参考量级（`bundle`，本机）：`cold` 中位 123.57 s、`hot`（`check`）0.971 s、`noop`（`install` 无变化）
  1.041 s；`cold-lock` 单次 34.91 s。即：**Rails 规模下"无变化 install"参考侧是 1 s 级，冷安装是百秒级**。

### 三、实现位置（被测物在哪）

| 侧 | 可执行文件 | 版本来源 |
| --- | --- | --- |
| celerite | 本工作树现编译的 `bin/celerite.exe`（13 199 572 字节） | `celerite --version` 末行 `4.0.24` |
| 参考 | `ruby.exe` + `bundler-4.0.24/exe/bundle` | `bundle --version` → `4.0.24` |

- RPC 计数的实现点：`src/celerite/bridge/client.cr:19`（`CELERITE_BRIDGE_STATS` 开关注释）与
  `src/celerite/bridge/client.cr:31`（`ENV["CELERITE_BRIDGE_STATS"]?`），开启后 stderr 打印
  `bridge: procs=… rpc=… req_bytes=… resp_bytes=…`。
- 安装失败码 5 的定义点：`src/celerite/cli/commands_install.cr:643-646`，注释指向 RubyGems 的
  `gem_installer.rb:38-49` 与 `parallel_installer.rb:198`（待安装 gem 失败路径）。
- 驱动：`script/bench-m8`（本任务新增）。口径：`--side celerite|bundle`、`--tiers cold,hot,noop`、
  `--runs N`、`--scratch`、`--out`、`--gemfile`、`--timeout`、`--poll-ms`、`--yjit`、`--help`；
  退出码 `0` 两侧全部一致、`1` 用法/缺可执行文件、`3` 某侧或某档不可用、`4` 两侧不一致。

### 四、证据（实测数字与两侧分歧）

汇总（中位数，范围见样本文件）：

| 侧 | 档 | n | wall (s) | CPU 树 (s) | 峰值 RSS 树 (KiB) | procs | rpc | exit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| celerite | cold | 3 | 257.11 | 129.98 | 462 256 | 1 | 312 | **5** |
| celerite | cold-lock | 3 | 144.87 | 85.64 | 232 480 | 1 | 4 | 0 |
| celerite | hot（参考树） | 3 | 0.927 | 0.234 | 36 000 | 1 | 2 | 0 |
| celerite | noop（参考树） | 3 | 136.52 | 135.64 | 235 440 | 1 | 72 | 0 |
| bundle | cold | 3 | 123.57 | 167.55 | 1 321 636 | - | - | 0 |
| bundle | cold-lock | 1 | 34.91 | 7.22 | 274 776 | - | - | 0 |
| bundle | hot | 3 | 0.971 | 0.234 | 23 444 | - | - | 0 |
| bundle | noop | 3 | 1.041 | 0.266 | 23 476 | - | - | 0 |

RPC 一列 `-` 表示**参考侧没有对应指标**（bundler 不暴露 RPC/字节计数），不是 0，也不是"没测"。

读数（不合并成倍数）：

1. **`cold` 两侧都不收敛，但原因不同。** `celerite` 三次全部 **exit 5**，stdout 停在
   `Installing bigdecimal 4.1.3 with native extensions`，stderr 为
   `An error occurred while installing bigdecimal (4.1.3), and Bundler cannot continue.`，并附
   `In Gemfile: rails was resolved to 8.0.2 → activesupport → bigdecimal`。同环境同 Gemfile 参考侧
   exit 0 装完 64 个 gem。**这是行为差异，不是环境不可用**：`celerite` 257 s 的花费里 312 次 RPC、
   约 102 KB 请求 / 437 KB 响应都已经做完，最后死在 native 扩展安装上。
2. **`cold` 的 wall 由网络主导。** 参考侧 `cold` 范围 123.42–135.04 s，另一次独立复跑 80.13 s、
   引导安装 112.73 s，波动 ±40 %。所以 `celerite` 与 `bundle` 的 cold wall 差（257 vs 124 s）**不能**
   直接读成解析或安装效率差；能读的是：`celerite` 的 `cold-lock`（只解析，144.87 s）本身就超过
   参考侧完整 `cold`（123.57 s），说明解析段是 celerite 的主成本，而参考侧解析段只有 34.91 s。
3. **CPU 与 wall 必须分开看。** `bundle cold-2` 的 CPU 树 678.36 s 对 wall 135.04 s —— native 扩展
   （bigdecimal）在 `BUNDLE_JOBS=4` 下多核并行编译，CPU 汇总远超墙钟。只报 wall 会把这类并行成本
   完全抹掉，这正是 L168 要 CPU 的原因。
4. **峰值 RSS 参考侧高得多。** `bundle cold` 峰值约 1.29–1.33 GiB，`celerite cold` 约 0.45–0.47 GiB；
   但 `celerite hot`（`check`）36 000 KiB 仍高于 `bundle hot` 23 444 KiB。RSS 的差距方向不一致，
   不能用一个数字总结。
5. **"无变化"档是最大分歧点。** 参考侧 `bundle install` 在无变化树上 **1.041 s** 收敛；`celerite install`
   在同一棵已装好的树上 **133–139 s / 72 次 RPC**，三次连续运行都重装而非收敛。这是本轮最该被
   后续切片处理的行为差异（它不在 task-241 的"性能对照"范围内，故只记录、不修）。
6. **只读路径两侧一致且都快。** `celerite check` 0.878–0.938 s / 2 次 RPC 对 `bundle check`
   0.906–1.105 s；两侧 stdout 都是同一句 `The Gemfile's dependencies are satisfied`。

正确性对照（同一档位两侧）：

| 档 | 退出码 | stdout 首行 | stdout 末行 | 判定 |
| --- | --- | --- | --- | --- |
| cold | celerite 5 / bundle 0 | 两侧同为 `Fetching gem metadata from https://rubygems.org/.` | celerite 停在失败点；bundle 为 `Bundled gems are installed into \`<run>\bundle\`` | **不一致** |
| hot | 两侧 0 | 两侧同为 `The Gemfile's dependencies are satisfied` | 同左 | 一致 |
| noop | 两侧 0 | 两侧同为 `Bundle complete! 1 Gemfile dependency, 64 gems now installed.` | 仅安装目录名不同 | 一致 |

比较前已把各自 scratch 运行目录折叠成 `<run>`，否则两侧永远"不同"而原因与行为无关。

### 五、已声明差异（口径上的诚实边界）

1. **I/O 未采集。** 本轮没有在进程树级别取块设备读写字节的手段（未上 ETW / Procmon），所以 L168 要求的
   "I/O"一项**空缺**，不是"测了相同"。补做思路写在第六节。
2. **RPC 只有 celerite 侧有。** `procs/rpc/req_bytes/resp_bytes` 来自 `CELERITE_BRIDGE_STATS`，参考侧
   bundler 无对应计数，表中以 `-` 标注。任何"RPC 更少所以更快"的推论都缺参考侧分母，本报告不作此推论。
3. **CPU 是两套口径并报。** 进程树 CPU（200 ms 轮询累加）会漏记短命子进程，根进程 CPU 只看根进程；
   两者都列，单独任一个都可能误导。
4. **峰值 RSS 是轮询峰值。** `Start-Process -PassThru` 在进程退出后常把 `PeakWorkingSet64` 报成 0，
   故以 200 ms 轮询峰值为主，可能低估瞬时尖峰。
5. **`celerite` 的 `hot`/`noop` 是补充样本，不是自建档。** 因为 `celerite install` 在 Rails 上失败、没有
   锁文件，这两个档在**参考侧装好的同一棵树上**测 celerite 的只读/无变化命令。树的内容（64 个 gem、
   同一 `Gemfile.lock`）一致，但"由谁安装"不同，属已声明差异。该组样本由一个临时包装脚本驱动驱动
   生成的 `measure.ps1` 采集，包装脚本的 TSV 列序有错位 bug，数值取自其逐次运行行与保留的
   `refhot-*.out/.err`；`bench-m8` 主流程样本不受影响。
6. **`bundle cold-lock` 只有 n=1。** 首次全量跑时该档在全新 `HOME` 下卡住超过 1200 s（stdout 停在
   `Resolving dependencies...`），我终止了该作业并限时复跑，复跑 34.91 s 正常完成，**该卡顿未能复现**，
   如实记录为"观察到一次未复现的长尾"。
7. **`celerite check` 存在页缓存漂移。** 同一棵树前 4 次 1.19–1.36 s，后 3 次 0.88–0.94 s；本报告取
   后 3 次并同时披露前 4 次。
8. **`script/bench-m8` 以 100644 入库。** 仓内其它 bash 驱动（`script/differential`、
   `script/upstream-specs`、`script/profile`）是 100755；本任务书禁止 amend，故不追改首笔提交，
   调用方式为 `bash script/bench-m8`（shebang 保留）。这是可在小后续里一行修掉的形式差异。
9. **`bin/celerite.exe` 依赖 MSYS2 UCRT64 运行库**（`libgc-1.dll`、`libssl-3-x64.dll`、
   `libcrypto-3-x64.dll`、`libpcre2-8-0.dll`、`libyaml-0-2.dll`、`zlib1.dll`、`libiconv-2.dll`）。
   缺目录时进程在 `main()` 前以 `0xC0000135` 退出且零输出，驱动加了 preflight 拒绝把这种失败记成
   "很快的样本"。

### 六、本轮未验证

- **YJIT 全部未验证（本机不可验证）。** `ruby -e 'p defined?(RubyVM::YJIT)'` 输出 `nil`，且
  `C:\Ruby40-x64\bin\ruby.exe` 自己打印
  `warning: Ruby was built without YJIT support. You may need to install rustc to build Ruby with YJIT.`
  因此没有任何 YJIT 样本，也无法判断 YJIT 对 `hot`/`noop` 的影响。补做需要：一个启用 YJIT 的 Ruby
  （官方 `--enable-yjit` 构建，或 Rust 工具链自建，或 Ruby ≥ 3.1 的 YJIT-enabled x64-mingw-ucrt 包），
  然后 `bash script/bench-m8 --yjit --tiers hot,noop`。驱动已实现该分支；不支持时打印
  `yjit: not sampled - …` 并以退出码 3 标为未采样。
- **I/O 未验证 / 未采集**：需要 ETW（`Microsoft-Windows-Kernel-File`）或 Procmon 按 pid 树归集，
  当前工具链没有这一步。
- **`celerite` 自建树的 `hot`/`noop` 未验证**：因 `install` 在 bigdecimal 4.1.3 上 exit 5，没有自建
  锁文件与已装 gem，只能在参考树的补充样本上测（见第五节第 5 条）。
- **`bundle cold-lock` 的 n=1 不足以给中位数**，该档结论只作参考；那次 >1200 s 卡顿未复现。
- **未测多轮交叉**（例如"先 celerite 后 bundle"与反序各 3 轮）以排除顺序偏差；本轮按侧串行。
- **未测 JDK/多 Ruby 版本、未测 `--jobs` 变化对 CPU 的影响**（`BUNDLE_JOBS=4` 固定）。
- **未做 CPU 亲和性固定与频率锁定**，笔记本的电源策略/热降频未受控，长跑（百秒级）样本含该噪声。

### 七、复现

```bash
export PATH=/usr/bin:/bin
cd /c/temp/celerite-t241
crystal build src/cli.cr -o bin/celerite.exe   # 需全新 CRYSTAL_CACHE_DIR/TMPDIR
bash script/bench-m8 --runs 3 \
  --scratch .tmp-scratch/bench-rails \
  --out .tmp-scratch/bench-rails/samples.tsv
```

不加参数时 `--help` 打印全部选项；退出码 `0/1/3/4` 含义见第三节。
