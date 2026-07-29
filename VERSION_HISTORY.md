# QuotaView 版本历史

本文件是 QuotaView 的版本索引和历史发布记录。当前开发状态、未完成事项与
下一次迭代入口请阅读 [HANDOFF.md](HANDOFF.md)。

记录范围为已创建 GitHub Release/tag 的公开版本，以及已经撤回但需要保留
故障背景的 Build 3；未形成独立 Release 的内部构建不单独列为历史版本。

## 当前最新版本

> Codex 版本定位入口：读取 `HANDOFF.md` 时，必须先核对本节，再继续处理
> 当前迭代。除非用户明确指定旧版本，否则一律以这里标记的最新版本作为
> 产品与发布基线。

| 项目 | 当前值 |
|---|---|
| 最新推荐版本 | `0.2.0 (Build 4)` |
| Git tag | `v0.2.0-build.4` |
| Tag commit | `8a76b5725b616091e2841a8eae232f58168d6674` |
| GitHub Release | [QuotaView 0.2.0 (Build 4) — Launch Reliability Hotfix](https://github.com/Duoasa/QuotaView/releases/tag/v0.2.0-build.4) |
| Release 资产 | `QuotaView-v0.2.0-build.4.zip` |
| 资产大小 | `8,032,585 bytes` |
| SHA-256 | `ab59fe031f6bf6693115968c5a0dc3ca4ea7051e5fefdab2b5cb293f8361aca0` |
| 最低系统版本 | macOS 14 |
| 架构 | Universal `arm64 + x86_64` |
| 签名 | ad-hoc，不启用 Hardened Runtime |
| 公证 | 未完成 |
| 发布状态 | 正式 Release、Latest、非 Draft、非 Pre-release |

### 版本定位规则

1. 新会话先读取 [HANDOFF.md](HANDOFF.md) 顶部的“版本定位入口”。
2. 按该入口跳转到本节，确认最新版本、tag、资产和发布状态。
3. 回到 `HANDOFF.md` 阅读当前工作区、已完成事项和下一次迭代建议。
4. 如本文件、`HANDOFF.md` 与生产代码中的版本号不一致，以用户当前指令和
   生产代码为准，并在同一任务内同步修正两份文档。
5. 不得把已撤回版本重新标记为最新版本，也不得移动已有正式 tag。
6. 如果 Marketing Version 继续保持 `0.2.0`，下一次发布的 Build Number
   必须大于 `4`，并使用唯一的 tag 与 ZIP 文件名；是否升级 Marketing
   Version 由用户在新迭代中决定。

## 版本总览

| 版本 | 日期（Asia/Shanghai） | 状态 | 核心定位 |
|---|---|---|---|
| `0.2.0 (Build 4)` | 2026-07-29 | **当前最新** | UI 热更新与下载版启动可靠性修复 |
| `0.2.0 (Build 3)` | 2026-07-29 | **已撤回并删除** | UI1/UI2 组件细节迭代；发布包存在 Framework 加载故障 |
| `0.2.0` | 2026-07-28 | 历史正式版 | 核心架构重构后的首个正式版本 |
| `0.1.5 (Build 6)` | 2026-07-27 | 历史正式版 | 原生菜单面板、玻璃外观、设置窗口和状态标签热修复 |
| `0.1.3` | 2026-07-26 | 历史正式版 | 设置、外观、语言、图标和发布流程完善 |
| `0.1.0` | 2026-07-26 | 首个公开版本 | Codex 额度、Credits、Token 与重置时间基础能力 |

## 0.2.0 (Build 4)

Tag：`v0.2.0-build.4`

状态：当前最新正式 Release。

主要特性：

- 包含 Build 3 完成的 UI1/UI2 组件精修：
  - 功能按钮；
  - 额度重置入口卡片；
  - 重置按钮；
  - 订阅类型 Tag；
  - Codex 数据连接状态标签；
  - 浅色功能图标和菜单栏图标。
- 连接状态标签固定为 `18 pt` 高、`6 pt` 连续圆角，不再退化为
  橄榄球形。
- 重置额度只读取真实
  `CurrentCodexPresentation.availableResetCredits`，不包含调试虚拟数据。
- 额度重置操作仍为本地 Demo，不调用真实
  `account/rateLimitResetCredit/consume`。
- 修复 GitHub 下载版在菜单栏项目建立前退出的问题：
  - Build 3 将无 Team ID 的 ad-hoc 签名与 Hardened Runtime 组合；
  - macOS Library Validation 因此拒绝加载
    `QuotaViewCore.framework`；
  - Build 4 的 ad-hoc 回退不再启用 Hardened Runtime；
  - Developer ID Application 与 Apple Development 身份仍保留
    Hardened Runtime。
- 打包脚本新增签名模式断言，避免再次生成“验签通过但运行时无法加载
  Framework”的发布包。
- GitHub Release Notes 只保留一份英文源文，由 GitHub 的界面翻译功能
  负责本地化，避免中英文正文重复显示。

验证记录：

- 本地与 GitHub Actions 的 28 项测试均通过；
- App 与 `QuotaViewCore.framework` 均为 Universal
  `x86_64 arm64`；
- ZIP 全新解包后通过 `codesign --verify --deep --strict`；
- 从 GitHub 回下载的 ZIP 与本地发布包逐字节一致；
- GitHub 回下载 App 的真实启动烟雾测试持续 3 秒，没有新增
  `fatalDyldError`。

## 0.2.0 (Build 3)

原 tag：`v0.2.0-build.3`

状态：已撤回；GitHub Release、远端 tag 和本地 tag 均已删除，不得作为
下载、开发或发布基线。

完成的功能：

- 按 Figma Page UI 的 UI1/UI2 精修按钮、重置入口、重置按钮、订阅 Tag
  和连接状态标签；
- 更新浅色功能图标和菜单栏图标；
- 修复连接状态标签的橄榄球形轮廓；
- 移除 3 次调试重置额度，恢复真实 Codex 数据链路。

撤回原因：

- 发布脚本使用 `--sign - --options runtime`；
- App 与内嵌 Framework 均没有 Team ID；
- `codesign --verify --deep --strict` 可以通过，但下载后运行时
  `dyld` 仍会因 Library Validation 拒绝 Framework；
- 进程在 `applicationDidFinishLaunching` 前退出，因此状态栏没有任何
  显示。

这些功能和修复均已由 Build 4 继承，不应恢复 Build 3。

## 0.2.0

Tag：`v0.2.0`

状态：历史正式 Release，已由 Build 4 取代为推荐下载版本。

核心特性：

- 引入标准化 Domain Model 与静态 Provider Registry，为未来官方数据源
  预留边界，但不加入动态插件运行时；
- 引入 generation、revision 和账户感知的刷新协调器，拒绝旧请求覆盖
  新状态；
- Codex App Server 增加有界输出、独立启动/请求超时、取消处理与可选
  usage 失败隔离；
- 同时关闭两个 Token 区域时不再请求 Token 用量；
- 增加历史、图表、通知和未来 WidgetKit 的轻量契约，不启用新的后台任务；
- 保留双语界面、菜单面板、设置窗口和本地额度重置 Demo；
- 默认只读，不包含真实额度重置或账户写操作。

历史资产：

- `QuotaView-v0.2.0.zip`
- SHA-256：
  `f14936120a1b884a95ca4e5150b70ababd5e40c1566ac78c0f26e716cb746bb0`

## 0.1.5 (Build 6)

Tag：`v0.1.5`

状态：历史正式 Release。

核心特性：

- 使用原生 `NSStatusItem` 和自定义动态高度面板重构菜单栏体验；
- 新增实时订阅名称、周剩余百分比、可用状态和可配置指标；
- 新增清透/磨砂玻璃与深浅外观适配；
- macOS 26 使用原生 Liquid Glass，macOS 14–15 使用 Material 回退；
- 重构设置窗口，包含菜单栏、面板内容、外观、语言和通用页面；
- 新增额度概览、重置时间、Credits、每日/累计 Token、重置入口的独立
  显示开关；
- 重构额度重置详情页和面板内确认流程，同时保持 Demo 安全边界；
- 完成简体中文与 English 界面；
- 打包 Asta Sans 与新的界面资源；
- Build 6 修复 Available/Unavailable 状态标签：
  - 固定 `18 pt` 高；
  - `6 pt` 连续圆角；
  - 移除状态色模糊外溢。

历史资产：

- `QuotaView-v0.1.5.zip`
- SHA-256：
  `979e68c07a9183b45350d7270b7e86c227a792f273a84035454d4443cd97ad74`

## 0.1.3

Tag：`v0.1.3`

状态：历史正式 Release。

核心特性：

- 新增原生设置窗口及菜单栏/Popover 显示选项；
- 新增跟随系统、浅色和深色外观；
- 新增跟随系统、简体中文和 English 语言选项；
- 新增磨砂/清透玻璃，以及 macOS 14–15 Material 回退；
- 新增正式 App Icon 和 Template 菜单栏图标；
- 改进额度重置详情与确认流程，继续保持 Demo 模式；
- 改进 Universal 发布打包与签名检查。

历史资产：

- `QuotaView-v0.1.3.zip`
- SHA-256：
  `3e704f939eeea7980b1c2f94978b89495e1c0501c999fef744828e5a40e5c10b`

## 0.1.0

Tag：`v0.1.0`

状态：首个公开 Release。

核心特性：

- 读取本机已登录 Codex 账户的当前额度和剩余百分比；
- 显示下次额度重置倒计时；
- 分离套餐额度与 Credits 余额；
- 显示可用重置次数，并提供安全 Demo 交互；
- 显示近期每日与累计 Token 用量；
- 自动刷新，并提供离线和错误状态；
- 支持 Apple Silicon 与 Intel 的 Universal macOS App。

历史资产：

- `QuotaView-v0.1.0.zip`
- SHA-256：
  `5a4412794f78fc8a340b9fbb7c9eca7908cc5395dcd21fcb6fce8f39998b88fe`

## 维护规则

- 每次正式发布、撤回版本或修改 Latest 指向时，必须同步更新：
  - 本文件的“当前最新版本”；
  - 版本总览；
  - 对应版本详情；
  - [HANDOFF.md](HANDOFF.md) 的当前版本与下一步。
- 版本记录只写已经发生并可由 tag、Release、生产代码或验证日志确认的
  事实；计划中的版本不得提前写成已发布。
- 删除 Release 时仍保留一条“已撤回”历史记录，说明原因和替代版本，
  防止后续 Codex 重复使用问题版本。
- GitHub Release Notes 使用单份英文源文，避免与 GitHub 自动翻译产生
  重复内容。
- 不移动或覆盖已发布 tag；热更新使用新的 Build Number、tag 和资产名。
