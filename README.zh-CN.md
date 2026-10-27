<p align="center">
  <img src="Resources/QuotaView-ICON.png" alt="QuotaView 图标" width="160">
</p>

<h1 align="center">QuotaView · macOS 与 Windows 多 Agent 灵动岛</h1>

<p align="center">
  液态玻璃，现在重新回归
</p>

<p align="center">
  实时状态、任务进度、等待确认、本次 Token、完成回执与剩余额度，都在一个原生灵动岛里。
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-build.1"><img alt="macOS 版本" src="https://img.shields.io/badge/macOS-v0.8.3_Build_1-blue"></a>
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-win.10"><img alt="Windows 版本" src="https://img.shields.io/badge/Windows-v0.8.3--win-blue"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI 状态" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="许可证：MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.8.3-build.1/QuotaView-v0.8.3-build.1.zip"><strong>下载 macOS 版 · v0.8.3 Build 1</strong></a>
  ·
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.8.3-win.10/QuotaView-Windows-0.8.3-win.10-x64.zip"><strong>下载 Windows 版 · 0.8.3-win</strong></a>
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

## 选择平台

| 平台 | 下载与源码 | 更新通道 |
| --- | --- | --- |
| macOS 14+ | [稳定版下载](https://github.com/Duoasa/QuotaView/releases/download/v0.8.3-build.1/QuotaView-v0.8.3-build.1.zip) · 根目录 Swift 工程 | 原有 macOS Sparkle 通道 |
| Windows x64 | [稳定版下载](https://github.com/Duoasa/QuotaView/releases/download/v0.8.3-win.10/QuotaView-Windows-0.8.3-win.10-x64.zip) · [.NET + WebView2 完整源码与说明](Windows/README.md) | 独立的签名 Windows appcast |

### Windows 首个正式版上线

[QuotaView 0.8.3-win](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-win.10) 现已发布。受系统能力与软件架构差异影响，目前 Windows 版是在 macOS 版基础上做的功能降级适配，后续会持续更新完善。首版保留纯色灵动岛、AI 球与量子噪点、任务状态与支持的审批操作，以及用量统计；暂不包含桌面小组件和原生液态玻璃。

两个平台后续均在本仓库维护，Release 标明所属平台，更新通道相互独立。Windows 包内与更新版本号保留为 `0.8.3-win.10`，安装方法见 [Windows 说明](Windows/README.md)。下方截图和版本说明为 macOS 版。

## 0.8.3 更新

改善 macOS 27 的液态玻璃兼容性。灵动岛下部玻璃区域与悬浮用量胶囊统一采用清透材质，支持浅色、深色和自动外观；设置项目重新分组，并优化工具图标、文字与标签间距。

同时修复系统升级后桌面小组件可能因自定义字体解码失败而空白的问题，保留 Asta Sans 字体样式。

## 同时包含 0.8.2 的改进

通用设置新增灵动岛显示位置：可以跟随当前活动窗口所在的屏幕，也可以固定在指定显示器。选择会自动保存，显示器断开时暂回主屏，重新连接后恢复。同时修复了子 Agent 信息在任务卡片下方偏上的问题。

## 液态玻璃，现在重新回归

QuotaView 0.8.1 为灵动岛带来新的液态玻璃界面。任务、用量和审批仍然留在屏幕顶部，玻璃、光线与壁纸自然相融。

![QuotaView 0.8.1：液态玻璃，现在重新回归](Resources/0.8.1/0.jpg)

### 每个任务，都有自己的状态

思考、工作、等待确认和完成，用不同的 AI 球与光效区分。展开后可以同时查看多个任务、子 Agent、模型和 Token 用量；完成后直接查看结果。任务卡片采用统一的圆角、间距和对齐，展开、收起与页面切换也更连贯。

![多任务灵动岛与状态卡片](Resources/0.8.1/1.jpg)

### 用量，不用反复打开面板

新增悬浮用量胶囊，显示剩余额度与重置倒计时。账户有 5 小时周期时，与周额度并列显示；只有周周期时，胶囊自动收窄。玻璃外观跟随灵动岛的浅色、深色或自动选择，显示开关可单独控制。

用量页可切换 Codex 和 Claude Code，集中查看可获取的额度、Token 历史、成本估算与活动热图。成本是估算值，不是账单；各客户端提供的数据范围不同。

![双周期额度、账户与 Token 活动](Resources/0.8.1/2.jpg)

### 看清请求，再决定

需要确认时，灵动岛用赤金色光晕提醒你。命令、工作目录、请求理由和授权范围分区展示，主要操作使用浅色玻璃按钮。支持的请求可直接在灵动岛处理，需要回到原客户端的请求会给出提示。

本次修复了 Codex 确认连接重新订阅后，后续审批信息可能无法继续更新的问题。

![审批详情与授权选项](Resources/0.8.1/3.jpg)

### 重置卡，也有新的样子

重置次数、剩余额度和操作说明放在同一页，红色按钮让操作更醒目。**额度重置目前仍为演示，不消耗真实重置次数。**

![额度重置卡演示](Resources/0.8.1/4.jpg)

### 按你的桌面来调整

设置改为左右分栏，窗口、文字、图标与控件更加紧凑。灵动岛支持液态玻璃和经典纯色两种材质，黑色区域可在 20%–80% 之间调整；展开宽度、胶囊显示、隐私模式和自动展开也能单独设置。浅色、深色和自动外观的可视化选项仅在液态玻璃下显示。

预览会同步显示材质和双周期胶囊。状态烟雾、量子噪点、液态涌浪三种任务特效可随时切换。

![灵动岛材质与显示设置](Resources/0.8.1/5.jpg)

### 连接你常用的 Agent

在同一页管理 Codex、Claude Code、DSH 和 Kimi Code。连接状态、开关与各自的详细设置放在一起，不必分散寻找。

![Agent 连接设置](Resources/0.8.1/6.jpg)

产品图展示 0.8.1 界面并使用示例数据，设置分组此后已有调整。实际额度、任务状态和可用操作以本地客户端提供的信息为准。原生液态玻璃需要 macOS 26；较早系统使用半透明材质，也可选择经典纯色。

## Agent 支持范围

| Agent | 任务与确认 | 用量 |
| --- | --- | --- |
| **Codex** | 自动发现本地任务，可选活动 Hook；支持的确认可在灵动岛处理。 | 可用的账户额度、重置时间、Credits、Tokens 与成本估算。 |
| **Claude Code** | 主动启用 Hook 后显示任务状态及支持的权限请求。 | 本地 Token 历史与成本估算；开启状态栏采集后读取官方额度窗口。 |
| **DSH** | 原生会话插件接收生命周期、工具、压缩和权限提醒；兼容客户端统一显示为 DSH。 | 事件实际提供的任务 Token 数；不提供账户额度与历史成本面板。 |
| **Kimi Code** | Hook 接收生命周期、工具、压缩和权限提醒。 | 不提供账户额度与历史成本面板。 |

DSH 和 Kimi Code 的权限请求在原客户端确认。可用字段取决于 Agent 及其版本，缺失数据保留占位符。DSH、Kimi 接入默认关闭，由用户主动开启。兼容边界见[接入规格](docs/specs/agent-integrations.md)。

## 快速开始

Windows 用户请参阅 [Windows 安装说明](Windows/README.md#下载与更新)，以下步骤适用于 macOS。

1. 下载 [QuotaView 0.8.3 Build 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-build.1)，解压并打开 `QuotaView.app`。
2. 在**设置 → 连接**中启用需要的 Agent。
3. Codex 自动发现本地任务。配置 Hook 或 DSH 插件后，按设置提示新建会话或重启对应客户端。

正式包已使用 Developer ID 签名、通过 Apple 公证并完成 Staple。

需要 **macOS 14 或更高版本**。Universal 应用同时支持 Apple 芯片与 Intel Mac；各 Agent 客户端需要单独安装和配置。

应用更新使用 Stable 通道，自动检查可选，安装更新需要确认。

## 隐私设计

任务信息在本地处理，不会上传到 QuotaView 服务，也不收集登录凭据。接入使用本地接口、有界会话记录、Hook 或原生插件。

启用接入可能修改对应客户端配置；修改前保存备份，只管理 QuotaView 自己的标记项。DSH 定制客户端继续使用各自独立的数据目录与会话身份。

成本为估算值，不是账单。额度重置仍是本地演示，不消耗真实重置次数。反馈问题时请勿上传凭据或原始会话记录。

## 从源码构建

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
swift run QuotaView
```

使用 Swift 6 或兼容的 Xcode 工具链；DSH 插件测试还需要 Node.js。需要完整 App 与小组件时，打开 `QuotaView.xcodeproj`，选择 **QuotaView** Scheme 和 **My Mac** 后运行。

分发包由 `scripts/build-app.sh` 构建。Developer ID 签名与公证需要自己的签名身份、公证配置，以及可恢复的 Sparkle 更新密钥加密备份，详见[发布流程](docs/workflow/RELEASE.md)。

## 项目与反馈

- [当前版本](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-build.1) · [上一稳定版 0.8.2](https://github.com/Duoasa/QuotaView/releases/tag/v0.8.2-build.2)
- [版本历史与发布证据](VERSION_HISTORY.md) · [开发交接](HANDOFF.md)
- [设计与行为规格](docs/specs/README.md) · [贡献指南](CONTRIBUTING.md)
- [提交问题](https://github.com/Duoasa/QuotaView/issues/new/choose)，也可从**设置 → Bug 反馈**进入。

采用 [MIT 许可证](LICENSE)开源。

**QQ 反馈群：1108649282**

<p align="center">
  <img src="Resources/QuotaView-QQ-Feedback-QR.png" alt="QuotaView QQ 反馈群二维码" width="280">
</p>
