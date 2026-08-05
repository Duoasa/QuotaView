# QuotaView 项目 Handoff

更新日期：2026-08-06

集成工作区：`/Users/sukduoasa/Documents/widget`

集成分支：`codex/app-store-v1.0.0a`

新 Codex 项目工作区：`/Users/sukduoasa/Documents/QuotaView-AppStore`

新 Codex 项目分支：`codex/appstore-runtime-spike`

当前稳定发布提交与 App Store 代码基座：
`3119171f45163fe45d68a4f774a0488968f14fd7`

远程：`https://github.com/Duoasa/QuotaView.git`

当前进行中的 App Store 适配：

| 项目 | 当前值 |
|---|---|
| 内部发行代号 | `QuotaView v1.0.0a` |
| App Store 版本 | `1.0.0 (Build 1)` |
| 发布渠道 | `appstore` |
| 基座 | `0.3.1 (Build 2)` / `v0.3.1-build.2` |
| 当前规格 | `QV-APPSTORE-RELEASE-1.0.0-001` |
| 交付状态 | `Implementing` |
| 发布状态 | 尚未提交 App Review，尚未发布 |
| 当前验证 | 额度重置移除后 `swift test` 53 项及 Universal Release 通过；版本、渠道、架构与资源检查通过 |
| 产品验收 | 通用页版本展示与移除重置后的 `373 pt` 主面板等待产品所有者运行确认 |

规格入口：
[docs/specs/README.md](docs/specs/README.md) →
[App Store 发行适配规格](docs/design/quotaview-app-store-release-1.0.0.md)。

新 Codex 项目的可执行交接入口：
[docs/specs/APPSTORE_CODEX_PROJECT_HANDOFF.md](docs/specs/APPSTORE_CODEX_PROJECT_HANDOFF.md)。

Codex 灵动岛 App Store 沙盒迁移的从属实施规格：
[docs/design/quotaview-app-store-codex-island-plugin-bridge.md](docs/design/quotaview-app-store-codex-island-plugin-bridge.md)。

基础额度与 OpenAI 登录 App Store 沙盒迁移的从属实施规格：
[docs/design/quotaview-app-store-codex-account-runtime.md](docs/design/quotaview-app-store-codex-account-runtime.md)。

2026-08-06：用户接受 App Store 版本使用最小 OpenAI 账户接入。基础额度不
依赖灵动岛插件，改由 App Bundle 内固定版本、Universal、签名并继承沙盒的
OpenAI Codex App Server Runtime 通过官方 ChatGPT Device Code 获取；凭证
由 Runtime 保存在 macOS Keychain，不进入 Swift 状态、UserDefaults、App
Group、日志、Widget 或 QuotaView 自有服务器。Runtime 使用独立容器 Home，
不读取外部 `~/.codex`、项目、Prompt、线程或工具输出，并使用严格账户与
额度 RPC 白名单。该方案已经固化但尚未开始源码实施，必须先通过 Runtime、
登录、Keychain、真实额度一致性、双架构、进程回收和 App Store Archive
技术 Spike。

版本管理建议已经写入账户 Runtime 规格：为 App Store 创建独立 Codex
项目/任务和同一 `Duoasa/QuotaView` 仓库的独立 Git worktree，不复制第二个
QuotaView 主应用仓库；灵动岛插件继续使用独立仓库和独立版本。本轮交接目标
为 `/Users/sukduoasa/Documents/QuotaView-AppStore` 与
`codex/appstore-runtime-spike`；长期 `appstore/main` 分支和插件仓库仍未
创建，必须在对应门禁满足后另行确认。

2026-08-06：用户接受 Git Marketplace 双通道插件桥接方案。Preview 阶段
由公开 Git 仓库分发 `QuotaView for Codex` 配套插件，未来公共目录版本从
同一插件源码和协议发布；QuotaView 只通过用户选择目录的只读
security-scoped bookmark 消费插件 `PLUGIN_DATA` 中的脱敏事件。详细阶段、
删除边界、协议、验收与回滚要求已经固化，但尚未开始源码实施；当前
`ENABLE_APP_SANDBOX = NO`、旧 Hook/Helper/Expect/Socket 链路和其他外部
`Process` 阻断项仍未整改，不能据此声称可提交 App Review。

