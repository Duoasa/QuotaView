<p align="center"><img src="docs/media/readme/0.9.1/app-icon.png" alt="QuotaView 新产品图标" width="112"></p>

<h1 align="center">QuotaView</h1>

<p align="center"><strong>多 Agent 状态与用量灵动岛。</strong></p>

<p align="center">任务、审批与用量，都在桌面顶部。</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.9.1-build.16"><img alt="macOS 0.9.1 Build 16" src="https://img.shields.io/badge/macOS-v0.9.1_Build_16-blue"></a>
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-win.13"><img alt="Windows 0.8.3-win.13" src="https://img.shields.io/badge/Windows-v0.8.3--win.13-blue"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.9.1-build.16/QuotaView-v0.9.1-build.16.zip"><strong>下载 macOS 版</strong></a>
  · <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.8.3-win.13/QuotaView-Windows-0.8.3-win.13-x64.zip"><strong>下载 Windows 版</strong></a>
  · <a href="#快速开始">快速开始</a>
  · <a href="#agent-支持范围">Agent 支持范围</a>
</p>

<p align="center"><a href="README.md">English</a> · <strong>简体中文</strong></p>

[![QuotaView：多 Agent 状态与用量灵动岛](docs/media/readme/0.9.1/zh-CN/cover.jpg)](docs/media/readme/0.9.1/zh-CN/cover.jpg)

QuotaView 0.9.1 带来全新的品牌视觉：蓝色终端图标、更新的 Agent 标识，以及更清晰的桌面灵动岛。延续 QuotaView 的名字，让多个 Agent 的工作状态与用量集中可见。

## 任务状态，抬眼就能看到

收起时，当前状态与悬浮用量胶囊留在桌面顶部，让你专注手头工作，也能留意任务进展。

[![收起态灵动岛与用量胶囊](docs/media/readme/0.9.1/zh-CN/01-compact.jpg)](docs/media/readme/0.9.1/zh-CN/01-compact.jpg)

展开后查看多个 Agent 的任务、模型、Token 数，以及可用的主任务与子 Agent 活动。公开进度和结果详情由原客户端提供，缺失或尚未同步的内容保留提示。

[![展开态多 Agent 任务列表](docs/media/readme/0.9.1/zh-CN/02-expanded.jpg)](docs/media/readme/0.9.1/zh-CN/02-expanded.jpg)

## 看清请求，再决定

需要审批时，先查看命令、工作目录、原因和授权范围，再允许或拒绝。支持的 Codex、Claude Code 请求可在灵动岛处理；其他接入提供提醒，确认仍在原客户端完成。

[![Agent 审批请求与授权选项](docs/media/readme/0.9.1/zh-CN/03-approval.jpg)](docs/media/readme/0.9.1/zh-CN/03-approval.jpg)

## 额度、Token 与活动，一页查看

切换 Codex 与 Claude Code，查看可获取的额度窗口、重置时间、Token 历史、成本估算和活动热图。悬浮胶囊根据账户支持的周期显示 5 小时额度、周额度或两者。

[![Codex 额度窗口、Token 历史与活动统计](docs/media/readme/0.9.1/zh-CN/04-usage.jpg)](docs/media/readme/0.9.1/zh-CN/04-usage.jpg)

额度字段取决于客户端和采集配置；没有数据时保留未知状态。成本是估算值，不是账单。

## 重置之前，先确认

**Codex：**查看可用重置卡，以及一周内到期的卡片列表。保护开关可禁用重置卡使用；每次使用仍需明确确认，并消耗一次真实重置机会。请求中断后，手动重试复用已保存的操作，避免重复提交。

[![Codex 重置卡操作与到期信息](docs/media/readme/0.9.1/zh-CN/05-reset.jpg)](docs/media/readme/0.9.1/zh-CN/05-reset.jpg)

**Claude Code：**复制 `/limit-reset`，到 Claude Code 中执行并查看剩余次数与期限。QuotaView 不会替你执行 Claude 的重置。

## 按你的桌面来调整

选择液态玻璃或经典纯色，在实时预览中切换状态烟雾、量子噪点和液态涌浪。展开宽度、胶囊显示、隐私模式和自动展开可独立设置；多屏使用时跟随活动窗口，或固定在指定显示器。

