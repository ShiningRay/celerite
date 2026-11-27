# M8 L164 剩余缺口实施设计

- 任务：task-271，只读设计；本文不改 `src/`、`spec/`、claims、roadmap 复选框、compat-report、证据总表或甘特图。
- 基线：`d9009b14a0bf18da62b7a85cfc68b2442c4446de`（task-271 detached worktree）。
- 设计输入：task-268 闭合审计、M8 原始快路径计划、当前 lock/install/runtime/eval 实现，以及 task-269 未提交的 `PluginGemfileCache` WIP。
- 验证边界：本轮只做静态代码与文档核对、`git diff --check` 和 LF 检查；未运行 build、spec、harness、differential、Rails 或任何 Ruby 探测。task-269 WIP 的行号属于未提交工作树，合并后必须重锚。

## 0. 结论与关键裁定

1. **锁摘要的权威位置是 EvalCache entry 的成功证书，不是 RuntimeRecord。** RuntimeRecord 只保存环境/ABI、Ruby 可执行文件身份摘要和证书引用；精确锁字节 SHA-256 随同一次成功 `lock`/`install` 的 evaluation 一起提交。这样不会让与环境无关的 RuntimeRecord 误装命令成功状态。
2. **保留多平台锁的精确等值保守回退。** 当前 `lockfile.platforms == [Gem::Platform.local.to_s]` 不放宽为“包含本平台”。任何多平台、平台未知、`force_ruby_platform` 或 profile 变化都走兼容路径。证据：`src/celerite/lock_fast_path.cr:129-131`、`src/celerite/install_fast_path.cr:108-123`。
3. **Ruby 身份只由文件系统取得，禁止启动 Ruby。** 复用 `RuntimeFacts.resolve_exe`/`detect` 的纯文件路径，新增路径定位摘要、size、mtime（含精度）和 SHA-256。身份 `Unknown`、包装器、不可读文件、rbconfig 不完整一律回落。
4. **成功证书以 RuntimeRecord 为最后提交标记。** evaluation 先落盘只是求值缓存，不含成功证书；命令成功后依次提交 EvalCache 证书、task-269 插件证书，最后写 RuntimeRecord。异常或非零退出不发布；`ensure` 只做清理/回滚，不发布证书。
5. **动态 DSL 采用首辅裁断 A：保守静态 allowlist。** 已被 `EvalFingerprint` 观测器判 `Unknown` 的动态 DSL/warning 必须回落；`rand`、时间、反射等无法由静态语法证明安全的构造也必须在分类器侧判 `Unknown`。L164 原文要求“有动态 DSL、插件或指纹不确定时显式走兼容路径”（`docs/roadmap.md:164`），不能用验收方接受残余来替代。allowlist/分类器与负向矩阵完成前，L164 不可勾；C 仅可记录为已声明差异，不能作为勾选依据（见 6.2）。
6. **CI 必须同时固定正门和反假绿门。** 热路径四计数为 0、输出/锁/树/exit parity、锁字节篡改强制 miss，并用固定旧二进制证明这些负向断言会失败；不能只靠本地手工。

## 1. 当前事实与缺口

| 现状 | 证据 | 设计含义 |
| --- | --- | --- |
| `trusted_attempt` 检查 CHECKSUMS、单平台、插件根、record、entry、evaluation、warning、source、dependency、incomplete、facts、engine、verdict，但没有锁字节摘要 | `src/celerite/lock_fast_path.cr:122-176` | 同一 Gemfile 求值可搭配一份已被改写但语义碰巧仍可解析的锁文件 |
| `remember`/`remember_after_lock`/`remember_after_install` 只在命令成功后被调用，持久化异常被吞 | `src/celerite/lock_fast_path.cr:178-223` | 顺序正确，但记录本身没有绑定“哪一份锁字节成功” |
| `lock` 包装层仅在 `run_lock` 返回 0 后写记录 | `src/celerite/cli/commands.cr:2955-2974` | 可作为最终提交点，但需前移到真正的命令事务边界 |
| `write_locked_lockfile` 会重写 `BUNDLED WITH`，2.x 还会删除 bundler 自校验行；print 模式不落盘 | `src/celerite/cli/commands.cr:3294-3315` | 必须哈希“最终实际落盘字节”，不能哈希渲染前内容；print 不发证书 |
| `Lockfile.write` 保留 CRLF，但直接 `File.write`，不是原子替换 | `src/celerite/lockfile/writer.cr:12-24` | 写失败可能留下部分锁字节；摘要不匹配必须 miss，后续应改原子写 |
| evaluation 在桥求值后立即持久化，payload 没有 command-success | `src/celerite/bridge/client.cr:445-492` | 求值缓存可以先存在，但绝不能单独充当 lock/install 成功证书 |
| `RuntimeFacts` 能纯文件解析 exe/rbconfig/RubyGems；`engine`/`engine_version` 本地为 `Unknown`，当前靠 CRuby 不变量从既有记录补齐 | `src/celerite/runtime_facts.cr:141-217,267-299`、`src/celerite/lock_fast_path.cr:225-243` | 新增可执行文件身份后，记录补齐必须绑定到上一份真实桥观察；身份未知时不得沿用该补齐 |
| task-269 WIP 用空插件根和空 `Plugin::DSL` 证书允许跳过插件预检 | `C:\temp\celerite-t269\src\celerite\plugin_gemfile_cache.cr:51-103`、`C:\temp\celerite-t269\src\celerite\install_fast_path.cr` WIP | 合流时保留其负例，但证书需升级为 nonce 绑定并参与最终提交 |
| CI 的 specs 未开四计数，differential 也没有 fast-path 顺序夹具 | `.github/workflows/ci.yml:9-53`、`script/differential:1-50,159-260` | 需要独立门和序列夹具，不能只靠现有全量 spec |

