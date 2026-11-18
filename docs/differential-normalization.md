# Differential normalization rules

`script/differential` compares reference Bundler output against Celerite after
applying a fixed, complete set of normalization rules. This file is the
authoritative list; the script header carries the same identifiers. Any new
rule requires review here first, then in the script, then a re-run of both
pinned profiles.

| ID | Rule | Why it is non-semantic |
|---|---|---|
| N1 | Sandbox paths (native and MSYS spellings) → `{SANDBOX}` | The two engines run in different temporary directories; only the mapping differs. |
| N2 | CRLF → LF | Windows checkout/line-ending conversion, not program output. |
| N3 | ISO-8601 timestamps → `{TIMESTAMP}` | Wall-clock noise (e.g. `live replay` headers). |
| N4 | Calendar dates → `{DATE}` | Same as N3 for `YYYY-MM-DD` shapes. |
| N5 | `## Environment` body up to `## Bundle Doctor` is dropped | Host Ruby/gem installation paths are machine-specific, not engine output. |
| N6 | Ruby backtrace frames (`   from ...`) are dropped | Frame paths are machine-specific; the exception line itself is kept. |
| N7 | Runs of consecutive `Fetching ` lines are sorted | Concurrent downloads complete in arbitrary order; no other line order is changed. |
| N9 | Installed-tree binary artifacts (`.so`/`.dll`/`.bundle`/`.o`/`.a`) compare presence + non-empty size + optional `ruby` loadability, not bytes | Native builds are non-deterministic (compiler revision, debug info, timestamps); Bundler's observable contract is "extension compiled and loadable", not identical bytes. |
| N10 | Fixtures that ship a `stderr-contains` marker compare stderr by `grep -Fq` needles instead of line-by-line | A plugin hook raising from user code makes the reference print a full Ruby backtrace with machine paths (outside N1/N6 scope); only the fixture-opted contract — "the failure names the raised message" — is compared. stdout, exit codes and project trees stay exact, so the crash cannot hide behind it. |

## What is *not* normalized

- Exit codes must match exactly.
- stdout/stderr lines other than N1–N7 must match exactly, in order.
- Project file trees: missing/extra paths fail the fixture.
- Project file contents: a file reported as differing by `diff -r` must be
  identical after N1–N7 normalization, otherwise the fixture fails.
- `first-line` and `file-contains` probes are byte-exact.
- `stderr-contains` (N10) is opt-in per fixture and *widens* stderr matching
  only for that fixture: every needle must appear verbatim on both sides, and
  the run prints `stderr compared by contains only (declared normalization
  N10)`. Fixtures without the marker keep the exact comparison.
- `file-absent` is opt-in per fixture and *tightens* the tree comparison: each
  listed project-relative path must be absent on both sides, with
  `file-absent violated (<path>): ref_exists=<..> cel_exists=<..>` otherwise.

## 安装树比较内容（`installed-tree` marker）

Fixtures may opt in to a bundle-tree comparison by listing globs relative to
`BUNDLE_PATH`, one per line, e.g.

```
ruby/*/gems
ruby/*/specifications
ruby/*/bin
```

`script/differential-installed-tree` compares, for every matched directory
(`compare_installed_tree`), in this order:

1. **匹配目录集合**：每个 marker glob 在 reference/celerite 两侧展开的目录集合必须一致。
2. **符号链接目标（symlink target）**：自行 `find . -type l` 枚举两侧符号链接并 `readlink` 比较目标字符串（不依赖 `diff -r --no-dereference` 的版本差异）；目标不一致输出
   `symlink target differs: ref=<x> cel=<y>` 并返回 1。符号链接本身跳过后续内容/可执行位比较。
3. **相对路径集合**：目录树内相对路径集合必须一致（缺失/多余项失败；基于 `diff -r --brief` 结果，排除 `Files ... differ` 行）。
4. **文件内容**：`diff -r --brief` 报告为内容不同的**非符号链接**文件，经 harness `normalize`（N1–N7 文本归一化，见上表；二进制载荷中替换串不出现时等效字节比较）后必须一致，否则 `content differs after normalization`。
   **N9（编译产物）**：扩展名为 `.so`/`.dll`/`.bundle`/`.o`/`.a` 的编译产物不比字节，改比 ①两侧都存在 ②非空 ③可选 `ruby -e "require '<rel path without ext>'"` 可加载（ruby 可用时）；其余文件仍按 N1–N7 归一化后逐字节比较。
5. **可执行权限（平台差异）**：仅在非 Windows（`uname -s` 非 MINGW/MSYS）比较内容已归一化一致文件的 executable bit；Windows/git 通常不保留该位，因此跳过。

**N1–N7 索引**：路径/换行/时间戳/日期/Environment 体/backtrace 帧/连续 `Fetching` 行排序的归一化规则见本文档顶部表格；安装树内容比较复用同一 `normalize`。

