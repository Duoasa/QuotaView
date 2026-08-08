# QuotaView 1.0.0 App Store 元数据草案

状态：`Draft / Do Not Submit`

本文件是 QuotaView `1.0.0 (Build 4)` 的 App Store Connect 元数据工作稿。
文案必须在第三方内容权利结论、支持页和隐私政策公开、付费 App 定价、固定
插件 Release、截图及产品所有者验收完成后再次核对。

## App 级信息

| 字段 | 候选值 | 状态 |
|---|---|---|
| App Name | `QuotaView` | 候选，9/30 字符 |
| Bundle ID | `com.quotaview.menubar` | 已固定 |
| SKU | `quotaview-macos-1` | 创建 App Record 前最终确认，创建后不可改 |
| Primary Language | `English (U.S.)` | 建议值；创建记录前由产品所有者确认 |
| Primary Category | `Developer Tools` | 与包内 `public.app-category.developer-tools` 一致 |
| Secondary Category | `Utilities` | 可选候选 |
| Distribution Model | `Paid Upfront` | 全部内置功能随 App 下载提供，无 IAP |
| Base Price | `USD 4.99` | 待在 Pricing and Availability 配置并复核各地区价格 |
| Content Rights | 展示用户通过官方 Codex 获得的脱敏用量与活动数据 | 必须如实回答；如 Apple 要求，应提供架构、来源和相应权利说明，OpenAI Support Case `12874203` 不构成商业展示授权 |
| Age Rating | 问卷按实际功能全部如实回答；预计 `4+` | 无内置浏览器、UGC、社交、聊天、广告或成人内容；最终以 App Store Connect 问卷计算为准 |
| Privacy Policy URL | `https://github.com/Duoasa/QuotaView/blob/main/PRIVACY.md` | 待补齐支持邮箱并公开 |
| App Uses Non-Exempt Encryption | `No` | App 本身不联网，仅使用 Apple 系统安全书签与系统加密能力；包内声明 `ITSAppUsesNonExemptEncryption = NO` |
| Copyright | `[CONFIRM 2026 LEGAL OWNER]` | 待产品所有者确认法定权利人 |
| DSA / trader status | `[COMPLETE IN ACCOUNT]` | 由 Account Holder 按实际经营身份完成，不能由代码推断 |

## 英文（English U.S.）

### Name

```text
QuotaView
```

### Subtitle

```text
AI Usage at a Glance
```

### Promotional Text

```text
Track your Codex quota from the menu bar and Widget, and follow live task status with the included Codex Island.
```

### Description

```text
QuotaView is a lightweight, native macOS menu-bar companion for viewing the signed-in user's own OpenAI Codex usage.

AT A GLANCE

• View current plan, period usage, remaining quota, and reset countdowns.
• Keep Credits and recent or lifetime token usage close at hand.
• Add native Small and Medium WidgetKit widgets to the desktop.
• Refresh from a compact menu panel without opening a browser dashboard.

INCLUDED CODEX ISLAND

Codex Island is included with the paid QuotaView download. There is no in-app purchase, subscription, or separate feature unlock.

Usage and Island activity require the public QuotaView for Codex plugin in the separately installed official Codex app. QuotaView does not download, install, update, or execute the plugin. The plugin writes only an allowlisted usage snapshot and bounded, sanitized lifecycle events to a folder selected by the user; QuotaView receives read-only access through the macOS system picker.

PRIVATE BY DESIGN

Sign-in remains in the official Codex app. QuotaView has no OpenAI OAuth client and receives no OpenAI credentials. The official codex app-server owns authentication and network access; the companion plugin keeps raw responses in memory and writes only allowlisted local fields. QuotaView has no network-client entitlement, analytics, advertising, tracking, or developer-operated account server.

Requires macOS 14 or later. An existing eligible OpenAI account is required for quota data. QuotaView is an independent third-party app and is not affiliated with or endorsed by OpenAI.
```

### Keywords

```text
usage,quota,credits,menu bar,widget,monitor,developer,status,tracker
```

### Support URL

```text
https://github.com/Duoasa/QuotaView/blob/main/SUPPORT.md
```

### Marketing URL

```text
https://github.com/Duoasa/QuotaView
```

## 简体中文（Simplified Chinese）

### 名称

```text
QuotaView
```

### 副标题

```text
AI 用量与实时任务状态
```

### 宣传文本

```text
在菜单栏和小组件中查看 Codex 额度，并通过随 App 提供的 Codex 灵动岛实时了解任务状态。
```

### 描述

