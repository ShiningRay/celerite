# M8 L161 批次级求解协议落地设计（task-256）

**Oracle**：L161 原文「定义版本化、批次级求值协议：一次导出完整 dependencies、groups、source、autorequire、platform、Ruby 约束和插件声明；一次提交完整候选集并返回解，禁止在 PubGrub 循环中逐版本跨桥。」现状裁定见 `docs/roadmap-evidence/M8-closure-audit.md:10`；旧设计明确不实现后半句，见 `docs/roadmap-evidence/M8-batch-protocol.md:18`。本文不改写验收口径。

**范围**：Oracle = main `ad97fa5`；参考 = 已安装 Bundler 4.0.24（`C:/Ruby40-x64/lib/ruby/gems/4.0.0/gems/bundler-4.0.24`）。只读调研；未起服务、未跑差分/build/spec。行号锚定下列文件。本文只交付设计，不宣称实现或闭合 L161。

## 0. 结论先行

1. 推荐 v3 `solve_batch` 的**主路径**由 Ruby 侧调用 Bundler 4.0.24 真 resolver：全候选集在一次请求内提交，解在一次响应内返回；解算期间不得再跨桥。
2. 可纯数据化的只有候选索引与 GEM source 的求值面；PATH/GIT/PLUGIN、动态 DSL、未知 typed source 仍需兼容路径。不得把这些场景写成「已一次提交并返回解」。
3. 把完整候选集一次送给 Crystal 再本地 PubGrub，只满足「禁止在 PubGrub 循环中逐版本跨桥」，不满足「一次提交完整候选集并返回解」的响应语义；除非首辅改验收口径，否则不能据此勾 L161。

## 1. 现有 v2 导出与七类缺口

协议 v2：`src/celerite/bridge/client.cr:16-17`（`PROTOCOL=2`, `PROTOCOL_MIN=1`）；envelope `{proto,id,op,payload}` / `{proto,id,ok,result}` 见 `assets/bridge/server.rb:11-19`；能力表 `:70`。`evaluate_batch` 的 `include` 只有 `gemspecs`/`fingerprint`，见 `src/celerite/bridge/client.cr:1019-1045`、`assets/bridge/server.rb:663-679`；响应上限 4 MiB（前者 `:36-37`、后者 `:43-44,:1439-1444`），不是候选集上限。

| L161 信息类 | v2 已有字段 | 缺失 / 不能充当候选级真相 |
|---|---|---|
| dependencies | `name/requirements/groups/platforms/autorequire/force_ruby_platform/gemspec_dev_dep/source`；`src/celerite/bridge/client.cr:622-636`，`assets/bridge/server.rb:314-351` | 无 root requirements 与 candidate dependencies 的分离；无解图边 |
| groups | 每个 dep 的 `groups`；同上 | 无 `with/without/optional` 策略；`src/celerite/cli/commands_surface.cr:1423-1428` 才读配置 |
| source | dep.source / 顶层 sources；`src/celerite/bridge/client.cr:638-656,719-734`，`assets/bridge/server.rb:1346-1385` | 只描述声明；无稳定 `source_id`、候选 source 归属、checksum store 或 source 对象身份 |
| autorequire | dep.autorequire；`src/celerite/bridge/client.cr:632` | 仅运行时 require 元数据，不参与 PubGrub；无候选级对应字段 |
| platform | dep.platforms；`src/celerite/bridge/client.cr:628`；运行环境另需 `op_ruby_environment`，`assets/bridge/server.rb:223-290` | 无 resolution platforms/added/removed；`src/celerite/resolution.cr:2360-2383`、无候选 variant platform |
| Ruby 约束 | `ruby/ruby_version/patchlevel/engine/engine_version`；`src/celerite/bridge/client.cr:719-734` | 无候选 `required_ruby_version`/`required_rubygems_version`；参考解析在 `bundler/endpoint_specification.rb:157-193` |
| plugin | 声明序列化见 `assets/bridge/server.rb:1346-1360` | 不在 batch；`plugin_gemfile_eval` 是独立 op，只回 names（`assets/bridge/server.rb:1388-1405`）；插件索引/能力/hook 不同次导出 |

