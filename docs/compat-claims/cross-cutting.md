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
