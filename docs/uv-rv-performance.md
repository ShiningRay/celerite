# uv 与 rv：高性能包管理工具参考

日期：2026-11-07

范围：Astral 的 Python 包与项目管理器 `uv`，以及 Spinel Cooperative 的 Ruby 版本与 gem 管理器 `rv`。

依据：前文讨论的官方发布说明、项目文档和官方基准。本文未在本地复测性能；倍率均属于特定基准，不是普遍保证。

## 1. 核心结论

两者都用 Rust 编写，但性能并非只来自 Rust：

- **uv** 优化依赖解析、下载、缓存和安装的完整链路，重点是原生执行、PubGrub、全局缓存，以及 Copy-on-Write 或硬链接。
- **rv** 当前最突出的优势是安装预编译 Ruby，省去本地源码编译；同时通过并行 gem 下载与安装、工具缓存复用提升速度。
- 两者共同的核心思想是：**减少重复工作，避免不必要的复制与编译，并并发执行相互独立的 I/O。**

## 2. uv 的性能机制

### 2.1 Rust 原生实现

- 以单个原生二进制分发，管理操作不需要先启动 Python 解释器。
- 版本解析、约束处理、元数据处理等工作由 Rust 完成。
- 原生实现为网络、解压和文件操作的并发提供了基础。

### 2.2 全局缓存

uv 使用全局缓存，避免重复下载和重复构建依赖：

- registry 依赖遵循 HTTP 缓存头。
- Git 依赖按已解析的 commit hash 缓存。
- 下载的 wheel 与源码构建的 wheel 都可缓存。
- 热缓存下重建虚拟环境或更新依赖时，可以省去大量网络与构建工作。

因此冷缓存和热缓存的性能差异很大。首次下载、网络缓慢或必须源码构建时，收益会缩小。

### 2.3 Copy-on-Write 与硬链接

从全局缓存安装到环境时，uv 在支持的文件系统上使用 Copy-on-Write 或硬链接，而非完整复制所有文件。

收益包括：

- 减少磁盘读写和安装时间。
- 多环境共享文件内容，减少磁盘占用。
- 保留各环境逻辑上的独立安装视图。

缓存目录与 Python 环境最好位于同一文件系统；不能链接时会退化为较慢的复制操作。

### 2.4 并行下载与安装

相互独立的下载、解包和安装准备可以并行执行，从而更好地利用网络、CPU 和磁盘。性能来自更短的 I/O 等待，而不只是单条指令执行更快。

### 2.5 PubGrub 与增量工作

- uv 使用 PubGrub 作为底层版本求解器。
- 解析、锁定、同步和安装整合在同一个工具内。
- 缓存元数据、锁文件及已有安装状态，可避免重复查询和未变化依赖的重复处理。

求解器重要，但不能把 uv 的全部性能归因于 PubGrub。缓存、网络与安装管线通常同样关键。

### 2.6 官方历史基准的边界

Astral 于 2024-02-15 发布 uv 时，在其 Trio 依赖基准中报告：

- 无缓存时，比 pip 和 pip-tools 快 8～10 倍。
- 热缓存时，快 80～115 倍。

这些数字对应特定版本、环境和负载，不代表所有项目，也不应当作当前版本的固定倍率。

## 3. rv 的性能机制与新特性

### 3.1 预编译 Ruby：最显著的加速来源

传统 `rbenv + ruby-build` 通常执行：

```text
下载源码 → configure → 编译 Ruby 与扩展 → 安装
```

rv 下载与操作系统、CPU 架构匹配的预编译 Ruby，再解压安装，省去本地编译 Ruby 的过程。

官方 Ruby 3.4.7 安装基准在一台 M5 MacBook Pro 上测得：

| 工具与模式 | 耗时 |
| --- | ---: |
| rv | 2.479 秒 |
| ruby-build，高性能模式 | 89.611 秒 |
| ruby-build，低功耗模式 | 159.752 秒 |

该基准中 rv 约快 36～64 倍。主要原因是**不做 Ruby 源码编译**，而不是 Rust 让同样的编译过程快几十倍。实际安装时间受网络和预编译产物可用性影响。

rv 还支持预编译的 `ruby-dev` 每日构建及 JRuby，降低测试开发版或不同 Ruby 实现的准备成本。

### 3.2 Rust、tokio 与 rayon

- Rust 原生二进制负责 Ruby 版本选择、环境发现与安装编排。
- `tokio` 用于并行网络下载。
- `rayon` 用于可并行处理的安装工作。

多个 gem 不必完全串行下载和准备。不过，含原生扩展的 gem 仍可能需要编译对应扩展；rv 没有消除这类构建成本。

### 3.3 工具下载与安装缓存