无变化快路径先于求解：`src/celerite/resolution.cr:1095-1249`，`run_resolution` 到 `:1884` 才调用。现跨桥按名字懒取候选：`src/celerite/resolver/source.cr:204-217` → `src/celerite/resolution.cr:1893-1899,952-983`；按版本读取本地 spec 见 `src/celerite/resolution.cr:882,929,1122-1123`。

## 2. Bundler 4.0.24 求解入口与对象边界

- 入口：`bundler/definition.rb:669-671` `resolver = new_resolver(resolution_base)`；`:1321-1328` 构造 `Resolver::Base.new(source_requirements, expanded_dependencies, last_resolve, @platforms, locked_specs:, unlock:, prerelease:, prefer_local:, new_platforms:, explicit_unlocks:)`，再 `Resolver.new(base, gem_version_promoter, most_specific_locked_platform)`；promoter 默认见 `:168-170`，级别/严格度见 `bundler/gem_version_promoter.rb:29-44`。
- 运行：`bundler/resolver.rb:19-26` 构造；`:28-37 start`；`:39-82 setup_solver` 首次按 name 从 `source.specs.search(name)` 取候选；`:85-91` 调 `PubGrub::VersionSolver#solve` 并以 `SpecSet` 返回；`:257-304` 做平台和版本组；`:328-330` 排序由 promoter 决定；解决失败自动 relax 见 `:92-122`。
- 索引：`bundler/index.rb:7-11,19-24,51-77,113-137,159-163` 支持 `Index.build`、`add`、`search`、duplicate merge。`bundler/fetcher.rb:178-195` 构造 `EndpointSpecification.new(name,version,platform,fetcher,dependencies,metadata)` 并写入 `source.checksum_store`；`bundler/endpoint_specification.rb:12-26,157-193` 解析 checksum/ruby/rubygems metadata。
- source 不能退化为 URL 字符串：`bundler/source_map.rb:17-57` 要求真实 source 对象提供 `spec_names`、`unmet_deps`、`add_dependency_names`；`bundler/resolver.rb:306-308` 用 `@source_requirements[name] || @source_requirements[:default]`。纯 GEM 可在 Ruby 侧用预构造 `Index` 包装一个 `Source::Rubygems` 对象并覆写 `specs` 返回冻结索引；此处是**设计 Proposal**，不是现成 API。
- PATH：`bundler/source/path.rb:16-39,98-108,159-179` 需本地目录、glob、gemspec 与 `spec.source=self`。GIT：`bundler/source/git.rb:12-33,190-199,416-434` 需 uri/ref/revision、fetch/checkout、本地 gemspec。PLUGIN：`bundler/plugin/api/source.rb:45-52,62-92,136-150` 含可执行 `fetch/install/cache/unlock`、checksum store、插件 gemspec；`options_to_lock` 也由插件实现。三者不能从纯 JSON 还原完整对象语义。

## 3. v3 `solve_batch` 协议（Proposal）

Envelope 沿用 `assets/bridge/server.rb:11-19`，加 `"schema":"celerite.solve_batch/3"` 与 `proto=3`；`features` 增 `solve_batch`。请求字段：

```json
{
  "schema": "celerite.solve_batch/3",
  "evaluation": {
    "gemfile": {"path_sha256": "...", "sha256": "..."},
    "fingerprint": {"format":"celerite-eval-v1","digest":"...","state":"deterministic",
                    "state_reason":null,"verify_files":[{"role":"gemfile","path":"...","sha256":"..."}],
                    "runtime":{},"config":{}},
    "sources": [{"source_id":"...","type":"Rubygems|Path|Git|Plugin|Metadata",
                 "name":null,"identity_sha256":"...","uri_redacted":"...","remotes":[],
                 "path":null,"revision":null,"ref":null,"branch":null,"tag":null,
                 "glob":null,"submodules":null,"plugin_type":null,"lock_options":{},
                 "materialization":"pure_data|path|git|plugin|unknown"}],
    "plugins": [{"name":"...","version":null,"source_id":null,"declaration_sha256":"..."}],
    "groups": {"with":[],"without":[],"optional":[],"all":[]}
  },
  "requirements": [{"name":"...","requirements":[">= 1"],"source_id":"...",
                    "groups":[],"platforms":[],"autorequire":[],
                    "force_ruby_platform":false,"gemspec_dev_dep":false,"direct":true}],
  "candidates_by_source": {"sid1": [{"name":"...","version":"...","platform":"ruby",
    "dependencies":[{"name":"...","requirements":[">= 0"]}],
    "required_ruby_version":null,"required_rubygems_version":null,
    "created_at":null,"checksum":{"algorithm":"sha256","value":"..."}}]},
  "locked_base": {"sha256":"...","specs":[{"name":"...","version":"...","platform":"ruby",
    "source_id":"...","dependencies":[],"checksum":null}]},
  "promotion": {"level":"patch|minor|major","strict":false,"pre":false,
    "unlock":false,"conservative":false,"prefer_local":false,"local_only":false},
  "constraints": {"ruby_version":"...","ruby_patchlevel":null,"ruby_engine":"ruby",
    "ruby_engine_version":"...","rubygems_version":"...","bundler_version":"4.0.24",
    "platforms":[],"added_platforms":[],"removed_platforms":[],"force_ruby_platform":false},
  "candidate_closure": {"complete":true,"digest":"...","name_count":0,"candidate_count":0},
  "limits": {"timeout_ms":60000}
}
```

