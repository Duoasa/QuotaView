# Claude Code 支持

文档编号：`QV-PRODUCT-CLAUDE-CODE-001` · 状态：`Accepted / Verifying` · 起始：2026-10-07

来源：用户要求按 `PLAN-claude-code-support.md`（2026-10-07 草案）为 QuotaView 加入
Claude Code 全功能支持。本规格记录目标、边界与证据；实现位于本节列出的文件。

## 目标

- 灵动岛显示 Claude Code 会话：标题、模型、过程、工具输出、Token、完成/中断/失败。
- Claude Code 权限请求可在灵动岛处理（允许一次、本会话允许、始终允许、拒绝、取消；
  AskUserQuestion 单选问题可直接回答）；任何失败回落到终端原生确认。
- 用量页可在 Codex / Claude Code 间切换：官方 5 小时 / 每周窗口（状态栏，可选）与本机
  会话记录统计的每日 Token、按模型公开单价估算的成本。
- 设置新增「Claude Code 连接」页：启用开关、灵动岛审批开关、官方用量窗口开关。

## 非目标

- 不内置 Claude 官方标识（卡片用 SF Symbol `asterisk` 占位）。
- 不定位或激活运行 Claude Code 的终端窗口；只提示用户切回终端。
- 多选 AskUserQuestion、被截断的工具输入不在灵动岛作答，只显示只读提醒。
- 不改变 Codex 的任何连接、审批或用量行为。

## 架构

| 层 | 文件 | 职责 |
|---|---|---|
| Helper | `Sources/QuotaViewActivityHook/ClaudeCodeHookMode.swift` | `--claude-code` 转发有界 Hook 输入；PermissionRequest 等待岛上决定；`--claude-statusline` 记录 `rate_limits` 并转发原状态栏 |
| Core | `ClaudeCodePricing.swift` / `ClaudeCodeTranscript.swift` / `ClaudeCodeUsage.swift` | 公开单价、会话记录有界解码与增量 tail、每日用量扫描、状态栏快照解码 |
| App | `ClaudeCodeBridge.swift` | 私有 Unix socket（0600），一行 JSON 请求；PermissionRequest 连接保持到应答或 helper 退出 |
| App | `ClaudeCodeInstaller.swift` | 写 `settings.json`（尊重 `CLAUDE_CONFIG_DIR`、首次备份、锁 + 修订校验），按「本通道 helper 路径 + Claude 模式参数」识别自有条目，保存并恢复原 statusLine |
| App | `ClaudeCodeRuntime.swift` / `ClaudeCodeApproval.swift` | 事件 → 灵动岛投影、回合划分、会话记录 tail、审批映射、用量发布 |
| UI | `ClaudeCodeSettingsView.swift`、`IslandConceptBoard.swift`、`IslandApproval.swift`、`IslandTaskDetail.swift` | 设置页、用量切换、按 provider 的文案与图标 |

Socket 协议：请求 `{authenticationToken, eventID, kind: hook|statusLine, awaitDecision, payload}`；
普通应答 `{eventID, accepted: true}`；需等待时先回 `{…, pending: true}`，之后
`{eventID, decision: {behavior: allow|deny, updatedInput?, updatedPermissions?, message?, interrupt?}}`。
连接无决定关闭即交回终端。

## 不变量

1. 会话 key = hash(`claude-code:` + session_id)，回合 key 由 App 在 UserPromptSubmit
   （或无提交时的首个活跃事件）铸造，不与 Codex 冲突，不依赖 prompt_id。
2. Claude 请求 `rpcEpoch 0`、id `claude:<eventID>`、`params.claudeCode = true`；只经
   `claudeRespond` 应答。Codex App Server 断线（`invalidateResponses`）和 Codex 连接纪元
   不影响 Claude 请求。
3. 灵动岛无法作答的请求（多选、截断输入、关闭审批开关）立即放行 Hook，不让 Claude Code
   等待只读请求。一般 helper 断开、对应工具结果、回合结束或中断撤下请求；关闭审批主动交回终端时保留只读提醒，直到真实结果或终态。
4. 中途接入只回放会话记录最近 1 MiB 中最后一次真实提问之后的记录；更早回合的回答、
   中断标记不进入当前卡片。标题顺序：custom-title > 首条用户提问 > 工作目录。
5. 用量按 `message.id + requestId` 跨文件去重；某天含无公开单价模型时该天成本为空，
   不用通用估算替代；未知值显示占位符。
6. 停用只移除本通道的 Hook 与状态栏条目并恢复原状态栏；其他工具的 Hook 原样保留。
   无法完整解析的 `settings.json` / `hooks` 不写入。

## 状态与失败语义

设置页状态：已停用 / 配置中 / 已配置（等待新会话）/ 已连接（本次运行收到事件）/ 需要处理
（写入失败、helper 缺失、socket 失败，可重试）。App 未运行时 helper 连接失败即静默退出，
Claude Code 行为不变；状态栏 helper 仍转发原状态栏输出。

