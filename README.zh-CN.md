<p align="center">
  <img src="Resources/QuotaView-ICON.png" alt="QuotaView 图标" width="160">
</p>

<h1 align="center">QuotaView</h1>

<p align="center">
  简洁、轻量地在 macOS 菜单栏查看 Codex 额度、Credits、Token 用量和重置时间。
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/Duoasa/QuotaView?display_name=tag&sort=semver"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI 状态" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/latest"><strong>下载最新版本</strong></a>
  ·
  <a href="#隐私设计">隐私说明</a>
  ·
  <a href="#构建与测试">从源码构建</a>
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

![QuotaView 应用预览](Resources/QuotaView-Preview.jpg)

QuotaView 是一款简洁、轻量的原生 macOS 菜单栏应用，使用本机已经登录的 Codex 账户。它以克制、无干扰的方式，让你在额度打断工作之前及时看到关键信息；不抓取网页，也不读取 `~/.codex` 中的登录凭据。

## 为什么选择 QuotaView

| | |
| --- | --- |
| **一眼掌握** | 无需离开当前应用，即可查看已用与剩余额度、重置倒计时、Credits 和可用状态。 |
| **本地连接** | 通过 JSON-RPC 与本机启动的 `codex app-server` 进程通信。 |
| **简洁设计** | 专注必要的额度信息，以紧凑、无冗余的界面降低干扰。 |
| **轻量原生** | 使用 SwiftUI 和 AppKit 原生构建，不包含嵌入式浏览器运行层。 |
| **按需显示** | 可以选择菜单栏显示的数值，以及面板中需要出现的内容区域。 |

## 快速开始

1. 确认已经安装并登录 ChatGPT 或 Codex。
2. 前往 [GitHub Releases](https://github.com/Duoasa/QuotaView/releases/latest) 下载 `QuotaView-v0.1.5.zip`。
3. 解压后打开 `QuotaView.app`。

> [!IMPORTANT]
> 当前 v0.1.5 Build 6 使用 Apple Development 证书签名，但尚未完成公证。如果 macOS 首次启动时拦截应用，请在 Finder 中右键点击 `QuotaView.app`，然后选择**打开**。Developer ID 签名与公证已列入路线图。

Universal 应用支持 macOS 14 或更高版本，同时兼容 Apple 芯片和 Intel Mac。从 Finder 启动后的首次账户请求可能需要 20–30 秒，后续刷新通常会快很多。

## 展示的数据

- 当前套餐和服务可用状态
- 本周已用额度和剩余百分比
- 距离下次额度重置的倒计时
- 分别展示套餐额度和额外 Credits
- 可用的额度重置次数
- 近期每日和累计 Token 用量
- 接近上限、额度耗尽、离线和 App Server 错误状态

## 原生使用体验

- 紧凑的状态栏入口和可动态调整高度的菜单面板
- 每 60 秒自动刷新，同时支持手动刷新
- 可配置菜单栏数值和六个面板内容区域
- 提供磨砂和清透玻璃效果，并适配浅色与深色模式
- macOS 26 使用原生 Liquid Glass，macOS 14–15 使用 Material 兼容方案
- 支持跟随系统或固定使用浅色、深色外观
- 支持简体中文和英文界面
- 原生设置窗口包含菜单栏、面板内容、外观、语言和通用选项

## 隐私设计

QuotaView **不会**：

- 抓取账户网页；
- 读取、复制或保存 `~/.codex` 中的登录凭据；
- 保存完整账户响应或身份认证 Token。

QuotaView 会启动本地 `codex app-server` 进程，并通过 JSON-RPC 请求账户数据。它只会在自己的 macOS 偏好设置域中保存最近一次成功刷新时间、可用状态、简短错误摘要和显示偏好。

本地诊断命令：

```bash
defaults read com.quotaview.menubar
```

应用 Target 已关闭 App Sandbox，因为它需要启动本机安装的 `codex app-server`。

## 系统要求

- macOS 14 或更高版本
- 已安装并登录 ChatGPT/Codex
- 仅在从源码构建时需要 Swift 6 或 Xcode 16+

QuotaView 会按以下顺序查找 Codex 可执行文件：

1. `CODEX_EXECUTABLE`
2. `/Applications/ChatGPT.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. 当前 `PATH`

## 当前限制

- 0.1.5 版本仅支持 Codex，后续计划适配更多 AI 服务。
- 额度重置界面仍是安全演示，不会调用 `account/rateLimitResetCredit/consume`。
- App Server Schema 可能随本机安装的 Codex 版本变化。
- 当前提供下载的构建尚未完成公证。

## 构建与测试

克隆仓库并运行单元测试：

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
```

运行只读数据探针：

```bash
swift run QuotaViewProbe
```

探针会输出套餐、额度百分比、重置时间、Credits 余额和累计 Token 用量，不会输出登录凭据。

在开发环境中运行应用：

```bash
swift run QuotaView
```

或者创建 Universal Release 应用和 ZIP：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/QuotaView.app
```

构建脚本会优先使用 Developer ID Application 身份，其次使用 Apple Development 身份，最后使用带 Hardened Runtime 的 ad-hoc 签名。创建经过公证的公开构建：

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="QuotaView-notary" \
./scripts/build-app.sh
```

使用 Xcode 时，请打开 `QuotaView.xcodeproj`，选择共享的 **QuotaView** Scheme 和 **My Mac**，然后运行或测试。

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

## 项目结构

```text
Sources/
├── QuotaView/              # SwiftUI 界面、设置与 AppKit 菜单面板
├── QuotaViewCore/          # 账户模型和 App Server 通信层
└── QuotaViewProbe/         # 只读命令行探针
Resources/
├── Assets.xcassets/        # 应用、菜单栏和界面资源
└── Fonts/                  # 内置 Asta Sans 字体文件
Tests/
└── QuotaViewCoreTests/     # 模型映射和进程通信测试
```

## 路线图

- [ ] 活跃任务状态和实时通知
- [ ] 使用 `ServiceManagement` 实现登录时启动
- [ ] 历史趋势和额度提醒
- [ ] 基于 App Group 的 WidgetKit 扩展
- [ ] 适配更多 AI 服务
- [ ] Developer ID 签名、公证和自动更新

## 反馈与贡献

欢迎提交 Bug、兼容性报告和目标明确的功能建议。请先使用 [Issue 模板](https://github.com/Duoasa/QuotaView/issues/new/choose)，准备代码改动前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

请勿在 Issue 中包含身份认证 Token、登录凭据或未经脱敏的 `~/.codex` 文件。