task-268 已明确 L164/S8c/S8d/S8e 暂不可勾，并列出锁摘要、Ruby 身份、失败半状态和 CI 门缺口：`docs/roadmap-evidence/M8-l164-closure-audit.md:9-24,44-56,162-180`。本文只把缺口变成可实施切片，不代替实现或验收。

## 2. 锁文件 SHA-256 门

### 2.1 数据归属与 schema

EvalCache entry 升级为 `celerite-eval-cache/2`。旧 `/1` entry 仍可作 evaluation-only 缓存，但没有 `certificates` 时绝不能命中 lock/install 快路径，miss 原因固定为 `lock-unbound`。

建议在 entry 中增加严格 allowlist 的 `certificates` 映射，key 为随机 nonce：

```text
certificates[nonce] = {
  format: "celerite-success-certificate/1",
  command: "lock" | "install",
  profile: <Profile.bundler_version>,
  ruby_identity: <SHA-256>,
  lock: {
    slot: "default" | "configured:<relative-path-digest>",
    sha256: <实际落盘原始字节 SHA-256>,
    byte_size: <整数>,
    line_ending: "lf" | "crlf" | "mixed",
    parser_revision: <锁解析器协议版本>,
    bundled_with: <字符串>,
    checksums_sha256: <CHECKSUMS 节规范投影 SHA-256>,
    platforms: <有序字符串数组>
  },
  plugin?: { certificate_nonce: <同一 nonce>, roots_digest: <摘要>, index_digest: <摘要> },
  install?: { plan_digest: <现有 plan_complete 证据的规范清单 SHA-256> }
}
```

约束：

- `sha256` 是权威门，覆盖原始字节，因此 CRLF/LF、空行、注释、`BUNDLED WITH`、`CHECKSUMS`、`PLATFORMS` 的任何变化都会 miss。其余字段用于诊断、schema 校验和快速拒绝，不替代字节摘要。
- `slot` 只保存逻辑锁槽或相对路径摘要，不存绝对路径。默认 `Gemfile.lock` 使用 `default`；`BUNDLE_LOCKFILE` 等自定义路径使用规范化相对路径的 SHA-256。
- `parser_revision` 变化或锁解析器不能确定支持当前格式时 miss(`lock-format`)。不能因为“摘要相同”就绕过格式门。
- RuntimeRecord 升级为 `/2`，增加 `ruby_identity`、`eval_digest`、`certificate_nonce`。RuntimeRecord **不重复保存锁 SHA-256**，只引用 EvalCache entry 中的 nonce。锁摘要的唯一权威副本在 EvalCache 证书中。
- 证书按 nonce 保留多份。失败的新事务不能覆盖旧 nonce，避免“新事务失败顺带作废旧成功证书”。prune 可清理无 RuntimeRecord 引用的旧证书，但不得在提交窗口删除当前 nonce。

### 2.2 无循环依赖

新增叶子模块 `src/celerite/cache_identity.cr`，只依赖 `Digest::SHA256`/`JSON`，定义 `LockIdentity`、`RubyIdentity`、摘要计算和严格 schema helper。依赖方向固定为：

```text
cache_identity.cr
  ├── eval_cache_store.cr        （entry 与证书 schema）
  ├── fast_path_store.cr         （RuntimeRecord 引用；现有 namespace 依赖不变）
  └── plugin_gemfile_cache.cr    （task-269 证书升级）
          ↑
lock_fast_path.cr / install_fast_path.cr / 命令层（组合与校验）
```

禁止：

- `eval_cache_store.cr` require `fast_path_store.cr` 或 `plugin_gemfile_cache.cr`；
- `fast_path_store.cr` 读取插件证书或调用 `trusted_attempt`；
- `PluginGemfileCache` 反向调用 `LockFastPath` 或命令层；
- 为避免循环而复制两份摘要算法。schema/summary 只能由叶子模块提供。

现有 `FastPathStore` 已依赖 `EvalCacheStore.namespace`（`src/celerite/fast_path_store.cr:216-220`），保持该单向依赖即可。

### 2.3 `lock` 命令时序

1. 在 `Definition.build` 后、任何输出前，解析本次实际使用的 Ruby exe 和锁路径，读取原始锁字节，计算 `LockIdentity`。
2. 先走现有廉价门：CHECKSUMS、单平台精确等值、插件根、record/entry/evaluation/warning/source/dependency/incomplete。
3. 要求 entry 为 `/2`、含 `command=lock` 的成功证书，且 nonce、profile、Ruby 身份、锁槽和锁 SHA-256 全部相等。旧 `/1`、缺证书、不同 nonce 都 miss。
4. **命中时先在不打印、不落盘的前提下渲染最终输出和锁字节。** 若渲染会改变锁字节（例如 `BUNDLED WITH` 重写或 2.x 删除 bundler 行），放弃本次命中，转兼容路径；不得先打印 `Writing lockfile...` 再发现摘要变化。
5. 渲染字节与当前锁字节完全一致时，才打印并走写/print 分支。写成功后再读取实际目标文件复核 size/SHA-256；若外部并发改写使复核失败，命令返回已有写错误语义，不发布证书。
6. 兼容路径成功且最终锁文件关闭后，重新读取实际落盘字节，计算最终摘要；只有退出码为 0 才提交证书。
7. `lock --print` 不产生持久化锁目标，不发成功证书；仍可保留 evaluation-only entry。

