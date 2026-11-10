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

## Known limits

- Installed gem trees under `BUNDLE_PATH` are not compared byte-for-byte yet
  (installed specs contain absolute paths); the comparison covers the project
  directory. Extending it to the bundle tree is tracked as M7 follow-up.
- N5/N7 are the only reductions that could hide a real ordering/content bug;
  they are reviewed whenever a fixture's expected output changes shape.
