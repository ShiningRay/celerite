# M7(5) Git/path/monorepo/私有 source/离线/平台

<!-- 源：docs/roadmap.md（治理前 218 行，2026-11-22）。以下为该处追加流水的逐字迁出，仅按追加边界重新分行，未修改任何文字。 -->

<!-- 原 roadmap.md 行 158 -->

（2026-11-15：装具 `git-init` 暂存路径缺陷已修——`mktemp -d "$work/gitstage.XXXXXX"` + `cygpath -w` 传给 `git -C`，`add-git`/`add-ref` 双 profile 由 FAIL 转 PASS；`git-installed-discovery`/`git-path-install`/`git-pristine`/`plugin-git-local`/`plugin-git-local2` 仍因本机 celerite 子进程 msys shm `0xC0000022` 失败，属环境，干净环境未验证。

**2026-11-15 补：新增 `git-tag` 装具清单（暂存仓库上打 tag）与夹具 `git-tag`/`git-glob`，取到参考 oracle（`tag:` 与 `glob: gems/*/*.gemspec` 的锁文件形态）；celerite 侧两项均在克隆阶段被同一 `0xC0000022` 环境缺陷挡住，因此两例计入失败桶（4.0.24 全量 `129 passed, 15 failed, 1 skipped`），`tag:`/`glob:` 语义仍**未验证**；`git-submodules` 仍为 documented SKIP（参考侧被 git ≥2.38 submodule file-transport 挡住）。

**2026-11-15（根因定位）：上述 13 例差分与全量 spec 的 4 个 `Celerite::GitSource` error 共同根因是**执行完整性级别**——工作区内的 Crystal 产物以 Low IL（`S-1-16-4096`）运行，其启动的 msys `sh.exe` 无法创建 `\BaseNamedObjects\msys-2.0S5-<hash>`（`0xC0000022`；`sh` 自身初始化失败为 `0xC0000142`），bash 直跑 git 为 Medium（`S-1-16-8192`）故正常；探针矩阵 A–H 与判定见 ``docs/compat-evidence/2026-11-15.md``「2026-11-15 M7(5)/M7(8) 环境失败根因」节。属环境，非产品缺陷，未改产品代码，需在放行环境复跑。**；2026-11-15（M7(5) --local/--prefer-local）：已实现——`--local` 只认已安装 gems + `vendor/cache`（不查任何索引，含 file://），缺失即参考消息 exit 7；`--prefer-local` 本地优先、失败回落；5 例 spec + `install-local` 差分双 profile PASS（详见 `docs/compat-evidence/2026-11-15.md` 同名节）。**；

**2026-11-16 补（`glob:` 锁文件行与 GIT 源选项顺序，属「多个 gemspec、monorepo」）**：`src/celerite/resolution.cr` 新增 `DEFAULT_GLOB = "{,*,*/*}.gemspec"` 与纯函数 `Resolution.git_lock_options`/`Resolution.path_lock_options`（参考 `source/path.rb:14,45-49`、`source/git.rb:53-61`），`generated_lockfile` 的 PATH 段现在写 `  glob: <glob>`（仅非默认值时）、GIT 段选项顺序修正为 `ref, branch, tag, submodules, glob`（原为 `branch, tag, ref` 且无 glob）；证据：`spec/m7_source_lock_options_spec.cr` 5/0/0，差分 `fixtures/differential/path-glob-monorepo` 4.0.24/2.7.2 双 PASS（负对照把 glob 恒抑制 → `file-contains differs … needle=  glob: gems/*/*.gemspec`），全量 413/0/4；**未验证**：GIT `glob:` 无差分夹具（本机 celerite 子进程 msys `sh.exe` 在 Low IL 下 `0xC0000022`，`git-glob` 仍卡在克隆阶段，环境），`glob:` 与非默认相对化/绝对路径组合、`cache`/`package` 对 monorepo glob 源的复制行为；私有 source 鉴权、磁盘错误与中断清理、Linux gnu/musl、多 ABI 仍未验证。

