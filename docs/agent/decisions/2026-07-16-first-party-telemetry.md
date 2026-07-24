# ADR：采用首方、明确同意的匿名观测

日期：2026-07-16

## 背景

TrailBox 已覆盖探索、详情、收藏、出发、分享和上传等长链路，但此前没有自动化回归体系，也无法在小规模用户阶段及时定位功能失败、崩溃或卡死。仅依赖 App Store Analytics 会受用户共享设置和最小样本阈值影响。

## 决策

- 使用自有 FastAPI 接收固定白名单事件和 Apple MetricKit 报告，不引入第三方分析 SDK。
- 首次启动明确询问；拒绝时不生成匿名安装标识、不入队、不订阅 MetricKit。设置中可随时关闭。
- 客户端仅保存随机安装 UUID、单次启动 session UUID、版本信息、固定事件结果和诊断；离线队列保留 7 天，上限 500 个事件和 20 份报告。
- 服务端只保存 UUID 的 HMAC-SHA256 摘要；原始事件和报告保留 30 天，管理员只查看匿名 7/30 天汇总和诊断报告。
- 禁止发送账号、Authorization Token、轨迹 ID/坐标、路线名称、搜索词、自由文本、语音或任意属性字典。

## 后果

- 能在不关联用户身份的前提下判断路线到收藏/出发/导航的会话级漏斗，并按版本定位失败和 MetricKit 诊断。
- 发布前必须同步公开隐私政策和 App Store Connect 的 Device ID、Product Interaction、Crash Data、Performance Data、Other Diagnostic Data 声明；用途为 Analytics/App Functionality，未关联用户且不用于 Tracking。
- 遥测服务不可用时业务必须继续工作；发送失败只能静默排队，不得展示用户错误或阻塞业务动作。

## 复查条件

若引入第三方 SDK、需要账号级分析、改变保留期、扩大事件字段，或需要把匿名数据与其他数据集关联，必须先重新评估隐私政策、App Store 声明和本 ADR。

---

## 修订 2026-07-24：发送并发安全与旧 build 隔离

- iOS 遥测发送采用 single-flight：同时到达的启动、scene 激活、业务事件和 MetricKit 回调只允许一个队列 drain 执行。
- 网络发送前快照事件/报告 UUID；成功后按 UUID 删除已确认项，禁止在 actor 经过网络 `await` 重入后使用旧数组的索引或数量删除。
- 启用、关闭观测都会推进 lifecycle generation。旧 lifecycle 的在途响应不得修改关闭后清空的队列，也不得修改重新启用后的新队列。
- 服务端暂时拒绝 `0.1.7 (9)` 的 `/telemetry/events` 与 `/telemetry/reports`，返回 `503 Service Unavailable` 和 24 小时 `Retry-After`。该隔离只作用于遥测接收，不影响业务 API 或 `0.1.8 (10)`。
- 移除隔离前必须确认 `0.1.8 (10)` 已形成足够覆盖，并复查线上不再存在相同 `SIGTRAP / EXC_BREAKPOINT` 队列删除崩溃。
