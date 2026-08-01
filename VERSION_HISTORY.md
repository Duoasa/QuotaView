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
| 最新推荐版本 | `0.3.1 (Build 1)` |
| Git tag | `v0.3.1` |
| Tag commit | `041c698ae9755d458fa9f111e4ac74e9711048b9` |
| GitHub Release | [QuotaView 0.3.1 — Codex Island](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1) |
| Release 资产 | `QuotaView-v0.3.1.zip` |
| 资产大小 | `11,443,295 bytes` |
| SHA-256 | `ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d` |
| 最低系统版本 | macOS 14 |
| 架构 | Universal `arm64 + x86_64` |
| 签名 | `Developer ID Application: Chenchen Xu (BUUH229D5Q)`，启用 Hardened Runtime |
| 公证 | Apple Accepted，已 Staple；Submission `2b125886-a3dc-4734-a139-280a08302e5c` |
| 发布状态 | 正式 Release、Latest、非 Draft、非 Pre-release |

> 当前生产版本为 `0.3.1 (Build 1)`，核心定位为 Codex 灵动岛。开发、
> 验证与发布记录见
> [HANDOFF.md](HANDOFF.md#1-031-正式发布状态)。

> 2026-08-01 已确认公开 Build 1 的 Widget 在 Developer ID 直接分发环境
> 中会被 `SystemPolicyAppData` 拒绝读取未带团队前缀的 App Group，导致小号
> 与中号小组件显示“额度数据不可用”。本地 `0.3.1 (Build 2)` 热修复候选
> 已迁移到 `BUUH229D5Q.com.quotaview.shared`，并将当前额度标题统一为
> “本周期剩余” / `Period Remaining`。在 Build 2 完成公证并创建独立
> Release 前，本节继续保留已经发生的 Build 1 公开发布事实；候选元数据、
> 验证结果和发布清单见 [HANDOFF.md](HANDOFF.md#031-build-2-github-发布候选)。

### 版本定位规则

1. 新会话先读取 [HANDOFF.md](HANDOFF.md) 顶部的“版本定位入口”。
2. 按该入口跳转到本节，确认最新版本、tag、资产和发布状态。
3. 回到 `HANDOFF.md` 阅读当前工作区、已完成事项和下一次迭代建议。
4. 如本文件、`HANDOFF.md` 与生产代码中的版本号不一致，以用户当前指令和
   生产代码为准，并在同一任务内同步修正两份文档。
5. 不得把已撤回版本重新标记为最新版本，也不得移动已有正式 tag。
6. 新版本只有完成正式签名、公证、资产验证和 Release 后才能加入版本总览
   并切换 Latest；必须使用唯一的 tag 与 ZIP 文件名。

## 版本总览

| 版本 | 日期（Asia/Shanghai） | 状态 | 核心定位 |
|---|---|---|---|
| `0.3.1 (Build 1)` | 2026-07-30 | **当前最新** | Codex 灵动岛实时任务状态与官方 Hooks 连接 |
| `0.2.1 (Build 1)` | 2026-07-30 | 历史正式版 | 原生 WidgetKit 小组件与 Developer ID 公证分发 |
| `0.2.0 (Build 4)` | 2026-07-29 | 历史正式版 | UI 热更新与下载版启动可靠性修复 |
| `0.2.0 (Build 3)` | 2026-07-29 | **已撤回并删除** | UI1/UI2 组件细节迭代；发布包存在 Framework 加载故障 |
| `0.2.0` | 2026-07-28 | 历史正式版 | 核心架构重构后的首个正式版本 |
| `0.1.5 (Build 6)` | 2026-07-27 | 历史正式版 | 原生菜单面板、玻璃外观、设置窗口和状态标签热修复 |
| `0.1.3` | 2026-07-26 | 历史正式版 | 设置、外观、语言、图标和发布流程完善 |
| `0.1.0` | 2026-07-26 | 首个公开版本 | Codex 额度、Credits、Token 与重置时间基础能力 |

## 0.3.1 (Build 1)

Tag：`v0.3.1`

状态：当前最新正式 Release、GitHub Latest、非 Draft、非 Pre-release。

发布提交：
`041c698ae9755d458fa9f111e4ac74e9711048b9`

主要特性：

- 新增 Codex 灵动岛，以位于菜单栏下方的原生非激活浮层实时展示 Codex
  任务状态；
- 使用 Metal 流体球、状态配色和动效表达思考、工作、工具调用、权限确认、
  上下文压缩、子任务、完成与失败；
- 实现最大态、紧凑态和隐藏状态：任务完成 20 秒后紧凑，完成满 120 秒后
  隐藏，新活动立即重新展开；
- 使用 Codex 官方 Hooks 获取生命周期事件，并通过独立签名的
  `QuotaViewActivityHook` 在本机转发最小、脱敏的事件元数据；
- 新增新手向一键连接流程，自动检测 Hooks 支持、维护固定路径 Helper、
  保留现有 Hooks，并打开官方 `/hooks` 信任审查页；
- 只有 Codex 完成信任、重启并产生第一条真实 `UserPromptSubmit` 后，
  QuotaView 才会报告连接成功；
- README 中英文版本重点介绍 Codex 灵动岛，并加入任务完成状态预览图；
- 保留额度菜单、WidgetKit 小组件和只读账户边界；额度重置继续为本地
  Demo。

隐私与安全：

- Helper 只转发哈希会话标识、工作区路径最后一级、事件类型、粗粒度工具
  类别、SessionStart 来源和时间；
- 不转发提示词、命令、参数、工具输出、模型内容或会话记录路径；
- 本地桥接使用随机令牌、文件所有者与时效校验；不会绕过 Codex 官方
  Hook 信任确认；
- Prototype、CodexBar 参考文档和其他用户参考图片未进入发布提交。

发布资产：

- 文件名：`QuotaView-v0.3.1.zip`
- 大小：`11,443,295 bytes`
- SHA-256：
  `ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d`
- App、`QuotaViewCore.framework`、Widget Extension 与
  `QuotaViewActivityHook` 均为 Universal `x86_64 arm64`
- App、Widget 与 Helper 均为 `0.3.1 (1)`

签名与公证：

- App、Widget、Framework 与 Helper 使用
  `Developer ID Application: Chenchen Xu (BUUH229D5Q)`；
- Team ID 为 `BUUH229D5Q`，启用 Hardened Runtime 和可信时间戳；
- Apple notarization 状态为 `Accepted`，Submission ID：
  `2b125886-a3dc-4734-a139-280a08302e5c`；
- 公证票据已 Staple，`spctl` 返回
  `accepted / source=Notarized Developer ID`。

验证记录：

- 本地与 GitHub Actions 的 52 项测试均通过；
- 最终 ZIP 全新解压后通过 `codesign --verify --deep --strict`、
  `stapler validate` 与 `spctl --assess`；
- 加入下载隔离属性后 Gatekeeper 仍正常接受；
- GitHub 回下载资产与本地最终 ZIP 逐字节一致；
- GitHub 回下载 App 的真实启动烟雾测试持续 5 秒，没有 Framework、
  Helper、签名或 `fatalDyldError`；
- 最终视觉、语言与辅助功能矩阵仍等待产品所有者逐项验收，不提前记录为
  “已通过”。

## 0.2.1 (Build 1)

Tag：`v0.2.1`

状态：历史正式 Release，已由 0.3.1 取代为推荐下载版本。

发布提交：
`56aa71dd9f4013412f90c75e0c282a610e87d14e`

主要特性：

- 新增原生 WidgetKit 扩展，支持 macOS 小号与中号小组件；
- 小组件展示本周额度、重置时间、Credits、今日与累计 Token、订阅方案和
  连接状态；
- 主 App 通过正式 App Group 写入最小、脱敏且会过期的快照，Widget
  不访问网络、认证凭据或 Codex App Server；
- 更新菜单面板、进度条、连接状态与局部 Liquid Glass 细节；
- 订阅类型统一映射到 OpenAI 官方方案名称，未知值和不可用状态使用
  破折号，不伪造数据；
- README 中英文版本使用新的产品预览图，并同步 0.2.1 下载入口与更新
  说明；
- 继续保持只读边界；额度重置仍为本地 Demo，不调用真实消费接口。

发布资产：

- 文件名：`QuotaView-v0.2.1.zip`
- 大小：`10,907,231 bytes`
- SHA-256：
  `99e7fb951d4abd6475204c059f1e16481dac8be4c3b72e6b19889fc54737521b`
- App、`QuotaViewCore.framework` 与 Widget Extension 均为 Universal
  `x86_64 arm64`
- App 与 Widget 均为 `0.2.1 (1)`

签名与公证：

- App 与 Widget 均使用
  `Developer ID Application: Chenchen Xu (BUUH229D5Q)`；
- Team ID 为 `BUUH229D5Q`，启用 Hardened Runtime 和可信时间戳；
- Apple notarization 状态为 `Accepted`，Submission ID：
  `e211abde-be96-47eb-a5ca-50ec1df7f260`；
- 公证票据已 Staple，`spctl` 返回
  `accepted / source=Notarized Developer ID`。

验证记录：

- 本地与 GitHub Actions 的 33 项测试均通过；
- 无签名 Universal Xcode Release 构建通过；
- 最终 ZIP 全新解压后通过 `codesign --verify --deep --strict`、
  `stapler validate` 与 `spctl --assess`；
- 为解压 App 加入下载隔离属性后，Gatekeeper 仍正常接受；
- 本地最终包与 GitHub 回下载资产逐字节一致；
- GitHub 回下载 App 的真实启动烟雾测试持续 5 秒，没有
  `fatalDyldError`、Framework 加载或签名错误；
- 最终视觉与交互矩阵仍等待产品所有者验收，不在本记录中提前标记通过。

## 0.2.0 (Build 4)

Tag：`v0.2.0-build.4`

状态：历史正式 Release，已由 0.2.1 取代为推荐下载版本。

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
