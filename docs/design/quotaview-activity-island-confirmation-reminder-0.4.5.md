# QuotaView 0.4.5 灵动岛等待确认提醒

> Spec ID：`QV-PRODUCT-ACTIVITY-ISLAND-CONFIRMATION-REMINDER-014`
>
> 状态：`Accepted / Released`
>
> 目标版本：`0.4.5 Build 1`（Sparkle 内部 Build `17`）

## 1. 决策

Codex 任务进入真实“等待确认”或“等待用户输入”状态后，前 10 秒继续使用
既有橙黄色状态表现；持续等待满 10 秒时，灵动岛增加黄色静态高光描边和
四周黄色光晕，提示用户当前任务需要处理。

## 2. Requirement

| ID | Requirement |
|---|---|
| `CONFIRM-REMINDER-01` | 只接受投影为 `awaitingConfirmation` 的真实 `PermissionRequest`、`waitingOnApproval` 或 `waitingOnUserInput` 状态，不从普通运行、Goal、超时或 Token 停滞推断确认状态 |
| `CONFIRM-REMINDER-02` | 从真实等待事件的 `occurredAt` 开始计时，持续满 `10 s` 才激活；恢复时若事件已超过门槛则立即激活 |
| `CONFIRM-REMINDER-03` | 同一 session/turn 的重复等待通知不得重置计时；离开等待状态、切换任务、完成、中断、失败、隐藏或停止 Store 时立即取消计时和提醒 |
| `CONFIRM-REMINDER-04` | 激活后使用现有风险黄色 `#FFCC00` 绘制 `1 pt` 静态完整描边，并在岛体图层后方产生四周黄色光晕；不得增加沿边缘移动的高光点或流光 |
| `CONFIRM-REMINDER-05` | 黄色提醒复用现有完成光晕的几何、层级与呼吸节奏，不改变岛体、进度效果、文字、尺寸、悬停透明或生命周期 |
| `CONFIRM-REMINDER-06` | 开启 Reduce Motion 时保留静态黄色描边和静态黄色光晕，停止呼吸动画；提醒不新增设置项或持久化键 |
| `CONFIRM-REMINDER-07` | 完成态继续使用既有紫蓝青描边和光晕；等待提醒与完成反馈必须互斥，不能串色或覆盖真实完成语义 |

## 3. 实现边界

- `CodexActivityStore` 保存等待 session/turn 上下文并管理单一可取消计时任务。
- 计时器只发布布尔提醒状态，不改变 `CodexActivityVisualState`、进度或操作文案。
- 描边与光晕复用现有外部叠层，通过边缘强调语义切换颜色；黄色模式保持
  静态描边，只有外部光晕可呼吸。
- 状态文字已经明确“等待确认/等待输入”，颜色不是唯一的信息载体。

## 4. 验证

1. 单元测试固定生产门槛为 `10 s`，并用缩短门槛验证持续等待后激活、离开
   等待后立即清除。
2. 契约测试确认未到门槛无边缘强调、超时等待使用黄色强调、完成态仍使用
   原紫蓝青强调，风险黄色来源保持一致。
3. 运行 `swift test`、Universal Release 无签名构建，并核对版本、架构、
   资源、ad-hoc 签名和干净副本启动。
4. 黄色描边亮度、光晕范围和提醒强度由产品所有者运行真实确认任务验收。

## 5. 当前验证

- `swift test`：130 项通过、0 失败；包含门槛、激活、撤销、强调互斥和颜色
  复用测试。
- Universal Release 无签名构建通过；App、Core、Widget 与 Activity Hook
  均为 `x86_64 arm64`，版本为 `0.4.5 Build 1` / internal `17`，资源与
  干净副本的 ad-hoc 严格签名校验通过。
- 干净临时副本已以 PID `80828` 启动；开发 ZIP SHA-256 为
  `fc247a259f9f25f6f405bccbd5308ad1582667ff7bfa55ec34a77c635c99c297`。
- 25 秒端到端状态测试两次完成：确认态分别保持 16 秒，均跨过 10 秒提醒
  门槛，随后切换运行态并以 `Stop` 自然结束；对应事件被正式状态机接收。
- 产品所有者已批准包含本提醒效果的 0.4.5 候选发布；完整 Reduce Motion 与
  辅助功能交叉矩阵不作为本次发布的已验证结论。
- 本规格已随 `v0.4.5-build.1` 正式发布。
