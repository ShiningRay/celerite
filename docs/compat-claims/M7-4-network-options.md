# M7-4 网络与传输选项（claims）

本文件是 M7-4 的断言账本：把 `../compat-evidence/` 里已取证的结论逐条固化为可复跑断言。原始建档、逐字输出与探针目录仍留在 evidence，本文件只写结论与判据。

## C-M7-4-001 配置 `mirror.<url>` 后抓取先走镜像，镜像失败再回退原 remote

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/mirror.rb:22-28 Mirrors#for` 与 `:48-54 fetch_valid_mirror_for` 先取镜像、校验可达性，全部无效时回退 `Mirror.new(uri)`（即原 remote）
- 我方行为：`src/celerite/mirror.cr:45 Celerite::Mirror.resolve` 选镜像；`src/celerite/downloader.cr:182` 命中 `@mirror_url` 时先试镜像，`:186` 以 `allow_mirror: false` 重试原 remote；`src/celerite/compact_index/cache.cr:99-101` 同一顺序
- 判据：`crystal spec spec/m7_download_settings_spec.cr`；`crystal spec spec/compact_index/http_fetcher_spec.cr`
- 边界：镜像探测无缓存，每次 `resolve` 重探一次（参考只在构造 `Mirror` 时 `validate!`）；未做真实公网镜像故障切换
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-002 `mirror.<url>.fallback_timeout` 按 Bundler 语义解析：true→0.1 秒、false→0、其余按 `to_i` 整数截断

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/mirror.rb:82-92 Mirror#fallback_timeout=`（`true`/"true"→`DEFAULT_FALLBACK_TIMEOUT`，`false`/"false"→0，其他 `timeout.to_i`）、`:63 DEFAULT_FALLBACK_TIMEOUT = 0.1`、`:104-110 Mirror#validate!`（`fallback_timeout == 0` 即短路不探测）
- 我方行为：`src/celerite/mirror.cr:15 DEFAULT_FALLBACK_TIMEOUT = 0.1`、`:21 Celerite::Mirror.fallback_timeout_seconds`、`:28 Celerite::Mirror.reachable?`（`timeout <= 0` 直接判可达、不建连）；`src/celerite/config.cr:483 mirror_fallback_timeout`、`:495 Config.fallback_timeout_seconds`
- 判据：`crystal spec spec/m7_download_settings_spec.cr`
- 边界：`"2.5"`→2、`"0.5"`→0 的截断已断言；负值 `"-1"` 走 `timeout <= 0` 分支视为可达（参考会探测），未加断言
- 生效：M7(4) 期间（27758b2）
- 取代：无

## C-M7-4-003 HTTP 代理按 `http_proxy`/`HTTP_PROXY` 或 config `proxy` 生效：http 用绝对 URI 请求行，https 先 CONNECT 建隧道

- 状态：已实现
- 参考行为（4.0.24）：vendored net-http-persistent `persistent.rb:843-859 proxy_uri`、`:860-875 proxy_from_env`（只读 `http_proxy`/`HTTP_PROXY`，空值即无代理）、`:629-635 proxy_bypass?`；`lib/bundler/fetcher.rb:313-316` 取 `Gem.configuration[:http_proxy]` 设 `con.proxy`
- 我方行为：`src/celerite/proxy.cr:35 Proxy.from_environment`、`:43 Proxy.resolve`；`src/celerite/http_transport.cr:20 HttpTransport.get`、`:32 direct_get`、`:55 proxied_get`、`:87 open_tunnel`（CONNECT 内再起 `OpenSSL::SSL::Socket::Client`，SNI 为目标 host）
- 判据：`crystal spec spec/m7_proxy_spec.cr`
- 边界：真实公网代理鉴权只在本地回环验证；SOCKS 与 NTLM/挑战式代理认证不支持
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-004 `no_proxy` 按主机后缀匹配绕过代理，`*` 绕过全部

