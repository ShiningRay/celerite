# M7-3 占位路径与硬编码运行环境（claims）

本文件是 M7-3 的断言账本：把 `../compat-evidence/`（及 `../roadmap-evidence/M7-3-placeholders.md`）里已取证的 `fund` / `gem` / `console` / `env` / `issue` 结论逐条固化为可复跑断言。原始建档、逐字输出与探针目录仍留在 evidence，本文件只写结论与判据。

## C-M7-3-001 `fund` 从已安装 specifications 的 `funding_uri` metadata 打印资助信息

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/fund.rb:14-32` 遍历 `definition.specs` 里直接依赖的 spec，取 `spec.metadata["funding_uri"]`，命中打印 `* <full_name>` 与 `  Funding: <uri>`
- 我方行为：`src/celerite/cli/commands_surface.cr:2106` 的 `read_funding_uri` 只读 `<bundle>/ruby/<abi>/specifications/<full_name>.gemspec` 内的 metadata（`:2121-2136`），不探测 `cache/*.gem`
- 判据：`crystal spec spec/m7_fund_spec.cr`
- 边界：真实 rubygems.org 源未触达，只验证本地已安装 specifications
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-002 `fund` 优先从 PATH/GIT 源的 gemspec 读 `funding_uri`

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/fund.rb:14-32` 对 PATH/GIT 源取该源内 gemspec 的 funding metadata
- 我方行为：`src/celerite/cli/commands_surface.cr:2084` 的 `read_source_funding_uri`，由 `:2106` 的 `read_funding_uri` 在 `:2107` 优先返回
- 判据：`bash script/differential fund-path`
- 边界：只有 PATH 源夹具；GIT 源无独立夹具
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-003 `fund --group` 按标量语义取组、重复后者覆盖且不切分逗号

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/fund.rb:14` 的 `Array(options[:group]).map(&:to_sym)` 直接交给 `definition.dependencies_for`；`bundler/definition.rb:286-288` 与 `:328-333` 保留任一 group 落在请求集合内的依赖
- 我方行为：`src/celerite/cli/commands_surface.cr:2005` 的 `fund_group_flag` 同时接受 `--group=x` 与 `--group x`，重复时后者覆盖，`development,test` 整体作为一个组名
- 判据：`bash script/differential fund-groups fund-group-development`
- 边界：`--group=development --group=test` 与 `--group=missing` 的 None 形态由同一夹具族覆盖
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-004 `fund` 的默认组集合等于声明组减 `without` 加 `with`

- 状态：已实现
- 参考行为（4.0.24）：`bundler/definition.rb:1251-1255` 的 `values = groups - Bundler.settings[:without] - @optional_groups + Bundler.settings[:with]`
- 我方行为：`src/celerite/cli/commands_surface.cr:2026` 的 `fund_requested_groups` 配 `setting_list`
- 判据：`bash script/differential fund-groups-without`
- 边界：`BUNDLE_WITH` 方向无夹具
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-005 `fund` 遇缺失 PATH 源按参考 `PathError` 折行报错并 exit 13

- 状态：已实现
- 参考行为（4.0.24）：`bundler/source/path.rb:198-204` 拼 `The path \`<expanded_path>\` does not exist.` 后 `raise PathError`；`bundler/errors.rb` 给 `PathError` 状态 13；折行经 `bundler/ui/shell.rb:167-171` 的 `word_wrap`
- 我方行为：`src/celerite/cli/commands_surface.cr:2073` 的 `fund_missing_path` 遍历锁内全部 PATH 源，`Commands.word_wrap("The path \`<abs>\` does not exist.", CLI.terminal_width)` 打印到 stderr 并由 `:1977` 返回 13
- 判据：`crystal spec spec/m7_fund_group_spec.cr`
- 边界：折行按终端宽度推导（`THOR_COLUMNS=1000` 下同一消息只有一行），不是硬编码三行
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-006 `BUNDLE_WITHOUT` 命中 `--group` 时参考崩溃，本实现不复刻

- 状态：已声明差异
- 参考行为（4.0.24）：`bundler/cli/fund.rb:24` 的 `Bundler.definition.specs[dep.name].first` 取到 nil，随后访问 `.metadata` 抛 `NoMethodError: undefined method 'metadata' for nil` 并以 ERROR REPORT 模板结束
- 我方行为：`src/celerite/cli/commands_surface.cr:2026` 减掉 `without` 后按「无资金信息」打印 `None of the installed gems you directly depend on are looking for funding.` 并 exit 0
- 判据：`crystal spec spec/m7_fund_group_spec.cr`
- 边界：有意不复刻参考崩溃，属声明的不一致而非兼容通过；2.7.2 的同一分支未单独验证
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-007 `fund` 无锁文件时走 local-only 解析而不是报缺 `Gemfile.lock`

- 状态：已实现
- 参考行为（4.0.24）：只有 `check`（`bundler/definition.rb:170-180`）与 `install` 会访问索引，`bundler/cli/fund.rb:14-27`、`bundler/cli/clean.rb:11-14`、`bundler/cli/binstubs.rb:12-26` 都只 materialize 后 resolve，缺失 gem 报 `Could not find gem '<name> (<req>)' in locally installed gems.`（`bundler/source/rubygems.rb:122-136` 在 `@allow_remote = false` 下把 source 呈现为 `locally installed gems`）
- 我方行为：`src/celerite/cli/commands_surface.cr:1970` 的 `materialize_lockfile(definition, stdout, local_only: true)`；`src/celerite/resolution.cr` 的 `make_source` 在 local-only 下输出同一措辞
- 判据：`bash script/differential fund-no-lockfile`
- 边界：负对照（把 `local_only` 改回 `false`）由 `spec/m7_no_lockfile_commands_spec.cr` 承担
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-008 `gem --no-git` 生成 9 个文件且不写 `.gitignore` 与 `.git`

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/gem.rb:45-49` 的三次 `git config` 全部以 `use_git` 为条件；`:113-116` 只有 `use_git` 才 merge `gitignore.tt` 并把 `.gitignore` 追加进 `ignore_paths`
- 我方行为：`src/celerite/cli/commands_surface.cr:3686` 的 `self.gem` 经 `Commands.negated_flag?` 放行 Thor 生成的 `--no-<bool>`，模板由 `src/celerite/gem_template.cr:8` 的 `GemTemplate` 渲染
- 判据：`bash script/differential gem-no-git`
- 边界：2.7.2 由 `fixtures/differential/gem-no-git/deferred-2.7.2` 标记延迟
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-009 `gem --rubocop` 与 `--no-rubocop` 按参考 removed 文案 exit 15 且不创建文件

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli.rb:607-608` 对两者直接 `raise InvalidOption`，文案为 `--rubocop has been removed, use --linter=rubocop` 与 `--no-rubocop has been removed, use --no-linter`
- 我方行为：`src/celerite/cli/commands_surface.cr:3701`（`--rubocop`）与 `:3705`（`--no-rubocop`）写 stderr 后返回 15，不进入脚手架
- 判据：`crystal spec spec/m7_gem_template_spec.cr`
- 边界：2.7.2 的 `--no-rubocop` 文案为 `use --linter`（`:3706` 按 profile 分支）
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-010 `gem <name>` 目标为同名文件时 exit 32 且不写文件

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/gem.rb:252-255` 的 `if target.exist? && !target.directory?` 分支打印 ``Couldn't create a new gem named `<name>` because there's an existing file named `<name>`.`` 后 `exit`
- 我方行为：`src/celerite/cli/commands_surface.cr:3804-3805` 打印同一文案（含反引号）并返回 32
- 判据：`crystal spec spec/m7_gem_template_spec.cr`
- 边界：目录已存在时参考继续写入而非报错，该分支由同一 spec 文件覆盖
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-011 `gem --help` 渲染 pinned 版本的参考手册页文本

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli.rb:589-602` 定义 `gem` 的全部选项，`--help` 由 Thor 在命令体之前打印
- 我方行为：`src/celerite/cli/commands_surface.cr:3691` 的 `stdout.print GemTemplate.help_text(profile)` 后返回 0
- 判据：`crystal spec spec/m7_gem_options_spec.cr`
- 边界：2.7.2 文本不同（含 `--rubocop` 段、`--ext=c/rust` 而非 `c/go/rust`），由同一 spec 的 profile 分支覆盖
- 生效：task-27（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-012 `gem` 的 test/CI/linter/mit/coc/changelog/exe/ext 模板分支按选项渲染

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/gem.rb:118-155`（test）、`:157-171`（CI）、`:173-201`（mit/coc/changelog）、`:203-215`（linter）、`:217-220`（exe）、`:222-250`（ext）；`bundler/cli.rb:14` 的 `EXTENSIONS = ["c", "rust", "go"]`
- 我方行为：`src/celerite/cli/commands_surface.cr:3857` 组装 `GemTemplate::Options`、`:3859` 调 `GemTemplate.render`；模板经 `src/celerite/gem_template.cr:25` 的 `asset_path("gem_render.rb")` 复用参考自带 ERB 模板集
- 判据：`bash script/differential gem-options gem-ext`
- 边界：2.7.2 的 rust 模板无 `build.rs`（`:228-232`）；`--ext=go` 无夹具
- 生效：task-27（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-013 `gem` 的枚举值与未知开关按 Thor 文案拒绝并 exit 15

- 状态：已实现
- 参考行为（4.0.24）：枚举错值报 `Expected '--test' to be one of rspec, minitest, test-unit; got minitestx`，未知开关报 `Unknown switches "--bogus"`
- 我方行为：`src/celerite/cli/commands_surface.cr:3722` 的 `value_options` 与 `:3749-3767` 的枚举校验；linter 文案在 `:3762-3763`
- 判据：`bash script/differential gem-invalid`
- 边界：未知开关与多位置参数共用同一拒绝器，二者的先后顺序由同一夹具覆盖
- 生效：task-27（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-014 `gem --edit` 与 `--bundle` 显式报不支持并 exit 1

- 状态：已声明差异
- 参考行为（4.0.24）：`--edit` 打开生成的 gemspec、`--bundle` 在生成后自动执行 `bundle install`，均属交互或网络副作用
- 我方行为：`src/celerite/cli/commands_surface.cr:3790-3791` 报 `bundle gem option --bundle is not supported by Celerite (reference runs \`bundle install\`)`，`:3794-3797` 报 `bundle gem option --edit is not supported by Celerite (reference opens the gemspec in an editor)`，两者返回 1
- 判据：`crystal spec spec/m7_gem_options_spec.cr`
- 边界：属有意的不支持边界而非静默忽略；参考的交互与网络副作用不在本产品范围内
- 生效：task-27（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-015 `gem` 的交互式问卷（test/CI/linter/license/COC/changelog）已实现，提示语与持久化逐字对齐 4.0.24

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/gem.rb:118`（test）→`:157`（ci）→`:173`（mit）→`:182`（coc）→`:191`（changelog）→`:203`（linter）；`gem.rb:299-310` 的 `ask_and_set` 以 `choice.nil?` 判定未配置，`gem.rb:322-347`/`:362-391`/`:393-426` 以 `settings[...].to_s.empty?` 判定；`bundler/cli.rb:590-601` 的 `--test/--ci/--linter` 用 `lazy_default: Bundler.settings["gem.<key>"] || ""`；提示行的尾随空格与换行由 `bundler/vendor/thor/lib/thor/shell/basic.rb:330-345`（ask_simply）与 `:98-106`（say）裁定
- 我方行为：`src/celerite/cli/commands_surface.cr:3750` 起 `Commands.gem` 按同一顺序提问（test → ci → mit → coc → changelog → linter），同文件 `gem` 之后的 `gem_ask_and_set` / `gem_ask_and_set_choice` / `gem_hint_text` / `gem_setting` / `gem_say` / `gem_ask` / `gem_yes?` 复刻 nil 判定、正则采纳、`BUNDLE_GEM__*` 六键持久化与 "already configured, ignoring --<flag> flag." 行；`--no-test/--no-ci/--no-linter` 跳过对应问题
- 判据：`bash script/differential gem-questionnaire`（stdout 逐字 2905 字符、退出码、`$HOME/.bundle/config` 逐字）；`crystal spec spec/m7_gem_questionnaire_spec.cr`（4 examples, 0 failures）
- 边界：夹具 `extra/norl.rb` 删掉 `Readline` 常量，并以 `env` 的 `RUBYOPT=-I. -rnorl` 预载，使 Thor 回落到 `Thor::LineEditor::Basic`；Ruby 4 的 reline 在管道 stdin 下会重绘提示行并混入 ANSI 转义，不这样做 stdout 无法逐字比对。此归一化只换行编辑后端，不涉及产品输出。2.7.2 模板集与成功链接不同（见 `C-M7-3-016`），该夹具 2.7.2 deferred。该夹具依赖宿主用户级 bundler 配置必须被隔离：`bundle gem` 只为「用户配置里还没答案」的问题提问，真实机器上残留的 `BUNDLE_GEM__TEST/__CI/__MIT/__COC/__CHANGELOG/__LINTER` 会让两侧问题序列不一致（首辅 19:57 见参考侧跳过全部六问、我方全问；task-190 两次污染真实 `~/.bundle/config` 后重跑未复现，见 `docs/compat-evidence/2026-11-23.md`）。现行隔离由 `script/differential:364-366`/`:494` 把 `HOME`、`USERPROFILE` 指向 `<sandbox>/home` 提供，两侧各自读写自己的 `~/.bundle/config`（celerite 侧同一解析见 `src/celerite/config.cr:313-327`，`:329-334` 有意优先 `HOME`）；直接手跑该命令而不经装具时没有这层隔离，需自备干净 `HOME`
- 生效：task-189（提交见 `docs/compat-evidence/2026-11-23.md`）
- 取代：无

## C-M7-3-016 2.7.2 的 `gem` 模板与成功链接不同，两个 gem 夹具在该 profile 下 deferred

- 状态：已声明差异
- 参考行为（2.7.2）：`bundler-2.7.2/lib/bundler/cli/gem.rb:419-434`，成功行指向 `https://bundler.io/guides/creating_gem.html`，模板集与 4.0.24 不同
- 我方行为：不按 2.7.2 模板集渲染
- 判据：`bash script/differential gem-default`
- 边界：`fixtures/differential/gem-default/deferred-2.7.2` 与 `fixtures/differential/gem-no-git/deferred-2.7.2` 为实现该延迟的标记文件
- 生效：task-27（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-017 `console [GROUP]` 在 bundle 语境里 require 依赖后再启动控制台

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/console.rb:11-17` 的 `group ? Bundler.require(:default, *group.split(" ").map!(&:to_sym)) : Bundler.require` 后 `ARGV.clear`、取控制台常量、`console.start`
- 我方行为：`assets/bridge/console_boot.rb:26` 读 `ENV["CELERITE_CONSOLE_GROUPS"]`、`:30` 调 `Bundler.require(:default, *groups.split(" ").map!(&:to_sym))`、`:28` 无 GROUP 时无参 `Bundler.require`、`:32` 的 `ARGV.clear`；`src/celerite/cli/commands_surface.cr:3639` 传入该环境变量
- 判据：`bash script/differential console-group`
- 边界：引导脚本由 `src/celerite/cli/commands_surface.cr:3657` 的 `console_boot_path` 定位（可用 `CELERITE_CONSOLE_BOOT` 覆盖）
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-018 配置的控制台不在 bundle 内时回退 irb，irb 亦不可用时 exit 1 且末行 `irb is not available`

- 状态：已声明差异
- 参考行为（4.0.24）：`bundler/cli/console.rb:19-36` 的 `get_console` 在 `rescue LoadError` 后分两支。`name == "irb"`（`:23`）且 `defined?(Gem::BUNDLED_GEMS) && Gem::BUNDLED_GEMS.respond_to?(:force_activate)` 为真时，先 `Gem::BUNDLED_GEMS.force_activate "irb"`（`:24-25`）再 `require name` 并取常量（`:26-27`）；该次 `require` 仍抛 `LoadError` 时不再兜底，异常冒泡为 `Failed to activate irb, please install it with 'gem install irb'` 加 ERROR REPORT，exit 1（`:24-28`）。只有该能力不存在时才走 `Bundler.ui.error "#{name} is not available"; exit 1`（`:29-30`）。2.7.2 无 `force_activate` 分支：`bundler-2.7.2/lib/bundler/cli/console.rb:19-31` 直接在 `LoadError` 时打 `irb is not available` 并 exit 1（`:23-25`）。非 irb 名字先打 `Couldn't load console #{name}, falling back to irb` 再以 irb retry（4.0.24 `:31-35`）。
- 我方行为：`assets/bridge/console_boot.rb:57-58` 打印 fallback 首行；`:63` 与 `:67` 在 irb 缺失时打印 `irb is not available` 并 exit 1；`:52-56` 注释明记不镜像 4.0.24 的 `force_activate` retry（声明差异）。子进程入口 `src/celerite/cli/commands_surface.cr:3706`。
- 判据：`crystal spec spec/m7_console_spec.cr`
- 边界：本机 4.0.24 在 bundle 内 `force_activate` 后仍 `LoadError`，输出 `Failed to activate irb, please install it with 'gem install irb'` 加 ERROR REPORT（exit 1）；celerite 输出 `irb is not available`（exit 1）。二者退出码一致，末行文案不同，`irb is not available` 是 2.7.2 文案。fallback 首行文案与退出码对齐，file:line 提示由实现文件位置决定故不设夹具。该 spec 经子进程取证，前提是先构建 `bin/celerite.exe`；缺二进制时整组 pending 跳过并 exit 0，故仅凭退出码 0 不足以证明通过。
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：task-210 按 4.0.24 实测改写参考锚点（补 `cli/console.rb:24-28` 的 `force_activate` 分支），状态由「已实现」改判「已声明差异」：我方末行沿用 2.7.2 文案，不镜像 4.0.24 的 ERROR REPORT 形态。

## C-M7-3-019 `console` 的多余位置参数按 Thor 报错并 exit 15

- 状态：已实现
- 参考行为（4.0.24）：Thor 的 `handle_argument_error` 打印 `ERROR: "bundle console" was called with arguments [...]` 与 `Usage: "bundle console [GROUP]"`
- 我方行为：`src/celerite/cli/commands_surface.cr:3602` 的 `self.console` 先走 `reject_positional_arguments`
- 判据：`crystal spec spec/m7_console_spec.cr`
- 边界：无
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-020 控制台在独立 ruby 子进程中运行，不是参考的进程内 `console.start`

- 状态：已声明差异
- 参考行为（4.0.24）：`bundler/cli/console.rb:16` 的 `console.start` 在当前进程内启动控制台
- 我方行为：`src/celerite/cli/commands_surface.cr:3602` 起 `ruby <console_boot.rb>` 子进程，脚本由 `:3642` 取路径
- 判据：`crystal spec spec/m7_console_spec.cr`
- 边界：进程内行为（控制台读取调用方 binding、`at_exit` 顺序）不宣称一致；fallback 场景只对齐首行文案与退出码，行尾的 file:line 提示由实现文件位置决定故不设夹具
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-021 IRB 可用时的交互式 console 会话行为未验证

- 状态：未验证
- 参考行为（4.0.24）：`bundler/cli/console.rb:16` 的 `console.start` 在当前进程内进入真实 IRB 或 pry 提示符；bundle 内 `require "irb"` 有两条路径（见 018）：`force_activate` 成功则 `console.start`，失败则 `Failed to activate irb...` 加 ERROR REPORT 并 exit 1。
- 我方行为：`src/celerite/cli/commands_surface.cr:3706` 起 `ruby assets/bridge/console_boot.rb` 子进程，`:3721` 的 `console_boot_path` 定位脚本；脚本 `assets/bridge/console_boot.rb:72` 调 `console.start`。
- 判据：`crystal spec spec/m7_console_spec.cr`
- 边界：真实 TTY 交互未做 A/B，只用「打印后 exit 0」的探针控制台取证。两侧在 bundle 内都进不了 IRB：bundler 4.0.24 在 `cli/console.rb:24-28` 的 `force_activate "irb"` 后仍 `LoadError`（打 `Failed to activate irb, please install it with 'gem install irb'` 加 ERROR REPORT，exit 1），celerite 打 `irb is not available`（exit 1）。真实 IRB 会话需 Gemfile 声明 `irb` 且可离线安装，本机 gem-index 无 irb，故不可达；这是本机环境限制，不是产品缺口。bundle 外 `require` irb/reline/fiddle 均可（IRB 1.19.0 / reline 0.7.0 / fiddle 1.1.8）。
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：task-210 改写边界：删除「本机 irb/reline/fiddle 链不可用」这一已被证伪的表述（bundle 外三者均可 require），改记「两侧 bundle 内都不可达真实 IRB 会话」的实测事实；状态仍为未验证（本机环境限制）。

## C-M7-3-022 `env` 的 Gem Path 用平台分隔符并按 `Gem.path` 追加默认目录

- 状态：已实现
- 参考行为（4.0.24）：`bundler/env.rb:102` 的 `Gem.path.join(File::PATH_SEPARATOR)`，用户设置 `GEM_PATH` 时 RubyGems 会追加默认 gem 目录
- 我方行为：`src/celerite/cli/commands_surface.cr:1141` 的 `re.gem_paths.map(&.gsub(/\\/, "/")).join(Process::PATH_DELIMITER)`
- 判据：`crystal spec spec/m7_env_output_spec.cr`
- 边界：未显式设置 `GEM_HOME` 时本机 `Gem Home`/`Bin Dir` 因 RubyGems 在默认 gem 目录不可写时回退 `Gem.user_dir` 而与参考不同，属环境差异；两侧显式设 `GEM_HOME` 后逐字一致
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-023 `env` 的 Config Dir 取系统配置目录并以正斜杠渲染

- 状态：已实现
- 参考行为（4.0.24）：`bundler/env.rb:99` 的 `Pathname.new(Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE).dirname`
- 我方行为：`src/celerite/cli/commands_surface.cr:1137` 取 `re.system_config_dir || config_dir` 后 `gsub(/\\/, "/")`
- 判据：`crystal spec spec/m7_env_output_spec.cr`
- 边界：无
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-024 `env` 的 Bin Dir 取 `Gem.bindir`

- 状态：已实现
- 参考行为（4.0.24）：`bundler/env.rb:105` 的 `["  Bin Dir", Gem.bindir]`
- 我方行为：`src/celerite/cli/commands_surface.cr:1153` 的 `bin_dir = re.gem_bindir || File.join(re.default_gem_dir, "bin")`，`gem_bindir` 由桥的 `op_ruby_environment` 提供
- 判据：`crystal spec spec/m7_env_output_spec.cr`
- 边界：桥不可用时回落到 `<default gem dir>/bin`
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-025 `env` 与 `issue` 的 `## Bundler Build Metadata` 用发布常量而非本仓 git 值

- 状态：已实现
- 参考行为（4.0.24）：`bundler/build_metadata.rb` 的 `@built_at`（`2026-11-05`）与 `@git_commit_sha`（`3b396e4`）是发布时烘焙的常量，`bundler/env.rb:18` 的 `append_formatted_table("Bundler Build Metadata", BuildMetadata.to_h, out)` 原样打印
- 我方行为：`src/celerite/release_metadata.cr:10` 的 `RELEASES` 与 `:18` 的 `ReleaseMetadata.for`；`env` 在 `src/celerite/cli/commands_surface.cr:1182`、`issue` 在 `:3555` 取用
- 判据：`crystal spec spec/m7_env_output_spec.cr`
- 边界：未知 profile 回退本仓 git 值；`issue` 的 Build Metadata 无独立夹具（与 `env` 共用常量与打印路径）
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-026 `bundle version` 追加发布构建元数据，而 `-v` 与 `--version` 只打版本

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli.rb:555-567`，`build_info = " (#{BuildMetadata.timestamp} commit #{BuildMetadata.git_commit_sha})"`，仅 `bundle version` 拼接；2.x 前缀 `Bundler version `
- 我方行为：`src/celerite/cli/commands.cr:1194` 的 `def self.version(worded : Bool, stdout : IO, stderr : IO, rest : Array(String)) : Int32` 仅在 `worded` 时追加 `(#{meta[0]} commit #{meta[1]})`；`:3536` 的 `version_banner` 供 `-v`/`--version`
- 判据：`bash script/differential version-plain`
- 边界：未知 profile 无元数据后缀；`issue` 的 Build Metadata 与 `env` 共用路径
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-027 `bundle version` 的多余位置参数按 Thor 报错并 exit 15

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli.rb:555-567` 走 Thor 的 `UnknownArgumentError`，渲染 `Usage: "bundle version"` 并 exit 15
- 我方行为：`src/celerite/cli/commands.cr:1194` 在 `rest` 非空时打印 `ERROR: "bundle version" was called with arguments #{rest.inspect}` 与 `Usage: "bundle version"` 后返回 15
- 判据：`bash script/differential version-extra`
- 边界：参考的 stderr 为 CRLF（Ruby 文本模式），我方为 LF
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-028 `bundle issue` 在只有 Gemfile、无锁文件时正常解析、写锁并给 `No issues found...`

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/issue.rb:33-38` 先 `Bundler.ui.info Bundler::Env.report`（`Env.report` 始终输出 Gemfile 段），再 `Bundler.ui.info "\n## Bundle Doctor"` 并跑 doctor，无锁不是错误
- 我方行为：`src/celerite/cli/commands_surface.cr:3501` 的 `self.issue` 删除了 `lockfile.nil?` 提前返回，报告后由 `:3596` 调 `doctor_report`；`:1416` 的 `doctor_report` 在依赖满足时经 `:1619` 的 `persist_generated_lockfile` 写锁
- 判据：`bash script/differential issue-no-lockfile`
- 边界：`doctor-no-lockfile` 夹具覆盖同一路径下的 `doctor`；写锁字节数属一次性数据，留在 evidence
- 生效：task-49（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-029 `env` 与 `issue` 共用 Gemfile 段与 `<No <abs> found>` 占位

- 状态：已实现
- 参考行为（4.0.24）：`bundler/env.rb:41` 的 `out << "\n## Gemfile\n"` 与 `:63-70` 的 `read_file`（`rescue Errno::ENOENT` 时返回 `"<No #{filename} found>"`）
- 我方行为：`src/celerite/cli/commands_surface.cr:1209` 的 `private def self.print_gemfile_sections(stdout : IO, definition : Definition, bridge : Bridge::Client?) : Nil`，`env` 在 `:1198`、`issue` 在报告段共用
- 判据：`crystal spec spec/m7_issue_report_spec.cr`
- 边界：无
- 生效：task-49（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-030 无 Gemfile 时参考 `issue` 回溯宿主机 user config，双方输出不可逐字比对

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli/issue.rb:33-38` 经 `Env.report` 读取 `~/.bundle/config` 等宿主机配置
- 我方行为：`src/celerite/cli/commands_surface.cr:3565` 的 `self.issue`
- 判据：`bash script/differential issue-no-gemfile`；等价环境 A/B：按差分 `isolated_env` 复刻后运行 `issue`，比对 stdout、stderr 与退出码
- 边界：夹具 `fixtures/differential/issue-no-gemfile` 仍带 `deferred-2.7.2` 与 `deferred-4.0.24` 标记，差分命令当前两侧仍 deferred；判据以 `spec/m7_issue_report_spec.cr` 与等价环境 A/B 为准（task-206 实测：两侧 exit 10、stdout 各 1839 字节、路径归一后逐字相等、stderr 逐字同）。
- 生效：task-49（哈希未记录（evidence 未记））
- 取代：task-210 按 task-206 实测改判「已实现」：原 deferred 理由「无 Gemfile 时回溯宿主机 user config、不可逐字比对」在 harness 等价环境下不复现（两侧 stdout 归一后逐字相等）。

## C-M7-3-031 `doctor` 的完整诊断面（home 权限、路径组件、Gem path 规则）未实现

- 状态：未实现
- 参考行为（4.0.24）：`bundler/cli/doctor.rb:16-19` 的 `diagnose` 在 `require_relative "doctor/diagnose"` 后调 `Diagnose.new(options).run`。`cli/doctor/diagnose.rb:77-110` 的 `run` 依次执行：`settings.validate!`（`:79`）→ `check!`（`:80`，定义 `:67-70`，转调 `Bundler::CLI::Check`）→ `--ssl` 时 `diagnose_ssl`（`:81`，定义 `:72-75`）→ 遍历 `definition.specs` 对每个 `**/*.bundle` 取 dylibs 并 `lookup_with_fiddle`（`:83-96`；dylibs `:41-53`，Windows 等平台只 warn "Dynamic library check not supported on this platform." 并返回空）→ `check_home_permissions`（`:98` 调用、`:115-165` 定义：坏链、他人所有但可读、他人所有且不可读、不可读四类 warn 并置 `ok=false`）→ 有坏链时 `raise ProductionError`（`:107`），否则 `permissions_valid` 时打 `No issues found with the installed bundle`（`:109`）。
- 我方行为：`src/celerite/cli/commands_surface.cr:1351`（`doctor` 命令）与 `:1455` 的 `doctor_report` 只覆盖依赖满足与缺失、锁写入、`--ssl` 报告与 `*.bundle` 平台警告；`:1502-1504` 注释自认 `check_home_permissions` 警告在本环境未实现。
- 判据：`bash script/differential doctor-no-lockfile`
- 边界：`--verbose` 分层未对齐；`doctor <域>` 的值域校验未覆盖；`check_home_permissions` 在本环境无法触发。
- 归属：本行（M7-3）文字未点名 doctor，首辅裁定迁出本行闭合判据，作为独立待办。
- 生效：task-49（哈希未记录（evidence 未记））
- 取代：task-210 按 4.0.24 实测重写参考锚点：删除 4.0.24 全树不存在的 `check_path_components` / `check_gem_path`（4.0.24 只有 `cli/doctor/diagnose.rb:98`、`:115` 的 `check_home_permissions`），并补「归属」行。

## C-M7-3-032 `help` 与 `<cmd> --help` 渲染参考自带的 `.ronn` 手册页

- 状态：已实现
- 参考行为（4.0.24）：`bundler/cli.rb:155-185` 的 `#help`，`man_pages` 命中且 `Bundler.which("man")` 缺失时执行 `puts File.read("#{man_path}/#{File.basename(man_page)}.ronn")`
- 我方行为：`src/celerite/manpages.cr:20` 的 `page_name`、`:34` 的 `search_dirs`、`:65` 的 `render`；调用点 `src/celerite/cli/commands.cr:3813` 与 `:3822`
- 判据：`bash script/differential help-install`
- 边界：手册页是 vendored 副本（`assets/man/<profile>`），升级参考版本须重复制；`man` 在 PATH 上时参考走 `Kernel.exec("man", …)` 分支，本机无 man 故该分支未验证
- 生效：M7 task-3（`53024ad`）
- 取代：无

