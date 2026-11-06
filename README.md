# Celerite

A high-performance, Bundler-compatible Ruby dependency manager written in Crystal.

> **Status: design and scaffolding.** Celerite is not yet a working Bundler
> replacement. Compatibility is a release gate, not a claim based on parsing
> common Gemfiles.

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

## Development

Requires Crystal 1.21.1 or newer.

```console
shards build
crystal spec
shards build
bin/celerite --version
```

Only `celerite version`, `celerite --version`, `celerite help`, and
`celerite --help` are implemented in this scaffold. Other commands fail fast.

## License

MIT. Celerite is an independent project and is not affiliated with the Bundler
or RubyGems teams.