**2026-11-16 补（私有 source 鉴权失败映射）**: 按参考 `fetcher/downloader.rb:70-73` + 本地 oracle 实现——401 无凭据 → `AuthenticationRequiredError`（四行、host 形态、末行 `BUNDLE_127__0__0__1`）、401 带凭据 → `BadAuthenticationError`（两行）、403 无 `WWW-Authenticate` → 同 401 无凭据文案，三者均 exit 17 且不重试（原实现把 401 当空索引 → exit 7）；`spec/m7_authentication_errors_spec.cr` 4 例、端到端 ref/cel 三场景 stdout+stderr+exit 一致，全量 417/0/4；**未验证**：gem 下载 403 的 oracle、`~/.gemrc`/`Gem.configuration` 凭据源、`WWW-Authenticate: Basic` 变体、代理 CONNECT 后 401、`install`/`update`/`cache` 逐命令差分。2026-11-16 锁文件写入保留既有 CRLF：新增 `Lockfile.write`（`src/celerite/lockfile/writer.cr`，既有锁文件含 CRLF 时把孤立 LF 提升为 CRLF），三处写锁点改接；新 spec `m7_lockfile_line_endings_spec.cr` 4 例，全量 421/0/4；差分夹具 `lock-preserve-crlf` 双 profile 均 PASS（4.0.24 两侧 13 个 CR；2.7.2 按参考文本模式归一为 LF，`file-crlf` 按 profile 断言）。**）；2026-11-16 锁文件写入失败映射：只读锁文件 → `PermissionError`（exit 23、参考三行消息），`Lockfile.write` 捕获 `File::AccessDeniedError`，spec `m7_filesystem_errors_spec.cr` 4 例，全量 425/0/4（详见 `docs/compat-evidence/2026-11-16.md` 同名节）。；2026-11-16 `Dir.glob` 反斜杠模式：Crystal 1.22 Windows 下 `Dir.glob` 把 `\` 当转义符，`File.join` 拼出的模式恒空（同内容的 `/` 形式正常），新增 `Glob.paths`（`Dir.children`+`File.match?`）修复 5 处调用；`install --local` 直接从 `vendor/cache` 安装（不打印 `Fetching`，并打印 `Updating files in vendor/cache`），spec 3 例、差分 `install-local-vendor-cache` 双 profile PASS，全量 428/0/4（详见 `docs/compat-evidence/2026-11-16.md` 同名节）。

**2026-11-16 再补（扩展编译失败，属「磁盘错误与中断清理」）**：`Gem::Ext::BuildError` 现映射为 `InstallError`（status 5、80 列折行），消息按参考拼 `"<类>: <消息>\n"` + 真实回溯 + `An error occurred while installing <name> (<version>), and Bundler cannot continue.` + `In Gemfile:` 依赖树；半装目录（`gems/<full>`、`extensions/…/gem_make.out`）按参考**保留**，只删 `specifications/<full>.gemspec` 以保证 `installed?` 仍为假。桥新增 `error_class`/完整 `backtrace`；新增 `spec/m7_install_failure_spec.cr` 3 例（含两级依赖树），两次负对照分别落到 `2 failures`/`1 failure`，全量 431/0/4；回溯段是本实现真实栈（不伪造 Bundler 帧），故该场景不做差分夹具、改由 spec + 等长沙箱 A/B 逐行取证（详见 `docs/compat-evidence/2026-11-16.md` 同名节）。 

**2026-11-16 再补（扩展失败后的 bundle 缓存清理）**：扩展编译失败时参考不在 `<bundle>/cache/` 留 `.gem`，本实现原先保留（成功安装时两侧都保留，故上一轮「参考不复制」的登记已更正）；现于 `rescue ex : InstallError` 分支删除该缓存包，`spec/m7_install_failure_spec.cr` 增「失败无缓存」与「成功仍保留缓存」两断言（4 例），负对照 `if false && …` → `4 examples, 1 failures`（`:95`），A/B 两侧残留树 `exit=5 cache=[] gems=[fail-ext-0.1.0] specs=[]` 一致，全量 443/0/4。；2026-11-16 再补（文件系统错误映射，属「磁盘错误」）：新增 src/celerite/filesystem_errors.cr 的 FilesystemErrors.map（File::Error → 参考的 PermissionError/TemporaryResourceError(26)/NoSpaceOnDeviceError(31)/ReadOnlyFileSystemError(42)/OperationNotPermittedError(43)/OperationNotSupportedError(28)/VirtualProtocolError(27)/GenericSystemCallError(32)，EEXIST/ENOENT 原样抛出，Windows 侧映射 ERROR_DISK_FULL/ERROR_HANDLE_DISK_FULL/ERROR_WRITE_PROTECT/ERROR_ACCESS_DENIED），Lockfile.write 改接；spec/m7_filesystem_error_mapping_spec.cr 10 例、负对照 10 examples, 1 failures，全量 456/0/4；同轮全量差分复测 **160 passed, 16 failed, 2 skipped**（旧二进制 135/19/2），并修掉 cache --cache-path 开关泄漏（install_args_from_cache）与无 Gemfile 工程残留 .bundle（plugin_app_config_root + 空壳清理）两处真实缺陷，双 profile 各 6 夹具 PASS；**仍未修**：bundle add 的 --version/--group/--strict/--optimistic 开关（5 条差分 FAIL，下一轮）、cache --all-platforms 跨平台语义、removed-flag 专属文案与 Did you mean?、环境阻塞的 9 条 Low-IL 夹具；真实 ENOSPC/EROFS/EPERM 未在真机复现，filesystem_access 的其余调用点（下载缓存、bundle 目录创建）尚未接入映射。；2026-11-16 三补（bundle add 开关面 / bundle remove 消息，属 L157 的「不得静默忽略」）：add 先做未知开关校验（ADD_SWITCH_FLAGS/ADD_SWITCH_VALUES 对齐 cli.rb:404-426），--strict 与 --optimistic 并用时 exit 15 并给逐字消息，委托 install 前经 install_args_from_add 剔除 add 专属开关（此前 add --group 与 --version= 一律 exit 15）；索引探针改为静默 resolve 后按参考顺序打印 Fetching source index from <remote>/ 与 Resolving dependencies...；remove 消息改按 Gemfile 行的 requirement 原文拼 name (req) was removed.，Gemfile 已无 gem 行时把 The Gemfile specifies no dependencies 打到 stderr；并撤掉 remove 结束后的剪枝（参考不做，clean 才报 Removing <name> (<version>)；旧行为靠陈旧的 definition.lockfile! 缓存才没被 spec/m7_clean_spec.cr 抓到）。证据：新 spec/m7_add_remove_spec.cr 6 例、5 个新差分夹具、双 profile 各 10/10、4 条 add 命令逐字 A/B 相同、负对照 0 passed 2 failed（开关透传）与 4 examples 3 failures（剪枝回填）；全量 462 examples 0 failures 4 errors。仍未做：--github/--branch/--ref/--glob 组合语义、--cooldown、add --skip-install 的探针行、多 requirement 与 eval_gemfile 场景；4 个依赖 racc 的旧夹具仍受本机 msys Low-IL 阻塞。 

**2026-11-17 二十三补（gem 下载 403）**：`downloader.cr` 新增 `ForbiddenDownloadError`（status 5、`error_class_name` 为 `Bundler::HTTPError`），403 下载按 `Retry` 打三行 `Retrying download gem … (2/4|3/4|4/4)` 后抛错；`installer.cr` 拼 `An error occurred while installing <gem> (<ver>), and Bundler cannot continue.` + `In Gemfile:` 树并包成 `InstallError`(5)；`commands_install.cr` 用 `early_fetch`/`flush_early_fetch` 在首次重试通知时提前释放挂起的 `Fetching <gem>` 行，使 stdout 顺序与参考**逐字相同**。新 spec `m7_forbidden_download_spec.cr` 1/0（本地 `HTTP::Server` 服务真实索引、仅 `/gems/` 与 `/quick/` 回 403，断言 5 个空行尾），负对照 1 failure，全量 614 examples 0 failures 4 errors。仍未做：参考在 `Bundler::HTTPError` 之后打印的 ~20 行 Ruby 回溯不复刻（不做全量输出差分）、`Bundler::Retry` 的 jitter 未建模、`/quick/` 与 `/gems/` 的 403 未分别验证。 

**2026-11-19（task-36 补记）：path 源默认 glob 已对齐 `{,*,*/*}.gemspec`（A/B/E 命中、C/E2 未命中并按 `source at \`vendor/mono\`` 归属）；B/C 差分双 profile 与 10 项回归全绿。L158 仍未清零：git 三族（tag/submodules/glob）受 Low-IL `0xC0000022` 阻塞，私有 source 鉴权与磁盘错误只能 spec/未验证，默认 glob 深度上限未逐层铺夹具。复选框保持 `[ ]`。** 

**2026-11-19（task-39 漂移校正）：“默认 glob 深度上限未逐层铺夹具”已过期——默认已对齐且 C 负例存在；仍缺 E2（d1/d2）与更深的逐层夹具。复选框保持 `[ ]`。** 

**2026-11-20（task-44a 补记）：`check` 重写保留 PATH/GIT/PLUGIN SOURCE 段与既有 CHECKSUMS，Gemfile 无 `source` 行时 GEM 段不带 `remote:`；新 2 夹具 + 2 examples 双 profile 全绿，负对照 0 passed/2 failed。复选框保持 `[ ]`。

**（2026-11-20（task-44b 补记）：PATH 源身份不含 `glob:`（两侧都展开为绝对路径再比），`glob` 变化是否重解改由「锁侧 path+glob 下可见 gemspec 的 name/version 集」判定；frozen `check` 只在可见集真变时报 16（4.0.24）/ 1（2.7.2），glob-only 变化 exit 0；新增桥接 op `load_gemspec_dir_specs`，4 夹具 + spec 重写双 profile 全绿，负对照 0 passed/4 failed；复选框保持 `[ ]`。） 

**2026-11-20（task-46 补记）：PATH 源改为按 gemspec 自身 name 匹配（`source/path.rb:159-179`），桥 `load_gemspec_dir` 增 `name` 参数、未命中即报错，不再用首个 gemspec 伪造同名 spec；PLUGIN 源未命中归属改为参考串 `plugin source for <type> with uri <uri>`（`plugin/api/source.rb:293-296`）；2 新夹具（`path-source-missing-gem`/`plugin-source-missing-gem`，断言不写锁）双 profile PASS，负对照双 profile 均 FAIL；GIT 归属未验证。复选框保持 `[ ]`。** 

**2026-11-21（判据重写，判据见 L155 的同类记录）：已实现且有证据——差分：install-local、install-local-vendor-cache、install-local-index-unreachable、path-glob-monorepo、path-glob-default-root、path-glob-default-nested、path-glob-default-deep-miss、path-source-missing-gem、plugin-source-missing-gem、lock-preserve-crlf、path-gemspec-bump-reresolves、check-frozen-path-gemspec-bump、path-locked-glob-wins；spec：m7_source_lock_options_spec（5）、m7_authentication_errors_spec（4）、m7_installed_discovery_spec（23）、m7_lockfile_line_endings_spec（4）、m7_filesystem_error_mapping_spec（12）、m7_install_failure_spec（4）（复跑：`crystal spec spec/<name>.cr`；差分 `CELERITE_BIN=bin/celerite.exe bash script/differential <夹具名>`，双 profile 追加 `BUNDLER_REF_VERSION=2.7.2`。）。仍缺（真未实现）——私有 source 的 `~/.gemrc`、`WWW-Authenticate: Basic` 与代理 CONNECT 401 未做；`cache`/`package` 对 monorepo glob 源的复制未覆盖；GIT 未命中归属只在 spec 级（`source/git.rb:92-102` `uri_with_specifiers`）。本机不可验证——git tag/submodules/glob 三族（夹具 git-tag、git-glob、git-submodules 在 Crystal 进程树下撞 msys `sh.exe` 的 `NtCreateDirectoryObject … 0xC0000022`）；磁盘 ENOSPC/EROFS/EPERM 真机注入未复现，`filesystem_access` 仍有未接映射的调用点。不勾选依据：git 三族无法在本机取证，鉴权与磁盘注入未实现。** 

**2026-11-21（task-84 补记）：`cache`/`package` 对工程外 `path` 源的整目录复制已实现——参考 `source/path.rb:84-96` 在 `cache_all` 打开（4.x 默认 true，`settings.rb:88`）且源在工程外时 `rm_rf` 后 `cp_r` 到 `<cache>/<gem name>/` 并 `touch .bundlecache`，工程内源跳过；我方 `run_cache` 原先只拷 `#{full_name}.gem`。装具新增 `sibling/`（夹具目录下 `sibling/<rel>` 复制到 `<sandbox>/<rel>`，供工程外 path 源夹具使用）。差分 `cache-all-path` 4.0.24 PASS、2.7.2 `deferred-2.7.2`（2.7.2 的 `cache` 固定写 `cache_all: false`，不复制）；`cache-no-all-path` 双 profile PASS；负对照 `dab70e3` 上 `cache-all-path` 报 `Only in SANDBOX/project/vendor/cache: pgem`。`glob:` 多 gemspec 的 path 源复制本轮未取 oracle，仍挂账。** 

**2026-11-21（task-85 补记）：`~/.gemrc` 的 `:http_proxy` 参考会读——`fetcher.rb:262`/`:313-316` 取 `Gem.configuration[:http_proxy]`，`:no_proxy` 直接关闭代理；实测优先级 gemrc > `http_proxy` env >（`.bundle/config` 的 `proxy`/`http_proxy` 参考根本不用，我方仍读，记为已声明差异）。我方 `Proxy.resolve` 已补 gemrc 解析（键可写 `:http_proxy` 或 `http_proxy`），装具新增 `home/`（夹具 `home/<rel>` 落到两侧 `$HOME`）。差分 `lock-gemrc-proxy`（exit 17，无锁）与 `lock-gemrc-no-proxy`（exit 0）双 profile PASS，负对照 `37ede89` 上前者 FAIL（`celerite=0`、`Gemfile.lock` 被写出）。另注：`~/.gemrc` 的 `:sources` 参考全库仅在 `plugin.rb:8` 里作为文档串出现，**不读**，故不列为缺口。** 

**2026-11-21（task-87 补记）：install/update/add 现按参考 `Runtime#cache` 刷新工程内 `vendor/cache`（`cli/install.rb:52-53`、`cli/update.rb:82`、`cli/add.rb:29`；`--no-cache`、frozen、目录不存在时跳过），逐包打印 `  * <file>.gem`；装具新增 `file-exists` 断言原语。`cache`/`package` 对 monorepo glob 源的复制仍挂账。** 

**2026-11-21（task-88 补记）：首次 `bundle install` 已能把工程外 `path` 源整目录复制进 `vendor/cache`（此前只在已有锁时才复制）；`Bundled gems are installed into` 对绝对 `BUNDLE_PATH` 改为保留配置原样（含反斜杠），相对值仍补 `./`。** 

**2026-11-21（task-97 补记）：`BUNDLE_ONLY`/`settings[:only]` 已按 `groups - without - optional + with` 与 `only` 求交（安装/列表/check 只看交集，锁文件仍记全量）；`update --all` 在 `BUNDLE_WITHOUT` 下补印 `Gems in the group 'x' were not updated.` 且不再安装被排除组。差分 4.0.24 6/0、2.7.2 4/0，负对照 0/4。** **（task-102：check 自愈 PATH 段缺 spec/版本漂移，5 形状手工 oracle 见 `docs/compat-evidence/2026-11-21.md`。）** **（回修：仅路径段真实漂移才宣告解析；新增 C 形态护栏夹具。）**

## 2026-11-23：path 源 gemspec glob 的逐层深度边界（task-145）

### oracle

path 源默认 glob 相对**路径源根目录**展开，四种目录层数各取一形，双 profile 逐字同判：

| 夹具 | 布局（相对 path 源根 `vendor/mono`） | 子目录层数 | exit | 结果 |
|---|---|---|---|---|
| `path-glob-default-root` | `mono_a.gemspec` | 0 | 0 | 命中，PATH 段 `remote: vendor/mono` + `specs: mono_a (0.1.0)` |
| `path-glob-depth-one` | `d1/mono_a.gemspec` | 1 | 0 | 命中，锁全文等于同深度 `gems/` 形态 |
| `path-glob-default-nested` | `gems/mono_a.gemspec` | 1 | 0 | 命中，锁全文逐字断言 |
| `path-glob-depth-two` | `d1/d2/mono_a.gemspec` | 2 | 7 | **未命中**，stderr `Could not find gem 'mono_a' in source at \`vendor/mono\`.` |
| `path-glob-default-deep-miss` | `gems/mono_a/mono_a.gemspec` | 2 | 7 | 未命中，路径源归属文案同上 |
| `path-glob-depth-three` | `d1/d2/d3/mono_a.gemspec` | 3 | 7 | 未命中，路径源归属文案同上 |

边界判据：**命中 ≤ 1 层子目录，≥ 2 层未命中**。与默认 glob 的三支展开一一对应——`{,*,*/*}.gemspec` 展开为 `.gemspec`（字面名）、`*.gemspec`（0 层）、`*/*.gemspec`（1 层），第 2 层起无任何分支可达，故深度是**硬上限**而非贪心/递归搜索。

`d1` 与 `gems` 两种目录名同深度同判，说明命中与否只取决于**层数**，与目录字面名无关（`path-glob-monorepo` 的显式 glob `gems/*/*.gemspec` 命中 2 层则是另一种形态：显式 glob 可越默认上限）。

### 参考锚点

- `bundler-4.0.24/lib/bundler/source/path.rb:14` `DEFAULT_GLOB = "{,*,*/*}.gemspec"`；`:19` `@glob = options["glob"] || DEFAULT_GLOB`。
- `bundler-4.0.24/lib/bundler/source/path.rb:159-164` `load_spec_files`：目录存在则 `SharedHelpers.glob_files_in_dir(@glob, expanded_path).sort_by { |p| -p.split(File::SEPARATOR).size }`，逐文件 `load_gemspec`，不做递归下降。
- `bundler-4.0.24/lib/bundler/shared_helpers.rb:242-246` `glob_files_in_dir(glob, base_path)` → `Dir.glob(glob, base: base_path)`，即 glob 相对路径源根求值。
- `bundler-4.0.24/lib/bundler/source/path.rb:48` 仅当 `@glob != DEFAULT_GLOB` 才把 `glob:` 写进锁；`:52-54` `to_s` = ``source at `<path>` ``（未命中归属文案的来源）。

### 实现位置

- `src/celerite/resolution.cr:2298` `DEFAULT_GLOB = "{,*,*/*}.gemspec"`（注释 `:2295-2297` 锚 `source/path.rb:14`）；`:2296` 默认值不落锁；`:2310-2311`、`:2320-2321` 非默认才追加 `glob` 选项。
- `src/celerite/resolution.cr:613-617` `load_source_gem_spec` → `@bridge.not_nil!.load_gemspec_dir(dir, glob || DEFAULT_GLOB, name)`（显式传参，不走桥 fallback）。
- `src/celerite/resolution.cr:1457`、`:1679` 锁侧/源侧 `section.option("glob").as?(String) || DEFAULT_GLOB`；`:1460` `load_gemspec_dir_specs`；`:2086` 取源 glob。
- `assets/bridge/server.rb:564` `SOURCE_DEFAULT_GLOB`（注释 `:560-563` 要求与 `Resolution::DEFAULT_GLOB` 同步）；`:574-575`、`:601-604` `Dir.glob(File.join(dir, glob))` + 按路径段数降序，与参考同形；`:614` 另一处同法。

### 证据

- 新增夹具双 profile 原始结果行：`PASS path-glob-depth-one (exit=0)`、`PASS path-glob-depth-two (exit=7)`、`PASS path-glob-depth-three (exit=7)`，每个两侧均为 `differential (4.0.24): 1 passed, 0 failed, 0 skipped (documented deferrals)` 与 `differential (2.7.2): 1 passed, 0 failed, 0 skipped (documented deferrals)`，`harness-exit=0`。
- 新夹具断言组合：`file-equals-4.0.24` / `file-equals-2.7.2`（`path-glob-depth-one`，锁全文逐字）、`stderr-contains`（`depth-two`/`depth-three`，路径源归属文案）、`file-absent`=`Gemfile.lock`（`depth-two`/`depth-three`，证未命中时**不写锁**）、stdout 逐字与项目树路径比较（装具默认，两侧同判）。
- 既有三个 path-glob 夹具复跑未受影响：`path-glob-default-root` exit 0、`path-glob-default-nested` exit 0、`path-glob-default-deep-miss` exit 7，4.0.24 与 2.7.2 双 profile 各 `1 passed, 0 failed`。
- `spec/m7_path_glob_default_spec.cr` 已在 spec 级覆盖 0 层命中与 2 层未命中；本轮补的是**差分级逐层夹具**（`docs/compat-evidence/2026-11-19.md:996` 挂账的「未为每个深度单独建夹具」）。
- 本条同时结清本文档 `:25`（task-39 漂移校正）遗留的「仍缺 E2（d1/d2）与更深的逐层夹具」：E2 对应 `path-glob-depth-two`（exit 7），更深对应 `path-glob-depth-three`（exit 7），oracle 表 E 行的 `d1/` 目录名形态对应 `path-glob-depth-one`（exit 0）。上行原文保留为历史记录，不删改。

### 已声明差异

- **本轮未发现新的 cel/参考分歧**：三个深度上双方 exit 与 stderr 判据一致，未改任何产品代码。
- 实测与既有 oracle 一致，无口径修正：`docs/compat-evidence/2026-11-19.md:979` 记 E2（`vendor/mono/d1/d2/mono_a.gemspec`）为 exit 7，本轮 `path-glob-depth-two` 同名同深同判；`:978` 记 E 行（`vendor/mono/d1/mono_a.gemspec`）为 exit 0，本轮 `path-glob-depth-one` 复现。task-36 的 oracle 表未把 E2 记成命中，本轮不涉及对该表的更正。
- 沿用 task-36 已声明差异，未在本轮重测：仅 PATH 归属改 `source at`，GIT/PLUGIN 未命中仍为 rubygems 文案；`file://` 参考索引须含 `specs.4.8.gz`；私有 source 鉴权与磁盘错误未验证；本机 git 族仍受 Low-IL `0xC0000022` 限制。
- 未覆盖：显式 `glob:` 越过默认上限的逐层形态只由 `path-glob-monorepo`（`gems/*/*.gemspec` 命中 2 层）单点代表，未逐层铺；`cache`/`package` 对多 gemspec path 源的复制仍未取 oracle。未重跑全量 `crystal spec` 与全量差分。
## 2026-11-23：M7-5 剩余证据缺口清单（task-160）