现有命令入口分别位于 `src/celerite/cli/commands.cr:3086-3129`（快路径在 `Resolution.new` 前）、`:3271-3283`（print/写）和 `:3294-3315`（重写 helper）。实施时必须把“渲染”与“打印/写入”拆开，否则无法在输出前证明最终字节未变。

### 2.4 `install` 命令时序

1. 与 `lock` 相同，先计算当前锁身份；install 还要求现有 `plan_complete?` 证据全部通过。
2. 热命中要求 `command=install` 证书、相同 nonce/profile/Ruby 身份/锁 SHA-256，以及 `plan_digest` 与当前安装树证据一致。
3. 兼容 install 只有在安装动作、插件 after-install hook、锁文件写入全部成功并返回 0 后，才读取最终锁字节并计算 `plan_digest`。
4. 证书必须包含插件证书 nonce（启用插件时）；task-269 的空插件证书是必要条件，不是充分条件。
5. 任何 hook 非零、锁写失败、异常、树不完整都不提交。现有插件 hook 失败点见 `src/celerite/cli/commands_install.cr:860-912`；锁写入和返回 0 的关系见 `:988-1003`。

### 2.5 锁格式、BUNDLED WITH、CHECKSUMS、平台

| 变化 | 行为 |
| --- | --- |
| 原始锁任意字节变化 | `lock-digest` miss；重新走兼容路径，成功后发新 nonce |
| 仅 `BUNDLED WITH` 变化 | miss；禁止用旧求值直接重写后沿用旧证书 |
| 2.x/4.x profile 切换导致 bundler 行删除或版本变化 | miss(`profile` 或 `lock-digest`)；新 profile 重新成功后才可命中 |
| `CHECKSUMS` 增删改 | 字节摘要 miss；缺失/空仍先由现有 `checksums` 门拒绝 |
| 锁解析 revision/未知格式变化 | `lock-format` miss，不放宽解析器 |
| `PLATFORMS` 为多个平台 | 保留精确等值门，永远 miss(`platforms`) |
| 本平台未知或 `force_ruby_platform` | miss；不得猜测平台 |
| CRLF 与 LF 互换 | 原始字节摘要 miss；即使语义相同也不命中 |
| print 模式 | 不发证书 |

## 3. Ruby 可执行文件身份

### 3.1 解析顺序，零进程

每次命令只解析一次候选 exe，并把同一个 exe 传给 `RuntimeFacts.detect(exe)`：

1. 显式参数（目前生产入口没有则跳过）；
2. `CELERITE_RUBY`；
3. `PATH`。

复用 `src/celerite/runtime_facts.cr:169-193` 的 Windows/Unix 规则：Windows 候选名 `ruby.exe`/`ruby`、路径分隔符 `;`；Unix 候选名 `ruby`、分隔符 `:`。Windows 的 `.bat`/`.cmd`、Unix 的脚本/shim 即使可执行也算包装器，身份为 `Unknown`，不得启动它探测版本。

候选必须是普通文件、可读，且能按现有 `ruby_root`/`find_rbconfig` 规则找到完整 rbconfig。现有规则只接受父目录名为 `bin`，并在多个 rbconfig 中按排序取首份：`src/celerite/runtime_facts.cr:195-217`。找不到、匹配多个无法确定、读取失败均 `Unknown`。

### 3.2 身份组成

在内存中取得：

- `canonical_path = File.realpath(candidate)`；
- `ruby_root`：canonical path 的父目录为 `bin` 时的根；
- `relative_locator`：相对 root 的规范路径，Windows 统一小写并转 `/`；通常为 `bin/ruby.exe` 或 `bin/ruby`；
- `selection_kind`：`explicit` 或 `path`；
- `size`：实际普通文件字节数；
- `mtime`：秒与纳秒；同时记录 `precision = "ns" | "second"`；
- `sha256`：实际普通文件内容 SHA-256。

持久化只保存 `relative_locator`、`selection_kind`、size、mtime、precision、sha256 和一个组合 `identity_digest`，**不保存绝对路径、PATH 原文或 `CELERITE_RUBY` 原文**。组合摘要示例：

```text
SHA256("celerite/ruby-identity/1\0" + selection_kind + "\0" + relative_locator +
       "\0" + size + "\0" + mtime_seconds + "\0" + mtime_ns + "\0" +
       precision + "\0" + file_sha256)
```

这样整个 Ruby root 迁移时，根路径本身不进入身份；root 内实际 launcher 位置、大小、时间或内容变化仍会 miss。若平台无法提供纳秒，`precision=second` 只能用于诊断，**不能据“size/mtime 相等”跳过 SHA-256**；每次热校验仍读取并哈希候选文件。

### 3.3 Windows/Unix、符号链接与包装器

- Windows：使用 `ruby.exe`，路径比较大小写不敏感；记录文件系统返回的真实 mtime 精度。符号链接/junction 先 `realpath`，但若解析结果不再是可证明的 Ruby root/bin 布局，则 `Unknown`。
- Unix：符号链接可解析到普通 `bin/ruby`；链接目标变化会改变 canonical path/relative locator 或内容摘要。链接循环、断链、不可读目标为 `Unknown`。
- `.bat`/`.cmd`/`.cmd` shim、shell 脚本、需要启动后才可知真实解释器的 launcher 均为 `Unknown`。不能通过读取脚本猜测并放行。
- PATH 中首个命中的包装器不能静默跳到后一个真实 Ruby；那会改变实际命令语义，直接回落。
- 不调用 `ruby -e`、`ruby --version`、`ruby -rrbconfig`，也不读取进程列表。冷路径的桥观察只能来自正常兼容命令已经启动的 Ruby，不能新增探测进程。

### 3.4 与 RuntimeRecord 的关系

