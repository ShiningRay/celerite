# M8 L165 计划缓存只读闭合审计（task-278）

- 工作树：`C:\Temp\celerite-t278`
- 审计基线：`ac42563d74fff66906c973490424eda4cb6decfa`，起始工作树干净。
- 审计对象：`docs/roadmap.md:165/168`，以及 `PlanCache`、`Resolution`、安装命令、`InstallFastPath`、P1/P2 与 P3/P4 设计/交付证据。
- 审计方式：只读源码、文档与 Git 祖先关系核对。按任务禁令，未运行 Crystal、build、spec、differential 或 Rails；本文不把历史测试记作本轮实测。
- 写入范围：仅本文件；不修改 roadmap、claims、src、spec 或其它文档，不 push。

## 结论

**L165 当前不可勾。**

条目层的六成分键、版本化 envelope、凭据命名空间、损坏删除、原子替换、namespace 内裁剪、root-independent payload 与 remote-only locked-plan 重水合均有静态实现依据；P1、P2、P3、P4a 也都有当前 HEAD 祖先提交。

但整行尚不能闭合，原因有两类：

1. **产品缺口**：通用 `PlanCache.read` 只校验 format/key/namespace/digest，未重做 writer 的 payload 形状、portable 与 credential 检查；手工构造且 digest 自洽的 root-dependent/credential-bearing payload 可被通用 reader 判为 Hit。P3 的严格 locked payload 与当前计划全等比较缓解了当前命令路径，但通用 reader 尚未满足“未校验产物不得视为可用”。此外，P3 在 `ProcessLock` 前只取一次 `trusted_result`；普通路径随后虽然重新取得 evaluation，却在存在旧 Hit 时忽略 fresh evaluation，P3 读取与写入没有在锁内重验 evaluation/fingerprint。Gemfile 或 gemspec 在首次信任判定后、锁内复用前变化时，可能继续用旧 evaluation 构造计划。
2. **证据缺口**：P3/P4 设计文档没有实施后验证章节；现有 151/0、1393/0、双 profile 三夹具等均为历史采集，未绑定当前 `ac42563` 重跑。当前 HEAD 的完整 spec、全量 differential、第二 ABI、Linux/macOS、真 ACL、并发/崩溃、跨根与当前 RPC/IO 基准均未验证。

P4b 的持久化 installed snapshot **未实现**；设计明确它是可选完整性层，因此“未实现 P4b”本身不是 L165 阻断项。当前材料只能声明 P4a 的结构化 no-op 与普通文件内容摘要，不能声明 PlanCache snapshot 抗篡改，也不能把 symlink 目标内容变更纳入已验证范围。

## 1. 判据与审计口径

