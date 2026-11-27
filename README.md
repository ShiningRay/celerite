# Celerite

A Crystal-native Bundler-compatible dependency manager, with a controlled Ruby
compatibility boundary. Performance is a measured goal, not an unconditional claim.

> **Status: native resolution and installation paths exist; full compatibility is
> not yet accepted.** Crystal implements the core version/requirement model,
> PubGrub, Compact Index, lockfiles, downloads/checksums and basic installation.
> Ruby still handles dynamic Gemfile/gemspec evaluation, native extension builds,
> plugin hooks and parts of the runtime through the compatibility bridge.
>
> Recent native coverage includes install-time `required_ruby_version` /
> `required_rubygems_version` rechecks (`src/celerite/installer.cr:99-120`),
> empty-CHECKSUMS backfill (`src/celerite/definition.cr:566-590`),
> installed-specification detection for `check`/`list`/`show`/`info`
> (`src/celerite/cli/commands_surface.cr:1671`), and typed custom sources at
> S1+S2+S3 (`PLUGIN SOURCE` write, locked reuse and install;
> `src/celerite/resolution.cr:1362`, `:1371`, `:1494`). The S3 install path is
> covered by `plugin-source-install` on both reference profiles.
>
> Tasks 52–60 added native coverage for the after-install clean-up
> (`BUNDLE_CLEAN`), the `doctor` subcommands with the Windows dylib warning,
> `doctor ssl` and `diagnose --ssl`, the `add` option and operand surface,
> `plugin new` / `licenses` / local `config` wording, `update --bundler`,
> `lock --normalize-platforms` and `--lockfile`, the missing
> `install --target-rbconfig` failure surface, and cache-based
> `update --redownload` output. Details and declared gaps are in the
> corresponding `docs/compat-report.md` sections.
>
> The current roadmap prioritizes correctness and trustworthy upstream evidence
> (M7), then batch bridge calls and no-Ruby cache hits (M8), native install plans
> and a lightweight runtime (M9). Embedding Crystal as a Ruby native extension is
> an optional later spike (M10), not the default architecture. See
> [the compatibility report](docs/compat-report.md) for measured coverage and
> known gaps rather than treating command names as completed functionality.
> Snapshot figures in that report are recorded evidence and may be **unverified
> against the current HEAD** until rerun (see the report header).

## Goals

- Preserve Bundler's observable behavior: Gemfiles, lockfiles, CLI, installation,
  runtime setup, and plugins.
- Move dependency resolution, Compact Index processing, downloads, verification,
  and installation planning into native Crystal code.
- Keep a controlled Ruby compatibility bridge for arbitrary Ruby DSL, native
  extension builds, and third-party Bundler plugins.
- Verify behavior with differential tests and the upstream Bundler test suite
  (current v4.0.24 lockfile baseline: 64 examples, 45 failed / 19 passed;
  buckets `env:out-of-process-artifice` 44 / `fixture:fetch-failed` 1 /
  `env:low-il-shm` 0 / `product:candidates` 0; real-drive 69 celerite invocations,
  harness verdict `ok`; collected 2026-11-23 by task-193, kept current in
  [the compatibility report](docs/compat-report.md) under `Current metrics`).
  The 50-failure snapshot — 64 examples, 50 failed / 14 passed; buckets
  `env:out-of-process-artifice` 38 / `env:low-il-shm` 9 / `fixture:fetch-failed` 3,
  with `product:candidates` at zero; real-drive 69, harness verdict `ok`;
  collected 2026-11-23 by task-178 — is a historical snapshot, superseded by the
  2026-11-23 45/44/1/0 run above, and preserved as history. The 47-failure line —
  64 examples, 47 failed / 17 passed; buckets artifice 41 / fetch 3 / product 3,
  collected 2026-11-22 — is superseded and preserved as history. The artifice
  bucket is not merely unrun: it is structurally
  undecidable under real-drive, because celerite runs as a native executable and
  cannot receive the RSpec `RUBYOPT=-r` stub injected into child processes;
  installing `sinatra` only cleared the reference-side `LoadError` (sinatra load
  failures: 0), which moved nothing. The earlier snapshot — 64 examples,
  54 failed / 10 passed; buckets artifice
  38 / low-IL 8 / fetch 6 / product 2, collected 2026-11-19 16:32 by task-32 —
  is superseded and preserved as history: it was not recollected after tasks
  33–59 and is recorded in ``docs/compat-evidence/2026-11-19.md`` task-32).

## Non-goals

- Replacing Ruby or RubyGems.
- Claiming compatibility through command names alone.
- Silently delegating an entire installation to `bundle install` when native
  functionality is missing.

The `celerite` executable is the initial entry point. A `bundle` alias will be an
explicit, opt-in installation step; it will never be overwritten automatically.

## Documentation

- [架构方案](docs/architecture.md)
- [兼容性契约](docs/compatibility.md)
- [实施计划](docs/roadmap.md)
- [兼容矩阵基线](docs/compat-matrix/README.md) — hand-collected per-version
  feature lists pinned to the upstream manifest ([manifest](vendor/reference/MANIFEST.md));
  collection dates are recorded in the matrix index (docs/compat-matrix/README.md)

## Install

One-liner (downloads the platform binary from GitHub Releases, verifies it
against `checksums.sha256`, installs to `~/.local/bin`; never replaces an
existing `bundle` — the shim lands as `celerite-bundle` instead):

```console
curl -fsSL https://github.com/ShiningRay/celerite/releases/latest/download/install.sh | bash
```

Options: `PREFIX=<dir>`, pin a version with an argument (`... | bash -s -- 0.1.0`).

Via RubyGems (platform gems built per release):