2026-08-05：用户明确授权 App Store `1.0.0` 移除额度重置功能。当前分支已
删除主面板入口、重置详情页、最终确认层、对应设置、Demo 执行器、Widget
快照字段、Probe 输出和专用资源；“下次重置”倒计时与普通 Credits 余额
继续保留为只读信息。源码残留搜索与 `swift test` 共 53 项通过；无签名
Universal Xcode Release 构建通过，App、Widget、Framework 与 Helper 均为
`x86_64 arm64`，产物为 `1.0.0 (Build 1)` / `appstore`，已编译资源与二进制
无额度重置入口残留。

## 0. 版本定位入口

公开发布版本的唯一索引位于：

**[VERSION_HISTORY.md → 当前最新版本](VERSION_HISTORY.md#当前最新版本)**

当前公开 Latest 为：

| 项目 | 当前值 |
|---|---|
| 最新推荐版本 | `0.3.1 (Build 2)` |
| tag | `v0.3.1-build.2` |
| 发布提交 | `3119171f45163fe45d68a4f774a0488968f14fd7` |
| Release | [QuotaView 0.3.1 Build 2 — Widget Hotfix](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1-build.2) |
| 资产 | `QuotaView-v0.3.1-build.2.zip` |
| SHA-256 | `9051b60799a5a20e578c2eea4e3f3a5b3725109b553fc8580473953c0f59a1ed` |

`0.3.1 (Build 2)` 已完成 Developer ID 签名、Apple 公证、Staple、
GitHub Release、Latest 切换和 GitHub 回下载复核，是当前公开生产基线和
本轮 App Store 适配的不可移动代码基座。

2026-08-01：`0.3.1 (Build 2)` Widget 热修复已完成实现、安装验证和正式
发布。macOS
系统日志确认，公开 Build 1 的 Widget 在 Developer ID 直接分发环境中被
`SystemPolicyAppData` 拒绝读取 `group.com.quotaview.shared`。Build 2 将
App Group 迁移为团队前缀 `BUUH229D5Q.com.quotaview.shared`，符合未嵌入
provisioning profile 的公证 App 共享容器要求。`swift test` 共 `53` 项
通过，Universal Release 构建和 Developer ID 签名验证通过；App、Widget
与 Helper 均为 `x86_64 arm64`。安装后新容器写入有效快照，Widget 时间线
成功归档，内核不再出现共享快照读取拒绝；视觉结果等待产品所有者验收。
正式发布资产已完成 Apple 公证、Staple、GitHub 上传和回下载复核。

Build 2 将主面板与 Widget 的额度标题从“本周剩余”统一调整为“本周期
剩余”，英文使用两词 `Period Remaining`，以兼容 Codex 的 5 小时、7 天
及后续可变用量周期；Tooltip、VoiceOver 与实现内部命名同步使用周期语义。

### 0.3.1 Build 2 发布归档

目标发布元数据：

| 项目 | 发布值 |
|---|---|
| Marketing Version | `0.3.1` |
| Build Number | `2` |
| tag | `v0.3.1-build.2` |
| Release 标题 | `QuotaView 0.3.1 Build 2 — Widget Hotfix` |
| 最终资产名 | `QuotaView-v0.3.1-build.2.zip` |
| App Group | `BUUH229D5Q.com.quotaview.shared` |
| 最低系统版本 | macOS 14 |
| 架构 | Universal `arm64 + x86_64` |

正式发布资产：

| 项目 | 当前值 |
|---|---|
| 文件 | `dist/QuotaView-v0.3.1-build.2.zip` |
| 大小 | `11,443,325 bytes` |
| SHA-256 | `9051b60799a5a20e578c2eea4e3f3a5b3725109b553fc8580473953c0f59a1ed` |
| 签名 | `Developer ID Application: Chenchen Xu (BUUH229D5Q)`，Hardened Runtime |
| 公证 | Apple Accepted，已 Staple；Submission `0ff9bf81-3570-4243-b3be-5d076b0f888c` |

正式 ZIP 已在全新目录解压、附加隔离属性并通过
`codesign --verify --deep --strict`、`stapler validate`、`spctl`、版本、
架构、资源与真实启动烟雾测试；App、Widget 与 Helper 均包含
`x86_64 arm64`，App 与 Widget entitlement 均包含团队前缀 App Group。

GitHub Release Notes 使用以下单份英文源正文；GitHub 界面负责翻译：

```markdown
QuotaView 0.3.1 Build 2 is a focused hotfix for WidgetKit data sharing and
variable Codex quota periods.

## Fixed

- Restored Small and Medium widget data for notarized direct downloads by
  migrating the shared container to the team-prefixed App Group
  `BUUH229D5Q.com.quotaview.shared`.
- Renamed “Weekly Remaining” to “Period Remaining” so the interface works for
  5-hour, 7-day, and future variable quota periods. The Simplified Chinese
  title is now “本周期剩余”.
- Added a release packaging check that rejects a non-team-prefixed App Group
  unless the app embeds a provisioning profile.

## Requirements

- macOS 14 or later
- A Codex version with Hooks support
```

Build 2 发布检查清单：

- [x] 源码、App 与 Widget 版本统一为 `0.3.1 (Build 2)`；
- [x] App Group 迁移为 `BUUH229D5Q.com.quotaview.shared`，并加入打包门禁；
- [x] 主面板与 Widget 使用“本周期剩余” / 两词 `Period Remaining`；
- [x] `swift test` 53 项通过，0 失败；
- [x] Universal Xcode Release 构建通过；
- [x] Developer ID 本地候选签名、全新解压验签、版本、架构、资源和
  entitlement 检查通过；
- [x] 新共享容器写入有效快照，Widget 时间线成功归档，内核没有新的
  `SystemPolicyAppData` 读取拒绝；
- [ ] 产品所有者确认小号 / 中号、深色 / 浅色和中英文最终视觉；
- [x] 使用 `NOTARY_PROFILE` 生成无 `candidate` 后缀的最终资产，完成 Apple
  公证与 Staple；
- [x] 对最终 ZIP 全新解压并执行 `codesign`、`stapler`、`spctl`、版本、
  架构、资源、隔离属性和真实启动烟雾测试；
- [x] 将最终资产大小、SHA-256 和 Submission ID 同步到本文件；发布提交、
  `VERSION_HISTORY.md` 与 README 中英文版本待 Release 建立后同步；
- [ ] 创建发布提交，使用唯一 tag `v0.3.1-build.2`，上传唯一正式 ZIP，
  将 GitHub Latest 切换到 Build 2；
- [ ] 从 GitHub 回下载资产，逐字节核对并再次验签和启动测试。

2026-08-01：宣传片摄录专用的本地 `0.3.2 Demo` 已结束使用；灵动岛已
恢复为完成后 `20` 秒紧凑、
完成满 `120` 秒隐藏的正式时序。摄录 ZIP 仅作为本地产物保留，不属于当前
源码版本，也没有 tag、Release 或 GitHub Latest。恢复后 `swift test` 共
`52` 项通过、`0` 项失败；Universal Xcode Release 无签名构建通过，App、
Widget 与 Helper 均包含 `x86_64 arm64`。视觉与实机时序等待产品所有者验收。

文档职责：

- `HANDOFF.md`：当前开发状态、验证结论和发布入口；
- `VERSION_HISTORY.md`：公开版本、tag、Release、资产与撤回记录；
- `AGENTS.md`：长期产品、设计、实现和发布约束；
- `design-qa.md`：视觉验收历史。

## 1. 0.3.1 正式发布状态

### 版本定位

| 项目 | 当前值 |
|---|---|
| Marketing Version | `0.3.1` |
| Build Number | `2` |
| 开发主题 | Codex 灵动岛 + Widget 共享容器热修复 |
| 发布状态 | 正式 Release、Latest、非 Draft、非 Pre-release |
| 公开 Latest | `0.3.1 (Build 2)` |

### 已实现

- 将独立 Metal Demo 重构进 QuotaView 主 App，不再依赖 Debug 控制器；
- 使用 Codex 官方 Hooks 覆盖 `SessionStart`、`SessionEnd`、
  `UserPromptSubmit`、工具、批准、上下文压缩、子任务和 `Stop` 事件；
- 新增独立签名辅助程序 `QuotaViewActivityHook`，嵌入
  `Contents/Helpers`；
- 辅助程序只转发哈希会话标识、工作区末级名称、事件、工具类别、
  SessionStart 来源与时间，不转发提示词、命令、参数、输出或记录路径；
- 主 App 优先通过权限为 `0600`、带随机令牌的 Unix Socket 接收脱敏
  事件；当 Codex 沙盒拒绝 Unix Socket 时，Helper 自动回退到当前用户
  独占的 `/tmp` 原子文件队列，目录权限为 `0700`、事件文件为 `0600`，
  主 App 仍执行随机令牌、文件所有者、类型、大小与时效校验；
- 通过 App Server `thread/list` 匹配当前会话名称；界面不展示
  `thread.preview`；
- 实现最大态、紧凑态和隐藏三阶段状态机：完成后 20 秒紧凑，完成满
  120 秒隐藏，新事件立即重新展开；
- 保留 Demo 中已确认的 Metal 流体球、状态配色、上下文白色挤压、
  三行真实字形居中、尾部缩略和操作文案扫光；
- 新增设置页一键安装编排：检测 Codex 版本与 Hooks 功能，必要时执行
  官方 `codex features enable hooks`，更新固定路径 Helper，合并用户级
  Hook，并自动打开 Codex CLI；用户等待 CLI 首次加载完成，等待
  QuotaView 自动输入 `/hooks` 并进入 Hooks 页面后再按 `T`，随后
  QuotaView 自动识别确认结果并关闭临时 CLI；
- 设置页改为新手向单步引导，默认隐藏 Codex 版本、Hooks、本地桥接和
  诊断路径等技术信息；
- 用户点击“连接 Codex”时立即显示最大态“未连接 Codex”，不再等待安装
  或首个 Hook；完成信任、重启并收到第一条真实 `UserPromptSubmit` 后，
  自动切换为真实活动状态；
- 连接状态拆分为未安装、已安装等待重启、等待信任、等待首个事件、
  已连接和连接异常；只有当前固定 Hook 定义产生的第一条真实
  `UserPromptSubmit` 才建立“已连接”证据；
- 打开审查页时记录 Codex Desktop 进程标识，重启前丢弃设置 CLI 产生的
  事件，避免首次配置过程被误判为已连接；
- 安全确认启动器不再使用固定延迟或输入提示符单一信号，而是等待输入
  提示符出现且终端输出连续稳定 3 秒后发送 `/hooks`；审查页未出现时
  有界重试，官方“Trust all”页面出现前不转发用户按键；
- 用户实际按下 `T` 且 Codex 输出确认结果后，启动器通过权限隔离的本地
  信号通知 QuotaView；设置页自动进入“等待重启”，并提供一次
  “重新启动 Codex”操作；
- 桥接消息同时校验随机令牌与固定命令派生的安装标识，旧 Codex 进程或
  旧 Helper 的残留事件不能越过重启/信任门禁；
- Helper 固定安装到
  `~/Library/Application Support/QuotaView/Helpers/QuotaViewActivityHook`，
  后续应用移动或常规升级不改变 Hook 命令路径；已启用用户在后续启动时
  自动更新 Helper 和校正配置；
- Hook 安装保留既有配置并创建备份；配置结构无效时拒绝覆盖；QuotaView
  自动进入 Codex `/hooks` 页面，但不会代替用户按 `T` 或绕过信任；
- Helper 连接失败时同时写入统一日志和权限隔离的本地诊断日志，内容只含
  时间、错误代码与回退结果，不含会话或任务业务数据；
- App、Widget、Helper 和设置中的 Marketing Version 已更新为
  `0.3.1`，Build Number 保持 `1`。

产品与实现依据：

- [Codex 灵动岛产品文档](docs/design/quotaview-codex-activity-widget-product.md)
- [OpenAI Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [OpenAI Codex App Server](https://learn.chatgpt.com/docs/app-server)

### 当前验证

- `swift test`：52 项通过，0 失败；
- 无签名 Universal Xcode Release 构建通过；
- App、Widget Extension 与 `QuotaViewActivityHook` 均为
  `x86_64 arm64`；
- 最终 App Bundle 中 Helper 位于
  `Contents/Helpers/QuotaViewActivityHook`；
- App 为 `0.3.1 (1)`；
- `AppIcon.icns`、`Assets.car` 与 Asta Sans 字体均存在；
- `scripts/build-app.sh` 语法检查通过，并已加入 Helper 签名、Hardened
  Runtime 与 Universal 架构门禁；
- 正式发布包已使用
  `Developer ID Application: Chenchen Xu (BUUH229D5Q)` 签名并启用
  Hardened Runtime；Apple 公证状态为 `Accepted`，Submission ID 为
  `2b125886-a3dc-4734-a139-280a08302e5c`，App 已完成 Staple；
- 正式资产为 `QuotaView-v0.3.1.zip`，大小
  `11,443,295 bytes`，SHA-256
  `ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d`；
- 最终 ZIP 全新解压后通过 `codesign --verify --deep --strict`、
  `stapler validate` 与 `spctl --assess`；加入下载隔离属性后 Gatekeeper
  返回 `accepted / source=Notarized Developer ID`，真实启动烟雾测试
  持续 5 秒；
- Hook 映射、压缩恢复、事件乱序、20 秒 / 120 秒收起、Codex 环境检测、
  必要时启用 Hooks、固定路径 Helper、重复安装、卸载、既有配置保留、
  无效配置拒绝、真实 `UserPromptSubmit` 连接门禁、重启前设置 CLI 事件
  拒绝、私有启动器真实 PTY `/hooks` 输入、CLI 首次加载与输出稳定等待、
  审查页有界重试和文件队列令牌校验均有自动化测试；
- 真实 `codex exec` 临时会话已触发
  `SessionStart → UserPromptSubmit → Stop`，所有 Hook 均返回 Completed；
- 已从系统 Sandbox 日志确认旧故障是 Helper 访问 Unix Socket 被
  `deny network-outbound`，本轮文件队列回退不要求扩大 Codex 权限，也
  不改变现有 Hook 命令，因此无需重新安装或重新信任；
- 临时虚拟数据、自动展开、自动点击、截图与 UI QA 入口搜索无匹配；
- `git diff --check` 通过。

产品所有者已确认：

- 当前新手向设置流程“比较完整”，可以作为 `0.3.1` 发布候选的功能流程
  基线；
- 流程包含点击连接后立即出现“未连接 Codex”，明确引导等待 CLI 首次加载、
  等待自动输入 `/hooks` 并进入 Hooks 页面后再按 `T`，以及重启与首个
  真实 `UserPromptSubmit` 变为“已连接”。

以上确认只表示设置流程方向与完整性得到认可，不替代正式发布包的最终
实机烟雾测试，也不代表以下视觉、语言与辅助功能矩阵已经通过。

等待产品所有者验收：

- 新手向“Codex 灵动岛”设置页六种连接状态的最终布局、折叠详情、长文案
  适配和按钮交互；
- 完成后 20 秒进入紧凑态、完成满 120 秒隐藏的实机时序；
- 最大态 / 紧凑态的最终视觉、居中、截断和过渡；
- 各状态颜色、流体速度与上下文压缩效果；
- 简体中文 / English；
- Reduce Motion / Increase Contrast / VoiceOver。

### GitHub 发布完成

2026-07-30 已通过 GitHub 远端核对：

- GitHub Latest 为 `v0.3.1`，非 Draft、非 Pre-release；
- `v0.3.1` tag 精确指向
  `041c698ae9755d458fa9f111e4ac74e9711048b9`；
- Release 只有正式资产 `QuotaView-v0.3.1.zip`，大小
  `11,443,295 bytes`；
- README 中英文下载入口均指向 `v0.3.1`，Codex 灵动岛截图位于更新说明
  开头。

实际 GitHub Release 元数据：

| 项目 | 发布值 |
|---|---|
| Tag | `v0.3.1` |
| Release 标题 | `QuotaView 0.3.1 — Codex Island` |
| Release 类型 | 正式 Release、Latest、非 Draft、非 Pre-release |
| 目标提交 | `041c698ae9755d458fa9f111e4ac74e9711048b9` |
| Release URL | <https://github.com/Duoasa/QuotaView/releases/tag/v0.3.1> |
| 上传资产 | `QuotaView-v0.3.1.zip` |
| 最终大小 / SHA-256 | `11,443,295 bytes` / `ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d` |
| 公证 | Apple Accepted，已 Staple；Submission `2b125886-a3dc-4734-a139-280a08302e5c` |

GitHub Release Notes 使用以下单份英文源正文；GitHub 界面负责翻译，不再
额外维护一份中文 Release 正文：

```markdown
QuotaView 0.3.1 introduces Codex Island, a native macOS activity surface that
shows Codex status with a live Metal-rendered fluid sphere.

## What's new

- Added expanded, compact, and hidden Codex Island states with smooth
  transitions and status-specific motion and color.
- Added live Codex lifecycle tracking through official Hooks, including tool
  use, permission requests, context compaction, subagents, completion, and
  failures.
- Added a guided one-click setup flow in Settings. QuotaView installs and
  updates its fixed-path helper, preserves existing hooks, opens the official
  `/hooks` review page, and asks for the one trust confirmation required by
  Codex.
- Added clear connection states, immediate “Codex not connected” feedback,
  automatic restart guidance, and real-event verification before reporting a
  successful connection.
- Codex Island compacts 20 seconds after completion and hides after 2 minutes;
  new activity expands it immediately.

## Privacy and security

QuotaView forwards only a hashed session identifier, the last workspace path
component, event type, coarse tool category, session source, and timestamp. It
does not collect prompts, commands, arguments, tool output, or transcript
paths. Hook trust is never bypassed.

## Requirements

- macOS 14 or later
- A Codex version with Hooks support

SHA-256:
`ff2417f40c8d5ad9e12c4c3c42101fb3e12e9e04c137c1bc6a42e2b56bf50e2d`
```

发布检查清单：

- [x] 版本号为 `0.3.1 (Build 1)`；
- [x] `swift test` 52 项通过；
- [x] Universal App、Widget、Helper 与 Framework 均包含
  `x86_64 arm64`；
- [x] Developer ID 签名与 Hardened Runtime 已通过全新解压验证；
- [x] 产品所有者认可当前设置流程完整性；
- [x] 审查工作区提交范围；Prototype、参考文档和其他用户资料未纳入；
- [x] 产品所有者明确要求发布 0.3.1；剩余视觉矩阵仍等待逐项验收，不
  提前记录为“已通过”；
- [x] 使用 `NOTARY_PROFILE` 重新构建，完成 Apple 公证与 Staple；
- [x] 对最终 ZIP 全新解压并完成 `codesign`、`stapler`、`spctl`、版本、
  架构、资源和真实启动烟雾测试；
- [x] 更新本节最终资产大小与 SHA-256；
- [x] 创建发布提交并推送，确认 tag 精确指向该提交；
- [x] 创建 `v0.3.1` Release，上传唯一最终 ZIP，并设为 Latest；
- [x] 同步 README 中英文下载入口、`VERSION_HISTORY.md` 与本文件的公开
  Latest；
- [x] 从 GitHub 回下载资产，逐字节核对并再次执行验签和启动测试。

0.3.1 已通过 PR [#12](https://github.com/Duoasa/QuotaView/pull/12)
合并并正式发布。GitHub 回下载资产与本地最终 ZIP 逐字节一致；回下载 App
通过签名、公证、Gatekeeper 和 5 秒真实启动复核。

## 2. 0.2.1 正式发布

### 版本与目标

| 项目 | 当前值 |
|---|---|
| Marketing Version | `0.2.1` |
| Build Number | `1` |
| 最低系统版本 | macOS 14 |
| App Bundle ID | `com.quotaview.menubar` |
| Widget Bundle ID | `com.quotaview.menubar.widget` |
| App Group | `group.com.quotaview.shared` |
| 架构 | Universal `arm64 + x86_64` |
| Development Team | `BUUH229D5Q` |
| 发布状态 | 正式 Release、Latest、非 Draft、非 Pre-release |
| Git tag | `v0.2.1` |
| Release 资产 | `QuotaView-v0.2.1.zip` |
| 资产大小 | `10,907,231 bytes` |
| SHA-256 | `99e7fb951d4abd6475204c059f1e16481dac8be4c3b72e6b19889fc54737521b` |

### 关键更新

- 新增原生 WidgetKit 扩展，支持 macOS 小号与中号小组件；
- 主 App 通过 App Group 原子写入最小、脱敏且带过期时间的快照，Widget
  只读快照，不直接访问网络、凭据或 Codex App Server；
- 小组件接入真实额度、重置时间、Credits、今日 Token、累计 Token、
  订阅方案和连接状态；缺失、错误或过期时显示不可用和破折号，不伪造
  `0%`；
- 按 Figma 节点 `34:1846` 完成小号/中号、深色/浅色 Widget UI，并修复
  SwiftUI 紧行高导致 Asta Sans 字号被二次缩小的问题；
- 按 Figma 节点 `1:704` 更新状态栏菜单 UI、进度条、连接状态和局部
  Liquid Glass；
- 订阅方案统一映射为 OpenAI 官方名称，未知协议值显示破折号；
- 恢复 Apple 正式开发环境：主 App 与 Widget 使用 Automatic Signing、
  正式 App Group entitlement 和各自的显式 App ID；
- 构建脚本已覆盖嵌套 Widget Extension 的签名、版本、Bundle ID、架构、
  extension point、sandbox 与 App Group 校验。

### 产品与安全边界

- 当前功能保持只读；
- Widget 快照不得包含认证 Token、Cookie、账号标识、完整响应或历史明细；
- Widget 不得自行启动 Codex App Server；
- 额度重置仍为本地 Demo，不得调用
  `account/rateLimitResetCredit/consume`；
- Release 构建不得包含调试虚拟数据、自动展开、自动点击、截图或 UI QA
  入口。

## 3. 0.2.1 验证状态

已完成：

- `swift test`：33 项通过，0 失败；
- Apple Development Xcode Debug 构建通过，主 App 与 Widget 的开发
  Profile 均包含 `group.com.quotaview.shared`；
- 无签名 Universal Xcode Release 构建通过；
- App、`QuotaViewCore.framework` 与 Widget Extension 均为
  `x86_64 arm64`；
- App 与 Widget 均为 `0.2.1 (1)`；
- Widget Extension 包含 `Assets.car`、Asta Sans 字体和简体中文资源；
- `codesign --verify --deep --strict` 已在开发构建链路通过；
- 产品所有者已确认主 App 写入、Widget 读取和 timeline 刷新成功；
- 临时虚拟数据、真实额度消费调用和 UI QA 入口搜索无匹配。
- GitHub Actions 33 项测试通过；
- 最终 App、Framework 与 Widget 使用 Developer ID 签名并启用
  Hardened Runtime；
- Apple notarization 返回 `Accepted`，Submission ID 为
  `e211abde-be96-47eb-a5ca-50ec1df7f260`；
- App 已 Staple，`stapler validate` 与 `spctl` 均通过；
- 全新解压和 GitHub 回下载资产均通过 `codesign --verify --deep --strict`；
- GitHub 回下载 ZIP 与本地最终包逐字节一致；
- 加入下载隔离属性后 Gatekeeper 仍返回
  `accepted / source=Notarized Developer ID`；
- GitHub 回下载 App 的真实启动烟雾测试持续 5 秒，没有发现
  Framework 加载、签名或 `fatalDyldError`。

等待产品所有者验收：

- 小号 / 中号；
- 浅色 / 深色；
- 简体中文 / English；
- Increase Contrast / Reduce Motion / VoiceOver；
- 菜单与 Widget 的最终视觉、Hover、Pressed、Disabled 和键盘交互。

视觉与交互矩阵在用户明确确认前不得记录为“已通过”。

## 4. 0.2.1 发布完成状态

钥匙串中已确认存在：

- `Apple Development: Chenchen Xu (Z6X48CV8PX)`；
- `Apple Distribution: Chenchen Xu (BUUH229D5Q)`；
- `Developer ID Application: Chenchen Xu (BUUH229D5Q)`。

已完成：

1. PR [#9](https://github.com/Duoasa/QuotaView/pull/9) 经 GitHub Actions
   验证后合并；
2. 发布提交为
   `56aa71dd9f4013412f90c75e0c282a610e87d14e`；
3. `v0.2.1` tag 与正式 GitHub Release 已创建并设为 Latest；
4. `QuotaView-v0.2.1.zip` 已使用 Developer ID 签名、完成 Apple 公证与
   Staple；
5. Release Notes 只保留一份英文源正文；
6. README 中英文下载入口和产品预览图已更新；
7. GitHub 回下载、SHA-256、签名、公证、Gatekeeper 与真实启动复核完成。

正式 Release：

<https://github.com/Duoasa/QuotaView/releases/tag/v0.2.1>

此前生成的 ad-hoc `0.2.1 Build 1` ZIP 早于最终 Widget UI，不是正式发布
资产，后续不得替换当前 Release。

如 Marketing Version 保持 `0.2.1` 但需要发布热修复，必须增加 Build
Number，并为 tag 和 ZIP 加入唯一 Build 标识。

## 5. 0.2.1 实现边界

数据链路：

```text
CodexProviderAdapter
→ CodexStatusStore
→ sanitized WidgetSnapshot JSON
→ group.com.quotaview.shared
→ QuotaViewWidgetExtension
```

实现约束：

- 主 App 是唯一数据获取方；
- Widget 快照默认 15 分钟过期，timeline 最短 5 分钟重新读取；
- 主数据刷新、可用状态或语言变化时更新快照；
- 可选 Credits 或 Token 数据缺失不能覆盖有效额度状态；
- 主面板继续使用 Asta Sans，设置窗口继续使用系统字体；
- 菜单与 Widget 的详细视觉令牌以 `AGENTS.md` 和对应 Figma 节点为准；
- 不增加第二层主面板玻璃，不接入真实额度重置接口。

## 6. Git 工作区

0.3.1 源码、测试、README、灵动岛截图和产品文档已通过 PR
[#12](https://github.com/Duoasa/QuotaView/pull/12) 合并，发布 tag 指向：

```text
041c698ae9755d458fa9f111e4ac74e9711048b9
```

以下未跟踪 Prototype 与参考资料未进入 0.3.1 发布提交，所有权和后续提交
范围仍未确认，默认不得擅自纳入：

```text
Prototypes/
docs/reference/
quotaview-blurred-gradient-background-2k.png
subtract-frosted-glass-icon-transparent.png
subtract-frosted-glass-icon.png
```

不得使用 `git clean`、`git reset --hard` 或 `git checkout --` 清理用户
文件。

## 7. 发布门禁

发布前至少执行：

```bash
swift test

rg -n \
  'DEBUG-ONLY-MOCK|DEBUG MOCK|DEBUG ONLY|仅用于调试|debugResetCreditOverride|displayAvailableResetCredits' \
  Sources Tests

rg -n 'account/rateLimitResetCredit/consume' Sources Tests

git diff --check
git diff --cached --check
git status --short --branch
```

正式签名、公证和打包：

```bash
CODESIGN_IDENTITY="Developer ID Application: Chenchen Xu (BUUH229D5Q)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

发布产物至少检查：

```bash
codesign --verify --deep --strict --verbose=4 QuotaView.app
spctl --assess --type execute --verbose=4 QuotaView.app
lipo -archs QuotaView.app/Contents/MacOS/QuotaView
lipo -archs \
  QuotaView.app/Contents/PlugIns/QuotaViewWidgetExtension.appex/Contents/MacOS/QuotaViewWidgetExtension
```

仅验签不足以证明可发布。必须全新解压并进行真实启动测试；发布后还要从
GitHub 回下载再次验证。

## 8. 文档联动

0.3.1 已在同一发布任务内完成：

1. 将 `VERSION_HISTORY.md#当前最新版本` 更新为 0.3.1；
2. 在版本总览和版本详情中记录 tag、发布提交、Release URL、资产名、
   大小、SHA-256、签名、公证和验证结论；
3. 将本文件的版本入口、发布、验证与完成状态由候选状态更新为发布事实；
4. 更新 README 中英文下载入口、Codex 灵动岛重点文案和预览图；
5. 确认 GitHub Release Notes 只有一份英文源正文；
6. 确认已撤回的 `0.2.0 Build 3` 不会重新成为下载或开发基线。

README 下载入口、GitHub Latest 和
`VERSION_HISTORY.md#当前最新版本` 当前均指向 `v0.3.1-build.2`。已撤回的
`0.2.0 Build 3` 继续只保留历史记录，不得恢复为下载或开发基线。