当前本地 `RuntimeFacts` 无法从静态 rbconfig 判断 `engine`/`engine_version`，`src/celerite/runtime_facts.cr:295-298` 明确置为 `Unknown`。当前 `complete_facts` 只在记录为 CRuby 且 `engine_version == ruby_version` 时补齐：`src/celerite/lock_fast_path.cr:225-243`。

升级后该补齐增加前置条件：

1. 本次 `RubyIdentity` 必须为 `Known`；
2. `identity_digest` 必须等于 RuntimeRecord 中上一回正常桥观察绑定的摘要；
3. 仍须满足现有 CRuby/version 不变量。

因此记录中的 engine 不是“本地静态探测结果”，而是“同一可执行文件内容上次由真实桥报告的结果”。身份未知、摘要变化、记录为旧 `/1` 都不能使用该补齐，必须回落。不得把 `Unknown` 当通配符。

## 4. 失败不写半状态

### 4.1 事务边界

引入命令级 `FastPathTransaction`（可由 `lock_fast_path.cr` 提供，不放进 store 叶子模块）：

```text
begin
  nonce = random
  evaluation-only entry 可正常持久化
  执行完整兼容命令
  if exit != 0 || exception
    abort；不新增成功证书
  else
    复核最终锁字节、RubyIdentity、plan_digest、插件证据
    写 EvalCache certificates[nonce]
    写 PluginGemfileCache nonce 证书（若需要）
    最后写 RuntimeRecord(/2, eval_digest, nonce, ruby_identity)
  end
ensure
  释放 ProcessLock/bridge；只在“已写 RuntimeRecord 后仍异常”时回滚本次 nonce
```

提交顺序的理由：

- evaluation-only entry 先存在，不含 nonce 证书，普通求值缓存可复用，但快路径必须看到证书；
- EvalCache 证书先写、插件证书后写，即使中途崩溃，RuntimeRecord 仍指向旧 nonce 或不存在，新 nonce 不可信；
- RuntimeRecord 最后写，是唯一提交标记。三个文件不做跨文件原子替换，也不假装能做；
- 每个 nonce 独立保存，失败事务不覆盖旧证书；
- 缓存写失败只损失优化，不改变已成功命令的 stdout/stderr/exit；
- `ensure` 不调用 `remember*` 发布成功状态。当前 install 主 ensure 只关 ProcessLock/bridge：`src/celerite/cli/commands_install.cr:1000-1003`，保持这一边界。

普通非零退出、抛异常、锁写失败、hook 失败均发生在最终提交前。若 Finalize 内部异常，缓存层吞掉异常且不写 RuntimeRecord。若 RuntimeRecord 已写后包装层仍抛异常，`ensure` 只能删除/恢复“本次 nonce 对应且仍指向本进程”的记录，不能删除别人的并发记录；ProcessLock 覆盖整个命令，避免同项目并发提交。

### 4.2 不可完全原子化的边界

进程在 RuntimeRecord 已提交、正常返回 0 之前被 `SIGKILL`、断电或宿主强制终止时，无法保证“外部观察到非零 exit”与“删除证书”同时发生。设计不夸大该保证：

- 正常错误/异常窗口由上述顺序和回滚覆盖；
- 硬终止窗口只能保证证书描述的锁字节、Ruby 身份和 install plan 在提交时已经真实完成，不包含半完成状态；
- 若 L164 验收明确要求覆盖硬终止后 exit 与证书的原子性，则本设计不足，L164 不可勾；
- 建议 spec 覆盖普通非零与异常，不把硬终止伪称为已解决。

### 4.3 失败点与发布规则

| 点 | 当前证据 | 发布规则 |
| --- | --- | --- |
| evaluation 持久化 | `src/celerite/bridge/client.cr:445-492` | 可写 evaluation-only；无 nonce 证书 |
| lock 写失败 | `src/celerite/cli/commands.cr:3271-3283,3324-3337` | 不写证书；目标若被部分改写，摘要与旧证书不同，下一轮 miss |
| `BUNDLED WITH`/checksum 重写 | `src/celerite/cli/commands.cr:3294-3315` | 只哈希最终落盘字节；渲染阶段不发布 |
| lock 返回非零 | `src/celerite/cli/commands.cr:2955-2974` | 不调用 Finalize |
| install hook 失败 | `src/celerite/cli/commands_install.cr:860-912` | 不写 install 证书/RuntimeRecord |
| install 锁写后异常 | `src/celerite/cli/commands_install.cr:988-1003` | 不发布；旧 install 证书即使仍在，`plan_digest` 必须不匹配 |
| RuntimeRecord 写失败 | `src/celerite/lock_fast_path.cr:184-223` | EvalCache/plugin 证书可残留但无 RuntimeRecord nonce，禁止命中 |
| 旧证书与新事务同 digest | 当前单文件 entry：`src/celerite/eval_cache_store.cr:104-133` | v2 改为 nonce 列表/独立 nonce 文件，失败事务不得覆盖旧 nonce |
| 缓存目录只读/磁盘满 | 现有 remember 均吞持久化异常 | 命令结果不变；不发新证书 |

### 4.4 spec 矩阵

每个用例都启用 `CELERITE_FAST_PATH=1`、`CELERITE_EVAL_CACHE=1`、`CELERITE_BRIDGE_STATS=1`，使用隔离 `HOME`/`USERPROFILE`/`CELERITE_CACHE_DIR`/`BUNDLE_PATH` 和离线 `file://` fixture。

