# M7-5 Git 源 / 多 gemspec / 私有 source / 离线 / 磁盘错误 / 平台 ABI（claims）

本文件是 M7(5) 的断言账本：把 Git 源与 GIT 锁段、多 gemspec 与 monorepo glob 源、私有 source 鉴权、离线安装、磁盘错误与安装失败清理、平台 ABI 六类已取证结论逐条固化为可复跑断言。原始 oracle、逐字输出与探针目录仍留在 `../compat-evidence/`，实证流水见 `../roadmap-evidence/M7-5-sources-platforms.md`；本文件只写结论与判据，计数与总览归 `../compat-report.md`。

> 本轮（2026-11-22）未能复跑任何判据：本机 `crystal spec` 在当前沙箱下无法完成编译，差分夹具的 git 与原生扩展子进程又受 msys Low-IL `0xC0000022` 限制（见 `../compat-claims/cross-cutting.md` 的 C-cross-001）。下列状态取自 `../compat-evidence/` 中记录的运行；每条判据的目标均以 `ls` / `test -e` 逐条确认存在，未改名、未删除。

## C-M7-5-001 判据装具把 git 源夹具的暂存仓库建在工作目录内并以 Windows 路径交给 `git -C`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：不适用——缺陷在判据装具而非产品；夹具载荷被拷成非仓库时，参考侧的表现为 `fatal: repository './gitgem' does not exist` 与 exit 11
- 我方行为：`script/differential:284` `staging="$(mktemp -d "$work/gitstage.XXXXXX")"`、`:285` `staging_win="$(cygpath -w "$staging")"`，`:295` / `:297` / `:301` 三处 `git -C` 改用 `"$staging_win/$rel"`；`cp -r` 与 `test -d` 仍用 POSIX 形式
- 判据：`bash script/differential add-git add-ref`
- 边界：精确成因未证实——旧形态的两条语句独立重放能正常产出 `.git`，只证明了旧形态失败、新形态通过（负对照已做）；同宿主的 `git-installed-discovery`、`git-path-install`、`git-pristine`、`plugin-git-local`、`plugin-git-local2` 仍撞 Low-IL `0xC0000022`，属环境
- 生效：task-8（2e0798c）
- 取代：无

## C-M7-5-002 GIT 锁段按 `ref, branch, tag, submodules, glob` 的固定顺序写选项，非默认 glob 才写 `glob:`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/source/git.rb:53-61 to_lock` 先写 `GIT` / `  remote:` / `  revision:`，再按 `%w[ref branch tag submodules]` 的固定顺序写已出现的选项，最后只在非默认时写 `  glob:`；默认值见 `:15 @glob = options["glob"] || DEFAULT_GLOB`
- 我方行为：`src/celerite/resolution.cr:2271 Resolution.git_lock_options`，`:2279 options << Lockfile::Option.new("glob", glob) unless glob == DEFAULT_GLOB`，默认值 `:2266 DEFAULT_GLOB = "{,*,*/*}.gemspec"`
- 判据：`crystal spec spec/m7_source_lock_options_spec.cr`；`bash script/differential path-glob-monorepo`
- 边界：GIT 段只有 spec 级证据——`git-tag` / `git-glob` 在本机卡在克隆阶段（见 C-M7-5-003），`path-glob-monorepo` 断言的是 PATH 段
- 生效：task-5（b051585）
- 取代：无

## C-M7-5-003 git 源 `tag:` 与 `glob:` 的锁段语义在本机无法取证

- 状态：未验证
- 参考行为（4.0.24）：`lib/bundler/source/git.rb:53-61` 在 `revision:` 之后写 `  tag: <tag>` 或非默认 `  glob: <glob>`；`git-tag` 夹具的参考锁段为 `remote: ./gitgem` / `revision: <staged sha>` / `tag: v0.1.0` 与 `specs: gitgem (0.2.0)`，`git-glob` 夹具写 `glob: gems/*/*.gemspec` 且只锁 `alpha (0.1.0)`
- 我方行为：`src/celerite/resolution.cr:2271 git_lock_options` 已按同一顺序渲染，但两条端到端均未取证
- 判据：`bash script/differential git-tag git-glob`
- 边界：本机 Crystal 产物以 Low IL（`S-1-16-4096`）运行，其 msys `sh.exe` 无法创建 `\BaseNamedObjects\msys-2.0S5-<hash>`，两夹具都在 `git clone --mirror` 阶段以 `0xC0000022` 失败（与 C-cross-001 同因）；干净非沙箱环境与 Linux 宿主均未复跑，故不升级为已实现
- 生效：task-5（4237b06）
- 取代：无

## C-M7-5-004 git 源 `submodules:` 选项两侧都没有可执行证据

