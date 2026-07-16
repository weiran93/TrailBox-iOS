# TrailBox iOS 测试指南

> 更新时间：2026-07-16

## 测试分层

- `TrailBoxTests`：API 日期/状态/解码、匿名观测同意与队列、Deep Link、收藏乐观更新。
- `TrailBoxUITests`：游客登录拦截、缓存登录态过期、匿名观测同意/拒绝/关闭、探索路线到收藏、一键出发与分享卡生成的核心冒烟流程。
- 关联后端 `/Users/zhaoweiran/projects/TrailBox/api/tests`：API schema、持久化、权限、遥测汇总和既有业务回归。

## 常用命令

完整 iOS 测试：

```bash
cd /Users/zhaoweiran/projects/TrailBox-iOS
xcodebuild test -project TrailBox.xcodeproj \
  -scheme TrailBox \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

只跑单元测试或 UI 测试：

```bash
xcodebuild test -project TrailBox.xcodeproj -scheme TrailBox \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TrailBoxTests CODE_SIGNING_ALLOWED=NO

xcodebuild test -project TrailBox.xcodeproj -scheme TrailBox \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TrailBoxUITests CODE_SIGNING_ALLOWED=NO
```

后端测试：

```bash
cd /Users/zhaoweiran/projects/TrailBox/api
source .venv/bin/activate
python -m pytest -q
```

## 持续集成

- iOS GitHub Actions 配置在 `.github/workflows/ci.yml`，对 `main` 的 push、pull request 和手动触发运行。
- CI 使用 `macos-26`、Xcode 26.4 和 Runner 上最新可用的 iPhone 17 模拟器，顺序执行完整 XCTest 与 Release 模拟器构建。
- 测试或构建失败时，Actions 运行详情会保留 7 天的 `.xcresult` 和 `xcodebuild` 日志。
- 关联后端仓库通过 `.github/workflows/api-ci.yml` 在 Ubuntu / Python 3.12 上执行 `python -m pytest -q`。
- CI 不使用生产账号、签名、Token 或 App Store Connect 密钥；发布归档和真机 MetricKit 验证仍按发布流程单独执行。

## Fixture 与约束

- UI 测试通过 `-trailboxUITestMode` 启用 `URLProtocol` 固定响应；测试支持代码必须保持在 `#if DEBUG` 内。
- `-trailboxUITestAuthenticated` 注入固定测试用户；`-trailboxUITestExpiredSession` 让收藏启动请求返回 401；`-trailboxUITestConsent unknown|enabled|disabled` 控制同意状态；`-trailboxUITestReset` 清理测试遥测状态。
- Release 构建不得包含测试网络拦截行为，不得依赖生产账号或真实生产数据。
- API/遥测测试不得断言或记录真实 Token、账号、轨迹 ID、坐标、路线名称或用户输入。

## 运行时机

- 修改模型、APIClient、状态管理或导航：至少运行 `TrailBoxTests` 和模拟器构建。
- 修改登录拦截、根导航、探索/详情/收藏/出发或隐私设置：运行完整 iOS 测试。
- 修改后端接口、模型或数据存储：运行后端全量测试；涉及 iOS wire shape 时再运行完整 iOS 测试。
- App Store 提交前：完整 iOS 测试、后端测试、Release archive，并在真机验证 MetricKit 订阅和关闭开关。真实 MetricKit 报告可能延迟，不作为自动化测试阻塞项。
- PR 或 push 的 CI 失败时不得进入发布流程；先从 Actions 的失败 step 和诊断 artifact 定位并修复。
