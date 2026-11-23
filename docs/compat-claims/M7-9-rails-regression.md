# M7-9 Rails 规模真实项目回归（claims）

本文件是 M7-9 的断言账本：把 `../compat-evidence/2026-11-14.md` 与 `../roadmap-evidence/M7-9-rails-regression.md` 里已取证的产品侧结论逐条固化为可复跑断言。原始建档、逐字输出与本机夹具仍留在 evidence，本文件只写结论与判据；度量见 `../compat-report.md`。

## C-M7-9-001 `VersionUnion` 的区间扫描不再提前耗尽无上界一侧，多 `!=` 排除的 union 保持完整

- 状态：已实现
- 参考行为（4.0.24）：`vendor/reference/v4.0.24/pub_grub/version_union.rb:69` 的 `def intersects?(other)` 与 `:112` 的 `def intersect(other)` 均用 `if !my_range.max || other_range.empty? || (other_range.max && other_range.max < my_range.max)` 决定推进哪一侧，无上界的一侧不会在另一侧耗尽前被丢弃
- 我方行为：`src/celerite/resolver/ranges.cr:467` `def intersects?(other : VersionRange) : Bool` 与 `:505` `def intersect(other : VersionRange) : VersionRange` 改为「先判 my 无上界则前进 other；再判 other 无上界则前进 my；否则按上界小者前进」；`src/celerite/resolver/solver.cr:539` 的 `CELERITE_SOLVER_DEBUG` 诊断出口默认关闭，`(derived conflict)` 文本不变
- 判据：`crystal spec spec/m7_resolver_version_union_intersect_spec.cr`
- 边界：只覆盖 `!=` 多排除导致的 union 截断形态（rails 8.0.2 的伪冲突根因）；判据本轮未执行，仅核实文件存在
- 生效：M7(9) H1 轮（2026-11-14）
- 取代：无

## C-M7-9-002 锁文件按本地平台变体物化，不退回 ruby 变体