- 状态：已实现
- 参考行为（4.0.24）：vendored net-http-persistent `persistent.rb:629-635 proxy_bypass?`（`no_proxy` 逗号项按 host[:port] 后缀匹配）
- 我方行为：`src/celerite/proxy.cr:113 Proxy#bypass?`（逗号项后缀匹配，`*` 全绕过；读 `no_proxy`/`NO_PROXY`）
- 判据：`crystal spec spec/m7_proxy_spec.cr`
- 边界：IPv6 字面量未测
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-005 `https_proxy`/`ALL_PROXY` 不参与取代理，与参考一致

- 状态：已实现
- 参考行为（4.0.24）：vendored net-http-persistent `persistent.rb:860-875 proxy_from_env` 只读 `http_proxy`/`HTTP_PROXY`，`https_proxy`/`ALL_PROXY` 不参与
- 我方行为：`src/celerite/proxy.cr:35 Proxy.from_environment` 只读 `http_proxy`/`HTTP_PROXY`（大小写两形态），不读 `https_proxy`/`ALL_PROXY`
- 判据：`crystal spec spec/m7_proxy_spec.cr`
- 边界：无
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-006 `~/.gemrc` 的 `:http_proxy` 优先于 `http_proxy` 环境变量

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:262` `GemRemoteFetcher.new Gem.configuration[:http_proxy]` 与 `:313-316` `con.proxy = Gem::URI.parse(gem_proxy) if gem_proxy != :no_proxy`；`Gem.configuration` 取自 `~/.gemrc`，故 gemrc 值压过环境变量
- 我方行为：`src/celerite/proxy.cr:66 Proxy.gemrc_http_proxy`（读 `$HOME/.gemrc`，键接受 `:http_proxy` 与 `http_proxy`）、`:89 Proxy.gemrc_path`；`src/celerite/proxy.cr:43 Proxy.resolve` 顺序为 gemrc → `.bundle/config` → 环境
- 判据：`crystal spec spec/m7_gemrc_proxy_spec.cr`；`bash script/differential lock-gemrc-proxy`
- 边界：系统级 gemrc（`Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE`）未读；gemrc 的 `https_proxy` 未对齐
- 生效：task-85
- 取代：无

## C-M7-4-007 `~/.gemrc` 把 `:http_proxy` 设为 `:no_proxy` 时禁用代理，即使环境变量另给了地址

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:313-316` 的 `if gem_proxy != :no_proxy` 判断——`Gem.configuration[:http_proxy]` 返回符号 `:no_proxy` 时整套代理被显式关闭
- 我方行为：`src/celerite/proxy.cr:66 Proxy.gemrc_http_proxy` 返回 `disabled: true` 时 `:43 Proxy.resolve` 立即返回 nil，短路后续 `.bundle/config` 与环境来源
- 判据：`crystal spec spec/m7_gemrc_proxy_spec.cr`；`bash script/differential lock-gemrc-no-proxy`
- 边界：无
- 生效：task-85
- 取代：无

## C-M7-4-008 `.bundle/config` 的 `proxy`/`http_proxy` 参与取代理，参考不参与

- 状态：已声明差异
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:313-316` 只从 `Gem.configuration[:http_proxy]`（gemrc）与环境取代理，`.bundle/config` 的 `proxy`/`http_proxy` 键不进该链路
- 我方行为：`src/celerite/proxy.cr:43 Proxy.resolve` 在 gemrc 之后读 `.bundle/config` 的 `proxy`、再读 `http_proxy`
- 判据：`crystal spec spec/m7_proxy_spec.cr`
- 边界：有意扩展——`.bundle/config` 写代理在参考里被静默忽略，本产品让其生效；此差异只影响显式写了这两个键的项目
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-009 gem 下载路径的重定向次数受 `redirect`（默认 5）限制，超限抛 `DownloadError`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:131 self.redirect_limit = Bundler.settings[:redirect]`、`:371` 传入 `Downloader.new`；`lib/bundler/fetcher/downloader.rb:29-37` `raise HTTPError, "Too many redirects" if counter >= redirect_limit`；`lib/bundler/settings.rb:44-51` 把 `redirect` 列为数字键
- 我方行为：`src/celerite/downloader.cr:64 getter max_redirects`（默认 5）、`:280-281` 超限抛 `DownloadError.new("Too many redirects (>#{@max_redirects}) for #{@remote}")`；`src/celerite/errors.cr:520 DownloadError`（status 17）
- 判据：`crystal spec spec/m7_transport_evidence_spec.cr`；`crystal spec spec/m7_download_settings_spec.cr`
- 边界：`redirect` 上限只在 gem 下载路径生效，紧凑索引路径没有（见 C-M7-4-011）
- 生效：M7(4) 期间（e6f0086）
- 取代：无