| 判据 | 要求 | 本轮口径 |
| --- | --- | --- |
| [docs/roadmap.md:165](<docs/roadmap.md#L165>) | 持久化、版本化解析/安装计划缓存；键含 source 身份、凭据隔离标识、checksum、platform、Ruby ABI、build 配置；损坏安全回退；未校验产物不得直接可用 | 六成分逐项核对实现与负向回落；再核对 P3/P4 是否真正接入、是否在命令成功与锁内发布、是否保留信任门 |
| [docs/roadmap.md:168](<docs/roadmap.md#L168>) | 无变化 lock/install Ruby 启动为 0（明确需 Ruby 的 source/plugin 除外）；指纹失效差分；复用前后输出/依赖/文件/退出码一致；基准含 wall/CPU/RSS/RPC/IO | L165 可独立判断，但 L168 的总验收仍要求上述证据。历史 {0,0,0,0} 或三夹具差分不等于当前 HEAD 全矩阵通过 |
| [docs/roadmap.md:164](<docs/roadmap.md#L164>) | 动态 DSL、插件、指纹不确定时走兼容路径 | 作为 P3/P4 安全回落的上位约束；PlanCache 开关不得授予信任 |

“已实现”只表示当前源码存在对应路径；“已验证”必须绑定到具体提交、命令、环境和结果。二者不互相替代。

## 2. 当前 HEAD 的交付谱系

以下提交均经 `git merge-base --is-ancestor <commit> ac42563` 核对为当前 HEAD 祖先。

| 切片 | 当前主线提交 | 实际状态 |
| --- | --- | --- |
| P1：六成分键、只读与损坏删除 | `7e2d0c2` | 已实现；历史 25 examples/0，未在本轮重跑 |
| P2：writer、原子替换、namespace 内 prune | `05aad11` | 已实现；历史 53 examples/0，未在本轮重跑 |
| P3：locked-plan 重水合与安装接线 | `5266632`、`521d35e`、`2c68b3e`、`e06c446` | 已接线；存在下述锁内信任复验缺口，历史 focused/双 profile 证据不完整 |
| P4a：结构化 no-op、2.7 汇总、计划摘要、最终事务 | `468739a`、`edd0ef5`、`92a6737`、`c1eda78`、`1f01482` | 已实现；当前 HEAD 未重跑，平台/并发/崩溃未验证 |
| P4b：持久化 installed snapshot 内容摘要 | 无 | 未实现；可选切片，未实现不得宣称 snapshot 抗篡改 |

证据对齐问题：

- [docs/roadmap-evidence/M8-plan-cache-plan.md:224-236](<docs/roadmap-evidence/M8-plan-cache-plan.md#L224-L236>) 与 [docs/compat-claims/M8-batch-bridge.md:300-308](<docs/compat-claims/M8-batch-bridge.md#L300-L308>) 记录 P2 实现为 `54c76f2`；该提交不是当前 HEAD 祖先。当前主线可用锚点是 `05aad11`，不能把另一条 cherry-pick 历史重复计为额外交付。
- P3 设计引用的 `0bce9b6` 同样不是当前 HEAD 祖先；当前主线以 `5266632` 等提交为准。
- [src/celerite/plan_cache.cr:12-15](<src/celerite/plan_cache.cr#L12-L15>) 仍写“no command integration”，已被当前 P3 接线取代。该注释是文档/证据缺口，不改变代码事实。

## 3. 六成分逐项核对

### 3.1 总表

| 成分 | 静态实现 | 判定 | 证据与边界 |
| --- | --- | --- | --- |
| source 身份 | `components_for` 规范化 GEM/PATH/GIT/plugin/自定义源；远端 URI 去 userinfo，拒 query/fragment；PATH 以 project root 绝对化；未知类型 miss | 基本具备 | [src/celerite/plan_cache.cr:197-301](<src/celerite/plan_cache.cr#L197-L301>)。P3 另限 GEM/Rubygems/Metadata，PATH/GIT/plugin 不进入 P3 |
| 凭据 namespace | 仅从 ENV 中 `BUNDLE_*` 且键含 `__` 或值含 URI userinfo 的项计算 16-hex namespace；读时精确比较嵌入 namespace；writer 拒敏感键、userinfo 与当前环境凭据值 | 具备 ENV 路径；配置/钥匙串未验证 | [src/celerite/plan_cache.cr:128-143](<src/celerite/plan_cache.cr#L128-L143>)、[src/celerite/plan_cache.cr:338-436](<src/celerite/plan_cache.cr#L338-L436>)、[src/celerite/plan_cache.cr:531-576](<src/celerite/plan_cache.cr#L531-L576>) |
| checksum | 所有 lock spec 必须有 checksum；P3 provenance 检查 checksum refresh 与 lock SHA-256；reader 重算 payload digest | 具备 | [src/celerite/plan_cache.cr:197-284](<src/celerite/plan_cache.cr#L197-L284>)、[src/celerite/plan_cache.cr:592-653](<src/celerite/plan_cache.cr#L592-L653>) |
| platform | 键含全部 locked platforms、本地 platform 与 `force_ruby_platform`；P3 信任门要求锁平台恰为 `[local]` | 具备；多平台保守 miss | [src/celerite/plan_cache.cr:197-284](<src/celerite/plan_cache.cr#L197-L284>)、[src/celerite/lock_fast_path.cr:139-204](<src/celerite/lock_fast_path.cr#L139-L204>) |
| Ruby ABI | 键含 `ruby_version`、`ruby_api_version`、`extension_api_version`；P3 还经 FastPath/EvalCache/runtime facts 信任门 | 具备静态实现；第二 ABI 未验证 | [src/celerite/plan_cache.cr:197-284](<src/celerite/plan_cache.cr#L197-L284>)、[src/celerite/lock_fast_path.cr:64-90](<src/celerite/lock_fast_path.cr#L64-L90>) |
| build 配置 | 每个 spec 的 `build.<name>` 进入 canonical components；canonical JSON 排序稳定；未知值 miss | 具备 | [src/celerite/plan_cache.cr:176-284](<src/celerite/plan_cache.cr#L176-L284>) |

### 3.2 source 身份

- P1/P2 的通用键可以表达 PATH/GIT/plugin/自定义源；PATH 源显式包含 project root，因此该键**不承诺跨项目根复用**。这是保守处理，不是把绝对路径写入 payload。
- P3 的实际命令路径更窄：`gem_sources_only?` 只允许 GEM/Rubygems/Metadata，`LockFastPath` 的 remote-only 检查同时覆盖 dependency source 与 evaluation sources。见 [src/celerite/plan_cache.cr:592-630](<src/celerite/plan_cache.cr#L592-L630>)、[src/celerite/lock_fast_path.cr:380-384](<src/celerite/lock_fast_path.cr#L380-L384>)。
- 因而 L165 的 source 成分在“键可表达”层面成立，在“当前命令可利用”层面仅覆盖 remote-only GEM。PATH/GIT/plugin 必须回退兼容路径，不能把 miss 写成命中。

### 3.3 凭据隔离

- `credential_namespace` 只读当前进程 ENV，不读取原始 ENV/config 到 payload；namespace 变化会改变条目目录与 key。
- `read` 对嵌入 namespace 与当前 namespace 不等按 corrupt 处理并删除，避免把另一凭据空间的条目当命中。
- writer 除检查敏感键与 URI userinfo 外，还扫描当前环境中的实际凭据值，防止明文落盘。
- 未验证：`.bundle/config`、keychain、外部 credential helper 或非 `BUNDLE_*` 形态的凭据变化是否都进入 namespace。当前证据只能支持 ENV 路径，不能外推为所有凭据来源均已隔离。

### 3.4 checksum、platform、ABI、build

- checksum 缺失、需要 refresh、锁 SHA 变化均使 P3 provenance 不成立；reader 还重算 canonical key 与 payload digest。
- platform 同时进入键；P3 借信任门把多平台锁收紧为单平台，避免用 ruby 行冒充 native 行。
- ABI 三视图进入键，runtime record 还要求与当前 facts 全等。未知 ABI 不猜、不命中。
- build args 按 spec 名读取并 canonical 排序；环境形态的 `BUNDLE_*__*` 同时进入 credential namespace。extensions 目录本身不证明 build args 未变，因此 build 必须来自配置键，不能来自 marker。

## 4. unknown/corrupt 与安全回落

| 情况 | 代码行为 | 判定 |
| --- | --- | --- |
| 六成分缺失、类型错误、未知 source/platform/ABI/build | `components_for` 返回 nil；调用方 miss | 安全 |
| 条目不存在、I/O 失败 | miss，不伪造 hit | 安全 |
| 超限、format/key/digest/namespace 不符 | `read` 判 corrupt 并删除目标条目；locked schema 由 `read_locked` 另验 | 基础安全 |
| payload 含绝对根路径、盘符/UNC、`file://`、任意 `..` 段、敏感键、userinfo 或当前凭据值 | writer 拒绝；通用 `read` 未重做 portable/credential 检查 | 通用 reader 有 G2 缺口；P3 当前路径由严格 schema 与当前计划全等比较缓解 |
| namespace 不匹配 | 不读取为可用，按 corrupt 删除当前 namespace 路径下的目标 | 安全 |
| prune | 只遍历当前 namespace；最多 256 条/16 MiB；按 mtime/path 淘汰 | 安全；不清理其它 namespace |
| 原子替换 | 同目录 temp → flush → fsync（不支持时忽略）→ `File.rename` 覆盖；不先 unlink | 具备进程内原子发布语义；目录 fsync/断电耐久性未验证 |
| writer 不可写、rename 失败、temp 清理失败 | 返回失败/诊断，不改变 install 退出码 | 安全；历史 focused 有覆盖，本轮未重跑 |
| PATH/GIT/plugin、warnings、runtime mismatch、checksum refresh、Bundler profile 不符 | P3 context/provenance/trusted gate miss，回退普通安装 | 安全 |
| 默认 `plugins=true` 且没有可信空插件证书 | 不允许 P3 context；走 Ruby plugin preflight/兼容路径 | 安全 |
| PlanCache 关闭 | 不读、不写、不 prune；只影响优化，不授予信任 | 安全 |

主要证据：[src/celerite/plan_cache.cr:338-520](<src/celerite/plan_cache.cr#L338-L520>)、[src/celerite/plan_cache.cr:522-576](<src/celerite/plan_cache.cr#L522-L576>)、[src/celerite/plan_cache.cr:592-749](<src/celerite/plan_cache.cr#L592-L749>)、[src/celerite/install_fast_path.cr:116-141](<src/celerite/install_fast_path.cr#L116-L141>)。

### 4.1 root-independent 的准确边界

- P3 locked payload 只保存远端 GEM 的本地行、额外平台行与 provenance；写入前执行 portable/credential 扫描，不保存绝对 install root、gemspec 路径或原始 ENV/config。
- `read_locked` 除 envelope/provenance 外，还与当前 `resolution.locked_plan_rows` 逐项相等。因此 payload 不是“换个根就直接执行”的权威产物；当前 Definition、当前 evaluation 与当前锁行仍决定语义。
- 通用 `read` 没有调用 `valid_payload?`、`portable_json?`、`credential_free_json?` 或 `contains_environment_credential?`；这些检查目前只在 writer。见 [src/celerite/plan_cache.cr:338-377](<src/celerite/plan_cache.cr#L338-L377>)、[src/celerite/plan_cache.cr:393-436](<src/celerite/plan_cache.cr#L393-L436>)。所以“writer 不写 root-dependent payload”成立，“通用 reader 拒绝 root-dependent payload”尚不成立。
- 通用 P1/P2 对 PATH 源会把 project root 纳入 source identity，所以 PATH 键不是 root-independent。P3 直接拒绝 PATH，避免这一歧义。
- 设计要求的“跨项目根”验收仍未看到当前 HEAD 的实测；静态可移植检查不能替代跨根差分。

## 5. P1/P2/P3/P4 实际状态

| 切片 | 设计职责 | 当前实现 | 闭合判断 |
| --- | --- | --- | --- |
| P1 | 只算键、只读、损坏删除、unknown miss | `FORMAT/LAYOUT`、六/九成分 canonical key、namespace、read/delete、debug | 已实现，但通用 reader 缺 payload 安全复验（G2）；历史验证未绑定当前 HEAD |
| P2 | writer、原子替换、256 条/16 MiB、namespace 内 prune | `write/store`、`prune`、同目录 temp/fsync/rename、portable/credential 检查 | 已实现；历史 53/0；并发/ACL/断电未验证 |
| P3 | 在 trusted remote-only locked install、no-op miss 时重水合计划；不能把快路径收益重复计给 PlanCache | `commands_install` 在 reuse+trusted+context 时 `read_locked`/`from_plan`；成功尾部 `write_locked`；miss 回落 `Resolution.new` | 已接线，但锁内信任复验不足，且当前证据不足，不能据此勾 L165 |
| P4a | 继续以 `InstallFastPath` 为权威 no-op；修 2.7 `+1` 与多平台 false miss；锁内复验；最终证书事务 | bare install 拒绝矩阵、`plan_evidence`、锁内 `revalidate?`、共享 summary、nonce/plugin/runtime 事务 | 已实现；历史热路径 {0,0,0,0} 与 focused 证据不是当前 HEAD 全量验收 |
| P4b | 可选 installed snapshot 作为额外完整性层 | `PAYLOAD_KEYS` 虽含 `installed_snapshot`，但只有三段形状检查；未发现 snapshot 的生产、消费、内容 digest 或复用校验 | 未实现；不得宣称 PlanCache snapshot 抗篡改 |

P3 的关键正确性依据是 [src/celerite/plan_cache.cr:638-653](<src/celerite/plan_cache.cr#L638-L653>)：除了 schema/provenance，还把 payload 计划与当前 `locked_plan_rows` 全等比较。缓存不能单方面提供未经核对的计划行。

## 6. 事务、锁与证书交互

### 6.1 已有正确部分

1. `InstallFastPath` 的 hot path 在 `ProcessLock` 内重新执行 `trusted_attempt`、digest/nonce/lock identity、`plan_evidence` 与 plugin 检查，命中后才 emit/rotate。见 [src/celerite/install_fast_path.cr:256-273](<src/celerite/install_fast_path.cr#L256-L273>)。
2. `remember_after_install` 先验证 EvalCache entry/fingerprint/document/runtime/install root/lock/plan/plugin，再依次发布 nonce 证书、plugin cache、最终 RuntimeRecord；失败恢复旧 eval/plugin 快照。见 [src/celerite/install_fast_path.cr:290-412](<src/celerite/install_fast_path.cr#L290-L412>)。
3. `SuccessCertificate` 严格绑定 command/profile/ruby identity/lock/plugin/install；install 命令必须有 install binding，lock 不得携带 install binding。见 [src/celerite/cache_identity.cr:241-292](<src/celerite/cache_identity.cr#L241-L292>)。
4. P3 writer 位于锁文件写入之后、install 证书最终提交之前；writer 失败不影响命令。RuntimeRecord 仍是最终信任提交标记。见 [src/celerite/cli/commands_install.cr:1062-1087](<src/celerite/cli/commands_install.cr#L1062-L1087>)。
5. PlanCache 不是信任证书。即使证书事务回滚后残留一个条目，后续 P3 仍必须先取得可信 Hit，不能仅凭条目存在而命中。

### 6.2 产品缺口 G1：P3 锁内信任复验不足

当前顺序是：

1. [src/celerite/cli/commands_install.cr:281-284](<src/celerite/cli/commands_install.cr#L281-L284>)：在 `ProcessLock` 前计算一次 `trusted_result`。
2. [src/celerite/cli/commands_install.cr:323-369](<src/celerite/cli/commands_install.cr#L323-L369>)：启动 bridge，重新 `GemfileEvaluator.fetch`，但 [src/celerite/cli/commands_install.cr:334-338](<src/celerite/cli/commands_install.cr#L334-L338>) 只要旧 Hit 存在就忽略 fresh `batch.evaluation`；之后才创建 install root 与 `ProcessLock`。
3. [src/celerite/cli/commands_install.cr:472-499](<src/celerite/cli/commands_install.cr#L472-L499>)：锁内直接使用旧 `trusted.evaluation` 构造/读取 locked plan，没有再次调用 `trusted_attempt`，也没有比较 fresh fingerprint/evaluation digest。
4. `resolution_can_reuse?` 只调用 `resolution.reuse_locked?`；后者使用 `@evaluation.dependencies` 与锁比较，而此处 `@evaluation` 仍是旧 Hit 的 evaluation。见 [src/celerite/cli/commands_install.cr:1132-1136](<src/celerite/cli/commands_install.cr#L1132-L1136>)、[src/celerite/resolution.cr:1478-1530](<src/celerite/resolution.cr#L1478-L1530>)。

因此，首次信任判定后 Gemfile/gemspec 指纹发生变化，但锁文件未变时，fresh evaluation 不能使旧 Hit 自动失效。P3 可能继续用旧依赖/源集合构造当前计划。该缺口与 [docs/roadmap-evidence/M8-plan-cache-p3-p4-plan.md:44-65](<docs/roadmap-evidence/M8-plan-cache-p3-p4-plan.md#L44-L65>) 的“evaluation 只能来自可信 Hit、每次复用前重验信任”边界不一致，是本轮判 L165 不可勾的产品原因之一。

最小修复不是绕过信任门，而是在锁内、P3 read 与 writer 前重跑 `trusted_attempt(definition, "install")`，或至少用 fresh evaluation/fingerprint 与旧 Hit 的 digest 做精确比较；不一致立即清空 trusted、跳过 P3，走兼容路径。writer 前还应再次确认锁 SHA 与 evaluation/fingerprint 未变。

### 6.3 产品缺口 G2：通用 reader 未重做 payload 安全校验

`read` 在 digest 自洽后直接返回 payload；`valid_payload?`、`portable_json?`、`credential_free_json?` 与 `contains_environment_credential?` 只在 writer 调用。见 [src/celerite/plan_cache.cr:338-377](<src/celerite/plan_cache.cr#L338-L377>)、[src/celerite/plan_cache.cr:393-436](<src/celerite/plan_cache.cr#L393-L436>)、[src/celerite/plan_cache.cr:522-576](<src/celerite/plan_cache.cr#L522-L576>)。

因此，手工构造一个 key/namespace 正确、digest 重算正确的条目，即使 payload 带绝对路径、`..`、敏感键或凭据值，通用 `read` 仍可判 Hit。当前 P3 调用 `read_locked` 后还有严格 `LOCKED_KEYS`、provenance 全等和当前计划全等比较，实际命令路径不易直接消费任意 payload；但 P1/P2 的通用 reader 契约本身不完整，也不能满足 L165“未校验产物不得视为可用”的要求。

最小修复是在 digest 校验后、返回 Hit 前重做 payload 形状、portable、credential 与环境凭据值检查；失败按 corrupt 删除。需补“合法 digest 但 root-dependent/credential-bearing payload”reader 反例，不能只测 writer 拒绝。

### 6.4 产品缺口 G3：锁文件删除竞争

`ProcessLock` 在 close 时先 unlock/close，再删除 lock 文件。见 [src/celerite/cli/commands_install.cr:43-85](<src/celerite/cli/commands_install.cr#L43-L85>)。这是一种常见竞态：等待者可能仍持有旧 inode，而新进程已创建并锁定新文件，两个进程可同时进入临界区。

PlanCache 自身使用原子 rename，但安装证书与 P3 writer 都依赖 `ProcessLock` 提供跨进程互斥。当前没有真实并发证据，不能把“文件存在时 flock”直接外推为无删除竞争。最小修复是保留稳定 lock 文件、不删除，或采用明确证明安全的锁协议，并增加双进程并发验收。

### 6.5 产品/声明边界 G4：P4b 与 symlink 内容

`plan_evidence` 已哈希 gemspec、gem 目录中的普通文件与 native marker；但 symlink 只记录 link target，不读取目标内容，也不验证目标是否位于 install root 内。见 [src/celerite/install_fast_path.cr:539-611](<src/celerite/install_fast_path.cr#L539-L611>)。

所以：

- 普通文件内容变化可进入 no-op 计划摘要；
- symlink 指向目标的内容变化、越界 symlink 不在当前已验证范围；
- 该摘要是每次热路径重算的证书证据，不是 PlanCache P4b 的持久化 snapshot；
- 不得把 P4a 的描述写成“安装树任意篡改均可发现”。

## 7. RPC 与性能口径

### 7.1 可以陈述的事实

- P3 普通安装仍创建 bridge，仍需要当前 Ruby environment；它不是零 Ruby 路径。见 [src/celerite/cli/commands_install.cr:323-369](<src/celerite/cli/commands_install.cr#L323-L369>)。
- `GemfileEvaluator.fetch` 调用 `evaluate_batch` API，但 `Bridge::Client#evaluate_batch` 会先查 EvalCache；warm hit 可本地返回，不发该 RPC。冷缓存会发一次 `evaluate_batch`。见 [src/celerite/gemfile_evaluation.cr:35-48](<src/celerite/gemfile_evaluation.cr#L35-L48>)、[src/celerite/bridge/client.cr:1048-1058](<src/celerite/bridge/client.cr#L1048-L1058>)。
- P3 的可信 Hit 依赖 EvalCache/FastPath 信任链；冷 EvalCache 不能作为 P3 的收益场景。不能宣称“冷 EvalCache 省两个 RPC”。
- 默认 Bundler 4.x layout 在 default cache 文件存在且 SHA 可读时使用 optimized local candidate，可避免 `bundler_cache_file`；custom layout 仍需要一个 authoritative RPC。见 [src/celerite/resolution.cr:411-444](<src/celerite/resolution.cr#L411-L444>)。
- 历史 focused 实测记录：默认 layout 的 base/hit RPC 差额为 **1**，custom layout **相等**。见 [docs/compat-evidence/2026-11-26.md:23-24](<docs/compat-evidence/2026-11-26.md#L23-L24>)。
- 无变化 no-op 的历史四计数为 `{0,0,0,0}`；这是 `InstallFastPath` 的收益，不是 P3 在冷 EvalCache 下新增的收益。

### 7.2 不能使用的数字

[docs/roadmap-evidence/M8-plan-cache-samples.md:3-50](<docs/roadmap-evidence/M8-plan-cache-samples.md#L3-L50>) 的 10 RPC/315715 B、1053–1146 ms、2 RPC/1911 B、404–794 ms 与约 300 KB 都属于旧基线 `053036e`/task-254。它们不是当前 `ac42563`、P3 或 P4 的实测，不能写成当前收益。

本轮没有采集 wall/CPU/RSS/RPC/IO 的当前基线，因此 L168 的性能证据仍缺。

## 8. 证据缺口

1. **当前 HEAD 未复跑**：任务明确禁止 Crystal/build/spec/differential/Rails。P2 的 53/0、P3 的 151/0、合流后的 1393/0 都只能作为历史证据，见 [docs/compat-claims/M8-batch-bridge.md:271-306](<docs/compat-claims/M8-batch-bridge.md#L271-L306>)、[docs/compat-evidence/2026-11-26.md:3-80](<docs/compat-evidence/2026-11-26.md#L3-L80>)。
2. **P3/P4 设计文档无实施后验证章节**：[docs/roadmap-evidence/M8-plan-cache-p3-p4-plan.md:278-295](<docs/roadmap-evidence/M8-plan-cache-p3-p4-plan.md#L278-L295>) 仍是实施顺序/未验证项；不能当交付验收。
3. **负向矩阵未绑定当前 HEAD**：六成分逐项变化、unknown/corrupt、namespace 变化、PATH/GIT/plugin/checksum miss、Bundler/profile/runtime mismatch、writer fail、跨根复用，缺当前提交的统一结果；通用 reader 对合法 digest 但 root-dependent/credential-bearing payload 的反例也未验证。
4. **平台与 ABI 不足**：Linux/macOS、第二 Ruby ABI、不同 extension API 未验证。
5. **并发与崩溃不足**：真 ACL、多进程并发、kill/断电、目录 fsync、跨文件原子性未验证。
6. **差分与性能不足**：全量 differential 未跑；当前 wall/CPU/RSS/RPC/IO 未采集；旧样本不能替代。
7. **CI 门不足**：[.github/workflows/ci.yml:30-53](<.github/workflows/ci.yml#L30-L53>) 有全量 spec/differential job，[.github/workflows/fast-path-gates.yml:87-112](<.github/workflows/fast-path-gates.yml#L87-L112>) 有 lock tamper/old binary install gate；本次 grep 未发现 `CELERITE_PLAN_CACHE` 或 plan-cache 专门门。
8. **凭据来源未穷尽**：ENV namespace 有实现与历史测试；config/keychain/credential helper 的隔离未验证。
9. **P4b 无交付**：`installed_snapshot` 只有形状检查，没有生产/消费/内容校验；symlink 目标内容不在已验证范围。

## 9. 最小闭合切片

建议按依赖顺序推进；本审计不执行这些写操作。

### S1：补通用 reader 的 payload 安全复验（阻断项）

- 在 digest 校验后、返回 Hit 前重做 `valid_payload?`、`portable_json?`、`credential_free_json?` 与环境凭据值检查。
- 失败按 corrupt 删除；locked payload 还需保留严格 schema/provenance/当前计划全等比较。
- 增加“key/namespace/digest 自洽但 payload root-dependent 或含凭据”的 reader 反例；writer 拒绝测试不能替代 reader 测试。

验收：修复前通用 reader 可返回该类 payload，修复后稳定 miss+delete；P3 正常命中不受影响。

### S2：修 P3 锁内信任复验（阻断项）

- 在 `ProcessLock` 内、P3 read 前重新取得当前 evaluation/fingerprint，并重跑 `trusted_attempt(definition, "install")`，或做等价的 fresh digest 精确比较。
- 不一致时清空旧 Hit，P3 直接 miss，使用 fresh evaluation 的兼容路径。
- P3 writer 前再次确认 evaluation/fingerprint、锁 SHA、当前计划行未变。
- 增加确定性反例：首次 trusted 与锁内复用之间改变 Gemfile/gemspec；必须 miss，不得用旧依赖生成计划。

验收：反例在修复前能命中旧计划，修复后稳定回落；双 profile 输出/锁/退出码与关闭 PlanCache 一致。

### S3：锁定 ProcessLock 并发语义（阻断并发声明）

- 不删除稳定 lock 文件，或采用可证明安全的锁协议。
- 双进程同时 install：同一项目只能有一个写入者；证书最终提交、PlanCache writer、lockfile 写入不交叉。
- 覆盖 Windows 与至少一个 POSIX 平台；记录 ACL/权限失败行为。

### S4：补当前 HEAD 的 L165 负向与跨根证据

- 六成分逐项变化、unknown/corrupt、namespace mismatch、checksum/platform/ABI/build mismatch。
- PATH/GIT/plugin/warnings/checksum refresh/frozen/deployment/shared/force-ruby/clean/cooldown 全部 miss。
- remote-only 跨项目根：payload 不含绝对根；命中仍使用当前 Definition/evaluation/install root。
- writer 不可写、rename 失败、temp 清理失败不改变命令结果。
- 绑定修复提交，记录命令、profile、环境、计数与退出码。

### S5：明确 P4 范围并补 L168 总验收

- 若只保留 P4a：明确声明无 PlanCache snapshot 抗篡改能力，symlink 目标内容不在保证范围。
- 若要 P4b：新增有界持久 manifest 的生产/消费/内容 digest 校验、锁内复验与 symlink 策略，并测量全树哈希成本；不能只保留 `installed_snapshot` 形状字段。
- 双 profile 运行 lock/install 差分，覆盖指纹失效与复用前后 stdout/stderr、依赖、lock、安装树、退出码。
- 采集 wall/CPU/RSS/RPC/IO；RPC 分默认 optimized/custom、warm/cold，禁止把旧 2 RPC 写成冷 EvalCache 收益。

### S6：修正证据文档（后续授权任务）

- 更新 `plan_cache.cr` 的过时“no command integration”注释。
- 在 P3/P4 设计中补实施后验证章节，或新增独立证据文档并互链。
- 将 P2/P3 的当前主线祖先提交与旧 cherry-pick 提交分开记录。

## 10. 未验证项清单

- 本轮未运行 Crystal、`shards build`、`crystal spec`、`script/differential`、Rails 或任何 binary 命令。
- 当前 HEAD 的完整 spec、M8 family、format/build/diff check 之外的产品门禁未重跑。
- 通用 reader 对合法 digest 但 root-dependent/credential-bearing payload 的反例未执行；结论来自 `read` 与 writer 的调用差异。
- P3 在真实 Gemfile/gemspec 中途变化下的 TOCTOU 反例未执行；结论来自源码顺序与 `reuse_locked?` 的 evaluation 来源。
- 跨项目根 remote-only 命中、第二 ABI、Linux/macOS、真 ACL、多进程并发、kill/断电未验证。
- `.bundle/config`、keychain、credential helper 的 namespace 隔离未验证。
- P4b snapshot 未实现；symlink 目标内容/越界目标未验证。
- 当前 wall/CPU/RSS/RPC/IO 未采集；历史 focused 的默认 1 RPC 差额不能替代当前基准。

## 11. 最终裁定

- **六成分键、版本化 envelope、namespace 隔离与原子替换：静态实现成立。**
- **unknown/corrupt 基础校验成立；通用 reader 的 payload 安全复验不完整（G2）。**
- **root-independent writer 与 P3 payload 静态约束成立；通用 reader 尚不能独立拒绝 root-dependent payload。**
- **P3：已接线，但锁内信任复验不足（G1），且历史验证不能替代当前 HEAD 验收。**
- **P4a：已实现；P4b：未实现且为可选，不得宣称 snapshot 抗篡改。**
- **L165：不可勾。** 先修 G1/G2，并补 S1/S2/S4 的当前提交证据；并发声明还需 S3。L168 另需 S5 的差分与性能证据。