响应：

```json
{"schema":"celerite.solve_batch/3","ok":true,
 "result":{"chosen":[{"name":"...","version":"...","platform":"ruby","source_id":"...",
   "dependencies":[{"name":"...","requirements":[">= 0"]}],"checksum":null,
   "required_ruby_version":null,"required_rubygems_version":null}],
  "edges":[{"from":"root","to":"gem/1.0/ruby","requirements":[">= 0"]}],
  "variants":{"gem/1.0/ruby":["x64-mingw-ucrt"]},
  "failure":null,
  "stats":{"candidate_bytes":0,"candidate_count":0,"source_count":0,"name_count":0,
    "materialize_ms":0,"solve_ms":0,"candidate_digest":"...","bridge_pid":0,
    "relaxations":[],"fallback_reason":null}}}
```

失败响应 `ok:false`，`failure` 必填：`class`、`message`、`category ∈ {requirements_conflict, ruby_incompatible, platform_unavailable, candidate_incomplete, source_unsupported, checksum_invalid, timeout, internal}`，并附 `incompatibilities[]`。分类只做稳定归类，原文进 `message`，不得吞掉参考错误信息。

**上限与隔离（初始提案，需 Rails 样本量化）**：请求解析前按字节拒绝，32 MiB；响应 8 MiB；候选 100,000、source 4,096、name 10,000；超时 60 s。超出回 `BatchTooLarge`/`timeout`，不截断。请求只含 `uri_redacted` 与 `source_id`；不得含 `://user:pass@`、token、header。真实 source 对象由桥进程在求值阶段登记到 session-local `source_id → Source`；session 丢失、`identity_sha256` 不匹配即 `source_unsupported`，走兼容路径。凭据哈希沿用 `src/celerite/eval_cache_store.cr:68-83,97-102` 的 namespace 思路，禁止明文落盘。

**缓存指纹衔接**：solve 缓存键 = F1/F3 fingerprint digest（`src/celerite/eval_fingerprint.cr:35-39,60-80`、`assets/bridge/server.rb:566-626`）+ ENV signature（`src/celerite/eval_fingerprint.cr:32-34`）+ locked_base.sha256 + candidate_closure.digest + source identity/checksum digest + promotion/constraints 规范化 JSON。`unknown/broken` 不写 solve cache（`src/celerite/eval_cache_store.cr:29-31,100-102`）。命中 F1–F4 只证明求值可复用，不等于求解可命中；S8b `fast_path_store.cr:42-59,82-123` 只记录 runtime，不含 lock/plan，不能当 solve cache。

## 4. 调用点与兼容边界

1. `resolve!` 中 local-only、frozen/stale、locked reuse 快路（`src/celerite/resolution.cr:1095-1249`）全部先执行；无任何变化时不得进入 solve。
2. 需要求解时，在 `run_resolution` 的 `build_index`/lazy `fetcher` 之前（`src/celerite/resolution.cr:1884-1899`）一次性物化候选闭包：从 root 名 + locked 名迭代并入所有候选依赖名，批量取得每个名字的**全部**候选；该阶段不属于 PubGrub 循环。
3. 构造一次 `solve_batch` 请求；桥侧按 source_id 建立冻结 `Bundler::Index`、真实 Source 对象、locked base、promoter（`bundler/resolver/base.rb:10-33,55-84,113-123`），调用 `Resolver#start`，一次返回 SpecSet/边/失败。Crystal 侧只消费响应，不再调用 `index_specs_for`、`read_gem_spec` 或插件 spec op。
4. 闭包不完整、响应超限、桥无 `solve_batch` feature、fingerprint 非 `deterministic`、source 为 PATH/GIT/PLUGIN/未知 typed source、动态 Gemfile DSL/插件索引不可证、凭据不可隔离时，退回现路径并在 stats/日志标 `fallback_reason`。兼容路径是显式降级，不是绿色结果；不得声称该场景满足 L161。

