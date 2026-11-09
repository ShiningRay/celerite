# Celerite

A Crystal-native Bundler-compatible dependency manager, with a controlled Ruby
compatibility boundary. Performance is a measured goal, not an unconditional claim.

> **Status: native resolution and installation paths exist; full compatibility is
> not yet accepted.** Crystal implements the core version/requirement model,
> PubGrub, Compact Index, lockfiles, downloads/checksums and basic installation.
> Ruby still handles dynamic Gemfile/gemspec evaluation, native extension builds,
> plugin hooks and parts of the runtime through the compatibility bridge.
>
> The current roadmap prioritizes correctness and trustworthy upstream evidence
> (M7), then batch bridge calls and no-Ruby cache hits (M8), native install plans
> and a lightweight runtime (M9). Embedding Crystal as a Ruby native extension is
> an optional later spike (M10), not the default architecture. See
> [the compatibility report](docs/compat-report.md) for measured coverage and
> known gaps rather than treating command names as completed functionality.

## Goals

- Preserve Bundler's observable behavior: Gemfiles, lockfiles, CLI, installation,
  runtime setup, and plugins.
- Move dependency resolution, Compact Index processing, downloads, verification,
  and installation planning into native Crystal code.
- Keep a controlled Ruby compatibility bridge for arbitrary Ruby DSL, native
  extension builds, and third-party Bundler plugins.
- Verify behavior with differential tests and the upstream Bundler test suite.

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
- [兼容矩阵基线](docs/compat-matrix/README.md) — per-version feature lists generated
  from pinned upstream sources ([manifest](vendor/reference/MANIFEST.md))

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

Requires Crystal 1.21.1 or newer.

```console
shards build          # build bin/celerite
crystal spec          # unit + property + behavior specs
crystal tool format --check src spec
script/differential   # differential harness vs pinned reference Bundlers
```

Reference Bundler versions (4.0.24 and 2.7.2) must be installed for the
differential harness: `gem install bundler -v 4.0.24 -v 2.7.2`. The harness runs
each fixture in isolated sandboxes (no network) and compares exit codes,
stdout/stderr, and the project file tree after path normalization.

## License

MIT. Celerite is an independent project and is not affiliated with the Bundler
or RubyGems teams.