- 状态：未验证
- 参考行为（4.0.24）：`lib/bundler/source/git.rb:53-61` 的 `%w[ref branch tag submodules]` 会把 `  submodules: true` 写进 GIT 段；参考侧本夹具因 git ≥2.38 拒绝 submodule file-transport（`fatal: transport 'file' not allowed`）记为 documented SKIP
- 我方行为：同 `src/celerite/resolution.cr:2271`，未单独取证
- 判据：`bash script/differential git-submodules`
- 边界：参考自 git 2.38 起拒绝 file transport，我方受同一 Low-IL 阻塞；不带 submodule 的 git 源见 C-M7-5-003
- 生效：task-5（4237b06）
- 取代：无

## C-M7-5-005 git / path 源的身份包含 uri、ref、branch、glob、submodules，源变化必须重解而非复用锁定路径

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/source/git.rb:76-81 eql?` 把 uri、ref、branch、glob、submodules 全部计入源身份；`lib/bundler/source/path.rb:64-68`（`alias_method :==, :eql?`）把 PATH 源身份定为 `expanded_original_path` + `version`，`glob` 不参与
- 我方行为：`src/celerite/resolution.cr:1102`（源变化使锁内 spec 不合格）、`:1378`（身份含 uri/ref/branch/glob/submodules），`src/celerite/definition.cr:309` 起同口径注释
- 判据：`crystal spec spec/m7_git_source_reuse_spec.cr`
- 边界：只有 spec 级证据，无差分夹具（源变化重解本身不依赖 git 子进程，但夹具无法在本机两 profile 上稳定跑通）；`--branch` 与 `--ref` 同时给出时的优先级未覆盖
- 生效：task-44b（713d3d6）
- 取代：无

## C-M7-5-006 PATH 锁段只在 glob 非默认值时写 `glob:`，默认值是 `{,*,*/*}.gemspec`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/source/path.rb:14 DEFAULT_GLOB = "{,*,*/*}.gemspec"`；`:45-49 to_lock` 写 `PATH` / `  remote: <lockfile_path>` / 仅在 `@glob != DEFAULT_GLOB` 时写 `  glob: <@glob>` / `  specs:`
- 我方行为：`src/celerite/resolution.cr:2286 Resolution.path_lock_options`，`:2289` 同一条非默认守卫；回读侧 `:1647 glob = section.option("glob").as?(String) || DEFAULT_GLOB`
- 判据：`bash script/differential path-glob-monorepo`；`crystal spec spec/m7_source_lock_options_spec.cr`
- 边界：只覆盖相对路径源；`glob:` 与非默认绝对路径的组合、`cache`/`package` 对 monorepo glob 源的复制未取 oracle
- 生效：task-5（b051585）
- 取代：无

