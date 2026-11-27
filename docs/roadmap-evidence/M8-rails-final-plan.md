# M8 L166 Rails 8.0.2 最终基准执行方案（task-279）

## 1. 状态与边界

- 状态：**只读设计，未执行基准，未取得 CI 结果**。
- 产品基线：`0215cd0b29ceaae342b5ec8e86b3138b7cc05557`。最终执行时，`baseline_sha` 必须是首辅批准的不可变完整提交，包含待测产品代码、基准驱动和本方案对应的 workflow；不得使用移动的 `main`。
- 本方案只覆盖 `docs/roadmap.md:166` 的 Rails 8.0.2 cold/hot/noop 对照与 `docs/roadmap.md:168` 的 wall/CPU/RSS/RPC/IO 证据要求。它不证明 L166 的零 Ruby、指纹失效或缓存一致性条件，也不单独关闭 L168。
- task-279 不运行 Crystal、build、spec、differential、Rails 或长命令；只写本文件并做一笔提交，不 push。
- 本机 Windows/Ruby 4.0.6 无 YJIT 的旧结果只能作为历史环境记录，不能作为本方案的 YJIT 结果。CI YJIT 结果必须来自本方案门禁通过的当前 run artifact。

## 2. 已核实的审计依据

### 2.1 路线图要求

- `docs/roadmap.md:166`：真实 Rails 规模冷/热/无变化运行必须建立性能对照，包含 Bundler + YJIT。
- `docs/roadmap.md:168`：验收不只看加速比，还必须报告 wall、CPU、RSS、RPC 和 IO。
- `docs/roadmap-evidence/M8-rails-bench.md:176-185` 明确把 task-255 标为 “PROCESS DATA, NOT for L166”，且最终 job 已停止；其旧基线、旧进程数和被覆盖的 IO TSV 均不得进入最终报告。

### 2.2 现有驱动可复用部分

`script/bench-m8` 已具备：

- 两侧：`celerite` 与固定 Bundler `4.0.24` 的 `bundle`（`script/bench-m8:4-13`）。
- 三档：cold 安装、hot `check`、noop `install`（`script/bench-m8:4-13`）。
- Rails 默认版本 `8.0.2`，默认 `RUNS=3`、`WARMUP=1`、`JOBS=4`、`TIMEOUT_S=1200`（`script/bench-m8:61-75`）。
- 每样本 stdout/stderr、退出码、wall、CPU、RSS、Windows IO、桥 `procs/rpc/req_bytes/resp_bytes`、lock SHA 和 gemspec manifest（`script/bench-m8:14-20,265-278,617-668`）。
- 冷/热 scratch 隔离与已安装种子复用（`script/bench-m8:670-690,717-775`）。
- YJIT 能力探针：先检查 `RubyVM::YJIT`，再以 `RUBY_YJIT_ENABLE=1` 检查 `RubyVM::YJIT.enabled?`；不支持时退出 3（`script/bench-m8:245-286`）。

### 2.3 现有驱动不能直接作为 Linux 最终门禁

- POSIX 路径只用 `/usr/bin/time` 取根进程 `%e/%U/%S/%M`，没有进程树 CPU/RSS、没有 IO、没有超时执行；`TIMEOUT_S` 只传给 Windows helper（`script/bench-m8:569-591`）。
- Windows helper 的 200 ms 轮询会漏掉短命子进程和 RSS 峰值，IO 也可能为空（`script/bench-m8:291-529`）。空值必须保留为缺失，不能写成 0。
- `--yjit` 只增加 `hot-yjit` 和 `noop-yjit`，没有 `cold-yjit`；且 YJIT 环境也会传给 celerite 侧，实际只可能影响 Ruby 桥，不会让 Crystal 核心变成 YJIT（`script/bench-m8:777-857`）。
- POSIX 默认 Ruby/Bundler 仍是 Windows 绝对路径，`SSL_CERT_FILE` 也硬编码为 Windows 路径；CI 必须显式覆盖（`script/bench-m8:190-200,670-690`）。
- 当前汇总的 IO 只覆盖普通 cold/hot/noop，不含 cold-lock/YJIT 行（`script/bench-m8:859-947`）。
- 旧实测出现过 celerite 65 specs、bundle 64 specs，manifest 不一致；最终门禁必须解释并规范化差异，不能直接宣称 parity（`docs/roadmap-evidence/M8-rails-bench.md:176-185`）。

