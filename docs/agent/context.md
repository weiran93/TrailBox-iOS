# TrailBox iOS 上下文

> 更新时间：2026-07-13
> 读者：接手 `/Users/zhaoweiran/projects/TrailBox-iOS` 的 Codex / 开发者。

## 项目状态

- TrailBox iOS 是「小野box」原生 iPhone 客户端，面向越野跑、徒步轨迹收藏、分享与 AI 运动分析。
- 仓库路径：`/Users/zhaoweiran/projects/TrailBox-iOS`。
- 关联后端与 PWA 在 `/Users/zhaoweiran/projects/TrailBox`，生产 API 默认指向 `https://runfast.fun`。
- 当前 iOS 工程零第三方依赖，使用 SwiftUI、MapKit、Swift Charts、Speech、AVFoundation、URLSession。
- App Store Connect 发布流程已有记录，详见 `AGENTS.md` 第 15 节；不要记录或外泄 `.p8` 私钥内容。

## 当前工程事实

- App 显示名：`小野box`。
- Bundle ID：`com.trailbox.ios`。
- 版本：`MARKETING_VERSION = 0.1.3`，`CURRENT_PROJECT_VERSION = 5`。
- 最低系统：iOS 16.0。
- 设备：仅 iPhone，`TARGETED_DEVICE_FAMILY = 1`。
- 生命周期：纯 SwiftUI App，入口为 `TrailBox/TrailBoxApp.swift`。
- `SessionStore`、`DeepLinkRouter`、`SavedRoutesStore`、`DeparturePlanStore` 在 app 入口注入为 environment object。
- 根导航使用系统 `TabView`；iOS 26 自动采用 Liquid Glass Tab Bar，iOS 16–25 保持对应系统原生样式。未登录选择「运动记录」或「我的」时，由 `RootView` 拦截并弹出认证页，登录成功后再进入原目标 Tab；不要让未登录的记录页停留在 ViewModel 的 loading 状态。详情页隐藏底栏，探索、运动记录和「我的」三个根页面按导航路径显式恢复底栏可见，避免返回后继承隐藏状态。根页面进入详情时应更新其绑定的 `navigationPath`；运动记录卡片使用程序化路径跳转，不要改回不更新路径的直接 `NavigationLink`，否则父页面会错误地强制显示 Tab Bar。
- `TrailBox/DesignSystem.swift` 提供统一的 `trailBoxGlass(...)` 修饰器和 `FloatingActionBar`：iOS 26 使用原生 `glassEffect`，iOS 16–25 使用系统 Material 回退；玻璃效果优先用于导航和悬浮操作层，内容卡片保持实体表面，页面底部主操作复用公共操作栏布局。
- 当前视觉语言为「山野地图 + Liquid Glass」：基础色使用森林绿、苔藓绿与暖米色，页面背景可使用低对比度等高线纹理；玻璃效果不覆盖主要内容卡片，路线数据和长文本继续使用高对比度实体表面。探索卡片以轨迹图、路线负荷和距离/累计爬升/参考用时组成决策层级；公开路线详情首屏将地图、名称和位置合并为 Hero，并用统一的「路线说明书」汇总距离、爬升、坡度、预计用时、出发判断、动态提醒和资料状态，详细内容使用概览/分析/设施/跑友/剖面吸顶分段导航，原始来源卡片继续保留；详情一级模块标题统一复用同尺寸的圆角图标底板、SF Symbol 与标题字级，不再混用裸标题和普通 `Label`。运动记录根页使用训练总览 Hero 和轨迹记录卡片；记录详情按记录 Hero、运动概览、地图、AI 复盘和运动图表组织，海拔、坡度、心率与配速图表统一以沿途距离为横轴并限制展示采样数。AI 复盘结果按结论、原因、行动、恢复与风险拆分为实体内容块；分析期间使用状态进度和分段揭示反馈，并在系统开启「减少动态效果」时关闭循环和位移动画。「我的」根页在个人 Hero 中汇总收藏、贡献和 ITRA，并在收藏与贡献预览中直接展示完整取景的轨迹。
- 「我的记录」顶部包含 ITRA 资料入口。未绑定时展示查询 banner；已绑定时展示 ITRA 基础资料，并可进入 App 内 ITRA 详情页。
- 「探索路线」顶部新增「贡献路线」入口，普通用户可上传轨迹并公开贡献到社区；对应页面为 `TrailBox/ContributeRouteView.swift`，后端 `Track` 模型新增 `recommendation_reason`（推荐理由）字段。
- 登录用户可在探索列表和公开路线详情收藏/取消收藏路线；`TrailBox/SavedRoutesStore.swift` 维护跨页面的收藏状态、乐观更新和请求防重，成功后由根视图显示统一反馈，取消收藏可在短时间内撤销。「我的」页提供收藏预览和完整列表。后端收藏盒子只返回路线摘要、不包含轨迹点，客户端必须为缺少 `points` 的收藏项并发读取公开详情并缓存预览轨迹，不能直接把盒子响应交给轨迹卡片。后端复用私有路线盒子，提供 `GET /boxes/want-to-run`、`PUT /boxes/want-to-run/tracks/{track_id}`、`DELETE /boxes/want-to-run/tracks/{track_id}`。
- 收藏路线完整列表支持搜索、城市筛选、距离/爬升排序和侧滑取消收藏；卡片使用程序化跳转，避免系统 `NavigationLink` 附件压缩卡片宽度。
- 探索路线卡片使用距离和每公里爬升密度给出透明的路线负荷提示，卡片数据区直接展示距离、累计爬升和基于距离/爬升估算的参考用时；该提示和参考用时只用于列表决策辅助，不替代详情页的服务端路线分析。
- 探索路线列表提供「这次想怎么跑」意图快捷入口，当前按参考用时、距离和爬升密度生成 2 小时左右、半日、全天、新手友好、爬升训练和长距离等选项；只展示当前已加载路线中确实有结果的类型，并继续保留标签、城市、距离和排序等精细筛选。
- 探索路线的筛选面板使用临时草稿，只有点击「应用」才写入列表状态；已启用的城市、距离和排序会显示数量徽标，列表顶部同步显示当前结果数和筛选摘要，并提供一键清除。页面 ViewModel 随导航栈保留，进入详情再返回时不会重置已有搜索与筛选。
- 公开路线详情已接入路线智能层：`RouteIntelligenceStore` 并发加载难度与路线形态、预计用时、补给装备建议、动态天气与日落、沿途设施、近期路况、跑友评价、完成记录和登录用户的个性化适配。贡献者可确认 MapKit 搜索到的设施，运动记录上传后会自动匹配已公开路线。
- 路线智能后端位于关联仓库的 `api/app/routers/route_intelligence.py` 与 `api/app/services/route_intelligence.py`，已于 2026-07-13 部署到 `runfast.fun`。路线分析为可解释的确定性计算；天气来源为 Open-Meteo，15 分钟内存缓存；沿途设施来源和更新时间必须在 UI 中明确标注，不能把地图检索结果表述为已核实的补水点。
- 路线智能信息采用渐进加载：分析、天气、设施和跑友信息各自完成后立即更新；设施检索期间保持固定骨架占位，并在进程内缓存 MapKit 结果，避免卡片延迟插入造成页面跳动。下拉刷新或菜单手动刷新时保留上一次成功数据并显示更新时间，单项失败仅在对应模块提示且支持独立重试，不能因刷新或某项请求失败而清空、静默隐藏整块内容。
- 登录用户可在公开路线详情根据路线分析、个性化适配、天气、日落、近期路况和设施信息生成「出发计划」。`TrailBox/DeparturePlanStore.swift` 按用户将计划保存在 UserDefaults，计划包含建议出发时间、预计完成区间、最晚安全出发时间、风险摘要和可勾选准备清单；「我的」页提供最近计划预览与完整列表。计划属于本地辅助建议，设施未核实状态和安全免责说明必须保留。
- 公开路线详情底部主操作为「一键出发」，动作面板集中提供起点导航、出发计划、GPX 导出和路线收藏；公开路线导航与 GPX 导出不要求登录，出发计划和收藏仍要求登录。路线资料状态只根据轨迹解析、路线分析、天气、设施与跑友数据的实际可用性展示，必须明确区分「设施已确认」和「地图设施待核实」，且不能将资料完整度表述为路线安全认证。
- ITRA 详情依赖后端公开资料解析接口：`GET /integrations/itra/profile/{runner_id}` 和 `POST /integrations/itra/profile/parse-html`。如果服务器抓取公开页只得到 partial，iOS 会尝试原生拉取公开 HTML 后提交后端 parser 兜底。