- 状态：已实现
- 参考行为（4.0.24）：`vendor/reference/v4.0.24/resolver/resolver.rb:257` 的 `def all_versions_for(package)` 为每个版本同时建 ruby 候选（`:293` `priority: -1`）与平台候选（`:300` `priority: 1`）
- 我方行为：`src/celerite/resolver/source.cr:278` 新增 `def self.select_variant(specs : Hash(String, Array(IndexSpec))?, name : String, version : Gem::Version) : IndexSpec?`；`src/celerite/resolution.cr:1891` 新增 `private def platform_mergeable?(specs : Array(Resolver::IndexSpec)?) : Bool`，`:1923` 按 `candidate_version.priority == 1 || platform_mergeable?(same_version)` 走平台变体查找。修复前 `decisions_to_specs` 硬编码 `platform_ruby?` 查找，丢弃已选平台变体
- 判据：`crystal spec spec/m7_platform_variant_selection_spec.cr`；`bash script/differential platform-variant-fail multi-platform-lock`
- 边界：rails 8.0.2 实测夹具只在 `C:\temp\rails-min\`，不入库；本机平台为 `x64-mingw-ucrt`，其它平台组合未覆盖
- 生效：M7(9) K 轮（2026-11-14）
- 取代：无

## C-M7-9-003 Rails 8.0.2 真实应用的端到端安装未通过，该 profile 的兼容声明未恢复

- 状态：已取代
- 参考行为（4.0.24）：`bundle _4.0.24_ lock` 对只含 `source "https://rubygems.org"` 与 `gem "rails", "8.0.2"` 的项目 exit 0 并写出锁文件
- 我方行为：`celerite lock` 在同一夹具上 exit 0，DEPENDENCIES / PLATFORMS / BUNDLED WITH 三段与参照逐字节一致；`celerite install` 在原生扩展构建处被宿主限制阻塞（未为此改 `src/`）
- 判据：`bash script/differential install-check`（同形态的入库回归门禁；rails 规模夹具不入库，端到端无入库判据）
- 边界：夹具仅存于本机 `C:\temp\rails-min\`，不可从仓库复现；msys Low-IL 的 `0xC0000022` 与原生扩展构建属宿主环境阻塞。判据只覆盖差分门禁，不构成该 profile 的兼容声明，故记未验证
- 生效：M7(9) 期间（2026-11-14 / 2026-11-16 / 2026-11-19 三轮探测）
- 取代：C-M7-9-005

## C-M7-9-004 锁文件渲染不在 GEM 段列出 bundler 自身，其 CHECKSUMS 条目由自校验块唯一写出

- 状态：已实现
- 参考行为（4.0.24）：`vendor/reference/v4.0.24/lockfile_generator.rb:44-51` 的 `def add_specs(specs)` 按 `specs.sort_by(&:full_name)` 写出 GEM specs，并以 `next if spec.name == "bundler"` 跳过 bundler 自身
- 我方行为：`src/celerite/resolution.cr:2347` GEM 段构造用 `.reject(&.name.==("bundler"))`；`:2455` CHECKSUMS 段同样 `.reject(&.name.==("bundler"))`；`:2482` bundler 自校验条目只在 `!profile_is_2_x?` 分支唯一写出；`:2485-2492` 按 (name, version, platform) 去重，`:2496` 剔除 2.7.x profile 的 bundler 条目
- 判据：`bash script/differential lock-normalize`；`crystal spec spec/m7_lock_rewrite_fidelity_spec.cr`
- 边界：只覆盖锁文件写出路径；rails-min 上的逐字节对照依赖不入库夹具，形态以差分夹具为准；判据本轮未执行，仅核实文件存在
- 生效：M7(9) K'' 轮（2026-11-14）
- 取代：无

## C-M7-9-005 rails 8.0.2 规模下锁已完整时 `install` 不再把锁收缩成 1 条 spec，装出的 gem 集合与 oracle 锁一致

- 状态：已实现
- 参考行为（4.0.24）：`bundle _4.0.24_ install` 在锁已覆盖 Gemfile 依赖时按锁安装，不重写 GEM 段的 spec 集合，装完打印 `Bundle complete! 1 Gemfile dependency, 64 gems now installed.`
- 我方行为：`src/celerite/resolution.cr:1504` 在 `lockfile_covers_dependencies?` 的 spec 依赖边循环里 `next if edge.name == "bundler"`，`:1411` 由 `reuse_locked_resolution?` 调用，故 rails 的 `bundler (>= 1.15.0)` 边不再让完整锁被判为未覆盖而重跑解析；`install` 保留锁的 spec 集合并按锁安装。
- 判据：`bash script/differential install-check`；端到端复跑步骤与原始数字见 `../roadmap-evidence/M7-9-rails-regression.md` 的 task-174 节
- 边界：rails 夹具不入库（本机 `C:\temp\rails-min\`），端到端结论不可从仓库复现，入库判据只覆盖同形态的差分门禁。两次运行中一次在 `make` 缺失处 exit 5 且锁未被改写，一次 exit 0；锁字节与 spec 行数同 oracle，spec 依赖行次序有 16 处不同但内容等价。原生扩展构建仍受宿主限制。
- 生效：task-174（72398c0）
- 取代：C-M7-9-003

## C-M7-9-006 rails 规模安装树的集合级内容与 `check`/`exec` 语义两侧一致，但逐文件字节仍存未解释差异，该 profile 兼容声明未恢复

- 状态：未验证
- 参考行为（4.0.24）：`bundle install` 在同一把锁下装出 64 个 gem（`Bundle complete! 1 Gemfile dependency, 64 gems now installed.`），`bundle check` 打印 `The Gemfile's dependencies are satisfied` 并 exit 0，`bundle exec` 能 `require "rails"` 得到 `8.0.2`，`bundle binstubs railties` 写出 `bin/rails` + `bin/rails.cmd`
- 我方行为：`celerite install` 在同一把锁下装出同样的 64 个 gem 目录、64 个 gemspec、64 个 `.gem`、28 条 `extensions/` 路径、22 个 `.so`、24 个 `bin/` 文件，集合级与参考侧完全相等；`celerite check` exit 0 且输出逐字相同；`celerite exec ruby` 同样得到 `8.0.2`；`celerite binstubs railties` 产物逐字节相同。但逐文件比对仍有 5 类未解释差异：`plugins/rdoc_plugin.rb` 仅参考侧存在（我方未实现 RubyGems 写 plugin）、12 个 `bin/*.bat` 为 LF 而参考为 CRLF、14 个 `.so` 因扩展构建时 `gcc` 解析到不同发行版（内嵌 `GCC: (Rev6…) 16.2.0` vs `GCC: (Rev5…) 16.1.0`）而字节不同、13 个构建日志因 `assets/bridge/server.rb:551` 未传 `build_jobs`（`make` vs `make -j3`）而不同、`binstubs rails` 候选清单少 `bundler has: bundle, bundler`
- 判据：`bash script/differential install-check`（入库门禁，同形态 install；本轮未执行）；端到端判据为两侧各一次 `celerite install` / `bundle install`（隔离 `BUNDLE_PATH`/`BUNDLE_USER_HOME`/`SSL_CERT_FILE`，`PATH` 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;C:\Ruby40-x64\msys64\usr\bin`），再跑 `celerite check` / `bundle check`、`celerite exec ruby -e "require 'rails'; puts Rails::VERSION::STRING"`、`celerite binstubs railties`，安装树用 `Get-ChildItem -Recurse -File` + SHA256 `Compare-Object`；原始命令、输出与计数见 `../roadmap-evidence/M7-9-rails-regression.md` 的 task-194 节
- 边界：rails 规模探针不入库（本机 `C:\temp\celerite-t194\.tmp-scratch\probe-cel` / `probe-ref`），端到端结论不可从仓库复现；本轮无入库判据，未跑 `script/differential` 与全量 `crystal spec`。扩展构建前 PATH 的改写者未定位，故 `.so`/日志的差异只证明「工具链不同」不证明「不可归零」。两侧 install 耗时 705 s / 148 s 不可互为基线。未覆盖 Linux 与其它 Ruby ABI。因未解释差异 ≠ 0，本断言不判「已实现」，`docs/roadmap.md:149` 的复选框不勾选
- 生效：task-194（基线 `954f2d5`）
- 取代：无，补充 C-M7-9-005 的锁外维度
