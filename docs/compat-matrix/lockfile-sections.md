# Lockfile sections — reference: Bundler 4.0.24 / 2.7.2

Derived from `Bundler::LockfileParser` and `Bundler::LockfileGenerator` at the pinned
tags (see `vendor/reference/`). Status markers: **native** = target for Celerite's
Crystal core; *M1* = first delivery milestone.

## Section inventory

Introduced in (`SECTIONS_BY_VERSION_INTRODUCED`, identical in both references):

| Section | Since | Content form |
|---|---|---|
| `GEM` | 1.0 | source header + options + `  specs:` |
| `PATH` | 1.0 | source header + options + `  specs:` |
| `GIT` | 1.0 | source header + options + `  specs:` |
| `PLATFORMS` | 1.0 | one platform string per 2-space line |
| `DEPENDENCIES` | 1.0 | `  name (req...)` lines |
| `BUNDLED WITH` | 1.10 | single 2/3-space version string |
| `RUBY VERSION` | 1.12 | single 2/3-space version string |
| `PLUGIN SOURCE` | 1.13 | source header + options + `  specs:` |
| `CHECKSUMS` | 2.5.0 | `  name (version[-platform]) sha256=hex[,sha256=hex]` |

Unknown section headings (matched by `/^\w[\w ]*$/` at column 0, not in the list
above) must be preserved verbatim by the parser and are reported via
`unknown_sections` — parser silently stops interpreting indented lines under them
until the next known heading (both references do this).

## Parsing rules (identical in both references unless noted)

- Merge-conflict markers `<<<<<<<`, `=======`, `>>>>>>>`, `||||||||` anywhere in the
  file → hard failure: `Your <lockfile> contains merge conflicts.` with the
  `git checkout HEAD --` hint.
- Line splitting on `/\r?\n/` runs; blank separator chunks skipped.
- Column-0 lines: section selection. `GEM`/`PATH`/`GIT`/`PLUGIN SOURCE` switch into
  source mode (`parse_source`); `DEPENDENCIES`, `CHECKSUMS`, `PLATFORMS`,
  `RUBY VERSION`, `BUNDLED WITH` switch to their parsers. Any other column-0 line
  cancels the current parse mode (unknown-section content ignored).
- Source options: `/^  ([a-z]+): (.*)$/i`; `true`/`false` literal strings become
  booleans; repeated keys accumulate into an array.
- `  specs:` (exactly) materializes the current source from its options.
- Name/version line grammar `NAME_VERSION` (both references):
  - exactly 2, 4, or 6 leading spaces (`(?! )` forbids a 7th);
  - name, then optional ` (version[-platform])`, optional `!` (pinned), optional
    space-separated checksum token;
  - the version group is `[^-]*`, so the first `-` splits version from platform
    (e.g. `rails (7.0.4-x86_64-linux)`);
- 4-space lines inside a source = specs: `name (version)` or
  `name (version-platform)`; malformed version → `LockfileError`
  `Your lockfile is unreadable...` with `line:column` position.
- 6-space lines inside a source = spec dependencies: `name (req, req, ...)` —
  version field split on `,`, each part stripped, parsed with RubyGems
  `Gem::Dependency` semantics.
- `DEPENDENCIES` lines: 2-space indent only; same grammar; `!` marks a dependency
  pinned to its locked source (except name `bundler`); `= <version>` single-requirement
  deps of a PATH source feed the fallback spec name/version.
- `CHECKSUMS` lines: 2-space indent; `name (version[-platform])` + checksums split on
  `,`; `bundler` entries bind to the metadata source (4.0.24) / are stored on the
  matched spec or a lazy bundler spec (2.7.2).
- `PLATFORMS` lines: 2-space indent, one `Gem::Platform` each, order preserved,
  duplicates possible upstream (kept as-is by the parser).
- `RUBY VERSION`: the whole line stripped; stored as a string (e.g.
  `ruby 3.2.0p0 (x64-mingw-ucrt)`) — not parsed into a requirement at this layer.
- `BUNDLED WITH`: line stripped; must satisfy `Gem::Version.correct?`; otherwise
  ignored (no version recorded).
- 4.0.24 only: an empty lockfile or one with at least one known section is `valid?`;
  otherwise a feature deprecation warning is emitted (`does not appear to be a valid
  lockfile`). 2.7.2 has no validity concept.
- 2.7.2 only: `x64-mingw32` in `PLATFORMS` is rewritten to `x64-mingw-ucrt` with a
  major deprecation (deleted when both present, replaced otherwise), unless frozen;
  4.0.24 only warns `deprecated and will be removed in the future`.