本节按 M7-5 任务陈述逐项列「已有证据 / 仍缺什么 / 本机可否验证」。只做清单，不改代码、不改夹具。

### 1. Git tag

- 已有证据：夹具 `fixtures/differential/git-tag`（提交 `4237b06`「test(M7 task-5): add differential fixtures for git tag and glob sources」）；`spec/git_source_spec.cr`。
- 仍缺：该夹具**当前双 profile 的原始 PASS 行**。本任务未在证据文件中找到 task-154（git-init 桩修复）之后 `git-tag` 的复跑记录。
- 本机可否验证：**可**（本地 `file://` git 源；git 装具已修）。需一次定向差分复跑取原始输出，本轮未跑。

### 2. Git submodules

- 已有证据：夹具 `fixtures/differential/git-submodules`；两个 profile 均置 `deferred-2.7.2` / `deferred-4.0.24`（实测计数：2.7.2 共 26 个、4.0.24 共 5 个，`git-submodules` 同时在其中）；提交 `254e493`「test(M7 task-3): add git submodules fixture」。`docs/roadmap-evidence/M7-5-sources-platforms.md` 已记为 documented SKIP。
- 仍缺：**能取到 oracle 的宿主**。参考侧（Bundler 4.0.24）在 git ≥ 2.38 上对 submodule 的 file 传输被 `protocol.file.allow` 策略阻断（本机 git 2.55.0.windows.3），故 oracle 拿不到，不是我方缺陷。
- 本机可否验证：**否**（参考侧阻断）。改动 `protocol.file.allow=always` 属改参考侧环境，取到的 oracle 不具代表性，不建议。