**自测**：`script/differential-installed-tree-selftest` 覆盖 6 断言——(a) 完全一致 PASS、(b) 内容差异 FAIL 且含 `content differs`、(c) symlink 目标差异 FAIL 且含 `symlink target differs`、(d) 缺 symlink FAIL、(e) ref 普通文件 vs cel 同名 symlink（内容相同）FAIL 且含 `entry type differs`、(f) cel 多一个 symlink FAIL 且含 `unexpected symlink`。Windows 使用 `MSYS=winsymlinks:nativestrict ln -s` 探测/创建真实符号链接；若无法创建时 (c)/(d)/(e)/(f) 记为 SKIP 并输出错误与复现命令（不伪报 PASS）。

**N9 补充**：编译产物（`.so`/`.dll`/`.bundle`/`.o`/`.a`）走存在性+非空+可选可加载判定，不比字节（编译器非确定性，字节差异不属可观察契约；边界：不校验 ABI 兼容性，仅存在性+可加载性）。

**5 类判定**（安装树 `compare_installed_tree`）：① 路径集合（matched dirs / relative path set，missing/extra）；② 类型（symlink vs regular file，输出 `entry type differs: ref=<file|symlink> cel=<file|symlink>`）；③ 链接目标（`readlink` 不一致，输出 `symlink target differs: ref=<x> cel=<y>`；仅单侧存在时 `symlink missing on celerite side` / `unexpected symlink on celerite side`）；④ 内容（非 symlink 文件经 N1–N7 normalize 后一致，否则 `content differs after normalization`）；⑤ 可执行位（仅非 Windows，executable bit differs）。消息文本与上述输出字面一致。

**覆盖范围**：带 `installed-tree` marker 的 fixture 列表随仓库演进变化，权威来源为 `ls fixtures/differential/*/installed-tree`（历史：HEAD=206d749 时 20 个）。回归时应至少对可运行的请求 fixture 在双 profile 下记录命令/exit/计数。
## 2026-11-19 断言通道：`file-absent` 与 `stderr-contains`

对比通道此前只有 exit / stdout / stderr / tree / `first-line` / `file-contains`
/ `file-crlf`。本轮补两条夹具级标记（仅显式提供标记文件的夹具生效）：

- `file-absent`：每行一个 project 相对路径，两侧都必须不存在；违例时
  `file-absent violated (<path>): ref_exists=<yes|no> cel_exists=<yes|no>`。
  用途：`plugin-hook-raise` 断言 hook 失败后**不留 `Gemfile.lock`**——纯树
  路径比较无法表达「不得存在」，两侧都写出该文件反而会 PASS。
- `stderr-contains`：每行一个 needle（与 `file-contains` 相同的 `@PLACEHOLDER@`
  替换），两侧 stderr 都必须 `grep -Fq` 命中；命中时**跳过该夹具的逐字 stderr
  比较**并在输出里注明 `stderr compared by contains only (declared
  normalization N10)`。用途：参考在 hook 抛异常时打印完整 Ruby backtrace
  （含机器路径，N6 只剥 `   from ...` 帧，异常后的上下文仍在），逐字比较不可能
  稳定；stdout、exit code、project tree 仍是精确比较。

使用约束（N10）：只有参考侧输出是**不可逐字复现的 crash report** 时才允许启用
`stderr-contains`，且该夹具必须同时精确断言 exit code、stdout 与受影响文件
状态（本切片：exit 1、stdout 三行逐字、`file-absent Gemfile.lock`）；当前仓库
唯一使用点是 `fixtures/differential/plugin-hook-raise/`。

自测夹具 `fixtures/differential/harness-assert-selftest/`：`command` 为
`install`（项目无 Gemfile，两侧 exit 10），`stderr-contains` 为
`Could not locate Gemfile`，`file-absent` 为 `Gemfile.lock`。实跑（4.0.24）：

```
    stderr compared by contains only (declared normalization N10)
PASS harness-assert-selftest (exit=10)
differential (4.0.24): 1 passed, 0 failed, 0 skipped
```

负对照（现场改标记后恢复）：`stderr-contains` 追加
`definitely-not-in-stderr` → FAIL 且
`stderr-contains differs: needle=definitely-not-in-stderr`（exit 1）；在
`extra/` 放 `probe-marker.txt` 并把该路径写进 `file-absent` → FAIL 且
`file-absent violated (probe-marker.txt): ref_exists=yes cel_exists=yes`
（exit 1，两行均逐字见输出）。

## Known limits

- Binary artifacts inside `.gem` payloads are compared through normalized
  text, so a payload byte difference that does not change the text shape is
  not detected; the checksum verification in the installer covers those.
- N5/N7 are the only reductions that could hide a real ordering/content bug;
  they are reviewed whenever a fixture's expected output changes shape.

## 2026-11-15 harness fixes

- `bundle-preset/` fixture directory: copied into both sides' `$BUNDLE_PATH`
  before the commands run, so fixtures can start from "already installed"
  state (for example `check` with satisfied dependencies). The directory lives
  inside the sandbox and is not part of the project-tree comparison.
- `installed tree` content comparison normalizes through temp files inside each
  sandbox and then runs `cmp`. The Ruby-bundled msys `diff` on this host does
  not support bash process substitution (`/dev/fd/63: No such file or
  directory`), which previously misreported the CRLF `thor.bat` as different.
