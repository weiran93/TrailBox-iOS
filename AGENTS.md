# TrailBox iOS — Agent 接手文档

> 文档定位：本文件面向需要继续迭代、修复或扩展 TrailBox iOS 端的 AI Agent / 开发者。阅读后应能独立完成编译、运行、定位代码、添加功能。
> 文档版本：2026-06-23（基于项目当前文件状态）
> 项目路径：`/Users/zhaoweiran/projects/TrailBox-iOS`

---

## 1. 项目概述

**TrailBox（小野box）** 是一个面向越野跑 / 徒步用户的轨迹收藏与分享应用。iOS 端是该产品的原生客户端，与现有的 FastAPI 后端和 PWA 前端共享同一套业务数据。

- **App 显示名**：`小野box`
- **Bundle ID**：`com.trailbox.ios`
- **当前版本**：`0.1.0`（Build `1`）
- **iOS 最低版本**：iOS 16.0
- **设备支持**：仅 iPhone（`TARGETED_DEVICE_FAMILY = 1`）
- **开发团队**：`CNXB3793X3`
- **生命周期**：纯 SwiftUI 4 App 生命周期，无 `AppDelegate` / `SceneDelegate`

### 1.1 与相关项目的关系

本仓库是 iOS 原生客户端，与以下项目共享同一套后端业务数据：

- **后端 + PWA**：`/Users/zhaoweiran/projects/TrailBox`
  - `api/`：FastAPI 后端
  - `web/`：PWA 前端

```
TrailBox-iOS/              # 本仓库
├── AGENTS.md              # 本文件
├── TrailBox.xcodeproj     # Xcode 工程
└── TrailBox/              # 源码目录
```

iOS 端复用后端 API，默认连接生产域名 `https://runfast.fun`；本地开发可通过 Xcode Launch Argument 指向本机后端。

> 本地联调时需要同时启动 `/Users/zhaoweiran/projects/TrailBox/api` 下的后端服务。

### 1.2 仓库拆分状态（已完成）

本地 `/Users/zhaoweiran/projects/TrailBox-iOS` 已作为独立 Git 仓库从原 `TrailBox` monorepo 拆分出来，并已成功推送至 GitHub。

- 当前本地分支：`main`
- 当前最新提交：`6a6ec61 chore: add .gitignore and track Xcode workspace metadata`
- 当前 remote：`origin` → `https://github.com/weiran93/TrailBox-iOS.git`
- GitHub 仓库：`https://github.com/weiran93/TrailBox-iOS`
- `gh`（GitHub CLI）已登录为 `weiran93`

已完成的本地准备：

1. 新增 `.gitignore`，过滤 `.DS_Store` 和 Xcode `xcuserdata/` 等用户特定文件。
2. 提交 `.gitignore`。
3. 提交 `TrailBox.xcodeproj/project.xcworkspace/contents.xcworkspacedata`（Xcode 工程需要的元数据文件）。

待确认：

1. `privacy.html` 当前未跟踪，需确认是否属于本仓库；**暂不建议自动提交**。

拆分完成的标准：

1. ✅ GitHub 上存在 `weiran93/TrailBox-iOS` 仓库。
2. ✅ 本地 `TrailBox-iOS` 配置了 remote `origin` 指向该仓库。
3. ✅ 本地 `main` 分支已成功推送至 GitHub。

---

## 2. 如何构建与运行

### 2.1 前置条件

- macOS + Xcode 14.0 或更高版本（当前项目最近由 Xcode 26.5 编辑）
- iOS 16.0+ SDK
- **无需安装 CocoaPods / Swift Package Manager / Carthage**：项目零第三方依赖

### 2.2 当前构建阻塞（必须先修）

文件 `TrailBox/BottomBarVisibilityStore.swift` 已存在磁盘，但 **未加入 `TrailBox.xcodeproj` 的 Compile Sources 构建阶段**。由于 `TrailBoxApp.swift` 和 `RootView.swift` 都引用了它，项目当前无法编译。