### 3. Git glob

- 已有证据：task-156 修好并**双 profile PASS**；夹具 `fixtures/differential/git-glob`；`spec/m7_git_source_glob_spec.cr`；证据节见 `docs/compat-evidence/2026-11-23.md` 的「GIT 源自定义 glob 的 gemspec 加载（task-156）」。
- 仍缺：无（就本行陈述的 git glob 覆盖面而言已闭合）。
- 本机可否验证：**可**，且已验证。

### 4. 多个 gemspec

- 已有证据：`fixtures/differential/path-glob-monorepo`（显式 glob `gems/*/*.gemspec` 命中 2 层，单点代表）；`fixtures/differential/env-gemspec`；`spec/m7_path_glob_default_spec.cr`；`docs/roadmap-evidence/M7-5-sources-platforms.md` 的 task-145 节。
- 仍缺：该节自述「`cache`/`package` 对多 gemspec path 源的复制仍未取 oracle」；显式 `glob:` 越过默认上限的**逐层形态**只有 `path-glob-monorepo` 单点代表，未逐层铺。
- 本机可否验证：**可**（纯本地 `path` 源，无需网络与 git）。

### 5. monorepo

- 已有证据：`fixtures/differential/path-glob-monorepo`（同一 path 源下多子目录多 gemspec）。
- 仍缺：monorepo 形态下 `lock`/`install`/`cache` 的**完整矩阵**（当前只覆盖锁与命中判定）。
- 本机可否验证：**可**。