| 编号 | 场景 | 必须断言 |
| --- | --- | --- |
| F01 | 第一次成功 lock/install，第二次无变化 | 第二回四计数全 0；stdout/stderr/exit/锁/树与关闭快路径的兼容运行一致 |
| F02 | v1 entry 或 RuntimeRecord | miss `lock-unbound`/`record-format`；不把旧缓存升级成成功证书 |
| F03 | 锁内容改一字节但保持可解析 | 下一回 miss `lock-digest`；不得四计数全 0 |
| F04 | CRLF↔LF | miss `lock-digest` |
| F05 | 仅改 `BUNDLED WITH` | miss；新成功后才可命中 |
| F06 | profile 4.0.24↔2.7.2 | miss `profile` 或 `lock-digest`；输出按各 profile |
| F07 | 改/删/增 CHECKSUMS | miss；空 CHECKSUMS 仍走现有 `checksums` 门 |
| F08 | 多平台锁、未知平台、force_ruby_platform | 全部 miss `platforms`/对应配置门 |
| F09 | `lock --print` | exit/output parity；不产生命令证书 |
| F10 | Ruby 路径变化、size 变化、mtime 变化、内容变化 | 分别 miss `ruby-identity:*`；只改绝对 root 而 relative locator/内容不变可命中 |
| F11 | mtime 精度仅到秒且同秒改内容 | 仍因 SHA-256 miss；不得用 mtime 跳过哈希 |
| F12 | symlink 指向另一 Ruby、断链、循环 | locator/hash miss 或 `Unknown` 回落 |
| F13 | `.bat`/`.cmd`/shell shim | `Unknown` 回落；不得启动探测 |
| F14 | `CELERITE_RUBY` 优先于 PATH；PATH 分隔符差异 | 解析顺序与现有规则一致；零新增进程 |
| F15 | lock 写失败/渲染后失败 | exit 非零；无新 RuntimeRecord nonce；旧证书不能被新 nonce 引用 |
| F16 | install hook 返回非零/抛异常 | 不发 install 证书；下一回 plan 门或证书门 miss |
| F17 | RuntimeRecord 写失败 | EvalCache/plugin 可残留；快路径仍 miss |
| F18 | 失败事务与旧成功同 digest | 旧 nonce 不被覆盖；旧锁/树仍有效时可继续命中旧证书 |
| F19 | 安装树缺 gem/spec/native marker/索引 | 现有 plan 门继续 miss；`plan_digest` 不得放行 |
| F20a | 已被观测器判 `Unknown` 的动态 DSL、warning、Unknown fingerprint | 必回落；不得仅凭 fingerprint deterministic 文案放行 |
| F20b | 未被观测器识别的 `rand`/时间/反射/外部副作用 DSL | 属未解决残余；按 6.1 选定政策断言，禁止宣称已检测或保证永不误命中 |
| F21 | task-269 插件根/index 非空、证书缺失/损坏 | miss；保留 task-269 WIP 负例 |
| F22 | 两次成功生成新 nonce，旧 nonce 保留 | 当前 RuntimeRecord 只认当前 nonce；prune 不删活跃 nonce |

## 5. CI 门禁

### 5.1 正门：热路径与 parity

在 `.github/workflows/ci.yml` 增加独立 `fast-path-gate` job，矩阵至少 `ubuntu-latest` 与 `windows-latest`，依赖已完成的主二进制构建。job 环境固定：

```text
CELERITE_FAST_PATH=1
CELERITE_EVAL_CACHE=1
CELERITE_BRIDGE_STATS=1
CELERITE_CACHE_DIR=<job 临时目录>
HOME/USERPROFILE/BUNDLE_PATH=<job 临时目录>
```

实现推荐 `script/fast-path-gate.sh` 与 `script/fast-path-gate.ps1` 共享同一 manifest 格式，或用一个跨平台 Crystal 驱动；不要在 CI 里直接跑 `script/bench-m8` 的 bootstrap/probe 来证明零 Ruby。`script/bench-m8:692-703` 已有四计数解析，`:950-1010` 已有 exit/stdout/lock/gemspec 比较，可复用解析思路，但该脚本会运行/探测 Ruby，且当前未把四计数=0 设为失败门：`script/bench-m8:717-746,950-1010`。

正门步骤：

1. 用离线 `fixtures/gem-index` 建最小项目，不访问网络。
2. 第一次 `lock`、第一次 `install` 允许起 Ruby，作为合法 warmup；记录 exit/stdout/stderr/锁 SHA/tree manifest。
3. 第二次 bare `lock`、第二次 bare `install` 必须 exit 0，stderr 必须**恰有一行** `bridge: procs=0 rpc=0 req_bytes=0 resp_bytes=0`。
4. 将热运行与同 profile 的 `CELERITE_FAST_PATH=0` 兼容运行比较：stdout、stderr（去掉仅计数行）、exit、`Gemfile.lock` 原始字节、安装树规范 manifest 全部一致。
5. 树 manifest 排除 cache、日志和临时目录，但包含锁文件、`vendor/bundle`/配置指定的安装根、gemspec 与 native marker；路径规范化，Unix 保留/规范化 executable bit。
6. 任何一步失败保留统计行、锁摘要、tree manifest 和命令退出码为 artifact。

### 5.2 parity 必须进入 differential

`script/differential` 当前契约是比较 exit/stdout/stderr/项目树，并支持 `CELERITE_BIN` 指定二进制：`script/differential:1-50,53-102`；每 fixture 会复制 Gemfile/lock/extra 到双侧 sandbox：`:159-260`。

增加 `warm-sequence` fixture/scenario：

1. candidate 侧先跑一次 `lock` 和 `install` warmup；
2. 对第二次无变化运行走现有 differential 比较；
3. oracle 侧保持对应 Bundler profile 的正常运行；
4. 比较输出、锁文件和项目树，而不是只比较 stdout 首尾；
5. warmup 的计数不参与 oracle parity，但 candidate 第二回必须过正门；
6. 两个 profile（4.0.24/2.7.2）都执行。现有 CI differential 已覆盖双 profile：`.github/workflows/ci.yml:33-53`。