**修复步骤（Xcode）：**

1. 打开 `TrailBox.xcodeproj`
2. 选中 `TrailBox` 目标 → `Build Phases` → `Compile Sources`
3. 点击 `+` → 添加 `TrailBox/BottomBarVisibilityStore.swift`

或者直接在 Finder 中把该文件拖入 Xcode 的 `TrailBox` 源码分组，勾选 `Copy items if needed` 和目标 `TrailBox`。

### 2.3 构建命令行

```bash
cd /Users/zhaoweiran/projects/TrailBox-iOS

# 查看可用模拟器
xcodebuild -scheme TrailBox -sdk iphonesimulator -showdestinations

# 构建（示例：iPhone 17 模拟器）
xcodebuild -scheme TrailBox -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGNING_ALLOWED=NO
```

### 2.4 运行与调试

- Xcode 打开工程，选择 iPhone 模拟器或真机，按 `Cmd+R`。
- 真机调试需要 Apple Developer 账号并配置自动签名（已在 pbxproj 中开启 Automatic signing）。
- 默认 API 指向 `https://runfast.fun`；本地调试需改 Launch Argument（见 4.2）。

### 2.5 本地后端联调

```bash
# 启动后端（端口以后端实际配置为准，常见 8000 或 8001）
cd /Users/zhaoweiran/projects/TrailBox/api
source .venv/bin/activate
python3 run.py
```

在 Xcode 中：

1. `Product` → `Scheme` → `Edit Scheme` → `Run` → `Arguments`
2. 添加启动参数：`-trailboxAPIBaseURL http://<你的 Mac 局域网 IP>:<端口>`
3. 注意：真机不能访问 `127.0.0.1:8000`，必须使用 Mac 的 LAN IP

---

## 3. 技术栈与架构

### 3.1 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | SwiftUI 4 |
| 并发 | `async/await`，无 Combine |
| 数据观察 | `ObservableObject` + `@Published` + `@StateObject` / `@EnvironmentObject` |
| 网络 | `URLSession` 原生（`APIClient.shared` 单例） |
| 本地持久化 | Keychain（token）、UserDefaults（用户缓存） |
| 地图 | MapKit |
| 图表 | Swift Charts |
| 语音 | `Speech` + `AVFoundation` |
| 分享卡渲染 | MapKit Snapshot + CoreGraphics + Core Image |

### 3.2 架构模式

- **MVVM-lite**：每个主要页面都有独立的 `ViewModel`（`ExploreViewModel`、`MyTracksViewModel`、`TrackDetailViewModel`、`ShareCardRenderer`），视图持有 `@StateObject`。
- **全局状态注入**：`SessionStore`、`DeepLinkRouter`、`BottomBarVisibilityStore` 作为 `EnvironmentObject` 在 `TrailBoxApp` 注入。
- **单例依赖**：`APIClient.shared` 是网络入口；没有 DI 容器或协议抽象，新增依赖保持同样风格即可。
- **无测试**：当前无 Unit Test / UI Test 目标。

---

## 4. 源码文件速查

源码集中在 `TrailBox/TrailBox/`。

### 4.1 应用骨架

| 文件 | 作用 |
|------|------|
| `TrailBoxApp.swift` | `@main` 入口，注入环境对象，处理 deep link / universal link |
| `RootView.swift` | 根视图：自定义底部 Tab 栏（探索路线 / 我的记录），控制认证弹窗 |
| `AuthenticationView.swift` | 登录 / 注册 Sheet |
| `DeepLinkRouter.swift` | 处理 `https://runfast.fun/r/{id}`，跳转公开轨迹详情 |
| `BottomBarVisibilityStore.swift` | 控制自定义底部导航栏显隐 |

### 4.2 页面与业务

