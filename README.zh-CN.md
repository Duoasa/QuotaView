<p align="center">
  <img src="Resources/QuotaView-ICON.png" alt="QuotaView 图标" width="160">
</p>

<h1 align="center">QuotaView</h1>

<p align="center">
  简洁、轻量地查看 Codex 额度与实时任务状态。
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1-build.2"><img alt="最新版本" src="https://img.shields.io/github/v/release/Duoasa/QuotaView?display_name=tag"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI 状态" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.3.1-build.2/QuotaView-v0.3.1-build.2.zip"><strong>下载 QuotaView v0.3.1 Build 2</strong></a>
  ·
  <a href="#隐私设计">隐私说明</a>
  ·
  <a href="#构建与测试">从源码构建</a>
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <img src="Resources/QuotaView-Preview.jpg" alt="QuotaView 深色外观预览" width="49%">
  <img src="Resources/QuotaView-Preview-Light.jpg" alt="QuotaView 浅色外观预览" width="49%">
</p>

QuotaView 是一款简洁、轻量的原生 macOS Codex 助手，使用本机已经登录的 Codex 账户。全新的 **Codex 灵动岛**会在菜单栏下方实时呈现任务状态，菜单面板和桌面小组件则让额度、Credits、Token 用量和重置时间保持触手可及；不抓取网页，也不读取 `~/.codex` 中的登录凭据。

## 为什么选择 QuotaView

| | |
| --- | --- |
| **Codex 灵动岛** | 通过实时 Metal 流体球查看思考、工具调用、权限确认、上下文压缩、子任务、完成与失败状态。 |
| **一眼掌握** | 无需离开当前应用，即可从菜单栏或原生桌面小组件查看已用与剩余额度、重置倒计时、Credits 和可用状态。 |
| **本地连接** | 通过 JSON-RPC 与本机启动的 `codex app-server` 进程通信。 |
| **简洁设计** | 专注必要的额度信息，以紧凑、无冗余的界面降低干扰。 |
| **轻量原生** | 使用 SwiftUI 和 AppKit 原生构建，不包含嵌入式浏览器运行层。 |
| **按需显示** | 可以选择菜单栏显示的数值，以及面板中需要出现的内容区域。 |

## 快速开始

1. 确认已经安装并登录 ChatGPT 或 Codex。
2. 前往 [v0.3.1 Build 2 Release](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1-build.2) 下载 `QuotaView-v0.3.1-build.2.zip`。
3. 解压后打开 `QuotaView.app`。

> [!IMPORTANT]
> v0.3.1 Build 2 已使用 Developer ID 证书签名、通过 Apple 公证并完成 Staple，
> 可在解压后正常打开，不再需要旧版未签名构建所使用的 Finder 右键打开
> 方式。

Universal 应用支持 macOS 14 或更高版本，同时兼容 Apple 芯片和 Intel Mac。从 Finder 启动后的首次账户请求可能需要 20–30 秒，后续刷新通常会快很多。

## 展示的数据

- 当前套餐和服务可用状态
- 本周期已用额度和剩余百分比
- 距离下次额度重置的倒计时
- 分别展示套餐额度和额外 Credits
- 可用的额度重置次数
- 近期每日和累计 Token 用量
- 接近上限、额度耗尽、离线和 App Server 错误状态

## 原生使用体验

- Codex 灵动岛提供最大态、紧凑态、实时 Metal 流体球、状态化颜色与动效，
  并在任务完成后自动收起
- 紧凑的状态栏入口和可动态调整高度的菜单面板
- 每 60 秒自动刷新，同时支持手动刷新
- 可配置菜单栏数值和六个面板内容区域
- 提供磨砂和清透玻璃效果，并适配浅色与深色模式
- macOS 26 使用原生 Liquid Glass，macOS 14–15 使用 Material 兼容方案
- 支持跟随系统或固定使用浅色、深色外观
- 支持简体中文和英文界面
- 原生设置窗口包含菜单栏、面板内容、外观、语言和通用选项
- 提供小号与中号两种原生 WidgetKit 小组件

## 0.3.2 Preview 1：Codex 灵动岛多任务

> [!NOTE]
> 0.3.2 Preview 1 是用于验证 Codex 灵动岛多任务体验的抢先预览版。
> v0.3.1 Build 2 继续作为推荐稳定版和默认下载版本。

当前版本已经在一个固定灵动岛内基本实现完整的多任务工作流：

- 同时跟踪多个 Codex 会话，并分别维护状态、生命周期、完成与清理；
- 新增三行任务列表、更长任务列表的连续滑动窗口、任务总数和紧凑态多任务
  摘要；
- 通过稳定的优先级仲裁选择主任务，避免普通后台事件无必要地抢占灵动岛；
- 新增可选的“跟随当前 Codex 任务”，只对辅助功能标题进行有界、只读匹配，
  无法高置信度匹配时自动降级；
- 保留现有实时 Metal 状态界面、原生玻璃切换、最大态/紧凑态、减少动态效果
  和辅助功能操作。

预览版已知不足：

- 从任务事件到灵动岛显示的响应速度仍可能受 Hook 传递、本机调度和当前
  Codex 任务状态影响，部分场景会感到延迟；
- 当前任务跟随基于标题匹配；当标题尚未解析、重复、快速变化或 Codex 界面
  发生调整时，可能出现跟随滞后或未命中；
- 任务切换、长标题跑马灯以及最大态/紧凑态切换节奏仍需要继续优化体验与
  性能；
- 本版本用于预览验证。如果更重视稳定体验，请继续使用 v0.3.1 Build 2。