## 关键命令

```bash
cd /Users/zhaoweiran/projects/TrailBox-iOS

xcodebuild -scheme TrailBox -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

本地后端联调：

```bash
cd /Users/zhaoweiran/projects/TrailBox/api
source .venv/bin/activate
python3 run.py
```

真机调本地后端时，通过 Xcode Launch Argument 设置：

```text
-trailboxAPIBaseURL http://<Mac 局域网 IP>:<端口>
```

## 需求池工作流

Todo agent CLI 位于 `/Users/zhaoweiran/projects/todo`，`TrailBox-iOS` 项目 ID 为 `cmr6gvqen000dr3pklitxsh8q`。CLI token 已保存在本机 `~/.todo-agent.json` 时可直接使用；不要把 token 写入仓库、文档或聊天。

查询需求池：

```bash
cd /Users/zhaoweiran/projects/todo
npm run agent:cli -- requirements list --project cmr6gvqen000dr3pklitxsh8q --status backlog
```

查看单条需求：

```bash
npm run agent:cli -- requirement get <requirement-id>
```

开始实现前更新状态：

```bash
npm run agent:cli -- requirement update <requirement-id> \
  --status in_progress \
  --log "Agent 开始实现：<简短说明>"
```

完成并验证后更新状态：

```bash
npm run agent:cli -- requirement update <requirement-id> \
  --status done \
  --log "已完成并验证：<变更摘要；验证命令或结果>"
```

## 代码约束

- 新增用户可见文案保持中文。
- 不要硬编码本地 API 地址；使用 `-trailboxAPIBaseURL` 覆盖。
- 不要私自引入 CocoaPods、SPM 或 Carthage；确需依赖时先更新依赖说明和上下文文档。
- 修改敏感权限时同步检查 `TrailBox/Info.plist` 的 UsageDescription。
- 修改 universal link、隐私政策、App Store 链接或支持邮箱时，同步检查 `TrailBox/AppConfiguration.swift`、`TrailBox/TrailBox.entitlements` 和相关文档。

## 待确认事项

- `privacy.html` 当前在仓库根目录但未跟踪；除非用户明确要求，不要自动加入 iOS 仓库。
- `AGENTS.md` 仍包含大量知识库和发布历史，后续如要瘦身，应先给出迁移/拆分计划并等待确认。
- 关联后端仓库已在本地修复公开 GPX 导出触发 SQLAlchemy 异步懒加载而返回 500 的问题，并新增回归测试；`runfast.fun` 尚未部署该修复，生产 GPX 导出需在明确发布后才能恢复。