| 文件 | 行数 | 作用 |
|------|------|------|
| `ExploreView.swift` | ~450 | 公开路线列表：搜索、标签、城市/距离/排序筛选、分页 |
| `MyTracksView.swift` | ~1,500 | 我的记录：个人轨迹列表、月度统计、上传、设置、管理员后台 |
| `TrackDetailView.swift` | ~1,700 | 轨迹详情：地图、海拔/坡度/配速/心率图、AI 分析、语音反馈、分享、下载 GPX、举报/拉黑、导航 |
| `ShareCard.swift` | ~850 | 1080×1440 分享卡渲染：MapKit 快照、PWA 风格、二维码、保存相册 |
| `SharePreviewView.swift` | ~100 | 分享预览 Sheet |

### 4.3 数据与服务

| 文件 | 作用 |
|------|------|
| `Models.swift` | 所有 Codable 领域模型：`User`、`Track`、`TrackPoint`、`AIAnalysis`、`ActivityFeeling` 等 |
| `APIClient.swift` | 单例 REST 客户端：JSON 请求、multipart 上传、GPX 下载、日期解析兼容 |
| `SessionStore.swift` | 认证状态：登录/注册/登出/注销、token 管理、401 处理 |
| `KeychainStore.swift` | Keychain 封装，用于保存 access token |
| `AppConfiguration.swift` | API Base URL、隐私政策链接、支持邮箱、启动参数读取 |
| `DesignSystem.swift` | 全局颜色、卡片组件、空状态、格式化工具 |

### 4.4 资源

| 文件/目录 | 作用 |
|-----------|------|
| `Assets.xcassets/AppIcon.appiconset` | App 图标 |
| `Info.plist` | 权限声明、URL Schemes 白名单、启动屏 |
| `TrailBox.entitlements` | Associated Domains：`applinks:runfast.fun` |

---

## 5. 关键业务与 API

### 5.1 认证

- `POST /auth/login`
- `POST /auth/register`
- Token 存 Keychain；`User` 缓存到 UserDefaults（key：`trailbox.current-user`）
- 401 时 `SessionStore.handle(_:)` 会清空登录态

### 5.2 轨迹相关

| 接口 | 用途 |
|------|------|
| `GET /tracks/public?include_points=true&limit=20&offset=...` | 公开路线列表 |
| `GET /tracks/my?include_points=true&limit=20&offset=...` | 我的轨迹 |
| `GET /tracks/{id}` | 轨迹详情（需登录） |
| `GET /tracks/{id}/public` | 公开轨迹详情（deep link 使用） |
| `POST /tracks` | 上传 `.fit`/`.gpx`/`.kml` |
| `POST /tracks/suggest-metadata` | 上传前自动推荐名称/城市/标签/运动类型 |
| `GET /tracks/{id}/download.gpx` | 下载 GPX |
| `POST /tracks/{id}/ai-analysis` | 提交体感，获取 AI 分析 |

### 5.3 用户与设置

| 接口 | 用途 |
|------|------|
| `GET /users/me` | 当前用户信息 |
| `PATCH /users/me` | 修改昵称 |
| `POST /users/me/change-password` | 修改密码 |
| `DELETE /users/me` | 注销账号 |

### 5.4 管理与审核

| 接口 | 用途 |
|------|------|
| `GET /admin/stats` | 统计 |
| `GET /admin/tracks` | 全部轨迹 |
| `POST /admin/tracks/batch` | 批量上传 |
| `GET /admin/reports` | 举报列表 |
| `POST /admin/reports/{id}/resolve` | 处理举报 |
| `GET /tags` | 标签列表 |
| `PUT /admin/tags` | 配置标签 |
| `POST /moderation/reports` | 举报 |
| `POST /moderation/blocks` | 拉黑 |

### 5.5 JSON 约定

- 后端返回 snake_case，客户端通过 `CodingKeys` 映射为 camelCase。
- 日期格式兼容多种 ISO8601 和普通日期字符串（见 `APIClient` 自定义 `dateDecodingStrategy`）。
- 请求编码使用 `.convertToSnakeCase`。

---

## 6. 状态管理指南

### 6.1 全局状态（EnvironmentObject）

