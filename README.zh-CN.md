<img src="Resources/QuotaView-ICON.png" alt="QuotaView 图标" width="200">

[English](README.md) | [**简体中文**](README.zh-CN.md)

# QuotaView

QuotaView 是一款原生 macOS 菜单栏应用，用一个界面集中展示 AI 服务的额度、用量、余额和重置时间。0.1.3 版本首先支持读取本机已登录的 Codex 账户，后续计划适配更多 AI 服务。

QuotaView 不会抓取网页，也不会读取、复制或保存 `~/.codex` 中的登录凭据。它会启动本地 `codex app-server` 进程，并通过其官方 JSON-RPC 接口读取账户数据。

## 下载

前往 [GitHub Releases](https://github.com/Duoasa/QuotaView/releases) 下载 `QuotaView-v0.1.3.zip`，解压后打开 `QuotaView.app`。

Universal 应用支持 macOS 14 或更高版本，同时兼容 Apple 芯片和 Intel Mac。v0.1.3 使用 Apple Development 证书签名，但尚未完成公证。如果 macOS 首次启动时拦截应用，请在 Finder 中右键点击 `QuotaView.app`，然后选择**打开**。

## 功能

- 显示当前 AI 服务是否可用、接近额度上限或额度已用尽。
- 显示当前周期内已用和剩余额度百分比。
- 显示距离下次额度重置的倒计时。
- 分别展示套餐额度和额外 Credits 余额。
- 将可用的额度重置次数显示为独立操作。
- 提供额度重置详情、风险确认和最终确认流程。
- 额度重置保持演示模式，不会调用真实的消费接口。
- 提供磨砂和清透两种原生玻璃效果，并自动适配浅色与深色模式；macOS 14–15 使用 Material 兼容方案。
- 在整个界面中使用 QuotaView 的蓝紫色视觉风格。
- 可自定义菜单栏标签和弹窗中显示的数据。
- 提供原生设置窗口，可跟随系统或固定使用浅色、深色外观。
- 支持跟随系统或固定使用简体中文、英文界面。
- 显示近期每日和累计 Token 用量。
- 每 60 秒自动刷新，也支持手动刷新。
- 可从 ChatGPT、Homebrew、自定义路径或当前 `PATH` 中查找 Codex。
- 妥善处理离线、未安装和 App Server 错误状态。

从 Finder 启动后的首次账户请求可能需要 20–30 秒。QuotaView 为冷启动预留了 45 秒响应时间，后续刷新通常会快很多。

## 隐私

QuotaView 只会在自己的 macOS 偏好设置域中保存最近一次成功刷新时间、可用状态、简短错误摘要和显示偏好。它不会保存 Token 或完整的账户响应。

诊断偏好设置：

```bash
defaults read com.quotaview.menubar
```

## 系统要求

- macOS 14 或更高版本
- Swift 6 或 Xcode 16+
- 已安装并登录 ChatGPT/Codex

QuotaView 会按以下顺序查找 Codex 可执行文件：

1. `CODEX_EXECUTABLE`
2. `/Applications/ChatGPT.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. 当前 `PATH`

## 验证

运行单元测试：

```bash
swift test
```

运行只读数据探针：

```bash
swift run QuotaViewProbe
```

探针会输出套餐、额度百分比、重置时间、Credits 余额和累计 Token 用量，不会输出登录凭据。

## 构建应用

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/QuotaView.app
```

构建脚本会创建包含完整资源目录的 Universal Xcode Release 构建：

```text
dist/QuotaView.app
dist/QuotaView-v0.1.3.zip
```

在没有额外参数时，脚本会优先使用已安装的 Developer ID Application 身份，其次使用 Apple Development 身份，最后使用带 Hardened Runtime 的 ad-hoc 签名。若要明确指定签名身份：

```bash
CODESIGN_IDENTITY="Apple Development: Name (ID)" ./scripts/build-app.sh
```

公开分发时，请使用 Developer ID Application 身份和已有的 `notarytool` 钥匙串配置：

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="QuotaView-notary" \
./scripts/build-app.sh
```

带版本号的 ZIP 会保留已签名的 macOS 应用包，可直接用于 GitHub Releases。Apple Development 签名仅适合开发和测试；公开分发应使用 Developer ID 签名和 Apple 公证。

## 开发运行

```bash
swift run QuotaView
```

QuotaView 只会出现在 macOS 菜单栏中，不会显示 Dock 图标。

## Xcode

打开原生 Xcode 项目，选择共享的 `QuotaView` Scheme 和 **My Mac**，然后运行或测试：

```bash
open QuotaView.xcodeproj
```

项目包含三个 Target：

- `QuotaView`：菜单栏应用
- `QuotaViewCore`：可复用的账户模型和 App Server 通信层
- `QuotaViewTests`：核心模型与进程通信测试

应用 Target 已关闭 App Sandbox，因为它需要启动本机安装的 `codex app-server`。创建正式签名版本前，请在 **Signing & Capabilities** 中选择 Apple Developer Team。

## 数据协议

初始化后，客户端会发送以下请求：

```text
initialize
initialized
account/rateLimits/read
account/usage/read
```

| 界面数据 | App Server 字段 |
| --- | --- |
| 可用状态 | `rateLimitReachedType`、`spendControlReached`、`primary.usedPercent` |
| 已用额度 | `primary.usedPercent` |
| 剩余额度 | `100 - primary.usedPercent` |
| 重置时间 | `primary.resetsAt` |
| Credits | `credits.balance`、`credits.unlimited` |
| 重置次数 | `rateLimitResetCredits.availableCount` |
| Token | `summary.lifetimeTokens`、`dailyUsageBuckets` |

Credits 与套餐剩余额度是两个独立概念，界面不会将它们合并。

0.1.3 版本已经实现额度重置交互和安全确认，但不会发送 `account/rateLimitResetCredit/consume` 请求。未来启用真实额度重置前，应加入幂等键、明确的结果处理和协议兼容性测试。

## 项目结构

```text
Sources/
├── QuotaView/              # SwiftUI 菜单栏界面与状态
├── QuotaViewCore/          # 服务客户端、可执行文件查找与数据模型
└── QuotaViewProbe/         # 只读命令行探针
Tests/
└── QuotaViewCoreTests/     # 模型映射与进程通信测试
```

## 路线图

1. 添加活跃任务状态和实时通知。
2. 使用 `ServiceManagement` 添加开机启动。
3. 添加历史趋势和额度提醒。
4. 添加基于 App Group 的 WidgetKit 扩展。
5. 适配更多 AI 服务。
6. 添加 Developer ID 签名、公证和自动更新。

App Server Schema 取决于本机安装的 Codex 版本。Release CI 应运行 `codex app-server generate-json-schema` 并包含协议兼容性测试。