## C-M7-4-010 302 重定向的 `Location` 为相对路径时按 base URI 解析，且跳转后沿用重定向目标路径而非重新拼 `/gems/…`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher/downloader.rb:44-58` 用 `Gem::URI.parse(response["location"])` 取新地址后 `fetch(new_uri, headers, counter + 1)`
- 我方行为：`src/celerite/downloader.cr:312 resolve_redirect_location`（`:313` 有 host 直接用，否则 `URI.parse(base).resolve(ref)`，解析失败退回原串）；`:289` 取解析结果、`:294` 递归时传 `request_path: request`
- 判据：`crystal spec spec/m7_transport_evidence_spec.cr`
- 边界：未验证跨 host 跳转、空或畸形 `Location`、307/308 的方法保持（端点均为 GET）
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-011 紧凑索引路径跟随 301/302/303/307/308 时不计数、无上限

- 状态：未实现
- 参考行为（4.0.24）：`lib/bundler/fetcher/compact_index.rb:122-130 ClientFetcher#call` 走 `fetcher.downloader.fetch(...)`，即**与 gem 下载共用同一个受 `redirect_limit` 约束的 `Downloader#fetch`**（`lib/bundler/fetcher/downloader.rb:29-37`）
- 我方行为：`src/celerite/compact_index/cache.cr:112-116` 命中 301/302/303/307/308 时直接 `@uri = URI.parse(loc)` 后递归 `call`，没有 `max_redirects` 计数
- 判据：`crystal spec spec/compact_index/http_fetcher_spec.cr`
- 边界：缺口由读源码确认（`cache.cr:112-116` 无计数变量），判据只作回归锚点固定现状，不能自证缺口；参考两条路径共用同一限额，本产品只在下标器设限，`BUNDLE_REDIRECT` 对索引抓取实际无效
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-012 gem 下载路径对 404 与 5xx 都重试，`retries: 0` 时只请求一次

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/rubygems_integration.rb:379-407 download_gem` 用 `Bundler::Retry.new("download gem from …")` 且不传 exceptions，`lib/bundler/retry.rb:55` 对任意 `StandardError` 重试，404 经 `lib/bundler/remote_fetcher.rb:237` 变成 `FetchError` 故也被重试
- 我方行为：`src/celerite/downloader.cr:229 max_attempts = {@retries + 1, 1}.max`、`:239`/`:262`/`:297` 只在 `attempt < max_attempts` 时重试、`:269` 打印 `Retrying download gem from …` 行
- 判据：`crystal spec spec/m7_transport_evidence_spec.cr`
- 边界：退避基数为 0.5 秒指数增长，`Bundler::Retry` 的抖动未建模
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-013 紧凑索引只对 408/429/5xx 重试，404 等其余状态立即失败

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:101-125` 的 `FAIL_ERRORS` 把 `HTTPNotFound`、`FallbackError`、`HTTPBadGateway` 列为不重试，`lib/bundler/fetcher.rb:159`/`:173` 传给 fetcher 的重试器
- 我方行为：`src/celerite/compact_index/cache.cr:154 retryable_status?` 只认 `408`、`429`、`500..599`；`:118` 仅在该判定为真且 `attempt < max_attempts` 时重试
- 判据：`crystal spec spec/compact_index/http_fetcher_spec.cr`
- 边界：502 在参考里属 `FAIL_ERRORS` 不重试，本产品按 5xx 重试——属参考两处分类不完全一致的灰区，未逐条差分
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-014 `timeout` 配置映射为连接超时，且小于 1 的值回落到默认值

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/settings.rb:44-51` 把 `timeout` 列为数字键
- 我方行为：`src/celerite/downloader.cr:70 def connect_timeout : Time::Span`（返回 `@timeout.seconds`）、`:74` 构造参数 `timeout : Int32 = 30`；`src/celerite/cli/commands.cr:2825 Commands.timeout_seconds`（默认 10，<1 回退）
- 判据：`crystal spec spec/m7_download_settings_spec.cr`
- 边界：读超时（`read_timeout`）的触发路径未单独断言；只验证到连接超时
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-015 `ssl_ca_cert` 指向 PEM 文件时装入该文件、指向目录时按 CApath 装入、未配置时用默认信任库

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:349-359`——`ssl_ca_cert = Bundler.settings[:ssl_ca_cert] || Gem.configuration.ssl_ca_cert`；`File.directory?` 为真走 `store.add_path`（c_rehash 布局），否则 `store.add_file`；两者都没有则 `store.set_default_paths`（再补 `Gem::Request.get_cert_files`）
- 我方行为：`src/celerite/tls.cr:31 TLS.configure_trust_store`；`:34 ctx.set_default_verify_paths`（并显式补 `ENV["SSL_CERT_FILE"]`）、`:46 ctx.ca_certificates = path`（文件）、`:44 ctx.ca_certificates_path = path`（目录）；调用点 `src/celerite/downloader.cr:208`、`src/celerite/compact_index/cache.cr:164`
- 判据：`crystal spec spec/m7_tls_trust_store_spec.cr`
- 边界：Windows 系统证书库（SCHANNEL/certmgr）不参与 OpenSSL 信任判断；CA 目录需事先 c_rehash，不做自动 rehash；`Gem.configuration.ssl_ca_cert`（`~/.gemrc`）未读
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-016 `ssl_verify_mode` 为 `none` 时跳过校验，默认 peer 校验失败转成 `CertificateFailureError` 并以 17 退出

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:319 con.verify_mode = (Bundler.settings[:ssl_verify_mode] || …)`；`lib/bundler/fetcher.rb:25-34 CertificateFailureError < HTTPError`（status 17、wrap）、`lib/bundler/fetcher/downloader.rb:94-95` 在 `OpenSSL::SSL::SSLError` 上转换、`lib/bundler/errors.rb:34-37` HTTPError 退出码 17
- 我方行为：`src/celerite/downloader.cr:212-217`（`"none"`→`VerifyMode::NONE`，`"peer"`→`PEER`）、`src/celerite/compact_index/cache.cr:168-173` 同；`src/celerite/http_transport.cr:119 translate_tls_failure` 仅对 `certificate verify failed` 转 `src/celerite/errors.cr:568 CertificateFailureError`
- 判据：`crystal spec spec/m7_transport_evidence_spec.cr`；`crystal spec spec/m7_certificate_failure_spec.cr`
- 边界：参考在失败前会打印 `Fetching source index from …` 与一次 `Retrying fetcher due to error (2/4)`，本产品不打印也不重试一次；TLS 1.2 与真实公网证书链未验证
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-017 `ssl_client_cert` 指向的同一 PEM 内同时装载证书链与私钥，因而客户端证书认证（mTLS）可用

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher.rb:324-331` 从**同一个 PEM** 读证书与私钥（`con.cert = OpenSSL::X509::Certificate.new(File.read(pem))` 后 `con.key = OpenSSL::PKey.read(pem)`；只有证书时 key 为 nil 且不报错），`:303-304` 只要配置了 `ssl_verify_mode` 或 `ssl_client_cert` 就加载 openssl
- 我方行为：`src/celerite/tls.cr:12 TLS.configure_client_certificate`——`:15 ctx.certificate_chain = pem_path` 无条件设置、`:20 return unless File.read(pem_path).includes?("PRIVATE KEY")`、`:22 ctx.private_key = pem_path`；调用点 `src/celerite/downloader.cr:210`、`src/celerite/compact_index/cache.cr:166`
- 判据：`crystal spec spec/m7_client_cert_spec.cr`
- 边界：仅单证书 + 同 PEM 私钥与「只有证书」两态实测；带口令的 `ENCRYPTED PRIVATE KEY`、多级链 + 分离 key 文件、TLS 1.2、真实远端 mTLS 均未验证。**该能力曾只装载证书链、从不设 `private_key=`，属半接线（证据原文见 `../compat-evidence/2026-11-15.md` 的「2026-11-15 M7(4) 第二子项：`ssl_client_cert` 的 mTLS 私钥接线」）；负对照注释掉 `tls.cr:22` 后两条正例立即以 `SSL routines::tlsv13 alert certificate required` 失败，证明正例通过确由私钥接线决定**
- 生效：M7(4) 期间（cd16bae）
- 取代：无