## 0.3.1 Build 2 小组件热修复

- 使用 macOS 直接分发所需的团队前缀共享 App Group，恢复已公证下载版的
  小号与中号 Widget 数据。
- 将 App、小组件、Tooltip 和辅助功能文案中的“本周剩余”统一改为“本周期
  剩余”，兼容 Codex 的可变额度周期。
- 新增发布打包门禁，避免不兼容的 App Group 配置进入公证分发包。

## 0.3.1 最大更新：Codex 灵动岛

v0.3.1 带来 QuotaView 至今最大的一次更新：原生、实时的
**Codex 灵动岛**。

<p align="center">
  <img src="Resources/QuotaView-Codex-Island.gif" alt="QuotaView Codex 灵动岛状态动画演示" width="100%">
</p>

- 通过实时 Metal 流体球展示思考、工作、工具调用、权限确认、上下文压缩、
  子任务、完成与失败，并为不同状态提供独立的颜色和动效。
- 新活动到来时立即展开；任务完成 20 秒后进入紧凑态，完成两分钟后自动
  隐藏。
- 新增新手向连接流程：自动检测 Hooks 支持、安装和更新固定路径 Helper、
  保留现有 Hooks，并打开 Codex 官方信任审查页。
- 只有在 Codex 完成重启并收到受信任 Hook 的第一条真实消息后，才会显示
  连接成功。
- 不转发提示词、命令、参数、工具输出或会话记录路径，只在本机传递最小、
  脱敏的生命周期元数据。
- 继续包含 v0.2.1 引入的小号与中号原生 WidgetKit 小组件。

## 隐私设计

QuotaView **不会**：

- 抓取账户网页；
- 读取、复制或保存 `~/.codex` 中的登录凭据；
- 保存完整账户响应或身份认证 Token。

QuotaView 会启动本地 `codex app-server` 进程，并通过 JSON-RPC 请求账户数据。它只会在自己的 macOS 偏好设置域中保存最近一次成功刷新时间、可用状态、简短错误摘要和显示偏好。

0.3.1 默认只读，不包含真实账户操作执行器；额度重置仍是本地 Demo。
底层只为未来“用户单独授权后的官方账户操作”预留独立边界，数据刷新不能
隐式触发任何写操作。

主 App 只会向 App Group 写入有界、脱敏的快照供 WidgetKit 扩展读取；
其中不包含身份认证 Token、Cookie、账号标识、完整服务器响应或用量历史。

Codex 灵动岛使用官方 Codex Hooks 与独立签名的本地 Helper，只转发哈希
会话标识、工作区路径最后一级、事件类型、粗粒度工具类别、会话来源和时间。
它不会转发提示词、命令、参数、工具输出或会话记录路径，也不会绕过官方
Hook 信任确认。

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

- 0.3.1 当前仍只支持 Codex，后续通过静态 Provider Registry 接入更多
  官方数据源。
- 额度重置界面仍是安全演示，不会调用 `account/rateLimitResetCredit/consume`。
- App Server Schema 可能随本机安装的 Codex 版本变化。

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

构建脚本会优先使用 Developer ID Application 身份，其次使用 Apple Development 身份；这两类带 Team ID 的身份继续启用 Hardened Runtime。如果两者都不可用，脚本会回退到不启用 Hardened Runtime 的 ad-hoc 签名，确保内嵌 Framework 可以正常加载。只有 Developer ID Application 构建可以使用公证流程：

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

使用 Xcode 时，请打开 `QuotaView.xcodeproj`，选择共享的 **QuotaView** Scheme 和 **My Mac**，然后运行或测试。

## 数据协议

初始化后，客户端会发送以下请求：

```text
initialize
initialized
account/rateLimits/read
account/usage/read  # 仅在任一 Token 区域开启时请求
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

## 生产源码结构

```text
Sources/
├── QuotaView/              # SwiftUI 界面、设置与 AppKit 菜单面板
├── QuotaViewActivityHook/  # 已签名、保护隐私的 Codex Hook Helper
├── QuotaViewCore/          # Domain、Provider、刷新与账户操作边界
├── QuotaViewFutureContracts/# 不随 App 链接的历史、图表、显示与通知契约
├── QuotaViewWidgetContract/# 只依赖 Foundation 的有界 Widget 快照契约
├── QuotaViewWidget/        # 原生小号与中号 WidgetKit 扩展
└── QuotaViewProbe/         # 只读命令行探针
Resources/
├── Assets.xcassets/        # 应用、菜单栏和界面资源
└── Fonts/                  # 内置 Asta Sans 字体文件
Tests/
└── QuotaViewCoreTests/     # Domain、应用行为、进程与契约测试
```

## 路线图

- [x] Codex 灵动岛实时任务状态
- [ ] 使用 `ServiceManagement` 实现登录时启动
- [ ] 历史趋势和额度提醒
- [x] 基于 App Group 的 WidgetKit 扩展
- [ ] 适配更多 AI 服务
- [ ] 用户单独授权后的官方账户操作
- [x] Developer ID 签名与公证
- [ ] 自动更新

## 反馈与贡献

欢迎提交 Bug、兼容性报告和目标明确的功能建议。请先使用 [Issue 模板](https://github.com/Duoasa/QuotaView/issues/new/choose)，准备代码改动前请阅读 [SDD 规格索引](docs/specs/README.md) 和 [CONTRIBUTING.md](CONTRIBUTING.md)。

请勿在 Issue 中包含身份认证 Token、登录凭据或未经脱敏的 `~/.codex` 文件。