```swift
@main
struct TrailBoxApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var bottomBarVisibility = BottomBarVisibilityStore()
    // ...
}
```

- `SessionStore`：登录态、用户信息、触发认证弹窗。
- `DeepLinkRouter`：保存待处理的 deep link route。
- `BottomBarVisibilityStore`：控制 `RootView` 底部栏显隐。

### 6.2 页面级状态（ViewModel）

- ViewModel 为 `@MainActor final class ...: ObservableObject`，含 `@Published` 属性。
- 典型模式：
  - `items: [Track]` / `isLoading: Bool` / `error: Error?` / `hasMore: Bool`
  - 分页加载方法 `loadMore()`、`refresh()`
- 视图通过 `@StateObject private var viewModel = ExploreViewModel()` 持有。

### 6.3 本地持久化

| 数据 | 存储方式 | Key |
|------|----------|-----|
| Access Token | Keychain | `com.trailbox.access-token` |
| 当前用户 JSON | UserDefaults | `trailbox.current-user` |

---

## 7. 主要功能模块

### 7.1 探索路线（ExploreView）

- 公开轨迹卡片列表，上图下文布局。
- 顶部：搜索框 + 标签横向滚动。
- 底部面板：城市筛选、距离范围、排序（最新/距离/海拔等）。
- 分页：每页 20 条，下滑加载更多。

### 7.2 我的记录（MyTracksView）

- 个人轨迹列表与月度统计。
- 上传流程：选择文件 → 自动推荐元数据 → 编辑名称/城市/标签/运动类型/公开性/贡献者显示 → 上传。
- 设置：修改昵称、DeepSeek API Key、隐私政策、联系邮箱、注销账号。
- 管理员入口：统计、批量上传、标签配置、举报处理、AI 设置。

### 7.3 轨迹详情（TrackDetailView）

- MapKit 地图，显示起点/终点标注。
- 图表：海拔、坡度、配速、心率（私人数据）。
- AI 运动分析：可语音或文字输入体感反馈，后端返回结构化分析。
- 操作：下载 GPX、生成分享卡、举报/拉黑、导航到起点/终点。
- 导航支持：Apple Maps、高德、百度、腾讯、Google Maps。

### 7.4 分享卡（ShareCard）

- 渲染 1080×1440 图片。
- 使用 MapKit Snapshotter 生成路线缩略图，叠加 CoreGraphics 排版。
- 生成二维码（deep link）。
- 可保存到相册、系统分享。

### 7.5 分享落地页与 Universal Link

分享卡片二维码指向：`https://runfast.fun/r/{id}?utm_source=share_card&...`

该链接同时承担两个职责：

1. **PWA 落地页**（未安装 App 时）
   - 后端 `api/app/main.py` 通过 SPA fallback 将 `/r/{id}` 交给 `web/index.html`。
   - PWA `web/app.js` 检测到路径 `/r/{id}` 后，调用 `renderShareLanding(trackId)`。
   - 落地页展示公开路线详情，并在顶部显示 App 引导条：
     - 「打开 APP」按钮
     - 微信内额外提示：「点击右上角 ⋯ → 在 Safari 中打开」
   - 页面隐藏底部 Tab 导航，专注展示单条路线。

2. **iOS Universal Link**（已安装 App 时）
   - iOS App 的 `TrailBox.entitlements` 声明 `applinks:runfast.fun`。
   - 后端提供 AASA 文件：`GET /.well-known/apple-app-site-association`。
   - 用户在 Safari 中访问 `https://runfast.fun/r/{id}` 时，系统会唤起 App 并进入路线详情。
   - `DeepLinkRouter` 解析路径 `/r/{id}`，弹出 `TrackDetailView`。

> 注意：微信内置浏览器会拦截 Universal Link 自动唤起，因此落地页需要在微信内给出明确的「用 Safari 打开」引导。