## C-M7-4-018 `ssl_client_key` 被显式配置时快速失败，因为参考没有该配置键

- 状态：已声明差异
- 参考行为（4.0.24 = 2.7.2）：`lib/bundler/fetcher.rb:324-331` 只认 `ssl_client_cert`（单 PEM 兼证书与私钥）；bundler 4.0.24/4.0.16/2.7.2 全树对 `ssl_client_key` 零命中，`settings.rb` 亦无该键
- 我方行为：`src/celerite/cli/commands.cr:2852 Commands.unsupported_setting_error`、`:2855 return "not supported by Celerite: ssl_client_key"`；调用点 `src/celerite/cli/commands_install.cr:227`、`src/celerite/cli/commands_surface.cr:108`
- 判据：`crystal spec spec/m7_build_args_spec.cr`
- 边界：参考对该键静默保存（未知键无 validator 规则），本产品改为报错退出——属既定政策，避免用户以为分离私钥已生效
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-019 `legacy_index`/`full_index` 被显式配置时快速失败，因为参考没有这两个配置键

- 状态：已声明差异
- 参考行为（4.0.24 = 2.7.2）：bundler 4.0.24/4.0.16/2.7.2 全树对 `legacy_index`、`full_index` 两键零命中（`--full-index` 是 CLI 开关，不是配置键，见 C-M7-4-021）
- 我方行为：`src/celerite/cli/commands.cr:2859 {"legacy_index", "full_index"}.each do |key|`、`:2862 return "not supported by Celerite: #{key}"`；同样经 `:2852 Commands.unsupported_setting_error`
- 判据：`crystal spec spec/m7_build_args_spec.cr`
- 边界：参考把未知配置键静默保存，本产品改为报错退出——属既定政策。注意与 C-M7-4-020 区分：**配置键**参考没有，**索引回退机制**参考有
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-020 紧凑索引不可用时没有回退到 legacy 全量索引（`specs.4.8.gz`）的路径

