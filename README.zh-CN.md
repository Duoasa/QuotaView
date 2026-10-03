<p align="center">
  <img src="Resources/QuotaView-ICON.png" alt="QuotaView 图标" width="160">
</p>

<h1 align="center">QuotaView · macOS 上的 Codex 灵动岛</h1>

<p align="center">
  让 Codex 工作时始终可见。
</p>

<p align="center">
  实时状态、任务进度、等待确认、本次 Token、完成回执与剩余额度，都在一个原生灵动岛里。
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.7.5-build.3"><img alt="最新版本" src="https://img.shields.io/github/v/release/Duoasa/QuotaView?display_name=tag"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI 状态" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="许可证：MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.7.5-build.3/QuotaView-v0.7.5-build.3.zip"><strong>下载 QuotaView v0.7.5 Build 3</strong></a>
  ·
  <a href="#快速开始">快速开始</a>
  ·
  <a href="#隐私设计">隐私说明</a>
  ·
  <a href="#从源码构建">从源码构建</a>
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <img src="Resources/QuotaView-0.7.5-Island.png" alt="QuotaView Codex 灵动岛在 macOS 上显示实时任务进度与额度" width="100%">
</p>

无需频繁切换窗口，也能掌握并行工作的进展。QuotaView 将任务、多 Agent 协作、确认请求与用量集中到菜单栏下方的原生 **Codex 灵动岛**。

QuotaView 开源、轻量，并以本地处理为核心。自动发现正在运行的本地会话，额度与用量一次点击即可查看。

## 0.7.5：迄今最大规模的更新

QuotaView 0.7.5 是迄今为止规模最大的一次重构与更新。全新的多任务灵动岛，将任务进展、协作状态和额度用量集中呈现，让并行工作更容易掌握。

- **多任务管理：** 同时关注多个会话，查看任务进展、详情与完成结果。
- **多 Agent 协作：** 子任务与主任务关联展示，清晰呈现协作关系和各自状态。
- **任务确认：** 集中查看需要关注的请求，直接处理支持的确认操作。
- **全新用量面板：** 重新组织额度、重置时间与 Token 统计，重要信息一目了然。

底层数据接收与状态同步也经过系统性重构，提升长会话和多任务运行时的信息完整性。设置中新增独立的问题反馈入口，方便提交问题与建议。

## Codex 灵动岛

| 任务时刻 | 灵动岛显示什么 |
| --- | --- |
| **思考与执行** | 任务标题、公开进展、模型、运行时间与 Token 用量。 |
| **并行任务** | 每个会话独立展示，可展开详情并查看完成结果。 |
| **多 Agent 协作** | 子任务从主卡片下方伸出，显示各自头像、名称、模型与状态；内容过多时单向滚动。 |
| **等待确认** | 突出显示待处理请求，提供有长度限制的预览与支持的确认操作。 |
| **记忆整理** | 独立显示为底栏小 AI 球，持续更新真实状态，不占用任务列表。 |
| **任务完成** | 保留完成结果，支持本地归档卡片。 |

灵动岛区分思考、工具调用、等待确认、上下文压缩、完成、中断与失败。只有任务真实完成才会到达 100%；展开和收起时保持任务上下文。

## 新版 Codex，即开即用

- **自动发现任务。** 开始本地任务即可跟随活动，首次使用无需配置 Hook。
- **统一状态同步。** 会话元数据、实时事件和公开进展汇入同一套任务展示。
- **保留兼容通道。** 本地 App Server 与签名 Activity Hook 补充本地任务发现。
- **操作由你决定。** 日常观察保持只读；支持的确认请求由你主动回应，不可处理的请求可跳回原任务。

## 额度与用量，一次点击

从灵动岛进入用量统计，集中查看账户、额度与使用趋势。

<p align="center">
  <img src="Resources/QuotaView-0.7.5-Usage.png" alt="QuotaView 0.7.5 用量面板，展示额度、Token 活动与成本估算" width="100%">
</p>

| 界面 | 用途 |
| --- | --- |
| **菜单栏** | 无需打开窗口，持续显示你选择的额度数值或重置倒计时。 |
| **用量面板** | 查看全部可用 Codex 额度周期、Spark 额度、重置时间、Credits、最近一天与 30 日 Token，以及累计用量。 |
| **Token 活动** | 通过活动网格查看 Token 使用情况，支持每天、每周与累计视图。 |
| **成本估算** | 查看明确标注的本地 30 日估算值；它是估算，不是账单。 |
| **桌面小组件** | 使用原生小号或中号 WidgetKit 小组件查看额度和重置信息。 |
| **应用更新** | 手动检查 Stable 通道，或主动开启每 24 小时一次的原生检查；安装更新始终需要确认。 |

## 快速开始