## C-M7-5-007 path 源按默认 glob 的三档深度取 gemspec，未命中时归属串为 `source at \`<path>\``

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/source/path.rb:14` 的 `{,*,*/*}.gemspec` 决定只认根、一层、两层目录下的 gemspec；未命中归属串见 `lib/bundler/source/path.rb:159-179`（`source at \`<path>\``）
- 我方行为：`src/celerite/resolution.cr:2266 DEFAULT_GLOB`，`:617 info = @bridge.not_nil!.load_gemspec_dir(dir, glob || DEFAULT_GLOB, name)`，`:1787` 起按参考 `Source::Path#to_s` 渲染归属
- 判据：`bash script/differential path-glob-default-root path-glob-default-nested path-glob-default-deep-miss`；`crystal spec spec/m7_path_glob_default_spec.cr`
- 边界：深度只铺到 `*/*`，更深的逐层夹具仍缺（task-39 已把「默认 glob 深度上限未铺夹具」的旧登记更正为过期）；`E2` 形态与 monorepo 多 gemspec 的 `cache`/`package` 复制未覆盖
- 生效：task-36（35cf103）
- 取代：无

## C-M7-5-008 path 源按 gemspec 自身的 name 匹配请求，未命中即报错且不写锁

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/source/path.rb:159-179` 用 gemspec 自己的 `name` 决定该源是否提供被请求的 gem，不命中即报错，而不是取目录里第一个 gemspec 冒充
- 我方行为：`src/celerite/resolution.cr:617 load_gemspec_dir(dir, glob, name)`（桥接侧 `load_gemspec_dir` 增 `name` 参数），未命中走 `src/celerite/resolver/source.cr:188` 的 `GemNotFoundError`
- 判据：`bash script/differential path-source-missing-gem plugin-source-missing-gem`；`crystal spec spec/m7_path_source_missing_gem_spec.cr`
- 边界：`plugin-source-missing-gem` 的归属串属插件源（`lib/bundler/plugin/api/source.rb:293-296`），归 M7-6；GIT 源的未命中归属未验证
- 生效：task-46（a7590a6）
- 取代：无

## C-M7-5-009 glob 变化是否重解由「锁侧 path+glob 下可见 gemspec 的 name/version 集」决定，而非 glob 字符串

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/source/path.rb:64-68` 把 glob 排除出源身份；`lib/bundler/definition.rb:929-950 specs_changed?` 比较 `locked_index.subset?(source.specs)`，即锁侧 spec 集是否被当前可见集覆盖；frozen 下的拒绝码是 16（4.0.24）/ 1（2.7.2）
- 我方行为：`src/celerite/resolution.cr:1323 lockfile_covers_all_dependencies?` 与可见集判定；glob-only 变化不触发重解
- 判据：`bash script/differential path-gemspec-bump-reresolves check-frozen-path-gemspec-bump path-locked-glob-wins path-glob-change-keeps-lock`
- 边界：`path-glob-change-keeps-lock` 只断言锁不变；「glob 变成空集」的 frozen 形态未取 oracle
- 生效：task-44b（713d3d6）
- 取代：无

## C-M7-5-010 `check` 重写锁文件时保留 PATH / GIT / PLUGIN SOURCE 段与既有 CHECKSUMS

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/definition.rb:379 lock(file_or_preserve_unknown_sections = false, …)` → `:398 write_lock(target_lockfile, preserve_unknown_sections)` → `:401 write_lock`；重写时从锁里的 source 对象重新序列化（`lib/bundler/source/path.rb:41-43`、`lib/bundler/source/git.rb:39-48`、`lib/bundler/lockfile_generator.rb:31-42`），Gemfile 未声明 `source` 行时 GEM 段不带 `remote:`（`lib/bundler/source/rubygems.rb:114-120`）
- 我方行为：`src/celerite/cli/commands_surface.cr:877` 起（`Definition#write_lock` 的等价实现与注释），`:942-944 evaluate_gemfile_before_rewrite`
- 判据：`bash script/differential check-rewrite-keeps-path-source check-rewrites-lock lock-path-source-only-no-remote`；`crystal spec spec/m7_check_rewrite_spec.cr`
- 边界：下游工具注入的任意未知段只测过 PATH / GIT / PLUGIN SOURCE 三类；frozen 与 `--dry-run` 组合见 `check-dry-run-keeps-lock`，不在本条
- 生效：task-44a（882763b）
- 取代：无

## C-M7-5-011 `cache` / `package` 把工程外 path 源整目录复制进 `<cache>/<gem name>/` 并打 `.bundlecache`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/source/path.rb:84-96 cache` 在 `Bundler.settings[:cache_all]`（4.x 默认 true，`lib/bundler/settings.rb:88`）且源在工程外时 `rm_rf` 后 `cp_r` 整目录到 `<cache>/<gem name>/` 并 `touch .bundlecache`，工程内源跳过；`lib/bundler/runtime.rb:131-142 cache` 决定遍历哪些 spec
- 我方行为：`src/celerite/cli/commands_surface.cr:2537-2548 copy_tree`（纯 Crystal 递归复制，沙箱 Low IL 下 `cp -r` 子进程不可用），调用点 `:2685` / `:2692` / `:2703`
- 判据：`bash script/differential cache-all-path cache-no-all-path`；`crystal spec spec/m7_cache_all_path_spec.cr`
- 边界：2.7.2 上 `cache-all-path` 记 `deferred-2.7.2`（2.7.2 的 `cache` 固定写 `cache_all: false`，不复制）；monorepo glob 多 gemspec 源的复制未取 oracle，仍挂账
- 生效：task-84（d95df5a）
- 取代：无

## C-M7-5-012 `install` / `update` / `add` 在工程内存在 `vendor/cache` 时刷新缓存并逐包打印 `  * <file>.gem`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/cli/install.rb:52-53`、`lib/bundler/cli/update.rb:82`、`lib/bundler/cli/add.rb:29` 都在 `Bundler.app_cache.exist?` 时调用 `Bundler.load.cache`；`--no-cache` 与 frozen 不调用
- 我方行为：`src/celerite/cli/commands_install.cr:900 if refresh_cache && refresh_app_cache?(...)`，`:1311 refresh_app_cache?` 等价判定（`Dir.exists?(app_cache_path) && !frozen && !rest.includes?("--no-cache")`），`:1272 refresh_app_cache`
- 判据：`bash script/differential install-refreshes-app-cache`；`crystal spec spec/m7_install_app_cache_spec.cr`
- 边界：逐包 `  * <file>.gem` 行的顺序未逐字对照；`cache` / `package` 对 monorepo glob 源的复制仍挂账
- 生效：task-87（bc8caea）
- 取代：无

## C-M7-5-013 首次 `install` 也把工程外 path 源复制进 `vendor/cache`，绝对 `BUNDLE_PATH` 原样渲染

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/runtime.rb:131-142 cache` 遍历 `definition.specs` 而非锁文件，故首次安装同样复制工程外 path 源；`lib/bundler/cli/install.rb:57-64` 用 `lib/bundler/settings.rb:253-297` 的 `base_path_relative_to_pwd` 决定 `Bundled gems are installed into` 的渲染
- 我方行为：`src/celerite/cli/commands_install.cr:1135 app_cache_label`、`:1140 app_cache_path`、`:1272 refresh_app_cache`；缓存源列表改由调用方传入的 `Lockfile::Data` 驱动，不再依赖已有锁
- 判据：`bash script/differential install-path-source-app-cache-first`；`crystal spec spec/m7_bundle_path_rendering_spec.cr`
- 边界：绝对 `BUNDLE_PATH` 无法做成差分夹具（装具只有 `@INDEX_DIR@` / `@PLATFORM_INDEX_DIR@` 占位符，没有沙箱根占位符），该形态只由 spec 覆盖；2.7.2 上该夹具记 `deferred-2.7.2`；`Source::Git#cache` 仍不可用
- 生效：task-88（d2cd4f5）
- 取代：无

## C-M7-5-014 私有 source 的 401 按是否带凭据分派 `AuthenticationRequiredError` / `BadAuthenticationError`，均以 17 退出且不重试

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/fetcher/downloader.rb:66-76` 对 `HTTPUnauthorized` 按 `uri.userinfo` 分派，两者都传 `uri.host`；文案在 `lib/bundler/fetcher.rb:45-48`（四行，末行是 `BUNDLE_<key>` 环境变量）与 `:54-59`（两行）；`lib/bundler/errors.rb:38 HTTPError` 的 status 是 17
- 我方行为：`src/celerite/compact_index/cache.cr:160 perform`，`:198-205` 的 401 分支（有 `user` / `password` 或 URI userinfo 走 Bad，否则 Required）；`src/celerite/downloader.cr:248-254` 同规则；错误类 `src/celerite/errors.cr:274` 与 `:295`
- 判据：`crystal spec spec/m7_authentication_errors_spec.cr`；`bash script/differential auth-401-no-credentials`；`bash script/differential auth-401-bad-credentials`（4.0.24 与 2.7.2 双 profile 均 PASS，exit 17，stdout/stderr 逐字一致）
- 边界：差分只覆盖 `install` 单命令与 `http://127.0.0.1:8765/` 的静态桩；`update` / `cache` 未做；`WWW-Authenticate: Basic` 质询与 `~/.gemrc` 凭据仍属 C-M7-5-018 的未实现缺口；不重试以差分 `(exit=17)` 固定，`src/celerite/downloader.cr:235` 的三类 rescue 是代码层保证
- 生效：task-5（e3c8c07）
- 取代：无

## C-M7-5-015 索引期 403 归因到完整源 URI（含尾斜杠），紧凑索引 403 回退 legacy 索引后再报错

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher/compact_index.rb:9-23` 只重抛 401，其余 HTTP 错误记日志后返回 nil，故 403 回退到 legacy `specs` 索引；`lib/bundler/fetcher/index.rb:10-22` 以**完整源 URI**（`remote_uri`，含尾斜杠）抛 `AuthenticationForbiddenError`；文案在 `lib/bundler/fetcher.rb:63-70`
- 我方行为：`src/celerite/compact_index/cache.cr:198-205` 的 403 分支用补齐尾斜杠的完整 URI；`src/celerite/resolution.cr:781-783` 起在抛出前补印 `Fetching source index from <remote>` 与空行；错误类 `src/celerite/errors.cr:317`
- 判据：`crystal spec spec/m7_forbidden_spec.cr`；`bash script/differential auth-403-index`（4.0.24 与 2.7.2 双 profile 均 PASS，exit 17，`Fetching source index from <远程>` 加空行，stderr 两行逐字一致）
- 边界：legacy `specs.4.8.gz` 索引本身未实现；夹具把 `/versions`、`/info/` 与 legacy `/specs.4.8.gz`、`/latest_specs.4.8.gz`、`/prerelease_specs.4.8.gz` 一并置 403，只验证「回退 legacy 后仍 403」的归因与退出码。只让紧凑索引 403 时参考用 legacy 索引成功安装（4.0.24 实测 exit 0），我方 exit 17——回退后成功取到索引的形态属已声明缺口，未实现；403 与凭据组合未测
- 生效：task-5（7f84050）
- 取代：无

## C-M7-5-016 gem 下载 403 按 4 轮重试并逐轮打印 `Retrying download gem …`，最终以 `InstallError`（5）失败

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/rubygems_integration.rb:379 download_gem` 用 `:384 Bundler::Retry.new("download gem from …")`；`lib/bundler/retry.rb:53-64 fail_attempt` 在最后一轮或不可重试异常时抛原异常，否则打空行与 `Retrying … due to error (n/4): …`；`lib/bundler/installer/gem_installer.rb:44-48` 拼 `"<类>: <消息>" + 回溯 + failure_message`，`:55-57` 的 failure_message 是 `An error occurred while installing <name> (<version>), and Bundler cannot continue.`；status 5 见 `lib/bundler/errors.rb:21`
- 我方行为：`src/celerite/downloader.cr:30 ForbiddenDownloadError`、`:48 "<bad response Forbidden 403 (#{@url})>"`、`:255-276` 的 403 重试循环；`src/celerite/installer.cr:321 Installer.download_failure_message`、`:313` 追加 `In Gemfile:` 依赖树
- 判据：`crystal spec spec/m7_forbidden_download_spec.cr`；`bash script/differential auth-403-download`（4.0.24 与 2.7.2 双 profile 均 PASS，exit 5；stderr 走 N10 contains-only，逐字钉住三条 `Retrying download gem … (2/4|3/4|4/4)`、`Bundler::HTTPError: Could not download gem from …` 与 failure message）
- 边界：参考在 `Bundler::HTTPError` 之后打印的约 20 行 Ruby 回溯不复刻（我方回溯是真实栈），故该夹具只用 contains-only、不用 `file-equals`；`Bundler::Retry` 的 jitter 与退避时长未建模；`/quick/` 的 403 未验证，夹具只覆盖 `/gems/` 与 `json_pure 2.8.1`
- 生效：task-5（b6db076）
- 取代：无

## C-M7-5-017 `~/.gemrc` 的 `:http_proxy` 参与代理解析，取值为 `:no_proxy` 时关闭代理

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:262 fetcher = GemRemoteFetcher.new Gem.configuration[:http_proxy]`，`:313-316` 仅在 `gem_proxy != :no_proxy` 时设置代理；`Gem.configuration[:http_proxy]` 的来源是 `~/.gemrc`（`lib/bundler/plugin.rb:8` 只把 `:sources` 当文档串，参考不读）
- 我方行为：`src/celerite/proxy.cr:44-47`（gemrc 命中即不再看其它来源，`:no_proxy` 直接返回 nil），`:66 gemrc_http_proxy`，`:92 File.join(home, ".gemrc")`
- 判据：`bash script/differential lock-gemrc-proxy lock-gemrc-no-proxy`；`crystal spec spec/m7_gemrc_proxy_spec.cr`
- 边界：`.bundle/config` 的 `proxy` / `http_proxy` 参考不读、我方仍读并排在 gemrc 之后，属有意扩展；gemrc 的 `https_proxy` 与系统级 gemrc 未对齐
- 生效：task-85（de62795）
- 取代：无

## C-M7-5-018 `~/.gemrc` 凭据源、`WWW-Authenticate: Basic` 与代理 CONNECT 后的 401 尚未实现

- 状态：未实现
- 参考行为（4.0.24）：`lib/bundler/fetcher/downloader.rb:66-76` 的 401 分派依赖 `uri.userinfo`，凭据可由 `BUNDLE_<host>` 键与 `Gem.configuration`（含 `~/.gemrc`）提供；`WWW-Authenticate: Basic` 变体与代理 `CONNECT` 之后的 401 走同一分派
- 我方行为：未改代码——凭据只来自源 URI 的 userinfo 与 `BUNDLE_*` 环境变量 / `.bundle/config`，不读 `~/.gemrc`，也不解析 `WWW-Authenticate`
- 判据：`crystal spec spec/m7_authentication_errors_spec.cr`
- 边界：三种形态都没有 oracle，故本条无独立判据——上述 spec 只覆盖已实现的三档，不能证明缺口本身；状态取自 `../roadmap-evidence/M7-5-sources-platforms.md` 的「仍缺（真未实现）」清单
- 生效：task-5（e3c8c07）
- 取代：无

## C-M7-5-019 `--local` 只从已安装 gems 与 `vendor/cache` 取材，不查任何索引（含 `file://`），缺失即以 exit 7 报参考文案

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/definition.rb:190-203 setup_domain!` 在 `--local` 时走 `sources.local!` 而不是 `sources.remote!`；`lib/bundler/source/rubygems.rb:69-76 cached!`；缺失候选由 `lib/bundler/resolver.rb:334-361 raise_not_found!` 组 `Could not find gem '<req>' in <source>.`
- 我方行为：`src/celerite/resolution.cr:946 index_specs_for`（`:948 if @local_only` 直接返回本地候选），`:813 local_index_specs`，`:871 vendor_cache_specs`；文案分档见 `:1778`（`cached gems or installed locally`）与 `:1783`
- 判据：`bash script/differential install-local install-local-no-cache install-local-index-unreachable`；`crystal spec spec/m7_local_install_spec.cr`
- 边界：真实 https 离线、`--local` + git 源、`--local` + `--frozen`、`BUNDLE_LOCAL` 设置项未验证；本地候选在设置 `GEM_HOME` 时只认它，参考用全局 `Gem.path`（已声明差异，见 `../compat-evidence/2026-11-15.md` 的 `--local` 节）
- 生效：task-5（1c0c214）
- 取代：无

## C-M7-5-020 `install --local` 直接从 `vendor/cache` 取包，不打印 `Fetching`，并打印 `Updating files in vendor/cache`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/source/rubygems.rb:69-76` 的缓存来源在 `--local` 下参与候选，取包不再访问索引，故无 `Fetching` 行；`lib/bundler/cli/install.rb:52-53` 只在 `app_cache.exist?` 且非 `--no-cache`、非 frozen 时刷新缓存
- 我方行为：`src/celerite/resolution.cr:871 vendor_cache_specs` 记录 `full_name → .gem`，`src/celerite/cli/commands_install.cr:600` 在 local_only 下改用该文件并跳过 `Fetching`
- 判据：`bash script/differential install-local-vendor-cache`；`crystal spec spec/m7_vendor_cache_spec.cr`
- 边界：多平台 `vendor/cache`（同名不同平台包）未验证；`Updating files in vendor/cache` 的打印时机只对 4.0.24 取过 oracle
- 生效：task-5（2be0ec6）
- 取代：无

## C-M7-5-021 `--local` 下新增非本地依赖以 exit 7 失败，且不写出被改坏的锁

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/definition.rb:1051 converge_dependencies` 判定 Gemfile 依赖不在锁内即需重解；`--local` 下候选只含本地 gems，缺失即由 `lib/bundler/resolver.rb:334-361` 抛出，锁文件不被写入；源描述来自 `lib/bundler/source/rubygems.rb:122-136`
- 我方行为：`src/celerite/resolution.cr:1076`（`--local` 且锁全覆盖才走 `materialize_locked` 早退）与 `:1323 lockfile_covers_all_dependencies?`；未覆盖时回落正常解析，`src/celerite/resolver/source.cr:188` 抛 `GemNotFoundError`，异常发生在写锁之前
- 判据：`bash script/differential install-local-new-dep-not-installed`；`crystal spec spec/m7_local_install_missing_dep_spec.cr`
- 边界：覆盖判定只看依赖**名字**是否在锁内，不看 requirement；`update --local` 只有手工 A/B，没有固定夹具；2.7.2 只跑了夹具，没有逐字 oracle
- 生效：task-120（3dcba4b）
- 取代：无

## C-M7-5-022 `--prefer-local` 先取远端索引再以本工程已安装 gems / `vendor/cache` 为候选，本地为空才回落远端

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:190-203 setup_domain!` 在 `--prefer-local` 时先 `prefer_local!` 再 `sources.cached!`，即保留远端但优先本地
- 我方行为：`src/celerite/resolution.cr:954 if @prefer_local`（先 `index_specs_from_remote`，本地候选非空即采用），`:919 prefer_local_candidates`
- 判据：`crystal spec spec/m7_prefer_local_spec.cr`
- 边界：无差分夹具；`--local` 与 `--prefer-local` 同时给出时的优先级无独立 oracle；本地候选的目录扫描改用 `src/celerite/glob.cr:12` 的 `Glob.paths`，因为 Crystal `Dir.glob` 对绝对 Windows 路径返回 0 命中
- 生效：task-113（6ea4774）
- 取代：无

## C-M7-5-023 Windows 下 `Dir.glob` 把 `\` 当转义符，glob 枚举改用 `Dir.children` + `File.match?` 的 `Glob.paths`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：不适用——参考在 Ruby 侧用 `Dir.glob` 枚举 gemspec，没有该转义行为；本条是 Crystal 1.22 Windows 上的实现约束
- 我方行为：`src/celerite/glob.cr:12 Glob.paths(dir, pattern)`，`:13 path = dir.gsub('\\', "/")`，随后对 `Dir.children` 的 basename 做 `File.match?` 并按 `File.join` 重新拼接排序
- 判据：`crystal spec spec/m7_vendor_cache_spec.cr`；`bash script/differential install-local-vendor-cache`
- 边界：`Glob.paths` 只支持 basename 模式，不支持 `**` 递归；没有独立的 `spec/glob_spec.cr`，覆盖散在 `m7_vendor_cache_spec.cr` 与 `m7_prefer_local_spec.cr`
- 生效：task-5（2be0ec6）
- 取代：无

## C-M7-5-024 锁文件写入被拒映射为 `PermissionError` 并以 23 退出

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/shared_helpers.rb:105-127 filesystem_access` 把 `Errno::EACCES` 映射为 `PermissionError.new(path, action)`；`lib/bundler/errors.rb:94-127` 的 `PermissionError` 以 80 列 `wrap` 输出三行，`:127 status_code(23)`
- 我方行为：`src/celerite/errors.cr:341 class PermissionError`（status 23、`wrap?` true），`src/celerite/lockfile/writer.cr:19-24 rescue ex : File::Error` 后经 `:23 mapped = FilesystemErrors.map(ex, :write)` 交给映射
- 判据：`crystal spec spec/m7_filesystem_errors_spec.cr`
- 边界：唯一真机复现形态是只读锁文件；无差分夹具（受管沙箱无法稳定造出只读文件），故只有 spec 级证据
- 生效：task-5（6343016）
- 取代：无

## C-M7-5-025 文件系统错误按参考分档映射为 `PermissionError` / `TemporaryResourceError` / `NoSpaceOnDeviceError` / `ReadOnlyFileSystemError` / `OperationNotPermittedError` / `OperationNotSupportedError` / `VirtualProtocolError` / `GenericSystemCallError`

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/shared_helpers.rb:105-127` 的分支——`EAGAIN`→`TemporaryResourceError`、`EPROTO`→`VirtualProtocolError`、`ENOSPC`→`NoSpaceOnDeviceError`、`ENOTSUP`→`OperationNotSupportedError`、`EPERM`→`OperationNotPermittedError`、`EROFS`→`ReadOnlyFileSystemError`、`EEXIST` / `ENOENT` 原样重抛、其余 `SystemCallError`→`GenericSystemCallError`；状态码见 `lib/bundler/errors.rb:156-198`（26 / 27 / 28 / 31 / 42）
- 我方行为：`src/celerite/filesystem_errors.cr:13 FilesystemErrors.map(error : File::Error, action : Symbol = :write)`，`:37` `ERROR_DISK_FULL` / `ERROR_HANDLE_DISK_FULL`，`:39` `ERROR_WRITE_PROTECT`，`:41` `ERROR_ACCESS_DENIED`；错误类 `src/celerite/errors.cr:392` / `:404` / `:423` / `:434` / `:445` / `:456` / `:467`
- 判据：`crystal spec spec/m7_filesystem_error_mapping_spec.cr`
- 边界：真实 ENOSPC / EROFS / EPERM 从未在真机复现，spec 用 `File::Error.from_os_error` 构造；映射只接到锁文件写出，参考 `filesystem_access` 同时覆盖下载缓存与 bundle 目录创建，那两处未接线；`DirectoryRemovalError`（36）、`YamlSyntaxError`（25）、`GemRequireError`（24）未覆盖
- 生效：task-5（590a0dd）
- 取代：无

## C-M7-5-026 既有锁文件含 CRLF 时写回保持 CRLF，新建锁文件用 LF

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/definition.rb:428-434` 在既有锁文件字节含 `\r\n` 时 `contents.gsub!(/\n/, "\r\n")`，随后 `:438 File.open(p, "wb") {|f| f.puts(contents) }`；2.7.2 以文本模式读锁使 `match?("\r\n")` 不触发，归一为 LF 属参考行为而非我方偏差
- 我方行为：`src/celerite/lockfile/writer.cr:12 Lockfile.write(path, contents, preserve_crlf = true)`，`:14` 检测既有 `\r\n`，`:16 text = contents.gsub(/(?<!\r)\n/, "\r\n")`
- 判据：`bash script/differential lock-preserve-crlf`；`crystal spec spec/m7_lockfile_line_endings_spec.cr`
- 边界：`install` / `update` 的写锁路径只有单元级推断；混合 CRLF/LF、BOM/UTF-8、`--lockfile` 别名未验证；新建锁文件为 LF 未单独断言
- 生效：task-5（926e83a）
- 取代：无

## C-M7-5-027 原生扩展编译失败映射为 `InstallError`（5）：消息含真实回溯与 `In Gemfile:` 依赖树，半装目录保留、只删 `specifications/<full>.gemspec`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/installer/gem_installer.rb:22-25` 把 `Gem::InstallError`（含 `Gem::Ext::BuildError`）交给 `:44-48 specific_failure_message`（`"<类>: <消息>" + "  " + 回溯 + "\n\n" + failure_message`），`:55-57` 的 failure_message 是 `An error occurred while installing <name> (<version>), and Bundler cannot continue.`；`lib/bundler/installer/parallel_installer.rb:198` / `:214` 追加 `:256` 起的 `require_tree_for_spec` 依赖树；status 5 见 `lib/bundler/errors.rb:21`
- 我方行为：`src/celerite/install_error.cr:7 InstallError`（status 5、`wrap?` true），`src/celerite/installer.cr:249 raise InstallError.new(extension_failure_message(...))`，`:294 extension_failure_message`，`:313` 追加依赖树，`:349 require_tree_for`
- 判据：`crystal spec spec/m7_install_failure_spec.cr`
- 边界：故意不做差分夹具——我方回溯是真实栈，参考的 Bundler 帧不可伪造；2.7.2 profile 未单独断言；其它失败种类未验证
- 生效：task-5（281e0bc）
- 取代：无

## C-M7-5-028 扩展编译失败后不在 `<bundle>/cache/` 留下该 gem 的 `.gem`

- 状态：已实现
- 参考行为（4.0.24）：扩展编译失败时缓存目录不留 `<full_name>.gem`，成功安装则两侧都保留，故 `installed?` 仍为假
- 我方行为：`src/celerite/installer.cr:265 rescue ex : InstallError`，`:276-277 failed_cache = File.join(@install_root, "cache", "#{full_name}.gem")` 后删除
- 判据：`crystal spec spec/m7_install_failure_spec.cr`
- 边界：只覆盖 `InstallError` 一类失败；多平台 `full_name` 与 `cache` / `package` 下的失败清理未验证
- 生效：task-5（2d2fbf4）
- 取代：无

## C-M7-5-029 安装结束后不留 `bundler.lock`，并按参考补齐 `ruby/<abi>` 下的记账目录

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：RubyGems `lib/rubygems/installer.rb:902-918 write_build_info_file` 与 `:475-484 generate_plugins`（`Gem.plugindir`）决定 `build_info` / `plugins` 等目录存在；命令结束后不残留进程锁文件
- 我方行为：`src/celerite/installer.cr:43 Installer.ensure_layout` 建 `build_info` / `doc` / `plugins` / `extensions`，`:35` 在构造时调用；`src/celerite/cli/commands_install.cr:44 class ProcessLock`、`:48` 起 `lock`、`:50` `path = File.join(bundle_path, "bundler.lock")`、`:62` 起 `close` 解锁并 `File.delete`
- 判据：`bash script/differential install-bundle-layout`；`crystal spec spec/m7_bundle_layout_spec.cr`
- 边界：`doc` / `extensions` 两个目录只有观测目录清单、没有参考行号锚点；无端到端 spec（进程内安装不落 `bundle/ruby/*`），只有单测加差分夹具；2.7.2 下该夹具会多打一行 `Fetching source index …`（已在 task-104 登记）
- 生效：task-105（6946fca）
- 取代：无

## C-M7-5-030 Linux gnu / musl 平台匹配只做到平台字符串归一，真实 Linux ABI 运行矩阵未验证

- 状态：未验证
- 参考行为（4.0.24）：RubyGems `lib/rubygems/platform.rb:218` 对 linux 用 `normalized_linux_version == other.normalized_linux_version || ["musl#{@version}", "musleabi#{@version}", "musleabihf#{@version}"].include?(other.version)`；`:226-230 normalized_linux_version` 去掉 `gnu` 前缀与 `eabi(hf)` 后缀，`:194` 注释说明「无版本」等价于 gnu
- 我方行为：`src/celerite/gem/platform.cr:171`（非 linux 走空版本通配）、`:173-174`（同样的归一比较与 musl 候选集）、`:177 normalized_linux_version`、`:185 musl_candidate`
- 判据：`crystal spec spec/gem/platform_spec.cr`
- 边界：判据只在 Windows x64-mingw-ucrt 宿主上做字符串比较；`gnu` / `musl` 的真实 ABI 差异（`docs/architecture.md:202` 要求的运行矩阵）没有任何 Linux 宿主、容器或虚拟机证据，故不声明为已实现
- 生效：—
- 取代：无

## C-M7-5-031 多 Ruby ABI 的平台变体选择只在宿主 `x64-mingw-ucrt` 上取证，跨 ABI 矩阵未验证

- 状态：未验证
- 参考行为（4.0.24）：平台变体选择 `lib/bundler/resolver.rb:255-303 all_versions_for`（ruby 候选 priority -1、平台候选 priority 1）→ `lib/bundler/match_platform.rb:12-15 select_best_platform_match` → `lib/bundler/rubygems_ext.rb:115-124 sort_and_filter_best_platform_match`（精确平台优先，再按 specificity 与依赖集取同组）
- 我方行为：`src/celerite/resolver/source.cr:246` / `:257` / `:284`（同口径的 ruby / 平台分组与 specificity 取最小），`ResolvedSpec` 的平台字段驱动 PLATFORMS 段
- 判据：`bash script/differential multi-platform-lock multi-platform-install multi-platform-install-ruby`；`crystal spec spec/m7_platform_variant_selection_spec.cr`
- 边界：宿主只有 `x64-mingw-ucrt` 一种 ABI；`BUNDLER_REF_VERSION=2.7.2` 换的是参考 Bundler 版本，不是第二个 Ruby ABI；Linux / macOS ABI 与多 Ruby 版本矩阵没有任何证据
- 生效：task-3（d130bbb）
- 取代：无

## C-M7-5-032 `add --strict` 在 install 阶段失败时保留已追加的 Gemfile 与已改写的锁，注入阶段失败时不写盘

- 状态：已实现
- 参考行为（4.0.24）：`injector.rb` 的 Gemfile 追加（`:47` `append_to(gemfile_path, build_gem_lines(@options[:conservative_versioning]))`）与锁改写（`:50` `@definition.lock`）都发生在 `cli/add.rb:22` 的 `perform_bundle_install` 之前；解析已成功而 install 阶段失败时两处写入均已落盘，注入阶段抛错则一个文件都没写过。
- 我方行为：`src/celerite/cli/commands_surface.cr:574-575` 在 installer 之前先 `persist_add_lockfile` 写锁，`:577-579` 的 rescue 只在 probe/relock 失败时用备份还原 Gemfile，`:598` 的 installer 调用在该 rescue 之外，故 install 阶段失败保留已追加的 Gemfile 与已改写的锁；`resolution.cr:2437` 的 `inject_dependency!` 失败时 `commands_surface.cr:577-579` 还原 Gemfile 且不写锁。
- 判据：`bash script/differential add-strict`；`crystal spec spec/m7_add_strict_write_spec.cr`
- 边界：该 spec 有临时根长度前提——临时根距盘符不超过 67 字符，且 `TMPDIR`/`TMP`/`TEMP`/`HOME`/`USERPROFILE` 都指向它，否则 bridge 缓存路径越过 Windows `MAX_PATH`，`add` 以 exit 1 的内部错误失败而非 7。sourced add（`--path`/`--git`/`--github`/`--source`）不做注入，见 `commands_surface.cr:632` 的 `sourced_add?`。锁文件另有 json_pure sha256 行的已知差异（+72 B），不在本条范围。
- 生效：task-167（67196b2）
- 取代：无