`rvx` 首次执行 gem CLI 时准备所需 Ruby 和 gems；后续运行复用已有下载与安装结果，因此可接近即时启动。

这与 uv 的热缓存相似：第二次更快，主要因为不再重复首次安装工作。

### 3.4 隔离的 gem CLI 环境

```bash
rvx rubocop
rvx rubocop@1.82
rv tool install rerun
rvx --with pg sequel
```

每个工具可拥有独立的 Ruby 与 gem 环境：

- 不受当前项目的 Gemfile 和 Ruby 版本影响。
- 避免为解决工具与项目的依赖冲突而反复调整环境。
- 隔离环境使缓存安装结果可以稳定复用。
- `--with` 支持为工具补充可选依赖。

隔离主要改善可靠性，并通过复用间接改善性能。

### 3.5 Ruby、gems 与命令执行统一管理

```bash
rv run ruby
rv run script.rb
rv clean-install
```

rv 将 Ruby 安装与切换、gem 工具执行、项目依赖安装整合起来，减少 rbenv、ruby-build、RubyGems 和 Bundler 之间的手工串联。

其他已发布能力包括 Windows 支持、私有 gem server 认证和 `rv fmt`。这些是功能或工作流改进，不应全部归为包安装加速。

### 3.6 尚不能视作完整 Bundler 替代

截至本文核对的官方规划与 README：

- `rv clean-install` / `rv ci` 已可按 `Gemfile.lock` 安装项目依赖。
- `rv sync`、`rv add`、`rv remove` 等项目级操作仍列在规划中。
- Ruby 安装基准不能用于声称 `bundle install` 或完整 Gemfile 工作流也获得同样倍率。
- 是否适合替换现有 Ruby 工具链，应按项目所需功能与兼容性单独验证。

## 4. 对比速查

| 维度 | uv | rv |
| --- | --- | --- |
| 主要生态 | Python | Ruby |
| 实现语言 | Rust | Rust |
| 最突出的加速点 | 全链路解析、缓存与链接安装 | 预编译 Ruby |
| 缓存 | 元数据、下载产物、构建产物等 | Ruby 与 gem 工具的下载、安装结果 |
| 减少文件复制 | Copy-on-Write、硬链接 | 本文未核到同等机制，不作此声明 |
| 依赖求解 | PubGrub，整合锁定与同步 | 已有锁文件安装；完整项目管理命令仍在扩展 |
| 并发 | 下载、解包与安装准备 | tokio/rayon 并行下载与安装 |
| 工具执行 | `uvx` / `uv tool` | `rvx` / `rv tool` |
| 主要性能边界 | 冷缓存、网络、源码构建、文件系统不支持链接 | 网络、预编译产物覆盖、原生扩展编译、功能兼容范围 |

## 5. 对 Celerite 的参考意义

可借鉴的是设计原则，而非照搬某个语言实现：

1. 优先消除重复下载、重复构建和无效安装，再优化局部代码。
2. 缓存键必须包含包内容、平台、Ruby ABI 与构建配置等必要身份信息。
3. 下载、校验和解包采用有界并发；有状态求解器不盲目并行化。
4. 不可变产物可使用硬链接；无法链接时明确回退复制。
5. 首次与再次执行、冷缓存与热缓存、有无原生扩展分别测量。
6. 所有性能声明必须附参考版本、负载、环境和缓存状态；功能规划不计入已交付性能。

Celerite 仍须保持 Ruby 兼容桥边界：任意 Gemfile DSL、gemspec、插件、原生扩展工具链及 Ruby 运行时语义不能为了性能被静态近似替代。

## 6. 官方资料

### uv

- [uv 官方发布说明（2024-02-15）](https://astral.sh/blog/uv)
- [uv 缓存文档](https://docs.astral.sh/uv/concepts/cache/)
- [uv 安装链接模式设置](https://docs.astral.sh/uv/reference/settings/#link-mode)

### rv

- [rv 官方仓库与 README](https://github.com/spinel-coop/rv)
- [rv 的 Ruby 安装基准](https://github.com/spinel-coop/rv/blob/main/docs/INSTALL_BENCHMARK.md)
- [rv 功能规划与完成状态](https://github.com/spinel-coop/rv/blob/main/docs/PLANS.md)
- [rv 设计动机](https://andre.arko.net/2025/08/25/rv-a-new-kind-of-ruby-management-tool/)
- [rv 0.5：CLI tools 与 Windows](https://spinel.coop/blog/rv-0.5-cli-tools-windows/)
- [rv 0.6：ruby-dev、rvx namespace 与私有源认证](https://spinel.coop/blog/rv-0.6.0-released/)
- [rv 0.7：JRuby、rv fmt 与 rvx --with](https://spinel.coop/blog/rv-0.7-released/)
