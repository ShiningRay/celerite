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

## What is *not* normalized

- Exit codes must match exactly.
- stdout/stderr lines other than N1–N7 must match exactly, in order.
- Project file trees: missing/extra paths fail the fixture.
- Project file contents: a file reported as differing by `diff -r` must be
  identical after N1–N7 normalization, otherwise the fixture fails.
- `first-line` and `file-contains` probes are byte-exact.

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
5. **可执行权限（平台差异）**：仅在非 Windows（`uname -s` 非 MINGW/MSYS）比较内容已归一化一致文件的 executable bit；Windows/git 通常不保留该位，因此跳过。

**N1–N7 索引**：路径/换行/时间戳/日期/Environment 体/backtrace 帧/连续 `Fetching` 行排序的归一化规则见本文档顶部表格；安装树内容比较复用同一 `normalize`。

**自测**：`script/differential-installed-tree-selftest` 覆盖 (a) 完全一致 PASS、(b) 内容差异 FAIL 且含 `content differs`、(c) symlink 目标差异 FAIL 且含 `symlink target differs`、(d) 缺 symlink FAIL。Windows 使用 `MSYS=winsymlinks:nativestrict ln -s` 探测/创建真实符号链接；若无法创建时 (c)/(d) 记为 SKIP 并输出错误与复现命令（不伪报 PASS）。

**覆盖范围**：带 `installed-tree` marker 的 fixture 列表随仓库演进变化，权威来源为 `ls fixtures/differential/*/installed-tree`（历史：HEAD=206d749 时 20 个）。回归时应至少对可运行的请求 fixture 在双 profile 下记录命令/exit/计数。
## Known limits

- Binary artifacts inside `.gem` payloads are compared through normalized
  text, so a payload byte difference that does not change the text shape is
  not detected; the checksum verification in the installer covers those.
- N5/N7 are the only reductions that could hide a real ordering/content bug;
  they are reviewed whenever a fixture's expected output changes shape.
