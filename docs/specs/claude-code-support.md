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
- 综合「连接 / Connections」页内独立 Claude 分组：启用、岛上审批、官方用量窗口开关；与 Codex 状态分别维护。

## 非目标

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

设置页状态：已停用 / 配置中 / 等待会话（已配置，等待新会话）/ 已连接（本次运行收到事件）/ 需要处理
（写入失败、helper 缺失、socket 失败，可重试）。App 未运行时 helper 连接失败即静默退出，
Claude Code 行为不变；状态栏 helper 仍转发原状态栏输出。

## 连接设置布局（2026-10-09）

- Codex 设置参考 Claude 的简洁行布局：连接状态、目录、相关功能控件，共用状态与“连接详情”组件；不改变两者运行时能力或配置行为。
- Claude 保留启用、岛上审批与官方用量读取开关、设置文件入口。错误与重试直接放在连接行，停用清理失败时仍能重试；等待会话不会显示为已连接。
- 套餐、额度、30 天 Tokens 和成本从连接页移除，由原有用量页显示；连接页不再计算这些统计。Hook 配置说明默认折叠，实际授权与故障处理操作保持可见。
- Claude 图标已采用官网原始矢量资源，不再使用系统星号；资源与共用规则见[图标记录](../design/quotaview-provider-icons.md)。
- 本轮运行与构建证据见 [Handoff](../../HANDOFF.md)，视觉与交互由用户验收。

## 生命周期与开关

- 接受 helper 连接后清除从监听 socket 继承的非阻塞标志，以已有收发超时完成有界 JSON 读取；不能把首批数据尚未到达误判为连接关闭。此修复已随 PR #85 合入 main，并于 2026-10-08 17:05 进入开发运行包；源码/运行证据见 Handoff。
- runtime 停止后重启重新建立监听；取消未开始的配置任务，已经开始的文件事务串行完成；旧修订结果不覆盖新状态。取消用量刷新后禁止迟到回写。
- 停用清理失败显示“需要处理”与重试；完成清理才显示已停用。重新启动时按当前关闭配置移除本通道遗留项。
- 关闭审批立即撤销应答能力、无决定释放已挂起 helper，保留只读终端提醒；旧 route 迟到请求同样回退。重新开启不接管旧请求，真实工具结果/终态负责清理提醒。

## 当前验证与待办

2026-10-08 在现有 Build 2 基准上完成上述局部修复：19 项隔离冒烟、0 失败；Debug arm64 增量编译和 201 项输入核对通过，已按用户授权替换开发运行包。当前路径、版本与证据只在 [Handoff](../../HANDOFF.md) 维护。

仍需用户验收真实 Claude 会话、岛上审批与状态栏刷新，以及与其他 PermissionRequest Hook 并存的行为。隔离测试没有修改真实 Claude 配置或代答真实审批。

迁入前的构建、协议探针、15 项原测试，以及迁入后早期未执行测试的记录均属于各自阶段，见[清理前快照](../archive/maintenance-20261008/README.md)；不得覆盖本节的当前结论。