## C-M7-3-033 无手册页的命令回退 Thor `command_help`，本命令 option 表未复刻

- 状态：已声明差异
- 参考行为（4.0.24）：`bundler/vendor/thor/lib/thor.rb:252-280` 的 `command_help` 渲染 `Usage:` 行、class option 段与命令描述，完整版还会列出本命令自己的 option 表
- 我方行为：`src/celerite/cli/commands.cr:3873` 查 `THOR_HELP_FALLBACK[name]?`、`:3839` 的 `thor_help_text(entry[0], entry[1])` 输出硬编码文本（常量在 `:3925`）
- 判据：`bash script/differential help-tree-fallback`
- 边界：只渲染 usage 加 class options 加描述；硬编码文本为 4.0.24 与 2.7.2 的共同形状
- 生效：M7 task-3（`53024ad`）
- 取代：无

## C-M7-3-034 `env` 的 OpenSSL 块按解释器加载情况打印

- 状态：已实现
- 参考行为（4.0.24）：`bundler/env.rb:106-112` 打印 `OpenSSL`/`Compiled`/`Loaded`/`Cert File`/`Cert Dir` 五行，每行由独立 `defined?` 门控
- 我方行为：`src/celerite/cli/commands_surface.cr:1157` 输出 OpenSSL 五行，取值来自桥 `op_ruby_environment` 的 `openssl_compiled` / `openssl_loaded` / `openssl_cert_file` / `openssl_cert_dir`（桥侧不 `require "openssl"`）
- 判据：`crystal spec spec/m7_env_output_spec.cr`
- 边界：本机桥进程默认未加载 OpenSSL，与参考一致地不打印该块；加载态由 spec 覆盖
- 生效：M7(3) 迭代内（哈希未记录（evidence 未记））
- 取代：无