1. 确认已经安装并登录 ChatGPT 或 Codex。
2. 从 [v0.7.5 Build 3 Release](https://github.com/Duoasa/QuotaView/releases/tag/v0.7.5-build.3) 下载 `QuotaView-v0.7.5-build.3.zip`。
3. 解压后打开 `QuotaView.app`。
4. 开始一个 Codex 任务。新版 Codex 会自动连接，不需要安装 Hook 或重启。

> [!IMPORTANT]
> v0.7.5 Build 3 已使用 Developer ID 证书签名、通过 Apple 公证并完成
> Staple。解压后可以正常打开，不再需要旧版未签名构建使用的 Finder
> 右键打开方式。

Universal 应用支持 macOS 14 或更高版本，同时兼容 Apple 芯片和 Intel Mac。从 Finder 启动后的首次账户请求可能需要 20–30 秒，后续刷新通常会快很多。

## 隐私设计

QuotaView 在本地处理任务信息，不抓取账户网页，不收集登录凭据，也不会将任务内容上传到 QuotaView 服务。

任务桥有界读取本地会话记录与元数据，用于展示状态、Token 和公开进展。公开消息与工具详情仅供任务视图临时使用，不读取私有推理；诊断只保留脱敏标识与摘要，不包含消息正文或原始任务记录。

额度信息来自本机安装的 App Server。显示偏好、紧凑的本地状态和有界 WidgetKit 快照保存在你的 Mac 上；QuotaView 不持久化身份认证 Token、Cookie 或完整账户响应。

日常观察保持只读，支持的确认操作需要用户主动触发。额度重置界面仍是本地演示，不会消耗真实重置次数。

主 App Target 关闭 App Sandbox，以便与本机安装的服务通信。

## 系统要求与当前范围

- macOS 14 或更高版本
- 已安装并登录 ChatGPT/Codex
- 仅从源码构建时需要 Swift 6 或 Xcode 16+
- 当前稳定版聚焦支持 Codex
- 同时展示多个本地会话及其子 Agent；可用确认操作取决于当前会话连接能力
- 成本数值是本地估算，不是账单记录
- Codex 协议细节可能随安装版本变化，因此 QuotaView 保留兼容回退路径

QuotaView 依次检查 `CODEX_EXECUTABLE`、已安装桌面应用中的新旧程序路径、Homebrew 路径与当前 `PATH`。

## 从源码构建

克隆仓库并运行测试：

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
```

运行只读额度探针：

```bash
swift run QuotaViewProbe
```

在开发环境中运行应用：

```bash
swift run QuotaView
```

或者构建 Universal 应用和 ZIP：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/QuotaView.app
```

构建脚本会优先使用 Developer ID Application 身份，其次使用 Apple Development 身份。如果两者都不可用，会回退到适合本地测试的 ad-hoc 签名。只有 Developer ID Application 构建可以使用公证流程：

使用 Developer ID 打包前，先确认 Sparkle 签名密钥已有加密备份。

```bash
SPARKLE_KEY_BACKUP_CONFIRMED=YES \
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

使用 Xcode 时，请打开 `QuotaView.xcodeproj`，选择共享的 **QuotaView** Scheme 和 **My Mac**，然后运行或测试。

## 数据来源

初始化后请求额度与用量数据：

```text
initialize
initialized
account/rateLimits/read
account/usage/read  # 仅在 Token 区域开启时请求
```

| QuotaView 数据 | Codex App Server 字段 |
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
├── QuotaView/                    # SwiftUI 界面、设置与 AppKit 界面层
├── QuotaViewActivityHook/        # 已签名的兼容 Hook Helper
├── QuotaViewActivityHookSupport/ # 共享的脱敏 Hook 协议支持
├── QuotaViewCore/                # 领域模型、数据源、任务桥与刷新
├── QuotaViewFutureContracts/     # 未链接的未来能力契约
├── QuotaViewWidgetContract/      # 有界 WidgetKit 快照契约
├── QuotaViewWidget/              # 原生小号与中号小组件
└── QuotaViewProbe/               # 只读命令行额度探针
Tests/
└── QuotaViewCoreTests/           # 领域、数据桥、生命周期与 App 测试
```

## 灵动岛开发台

长期保留的 [灵动岛内容开发台](Prototypes/IslandTextConsole/README.md) 支持手动检查状态、百分比、中英文和长文字。打开 `Prototypes/IslandTextConsole/Open Console.command`；生产渲染代码改动后用 `--rebuild` 重建。开发台使用独立调试数据和构建目标，与正式应用隔离。

## 发布与项目状态

- **推荐稳定版：** [QuotaView v0.7.5 Build 3](https://github.com/Duoasa/QuotaView/releases/tag/v0.7.5-build.3)
- **稳定回滚版本：** [QuotaView v0.5.1 Build 13](https://github.com/Duoasa/QuotaView/releases/tag/v0.5.1-build.13)
- **已撤回的 0.4.7 Build 2：** Release 转为草稿，不再显示在公开时间线；撤回原因和历史证据见 [版本历史](VERSION_HISTORY.md)。
- **历史代理预览：** [QuotaView v0.4.7 Preview 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.7-preview.1) — 仅保留历史测试记录，不是推荐稳定版。
- **历史多任务预览：** [QuotaView v0.3.2 Preview 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.2-preview.1)
- **版本历史与发布验证：** [VERSION_HISTORY.md](VERSION_HISTORY.md)
- **当前工程交接：** [HANDOFF.md](HANDOFF.md)
- **设计与行为规格：** [docs/specs/README.md](docs/specs/README.md)

## 开源与贡献

QuotaView 采用 [MIT 许可证](LICENSE)开源。

可通过 **设置 → Bug 反馈** 查看 QQ 群二维码或直接打开 GitHub Issues。欢迎提交 Bug、兼容性报告和目标明确的功能建议。请先使用 [Issue 模板](https://github.com/Duoasa/QuotaView/issues/new/choose)，准备代码改动前阅读 [规格索引](docs/specs/README.md) 和 [CONTRIBUTING.md](CONTRIBUTING.md)。

请勿在 Issue 中包含身份认证 Token、登录凭据、原始任务记录或未经脱敏的 `~/.codex` 文件。

## 用户反馈社群

遇到问题、发现 Bug，或者有新想法？欢迎加入 QuotaView QQ 反馈群。

**QQ群：1108649282**

<p align="center">
  <img src="Resources/QuotaView-QQ-Feedback-Community.jpg" alt="QuotaView QQ 反馈群二维码，群号 1108649282" width="320">
</p>
