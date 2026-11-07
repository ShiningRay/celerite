# Reference revision manifest

Vendor copies of the exact upstream sources the Celerite compatibility contract is
derived from. Do not edit these files; re-pin by re-downloading and updating this
manifest together with `docs/compat-matrix/`.

Fetched: 2026-11-06

| Tag | Purpose | Files |
|---|---|---|
| `rubygems/rubygems` @ `v4.0.24` (Bundler 4.0.24) | primary reference | `v4.0.24/{version,requirement,platform,dependency,settings,rubygems_dependency,rubygems_ext,checksum}.rb`, `v4.0.24/lockfile_{parser,generator}.rb`, `v4.0.24/{dsl,definition,gem_version_promoter,compact_index_client,rubygems_ext}.rb`, `v4.0.24/pub_grub/` (vendored PubGrub), `v4.0.24/resolver/` (Bundler resolver layer), `v4.0.24/compact_index_client/` (cache/parser/updater), `v4.0.24/{platform,check,list,show,info,lock,config}.rb` (CLI commands), `v4.0.24/gem_parser.rb` |
| `rubygems/rubygems` @ `bundler-v2.7.2` (Bundler 2.7.2) | still-supported reference | `bundler-v2.7.2/` same file set |

URLs used:

- `https://raw.githubusercontent.com/rubygems/rubygems/v4.0.24/lib/rubygems/{version,requirement,platform,dependency}.rb`
- `https://raw.githubusercontent.com/rubygems/rubygems/v4.0.24/bundler/lib/bundler/{lockfile_parser,lockfile_generator,settings,dependency}.rb`
- `https://raw.githubusercontent.com/rubygems/rubygems/bundler-v2.7.2/...` (same paths)

Oracle binaries installed locally (Windows x64-mingw-ucrt, Ruby 4.0.6):

- `bundler-4.0.24` — run via `_bundler`-style wrapper (`script/differential`) with
  `RUBYOPT=-I... -rbundler/setup` or `bundle _4.0.24_` shim generated at first use.
- `bundler-2.7.2` — same.

Known semantic deltas between the two tags (observed from the vendored diffs):

- `Gem::Version`: identical observable semantics; 4.0.24 only adds a sort-key fast path
  and accepts `nil` (→ `0`) in `correct?`.
- Lockfile generator (4.0.24): `String` section values (e.g. `BUNDLED WITH`,
  `RUBY VERSION`) indent with **two** spaces; 2.7.2 indents with **three** spaces.
- Lockfile generator (4.0.24 only): a `bundler (<version>) sha256=...` entry is added to
  `CHECKSUMS` (subject to frozen/`.dev`/`SKIP_BUNDLER_CHECKSUM` opt-outs).
- Lockfile parser (4.0.24 only): tracks a `metadata` source; a lockfile whose only
  headings are unknown triggers a feature deprecation warning and reports `valid?` false.
- Lockfile parser (2.7.2 only): rewrites legacy `x64-mingw32` platform entries to
  `x64-mingw-ucrt` with a major deprecation warning; 4.0.24 only warns.
- `Bundler::Settings`: 4.0.24 adds `cooldown`, `default_cli_command`, `lockfile`,
  `lockfile_checksums`, `BUNDLE_LOCKFILE_CHECKSUMS`, `BUNDLE_CACHE_ALL`,
  `BUNDLE_PLUGINS`, `BUNDLE_GLOBAL_GEM_CACHE`, `BUNDLE_UPDATE_REQUIRES_ALL_FLAG`
  defaults and drops 2.7.2's `allow_offline_install` / remembered-flags behavior.