## C-M7-3-035 `env` 的多 `gemspec` 指令按 Gemfile 求值序输出且不去重，已钉住

- 状态：已实现
- 参考行为（4.0.24）：`bundler/env.rb:51-58` 的 `print_gemspecs` 先 `Dsl.new.tap { |d| d.eval_gemfile(Bundler.default_gemfile) }`，再逐条输出 `\n### <basename>` 与 ```ruby 围栏内的文件正文；`bundler/dsl.rb:63-99` 的 `gemspec` 把 `installable_on_platform?` 命中项（`dsl.rb:78`）追加进 `@gemspecs`（`dsl.rb:80`），不去重，重复的 `gemspec` 指令就在段里出现两次
- 我方行为：`src/celerite/cli/commands_surface.cr:1248-1285` 的 `print_gemfile_sections` 经 `bridge.gemspec_paths(definition.gemfile_path)`（`:1270`）取路径；`assets/bridge/server.rb:227-238` 的 `op_gemspec_paths` 直接用参考 `Bundler::Dsl#gemspecs.map(&:loaded_from)`，故顺序与重复即参考自身；客户端入口 `src/celerite/bridge/client.cr:321`
- 判据：`bash script/differential env-gemspec-multi`（stdout 逐字含 `### aaa.gemspec` / `### zzz.gemspec` / `### aaa.gemspec`，stderr 逐字含重复依赖警告）；`crystal spec spec/m7_env_multi_gemspec_spec.cr`（2 examples, 0 failures）
- 边界：同一目录放多个 `.gemspec` 且 `gemspec` 指令未给 `:name` 时，参考在 `bundler/dsl.rb:96-97` 抛 `There are multiple gemspecs at <path>. Please use the :name option to specify which one should be used`；该错误路径与 2.7.2 profile 均未验证。本项无 `src/` 改动，反假绿由 `gem-questionnaire` 承担
- 生效：task-189（提交见 `docs/compat-evidence/2026-11-23.md`）
- 取代：无
