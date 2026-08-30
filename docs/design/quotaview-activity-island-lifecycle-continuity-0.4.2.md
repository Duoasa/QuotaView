# QuotaView 0.4.2 灵动岛任务连续性修正规格

> Spec ID：`QV-PRODUCT-ACTIVITY-ISLAND-LIFECYCLE-008`
>
> 状态：`Accepted / Released`
>
> 日期：2026-08-30
>
> 生产基线：`0.4.1 Build 1`

## 问题与根因

0.4.1 为避免缺失 `Stop` 时岛体永久停留，把 `PostToolUse`、`PostCompact`
和 `SubagentStop` 后连续 20 秒无新事件解释为可以隐藏。这三个事件实际只
结束局部阶段，不证明整轮任务结束。任务在长时间思考、等待下一步工具或
主 Agent 汇总期间超过 20 秒没有 Hook 时，岛体会误进 `.hidden`；下一条
真实活动事件又会重新展开，形成“任务中消失、过一会重新出现”。

第一轮修正移除了实时局部结束事件的 20 秒隐藏计时，但仍把“摄入时已经
超过 20 秒”直接解释为启动重放。事件年龄不是投递来源：应用休眠、主线程
阻塞或文件队列积压都可能让实时事件延迟到达，因此该判断仍可能误隐藏活动
任务。

同时，当前 Store 用最后一个 Hook 事件同时表达任务生命周期和局部执行阶段。
`PostToolUse` 会留下“思考中 / 正在检查工具执行结果”，而渲染器只要面板可见
就持续播放动画。如果 `Stop` 未投递、未确认或被迟到事件覆盖，灵动岛就会在
任务已经结束后永久保持动画。两个现象是同一个状态建模缺陷的相反结果。

## 决策

任务生命周期、局部执行阶段和面板展示状态分开维护。实时收到的局部结束
事件不启动隐藏计时；只有真实 Hook `Stop` 可以进入 `.completed` 并触发完成
动画，`SessionEnd` 只负责立即隐藏。Codex App Server 的线程或 turn 状态只反映
持久化/查询时刻的状态，不能制造终态，也不能写入展示快照。

Unix Socket 与文件队列必须附带可去重的事件 ID；Socket 成功必须收到接收
确认，文件队列只能在 Runtime 接受事件后删除。文件桥在启动时先记录已有
文件，并把来源显式区分为 `startupReplay` 与 `liveQueue`；实时事件不得再按
墙钟年龄推断为重放。

同一会话进入完成态后形成终态锁，忽略迟到的 `PostToolUse`、`PostCompact`、
`SubagentStop` 和重复 `Stop`。新的 `UserPromptSubmit`、非 compact
`SessionStart`，以及新一轮的 `PreToolUse`、`PermissionRequest`、
`PreCompact`、`SubagentStart` 可以解除终态锁。Codex Host 不保证每轮任务都
先发 `UserPromptSubmit`，因此缺少 `turn_id` 时，新的前置活动仍可解除锁；
如果终态与迟到前置事件都带有相同 `turn_id`，则该事件属于已经完成的旧轮次，
必须忽略。终态锁不得拦截更强的 `SessionEnd`；`Stop → SessionEnd` 必须立即
隐藏。

局部步骤结束后保持 `.active`，直到收到真实 `Stop`。缺少终止真相时不得用
事件沉默、App Server 的 `idle/completed` 或上一轮持久化记录伪造任务结束。
Socket 接收确认和可持久重放的文件队列负责解决 `Stop` 的瞬时投递失败；状态
机不再用第二套推断通道补偿传输问题。动画资格由生命周期决定，不能等同于
“面板可见”。

## Requirement