## 生命周期与审批开关修订 · 2026-10-08

- 停止后再次启动重建监听；取消未开始的配置任务，已经开始的文件事务串行完成，旧修订结果不能覆盖新状态；取消用量刷新后禁止迟到回写。
- 停用清理失败显示失败与重试，完成清理才显示已停用；重新启动按当前关闭配置移除本通道遗留项。
- 关闭审批立即撤销应答能力，无决定释放挂起 helper 并保留只读终端提醒；旧 route 的迟到请求同样回退，再次开启不重新接管旧请求；真实工具结果/终态清理提醒。
- 本轮 19 项隔离冒烟、0 失败，Debug arm64 编译通过并已更新开发包；真实 Claude 会话与多个 PermissionRequest Hook 并存仍待用户验收。当前运行与证据见 [Handoff](../../HANDOFF.md)。

## 原适配工作区验证记录（迁入前，2026-10-07）

- Helper：SwiftPM 与 Xcode `QuotaViewActivityHook` 构建通过；模拟 socket 冒烟确认普通事件
  静默转发、PermissionRequest 输出 `hookSpecificOutput.decision`、状态栏写快照并转发、
  权限不安全/缺失的 route 静默退出。
- 协议核对：本机 Claude Code 2.1.292 二进制包含所用事件名与字段；`rate_limits.*.used_percentage`
  / `resets_at`（秒）、PermissionRequest 决定 schema（deny 需 message）与 AskUserQuestion
  `answers`（问题文本 → 答案）与实现一致。
- 真实数据只读探针：本机 `~/.claude/projects` 1,146 行解码，3 个模型均有单价，扫描 0.75 秒。
- 新增 `ClaudeCodeSupportTests` 15 项（单价、解码、tail、扫描去重、状态栏、安装/恢复、
  无效设置拒写、审批映射与决定、Claude/Codex 传输隔离、只读请求、bridge 持有/应答/断开、
  Runtime 端到端）；SwiftPM 全量见 Handoff；Xcode Debug arm64 构建通过。
- 未完成：真实 Claude Code 会话中的灵动岛显示、岛上审批与状态栏刷新的人工验收；
  与其他同时注册 PermissionRequest Hook 的工具并存时的先后行为未验证。

## 发行基线迁入（2026-10-07）

用户要求以 0.7.7 Build 1 为基线，只迁入 Claude 适配；既有设置/卡片界面修改保留。
原工作区依赖审计分支，此处已移除这些依赖：

- `RequestLifecycle` 保持在 `IslandLiveStore.swift`，只增加 Claude 独立应答能力与 Codex 断线隔离。
- 渲染 provider/用量字段加入 `CodexMultitaskIsland.swift`，模型价格加入 `QuotaViewFigmaMenu.swift` 中的既有成本模型。
- 请求 ID 使用发行基线的 `IslandApprovalJSON`，Claude 标题在适配入口生成；不迁入审计版请求语义改写。
- Claude 通道目录由 `ClaudeCodeChannel` 独立解析，已安装 Claude helper 的 stable/dev 路径不变；Codex 通道维持发行基线。
- 设置页适配当前顶部导航与状态页头，保留所有原设置项。
- 原状态栏备份只在设置写入成功后删除，修订冲突重试不会丢失恢复内容；socket 失败不会再被“已配置”覆盖。

上方旧验证结果只属于原适配工作区，不能作为此合并候选的验证结果。
迁入阶段源码/工程引用、补丁空白与 plist 核验通过；Core、WidgetContract、HookSupport、Hook、App 的 arm64/macOS 14 编译器检查通过。迁入测试文件仅做类型检查且通过，该阶段未执行测试、链接/构建应用或修改真实 Claude 配置。

随后用户明确要求开启新版：2026-10-07 14:14（Asia/Shanghai）Debug arm64 最小开发编译成功，已启动本工作区 `.build/Development075Build3/Build/Products/Debug/QuotaView.app`（PID 14296），旧 Opus 开发进程 84585 正常退出。版本仍为 0.7.7 / Build 1 / 内部 57；身份 `com.quotaview.development073`。未执行测试、发布打包或签名，未手动调整连接设置；本地合入源码未推送。编译日志与运行证据见 `.build/claude-integration-20261007/development-build.log` / `development-runtime.json`。启动存活只证明应用已运行，真实 Claude/Codex 交互仍由用户验收。

## 设置页合并 · 2026-10-07

Codex 与 Claude Code 合并为一个“连接 / Connections”导航入口；页头各自显示实时状态，下方按服务分组复用完整设置。Claude 运行时仍单独观察，禁用、失败与等待事件状态独立，不合并开关或修改连接/审批机制。开发运行与验收记录见 Handoff。