- CRLF vs LF inside `.bat` binstubs is tolerated by N2 on both sides; the
  product is not changed (the reference writes CRLF).
- Sandbox roots are `$work/ref` and `$work/cel` (equal length), so
  column-wrapped output breaks at the same point after `{SANDBOX}`
  substitution.
- The default work root is `$repo_root/.d` (override with
  `CELERITE_DIFF_WORK_ROOT`), because celerite can only write inside the
  workspace on this host; `TMP`/`TEMP`/`TMPDIR` point into the sandbox.
- HTTP-index fixtures (`http-index` marker) wait for the server before the
  first command: the harness probes `http://127.0.0.1:8765/versions` every
  100ms for up to 10s, skips the fixture with an explicit message if the port
  is already served by a foreign process or the server never becomes ready,
  and `kill`s plus `wait`s the child afterwards. Without the wait the first
  command raced `listen()` and failed with `ECONNREFUSED`, which surfaced as
  spurious `cooldown*`, `outdated-cooldown-*` and `plugin-source` failures.
  These fixtures need `node` on the bash `PATH`; when it is absent they SKIP
  explicitly (never pass) — add
  `CELERITE_DIFF_EXTRA_PATH="/c/Program Files/nodejs"`. The 121/15/2 baseline
  assumes node is available; without it the same run is 115/15/8 (the six
  http-index fixtures move to SKIP, the same 15 failures remain).
- Native extension builds still fail for celerite descendants here
  (`NtCreateDirectoryObject ... 0xC0000022` from msys `make`), so fixtures that
  build gems are classified as environment failures, not harness or product
  failures. Root cause (2026-11-15): workspace Crystal binaries run at Low
  integrity (`S-1-16-4096`) and their msys `sh` cannot create the
  `\BaseNamedObjects\msys-2.0S5-<hash>` object; see
  `docs/compat-report.md`「2026-11-15 M7(5)/M7(8) 环境失败根因」.
- Each command of a multi-command fixture writes its own `ref.part.$n.out` /
  `.err` (and `cel.part.$n.*`); the per-side files are combined once with
  `cat "${parts[@]}" > "$work/ref.out"`. On this host a second `>>` reopen of
  the same file resets the write offset, so the next command overwrote the
  previous command's output from byte 0. That artifact produced spurious
  one-character wrap shifts after whitespace normalization; it was *not* a
  product `word_wrap` defect and no product code was changed for it.
- Fixtures that pass a relative git path (`--git=./gitgem`) are set up by the
  harness from each fixture's `git-init` manifest. Staging repos are created
  inside `$work` and handed to `git -C` as Windows paths (`cygpath -w`). The
  earlier form (`mktemp -d` POSIX path straight into `git -C`) left
  `project/<rel>` without `.git`, so the reference saw a non-repository
  (`fatal: repository './gitgem' does not exist`); reverting those two lines
  reproduces the failure (verified 2026-11-15), while the underlying path-root
  mechanism is still a hypothesis (a standalone replay of the old commands
  produced a valid `.git`). No normalization rule is involved.

### 2026-11-15: `## Environment` 只在 doctor 报告中被剥离（N5 修正）

旧规则（sed 区间 `/^## Environment$/,/^## Bundle Doctor$/{…d}`）对 `bundle env` 输出会从
`## Environment` 一直删到 EOF（env 输出没有 `## Bundle Doctor` 终止符），两侧都变成
0 字节，`env-report` 因此长期是空比较（假 PASS）。修正：改在 awk 中条件缓冲——
只有遇到 `## Bundle Doctor` 才丢弃已缓冲的 Environment 行，否则 EOF 时原样输出；
doctor 类（`issue-*`）行为不变（复跑 `issue-no-gemfile`/`issue-missing-gems`/`issue-satisfied` 仍 3/3 PASS）。
同时新增两条行级归一化（只替换值、保留字段名）：`Git SHA    <sha>` → `{GIT_SHA}`
（参考是它自己的构建 SHA，我们是 HEAD）；`bundle #!  <shebang>` → `{BUNDLE_SHEBANG}`
（本产品是原生可执行文件、无 shebang，属已声明偏差）。日期行继续按 N4 替换值
（`Timestamp` 不再泄漏构建日期；计数改为显式 `[0-9]` 以避开不同 sed 的区间语法差异）。
除此之外 env 输出逐字比较。负对照：修复后 `env-report` 由 PASS 变 FAIL（真实差异：
`Bundler` 行多 `(Celerite …, compatibility profile)`、缺 `## Bundler settings` 段、
`<No … Gemfile.lock found>` 行），证明比较已生效。

- 夹具 `Gemfile`/`Gemfile.lock` 的复制使用 `copy_fixture_text`：`sed` 只做 `@PLACEHOLDER@` 替换，若源文件含 CRLF，再用 bash 行循环以 `printf '%s\r\n'` 重写（MSYS `grep` 会剥 CR，检测走 `od -tx1 | grep 0d0a`）。`file-crlf` 标记对 4.x 断言「至少 1 个 CRLF 且无孤立 LF」，对 2.7.x 断言 LF（参考在 Windows 文本模式下会归一）。
