# Celerite

A high-performance, Bundler-compatible Ruby dependency manager written in Crystal.

> **Status: M0+M1 complete (read-only locked path).** Celerite reads lockfiles,
> validates project state, and runs the locked-path versions of `check`,
> `list`, `show`/`info`, `platform`, `lock --print`, and `config get` — all
> verified byte-for-byte against pinned reference Bundlers via the differential
> harness. Resolution, installation, and the Ruby bridge are next (M2+).
> Compatibility is a release gate, not a claim based on parsing common Gemfiles.

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

Platform gems are built per release (`script/release` produces both the
dist bundle and the gem). Build the gem for the current platform locally:

```console
script/gem            # builds pkg/celerite-<version>-<platform>.gem
gem install --local pkg/celerite-<version>-<platform>.gem
```

The gem ships the native binary plus the Ruby bridge; the installed shim
locates your Bundler gem automatically and exports the bridge environment
(`CELERITE_BRIDGE_SERVER`, `CELERITE_REFERENCE_BUNDLER_LIB`,
`CELERITE_PROFILE_BUNDLER_VERSION`). A bare `gem build celerite.gemspec`
produces a metadata-only gem — always build through `script/gem`.

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