### 5.3 反假绿：旧二进制必须 FAIL

在 CI 固定构建 `d9009b14a0bf18da62b7a85cfc68b2442c4446de` 为 `bin/celerite-old`，运行同一 gate 的**负向能力子集**：

- 先让旧二进制生成自己的热缓存；
- 第二次无变化运行后，在保持 Gemfile/求值不变的前提下改动一个锁字节；
- 再运行一次，新实现必须 miss 并出现非零 Ruby 计数；旧实现因没有锁摘要门，预期仍错误命中；
- CI 用反转断言要求旧二进制失败，并识别失败原因必须是 `expected_miss_after_lock_tamper`，不能是找不到二进制、fixture 错误或环境错误；
- 若旧二进制意外通过，job 失败并报 `old-binary-false-green`，不得放宽新门。

只让旧二进制在“第二次零计数”上失败不够，因为旧二进制本身已有快路径；必须用本单新增的锁/Ruby 身份失效能力做判别。

## 6. task-269 合流后的最终信任顺序

```text
bare lock / bare install
  → 开关与命令形态（print/frozen/local/force/clean/... 先回落）
  → ProcessLock（同项目串行）
  → 当前锁原始字节 SHA-256 + 锁格式/CHECKSUMS
  → PLATFORMS 精确等于 [本平台]（多平台立即回落）
  → 当前 Gemfile/evalchain/gemspec fingerprint + deterministic + 无 warning
  → RuntimeFacts.detect(同一个 exe) + RubyIdentity Known
  → RuntimeRecord /2：project/namespace/七事实/ABI/ruby_identity/eval_digest/nonce
  → EvalCache /2 certificates[nonce]：command/profile/lock.sha256
  → 插件门：hooks 关闭，或 root/index 为空且 PluginGemfileCache nonce 证书有效
  → install 专属：plan_complete + plan_digest（在信任 RuntimeRecord 之前）
  → FastPathStore verdict == Allowed
  → 渲染；锁字节不变才输出；成功后按第 4 节提交
```

task-269 当前 WIP 的顺序是先 `trusted_attempt` 再检查 `PluginGemfileCache.trusted?`，并要求本地/全局 root 与 index 为空（`C:\temp\celerite-t269\src\celerite\install_fast_path.cr:93-108,203`）。合流后可保留其语义，但把 nonce 校验并入同一证书链，避免“共享 trusted 结果 + 另一份单文件插件证书”各活各的。task-269 `plugin_gemfile_cache.cr:20-33,51-103` 的 v1 单证书只作为兼容输入，不能直接成为 v2 nonce 链。

### 6.1 动态 DSL/随机 DSL 的已知边界

`EvalFingerprint::State::Deterministic` 的定义是“主 Gemfile、evalchain、gemspec 只含静态声明，`verify.files` 是全部输入”：`src/celerite/eval_fingerprint.cr:41-59`。动态 Ruby、运行期构造的 `eval_gemfile` 路径、插件 source/index 会被判为 `Unknown` 且不持久化：`:50-54`。

必须把边界分成两档，不能混写成“动态/随机 DSL 永不命中”：

1. **已识别动态 DSL：必回落。** 只要现有观测器把求值判为 `Unknown`、发现 warning，或 task-269 的静态/执行观测不能证明空 `Plugin::DSL`，信任链就必须 miss。这一档有可实现、可测试的判据。
2. **未识别运行期随机/反射 DSL：未解决残余。** 若 Gemfile 源字节与指纹不变，但 `rand`、时间、网络、未纳入环境签名的 ENV、C 扩展、外部进程或反射在两次执行间产生不同插件声明，当前证书无法在“第二次不执行 Ruby”时发现。task-269 证书只绑定 `plugin_names + fingerprint`（`C:\temp\celerite-t269\src\celerite\plugin_gemfile_cache.cr:51-103`），因此上一次为空、这一次随机生成插件的情况可能仍命中。这不是 deterministic fingerprint 能证明或检测的事情。

fingerprint deterministic 是桥侧静态/执行观测的分类，不是对任意 Ruby 图灵完备执行的证明。空 `Plugin::DSL` 证书只覆盖该次确定的 Gemfile 求值，不能检测插件安装后 root 变化、动态 `eval("plugin ...")` 或未识别的运行期随机生成插件声明。

### 6.2 动态 DSL 裁断：采用 A

`docs/roadmap.md:164` 的原文是“有动态 DSL、插件或指纹不确定时显式走兼容路径”。首辅据此裁断采用 **A**：默认只对能够由静态分类器证明安全的 Gemfile 发证书；allowlist 外或证明失败一律走兼容路径。不能把“fingerprint deterministic”升级为“任意 Ruby 已证明无运行期随机性”。

| 选项 | 规则 | 保证与代价 | 对 L164 的影响 |
| --- | --- | --- | --- |
| A. 保守静态 allowlist（采用） | 仅接受严格语法/API allowlist 内的 Gemfile；allowlist 外、任何无法证明静态的构造直接回落 | 对 allowlist 内可给出强保证；需维护解析/分类器并接受假阴性。若 allowlist 未完整排除元编程、动态求值与外部输入，仍不能宣称覆盖任意 Ruby | 在 allowlist、分类器和负向矩阵完成前不可勾 |
| B. 显式 opt-out | 默认对可能动态的 Gemfile 回落；用户用显式配置/项目标记声明“本次按静态处理”后才允许证书 | 实现简单、用户可控；保证来自用户声明，不是自动观测，不能写成 Celerite 已检测动态性 | 可作为兼容策略，但不能替代 L164 的默认自动安全判据 |
| C. 限定已识别范围并记录残余 | 已识别 `Unknown`/warning 必回落；未识别的运行期随机/反射明确列为不支持残余 | 与现有观测器最契合，但残余存在时可能误命中，必须显式接受 | 仅可作为已声明差异记录，不能作为 L164 勾选依据 |