> **当前临时调整（2026-06-23）**：由于 `runfast.fun` 域名 ICP 备案尚未完成，公网 80/443 被阿里云拦截，分享卡片中的路线二维码暂时移除。路线版分享卡（`ShareCardType.routeQR`）底部改为文案引导：「在 App Store 搜索「小野box」下载 APP」。待 ICP 备案完成或 App Store 链接确定后，可恢复二维码或改为指向 App Store 产品页。相关实现见 `TrailBox/ShareCard.swift`。

---

## 8. 编码规范

### 8.1 语言与命名

- Swift 5.0，UI 文案大量使用中文。
- 类型：PascalCase；函数/变量：camelCase。
- ViewModel 后缀为 `ViewModel`；单例使用 `shared`。
- 模型使用 `Codable`，`CodingKeys` 处理 snake_case。

### 8.2 视图与 ViewModel

- 视图是 `struct` 遵守 `View`。
- 视图模型是 `@MainActor final class` 遵守 `ObservableObject`。
- 全局状态通过 `.environmentObject(...)` 注入，视图内用 `@EnvironmentObject` 读取。
- 页面内部大量内联 `private` 计算属性 / helper view。

### 8.3 网络请求写法

```swift
let tracks: [Track] = try await APIClient.shared.request(
    "/tracks/public?include_points=true&limit=20&offset=0",
    token: session.token
)
```

- 需要 token 的接口传 `token`。
- 上传文件使用 `APIClient.shared.uploadTrack(...)` 或 `uploadAdminTracks(...)`。

### 8.4 错误处理

- API 层抛出 `APIError`（invalidResponse / unauthorized / server）。
- 视图模型捕获后设置 `errorMessage` 或调用 `session.handle(error)` 处理 401。

---

## 9. 已知问题与注意事项

1. **版本号不一致**：`SettingsView` 中硬编码版本 `v1.6.1`，但 `MARKETING_VERSION` 是 `0.1.0`。发布前需统一。**（已修复：2026-06-23 改为从 `Bundle.main` 读取 `CFBundleShortVersionString`。）**
2. **无单元/UI 测试**：新增关键逻辑时建议补充测试。
3. **中文 UI 文案**：所有用户可见文本都是中文，新增文案保持一致。
4. **权限声明**：`Info.plist` 已声明麦克风、语音识别、相册写入。新增敏感权限必须补充 UsageDescription。
5. **Deep Link 域名**：`runfast.fun`，仅支持 HTTPS universal link，无自定义 URL scheme。分享卡片二维码指向 `https://runfast.fun/r/{id}`，该链接同时作为 PWA 落地页和 iOS Universal Link 使用。
6. **后端地址**：默认生产 `https://runfast.fun`；本地调试用 Launch Argument 覆盖，不要硬编码到代码里。
7. **无第三方依赖**：不要私自引入 CocoaPods / SPM 包；如确需引入，需在本文档更新依赖说明。
8. **分享卡二维码临时移除**：因 ICP 备案未完成，`runfast.fun` 落地页无法访问，分享卡片（路线版）不再渲染二维码，改为底部文案「在 App Store 搜索「小野box」下载 APP」。待 ICP 备案完成或 App Store 链接确定后可恢复。相关代码位于 `TrailBox/ShareCard.swift`。

---

## 10. 如何新增功能

### 10.1 新增页面

1. 在 `TrailBox/` 下创建 `NewFeatureView.swift`。
2. 如需页面级状态，创建 `NewFeatureViewModel.swift`（`@MainActor final class: ObservableObject`）。
3. 在 `RootView` 或相关页面中导航进入。
4. 如需网络接口，优先在 `APIClient` 新增方法或复用 `request(_:method:body:token:)`。
5. 如需数据模型，加到 `Models.swift`。

### 10.2 新增网络接口

1. 在 `Models.swift` 定义 Request/Response 模型。
2. 在 `APIClient.swift` 新增方法；尽量保持与现有风格一致（单例、`async throws`、统一错误处理）。
3. 在 ViewModel 中调用，视图观察 `@Published` 状态。

