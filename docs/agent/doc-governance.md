# Agent 文档治理

> 更新时间：2026-07-07

## 核心文档职责

- `AGENTS.md`：每次接手仓库必须读取的操作守则、关键命令入口、强约束和长期注意事项。
- `docs/agent/context.md`：项目当前状态摘要，记录未来任务会反复用到的稳定事实。
- `docs/agent/doc-governance.md`：规定 agent 文档何时更新、拆分、删除或保持不变。

## 更新触发

完成以下变更后，必须做文档影响检查：

- 构建、测试、运行、发布、部署命令发生变化。
- 修改项目结构、模块边界、架构约束或公共接口。
- 新增第三方依赖、敏感权限、URL scheme、universal link、API base URL 或签名配置。
- 修改版本号、Bundle ID、App Store 发布流程或后端/PWA 协作方式。
- 发现 `AGENTS.md` 或 `docs/agent/` 与代码、命令实际行为不一致。

## 路由规则

- 只影响 Codex 操作方式的短规则，写入 `AGENTS.md`。
- 项目当前事实、常用命令和长期约束，写入 `docs/agent/context.md`。
- 文档维护规则，写入本文件。
- 架构说明反复影响实现时，创建 `docs/agent/architecture.md`。
- 测试体系复杂到需要按改动范围选择命令时，创建 `docs/agent/testing.md`。
- 发布流程需要独立维护时，创建 `docs/agent/release.md`，并让 `AGENTS.md` 只保留入口。
- 重要长期决策需要背景、取舍和复查条件时，创建 `docs/agent/decisions/YYYY-MM-DD-title.md`。

## 禁止写入

- 一次性任务说明、临时调试过程、未确认猜测。
- 密钥、令牌、私有账号密码、`.p8` 私钥内容或客户隐私。
- 代码局部细节，除非它代表长期架构约束。
- 已经能从代码、类型或正式 README 直接读出的低价值重复信息。

## 需要用户确认

执行以下操作前先给计划并等待确认：

- 删除、重命名或归档长期上下文文档。
- 大幅重写或瘦身 `AGENTS.md`。
- 将敏感或可能仍有价值的历史发布信息移出当前文档。
- 引入新的长期文档结构，且会影响后续 agent 的读取路径。

## 收尾要求

使用 `project-context-manager` 后，最终回复说明：

- `docs updated`：实际更新的文档。
- `docs unchanged`：检查过但无需更新的文档及原因。
- `needs confirmation`：需要用户确认的清理、大改或归档项。
- `verification`：运行过的命令或做过的检查。