### 6. 私有 source 鉴权

- 已有证据：**裸状态码**的 401/403 映射已实现并有 spec —— `spec/m7_authentication_errors_spec.cr`（`describe "private source authentication errors"` 四例：无凭据 401 → `AuthenticationRequiredError`、错凭据后 401 → `BadAuthenticationError`、403 → `AuthenticationForbiddenError`，全部 status 17 / wrap）；实现侧 `src/celerite/downloader.cr:250-253`、`src/celerite/compact_index/cache.cr:189-190`、`src/celerite/errors.cr:271-300`；凭据来源 `src/celerite/config.cr:519` 的 `credentials_for`。另 `spec/m7_source_index_missing_spec.cr`。
- 仍缺（两条，性质不同）：
  1. **差分级 oracle**：`fixtures/differential/` 下无任何以 401/403 为判据的夹具（实测按 `command` 内容检索 `401|403|auth` 零命中；仅有 `lock-gemrc-proxy` / `lock-gemrc-no-proxy`，那是 `~/.gemrc` 代理，不是鉴权）。spec 用的是 spec 内自建 `HTTP::Server`（`spec/m7_authentication_errors_spec.cr:10-23`），只在本进程内证明映射，不与参考侧对照。
  2. **真未实现（账本已声明）**：`docs/compat-claims/README.md:231` 的 `C-M7-5-018` 记为「`~/.gemrc` 凭据源、`WWW-Authenticate: Basic` 与代理 CONNECT 后的 401 尚未实现」，状态 `未实现`。本轮核实：`src/**/*.cr` 检索 `WWW-Authenticate` **零命中**，`src/celerite/proxy.cr` 只解析 `~/.gemrc` 的 `:http_proxy` / `:no_proxy`（`proxy.cr:66-92`），不读凭据条目 —— 与该断言一致。
- 本机可否验证：**第 1 条可**（本地起带 401/403 的 HTTP 服务即可造夹具），**第 2 条否**（属功能缺失，非验证问题）。补充：`script/http_index_server.js` 目前只有 `writeHead(404)` 与 `writeHead(200)` 两处（`script/http_index_server.js:17`、`:21`），**不含自定义状态码参数**，故造 401/403 夹具需另写服务或改该脚本（改脚本越出本任务只读范围，本轮未做）。

### 7. 离线安装

- 已有证据：`install-local-no-cache`、`install-local-vendor-cache`、`install-local-vendored-install`、`vendor/cache` 刷新（task-87）、`install-unreachable-source-with-cache`（task-157）、`lock-missing-spec-row`（task-149）、`cache-*` 系列；`spec/m7_vendor_cache_spec.cr`、`spec/m7_install_app_cache_spec.cr`。
- 仍缺：本任务未发现明确缺口条目；覆盖面已较厚（若要求逐条对齐参考的 `--local` 语义矩阵，需一次专门盘点，本轮未做）。
- 本机可否验证：**可**，且大部分已验证。

### 8. 磁盘错误与中断清理

- 已有证据：`FilesystemErrors.map` 已落地；`spec/m7_filesystem_errors_spec.cr`、`spec/m7_filesystem_error_mapping_spec.cr`。
- 仍缺：**差分级**的磁盘错误夹具（如只读目录 / 空间不足下的退出码与文案对齐）；**中断清理**（install 被 Ctrl-C/终止时对半成品 `bundle/` 与临时文件的清理）无任何 spec 或夹具证据。
- 本机可否验证：磁盘错误**部分可**（只读目录可造；ENOSPC 需配额/虚拟盘，本机未验证）；中断清理**难**（Crystal 在 Windows 上 `Signal` trap 未实现，`docs/compat-report.md` 已声明该边界），且需可控的长时间 install 窗口才能稳定命中，本轮未做。

### 9. Linux gnu/musl 与多 Ruby ABI

- 已有证据：本机为 Windows x64-mingw-ucrt 单 ABI；`docs/compat-report.md` 已声明宿主限制。
- 仍缺：Linux glibc/musl 平台变体选择、多 Ruby（3.x/4.x）ABI 派生与锁定。
- 本机可否验证：**否**。需 Linux 宿主或容器，且需多 Ruby 安装（本机 `C:\Ruby40-x64` 只有 ruby 4.0.6 一套）。

### 汇总（本机可否验证）

| 条目 | 本机可否验证 |
|---|---|
| git tag | 可（需一次定向复跑） |
| git submodules | 否（参考侧 protocol.file.allow 阻断） |
| git glob | 可（已验证，task-156） |
| 多个 gemspec | 可（`cache`/`package` 多 gemspec 复制未取 oracle） |
| monorepo | 可 |
| 私有 source 鉴权 | 裸 401/403 映射可（但无差分夹具）；`WWW-Authenticate`/gemrc 凭据/CONNECT 后 401 属未实现，不可验证 |
| 离线安装 | 可（覆盖面已厚） |
| 磁盘错误 | 部分可（ENOSPC 未验证） |
| 中断清理 | 难（Windows 无 Signal trap），未验证 |
| Linux gnu/musl + 多 Ruby ABI | 否（需 Linux 宿主与多 Ruby） |

## 2026-11-23：M7-5 行的闭合判据审计（task-192）

### 审计口径

