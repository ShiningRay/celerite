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