- 状态：未实现
- 参考行为（4.0.24）：`lib/bundler/fetcher/compact_index.rb:9-23 compact_index_request` 只让 401 原样抛出，其余 `HTTPError` 记 trace 后返回 nil——紧凑索引 403 时退到 legacy 索引；`lib/bundler/fetcher/index.rb:14-19` 的 legacy `specs` 在 403 时抛 `AuthenticationForbiddenError` 并带完整源 URI
- 我方行为：`src/celerite/compact_index/cache.cr:46 class FileFetcher < Fetcher` 只读紧凑索引目录（`versions`/`info/<gem>`/`names`）、`:605-612 make_fetcher` 对 `file:` 源同样只造 `FileFetcher`；`src/celerite/resolution.cr:1009 index_specs_from_remote` 走 `client.info(name)`，`:1041` 只在 403 时打印抓取行与完整 URI 后重抛，不解析 legacy 索引
- 判据：`bash script/differential install-platforms-add-local`；`crystal spec spec/m7_forbidden_spec.cr`
- 边界：缺口由读源码确认（无 legacy 解析路径），判据只作回归锚点固定现状，不能自证缺口；`fixtures/gem-index-legacy/` 同时含紧凑索引与 legacy 文件，故该夹具靠紧凑读取通过，不能证明 legacy 回退存在；`file://` 源在参考侧只走 legacy marshal 全索引，本产品只走紧凑索引，缺紧凑索引时直接失败（真实 legacy 解析未验证）
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-021 `--full-index` 开关被接受但没有对应语义

