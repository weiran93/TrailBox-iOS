# 小野box App Store 上架文案

> 本文档汇总了在 App Store Connect 提交「小野box」所需的所有文案与元数据。
> 适用于中国区（简体中文）商店，同时提供英文版本供其他区参考。

---

## 1. 基础信息

| 字段 | 中文区 | 英文区（供参考） |
|---|---|---|
| App 名称 | 小野box | TrailBox |
| 副标题 | 越野跑·徒步轨迹收藏与分享 | Track Collection & Sharing |
| 主要语言 | 简体中文 | English |
| 套装 ID | `com.trailbox.ios` | `com.trailbox.ios` |
| 类别 | 健康健美 / 导航（建议） | Health & Fitness / Navigation |
| 年龄分级 | 17+（因用户生成内容与举报功能） | 17+ |

### 副标题说明
- 中文副标题：`越野跑·徒步轨迹收藏与分享`（16 个字符，≤ 30 字符限制）
- 英文副标题：`Track Collection & Sharing`（28 个字符，≤ 30 字符限制）

---

## 2. 关键词（Keywords）

> App Store 关键词每个语言版本限 100 个字符，使用英文逗号或中文逗号分隔，不要空格。

### 中文区关键词（96 字符）
```
越野跑,徒步,轨迹,GPX,FIT,路线,户外,跑步,运动,AI分析,分享卡,地图,登山,骑行
```

### 英文区关键词（约 98 字符）
```
trail running,hiking,GPX,fit,track,route,outdoor,running,sports,AI analysis,share card,map
```

---

## 3. App 描述（Description）

### 中文区

```
小野box 是一款面向越野跑、徒步和户外爱好者的轨迹收藏与分享工具。

在这里，你可以：
• 导入 .fit、.gpx、.kml 等多种格式的轨迹文件，集中管理你的每一次户外记录；
• 在「探索路线」中发现其他用户公开的优质路线，按城市、距离、标签快速筛选；
• 记录运动体感，通过 AI 生成个性化的运动分析与恢复建议；
• 一键生成精美分享卡，保存到相册或分享给好友；
• 下载 GPX 文件、导航至路线起点或终点，支持 Apple Maps、高德、百度、腾讯、Google Maps；
• 公开你的路线，与更多山友交流；也可随时删除、举报或屏蔽不合适的内容。

小野box 重视你的隐私：麦克风、语音识别与相册写入权限仅在必要时请求，详细的隐私政策请参见应用内链接。

无论你是城市跑者、山野徒步者还是百公里越野玩家，小野box 都希望成为你探索户外的可靠助手。

---
支持邮箱：zhaowr93@foxmail.com
隐私政策：https://weiran93.github.io/trailbox-privacy/privacy.html
```

### 英文区（供参考）

```
TrailBox is a track collection and sharing app built for trail runners, hikers, and outdoor enthusiasts.

With TrailBox you can:
• Import .fit, .gpx, and .kml files to manage all your outdoor activities in one place;
• Discover public routes shared by the community, filtered by city, distance, and tags;
• Record how you felt during a workout and get AI-powered analysis and recovery tips;
• Generate beautiful share cards and save them to your photo library;
• Download GPX files and navigate to the start or finish using Apple Maps, Gaode, Baidu, Tencent, or Google Maps;
• Share your own routes with the community, or delete, report, and block content as needed.

TrailBox respects your privacy: microphone, speech recognition, and photo-library access are requested only when needed.

Support: zhaowr93@foxmail.com
Privacy Policy: https://weiran93.github.io/trailbox-privacy/privacy.html
```

---

## 4. 宣传文本（Promotional Text）

### 中文
```
越野跑和徒步爱好者的轨迹收藏夹。导入、探索、分享你的每一条路线，让 AI 帮你总结运动体感。
```

### 英文
```
Your track collection for trail running and hiking. Import, explore, and share routes — and let AI summarize your workout feedback.
```

---