A 的最小可行实现应由现有 `bridge_fingerprint_dynamic_reason` 扩展为“无法证明静态即 `Unknown`”，而不是继续扩大动态 token 黑名单。现有实现位于 `assets/bridge/server.rb:516-565`：它对 12 类 token、`ruby file:`、plugin source、非字面量 `eval_gemfile`/`install_if` 做扫描；`bridge_fingerprint_state` 在 `:585-601` 据此返回 `broken > unknown > deterministic`。最小改造如下：

1. 在冷路径桥侧用语法感知的 tokenizer/parser 读取主 Gemfile、evalchain 与 gemspec 源码；只列出允许的 DSL 调用节点、静态参数、布尔条件和文件集合，禁止任意方法调用、block/元编程、动态常量、反射、`send`/`public_send`、字符串插值、外部输入与副作用节点进入 deterministic 集合。parser 失败或节点不在 allowlist，返回 `unknown:unproven-static`；不得以“没命中黑名单”当作安全证明。
2. 保留现有 `bridge_fingerprint_dynamic_reason` 产生诊断原因，但判定改为正向证明：只有整份输入都被 allowlist 覆盖且 `verify.files` 是全部依赖，才允许 `deterministic`。分类结果进入 fingerprint state，second hit 只检查该证书，不在热路径启动 Ruby 或重新执行 DSL。
3. 误报边界：注释、字符串或语义安全但暂不在 allowlist 的写法会被回落；这是有意的假阴性，牺牲命中率换正确性，不得为“提高命中”静默放宽 allowlist。
4. 漏报边界：朴素正则仍可能漏掉 heredoc、别名、反射、C 扩展、插件安装后行为和未建模外部输入。因此必须用语法树/词法规则而非 token 正则作最终安全门，并为每一类绕过补负向 fixture。该设计只保证 **allowlist 外回落**，不声称能证明任意 Ruby。

C 只能写入 compat-evidence/claims 的差异记录：说明其接受未识别运行期随机/反射残余。该记录不改变本计划，也不得据此勾选 L164。

## 7. 剩余实施切片

以下切片编号是建议，依赖串行。每片只做列出的写入范围；实现时必须同时带 spec，不得用空实现或模板测试充绿。

### task-272：身份、v2 schema 与静态 DSL 证明叶子层

- 写入：`src/celerite/cache_identity.cr`、`src/celerite/runtime_facts.cr`、`src/celerite/eval_cache_store.cr`、`src/celerite/fast_path_store.cr`、`src/celerite/eval_fingerprint.cr`、`assets/bridge/server.rb`、对应 `spec/m8_*`。
- 交付：`LockIdentity`、`RubyIdentity`、EvalCache `/2` certificates 容器、RuntimeRecord `/2` nonce/ruby_identity 引用；按 6.2 实现正向静态 DSL 证明，未覆盖节点返回 `Unknown`；旧 `/1` 明确只读不命中。
- 验收：路径/size/mtime/hash 各变化正确 miss；绝对 root 迁移不因路径本身 miss；Unknown/shim/断链回落；零 Ruby 探测；静态 allowlist 正例与 `rand`/时间/反射/动态 `eval`/heredoc/别名等负例矩阵全绿；依赖无环。
- 反假绿：把旧 `/1` 与新 `/2` 混放，旧记录不得被“补字段”后放行；mtime 同秒内容变化必须靠 hash 拒绝；删除任一 allowlist 节点必须回落，不能只靠动态 token 黑名单判 deterministic。
- 依赖：task-269 分支接口已合入或至少其 schema 方向已确认；本文不改其 WIP。

### task-273：lock 字节门与命令事务

- 写入：`src/celerite/lock_fast_path.cr`、`src/celerite/cli/commands.cr`、`src/celerite/lockfile/writer.cr`、`spec/m8_lock_fast_path_spec.cr` 与失败矩阵 spec。
- 交付：渲染/打印分离、实际落盘字节复核、atomic lock write（保留 CRLF）、lock nonce 证书、print 不发证书。
- 验收：F02–F09、F15、F17–F18 全绿；热路径四计数为 0；写失败 exit/输出与兼容路径一致。
- 反假绿：在 `Writing lockfile...` 输出后注入锁变化，仍不得发布；只改 `BUNDLED WITH` 必须 miss。
- 依赖：task-272。

### task-274：install 最终化与 task-269 合流

- 写入：`src/celerite/install_fast_path.cr`、`src/celerite/cli/commands_install.cr`、`src/celerite/plugin_gemfile_cache.cr`、`spec/m8_install_fast_path_spec.cr`。
- 交付：install `plan_digest`、nonce 插件证书、RuntimeRecord 最后提交、失败回滚；保留 task-269 的空 root/index 负例。
- 验收：F01、F10–F14、F16–F22；hook 失败/树不完整不发证书；插件证书损坏回落。
- 反假绿：同 digest 的失败事务不得覆盖旧 nonce；只删 RuntimeRecord 后即使 EvalCache/plugin 证书在也不能命中。
- 依赖：task-269 合入、task-273。

### task-275：CI 正门、differential 序列与旧二进制 FAIL