- 状态：未验证
- 参考行为（4.0.24）：`lib/bundler/cli.rb:270`/`:323`/`:646` 声明 `method_option "full-index", type: :boolean, banner: "Fall back to using the single-file index of all gems"`；`lib/bundler/cli/install.rb:39 Bundler::Fetcher.disable_endpoint = options["full-index"]`
- 我方行为：`src/celerite/cli/commands.cr:502`、`:1019 INSTALL_SWITCH_FLAGS`、`:1026 UPDATE_SWITCH_FLAGS`、`:1029 LOCK_SWITCH_FLAGS` 均接受 `--full-index`，但没有下游消费者
- 判据：`crystal spec spec/m7_install_family_switches_spec.cr`
- 边界：开关被白名单接受（不报未知开关），语义未逐一复核，也没有对照参考 `disable_endpoint` 的差分用例；现有 spec 只覆盖白名单中的 `--local`/`--all`/`--print`/`--no-install` 与若干值选项，未直接断言 `--full-index`；因此写「未验证」而不是「已实现」
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-022 `path.system` 为真且无显式 `path` 时安装根为 `Gem.dir`，且不追加 `ruby/<abi>` 层

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/settings.rb:238-297 Bundler::Settings::Path`——`use_system_gems?` 在 `path.system` 为真或 `disable_shared_gems == false` 时返回真，`base_path` 因此回落 `Bundler.rubygems.gem_dir`；显式 `path` 优先
- 我方行为：`src/celerite/resolution.cr:51 InstallPaths.use_system_gems?`、`:73 InstallPaths.base_path`、`:132 InstallPaths.gem_root`（系统 gems 模式下不再拼 `ruby/<abi>`）；`src/celerite/cli/commands_install.cr:921` 按其选收尾消息
- 判据：`crystal spec spec/m7_path_system_spec.cr`
- 边界：`cache`/`clean` 的 `<base>/ruby` 枚举在系统 gems 模式下仍按产品 base（无桥拿不到 `Gem.dir`）；`disable_shared_gems: false` 只有单测，无端到端安装
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-023 显式 `path` 与 `path.system` 同时成立时抛 `PathConflictError`，以 15 退出

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/settings.rb:287-297 Path#validate!` 在 `explicit_path && system_path` 时抛 `InvalidOption`，消息 `Using a custom path while using system gems is unsupported.`；`lib/bundler/errors.rb:34` `InvalidOption` 退出码 15；`lib/bundler/settings/validator.rb:57-63` 另把两者互斥置 nil 并打印 `Setting \`key\` to nil`
- 我方行为：`src/celerite/errors.cr:48 class PathConflictError < Error`（`status_code` 15）、`src/celerite/resolution.cr:66 InstallPaths.validate!` 抛出；`src/celerite/cli/commands_surface.cr:1367 doctor_settings_notices` 复刻 stdout 的置 nil 提示
- 判据：`bash script/differential install-path-conflict`；`crystal spec spec/m7_path_system_spec.cr`
- 边界：置 nil 提示只在 `doctor` 路径复刻；冲突配置下不计算 gem root 的命令（如 `config list`）是否同样退出 15 未核对
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-024 完全没有 `path` 配置时仍安装到 `<home>/.bundle/ruby/<abi>`，参考装进系统 gems