### 10.3 修改 UI/样式

- 颜色优先使用 `TrailBoxColor`。
- 卡片优先使用 `SectionCard`。
- 空状态使用 `EmptyStateView`。
- 距离/海拔格式化使用 `DisplayFormat`。

### 10.4 修改项目配置

- Bundle ID、版本号、签名团队在 `project.pbxproj`。
- 权限文案在 `Info.plist`。
- Associated Domains 在 `TrailBox.entitlements`。

---

## 11. 常用命令速查

```bash
# 进入 iOS 项目目录
cd /Users/zhaoweiran/projects/TrailBox-iOS

# 构建到模拟器
xcodebuild -scheme TrailBox -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGNING_ALLOWED=NO

# 启动后端（端口以实际配置为准）
cd /Users/zhaoweiran/projects/TrailBox/api
source .venv/bin/activate
python3 run.py
```

---

## 12. 生产部署说明（阿里云）

> 当前状态：后端代码已部署到阿里云 ECS，但因域名 `runfast.fun` 尚未完成 ICP 备案，公网 80/443 端口被阿里云拦截，无法直接访问。备案通过并配置 Nginx Proxy Manager 后即可正式对外服务。

### 12.1 服务器信息

| 项目 | 值 |
|------|-----|
| 云服务商 | 阿里云 |
| 实例 ID | `i-bp16gxvgsif3mehs8mja` |
| 公网 IP | `121.40.151.3` |
| 内网 IP | `172.17.9.104` |
| 地域 | 杭州 (`cn-hangzhou`) |
| 操作系统 | Alibaba Cloud Linux 3.2104 LTS 64 位 |
| SSH 用户名 | `root` |
| SSH 私钥路径（本机） | `/Users/zhaoweiran/.ssh/trailbox-ecs` |
| 部署目录 | `/opt/trailbox` |
| 后端服务 | `trailbox.service`（systemd） |
| 反向代理 | Nginx Proxy Manager（Docker，`nginx-app`） |
| NPM 管理后台 | `http://121.40.151.3:5003` |

> ⚠️ 安全提示：`/Users/zhaoweiran/.ssh/trailbox-ecs` 是 SSH 私钥，仅限本机 Agent 使用，**不要上传到代码仓库或发送给他人**。

### 12.2 SSH 登录命令

```bash
ssh -i /Users/zhaoweiran/.ssh/trailbox-ecs root@121.40.151.3
```

### 12.3 更新部署代码

```bash
# 1. 进入本地项目
cd /Users/zhaoweiran/projects/TrailBox

# 2. 打包 api 和 web（排除不需要同步的目录）
tar czf /tmp/trailbox-api-deploy.tar.gz \
  --exclude='.venv' --exclude='__pycache__' --exclude='.cache' \
  --exclude='.env' --exclude='data' --exclude='uploads' \
  -C api .

tar czf /tmp/trailbox-web-deploy.tar.gz \
  --exclude='.cache' -C web .

# 3. 上传到服务器
scp -i /Users/zhaoweiran/.ssh/trailbox-ecs \
  /tmp/trailbox-api-deploy.tar.gz root@121.40.151.3:/tmp/

scp -i /Users/zhaoweiran/.ssh/trailbox-ecs \
  /tmp/trailbox-web-deploy.tar.gz root@121.40.151.3:/tmp/

# 4. 在服务器上解压并重启服务
ssh -i /Users/zhaoweiran/.ssh/trailbox-ecs root@121.40.151.3 "
  rm -rf /opt/trailbox/api/* /opt/trailbox/web/*
  tar xzf /tmp/trailbox-api-deploy.tar.gz -C /opt/trailbox/api
  tar xzf /tmp/trailbox-web-deploy.tar.gz -C /opt/trailbox/web
  systemctl restart trailbox.service
"
```

### 12.4 重启后端服务

```bash
ssh -i /Users/zhaoweiran/.ssh/trailbox-ecs root@121.40.151.3 \
  "systemctl restart trailbox.service && systemctl status trailbox.service --no-pager"
```

