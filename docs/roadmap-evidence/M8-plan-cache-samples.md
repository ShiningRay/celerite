# M8 L165 计划缓存：本机实测样本（task-254）

采集时间：2026-11-24 13:36–13:45（local，Asia/Shanghai）。采集机：本机 Windows，Crystal 1.22.1 构建的 `bin\celerite.exe`（`--version` = `4.0.24`），Ruby 位于 `C:\Ruby40-x64`。

配套设计文档：`docs/roadmap-evidence/M8-plan-cache-plan.md`（第 6 节表格即本文件的汇总）。

## 采集方法

```powershell
$env:PATH = "C:\msys64\usr\bin;C:\msys64\ucrt64\bin;C:\Ruby40-x64\bin;C:\Program Files\Git\cmd;" + $env:PATH
$env:CELERITE_BRIDGE_STATS = "1"
$env:CELERITE_CACHE_DIR = "C:\temp\t254-cache-a"
$env:BUNDLE_PATH = "C:\temp\t254-proj\vendor\bundle"
# 每次运行：Stopwatch 包住整次进程调用，stderr 落文件后抓 bridge 行
& C:\temp\celerite-t254\bin\celerite.exe install 2> stderr.txt
```

- 统计行格式来自 `src/celerite/bridge/client.cr:93-95`：`bridge: procs=N rpc=N req_bytes=N resp_bytes=N`。
- 冷场景先删 `C:\temp\t254-proj\vendor\` 与 `Gemfile.lock`。
- 项目：`C:\temp\t254-proj`，`Gemfile` 为 `source "file:///C:/temp/celerite-t254/fixtures/gem-index"` + `gem "json_pure"` + `gem "thor"`；源为仓库内 `fixtures/gem-index`（本地索引，无网络）。
- 全部运行退出码 0。

## 主矩阵（3 场景 × 2 次）

| 场景 | 次 | procs | rpc | req_bytes | resp_bytes | wall_ms | 退出码 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 冷 `install` | 1 | 1 | 21 | 4285 | 320366 | 2172 | 0 |
| 冷 `install` | 2 | 1 | 21 | 4283 | 320366 | 1305 | 0 |
| 无变化 `install` | 1 | 1 | 10 | 1675 | 315715 | 1053 | 0 |
| 无变化 `install` | 2 | 1 | 10 | 1675 | 315715 | 1146 | 0 |
| 无变化 `lock` | 1 | 1 | 2 | 207 | 1911 | 404 | 0 |
| 无变化 `lock` | 2 | 1 | 2 | 207 | 1911 | 794 | 0 |

## 归因样本

| 样本 | 命令/条件 | procs | rpc | req_bytes | resp_bytes | wall_ms |
| --- | --- | --- | --- | --- | --- | --- |
| CLI 进程底（首次） | `celerite --version` | 0 | 0 | 0 | 0 | 272 |
| CLI 进程底（暖） | `celerite --version` | 0 | 0 | 0 | 0 | 28 |
| 只读命令 | `celerite check` | 1 | 2 | 211 | 3115 | 366 |
| 单 gem 项目冷装 | `celerite install`（仅 `thor`，独立项目 `C:\temp\t254-proj2`） | 1 | 15 | 2886 | 317786 | 1504 |
| 单 gem 项目热装 | 同上，第二次 | 1 | 9 | 1445 | 315470 | 1229 |
| 宿主 gem 隐藏 | 无变化 `install`，`GEM_HOME`=`GEM_PATH`=`C:\temp\t254-gemhome`（空目录） | 1 | 10 | 1675 | **15553** | 1087 |
| 本地源约束 | `celerite install --local`（无变化） | 1 | 10 | 1675 | 315715 | 1106 |

## 读法

- 冷/热差：21 → 10 rpc、320,366 → 315,715 B，对应下载与落盘动作（`src/celerite/installer.cr:132`、`:236-291`）。
- 无变化 install 的 ~300 KB 响应与项目 gem 数无关（1 gem 315,470 B vs 2 gem 315,715 B），随宿主已装 gem 规模变化（`GEM_HOME` 置空后 15,553 B、rpc 不变），判为宿主 Ruby 已装 spec 枚举；具体 RPC 名与调用点**未定位**。
- `lock` 的 2 rpc / 1,911 B / 404–794 ms 是解析侧成本的可测上界；未逐 op 打点，属按代码路径（`src/celerite/cli/commands_install.cr:490` → `src/celerite/resolution.cr:1096` → `:1183`）的推断。
