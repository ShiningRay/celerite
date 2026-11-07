# Configuration — reference: Bundler 4.0.24 / 2.7.2

Derived from the pinned `bundler/lib/bundler/settings.rb` (see `vendor/reference/`).

## Priority (highest wins)

`local (.bundle/config in project) > ENV (BUNDLE_<KEY>) > global (~/.bundle/config) > default`.

- Key name normalization: `-`/`_` interchangeable (`BUNDLE_PATH` ↔ `path`);
  remembered CLI flags map onto the same keys.
- `BUNDLE_IGNORE_CONFIG=1` disables local+global file loading.
- `bundle config get/set/unset/list` persists local config by default, `--global`
  for global; nested keys with dots (`path.system`).
- Credentials/mirrors: `mirror.<url>`, `mirror.<url>.fallback_timeout`,
  `https://user:pass@...` URLs; credentials must never appear in logs, trace
  output, or diff results (architecture §4).

## Key inventory

| Key | Default (4.0.24) | Note |
|---|---|---|
| `path` | — | install location; implies `path.system` false |
| `path.system` | false | system gem dir install |
| `bin` | — | binstub dir |
| `frozen` | false | lockfile immutable |
| `deployment` | false | frozen + `without: development, test` + path lock |
| `disable_shared_gems` | false | isolated gem dir |
| `force` | false | reinstall |
| `forget_cli_options` | false (2.7.2 only) | skip persisting remembered flags |
| `jobs` | processors | parallel download/install |
| `retry` | 3 | network retries |
| `timeout` | 30 | network timeout |
| `redirect` | 5 | max redirects |
| `version` | — | require specific Bundler version |
| `cache_all` | true (4.x) | cache all platforms |
| `cache_all_platforms` | false | |
| `no_install` | false | resolve+lock only |
| `no_prune` | false | keep stale cached gems |
| `prune` | — | |
| `shebang` | — | binstub shebang |
| `clean` | false | auto-clean after install |
| `without` / `with` | [] | group filters |
| `ssl_verify_mode` | — | |
| `ssl_ca_cert` / `ssl_client_cert` | — | |
| `mirror.<url>` | — | |
| `mirror.<url>.fallback_timeout` | — | |
| `build.<gem>` | — | extension build args |
| `trust-policy` | — | |
| `allow_offline_install` | false (2.7.2 only) | |
| `update_requires_all_flag` | false (4.0.24 only) | |
| `global_gem_cache` | false (4.0.24 only) | |
| `lockfile_checksums` | true (4.0.24) | CHECKSUMS section emission |
| `cache_command_is_package` | true (2.7.2, deprecated) | |
| `error_on_stderr` | true (2.7.2) | |
| `major_deprecations` | false | |
| `lockfile` | — (4.0.24 only) | custom lockfile path |
| `cooldown` | 0 (4.0.24 only) | per-source cooldown in days |
| `default_cli_command` | install (4.0.24 only) | bare `bundle` behavior |

Env var form: `BUNDLE_<KEY uppercased, . and - → _>` (e.g. `BUNDLE_PATH`,
`BUNDLE_FROZEN`, `BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG__`).

## Per-version deltas (verified against pinned settings.rb)

- 4.0.24 adds `cooldown`, `default_cli_command`, `lockfile`, `lockfile_checksums`,
  `update_requires_all_flag`, `global_gem_cache`, `plugins`; drops
  `allow_offline_install` and the 2.7.2 REMEMBERED_KEYS machinery
  (`bin`, `cache_all`, `clean`, `deployment`, `frozen`, `no_prune`, `path`,
  `shebang`, `path.system`, `without`, `with` were persisted on CLI use in 2.7.2).
- Both honor the same precedence; CLI-remembered flags only differ in 2.7.2.

## Celerite behavior contract

- M1 implements discovery + priority readback for the keys needed by read-only
  commands (`path`, `frozen`, `gemfile`, `lockfile`...).
- Unknown keys round-trip untouched (config file fidelity).
- Writing config: M5; until then, `config` mutating subcommands report
  not-implemented explicitly.