## 5. 实施切片（依赖顺序严格串行）

| 片 | 目标 / 交付物 | 验收与反假绿 | 依赖 |
|---|---|---|---|
| S1 schema + 纯数据 solver | JSON schema、fixture、Ruby 纯数据 harness：冻结 Index → Resolver → SpecSet；不接桥 | 至少覆盖 promotion 三档/strict、prerelease、平台 variant、Ruby 约束、locked relax、冲突分类；故意删一个候选/改一个 checksum 必须失败；M7 现有输出/锁/exit 不变（本片不接命令） | 无 |
| S2 op 实现 | `assets/bridge/server.rb` 增 `solve_batch`、features、字节/超时/凭据隔离、结构化失败；`src/celerite/bridge/client.cr` 增结构与 envelope | 单测断言一次请求、零 callback、未知 op 兼容；毒化 source_id/候选摘要/超时必须失败；evaluate_batch 输出/锁/exit 不变 | S1 |
| S3 Crystal 调用点 | `src/celerite/resolution.cr` 的预物化与一次提交；快路优先级不变 | 静态断言 solve 前无 fetcher 调用；关节拍测候选完整才提交；无变化样例 procs/output/lock/exit 与 M7 基线相同；负值夹具不得静默 fallback 后报成功 | S2 |
| S4 真实 Rails/差分回归 | Rails 规模样本、双 Bundler profile、输出/锁文件/退出码三断言、性能与字节统计 | 首辅执行；本设计未跑。任一输出/锁/exit 差异不得用「求解器等价」解释；兼容场景单列，不并入 L161 成功数 | S3 |

## 6. 风险与裁定建议

- **推荐 Ruby 侧求解**：主价值是复用参考语义（`bundler/resolver.rb:85-91,257-330`、`bundler/definition.rb:1321-1328`），避免 Crystal 端口在 promotion、平台组、relax、SpecSet 变体上再次追平 4.0.24；代价是桥进程需保持 source session、协议体显著变大。
- **Crystal 本地 PubGrub 的边界**：一次性把候选送进 Crystal 可消除 `src/celerite/resolver/source.cr:204-217` 的逐名回调，但解不随桥响应返回；按 L161 原文不能宣称满足后半句。除非首辅明确改验收口径（本文不改），此路只可作性能备选。
- **纯数据化不完备**：`bundler/source_map.rb:17-57` 与 PATH/GIT/PLUGIN 源码证明 source 是行为对象；即使候选可 JSON 化，安装/锁 section 的真实对象仍需兼容路径。`autorequire`/groups 在 Bundler 求解中不同于依赖边，不得把它们塞进 resolver 输入冒充依赖。
- **反假绿底线**：候选不完整、session 缺失、超时、fallback 均不得产生「solve_ok」；M7 的 stdout/stderr、Gemfile.lock 字节、exit code 三条必须同时断言。

## 未验证

- 未运行 build/spec/differential，未测 8765；所有性能阈值、Rails 候选规模、32/8 MiB 上限和 60 s 超时均为提案，未实测。
- 未实测 Ruby 冻结 Index 包装能否在全部 Rails 候选上产出与原生 `Definition#resolver` 逐字节相同的 lock；`EndpointSpecification` 的 fetcher/remote 依赖（`bundler/endpoint_specification.rb:131-151`）可能在下游安装阶段触发材料化。
- 未验证插件 source 在「候选纯数据 + 对象 session」模式下仍可执行且不二次求值；未验证非 MRI 引擎、Windows 凭据 URI、source 同名多源的参考错误映射。
- 本文未改 `docs/roadmap.md`、claims、索引或任何源码；L161 是否闭合由首辅按原 Oracle 裁定。
