# 工程约定

- 开发命令：`shards build`、`crystal spec`、`crystal tool format --check src spec`。
- 核心依赖管理路径使用 Crystal；Ruby 只承载明确定义的兼容边界，禁止以静默执行 `bundle install` 代替实现。
- 兼容性改动必须附与指定 Bundler 版本的差分用例；输出、锁文件和退出码均需断言。
- 不将模板测试、空实现或未测的兼容声明标记为完成。
- 提交前运行上述检查，并只暂存本任务相关文件。

当前架构、范围与实施顺序见 `docs/`。