| ID | Requirement |
|---|---|
| `ACTIVITY-ISLAND-LIFECYCLE-18` | 实时 `PostToolUse`、`PostCompact` 和 `SubagentStop` 后超过旧 20 秒阈值仍保持展开，不得自动进入 hidden |
| `ACTIVITY-ISLAND-LIFECYCLE-19` | 下一条活动事件更新状态但不得承担“重新打开误隐藏岛体”的补偿职责 |
| `ACTIVITY-ISLAND-LIFECYCLE-20` | 摄入时已超过 20 秒的上述旧队列事件保持 hidden，不在重启后重放视觉状态 |
| `ACTIVITY-ISLAND-LIFECYCLE-21` | `Stop` 仍按用户配置先展开、后紧凑、再隐藏；`SessionEnd` 仍立即隐藏 |
| `ACTIVITY-ISLAND-LIFECYCLE-22` | 同一轮 `Stop` 后的迟到局部结束事件仍被忽略；新一轮即使缺少 `UserPromptSubmit`，首个前置活动事件也必须正常解除终态锁 |
| `ACTIVITY-ISLAND-LIFECYCLE-23` | `startupReplay`、`liveQueue` 与 `liveSocket` 必须显式区分；事件年龄不得单独决定实时事件可见性 |
| `ACTIVITY-ISLAND-LIFECYCLE-24` | Socket 事件具有事件 ID 和接收确认；文件队列仅在 Runtime 接受后删除，重复事件幂等 |
| `ACTIVITY-ISLAND-LIFECYCLE-25` | 生命周期与局部阶段分离；终态锁不依赖单一开始 Hook，迟到尾部事件不能覆盖完成态，但新前置活动与 `SessionEnd` 必须生效 |
| `ACTIVITY-ISLAND-LIFECYCLE-26` | `PostToolUse`、`PostCompact`、`SubagentStop`、事件沉默和 App Server 状态都不得写入 `.completed`；完成态唯一来源是 Hook `Stop` |
| `ACTIVITY-ISLAND-LIFECYCLE-27` | 启动时重放的陈旧局部结束事件保持 hidden/unconfirmed，不重放视觉状态，也不伪造完成态 |
| `ACTIVITY-ISLAND-LIFECYCLE-28` | 渲染器播放资格来自生命周期与 Reduce Motion，不再由面板可见性单独决定 |
| `ACTIVITY-ISLAND-LIFECYCLE-29` | 诊断日志只记录事件类型、来源、状态机是否应用和哈希标识，不记录提示词、工具输入输出或正文；达到容量上限后必须安全滚动，不能停止记录新事件 |
| `ACTIVITY-ISLAND-LIFECYCLE-30` | 终态后相同 turn ID 的迟到前置事件不得解除锁；不同 turn ID 或缺失 turn ID 的真实前置活动仍可启动新一轮 |

## 验证

自动化必须覆盖：延迟超过旧阈值的实时事件、启动重放、事件去重与确认、
缺失或乱序 `Stop`、四步任务局部结束、终态锁、新一轮开始、相同/不同 turn
ID 的迟到前置事件和完成时序。产品所有者已确认当前真实任务表现满足发布；
完整 Reduce Motion 与辅助功能交叉矩阵未单独记录为全量通过。

2026-08-30 早期工程验证曾得到 `swift test` 108 项、0 失败；覆盖 Socket ACK、
队列接受后删除、延迟实时事件、启动重放、去重、终态锁和状态核对。但随后
的真实四步任务证明“测试通过”并不等于状态语义正确，该结论已被后续修正
取代。
Universal Xcode Release 本地 ad-hoc 构建通过，App、Widget 与 Activity Hook
均为 `x86_64 arm64`；归档解压后的严格深层签名校验通过。视觉与真实
生命周期结果仍标记为等待产品所有者验收。

同日执行 600 秒本地多状态序列，覆盖 SessionStart、UserPromptSubmit、
Pre/PostToolUse、PermissionRequest、Pre/PostCompact、SubagentStart/Stop、
Stop、迟到 PostToolUse、新一轮任务与 SessionEnd；包含 70 秒活动静默、
70 秒无法核对静默和 40 秒结束后空闲。该轮测试先后暴露了终态锁误拦截
`Stop → SessionEnd`，以及下一任务缺少 `UserPromptSubmit` 时无法解除完成态
两个边界，不记录为视觉通过。修正后使用已安装 Hook 完成 35 秒针对性序列：
迟到 `PostToolUse` 被状态机忽略，无提示提交的下一轮 `PreToolUse` 被应用，
最终 `SessionEnd` 被应用。随后真实四步任务暴露每次 `PostToolUse` 后，
App Server 瞬时返回当前 turn 的 `completed/idle`，状态机便主动制造
`.completed` 快照；真实 `Stop` 因终态锁已经建立而被记录为
`accepted_ignored`。单纯增加 turn ID 匹配无法修正这个语义错误。最终修正
删除 App Server 终态核对和合成完成路径，完成态只由真实 `Stop` 产生，并
增加四步任务及相同 turn ID 迟到前置事件回归。视觉结果等待产品所有者确认。

本次结构修正后的工程验证：`swift test` 103 项、0 失败；Universal Xcode
Release 本地 ad-hoc 构建、归档解压校验和深层签名校验通过，App、Widget 与
Activity Hook 均为 `x86_64 arm64`。本地候选已重新运行，并获产品所有者
发布批准；完整视觉与辅助功能交叉矩阵未单独记录为全量通过。正式签名、
公证与线上发布证据由
[`QV-RELEASE-0.4.2-001`](quotaview-0.4.2-release.md) 记录。

本规格已随 `0.4.2 Build 1` / `v0.4.2-build.1` 正式发布。