- 范围：只读审计 `docs/compat-claims/M7-5-sources-platforms.md`（33 条断言）、本文件既有流水与 `fixtures/differential/`；本轮只追加文档，未改 `src/`、`spec/`、`fixtures/`、`script/`、`docs/compat-claims/`。
- 判据现跑环境：worktree `C:\temp\celerite-t192`（`954f2d5`）；`New-Item -ItemType Directory -Force bin` 后 `crystal build src/cli.cr -o bin/celerite.exe`（EXIT 0，仅 2 条 `File.executable?` 弃用警告）；`PATH` 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;`，`TMPDIR=/c/temp`，`CELERITE_BIN=C:\temp\celerite-t192\bin\celerite.exe`；差分默认 4.0.24，`git-tag` 另跑 `BUNDLER_REF_VERSION=2.7.2`；spec 的 `TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE`/`CRYSTAL_CACHE_DIR` 全指 `C:\temp\celerite-t192\.tmp-crystal`（距盘符 33 字符，≤67）。
- 结论三档：`可勾` = 该分句语义已有可执行判据且本轮或既有记录在 4.0.24（必要时含 2.7.2）通过；`不可勾（缺 N 项）` = 至少一项判据缺 oracle / 缺实现 / 缺判据；`本机不可验证` = 判据存在但本机物理上无法产出 oracle。
- 引用纪律：本节只引断言 ID、证据节标题与夹具名，不引 roadmap 行号或本文件行号。

### 九个分句的判定

| # | 分句 | 结论 | 依据（断言 / 证据节 / 夹具） | 缺口是什么 | 本机可否补 |
|---|---|---|---|---|---|
| ① | Git tag | **可勾** | `C-M7-5-003`（状态「未验证」，**已过期**）；证据节「GIT 源自定义 glob 的 gemspec 加载（task-156）」的同族回归清单；夹具 `git-tag`（本轮 4.0.24 与 2.7.2 均 `PASS (exit=0)`） | 无判据缺口；欠账是断言状态未随 task-156 更新 | 能，且本轮已补跑 |
| ② | Git submodules | **不可勾（缺 1 项）** | `C-M7-5-004`（未验证）；夹具 `git-submodules`（本轮 4.0.24 `SKIP`，deferred） | 缺 oracle：参考侧 git ≥2.38 拒绝 submodule 的 `file` transport（`fatal: transport 'file' not allowed`），我方即便修好也无可比基准 | 不能：参考侧阻断；改 `protocol.file.allow=always` 属改参考环境，取到的 oracle 不具代表性 |
| ③ | Git glob | **可勾** | `C-M7-5-003`（未验证，已过期）；证据节「GIT 源自定义 glob 的 gemspec 加载（task-156）」（已记双 profile PASS）；夹具 `git-glob`（本轮 4.0.24 `PASS (exit=0)`） | 无判据缺口；同上，状态待改 | 能，且本轮已复跑 |
| ④ | 多个 gemspec | **可勾** | `C-M7-5-006`/`007`/`011`/`033`（均已实现）；证据节「多 gemspec path 源的 cache/package 与显式深层 glob（task-187）」；夹具 `path-glob-monorepo`、`path-cache-multi-gemspec`、`path-package-multi-gemspec`（本轮均 `PASS (exit=0)`） | 无行级缺口；余量是 2.7.2 上两条 path 夹具记 deferred（2.7.2 的 `cache` 固定 `cache_all: false`，两侧都不复制） | 能 |
| ⑤ | monorepo | **可勾** | `C-M7-5-002`/`005`/`006`/`009`/`033`（均已实现）；证据节「path 源 gemspec glob 的逐层深度边界（task-145）」与 task-187 节；夹具 `path-glob-monorepo`、`path-glob-explicit-deep`（本轮均 `PASS (exit=0)`） | 无行级缺口；`lock`/`install`/`cache` 全矩阵未逐格铺，属余量 | 能 |
| ⑥ | 私有 source 鉴权 | **不可勾（缺 1 项）** | `C-M7-5-014`/`015`/`016`（已实现）；`C-M7-5-018`（**未实现**）；证据节「私有 source 的 401/403 差分夹具与 http-status 装具能力（task-186）」；夹具 `auth-401-no-credentials`（本轮 `PASS (exit=17)`） | 缺实现：`~/.gemrc` 凭据源、`WWW-Authenticate: Basic` 质询、代理 `CONNECT` 后的 401 三形态均未做，且无 oracle | 能，但需改 `src/` 并新增 401/407 桩服务，属实现工作，越出本轮只读范围 |
| ⑦ | 离线安装 | **可勾** | `C-M7-5-019`/`020`/`021`/`022`/`023`（均已实现）；证据节「不可达源 + vendor/cache 时的 install 退出码（task-157）」；夹具 `install-local-vendor-cache`（`PASS (exit=0)`）、`install-local-no-cache`（`PASS (exit=7)`）、`install-local-new-dep-not-installed`（`PASS (exit=7)`） | 无行级缺口；`--local` + git 源、`--local` + `--frozen`、真实 https 离线、多平台 `vendor/cache` 未验证 | 能 |
| ⑧ | 磁盘错误与中断清理 | **不可勾（缺 2 项）** | 磁盘错误：`C-M7-5-024`/`025`/`027`/`028`/`029`（均已实现，**全部只有 spec 级**）；中断清理：无任何断言、无 spec、无夹具 | 缺判据：磁盘错误无差分级 oracle（只读锁文件是唯一真机形态，ENOSPC/EROFS/EPERM 未真机复现）；中断清理连实现证据都没有——`src/celerite/cli/commands_install.cr` 的 `Signal::INT.trap` 只在 `{% unless flag?(:windows) %}` 分支内（转发给 `bundle exec` 子进程），Windows 安装中断路径无清理契约；`src/celerite/installer.cr` 只做「重跑时清掉上次残留目标」的自愈 | 磁盘错误：部分能（只读目录可造；ENOSPC 需配额盘，不能）；中断清理：不能（Windows 无 `Signal::INT.trap`，且需可控长安装窗口才能稳定命中） |
| ⑨ | Linux gnu/musl 和多 Ruby ABI 验证 | **本机不可验证（缺 2 项）** | `C-M7-5-030`、`C-M7-5-031`（均未验证）；证据节「M7-5 剩余证据缺口清单（task-160）」；夹具 `multi-platform-lock`（本轮 `PASS (exit=0)`，但只跑宿主单 ABI）；`spec/gem/platform_spec.cr` 本轮 `16 examples, 0 failures` | 只能靠别平台验证：无 Linux 宿主/容器，无第二套 Ruby ABI（本机仅 `C:\Ruby40-x64` 的 `ruby 4.0.6 [x64-mingw-ucrt]`）；`BUNDLER_REF_VERSION=2.7.2` 换的是参考 Bundler 版本而非 ABI。**不记入「已声明差异」**——账本该列仍为 0，本轮未新增差异条目 | 不能：需 Linux 宿主（gnu 与 musl 两套）与多 Ruby 安装 |

### 33 条断言的状态表（只列不改）

| 断言 | 状态 | 是否有可执行判据 | 判据现在还能不能跑 |
|---|---|---|---|
| `C-M7-5-001` | 已实现 | 有：差分 `add-git`、`add-ref` | 未复跑；夹具在 |
| `C-M7-5-002` | 已实现 | 有：spec `m7_source_lock_options_spec.cr` + 差分 `path-glob-monorepo` | 夹具本轮 PASS；spec 未复跑 |
| `C-M7-5-003` | 未验证 | 有：差分 `git-tag`、`git-glob` | **本轮可跑且 PASS**（`git-tag` 双 profile、`git-glob` 4.0.24）→ 状态已过期 |
| `C-M7-5-004` | 未验证 | 有：差分 `git-submodules` | 可跑，但两侧 SKIP（本轮 4.0.24 `SKIP`） |
| `C-M7-5-005` | 已实现 | 有：spec `m7_git_source_reuse_spec.cr` | 未复跑 |
| `C-M7-5-006` | 已实现 | 有：差分 `path-glob-monorepo` + spec | 夹具本轮 PASS |
| `C-M7-5-007` | 已实现 | 有：3 个 `path-glob-default-*` + spec | 未复跑；夹具在 |
| `C-M7-5-008` | 已实现 | 有：`path-source-missing-gem`、`plugin-source-missing-gem` + spec | 未复跑 |
| `C-M7-5-009` | 已实现 | 有：4 个夹具（`path-gemspec-bump-reresolves` 等） | 未复跑 |
| `C-M7-5-010` | 已实现 | 有：3 个夹具 + spec | 未复跑 |
| `C-M7-5-011` | 已实现 | 有：4 个夹具 + 2 spec | `path-cache-multi-gemspec` 本轮 PASS |
| `C-M7-5-012` | 已实现 | 有：`install-refreshes-app-cache` + spec | 未复跑 |
| `C-M7-5-013` | 已实现 | 有：`install-path-source-app-cache-first` + spec | 未复跑 |
| `C-M7-5-014` | 已实现 | 有：`auth-401-no-credentials`、`auth-401-bad-credentials` + spec | 前者本轮 PASS（exit=17） |
| `C-M7-5-015` | 已实现 | 有：`auth-403-index` + spec | 未复跑 |
| `C-M7-5-016` | 已实现 | 有：`auth-403-download` + spec | 未复跑 |
| `C-M7-5-017` | 已实现 | 有：`lock-gemrc-proxy`、`lock-gemrc-no-proxy` + spec | 未复跑 |
| `C-M7-5-018` | **未实现** | **无独立判据**（所引 spec 只覆盖已实现三档） | 不可跑（无 oracle） |
| `C-M7-5-019` | 已实现 | 有：3 个 `install-local-*` + spec | `install-local-no-cache` 本轮 PASS（exit=7） |
| `C-M7-5-020` | 已实现 | 有：`install-local-vendor-cache` + spec | 本轮 PASS（exit=0） |
| `C-M7-5-021` | 已实现 | 有：`install-local-new-dep-not-installed` + spec | 本轮 PASS（exit=7） |
| `C-M7-5-022` | 已实现 | 有：仅 spec `m7_prefer_local_spec.cr` | 未复跑 |
| `C-M7-5-023` | 已实现 | 有：`install-local-vendor-cache` + spec | 本轮 PASS（夹具部分） |
| `C-M7-5-024` | 已实现 | 有：仅 spec `m7_filesystem_errors_spec.cr` | 本轮 PASS（与 025 合并 14 examples / 0 failures） |
| `C-M7-5-025` | 已实现 | 有：仅 spec `m7_filesystem_error_mapping_spec.cr` | 本轮 PASS（同上） |
| `C-M7-5-026` | 已实现 | 有：`lock-preserve-crlf` + spec | 未复跑 |
| `C-M7-5-027` | 已实现 | 有：仅 spec `m7_install_failure_spec.cr` | 未复跑 |
| `C-M7-5-028` | 已实现 | 有：仅 spec `m7_install_failure_spec.cr` | 未复跑 |
| `C-M7-5-029` | 已实现 | 有：`install-bundle-layout` + spec | 未复跑 |
| `C-M7-5-030` | 未验证 | 有：仅 spec `spec/gem/platform_spec.cr` | 本轮 PASS（16 examples），但只证明平台字符串归一 |
| `C-M7-5-031` | 未验证 | 有：3 个 `multi-platform-*` + spec | `multi-platform-lock` 本轮 PASS（单 ABI） |
| `C-M7-5-032` | 已实现 | 有：`add-strict` + spec | 未复跑 |
| `C-M7-5-033` | 已实现 | 有：`path-glob-explicit-deep`、`path-glob-explicit-deep-miss` | 前者本轮 PASS（exit=0） |

合计：已实现 28、未验证 4（`003`/`004`/`030`/`031`）、未实现 1（`018`）、已声明差异 0。

### `未实现 1` 与 `未验证 4` 的收口判断

| 断言 | 能否在本机收口 | 理由 |
|---|---|---|
| `C-M7-5-003`（未验证） | **能，且本轮已收口** | `git-tag` 4.0.24 `PASS (exit=0)`、2.7.2 `PASS (exit=0)`；`git-glob` 4.0.24 `PASS (exit=0)`（task-156 节已记 2.7.2 亦 PASS）。建议下一轮把状态改为「已实现」，判据保留两条夹具；本轮只读，未改 claims。 |
| `C-M7-5-004`（未验证） | 不能 | 参考侧 git ≥2.38 对 submodule 的 `file` transport 直接拒绝，oracle 取不到；绕过需改参考环境，证据不具代表性。 |
| `C-M7-5-018`（未实现） | 不能（属实现缺口，不是验证缺口） | 需新增 `~/.gemrc` 凭据读取、`WWW-Authenticate: Basic` 解析与 `CONNECT` 后 401 分派，并各配 401/407 桩；越出本轮只读范围。 |
| `C-M7-5-030`（未验证） | 不能 | 需 Linux 宿主或容器分别跑 gnu 与 musl 平台变体；本机只有 Windows `x64-mingw-ucrt`。 |
| `C-M7-5-031`（未验证） | 不能 | 需第二套 Ruby ABI；本机仅 `C:\Ruby40-x64` 的 `ruby 4.0.6 [x64-mingw-ucrt]`，`BUNDLER_REF_VERSION` 不改变 ABI。 |

### 抽跑记录（12 个差分夹具 + 2 次 spec，覆盖全部九个分句）

| 判据 | profile | 原始结果 | 覆盖分句 |
|---|---|---|---|
| `bash script/differential git-tag` | 4.0.24 | `PASS git-tag (exit=0)`；`1 passed, 0 failed, 0 skipped` | ① |
| `bash script/differential git-tag`（`BUNDLER_REF_VERSION=2.7.2`） | 2.7.2 | `PASS git-tag (exit=0)`；`1 passed, 0 failed, 0 skipped` | ① |
| `bash script/differential git-glob` | 4.0.24 | `PASS git-glob (exit=0)`；`1 passed, 0 failed, 0 skipped` | ③ |
| `bash script/differential git-submodules` | 4.0.24 | `SKIP git-submodules`（deferred：参考侧 `protocol.file.allow` 阻断）；`0 passed, 0 failed, 1 skipped` | ② |
| `bash script/differential path-glob-monorepo` | 4.0.24 | `PASS path-glob-monorepo (exit=0)` | ④⑤ |
| `bash script/differential path-glob-explicit-deep` | 4.0.24 | `PASS path-glob-explicit-deep (exit=0)` | ④⑤ |
| `bash script/differential path-cache-multi-gemspec` | 4.0.24 | `PASS path-cache-multi-gemspec (exit=0)` | ④ |
| `bash script/differential path-package-multi-gemspec` | 4.0.24 | `PASS path-package-multi-gemspec (exit=0)` | ④ |
| `bash script/differential auth-401-no-credentials` | 4.0.24 | `PASS auth-401-no-credentials (exit=17)` | ⑥ |
| `bash script/differential install-local-vendor-cache` | 4.0.24 | `PASS install-local-vendor-cache (exit=0)` | ⑦ |
| `bash script/differential install-local-no-cache` | 4.0.24 | `PASS install-local-no-cache (exit=7)`（stderr contains-only，声明归一化 N10） | ⑦ |
| `bash script/differential install-local-new-dep-not-installed` | 4.0.24 | `PASS install-local-new-dep-not-installed (exit=7)`（stderr contains-only，N10） | ⑦ |
| `bash script/differential multi-platform-lock` | 4.0.24 | `PASS multi-platform-lock (exit=0)` | ⑨ |
| `crystal spec spec/m7_filesystem_errors_spec.cr spec/m7_filesystem_error_mapping_spec.cr` | — | `14 examples, 0 failures, 0 errors, 0 pending` | ⑧ |
| `crystal spec spec/gem/platform_spec.cr` | — | `16 examples, 0 failures, 0 errors, 0 pending` | ⑨ |

- 单夹具重跑次数：均 ≤2（`git-tag` 跑两个 profile 各一次，其余各一次）。
- 全部命令只读、可重复；未改任何产品代码或夹具。
- 关键发现：`git-tag`/`git-glob` 在短路径 worktree（`C:\temp\celerite-t192`）+ 前置两个 msys bin 的环境下不再撞 Low-IL `0xC0000022`，因此 `C-M7-5-003` 的「本机无法取证」边界已不成立，`task-160` 清单里「git tag 仍缺一次定向复跑」也已由本轮补齐。

### 最终判定

**如果维持现状（不新增任何夹具/实现），M7-5 行应保持 `[ ]`：是。**

一句话理由：九个分句里 ①③④⑤⑦ 已可勾，但 ② 缺 oracle、⑥ 有一条断言真未实现、⑧ 的中断清理没有任何判据与实现证据、⑨ 必须靠 Linux 宿主与第二套 Ruby ABI 才能验证——四项都不能靠文档或现有判据收口，故整行不得勾选。

未验证项（本轮明确未做）：其余 20 条已实现断言的判据未逐条复跑（只抽跑 12 个夹具 + 2 次 spec）；2.7.2 全量差分未跑；中断清理未做任何注入实验；ENOSPC/EROFS/EPERM 未真机复现。

## 2026-11-23：私有 source 鉴权的三形态与 C-M7-5-018 收口（task-195）

### oracle

worktree `C:\temp\celerite-t195`（基线 `e45f671`）；`PATH` 前置 `C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;`，`TMPDIR=/c/temp`，`CELERITE_BIN=C:\temp\celerite-t195\bin\celerite.exe`；spec 的另一套 `TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE`/`CRYSTAL_CACHE_DIR` 指向 `C:\temp\celerite-t195\.tmp-scratch\*`。参考 CLI = `C:\Ruby40-x64\lib\ruby\gems\4.0.0\gems\bundler-4.0.24\exe\bundle`。

手工探针（`script/http_index_server.js` 起在 8931/9443 私桩，请求日志逐行落盘）：

- `~/.gemrc` 写 `http://127.0.0.1:8931/: user:pass` → 参考 `exit=17`，stderr 四行 `Authentication is required for 127.0.0.1.` / `Please supply credentials for this source. You can do this by running:` / `` `bundle config set --global 127.0.0.1 username:password` `` / ``or by storing the credentials in the `BUNDLE_127__0__0__1` environment variable``。
- `bundle config set --global http://127.0.0.1:8931/ user:pass` → `exit=0`，`~/.bundle/config` 逐字 `---` 与 `BUNDLE_HTTP://127__0__0__1:8931/: "user:pass"`。
- `source "http://user:pass@127.0.0.1:8931/"` → `exit=0`，首行 `Fetching gem metadata from http://127.0.0.1:8931/.`（userinfo 被过滤）。
- userinfo 对 + config 错 → `exit=0`，三次请求均带 `Basic dXNlcjpwYXNz`；userinfo 错 + config 对 → `exit=17` + `Bad username or password for 127.0.0.1.`，只有一次 `/versions`、带 `Basic YmFkOndyb25n`。
- 无凭据 + `401 WWW-Authenticate: Basic realm="private"` → `exit=17`，服务器只记录一次 `/versions`、`Authorization` 为空（不重试）。
- CONNECT：自签 CA（SAN `IP:127.0.0.1`）+ `https://127.0.0.1:9443/` 经 8932 的 `CONNECT` 代理；无凭据 1 次 CONNECT 后与直连逐字相同的 `exit=17` 文案，`bundle config` 凭据 3 次 CONNECT、三次请求均带 `Basic`、`exit=0`。