## 3. GitHub Actions + ruby/setup-ruby + YJIT 可行性裁定

**结论：workflow_dispatch 在 Ubuntu 上执行基准可行；YJIT-capable Ruby 的存在性必须在 run 内证明，当前不能视为已验证。**

依据：

- 仓库已有 `workflow_dispatch` 先例：`.github/workflows/fast-path-gates.yml:3-6`、`.github/workflows/release.yml:3-6`。
- 仓库已有 Ubuntu、`ruby/setup-ruby@v1`、Ruby `4.0`、Bundler `4.0.24` 和 artifact 上传先例：`.github/workflows/ci.yml:10-31,71-74`。
- [ruby/setup-ruby README](https://raw.githubusercontent.com/ruby/setup-ruby/master/README.md) 说明它可安装预编译 MRI，支持 Ubuntu 22.04/24.04/26.04，也支持 ruby-builder 源码构建；README 本身不保证所选 Ruby 编译进 YJIT。
- [ruby-build issue #1970](https://github.com/rbenv/ruby-build/issues/1970) 说明 CRuby 默认构建可能不含 YJIT，需要 `--enable-yjit`。因此不能因 action 安装成功就宣称 YJIT 可用。
- YJIT 最终判据只能是 run 内输出：`defined?(RubyVM::YJIT)` 为真，且 `RUBY_YJIT_ENABLE=1 ruby -e 'abort unless RubyVM::YJIT.enabled?'` 退出 0；同时保存 `ruby -v`、`RbConfig::CONFIG` 和 YJIT 探针输出。

执行规则：

1. `ruby-version` 默认固定为 `4.0.6`，与历史本机版本对齐；若 setup-ruby 的该预编译包不含 YJIT，run 直接失败，不得自动降级为无 YJIT。
2. 若必须回退到源码构建，只能作为单独获批的 driver 变更：安装 Rust，使用 `ruby-build` 并显式传 `--enable-yjit`，记录 ruby-build commit、Rust 版本和 configure 参数；不能在最终 run 中静默切换。
3. workflow 只跑一个串行 benchmark job，禁止多个 benchmark job 争用同一 runner 的 CPU/磁盘/网络。
4. 不启用 `bundler-cache`，不让 action 预装 Rails；否则 cold 不再 cold。

## 4. 最终矩阵

主矩阵为 **2 侧 × 3 档 × 2 Ruby 模式 = 12 个单元**。每个单元 `warmup=1`、`n=5`，warmup 单独保存但不进入统计。

| side | Ruby 模式 | cold | hot | noop | 含义 |
|---|---|---:|---:|---:|---|
| celerite | off | ✓ | ✓ | ✓ | Crystal 核心；桥 Ruby 不启用 YJIT |
| celerite | on | ✓ | ✓ | ✓ | Crystal 核心不变；仅验证 Ruby 桥/显式 Ruby 执行边界继承 YJIT |
| bundle | off | ✓ | ✓ | ✓ | Bundler 4.0.24 基线，不启用 YJIT |
| bundle | on | ✓ | ✓ | ✓ | Bundler 4.0.24 + YJIT，满足 L166 的 Bundler + YJIT 对照 |

解释约束：

- `celerite-off` 对 `bundle-off` 是产品对照。
- `bundle-off` 对 `bundle-on` 是 Ruby/Bundler 的 YJIT 效应。
- `celerite-off` 对 `celerite-on` 只是桥 Ruby 效应；**不得**把 `celerite-on` 对 `bundle-on` 解释为 Crystal 对 Ruby 的纯语言加速比。
- celerite 的 `procs/rpc/req_bytes/resp_bytes` 必须是数值；bundle 侧明确记 `N/A`，不得伪造 0。
- `cold-lock` 只能作为额外诊断矩阵，不能替代 cold，也不能混入 12 单元主汇总。

## 5. 输入、lock 与安装树 parity

### 5.1 固定输入

在未计时的 setup 阶段生成一次参考 lock：

```text
source "https://rubygems.org"

gem "rails", "8.0.2"
```

- 只用 Bundler `4.0.24` 和选定 Ruby `4.0.6` 生成 `Gemfile.lock`；保存 Gemfile、lock 原文和 SHA-256。
- 所有 cold/hot/noop 单元复制同一 Gemfile 和同一 lock。cold 使用全新 `HOME`、`BUNDLE_PATH`、`BUNDLE_APP_CONFIG`、`TMP` 和用户 gem cache；不得复用其他样本的安装树。
- 每个样本运行后重新计算 lock SHA。任何 lock 变化都使该单元失败。
- hot/noop 的种子安装也不得改 lock；种子只在该 side/mode/tier 内复用。

### 5.2 parity 门禁

每个样本同时保存：

- `lock_sha256`；
- 已安装 specifications 的原始清单：相对路径、文件名和文件内容 SHA-256；
- 排序后的 `gemspec_manifest_sha256`；
- 原始 spec 数量与规范化后数量。

两侧比较规则：

1. lock SHA 必须完全相同。
2. stdout 只在规范化 scratch 绝对路径后比较；退出码必须同为预期值。
3. gemspec manifest 先按相同排序、相同路径规范化比较。
4. 若 oracle 工具自身 spec（例如 Bundler）造成差异，必须输出精确 diff，并只允许一个**显式、双侧同规则**的排除项；原始与规范化结果都要保留。任何额外应用 gem 差异、版本差异或内容差异均失败。
5. parity 失败时不得汇总时延，也不得把某一侧从最终表删除后宣布通过。

## 6. CI workflow 设计（待实施，不在 task-279 创建）

建议新增 `.github/workflows/m8-rails-final.yml`，要点如下：

```yaml
on:
  workflow_dispatch:
    inputs:
      baseline_sha:
        required: true
      mode:
        type: choice
        options: [smoke, full]
        default: full
      runs:
        default: "5"
      warmup:
        default: "1"

permissions:
  contents: read

jobs:
  rails-final:
    runs-on: ubuntu-24.04
    timeout-minutes: 180
```

执行步骤：

1. `actions/checkout@v4` 检出 `inputs.baseline_sha`，立即断言 `git rev-parse HEAD` 完全等于输入，且工作树干净。
2. `crystal-lang/install-crystal@v1` 固定 Crystal `1.22.1`；`ruby/setup-ruby@v1` 固定 Ruby `4.0.6`。
3. `gem install bundler -v 4.0.24 --no-document`，断言 `bundle _4.0.24_ --version`。
4. 导出 `CELERITE_BRIDGE_SERVER`、`CELERITE_REFERENCE_BUNDLER_LIB`、`CELERITE_PROFILE_BUNDLER_VERSION=4.0.24`，方式沿用 `.github/workflows/ci.yml:24-28`。
5. 运行 YJIT 能力探针；失败即终止，不进入采样。
6. 从同一 baseline 构建一次 `bin/celerite`，记录二进制 SHA-256。不得使用 release artifact 或旧 worktree 的二进制。
7. 生成参考 lock，记录其 SHA；调用扩展后的 Linux 驱动，显式传 `--celerite`、`--ruby`、`--bundle-exe`、`--scratch`、`--out`、`--jobs 4`、`--runs`、`--warmup` 和逐档 timeout。
8. 先跑 validator，再生成 summary；validator 失败时 workflow 失败。
9. `actions/upload-artifact@v4` 使用 `if: always()`，上传原始证据、失败日志和 manifest。

未来 driver 必须增加的接口能力：

- 明确的 `--ruby-mode off|on`，对 cold/hot/noop 都生效，并在每行记录 requested/compiled/enabled 三个 YJIT 状态。
- Linux 进程树 CPU/RSS/IO collector 与真实 timeout/process-group kill。
- 按 round 交错两侧顺序，而不是先跑完 celerite 再跑 bundle。
- 每单元独立 raw 输出与 validator；汇总只能消费当前 run 的 validated rows。

## 7. Linux 测量契约

### 7.1 必采指标

每个 measured row 至少包含：

- wall：单调时钟的进程组存活时间；
- CPU：root 与进程树 user/system CPU 秒；
- RSS：root exact peak working set 与进程树采样 peak；
- IO：root 与进程树 read/write/syscall 的 bytes 和 operations；
- RPC：celerite 桥的 `procs/rpc/req_bytes/resp_bytes`，bundle 为 `N/A`；
- exit/status、stdout/stderr bytes、timeout 标志；
- side、tier、Ruby mode、round、sample_id、start/end UTC、command、scratch id；
- lock SHA、raw/normalized gemspec manifest SHA 和 count。

### 7.2 collector 实现要求

- 用 pid + `/proc/<pid>/stat` starttime 作为进程身份，避免 pid 复用误累计。
- 每个样本新建 process group/session；timeout 到期后 kill 整个组并等待 reap，记录 `timed_out=true`，不得把超时当成有效快样本。
- root exact CPU/RSS 可用 `wait4`/`getrusage` 或 `/usr/bin/time`；树指标从 `/proc` 的 `stat`、`status`、`io`、`task/*/children` 采集。
- 采样周期默认 20 ms，可配置但必须写入 manifest。树 CPU 对已观察进程使用累计值最大值，RSS 使用同一采样时刻的树和，避免把不同生命周期的峰值错误相加。
- `/proc` 轮询可能漏掉短命子进程。若使用 cgroup v2 隔离，则记录 cgroup 路径和 `io.stat`/`memory.peak`/`cpu.stat`；若 runner 无 cgroup 委托权限，明确记录 collector 类型与覆盖范围。
- run 前执行 collector self-test：启动已知会创建子进程并做 read/write 的 fixture，断言 CPU/RSS/IO 非空且树计数大于 root。self-test 失败则最终矩阵不启动。
- 任何指标缺失写空值并标 `incomplete`；不得以 0 代替。最终 L168 验收要求完整树 IO，因此 `incomplete` 行不能通过最终门禁。

### 7.3 超时与采样参数

- cold：`timeout=1800 s`；hot/noop：`timeout=120 s`。这些是初值，若 smoke 显示系统性超时必须先调查，不得通过调大 timeout 掩盖挂起。
- `warmup=1`，`n=5`。每个样本独立计时；warmup 的 stdout/stderr 可保留，但不得进入 median/range。
- `JOBS=4` 固定。记录 `nproc`、CPU model、runner OS、kernel、允许 CPU 列表；所有单元使用相同 allowed CPU set。
- 同一 round 内交错 `celerite/bundle`，奇偶 round 反转顺序。不同 Ruby mode 也记录实际执行顺序。
- cold 包含真实 gem 下载和本机 page-cache 状态；hosted runner 不宣称可稳定清空宿主 page cache。cold 结果必须与 hot/noop 分开解释，不能当作纯 CPU 数字。
- 全流程一个 job 串行，禁止并发 benchmark job；不执行会污染磁盘/网络的无关测试。

## 8. Artifact 契约

artifact 名必须包含当前 `github.run_id`、`github.run_attempt` 和完整 `baseline_sha`，例如：

```text
m8-rails-final-<run_id>-<attempt>-<baseline_sha>
```

目录结构：

```text
manifest.json
commands.txt
validator.txt
summary.tsv
summary.json
samples.jsonl
samples.tsv
raw/<side>/<ruby-mode>/<tier>/<round>/<sample-id>/
  stdout.txt
  stderr.txt
  exit.txt
  lock/Gemfile
  lock/Gemfile.lock
  gemspecs.tsv
  metrics.json
warmup/<side>/<ruby-mode>/<tier>/...
logs/driver.log
logs/yjit-probe.txt
logs/collector-self-test.txt
checksums.sha256
```

`manifest.json` 必填：

- run id/attempt、baseline SHA、workflow ref/SHA、driver SHA；
- celerite binary SHA、Ruby `RUBY_VERSION`/`RbConfig::CONFIG`、YJIT compiled/requested/enabled；
- Bundler 4.0.24、Crystal 版本、Ubuntu/kernel/CPU/affinity；
- Gemfile/lock SHA、warmup/n/JOBS/timeout/poll interval；
- 每单元开始/结束时间、实际 side 顺序、collector 类型与覆盖范围；
- 不含 token、密码或私有环境变量；环境清单只记录安全键名和非敏感值。

上传规则：

- `if: always()`；即使 YJIT 探针、build、collector self-test 或 validator 失败，也上传已产生的日志。
- artifact 只属于当前 run attempt。禁止把旧 task-241/255 artifact 下载后并入当前 `samples.tsv`。
- summary 生成器只接受带当前 run id + baseline SHA + 完整 12 单元计数的 validated artifact。
- 最终报告引用 artifact 名、run id、baseline SHA 和 `checksums.sha256`；旧文档数字只能放在“历史背景”，不得进入最终对照表。

## 9. 最终验收门禁

全部满足才算可交付最终 Rails 矩阵：

1. `git rev-parse HEAD == inputs.baseline_sha`，baseline 是获批的完整不可变提交。
2. Ruby 精确为 `4.0.6`，Bundler 精确为 `4.0.24`，Crystal 版本已记录。
3. YJIT-on 单元探针为 true；YJIT-off 单元实际 enabled 为 false。探针失败不得降级。
4. 12 个主单元齐全；每单元 measured rows 恰好 `n=5`，warmup 不混入。
5. 无 missing executable、DLL/loader failure、timeout、collector incomplete 或 unexpected exit。
6. wall/CPU/RSS/IO 完整；bundle 的 RPC 为 `N/A`，celerite 的 RPC 为数值。
7. 每样本 lock SHA 相同；stdout/exit 一致；gemspec 原始与规范化 diff 已审查且通过。
8. raw、logs、manifest、validator、summary 和 checksums 齐全；artifact 名与 manifest 的 run/baseline 完全一致。
9. 最终报告只使用本次 validated rows，明确区分本机 Windows 无 YJIT 历史与 Ubuntu CI YJIT 结果。
10. 本方案本身不关闭 L166/L168；只有未来 CI run 通过上述门禁并另附结果报告，才可提请首辅验收。

## 10. 最小切片与推进顺序

### Slice A：能力探针，不做性能结论

- Ubuntu 24.04 + Ruby 4.0.6 + Bundler 4.0.24。
- 只运行 YJIT compiled/enabled 探针、collector self-test 和 binary SHA 记录。
- 产出：probe/self-test/manifest。任一失败即停止，证明当前 setup-ruby 路径或 collector 不可用。

### Slice B：无变化的 Linux 冒烟

- 两侧 × hot/noop × YJIT off/on，`warmup=1`、`n=1`。
- 验证 cold 之外的 scratch、lock parity、RPC、POSIX 指标、timeout 和 artifact 上传。
- 产出只能标 `smoke`，不得写成最终性能结论。

### Slice C：完整矩阵

- Slice A/B 通过后，实施 cold-yjit、交错顺序和 Linux collector。
- 跑 12 单元，`warmup=1`、`n=5`，执行 validator，生成最终 summary。
- 只有 Slice C 的 validated artifact 可进入 L166/L168 结果报告。

## 11. 当前未验证项

- setup-ruby 的 Ruby 4.0.6 Ubuntu 预编译包是否实际包含 YJIT；本任务没有触发 workflow。
- Linux 进程树 collector 的短命子进程覆盖、cgroup 权限和 IO 精度。
- 当前 `0215cd0` 在 Ubuntu 上构建、Rails 8.0.2 cold 安装及 native extension 行为。
- cold-yjit 驱动扩展、交错采样和真实 POSIX timeout 尚未实现。
- 两侧 gemspec 差异的精确内容与可接受规范化规则；旧 65/64 只说明必须调查，不证明应排除哪一项。
- YJIT 环境是否按预期传入 celerite 的 Ruby 桥。
- CI cold 网络时延、runner 噪声、affinity 与最终 wall/CPU/RSS/RPC/IO 数值。
- 因而不存在本任务可报告的最终 Rails/YJIT 性能结果。

## 12. 外部参考

- [ruby/setup-ruby README](https://raw.githubusercontent.com/ruby/setup-ruby/master/README.md)
- [ruby-build issue #1970：YJIT 需要显式构建支持](https://github.com/rbenv/ruby-build/issues/1970)
- [Ruby 4.0 YJIT 文档镜像](https://docs.ruby-lang.cn/en/4.0/jit/yjit_md.html)