```console
gem install celerite
```

The gem ships the native binary plus the Ruby bridge; the installed shim
locates your Bundler gem automatically and exports the bridge environment
(`CELERITE_BRIDGE_SERVER`, `CELERITE_REFERENCE_BUNDLER_LIB`,
`CELERITE_PROFILE_BUNDLER_VERSION`).

Platform gems are self-contained: the release build bundles the non-system
shared libraries the binary links against (see `THIRD_PARTY_LICENSES.md`), for
Darwin (arm64 and x86_64), Linux x86_64, and Windows x64. No Homebrew, MSYS2, or
extra system packages are required.

Both channels are produced by `script/release` (dist bundle + platform gem
with an install smoke test); releases are published from the `v*` tag
workflow. A bare `gem build celerite.gemspec` produces a metadata-only gem —
always build through `script/gem`.

## Development

Requires Crystal 1.21.1 or newer. On this Windows host, run specs with `HOME`,
`TMP`, `TEMP` and `TMPDIR` pointed inside the workspace (e.g.
`.tmp-scratch/spectmp`); otherwise environment-related sandbox errors appear and
are not product failures (see `docs/compat-report.md`). The differential harness
also needs the msys64 tool directories on `PATH` and `CELERITE_BIN` set.
Release binaries do not carry the differential harness, so runtime conclusions
do not cover development-time differential runs.

```console
shards build          # build bin/celerite
crystal spec          # unit + property + behavior specs
crystal tool format --check src spec
script/differential   # differential harness vs pinned reference Bundlers
```

Reference Bundler versions (4.0.24 and 2.7.2) must be installed for the
differential harness:

```console
gem install bundler -v 4.0.24
gem install bundler -v 2.7.2
```

The harness runs each fixture in its own sandbox. Most fixtures are offline, but
`http-index` fixtures start a loopback HTTP server on `127.0.0.1`. Known limits:
Low-IL Windows hosts block some git-source fixtures (`0xC0000022`). Deferrals are
per profile: 30 fixtures carry the `deferred-2.7.2` marker (`add-group`,
`add-option-conflicts`, `cache-all-path`, `cache-all-platforms`,
`cache-path-removed`, `cache-rerun-existing-cache`,
`check-frozen-extra-locked-spec`, `check-frozen-locked-version-mismatch`,
`check-frozen-missing-locked-spec`, `check-path-removed`,
`config-deprecated-get`, `config-get-user-cache`,
`doctor-default-cli-command`, `gem-default`, `gem-did-you-mean`, `gem-no-git`,
`gem-questionnaire`,
`git-submodules`, `install-force-ruby-platform-locked`,
`install-path-source-app-cache-first`, `issue-no-gemfile`,
`path-cache-multi-gemspec`, `path-cache-out-of-project`,
`path-package-multi-gemspec`,
`plugin-source-disabled`, `pristine-name-suggestion`, `removed-viz`,
`update-group-missing`, `update-group-present`, `update-name-suggestion`)
and 5 for 4.0.24 (`cache-all-platforms`, `git-submodules`, `issue-no-gemfile`,
`plugin-source-disabled`, `show-outdated-verbose-272`); marker
`deferred-<version>`, `script/differential:794-795`. It compares exit codes,
stdout/stderr, the project tree, and optional content probes —
`installed-tree` (`:622`), `first-line` (`:633`), `file-equals` (`:646-661`),
`file-contains` (`:666-679`) and `file-absent` (`:686-697`).

Glob patterns such as `*.gemspec` are expanded by the Windows `ruby.exe` argv
layer before Bundler sees them; Bundler itself stores the `glob` option verbatim
(`dependency.rb:55-59`) and writes it back verbatim (`injector.rb:119`).
Celerite does not emulate that argv-level expansion, so `cmd.exe` invocations of
`celerite add --glob *.gemspec` differ from the reference, while
`script/differential` expands in bash first and both sides agree.

### M8 Rails final benchmark

The final Rails benchmark is Linux-only and manual. Use the committed full SHA as
`baseline_sha`; the driver rejects a dirty worktree or any other HEAD. It requires
Crystal 1.22.1, Ruby 4.0.6 and Bundler 4.0.24, probes YJIT off/on without fallback,
and runs the collector self-test before a smoke run:

```console
script/bench-m8 --mode smoke --baseline-sha "$(git rev-parse HEAD)" \
  --celerite "$PWD/bin/celerite" --ruby "$(command -v ruby)" \
  --bundle-exe "$(command -v bundle)" --scratch "$PWD/.tmp-scratch/m8" \
  --out "$PWD/.tmp-scratch/m8-artifacts" --self-test

script/bench-m8 --mode smoke --baseline-sha "$(git rev-parse HEAD)" \
  --celerite "$PWD/bin/celerite" --ruby "$(command -v ruby)" \
  --bundle-exe "$(command -v bundle)" --scratch "$PWD/.tmp-scratch/m8" \
  --out "$PWD/.tmp-scratch/m8-artifacts" --jobs 4
```

Omit `--mode smoke` for the final matrix: cold/hot/noop × YJIT off/on, warmup=1
and n=5. Only a validated summary is a performance result; missing metrics,
timeouts, nonzero exits or parity failures produce no summary. Artifacts include
raw samples, logs, manifests, validator output and checksums under the current
run/attempt/baseline SHA. The `M8 Rails final benchmark` workflow is
`workflow_dispatch`-only and does not run on push. Its final CI result and Linux
Rails/YJIT measurements are not yet verified in this checkout; historical Windows
samples and task-255 artifacts are not a substitute.

## License

MIT. Celerite is an independent project and is not affiliated with the Bundler
or RubyGems teams.