### 12.5 ICP 备案完成后的 Nginx Proxy Manager 配置

备案通过后，登录 Nginx Proxy Manager 管理后台：

```text
http://121.40.151.3:5003
```

添加一个 Proxy Host：

| 配置项 | 值 |
|--------|-----|
| Domain Names | `runfast.fun` |
| Scheme | `http` |
| Forward Hostname / IP | `172.17.9.104` 或 `localhost` |
| Forward Port | `8000` |
| Block Common Exploits | 可选 |
| Cache Assets | 可选 |
| SSL Certificate | 在 SSL 标签页申请 Let's Encrypt |
| Force SSL | 建议开启 |
| HTTP/2 Support | 建议开启 |

保存后等待证书申请完成，即可通过 `https://runfast.fun` 访问。

### 12.6 部署后验证清单

```bash
# 1. 验证 AASA 文件（iOS Universal Link 必需）
curl -s https://runfast.fun/.well-known/apple-app-site-association

# 2. 验证健康检查
curl -s https://runfast.fun/health

# 3. 验证分享落地页
curl -s https://runfast.fun/r/{某条公开路线ID} | head -20
```

### 12.7 已知部署限制

- **ICP 备案未完成前**，公网 `http://runfast.fun` 和 `https://runfast.fun` 都会被阿里云拦截，无法访问。
- 备案期间如需测试，可使用：
  - 本地开发环境：`http://localhost:8000`
  - 局域网 IP + iOS Launch Argument
  - 内网穿透工具（如 `localtunnel`、`ngrok`）临时暴露服务

---

## 13. 联系方式与外部链接

- 后端生产地址：`https://runfast.fun`
- 隐私政策：`https://runfast.fun/privacy.html`
- 支持邮箱：`zhaowr93@foxmail.com`
- Deep Link 域名：`https://runfast.fun/r/{id}`
- 生产服务器：阿里云 ECS `121.40.151.3`

---

## 14. 当前会话上下文（2026-06-23）

> 本小节记录当前正在进行、尚未完成的工作，供新打开的 Agent 会话快速接手。

### 进行中的任务

为 App Store 上架准备可访问的隐私政策页面。

### 已完成

1. 生成隐私政策 HTML：`/Users/zhaoweiran/projects/TrailBox-iOS/privacy.html`
2. 安装 GitHub CLI：`~/.local/bin/gh`（版本 2.95.0）

### 待完成

1. 使用 GitHub CLI 创建公开仓库 `trailbox-privacy`
2. 上传 `privacy.html` 到该仓库
3. 开启 GitHub Pages（source: main / root）
4. 获取 Pages 链接，例如：
   `https://<GitHub用户名>.github.io/trailbox-privacy/privacy.html`
5. 更新 `TrailBox/AppConfiguration.swift` 中的 `privacyPolicyURL`
6. 更新本 AGENTS.md 中相关的隐私政策 URL 引用
7. 构建验证项目是否仍能编译通过

### 阻塞点

- ✅ 已解决：已通过 Personal Access Token 完成 `gh auth login`，当前登录用户为 `weiran93`，可直接继续创建 `trailbox-privacy` 仓库。

### 相关文件

- `TrailBox/AppConfiguration.swift`（需更新 `privacyPolicyURL`）
- `/Users/zhaoweiran/projects/TrailBox-iOS/privacy.html`（已生成的隐私政策页面）

---

## 15. 文档维护说明

修改以下内容时，请同步更新本文件：

1. 新增/删除源码文件或目标
2. 新增第三方依赖
3. 新增敏感权限
4. 修改 API Base URL 或后端域名
5. 修改 Bundle ID、版本号、签名配置
6. 引入新的架构模式或状态管理方式
7. 发现新的构建阻塞或已知问题

---

*本文档由 Agent 于 2026-06-22 根据项目实际文件生成。若发现与代码不一致，以代码为准，并请及时更新本文档。*