## 5. 新功能/更新说明（What's New）

> 首次提交可填写「首发版本」，后续更新按需修改。

### 中文
```
本次更新：
• 新增可选择开启的匿名使用与崩溃、性能诊断，帮助持续改进体验
• 优化登录过期处理，避免账号状态显示不一致
• 优化路线分享卡二维码说明和地图信息标签排版
• 提升路线、收藏、一键出发与分享流程的稳定性
```

### 英文
```
This update:
• Adds optional anonymous usage, crash, and performance diagnostics to help improve the app
• Improves expired-session handling so account state stays consistent
• Refines QR-code captions and map information labels on route share cards
• Improves reliability across routes, favorites, one-tap departure, and sharing
```

---

## 6. URL 信息

| 字段 | 链接 |
|---|---|
| 隐私政策 | `https://weiran93.github.io/trailbox-privacy/privacy.html` |
| 支持页面 | 建议与隐私政策共用，或后续补充独立支持页 |
| 营销页面 | 可选，可留空或使用项目仓库 `https://github.com/weiran93/TrailBox-iOS` |

---

## 7. App 审核信息（App Review Information）

> 以下信息需要开发者根据实际情况填写。

| 字段 | 建议值 / 占位符 |
|---|---|
| 姓名 | `[待填写：开发者姓名]` |
| 电话号码 | `[待填写：+86 1xx-xxxx-xxxx]` |
| 邮箱 | `zhaowr93@foxmail.com` |
| 演示账户 | `[待填写：测试账号 / 密码]` |
| 备注 | 见下方「审核备注」 |

### 审核备注（Review Notes）

```
小野box 是一款面向越野跑和徒步爱好者的轨迹管理应用。

主要功能说明：
1. 用户可导入本地 .fit / .gpx / .kml 文件，应用解析并展示路线、海拔、配速、心率等数据。
2. 用户可选择将路线公开至「探索路线」供其他用户浏览，也可保持私有。
3. 应用使用麦克风与语音识别权限，用于录制和转写用户的运动体感反馈，并调用后端 AI 接口生成分析建议；仅在用户主动点击录音按钮时访问麦克风，不会后台录音。
4. 相册写入权限用于保存生成的分享卡图片，应用不会读取相册内容。
5. 位置数据来自用户导入的轨迹文件，应用不会主动请求或持续收集实时位置。
6. 应用内置举报与屏蔽功能，用于社区内容管理。

如需测试账号，请使用上方提供的演示账户登录。
```

---

## 8. 截屏/视频说明

> 以下文案可用于 App Store 截屏上的文字叠加，每张不超过简短一句。

### 中文截屏文案
1. 导入你的每一条户外轨迹
2. 在探索中发现优质路线
3. AI 帮你总结运动体感
4. 一键生成精美分享卡
5. 轻松导航到起点或终点

### 英文截屏文案
1. Import your outdoor tracks
2. Discover routes from the community
3. AI analysis for your workout feedback
4. Generate share cards in one tap
5. Navigate to start or finish easily

---

## 9. 补充说明

- **年龄分级建议**：因应用包含用户生成内容（UGC）、举报/屏蔽机制以及 AI 生成内容，建议填写「17+」。
- **数据收集**：App Store Connect「App 隐私」除既有用户 ID、联系信息、健康与健身、轨迹文件中的位置、音频等声明外，0.1.7 需增加以下未关联用户、非 Tracking 数据：Device ID（随机匿名安装标识）、Product Interaction（固定功能开始/成功/失败/取消）、Crash Data、Performance Data、Other Diagnostic Data。用途选择 Analytics 与 App Functionality；明确不包含账号、轨迹 ID/坐标、路线名称、搜索词、用户输入或 Token。
- **登录要求**：应用支持游客浏览探索路线，但上传轨迹、AI 分析等功能需要注册/登录账号。

---

*本文档由 Agent 生成，提交前请人工核对所有占位符信息。*