- `most_specific_locked_platform` = platforms sorted by
  `Gem::Platform.platform_specificity_match(platform, Bundler.local_platform)`
  (equal → -1; RUBY involvement → 1_000_000; else os+cpu*10+version*100 scoring);
  specs get it assigned after sorting by `full_name`.

## Serialization rules

- Sources in lock order; each `source.to_lock` writes header + options
  (`  remote: <url>`, GIT: `  remote:`, `  revision:`, `  branch:`, `  tag:`,
  `  glob:`), then `  specs:` + specs sorted by `full_name` (name, version, platform
  ordering), skipping name `bundler`.
- `DEPENDENCIES`: deps sorted by `to_s` (name then requirement string), deduped by
  name; each `dep.to_lock` = `  name (req...)` (+ `!` when locked source pinned),
  requirement rendered by `Gem::Requirement#for_lockfile`: `>= 0` alone → `()` omitted;
  requirements sorted by version ascending, formatted `op version`, unique,
  wrapped as ` (a, b)`.
- `PLATFORMS`: values `to_s`, sorted, 2-space indent.
- `CHECKSUMS` (when enabled): `name (version[-platform]) sha256=...` sorted (array of
  strings sort), 2-space indent; 4.0.24 appends `bundler (version) sha256=...` unless
  frozen (reproduces locked entry), `.dev` bundler, or `SKIP_BUNDLER_CHECKSUM`.
- `RUBY VERSION`: `  <string>` — **4.0.24 uses 2 spaces, 2.7.2 uses 3 spaces**.
- `BUNDLED WITH`: `  <version>` — same per-version indent delta.
- Array/Hash section values sort by their string forms; sections separated by one
  blank line; sources separated by one blank line, none before the first.

## Gem::Version semantics (shared model, from pinned `rubygems/version.rb`)

- Pattern (anchored, optional whitespace): `[0-9]+(?>\.[0-9a-zA-Z]+)*(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?`;
  empty/whitespace-only/`nil` → `0` (2.7.2 warns on `nil`).
- Stored string: strip; `-` → `.pre.`; `to_s` returns the stored string
  (`1.0-beta` ⇒ `1.0.pre.beta`).
- `prerelease?` = version contains `[a-zA-Z]`.
- Segments: scan `/\d+|[a-z]+/i` → integers or strings.
- Comparison uses canonical segments: trailing `[.0]+` runs anchored behind a letter
  or dot removed; in prereleases, leading `[0.]+` before the first letter removed;
  per index: equal → next; `String < Numeric`; numbers compare numerically, strings
  lexicographically; exhausted side wins only against remaining non-zero numbers
  (remaining `String` ⇒ exhausted side larger). No special-casing of prerelease vs
  release beyond this: `1.0.a < 1.0`, `1.0.a < 1.0.1`, `0.a < 0`.

## Gem::Requirement semantics (from pinned `rubygems/requirement.rb`)

- Ops: `= != > < >= <= ~>`. `~>` satisfied when `v >= r && v.release < r.bump`.
- Pattern: optional op, optional spaces, version (Gem::Version pattern, non-empty),
  optional spaces; bare version ⇒ `=`.
- `>= 0` normalizes to the default requirement; `>= 0.a` to the default prerelease
  requirement; malformed → `Illformed requirement [...]` error.
- `for_lockfile` formatting as above; `specific?` = more than one requirement or op
  not in `>` / `>=`.

## Gem::Platform semantics (from pinned `rubygems/platform.rb`)

- `new("ruby" | "" | nil)` ⇒ the virtual RUBY platform; `new("current")` ⇒ local.
- Parsing `cpu-os[-version]`: cpu `i\d86` → `x86`; trailing `-+` stripped; os matched
  against the known list (`aix, cygwin, darwin, macruby, freebsd, java, dalvik,
  dotnet, linux, mingw32, mingw, mswin\d+, netbsdelf, openbsd, solaris, wasi`,
  `<word>_platform` test hooks, else `unknown`); `mswin\d+` sets cpu x86 for the 32
  variant when cpu absent; legacy jruby (single token) ⇒ cpu nil.
- `to_s` = `cpu-os-version` joined with `-`, nil fields dropped; when cpu is nil the
  joiner is `""` (legacy jruby round-trip).
- Equality = cpu+os+version triple; match (`===`) rules incl. universal-mingw
  cross-matching, `arm` vs `armv*`, and linux gnu/musl/eabi version normalization.