差分与 spec：`bash script/differential auth-config-credentials auth-gemrc-not-a-source auth-userinfo-source auth-userinfo-precedence` → 4.0.24 `4 passed`（exit 0/17/0/0），`BUNDLER_REF_VERSION=2.7.2` 同 4 条 `4 passed`；`crystal spec spec/uri_credentials_filter_spec.cr` → `5 examples, 0 failures`；`crystal spec spec/m7_authentication_errors_spec.cr` → `4 examples, 0 failures`。反假绿：`C:\temp\celerite-pre195\bin\celerite.exe`（同 commit 改动前构建）对 `auth-userinfo-source`、`auth-userinfo-precedence` FAIL，逐字 `1c1` / `< Fetching gem metadata from http://127.0.0.1:8765/.` / `---` / `> Fetching gem metadata from http://user:pass@127.0.0.1:8765/.`；另两条旧二进制亦 PASS（取证型）。回归：`bash script/differential auth-401-no-credentials auth-401-bad-credentials auth-403-index auth-403-download outdated-cooldown-http` → `5 passed`（exit 17/17/17/5/1）。

### 参考锚点

- `lib/bundler/source/rubygems/remote.rb:9-18,62-73`：`fallback_auth = Bundler.settings.credentials_for(uri)`，`apply_auth` 只在 `uri.userinfo.nil?` 时写入 ⇒ 源 URI userinfo 优先。
- `lib/bundler/settings.rb:109-120,185-187,528-536`：`credentials_for(uri) = self[uri.to_s] || self[uri.host]`；层级 temporary > local > env > global；`key_for` 做 `normalize_uri` + `.`→`__`、`-`→`___`、upcase、`BUNDLE_` 前缀。
- `lib/bundler/fetcher/downloader.rb:88-92`：预置式 `basic_auth(CGI.unescape(uri.user), …)`；`:36-79` 的 401 只按 `uri.userinfo` 分派，`:72-73` 的 403 → `AuthenticationForbiddenError`。
- `lib/bundler/fetcher.rb:262`：gemrc 只贡献 `:http_proxy`；全树无 gemrc 凭据读取；`rubygems/**` 无 `WWW-Authenticate` 解析；`fetcher.rb:99-108` 三种鉴权错误不重试。
- `lib/bundler/uri_credentials_filter.rb` 是进度行的过滤器，但 4.0.24 实测输出连 `user@` 也不留，故过滤器整体丢弃 userinfo。

