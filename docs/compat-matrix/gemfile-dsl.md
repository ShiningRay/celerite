# Gemfile DSL — reference: Bundler 4.0.24 / 2.7.2

Target path: **Ruby compatibility bridge** (`evaluate_gemfile` protocol op).
Celerite never reimplements Gemfile evaluation as static parsing — the Gemfile is
executable Ruby (architecture constraint 1). This matrix fixes the *observable
effects* the bridge must report back to the native core.

## Methods

| Method | Observable effect | Notes |
|---|---|---|
| `source(url, options = {})` / block | current default source; `options` become lockfile options (`type:`, `mirror`…) | multiple sources allowed; block-scoped |
| `source :rubygems, :git, :path` (symbols) | sets source priority order | 4.x validates symbol set |
| `ruby(spec)` | records Ruby engine/version constraint; fails install when unmet | string or `RUBY_VERSION` interpolation |
| `gem(name, *reqs, options = {})` | adds dependency with requirement list | req strings parsed by Gem::Requirement semantics; option `require:` affects runtime only |
| `gemspec(options = {})` | adds deps of local gemspec(s); `name:`, `path:`, `development_group:` | path resolution relative to Gemfile |
| `group(*names, &block)` | groups following gems | nested groups union |
| `groups` / `group` without block | introspection inside Gemfile | |
| `platforms(*plats, &block)` | conditional gems | `mri`, `jruby`, `rbx`, `ruby`, `mswin`, `mswin64`, `mingw`, `x64_mingw`, `windows` shortcuts |
| `platform(plat, &block)` | singular alias | |
| `env(name, &block)` | conditional on `ENV[name]` | value defaults to "true" |
| `install_if(&block)` | conditional gems | evaluated at resolve time |
| `git_source(name, &block)` | custom git shortcut | `github:`, `gist:`, `bitbucket:` are predefined |
| `github(user/repo, options)` | → git source | 4.x warns/behaves on protocol options |
| `path(p, options = {}, &block)` | scoped path source | |
| `git(url, options = {}, &block)` | scoped git source | `branch:`, `tag:`, `ref:`, `submodules:`, `glob:` |
| `plugin(name, options)` | plugin-declared source | appears as `PLUGIN SOURCE` in lockfile |
| `file(name, *groups)` / `eval_gemfile(path)` | include another Gemfile | `file` 4.x alias of eval_gemfile with groups |

## Cross-version deltas

- 4.x raises on unknown DSL method names instead of silently ignoring (NoMethodError
  from Ruby is already the default — parity comes free via the bridge).
- `x64_mingw` platform alias resolves to `x64-mingw-ucrt` in modern references.
- Source priority: `source` symbols form an ordered list; later `source` calls append;
  git/path sources always take precedence over remote sources for matching gems.

## Bridge contract

`evaluate_gemfile` returns, for the resolved Gemfile + env:

- ordered dependencies: name, requirement strings, groups, platforms, source binding,
  install-if results;
- source list in declaration order with options;
- Ruby constraint;
- plugin declarations;
- an evaluation fingerprint (inputs: Gemfile content, env vars read via a wrapped
  `ENV`, referenced gemspec files, bundled gem versions) so the native core can skip
  re-evaluation when nothing changed (M2+).