```text
QuotaView 是一款轻量、原生的 macOS 菜单栏应用，用于查看当前登录用户自己的 OpenAI Codex 用量。

一眼掌握

• 查看当前套餐、本周期用量、剩余额度和重置倒计时；
• 随时了解 Credits、近期和累计 Token 用量；
• 在桌面添加原生 WidgetKit 小号或中号小组件；
• 通过紧凑的菜单面板刷新数据，无需打开网页控制台。

内置的 CODEX 灵动岛

Codex 灵动岛已包含在付费下载的 QuotaView 中，不提供 App 内购买、订阅或单独功能解锁。

用量和灵动岛活动需要在另行安装的官方 Codex 应用中启用公开的 QuotaView for Codex 插件。QuotaView 不会下载、安装、更新或执行插件。插件只向用户选择的本地目录写入白名单用量快照及有界、脱敏的生命周期事件；QuotaView 通过 macOS 系统选择器取得只读权限。

隐私设计

登录始终在官方 Codex 应用中完成。QuotaView 没有自有 OpenAI OAuth，也不接收 OpenAI 凭证。官方 codex app-server 负责身份验证和联网；伴侣插件仅在内存中处理原始响应，并只写入白名单本地字段。QuotaView 没有网络客户端权限、分析、广告、跟踪或开发者运营的账号服务器。

需要 macOS 14 或更高版本。读取额度需要用户已有且符合条件的 OpenAI 账号。QuotaView 是独立第三方应用，与 OpenAI 不存在隶属或官方背书关系。
```

### 关键词

```text
使用量,额度监控,配额管理,菜单栏,桌面组件,开发工具,状态追踪
```

### 支持网址

```text
https://github.com/Duoasa/QuotaView/blob/main/SUPPORT.md
```

### 营销网址

```text
https://github.com/Duoasa/QuotaView
```

## 自动校验

运行 `scripts/check-appstore-metadata.sh` 会按 Apple 当前官方限制校验两种本地化
的名称 `2–30` 字符、副标题 `≤30` 字符、宣传文本 `≤170` 字符、描述
`≤4000` 字符和关键词 `≤100 UTF-8 bytes`，同时检查关键词长度/重复项、
HTTPS URL、本地化 URL 一致性、纯文本边界，以及 App Name / Bundle ID 与
`Configs/App.xcconfig` 的一致性。`--submission` 还会拒绝 Draft 状态和提交
占位符；该检查已经接入 `scripts/check-appstore-readiness.sh`。

当前草案自动测量结果：

| 本地化 | Name | Subtitle | Promotional | Description | Keywords |
|---|---:|---:|---:|---:|---:|
| English (U.S.) | `9 / 30 chars` | `20 / 30 chars` | `112 / 170 chars` | `1549 / 4000 chars` | `68 / 100 bytes` |
| 简体中文 | `9 / 30 chars` | `12 / 30 chars` | `52 / 170 chars` | `664 / 4000 chars` | `84 / 100 bytes` |

自动校验不能替代 App Store Connect 对最终粘贴内容的服务器端验证；任何最终
文案修改后必须重新运行，并在提交界面再次核对。

## 首版截图计划

截图是必填项，但必须由产品所有者在真实 Release 构建中完成视觉验收后制作，
当前不自动生成或伪造截图。建议中英文各准备同一组真实画面：

1. 菜单栏主面板：有效额度、Credits 和重置倒计时；
2. Small / Medium Widget：桌面中的真实系统容器；
3. 连接与灵动岛设置：官方 Codex 登录、插件、只读目录边界和独立显示开关；
4. Codex 灵动岛：收到真实插件事件后的运行状态；
5. 灵动岛设置：插件安装与只读连接说明。

不得在截图中出现测试账号、Token、邮箱、完整路径、提示词、源代码、调试标记
或虚构数据。截图和产品页必须明确 QuotaView 为一次性付费下载，所有内置功能
均已包含。

## App Review 信息

- Contact name / email / phone：`[COMPLETE IN APP STORE CONNECT]`；
- Sign-in required：说明审核人员需在另行安装的官方 Codex 中登录；如果
  Apple 要求测试凭证，只能通过 App Store Connect 安全字段提供，仓库和
  Review Notes 不得出现凭证；
- Notes：使用
  [APP_STORE_REVIEW_NOTES_DRAFT.md](APP_STORE_REVIEW_NOTES_DRAFT.md)，控制在
  Apple 当前 `4000 bytes` 限制内；
- Pricing：在 Pricing and Availability 中将美国基准价格设置为 `USD 4.99`；
- Version release：首版建议选择“审核通过后手动发布”，由产品所有者最终确认。

## 提交前检查

- [ ] 确认 App Name、SKU、Primary Language、Category 和版权主体；
- [ ] 完成 Content Rights 与品牌/第三方数据展示权利评估，并准备 Apple
  要求时可提供的来源和架构说明；
- [ ] `SUPPORT.md` 与 `PRIVACY.md` 补齐同一受监控邮箱并公开可访问；
- [x] 当前草案的英文、简体中文字段长度和 UTF-8 bytes 已通过本地自动校验；
- [ ] 最终粘贴内容在 App Store Connect 再次核验；
- [ ] App Privacy 答案发布，年龄分级和 Content Rights 问卷完成；
- [ ] Paid Apps Agreement 生效，`USD 4.99` 基准价格和各地区价格完成；
- [x] 固定 `v1.0.0-preview.7` 插件 Pre-release、匿名 clone、隔离安装和公开
  资产回下载复验完成；
- [ ] Review Notes 无占位符，官方 Codex + 固定插件 Release 能从干净 Mac
  完整复现；
- [ ] 真实 Release 构建截图由产品所有者审核，不使用自动截图或 Debug 数据；
- [ ] 最终 Archive 重新生成、上传并选择正确的 `1.0.0 (Build 4)` 构建。

## Apple 官方依据

- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [App privacy](https://developer.apple.com/help/app-store-connect/reference/app-privacy/)
- [Age ratings](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