原生液态玻璃需要 macOS 26 或更新系统；macOS 14–15 使用半透明材质，也可选择经典纯色。产品图展示 macOS 版；[此前的 0.8.5 视频演示](https://duoasa.github.io/QuotaView/demos/0.8.5/zh-CN/)仍可查看。

## Agent 支持范围

| Agent | 任务与确认 | 用量 |
| --- | --- | --- |
| **Codex** | 自动发现本地任务，可选活动 Hook；支持的确认可在灵动岛处理。 | 可用账户额度、重置时间、Credits、Tokens、成本估算及手动额度重置。 |
| **Claude Code** | 启用 Hook 后显示任务状态及支持的权限请求。 | 本地 Token 历史与成本估算；开启状态栏采集后读取官方额度窗口。 |
| **DSH** | 原生插件接收会话、工具、压缩与权限提醒。 | 事件实际提供的任务 Token 数；不提供账户额度面板。 |
| **Kimi Code** | Hook 接收任务状态、工具、压缩与权限提醒。 | 不提供账户额度与历史成本面板。 |
| **Cursor / Gemini CLI / OpenCode / GitHub Copilot CLI（预览）** | 可选的本地任务状态接入，确认仍在原客户端完成。 | 事件可提供的元数据；不提供账户额度面板。 |
| **Devin Desktop（预览）** | 独立开关与任务身份。 | 本地记录格式支持时读取当前会话模型与本轮 Token。 |
| **Devin CLI（预览）** | 独立开关与任务身份。 | 本地记录格式支持时读取当前会话模型与本轮 Token。 |

字段取决于客户端版本和配置。预览接入仍在不同客户端环境中验证，缺失数据保持未知。详见[接入契约](docs/specs/agent-integrations.md)。本表描述 macOS；Windows 支持范围以其说明为准。

## 快速开始

| 平台 | 当前版本 | 要求与说明 |
| --- | --- | --- |
| **macOS** | [0.9.1 Build 16](https://github.com/Duoasa/QuotaView/releases/download/v0.9.1-build.16/QuotaView-v0.9.1-build.16.zip) | macOS 14+；Apple silicon + Intel 通用包；Developer ID 签名与 Apple 公证。 |
| **Windows** | [0.8.3-win.13](https://github.com/Duoasa/QuotaView/releases/download/v0.8.3-win.13/QuotaView-Windows-0.8.3-win.13-x64.zip) | x64；[安装与连接说明](Windows/README.md)。 |

1. 在 macOS 下载、解压并打开 `QuotaView.app`。
2. 进入「设置 → 连接」，启用需要的 Agent；各客户端需单独安装与配置。
3. Codex 任务会在本地自动发现。配置 Hook 或插件后，按提示开启新会话或重启对应客户端。

macOS **默认开启自动检查更新**；已有用户偏好保留，可在设置中关闭。下载和安装更新仍需确认。

Windows 是 macOS 功能降级适配版，包含纯色灵动岛、AI 球与量子噪点、任务及支持的审批、用量统计；不包含桌面小组件和原生液态玻璃。两平台使用独立更新通道，本次 macOS 发布不改变 Windows 版本。

### 0.9.1 更新重点

- 全新品牌视觉与应用、Agent 图标；完成卡片采用中性底色，保留流动高光。
- 整理设置与预览，新增日语、韩语、繁体中文和西班牙语。
- 新增预览 Agent 接入，包括独立的 Devin Desktop / CLI 以及模型、Token 读取。
- 重置保护开关与一周内到期的重置卡列表。
- 减少后台重复读取，Claude 转录后台解析，特效按需加载。

[完整发布说明](https://github.com/Duoasa/QuotaView/releases/tag/v0.9.1-build.16) · [版本历史](VERSION_HISTORY.md)

## 隐私与本地处理

任务信息在本机处理。QuotaView 不把任务内容发送到 QuotaView 服务，也不收集登录凭据；连接通过本地 API、有界会话记录、Hook 或原生插件完成。

启用接入可能修改客户端配置，QuotaView 会先备份并只管理自己的条目。Codex 重置仅保存用于安全重试的本地操作记录，不保存登录凭据。反馈问题时请勿附带凭据或原始会话日志。

## 从源码构建

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
swift run QuotaView
```

需要 Swift 6 或兼容的 Xcode 工具链；DSH 插件测试还需要 Node.js。完整 App 与小组件使用 `QuotaView.xcodeproj`，选择 **QuotaView** Scheme 和 **My Mac** 后运行。Windows 构建见 [Windows/README.md](Windows/README.md)。

分发包的签名、公证与更新密钥配置见[发布流程](docs/workflow/RELEASE.md)。

## 项目与反馈

- [提交问题](https://github.com/Duoasa/QuotaView/issues/new/choose)，也可从**设置 → Bug 反馈**进入。
- [贡献指南](CONTRIBUTING.md) · [设计与行为规格](docs/specs/README.md) · [开发交接](HANDOFF.md)
- 采用 [MIT 许可证](LICENSE)开源。

**QQ 反馈群：1108649282**

<p align="center"><img src="docs/media/readme/shared/feedback-qr.jpg" alt="QuotaView QQ 反馈群二维码" width="240"></p>
