# TrailBox iOS 上下文

> 更新时间：2026-07-08
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
- `SessionStore`、`DeepLinkRouter`、`BottomBarVisibilityStore` 在 app 入口注入为 environment object。
- `BottomBarVisibilityStore` 当前定义在 `TrailBox/RootView.swift`，没有独立 Swift 文件。
- 「我的记录」顶部包含 ITRA 资料入口。未绑定时展示查询 banner；已绑定时展示 ITRA 基础资料，并可进入 App 内 ITRA 详情页。
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