- 写入：`.github/workflows/ci.yml`、`script/fast-path-gate.sh`、`script/fast-path-gate.ps1`（或等价跨平台驱动）、`script/differential`、fast-path sequence fixture、CI spec。
- 交付：Windows/Ubuntu 矩阵正门、双 profile parity、锁篡改负向能力、固定 `d9009b1` 旧二进制反假绿、artifact 证据。
- 验收：四计数严格为 0；输出/锁/树/exit parity；旧二进制必须因 `expected_miss_after_lock_tamper` 失败；环境错误不算通过。
- 反假绿：CI 故意关闭 `CELERITE_BRIDGE_STATS` 时 job 必须失败；旧二进制若通过则 job 必须失败。
- 依赖：task-273、task-274。

### task-276：跨平台证据与闭合建议

- 写入：仅新的 `docs/roadmap-evidence/` 证据文档和 compat-evidence；本任务不勾任何 roadmap/claims 复选框。
- 交付：Windows/Unix 实际命令输出、锁 SHA、tree manifest、四计数、旧二进制 FAIL 证据、未验证项清单。
- 验收：证据可回溯到 CI run/提交/命令；动态 DSL、硬终止等边界按事实写明。
- 反假绿：不得用本地单平台结果代替 CI 双平台；不得把未复跑的历史证据写成本轮实测。
- 依赖：task-275。

## 8. L164 可勾与不可勾条件

### 8.1 可勾条件（全部满足）

- task-269 已合入，默认 bare `lock`/`install` 在空插件环境可按最终信任顺序命中；
- 已按 6.2 实现 A：正向静态 allowlist/分类器把无法证明静态的 DSL（包括 `rand`、时间、反射、动态 `eval` 等）判为 `Unknown` 并显式回落；F20b 的未识别残余只可作为风险记录，不能作为命中许可；
- 锁原始字节 SHA-256、Ruby 身份、nonce 证书链和失败事务矩阵全部实现并有 spec；
- 现有十二判据仍全部通过，特别是第二次 `procs/rpc/req_bytes/resp_bytes` 同时为 0：`docs/roadmap-evidence/M8-fast-path-plan.md:234-257`；
- CI 双平台正门通过，输出/锁/树/exit parity 通过；
- 固定旧二进制在新增负向能力上 FAIL，且失败原因正确；
- task-276 证据落库，首辅/验收方确认无遗漏；由获得授权的后续任务更新 roadmap/claims，而非本设计文档。

### 8.2 不可勾条件（任一成立）

- 只完成锁摘要或只完成 Ruby 身份；
- 仍接受 v1 无绑定证书，或用 RuntimeRecord 代替 evaluation 成功证书；
- 为支持多平台锁放宽精确等值门；
- 用启动 Ruby 探测换取身份；
- 只验证“第二次零计数”，没有锁/输出/树/exit parity；
- 只跑本地手工，没有 CI 正门与旧二进制反假绿；
- 已被观测器判 `Unknown` 的动态 DSL/warning 仍可命中，或文档宣称 fingerprint deterministic 能检测所有运行期随机性；
- A 的静态 allowlist/分类器尚未完成，或 allowlist 外、无法证明静态的构造仍可命中；
- 采用 C 或仅记录未识别运行期随机/反射残余，试图代替 L164 原文要求的默认兼容路径；
- 非零退出/异常会发布新 nonce 证书；
- 只有 Windows 或只有 Unix 实测；
- 硬终止原子性被列为已解决但无证据。若该边界被明确排除且记录在案，可按剩余判据验收；若验收要求覆盖它，则 L164 保持不可勾。

## 9. 本轮未验证项

- task-269 WIP 未提交，合流后的文件路径/行号/行为可能变化；本文引用仅用于设计。
- 未运行 build/spec/format/harness/differential/Rails；所有实现验收均为设计目标，不是实测结果。
- 未验证 Crystal 在各平台暴露的 mtime 纳秒精度、junction/符号链接行为、跨盘 atomic rename 行为；task-272/273 必须补平台 spec。
- 未验证旧二进制 `d9009b1` 在锁篡改负向子集上的实际失败文本；task-275 必须固定并观测。
- 未验证硬终止窗口；见第 4.2 节。

## 10. task-291 最终闭合说明（2026-11-27）

- §8.1 可勾条件已由后续实现与 run [`45975413773`](https://github.com/ShiningRay/celerite/actions/runs/45975413773) 闭合：同一提交 `4e1faee0827fec85a6a18752a4db0e9ef288b995` 的 Windows/Ubuntu × Bundler 4.0.24/2.7.2 四格均 success，四格 `summary.json` 均 `status=passed`，lock/install hot 四计数均 `{0,0,0,0}`，输出/锁/树/exit parity、四类负门、stats-off fail closed 与 current capability 均通过。
- 固定旧 binary `d9009b14a0bf18da62b7a85cfc68b2442c4446de` 在四格均非零且精确失败 `expected_miss_after_lock_tamper: stats={0, 0, 0, 0}`，满足 §8.1 的旧二进制 FAIL 与正确失败原因要求。
- §8.2 中“只有 Windows 或只有 Unix 实测”“只跑本地手工”“旧 binary 未到锁篡改点”等阻断已消除；硬终止原子性未被宣称解决，明确排除在本行最低闭合条件之外并继续保留风险，因此不构成伪报完成。
- 最终只勾选 `docs/roadmap.md:164`。第二 ABI、JRuby/TruffleRuby/shim、真实 ACL、多进程并发、idle-timeout、Windows rename/symlink/junction、大小写/路径、跨文件非原子、硬终止、Ubuntu 本机、真实 index/Rails 与全量 differential 仍为残余未验证项；L161/L165/L166 状态不变。