- 状态：已声明差异
- 参考行为（4.0.24）：`lib/bundler/settings.rb:260-264 Path#use_system_gems?` 在无显式 `path` 且非 `bundler_5_mode?` 时返回真，`:266-271 Path#base_path` 因此回落 `Bundler.rubygems.gem_dir`，安装后打印 `Use \`bundle info [gemname]\` to see where a bundled gem is installed.`
- 我方行为：`src/celerite/resolution.cr:73 InstallPaths.base_path` 在拿不到 `Gem.dir` 或无配置时回落 `<home>/.bundle`；`src/celerite/cli/commands_install.cr:927` 打印 `Bundled gems are installed into \`…\``
- 判据：`crystal spec spec/m7_path_system_spec.cr`
- 边界：有意保留的偏差——改默认会让未隔离 `GEM_HOME` 的用例与本地使用直写宿主 RubyGems 目录，故只对齐语义入口与消息分支。`script/differential` 对两侧都固定设置 `BUNDLE_PATH`，该默认路径没有差分夹具，只有 A/B 探针取证
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-025 部署模式且无显式 `path` 时安装根默认 `vendor/bundle`

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/settings.rb:238-251 Settings#path`——无任何 path 配置但 `deployment` 为真时返回 `"vendor/bundle"`
- 我方行为：`src/celerite/resolution.cr:31 DEPLOYMENT_PATH = "vendor/bundle"`、`:83 return File.expand_path(File.join(root, DEPLOYMENT_PATH))`
- 判据：`crystal spec spec/m7_deployment_path_spec.cr`；`bash script/differential install-deployment-empty-checksums`
- 边界：`bundler_5_mode?` 分支未建模（两个参考 profile 下该标志恒为假）
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-026 自定义 `path` 的安装提示按项目根相对化，并以 `./` 前缀输出

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/settings.rb:273-285 Path#base_path_relative_to_pwd`——以 `..` 开头且 base 为绝对路径时回退绝对写法，否则加 `./` 前缀；`lib/bundler/cli/install.rb:56-64` 用它拼 ``Bundled gems are installed into `…` ``
- 我方行为：`src/celerite/resolution.cr:95 InstallPaths.base_path_relative_to_pwd`（反斜杠归一为 `/`、按 `..` 分支、`"./#{relative}"`、跨盘 `ArgumentError` 退绝对）；`src/celerite/cli/commands_install.cr:927` 使用该相对路径
- 判据：`bash script/differential install-custom-path-summary`；`crystal spec spec/m7_path_system_spec.cr`
- 边界：跨盘相对 `path` 的 `ArgumentError` 回退未复现
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-027 `build.<gem>` 参数经桥传到原生扩展编译，按 gem 名分别取用

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/settings.rb:360` 把 `build.` 前缀的键按字符串键保存（`name.start_with?("build.")`），由 RubyGems 侧经 `lib/bundler/rubygems_integration.rb:23-30` 的 `Gem::Command.build_args` 消费
- 我方行为：`src/celerite/installer.cr:62 config_build_args`（读 `cfg["build.#{name}"]`）、`:244-245` 传给 `@bridge.build_extension`
- 判据：`crystal spec spec/m7_build_args_spec.cr`
- 边界：多个 gem 各自不同参数、含空格或引号的参数切分、真实编译型扩展均未验证（夹具用的是 no-op Makefile）
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-028 目标主机不可达时输出参考措辞并以 17 退出，不打印内部错误

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher/downloader.rb:80-106` 把不可达归入 `HTTP_NON_RETRYABLE_ERRORS` 并 `raise NetworkDownError, "Could not reach host #{host}. Check your network connection and try again."`；`lib/bundler/fetcher.rb:18 NetworkDownError < HTTPError`；`lib/bundler/errors.rb:37-38` HTTPError 退出码 17
- 我方行为：`src/celerite/errors.cr:534 class NetworkDownError < Error`（status 17、wrap）；`src/celerite/http_transport.cr:129 network_down` 只在连接建立阶段把 `Socket::Error` 转换（`:45`、`:65`）
- 判据：`crystal spec spec/m7_network_down_spec.cr`；`bash script/differential network-unreachable`
- 边界：DNS 解析失败、代理连接失败、读超时与 TLS 相关的措辞未单独验证
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-029 同进程内连续调用时，`--retry` 只作用于当次调用，不泄漏到下一次

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/cli.rb:83 Bundler.settings.set_command_option_if_given :retry, options[:retry]`——`retry` 是本次 CLI 对象的命令行覆盖，`lib/bundler/settings.rb:44-51` 把它列为数字键，未给 `--retry` 时 `return if value.nil?` 不写入，故参考结构上不存在跨调用泄漏
- 我方行为：`src/celerite/cli/commands.cr:519 Commands.extract_retry_switch` 在剥离全局开关前对原始参数求值，`:612 Commands.retry_count` 先读 `CELERITE_CLI_RETRY` 再读 config、默认 3
- 判据：`crystal spec spec/m7_cli_state_isolation_spec.cr`；`crystal spec spec/m7_thor_argument_spec.cr`
- 边界：进程内连续多次调用是本实现特有形态（参考每次都是新进程），只在该形态下有意义
- 生效：task-128（633c5f9）
- 取代：无

## C-M7-4-030 索引返回 403 时先打印 `Fetching source index from <完整源 URI>` 再以 17 退出

- 状态：已实现
- 参考行为（4.0.24）：`lib/bundler/fetcher/index.rb:14-19` legacy 索引 403 抛 `AuthenticationForbiddenError` 并带完整源 URI（含尾斜杠）；`lib/bundler/fetcher/downloader.rb:69-75` 的 `HTTPForbidden` 分派取 `uri.host`
- 我方行为：`src/celerite/resolution.cr:1041 rescue ex : Celerite::AuthenticationForbiddenError` → `:1046 puts "Fetching source index from #{remote}"`、`:1047` 空行、`:1048 raise ex`；错误类 `src/celerite/errors.cr:317 AuthenticationForbiddenError`
- 判据：`crystal spec spec/m7_forbidden_spec.cr`；`crystal spec spec/m7_network_down_spec.cr`
- 边界：真正的 legacy 解析未实现（见 C-M7-4-020），此处只复刻「抓取行 + 完整 URI 文案」的顺序
- 生效：M7(4) 期间
- 取代：无

## C-M7-4-031 gem 下载遇 403 时重试三次后抛 `Bundler::HTTPError: Could not download gem` 并以 5 退出，但不再打印参考的 Ruby 回溯

- 状态：已声明差异
- 参考行为（4.0.24）：gem 下载走 `lib/bundler/rubygems_integration.rb:379-407 download_gem` 的 `Bundler::Retry.new("download gem from …")`；`lib/bundler/retry.rb:60-64 fail_attempt` 每次失败先往 stdout 写空行、再往 stderr 写 `Retrying download gem from <source> due to error (n/4): Gem::RemoteFetcher::FetchError bad response Forbidden 403 (<url>)`，最后一次抛 `Bundler::HTTPError: Could not download gem from <source> due to underlying error <bad response Forbidden 403 (<url>)>`，最终 status 5
- 我方行为：`src/celerite/downloader.cr:30 class ForbiddenDownloadError`（`:35-37 status_code` 为 5、`:39-41 wrap?` true、`:51-52 error_class_name` 为 `Bundler::HTTPError`、`:43-49` 消息逐字）；`:262-274` 打印重试行与退避、`:276` 耗尽后抛出
- 判据：`crystal spec spec/m7_forbidden_download_spec.cr`；`crystal spec spec/m7_forbidden_spec.cr`
- 边界：参考在 `Bundler::HTTPError` 之后打印约 20 行 Ruby 回溯，本产品不复刻（Crystal 程序没有 Ruby 帧）；`Bundler::Retry` 的 jitter（±0.5）未建模，三次重试总耗时与参考不完全一致；`/quick/` 与 `/gems/` 两个 403 抛出点是否同一路径未分别验证
- 生效：M7(4) 期间
- 取代：无
