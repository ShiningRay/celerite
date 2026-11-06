# 兼容性契约

状态：规划基线。表中“原生”和“桥接”是目标架构，不表示已经实现。

## 版本口径

- 初始参考：Bundler 4.0.24 与 2.7.2；CI 固定参考 gem、Ruby/RubyGems 和上游 revision。
- 官方兼容文档当前列出 4.0 与 2.7 系列的最低 Ruby 3.2.0、RubyGems 3.4.1；2.6 和 2.5 为历史行为测试输入，不默认承诺支持。
- `BUNDLED WITH` 用于确定预期行为和兼容引擎，不等同于 Celerite 自身版本。
- “兼容”必须注明 Bundler、Ruby、RubyGems、OS 和 CPU 架构。

## 兼容矩阵

| 领域 | 必须保持的行为 | 目标路径 | 验证重点 |
|---|---|---|---|
| Gemfile DSL | 任意合法 Ruby 求值、source/gem/group/env/platforms/ruby/plugin/gemspec | 桥接；锁定快路径可跳过重复求值 | 动态 DSL、相对路径、异常、顺序 |
| gemspec | 本地 gemspec 的 Ruby 语义和依赖 | 桥接求值 + 原生模型 | 多个 gemspec、路径与依赖变化 |
| Lockfile | 所有 section（含 `PLUGIN SOURCE`）、格式、排序、保留 pin、checksum；按 profile 识别新字段 | 原生 | 字节/语义差分、冲突标记、未知字段、`Gemfile.lock`/`gems.locked` |
| CLI | 主命令、utilities、别名、flag、help、错误与退出码 | 原生；插件命令桥接 | Thor 行为、stdout/stderr、非 TTY |
| 配置 | local > ENV > global > default 的优先级与持久化 | 原生 | 键名正规化、remembered flags、mirror/build/local override、凭据脱敏 |
| 依赖解析 | PubGrub 解、候选分组、锁版本偏好、保守更新、冲突解释与有界放宽重试 | 原生 PubGrub + 策略层 | 解一致、最少解锁、无网络边界、预发布/本地优先重试 |
| Ruby/RubyGems 约束 | 当前及目标 Ruby、ABI、引擎和补丁版本 | 原生约束 + 桥接环境 | 预发布、引擎变体、要求不满足 |
| 平台 | ruby/具体平台、multi-ABI、平台增删与规范化 | 原生 | macOS/Linux、锁文件无意外漂移 |
| Compact Index | versions/info、ETag、Range、Repr-Digest、yank | 原生 | 206/200、坏 digest、缓存恢复 |
| rubygems source | 多 source、镜像、重定向、代理、鉴权、重试 | 原生 | source 隔离、脱敏、超时/限流 |
| Git source | branch/ref/tag/revision、submodule、glob | 原生 Git orchestration + gemspec 桥接 | 锁定 revision、离线缓存、 dirty tree |
| Path source | 相对路径、变更可见性、安装位置 | 原生 + gemspec 桥接 | 不缓存过期本地内容 |
| 下载和 cache | `.gem` 校验、vendor/cache、离线安装、清理 | 原生 | 失败原子性、并发与损坏恢复 |
| 安装 | spec、文件、权限、可执行文件、binstub | 原生 | 文件树差分、重复安装、失败清理 |
| 原生扩展 | Ruby 扩展构建与 ABI 绑定 | 桥接 Ruby/RubyGems 工具链 | 编译失败、build args、重装 |
| `exec`/runtime | load path、可执行发现、环境、退出与信号 | 原生 + Ruby runtime 适配 | `ruby -rbundler/setup`、嵌套 exec、Ruby shebang 的 `Kernel.load` |
| Ruby API | `Bundler.setup`、`require`、`definition` 等公开 API | Ruby 适配层 | 真实应用 require 与插件 API |
| `bundler/inline` | Ruby 脚本内 `gemfile` block 的 install/setup/require | Ruby 适配层 | 单文件脚本、隔离环境和失败行为 |
| 插件 | plugin install/list、命令、hook、source、PATH fallback | 桥接 | 事件顺序、hook 异常、源码插件 |
| 安全 | TLS、checksum、凭据和文件权限 | 原生默认不降级 | 篡改、日志脱敏、路径穿越 |

## CLI 基线

官方 Bundler 4.0.24 命令参考包含：

- primary：`install`、`update`、`cache`/`package`/`pack`、`exec`、`config`、`help`。
- utilities：`add`、`binstubs`、`check`、`show`/`info`、`list`、`licenses`、`fund`、`outdated`、`lock`、`init`、`gem`、`platform`、`clean`、`pristine`、`doctor`、`env`、`issue`、`remove`、`plugin`、`version`。
- 兼容处理：deprecated `console`、插件命令和 PATH 上的 `bundler-<command>`。

此列表是核对起点，不是全部验收。每项必须展开 flags、别名、配置和错误分支，并与固定版本实现/spec 对齐。

## 行为比较规则

1. 比较成功和失败；失败信息中的路径、临时目录和时间需正规化，其余文本不任意忽略。
2. 比较锁文件的语义与预期格式；若目标要求 byte-identical，则用对应测试明确标注。
3. 比较安装文件树、权限和可执行结果，而不只看退出码。
4. 至少执行一个 Ruby 应用来验证 load path 和 gems 可加载。
5. 不支持的输入快速失败，并报告功能与引擎；禁止静默改变 source、版本或安全策略。
6. 上游每个新版本先重跑基线；结果变化经评审后更新 fixture，不直接刷新 oracle 让测试转绿。

## 发布门禁

只有指定兼容矩阵中所有适用测试通过，且未解释的差异为零，才能对该矩阵声明“兼容”。“完整产品兼容”里程碑包括 Ruby DSL、插件和运行时，不仅限于 install/lock。
