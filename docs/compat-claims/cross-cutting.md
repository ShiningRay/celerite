# 贯穿性断言（cross-cutting）

宿主限制、M0–M6 遗留、以及跨多个 M7 子项的边界结论。

## C-cross-001 `bundle exec` 的子进程在 Unix 上随父进程收到 SIGINT/SIGTERM 而终止，Windows 上共享控制台

- 状态：已声明差异
- 参考行为（4.0.24）：trap 整个进程组，子进程随父进程终止
- 我方行为：Unix 上 `Signal::INT.trap { process.signal(Signal::INT) }` 转发、结束前 `Signal::INT.reset`（`src/celerite/cli/commands_install.cr:1841`、`:1846`）；Windows 上 Crystal 的 `Signal` trap 未实现，子进程共享控制台（`src/celerite/cli/commands_install.cr:1783` 的 `trap("INT", "DEFAULT")`）
- 判据：`crystal spec spec/m7_exec_spec.cr`
- 边界：Windows 的信号语义不作兼容声明
- 生效：M2–M6 期间
- 取代：无

## C-cross-002 可直接加载的 Ruby 脚本走 `Kernel.load` 运行时适配器，`disable_exec_load` 可绕过

- 状态：已声明差异
- 参考行为（4.0.24）：同样用 `Kernel.load` 装载可执行脚本，`disable_exec_load` 时走普通 exec
- 我方行为：适配器设 `$0`/ARGV/进程标题、把 SIGINT 还原为 `DEFAULT` 后 `Kernel.load`（`src/celerite/cli/commands_install.cr:1768-1769`）；这是 Ruby 进程适配器，不是 Crystal 内原生 load，脚本级进程内状态变更不作兼容声明
- 判据：`bash script/differential exec-loader exec-loader-disabled exec-thor-version`
- 边界：仅覆盖这三个夹具的形态
- 生效：M2–M6 期间
- 取代：无

## C-cross-003 install / update / pristine 在 `<bundle_path>/bundler` 上取独占锁，并发运行串行化

- 状态：已实现
- 参考行为（4.0.24 = 2.7.2）：同样在 bundle 路径上加独占文件锁
- 我方行为：`ProcessLock` 用标准库 `flock_exclusive` 及 Win32 等价物（`src/celerite/cli/commands_install.cr:44`）
- 判据：`crystal spec spec/process_lock_spec.cr spec/process_race_spec.cr`
- 边界：`process_race_spec` 验证的是独立 OS 进程持有锁时竞争者阻塞，不是分布式锁
- 生效：M2–M6 期间
- 取代：无

## C-cross-004 `--cooldown` 只校验数值与主远程的 Gemfile per-source，非适用命令未单独加固

- 状态：已声明差异
- 参考行为（4.0.24）：`--cooldown` 按命令适用面分别生效，非法值报 `Expected numeric value for '--cooldown'`
- 我方行为：数值与非负校验已对齐（`src/celerite/config.cr:453-455` 取 `cooldown` 设置）；`exec` 等非适用命令不做额外加固；Gemfile per-source `cooldown:` 只对主远程强制，多源 fan-in 按规范源优先级解析
- 判据：`bash script/differential outdated-cooldown-http outdated-cooldown-table`
- 边界：多源 cooldown 的取舍未逐源验证
- 生效：M7 期间
- 取代：无

## C-cross-005 `add --group` 在 2.7.2 profile 下 deferred，不是 passed

- 状态：已声明差异
- 参考行为（2.7.2）：为 lockfile 声明的 Bundler 版本会从 rubygems.org 自动安装 4.0.24，离线沙箱无网络
- 我方行为：不适用；4.0.24 profile 下该夹具为绿
- 判据：`bash script/differential add-group`
- 边界：2.7.2 路径只作记录，不作兼容声明
- 生效：M7 期间
- 取代：无

## C-cross-006 纯 Ruby gem 先于原生扩展 gem 安装，顺序由 `cache-all-platforms` 探针钉住

- 状态：已实现
- 参考行为（4.0.24）：同一安装批次内纯 Ruby gem 先装、原生扩展后装
- 我方行为：同序，被 `cache-all-platforms` 的安装顺序探针固定
- 判据：`bash script/differential cache-all-platforms`
- 边界：只对全新 install / update 的顺序作声明
- 生效：M7 期间
- 取代：无

## C-cross-007 安装后的 `.gemspec` 采用 RubyGems stub 格式，与参考模式一致

- 状态：已实现
- 参考行为（4.0.24）：安装树里的 spec 是 Ruby stub 文件，不是 Marshal
- 我方行为：同格式，由 install/exec 差分夹具验证
- 判据：`bash script/differential install-force`
- 边界：验证锚在安装树比较的路径与内容探针上，不是逐字节比较
- 生效：M7 期间
- 取代：无

## C-cross-008 Ruby 运行时场景走参考的 `bundler/setup`，不是独立轻量 Ruby 运行时

- 状态：已声明差异
- 参考行为（4.0.24）：`Bundler.setup`
- 我方行为：运行时兼容路径加载参考 `bundler/setup`；独立轻量适配器排在 M9
- 判据：`bash script/differential ruby-api`
- 边界：`ruby-api` 证明的是经由该参考边界的行为等价，不声称 Crystal 自带 Ruby API
- 生效：M7 期间
- 取代：无

## C-cross-009 并发下载按 name/version/platform 做进程内 single-flight 去重，不声称分布式互斥