### 实现位置

- 新增 `src/celerite/uri_credentials_filter.cr`（`Celerite::URICredentialsFilter.credential_filtered_uri`，`String` / `URI` 两个重载，解析失败原样返回）；`src/celerite.cr:6-7` require。
- `src/celerite/resolution.cr:683,689,1048,1306,1308`、`src/celerite/cli/commands_install.cr:529,800`：`Fetching … from <source>` 全部改走过滤器。
- 未改的凭据与分派链路（已与参考一致）：`src/celerite/config.cr:519-539`、`src/celerite/compact_index/cache.cr:88-89,182-201`、`src/celerite/downloader.cr:222-254`、`src/celerite/http_transport.cr:159`（CONNECT 隧道后同一响应分派）。
- 装具：`script/http_index_server.js` 新增第 5 参 auth map（`<prefix><TAB><user>:<pass>`，最长前缀胜，缺 `Authorization: Basic` 回 `401` + `WWW-Authenticate`）；`script/differential:441-450,460` 把夹具的 `http-auth` 传入。

### 证据

`../compat-evidence/2026-11-23.md` 的「私有 source 鉴权三形态…」节（逐字 stdout/stderr、请求日志与失败 diff）；夹具 `fixtures/differential/auth-config-credentials/`、`auth-gemrc-not-a-source/`、`auth-userinfo-source/`、`auth-userinfo-precedence/`；spec `spec/uri_credentials_filter_spec.cr`。

### 已声明差异

- 原断言「`~/.gemrc` 是凭据源、`WWW-Authenticate` 质询会重试」被 oracle 证伪：参考两条都不实现，我方按参考保持不实现，登记为 `C-M7-5-034`（已声明差异），不得据旧断言自造功能。
- 质询与 CONNECT 两形态不做差分夹具：装具没有代理/TLS 桩服务器；「质询一次后重试」在单个夹具服务器上无法对 ref/cel 两侧分别计数，首侧触发质询后次侧会被直接放行。两形态只用上面的手工探针与请求日志取证。
- 403（`AuthenticationForbiddenError`）文案里的 userinfo 未过滤、未取 oracle；`user@` 无密码的 userinfo 未逐字比对。