- 状态：已声明差异
- 参考行为（4.0.24）：下载缓存按内容寻址，同一 gem 并发请求只下载一次
- 我方行为：内容寻址缓存的进程内 single-flight 去重（`src/celerite/downloader.cr:13`）；跨进程靠 C-cross-003 的 bundle 路径独占锁串行化，不是分布式锁
- 判据：`crystal spec spec/process_lock_spec.cr`
- 边界：进程内语义，不跨进程
- 生效：M7 期间
- 取代：无

## C-cross-010 `BUNDLE_GEMFILE` 指向缺失路径时，读类命令统一报单行 `<绝对路径> not found` 并 exit 10

- 状态：已实现
- 参考行为（4.0.24；2.7.2 同族）：`lib/bundler/definition.rb:38` 在 `Definition` 构造时 `raise GemfileNotFound, "#{gemfile} not found" unless gemfile.file?`；`shared_helpers.rb:263-265` 的 `find_gemfile` 只做路径解析、不校验存在性；`friendly_errors.rb:35` 以 `wrap: true` 输出该消息并映射 exit 10。命令族：`list`/`check`/`show`/`outdated`/`lock`/`binstubs`/`info`/`platform`/`add`/`remove`/`doctor`/`licenses`/`pristine`/`fund`/`console`。
- 我方行为：`src/celerite/definition.cr:29-35` 的 `validate_gemfile_env!` 在 `Definition` 构造（`src/celerite/definition.cr:51`）校验 `BUNDLE_GEMFILE` 指向的文件，缺失即抛 `GemfileNotFound`；`src/celerite/cli/commands.cr:126` 按命令打开该开关，`:434` 的 `RAW_GEMFILE_READ_COMMANDS` 把写类命令排除在外，`src/celerite/cli.cr:28` 每次 `CLI.run` 复位；`src/celerite/errors.cr:259-266` 给该异常 status 10 与 `wrap? == true`。
- 判据：`bash script/differential gemfile-env-missing`；`crystal spec spec/m7_gemfile_env_missing_spec.cr`
- 边界：差分夹具只跑 `list`/`check`/`platform`（`platform` 由 exit 0 转绿）；写类命令族见 C-cross-011。`spec/m7_gemfile_env_missing_spec.cr:122` 仍钉着 task-168 修复前的 `--gemfile` 两行文案，该例当前为红，属 spec 侧待更正，不影响本条的差分判据（双 profile PASS）。
- 生效：task-165（486c822）
- 取代：无

## C-cross-011 `BUNDLE_GEMFILE` 指向缺失路径时，写类命令保留 exit 1 的裸 `Errno::ENOENT`，未复刻参考的崩溃报告

- 状态：已声明差异
- 参考行为（4.0.24；2.7.2 同族，对应行 `lib/bundler/bundler.rb:524`）：`install`/`update`/`cache`/`package`/`pack`/`env`/`issue` 在 `Bundler.definition` 之前经 `bundler.rb:499-500` 的 `read_file` 读 Gemfile，`shared_helpers.rb:105-106` 的 `filesystem_access` 不转 ENOENT，于是 `friendly_errors.rb:50` 走 `request_issue_report_for`，输出 `bundler.rb:501:in 'File#initialize': No such file or directory @ rb_sysopen - <绝对路径>/Gemfile (Errno::ENOENT)` 加两段 backtrace，exit 1。
- 我方行为：未对齐，保持原状——这些命令被 `src/celerite/cli/commands.cr:434` 的 `RAW_GEMFILE_READ_COMMANDS` 排除在 `validate_gemfile_env!` 之外，仍以 exit 1 输出一行裸 ENOENT 消息，不产生崩溃报告与 backtrace。
- 判据：`bash script/differential gemfile-env-missing`
- 边界：该夹具只覆盖读类命令（C-cross-010），写类族当前无差分夹具，也无 spec 钉住现状；本条的不对齐结论来自逐命令 oracle 对照，见 `../compat-evidence/2026-11-23.md` 的「`BUNDLE_GEMFILE` 指向缺失路径时的错误形态（task-165）」节。`clean`（参考 exit 15）与 `exec`（两侧逐字同形）不在本条范围。
- 生效：task-165（486c822）
- 取代：无

## C-cross-012 `--gemfile` 指向缺失文件时报单行 `<展开路径> not found` 并 exit 10，折行交给统一的 word_wrap

- 状态：已实现
- 参考行为（4.0.24；2.7.2 同族）：`lib/bundler/definition.rb:38` 的消息是单行拼接；`friendly_errors.rb:31-36` 对 BundlerError 以 `wrap: true` 输出；`ui/shell.rb:139`/`:151` 只在 `wrap: true` 时折行，`:167-171` 的 `word_wrap` 按 `Thor::Terminal.terminal_width`（默认 80，`< 10` 回落 80）重折。
- 我方行为：`src/celerite/cli/commands.cr:1107-1110` 的 `--gemfile` 分支只抛单行消息（去掉了旧的字面 `\n`），`src/celerite/errors.cr:264-266` 的 `wrap? == true` 让它走统一折行，按 `THOR_COLUMNS` 决定行宽。
- 判据：`bash script/differential check-gemfile-missing`
- 边界：`spec/m7_gemfile_not_found_message_spec.cr` 当前 4 例 3 失败——它仍按修复前的「不折行/固定两行」写断言，更正由 task-171 承担；短路径、长路径、`THOR_COLUMNS=40` 三形态两侧逐字一致。`install --gemfile <缺失>` 不在此列：参考走 `bundler.rb:501` 的 ENOENT（见 C-cross-011）。
- 生效：task-168（1fc1b9d）
- 取代：无
